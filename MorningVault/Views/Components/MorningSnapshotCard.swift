import SwiftUI

/// Compact market strip under the hero: SPY / BTC with change pills and a freshness label.
/// Weather lives in the Weather card; this strip only speaks up about weather when it
/// cannot be shown (Location, WeatherKit, toggle off).
struct MorningSnapshotCard: View {
    let snapshot: MorningSnapshot

    private var showsWeatherNotice: Bool {
        snapshot.weatherLine == nil
    }

    var body: some View {
        if showsWeatherNotice || snapshot.marketsStatus != .loading || !snapshot.marketQuotes.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                if showsWeatherNotice {
                    HStack(alignment: .top, spacing: 8) {
                        Image(systemName: snapshot.weatherNeedsLocation ? "location.slash" : "cloud.slash")
                            .font(.caption)
                            .symbolRenderingMode(.hierarchical)
                            .foregroundStyle(Color.appAccentColor)
                        Text(weatherPlaceholder)
                            .font(.footnote)
                            .foregroundStyle(Color.inkSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                marketRow
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .editorialCard(padding: 16)
            .cardEntrance(delay: 0)
        }
    }

    @ViewBuilder
    private var marketRow: some View {
        switch snapshot.marketsStatus {
        case .loading:
            HStack(spacing: 10) {
                SkeletonLine(width: 110, height: 12)
                SkeletonLine(width: 110, height: 12)
            }
            .accessibilityLabel("Loading markets")
        case .unavailable:
            Text("Market prices are off until the price server is published. Everything else in your briefing is on device.")
                .font(.footnote)
                .foregroundStyle(Color.inkSecondary)
                .fixedSize(horizontal: false, vertical: true)
        case .live, .cached:
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 14) {
                    quotes
                    Spacer(minLength: 0)
                    statusLabel
                }
                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 14) { quotes }
                    statusLabel
                }
            }
        }
    }

    @ViewBuilder
    private var quotes: some View {
        ForEach(snapshot.marketQuotes) { quote in
            HStack(spacing: 6) {
                Text(quote.symbol)
                    .font(.caption.weight(.bold))
                    .foregroundStyle(Color.inkSecondary)
                    .lineLimit(1)
                    .fixedSize()
                Text(quote.priceText)
                    .font(.subheadline.weight(.semibold).monospacedDigit())
                    .foregroundStyle(Color.inkPrimary)
                    .lineLimit(1)
                    .fixedSize()
                ChangePill(change: quote.change24h)
            }
            .accessibilityElement(children: .combine)
        }
        if snapshot.marketQuotes.isEmpty {
            Text("No market quotes yet")
                .font(.footnote)
                .foregroundStyle(Color.inkSecondary)
        }
    }

    private var statusLabel: some View {
        let text: String
        switch snapshot.marketsStatus {
        case .live: text = snapshot.updatedAt.map { "Live · \(EditorialFormat.time($0))" } ?? "Live"
        case .cached: text = "Cached"
        default: text = ""
        }
        return Text(text)
            .font(.caption2.weight(.semibold))
            .foregroundStyle(Color.inkSecondary)
            .lineLimit(1)
    }

    private var weatherPlaceholder: String {
        if !snapshot.weatherEnabled {
            return "Weather is off in Settings → Data Sources."
        }
        if snapshot.weatherNeedsLocation {
            return "Allow Location for MorningVault (Settings → Privacy → Location → While Using), then pull to refresh."
        }
        if let detail = snapshot.weatherErrorDetail, !detail.isEmpty {
            if detail.localizedCaseInsensitiveContains("Location") {
                return "Weather needs your location. Allow it in Settings, then pull to refresh."
            }
            return "Weather is unavailable right now. Pull to refresh to try again."
        }
        return "Weather is unavailable right now. Pull to refresh to try again."
    }
}
