import AppKit

/// Measurements of the physical notch (or a virtual one on screens without it)
/// and the sizes the notch grows to in each state.
struct NotchGeometry: Equatable {
    let screenFrame: NSRect
    /// Horizontal centre of the notch in screen coordinates.
    let centerX: CGFloat
    let notchSize: CGSize

    static let openWidth: CGFloat = 580
    static let openBodyHeight: CGFloat = 166

    init(screen: NSScreen) {
        screenFrame = screen.frame
        if screen.safeAreaInsets.top > 0,
           let left = screen.auxiliaryTopLeftArea,
           let right = screen.auxiliaryTopRightArea {
            let width = right.minX - left.maxX
            notchSize = CGSize(width: width, height: screen.safeAreaInsets.top)
            centerX = left.maxX + width / 2
        } else {
            let menuBarHeight = screen.frame.maxY - screen.visibleFrame.maxY
            notchSize = CGSize(width: 190, height: menuBarHeight > 0 ? menuBarHeight : 32)
            centerX = screen.frame.midX
        }
    }

    var closedSize: CGSize { notchSize }

    /// Collapsed notch with artwork on the left and bars on the right.
    var liveSize: CGSize {
        CGSize(width: notchSize.width + 2 * (notchSize.height + 12), height: notchSize.height)
    }

    var openSize: CGSize {
        CGSize(width: max(Self.openWidth, notchSize.width + 200),
               height: notchSize.height + Self.openBodyHeight)
    }

    /// The window always has the open size; the black shape animates inside it.
    var windowFrame: NSRect {
        let size = openSize
        let width = size.width + 2 * NotchShape.openTopRadius
        return NSRect(x: centerX - width / 2, y: screenFrame.maxY - size.height,
                      width: width, height: size.height)
    }

    /// Camera popup: a square hanging from the top of the screen, just right of the open notch.
    static let mirrorSize = CGSize(width: 164, height: 164)
    static let mirrorGap: CGFloat = 10

    var mirrorWindowFrame: NSRect {
        let width = Self.mirrorSize.width + 2 * NotchShape.mirrorTopRadius
        let x = centerX + openSize.width / 2 + NotchShape.openTopRadius + Self.mirrorGap
        return NSRect(x: x, y: screenFrame.maxY - Self.mirrorSize.height,
                      width: width, height: Self.mirrorSize.height)
    }

    /// Screen-space rect covered by a notch of the given size.
    func rect(for size: CGSize) -> NSRect {
        NSRect(x: centerX - size.width / 2, y: screenFrame.maxY - size.height,
               width: size.width, height: size.height)
    }
}
