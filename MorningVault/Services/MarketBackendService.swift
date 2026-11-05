import Foundation

/// Market quotes via MorningVault's own Cloudflare Worker (backend/worker) — the app never calls a third party.
enum MarketBackendService {
    /// Override via UserDefaults key `market_backend_url` when you deploy a new host.
    static var baseURL: String {
        let custom = UserDefaults.standard.string(forKey: "market_backend_url")?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if let custom, !custom.isEmpty { return custom }
        return "https://api.morningvault.app"
    }

    struct Quote: Equatable, Sendable {
        let symbol: String
        let price: Double
        let change24h: Double
        let cached: Bool
        let error: String?
    }

    fileprivate struct BatchResponse: Codable {
        let symbol: String
        let price: Double
        let change24h: Double
        let cached: Bool
        let error: String?
    }

    /// All symbols in one call: `GET /market/batch?symbols=SPY,BTC`.
    ///
    /// The worker in `backend/worker` serves this route, but it is not deployed yet; a host
    /// that answers 404 for it gets one `GET /market/<SYMBOL>` per symbol instead (same host,
    /// same proxy — the phone still never talks to a market vendor).
    static func fetchBatch(symbols: [String]) async -> [Quote] {
        let cleaned = symbols.map { $0.uppercased().trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        guard !cleaned.isEmpty else { return [] }

        var components = URLComponents(string: "\(baseURL)/market/batch")
        components?.queryItems = [URLQueryItem(name: "symbols", value: cleaned.joined(separator: ","))]
        guard let url = components?.url else { return [] }

        do {
            let (data, response) = try await URLSession.shared.data(from: url)
            guard let http = response as? HTTPURLResponse else { return [] }
            if http.statusCode == 404 {
                return await fetchIndividually(symbols: cleaned)
            }
            guard http.statusCode == 200 else { return [] }
            let decoded = try JSONDecoder().decode([BatchResponse].self, from: data)
            return decoded.map(Quote.init)
        } catch {
            return []
        }
    }

    /// One `GET /market/<SYMBOL>` per symbol, in parallel. Used only when the batch route is missing.
    static func fetchIndividually(symbols: [String]) async -> [Quote] {
        await withTaskGroup(of: Quote?.self) { group in
            for symbol in symbols {
                group.addTask { await fetchQuote(symbol: symbol) }
            }
            var quotes: [Quote] = []
            for await quote in group {
                if let quote { quotes.append(quote) }
            }
            return quotes
        }
    }

    /// `GET /market/<SYMBOL>` — the single-symbol route; 502 carries an `error` row.
    static func fetchQuote(symbol: String) async -> Quote? {
        let cleaned = symbol.uppercased().trimmingCharacters(in: .whitespaces)
        guard !cleaned.isEmpty,
              let encoded = cleaned.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed),
              let url = URL(string: "\(baseURL)/market/\(encoded)") else { return nil }
        do {
            let (data, response) = try await URLSession.shared.data(from: url)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 || http.statusCode == 502 else { return nil }
            return Quote(try JSONDecoder().decode(BatchResponse.self, from: data))
        } catch {
            return nil
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

private extension MarketBackendService.Quote {
    init(_ row: MarketBackendService.BatchResponse) {
        self.init(symbol: row.symbol, price: row.price, change24h: row.change24h, cached: row.cached, error: row.error)
    }
}
