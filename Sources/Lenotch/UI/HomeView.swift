import SwiftUI

/// The first tab when both music and calendar are off: the Lenotch logo and name
/// with the time, and the current weather with a small animated scene.
struct HomeView: View {
    let model: NotchViewModel

    private var weather: WeatherService { model.weather }
    private var glass: Bool { model.settings.appearance == .glass }

    var body: some View {
        HStack(spacing: 28) {
            HStack(spacing: 14) {
                AppLogo(height: 46, glass: glass, color: glass ? nil : model.accentColor)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Lenotch")
                        .font(.system(size: 20, weight: .bold))
                        .foregroundStyle(.white)
                    TimelineView(.everyMinute) { context in
                        VStack(alignment: .leading, spacing: 1) {
                            Text(context.date, format: .dateTime.hour().minute())
                                .font(.system(size: 15, weight: .semibold).monospacedDigit())
                            Text(context.date, format: .dateTime.weekday(.wide).day().month(.wide))
                                .font(.system(size: 12, weight: .medium))
                        }
                        .foregroundStyle(.white.opacity(0.55))
                    }
                }
            }
            .slideIn(0)

            Spacer(minLength: 0)

            weatherBlock
                .slideIn(1)
        }
        .frame(maxHeight: .infinity)
        // Fetch while visible only (the service itself waits 15 minutes between readings).
        .task(id: "\(model.settings.weatherPlace?.name ?? "")\(model.settings.weatherFahrenheit)") {
            while !Task.isCancelled {
                await weather.refreshIfNeeded()
                try? await Task.sleep(for: .seconds(60))
            }
        }
    }

    @ViewBuilder
    private var weatherBlock: some View {
        if let reading = weather.reading {
            HStack(spacing: 12) {
                WeatherScene(kind: reading.kind, isDay: reading.isDay)
                    .frame(width: 88, height: 88)
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(Int(reading.temperature.rounded()))°")
                        .font(.system(size: 34, weight: .semibold).monospacedDigit())
                        .foregroundStyle(.white)
                        .contentTransition(.numericText())
                    Text(reading.kind.title)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.8))
                    Text("H \(Int(reading.high.rounded()))°  L \(Int(reading.low.rounded()))°")
                        .font(.system(size: 11, weight: .medium).monospacedDigit())
                        .foregroundStyle(.white.opacity(0.5))
                    if let name = weather.placeName {
                        Label(name, systemImage: "location.fill")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(.white.opacity(0.45))
                            .lineLimit(1)
                    }
                }
            }
        } else {
            ProgressView().controlSize(.small)
                .frame(width: 88, height: 88)
        }
    }
}
