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
    private var locationContinuationAuth: CheckedContinuation<Void, Never>?

    @Published var isAuthorized = false
    @Published var lastError: String?
    @Published var approximateLocation: String = "Unknown"

    override init() {
        super.init()
        locationManager.delegate = self
        // Privacy: approximate location only
        locationManager.desiredAccuracy = kCLLocationAccuracyReduced
        syncAuthorizationFromManager()
    }

    /// Call on launch — delegate may not have fired yet when status was already granted.
    func syncAuthorizationFromManager() {
        switch locationManager.authorizationStatus {
        case .authorizedWhenInUse, .authorizedAlways:
            isAuthorized = true
        default:
            isAuthorized = false
        }
    }

    var needsLocationPermission: Bool {
        switch locationManager.authorizationStatus {
        case .denied, .restricted:
            return true
        case .notDetermined:
            return true
        default:
            return false
        }
    }

    // MARK: - Authorization

    func requestAuthorization() {
        locationManager.requestWhenInUseAuthorization()
    }

    // MARK: - Fetch with Approximate Location

    func fetchWeather() async -> WeatherData? {
        syncAuthorizationFromManager()

        if !isAuthorized {
            requestAuthorization()
            for _ in 0..<6 {
                try? await Task.sleep(nanoseconds: 500_000_000)
                syncAuthorizationFromManager()
                if isAuthorized { break }
            }
            if !isAuthorized { return nil }
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
        let weather = await fetchWeatherByLocation(location)
        return weather
    }

    // MARK: - Cache (delegated to TTLCache for consistency)

    private func getCachedWeather() -> WeatherData? {
        // Use shared TTLCache for consistent TTL-based caching across all services
        return nil  // Cache lookup done at BriefingViewModel level via sharedCache
    }

    // MARK: - Reverse Geocode to City

    private func reverseGeocodeToCity(location: CLLocation) async {
        // CLGeocoder.reverseGeocodeLocation is deprecated in iOS 26 but there is no stable
        // replacement API yet. The method remains functional across all supported versions.
        let geocoder = CLGeocoder()
        do {
            let placemarks: [CLPlacemark] = try await geocoder.reverseGeocodeLocation(location)
            if let placemark = placemarks.first {
                // Use locality (city name) — no precise address stored
                approximateLocation = placemark.locality ?? placemark.administrativeArea ?? "Unknown"
            }
        } catch {
            approximateLocation = "Unknown"
        }
    }

    // MARK: - Fetch via WeatherKit, wttr.in city fallback if JWT/profile fails

    private func fetchWeatherByLocation(_ location: CLLocation) async -> WeatherData? {
        do {
            let weather = try await WeatherKit.WeatherService.shared.weather(for: location)
            lastError = nil
            return parseWeatherKitResponse(weather)
        } catch {
            lastError = "WeatherKit unavailable: \(error.localizedDescription)"
            if let fallback = await fetchWttrCityFallback() {
                lastError = nil
                return fallback
            }
            return nil
        }
    }

    /// City-name only (`~city`), no lat/lon in URL — used when WeatherKit JWT fails (e.g. stale profile).
    private func fetchWttrCityFallback() async -> WeatherData? {
        let city = approximateLocation.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !city.isEmpty, city != "Unknown" else { return nil }

        let slug = city.replacingOccurrences(of: " ", with: "_")
        guard let encoded = slug.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed),
              let url = URL(string: "https://wttr.in/~\(encoded)?format=j1") else { return nil }

        var request = URLRequest(url: url, timeoutInterval: 25)
        request.setValue("MorningVault/1.0", forHTTPHeaderField: "User-Agent")

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else { return nil }
            return parseWttrJ1(data, city: city)
        } catch {
            return nil
        }
    }

    private func parseWttrJ1(_ data: Data, city: String) -> WeatherData? {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let conditions = json["current_condition"] as? [[String: Any]],
              let current = conditions.first else { return nil }

        func intVal(_ key: String) -> Int {
            if let s = current[key] as? String, let v = Int(s) { return v }
            if let n = current[key] as? Int { return n }
            return 0
        }
        func doubleVal(_ key: String) -> Double {
            if let s = current[key] as? String, let v = Double(s) { return v }
            if let n = current[key] as? Double { return n }
            return 0
        }

        var condition = "Weather"
        if let desc = current["weatherDesc"] as? [[String: Any]],
           let first = desc.first,
           let value = first["value"] as? String {
            condition = value
        }

        let tempC = intVal("temp_C")
        let feelsLikeC = intVal("FeelsLikeC")
        let humidity = intVal("humidity")
        let windKph = intVal("windspeedKmph")
        let windDir = (current["winddir16Point"] as? String) ?? ""
        let uvIndex = intVal("uvIndex")
        let precipMM = doubleVal("precipMM")

        let lower = condition.lowercased()
        let icon: String
        if lower.contains("rain") || lower.contains("drizzle") { icon = "🌧️" }
        else if lower.contains("snow") { icon = "❄️" }
        else if lower.contains("thunder") { icon = "⛈️" }
        else if lower.contains("fog") || lower.contains("mist") { icon = "🌫️" }
        else if lower.contains("cloud") || lower.contains("overcast") { icon = "☁️" }
        else if lower.contains("clear") || lower.contains("sunny") { icon = "☀️" }
        else { icon = "🌤️" }

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
            location: city
        )
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
        syncAuthorizationFromManager()
        if isAuthorized {
            locationContinuationAuth?.resume()
            locationContinuationAuth = nil
        }
    }

    private func getCurrentLocation() async throws -> CLLocation {
        if locationManager.authorizationStatus == .notDetermined {
            _ = await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                self.locationContinuationAuth = continuation
                locationManager.requestWhenInUseAuthorization()
            }
        }

        return try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<CLLocation, Error>) in
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
