import SwiftUI

/// Closed notch during a download or upload: download speed left of the notch,
/// upload speed right of it.
struct NetworkSpeedView: View {
    let speed: NetworkMonitor.Speed
    let notchWidth: CGFloat

    var body: some View {
        HStack(spacing: 0) {
            side("arrow.down", speed.down, highlighted: speed.down >= speed.up)
                .padding(.leading, 12)
                .frame(width: NotchGeometry.indicatorSideWidth, alignment: .leading)
            Spacer(minLength: notchWidth)
            side("arrow.up", speed.up, highlighted: speed.up > speed.down)
                .padding(.trailing, 12)
                .frame(width: NotchGeometry.indicatorSideWidth, alignment: .trailing)
        }
        .frame(maxHeight: .infinity)
        .animation(.easeOut(duration: 0.3), value: speed)
    }

    private func side(_ symbol: String, _ rate: Double, highlighted: Bool) -> some View {
        HStack(spacing: 4) {
            Image(systemName: symbol)
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(highlighted ? Color.cyan : .white.opacity(0.5))
            Text(NetworkMonitor.format(rate))
                .font(.system(size: 11, weight: .semibold).monospacedDigit())
                .foregroundStyle(.white.opacity(highlighted ? 1 : 0.6))
                .contentTransition(.numericText())
        }
        .lineLimit(1)
    }
}
