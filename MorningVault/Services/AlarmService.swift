import Foundation
import UserNotifications

/// AlarmService — UNUserNotificationCenter-only (AlarmKit requires organization Developer account)
/// Fires daily briefing notification → "View Brief" action → posts to NotificationCenter → opens briefing.
@MainActor
final class AlarmService: ObservableObject {
    static let shared = AlarmService()

    @Published var authorizationState: UNAuthorizationStatus = .notDetermined
    @Published var activeAlarms: [String] = []
    /// Plain-sentence problem for the user ("Notifications are off for MorningVault.").
    @Published var lastError: String?
    /// Raw framework text behind `lastError`, for a Details disclosure.
    @Published var lastErrorDetails: String?
    @Published var isScheduling = false
    /// When the next briefing notification fires, from the pending requests.
    @Published var nextAlarmDate: Date?

    static let weekdaysOnlyKey = "alarm_weekdays_only"

    /// "Thu 6:30 AM" style text for the next alarm, or nil when nothing is scheduled.
    var nextAlarmText: String? {
        guard let next = nextAlarmDate else { return nil }
        return next.formatted(.dateTime.weekday(.abbreviated).hour().minute())
    }

    private let notificationIDKey = "morning_brief_notification_id"
    private let fallbackScheduledKey = "fallback_notification_scheduled"

    // MARK: - Authorization

    func requestAuthorization() async {
        do {
            _ = try await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge])
            await refreshAuthorizationState()
        } catch {
            lastError = "Notifications could not be turned on."
            lastErrorDetails = error.localizedDescription
        }
    }

    func refreshAuthorizationState() async {
        let status = await UNUserNotificationCenter.current().notificationSettings().authorizationStatus
        await MainActor.run { authorizationState = status }
    }

    // MARK: - Schedule

    /// Schedule the morning briefing at `hour`:`minute`, Mon–Fri or every day.
    /// Uses separate UNCalendarNotificationTrigger per weekday — fires at system level,
    /// not app level. Works even if the app has been killed.
    func scheduleBriefing(hour: Int, minute: Int, weekdaysOnly: Bool = true) async {
        isScheduling = true
        defer { isScheduling = false }

        let center = UNUserNotificationCenter.current()

        // Check authorization first
        let settings = await center.notificationSettings()
        if settings.authorizationStatus != .authorized {
            lastError = "Notifications are off for MorningVault. Turn them on in Settings › Notifications."
            lastErrorDetails = nil
            activeAlarms = []
            nextAlarmDate = nil
            return
        }
        lastError = nil
        lastErrorDetails = nil

        // Cancel any existing first
        await cancelBriefingAlarm()

        // Register category with "View Brief" action
        let viewBriefAction = UNNotificationAction(
            identifier: "VIEW_BRIEF_ACTION",
            title: "View Brief ☀️",
            options: [.foreground]
        )
        let briefingCategory = UNNotificationCategory(
            identifier: "BRIEFING",
            actions: [viewBriefAction],
            intentIdentifiers: [],
            options: []
        )
        center.setNotificationCategories([briefingCategory])

        // Build one trigger per weekday (Sun=1 … Sat=7; Mon–Fri when weekdaysOnly).
        // Each fires only on its own weekday — system-level enforcement,
        // not app delegate, so works even after app kill.
        let weekdayComponents: [Int] = weekdaysOnly ? [2, 3, 4, 5, 6] : Array(1...7)

        let content = UNMutableNotificationContent()
        content.title = "MorningVault ☀️"
        content.body = "Your personalized briefing is ready. Weather, health, calendar & more."
        content.sound = .default
        content.categoryIdentifier = "BRIEFING"
        content.userInfo = ["deepLink": "morningvault://briefing"]

        var scheduledIds: [String] = []
        for wd in weekdayComponents {
            let trigger = UNCalendarNotificationTrigger(
                dateMatching: DateComponents(hour: hour, minute: minute, weekday: wd),
                repeats: true
            )
            let id = "morning_brief_weekday_\(wd)"
            let request = UNNotificationRequest(identifier: id, content: content, trigger: trigger)
            do {
                try await center.add(request)
                scheduledIds.append(id)
            } catch {
                lastError = "The alarm could not be scheduled."
                lastErrorDetails = "Weekday \(wd): \(error.localizedDescription)"
            }
        }

        if !scheduledIds.isEmpty {
            UserDefaults.standard.set(true, forKey: fallbackScheduledKey)
            activeAlarms = scheduledIds
            Task { await refreshPendingAlarms() }
        }
    }

    /// Schedule a one-time test notification (fires in `seconds`)
    func scheduleTest(seconds: TimeInterval = 15) async {
        isScheduling = true
        defer { isScheduling = false }

        let center = UNUserNotificationCenter.current()

        // Register category
        let viewBriefAction = UNNotificationAction(
            identifier: "VIEW_BRIEF_ACTION",
            title: "View Brief ☀️",
            options: [.foreground]
        )
        let briefingCategory = UNNotificationCategory(
            identifier: "BRIEFING",
            actions: [viewBriefAction],
            intentIdentifiers: [],
            options: []
        )
        center.setNotificationCategories([briefingCategory])

        let content = UNMutableNotificationContent()
        content.title = "MorningVault ☀️"
        content.body = "Test briefing notification. Tap to view."
        content.sound = .default
        content.categoryIdentifier = "BRIEFING"
        content.userInfo = ["deepLink": "morningvault://briefing"]

        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: seconds, repeats: false)

        let request = UNNotificationRequest(
            identifier: "test_briefing_\(UUID().uuidString)",
            content: content,
            trigger: trigger
        )

        try? await center.add(request)
    }

    // MARK: - Cancel

    func cancelBriefingAlarm() async {
        UNUserNotificationCenter.current().removePendingNotificationRequests(
            withIdentifiers: (1...7).map { "morning_brief_weekday_\($0)" } + [notificationIDKey, "test_briefing_notification"]
        )
        await MainActor.run {
            activeAlarms = []
            nextAlarmDate = nil
            UserDefaults.standard.set(false, forKey: fallbackScheduledKey)
        }
    }

    // MARK: - Pending

    func refreshPendingAlarms() async {
        let pending = await UNUserNotificationCenter.current().pendingNotificationRequests()
        let briefing = pending.filter { $0.identifier.hasPrefix("morning_brief_weekday_") }
        let next = briefing
            .compactMap { ($0.trigger as? UNCalendarNotificationTrigger)?.nextTriggerDate() }
            .min()
        await MainActor.run {
            activeAlarms = briefing.map { $0.identifier }
            nextAlarmDate = next
        }
    }

    // MARK: - UNUserNotificationCenterDelegate Helper

    /// Call from AppDelegate SceneDelegate — sets self as notification delegate.
    func setupAsDelegate() {
        UNUserNotificationCenter.current().delegate = NotificationDelegate.shared
    }
}
