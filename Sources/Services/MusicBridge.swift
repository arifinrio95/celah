import AppKit
import Combine

/// Now-playing + transport for Spotify and Apple Music via AppleScript (no private MediaRemote APIs).
final class MusicBridge: ObservableObject {
    enum Player: String, CaseIterable {
        case spotify, music
        var bundleID: String { self == .spotify ? "com.spotify.client" : "com.apple.Music" }
        var scriptName: String { self == .spotify ? "Spotify" : "Music" }
        var displayName: String { self == .spotify ? "Spotify" : "Apple Music" }
        var notification: Notification.Name {
            Notification.Name(self == .spotify ? "com.spotify.client.PlaybackStateChanged" : "com.apple.Music.playerInfo")
        }
        var isRunning: Bool { !NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).isEmpty }
    }

    struct NowPlaying: Equatable {
        let player: Player
        let title: String
        let artist: String
        let album: String
        let duration: TimeInterval
        let position: TimeInterval
        let positionAt: Date
        let isPlaying: Bool
        let artKey: String
        let artURL: URL?
    }

    @Published private(set) var now: NowPlaying?
    @Published private(set) var artwork: NSImage?
    @Published private(set) var runningPlayers: [Player] = []

    private let q = DispatchQueue(label: "id.datasans.celah.music", qos: .userInitiated)
    private var artCache: [String: NSImage] = [:]
    /// The player the user last played; remembered across launches.
    @Published private(set) var preferred: Player?
    private var pending = false
    private var bag = Set<AnyCancellable>()

    func start() {
        preferred = UserDefaults.standard.string(forKey: "music.lastPlayer").flatMap(Player.init(rawValue:))
        let dnc = DistributedNotificationCenter.default()
        for p in Player.allCases {
            dnc.addObserver(forName: p.notification, object: nil, queue: .main) { [weak self] _ in
                self?.setPreferred(p)
                self?.scheduleRefresh()
            }
        }
        let ws = NSWorkspace.shared.notificationCenter
        ws.addObserver(forName: NSWorkspace.didLaunchApplicationNotification, object: nil, queue: .main) { [weak self] _ in self?.scheduleRefresh() }
        ws.addObserver(forName: NSWorkspace.didTerminateApplicationNotification, object: nil, queue: .main) { [weak self] _ in self?.scheduleRefresh() }
        refresh()
    }

    func setPreferred(_ p: Player) {
        preferred = p
        UserDefaults.standard.set(p.rawValue, forKey: "music.lastPlayer")
    }

    private func scheduleRefresh() {
        guard !pending else { return }
        pending = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
            self?.pending = false
            self?.refresh()
        }
    }

    func position(at date: Date) -> TimeInterval {
        guard let n = now else { return 0 }
        let p = n.isPlaying ? n.position + date.timeIntervalSince(n.positionAt) : n.position
        return min(max(0, p), n.duration > 0 ? n.duration : p)
    }

    // MARK: - Query

    func refresh() {
        q.async { [weak self] in
            guard let self else { return }
            let running = Player.allCases.filter { $0.isRunning }
            var order = running
            if let pref = self.preferred, let i = order.firstIndex(of: pref) { order.remove(at: i); order.insert(pref, at: 0) }
            var found: NowPlaying?
            for p in order {
                guard let np = self.query(p) else { continue }
                if np.isPlaying { found = np; break }
                if found == nil { found = np }
            }
            DispatchQueue.main.async {
                self.runningPlayers = running
                self.now = found
                if let np = found { self.loadArtwork(for: np) } else { self.artwork = nil }
            }
        }
    }

    private func query(_ p: Player) -> NowPlaying? {
        let script: String
        if p == .spotify {
            script = """
            tell application "Spotify"
                set pstate to player state as text
                try
                    set trk to current track
                    return pstate & "<|>" & (name of trk) & "<|>" & (artist of trk) & "<|>" & (album of trk) & "<|>" & (duration of trk) & "<|>" & (player position) & "<|>" & (artwork url of trk) & "<|>" & (id of trk)
                on error
                    return pstate
                end try
            end tell
            """
        } else {
            script = """
            tell application "Music"
                set pstate to player state as text
                try
                    set trk to current track
                    return pstate & "<|>" & (name of trk) & "<|>" & (artist of trk) & "<|>" & (album of trk) & "<|>" & ((duration of trk) * 1000) & "<|>" & (player position) & "<|>" & "" & "<|>" & (persistent ID of trk)
                on error
                    return pstate
                end try
            end tell
            """
        }
        let r = Shell.osascript(script, timeout: 4)
        guard r.status == 0, !r.out.isEmpty else {
            Log.write("music \(p.rawValue) query failed status=\(r.status) err=\(r.err)")
            return nil
        }
        let parts = r.out.components(separatedBy: "<|>")
        let state = parts[0].lowercased()
        guard parts.count >= 8, state != "stopped" else { return nil }
        func num(_ s: String) -> Double { Double(s.replacingOccurrences(of: ",", with: ".").trimmingCharacters(in: .whitespaces)) ?? 0 }
        let durationMs = num(parts[4])
        return NowPlaying(player: p, title: parts[1], artist: parts[2], album: parts[3],
                          duration: durationMs / 1000, position: num(parts[5]), positionAt: Date(),
                          isPlaying: state == "playing", artKey: p.rawValue + ":" + parts[7],
                          artURL: parts[6].isEmpty ? nil : URL(string: parts[6]))
    }

    private func loadArtwork(for np: NowPlaying) {
        if let img = artCache[np.artKey] { artwork = img; return }
        let key = np.artKey
        if let url = np.artURL {
            URLSession.shared.dataTask(with: url) { [weak self] data, _, _ in
                guard let data, let img = NSImage(data: data) else { return }
                DispatchQueue.main.async { self?.store(img, key: key) }
            }.resume()
        } else if np.player == .music {
            q.async { [weak self] in
                let r = Shell.osascript("""
                tell application "Music"
                    try
                        set trk to current track
                        if (count of artworks of trk) > 0 then return (data of artwork 1 of trk)
                    end try
                    return ""
                end tell
                """, timeout: 6)
                guard let img = Self.decodeAppleScriptData(r.out) else { return }
                DispatchQueue.main.async { self?.store(img, key: key) }
            }
        } else {
            artwork = nil
        }
    }

    private func store(_ img: NSImage, key: String) {
        if artCache.count > 30 { artCache.removeAll() }
        artCache[key] = img
        if now?.artKey == key { artwork = img }
    }

    /// osascript prints raw data as «data XXXX48656C6C6F»; decode the hex payload.
    private static func decodeAppleScriptData(_ s: String) -> NSImage? {
        guard let start = s.range(of: "«data "), let end = s.range(of: "»", range: start.upperBound..<s.endIndex) else { return nil }
        let body = s[start.upperBound..<end.lowerBound]
        guard body.count > 8 else { return nil }
        let hex = body.dropFirst(4)
        var data = Data(capacity: hex.count / 2)
        var idx = hex.startIndex
        while idx < hex.endIndex {
            guard let next = hex.index(idx, offsetBy: 2, limitedBy: hex.endIndex), let b = UInt8(hex[idx..<next], radix: 16) else { break }
            data.append(b)
            idx = next
        }
        return NSImage(data: data)
    }

    // MARK: - Transport

    private func send(_ command: String) {
        guard let p = now?.player ?? runningPlayers.first else { return }
        q.async { [weak self] in
            Shell.osascript("tell application \"\(p.scriptName)\" to \(command)", timeout: 4)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { self?.refresh() }
        }
    }

    func playPause() { send("playpause") }
    func next() { send("next track") }
    func previous() { send("previous track") }
    func seek(to seconds: TimeInterval) {
        let s = String(format: "%.1f", max(0, seconds)).replacingOccurrences(of: ",", with: ".")
        send("set player position to \(s)")
    }
}
