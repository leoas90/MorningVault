import XCTest
@testable import MorningVault

/// "My cups": the model rules, how they are stored and migrated, and what reads the first cup.
final class WaterCupsTests: XCTestCase {
    private var suiteName = ""
    private var settings: UserDefaults!

    override func setUp() {
        super.setUp()
        suiteName = "WaterCupsTests." + UUID().uuidString
        settings = UserDefaults(suiteName: suiteName)
    }

    override func tearDown() {
        UserDefaults.standard.removePersistentDomain(forName: suiteName)
        settings = nil
        super.tearDown()
    }

    private var la: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "America/Los_Angeles")!
        c.locale = Locale(identifier: "en_US_POSIX")
        return c
    }

    /// Monday 2026-11-09 at the given hour.
    private func at(_ h: Int, _ m: Int = 0) -> Date {
        la.date(from: DateComponents(year: 2026, month: 11, day: 9, hour: h, minute: m))!
    }

    // MARK: Model rules

    func testSizeIsClampedAndNameIsTrimmed() {
        XCTAssertEqual(WaterCup(name: "Bucket", ml: 5000).ml, 2000, "clamped to the maximum")
        XCTAssertEqual(WaterCup(name: "Thimble", ml: 10).ml, 50, "clamped to the minimum")
        XCTAssertEqual(WaterCup(name: "  Travel mug  ", ml: 350).name, "Travel mug")
        let long = WaterCup(name: String(repeating: "a", count: 40), ml: 350)
        XCTAssertEqual(long.name.count, WaterCup.maxNameLength)
    }

    func testEmptyNameFallsBackToTheSize() {
        let cup = WaterCup(name: "   ", ml: 250)
        XCTAssertFalse(cup.name.isEmpty)
        XCTAssertEqual(cup.name, UnitsPreference.current.formatVolume(ml: 250))
    }

    func testDecodingClampsTheSize() throws {
        let json = Data(#"[{"id":"00000000-0000-0000-0000-000000000001","name":" Jug ","ml":9000}]"#.utf8)
        let cups = try JSONDecoder().decode([WaterCup].self, from: json)
        XCTAssertEqual(cups.count, 1)
        XCTAssertEqual(cups[0].ml, 2000)
        XCTAssertEqual(cups[0].name, "Jug")
    }

    func testAtMostFiveCupsAndNeverNone() {
        let six = (1...6).map { WaterCup(name: "Cup \($0)", ml: 100 * $0) }
        let capped = WaterTracker.normalizedCups(six)
        XCTAssertEqual(capped.count, WaterCup.maxCount)
        XCTAssertEqual(capped.map(\.name), ["Cup 1", "Cup 2", "Cup 3", "Cup 4", "Cup 5"], "order kept, extras dropped")
        XCTAssertEqual(WaterTracker.normalizedCups([]).map(\.ml), WaterTracker.defaultQuickAmounts, "empty falls back to the defaults")
        XCTAssertFalse(WaterTracker().cups.isEmpty)
    }

    func testPrimaryCupIsTheFirstOne() {
        let t = WaterTracker(cups: [WaterCup(name: "Travel mug", ml: 420), WaterCup(name: "Glass", ml: 250)])
        XCTAssertEqual(t.primaryCup.name, "Travel mug")
        XCTAssertEqual(t.glassML, 420)
        XCTAssertEqual(WaterTracker().glassML, WaterGlass.ml, "the default first cup is a 250 mL glass")
    }

    // MARK: Storage and migration

    func testCupsRoundTripThroughSettings() {
        let saved = WaterSettings.saveCups([WaterCup(name: "Glass", ml: 250),
                                            WaterCup(name: "Travel mug", ml: 420)], defaults: settings)
        XCTAssertEqual(saved.count, 2)
        let read = WaterSettings.cups(defaults: settings)
        XCTAssertEqual(read.map(\.name), ["Glass", "Travel mug"])
        XCTAssertEqual(read.map(\.ml), [250, 420])
        XCTAssertEqual(read.map(\.id), saved.map(\.id), "ids survive the round trip")
        XCTAssertEqual(WaterSettings.primaryCup(defaults: settings).name, "Glass")
        XCTAssertEqual(WaterSettings.tracker(defaults: settings).cups, read)
    }

    func testSavingMoreThanFiveCupsKeepsTheFirstFive() {
        let saved = WaterSettings.saveCups((1...7).map { WaterCup(name: "Cup \($0)", ml: 100 * $0) }, defaults: settings)
        XCTAssertEqual(saved.count, WaterCup.maxCount)
        XCTAssertEqual(WaterSettings.cups(defaults: settings).count, WaterCup.maxCount)
    }

    func testMigratesTheOldQuickAmounts() {
        settings.set(200, forKey: WaterSettings.Key.quick1)
        settings.set(400, forKey: WaterSettings.Key.quick2)
        let cups = WaterSettings.cups(defaults: settings)
        XCTAssertEqual(cups.map(\.ml), [200, 400, 500], "quick 3 keeps its default")
        XCTAssertEqual(cups.map(\.name), WaterTracker.defaultCupNames)
        XCTAssertEqual(WaterSettings.tracker(defaults: settings).glassML, 200)
    }

    func testDefaultCupsWhenNothingIsSaved() {
        let cups = WaterSettings.cups(defaults: settings)
        XCTAssertEqual(cups.map(\.ml), [250, 350, 500])
        XCTAssertEqual(cups.map(\.name), ["Glass", "Bottle", "Large bottle"])
    }

    func testSavedCupsWinOverTheOldQuickAmounts() {
        settings.set(200, forKey: WaterSettings.Key.quick1)
        WaterSettings.saveCups([WaterCup(name: "Only", ml: 600)], defaults: settings)
        XCTAssertEqual(WaterSettings.cups(defaults: settings).map(\.ml), [600])
    }

    // MARK: Units

    func testImperialCupConvertsToMillilitres() {
        let ml = UnitsPreference.imperial.ml(fromVolume: 24)
        XCTAssertEqual(ml, 710, "24 oz is about 710 mL")
        let cup = WaterCup(name: "Tumbler", ml: ml)
        XCTAssertEqual(cup.ml, 710)
        XCTAssertEqual(UnitsPreference.imperial.formatVolume(ml: cup.ml), "24 oz", "and back again")
    }

    // MARK: Tiers

    func testTiersFollowThePrimaryCupSize() {
        let big = [WaterCup(name: "Big bottle", ml: 500)]
        func tracker(logged: Int, cups: [WaterCup]) -> WaterTracker {
            WaterTracker(goalML: 2000,
                         entries: [WaterEntry(ts: at(8), ml: logged)],
                         windowStartMinutes: 7 * 60, windowEndMinutes: 21 * 60,
                         cups: cups)
        }
        // 14:00 expects 1,000 mL.
        XCTAssertEqual(tracker(logged: 500, cups: big).tier(at: at(14), calendar: la), .nudge,
                       "500 behind is one 500 mL cup: gentle")
        XCTAssertEqual(tracker(logged: 500, cups: [WaterCup(name: "Glass", ml: 250)]).tier(at: at(14), calendar: la), .reminder,
                       "the same deficit is two 250 mL glasses")
        XCTAssertEqual(tracker(logged: 400, cups: big).tier(at: at(14), calendar: la), .reminder, "600 behind is over one cup")
        // 18:00 expects 1,571 mL: 1,071 behind is more than two 500 mL cups.
        XCTAssertEqual(tracker(logged: 500, cups: big).tier(at: at(18), calendar: la), .behind)
    }

    // MARK: Intent

    func testIntentDefaultsToThePrimaryCup() {
        let cup = WaterCup(name: "Travel mug", ml: 420)
        XCTAssertEqual(LogWaterIntent.amount(ml: nil, cup: cup), 420, "no amount logs the first cup")
        XCTAssertEqual(LogWaterIntent.amount(ml: 300, cup: cup), 300, "an explicit amount still wins")
        XCTAssertEqual(LogWaterIntent.amount(ml: 9000, cup: cup), 2000, "clamped")
    }
}
