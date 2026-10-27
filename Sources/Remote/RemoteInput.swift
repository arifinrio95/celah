import AppKit
import CoreGraphics

/// Turns phone gestures into mouse and keyboard events on the Mac. Needs Accessibility for Celah.
final class RemoteInput {
    private var leftDown = false
    var bounds: () -> CGRect = { CGDisplayBounds(CGMainDisplayID()) }

    var trusted: Bool { AXIsProcessTrusted() }
    func askForTrust() {
        let opts = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(opts)
    }

    private var cursor: CGPoint { CGEvent(source: nil)?.location ?? .zero }

    /// x, y are 0…1 over the shared display.
    func point(_ x: Double, _ y: Double) -> CGPoint {
        let b = bounds()
        return CGPoint(x: b.minX + max(0, min(1, x)) * b.width, y: b.minY + max(0, min(1, y)) * b.height)
    }

    func move(to p: CGPoint) {
        post(CGEvent(mouseEventSource: nil, mouseType: leftDown ? .leftMouseDragged : .mouseMoved, mouseCursorPosition: p, mouseButton: .left))
    }

    func moveBy(_ dx: Double, _ dy: Double) {
        let b = bounds(), c = cursor
        move(to: CGPoint(x: max(b.minX, min(b.maxX - 1, c.x + dx)), y: max(b.minY, min(b.maxY - 1, c.y + dy))))
    }

    /// One click. `count` is the click state: the phone sends 1 for a tap and 2 for the second tap of a double tap.
    func click(right: Bool, count: Int, at p: CGPoint?) {
        let pos = p ?? cursor
        if let p { move(to: p) }
        let (down, up, btn): (CGEventType, CGEventType, CGMouseButton) = right ? (.rightMouseDown, .rightMouseUp, .right) : (.leftMouseDown, .leftMouseUp, .left)
        let n = Int64(max(1, min(3, count)))
        let d = CGEvent(mouseEventSource: nil, mouseType: down, mouseCursorPosition: pos, mouseButton: btn)
        let u = CGEvent(mouseEventSource: nil, mouseType: up, mouseCursorPosition: pos, mouseButton: btn)
        d?.setIntegerValueField(.mouseEventClickState, value: n); u?.setIntegerValueField(.mouseEventClickState, value: n)
        post(d); post(u)
    }

    /// Cursor position as 0…1 over the shared display.
    var normalizedCursor: (Double, Double) {
        let b = bounds(), c = cursor
        return (Double((c.x - b.minX) / b.width), Double((c.y - b.minY) / b.height))
    }

    func press(_ down: Bool, at p: CGPoint?) {
        let pos = p ?? cursor
        leftDown = down
        post(CGEvent(mouseEventSource: nil, mouseType: down ? .leftMouseDown : .leftMouseUp, mouseCursorPosition: pos, mouseButton: .left))
    }

    func scroll(_ dx: Double, _ dy: Double) {
        post(CGEvent(scrollWheelEvent2Source: nil, units: .pixel, wheelCount: 2, wheel1: Int32(dy), wheel2: Int32(dx), wheel3: 0))
    }

    func type(_ text: String) {
        for ch in text {
            let utf16 = Array(String(ch).utf16)
            for down in [true, false] {
                let e = CGEvent(keyboardEventSource: nil, virtualKey: 0, keyDown: down)
                e?.keyboardSetUnicodeString(stringLength: utf16.count, unicodeString: utf16)
                post(e)
            }
        }
    }

    static let keys: [String: CGKeyCode] = [
        "return": 36, "tab": 48, "space": 49, "delete": 51, "escape": 53, "forwarddelete": 117,
        "left": 123, "right": 124, "down": 125, "up": 126, "home": 115, "end": 119, "pageup": 116, "pagedown": 121,
        "a": 0, "c": 8, "v": 9, "x": 7, "z": 6, "s": 1, "f": 3, "q": 12, "w": 13, "t": 17, "r": 15, "n": 45,
        "f3": 160, "f11": 103, "grave": 50,
    ]

    func key(_ name: String, mods: [String]) {
        guard let code = Self.keys[name.lowercased()] else { return }
        var flags: CGEventFlags = []
        for m in mods {
            switch m { case "cmd": flags.insert(.maskCommand); case "shift": flags.insert(.maskShift)
            case "opt", "alt": flags.insert(.maskAlternate); case "ctrl": flags.insert(.maskControl); default: break }
        }
        for down in [true, false] {
            let e = CGEvent(keyboardEventSource: nil, virtualKey: code, keyDown: down)
            e?.flags = flags
            post(e)
        }
    }

    private func post(_ e: CGEvent?) { e?.post(tap: .cghidEventTap) }
}
