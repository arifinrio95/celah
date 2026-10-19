import SwiftUI

/// Prayer: a big countdown and the day drawn as a sky arc, with the sun (or moon) travelling along it.
struct PrayerView: View {
    @EnvironmentObject var prayer: PrayerService
    @EnvironmentObject var clock: Clock

    var body: some View {
        let p = D.p
        let now = clock.now
        let next = prayer.next(at: now)
        Card(title: "Prayer", glyph: "moon.stars.fill", meta: prayer.sunrise.map { "sunrise " + Fmt.hm($0, tz: prayer.timeZone) },
             tint: D.amber, background: AnyView(sky(now))) {
            Spacer(minLength: 4)
            if let next {
                HStack(alignment: .lastTextBaseline, spacing: 8) {
                    VStack(alignment: .leading, spacing: -2) {
                        Text(next.name).font(D.serif(15, .medium).italic()).foregroundStyle(p.accentInk)
                        Text(Fmt.countdown(next.date.timeIntervalSince(now)))
                            .font(D.rounded(30, .light)).monospacedDigit().foregroundStyle(p.ink)
                            .contentTransition(.numericText(countsDown: true))
                    }
                    Spacer(minLength: 0)
                    VStack(alignment: .trailing, spacing: 1) {
                        Text(Fmt.hm(next.date, tz: prayer.timeZone)).font(D.rounded(13, .bold)).monospacedDigit().foregroundStyle(p.ink2)
                        Text(next.isTomorrow ? "tomorrow" : "today").font(D.rounded(9.5, .semibold)).foregroundStyle(p.ink3)
                    }
                }
            } else {
                Text("Schedule unavailable").font(D.rounded(12, .medium)).foregroundStyle(p.ink3)
            }
            Spacer(minLength: 2)
            SkyArc(times: prayer.today, next: next, now: now, tz: prayer.timeZone)
                .frame(height: 60)
        }
    }

    /// A wash that follows the sky: night indigo, dawn rose, day blue, dusk orange.
    private func sky(_ now: Date) -> some View {
        var cal = Calendar(identifier: .gregorian); cal.timeZone = prayer.timeZone
        let h = Double(cal.component(.hour, from: now)) + Double(cal.component(.minute, from: now)) / 60
        let (a, b): (Color, Color) = {
            switch h {
            case 4..<6.5: return (Color(hex: 0xF7A8B8), Color(hex: 0xFFD8A8))
            case 6.5..<16: return (Color(hex: 0x9CC8F5), Color(hex: 0xE4F1FF))
            case 16..<19: return (Color(hex: 0xFFB36B), Color(hex: 0xF38BA0))
            default: return (Color(hex: 0x3B3F8F), Color(hex: 0x7E6BC4))
            }
        }()
        return LinearGradient(colors: [a.opacity(D.p.dark ? 0.32 : 0.30), b.opacity(D.p.dark ? 0.12 : 0.10), .clear],
                              startPoint: .topTrailing, endPoint: .bottomLeading)
    }
}

struct SkyArc: View {
    let times: [PrayerService.PrayerTime]
    let next: PrayerService.PrayerTime?
    let now: Date
    let tz: TimeZone

    var body: some View {
        let p = D.p
        Canvas { ctx, size in
            let n = times.count
            guard n > 0 else { return }
            let left: CGFloat = 4, right = size.width - 4
            let base = size.height - 24, top: CGFloat = 6
            // prayers sit at even steps along the arc; the sun moves between them by the clock
            func at(_ f: Double) -> CGPoint {
                let x = left + (right - left) * f
                return CGPoint(x: x, y: base - (base - top) * sin(.pi * (0.08 + 0.84 * f)))
            }
            func slot(_ i: Int) -> Double { (Double(i) + 0.5) / Double(n) }
            var nowF: Double = 0
            if now < times[0].date { nowF = slot(0) * max(0, 1 - times[0].date.timeIntervalSince(now) / (6 * 3600)) }
            else if now >= times[n - 1].date { nowF = slot(n - 1) + (1 - slot(n - 1)) * min(1, now.timeIntervalSince(times[n - 1].date) / (5 * 3600)) }
            else {
                for i in 0..<(n - 1) where now >= times[i].date && now < times[i + 1].date {
                    let k = now.timeIntervalSince(times[i].date) / times[i + 1].date.timeIntervalSince(times[i].date)
                    nowF = slot(i) + (slot(i + 1) - slot(i)) * k
                }
            }
            var arc = Path()
            for i in 0...60 { let q = at(Double(i) / 60); i == 0 ? arc.move(to: q) : arc.addLine(to: q) }
            ctx.stroke(arc, with: .color(p.ink4), style: StrokeStyle(lineWidth: 1.2, lineCap: .round, dash: [2, 4]))
            var done = Path()
            let steps = max(2, Int(nowF * 60))
            for i in 0...steps { let q = at(nowF * Double(i) / Double(steps)); i == 0 ? done.move(to: q) : done.addLine(to: q) }
            ctx.stroke(done, with: .color(D.amber.opacity(0.8)), style: StrokeStyle(lineWidth: 2, lineCap: .round))
            for (i, pr) in times.enumerated() {
                let q = at(slot(i))
                let isNext = next?.key == pr.key && next?.isTomorrow == false
                let passed = pr.date <= now
                let r: CGFloat = isNext ? 4.5 : 3
                ctx.fill(Path(ellipseIn: CGRect(x: q.x - r, y: q.y - r, width: r * 2, height: r * 2)),
                         with: .color(isNext ? D.amber : (passed ? p.ink3 : p.ink2)))
                let x = left + (right - left) * slot(i)
                ctx.draw(Text(pr.short.uppercased()).font(D.label(7.5)).foregroundColor(isNext ? p.accentInk : p.ink3),
                         at: CGPoint(x: x, y: base + 9))
                ctx.draw(Text(Fmt.hm(pr.date, tz: tz)).font(D.rounded(8.5, isNext ? .bold : .semibold)).foregroundColor(isNext ? p.ink : p.ink3),
                         at: CGPoint(x: x, y: base + 19))
            }
            let q = at(nowF)
            let day = n > 1 && now > times[1].date.addingTimeInterval(-5 * 3600) && now < times[min(3, n - 1)].date
            if day {
                ctx.fill(Path(ellipseIn: CGRect(x: q.x - 9, y: q.y - 9, width: 18, height: 18)), with: .color(D.amber.opacity(0.25)))
                ctx.fill(Path(ellipseIn: CGRect(x: q.x - 5, y: q.y - 5, width: 10, height: 10)), with: .color(D.amber))
            } else {
                ctx.fill(Path(ellipseIn: CGRect(x: q.x - 8, y: q.y - 8, width: 16, height: 16)), with: .color(Color(hex: 0x7E6BC4).opacity(0.22)))
                ctx.draw(Text(Image(systemName: "moon.fill")).font(.system(size: 10)).foregroundColor(Color(hex: 0x7E6BC4)), at: q)
            }
        }
    }
}
