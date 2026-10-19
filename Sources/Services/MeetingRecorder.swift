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
    /// True between the click and the first buffer, so the button can show it is working.
    @Published private(set) var isStarting = false
    /// Something the user should see on the board (a missing permission, a failure). Cleared by the user or a timer.
    @Published var notice: Notice?

    struct Notice: Equatable {
        let text: String
        var settingsPane: String? = nil          // x-apple.systempreferences anchor, e.g. "Privacy_Microphone"
        var isError = true
    }

    /// Shows a notice on the board (and posts a notification as a backup, in case the board is closed).
    private func show(_ n: Notice) {
        DispatchQueue.main.async {
            self.notice = n
            let shown = n
            DispatchQueue.main.asyncAfter(deadline: .now() + 9) { if self.notice == shown { self.notice = nil } }
        }
        notify(n.text)
    }

    func openSettings(_ pane: String) {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?\(pane)") { NSWorkspace.shared.open(url) }
    }

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

    func toggle() {
        isRecording ? stop() : start()
    }

    func start() {
        guard !isRecording, !isStarting else { return }
        isStarting = true
        notice = nil
        Log.write("record pressed")
        Task { [weak self] in
            await self?.startCapture()
            DispatchQueue.main.async { self?.isStarting = false }
        }
    }

    private func startCapture() async {
        // The microphone is required. System audio (the other side of the call) needs Screen Recording;
        // without it we still record the microphone and say so, instead of silently doing nothing.
        guard await AVCaptureDevice.requestAccess(for: .audio) else {
            Log.write("record: microphone not allowed")
            show(Notice(text: "Celah needs Microphone access to record. Turn it on, then press Record again.", settingsPane: "Privacy_Microphone"))
            return
        }
        let canCaptureSystem = CGPreflightScreenCaptureAccess() || CGRequestScreenCaptureAccess()
        if !canCaptureSystem { Log.write("record: screen recording not allowed, microphone only") }

        let dir = Self.root.appendingPathComponent("\(Self.stampFormat.string(from: Date())) Meeting", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let micTrack = AudioTrackWriter(url: dir.appendingPathComponent("mic.m4a"))
        let sysTrack = AudioTrackWriter(url: dir.appendingPathComponent("system.m4a"))

        // Microphone
        let eng = AVAudioEngine()
        let input = eng.inputNode
        let format = input.outputFormat(forBus: 0)
        guard format.sampleRate > 0 else {
            show(Notice(text: "No microphone input found."))
            return
        }
        input.installTap(onBus: 0, bufferSize: 4096, format: format) { buffer, _ in micTrack.append(buffer) }
        do {
            try eng.start()
        } catch {
            input.removeTap(onBus: 0)
            show(Notice(text: "The microphone could not start: \(error.localizedDescription)"))
            return
        }
        engine = eng
        micWriter = micTrack

        // System audio. If this fails, the meeting still records the microphone.
        if canCaptureSystem { do {
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
            show(Notice(text: "Recording your microphone only. System audio failed: \(error.localizedDescription)", isError: false))
        } } else {
            show(Notice(text: "Recording your microphone only. Allow Screen Recording to also capture the other side of the call.",
                        settingsPane: "Privacy_ScreenCapture", isError: false))
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
