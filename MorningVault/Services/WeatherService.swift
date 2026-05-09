import Foundation
import CoreLocation
import MapKit

/// WeatherKit service — approximate location only, no precise GPS stored/transmitted
/// Uses wttr.in ~city for city-level privacy-preserving weather queries
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
            return await fetchWeatherByIP()
        }

        // Reverse geocode to city name only (no precise address)
        await reverseGeocodeToCity(location: location)

        // Fetch weather using city name only (privacy: ~1km city-level approximation)
        // wttr.in's ~ prefix gives city-level weather without precise lat/lon
        return await fetchWeatherByCityName(city: approximateLocation)
    }

    private func reverseGeocodeToCity(location: CLLocation) async {
        if #available(iOS 26.0, *) {
            // Use new MapKit reverse geocoding API (iOS 26+)
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
            // Fallback for earlier iOS versions
            let geocoder = CLGeocoder()
            if let placemarks = try? await geocoder.reverseGeocodeLocation(location),
               let placemark = placemarks.first {
                let city = placemark.locality ?? placemark.administrativeArea ?? "Unknown"
                await MainActor.run { self.approximateLocation = city }
            }
        }
    }

    // MARK: - Fetch by City Name (privacy-preserving: ~1km approximation via wttr.in ~ prefix)

    private func fetchWeatherByCityName(city: String) async -> WeatherData? {
        guard !city.isEmpty, city != "Unknown" else { return await fetchWeatherByIP() }
        let encodedCity = city.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? city
        let urlString = "https://wttr.in/~\(encodedCity)?format=j1"
        guard let url = URL(string: urlString) else { return nil }

        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            let response = try JSONDecoder().decode(wttrResponse.self, from: data)
            return parseWeatherResponse(response)
        } catch {
            lastError = error.localizedDescription
            return nil
        }
    }

    // MARK: - Fetch by IP (fallback — inherently approximate)

    private func fetchWeatherByIP() async -> WeatherData? {
        guard let url = URL(string: "https://wttr.in/?format=j1") else { return nil }

        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            let response = try JSONDecoder().decode(wttrResponse.self, from: data)
            return parseWeatherResponse(response)
        } catch {
            lastError = error.localizedDescription
            return nil
        }
    }

    // MARK: - Parse wttr.in response

    private func parseWeatherResponse(_ response: wttrResponse) -> WeatherData? {
        guard let current = response.current_condition.first else { return nil }
        let cc = current

        let tempC = Int(cc.temp_C) ?? 0
        let condition = cc.weatherDesc.first?.value ?? "Unknown"
        let humidity = Int(cc.humidity) ?? 0
        let windKph = Int(cc.windspeedKmph) ?? 0
        let windDir = cc.winddir16Point
        let feelsLikeC = Int(cc.FeelsLikeC) ?? tempC
        let uvIndex = Int(cc.uvIndex) ?? 0
        let precipMM = Double(cc.precipMM) ?? 0

        let icon: String
        switch condition.lowercased() {
        case let c where c.contains("sun") || c.contains("clear"): icon = "☀️"
        case let c where c.contains("cloud"): icon = "☁️"
        case let c where c.contains("rain"): icon = "🌧️"
        case let c where c.contains("snow"): icon = "❄️"
        case let c where c.contains("thunder"): icon = "⛈️"
        case let c where c.contains("mist") || c.contains("fog"): icon = "🌫️"
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

// MARK: - wttr.in JSON Response

private struct wttrResponse: Codable {
    let current_condition: [wttrCurrentCondition]
}

private struct wttrCurrentCondition: Codable {
    let temp_C: String
    let FeelsLikeC: String
    let humidity: String
    let windspeedKmph: String
    let winddir16Point: String
    let weatherDesc: [wttrWeatherDesc]
    let uvIndex: String
    let precipMM: String
}

private struct wttrWeatherDesc: Codable {
    let value: String
}
