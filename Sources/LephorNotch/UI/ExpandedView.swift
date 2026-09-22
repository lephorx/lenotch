import SwiftUI

struct ExpandedView: View {
    @ObservedObject var model: NotchViewModel
    var notchWidth: CGFloat

    var body: some View {
        VStack(spacing: 0) {
            header
            content
                .padding(.horizontal, 18)
                .padding(.bottom, 16)
                .padding(.top, 4)
        }
    }

    /// The header straddles the hardware cutout: tabs on the left, clock and status on the
    /// right, and a transparent gap in the middle where the camera lives.
    private var header: some View {
        HStack(spacing: 0) {
            HStack(spacing: 2) {
                ForEach(NotchTab.allCases) { tab in
                    TabChip(tab: tab, selected: model.tab == tab) { model.select(tab) }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.leading, 14)

            Color.clear.frame(width: notchWidth)

            HStack(spacing: 10) {
                Spacer(minLength: 0)
                ClockLabel()
                if model.battery.hasBattery {
                    BatteryIndicator(battery: model.battery, showPercent: true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .trailing)
            .padding(.trailing, 14)
        }
        .frame(height: max(model.geometry.notchSize.height, 30))
    }

    @ViewBuilder
    private var content: some View {
        ZStack {
            switch model.tab {
            case .home:
                MusicView(media: model.media, battery: model.battery)
                    .transition(transition)
            case .calendar:
                CalendarPanel(service: model.calendar)
                    .transition(transition)
            case .shelf:
                ShelfPanel(shelf: model.shelf)
                    .transition(transition)
            case .settings:
                SettingsPanel(model: model, settings: model.settings, hud: model.hud)
                    .transition(transition)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var transition: AnyTransition {
        .asymmetric(
            insertion: .opacity.combined(with: .offset(y: 8)).combined(with: .scale(scale: 0.98)),
            removal: .opacity.combined(with: .scale(scale: 0.98)))
    }
}

private struct TabChip: View {
    let tab: NotchTab
    let selected: Bool
    let action: () -> Void

    @State private var hovering = false
    @Namespace private var namespace

    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Image(systemName: tab.symbol)
                    .font(.system(size: 10, weight: .semibold))
                if selected {
                    Text(tab.title)
                        .font(.system(size: 10, weight: .semibold))
                        .fixedSize()
                        .transition(.opacity.combined(with: .offset(x: -6)))
                }
            }
            .foregroundStyle(selected ? .white : Color.white.opacity(hovering ? 0.8 : 0.45))
            .padding(.horizontal, selected ? 9 : 7)
            .padding(.vertical, 5)
            .background {
                if selected {
                    Capsule().fill(.white.opacity(0.14))
                } else if hovering {
                    Capsule().fill(.white.opacity(0.06))
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .animation(Theme.content, value: hovering)
        .help(tab.title)
    }
}

struct ClockLabel: View {
    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let formatter = Self.formatter
            Text(formatter.string(from: context.date))
                .font(.system(size: 11, weight: .medium, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(.white.opacity(0.85))
        }
    }

    private static let formatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEE d MMM  HH:mm"
        return formatter
    }()
}
