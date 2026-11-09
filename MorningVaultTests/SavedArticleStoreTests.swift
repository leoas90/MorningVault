import XCTest
@testable import MorningVault

/// The Saved list behind "Save for later": save, dedupe, cap, remove, and the migration of
/// ids that were marked `.later` before snapshots existed.
@MainActor
final class SavedArticleStoreTests: XCTestCase {

    private var suiteName = ""
    private var defaults: UserDefaults!

    override func setUp() {
        super.setUp()
        suiteName = "test.saved.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        super.tearDown()
    }

    private func makeStore() -> SavedArticleStore {
        SavedArticleStore(defaults: defaults, key: "saved")
    }

    private func article(_ id: String, title: String? = nil, summary: String? = nil) -> RSSArticle {
        RSSArticle(id: id, title: title ?? "Story \(id)", url: "https://example.com/\(id)",
                   publishedAt: nil, summary: summary)
    }

    private func feed(_ articles: [RSSArticle], source: String = "The Wire") -> RSSFeedData {
        RSSFeedData(id: "feed-1", sourceName: source, articles: articles)
    }

    // MARK: Save

    func testSaveKeepsTheSnapshotNewestFirst() {
        let store = makeStore()
        store.save(article("a", title: "First"), sourceName: "The Wire", at: Date(timeIntervalSince1970: 1_000))
        store.save(article("b", title: "Second", summary: "A gist."), sourceName: "Daily Signal", at: Date(timeIntervalSince1970: 2_000))

        XCTAssertEqual(store.articles.map(\.id), ["b", "a"])
        let newest = store.articles[0]
        XCTAssertEqual(newest.title, "Second")
        XCTAssertEqual(newest.sourceName, "Daily Signal")
        XCTAssertEqual(newest.gist, "A gist.")
        XCTAssertEqual(newest.url, "https://example.com/b")
        XCTAssertTrue(store.contains(id: "a"))
    }

    func testAnEmptySummaryIsNotStoredAsAGist() {
        let store = makeStore()
        store.save(article("a", summary: "   "), sourceName: "The Wire")
        XCTAssertNil(store.articles[0].gist)
    }

    func testSavingTheSameArticleTwiceDedupesAndMovesItToTheTop() {
        let store = makeStore()
        store.save(article("a"), sourceName: "The Wire", at: Date(timeIntervalSince1970: 1_000))
        store.save(article("b"), sourceName: "The Wire", at: Date(timeIntervalSince1970: 2_000))
        store.save(article("a", title: "First, updated"), sourceName: "The Wire", at: Date(timeIntervalSince1970: 3_000))

        XCTAssertEqual(store.count, 2)
        XCTAssertEqual(store.articles.map(\.id), ["a", "b"])
        XCTAssertEqual(store.articles[0].title, "First, updated")
    }

    func testTheListIsCappedAndDropsTheOldest() {
        let store = makeStore()
        for index in 0..<(SavedArticleStore.cap + 10) {
            store.save(article("a\(index)"), sourceName: "The Wire",
                       at: Date(timeIntervalSince1970: TimeInterval(index)))
        }
        XCTAssertEqual(store.count, SavedArticleStore.cap)
        XCTAssertEqual(store.articles.first?.id, "a\(SavedArticleStore.cap + 9)")
        XCTAssertFalse(store.contains(id: "a0"), "the oldest saves fall off the end")
    }

    // MARK: Remove

    func testRemoveByIdAndByOffset() {
        let store = makeStore()
        for id in ["a", "b", "c"] { store.save(article(id), sourceName: "The Wire") }
        store.remove(id: "b")
        XCTAssertEqual(store.count, 2)
        XCTAssertFalse(store.contains(id: "b"))

        store.remove(atOffsets: IndexSet(integer: 0))
        XCTAssertEqual(store.count, 1)
        store.removeAll()
        XCTAssertTrue(store.articles.isEmpty)
    }

    func testRemovingSomethingThatIsNotSavedChangesNothing() {
        let store = makeStore()
        store.save(article("a"), sourceName: "The Wire")
        store.remove(id: "nope")
        XCTAssertEqual(store.count, 1)
    }

    // MARK: Persistence

    func testSavedArticlesSurviveAReload() {
        let store = makeStore()
        store.save(article("a", title: "Kept"), sourceName: "The Wire", at: Date(timeIntervalSince1970: 1_000))
        store.save(article("b"), sourceName: "The Wire", at: Date(timeIntervalSince1970: 2_000))

        let reopened = makeStore()
        XCTAssertEqual(reopened.articles.map(\.id), ["b", "a"])
        XCTAssertEqual(reopened.articles[1].title, "Kept")
    }

    // MARK: Migration

    func testMigrateAdoptsLaterIdsStillInTheFeed() {
        let store = makeStore()
        let articles = [article("a"), article("b"), article("c")]
        let states: [String: NewsArticleState] = ["a": .later, "b": .read, "c": .later, "gone": .later]

        let added = store.migrate(from: [feed(articles)], states: states)
        XCTAssertEqual(added, 2)
        XCTAssertEqual(Set(store.articles.map(\.id)), ["a", "c"])
        XCTAssertEqual(store.articles[0].sourceName, "The Wire")
    }

    func testMigrateIsIdempotentAndKeepsTheOriginalSaveDate() {
        let store = makeStore()
        let original = Date(timeIntervalSince1970: 1_000)
        store.save(article("a"), sourceName: "The Wire", at: original)

        let added = store.migrate(from: [feed([article("a")])], states: ["a": .later],
                                  at: Date(timeIntervalSince1970: 9_000))
        XCTAssertEqual(added, 0)
        XCTAssertEqual(store.count, 1)
        XCTAssertEqual(store.articles[0].savedAt, original)
    }

    // MARK: Row copy

    func testSavedTextReadsAsADate() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        let now = Date(timeIntervalSince1970: 1_762_689_600)
        let yesterday = calendar.date(byAdding: .day, value: -1, to: now)!
        let older = calendar.date(byAdding: .day, value: -9, to: now)!

        XCTAssertEqual(SavedArticle(id: "a", title: "t", url: "", sourceName: "s", savedAt: now)
            .savedText(relativeTo: now, calendar: calendar), "Saved today")
        XCTAssertEqual(SavedArticle(id: "a", title: "t", url: "", sourceName: "s", savedAt: yesterday)
            .savedText(relativeTo: now, calendar: calendar), "Saved yesterday")
        XCTAssertTrue(SavedArticle(id: "a", title: "t", url: "", sourceName: "s", savedAt: older)
            .savedText(relativeTo: now, calendar: calendar).hasPrefix("Saved "))
    }
}
