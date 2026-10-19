import SwiftUI

/// The tray's contents: a header that keeps clear of the creature's chin, then a bento of cards.
/// Cards are dealt in one after another when the board opens. Panels (Keep Awake, Clipboard)
/// slide up over the cards.
struct BoardView: View {
    @ObservedObject var ctl: NotchController
    @EnvironmentObject var clip: ClipboardStore
    @EnvironmentObject var awake: KeepAwake
    @EnvironmentObject var settings: AppSettings

    static let gap: CGFloat = 10
    static let weights: [BoardModule: CGFloat] = [.music: 1.32, .usage: 1.0, .prayer: 1.1, .tasks: 1.2, .system: 0.86, .quran: 1.32]

    var body: some View {
        let open = ctl.isExpanded
        let width = ctl.trayWidth - 24
        VStack(spacing: 8) {
            BoardHeader(ctl: ctl, chinClearance: ctl.chinWidth + 26)
                .frame(height: 30)
                .opacity(open ? 1 : 0)
                .offset(y: open ? 0 : -8)
                .animation(open ? D.springIn.delay(0.1) : .easeIn(duration: 0.1), value: open)
            ZStack {
                grid(width: width)
                    .blur(radius: clip.panelOpen || awake.panelOpen ? 6 : 0)
                    .scaleEffect(clip.panelOpen || awake.panelOpen ? 0.97 : 1)
                    .opacity(clip.panelOpen || awake.panelOpen ? 0.35 : 1)
                    .allowsHitTesting(!(clip.panelOpen || awake.panelOpen))
                if clip.panelOpen {
                    ClipboardPanel()
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                } else if awake.panelOpen {
                    AwakePanel(ctl: ctl)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .animation(D.springIn, value: clip.panelOpen)
            .animation(D.springIn, value: awake.panelOpen)
        }
    }

    @ViewBuilder private func grid(width: CGFloat) -> some View {
        let mods = Array(settings.modules.prefix(BoardLayout.maxModules))
        let rows = BoardLayout.rows(for: mods.count)
        if mods.isEmpty {
            VStack(spacing: 8) {
                Text("An empty tray.").font(D.serif(18, .regular).italic()).foregroundStyle(D.p.ink2)
                Text("Pick modules in Settings").font(D.rounded(11, .medium)).foregroundStyle(D.p.ink3)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            VStack(spacing: Self.gap) {
                ForEach(Array(rows.enumerated()), id: \.offset) { r, count in
                    let start = rows.prefix(r).reduce(0, +)
                    let row = Array(mods[start..<(start + count)])
                    let total = row.map { Self.weights[$0] ?? 1 }.reduce(0, +)
                    let avail = width - Self.gap * CGFloat(count - 1)
                    HStack(spacing: Self.gap) {
                        ForEach(Array(row.enumerated()), id: \.element) { c, m in
                            Dealt(index: start + c, open: ctl.isExpanded) {
                                moduleView(m)
                            }
                            .frame(width: avail * (Self.weights[m] ?? 1) / total)
                        }
                    }
                    .frame(maxHeight: .infinity)
                }
            }
        }
    }

    @ViewBuilder private func moduleView(_ m: BoardModule) -> some View {
        switch m {
        case .music: MusicView()
        case .usage: UsageView()
        case .prayer: PrayerView()
        case .tasks: TasksView(ctl: ctl)
        case .system: SystemView()
        case .quran: QuranView()
        }
    }
}

/// A card being dealt: drops in from the slot, tilted a little, and settles.
struct Dealt<Content: View>: View {
    let index: Int
    let open: Bool
    @ViewBuilder var content: Content

    var body: some View {
        let tilt: Double = [-2.2, 1.6, -1.2, 2.0, -1.8, 1.3][index % 6]
        content
            .opacity(open ? 1 : 0)
            .offset(y: open ? 0 : -34)
            .rotationEffect(.degrees(open ? 0 : tilt), anchor: .top)
            .scaleEffect(open ? 1 : 0.94, anchor: .top)
            .animation(open ? .spring(response: 0.46, dampingFraction: 0.72).delay(0.12 + Double(index) * 0.045)
                            : .easeIn(duration: 0.12), value: open)
    }
}

/// Day on the left, actions on the right, a gap in the middle for the creature. Nothing sits under the camera.
struct BoardHeader: View {
    @ObservedObject var ctl: NotchController
    let chinClearance: CGFloat
    @EnvironmentObject var clock: Clock
    @EnvironmentObject var clip: ClipboardStore
    @EnvironmentObject var awake: KeepAwake
    @EnvironmentObject var recorder: MeetingRecorder
    @EnvironmentObject var prayer: PrayerService

    var body: some View {
        let p = D.p
        HStack(spacing: 0) {
            HStack(alignment: .firstTextBaseline, spacing: 7) {
                Text(weekday).font(D.serif(19, .regular).italic()).foregroundStyle(p.ink)
                Text(dayMonth).font(D.rounded(11.5, .semibold)).foregroundStyle(p.ink3)
                if !prayer.locationName.isEmpty {
                    Text("· " + prayer.locationName).font(D.rounded(11.5, .medium)).foregroundStyle(p.ink3).lineLimit(1)
                }
            }
            .padding(.leading, 6)
            .frame(maxWidth: .infinity, alignment: .leading)
            Spacer().frame(width: chinClearance)
            ViewThatFits(in: .horizontal) {
                actions(labels: true)
                actions(labels: false)
            }
            .frame(maxWidth: .infinity, alignment: .trailing)
        }
    }

    private func actions(labels: Bool) -> some View {
        let p = D.p
        return HStack(spacing: 6) {
            if labels {
                Pill(symbol: recorder.isRecording ? "stop.fill" : "record.circle",
                     text: recorder.isRecording ? Fmt.short(clock.now.timeIntervalSince(recorder.startedAt ?? clock.now)) : "Record",
                     on: recorder.isRecording, tint: p.danger) { recorder.toggle(); ctl.cheer(recorder.isRecording ? .wired : .happy) }
                    .help(recorder.isRecording ? "Stop recording" : "Record this meeting")
                Pill(symbol: awake.isActive ? "cup.and.saucer.fill" : "cup.and.saucer",
                     text: awake.isActive ? (awake.endsAt.map { Fmt.short($0.timeIntervalSince(clock.now)) } ?? "Awake") : "Awake",
                     on: awake.isActive || awake.panelOpen) { awake.panelOpen.toggle(); clip.panelOpen = false }
                    .help("Keep this Mac awake")
                Pill(symbol: "doc.on.clipboard", text: clip.items.isEmpty ? "Clipboard" : "Clipboard \(clip.items.count)",
                     on: clip.panelOpen, tint: p.ink) { clip.panelOpen.toggle(); awake.panelOpen = false }
                    .help("Clipboard history")
            } else {
                Orb(symbol: recorder.isRecording ? "stop.fill" : "record.circle", filled: recorder.isRecording, tint: p.danger) { recorder.toggle() }
                Orb(symbol: "cup.and.saucer.fill", filled: awake.isActive) { awake.panelOpen.toggle(); clip.panelOpen = false }
                Orb(symbol: "doc.on.clipboard", filled: clip.panelOpen) { clip.panelOpen.toggle(); awake.panelOpen = false }
            }
            Orb(symbol: "folder") { (NSApp.delegate as? AppDelegate)?.showMeetings() }
                .help("Meetings: send a recording to Claude or Codex")
            Orb(symbol: "ellipsis") { (NSApp.delegate as? AppDelegate)?.showMenu() }
        }
        .padding(.trailing, 2)
        .fixedSize()
    }

    private var weekday: String { let f = DateFormatter(); f.locale = Fmt.locale; f.dateFormat = "EEEE"; return f.string(from: clock.now) }
    private var dayMonth: String { let f = DateFormatter(); f.locale = Fmt.locale; f.dateFormat = "d MMM"; return f.string(from: clock.now) }
}
