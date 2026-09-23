import AppKit
import SwiftUI

/// Borderless, transparent panel that sits above the menu bar on every space.
final class NotchPanel: NSPanel {
    init(contentRect: NSRect) {
        super.init(contentRect: contentRect,
                   styleMask: [.borderless, .nonactivatingPanel],
                   backing: .buffered, defer: false)
        isFloatingPanel = true
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        isMovable = false
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        level = NSWindow.Level(rawValue: NSWindow.Level.mainMenu.rawValue + 3)
        collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    // The panel is almost never key, and AppKit renders glass and materials in
    // inactive windows with a flat, desaturated look. These private NSWindow hooks
    // make the notch always draw with its active appearance; if a future macOS
    // drops them the overrides are simply never called.
    @objc func _hasActiveAppearance() -> Bool { true }
    @objc func _hasActiveAppearanceIgnoringKeyFocus() -> Bool { true }
}

/// Lets buttons react to the first click without activating the app first.
/// Don't use `.help()` tooltips inside the notch: SwiftUI hosts them in an extra
/// AppKit view that doesn't accept the first click, so the button needs two.
final class NotchHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}
