import Foundation
import Combine

/// Claude (Claude Code OAuth usage endpoint) and ChatGPT (Codex token → chatgpt.com usage) limits.
final class AIUsage: ObservableObject {
    struct Window: Identifiable {
        let label: String
        let used: Double        // 0…1
        let resetsAt: Date?
        var id: String { label }
    }

    struct Block {
        let name: String
        let bundleID: String
        let tier: String?
        let windows: [Window]
        let note: String?
        var iconPath: String? { Apps.path(bundleID: bundleID) }
    }

    @Published private(set) var claudeBlock = Block(name: "Claude", bundleID: "com.anthropic.claudefordesktop", tier: nil, windows: [], note: "memuat…")
    @Published private(set) var chatgptBlock = Block(name: "ChatGPT", bundleID: "com.openai.codex", tier: nil, windows: [], note: "memuat…")
    @Published private(set) var lastFetched: Date?

    private let q = DispatchQueue(label: "id.datasans.celah.usage", qos: .utility)
    private var inflight = false
    private let session: URLSession = {
        let c = URLSessionConfiguration.ephemeral
        c.timeoutIntervalForRequest = 15
        return URLSession(configuration: c)
    }()

    func refresh(force: Bool) {
        if !force, let t = lastFetched, Date().timeIntervalSince(t) < 90 { return }
        guard !inflight else { return }
        inflight = true
        let group = DispatchGroup()
        group.enter()
        q.async { self.fetchClaude { group.leave() } }
        group.enter()
        q.async { self.fetchChatGPT { group.leave() } }
        group.notify(queue: .main) {
            self.inflight = false
            self.lastFetched = Date()
        }
    }

    // MARK: - Claude

    private func fetchClaude(done: @escaping () -> Void) {
        let tier = Self.claudeTier()
        func finish(_ windows: [Window], _ note: String?) {
            DispatchQueue.main.async {
                self.claudeBlock = Block(name: "Claude", bundleID: "com.anthropic.claudefordesktop", tier: tier, windows: windows, note: note)
                done()
            }
        }
        let cred = Shell.run("/usr/bin/security", ["find-generic-password", "-s", "Claude Code-credentials", "-w"], timeout: 20)
        guard cred.status == 0, let data = cred.out.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let oauth = json["claudeAiOauth"] as? [String: Any] else {
            finish([], "Not signed in · run: claude auth login"); return
        }
        let token = oauth["accessToken"] as? String ?? ""
        let expiresMs = (oauth["expiresAt"] as? NSNumber)?.doubleValue ?? 0
        guard !token.isEmpty else { finish([], "Not signed in · run: claude auth login"); return }
        if expiresMs > 0, expiresMs / 1000 < Date().timeIntervalSince1970 {
            finish([], "Token expired · open Claude Code once"); return
        }
        var req = URLRequest(url: URL(string: "https://api.anthropic.com/api/oauth/usage")!)
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        req.setValue("oauth-2025-04-20", forHTTPHeaderField: "anthropic-beta")
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        req.setValue("Celah/0.1", forHTTPHeaderField: "User-Agent")
        session.dataTask(with: req) { data, resp, err in
            let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
            guard err == nil, let data, code == 200,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                finish([], code == 401 ? "Token rejected · sign in again" : "Could not load (\(code))"); return
            }
            finish(Self.parseClaude(json), nil)
        }.resume()
    }

    private static func parseClaude(_ json: [String: Any]) -> [Window] {
        let order: [(String, String)] = [("five_hour", "5 hrs"), ("seven_day", "Week"), ("seven_day_opus", "Opus/wk"),
                                         ("seven_day_sonnet", "Sonnet/wk"), ("seven_day_oauth_apps", "Apps/wk")]
        var out: [Window] = []
        for (key, label) in order {
            guard let w = json[key] as? [String: Any], let u = (w["utilization"] as? NSNumber)?.doubleValue else { continue }
            let used = u > 1.0 ? u / 100 : (u == 1.0 && key != "five_hour" ? 1.0 : u)
            out.append(Window(label: label, used: min(1, max(0, used)), resetsAt: parseDate(w["resets_at"])))
        }
        // Model-specific windows only matter when they carry something.
        let primary = out.filter { $0.label == "5 hrs" || $0.label == "Week" }
        let extra = out.filter { !($0.label == "5 hrs" || $0.label == "Week") && $0.used > 0.01 }
        return Array((primary + extra).prefix(3))
    }

    private static func claudeTier() -> String? {
        let url = URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent(".claude.json")
        guard let data = try? Data(contentsOf: url),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let acct = json["oauthAccount"] as? [String: Any] else { return nil }
        let tier = (acct["organizationRateLimitTier"] as? String ?? "").lowercased()
        let type = (acct["organizationType"] as? String ?? "").lowercased()
        if tier.contains("max_20x") { return "Max 20×" }
        if tier.contains("max_5x") { return "Max 5×" }
        if type.contains("max") { return "Max" }
        if type.contains("pro") || tier.contains("pro") { return "Pro" }
        if type.contains("team") { return "Team" }
        return nil
    }

    // MARK: - ChatGPT (Codex)

    private func fetchChatGPT(done: @escaping () -> Void) {
        func finish(_ tier: String?, _ windows: [Window], _ note: String?) {
            DispatchQueue.main.async {
                self.chatgptBlock = Block(name: "ChatGPT", bundleID: "com.openai.codex", tier: tier, windows: windows, note: note)
                done()
            }
        }
        let authURL = URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent(".codex/auth.json")
        guard let data = try? Data(contentsOf: authURL),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let tokens = json["tokens"] as? [String: Any],
              let token = tokens["access_token"] as? String, !token.isEmpty else {
            finish(nil, [], "Codex not signed in · run: codex login"); return
        }
        let account = tokens["account_id"] as? String ?? ""
        var req = URLRequest(url: URL(string: "https://chatgpt.com/backend-api/wham/usage")!)
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        if !account.isEmpty { req.setValue(account, forHTTPHeaderField: "ChatGPT-Account-Id") }
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        req.setValue("Celah/0.1", forHTTPHeaderField: "User-Agent")
        session.dataTask(with: req) { data, resp, err in
            let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
            if err == nil, let data, code == 200,
               let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                let plan = Self.planName(json["plan_type"] as? String)
                let windows = Self.parseChatGPT(rateLimit: json["rate_limit"] as? [String: Any])
                finish(plan, windows, windows.isEmpty ? "No limit data" : nil)
                return
            }
            // Offline / expired token: fall back to the last rate_limits event Codex logged.
            if let (plan, windows, at) = Self.fallbackFromSessions() {
                finish(plan, windows, "from Codex log · " + Fmt.ago(at))
            } else {
                finish(nil, [], code == 401 ? "Codex token expired · run codex" : "Could not load (\(code))")
            }
        }.resume()
    }

    private static func planName(_ s: String?) -> String? {
        guard let s, !s.isEmpty else { return nil }
        return s.prefix(1).uppercased() + s.dropFirst()
    }

    private static func windowLabel(seconds: Double) -> String {
        if seconds >= 6 * 86400 { return "Week" }
        if seconds >= 86400 { return "\(Int(seconds / 86400)) d" }
        return "\(Int((seconds / 3600).rounded())) h"
    }

    private static func parseChatGPT(rateLimit: [String: Any]?) -> [Window] {
        guard let rl = rateLimit else { return [] }
        var out: [Window] = []
        for key in ["secondary_window", "primary_window"] {
            guard let w = rl[key] as? [String: Any], let used = (w["used_percent"] as? NSNumber)?.doubleValue else { continue }
            let secs = (w["limit_window_seconds"] as? NSNumber)?.doubleValue ?? 0
            let reset = (w["reset_at"] as? NSNumber).map { Date(timeIntervalSince1970: $0.doubleValue) }
            out.append(Window(label: windowLabel(seconds: secs), used: min(1, max(0, used / 100)), resetsAt: reset))
        }
        return out
    }

    /// Newest `rate_limits` object from ~/.codex/sessions/**/*.jsonl.
    private static func fallbackFromSessions() -> (String?, [Window], Date)? {
        let root = URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent(".codex/sessions")
        guard let e = FileManager.default.enumerator(at: root, includingPropertiesForKeys: [.contentModificationDateKey]) else { return nil }
        var newest: (URL, Date)?
        for case let url as URL in e where url.pathExtension == "jsonl" {
            let m = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? .distantPast
            if newest == nil || m > newest!.1 { newest = (url, m) }
        }
        guard let (url, at) = newest, let text = try? String(contentsOf: url, encoding: .utf8) else { return nil }
        for line in text.split(separator: "\n").reversed() where line.contains("\"rate_limits\"") {
            guard let d = line.data(using: .utf8), let obj = try? JSONSerialization.jsonObject(with: d) as? [String: Any],
                  let payload = obj["payload"] as? [String: Any], let rl = payload["rate_limits"] as? [String: Any] else { continue }
            var out: [Window] = []
            for key in ["secondary", "primary"] {
                guard let w = rl[key] as? [String: Any], let used = (w["used_percent"] as? NSNumber)?.doubleValue else { continue }
                let mins = (w["window_minutes"] as? NSNumber)?.doubleValue ?? 0
                let reset = (w["resets_at"] as? NSNumber).map { Date(timeIntervalSince1970: $0.doubleValue) }
                out.append(Window(label: windowLabel(seconds: mins * 60), used: min(1, max(0, used / 100)), resetsAt: reset))
            }
            if !out.isEmpty { return (planName(rl["plan_type"] as? String), out, at) }
        }
        return nil
    }

    private static func parseDate(_ v: Any?) -> Date? {
        if let n = v as? NSNumber { return Date(timeIntervalSince1970: n.doubleValue) }
        guard let s = v as? String else { return nil }
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = f.date(from: s) { return d }
        f.formatOptions = [.withInternetDateTime]
        return f.date(from: s)
    }
}
