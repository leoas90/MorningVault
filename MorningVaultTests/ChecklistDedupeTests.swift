import XCTest
@testable import MorningVault

/// Duplicate checklist entries: mirrored calendars (one real event in both an iCloud and a
/// Google calendar) used to make two suggestions and two independent items.
final class ChecklistDedupeTests: XCTestCase {
    private var la: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "America/Los_Angeles")!
        return c
    }

    private func date(_ y: Int, _ m: Int, _ d: Int, _ h: Int = 9, _ min: Int = 0) -> Date {
        la.date(from: DateComponents(year: y, month: m, day: d, hour: h, minute: min))!
    }

    private var morning: Date { date(2026, 11, 10, 7) }

    private func makeStore() -> ChecklistStore { ChecklistStore(inMemory: true, calendar: la) }

    override func tearDown() {
        for key in ["health_enabled", "calendar_enabled", "weather_enabled"] {
            UserDefaults.standard.removeObject(forKey: key)
        }
        super.tearDown()
    }

    // MARK: Engine

    private func input(_ events: [SuggestionEvent]) -> SuggestionEngine.Input {
        SuggestionEngine.Input(events: events, members: HouseholdMember.sample, calendarMembers: [:],
                               selectedCalendars: nil, decisions: [], existingTitles: [], now: morning, calendar: la)
    }

    func testMirroredCalendarsMakeOneSuggestion() {
        let icloud = SuggestionEvent(id: "icloud-1", title: "Soccer practice", location: nil,
                                     start: date(2026, 11, 10, 16), isAllDay: false, calendarIdentifier: "icloud")
        let google = SuggestionEvent(id: "google-1", title: "soccer  Practice ", location: nil,
                                     start: date(2026, 11, 10, 16), isAllDay: false, calendarIdentifier: "google-family")
        let out = SuggestionEngine.rules(input([icloud, google]))
        XCTAssertEqual(out.count, 1)
        XCTAssertEqual(out.first?.eventID, "icloud-1")
        XCTAssertEqual(out.first?.title, "Pack soccer bag")
    }

    func testMirroredAllDayEventsMakeOneSuggestion() {
        let a = SuggestionEvent(id: "a", title: "Field trip", location: nil,
                                start: date(2026, 11, 10, 0), isAllDay: true, calendarIdentifier: "icloud")
        let b = SuggestionEvent(id: "b", title: "Field trip", location: nil,
                                start: date(2026, 11, 10, 6), isAllDay: true, calendarIdentifier: "google")
        XCTAssertEqual(SuggestionEngine.rules(input([a, b])).count, 1)
    }

    func testSameTitleDifferentStartKeepsBothSuggestions() {
        let early = SuggestionEvent(id: "e1", title: "Soccer practice", location: nil,
                                    start: date(2026, 11, 10, 15), isAllDay: false, calendarIdentifier: "icloud")
        let late = SuggestionEvent(id: "e2", title: "Soccer practice", location: nil,
                                   start: date(2026, 11, 10, 18), isAllDay: false, calendarIdentifier: "icloud")
        let out = SuggestionEngine.rules(input([early, late]))
        XCTAssertEqual(out.count, 2)
        XCTAssertEqual(out.map(\.eventID), ["e1", "e2"])
    }

    // MARK: Deduper

    private func item(_ title: String, member: UUID? = nil, recurrence: Recurrence = .daily,
                      kind: ChecklistItem.Kind = .check, createdAt: Date) -> ChecklistItem {
        ChecklistItem(title: title, forMember: member, kind: kind, recurrence: recurrence, createdAt: createdAt)
    }

    func testDeduperKeepsTheItemWithHistory() {
        let older = item("Vitamins", createdAt: date(2026, 11, 1))
        let newer = item("  vitamins ", createdAt: date(2026, 11, 5))
        let groups = ChecklistDeduper.duplicateGroups(items: [older, newer], completionCounts: [newer.id: 4, older.id: 1])
        XCTAssertEqual(groups.count, 1)
        XCTAssertEqual(groups.first?.keep, newer.id)
        XCTAssertEqual(groups.first?.archive, [older.id])
    }

    func testDeduperFallsBackToEarliestCreatedAt() {
        let older = item("Vitamins", createdAt: date(2026, 11, 1))
        let newer = item("Vitamins", createdAt: date(2026, 11, 5))
        let third = item("VITAMINS", createdAt: date(2026, 11, 7))
        let groups = ChecklistDeduper.duplicateGroups(items: [newer, third, older])
        XCTAssertEqual(groups.first?.keep, older.id)
        XCTAssertEqual(Set(groups.first?.archive ?? []), [newer.id, third.id])
    }

    func testDifferentMemberKindOrRecurrenceAreNotDuplicates() {
        let riley = HouseholdMember.sampleChild1.id
        let jordan = HouseholdMember.sampleChild2.id
        let items = [
            item("Pack bag", member: riley, createdAt: date(2026, 11, 1)),
            item("Pack bag", member: jordan, createdAt: date(2026, 11, 1)),
            item("Pack bag", createdAt: date(2026, 11, 1)),
            item("Pack bag", member: riley, recurrence: .weekdays([.monday]), createdAt: date(2026, 11, 1)),
            item("Pack bag", member: riley, kind: .timer(minutes: 5), createdAt: date(2026, 11, 1)),
        ]
        XCTAssertTrue(ChecklistDeduper.duplicateGroups(items: items).isEmpty)
    }

    func testArchivedItemsAreIgnored() {
        var archived = item("Vitamins", createdAt: date(2026, 11, 1))
        archived.archivedAt = date(2026, 11, 2)
        let active = item("Vitamins", createdAt: date(2026, 11, 3))
        XCTAssertTrue(ChecklistDeduper.duplicateGroups(items: [archived, active]).isEmpty)
    }

    func testNormalizedTitleCollapsesWhitespaceAndCase() {
        XCTAssertEqual(ChecklistDeduper.normalizedTitle("  Pack   Soccer\tbag "), "pack soccer bag")
    }

    // MARK: Store

    func testRemoveDuplicateItemsArchivesAndIsIdempotent() async throws {
        let store = makeStore()
        let now = date(2026, 11, 10)
        let keeper = ChecklistItem(title: "Vitamins", recurrence: .daily, createdAt: date(2026, 11, 5))
        let copy = ChecklistItem(title: "vitamins", recurrence: .daily, createdAt: date(2026, 11, 1))
        let other = ChecklistItem(title: "Walk", recurrence: .daily, createdAt: date(2026, 11, 1))
        for i in [keeper, copy, other] { try await store.saveItem(i) }
        // The newer copy has the completion history, so it is the one that stays.
        try await store.toggle(itemID: keeper.id, on: date(2026, 11, 9), at: date(2026, 11, 9))
        try await store.toggle(itemID: keeper.id, on: now, at: now)

        let removed = try await store.removeDuplicateItems(at: now)
        XCTAssertEqual(removed, 1)
        let active = try await store.items()
        XCTAssertEqual(Set(active.map(\.id)), [keeper.id, other.id])
        // Archived, not deleted: history stays reachable.
        let all = try await store.items(includeArchived: true)
        XCTAssertEqual(all.count, 3)
        XCTAssertNotNil(all.first { $0.id == copy.id }?.archivedAt)

        let second = try await store.removeDuplicateItems(at: now)
        XCTAssertEqual(second, 0)
        let stillActive = try await store.items()
        XCTAssertEqual(stillActive.count, 2)
    }

    func testRemoveDuplicateItemsOnCleanListReturnsZero() async throws {
        let store = makeStore()
        try await store.saveItem(ChecklistItem(title: "Vitamins", createdAt: date(2026, 11, 1)))
        try await store.saveItem(ChecklistItem(title: "Walk", createdAt: date(2026, 11, 1)))
        let removed = try await store.removeDuplicateItems(at: date(2026, 11, 10))
        XCTAssertEqual(removed, 0)
    }

    @MainActor
    func testViewModelLoadSweepsDuplicates() async throws {
        UserDefaults.standard.set(false, forKey: "health_enabled")
        UserDefaults.standard.set(false, forKey: "calendar_enabled")
        UserDefaults.standard.set(false, forKey: "weather_enabled")
        let store = makeStore()
        let now = date(2026, 11, 10)
        try await store.saveItem(ChecklistItem(title: "Vitamins", createdAt: date(2026, 11, 1)))
        try await store.saveItem(ChecklistItem(title: " Vitamins  ", createdAt: date(2026, 11, 2)))

        let model = ChecklistViewModel(store: store, now: now, calendar: la)
        await model.load()
        XCTAssertEqual(model.activeItems.count, 1)
        let again = await model.removeDuplicates()
        XCTAssertEqual(again, 0)
    }
}
