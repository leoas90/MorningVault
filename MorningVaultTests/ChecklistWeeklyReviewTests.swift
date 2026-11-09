import XCTest
@testable import MorningVault

/// The weekly review math: week boundaries, skips, hourly slots, mid-week creation, the
/// missed-weekday pattern and the achieved / work-on thresholds. Pure model, fixed calendar.
final class ChecklistWeeklyReviewTests: XCTestCase {

    // MARK: Fixtures

    /// Gregorian, UTC, so week boundaries never depend on the machine's zone.
    private var calendar: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        c.locale = Locale(identifier: "en_US_POSIX")
        return c
    }()

    private func date(_ year: Int, _ month: Int, _ day: Int, hour: Int = 9) -> Date {
        var c = DateComponents()
        c.year = year; c.month = month; c.day = day; c.hour = hour
        return calendar.date(from: c)!
    }

    /// Monday 2 Nov 2026 to Sunday 8 Nov 2026 is the reviewed week throughout.
    private var monday: Date { date(2026, 11, 2) }
    private var sunday: Date { date(2026, 11, 8) }
    /// Monday 9 Nov 2026: the day the Brief would show the review.
    private var nextMonday: Date { date(2026, 11, 9) }

    private func key(_ year: Int, _ month: Int, _ day: Int) -> String {
        ChecklistDay.key(for: date(year, month, day), calendar: calendar)
    }

    private func item(_ title: String, recurrence: Recurrence = .daily, created: Date? = nil,
                      reminder: ReminderRule? = nil, order: Int = 0) -> ChecklistItem {
        ChecklistItem(title: title, recurrence: recurrence, reminder: reminder, order: order,
                      createdAt: created ?? date(2026, 1, 1))
    }

    private func review(_ ledger: ChecklistLedger, weekStart: Date? = nil, asOf: Date? = nil,
                        members: [HouseholdMember] = []) -> ChecklistWeeklyReview {
        ChecklistWeeklyReview.make(from: ledger, weekStart: weekStart ?? monday, calendar: calendar,
                                   members: members, asOf: asOf)
    }

    // MARK: Week boundaries

    func testWeekStartIsMondayForEveryDayOfTheWeek() {
        let expected = calendar.startOfDay(for: monday)
        for offset in 0..<7 {
            let day = calendar.date(byAdding: .day, value: offset, to: monday)!
            XCTAssertEqual(ChecklistWeeklyReview.weekStart(containing: day, calendar: calendar), expected,
                           "offset \(offset)")
        }
        // The next Monday starts its own week.
        XCTAssertEqual(ChecklistWeeklyReview.weekStart(containing: nextMonday, calendar: calendar),
                       calendar.startOfDay(for: nextMonday))
    }

    func testWeekStartIgnoresTheCalendarsFirstWeekday() {
        var sundayFirst = calendar
        sundayFirst.firstWeekday = 1
        var saturdayFirst = calendar
        saturdayFirst.firstWeekday = 7
        let expected = calendar.startOfDay(for: monday)
        XCTAssertEqual(ChecklistWeeklyReview.weekStart(containing: sunday, calendar: sundayFirst), expected)
        XCTAssertEqual(ChecklistWeeklyReview.weekStart(containing: sunday, calendar: saturdayFirst), expected)
    }

    func testPreviousWeekStartAndIsMonday() {
        XCTAssertEqual(ChecklistWeeklyReview.previousWeekStart(containing: nextMonday, calendar: calendar),
                       calendar.startOfDay(for: monday))
        XCTAssertTrue(ChecklistWeeklyReview.isMonday(nextMonday, calendar: calendar))
        XCTAssertFalse(ChecklistWeeklyReview.isMonday(sunday, calendar: calendar))
    }

    func testReviewCoversExactlyMondayToSunday() {
        let daily = item("Water the plants")
        // One completion the Sunday before the week and one the Monday after it: neither counts.
        let ledger = ChecklistLedger(
            items: [daily],
            completions: [
                Completion(itemID: daily.id, day: key(2026, 11, 1)),
                Completion(itemID: daily.id, day: key(2026, 11, 9)),
                Completion(itemID: daily.id, day: key(2026, 11, 2)),
                Completion(itemID: daily.id, day: key(2026, 11, 8)),
            ])
        let r = review(ledger)
        XCTAssertEqual(r.weekStart, calendar.startOfDay(for: monday))
        XCTAssertEqual(r.weekEnd, calendar.startOfDay(for: sunday))
        XCTAssertEqual(r.scheduledTotal, 7)
        XCTAssertEqual(r.doneTotal, 2, "only the Monday and Sunday inside the week count")
    }

    // MARK: Skips

    func testSkippedDaysNeitherCountNorFail() {
        let daily = item("Kids' meds")
        var completions: [Completion] = []
        // Done Mon, Tue, Wed, Thu, Fri. Saturday skipped, Sunday missed.
        for day in 2...6 { completions.append(Completion(itemID: daily.id, day: key(2026, 11, day))) }
        let ledger = ChecklistLedger(items: [daily], completions: completions,
                                     skips: [Skip(itemID: daily.id, day: key(2026, 11, 7))])
        let r = review(ledger)
        let line = try! XCTUnwrap(r.items.first)
        XCTAssertEqual(line.scheduled, 6, "the skipped Saturday leaves the total")
        XCTAssertEqual(line.done, 5)
        XCTAssertEqual(line.skippedDays, 1)
        XCTAssertEqual(line.days[5], .skipped)
        XCTAssertEqual(line.days[6], .missed)
        XCTAssertEqual(r.scheduledTotal, 6)
        XCTAssertEqual(r.doneTotal, 5)
    }

    func testAnEntirelySkippedWeekScoresNothingAndIsNotAchieved() {
        let daily = item("Walk")
        let skips = (2...8).map { Skip(itemID: daily.id, day: key(2026, 11, $0)) }
        let r = review(ChecklistLedger(items: [daily], skips: skips))
        XCTAssertFalse(r.hasAnythingScheduled)
        XCTAssertEqual(r.scheduledTotal, 0)
        XCTAssertTrue(r.achieved.isEmpty)
        XCTAssertTrue(r.workOn.isEmpty)
        XCTAssertNil(r.spokenLine)
    }

    // MARK: Hourly slots

    func testHourlyItemCountsOneOccurrencePerSlot() {
        let hourly = item("Stretch", recurrence: .hourly(
            everyHours: 2, from: DateComponents(hour: 8, minute: 0), to: DateComponents(hour: 18, minute: 0),
            on: Weekday.all))
        // 8, 10, 12, 14, 16, 18 = six slots a day, seven days = 42 occurrences.
        var completions: [Completion] = []
        for slot in 0..<3 { completions.append(Completion(itemID: hourly.id, day: key(2026, 11, 2), slotIndex: slot)) }
        for slot in 0..<6 { completions.append(Completion(itemID: hourly.id, day: key(2026, 11, 3), slotIndex: slot)) }
        let r = review(ChecklistLedger(items: [hourly], completions: completions))
        let line = try! XCTUnwrap(r.items.first)
        XCTAssertEqual(line.scheduled, 42)
        XCTAssertEqual(line.done, 9, "three slots Monday plus six Tuesday")
        XCTAssertEqual(line.days[0], .partial, "a part-checked hourly day reads as partial")
        XCTAssertEqual(line.days[1], .done)
        XCTAssertEqual(line.days[2], .missed)
    }

    // MARK: Mid-week creation

    func testItemCreatedMidWeekOnlyCountsFromItsCreationDay() {
        let created = date(2026, 11, 4)  // Wednesday
        let fresh = item("Sign school forms", created: created)
        let completions = [Completion(itemID: fresh.id, day: key(2026, 11, 4)),
                           Completion(itemID: fresh.id, day: key(2026, 11, 5))]
        // A completion recorded before the item existed must not inflate the count.
        let r = review(ChecklistLedger(items: [fresh],
                                       completions: completions + [Completion(itemID: fresh.id, day: key(2026, 11, 2))]))
        let line = try! XCTUnwrap(r.items.first)
        XCTAssertEqual(line.scheduled, 5, "Wednesday through Sunday")
        XCTAssertEqual(line.done, 2)
        XCTAssertEqual(line.days[0], .notScheduled)
        XCTAssertEqual(line.days[1], .notScheduled)
        XCTAssertEqual(line.days[2], .done)
    }

    // MARK: Partial week

    func testThisWeekSoFarStopsAtTodayAndDoesNotCountLaterDaysAsMissed() {
        let daily = item("Pack lunches")
        let completions = [Completion(itemID: daily.id, day: key(2026, 11, 9)),
                           Completion(itemID: daily.id, day: key(2026, 11, 10))]
        let wednesday = date(2026, 11, 11)
        let r = ChecklistWeeklyReview.weekSoFar(from: ChecklistLedger(items: [daily], completions: completions),
                                                asOf: wednesday, calendar: calendar)
        let line = try! XCTUnwrap(r.items.first)
        XCTAssertTrue(r.isPartialWeek)
        XCTAssertEqual(r.weekStart, calendar.startOfDay(for: nextMonday))
        XCTAssertEqual(line.scheduled, 3, "Monday, Tuesday and Wednesday only")
        XCTAssertEqual(line.done, 2)
        XCTAssertEqual(line.days[3], .notScheduled, "Thursday is still ahead")
        XCTAssertEqual(line.days[6], .notScheduled)
    }

    // MARK: Most-missed weekday

    func testMostMissedWeekdayNeedsTwoMissesAndReportsTheCount() {
        // Tuesdays only, four weeks back from Sunday 8 Nov: 13, 20, 27 Oct and 3 Nov.
        let tuesday = item("Take out trash", recurrence: .weekdays([.tuesday]), reminder: ReminderRule(time: DateComponents(hour: 7)))
        let ledger = ChecklistLedger(items: [tuesday],
                                     completions: [Completion(itemID: tuesday.id, day: key(2026, 10, 20))])
        let r = review(ledger)
        let line = try! XCTUnwrap(r.items.first)
        XCTAssertEqual(line.mostMissedWeekday, .tuesday)
        XCTAssertEqual(line.mostMissedCount, 3)
        XCTAssertEqual(line.mostMissedOutOf, 4)
        XCTAssertEqual(r.workOn.first?.reason, "missed 3 of 4 Tuesdays")
    }

    func testOneMissIsNotAPattern() {
        // Scheduled on Tuesdays, missed only the most recent one.
        let tuesday = item("Take out trash", recurrence: .weekdays([.tuesday]))
        let done = [key(2026, 10, 13), key(2026, 10, 20), key(2026, 10, 27)]
            .map { Completion(itemID: tuesday.id, day: $0) }
        let r = review(ChecklistLedger(items: [tuesday], completions: done))
        let line = try! XCTUnwrap(r.items.first)
        XCTAssertNil(line.mostMissedWeekday)
    }

    func testADailyItemMissedEveryDayHasNoWeekdayPattern() {
        // Missed on all seven weekdays alike: that is not a Sunday problem.
        let daily = item("Stretch")
        let r = review(ChecklistLedger(items: [daily]))
        let line = try! XCTUnwrap(r.items.first)
        XCTAssertNil(line.mostMissedWeekday)
        XCTAssertEqual(r.workOn.first?.reason, "no reminder set: add one")
    }

    func testAStandoutWeekdayStillCountsForADailyItem() {
        // Daily item done every day except three Tuesdays and one Friday.
        let daily = item("Walk")
        var completions: [Completion] = []
        let missed = Set([key(2026, 10, 13), key(2026, 10, 20), key(2026, 11, 3), key(2026, 10, 16)])
        for offset in 0..<28 {
            let day = calendar.date(byAdding: .day, value: -offset, to: sunday)!
            let dayKey = ChecklistDay.key(for: day, calendar: calendar)
            if !missed.contains(dayKey) { completions.append(Completion(itemID: daily.id, day: dayKey)) }
        }
        let line = try! XCTUnwrap(review(ChecklistLedger(items: [daily], completions: completions)).items.first)
        XCTAssertEqual(line.mostMissedWeekday, .tuesday)
        XCTAssertEqual(line.mostMissedCount, 3)
        XCTAssertEqual(line.mostMissedOutOf, 4)
    }

    func testSkippedDaysAreNotCountedAsMissesInThePattern() {
        let tuesday = item("Take out trash", recurrence: .weekdays([.tuesday]))
        let skips = [key(2026, 10, 27), key(2026, 11, 3)].map { Skip(itemID: tuesday.id, day: $0) }
        let r = review(ChecklistLedger(items: [tuesday],
                                       completions: [Completion(itemID: tuesday.id, day: key(2026, 10, 13)),
                                                     Completion(itemID: tuesday.id, day: key(2026, 10, 20))],
                                       skips: skips))
        let line = try! XCTUnwrap(r.items.first)
        XCTAssertNil(line.mostMissedWeekday, "two skipped Tuesdays are not two missed Tuesdays")
    }

    // MARK: Thresholds

    func testAchievedAndWorkOnThresholds() {
        let good = item("Kids' meds", order: 0)          // 7 of 7
        let edge = item("Water the plants", order: 1)     // 6 of 7, 0.857 -> achieved
        let middling = item("Read 10 min", order: 2)      // 5 of 7, 0.714 -> neither
        let poor = item("Walk", order: 3)                 // 2 of 7, 0.286 -> work on
        var completions: [Completion] = []
        for day in 2...8 { completions.append(Completion(itemID: good.id, day: key(2026, 11, day))) }
        for day in 2...7 { completions.append(Completion(itemID: edge.id, day: key(2026, 11, day))) }
        for day in 2...6 { completions.append(Completion(itemID: middling.id, day: key(2026, 11, day))) }
        for day in 2...3 { completions.append(Completion(itemID: poor.id, day: key(2026, 11, day))) }

        let r = review(ChecklistLedger(items: [good, edge, middling, poor], completions: completions))
        XCTAssertEqual(r.achieved.map(\.title), ["Kids' meds", "Water the plants"])
        XCTAssertEqual(r.perfect.map(\.title), ["Kids' meds"])
        XCTAssertEqual(r.workOn.map(\.item.title), ["Walk"])
        XCTAssertEqual(r.doneTotal, 20)
        XCTAssertEqual(r.scheduledTotal, 28)
        XCTAssertEqual(r.countText, "20 of 28 done")
    }

    func testWorkOnIsLowestFirstAndCapsAtThree() {
        let items = (0..<5).map { item("Item \($0)", order: $0) }
        var completions: [Completion] = []
        // Item 0 done 0/7, item 1 1/7, ... item 4 4/7. Only the four under 60% qualify.
        for (index, line) in items.enumerated() where index > 0 {
            for day in 2..<(2 + index) { completions.append(Completion(itemID: line.id, day: key(2026, 11, day))) }
        }
        let r = review(ChecklistLedger(items: items, completions: completions))
        XCTAssertEqual(r.workOn.count, ChecklistWeeklyReview.maxWorkOn)
        XCTAssertEqual(r.workOn.map(\.item.title), ["Item 0", "Item 1", "Item 2"])
    }

    func testReasonIsTheMissingReminderWhenThereIsNoWeekdayPattern() {
        // Scheduled Tuesdays only, with a one-off history: no two misses on any weekday.
        let tuesday = item("Take out trash", recurrence: .weekdays([.tuesday]))
        let done = [key(2026, 10, 13), key(2026, 10, 20), key(2026, 10, 27)]
            .map { Completion(itemID: tuesday.id, day: $0) }
        let r = review(ChecklistLedger(items: [tuesday], completions: done))
        XCTAssertEqual(r.workOn.first?.reason, "no reminder set: add one")
    }

    // MARK: Delta, streak, members

    func testPreviousWeekRateDrivesTheDelta() throws {
        let daily = item("Water the plants")
        var list: [Completion] = []
        // Last week (2-8 Nov): 6 of 7. The week before (26 Oct - 1 Nov): 3 of 7.
        for day in 2...7 { list.append(Completion(itemID: daily.id, day: key(2026, 11, day))) }
        for day in 26...28 { list.append(Completion(itemID: daily.id, day: key(2026, 10, day))) }
        let r = review(ChecklistLedger(items: [daily], completions: list))
        XCTAssertEqual(r.previousDone, 3)
        XCTAssertEqual(r.previousScheduled, 7)
        XCTAssertEqual(try XCTUnwrap(r.delta), 3.0 / 7.0, accuracy: 0.0001)
        XCTAssertEqual(r.deltaText, "up from 3 of 7")
    }

    func testMemberLinesOnlyAppearWithMoreThanOneMember() {
        let daily = item("Pack lunches")
        let me = HouseholdMember.sampleMe
        let partner = HouseholdMember.samplePartner
        let completions = [
            Completion(itemID: daily.id, day: key(2026, 11, 2), byMember: me.id),
            Completion(itemID: daily.id, day: key(2026, 11, 3), byMember: me.id),
            Completion(itemID: daily.id, day: key(2026, 11, 4), byMember: partner.id),
        ]
        let ledger = ChecklistLedger(items: [daily], completions: completions)
        XCTAssertTrue(review(ledger, members: [me]).members.isEmpty)
        let lines = review(ledger, members: [me, partner]).members
        XCTAssertEqual(lines.map(\.name), [me.name, partner.name])
        XCTAssertEqual(lines.map(\.done), [2, 1])
    }

    // MARK: Spoken line

    func testSpokenLineNamesTheSlipAndStaysOneSentence() {
        let tuesday = item("Walk", recurrence: .weekdays([.tuesday]), order: 0)
        let ledger = ChecklistLedger(items: [tuesday],
                                     completions: [Completion(itemID: tuesday.id, day: key(2026, 10, 20))])
        let line = try! XCTUnwrap(review(ledger).spokenLine)
        XCTAssertEqual(line, "Last week you did 0 of 1 checklist items; walk slipped on Tuesdays.")
        XCTAssertEqual(line.filter { $0 == "." }.count, 1)
    }

    func testSpokenLineCallsOutAPerfectItemWhenNothingSlipped() {
        let daily = item("Kids' meds")
        var completions: [Completion] = []
        for day in 2...8 { completions.append(Completion(itemID: daily.id, day: key(2026, 11, day))) }
        let line = try! XCTUnwrap(review(ChecklistLedger(items: [daily], completions: completions)).spokenLine)
        XCTAssertEqual(line, "Last week you did 7 of 7 checklist items; kids' meds every time.")
    }

    // MARK: Voice cache

    func testVoiceCacheOnlyReturnsTheLineForTheWeekItDescribes() throws {
        let defaults = try XCTUnwrap(UserDefaults(suiteName: "test.weekly.\(UUID().uuidString)"))
        WeeklyReviewVoiceCache.save(line: "Last week you did 7 of 7 checklist items.", weekStart: monday,
                                    calendar: calendar, defaults: defaults)
        XCTAssertNotNil(WeeklyReviewVoiceCache.line(forWeekStarting: monday, calendar: calendar, defaults: defaults))
        XCTAssertNil(WeeklyReviewVoiceCache.line(forWeekStarting: nextMonday, calendar: calendar, defaults: defaults),
                     "a line for another week is never spoken")
        WeeklyReviewVoiceCache.save(line: nil, weekStart: monday, calendar: calendar, defaults: defaults)
        XCTAssertNil(WeeklyReviewVoiceCache.line(forWeekStarting: monday, calendar: calendar, defaults: defaults))
    }

    func testSpokenBriefOnlySaysTheWeeklyLineOnMondayAndWhenTheSectionIsOn() throws {
        let defaults = try XCTUnwrap(UserDefaults(suiteName: "test.weekly.\(UUID().uuidString)"))
        let line = "Last week you did 18 of 24 checklist items."
        WeeklyReviewVoiceCache.save(line: line, weekStart: monday, calendar: calendar, defaults: defaults)

        XCTAssertEqual(VoiceBriefingService.weeklyReviewLine(now: nextMonday, calendar: calendar,
                                                             enabled: true, defaults: defaults), line)
        XCTAssertNil(VoiceBriefingService.weeklyReviewLine(now: nextMonday, calendar: calendar,
                                                           enabled: false, defaults: defaults),
                     "the Weekly review toggle wins")
        XCTAssertNil(VoiceBriefingService.weeklyReviewLine(now: date(2026, 11, 10), calendar: calendar,
                                                           enabled: true, defaults: defaults),
                     "Tuesday says nothing")
    }

    func testShortBriefingIncludesTheWeeklyLineWhenGiven() {
        let text = VoiceBriefingService.compileShortBriefing(
            from: [], summary: "A quiet day.", now: nextMonday, checklist: nil, water: nil,
            weeklyReview: "Last week you did 18 of 24 checklist items.")
        XCTAssertTrue(text.contains("Last week you did 18 of 24 checklist items."), text)
        XCTAssertTrue(text.hasSuffix("A quiet day."), text)
        let without = VoiceBriefingService.compileShortBriefing(
            from: [], summary: "A quiet day.", now: nextMonday, checklist: nil, water: nil, weeklyReview: nil)
        XCTAssertFalse(without.contains("Last week"), without)
    }
}
