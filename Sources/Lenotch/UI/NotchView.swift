import SwiftUI

/// Root view: a black notch that animates between closed, live activity and open.
struct NotchView: View {
    let model: NotchViewModel

    private var isOpen: Bool { model.state == .open }

    var body: some View {
        let size = model.currentSize
        let top = isOpen ? NotchShape.openTopRadius : NotchShape.closedTopRadius
        let bottom = isOpen ? NotchShape.openBottomRadius : NotchShape.closedBottomRadius
        let shape = NotchShape(topRadius: top, bottomRadius: bottom)

        content
            .frame(width: size.width, height: size.height, alignment: .top)
            .coordinateSpace(.named(NotchGradientSlice.coordinateSpace))
            .padding(.horizontal, top)
            .background {
                NotchBackground(appearance: model.settings.appearance,
                                gradient: model.backgroundGradient, isOpen: isOpen,
                                notchHeight: model.geometry.notchSize.height, shape: shape)
            }
            .clipShape(shape)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .animation(.spring(response: 0.42, dampingFraction: 0.82), value: model.state)
            .animation(.spring(response: 0.42, dampingFraction: 0.82), value: model.showsLiveActivity)
            .animation(.easeInOut(duration: 0.3), value: model.settings.appearance)
            .animation(.easeInOut(duration: 0.6), value: model.backgroundGradient)
            .environment(\.colorScheme, .dark)
    }

    @ViewBuilder
    private var content: some View {
        if isOpen {
            ExpandedView(model: model)
                .transition(.blurReplace.combined(with: .scale(0.92, anchor: .top)))
        } else if model.showsLiveActivity {
            LiveActivityView(model: model)
                .transition(.opacity)
        } else {
            Color.clear
        }
    }
}
