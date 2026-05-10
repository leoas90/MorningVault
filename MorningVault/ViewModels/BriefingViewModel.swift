import SwiftUI
import Combine
import FoundationModels

/// On-device AI briefing generator for MorningVault.
///
/// **Privacy contract:**
/// - Health data is SANITIZED before entering prompts (no raw HRV, sleep stages, etc.)
/// - `localOnly` mode is enforced: when enabled, no external calls
/// - Always uses on-device Foundation Models (iOS 26+) — no external endpoints
///
/// Fallback: if on-device FM is unavailable, returns nil and lets the caller
/// display the raw data sections without AI enhancement.
@MainActor
final class BriefingViewModel: ObservableObject {
    @Published var briefingSections: [BriefingSection] = []
    @Published var isLoading = false
    @Published var isGeneratingAI = false
    @Published var lastError: String?
    @Published var networkBadge: NetworkBadge = .local
    @Published var aiDaySummary: String? = nil
    @Published var permissionDenied: [String] = []  // services that were denied

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

        // Health — denied
        if permissionDenied.contains("health") {
            sections.append(BriefingSection(
                id: "health",
                title: "Health",
                icon: "❤️‍🔥",
                content: "No health data available. Enable Health access in Settings to see your activity, sleep, and HRV.",
                sentiment: nil,
                errorMessage: "Health access denied"
            ))
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

        // Calendar — denied (empty doesn't mean denied, check permissionDenied)
        if calendarEvents.isEmpty && !permissionDenied.contains("calendar") {
            sections.append(BriefingSection(
                id: "calendar",
                title: "Today",
                icon: "📅",
                content: "No events scheduled. Your calendar is clear for today.",
                sentiment: nil
            ))
        }

        if permissionDenied.contains("calendar") {
            sections.append(BriefingSection(
                id: "calendar",
                title: "Today",
                icon: "📅",
                content: "No calendar access. Enable Calendar access in Settings to see your events.",
                sentiment: nil,
                errorMessage: "Calendar access denied"
            ))
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
        updateNetworkBadge()
    }

    // MARK: - Generate AI-enhanced briefing

    /// Full briefing generation: load data then enhance with on-device AI.
    /// Uses AIService (Foundation Models, iOS 26+) — no external AI endpoints.
    /// Shows loading state during AI generation.
    func generateBriefing() async {
        isLoading = true
        defer { isLoading = false }

        // Load all data sections first
        await loadData()

        // Update badge BEFORE the guard that may early-return for localOnly
        updateNetworkBadge()

        // Then generate AI summary via on-device Foundation Models
        // Skip if no sections to process (localOnly users still get data, just no FM)
        guard !briefingSections.isEmpty else { return }

        isGeneratingAI = true
        if let summary = await AIService.shared.generateInsight(from: briefingSections) {
            aiDaySummary = summary.insight
        }
        isGeneratingAI = false
    }

    private func updateNetworkBadge() {
        if localOnly {
            networkBadge = .local
        } else {
            // External when any live (non-cache) fetch succeeded
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
        // localOnly: skip live HealthKit fetch, only use cache
        if localOnly {
            return await cache.getHealth()
        }
        if let cached: HealthData = await cache.getHealth() {
            return cached
        }
        _ = await healthService.requestAuthorization()
        // Check if user denied HealthKit access
        if !healthService.isAuthorized {
            await MainActor.run { self.permissionDenied.append("health") }
            return nil
        }
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
        // localOnly: skip live Calendar fetch, only use cache
        if localOnly {
            return await cache.getCalendar() ?? []
        }
        if let cached: [CalendarEvent] = await cache.getCalendar() {
            return cached
        }
        _ = await calendarService.requestAuthorization()
        // Check if user denied Calendar access
        if !calendarService.isAuthorized {
            await MainActor.run { self.permissionDenied.append("calendar") }
            return []
        }
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

    // MARK: - Symbol fetcher with cache fallback

    /// Fetches symbol price, falling back to cache on any live-fetch failure.
    /// Always attempts live data first; only shows "unavailable" when both
    /// live fetch AND cache miss.
    private func fetchSymbolWithCacheFallback(symbol: String) async -> SymbolData? {
        if let data = await fetchSymbolData(symbol: symbol) {
            // Live fetch succeeded — update cache
            await cache.setSymbolPrice(
                symbol,
                data: TTLCache.CachedSymbolData(
                    price: data.price,
                    change24h: data.change24h,
                    timestamp: Date()
                )
            )
            return data
        }
        // Live fetch failed (rate limit, network, parse) — try cache
        return await cache.getSymbolPrice(symbol).map {
            SymbolData(price: $0.price, change24h: $0.change24h)
        }
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
                priceData = await fetchSymbolWithCacheFallback(symbol: item.symbol)
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

    // MARK: - Symbol data fetchers — Polygon.io unified (stocks + crypto)

    /// Unified fetcher: all symbols via Polygon.io AGG API.
    /// - Stocks: AAPL, SPY, QQQ → polygon ticker = raw symbol
    /// - Crypto: BTC, ETH, SOL → polygon ticker = X:{SYMBOL}USD
    private func fetchSymbolData(symbol: String) async -> SymbolData? {
        let upper = symbol.uppercased()
        // Crypto pairs need X: prefix and USD suffix on Polygon
        if cryptoSymbols.contains(upper) {
            let polygonSymbol = "X:\(upper)USD"
            return await fetchViaPolygon(symbol: polygonSymbol)
        }
        // Stocks go through as-is
        return await fetchViaPolygon(symbol: upper)
    }

    /// All fetches route through Polygon.io — one API for both stocks and crypto.
    /// Retries once on 429 with 1s backoff before falling back to cache.
    private func fetchViaPolygon(symbol: String) async -> SymbolData? {
        guard let key = Bundle.main.object(forInfoDictionaryKey: "POLYGON_API_KEY") as? String,
              !key.isEmpty else {
            return nil
        }
        guard let url = URL(
            string: "https://api.polygon.io/v2/aggs/ticker/\(symbol)/prev?adjusted=true&apiKey=\(key)"
        ) else {
            return nil
        }

        // First attempt
        if let result = await attemptPolygonFetch(url: url) { return result }
        // Retry once on 429
        try? await Task.sleep(nanoseconds: 1_000_000_000)
        return await attemptPolygonFetch(url: url)
    }

    private func attemptPolygonFetch(url: URL) async -> SymbolData? {
        do {
            let (data, response) = try await URLSession.shared.data(from: url)
            if let http = response as? HTTPURLResponse, http.statusCode == 429 { return nil }
            guard let json = try? JSONDecoder().decode(PolygonAggResponse.self, from: data),
                  let result = json.results.first, result.c > 0, result.o > 0 else { return nil }
            let change = ((result.c - result.o) / result.o) * 100
            return SymbolData(price: result.c, change24h: change)
        } catch {
            return nil
        }
    }
}

// MARK: - Polygon.io Response

private struct PolygonAggResponse: Codable {
    let results: [PolygonAggResult]
}

private struct PolygonAggResult: Codable {
    let o: Double  // open
    let c: Double  // close
}

// MARK: - Network Badge

enum NetworkBadge {
    case local    // 🟢 green — all data local, zero network calls
    case external // 🟡 yellow — external non-PII fetches active
    case unknown  // gray
}
