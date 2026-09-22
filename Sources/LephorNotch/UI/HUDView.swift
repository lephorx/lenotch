import SwiftUI

/// The volume/brightness readout that replaces the stock macOS HUD. It renders inside the
/// collapsed notch, so the notch briefly becomes the system indicator.
struct HUDStripView: View {
    let kind: HUDKind
    let width: CGFloat

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: kind.symbol)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.white)
                .contentTransition(.symbolEffect(.replace))
                .frame(width: 14)

            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.white.opacity(0.16))
                    Capsule()
                        .fill(LinearGradient(colors: [.white.opacity(0.85), .white],
                                             startPoint: .leading, endPoint: .trailing))
                        .frame(width: max(3, proxy.size.width * CGFloat(kind.value)))
                }
            }
            .frame(height: 4)

            Text("\(Int((kind.value * 100).rounded()))")
                .font(.system(size: 10, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(Theme.secondaryText)
                .frame(width: 22, alignment: .trailing)
        }
        .padding(.horizontal, 12)
        .frame(width: width)
        .animation(Theme.hud, value: kind.value)
        .transition(.opacity.combined(with: .scale(scale: 0.94)))
    }
}
