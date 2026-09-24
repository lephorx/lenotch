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
    /// Show the calendar next to the music (it also needs calendar permission).
    var showCalendar: Bool { didSet { save(showCalendar, "showCalendar") } }

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

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        Self.migrateFromLephorNotch(into: defaults)
        func bool(_ key: String, _ fallback: Bool) -> Bool { defaults.object(forKey: key) as? Bool ?? fallback }

        hasCompletedOnboarding = bool("hasCompletedOnboarding", false)
        hasPlayedIntro = bool("hasPlayedIntro", false)
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
        showCalendar = bool("showCalendar", true)
        appearance = defaults.string(forKey: "appearance").flatMap(Appearance.init) ?? .black
        func gradient(_ key: String, _ fallback: NotchGradient) -> NotchGradient {
            defaults.data(forKey: key).flatMap { try? JSONDecoder().decode(NotchGradient.self, from: $0) } ?? fallback
        }
        blackGradient = gradient("blackGradient", .blackDefault)
        let savedGlass = gradient("glassGradient", .glassDefault)
        glassGradient = savedGlass == .previousGlassDefault ? .glassDefault : savedGlass
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
