import AppKit
import AVFoundation
import EventKit
import Observation

/// The macOS permissions Lenotch can use, each asked for only when the user
/// chooses the feature that needs it (in the setup window or Settings).
@Observable
final class PermissionCenter {
    enum Status: Equatable {
        case notAsked, granted, denied
        /// For app automation: the app has to be open to be asked.
        case needsAppOpen
    }

    /// Music apps Lenotch can control directly, when installed.
    struct ControllableApp: Identifiable {
        let id: String  // bundle identifier
        let name: String
    }

    private(set) var calendar: Status = .notAsked
    private(set) var reminders: Status = .notAsked
    private(set) var camera: Status = .notAsked
    private(set) var automation: [String: Status] = [:]

    @ObservationIgnored private let settings: AppSettings
    @ObservationIgnored private let startAudioTap: () -> Void
    /// Called when a macOS prompt is about to show and after it's answered, so the
    /// window that asked can stay in front instead of falling behind other apps.
    @ObservationIgnored var onPromptStarted: (() -> Void)?
    @ObservationIgnored var onPromptFinished: (() -> Void)?

    let controllableApps: [ControllableApp] = [("com.spotify.client", "Spotify"), ("com.apple.Music", "Music")]
        .filter { NSWorkspace.shared.urlForApplication(withBundleIdentifier: $0.0) != nil }
        .map { ControllableApp(id: $0.0, name: $0.1) }

    init(settings: AppSettings, startAudioTap: @escaping () -> Void) {
        self.settings = settings
        self.startAudioTap = startAudioTap
        refresh()
    }

    /// Re-reads every status (e.g. after returning from System Settings).
    func refresh() {
        calendar = switch EKEventStore.authorizationStatus(for: .event) {
        case .fullAccess: .granted
        case .notDetermined: .notAsked
        default: .denied
        }
        reminders = switch EKEventStore.authorizationStatus(for: .reminder) {
        case .fullAccess: .granted
        case .notDetermined: .notAsked
        default: .denied
        }
        camera = switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized: .granted
        case .notDetermined: .notAsked
        default: .denied
        }
        for app in controllableApps {
            automation[app.id] = Self.automationStatus(app.id, ask: false)
        }
    }

    // MARK: - Requests (only ever called from a user's click)

    func requestCalendar() {
        onPromptStarted?()
        EKEventStore().requestFullAccessToEvents { _, _ in
            DispatchQueue.main.async { self.finished() }
        }
    }

    func requestReminders() {
        onPromptStarted?()
        EKEventStore().requestFullAccessToReminders { _, _ in
            DispatchQueue.main.async { self.finished() }
        }
    }

    func requestCamera() {
        onPromptStarted?()
        AVCaptureDevice.requestAccess(for: .video) { _ in
            DispatchQueue.main.async { self.finished() }
        }
    }

    /// Turns the real visualizer on; macOS asks the first time the audio tap starts.
    /// There's no callback for that prompt, so the window is released after a while.
    func enableAudioVisualizer() {
        onPromptStarted?()
        settings.realAudioVisualizer = true
        startAudioTap()
        DispatchQueue.main.asyncAfter(deadline: .now() + 20) { self.onPromptFinished?() }
    }

    func requestAutomation(_ app: ControllableApp) {
        onPromptStarted?()
        DispatchQueue.global(qos: .userInitiated).async {
            let status = Self.automationStatus(app.id, ask: true)
            DispatchQueue.main.async {
                self.automation[app.id] = status
                self.finished()
            }
        }
    }

    private func finished() {
        refresh()
        onPromptFinished?()
    }

    func openPrivacySettings(_ pane: String) {
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?\(pane)")!)
    }

    private static func automationStatus(_ bundleID: String, ask: Bool) -> Status {
        let target = NSAppleEventDescriptor(bundleIdentifier: bundleID)
        guard let descriptor = target.aeDesc else { return .notAsked }
        let result = AEDeterminePermissionToAutomateTarget(descriptor, typeWildCard, typeWildCard, ask)
        switch result {
        case noErr: return .granted
        case OSStatus(errAEEventNotPermitted): return .denied
        case OSStatus(procNotFound): return .needsAppOpen
        default: return .notAsked
        }
    }
}
