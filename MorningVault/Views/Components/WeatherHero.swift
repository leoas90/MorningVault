import SwiftUI

// MARK: - Weather hero (L1, full bleed)
//
// The Brief's one hero object, with no container: the sky scene runs edge to edge and under
// the status bar / navigation bar, and fades into the canvas over its last 80 pt (gradient
// mask, no seam). The content stays inside the safe area: date eyebrow + "Updated h:mm" with
// the breathing dot, the temperature (76 pt serif, degree sign 40 pt hung from the cap line),
// "Condition · Location", and a three-column stats grid. Without weather it shows the
// greeting in the same slot.
//
// `contentHeight` is the part below the safe area (196 pt); the scene overflows the frame
// upward by `topInset` (the status bar + inline navigation bar, ~100 pt, so ~300 pt in all).
// The ScrollView shows that overflow in its top content inset, so the sky runs to the edge.
//
// Plain values in, so the share card can render the same hero at any scale.

struct WeatherHero: View {
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
    /// Sky drawn above the content block (the status bar + navigation bar in the app; a fixed
    /// band on the share card). The scene overflows the hero's frame upward by this amount.
    var topInset: CGFloat = 0

    /// Height of the content block below the safe area.
    static let contentHeight: CGFloat = 196
    /// Height of the bottom fade into the canvas.
    static let fade: CGFloat = 80
    static let padding: CGFloat = 20

    @Environment(\.colorScheme) private var environmentScheme

    private var scheme: ColorScheme { colorSchemeOverride ?? environmentScheme }
    var style: SkyStyle { SkyStyle.resolve(hour: hour, condition: weather?.condition, colorScheme: scheme) }
    private var ink: Color { style.usesLightText ? Color.white : Color(hex: "171615") }
    private var inkSecondary: Color { style.usesLightText ? Color.white.opacity(0.78) : Color(hex: "171615").opacity(0.66) }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            topRow
            Spacer(minLength: 12)
            if let weather {
                weatherBlock(weather)
            } else {
                greetingBlock
            }
        }
        .padding(.horizontal, Self.padding)
        .padding(.top, 8)
        .padding(.bottom, Self.padding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(height: Self.contentHeight)
        .background(alignment: .bottom) {
            // The scene is taller than the content block and hangs off its top, under the
            // status bar and the (background-hidden) navigation bar; the art box keeps its
            // 44 pt inset below them. Bottom 80 pt fade into the canvas.
            SkyScene(hour: hour, condition: weather?.condition,
                     artInset: CGSize(width: 20, height: topInset + 44))
                .environment(\.colorScheme, scheme)
                .frame(height: Self.contentHeight + topInset)
                .mask {
                    VStack(spacing: 0) {
                        Color.black
                        LinearGradient(colors: [Color.black, Color.black.opacity(0)], startPoint: .top, endPoint: .bottom)
                            .frame(height: Self.fade)
                    }
                }
        }
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
            WeatherHero(hour: 7, weather: WeatherSummary.parse(clear), dateText: "Monday, November 10", updatedText: "7:21 AM", topInset: 100).padding(.top, 100)
            WeatherHero(hour: 9, weather: WeatherSummary.parse(rain), dateText: "Monday, November 10", updatedText: "7:21 AM", topInset: 100).padding(.top, 100)
            WeatherHero(hour: 18, weather: WeatherSummary.parse(cloudy), dateText: "Monday, November 10", updatedText: "6:02 PM", colorSchemeOverride: .dark, topInset: 100).padding(.top, 100)
            WeatherHero(hour: 7, weather: nil, dateText: "Monday, November 10", greeting: "Good morning, Yezid.", notice: "Allow Location to see the weather here.", topInset: 100).padding(.top, 100)
        }
    }
    .background(Color.backgroundColor)
}
