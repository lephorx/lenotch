import AppKit

// Run from the repository root to regenerate the Finder installer artwork.
let width = 600
let height = 300
let scale = 2
let output = URL(fileURLWithPath: "Resources/installer-background.png")

guard let bitmap = NSBitmapImageRep(
    bitmapDataPlanes: nil, pixelsWide: width * scale, pixelsHigh: height * scale,
    bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
    colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
), let graphics = NSGraphicsContext(bitmapImageRep: bitmap) else {
    fatalError("Could not make installer artwork")
}
bitmap.size = NSSize(width: width, height: height)

NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = graphics
graphics.cgContext.scaleBy(x: CGFloat(scale), y: CGFloat(scale))

NSColor(srgbRed: 206 / 255, green: 225 / 255, blue: 252 / 255, alpha: 1).setFill()
NSRect(x: 0, y: 0, width: width, height: height).fill()

// A soft S curve leads from the app icon to the Applications shortcut.
let arrow = NSBezierPath()
arrow.move(to: NSPoint(x: 247, y: 145))
arrow.curve(to: NSPoint(x: 296, y: 164),
            controlPoint1: NSPoint(x: 268, y: 185),
            controlPoint2: NSPoint(x: 278, y: 186))
arrow.curve(to: NSPoint(x: 349, y: 149),
            controlPoint1: NSPoint(x: 319, y: 137),
            controlPoint2: NSPoint(x: 327, y: 129))
arrow.lineWidth = 5
arrow.lineCapStyle = .round
arrow.lineJoinStyle = .round
NSColor(srgbRed: 48 / 255, green: 97 / 255, blue: 167 / 255, alpha: 0.85).setStroke()
arrow.stroke()

let head = NSBezierPath()
head.move(to: NSPoint(x: 333, y: 163))
head.line(to: NSPoint(x: 349, y: 149))
head.line(to: NSPoint(x: 331, y: 140))
head.lineWidth = 5
head.lineCapStyle = .round
head.lineJoinStyle = .round
head.stroke()

NSGraphicsContext.restoreGraphicsState()
guard let png = bitmap.representation(using: .png, properties: [:]) else {
    fatalError("Could not encode installer artwork")
}
try png.write(to: output)
print("Wrote \(output.path)")
