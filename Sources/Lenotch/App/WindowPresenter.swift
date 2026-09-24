import AppKit
import SwiftUI

/// Shows SwiftUI views in regular windows. The app runs as a menu bar
/// accessory, so windows have to be brought to the front explicitly.
final class WindowPresenter {
    private var windows: [String: NSWindow] = [:]
    private var closeObservers: [String: NSObjectProtocol] = [:]

    /// `floating` keeps the window above others, e.g. while permission prompts come and go.
    func show<Content: View>(id: String, title: String, floating: Bool = false, content: () -> Content) {
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
        if floating { window.level = .floating }
        windows[id] = window
        // Release the window and its SwiftUI views when it's closed.
        closeObservers[id] = NotificationCenter.default.addObserver(
            forName: NSWindow.willCloseNotification, object: window, queue: .main
        ) { [weak self] _ in
            guard let self else { return }
            if let observer = self.closeObservers.removeValue(forKey: id) {
                NotificationCenter.default.removeObserver(observer)
            }
            self.windows[id] = nil
            DispatchQueue.main.async { window.contentViewController = nil }
        }
        bringToFront(window)
    }

    /// Keeps every open window above other apps (or back to normal), e.g. around a
    /// permission prompt; bringing them back to the front when released.
    func setFloating(_ floating: Bool) {
        for (id, window) in windows {
            // The setup window always floats.
            window.level = floating || id == "onboarding" ? .floating : .normal
            if !floating { bringToFront(window) }
        }
    }

    func close(id: String) {
        windows[id]?.close()
    }

    private func bringToFront(_ window: NSWindow) {
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }
}
