import Foundation
import SwiftData

/// Builds the widget's `MeetingsSnapshot` from the store and the calendar and saves it
/// to the App Group. Everything here is a small read; nothing waits on the model or
/// the microphone.
@MainActor
enum MeetingsSnapshotPublisher {
    /// Full refresh: the next calendar event, the last meeting and the open items.
    /// Called when the home screen loads or pulls to refresh.
    static func publish(events: [CalendarEventInfo], now: Date = Date(), context: ModelContext) {
        MeetingsSnapshotStore.update { snapshot in
            snapshot.nextMeeting = nextMeeting(from: events, now: now)
            snapshot.isRecording = ActiveRecordingRegistry.shared.isRecording
            fillStoreFields(&snapshot, context: context)
        }
    }

    /// Partial refresh after a meeting was saved, enhanced, deleted or an action item was
    /// toggled. Keeps the calendar part of the last full refresh.
    static func publishStoreChanges(context: ModelContext) {
        MeetingsSnapshotStore.update { snapshot in
            fillStoreFields(&snapshot, context: context)
        }
    }

    /// Flags whether a recording is running.
    static func setRecording(_ isRecording: Bool) {
        MeetingsSnapshotStore.update { $0.isRecording = isRecording }
    }

    // MARK: - Pieces

    static func nextMeeting(from events: [CalendarEventInfo], now: Date) -> MeetingsSnapshot.NextMeeting? {
        guard let event = events
            .filter({ $0.end > now })
            .sorted(by: { $0.start < $1.start })
            .first
        else { return nil }
        return MeetingsSnapshot.NextMeeting(
            title: event.title.isEmpty ? "Untitled event" : event.title,
            start: event.start,
            end: event.end,
            calendarEventID: event.id,
            attendeeNames: event.attendeeNames
        )
    }

    private static func fillStoreFields(_ snapshot: inout MeetingsSnapshot, context: ModelContext) {
        var latest = FetchDescriptor<Meeting>(sortBy: [SortDescriptor(\Meeting.startedAt, order: .reverse)])
        latest.fetchLimit = 1
        let lastMeeting = (try? context.fetch(latest))?.first

        let open = (try? context.fetch(
            FetchDescriptor<ActionItemRecord>(
                predicate: #Predicate { $0.isDone == false },
                sortBy: [SortDescriptor(\ActionItemRecord.createdAt, order: .reverse)]
            )
        )) ?? []

        snapshot.openItemCount = open.count
        snapshot.openItems = open.prefix(MeetingsSnapshot.maxOpenItems).map {
            MeetingsSnapshot.OpenItem(text: $0.text, meetingID: $0.meetingID)
        }
        if let lastMeeting {
            snapshot.lastMeeting = MeetingsSnapshot.LastMeeting(
                id: lastMeeting.id,
                title: lastMeeting.displayTitle,
                date: lastMeeting.startedAt,
                openItemCount: open.filter { $0.meetingID == lastMeeting.id }.count
            )
        } else {
            snapshot.lastMeeting = nil
        }
    }
}
