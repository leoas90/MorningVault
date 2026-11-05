import Foundation
import SwiftData

/// Saves and reads meeting data in the SwiftData store.
///
/// Every write throws when the store refuses it, so the screen that asked can
/// say so instead of showing work that was never saved.
@MainActor
public enum MeetingPersistence {
    /// Stores the transcript, notes and summary on the meeting.
    public static func update(
        meeting: Meeting,
        transcript: String? = nil,
        scratchpad: String? = nil,
        summary: MeetingSummary? = nil,
        context: ModelContext
    ) throws {
        if let transcript {
            meeting.transcript = transcript
        }
        if let scratchpad {
            meeting.scratchpad = scratchpad
        }
        if let summary {
            let data = try JSONEncoder().encode(summary)
            meeting.summaryJSON = String(data: data, encoding: .utf8)
        }
        try context.save()
    }

    /// Reads the stored summary of a meeting.
    public static func summary(of meeting: Meeting) -> MeetingSummary? {
        guard let json = meeting.summaryJSON, let data = json.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(MeetingSummary.self, from: data)
    }

    // MARK: - Action items

    /// Brings the action items of a meeting in line with the ones from a summary
    /// without losing what the user did to them.
    ///
    /// Rows are matched to incoming items by their normalized text. A match keeps
    /// its `isDone` and `exportedToReminders` flags and takes the new owner and due
    /// date; items with no row are inserted; rows with no item are deleted.
    public static func replaceActionItems(
        of meeting: Meeting,
        with items: [ActionItem],
        context: ModelContext
    ) throws {
        let existing = fetchActionItems(for: meeting.id, context: context)
        let plan = ActionItemReconciler.plan(
            existing: existing.map { ActionItemReconciler.Row(id: $0.id, text: $0.text) },
            incoming: items
        )
        let byID = Dictionary(uniqueKeysWithValues: existing.map { ($0.id, $0) })

        for (index, item) in items.enumerated() {
            let createdAt = meeting.startedAt.addingTimeInterval(Double(index))
            if let rowID = plan.matches[index], let record = byID[rowID] {
                record.text = item.text
                record.owner = item.owner
                record.due = parseDue(item.due)
                record.createdAt = createdAt
            } else {
                context.insert(ActionItemRecord(
                    meetingID: meeting.id,
                    text: item.text,
                    owner: item.owner,
                    due: parseDue(item.due),
                    // Offset by a second each so the list keeps the model's order.
                    createdAt: createdAt
                ))
            }
        }
        for rowID in plan.deletions {
            if let record = byID[rowID] {
                context.delete(record)
            }
        }
        try context.save()
    }

    /// Action items belonging to a meeting.
    public static func fetchActionItems(for meetingID: UUID, context: ModelContext) -> [ActionItemRecord] {
        let descriptor = FetchDescriptor<ActionItemRecord>(
            predicate: #Predicate { $0.meetingID == meetingID },
            sortBy: [SortDescriptor(\ActionItemRecord.createdAt)]
        )
        return (try? context.fetch(descriptor)) ?? []
    }

    /// The action items that still have to go to Reminders: open ones that
    /// were not sent before.
    public static func actionItemsToExport(from items: [ActionItemRecord]) -> [ActionItemRecord] {
        items.filter { !$0.isDone && !$0.exportedToReminders }
    }

    /// Remembers that `items` went to Reminders, so a second tap does not send
    /// them again.
    public static func markExported(_ items: [ActionItemRecord], context: ModelContext) throws {
        for item in items {
            item.exportedToReminders = true
        }
        try context.save()
    }

    // MARK: - Transcript segments and speakers

    /// Replaces the timed transcript of a meeting.
    public static func replaceTranscriptPieces(
        of meeting: Meeting,
        with pieces: [TranscriptPiece],
        context: ModelContext
    ) throws {
        for segment in fetchTranscriptSegments(for: meeting.id, context: context) {
            context.delete(segment)
        }
        for (index, piece) in pieces.enumerated() {
            let record = TranscriptSegment(
                meetingID: meeting.id,
                index: index,
                text: piece.text,
                startTime: piece.start,
                endTime: piece.end
            )
            context.insert(record)
        }
        try context.save()
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
    ) throws {
        let segments = fetchTranscriptSegments(for: meeting.id, context: context)
        let pieces = segments.map { TranscriptPiece(text: $0.text, start: $0.startTime, end: $0.endTime) }
        let keys = SpeakerAssignment.assign(pieces: pieces, to: identification.turns)
        for (segment, key) in zip(segments, keys) {
            segment.speakerKey = key
        }
        meeting.speakerLabels = identification.labels
        try context.save()
    }

    /// Renames a speaker. Renaming to "You" teaches the voice profile when the
    /// user allowed that, and takes the name away from any other "You".
    public static func renameSpeaker(key: String, to newName: String, in meeting: Meeting, context: ModelContext) throws {
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
        try context.save()
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

    // MARK: - App group copies

    /// Writes the meeting (notes, summary, action items and the full transcript) as a
    /// Markdown file in the shared app group. Off unless the user turned on
    /// "Also save Markdown copies"; failures are ignored on purpose.
    @discardableResult
    public static func writeToAppGroup(for meeting: Meeting, context: ModelContext) -> Bool {
        guard MarkdownCopiesSetting.isEnabled else { return false }
        return AppGroupMarkdownWriter.write(markdown(for: meeting, context: context), fileName: appGroupFileName(for: meeting))
    }

    /// File name the app group copy of `meeting` uses (for `title`, when given).
    ///
    /// Carries the meeting id, so two meetings with the same title on one day
    /// get two files and a rename can find the old one.
    public static func appGroupFileName(for meeting: Meeting, title: String? = nil) -> String {
        let name = (title ?? meeting.title).trimmingCharacters(in: .whitespacesAndNewlines)
        let document = MarkdownExporter.Document(
            title: name.isEmpty ? "Untitled meeting" : name,
            date: meeting.startedAt,
            duration: meeting.duration,
            attendees: meeting.attendeeNames
        )
        return MarkdownExporter.fileName(for: document, id: meeting.id)
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

    // MARK: - Deleting

    /// Removes the recording folder of a meeting, whatever is in it.
    public static func deleteRecordings(for meeting: Meeting) {
        let folder = MeetingNotesStore.audioFolder(for: meeting.id)
        guard FileManager.default.fileExists(atPath: folder.path) else { return }
        try? FileManager.default.removeItem(at: folder)
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

/// Decides which stored action items an enhanced summary keeps, adds and drops.
/// Pure, so it can be tested without a store.
public enum ActionItemReconciler {
    /// One stored row, by id and text.
    public struct Row: Equatable, Sendable {
        public var id: UUID
        public var text: String

        public init(id: UUID, text: String) {
            self.id = id
            self.text = text
        }
    }

    /// The outcome: for every incoming item (by index) the row it updates, or
    /// `nil` when it is new; and the rows nothing matched.
    public struct Plan: Equatable, Sendable {
        public var matches: [UUID?]
        public var deletions: [UUID]
    }

    /// Matches `incoming` items to `existing` rows by normalized text. Each row
    /// is used at most once; duplicates in the summary become new rows.
    public static func plan(existing: [Row], incoming: [ActionItem]) -> Plan {
        var unused: [String: [UUID]] = [:]
        for row in existing {
            unused[normalize(row.text), default: []].append(row.id)
        }
        var matches: [UUID?] = []
        for item in incoming {
            let key = normalize(item.text)
            if var ids = unused[key], !ids.isEmpty {
                matches.append(ids.removeFirst())
                unused[key] = ids
            } else {
                matches.append(nil)
            }
        }
        let kept = Set(matches.compactMap { $0 })
        let deletions = existing.map(\.id).filter { !kept.contains($0) }
        return Plan(matches: matches, deletions: deletions)
    }

    /// Lower case, single spaces, no trailing punctuation.
    public static func normalize(_ text: String) -> String {
        let folded = text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
        let words = folded.split(whereSeparator: { $0.isWhitespace || $0.isNewline })
        var joined = words.joined(separator: " ")
        while let last = joined.last, last.isPunctuation {
            joined.removeLast()
        }
        return joined
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
        "MMMM d, yyyy"
    ]

    /// Turns a phrase such as "Friday" or "2026-11-08" into a date.
    ///
    /// A weekday name means the next such day after `now` (never today, so
    /// "Friday" said on a Friday is a week out). "Today" and "tomorrow" work too.
    public static func date(from value: String, now: Date = Date(), calendar: Calendar = .current) -> Date? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = calendar.timeZone
        formatter.calendar = calendar
        for format in formats {
            formatter.dateFormat = format
            if let date = formatter.date(from: trimmed) {
                return date
            }
        }

        return relativeDate(from: trimmed, now: now, calendar: calendar)
    }

    /// Renders a date the way the notes show it.
    public static func string(from date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale.current
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter.string(from: date)
    }

    /// "Friday", "next Monday", "today", "tomorrow" → a day at midnight after `now`.
    static func relativeDate(from phrase: String, now: Date, calendar: Calendar) -> Date? {
        var words = phrase.lowercased()
            .split(whereSeparator: { $0.isWhitespace })
            .map { $0.trimmingCharacters(in: .punctuationCharacters) }
            .filter { !$0.isEmpty }
        if words.first == "on" || words.first == "by" || words.first == "next" || words.first == "this" {
            words.removeFirst()
        }
        guard words.count == 1, let word = words.first else { return nil }

        let today = calendar.startOfDay(for: now)
        switch word {
        case "today":
            return today
        case "tomorrow":
            return calendar.date(byAdding: .day, value: 1, to: today)
        default:
            break
        }

        guard let weekday = weekdayNumber(for: word, calendar: calendar) else { return nil }
        return calendar.nextDate(
            after: today,
            matching: DateComponents(weekday: weekday),
            matchingPolicy: .nextTime,
            direction: .forward
        )
    }

    /// 1 (Sunday) … 7 (Saturday) for an English weekday name or abbreviation.
    private static func weekdayNumber(for word: String, calendar: Calendar) -> Int? {
        var english = Calendar(identifier: .gregorian)
        english.locale = Locale(identifier: "en_US_POSIX")
        let names = zip(english.weekdaySymbols, english.shortWeekdaySymbols)
        for (index, pair) in names.enumerated() {
            let (full, short) = pair
            if word == full.lowercased() || word == short.lowercased() {
                return index + 1
            }
        }
        return nil
    }
}
