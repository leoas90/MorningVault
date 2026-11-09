import XCTest
@testable import MorningVault

final class TodaySectionPrefsTests: XCTestCase {
    private let keys = [BriefSectionPrefs.householdEnabledKey, BriefSectionPrefs.Key.today]

    override func setUp() {
        super.setUp()
        for key in keys {
            UserDefaults.standard.removeObject(forKey: key)
            UserDefaults(suiteName: BriefSectionPrefs.appGroup)?.removeObject(forKey: key)
        }
    }

    override func tearDown() {
        for key in keys {
            UserDefaults.standard.removeObject(forKey: key)
            UserDefaults(suiteName: BriefSectionPrefs.appGroup)?.removeObject(forKey: key)
        }
        super.tearDown()
    }

    func testTodayNeedsHouseholdTracker() {
        XCTAssertFalse(BriefSectionPrefs.isEnabled("today"), "off by default")
        UserDefaults.standard.set(true, forKey: BriefSectionPrefs.householdEnabledKey)
        XCTAssertTrue(BriefSectionPrefs.isEnabled("today"))
        UserDefaults.standard.set(false, forKey: BriefSectionPrefs.Key.today)
        XCTAssertFalse(BriefSectionPrefs.isEnabled("today"), "section toggle wins")
    }

    func testTodaySitsBetweenCalendarAndMarkets() {
        for template in BriefingTemplate.allCases where template != .custom {
            let calendar = template.sectionPriority(for: "calendar")
            let today = template.sectionPriority(for: "today")
            XCTAssertEqual(today, calendar + 1, "\(template.rawValue)")
            if template != .traderFocus, template != .newsFirst {
                XCTAssertLessThan(today, template.sectionPriority(for: "markets"), "\(template.rawValue)")
            }
        }
    }
}
