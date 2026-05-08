import Foundation
import CoreLocation

/// WeatherKit service — approximate location only, no precise GPS stored/transmitted
/// Uses wttr.in which requires no API key and accepts city/area queries
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
        let geocoder = CLGeocoder()
        do {
            let placemarks = try await geocoder.reverseGeocodeLocation(location)
            if let placemark = placemarks.first {
                let city = placemark.locality ?? placemark.administrativeArea ?? "Unknown"
                await MainActor.run {
                    approximateLocation = city
                }
            }
        } catch {
            // Proceed without city name
        }

        // Fetch weather using lat/lon (approximate, no street-level precision)
        return await fetchWeatherByCoordinates(
            lat: location.coordinate.latitude,
            lon: location.coordinate.longitude
        )
    }

    // MARK: - Fetch by Coordinates (approximate — no street precision in API calls)

    private func fetchWeatherByCoordinates(lat: Double, lon: Double) async -> WeatherData? {
        let urlString = "https://wttr.in/\(lat),\(lon)?format=j1"
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
