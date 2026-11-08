import Foundation

/// TTL-based cache — UserDefaults for small values, FileManager for larger ones
/// All data is non-PII. No network IDs, no email, no precise location stored.
actor TTLCache {
    private let defaults = UserDefaults.standard
    private let fileManager = FileManager.default
    private let cacheDir: URL

    init(name: String = "MorningVaultCache", defaultTTL: TimeInterval = 300) {
        self.defaultTTL = defaultTTL
        let base = fileManager.urls(for: .cachesDirectory, in: .userDomainMask).first!
        self.cacheDir = base.appendingPathComponent(name)
        try? fileManager.createDirectory(at: cacheDir, withIntermediateDirectories: true)
    }

    private let defaultTTL: TimeInterval

    // MARK: - Generic get/set

    func get<T: Codable>(_ key: String, ttl: TimeInterval? = nil) -> T? {
        let entry = loadEntry(key)

        guard let entry = entry else { return nil }
        // The TTL given at `set` time wins (weather 30 min, RSS 1 h…); the old code ignored
        // it and expired everything after the 5-minute default.
        let effectiveTTL = ttl ?? entry.ttl ?? defaultTTL
        guard Date().timeIntervalSince(entry.timestamp) < effectiveTTL else {
            delete(key)
            return nil
        }

        // Was `entry.value as? T`, which is always nil for a wrapped payload — the cache
        // never returned a hit, so every launch re-fetched everything.
        return entry.value.decode(T.self)
    }

    /// Seconds since `key` was written, without expiring it (nil when absent).
    func age(_ key: String) -> TimeInterval? {
        loadEntry(key).map { Date().timeIntervalSince($0.timestamp) }
    }

    func set<T: Codable>(_ key: String, value: T, ttl: TimeInterval? = nil) {
        let entry = CacheEntry(timestamp: Date(), ttl: ttl, value: AnyCodable(encodable: value))
        saveEntry(key, entry)
    }

    func delete(_ key: String) {
        let file = cacheFile(key)
        try? fileManager.removeItem(at: file)
        defaults.removeObject(forKey: "cache:\(key)")
    }

    func clearAll() {
        try? fileManager.removeItem(at: cacheDir)
        try? fileManager.createDirectory(at: cacheDir, withIntermediateDirectories: true)
    }

    // MARK: - Per-symbol market cache (scalable — backend slot-in ready)

    func getSymbolPrice(_ symbol: String) -> CachedSymbolData? { get("market:\(symbol)") }
    func setSymbolPrice(_ symbol: String, data: CachedSymbolData, ttl: TimeInterval = 900) { set("market:\(symbol)", value: data, ttl: ttl) }

    func getRSSFeed(_ feedId: String) -> RSSFeedData? { get("rss:\(feedId)") }
    func setRSSFeed(_ feedId: String, data: RSSFeedData, ttl: TimeInterval = 3600) { set("rss:\(feedId)", value: data, ttl: ttl) }

    // MARK: - Typed convenience accessors

    func getWeather() -> WeatherData? { get("weather") }
    func setWeather(_ data: WeatherData, ttl: TimeInterval = 3 * 3600) { set("weather", value: data, ttl: ttl) }

    func getHealth() -> HealthData? { get("health") }
    func setHealth(_ data: HealthData, ttl: TimeInterval = 3600) { set("health", value: data, ttl: ttl) }

    func getCalendar() -> [CalendarEvent]? { get("calendar") }
    func setCalendar(_ events: [CalendarEvent], ttl: TimeInterval = 1800) { set("calendar", value: events, ttl: ttl) }

    func getBriefing() -> BriefingData? { get("briefing") }
    func setBriefing(_ data: BriefingData, ttl: TimeInterval = 300) { set("briefing", value: data, ttl: ttl) }

    func getRSSFeeds() -> [RSSFeedData]? { get("rss") }
    func setRSSFeeds(_ feeds: [RSSFeedData], ttl: TimeInterval = 3600) { set("rss", value: feeds, ttl: ttl) }

    // MARK: - Private

    private struct CacheEntry: Codable {
        let timestamp: Date
        var ttl: TimeInterval?   // optional: entries written before this field existed decode fine
        let value: AnyCodable
    }

    private struct AnyCodable: Codable {
        let data: Data

        init<T: Codable>(encodable value: T) {
            self.data = (try? JSONEncoder().encode(value)) ?? Data()
        }

        func decode<T: Codable>(_ type: T.Type) -> T? {
            guard let decoded = try? JSONDecoder().decode(T.self, from: data) else {
                // DEBUG: print("[TTLCache] Failed to decode \(type) from cache — data may be corrupted")
                return nil
            }
            return decoded
        }
    }

    // MARK: - Shared data models (scalable cache entries)

    struct CachedSymbolData: Codable {
        let price: Double
        let change24h: Double
        let timestamp: Date
        /// Sparkline inputs; optional so entries written before they existed still decode.
        var prevClose: Double? = nil
        var series: [Double]? = nil
    }

    private func cacheFile(_ key: String) -> URL {
        let safe = key.replacingOccurrences(of: "/", with: "_")
        return cacheDir.appendingPathComponent("\(safe).json")
    }

    private func loadEntry(_ key: String) -> CacheEntry? {
        let file = cacheFile(key)
        guard let data = try? Data(contentsOf: file) else { return nil }
        return try? JSONDecoder().decode(CacheEntry.self, from: data)
    }

    private func saveEntry(_ key: String, _ entry: CacheEntry) {
        let file = cacheFile(key)
        guard let data = try? JSONEncoder().encode(entry) else { return }
        try? data.write(to: file)
    }
}

// MARK: - Shared Cache Instance

let sharedCache = TTLCache()
