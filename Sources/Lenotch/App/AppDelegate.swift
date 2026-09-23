import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    let settings = AppSettings()
    private lazy var media = NowPlayingService(source: settings.audioSource)
    private let battery = BatteryMonitor()
    private lazy var shelf = ShelfStore(settings: settings)
    private let visualizer = AudioVisualizer()
    private var visualizerTimer: Timer?
    private let windows = WindowPresenter()
    private var notch: NotchWindowController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        settings.onAudioSourceChange = { [weak self] source in self?.media.setSource(source) }
        media.start()
        notch = NotchWindowController(media: media, settings: settings, battery: battery, shelf: shelf,
                                      visualizer: visualizer,
                                      openSettings: { [weak self] in self?.showSettings() })

        // Tap system audio only while music plays and the visualizer is on.
        visualizerTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            self?.updateVisualizer()
        }
        updateVisualizer()

        if !settings.hasCompletedOnboarding {
            showOnboarding()
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        media.stop()
        visualizer.stop()
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
            SettingsView(settings: settings, shelf: shelf, showOnboarding: { [weak self] in self?.showOnboarding() })
        }
    }

    func showOnboarding() {
        windows.show(id: "onboarding", title: "Welcome to Lenotch") {
            OnboardingView(settings: settings) { [weak self] in
                self?.settings.hasCompletedOnboarding = true
                self?.windows.close(id: "onboarding")
            }
        }
    }
}
