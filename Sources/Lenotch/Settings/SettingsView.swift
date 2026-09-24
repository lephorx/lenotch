import ServiceManagement
import Sparkle
import SwiftUI

/// Settings sections, listed in the sidebar.
enum SettingsSection: String, CaseIterable, Identifiable {
    case general, appearance, media, calendar, aiUsage, shelf, permissions

    var id: String { rawValue }

    var title: String {
        switch self {
        case .general: "General"
        case .appearance: "Appearance"
        case .media: "Media"
        case .calendar: "Calendar"
        case .aiUsage: "AI Usage"
        case .shelf: "Shelf"
        case .permissions: "Permissions"
        }
    }

    var symbol: String {
        switch self {
        case .general: "gearshape.fill"
        case .appearance: "paintbrush.fill"
        case .media: "music.note"
        case .calendar: "calendar"
        case .aiUsage: "sparkles"
        case .shelf: "tray.full.fill"
        case .permissions: "hand.raised.fill"
        }
    }

    /// Tile colour behind the white icon, like System Settings.
    var tint: Color {
        switch self {
        case .general: .gray
        case .appearance: .indigo
        case .media: .pink
        case .calendar: .blue
        case .aiUsage: .orange
        case .shelf: .blue
        case .permissions: .green
        }
    }
}

struct SettingsView: View {
    @Bindable var settings: AppSettings
    let shelf: ShelfStore
    let permissions: PermissionCenter
    let updater: SPUUpdater
    let showOnboarding: () -> Void
    let playIntro: () -> Void

    @State private var section: SettingsSection? = .general

    var body: some View {
        NavigationSplitView {
            List(SettingsSection.allCases, selection: $section) { section in
                Label {
                    Text(section.title)
                } icon: {
                    Image(systemName: section.symbol)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(width: 22, height: 22)
                        .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(section.tint.gradient))
                }
                .tag(section)
            }
            .navigationSplitViewColumnWidth(190)
        } detail: {
            detail
                .navigationTitle(section?.title ?? "Settings")
                // Switches reflect real permission status, e.g. after returning from System Settings.
                .onAppear(perform: permissions.refresh)
                .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
                    permissions.refresh()
                }
        }
        .frame(width: 780, height: 580)
    }

    @ViewBuilder
    private var detail: some View {
        switch section ?? .general {
        case .general:
            GeneralSettings(settings: settings, permissions: permissions, updater: updater,
                            showOnboarding: showOnboarding, playIntro: playIntro)
        case .appearance:
            AppearanceSettings(settings: settings)
        case .media:
            MediaSettings(settings: settings, permissions: permissions)
        case .calendar:
            CalendarSettings(settings: settings, permissions: permissions)
        case .aiUsage:
            AIUsageSettings(settings: settings)
        case .shelf:
            ShelfSettings(settings: settings, shelf: shelf)
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

// MARK: - Tabs

private struct GeneralSettings: View {
    @Bindable var settings: AppSettings
    let permissions: PermissionCenter
    let updater: SPUUpdater
    let showOnboarding: () -> Void
    let playIntro: () -> Void

    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled

    var body: some View {
        Form {
            Section {
                Toggle("Music player", isOn: $settings.showMusic)
                permissions.toggle("Calendar next to the music", isEnabled: $settings.showCalendar, calendar: .events)
                permissions.cameraToggle("Camera mirror button", isEnabled: $settings.showMirror)
                ShelfTabToggle(settings: settings)
            } header: {
                Text("Features")
            } footer: {
                Text("Features that need a permission turn on only once it's allowed; switching one on asks macOS.")
            }
            WeatherSection(settings: settings)
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
                Toggle("Show battery percentage", isOn: $settings.showBatteryPercentage)
            } header: {
                Text("Battery")
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
                Text("Work in any app. Peek shows the song and artist under the notch for a few seconds, and does nothing when nothing is playing.")
            }
            Section {
                Toggle("Show icon in the menu bar", isOn: $settings.showMenuBarIcon)
            } header: {
                Text("Menu bar")
            } footer: {
                Text("When hidden, open Settings with the gear in the notch, or by opening Lenotch again from Applications or Spotlight.")
            }
            Section("App") {
                Toggle("Launch at login", isOn: $launchAtLogin)
                Toggle("Check for updates automatically", isOn: Binding(
                    get: { updater.automaticallyChecksForUpdates },
                    set: { updater.automaticallyChecksForUpdates = $0 }
                ))
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

private struct AppearanceSettings: View {
    @Bindable var settings: AppSettings

    var body: some View {
        Form {
            Section("Style") {
                AppearancePicker(settings: settings)
                    .padding(.vertical, 4)
            }
            GradientSettings(settings: settings, appearance: settings.appearance)
            Section {
                Toggle("Equalizer bars", isOn: $settings.tintEqualizer)
                Toggle("Progress bar", isOn: $settings.tintProgressBar)
            } header: {
                Text("Album art colours")
            } footer: {
                Text("Tints these with the main colour of the current cover.")
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
            Toggle("Match the song's colour", isOn: gradient.bottomFollowsMusic)
            ColorPicker(gradient.wrappedValue.bottomFollowsMusic ? "Bottom colour when nothing plays" : "Bottom colour",
                        selection: color(\.bottom), supportsOpacity: false)
            if appearance == .glass {
                LabeledContent("Bottom opacity") {
                    percentSlider(Binding(get: { gradient.wrappedValue.bottom.alpha },
                                          set: { gradient.wrappedValue.bottom.alpha = $0 }))
                }
            }
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
            Text("Colour transition · \(appearance.title)")
        } footer: {
            Text(appearance == .glass
                 ? "Fades from the top colour into the bottom colour over the glass. Lower the bottom opacity to see more glass."
                 : "Fades from the top colour into the bottom colour. The strip beside the hardware notch always uses the top colour.")
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

private struct MediaSettings: View {
    @Bindable var settings: AppSettings
    let permissions: PermissionCenter

    var body: some View {
        Form {
            Section {
                SourcePicker(selection: $settings.audioSource)
                    .padding(.vertical, 4)
            } header: {
                Text("Audio source")
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
                Text("Buttons only appear when the player supports them. Favorite works with Apple Music, which also adds the song to your library.")
            }
            Section {
                // Turning it on starts the audio tap, which is what makes macOS ask.
                Toggle("Real audio visualizer", isOn: Binding(
                    get: { settings.realAudioVisualizer },
                    set: { on in
                        if on { permissions.enableAudioVisualizer() } else { settings.realAudioVisualizer = false }
                    }))
            } header: {
                Text("Visualizer")
            } footer: {
                Text("The bars follow the actual sound while music plays. macOS asks once for permission to record system audio, and shows its recording indicator while the bars listen. Without permission the bars use an animation instead.")
            }
        }
        .formStyle(.grouped)
    }

    private var sourceFooter: String? {
        switch settings.audioSource {
        case .nowPlaying: nil
        case .spotify, .appleMusic:
            "macOS will ask once for permission to control \(settings.audioSource.title)."
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
