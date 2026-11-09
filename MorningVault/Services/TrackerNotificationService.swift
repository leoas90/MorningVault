import Foundation
import UserNotifications

/// Local notifications for the household checklist: the end of a timer and (next task) the
/// per-item reminders. Stateless; every call talks to `UNUserNotificationCenter` and, for
/// actions, to the `ChecklistStore` actor. Nothing here runs on the main actor: the
/// notification delegate calls it from the system's queue.
///
/// Identifiers: `timer.<itemID>` and `check.<itemID>.<day>[.<n>]`, so a reschedule can
/// cancel its own requests and leave the morning alarm (`morning_brief_weekday_*`) alone.
enum TrackerNotificationService {
    enum Category {
        static let briefing = "BRIEFING"
        static let checkRemind = "CHECK_REMIND"
        static let timerDone = "TIMER_DONE"
        static let waterRemind = "WATER_REMIND"
    }

    enum Action {
        static let viewBrief = "VIEW_BRIEF_ACTION"
        static let markDone = "MARK_DONE"
        static let snooze30 = "SNOOZE_30"
        static let skipToday = "SKIP_TODAY"
        static let log250 = "LOG_250"
        static let log500 = "LOG_500"
    }

    enum UserInfoKey {
        static let itemID = "itemID"
        static let day = "day"
        static let slotIndex = "slotIndex"
    }

    static let timerPrefix = "timer."
    static let checkPrefix = "check."

    // MARK: Categories

    /// Every category the app uses. `setNotificationCategories` replaces the whole set, so the
    /// alarm and the trackers register through this one list.
    static var allCategories: Set<UNNotificationCategory> {
        let viewBrief = UNNotificationAction(identifier: Action.viewBrief, title: "View Brief ☀️", options: [.foreground])
        let briefing = UNNotificationCategory(identifier: Category.briefing, actions: [viewBrief], intentIdentifiers: [], options: [])

        let markDone = UNNotificationAction(identifier: Action.markDone, title: "Mark done", options: [])
        let snooze = UNNotificationAction(identifier: Action.snooze30, title: "Remind me in 30 minutes", options: [])
        let skip = UNNotificationAction(identifier: Action.skipToday, title: "Skip today", options: [])
        let check = UNNotificationCategory(identifier: Category.checkRemind, actions: [markDone, snooze, skip], intentIdentifiers: [], options: [])
        let timer = UNNotificationCategory(identifier: Category.timerDone, actions: [markDone], intentIdentifiers: [], options: [])

        // Water: amounts in the user's unit, logged in the background, no app launch.
        let units = UnitsPreference.current
        let log250 = UNNotificationAction(identifier: Action.log250, title: "Log \(units.formatVolume(ml: 250))", options: [])
        let log500 = UNNotificationAction(identifier: Action.log500, title: "Log \(units.formatVolume(ml: 500))", options: [])
        let water = UNNotificationCategory(identifier: Category.waterRemind, actions: [log250, log500, snooze], intentIdentifiers: [], options: [])
        return [briefing, check, timer, water]
    }

    static func registerCategories(center: UNUserNotificationCenter = .current()) {
        center.setNotificationCategories(allCategories)
    }

    // MARK: Timer

    static func timerIdentifier(for itemID: UUID) -> String { timerPrefix + itemID.uuidString }

    /// One notification when the timer ends: "Walk done, 20 min". Tapping it or Mark done
    /// checks the item; the row checks itself anyway if the app is open.
    static func scheduleTimerDone(item: ChecklistItem, endsAt: Date, day: String, center: UNUserNotificationCenter = .current()) async {
        registerCategories(center: center)
        center.removePendingNotificationRequests(withIdentifiers: [timerIdentifier(for: item.id)])
        let seconds = endsAt.timeIntervalSinceNow
        guard seconds > 1 else { return }

        let content = UNMutableNotificationContent()
        content.title = item.title
        if case .timer(let minutes) = item.kind {
            content.body = "Done, \(minutes) min."
        } else {
            content.body = "Timer finished."
        }
        content.sound = .default
        content.interruptionLevel = .active
        content.categoryIdentifier = Category.timerDone
        content.threadIdentifier = "household"
        content.userInfo = [UserInfoKey.itemID: item.id.uuidString, UserInfoKey.day: day]

        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: seconds, repeats: false)
        let request = UNNotificationRequest(identifier: timerIdentifier(for: item.id), content: content, trigger: trigger)
        try? await center.add(request)
    }

    static func cancelTimerDone(itemID: UUID, center: UNUserNotificationCenter = .current()) {
        let id = timerIdentifier(for: itemID)
        center.removePendingNotificationRequests(withIdentifiers: [id])
        center.removeDeliveredNotifications(withIdentifiers: [id])
    }

    // MARK: Reminders (Pro)

    /// Rebuilds the pending `check.*` requests from the store: cancels ours, plans the next
    /// seven days (see `ReminderScheduler`), adds them under the 40-request budget. Called
    /// after every store write and when the Brief opens. Without Pro nothing is scheduled.
    static func rescheduleReminders(store: ChecklistStore = .shared, now: Date = Date(), center: UNUserNotificationCenter = .current()) async {
        let pending = await center.pendingNotificationRequests().map(\.identifier)
        center.removePendingNotificationRequests(withIdentifiers: ReminderScheduler.identifiersToCancel(pending: pending))
        guard ProGate.isUnlocked else { return }
        let settings = await center.notificationSettings()
        guard settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional else { return }
        guard let ledger = try? await store.ledger(asOf: now) else { return }

        let context = ReminderScheduler.Context(
            now: now,
            calendar: .current,
            meMemberID: HouseholdPhoneSettings.meMemberID,
            briefLastOpened: HouseholdPhoneSettings.briefLastOpened,
            isPro: ProGate.isUnlocked,
            cap: max(0, ReminderScheduler.totalCap - ReminderScheduler.foreignCount(pending: pending)))
        let plans = ReminderScheduler.plan(ledger: ledger, context: context)
        guard !plans.isEmpty else { return }
        registerCategories(center: center)
        for plan in plans {
            try? await center.add(request(for: plan, timeSensitiveAllowed: settings.timeSensitiveSetting == .enabled))
        }
    }

    /// Builds the request for one plan. Gentle = passive, Normal = active, Must do = time
    /// sensitive (falls back to active while the user has not allowed it). Never critical.
    static func request(for plan: ReminderPlan, timeSensitiveAllowed: Bool) -> UNNotificationRequest {
        let content = UNMutableNotificationContent()
        content.title = plan.title
        content.body = plan.isFollowUp ? "Still to do." : "Time for this."
        content.categoryIdentifier = Category.checkRemind
        content.threadIdentifier = "household"
        content.userInfo = [UserInfoKey.itemID: plan.itemID.uuidString, UserInfoKey.day: plan.day, UserInfoKey.slotIndex: plan.slotIndex]
        switch plan.urgency {
        case .gentle:
            content.interruptionLevel = .passive
            content.sound = nil
        case .normal:
            content.interruptionLevel = .active
            content.sound = .default
        case .mustDo:
            content.interruptionLevel = timeSensitiveAllowed ? .timeSensitive : .active
            content.sound = .default
        }
        let components = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: plan.fireAt)
        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
        return UNNotificationRequest(identifier: plan.identifier, content: content, trigger: trigger)
    }

    /// True when the user has allowed Time Sensitive notifications for the app.
    static func timeSensitiveAllowed(center: UNUserNotificationCenter = .current()) async -> Bool {
        await center.notificationSettings().timeSensitiveSetting == .enabled
    }

    // MARK: Responses

    /// Handles a tap or action on a tracker notification. Returns false for other categories.
    /// Store writes go through the `ChecklistStore` actor; the Brief reloads on
    /// `.checklistChangedExternally`.
    static func handle(response: UNNotificationResponse, store: ChecklistStore = .shared) async -> Bool {
        let content = response.notification.request.content
        let category = content.categoryIdentifier
        if category == Category.waterRemind {
            await WaterReminderScheduler.handle(response: response)
            return true
        }
        guard category == Category.timerDone || category == Category.checkRemind else { return false }
        guard let idString = content.userInfo[UserInfoKey.itemID] as? String, let itemID = UUID(uuidString: idString) else { return true }
        let dayKey = content.userInfo[UserInfoKey.day] as? String
        let day = dayKey.flatMap { ChecklistDay.date(from: $0) } ?? Date()
        let slot = content.userInfo[UserInfoKey.slotIndex] as? Int ?? 0

        switch response.actionIdentifier {
        case Action.markDone:
            if category == Category.timerDone {
                try? await store.finishTimer(itemID: itemID, on: day)
            } else {
                try? await store.markDone(itemID: itemID, on: day, slotIndex: slot)
            }
        case Action.skipToday:
            try? await store.skip(itemID: itemID, on: day)
        case Action.snooze30:
            await snooze(content: content, minutes: 30)
        case UNNotificationDefaultActionIdentifier:
            // Tap: a finished timer checks itself; a reminder opens the Brief.
            if category == Category.timerDone {
                try? await store.finishTimer(itemID: itemID, on: day)
            }
            await MainActor.run { NotificationCenter.default.post(name: .viewBriefingRequested, object: nil) }
        default:
            break
        }
        await rescheduleReminders(store: store)
        await MainActor.run { NotificationCenter.default.post(name: .checklistChangedExternally, object: nil) }
        return true
    }

    /// Re-posts the same content `minutes` later under a snooze identifier.
    static func snooze(content: UNNotificationContent, minutes: Int, center: UNUserNotificationCenter = .current()) async {
        guard let copy = content.mutableCopy() as? UNMutableNotificationContent else { return }
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: TimeInterval(minutes * 60), repeats: false)
        let id = checkPrefix + "snooze." + UUID().uuidString
        try? await center.add(UNNotificationRequest(identifier: id, content: copy, trigger: trigger))
    }
}
