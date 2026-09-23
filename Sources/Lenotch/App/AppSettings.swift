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

    // MARK: General
    var openMode: OpenMode { didSet { save(openMode.rawValue, "openMode") } }
    /// Seconds the pointer has to rest on the notch before it opens in hover mode.
    var hoverDelay: Double { didSet { save(hoverDelay, "hoverDelay") } }
    var showBattery: Bool { didSet { save(showBattery, "showBattery") } }
    var showBatteryPercentage: Bool { didSet { save(showBatteryPercentage, "showBatteryPercentage") } }

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

    // MARK: Shelf
    var shelfEnabled: Bool { didSet { save(shelfEnabled, "shelfEnabled") } }
    var keepShelfItems: Bool { didSet { save(keepShelfItems, "keepShelfItems") } }
    var openShelfOnDrag: Bool { didSet { save(openShelfOnDrag, "openShelfOnDrag") } }
    var showAirDrop: Bool { didSet { save(showAirDrop, "showAirDrop") } }

    // MARK: Mirror
    var mirrorEnabled: Bool { didSet { save(mirrorEnabled, "mirrorEnabled") } }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        Self.migrateFromLephorNotch(into: defaults)
        func bool(_ key: String, _ fallback: Bool) -> Bool { defaults.object(forKey: key) as? Bool ?? fallback }

        hasCompletedOnboarding = bool("hasCompletedOnboarding", false)
        openMode = defaults.string(forKey: "openMode").flatMap(OpenMode.init) ?? .hover
        hoverDelay = defaults.object(forKey: "hoverDelay") as? Double ?? 0.12
        showBattery = bool("showBattery", true)
        showBatteryPercentage = bool("showBatteryPercentage", true)
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
        realAudioVisualizer = bool("realAudioVisualizer", true)
        shelfEnabled = bool("shelfEnabled", true)
        keepShelfItems = bool("keepShelfItems", true)
        openShelfOnDrag = bool("openShelfOnDrag", true)
        showAirDrop = bool("showAirDrop", true)
        mirrorEnabled = bool("mirrorEnabled", true)
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

    private func saveGradient(_ gradient: NotchGradient, _ key: String) {
        defaults.set(try? JSONEncoder().encode(gradient), forKey: key)
    }
}
