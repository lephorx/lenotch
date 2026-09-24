import SwiftUI

/// A small animated picture of the weather: sun rays turning, clouds drifting,
/// rain and snow falling, lightning flashing, stars twinkling at night.
struct WeatherScene: View {
    let kind: WeatherKind
    let isDay: Bool

    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 30)) { context in
            let time = context.date.timeIntervalSinceReferenceDate
            Canvas { canvas, size in
                draw(in: &canvas, size: size, time: time)
            }
        }
    }

    private func draw(in canvas: inout GraphicsContext, size: CGSize, time: Double) {
        let w = size.width, h = size.height
        switch kind {
        case .clear:
            isDay ? sun(&canvas, center: CGPoint(x: w * 0.5, y: h * 0.5), radius: w * 0.2, time: time)
                  : night(&canvas, size: size, time: time, moonAt: CGPoint(x: w * 0.5, y: h * 0.48))
        case .partlyCloudy:
            if isDay {
                sun(&canvas, center: CGPoint(x: w * 0.36, y: h * 0.36), radius: w * 0.16, time: time)
            } else {
                night(&canvas, size: size, time: time, moonAt: CGPoint(x: w * 0.36, y: h * 0.34))
            }
            cloud(&canvas, center: CGPoint(x: w * 0.58 + drift(time, 0.35, w * 0.05), y: h * 0.6), scale: w * 0.3, opacity: 0.95)
        case .cloudy:
            cloud(&canvas, center: CGPoint(x: w * 0.38 + drift(time, 0.25, w * 0.06), y: h * 0.42), scale: w * 0.26, opacity: 0.6)
            cloud(&canvas, center: CGPoint(x: w * 0.58 + drift(time + 2, 0.3, w * 0.05), y: h * 0.6), scale: w * 0.32, opacity: 0.95)
        case .fog:
            for band in 0..<4 {
                let y = h * (0.3 + Double(band) * 0.14)
                let x = drift(time + Double(band), 0.4, w * 0.08)
                let rect = CGRect(x: w * 0.12 + x, y: y, width: w * 0.76, height: h * 0.06)
                canvas.fill(Capsule().path(in: rect), with: .color(.white.opacity(0.35 + Double(band % 2) * 0.2)))
            }
        case .drizzle, .rain, .thunderstorm:
            let heavy = kind != .drizzle
            let cloudColor = kind == .thunderstorm ? 0.7 : 0.9
            rain(&canvas, size: size, time: time, count: heavy ? 14 : 7, speed: heavy ? 1.6 : 1.0)
            cloud(&canvas, center: CGPoint(x: w * 0.5 + drift(time, 0.3, w * 0.03), y: h * 0.36), scale: w * 0.34,
                  opacity: cloudColor)
            if kind == .thunderstorm { lightning(&canvas, size: size, time: time) }
        case .snow:
            snow(&canvas, size: size, time: time)
            cloud(&canvas, center: CGPoint(x: w * 0.5 + drift(time, 0.3, w * 0.03), y: h * 0.36), scale: w * 0.34, opacity: 0.95)
        }
    }

    /// Gentle side-to-side movement.
    private func drift(_ time: Double, _ speed: Double, _ amount: Double) -> Double {
        sin(time * speed) * amount
    }

    private func sun(_ canvas: inout GraphicsContext, center: CGPoint, radius: Double, time: Double) {
        let glow = 1 + 0.08 * sin(time * 2)
        canvas.fill(Circle().path(in: CGRect(x: center.x - radius * 1.9 * glow, y: center.y - radius * 1.9 * glow,
                                             width: radius * 3.8 * glow, height: radius * 3.8 * glow)),
                    with: .radialGradient(Gradient(colors: [.yellow.opacity(0.35), .clear]), center: center,
                                          startRadius: 0, endRadius: radius * 1.9 * glow))
        for ray in 0..<10 {
            let angle = Double(ray) / 10 * .pi * 2 + time * 0.4
            var path = Path()
            path.move(to: CGPoint(x: center.x + cos(angle) * radius * 1.35, y: center.y + sin(angle) * radius * 1.35))
            path.addLine(to: CGPoint(x: center.x + cos(angle) * radius * 1.75, y: center.y + sin(angle) * radius * 1.75))
            canvas.stroke(path, with: .color(.yellow.opacity(0.9)), style: StrokeStyle(lineWidth: radius * 0.16, lineCap: .round))
        }
        canvas.fill(Circle().path(in: CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2)),
                    with: .linearGradient(Gradient(colors: [Color(red: 1, green: 0.9, blue: 0.35), .orange]),
                                          startPoint: CGPoint(x: center.x, y: center.y - radius),
                                          endPoint: CGPoint(x: center.x, y: center.y + radius)))
    }

    private func night(_ canvas: inout GraphicsContext, size: CGSize, time: Double, moonAt center: CGPoint) {
        let stars: [(Double, Double, Double)] = [(0.18, 0.2, 0), (0.8, 0.18, 1.3), (0.72, 0.72, 2.1), (0.2, 0.7, 3.4),
                                                 (0.88, 0.45, 4.2), (0.1, 0.45, 5.1)]
        for (x, y, phase) in stars {
            let twinkle = 0.3 + 0.7 * abs(sin(time * 1.5 + phase))
            let r = size.width * 0.018
            canvas.fill(Circle().path(in: CGRect(x: size.width * x - r, y: size.height * y - r, width: r * 2, height: r * 2)),
                        with: .color(.white.opacity(twinkle)))
        }
        let radius = size.width * 0.2
        var moon = Path(ellipseIn: CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2))
        moon = moon.subtracting(Path(ellipseIn: CGRect(x: center.x - radius * 0.45, y: center.y - radius * 1.25,
                                                       width: radius * 2, height: radius * 2)))
        canvas.fill(moon, with: .color(Color(red: 0.95, green: 0.93, blue: 0.8)))
    }

    private func cloud(_ canvas: inout GraphicsContext, center: CGPoint, scale: Double, opacity: Double) {
        let puffs: [(Double, Double, Double)] = [(-0.55, 0.15, 0.42), (-0.1, -0.2, 0.58), (0.45, 0.05, 0.48), (0, 0.25, 0.45)]
        var path = Path()
        for (x, y, r) in puffs {
            path.addEllipse(in: CGRect(x: center.x + x * scale - r * scale, y: center.y + y * scale - r * scale,
                                       width: r * scale * 2, height: r * scale * 2))
        }
        canvas.fill(path, with: .color(.white.opacity(opacity)))
    }

    private func rain(_ canvas: inout GraphicsContext, size: CGSize, time: Double, count: Int, speed: Double) {
        for drop in 0..<count {
            let x = size.width * (0.25 + 0.5 * Double(drop) / Double(max(count - 1, 1)))
            let progress = (time * speed + Double(drop) * 0.37).truncatingRemainder(dividingBy: 1)
            let y = size.height * (0.45 + progress * 0.5)
            var path = Path()
            path.move(to: CGPoint(x: x, y: y))
            path.addLine(to: CGPoint(x: x - size.width * 0.02, y: y + size.height * 0.08))
            canvas.stroke(path, with: .color(Color(red: 0.55, green: 0.75, blue: 1).opacity(1 - progress * 0.6)),
                          style: StrokeStyle(lineWidth: size.width * 0.02, lineCap: .round))
        }
    }

    private func snow(_ canvas: inout GraphicsContext, size: CGSize, time: Double) {
        for flake in 0..<10 {
            let progress = (time * 0.35 + Double(flake) * 0.29).truncatingRemainder(dividingBy: 1)
            let x = size.width * (0.22 + 0.56 * Double(flake) / 9) + sin(time * 1.5 + Double(flake)) * size.width * 0.03
            let y = size.height * (0.45 + progress * 0.5)
            let r = size.width * 0.022
            canvas.fill(Circle().path(in: CGRect(x: x - r, y: y - r, width: r * 2, height: r * 2)),
                        with: .color(.white.opacity(1 - progress * 0.5)))
        }
    }

    private func lightning(_ canvas: inout GraphicsContext, size: CGSize, time: Double) {
        // A short double flash every few seconds.
        let phase = time.truncatingRemainder(dividingBy: 4)
        guard phase < 0.12 || (phase > 0.22 && phase < 0.3) else { return }
        var bolt = Path()
        let w = size.width, h = size.height
        bolt.move(to: CGPoint(x: w * 0.52, y: h * 0.48))
        bolt.addLine(to: CGPoint(x: w * 0.44, y: h * 0.68))
        bolt.addLine(to: CGPoint(x: w * 0.52, y: h * 0.68))
        bolt.addLine(to: CGPoint(x: w * 0.46, y: h * 0.88))
        bolt.addLine(to: CGPoint(x: w * 0.6, y: h * 0.62))
        bolt.addLine(to: CGPoint(x: w * 0.52, y: h * 0.62))
        bolt.addLine(to: CGPoint(x: w * 0.58, y: h * 0.48))
        bolt.closeSubpath()
        canvas.fill(bolt, with: .color(.yellow))
    }
}
