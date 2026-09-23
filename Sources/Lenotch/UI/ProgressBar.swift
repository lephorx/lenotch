import SwiftUI

/// Thin scrubbable progress bar with elapsed and total time underneath.
struct ProgressBar: View {
    let model: NotchViewModel
    let duration: Double

    @State private var dragProgress: Double?

    var body: some View {
        // Redraw every frame while playing so the bar glides instead of stepping.
        TimelineView(.animation(minimumInterval: 1 / 30, paused: !model.media.isPlaying)) { context in
            let elapsed = model.media.elapsed(at: context.date)
            let progress = dragProgress ?? (duration > 0 ? elapsed / duration : 0)
            let shownElapsed = dragProgress.map { $0 * duration } ?? elapsed

            VStack(spacing: 6) {
                bar(progress: progress)
                HStack {
                    Text(Self.format(shownElapsed))
                    Spacer()
                    Text(Self.format(duration))
                }
                .font(.system(size: 11, weight: .medium).monospacedDigit())
                .foregroundStyle(.white.opacity(0.5))
            }
        }
    }

    private func bar(progress: Double) -> some View {
        GeometryReader { proxy in
            let isDragging = dragProgress != nil
            let height: CGFloat = isDragging ? 7 : 4
            let fillWidth = proxy.size.width * min(max(progress, 0), 1)
            ZStack(alignment: .leading) {
                Capsule().fill(.white.opacity(0.18))
                Capsule().fill(model.progressColor ?? .white)
                    .frame(width: fillWidth > 0 ? max(height, fillWidth) : 0)
            }
            .frame(height: height)
            .frame(maxHeight: .infinity)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        guard duration > 0 else { return }
                        model.isInteracting = true
                        dragProgress = min(max(value.location.x / proxy.size.width, 0), 1)
                    }
                    .onEnded { _ in
                        if let dragProgress { model.media.seek(to: dragProgress * duration) }
                        dragProgress = nil
                        model.isInteracting = false
                    }
            )
            .animation(.spring(response: 0.25, dampingFraction: 0.8), value: isDragging)
        }
        .frame(height: 12)
    }

    private static func format(_ seconds: Double) -> String {
        guard seconds.isFinite else { return "0:00" }
        let total = Int(seconds.rounded(.down))
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}
