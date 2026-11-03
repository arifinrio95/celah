import AppKit
import Combine
import SwiftUI
import Darwin

/// Running apps with their CPU and memory. Every process is added to the app responsible for it (Chrome's
/// renderers, Safari's web content, the `node` a desktop app starts), so a row is what the user thinks of as
/// "the app". What no app owns goes into one Background row. Samples off the main thread every two seconds,
/// only while the panel is open.
final class ProcessMonitor: ObservableObject {
    struct AppUsage: Identifiable, Equatable {
        let id: String              // bundle path
        let name: String
        let pid: pid_t              // the app's own process; 0 for the Background row
        var isProcess = false       // a heavy process no app owns (a dev server, a script), shown on its own
        var folder: String?         // for such a process: the folder it runs in, so you know which project it is
        var cpu: Double             // percent of one core, summed over its processes
        var rssKB: Int              // physical footprint, summed (Activity Monitor's "Memory")
        var processes: Int
        let icon: NSImage?
        var isBackground: Bool { pid == 0 }
        static let backgroundID = "background"
        static func == (a: AppUsage, b: AppUsage) -> Bool { a.id == b.id && a.cpu == b.cpu && a.rssKB == b.rssKB && a.processes == b.processes }
    }
    enum SortKey: String { case cpu, memory }

    enum Tab: String { case running, storage }
    @Published var panelOpen = false { didSet { updateSampling() } }
    /// Resources shows either running apps or storage; apps are only sampled while their tab is showing.
    @Published var tab: Tab = Tab(rawValue: UserDefaults.standard.string(forKey: "resources.tab") ?? "") ?? .running {
        didSet { UserDefaults.standard.set(tab.rawValue, forKey: "resources.tab"); updateSampling() }
    }
    private func updateSampling() { panelOpen && tab == .running ? start() : stop() }
    @Published private(set) var apps: [AppUsage] = []
    @Published var sort: SortKey = SortKey(rawValue: UserDefaults.standard.string(forKey: "apps.sort") ?? "") ?? .memory {
        didSet { UserDefaults.standard.set(sort.rawValue, forKey: "apps.sort"); apps = sorted(apps) }
    }
    @Published private(set) var loading = false
    @Published var message: String?

    private var timer: Timer?
    private let queue = DispatchQueue(label: "id.datasans.celah.processes", qos: .utility)

    private func start() {
        loading = apps.isEmpty
        refresh()
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in self?.refresh() }
        timer?.tolerance = 0.3
    }

    private func stop() { timer?.invalidate(); timer = nil }

    func refresh() {
        let running = NSWorkspace.shared.runningApplications.filter { $0.activationPolicy == .regular && $0.bundleURL != nil }
        queue.async { [weak self] in
            guard let self else { return }
            var result = Self.sample(running)
            if result.allSatisfy({ $0.cpu == 0 }) { Thread.sleep(forTimeInterval: 0.4); result = Self.sample(running) }
            DispatchQueue.main.async {
                self.apps = self.sorted(result)
                self.loading = false
            }
        }
    }

    private func sorted(_ list: [AppUsage]) -> [AppUsage] {
        list.sorted { sort == .cpu ? ($0.cpu, $0.rssKB) > ($1.cpu, $1.rssKB) : ($0.rssKB, $0.cpu) > ($1.rssKB, $1.cpu) }
    }

    /// One pass over every process via libproc (no subprocess), grouped by the app bundle each executable lives in.
    /// Memory is the physical footprint, the same number Activity Monitor shows; CPU is the change in CPU time
    /// since the previous pass, as a percent of one core.
    private static var lastCPU: [pid_t: UInt64] = [:]
    private static var lastAt: UInt64 = 0
    private static let timebase: (UInt32, UInt32) = { var t = mach_timebase_info_data_t(); mach_timebase_info(&t); return (t.numer, t.denom) }()

    private static func sample(_ running: [NSRunningApplication]) -> [AppUsage] {
        var byBundle: [String: NSRunningApplication] = [:], byPID: [pid_t: NSRunningApplication] = [:]
        for app in running {
            if let p = app.bundleURL?.standardizedFileURL.path { byBundle[p] = app }
            byPID[app.processIdentifier] = app
        }
        let n = proc_listallpids(nil, 0)
        guard n > 0 else { return [] }
        var pids = [pid_t](repeating: 0, count: Int(n) + 64)
        let got = Int(proc_listallpids(&pids, Int32(pids.count * MemoryLayout<pid_t>.size)))
        let now = mach_absolute_time()
        let wallNs = lastAt == 0 ? 0 : Double(now - lastAt) * Double(timebase.0) / Double(timebase.1)
        var nextCPU: [pid_t: UInt64] = [:]
        var acc: [pid_t: (cpu: Double, mem: Int, n: Int)] = [:]      // keyed by the owning app's pid; 0 = background
        var loose: [(pid: pid_t, path: String, cpu: Double, mem: Int)] = []   // processes no app owns
        var pathBuf = [CChar](repeating: 0, count: 4096)
        for pid in pids.prefix(got) where pid > 0 {
            let path = proc_pidpath(pid, &pathBuf, UInt32(pathBuf.count)) > 0 ? String(cString: pathBuf) : ""
            // owner: the app itself, an app whose bundle holds this executable, or the app responsible for it
            let owner = byPID[pid] ?? outermostApp(in: path).flatMap { byBundle[$0] } ?? responsible(pid).flatMap { byPID[$0] }
            var ri = rusage_info_v4()
            let ok = withUnsafeMutablePointer(to: &ri) { ptr in
                ptr.withMemoryRebound(to: rusage_info_t?.self, capacity: 1) { proc_pid_rusage(pid, RUSAGE_INFO_V4, $0) }
            }
            guard ok == 0 else { continue }
            let cpuTime = ri.ri_user_time + ri.ri_system_time                 // mach absolute units
            nextCPU[pid] = cpuTime
            var cpu = 0.0
            if wallNs > 0, let prev = lastCPU[pid], cpuTime >= prev {
                cpu = Double(cpuTime - prev) * Double(timebase.0) / Double(timebase.1) / wallNs * 100
            }
            guard let owner else {
                loose.append((pid, path, cpu, Int(ri.ri_phys_footprint / 1024)))
                continue
            }
            let key = owner.processIdentifier
            var e = acc[key] ?? (0, 0, 0)
            e.cpu += cpu; e.mem += Int(ri.ri_phys_footprint / 1024); e.n += 1
            acc[key] = e
        }
        lastCPU = nextCPU; lastAt = now
        let me = ProcessInfo.processInfo.processIdentifier
        // the heaviest loose processes of this user get rows of their own; the rest is one Background row
        let uid = getuid()
        let heavy = loose.filter { $0.mem >= heavyKB && ownerUID($0.pid) == uid }.sorted { $0.mem > $1.mem }.prefix(4)
        let heavyPIDs = Set(heavy.map(\.pid))
        var processRows: [AppUsage] = heavy.map { l in
            var row = AppUsage(id: "pid-\(l.pid)", name: label(l.pid, path: l.path), pid: l.pid, cpu: l.cpu, rssKB: l.mem, processes: 1,
                               icon: NSImage(systemSymbolName: "terminal.fill", accessibilityDescription: nil))
            row.isProcess = true
            row.folder = workingFolder(l.pid)
            return row
        }
        for l in loose where !heavyPIDs.contains(l.pid) {
            var e = acc[0] ?? (0, 0, 0)
            e.cpu += l.cpu; e.mem += l.mem; e.n += 1
            acc[0] = e
        }
        processRows += acc.compactMap { key, e in
            if key == 0 {
                return AppUsage(id: AppUsage.backgroundID, name: "Background", pid: 0, cpu: e.cpu, rssKB: e.mem,
                                processes: e.n, icon: NSImage(systemSymbolName: "gearshape.2.fill", accessibilityDescription: nil))
            }
            guard key != me, let app = byPID[key] else { return nil }
            let path = app.bundleURL?.standardizedFileURL.path ?? "\(key)"
            return AppUsage(id: path, name: app.localizedName ?? URL(fileURLWithPath: path).deletingPathExtension().lastPathComponent,
                            pid: key, cpu: e.cpu, rssKB: e.mem, processes: e.n, icon: app.icon)
        }
        return processRows
    }

    private static let heavyKB = 400 * 1024

    private static func ownerUID(_ pid: pid_t) -> uid_t? {
        var info = proc_bsdshortinfo()
        let n = proc_pidinfo(pid, PROC_PIDT_SHORTBSDINFO, 0, &info, Int32(MemoryLayout<proc_bsdshortinfo>.size))
        return n == Int32(MemoryLayout<proc_bsdshortinfo>.size) ? info.pbsi_uid : nil
    }

    /// "node · run-scoped-study.ts": for interpreters, the script they run; otherwise the executable's name.
    private static func label(_ pid: pid_t, path: String) -> String {
        let exe = URL(fileURLWithPath: path).lastPathComponent
        let interpreters = ["node", "python", "python3", "ruby", "bun", "deno", "java", "php", "perl"]
        let args = arguments(pid)
        // some servers rename themselves ("next-server (v15.2.0)"); that name says more than "node"
        if let first = args?.first, !first.contains("/"), first != exe, !first.isEmpty { return first }
        guard interpreters.contains(where: { exe == $0 || exe.hasPrefix($0 + ".") || exe.hasPrefix("python3.") }),
              let args else { return exe.isEmpty ? "pid \(pid)" : exe }
        let script = args.dropFirst().first { !$0.hasPrefix("-") && ($0.contains(".") || $0.contains("/")) && !$0.hasPrefix("file:") }
        return script.map { "\(exe) · \(URL(fileURLWithPath: $0).lastPathComponent)" } ?? exe
    }

    /// "~/SINTESA/web": where a process was started.
    private static func workingFolder(_ pid: pid_t) -> String? {
        var info = proc_vnodepathinfo()
        let size = Int32(MemoryLayout<proc_vnodepathinfo>.size)
        guard proc_pidinfo(pid, PROC_PIDVNODEPATHINFO, 0, &info, size) == size else { return nil }
        let path = withUnsafeBytes(of: info.pvi_cdir.vip_path) { String(decoding: $0.prefix { $0 != 0 }, as: UTF8.self) }
        guard !path.isEmpty, path != "/" else { return nil }
        let home = NSHomeDirectory()
        return path.hasPrefix(home) ? "~" + path.dropFirst(home.count) : path
    }

    /// A process's argv via KERN_PROCARGS2 (works for this user's processes).
    private static func arguments(_ pid: pid_t) -> [String]? {
        var mib = [CTL_KERN, KERN_PROCARGS2, pid]
        var size = 0
        guard sysctl(&mib, 3, nil, &size, nil, 0) == 0, size > 4 else { return nil }
        var buf = [UInt8](repeating: 0, count: size)
        guard sysctl(&mib, 3, &buf, &size, nil, 0) == 0 else { return nil }
        let argc = Int(buf.withUnsafeBytes { $0.load(as: Int32.self) })
        var i = 4
        while i < size, buf[i] != 0 { i += 1 }          // executable path
        while i < size, buf[i] == 0 { i += 1 }          // padding
        var args: [String] = []
        while args.count < argc, i < size {
            let start = i
            while i < size, buf[i] != 0 { i += 1 }
            args.append(String(decoding: buf[start..<i], as: UTF8.self))
            i += 1
        }
        return args
    }

    /// The process macOS holds responsible for `pid` (what Activity Monitor groups by). A private but stable libSystem call.
    private typealias ResponsibleFn = @convention(c) (pid_t) -> pid_t
    private static let responsibleFn: ResponsibleFn? = dlsym(UnsafeMutableRawPointer(bitPattern: -2), "responsibility_get_pid_responsible_for_pid")
        .map { unsafeBitCast($0, to: ResponsibleFn.self) }
    private static func responsible(_ pid: pid_t) -> pid_t? {
        guard let f = responsibleFn else { return nil }
        let r = f(pid)
        return r > 0 && r != pid ? r : nil
    }

    /// "/Applications/Google Chrome.app/Contents/Frameworks/…/Helper.app/…" → "/Applications/Google Chrome.app"
    private static func outermostApp(in path: String) -> String? {
        guard let r = path.range(of: ".app/") ?? (path.hasSuffix(".app") ? path.range(of: ".app", options: .backwards) : nil) else { return nil }
        return String(path[..<r.upperBound]).replacingOccurrences(of: ".app/", with: ".app")
    }

    /// Force quits an app (and so its helpers). Returns false if macOS refused.
    @discardableResult
    func forceQuit(_ app: AppUsage) -> Bool {
        if app.isProcess {
            let ok = kill(app.pid, SIGKILL) == 0 || errno == ESRCH
            if ok {
                Log.write("force quit process \(app.name) (pid \(app.pid))")
                withAnimation { apps.removeAll { $0.id == app.id } }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { [weak self] in self?.refresh() }
            } else { message = "macOS refused to quit \(app.name)." }
            return ok
        }
        guard let running = NSRunningApplication(processIdentifier: app.pid) else { message = "\(app.name) already quit."; return true }
        let ok = running.forceTerminate()
        if ok {
            Log.write("force quit \(app.name) (pid \(app.pid))")
            withAnimation { apps.removeAll { $0.id == app.id } }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { [weak self] in self?.refresh() }
        } else {
            message = "macOS refused to quit \(app.name)."
        }
        return ok
    }
}

