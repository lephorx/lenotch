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
    var musicColor: Color? = nil

    var body: some View {
        GeometryReader { proxy in
            let solidFraction = notchHeight / max(proxy.size.height, 1)
            ZStack {
                if appearance == .glass {
                    GlassFill(shape: shape)
                }
                LinearGradient(stops: gradient.stops(solidFraction: solidFraction),
                               startPoint: .top, endPoint: .bottom)
                if let musicColor, isOpen {
                    // Keep the album colour near the cover in the lower left.
                    // The top stays black and the right side remains quiet.
                    RadialGradient(colors: [
                        musicColor.opacity(appearance == .glass ? 0.30 : 0.42),
                        musicColor.opacity(0.13),
                        .clear
                    ], center: UnitPoint(x: 0.12, y: 0.98), startRadius: 0,
                       endRadius: proxy.size.width * 0.58)
                        .mask {
                            LinearGradient(stops: [
                                .init(color: .clear, location: 0),
                                .init(color: .clear, location: solidFraction),
                                .init(color: .white, location: min(solidFraction + 0.48, 1)),
                                .init(color: .white, location: 1)
                            ], startPoint: .top, endPoint: .bottom)
                        }
                    // A narrow rim carries that colour along the bottom edge.
                    shape.stroke(
                        LinearGradient(colors: [musicColor.opacity(0.8),
                                                musicColor.opacity(0.55),
                                                musicColor.opacity(0.28)],
                                       startPoint: .leading, endPoint: .trailing),
                        lineWidth: 2
                    )
                    .mask {
                        LinearGradient(stops: [
                            .init(color: .clear, location: 0),
                            .init(color: .clear, location: 0.55),
                            .init(color: .white, location: 0.9),
                            .init(color: .white, location: 1)
                        ], startPoint: .top, endPoint: .bottom)
                    }
                }
                Color.black.opacity(isOpen ? 0 : 1)
            }
        }
    }
}

private struct GlassFill: View {
    let shape: NotchShape

    var body: some View {
        Color.clear.notchGlass(true, in: shape).allowsHitTesting(false)
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
        // The gradient spans the whole notch height (only a slice shows), so it must not
        // take clicks: it used to swallow clicks on the progress bar above the pill.
        .allowsHitTesting(false)
    }
}
