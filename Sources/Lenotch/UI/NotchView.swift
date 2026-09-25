import SwiftUI

/// Root view: a black notch that animates between closed, live activity and open.
struct NotchView: View {
    let model: NotchViewModel

    private var isOpen: Bool { model.state == .open }
    /// Open or playing the intro: uses the open notch's shape and background.
    private var isExpanded: Bool {
        isOpen || model.isShowingIntro || model.isShowingAppearancePreview || model.isTimerFinished
            || (model.isPeeking && model.indicator == nil)
    }

    var body: some View {
        let size = model.currentSize
        let top = isExpanded ? NotchShape.openTopRadius : NotchShape.closedTopRadius
        let bottom = isExpanded ? NotchShape.openBottomRadius : NotchShape.closedBottomRadius
        let shape = NotchShape(topRadius: top, bottomRadius: bottom)

        content
            .frame(width: size.width, height: size.height, alignment: .top)
            .coordinateSpace(.named(NotchGradientSlice.coordinateSpace))
            .padding(.horizontal, top)
            .background {
                NotchBackground(appearance: model.settings.appearance,
                                gradient: model.backgroundGradient, isOpen: isExpanded,
                                notchHeight: model.geometry.notchSize.height, shape: shape,
                                musicColor: isOpen && model.visiblePage == .player
                                    && model.settings.showMusic && model.settings.gradient(for: model.settings.appearance).bottomFollowsMusic
                                    ? model.accentColor : nil)
            }
            // Microphone (orange) or camera (green) in use: a thin outline around the notch.
            // Stroked on the edge and clipped, so the line sits just inside it.
            .overlay {
                if let color = privacyColor {
                    PrivacyOutline(shape: shape, color: color)
                        .transition(.opacity)
                }
            }
            .clipShape(shape)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .animation(.spring(response: 0.42, dampingFraction: 0.82), value: model.state)
            .animation(.spring(response: 0.5, dampingFraction: 0.78), value: model.isShowingIntro)
            .animation(.spring(response: 0.5, dampingFraction: 0.78), value: model.isShowingAppearancePreview)
            .animation(.spring(response: 0.45, dampingFraction: 0.8), value: model.isPeeking)
            .animation(.spring(response: 0.42, dampingFraction: 0.82), value: model.showsLiveActivity)
            .animation(.spring(response: 0.38, dampingFraction: 0.82), value: model.indicator != nil)
            .animation(.spring(response: 0.42, dampingFraction: 0.82), value: model.showsPrivacy)
            .animation(.spring(response: 0.42, dampingFraction: 0.82), value: model.showsCrypto)
            .animation(.spring(response: 0.42, dampingFraction: 0.82), value: model.showsNetwork)
            .animation(.spring(response: 0.42, dampingFraction: 0.82), value: model.timer.isActive)
            // Folding down when the timer ends: a little bouncier than the peek.
            .animation(.spring(response: 0.5, dampingFraction: 0.62), value: model.isTimerFinished)
            // Turning the ticker on, or picking other coins, fetches right away.
            .task(id: "\(model.settings.showCrypto)\(model.settings.cryptoCoins)\(model.settings.cryptoCurrency)") {
                model.crypto.refresh()
            }
            .animation(.easeInOut(duration: 0.3), value: model.settings.appearance)
            .animation(.easeInOut(duration: 0.25), value: model.backgroundGradient)
            .animation(.easeInOut(duration: 0.6), value: model.accentColor)
            .environment(\.colorScheme, .dark)
    }

    private var privacyColor: Color? {
        guard model.showsPrivacy else { return nil }
        return model.privacy.isMicOn ? .orange : .green
    }

    @ViewBuilder
    private var content: some View {
        if model.isShowingIntro {
            IntroView(notchHeight: model.geometry.notchSize.height) {
                model.isShowingIntro = false
            }
                .id(model.introGeneration)
                .transition(.opacity)
        } else if model.isShowingAppearancePreview {
            AppearanceLivePreview(notchHeight: model.geometry.notchSize.height)
                .transition(.opacity)
        } else if isOpen {
            ExpandedView(model: model)
                .transition(.blurReplace.combined(with: .scale(0.92, anchor: .top)))
        } else if model.isTimerFinished {
            TimerDoneView(model: model)
                .transition(.opacity.combined(with: .scale(0.95, anchor: .top)))
        } else if let indicator = model.indicator {
            IndicatorView(indicator: indicator, notchWidth: model.geometry.notchSize.width)
                .transition(.opacity)
        } else if model.isPeeking, let track = model.media.track {
            PeekView(model: model, track: track)
                .transition(.opacity.combined(with: .scale(0.95, anchor: .top)))
        } else if model.timer.isActive {
            TimerLiveView(model: model)
                .transition(.opacity)
        } else if model.showsLiveActivity {
            LiveActivityView(model: model)
                .transition(.opacity)
        } else if model.showsNetwork, let speed = model.network {
            NetworkSpeedView(speed: speed, notchWidth: model.geometry.notchSize.width)
                .transition(.opacity)
        } else if model.showsCrypto {
            CryptoTickerView(model: model)
                .transition(.opacity)
        } else {
            Color.clear
        }
    }
}

/// The outline shown while the microphone or camera is in use, gently pulsing.
private struct PrivacyOutline: View {
    let shape: NotchShape
    let color: Color
    @State private var bright = false

    var body: some View {
        shape.stroke(color, lineWidth: 3)
            .shadow(color: color.opacity(0.8), radius: 3)
            .opacity(bright ? 1 : 0.6)
            .allowsHitTesting(false)
            .onAppear {
                withAnimation(.easeInOut(duration: 1.4).repeatForever(autoreverses: true)) { bright = true }
            }
    }
}
