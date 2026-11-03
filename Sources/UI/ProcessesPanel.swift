import SwiftUI

/// Running apps, heaviest first, with Force Quit. Opens from Apps in the board's top row.
struct ProcessesPanel: View {
    @EnvironmentObject var procs: ProcessMonitor
    @EnvironmentObject var stats: SystemStats
    @State private var confirming: String?

    var body: some View {
        let p = D.p
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("Apps").font(D.serif(20).italic()).foregroundStyle(p.ink)
                Text("\(procs.apps.filter { !$0.isBackground && !$0.isProcess }.count) apps · CPU \(Fmt.pct(stats.cpu))")
                    .font(D.rounded(11.5, .semibold)).foregroundStyle(p.ink3).lineLimit(1)
                Spacer()
                HStack(spacing: 3) {
                    sortTab("Memory", .memory)
                    sortTab("CPU", .cpu)
                }
                .padding(2).background(Capsule().fill(p.track))
                Orb(symbol: "xmark", size: 24) { procs.panelOpen = false }
            }
            ramBreakdown
            if let m = procs.message {
                Text(m).font(D.rounded(11.5, .semibold)).foregroundStyle(p.danger)
                    .onAppear { DispatchQueue.main.asyncAfter(deadline: .now() + 4) { procs.message = nil } }
            }
            if procs.loading {
                VStack { Spacer(); ProgressView().controlSize(.small); Spacer() }.frame(maxWidth: .infinity)
            } else {
                let maxCPU = max(100, procs.apps.map(\.cpu).max() ?? 100)
                let maxRSS = max(1, procs.apps.map(\.rssKB).max() ?? 1)
                HStack(spacing: 10) {
                    Text("APP").frame(width: 202, alignment: .leading)
                    Text("CPU").frame(maxWidth: .infinity, alignment: .leading)
                    Text("RAM").frame(maxWidth: .infinity, alignment: .leading)
                    Text("").frame(width: 84)
                }
                .font(D.label(8.5)).tracking(1).foregroundStyle(p.ink3)
                .padding(.horizontal, 10)
                ScrollView(.vertical, showsIndicators: false) {
                    LazyVStack(spacing: 4) {
                        ForEach(procs.apps) { app in
                            row(app, cpuScale: maxCPU, rssScale: maxRSS)
                        }
                    }
                    .padding(.bottom, 4)
                    .animation(D.snappy, value: procs.apps.map(\.id))
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

    /// RAM in use, split the way Activity Monitor does, so the System card's number makes sense next to the rows.
    private var ramBreakdown: some View {
        let p = D.p, m = stats.memParts
        let total = max(1, Double(stats.memTotal))
        return VStack(alignment: .leading, spacing: 5) {
            GeometryReader { g in
                HStack(spacing: 2) {
                    Capsule().fill(SystemView.ramColor).frame(width: g.size.width * Double(m.app) / total)
                    Capsule().fill(SystemView.ramColor.opacity(0.55)).frame(width: g.size.width * Double(m.compressed) / total)
                    Capsule().fill(p.ink3).frame(width: g.size.width * Double(m.wired) / total)
                    Spacer(minLength: 0)
                }
            }
            .frame(height: 6)
            .background(Capsule().fill(p.track))
            HStack(spacing: 12) {
                Text("RAM in use \(Fmt.gb(stats.memUsed)) of \(Fmt.gb(stats.memTotal))").foregroundStyle(p.ink)
                legend(SystemView.ramColor, "apps \(Fmt.gb(m.app))")
                legend(SystemView.ramColor.opacity(0.55), "compressed \(Fmt.gb(m.compressed))")
                legend(p.ink3, "macOS \(Fmt.gb(m.wired))")
                Spacer(minLength: 0)
                Image(systemName: "info.circle").foregroundStyle(p.ink3)
                    .help("The rows show each app's memory the way Activity Monitor's Memory column does: everything it holds, including what macOS has compressed, counted at full size. That is why the rows can add up to more than RAM in use. RAM in use counts compressed memory at its squeezed size, plus memory macOS keeps for itself.")
            }
            .font(D.rounded(10.5, .semibold)).monospacedDigit().foregroundStyle(p.ink3)
        }
    }

    private func legend(_ c: Color, _ text: String) -> some View {
        HStack(spacing: 4) { Circle().fill(c).frame(width: 6, height: 6); Text(text) }
    }

    private func sortTab(_ title: String, _ key: ProcessMonitor.SortKey) -> some View {
        let p = D.p, on = procs.sort == key
        return Button { withAnimation(D.snappy) { procs.sort = key } } label: {
            Text(title).font(D.rounded(10.5, .bold))
                .foregroundStyle(on ? (p.dark ? Color.black : Color.white) : p.ink3)
                .padding(.horizontal, 10).frame(height: 22)
                .background { if on { Capsule().fill(p.ink) } }
                .contentShape(Capsule())
        }.buttonStyle(PressScale())
    }

    private func row(_ app: ProcessMonitor.AppUsage, cpuScale: Double, rssScale: Int) -> some View {
        let p = D.p
        let confirm = confirming == app.id
        return HStack(spacing: 10) {
            Group {
                if let icon = app.icon { Image(nsImage: icon).resizable().interpolation(.high) } else { Image(systemName: "app.fill").resizable() }
            }
            .frame(width: 22, height: 22)
            VStack(alignment: .leading, spacing: 1) {
                Text(app.name).font(D.rounded(12.5, .semibold)).foregroundStyle(p.ink).lineLimit(1)
                Text(app.isBackground ? "\(app.processes) processes · macOS & tools" : app.isProcess ? (app.folder.map { "in " + $0 } ?? "pid " + String(app.pid)) : app.processes > 1 ? "\(app.processes) processes" : "1 process")
                    .font(D.rounded(9.5, .medium)).foregroundStyle(p.ink3).lineLimit(1).truncationMode(app.isProcess ? .middle : .tail)
                    .help(app.folder ?? "")
            }
            .frame(width: 170, alignment: .leading)
            meter("CPU", String(format: "%.0f%%", app.cpu), app.cpu / cpuScale, SystemView.cpuColor, emphasized: procs.sort == .cpu)
            meter("RAM", Self.memory(app.rssKB), Double(app.rssKB) / Double(rssScale), SystemView.ramColor, emphasized: procs.sort == .memory)
            if app.isBackground {
                Text("system").font(D.rounded(10, .semibold)).foregroundStyle(p.ink4).frame(width: 84)
                    .help("macOS services and small tools no app owns. Big ones get a row of their own.")
            } else {
                Button {
                    if confirm { procs.forceQuit(app); confirming = nil; (NSApp.delegate as? AppDelegate)?.notch.cheer(.wired, for: 1.2) }
                    else {
                        withAnimation(D.snappy) { confirming = app.id }
                        DispatchQueue.main.asyncAfter(deadline: .now() + 3) { if confirming == app.id { withAnimation { confirming = nil } } }
                    }
                } label: {
                    Text(confirm ? "Force Quit?" : "Quit")
                        .font(D.rounded(10.5, .bold))
                        .foregroundStyle(confirm ? Color.white : p.danger)
                        .padding(.horizontal, 10).frame(height: 24)
                        .background(Capsule().fill(confirm ? p.danger : p.danger.opacity(0.10)))
                        .contentShape(Capsule())
                }
                .buttonStyle(PressScale())
                .help(confirm ? "Click again to force quit \(app.name). Unsaved work is lost." : "Force quit \(app.name)")
                .frame(width: 84, alignment: .trailing)
            }
        }
        .padding(.horizontal, 10).frame(height: 40)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(confirm ? p.danger.opacity(0.06) : p.track))
    }

    private func meter(_ label: String, _ value: String, _ f: Double, _ c: Color, emphasized: Bool) -> some View {
        let p = D.p
        return HStack(spacing: 8) {
            GeometryReader { g in
                ZStack(alignment: .leading) {
                    Capsule().fill(c.opacity(0.14))
                    Capsule().fill(c).frame(width: max(3, g.size.width * min(1, f)))
                }
            }
            .frame(height: 5)
            Text(value).font(D.rounded(11.5, emphasized ? .heavy : .semibold)).monospacedDigit()
                .foregroundStyle(emphasized ? p.ink : p.ink2).frame(width: 64, alignment: .trailing)
        }
        .frame(maxWidth: .infinity)
        .help(label)
    }

    static func memory(_ kb: Int) -> String {
        let mb = Double(kb) / 1024
        return mb >= 1024 ? String(format: "%.1f GB", mb / 1024) : String(format: "%.0f MB", mb)
    }
}
