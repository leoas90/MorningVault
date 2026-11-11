import Foundation

// MARK: - Duplicate checklist items
//
// Mirrored calendars (the same event in an iCloud and a Google calendar) used to produce two
// suggestions and therefore two independent items. The engine no longer does that, but phones
// that already added both keep the pair, and deleting the calendar event never removed them.
// This is the pure grouping pass the store runs over its active items; Foundation only, so it
// is unit-testable without Core Data and safe for the widget target.

enum ChecklistDeduper {
    /// Trim, lowercase, collapse runs of whitespace. The identity used for "same item".
    static func normalizedTitle(_ title: String) -> String {
        title.split(whereSeparator: { $0.isWhitespace || $0.isNewline })
            .map { $0.lowercased() }
            .joined(separator: " ")
    }

    /// Everything that has to match for two items to be the same real item.
    struct Key: Hashable, Sendable {
        var title: String
        var forMember: UUID?
        var kind: ChecklistItem.Kind
        var recurrence: Recurrence
    }

    static func key(for item: ChecklistItem) -> Key {
        Key(title: normalizedTitle(item.title), forMember: item.forMember, kind: item.kind, recurrence: item.recurrence)
    }

    /// One group of duplicates: the item that stays and the ones to archive.
    struct Group: Equatable, Sendable {
        var keep: UUID
        var archive: [UUID]
    }

    /// Groups of two or more active items that share a key. The keeper is the one with the
    /// most completions, then the earliest `createdAt`, then the lowest id so the result is
    /// stable. Archived items are ignored, and singletons are not returned.
    ///
    /// - Parameter completionCounts: item id -> number of recorded completions.
    static func duplicateGroups(items: [ChecklistItem], completionCounts: [UUID: Int] = [:]) -> [Group] {
        var buckets: [Key: [ChecklistItem]] = [:]
        var order: [Key] = []
        for item in items where item.archivedAt == nil {
            let k = key(for: item)
            if buckets[k] == nil { order.append(k) }
            buckets[k, default: []].append(item)
        }
        return order.compactMap { k in
            guard let group = buckets[k], group.count > 1 else { return nil }
            let ranked = group.sorted { lhs, rhs in
                let l = completionCounts[lhs.id] ?? 0
                let r = completionCounts[rhs.id] ?? 0
                if l != r { return l > r }
                if lhs.createdAt != rhs.createdAt { return lhs.createdAt < rhs.createdAt }
                return lhs.id.uuidString < rhs.id.uuidString
            }
            return Group(keep: ranked[0].id, archive: ranked.dropFirst().map(\.id))
        }
    }

    /// Ids to archive, in group order.
    static func duplicateIDsToArchive(items: [ChecklistItem], completionCounts: [UUID: Int] = [:]) -> [UUID] {
        duplicateGroups(items: items, completionCounts: completionCounts).flatMap(\.archive)
    }
}

// MARK: - Duplicate calendar events

/// The same real event mirrored into two calendars (iCloud and Google Family) arrives from
/// EventKit twice with different ids. Same title (case and whitespace insensitive) and same
/// start (the minute for timed events, the day for all-day) is one event; the first wins.
enum CalendarEventDeduper {
    static func uniqued<T>(_ items: [T], title: (T) -> String, start: (T) -> Date,
                           isAllDay: (T) -> Bool, calendar: Calendar = .current) -> [T] {
        var seen = Set<String>()
        return items.filter { item in
            let when: String
            if isAllDay(item) {
                let c = calendar.dateComponents([.year, .month, .day], from: start(item))
                when = "day-\(c.year ?? 0)-\(c.month ?? 0)-\(c.day ?? 0)"
            } else {
                when = "min-\(Int(start(item).timeIntervalSinceReferenceDate / 60))"
            }
            return seen.insert("\(ChecklistDeduper.normalizedTitle(title(item)))|\(when)").inserted
        }
    }
}
