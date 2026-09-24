import SwiftUI

@main
struct LenotchApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        MenuBarExtra(isInserted: Bindable(appDelegate.settings).showMenuBarIcon) {
            MenuContent(settings: appDelegate.settings, showSettings: appDelegate.showSettings,
                        checkForUpdates: appDelegate.checkForUpdates)
        } label: {
            Image(nsImage: LogoShape.menuBarImage())
                .accessibilityLabel("Lenotch")
        }
    }
}

private struct MenuContent: View {
    @Bindable var settings: AppSettings
    let showSettings: () -> Void
    let checkForUpdates: () -> Void

    var body: some View {
        Toggle("Real Audio Visualizer", isOn: $settings.realAudioVisualizer)
        Divider()
        Button("Settings…", action: showSettings)
            .keyboardShortcut(",")
        Button("Check for Updates…", action: checkForUpdates)
        Divider()
        Button("Hide Menu Bar Icon") { settings.showMenuBarIcon = false }
        Button("Quit Lenotch") { NSApp.terminate(nil) }
            .keyboardShortcut("q")
    }
}
