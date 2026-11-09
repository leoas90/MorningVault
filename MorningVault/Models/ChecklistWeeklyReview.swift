import Foundation

// MARK: - Weekly checklist review
//
// A Monday-to-Sunday read of the household checklist: what was achieved, what to work on.
// Pure value types and pure functions over `ChecklistLedger`; nothing here touches storage,
// the network or the UI, and every date rule takes an injected `Calendar` so the tests can
// pin a time zone. The store already keeps 90 days of history, so last week and the week
// before it are always in the ledger the Brief already loaded.
//
// Counting rules, in one place:
// - An hourly item counts one occurrence per slot that day; everything else counts one.
// - A skipped day is excluded entirely: it neither counts toward the total nor fails.
// - An item created mid-week only counts from its creation day (ChecklistItem.isScheduled
//   already refuses days before `createdAt`, and days from `archivedAt` or `expiresAt` on).
// - "This week so far" stops at `asOf`: later days in the week are not counted as missed.

struct ChecklistWeeklyReview: Equatable, Sendable {

    /// What one calendar day of the week looked like for one item.
    enum DayState: Equatable, Sendable {
        /// The item was not on the list that day (or the day is still ahead).
        case notScheduled
        case done
        /// Hourly item with some but not all slots checked.
        case partial
        case missed
        case skipped
    }

    struct ItemReview: Equatable, Sendable, Identifiable {
        var id: UUID { itemID }
        let itemID: UUID
        let title: String
        let icon: String
        /// Occurrences that counted this week (slots for hourly items), skips excluded.
        let scheduled: Int
        let done: Int
        /// Days the user explicitly skipped.
        let skippedDays: Int
        /// Current streak at the end of the reviewed range.
        let streak: Int
        let hasReminder: Bool
        /// Weekday missed most often over the trailing pattern window, only when it was
        /// missed twice or more (one week holds each weekday once, so a pattern needs weeks).
        let mostMissedWeekday: Weekday?
        /// Times it was missed on that weekday in the window.
        let mostMissedCount: Int
        /// Times that weekday came up in the window ("missed 3 of 4 Tuesdays").
        let mostMissedOutOf: Int
        /// Monday to Sunday, one entry a day.
        let days: [DayState]

        var rate: Double { scheduled == 0 ? 0 : Double(done) / Double(scheduled) }
        var isPerfect: Bool { scheduled > 0 && done >= scheduled }
        var countText: String { "\(done) of \(scheduled)" }
    }

    /// One item to work on, with the one reason the data supports.
    struct WorkOnItem: Equatable, Sendable, Identifiable {
        var id: UUID { item.itemID }
        let item: ItemReview
        /// Plain language, derived from the numbers: "missed 3 of 4 Tuesdays".
        let reason: String
    }

    /// Who checked things off, when the household has more than one member.
    struct MemberLine: Equatable, Sendable, Identifiable {
        let id: UUID
        let name: String
        let done: Int
    }

    /// At or above this, an item counts as achieved.
    static let achievedThreshold = 0.8
    /// Below this, an item lands in "work on".
    static let workOnThreshold = 0.6
    /// Most items listed under "work on".
    static let maxWorkOn = 3
    /// Weeks looked at when hunting for a missed-weekday pattern. One week holds each weekday
    /// once, so "missed 3 of 4 Tuesdays" needs a trailing window, not the reviewed week alone.
    static let patternWeeks = 4

    /// Monday, start of day.
    let weekStart: Date
    /// Sunday, start of day.
    let weekEnd: Date
    /// Last day actually counted (Sunday for a full week, today for "this week so far").
    let lastCountedDay: Date
    /// True when the range is the week in progress rather than a finished one.
    let isPartialWeek: Bool
    let items: [ItemReview]
    let doneTotal: Int
    let scheduledTotal: Int
    /// Overall rate the week before, when that week had anything scheduled.
    let previousRate: Double?
    let previousDone: Int
    let previousScheduled: Int
    let members: [MemberLine]

    // MARK: Derived

    var rate: Double { scheduledTotal == 0 ? 0 : Double(doneTotal) / Double(scheduledTotal) }

    /// Change in overall rate against the week before; nil when there is nothing to compare.
    var delta: Double? {
        guard let previousRate else { return nil }
        return rate - previousRate
    }

    /// True when the week is worth showing at all.
    var hasAnythingScheduled: Bool { scheduledTotal > 0 }

    /// Items at or above the achieved threshold, best first.
    var achieved: [ItemReview] {
        items.filter { $0.scheduled > 0 && $0.rate >= Self.achievedThreshold }
            .sorted { ($0.rate, $0.done) > ($1.rate, $1.done) }
    }

    /// Achieved items that did not miss once.
    var perfect: [ItemReview] { achieved.filter(\.isPerfect) }

    var longestStreak: Int { items.map(\.streak).max() ?? 0 }

    var itemWithLongestStreak: ItemReview? {
        guard let best = items.max(by: { $0.streak < $1.streak }), best.streak > 0 else { return nil }
        return best
    }

    /// Up to three items under the work-on threshold, lowest rate first.
    var workOn: [WorkOnItem] {
        items.filter { $0.scheduled > 0 && $0.rate < Self.workOnThreshold }
            .sorted { ($0.rate, -Double($0.scheduled)) < ($1.rate, -Double($1.scheduled)) }
            .prefix(Self.maxWorkOn)
            .map { WorkOnItem(item: $0, reason: Self.reason(for: $0)) }
    }

    /// "18 of 24 done" for the block header.
    var countText: String { "\(doneTotal) of \(scheduledTotal) done" }

    /// "up from 15 of 24" / "down from 22 of 24" / nil.
    var deltaText: String? {
        // No completions at all the week before usually means no history yet, not a bad week.
        guard let delta, previousScheduled > 0, previousDone > 0 else { return nil }
        if abs(delta) < 0.005 { return "same as the week before" }
        let direction = delta > 0 ? "up" : "down"
        return "\(direction) from \(previousDone) of \(previousScheduled)"
    }

    /// "Mon 3 - Sun 9 Nov" style range for the screen header.
    func rangeText(calendar: Calendar = .current) -> String {
        let style = Date.FormatStyle(date: .abbreviated, time: .omitted).locale(calendar.locale ?? .current)
        return "\(weekStart.formatted(style)) to \(weekEnd.formatted(style))"
    }

    // MARK: Spoken line

    /// The one Monday sentence for the spoken brief. Deterministic; nil when the week had
    /// nothing scheduled.
    var spokenLine: String? {
        guard scheduledTotal > 0 else { return nil }
        var line = "Last week you did \(doneTotal) of \(scheduledTotal) checklist items"
        if let slip = workOn.first, let weekday = slip.item.mostMissedWeekday {
            line += "; \(slip.item.title.lowercased()) slipped on \(Self.pluralWeekday(weekday))"
        } else if let best = perfect.first {
            line += "; \(best.title.lowercased()) every time"
        }
        return line + "."
    }

    /// "Tuesdays" in the current locale.
    static func pluralWeekday(_ weekday: Weekday, calendar: Calendar = .current) -> String {
        calendar.weekdaySymbols[weekday.rawValue - 1] + "s"
    }

    // MARK: Week boundaries

    /// Monday, start of day, of the week containing `date`. Independent of the calendar's
    /// `firstWeekday`: weeks in this review always run Monday to Sunday.
    static func weekStart(containing date: Date, calendar: Calendar = .current) -> Date {
        let startOfDay = calendar.startOfDay(for: date)
        let weekday = calendar.component(.weekday, from: startOfDay)
        // Foundation numbers Sunday 1 ... Saturday 7; Monday is 2.
        let back = (weekday + 5) % 7
        return calendar.date(byAdding: .day, value: -back, to: startOfDay) ?? startOfDay
    }

    /// Monday of the week before the one containing `date`.
    static func previousWeekStart(containing date: Date, calendar: Calendar = .current) -> Date {
        let start = weekStart(containing: date, calendar: calendar)
        return calendar.date(byAdding: .day, value: -7, to: start) ?? start
    }

    static func isMonday(_ date: Date, calendar: Calendar = .current) -> Bool {
        calendar.component(.weekday, from: date) == Weekday.monday.rawValue
    }

    // MARK: Build

    /// Builds the review for the Monday-to-Sunday week starting at `weekStart`.
    /// - Parameter asOf: when set and inside the week, only days up to it are counted
    ///   (the week in progress). Days after it read as not scheduled.
    static func make(
        from ledger: ChecklistLedger,
        weekStart rawStart: Date,
        calendar: Calendar = .current,
        members: [HouseholdMember] = [],
        asOf: Date? = nil
    ) -> ChecklistWeeklyReview {
        let start = calendar.startOfDay(for: rawStart)
        let end = calendar.date(byAdding: .day, value: 6, to: start) ?? start
        let limit = asOf.map { calendar.startOfDay(for: $0) }
        let lastCounted = min(end, limit ?? end)
        let isPartial = (limit ?? end) < end

        let days: [Date] = (0..<7).compactMap { calendar.date(byAdding: .day, value: $0, to: start) }
        let countedDays = days.filter { $0 <= lastCounted }

        var reviews: [ItemReview] = []
        var doneTotal = 0
        var scheduledTotal = 0

        for item in ledger.items.sorted(by: { $0.order < $1.order }) {
            var scheduled = 0
            var done = 0
            var skippedDays = 0
            var states: [DayState] = []

            for day in days {
                guard day <= lastCounted, item.isScheduled(on: day, calendar: calendar) else {
                    states.append(.notScheduled)
                    continue
                }
                if ledger.isSkipped(item, on: day, calendar: calendar) {
                    skippedDays += 1
                    states.append(.skipped)
                    continue
                }
                let occurrences = max(1, item.slotCount(on: day, calendar: calendar))
                let checked: Int
                if item.recurrence.isHourly {
                    checked = min(occurrences, ledger.doneSlots(for: item, on: day, calendar: calendar).count)
                } else {
                    checked = ledger.isDone(item, on: day, calendar: calendar) ? 1 : 0
                }
                scheduled += occurrences
                done += checked
                if checked >= occurrences {
                    states.append(.done)
                } else {
                    states.append(checked > 0 ? .partial : .missed)
                }
            }

            // Items with nothing scheduled and nothing skipped this week are not reviewed.
            guard scheduled > 0 || skippedDays > 0 else { continue }

            let pattern = missedWeekdayPattern(for: item, ledger: ledger, endingAt: lastCounted, calendar: calendar)

            reviews.append(ItemReview(
                itemID: item.id,
                title: item.title,
                icon: item.icon,
                scheduled: scheduled,
                done: done,
                skippedDays: skippedDays,
                streak: ledger.streak(for: item, asOf: lastCounted, calendar: calendar),
                hasReminder: item.reminder != nil,
                mostMissedWeekday: pattern?.weekday,
                mostMissedCount: pattern?.missed ?? 0,
                mostMissedOutOf: pattern?.outOf ?? 0,
                days: states
            ))
            doneTotal += done
            scheduledTotal += scheduled
        }

        // The week before, for the delta. Same rules, full week.
        let previousStart = calendar.date(byAdding: .day, value: -7, to: start) ?? start
        let previous = totals(from: ledger, weekStart: previousStart, calendar: calendar)

        return ChecklistWeeklyReview(
            weekStart: start,
            weekEnd: end,
            lastCountedDay: lastCounted,
            isPartialWeek: isPartial,
            items: reviews,
            doneTotal: doneTotal,
            scheduledTotal: scheduledTotal,
            previousRate: previous.scheduled > 0 ? Double(previous.done) / Double(previous.scheduled) : nil,
            previousDone: previous.done,
            previousScheduled: previous.scheduled,
            members: memberLines(from: ledger, days: countedDays, calendar: calendar, members: members)
        )
    }

    /// Convenience: last full Monday-to-Sunday week before `date`.
    static func lastFullWeek(from ledger: ChecklistLedger, asOf date: Date, calendar: Calendar = .current,
                             members: [HouseholdMember] = []) -> ChecklistWeeklyReview {
        make(from: ledger, weekStart: previousWeekStart(containing: date, calendar: calendar),
             calendar: calendar, members: members)
    }

    /// Convenience: the week in progress, counted up to `date`.
    static func weekSoFar(from ledger: ChecklistLedger, asOf date: Date, calendar: Calendar = .current,
                          members: [HouseholdMember] = []) -> ChecklistWeeklyReview {
        make(from: ledger, weekStart: weekStart(containing: date, calendar: calendar),
             calendar: calendar, members: members, asOf: date)
    }

    // MARK: Helpers

    /// (done, scheduled) over a whole week, using the same counting rules.
    private static func totals(from ledger: ChecklistLedger, weekStart start: Date, calendar: Calendar) -> (done: Int, scheduled: Int) {
        var done = 0
        var scheduled = 0
        for offset in 0..<7 {
            guard let day = calendar.date(byAdding: .day, value: offset, to: start) else { continue }
            for item in ledger.items where item.isScheduled(on: day, calendar: calendar) {
                if ledger.isSkipped(item, on: day, calendar: calendar) { continue }
                let occurrences = max(1, item.slotCount(on: day, calendar: calendar))
                scheduled += occurrences
                if item.recurrence.isHourly {
                    done += min(occurrences, ledger.doneSlots(for: item, on: day, calendar: calendar).count)
                } else if ledger.isDone(item, on: day, calendar: calendar) {
                    done += 1
                }
            }
        }
        return (done, scheduled)
    }

    /// The weekday this item slips on, over the trailing `patternWeeks` ending at `end`.
    /// Nil unless it was missed at least twice on that weekday. Skipped days do not count as
    /// misses, and a weekday only counts when the item was actually scheduled on it.
    static func missedWeekdayPattern(for item: ChecklistItem, ledger: ChecklistLedger, endingAt end: Date,
                                     calendar: Calendar = .current) -> (weekday: Weekday, missed: Int, outOf: Int)? {
        var missed: [Weekday: Int] = [:]
        var scheduled: [Weekday: Int] = [:]
        let lastDay = calendar.startOfDay(for: end)
        for back in 0..<(7 * patternWeeks) {
            guard let day = calendar.date(byAdding: .day, value: -back, to: lastDay),
                  item.isScheduled(on: day, calendar: calendar),
                  !ledger.isSkipped(item, on: day, calendar: calendar)
            else { continue }
            let weekday = Weekday.of(day, calendar: calendar)
            scheduled[weekday, default: 0] += 1
            if !ledger.isDone(item, on: day, calendar: calendar) {
                missed[weekday, default: 0] += 1
            }
        }
        // Most misses wins; ties go to the lower weekday number so the text is stable.
        guard let worst = missed.filter({ $0.value >= 2 }).max(by: { lhs, rhs in
            lhs.value == rhs.value ? lhs.key > rhs.key : lhs.value < rhs.value
        }) else { return nil }
        // A weekday is only a pattern when it stands out. An item missed the same number of
        // times on several weekdays has no weekday problem, it has a doing-it problem, and
        // calling that "missed 4 of 4 Sundays" would be misleading. The exception is an item
        // scheduled on one weekday only: there, the weekday is the whole story.
        let tiedWorst = missed.values.filter { $0 == worst.value }.count
        guard tiedWorst == 1 || scheduled.keys.count == 1 else { return nil }
        return (worst.key, worst.value, max(scheduled[worst.key] ?? worst.value, worst.value))
    }

    private static func memberLines(from ledger: ChecklistLedger, days: [Date], calendar: Calendar,
                                    members: [HouseholdMember]) -> [MemberLine] {
        guard members.count > 1 else { return [] }
        let keys = Set(days.map { ChecklistDay.key(for: $0, calendar: calendar) })
        var counts: [UUID: Int] = [:]
        for completion in ledger.completions where keys.contains(completion.day) {
            guard let member = completion.byMember else { continue }
            counts[member, default: 0] += 1
        }
        return members
            .compactMap { member in
                guard let done = counts[member.id], done > 0 else { return nil }
                return MemberLine(id: member.id, name: member.name, done: done)
            }
            .sorted { $0.done > $1.done }
    }

    /// One concrete reason, in plain language, picked from the data.
    private static func reason(for item: ItemReview) -> String {
        if let weekday = item.mostMissedWeekday, item.mostMissedCount >= 2 {
            let outOf = max(item.mostMissedOutOf, item.mostMissedCount)
            return "missed \(item.mostMissedCount) of \(outOf) \(pluralWeekday(weekday))"
        }
        if !item.hasReminder {
            return "no reminder set: add one"
        }
        return "done \(item.done) of \(item.scheduled)"
    }
}

// MARK: - Spoken line cache

/// The weekly sentence the spoken brief says on Mondays.
///
/// `VoiceBriefingService.compileShortBriefing` is synchronous and has no store access, the
/// same reason the Today line reads a published snapshot. The checklist view model writes
/// this cache whenever it loads the ledger, keyed by the Monday of the week it describes, so
/// a stale week can never be spoken.
enum WeeklyReviewVoiceCache {
    private static let lineKey = "weekly_review_spoken_line"
    private static let weekKey = "weekly_review_spoken_week"

    static func save(line: String?, weekStart: Date, calendar: Calendar = .current,
                     defaults: UserDefaults = .standard) {
        guard let line, !line.isEmpty else {
            defaults.removeObject(forKey: lineKey)
            defaults.removeObject(forKey: weekKey)
            return
        }
        defaults.set(line, forKey: lineKey)
        defaults.set(ChecklistDay.key(for: weekStart, calendar: calendar), forKey: weekKey)
    }

    /// The cached line, only when it describes the week starting at `weekStart`.
    static func line(forWeekStarting weekStart: Date, calendar: Calendar = .current,
                     defaults: UserDefaults = .standard) -> String? {
        guard let line = defaults.string(forKey: lineKey),
              defaults.string(forKey: weekKey) == ChecklistDay.key(for: weekStart, calendar: calendar)
        else { return nil }
        return line
    }
}

// MARK: - Sample data

extension ChecklistWeeklyReview {
    /// Preview review built from the sample ledger, for a week that is already over.
    static func sample(now: Date = Date(timeIntervalSince1970: 1_794_214_800), calendar: Calendar = .current) -> ChecklistWeeklyReview {
        lastFullWeek(from: ChecklistLedger.sample(now: now, calendar: calendar), asOf: now,
                     calendar: calendar, members: HouseholdMember.sample)
    }
}
