import Foundation
import CoreLocation
import MapKit
import WeatherKit

/// WeatherKit service — approximate location only, no precise GPS stored/transmitted
/// Uses WeatherKit native API with city-level approximated location (no precise lat/lon transmitted)
final class WeatherService: NSObject, ObservableObject, CLLocationManagerDelegate {
    static let shared = WeatherService()

    private let locationManager = CLLocationManager()
    private var locationContinuation: CheckedContinuation<CLLocation, Error>?

    @Published var isAuthorized = false
    @Published var lastError: String?
    @Published var approximateLocation: String = "Unknown"

    override init() {
        super.init()
        locationManager.delegate = self
        // Privacy: approximate location only
        locationManager.desiredAccuracy = kCLLocationAccuracyReduced
    }

    // MARK: - Authorization

    func requestAuthorization() {
        locationManager.requestWhenInUseAuthorization()
    }

    // MARK: - Fetch with Approximate Location

    func fetchWeather() async -> WeatherData? {
        // Request authorization if needed
        guard isAuthorized else {
            requestAuthorization()
            // Wait briefly for auth
            try? await Task.sleep(nanoseconds: 500_000_000)
            guard isAuthorized else { return nil }
            return await fetchWeather()
        }

        // Get location (approximate)
        let location: CLLocation
        do {
            location = try await getCurrentLocation()
        } catch {
            lastError = "Location unavailable: \(error.localizedDescription)"
            return nil
        }

        // Reverse geocode to city name only (no precise address stored)
        await reverseGeocodeToCity(location: location)

        // Fetch weather using WeatherKit (privacy: no wttr.in call, no precise lat/lon in URL)
        return await fetchWeatherByLocation(location)
    }

    private func reverseGeocodeToCity(location: CLLocation) async {
        if #available(iOS 26.0, *) {
            guard let request = MKReverseGeocodingRequest(location: location) else { return }
            await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                request.getMapItems { [weak self] mapItems, error in
                    defer { continuation.resume() }
                    guard let self = self, let item = mapItems?.first else { return }
                    let city = item.addressRepresentations?.cityName
                        ?? item.addressRepresentations?.cityWithContext
                        ?? item.placemark.locality
                        ?? item.placemark.administrativeArea
                        ?? "Unknown"
                    Task { @MainActor in
                        self.approximateLocation = city
                    }
                }
            }
        } else {
            let geocoder = CLGeocoder()
            if let placemarks = try? await geocoder.reverseGeocodeLocation(location),
               let placemark = placemarks.first {
                let city = placemark.locality ?? placemark.administrativeArea ?? "Unknown"
                await MainActor.run { self.approximateLocation = city }
            }
        }
    }

    // MARK: - Fetch via WeatherKit (native, no wttr.in)

    private func fetchWeatherByLocation(_ location: CLLocation) async -> WeatherData? {
        do {
            let weather = try await WeatherKit.WeatherService.shared.weather(for: location)
            return parseWeatherKitResponse(weather)
        } catch {
            lastError = error.localizedDescription
            return nil
        }
    }

    // MARK: - Parse WeatherKit response → WeatherData

    private func parseWeatherKitResponse(_ weather: WeatherKit.Weather) -> WeatherData? {
        let current = weather.currentWeather

        let tempC = Int(current.temperature.value)
        let condition = current.condition.description
        let humidity = Int(current.humidity * 100)
        let windKph = Int(current.wind.speed.value)
        let windDir = current.wind.compassDirection.rawValue
        let feelsLikeC = Int(current.apparentTemperature.value)
        let uvIndex = current.uvIndex.value
        let precipMM: Double = 0  // CurrentWeather doesn't expose precip chance; daily forecast available if needed

        let icon: String
        switch current.condition {
        case .clear, .mostlyClear, .hot: icon = "☀️"
        case .partlyCloudy, .mostlyCloudy, .cloudy: icon = "☁️"
        case .rain, .heavyRain, .drizzle, .isolatedThunderstorms: icon = "🌧️"
        case .snow, .heavySnow, .flurries, .sleet, .blizzard: icon = "❄️"
        case .thunderstorms: icon = "⛈️"
        case .foggy, .haze, .smoky: icon = "🌫️"
        case .windy: icon = "💨"
        default: icon = "🌤️"
        }

        return WeatherData(
            temperatureC: tempC,
            feelsLikeC: feelsLikeC,
            condition: condition,
            conditionIcon: icon,
            humidity: humidity,
            windKph: windKph,
            windDirection: windDir,
            uvIndex: uvIndex,
            precipMM: precipMM,
            location: approximateLocation
        )
    }

    // MARK: - CLLocationManagerDelegate

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        switch manager.authorizationStatus {
        case .authorizedWhenInUse, .authorizedAlways:
            isAuthorized = true
        default:
            isAuthorized = false
        }
    }

    private func getCurrentLocation() async throws -> CLLocation {
        if locationManager.authorizationStatus == .notDetermined {
            requestAuthorization()
        }

        return try await withCheckedThrowingContinuation { continuation in
            self.locationContinuation = continuation
            locationManager.requestLocation()
        }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }
        locationContinuation?.resume(returning: location)
        locationContinuation = nil
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        locationContinuation?.resume(throwing: error)
        locationContinuation = nil
    }
}
