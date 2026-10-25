import AVFoundation
import AppKit
import Combine

/// The notch is where the camera lives, so Celah can be a mirror. The camera runs only while the mirror is open
/// and stops the moment it closes (or the board folds away), so the green light never stays on by accident.
final class MirrorCamera: ObservableObject {
    enum State: Equatable { case off, starting, live, denied, noCamera, failed(String) }

    @Published var panelOpen = false { didSet { panelOpen ? start() : stop() } }
    @Published private(set) var state: State = .off
    @Published var ringLight = UserDefaults.standard.bool(forKey: "mirror.ringLight") {
        didSet { UserDefaults.standard.set(ringLight, forKey: "mirror.ringLight") }
    }
    let session = AVCaptureSession()
    private let queue = DispatchQueue(label: "id.datasans.celah.mirror")
    private var configured = false

    private func start() {
        state = .starting
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized: run()
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { [weak self] ok in
                DispatchQueue.main.async { guard let self, self.panelOpen else { return }; ok ? self.run() : (self.state = .denied) }
            }
        default: state = .denied
        }
    }

    private func run() {
        queue.async { [weak self] in
            guard let self else { return }
            if !self.configured {
                guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .unspecified)
                        ?? AVCaptureDevice.default(for: .video) else {
                    DispatchQueue.main.async { self.state = .noCamera }; return
                }
                do {
                    let input = try AVCaptureDeviceInput(device: device)
                    self.session.beginConfiguration()
                    self.session.sessionPreset = .high
                    if self.session.canAddInput(input) { self.session.addInput(input) }
                    self.session.commitConfiguration()
                    self.configured = true
                } catch {
                    DispatchQueue.main.async { self.state = .failed(error.localizedDescription) }; return
                }
            }
            if !self.session.isRunning { self.session.startRunning() }
            DispatchQueue.main.async { if self.panelOpen { self.state = .live } else { self.stop() } }
        }
    }

    func stop() {
        if case .denied = state {} else { state = .off }
        queue.async { [weak self] in if self?.session.isRunning == true { self?.session.stopRunning() } }
    }

    func openSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Camera") { NSWorkspace.shared.open(url) }
    }
}
