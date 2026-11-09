import XCTest
@testable import MorningVault

/// Settings > Data sources > Headlines off must leave the Brief without a headlines section.
@MainActor
final class HeadlinesToggleTests: XCTestCase {
    override func tearDown() {
        for key in ["headlines_enabled", "health_enabled", "calendar_enabled", "weather_enabled"] { UserDefaults.standard.removeObject(forKey: key) }
        super.tearDown()
    }

    func testHeadlinesOffRemovesSectionAfterReload() async {
        // Only the network source: permission prompts would hang the test host.
        for key in ["health_enabled", "calendar_enabled", "weather_enabled"] {
            UserDefaults.standard.set(false, forKey: key)
        }
        UserDefaults.standard.set(true, forKey: "headlines_enabled")
        let model = BriefingViewModel()
        await model.loadData(force: true)
        let before = model.briefingSections.map(\.id)
        print("HEADLINES_TEST before:", before)

        UserDefaults.standard.set(false, forKey: "headlines_enabled")
        await model.loadData(force: true)
        let after = model.briefingSections.map(\.id)
        print("HEADLINES_TEST after:", after)
        XCTAssertFalse(after.contains("headlines"))
    }
}
