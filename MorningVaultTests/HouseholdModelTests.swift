import XCTest
@testable import MorningVault

final class HouseholdModelTests: XCTestCase {
    /// Los Angeles: DST ends 2026-11-01 (25 h day) and starts 2026-03-08 (23 h day).
    private var la: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "America/Los_Angeles")!
        c.locale = Locale(identifier: "en_US_POSIX")
        return c
    }

    private func date(_ y: Int, _ m: Int, _ d: Int, _ h: Int = 9, _ min: Int = 0, calendar: Calendar? = nil) -> Date {
        let cal = calendar ?? la
        return cal.date(from: DateComponents(year: y, month: m, day: d, hour: h, minute: min))!
    }

    private func hourly(every: Int, from: (Int, Int), to: (Int, Int)) -> Recurrence {
        .hourly(everyHours: every,
                from: DateComponents(hour: from.0, minute: from.1),
                to: DateComponents(hour: to.0, minute: to.1),
                on: Weekday.all)
    }

    // MARK: Recurrence

    func testMonthlyClampsFeb30ToLastDay() {
        let r = Recurrence.monthly(day: 30)
        // 2026 is not a leap year: Feb has 28 days.
        XCTAssertTrue(r.isScheduled(on: date(2026, 2, 28), calendar: la))
        XCTAssertFalse(r.isScheduled(on: date(2026, 2, 27), calendar: la))
        XCTAssertTrue(r.isScheduled(on: date(2026, 4, 30), calendar: la))
        XCTAssertFalse(r.isScheduled(on: date(2026, 4, 29), calendar: la))
        // Leap year: Feb 29.
        XCTAssertTrue(r.isScheduled(on: date(2028, 2, 29), calendar: la))
        // Day 31 on a 30-day month lands on the 30th.
        XCTAssertTrue(Recurrence.monthly(day: 31).isScheduled(on: date(2026, 6, 30), calendar: la))
    }

    func testEveryTwoWeeksAnchorAcrossAYear() {
        // Anchor Monday 2025-12-22; Mondays every two weeks: Jan 5, Jan 19, Feb 2... Dec 21 2026.
        let anchor = date(2025, 12, 22)
        let r = Recurrence.everyNWeeks(n: 2, on: [.monday], anchor: anchor)
        XCTAssertTrue(r.isScheduled(on: anchor, calendar: la))
        XCTAssertFalse(r.isScheduled(on: date(2025, 12, 29), calendar: la))
        XCTAssertTrue(r.isScheduled(on: date(2026, 1, 5), calendar: la))
        XCTAssertFalse(r.isScheduled(on: date(2026, 1, 12), calendar: la))
        XCTAssertTrue(r.isScheduled(on: date(2026, 1, 19), calendar: la))
        // 52 weeks later: still on cadence.
        XCTAssertTrue(r.isScheduled(on: date(2026, 12, 21), calendar: la))
        XCTAssertFalse(r.isScheduled(on: date(2026, 12, 28), calendar: la))
        // Wrong weekday never counts; before the anchor never counts.
        XCTAssertFalse(r.isScheduled(on: date(2026, 1, 6), calendar: la))
        XCTAssertFalse(r.isScheduled(on: date(2025, 12, 8), calendar: la))
    }

    func testOnceExpiresAfterItsDay() {
        let day = date(2026, 11, 10)
        let item = ChecklistItem(title: "Return library books", recurrence: .once(day), createdAt: date(2026, 11, 1))
        XCTAssertTrue(item.isScheduled(on: day, calendar: la))
        XCTAssertTrue(item.isScheduled(on: date(2026, 11, 10, 23, 59), calendar: la))
        XCTAssertFalse(item.isScheduled(on: date(2026, 11, 9), calendar: la))
        XCTAssertFalse(item.isScheduled(on: date(2026, 11, 11, 0, 1), calendar: la))
        XCTAssertNotNil(item.expiresAt)
    }

    func testWeekdaysAndDaily() {
        let monday = date(2026, 11, 9)
        let saturday = date(2026, 11, 14)
        XCTAssertTrue(Recurrence.daily.isScheduled(on: saturday, calendar: la))
        XCTAssertTrue(Recurrence.weekdays(Weekday.weekdays).isScheduled(on: monday, calendar: la))
        XCTAssertFalse(Recurrence.weekdays(Weekday.weekdays).isScheduled(on: saturday, calendar: la))
        XCTAssertTrue(Recurrence.weekdays(Weekday.weekends).isScheduled(on: saturday, calendar: la))
    }

    // MARK: Hourly slots

    func testHourlySlotCountOnTheHourVsMidHour() {
        let day = date(2026, 11, 10)
        // 8:00 to 20:00 every 2 h, inclusive: 8,10,12,14,16,18,20 = 7.
        XCTAssertEqual(hourly(every: 2, from: (8, 0), to: (20, 0)).slots(on: day, calendar: la).count, 7)
        // 8:00 to 19:30: 8,10,12,14,16,18 = 6.
        XCTAssertEqual(hourly(every: 2, from: (8, 0), to: (19, 30)).slots(on: day, calendar: la).count, 6)
        // 8:30 to 20:00 every 2 h: 8:30,10:30,...,18:30 = 6 (20:30 is past the end).
        let midStart = hourly(every: 2, from: (8, 30), to: (20, 0)).slots(on: day, calendar: la)
        XCTAssertEqual(midStart.count, 6)
        XCTAssertEqual(la.component(.minute, from: midStart[0]), 30)
        // Window that ends before it starts yields nothing, so the item is not scheduled.
        XCTAssertTrue(hourly(every: 1, from: (20, 0), to: (8, 0)).slots(on: day, calendar: la).isEmpty)
        XCTAssertFalse(hourly(every: 1, from: (20, 0), to: (8, 0)).isScheduled(on: day, calendar: la))
    }

    func testHourlyCapsAtTwelveSlots() {
        let day = date(2026, 11, 10)
        let slots = hourly(every: 1, from: (0, 0), to: (23, 0)).slots(on: day, calendar: la)
        XCTAssertEqual(slots.count, Recurrence.maxSlotsPerDay)
        XCTAssertEqual(slots.count, 12)
    }

    func testHourlyOnDSTDays() {
        // 2026-11-01: clocks fall back at 2:00 (25-hour day). Every hour 0:00-23:00 would be 24
        // wall-clock slots; cap is 12 and every slot stays on its wall-clock hour.
        let fallBack = date(2026, 11, 1, 12)
        let fb = hourly(every: 2, from: (0, 0), to: (23, 0)).slots(on: fallBack, calendar: la)
        XCTAssertEqual(fb.count, 12)
        XCTAssertEqual(fb.map { la.component(.hour, from: $0) }, [0, 2, 4, 6, 8, 10, 12, 14, 16, 18, 20, 22])

        // 2026-03-08: clocks spring forward at 2:00 (23-hour day); 2:00 does not exist and is skipped.
        let springForward = date(2026, 3, 8, 12)
        let sf = hourly(every: 1, from: (0, 0), to: (5, 0)).slots(on: springForward, calendar: la)
        XCTAssertEqual(sf.map { la.component(.hour, from: $0) }, [0, 1, 3, 4, 5])
        // Non-DST day for comparison.
        let plain = hourly(every: 1, from: (0, 0), to: (5, 0)).slots(on: date(2026, 3, 9, 12), calendar: la)
        XCTAssertEqual(plain.count, 6)
    }

    func testCurrentSlotIndex() {
        let r = hourly(every: 2, from: (8, 0), to: (18, 0))
        XCTAssertNil(r.currentSlotIndex(at: date(2026, 11, 10, 7, 59), calendar: la))
        XCTAssertEqual(r.currentSlotIndex(at: date(2026, 11, 10, 8, 0), calendar: la), 0)
        XCTAssertEqual(r.currentSlotIndex(at: date(2026, 11, 10, 11, 30), calendar: la), 1)
        XCTAssertEqual(r.currentSlotIndex(at: date(2026, 11, 10, 21, 0), calendar: la), 5)
    }

    // MARK: Ledger

    func testHourlyDoneOnlyWhenEverySlotChecked() {
        let now = date(2026, 11, 10, 12)
        let item = ChecklistItem(title: "Stretch", recurrence: hourly(every: 2, from: (8, 0), to: (18, 0)), createdAt: date(2026, 11, 1))
        let key = ChecklistDay.key(for: now, calendar: la)
        var ledger = ChecklistLedger(items: [item])
        XCTAssertFalse(ledger.isDone(item, on: now, calendar: la))
        ledger.completions = (0..<5).map { Completion(itemID: item.id, day: key, slotIndex: $0) }
        XCTAssertFalse(ledger.isDone(item, on: now, calendar: la))
        XCTAssertEqual(la.component(.hour, from: ledger.nextSlot(for: item, at: now, calendar: la)!), 18)
        ledger.completions.append(Completion(itemID: item.id, day: key, slotIndex: 5))
        XCTAssertTrue(ledger.isDone(item, on: now, calendar: la))
        XCTAssertNil(ledger.nextSlot(for: item, at: now, calendar: la))
    }

    func testProgressCountsScheduledItemsOnly() {
        let saturday = date(2026, 11, 14)
        let key = ChecklistDay.key(for: saturday, calendar: la)
        let created = date(2026, 11, 1)
        let lunches = ChecklistItem(title: "Pack lunches", recurrence: .weekdays(Weekday.weekdays), createdAt: created)
        let walk = ChecklistItem(title: "Walk", createdAt: created)
        let plants = ChecklistItem(title: "Plants", createdAt: created)
        let ledger = ChecklistLedger(items: [lunches, walk, plants],
                                     completions: [Completion(itemID: walk.id, day: key)],
                                     skips: [Skip(itemID: plants.id, day: key)])
        let p = ledger.progress(on: saturday, calendar: la)
        XCTAssertEqual(p.done, 1)
        XCTAssertEqual(p.total, 1)  // lunches not scheduled on Saturday; plants skipped
    }

    func testStreakPausesOnSkipAndBreaksOnMiss() {
        let created = date(2026, 10, 1)
        let item = ChecklistItem(title: "Walk", createdAt: created)
        let today = date(2026, 11, 10)
        func key(_ back: Int) -> String { ChecklistDay.key(for: la.date(byAdding: .day, value: -back, to: today)!, calendar: la) }

        // Done 1..5 days ago, skipped 3 days ago instead of done, today undone.
        var completions = [1, 2, 4, 5].map { Completion(itemID: item.id, day: key($0)) }
        var ledger = ChecklistLedger(items: [item], completions: completions, skips: [Skip(itemID: item.id, day: key(3))])
        XCTAssertEqual(ledger.streak(for: item, asOf: today, calendar: la), 4)

        // Today done adds one.
        completions.append(Completion(itemID: item.id, day: key(0)))
        ledger.completions = completions
        XCTAssertEqual(ledger.streak(for: item, asOf: today, calendar: la), 5)

        // Remove the skip: the missed day breaks the streak at 2 (+ today = 3).
        ledger.skips = []
        XCTAssertEqual(ledger.streak(for: item, asOf: today, calendar: la), 3)
    }

    func testStreakOnlyCountsScheduledDays() {
        let created = date(2026, 10, 1)
        let item = ChecklistItem(title: "Lunches", recurrence: .weekdays(Weekday.weekdays), createdAt: created)
        // Monday 2026-11-09 as "today", done Fri 6, Thu 5, Wed 4; the weekend is not scheduled.
        let monday = date(2026, 11, 9)
        let days = [date(2026, 11, 6), date(2026, 11, 5), date(2026, 11, 4)].map { ChecklistDay.key(for: $0, calendar: la) }
        let ledger = ChecklistLedger(items: [item], completions: days.map { Completion(itemID: item.id, day: $0) })
        XCTAssertEqual(ledger.streak(for: item, asOf: monday, calendar: la), 3)
    }

    func testTwelveItemCap() {
        var ledger = ChecklistLedger(items: (0..<11).map { ChecklistItem(title: "Item \($0)", order: $0) })
        XCTAssertTrue(ledger.canAddItem)
        ledger.items.append(ChecklistItem(title: "Item 11", order: 11))
        XCTAssertFalse(ledger.canAddItem)
        // Archived items do not count toward the cap.
        ledger.items[0].archivedAt = Date()
        XCTAssertTrue(ledger.canAddItem)
    }

    func testArchivedItemHiddenFromArchiveDayOn() {
        let item = ChecklistItem(title: "Old", createdAt: date(2026, 10, 1), archivedAt: date(2026, 11, 10, 9))
        XCTAssertTrue(item.isScheduled(on: date(2026, 11, 9), calendar: la))
        XCTAssertFalse(item.isScheduled(on: date(2026, 11, 10, 15), calendar: la))
        XCTAssertFalse(item.isScheduled(on: date(2026, 11, 11), calendar: la))
    }

    func testTitleAndNotesLimits() {
        let long = String(repeating: "a", count: 60)
        let item = ChecklistItem(title: long, notes: String(repeating: "n", count: 300))
        XCTAssertEqual(item.title.count, ChecklistItem.titleLimit)
        XCTAssertEqual(item.notes.count, ChecklistItem.notesLimit)
        XCTAssertFalse(ChecklistItem.isValidTitle("   "))
        XCTAssertTrue(ChecklistItem.isValidTitle("Walk"))
    }

    func testTemplatesExpandPerChild() {
        let named = ChecklistTemplate.timeWithChildren(members: HouseholdMember.sample)
        XCTAssertEqual(named.map(\.title), ["Time with Riley", "Time with Jordan"])
        let none = ChecklistTemplate.timeWithChildren(members: [HouseholdMember.sampleMe])
        XCTAssertEqual(none.map(\.title), ["Time with kids"])
    }

    func testRecurrenceRoundTripsThroughJSON() throws {
        let cases: [Recurrence] = [
            .daily, .weekdays(Weekday.weekends), .everyNWeeks(n: 3, on: [.tuesday], anchor: date(2026, 1, 6)),
            .monthly(day: 15), .once(date(2026, 12, 24)), hourly(every: 3, from: (9, 15), to: (21, 0)),
        ]
        for r in cases {
            let data = try JSONEncoder().encode(r)
            XCTAssertEqual(try JSONDecoder().decode(Recurrence.self, from: data), r)
        }
    }
}
