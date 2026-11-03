import Foundation

/// "Since yesterday": a few plain lines about what is different from the last briefing,
/// so the top of the app is about what's new rather than a repeat of yesterday.
///
/// Works by saving a tiny digest of each day's briefing on the device and comparing
/// today's against the most recent earlier one (up to 3 days back). Deterministic, no
/// model and no network: the numbers come straight from the briefing data, and health
/// changes are only ever described qualitatively.
struct DailyDigest: Codable, Equatable, Sendable {
    var day: String
    var tempC: Int?
    var condition: String?
    var eventCount: Int
    var headlineTitles: [String]
    var sleepMinutes: Int?
}

@MainActor
enum SinceYesterday {
    private static let key = "daily_digests_v1"
    private static let maxLines = 3

    static func digest(weather: WeatherData?, events: [CalendarEvent], headlines: [String], health: HealthData?) -> DailyDigest {
        let sleep = health?.sleep.map { $0.hoursAsleep * 60 + $0.minutesAsleep }
        return DailyDigest(
            day: SharedBriefing.today(),
            tempC: weather?.temperatureC,
            condition: weather?.condition,
            eventCount: events.filter { !$0.isAllDay }.count,
            headlineTitles: Array(headlines.prefix(10)),
            sleepMinutes: (sleep ?? 0) > 0 ? sleep : nil
        )
    }

    /// Saves today's digest and returns the change lines versus the previous digest.
    static func update(with today: DailyDigest) -> [String] {
        var all = load()
        all.removeAll { $0.day == today.day }
        let previous = all.filter { $0.day < today.day }.max { $0.day < $1.day }
        all.append(today)
        all = Array(all.sorted { $0.day < $1.day }.suffix(4))
        if let data = try? JSONEncoder().encode(all) {
            UserDefaults.standard.set(data, forKey: key)
        }
        guard let previous, daysBetween(previous.day, today.day) <= 3 else { return [] }
        return changes(from: previous, to: today, gapDays: daysBetween(previous.day, today.day))
    }

    static func changes(from y: DailyDigest, to t: DailyDigest, gapDays: Int) -> [String] {
        let since = gapDays <= 1 ? "yesterday" : "your last briefing"
        var lines: [String] = []

        // Calendar load
        let diff = t.eventCount - y.eventCount
        if t.eventCount == 0 && y.eventCount > 0 {
            lines.append("Clear calendar today (\(y.eventCount) event\(y.eventCount == 1 ? "" : "s") \(gapDays <= 1 ? "yesterday" : "last time")).")
        } else if abs(diff) >= 2 {
            lines.append(diff > 0
                ? "Busier day: \(t.eventCount) events, up from \(y.eventCount)."
                : "Lighter day: \(t.eventCount) event\(t.eventCount == 1 ? "" : "s"), down from \(y.eventCount).")
        }

        // Weather
        if let tc = t.tempC, let yc = y.tempC, abs(tc - yc) >= 3 {
            lines.append("\(abs(tc - yc))° \(tc > yc ? "warmer" : "cooler") than \(since).")
        } else if let tcond = t.condition?.lowercased(), let ycond = y.condition?.lowercased(),
                  isWet(tcond) != isWet(ycond) {
            lines.append(isWet(tcond) ? "Rain in today's forecast, unlike \(since)." : "Drying out after \(since)'s rain.")
        }

        // Headlines: what's still developing vs new
        let yset = Set(y.headlineTitles.map(normalize))
        let repeated = t.headlineTitles.filter { yset.contains(normalize($0)) }
        let fresh = t.headlineTitles.count - repeated.count
        if !t.headlineTitles.isEmpty, !y.headlineTitles.isEmpty {
            if let first = repeated.first {
                lines.append("Still developing: \(shorten(first))" + (fresh > 0 ? " (\(fresh) new stor\(fresh == 1 ? "y" : "ies") too)." : "."))
            } else if fresh > 0 {
                lines.append("Every top story is new since \(since).")
            }
        }

        // Sleep, qualitative only
        if let ts = t.sleepMinutes, let ys = y.sleepMinutes, abs(ts - ys) >= 45 {
            let amount = abs(ts - ys) >= 90 ? "a lot" : "a bit"
            lines.append("You slept \(amount) \(ts > ys ? "more" : "less") than the night before.")
        }

        return Array(lines.prefix(maxLines))
    }

    // MARK: - Helpers

    private static func load() -> [DailyDigest] {
        guard let data = UserDefaults.standard.data(forKey: key) else { return [] }
        return (try? JSONDecoder().decode([DailyDigest].self, from: data)) ?? []
    }

    private static func daysBetween(_ a: String, _ b: String) -> Int {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .gregorian)
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        guard let da = f.date(from: a), let db = f.date(from: b) else { return .max }
        return Calendar(identifier: .gregorian).dateComponents([.day], from: da, to: db).day ?? .max
    }

    private static func isWet(_ condition: String) -> Bool {
        ["rain", "shower", "drizzle", "storm", "thunder", "snow", "sleet"].contains { condition.contains($0) }
    }

    private static func normalize(_ title: String) -> String {
        title.lowercased().filter { $0.isLetter || $0.isNumber || $0 == " " }
            .split(separator: " ").joined(separator: " ")
    }

    private static func shorten(_ title: String) -> String {
        let t = title.trimmingCharacters(in: CharacterSet(charactersIn: " .!?"))
        return t.count <= 70 ? t : String(t.prefix(67)) + "…"
    }
}
