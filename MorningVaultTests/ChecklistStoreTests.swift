import XCTest
@testable import MorningVault

final class ChecklistStoreTests: XCTestCase {
    private var la: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "America/Los_Angeles")!
        return c
    }

    private func date(_ y: Int, _ m: Int, _ d: Int, _ h: Int = 9) -> Date {
        la.date(from: DateComponents(year: y, month: m, day: d, hour: h))!
    }

    private func makeStore() -> ChecklistStore {
        ChecklistStore(inMemory: true, calendar: la)
    }

    func testToggleCreatesAndUndoDeletesCompletion() async throws {
        let store = makeStore()
        let now = date(2026, 11, 10)
        let item = ChecklistItem(title: "Walk", createdAt: date(2026, 11, 1))
        try await store.saveItem(item)

        let checked = try await store.toggle(itemID: item.id, on: now, byMember: HouseholdMember.sampleMe.id, at: now)
        XCTAssertTrue(checked)
        var ledger = try await store.ledger(asOf: now)
        XCTAssertEqual(ledger.completions.count, 1)
        XCTAssertEqual(ledger.completions.first?.byMember, HouseholdMember.sampleMe.id)
        XCTAssertTrue(ledger.isDone(item, on: now, calendar: la))

        let unchecked = try await store.toggle(itemID: item.id, on: now, at: now)
        XCTAssertFalse(unchecked)
        ledger = try await store.ledger(asOf: now)
        XCTAssertTrue(ledger.completions.isEmpty)
        XCTAssertFalse(ledger.isDone(item, on: now, calendar: la))
    }

    func testHourlySlotCompletion() async throws {
        let store = makeStore()
        let now = date(2026, 11, 10, 12)
        let item = ChecklistItem(
            title: "Stretch",
            recurrence: .hourly(everyHours: 2, from: DateComponents(hour: 8, minute: 0), to: DateComponents(hour: 18, minute: 0), on: Weekday.all),
            createdAt: date(2026, 11, 1))
        try await store.saveItem(item)

        try await store.toggle(itemID: item.id, on: now, slotIndex: 0, at: now)
        try await store.toggle(itemID: item.id, on: now, slotIndex: 1, at: now)
        var ledger = try await store.ledger(asOf: now)
        XCTAssertEqual(ledger.doneSlots(for: item, on: now, calendar: la), [0, 1])
        XCTAssertFalse(ledger.isDone(item, on: now, calendar: la))

        // Toggling slot 1 again undoes only that slot.
        try await store.toggle(itemID: item.id, on: now, slotIndex: 1, at: now)
        ledger = try await store.ledger(asOf: now)
        XCTAssertEqual(ledger.doneSlots(for: item, on: now, calendar: la), [0])

        for slot in 1..<6 { try await store.toggle(itemID: item.id, on: now, slotIndex: slot, at: now) }
        ledger = try await store.ledger(asOf: now)
        XCTAssertTrue(ledger.isDone(item, on: now, calendar: la))

        let snapshot = try await store.makeSnapshot(now: now)
        XCTAssertEqual(snapshot.done, 1)
        XCTAssertEqual(snapshot.total, 1)
        XCTAssertNil(snapshot.items.first?.nextSlot)
    }

    func testArchiveHidesItemButKeepsHistory() async throws {
        let store = makeStore()
        let yesterday = date(2026, 11, 9)
        let today = date(2026, 11, 10)
        let item = ChecklistItem(title: "Plants", createdAt: date(2026, 11, 1))
        try await store.saveItem(item)
        try await store.toggle(itemID: item.id, on: yesterday, at: yesterday)

        try await store.archiveItem(id: item.id, at: today)
        let active = try await store.items()
        XCTAssertTrue(active.isEmpty)
        let all = try await store.items(includeArchived: true)
        XCTAssertEqual(all.count, 1)
        XCTAssertNotNil(all.first?.archivedAt)

        let ledger = try await store.ledger(asOf: today)
        XCTAssertEqual(ledger.completions.count, 1)
        XCTAssertTrue(ledger.scheduled(on: today, calendar: la).isEmpty)
        XCTAssertEqual(ledger.scheduled(on: yesterday, calendar: la).count, 1)
        XCTAssertTrue(ledger.isDone(all[0], on: yesterday, calendar: la))
    }

    func testTrimKeepsNinetyDays() async throws {
        let store = makeStore()
        let now = date(2026, 11, 10)
        let item = ChecklistItem(title: "Walk", createdAt: date(2026, 1, 1))
        try await store.saveItem(item)
        // 89 days back is kept (90 days including today); 90 and 120 back are trimmed.
        for back in [0, 1, 89, 90, 120] {
            let day = la.date(byAdding: .day, value: -back, to: now)!
            try await store.toggle(itemID: item.id, on: day, at: day)
        }
        try await store.skip(itemID: item.id, on: la.date(byAdding: .day, value: -100, to: now)!)
        try await store.skip(itemID: item.id, on: la.date(byAdding: .day, value: -2, to: now)!)

        try await store.trim(asOf: now)
        let ledger = try await store.ledger(asOf: now)
        XCTAssertEqual(ledger.completions.count, 3)
        XCTAssertEqual(ledger.skips.count, 1)
        // Reading as of 100 days ago widens the window to those old keys: they are really gone.
        let past = la.date(byAdding: .day, value: -100, to: now)!
        let old = try await store.ledger(asOf: past)
        XCTAssertEqual(old.completions.count, 3)
        XCTAssertEqual(old.skips.count, 1)
    }

    func testItemCapAndTitleValidation() async throws {
        let store = makeStore()
        for i in 0..<12 { try await store.saveItem(ChecklistItem(title: "Item \(i)", order: i)) }
        do {
            try await store.saveItem(ChecklistItem(title: "One too many", order: 12))
            XCTFail("expected cap error")
        } catch ChecklistStore.StoreError.itemCapReached {
        }
        do {
            try await store.saveItem(ChecklistItem(title: "   "))
            XCTFail("expected title error")
        } catch ChecklistStore.StoreError.invalidTitle {
        }
    }

    func testMembersAndEnsureMe() async throws {
        let store = makeStore()
        let none = try await store.ensureMe(named: "   ")
        XCTAssertNil(none)
        let me = try await store.ensureMe(named: "Sam")
        XCTAssertEqual(me?.role, .me)
        XCTAssertEqual(me?.name, "Sam")
        // Second call returns the same member, no duplicate.
        let again = try await store.ensureMe(named: "Other")
        XCTAssertEqual(again?.id, me?.id)

        let child = HouseholdMember(name: "Riley", role: .child)
        try await store.saveMember(child)
        let item = ChecklistItem(title: "Pack lunches", forMember: child.id)
        try await store.saveItem(item)
        var members = try await store.members()
        XCTAssertEqual(members.map(\.name), ["Sam", "Riley"])

        try await store.deleteMember(id: child.id)
        members = try await store.members()
        XCTAssertEqual(members.count, 1)
        let items = try await store.items()
        XCTAssertNil(items.first?.forMember)
    }

    func testSnapshotRoundTripsAndRecurrenceSurvivesStore() async throws {
        let store = makeStore()
        let now = date(2026, 11, 10)
        let me = HouseholdMember(name: "Sam", role: .me)
        try await store.saveMember(me)
        let r = Recurrence.everyNWeeks(n: 2, on: [.tuesday], anchor: date(2026, 11, 10))
        let item = ChecklistItem(title: "Bins out", forMember: me.id, recurrence: r,
                                 reminder: ReminderRule(time: DateComponents(hour: 7, minute: 30), urgency: .mustDo),
                                 notes: "Green bin too", createdAt: date(2026, 11, 1))
        try await store.saveItem(item)
        let stored = try await store.items().first
        XCTAssertEqual(stored?.recurrence, r)
        XCTAssertEqual(stored?.reminder?.urgency, .mustDo)
        XCTAssertEqual(stored?.notes, "Green bin too")

        let snapshot = try await store.makeSnapshot(now: now)
        XCTAssertEqual(snapshot.day, "2026-11-10")
        XCTAssertEqual(snapshot.total, 1)
        XCTAssertEqual(snapshot.items.first?.forInitial, "S")
        XCTAssertEqual(snapshot.nextUndoneTitles, ["Bins out"])

        let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .iso8601
        let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .iso8601
        let data = try encoder.encode(snapshot)
        XCTAssertEqual(try decoder.decode(ChecklistTodaySnapshot.self, from: data), snapshot)
    }

    // MARK: Timers

    func testTimerStartPersistsAndFinishChecksOnce() async throws {
        let store = makeStore()
        let now = date(2026, 11, 10, 7)
        let item = ChecklistItem(title: "Walk", kind: .timer(minutes: 20), createdAt: date(2026, 11, 1))
        try await store.saveItem(item)

        try await store.startTimer(itemID: item.id, at: now)
        var items = try await store.items()
        XCTAssertEqual(items.first?.timerStartedAt, now)
        XCTAssertEqual(items.first?.timerEndsAt, now.addingTimeInterval(20 * 60))
        XCTAssertEqual(items.first?.timerRemaining(at: now.addingTimeInterval(600)), 600)

        try await store.finishTimer(itemID: item.id, on: now, at: now.addingTimeInterval(1200))
        items = try await store.items()
        XCTAssertNil(items.first?.timerStartedAt)
        var ledger = try await store.ledger(asOf: now)
        XCTAssertTrue(ledger.isDone(item, on: now, calendar: la))

        // Finishing again (notification action after the row already checked) never undoes the check.
        try await store.finishTimer(itemID: item.id, on: now, at: now.addingTimeInterval(1300))
        ledger = try await store.ledger(asOf: now)
        XCTAssertTrue(ledger.isDone(item, on: now, calendar: la))
        XCTAssertEqual(ledger.completions.count, 1)
    }

    func testCancelTimerLeavesItemUndone() async throws {
        let store = makeStore()
        let now = date(2026, 11, 10, 7)
        let item = ChecklistItem(title: "Read", kind: .timer(minutes: 10), createdAt: date(2026, 11, 1))
        try await store.saveItem(item)
        try await store.startTimer(itemID: item.id, at: now)
        try await store.cancelTimer(itemID: item.id)
        let items = try await store.items()
        XCTAssertNil(items.first?.timerStartedAt)
        let ledger = try await store.ledger(asOf: now)
        XCTAssertFalse(ledger.isDone(item, on: now, calendar: la))
    }
}
