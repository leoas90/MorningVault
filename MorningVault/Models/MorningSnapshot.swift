import Foundation

/// At-a-glance data for the Brief tab hero card.
struct MorningSnapshot: Equatable {
    var weatherIcon: String?
    var weatherLine: String?
    var location: String?
    var calendarLine: String?
    var marketQuotes: [MorningSnapshotQuote]
    var marketsStatus: MarketsStatus
    /// Mirrors Settings → Weather toggle so the card doesn't blame Settings when it's on.
    var weatherEnabled: Bool
    var weatherNeedsLocation: Bool
    var updatedAt: Date?

    enum MarketsStatus: Equatable {
        case loading
        case live
        case cached
        case unavailable
    }

    static let empty = MorningSnapshot(
        weatherIcon: nil,
        weatherLine: nil,
        location: nil,
        calendarLine: nil,
        marketQuotes: [],
        marketsStatus: .loading,
        weatherEnabled: true,
        weatherNeedsLocation: false,
        updatedAt: nil
    )
}

struct MorningSnapshotQuote: Identifiable, Equatable {
    let symbol: String
    let priceText: String
    let change24h: Double
    var id: String { symbol }

    var changeText: String {
        let sign = change24h >= 0 ? "+" : ""
        return "\(sign)\(String(format: "%.2f", change24h))%"
    }

    var isPositive: Bool { change24h >= 0 }
}