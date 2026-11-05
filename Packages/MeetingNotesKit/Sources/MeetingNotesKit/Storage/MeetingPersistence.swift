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
        for (index, item) in items.enumerated() {
            let record = ActionItemRecord(
                meetingID: meeting.id,
                text: item.text,
                owner: item.owner,
                due: parseDue(item.due),
                // Offset by a second each so the list keeps the model's order.
                createdAt: meeting.startedAt.addingTimeInterval(Double(index))
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

    // MARK: - Transcript segments and speakers

    /// Replaces the timed transcript of a meeting.
    public static func replaceTranscriptPieces(
        of meeting: Meeting,
        with pieces: [TranscriptPiece],
        speakerKeys: [String?] = [],
        context: ModelContext
    ) {
        for segment in fetchTranscriptSegments(for: meeting.id, context: context) {
            context.delete(segment)
        }
        for (index, piece) in pieces.enumerated() {
            let record = TranscriptSegment(
                meetingID: meeting.id,
                index: index,
                text: piece.text,
                startTime: piece.start,
                endTime: piece.end,
                speakerKey: index < speakerKeys.count ? speakerKeys[index] : nil
            )
            context.insert(record)
        }
        try? context.save()
    }

    /// Timed transcript of a meeting, in order.
    public static func fetchTranscriptSegments(for meetingID: UUID, context: ModelContext) -> [TranscriptSegment] {
        let descriptor = FetchDescriptor<TranscriptSegment>(
            predicate: #Predicate { $0.meetingID == meetingID },
            sortBy: [SortDescriptor(\TranscriptSegment.index)]
        )
        return (try? context.fetch(descriptor)) ?? []
    }

    /// Stores who said what: the speaker of every segment and the speaker labels.
    public static func applySpeakers(
        _ identification: SpeakerIdentification,
        to meeting: Meeting,
        context: ModelContext
    ) {
        let segments = fetchTranscriptSegments(for: meeting.id, context: context)
        let pieces = segments.map { TranscriptPiece(text: $0.text, start: $0.startTime, end: $0.endTime) }
        let keys = SpeakerAssignment.assign(pieces: pieces, to: identification.turns)
        for (segment, key) in zip(segments, keys) {
            segment.speakerKey = key
        }
        meeting.speakerLabels = identification.labels
        try? context.save()
    }

    /// Renames a speaker. Renaming to "You" teaches the voice profile when the
    /// user allowed that, and takes the name away from any other "You".
    public static func renameSpeaker(key: String, to newName: String, in meeting: Meeting, context: ModelContext) {
        let name = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }
        var labels = meeting.speakerLabels
        guard let index = labels.firstIndex(where: { $0.key == key }) else { return }
        let becomesYou = name.caseInsensitiveCompare(SpeakerLabel.youName) == .orderedSame
        if becomesYou {
            var number = 1
            for other in labels.indices where other != index && labels[other].isYou {
                labels[other].name = "Speaker \(number)"
                number += 1
            }
            if !labels[index].isYou {
                VoiceProfileStore.learn(from: labels[index].centroid)
            }
        }
        labels[index].name = becomesYou ? SpeakerLabel.youName : name
        meeting.speakerLabels = labels
        try? context.save()
    }

    /// The transcript with speaker names, as `[Name] text` lines. Falls back to
    /// the plain transcript when speakers are not known.
    public static func labelledTranscript(for meeting: Meeting, context: ModelContext) -> String {
        let segments = fetchTranscriptSegments(for: meeting.id, context: context)
        guard !segments.isEmpty, segments.contains(where: { $0.speakerKey != nil }) else {
            return meeting.transcript
        }
        let pieces = segments.map { TranscriptPiece(text: $0.text, start: $0.startTime, end: $0.endTime) }
        let labels = meeting.speakerLabels
        return SpeakerAssignment.labelledTranscript(
            pieces: pieces,
            keys: segments.map(\.speakerKey),
            names: { key in labels.first { $0.key == key }?.name }
        )
    }

    /// The transcript the way exports show it: `**Name:** text` paragraphs
    /// when speakers are known, plain text otherwise.
    public static func exportTranscript(for meeting: Meeting, context: ModelContext) -> String {
        let segments = fetchTranscriptSegments(for: meeting.id, context: context)
        guard !segments.isEmpty, segments.contains(where: { $0.speakerKey != nil }) else {
            return meeting.transcript
        }
        let pieces = segments.map { TranscriptPiece(text: $0.text, start: $0.startTime, end: $0.endTime) }
        let labels = meeting.speakerLabels
        let turns = SpeakerAssignment.turns(
            from: pieces,
            keys: segments.map(\.speakerKey),
            names: { key in labels.first { $0.key == key }?.name }
        )
        return turns.map { "**\($0.name ?? "Unknown"):** \($0.text)" }.joined(separator: "\n\n")
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
            transcript: exportTranscript(for: meeting, context: context),
            actionItems: items.map { item in
                ActionItem(text: item.text, owner: item.owner, due: item.due.map { DueFormatter.string(from: $0) })
            }
        )
        return MarkdownExporter.markdown(for: document)
    }

    /// Writes the meeting (notes, summary, action items and the full transcript) as a
    /// Markdown file in the shared app group. Off unless the user turned on
    /// "Also save Markdown copies"; failures are ignored on purpose.
    @discardableResult
    public static func writeToAppGroup(for meeting: Meeting, context: ModelContext) -> Bool {
        guard MarkdownCopiesSetting.isEnabled else { return false }
        return AppGroupMarkdownWriter.write(markdown(for: meeting, context: context), fileName: appGroupFileName(for: meeting))
    }

    /// File name the app group copy of `meeting` uses (for `title`, when given).
    public static func appGroupFileName(for meeting: Meeting, title: String? = nil) -> String {
        let name = (title ?? meeting.title).trimmingCharacters(in: .whitespacesAndNewlines)
        let document = MarkdownExporter.Document(
            title: name.isEmpty ? "Untitled meeting" : name,
            date: meeting.startedAt,
            duration: meeting.duration,
            attendees: meeting.attendeeNames
        )
        return MarkdownExporter.fileName(for: document)
    }

    /// Removes the app group copy of a meeting, if there is one.
    public static func deleteAppGroupCopy(for meeting: Meeting) {
        AppGroupMarkdownWriter.delete(fileName: appGroupFileName(for: meeting))
    }

    /// Moves the app group copy to the file name of the meeting's new title. Call after
    /// `meeting.title` changed, passing the title it had before.
    public static func appGroupCopyRetitled(_ meeting: Meeting, from oldTitle: String) {
        let old = appGroupFileName(for: meeting, title: oldTitle)
        let new = appGroupFileName(for: meeting)
        guard old != new else { return }
        AppGroupMarkdownWriter.move(fileName: old, to: new)
    }

    /// Removes the recording files of a meeting.
    public static func deleteRecordings(for meeting: Meeting) {
        guard let fileName = meeting.audioFileName else { return }
        let url = MeetingNotesStore.audioFolder(for: meeting.id).appendingPathComponent(fileName)
        try? FileManager.default.removeItem(at: url)
    }

    /// Everything on disk and in the store that belongs to a meeting, then the meeting.
    public static func delete(_ meeting: Meeting, context: ModelContext) {
        deleteRecordings(for: meeting)
        deleteAppGroupCopy(for: meeting)
        for item in fetchActionItems(for: meeting.id, context: context) {
            context.delete(item)
        }
        for segment in fetchTranscriptSegments(for: meeting.id, context: context) {
            context.delete(segment)
        }
        context.delete(meeting)
    }

    private static func parseDue(_ value: String?) -> Date? {
        guard let value, !value.isEmpty else { return nil }
        return DueFormatter.date(from: value)
    }
}

/// The "Also save Markdown copies" switch: when on, every saved or enhanced meeting is
/// also written as Markdown (with its transcript) into the App Group folder. Off by
/// default; turning it off leaves existing copies alone.
public enum MarkdownCopiesSetting {
    public static let key = "meetings.saveMarkdownCopies"

    public static var isEnabled: Bool {
        get { UserDefaults.standard.bool(forKey: key) }
        set { UserDefaults.standard.set(newValue, forKey: key) }
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
