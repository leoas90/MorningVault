import SwiftUI
import BackgroundTasks
import UserNotifications

@main
struct MorningVaultApp: App {
    // BGTaskScheduler registration ID
    private let precomputationTaskID = "com.yeziddr.morningvault.precompute"
    @AppStorage("theme") private var themeRaw: String = AppTheme.system.rawValue

    private var currentTheme: AppTheme {
        AppTheme(rawValue: themeRaw) ?? .system
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .onOpenURL { url in
                    handleDeepLink(url)
                }
                .appTheme(currentTheme)
        }
    }

    init() {
        // Register notification delegate
        UNUserNotificationCenter.current().delegate = NotificationDelegate.shared

        // Register BGTaskScheduler for 6:55 AM precomputation
        registerBackgroundTasks()
        schedulePrecomputation()  // Schedule for next 6:55 AM
    }

    // MARK: - Deep Link Handling

    private func handleDeepLink(_ url: URL) {
        // DEBUG: print("[MorningVaultApp] Deep link: \(url)")
        if url.scheme == "morningvault" {
            NotificationCenter.default.post(name: .viewBriefingRequested, object: nil)
        }
    }

    // MARK: - Background Tasks

    private func registerBackgroundTasks() {
        BGTaskScheduler.shared.register(
            forTaskWithIdentifier: precomputationTaskID,
            using: nil
        ) { task in
            self.handlePrecomputation(task: task as! BGAppRefreshTask)
        }
    }

    private func handlePrecomputation(task: BGAppRefreshTask) {
        // DEBUG: print("[MorningVaultApp] 6:55 AM precomputation triggered")
        schedulePrecomputation() // schedule next

        // GATE 4 fix: respect localOnly — no network fetches in background when enabled
        if UserDefaults.standard.bool(forKey: "local_only") {
            // DEBUG: print("[MorningVaultApp] localOnly=true — skipping precomputation network fetches")
            task.setTaskCompleted(success: true)
            return
        }

        Task {
            let viewModel = BriefingViewModel()
            await viewModel.loadData()
            await viewModel.generateBriefing()
            task.setTaskCompleted(success: true)
        }

        task.expirationHandler = {
            task.setTaskCompleted(success: false)
        }
    }

    private func schedulePrecomputation() {
        let calendar = Calendar.current
        var components = calendar.dateComponents([.year, .month, .day], from: Date())
        components.hour = 6
        components.minute = 55

        guard let next6_55 = calendar.nextDate(after: Date(), matching: components, matchingPolicy: .nextTime) else { return }

        let request = BGAppRefreshTaskRequest(identifier: precomputationTaskID)
        request.earliestBeginDate = next6_55

        do {
            try BGTaskScheduler.shared.submit(request)
            // DEBUG: print("[MorningVaultApp] Precomputation scheduled for \(next6_55)")
        } catch {
            // DEBUG: print("[MorningVaultApp] Failed to schedule precomputation: \(error)")
        }
    }
}

// MARK: - Notification Delegate (for deep-link on tap)

class NotificationDelegate: NSObject, UNUserNotificationCenterDelegate {
    static let shared = NotificationDelegate()

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        // Note: Mon-Fri filtering is now done at the trigger level (per-weekday
        // UNCalendarNotificationTrigger). weekdayFilter in userInfo is no longer used.
        completionHandler([.banner, .sound])
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        if response.notification.request.content.categoryIdentifier == "BRIEFING" {
            NotificationCenter.default.post(name: .viewBriefingRequested, object: nil)
        }
        completionHandler()
    }
}

// MARK: - Notification Names

extension Notification.Name {
    static let viewBriefingRequested = Notification.Name("viewBriefingRequested")
}

// MARK: - Theme System

enum AppTheme: String, CaseIterable, Identifiable {
    case system
    case warm
    case cool
    case dark

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .system: return "System"
        case .warm: return "Warm"
        case .cool: return "Cool"
        case .dark: return "Dark"
        }
    }

    var icon: String {
        switch self {
        case .system: return "circle.lefthalf.filled"
        case .warm: return "sun.max.fill"
        case .cool: return "moon.fill"
        case .dark: return "moon.stars.fill"
        }
    }
}

// MARK: - Adaptive Color System

// Static accessors — reads stored theme from UserDefaults; views using @AppStorage re-render on theme change.

extension Color {
    static var backgroundColor: Color {
        let themeRaw = UserDefaults.standard.string(forKey: "theme") ?? AppTheme.system.rawValue
        let theme = AppTheme(rawValue: themeRaw) ?? .system
        return backgroundColor(for: theme)
    }

    static var surfaceColor: Color {
        let themeRaw = UserDefaults.standard.string(forKey: "theme") ?? AppTheme.system.rawValue
        let theme = AppTheme(rawValue: themeRaw) ?? .system
        return surfaceColor(for: theme)
    }

    static func backgroundColor(for theme: AppTheme) -> Color {
        switch theme {
        case .system:
            return Color(UIColor { traits in
                traits.userInterfaceStyle == .dark
                    ? UIColor(hex: "0D0D0F")
                    : UIColor(hex: "F2F2F7")
            })
        case .warm:
            return Color(UIColor(hex: "FBF8F3"))  // warm cream
        case .cool:
            return Color(UIColor(hex: "F0F4F8"))  // cool gray-blue
        case .dark:
            return Color(UIColor(hex: "0D0D0F"))  // premium dark
        }
    }

    static func surfaceColor(for theme: AppTheme) -> Color {
        switch theme {
        case .system:
            return Color(UIColor { traits in
                traits.userInterfaceStyle == .dark
                    ? UIColor(hex: "1C1C1E")
                    : UIColor.white
            })
        case .warm:
            return Color(UIColor(hex: "FFFDF9"))  // warm white
        case .cool:
            return Color(UIColor(hex: "FFFFFF"))  // crisp white
        case .dark:
            return Color(UIColor(hex: "1C1C1E"))
        }
    }

    static var appAccentColor: Color {
        let themeRaw = UserDefaults.standard.string(forKey: "theme") ?? AppTheme.system.rawValue
        let theme = AppTheme(rawValue: themeRaw) ?? .system
        return appAccentColor(for: theme)
    }

    static func appAccentColor(for theme: AppTheme) -> Color {
        switch theme {
        case .system:
            return .blue
        case .warm:
            return Color(UIColor(hex: "D4A373"))  // soft terracotta
        case .cool:
            return Color(UIColor(hex: "7E8EA8"))  // cool slate
        case .dark:
            return Color(UIColor(hex: "6B7280"))  // muted gray
        }
    }

    static var positiveColor: Color {
        let themeRaw = UserDefaults.standard.string(forKey: "theme") ?? AppTheme.system.rawValue
        let theme = AppTheme(rawValue: themeRaw) ?? .system
        return _positiveColor(for: theme)
    }

    static func _positiveColor(for theme: AppTheme) -> Color {
        switch theme {
        case .system:
            return .green
        case .warm:
            return Color(UIColor(hex: "81B29A"))  // sage green
        case .cool:
            return .green
        case .dark:
            return .green
        }
    }

    static var aiSummaryBadgeColor: Color {
        let themeRaw = UserDefaults.standard.string(forKey: "theme") ?? AppTheme.system.rawValue
        let theme = AppTheme(rawValue: themeRaw) ?? .system
        return aiSummaryBadgeColor(for: theme)
    }

    static func aiSummaryBadgeColor(for theme: AppTheme) -> Color {
        switch theme {
        case .system:
            return .orange
        case .warm:
            return Color(UIColor(hex: "E07A5F"))  // terracotta coral
        case .cool:
            return Color(UIColor(hex: "7E8EA8"))  // cool slate
        case .dark:
            return Color(UIColor(hex: "6B7280"))  // muted gray
        }
    }
}

// MARK: - Theme Environment Key

private struct ThemeKey: EnvironmentKey {
    static let defaultValue: AppTheme = .system
}

extension EnvironmentValues {
    var appTheme: AppTheme {
        get { self[ThemeKey.self] }
        set { self[ThemeKey.self] = newValue }
    }
}

extension View {
    func appTheme(_ theme: AppTheme) -> some View {
        environment(\.appTheme, theme)
    }
}

extension UIColor {
    convenience init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let r, g, b: UInt64
        switch hex.count {
        case 6: (r, g, b) = ((int >> 16) & 0xFF, (int >> 8) & 0xFF, int & 0xFF)
        default: (r, g, b) = (0, 0, 0)
        }
        self.init(red: CGFloat(r)/255, green: CGFloat(g)/255, blue: CGFloat(b)/255, alpha: 1)
    }
}