import ServiceManagement
import Sparkle
import SwiftUI

/// Settings pages, grouped in the sidebar by what you want to change: how the notch
/// behaves and looks, each feature with its own page, and privacy.
enum SettingsSection: String, CaseIterable, Identifiable {
    case general, look, music, calendar, weather, shelf, camera, aiUsage, permissions

    enum Group: String, CaseIterable {
        case notch = "Notch"
        case features = "Features"
        case privacy = "Privacy"
    }

    var id: String { rawValue }

    var group: Group {
        switch self {
        case .general, .look: .notch
        case .permissions: .privacy
        default: .features
        }
    }

    var title: String {
        switch self {
        case .general: "General"
        case .look: "Look"
        case .music: "Music"
        case .calendar: "Calendar"
        case .weather: "Weather"
        case .shelf: "Shelf"
        case .camera: "Camera"
        case .aiUsage: "AI Usage"
        case .permissions: "Permissions"
        }
    }

    var symbol: String {
        switch self {
        case .general: "gearshape.fill"
        case .look: "paintbrush.fill"
        case .music: "music.note"
        case .calendar: "calendar"
        case .weather: "cloud.sun.fill"
        case .shelf: "tray.full.fill"
        case .camera: "camera.fill"
        case .aiUsage: "sparkles"
        case .permissions: "hand.raised.fill"
        }
    }

    /// Tile colour behind the white icon, like System Settings.
    var tint: Color {
        switch self {
        case .general: .gray
        case .look: .indigo
        case .music: .pink
        case .calendar: .red
        case .weather: .cyan
        case .shelf: .blue
        case .camera: .teal
        case .aiUsage: .orange
        case .permissions: .green
        }
    }

    /// Words people might search for to find this page.
    var keywords: [String] {
        switch self {
        case .general: ["open", "hover", "click", "delay", "shortcut", "keyboard", "menu bar", "icon", "login",
                        "startup", "update", "welcome", "intro", "peek"]
        case .look: ["style", "black", "glass", "liquid", "opacity", "transparent", "colour", "color", "gradient",
                     "fade", "battery", "percentage", "look", "appearance", "theme"]
        case .music: ["music", "song", "player", "spotify", "apple music", "youtube", "source", "shuffle", "repeat",
                      "favorite", "like", "album", "art", "cover", "colour", "color", "equalizer", "bars",
                      "progress", "visualizer", "audio", "sound"]
        case .calendar: ["calendar", "events", "month", "day strip", "reminders", "schedule", "date"]
        case .weather: ["weather", "temperature", "city", "location", "celsius", "fahrenheit", "forecast"]
        case .shelf: ["shelf", "files", "drop", "drag", "airdrop", "share"]
        case .camera: ["camera", "mirror", "video", "face"]
        case .aiUsage: ["ai", "usage", "claude", "codex", "cursor", "copilot", "limits", "provider", "tokens"]
        case .permissions: ["permission", "privacy", "allow", "access", "security"]
        }
    }

    func matches(_ query: String) -> Bool {
        let text = query.trimmingCharacters(in: .whitespaces).lowercased()
        guard !text.isEmpty else { return true }
        return title.lowercased().contains(text) || keywords.contains { $0.contains(text) }
    }
}

struct SettingsView: View {
    @Bindable var settings: AppSettings
    let shelf: ShelfStore
    let permissions: PermissionCenter
    let updater: SPUUpdater
    let showOnboarding: () -> Void
    let playIntro: () -> Void

    /// Page shown when the window opens (debug hooks can pick another).
    static var initialSection: SettingsSection = .general
    @State private var section: SettingsSection? = SettingsView.initialSection
    @State private var query = ""

    var body: some View {
        NavigationSplitView {
            List(selection: $section) {
                ForEach(SettingsSection.Group.allCases, id: \.self) { group in
                    let pages = SettingsSection.allCases.filter { $0.group == group && $0.matches(query) }
                    if !pages.isEmpty {
                        Section(group.rawValue) {
                            ForEach(pages) { page in
                                Label {
                                    Text(page.title)
                                } icon: {
                                    Image(systemName: page.symbol)
                                        .font(.system(size: 11, weight: .semibold))
                                        .foregroundStyle(.white)
                                        .frame(width: 22, height: 22)
                                        .background(RoundedRectangle(cornerRadius: 6, style: .continuous)
                                            .fill(page.tint.gradient))
                                }
                                .tag(page)
                            }
                        }
                    }
                }
            }
            .searchable(text: $query, placement: .sidebar, prompt: "Search settings")
            // Jump to the first page that matches what's typed.
            .onChange(of: query) { _, text in
                if let first = SettingsSection.allCases.first(where: { $0.matches(text) }),
                   !(section?.matches(text) ?? false) {
                    section = first
                }
            }
            .navigationSplitViewColumnWidth(200)
        } detail: {
            detail
                .navigationTitle(section?.title ?? "Settings")
                // Switches reflect real permission status, e.g. after returning from System Settings.
                .onAppear(perform: permissions.refresh)
                .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
                    permissions.refresh()
                }
        }
        .frame(width: 800, height: 600)
    }

    @ViewBuilder
    private var detail: some View {
        switch section ?? .general {
        case .general:
            GeneralSettings(settings: settings, updater: updater, showOnboarding: showOnboarding, playIntro: playIntro)
        case .look:
            LookSettings(settings: settings)
        case .music:
            MusicSettings(settings: settings, permissions: permissions)
        case .calendar:
            CalendarSettings(settings: settings, permissions: permissions)
        case .weather:
            Form { WeatherSection(settings: settings) }.formStyle(.grouped)
        case .shelf:
            ShelfSettings(settings: settings, shelf: shelf)
        case .camera:
            Form {
                Section {
                    permissions.cameraToggle("Camera mirror button", isEnabled: $settings.showMirror)
                } footer: {
                    Text("A camera button in the notch drops a small mirror down beside it. The camera only runs while the mirror is showing.")
                }
            }
            .formStyle(.grouped)
        case .aiUsage:
            AIUsageSettings(settings: settings)
        case .permissions:
            Form {
                Section {
                    PermissionsView(permissions: permissions, settings: settings)
                } footer: {
                    Text("macOS only asks when you click Allow. Anything you don't allow is never asked for.")
                }
            }
            .formStyle(.grouped)
        }
    }
}

// MARK: - Notch

/// How the notch opens, shortcuts, the menu bar icon, startup and help.
private struct GeneralSettings: View {
    @Bindable var settings: AppSettings
    let updater: SPUUpdater
    let showOnboarding: () -> Void
    let playIntro: () -> Void

    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled

    var body: some View {
        Form {
            Section("Opening") {
                Picker("Open the notch on", selection: $settings.openMode) {
                    ForEach(OpenMode.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
                if settings.openMode == .hover {
                    LabeledContent("Hover delay") {
                        HStack {
                            Slider(value: $settings.hoverDelay, in: 0...1, step: 0.05)
                            Text("\(settings.hoverDelay, format: .number.precision(.fractionLength(2))) s")
                                .monospacedDigit()
                                .frame(width: 44, alignment: .trailing)
                        }
                    }
                }
            }
            Section {
                LabeledContent("Open or close the notch") {
                    ShortcutRecorder(shortcut: $settings.toggleShortcut, defaultShortcut: .toggleDefault)
                }
                LabeledContent("Peek at the current song") {
                    ShortcutRecorder(shortcut: $settings.peekShortcut, defaultShortcut: .peekDefault)
                }
            } header: {
                Text("Keyboard shortcuts")
            } footer: {
                Text("Work in any app. Swipe up on the open notch to close it.")
            }
            Section {
                Toggle("Show icon in the menu bar", isOn: $settings.showMenuBarIcon)
            } header: {
                Text("Menu bar")
            } footer: {
                Text("When hidden, open Settings with the gear in the notch, or by opening Lenotch again from Applications or Spotlight.")
            }
            Section("Startup & updates") {
                Toggle("Launch at login", isOn: $launchAtLogin)
                Toggle("Check for updates automatically", isOn: Binding(
                    get: { updater.automaticallyChecksForUpdates },
                    set: { updater.automaticallyChecksForUpdates = $0 }
                ))
            }
            Section("Help") {
                LabeledContent("Welcome screen") {
                    Button("Show Again…", action: showOnboarding)
                }
                LabeledContent("Intro animation") {
                    Button("Play Intro", action: playIntro)
                }
            }
        }
        .formStyle(.grouped)
        .onChange(of: launchAtLogin) { _, enabled in
            do {
                if enabled {
                    try SMAppService.mainApp.register()
                } else {
                    try SMAppService.mainApp.unregister()
                }
            } catch {
                NSLog("Lenotch: launch at login failed: \(error)")
                launchAtLogin = SMAppService.mainApp.status == .enabled
            }
        }
    }
}

/// Everything about how the notch looks: style, glass opacity, colours, the header.
private struct LookSettings: View {
    @Bindable var settings: AppSettings

    var body: some View {
        Form {
            Section("Style") {
                AppearancePicker(settings: settings)
                    .padding(.vertical, 4)
            }
            if settings.appearance == .glass {
                Section {
                    LabeledContent("Opacity") {
                        HStack {
                            Text("Clear").font(.system(size: 11)).foregroundStyle(.secondary)
                            Slider(value: $settings.glassGradient.bottom.alpha, in: 0...1)
                            Text("Dark").font(.system(size: 11)).foregroundStyle(.secondary)
                            Text(settings.glassGradient.bottom.alpha, format: .percent.precision(.fractionLength(0)))
                                .monospacedDigit()
                                .frame(width: 40, alignment: .trailing)
                        }
                    }
                } header: {
                    Text("Liquid Glass")
                } footer: {
                    Text("How much the glass darkens towards the bottom. Higher is easier to read over bright or busy backgrounds.")
                }
            }
            GradientSettings(settings: settings, appearance: settings.appearance)
            Section("Notch header") {
                Toggle("Show battery percentage", isOn: $settings.showBatteryPercentage)
            }
        }
        .formStyle(.grouped)
    }
}

/// Editor for the colour transition of one style (each style keeps its own).
private struct GradientSettings: View {
    @Bindable var settings: AppSettings
    let appearance: Appearance

    private var gradient: Binding<NotchGradient> {
        Binding(
            get: { settings.gradient(for: appearance) },
            set: { newValue in
                if appearance == .glass {
                    settings.glassGradient = newValue
                } else {
                    settings.blackGradient = newValue
                }
            })
    }

    var body: some View {
        Section {
            ColorPicker("Top colour", selection: color(\.top), supportsOpacity: false)
            ColorPicker("Bottom colour", selection: color(\.bottom), supportsOpacity: false)
            LabeledContent("Transition starts") {
                percentSlider(gradient.start)
            }
            LabeledContent("Transition length") {
                percentSlider(gradient.length, range: 0.02...1)
            }
            LabeledContent("Reset") {
                Button("Restore Default") { gradient.wrappedValue = .default(for: appearance) }
                    .disabled(gradient.wrappedValue == .default(for: appearance))
            }
        } header: {
            Text("Colours")
        } footer: {
            Text(gradient.wrappedValue.bottomFollowsMusic
                 ? "The song's colour glows in the lower left and traces the bottom edge (Music → Colours from the album art)."
                 : "The notch fades from the top colour into the bottom colour. The strip beside the hardware notch always uses the top colour.")
        }
    }

    private func color(_ keyPath: WritableKeyPath<NotchGradient, RGBAColor>) -> Binding<Color> {
        Binding(
            get: { gradient.wrappedValue[keyPath: keyPath].color },
            set: { newColor in
                // Pickers set the colour only; the glass bottom's opacity has its own slider,
                // everything else is opaque.
                var value = RGBAColor(newColor)
                value.alpha = appearance == .glass && keyPath == \NotchGradient.bottom
                    ? gradient.wrappedValue.bottom.alpha : 1
                gradient.wrappedValue[keyPath: keyPath] = value
            })
    }

    private func percentSlider(_ value: Binding<Double>, range: ClosedRange<Double> = 0...1) -> some View {
        HStack {
            Slider(value: value, in: range)
            Text(value.wrappedValue, format: .percent.precision(.fractionLength(0)))
                .monospacedDigit()
                .frame(width: 42, alignment: .trailing)
        }
    }
}

// MARK: - Features

/// The music player: on/off, where it reads from, its controls, colours taken from
/// the album art, and the visualizer.
private struct MusicSettings: View {
    @Bindable var settings: AppSettings
    let permissions: PermissionCenter

    /// "Match the song's colour" belongs to the current style's colours.
    private var notchFollowsMusic: Binding<Bool> {
        Binding(
            get: { settings.gradient(for: settings.appearance).bottomFollowsMusic },
            set: { on in
                if settings.appearance == .glass {
                    settings.glassGradient.bottomFollowsMusic = on
                } else {
                    settings.blackGradient.bottomFollowsMusic = on
                }
            })
    }

    var body: some View {
        Form {
            Section {
                Toggle("Show the music player", isOn: $settings.showMusic)
            } footer: {
                Text("When off, the first tab shows the calendar, or the time and weather.")
            }
            Group {
                Section {
                    SourcePicker(selection: $settings.audioSource)
                        .padding(.vertical, 4)
                } header: {
                    Text("Music from")
                } footer: {
                    if let footer = sourceFooter {
                        Text(footer)
                    }
                }
                Section {
                    Toggle("Shuffle and repeat buttons", isOn: $settings.showShuffleRepeat)
                    Toggle("Favorite button", isOn: $settings.showFavorite)
                } header: {
                    Text("Controls")
                } footer: {
                    Text("Buttons only appear when the player supports them. Favorite works with Apple Music.")
                }
                Section {
                    Toggle("Notch background", isOn: notchFollowsMusic)
                    Toggle("Equalizer bars", isOn: $settings.tintEqualizer)
                    Toggle("Progress bar", isOn: $settings.tintProgressBar)
                } header: {
                    Text("Colours from the album art")
                } footer: {
                    Text("Uses the current cover for a soft colour glow in the lower left and a fine line along the bottom (\(settings.appearance.title) style).")
                }
                Section {
                    // Turning it on starts the audio tap, which is what makes macOS ask.
                    Toggle("Bars follow the real sound", isOn: Binding(
                        get: { settings.realAudioVisualizer },
                        set: { on in
                            if on { permissions.enableAudioVisualizer() } else { settings.realAudioVisualizer = false }
                        }))
                } header: {
                    Text("Visualizer")
                } footer: {
                    Text("macOS asks once for permission to record system audio. Without it the bars use an animation.")
                }
            }
            .disabled(!settings.showMusic)
        }
        .formStyle(.grouped)
    }

    private var sourceFooter: String? {
        switch settings.audioSource {
        case .nowPlaying: nil
        case .spotify, .appleMusic:
            "Needs permission to control \(settings.audioSource.title) (Permissions)."
        case .youtubeMusic:
            "Works with the YouTube Music desktop app, or music.youtube.com in your browser."
        }
    }
}

private struct ShelfSettings: View {
    @Bindable var settings: AppSettings
    let shelf: ShelfStore

    var body: some View {
        Form {
            Section {
                Text("Drop files on the notch to keep them handy, then drag them out wherever you need them.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            Section {
                ShelfTabToggle(settings: settings)
                Toggle("File shelf", isOn: $settings.showFileShelf)
                Toggle("AirDrop", isOn: $settings.showAirDrop)
            } header: {
                Text("Shelf tab")
            } footer: {
                Text("Without the file shelf, AirDrop fills the tab. With both off, the shelf tab is hidden.")
            }
            Section("Behaviour") {
                Toggle("Open the shelf when dragging files onto the notch", isOn: $settings.openShelfOnDrag)
                Toggle("Keep files on the shelf after restarting", isOn: $settings.keepShelfItems)
                    .onChange(of: settings.keepShelfItems) { shelf.persist() }
            }
            Section {
                LabeledContent("\(shelf.items.count) item\(shelf.items.count == 1 ? "" : "s") on the shelf") {
                    Button("Clear Shelf", role: .destructive) { shelf.removeAll() }
                        .disabled(shelf.items.isEmpty)
                }
            }
        }
        .formStyle(.grouped)
    }
}

/// The shelf tab's switch: off and disabled when neither the file shelf nor AirDrop is on.
private struct ShelfTabToggle: View {
    @Bindable var settings: AppSettings

    var body: some View {
        Toggle("Shelf tab", isOn: Binding(get: { settings.showsShelfTab },
                                          set: { settings.showShelfTab = $0 }))
            .disabled(!settings.hasShelfContent)
    }
}
