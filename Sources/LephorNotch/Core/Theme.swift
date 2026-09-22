import SwiftUI

enum Theme {
    /// The spring every size/opacity change in the notch rides on. One curve everywhere is
    /// what makes the thing feel like a single physical object rather than a stack of views.
    static let open = Animation.spring(response: 0.42, dampingFraction: 0.78, blendDuration: 0.1)
    static let close = Animation.spring(response: 0.34, dampingFraction: 0.86)
    static let content = Animation.spring(response: 0.30, dampingFraction: 0.85)
    static let hud = Animation.spring(response: 0.28, dampingFraction: 0.80)

    /// Used whenever album art yields no usable colour.
    static let artworkFallback: [Color] = [
        Color(red: 0.18, green: 0.20, blue: 0.28),
        Color(red: 0.09, green: 0.10, blue: 0.14)
    ]

    static let accent = Color(red: 0.36, green: 0.78, blue: 0.98)
    static let secondaryText = Color.white.opacity(0.55)

    static let cornerRadius: CGFloat = 22
    static let closedCornerRadius: CGFloat = 12
}

extension View {
    /// Applies Liquid Glass where the OS provides it, with a material fallback.
    @ViewBuilder
    func notchGlass<S: Shape>(in shape: S, enabled: Bool) -> some View {
        if enabled {
            if #available(macOS 26.0, *) {
                self.glassEffect(.regular, in: shape)
            } else {
                self.background(.ultraThinMaterial, in: shape)
            }
        } else {
            self
        }
    }
}
