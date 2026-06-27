import Foundation

/// Server-side Polygon proxy — API keys never ship in the iOS binary.
enum MarketBackendService {
    /// Override via UserDefaults key `market_backend_url` when you deploy a new host.
    static var baseURL: String {
        let custom = UserDefaults.standard.string(forKey: "market_backend_url")?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if let custom, !custom.isEmpty { return custom }
        return "https://morningvault.fly.dev"
    }

    struct Quote: Equatable, Sendable {
        let symbol: String
        let price: Double
        let change24h: Double
        let cached: Bool
        let error: String?
    }

    private struct BatchResponse: Codable {
        let symbol: String
        let price: Double
        let change24h: Double
        let cached: Bool
        let error: String?
    }

    /// `GET /market/batch?symbols=SPY,BTC`
    static func fetchBatch(symbols: [String]) async -> [Quote] {
        let cleaned = symbols.map { $0.uppercased().trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        guard !cleaned.isEmpty else { return [] }

        var components = URLComponents(string: "\(baseURL)/market/batch")
        components?.queryItems = [URLQueryItem(name: "symbols", value: cleaned.joined(separator: ","))]
        guard let url = components?.url else { return [] }

        do {
            let (data, response) = try await URLSession.shared.data(from: url)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else { return [] }
            let decoded = try JSONDecoder().decode([BatchResponse].self, from: data)
            return decoded.map {
                Quote(
                    symbol: $0.symbol,
                    price: $0.price,
                    change24h: $0.change24h,
                    cached: $0.cached,
                    error: $0.error
                )
            }
        } catch {
            return []
        }
    }

    static func formatPrice(symbol: String, price: Double) -> String {
        let crypto: Set<String> = ["BTC", "ETH", "SOL", "BNB", "XRP", "ADA", "DOGE", "DOT", "AVAX", "LINK"]
        if crypto.contains(symbol.uppercased()) {
            return price >= 1000 ? "$\(Int(price.rounded()))" : "$\(String(format: "%.2f", price))"
        }
        return "$\(String(format: "%.2f", price))"
    }
}