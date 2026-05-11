import Foundation

// MARK: - Health Data

struct HealthData: Codable {
    let sleep: SleepData?
    let steps: Int?
    let activeCalories: Double?
    let hrv: Double?
    let heartRate: Double?
    let fetchedAt: Date
}

struct SleepData: Codable {
    let hoursInBed: Int
    let minutesInBed: Int
    let hoursAsleep: Int
    let minutesAsleep: Int
    let date: Date

    var inBedFormatted: String { "\(hoursInBed)h \(minutesInBed)m" }
    var asleepFormatted: String { "\(hoursAsleep)h \(minutesAsleep)m" }
}

// MARK: - Weather Data

struct WeatherData: Codable {
    let temperatureC: Int
    let feelsLikeC: Int
    let condition: String
    let conditionIcon: String
    let humidity: Int
    let windKph: Int
    let windDirection: String
    let uvIndex: Int
    let precipMM: Double
    let location: String

    var formatted: String {
        "\(conditionIcon) \(temperatureC)°C (\(condition))"
    }

    var uvWarning: String? {
        switch uvIndex {
        case 0...2: return nil
        case 3...5: return "Moderate UV"
        case 6...7: return "High UV"
        case 8...10: return "Very High UV"
        default: return "Extreme UV"
        }
    }
}

// MARK: - Calendar Data

struct CalendarEvent: Identifiable, Codable {
    let id: String
    let title: String
    let startDate: Date
    let endDate: Date
    let isAllDay: Bool
    let location: String?
    let notes: String?
    let calendarColor: String?

    var timeFormatted: String {
        if isAllDay { return "All day" }
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        return formatter.string(from: startDate)
    }

    var durationFormatted: String {
        if isAllDay { return "" }
        let minutes = Int(endDate.timeIntervalSince(startDate) / 60)
        if minutes < 60 {
            return "\(minutes)m"
        } else {
            let h = minutes / 60
            let m = minutes % 60
            return m > 0 ? "\(h)h \(m)m" : "\(h)h"
        }
    }
}

// MARK: - Briefing Data

struct BriefingData: Codable {
    let sections: [BriefingSection]
    let generatedAt: Date
    let latencyMs: Int
}

struct BriefingSection: Codable, Identifiable {
    let id: String
    let title: String
    let icon: String
    let content: String
    let sentiment: String?  // "bullish", "bearish", "neutral", "positive", "negative", nil
    var errorMessage: String?  // e.g. permission denied — shown as inline user-facing message
    var priority: Int = 999  // lower = higher priority; controls display order in briefing (default 999)
    /// Optional RSS feed data for the headlines section — enables Inbox Zero article rows
    var rssFeed: RSSFeedData?
}

// MARK: - RSS Data

struct RSSFeedData: Codable, Identifiable {
    let id: String
    let sourceName: String
    let articles: [RSSArticle]
}

struct RSSArticle: Codable, Identifiable {
    let id: String
    let title: String
    let url: String
    let publishedAt: Date?
    let summary: String?
}

// MARK: - News Article State (Inbox Zero for News)

/// Per-article read/later/skip state for Inbox Zero workflow.
enum NewsArticleState: String, Codable {
    case unread   // default — article is new
    case read     // user has read it
    case later    // saved for later reading
    case skipped  // user skipped this article
}

/// Tracks individual article states for Inbox Zero.
struct ArticleReadState: Codable, Identifiable {
    var id: String { articleId }
    let articleId: String
    var state: NewsArticleState
    var markedAt: Date

    init(articleId: String, state: NewsArticleState) {
        self.articleId = articleId
        self.state = state
        self.markedAt = Date()
    }
}

/// Tracks read state for all articles across all feeds.
/// Persisted to UserDefaults as JSON.
final class NewsReadStateTracker: ObservableObject {
    static let shared = NewsReadStateTracker()

    @Published private(set) var states: [String: NewsArticleState] = [:]

    private let key = "com.morningvault.articleStates"

    private init() { load() }

    // MARK: - Public API

    func state(for articleId: String) -> NewsArticleState {
        states[articleId] ?? .unread
    }

    func mark(_ articleId: String, as newState: NewsArticleState) {
        states[articleId] = newState
        save()
    }

    func markRead(_ articleId: String)    { mark(articleId, as: .read) }
    func markLater(_ articleId: String)   { mark(articleId, as: .later) }
    func markSkipped(_ articleId: String) { mark(articleId, as: .skipped) }
    func markUnread(_ articleId: String)  { mark(articleId, as: .unread) }

    /// Returns true if there are any unread articles in the given feeds.
    func hasUnread(in feeds: [RSSFeedData]) -> Bool {
        feeds.flatMap(\.articles).contains { state(for: $0.id) == .unread }
    }

    /// Returns the count of unread articles across all feeds.
    func unreadCount(in feeds: [RSSFeedData]) -> Int {
        feeds.flatMap(\.articles).filter { state(for: $0.id) == .unread }.count
    }

    /// Clears all states to reset Inbox Zero.
    func resetAll() {
        states.removeAll()
        save()
    }

    // MARK: - Persistence

    private func load() {
        guard let data = UserDefaults.standard.data(forKey: key),
              let decoded = try? JSONDecoder().decode([String: NewsArticleState].self, from: data) else {
            return
        }
        states = decoded
    }

    private func save() {
        if let encoded = try? JSONEncoder().encode(states) {
            UserDefaults.standard.set(encoded, forKey: key)
        }
    }
}