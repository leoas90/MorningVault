import Foundation

// Shared by the app (starts the activity through MeetingNotesKit), the widget extension
// (draws it) and MeetingNotesKit (symlinked). ActivityKit matches the activity to its
// view by this type's name, so the three copies must stay identical.

#if canImport(ActivityKit) && os(iOS)
import ActivityKit

/// The Live Activity shown while a meeting is being recorded.
struct RecordingActivityAttributes: ActivityAttributes, Sendable {
    /// What changes during a recording.
    struct ContentState: Codable, Hashable, Sendable {
        /// When the recording started, shifted forward by any time spent paused, so
        /// `Text(timerInterval:)` counting from here shows the recorded length.
        var startedAt: Date
        var isPaused: Bool
        /// When the pause began; the timer freezes at this instant.
        var pausedAt: Date?

        init(startedAt: Date, isPaused: Bool = false, pausedAt: Date? = nil) {
            self.startedAt = startedAt
            self.isPaused = isPaused
            self.pausedAt = pausedAt
        }

        /// The range the elapsed-time timer counts over. The upper bound only has to be
        /// later than any realistic meeting.
        var timerRange: ClosedRange<Date> {
            startedAt...startedAt.addingTimeInterval(12 * 60 * 60)
        }
    }

    /// Title of the meeting being recorded, or empty.
    var meetingTitle: String

    var displayTitle: String {
        let trimmed = meetingTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "Recording" : trimmed
    }
}
#endif
