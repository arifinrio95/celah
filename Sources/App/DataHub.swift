import AppKit
import SwiftUI
import Combine

/// Owns every data service and decides what the collapsed notch shows.
final class DataHub {
    let settings = AppSettings()
    let clock = Clock()
    let stats = SystemStats()
    let usage = AIUsage()
    let music = MusicBridge()
    let tasks = TaskStore()
    let prayer: PrayerService
    let quran = QuranStore()
    let clipboard = ClipboardStore()
    let awake = KeepAwake()
    let recorder = MeetingRecorder()
    let notifier = Notifier()

    private weak var notch: NotchController?
    private var bag = Set<AnyCancellable>()
    private var lastMusicSync = Date.distantPast

    init() {
        prayer = PrayerService(settings: settings)
    }

    /// Attaches every service as an environment object.
    func inject<V: View>(_ view: V) -> AnyView {
        AnyView(view
            .environmentObject(settings)
            .environmentObject(clock)
            .environmentObject(stats)
            .environmentObject(usage)
            .environmentObject(music)
            .environmentObject(tasks)
            .environmentObject(prayer)
            .environmentObject(quran)
            .environmentObject(clipboard)
            .environmentObject(awake)
            .environmentObject(recorder))
    }

    func start(notch: NotchController) {
        self.notch = notch
        notifier.start()
        prayer.notifier = notifier
        stats.start()
        music.start()
        prayer.start()
        quran.load()
        clipboard.start()
        awake.recoverIfNeeded()
        recorder.$isRecording.sink { [weak self] _ in DispatchQueue.main.async { self?.updateWing() } }.store(in: &bag)
        awake.$mode.sink { [weak self] _ in DispatchQueue.main.async { self?.updateWing() } }.store(in: &bag)
        usage.refresh(force: false)

        notch.onExpand = { [weak self] in self?.onExpand() }
        notch.onCollapse = { [weak self] in self?.onCollapse() }

        clock.$now.sink { [weak self] now in self?.tick(now) }.store(in: &bag)
        music.$now.sink { [weak self] _ in DispatchQueue.main.async { self?.updateWing() } }.store(in: &bag)
        settings.$wings.sink { [weak self] _ in DispatchQueue.main.async { self?.updateWing() } }.store(in: &bag)
        clock.setFast(false)
    }

    func stop() {
        stats.stop()
        clipboard.stop()
        awake.shutdown()
        recorder.shutdown()
        clock.stop()
    }

    func refreshAll(force: Bool) {
        stats.sample()
        usage.refresh(force: force)
        music.refresh()
        prayer.recompute()
    }

    private func onExpand() {
        stats.sample()
        usage.refresh(force: false)
        music.refresh()
        clock.setFast(true)
    }

    private func onCollapse() {
        clock.setFast(wingIsPrayer)
    }

    private var wingIsPrayer: Bool {
        if case .prayer = notch?.wing ?? .none { return true }
        return false
    }

    private func tick(_ now: Date) {
        prayer.tick(now)
        if notch?.isExpanded == true, music.now?.isPlaying == true, now.timeIntervalSince(lastMusicSync) > 5 {
            lastMusicSync = now
            music.refresh()
        }
        updateWing()
    }

    private func updateWing() {
        guard let notch else { return }
        let now = clock.now
        var wing: WingContent = .none
        if let forced = ProcessInfo.processInfo.environment["CELAH_FORCE_WING"] {   // debug aid
            wing = forced == "music" ? .music : .prayer(prayer.next(at: now)?.name ?? "Maghrib")
        } else if settings.wings {
            if let next = prayer.next(at: now), next.date.timeIntervalSince(now) <= 600 {
                wing = .prayer(next.name)
            } else if music.now?.isPlaying == true {
                wing = .music
            } else if awake.isActive {
                wing = .awake
            }
        }
        if recorder.isRecording { wing = .recording }
        // the creature's resting mood follows the data
        let worst = (usage.claudeBlock.windows + usage.chatgptBlock.windows).map(\.used).max() ?? 0
        let hour = Calendar.current.component(.hour, from: now)
        let mood: Mood = worst >= 0.9 ? .worried : (awake.isActive ? .wired : (hour < 5 ? .sleepy : .neutral))
        if notch.baseMood != mood { withAnimation(D.snappy) { notch.baseMood = mood } }
        if notch.wing != wing {
            withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) { notch.wing = wing }
            if !notch.isExpanded { clock.setFast(wingIsPrayer) }
        }
    }
}

/// A shared clock so views tick together: 1 Hz when something is visibly counting, slow otherwise.
final class Clock: ObservableObject {
    @Published private(set) var now = Date()
    private var timer: Timer?
    private var fast = false

    func setFast(_ fast: Bool) {
        if self.fast == fast, timer != nil { return }
        self.fast = fast
        timer?.invalidate()
        now = Date()
        timer = Timer.scheduledTimer(withTimeInterval: fast ? 1 : 20, repeats: true) { [weak self] _ in
            self?.now = Date()
        }
        timer?.tolerance = fast ? 0.1 : 5
    }

    func stop() { timer?.invalidate(); timer = nil }
}
