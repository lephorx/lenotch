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
            ZStack {
                tabContent
                    .id(model.visibleTab)
                    .transition(.push(from: model.tabMovesForward ? .trailing : .leading))
            }
            .padding(.horizontal, 30)
            .padding(.bottom, 20)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .clipped()
        }
        // Dropping files anywhere on the open notch puts them on the shelf.
        .onDrop(of: [.fileURL], isTargeted: $isDropTargeted) { providers in
            guard settings.shelfEnabled else { return false }
            ShelfStore.loadURLs(from: providers) { model.shelf.add($0) }
            return true
        }
        .onChange(of: isDropTargeted) { _, targeted in
            if targeted, settings.shelfEnabled { model.select(.shelf) }
        }
    }

    @ViewBuilder
    private var tabContent: some View {
        switch model.visibleTab {
        case .nowPlaying:
            if let track = media.track {
                NowPlayingView(model: model, track: track)
            } else {
                idle
            }
        case .shelf:
            ShelfView(model: model, isDropTargeted: isDropTargeted)
        }
    }

    /// Row beside the physical notch: tabs (or the player) on the left, buttons and battery on the right.
    private var header: some View {
        HStack {
            if model.tabs.count > 1 {
                TabSwitcher(model: model)
            } else {
                HStack(spacing: 6) {
                    if media.track != nil, let icon = media.appIcon {
                        Image(nsImage: icon).resizable().frame(width: 14, height: 14)
                    }
                    Text(media.track != nil ? media.appName ?? media.source.title : media.source.title)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: model.geometry.notchSize.width + 16)
            HStack(spacing: 10) {
                if settings.mirrorEnabled {
                    HeaderButton(symbol: "camera.fill", label: "Mirror", isOn: model.isMirrorVisible,
                                 action: model.toggleMirror)
                }
                HeaderButton(symbol: "gearshape.fill", label: "Settings", action: model.openSettings)
                if settings.showBattery, model.battery.hasBattery {
                    BatteryView(battery: model.battery, showsPercentage: settings.showBatteryPercentage)
                }
            }
        }
        .font(.system(size: 11, weight: .medium))
        .foregroundStyle(.white.opacity(0.55))
        .padding(.horizontal, 30)
    }

    private var idleHint: String {
        switch media.source {
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

/// Tab buttons in the header: the app logo for Now Playing and a tray for the shelf.
/// Glass mode shows the selected tab as a clear glass pill.
private struct TabSwitcher: View {
    let model: NotchViewModel

    private var glass: Bool { model.settings.appearance == .glass }

    var body: some View {
        HStack(spacing: glass ? 4 : 2) {
            ForEach(model.tabs, id: \.self) { tab in
                button(for: tab)
            }
        }
        .padding(glass ? 0 : 2)
        .background(Capsule().fill(.white.opacity(glass ? 0 : 0.08)))
    }

    private func button(for tab: NotchTab) -> some View {
        let isSelected = model.visibleTab == tab
        return Button {
            model.select(tab)
        } label: {
            icon(for: tab, isSelected: isSelected)
                .frame(width: glass ? 34 : 26, height: glass ? 22 : 18)
                .background {
                    if glass {
                        if isSelected {
                            Color.clear.notchGlass(true, in: Capsule())
                        }
                    } else {
                        Capsule().fill(.white.opacity(isSelected ? 0.18 : 0))
                    }
                }
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label(for: tab))
        .animation(.easeOut(duration: 0.15), value: isSelected)
    }

    @ViewBuilder
    private func icon(for tab: NotchTab, isSelected: Bool) -> some View {
        switch tab {
        case .nowPlaying:
            AppLogo(height: glass ? 15 : 13, glass: glass, highlight: isSelected ? 0.2 : 0,
                    color: model.accentColor)
                .opacity(glass || isSelected ? 1 : 0.6)
        case .shelf:
            symbol(glass ? "tray.fill" : "tray.full", isSelected: isSelected)
        }
    }

    private func symbol(_ name: String, isSelected: Bool) -> some View {
        Image(systemName: name)
            .font(.system(size: glass ? 11 : 10, weight: .semibold))
            .foregroundStyle(.white.opacity(isSelected ? 1 : 0.5))
    }

    private func label(for tab: NotchTab) -> String {
        switch tab {
        case .nowPlaying: "Now Playing"
        case .shelf: "Shelf"
        }
    }
}

/// Small icon button in the header row; bright while `isOn`.
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
