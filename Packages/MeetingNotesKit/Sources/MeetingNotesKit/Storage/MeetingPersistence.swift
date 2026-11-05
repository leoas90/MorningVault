import Foundation
import SwiftData

/// Saves and reads meeting data in the SwiftData store.
@MainActor
public enum MeetingPersistence {
    /// Stores the transcript, notes and summary on the meeting.
    public static func update(
        meeting: Meeting,
        transcript: String? = nil,
        scratchpad: String? = nil,
        summary: MeetingSummary? = nil,
        context: ModelContext
    ) {
        if let transcript {
            meeting.transcript = transcript
        }
        if let scratchpad {
            meeting.scratchpad = scratchpad
        }
        if let summary {
            if let data = try? JSONEncoder().encode(summary) {
                meeting.summaryJSON = String(data: data, encoding: .utf8)
            }
        }
        try? context.save()
    }

    /// Reads the stored summary of a meeting.
    public static func summary(of meeting: Meeting) -> MeetingSummary? {
        guard let json = meeting.summaryJSON, let data = json.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(MeetingSummary.self, from: data)
    }

    /// Replaces the action items of a meeting with the ones from a summary.
    public static func replaceActionItems(
        of meeting: Meeting,
        with items: [ActionItem],
        context: ModelContext
    ) {
        let existing = fetchActionItems(for: meeting.id, context: context)
        for item in existing {
            context.delete(item)
        }
        for item in items {
            let record = ActionItemRecord(
                meetingID: meeting.id,
                text: item.text,
                owner: item.owner,
                due: parseDue(item.due),
                createdAt: meeting.startedAt
            )
            context.insert(record)
        }
        try? context.save()
    }

    /// Action items belonging to a meeting.
    public static func fetchActionItems(for meetingID: UUID, context: ModelContext) -> [ActionItemRecord] {
        let descriptor = FetchDescriptor<ActionItemRecord>(
            predicate: #Predicate { $0.meetingID == meetingID },
            sortBy: [SortDescriptor(\ActionItemRecord.createdAt)]
        )
        return (try? context.fetch(descriptor)) ?? []
    }

    /// Builds the Markdown document of a meeting.
    public static func markdown(for meeting: Meeting, context: ModelContext) -> String {
        let items = fetchActionItems(for: meeting.id, context: context)
        let document = MarkdownExporter.Document(
            title: meeting.displayTitle,
            date: meeting.startedAt,
            duration: meeting.duration,
            attendees: meeting.attendeeNames,
            summary: summary(of: meeting),
            scratchpad: meeting.scratchpad,
            transcript: meeting.transcript,
            actionItems: items.map { item in
                ActionItem(text: item.text, owner: item.owner, due: item.due.map { DueFormatter.string(from: $0) })
            }
        )
        return MarkdownExporter.markdown(for: document)
    }

    /// Writes the meeting to the shared app group. Failures are ignored on purpose.
    @discardableResult
    public static func writeToAppGroup(for meeting: Meeting, context: ModelContext) -> Bool {
        let document = MarkdownExporter.Document(
            title: meeting.displayTitle,
            date: meeting.startedAt,
            duration: meeting.duration,
            attendees: meeting.attendeeNames
        )
        let fileName = MarkdownExporter.fileName(for: document)
        return AppGroupMarkdownWriter.write(markdown(for: meeting, context: context), fileName: fileName)
    }

    /// Removes the recording files of a meeting.
    public static func deleteRecordings(for meeting: Meeting) {
        guard let fileName = meeting.audioFileName else { return }
        let url = MeetingNotesStore.audioFolder(for: meeting.id).appendingPathComponent(fileName)
        try? FileManager.default.removeItem(at: url)
    }

    private static func parseDue(_ value: String?) -> Date? {
        guard let value, !value.isEmpty else { return nil }
        return DueFormatter.date(from: value)
    }
}

/// Reads and writes the short due dates the model produces.
public enum DueFormatter {
    private static let formats = [
        "yyyy-MM-dd",
        "d MMM yyyy",
        "d MMMM yyyy",
        "MMM d, yyyy",
        "EEEE",
        "EEE"
    ]

    /// Turns a phrase such as "Friday" or "2026-11-08" into a date.
    public static func date(from value: String) -> Date? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        for format in formats {
            formatter.dateFormat = format
            if let date = formatter.date(from: trimmed) {
                return date
            }
        }

        formatter.dateFormat = "EEEE"
        if let weekday = formatter.date(from: trimmed) {
            let calendar = Calendar.current
            let components = calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: weekday)
            return calendar.date(from: components)
        }
        return nil
    }

    /// Renders a date the way the notes show it.
    public static func string(from date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale.current
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter.string(from: date)
    }
}
