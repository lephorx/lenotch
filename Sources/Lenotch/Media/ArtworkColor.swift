import AppKit

enum ArtworkColor {
    /// The artwork's most vivid colour, brightened so it reads on black.
    /// Averages the pixels of a tiny thumbnail, weighting each by its saturation.
    static func accent(of image: NSImage) -> NSColor? {
        let side = 24
        guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil),
              let context = CGContext(data: nil, width: side, height: side, bitsPerComponent: 8,
                                      bytesPerRow: side * 4, space: CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: side, height: side))
        guard let data = context.data else { return nil }

        let pixels = data.bindMemory(to: UInt8.self, capacity: side * side * 4)
        var red = 0.0, green = 0.0, blue = 0.0, totalWeight = 0.0
        for index in 0..<(side * side) {
            let r = Double(pixels[index * 4]) / 255
            let g = Double(pixels[index * 4 + 1]) / 255
            let b = Double(pixels[index * 4 + 2]) / 255
            let maxValue = max(r, g, b), minValue = min(r, g, b)
            let saturation = maxValue > 0 ? (maxValue - minValue) / maxValue : 0
            // Favour saturated, not-too-dark pixels; keep a small floor so grey art still averages.
            let weight = 0.05 + saturation * saturation * maxValue
            red += r * weight
            green += g * weight
            blue += b * weight
            totalWeight += weight
        }
        guard totalWeight > 0 else { return nil }

        let average = NSColor(srgbRed: red / totalWeight, green: green / totalWeight,
                              blue: blue / totalWeight, alpha: 1)
        var hue: CGFloat = 0, saturation: CGFloat = 0, brightness: CGFloat = 0
        average.getHue(&hue, saturation: &saturation, brightness: &brightness, alpha: nil)
        return NSColor(hue: hue, saturation: min(saturation * 1.2, 0.85),
                       brightness: max(brightness, 0.85), alpha: 1)
    }
}
