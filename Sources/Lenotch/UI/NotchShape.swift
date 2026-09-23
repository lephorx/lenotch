import SwiftUI

/// Notch outline: small outward "ears" at the top that melt into the menu bar,
/// rounded corners at the bottom. The ears extend `topRadius` beyond the body on each side.
struct NotchShape: Shape {
    var topRadius: CGFloat
    var bottomRadius: CGFloat

    static let closedTopRadius: CGFloat = 6
    static let closedBottomRadius: CGFloat = 12
    static let openTopRadius: CGFloat = 22
    static let openBottomRadius: CGFloat = 44
    static let mirrorTopRadius: CGFloat = 12
    static let mirrorBottomRadius: CGFloat = 34

    var animatableData: AnimatablePair<CGFloat, CGFloat> {
        get { AnimatablePair(topRadius, bottomRadius) }
        set { topRadius = newValue.first; bottomRadius = newValue.second }
    }

    func path(in rect: CGRect) -> Path {
        let top = topRadius
        let bottom = min(bottomRadius, rect.height - top)
        // Cubic control-point factor for a circular quarter arc.
        let k: CGFloat = 0.5523
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.minY))
        // Left ear: curves from the top edge of the screen down into the side.
        path.addCurve(to: CGPoint(x: rect.minX + top, y: rect.minY + top),
                      control1: CGPoint(x: rect.minX + top * k, y: rect.minY),
                      control2: CGPoint(x: rect.minX + top, y: rect.minY + top * (1 - k)))
        path.addLine(to: CGPoint(x: rect.minX + top, y: rect.maxY - bottom))
        path.addCurve(to: CGPoint(x: rect.minX + top + bottom, y: rect.maxY),
                      control1: CGPoint(x: rect.minX + top, y: rect.maxY - bottom * (1 - k)),
                      control2: CGPoint(x: rect.minX + top + bottom * (1 - k), y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.maxX - top - bottom, y: rect.maxY))
        path.addCurve(to: CGPoint(x: rect.maxX - top, y: rect.maxY - bottom),
                      control1: CGPoint(x: rect.maxX - top - bottom * (1 - k), y: rect.maxY),
                      control2: CGPoint(x: rect.maxX - top, y: rect.maxY - bottom * (1 - k)))
        path.addLine(to: CGPoint(x: rect.maxX - top, y: rect.minY + top))
        // Right ear.
        path.addCurve(to: CGPoint(x: rect.maxX, y: rect.minY),
                      control1: CGPoint(x: rect.maxX - top, y: rect.minY + top * (1 - k)),
                      control2: CGPoint(x: rect.maxX - top * k, y: rect.minY))
        path.closeSubpath()
        return path
    }
}
