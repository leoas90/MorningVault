import Foundation

/// Which sections of the Brief the user wants, plus how many headlines to show.
///
/// The Settings toggles write `UserDefaults.standard` (so `@AppStorage` drives them); the
/// app mirrors the values into the App Group so the widget and the Siri / Shortcuts
/// actions, which run in their own processes, make the same choice. A turned-off section
/// is left out of the Brief, the widget, the shared snapshot and the spoken brief, no matter
/// which template is picked: the toggle wins.
///
/// Compiled into the app and the widget extension (project.yml adds MorningVault/Shared to
/// both), so it stays Foundation-only.
enum BriefSectionPrefs {
    static let appGroup = "group.com.morningvault.app"

    /// Layout sections with their own toggle under Settings > Brief sections.
    enum Key {
        static let summary = "section_summary_enabled"
        static let next = "section_next_enabled"
        static let changes = "section_changes_enabled"
        static let markets = "section_markets_enabled"
        static let headlineCount = "headline_count"
    }

    /// Section id -> defaults key. Data sources keep their older `<id>_enabled` keys.
    private static let keys: [String: String] = [
        "summary": Key.summary,
        "next": Key.next,
        "changes": Key.changes,
        "markets": Key.markets,
        "health": "health_enabled",
        "calendar": "calendar_enabled",
        "weather": "weather_enabled",
        "headlines": "headlines_enabled",
    ]

    private static let mirroredKeys: [String] = [
        Key.summary, Key.next, Key.changes, Key.markets, Key.headlineCount,
        "health_enabled", "calendar_enabled", "weather_enabled", "headlines_enabled",
    ]

    /// Headline counts offered in Settings.
    static let headlineCountChoices = [3, 5, 8, 10]
    static let defaultHeadlineCount = 5

    /// True when the section is on. Unknown ids are on. Reads the standard defaults first
    /// (the source of truth in the app), then the App Group mirror (what an extension sees).
    static func isEnabled(_ id: String) -> Bool {
        guard let key = keys[id] else { return true }
        if let value = value(forKey: key) as? Bool { return value }
        return true
    }

    /// Headlines in the Brief, 3 to 10 (default 5). Zero when headlines are off.
    static var headlineCount: Int {
        guard isEnabled("headlines") else { return 0 }
        guard let n = value(forKey: Key.headlineCount) as? Int, headlineCountChoices.contains(n) else {
            return defaultHeadlineCount
        }
        return n
    }

    /// Copies the standard-defaults values into the App Group so extensions see them.
    static func mirrorToAppGroup() {
        guard let group = UserDefaults(suiteName: appGroup) else { return }
        for key in mirroredKeys {
            if let v = UserDefaults.standard.object(forKey: key) {
                group.set(v, forKey: key)
            } else {
                group.removeObject(forKey: key)
            }
        }
    }

    private static func value(forKey key: String) -> Any? {
        if let v = UserDefaults.standard.object(forKey: key) { return v }
        return UserDefaults(suiteName: appGroup)?.object(forKey: key)
    }
}
