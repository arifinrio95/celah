import SwiftUI

/// Keep Awake: three illustrated choices, a duration, and the guardrails. Slides up over the cards.
struct AwakePanel: View {
    @ObservedObject var ctl: NotchController
    @EnvironmentObject var awake: KeepAwake
    @EnvironmentObject var clock: Clock

    var body: some View {
        let p = D.p
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("Keep Awake").font(D.serif(20).italic()).foregroundStyle(p.ink)
                Text(status).font(D.rounded(11.5, .semibold)).monospacedDigit().foregroundStyle(awake.isActive ? p.accentInk : p.ink3)
                Spacer()
                Orb(symbol: "xmark", size: 24) { awake.panelOpen = false }
            }
            HStack(spacing: 10) {
                option(.off, title: "Sleep as usual", detail: "Nothing special.")
                option(.awake, title: "Stay awake", detail: "The screen may still nap.")
                option(.lidClosed, title: "Lid closed too", detail: "Bag it. The agent keeps going.")
            }
            HStack(spacing: 6) {
                Text("FOR").font(D.label(9)).tracking(1).foregroundStyle(p.ink3)
                ForEach(Array(KeepAwake.durations.enumerated()), id: \.offset) { _, d in
                    Pill(symbol: d.minutes == nil ? "infinity" : "timer", text: d.label, on: awake.minutes == d.minutes, tint: p.ink) { awake.setDuration(d.minutes) }
                }
                Spacer(minLength: 6)
                if !awake.helperInstalled {
                    Pill(symbol: "key.fill", text: "Set up once", tint: p.accent) { awake.installHelper() }
                        .help("One password prompt, then lid-closed mode never asks again")
                }
                if awake.sleepDisabled && awake.mode != .lidClosed {
                    Pill(symbol: "arrow.counterclockwise", text: "Restore sleep") { awake.restoreSleep() }
                }
            }
            HStack(spacing: 6) {
                Image(systemName: "shield.lefthalf.filled").font(.system(size: 10, weight: .bold)).foregroundStyle(p.ok)
                Text("Turns itself off below \(awake.batteryThreshold)% battery or if the Mac runs hot.")
                    .font(D.rounded(10.5, .medium)).foregroundStyle(p.ink3)
                if let msg = awake.message {
                    Text("· " + msg).font(D.rounded(10.5, .semibold)).foregroundStyle(p.danger).lineLimit(1)
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background {
            RoundedRectangle(cornerRadius: 22, style: .continuous).fill(p.card)
                .shadow(color: p.cardShadow, radius: 18, y: 10)
        }
    }

    private var status: String {
        guard awake.isActive else { return "off" }
        if let endsAt = awake.endsAt { return Fmt.short(endsAt.timeIntervalSince(clock.now)) + " left" }
        return "until you say so"
    }

    private func option(_ m: KeepAwake.Mode, title: String, detail: String) -> some View {
        let p = D.p
        let on = awake.mode == m
        return Button {
            withAnimation(D.snappy) { awake.choose(m) }
            ctl.cheer(m == .off ? .sleepy : .wired, for: 1.6)
        } label: {
            VStack(spacing: 8) {
                AwakeArt(mode: m, on: on).frame(height: 128)
                VStack(spacing: 2) {
                    Text(title).font(D.rounded(13, .bold)).foregroundStyle(p.ink)
                    Text(detail).font(D.rounded(10.5, .medium)).foregroundStyle(p.ink3).lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(on ? D.amber.opacity(p.dark ? 0.16 : 0.13) : p.track)
                    .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(on ? D.amber : .clear, lineWidth: 2))
            }
            .scaleEffect(on ? 1.0 : 0.97)
            .contentShape(RoundedRectangle(cornerRadius: 18))
        }
        .buttonStyle(PressScale())
    }
}

/// Little drawings for each mode: a sleeping moon, a steaming mug, a closed laptop with a coffee on top.
struct AwakeArt: View {
    let mode: KeepAwake.Mode
    let on: Bool

    var body: some View {
        let p = D.p
        TimelineView(.animation(minimumInterval: 1 / 24, paused: !on)) { tl in
            let t = tl.date.timeIntervalSinceReferenceDate
            ZStack {
                switch mode {
                case .off:
                    SleepyMoon(t: t, on: on)
                case .awake:
                    SteamingCup(size: 84, live: on, coffee: true, color: on ? D.amber : p.ink3)
                case .lidClosed:
                    VStack(spacing: 0) {
                        SteamingCup(size: 50, live: on, coffee: true, color: on ? D.amber : p.ink3).offset(x: 22, y: 6)
                        RoundedRectangle(cornerRadius: 4).fill(on ? Color(hex: 0xB9BCC2) : p.ink4).frame(width: 124, height: 10)
                        RoundedRectangle(cornerRadius: 3).fill(on ? Color(hex: 0x9EA1A7) : p.ink4).frame(width: 136, height: 6)
                    }
                    if on {
                        Circle().fill(p.ok).frame(width: 8, height: 8).offset(x: -44, y: 36)
                            .opacity(0.5 + 0.5 * sin(t * 4))
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

private struct SleepyMoon: View {
    let t: Double
    let on: Bool
    var body: some View {
        let c: Color = on ? Color(hex: 0x7E6BC4) : D.p.ink3
        let wobble: Double = -18 + 4 * sin(t * 1.2)
        ZStack {
            Image(systemName: "moon.fill").font(.system(size: 52)).foregroundStyle(c).rotationEffect(.degrees(wobble))
            ForEach(0..<3, id: \.self) { i in zee(i, color: c) }
        }
    }
    private func zee(_ i: Int, color: Color) -> some View {
        let z: Double = (t * 0.5 + Double(i) / 3).truncatingRemainder(dividingBy: 1)
        let size: CGFloat = 13 + CGFloat(i) * 4
        let alpha: Double = on ? 1 - z : 0.5
        let x: CGFloat = 34 + CGFloat(z) * 16
        let y: CGFloat = -16 - CGFloat(z) * 30 - CGFloat(i) * 4
        return Text("z").font(D.rounded(size, .heavy)).foregroundStyle(color.opacity(alpha)).offset(x: x, y: y)
    }
}
