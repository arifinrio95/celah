import AppKit
import Combine
import CryptoKit
import Security

/// Phone Remote: see and control this Mac from a phone, from anywhere.
///
/// - A local server on 127.0.0.1 (never on the network directly).
/// - A Cloudflare quick tunnel gives it a public HTTPS address. `cloudflared` is downloaded from Cloudflare's
///   release and only run if it is signed by Cloudflare Inc. (68WVV388M8).
/// - The phone app lives at a fixed address (GitHub Pages). When the tunnel address changes, the Mac posts the
///   new one to a rendezvous topic on ntfy.sh, encrypted with AES-GCM under a key only paired phones have.
/// - Pairing: a QR with a one-time code (3 minutes). Each phone gets its own 256-bit token; revoke any time.
final class RemoteService: ObservableObject {
    enum Tunnel: Equatable { case off, preparing(String), connecting, online(String), failed(String) }
    struct Device: Codable, Identifiable, Equatable { let id: String; var name: String; let tokenHash: String; let created: Date; var lastSeen: Date? }
    final class Session: Identifiable {
        let id: UUID; let socket: RemoteSocket; var device: Device?; var ready = false; var lastSeq = -1
        init(_ s: RemoteSocket) { socket = s; id = s.id }
    }

    static let phoneApp = "https://arifinrio95.github.io/celah/remote/"
    static let origin = "https://arifinrio95.github.io"
    let port: UInt16 = 47800

    @Published var enabled = UserDefaults.standard.bool(forKey: "remote.enabled") {
        didSet { guard enabled != oldValue else { return }; UserDefaults.standard.set(enabled, forKey: "remote.enabled"); enabled ? start() : stop() }
    }
    @Published private(set) var tunnel: Tunnel = .off
    @Published private(set) var pairLink: String?
    @Published private(set) var pairExpires: Date?
    @Published private(set) var devices: [Device] = []
    @Published private(set) var connected: [String] = []       // names of phones connected right now
    @Published private(set) var warning: String?
    @Published var panelOpen = false

    private let http: RemoteHTTPServer
    private let screen = ScreenStreamer()
    private let input = RemoteInput()
    private var sessions: [UUID: Session] = [:]
    private let q = DispatchQueue(label: "id.datasans.celah.remote")
    private var tunnelProc: Process?
    private var publicURL: String?
    private var pairCode: String?
    private var failedAuth: [Date] = []
    private let authLock = NSLock()
    private var republish: Timer?
    private var retryDelay: TimeInterval = 3

    private let topic: String
    private let key: SymmetricKey

    init() {
        let d = UserDefaults.standard
        if let t = d.string(forKey: "remote.topic") { topic = t } else { topic = "celah-" + Self.randomHex(12); d.set(topic, forKey: "remote.topic") }
        if let k = d.data(forKey: "remote.key") { key = SymmetricKey(data: k) } else {
            let k = SymmetricKey(size: .bits256); d.set(k.withUnsafeBytes { Data($0) }, forKey: "remote.key"); key = k
        }
        if let data = d.data(forKey: "remote.devices"), let list = try? JSONDecoder().decode([Device].self, from: data) { devices = list }
        http = RemoteHTTPServer(port: port)
        http.allowedOrigin = Self.origin
        http.route = { [weak self] req in self?.route(req) ?? .text("gone", status: 404) }
        http.acceptSocket = { req in (req.headers["origin"] ?? "") == RemoteService.origin }
        http.onSocket = { [weak self] s in self?.attach(s) }
        screen.onFrameReady = { [weak self] in self?.q.async { self?.pump() } }
        screen.onError = { [weak self] msg in DispatchQueue.main.async { self?.warning = msg }; self?.broadcast(["t": "warn", "msg": msg]) }
    }

    func boot() { if enabled { start() } }

    // MARK: - lifecycle

    private func start() {
        warning = nil
        do { try http.start() } catch { tunnel = .failed("Could not open the local server: \(error.localizedDescription)"); return }
        tunnel = .preparing("Getting the tunnel ready…")
        Task.detached { [weak self] in
            guard let self else { return }
            do {
                let bin = try await Self.cloudflared { msg in DispatchQueue.main.async { self.tunnel = .preparing(msg) } }
                await MainActor.run { self.launchTunnel(bin) }
            } catch {
                await MainActor.run { self.tunnel = .failed(error.localizedDescription) }
            }
        }
    }

    private func stop() {
        republish?.invalidate(); republish = nil
        tunnelProc?.terminate(); tunnelProc = nil
        http.stop()
        q.async { for s in self.sessions.values { s.socket.close() }; self.sessions.removeAll(); self.screen.stop() }
        publicURL = nil; pairLink = nil; pairCode = nil
        tunnel = .off; connected = []
    }

    func shutdown() { tunnelProc?.terminate() }

    // MARK: - tunnel

    private func launchTunnel(_ bin: URL) {
        guard enabled else { return }
        tunnel = .connecting
        // a tunnel left behind by a crashed or killed Celah would keep serving an old address
        Shell.run("/usr/bin/pkill", ["-f", "\(bin.path) tunnel --no-autoupdate --url http://127.0.0.1:\(port)"], timeout: 3)
        let p = Process()
        p.executableURL = bin
        p.arguments = ["tunnel", "--no-autoupdate", "--url", "http://127.0.0.1:\(port)"]
        let err = Pipe(); p.standardError = err; p.standardOutput = FileHandle.nullDevice
        err.fileHandleForReading.readabilityHandler = { [weak self] h in
            let text = String(decoding: h.availableData, as: UTF8.self)
            guard let self, let r = text.range(of: #"https://[a-z0-9-]+\.trycloudflare\.com"#, options: .regularExpression) else { return }
            let url = String(text[r])
            DispatchQueue.main.async { self.online(url) }
        }
        p.terminationHandler = { [weak self] _ in
            DispatchQueue.main.async {
                guard let self, self.enabled, self.tunnelProc === p else { return }
                Log.write("remote: tunnel exited, retrying in \(Int(self.retryDelay)) s")
                self.tunnel = .connecting
                DispatchQueue.main.asyncAfter(deadline: .now() + self.retryDelay) { [weak self] in self?.launchTunnel(bin) }
                self.retryDelay = min(60, self.retryDelay * 2)
            }
        }
        do { try p.run(); tunnelProc = p } catch { tunnel = .failed("cloudflared did not start: \(error.localizedDescription)") }
    }

    private func online(_ url: String) {
        guard publicURL != url else { return }
        publicURL = url
        retryDelay = 3
        tunnel = .online(url)
        Log.write("remote: online")
        publish()
        republish?.invalidate()
        republish = Timer.scheduledTimer(withTimeInterval: 4 * 3600, repeats: true) { [weak self] _ in self?.publish() }
        newPairing()
    }

    /// Posts the current address to the rendezvous topic, sealed so only paired phones can read it.
    private func publish() {
        guard let url = publicURL, let sealed = try? AES.GCM.seal(Data(url.utf8), using: key).combined else { return }
        var req = URLRequest(url: URL(string: "https://ntfy.sh/\(topic)")!)
        req.httpMethod = "POST"
        req.httpBody = Data(Self.b64url(sealed).utf8)
        URLSession.shared.dataTask(with: req) { _, resp, err in
            Log.write("remote: rendezvous \(err == nil ? "posted" : "failed \(err!.localizedDescription)") \((resp as? HTTPURLResponse)?.statusCode ?? 0)")
        }.resume()
    }

    // MARK: - pairing

    /// A fresh one-time QR, valid for three minutes.
    func newPairing() {
        guard let url = publicURL else { return }
        let code = Self.randomHex(12)
        pairCode = code
        pairExpires = Date().addingTimeInterval(180)
        let payload: [String: String] = ["u": url, "c": code, "t": topic, "k": Self.b64url(key.withUnsafeBytes { Data($0) }), "m": Host.current().localizedName ?? "Mac"]
        let json = (try? JSONSerialization.data(withJSONObject: payload)) ?? Data()
        pairLink = Self.phoneApp + "#p=" + Self.b64url(json)
        // debug aid for testing pairing without the window: CELAH_REMOTE_LINK_FILE=/path/in/scratch
        if let f = ProcessInfo.processInfo.environment["CELAH_REMOTE_LINK_FILE"], let link = pairLink { try? link.write(toFile: f, atomically: true, encoding: .utf8) }
    }

    /// Opening the panel always shows a code that still works.
    func freshenPairing() {
        if pairLink == nil || (pairExpires ?? .distantPast) < Date().addingTimeInterval(20) { newPairing() }
    }

    func revoke(_ d: Device) {
        devices.removeAll { $0.id == d.id }
        saveDevices()
        q.async { for s in self.sessions.values where s.device?.id == d.id { s.socket.close() } }
    }

    private func saveDevices() { UserDefaults.standard.set(try? JSONEncoder().encode(devices), forKey: "remote.devices") }

    private func device(forToken token: String) -> Device? {
        let h = Self.sha(token)
        return DispatchQueue.main.sync { devices.first { $0.tokenHash == h } }
    }

    /// More than ten bad codes or tokens in a minute and everything is refused for a while.
    private func throttled() -> Bool {
        authLock.lock(); defer { authLock.unlock() }
        failedAuth = failedAuth.filter { $0.timeIntervalSinceNow > -60 }
        return failedAuth.count >= 10
    }
    private func noteFailure() { authLock.lock(); failedAuth.append(Date()); authLock.unlock() }

    // MARK: - HTTP (runs on the server queue)

    private func route(_ req: RemoteHTTPServer.Request) -> RemoteHTTPServer.Response {
        let path = req.path.split(separator: "?").first.map(String.init) ?? req.path
        switch (req.method, path) {
        case ("GET", "/health"): return .json(["ok": true, "app": "celah"])
        case ("POST", "/api/pair"):
            guard (req.headers["origin"] ?? "") == Self.origin else { return .json(["error": "origin"], status: 403) }
            if throttled() { return .json(["error": "slow down"], status: 429) }
            guard let body = try? JSONSerialization.jsonObject(with: req.body) as? [String: Any],
                  let code = body["code"] as? String else { return .json(["error": "bad request"], status: 400) }
            let name = String((body["name"] as? String ?? "Phone").prefix(40))
            let (ok, expired): (Bool, Bool) = DispatchQueue.main.sync {
                guard let c = pairCode, let exp = pairExpires else { return (false, false) }
                return (Self.constantTimeEqual(c, code) && exp > Date(), exp <= Date())
            }
            guard ok else { noteFailure(); return .json(["error": expired ? "This QR code expired. Show a new one on the Mac." : "Invalid pairing code."], status: 401) }
            let token = Self.randomHex(32)
            let dev = Device(id: UUID().uuidString, name: name, tokenHash: Self.sha(token), created: Date(), lastSeen: Date())
            DispatchQueue.main.async {
                self.devices.append(dev); self.saveDevices()
                self.newPairing()                             // the code is single-use
                Log.write("remote: paired \(name)")
            }
            return .json(["token": token, "mac": Host.current().localizedName ?? "Mac"])
        default:
            return .text("Celah Phone Remote. Open \(Self.phoneApp) on your phone.", status: 404)
        }
    }

    // MARK: - sockets

    private func attach(_ s: RemoteSocket) {
        let session = Session(s)
        q.async { self.sessions[session.id] = session }
        s.onText = { [weak self] text in self?.q.async { self?.handle(session, text) } }
        s.onClose = { [weak self] in self?.q.async { self?.detach(session) } }
        // five seconds to authenticate
        q.asyncAfter(deadline: .now() + 5) { if session.device == nil { s.close() } }
    }

    private func detach(_ s: Session) {
        sessions[s.id] = nil
        if !sessions.values.contains(where: { $0.device != nil }) { screen.stop() }
        updateConnected()
    }

    private func updateConnected() {
        let names = sessions.values.compactMap { $0.device?.name }
        DispatchQueue.main.async { self.connected = names }
    }

    private func handle(_ s: Session, _ text: String) {
        guard let m = try? JSONSerialization.jsonObject(with: Data(text.utf8)) as? [String: Any], let t = m["t"] as? String else { return }
        if s.device == nil {
            guard t == "auth", let token = m["token"] as? String, !throttled() else { s.socket.close(); return }
            guard var dev = device(forToken: token) else {
                noteFailure()
                s.socket.sendThenClose(text: #"{"t":"denied"}"#); return
            }
            dev.lastSeen = Date()
            s.device = dev
            DispatchQueue.main.async {
                if let i = self.devices.firstIndex(where: { $0.id == dev.id }) { self.devices[i].lastSeen = Date(); self.saveDevices() }
            }
            let b = screen.displayBounds
            send(s, ["t": "hello", "mac": Host.current().localizedName ?? "Mac", "w": b.width, "h": b.height, "control": input.trusted])
            if !input.trusted { DispatchQueue.main.async { self.input.askForTrust() } }
            if !screen.isRunning { screen.start() }
            s.ready = true
            updateConnected()
            Log.write("remote: \(dev.name) connected")
            DispatchQueue.main.async { (NSApp.delegate as? AppDelegate)?.notch.cheer(.wired, for: 1.5) }
            return
        }
        let x = m["x"] as? Double, y = m["y"] as? Double
        let at = (x != nil && y != nil) ? input.point(x!, y!) : nil
        switch t {
        case "ack": s.ready = true; pump()
        case "move": if let at { input.move(to: at) }
        case "rel": input.moveBy(m["dx"] as? Double ?? 0, m["dy"] as? Double ?? 0)
        case "click": input.click(right: (m["b"] as? String) == "r", count: m["n"] as? Int ?? 1, at: at)
        case "down": input.press(true, at: at)
        case "up": input.press(false, at: at)
        case "scroll": input.scroll(m["dx"] as? Double ?? 0, m["dy"] as? Double ?? 0)
        case "text": if let str = m["s"] as? String { input.type(String(str.prefix(500))) }
        case "key": if let k = m["k"] as? String { input.key(k, mods: m["m"] as? [String] ?? []) }
        case "quality":
            if let qv = m["q"] as? Double { screen.quality = CGFloat(max(0.2, min(0.85, qv))) }
        default: break
        }
        if !input.trusted, ["move", "rel", "click", "down", "scroll", "text", "key"].contains(t) {
            send(s, ["t": "warn", "msg": "Allow Accessibility for Celah on the Mac so the phone can control it."])
        }
    }

    /// Sends the newest frame to every phone that has drawn the last one.
    private func pump() {
        for s in sessions.values where s.device != nil && s.ready && s.socket.pending < 512 * 1024 {
            guard let (jpeg, seq) = screen.jpeg(), seq != s.lastSeq else { continue }
            s.ready = false; s.lastSeq = seq
            let (cx, cy) = input.normalizedCursor
            s.socket.send(text: String(format: #"{"t":"cur","x":%.4f,"y":%.4f}"#, cx, cy))
            s.socket.send(binary: jpeg)
        }
    }

    private func send(_ s: Session, _ obj: [String: Any]) {
        if let d = try? JSONSerialization.data(withJSONObject: obj) { s.socket.send(text: String(decoding: d, as: UTF8.self)) }
    }
    private func broadcast(_ obj: [String: Any]) { q.async { for s in self.sessions.values where s.device != nil { self.send(s, obj) } } }

    // MARK: - cloudflared

    enum RemoteError: LocalizedError { case download(String), signature
        var errorDescription: String? {
            switch self { case .download(let m): return "Could not get cloudflared: \(m)"
            case .signature: return "The downloaded cloudflared is not signed by Cloudflare, so Celah will not run it." }
        }
    }

    /// Celah's own copy of cloudflared, downloaded once from Cloudflare and checked against Cloudflare's signature.
    static func cloudflared(progress: @escaping (String) -> Void) async throws -> URL {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("Celah/bin", isDirectory: true)
        let bin = dir.appendingPathComponent("cloudflared")
        if FileManager.default.isExecutableFile(atPath: bin.path), verify(bin) { return bin }
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        progress("Downloading cloudflared from Cloudflare (20 MB, once)…")
        let src = URL(string: "https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-darwin-\(isARM ? "arm64" : "amd64").tgz")!
        let (tmp, resp) = try await URLSession.shared.download(from: src)
        guard (resp as? HTTPURLResponse)?.statusCode == 200 else { throw RemoteError.download("HTTP \((resp as? HTTPURLResponse)?.statusCode ?? 0)") }
        let tgz = dir.appendingPathComponent("cloudflared.tgz")
        try? FileManager.default.removeItem(at: tgz)
        try FileManager.default.moveItem(at: tmp, to: tgz)
        progress("Checking Cloudflare's signature…")
        let r = Shell.run("/usr/bin/tar", ["-xzf", tgz.path, "-C", dir.path], timeout: 60)
        try? FileManager.default.removeItem(at: tgz)
        guard r.status == 0, FileManager.default.fileExists(atPath: bin.path) else { throw RemoteError.download("could not unpack") }
        guard verify(bin) else { try? FileManager.default.removeItem(at: bin); throw RemoteError.signature }
        return bin
    }

    private static var isARM: Bool {
        var sysinfo = utsname(); uname(&sysinfo)
        return withUnsafeBytes(of: &sysinfo.machine) { String(decoding: $0.prefix { $0 != 0 }, as: UTF8.self) }.contains("arm64")
    }

    /// Valid signature, anchored at Apple, issued to Cloudflare Inc. (team 68WVV388M8).
    private static func verify(_ url: URL) -> Bool {
        var code: SecStaticCode?
        guard SecStaticCodeCreateWithPath(url as CFURL, [], &code) == errSecSuccess, let code else { return false }
        var req: SecRequirement?
        guard SecRequirementCreateWithString("anchor apple generic and certificate leaf[subject.OU] = \"68WVV388M8\"" as CFString, [], &req) == errSecSuccess else { return false }
        return SecStaticCodeCheckValidity(code, SecCSFlags(rawValue: kSecCSCheckAllArchitectures), req) == errSecSuccess
    }

    // MARK: - helpers

    static func randomHex(_ bytes: Int) -> String {
        var b = [UInt8](repeating: 0, count: bytes)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes, &b)
        return b.map { String(format: "%02x", $0) }.joined()
    }
    static func sha(_ s: String) -> String { SHA256.hash(data: Data(s.utf8)).map { String(format: "%02x", $0) }.joined() }
    static func b64url(_ d: Data) -> String {
        d.base64EncodedString().replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "")
    }
    static func constantTimeEqual(_ a: String, _ b: String) -> Bool {
        let x = Array(a.utf8), y = Array(b.utf8)
        guard x.count == y.count else { return false }
        var diff: UInt8 = 0
        for i in 0..<x.count { diff |= x[i] ^ y[i] }
        return diff == 0
    }
}
