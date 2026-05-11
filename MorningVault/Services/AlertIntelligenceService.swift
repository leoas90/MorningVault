import Foundation

/// Generates context-aware market alerts with semantic meaning.
/// Instead of "SPY down 1%", produces: "SPY at 200-day support, watching for breakdown below $510".
final class AlertIntelligenceService {

    static let shared = AlertIntelligenceService()

    private let alertStore = AlertStore.shared

    private init() {}

    // MARK: - Public API

    /// Generates contextual alerts for tracked symbols based on current prices.
    /// Call this after fetchLivePrices() completes.
    func generateAlerts(
        for symbols: [TrackedSymbol],
        prices: [String: (price: Double, change: Double)]
    ) async -> [MarketAlert] {
        var newAlerts: [MarketAlert] = []

        for tracked in symbols {
            let symbol = tracked.symbol
            guard let (price, change) = prices[symbol] else { continue }

            let alerts = await analyzeSymbol(
                symbol: symbol,
                currentPrice: price,
                change24h: change
            )
            newAlerts.append(contentsOf: alerts)
        }

        alertStore.save(newAlerts)
        return newAlerts
    }

    /// Returns all active (non-triggered) alerts from the store.
    func activeAlerts() -> [MarketAlert] {
        alertStore.load().filter { !$0.triggered }
    }

    /// Dismiss an alert.
    func dismiss(_ alert: MarketAlert) {
        alertStore.dismiss(alert)
    }

    // MARK: - Core Analysis

    private func analyzeSymbol(
        symbol: String,
        currentPrice: Double,
        change24h: Double
    ) async -> [MarketAlert] {
        var alerts: [MarketAlert] = []

        // 1. Anomaly: >3% move in either direction
        if abs(change24h) > 3.0 {
            let direction = change24h > 0 ? "surged" : "dropped"
            alerts.append(MarketAlert(
                symbol: symbol,
                alertType: .anomaly,
                message: "\(symbol) \(direction) \(String(format: "%.1f", abs(change24h)))% — unusually large move",
                priceLevel: currentPrice,
                currentPrice: currentPrice,
                context: "\(String(format: "%.1f", abs(change24h)))% single-day move"
            ))
        }

        // 2. Support level detection using cached price as reference
        if let cachedData = await sharedCache.getSymbolPrice(symbol) {
            let lastPrice = cachedData.price

            // Calculate a synthetic support level (last price is our best reference)
            // 2% below last price = support zone
            let supportLevel = lastPrice * 0.98
            let resistanceLevel = lastPrice * 1.02

            // Support: current price within 2% above the support level
            if currentPrice > supportLevel && currentPrice < lastPrice {
                alerts.append(MarketAlert(
                    symbol: symbol,
                    alertType: .support,
                    message: "\(symbol) at support — watching for drop below \(formatPrice(supportLevel))",
                    priceLevel: supportLevel,
                    currentPrice: currentPrice,
                    context: "Near \(formatPrice(lastPrice)) support"
                ))
            }

            // Resistance: current price within 2% below resistance level
            if currentPrice < resistanceLevel && currentPrice > lastPrice {
                alerts.append(MarketAlert(
                    symbol: symbol,
                    alertType: .resistance,
                    message: "\(symbol) near resistance — \(formatPrice(currentPrice))",
                    priceLevel: resistanceLevel,
                    currentPrice: currentPrice,
                    context: "Near \(formatPrice(lastPrice)) resistance"
                ))
            }

            // 3. Breakout/breakdown alerts
            let threshold = lastPrice * 0.02

            if currentPrice > lastPrice + threshold {
                alerts.append(MarketAlert(
                    symbol: symbol,
                    alertType: .breakout,
                    message: "\(symbol) broke above \(formatPrice(lastPrice)) — now \(formatPrice(currentPrice))",
                    priceLevel: lastPrice,
                    currentPrice: currentPrice,
                    context: "Above \(formatPrice(lastPrice)) resistance"
                ))
            } else if currentPrice < lastPrice - threshold {
                alerts.append(MarketAlert(
                    symbol: symbol,
                    alertType: .breakdown,
                    message: "\(symbol) dropped below \(formatPrice(lastPrice)) — now \(formatPrice(currentPrice))",
                    priceLevel: lastPrice,
                    currentPrice: currentPrice,
                    context: "Below \(formatPrice(lastPrice)) support"
                ))
            }
        }

        return alerts
    }

    // MARK: - Helpers

    private func formatPrice(_ price: Double) -> String {
        if price >= 1000 {
            return String(format: "$%.0f", price)
        } else if price >= 1 {
            return String(format: "$%.2f", price)
        } else {
            return String(format: "$%.4f", price)
        }
    }
}