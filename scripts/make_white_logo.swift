// Turns the blue logo into a white one that keeps its facets: each pixel's
// brightness is mapped onto light grey (darkest facet) … white (lightest facet).
// Run via ./scripts/make_icon.sh
import AppKit

let args = CommandLine.arguments
guard args.count == 3, let source = NSImage(contentsOfFile: args[1]),
      let image = source.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
    print("usage: make_white_logo <logo.png> <out.png>")
    exit(1)
}

let width = image.width, height = image.height
let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
                        space: CGColorSpace(name: CGColorSpace.sRGB)!,
                        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
let pixels = context.data!.bindMemory(to: UInt8.self, capacity: width * height * 4)

// Luminance range of the logo's facets, and the grey range they map onto.
let (darkest, lightest) = (0.22, 0.76)
let (low, high) = (0.7, 1.0)

for i in 0..<(width * height) {
    let alpha = Double(pixels[i * 4 + 3]) / 255
    guard alpha > 0 else { continue }
    // Un-premultiply to get the real colour.
    let r = Double(pixels[i * 4]) / 255 / alpha
    let g = Double(pixels[i * 4 + 1]) / 255 / alpha
    let b = Double(pixels[i * 4 + 2]) / 255 / alpha
    let luminance = 0.2126 * r + 0.7152 * g + 0.0722 * b
    let t = min(max((luminance - darkest) / (lightest - darkest), 0), 1)
    let value = UInt8(((low + (high - low) * t) * alpha * 255).rounded())
    pixels[i * 4] = value
    pixels[i * 4 + 1] = value
    pixels[i * 4 + 2] = value
}

let png = NSBitmapImageRep(cgImage: context.makeImage()!).representation(using: .png, properties: [:])!
try! png.write(to: URL(fileURLWithPath: args[2]))
