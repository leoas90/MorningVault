import WidgetKit
import SwiftUI

// MARK: - Timeline Entry

struct MorningWidgetEntry: TimelineEntry {
    let date: Date
    let weatherTemp: String
    let weatherCondition: String
    let weatherIcon: String
    let topMovers: [WidgetMarketMover]
    let isPlaceholder: Bool

    static var placeholder: MorningWidgetEntry {
        MorningWidgetEntry(
            date: Date(),
            weatherTemp: "72°",
            weatherCondition: "Clear",
            weatherIcon: "sun.max.fill",
            topMovers: [
                WidgetMarketMover(symbol: "SPY", price: 520.0, change: 0.5),
                WidgetMarketMover(symbol: "AAPL", price: 189.0, change: 1.2),
                WidgetMarketMover(symbol: "BTC", price: 67500.0, change: -0.8),
            ],
            isPlaceholder: true
        )
    }
}

struct WidgetMarketMover: Codable {
    let symbol: String
    let price: Double
    let change: Double
}

// MARK: - Timeline Provider

struct MorningWidgetProvider: TimelineProvider {
    private let appGroupID = "group.com.morningvault.app"

    func placeholder(in context: Context) -> MorningWidgetEntry {
        MorningWidgetEntry.placeholder
    }

    func getSnapshot(in context: Context, completion: @escaping (MorningWidgetEntry) -> Void) {
        completion(loadEntry())
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<MorningWidgetEntry>) -> Void) {
        let entry = loadEntry()
        // Refresh every 15 minutes
        let nextUpdate = Calendar.current.date(byAdding: .minute, value: 15, to: Date())!
        let timeline = Timeline(entries: [entry], policy: .after(nextUpdate))
        completion(timeline)
    }

    private func loadEntry() -> MorningWidgetEntry {
        let defaults = UserDefaults(suiteName: appGroupID) ?? .standard

        let temp = defaults.string(forKey: "widget_weather_temp") ?? "—"
        let condition = defaults.string(forKey: "widget_weather_condition") ?? "—"
        let icon = defaults.string(forKey: "widget_weather_icon") ?? "cloud.fill"

        var movers: [WidgetMarketMover] = []
        if let moversData = defaults.data(forKey: "widget_top_movers"),
           let decoded = try? JSONDecoder().decode([WidgetMarketMover].self, from: moversData) {
            movers = decoded
        }

        return MorningWidgetEntry(
            date: Date(),
            weatherTemp: temp,
            weatherCondition: condition,
            weatherIcon: icon,
            topMovers: movers,
            isPlaceholder: false
        )
    }
}

// MARK: - Widget Views

struct MorningVaultWidgetEntryView: View {
    @Environment(\.widgetFamily) var family
    var entry: MorningWidgetEntry

    var body: some View {
        switch family {
        case .systemSmall:
            SmallWidgetView(entry: entry)
        case .systemMedium:
            MediumWidgetView(entry: entry)
        default:
            SmallWidgetView(entry: entry)
        }
    }
}

struct SmallWidgetView: View {
    let entry: MorningWidgetEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            // Weather
            HStack(spacing: 4) {
                Image(systemName: entry.weatherIcon)
                    .font(.title2)
                    .foregroundStyle(.orange)
                Text(entry.weatherTemp)
                    .font(.title3)
                    .fontWeight(.semibold)
            }

            Spacer()

            // Top market mover
            if let top = entry.topMovers.first {
                VStack(alignment: .leading, spacing: 2) {
                    Text(top.symbol)
                        .font(.caption)
                        .fontWeight(.bold)
                        .foregroundStyle(.secondary)
                    Text(formatPrice(top.price))
                        .font(.caption2)
                    Text(formatChange(top.change))
                        .font(.caption2)
                        .fontWeight(.semibold)
                        .foregroundStyle(top.change >= 0 ? .green : .red)
                }
            }
        }
        .padding()
    }

    private func formatPrice(_ price: Double) -> String {
        if price >= 1000 { return String(format: "$%.0f", price) }
        return String(format: "$%.2f", price)
    }

    private func formatChange(_ change: Double) -> String {
        let sign = change >= 0 ? "+" : ""
        return "\(sign)\(String(format: "%.1f", change))%"
    }
}

struct MediumWidgetView: View {
    let entry: MorningWidgetEntry

    var body: some View {
        HStack(spacing: 16) {
            // Weather section (left)
            VStack(alignment: .leading, spacing: 4) {
                Image(systemName: entry.weatherIcon)
                    .font(.largeTitle)
                    .foregroundStyle(.orange)
                Text(entry.weatherTemp)
                    .font(.title)
                    .fontWeight(.bold)
                Text(entry.weatherCondition)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .frame(minWidth: 80)

            Divider()

            // Market movers (right)
            VStack(alignment: .leading, spacing: 6) {
                Text("MARKETS")
                    .font(.caption2)
                    .fontWeight(.bold)
                    .foregroundStyle(.secondary)

                ForEach(Array(entry.topMovers.prefix(3).enumerated()), id: \.offset) { _, mover in
                    HStack {
                        Text(mover.symbol)
                            .font(.caption)
                            .fontWeight(.bold)
                        Spacer()
                        Text(formatChange(mover.change))
                            .font(.caption)
                            .fontWeight(.semibold)
                            .foregroundStyle(mover.change >= 0 ? .green : .red)
                    }
                }
            }
        }
        .padding()
    }

    private func formatChange(_ change: Double) -> String {
        let sign = change >= 0 ? "+" : ""
        return "\(sign)\(String(format: "%.1f", change))%"
    }
}

// MARK: - Widget Configuration

struct MorningVaultWidget: Widget {
    let kind: String = "MorningVaultWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: MorningWidgetProvider()) { entry in
            MorningVaultWidgetEntryView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("Morning Briefing")
        .description("Weather and market movers at a glance.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

// MARK: - Lock Screen Widget

struct MorningVaultLockScreenWidget: Widget {
    let kind: String = "MorningVaultLockScreenWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: MorningWidgetProvider()) { entry in
            LockScreenWidgetView(entry: entry)
        }
        .configurationDisplayName("Morning Snapshot")
        .description("Quick weather and market glance from your lock screen.")
        .supportedFamilies([.accessoryRectangular, .accessoryCircular])
    }
}

struct LockScreenWidgetView: View {
    @Environment(\.widgetFamily) var family
    var entry: MorningWidgetEntry

    var body: some View {
        switch family {
        case .accessoryRectangular:
            RectangularLockScreenView(entry: entry)
        case .accessoryCircular:
            CircularLockScreenView(entry: entry)
        default:
            RectangularLockScreenView(entry: entry)
        }
    }
}

struct RectangularLockScreenView: View {
    let entry: MorningWidgetEntry

    var body: some View {
        HStack(spacing: 6) {
            // Weather
            VStack(alignment: .leading) {
                Image(systemName: entry.weatherIcon)
                    .font(.caption)
                Text(entry.weatherTemp)
                    .font(.caption)
                    .fontWeight(.bold)
            }

            Divider()

            // Top mover
            if let top = entry.topMovers.first {
                VStack(alignment: .leading) {
                    Text(top.symbol)
                        .font(.caption2)
                        .fontWeight(.bold)
                    Text(formatChange(top.change))
                        .font(.caption2)
                        .fontWeight(.semibold)
                }
            }
        }
    }

    private func formatChange(_ change: Double) -> String {
        let sign = change >= 0 ? "+" : ""
        return "\(sign)\(String(format: "%.1f", change))%"
    }
}

struct CircularLockScreenView: View {
    let entry: MorningWidgetEntry

    var body: some View {
        ZStack {
            // Show the overall market direction as a gauge
            if let top = entry.topMovers.first {
                Gauge(value: min(abs(top.change), 5), in: 0...5) {
                    Text(top.symbol)
                } currentValueLabel: {
                    Text(formatChange(top.change))
                        .font(.caption2)
                        .fontWeight(.bold)
                }
                .gaugeStyle(.accessoryCircularCapacity)
                .tint(top.change >= 0 ? .green : .red)
            }
        }
    }

    private func formatChange(_ change: Double) -> String {
        let sign = change >= 0 ? "+" : ""
        return "\(sign)\(String(format: "%.1f", change))%"
    }
}