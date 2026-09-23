import SwiftUI

/// Fill behind the notch. Open, it's the user's colour transition for the
/// current style, over Liquid Glass in the glass style. Closed it's always
/// black so it matches the hardware notch.
struct NotchBackground: View {
    let appearance: Appearance
    let gradient: NotchGradient
    let isOpen: Bool
    let notchHeight: CGFloat
    let shape: NotchShape

    var body: some View {
        GeometryReader { proxy in
            let solidFraction = notchHeight / max(proxy.size.height, 1)
            ZStack {
                if appearance == .glass {
                    GlassFill(shape: shape)
                }
                LinearGradient(stops: gradient.stops(solidFraction: solidFraction),
                               startPoint: .top, endPoint: .bottom)
                Color.black.opacity(isOpen ? 0 : 1)
            }
        }
    }
}

private struct GlassFill: View {
    let shape: NotchShape

    var body: some View {
        Color.clear.notchGlass(true, in: shape)
    }
}

/// The part of the notch's colour transition that sits behind this view, so a
/// glass element (like the playback pill) shows the same shade as the notch
/// around it instead of the raw desktop.
struct NotchGradientSlice: View {
    static let coordinateSpace = "notch"

    let model: NotchViewModel

    var body: some View {
        GeometryReader { proxy in
            let frame = proxy.frame(in: .named(Self.coordinateSpace))
            let notchHeight = model.currentSize.height
            LinearGradient(stops: model.backgroundGradient.stops(
                               solidFraction: model.geometry.notchSize.height / max(notchHeight, 1)),
                           startPoint: .top, endPoint: .bottom)
                .frame(width: proxy.size.width, height: notchHeight)
                .offset(y: -frame.minY)
        }
    }
}
