import AppKit
import SwiftUI

/// A colour stored as sRGB components so it can be saved in UserDefaults.
struct RGBAColor: Codable, Equatable {
    var red: Double
    var green: Double
    var blue: Double
    var alpha: Double

    static let black = RGBAColor(red: 0, green: 0, blue: 0, alpha: 1)
    static let clear = RGBAColor(red: 0, green: 0, blue: 0, alpha: 0)

    init(red: Double, green: Double, blue: Double, alpha: Double) {
        self.red = red
        self.green = green
        self.blue = blue
        self.alpha = alpha
    }

    init(_ color: Color) {
        let ns = NSColor(color).usingColorSpace(.sRGB) ?? .black
        self.init(red: ns.redComponent, green: ns.greenComponent, blue: ns.blueComponent, alpha: ns.alphaComponent)
    }

    var color: Color { Color(.sRGB, red: red, green: green, blue: blue, opacity: alpha) }

    func mixed(with other: RGBAColor, _ t: Double) -> RGBAColor {
        RGBAColor(red: red + (other.red - red) * t,
                  green: green + (other.green - green) * t,
                  blue: blue + (other.blue - blue) * t,
                  alpha: alpha + (other.alpha - alpha) * t)
    }
}

/// Colour transition of the open notch, from `top` to `bottom`.
///
/// The strip beside the hardware notch is always `top`. Below it, the fade
/// begins `start` of the way down and runs for `length` of the remaining height
/// (both 0...1), eased so it has no hard edges.
struct NotchGradient: Codable, Equatable {
    var top: RGBAColor
    var bottom: RGBAColor
    var start: Double
    var length: Double
    /// Add the current song's artwork colour as a localized glow and bottom rim.
    var bottomFollowsMusic = false

    init(top: RGBAColor, bottom: RGBAColor, start: Double, length: Double, bottomFollowsMusic: Bool = false) {
        self.top = top
        self.bottom = bottom
        self.start = start
        self.length = length
        self.bottomFollowsMusic = bottomFollowsMusic
    }

    // Decoded by hand so gradients saved before `bottomFollowsMusic` existed still load.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        top = try container.decode(RGBAColor.self, forKey: .top)
        bottom = try container.decode(RGBAColor.self, forKey: .bottom)
        start = try container.decode(Double.self, forKey: .start)
        length = try container.decode(Double.self, forKey: .length)
        bottomFollowsMusic = try container.decodeIfPresent(Bool.self, forKey: .bottomFollowsMusic) ?? false
    }

    /// Solid black, as before custom gradients existed.
    static let blackDefault = NotchGradient(top: .black, bottom: .black, start: 0, length: 1,
                                            bottomFollowsMusic: true)
    /// Black fading into fully clear glass, across the whole height.
    static let glassDefault = NotchGradient(top: .black, bottom: .clear, start: 0, length: 1,
                                            bottomFollowsMusic: true)
    static let legacyBlackDefault = NotchGradient(top: .black, bottom: .black, start: 0, length: 1)
    static let legacyGlassDefault = NotchGradient(top: .black, bottom: .clear, start: 0, length: 1)
    /// The earlier 50% glass default; saved copies of it are upgraded to the current default.
    static let previousGlassDefault = NotchGradient(top: .black, bottom: RGBAColor(red: 0, green: 0, blue: 0, alpha: 0.5),
                                                    start: 0, length: 1)

    static func `default`(for appearance: Appearance) -> NotchGradient {
        appearance == .glass ? glassDefault : blackDefault
    }

    /// Gradient stops for a view whose top `solidFraction` is the notch strip.
    func stops(solidFraction: Double) -> [Gradient.Stop] {
        let solidEnd = min(max(solidFraction, 0), 1)
        let remaining = 1 - solidEnd
        let fadeStart = solidEnd + remaining * min(max(start, 0), 1)
        let fadeEnd = min(fadeStart + remaining * max(length, 0.02), 1)
        let samples = 8
        let fade = (0...samples).map { index -> Gradient.Stop in
            let t = Double(index) / Double(samples)
            let eased = t * t * (3 - 2 * t)
            return .init(color: top.mixed(with: bottom, eased).color,
                         location: fadeStart + (fadeEnd - fadeStart) * t)
        }
        return [.init(color: top.color, location: 0), .init(color: top.color, location: fadeStart)]
            + fade
            + [.init(color: bottom.color, location: 1)]
    }
}
