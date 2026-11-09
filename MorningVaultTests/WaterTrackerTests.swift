import XCTest
@testable import MorningVault

final class WaterTrackerTests: XCTestCase {
    private var la: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "America/Los_Angeles")!
        c.locale = Locale(identifier: "en_US_POSIX")
        return c
    }

    /// Monday 2026-11-09 at the given time.
    private func at(_ h: Int, _ m: Int = 0) -> Date {
        la.date(from: DateComponents(year: 2026, month: 11, day: 9, hour: h, minute: m))!
    }

    private func tracker(goal: Int = 2000, logged: [Int] = [], start: Int = 7 * 60, end: Int = 21 * 60, quiet: Bool = false) -> WaterTracker {
        let entries = logged.enumerated().map { index, ml in
            WaterEntry(ts: at(8).addingTimeInterval(TimeInterval(index * 60)), ml: ml)
        }
        return WaterTracker(goalML: goal, entries: entries, windowStartMinutes: start, windowEndMinutes: end, quietToday: quiet)
    }

    // MARK: Expected and deficit

    func testExpectedAtWindowBoundaries() {
        let t = tracker()
        XCTAssertEqual(t.expected(at: at(7), calendar: la), 0)
        XCTAssertEqual(t.expected(at: at(6), calendar: la), 0, "before the window is zero")
        XCTAssertEqual(t.expected(at: at(14), calendar: la), 1000, "midpoint of 07:00 to 21:00 is half the goal")
        XCTAssertEqual(t.expected(at: at(21), calendar: la), 2000)
        XCTAssertEqual(t.expected(at: at(23), calendar: la), 2000, "after the window is the goal")
    }

    func testDeficitFollowsLoggedAmount() {
        let t = tracker(logged: [250, 250])
        XCTAssertEqual(t.deficit(at: at(14), calendar: la), 500)
        XCTAssertEqual(t.deficit(at: at(7), calendar: la), -500, "ahead at the start")
        XCTAssertEqual(t.remaining(at: at(14), calendar: la), 1500)
        XCTAssertEqual(t.progress(at: at(14), calendar: la), 0.25, accuracy: 0.0001)
    }

    // MARK: Tiers

    func testTierBoundariesByGlass() {
        // 14:00 expects 1000. Logged 1000 -> quiet; 750 -> nudge (250); 500 -> reminder (500); 499 -> behind.
        XCTAssertEqual(tracker(logged: [1000]).tier(at: at(14), calendar: la), .quiet)
        XCTAssertEqual(tracker(logged: [1100]).tier(at: at(14), calendar: la), .quiet, "ahead is quiet")
        XCTAssertEqual(tracker(logged: [750]).tier(at: at(14), calendar: la), .nudge)
        XCTAssertEqual(tracker(logged: [999]).tier(at: at(14), calendar: la), .nudge, "one millilitre behind is still a nudge")
        XCTAssertEqual(tracker(logged: [500]).tier(at: at(14), calendar: la), .reminder)
        XCTAssertEqual(tracker(logged: [749]).tier(at: at(14), calendar: la), .reminder)
        XCTAssertEqual(tracker(logged: [499]).tier(at: at(14), calendar: la), .behind)
    }

    func testNothingByNoonIsBehind() {
        // 12:00 expects 714: a deficit of 714 would be behind anyway, so test an early window
        // where the deficit alone would be a nudge.
        let t = tracker(start: 11 * 60 + 30, end: 23 * 60)
        // 12:00 is 30 of 690 minutes in: expected 87, which is a nudge by deficit alone.
        XCTAssertEqual(t.deficit(at: at(12), calendar: la), 87)
        XCTAssertEqual(t.tier(at: at(12), calendar: la), .behind, "nothing logged by noon is behind")
        XCTAssertEqual(t.tier(at: at(11, 45), calendar: la), .nudge, "before noon the deficit decides")
        // One sip before noon and the noon rule no longer applies.
        var sipped = t
        sipped.entries = [WaterEntry(ts: at(11, 40), ml: 50)]
        XCTAssertEqual(sipped.tier(at: at(12), calendar: la), .nudge)
    }

    func testQuietDayAndOutsideWindowAreQuiet() {
        XCTAssertEqual(tracker(quiet: true).tier(at: at(14), calendar: la), .quiet)
        XCTAssertEqual(tracker().tier(at: at(6, 59), calendar: la), .quiet, "before the window")
        XCTAssertEqual(tracker().tier(at: at(21), calendar: la), .quiet, "at the end, nothing more")
        XCTAssertEqual(tracker().tier(at: at(22), calendar: la), .quiet)
        XCTAssertFalse(tracker().isInWindow(at(21), calendar: la))
        XCTAssertTrue(tracker().isInWindow(at(7), calendar: la))
    }

    func testEveningClose() {
        let t = tracker(logged: [500])
        XCTAssertEqual(t.eveningClose(on: at(10), calendar: la), at(20))
        XCTAssertTrue(t.needsEveningClose(on: at(10), calendar: la))
        XCTAssertFalse(tracker(logged: [2000]).needsEveningClose(on: at(10), calendar: la), "goal met: no close")
        XCTAssertFalse(tracker(logged: [500], quiet: true).needsEveningClose(on: at(10), calendar: la))
    }

    // MARK: Goal

    func testSuggestedGoalFromWeight() {
        XCTAssertEqual(WaterTracker.suggestedGoal(kg: 70), 2450)
        XCTAssertEqual(WaterTracker.suggestedGoal(kg: 80), 2800)
        XCTAssertEqual(WaterTracker.suggestedGoal(kg: 57.3), 2000, "2005.5 rounds to 2000")
        XCTAssertEqual(WaterTracker.suggestedGoal(kg: 0), WaterTracker.defaultGoalML)
        XCTAssertEqual(WaterTracker.suggestedGoal(kg: 500), WaterTracker.goalRange.upperBound, "clamped")
    }

    // MARK: Units

    func testVolumeConversion() {
        XCTAssertEqual(UnitsPreference.metric.formatVolume(ml: 2000), "2,000 mL")
        XCTAssertEqual(UnitsPreference.imperial.formatVolume(ml: 500), "17 oz")
        XCTAssertEqual(UnitsPreference.imperial.volumeValue(ml: 2000), 68)
        XCTAssertEqual(UnitsPreference.imperial.ml(fromVolume: 8), 237)
        XCTAssertEqual(UnitsPreference.metric.ml(fromVolume: 350), 350)
        XCTAssertEqual(UnitsPreference.imperial.kg(fromWeight: 154), 69.85, accuracy: 0.01)
        XCTAssertEqual(UnitsPreference.metric.spokenVolume(ml: 1000), "a litre")
        XCTAssertEqual(UnitsPreference.metric.spokenVolume(ml: 1500), "1.5 litres")
        XCTAssertEqual(UnitsPreference.metric.spokenVolume(ml: 500), "500 millilitres")
        XCTAssertEqual(UnitsPreference.imperial.spokenVolume(ml: 1000), "34 ounces")
    }

    func testEntriesOnDayNewestFirst() {
        var t = tracker(logged: [250, 500])
        t.entries.append(WaterEntry(ts: at(8).addingTimeInterval(-86400), ml: 999))
        let today = t.entries(on: at(12), calendar: la)
        XCTAssertEqual(today.map(\.ml), [500, 250])
        XCTAssertEqual(t.logged(at: at(12), calendar: la), 750, "yesterday does not count")
    }

    // MARK: Voice and Brief prefs

    func testVoiceLineOnlyWhenBehind() {
        let today = Calendar.current.startOfDay(for: Date())
        let two = today.addingTimeInterval(14 * 3600)
        let day = ChecklistDay.key(for: two)
        let behind = WaterTodaySnapshot(day: day, goalML: 2000, loggedML: 500,
                                        entries: [WaterEntry(ts: today.addingTimeInterval(8 * 3600), ml: 500)], quietToday: false)
        XCTAssertEqual(VoiceBriefingService.waterLine(behind, now: two, units: .metric, enabled: true), "Water: 1.5 litres to go.")
        XCTAssertNil(VoiceBriefingService.waterLine(behind, now: two, units: .metric, enabled: false), "tracker off")
        let onTrack = WaterTodaySnapshot(day: day, goalML: 2000, loggedML: 1500,
                                         entries: [WaterEntry(ts: today.addingTimeInterval(8 * 3600), ml: 1500)], quietToday: false)
        XCTAssertNil(VoiceBriefingService.waterLine(onTrack, now: two, units: .metric, enabled: true), "ahead: nothing to say")
        XCTAssertNil(VoiceBriefingService.waterLine(nil, now: two, units: .metric, enabled: true))
        let yesterday = WaterTodaySnapshot(day: "2000-01-01", goalML: 2000, loggedML: 0, entries: [], quietToday: false)
        XCTAssertNil(VoiceBriefingService.waterLine(yesterday, now: two, units: .metric, enabled: true), "stale snapshot")
    }

    func testWaterBriefSectionFollowsTheTrackerToggle() {
        let key = BriefSectionPrefs.waterEnabledKey
        let previous = UserDefaults.standard.object(forKey: key)
        defer { UserDefaults.standard.set(previous, forKey: key) }
        UserDefaults.standard.removeObject(forKey: key)
        UserDefaults(suiteName: BriefSectionPrefs.appGroup)?.removeObject(forKey: key)
        XCTAssertFalse(BriefSectionPrefs.isEnabled("water"), "off by default")
        UserDefaults.standard.set(true, forKey: key)
        XCTAssertTrue(BriefSectionPrefs.isEnabled("water"))
    }
}
