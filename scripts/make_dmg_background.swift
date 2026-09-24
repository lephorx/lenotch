import AppKit

// Run from the repository root: swift scripts/make_dmg_background.swift
// Finder displays this 2x PNG in a 760 × 430 point installer window.
let width = 760
let height = 430
let scale = 2
let root = URL(fileURLWithPath: CommandLine.arguments[0]).deletingLastPathComponent().deletingLastPathComponent()
let output = root.appendingPathComponent("Resources/dmg-background.png")

guard let bitmap = NSBitmapImageRep(
    bitmapDataPlanes: nil, pixelsWide: width * scale, pixelsHigh: height * scale,
    bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
    colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
), let graphics = NSGraphicsContext(bitmapImageRep: bitmap) else {
    fatalError("Could not create DMG background bitmap")
}
// Finder sizes background pictures using their point size. Keep 2x pixels for
// sharp text, but mark the image as 760 × 430 points so icon coordinates align.
bitmap.size = NSSize(width: width, height: height)

func color(_ red: CGFloat, _ green: CGFloat, _ blue: CGFloat, _ alpha: CGFloat = 1) -> NSColor {
    NSColor(srgbRed: red / 255, green: green / 255, blue: blue / 255, alpha: alpha)
}

func rect(_ x: CGFloat, _ top: CGFloat, _ width: CGFloat, _ height: CGFloat) -> NSRect {
    NSRect(x: x, y: CGFloat(430) - top - height, width: width, height: height)
}

func rounded(_ bounds: NSRect, radius: CGFloat, fill: NSColor, stroke: NSColor? = nil) {
    let path = NSBezierPath(roundedRect: bounds, xRadius: radius, yRadius: radius)
    fill.setFill()
    path.fill()
    if let stroke {
        stroke.setStroke()
        path.lineWidth = 1
        path.stroke()
    }
}

func text(_ string: String, x: CGFloat, top: CGFloat, width: CGFloat, height: CGFloat,
          size: CGFloat, weight: NSFont.Weight, foreground: NSColor, tracking: CGFloat = 0) {
    let paragraph = NSMutableParagraphStyle()
    paragraph.lineBreakMode = .byClipping
    let attributes: [NSAttributedString.Key: Any] = [
        .font: NSFont.systemFont(ofSize: size, weight: weight),
        .foregroundColor: foreground,
        .kern: tracking,
        .paragraphStyle: paragraph
    ]
    NSAttributedString(string: string, attributes: attributes)
        .draw(in: rect(x, top, width, height))
}

func glow(at center: CGPoint, radius: CGFloat, tint: NSColor) {
    let colors = [tint.cgColor, tint.withAlphaComponent(0).cgColor] as CFArray
    let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: [0, 1])!
    graphics.cgContext.drawRadialGradient(gradient, startCenter: center, startRadius: 0,
                                          endCenter: center, endRadius: radius, options: [])
}

NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = graphics
graphics.cgContext.scaleBy(x: CGFloat(scale), y: CGFloat(scale))

color(11, 15, 25).setFill()
NSRect(x: 0, y: 0, width: width, height: height).fill()
glow(at: CGPoint(x: 116, y: 278), radius: 340, tint: color(33, 126, 194, 0.28))
glow(at: CGPoint(x: 660, y: 121), radius: 320, tint: color(117, 72, 184, 0.19))

// Delicate grid gives the empty space texture without competing with Finder icons.
let context = graphics.cgContext
context.setStrokeColor(color(255, 255, 255, 0.026).cgColor)
context.setLineWidth(0.5)
for x in stride(from: CGFloat(0), through: CGFloat(width), by: 38) {
    context.move(to: CGPoint(x: x, y: 0))
    context.addLine(to: CGPoint(x: x, y: CGFloat(height)))
}
for y in stride(from: CGFloat(0), through: CGFloat(height), by: 38) {
    context.move(to: CGPoint(x: 0, y: y))
    context.addLine(to: CGPoint(x: CGFloat(width), y: y))
}
context.strokePath()

rounded(rect(24, 22, 712, 386), radius: 25,
        fill: color(15, 19, 30, 0.63), stroke: color(255, 255, 255, 0.10))

if let logo = NSImage(contentsOf: root.appendingPathComponent("Resources/logo-white.png")) {
    logo.draw(in: rect(52, 45, 30, 35), from: .zero, operation: .sourceOver, fraction: 0.95)
}
text("Lenotch", x: 93, top: 42, width: 295, height: 48,
     size: 31, weight: .semibold, foreground: color(247, 250, 255), tracking: -0.8)
text("A little more space at the top of your Mac.", x: 52, top: 91, width: 480, height: 25,
     size: 14, weight: .regular, foreground: color(177, 188, 207))
rounded(rect(615, 53, 92, 26), radius: 13,
        fill: color(75, 143, 202, 0.14), stroke: color(100, 180, 230, 0.30))
text("FOR macOS", x: 629, top: 57, width: 76, height: 20,
     size: 10, weight: .semibold, foreground: color(171, 218, 250), tracking: 0.5)

color(255, 255, 255, 0.10).setFill()
rect(52, 133, 656, 1).fill()

// Finder overlays the app and Applications icons at the centres of these pads.
rounded(rect(105, 158, 170, 157), radius: 28,
        fill: color(47, 68, 96, 0.18), stroke: color(132, 186, 231, 0.15))
rounded(rect(485, 158, 170, 157), radius: 28,
        fill: color(47, 68, 96, 0.18), stroke: color(132, 186, 231, 0.15))
// Finder chooses black or white icon captions from the user's appearance.
// Mid-tone glass behind them keeps both readable.
rounded(rect(121, 284, 138, 28), radius: 14,
        fill: color(196, 210, 229, 0.44), stroke: color(255, 255, 255, 0.18))
rounded(rect(501, 284, 138, 28), radius: 14,
        fill: color(196, 210, 229, 0.44), stroke: color(255, 255, 255, 0.18))

rounded(rect(340, 216, 80, 39), radius: 19,
        fill: color(63, 139, 201, 0.13), stroke: color(104, 191, 249, 0.20))
let arrow = NSBezierPath()
arrow.move(to: CGPoint(x: 358, y: 194))
arrow.line(to: CGPoint(x: 400, y: 194))
arrow.move(to: CGPoint(x: 390, y: 203))
arrow.line(to: CGPoint(x: 400, y: 194))
arrow.line(to: CGPoint(x: 390, y: 185))
arrow.lineWidth = 3
arrow.lineCapStyle = .round
arrow.lineJoinStyle = .round
color(137, 215, 255).setStroke()
arrow.stroke()

rect(52, 345, 656, 1).fill()
text("DRAG LENOTCH TO APPLICATIONS TO INSTALL", x: 205, top: 365,
     width: 425, height: 24, size: 11, weight: .semibold,
     foreground: color(193, 206, 224), tracking: 1.05)

NSGraphicsContext.restoreGraphicsState()
guard let png = bitmap.representation(using: .png, properties: [:]) else {
    fatalError("Could not encode DMG background")
}
try png.write(to: output)
print("Wrote \(output.path)")
