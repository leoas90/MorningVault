import Foundation
import Observation

/// The Theme (System/Light/Dark) and Appearance (Warm/Cool/Calm) settings as one observable
/// object. The `Color.warm…` accessors read it, so a view body that uses them is tracked and
/// re-renders in place when either value changes — no `.id()` rebuild, no lost tab or
/// navigation state. Values persist under the same UserDefaults keys as before.
@MainActor
@Observable
final class ThemeStore {
    static let shared = ThemeStore()

    static let themeKey = "theme"
    static let appearanceKey = "appearance"

    var themeRaw: String {
        didSet { UserDefaults.standard.set(themeRaw, forKey: Self.themeKey) }
    }

    var appearanceRaw: String {
        didSet { UserDefaults.standard.set(appearanceRaw, forKey: Self.appearanceKey) }
    }

    var theme: AppTheme { AppTheme(rawValue: themeRaw) ?? .system }
    var appearance: ColorAppearance { ColorAppearance(rawValue: appearanceRaw) ?? .warm }

    private init() {
        themeRaw = UserDefaults.standard.string(forKey: Self.themeKey) ?? AppTheme.system.rawValue
        appearanceRaw = UserDefaults.standard.string(forKey: Self.appearanceKey) ?? ColorAppearance.warm.rawValue
    }
}
