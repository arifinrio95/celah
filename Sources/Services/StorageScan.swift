import Foundation

/// One pass over a folder tree: the size of every folder, the biggest files, and the `node_modules` folders it met.
/// Pure Foundation so it can be tested on its own. Sizes are allocated bytes (what the disk actually spends).
struct StorageScan {
    struct FileHit { let path: String; let bytes: Int64; let opened: Date? }

    let root: String
    var dirSizes: [String: Int64] = [:]
    var topFiles: [FileHit] = []
    var nodeModules: [String] = []
    var files = 0
    var bytes: Int64 = 0
    var unreadable = 0

    /// Folders that are never read: other apps' sandboxes (reading them makes macOS ask for permission), iCloud's
    /// placeholders, and private stores macOS guards anyway.
    static func skipped(home: String) -> Set<String> {
        ["Library/Containers", "Library/Group Containers", "Library/Mobile Documents", "Library/Mail", "Library/Messages",
         "Library/Metadata/CoreSpotlight", "Library/Biome", "Library/Suggestions", "Library/Safari", "Library/Cookies",
         "Library/Accounts", "Library/Keychains", "Library/Calendars", "Library/HomeKit", "Library/IdentityServices"]
            .reduce(into: Set<String>()) { $0.insert(home + "/" + $1) }
    }

    /// Walks `root`, calling `progress` now and then (on the scanning thread). Return false from it to stop.
    static func run(root: String, skip: Set<String>, topCount: Int = 200,
                    progress: (_ files: Int, _ bytes: Int64, _ at: String) -> Bool) -> StorageScan {
        var scan = StorageScan(root: root)
        let keys: [URLResourceKey] = [.isDirectoryKey, .isSymbolicLinkKey, .totalFileAllocatedSizeKey, .fileAllocatedSizeKey, .contentAccessDateKey]
        let keySet = Set(keys)
        guard let e = FileManager.default.enumerator(at: URL(fileURLWithPath: root), includingPropertiesForKeys: keys, options: [],
                                                     errorHandler: { _, _ in scan.unreadable += 1; return true }) else { return scan }
        // folder sizes with a stack: entries come parent-first, so a folder is finished when the walk climbs back above it
        var stack: [(path: String, size: Int64)] = [(root, 0)]
        func pop() {
            let done = stack.removeLast()
            scan.dirSizes[done.path] = done.size
            stack[stack.count - 1].size += done.size
        }
        var smallest: Int64 = 0                     // size of the smallest file currently in topFiles (once full)
        var stopped = false
        while let url = e.nextObject() as? URL {
            let level = e.level
            while stack.count > level { pop() }
            let path = url.path
            guard let v = try? url.resourceValues(forKeys: keySet) else { continue }
            if v.isSymbolicLink == true { continue }
            if v.isDirectory == true {
                if skip.contains(path) { e.skipDescendants(); continue }
                if url.lastPathComponent == "node_modules", !path.dropLast(13).contains("/node_modules") { scan.nodeModules.append(path) }
                stack.append((path, 0))
                continue
            }
            let size = Int64(v.totalFileAllocatedSize ?? v.fileAllocatedSize ?? 0)
            stack[stack.count - 1].size += size
            scan.files += 1
            scan.bytes += size
            if scan.topFiles.count < topCount || size > smallest {
                scan.topFiles.append(FileHit(path: path, bytes: size, opened: v.contentAccessDate))
                if scan.topFiles.count > topCount * 2 {           // trim in batches, not on every insert
                    scan.topFiles.sort { $0.bytes > $1.bytes }
                    scan.topFiles.removeLast(scan.topFiles.count - topCount)
                    smallest = scan.topFiles.last?.bytes ?? 0
                }
            }
            if scan.files % 4000 == 0, !progress(scan.files, scan.bytes, url.deletingLastPathComponent().path) { stopped = true; break }
        }
        if !stopped { while stack.count > 1 { pop() } }
        scan.dirSizes[root] = stack[0].size
        scan.topFiles.sort { $0.bytes > $1.bytes }
        if scan.topFiles.count > topCount { scan.topFiles.removeLast(scan.topFiles.count - topCount) }
        return scan
    }
}

/// What Celah may move to the Trash, decided by path alone. Celah never deletes anything for good: everything it
/// removes goes to the Trash, where you can put it back. And everything goes through here, so a bug elsewhere cannot
/// reach a keychain, a photo library, a git repository's insides or a Documents folder by accident.
enum StorageGuard {
    static let home = NSHomeDirectory()

    /// Folders that are never removed and never emptied by Celah, nor anything inside them.
    static let sealed: [String] = [
        "Library/Keychains", "Library/Mobile Documents", "Library/Mail", "Library/Messages", "Library/Containers",
        "Library/Group Containers", "Library/Accounts", "Library/Cookies", "Library/Preferences", "Library/Calendars",
        "Library/Photos", "Library/Application Support/AddressBook", "Library/IdentityServices", "Library/Biome",
        ".ssh", ".gnupg", ".aws", ".kube", ".docker", ".config", ".codex", ".claude", ".local/share/keyrings",
    ].map { home + "/" + $0 }

    /// Folders the user keeps things in: their contents can go to the Trash, but never the folders themselves.
    static let roots: [String] = ["", "Desktop", "Documents", "Downloads", "Pictures", "Movies", "Music", "Public", "Applications",
                                  "Library", "Library/Caches", "Library/Logs", "Library/Developer", "Library/Application Support"]
        .map { $0.isEmpty ? home : home + "/" + $0 }

    /// Inside ~/Library only these can be sent to the Trash; the rest belongs to apps.
    static let libraryTrashable: [String] = ["Library/Application Support/MobileSync/Backup", "Library/Caches", "Library/Logs",
                                             "Library/Developer/Xcode/DerivedData", "Library/Developer/CoreSimulator/Caches",
                                             "Library/Developer/Xcode/iOS DeviceSupport", "Library/Developer/Xcode/macOS DeviceSupport"].map { home + "/" + $0 }

    static func allows(_ url: URL) -> Bool { reason(url) == nil }

    private static func isDirectory(_ p: String) -> Bool {
        var d: ObjCBool = false
        return FileManager.default.fileExists(atPath: p, isDirectory: &d) && d.boolValue
    }

    /// Why Celah won't remove this, or nil if it may.
    static func reason(_ url: URL) -> String? {
        let p = url.standardizedFileURL.resolvingSymlinksInPath().path
        if roots.contains(p) { return "A main folder of your Mac" }
        guard p.hasPrefix(home + "/") else { return "Outside your home folder" }
        if roots.contains(where: { $0.hasPrefix(p + "/") }) || sealed.contains(where: { $0.hasPrefix(p + "/") }) { return "Holds folders macOS needs" }
        if sealed.contains(where: { p == $0 || p.hasPrefix($0 + "/") }) { return "Private data macOS or your tools rely on" }
        let parts = p.split(separator: "/")
        if parts.contains(where: { $0 == ".git" }) { return "Inside a git repository's history" }
        if parts.contains(where: { $0.hasSuffix(".photoslibrary") || $0.hasSuffix(".musiclibrary") || $0.hasSuffix(".tvlibrary") }) { return "Inside a Photos or Music library" }
        if url.hasDirectoryPath || isDirectory(p) {
            if (p as NSString).deletingLastPathComponent == home { return "A main folder in your home. Use Finder if you really mean it" }
            if FileManager.default.fileExists(atPath: p + "/.git") { return "A code project with its history. Use Finder if you really mean it" }
        }
        if p.hasPrefix(home + "/Library/"), !libraryTrashable.contains(where: { p.hasPrefix($0 + "/") }) { return "Belongs to an app" }
        if p.hasPrefix(home + "/.Trash/") { return "Already in the Trash" }
        return nil
    }
}
