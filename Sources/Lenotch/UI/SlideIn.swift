import SwiftUI

/// Which way the tabs moved, so a new tab's items slide in from that side.
private struct PageForwardKey: EnvironmentKey {
    static let defaultValue = true
}

extension EnvironmentValues {
    var pageMovesForward: Bool {
        get { self[PageForwardKey.self] }
        set { self[PageForwardKey.self] = newValue }
    }
}

extension View {
    /// Slides the item in (with a fade) when its tab appears, one after another by `order`.
    func slideIn(_ order: Int) -> some View {
        modifier(SlideIn(order: order))
    }
}

private struct SlideIn: ViewModifier {
    let order: Int

    @Environment(\.pageMovesForward) private var forward
    @State private var shown = false

    private static let travel: CGFloat = 36
    private static let stagger = 0.045

    func body(content: Content) -> some View {
        content
            .offset(x: shown ? 0 : (forward ? Self.travel : -Self.travel))
            .opacity(shown ? 1 : 0)
            .onAppear {
                withAnimation(.spring(response: 0.5, dampingFraction: 0.78).delay(Double(order) * Self.stagger)) {
                    shown = true
                }
            }
    }
}
