import AppKit
import Combine
import SwiftUI
import Darwin

/// Running apps with their CPU and memory. Helper processes inside an app bundle (Chrome's renderers, Electron
/// helpers) are added to their app, so a row is what the user thinks of as "the app". Samples `ps` off the main
/// thread every two seconds, only while the panel is open.
final class ProcessMonitor: ObservableObject {
    struct AppUsage: Identifiable, Equatable {
        let id: String              // bundle path
        let name: String
        let pid: pid_t              // the app's own process
        var cpu: Double             // percent of one core, summed over its processes
        var rssKB: Int              // resident memory, summed
        var processes: Int
        let icon: NSImage?
        static func == (a: AppUsage, b: AppUsage) -> Bool { a.id == b.id && a.cpu == b.cpu && a.rssKB == b.rssKB && a.processes == b.processes }
    }
    enum SortKey: String { case cpu, memory }

    @Published var panelOpen = false { didSet { panelOpen ? start() : stop() } }
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
        var byBundle: [String: NSRunningApplication] = [:]
        for app in running { if let p = app.bundleURL?.standardizedFileURL.path { byBundle[p] = app } }
        let n = proc_listallpids(nil, 0)
        guard n > 0 else { return [] }
        var pids = [pid_t](repeating: 0, count: Int(n) + 64)
        let got = Int(proc_listallpids(&pids, Int32(pids.count * MemoryLayout<pid_t>.size)))
        let now = mach_absolute_time()
        let wallNs = lastAt == 0 ? 0 : Double(now - lastAt) * Double(timebase.0) / Double(timebase.1)
        var nextCPU: [pid_t: UInt64] = [:]
        var acc: [String: (cpu: Double, mem: Int, n: Int)] = [:]
        var pathBuf = [CChar](repeating: 0, count: 4096)
        for pid in pids.prefix(got) where pid > 0 {
            guard proc_pidpath(pid, &pathBuf, UInt32(pathBuf.count)) > 0 else { continue }
            let path = String(cString: pathBuf)
            guard let bundle = outermostApp(in: path), byBundle[bundle] != nil else { continue }
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
            var e = acc[bundle] ?? (0, 0, 0)
            e.cpu += cpu; e.mem += Int(ri.ri_phys_footprint / 1024); e.n += 1
            acc[bundle] = e
        }
        lastCPU = nextCPU; lastAt = now
        let me = ProcessInfo.processInfo.processIdentifier
        return acc.compactMap { path, e in
            guard let app = byBundle[path], app.processIdentifier != me else { return nil }
            return AppUsage(id: path, name: app.localizedName ?? URL(fileURLWithPath: path).deletingPathExtension().lastPathComponent,
                            pid: app.processIdentifier, cpu: e.cpu, rssKB: e.mem, processes: e.n, icon: app.icon)
        }
    }

    /// "/Applications/Google Chrome.app/Contents/Frameworks/…/Helper.app/…" → "/Applications/Google Chrome.app"
    private static func outermostApp(in path: String) -> String? {
        guard let r = path.range(of: ".app/") ?? (path.hasSuffix(".app") ? path.range(of: ".app", options: .backwards) : nil) else { return nil }
        return String(path[..<r.upperBound]).replacingOccurrences(of: ".app/", with: ".app")
    }

    /// Force quits an app (and so its helpers). Returns false if macOS refused.
    @discardableResult
    func forceQuit(_ app: AppUsage) -> Bool {
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

