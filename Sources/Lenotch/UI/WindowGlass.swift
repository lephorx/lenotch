import AppKit
import SwiftUI

extension View {
    /// Styles a Lenotch window (Settings, the setup) after the chosen notch style:
    /// with Liquid Glass the window turns see-through with glass behind the content,
    /// tinted by the glass opacity; with Black it's an ordinary window.
    func lenotchWindowStyle(_ settings: AppSettings) -> some View {
        modifier(WindowGlassStyle(settings: settings))
    }
}

private struct WindowGlassStyle: ViewModifier {
    let settings: AppSettings

    private var isGlass: Bool { settings.appearance == .glass }

    func body(content: Content) -> some View {
        content
            // Forms and lists draw their own opaque backgrounds; hide them so the glass shows.
            .scrollContentBackground(isGlass ? .hidden : .automatic)
            .background {
                if isGlass {
                    GlassBackdrop(opacity: settings.glassGradient.bottom.alpha)
                        .ignoresSafeArea()
                        .transition(.opacity)
                }
            }
            .background(WindowTransparency(isTransparent: isGlass))
            // Light text reads best on glass over any wallpaper.
            .environment(\.colorScheme, isGlass ? .dark : .light)
            .preferredColorScheme(isGlass ? .dark : nil)
            .animation(.easeInOut(duration: 0.35), value: isGlass)
    }
}

/// Window-sized Liquid Glass, darkened by the user's glass opacity (with a floor so
/// text stays readable over bright wallpapers).
private struct GlassBackdrop: View {
    let opacity: Double

    var body: some View {
        let tint = Color.black.opacity(0.18 + opacity * 0.5)
        if #available(macOS 26, *) {
            Color.clear.glassEffect(.clear.tint(tint), in: Rectangle())
        } else {
            Rectangle().fill(.ultraThinMaterial).overlay(tint)
        }
    }
}

/// Makes the hosting window see-through (or opaque again) so the glass can show
/// what's behind it.
private struct WindowTransparency: NSViewRepresentable {
    let isTransparent: Bool

    func makeNSView(context: Context) -> NSView { WindowProbe(isTransparent: isTransparent) }

    func updateNSView(_ nsView: NSView, context: Context) {
        (nsView as? WindowProbe)?.isTransparent = isTransparent
    }

    final class WindowProbe: NSView {
        var isTransparent: Bool { didSet { apply() } }

        init(isTransparent: Bool) {
            self.isTransparent = isTransparent
            super.init(frame: .zero)
        }

        required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            apply()
        }

        private func apply() {
            guard let window else { return }
            window.isOpaque = !isTransparent
            window.backgroundColor = isTransparent ? .clear : .windowBackgroundColor
            window.titlebarAppearsTransparent = true
            window.invalidateShadow()
        }
    }
}
