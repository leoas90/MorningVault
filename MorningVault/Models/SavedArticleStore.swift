import Foundation

// MARK: - Saved articles
//
// "Save for later" used to write nothing but an id into `NewsReadStateTracker`, so the story
// disappeared with the next feed refresh. This keeps a snapshot of what was saved, so the
// Saved list survives refreshes and stays readable even with Headlines turned off.
//
// On device only: JSON in UserDefaults, newest first, capped. No network, no CloudKit.

struct SavedArticle: Codable, Identifiable, Equatable, Sendable {
    /// The RSS article id, the same key `NewsReadStateTracker` uses.
    let id: String
    let title: String
    /// Story link; may be empty for a feed that gave none.
    let url: String
    let sourceName: String
    /// Short summary from the feed, when it had one.
    let gist: String?
    let savedAt: Date

    init(id: String, title: String, url: String, sourceName: String, gist: String? = nil, savedAt: Date = Date()) {
        self.id = id
        self.title = title
        self.url = url
        self.sourceName = sourceName
        let trimmed = gist?.trimmingCharacters(in: .whitespacesAndNewlines)
        self.gist = (trimmed?.isEmpty ?? true) ? nil : trimmed
        self.savedAt = savedAt
    }

    init(article: RSSArticle, sourceName: String, savedAt: Date = Date()) {
        self.init(id: article.id, title: article.title, url: article.url,
                  sourceName: sourceName, gist: article.summary, savedAt: savedAt)
    }

    /// "Saved 9 Nov" for the row's meta line.
    func savedText(relativeTo now: Date = Date(), calendar: Calendar = .current) -> String {
        if calendar.isDate(savedAt, inSameDayAs: now) { return "Saved today" }
        if let yesterday = calendar.date(byAdding: .day, value: -1, to: now),
           calendar.isDate(savedAt, inSameDayAs: yesterday) { return "Saved yesterday" }
        return "Saved " + savedAt.formatted(.dateTime.day().month(.abbreviated))
    }
}

/// The saved list. Main-actor isolated: it drives `@ObservedObject` in the Saved screen and
/// the Brief's headline rows, the same as `NewsReadStateTracker`.
@MainActor
final class SavedArticleStore: ObservableObject {
    static let shared = SavedArticleStore()

    /// Newest first.
    @Published private(set) var articles: [SavedArticle] = []

    /// Hard cap; saving past it drops the oldest.
    static let cap = 100
    static let defaultsKey = "com.morningvault.savedArticles"

    private let defaults: UserDefaults
    private let key: String

    init(defaults: UserDefaults = .standard, key: String = SavedArticleStore.defaultsKey) {
        self.defaults = defaults
        self.key = key
        load()
    }

    var count: Int { articles.count }

    func contains(id: String) -> Bool { articles.contains { $0.id == id } }

    // MARK: Writes

    /// Saves (or refreshes) one article and moves it to the top. Dedupes on the article id.
    func save(_ article: SavedArticle) {
        var next = articles.filter { $0.id != article.id }
        next.insert(article, at: 0)
        if next.count > Self.cap { next = Array(next.prefix(Self.cap)) }
        articles = next
        persist()
    }

    func save(_ article: RSSArticle, sourceName: String, at now: Date = Date()) {
        save(SavedArticle(article: article, sourceName: sourceName, savedAt: now))
    }

    func remove(id: String) {
        guard articles.contains(where: { $0.id == id }) else { return }
        articles.removeAll { $0.id == id }
        persist()
    }

    func remove(atOffsets offsets: IndexSet) {
        let ids = offsets.compactMap { articles.indices.contains($0) ? articles[$0].id : nil }
        guard !ids.isEmpty else { return }
        articles.removeAll { ids.contains($0.id) }
        persist()
    }

    func removeAll() {
        guard !articles.isEmpty else { return }
        articles.removeAll()
        persist()
    }

    /// Picks up stories that were marked "Save for later" before this list existed: any id
    /// still in `.later` whose article is in the feeds on screen. Already-saved ids are left
    /// alone, so their original save date survives.
    @discardableResult
    func migrate(from feeds: [RSSFeedData], states: [String: NewsArticleState], at now: Date = Date()) -> Int {
        var added = 0
        for feed in feeds {
            for article in feed.articles where states[article.id] == .later && !contains(id: article.id) {
                save(SavedArticle(article: article, sourceName: feed.sourceName, savedAt: now))
                added += 1
            }
        }
        return added
    }

    // MARK: Persistence

    private func load() {
        guard let data = defaults.data(forKey: key),
              let decoded = try? JSONDecoder().decode([SavedArticle].self, from: data) else { return }
        articles = Array(decoded.sorted { $0.savedAt > $1.savedAt }.prefix(Self.cap))
    }

    private func persist() {
        guard let data = try? JSONEncoder().encode(articles) else { return }
        defaults.set(data, forKey: key)
    }
}

// MARK: - Sample data

extension SavedArticle {
    /// Fictional stories for previews.
    static let sample: [SavedArticle] = [
        SavedArticle(id: "sample-1", title: "On-device models get a second wind",
                     url: "https://example.com/on-device-models", sourceName: "The Wire",
                     gist: "Smaller models, fewer round trips, and what that means for phones.",
                     savedAt: Date(timeIntervalSince1970: 1_762_600_000)),
        SavedArticle(id: "sample-2", title: "A storm system lines up for the weekend",
                     url: "https://example.com/storm-system", sourceName: "Daily Signal",
                     savedAt: Date(timeIntervalSince1970: 1_762_300_000)),
        SavedArticle(id: "sample-3", title: "Why the quiet commute is back",
                     url: "https://example.com/quiet-commute", sourceName: "The Wire",
                     gist: "Transit numbers are up for the fourth quarter running.",
                     savedAt: Date(timeIntervalSince1970: 1_761_900_000)),
    ]
}
