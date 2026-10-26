import AVFoundation
import AppKit
import Combine
import CoreVideo

/// The notch is where the camera lives, so Celah can be a mirror. The camera runs only while the mirror is open
/// and stops the moment it closes (or the board folds away), so the green light never stays on by accident.
///
/// Frames are drawn by Celah itself (an IOSurface handed straight to a layer) instead of through a preview layer,
/// and the mirror only says "live" once a real frame has arrived. If none arrives, it restarts the camera once,
/// then explains what is wrong instead of showing a black box.
final class MirrorCamera: NSObject, ObservableObject, AVCaptureVideoDataOutputSampleBufferDelegate {
    enum State: Equatable { case off, starting, live, denied, noCamera, failed(String) }

    @Published var panelOpen = false { didSet { if panelOpen != oldValue { panelOpen ? start() : stop() } } }
    @Published private(set) var state: State = .off
    @Published var ringLight = UserDefaults.standard.bool(forKey: "mirror.ringLight") {
        didSet { UserDefaults.standard.set(ringLight, forKey: "mirror.ringLight") }
    }
    /// Set by the view that shows the mirror; called on the main thread with each new frame.
    var onFrame: ((IOSurface) -> Void)?

    private let session = AVCaptureSession()
    private let output = AVCaptureVideoDataOutput()
    private let queue = DispatchQueue(label: "id.datasans.celah.mirror")
    private var configured = false
    private var generation = 0            // bumps on every start/stop so late callbacks from an old run are ignored
    private var gotFrame = false
    private var retried = false

    private func start() {
        generation += 1
        gotFrame = false; retried = false
        state = .starting
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized: run(generation)
        case .notDetermined:
            let g = generation
            AVCaptureDevice.requestAccess(for: .video) { [weak self] ok in
                DispatchQueue.main.async {
                    guard let self, self.panelOpen, g == self.generation else { return }
                    ok ? self.run(g) : (self.state = .denied)
                }
            }
        default: state = .denied
        }
    }

    private func run(_ g: Int) {
        queue.async { [weak self] in
            guard let self else { return }
            if !self.configured, let err = self.configure() {
                DispatchQueue.main.async { if g == self.generation { self.state = err } }
                return
            }
            if !self.session.isRunning { self.session.startRunning() }
            Log.write("mirror: session running=\(self.session.isRunning)")
        }
        watchdog(g)
    }

    /// No picture in 2.5 s: restart the session once; still nothing: say so.
    private func watchdog(_ g: Int) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) { [weak self] in
            guard let self, g == self.generation, self.panelOpen, !self.gotFrame else { return }
            if !self.retried {
                self.retried = true
                Log.write("mirror: no frame yet, restarting the camera")
                self.queue.async {
                    self.session.stopRunning()
                    self.session.startRunning()
                }
                self.watchdog(g)
            } else {
                Log.write("mirror: still no frame after a restart")
                self.state = .failed("No picture from the camera. Another app may be using it.")
            }
        }
    }

    private func configure() -> State? {
        let discovery = AVCaptureDevice.DiscoverySession(deviceTypes: [.builtInWideAngleCamera], mediaType: .video, position: .unspecified)
        guard let device = discovery.devices.first ?? AVCaptureDevice.default(for: .video) else { return .noCamera }
        do {
            let input = try AVCaptureDeviceInput(device: device)
            session.beginConfiguration()
            session.sessionPreset = .high
            if session.canAddInput(input) { session.addInput(input) }
            output.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
                                    kCVPixelBufferIOSurfacePropertiesKey as String: [:]]
            output.alwaysDiscardsLateVideoFrames = true
            output.setSampleBufferDelegate(self, queue: queue)
            if session.canAddOutput(output) { session.addOutput(output) }
            session.commitConfiguration()
            configured = true
            Log.write("mirror: using \(device.localizedName)")
            return nil
        } catch {
            return .failed(error.localizedDescription)
        }
    }

    func stop() {
        generation += 1
        if state != .denied { state = .off }
        queue.async { [weak self] in if self?.session.isRunning == true { self?.session.stopRunning() } }
    }

    func retry() { if panelOpen { start() } }

    // MARK: frames

    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        guard let pb = CMSampleBufferGetImageBuffer(sampleBuffer), let surface = CVPixelBufferGetIOSurface(pb)?.takeUnretainedValue() else { return }
        DispatchQueue.main.async { [weak self] in
            guard let self, self.panelOpen else { return }
            if !self.gotFrame { self.gotFrame = true; self.state = .live; Log.write("mirror: first frame") }
            self.onFrame?(surface)
        }
    }

    func openSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Camera") { NSWorkspace.shared.open(url) }
    }
}
