import AppKit

/// `Celah --diag`: print what each service sees, then exit. No UI, no notifications.
enum Diagnostics {
    static func run() -> Never {
        let settings = AppSettings()
        let geo = NotchGeometry.detect()
        print("notch: hasNotch=\(geo.hasNotch) width=\(geo.notchWidth) height=\(geo.notchHeight) screen=\(geo.screenFrame)")

        let prayer = PrayerService(settings: settings)
        prayer.recompute()
        print("prayer @ \(prayer.locationName) (\(prayer.timeZone.identifier)):")
        if let s = prayer.sunrise { print("  sunrise  \(Fmt.hm(s, tz: prayer.timeZone))") }
        for p in prayer.today { print("  \(p.name.padding(toLength: 8, withPad: " ", startingAt: 0)) \(Fmt.hm(p.date, tz: prayer.timeZone))") }
        if let n = prayer.next(at: Date()) { print("  next: \(n.name) in \(Fmt.countdown(n.date.timeIntervalSinceNow))") }

        let stats = SystemStats()
        stats.sample()
        Thread.sleep(forTimeInterval: 1.6)
        stats.sample()
        Thread.sleep(forTimeInterval: 0.5)
        RunLoop.main.run(until: Date().addingTimeInterval(0.2))
        print("system: \(stats.chip) cpu=\(Fmt.pct(stats.cpu)) mem=\(Fmt.gb(stats.memUsed))/\(Fmt.gb(stats.memTotal)) disk free=\(Fmt.gb(stats.diskFree))/\(Fmt.gb(stats.diskTotal))")

        let music = MusicBridge()
        music.refresh()
        RunLoop.main.run(until: Date().addingTimeInterval(2.5))
        if let np = music.now {
            print("music: \(np.player.displayName) \(np.isPlaying ? "playing" : "paused") — \(np.title) / \(np.artist) pos=\(Int(np.position))s dur=\(Int(np.duration))s art=\(np.artURL?.absoluteString ?? "(data)")")
        } else {
            print("music: nothing (running: \(music.runningPlayers.map(\.displayName)))")
        }

        let usage = AIUsage()
        usage.refresh(force: true)
        let deadline = Date().addingTimeInterval(20)
        while usage.lastFetched == nil, Date() < deadline { RunLoop.main.run(until: Date().addingTimeInterval(0.2)) }
        for b in [usage.claudeBlock, usage.chatgptBlock] {
            print("usage: \(b.name) tier=\(b.tier ?? "-") note=\(b.note ?? "-")")
            for w in b.windows { print("   \(w.label): \(Fmt.pct(w.used)) \(Fmt.reset(w.resetsAt))") }
        }

        let quran = QuranStore()
        quran.load()
        let qDeadline = Date().addingTimeInterval(5)
        while !quran.loaded, Date() < qDeadline { RunLoop.main.run(until: Date().addingTimeInterval(0.1)) }
        if let a = quran.current, let s = quran.currentSurah {
            print("quran: \(quran.count) ayat loaded; at \(s.latin) \(a.surah):\(a.number) — \(a.translation.prefix(60))…")
        } else {
            print("quran: failed to load (bundle resource missing?)")
        }
        exit(0)
    }
}
