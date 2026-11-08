import SwiftUI

// MARK: - Editorial design system
//
// "Calm morning paper": paper background, ink text, serif display type, one accent.
// Everything here is presentational and reads the theme through `Color.ink…`/`warm…`,
// so a Theme or Palette change re-renders in place.

// MARK: Type

// Type scale. Serif (New York) is reserved for three things: the temperature numeral, the
// greeting (34/40 semibold) and the Markets / Settings page titles (34 semibold). Everything
// else is SF Pro: lede 20/26, body 17/25, secondary 15/21, agenda title 16/22 semibold,
// metric value 15/20 medium, market quote 30/34 medium tabular, delta 13/16 semibold,
// section label 11/14 semibold uppercase tracking 0.8. Nothing meaningful below 12 pt.
extension Font {
    /// Display serif (New York): greeting, temperature numeral, page titles.
    static func display(_ size: CGFloat, weight: Font.Weight = .medium) -> Font {
        .system(size: size, weight: weight, design: .serif)
    }

    /// "Good morning, Yezid." — 34/40 serif semibold, two lines at most.
    static var greeting: Font { .system(size: 34, weight: .semibold, design: .serif) }
    /// Page titles on Markets / Settings.
    static var pageTitle: Font { .system(size: 34, weight: .semibold, design: .serif) }
    /// The one synthesis sentence under the greeting (SF, not serif).
    static var lede: Font { .system(size: 20, weight: .regular) }
    static var bodyText: Font { .system(size: 17, weight: .regular) }
    static var secondaryText: Font { .system(size: 15, weight: .regular) }
    static var metaText: Font { .system(size: 13, weight: .regular) }
    static var agendaTitle: Font { .system(size: 16, weight: .semibold) }
    static var metricValue: Font { .system(size: 15, weight: .medium).monospacedDigit() }
    static var marketQuote: Font { .system(size: 30, weight: .medium).monospacedDigit() }
    static var delta: Font { .system(size: 13, weight: .semibold).monospacedDigit() }
    static var sectionLabel: Font { .system(size: 11, weight: .semibold) }
    /// 15 pt medium: toolbar text buttons, "Change entry price", disclosure rows.
    static var control: Font { .system(size: 15, weight: .medium) }
}

/// Line spacing to reach the scale's line heights (SwiftUI's `lineSpacing` is extra leading).
enum Leading {
    static let greeting: CGFloat = 2    // 34 → 40
    static let lede: CGFloat = 3        // 20 → 26
    static let body: CGFloat = 4        // 17 → 25
    static let secondary: CGFloat = 3   // 15 → 21
}

/// 4-pt grid. Horizontal margin 20; card-to-card 16; section-to-section 28; label-to-content
/// 8–12; greeting-to-lede 8; lede-to-agenda 28; agenda row 52–56; field / button height 52.
enum Grid4 {
    static let margin: CGFloat = 20
    static let card: CGFloat = 16
    static let section: CGFloat = 28
    static let label: CGFloat = 10
    static let greetingToLede: CGFloat = 8
    static let agendaRow: CGFloat = 52
    static let timeColumn: CGFloat = 72
    static let control: CGFloat = 52
}

/// Section label: "MARKETS", "NEXT", "SATURDAY, NOVEMBER 8". 11/14 semibold uppercase, tracking 0.8.
struct Eyebrow: View {
    let text: String
    var color: Color? = nil

    var body: some View {
        Text(text)
            .font(.sectionLabel)
            .textCase(.uppercase)
            .tracking(0.8)
            .foregroundStyle(color ?? Color.inkSecondary)
    }
}

/// Pressed controls scale to 0.98; a plain fade under Reduce Motion.
struct PressableButtonStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.98 : 1)
            .opacity(configuration.isPressed ? 0.85 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

extension ButtonStyle where Self == PressableButtonStyle {
    static var pressable: PressableButtonStyle { PressableButtonStyle() }
}

/// One-shot entrance: fade + 6 pt rise after `delay`, driven by `withAnimation` only (never
/// `.animation(value:)`, which would also animate the first layout pass). Reduce Motion: a
/// 200 ms fade with no drift.
struct EntranceModifier: ViewModifier {
    var delay: Double
    var rise: CGFloat = 6
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var shown = false

    func body(content: Content) -> some View {
        content
            .opacity(shown ? 1 : 0)
            .offset(y: shown || reduceMotion ? 0 : rise)
            .onAppear {
                guard !shown else { return }
                if reduceMotion {
                    withAnimation(.easeOut(duration: 0.2)) { shown = true }
                } else {
                    withAnimation(.easeOut(duration: 0.35).delay(delay)) { shown = true }
                }
            }
    }
}

extension View {
    func entrance(delay: Double, rise: CGFloat = 6) -> some View {
        modifier(EntranceModifier(delay: delay, rise: rise))
    }
}

/// Dark-mode surfaces take a 4 % tint of the current sky so the page reads as one environment.
private struct SkyTintKey: EnvironmentKey {
    static let defaultValue: Color? = nil
}

extension EnvironmentValues {
    var skyTint: Color? {
        get { self[SkyTintKey.self] }
        set { self[SkyTintKey.self] = newValue }
    }
}

// MARK: Card

/// Depth model, three levels: L0 the canvas; L1 the hero card; L2 one functional surface
/// (radius 20, padding 16, black 5 % shadow r12 y4 in light; hairline border, no shadow, in
/// dark). Nothing else gets a card. `editorialCard()` is the L2 treatment.
struct EditorialCardModifier: ViewModifier {
    @Environment(\.colorScheme) private var colorScheme
    var padding: CGFloat = 16

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: AppRadius.card, style: .continuous)
        content
            .padding(padding)
            .background(shape.fill(Color.surfaceColor))
            .overlay(shape.strokeBorder(Color.surfaceBorder, lineWidth: 1))
            .shadow(color: Color.black.opacity(colorScheme == .dark ? 0 : 0.05), radius: 12, x: 0, y: 4)
    }
}

extension View {
    func editorialCard(padding: CGFloat = 16) -> some View {
        modifier(EditorialCardModifier(padding: padding))
    }
}

/// 1 pt rule in the separator token.
struct Hairline: View {
    var color: Color? = nil
    var body: some View {
        Rectangle()
            .fill(color ?? Color.hairline)
            .frame(height: 1)
    }
}

/// Filled accent control, 52 pt tall, radius 12; disabled at 40 % opacity.
struct PrimaryButton: View {
    let title: String
    var systemImage: String? = nil
    var isEnabled: Bool = true
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                if let systemImage {
                    Image(systemName: systemImage).font(.system(size: 16, weight: .medium))
                }
                Text(title).font(.system(size: 17, weight: .semibold))
            }
            .foregroundStyle(Color.onAccent)
            .frame(maxWidth: .infinity)
            .frame(height: Grid4.control)
            .background(Color.appAccentColor, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(.pressable)
        .disabled(!isEnabled)
        .opacity(isEnabled ? 1 : 0.4)
    }
}

/// 52 pt text field, radius 12, hairline at rest and a 2 pt accent ring when focused.
struct FormField<Content: View>: View {
    var isFocused: Bool
    @ViewBuilder var content: () -> Content

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 12, style: .continuous)
        content()
            .font(.bodyText)
            .foregroundStyle(Color.inkPrimary)
            .padding(.horizontal, 14)
            .frame(height: Grid4.control)
            .background(shape.fill(Color.surfaceColor))
            .overlay(shape.strokeBorder(isFocused ? Color.appAccentColor : Color.hairline, lineWidth: isFocused ? 2 : 1))
            .animation(.easeOut(duration: 0.15), value: isFocused)
    }
}

// MARK: Pills

/// Pill action button ("Listen" is the one accent-coloured control on the Brief).
struct PillButton: View {
    let title: String
    let systemImage: String
    var prominent: Bool = false
    var isActive: Bool = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: systemImage)
                    .font(.system(size: 15, weight: .medium))
                    .symbolRenderingMode(.hierarchical)
                    .symbolEffect(.variableColor.iterative, isActive: isActive)
                Text(title)
                    .font(.system(size: 15, weight: .semibold))
            }
            .lineLimit(1)
            .padding(.horizontal, 16)
            .frame(minHeight: 40)
            .foregroundStyle(prominent ? Color.onAccent : Color.inkPrimary)
            .background(prominent ? Color.appAccentColor : Color.surfaceColor, in: Capsule())
            .overlay(Capsule().strokeBorder(prominent ? Color.clear : Color.hairline, lineWidth: 1))
        }
        .buttonStyle(.pressable)
    }
}

/// Neutral 17 pt-medium symbol in a 44×44 target (Share, Edit, Add…); never accent-coloured.
struct IconButton: View {
    let systemImage: String
    let label: String
    var tint: Color? = nil
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 17, weight: .medium))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(tint ?? Color.inkPrimary)
                .frame(width: 44, height: 44)
                .contentShape(Circle())
        }
        .buttonStyle(.pressable)
        .accessibilityLabel(label)
    }
}

// MARK: Time-of-day gradient

/// Background wash for the hero. Hour buckets: pre-dawn, sunrise, day, dusk.
struct TimeOfDayGradient: View {
    @Environment(\.colorScheme) private var colorScheme
    var hour: Int = Calendar.current.component(.hour, from: Date())

    private var colors: [Color] {
        let light: [Color]
        let dark: [Color]
        switch hour {
        case 0..<6:
            light = [Color(hex: "3B3561"), Color(hex: "6B4E71")]
            dark = [Color(hex: "1A1830"), Color(hex: "2A1E33")]
        case 6..<10:
            light = [Color(hex: "F6C9A8"), Color(hex: "F2D9A0")]
            dark = [Color(hex: "3A2A22"), Color(hex: "2E2518")]
        case 10..<17:
            light = [Color(hex: "D9E6F2"), Color(hex: "F3EEE4")]
            dark = [Color(hex: "1C2430"), Color(hex: "19191C")]
        default:
            light = [Color(hex: "E8A96B"), Color(hex: "4A4068")]
            dark = [Color(hex: "33241E"), Color(hex: "1C1B2E")]
        }
        return colorScheme == .dark ? dark : light
    }

    /// Pre-dawn and dusk use light text; the day/sunrise washes use ink. The sky scene
    /// resolves the same question with the weather folded in.
    static func usesLightText(hour: Int, colorScheme: ColorScheme, condition: String? = nil) -> Bool {
        SkyStyle.resolve(hour: hour, condition: condition, colorScheme: colorScheme).usesLightText
    }

    var body: some View {
        LinearGradient(colors: colors, startPoint: .top, endPoint: .bottom)
    }
}

// MARK: Shimmer / skeleton

struct ShimmerModifier: ViewModifier {
    @State private var phase: CGFloat = -0.4

    func body(content: Content) -> some View {
        content
            .overlay {
                GeometryReader { proxy in
                    LinearGradient(
                        colors: [.clear, Color.white.opacity(0.35), .clear],
                        startPoint: .leading, endPoint: .trailing
                    )
                    .frame(width: proxy.size.width * 0.6)
                    .offset(x: phase * proxy.size.width * 1.6)
                }
                .blendMode(.plusLighter)
            }
            .clipped()
            .onAppear {
                guard !UIAccessibility.isReduceMotionEnabled else { return }
                withAnimation(.linear(duration: 1.4).repeatForever(autoreverses: false)) {
                    phase = 1
                }
            }
    }
}

extension View {
    func shimmer() -> some View { modifier(ShimmerModifier()) }
}

/// One grey placeholder line.
struct SkeletonLine: View {
    var width: CGFloat? = nil
    var height: CGFloat = 12

    var body: some View {
        RoundedRectangle(cornerRadius: height / 2, style: .continuous)
            .fill(Color.inkPrimary.opacity(0.10))
            .frame(width: width, height: height)
            .frame(maxWidth: width == nil ? .infinity : nil, alignment: .leading)
            .shimmer()
    }
}

// MARK: Flow layout

/// Wrapping row layout for chips; items never break mid-word because each chip keeps its
/// ideal width.
struct FlowLayout: Layout {
    var spacing: CGFloat = 8
    var alignment: HorizontalAlignment = .center

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        let rows = computeRows(maxWidth: maxWidth, subviews: subviews)
        let height = rows.reduce(0) { $0 + $1.height } + CGFloat(max(rows.count - 1, 0)) * spacing
        let width = rows.map(\.width).max() ?? 0
        return CGSize(width: proposal.width ?? width, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let rows = computeRows(maxWidth: bounds.width, subviews: subviews)
        var y = bounds.minY
        for row in rows {
            var x: CGFloat
            switch alignment {
            case .leading: x = bounds.minX
            case .trailing: x = bounds.maxX - row.width
            default: x = bounds.minX + (bounds.width - row.width) / 2
            }
            for index in row.indices {
                let size = subviews[index].sizeThatFits(.unspecified)
                subviews[index].place(at: CGPoint(x: x, y: y + (row.height - size.height) / 2),
                                      proposal: ProposedViewSize(size))
                x += size.width + spacing
            }
            y += row.height + spacing
        }
    }

    private struct Row {
        var indices: [Int] = []
        var width: CGFloat = 0
        var height: CGFloat = 0
    }

    private func computeRows(maxWidth: CGFloat, subviews: Subviews) -> [Row] {
        var rows: [Row] = []
        var current = Row()
        for (index, subview) in subviews.enumerated() {
            let size = subview.sizeThatFits(.unspecified)
            let needed = current.indices.isEmpty ? size.width : current.width + spacing + size.width
            if needed > maxWidth, !current.indices.isEmpty {
                rows.append(current)
                current = Row()
            }
            current.indices.append(index)
            current.width = current.indices.count == 1 ? size.width : current.width + spacing + size.width
            current.height = max(current.height, size.height)
        }
        if !current.indices.isEmpty { rows.append(current) }
        return rows
    }
}

// MARK: Formatting helpers

enum EditorialFormat {
    /// "SATURDAY, NOVEMBER 8" (cased by the Eyebrow view).
    static func dateEyebrow(_ date: Date = Date()) -> String {
        let f = DateFormatter()
        f.setLocalizedDateFormatFromTemplate("EEEEMMMMd")
        return f.string(from: date)
    }

    /// Price with thousands grouping; crypto at or above $1,000 drops the cents.
    static func price(symbol: String, _ value: Double) -> String {
        let crypto: Set<String> = ["BTC", "ETH", "SOL", "BNB", "XRP", "ADA", "DOGE", "DOT", "AVAX", "LINK"]
        let digits = (crypto.contains(symbol.uppercased()) && value >= 1000) ? 0 : 2
        return "$" + value.formatted(.number.precision(.fractionLength(digits)).grouping(.automatic))
    }

    static func time(_ date: Date) -> String {
        date.formatted(date: .omitted, time: .shortened)
    }

    /// First sentence (the lede) and the remainder, split on sentence punctuation.
    static func splitLede(_ text: String) -> (lede: String, rest: String?) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let m = try? #/^(.+?[.!?])\s+(\S.*)$/#.dotMatchesNewlines().firstMatch(in: trimmed) else {
            return (trimmed, nil)
        }
        let rest = String(m.2).trimmingCharacters(in: .whitespacesAndNewlines)
        return (String(m.1), rest.isEmpty ? nil : rest)
    }
}

// MARK: Schedule (Next block)

/// Upcoming vs. earlier events relative to a clock, from the "9:00 AM — Standup" lines.
/// Previews pass a fixed `now`; the app passes `Date()`.
struct BriefSchedule {
    let upcoming: [CalendarLine]
    let earlier: [CalendarLine]

    static func make(from events: [CalendarLine], now: Date, calendar: Calendar = .current) -> BriefSchedule {
        var upcoming: [CalendarLine] = []
        var earlier: [CalendarLine] = []
        for event in events {
            if let start = startDate(of: event.time, on: now, calendar: calendar), start < now {
                earlier.append(event)
            } else {
                upcoming.append(event)
            }
        }
        return BriefSchedule(upcoming: upcoming, earlier: earlier)
    }

    /// "9:00 AM" / "09:00" / "9 AM" → today at that time. Anything unparseable counts as upcoming.
    static func startDate(of time: String, on day: Date, calendar: Calendar = .current) -> Date? {
        let t = time.uppercased().replacingOccurrences(of: "\u{202F}", with: " ").trimmingCharacters(in: .whitespaces)
        guard let m = try? #/^(\d{1,2})(?::(\d{2}))?\s*(AM|PM)?$/#.firstMatch(in: t) else { return nil }
        var hour = Int(m.1) ?? 0
        let minute = m.2.flatMap { Int($0) } ?? 0
        if let meridiem = m.3 {
            if meridiem == "PM", hour < 12 { hour += 12 }
            if meridiem == "AM", hour == 12 { hour = 0 }
        }
        return calendar.date(bySettingHour: hour, minute: minute, second: 0, of: day)
    }

    /// Time column text: "9:00" with the AM/PM dropped when the hour is unambiguous in context.
    static func shortTime(_ time: String) -> String {
        time.replacingOccurrences(of: "\u{202F}", with: " ")
    }
}

// MARK: Weather parsing

/// Parsed form of the weather section text
/// ("64°F (Partly Cloudy) in Murrieta. Feels like 62°F. Humidity 40%. Wind 8 mph W.").
struct WeatherSummary {
    let temperature: String   // "64°"
    let unit: String          // "F"
    let condition: String     // "Partly Cloudy"
    let location: String      // "Murrieta"
    let feelsLike: String?    // "62°F"
    let humidity: String?     // "40%"
    let wind: String?         // "8 mph W"
    let note: String?         // trailing UV warning, if any

    static func parse(_ text: String) -> WeatherSummary? {
        let pattern = #/^\s*(?<temp>-?\d+)°(?<unit>[CF])\s*\((?<cond>[^)]+)\)\s*in\s+(?<loc>[^.]+)\.(?<rest>.*)$/#
        guard let m = try? pattern.firstMatch(in: text) else { return nil }
        let rest = String(m.rest)
        func capture(_ regex: Regex<(Substring, Substring)>) -> String? {
            guard let r = try? regex.firstMatch(in: rest) else { return nil }
            return String(r.1).trimmingCharacters(in: .whitespaces)
        }
        let feels = capture(#/Feels like\s+([^.]+)\./#)
        let humidity = capture(#/Humidity\s+([^.]+)\./#)
        let wind = capture(#/Wind\s+([^.]+)\./#)
        var note: String? = nil
        if let windRange = rest.range(of: "Wind") , let dot = rest[windRange.upperBound...].firstIndex(of: ".") {
            let trailing = rest[rest.index(after: dot)...].trimmingCharacters(in: .whitespacesAndNewlines)
            note = trailing.isEmpty ? nil : trailing
        }
        return WeatherSummary(
            temperature: "\(m.temp)°",
            unit: String(m.unit),
            condition: String(m.cond).trimmingCharacters(in: .whitespaces),
            location: String(m.loc).trimmingCharacters(in: .whitespaces),
            feelsLike: feels, humidity: humidity, wind: wind, note: note
        )
    }

    /// SF Symbol for the condition text; night variants between 19:00 and 06:00.
    static func symbol(for condition: String, hour: Int = Calendar.current.component(.hour, from: Date())) -> String {
        let c = condition.lowercased()
        let night = hour >= 19 || hour < 6
        if c.contains("thunder") || c.contains("storm") { return "cloud.bolt.rain" }
        if c.contains("snow") || c.contains("sleet") || c.contains("flurr") { return "cloud.snow" }
        if c.contains("rain") || c.contains("drizzle") || c.contains("shower") { return "cloud.rain" }
        if c.contains("fog") || c.contains("mist") || c.contains("haze") || c.contains("smoke") { return "cloud.fog" }
        if c.contains("wind") || c.contains("breez") { return "wind" }
        if c.contains("partly") || c.contains("mostly clear") || c.contains("few clouds") {
            return night ? "cloud.moon" : "cloud.sun"
        }
        if c.contains("cloud") || c.contains("overcast") { return "cloud" }
        if c.contains("clear") || c.contains("sunny") { return night ? "moon.stars" : "sun.max" }
        return night ? "moon.stars" : "sun.max"
    }
}

// MARK: Health parsing

/// Stat tiles parsed from the health section text
/// ("Last night: 7h 12m asleep (of 7h 50m in bed). Today: 8432 steps. HRV: 45ms. Resting HR: 58 bpm.").
struct HealthStat: Identifiable {
    let label: String
    let value: String
    let unit: String?
    var id: String { label }

    static func parse(_ text: String) -> [HealthStat] {
        var stats: [HealthStat] = []
        if let m = try? #/Last night:\s*([^(.]+?)\s+asleep/#.firstMatch(in: text) {
            stats.append(HealthStat(label: "Sleep", value: String(m.1).trimmingCharacters(in: .whitespaces), unit: nil))
        }
        if let m = try? #/Today:\s*([\d,]+)\s+steps/#.firstMatch(in: text) {
            let n = Int(String(m.1).replacingOccurrences(of: ",", with: "")) ?? 0
            stats.append(HealthStat(label: "Steps", value: n.formatted(.number.grouping(.automatic)), unit: nil))
        }
        if let m = try? #/HRV:\s*(\d+)\s*ms/#.firstMatch(in: text) {
            stats.append(HealthStat(label: "HRV", value: String(m.1), unit: "ms"))
        }
        if let m = try? #/Resting HR:\s*(\d+)\s*bpm/#.firstMatch(in: text) {
            stats.append(HealthStat(label: "Resting HR", value: String(m.1), unit: "bpm"))
        }
        return stats
    }
}

// MARK: Markets line parsing

/// One "SPY: $735.29 ↓2.70%" line from the markets section.
struct MarketLine: Identifiable {
    let symbol: String
    let price: String
    let change: Double
    var id: String { symbol }

    static func parse(_ text: String) -> [MarketLine] {
        text.split(separator: "\n").compactMap { line -> MarketLine? in
            guard let m = try? #/^\s*([A-Za-z0-9.\-]+):\s*(\$[\d,\.]+)\s*([↑↓])\s*([\d.]+)%/#.firstMatch(in: line) else { return nil }
            let magnitude = Double(String(m.4)) ?? 0
            return MarketLine(symbol: String(m.1), price: String(m.2),
                              change: m.3 == "↓" ? -magnitude : magnitude)
        }
    }
}

/// One "9:00 AM — Standup" line from the calendar section.
struct CalendarLine: Identifiable {
    let time: String
    let title: String
    var id: String { time + title }

    static func parse(_ text: String) -> [CalendarLine] {
        text.split(separator: "\n").compactMap { line -> CalendarLine? in
            let parts = line.components(separatedBy: " — ")
            guard parts.count >= 2 else { return nil }
            return CalendarLine(time: parts[0].trimmingCharacters(in: .whitespaces),
                                title: parts.dropFirst().joined(separator: " — ").trimmingCharacters(in: .whitespaces))
        }
    }
}
