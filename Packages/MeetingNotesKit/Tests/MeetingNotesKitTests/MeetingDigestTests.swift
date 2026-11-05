import Foundation
import SwiftData
import XCTest
@testable import MeetingNotesKit

final class MeetingDigestTests: XCTestCase {
    @MainActor
    private func makeContainer() throws -> ModelContainer {
        try MeetingNotesStore.modelContainer(inMemory: true)
    }

    @MainActor
    private func seed(container: ModelContainer, meetingDate: Date, text: String, owner: String?, isDone: Bool) throws {
        let context = ModelContext(container)
        let meeting = Meeting(title: "Sync", startedAt: meetingDate)
        context.insert(meeting)
        try context.save()

        let item = ActionItemRecord(
            meetingID: meeting.id,
            text: text,
            owner: owner,
            isDone: isDone,
            createdAt: meetingDate
        )
        context.insert(item)
        try context.save()
    }

    @MainActor
    func testOnlyOpenItemsFromRecentMeetingsAreReturned() throws {
        let container = try makeContainer()
        let now = Date()
        let yesterday = now.addingTimeInterval(-86_400)
        let lastWeek = now.addingTimeInterval(-7 * 86_400)

        try seed(container: container, meetingDate: yesterday, text: "Send the notes", owner: "Ana", isDone: false)
        try seed(container: container, meetingDate: yesterday, text: "Finished task", owner: nil, isDone: true)
        try seed(container: container, meetingDate: lastWeek, text: "Ancient task", owner: nil, isDone: false)

        let open = try MeetingDigest.openActionItems(since: yesterday.addingTimeInterval(-60), in: container)

        XCTAssertEqual(open.count, 1)
        XCTAssertEqual(open.first, "Send the notes — Ana")
    }

    @MainActor
    func testNothingOlderThanTheCutoffIsReturned() throws {
        let container = try makeContainer()
        let now = Date()
        let lastWeek = now.addingTimeInterval(-7 * 86_400)
        try seed(container: container, meetingDate: lastWeek, text: "Ancient task", owner: nil, isDone: false)

        let open = try MeetingDigest.openActionItems(since: now.addingTimeInterval(-86_400), in: container)
        XCTAssertTrue(open.isEmpty)
    }

    @MainActor
    func testEmptyStoreReturnsNothing() throws {
        let container = try makeContainer()
        let open = try MeetingDigest.openActionItems(since: Date().addingTimeInterval(-86_400), in: container)
        XCTAssertTrue(open.isEmpty)
    }
}
