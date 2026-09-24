import SwiftUI

/// Where the weather in the home view is for: approximate (from the IP address),
/// a searched city, or the current location (asks for location permission).
struct WeatherSection: View {
    @Bindable var settings: AppSettings

    @State private var locator: WeatherService?
    @State private var query = ""
    @State private var results: [WeatherService.SearchResult] = []

    var body: some View {
        Section {
            LabeledContent("Location") {
                Text(settings.weatherPlace?.name ?? "Approximate (from your internet connection)")
                    .foregroundStyle(.secondary)
            }
            TextField("Search for a city", text: $query)
                .onSubmit { Task { results = await WeatherService.search(query) } }
                .task(id: query) {
                    // Search as you type, after a short pause.
                    try? await Task.sleep(for: .milliseconds(400))
                    guard !Task.isCancelled else { return }
                    results = await WeatherService.search(query)
                }
            ForEach(results) { result in
                Button {
                    settings.weatherPlace = result.place
                    query = ""
                    results = []
                } label: {
                    VStack(alignment: .leading, spacing: 1) {
                        Text(result.place.name)
                        Text(result.detail).font(.system(size: 11)).foregroundStyle(.secondary)
                    }
                }
                .buttonStyle(.plain)
            }
            HStack {
                Button {
                    let service = WeatherService(settings: settings)
                    locator = service
                    service.useCurrentLocation()
                } label: {
                    Label(locator?.isLocating == true ? "Locating…" : "Use My Location", systemImage: "location")
                }
                .disabled(locator?.isLocating == true)
                if settings.weatherPlace != nil {
                    Button("Use Approximate Location") { settings.weatherPlace = nil }
                }
            }
            if locator?.locationDenied == true {
                Text("Location access is off — allow Lenotch in System Settings → Privacy & Security → Location Services.")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
            Picker("Temperature", selection: $settings.weatherFahrenheit) {
                Text("°C").tag(false)
                Text("°F").tag(true)
            }
            .pickerStyle(.segmented)
        } header: {
            Text("Weather")
        } footer: {
            Text("Shown when both music and calendar are off. Without a city or your location, an approximate place from your internet connection is used (Zurich if that fails). Weather by Open-Meteo.")
        }
    }
}
