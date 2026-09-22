import AppKit
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var panel: NotchPanel?
    private var model: NotchViewModel?
    private var statusItem: NSStatusItem?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        let geometry = NotchGeometry.detectOnPreferredScreen()
        let model = NotchViewModel(geometry: geometry)
        self.model = model

        buildPanel(with: model, geometry: geometry)
        buildStatusItem()

        // Follow the notch when displays are plugged in, resolution changes, or the app is
        // moved to a different screen.
        NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor in self?.repositionForScreenChange() }
            }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    private func buildPanel(with model: NotchViewModel, geometry: NotchGeometry) {
        let frame = NSRect(origin: geometry.panelOrigin, size: geometry.panelSize)
        let panel = NotchPanel(contentRect: frame)

        let host = NSHostingView(rootView: NotchRootView(model: model, settings: model.settings))
        host.frame = NSRect(origin: .zero, size: geometry.panelSize)
        host.autoresizingMask = [.width, .height]
        panel.contentView = host
        panel.setFrame(frame, display: true)
        panel.orderFrontRegardless()
        self.panel = panel
    }

    private func buildStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.image = NSImage(systemSymbolName: "rectangle.topthird.inset.filled",
                                     accessibilityDescription: "LephorNotch")
        item.button?.image?.isTemplate = true

        let menu = NSMenu()
        menu.addItem(withTitle: "Open Notch", action: #selector(openNotch), keyEquivalent: "")
            .target = self
        menu.addItem(withTitle: "Settings", action: #selector(openSettings), keyEquivalent: ",")
            .target = self
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit LephorNotch", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        item.menu = menu
        statusItem = item
    }

    @objc private func openNotch() {
        model?.select(.home)
        model?.open()
    }

    @objc private func openSettings() {
        model?.select(.settings)
        model?.open()
    }

    private func repositionForScreenChange() {
        guard let panel, let model else { return }
        let geometry = NotchGeometry.detectOnPreferredScreen()
        model.updateGeometry(geometry)
        panel.setFrame(NSRect(origin: geometry.panelOrigin, size: geometry.panelSize), display: true)
        panel.orderFrontRegardless()
    }
}
