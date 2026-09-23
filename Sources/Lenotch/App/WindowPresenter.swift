import AppKit
import SwiftUI

/// Shows SwiftUI views in regular windows. The app runs as a menu bar
/// accessory, so windows have to be brought to the front explicitly.
final class WindowPresenter {
    private var windows: [String: NSWindow] = [:]

    func show<Content: View>(id: String, title: String, content: () -> Content) {
        if let window = windows[id] {
            bringToFront(window)
            return
        }
        let controller = NSHostingController(rootView: content())
        controller.sizingOptions = .preferredContentSize
        let window = NSWindow(contentViewController: controller)
        window.title = title
        window.styleMask = [.titled, .closable, .fullSizeContentView]
        window.titlebarAppearsTransparent = true
        window.isReleasedWhenClosed = false
        window.center()
        windows[id] = window
        bringToFront(window)
    }

    func close(id: String) {
        windows[id]?.close()
    }

    private func bringToFront(_ window: NSWindow) {
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }
}
