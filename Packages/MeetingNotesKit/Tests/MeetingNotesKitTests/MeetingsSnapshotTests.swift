import Foundation
import XCTest
@testable import MeetingNotesKit

final class MeetingsSnapshotTests: XCTestCase {
    private var defaults: UserDefaults!
    private let suite = "MeetingsSnapshotTests"

    override func setUp() {
        super.setUp()
        defaults = UserDefaults(suiteName: suite)
        defaults.removePersistentDomain(forName: suite)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suite)
        super.tearDown()
    }

    private func sample() -> MeetingsSnapshot {
        let meetingID = UUID()
        return MeetingsSnapshot(
            nextMeeting: .init(
                title: "Design review",
                start: Date(timeIntervalSince1970: 1_800_000_000),
                end: Date(timeIntervalSince1970: 1_800_003_600),
                calendarEventID: "ABC:123",
                attendeeNames: ["Ana", "Ben"]
            ),
            lastMeeting: .init(id: meetingID, title: "Weekly sync", date: Date(timeIntervalSince1970: 1_799_900_000), openItemCount: 2),
            openItemCount: 5,
            openItems: [
                .init(text: "Send the deck", meetingID: meetingID),
                .init(text: "Book the room", meetingID: meetingID),
                .init(text: "Reply to Ben", meetingID: meetingID),
                .init(text: "Fourth item is dropped", meetingID: meetingID)
            ],
            isRecording: true,
            updatedAt: Date(timeIntervalSince1970: 1_799_990_000)
        )
    }

    func testRoundTripsThroughJSON() throws {
        let original = sample()
        let data = try MeetingsSnapshot.encode(original)
        let decoded = try MeetingsSnapshot.decode(data)
        XCTAssertEqual(decoded, original)
        XCTAssertEqual(decoded.openItems.count, MeetingsSnapshot.maxOpenItems, "the init caps the list the widget shows")
        XCTAssertEqual(decoded.openItemCount, 5, "the count still reflects every open item")
    }

    func testJSONUsesStableKeysAndISODates() throws {
        let data = try MeetingsSnapshot.encode(sample())
        let json = try XCTUnwrap(String(data: data, encoding: .utf8))
        for key in ["\"version\":1", "\"nextMeeting\"", "\"lastMeeting\"", "\"openItemCount\":5", "\"openItems\"", "\"isRecording\":true", "\"calendarEventID\":\"ABC:123\""] {
            XCTAssertTrue(json.contains(key), "missing \(key) in \(json)")
        }
        XCTAssertTrue(json.contains("2027-01-15T08:00:00Z"), "dates are ISO 8601 so the widget and the app agree: \(json)")
    }

    func testStoreSavesLoadsAndUpdatesInPlace() {
        XCTAssertNil(MeetingsSnapshotStore.load(from: defaults))

        MeetingsSnapshotStore.save(sample(), to: defaults)
        let loaded = MeetingsSnapshotStore.load(from: defaults)
        XCTAssertEqual(loaded?.nextMeeting?.title, "Design review")
        XCTAssertEqual(loaded?.version, MeetingsSnapshot.currentVersion)

        MeetingsSnapshotStore.update(in: defaults) { $0.isRecording = false }
        let updated = MeetingsSnapshotStore.load(from: defaults)
        XCTAssertEqual(updated?.isRecording, false)
        XCTAssertEqual(updated?.nextMeeting?.calendarEventID, "ABC:123", "a partial update keeps the rest")

        MeetingsSnapshotStore.clear(in: defaults)
        XCTAssertNil(MeetingsSnapshotStore.load(from: defaults))
    }

    func testUpcomingMeetingHidesEndedEvents() {
        let snapshot = sample()
        let beforeEnd = Date(timeIntervalSince1970: 1_800_001_000)
        let afterEnd = Date(timeIntervalSince1970: 1_800_004_000)
        XCTAssertNotNil(snapshot.upcomingMeeting(at: beforeEnd))
        XCTAssertNil(snapshot.upcomingMeeting(at: afterEnd))
    }

    @MainActor
    func testNextMeetingPicksFirstEventStillRunning() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let events = [
            CalendarEventInfo(id: "later", title: "Later", start: now.addingTimeInterval(7200), end: now.addingTimeInterval(9000)),
            CalendarEventInfo(id: "done", title: "Done", start: now.addingTimeInterval(-7200), end: now.addingTimeInterval(-3600)),
            CalendarEventInfo(id: "now", title: "", start: now.addingTimeInterval(-600), end: now.addingTimeInterval(1800), attendeeNames: ["Cy"])
        ]
        let next = MeetingsSnapshotPublisher.nextMeeting(from: events, now: now)
        XCTAssertEqual(next?.calendarEventID, "now")
        XCTAssertEqual(next?.title, "Untitled event")
        XCTAssertEqual(next?.attendeeNames, ["Cy"])
        XCTAssertNil(MeetingsSnapshotPublisher.nextMeeting(from: [events[1]], now: now))
    }
}
