import SwiftUI
import Combine
import FoundationModels

/// Main briefing view model — orchestrates all data sources and AI generation
@MainActor
final class BriefingViewModel: ObservableObject {
    @Published var briefingSections: [BriefingSection] = []
    @Published var isLoading = false
    @Published var lastError: String?
    @Published var networkBadge: NetworkBadge = .local
    @Published var aiDaySummary: String? = nil

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
            await enhanceWithFoundationModels()
        }
    }

    // MARK: - Data fetchers (with cache fallback)

    private func fetchWeather() async -> WeatherData? {
        // Try cache first
        if let cached: WeatherData = await cache.get("weather", ttl: 1800) {
            return cached
        }
        // Fetch fresh
        let data = await weatherService.fetchWeather()
        if let data = data {
            await cache.setWeather(data, ttl: 1800)
        }
        return data
    }

    private func fetchHealth() async -> HealthData? {
        if let cached: HealthData = await cache.get("health", ttl: 3600) {
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
        await cache.setHealth(data, ttl: 3600)
        return data
    }

    private func fetchCalendar() async -> [CalendarEvent] {
        if let cached: [CalendarEvent] = await cache.get("calendar", ttl: 1800) {
            return cached
        }
        await calendarService.requestAuthorization()
        let events = await calendarService.fetchTodayEvents()
        await cache.setCalendar(events, ttl: 1800)
        return events
    }

    private func fetchRSS() async -> [RSSFeedData] {
        if let cached: [RSSFeedData] = await cache.get("rss", ttl: 3600) {
            return cached
        }
        let feeds = await rssService.fetchAllFeeds()
        await cache.setRSSFeeds(feeds, ttl: 3600)
        return feeds
    }

    private func fetchMarketSentiment() async -> (content: String, sentiment: String?) {
        let tracked = loadTrackedSymbols()
        var content = ""
        var sentiment: String? = nil
        var hasBullish = false
        var hasBearish = false

        for item in tracked {
            let data = await fetchSymbolData(symbol: item.symbol)
            guard let price = data?.price, price > 0 else { continue }
            let change = data?.change24h ?? 0
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

        if hasBullish && !hasBearish { sentiment = "bullish" }
        else if hasBearish && !hasBullish { sentiment = "bearish" }
        else if !tracked.isEmpty { sentiment = "neutral" }

        return (content.isEmpty ? "Market data unavailable" : content, sentiment)
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

    private var cryptoSymbols: Set<String> { ["BTC", "ETH", "SOL", "BNB", "XRP", "ADA", "DOGE", "DOT", "AVAX", "LINK"] }

    private func fetchSymbolData(symbol: String) async -> SymbolData? {
        let upper = symbol.uppercased()
        if cryptoSymbols.contains(upper) {
            return await fetchCryptoData(symbol: upper)
        }
        return await fetchStockData(symbol: upper)
    }

    private func fetchCryptoData(symbol: String) async -> SymbolData? {
        let idMap: [String: String] = ["BTC": "bitcoin", "ETH": "ethereum", "SOL": "solana",
                                       "BNB": "binancecoin", "XRP": "ripple", "ADA": "cardano",
                                       "DOGE": "dogecoin", "DOT": "polkadot", "AVAX": "avalanche-2", "LINK": "chainlink"]
        guard let id = idMap[symbol],
              let url = URL(string: "https://api.coingecko.com/api/v3/simple/price?ids=\(id)&vs_currencies=usd&include_24hr_change=true") else { return nil }
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            let json = try JSONDecoder().decode([String: [String: Double]].self, from: data)
            guard let coin = json[id], let price = coin["usd"], let change = coin["usd_24h_change"] else { return nil }
            return SymbolData(price: price, change24h: change)
        } catch { return nil }
    }

    private func fetchStockData(symbol: String) async -> SymbolData? {
        guard let url = URL(string: "https://query1.finance.yahoo.com/v8/finance/chart/\(symbol)?interval=1d&range=1d") else { return nil }
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            let json = try JSONDecoder().decode(YahooChartResponse.self, from: data)
            guard let result = json.chart?.result?.first,
                  let quote = result.indicators?.quote?.first else { return nil }
            let price = quote.close?.last ?? 0
            let open = quote.open?.first ?? price
            let change = ((price - open) / open) * 100
            return SymbolData(price: price, change24h: change)
        } catch { return nil }
    }

    // MARK: - Foundation Models enhancement (iOS 26+)

    /// Maximum tokens before we chunk the prompt into segments (≈3.5K tokens safe limit)
    private static let chunkThreshold = 3500

    /// Target per-segment token budgets (words as proxy for tokens, ~4 chars per token)
    private static let segmentBudgets: [String: Int] = [
        "health":    125,  // ≈500 tokens
        "calendar":  200,  // ≈800 tokens
        "weather":    50,  // ≈200 tokens
        "markets":    75,  // ≈300 tokens
        "rss":       500,  // ≈2000 tokens
    ]

    @available(iOS 26.0, *)
    private func enhanceWithFoundationModels() async {
        let lm = SystemLanguageModel()
        if case .unavailable(let reason) = lm.availability {
            print("[BriefingViewModel] AppleIntelligence unavailable: \(String(describing: reason))")
            return
        }

        let session = LanguageModelSession(model: lm)
        let startTime = Date()
        var aiInsight: String?
        var sentiment: String?

        // Estimate combined prompt size and decide: chunked vs single-call
        let combinedPrompt = buildBriefingPrompt()
        let estimatedTokens = combinedPrompt.count / 4  // rough approximation

        if estimatedTokens > Self.chunkThreshold {
            // Token chunking: call FM per segment, aggregate responses
            let segmentedResult = await generateChunked(session: session)
            aiInsight = segmentedResult.insight
            sentiment = segmentedResult.sentiment
        } else {
            // Single-call path (under token limit)
            let result = await generateSingle(session: session, prompt: combinedPrompt)
            if let insight = result.insight {
                aiInsight = insight
                sentiment = result.sentiment
            }
        }

        let latencyMs = Int(Date().timeIntervalSince(startTime) * 1000)
        Self.recordLatency(latencyMs)
        let p95Ms = Self.computeP95()
        print("[BriefingViewModel] FM latency: \(latencyMs)ms (p95: \(p95Ms)ms)")

        if let insight = aiInsight {
            aiDaySummary = insight
            let section = BriefingSection(
                id: "ai-insight",
                title: "AI Insight",
                icon: "🤖",
                content: insight,
                sentiment: sentiment
            )
            if let idx = briefingSections.firstIndex(where: { $0.id == "markets" }) {
                briefingSections[idx] = section
            } else {
                briefingSections.append(section)
            }
            await cache.setBriefing(BriefingData(sections: briefingSections, generatedAt: Date(), latencyMs: latencyMs), ttl: 300)
        }
    }

    // MARK: - Single-call path (under token budget)

    @available(iOS 26.0, *)
    private func generateSingle(session: LanguageModelSession, prompt: String) async -> (insight: String?, sentiment: String?) {
        do {
            let response = try await session.respond(to: prompt, generating: BriefingInsight.self)
            return (response.content.insight, response.content.sentiment)
        } catch is CancellationError {
            // Task was cancelled (e.g., user navigated away) — not an error, just abort silently
            return (nil, nil)
        } catch {
            print("[BriefingViewModel] FM single-call error: \(error.localizedDescription)")
            return ("Unable to generate insight.", nil)
        }
    }

    // MARK: - Chunked path (exceeds token budget)

    @available(iOS 26.0, *)
    private func generateChunked(session: LanguageModelSession) async -> (insight: String, sentiment: String?) {
        var segmentInsights: [String] = []

        for section in briefingSections {
            guard let budget = Self.segmentBudgets[section.id] else { continue }
            let maxChars = budget * 4
            let truncated = section.content.count > maxChars
                ? String(section.content.prefix(maxChars)) + "…"
                : section.content

            let segmentPrompt = """
            Based on this \(section.title) data: "\(truncated)"

            Provide a brief insight and classify sentiment. Respond with ONLY JSON (no markdown):
            {"text": "...", "sentiment": "bullish|bearish|neutral"}
            """

            do {
                let response = try await session.respond(to: segmentPrompt, generating: BriefingInsightText.self)
                if !response.content.text.isEmpty {
                    segmentInsights.append("\(section.title): \(response.content.text)")
                }
            } catch is CancellationError {
                // Silently skip cancelled segment — user likely navigated away; stop chunking
                break
            } catch {
                print("[BriefingViewModel] FM chunk error for \(section.id): \(error.localizedDescription)")
            }
        }

        guard !segmentInsights.isEmpty else {
            return ("Unable to generate insight.", nil)
        }

        let aggregationPrompt = """
        Combine these segment insights into a single coherent morning briefing insight (2-3 sentences).

        Segments:
        \(segmentInsights.joined(separator: "\n"))

        Respond with ONLY JSON (no markdown):
        {"text": "...", "sentiment": "bullish|bearish|neutral"}
        """

        do {
            let response = try await session.respond(to: aggregationPrompt, generating: BriefingInsightText.self)
            return (response.content.text, response.content.sentiment)
        } catch is CancellationError {
            // Aggregation cancelled — return collected segment insights rather than losing them
            guard !segmentInsights.isEmpty else {
                return (insight: "Unable to generate insight.", sentiment: nil)
            }
            return (segmentInsights.joined(separator: " "), nil)
        } catch {
            return (segmentInsights.joined(separator: " "), nil)
        }
    }

    private func buildBriefingPrompt() -> String {
        let sectionTexts = briefingSections.map { "\($0.title): \($0.content)" }.joined(separator: "\n")
        return """
You are a morning briefing assistant. Based on the following data, provide 2-3 sentences of insight or a recommendation. Be concise and actionable.

\(sectionTexts)

Respond with ONLY this JSON (no markdown):
{"insight": "...", "recommendation": "...", "sentiment": "bullish|bearish|neutral"}
"""
    }
}

// MARK: - Network Badge

enum NetworkBadge {
    case local      // green — all data local
    case external   // yellow — external non-PII fetch
    case unknown    // gray
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

// MARK: - AI Response / Structured Output

/// Codable struct for single-call structured output (full briefing prompt response)
/// Mark with @Generable so LanguageModelSession can use it with .respond(generating:)
@FoundationModels.Generable
private struct BriefingInsight: Codable {
    let insight: String
    let recommendation: String
    let sentiment: String  // "bullish" | "bearish" | "neutral"
}

/// Codable struct for per-segment chunk responses
@FoundationModels.Generable
private struct BriefingInsightText: Codable {
    let text: String
    let sentiment: String  // "bullish" | "bearish" | "neutral"
}
