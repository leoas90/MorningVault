import Foundation

// MARK: - Reminder planning (pure)
//
// Turns the ledger into the list of local notifications that should be pending for the next
// seven days. No UserNotifications here, so the rules are unit-testable: scheduled days only,
// skip when done or skipped, assignee filter, urgency follow-ups, the 22:00 cutoff, the
// Gentle-while-reading rule and the total cap.

/// One notification to schedule.
struct ReminderPlan: Equatable, Hashable, Sendable {
    var identifier: String
    var itemID: UUID
    var title: String
    /// yyyy-MM-dd of the day the item is for.
    var day: String
    var slotIndex: Int
    var fireAt: Date
    var urgency: ReminderRule.Urgency
    /// True for the +60 / +45 min repeats.
    var isFollowUp: Bool
}

enum ReminderScheduler {
    /// Everything the plan needs besides the ledger.
    struct Context: Sendable {
        var now: Date
        var calendar: Calendar = .current
        /// The member this phone belongs to (`household_me_member_id`); nil = not chosen.
        var meMemberID: UUID? = nil
        /// Last time the Brief was on screen; Gentle reminders within 10 min of it are dropped.
        var briefLastOpened: Date? = nil
        var isPro: Bool = true
        var days: Int = 7
        /// How many requests may be added (40 total minus what else is pending).
        var cap: Int = ReminderScheduler.totalCap
    }

    static let identifierPrefix = "check."
    static let timerPrefix = "timer."
    /// Pending requests the whole app may hold (iOS allows 64; the alarm uses up to 7).
    static let totalCap = 40
    /// Nothing fires at or after this hour.
    static let quietHour = 22
    static let gentleReadingWindow: TimeInterval = 10 * 60
    static let normalFollowUp: TimeInterval = 60 * 60
    static let mustDoFollowUp: TimeInterval = 45 * 60
    static let mustDoFollowUpCount = 3

    /// Identifiers among `pending` that belong to the checklist reminders (not timers, not the
    /// morning alarm) and should be cancelled before a reschedule.
    static func identifiersToCancel(pending: [String]) -> [String] {
        pending.filter { $0.hasPrefix(identifierPrefix) }
    }

    /// Requests to keep the budget honest: everything pending that is not ours.
    static func foreignCount(pending: [String]) -> Int {
        pending.filter { !$0.hasPrefix(identifierPrefix) }.count
    }

    static func plan(ledger: ChecklistLedger, context: Context) -> [ReminderPlan] {
        guard context.isPro, context.cap > 0 else { return [] }
        let cal = context.calendar
        var plans: [ReminderPlan] = []

        for item in ledger.items where !item.isArchived {
            guard let rule = item.reminder else { continue }
            // Event-relative reminders need a linked event; none yet, so only clock times fire.
            guard case .atTime = rule.mode else { continue }
            // Assignee: only this phone's member, or everyone when the item is for the household.
            if let forMember = item.forMember, let me = context.meMemberID, forMember != me { continue }

            for offset in 0..<max(1, context.days) {
                guard let day = cal.date(byAdding: .day, value: offset, to: cal.startOfDay(for: context.now)) else { continue }
                guard item.isScheduled(on: day, calendar: cal) else { continue }
                if ledger.isSkipped(item, on: day, calendar: cal) { continue }
                if ledger.isDone(item, on: day, calendar: cal) { continue }
                let dayKey = ChecklistDay.key(for: day, calendar: cal)

                if item.recurrence.isHourly {
                    // One per slot, no follow-ups: the next slot is the follow-up.
                    let done = ledger.doneSlots(for: item, on: day, calendar: cal)
                    for (index, start) in item.slots(on: day, calendar: cal).enumerated() where !done.contains(index) {
                        guard start > context.now, !isQuiet(start, calendar: cal) else { continue }
                        if shouldDropGentle(rule.urgency, fireAt: start, context: context) { continue }
                        plans.append(ReminderPlan(
                            identifier: "\(identifierPrefix)\(item.id.uuidString).\(dayKey).s\(index)",
                            itemID: item.id, title: item.title, day: dayKey, slotIndex: index,
                            fireAt: start, urgency: rule.urgency, isFollowUp: false))
                    }
                    continue
                }

                guard let primary = cal.date(bySettingHour: rule.time.hour ?? 7, minute: rule.time.minute ?? 0, second: 0, of: day) else { continue }
                var fires: [(Date, Bool)] = [(primary, false)]
                switch rule.urgency {
                case .gentle:
                    break
                case .normal:
                    fires.append((primary.addingTimeInterval(normalFollowUp), true))
                case .mustDo:
                    for n in 1...mustDoFollowUpCount {
                        fires.append((primary.addingTimeInterval(Double(n) * mustDoFollowUp), true))
                    }
                }
                for (n, (fireAt, isFollowUp)) in fires.enumerated() {
                    guard fireAt > context.now else { continue }
                    guard cal.isDate(fireAt, inSameDayAs: day), !isQuiet(fireAt, calendar: cal) else { continue }
                    if shouldDropGentle(rule.urgency, fireAt: fireAt, context: context) { continue }
                    plans.append(ReminderPlan(
                        identifier: "\(identifierPrefix)\(item.id.uuidString).\(dayKey).\(n)",
                        itemID: item.id, title: item.title, day: dayKey, slotIndex: 0,
                        fireAt: fireAt, urgency: rule.urgency, isFollowUp: isFollowUp))
                }
            }
        }

        // Soonest first, then cut to the budget so the alarm always has room.
        return Array(plans.sorted { $0.fireAt < $1.fireAt }.prefix(context.cap))
    }

    /// At or after 22:00 local.
    static func isQuiet(_ date: Date, calendar: Calendar) -> Bool {
        calendar.component(.hour, from: date) >= quietHour
    }

    /// A Gentle reminder due within ten minutes after the Brief was last on screen is noise:
    /// the user is looking at the list.
    static func shouldDropGentle(_ urgency: ReminderRule.Urgency, fireAt: Date, context: Context) -> Bool {
        guard urgency == .gentle, let opened = context.briefLastOpened else { return false }
        let delta = fireAt.timeIntervalSince(opened)
        return delta >= 0 && delta <= gentleReadingWindow
    }
}

// MARK: - Local phone settings

/// Settings that belong to this phone, never to the shared household: which member is "me"
/// here, and when the Brief was last open. Standard defaults for the member (the widget and
/// intents do not need it), App Group for the open timestamp (the reminder pass may run from
/// a notification action).
enum HouseholdPhoneSettings {
    static let meMemberKey = "household_me_member_id"
    static let briefLastOpenedKey = "brief_last_opened_at"
    static let mustDoHintShownKey = "household_must_do_hint_shown"
    static let appGroup = "group.com.morningvault.app"

    nonisolated static var meMemberID: UUID? {
        get { UserDefaults.standard.string(forKey: meMemberKey).flatMap(UUID.init(uuidString:)) }
        set { UserDefaults.standard.set(newValue?.uuidString, forKey: meMemberKey) }
    }

    nonisolated static var briefLastOpened: Date? {
        get { (UserDefaults(suiteName: appGroup) ?? .standard).object(forKey: briefLastOpenedKey) as? Date }
        set { (UserDefaults(suiteName: appGroup) ?? .standard).set(newValue, forKey: briefLastOpenedKey) }
    }

    nonisolated static func markBriefOpened(at date: Date = Date()) {
        briefLastOpened = date
    }
}
