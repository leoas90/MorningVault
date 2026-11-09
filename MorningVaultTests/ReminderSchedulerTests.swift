import XCTest
@testable import MorningVault

final class ReminderSchedulerTests: XCTestCase {
    private var la: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "America/Los_Angeles")!
        return c
    }

    private func date(_ y: Int, _ m: Int, _ d: Int, _ h: Int = 9, _ min: Int = 0) -> Date {
        la.date(from: DateComponents(year: y, month: m, day: d, hour: h, minute: min))!
    }

    /// Monday 2026-11-09, 06:00.
    private var monday6: Date { date(2026, 11, 9, 6) }

    private func item(_ title: String = "Walk", hour: Int = 7, minute: Int = 30, urgency: ReminderRule.Urgency = .normal,
                      recurrence: Recurrence = .daily, forMember: UUID? = nil) -> ChecklistItem {
        ChecklistItem(title: title, forMember: forMember, recurrence: recurrence,
                      reminder: ReminderRule(time: DateComponents(hour: hour, minute: minute), urgency: urgency),
                      createdAt: date(2026, 11, 1))
    }

    private func context(now: Date, me: UUID? = nil, opened: Date? = nil, pro: Bool = true, cap: Int = 40) -> ReminderScheduler.Context {
        ReminderScheduler.Context(now: now, calendar: la, meMemberID: me, briefLastOpened: opened, isPro: pro, days: 7, cap: cap)
    }

    // MARK: Scheduled days

    func testOnlyScheduledDaysGetReminders() {
        let weekdays = item(urgency: .gentle, recurrence: .weekdays(Weekday.weekdays))
        let plans = ReminderScheduler.plan(ledger: ChecklistLedger(items: [weekdays]), context: context(now: monday6))
        // Mon-Fri of this week only: five primaries, no follow-ups for Gentle.
        XCTAssertEqual(plans.count, 5)
        for plan in plans {
            let weekday = la.component(.weekday, from: plan.fireAt)
            XCTAssertTrue((2...6).contains(weekday), "fired on weekend: \(plan.fireAt)")
        }
    }

    func testDoneAndSkippedDaysAreSkipped() {
        let walk = item(urgency: .gentle)
        let today = ChecklistDay.key(for: monday6, calendar: la)
        let tomorrow = ChecklistDay.key(for: date(2026, 11, 10), calendar: la)
        let ledger = ChecklistLedger(items: [walk],
                                     completions: [Completion(itemID: walk.id, day: today, at: monday6)],
                                     skips: [Skip(itemID: walk.id, day: tomorrow)])
        let plans = ReminderScheduler.plan(ledger: ledger, context: context(now: monday6))
        XCTAssertEqual(plans.count, 5)
        XCTAssertFalse(plans.contains { $0.day == today })
        XCTAssertFalse(plans.contains { $0.day == tomorrow })
    }

    func testPastTimesTodayAreSkipped() {
        let walk = item(hour: 5, urgency: .gentle)  // 5:00, before the 6:00 "now"
        let plans = ReminderScheduler.plan(ledger: ChecklistLedger(items: [walk]), context: context(now: monday6))
        XCTAssertEqual(plans.count, 6)
        XCTAssertTrue(plans.allSatisfy { $0.fireAt > monday6 })
    }

    // MARK: Assignee

    func testAssigneeFilter() {
        let me = HouseholdMember.sampleMe.id
        let partner = HouseholdMember.samplePartner.id
        let mine = item("Mine", urgency: .gentle, forMember: me)
        let theirs = item("Theirs", urgency: .gentle, forMember: partner)
        let shared = item("Shared", urgency: .gentle, forMember: nil)
        let ledger = ChecklistLedger(items: [mine, theirs, shared])

        let onMyPhone = ReminderScheduler.plan(ledger: ledger, context: context(now: monday6, me: me))
        XCTAssertEqual(Set(onMyPhone.map(\.title)), ["Mine", "Shared"])

        // No "This is me" chosen: nothing is filtered.
        let unassigned = ReminderScheduler.plan(ledger: ledger, context: context(now: monday6, me: nil))
        XCTAssertEqual(Set(unassigned.map(\.title)), ["Mine", "Theirs", "Shared"])
    }

    // MARK: Urgency follow-ups

    func testFollowUpCountsPerUrgency() {
        let gentle = item("G", urgency: .gentle)
        let normal = item("N", urgency: .normal)
        let must = item("M", urgency: .mustDo)
        let ctx = context(now: monday6)
        let dayPlans = { (i: ChecklistItem) -> [ReminderPlan] in
            ReminderScheduler.plan(ledger: ChecklistLedger(items: [i]), context: ctx).filter { $0.day == "2026-11-09" }
        }
        XCTAssertEqual(dayPlans(gentle).filter(\.isFollowUp).count, 0)
        XCTAssertEqual(dayPlans(normal).filter(\.isFollowUp).count, 1)
        XCTAssertEqual(dayPlans(normal).first { $0.isFollowUp }?.fireAt, date(2026, 11, 9, 8, 30))
        let m = dayPlans(must)
        XCTAssertEqual(m.filter(\.isFollowUp).count, 3)
        XCTAssertEqual(m.map(\.fireAt), [date(2026, 11, 9, 7, 30), date(2026, 11, 9, 8, 15), date(2026, 11, 9, 9, 0), date(2026, 11, 9, 9, 45)])
        XCTAssertTrue(m.allSatisfy { $0.urgency == .mustDo })
    }

    func testHourlyFiresPerSlotWithoutFollowUps() {
        let stretch = ChecklistItem(
            title: "Stretch",
            recurrence: .hourly(everyHours: 2, from: DateComponents(hour: 8, minute: 0), to: DateComponents(hour: 18, minute: 0), on: Weekday.all),
            reminder: ReminderRule(time: DateComponents(hour: 8, minute: 0), urgency: .mustDo),
            createdAt: date(2026, 11, 1))
        let today = ChecklistDay.key(for: monday6, calendar: la)
        let ledger = ChecklistLedger(items: [stretch], completions: [Completion(itemID: stretch.id, day: today, slotIndex: 0, at: monday6)])
        let plans = ReminderScheduler.plan(ledger: ledger, context: context(now: date(2026, 11, 9, 9), cap: 100)).filter { $0.day == today }
        // Six slots (8, 10, 12, 14, 16, 18); slot 0 done, slot at 8 is past anyway: five left.
        XCTAssertEqual(plans.count, 5)
        XCTAssertEqual(plans.map(\.slotIndex), [1, 2, 3, 4, 5])
        XCTAssertTrue(plans.allSatisfy { !$0.isFollowUp })
    }

    // MARK: Cutoff

    func testNothingAtOrAfterTenPM() {
        let late = item("Late", hour: 21, minute: 30, urgency: .mustDo)
        let plans = ReminderScheduler.plan(ledger: ChecklistLedger(items: [late]), context: context(now: monday6)).filter { $0.day == "2026-11-09" }
        // 21:30 primary only; 22:15, 23:00, 23:45 follow-ups are dropped.
        XCTAssertEqual(plans.map(\.fireAt), [date(2026, 11, 9, 21, 30)])
        let tooLate = item("Too late", hour: 22, minute: 0, urgency: .normal)
        XCTAssertTrue(ReminderScheduler.plan(ledger: ChecklistLedger(items: [tooLate]), context: context(now: monday6)).isEmpty)
    }

    // MARK: Gentle while reading

    func testGentleDroppedWithinTenMinutesOfBriefOpen() {
        let now = date(2026, 11, 9, 7, 25)
        let gentle = item("G", hour: 7, minute: 30, urgency: .gentle)
        let normal = item("N", hour: 7, minute: 30, urgency: .normal)
        let ledger = ChecklistLedger(items: [gentle, normal])
        let plans = ReminderScheduler.plan(ledger: ledger, context: context(now: now, opened: now)).filter { $0.day == "2026-11-09" }
        XCTAssertEqual(plans.map(\.title), ["N", "N"])
        // Opened long ago: Gentle fires.
        let later = ReminderScheduler.plan(ledger: ledger, context: context(now: now, opened: date(2026, 11, 9, 6))).filter { $0.day == "2026-11-09" }
        XCTAssertTrue(later.contains { $0.title == "G" })
    }

    // MARK: Identifiers and cap

    func testIdentifierCleanupOnlyTouchesCheckRequests() {
        let pending = ["check.a.2026-11-09.0", "timer.b", "morning_brief_weekday_2", "check.snooze.x", "test_briefing_1"]
        XCTAssertEqual(ReminderScheduler.identifiersToCancel(pending: pending), ["check.a.2026-11-09.0", "check.snooze.x"])
        XCTAssertEqual(ReminderScheduler.foreignCount(pending: pending), 3)
    }

    func testIdentifiersAreUniqueAndPrefixed() {
        let items = (0..<3).map { item("I\($0)", urgency: .mustDo) }
        let plans = ReminderScheduler.plan(ledger: ChecklistLedger(items: items), context: context(now: monday6, cap: 200))
        XCTAssertEqual(Set(plans.map(\.identifier)).count, plans.count)
        XCTAssertTrue(plans.allSatisfy { $0.identifier.hasPrefix("check.") })
    }

    func testCapKeepsTotalUnderForty() {
        // Six Must do items x 7 days x 4 fires = 168 candidates.
        let items = (0..<6).map { item("I\($0)", urgency: .mustDo) }
        let pendingElsewhere = ["morning_brief_weekday_2", "morning_brief_weekday_3", "timer.x"]
        let cap = ReminderScheduler.totalCap - ReminderScheduler.foreignCount(pending: pendingElsewhere)
        let plans = ReminderScheduler.plan(ledger: ChecklistLedger(items: items), context: context(now: monday6, cap: cap))
        XCTAssertEqual(plans.count, 37)
        XCTAssertLessThan(plans.count + pendingElsewhere.count, 41)
        // Soonest first, so the near days survive the cut.
        XCTAssertEqual(plans.map(\.fireAt), plans.map(\.fireAt).sorted())
    }

    func testNothingWithoutPro() {
        let plans = ReminderScheduler.plan(ledger: ChecklistLedger(items: [item()]), context: context(now: monday6, pro: false))
        XCTAssertTrue(plans.isEmpty)
    }
}
