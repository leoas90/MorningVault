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

    func testVoiceLineShortAndFull() {
        UserDefaults.standard.set(true, forKey: BriefSectionPrefs.householdEnabledKey)
        UserDefaults.standard.set(true, forKey: BriefSectionPrefs.Key.today)
        defer {
            UserDefaults.standard.removeObject(forKey: BriefSectionPrefs.householdEnabledKey)
            UserDefaults.standard.removeObject(forKey: BriefSectionPrefs.Key.today)
        }
        let one = snapshot(done: 1, total: 6, titles: ["Medicine", "Walk", "Piano", "A", "B", "C"], doneTitles: ["Medicine"])
        XCTAssertEqual(VoiceBriefingService.checklistLine(one, full: false), "Six things today; medicine is done.")
        let none = snapshot(done: 0, total: 2, titles: ["Walk", "Piano"])
        XCTAssertEqual(VoiceBriefingService.checklistLine(none, full: false), "Two things today, nothing checked yet.")
        let two = snapshot(done: 2, total: 3, titles: ["Walk", "Piano", "Read"], doneTitles: ["Walk", "Piano"])
        XCTAssertEqual(VoiceBriefingService.checklistLine(two, full: false), "Three things today; two are done.")
        XCTAssertEqual(VoiceBriefingService.checklistLine(two, full: true), "Household. Three things today, two done. Still open: read.")
        // All done: the short brief stays short.
        let done = snapshot(done: 2, total: 2, titles: ["Walk", "Piano"], doneTitles: ["Walk", "Piano"])
        XCTAssertNil(VoiceBriefingService.checklistLine(done, full: false))
        XCTAssertNil(VoiceBriefingService.checklistLine(nil, full: false))
    }

    func testMarkDoneViaStoreIsIdempotent() async throws {
        var la = Calendar(identifier: .gregorian)
        la.timeZone = TimeZone(identifier: "America/Los_Angeles")!
        let store = ChecklistStore(inMemory: true, calendar: la)
        let now = la.date(from: DateComponents(year: 2026, month: 11, day: 10, hour: 9))!
        let item = ChecklistItem(title: "Walk", createdAt: la.date(from: DateComponents(year: 2026, month: 11, day: 1))!)
        try await store.saveItem(item)
        let first = try await store.markDone(itemID: item.id, on: now, at: now)
        let second = try await store.markDone(itemID: item.id, on: now, at: now)
        XCTAssertTrue(first)
        XCTAssertFalse(second)
        let ledger = try await store.ledger(asOf: now)
        XCTAssertEqual(ledger.completions.count, 1)
    }
}
