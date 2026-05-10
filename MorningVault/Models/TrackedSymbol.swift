import Foundation

// Shared tracked symbol model — used by both MarketsView and BriefingViewModel

struct TrackedSymbol: Codable, Identifiable, Equatable {
    var id: String { symbol }
    let symbol: String
    var entryPrice: Double?
    var updatedAt: Date?
}