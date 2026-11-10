import Foundation

// MARK: - Water settings and today's snapshot
//
// Settings live in `UserDefaults.standard` (so `@AppStorage` drives Settings) and are
// mirrored into the App Group for the widget and the Siri actions. Today's entries live only
// in the App Group snapshot `water_today_v1`: Health is the store of truth, the snapshot is
// the local mirror the widget and the reminders read. Foundation only; compiled into both
// targets.

enum WaterSettings {
    static let appGroup = "group.com.morningvault.app"

    enum Key {
        static let enabled = "water_enabled"
        static let goalML = "water_goal_ml"
        static let windowStart = "water_window_start_min"
        static let windowEnd = "water_window_end_min"
        /// Legacy quick amounts. Read once to migrate into cups, never written again.
        static let quick1 = "water_quick_1"
        static let quick2 = "water_quick_2"
        static let quick3 = "water_quick_3"
        /// The user's cups, JSON encoded `[WaterCup]`.
        static let cups = "water_cups_v1"
        /// Tier 3 may use `.timeSensitive`. Opt-in; default false.
        static let urgentEnabled = "water_urgent_enabled"
        /// The one-time "Set from weight" sheet has been shown.
        static let goalSheetShown = "water_goal_sheet_shown"
        /// The alarm time, reused as the default window start when the user has one.
        static let briefingTime = "briefing_time"
    }

    static let mirroredKeys = [Key.enabled, Key.goalML, Key.windowStart, Key.windowEnd, Key.quick1, Key.quick2, Key.quick3,
                               Key.cups, Key.urgentEnabled, Key.goalSheetShown, Key.briefingTime]

    /// Reads the standard defaults first (the app), then the App Group mirror (an extension).
    static func value(forKey key: String, defaults: UserDefaults = .standard) -> Any? {
        if let v = defaults.object(forKey: key) { return v }
        if defaults === UserDefaults.standard { return UserDefaults(suiteName: appGroup)?.object(forKey: key) }
        return nil
    }

    static func isEnabled(defaults: UserDefaults = .standard) -> Bool {
        (value(forKey: Key.enabled, defaults: defaults) as? Bool) ?? false
    }

    static func urgentEnabled(defaults: UserDefaults = .standard) -> Bool {
        (value(forKey: Key.urgentEnabled, defaults: defaults) as? Bool) ?? false
    }

    /// The default window start: the alarm time when set, else 07:00.
    static func defaultWindowStartMinutes(defaults: UserDefaults = .standard) -> Int {
        if let seconds = value(forKey: Key.briefingTime, defaults: defaults) as? Double, seconds > 0 {
            return Int(seconds / 60)
        }
        return WaterTracker.defaultWindowStartMinutes
    }

    /// The tracker's configuration (no entries) from the saved settings.
    static func tracker(defaults: UserDefaults = .standard) -> WaterTracker {
        var t = WaterTracker()
        if let goal = value(forKey: Key.goalML, defaults: defaults) as? Int { t.goalML = WaterTracker.clampGoal(goal) }
        t.windowStartMinutes = (value(forKey: Key.windowStart, defaults: defaults) as? Int) ?? defaultWindowStartMinutes(defaults: defaults)
        t.windowEndMinutes = (value(forKey: Key.windowEnd, defaults: defaults) as? Int) ?? WaterTracker.defaultWindowEndMinutes
        if t.windowEndMinutes <= t.windowStartMinutes { t.windowEndMinutes = min(24 * 60 - 1, t.windowStartMinutes + 60) }
        t.cups = cups(defaults: defaults)
        return t
    }

    // MARK: Cups

    /// The saved cups, or the ones migrated from the old quick amounts, or the defaults.
    static func cups(defaults: UserDefaults = .standard) -> [WaterCup] {
        if let data = value(forKey: Key.cups, defaults: defaults) as? Data,
           let decoded = try? JSONDecoder().decode([WaterCup].self, from: data),
           !decoded.isEmpty {
            return WaterTracker.normalizedCups(decoded)
        }
        return WaterTracker.normalizedCups(migratedCups(defaults: defaults))
    }

    /// The first cup: what the widget, Siri and the reminders log.
    static func primaryCup(defaults: UserDefaults = .standard) -> WaterCup {
        cups(defaults: defaults).first ?? WaterCup(name: WaterTracker.defaultCupNames[0], ml: WaterGlass.ml)
    }

    /// Old `water_quick_1...3` values become named cups. No saved values: the defaults.
    static func migratedCups(defaults: UserDefaults = .standard) -> [WaterCup] {
        let saved = [Key.quick1, Key.quick2, Key.quick3].map { value(forKey: $0, defaults: defaults) as? Int }
        guard saved.contains(where: { $0 != nil }) else { return WaterTracker.defaultCups }
        return saved.enumerated().map { index, ml in
            WaterCup(name: WaterTracker.defaultCupNames[index], ml: ml ?? WaterTracker.defaultQuickAmounts[index])
        }
    }

    /// Saves the cups (normalized) and mirrors them for the widget and the intents.
    @discardableResult
    static func saveCups(_ cups: [WaterCup], defaults: UserDefaults = .standard) -> [WaterCup] {
        let normalized = WaterTracker.normalizedCups(cups)
        if let data = try? JSONEncoder().encode(normalized) {
            defaults.set(data, forKey: Key.cups)
            if defaults === UserDefaults.standard { UserDefaults(suiteName: appGroup)?.set(data, forKey: Key.cups) }
        }
        return normalized
    }

    /// Copies the standard-defaults values into the App Group so extensions see them.
    static func mirrorToAppGroup() {
        guard let group = UserDefaults(suiteName: appGroup) else { return }
        for key in mirroredKeys {
            if let v = UserDefaults.standard.object(forKey: key) {
                group.set(v, forKey: key)
            } else {
                group.removeObject(forKey: key)
            }
        }
    }
}

/// Today's water, parked in the App Group after every store write.
struct WaterTodaySnapshot: Codable, Equatable, Sendable {
    /// yyyy-MM-dd, local calendar.
    var day: String
    var goalML: Int
    var loggedML: Int
    var entries: [WaterEntry]
    var quietToday: Bool
    /// The next planned reminder, set by the scheduler; nil when nothing is pending.
    var nextSlot: Date?
    /// Set by Snooze: no reminder before this.
    var snoozedUntil: Date?
    var updatedAt: Date

    init(day: String, goalML: Int, loggedML: Int, entries: [WaterEntry], quietToday: Bool,
         nextSlot: Date? = nil, snoozedUntil: Date? = nil, updatedAt: Date = Date()) {
        self.day = day
        self.goalML = goalML
        self.loggedML = loggedML
        self.entries = entries
        self.quietToday = quietToday
        self.nextSlot = nextSlot
        self.snoozedUntil = snoozedUntil
        self.updatedAt = updatedAt
    }

    var remainingML: Int { max(0, goalML - loggedML) }
    var progress: Double { goalML > 0 ? min(1, Double(loggedML) / Double(goalML)) : 0 }
    var isGoalMet: Bool { loggedML >= goalML }

    func isToday(_ now: Date = Date(), calendar: Calendar = .current) -> Bool {
        day == ChecklistDay.key(for: now, calendar: calendar)
    }
}

enum WaterSnapshotStore {
    static let appGroup = "group.com.morningvault.app"
    static let key = "water_today_v1"

    private static var defaults: UserDefaults { UserDefaults(suiteName: appGroup) ?? .standard }

    static func load(from defaults: UserDefaults? = nil) -> WaterTodaySnapshot? {
        guard let data = (defaults ?? self.defaults).data(forKey: key) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(WaterTodaySnapshot.self, from: data)
    }

    static func save(_ snapshot: WaterTodaySnapshot, to defaults: UserDefaults? = nil) {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(snapshot) else { return }
        (defaults ?? self.defaults).set(data, forKey: key)
    }

    static func clear(from defaults: UserDefaults? = nil) {
        (defaults ?? self.defaults).removeObject(forKey: key)
    }
}

/// Asks WidgetKit to refresh the Water widget after a store write.
enum WaterWidgetReloader {
    static let widgetKind = "WaterWidget"

    nonisolated static func reload() {
        #if canImport(WidgetKit)
        WidgetCenter.shared.reloadTimelines(ofKind: widgetKind)
        #endif
    }
}

#if canImport(WidgetKit)
import WidgetKit
#endif

extension Notification.Name {
    /// A notification action or an intent wrote to the water store from outside the UI.
    static let waterChangedExternally = Notification.Name("waterChangedExternally")
    /// Open the water tracker screen (Brief row tap, notification tap, deep link).
    static let openWaterTracker = Notification.Name("openWaterTracker")
}
