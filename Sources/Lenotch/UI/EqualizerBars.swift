import SwiftUI

/// Bars that follow the real audio when `levels` has a signal, and otherwise
/// bounce with a stand-in animation while playing; they settle when paused.
struct EqualizerBars: View {
    let isPlaying: Bool
    var color: Color = .white
    var levels: AudioVisualizer? = nil

    private static let speeds: [Double] = [5.1, 7.3, 4.2, 6.4]
    private static let phases: [Double] = [0, 1.7, 3.1, 0.8]

    var body: some View {
        // 30 fps is plenty for bars and far cheaper than the display's 120 Hz.
        TimelineView(.animation(minimumInterval: 1 / 30, paused: !isPlaying)) { context in
            let time = context.date.timeIntervalSinceReferenceDate
            let real = levels.flatMap { $0.hasSignal ? $0.levels : nil }
            GeometryReader { proxy in
                let count = Self.speeds.count
                let spacing = proxy.size.width * 0.12
                let barWidth = (proxy.size.width - spacing * CGFloat(count - 1)) / CGFloat(count)
                HStack(alignment: .center, spacing: spacing) {
                    ForEach(0..<count, id: \.self) { index in
                        let level: Double = if !isPlaying {
                            0.2
                        } else if let real, index < real.count {
                            0.15 + 0.85 * Double(real[index])
                        } else {
                            0.3 + 0.7 * abs(sin(time * Self.speeds[index] + Self.phases[index]))
                        }
                        Capsule()
                            .fill(color)
                            .frame(width: barWidth, height: max(barWidth, proxy.size.height * level))
                    }
                }
                .frame(width: proxy.size.width, height: proxy.size.height)
            }
        }
        .animation(.easeOut(duration: 0.3), value: isPlaying)
        .animation(.easeInOut(duration: 0.6), value: color)
    }
}
