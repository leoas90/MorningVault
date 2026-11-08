import SwiftUI

// MARK: - Editorial design system
//
// "Calm morning paper": paper background, ink text, serif display type, one accent.
// Everything here is presentational and reads the theme through `Color.ink…`/`warm…`,
// so a Theme or Palette change re-renders in place.

// MARK: Type

extension Font {
    /// Display serif (New York) for greetings, titles and big numerals.
    static func display(_ size: CGFloat, weight: Font.Weight = .semibold) -> Font {
        .system(size: size, weight: weight, design: .serif)
    }

    /// Lede paragraph under the greeting.
    static var lede: Font { .system(size: 17, weight: .regular, design: .serif) }
}

/// Small-caps style label: "WEATHER", "TODAY", "SATURDAY, NOVEMBER 8".
struct Eyebrow: View {
    let text: String
    var color: Color? = nil

    var body: some View {
        Text(text)
            .font(.caption.weight(.semibold))
            .textCase(.uppercase)
            .tracking(1.2)
            .foregroundStyle(color ?? Color.inkSecondary)
    }
}

// MARK: Card

/// The one card treatment: surface, hairline border, soft shadow in light mode only.
struct EditorialCardModifier: ViewModifier {
    @Environment(\.colorScheme) private var colorScheme
    var padding: CGFloat = 18

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: AppRadius.card, style: .continuous)
        content
            .padding(padding)
            .background(Color.surfaceColor, in: shape)
            .overlay(shape.strokeBorder(Color.hairline, lineWidth: 1))
            .shadow(color: Color.black.opacity(colorScheme == .dark ? 0 : 0.06), radius: 12, x: 0, y: 4)
    }
}

extension View {
    func editorialCard(padding: CGFloat = 18) -> some View {
        modifier(EditorialCardModifier(padding: padding))
    }
}

/// 1px rule in the ink hairline color.
struct Hairline: View {
    var body: some View {
        Rectangle()
            .fill(Color.inkPrimary.opacity(0.12))
            .frame(height: 1)
    }
}

// MARK: Pills

/// Percentage change with a tinted background, not just colored text.
struct ChangePill: View {
    let change: Double

    private var color: Color {
        if change > 0 { return Color.positiveColor }
        if change < 0 { return Color.negativeColor }
        return Color.inkSecondary
    }

    private var text: String {
        let sign = change > 0 ? "+" : (change < 0 ? "−" : "")
        return "\(sign)\(String(format: "%.2f", abs(change)))%"
    }

    var body: some View {
        Text(text)
            .font(.caption.weight(.semibold).monospacedDigit())
            .foregroundStyle(color)
            .lineLimit(1)
            .fixedSize()
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(color.opacity(0.16), in: Capsule())
            .accessibilityLabel(change >= 0 ? "up \(text)" : "down \(text)")
    }
}

/// Quiet sentiment pill for card headers.
struct SentimentPill: View {
    let sentiment: String

    private var color: Color {
        switch sentiment.lowercased() {
        case "bullish", "positive": return Color.positiveColor
        case "bearish", "negative": return Color.negativeColor
        default: return Color.inkSecondary
        }
    }

    var body: some View {
        Text(sentiment.capitalized)
            .font(.caption2.weight(.semibold))
            .foregroundStyle(color)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(color.opacity(0.12), in: Capsule())
    }
}

/// Pill action button used in the hero ("Listen", "Share").
struct PillButton: View {
    let title: String
    let systemImage: String
    var prominent: Bool = false
    var isActive: Bool = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .font(.subheadline.weight(.semibold))
                .symbolEffect(.variableColor.iterative, isActive: isActive)
                .lineLimit(1)
                .padding(.horizontal, 16)
                .frame(minHeight: 44)
                .foregroundStyle(prominent ? Color.onAccent : Color.inkPrimary)
                .background(prominent ? Color.appAccentColor : Color.surfaceColor, in: Capsule())
                .overlay(Capsule().strokeBorder(prominent ? Color.clear : Color.inkPrimary.opacity(0.16), lineWidth: 1))
        }
        .buttonStyle(.plain)
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

    /// Pre-dawn and dusk use light text; the day/sunrise washes use ink.
    static func usesLightText(hour: Int, colorScheme: ColorScheme) -> Bool {
        if colorScheme == .dark { return true }
        switch hour {
        case 0..<6: return true
        case 6..<17: return false
        default: return true
        }
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
