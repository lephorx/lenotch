import SwiftUI

enum NotchGlassStyle {
    /// Fully see-through; used for the notch body.
    case clear
    /// Blurred and filled, with a softer rim; used for cards, tabs and the slider.
    case frosted
}

extension View {
    /// Liquid Glass behind the view when `enabled` (material blur before macOS 26).
    /// Everything glass in the notch goes through here so it stays consistent.
    @ViewBuilder
    func notchGlass<S: Shape>(_ enabled: Bool, in shape: S, style: NotchGlassStyle = .clear,
                              tint: Color? = nil) -> some View {
        if !enabled {
            self
        } else if #available(macOS 26, *) {
            glassEffect((style == .clear ? Glass.clear : Glass.regular).tint(tint), in: shape)
        } else {
            background(style == .clear ? .ultraThinMaterial : .regularMaterial, in: shape)
                .overlay(shape.fill(tint ?? .clear))
        }
    }
}

/// An icon made of the notch's clear glass, in the outline of `shape`.
/// `highlight` mixes in white (none at rest, so it matches the notch exactly).
struct GlassIcon<S: Shape>: View {
    let shape: S
    let size: CGSize
    var highlight: Double = 0

    var body: some View {
        Color.clear
            .frame(width: size.width, height: size.height)
            .notchGlass(true, in: shape, tint: highlight > 0 ? .white.opacity(highlight) : nil)
    }
}

/// Dark frosted glass card with a soft shadow. `isRaised` (hover or drop target)
/// lightens it and deepens the shadow. The card never moves or scales, since
/// transformed glass renders out of step with its outline.
struct GlassCard<Content: View>: View {
    var cornerRadius: CGFloat = 26
    var isRaised = false
    @ViewBuilder let content: Content

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        content
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background {
                ZStack {
                    OuterShadow(shape: shape, isRaised: isRaised)
                    Color.clear.notchGlass(true, in: shape, style: .frosted,
                                           tint: .black.opacity(isRaised ? 0.15 : 0.3))
                }
            }
            .animation(.easeOut(duration: 0.2), value: isRaised)
    }
}

/// Shadow drawn only outside the shape, so it doesn't darken the glass on top.
private struct OuterShadow<S: Shape>: View {
    let shape: S
    let isRaised: Bool

    var body: some View {
        ZStack {
            shape.fill(.black)
                .shadow(color: .black.opacity(isRaised ? 0.45 : 0.3),
                        radius: isRaised ? 12 : 8, y: isRaised ? 6 : 3)
            shape.fill(.black).blendMode(.destinationOut)
        }
        .compositingGroup()
    }
}
