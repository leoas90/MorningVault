import SwiftUI

/// Colors the host app hands to the Meetings screens so they match the rest of the app.
///
/// Every value is optional: when the host sets nothing, the screens use system colors, so
/// the package carries no brand colors of its own. MorningVault sets it from `ContentView`
/// (`.meetingsTheme(...)`) with its warm/cool/calm palette.
public struct MeetingsTheme: Equatable, Sendable {
    /// Page background behind lists and scroll views.
    public var background: Color?
    /// Card and banner fill.
    public var surface: Color?
    /// The one accent: the Record button, active states, the "You" speaker, done checks.
    public var accent: Color?
    /// Destructive / failed states and the Stop control.
    public var negative: Color?
    /// Corner radius of banners and functional cards.
    public var cardRadius: CGFloat
    /// Primary text ink. Falls back to the system primary label color.
    public var inkPrimary: Color?
    /// Secondary text ink: meta lines, eyebrows, captions.
    public var inkSecondary: Color?
    /// 1 pt rules between rows and around cards in dark mode.
    public var hairline: Color?
    /// Success states (saved, enrolled).
    public var positive: Color?
    /// Text drawn on top of the accent (the Record button label).
    public var onAccent: Color?

    public init(
        background: Color? = nil,
        surface: Color? = nil,
        accent: Color? = nil,
        negative: Color? = nil,
        cardRadius: CGFloat = 20,
        inkPrimary: Color? = nil,
        inkSecondary: Color? = nil,
        hairline: Color? = nil,
        positive: Color? = nil,
        onAccent: Color? = nil
    ) {
        self.background = background
        self.surface = surface
        self.accent = accent
        self.negative = negative
        self.cardRadius = cardRadius
        self.inkPrimary = inkPrimary
        self.inkSecondary = inkSecondary
        self.hairline = hairline
        self.positive = positive
        self.onAccent = onAccent
    }

    // Fallbacks used inside the package.
    var accentColor: Color { accent ?? .accentColor }
    var negativeColor: Color { negative ?? .red }
    var positiveColor: Color { positive ?? .green }
    var surfaceColor: Color { surface ?? Color.primary.opacity(0.04) }
    var backgroundColor: Color { background ?? Color.clear }
    var hasBackground: Bool { background != nil }
    var ink: Color { inkPrimary ?? .primary }
    /// Secondary ink. The fallback is the primary label at 62 %, not `.secondary`: the
    /// system secondary label is 3.4:1 on white, this is 6.2:1 in light and 7.8:1 in dark,
    /// so eyebrows and meta lines pass 4.5:1 without a host palette.
    var inkSoft: Color { inkSecondary ?? Color.primary.opacity(0.62) }
    var hairlineColor: Color { hairline ?? Color.primary.opacity(0.10) }
    var onAccentColor: Color { onAccent ?? .white }
    /// 6 % accent wash for pills and strips.
    var accentWash: Color { accentColor.opacity(0.06) }
    /// Radius of the one primary card on a screen.
    var primaryRadius: CGFloat { 28 }
    /// Radius of secondary, functional cards.
    var functionalRadius: CGFloat { min(cardRadius, 20) }
}

private struct MeetingsThemeKey: EnvironmentKey {
    static let defaultValue = MeetingsTheme()
}

public extension EnvironmentValues {
    var meetingsTheme: MeetingsTheme {
        get { self[MeetingsThemeKey.self] }
        set { self[MeetingsThemeKey.self] = newValue }
    }
}

public extension View {
    /// Hands the host's colors to every Meetings screen below this view.
    func meetingsTheme(_ theme: MeetingsTheme) -> some View {
        environment(\.meetingsTheme, theme)
    }
}

// MARK: - Type scale

/// The Meetings type scale. New York serif is reserved for page titles and one hero line
/// per screen; everything else is SF Pro.
enum MeetingsType {
    /// 34 pt serif semibold page title.
    static var pageTitle: Font { .system(size: 34, weight: .semibold, design: .serif) }
    /// 28 pt serif meeting title on the detail screen.
    static var meetingTitle: Font { .system(size: 28, weight: .semibold, design: .serif) }
    /// 56 pt serif hero timer.
    static var heroTimer: Font { .system(size: 56, weight: .medium, design: .serif).monospacedDigit() }
    /// Body 17/25.
    static var body: Font { .system(size: 17, weight: .regular) }
    /// Secondary 15/21.
    static var secondary: Font { .system(size: 15, weight: .regular) }
    /// Row title 16/22 semibold.
    static var rowTitle: Font { .system(size: 16, weight: .semibold) }
    /// Meta 13/17.
    static var meta: Font { .system(size: 13, weight: .regular) }
    /// Meta, medium weight, for pills and timestamps.
    static var metaMedium: Font { .system(size: 13, weight: .medium) }
    /// Monospaced 13 pt for timestamps.
    static var metaMono: Font { .system(size: 13, weight: .regular, design: .monospaced) }
    /// Eyebrow 11 pt semibold, uppercased by the view.
    static var eyebrow: Font { .system(size: 11, weight: .semibold) }
    /// Button labels 17 semibold.
    static var button: Font { .system(size: 17, weight: .semibold) }
    /// 16–18 pt medium symbols.
    static var symbol: Font { .system(size: 17, weight: .medium) }
}

/// Spacing on a 4 pt grid.
enum MeetingsSpace {
    static let margin: CGFloat = 20
    static let cardGap: CGFloat = 16
    static let sectionGap: CGFloat = 28
    static let label: CGFloat = 8
    static let control: CGFloat = 52
    static let target: CGFloat = 44
}

/// Page background that follows the host theme.
struct ThemedPageBackground: ViewModifier {
    @Environment(\.meetingsTheme) private var theme

    func body(content: Content) -> some View {
        content.background(theme.backgroundColor.ignoresSafeArea())
    }
}

extension View {
    func themedPageBackground() -> some View { modifier(ThemedPageBackground()) }
}
