import SwiftUI

/// Hero card: local weather + proxy-backed market pulse (SPY / BTC).
struct MorningSnapshotCard: View {
    let snapshot: MorningSnapshot

    var body: some View {
        AnimatedCard(delay: 0) {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Label("Morning snapshot", systemImage: "sun.horizon.fill")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Color.warmPrimaryAccent)
                    Spacer()
                    statusPill
                }

                if let weatherLine = snapshot.weatherLine {
                    HStack(alignment: .firstTextBaseline, spacing: 10) {
                        Text(snapshot.weatherIcon ?? "🌤️")
                            .font(.title2)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(weatherLine)
                                .font(.title3.weight(.bold))
                                .foregroundStyle(Color.warmTextPrimary)
                            if let location = snapshot.location {
                                Text(location)
                                    .font(.caption)
                                    .foregroundStyle(Color.warmTextSecondary)
                            }
                        }
                    }
                } else {
                    Text(weatherPlaceholder)
                        .font(.subheadline)
                        .foregroundStyle(Color.warmTextSecondary)
                }

                if let cal = snapshot.calendarLine {
                    HStack(spacing: 6) {
                        Image(systemName: "calendar")
                            .font(.caption)
                        Text(cal)
                            .font(.caption)
                    }
                    .foregroundStyle(Color.warmTextSecondary)
                }

                Divider().opacity(0.35)

                marketRow
            }
        }
    }

    @ViewBuilder
    private var marketRow: some View {
        switch snapshot.marketsStatus {
        case .loading:
            HStack(spacing: 8) {
                ProgressView()
                Text("Loading markets…")
                    .font(.caption)
                    .foregroundStyle(Color.warmTextSecondary)
            }
        case .unavailable:
            Text("Markets offline — pull to refresh when you’re back online.")
                .font(.caption)
                .foregroundStyle(Color.warmTextSecondary)
        case .live, .cached:
            HStack(spacing: 12) {
                ForEach(snapshot.marketQuotes) { quote in
                    quoteChip(quote)
                }
                if snapshot.marketQuotes.isEmpty {
                    Text("No market quotes yet")
                        .font(.caption)
                        .foregroundStyle(Color.warmTextSecondary)
                }
            }
        }
    }

    private func quoteChip(_ quote: MorningSnapshotQuote) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(quote.symbol)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(Color.warmTextSecondary)
            Text(quote.priceText)
                .font(.subheadline.weight(.bold))
                .foregroundStyle(Color.warmTextPrimary)
            Text(quote.changeText)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(quote.isPositive ? Color.warmPositive : Color.warmNegative)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(Color.warmCardBackground.opacity(0.6))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private var statusPill: some View {
        let (text, color): (String, Color) = {
            switch snapshot.marketsStatus {
            case .loading: return ("…", Color.warmTextSecondary)
            case .live: return ("LIVE", Color.warmExternalBadge)
            case .cached: return ("CACHED", Color.warmSecondaryAccent)
            case .unavailable: return ("MARKETS", Color.warmTextSecondary)
            }
        }()
        return Text(text)
            .font(.caption2.weight(.bold))
            .foregroundStyle(color)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(color.opacity(0.12))
            .clipShape(Capsule())
    }

    private var weatherPlaceholder: String {
        if !snapshot.weatherEnabled {
            return "Weather is off in Settings → Data Sources."
        }
        if snapshot.weatherNeedsLocation {
            return "Allow Location for MorningVault (Settings → Privacy → Location → While Using), then pull to refresh."
        }
        if let detail = snapshot.weatherErrorDetail, !detail.isEmpty {
            if detail.localizedCaseInsensitiveContains("WeatherKit") || detail.contains("error 2") {
                return "WeatherKit JWT failed (stale App Store profile). Regenerate MorningVaultAppStores, reinstall. Weather may still load via city fallback after refresh."
            }
            if detail.localizedCaseInsensitiveContains("Location") {
                return "\(detail) Pull to refresh after granting location."
            }
            return "\(detail) Pull to refresh."
        }
        return "Weather didn’t load — pull to refresh. Check Location (While Using) and WeatherKit on your Apple Developer App ID."
    }
}