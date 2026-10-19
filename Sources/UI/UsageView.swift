import SwiftUI

/// AI usage: one jelly bar per assistant, filled by the tightest window, wobbling gently.
struct UsageView: View {
    @EnvironmentObject var usage: AIUsage
    @EnvironmentObject var clock: Clock

    var body: some View {
        Card(title: "AI Usage", glyph: "sparkles", meta: usage.lastFetched.map { Fmt.ago($0, now: clock.now) }) {
            Spacer(minLength: 8)
            VStack(spacing: 12) {
                UsageRow(block: usage.claudeBlock, brand: D.claude, now: clock.now)
                UsageRow(block: usage.chatgptBlock, brand: D.chatgpt, now: clock.now)
            }
            Spacer(minLength: 0)
        }
    }
}

struct UsageRow: View {
    let block: AIUsage.Block
    let brand: Color
    let now: Date
    @State private var hover = false

    var body: some View {
        let p = D.p
        let worst = block.windows.max { $0.used < $1.used }
        let used = worst?.used ?? 0
        let color = used >= 0.9 ? p.danger : (used >= 0.72 ? D.amber : brand)
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                if let path = block.iconPath { AppIconView(path: path, size: 15) }
                Text(block.name).font(D.rounded(12.5, .bold)).foregroundStyle(p.ink)
                if let tier = block.tier {
                    Text(tier.uppercased()).font(D.label(8)).tracking(0.8).foregroundStyle(p.ink3)
                        .padding(.horizontal, 5).padding(.vertical, 1.5)
                        .background(Capsule().strokeBorder(p.ink4, lineWidth: 1))
                }
                Spacer(minLength: 4)
                if worst != nil {
                    Text(Fmt.pct(used)).font(D.rounded(13, .heavy)).monospacedDigit().foregroundStyle(used >= 0.9 ? p.danger : p.ink)
                        .contentTransition(.numericText())
                }
            }
            if block.windows.isEmpty {
                Text(block.note ?? "—").font(D.rounded(10.5, .medium)).foregroundStyle(p.ink3).lineLimit(2)
            } else {
                JellyBar(value: used, color: color, height: 16)
                HStack(spacing: 8) {
                    ForEach(block.windows) { w in
                        HStack(spacing: 3) {
                            Circle().fill(w.used >= 0.9 ? p.danger : (w.used >= 0.72 ? D.amber : brand)).frame(width: 5, height: 5)
                            Text("\(w.label.lowercased()) \(Fmt.pct(w.used))").font(D.rounded(9.5, .bold)).foregroundStyle(p.ink2)
                            Text(Fmt.reset(w.resetsAt, now: now).replacingOccurrences(of: "resets ", with: "↺ "))
                                .font(D.rounded(9.5, .medium)).foregroundStyle(p.ink3)
                        }
                        .lineLimit(1)
                    }
                }
            }
        }
        .padding(6)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(hover ? p.track : .clear))
        .padding(-6)
        .contentShape(Rectangle())
        .onHover { hover = $0 }
        .onTapGesture { Apps.open(bundleID: block.bundleID, name: block.name == "Claude" ? "Claude" : "ChatGPT") }
    }
}
