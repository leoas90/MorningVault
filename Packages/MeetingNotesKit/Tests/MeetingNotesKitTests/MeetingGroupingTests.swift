import Foundation
import XCTest
@testable import MeetingNotesKit

final class MeetingGroupingTests: XCTestCase {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Los_Angeles")!
        return calendar
    }

    /// Wednesday 4 Nov 2026, 15:00 local.
    private var now: Date {
        calendar.date(from: DateComponents(year: 2026, month: 11, day: 4, hour: 15))!
    }

    private func date(day: Int, hour: Int = 10, month: Int = 11) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: month, day: day, hour: hour))!
    }

    func testTodayCoversTheWholeDayAndTheFuture() {
        XCTAssertEqual(MeetingDayGroup.group(for: date(day: 4, hour: 0), now: now, calendar: calendar), .today)
        XCTAssertEqual(MeetingDayGroup.group(for: date(day: 4, hour: 23), now: now, calendar: calendar), .today)
        XCTAssertEqual(MeetingDayGroup.group(for: date(day: 9), now: now, calendar: calendar), .today)
    }

    func testYesterdayIsOnlyTheDayBefore() {
        XCTAssertEqual(MeetingDayGroup.group(for: date(day: 3, hour: 0), now: now, calendar: calendar), .yesterday)
        XCTAssertEqual(MeetingDayGroup.group(for: date(day: 3, hour: 23), now: now, calendar: calendar), .yesterday)
    }

    func testThisWeekIsTheFiveDaysBeforeYesterday() {
        XCTAssertEqual(MeetingDayGroup.group(for: date(day: 2), now: now, calendar: calendar), .thisWeek)
        XCTAssertEqual(MeetingDayGroup.group(for: date(day: 29, month: 10), now: now, calendar: calendar), .thisWeek)
        XCTAssertEqual(MeetingDayGroup.group(for: date(day: 28, month: 10), now: now, calendar: calendar), .earlier)
    }

    func testGroupedKeepsOrderAndDropsEmptyBuckets() {
        let items: [(String, Date)] = [
            ("a", date(day: 4, hour: 14)),
            ("b", date(day: 4, hour: 9)),
            ("c", date(day: 1)),
            ("d", date(day: 1, month: 10))
        ]
        let groups = MeetingDayGroup.grouped(items, date: { $0.1 }, now: now, calendar: calendar)
        XCTAssertEqual(groups.map(\.group), [.today, .thisWeek, .earlier])
        XCTAssertEqual(groups[0].items.map(\.0), ["a", "b"])
        XCTAssertEqual(groups[1].items.map(\.0), ["c"])
        XCTAssertEqual(groups[2].items.map(\.0), ["d"])
    }

    func testGroupsAreOrdered() {
        XCTAssertTrue(MeetingDayGroup.today < MeetingDayGroup.yesterday)
        XCTAssertTrue(MeetingDayGroup.thisWeek < MeetingDayGroup.earlier)
        XCTAssertEqual(MeetingDayGroup.allCases.map(\.title), ["Today", "Yesterday", "This week", "Earlier"])
    }

    func testSearchIsCaseInsensitiveAndIgnoresBlankQueries() {
        XCTAssertTrue(MeetingSearch.matches(query: "   ", fields: ["anything"]))
        XCTAssertTrue(MeetingSearch.matches(query: "BETA", fields: ["Ship the beta on Friday"]))
        XCTAssertFalse(MeetingSearch.matches(query: "alpha", fields: ["Ship the beta on Friday", ""]))
    }
}
