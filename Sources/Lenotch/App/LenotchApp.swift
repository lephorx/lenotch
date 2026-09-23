import SwiftUI

@main
struct LenotchApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        MenuBarExtra("Lenotch", systemImage: "rectangle.topthird.inset.filled") {
            MenuContent(settings: appDelegate.settings, showSettings: appDelegate.showSettings)
        }
    }
}

private struct MenuContent: View {
    @Bindable var settings: AppSettings
    let showSettings: () -> Void

    var body: some View {
        Toggle("Real Audio Visualizer", isOn: $settings.realAudioVisualizer)
        Divider()
        Button("Settings…", action: showSettings)
            .keyboardShortcut(",")
        Divider()
        Button("Quit Lenotch") { NSApp.terminate(nil) }
            .keyboardShortcut("q")
    }
}
