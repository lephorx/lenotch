import AppKit

/// Measurements of the physical notch (or a virtual one on screens without it)
/// and the sizes the notch grows to in each state.
struct NotchGeometry: Equatable {
    let screenFrame: NSRect
    /// Horizontal centre of the notch in screen coordinates.
    let centerX: CGFloat
    let notchSize: CGSize
    static let openBodyHeight: CGFloat = 166
    static let openWidth: CGFloat = 688

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

    /// The card that drops out of the closed notch to show the current song.
    var peekSize: CGSize {
        CGSize(width: notchSize.width + 240, height: notchSize.height + 58)
    }

    /// The splash the notch grows into for the intro.
    var introSize: CGSize {
        CGSize(width: notchSize.width + 180, height: notchSize.height + 110)
    }

    /// Largest open size (the player and calendar tab); the window is sized for it.
    var openSize: CGSize {
        CGSize(width: min(Self.openWidth, screenFrame.width - 24),
               height: notchSize.height + Self.openBodyHeight)
    }

    /// Open size for a tab whose content needs `contentWidth` × `bodyHeight`, kept wide
    /// enough for the header (tabs and buttons either side of the notch) and within the largest size.
    func openSize(contentWidth: CGFloat, bodyHeight: CGFloat) -> CGSize {
        CGSize(width: min(max(contentWidth, notchSize.width + 340), openSize.width),
               height: notchSize.height + min(bodyHeight, Self.openBodyHeight))
    }

    /// The window is sized for the widest page; the black shape animates inside it.
    var windowFrame: NSRect {
        let size = openSize
        let width = size.width + 2 * NotchShape.openTopRadius
        return NSRect(x: centerX - width / 2, y: screenFrame.maxY - size.height,
                      width: width, height: size.height)
    }

    /// Camera popup: a square hanging from the top of the screen, just right of the open notch.
    static let mirrorSize = CGSize(width: 164, height: 164)
    static let mirrorGap: CGFloat = 10

    /// Beside an open notch of the given width.
    func mirrorWindowFrame(openWidth: CGFloat) -> NSRect {
        let width = Self.mirrorSize.width + 2 * NotchShape.mirrorTopRadius
        let x = centerX + openWidth / 2 + NotchShape.openTopRadius + Self.mirrorGap
        return NSRect(x: x, y: screenFrame.maxY - Self.mirrorSize.height,
                      width: width, height: Self.mirrorSize.height)
    }

    /// Screen-space rect covered by a notch of the given size.
    func rect(for size: CGSize) -> NSRect {
        NSRect(x: centerX - size.width / 2, y: screenFrame.maxY - size.height,
               width: size.width, height: size.height)
    }
}
