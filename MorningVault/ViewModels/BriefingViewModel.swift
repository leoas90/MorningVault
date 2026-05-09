import SwiftUI
import Combine
import FoundationModels

/// Main briefing view model — orchestrates all data sources and AI generation.
///
/// AI enhancement is delegated to `AIService`, which enforces:
/// - On-device-only processing via Foundation Models
/// - `localOnly` guard (no external AI routing when enabled)
/// - Health data sanitization before entering FM prompts
@MainActor
final class BriefingViewModel: ObservableObject {
    @Published var briefingSections: [BriefingSection] = []
    @Published var isLoading = false
    @Published var lastError: String?
    @Published var networkBadge: NetworkBadge = .local
    @Published var aiDaySummary: String? = nil

    @AppStorage("local_only") private var localOnly = false

    private let healthService = HealthKitService.shared
    private let calendarService = CalendarService.shared
    private let weatherService = WeatherService.shared
    private let rssService = RSSService.shared
    private let cache = sharedCache

    // MARK: - Latency instrumentation

    /// Ring buffer of last N FM call latencies (milliseconds)
    private static var fmLatencyHistory: [Int] = []
    private static let latencyHistoryCapacity = 10

    private static func recordLatency(_ ms: Int) {
        fmLatencyHistory.append(ms)
        if fmLatencyHistory.count > latencyHistoryCapacity {
            fmLatencyHistory.removeFirst()
        }
    }

    private static func computeP95() -> Int {
        guard !fmLatencyHistory.isEmpty else { return 0 }
        let sorted = fmLatencyHistory.sorted()
        let index = Int(Double(sorted.count - 1) * 0.95)
        return sorted[index]
    }

    // MARK: - Load all data then generate

    func loadData() async {
        isLoading = true
        defer { isLoading = false }

        // Fetch all sources concurrently
        async let health = fetchHealth()
        async let weather = fetchWeather()
        async let calendar = fetchCalendar()
        async let rss = fetchRSS()

        let (healthData, weatherData, calendarEvents, rssFeeds) = await (health, weather, calendar, rss)

        // Build sections from raw data (before AI processing)
        var sections: [BriefingSection] = []

        // Weather section
        if let w = weatherData {
            sections.append(BriefingSection(
                id: "weather",
                title: "Weather",
                icon: w.conditionIcon,
                content: "\(w.temperatureC)°C (\(w.condition)) in \(w.location). Feels like \(w.feelsLikeC)°C. Humidity \(w.humidity)%. \(w.uvWarning ?? "")",
                sentiment: nil
            ))
            await cache.setWeather(w)
        }

        // Health section
        if let h = healthData {
            var healthContent = ""
            if let sleep = h.sleep {
                healthContent += "Last night: \(sleep.asleepFormatted) asleep (of \(sleep.inBedFormatted) in bed). "
            }
            if let steps = h.steps {
                healthContent += "Today: \(steps) steps. "
            }
            if let hrv = h.hrv {
                healthContent += "HRV: \(Int(hrv))ms. "
            }
            if !healthContent.isEmpty {
                sections.append(BriefingSection(
                    id: "health",
                    title: "Health",
                    icon: "❤️‍🔥",
                    content: healthContent,
                    sentiment: nil
                ))
            }
            await cache.setHealth(h)
        }

        // Calendar section
        if !calendarEvents.isEmpty {
            let eventList = calendarEvents.prefix(5).map { "\($0.timeFormatted) — \($0.title)" }.joined(separator: "\n")
            sections.append(BriefingSection(
                id: "calendar",
                title: "Today",
                icon: "📅",
                content: eventList,
                sentiment: nil
            ))
            await cache.setCalendar(calendarEvents)
        }

        // Market section (BTC + SPY/QQQ sentiment)
        let marketSentiment = await fetchMarketSentiment()
        sections.append(BriefingSection(
            id: "markets",
            title: "Markets",
            icon: "📈",
            content: marketSentiment.content,
            sentiment: marketSentiment.sentiment
        ))

        // RSS headlines
        if !rssFeeds.isEmpty {
            let headlines = rssFeeds.flatMap { $0.articles }.prefix(5).map { "• \($0.title)" }.joined(separator: "\n")
            sections.append(BriefingSection(
                id: "headlines",
                title: "Headlines",
                icon: "📰",
                content: headlines,
                sentiment: nil
            ))
        }

        briefingSections = sections
    }

    // MARK: - Generate AI-enhanced briefing

    func generateBriefing() async {
        isLoading = true
        defer { isLoading = false }

        await loadData()

        // If FoundationModels is available, enhance with AI
        if #available(iOS 26.0, *) {
            await enhanceWithAI()
        }
    }

    // MARK: - AI Service delegation

    /// AI enhancement via AIService — always on-device, localOnly guard enforced.
    /// Implemented per GATE-3-FOUNDATION-MODELS spec: chunking, structured output,
    /// graceful degradation, <5s latency target on physical device.
    @available(iOS 26.0, *)
    private func enhanceWithAI() async {
        guard let result = await AIService.shared.generateInsight(
            from: briefingSections,
            localOnly: localOnly
        ) else { return }
        aiDaySummary = result.insight
    }

    /// Foundation Models entry point per SPEC.
    /// Falls back gracefully when FM is unavailable (sets aiDaySummary = nil, no crash).
    @available(iOS 26.0, *)
    private func enhanceWithFoundationModels() async {
        guard let result = await AIService.shared.generateInsight(
            from: briefingSections,
            localOnly: localOnly
        ) else {
            aiDaySummary = nil
            return
        }
        aiDaySummary = result.insight
    }

    private func updateNetworkBadge() {
        if localOnly {
            networkBadge = .local
        } else {
            networkBadge = .external
        }
    }

    // MARK: - Data fetchers (with cache fallback)

    private func fetchWeather() async -> WeatherData? {
        if localOnly {
            return await cache.getWeather()
        }
        if let cached: WeatherData = await cache.getWeather() {
            return cached
        }
        let data = await weatherService.fetchWeather()
        if let data = data {
            await cache.setWeather(data)
        }
        return data
    }

    private func fetchHealth() async -> HealthData? {
        if let cached: HealthData = await cache.getHealth() {
            return cached
        }
        _ = await healthService.requestAuthorization()
        async let sleep = healthService.fetchLastNightSleep()
        async let steps = healthService.fetchTodaySteps()
        async let cals = healthService.fetchTodayActiveCalories()
        async let hrv = healthService.fetchLatestHRV()
        async let hr = healthService.fetchLatestHeartRate()

        let data = HealthData(
            sleep: await sleep,
            steps: await steps,
            activeCalories: await cals,
            hrv: await hrv,
            heartRate: await hr,
            fetchedAt: Date()
        )
        await cache.setHealth(data)
        return data
    }

    private func fetchCalendar() async -> [CalendarEvent] {
        if let cached: [CalendarEvent] = await cache.getCalendar() {
            return cached
        }
        _ = await calendarService.requestAuthorization()
        let events = await calendarService.fetchTodayEvents()
        await cache.setCalendar(events)
        return events
    }

    private func fetchRSS() async -> [RSSFeedData] {
        if localOnly {
            return await cache.getRSSFeeds() ?? []
        }
        if let cached: [RSSFeedData] = await cache.getRSSFeeds() {
            return cached
        }
        let feeds = await rssService.fetchAllFeeds()
        await cache.setRSSFeeds(feeds)
        return feeds
    }

    // MARK: - Scalable per-symbol market fetch

    /// Fetches market sentiment using per-symbol cache keys.
    /// Each symbol is cached independently — backend slot-in ready.
    private func fetchMarketSentiment() async -> (content: String, sentiment: String?) {
        let useCache = localOnly
        return await assembleMarketContent(tracked: loadTrackedSymbols(), useCache: useCache)
    }

    private func assembleMarketContent(
        tracked: [(symbol: String, entryPrice: Double?)],
        useCache: Bool
    ) async -> (content: String, sentiment: String?) {
        var content = ""
        var sentiment: String? = nil
        var hasBullish = false
        var hasBearish = false
        var allFailed = true

        for item in tracked {
            let priceData: SymbolData?
            if useCache {
                priceData = await cache.getSymbolPrice(item.symbol).map {
                    SymbolData(price: $0.price, change24h: $0.change24h)
                }
            } else {
                priceData = await fetchSymbolData(symbol: item.symbol)
                if let pd = priceData {
                    await cache.setSymbolPrice(
                        item.symbol,
                        data: TTLCache.CachedSymbolData(
                            price: pd.price,
                            change24h: pd.change24h,
                            timestamp: Date()
                        )
                    )
                }
            }

            guard let data = priceData else { continue }
            allFailed = false

            let price = data.price
            let change = data.change24h
            let arrow = change >= 0 ? "↑" : "↓"
            content += "\(item.symbol): \(formatPrice(item.symbol, price)) \(arrow)\(String(format: change >= 0 ? "%.2f" : "%.2f", abs(change)))%"
            if let entry = item.entryPrice, entry > 0 {
                let pnl = ((price - entry) / entry) * 100
                let pnlArrow = pnl >= 0 ? "+" : ""
                content += " | P&L: \(pnlArrow)\(String(format: "%.1f", pnl))%"
            }
            content += "\n"

            if change >= 2 { hasBullish = true }
            if change <= -2 { hasBearish = true }
        }

        if allFailed || content.isEmpty {
            content = "market data unavailable"
        }

        if hasBullish && !hasBearish { sentiment = "bullish" }
        else if hasBearish && !hasBullish { sentiment = "bearish" }
        else if !tracked.isEmpty { sentiment = "neutral" }

        return (content.isEmpty ? "market data unavailable" : content, sentiment)
    }

    private struct SymbolData { let price: Double; let change24h: Double }

    private func loadTrackedSymbols() -> [(symbol: String, entryPrice: Double?)] {
        guard let data = UserDefaults.standard.data(forKey: "tracked_symbols"),
              let decoded = try? JSONDecoder().decode([TrackedSymbolCodable].self, from: data) else {
            return [("BTC", nil), ("SPY", nil)]
        }
        return decoded.map { ($0.symbol, $0.entryPrice) }
    }

    private struct TrackedSymbolCodable: Codable {
        let symbol: String
        var entryPrice: Double?
    }

    private func formatPrice(_ symbol: String, _ price: Double) -> String {
        if cryptoSymbols.contains(symbol.uppercased()) {
            return "$\(Int(price))"
        }
        return "$\(String(format: "%.2f", price))"
    }

    private var cryptoSymbols: Set<String> {
        ["BTC", "ETH", "SOL", "BNB", "XRP", "ADA", "DOGE", "DOT", "AVAX", "LINK"]
    }

    // MARK: - Symbol data fetchers

    private func fetchSymbolData(symbol: String) async -> SymbolData? {
        let upper = symbol.uppercased()
        if cryptoSymbols.contains(upper) {
            return await fetchCryptoData(symbol: upper)
        }
        return await fetchStockData(symbol: upper)
    }

    private func fetchCryptoData(symbol: String) async -> SymbolData? {
        let idMap: [String: String] = [
            "BTC": "bitcoin", "ETH": "ethereum", "SOL": "solana",
            "BNB": "binancecoin", "XRP": "ripple", "ADA": "cardano",
            "DOGE": "dogecoin", "DOT": "polkadot", "AVAX": "avalanche-2",
            "LINK": "chainlink"
        ]
        guard let id = idMap[symbol],
              let url = URL(string: "https://api.coingecko.com/api/v3/simple/price?ids=\(id)&vs_currencies=usd&include_24hr_change=true") else {
            return nil
        }
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            let json = try JSONDecoder().decode([String: [String: Double]].self, from: data)
            guard let coin = json[id], let price = coin["usd"], let change = coin["usd_24h_change"], price > 0 else {
                return nil
            }
            return SymbolData(price: price, change24h: change)
        } catch {
            return nil
        }
    }

    private func fetchStockData(symbol: String) async -> SymbolData? {
        // ⚠️ Yahoo Finance — legal flag still open for stocks.
        // Replace with Finnhub or Alpha Vantage before App Store submission.
        // CoinGecko handles crypto with no flag.
        guard let url = URL(string: "https://query1.finance.yahoo.com/v8/finance/chart/\(symbol)?interval=1d&range=1d") else {
            return nil
        }
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            let json = try JSONDecoder().decode(YahooChartResponse.self, from: data)
            guard let result = json.chart?.result?.first,
                  let quote = result.indicators?.quote?.first,
                  let close = quote.close?.last, close > 0 else {
                return nil
            }
            let open = quote.open?.first ?? close
            let change = ((close - open) / open) * 100
            return SymbolData(price: close, change24h: change)
        } catch {
            return nil
        }
    }
}

// MARK: - Network Badge

enum NetworkBadge {
    case local    // 🟢 green — all data local, zero network calls
    case external // 🟡 yellow — external non-PII fetches active
    case unknown  // gray
}

// MARK: - Yahoo Finance Response

private struct YahooChartResponse: Codable {
    let chart: ChartResult?
}

private struct ChartResult: Codable {
    let result: [ChartQuote]?
}

private struct ChartQuote: Codable {
    let indicators: Indicators?
}

private struct Indicators: Codable {
    let quote: [QuoteData]?
}

private struct QuoteData: Codable {
    let open: [Double]?
    let close: [Double]?
}
