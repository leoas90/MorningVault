import Foundation

/// Today's checklist, derived from the Core Data store after every write and parked in the
/// App Group so the widget and the Siri / Shortcuts actions (own processes) can show it
/// without opening the store. Same pattern as `meetings_snapshot_v1`.
///
/// Foundation-only: compiled into the app and the widget extension.
struct ChecklistTodaySnapshot: Codable, Equatable, Sendable {
    struct Item: Codable, Equatable, Identifiable, Sendable {
        var id: UUID
        var title: String
        /// Member initial for the row chip; nil = whole household.
        var forInitial: String?
        var isDone: Bool
        /// Hourly items: the next unchecked slot start, if any.
        var nextSlot: Date?
    }

    /// yyyy-MM-dd, local calendar.
    var day: String
    var done: Int
    var total: Int
    /// Up to three undone titles, in user order.
    var nextUndoneTitles: [String]
    var items: [Item]
    var updatedAt: Date

    var isToday: Bool { day == ChecklistTodaySnapshot.dayKey(Date()) }
    var isComplete: Bool { total > 0 && done >= total }

    static func dayKey(_ date: Date, calendar: Calendar = .current) -> String {
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }
}

enum ChecklistSnapshotStore {
    static let appGroup = "group.com.morningvault.app"
    static let key = "checklist_today_v1"

    private static var defaults: UserDefaults {
        UserDefaults(suiteName: appGroup) ?? .standard
    }

    static func load() -> ChecklistTodaySnapshot? {
        guard let data = defaults.data(forKey: key) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(ChecklistTodaySnapshot.self, from: data)
    }

    static func save(_ snapshot: ChecklistTodaySnapshot) {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(snapshot) else { return }
        defaults.set(data, forKey: key)
    }

    static func clear() {
        defaults.removeObject(forKey: key)
    }
}
