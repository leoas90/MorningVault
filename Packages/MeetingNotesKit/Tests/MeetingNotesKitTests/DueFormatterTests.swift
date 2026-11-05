import Foundation
import XCTest
@testable import MeetingNotesKit

/// M1: weekday names resolve to the next such day after today, never to the year 2000.
final class DueFormatterTests: XCTestCase {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Los_Angeles")!
        calendar.locale = Locale(identifier: "en_US_POSIX")
        return calendar
    }

    /// Wednesday 2026-11-04, 10:30 local.
    private var wednesday: Date {
        calendar.date(from: DateComponents(year: 2026, month: 11, day: 4, hour: 10, minute: 30))!
    }

    private func ymd(_ date: Date?) -> String? {
        guard let date else { return nil }
        let components = calendar.dateComponents([.year, .month, .day, .weekday, .hour], from: date)
        return "\(components.year!)-\(components.month!)-\(components.day!) wd\(components.weekday!) h\(components.hour!)"
    }

    func testFridayIsTheComingFriday() {
        XCTAssertEqual(ymd(DueFormatter.date(from: "Friday", now: wednesday, calendar: calendar)), "2026-11-6 wd6 h0")
        XCTAssertEqual(ymd(DueFormatter.date(from: "fri", now: wednesday, calendar: calendar)), "2026-11-6 wd6 h0")
        XCTAssertEqual(ymd(DueFormatter.date(from: "by Friday", now: wednesday, calendar: calendar)), "2026-11-6 wd6 h0")
    }

    func testMondayIsNextWeek() {
        XCTAssertEqual(ymd(DueFormatter.date(from: "Monday", now: wednesday, calendar: calendar)), "2026-11-9 wd2 h0")
        XCTAssertEqual(ymd(DueFormatter.date(from: "next Monday", now: wednesday, calendar: calendar)), "2026-11-9 wd2 h0")
    }

    func testSameWeekdayMeansAWeekOut() {
        XCTAssertEqual(ymd(DueFormatter.date(from: "Wednesday", now: wednesday, calendar: calendar)), "2026-11-11 wd4 h0")
    }

    func testTodayAndTomorrow() {
        XCTAssertEqual(ymd(DueFormatter.date(from: "today", now: wednesday, calendar: calendar)), "2026-11-4 wd4 h0")
        XCTAssertEqual(ymd(DueFormatter.date(from: "Tomorrow", now: wednesday, calendar: calendar)), "2026-11-5 wd5 h0")
    }

    func testAbsoluteDatesStillParse() {
        XCTAssertEqual(ymd(DueFormatter.date(from: "2026-11-08", now: wednesday, calendar: calendar)), "2026-11-8 wd1 h0")
        XCTAssertEqual(ymd(DueFormatter.date(from: "8 Nov 2026", now: wednesday, calendar: calendar)), "2026-11-8 wd1 h0")
        XCTAssertEqual(ymd(DueFormatter.date(from: "Nov 8, 2026", now: wednesday, calendar: calendar)), "2026-11-8 wd1 h0")
    }

    func testNonsenseIsNil() {
        XCTAssertNil(DueFormatter.date(from: "soon", now: wednesday, calendar: calendar))
        XCTAssertNil(DueFormatter.date(from: "", now: wednesday, calendar: calendar))
        XCTAssertNil(DueFormatter.date(from: "Friday afternoon", now: wednesday, calendar: calendar))
    }

    func testNeverTheYear2000() {
        for phrase in ["Friday", "Monday", "Sat", "Sunday"] {
            let date = DueFormatter.date(from: phrase, now: wednesday, calendar: calendar)
            XCTAssertNotNil(date, phrase)
            XCTAssertGreaterThan(date!, wednesday, phrase)
        }
    }
}
