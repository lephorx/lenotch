import SwiftUI

/// Collapsed notch while an app uses the microphone or camera: the app's icon left of
/// the notch, orange (mic) and green (camera) dots right of it, like macOS.
struct PrivacyView: View {
    let model: NotchViewModel

    var body: some View {
        GeometryReader { proxy in
            let side = proxy.size.height - 10
            HStack(spacing: 0) {
                icon
                    .frame(width: side, height: side)
                Spacer(minLength: model.geometry.notchSize.width)
                // Overlap a little so both dots fit beside the notch.
                HStack(spacing: -3) {
                    if model.privacy.isCameraOn, !model.isMirrorVisible {
                        dot(.green, symbol: "video.fill")
                    }
                    if model.privacy.isMicOn {
                        dot(.orange, symbol: "mic.fill")
                    }
                }
                .frame(width: side)
            }
            .padding(.horizontal, 10)
            .frame(maxHeight: .infinity)
        }
    }

    @ViewBuilder
    private var icon: some View {
        if let image = model.privacy.micApps.lazy.compactMap(Self.appIcon).first {
            Image(nsImage: image).resizable().interpolation(.high)
        } else {
            Image(systemName: model.privacy.isMicOn ? "mic.fill" : "video.fill")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(model.privacy.isMicOn ? .orange : .green)
        }
    }

    private func dot(_ color: Color, symbol: String) -> some View {
        Image(systemName: symbol)
            .font(.system(size: 8, weight: .bold))
            .foregroundStyle(.black)
            .frame(width: 16, height: 16)
            .background(Circle().fill(color).stroke(.black, lineWidth: 1.5))
            .shadow(color: color.opacity(0.7), radius: 5)
            .symbolEffect(.pulse, options: .repeating)
    }

    /// The app's icon; helpers (e.g. `com.google.Chrome.helper`) fall back to their parent app.
    private static func appIcon(for bundleID: String) -> NSImage? {
        var parts = bundleID.split(separator: ".")
        while parts.count >= 2 {
            if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: parts.joined(separator: ".")) {
                return NSWorkspace.shared.icon(forFile: url.path)
            }
            parts.removeLast()
        }
        return nil
    }
}
