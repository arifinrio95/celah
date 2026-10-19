import SwiftUI

/// Qur'an: one verse on parchment with a faint eight-point star lattice; pages turn when you move on.
struct QuranView: View {
    @EnvironmentObject var quran: QuranStore
    @State private var forward = true

    var body: some View {
        let p = D.p
        Card(title: "Qur'an", glyph: "book.closed.fill", meta: meta, metaAction: { (NSApp.delegate as? AppDelegate)?.openQuran() },
             tint: Color(hex: 0x2F8F6B), background: AnyView(parchment)) {
            if let ay = quran.current {
                Spacer(minLength: 6)
                ZStack {
                    ScrollView(.vertical, showsIndicators: false) {
                        VStack(alignment: .trailing, spacing: 6) {
                            Text(ay.arabic)
                                .font(.custom("Amiri Quran", size: ay.arabic.count > 160 ? 17 : 20))
                                .foregroundStyle(p.ink)
                                .lineSpacing(6)
                                .multilineTextAlignment(.trailing)
                                .frame(maxWidth: .infinity, alignment: .trailing)
                                .environment(\.layoutDirection, .rightToLeft)
                                .fixedSize(horizontal: false, vertical: true)
                            Text(ay.translation)
                                .font(D.serif(11.5).italic())
                                .foregroundStyle(p.ink2)
                                .lineSpacing(1.5)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .padding(.bottom, 10)
                    }
                    .mask(LinearGradient(stops: [.init(color: .black, location: 0), .init(color: .black, location: 0.82), .init(color: .clear, location: 1)],
                                         startPoint: .top, endPoint: .bottom))
                    .id(quran.index)
                    .transition(.asymmetric(insertion: .pageTurn(forward ? 1 : -1), removal: .opacity.animation(.easeOut(duration: 0.12))))
                }
                .animation(.spring(response: 0.55, dampingFraction: 0.82), value: quran.index)
                .frame(maxHeight: .infinity, alignment: .top)
                HStack(spacing: 8) {
                    Orb(symbol: "chevron.left", size: 24) { forward = false; quran.prev() }
                    Orb(symbol: "chevron.right", size: 24, filled: true, tint: Color(hex: 0x2F8F6B)) { forward = true; quran.next() }
                    Orb(symbol: "arrow.up.left.and.arrow.down.right", size: 24) { (NSApp.delegate as? AppDelegate)?.openQuran() }
                        .help("Mushaf Mode: read on the big screen")
                    Spacer()
                    ZStack {
                        Image(systemName: "seal").font(.system(size: 22, weight: .light)).foregroundStyle(Color(hex: 0x2F8F6B).opacity(0.7))
                        Text(verbatim: "\(quran.current?.number ?? 0)").font(D.rounded(8.5, .heavy)).foregroundStyle(p.ink2)
                    }
                    VStack(alignment: .trailing, spacing: 3) {
                        Text(verbatim: "\(quran.index + 1) / \(quran.count)").font(D.rounded(9.5, .semibold)).monospacedDigit().foregroundStyle(p.ink3)
                        GeometryReader { g in
                            ZStack(alignment: .leading) {
                                Capsule().fill(p.track)
                                Capsule().fill(Color(hex: 0x2F8F6B)).frame(width: max(3, g.size.width * Double(quran.index + 1) / Double(max(1, quran.count))))
                            }
                        }
                        .frame(width: 70, height: 3)
                    }
                }
            } else {
                Text("Opening the mushaf…").font(D.serif(13).italic()).foregroundStyle(p.ink3)
                Spacer(minLength: 0)
            }
        }
    }

    private var meta: String? {
        guard let ay = quran.current, let s = quran.currentSurah else { return nil }
        return "\(s.latin) · \(ay.surah):\(ay.number)"
    }

    private var parchment: some View {
        ZStack {
            LinearGradient(colors: D.p.dark ? [Color(hex: 0x1C2621), Color(hex: 0x15191A)] : [Color(hex: 0xF8F1E1), Color(hex: 0xF3E9D2)],
                           startPoint: .top, endPoint: .bottom)
            StarLattice().stroke(Color(hex: D.p.dark ? 0x7FD1AE : 0x8A6A2E).opacity(D.p.dark ? 0.08 : 0.10), lineWidth: 0.7)
        }
    }
}

/// Eight-point stars on a square lattice.
struct StarLattice: Shape {
    var cell: CGFloat = 34
    func path(in r: CGRect) -> Path {
        var p = Path()
        let k = cell / 2
        var y = r.minY
        while y < r.maxY + cell {
            var x = r.minX
            while x < r.maxX + cell {
                let c = CGPoint(x: x, y: y)
                for a in [0.0, Double.pi / 4] {
                    var sq = Path()
                    for i in 0..<4 {
                        let t: Double = a + Double(i) * Double.pi / 2
                        let q = CGPoint(x: c.x + CGFloat(cos(t)) * k * 0.62, y: c.y + CGFloat(sin(t)) * k * 0.62)
                        i == 0 ? sq.move(to: q) : sq.addLine(to: q)
                    }
                    sq.closeSubpath(); p.addPath(sq)
                }
                x += cell
            }
            y += cell
        }
        return p
    }
}

/// A page turning in from one side.
struct PageTurn: ViewModifier {
    let angle: Double
    func body(content: Content) -> some View {
        content
            .rotation3DEffect(.degrees(angle), axis: (x: 0, y: 1, z: 0), anchor: angle > 0 ? .leading : .trailing, perspective: 0.6)
            .opacity(abs(angle) > 60 ? 0 : 1)
    }
}
extension AnyTransition {
    static func pageTurn(_ dir: Double) -> AnyTransition {
        .modifier(active: PageTurn(angle: -75 * dir), identity: PageTurn(angle: 0))
    }
}
