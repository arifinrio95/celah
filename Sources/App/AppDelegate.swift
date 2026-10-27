import AppKit
import SwiftUI
import ServiceManagement

final class AppDelegate: NSObject, NSApplicationDelegate {
    static let pinNotification = Notification.Name("id.datasans.celah.pin")
    static let settingsNotification = Notification.Name("id.datasans.celah.settings")
    static let tasksNotification = Notification.Name("id.datasans.celah.tasks")
    static let quranNotification = Notification.Name("id.datasans.celah.quran")
    static let meetingsNotification = Notification.Name("id.datasans.celah.meetings")
    static let remoteNotification = Notification.Name("id.datasans.celah.remote")

    private(set) var hub: DataHub!
    private(set) var notch: NotchController!
    private var settingsWindow: NSWindow?
    private var tasksWindow: NSWindow?
    private var meetingsWindow: NSWindow?
    private var quranWindow: NSWindow?
    private var remoteWindow: NSWindow?
    private var termSource: DispatchSourceSignal?

    func applicationDidFinishLaunching(_ notification: Notification) {
        Fonts.register()
        hub = DataHub()
        notch = NotchController()
        notch.install(root: hub.inject(NotchRootView(ctl: notch)))
        hub.start(notch: notch)
        notch.start()

        DistributedNotificationCenter.default().addObserver(self, selector: #selector(togglePin),
                                                            name: AppDelegate.pinNotification, object: nil)
        DistributedNotificationCenter.default().addObserver(self, selector: #selector(openSettings),
                                                            name: AppDelegate.settingsNotification, object: nil)
        DistributedNotificationCenter.default().addObserver(self, selector: #selector(openTasks),
                                                            name: AppDelegate.tasksNotification, object: nil)
        DistributedNotificationCenter.default().addObserver(self, selector: #selector(openQuran),
                                                            name: AppDelegate.quranNotification, object: nil)
        DistributedNotificationCenter.default().addObserver(self, selector: #selector(showMeetingsFromCLI),
                                                            name: AppDelegate.meetingsNotification, object: nil)
        DistributedNotificationCenter.default().addObserver(self, selector: #selector(openRemoteFromCLI(_:)),
                                                            name: AppDelegate.remoteNotification, object: nil)
        // `kill` (or a logout) should still close the tunnel and finish a recording
        signal(SIGTERM, SIG_IGN)
        termSource = DispatchSource.makeSignalSource(signal: SIGTERM, queue: .main)
        termSource?.setEventHandler { NSApp.terminate(nil) }
        termSource?.resume()
        handleSnapshotFlag()
        handleMirrorTest()
    }

    func applicationWillTerminate(_ notification: Notification) {
        hub.stop()
    }

    // MARK: - Pin / snapshot (debug helpers)

    @objc private func togglePin() {
        notch.pinned.toggle()
        if notch.pinned { notch.expand() } else { notch.collapse() }
    }

    /// `--mirror-test`: opens and closes the mirror three times and logs whether frames arrived. Saves no picture.
    private func handleMirrorTest() {
        guard CommandLine.arguments.contains("--mirror-test") else { return }
        notch.pinned = true
        notch.expand()
        func cycle(_ n: Int) {
            guard n <= 3 else { Log.write("mirror test: done"); NSApp.terminate(nil); return }
            hub.showPanel(.mirror)
            let t0 = Date()
            DispatchQueue.main.asyncAfter(deadline: .now() + 3.2) { [self] in
                Log.write("mirror test \(n): state=\(hub.mirror.state) after \(String(format: "%.1f", Date().timeIntervalSince(t0))) s")
                hub.showPanel(nil)
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { cycle(n + 1) }
            }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { cycle(1) }
    }

    private func handleSnapshotFlag() {
        let args = CommandLine.arguments
        guard let i = args.firstIndex(of: "--snapshot"), args.count > i + 1 else { return }
        let path = args[i + 1]
        notch.pinned = true
        notch.expand()
        if ProcessInfo.processInfo.environment["CELAH_PANEL"] == "apps" { hub.showPanel(.apps) }   // debug: snapshot a panel
        DispatchQueue.main.asyncAfter(deadline: .now() + 4.0) { [self] in
            notch.snapshot(to: path)
            NSApp.terminate(nil)
        }
    }

    // MARK: - Menu & settings

    func showMenu() {
        let menu = NSMenu()
        menu.addItem(withTitle: "Task Board", action: #selector(openTasks), keyEquivalent: "t").target = self
        menu.addItem(withTitle: "Qur'an — Mushaf Mode", action: #selector(openQuran), keyEquivalent: "m").target = self
        menu.addItem(withTitle: hub.remote.connected.isEmpty ? "Phone Remote…" : "Phone Remote (live)…", action: #selector(openRemote), keyEquivalent: "").target = self
        let settings = menu.addItem(withTitle: "Settings…", action: #selector(openSettings), keyEquivalent: ",")
        settings.target = self
        let login = menu.addItem(withTitle: "Open at login", action: #selector(toggleLaunchAtLogin), keyEquivalent: "")
        login.target = self
        login.state = launchAtLogin ? .on : .off
        menu.addItem(withTitle: "Open Meetings Folder", action: #selector(openMeetings), keyEquivalent: "").target = self
        let reload = menu.addItem(withTitle: "Reload data", action: #selector(reloadAll), keyEquivalent: "r")
        reload.target = self
        menu.addItem(.separator())
        let quit = menu.addItem(withTitle: "Quit Celah", action: #selector(quit), keyEquivalent: "q")
        quit.target = self

        notch.isMenuOpen = true
        let point = notch.panel.mouseLocationOutsideOfEventStream
        menu.popUp(positioning: nil, at: point, in: notch.panel.contentView)
        notch.isMenuOpen = false
        notch.recheckMouse()
    }

    @objc func openSettings() {
        if settingsWindow == nil {
            let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 400, height: 620),
                             styleMask: [.titled, .closable], backing: .buffered, defer: false)
            w.title = "Celah"
            w.isReleasedWhenClosed = false
            w.contentView = NSHostingView(rootView: hub.inject(SettingsView()))
            w.center()
            settingsWindow = w
        }
        NSApp.activate(ignoringOtherApps: true)
        settingsWindow?.makeKeyAndOrderFront(nil)
    }

    @objc func openTasks() {
        if tasksWindow == nil {
            let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 960, height: 560),
                             styleMask: [.titled, .closable, .resizable, .fullSizeContentView], backing: .buffered, defer: false)
            w.title = "Tasks"
            w.titlebarAppearsTransparent = true
            w.backgroundColor = .black
            w.appearance = NSAppearance(named: .darkAqua)
            w.isReleasedWhenClosed = false
            w.contentView = NSHostingView(rootView: hub.inject(TaskBoardView()))
            w.center()
            tasksWindow = w
        }
        notch.collapse()
        NSApp.activate(ignoringOtherApps: true)
        tasksWindow?.makeKeyAndOrderFront(nil)
    }

    @objc func openMeetings() { hub.recorder.openFolder() }

    /// Mushaf Mode: the Qur'an in a big, resizable window (full screen works too).
    @objc func openQuran() {
        if quranWindow == nil {
            let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1120, height: 760),
                             styleMask: [.titled, .closable, .resizable, .miniaturizable, .fullSizeContentView], backing: .buffered, defer: false)
            w.title = "Qur'an"
            w.titlebarAppearsTransparent = true
            w.titleVisibility = .hidden
            w.isReleasedWhenClosed = false
            w.minSize = NSSize(width: 720, height: 520)
            w.collectionBehavior = [.fullScreenPrimary]
            w.contentView = NSHostingView(rootView: hub.inject(QuranReader()))
            w.center()
            w.setFrameAutosaveName("CelahQuranReader")
            quranWindow = w
        }
        notch.collapse()
        NSApp.activate(ignoringOtherApps: true)
        quranWindow?.makeKeyAndOrderFront(nil)
    }

    @objc private func openRemoteFromCLI(_ n: Notification) {
        openRemote()
        guard let path = n.userInfo?["shot"] as? String else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [self] in
            guard let v = remoteWindow?.contentView, let rep = v.bitmapImageRepForCachingDisplay(in: v.bounds) else { return }
            v.cacheDisplay(in: v.bounds, to: rep)
            try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: path))
        }
    }

    @objc func openRemote() {
        if remoteWindow == nil {
            let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 440, height: 580),
                             styleMask: [.titled, .closable, .fullSizeContentView], backing: .buffered, defer: false)
            w.title = "Phone Remote"
            w.appearance = NSAppearance(named: D.p.dark ? .darkAqua : .aqua)
            w.titlebarAppearsTransparent = true
            w.titleVisibility = .hidden
            w.isReleasedWhenClosed = false
            w.contentView = NSHostingView(rootView: hub.inject(RemoteWindow()))
            w.center()
            remoteWindow = w
        }
        notch.collapse()
        NSApp.activate(ignoringOtherApps: true)
        remoteWindow?.makeKeyAndOrderFront(nil)
    }

    @objc private func showMeetingsFromCLI() { showMeetings() }

    func showMeetings() {
        if meetingsWindow == nil {
            let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 460, height: 420),
                             styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
            w.title = "Meetings"
            w.backgroundColor = .black
            w.appearance = NSAppearance(named: .darkAqua)
            w.isReleasedWhenClosed = false
            w.contentView = NSHostingView(rootView: hub.inject(MeetingsPanel()))
            w.center()
            meetingsWindow = w
        }
        notch.collapse()
        NSApp.activate(ignoringOtherApps: true)
        meetingsWindow?.makeKeyAndOrderFront(nil)
    }

    @objc func reloadAll() { hub.refreshAll(force: true) }
    @objc func quit() { NSApp.terminate(nil) }

    var launchAtLogin: Bool { SMAppService.mainApp.status == .enabled }

    @objc func toggleLaunchAtLogin() {
        do {
            if launchAtLogin { try SMAppService.mainApp.unregister() } else { try SMAppService.mainApp.register() }
        } catch {
            NSLog("launch at login: \(error.localizedDescription)")
        }
        hub.settings.objectWillChange.send()
    }
}

enum Fonts {
    static func register() {
        guard let dir = Bundle.main.resourceURL?.appendingPathComponent("Fonts"),
              let files = try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil) else { return }
        for f in files where ["ttf", "otf"].contains(f.pathExtension.lowercased()) {
            CTFontManagerRegisterFontsForURL(f as CFURL, .process, nil)
        }
    }
}
