import Foundation
import SwiftData

/// Version 1 of the meetings schema: the models as shipped, including the
/// optional `speakerLabelsJSON` and `TranscriptSegment.speakerKey` fields.
///
/// The model classes live at the top level (not nested here) on purpose: their
/// entity names must stay `Meeting`, `TranscriptSegment` and `ActionItemRecord`
/// so stores written before this plan existed open unchanged. When the schema
/// changes next, add `MeetingNotesSchemaV2` with the new shapes, keep V1's
/// classes under a new name, and append a migration stage to the plan.
public enum MeetingNotesSchemaV1: VersionedSchema {
    public static let versionIdentifier = Schema.Version(1, 0, 0)

    public static var models: [any PersistentModel.Type] {
        [Meeting.self, TranscriptSegment.self, ActionItemRecord.self]
    }
}

/// How stores move from one schema version to the next. One version so far.
public enum MeetingNotesMigrationPlan: SchemaMigrationPlan {
    public static var schemas: [any VersionedSchema.Type] {
        [MeetingNotesSchemaV1.self]
    }

    public static var stages: [MigrationStage] {
        []
    }
}
