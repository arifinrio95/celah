import AppKit
import SwiftUI
import Combine

/// Lets the first click on the non-activating panel reach SwiftUI controls instead of being swallowed.
final class NotchHostingView: NSHostingView<AnyView> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

/// How the little creature in the notch feels. `base` follows the data; `cheer` overrides it for a moment.
enum Mood: Equatable { case neutral, happy, worried, sleepy, wired, love }

enum WingContent: Equatable {
    case none
    case music
    case awake
    case recording
    case prayer(String)
}

/// Hover state machine + window geometry. The window always has the expanded size;
/// when collapsed it ignores mouse events and the global monitor watches the notch zone.
final class NotchController: ObservableObject {
    @Published private(set) var isExpanded = false
    @Published var pinned = false
    @Published var wing: WingContent = .none
    @Published private(set) var geometry = NotchGeometry.detect()
    /// 0…1, how close the cursor is to the closed notch (the creature peeks out).
    @Published private(set) var proximity: CGFloat = 0
    /// Cursor in screen coordinates, published while the creature can see it.
    @Published private(set) var mouse: CGPoint = .zero
    @Published var baseMood: Mood = .neutral
    @Published private(set) var cheerMood: Mood?
    @Published private(set) var quip: String?
    var mood: Mood { cheerMood ?? baseMood }

    /// The black lip is as wide as the board; the paper tray hangs under it.
    let lipWidth: CGFloat = 840
    let trayWidth: CGFloat = 812
    let trayHeight: CGFloat = 402
    let trayOverlap: CGFloat = 10
    let chinWidth: CGFloat = 78
    let chinDepth: CGFloat = 25
    let shadowPad: CGFloat = 34
    var boardSize: CGSize { CGSize(width: lipWidth, height: geometry.notchHeight + trayHeight - trayOverlap) }
    let ear: CGFloat = 16
    let bottomRadius: CGFloat = 22
    let collapsedRadius: CGFloat = 11
    let musicWing: CGFloat = 46
    let prayerWing: CGFloat = 92

    let panel: NotchPanel
    var isMenuOpen = false
    var onExpand: (() -> Void)?
    var onCollapse: (() -> Void)?

    private var monitors: [Any] = []
    private var expandWork: DispatchWorkItem?
    private var collapseWork: DispatchWorkItem?
    private var pollTimer: Timer?

    init() {
        panel = NotchPanel(frame: .zero)
    }

    // MARK: - Sizes

    var windowSize: CGSize { CGSize(width: boardSize.width + ear * 2 + shadowPad * 2, height: boardSize.height + shadowPad + 40) }

    var collapsedWidth: CGFloat {
        switch wing {
        case .none: return geometry.notchWidth
        case .music, .awake, .recording: return geometry.notchWidth + musicWing * 2
        case .prayer: return geometry.notchWidth + prayerWing * 2
        }
    }
    var collapsedHeight: CGFloat { geometry.notchHeight }
    var currentWidth: CGFloat { isExpanded ? boardSize.width : collapsedWidth }
    var currentHeight: CGFloat { isExpanded ? boardSize.height : collapsedHeight }
    var drawsCollapsed: Bool { geometry.hasNotch || wing != .none }

    private var windowFrame: CGRect {
        CGRect(x: geometry.centerX - windowSize.width / 2, y: geometry.top - windowSize.height,
               width: windowSize.width, height: windowSize.height)
    }
    private var collapsedRect: CGRect {
        let peek = proximity > 0.6 ? chinDepth * 0.7 : 0
        return CGRect(x: geometry.centerX - collapsedWidth / 2, y: geometry.top - collapsedHeight - peek,
                      width: collapsedWidth, height: collapsedHeight + peek)
    }
    private var expandedRect: CGRect {
        CGRect(x: geometry.centerX - boardSize.width / 2 - ear, y: geometry.top - boardSize.height,
               width: boardSize.width + ear * 2, height: boardSize.height)
    }

    // MARK: - Lifecycle

    func install(root: AnyView) {
        let hosting = NotchHostingView(rootView: root)
        hosting.frame = CGRect(origin: .zero, size: windowSize)
        hosting.autoresizingMask = [.width, .height]
        panel.contentView = hosting
    }

    func start() {
        relayout()
        panel.orderFrontRegardless()
        monitors.append(NSEvent.addGlobalMonitorForEvents(matching: [.mouseMoved, .leftMouseDragged]) { [weak self] _ in
            self?.mouseMoved()
        } as Any)
        monitors.append(NSEvent.addLocalMonitorForEvents(matching: [.mouseMoved, .leftMouseDragged, .leftMouseDown]) { [weak self] e in
            if e.type == .leftMouseDown { Log.write("click in panel at \(e.locationInWindow) ignores=\(self?.panel.ignoresMouseEvents ?? true)") }
            self?.mouseMoved(); return e
        } as Any)
        NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification,
                                               object: nil, queue: .main) { [weak self] _ in self?.relayout() }
        // Low-rate safety net in case a mouseMoved event is missed (e.g. cursor warped by another app).
        pollTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in self?.mouseMoved() }
        pollTimer?.tolerance = 0.02
    }

    func relayout() {
        geometry = NotchGeometry.detect()
        panel.setFrame(windowFrame, display: true)
    }

    // MARK: - Hover logic

    func recheckMouse() { mouseMoved() }

    private func mouseMoved() {
        let p = NSEvent.mouseLocation
        trackCreature(p)
        if isExpanded {
            if pinned || isMenuOpen { cancelCollapse(); return }
            if expandedRect.insetBy(dx: -6, dy: -6).contains(p) {
                cancelCollapse()
            } else if collapseWork == nil {
                let w = DispatchWorkItem { [weak self] in self?.collapse() }
                collapseWork = w
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.35, execute: w)
            }
        } else {
            let inside = collapsedRect.insetBy(dx: -6, dy: -3).contains(p)
            let delay = openDelay
            if delay < 0 {
                // click to open: the closed notch takes clicks only while the cursor is on it
                if panel.ignoresMouseEvents == inside { panel.ignoresMouseEvents = !inside }
            } else if inside {
                if !panel.ignoresMouseEvents { panel.ignoresMouseEvents = true }
                if delay == 0 { expand() }
                else if expandWork == nil {
                    let w = DispatchWorkItem { [weak self] in
                        guard let self else { return }
                        self.expandWork = nil
                        if self.collapsedRect.insetBy(dx: -6, dy: -3).contains(NSEvent.mouseLocation) { self.expand() }
                    }
                    expandWork = w
                    DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: w)
                }
            } else {
                if !panel.ignoresMouseEvents { panel.ignoresMouseEvents = true }
                if let w = expandWork { w.cancel(); expandWork = nil }
            }
        }
    }

    /// Seconds to wait before the board opens on hover; negative means "only on click". Set in Settings.
    var openDelay: Double { UserDefaults.standard.object(forKey: "notch.openDelay") == nil ? 0 : UserDefaults.standard.double(forKey: "notch.openDelay") }
    var opensOnClick: Bool { openDelay < 0 }

    private func cancelCollapse() { collapseWork?.cancel(); collapseWork = nil }

    /// Proximity for the peek, and the cursor for the eyes. Publishes only on real change.
    private func trackCreature(_ p: CGPoint) {
        let notchBottom = geometry.top - geometry.notchHeight
        let dx = max(0, abs(p.x - geometry.centerX) - geometry.notchWidth / 2)
        let dy = max(0, notchBottom - p.y)
        let d = hypot(dx, dy)
        var prox = isExpanded ? 0 : max(0, min(1, 1 - (d - 8) / 150))
        if !geometry.hasNotch { prox = 0 }
        if abs(prox - proximity) > 0.015 || (prox == 0 && proximity != 0) {
            withAnimation(.interactiveSpring(response: 0.35, dampingFraction: 0.7)) { proximity = prox }
        }
        if (isExpanded || proximity > 0.05), hypot(p.x - mouse.x, p.y - mouse.y) > 1.5 { mouse = p }
    }

    /// A moment of joy (or whatever mood) that wears off by itself.
    func cheer(_ m: Mood = .happy, for seconds: Double = 1.3) {
        withAnimation(D.snappy) { cheerMood = m }
        let token = UUID(); cheerToken = token
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds) { [weak self] in
            guard let self, self.cheerToken == token else { return }
            withAnimation(D.snappy) { self.cheerMood = nil }
        }
    }
    private var cheerToken = UUID()

    /// Click the creature: it giggles and says something.
    func poke() {
        let lines = ["I live here now.", "Agent's still cooking.", "Drink some water.", "Ship it.", "Nice notch, right?",
                     "Breathe. Then merge.", "Saved you a seat.", "You again! Hi.", "Commit early, commit often.", "Bismillah, deploy."]
        quipIndex = (quipIndex + 1 + Int.random(in: 0..<3)) % lines.count
        withAnimation(D.snappy) { quip = lines[quipIndex] }
        cheer(.love, for: 1.6)
        let token = UUID(); quipToken = token
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.6) { [weak self] in
            guard let self, self.quipToken == token else { return }
            withAnimation(D.springOut) { self.quip = nil }
        }
    }
    private var quipIndex = 0
    private var quipToken = UUID()

    func expand() {
        expandWork = nil
        guard !isExpanded else { return }
        panel.ignoresMouseEvents = false
        withAnimation(D.springIn) { isExpanded = true; proximity = 0 }
        onExpand?()
        Log.write("notch expand")
    }

    func collapse() {
        collapseWork = nil
        guard isExpanded, !pinned else { return }
        withAnimation(D.springOut) { isExpanded = false; quip = nil }
        onCollapse?()
        Log.write("notch collapse")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) { [weak self] in
            guard let self, !self.isExpanded else { return }
            self.panel.ignoresMouseEvents = true
        }
    }

    // MARK: - Snapshot (debug)

    func snapshot(to path: String) {
        guard let v = panel.contentView, let rep = v.bitmapImageRepForCachingDisplay(in: v.bounds) else { return }
        v.cacheDisplay(in: v.bounds, to: rep)
        let size = v.bounds.size
        let out = NSImage(size: size)
        out.lockFocus()
        NSColor(calibratedWhite: 0.55, alpha: 1).setFill()
        NSRect(origin: .zero, size: size).fill()
        NSImage(cgImage: rep.cgImage!, size: size).draw(in: NSRect(origin: .zero, size: size), from: .zero, operation: .sourceOver, fraction: 1)
        out.unlockFocus()
        if let tiff = out.tiffRepresentation, let png = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:]) {
            try? png.write(to: URL(fileURLWithPath: path))
        }
    }
}
