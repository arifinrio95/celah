import SwiftUI
import AVFoundation
import AppKit

/// A mirror under the notch. Optional ring light: the tray's edge glows white to light your face.
struct MirrorPanel: View {
    @ObservedObject var ctl: NotchController
    @EnvironmentObject var mirror: MirrorCamera

    var body: some View {
        let p = D.p
        VStack(spacing: 12) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("Mirror").font(D.serif(20).italic()).foregroundStyle(p.ink)
                Text(status).font(D.rounded(11.5, .semibold)).foregroundStyle(p.ink3)
                Spacer()
                Pill(symbol: mirror.ringLight ? "sun.max.fill" : "sun.max", text: "Ring light", on: mirror.ringLight, tint: D.amber) {
                    withAnimation(.easeInOut(duration: 0.35)) { mirror.ringLight.toggle() }
                }
                Orb(symbol: "xmark", size: 24) { mirror.panelOpen = false }
            }
            ZStack {
                RoundedRectangle(cornerRadius: 26, style: .continuous).fill(Color.black)
                if mirror.state == .live {
                    CameraPreview(session: mirror.session)
                        .clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
                        .transition(.opacity)
                } else {
                    VStack(spacing: 10) {
                        Image(systemName: icon).font(.system(size: 26, weight: .semibold)).foregroundStyle(.white.opacity(0.7))
                        Text(message).font(D.rounded(12.5, .semibold)).foregroundStyle(.white.opacity(0.75)).multilineTextAlignment(.center)
                        if mirror.state == .denied {
                            Pill(symbol: "gearshape.fill", text: "Open Settings", on: true, tint: D.amber) { mirror.openSettings() }
                        }
                    }
                    .padding(20)
                }
                // a ring light: soft white glow around the picture
                RoundedRectangle(cornerRadius: 26, style: .continuous)
                    .strokeBorder(Color.white.opacity(mirror.ringLight ? 0.95 : 0), lineWidth: mirror.ringLight ? 10 : 0)
                    .shadow(color: .white.opacity(mirror.ringLight ? 0.9 : 0), radius: 22)
            }
            .aspectRatio(16 / 10, contentMode: .fit)
            .frame(maxWidth: .infinity)
            .animation(.easeInOut(duration: 0.3), value: mirror.state)
        }
        .padding(16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(mirror.ringLight ? Color.white : p.card)
                .shadow(color: mirror.ringLight ? .white.opacity(0.9) : p.cardShadow, radius: mirror.ringLight ? 30 : 18, y: mirror.ringLight ? 0 : 10)
        }
        .onAppear { ctl.cheer(.happy, for: 1.4) }
    }

    private var status: String {
        switch mirror.state {
        case .live: return "you look great"
        case .starting: return "waking the camera…"
        default: return "camera off"
        }
    }
    private var icon: String {
        switch mirror.state {
        case .denied: return "video.slash.fill"
        case .noCamera: return "camera.badge.ellipsis"
        case .failed: return "exclamationmark.triangle.fill"
        default: return "camera.fill"
        }
    }
    private var message: String {
        switch mirror.state {
        case .denied: return "Celah needs Camera access to be a mirror."
        case .noCamera: return "No camera found."
        case .failed(let e): return "The camera could not start: \(e)"
        default: return "Waking the camera…"
        }
    }
}

/// The live camera, mirrored like a real mirror.
struct CameraPreview: NSViewRepresentable {
    let session: AVCaptureSession
    func makeNSView(context: Context) -> NSView {
        let v = NSView()
        v.wantsLayer = true
        let layer = AVCaptureVideoPreviewLayer(session: session)
        layer.videoGravity = .resizeAspectFill
        if let c = layer.connection, c.isVideoMirroringSupported { c.automaticallyAdjustsVideoMirroring = false; c.isVideoMirrored = true }
        layer.autoresizingMask = [.layerWidthSizable, .layerHeightSizable]
        v.layer = layer
        return v
    }
    func updateNSView(_ v: NSView, context: Context) {
        if let layer = v.layer as? AVCaptureVideoPreviewLayer, let c = layer.connection, c.isVideoMirroringSupported, !c.isVideoMirrored {
            c.automaticallyAdjustsVideoMirroring = false; c.isVideoMirrored = true
        }
    }
}
