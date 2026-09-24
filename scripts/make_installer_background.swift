import AppKit

// Run from the repository root to regenerate the Finder installer artwork.
let width = 600
// Slightly taller than Finder's visible area so no unpainted strip appears.
let height = 340
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

let background = NSGradient(starting: NSColor(srgbRed: 19 / 255, green: 29 / 255, blue: 48 / 255, alpha: 1),
                            ending: NSColor(srgbRed: 10 / 255, green: 16 / 255, blue: 29 / 255, alpha: 1))!
background.draw(in: NSRect(x: 0, y: 0, width: width, height: height), angle: 90)

// Finder can render dark icon captions even over a dark picture. These small
// neutral plates keep either caption color legible.
for center in [155.0, 445.0] {
    let plate = NSBezierPath(roundedRect: NSRect(x: center - 70, y: 85, width: 140, height: 25),
                             xRadius: 12.5, yRadius: 12.5)
    NSColor(srgbRed: 148 / 255, green: 165 / 255, blue: 190 / 255, alpha: 0.62).setFill()
    plate.fill()
}

// One continuous curve points from Lenotch to Applications.
let arrow = NSBezierPath()
arrow.move(to: NSPoint(x: 245, y: 185))
arrow.curve(to: NSPoint(x: 295, y: 194),
            controlPoint1: NSPoint(x: 262, y: 218),
            controlPoint2: NSPoint(x: 277, y: 222))
arrow.curve(to: NSPoint(x: 350, y: 185),
            controlPoint1: NSPoint(x: 314, y: 166),
            controlPoint2: NSPoint(x: 332, y: 185))
arrow.lineWidth = 4.5
arrow.lineCapStyle = .round
arrow.lineJoinStyle = .round
NSColor(srgbRed: 110 / 255, green: 192 / 255, blue: 244 / 255, alpha: 0.9).setStroke()
arrow.stroke()

let head = NSBezierPath()
head.move(to: NSPoint(x: 332, y: 201))
head.line(to: NSPoint(x: 350, y: 185))
head.line(to: NSPoint(x: 332, y: 169))
head.lineWidth = 4.5
head.lineCapStyle = .round
head.lineJoinStyle = .round
head.stroke()

NSGraphicsContext.restoreGraphicsState()
guard let png = bitmap.representation(using: .png, properties: [:]) else {
    fatalError("Could not encode installer artwork")
}
try png.write(to: output)
print("Wrote \(output.path)")
