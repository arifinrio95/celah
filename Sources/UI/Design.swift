import SwiftUI
import AppKit

/// Design system for the notch board. Two looks share every token:
/// Porcelain (warm paper tray under the black notch) and Ink (smoked glass).
/// Legacy windows (Settings, Task Board, Meetings) keep using `Theme`.
struct Palette {
    let trayTop: Color, trayBottom: Color
    let card: Color, cardStroke: Color, cardShadow: Color
    let ink: Color, ink2: Color, ink3: Color, ink4: Color, hair: Color, track: Color
    let accent: Color, accentInk: Color
    let danger: Color, ok: Color
    let dark: Bool

    static let porcelain = Palette(
        trayTop: Color(hex: 0xF7F2EA), trayBottom: Color(hex: 0xEEE6DA),
        card: Color(hex: 0xFFFDF9), cardStroke: Color.black.opacity(0.06), cardShadow: Color(hex: 0x5B4630).opacity(0.10),
        ink: Color(hex: 0x1C1A17), ink2: Color(hex: 0x1C1A17).opacity(0.64), ink3: Color(hex: 0x1C1A17).opacity(0.42),
        ink4: Color(hex: 0x1C1A17).opacity(0.14), hair: Color(hex: 0x1C1A17).opacity(0.08), track: Color(hex: 0x1C1A17).opacity(0.07),
        accent: Color(hex: 0xE58A17), accentInk: Color(hex: 0xB86A08),
        danger: Color(hex: 0xE5484D), ok: Color(hex: 0x2E9E6B), dark: false)

    static let ink = Palette(
        trayTop: Color(hex: 0x17171B), trayBottom: Color(hex: 0x0E0E11),
        card: Color(hex: 0x202026), cardStroke: Color.white.opacity(0.07), cardShadow: Color.black.opacity(0.45),
        ink: .white, ink2: Color.white.opacity(0.66), ink3: Color.white.opacity(0.42),
        ink4: Color.white.opacity(0.16), hair: Color.white.opacity(0.08), track: Color.white.opacity(0.09),
        accent: Color(hex: 0xF5B84C), accentInk: Color(hex: 0xF5B84C),
        danger: Color(hex: 0xFF6B66), ok: Color(hex: 0x52D394), dark: true)
}

enum D {
    /// Set by the root view from settings; every board view reads it while rendering.
    static var p = Palette.porcelain

    static let lip = Color.black
    static let amber = Color(hex: 0xF5B84C)
    static let claude = Color(hex: 0xD97757)
    static let chatgpt = Color(hex: 0x10A37F)

    static func rounded(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font { .system(size: size, weight: weight, design: .rounded) }
    static func serif(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font { .system(size: size, weight: weight, design: .serif) }
    static func mono(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font { .system(size: size, weight: weight, design: .monospaced) }
    static func label(_ size: CGFloat = 9.5) -> Font { .system(size: size, weight: .bold, design: .rounded) }

    static let springIn = Animation.spring(response: 0.42, dampingFraction: 0.78)
    static let springOut = Animation.spring(response: 0.28, dampingFraction: 0.95)
    static let snappy = Animation.spring(response: 0.3, dampingFraction: 0.72)
}

extension Color {
    init(hex: UInt32, alpha: Double = 1) {
        self.init(.sRGB, red: Double((hex >> 16) & 0xFF) / 255, green: Double((hex >> 8) & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255, opacity: alpha)
    }
}

// MARK: - Card

/// A module card: soft paper, hairline edge, two-layer shadow, a small rounded label with a glyph.
struct Card<Content: View>: View {
    let title: String
    let glyph: String
    var meta: String? = nil
    var metaAction: (() -> Void)? = nil
    var tint: Color? = nil
    var background: AnyView? = nil
    @ViewBuilder var content: Content
    @State private var hoverMeta = false

    var body: some View {
        let p = D.p
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 5) {
                Image(systemName: glyph).font(.system(size: 9, weight: .bold)).foregroundStyle(tint ?? p.ink3)
                Text(title.uppercased()).font(D.label(9)).tracking(1.3).foregroundStyle(p.ink3)
                Spacer(minLength: 6)
                if let meta {
                    if let metaAction {
                        Button(action: metaAction) {
                            HStack(spacing: 3) {
                                Text(meta).font(D.rounded(9.5, .semibold))
                                Image(systemName: "arrow.up.right").font(.system(size: 7.5, weight: .heavy))
                            }
                            .foregroundStyle(hoverMeta ? p.ink : p.ink3)
                            .padding(.horizontal, 6).padding(.vertical, 2)
                            .background(Capsule().fill(hoverMeta ? p.ink4 : .clear))
                            .contentShape(Capsule())
                        }
                        .buttonStyle(.plain)
                        .onHover { hoverMeta = $0 }
                    } else {
                        Text(meta).font(D.rounded(9.5, .medium)).foregroundStyle(p.ink3).lineLimit(1)
                    }
                }
            }
            .frame(height: 16)
            content
        }
        .padding(.horizontal, 14)
        .padding(.top, 11)
        .padding(.bottom, 12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background {
            ZStack {
                RoundedRectangle(cornerRadius: 20, style: .continuous).fill(p.card)
                if let background { background.frame(maxWidth: .infinity, maxHeight: .infinity).clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous)) }
                RoundedRectangle(cornerRadius: 20, style: .continuous).strokeBorder(p.cardStroke, lineWidth: 0.75)
            }
            .shadow(color: p.cardShadow.opacity(0.6), radius: 1, y: 1)
            .shadow(color: p.cardShadow, radius: 14, y: 8)
        }
    }
}

// MARK: - Buttons

/// Round icon button that pops on press.
struct Orb: View {
    let symbol: String
    var size: CGFloat = 26
    var filled = false
    var tint: Color? = nil
    var action: () -> Void
    @State private var hover = false

    var body: some View {
        let p = D.p
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: size * 0.4, weight: .bold))
                .foregroundStyle(filled ? (p.dark ? Color.black : Color.white) : (hover ? p.ink : p.ink2))
                .frame(width: size, height: size)
                .background(Circle().fill(filled ? (tint ?? p.ink) : (hover ? p.ink4 : p.track)))
                .contentShape(Circle())
        }
        .buttonStyle(PressScale())
        .onHover { hover = $0 }
    }
}

/// Pill with a glyph and a short label; the label never wraps or hides.
struct Pill: View {
    let symbol: String
    let text: String
    var on = false
    var tint: Color? = nil
    var action: () -> Void
    @State private var hover = false

    var body: some View {
        let p = D.p
        let c = tint ?? p.accent
        Button(action: action) {
            HStack(spacing: 5) {
                Image(systemName: symbol).font(.system(size: 10, weight: .bold))
                Text(text).font(D.rounded(11, .semibold)).lineLimit(1).fixedSize()
            }
            .foregroundStyle(on ? (p.dark ? Color.black : Color.white) : (hover ? p.ink : p.ink2))
            .padding(.horizontal, 10)
            .frame(height: 26)
            .background(Capsule().fill(on ? c : (hover ? p.ink4 : p.track)))
            .contentShape(Capsule())
        }
        .buttonStyle(PressScale())
        .onHover { hover = $0 }
    }
}

struct PressScale: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.9 : 1)
            .animation(.spring(response: 0.22, dampingFraction: 0.6), value: configuration.isPressed)
    }
}

// MARK: - Jelly bar

/// A horizontal meter whose leading edge wobbles like jelly; it settles when nothing changes.
struct JellyBar: View {
    let value: Double
    let color: Color
    var height: CGFloat = 20
    var live = true

    var body: some View {
        let p = D.p
        TimelineView(.animation(minimumInterval: 1 / 30, paused: !live)) { tl in
            let t = tl.date.timeIntervalSinceReferenceDate
            Canvas { ctx, size in
                let r = size.height / 2
                let track = Path(roundedRect: CGRect(origin: .zero, size: size), cornerRadius: r)
                ctx.fill(track, with: .color(p.track))
                let v = max(0, min(1, value))
                guard v > 0.001 else { return }
                let x = max(r * 1.2, v * size.width)
                var path = Path()
                path.move(to: .zero)
                let steps = 14
                path.addLine(to: CGPoint(x: x, y: 0))
                for i in 0...steps {
                    let y = CGFloat(i) / CGFloat(steps) * size.height
                    let w = sin(t * 3.1 + Double(y) * 0.32) * 1.8 + sin(t * 1.7 + Double(y) * 0.18) * 1.2
                    path.addLine(to: CGPoint(x: x + w, y: y))
                }
                path.addLine(to: CGPoint(x: 0, y: size.height))
                path.closeSubpath()
                ctx.clip(to: track)
                ctx.fill(path, with: .linearGradient(Gradient(colors: [color.opacity(0.85), color]),
                                                     startPoint: .zero, endPoint: CGPoint(x: size.width, y: 0)))
                // glossy highlight
                ctx.fill(Path(roundedRect: CGRect(x: 4, y: 3, width: max(0, x - 10), height: size.height * 0.28), cornerRadius: 3),
                         with: .color(.white.opacity(0.28)))
            }
        }
        .frame(height: height)
        .animation(.spring(response: 0.8, dampingFraction: 0.7), value: value)
    }
}

// MARK: - Artwork colour

enum ImageTint {
    private static var cache: [ObjectIdentifier: Color] = [:]
    /// Average colour of an image, nudged toward saturation so washes do not go muddy.
    static func average(_ image: NSImage?) -> Color? {
        guard let image else { return nil }
        let key = ObjectIdentifier(image)
        if let c = cache[key] { return c }
        guard let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return nil }
        var px = [UInt8](repeating: 0, count: 4)
        guard let ctx = CGContext(data: &px, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
                                  space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        ctx.interpolationQuality = .medium
        ctx.draw(cg, in: CGRect(x: 0, y: 0, width: 1, height: 1))
        let ns = NSColor(srgbRed: CGFloat(px[0]) / 255, green: CGFloat(px[1]) / 255, blue: CGFloat(px[2]) / 255, alpha: 1)
        var h: CGFloat = 0, s: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        ns.getHue(&h, saturation: &s, brightness: &b, alpha: &a)
        let c = Color(hue: Double(h), saturation: Double(min(1, s * 1.35 + 0.08)), brightness: Double(min(0.92, max(0.45, b))))
        cache[key] = c
        return c
    }
}

// MARK: - Grain

/// Fine paper grain, generated once.
struct Grain: View {
    private static let image: NSImage = {
        let w = 256, h = 256
        var bytes = [UInt8](repeating: 0, count: w * h * 4)
        var seed: UInt32 = 2166136261
        for i in 0..<(w * h) {
            seed = seed &* 1664525 &+ 1013904223
            let v = UInt8(truncatingIfNeeded: seed >> 24)
            bytes[i * 4] = v; bytes[i * 4 + 1] = v; bytes[i * 4 + 2] = v; bytes[i * 4 + 3] = 255
        }
        let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: w, pixelsHigh: h, bitsPerSample: 8, samplesPerPixel: 4,
                                   hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: w * 4, bitsPerPixel: 32)!
        memcpy(rep.bitmapData!, bytes, bytes.count)
        let img = NSImage(size: NSSize(width: w, height: h)); img.addRepresentation(rep)
        return img
    }()
    var opacity: Double = 0.05
    var body: some View {
        Image(nsImage: Self.image).resizable(resizingMode: .tile).blendMode(.overlay).opacity(opacity).allowsHitTesting(false)
    }
}
