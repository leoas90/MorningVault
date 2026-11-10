import Foundation

// MARK: - Water tracker model
//
// Pure value types and math for the water tracker. No HealthKit, no notifications, no UI:
// the store feeds entries in, the scheduler and the views read numbers out. Compiled into
// the app and the widget extension (project.yml), so Foundation only.
//
// Stored amounts are always millilitres; `UnitsPreference` turns them into text.

/// The fallback glass, used when no cup is configured. The urgency tiers measure the deficit
/// in cups: the first cup's size, this when there is none.
enum WaterGlass {
    static let ml = 250
}

/// One of the user's own cups: a name and a size. Up to five, kept in order; the first one is
/// the primary cup the widget, Siri and the reminders use.
struct WaterCup: Codable, Hashable, Identifiable, Sendable {
    static let maxCount = 5
    static let maxNameLength = 20

    var id: UUID
    var name: String
    var ml: Int

    /// Clamps the size and trims the name. An empty name falls back to the size text.
    init(id: UUID = UUID(), name: String, ml: Int) {
        let clamped = WaterTracker.clampAmount(ml)
        self.id = id
        self.ml = clamped
        self.name = Self.cleanedName(name, ml: clamped)
    }

    /// Decoding goes through the designated initializer so stored JSON is clamped too.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.init(id: try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID(),
                  name: try c.decodeIfPresent(String.self, forKey: .name) ?? "",
                  ml: try c.decodeIfPresent(Int.self, forKey: .ml) ?? WaterGlass.ml)
    }

    static func cleanedName(_ raw: String, ml: Int) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return UnitsPreference.current.formatVolume(ml: ml) }
        return String(trimmed.prefix(maxNameLength))
    }
}

/// One logged amount. `source` says who wrote it: the app (and mirrored to Health) or
/// another Health source (Watch, another app). `healthID` is the HealthKit sample UUID
/// once the entry is in Health; nil means it is local only (Health unavailable or pending).
struct WaterEntry: Codable, Equatable, Hashable, Identifiable, Sendable {
    enum Source: String, Codable, Sendable {
        case app
        case health
    }

    var id: UUID
    var ts: Date
    var ml: Int
    var source: Source
    var healthID: UUID?

    init(id: UUID = UUID(), ts: Date, ml: Int, source: Source = .app, healthID: UUID? = nil) {
        self.id = id
        self.ts = ts
        self.ml = ml
        self.source = source
        self.healthID = healthID
    }
}

/// Urgency of the next reminder, from the deficit against a linear expectation across the
/// active window. Same vocabulary as the household checklist: Gentle, Normal, Must do.
enum WaterTier: Int, Comparable, Sendable {
    /// On track (or outside the window, or a quiet day): nothing fires.
    case quiet = 0
    /// Up to one glass behind: passive, no sound.
    case nudge = 1
    /// One to two glasses behind: default level with sound, at most one every 45 minutes.
    case reminder = 2
    /// More than two glasses behind, or nothing logged by noon: time sensitive when the user
    /// opted in, otherwise active. At most three a day.
    case behind = 3

    static func < (lhs: WaterTier, rhs: WaterTier) -> Bool { lhs.rawValue < rhs.rawValue }

    var label: String {
        switch self {
        case .quiet: return "Quiet"
        case .nudge: return "Gentle"
        case .reminder: return "Normal"
        case .behind: return "Must do"
        }
    }
}

/// Today's goal, window and entries, plus the deficit math the reminders are built from.
struct WaterTracker: Codable, Equatable, Sendable {
    static let defaultGoalML = 2000
    /// Legacy quick amounts, kept only to migrate old settings into cups.
    static let defaultQuickAmounts = [250, 350, 500]
    static let defaultCupNames = ["Glass", "Bottle", "Large bottle"]
    /// Three cups out of the box: a glass, a bottle and a large bottle.
    static var defaultCups: [WaterCup] {
        zip(defaultCupNames, defaultQuickAmounts).map { WaterCup(name: $0, ml: $1) }
    }
    static let defaultWindowStartMinutes = 7 * 60
    static let defaultWindowEndMinutes = 21 * 60
    /// The evening close fires this long before the window ends.
    static let eveningCloseLeadMinutes = 60
    /// Goal suggestion: 35 mL per kilogram of body weight, rounded to 50.
    static let mlPerKilogram = 35
    static let goalRange = 500...6000

    var goalML: Int
    var entries: [WaterEntry]
    /// Minutes after local midnight.
    var windowStartMinutes: Int
    var windowEndMinutes: Int
    /// The user's cups, in order. Never empty; at most `WaterCup.maxCount`.
    var cups: [WaterCup]
    var quietToday: Bool

    init(goalML: Int = WaterTracker.defaultGoalML,
         entries: [WaterEntry] = [],
         windowStartMinutes: Int = WaterTracker.defaultWindowStartMinutes,
         windowEndMinutes: Int = WaterTracker.defaultWindowEndMinutes,
         cups: [WaterCup]? = nil,
         quietToday: Bool = false) {
        self.goalML = goalML
        self.entries = entries
        self.windowStartMinutes = windowStartMinutes
        self.windowEndMinutes = windowEndMinutes
        self.cups = WaterTracker.normalizedCups(cups ?? WaterTracker.defaultCups)
        self.quietToday = quietToday
    }

    // MARK: Cups

    /// At most five cups, never empty: an empty list falls back to the defaults.
    static func normalizedCups(_ cups: [WaterCup]) -> [WaterCup] {
        let capped = Array(cups.prefix(WaterCup.maxCount))
        return capped.isEmpty ? defaultCups : capped
    }

    /// The cup the widget, Siri, the Brief row and the reminders use.
    var primaryCup: WaterCup {
        cups.first ?? WaterCup(name: WaterTracker.defaultCupNames[0], ml: WaterGlass.ml)
    }

    /// The size the urgency tiers are measured in: the primary cup.
    var glassML: Int { primaryCup.ml }

    // MARK: Goal

    /// 35 mL per kilogram, rounded to the nearest 50 mL and clamped to the goal range.
    /// Zero or negative weight gives the default goal.
    static func suggestedGoal(kg: Double) -> Int {
        guard kg > 0, kg.isFinite else { return defaultGoalML }
        let raw = kg * Double(mlPerKilogram)
        let rounded = Int((raw / 50).rounded()) * 50
        return min(max(rounded, goalRange.lowerBound), goalRange.upperBound)
    }

    // MARK: Window

    func windowStart(on day: Date, calendar: Calendar = .current) -> Date {
        calendar.startOfDay(for: day).addingTimeInterval(TimeInterval(windowStartMinutes * 60))
    }

    func windowEnd(on day: Date, calendar: Calendar = .current) -> Date {
        calendar.startOfDay(for: day).addingTimeInterval(TimeInterval(windowEndMinutes * 60))
    }

    /// Sixty minutes before the window ends.
    func eveningClose(on day: Date, calendar: Calendar = .current) -> Date {
        windowEnd(on: day, calendar: calendar).addingTimeInterval(-TimeInterval(Self.eveningCloseLeadMinutes * 60))
    }

    func noon(on day: Date, calendar: Calendar = .current) -> Date {
        calendar.startOfDay(for: day).addingTimeInterval(12 * 3600)
    }

    func isInWindow(_ t: Date, calendar: Calendar = .current) -> Bool {
        t >= windowStart(on: t, calendar: calendar) && t < windowEnd(on: t, calendar: calendar)
    }

    // MARK: Amounts

    /// Millilitres logged on the same day as `t`.
    func logged(at t: Date, calendar: Calendar = .current) -> Int {
        entries.filter { calendar.isDate($0.ts, inSameDayAs: t) }.reduce(0) { $0 + $1.ml }
    }

    func remaining(at t: Date, calendar: Calendar = .current) -> Int {
        max(0, goalML - logged(at: t, calendar: calendar))
    }

    /// 0...1 of the goal reached.
    func progress(at t: Date, calendar: Calendar = .current) -> Double {
        guard goalML > 0 else { return 0 }
        return min(1, Double(logged(at: t, calendar: calendar)) / Double(goalML))
    }

    /// Where the intake should be at `t`: zero before the window, the goal after it, linear
    /// in between.
    func expected(at t: Date, calendar: Calendar = .current) -> Int {
        let start = windowStart(on: t, calendar: calendar)
        let end = windowEnd(on: t, calendar: calendar)
        guard end > start else { return goalML }
        if t <= start { return 0 }
        if t >= end { return goalML }
        let fraction = t.timeIntervalSince(start) / end.timeIntervalSince(start)
        return Int((Double(goalML) * fraction).rounded())
    }

    /// Expected minus logged. Negative when ahead.
    func deficit(at t: Date, calendar: Calendar = .current) -> Int {
        expected(at: t, calendar: calendar) - logged(at: t, calendar: calendar)
    }

    // MARK: Tiers

    /// The urgency at `t`. Quiet on a quiet day and outside the window. Nothing logged by
    /// noon counts as behind whatever the deficit says.
    func tier(at t: Date, calendar: Calendar = .current) -> WaterTier {
        guard !quietToday, isInWindow(t, calendar: calendar) else { return .quiet }
        let logged = logged(at: t, calendar: calendar)
        if logged == 0, t >= noon(on: t, calendar: calendar) { return .behind }
        let d = deficit(at: t, calendar: calendar)
        if d <= 0 { return .quiet }
        if d <= glassML { return .nudge }
        if d <= 2 * glassML { return .reminder }
        return .behind
    }

    /// True when the evening close should fire on the day of `t`: under goal and not quiet.
    func needsEveningClose(on day: Date, calendar: Calendar = .current) -> Bool {
        !quietToday && logged(at: day, calendar: calendar) < goalML
    }

    // MARK: Entries

    var lastAppEntry: WaterEntry? {
        entries.filter { $0.source == .app }.max { $0.ts < $1.ts }
    }

    /// Entries on the day of `t`, newest first.
    func entries(on t: Date, calendar: Calendar = .current) -> [WaterEntry] {
        entries.filter { calendar.isDate($0.ts, inSameDayAs: t) }.sorted { $0.ts > $1.ts }
    }

    // MARK: Validation

    static func clampGoal(_ ml: Int) -> Int { min(max(ml, goalRange.lowerBound), goalRange.upperBound) }
    static func clampAmount(_ ml: Int) -> Int { min(max(ml, 50), 2000) }
}

// MARK: - Volume and weight text

extension UnitsPreference {
    static let mlPerFluidOunce = 29.5735
    static let kgPerPound = 0.45359237

    /// Whole units in the user's system: millilitres or fluid ounces.
    func volumeValue(ml: Int) -> Int {
        usesImperial ? Int((Double(ml) / Self.mlPerFluidOunce).rounded()) : ml
    }

    /// "500 mL" / "17 oz".
    func formatVolume(ml: Int) -> String {
        let value = volumeValue(ml: ml)
        return usesImperial ? "\(value) oz" : "\(value.formatted(.number.grouping(.automatic))) mL"
    }

    /// "500" / "17": the number without its unit, for rows that carry the unit once.
    func formatVolumeNumber(ml: Int) -> String {
        volumeValue(ml: ml).formatted(.number.grouping(.automatic))
    }

    var volumeUnitLabel: String { usesImperial ? "oz" : "mL" }
    var weightUnitLabel: String { usesImperial ? "lb" : "kg" }

    /// A user-typed volume back to millilitres.
    func ml(fromVolume value: Double) -> Int {
        Int((usesImperial ? value * Self.mlPerFluidOunce : value).rounded())
    }

    /// A user-typed weight back to kilograms.
    func kg(fromWeight value: Double) -> Double {
        usesImperial ? value * Self.kgPerPound : value
    }

    /// Spoken volume: "a litre", "1.5 litres", "500 millilitres", "17 ounces".
    func spokenVolume(ml: Int) -> String {
        if usesImperial {
            let oz = volumeValue(ml: ml)
            return oz == 1 ? "one ounce" : "\(oz) ounces"
        }
        if ml < 950 { return "\(ml) millilitres" }
        let litres = Double(ml) / 1000
        if litres < 1.25 { return "a litre" }
        let rounded = (litres * 2).rounded() / 2
        let text = rounded == rounded.rounded() ? String(Int(rounded)) : String(format: "%.1f", rounded)
        return "\(text) litres"
    }
}
