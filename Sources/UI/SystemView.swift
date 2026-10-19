import SwiftUI

/// System: three nested rings (CPU, RAM, Storage) and their readings.
struct SystemView: View {
    @EnvironmentObject var stats: SystemStats

    static let cpuColor = Color(hex: 0xF5A524), ramColor = Color(hex: 0xE5735A), diskColor = Color(hex: 0x3AA7A0)

    var body: some View {
        let p = D.p
        let mem = stats.memTotal > 0 ? Double(stats.memUsed) / Double(stats.memTotal) : 0
        let disk = stats.diskTotal > 0 ? Double(stats.diskUsed) / Double(stats.diskTotal) : 0
        Card(title: "System", glyph: "cpu", meta: stats.chip) {
            Spacer(minLength: 6)
            HStack(spacing: 12) {
                ZStack {
                    Ring(value: stats.cpu, color: Self.cpuColor, diameter: 92, width: 9)
                    Ring(value: mem, color: Self.ramColor, diameter: 68, width: 9)
                    Ring(value: disk, color: Self.diskColor, diameter: 44, width: 9)
                }
                .frame(width: 92, height: 92)
                VStack(alignment: .leading, spacing: 9) {
                    reading("CPU", Fmt.pct(stats.cpu), Self.cpuColor)
                    reading("RAM", Fmt.gb(stats.memUsed), Self.ramColor)
                    reading("Free", Fmt.gb(stats.diskFree), Self.diskColor)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            Spacer(minLength: 0)
        }
        .foregroundStyle(p.ink)
    }

    private func reading(_ label: String, _ value: String, _ c: Color) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 4) {
                Circle().fill(c).frame(width: 6, height: 6)
                Text(label.uppercased()).font(D.label(8.5)).tracking(0.8).foregroundStyle(D.p.ink3)
            }
            Text(value).font(D.rounded(14, .bold)).monospacedDigit().foregroundStyle(D.p.ink).lineLimit(1).minimumScaleFactor(0.7)
                .contentTransition(.numericText())
        }
    }
}

struct Ring: View {
    let value: Double
    let color: Color
    let diameter: CGFloat
    let width: CGFloat

    var body: some View {
        ZStack {
            Circle().stroke(color.opacity(0.16), lineWidth: width)
            Circle()
                .trim(from: 0, to: max(0.012, min(1, value)))
                .stroke(AngularGradient(colors: [color.opacity(0.7), color], center: .center, startAngle: .degrees(0), endAngle: .degrees(360 * max(0.05, value))),
                        style: StrokeStyle(lineWidth: width, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .shadow(color: color.opacity(0.35), radius: 3)
        }
        .frame(width: diameter - width, height: diameter - width)
        .animation(.spring(response: 0.9, dampingFraction: 0.75), value: value)
    }
}
