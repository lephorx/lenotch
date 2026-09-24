import SwiftUI

/// macOS-style battery glyph with optional percentage; the percentage also
/// turns yellow in Low Power Mode.
struct BatteryView: View {
    let battery: BatteryMonitor
    let showsPercentage: Bool

    var body: some View {
        HStack(spacing: 5) {
            if showsPercentage {
                Text("\(Int((battery.level * 100).rounded()))%")
                    .monospacedDigit()
                    .fixedSize()
                    .foregroundStyle(battery.isLowPowerMode ? AnyShapeStyle(.yellow) : AnyShapeStyle(.foreground))
            }
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 3, style: .continuous)
                    .strokeBorder(.white.opacity(0.45), lineWidth: 1)
                RoundedRectangle(cornerRadius: 1.5, style: .continuous)
                    .fill(fillColor)
                    .frame(width: max(2, 17 * battery.level))
                    .padding(2)
                if battery.isCharging || battery.isPluggedIn {
                    Image(systemName: "bolt.fill")
                        .font(.system(size: 7, weight: .bold))
                        .foregroundStyle(.white)
                        .shadow(color: .black.opacity(0.6), radius: 1)
                        .frame(maxWidth: .infinity)
                }
            }
            .frame(width: 22, height: 11)
            .overlay(alignment: .trailing) {
                Capsule().fill(.white.opacity(0.45)).frame(width: 1.5, height: 4).offset(x: 2.5)
            }
        }
    }

    /// Yellow in Low Power Mode (like macOS), green while charging, red when low.
    private var fillColor: Color {
        if battery.isLowPowerMode { return .yellow }
        if battery.isCharging { return .green }
        if battery.level <= 0.2 { return .red }
        return .white
    }
}
