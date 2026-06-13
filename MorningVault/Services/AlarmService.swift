import Foundation
import UserNotifications

/// AlarmService — UNUserNotificationCenter-only (AlarmKit requires organization Developer account)
/// Fires daily briefing notification → "View Brief" action → posts to NotificationCenter → opens briefing.
@MainActor
final class AlarmService: ObservableObject {
    static let shared = AlarmService()

    @Published var authorizationState: UNAuthorizationStatus = .notDetermined
    @Published var activeAlarms: [String] = []
    @Published var lastError: String?
    @Published var isScheduling = false

    private let notificationIDKey = "morning_brief_notification_id"
    private let fallbackScheduledKey = "fallback_notification_scheduled"

    // MARK: - Authorization

    func requestAuthorization() async {
        do {
            _ = try await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge])
            await refreshAuthorizationState()
        } catch {
            lastError = "Authorization failed: \(error.localizedDescription)"
        }
    }

    func refreshAuthorizationState() async {
        let status = await UNUserNotificationCenter.current().notificationSettings().authorizationStatus
        await MainActor.run { authorizationState = status }
    }

    // MARK: - Schedule

    /// Schedule Mon-Fri morning briefing at `hour`:`minute`.
    /// Uses separate UNCalendarNotificationTrigger per weekday — fires at system level,
    /// not app level. Works even if the app has been killed.
    func scheduleBriefing(hour: Int, minute: Int) async {
        isScheduling = true
        defer { isScheduling = false }

        let center = UNUserNotificationCenter.current()

        // Check authorization first
        let settings = await center.notificationSettings()
        if settings.authorizationStatus != .authorized {
            lastError = "Notifications not authorized. Please enable in Settings > Notifications."
            activeAlarms = []
            return
        }

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

        // Build one trigger per weekday (Mon=2 … Fri=6)
        // Each fires only on its own weekday — system-level enforcement,
        // not app delegate, so works even after app kill.
        let weekdayComponents: [Int] = [2, 3, 4, 5, 6] // Mon through Fri

        let content = UNMutableNotificationContent()
        content.title = "Morning Vault ☀️"
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
                lastError = "Failed to schedule weekday \(wd): \(error.localizedDescription)"
            }
        }

        if !scheduledIds.isEmpty {
            UserDefaults.standard.set(true, forKey: fallbackScheduledKey)
            activeAlarms = scheduledIds
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
        content.title = "Morning Vault ☀️"
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
            withIdentifiers: ["morning_brief_weekday_2", "morning_brief_weekday_3",
                               "morning_brief_weekday_4", "morning_brief_weekday_5",
                               "morning_brief_weekday_6", notificationIDKey,
                               "test_briefing_notification"]
        )
        await MainActor.run {
            activeAlarms = []
            UserDefaults.standard.set(false, forKey: fallbackScheduledKey)
        }
    }

    // MARK: - Pending

    func refreshPendingAlarms() async {
        let pending = await UNUserNotificationCenter.current().pendingNotificationRequests()
        await MainActor.run {
            activeAlarms = pending.map { $0.identifier }
        }
    }

    // MARK: - UNUserNotificationCenterDelegate Helper

    /// Call from AppDelegate SceneDelegate — sets self as notification delegate.
    func setupAsDelegate() {
        UNUserNotificationCenter.current().delegate = NotificationDelegate.shared
    }
}
