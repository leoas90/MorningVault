import XCTest
@testable import MorningVault

final class SuggestionEngineTests: XCTestCase {
    private var la: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "America/Los_Angeles")!
        return c
    }

    private func date(_ y: Int, _ m: Int, _ d: Int, _ h: Int = 9, _ min: Int = 0) -> Date {
        la.date(from: DateComponents(year: y, month: m, day: d, hour: h, minute: min))!
    }

    /// Tuesday 2026-11-10, 07:00.
    private var morning: Date { date(2026, 11, 10, 7) }

    private func event(_ title: String, at hour: Int = 16, location: String? = nil, allDay: Bool = false, calendar: String? = nil, id: String? = nil) -> SuggestionEvent {
        SuggestionEvent(id: id ?? title, title: title, location: location, start: date(2026, 11, 10, hour), isAllDay: allDay, calendarIdentifier: calendar)
    }

    private func input(_ events: [SuggestionEvent], members: [HouseholdMember] = HouseholdMember.sample,
                       mapping: [String: UUID?] = [:], decisions: [SuggestionDecision] = [], existing: [String] = [],
                       now: Date? = nil) -> SuggestionEngine.Input {
        SuggestionEngine.Input(events: events, members: members, calendarMembers: mapping, selectedCalendars: nil,
                               decisions: decisions, existingTitles: existing, now: now ?? morning, calendar: la)
    }

    // MARK: Keyword match

    func testKeywordMatchAndSportPlaceholder() {
        let out = SuggestionEngine.rules(input([event("Soccer practice")]))
        XCTAssertEqual(out.count, 1)
        XCTAssertEqual(out.first?.ruleID, "practice")
        XCTAssertEqual(out.first?.title, "Pack soccer bag")

        let plain = SuggestionEngine.rules(input([event("Practice")]))
        XCTAssertEqual(plain.first?.title, "Pack practice bag")
    }

    func testMatchIsCaseInsensitiveAndUsesLocation() {
        let out = SuggestionEngine.rules(input([event("Checkup", location: "DENTIST on Main")]))
        XCTAssertEqual(out.first?.ruleID, "doctor")
        XCTAssertEqual(out.first?.title, "Insurance card, questions")
    }

    func testBestRuleByKeywordCount() {
        // "practice" (1) vs "game" + "tournament" (2): the game rule wins.
        let out = SuggestionEngine.rules(input([event("Tournament game, no practice")]))
        XCTAssertEqual(out.first?.ruleID, "game")
    }

    func testNoRuleNoSuggestion() {
        XCTAssertTrue(SuggestionEngine.rules(input([event("Standup")])).isEmpty)
    }

    // MARK: Person inference

    func testInferenceOrderCalendarThenNameThenHome() {
        let riley = HouseholdMember.sampleChild1
        let jordan = HouseholdMember.sampleChild2
        // Calendar mapping beats the name in the title.
        let mapped = SuggestionEngine.rules(input([event("Riley soccer practice", calendar: "cal-jordan")], mapping: ["cal-jordan": jordan.id]))
        XCTAssertEqual(mapped.first?.forMember, jordan.id)
        // A calendar mapped to Home (nil) still wins over the name.
        let home = SuggestionEngine.rules(input([event("Riley soccer practice", calendar: "cal-home")], mapping: ["cal-home": nil]))
        XCTAssertNil(home.first?.forMember)
        // No mapping: the name in the title.
        let named = SuggestionEngine.rules(input([event("Riley soccer practice", calendar: "cal-x")]))
        XCTAssertEqual(named.first?.forMember, riley.id)
        // Nothing: Home.
        let none = SuggestionEngine.rules(input([event("Soccer practice")]))
        XCTAssertNil(none.first?.forMember)
    }

    // MARK: Caps and filters

    func testMaxThreePerDayEarliestFirst() {
        let events = [
            event("Dentist", at: 18, id: "d"),
            event("Soccer practice", at: 16, id: "s"),
            event("Piano lesson", at: 15, id: "p"),
            event("Library", at: 17, id: "l"),
        ]
        let out = SuggestionEngine.rules(input(events))
        XCTAssertEqual(out.count, 3)
        XCTAssertEqual(out.map(\.eventID), ["p", "s", "l"])
    }

    func testNeverDecisionSuppresses() {
        let decision = SuggestionDecision(ruleID: "practice", titlePattern: SuggestionDecision.pattern(for: "Soccer Practice"))
        let out = SuggestionEngine.rules(input([event("soccer practice"), event("Swim practice", at: 17)], decisions: [decision]))
        XCTAssertEqual(out.map(\.eventTitle), ["Swim practice"])
    }

    func testEventsWithinSixtyMinutesAreSkipped() {
        let soon = event("Soccer practice", at: 7)   // 07:00 now, event 07:00
        let inFifty = SuggestionEvent(id: "x", title: "Soccer practice", location: nil, start: date(2026, 11, 10, 7, 50), isAllDay: false, calendarIdentifier: nil)
        let later = event("Dentist", at: 8)          // exactly 60 min: allowed
        let out = SuggestionEngine.rules(input([soon, inFifty, later]))
        XCTAssertEqual(out.map(\.eventTitle), ["Dentist"])
    }

    func testAllDayOnlyForFieldTripAndBirthday() {
        let events = [
            event("School", allDay: true),
            event("Field trip", allDay: true, id: "ft"),
            event("Riley's birthday", allDay: true, id: "bd"),
            event("Soccer practice", allDay: true),
        ]
        let out = SuggestionEngine.rules(input(events))
        XCTAssertEqual(Set(out.map(\.eventID)), ["ft", "bd"])
    }

    func testIdenticalItemTodaySuppresses() {
        let out = SuggestionEngine.rules(input([event("Soccer practice")], existing: ["pack soccer bag"]))
        XCTAssertTrue(out.isEmpty)
    }

    func testSchoolRuleIsWeekdaysOnly() {
        // 2026-11-14 is a Saturday.
        let saturday = SuggestionEvent(id: "s", title: "School fair", location: nil, start: date(2026, 11, 14, 10), isAllDay: false, calendarIdentifier: nil)
        XCTAssertTrue(SuggestionEngine.rules(input([saturday], now: date(2026, 11, 14, 7))).isEmpty)
    }

    func testSelectedCalendarsScope() {
        var i = input([event("Soccer practice", calendar: "off"), event("Dentist", at: 17, calendar: "on")])
        i.selectedCalendars = ["on"]
        XCTAssertEqual(SuggestionEngine.rules(i).map(\.eventTitle), ["Dentist"])
    }

    // MARK: Preview

    func testPreviewExpiryAfterSevenDays() {
        let started = date(2026, 11, 1)
        XCTAssertFalse(SuggestionsCache.previewElapsed(started: started, now: date(2026, 11, 7, 23), calendar: la))
        XCTAssertTrue(SuggestionsCache.previewElapsed(started: started, now: date(2026, 11, 8, 0, 5), calendar: la))

        let defaults = UserDefaults(suiteName: "SuggestionEngineTests.preview")!
        defaults.removePersistentDomain(forName: "SuggestionEngineTests.preview")
        XCTAssertTrue(SuggestionsCache.previewActive(now: started, defaults: defaults, calendar: la))
        XCTAssertEqual(defaults.object(forKey: SuggestionsCache.previewStartedKey) as? Date, started)
        XCTAssertTrue(SuggestionsCache.previewActive(now: date(2026, 11, 5), defaults: defaults, calendar: la))
        XCTAssertFalse(SuggestionsCache.previewActive(now: date(2026, 11, 9), defaults: defaults, calendar: la))
    }

    func testSuggestionIDsAreDistinctPerEventAndRule() {
        let ids = Suggestion.sample.map(\.id)
        XCTAssertEqual(Set(ids).count, ids.count)
        XCTAssertTrue(ids[0].hasPrefix(Suggestion.sample[0].eventID + "|"))
    }

    func testCacheRoundTrip() {
        let defaults = UserDefaults(suiteName: "SuggestionEngineTests.cache")!
        defaults.removePersistentDomain(forName: "SuggestionEngineTests.cache")
        let cache = SuggestionsCache(day: "2026-11-10", computedAt: morning, suggestions: Suggestion.sample, dismissed: ["evt-2"])
        cache.save(defaults: defaults)
        XCTAssertEqual(SuggestionsCache.load(defaults: defaults), cache)
    }
}
