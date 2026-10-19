import Foundation

/// Tiny append-only log at ~/Library/Logs/Celah.log (never logs tokens or event titles).
enum Log {
    private static let url = URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Logs/Celah.log")
    private static let q = DispatchQueue(label: "id.datasans.celah.log", qos: .utility)
    private static let f: DateFormatter = { let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd HH:mm:ss"; return f }()

    static func write(_ msg: String) {
        q.async {
            let line = "\(f.string(from: Date())) \(msg)\n"
            if let h = try? FileHandle(forWritingTo: url) {
                h.seekToEndOfFile(); h.write(line.data(using: .utf8)!); try? h.close()
            } else {
                try? line.write(to: url, atomically: true, encoding: .utf8)
            }
        }
    }
}
