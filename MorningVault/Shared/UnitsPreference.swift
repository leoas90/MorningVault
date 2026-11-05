import Foundation

/// Units the user wants to read: Automatic (follow the device's region), Metric or Imperial.
///
/// Stored in `UserDefaults.standard` under "units" (so `@AppStorage("units")` drives the
/// Settings picker) and mirrored into the App Group so the widget and the Siri / Shortcuts
/// actions, which run in their own processes, read the same choice.
///
/// All stored data stays metric (°C, km/h, mm); conversion happens only when a value is
/// turned into text for the user.
enum UnitsPreference: String, CaseIterable, Identifiable, Sendable {
    case automatic
    case metric
    case imperial

    var id: String { rawValue }

    static let storageKey = "units"
    static let appGroup = "group.com.morningvault.app"

    var displayName: String {
        switch self {
        case .automatic: return "Automatic"
        case .metric: return "Metric"
        case .imperial: return "Imperial"
        }
    }

    /// What `.automatic` resolves to for the current locale.
    var usesImperial: Bool {
        switch self {
        case .metric: return false
        case .imperial: return true
        case .automatic:
            return Locale.current.measurementSystem != .metric
        }
    }

    // MARK: - Current preference

    /// The saved preference. In the app this reads the standard defaults (the source of
    /// truth for `@AppStorage`); in an extension it falls back to the App Group mirror.
    static var current: UnitsPreference {
        if let raw = UserDefaults.standard.string(forKey: storageKey),
           let p = UnitsPreference(rawValue: raw) {
            return p
        }
        if let raw = UserDefaults(suiteName: appGroup)?.string(forKey: storageKey),
           let p = UnitsPreference(rawValue: raw) {
            return p
        }
        return .automatic
    }

    /// Copies the standard-defaults value into the App Group so extensions see it.
    static func mirrorToAppGroup() {
        let raw = UserDefaults.standard.string(forKey: storageKey) ?? UnitsPreference.automatic.rawValue
        UserDefaults(suiteName: appGroup)?.set(raw, forKey: storageKey)
    }

    // MARK: - Formatting (stored values are always metric)

    /// "72°F" / "22°C".
    func formatTemperature(celsius: Int) -> String {
        usesImperial ? "\(Self.fahrenheit(fromCelsius: celsius))°F" : "\(celsius)°C"
    }

    /// "72°" / "22°" — for compact lines where the unit letter is noise.
    func formatTemperatureShort(celsius: Int) -> String {
        usesImperial ? "\(Self.fahrenheit(fromCelsius: celsius))°" : "\(celsius)°"
    }

    /// Difference between two Celsius readings, as the user's unit ("5°" or "3°").
    /// A Celsius delta is scaled by 9/5 for Fahrenheit (no +32 offset).
    func formatTemperatureDelta(celsius delta: Int) -> String {
        let d = abs(delta)
        return usesImperial ? "\(Int((Double(d) * 9.0 / 5.0).rounded()))°" : "\(d)°"
    }

    /// Minimum Celsius change worth mentioning as "warmer/cooler" (3°C ≈ 5°F).
    var temperatureDeltaThresholdC: Int { 3 }

    /// "12 mph" / "19 km/h".
    func formatSpeed(kph: Int) -> String {
        usesImperial ? "\(Int((Double(kph) * 0.621371).rounded())) mph" : "\(kph) km/h"
    }

    /// "3.1 mi" / "5.0 km".
    func formatDistance(km: Double) -> String {
        usesImperial ? String(format: "%.1f mi", km * 0.621371) : String(format: "%.1f km", km)
    }

    /// "0.4 in" / "10 mm" (precipitation).
    func formatPrecipitation(mm: Double) -> String {
        usesImperial ? String(format: "%.1f in", mm / 25.4) : String(format: "%.0f mm", mm)
    }

    /// Unit label for prompts ("°F" / "°C").
    var temperatureSymbol: String { usesImperial ? "°F" : "°C" }

    static func fahrenheit(fromCelsius c: Int) -> Int {
        Int((Double(c) * 9.0 / 5.0 + 32.0).rounded())
    }
}
