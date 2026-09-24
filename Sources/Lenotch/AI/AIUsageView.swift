import SwiftUI

/// Usage limits of the enabled coding assistants as rings, like codenotch: the
/// provider's mark inside, the headline window (e.g. the current session) as the
/// arc, the percentage underneath. Eight per row, at most two rows. Hovering a ring
/// shows its limit windows in a bubble below the notch (`UsageTooltip`).
struct AIUsageView: View {
    let model: NotchViewModel

    private static let ringsPerRow = 8
    private static let maxRows = 2

    private var service: AIUsageService { model.aiUsage }
    private var sources: [UsageSource] { model.settings.usageSources }

    /// Sources with something to show (tools that aren't set up are hidden).
    private var visible: [(UsageSource, ProviderUsage)] {
        let shown = sources.compactMap { source -> (UsageSource, ProviderUsage)? in
            let usage = service.usage[source.id] ?? .loading
            return usage == .notSetUp ? nil : (source, usage)
        }
        return Array(shown.prefix(Self.ringsPerRow * Self.maxRows))
    }

    var body: some View {
        Group {
            if visible.isEmpty {
                empty
            } else {
                let rows = stride(from: 0, to: visible.count, by: Self.ringsPerRow).map {
                    Array(visible[$0..<min($0 + Self.ringsPerRow, visible.count)])
                }
                let compact = rows.count > 1
                VStack(spacing: compact ? 8 : 0) {
                    ForEach(rows.indices, id: \.self) { index in
                        HStack(alignment: .top, spacing: compact ? 18 : 26) {
                            ForEach(Array(rows[index].enumerated()), id: \.element.0.id) { position, item in
                                RingCell(model: model, source: item.0, usage: item.1, diameter: compact ? 40 : 52)
                                    .slideIn(index * 8 + position)
                            }
                        }
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .onDisappear { model.setUsageHover(nil) }
        // Poll only while the widget is on screen.
        .task(id: sources.map(\.id)) {
            while !Task.isCancelled {
                await service.refresh(sources)
                try? await Task.sleep(for: .seconds(120))
            }
        }
    }

    private var empty: some View {
        VStack(alignment: .leading, spacing: 4) {
            Label("AI Usage", systemImage: "sparkles")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.white)
            Text(sources.isEmpty
                 ? "Turn on a provider in Settings → AI Usage."
                 : "Sign in to Claude Code, Codex, Cursor or another supported tool to see usage here.")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.white.opacity(0.5))
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

extension ProviderUsage {
    var windows: [UsageWindow] {
        if case .ok(_, let windows) = self { return windows }
        return []
    }

    var headline: UsageWindow? { windows.first }
}

/// codenotch's bands: green, then yellow from 50%, then orange-red from 70%.
enum UsageColor {
    static func of(_ used: Double) -> Color {
        switch used {
        case ..<0.5: Color(red: 0.13, green: 0.88, blue: 0.54)
        case ..<0.7: Color(red: 0.95, green: 0.95, blue: 0.05)
        default: Color(red: 1, green: 0.24, blue: 0.06)
        }
    }
}

private struct RingCell: View {
    let model: NotchViewModel
    let source: UsageSource
    let usage: ProviderUsage
    let diameter: CGFloat

    @State private var frame: CGRect = .zero

    private var isHovered: Bool { model.usageHover?.id == source.id }

    var body: some View {
        VStack(spacing: diameter > 44 ? 8 : 4) {
            ZStack {
                // Strokes are inset by half their width so they stay inside the frame.
                Circle().inset(by: lineWidth / 2).stroke(Color(white: 0.2), lineWidth: lineWidth)
                if let headline = usage.headline {
                    Circle()
                        .inset(by: lineWidth / 2)
                        .trim(from: 0, to: min(max(headline.used, 0), 1))
                        .stroke(UsageColor.of(headline.used), style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                        .animation(.easeOut(duration: 0.6), value: headline.used)
                }
                ProviderGlyphView(glyph: source.glyph, size: diameter * 0.4)
                    .foregroundStyle(.white)
            }
            .frame(width: diameter, height: diameter)
            .scaleEffect(isHovered ? 1.05 : 1)
            .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isHovered)

            Group {
                switch usage {
                case .ok:
                    Text("\(Int(((usage.headline?.used ?? 0) * 100).rounded()))%")
                case .loading:
                    Text("–")
                case .problem, .notSetUp:
                    Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                }
            }
            .font(.system(size: diameter > 44 ? 15 : 12, weight: .medium).monospacedDigit())
            .foregroundStyle(.white)
        }
        .contentShape(Rectangle())
        // Where the ring is in the notch window, so the bubble can point at it.
        .background(GeometryReader { proxy in
            Color.clear
                .onAppear { frame = proxy.frame(in: .global) }
                .onChange(of: proxy.frame(in: .global)) { _, new in frame = new }
        })
        .onHover { hovering in
            if hovering {
                model.setUsageHover(UsageHover(id: source.id, anchorX: frame.midX))
            } else if isHovered {
                model.setUsageHover(nil)
            }
        }
    }

    private var lineWidth: CGFloat { diameter > 44 ? 5 : 4 }
}
