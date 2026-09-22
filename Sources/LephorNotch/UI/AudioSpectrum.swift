import SwiftUI

/// A stylised spectrum. macOS gives no tap on another app's audio without a virtual device,
/// so these bars are driven by a pseudo-random walk seeded per bar — they read as "audio is
/// playing" without pretending to be a real FFT.
struct AudioSpectrumView: View {
    var isPlaying: Bool
    var tint: Color
    var barCount: Int = 4
    var barWidth: CGFloat = 2.6
    var maxHeight: CGFloat = 13

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 24.0, paused: !isPlaying)) { context in
            let t = context.date.timeIntervalSinceReferenceDate
            HStack(alignment: .center, spacing: barWidth * 0.8) {
                ForEach(0..<barCount, id: \.self) { index in
                    Capsule()
                        .fill(tint)
                        .frame(width: barWidth, height: height(for: index, at: t))
                }
            }
            .frame(height: maxHeight)
            .animation(.easeOut(duration: 0.08), value: isPlaying)
        }
    }

    private func height(for index: Int, at time: TimeInterval) -> CGFloat {
        guard isPlaying else { return barWidth }
        // Two incommensurate sines per bar so the pattern never visibly loops.
        let phase = Double(index) * 1.7
        let a = sin(time * 6.1 + phase)
        let b = sin(time * 2.7 + phase * 2.3)
        let level = (a * 0.6 + b * 0.4 + 1) / 2
        return max(barWidth, CGFloat(level) * maxHeight)
    }
}
