import Foundation

// MARK: - Household checklist model
//
// Pure value types and pure functions. Nothing here touches storage or the UI; the store
// (Shared/ChecklistStore.swift) persists these and the Brief renders them. Every date rule
// takes an injected `Calendar` so the tests can pin a time zone.
//
// Public app: sample data uses fictional members only (Sam, Alex, Riley, Jordan).

// MARK: Members

struct HouseholdMember: Codable, Identifiable, Equatable, Hashable, Sendable {
    enum Role: String, Codable, CaseIterable, Sendable {
        case me, partner, child, other

        var label: String {
            switch self {
            case .me: return "Me"
            case .partner: return "Partner"
            case .child: return "Child"
            case .other: return "Other"
            }
        }
    }

    var id: UUID
    var name: String
    var role: Role

    init(id: UUID = UUID(), name: String, role: Role) {
        self.id = id
        self.name = name
        self.role = role
    }

    /// One uppercase letter for the row chip; "?" for an empty name.
    var initial: String {
        guard let first = name.trimmingCharacters(in: .whitespaces).first else { return "?" }
        return String(first).uppercased()
    }

    /// Fictional household for previews, tests and screenshots.
    static let sampleMe = HouseholdMember(id: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!, name: "Sam", role: .me)
    static let samplePartner = HouseholdMember(id: UUID(uuidString: "00000000-0000-0000-0000-000000000002")!, name: "Alex", role: .partner)
    static let sampleChild1 = HouseholdMember(id: UUID(uuidString: "00000000-0000-0000-0000-000000000003")!, name: "Riley", role: .child)
    static let sampleChild2 = HouseholdMember(id: UUID(uuidString: "00000000-0000-0000-0000-000000000004")!, name: "Jordan", role: .child)
    static let sample: [HouseholdMember] = [sampleMe, samplePartner, sampleChild1, sampleChild2]
}

// MARK: Weekday

/// ISO-style weekday with Foundation's numbering (Sunday = 1) so `Calendar.component(.weekday)`
/// maps straight onto it.
enum Weekday: Int, Codable, CaseIterable, Comparable, Hashable, Sendable {
    case sunday = 1, monday, tuesday, wednesday, thursday, friday, saturday

    static func < (lhs: Weekday, rhs: Weekday) -> Bool { lhs.rawValue < rhs.rawValue }

    static let all: Set<Weekday> = Set(allCases)
    static let weekdays: Set<Weekday> = [.monday, .tuesday, .wednesday, .thursday, .friday]
    static let weekends: Set<Weekday> = [.saturday, .sunday]

    /// "Mon", "Tue"... in the current locale.
    var shortLabel: String {
        let symbols = Calendar.current.shortWeekdaySymbols
        return symbols[rawValue - 1]
    }

    /// "M", "T"... one letter for compact chips.
    var letter: String {
        let symbols = Calendar.current.veryShortWeekdaySymbols
        return symbols[rawValue - 1]
    }

    static func of(_ date: Date, calendar: Calendar) -> Weekday {
        Weekday(rawValue: calendar.component(.weekday, from: date)) ?? .sunday
    }

    /// Monday first, as the editor shows them.
    static let editorOrder: [Weekday] = [.monday, .tuesday, .wednesday, .thursday, .friday, .saturday, .sunday]
}

// MARK: Recurrence

enum Recurrence: Codable, Equatable, Hashable, Sendable {
    case daily
    /// Weekdays, weekends and custom day pickers are all this.
    case weekdays(Set<Weekday>)
    /// Every `n` weeks on the given days, counting from the week that contains `anchor`.
    case everyNWeeks(n: Int, on: Set<Weekday>, anchor: Date)
    /// Day of month 1-31; clamps to the month's length (31 -> Feb 28/29).
    case monthly(day: Int)
    /// One day only; the item expires after it.
    case once(Date)
    /// Every `everyHours` hours from `from` to `to` (hour/minute components) on the given days.
    case hourly(everyHours: Int, from: DateComponents, to: DateComponents, on: Set<Weekday>)

    /// Longest slot list an hourly item may produce in a day.
    static let maxSlotsPerDay = 12

    var isHourly: Bool {
        if case .hourly = self { return true }
        return false
    }

    var isOnce: Bool {
        if case .once = self { return true }
        return false
    }

    /// True when the item is scheduled on the calendar day containing `day`.
    func isScheduled(on day: Date, calendar: Calendar) -> Bool {
        let weekday = Weekday.of(day, calendar: calendar)
        switch self {
        case .daily:
            return true
        case .weekdays(let days):
            return days.contains(weekday)
        case .everyNWeeks(let n, let days, let anchor):
            guard n >= 1, days.contains(weekday) else { return false }
            guard let anchorWeek = calendar.dateInterval(of: .weekOfYear, for: anchor)?.start,
                  let dayWeek = calendar.dateInterval(of: .weekOfYear, for: day)?.start else { return false }
            let weeks = calendar.dateComponents([.weekOfYear], from: anchorWeek, to: dayWeek).weekOfYear ?? 0
            // Weeks before the anchor never count; weeks after count every n.
            return weeks >= 0 && weeks % n == 0
        case .monthly(let wanted):
            guard let range = calendar.range(of: .day, in: .month, for: day) else { return false }
            let clamped = min(max(wanted, 1), range.count)
            return calendar.component(.day, from: day) == clamped
        case .once(let date):
            return calendar.isDate(date, inSameDayAs: day)
        case .hourly(_, _, _, let days):
            return days.contains(weekday) && !slots(on: day, calendar: calendar).isEmpty
        }
    }

    /// Slot start times for an hourly item on `day`, oldest first, capped at `maxSlotsPerDay`.
    /// Empty for every other recurrence. The window is inclusive at both ends: 8:00-20:00 every
    /// 2 hours gives 7 slots; 8:00-19:30 gives 6. Slots are built from clock components, so a
    /// DST day still yields slots at the wall-clock times the user chose (a time that does not
    /// exist that day is skipped).
    func slots(on day: Date, calendar: Calendar) -> [Date] {
        guard case .hourly(let every, let from, let to, _) = self, every >= 1 else { return [] }
        let startOfDay = calendar.startOfDay(for: day)
        let fromMinutes = (from.hour ?? 0) * 60 + (from.minute ?? 0)
        let toMinutes = (to.hour ?? 0) * 60 + (to.minute ?? 0)
        guard toMinutes >= fromMinutes else { return [] }
        var result: [Date] = []
        var minutes = fromMinutes
        while minutes <= toMinutes, result.count < Self.maxSlotsPerDay {
            if let date = calendar.date(bySettingHour: minutes / 60, minute: minutes % 60, second: 0, of: startOfDay),
               calendar.isDate(date, inSameDayAs: startOfDay),
               calendar.component(.hour, from: date) == minutes / 60,
               calendar.component(.minute, from: date) == minutes % 60 {
                result.append(date)
            }
            minutes += every * 60
        }
        return result
    }

    /// Index of the slot whose window contains `now` (the latest slot that has started), or
    /// nil before the first slot. Hourly only.
    func currentSlotIndex(at now: Date, calendar: Calendar) -> Int? {
        let starts = slots(on: now, calendar: calendar)
        guard let last = starts.lastIndex(where: { $0 <= now }) else { return nil }
        return last
    }

    /// Short description for the editor list: "Daily", "Weekdays", "Every 2 weeks", ...
    var summary: String {
        switch self {
        case .daily:
            return "Daily"
        case .weekdays(let days):
            if days == Weekday.all { return "Daily" }
            if days == Weekday.weekdays { return "Weekdays" }
            if days == Weekday.weekends { return "Weekends" }
            if days.isEmpty { return "Never" }
            return Weekday.editorOrder.filter { days.contains($0) }.map(\.shortLabel).joined(separator: " ")
        case .everyNWeeks(let n, let days, _):
            let dayText = Weekday.editorOrder.filter { days.contains($0) }.map(\.shortLabel).joined(separator: " ")
            return n == 1 ? dayText : "Every \(n) weeks, \(dayText)"
        case .monthly(let day):
            return "Monthly on day \(day)"
        case .once(let date):
            return "Once, " + date.formatted(date: .abbreviated, time: .omitted)
        case .hourly(let every, let from, let to, _):
            let f = Self.clock(from), t = Self.clock(to)
            return every == 1 ? "Hourly, \(f) to \(t)" : "Every \(every) hours, \(f) to \(t)"
        }
    }

    private static func clock(_ c: DateComponents) -> String {
        var comps = DateComponents()
        comps.hour = c.hour ?? 0
        comps.minute = c.minute ?? 0
        let cal = Calendar.current
        guard let date = cal.date(from: comps) else { return "\(c.hour ?? 0):00" }
        return date.formatted(date: .omitted, time: .shortened)
    }
}

// MARK: Reminder

struct ReminderRule: Codable, Equatable, Hashable, Sendable {
    enum Mode: Codable, Equatable, Hashable, Sendable {
        case atTime
        case beforeEvent(minutes: Int)
    }

    /// Same vocabulary as the water tracker: Gentle (passive), Normal (active), Must do
    /// (time sensitive). Never critical.
    enum Urgency: String, Codable, CaseIterable, Sendable {
        case gentle, normal, mustDo

        var label: String {
            switch self {
            case .gentle: return "Gentle"
            case .normal: return "Normal"
            case .mustDo: return "Must do"
            }
        }

        var explanation: String {
            switch self {
            case .gentle: return "Shows in Notification Center. No sound, screen stays dark."
            case .normal: return "Sound and banner. One follow-up an hour later if still undone."
            case .mustDo: return "Breaks through Focus when you allow it. Follow-ups every 45 minutes, up to three."
            }
        }
    }

    /// Hour and minute, local.
    var time: DateComponents
    var mode: Mode = .atTime
    var urgency: Urgency = .normal
    var nagIfUndone: Bool = true
}

// MARK: Item

struct ChecklistItem: Codable, Identifiable, Equatable, Hashable, Sendable {
    enum Kind: Codable, Equatable, Hashable, Sendable {
        case check
        case timer(minutes: Int)

        var isTimer: Bool {
            if case .timer = self { return true }
            return false
        }
    }

    static let titleLimit = 40
    static let notesLimit = 200
    /// Hard cap on active items; past this the editor says no.
    static let maxItems = 12

    /// Twelve curated SF Symbols for the icon picker.
    static let icons: [String] = [
        "pills", "figure.walk", "pianokeys", "book", "figure.2.and.child.holdinghands", "drop",
        "bed.double", "fork.knife", "dumbbell", "leaf", "iphone.slash", "star",
    ]

    var id: UUID
    var title: String
    var icon: String
    /// Member the item is for; nil = the whole household.
    var forMember: UUID?
    var kind: Kind
    var recurrence: Recurrence
    var reminder: ReminderRule?
    var notes: String
    var order: Int
    var createdAt: Date
    /// Soft delete; history stays.
    var archivedAt: Date?
    /// One-time items stop appearing after this; set from `.once`.
    var expiresAt: Date?
    /// Calendar event that produced a suggested item (next task).
    var sourceEventID: String?
    /// Suggestion rule that produced it (next task).
    var sourceRuleID: String?

    init(
        id: UUID = UUID(),
        title: String,
        icon: String = "star",
        forMember: UUID? = nil,
        kind: Kind = .check,
        recurrence: Recurrence = .daily,
        reminder: ReminderRule? = nil,
        notes: String = "",
        order: Int = 0,
        createdAt: Date = Date(),
        archivedAt: Date? = nil,
        expiresAt: Date? = nil,
        sourceEventID: String? = nil,
        sourceRuleID: String? = nil
    ) {
        self.id = id
        self.title = String(title.prefix(Self.titleLimit))
        self.icon = icon
        self.forMember = forMember
        self.kind = kind
        self.recurrence = recurrence
        self.reminder = reminder
        self.notes = String(notes.prefix(Self.notesLimit))
        self.order = order
        self.createdAt = createdAt
        self.archivedAt = archivedAt
        self.sourceEventID = sourceEventID
        self.sourceRuleID = sourceRuleID
        if let expiresAt {
            self.expiresAt = expiresAt
        } else if case .once(let date) = recurrence {
            self.expiresAt = Calendar.current.date(byAdding: .day, value: 1, to: Calendar.current.startOfDay(for: date))
        } else {
            self.expiresAt = nil
        }
    }

    var isArchived: Bool { archivedAt != nil }

    /// Title valid: 1-40 characters after trimming.
    static func isValidTitle(_ title: String) -> Bool {
        let t = title.trimmingCharacters(in: .whitespacesAndNewlines)
        return !t.isEmpty && t.count <= titleLimit
    }

    /// Active on `day`: not archived before that day, not expired, and the recurrence hits.
    func isScheduled(on day: Date, calendar: Calendar = .current) -> Bool {
        // Archived items vanish from the day they were archived onward, but stay in history.
        if let archivedAt, calendar.startOfDay(for: archivedAt) <= calendar.startOfDay(for: day) { return false }
        if let expiresAt, calendar.startOfDay(for: day) >= expiresAt { return false }
        if calendar.startOfDay(for: day) < calendar.startOfDay(for: createdAt) { return false }
        return recurrence.isScheduled(on: day, calendar: calendar)
    }

    /// Slot start times on `day` (hourly only; empty otherwise).
    func slots(on day: Date, calendar: Calendar = .current) -> [Date] {
        recurrence.slots(on: day, calendar: calendar)
    }

    /// Number of completions needed for the day to count as done: slot count for hourly, 1 otherwise.
    func slotCount(on day: Date, calendar: Calendar = .current) -> Int {
        recurrence.isHourly ? slots(on: day, calendar: calendar).count : 1
    }
}

// MARK: Completion

/// One check. "Done" = a completion exists for item + day (+ slot); undo deletes your own.
struct Completion: Codable, Identifiable, Equatable, Hashable, Sendable {
    var id: UUID
    var itemID: UUID
    /// yyyy-MM-dd, local calendar.
    var day: String
    /// 0 for non-hourly items; the slot index for hourly items.
    var slotIndex: Int
    var byMember: UUID?
    var at: Date

    init(id: UUID = UUID(), itemID: UUID, day: String, slotIndex: Int = 0, byMember: UUID? = nil, at: Date = Date()) {
        self.id = id
        self.itemID = itemID
        self.day = day
        self.slotIndex = slotIndex
        self.byMember = byMember
        self.at = at
    }
}

/// Explicit "not today": pauses the streak without breaking it.
struct Skip: Codable, Identifiable, Equatable, Hashable, Sendable {
    var id: UUID
    var itemID: UUID
    var day: String

    init(id: UUID = UUID(), itemID: UUID, day: String) {
        self.id = id
        self.itemID = itemID
        self.day = day
    }
}

// MARK: Day keys

enum ChecklistDay {
    /// yyyy-MM-dd in the given calendar's time zone.
    static func key(for date: Date, calendar: Calendar = .current) -> String {
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }

    static func date(from key: String, calendar: Calendar = .current) -> Date? {
        let parts = key.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else { return nil }
        var c = DateComponents()
        c.year = parts[0]; c.month = parts[1]; c.day = parts[2]
        return calendar.date(from: c)
    }
}

// MARK: Pure logic

/// Items plus their completions and skips, the input to every derived number.
struct ChecklistLedger: Equatable, Sendable {
    var items: [ChecklistItem]
    var completions: [Completion]
    var skips: [Skip]

    init(items: [ChecklistItem] = [], completions: [Completion] = [], skips: [Skip] = []) {
        self.items = items
        self.completions = completions
        self.skips = skips
    }

    /// Items scheduled on `day`, in user order.
    func scheduled(on day: Date, calendar: Calendar = .current) -> [ChecklistItem] {
        items.filter { $0.isScheduled(on: day, calendar: calendar) }.sorted { $0.order < $1.order }
    }

    func completions(for item: ChecklistItem, on day: Date, calendar: Calendar = .current) -> [Completion] {
        let key = ChecklistDay.key(for: day, calendar: calendar)
        return completions.filter { $0.itemID == item.id && $0.day == key }
    }

    /// Slot indices done for an hourly item on `day`.
    func doneSlots(for item: ChecklistItem, on day: Date, calendar: Calendar = .current) -> Set<Int> {
        Set(completions(for: item, on: day, calendar: calendar).map(\.slotIndex))
    }

    func isSkipped(_ item: ChecklistItem, on day: Date, calendar: Calendar = .current) -> Bool {
        let key = ChecklistDay.key(for: day, calendar: calendar)
        return skips.contains { $0.itemID == item.id && $0.day == key }
    }

    /// Done for the day: every slot checked (hourly) or any completion (otherwise).
    func isDone(_ item: ChecklistItem, on day: Date, calendar: Calendar = .current) -> Bool {
        let done = doneSlots(for: item, on: day, calendar: calendar)
        if item.recurrence.isHourly {
            let count = item.slotCount(on: day, calendar: calendar)
            guard count > 0 else { return false }
            return (0..<count).allSatisfy { done.contains($0) }
        }
        return !done.isEmpty
    }

    /// Next slot not yet checked at or after `now` for an hourly item; nil when none remain.
    func nextSlot(for item: ChecklistItem, at now: Date, calendar: Calendar = .current) -> Date? {
        let starts = item.slots(on: now, calendar: calendar)
        let done = doneSlots(for: item, on: now, calendar: calendar)
        for (index, start) in starts.enumerated() where !done.contains(index) && start >= now {
            return start
        }
        return nil
    }

    /// (done, total) over the items scheduled on `day`. Skipped items leave the total.
    func progress(on day: Date, calendar: Calendar = .current) -> (done: Int, total: Int) {
        let today = scheduled(on: day, calendar: calendar).filter { !isSkipped($0, on: day, calendar: calendar) }
        let done = today.filter { isDone($0, on: day, calendar: calendar) }.count
        return (done, today.count)
    }

    /// Consecutive scheduled days done, counting back from `asOf`. A skipped day pauses the
    /// streak (neither counts nor breaks it); an undone past day breaks it. Today, if undone,
    /// is not counted but does not break the streak either. Looks back at most 366 days.
    func streak(for item: ChecklistItem, asOf: Date, calendar: Calendar = .current) -> Int {
        var count = 0
        var cursor = calendar.startOfDay(for: asOf)
        let floor = calendar.startOfDay(for: item.createdAt)
        var isToday = true
        for _ in 0..<366 {
            if cursor < floor { break }
            if item.recurrence.isScheduled(on: cursor, calendar: calendar) {
                if isDone(item, on: cursor, calendar: calendar) {
                    count += 1
                } else if isSkipped(item, on: cursor, calendar: calendar) {
                    // pause
                } else if !isToday {
                    break
                }
            }
            isToday = false
            guard let previous = calendar.date(byAdding: .day, value: -1, to: cursor) else { break }
            cursor = previous
        }
        return count
    }

    /// Last `count` scheduled days ending at `asOf`, oldest first, for the streak dots.
    enum DayMark: Equatable, Sendable { case done, missed, skipped }

    func recentMarks(for item: ChecklistItem, asOf: Date, count: Int = 7, calendar: Calendar = .current) -> [DayMark] {
        var marks: [DayMark] = []
        var cursor = calendar.startOfDay(for: asOf)
        let floor = calendar.startOfDay(for: item.createdAt)
        var guardCount = 0
        while marks.count < count, guardCount < 120, cursor >= floor {
            guardCount += 1
            if item.recurrence.isScheduled(on: cursor, calendar: calendar) {
                if isDone(item, on: cursor, calendar: calendar) {
                    marks.append(.done)
                } else if isSkipped(item, on: cursor, calendar: calendar) {
                    marks.append(.skipped)
                } else {
                    marks.append(.missed)
                }
            }
            guard let previous = calendar.date(byAdding: .day, value: -1, to: cursor) else { break }
            cursor = previous
        }
        return marks.reversed()
    }

    /// Distinct `forMember` tags among the items scheduled on `day` (nil counts as a tag).
    func memberTagsInUse(on day: Date, calendar: Calendar = .current) -> Int {
        Set(scheduled(on: day, calendar: calendar).map { $0.forMember?.uuidString ?? "household" }).count
    }

    /// True when another active item can be added.
    var canAddItem: Bool { items.filter { !$0.isArchived }.count < ChecklistItem.maxItems }
}

// MARK: Templates

/// Starter chips shown when the editor opens with no items. Role-based, never named.
struct ChecklistTemplate: Identifiable, Equatable, Sendable {
    var id: String { title }
    var title: String
    var icon: String
    var kind: ChecklistItem.Kind = .check
    var recurrence: Recurrence = .daily

    static let all: [ChecklistTemplate] = [
        ChecklistTemplate(title: "Pack lunches", icon: "fork.knife", recurrence: .weekdays(Weekday.weekdays)),
        ChecklistTemplate(title: "Kids' meds", icon: "pills"),
        ChecklistTemplate(title: "Sign school forms", icon: "book", recurrence: .weekdays(Weekday.weekdays)),
        ChecklistTemplate(title: "Water the plants", icon: "leaf"),
        ChecklistTemplate(title: "Feed the pet", icon: "star"),
        ChecklistTemplate(title: "Take out trash", icon: "leaf", recurrence: .weekdays(Weekday.weekdays)),
        ChecklistTemplate(title: "Walk", icon: "figure.walk", kind: .timer(minutes: 20)),
        ChecklistTemplate(title: "Read 10 min", icon: "book", kind: .timer(minutes: 10)),
    ]

    /// "Time with [Child]" expands to one item per child member, or "Time with kids" if none.
    static func timeWithChildren(members: [HouseholdMember]) -> [ChecklistTemplate] {
        let children = members.filter { $0.role == .child && !$0.name.trimmingCharacters(in: .whitespaces).isEmpty }
        if children.isEmpty {
            return [ChecklistTemplate(title: "Time with kids", icon: "figure.2.and.child.holdinghands", kind: .timer(minutes: 15))]
        }
        return children.map {
            ChecklistTemplate(title: String("Time with \($0.name)".prefix(ChecklistItem.titleLimit)),
                              icon: "figure.2.and.child.holdinghands", kind: .timer(minutes: 15))
        }
    }

    func makeItem(order: Int, forMember: UUID? = nil) -> ChecklistItem {
        ChecklistItem(title: title, icon: icon, forMember: forMember, kind: kind, recurrence: recurrence, order: order)
    }
}

// MARK: Sample data

extension ChecklistItem {
    /// Six items for previews: two done, one hourly (see `ChecklistLedger.sample`).
    static let sample: [ChecklistItem] = {
        let members = HouseholdMember.sample
        let created = Date(timeIntervalSince1970: 1_760_000_000)  // well before any preview "now"
        return [
            ChecklistItem(id: UUID(uuidString: "10000000-0000-0000-0000-000000000001")!, title: "Pack lunches", icon: "fork.knife",
                          forMember: members[2].id, recurrence: .weekdays(Weekday.weekdays), order: 0, createdAt: created),
            ChecklistItem(id: UUID(uuidString: "10000000-0000-0000-0000-000000000002")!, title: "Kids' meds", icon: "pills",
                          forMember: members[3].id, order: 1, createdAt: created),
            ChecklistItem(id: UUID(uuidString: "10000000-0000-0000-0000-000000000003")!, title: "Walk", icon: "figure.walk",
                          forMember: members[0].id, kind: .timer(minutes: 20), order: 2, createdAt: created),
            ChecklistItem(id: UUID(uuidString: "10000000-0000-0000-0000-000000000004")!, title: "Stretch", icon: "dumbbell",
                          forMember: members[0].id,
                          recurrence: .hourly(everyHours: 2, from: DateComponents(hour: 8, minute: 0), to: DateComponents(hour: 18, minute: 0), on: Weekday.all),
                          order: 3, createdAt: created),
            ChecklistItem(id: UUID(uuidString: "10000000-0000-0000-0000-000000000005")!, title: "Water the plants", icon: "leaf",
                          order: 4, createdAt: created),
            ChecklistItem(id: UUID(uuidString: "10000000-0000-0000-0000-000000000006")!, title: "Read 10 min", icon: "book",
                          forMember: members[1].id, kind: .timer(minutes: 10), order: 5, createdAt: created),
        ]
    }()
}

extension ChecklistLedger {
    /// Preview ledger: six items, "Pack lunches" and "Kids' meds" done, hourly "Stretch" two of six.
    static func sample(now: Date, calendar: Calendar = .current) -> ChecklistLedger {
        let items = ChecklistItem.sample
        let day = ChecklistDay.key(for: now, calendar: calendar)
        var completions: [Completion] = [
            Completion(itemID: items[0].id, day: day, byMember: HouseholdMember.sampleMe.id, at: now.addingTimeInterval(-3600)),
            Completion(itemID: items[1].id, day: day, byMember: HouseholdMember.samplePartner.id, at: now.addingTimeInterval(-2400)),
            Completion(itemID: items[3].id, day: day, slotIndex: 0, at: now),
            Completion(itemID: items[3].id, day: day, slotIndex: 1, at: now),
        ]
        // A week of history so the streak dots have something to show.
        for back in 1...7 {
            guard let past = calendar.date(byAdding: .day, value: -back, to: now) else { continue }
            let key = ChecklistDay.key(for: past, calendar: calendar)
            if back != 3 { completions.append(Completion(itemID: items[2].id, day: key, at: past)) }
            completions.append(Completion(itemID: items[4].id, day: key, at: past))
            if back % 2 == 0 { completions.append(Completion(itemID: items[5].id, day: key, at: past)) }
        }
        let skips = [Skip(itemID: items[2].id, day: ChecklistDay.key(for: calendar.date(byAdding: .day, value: -3, to: now) ?? now, calendar: calendar))]
        return ChecklistLedger(items: items, completions: completions, skips: skips)
    }
}
