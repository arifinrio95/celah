import AppKit
import AVFoundation
import CoreMedia
import Combine
import ScreenCaptureKit
import UserNotifications

/// Writes one audio source to an AAC .m4a file. Each writer is only used from one thread.
final class AudioTrackWriter {
    private let url: URL
    private var file: AVAudioFile?
    private var converter: AVAudioConverter?

    init(url: URL) { self.url = url }

    func append(_ buffer: AVAudioPCMBuffer) {
        if file == nil {
            let settings: [String: Any] = [
                AVFormatIDKey: kAudioFormatMPEG4AAC,
                AVSampleRateKey: buffer.format.sampleRate,
                AVNumberOfChannelsKey: buffer.format.channelCount,
                AVEncoderBitRateKey: 128_000,
            ]
            do {
                file = try AVAudioFile(forWriting: url, settings: settings, commonFormat: .pcmFormatFloat32, interleaved: false)
            } catch {
                Log.write("recording: cannot create \(url.lastPathComponent): \(error.localizedDescription)")
                return
            }
        }
        guard let file else { return }
        let target = file.processingFormat
        let out: AVAudioPCMBuffer
        if buffer.format == target {
            out = buffer
        } else {
            if converter == nil || converter?.inputFormat != buffer.format {
                converter = AVAudioConverter(from: buffer.format, to: target)
            }
            guard let converter, let converted = AVAudioPCMBuffer(pcmFormat: target, frameCapacity: buffer.frameLength) else { return }
            var fed = false
            var error: NSError?
            let status = converter.convert(to: converted, error: &error) { _, inputStatus in
                if fed { inputStatus.pointee = .noDataNow; return nil }
                fed = true
                inputStatus.pointee = .haveData
                return buffer
            }
            guard status != .error, error == nil else { return }
            out = converted
        }
        do { try file.write(from: out) } catch { Log.write("recording: write failed: \(error.localizedDescription)") }
    }

    func close() {
        file = nil
        converter = nil
    }
}

/// Records the meeting: system audio (what the other people say) and the microphone (what you say).
/// Saves two files per meeting in ~/Celah Meetings/<date time> Meeting/.
/// Not under ~/Documents on purpose: that folder is privacy-protected, so every rebuild of an ad-hoc signed
/// app re-asks for access, and an unanswered (often invisible) prompt blocks whatever thread touches it.
final class MeetingRecorder: NSObject, ObservableObject, SCStreamOutput, SCStreamDelegate {
    @Published private(set) var isRecording = false
    @Published private(set) var startedAt: Date?

    static let root: URL = {
        let dir = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Celah Meetings", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }()

    private static let stampFormat: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd HH.mm"
        return f
    }()

    private var stream: SCStream?
    private var engine: AVAudioEngine?
    private var systemWriter: AudioTrackWriter?
    private var micWriter: AudioTrackWriter?
    private let systemQueue = DispatchQueue(label: "id.datasans.celah.recording.system")
    private var starting = false

    func toggle() {
        isRecording ? stop() : start()
    }

    func start() {
        guard !isRecording, !starting else { return }
        starting = true
        Task { [weak self] in
            await self?.startCapture()
            self?.starting = false
        }
    }

    private func startCapture() async {
        guard CGPreflightScreenCaptureAccess() || CGRequestScreenCaptureAccess() else {
            notify("Allow Screen Recording for Celah in System Settings, then press Record again.")
            return
        }
        guard await AVCaptureDevice.requestAccess(for: .audio) else {
            notify("Allow Microphone for Celah in System Settings, then press Record again.")
            return
        }

        let dir = Self.root.appendingPathComponent("\(Self.stampFormat.string(from: Date())) Meeting", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let micTrack = AudioTrackWriter(url: dir.appendingPathComponent("mic.m4a"))
        let sysTrack = AudioTrackWriter(url: dir.appendingPathComponent("system.m4a"))

        // Microphone
        let eng = AVAudioEngine()
        let input = eng.inputNode
        let format = input.outputFormat(forBus: 0)
        guard format.sampleRate > 0 else {
            notify("No microphone input found.")
            return
        }
        input.installTap(onBus: 0, bufferSize: 4096, format: format) { buffer, _ in micTrack.append(buffer) }
        do {
            try eng.start()
        } catch {
            input.removeTap(onBus: 0)
            notify("Microphone failed: \(error.localizedDescription)")
            return
        }
        engine = eng
        micWriter = micTrack

        // System audio. If this fails, the meeting still records the microphone.
        do {
            let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
            guard let display = content.displays.first else {
                throw NSError(domain: "Celah", code: 1, userInfo: [NSLocalizedDescriptionKey: "No display found"])
            }
            let config = SCStreamConfiguration()
            config.capturesAudio = true
            config.excludesCurrentProcessAudio = true
            config.sampleRate = 48_000
            config.channelCount = 2
            config.width = 2
            config.height = 2
            config.minimumFrameInterval = CMTime(value: 1, timescale: 1)
            let s = SCStream(filter: SCContentFilter(display: display, excludingWindows: []), configuration: config, delegate: self)
            try s.addStreamOutput(self, type: .audio, sampleHandlerQueue: systemQueue)
            systemQueue.sync { systemWriter = sysTrack }
            try await s.startCapture()
            stream = s
        } catch {
            notify("System audio not recorded, only your microphone: \(error.localizedDescription)")
        }

        DispatchQueue.main.async {
            self.startedAt = Date()
            self.isRecording = true
        }
        Log.write("recording started: \(dir.lastPathComponent)")
    }

    func stop() {
        guard isRecording else { return }
        isRecording = false
        startedAt = nil
        if let eng = engine {
            eng.inputNode.removeTap(onBus: 0)
            eng.stop()
        }
        engine = nil
        micWriter?.close()
        micWriter = nil
        systemQueue.sync {
            systemWriter?.close()
            systemWriter = nil
        }
        let s = stream
        stream = nil
        Task { try? await s?.stopCapture() }
        Log.write("recording stopped")
        notify("Recording saved in Celah Meetings.")
    }

    func openFolder() {
        NSWorkspace.shared.open(Self.root)
    }

    /// Called on quit so that files are closed cleanly.
    func shutdown() {
        if isRecording { stop() }
    }

    // MARK: - SCStream

    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard type == .audio, let pcm = Self.pcm(from: sampleBuffer) else { return }
        systemWriter?.append(pcm)
    }

    func stream(_ stream: SCStream, didStopWithError error: Error) {
        Log.write("system audio stopped: \(error.localizedDescription)")
        DispatchQueue.main.async {
            if self.isRecording { self.notify("System audio stopped. Your microphone is still recording.") }
        }
    }

    private static func pcm(from sampleBuffer: CMSampleBuffer) -> AVAudioPCMBuffer? {
        guard let desc = CMSampleBufferGetFormatDescription(sampleBuffer),
              let basicPtr = CMAudioFormatDescriptionGetStreamBasicDescription(desc) else { return nil }
        var asbd = basicPtr.pointee
        guard let format = AVAudioFormat(streamDescription: &asbd) else { return nil }
        let frames = AVAudioFrameCount(CMSampleBufferGetNumSamples(sampleBuffer))
        guard frames > 0, let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames) else { return nil }
        buffer.frameLength = frames
        let status = CMSampleBufferCopyPCMDataIntoAudioBufferList(sampleBuffer, at: 0, frameCount: Int32(frames),
                                                                  into: buffer.mutableAudioBufferList)
        return status == noErr ? buffer : nil
    }

    private func notify(_ text: String) {
        let content = UNMutableNotificationContent()
        content.title = "Celah Recording"
        content.body = text
        UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil))
    }
}
