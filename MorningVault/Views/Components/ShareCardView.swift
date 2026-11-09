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
    var updatedText: String? = nil
    var colorScheme: ColorScheme = .light

    static let size = CGSize(width: 1080, height: 1350)
    /// The hero is laid out at phone size (353 wide, 196 pt of content under 56 pt of sky, the
    /// same proportions as the app under its bars) and scaled.
    private static let heroScale: CGFloat = 960 / 353
    private static let heroTopInset: CGFloat = 56
    private static let heroHeight: CGFloat = WeatherHero.contentHeight + heroTopInset


    private var canvas: Color { colorScheme == .dark ? Color(hex: "17141B") : Color(hex: "F6F2EC") }
    private var ink: Color { colorScheme == .dark ? Color(hex: "F7F2EA") : Color(hex: "171615") }
    private var inkSecondary: Color { colorScheme == .dark ? Color(hex: "B8B0B7") : Color(hex: "66615B") }
    private var separator: Color { colorScheme == .dark ? Color(hex: "3A333C") : Color(hex: "DDD7CF") }
    private func semantic(_ change: Double) -> Color {
        if change < 0 { return Color(hex: colorScheme == .dark ? "F07870" : "B83A3A") }
        return Color(hex: colorScheme == .dark ? "58BFA6" : "16735D")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 64) {
            WeatherHero(hour: hour, weather: weather, dateText: dateText, updatedText: updatedText,
                        greeting: greeting, colorSchemeOverride: colorScheme, animated: false, topInset: Self.heroTopInset)
                .environment(\.colorScheme, colorScheme)
                .frame(width: 353, height: WeatherHero.contentHeight)
                .padding(.top, Self.heroTopInset)
                .scaleEffect(Self.heroScale, anchor: .topLeading)
                .frame(width: 960, height: Self.heroHeight * Self.heroScale, alignment: .topLeading)

            VStack(alignment: .leading, spacing: 24) {
                Text(greeting)
                    .font(.system(size: 84, weight: .semibold, design: .serif))
                    .foregroundStyle(ink)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                if let lede {
                    Text(lede)
                        .font(.system(size: 48, weight: .regular))
                        .foregroundStyle(ink)
                        .lineSpacing(10)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            if let nextEvent {
                HStack(alignment: .firstTextBaseline, spacing: 24) {
                    Text("NEXT")
                        .font(.system(size: 26, weight: .semibold))
                        .tracking(2)
                        .foregroundStyle(inkSecondary)
                    Text(nextEvent.time)
                        .font(.system(size: 36, weight: .medium).monospacedDigit())
                        .foregroundStyle(inkSecondary)
                    Text(nextEvent.title)
                        .font(.system(size: 38, weight: .semibold))
                        .foregroundStyle(ink)
                        .lineLimit(1)
                }
            }

            if !quotes.isEmpty {
                VStack(alignment: .leading, spacing: 0) {
                    Rectangle().fill(separator).frame(height: 2)
                    HStack(spacing: 48) {
                        ForEach(quotes.prefix(2)) { q in
                            HStack(spacing: 28) {
                                VStack(alignment: .leading, spacing: 6) {
                                    Text(q.symbol)
                                        .font(.system(size: 26, weight: .semibold))
                                        .tracking(2)
                                        .foregroundStyle(inkSecondary)
                                    Text(q.priceText)
                                        .font(.system(size: 56, weight: .medium).monospacedDigit())
                                        .lineLimit(1)
                                        .fixedSize()
                                        .foregroundStyle(ink)
                                    Text("\(q.change24h > 0 ? "▲" : (q.change24h < 0 ? "▼" : "")) \(String(format: "%.2f", abs(q.change24h)))%")
                                        .font(.system(size: 30, weight: .semibold).monospacedDigit())
                                        .foregroundStyle(semantic(q.change24h))
                                }
                                if q.series.count > 1 {
                                    Sparkline(points: q.series, prevClose: q.prevClose, color: semantic(q.change24h),
                                              lineWidth: 4, animated: false)
                                        .frame(width: 160, height: 64)
                                }
                            }
                        }
                        Spacer(minLength: 0)
                    }
                    .padding(.top, 32)
                }
            }

            Spacer(minLength: 0)

            HStack(spacing: 12) {
                Image(systemName: "lock.fill")
                    .font(.system(size: 24, weight: .medium))
                Text("Written on this iPhone · MorningVault")
                    .font(.system(size: 26, weight: .medium))
            }
            .foregroundStyle(inkSecondary)
        }
        .padding(.horizontal, 60)
        .padding(.top, 72)
        .padding(.bottom, 64)
        .frame(width: Self.size.width, height: Self.size.height, alignment: .topLeading)
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
        weather: WeatherSummary.parse(BriefingViewModel.previewWeatherClear),
        greeting: "Good morning, Sam.",
        lede: "A mild morning with three meetings, the first at nine.",
        nextEvent: CalendarLine(time: "9:00 AM", title: "Standup"),
        quotes: [
            MorningSnapshotQuote(symbol: "SPY", priceText: "$735.29", change24h: -2.70, prevClose: 755.0, series: MarketPreviewData.spy),
            MorningSnapshotQuote(symbol: "BTC", priceText: "$75,699", change24h: 1.12, prevClose: 74_860, series: MarketPreviewData.btc)
        ],
        dateText: "Monday, November 10",
        updatedText: "7:21 AM"
    )
    .scaleEffect(0.33)
    .frame(width: 360, height: 450)
}
