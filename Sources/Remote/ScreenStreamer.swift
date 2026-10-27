import Foundation
import ScreenCaptureKit
import CoreImage
import CoreMedia
import AppKit

/// Captures the main display with ScreenCaptureKit and hands out JPEG frames on demand.
/// Frames are only encoded when a phone has drawn the previous one (back-pressure), so a slow 4G link gets fewer,
/// fresher frames instead of a growing backlog.
final class ScreenStreamer: NSObject, SCStreamOutput, SCStreamDelegate {
    private var stream: SCStream?
    private let queue = DispatchQueue(label: "id.datasans.celah.remote.screen")
    private let ci = CIContext(options: [.cacheIntermediates: false])
    private var latest: CVPixelBuffer?
    private(set) var seq = 0
    private var encodedSeq = -1
    private var encoded: (Data, Int)?
    /// Display geometry in global points (CGEvent space).
    private(set) var displayBounds = CGRect(x: 0, y: 0, width: 1440, height: 900)
    var onFrameReady: () -> Void = {}
    var onError: (String) -> Void = { _ in }
    var quality: CGFloat = 0.5
    var maxWidth = 1280

    var isRunning: Bool { stream != nil }

    func start() {
        guard stream == nil else { return }
        Task {
            do {
                let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
                let main = CGMainDisplayID()
                guard let display = content.displays.first(where: { $0.displayID == main }) ?? content.displays.first else {
                    onError("No display to share."); return
                }
                displayBounds = CGDisplayBounds(display.displayID)
                let cfg = SCStreamConfiguration()
                let scale = min(1, Double(maxWidth) / Double(display.width))
                cfg.width = Int(Double(display.width) * scale * 2) / 2
                cfg.height = Int(Double(display.height) * scale * 2) / 2
                cfg.pixelFormat = kCVPixelFormatType_32BGRA
                cfg.minimumFrameInterval = CMTime(value: 1, timescale: 15)
                cfg.queueDepth = 3
                cfg.showsCursor = true
                let s = SCStream(filter: SCContentFilter(display: display, excludingWindows: []), configuration: cfg, delegate: self)
                try s.addStreamOutput(self, type: .screen, sampleHandlerQueue: queue)
                try await s.startCapture()
                stream = s
                Log.write("remote: screen capture \(cfg.width)×\(cfg.height)")
            } catch {
                Log.write("remote: screen capture failed \(error.localizedDescription)")
                onError("This Mac isn't letting Celah share the screen yet. On the Mac, open the phone button on Celah's board and follow the Screen Recording hint.")
            }
        }
    }

    func stop() {
        let s = stream; stream = nil
        Task { try? await s?.stopCapture() }
        queue.async { self.latest = nil; self.encoded = nil }
    }

    func stream(_ stream: SCStream, didOutputSampleBuffer sb: CMSampleBuffer, of type: SCStreamOutputType) {
        guard type == .screen, let pb = CMSampleBufferGetImageBuffer(sb) else { return }
        // skip "idle" buffers: SCK sends them when nothing changed
        if let att = CMSampleBufferGetSampleAttachmentsArray(sb, createIfNecessary: false) as? [[SCStreamFrameInfo: Any]],
           let raw = att.first?[.status] as? Int, let status = SCFrameStatus(rawValue: raw), status != .complete { return }
        latest = pb
        seq += 1
        onFrameReady()
    }

    func stream(_ stream: SCStream, didStopWithError error: Error) {
        Log.write("remote: capture stopped \(error.localizedDescription)")
        self.stream = nil
    }

    /// The newest frame as JPEG, encoded at most once per captured frame. Call on any queue.
    func jpeg() -> (Data, Int)? {
        queue.sync {
            if encodedSeq == seq, let e = encoded { return e }
            guard let pb = latest else { return nil }
            let img = CIImage(cvPixelBuffer: pb)
            guard let cs = CGColorSpace(name: CGColorSpace.sRGB),
                  let data = ci.jpegRepresentation(of: img, colorSpace: cs,
                                                   options: [CIImageRepresentationOption(rawValue: kCGImageDestinationLossyCompressionQuality as String): quality]) else { return nil }
            encoded = (data, seq); encodedSeq = seq
            return encoded
        }
    }
}
