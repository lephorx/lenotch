import SwiftUI

struct ExpandedView: View {
    let model: NotchViewModel

    @State private var isDropTargeted = false

    private var media: NowPlayingService { model.media }
    private var settings: AppSettings { model.settings }

    var body: some View {
        VStack(spacing: 0) {
            header
                .frame(height: model.geometry.notchSize.height)
            // The new tab's items slide in one by one (`slideIn`); the old tab just fades.
            pageContent
                .environment(\.pageMovesForward, model.pageMovesForward)
                .id(model.visiblePage)
                .transition(.asymmetric(insertion: .identity,
                                        removal: .opacity.animation(.easeOut(duration: 0.12))))
                .padding(.horizontal, 30)
                .padding(.bottom, 20)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .clipped()
        }
        .onDrop(of: [.fileURL], isTargeted: $isDropTargeted) { providers in
            ShelfStore.loadURLs(from: providers) { model.shelf.add($0) }
            return true
        }
        .onChange(of: isDropTargeted) { _, targeted in
            if targeted { model.select(.shelf) }
        }
    }

    @ViewBuilder
    private var pageContent: some View {
        switch model.visiblePage {
        case .player:
            if settings.showMusic {
                HStack(alignment: .top, spacing: 28) {
                    Group {
                        if let track = media.track {
                            NowPlayingView(model: model, track: track)
                        } else {
                            idle.slideIn(0)
                        }
                    }
                    .frame(width: 400)
                    if model.showsCalendar {
                        CalendarPanel(model: model, width: 200)
                            .slideIn(4)
                    }
                }
            } else if model.showsCalendar {
                // Without music the calendar takes the whole tab.
                CalendarPanel(model: model, width: model.openWidth - 60)
                    .slideIn(0)
            } else {
                HomeView(model: model)
            }
        case .shelf:
            ShelfView(model: model, isDropTargeted: isDropTargeted)
                .frame(width: 440)
        case .aiUsage:
            // The AI page has the notch to itself, so it uses the full width (up to 8 rings per row).
            AIUsageView(model: model)
                .frame(maxWidth: .infinity)
        }
    }

    private var header: some View {
        HStack {
            TabSwitcher(model: model)
            Spacer(minLength: model.geometry.notchSize.width + 16)
            HStack(spacing: 10) {
                if model.settings.showMirror, model.isCameraAllowed {
                    HeaderButton(symbol: "camera.fill", label: "Mirror", isOn: model.isMirrorVisible,
                                 action: model.toggleMirror)
                }
                HeaderButton(symbol: "gearshape.fill", label: "Settings", action: model.openSettings)
                if model.battery.hasBattery {
                    BatteryView(battery: model.battery, showsPercentage: settings.showBatteryPercentage)
                }
            }
        }
        .font(.system(size: 11, weight: .medium))
        .foregroundStyle(.white.opacity(0.55))
        .lineLimit(1)
        .fixedSize(horizontal: false, vertical: true)
        .padding(.horizontal, 30)
    }

    private var idleHint: String {
        if let bundleID = media.source.bundleIdentifiers.first, media.source == .spotify || media.source == .appleMusic,
           !AppleScriptProvider.isAllowed(bundleID) {
            return "Allow control of \(media.source.title) in Settings → Permissions."
        }
        return switch media.source {
        case .nowPlaying: "Play something in any app or browser."
        case .spotify: "Play something in Spotify."
        case .appleMusic: "Play something in Music."
        case .youtubeMusic: "Play something on YouTube Music."
        }
    }

    private var idle: some View {
        HStack(spacing: 24) {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(.white.opacity(0.08))
                .frame(width: 120, height: 120)
                .overlay {
                    Image(systemName: "music.note")
                        .font(.system(size: 40, weight: .medium))
                        .foregroundStyle(.white.opacity(0.4))
                }
            VStack(alignment: .leading, spacing: 4) {
                Text("Not Playing")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(.white)
                Text(idleHint)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(.white.opacity(0.5))
            }
            Spacer()
        }
    }
}

private struct TabSwitcher: View {
    let model: NotchViewModel
    /// The selection pill slides between tabs.
    @Namespace private var pill

    private var glass: Bool { model.settings.appearance == .glass }

    var body: some View {
        HStack(spacing: glass ? 4 : 2) {
            ForEach(model.pages) { page in
                let isSelected = model.visiblePage == page
                Button { model.select(page) } label: {
                    Group {
                        if page == .player {
                            if glass || isSelected {
                                AppLogo(height: glass ? 15 : 13, glass: glass,
                                        highlight: isSelected ? 0.2 : 0, color: model.accentColor)
                            } else {
                                AppLogo(height: 13, glass: false).opacity(0.5)
                            }
                        } else {
                            Image(systemName: page.icon)
                                .font(.system(size: glass ? 11 : 10, weight: .semibold))
                                .foregroundStyle(.white.opacity(isSelected ? 1 : 0.5))
                        }
                    }
                    .frame(width: glass ? 34 : 26, height: glass ? 22 : 18)
                    .background {
                        if isSelected {
                            Group {
                                if glass {
                                    Color.clear.notchGlass(true, in: Capsule())
                                } else {
                                    Capsule().fill(.white.opacity(0.18))
                                }
                            }
                            .matchedGeometryEffect(id: "selection", in: pill)
                        }
                    }
                    .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(page.title)
            }
        }
        .padding(glass ? 0 : 2)
        .background(Capsule().fill(.white.opacity(glass ? 0 : 0.08)))
    }
}

private struct HeaderButton: View {
    let symbol: String
    let label: String
    var isOn = false
    let action: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.white.opacity(isOn ? 1 : isHovered ? 0.9 : 0.55))
                .frame(width: 20, height: 20)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
        .onHover { isHovered = $0 }
        .animation(.easeOut(duration: 0.15), value: isHovered)
        .animation(.easeOut(duration: 0.15), value: isOn)
    }
}
