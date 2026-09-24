import SwiftUI

/// A persistent version of the intro card, shown above setup while its style changes.
struct AppearanceLivePreview: View {
    let notchHeight: CGFloat

    var body: some View {
        VStack(spacing: 0) {
            Color.clear.frame(height: notchHeight)
            HStack(spacing: 14) {
                if let image = AppLogo.image {
                    Image(nsImage: image).resizable()
                        .frame(width: 54 * LogoShape.aspectRatio, height: 54)
                } else {
                    LogoShape().fill(.white)
                        .frame(width: 54 * LogoShape.aspectRatio, height: 54)
                }
                Text("Lenotch")
                    .font(.system(size: 30, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}
