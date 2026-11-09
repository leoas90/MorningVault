import Foundation
import UserNotifications

// MARK: - Plan

/// One planned water reminder. `tier` decides the interruption level; `eveningClose` is the
/// single "before the window ends" reminder.
struct WaterReminderPlan: Equatable, Sendable {
    enum Kind: Equatable, Sendable {
        case tier(WaterTier)
        case eveningClose
    }

    var identifier: String
    var fireAt: Date
    var kind: Kind
    var title: String
    var body: String

    var tier: WaterTier {
        switch kind {
        case .tier(let t): return t
        case .eveningClose: return .reminder
        }
    }
}

// MARK: - Scheduler

/// Builds the pending `water.*` requests from the model. Pure planning in `plan`, so it can
/// be tested with a fixed clock; `reschedule` talks to `UNUserNotificationCenter` and the
/// `WaterStore` actor. Nothing here runs on the main actor.
///
/// Rules (plan A3): slots every 45 minutes from now across the window, assuming no further
/// logging; a slot fires at the tier the deficit gives it (Gentle = passive, Normal = active,
/// Must do = time sensitive only when the user opted in, else active). Must do is capped at
/// three a day, extra ones fall back to Normal. One evening close 60 minutes before the
/// window ends if still under goal. Never after the end, never on a quiet day, at most eight
/// requests. Pro only.
enum WaterReminderScheduler {
    static let prefix = "water."
    static let snoozePrefix = "water.snooze."
    static let closeSuffix = "close"
    static let maxRequests = 8
    static let maxUrgentPerDay = 3
    static let slotInterval: TimeInterval = 45 * 60

    struct Context: Sendable {
        var now: Date
        var calendar: Calendar = .current
        var isPro: Bool = true
        var isEnabled: Bool = true
        /// `water_urgent_enabled`: tier 3 may use `.timeSensitive`.
        var urgentOptIn: Bool = false
        /// No slot before this (Snooze).
        var snoozedUntil: Date? = nil
        var units: UnitsPreference = .current
    }

    /// The requests to add for the rest of today. Empty when Pro is off, the tracker is off,
    /// the day is quiet or the window has ended.
    static func plan(tracker: WaterTracker, context: Context) -> [WaterReminderPlan] {
        guard context.isPro, context.isEnabled, !tracker.quietToday else { return [] }
        let cal = context.calendar
        let now = context.now
        let day = ChecklistDay.key(for: now, calendar: cal)
        let start = tracker.windowStart(on: now, calendar: cal)
        let end = tracker.windowEnd(on: now, calendar: cal)
        let close = tracker.eveningClose(on: now, calendar: cal)
        guard now < end else { return [] }

        var plans: [WaterReminderPlan] = []
        var urgentCount = 0
        // Snooze sets the first slot exactly; otherwise the first slot is one interval out.
        let first: Date
        if let snoozed = context.snoozedUntil, snoozed > now {
            first = snoozed
        } else {
            first = now.addingTimeInterval(slotInterval)
        }
        var slot = max(first, start)
        var index = 0
        while slot < close, plans.count < maxRequests - 1 {
            var tier = tracker.tier(at: slot, calendar: cal)
            if tier == .behind {
                if urgentCount >= maxUrgentPerDay { tier = .reminder } else { urgentCount += 1 }
            }
            if tier != .quiet {
                let deficit = max(0, tracker.deficit(at: slot, calendar: cal))
                plans.append(WaterReminderPlan(
                    identifier: "\(prefix)\(day).\(index)",
                    fireAt: slot,
                    kind: .tier(tier),
                    title: "Water",
                    body: body(for: tier, deficit: deficit, units: context.units)))
                index += 1
            }
            slot = slot.addingTimeInterval(slotInterval)
        }

        if tracker.needsEveningClose(on: now, calendar: cal), close > now, close >= (context.snoozedUntil ?? .distantPast) {
            let remaining = tracker.remaining(at: now, calendar: cal)
            let endText = end.formatted(date: .omitted, time: .shortened)
            plans.append(WaterReminderPlan(
                identifier: "\(prefix)\(day).\(closeSuffix)",
                fireAt: close,
                kind: .eveningClose,
                title: "Water",
                body: "\(context.units.formatVolume(ml: remaining)) to go before \(endText)."))
        }
        return Array(plans.prefix(maxRequests))
    }

    static func body(for tier: WaterTier, deficit: Int, units: UnitsPreference) -> String {
        switch tier {
        case .quiet: return ""
        case .nudge: return "A glass keeps you on track."
        case .reminder: return "About \(units.formatVolume(ml: deficit)) behind."
        case .behind: return deficit > 0 ? "\(units.formatVolume(ml: deficit)) behind." : "Nothing logged yet today."
        }
    }

    /// Pending identifiers that are ours (including snoozes).
    static func identifiersToCancel(pending: [String]) -> [String] {
        pending.filter { $0.hasPrefix(prefix) }
    }

    // MARK: Requests

    /// Builds the request. Gentle = passive, Normal = active, Must do = time sensitive only when
    /// the user opted in and allowed it, else active. Never critical.
    static func request(for plan: WaterReminderPlan, urgentOptIn: Bool, timeSensitiveAllowed: Bool, calendar: Calendar = .current) -> UNNotificationRequest {
        let content = UNMutableNotificationContent()
        content.title = plan.title
        content.body = plan.body
        content.categoryIdentifier = TrackerNotificationService.Category.waterRemind
        content.threadIdentifier = "water"
        switch plan.tier {
        case .quiet, .nudge:
            content.interruptionLevel = .passive
            content.sound = nil
        case .reminder:
            content.interruptionLevel = .active
            content.sound = .default
        case .behind:
            content.interruptionLevel = (urgentOptIn && timeSensitiveAllowed) ? .timeSensitive : .active
            content.sound = .default
        }
        let components = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: plan.fireAt)
        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
        return UNNotificationRequest(identifier: plan.identifier, content: content, trigger: trigger)
    }

    /// Cancels every pending `water.*` request and adds today's plan. Called after every log,
    /// on Snooze, when the tracker loads and when Settings change. Without Pro, or with the
    /// tracker off, it only cancels.
    static func reschedule(store: WaterStore = .shared, now: Date = Date(), center: UNUserNotificationCenter = .current()) async {
        let pending = await center.pendingNotificationRequests().map(\.identifier)
        center.removePendingNotificationRequests(withIdentifiers: identifiersToCancel(pending: pending))
        let enabled = WaterSettings.isEnabled()
        guard ProGate.isUnlocked, enabled else {
            await store.setNextSlot(nil, now: now)
            return
        }
        let settings = await center.notificationSettings()
        guard settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional else {
            await store.setNextSlot(nil, now: now)
            return
        }
        let tracker = await store.tracker(now: now)
        let snapshot = await store.current(now: now)
        let context = Context(now: now, calendar: .current, isPro: ProGate.isUnlocked, isEnabled: enabled,
                              urgentOptIn: WaterSettings.urgentEnabled(), snoozedUntil: snapshot.snoozedUntil, units: .current)
        let plans = plan(tracker: tracker, context: context)
        await store.setNextSlot(plans.first?.fireAt, now: now)
        guard !plans.isEmpty else { return }
        TrackerNotificationService.registerCategories(center: center)
        let timeSensitiveAllowed = settings.timeSensitiveSetting == .enabled
        for plan in plans {
            try? await center.add(request(for: plan, urgentOptIn: context.urgentOptIn, timeSensitiveAllowed: timeSensitiveAllowed))
        }
    }

    // MARK: Responses

    /// Handles an action on a `WATER_REMIND` notification. Log 250 / Log 500 write through the
    /// store (and Health) and rebuild the plan; Snooze pushes the next slot 30 minutes; a tap
    /// opens the tracker.
    static func handle(response: UNNotificationResponse, store: WaterStore = .shared) async {
        switch response.actionIdentifier {
        case TrackerNotificationService.Action.log250:
            await store.log(ml: 250)
        case TrackerNotificationService.Action.log500:
            await store.log(ml: 500)
        case TrackerNotificationService.Action.snooze30:
            await store.snooze(minutes: 30)
        case UNNotificationDefaultActionIdentifier:
            await MainActor.run {
                NotificationCenter.default.post(name: .viewBriefingRequested, object: nil)
                NotificationCenter.default.post(name: .openWaterTracker, object: nil)
            }
        default:
            break
        }
        await reschedule(store: store)
        await MainActor.run { NotificationCenter.default.post(name: .waterChangedExternally, object: nil) }
    }
}
