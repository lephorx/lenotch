import AppKit
import ImageIO

/// Keeps images at the size they're shown at, instead of holding full-resolution
/// bitmaps (a 1200 px cover is ~5.8 MB decoded; the notch shows it at 120 pt).
enum ImageDownsampling {
    /// Decodes encoded image data directly at most `maxPixelSize` on its longer side.
    static func image(from data: Data, maxPixelSize: Int = 320) -> NSImage? {
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize,
        ]
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }
        return NSImage(cgImage: image, size: .zero)
    }

    /// Renders an app or file icon into one small bitmap (points, drawn at 2×),
    /// so the multi-resolution icon it came from can be released.
    static func icon(forFile path: String, points: CGFloat) -> NSImage {
        let icon = NSWorkspace.shared.icon(forFile: path)
        let pixels = Int(points * 2)
        guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels,
                                         bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                         colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0) else { return icon }
        rep.size = NSSize(width: points, height: points)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        icon.draw(in: NSRect(x: 0, y: 0, width: points, height: points))
        NSGraphicsContext.restoreGraphicsState()
        let image = NSImage(size: rep.size)
        image.addRepresentation(rep)
        return image
    }
}
