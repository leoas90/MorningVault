import Foundation
import SwiftData

/// A recorded meeting. Everything the app knows about one sitting of notes.
@Model
public final class Meeting {
    @Attribute(.unique) public var id: UUID = UUID()
    public var title: String = ""
    public var startedAt: Date = Date()
    public var endedAt: Date?
    public var duration: TimeInterval = 0
    /// The user's own rough notes, typed while recording.
    public var scratchpad: String = ""
    /// The flattened transcript text.
    public var transcript: String = ""
    /// JSON payload of the on-device generated summary.
    public var summaryJSON: String?
    /// File name of the `.m4a` recording inside the Meetings folder.
    public var audioFileName: String?
    /// Identifier of the linked calendar event, when one was attached.
    public var calendarEventID: String?
    public var attendeeNames: [String] = []
    public var createdAt: Date = Date()
    /// JSON array of `SpeakerLabel`: the speakers found by diarization, their
    /// names and voice centroids. `nil` until speakers were identified.
    public var speakerLabelsJSON: String?

    public init(
        id: UUID = UUID(),
        title: String = "",
        startedAt: Date = Date(),
        endedAt: Date? = nil,
        duration: TimeInterval = 0,
        scratchpad: String = "",
        transcript: String = "",
        summaryJSON: String? = nil,
        audioFileName: String? = nil,
        calendarEventID: String? = nil,
        attendeeNames: [String] = [],
        createdAt: Date = Date(),
        speakerLabelsJSON: String? = nil
    ) {
        self.speakerLabelsJSON = speakerLabelsJSON
        self.id = id
        self.title = title
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.duration = duration
        self.scratchpad = scratchpad
        self.transcript = transcript
        self.summaryJSON = summaryJSON
        self.audioFileName = audioFileName
        self.calendarEventID = calendarEventID
        self.attendeeNames = attendeeNames
        self.createdAt = createdAt
    }

    /// Short human label used in lists and exports.
    public var displayTitle: String {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty { return trimmed }
        return "Untitled meeting"
    }
}

/// One stretch of transcribed speech belonging to a meeting.
@Model
public final class TranscriptSegment {
    public var id: UUID = UUID()
    public var meetingID: UUID = UUID()
    public var index: Int = 0
    public var text: String = ""
    public var startTime: TimeInterval = 0
    public var endTime: TimeInterval = 0
    public var isFinal: Bool = true
    /// Key of the speaker (from `Meeting.speakerLabels`) who said this, when known.
    public var speakerKey: String?

    public init(
        id: UUID = UUID(),
        meetingID: UUID = UUID(),
        index: Int = 0,
        text: String = "",
        startTime: TimeInterval = 0,
        endTime: TimeInterval = 0,
        isFinal: Bool = true,
        speakerKey: String? = nil
    ) {
        self.speakerKey = speakerKey
        self.id = id
        self.meetingID = meetingID
        self.index = index
        self.text = text
        self.startTime = startTime
        self.endTime = endTime
        self.isFinal = isFinal
    }
}

/// A single "someone should do something" line pulled out of a meeting.
@Model
public final class ActionItemRecord {
    public var id: UUID = UUID()
    public var meetingID: UUID = UUID()
    public var text: String = ""
    public var owner: String?
    public var due: Date?
    public var isDone: Bool = false
    public var exportedToReminders: Bool = false
    public var createdAt: Date = Date()

    public init(
        id: UUID = UUID(),
        meetingID: UUID = UUID(),
        text: String = "",
        owner: String? = nil,
        due: Date? = nil,
        isDone: Bool = false,
        exportedToReminders: Bool = false,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.meetingID = meetingID
        self.text = text
        self.owner = owner
        self.due = due
        self.isDone = isDone
        self.exportedToReminders = exportedToReminders
        self.createdAt = createdAt
    }
}
