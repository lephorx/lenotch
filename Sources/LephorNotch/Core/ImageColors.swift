import AppKit
import SwiftUI

extension NSImage {
    /// Cheap dominant-colour extraction: downsample to a tiny bitmap, bucket the pixels by
    /// hue, and return the two most populated buckets. Good enough to tint a glass panel and
    /// far cheaper than a real k-means pass on every track change.
    func dominantColors(count: Int = 2) -> [Color] {
        let side = 24
        guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil,
                                         pixelsWide: side, pixelsHigh: side,
                                         bitsPerSample: 8, samplesPerPixel: 4,
                                         hasAlpha: true, isPlanar: false,
                                         colorSpaceName: .deviceRGB,
                                         bytesPerRow: side * 4, bitsPerPixel: 32)
        else { return Theme.artworkFallback }

        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        draw(in: NSRect(x: 0, y: 0, width: side, height: side),
             from: .zero, operation: .copy, fraction: 1)
        NSGraphicsContext.restoreGraphicsState()

        var buckets: [Int: (r: Double, g: Double, b: Double, n: Double)] = [:]
        for y in 0..<side {
            for x in 0..<side {
                guard let color = rep.colorAt(x: x, y: y) else { continue }
                var h: CGFloat = 0, s: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
                color.usingColorSpace(.deviceRGB)?.getHue(&h, saturation: &s, brightness: &b, alpha: &a)
                // Skip near-black and near-white pixels; they make every album look grey.
                guard b > 0.12, s > 0.10 else { continue }
                let key = Int(h * 12)
                var entry = buckets[key] ?? (0, 0, 0, 0)
                entry.r += Double(color.redComponent)
                entry.g += Double(color.greenComponent)
                entry.b += Double(color.blueComponent)
                entry.n += 1
                buckets[key] = entry
            }
        }

        let ranked = buckets.values.sorted { $0.n > $1.n }.prefix(count)
        guard !ranked.isEmpty else { return Theme.artworkFallback }

        let colors = ranked.map { entry -> Color in
            Color(red: entry.r / entry.n, green: entry.g / entry.n, blue: entry.b / entry.n)
        }
        return colors.count >= count ? colors : colors + Theme.artworkFallback.suffix(count - colors.count)
    }
}
