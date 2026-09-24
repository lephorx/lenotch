import SwiftUI

struct NowPlayingView: View {
    let model: NotchViewModel
    let track: Track

    private var media: NowPlayingService { model.media }
    private var glass: Bool { model.settings.appearance == .glass }

    var body: some View {
        HStack(alignment: .center, spacing: 24) {
            artwork
                .slideIn(0)

            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .top, spacing: 8) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(track.title)
                            .font(.system(size: 16, weight: .bold))
                            .foregroundStyle(.white)
                        Text(track.artist.isEmpty ? track.album : track.artist)
                            .font(.system(size: 15, weight: .medium))
                            .foregroundStyle(.white.opacity(0.5))
                    }
                    .lineLimit(1)
                    Spacer(minLength: 0)
                    if model.settings.showFavorite, let isFavorite = media.isFavorite {
                        ToggleIconButton(symbol: isFavorite ? "heart.fill" : "heart", isOn: isFavorite,
                                         color: model.accentColor ?? .pink, label: "Favorite",
                                         action: media.toggleFavorite)
                    }
                }
                .slideIn(1)
                Spacer(minLength: 4)
                ProgressBar(model: model, duration: track.duration)
                    .slideIn(2)
                Spacer(minLength: 4)
                controls
                    .slideIn(3)
            }
            // Tall enough for title, progress (with its larger click area) and controls,
            // so nothing is pushed up and clipped.
            .frame(height: 138)
        }
    }

    private var artwork: some View {
        Button(action: media.openSourceApp) {
            // New songs slide in from the side they were skipped towards.
            ZStack {
                ArtworkView(artwork: media.artwork, fallback: media.appIcon, cornerRadius: 24)
                    .id(track.title + "\u{1}" + track.artist)
                    .transition(.asymmetric(
                        insertion: .push(from: media.skippedForward ? .trailing : .leading)
                            .combined(with: .scale(scale: 0.85)),
                        removal: .push(from: media.skippedForward ? .trailing : .leading)
                            .combined(with: .opacity)))
            }
            .frame(width: 120, height: 120)
            .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
            .animation(.spring(response: 0.5, dampingFraction: 0.78), value: track.title + track.artist)
                .overlay(alignment: .bottomTrailing) {
                    // Player badge, since the header shows tabs instead of the app name.
                    if media.artwork != nil, let icon = media.appIcon {
                        Image(nsImage: icon)
                            .resizable()
                            .frame(width: 30, height: 30)
                            .shadow(color: .black.opacity(0.4), radius: 2)
                            .offset(x: 7, y: 7)
                    }
                }
                .scaleEffect(media.isPlaying ? 1 : 0.94)
                .animation(.spring(response: 0.35, dampingFraction: 0.7), value: media.isPlaying)
        }
        .buttonStyle(.plain)
    }

    /// Previous / play / next in one capsule (clear glass in glass mode), with
    /// optional shuffle and repeat on either side.
    private var controls: some View {
        let showExtras = model.settings.showShuffleRepeat
        let activeColor = model.accentColor ?? .white
        let pillColor = model.settings.gradient(for: model.settings.appearance).bottomFollowsMusic
            ? model.accentColor : nil
        return HStack(spacing: 0) {
            Group {
                if showExtras, let shuffle = media.shuffle {
                    ToggleIconButton(symbol: "shuffle", isOn: shuffle, color: activeColor,
                                     label: "Shuffle", action: media.toggleShuffle)
                }
            }
            .frame(width: 28, alignment: .leading)
            Spacer(minLength: 0)
            HStack(spacing: 4) {
                ControlButton(symbol: "backward.fill", size: 15, label: "Previous", action: media.previousTrack)
                ControlButton(symbol: media.isPlaying ? "pause.fill" : "play.fill", size: 24,
                              label: media.isPlaying ? "Pause" : "Play", action: media.togglePlayPause)
                ControlButton(symbol: "forward.fill", size: 15, label: "Next", action: media.nextTrack)
            }
            .padding(.horizontal, 14)
            .frame(height: 42)
            .background {
                if glass {
                    // Glass that shows the same shade of the colour transition as the notch around it.
                    ZStack {
                        Color.clear.notchGlass(true, in: Capsule()).allowsHitTesting(false)
                        NotchGradientSlice(model: model).clipShape(Capsule())
                        if let pillColor { Capsule().fill(pillColor.opacity(0.10)) }
                    }
                } else {
                    ZStack {
                        Capsule().fill(.white.opacity(0.08))
                        if let pillColor { Capsule().fill(pillColor.opacity(0.12)) }
                    }
                }
            }
            Spacer(minLength: 0)
            Group {
                if showExtras, let repeatMode = media.repeatMode {
                    ToggleIconButton(symbol: repeatMode == .one ? "repeat.1" : "repeat", isOn: repeatMode != .off,
                                     color: activeColor, label: "Repeat", action: media.cycleRepeat)
                }
            }
            .frame(width: 28, alignment: .trailing)
        }
        .frame(maxWidth: .infinity)
    }
}

/// Solid white playback symbol. Only the symbol reacts to press, so the glass
/// capsule around it never moves.
private struct ControlButton: View {
    let symbol: String
    let size: CGFloat
    let label: String
    let action: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: size, weight: .semibold))
                .contentTransition(.symbolEffect(.replace))
                .frame(width: size + 20, height: 36)
                .contentShape(Rectangle())
        }
        .buttonStyle(PressStyle(isHovered: isHovered))
        .accessibilityLabel(label)
        .onHover { isHovered = $0 }
    }
}

private struct PressStyle: ButtonStyle {
    let isHovered: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(.white.opacity(configuration.isPressed ? 0.6 : isHovered ? 1 : 0.92))
            .scaleEffect(configuration.isPressed ? 0.85 : 1)
            .animation(.spring(response: 0.25, dampingFraction: 0.7), value: configuration.isPressed)
            .animation(.easeOut(duration: 0.15), value: isHovered)
    }
}

/// Small on/off control (shuffle, repeat, favorite): coloured when on, dim when off.
private struct ToggleIconButton: View {
    let symbol: String
    let isOn: Bool
    let color: Color
    let label: String
    let action: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 13, weight: .semibold))
                .contentTransition(.symbolEffect(.replace))
                .foregroundStyle(isOn ? color : .white.opacity(isHovered ? 0.8 : 0.45))
                .frame(width: 26, height: 24)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
        .onHover { isHovered = $0 }
        .animation(.easeOut(duration: 0.15), value: isOn)
        .animation(.easeOut(duration: 0.15), value: isHovered)
    }
}
