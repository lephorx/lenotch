import SwiftUI

/// Outline of the Lenotch "L" logo (Resources/logo.png), in unit coordinates.
struct LogoShape: Shape {
    static let aspectRatio: CGFloat = 225.0 / 256.0

    private static let points: [CGPoint] = [
        CGPoint(x: 0, y: 0.2367),
        CGPoint(x: 0.3433, y: 0),
        CGPoint(x: 0.3433, y: 0.7432),
        CGPoint(x: 1, y: 0.7432),
        CGPoint(x: 0.6866, y: 1),
        CGPoint(x: 0.054, y: 1),
        CGPoint(x: 0, y: 0.9557),
    ]

    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.addLines(Self.points.map { CGPoint(x: rect.minX + $0.x * rect.width, y: rect.minY + $0.y * rect.height) })
        path.closeSubpath()
        return path
    }
}

/// The app logo. In glass mode the logo itself is clear Liquid Glass in the
/// logo's outline, like the playback icons; otherwise the image, recoloured
/// to `color` when given.
struct AppLogo: View {
    let height: CGFloat
    let glass: Bool
    /// White mixed into the glass, for the selected state.
    var highlight: Double = 0
    /// Recolours the image logo (black mode), keeping its facet shading.
    var color: Color? = nil

    static let image: NSImage? = {
        let url = Bundle.main.url(forResource: "logo", withExtension: "png")
            ?? URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
                .appendingPathComponent("Resources/logo.png")
        return NSImage(contentsOf: url)
    }()

    var body: some View {
        let size = CGSize(width: height * LogoShape.aspectRatio, height: height)
        Group {
            if glass {
                GlassIcon(shape: LogoShape(), size: size, highlight: highlight)
            } else if let image = Self.image {
                if let color {
                    // Grayscale keeps the facets' light and dark; brightening then
                    // multiplying paints them in the music's colour.
                    Image(nsImage: image).resizable()
                        .saturation(0)
                        .brightness(0.35)
                        .colorMultiply(color)
                } else {
                    Image(nsImage: image).resizable()
                }
            } else {
                Image(systemName: "music.note").resizable().aspectRatio(contentMode: .fit)
            }
        }
        .frame(width: size.width, height: size.height)
    }
}
