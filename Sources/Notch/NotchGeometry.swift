import AppKit

/// Where the notch is, in screen coordinates (origin bottom-left, like AppKit).
struct NotchGeometry: Equatable {
    let screenFrame: CGRect
    let hasNotch: Bool
    let notchWidth: CGFloat
    let notchHeight: CGFloat

    var centerX: CGFloat { screenFrame.midX }
    var top: CGFloat { screenFrame.maxY }

    static func detect() -> NotchGeometry {
        let screens = NSScreen.screens
        if let s = screens.first(where: { $0.safeAreaInsets.top > 0 }),
           let l = s.auxiliaryTopLeftArea, let r = s.auxiliaryTopRightArea {
            return NotchGeometry(screenFrame: s.frame, hasNotch: true,
                                 notchWidth: r.minX - l.maxX, notchHeight: s.safeAreaInsets.top)
        }
        let s = NSScreen.main ?? screens[0]
        let menuBar = max(24, s.frame.maxY - s.visibleFrame.maxY)
        return NotchGeometry(screenFrame: s.frame, hasNotch: false, notchWidth: 200, notchHeight: menuBar)
    }
}
