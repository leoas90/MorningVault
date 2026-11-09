import XCTest
import UserNotifications
@testable import MorningVault

final class WaterReminderSchedulerTests: XCTestCase {
    private var la: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "America/Los_Angeles")!
        c.locale = Locale(identifier: "en_US_POSIX")
        return c
    }

    private func at(_ h: Int, _ m: Int = 0) -> Date {
        la.date(from: DateComponents(year: 2026, month: 11, day: 9, hour: h, minute: m))!
    }

    private func tracker(logged: [Int] = [], quiet: Bool = false) -> WaterTracker {
        let entries = logged.map { WaterEntry(ts: at(7, 30), ml: $0) }
        return WaterTracker(goalML: 2000, entries: entries, windowStartMinutes: 7 * 60, windowEndMinutes: 21 * 60, quietToday: quiet)
    }

    private func context(now: Date, pro: Bool = true, enabled: Bool = true, urgent: Bool = false, snoozed: Date? = nil) -> WaterReminderScheduler.Context {
        WaterReminderScheduler.Context(now: now, calendar: la, isPro: pro, isEnabled: enabled, urgentOptIn: urgent, snoozedUntil: snoozed, units: .metric)
    }

    private func tiers(_ plans: [WaterReminderPlan]) -> [WaterTier] {
        plans.compactMap { if case .tier(let t) = $0.kind { return t } else { return nil } }
    }

    // MARK: Counts and tiers

    func testPlanFromWindowStartEscalatesAndCapsAtEight() {
        let plans = WaterReminderScheduler.plan(tracker: tracker(), context: context(now: at(7)))
        XCTAssertEqual(plans.count, 8)
        XCTAssertLessThanOrEqual(plans.count, WaterReminderScheduler.maxRequests)
        // 07:45 and 08:30 are within a glass; 09:15 and 10:00 within two; then behind.
        XCTAssertEqual(tiers(plans), [.nudge, .nudge, .reminder, .reminder, .behind, .behind, .behind])
        XCTAssertEqual(plans.first?.fireAt, at(7, 45))
        XCTAssertEqual(plans.last?.kind, .eveningClose)
        XCTAssertEqual(plans.last?.fireAt, at(20), "evening close is 60 minutes before the end")
        XCTAssertTrue(plans.last?.body.contains("2,000 mL to go") ?? false)
        XCTAssertTrue(plans.allSatisfy { $0.identifier.hasPrefix("water.2026-11-09.") })
        XCTAssertEqual(Set(plans.map(\.identifier)).count, plans.count, "identifiers are unique")
    }

    func testSlotsAreAtLeast45MinutesApart() {
        let plans = WaterReminderScheduler.plan(tracker: tracker(logged: [100]), context: context(now: at(9, 10)))
        let times = plans.filter { $0.kind != .eveningClose }.map(\.fireAt)
        XCTAssertFalse(times.isEmpty)
        for (a, b) in zip(times, times.dropFirst()) {
            XCTAssertGreaterThanOrEqual(b.timeIntervalSince(a), 45 * 60)
        }
        XCTAssertEqual(times.first, at(9, 55), "first slot is one interval from now")
    }

    func testMustDoCappedAtThreePerDay() {
        // Nothing logged after noon: every slot is behind by the noon rule.
        let plans = WaterReminderScheduler.plan(tracker: tracker(), context: context(now: at(13)))
        let t = tiers(plans)
        XCTAssertEqual(t.filter { $0 == .behind }.count, 3)
        XCTAssertEqual(t.prefix(3), [.behind, .behind, .behind])
        XCTAssertTrue(t.dropFirst(3).allSatisfy { $0 == .reminder }, "extra Must do slots fall back to Normal")
        XCTAssertTrue(plans.first?.body.contains("behind") ?? false)
    }

    func testOnTrackSchedulesNothing() {
        let plans = WaterReminderScheduler.plan(tracker: tracker(logged: [2000]), context: context(now: at(9)))
        XCTAssertTrue(plans.isEmpty, "goal met: no slots and no evening close")
    }

    func testAheadNowBehindLaterSkipsQuietSlots() {
        // 500 at 07:30; on track until about 10:30, then nudges start.
        let plans = WaterReminderScheduler.plan(tracker: tracker(logged: [500]), context: context(now: at(8)))
        XCTAssertFalse(plans.isEmpty)
        XCTAssertGreaterThan(plans.first!.fireAt, at(10, 30))
        XCTAssertEqual(tiers(plans).first, .nudge)
    }

    // MARK: Quiet, window, gates

    func testQuietDaySchedulesNothing() {
        XCTAssertTrue(WaterReminderScheduler.plan(tracker: tracker(quiet: true), context: context(now: at(9))).isEmpty)
    }

    func testNothingAfterWindowEnd() {
        XCTAssertTrue(WaterReminderScheduler.plan(tracker: tracker(), context: context(now: at(21))).isEmpty)
        XCTAssertTrue(WaterReminderScheduler.plan(tracker: tracker(), context: context(now: at(22, 30))).isEmpty)
        // After the evening close but before the end: nothing left to say.
        XCTAssertTrue(WaterReminderScheduler.plan(tracker: tracker(), context: context(now: at(20, 30))).isEmpty)
        // Just before the close: one slot and the close, both before 21:00.
        let late = WaterReminderScheduler.plan(tracker: tracker(logged: [1500]), context: context(now: at(19)))
        XCTAssertEqual(late.map(\.fireAt), [at(19, 45), at(20)])
        XCTAssertTrue(late.allSatisfy { $0.fireAt < at(21) })
    }

    func testBeforeWindowStartsAtStart() {
        let plans = WaterReminderScheduler.plan(tracker: tracker(), context: context(now: at(5)))
        // 07:00 itself is on track (nothing expected yet); the first nudge is 07:45.
        XCTAssertEqual(plans.first?.fireAt, at(7, 45), "slots wait for the window")
        XCTAssertTrue(plans.allSatisfy { $0.fireAt >= at(7) })
        XCTAssertFalse(tiers(plans).contains(.quiet))
    }

    func testProOffAndTrackerOffScheduleNothing() {
        XCTAssertTrue(WaterReminderScheduler.plan(tracker: tracker(), context: context(now: at(9), pro: false)).isEmpty)
        XCTAssertTrue(WaterReminderScheduler.plan(tracker: tracker(), context: context(now: at(9), enabled: false)).isEmpty)
    }

    func testSnoozePushesTheNextSlot() {
        let plans = WaterReminderScheduler.plan(tracker: tracker(), context: context(now: at(9), snoozed: at(9, 30)))
        XCTAssertEqual(plans.first?.fireAt, at(9, 30))
        let stale = WaterReminderScheduler.plan(tracker: tracker(), context: context(now: at(9), snoozed: at(8)))
        XCTAssertEqual(stale.first?.fireAt, at(9, 45), "an old snooze is ignored")
    }

    // MARK: Requests

    func testInterruptionLevelsFollowTierAndOptIn() {
        let nudge = WaterReminderPlan(identifier: "water.a", fireAt: at(10), kind: .tier(.nudge), title: "Water", body: "")
        let normal = WaterReminderPlan(identifier: "water.b", fireAt: at(10), kind: .tier(.reminder), title: "Water", body: "")
        let behind = WaterReminderPlan(identifier: "water.c", fireAt: at(10), kind: .tier(.behind), title: "Water", body: "")
        let close = WaterReminderPlan(identifier: "water.d", fireAt: at(20), kind: .eveningClose, title: "Water", body: "")

        XCTAssertEqual(WaterReminderScheduler.request(for: nudge, urgentOptIn: true, timeSensitiveAllowed: true, calendar: la).content.interruptionLevel, .passive)
        XCTAssertNil(WaterReminderScheduler.request(for: nudge, urgentOptIn: true, timeSensitiveAllowed: true, calendar: la).content.sound)
        XCTAssertEqual(WaterReminderScheduler.request(for: normal, urgentOptIn: true, timeSensitiveAllowed: true, calendar: la).content.interruptionLevel, .active)
        XCTAssertEqual(WaterReminderScheduler.request(for: close, urgentOptIn: true, timeSensitiveAllowed: true, calendar: la).content.interruptionLevel, .active)
        // Tier 3 is time sensitive only when the user opted in and iOS allows it.
        XCTAssertEqual(WaterReminderScheduler.request(for: behind, urgentOptIn: true, timeSensitiveAllowed: true, calendar: la).content.interruptionLevel, .timeSensitive)
        XCTAssertEqual(WaterReminderScheduler.request(for: behind, urgentOptIn: false, timeSensitiveAllowed: true, calendar: la).content.interruptionLevel, .active)
        XCTAssertEqual(WaterReminderScheduler.request(for: behind, urgentOptIn: true, timeSensitiveAllowed: false, calendar: la).content.interruptionLevel, .active)
        let request = WaterReminderScheduler.request(for: behind, urgentOptIn: true, timeSensitiveAllowed: true, calendar: la)
        XCTAssertEqual(request.content.categoryIdentifier, "WATER_REMIND")
        XCTAssertNotEqual(request.content.interruptionLevel, .critical)
    }

    func testIdentifierCleanupOnlyTouchesWater() {
        let pending = ["water.2026-11-09.0", "water.2026-11-09.close", "water.snooze.abc", "check.x.2026-11-09", "timer.y", "morning_brief_weekday_2"]
        XCTAssertEqual(WaterReminderScheduler.identifiersToCancel(pending: pending), ["water.2026-11-09.0", "water.2026-11-09.close", "water.snooze.abc"])
    }

    func testWaterCategoryHasBackgroundActions() {
        let water = TrackerNotificationService.allCategories.first { $0.identifier == "WATER_REMIND" }
        XCTAssertNotNil(water)
        XCTAssertEqual(water?.actions.map(\.identifier), ["LOG_250", "LOG_500", "SNOOZE_30"])
        XCTAssertTrue(water?.actions.allSatisfy { !$0.options.contains(.foreground) } ?? false, "actions run in the background")
    }
}
