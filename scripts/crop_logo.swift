// Crops a logo PNG to its visible (non-transparent) area and scales it to 256 px high.
// Run via ./scripts/make_icon.sh
import AppKit

let args = CommandLine.arguments
guard args.count == 3, let source = NSImage(contentsOfFile: args[1]),
      let image = source.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
    print("usage: crop_logo <in.png> <out.png>")
    exit(1)
}

let width = image.width, height = image.height
let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
                        space: CGColorSpace(name: CGColorSpace.sRGB)!,
                        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
let pixels = context.data!.bindMemory(to: UInt8.self, capacity: width * height * 4)

// Bounding box of pixels that are more than half opaque (rows start at the top).
var minX = width, minY = height, maxX = 0, maxY = 0
for y in 0..<height {
    for x in 0..<width where pixels[(y * width + x) * 4 + 3] > 128 {
        minX = min(minX, x); maxX = max(maxX, x); minY = min(minY, y); maxY = max(maxY, y)
    }
}
let cropped = context.makeImage()!.cropping(to: CGRect(x: minX, y: minY, width: maxX - minX + 1, height: maxY - minY + 1))!

let outHeight = 256
let outWidth = Int((Double(cropped.width) / Double(cropped.height) * Double(outHeight)).rounded())
let out = CGContext(data: nil, width: outWidth, height: outHeight, bitsPerComponent: 8, bytesPerRow: 0,
                    space: CGColorSpace(name: CGColorSpace.sRGB)!,
                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
out.interpolationQuality = .high
out.draw(cropped, in: CGRect(x: 0, y: 0, width: outWidth, height: outHeight))
let png = NSBitmapImageRep(cgImage: out.makeImage()!).representation(using: .png, properties: [:])!
try! png.write(to: URL(fileURLWithPath: args[2]))
print("cropped to \(cropped.width)×\(cropped.height), wrote \(outWidth)×\(outHeight)")
