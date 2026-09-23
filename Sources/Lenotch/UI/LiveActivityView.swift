import SwiftUI

/// Collapsed notch while music plays: artwork left of the notch, equalizer right of it.
struct LiveActivityView: View {
    let model: NotchViewModel

    var body: some View {
        GeometryReader { proxy in
            let side = proxy.size.height - 10
            HStack(spacing: 0) {
                ArtworkView(artwork: model.media.artwork, fallback: model.media.appIcon, cornerRadius: 6)
                    .frame(width: side, height: side)
                Spacer(minLength: model.geometry.notchSize.width)
                EqualizerBars(isPlaying: model.media.isPlaying, color: model.equalizerColor,
                              levels: model.equalizerSource)
                    .frame(width: side * 0.8, height: side * 0.6)
                    .frame(width: side)
            }
            .padding(.horizontal, 10)
            .frame(maxHeight: .infinity)
        }
    }
}
