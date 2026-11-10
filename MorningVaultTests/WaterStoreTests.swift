import XCTest
@testable import MorningVault

/// A Health store in memory: records writes, serves samples, can be switched off.
actor FakeWaterHealth: WaterHealthClient {
    nonisolated let isAvailable: Bool
    var authorized: Bool
    var samples: [WaterHealthSample] = []
    var saveCalls = 0
    var deleteCalls = 0
    var authorizationRequests = 0

    init(available: Bool = true, authorized: Bool = true) {
        self.isAvailable = available
        self.authorized = authorized
    }

    func requestShareAuthorization() async -> Bool {
        authorizationRequests += 1
        authorized = true
        return true
    }

    func canWrite() async -> Bool { authorized }

    func save(ml: Int, date: Date) async throws -> UUID {
        saveCalls += 1
        let sample = WaterHealthSample(id: UUID(), ts: date, ml: ml)
        samples.append(sample)
        return sample.id
    }

    func delete(healthID: UUID) async throws {
        deleteCalls += 1
        samples.removeAll { $0.id == healthID }
    }

    func samples(on day: Date) async -> [WaterHealthSample]? {
        authorized ? samples : nil
    }

    func addForeign(ml: Int, at date: Date) {
        samples.append(WaterHealthSample(id: UUID(), ts: date, ml: ml))
    }
}

final class WaterStoreTests: XCTestCase {
    private var la: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "America/Los_Angeles")!
        return c
    }

    private func at(_ h: Int, _ m: Int = 0, day: Int = 9) -> Date {
        la.date(from: DateComponents(year: 2026, month: 11, day: day, hour: h, minute: m))!
    }

    private var settingsSuite = ""
    private var mirrorSuite = ""
    private var settings: UserDefaults { UserDefaults(suiteName: settingsSuite)! }
    private var mirror: UserDefaults { UserDefaults(suiteName: mirrorSuite)! }

    override func setUp() {
        super.setUp()
        let suite = "WaterStoreTests." + UUID().uuidString
        settingsSuite = suite + ".settings"
        mirrorSuite = suite + ".mirror"
        settings.set(2000, forKey: WaterSettings.Key.goalML)
    }

    override func tearDown() {
        UserDefaults.standard.removePersistentDomain(forName: settingsSuite)
        UserDefaults.standard.removePersistentDomain(forName: mirrorSuite)
        super.tearDown()
    }

    private func makeStore(health: WaterHealthClient?, now: Date) -> WaterStore {
        WaterStore(health: health, settingsSuite: settingsSuite, snapshotSuite: mirrorSuite, calendar: la, reloadsWidget: false, now: now)
    }

    // MARK: Logging

    func testLogWritesToHealthAndMirror() async {
        let health = FakeWaterHealth()
        let store = makeStore(health: health, now: at(9))
        let entry = await store.log(ml: 250, at: at(9))
        XCTAssertNotNil(entry.healthID)
        XCTAssertEqual(entry.source, .app)
        let saves = await health.saveCalls
        XCTAssertEqual(saves, 1)
        let snapshot = WaterSnapshotStore.load(from: mirror)
        XCTAssertEqual(snapshot?.loggedML, 250)
        XCTAssertEqual(snapshot?.goalML, 2000)
        XCTAssertEqual(snapshot?.day, "2026-11-09")
        XCTAssertEqual(snapshot?.entries.count, 1)
    }

    func testHealthUnavailableKeepsLocalMirror() async {
        let store = makeStore(health: FakeWaterHealth(available: false), now: at(9))
        let entry = await store.log(ml: 350, at: at(9))
        XCTAssertNil(entry.healthID, "no Health: local only")
        let tracker = await store.load(now: at(10))
        XCTAssertEqual(tracker.logged(at: at(10), calendar: la), 350, "load keeps local entries when Health is unavailable")
    }

    func testNoHealthClientAtAll() async {
        let store = makeStore(health: nil, now: at(9))
        await store.log(ml: 500, at: at(9))
        let tracker = await store.load(now: at(10))
        XCTAssertEqual(tracker.logged(at: at(10), calendar: la), 500)
    }

    func testNotAuthorizedLogsLocallyThenSyncsWhenAllowed() async {
        let health = FakeWaterHealth(authorized: false)
        let store = makeStore(health: health, now: at(9))
        let entry = await store.log(ml: 250, at: at(9))
        XCTAssertNil(entry.healthID)
        // The user allows writing later: the pending entry is pushed on the next load.
        _ = await store.requestHealthShare()
        let tracker = await store.load(now: at(10))
        let saves = await health.saveCalls
        XCTAssertEqual(saves, 1)
        XCTAssertEqual(tracker.entries.count, 1)
        XCTAssertNotNil(tracker.entries.first?.healthID)
    }

    // MARK: Merge

    func testLoadMergesForeignHealthSamples() async {
        let health = FakeWaterHealth()
        await health.addForeign(ml: 300, at: at(8))
        let store = makeStore(health: health, now: at(9))
        await store.log(ml: 250, at: at(9))
        let tracker = await store.load(now: at(10))
        XCTAssertEqual(tracker.entries.count, 2)
        XCTAssertEqual(tracker.logged(at: at(10), calendar: la), 550)
        XCTAssertEqual(tracker.entries.map(\.source), [.health, .app], "sorted by time, Watch sample first")
        // A second load does not duplicate.
        let again = await store.load(now: at(11))
        XCTAssertEqual(again.entries.count, 2)
    }

    func testEntryDeletedInHealthLeavesTheMirror() async {
        let health = FakeWaterHealth()
        let store = makeStore(health: health, now: at(9))
        let entry = await store.log(ml: 250, at: at(9))
        try? await health.delete(healthID: entry.healthID!)
        let tracker = await store.load(now: at(10))
        XCTAssertTrue(tracker.entries.isEmpty, "Health is the store of truth")
    }

    // MARK: Undo

    func testUndoLastRemovesAppEntryAndHealthSample() async {
        let health = FakeWaterHealth()
        await health.addForeign(ml: 300, at: at(8))
        let store = makeStore(health: health, now: at(9))
        await store.load(now: at(9))
        await store.log(ml: 250, at: at(9))
        await store.log(ml: 500, at: at(9, 30))
        let undone = await store.undoLast(now: at(10))
        XCTAssertEqual(undone?.ml, 500)
        let deletes = await health.deleteCalls
        XCTAssertEqual(deletes, 1)
        let tracker = await store.tracker(now: at(10))
        XCTAssertEqual(tracker.logged(at: at(10), calendar: la), 550)
        // Undo never touches a Watch entry.
        _ = await store.undoLast(now: at(10))
        let nothing = await store.undoLast(now: at(10))
        XCTAssertNil(nothing)
        let left = await store.tracker(now: at(10))
        XCTAssertEqual(left.entries.map(\.source), [.health])
    }

    // MARK: Day roll and flags

    func testNewDayStartsEmpty() async {
        let store = makeStore(health: nil, now: at(9))
        await store.log(ml: 500, at: at(9))
        await store.setQuietToday(true, now: at(9))
        let tomorrow = await store.current(now: at(8, day: 10))
        XCTAssertEqual(tomorrow.day, "2026-11-10")
        XCTAssertEqual(tomorrow.loggedML, 0)
        XCTAssertFalse(tomorrow.quietToday)
    }

    func testSnapshotSurvivesRestartSameDay() async {
        let store = makeStore(health: nil, now: at(9))
        await store.log(ml: 500, at: at(9))
        let reopened = makeStore(health: nil, now: at(12))
        let snapshot = await reopened.current(now: at(12))
        XCTAssertEqual(snapshot.loggedML, 500)
    }

    func testSnoozeAndQuiet() async {
        let store = makeStore(health: nil, now: at(9))
        await store.snooze(minutes: 30, now: at(9))
        let snapshot = await store.current(now: at(9))
        XCTAssertEqual(snapshot.snoozedUntil, at(9, 30))
        await store.setQuietToday(true, now: at(9))
        let tracker = await store.tracker(now: at(9))
        XCTAssertTrue(tracker.quietToday)
    }

    func testSettingsDriveTheTracker() async {
        settings.set(2500, forKey: WaterSettings.Key.goalML)
        settings.set(8 * 60, forKey: WaterSettings.Key.windowStart)
        settings.set(22 * 60, forKey: WaterSettings.Key.windowEnd)
        WaterSettings.saveCups([WaterCup(name: "Small glass", ml: 200), WaterCup(name: "Bottle", ml: 500)], defaults: settings)
        let store = makeStore(health: nil, now: at(9))
        let tracker = await store.tracker(now: at(9))
        XCTAssertEqual(tracker.goalML, 2500)
        XCTAssertEqual(tracker.windowStartMinutes, 8 * 60)
        XCTAssertEqual(tracker.windowEndMinutes, 22 * 60)
        XCTAssertEqual(tracker.cups.map(\.name), ["Small glass", "Bottle"])
        XCTAssertEqual(tracker.cups.map(\.ml), [200, 500])
        XCTAssertEqual(tracker.primaryCup.ml, 200)
    }

    func testWindowStartDefaultsToAlarmTime() {
        settings.set(6.5 * 3600, forKey: WaterSettings.Key.briefingTime)
        XCTAssertEqual(WaterSettings.tracker(defaults: settings).windowStartMinutes, 390)
        settings.removeObject(forKey: WaterSettings.Key.briefingTime)
        XCTAssertEqual(WaterSettings.tracker(defaults: settings).windowStartMinutes, 7 * 60)
    }

    func testPicksUpWidgetWritesFromTheMirror() async {
        let app = makeStore(health: nil, now: at(9))
        await app.log(ml: 250, at: at(9))
        // The widget process has its own store over the same mirror.
        let widget = makeStore(health: nil, now: at(9, 30))
        await widget.log(ml: 250, at: at(9, 30))
        let tracker = await app.tracker(now: at(10))
        XCTAssertEqual(tracker.entries.count, 2, "the app sees the widget's entry")
        XCTAssertEqual(tracker.logged(at: at(10), calendar: la), 500)
        // And a later app write does not drop it.
        await app.log(ml: 100, at: at(10, 5))
        XCTAssertEqual(WaterSnapshotStore.load(from: mirror)?.loggedML, 600)
    }
}
