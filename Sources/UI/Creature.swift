import SwiftUI

/// The black lip: flush with the top of the screen, concave ears at the top corners, pill-round bottom
/// corners, and a soft chin under the camera where the creature's face lives.
struct LipShape: Shape {
    var ear: CGFloat
    var radius: CGFloat
    var chinWidth: CGFloat
    var chinDepth: CGFloat
    var lipHeight: CGFloat

    var animatableData: AnimatablePair<AnimatablePair<CGFloat, CGFloat>, AnimatablePair<CGFloat, CGFloat>> {
        get { AnimatablePair(AnimatablePair(ear, radius), AnimatablePair(chinWidth, chinDepth)) }
        set { ear = newValue.first.first; radius = newValue.first.second; chinWidth = newValue.second.first; chinDepth = newValue.second.second }
    }

    func path(in r: CGRect) -> Path {
        var p = Path()
        let h = lipHeight, e = max(0, ear)
        let rad = min(radius, h / 2, r.width / 2)
        let cx = r.midX
        let cw = max(0, min(chinWidth, r.width - rad * 2 - 4)), cd = max(0, chinDepth)
        let f = min(9, cd * 0.6)                   // fillet between lip and chin
        p.move(to: CGPoint(x: r.minX - e, y: r.minY))
        p.addQuadCurve(to: CGPoint(x: r.minX, y: r.minY + e), control: CGPoint(x: r.minX, y: r.minY))
        p.addLine(to: CGPoint(x: r.minX, y: r.minY + h - rad))
        p.addArc(tangent1End: CGPoint(x: r.minX, y: r.minY + h), tangent2End: CGPoint(x: r.minX + rad, y: r.minY + h), radius: rad)
        if cd > 0.5 && cw > 4 {
            let l = cx - cw / 2, rt = cx + cw / 2, bottom = r.minY + h + cd
            let cr = min(cw / 2, cd + 2)
            p.addLine(to: CGPoint(x: l - f, y: r.minY + h))
            p.addQuadCurve(to: CGPoint(x: l, y: r.minY + h + f), control: CGPoint(x: l, y: r.minY + h))
            p.addLine(to: CGPoint(x: l, y: max(r.minY + h + f, bottom - cr)))
            p.addArc(tangent1End: CGPoint(x: l, y: bottom), tangent2End: CGPoint(x: l + cr, y: bottom), radius: cr)
            p.addLine(to: CGPoint(x: rt - cr, y: bottom))
            p.addArc(tangent1End: CGPoint(x: rt, y: bottom), tangent2End: CGPoint(x: rt, y: bottom - cr), radius: cr)
            p.addLine(to: CGPoint(x: rt, y: r.minY + h + f))
            p.addQuadCurve(to: CGPoint(x: rt + f, y: r.minY + h), control: CGPoint(x: rt, y: r.minY + h))
        }
        p.addLine(to: CGPoint(x: r.maxX - rad, y: r.minY + h))
        p.addArc(tangent1End: CGPoint(x: r.maxX, y: r.minY + h), tangent2End: CGPoint(x: r.maxX, y: r.minY + h - rad), radius: rad)
        p.addLine(to: CGPoint(x: r.maxX, y: r.minY + e))
        p.addQuadCurve(to: CGPoint(x: r.maxX + e, y: r.minY), control: CGPoint(x: r.maxX, y: r.minY))
        p.closeSubpath()
        return p
    }
}

/// Two amber eyes and a mouth. Eyes follow `look` (−1…1), blink on their own, and change with the mood.
struct CreatureFace: View {
    let mood: Mood
    let look: CGVector
    var scale: CGFloat = 1
    var awake = true

    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 30, paused: !awake)) { tl in
            let t = tl.date.timeIntervalSinceReferenceDate
            Canvas { ctx, size in
                draw(ctx: &ctx, size: size, t: t)
            }
        }
        .frame(width: 46 * scale, height: 22 * scale)
        .allowsHitTesting(false)
    }

    private func draw(ctx: inout GraphicsContext, size: CGSize, t: Double) {
        let amber = D.amber
        let s = scale
        let cx = size.width / 2 + look.dx * 2.4 * s
        let cy = size.height / 2 - 2 * s + look.dy * 1.8 * s
        let gap = 8.5 * s
        // a blink every ~3.6 s, a double blink every fourth time
        let period = mood == .wired ? 2.2 : 3.6
        let ph = t.truncatingRemainder(dividingBy: period * 4)
        let inBlink = { (x: Double) -> Bool in x.truncatingRemainder(dividingBy: period) < 0.12 }
        let blink = inBlink(ph) || (ph > period * 3 && ph < period * 3 + 0.4 && (ph - period * 3) > 0.22 && (ph - period * 3) < 0.34)
        for side in [-1.0, 1.0] {
            let ex = cx + side * gap
            switch mood {
            case .happy, .love:
                var a = Path()
                a.move(to: CGPoint(x: ex - 3.4 * s, y: cy + 1.5 * s))
                a.addQuadCurve(to: CGPoint(x: ex + 3.4 * s, y: cy + 1.5 * s), control: CGPoint(x: ex, y: cy - 4.2 * s))
                ctx.stroke(a, with: .color(amber), style: StrokeStyle(lineWidth: 2.1 * s, lineCap: .round))
            case .sleepy:
                var a = Path()
                a.move(to: CGPoint(x: ex - 3.2 * s, y: cy))
                a.addQuadCurve(to: CGPoint(x: ex + 3.2 * s, y: cy), control: CGPoint(x: ex, y: cy + 3.2 * s))
                ctx.stroke(a, with: .color(amber), style: StrokeStyle(lineWidth: 2 * s, lineCap: .round))
            default:
                let w = (mood == .wired ? 6.2 : 5.2) * s
                let h = blink ? 1.0 * s : (mood == .wired ? 8.4 : 7.2) * s
                ctx.fill(Path(roundedRect: CGRect(x: ex - w / 2, y: cy - h / 2, width: w, height: h), cornerRadius: w / 2), with: .color(amber))
                if !blink {
                    ctx.fill(Path(ellipseIn: CGRect(x: ex - w * 0.05 + look.dx * 0.6 * s, y: cy - h * 0.32, width: w * 0.36, height: w * 0.36)),
                             with: .color(.white.opacity(0.85)))
                }
                if mood == .worried {
                    var b = Path()
                    b.move(to: CGPoint(x: ex - 3.6 * s, y: cy - 6.6 * s + (side < 0 ? 1.4 : -1.4) * s * -1))
                    b.addLine(to: CGPoint(x: ex + 3.6 * s, y: cy - 6.6 * s + (side < 0 ? -1.4 : 1.4) * s * -1))
                    ctx.stroke(b, with: .color(amber.opacity(0.9)), style: StrokeStyle(lineWidth: 1.4 * s, lineCap: .round))
                }
            }
        }
        // mouth
        let my = cy + 6.6 * s
        var m = Path()
        switch mood {
        case .happy:
            m.move(to: CGPoint(x: cx - 5 * s, y: my - 1 * s))
            m.addQuadCurve(to: CGPoint(x: cx + 5 * s, y: my - 1 * s), control: CGPoint(x: cx, y: my + 5.5 * s))
            m.closeSubpath()
            ctx.fill(m, with: .color(amber))
        case .love:
            // a tiny heart instead of a mouth
            let hx = cx, hy = my + 0.6 * s, k = 2.3 * s
            m.move(to: CGPoint(x: hx, y: hy + k * 1.3))
            m.addCurve(to: CGPoint(x: hx - k * 1.6, y: hy - k * 0.3), control1: CGPoint(x: hx - k * 0.6, y: hy + k * 0.7), control2: CGPoint(x: hx - k * 1.6, y: hy + k * 0.4))
            m.addArc(center: CGPoint(x: hx - k * 0.8, y: hy - k * 0.35), radius: k * 0.8, startAngle: .degrees(180), endAngle: .degrees(0), clockwise: false)
            m.addArc(center: CGPoint(x: hx + k * 0.8, y: hy - k * 0.35), radius: k * 0.8, startAngle: .degrees(180), endAngle: .degrees(0), clockwise: false)
            m.addCurve(to: CGPoint(x: hx, y: hy + k * 1.3), control1: CGPoint(x: hx + k * 1.6, y: hy + k * 0.4), control2: CGPoint(x: hx + k * 0.6, y: hy + k * 0.7))
            ctx.fill(m, with: .color(Color(hex: 0xFF7A8A)))
        case .worried:
            m.move(to: CGPoint(x: cx - 4.5 * s, y: my + 1 * s))
            for i in 1...6 { m.addLine(to: CGPoint(x: cx - 4.5 * s + Double(i) * 1.5 * s, y: my + (i % 2 == 0 ? 1 : -0.6) * s)) }
            ctx.stroke(m, with: .color(amber), style: StrokeStyle(lineWidth: 1.4 * s, lineCap: .round, lineJoin: .round))
        case .sleepy:
            ctx.fill(Path(ellipseIn: CGRect(x: cx - 1.7 * s, y: my - 1 * s, width: 3.4 * s, height: 3.4 * s)), with: .color(amber.opacity(0.85)))
        case .wired:
            m.move(to: CGPoint(x: cx - 4 * s, y: my - 0.5 * s))
            m.addQuadCurve(to: CGPoint(x: cx + 4 * s, y: my - 0.5 * s), control: CGPoint(x: cx, y: my + 3.4 * s))
            ctx.stroke(m, with: .color(amber), style: StrokeStyle(lineWidth: 1.6 * s, lineCap: .round))
        case .neutral:
            m.move(to: CGPoint(x: cx - 3.4 * s, y: my - 0.4 * s))
            m.addQuadCurve(to: CGPoint(x: cx + 3.4 * s, y: my - 0.4 * s), control: CGPoint(x: cx, y: my + 2.6 * s))
            ctx.stroke(m, with: .color(amber), style: StrokeStyle(lineWidth: 1.5 * s, lineCap: .round))
        }
        // floating z's when sleepy
        if mood == .sleepy {
            let z = (t * 0.6).truncatingRemainder(dividingBy: 1)
            ctx.opacity = 1 - z
            ctx.draw(Text("z").font(.system(size: 6 * s + z * 3 * s, weight: .bold, design: .rounded)).foregroundColor(amber),
                     at: CGPoint(x: cx + gap + 6 * s + z * 4 * s, y: cy - 6 * s - z * 7 * s))
        }
    }
}

/// Cursor direction from a point on screen, squashed into −1…1.
func lookVector(from center: CGPoint, to mouse: CGPoint) -> CGVector {
    let dx = mouse.x - center.x, dy = center.y - mouse.y          // screen y grows upward
    let d = max(1, hypot(dx, dy))
    let k = min(1, d / 220)
    return CGVector(dx: dx / d * k, dy: max(-0.6, min(1, dy / d * k)))
}
