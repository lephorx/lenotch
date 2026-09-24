import SwiftUI

/// Which ring the pointer is on, and where it is horizontally in the notch window.
struct UsageHover: Equatable {
    let id: String
    let anchorX: CGFloat
}

/// codenotch's hover card: a black speech bubble below the notch, pointing up at
/// the hovered ring, with each limit window's bar, percentage and reset time.
struct UsageTooltip: View {
    let model: NotchViewModel

    static let width: CGFloat = 300
    static let pointerHeight: CGFloat = 10

    private var hovered: (UsageSource, ProviderUsage)? {
        guard let id = model.usageHover?.id,
              let source = model.settings.usageSources.first(where: { $0.id == id }) else { return nil }
        return (source, model.aiUsage.usage[id] ?? .loading)
    }

    var body: some View {
        TimelineView(.everyMinute) { context in
            ZStack(alignment: .top) {
                if let (source, usage) = hovered {
                    card(source: source, usage: usage, now: context.date)
                        .transition(.opacity.combined(with: .scale(0.96, anchor: .top)))
                        .id(source.id)
                }
            }
            .frame(width: Self.width, alignment: .top)
            .frame(maxHeight: .infinity, alignment: .top)
            .animation(.easeOut(duration: 0.15), value: model.usageHover?.id)
        }
    }

    private func card(source: UsageSource, usage: ProviderUsage, now: Date) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                ProviderGlyphView(glyph: source.glyph, size: 18)
                Text("\(source.title) Usage").font(.system(size: 15))
                if case .ok(let plan?, _) = usage {
                    Text(plan).font(.system(size: 12)).foregroundStyle(.white.opacity(0.45))
                }
            }
            .foregroundStyle(.white)

            switch usage {
            case .ok(_, let windows):
                ForEach(windows.prefix(4)) { window in
                    WindowBlock(window: window, now: now)
                }
            case .loading:
                Text("Loading…").font(.system(size: 12)).foregroundStyle(.white.opacity(0.5))
            case .problem(let message):
                Text(message).font(.system(size: 12)).foregroundStyle(.orange)
            case .notSetUp:
                EmptyView()
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 14)
        .padding(.bottom, 16)
        .frame(width: Self.width, alignment: .leading)
        .background(BubbleShape(pointerHeight: Self.pointerHeight).fill(.black))
        .padding(.top, Self.pointerHeight)
        .environment(\.colorScheme, .dark)
    }
}

private struct WindowBlock: View {
    let window: UsageWindow
    let now: Date

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(window.label).foregroundStyle(.white)
                Spacer(minLength: 8)
                if let reset = resetText {
                    Text(reset).foregroundStyle(.white.opacity(0.45))
                }
            }
            .font(.system(size: 12))
            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color(white: 0.2))
                    Capsule().fill(UsageColor.of(window.used))
                        .frame(width: max(6, proxy.size.width * min(max(window.used, 0), 1)))
                }
            }
            .frame(height: 6)
            Text("\(Int((window.used * 100).rounded()))% Used")
                .font(.system(size: 12))
                .foregroundStyle(.white)
        }
    }

    /// "Resets in 51 min" within a day, otherwise "Resets Thu 12:00 AM".
    private var resetText: String? {
        guard let date = window.resetsAt else { return nil }
        let seconds = max(0, date.timeIntervalSince(now))
        if seconds < 3_600 { return "Resets in \(max(1, Int(seconds / 60))) min" }
        if seconds < 86_400 {
            let hours = Int(seconds / 3_600), minutes = Int(seconds.truncatingRemainder(dividingBy: 3_600) / 60)
            return minutes > 0 ? "Resets in \(hours) hr \(minutes) min" : "Resets in \(hours) hr"
        }
        return "Resets \(date.formatted(.dateTime.weekday(.abbreviated).hour().minute()))"
    }
}

/// Rounded card with a small pointer centred on its top edge.
private struct BubbleShape: Shape {
    let pointerHeight: CGFloat

    func path(in rect: CGRect) -> Path {
        var path = Path(roundedRect: rect, cornerRadius: 22, style: .continuous)
        let tip = CGPoint(x: rect.midX, y: rect.minY - pointerHeight)
        path.move(to: CGPoint(x: rect.midX - 14, y: rect.minY + 1))
        path.addQuadCurve(to: tip, control: CGPoint(x: rect.midX - 4, y: rect.minY))
        path.addQuadCurve(to: CGPoint(x: rect.midX + 14, y: rect.minY + 1), control: CGPoint(x: rect.midX + 4, y: rect.minY))
        path.closeSubpath()
        return path
    }
}
