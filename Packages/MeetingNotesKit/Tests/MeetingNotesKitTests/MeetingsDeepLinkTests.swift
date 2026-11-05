import Foundation
import XCTest
@testable import MeetingNotesKit

final class MeetingsDeepLinkTests: XCTestCase {
    func testParsesMeetingsHome() throws {
        XCTAssertEqual(MeetingsDeepLink(url: try XCTUnwrap(URL(string: "morningvault://meetings"))), .meetings)
        XCTAssertEqual(MeetingsDeepLink(url: try XCTUnwrap(URL(string: "morningvault://meetings/"))), .meetings)
        XCTAssertEqual(MeetingsDeepLink(url: try XCTUnwrap(URL(string: "MorningVault://Meetings"))), .meetings)
    }

    func testParsesRecordWithAndWithoutEvent() throws {
        XCTAssertEqual(
            MeetingsDeepLink(url: try XCTUnwrap(URL(string: "morningvault://meetings/record"))),
            .record(calendarEventID: nil)
        )
        XCTAssertEqual(
            MeetingsDeepLink(url: try XCTUnwrap(URL(string: "morningvault://meetings/record?event="))),
            .record(calendarEventID: nil)
        )
        XCTAssertEqual(
            MeetingsDeepLink(url: try XCTUnwrap(URL(string: "morningvault://meetings/record?event=AB12%3A9F%3A7"))),
            .record(calendarEventID: "AB12:9F:7")
        )
    }

    func testParsesOpenAndRejectsBadIDs() throws {
        let id = UUID()
        XCTAssertEqual(
            MeetingsDeepLink(url: try XCTUnwrap(URL(string: "morningvault://meetings/open?id=\(id.uuidString)"))),
            .open(meetingID: id)
        )
        XCTAssertNil(MeetingsDeepLink(url: try XCTUnwrap(URL(string: "morningvault://meetings/open?id=nope"))))
        XCTAssertNil(MeetingsDeepLink(url: try XCTUnwrap(URL(string: "morningvault://meetings/open"))))
    }

    func testRejectsOtherLinks() throws {
        XCTAssertNil(MeetingsDeepLink(url: try XCTUnwrap(URL(string: "morningvault://briefing"))))
        XCTAssertNil(MeetingsDeepLink(url: try XCTUnwrap(URL(string: "https://meetings/record"))))
        XCTAssertNil(MeetingsDeepLink(url: try XCTUnwrap(URL(string: "morningvault://meetings/unknown"))))
    }

    func testBuildsURLsThatParseBack() throws {
        let cases: [MeetingsDeepLink] = [
            .meetings,
            .record(calendarEventID: nil),
            .record(calendarEventID: "0F9A:1C2D-ABC def&x=1"),
            .open(meetingID: UUID())
        ]
        for link in cases {
            XCTAssertEqual(MeetingsDeepLink(url: link.url), link, "\(link.url)")
            XCTAssertEqual(link.url.scheme, "morningvault")
            XCTAssertEqual(link.url.host(), "meetings")
        }
        XCTAssertEqual(MeetingsDeepLink.meetings.url.absoluteString, "morningvault://meetings")
        XCTAssertEqual(MeetingsDeepLink.record(calendarEventID: nil).url.absoluteString, "morningvault://meetings/record")
    }

    @MainActor
    func testRouterTurnsLinksIntoRoutes() throws {
        let router = MeetingsRouter.shared
        XCTAssertFalse(router.handle(url: try XCTUnwrap(URL(string: "morningvault://briefing"))))
        XCTAssertNil(router.pending)

        XCTAssertTrue(router.handle(url: try XCTUnwrap(URL(string: "morningvault://meetings/record?event=E1"))))
        XCTAssertEqual(router.pending, .record(calendarEventID: "E1", title: "", attendees: []))

        let id = UUID()
        XCTAssertTrue(router.handle(url: try XCTUnwrap(URL(string: "morningvault://meetings/open?id=\(id.uuidString)"))))
        XCTAssertEqual(router.pending, .open(meetingID: id))

        router.clear(.home)
        XCTAssertEqual(router.pending, .open(meetingID: id), "clearing a different route leaves the newer one queued")
        router.clear(.open(meetingID: id))
        XCTAssertNil(router.pending)
    }
}
