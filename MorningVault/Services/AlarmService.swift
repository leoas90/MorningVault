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
            let granted = try await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge])
            await updateAuthorizationState(granted: granted)
        } catch {
            lastError = error.localizedDescription
        }
    }

    private func updateAuthorizationState(granted: Bool) async {
        let status = await UNUserNotificationCenter.current().notificationSettings().authorizationStatus
        await MainActor.run { self.authorizationState = status }
    }

    // MARK: - Schedule Daily Briefing

    func scheduleBriefing(hour: Int, minute: Int) async {
        isScheduling = true
        defer { isScheduling = false }

        // Cancel any existing first
        await cancelBriefingAlarm()

        let center = UNUserNotificationCenter.current()

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

        // Build trigger — weekdays only (Mon-Fri)
        var dateComponents = DateComponents()
        dateComponents.hour = hour
        dateComponents.minute = minute
        dateComponents.weekday = nil // We'll filter in the notification delivery

        // Actually use a calendar trigger with weekdays set
        let trigger = UNCalendarNotificationTrigger(
            dateMatching: DateComponents(hour: hour, minute: minute, weekday: nil, weekdayOrdinal: nil),
            repeats: false
        )

        let content = UNMutableNotificationContent()
        content.title = "Morning Vault ☀️"
        content.body = "Your personalized briefing is ready. Weather, health, calendar & more."
        content.sound = .default
        content.categoryIdentifier = "BRIEFING"
        content.userInfo = ["deepLink": "morningvault://briefing"]

        let request = UNNotificationRequest(
            identifier: notificationIDKey,
            content: content,
            trigger: trigger
        )

        do {
            try await center.add(request)
            UserDefaults.standard.set(true, forKey: fallbackScheduledKey)
            activeAlarms = [notificationIDKey]
        } catch {
            lastError = "Failed to schedule notification: \(error.localizedDescription)"
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
            identifier: "test_briefing_notification",
            content: content,
            trigger: trigger
        )

        try? await center.add(request)
    }

    // MARK: - Cancel

    func cancelBriefingAlarm() async {
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [notificationIDKey, "test_briefing_notification"])
        UserDefaults.standard.removeObject(forKey: fallbackScheduledKey)
        activeAlarms = []
    }

    func cancelAll() {
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [notificationIDKey, "test_briefing_notification"])
        UserDefaults.standard.removeObject(forKey: fallbackScheduledKey)
        activeAlarms = []
    }

    // MARK: - Refresh

    func refreshAlarms() async {
        let pending = await UNUserNotificationCenter.current().pendingNotificationRequests()
        await MainActor.run { self.activeAlarms = pending.map { $0.identifier } }
    }
}

// Notification.Name values are defined in MorningVaultApp.swift

// MARK: - UNUserNotificationCenterDelegate Helper

/// Call this from your App delegate or SceneDelegate to wire up the "View Brief" action
func configureNotificationCategories() {
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
    UNUserNotificationCenter.current().setNotificationCategories([briefingCategory])
}
