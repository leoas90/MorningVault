import Foundation

/// Buckets past meetings the way the home list shows them.
public enum MeetingDayGroup: Int, CaseIterable, Sendable, Comparable, Identifiable {
    case today
    case yesterday
    case thisWeek
    case earlier

    public var id: Int { rawValue }

    public var title: String {
        switch self {
        case .today: return "Today"
        case .yesterday: return "Yesterday"
        case .thisWeek: return "This week"
        case .earlier: return "Earlier"
        }
    }

    public static func < (lhs: MeetingDayGroup, rhs: MeetingDayGroup) -> Bool {
        lhs.rawValue < rhs.rawValue
    }

    /// The bucket `date` belongs to when seen from `now`.
    ///
    /// Anything from the start of today onwards (including the future) is
    /// "Today"; "This week" is the five days before yesterday.
    public static func group(for date: Date, now: Date = Date(), calendar: Calendar = .current) -> MeetingDayGroup {
        let startOfToday = calendar.startOfDay(for: now)
        if date >= startOfToday { return .today }
        guard let startOfYesterday = calendar.date(byAdding: .day, value: -1, to: startOfToday) else { return .earlier }
        if date >= startOfYesterday { return .yesterday }
        guard let startOfWeekWindow = calendar.date(byAdding: .day, value: -6, to: startOfToday) else { return .earlier }
        if date >= startOfWeekWindow { return .thisWeek }
        return .earlier
    }

    /// Splits `items` into ordered buckets, keeping the order of `items`
    /// inside each bucket. Empty buckets are left out.
    public static func grouped<Item>(
        _ items: [Item],
        date: (Item) -> Date,
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> [(group: MeetingDayGroup, items: [Item])] {
        var buckets: [MeetingDayGroup: [Item]] = [:]
        for item in items {
            buckets[group(for: date(item), now: now, calendar: calendar), default: []].append(item)
        }
        return MeetingDayGroup.allCases.compactMap { group in
            guard let bucket = buckets[group], !bucket.isEmpty else { return nil }
            return (group: group, items: bucket)
        }
    }
}

/// Case-insensitive search over the text of a meeting.
public enum MeetingSearch {
    /// True when `query` is empty or appears in any of `fields`.
    public static func matches(query: String, fields: [String]) -> Bool {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return true }
        return fields.contains { $0.localizedCaseInsensitiveContains(trimmed) }
    }
}
