import SwiftUI
import Combine
#if canImport(FoundationModels)
import FoundationModels
#endif
import Security
import MeetingNotesKit

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
    @Published var hasLoaded = false  // guard: only load once per session, not on every tab appear
    /// Previews: injected sample data; refreshes and generation are no-ops.
    var isPreview = false
    @Published var isGeneratingAI = false
    @Published var lastError: String?
    @Published var networkBadge: NetworkBadge = .local
    @Published var aiDaySummary: String? = nil
    /// Up to 3 lines on what changed since the last briefing (on-device, no model).
    @Published var sinceYesterday: [String] = []
    @Published var meetingPrep: MeetingPrep? = nil
    @Published var permissionDenied: [String] = []  // services that were denied
    @Published var morningSnapshot: MorningSnapshot = .empty
    /// Sparkline inputs per tracked symbol, filled alongside the markets section text.
    @Published var marketSeries: [String: MarketSeries] = [:]

    private let meetingPrepService = MeetingPrepService.shared
    private static let snapshotSymbols = ["SPY", "BTC"]

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

    /// Coalesce overlapping launch/foreground refreshes (TestFlight SIGSEGV in Combine Published).
    private var loadDataInFlight: Task<Void, Never>?
    private var silentRefreshInFlight: Task<Void, Never>?

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

    func loadData(force: Bool = false) async {
        if hasLoaded && !force { return }
        if let loadDataInFlight {
            // Never run two loads at once: a forced refresh waits for the in-flight one, then runs.
            await loadDataInFlight.value
            if !force { return }
        }

        let task = Task { @MainActor in
            await self.performLoadData(force: force)
        }
        loadDataInFlight = task
        await task.value
        loadDataInFlight = nil
    }

    private func performLoadData(force: Bool) async {
        if hasLoaded && !force { return }
        isLoading = true
        defer { hasLoaded = true; isLoading = false }

        if force {
            permissionDenied = []
        }

        let units = UnitsPreference.current
        UnitsPreference.mirrorToAppGroup()

        // Fetch all sources concurrently
        async let health = fetchHealth(forceLive: force)
        async let weather = fetchWeather(forceLive: force)
        async let calendar = fetchCalendar(forceLive: force)
        async let rss = fetchRSS(forceLive: force)

        let (healthData, weatherData, calendarEvents, rssFeeds) = await (health, weather, calendar, rss)

        // Build sections from raw data (before AI processing)
        var sections: [BriefingSection] = []

        // Weather section
        if let w = weatherData {
            sections.append(BriefingSection(
                id: "weather",
                title: "Weather",
                icon: w.conditionIcon,
                content: "\(units.formatTemperature(celsius: w.temperatureC)) (\(w.condition)) in \(w.location). Feels like \(units.formatTemperature(celsius: w.feelsLikeC)). Humidity \(w.humidity)%. Wind \(units.formatSpeed(kph: w.windKph)) \(w.windDirection). \(w.uvWarning ?? "")",
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

        // Household checklist (Settings > Trackers). The rows come from ChecklistViewModel;
        // the section is the slot in the Brief.
        if BriefSectionPrefs.isEnabled("today") {
            sections.append(BriefingSection(id: "today", title: "Today", icon: "checklist", content: "", sentiment: nil))
            // Morning refresh: rebuild the calendar suggestions from this phone's selected calendars.
            await SuggestionEngine.refreshCacheForNow()
            await ChecklistViewModel.shared.load()
        }

        // Water tracker (Settings > Trackers): one row after Today, rendered by WaterBriefRow.
        if BriefSectionPrefs.isEnabled("water") {
            sections.append(BriefingSection(id: "water", title: "Water", icon: "drop", content: "", sentiment: nil))
        }

        // Market section (BTC + SPY/QQQ sentiment). Off in Settings > Brief sections: no fetch.
        if BriefSectionPrefs.isEnabled("markets") {
            let marketSentiment = await fetchMarketSentiment()
            sections.append(BriefingSection(
                id: "markets",
                title: "Markets",
                icon: "📈",
                content: marketSentiment.content,
                sentiment: marketSentiment.sentiment
            ))
        } else {
            marketSeries = [:]
        }

        // RSS headlines
        let headlineCount = BriefSectionPrefs.headlineCount
        if !rssFeeds.isEmpty, headlineCount > 0 {
            // Settings > Data sources > Headlines in brief decides how many stories make it.
            let shown = Array(rssFeeds.flatMap { $0.articles }.prefix(headlineCount))
            let shownFeed = RSSFeedData(id: "headlines", sourceName: "News", articles: shown)
            let unreadCount = NewsReadStateTracker.shared.unreadCount(in: [shownFeed])
            let headlines = shown.map { "• \($0.title)" }.joined(separator: "\n")
            let section = BriefingSection(
                id: "headlines",
                title: unreadCount > 0 ? "Headlines (\(unreadCount) new)" : "Headlines",
                icon: "📰",
                content: headlines,
                sentiment: nil,
                rssFeed: shownFeed
            )
            sections.append(section)
        }

        // Apply template-based priority to each section, then sort
        let templateRaw = UserDefaults.standard.string(forKey: "briefing_template") ?? BriefingTemplate.standard.rawValue
        let template = BriefingTemplate(rawValue: templateRaw) ?? .standard
        for i in sections.indices {
            sections[i].priority = template.sectionPriority(for: sections[i].id)
        }
        // A turned-off section is left out whatever the template says: the toggle wins.
        briefingSections = sections.filter { BriefSectionPrefs.isEnabled($0.id) }.sorted { $0.priority < $1.priority }
        updateNetworkBadge()
        await refreshMorningSnapshot(weather: weatherData, calendarCount: calendarEvents.count)

        let todayDigest = SinceYesterday.digest(
            weather: weatherData,
            events: calendarEvents,
            headlines: rssFeeds.flatMap { $0.articles }.map(\.title),
            health: healthData
        )
        // Always record today's digest so tomorrow's diff has something to compare against;
        // only show the result when the section is on.
        var changes = SinceYesterday.update(with: todayDigest)
        if let startOfYesterday = Calendar.current.date(byAdding: .day, value: -1, to: Calendar.current.startOfDay(for: Date())) {
            do {
                let open = try MeetingDigest.openActionItems(since: startOfYesterday)
                if let first = open.first {
                    changes.append(open.count == 1
                        ? "Open from a meeting: \(first)."
                        : "\(open.count) open meeting action items, starting with: \(first).")
                }
            } catch {
                // Say so instead of quietly dropping the meeting items from the brief.
                changes.append("Meeting action items could not be read: \(error.localizedDescription)")
            }
        }
        sinceYesterday = BriefSectionPrefs.isEnabled("changes") ? changes : []

        // Share what's on screen with the widget and Siri actions. Sections turned off in
        // Settings are left out of the snapshot too, so the widget never shows them.
        BriefSectionPrefs.mirrorToAppGroup()
        let nextEnabled = BriefSectionPrefs.isEnabled("next")
        let firstUpcoming = nextEnabled ? calendarEvents.first { !$0.isAllDay && $0.endDate > Date() } : nil
        let articles = Array(rssFeeds.flatMap { $0.articles }.prefix(min(headlineCount, 10)))
        SharedBriefingStore.update { b in
            b.firstEventTitle = firstUpcoming?.title
            b.firstEventStart = firstUpcoming?.startDate
            b.weatherTempC = weatherData?.temperatureC
            b.weatherCondition = weatherData?.condition
            b.weatherLine = weatherData.map { "\(units.formatTemperatureShort(celsius: $0.temperatureC)) \($0.condition)" }
            b.headlines = articles.map {
                SharedBriefing.Headline(title: $0.title, gist: Self.savedGists[$0.id], source: nil)
            }
            if BriefSectionPrefs.isEnabled("summary") {
                if let summary = self.aiDaySummary, !summary.isEmpty { b.summary = summary }
            } else {
                b.summary = nil
            }
        }
        applySavedGists()
        if headlinesEnabled && !articles.isEmpty {
            Task { await self.addHeadlineGists(for: articles) }
        }
    }

    // MARK: - Headline gists (on-device, one line per story)

    private static let gistsKey = "headline_gists_v1"

    /// article id -> one-line gist, kept for the latest ~150 stories.
    private static var savedGists: [String: String] {
        get { UserDefaults.standard.dictionary(forKey: gistsKey) as? [String: String] ?? [:] }
        set {
            var trimmed = newValue
            if trimmed.count > 150 {
                for k in trimmed.keys.prefix(trimmed.count - 150) { trimmed.removeValue(forKey: k) }
            }
            UserDefaults.standard.set(trimmed, forKey: gistsKey)
        }
    }

    /// Writes gists over the raw feed blurbs in the headlines section (raw blurb stays as fallback).
    private func applySavedGists() {
        let gists = Self.savedGists
        guard !gists.isEmpty,
              let i = briefingSections.firstIndex(where: { $0.id == "headlines" }),
              let feed = briefingSections[i].rssFeed else { return }
        let articles = feed.articles.map { a in
            RSSArticle(id: a.id, title: a.title, url: a.url, publishedAt: a.publishedAt,
                       summary: gists[a.id] ?? a.summary)
        }
        briefingSections[i].rssFeed = RSSFeedData(id: feed.id, sourceName: feed.sourceName, articles: articles)
    }

    private func addHeadlineGists(for articles: [RSSArticle]) async {
        var gists = Self.savedGists
        let missing = articles.filter { gists[$0.id] == nil }
        guard !missing.isEmpty else { return }
        let fresh = await AIService.shared.headlineGists(for: missing)
        guard !fresh.isEmpty else { return }
        gists.merge(fresh) { _, new in new }
        Self.savedGists = gists
        applySavedGists()
        SharedBriefingStore.update { b in
            b.headlines = b.headlines.enumerated().map { idx, h in
                var h = h
                if idx < articles.count, let g = gists[articles[idx].id] { h.gist = g }
                return h
            }
        }
    }

    // MARK: - Generate AI-enhanced briefing

    /// Full briefing generation: load data then enhance with on-device AI.
    /// Uses AIService (Foundation Models, iOS 26+) — no external AI endpoints.
    /// Shows loading state during AI generation.
    func generateBriefing() async {
        if isPreview { return }
        isLoading = true
        defer { isLoading = false }

        // Load all data sections first
        await loadData(force: true)

        // Update badge BEFORE the guard that may early-return for localOnly
        updateNetworkBadge()

        // Then generate AI summary via on-device Foundation Models
        // Skip if no sections to process (localOnly users still get data, just no FM)
        guard !briefingSections.isEmpty else { return }

        await generateAISummary()

        // Persist full briefing to cache so app can display instantly when opened from notification
        await cacheBriefing()

        // Load meeting prep (Feature #1) — skip if first meeting > 2 hours away
        meetingPrep = await meetingPrepService.prepareMeetingPrep()
    }

    /// Silent refresh — loads from cache first (instant), then does a live refresh in background.
    /// Use on app launch / deep-link open for instant briefing display.
    func silentRefresh() async {
        if isPreview { return }
        if let silentRefreshInFlight {
            await silentRefreshInFlight.value
            return
        }

        let task = Task { @MainActor in
            await self.loadFromCache()
            await self.loadData()
            if self.aiDaySummary == nil {
                await self.generateAISummary()
            }
        }
        silentRefreshInFlight = task
        await task.value
        silentRefreshInFlight = nil
    }

    // MARK: - AI day summary (on-device Foundation Models)

    private static let summaryKey = "ai_day_summary"
    private static let summaryDayKey = "ai_day_summary_day"

    /// Why there is no AI summary (device not eligible, Apple Intelligence off, still
    /// downloading). Shown in place of the summary so the header never just goes blank.
    @Published var aiUnavailableReason: String? = nil

    /// Streams the day summary into `aiDaySummary` and saves it for the rest of the day,
    /// so the summary made by the 6am background refresh is what you see when you open the app.
    func generateAISummary() async {
        guard BriefSectionPrefs.isEnabled("summary") else {
            aiDaySummary = nil
            aiUnavailableReason = nil
            return
        }
        guard !briefingSections.isEmpty, !isGeneratingAI else { return }
        let ai = AIService.shared
        guard ai.refreshAvailability() else {
            aiUnavailableReason = ai.unavailableReason
            return
        }
        aiUnavailableReason = nil
        isGeneratingAI = true
        defer { isGeneratingAI = false }
        let previous = aiDaySummary
        if let summary = await ai.generateInsight(from: briefingSections, onPartial: { [weak self] partial in
            self?.aiDaySummary = partial
        }) {
            aiDaySummary = summary.insight
            Self.saveSummary(summary.insight)
        } else {
            aiDaySummary = previous
        }
    }

    private static func dayStamp(_ date: Date = Date()) -> String {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .gregorian)
        f.dateFormat = "yyyy-MM-dd"
        return f.string(from: date)
    }

    private static func saveSummary(_ text: String) {
        UserDefaults.standard.set(text, forKey: summaryKey)
        UserDefaults.standard.set(dayStamp(), forKey: summaryDayKey)
        SharedBriefingStore.update { $0.summary = text }
    }

    private static func todaysSavedSummary() -> String? {
        guard UserDefaults.standard.string(forKey: summaryDayKey) == dayStamp() else { return nil }
        return UserDefaults.standard.string(forKey: summaryKey)
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

    /// Load briefing from TTLCache (instant, no network). Only fills an empty screen: it
    /// must never replace fresher in-memory sections with an older cached copy.
    private func loadFromCache() async {
        guard briefingSections.isEmpty else { return }
        if let cached: BriefingData = await cache.getBriefing() {
            briefingSections = cached.sections
            // AI summary lives outside BriefingData; restore today's saved copy.
            if aiDaySummary == nil, BriefSectionPrefs.isEnabled("summary") { aiDaySummary = Self.todaysSavedSummary() }
            updateNetworkBadge()
        }
    }

    private func updateNetworkBadge() {
        if localOnly {
            networkBadge = .local
        } else {
            // Online — live external sources active (weather/markets/RSS)
            networkBadge = .online
        }
    }

    // MARK: - Morning snapshot (Brief tab hero)

    func refreshMorningSnapshot(weather: WeatherData?, calendarCount: Int) async {
        let units = UnitsPreference.current
        var snapshot = MorningSnapshot.empty
        snapshot.updatedAt = Date()
        snapshot.weatherEnabled = weatherEnabled

        if let w = weather {
            snapshot.weatherIcon = w.conditionIcon
            snapshot.weatherLine = "\(units.formatTemperatureShort(celsius: w.temperatureC)) · \(w.condition)"
            snapshot.location = w.location
            snapshot.weatherNeedsLocation = false
            snapshot.weatherErrorDetail = nil
        } else if weatherEnabled {
            weatherService.syncAuthorizationFromManager()
            snapshot.weatherNeedsLocation = weatherService.needsLocationPermission
            snapshot.weatherErrorDetail = weatherService.lastError
            if let cached = await cache.getWeather() {
                snapshot.weatherIcon = cached.conditionIcon
                snapshot.weatherLine = "\(units.formatTemperatureShort(celsius: cached.temperatureC)) · \(cached.condition)"
                snapshot.location = cached.location
            }
        } else {
            snapshot.weatherEnabled = false
        }

        if calendarCount > 0 {
            snapshot.calendarLine = calendarCount == 1 ? "1 event today" : "\(calendarCount) events today"
        } else if calendarEnabled && !permissionDenied.contains("calendar") {
            snapshot.calendarLine = "Calendar clear today"
        }

        guard BriefSectionPrefs.isEnabled("markets") else {
            snapshot.marketsStatus = .unavailable
            morningSnapshot = snapshot
            SharedBriefingStore.update { $0.markets = nil }
            return
        }
        snapshot.marketsStatus = .loading
        morningSnapshot = snapshot

        let quotes: [MorningSnapshotQuote]
        let status: MorningSnapshot.MarketsStatus

        if localOnly {
            quotes = await snapshotQuotesFromCache()
            status = quotes.isEmpty ? .unavailable : .cached
        } else {
            let (liveQuotes, liveStatus) = await fetchSnapshotQuotesLive()
            quotes = liveQuotes
            status = liveStatus
        }

        snapshot.marketQuotes = quotes
        snapshot.marketsStatus = status
        morningSnapshot = snapshot

        // The rotating widget's Markets page shows the same rows as text.
        SharedBriefingStore.update { b in
            b.markets = quotes.isEmpty ? nil : quotes.prefix(3).map {
                SharedBriefing.MarketLine(symbol: $0.symbol, priceText: $0.priceText, changeText: $0.changeText, isPositive: $0.isPositive)
            }
        }
    }

    private func fetchSnapshotQuotesLive() async -> ([MorningSnapshotQuote], MorningSnapshot.MarketsStatus) {
        let batch = await MarketBackendService.fetchBatch(symbols: Self.snapshotSymbols)
        var quotes: [MorningSnapshotQuote] = []
        var anyLive = false
        var anyCached = false

        for symbol in Self.snapshotSymbols {
            if let row = batch.first(where: { $0.symbol == symbol }), row.error == nil, row.price > 0 {
                quotes.append(MorningSnapshotQuote(
                    symbol: symbol,
                    priceText: MarketBackendService.formatPrice(symbol: symbol, price: row.price),
                    change24h: row.change24h,
                    prevClose: row.prevClose, series: row.series
                ))
                if row.cached { anyCached = true } else { anyLive = true }
                await cache.setSymbolPrice(symbol, data: TTLCache.CachedSymbolData(
                    price: row.price, change24h: row.change24h, timestamp: Date(),
                    prevClose: row.prevClose, series: row.series
                ))
                continue
            }
            if let cached = await cache.getSymbolPrice(symbol) {
                quotes.append(MorningSnapshotQuote(
                    symbol: symbol,
                    priceText: MarketBackendService.formatPrice(symbol: symbol, price: cached.price),
                    change24h: cached.change24h,
                    prevClose: cached.prevClose, series: cached.series ?? []
                ))
                anyCached = true
            }
        }

        if quotes.isEmpty { return ([], .unavailable) }
        if anyLive { return (quotes, .live) }
        if anyCached { return (quotes, .cached) }
        return (quotes, .unavailable)
    }

    private func snapshotQuotesFromCache() async -> [MorningSnapshotQuote] {
        var quotes: [MorningSnapshotQuote] = []
        for symbol in Self.snapshotSymbols {
            guard let cached = await cache.getSymbolPrice(symbol) else { continue }
            quotes.append(MorningSnapshotQuote(
                symbol: symbol,
                priceText: MarketBackendService.formatPrice(symbol: symbol, price: cached.price),
                change24h: cached.change24h,
                prevClose: cached.prevClose, series: cached.series ?? []
            ))
        }
        return quotes
    }

    // MARK: - Data fetchers (with cache fallback)

    private func fetchWeather(forceLive: Bool = false) async -> WeatherData? {
        guard weatherEnabled else { return nil }
        if localOnly {
            return await cache.getWeather()
        }
        // WeatherKit is billed per call. Conditions change slowly, so reuse a reading for
        // an hour; pull-to-refresh and other forced reloads still reuse one under 15 min.
        // The cached copy is kept for 3 h as the fallback when a fetch fails.
        let maxAge: TimeInterval = forceLive ? 15 * 60 : 60 * 60
        // Exception: moved more than 10 km (landed in another city) means fetch now.
        if let age = await cache.age("weather"), age < maxAge,
           let cached: WeatherData = await cache.getWeather(),
           await !weatherService.hasMovedSinceLastFetch() {
            return cached
        }
        let data = await weatherService.fetchWeather()
        if let data = data {
            await cache.setWeather(data)
            return data
        }
        return await cache.getWeather()
    }

    private func fetchHealth(forceLive: Bool = false) async -> HealthData? {
        // Respect health_enabled setting
        guard healthEnabled else { return nil }
        // localOnly: skip live HealthKit fetch, only use cache
        if localOnly {
            return await cache.getHealth()
        }
        if !forceLive, let cached: HealthData = await cache.getHealth() {
            return cached
        }
        _ = await healthService.requestAuthorization()
        // Give HealthKit a moment to update published state, then check via async method
        try? await Task.sleep(nanoseconds: 500_000_000)
        let authorized: Bool = await healthService.isAuthorizedForHealthData()
        if !authorized {
            if !permissionDenied.contains("health") { permissionDenied.append("health") }
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

    private func fetchCalendar(forceLive: Bool = false) async -> [CalendarEvent] {
        // Respect calendar_enabled setting
        guard calendarEnabled else { return [] }
        // localOnly: skip live Calendar fetch, only use cache
        if localOnly {
            return await cache.getCalendar() ?? []
        }
        if !forceLive, let cached: [CalendarEvent] = await cache.getCalendar() {
            return cached
        }
        _ = await calendarService.requestAuthorization()
        // Check if user denied Calendar access
        if !calendarService.isAuthorized {
            if !permissionDenied.contains("calendar") { permissionDenied.append("calendar") }
            return []
        }
        let events = await calendarService.fetchTodayEvents()
        await cache.setCalendar(events)
        return events
    }

    private func fetchRSS(forceLive: Bool = false) async -> [RSSFeedData] {
        // Respect headlines_enabled setting
        guard headlinesEnabled else { return [] }
        if localOnly {
            return await cache.getRSSFeeds() ?? []
        }
        if !forceLive, let cached: [RSSFeedData] = await cache.getRSSFeeds() {
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
                    timestamp: Date(),
                    prevClose: data.prevClose,
                    series: data.series
                )
            )
            return data
        }
        // Live fetch failed (rate limit, network, parse) — try cache
        return await cache.getSymbolPrice(symbol).map {
            SymbolData(price: $0.price, change24h: $0.change24h, prevClose: $0.prevClose, series: $0.series ?? [])
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
        var series: [String: MarketSeries] = [:]

        for item in tracked {
            let priceData: SymbolData?
            if useCache {
                priceData = await cache.getSymbolPrice(item.symbol).map {
                    SymbolData(price: $0.price, change24h: $0.change24h, prevClose: $0.prevClose, series: $0.series ?? [])
                }
            } else {
                priceData = await fetchSymbolWithCacheFallback(symbol: item.symbol)
            }

            guard let data = priceData else { continue }
            allFailed = false
            series[item.symbol] = MarketSeries(prevClose: data.prevClose, points: data.series)

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
        marketSeries = series

        if hasBullish && !hasBearish { sentiment = "bullish" }
        else if hasBearish && !hasBullish { sentiment = "bearish" }
        else if !tracked.isEmpty { sentiment = "neutral" }

        return (content.isEmpty ? "market data unavailable" : content, sentiment)
    }

    private struct SymbolData {
        let price: Double
        let change24h: Double
        var prevClose: Double? = nil
        var series: [Double] = []
    }

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
            SymbolData(price: $0.price, change24h: $0.change24h, prevClose: $0.prevClose, series: $0.series ?? [])
        }
    }

    private func fetchFromBackend(symbol: String) async -> SymbolData? {
        let batch = await MarketBackendService.fetchBatch(symbols: [symbol])
        guard let row = batch.first, row.error == nil, row.price > 0 else { return nil }
        await cache.setSymbolPrice(symbol, data: TTLCache.CachedSymbolData(
            price: row.price, change24h: row.change24h, timestamp: Date(),
            prevClose: row.prevClose, series: row.series
        ))
        return SymbolData(price: row.price, change24h: row.change24h, prevClose: row.prevClose, series: row.series)
    }
}

/// Network badge — shows data freshness to user.
enum NetworkBadge {
    case local      // 🟢 LOCAL — localOnly mode, no external calls
    case online     // 🟡 ONLINE — normal mode, live data from weather/markets/RSS
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
        let briefingSections = VoiceBriefingService.sectionsForVoice(self.briefingSections)

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
        voiceBriefingService.speakBriefing(sections: briefingSections,
                                           summary: BriefSectionPrefs.isEnabled("summary") ? aiDaySummary : nil)
    }

    /// Stops any current voice briefing playback.
    func stopVoiceBriefing() {
        voiceBriefingService.stop()
    }
}