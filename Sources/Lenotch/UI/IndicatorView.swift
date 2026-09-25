import SwiftUI

/// Volume or brightness beside the hardware notch: the icon on the left, a level bar
/// and percentage on the right.
struct IndicatorView: View {
    let indicator: SystemIndicator
    let notchWidth: CGFloat

    private var level: Double { indicator.muted ? 0 : min(max(indicator.level, 0), 1) }

    var body: some View {
        HStack(spacing: 0) {
            Image(systemName: indicator.symbol)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.white)
                .contentTransition(.symbolEffect(.replace))
                .padding(.leading, 12)
                .frame(width: NotchGeometry.indicatorSideWidth, alignment: .leading)
            Spacer(minLength: notchWidth)
            HStack(spacing: 7) {
                GeometryReader { proxy in
                    ZStack(alignment: .leading) {
                        Capsule().fill(.white.opacity(0.2))
                        Capsule().fill(.white).frame(width: proxy.size.width * level)
                    }
                }
                .frame(width: 58, height: 5)
                Text("\(Int((level * 100).rounded()))")
                    .font(.system(size: 11, weight: .semibold).monospacedDigit())
                    .foregroundStyle(.white.opacity(0.8))
                    .contentTransition(.numericText())
                    .frame(width: 24, alignment: .trailing)
            }
            .padding(.trailing, 12)
            .frame(width: NotchGeometry.indicatorSideWidth, alignment: .trailing)
        }
        .frame(maxHeight: .infinity)
        .animation(.spring(response: 0.25, dampingFraction: 0.85), value: indicator)
    }
}
