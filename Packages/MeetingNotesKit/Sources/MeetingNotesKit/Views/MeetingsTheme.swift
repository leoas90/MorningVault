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
    /// Highlights: the "You" speaker label, done checkmarks, confirmation text.
    public var accent: Color?
    /// Destructive / failed states.
    public var negative: Color?
    /// Corner radius of cards and banners.
    public var cardRadius: CGFloat

    public init(
        background: Color? = nil,
        surface: Color? = nil,
        accent: Color? = nil,
        negative: Color? = nil,
        cardRadius: CGFloat = 14
    ) {
        self.background = background
        self.surface = surface
        self.accent = accent
        self.negative = negative
        self.cardRadius = cardRadius
    }

    // Fallbacks used inside the package.
    var accentColor: Color { accent ?? .accentColor }
    var negativeColor: Color { negative ?? .red }
    var surfaceColor: Color { surface ?? Color.primary.opacity(0.04) }
    var backgroundColor: Color { background ?? Color.clear }
    var hasBackground: Bool { background != nil }
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

/// Page background that follows the host theme (no-op when the host set none).
struct ThemedPageBackground: ViewModifier {
    @Environment(\.meetingsTheme) private var theme

    func body(content: Content) -> some View {
        if theme.hasBackground {
            content.background(theme.backgroundColor.ignoresSafeArea())
        } else {
            content
        }
    }
}

/// A list row drawn as a card on the host's surface color. Rows keep swipe actions and
/// `onDelete` because they stay inside a `List`.
struct ThemedListRow: ViewModifier {
    @Environment(\.meetingsTheme) private var theme

    func body(content: Content) -> some View {
        content
            .listRowSeparator(.hidden)
            .listRowBackground(
                RoundedRectangle(cornerRadius: theme.cardRadius, style: .continuous)
                    .fill(theme.surfaceColor)
                    .padding(.vertical, 4)
            )
    }
}

/// Section header in the same voice as the host's cards: small, semibold, secondary.
struct ThemedSectionHeader: View {
    let title: String

    var body: some View {
        Text(title)
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(.secondary)
            .textCase(nil)
            .padding(.leading, 4)
    }
}

extension View {
    func themedPageBackground() -> some View { modifier(ThemedPageBackground()) }
    func themedListRow() -> some View { modifier(ThemedListRow()) }
}
