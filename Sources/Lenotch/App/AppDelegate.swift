import AppKit
import Sparkle

final class AppDelegate: NSObject, NSApplicationDelegate {
    private let updaterController = SPUStandardUpdaterController(startingUpdater: true,
                                                                  updaterDelegate: nil,
                                                                  userDriverDelegate: nil)
    var updater: SPUUpdater { updaterController.updater }
    func checkForUpdates() { updaterController.checkForUpdates(nil) }
    let settings = AppSettings()
    private lazy var media = NowPlayingService(source: settings.audioSource)
    private let battery = BatteryMonitor()
    private lazy var shelf = ShelfStore(settings: settings)
    private let visualizer = AudioVisualizer()
    private var visualizerTimer: Timer?
    private let hotKeys = HotKeyCenter()
    /// Starting the audio tap is what makes macOS ask for audio recording; the
    /// visualizer timer stops it again right away if nothing is playing.
    private lazy var permissions: PermissionCenter = {
        let center = PermissionCenter(settings: settings) { [weak self] in self?.visualizer.start() }
        // Keep Settings / the setup in front while macOS asks, then bring them back.
        center.onPromptStarted = { [weak self] in self?.windows.setFloating(true) }
        center.onPromptFinished = { [weak self] in self?.windows.setFloating(false) }
        return center
    }()
    private let windows = WindowPresenter()
    private var notches: [CGDirectDisplayID: NotchWindowController] = [:]
    private var screenObserver: NSObjectProtocol?
    private var mediaKeyDisplay: CGDirectDisplayID?

    private func displayID(_ screen: NSScreen) -> CGDirectDisplayID {
        (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value ?? 0
    }

    private var activeNotch: NotchWindowController? {
        let screen = NSScreen.screens.first { $0.frame.contains(NSEvent.mouseLocation) }
        return screen.flatMap { notches[displayID($0)] } ?? notches.values.first
    }

    private func updateNotches() {
        let screens = NSScreen.screens
        guard let primary = screens.first(where: { $0.safeAreaInsets.top > 0 }) ?? NSScreen.main ?? screens.first else {
            notches.removeAll()
            mediaKeyDisplay = nil
            return
        }
        let targets = settings.showOnAllScreens ? screens : [primary]
        let owner = displayID(primary)
        // Reassign the single media-key tap when the primary display changes.
        if mediaKeyDisplay != owner { notches.removeAll() }
        mediaKeyDisplay = owner
        let ids = Set(targets.map(displayID))
        for id in Array(notches.keys) where !ids.contains(id) { notches.removeValue(forKey: id) }
        for screen in targets {
            let id = displayID(screen)
            if let notch = notches[id] {
                notch.relayout(on: screen)
            } else {
                notches[id] = NotchWindowController(media: media, settings: settings, battery: battery,
                    shelf: shelf, visualizer: visualizer, screen: screen, handlesMediaKeys: id == owner,
                    openSettings: { [weak self] in self?.showSettings() })
            }
        }
    }

    /// Opening Lenotch again (Finder, Spotlight) shows Settings — the way back
    /// when the menu bar icon is hidden.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showSettings()
        return false
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        settings.onAudioSourceChange = { [weak self] source in self?.media.setSource(source) }
        media.start()
        updateNotches()
        settings.onDisplaySettingsChange = { [weak self] in self?.updateNotches() }
        screenObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main
        ) { [weak self] _ in self?.updateNotches() }
        media.onTrackChange = { [weak self] in
            DispatchQueue.main.async {
                self?.notches.values.forEach { $0.peekForTrackChange() }
            }
        }

        registerShortcuts()
        settings.onShortcutsChange = { [weak self] in self?.registerShortcuts() }

        // Tap system audio only while music plays and the visualizer is on.
        visualizerTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            self?.updateVisualizer()
        }
        updateVisualizer()

        let hadCompletedOnboarding = settings.hasCompletedOnboarding
        if !settings.hasCompletedOnboarding {
            // The intro plays once the setup is done, in the chosen style.
            showOnboarding()
        } else if !settings.hasPlayedIntro {
            settings.hasPlayedIntro = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { [weak self] in self?.playIntro() }
        }

        // After an update (not a fresh install), show what changed once.
        if let version = Self.version, version != settings.lastSeenVersion {
            settings.lastSeenVersion = version
            if hadCompletedOnboarding {
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in self?.showWhatsNew() }
            }
        }
    }

    /// The release version (e.g. "2.8"); nil for local builds, which aren't released.
    private static var version: String? {
        let info = Bundle.main.infoDictionary
        guard info?["LenotchRelease"] as? Bool == true else { return nil }
        return info?["CFBundleShortVersionString"] as? String
    }

    func showWhatsNew() {
        guard let version = Self.version else { return }
        windows.show(id: "whatsNew", title: "What's New") {
            WhatsNewView(version: version) { [weak self] in self?.windows.close(id: "whatsNew") }
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        if let screenObserver { NotificationCenter.default.removeObserver(screenObserver) }
        notches.removeAll()
        media.stop()
        visualizer.stop()
    }

    private func registerShortcuts() {
        hotKeys.unregister(id: 1)
        hotKeys.unregister(id: 2)
        if let shortcut = settings.toggleShortcut {
            hotKeys.register(shortcut, id: 1) { [weak self] in self?.activeNotch?.toggleOpen() }
        }
        if let shortcut = settings.peekShortcut {
            hotKeys.register(shortcut, id: 2) { [weak self] in self?.activeNotch?.peek() }
        }
    }

    private func updateVisualizer() {
        let shouldRun = settings.realAudioVisualizer && media.isPlaying
        if shouldRun, !visualizer.isRunning {
            visualizer.start()
        } else if !shouldRun, visualizer.isRunning {
            visualizer.stop()
        }
    }

    func showSettings() {
        windows.show(id: "settings", title: "Lenotch Settings") {
            SettingsView(settings: settings, shelf: shelf, permissions: permissions,
                         updater: updater,
                         showOnboarding: { [weak self] in self?.showOnboarding() },
                         showWhatsNew: { [weak self] in self?.showWhatsNew() },
                         playIntro: { [weak self] in self?.playIntro() })
        }
    }

    func playIntro() {
        notches.values.forEach { $0.playIntro() }
    }

    func showOnboarding() {
        // Floating, so it stays in view while macOS permission prompts come and go.
        windows.show(id: "onboarding", title: "Welcome to Lenotch", floating: true) {
            OnboardingView(settings: settings, permissions: permissions,
                           showAppearancePreview: { [weak self] in self?.notches.values.forEach { $0.showAppearancePreview() } },
                           hideAppearancePreview: { [weak self] in self?.notches.values.forEach { $0.hideAppearancePreview() } }) { [weak self] in
                guard let self else { return }
                settings.hasCompletedOnboarding = true
                windows.close(id: "onboarding")
                // Finishing the setup always ends with the intro, in the style just picked.
                settings.hasPlayedIntro = true
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { self.playIntro() }
            }
        }
    }
}
