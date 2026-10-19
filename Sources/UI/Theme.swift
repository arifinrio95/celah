import SwiftUI
import AppKit

enum Theme {
    static let accent = Color(red: 0.96, green: 0.72, blue: 0.30)
    static let danger = Color(red: 0.96, green: 0.42, blue: 0.36)
    static let ink = Color.white
    static let ink2 = Color.white.opacity(0.64)
    static let ink3 = Color.white.opacity(0.40)
    static let ink4 = Color.white.opacity(0.18)
    static let hairline = Color.white.opacity(0.10)
    static let track = Color.white.opacity(0.12)

    static func label(_ size: CGFloat = 9.5) -> Font { .system(size: size, weight: .semibold).width(.condensed) }
    static func mono(_ size: CGFloat = 11, _ weight: Font.Weight = .regular) -> Font { .system(size: size, weight: weight, design: .monospaced) }
    static func body(_ size: CGFloat = 12, _ weight: Font.Weight = .regular) -> Font { .system(size: size, weight: weight) }
    static func readout(_ size: CGFloat = 30) -> Font { .system(size: size, weight: .light).monospacedDigit() }

    static func meterColor(_ v: Double) -> Color {
        v >= 0.9 ? danger : (v >= 0.72 ? accent : ink.opacity(0.8))
    }
}

// MARK: - Small building blocks

struct SectionLabel: View {
    let text: String
    var meta: String? = nil
    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(text.uppercased()).font(Theme.label()).tracking(1.6).foregroundStyle(Theme.ink3)
            Spacer(minLength: 8)
            if let meta, !meta.isEmpty {
                Text(meta).font(Theme.mono(9.5)).foregroundStyle(Theme.ink3).lineLimit(1).truncationMode(.middle)
            }
        }
    }
}

struct Meter: View {
    var value: Double
    var tint: Color = Theme.ink.opacity(0.8)
    var height: CGFloat = 3
    var body: some View {
        GeometryReader { g in
            ZStack(alignment: .leading) {
                Rectangle().fill(Theme.track)
                Rectangle().fill(tint).frame(width: max(0, min(1, value)) * g.size.width)
            }
        }
        .frame(height: height)
        .animation(.easeOut(duration: 0.45), value: value)
    }
}

struct HLine: View {
    var body: some View { Rectangle().fill(Theme.hairline).frame(height: 0.5) }
}

struct VLine: View {
    var body: some View { Rectangle().fill(Theme.hairline).frame(width: 0.5) }
}

struct GlyphButton: View {
    let symbol: String
    var size: CGFloat = 12
    var box: CGFloat = 24
    var action: () -> Void
    @State private var hover = false
    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: size, weight: .semibold))
                .foregroundStyle(hover ? Theme.ink : Theme.ink2)
                .frame(width: box, height: box)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
    }
}

struct RingButton: View {
    let symbol: String
    var action: () -> Void
    @State private var hover = false
    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 9.5, weight: .bold))
                .foregroundStyle(hover ? Theme.ink : Theme.ink2)
                .frame(width: 24, height: 24)
                .overlay(Circle().stroke(hover ? Theme.ink3 : Theme.hairline, lineWidth: 1))
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
    }
}

struct AppIconView: View {
    let path: String
    var size: CGFloat = 16
    private static var cache: [String: NSImage] = [:]
    var body: some View {
        Image(nsImage: Self.icon(path))
            .resizable()
            .interpolation(.high)
            .frame(width: size, height: size)
    }
    static func icon(_ path: String) -> NSImage {
        if let i = cache[path] { return i }
        let i = NSWorkspace.shared.icon(forFile: path)
        i.size = NSSize(width: 64, height: 64)
        cache[path] = i
        return i
    }
}

enum Apps {
    static func path(bundleID: String) -> String? {
        NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID)?.path
    }
    static func open(bundleID: String, name: String? = nil) {
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) {
            NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
        } else if let name {
            NSWorkspace.shared.open(URL(fileURLWithPath: "/Applications/\(name).app"))
        }
    }
}

// MARK: - Formatting

enum Fmt {
    static let locale = Locale(identifier: "en_US")

    private static func formatter(_ pattern: String, tz: TimeZone? = nil) -> DateFormatter {
        let f = DateFormatter()
        f.locale = locale
        f.dateFormat = pattern
        if let tz { f.timeZone = tz }
        return f
    }
    private static let hmF = formatter("HH:mm")
    private static let dayLongF = formatter("EEEE, d MMMM")
    private static let dayShortF = formatter("EEE, d MMM")
    private static let weekdayHmF = formatter("EEE HH:mm")
    private static let dayMonthHmF = formatter("d MMM HH:mm")

    static func hm(_ d: Date, tz: TimeZone? = nil) -> String {
        if let tz { return formatter("HH:mm", tz: tz).string(from: d) }
        return hmF.string(from: d)
    }
    static func dayLong(_ d: Date) -> String { dayLongF.string(from: d) }
    static func dayShort(_ d: Date) -> String { dayShortF.string(from: d) }

    static func gb(_ bytes: UInt64) -> String {
        let g = Double(bytes) / 1_073_741_824
        return g >= 100 ? String(format: "%.0f GB", g) : String(format: "%.1f GB", g)
    }
    static func pct(_ v: Double) -> String { String(format: "%.0f%%", v * 100) }

    static func countdown(_ s: TimeInterval) -> String {
        let t = max(0, Int(s.rounded()))
        return String(format: "%02d:%02d:%02d", t / 3600, (t % 3600) / 60, t % 60)
    }
    static func short(_ s: TimeInterval) -> String {
        let t = max(0, Int(s.rounded()))
        return t >= 3600 ? String(format: "%d:%02d:%02d", t / 3600, (t % 3600) / 60, t % 60)
                         : String(format: "%d:%02d", t / 60, t % 60)
    }
    static func clock(_ s: TimeInterval) -> String {
        let t = max(0, Int(s))
        return String(format: "%d:%02d", t / 60, t % 60)
    }

    /// "reset 18:40" today, "reset Sel 09:00" on another day.
    static func reset(_ d: Date?, now: Date = Date()) -> String {
        guard let d else { return "" }
        if Calendar.current.isDate(d, inSameDayAs: now) { return "resets " + hm(d) }
        if d.timeIntervalSince(now) < 6 * 86400 { return "resets " + weekdayHmF.string(from: d) }
        return "resets " + dayMonthHmF.string(from: d)
    }

    static func ago(_ d: Date, now: Date = Date()) -> String {
        let s = Int(now.timeIntervalSince(d))
        if s < 60 { return "just now" }
        if s < 3600 { return "\(s / 60) min ago" }
        return "\(s / 3600) h ago"
    }
}
