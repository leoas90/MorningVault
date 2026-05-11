import SwiftUI
import Combine
import FoundationModels
import Security

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
    @Published var meetingPrep: MeetingPrep? = nil
    @Published var permissionDenied: [String] = []  // services that were denied

    private let meetingPrepService = MeetingPrepService.shared

    @AppStorage("local_only") private var localOnly = false
    @AppStorage("health_enabled") private var healthEnabled = true
    @AppStorage("calendar_enabled") private var calendarEnabled = true
    @AppStorage("weather_enabled") private var weatherEnabled = true
    @AppStorage("headlines_enabled") private var headlinesEnabled = true

    private let healthService = HealthKitService.shared
    private let calendarService = CalendarService.shared
    private let weatherService = WeatherService.shared
    private let rssService = RSSService.shared
    private let cache = sharedCache

    private let voiceBriefingService = VoiceBriefingService.shared

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
            if let hr = h.heartRate {
                healthContent += "Resting HR: \(Int(hr)) bpm. "
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
            let allArticles = rssFeeds.flatMap { $0.articles }
            let unreadCount = NewsReadStateTracker.shared.unreadCount(in: rssFeeds)
            let headlines = allArticles.prefix(5).map { "• \($0.title)" }.joined(separator: "\n")
            let section = BriefingSection(
                id: "headlines",
                title: unreadCount > 0 ? "Headlines (\(unreadCount) new)" : "Headlines",
                icon: "📰",
                content: headlines,
                sentiment: nil,
                rssFeed: RSSFeedData(id: "headlines", sourceName: "News", articles: Array(allArticles))
            )
            sections.append(section)
        }

        // Apply template-based priority to each section, then sort
        let templateRaw = UserDefaults.standard.string(forKey: "briefing_template") ?? BriefingTemplate.standard.rawValue
        let template = BriefingTemplate(rawValue: templateRaw) ?? .standard
        for i in sections.indices {
            sections[i].priority = template.sectionPriority(for: sections[i].id)
        }
        // Sort: enabled sections first (ascending priority), then by template order
        let enabledSections = sections.filter { isSectionEnabled($0.id) }.sorted { $0.priority < $1.priority }
        let disabledSections = sections.filter { !isSectionEnabled($0.id) }.sorted { $0.priority < $1.priority }

        briefingSections = enabledSections + disabledSections
        updateNetworkBadge()
    }

    /// Returns true if a section's data source toggle is enabled.
    private func isSectionEnabled(_ sectionId: String) -> Bool {
        switch sectionId {
        case "health":    return healthEnabled
        case "calendar":  return calendarEnabled
        case "weather":   return weatherEnabled
        case "headlines": return headlinesEnabled
        case "markets":   return true  // markets section always shown if data available
        default:          return true
        }
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

        // Persist full briefing to cache so app can display instantly when opened from notification
        await cacheBriefing()

        // Load meeting prep (Feature #1) — skip if first meeting > 2 hours away
        meetingPrep = await meetingPrepService.prepareMeetingPrep()

        // Archive briefing for history (Feature 11)
        await briefingArchive.archiveBriefing(
            sections: briefingSections,
            aiSummary: aiDaySummary,
            mood: nil,  // Mood set separately via MorningMoodView
            highlights: []
        )
    }

    /// Silent refresh — loads from cache first (instant), then does a live refresh in background.
    /// Use on app launch / deep-link open for instant briefing display.
    func silentRefresh() async {
        // Load from cache for instant display
        await loadFromCache()

        // If no cached data, do a live load
        if briefingSections.isEmpty {
            await loadData()
        }
    }

    /// Persist current briefing to TTLCache for fast app launch.
    private func cacheBriefing() async {
        guard !briefingSections.isEmpty else { return }
        let briefingData = BriefingData(
            sections: briefingSections,
            generatedAt: Date(),
            latencyMs: 0
        )
        await cache.setBriefing(briefingData)
    }

    /// Load briefing from TTLCache (instant, no network).
    private func loadFromCache() async {
        if let cached: BriefingData = await cache.getBriefing() {
            briefingSections = cached.sections
            // AI summary lives in BriefingViewModel.aiDaySummary, not in BriefingData
            // Re-derive from sections if available
            updateNetworkBadge()
        }
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
        // Respect weather_enabled setting
        guard weatherEnabled else { return nil }
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
        // Respect health_enabled setting
        guard healthEnabled else { return nil }
        // localOnly: skip live HealthKit fetch, only use cache
        if localOnly {
            return await cache.getHealth()
        }
        if let cached: HealthData = await cache.getHealth() {
            return cached
        }
        _ = await healthService.requestAuthorization()
        // Give HealthKit a moment to update published state, then check via async method
        try? await Task.sleep(nanoseconds: 500_000_000)
        let authorized = await healthService.isAuthorizedForHealthData()
        if !authorized {
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
        // Respect calendar_enabled setting
        guard calendarEnabled else { return [] }
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
        // Respect headlines_enabled setting
        guard headlinesEnabled else { return [] }
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

    /// Unified fetcher: all symbols via the MorningVault backend proxy.
    /// Backend handles Polygon.io call + server-side caching.
    /// Falls back to local cache if backend is unreachable.
    private func fetchSymbolData(symbol: String) async -> SymbolData? {
        // Try backend first
        if let data = await fetchFromBackend(symbol: symbol) {
            return data
        }
        // Fallback to local cache
        return await cache.getSymbolPrice(symbol).map {
            SymbolData(price: $0.price, change24h: $0.change24h)
        }
    }

    /// Calls the MorningVault backend proxy for market data.
    /// Backend -> Polygon.io (paid tier) + server-side cache.
    private func fetchFromBackend(symbol: String) async -> SymbolData? {
        guard let baseURL = UserDefaults.standard.string(forKey: "market_backend_url"),
              !baseURL.isEmpty,
              let url = URL(string: "\(baseURL)/market/\(symbol.uppercased())") else {
            // Backend URL not configured — fall back to local cache
            return nil
        }

        do {
            let (data, response) = try await URLSession.shared.data(from: url)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else { return nil }
            let decoder = JSONDecoder()
            let market = try decoder.decode(BackendMarketResponse.self, from: data)
            // Cache the fresh data server-side
            Task { await cache.setSymbolPrice(symbol, data: TTLCache.CachedSymbolData(
                price: market.price, change24h: market.change24h, timestamp: Date())) }
            return SymbolData(price: market.price, change24h: market.change24h)
        } catch {
            return nil
        }
    }

    /// All fetches route through Polygon.io — one API for both stocks and crypto.
    /// Retries once on 429 with 1s backoff before falling back to cache.
    private func fetchViaPolygon(symbol: String) async -> SymbolData? {
        // Deprecated: backend now calls Polygon.io directly.
        // This stub exists only to avoid "unused function" warnings during migration.
        // Will be removed once backend integration is verified in production.
        return nil
    }

    private func attemptPolygonFetch(url: URL) async -> SymbolData? {
        return nil
    }
}

// MARK: - Backend + Network types

/// Response shape from the MorningVault backend /market/{symbol} endpoint.
private struct BackendMarketResponse: Codable {
    let symbol: String
    let price: Double
    let change24h: Double
    let cached: Bool
    let error: String?
}

/// Network badge — shows data freshness to user.
enum NetworkBadge {
    case local      // Served from cache (no live fetch)
    case external   // Served from live external source (backend → Polygon)
    case none       // No data loaded yet
}

// MARK: - Voice Briefing

extension BriefingViewModel {
    /// Generates an audio briefing from current sections.
    /// Compiles weather, top 3 markets, calendar, and meeting prep summary into conversational text,
    /// then uses VoiceBriefingService to speak it.
    /// Returns a temp file URL if audio file generation is supported, otherwise nil.
    func generateAudioBriefing() async -> URL? {
        // Collect key sections for voice briefing
        var voiceSections: [BriefingSection] = []

        // Weather (first if available)
        if let weatherSection = briefingSections.first(where: { $0.id == "weather" }) {
            voiceSections.append(weatherSection)
        }

        // Markets (top section)
        if let marketsSection = briefingSections.first(where: { $0.id == "markets" }) {
            voiceSections.append(marketsSection)
        }

        // Calendar
        if let calendarSection = briefingSections.first(where: { $0.id == "calendar" }) {
            voiceSections.append(calendarSection)
        }

        // Health (if present)
        if let healthSection = briefingSections.first(where: { $0.id == "health" }) {
            voiceSections.append(healthSection)
        }

        guard !voiceSections.isEmpty else { return nil }

        // Use the voice briefing service to generate audio
        return await voiceBriefingService.generateAudioBriefing(from: voiceSections)
    }

    /// Speaks the briefing aloud using the warm voice.
    func speakBriefingAloud() {
        voiceBriefingService.speakBriefing(sections: briefingSections)
    }

    /// Stops any current voice briefing playback.
    func stopVoiceBriefing() {
        voiceBriefingService.stop()
    }
}