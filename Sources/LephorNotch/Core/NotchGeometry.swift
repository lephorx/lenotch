import AppKit

/// Physical description of the notch (or a synthetic one on non-notched displays).
struct NotchGeometry: Equatable {
    var screenFrame: CGRect
    var notchSize: CGSize
    /// True when the screen actually has a hardware notch.
    var isHardware: Bool

    /// Size of the pill while collapsed. Slightly taller than the hardware notch so the
    /// rounded shoulders read as part of the notch instead of a bar hanging off it.
    var closedSize: CGSize { CGSize(width: notchSize.width, height: notchSize.height) }

    var openSize: CGSize { CGSize(width: 640, height: 240) }

    /// The panel is always the union of every state so we never resize the window itself,
    /// only the content inside it. Resizing NSWindows mid-animation is what makes most
    /// notch apps stutter.
    var panelSize: CGSize {
        CGSize(width: max(openSize.width, notchSize.width) + 120,
               height: openSize.height + 80)
    }

    var panelOrigin: CGPoint {
        CGPoint(x: screenFrame.midX - panelSize.width / 2,
                y: screenFrame.maxY - panelSize.height)
    }

    static func detect(on screen: NSScreen) -> NotchGeometry {
        let frame = screen.frame
        let topInset = screen.safeAreaInsets.top

        if topInset > 0,
           let left = screen.auxiliaryTopLeftArea,
           let right = screen.auxiliaryTopRightArea {
            let width = frame.width - left.width - right.width
            return NotchGeometry(screenFrame: frame,
                                 notchSize: CGSize(width: width, height: topInset),
                                 isHardware: true)
        }

        // No notch: fake one that matches the menu bar height so the app still works
        // on external displays and older Macs.
        let height = max(NSStatusBar.system.thickness, 24)
        return NotchGeometry(screenFrame: frame,
                             notchSize: CGSize(width: 190, height: height),
                             isHardware: false)
    }

    static func detectOnPreferredScreen() -> NotchGeometry {
        let screen = NSScreen.screens.first(where: { $0.safeAreaInsets.top > 0 })
            ?? NSScreen.main
            ?? NSScreen.screens[0]
        return detect(on: screen)
    }
}
