import Foundation
import Observation

enum Appearance: String, CaseIterable, Identifiable {
    case black
    case glass

    var id: String { rawValue }

    var title: String {
        switch self {
        case .black: "Black"
        case .glass: "Liquid Glass"
        }
    }

    var subtitle: String {
        switch self {
        case .black: "Solid black, like the hardware notch"
        case .glass: "Black at the top, glass underneath"
        }
    }
}

/// How the calendar looks when it has the first tab to itself (music off).
enum ExpandedCalendarStyle: String, CaseIterable, Identifiable {
    case month, strip

    var id: String { rawValue }

    var title: String {
        switch self {
        case .month: "Month view"
        case .strip: "Day strip"
        }
    }
}

enum OpenMode: String, CaseIterable, Identifiable {
    case hover
    case click

    var id: String { rawValue }

    var title: String {
        switch self {
        case .hover: "Hover"
        case .click: "Click"
        }
    }
}

/// User preferences, persisted in UserDefaults.
@Observable
final class AppSettings {
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored var onAudioSourceChange: ((AudioSource) -> Void)?
    // MARK: Setup
    var hasCompletedOnboarding: Bool { didSet { save(hasCompletedOnboarding, "hasCompletedOnboarding") } }
    var hasPlayedIntro: Bool { didSet { save(hasPlayedIntro, "hasPlayedIntro") } }
    /// The version whose What's New was last shown (or that was first installed).
    var lastSeenVersion: String? { didSet { defaults.set(lastSeenVersion, forKey: "lastSeenVersion") } }

    // MARK: General
    var openMode: OpenMode { didSet { save(openMode.rawValue, "openMode") } }
    /// Global shortcuts; nil turns one off.
    var toggleShortcut: KeyShortcut? {
        didSet { saveShortcut(toggleShortcut, "toggleShortcut"); onShortcutsChange?() }
    }
    var peekShortcut: KeyShortcut? {
        didSet { saveShortcut(peekShortcut, "peekShortcut"); onShortcutsChange?() }
    }
    @ObservationIgnored var onShortcutsChange: (() -> Void)?
    /// Seconds the pointer has to rest on the notch before it opens in hover mode.
    var hoverDelay: Double { didSet { save(hoverDelay, "hoverDelay") } }
    var showBatteryPercentage: Bool { didSet { save(showBatteryPercentage, "showBatteryPercentage") } }
    /// The Lenotch icon in the menu bar. When hidden, Settings is reached from the
    /// notch's gear or by opening the app again.
    var showMenuBarIcon: Bool { didSet { save(showMenuBarIcon, "showMenuBarIcon") } }
    /// Show the calendar next to the music (it also needs calendar permission).
    var showCalendar: Bool { didSet { save(showCalendar, "showCalendar") } }
    /// The music player in the first tab; off leaves the calendar (or the weather home view).
    var showMusic: Bool { didSet { save(showMusic, "showMusic") } }
    /// Briefly show the new song in the closed notch when the track changes.
    var peekOnTrackChange: Bool { didSet { save(peekOnTrackChange, "peekOnTrackChange") } }
    /// Seconds the new song stays in the notch after a track change.
    var trackPeekDuration: Double { didSet { save(trackPeekDuration, "trackPeekDuration") } }
    /// Show volume changes beside the notch.
    var showVolumeIndicator: Bool { didSet { save(showVolumeIndicator, "showVolumeIndicator") } }
    /// Show brightness changes beside the notch.
    var showBrightnessIndicator: Bool { didSet { save(showBrightnessIndicator, "showBrightnessIndicator") } }
    /// Take over the volume/brightness keys so macOS's own indicator doesn't show
    /// (only works once Accessibility is allowed).
    /// Crypto prices beside the closed notch while nothing is playing.
    var showCrypto: Bool { didSet { save(showCrypto, "showCrypto") } }
    /// CoinGecko ids, in catalogue order.
    var cryptoCoins: [String] { didSet { defaults.set(cryptoCoins, forKey: "cryptoCoins") } }
    var cryptoCurrency: String { didSet { save(cryptoCurrency, "cryptoCurrency") } }
    /// Show which app uses the microphone or camera beside the closed notch.
    var showPrivacyIndicator: Bool { didSet { save(showPrivacyIndicator, "showPrivacyIndicator") } }
    var hideSystemIndicator: Bool { didSet { save(hideSystemIndicator, "hideSystemIndicator") } }
    var expandedCalendarStyle: ExpandedCalendarStyle {
        didSet { save(expandedCalendarStyle.rawValue, "expandedCalendarStyle") }
    }
    /// Place for the weather in the home view (a typed city or the user's location).
    var weatherPlace: WeatherPlace? {
        didSet { defaults.set(weatherPlace.flatMap { try? JSONEncoder().encode($0) }, forKey: "weatherPlace") }
    }
    var weatherFahrenheit: Bool { didSet { save(weatherFahrenheit, "weatherFahrenheit") } }
    /// Reminders under the day's events (also needs reminders permission).
    var showReminders: Bool { didSet { save(showReminders, "showReminders") } }
    /// The camera mirror button in the notch (also needs camera permission).
    var showMirror: Bool { didSet { save(showMirror, "showMirror") } }
    var autoScrollCalendar: Bool { didSet { save(autoScrollCalendar, "autoScrollCalendar") } }
    var showFullEventTitles: Bool { didSet { save(showFullEventTitles, "showFullEventTitles") } }
    var hiddenCalendarIDs: Set<String> { didSet { save(Array(hiddenCalendarIDs), "hiddenCalendarIDs") } }
    var hiddenReminderListIDs: Set<String> { didSet { save(Array(hiddenReminderListIDs), "hiddenReminderListIDs") } }

    // MARK: Appearance
    var appearance: Appearance { didSet { save(appearance.rawValue, "appearance") } }
    var blackGradient: NotchGradient { didSet { saveGradient(blackGradient, "blackGradient") } }
    var glassGradient: NotchGradient { didSet { saveGradient(glassGradient, "glassGradient") } }
    var tintEqualizer: Bool { didSet { save(tintEqualizer, "tintEqualizer") } }
    var tintProgressBar: Bool { didSet { save(tintProgressBar, "tintProgressBar") } }

    // MARK: Media
    var audioSource: AudioSource {
        didSet {
            guard audioSource != oldValue else { return }
            save(audioSource.rawValue, "audioSource")
            onAudioSourceChange?(audioSource)
        }
    }
    var showShuffleRepeat: Bool { didSet { save(showShuffleRepeat, "showShuffleRepeat") } }
    var showFavorite: Bool { didSet { save(showFavorite, "showFavorite") } }
    /// Drive the equalizer bars from the actual system audio.
    var realAudioVisualizer: Bool { didSet { save(realAudioVisualizer, "realAudioVisualizer") } }

    // MARK: AI usage
    /// Off by default: the AI Usage tab only appears once switched on.
    var aiUsageEnabled: Bool { didSet { save(aiUsageEnabled, "aiUsageEnabled") } }
    /// Enabled usage sources in display order: built-in provider names or `custom:<uuid>`.
    var usageSourceKeys: [String] { didSet { save(usageSourceKeys, "aiProviders") } }
    var customProviders: [CustomAIProvider] {
        didSet { defaults.set(try? JSONEncoder().encode(customProviders), forKey: "customProviders") }
    }

    /// Providers loaded from config files in the Providers folder (not saved here).
    private(set) var configProviders: [CustomAIProvider] = []

    /// Hand-made and config-file custom providers together.
    var allCustomProviders: [CustomAIProvider] { customProviders + configProviders }

    /// The enabled sources, resolved, in order.
    var usageSources: [UsageSource] {
        usageSourceKeys.compactMap { UsageSource.resolve($0, customs: allCustomProviders) }
    }

    /// Re-reads the Providers folder. Configs seen for the first time are switched on;
    /// ones switched off stay off.
    func reloadProviderConfigs() {
        configProviders = ProviderConfigStore.loadAll()
        var known = Set(defaults.stringArray(forKey: "knownProviderConfigs") ?? [])
        for provider in configProviders where !known.contains(provider.key) {
            known.insert(provider.key)
            if !usageSourceKeys.contains(provider.key) { usageSourceKeys.append(provider.key) }
        }
        defaults.set(Array(known), forKey: "knownProviderConfigs")
    }

    // MARK: Shelf
    var keepShelfItems: Bool { didSet { save(keepShelfItems, "keepShelfItems") } }
    var openShelfOnDrag: Bool { didSet { save(openShelfOnDrag, "openShelfOnDrag") } }
    var showAirDrop: Bool { didSet { save(showAirDrop, "showAirDrop") } }
    /// The whole shelf tab.
    var showShelfTab: Bool { didSet { save(showShelfTab, "showShelfTab") } }
    /// The "Drop files here" shelf inside the tab; without it AirDrop fills the tab.
    var showFileShelf: Bool { didSet { save(showFileShelf, "showFileShelf") } }

    /// The shelf tab has something to show (the file shelf or AirDrop).
    var hasShelfContent: Bool { showFileShelf || showAirDrop }
    /// The shelf tab is in the notch: switched on and not empty.
    var showsShelfTab: Bool { showShelfTab && hasShelfContent }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        Self.migrateFromLephorNotch(into: defaults)
        func bool(_ key: String, _ fallback: Bool) -> Bool { defaults.object(forKey: key) as? Bool ?? fallback }

        hasCompletedOnboarding = bool("hasCompletedOnboarding", false)
        hasPlayedIntro = bool("hasPlayedIntro", false)
        lastSeenVersion = defaults.string(forKey: "lastSeenVersion")
        openMode = defaults.string(forKey: "openMode").flatMap(OpenMode.init) ?? .hover
        func shortcut(_ key: String, _ fallback: KeyShortcut) -> KeyShortcut? {
            guard let data = defaults.data(forKey: key) else { return fallback }
            // An empty value means the user turned the shortcut off.
            return data.isEmpty ? nil : try? JSONDecoder().decode(KeyShortcut.self, from: data)
        }
        toggleShortcut = shortcut("toggleShortcut", .toggleDefault)
        peekShortcut = shortcut("peekShortcut", .peekDefault)
        hoverDelay = defaults.object(forKey: "hoverDelay") as? Double ?? 0.12
        showBatteryPercentage = bool("showBatteryPercentage", true)
        showMenuBarIcon = bool("showMenuBarIcon", true)
        showCalendar = bool("showCalendar", true)
        showMusic = bool("showMusic", true)
        peekOnTrackChange = bool("peekOnTrackChange", true)
        trackPeekDuration = defaults.object(forKey: "trackPeekDuration") as? Double ?? 3
        showVolumeIndicator = bool("showVolumeIndicator", true)
        showBrightnessIndicator = bool("showBrightnessIndicator", true)
        hideSystemIndicator = bool("hideSystemIndicator", true)
        showPrivacyIndicator = bool("showPrivacyIndicator", true)
        showCrypto = bool("showCrypto", false)
        cryptoCoins = defaults.stringArray(forKey: "cryptoCoins") ?? ["bitcoin", "ethereum"]
        cryptoCurrency = defaults.string(forKey: "cryptoCurrency")
            ?? (["EUR", "CHF", "GBP", "JPY"].contains(Locale.current.currency?.identifier ?? "")
                ? Locale.current.currency!.identifier.lowercased() : "usd")
        expandedCalendarStyle = defaults.string(forKey: "expandedCalendarStyle")
            .flatMap(ExpandedCalendarStyle.init) ?? .month
        weatherPlace = defaults.data(forKey: "weatherPlace").flatMap { try? JSONDecoder().decode(WeatherPlace.self, from: $0) }
        weatherFahrenheit = bool("weatherFahrenheit", Locale.current.measurementSystem == .us)
        showReminders = bool("showReminders", true)
        showMirror = bool("showMirror", true)
        autoScrollCalendar = bool("autoScrollCalendar", true)
        showFullEventTitles = bool("showFullEventTitles", false)
        hiddenCalendarIDs = Set(defaults.stringArray(forKey: "hiddenCalendarIDs") ?? [])
        hiddenReminderListIDs = Set(defaults.stringArray(forKey: "hiddenReminderListIDs") ?? [])
        appearance = defaults.string(forKey: "appearance").flatMap(Appearance.init) ?? .black
        func gradient(_ key: String, _ fallback: NotchGradient) -> NotchGradient {
            defaults.data(forKey: key).flatMap { try? JSONDecoder().decode(NotchGradient.self, from: $0) } ?? fallback
        }
        // Bring unchanged old gradients onto the new album-art background once.
        // Custom gradients, and choices made after this migration, stay untouched.
        let upgradeArtworkBackground = defaults.integer(forKey: "artworkBackgroundVersion") < 1
        let savedBlack = gradient("blackGradient", .blackDefault)
        let upgradedBlack: NotchGradient = upgradeArtworkBackground && savedBlack == .legacyBlackDefault
            ? .blackDefault : savedBlack
        blackGradient = upgradedBlack
        let savedGlass = gradient("glassGradient", .glassDefault)
        let upgradedGlass: NotchGradient = (savedGlass == .previousGlassDefault
                                            || upgradeArtworkBackground && savedGlass == .legacyGlassDefault)
            ? .glassDefault : savedGlass
        glassGradient = upgradedGlass
        if upgradeArtworkBackground {
            defaults.set(try? JSONEncoder().encode(upgradedBlack), forKey: "blackGradient")
            defaults.set(try? JSONEncoder().encode(upgradedGlass), forKey: "glassGradient")
            defaults.set(1, forKey: "artworkBackgroundVersion")
        }
        tintEqualizer = bool("tintEqualizer", true)
        tintProgressBar = bool("tintProgressBar", true)
        audioSource = defaults.string(forKey: "audioSource").flatMap(AudioSource.init) ?? .nowPlaying
        showShuffleRepeat = bool("showShuffleRepeat", true)
        showFavorite = bool("showFavorite", true)
        // Off for new installs until chosen in the setup (it needs audio recording permission).
        realAudioVisualizer = bool("realAudioVisualizer", bool("hasCompletedOnboarding", false))
        aiUsageEnabled = bool("aiUsageEnabled", false)
        var sourceKeys = defaults.stringArray(forKey: "aiProviders") ?? AIProvider.allCases.map(\.rawValue)
        // Version 2 added Cursor, Grok, Kimi, OpenCode and Amp: switch them on once.
        if defaults.integer(forKey: "usageSourcesVersion") < 2 {
            sourceKeys += AIProvider.allCases.map(\.rawValue).filter { !sourceKeys.contains($0) }
            defaults.set(2, forKey: "usageSourcesVersion")
        }
        usageSourceKeys = sourceKeys
        customProviders = defaults.data(forKey: "customProviders")
            .flatMap { try? JSONDecoder().decode([CustomAIProvider].self, from: $0) } ?? []
        keepShelfItems = bool("keepShelfItems", true)
        openShelfOnDrag = bool("openShelfOnDrag", true)
        showAirDrop = bool("showAirDrop", true)
        showShelfTab = bool("showShelfTab", true)
        showFileShelf = bool("showFileShelf", true)
        reloadProviderConfigs()
    }

    /// The app used to be called LephorNotch (bundle ID com.lephorx.LephorNotch).
    /// Copies its saved preferences over once, so renaming doesn't reset anything.
    private static func migrateFromLephorNotch(into defaults: UserDefaults) {
        let flag = "migratedFromLephorNotch"
        guard !defaults.bool(forKey: flag) else { return }
        defaults.set(true, forKey: flag)
        guard let old = defaults.persistentDomain(forName: "com.lephorx.LephorNotch") else { return }
        for (key, value) in old where defaults.object(forKey: key) == nil {
            defaults.set(value, forKey: key)
        }
    }

    func gradient(for appearance: Appearance) -> NotchGradient {
        appearance == .glass ? glassGradient : blackGradient
    }

    private func save(_ value: Any, _ key: String) {
        defaults.set(value, forKey: key)
    }

    private func saveShortcut(_ shortcut: KeyShortcut?, _ key: String) {
        defaults.set(shortcut.flatMap { try? JSONEncoder().encode($0) } ?? Data(), forKey: key)
    }

    private func saveGradient(_ gradient: NotchGradient, _ key: String) {
        defaults.set(try? JSONEncoder().encode(gradient), forKey: key)
    }
}
