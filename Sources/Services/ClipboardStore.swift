import AppKit
import ApplicationServices
import Combine

struct ClipItem: Codable, Identifiable, Equatable {
    enum Kind: String, Codable { case text, image }

    var id = UUID()
    var kind: Kind
    var text: String?
    var imageFile: String?
    var imageSize: String?
    var source: String?
    var createdAt = Date()
    var pinned = false

    var title: String {
        switch kind {
        case .text:
            let flat = (text ?? "").split(whereSeparator: \.isWhitespace).joined(separator: " ")
            return flat.isEmpty ? "(empty)" : flat
        case .image:
            return "Image"
        }
    }
}

/// Clipboard history. Polls the pasteboard change counter (cheap integer read), records text and images,
/// skips items that password managers mark as concealed or transient, and persists locally.
final class ClipboardStore: ObservableObject {
    static let maxItems = 200
    static let maxImageBytes = 10_000_000
    static let maxTextChars = 50_000

    static let baseDir: URL = {
        let d = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("Celah")
        try? FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
        return d
    }()
    static let jsonURL = baseDir.appendingPathComponent("clipboard.json")
    static let imagesDir: URL = {
        let d = baseDir.appendingPathComponent("clipboard", isDirectory: true)
        try? FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
        return d
    }()
    static func imageURL(_ file: String) -> URL { imagesDir.appendingPathComponent(file) }

    @Published private(set) var items: [ClipItem] = []
    @Published var paused: Bool {
        didSet { UserDefaults.standard.set(paused, forKey: "clip.paused") }
    }
    @Published var panelOpen = false
    @Published var query = ""
    @Published private(set) var flash: String?

    private var lastCount = NSPasteboard.general.changeCount
    private var timer: Timer?
    private var saveWork: DispatchWorkItem?
    private let secretTypes: Set<String> = ["org.nspasteboard.ConcealedType", "org.nspasteboard.TransientType"]

    init() {
        paused = UserDefaults.standard.bool(forKey: "clip.paused")
        if let data = try? Data(contentsOf: Self.jsonURL),
           let decoded = try? JSONDecoder().decode([ClipItem].self, from: data) {
            items = decoded
        }
    }

    var canAutoPaste: Bool { AXIsProcessTrusted() }

    /// Items to show: pinned first, then recency. Search matches text or source app.
    var visible: [ClipItem] {
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        let base = q.isEmpty ? items : items.filter {
            $0.kind == .text ? ($0.text ?? "").lowercased().contains(q) : ($0.source ?? "").lowercased().contains(q)
        }
        return base.filter(\.pinned) + base.filter { !$0.pinned }
    }

    func start() {
        timer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in self?.poll() }
        timer?.tolerance = 0.15
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        if let data = try? JSONEncoder().encode(items) { try? data.write(to: Self.jsonURL, options: .atomic) }
    }

    // MARK: - Capture

    private func poll() {
        let pb = NSPasteboard.general
        guard pb.changeCount != lastCount else { return }
        lastCount = pb.changeCount
        guard !paused else { return }

        let types = Set((pb.types ?? []).map(\.rawValue))
        guard types.isDisjoint(with: secretTypes) else { return }

        let source = NSWorkspace.shared.frontmostApplication?.localizedName
        if let s = pb.string(forType: .string) {
            addText(s, source: source)
        } else if let data = pb.data(forType: .png) ?? pb.data(forType: .tiff) {
            addImage(data, source: source)
        }
    }

    private func addText(_ raw: String, source: String?) {
        let text = String(raw.prefix(Self.maxTextChars))
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        if let i = items.firstIndex(where: { $0.kind == .text && $0.text == text }) {
            var item = items.remove(at: i)
            item.createdAt = Date()
            item.source = source ?? item.source
            items.insert(item, at: 0)
        } else {
            items.insert(ClipItem(kind: .text, text: text, source: source), at: 0)
        }
        trim()
        save()
    }

    private func addImage(_ data: Data, source: String?) {
        guard data.count <= Self.maxImageBytes,
              let rep = NSBitmapImageRep(data: data),
              let png = rep.representation(using: .png, properties: [:]) else { return }
        let name = UUID().uuidString + ".png"
        do { try png.write(to: Self.imageURL(name)) } catch { return }
        items.insert(ClipItem(kind: .image, imageFile: name, imageSize: "\(rep.pixelsWide)×\(rep.pixelsHigh)", source: source), at: 0)
        trim()
        save()
    }

    private func trim() {
        let unpinned = items.filter { !$0.pinned }
        guard unpinned.count > Self.maxItems else { return }
        let drop = Set(unpinned.dropFirst(Self.maxItems).map(\.id))
        for it in items where drop.contains(it.id) { removeFiles(it) }
        items.removeAll { drop.contains($0.id) }
    }

    // MARK: - Actions

    func togglePin(_ id: UUID) {
        guard let i = items.firstIndex(where: { $0.id == id }) else { return }
        items[i].pinned.toggle()
        save()
    }

    func delete(_ id: UUID) {
        guard let i = items.firstIndex(where: { $0.id == id }) else { return }
        removeFiles(items[i])
        items.remove(at: i)
        save()
    }

    func clearUnpinned() {
        for it in items where !it.pinned { removeFiles(it) }
        items.removeAll { !$0.pinned }
        save()
    }

    /// Puts the item back on the pasteboard. If Accessibility is granted, also sends Cmd+V to the frontmost app.
    func copy(_ item: ClipItem) {
        let pb = NSPasteboard.general
        pb.clearContents()
        switch item.kind {
        case .text:
            pb.setString(item.text ?? "", forType: .string)
        case .image:
            if let f = item.imageFile, let img = NSImage(contentsOf: Self.imageURL(f)) {
                pb.writeObjects([img])
            }
        }
        lastCount = pb.changeCount   // our own write must not be recorded again
        panelOpen = false

        let paste = canAutoPaste
        flash = paste ? "Pasted" : "Copied"
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { [weak self] in self?.flash = nil }
        if paste {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.18) {
                let src = CGEventSource(stateID: .combinedSessionState)
                let down = CGEvent(keyboardEventSource: src, virtualKey: 9, keyDown: true)
                let up = CGEvent(keyboardEventSource: src, virtualKey: 9, keyDown: false)
                down?.flags = .maskCommand
                up?.flags = .maskCommand
                down?.post(tap: .cghidEventTap)
                up?.post(tap: .cghidEventTap)
            }
        }
    }

    private func removeFiles(_ item: ClipItem) {
        if let f = item.imageFile { try? FileManager.default.removeItem(at: Self.imageURL(f)) }
    }

    private func save() {
        saveWork?.cancel()
        let snapshot = items
        let url = Self.jsonURL
        let w = DispatchWorkItem {
            if let data = try? JSONEncoder().encode(snapshot) { try? data.write(to: url, options: .atomic) }
        }
        saveWork = w
        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 0.4, execute: w)
    }
}
