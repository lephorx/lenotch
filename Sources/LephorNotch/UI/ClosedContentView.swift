import SwiftUI

/// What lives inside the collapsed pill. Priority order: an active HUD, then a music
/// "sneak peek", then the ambient status row.
struct ClosedContentView: View {
    @ObservedObject var model: NotchViewModel
    @ObservedObject var media: MediaController
    @ObservedObject var hud: SystemHUDController
    @ObservedObject var battery: BatteryMonitor

    var size: CGSize
    /// Width of the physical cutout, which the content must straddle rather than sit under.
    var notchWidth: CGFloat

    var body: some View {
        ZStack {
            if let kind = hud.current {
                HUDStripView(kind: kind, width: size.width)
                    .id(kind.title)
            } else {
                statusRow
            }
        }
        .frame(width: size.width, height: size.height)
        .animation(Theme.hud, value: hud.current)
    }

    private var statusRow: some View {
        HStack(spacing: 0) {
            // Left of the cutout: what's playing.
            HStack(spacing: 6) {
                if let artwork = media.artwork, media.isRunning {
                    Image(nsImage: artwork)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: 16, height: 16)
                        .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
                        .transition(.scale.combined(with: .opacity))
                } else if model.state == .hovered {
                    Image(systemName: "chevron.down")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundStyle(Theme.secondaryText)
                        .transition(.opacity)
                }
            }
            .frame(maxWidth: .infinity, alignment: .trailing)
            .padding(.trailing, 7)

            // The cutout itself — always left empty.
            Color.clear.frame(width: notchWidth * 0.82)

            // Right of the cutout: playback life sign, then battery.
            HStack(spacing: 7) {
                if media.nowPlaying.isPlaying && model.settings.showSpectrum {
                    AudioSpectrumView(isPlaying: true,
                                      tint: media.artworkColors.first ?? .white,
                                      maxHeight: 11)
                        .transition(.scale.combined(with: .opacity))
                }
                if battery.hasBattery {
                    BatteryIndicator(battery: battery,
                                     showPercent: model.settings.showBatteryPercent,
                                     compact: model.state == .closed && media.nowPlaying.isPlaying)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.leading, 7)
        }
        .padding(.horizontal, 4)
        .animation(Theme.content, value: media.nowPlaying.isPlaying)
        .animation(Theme.content, value: media.isRunning)
    }
}
