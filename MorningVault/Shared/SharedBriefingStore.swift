import Foundation

/// Today's briefing in a form small enough to share outside the app: the widget and the
/// Siri / Shortcuts actions read it from the App Group, so neither has to load HealthKit,
/// EventKit or the network. The app writes it every time the briefing or summary changes.
///
/// Contains only what is already on screen in the app (summary text, headline titles and
/// their one-line gists, the first event title/time). No raw health numbers.
struct SharedBriefing: Codable, Equatable {
    var day: String                 // yyyy-MM-dd, local calendar
    var summary: String?
    var firstEventTitle: String?
    var firstEventStart: Date?
    var weatherLine: String?
    /// Raw weather so the widget can re-format when the Units setting changes.
    var weatherTempC: Int?
    var weatherCondition: String?
    var headlines: [Headline]
    var updatedAt: Date
    /// "Good morning, Yezid" as shown on the Brief; the widget shows the same line.
    var greeting: String?
    /// Optional one-line opener from the on-device model.
    var greetingOpener: String?

    /// Weather line in the user's current units (falls back to the saved text).
    var displayWeatherLine: String? {
        if let c = weatherTempC, let cond = weatherCondition {
            return "\(UnitsPreference.current.formatTemperatureShort(celsius: c)) \(cond)"
        }
        return weatherLine
    }

    struct Headline: Codable, Equatable {
        var title: String
        var gist: String?
        var source: String?
    }

    static func today(_ date: Date = Date()) -> String {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .gregorian)
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        return f.string(from: date)
    }

    var isToday: Bool { day == Self.today() }
}

enum SharedBriefingStore {
    static let appGroup = "group.com.morningvault.app"
    private static let key = "shared_briefing_v1"

    private static var defaults: UserDefaults {
        UserDefaults(suiteName: appGroup) ?? .standard
    }

    static func load() -> SharedBriefing? {
        guard let data = defaults.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(SharedBriefing.self, from: data)
    }

    /// Today's briefing, or nil if the last one saved is from an earlier day.
    static func loadToday() -> SharedBriefing? {
        guard let b = load(), b.isToday else { return nil }
        return b
    }

    /// Read-modify-write so the summary and the headlines can be saved independently.
    static func update(_ change: (inout SharedBriefing) -> Void) {
        var b = loadToday() ?? SharedBriefing(day: SharedBriefing.today(), summary: nil,
                                              firstEventTitle: nil, firstEventStart: nil,
                                              weatherLine: nil, weatherTempC: nil, weatherCondition: nil,
                                              headlines: [], updatedAt: Date())
        change(&b)
        b.day = SharedBriefing.today()
        b.updatedAt = Date()
        if let data = try? JSONEncoder().encode(b) {
            defaults.set(data, forKey: key)
        }
        BriefingWidgetReloader.reload()
    }
}

/// Asks WidgetKit to refresh. Lives here so the main app does not need to import WidgetKit
/// in every file that saves; a no-op where WidgetKit is unavailable.
enum BriefingWidgetReloader {
    static func reload() {
        #if canImport(WidgetKit)
        WidgetKitBridge.reloadAll()
        #endif
    }
}

#if canImport(WidgetKit)
import WidgetKit
enum WidgetKitBridge {
    static func reloadAll() { WidgetCenter.shared.reloadTimelines(ofKind: "MorningVaultSummary") }
}
#endif
