import XCTest
@testable import MorningVault

final class ChecklistIntentsTests: XCTestCase {
    private func snapshot(done: Int, total: Int, titles: [String], doneTitles: Set<String> = []) -> ChecklistTodaySnapshot {
        let items = titles.map { ChecklistTodaySnapshot.Item(id: UUID(), title: $0, forInitial: nil, isDone: doneTitles.contains($0), nextSlot: nil) }
        return ChecklistTodaySnapshot(day: ChecklistTodaySnapshot.dayKey(Date()), done: done, total: total,
                                      nextUndoneTitles: Array(items.filter { !$0.isDone }.map(\.title).prefix(3)), items: items, updatedAt: Date())
    }

    func testSpokenProgressListsWhatIsLeft() {
        let s = snapshot(done: 3, total: 6, titles: ["Pack lunches", "Kids' meds", "Stretch", "Walk", "Piano", "Time with kids"],
                         doneTitles: ["Pack lunches", "Kids' meds", "Stretch"])
        XCTAssertEqual(GetTodayProgressIntent.spokenProgress(snapshot: s), "Three of six done. Left: walk, piano, time with kids.")
    }

    func testSpokenProgressAllDoneAndEmpty() {
        XCTAssertEqual(GetTodayProgressIntent.spokenProgress(snapshot: snapshot(done: 2, total: 2, titles: ["A", "B"], doneTitles: ["A", "B"])),
                       "All two done today.")
        XCTAssertEqual(GetTodayProgressIntent.spokenProgress(snapshot: snapshot(done: 0, total: 0, titles: [])),
                       "Nothing on the household checklist today.")
        XCTAssertTrue(GetTodayProgressIntent.spokenProgress(snapshot: nil).hasPrefix("Nothing on the household checklist today yet."))
    }

    func testStaleSnapshotIsIgnored() {
        var s = snapshot(done: 1, total: 2, titles: ["A", "B"], doneTitles: ["A"])
        s.day = "2000-01-01"
        XCTAssertTrue(GetTodayProgressIntent.spokenProgress(snapshot: s).hasPrefix("Nothing"))
    }

    func testMarkDoneViaStoreIsIdempotent() async throws {
        var la = Calendar(identifier: .gregorian)
        la.timeZone = TimeZone(identifier: "America/Los_Angeles")!
        let store = ChecklistStore(inMemory: true, calendar: la)
        let now = la.date(from: DateComponents(year: 2026, month: 11, day: 10, hour: 9))!
        let item = ChecklistItem(title: "Walk", createdAt: la.date(from: DateComponents(year: 2026, month: 11, day: 1))!)
        try await store.saveItem(item)
        XCTAssertTrue(try await store.markDone(itemID: item.id, on: now, at: now))
        XCTAssertFalse(try await store.markDone(itemID: item.id, on: now, at: now))
        let ledger = try await store.ledger(asOf: now)
        XCTAssertEqual(ledger.completions.count, 1)
    }
}
