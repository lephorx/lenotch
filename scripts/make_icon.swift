// Renders the Lenotch app icon (1024×1024) from the white logo.
// Run: ./scripts/make_icon.sh
import AppKit
import SwiftUI

/// macOS icon grid: an 824-pt rounded square centred on a 1024 canvas.
struct IconView: View {
    let logo: NSImage

    var body: some View {
        let tile = RoundedRectangle(cornerRadius: 185, style: .continuous)
        ZStack {
            tile.fill(LinearGradient(colors: [Color(red: 0.11, green: 0.13, blue: 0.19),
                                              Color(red: 0.02, green: 0.03, blue: 0.05)],
                                     startPoint: .top, endPoint: .bottom))
            // Soft light behind the logo.
            tile.fill(RadialGradient(colors: [.white.opacity(0.14), .clear],
                                     center: UnitPoint(x: 0.5, y: 0.62), startRadius: 0, endRadius: 430))
            // The notch, flush with the top edge.
            NotchOutline()
                .fill(.black)
                .frame(width: 400, height: 96)
                .frame(maxHeight: .infinity, alignment: .top)
            Image(nsImage: logo)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(height: 400)
                .shadow(color: .white.opacity(0.35), radius: 36)
                .offset(y: 50)
        }
        .frame(width: 824, height: 824)
        .clipShape(tile)
        .shadow(color: .black.opacity(0.35), radius: 18, y: 10)
        .frame(width: 1024, height: 1024)
    }
}

/// Notch with flared top corners and rounded bottom corners.
struct NotchOutline: Shape {
    func path(in rect: CGRect) -> Path {
        let ear: CGFloat = 26, corner: CGFloat = 44, k: CGFloat = 0.5523
        var p = Path()
        p.move(to: CGPoint(x: rect.minX, y: rect.minY))
        p.addCurve(to: CGPoint(x: rect.minX + ear, y: rect.minY + ear),
                   control1: CGPoint(x: rect.minX + ear * k, y: rect.minY),
                   control2: CGPoint(x: rect.minX + ear, y: rect.minY + ear * (1 - k)))
        p.addLine(to: CGPoint(x: rect.minX + ear, y: rect.maxY - corner))
        p.addCurve(to: CGPoint(x: rect.minX + ear + corner, y: rect.maxY),
                   control1: CGPoint(x: rect.minX + ear, y: rect.maxY - corner * (1 - k)),
                   control2: CGPoint(x: rect.minX + ear + corner * (1 - k), y: rect.maxY))
        p.addLine(to: CGPoint(x: rect.maxX - ear - corner, y: rect.maxY))
        p.addCurve(to: CGPoint(x: rect.maxX - ear, y: rect.maxY - corner),
                   control1: CGPoint(x: rect.maxX - ear - corner * (1 - k), y: rect.maxY),
                   control2: CGPoint(x: rect.maxX - ear, y: rect.maxY - corner * (1 - k)))
        p.addLine(to: CGPoint(x: rect.maxX - ear, y: rect.minY + ear))
        p.addCurve(to: CGPoint(x: rect.maxX, y: rect.minY),
                   control1: CGPoint(x: rect.maxX - ear, y: rect.minY + ear * (1 - k)),
                   control2: CGPoint(x: rect.maxX - ear * k, y: rect.minY))
        p.closeSubpath()
        return p
    }
}

@main
struct MakeIcon {
    @MainActor static func main() {
        let args = CommandLine.arguments
        guard args.count == 3, let logo = NSImage(contentsOfFile: args[1]) else {
            print("usage: make_icon <logo.png> <out.png>")
            exit(1)
        }
        let renderer = ImageRenderer(content: IconView(logo: logo))
        renderer.scale = 1
        guard let cgImage = renderer.cgImage,
              let png = NSBitmapImageRep(cgImage: cgImage).representation(using: .png, properties: [:]) else { exit(1) }
        try! png.write(to: URL(fileURLWithPath: args[2]))
    }
}
