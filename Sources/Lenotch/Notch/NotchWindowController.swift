import AppKit
import SwiftUI

/// Owns the notch panel: places it on the notched screen, and opens/closes the
/// notch on hover or click, and when files are dragged onto it.
final class NotchWindowController {
    private let panel: NotchPanel
    /// Separate panel for the camera popup to the right of the notch.
    private let mirrorPanel: NotchPanel
    private let model: NotchViewModel
    private var monitors: [Any] = []
    private var pendingTransition: DispatchWorkItem?
    /// Drag pasteboard change count at the last mouse down; a change while
    /// dragging means files (or other content) are being dragged.
    private var dragChangeCount = NSPasteboard(name: .drag).changeCount

    private static let closeDelay = 0.2
    /// Horizontal finger travel (points) that counts as a tab swipe.
    private static let swipeThreshold: CGFloat = 60

    private var swipeDistance: CGFloat = 0
    private var swipeHandled = false
    private var lastScroll = Date.distantPast

    init(media: NowPlayingService, settings: AppSettings, battery: BatteryMonitor, shelf: ShelfStore,
         visualizer: AudioVisualizer, openSettings: @escaping () -> Void) {
        let geometry = NotchGeometry(screen: Self.targetScreen())
        model = NotchViewModel(geometry: geometry, media: media, settings: settings,
                               battery: battery, shelf: shelf, visualizer: visualizer,
                               openSettings: openSettings)
        panel = NotchPanel(contentRect: geometry.windowFrame)
        panel.contentView = NotchHostingView(rootView: NotchView(model: model))
        panel.ignoresMouseEvents = true
        panel.orderFrontRegardless()

        mirrorPanel = NotchPanel(contentRect: geometry.mirrorWindowFrame)
        mirrorPanel.contentView = NotchHostingView(rootView: MirrorPopup(model: model))
        mirrorPanel.ignoresMouseEvents = true
        mirrorPanel.orderFrontRegardless()

        installMouseMonitors()
        #if DEBUG
        installDebugHooks()
        #endif
        NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil, queue: .main
        ) { [weak self] _ in self?.relayout() }
    }

    deinit {
        monitors.forEach(NSEvent.removeMonitor)
    }

    /// Prefer the built-in display with a notch, otherwise the main screen.
    private static func targetScreen() -> NSScreen {
        NSScreen.screens.first { $0.safeAreaInsets.top > 0 } ?? NSScreen.main ?? NSScreen.screens[0]
    }

    private func relayout() {
        model.geometry = NotchGeometry(screen: Self.targetScreen())
        panel.setFrame(model.geometry.windowFrame, display: true)
        mirrorPanel.setFrame(model.geometry.mirrorWindowFrame, display: true)
    }

    // MARK: - Mouse

    private func installMouseMonitors() {
        let events: NSEvent.EventTypeMask = [.mouseMoved, .leftMouseDown, .leftMouseDragged, .leftMouseUp]
        if let global = NSEvent.addGlobalMonitorForEvents(matching: events, handler: { [weak self] event in
            self?.handle(event)
        }) {
            monitors.append(global)
        }
        if let local = NSEvent.addLocalMonitorForEvents(matching: events, handler: { [weak self] event in
            self?.handle(event)
            return event
        }) {
            monitors.append(local)
        }
        // Scroll events only reach the panel while the notch is open and under the pointer.
        if let scroll = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel, handler: { [weak self] event in
            self?.handleSwipe(event) ?? event
        }) {
            monitors.append(scroll)
        }
    }

    // MARK: - Swipe between tabs

    /// Two-finger horizontal swipes (trackpad or Magic Mouse) switch tabs, once per gesture.
    /// Returns nil when the event was used for a swipe.
    private func handleSwipe(_ event: NSEvent) -> NSEvent? {
        guard model.state == .open, model.tabs.count > 1 else { return event }
        // A full shelf scrolls sideways instead (about five files fit without scrolling).
        if model.visibleTab == .shelf, model.shelf.items.count > 5 { return event }
        // Ignore the inertia that keeps scrolling after the fingers lift.
        guard event.momentumPhase.isEmpty else { return swipeHandled ? nil : event }

        let now = Date()
        if event.phase.contains(.began) || (event.phase.isEmpty && now.timeIntervalSince(lastScroll) > 0.35) {
            swipeDistance = 0
            swipeHandled = false
        }
        lastScroll = now

        if abs(event.scrollingDeltaX) > abs(event.scrollingDeltaY) {
            // Normalise to finger movement regardless of the natural scrolling setting.
            swipeDistance += event.isDirectionInvertedFromDevice ? event.scrollingDeltaX : -event.scrollingDeltaX
        }

        if !swipeHandled, abs(swipeDistance) > Self.swipeThreshold {
            swipeHandled = true
            // Fingers moving left bring in the next tab, like paging.
            model.selectTab(offset: swipeDistance < 0 ? 1 : -1)
            NSHapticFeedbackManager.defaultPerformer.perform(.generic, performanceTime: .now)
            return nil
        }
        return swipeHandled ? nil : event
    }

    private func handle(_ event: NSEvent) {
        let location = NSEvent.mouseLocation
        let geometry = model.geometry
        let settings = model.settings

        if event.type == .leftMouseDown {
            dragChangeCount = NSPasteboard(name: .drag).changeCount
        }

        switch model.state {
        case .closed:
            // Grow the hot zone a little so the very top edge of the screen counts.
            let hotZone = geometry.rect(for: model.currentSize).insetBy(dx: -6, dy: -2)
            guard hotZone.contains(location) else {
                cancelPending()
                return
            }

            if event.type == .leftMouseDragged, isDraggingContent,
               settings.shelfEnabled, settings.openShelfOnDrag {
                cancelPending()
                model.selectedTab = .shelf
                setState(.open)
            } else if settings.openMode == .click {
                if event.type == .leftMouseDown { setState(.open) }
            } else if event.type == .mouseMoved {
                schedule(after: settings.hoverDelay) { [weak self] in self?.setState(.open) }
            }

        case .open:
            #if DEBUG
            if debugHoldOpen { return }
            #endif
            let area = geometry.rect(for: geometry.openSize).insetBy(dx: -8, dy: -8)
            // The camera popup counts as part of the notch while it's showing.
            let overMirror = model.isMirrorVisible
                && geometry.mirrorWindowFrame.insetBy(dx: -8, dy: -8).contains(location)
            // Stay open while a button is held, so scrubbing and drags in and out don't cut off.
            let buttonHeld = NSEvent.pressedMouseButtons & 1 != 0
            if area.contains(location) || overMirror || model.isInteracting || buttonHeld {
                cancelPending()
            } else {
                schedule(after: Self.closeDelay) { [weak self] in self?.setState(.closed) }
            }
        }
    }

    private var isDraggingContent: Bool {
        NSPasteboard(name: .drag).changeCount != dragChangeCount
    }

    private func setState(_ state: NotchViewModel.State) {
        guard model.state != state else { return }
        model.state = state
        panel.ignoresMouseEvents = state == .closed
        if state == .closed, model.isMirrorVisible {
            // The camera closes together with the notch.
            model.toggleMirror()
        }
        if state == .open {
            NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now)
        }
    }

    private func schedule(after delay: TimeInterval, _ action: @escaping () -> Void) {
        guard pendingTransition == nil else { return }
        let item = DispatchWorkItem { [weak self] in
            self?.pendingTransition = nil
            action()
        }
        pendingTransition = item
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: item)
    }

    private func cancelPending() {
        pendingTransition?.cancel()
        pendingTransition = nil
    }

    #if DEBUG
    private var debugHoldOpen = false

    /// Debug builds only: drive the notch from the command line while testing by
    /// writing `open`, `hold` (open and stay open), `release`, `mirror` or `close` into LENOTCH_DEBUG_DIR/lenotch-cmd.txt.
    /// The resulting state is written to lenotch-debug.txt next to it.
    private func installDebugHooks() {
        guard let dir = ProcessInfo.processInfo.environment["LENOTCH_DEBUG_DIR"] else { return }
        let command = dir + "/lenotch-cmd.txt", output = dir + "/lenotch-debug.txt"
        Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            guard let self else { return }
            if let text = try? String(contentsOfFile: command, encoding: .utf8) {
                try? FileManager.default.removeItem(atPath: command)
                let parts = text.split(separator: " ").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                switch parts.first ?? "" {
                case "snap":
                    self.debugSnapshot(self.panel, to: dir + "/snap-notch.png")
                    self.debugSnapshot(self.mirrorPanel, to: dir + "/snap-mirror.png")
                case "click" where parts.count == 3:
                    // Point in the notch panel, measured from its top-left corner.
                    if let x = Double(parts[1]), let y = Double(parts[2]) { self.debugClick(x: x, y: y) }
                case "hit" where parts.count == 3:
                    if let x = Double(parts[1]), let y = Double(parts[2]), let content = self.panel.contentView {
                        let point = NSPoint(x: x, y: self.panel.frame.height - y)
                        let hit = content.hitTest(content.convert(point, from: nil))
                        var chain: [String] = []
                        var view = hit
                        while let current = view { chain.append(String(describing: type(of: current))); view = current.superview }
                        NSLog("Lenotch debug: hit (\(x), \(y)) -> \(chain.joined(separator: " < "))")
                    }
                case "open": self.setState(.open)
                case "hold": self.debugHoldOpen = true; self.setState(.open)
                case "release": self.debugHoldOpen = false
                case "mirror": self.model.toggleMirror()
                case "close": self.setState(.closed)
                default: break
                }
            }
            let status = "state=\(self.model.state) mirror=\(self.model.isMirrorVisible) camera=\(self.model.camera.status)\n"
            try? status.write(toFile: output, atomically: true, encoding: .utf8)
        }
    }

    private func debugSnapshot(_ window: NSWindow, to path: String) {
        guard let image = CGWindowListCreateImage(.null, .optionIncludingWindow, CGWindowID(window.windowNumber),
                                                  [.boundsIgnoreFraming, .bestResolution]),
              let png = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:]) else { return }
        try? png.write(to: URL(fileURLWithPath: path))
    }

    private func debugClick(x: Double, y: Double) {
        // Queue a press and, a moment later, a release, like a real click.
        let point = NSPoint(x: x, y: panel.frame.height - y)
        func post(_ type: NSEvent.EventType) {
            guard let event = NSEvent.mouseEvent(with: type, location: point, modifierFlags: [],
                                                 timestamp: ProcessInfo.processInfo.systemUptime,
                                                 windowNumber: panel.windowNumber, context: nil, eventNumber: 0,
                                                 clickCount: 1, pressure: type == .leftMouseDown ? 1 : 0) else { return }
            NSApp.postEvent(event, atStart: false)
        }
        post(.leftMouseDown)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) { post(.leftMouseUp) }
    }
    #endif

}
