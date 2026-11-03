import AppKit
import Combine

/// Storage: what fills the disk, by folder and by file, and what can safely go.
///
/// Cleaning has two tiers. **Safe** is what rebuilds itself (caches, build output, package caches, old logs) and starts
/// ticked. **Review** is yours (old downloads, big old files, copies, backups, models) and starts unticked.
/// Either way Celah only moves things to the Trash, never deletes them, and `StorageGuard` checks every path first.
final class StorageStore: ObservableObject {
    enum Phase: Equatable { case idle, scanning(files: Int, bytes: Int64, at: String), done(Date) }
    enum Tier { case safe, review }

    struct Item: Identifiable, Hashable {
        let url: URL
        let bytes: Int64
        var opened: Date? = nil
        var id: String { url.path }
        var name: String { url.lastPathComponent }
    }

    struct Suggestion: Identifiable {
        let id: String
        let title: String
        let detail: String
        let symbol: String
        let tier: Tier
        var items: [Item]
        var bytes: Int64 { items.reduce(0) { $0 + $1.bytes } }
    }

    @Published private(set) var phase: Phase = .idle
    @Published private(set) var suggestions: [Suggestion] = []
    /// Ticked items, by path. Safe suggestions start fully ticked; review ones start empty.
    @Published var picked: Set<String> = []
    @Published private(set) var topFiles: [Item] = []
    @Published private(set) var disk = (used: Int64(0), free: Int64(0), total: Int64(0))
    @Published private(set) var cleaning = false
    @Published var notice: String?

    private(set) var dirSizes: [String: Int64] = [:]
    private var cancelled = false
    let home = NSHomeDirectory()
    /// Debug aid: scan another folder instead of home (CELAH_SCAN_ROOT).
    private var root: String { ProcessInfo.processInfo.environment["CELAH_SCAN_ROOT"] ?? home }

    init() { refreshDisk() }

    var scanned: Bool { if case .done = phase { return true }; return false }
    var isScanning: Bool { if case .scanning = phase { return true }; return false }

    // MARK: - disk

    func refreshDisk() {
        let v = try? URL(fileURLWithPath: "/").resourceValues(forKeys: [.volumeTotalCapacityKey, .volumeAvailableCapacityForImportantUsageKey])
        let total = Int64(v?.volumeTotalCapacity ?? 0), free = v?.volumeAvailableCapacityForImportantUsage ?? 0
        disk = (max(0, total - free), free, total)
    }

    // MARK: - scan

    func scan() {
        guard !isScanning else { return }
        cancelled = false
        phase = .scanning(files: 0, bytes: 0, at: "")
        notice = nil
        let root = self.root, home = self.home
        let running = Set(NSWorkspace.shared.runningApplications.compactMap { $0.bundleIdentifier?.lowercased() })
        DispatchQueue.global(qos: .utility).async { [weak self] in
            let t0 = Date()
            var lastReport = Date.distantPast
            var skip = StorageScan.skipped(home: home)
            if ProcessInfo.processInfo.environment["CELAH_SCAN_SKIP_PRIVATE"] != nil {      // debug: don't touch the user's private folders
                skip.formUnion(["Desktop", "Documents", "Downloads"].map { home + "/" + $0 })
            }
            let result = StorageScan.run(root: root, skip: skip) { files, bytes, at in
                guard let self else { return false }
                if Date().timeIntervalSince(lastReport) > 0.25 {
                    lastReport = Date()
                    DispatchQueue.main.async { if self.isScanning { self.phase = .scanning(files: files, bytes: bytes, at: at) } }
                }
                return !self.cancelled
            }
            guard let self else { return }
            let stopped = self.cancelled
            let suggestions = stopped ? [] : Self.suggest(from: result, home: home, running: running,
                                                          readDownloads: !skip.contains(home + "/Downloads"))
            Log.write("storage: scanned \(result.files) files, \(result.bytes / 1_000_000) MB in \(String(format: "%.1f", Date().timeIntervalSince(t0))) s")
            DispatchQueue.main.async {
                if stopped { self.phase = .idle; return }
                self.dirSizes = result.dirSizes
                self.topFiles = result.topFiles.prefix(150).map { Item(url: URL(fileURLWithPath: $0.path), bytes: $0.bytes, opened: $0.opened) }
                self.suggestions = suggestions
                self.picked = Set(suggestions.filter { $0.tier == .safe }.flatMap { $0.items.map(\.id) })
                self.phase = .done(Date())
                self.refreshDisk()
            }
        }
    }

    func cancel() { cancelled = true }

    // MARK: - folders

    /// The children of a folder with their sizes, biggest first (folders from the scan, files from disk).
    static func children(of path: String, sizes dirSizes: [String: Int64]) -> [Item] {
        let fm = FileManager.default
        guard let names = try? fm.contentsOfDirectory(atPath: path) else { return [] }
        var out: [Item] = []
        for n in names {
            let p = path + "/" + n
            var isDir: ObjCBool = false
            guard fm.fileExists(atPath: p, isDirectory: &isDir) else { continue }
            let url = URL(fileURLWithPath: p, isDirectory: isDir.boolValue)
            if isDir.boolValue, let s = dirSizes[p] { out.append(Item(url: url, bytes: s)) }
            else if !isDir.boolValue {
                let v = try? url.resourceValues(forKeys: [.totalFileAllocatedSizeKey, .contentAccessDateKey, .isSymbolicLinkKey])
                if v?.isSymbolicLink == true { continue }
                out.append(Item(url: url, bytes: Int64(v?.totalFileAllocatedSize ?? 0), opened: v?.contentAccessDate))
            } else {
                out.append(Item(url: url, bytes: -1))          // not scanned (skipped or unreadable)
            }
        }
        return out.sorted { $0.bytes > $1.bytes }
    }

    // MARK: - suggestions

    private static func suggest(from scan: StorageScan, home: String, running: Set<String>, readDownloads: Bool) -> [Suggestion] {
        let fm = FileManager.default
        let now = Date()
        func size(_ p: String) -> Int64 {
            if let s = scan.dirSizes[p] { return s }
            let v = try? URL(fileURLWithPath: p).resourceValues(forKeys: [.totalFileAllocatedSizeKey])
            return Int64(v?.totalFileAllocatedSize ?? 0)
        }
        func kids(_ p: String, _ keep: (String) -> Bool = { _ in true }) -> [Item] {
            ((try? fm.contentsOfDirectory(atPath: p)) ?? []).filter(keep).compactMap { n in
                let path = p + "/" + n
                let s = size(path)
                return s > 0 ? Item(url: URL(fileURLWithPath: path), bytes: s) : nil
            }.sorted { $0.bytes > $1.bytes }
        }
        func opened(_ p: String) -> Date? {
            let v = try? URL(fileURLWithPath: p).resourceValues(forKeys: [.contentAccessDateKey, .addedToDirectoryDateKey, .contentModificationDateKey])
            return [v?.contentAccessDate, v?.addedToDirectoryDate, v?.contentModificationDate].compactMap { $0 }.max()
        }
        func ago(_ d: Date?, days: Double) -> Bool { (d.map { now.timeIntervalSince($0) } ?? .infinity) > days * 86_400 }
        let H = home + "/"
        var out: [Suggestion] = []
        func add(_ id: String, _ title: String, _ detail: String, _ symbol: String, _ tier: Tier, _ items: [Item]) {
            let ok = items.filter { $0.bytes > 0 && StorageGuard.allows($0.url) }
            if ok.reduce(0, { $0 + $1.bytes }) >= 1_000_000 {
                out.append(Suggestion(id: id, title: title, detail: detail, symbol: symbol, tier: tier, items: ok))
            }
        }

        // safe: rebuilds itself
        add("caches", "App caches", "Apps rebuild these. Skips apps that are open and macOS's own.", "shippingbox", .safe,
            kids(H + "Library/Caches") { n in
                let l = n.lowercased()
                return !l.hasPrefix("com.apple.") && !running.contains(l) && l != "id.datasans.celah" && !l.hasPrefix(".")
            })
        add("derived", "Xcode build files", "DerivedData. Xcode makes it again on the next build.", "hammer", .safe,
            kids(H + "Library/Developer/Xcode/DerivedData"))
        add("simcache", "Simulator caches", "Rebuilt when a simulator starts.", "iphone", .safe,
            kids(H + "Library/Developer/CoreSimulator/Caches"))
        var pkg: [Item] = []
        for p in [".npm/_cacache", ".gradle/caches", ".cargo/registry/cache", ".bun/install/cache"] where fm.fileExists(atPath: H + p) {
            pkg.append(Item(url: URL(fileURLWithPath: H + p), bytes: size(H + p)))
        }
        add("pkgcache", "Package manager caches", "npm, Gradle, Cargo and Bun download these again when needed.", "archivebox", .safe,
            pkg.flatMap { kids($0.url.path) })
        add("logs", "Old logs", "Log files nobody has written to for a month.", "doc.text", .safe,
            kids(H + "Library/Logs").filter { ago(opened($0.url.path), days: 30) })

        // review: yours
        let downloads = readDownloads ? H + "Downloads" : "/nonexistent"
        let installers = kids(downloads) { n in ["dmg", "pkg", "iso", "xip"].contains((n as NSString).pathExtension.lowercased()) }
        add("installers", "Installers in Downloads", "Disk images and packages. Usually done with once the app is installed.", "opticaldiscdrive", .review, installers)
        let installerIDs = Set(installers.map(\.id))
        add("downloads", "Downloads you left alone", "Not opened in 3 months.", "arrow.down.circle", .review,
            kids(downloads) { !$0.hasPrefix(".") }.filter { !installerIDs.contains($0.id) && ago(opened($0.url.path), days: 90) }
                .map { var i = $0; i.opened = opened($0.url.path); return i })
        let idleModules = scan.nodeModules.compactMap { p -> Item? in
            let project = (p as NSString).deletingLastPathComponent
            let touched = [project, project + "/package.json", project + "/src"].compactMap(opened).max()
            guard ago(touched, days: 30) else { return nil }
            return Item(url: URL(fileURLWithPath: p), bytes: size(p), opened: touched)
        }.sorted { $0.bytes > $1.bytes }
        add("node", "node_modules in idle projects", "Projects untouched for a month. `npm install` brings them back.", "cube.box", .review, idleModules)
        add("bigold", "Big files you haven't opened", "Over 500 MB and not opened in 6 months.", "doc.badge.clock", .review,
            scan.topFiles.filter { $0.bytes >= 500_000_000 && ago($0.opened, days: 180) && !$0.path.hasPrefix(H + "Library/") && !$0.path.hasPrefix(H + "Downloads/") }
                .map { Item(url: URL(fileURLWithPath: $0.path), bytes: $0.bytes, opened: $0.opened) })
        // the same file (name and size) in several places: keep the one opened last
        let copies = Dictionary(grouping: scan.topFiles.filter { $0.bytes >= 50_000_000 && !$0.path.hasPrefix(H + "Library/") },
                                by: { "\(($0.path as NSString).lastPathComponent)|\($0.bytes)" })
            .values.filter { $0.count > 1 }
            .flatMap { group in group.sorted { ($0.opened ?? .distantPast) > ($1.opened ?? .distantPast) }.dropFirst() }
            .map { Item(url: URL(fileURLWithPath: $0.path), bytes: $0.bytes, opened: $0.opened) }
            .sorted { $0.bytes > $1.bytes }
        add("copies", "Copies of the same file", "Same name and size in more than one place. The one you opened last is kept.", "doc.on.doc", .review, copies)
        add("devsupport", "iPhone debugging files", "Xcode copies these again when you plug a device in.", "cable.connector", .review,
            kids(H + "Library/Developer/Xcode/iOS DeviceSupport") + kids(H + "Library/Developer/Xcode/macOS DeviceSupport"))
        add("models", "Downloaded AI models", "Ollama and Hugging Face models. Big to download again.", "brain", .review,
            [H + ".ollama/models"].filter { fm.fileExists(atPath: $0) }.map { Item(url: URL(fileURLWithPath: $0), bytes: size($0)) }
                + kids(H + ".cache/huggingface/hub") { $0.hasPrefix("models--") || $0.hasPrefix("datasets--") })
        add("backups", "iPhone backups", "Old device backups made by Finder.", "externaldrive", .review,
            kids(H + "Library/Application Support/MobileSync/Backup"))
        return out
    }

    // MARK: - cleaning

    var pickedBytes: Int64 {
        suggestions.flatMap(\.items).filter { picked.contains($0.id) }.reduce(0) { $0 + $1.bytes }
    }
    func toggle(_ s: Suggestion) {
        let ids = Set(s.items.map(\.id))
        if ids.isSubset(of: picked) { picked.subtract(ids) } else { picked.formUnion(ids) }
    }

    /// Moves everything ticked to the Trash. Nothing is deleted; emptying the Trash stays the user's call.
    func clean() {
        guard !cleaning else { return }
        let jobs = suggestions.flatMap { s in s.items.filter { picked.contains($0.id) } }
        guard !jobs.isEmpty else { return }
        cleaning = true
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            var trashed: Int64 = 0, failed = 0
            var done = Set<String>()
            for item in jobs {
                if Self.moveToTrash(item.url) { done.insert(item.id); trashed += item.bytes } else { failed += 1 }
            }
            Log.write("storage: moved \(done.count) items to the Trash, \(trashed / 1_000_000) MB, \(failed) failed")
            DispatchQueue.main.async {
                guard let self else { return }
                self.cleaning = false
                for i in self.suggestions.indices { self.suggestions[i].items.removeAll { done.contains($0.id) } }
                self.suggestions.removeAll { $0.items.isEmpty }
                self.picked.subtract(done)
                self.forget(done)
                self.refreshDisk()
                var parts: [String] = []
                if trashed > 0 { parts.append("\(Fmt.bytes(trashed)) moved to the Trash. Put anything back from there; the space frees up when you empty the Trash") }
                if failed > 0 { parts.append("\(failed) in use or protected, left alone") }
                self.notice = parts.joined(separator: " · ")
            }
        }
    }

    /// Moves one file or folder to the Trash, from the Folders or Files list.
    func trash(_ item: Item) {
        guard StorageGuard.allows(item.url) else { notice = StorageGuard.reason(item.url); return }
        if Self.moveToTrash(item.url) {
            forget([item.id])
            topFiles.removeAll { $0.id == item.id }
            for i in suggestions.indices { suggestions[i].items.removeAll { $0.id == item.id } }
            refreshDisk()
            notice = "\(item.name) moved to the Trash"
            Log.write("storage: trashed one item, \(item.bytes / 1_000_000) MB")
        } else {
            notice = "Couldn't move \(item.name) to the Trash"
        }
    }

    /// Removes deleted paths from the folder sizes, so the lists add up without a rescan.
    private func forget(_ paths: Set<String>) {
        for p in paths {
            let gone = dirSizes[p] ?? topFiles.first { $0.id == p }?.bytes ?? 0
            dirSizes = dirSizes.filter { $0.key != p && !$0.key.hasPrefix(p + "/") }
            var parent = (p as NSString).deletingLastPathComponent
            while parent.hasPrefix(home), let s = dirSizes[parent] {
                dirSizes[parent] = max(0, s - gone)
                if parent == home { break }
                parent = (parent as NSString).deletingLastPathComponent
            }
        }
    }

    /// The only way Celah removes anything: to the Trash, after the guard says yes.
    private static func moveToTrash(_ url: URL) -> Bool {
        guard StorageGuard.allows(url) else { return false }
        return (try? FileManager.default.trashItem(at: url, resultingItemURL: nil)) != nil
    }

    func reveal(_ item: Item) { NSWorkspace.shared.activateFileViewerSelecting([item.url]) }
}

extension Fmt {
    /// Disk sizes the way Finder shows them (decimal).
    static func bytes(_ b: Int64) -> String {
        if b < 0 { return "—" }
        let d = Double(b)
        func n(_ v: Double, _ unit: String) -> String { String(format: v >= 100 ? "%.0f %@" : "%.1f %@", v, unit) }
        if d >= 1e12 { return String(format: "%.2f TB", d / 1e12) }
        if d >= 1e9 { return n(d / 1e9, "GB") }
        if d >= 1e6 { return n(d / 1e6, "MB") }
        return String(format: "%.0f KB", max(1, d / 1e3))
    }
}
