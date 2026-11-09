import XCTest
@testable import MorningVault

final class WaterIntentsTests: XCTestCase {
    private var today: String { ChecklistDay.key(for: Date()) }

    private func snapshot(logged: Int, goal: Int = 2000) -> WaterTodaySnapshot {
        WaterTodaySnapshot(day: today, goalML: goal, loggedML: logged, entries: [], quietToday: false)
    }

    func testSpokenProgress() {
        XCTAssertEqual(GetWaterProgressIntent.spokenProgress(snapshot: snapshot(logged: 750), units: .metric),
                       "750 millilitres so far, 1.5 litres to go.")
        XCTAssertEqual(GetWaterProgressIntent.spokenProgress(snapshot: snapshot(logged: 2000), units: .metric),
                       "Goal met: 2 litres today.")
        XCTAssertEqual(GetWaterProgressIntent.spokenProgress(snapshot: snapshot(logged: 0), units: .metric),
                       "Nothing logged yet today. Your goal is 2 litres.")
        XCTAssertEqual(GetWaterProgressIntent.spokenProgress(snapshot: snapshot(logged: 1000), units: .imperial),
                       "34 ounces so far, 34 ounces to go.")
    }

    func testSpokenProgressWhenOffOrStale() {
        XCTAssertTrue(GetWaterProgressIntent.spokenProgress(snapshot: snapshot(logged: 500), enabled: false).contains("is off"))
        let stale = WaterTodaySnapshot(day: "2000-01-01", goalML: 2000, loggedML: 900, entries: [], quietToday: false)
        XCTAssertTrue(GetWaterProgressIntent.spokenProgress(snapshot: stale, units: .metric).hasPrefix("Nothing logged yet today."))
    }

    func testSnapshotDerivedValues() {
        let s = snapshot(logged: 1500)
        XCTAssertEqual(s.remainingML, 500)
        XCTAssertEqual(s.progress, 0.75, accuracy: 0.0001)
        XCTAssertFalse(s.isGoalMet)
        XCTAssertTrue(s.isToday())
        XCTAssertTrue(snapshot(logged: 2500).isGoalMet)
        XCTAssertEqual(snapshot(logged: 2500).remainingML, 0)
    }

    func testSnapshotRoundTripsThroughDefaults() {
        let suite = "WaterIntentsTests." + UUID().uuidString
        let defaults = UserDefaults(suiteName: suite)!
        defer { UserDefaults.standard.removePersistentDomain(forName: suite) }
        var s = snapshot(logged: 250)
        s.entries = [WaterEntry(ts: Date(timeIntervalSince1970: 1_800_000_000), ml: 250, source: .app, healthID: UUID())]
        s.snoozedUntil = Date(timeIntervalSince1970: 1_800_001_800)
        WaterSnapshotStore.save(s, to: defaults)
        let back = WaterSnapshotStore.load(from: defaults)
        XCTAssertEqual(back?.entries, s.entries)
        XCTAssertEqual(back?.snoozedUntil, s.snoozedUntil)
        XCTAssertEqual(back?.loggedML, 250)
    }
}
