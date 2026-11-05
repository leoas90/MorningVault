import Foundation
import SwiftData

/// A small hook the morning brief can use to list what is still open.
public enum MeetingDigest {
    /// Action items that are still open and belong to a meeting that started
    /// at or after `since`, read from the app's shared store.
    ///
    /// - Parameter since: the oldest meeting to look at, usually the start of yesterday.
    /// - Throws: when the store cannot be opened or read, so the caller can say so.
    public static func openActionItems(since: Date) throws -> [String] {
        try openActionItems(since: since, in: MeetingNotesStore.sharedContainer())
    }

    /// Same as `openActionItems(since:)` but against a container you already have.
    public static func openActionItems(since: Date, in container: ModelContainer) throws -> [String] {
        let context = ModelContext(container)

        let meetings = try context.fetch(
            FetchDescriptor<Meeting>(predicate: #Predicate { $0.startedAt >= since })
        )
        guard !meetings.isEmpty else { return [] }
        let meetingIDs = Set(meetings.map(\.id))

        let open = try context.fetch(
            FetchDescriptor<ActionItemRecord>(
                predicate: #Predicate { $0.isDone == false },
                sortBy: [SortDescriptor(\ActionItemRecord.createdAt)]
            )
        )

        return open
            .filter { meetingIDs.contains($0.meetingID) }
            .map { item in
                if let owner = item.owner, !owner.isEmpty {
                    return "\(item.text) — \(owner)"
                }
                return item.text
            }
    }
}
