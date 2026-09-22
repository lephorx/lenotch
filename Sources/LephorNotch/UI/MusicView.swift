import SwiftUI

struct MusicView: View {
    @ObservedObject var media: MediaController
    @ObservedObject var battery: BatteryMonitor

    @State private var scrubbing = false
    @State private var scrubValue: Double = 0
    @State private var hoveringArtwork = false

    var body: some View {
        HStack(spacing: 16) {
            artwork
            VStack(alignment: .leading, spacing: 0) {
                trackInfo
                Spacer(minLength: 8)
                scrubber
                Spacer(minLength: 10)
                transport
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Divider()
                .overlay(Color.white.opacity(0.08))
                .padding(.vertical, 6)

            VStack(alignment: .leading, spacing: 14) {
                BatteryCard(battery: battery)
                Spacer(minLength: 0)
                playerPicker
            }
            .frame(width: 128)
        }
    }

    // MARK: - Pieces

    private var artwork: some View {
        ZStack {
            if let image = media.artwork {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .transition(.opacity.combined(with: .scale(scale: 1.04)))
                    .id(media.nowPlaying.trackID)
            } else {
                LinearGradient(colors: media.artworkColors, startPoint: .topLeading, endPoint: .bottomTrailing)
                Image(systemName: media.player.symbol)
                    .font(.system(size: 26, weight: .light))
                    .foregroundStyle(.white.opacity(0.65))
            }

            if hoveringArtwork {
                Color.black.opacity(0.4)
                Image(systemName: media.nowPlaying.isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(.white)
            }
        }
        .frame(width: 116, height: 116)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(.white.opacity(0.14), lineWidth: 0.8))
        .shadow(color: (media.artworkColors.first ?? .black).opacity(0.5), radius: 18, y: 8)
        .scaleEffect(hoveringArtwork ? 1.03 : 1.0)
        .animation(Theme.content, value: hoveringArtwork)
        .animation(Theme.content, value: media.nowPlaying.trackID)
        .onHover { hoveringArtwork = $0 }
        .onTapGesture { media.playPause() }
    }

    private var trackInfo: some View {
        VStack(alignment: .leading, spacing: 3) {
            if media.needsAutomationPermission {
                Text("Allow automation")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.white)
                Text("System Settings › Privacy & Security › Automation → enable LephorNotch for \(media.player.displayName).")
                    .font(.system(size: 10))
                    .foregroundStyle(Theme.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            } else if !media.isRunning {
                Text("\(media.player.displayName) isn't running")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.white)
                Button("Open \(media.player.displayName)") { media.launchPlayer() }
                    .buttonStyle(.plain)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(Theme.accent)
                    .padding(.top, 2)
            } else {
                MarqueeText(text: media.nowPlaying.title.isEmpty ? "Nothing playing" : media.nowPlaying.title,
                            font: .system(size: 15, weight: .semibold))
                    .foregroundStyle(.white)
                Text(media.nowPlaying.artist)
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.secondaryText)
                    .lineLimit(1)
                Text(media.nowPlaying.album)
                    .font(.system(size: 10))
                    .foregroundStyle(.white.opacity(0.34))
                    .lineLimit(1)
            }
        }
    }

    private var scrubber: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 20.0, paused: !media.nowPlaying.isPlaying)) { context in
            let live = scrubbing ? scrubValue * media.nowPlaying.duration
                                 : media.interpolatedPosition(at: context.date)
            let fraction = media.nowPlaying.duration > 0 ? live / media.nowPlaying.duration : 0

            VStack(spacing: 4) {
                GeometryReader { proxy in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Color.white.opacity(0.14))
                        Capsule()
                            .fill(LinearGradient(colors: [.white.opacity(0.8), .white],
                                                 startPoint: .leading, endPoint: .trailing))
                            .frame(width: max(0, proxy.size.width * fraction))
                        Circle()
                            .fill(.white)
                            .frame(width: scrubbing ? 9 : 0, height: scrubbing ? 9 : 0)
                            .offset(x: max(0, proxy.size.width * fraction - 4.5))
                    }
                    .contentShape(Rectangle().inset(by: -8))
                    .gesture(
                        DragGesture(minimumDistance: 0)
                            .onChanged { value in
                                scrubbing = true
                                scrubValue = min(max(value.location.x / proxy.size.width, 0), 1)
                            }
                            .onEnded { _ in
                                media.seek(toFraction: scrubValue)
                                scrubbing = false
                            })
                }
                .frame(height: scrubbing ? 6 : 4)
                .animation(Theme.content, value: scrubbing)

                HStack {
                    Text(Self.time(live))
                    Spacer()
                    Text("-" + Self.time(max(0, media.nowPlaying.duration - live)))
                }
                .font(.system(size: 9, weight: .medium, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(.white.opacity(0.4))
            }
        }
        .disabled(!media.isRunning || media.nowPlaying.duration <= 0)
        .opacity(media.isRunning ? 1 : 0.35)
    }

    private var transport: some View {
        HStack(spacing: 14) {
            TransportButton(symbol: "shuffle", size: 11,
                            active: media.nowPlaying.shuffle) { media.toggleShuffle() }
            Spacer(minLength: 0)
            TransportButton(symbol: "backward.fill", size: 14) { media.previous() }
            TransportButton(symbol: media.nowPlaying.isPlaying ? "pause.fill" : "play.fill",
                            size: 19, prominent: true) { media.playPause() }
            TransportButton(symbol: "forward.fill", size: 14) { media.next() }
            Spacer(minLength: 0)
            TransportButton(symbol: "repeat", size: 11,
                            active: media.nowPlaying.repeating) { media.toggleRepeat() }
        }
        .disabled(!media.isRunning)
        .opacity(media.isRunning ? 1 : 0.35)
    }

    private var playerPicker: some View {
        HStack(spacing: 4) {
            ForEach(MediaPlayer.allCases) { option in
                Button {
                    withAnimation(Theme.content) { media.player = option }
                } label: {
                    Text(option.displayName)
                        .font(.system(size: 9.5, weight: .medium))
                        .foregroundStyle(media.player == option ? .black : Color.white.opacity(0.6))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background {
                            if media.player == option {
                                Capsule().fill(.white)
                            } else {
                                Capsule().fill(.white.opacity(0.08))
                            }
                        }
                }
                .buttonStyle(.plain)
            }
        }
    }

    private static func time(_ seconds: Double) -> String {
        guard seconds.isFinite, seconds >= 0 else { return "0:00" }
        let total = Int(seconds)
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}

struct TransportButton: View {
    let symbol: String
    var size: CGFloat = 14
    var prominent: Bool = false
    var active: Bool = false
    let action: () -> Void

    @State private var hovering = false
    @State private var pressed = false

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: size, weight: prominent ? .semibold : .medium))
                .foregroundStyle(active ? Theme.accent : (hovering ? .white : Color.white.opacity(0.78)))
                .contentTransition(.symbolEffect(.replace))
                .frame(width: prominent ? 34 : 26, height: prominent ? 34 : 26)
                .background {
                    Circle()
                        .fill(.white.opacity(hovering ? 0.14 : (prominent ? 0.08 : 0)))
                }
                .scaleEffect(pressed ? 0.88 : (hovering ? 1.08 : 1.0))
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .animation(Theme.content, value: hovering)
        .animation(.spring(response: 0.2, dampingFraction: 0.6), value: pressed)
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in pressed = true }
                .onEnded { _ in pressed = false })
    }
}

/// Scrolls long titles back and forth instead of truncating them.
struct MarqueeText: View {
    let text: String
    let font: Font

    @State private var textWidth: CGFloat = 0
    @State private var containerWidth: CGFloat = 0

    var body: some View {
        GeometryReader { proxy in
            let overflow = max(0, textWidth - proxy.size.width)
            TimelineView(.animation(paused: overflow <= 0)) { context in
                let cycle = 5.0 + Double(overflow) / 22.0
                let phase = context.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: cycle) / cycle
                // Ease in and out at both ends so the title pauses where it's readable.
                let eased = (1 - cos(phase * 2 * .pi)) / 2
                Text(text)
                    .font(font)
                    .lineLimit(1)
                    .fixedSize()
                    .background(widthReader)
                    .offset(x: -overflow * eased)
            }
            .frame(width: proxy.size.width, alignment: .leading)
            .clipped()
            .onAppear { containerWidth = proxy.size.width }
        }
        .frame(height: 19)
    }

    private var widthReader: some View {
        GeometryReader { proxy in
            Color.clear.onAppear { textWidth = proxy.size.width }
                .onChange(of: text) { _, _ in textWidth = proxy.size.width }
        }
    }
}
