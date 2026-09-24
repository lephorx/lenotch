import SwiftUI

/// Root view: a black notch that animates between closed, live activity and open.
struct NotchView: View {
    let model: NotchViewModel

    private var isOpen: Bool { model.state == .open }
    /// Open or playing the intro: uses the open notch's shape and background.
    private var isExpanded: Bool { isOpen || model.isShowingIntro || model.isShowingAppearancePreview || model.isPeeking }

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
                                artwork: isOpen && model.visiblePage == .player
                                    && model.settings.showMusic && model.settings.gradient(for: model.settings.appearance).bottomFollowsMusic
                                    ? model.media.artwork : nil)
            }
            .clipShape(shape)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .animation(.spring(response: 0.42, dampingFraction: 0.82), value: model.state)
            .animation(.spring(response: 0.5, dampingFraction: 0.78), value: model.isShowingIntro)
            .animation(.spring(response: 0.5, dampingFraction: 0.78), value: model.isShowingAppearancePreview)
            .animation(.spring(response: 0.45, dampingFraction: 0.8), value: model.isPeeking)
            .animation(.spring(response: 0.42, dampingFraction: 0.82), value: model.showsLiveActivity)
            .animation(.easeInOut(duration: 0.3), value: model.settings.appearance)
            .animation(.easeInOut(duration: 0.6), value: model.backgroundGradient)
            .environment(\.colorScheme, .dark)
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
        } else if model.isPeeking, let track = model.media.track {
            PeekView(model: model, track: track)
                .transition(.opacity.combined(with: .scale(0.95, anchor: .top)))
        } else if model.showsLiveActivity {
            LiveActivityView(model: model)
                .transition(.opacity)
        } else {
            Color.clear
        }
    }
}
