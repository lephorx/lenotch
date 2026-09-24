import AppKit
import SwiftUI

/// Owns the notch panel: places it on the notched screen, and opens/closes the
/// notch on hover or click, and when files are dragged onto it.
final class NotchWindowController {
    private let panel: NotchPanel
    /// Separate panel for the camera popup to the right of the notch.
    private let mirrorPanel: NotchPanel
    /// Speech bubble below the notch for the hovered AI usage ring; never takes the mouse.
    private let tooltipPanel: NotchPanel
    private static let tooltipHeight: CGFloat = 320
    private let model: NotchViewModel
    private var monitors: [Any] = []
    private var pendingTransition: DispatchWorkItem?
    private var introEnd: DispatchWorkItem?
    /// Drag pasteboard change count at the last mouse down; a change while
    /// dragging means files (or other content) are being dragged.
    private var dragChangeCount = NSPasteboard(name: .drag).changeCount

    private static let closeDelay = 0.2
    private static let peekDuration = 3.0

    /// Opened with the keyboard shortcut: stays open until the shortcut, a click
    /// elsewhere, or the pointer entering and then leaving the notch.
    private var openedByKeyboard = false
    private var peekEnd: DispatchWorkItem?
    /// Horizontal finger travel (points) that counts as a tab swipe.
    private static let swipeThreshold: CGFloat = 60

    private var swipeDistance: CGFloat = 0
    private var verticalSwipeDistance: CGFloat = 0
    /// After a swipe closes the notch, hovering doesn't reopen it until the pointer
    /// has left the notch once.
    private var hoverOpenBlocked = false
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

        mirrorPanel = NotchPanel(contentRect: geometry.mirrorWindowFrame(openWidth: geometry.openSize.width))
        mirrorPanel.contentView = NotchHostingView(rootView: MirrorPopup(model: model))
        mirrorPanel.ignoresMouseEvents = true
        mirrorPanel.orderFrontRegardless()

        tooltipPanel = NotchPanel(contentRect: NSRect(x: 0, y: 0, width: UsageTooltip.width, height: Self.tooltipHeight))
        tooltipPanel.contentView = NotchHostingView(rootView: UsageTooltip(model: model))
        tooltipPanel.ignoresMouseEvents = true
        tooltipPanel.orderFrontRegardless()
        model.onUsageHoverChange = { [weak self] in self?.positionTooltip() }
        model.onOpenSizeChange = { [weak self] in self?.positionMirror() }

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

    /// Puts the usage bubble just below the open notch, centred on the hovered ring.
    private func positionTooltip() {
        guard let hover = model.usageHover else { return }
        let screen = model.geometry.screenFrame
        let notchBottom = screen.maxY - model.currentSize.height
        let ringX = panel.frame.minX + hover.anchorX
        let x = min(max(ringX - UsageTooltip.width / 2, screen.minX + 8), screen.maxX - UsageTooltip.width - 8)
        tooltipPanel.setFrame(NSRect(x: x, y: notchBottom - 2 - Self.tooltipHeight,
                                     width: UsageTooltip.width, height: Self.tooltipHeight), display: true)
    }

    /// Prefer the built-in display with a notch, otherwise the main screen.
    private static func targetScreen() -> NSScreen {
        NSScreen.screens.first { $0.safeAreaInsets.top > 0 } ?? NSScreen.main ?? NSScreen.screens[0]
    }

    private func relayout() {
        model.geometry = NotchGeometry(screen: Self.targetScreen())
        panel.setFrame(model.geometry.windowFrame, display: true)
        positionMirror()
    }

    /// Keeps the camera popup just right of the open notch, whose width depends on the page.
    private func positionMirror() {
        mirrorPanel.setFrame(model.geometry.mirrorWindowFrame(openWidth: model.openWidth), display: true)
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
    /// Two-finger swipes on the open notch: sideways switches tabs, up closes it.
    private func handleSwipe(_ event: NSEvent) -> NSEvent? {
        guard model.state == .open else { return event }
        #if DEBUG
        if debugHoldOpen { return event }
        #endif
        // Sideways swipes scroll the calendar's day strip and a full shelf instead
        // (about five files fit without scrolling); vertical ones scroll the event list.
        let canSwitchTabs = model.pages.count > 1 && !model.isOverHorizontalScroller
            && !(model.visiblePage == .shelf && model.shelf.items.count > 5)
        let canClose = !model.isOverVerticalScroller
        // Ignore the inertia that keeps scrolling after the fingers lift.
        guard event.momentumPhase.isEmpty else { return swipeHandled ? nil : event }

        let now = Date()
        if event.phase.contains(.began) || (event.phase.isEmpty && now.timeIntervalSince(lastScroll) > 0.35) {
            swipeDistance = 0
            verticalSwipeDistance = 0
            swipeHandled = false
        }
        lastScroll = now

        // Normalise to finger movement regardless of the natural scrolling setting
        // (right and up are positive).
        let inverted = event.isDirectionInvertedFromDevice
        if abs(event.scrollingDeltaX) > abs(event.scrollingDeltaY) {
            guard canSwitchTabs else { return event }
            swipeDistance += inverted ? event.scrollingDeltaX : -event.scrollingDeltaX
        } else {
            guard canClose else { return event }
            verticalSwipeDistance += inverted ? -event.scrollingDeltaY : event.scrollingDeltaY
        }

        if !swipeHandled, verticalSwipeDistance > Self.swipeThreshold {
            swipeHandled = true
            // Fingers moving up close the notch, like flicking it back into the menu bar.
            cancelPending()
            setState(.closed)
            hoverOpenBlocked = true
            NSHapticFeedbackManager.defaultPerformer.perform(.generic, performanceTime: .now)
            return nil
        }

        if !swipeHandled, abs(swipeDistance) > Self.swipeThreshold {
            swipeHandled = true
            // Fingers moving left bring in the next tab, like paging.
            model.selectPage(offset: swipeDistance < 0 ? 1 : -1)
            NSHapticFeedbackManager.defaultPerformer.perform(.generic, performanceTime: .now)
            return nil
        }
        return swipeHandled ? nil : event
    }

    /// Plays the logo intro in the notch.
    func playIntro() {
        guard !model.isShowingIntro else { return }
        hideAppearancePreview()
        setState(.closed)
        cancelPending()
        peekEnd?.cancel()
        model.isPeeking = false
        panel.ignoresMouseEvents = true
        introEnd?.cancel()
        model.introGeneration = UUID()
        model.isShowingIntro = true
        // SwiftUI may cancel the view's animation task during a rapid replay or
        // window change. Never leave an expanded, noninteractive notch behind.
        let generation = model.introGeneration
        let end = DispatchWorkItem { [weak self] in
            guard let self, self.model.introGeneration == generation else { return }
            self.model.isShowingIntro = false
            self.introEnd = nil
        }
        introEnd = end
        DispatchQueue.main.asyncAfter(deadline: .now() + 4, execute: end)
    }

    func showAppearancePreview() {
        guard !model.isShowingIntro else { return }
        cancelPending()
        setState(.closed)
        peekEnd?.cancel()
        model.isPeeking = false
        model.isShowingAppearancePreview = true
        panel.ignoresMouseEvents = true
    }

    func hideAppearancePreview() {
        guard model.isShowingAppearancePreview else { return }
        model.isShowingAppearancePreview = false
        panel.ignoresMouseEvents = true
    }

    /// Keyboard shortcut: opens or closes the notch wherever the pointer is.
    func toggleOpen() {
        guard !model.isShowingIntro, !model.isShowingAppearancePreview else { return }
        cancelPending()
        if model.state == .open {
            setState(.closed)
        } else {
            openedByKeyboard = true
            setState(.open)
        }
    }

    /// Keyboard shortcut: closes an open notch and briefly shows the current
    /// song, or hides the peek if it's already showing.
    func peek() {
        if model.isPeeking {
            peekEnd?.cancel()
            model.isPeeking = false
            return
        }
        guard !model.isShowingIntro, !model.isShowingAppearancePreview,
              model.media.track != nil else { return }
        if model.state == .open {
            cancelPending()
            setState(.closed)
            // A pointer still over the notch must not reopen it over the peek.
            hoverOpenBlocked = true
        }
        peekEnd?.cancel()
        model.isPeeking = true
        let end = DispatchWorkItem { [weak self] in self?.model.isPeeking = false }
        peekEnd = end
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.peekDuration, execute: end)
    }

    private func handle(_ event: NSEvent) {
        guard !model.isShowingIntro, !model.isShowingAppearancePreview else { return }
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
                hoverOpenBlocked = false
                return
            }

            if event.type == .leftMouseDragged, isDraggingContent, settings.openShelfOnDrag, settings.showsShelfTab {
                cancelPending()
                model.selectedPage = .shelf
                setState(.open)
            } else if settings.openMode == .click {
                if event.type == .leftMouseDown { setState(.open) }
            } else if event.type == .mouseMoved, !hoverOpenBlocked {
                schedule(after: settings.hoverDelay) { [weak self] in self?.setState(.open) }
            }

        case .open:
            #if DEBUG
            if debugHoldOpen { return }
            #endif
            let area = geometry.rect(for: model.currentSize).insetBy(dx: -8, dy: -8)
            // The camera popup counts as part of the notch while it's showing.
            let overMirror = model.isMirrorVisible
                && geometry.mirrorWindowFrame(openWidth: model.openWidth).insetBy(dx: -8, dy: -8).contains(location)
            // Stay open while a button is held, so scrubbing and drags in and out don't cut off.
            let buttonHeld = NSEvent.pressedMouseButtons & 1 != 0
            let inside = area.contains(location) || overMirror
            if openedByKeyboard {
                // Keep it open until the pointer has been inside once, or the user clicks elsewhere.
                if inside {
                    openedByKeyboard = false
                } else if event.type == .leftMouseDown {
                    openedByKeyboard = false
                    setState(.closed)
                }
                return
            }
            if inside || model.isInteracting || buttonHeld {
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
        if state == .open {
            peekEnd?.cancel()
            model.isPeeking = false
        } else {
            openedByKeyboard = false
            model.setUsageHover(nil)
        }
        if state == .closed, model.isMirrorVisible {
            // The camera closes together with the notch.
            model.toggleMirror()
        }
        if state == .open {
            positionMirror()
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
                    self.debugSnapshot(self.tooltipPanel, to: dir + "/snap-tooltip.png")
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
                case "page" where parts.count == 2:
                    if let index = Int(parts[1]), self.model.pages.indices.contains(index) {
                        self.model.selectedPage = self.model.pages[index]
                    }
                case "intro": self.playIntro()
                case "peek": self.peek()
                case "settings":
                    // "settings music" opens a specific page (closing an open window first).
                    if parts.count == 2, let page = SettingsSection(rawValue: parts[1]) {
                        SettingsView.initialSection = page
                        NSApp.windows.first { $0.title.contains("Settings") }?.close()
                    }
                    self.model.openSettings()
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                        if let window = NSApp.windows.first(where: { $0.title.contains("Settings") }) {
                            self.debugSnapshot(window, to: dir + "/snap-settings.png")
                        }
                    }
                case "usagehover" where parts.count == 3:
                    if let x = Double(parts[2]) { self.model.setUsageHover(UsageHover(id: parts[1], anchorX: x)) }
                case "toggle": self.toggleOpen()
                case "open": self.setState(.open)
                case "hold": self.debugHoldOpen = true; self.setState(.open)
                case "release": self.debugHoldOpen = false
                case "mirror": self.model.toggleMirror()
                case "close": self.setState(.closed)
                default: break
                }
            }
            let page = self.model.visiblePage.rawValue
            let status = "state=\(self.model.state) intro=\(self.model.isShowingIntro) page=\(page)/\(self.model.pages.count) mirror=\(self.model.isMirrorVisible) camera=\(self.model.camera.status)\n"
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
