import SwiftUI

enum NotchAppearance: String, CaseIterable, Identifiable {
    case liquidGlass
    case pureBlack

    var id: String { rawValue }

    var label: String {
        switch self {
        case .liquidGlass: return "Liquid Glass"
        case .pureBlack: return "Pure Black"
        }
    }
}

@MainActor
final class Settings: ObservableObject {
    static let shared = Settings()

    @AppStorage("appearance") var appearance: NotchAppearance = .liquidGlass
    @AppStorage("openOnHover") var openOnHover: Bool = true
    @AppStorage("hoverDelay") var hoverDelay: Double = 0.16
    @AppStorage("showSpectrum") var showSpectrum: Bool = true
    @AppStorage("replaceSystemHUD") var replaceSystemHUD: Bool = true
    @AppStorage("suppressMacOSHUD") var suppressMacOSHUD: Bool = false
    @AppStorage("showBatteryPercent") var showBatteryPercent: Bool = true
    @AppStorage("hapticFeedback") var hapticFeedback: Bool = true
    @AppStorage("preferredPlayer") var preferredPlayer: String = MediaPlayer.spotify.rawValue

    private init() {}
}
