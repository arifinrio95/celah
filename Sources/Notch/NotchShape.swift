import SwiftUI

/// The notch outline: concave "ears" that blend into the top edge, rounded bottom corners.
/// Ears are drawn outside the rect so the surrounding window must leave room for them.
struct NotchShape: Shape {
    var ear: CGFloat
    var bottomRadius: CGFloat

    var animatableData: AnimatablePair<CGFloat, CGFloat> {
        get { AnimatablePair(ear, bottomRadius) }
        set { ear = newValue.first; bottomRadius = newValue.second }
    }

    func path(in r: CGRect) -> Path {
        var p = Path()
        let e = max(0, ear)
        let rad = min(bottomRadius, r.height / 2, r.width / 2)
        p.move(to: CGPoint(x: r.minX - e, y: r.minY))
        p.addQuadCurve(to: CGPoint(x: r.minX, y: r.minY + e), control: CGPoint(x: r.minX, y: r.minY))
        p.addLine(to: CGPoint(x: r.minX, y: r.maxY - rad))
        p.addArc(tangent1End: CGPoint(x: r.minX, y: r.maxY), tangent2End: CGPoint(x: r.minX + rad, y: r.maxY), radius: rad)
        p.addLine(to: CGPoint(x: r.maxX - rad, y: r.maxY))
        p.addArc(tangent1End: CGPoint(x: r.maxX, y: r.maxY), tangent2End: CGPoint(x: r.maxX, y: r.maxY - rad), radius: rad)
        p.addLine(to: CGPoint(x: r.maxX, y: r.minY + e))
        p.addQuadCurve(to: CGPoint(x: r.maxX + e, y: r.minY), control: CGPoint(x: r.maxX, y: r.minY))
        p.closeSubpath()
        return p
    }
}
