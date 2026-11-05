import Foundation
import SwiftData
import XCTest
@testable import MeetingNotesKit

/// H2 / M3: enhancing again keeps what the user did to action items, and
/// exports skip what was already sent.
final class ActionItemPersistenceTests: XCTestCase {
    @MainActor
    private func makeMeeting() throws -> (ModelContainer, ModelContext, Meeting) {
        let container = try MeetingNotesStore.modelContainer(inMemory: true)
        let context = ModelContext(container)
        let meeting = Meeting(title: "Sync", startedAt: Date(timeIntervalSince1970: 1_760_000_000))
        context.insert(meeting)
        try context.save()
        return (container, context, meeting)
    }

    // MARK: Reconciler (pure)

    func testPlanMatchesByNormalizedTextAndDeletesTheRest() {
        let keep = UUID(), gone = UUID()
        let plan = ActionItemReconciler.plan(
            existing: [
                ActionItemReconciler.Row(id: keep, text: "Send the  notes."),
                ActionItemReconciler.Row(id: gone, text: "Book the room")
            ],
            incoming: [
                ActionItem(text: "send the notes", owner: "Ana", due: nil),
                ActionItem(text: "Call Ben", owner: nil, due: nil)
            ]
        )
        XCTAssertEqual(plan.matches, [keep, nil])
        XCTAssertEqual(plan.deletions, [gone])
    }

    func testPlanUsesEachRowOnce() {
        let only = UUID()
        let plan = ActionItemReconciler.plan(
            existing: [ActionItemReconciler.Row(id: only, text: "Ship it")],
            incoming: [ActionItem(text: "Ship it", owner: nil, due: nil), ActionItem(text: "Ship it", owner: nil, due: nil)]
        )
        XCTAssertEqual(plan.matches, [only, nil])
        XCTAssertTrue(plan.deletions.isEmpty)
    }

    func testNormalize() {
        XCTAssertEqual(ActionItemReconciler.normalize("  Send   the Notes!! "), "send the notes")
        XCTAssertEqual(ActionItemReconciler.normalize("Café"), "cafe")
    }

    // MARK: Store round trip

    @MainActor
    func testEnhanceAgainPreservesDoneAndExportedFlags() throws {
        let (_, context, meeting) = try makeMeeting()
        try MeetingPersistence.replaceActionItems(of: meeting, with: [
            ActionItem(text: "Send the notes", owner: "Ana", due: nil),
            ActionItem(text: "Book the room", owner: nil, due: nil),
            ActionItem(text: "Call Ben", owner: nil, due: nil)
        ], context: context)

        var items = MeetingPersistence.fetchActionItems(for: meeting.id, context: context)
        XCTAssertEqual(items.map(\.text), ["Send the notes", "Book the room", "Call Ben"])
        items[0].isDone = true
        items[2].exportedToReminders = true
        try context.save()
        let keptID = items[0].id

        // The model rewrote one line, dropped one and added one.
        try MeetingPersistence.replaceActionItems(of: meeting, with: [
            ActionItem(text: "Call Ben", owner: "Ana", due: nil),
            ActionItem(text: "send the notes.", owner: "Ana", due: "2026-11-08"),
            ActionItem(text: "Draft the plan", owner: nil, due: nil)
        ], context: context)

        items = MeetingPersistence.fetchActionItems(for: meeting.id, context: context)
        XCTAssertEqual(items.map(\.text), ["Call Ben", "send the notes.", "Draft the plan"], "list follows the new order")

        let sendNotes = try XCTUnwrap(items.first { $0.text == "send the notes." })
        XCTAssertEqual(sendNotes.id, keptID, "the row survived instead of being recreated")
        XCTAssertTrue(sendNotes.isDone, "the tick the user made survives")
        XCTAssertNotNil(sendNotes.due, "new payload is taken")

        let callBen = try XCTUnwrap(items.first { $0.text == "Call Ben" })
        XCTAssertTrue(callBen.exportedToReminders)
        XCTAssertEqual(callBen.owner, "Ana")

        let draft = try XCTUnwrap(items.first { $0.text == "Draft the plan" })
        XCTAssertFalse(draft.isDone)
        XCTAssertFalse(draft.exportedToReminders)
        XCTAssertNil(items.first { $0.text == "Book the room" }, "vanished item is deleted")
    }

    @MainActor
    func testExportSkipsDoneAndAlreadyExportedItems() throws {
        let (_, context, meeting) = try makeMeeting()
        try MeetingPersistence.replaceActionItems(of: meeting, with: [
            ActionItem(text: "One", owner: nil, due: nil),
            ActionItem(text: "Two", owner: nil, due: nil),
            ActionItem(text: "Three", owner: nil, due: nil)
        ], context: context)
        let items = MeetingPersistence.fetchActionItems(for: meeting.id, context: context)
        items[0].isDone = true
        items[1].exportedToReminders = true
        try context.save()

        let pending = MeetingPersistence.actionItemsToExport(from: items)
        XCTAssertEqual(pending.map(\.text), ["Three"])

        try MeetingPersistence.markExported(pending, context: context)
        let again = MeetingPersistence.actionItemsToExport(
            from: MeetingPersistence.fetchActionItems(for: meeting.id, context: context)
        )
        XCTAssertTrue(again.isEmpty, "a second export has nothing left to send")
    }
}
