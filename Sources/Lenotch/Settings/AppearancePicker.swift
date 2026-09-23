import SwiftUI

/// Side-by-side previews of the notch styles.
struct AppearancePicker: View {
    @Bindable var settings: AppSettings

    var body: some View {
        HStack(spacing: 12) {
            ForEach(Appearance.allCases) { appearance in
                SelectableCard(isSelected: settings.appearance == appearance) {
                    settings.appearance = appearance
                } label: {
                    VStack(alignment: .leading, spacing: 10) {
                        NotchPreview(appearance: appearance, gradient: settings.gradient(for: appearance))
                            .frame(height: 96)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(appearance.title).font(.system(size: 13, weight: .semibold))
                            Text(appearance.subtitle).font(.system(size: 11)).foregroundStyle(.secondary)
                        }
                    }
                    .padding(10)
                }
            }
        }
    }
}

/// Miniature open notch on a colourful wallpaper so the glass is visible.
private struct NotchPreview: View {
    let appearance: Appearance
    let gradient: NotchGradient

    var body: some View {
        let shape = NotchShape(topRadius: 5, bottomRadius: 12)
        ZStack(alignment: .top) {
            LinearGradient(colors: [.orange, .pink, .purple, .blue],
                           startPoint: .topLeading, endPoint: .bottomTrailing)
            HStack(spacing: 8) {
                RoundedRectangle(cornerRadius: 5).fill(.white.opacity(0.85)).frame(width: 30, height: 30)
                VStack(alignment: .leading, spacing: 5) {
                    Capsule().fill(.white).frame(width: 60, height: 5)
                    Capsule().fill(.white.opacity(0.5)).frame(width: 40, height: 5)
                    Capsule().fill(.white.opacity(0.3)).frame(width: 80, height: 3)
                }
            }
            .padding(.top, 24)
            .frame(width: 150, height: 68, alignment: .top)
            .padding(.horizontal, 5)
            .background {
                NotchBackground(appearance: appearance, gradient: gradient, isOpen: true,
                                notchHeight: 12, shape: shape)
            }
            .clipShape(shape)
        }
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .environment(\.colorScheme, .dark)
    }
}
