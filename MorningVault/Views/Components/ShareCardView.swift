import SwiftUI
import UIKit

// MARK: - Share card
//
// 1080×1350 pt branded card rendered with ImageRenderer when Share is tapped: the mini sky
// scene with the temperature, the greeting, the lede, the next event and two market rows.

struct ShareCardView: View {
    let hour: Int
    let weather: WeatherSummary?
    let greeting: String
    let lede: String?
    let nextEvent: CalendarLine?
    let quotes: [MorningSnapshotQuote]
    let dateText: String
    var colorScheme: ColorScheme = .light

    static let size = CGSize(width: 1080, height: 1350)

    private var style: SkyStyle { SkyStyle.resolve(hour: hour, condition: weather?.condition, colorScheme: colorScheme) }
    private var sceneInk: Color { style.usesLightText ? .white : Color(hex: "121214") }
    private var canvas: Color { colorScheme == .dark ? Color(hex: "0B0C11") : Color(hex: "F3F0E9") }
    private var ink: Color { colorScheme == .dark ? Color(hex: "F5F2EC") : Color(hex: "121214") }
    private var inkSecondary: Color { colorScheme == .dark ? Color(hex: "ABA8A2") : Color(hex: "6E6A63") }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ZStack(alignment: .bottomLeading) {
                SkyScene(hour: hour, condition: weather?.condition)
                    .environment(\.colorScheme, colorScheme)
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Text(dateText.uppercased())
                            .font(.system(size: 26, weight: .semibold))
                            .tracking(3)
                        Spacer()
                        Text("MORNINGVAULT")
                            .font(.system(size: 26, weight: .semibold))
                            .tracking(3)
                    }
                    .foregroundStyle(sceneInk.opacity(0.85))
                    .padding(.bottom, 320)
                    if let weather {
                        Text(weather.temperature)
                            .font(.system(size: 220, weight: .medium, design: .serif))
                            .monospacedDigit()
                            .foregroundStyle(sceneInk)
                        Text("\(weather.condition) · \(weather.location)")
                            .font(.system(size: 40, weight: .medium))
                            .foregroundStyle(sceneInk.opacity(0.9))
                    }
                }
                .padding(64)
            }
            .frame(height: 720)
            .overlay(alignment: .bottom) {
                LinearGradient(colors: [canvas.opacity(0), canvas], startPoint: .top, endPoint: .bottom)
                    .frame(height: 160)
            }

            VStack(alignment: .leading, spacing: 28) {
                Text(greeting)
                    .font(.system(size: 72, weight: .medium, design: .serif))
                    .foregroundStyle(ink)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                if let lede {
                    Text(lede)
                        .font(.system(size: 40, weight: .regular, design: .serif))
                        .foregroundStyle(ink)
                        .lineSpacing(10)
                        .lineLimit(3)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if let nextEvent {
                    HStack(alignment: .firstTextBaseline, spacing: 24) {
                        Text("NEXT")
                            .font(.system(size: 24, weight: .semibold))
                            .tracking(3)
                            .foregroundStyle(inkSecondary)
                        Text(nextEvent.time)
                            .font(.system(size: 36, weight: .medium).monospacedDigit())
                            .foregroundStyle(inkSecondary)
                        Text(nextEvent.title)
                            .font(.system(size: 36, weight: .semibold))
                            .foregroundStyle(ink)
                            .lineLimit(1)
                    }
                }
                if !quotes.isEmpty {
                    Rectangle().fill(ink.opacity(0.1)).frame(height: 2)
                    HStack(spacing: 48) {
                        ForEach(quotes.prefix(2)) { q in
                            HStack(spacing: 24) {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(q.symbol)
                                        .font(.system(size: 24, weight: .semibold))
                                        .tracking(3)
                                        .foregroundStyle(inkSecondary)
                                    Text(q.priceText)
                                        .font(.system(size: 48, weight: .medium).monospacedDigit())
                                        .foregroundStyle(ink)
                                    Text("\(q.change24h > 0 ? "▲" : (q.change24h < 0 ? "▼" : "")) \(String(format: "%.2f", abs(q.change24h)))%")
                                        .font(.system(size: 26, weight: .semibold).monospacedDigit())
                                        .foregroundStyle(q.change24h >= 0 ? Color(hex: colorScheme == .dark ? "58C9A6" : "157B65")
                                                                           : Color(hex: colorScheme == .dark ? "FF746C" : "C44740"))
                                }
                                if q.series.count > 1 {
                                    Sparkline(points: q.series, prevClose: q.prevClose,
                                              color: q.change24h >= 0 ? Color(hex: colorScheme == .dark ? "58C9A6" : "157B65")
                                                                      : Color(hex: colorScheme == .dark ? "FF746C" : "C44740"),
                                              lineWidth: 3, animated: false)
                                        .frame(width: 180, height: 64)
                                }
                            }
                        }
                        Spacer(minLength: 0)
                    }
                }
                Spacer(minLength: 0)
                HStack(spacing: 10) {
                    Image(systemName: "lock.fill")
                        .font(.system(size: 22, weight: .medium))
                    Text("Written on this iPhone")
                        .font(.system(size: 24, weight: .regular))
                }
                .foregroundStyle(inkSecondary)
            }
            .padding(.horizontal, 64)
            .padding(.top, 8)
            .padding(.bottom, 56)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .frame(width: Self.size.width, height: Self.size.height)
        .background(canvas)
    }

    /// Rasterises the card at 2× (2160×2700 px) for the share sheet.
    @MainActor
    func render() -> UIImage? {
        let renderer = ImageRenderer(content: self)
        renderer.scale = 2
        renderer.proposedSize = ProposedViewSize(Self.size)
        return renderer.uiImage
    }
}

#Preview("Share card") {
    ShareCardView(
        hour: 7,
        weather: WeatherSummary.parse("64°F (Partly Cloudy) in Murrieta. Feels like 62°F. Humidity 40%. Wind 8 mph W."),
        greeting: "Good morning, Yezid.",
        lede: "A mild, partly cloudy morning with three meetings, the first at nine.",
        nextEvent: CalendarLine(time: "9:00 AM", title: "Standup"),
        quotes: [
            MorningSnapshotQuote(symbol: "SPY", priceText: "$735.29", change24h: -2.70, prevClose: 755.0, series: MarketPreviewData.spy),
            MorningSnapshotQuote(symbol: "BTC", priceText: "$75,699", change24h: 1.12, prevClose: 74_860, series: MarketPreviewData.btc)
        ],
        dateText: "Saturday, November 8"
    )
    .scaleEffect(0.33)
    .frame(width: 360, height: 450)
}
