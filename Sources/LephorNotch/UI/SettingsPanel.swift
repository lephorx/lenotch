import SwiftUI

struct SettingsPanel: View {
    @ObservedObject var model: NotchViewModel
    @ObservedObject var settings: Settings
    @ObservedObject var hud: SystemHUDController

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 14) {
                appearanceSection
                behaviourSection
                systemSection
                footer
            }
            .padding(.trailing, 4)
        }
    }

    private var appearanceSection: some View {
        Section(title: "Appearance") {
            HStack(spacing: 8) {
                ForEach(NotchAppearance.allCases) { option in
                    AppearanceSwatch(appearance: option, selected: settings.appearance == option) {
                        withAnimation(Theme.open) { settings.appearance = option }
                    }
                }
            }
            Toggle("Audio bars while playing", isOn: $settings.showSpectrum).toggleStyle(NotchToggle())
            Toggle("Battery percentage in the pill", isOn: $settings.showBatteryPercent).toggleStyle(NotchToggle())
        }
    }

    private var behaviourSection: some View {
        Section(title: "Behaviour") {
            Toggle("Open on hover", isOn: $settings.openOnHover).toggleStyle(NotchToggle())
            if settings.openOnHover {
                HStack {
                    Text("Hover delay")
                        .font(.system(size: 11))
                        .foregroundStyle(.white.opacity(0.8))
                    Slider(value: $settings.hoverDelay, in: 0...0.6)
                        .controlSize(.mini)
                        .tint(Theme.accent)
                    Text("\(Int(settings.hoverDelay * 1000)) ms")
                        .font(.system(size: 10, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(Theme.secondaryText)
                        .frame(width: 48, alignment: .trailing)
                }
            }
            Toggle("Haptic feedback", isOn: $settings.hapticFeedback).toggleStyle(NotchToggle())
        }
    }

    private var systemSection: some View {
        Section(title: "System HUD") {
            Toggle("Show volume & brightness in the notch", isOn: $settings.replaceSystemHUD)
                .toggleStyle(NotchToggle())

            Toggle("Hide the built-in macOS HUD", isOn: $settings.suppressMacOSHUD)
                .toggleStyle(NotchToggle())
                .onChange(of: settings.suppressMacOSHUD) { _, _ in hud.applySuppressionSetting() }

            if !hud.hasAccessibilityPermission {
                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 10))
                        .foregroundStyle(.orange)
                    Text("Without Accessibility access the keys still work, but macOS draws its own HUD too.")
                        .font(.system(size: 9.5))
                        .foregroundStyle(Theme.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 0)
                    Button("Grant") { hud.requestAccessibilityPermission() }
                        .buttonStyle(.plain)
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.black)
                        .padding(.horizontal, 10).padding(.vertical, 4)
                        .background(Capsule().fill(.white))
                }
                .padding(8)
                .background(RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(.orange.opacity(0.12)))
            }

            if !BrightnessService.shared.isAvailable {
                Text("Brightness control is unavailable on this display.")
                    .font(.system(size: 9.5))
                    .foregroundStyle(Theme.secondaryText)
            }
        }
    }

    private var footer: some View {
        HStack {
            Text("LephorNotch \(Bundle.main.shortVersion)")
                .font(.system(size: 9.5))
                .foregroundStyle(.white.opacity(0.3))
            Spacer()
            Button("Quit") { NSApp.terminate(nil) }
                .buttonStyle(.plain)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.red.opacity(0.85))
        }
        .padding(.top, 2)
    }

    private struct Section<Content: View>: View {
        let title: String
        @ViewBuilder var content: Content

        var body: some View {
            VStack(alignment: .leading, spacing: 8) {
                Text(title.uppercased())
                    .font(.system(size: 8.5, weight: .bold))
                    .foregroundStyle(.white.opacity(0.32))
                    .tracking(0.8)
                content
            }
        }
    }
}

private struct AppearanceSwatch: View {
    let appearance: NotchAppearance
    let selected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 5) {
                ZStack {
                    if appearance == .liquidGlass {
                        LinearGradient(colors: [.black, .white.opacity(0.35)],
                                       startPoint: .top, endPoint: .bottom)
                    } else {
                        Color.black
                    }
                }
                .frame(width: 54, height: 30)
                .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .strokeBorder(selected ? Theme.accent : .white.opacity(0.14),
                                  lineWidth: selected ? 1.6 : 0.8))

                Text(appearance.label)
                    .font(.system(size: 9, weight: selected ? .semibold : .regular))
                    .foregroundStyle(selected ? .white : Theme.secondaryText)
            }
        }
        .buttonStyle(.plain)
    }
}

struct NotchToggle: ToggleStyle {
    func makeBody(configuration: Configuration) -> some View {
        Button {
            withAnimation(.spring(response: 0.25, dampingFraction: 0.7)) {
                configuration.isOn.toggle()
            }
        } label: {
            HStack {
                configuration.label
                    .font(.system(size: 11))
                    .foregroundStyle(.white.opacity(0.85))
                Spacer(minLength: 8)
                Capsule()
                    .fill(configuration.isOn ? Theme.accent : Color.white.opacity(0.14))
                    .frame(width: 30, height: 17)
                    .overlay(alignment: configuration.isOn ? .trailing : .leading) {
                        Circle()
                            .fill(.white)
                            .frame(width: 13, height: 13)
                            .padding(.horizontal, 2)
                            .shadow(color: .black.opacity(0.3), radius: 1.5, y: 1)
                    }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

extension Bundle {
    var shortVersion: String {
        (infoDictionary?["CFBundleShortVersionString"] as? String) ?? "1.0"
    }
}
