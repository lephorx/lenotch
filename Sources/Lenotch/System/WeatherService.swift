import CoreLocation
import Foundation
import Observation

/// What the sky is doing, grouped for the animated scene.
enum WeatherKind: Equatable {
    case clear, partlyCloudy, cloudy, fog, drizzle, rain, snow, thunderstorm

    /// From a WMO weather code (Open-Meteo's `weather_code`).
    init(code: Int) {
        switch code {
        case 0: self = .clear
        case 1, 2: self = .partlyCloudy
        case 3: self = .cloudy
        case 45, 48: self = .fog
        case 51...57: self = .drizzle
        case 61...67, 80...82: self = .rain
        case 71...77, 85, 86: self = .snow
        case 95...99: self = .thunderstorm
        default: self = .cloudy
        }
    }

    var title: String {
        switch self {
        case .clear: "Clear"
        case .partlyCloudy: "Partly cloudy"
        case .cloudy: "Cloudy"
        case .fog: "Fog"
        case .drizzle: "Drizzle"
        case .rain: "Rain"
        case .snow: "Snow"
        case .thunderstorm: "Thunderstorm"
        }
    }
}

struct WeatherReading: Equatable {
    let temperature: Double
    let high: Double
    let low: Double
    let kind: WeatherKind
    let isDay: Bool
    let unit: String  // "°C" or "°F"
}

/// A saved place for the weather.
struct WeatherPlace: Codable, Hashable {
    var name: String
    var latitude: Double
    var longitude: Double
}

/// Current weather from Open-Meteo (free, no account or key). The place is a city
/// the user typed, or their location when they chose "Use my location" (the only
/// thing that asks for location permission). Without either, an approximate place
/// from the IP address is used, and Zurich if that fails.
@Observable
final class WeatherService: NSObject {
    private(set) var reading: WeatherReading?
    /// The place the current reading is for (shown under the temperature).
    private(set) var placeName: String?
    private(set) var isLocating = false
    private(set) var locationDenied = false

    @ObservationIgnored private let settings: AppSettings
    @ObservationIgnored private var lastFetch: (place: WeatherPlace, fahrenheit: Bool, date: Date)?
    @ObservationIgnored private var locationManager: CLLocationManager?
    /// Approximate place from the IP address, looked up once per launch.
    @ObservationIgnored private var approximatePlace: WeatherPlace?

    static let zurich = WeatherPlace(name: "Zurich", latitude: 47.3769, longitude: 8.5417)

    init(settings: AppSettings) {
        self.settings = settings
    }

    /// Reloads when the place changed or the last reading is older than 15 minutes.
    func refreshIfNeeded() async {
        let place: WeatherPlace
        if let chosen = settings.weatherPlace {
            place = chosen
        } else {
            if approximatePlace == nil { approximatePlace = await Self.placeFromIP() ?? Self.zurich }
            place = approximatePlace ?? Self.zurich
        }
        placeName = place.name
        let fahrenheit = settings.weatherFahrenheit
        if let last = lastFetch, last.place == place, last.fahrenheit == fahrenheit,
           Date().timeIntervalSince(last.date) < 15 * 60 { return }
        lastFetch = (place, fahrenheit, Date())
        reading = try? await Self.fetch(place, fahrenheit: settings.weatherFahrenheit)
    }

    func forceRefresh() async {
        lastFetch = nil
        await refreshIfNeeded()
    }

    /// Rough location from the IP address (city level), without any permission.
    /// Tries two free services; nil when both fail.
    private static func placeFromIP() async -> WeatherPlace? {
        for url in ["https://ipwho.is/", "https://get.geojs.io/v1/ip/geo.json"] {
            guard let (data, _) = try? await URLSession.shared.data(from: URL(string: url)!),
                  let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { continue }
            // geojs sends the coordinates as strings.
            func number(_ key: String) -> Double? {
                (root[key] as? NSNumber)?.doubleValue ?? (root[key] as? String).flatMap(Double.init)
            }
            if let latitude = number("latitude"), let longitude = number("longitude") {
                return WeatherPlace(name: root["city"] as? String ?? "Your area", latitude: latitude, longitude: longitude)
            }
        }
        return nil
    }

    // MARK: - City search

    struct SearchResult: Identifiable, Hashable {
        let id: Int
        let place: WeatherPlace
        let detail: String
    }

    static func search(_ query: String) async -> [SearchResult] {
        let text = query.trimmingCharacters(in: .whitespaces)
        guard text.count >= 2,
              var components = URLComponents(string: "https://geocoding-api.open-meteo.com/v1/search") else { return [] }
        components.queryItems = [.init(name: "name", value: text), .init(name: "count", value: "6"),
                                 .init(name: "language", value: Locale.current.language.languageCode?.identifier ?? "en")]
        guard let url = components.url,
              let (data, _) = try? await URLSession.shared.data(from: url),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let results = root["results"] as? [[String: Any]] else { return [] }
        return results.compactMap { item in
            guard let id = item["id"] as? Int, let name = item["name"] as? String,
                  let latitude = item["latitude"] as? Double, let longitude = item["longitude"] as? Double else { return nil }
            let detail = [item["admin1"] as? String, item["country"] as? String].compactMap { $0 }.joined(separator: ", ")
            return SearchResult(id: id, place: WeatherPlace(name: name, latitude: latitude, longitude: longitude),
                                detail: detail)
        }
    }

    // MARK: - Current location (asks for permission)

    func useCurrentLocation() {
        let manager = CLLocationManager()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyKilometer
        locationManager = manager
        isLocating = true
        locationDenied = false
        switch manager.authorizationStatus {
        case .notDetermined: manager.requestWhenInUseAuthorization()
        case .denied, .restricted: finishLocating(denied: true)
        default: manager.requestLocation()
        }
    }

    private func finishLocating(denied: Bool) {
        isLocating = false
        locationDenied = denied
        locationManager = nil
    }

    // MARK: - Fetch

    private static func fetch(_ place: WeatherPlace, fahrenheit: Bool) async throws -> WeatherReading? {
        var components = URLComponents(string: "https://api.open-meteo.com/v1/forecast")!
        components.queryItems = [
            .init(name: "latitude", value: String(place.latitude)),
            .init(name: "longitude", value: String(place.longitude)),
            .init(name: "current", value: "temperature_2m,weather_code,is_day"),
            .init(name: "daily", value: "temperature_2m_max,temperature_2m_min"),
            .init(name: "forecast_days", value: "1"),
            .init(name: "timezone", value: "auto"),
            .init(name: "temperature_unit", value: fahrenheit ? "fahrenheit" : "celsius"),
        ]
        let (data, _) = try await URLSession.shared.data(from: components.url!)
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let current = root["current"] as? [String: Any],
              let daily = root["daily"] as? [String: Any],
              let temperature = (current["temperature_2m"] as? NSNumber)?.doubleValue,
              let code = (current["weather_code"] as? NSNumber)?.intValue else { return nil }
        let high = ((daily["temperature_2m_max"] as? [NSNumber])?.first?.doubleValue) ?? temperature
        let low = ((daily["temperature_2m_min"] as? [NSNumber])?.first?.doubleValue) ?? temperature
        return WeatherReading(temperature: temperature, high: high, low: low, kind: WeatherKind(code: code),
                              isDay: (current["is_day"] as? NSNumber)?.intValue != 0,
                              unit: fahrenheit ? "°F" : "°C")
    }
}

extension WeatherService: CLLocationManagerDelegate {
    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        guard isLocating else { return }
        switch manager.authorizationStatus {
        case .notDetermined: break
        case .denied, .restricted: finishLocating(denied: true)
        default: manager.requestLocation()
        }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }
        CLGeocoder().reverseGeocodeLocation(location) { placemarks, _ in
            let name = placemarks?.first?.locality ?? "My location"
            DispatchQueue.main.async {
                self.settings.weatherPlace = WeatherPlace(name: name, latitude: location.coordinate.latitude,
                                                          longitude: location.coordinate.longitude)
                self.finishLocating(denied: false)
                Task { await self.forceRefresh() }
            }
        }
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        finishLocating(denied: (error as? CLError)?.code == .denied)
    }
}
