import XCTest
@testable import MorningVault

final class RotatingBriefPagesTests: XCTestCase {
    private let allOn: Set<String> = Set(RotatingBriefInput.sectionIDs)

    private func fullInput(enabled: Set<String>? = nil) -> RotatingBriefInput {
        RotatingBriefInput(enabled: enabled ?? allOn, hasWeather: true, hasUpcomingEvent: true, marketCount: 2,
                           checklistTotal: 6, hasWaterSnapshot: true, headlineCount: 5)
    }

    // MARK: Page selection

    func testAllSectionsOnWithDataGivesEveryPageOnMedium() {
        XCTAssertEqual(RotatingBriefPages.select(fullInput(), medium: true),
                       [.weather, .next, .markets, .today, .water, .headlines])
    }

    func testHeadlinesIsMediumOnly() {
        XCTAssertEqual(RotatingBriefPages.select(fullInput(), medium: false),
                       [.weather, .next, .markets, .today, .water])
    }

    func testToggleOffDropsPageEvenWithData() {
        var enabled = allOn
        enabled.remove("water")
        enabled.remove("markets")
        XCTAssertEqual(RotatingBriefPages.select(fullInput(enabled: enabled), medium: true),
                       [.weather, .next, .today, .headlines])
    }

    func testNoDataDropsPageEvenWhenOn() {
        var input = fullInput()
        input.hasUpcomingEvent = false
        input.checklistTotal = 0
        input.hasWaterSnapshot = false
        input.headlineCount = 0
        XCTAssertEqual(RotatingBriefPages.select(input, medium: true), [.weather, .markets])
    }

    func testNothingQualifiesGivesNoPages() {
        XCTAssertEqual(RotatingBriefPages.select(RotatingBriefInput(), medium: true), [])
        XCTAssertEqual(RotatingBriefPages.select(fullInput(enabled: []), medium: true), [])
    }

    // MARK: Index math

    func testIndexWrapsWithOffset() {
        XCTAssertEqual(RotatingBriefPages.index(slot: 0, offset: 0, pageCount: 4), 0)
        XCTAssertEqual(RotatingBriefPages.index(slot: 3, offset: 0, pageCount: 4), 3)
        XCTAssertEqual(RotatingBriefPages.index(slot: 4, offset: 0, pageCount: 4), 0)
        XCTAssertEqual(RotatingBriefPages.index(slot: 2, offset: 3, pageCount: 4), 1)
        XCTAssertEqual(RotatingBriefPages.index(slot: 7, offset: 9, pageCount: 4), 0)
        XCTAssertEqual(RotatingBriefPages.index(slot: 0, offset: -1, pageCount: 4), 3, "negative offsets wrap too")
        XCTAssertEqual(RotatingBriefPages.index(slot: 5, offset: 2, pageCount: 0), 0, "no pages: always 0")
    }

    // MARK: Timeline

    func testSixHoursAtTwelveMinutesIsThirtySlots() {
        XCTAssertEqual(RotatingBriefPages.slotCount(), 30)
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        for pageCount in 1...6 {
            let pages = Array(RotatingBriefPages.pageOrder.prefix(pageCount))
            let slots = RotatingBriefPages.schedule(pages: pages, offset: 0, start: start)
            XCTAssertEqual(slots.count, 30, "\(pageCount) pages")
            XCTAssertEqual(slots.first?.date, start)
            XCTAssertEqual(slots.last?.date, start.addingTimeInterval(29 * 12 * 60))
            for (i, slot) in slots.enumerated() {
                XCTAssertEqual(slot.slot, i)
                XCTAssertEqual(slot.pageIndex, i % pageCount)
                XCTAssertEqual(slot.page, pages[i % pageCount])
            }
        }
    }

    func testScheduleHonorsOffset() {
        let start = Date()
        let pages: [RotatingBriefPage] = [.weather, .next, .water]
        let slots = RotatingBriefPages.schedule(pages: pages, offset: 2, start: start)
        XCTAssertEqual(slots[0].page, .water, "slot 0 shows page `offset`")
        XCTAssertEqual(slots[1].page, .weather)
        XCTAssertEqual(slots[2].page, .next)
    }

    func testZeroPagesFallsBackToSingleWeatherEntry() {
        let start = Date()
        let slots = RotatingBriefPages.schedule(pages: [], offset: 5, start: start)
        XCTAssertEqual(slots.count, 1)
        XCTAssertEqual(slots[0].page, .weather)
        XCTAssertEqual(slots[0].pageIndex, 0)
        XCTAssertEqual(slots[0].date, start)
    }

    // MARK: Offset store

    func testOffsetStoreRoundTripsAndClampsNegatives() {
        let suite = "RotatingBriefPagesTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        XCTAssertEqual(RotatingBriefOffsetStore.load(from: defaults), 0)
        RotatingBriefOffsetStore.save(4, to: defaults)
        XCTAssertEqual(RotatingBriefOffsetStore.load(from: defaults), 4)
        RotatingBriefOffsetStore.save(-3, to: defaults)
        XCTAssertEqual(RotatingBriefOffsetStore.load(from: defaults), 0)
    }

    func testDeepLinksUseExistingHosts() {
        XCTAssertEqual(RotatingBriefPage.water.deepLink?.host, "water")
        for page in RotatingBriefPage.allCases where page != .water {
            XCTAssertEqual(page.deepLink?.host, "briefing", page.rawValue)
        }
    }
}
