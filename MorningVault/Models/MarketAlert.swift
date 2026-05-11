import Foundation

/// Contextual market alerts that go beyond simple price change notifications.
/// Each alert carries semantic context about WHY the alert matters.
struct MarketAlert: Identifiable, Codable {
    let id: UUID
    let symbol: String
    let alertType: AlertType
    let message: String       // Human-readable: "at 200-day support, watching for breakdown"
    let priceLevel: Double    // The price level being watched, e.g. 510.0
    let currentPrice: Double  // Price when alert was created
    let triggered: Bool
    let createdAt: Date
    let context: String        // Technical: "200-day moving average", "52-week high", "2x average volume"

    init(
        id: UUID = UUID(),
        symbol: String,
        alertType: AlertType,
        message: String,
        priceLevel: Double,
        currentPrice: Double,
        triggered: Bool = false,
        createdAt: Date = Date(),
        context: String
    ) {
        self.id = id
        self.symbol = symbol
        self.alertType = alertType
        self.message = message
        self.priceLevel = priceLevel
        self.currentPrice = currentPrice
        self.triggered = triggered
        self.createdAt = createdAt
        self.context = context
    }

    /// Formatted price level string for display
    var formattedPriceLevel: String {
        if priceLevel >= 1000 {
            return String(format: "$%.0f", priceLevel)
        } else if priceLevel >= 1 {
            return String(format: "$%.2f", priceLevel)
        } else {
            return String(format: "$%.4f", priceLevel)
        }
    }
}

enum AlertType: String, Codable {
    case support      // Price at or near a key support level
    case resistance   // Price at or near a key resistance level
    case volume       // Volume significantly elevated
    case anomaly      // Price movement outside normal bounds (>3%)
    case news         // News-driven alert (placeholder for future)
    case breakdown     // Support level broken — watch for more downside
    case breakout      // Resistance level broken — watch for upside continuation
    case high         // At or near all-time or period high
    case low          // At or near all-time or period low

    var icon: String {
        switch self {
        case .support:  return "arrow.down.to.line"
        case .resistance: return "arrow.up.to.line"
        case .volume:   return "chart.bar.fill"
        case .anomaly:  return "exclamationmark.triangle.fill"
        case .news:     return "newspaper.fill"
        case .breakdown: return "arrow.down.right"
        case .breakout:  return "arrow.up.right"
        case .high:     return "crown.fill"
        case .low:      return "arrow.down.circle.fill"
        }
    }

    var color: String {
        switch self {
        case .support, .low: return "blue"
        case .resistance, .high: return "green"
        case .volume: return "orange"
        case .anomaly, .breakdown: return "red"
        case .breakout: return "green"
        case .news: return "purple"
        }
    }
}

/// Stores active alerts in UserDefaults
final class AlertStore {
    static let shared = AlertStore()

    private let key = "active_market_alerts"
    private let defaults = UserDefaults.standard

    private init() {}

    func save(_ alerts: [MarketAlert]) {
        if let data = try? JSONEncoder().encode(alerts) {
            defaults.set(data, forKey: key)
        }
    }

    func load() -> [MarketAlert] {
        guard let data = defaults.data(forKey: key),
              let alerts = try? JSONDecoder().decode([MarketAlert].self, from: data) else {
            return []
        }
        return alerts
    }

    func dismiss(_ alert: MarketAlert) {
        var alerts = load()
        alerts.removeAll { $0.id == alert.id }
        save(alerts)
    }

    func clearAll() {
        defaults.removeObject(forKey: key)
    }
}