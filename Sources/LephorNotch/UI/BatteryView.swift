import SwiftUI

struct BatteryIndicator: View {
    @ObservedObject var battery: BatteryMonitor
    var showPercent: Bool
    var compact: Bool = false

    var body: some View {
        HStack(spacing: 5) {
            if showPercent && !compact {
                Text("\(battery.percentage)%")
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .foregroundStyle(battery.tint)
                    .contentTransition(.numericText())
                    .monospacedDigit()
            }

            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 3, style: .continuous)
                    .stroke(Color.white.opacity(0.42), lineWidth: 1)
                    .frame(width: 22, height: 11)

                RoundedRectangle(cornerRadius: 1.6, style: .continuous)
                    .fill(battery.tint)
                    .frame(width: max(2, 18 * CGFloat(battery.percentage) / 100), height: 7)
                    .padding(.leading, 2)
                    .animation(Theme.content, value: battery.percentage)

                if battery.isCharging {
                    Image(systemName: "bolt.fill")
                        .font(.system(size: 7, weight: .black))
                        .foregroundStyle(.black)
                        .frame(width: 22, height: 11)
                } else if battery.isLowPowerMode {
                    Image(systemName: "moon.fill")
                        .font(.system(size: 6, weight: .black))
                        .foregroundStyle(.black.opacity(0.7))
                        .frame(width: 22, height: 11)
                }
            }
            .overlay(alignment: .trailing) {
                Capsule()
                    .fill(Color.white.opacity(0.42))
                    .frame(width: 1.8, height: 4)
                    .offset(x: 3)
            }
        }
        .help(helpText)
    }

    private var helpText: String {
        var text = "\(battery.percentage)%"
        if battery.isCharging { text += " · charging" }
        if let remaining = battery.timeRemainingText {
            text += battery.isCharging ? " · \(remaining) to full" : " · \(remaining) left"
        }
        return text
    }
}

/// The wide battery card shown inside the open panel.
struct BatteryCard: View {
    @ObservedObject var battery: BatteryMonitor

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: battery.isCharging ? "bolt.fill" : "battery.100")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(battery.tint)
                Text("\(battery.percentage)%")
                    .font(.system(size: 20, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .contentTransition(.numericText())
                    .monospacedDigit()
            }

            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.white.opacity(0.12))
                    Capsule()
                        .fill(LinearGradient(colors: [battery.tint.opacity(0.75), battery.tint],
                                             startPoint: .leading, endPoint: .trailing))
                        .frame(width: proxy.size.width * CGFloat(battery.percentage) / 100)
                }
            }
            .frame(height: 5)

            Text(subtitle)
                .font(.system(size: 10))
                .foregroundStyle(Theme.secondaryText)
                .lineLimit(1)
        }
        .animation(Theme.content, value: battery.percentage)
    }

    private var subtitle: String {
        if battery.isCharging {
            return battery.timeRemainingText.map { "\($0) to full" } ?? "Charging"
        }
        if battery.isPluggedIn { return "Plugged in" }
        if battery.isLowPowerMode { return "Low Power Mode" }
        return battery.timeRemainingText.map { "\($0) remaining" } ?? "On battery"
    }
}
