import SwiftUI
import BackgroundTasks
import Synchronization
import UserNotifications
import MeetingNotesKit

@main
struct MorningVaultApp: App {
    @Environment(\.scenePhase) private var scenePhase
    /// Observed in place: a theme or appearance change re-renders views that read the
    /// `Color.warm…` accessors, without rebuilding the tab view or losing navigation.
    private let themeStore = ThemeStore.shared

    private var currentTheme: AppTheme {
        themeStore.theme
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .onOpenURL { url in
                    handleDeepLink(url)
                }
                .appTheme(currentTheme)
                .preferredColorScheme(preferredColorScheme)
                .onChange(of: scenePhase) { _, newPhase in
                    if newPhase == .active {
                        // Refresh on foreground. Not `.viewBriefingRequested`: that one also
                        // switches to the Brief tab, which yanked users off Meetings/Settings.
                        NotificationCenter.default.post(name: .appBecameActive, object: nil)
                    }
                }
        }
    }

    private var preferredColorScheme: ColorScheme? {
        switch currentTheme {
        case .light: return .light
        case .dark: return .dark
        case .system: return nil
        }
    }

    init() {
        // Register notification delegate
        UNUserNotificationCenter.current().delegate = NotificationDelegate.shared

        // A natural-voice synthesis that never finished means it crashed: fall back on this OS.
        NaturalVoiceGuard.checkAfterLaunch()

        // Register BGTaskScheduler for 6:55 AM precomputation (nonisolated, see BackgroundRefresh)
        BackgroundRefresh.register()
        BackgroundRefresh.schedule()

        // The Live Activity's Stop button performs StopRecordingIntent in this process;
        // this is the only link from that intent to the recorder.
        RecordingStopBridge.stopAction = { await ActiveRecordingRegistry.shared.stop() }
    }

    // MARK: - Deep Link Handling

    private func handleDeepLink(_ url: URL) {
        // DEBUG: print("[MorningVaultApp] Deep link: \(url)")
        // morningvault://meetings[/record?event=…|/open?id=…] from the Meetings widget and
        // the recording Live Activity; ContentView switches tabs when the router is set.
        if MeetingsRouter.shared.handle(url: url) { return }
        if url.scheme == "morningvault" {
            NotificationCenter.default.post(name: .viewBriefingRequested, object: nil)
        }
    }

}

// MARK: - Background refresh

/// BGTaskScheduler runs the launch handler and the expiration handler on its own background
/// queue. Everything here is nonisolated: a closure written inside the `@MainActor` App struct
/// inherits main-actor isolation, and Swift 6 traps (`_dispatch_assert_queue_fail`) when such a
/// closure runs off the main thread. That was the build 47 crash at the 6:55 AM refresh.
enum BackgroundRefresh {
    static let taskID = "com.yeziddr.morningvault.precompute"

    nonisolated static func register() {
        BGTaskScheduler.shared.register(forTaskWithIdentifier: taskID, using: nil) { @Sendable task in
            handle(task)
        }
    }

    nonisolated private static func handle(_ task: BGTask) {
        schedule() // queue tomorrow's run first

        guard task is BGAppRefreshTask else {
            task.setTaskCompleted(success: false)
            return
        }

        // GATE 4 fix: respect localOnly, no network fetches in background when enabled.
        if UserDefaults.standard.bool(forKey: "local_only") {
            task.setTaskCompleted(success: true)
            return
        }

        let completion = BackgroundTaskCompletion(task)
        // One load only: generateBriefing() already does loadData(force: true).
        let work = Task { @MainActor in
            let viewModel = BriefingViewModel()
            await viewModel.generateBriefing()
            completion.finish(success: !Task.isCancelled)
        }
        // iOS cuts app-refresh tasks at ~30 s; stop touching the model once it does.
        task.expirationHandler = { @Sendable in
            work.cancel()
            completion.finish(success: false)
        }
    }

    nonisolated static func schedule() {
        // Hour/minute only. With year/month/day pinned to today, `nextDate` found nothing
        // once 6:55 had passed, so no refresh was ever scheduled for tomorrow.
        let components = DateComponents(hour: 6, minute: 55)
        guard let next6_55 = Calendar.current.nextDate(after: Date(), matching: components, matchingPolicy: .nextTime) else { return }

        let request = BGAppRefreshTaskRequest(identifier: taskID)
        request.earliestBeginDate = next6_55
        try? BGTaskScheduler.shared.submit(request)
    }
}

/// Reports a BGTask's completion exactly once, from whichever thread gets there first
/// (the main-actor work or the scheduler's expiration handler).
final class BackgroundTaskCompletion: Sendable {
    // BGTask is not marked Sendable, but setTaskCompleted(success:) is documented as callable
    // from any thread; the mutex guarantees it is called once.
    nonisolated(unsafe) private let task: BGTask
    private let done = Mutex(false)

    init(_ task: BGTask) { self.task = task }

    nonisolated func finish(success: Bool) {
        let first = done.withLock { finished in
            defer { finished = true }
            return !finished
        }
        if first { task.setTaskCompleted(success: success) }
    }
}

// MARK: - Notification Delegate (for deep-link on tap)

/// Sendable: it holds no state at all — each callback just posts a Notification.
final class NotificationDelegate: NSObject, UNUserNotificationCenterDelegate, Sendable {
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
    /// Deep link / notification tap: switch to the Brief tab and refresh.
    static let viewBriefingRequested = Notification.Name("viewBriefingRequested")
    /// Scene became active: refresh in place.
    static let appBecameActive = Notification.Name("appBecameActive")
    /// Units setting changed: rebuild the briefing text.
    static let unitsChanged = Notification.Name("unitsChanged")
}

// MARK: - Theme System

enum AppTheme: String, CaseIterable, Identifiable {
    case system
    case light
    case dark

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .system: return "System"
        case .light: return "Light"
        case .dark: return "Dark"
        }
    }

    var icon: String {
        switch self {
        case .system: return "circle.lefthalf.filled"
        case .light: return "sun.max.fill"
        case .dark: return "moon.stars.fill"
        }
    }
}

enum ColorAppearance: String, CaseIterable, Identifiable {
    case cool
    case warm
    case calm

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .cool: return "Cool"
        case .warm: return "Warm"
        case .calm: return "Calm"
        }
    }

    var icon: String {
        switch self {
        case .cool: return "snowflake"
        case .warm: return "sun.max.fill"
        case .calm: return "leaf.fill"
        }
    }
}

// MARK: - Adaptive Color System

// Static accessors — read `ThemeStore.shared`, which is @Observable, so any view body that
// uses them re-renders in place when the theme or appearance changes.

extension Color {
    @MainActor static var backgroundColor: Color {
        let theme = ThemeStore.shared.theme
        return backgroundColor(for: theme)
    }

    @MainActor static var surfaceColor: Color {
        let theme = ThemeStore.shared.theme
        return surfaceColor(for: theme)
    }

    @MainActor static func backgroundColor(for theme: AppTheme) -> Color {
        let appearance = ThemeStore.shared.appearance
        switch theme {
        case .system:
            return Color(UIColor.dynamic(
                light: appearance == .warm ? UIColor(hex: "FBF8F3") : (appearance == .cool ? UIColor(hex: "F0F4F8") : UIColor(hex: "F5F7F5")),
                dark: UIColor(hex: "0D0D0F")))
        case .light:
            if appearance == .warm {
                return Color(UIColor(hex: "FBF8F3"))
            } else if appearance == .cool {
                return Color(UIColor(hex: "F0F4F8"))
            } else {
                return Color(UIColor(hex: "F5F7F5"))  // calm sage green tint
            }
        case .dark:
            return Color(UIColor(hex: "0D0D0F"))  // premium dark
        }
    }

    @MainActor static func surfaceColor(for theme: AppTheme) -> Color {
        let appearance = ThemeStore.shared.appearance
        switch theme {
        case .system:
            return Color(UIColor.dynamic(
                light: appearance == .warm ? UIColor(hex: "FFFDF9") : (appearance == .cool ? UIColor(hex: "FFFFFF") : UIColor(hex: "FAFCFA")),
                dark: UIColor(hex: "1C1C1E")))
        case .light:
            if appearance == .warm {
                return Color(UIColor(hex: "FFFDF9"))
            } else if appearance == .cool {
                return Color(UIColor(hex: "FFFFFF"))
            } else {
                return Color(UIColor(hex: "FAFCFA"))  // calm off-white
            }
        case .dark:
            return Color(UIColor(hex: "1C1C1E"))
        }
    }

    @MainActor static var appAccentColor: Color {
        let theme = ThemeStore.shared.theme
        return appAccentColor(for: theme)
    }

    @MainActor static func appAccentColor(for theme: AppTheme) -> Color {
        let appearance = ThemeStore.shared.appearance
        switch theme {
        case .system:
            if appearance == .warm {
                return Color(UIColor(hex: "D4A373"))
            } else if appearance == .cool {
                return Color(UIColor(hex: "7E8EA8"))
            } else {
                return Color(UIColor(hex: "81B29A"))
            }
        case .light:
            if appearance == .warm {
                return Color(UIColor(hex: "D4A373"))
            } else if appearance == .cool {
                return Color(UIColor(hex: "7E8EA8"))
            } else {
                return Color(UIColor(hex: "81B29A"))  // calm sage green
            }
        case .dark:
            return Color(UIColor(hex: "6B7280"))  // muted gray
        }
    }

    @MainActor static var positiveColor: Color {
        let theme = ThemeStore.shared.theme
        return _positiveColor(for: theme)
    }

    @MainActor static func _positiveColor(for theme: AppTheme) -> Color {
        let appearance = ThemeStore.shared.appearance
        switch theme {
        case .system:
            return appearance == .calm ? Color(UIColor(hex: "81B29A")) : .green
        case .light:
            if appearance == .warm {
                return Color(UIColor(hex: "81B29A"))
            } else if appearance == .cool {
                return .green
            } else {
                return Color(UIColor(hex: "81B29A"))  // calm sage
            }
        case .dark:
            return .green
        }
    }

    /// Down moves and bearish badges. Distinct from the accent in every appearance, and a
    /// clearly red hue in Dark so "down" never looks like "neutral".
    @MainActor static var negativeColor: Color {
        let theme = ThemeStore.shared.theme
        let appearance = ThemeStore.shared.appearance
        let light: UIColor
        switch appearance {
        case .warm: light = UIColor(hex: "C8553D")   // terracotta red
        case .cool: light = UIColor(hex: "C0392B")   // cool crimson
        case .calm: light = UIColor(hex: "B5564B")   // muted brick
        }
        let dark = UIColor(hex: "FF6B6B")            // readable red on the dark surface
        switch theme {
        case .system:
            return Color(UIColor.dynamic(light: light, dark: dark))
        case .light:
            return Color(light)
        case .dark:
            return Color(dark)
        }
    }

    @MainActor static var aiSummaryBadgeColor: Color {
        let theme = ThemeStore.shared.theme
        return aiSummaryBadgeColor(for: theme)
    }

    @MainActor static func aiSummaryBadgeColor(for theme: AppTheme) -> Color {
        let appearance = ThemeStore.shared.appearance
        switch theme {
        case .system:
            return appearance == .warm ? Color(UIColor(hex: "E07A5F")) : Color(UIColor(hex: "7E8EA8"))
        case .light:
            if appearance == .warm {
                return Color(UIColor(hex: "E07A5F"))
            } else if appearance == .cool {
                return Color(UIColor(hex: "7E8EA8"))
            } else {
                return Color(UIColor(hex: "81B29A"))  // calm green
            }
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
    /// Trait-dependent color whose provider is nonisolated. SwiftUI resolves colors on its
    /// async render thread; a provider closure formed inside a @MainActor getter inherits
    /// main-actor isolation and traps there under Swift 6 (builds 45/46 crash).
    nonisolated static func dynamic(light: UIColor, dark: UIColor) -> UIColor {
        UIColor { @Sendable traits in traits.userInterfaceStyle == .dark ? dark : light }
    }

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