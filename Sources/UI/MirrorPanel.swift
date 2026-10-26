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
                CameraPreview(mirror: mirror)
                    .clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
                    .opacity(mirror.state == .live ? 1 : 0)
                if mirror.state != .live {
                    VStack(spacing: 10) {
                        Image(systemName: icon).font(.system(size: 26, weight: .semibold)).foregroundStyle(.white.opacity(0.7))
                            .symbolEffect(.pulse, isActive: mirror.state == .starting)
                        Text(message).font(D.rounded(12.5, .semibold)).foregroundStyle(.white.opacity(0.75)).multilineTextAlignment(.center)
                        if mirror.state == .denied {
                            Pill(symbol: "gearshape.fill", text: "Open Settings", on: true, tint: D.amber) { mirror.openSettings() }
                        } else if case .failed = mirror.state {
                            Pill(symbol: "arrow.clockwise", text: "Try again", on: true, tint: D.amber) { mirror.retry() }
                        }
                    }
                    .padding(20)
                    .transition(.opacity)
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

/// The live camera, mirrored like a real mirror. Frames arrive as IOSurfaces and go straight into a layer.
struct CameraPreview: NSViewRepresentable {
    let mirror: MirrorCamera
    func makeNSView(context: Context) -> SurfaceView {
        let v = SurfaceView()
        mirror.onFrame = { [weak v] surface in v?.show(surface) }
        return v
    }
    func updateNSView(_ v: SurfaceView, context: Context) {
        mirror.onFrame = { [weak v] surface in v?.show(surface) }
    }
    static func dismantleNSView(_ v: SurfaceView, coordinator: ()) {}
}

/// A layer-hosting view: its own CALayer, set before wantsLayer, with one sublayer that shows the frames.
final class SurfaceView: NSView {
    private let content = CALayer()
    override init(frame: NSRect) {
        super.init(frame: frame)
        let root = CALayer()
        root.masksToBounds = true
        root.backgroundColor = NSColor.black.cgColor
        layer = root
        wantsLayer = true
        content.contentsGravity = .resizeAspectFill
        content.setAffineTransform(CGAffineTransform(scaleX: -1, y: 1))     // a mirror, not a camera
        root.addSublayer(content)
    }
    required init?(coder: NSCoder) { fatalError() }
    override func layout() {
        super.layout()
        CATransaction.begin(); CATransaction.setDisableActions(true)
        content.bounds = bounds
        content.position = CGPoint(x: bounds.midX, y: bounds.midY)
        CATransaction.commit()
    }
    func show(_ surface: IOSurface) {
        CATransaction.begin(); CATransaction.setDisableActions(true)
        content.contents = surface
        CATransaction.commit()
    }
}
