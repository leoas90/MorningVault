import Foundation
import SwiftData
import XCTest
@testable import MeetingNotesKit

/// The versioned schema opens stores written before the plan existed, and the
/// orphan sweep only removes what has no meeting row.
final class MeetingNotesStoreTests: XCTestCase {
    private func temporaryFolder() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("MeetingNotesStoreTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    @MainActor
    func testStoreWrittenWithoutMigrationPlanOpensWithIt() throws {
        let folder = try temporaryFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let url = folder.appendingPathComponent("MeetingNotes.store")
        let meetingID = UUID()

        // A store as the app wrote it before the VersionedSchema: same models, no plan.
        do {
            let legacySchema = Schema([Meeting.self, TranscriptSegment.self, ActionItemRecord.self])
            let container = try ModelContainer(
                for: legacySchema,
                configurations: [ModelConfiguration(schema: legacySchema, url: url)]
            )
            let context = ModelContext(container)
            let meeting = Meeting(id: meetingID, title: "Before the plan", speakerLabelsJSON: nil)
            context.insert(meeting)
            context.insert(ActionItemRecord(meetingID: meetingID, text: "Still here"))
            try context.save()
        }

        let container = try MeetingNotesStore.modelContainer(at: url)
        let context = ModelContext(container)
        let meetings = try context.fetch(FetchDescriptor<Meeting>())
        XCTAssertEqual(meetings.map(\.id), [meetingID])
        XCTAssertEqual(meetings.first?.title, "Before the plan")
        let items = try context.fetch(FetchDescriptor<ActionItemRecord>())
        XCTAssertEqual(items.map(\.text), ["Still here"])
    }

    func testSchemaVersionIsOne() {
        XCTAssertEqual(MeetingNotesSchemaV1.versionIdentifier, Schema.Version(1, 0, 0))
        XCTAssertEqual(MeetingNotesMigrationPlan.schemas.count, 1)
        XCTAssertTrue(MeetingNotesMigrationPlan.stages.isEmpty)
    }

    func testSweepRemovesOnlyOrphansAndEnrollmentClips() throws {
        let root = try temporaryFolder()
        defer { try? FileManager.default.removeItem(at: root) }
        let meetings = root.appendingPathComponent("Meetings", isDirectory: true)
        let enrollment = root.appendingPathComponent("Enrollment", isDirectory: true)
        let known = UUID(), active = UUID(), orphan = UUID()
        for id in [known, active, orphan] {
            let folder = meetings.appendingPathComponent(id.uuidString, isDirectory: true)
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            try Data([1, 2, 3]).write(to: folder.appendingPathComponent("recording.m4a"))
        }
        let stray = meetings.appendingPathComponent("not-a-uuid", isDirectory: true)
        try FileManager.default.createDirectory(at: stray, withIntermediateDirectories: true)
        let clip = enrollment.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: clip, withIntermediateDirectories: true)

        // grace 0: the folders were made a moment ago, and the grace window exists to
        // protect exactly that (see testSweepKeepsFoldersInsideTheGraceWindow).
        let removed = MeetingNotesStore.sweepOrphanedAudio(
            knownMeetingIDs: [known, active],
            meetingsFolder: meetings,
            enrollmentFolder: enrollment,
            grace: 0
        )

        XCTAssertEqual(Set(removed.map(\.lastPathComponent)), [orphan.uuidString, clip.lastPathComponent])
        XCTAssertTrue(FileManager.default.fileExists(atPath: meetings.appendingPathComponent(known.uuidString).path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: meetings.appendingPathComponent(active.uuidString).path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: meetings.appendingPathComponent(orphan.uuidString).path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: stray.path), "non-UUID folders are left alone")
        XCTAssertFalse(FileManager.default.fileExists(atPath: clip.path))
    }

    /// A recording that starts while the launch sweep is queued must survive it: the
    /// recorder stops the moment its folder goes away, which looked like a recording
    /// that started and stopped at once.
    func testSweepKeepsFoldersInsideTheGraceWindow() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("sweep-grace-\(UUID().uuidString)", isDirectory: true)
        let meetings = root.appendingPathComponent("Meetings", isDirectory: true)
        let enrollment = root.appendingPathComponent("Enrollment", isDirectory: true)
        try FileManager.default.createDirectory(at: enrollment, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let justStarted = UUID()
        let folder = meetings.appendingPathComponent(justStarted.uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try Data([1, 2, 3]).write(to: folder.appendingPathComponent("recording.m4a"))

        let clip = enrollment.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: clip, withIntermediateDirectories: true)

        let removed = MeetingNotesStore.sweepOrphanedAudio(
            knownMeetingIDs: [],
            meetingsFolder: meetings,
            enrollmentFolder: enrollment
        )

        XCTAssertTrue(removed.isEmpty, "nothing touched in the last ten minutes is swept")
        XCTAssertTrue(FileManager.default.fileExists(atPath: folder.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: clip.path))

        // Older than the window: swept as before.
        let old = MeetingNotesStore.sweepOrphanedAudio(
            knownMeetingIDs: [],
            meetingsFolder: meetings,
            enrollmentFolder: enrollment,
            now: Date().addingTimeInterval(3600)
        )
        XCTAssertEqual(old.count, 2)
        XCTAssertFalse(FileManager.default.fileExists(atPath: folder.path))
    }

    func testPathGettersDoNotCreateFolders() {
        let id = UUID()
        _ = MeetingNotesStore.audioFolder(for: id)
        _ = MeetingNotesStore.audioURL(for: id)
        _ = MeetingNotesStore.enrollmentAudioURL(for: id)
        XCTAssertFalse(FileManager.default.fileExists(atPath: MeetingNotesStore.audioFolder(for: id).path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: MeetingNotesStore.enrollmentFolder(for: id).path))
    }

    func testAppGroupFileNameCarriesTheMeetingID() {
        let id = UUID()
        let document = MarkdownExporter.Document(title: "Team Sync", date: Date(timeIntervalSince1970: 1_760_000_000), duration: 0)
        let name = MarkdownExporter.fileName(for: document, id: id)
        XCTAssertTrue(name.hasSuffix("-\(id.uuidString.lowercased()).md"), name)
        XCTAssertTrue(name.contains("team-sync"), name)
    }
}
