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
    private var notch: NotchWindowController?

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
        notch = NotchWindowController(media: media, settings: settings, battery: battery, shelf: shelf,
                                      visualizer: visualizer,
                                      openSettings: { [weak self] in self?.showSettings() })

        registerShortcuts()
        settings.onShortcutsChange = { [weak self] in self?.registerShortcuts() }

        // Tap system audio only while music plays and the visualizer is on.
        visualizerTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            self?.updateVisualizer()
        }
        updateVisualizer()

        if !settings.hasCompletedOnboarding {
            // The intro plays once the setup is done, in the chosen style.
            showOnboarding()
        } else if !settings.hasPlayedIntro {
            settings.hasPlayedIntro = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { [weak self] in self?.playIntro() }
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        media.stop()
        visualizer.stop()
    }

    private func registerShortcuts() {
        hotKeys.unregister(id: 1)
        hotKeys.unregister(id: 2)
        if let shortcut = settings.toggleShortcut {
            hotKeys.register(shortcut, id: 1) { [weak self] in self?.notch?.toggleOpen() }
        }
        if let shortcut = settings.peekShortcut {
            hotKeys.register(shortcut, id: 2) { [weak self] in self?.notch?.peek() }
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
                         playIntro: { [weak self] in self?.playIntro() })
        }
    }

    func playIntro() {
        notch?.playIntro()
    }

    func showOnboarding() {
        // Floating, so it stays in view while macOS permission prompts come and go.
        windows.show(id: "onboarding", title: "Welcome to Lenotch", floating: true) {
            OnboardingView(settings: settings, permissions: permissions,
                           showAppearancePreview: { [weak self] in self?.notch?.showAppearancePreview() },
                           hideAppearancePreview: { [weak self] in self?.notch?.hideAppearancePreview() }) { [weak self] in
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
