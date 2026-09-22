import SwiftUI

/// The panel's surface. The top band stays opaque black so it merges with the physical
/// notch and the menu bar; everything below fades into Liquid Glass, so the further the
/// panel extends past the cutout the more of the desktop shows through it.
struct NotchBackground: View {
    let shape: NotchShape
    let appearance: NotchAppearance
    let isOpen: Bool
    let tint: [Color]
    /// Height of the fully-opaque black band, in points — normally the hardware notch height.
    let blackBandHeight: CGFloat

    var body: some View {
        ZStack {
            if appearance == .liquidGlass && isOpen {
                Color.clear
                    .notchGlass(in: shape, enabled: true)
            }

            // Album-art tint, strongest in the middle of the panel where the art sits.
            if isOpen && appearance == .liquidGlass {
                LinearGradient(
                    colors: [tint.first?.opacity(0.34) ?? .clear,
                             tint.last?.opacity(0.16) ?? .clear,
                             .clear],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing)
                    .blur(radius: 26)
                    .clipShape(shape)
                    .blendMode(.plusLighter)
            }

            // The black-to-transparent fall-off. When closed (or in Pure Black) it covers
            // the whole panel, so the notch reads as solid hardware.
            GeometryReader { proxy in
                LinearGradient(stops: blackStops(height: proxy.size.height),
                               startPoint: .top,
                               endPoint: .bottom)
            }
            .clipShape(shape)

            // Hairline rim, brighter along the top edge where the light would catch.
            shape.strokeBorder(
                LinearGradient(colors: [.white.opacity(isOpen ? 0.22 : 0.06),
                                        .white.opacity(0.02)],
                               startPoint: .top,
                               endPoint: .bottom),
                lineWidth: 0.8)
        }
        .compositingGroup()
        .shadow(color: .black.opacity(isOpen ? 0.55 : 0.0),
                radius: isOpen ? 26 : 0,
                y: isOpen ? 12 : 0)
    }

    private func blackStops(height: CGFloat) -> [Gradient.Stop] {
        guard isOpen, appearance == .liquidGlass else {
            return [.init(color: .black, location: 0), .init(color: .black, location: 1)]
        }
        // Keep the band under the real notch fully black, then ease out over the rest.
        let solid = max(min(blackBandHeight / max(height, 1), 0.9), 0.05)
        return [
            .init(color: .black, location: 0),
            .init(color: .black, location: solid),
            .init(color: .black.opacity(0.78), location: solid + (1 - solid) * 0.28),
            .init(color: .black.opacity(0.42), location: solid + (1 - solid) * 0.62),
            .init(color: .black.opacity(0.18), location: 1)
        ]
    }
}

extension NotchShape: InsettableShape {
    func inset(by amount: CGFloat) -> some InsettableShape {
        InsetNotchShape(base: self, inset: amount)
    }
}

struct InsetNotchShape: InsettableShape {
    var base: NotchShape
    var inset: CGFloat

    func path(in rect: CGRect) -> Path {
        base.path(in: rect.insetBy(dx: inset, dy: inset))
    }

    func inset(by amount: CGFloat) -> InsetNotchShape {
        InsetNotchShape(base: base, inset: inset + amount)
    }
}
