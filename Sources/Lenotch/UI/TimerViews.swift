import SwiftUI

/// A ring that empties as the timer runs down.
struct TimerRing: View {
    let fraction: Double
    var lineWidth: CGFloat = 2.5
    var color: Color = .orange

    var body: some View {
        ZStack {
            Circle().stroke(.white.opacity(0.15), lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: max(fraction, 0.001))
                .stroke(color, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
        }
    }
}

/// Closed notch while a timer runs. With music playing: artwork and bars left of the
/// notch, ring and time right of it; otherwise just the ring and the time.
struct TimerLiveView: View {
    let model: NotchViewModel

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let timer = model.timer
            let side = model.geometry.notchSize.height - 10
            HStack(spacing: 0) {
                HStack(spacing: 8) {
                    if model.showsLiveActivity {
                        ArtworkView(artwork: model.media.artwork, fallback: model.media.appIcon, cornerRadius: 6)
                            .frame(width: side, height: side)
                        EqualizerBars(isPlaying: model.media.isPlaying, color: model.equalizerColor,
                                      levels: model.equalizerSource)
                            .frame(width: side * 0.7, height: side * 0.55)
                    } else {
                        Image(systemName: timer.isPaused ? "pause.fill" : "timer")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(.orange)
                    }
                }
                .padding(.leading, 10)
                .frame(width: NotchGeometry.timerSideWidth, alignment: .leading)
                Spacer(minLength: model.geometry.notchSize.width)
                HStack(spacing: 7) {
                    TimerRing(fraction: timer.fraction(at: context.date), lineWidth: 2.5)
                        .frame(width: 15, height: 15)
                        .animation(.linear(duration: 1), value: timer.fraction(at: context.date))
                    Text(NotchTimer.format(timer.remaining(at: context.date)))
                        .font(.system(size: 12, weight: .semibold).monospacedDigit())
                        .foregroundStyle(timer.isPaused ? .white.opacity(0.5) : .white)
                        .contentTransition(.numericText(countsDown: true))
                        .animation(.default, value: Int(timer.remaining(at: context.date)))
                }
                .padding(.trailing, 12)
                .frame(width: NotchGeometry.timerSideWidth, alignment: .trailing)
            }
            .frame(maxHeight: .infinity)
        }
    }
}

/// The card the notch folds down into when a timer ends: a ringing bell and a
/// pulsing glow, until the pointer opens the notch or it folds back up.
struct TimerDoneView: View {
    let model: NotchViewModel
    @State private var ring = false
    @State private var glow = false

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(Color.orange.opacity(glow ? 0.35 : 0.12))
                    .frame(width: 40, height: 40)
                    .scaleEffect(glow ? 1.12 : 0.9)
                Image(systemName: "bell.fill")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(.orange)
                    .rotationEffect(.degrees(ring ? 16 : -16), anchor: .top)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text("Timer done")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(.white)
                Text(model.finishedTimerLabel)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.white.opacity(0.6))
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 18)
        .padding(.top, model.geometry.notchSize.height + 8)
        .padding(.bottom, 12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .onAppear {
            withAnimation(.easeInOut(duration: 0.12).repeatForever(autoreverses: true)) { ring = true }
            withAnimation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true)) { glow = true }
        }
    }
}

/// In the open notch: presets to start a timer, or the running timer's controls.
struct TimerPanel: View {
    let model: NotchViewModel
    @State private var customMinutes = 20

    private static let presets = [1, 3, 5, 10, 15, 25, 30, 45, 60]

    var body: some View {
        let timer = model.timer
        Group {
            if timer.isActive {
                running(timer)
            } else {
                picker
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var picker: some View {
        VStack(spacing: 14) {
            LazyVGrid(columns: Array(repeating: GridItem(.fixed(62), spacing: 8), count: 5), spacing: 8) {
                ForEach(Self.presets, id: \.self) { minutes in
                    chip(minutes < 60 ? "\(minutes) min" : "1 h") { start(minutes) }
                }
                chip("Custom", highlighted: true) { start(customMinutes) }
            }
            HStack(spacing: 10) {
                roundButton("minus") { customMinutes = max(1, customMinutes - (customMinutes > 10 ? 5 : 1)) }
                Text("\(customMinutes) min")
                    .font(.system(size: 13, weight: .semibold).monospacedDigit())
                    .foregroundStyle(.white)
                    .frame(width: 70)
                roundButton("plus") { customMinutes = min(600, customMinutes + (customMinutes >= 10 ? 5 : 1)) }
            }
        }
        .slideIn(0)
    }

    private func running(_ timer: NotchTimer) -> some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            HStack(spacing: 28) {
                ZStack {
                    TimerRing(fraction: timer.fraction(at: context.date), lineWidth: 6)
                        .animation(.linear(duration: 1), value: timer.fraction(at: context.date))
                    Text(NotchTimer.format(timer.remaining(at: context.date)))
                        .font(.system(size: 22, weight: .bold).monospacedDigit())
                        .foregroundStyle(timer.isPaused ? .white.opacity(0.5) : .white)
                        .contentTransition(.numericText(countsDown: true))
                        .animation(.default, value: Int(timer.remaining(at: context.date)))
                }
                .frame(width: 110, height: 110)
                VStack(spacing: 10) {
                    HStack(spacing: 10) {
                        roundButton(timer.isPaused ? "play.fill" : "pause.fill", size: 40) {
                            timer.isPaused ? timer.resume() : timer.pause()
                        }
                        roundButton("xmark", size: 40) { timer.cancel() }
                    }
                    chip("+1 min") { timer.add(60) }
                }
            }
            .slideIn(0)
        }
    }

    private func start(_ minutes: Int) {
        model.timer.start(TimeInterval(minutes * 60))
    }

    private func chip(_ title: String, highlighted: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(highlighted ? .black : .white)
                .frame(width: 62, height: 28)
                .background(Capsule().fill(highlighted ? Color.orange : .white.opacity(0.1)))
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    private func roundButton(_ symbol: String, size: CGFloat = 28, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: size * 0.38, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: size, height: size)
                .background(Circle().fill(.white.opacity(0.12)))
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
    }
}
