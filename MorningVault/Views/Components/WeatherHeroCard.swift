import SwiftUI

// MARK: - Weather hero card (L1)
//
// The Brief's one hero object: a 250 pt card (radius 28, inner padding 20) with the sky scene
// clipped inside it. Top row: date eyebrow + "Updated h:mm" with the breathing dot. Then the
// temperature (76 pt serif, degree sign 40 pt on the same baseline), "Condition · Location",
// and a three-column stats grid. Without weather it shows the greeting in the same slot.
// Shadow: black 8 % r20 y8 in light; a hairline instead in dark.
//
// Plain values in, so the share card can render the same card at any scale.

struct WeatherHeroCard: View {
    let hour: Int
    let weather: WeatherSummary?
    let dateText: String
    /// "7:21 AM" — shown as "Updated 7:21 AM" with the breathing dot; nil hides the status.
    var updatedText: String? = nil
    /// Shown instead of "Updated" while a refresh is running.
    var isUpdating: Bool = false
    /// Greeting for the no-weather state.
    var greeting: String? = nil
    /// One-line reason weather is missing (Location, availability).
    var notice: String? = nil
    /// Previews / share card: force a scheme instead of reading the environment.
    var colorSchemeOverride: ColorScheme? = nil
    /// Offscreen renders: no breathing animation.
    var animated: Bool = true

    static let height: CGFloat = 250
    static let radius: CGFloat = 28
    static let padding: CGFloat = 20

    @Environment(\.colorScheme) private var environmentScheme

    private var scheme: ColorScheme { colorSchemeOverride ?? environmentScheme }
    private var style: SkyStyle { SkyStyle.resolve(hour: hour, condition: weather?.condition, colorScheme: scheme) }
    private var ink: Color { style.usesLightText ? Color.white : Color(hex: "171615") }
    private var inkSecondary: Color { style.usesLightText ? Color.white.opacity(0.78) : Color(hex: "171615").opacity(0.66) }

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: Self.radius, style: .continuous)
        VStack(alignment: .leading, spacing: 0) {
            topRow
            Spacer(minLength: 12)
            if let weather {
                weatherBlock(weather)
            } else {
                greetingBlock
            }
        }
        .padding(Self.padding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(height: Self.height)
        .background {
            SkyScene(hour: hour, condition: weather?.condition)
                .environment(\.colorScheme, scheme)
        }
        .clipShape(shape)
        .overlay {
            if scheme == .dark {
                shape.strokeBorder(Color.white.opacity(0.08), lineWidth: 1)
            }
        }
        .shadow(color: Color.black.opacity(scheme == .dark ? 0 : 0.08), radius: 20, x: 0, y: 8)
        .accessibilityElement(children: .contain)
    }

    // MARK: Rows

    private var topRow: some View {
        HStack(alignment: .center, spacing: 10) {
            Eyebrow(text: dateText, color: inkSecondary)
            Spacer(minLength: 8)
            if let updatedText {
                HStack(spacing: 6) {
                    BreathingDot(color: ink, animated: animated)
                    Text("Updated \(updatedText)")
                        .font(.system(size: 13, weight: .regular).monospacedDigit())
                }
                .foregroundStyle(inkSecondary)
                .accessibilityElement(children: .combine)
            } else if isUpdating {
                Text("Updating…")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(inkSecondary)
            }
        }
        .frame(height: 16)
    }

    private func weatherBlock(_ w: WeatherSummary) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                TemperatureText(value: w.temperature, color: ink)
                    .accessibilityLabel("\(w.temperature) \(w.unit)")
                Text("\(w.condition) · \(w.location)")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(ink)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
            }
            Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 4) {
                GridRow {
                    label("Feels like")
                    label("Humidity")
                    label("Wind")
                }
                GridRow {
                    stat(w.feelsLike)
                    stat(w.humidity)
                    stat(w.wind)
                }
            }
        }
    }

    private func label(_ text: String) -> some View {
        Eyebrow(text: text, color: inkSecondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .gridColumnAlignment(.leading)
    }

    /// "62°F" → "62°": the unit is implied by the big numeral.
    private func trimmedUnit(_ value: String) -> String {
        if value.hasSuffix("°F") || value.hasSuffix("°C") { return String(value.dropLast()) }
        return value
    }

    private func stat(_ value: String?) -> some View {
        Text(value.map(trimmedUnit) ?? "No data")
            .font(.metricValue)
            .foregroundStyle(value == nil ? inkSecondary : ink)
            .lineLimit(1)
            .frame(maxWidth: .infinity, alignment: .leading)
            .gridColumnAlignment(.leading)
    }

    private var greetingBlock: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(greeting ?? "Today")
                .font(.greeting)
                .lineSpacing(Leading.greeting)
                .foregroundStyle(ink)
                .lineLimit(2)
                .minimumScaleFactor(0.85)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
            if let notice {
                Text(notice)
                    .font(.secondaryText)
                    .foregroundStyle(inkSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .lineLimit(3)
            }
        }
        .frame(maxWidth: 280, alignment: .leading)
    }
}

/// "64°" with the numeral at 76 pt serif medium and the degree sign at 40 pt hung from the
/// cap height (an HStack aligned on `.top`, the sign nudged to the numeral's cap line; never
/// a scaled glyph).
struct TemperatureText: View {
    let value: String
    var color: Color
    var numeralSize: CGFloat = 76
    var signSize: CGFloat = 40

    private var numeral: String { value.replacingOccurrences(of: "°", with: "") }

    var body: some View {
        HStack(alignment: .top, spacing: -2) {
            Text(numeral)
                .font(.display(numeralSize, weight: .medium))
                .monospacedDigit()
            Text("°")
                .font(.display(signSize, weight: .medium))
                .padding(.top, numeralSize * 0.14)
        }
        .foregroundStyle(color)
        .lineLimit(1)
        .accessibilityElement(children: .ignore)
    }
}

#Preview("Hero · states") {
    ThemeStore.shared.themeRaw = AppTheme.light.rawValue
    let clear: String = "64°F (Clear) in Murrieta. Feels like 62°F. Humidity 40%. Wind 8 mph W."
    let rain: String = "52°F (Rain) in Murrieta. Feels like 48°F. Humidity 91%. Wind 14 mph S."
    let cloudy: String = "64°F (Partly Cloudy) in Murrieta. Feels like 62°F. Humidity 40%. Wind 8 mph W."
    return ScrollView {
        VStack(spacing: 16) {
            WeatherHeroCard(hour: 7, weather: WeatherSummary.parse(clear), dateText: "Monday, November 10", updatedText: "7:21 AM")
            WeatherHeroCard(hour: 9, weather: WeatherSummary.parse(rain), dateText: "Monday, November 10", updatedText: "7:21 AM")
            WeatherHeroCard(hour: 18, weather: WeatherSummary.parse(cloudy), dateText: "Monday, November 10", updatedText: "6:02 PM", colorSchemeOverride: .dark)
            WeatherHeroCard(hour: 7, weather: nil, dateText: "Monday, November 10", greeting: "Good morning, Yezid.", notice: "Allow Location to see the weather here.")
        }
        .padding(20)
    }
    .background(Color.backgroundColor)
}
