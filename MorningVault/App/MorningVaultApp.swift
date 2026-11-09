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

        // Water logs go to Health from the app; the widget's logs sync on the next load.
        Task { await WaterStore.shared.configure(health: HealthKitWaterClient()) }
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
            if Calendar.current.component(.hour, from: Date()) >= 19 {
                // The 8 pm run only precomputes tomorrow's calendar suggestions.
                await SuggestionEngine.refreshCacheForNow()
            } else {
                let viewModel = BriefingViewModel()
                await viewModel.generateBriefing()
            }
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
        // Two runs a day: 6:55 (the Brief) and 20:00 (tomorrow's calendar suggestions, when
        // the household checklist is on). Whichever comes first is queued.
        let now = Date()
        var candidates: [Date] = []
        if let morning = Calendar.current.nextDate(after: now, matching: DateComponents(hour: 6, minute: 55), matchingPolicy: .nextTime) {
            candidates.append(morning)
        }
        if BriefSectionPrefs.isHouseholdEnabled,
           let evening = Calendar.current.nextDate(after: now, matching: DateComponents(hour: 20, minute: 0), matchingPolicy: .nextTime) {
            candidates.append(evening)
        }
        guard let next = candidates.min() else { return }

        let request = BGAppRefreshTaskRequest(identifier: taskID)
        request.earliestBeginDate = next
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
        didReceive response: UNNotificationResponse
    ) async {
        // Timer and reminder actions write to the checklist store off the main actor.
        if await TrackerNotificationService.handle(response: response) { return }
        if response.notification.request.content.categoryIdentifier == "BRIEFING" {
            NotificationCenter.default.post(name: .viewBriefingRequested, object: nil)
        }
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
//
// Palette ("morning paper"): a paper background, a slightly lighter surface for cards, ink
// for text, and one saturated accent per appearance. Dark mode keeps the hue of each
// appearance (a warm black, a cool black, a green-black) and lifts the accent instead of
// greying it out.

/// Raw hex values per appearance. Light and dark are both listed so `.system` can build a
/// dynamic color and `.light`/`.dark` can pin one side.
struct AppPalette: Sendable {
    let backgroundLight: String
    let backgroundDark: String
    let surfaceLight: String
    let surfaceDark: String
    let accentLight: String
    let accentDark: String
    let positiveLight: String
    let positiveDark: String
    let negativeLight: String
    let negativeDark: String
    let inkLight: String
    let inkDark: String
    let inkSecondaryLight: String
    let inkSecondaryDark: String
    let separatorLight: String
    let separatorDark: String

    /// Contrast (WCAG, computed offline): every secondary ink is >= 5.1:1 on its surface and
    /// canvas; positive/negative >= 5.4:1 light / 5.9:1 dark; white on the warm light accent
    /// 4.5:1; dark canvas on the dark accents >= 8:1. Red/green are market semantics only
    /// and always travel with an arrow and a percentage.
    static func palette(for appearance: ColorAppearance) -> AppPalette {
        switch appearance {
        case .warm:
            return AppPalette(
                backgroundLight: "F6F2EC", backgroundDark: "17141B",
                surfaceLight: "FFFCF7", surfaceDark: "211C23",
                accentLight: "B85E24", accentDark: "E2A060",
                positiveLight: "16735D", positiveDark: "58BFA6",
                negativeLight: "B83A3A", negativeDark: "F07870",
                inkLight: "171615", inkDark: "F7F2EA",
                inkSecondaryLight: "66615B", inkSecondaryDark: "B8B0B7",
                separatorLight: "DDD7CF", separatorDark: "3A333C")
        case .cool:
            return AppPalette(
                backgroundLight: "EFF2F6", backgroundDark: "13161C",
                surfaceLight: "FAFBFD", surfaceDark: "1B1F27",
                accentLight: "35568A", accentDark: "8FB4EC",
                positiveLight: "16735D", positiveDark: "58BFA6",
                negativeLight: "B83A3A", negativeDark: "F07870",
                inkLight: "141518", inkDark: "EEF1F5",
                inkSecondaryLight: "5F6670", inkSecondaryDark: "AEB5BF",
                separatorLight: "D5DAE1", separatorDark: "343A44")
        case .calm:
            return AppPalette(
                backgroundLight: "F0F3EE", backgroundDark: "131A15",
                surfaceLight: "FAFCF9", surfaceDark: "1B221D",
                accentLight: "2F6E52", accentDark: "8AD3AC",
                positiveLight: "16735D", positiveDark: "58BFA6",
                negativeLight: "B83A3A", negativeDark: "F07870",
                inkLight: "121613", inkDark: "ECF1EC",
                inkSecondaryLight: "5E6660", inkSecondaryDark: "AAB6AD",
                separatorLight: "D6DDD4", separatorDark: "333C35")
        }
    }
}

extension Color {
    /// Resolves a light/dark hex pair against the Theme setting: `.system` follows the
    /// device, `.light`/`.dark` pin one side (so a forced theme never shows the other).
    @MainActor private static func themed(_ theme: AppTheme, light: String, dark: String) -> Color {
        switch theme {
        case .system: return Color(UIColor.dynamic(light: UIColor(hex: light), dark: UIColor(hex: dark)))
        case .light: return Color(UIColor(hex: light))
        case .dark: return Color(UIColor(hex: dark))
        }
    }

    @MainActor private static var currentPalette: AppPalette {
        AppPalette.palette(for: ThemeStore.shared.appearance)
    }

    @MainActor static var backgroundColor: Color {
        backgroundColor(for: ThemeStore.shared.theme)
    }

    @MainActor static var surfaceColor: Color {
        surfaceColor(for: ThemeStore.shared.theme)
    }

    @MainActor static func backgroundColor(for theme: AppTheme) -> Color {
        let p = currentPalette
        return themed(theme, light: p.backgroundLight, dark: p.backgroundDark)
    }

    @MainActor static func surfaceColor(for theme: AppTheme) -> Color {
        let p = currentPalette
        return themed(theme, light: p.surfaceLight, dark: p.surfaceDark)
    }

    @MainActor static var appAccentColor: Color {
        appAccentColor(for: ThemeStore.shared.theme)
    }

    @MainActor static func appAccentColor(for theme: AppTheme) -> Color {
        let p = currentPalette
        return themed(theme, light: p.accentLight, dark: p.accentDark)
    }

    @MainActor static var positiveColor: Color {
        _positiveColor(for: ThemeStore.shared.theme)
    }

    @MainActor static func _positiveColor(for theme: AppTheme) -> Color {
        let p = currentPalette
        return themed(theme, light: p.positiveLight, dark: p.positiveDark)
    }

    /// Down moves and bearish badges. Distinct from the accent in every appearance, and a
    /// clearly red hue in Dark so "down" never looks like "neutral".
    @MainActor static var negativeColor: Color {
        let p = currentPalette
        return themed(ThemeStore.shared.theme, light: p.negativeLight, dark: p.negativeDark)
    }

    /// Primary text ("ink"). Near-black on paper, warm off-white on the dark surface.
    @MainActor static var inkPrimary: Color {
        let p = currentPalette
        return themed(ThemeStore.shared.theme, light: p.inkLight, dark: p.inkDark)
    }

    /// Secondary text. Chosen to pass 4.5:1 on the surface color in both modes.
    @MainActor static var inkSecondary: Color {
        let p = currentPalette
        return themed(ThemeStore.shared.theme, light: p.inkSecondaryLight, dark: p.inkSecondaryDark)
    }

    /// Hairline rules and card borders: the opaque separator token (light #DDD7CF / dark #3A333C
    /// for Warm), so rules never shift with what is behind them.
    @MainActor static var hairline: Color {
        let p = currentPalette
        return themed(ThemeStore.shared.theme, light: p.separatorLight, dark: p.separatorDark)
    }

    /// L2 surface border. In dark the separator token (#3A333C) is ~8 % white over the surface.
    @MainActor static var surfaceBorder: Color { hairline }

    /// Text on an accent-filled control: white on the light accent, ink on the lighter dark
    /// accent (white on it fails contrast).
    @MainActor static var onAccent: Color {
        let p = currentPalette
        return themed(ThemeStore.shared.theme, light: "FFFFFF", dark: p.backgroundDark)
    }

    @MainActor static var aiSummaryBadgeColor: Color {
        aiSummaryBadgeColor(for: ThemeStore.shared.theme)
    }

    @MainActor static func aiSummaryBadgeColor(for theme: AppTheme) -> Color {
        appAccentColor(for: theme)
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