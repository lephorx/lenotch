import SwiftUI

/// The current song, dropped briefly out of the closed notch.
struct PeekView: View {
    let model: NotchViewModel
    let track: Track

    var body: some View {
        HStack(spacing: 10) {
            ArtworkView(artwork: model.media.artwork, fallback: model.media.appIcon, cornerRadius: 8)
                .frame(width: 38, height: 38)
            VStack(alignment: .leading, spacing: 2) {
                Text(track.title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white)
                Text(track.artist.isEmpty ? track.album : track.artist)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.white.opacity(0.6))
            }
            .lineLimit(1)
            Spacer(minLength: 0)
            EqualizerBars(isPlaying: model.media.isPlaying, color: model.equalizerColor, levels: model.equalizerSource)
                .frame(width: 16, height: 14)
        }
        .padding(.horizontal, 16)
        .padding(.top, model.geometry.notchSize.height + 6)
        .padding(.bottom, 10)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }
}
