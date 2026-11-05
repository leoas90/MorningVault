import Foundation

/// Turns a meeting into a Markdown file that can be shared or filed away.
public enum MarkdownExporter {
    /// Everything that ends up in the exported document.
    public struct Document: Sendable {
        public var title: String
        public var date: Date
        public var duration: TimeInterval
        public var attendees: [String]
        public var summary: MeetingSummary?
        public var scratchpad: String
        public var transcript: String
        public var actionItems: [ActionItem]
        public var location: String?

        public init(
            title: String,
            date: Date,
            duration: TimeInterval,
            attendees: [String] = [],
            summary: MeetingSummary? = nil,
            scratchpad: String = "",
            transcript: String = "",
            actionItems: [ActionItem] = [],
            location: String? = nil
        ) {
            self.title = title
            self.date = date
            self.duration = duration
            self.attendees = attendees
            self.summary = summary
            self.scratchpad = scratchpad
            self.transcript = transcript
            self.actionItems = actionItems
            self.location = location
        }
    }

    /// Builds the Markdown body of a meeting.
    public static func markdown(for document: Document) -> String {
        var lines: [String] = []
        let title = document.title.trimmingCharacters(in: .whitespacesAndNewlines)
        lines.append("# " + (title.isEmpty ? "Meeting" : title))
        lines.append("")

        var facts: [String] = []
        facts.append("**Date:** \(longDate(document.date))")
        facts.append("**Length:** \(durationText(document.duration))")
        if !document.attendees.isEmpty {
            facts.append("**Attendees:** \(document.attendees.joined(separator: ", "))")
        }
        if let location = document.location, !location.isEmpty {
            facts.append("**Location:** \(location)")
        }
        lines.append(contentsOf: facts)
        lines.append("")

        if let summary = document.summary {
            let actionItems = document.actionItems.isEmpty ? summary.actionItems : document.actionItems

            lines.append("## Summary")
            lines.append("")
            lines.append(summary.summary)
            lines.append("")

            if !summary.keyPoints.isEmpty {
                lines.append("## Key points")
                lines.append("")
                lines.append(contentsOf: summary.keyPoints.map { "- \($0)" })
                lines.append("")
            }

            if !summary.decisions.isEmpty {
                lines.append("## Decisions")
                lines.append("")
                lines.append(contentsOf: summary.decisions.map { "- \($0)" })
                lines.append("")
            }

            if !actionItems.isEmpty {
                lines.append("## Action items")
                lines.append("")
                lines.append(contentsOf: actionItems.map { item in
                    var line = "- [ ] \(item.text)"
                    var qualifiers: [String] = []
                    if let owner = item.owner, !owner.isEmpty { qualifiers.append("owner: \(owner)") }
                    if let due = item.due, !due.isEmpty { qualifiers.append("due: \(due)") }
                    if !qualifiers.isEmpty {
                        line += " (" + qualifiers.joined(separator: ", ") + ")"
                    }
                    return line
                })
                lines.append("")
            }

            if !summary.followUpQuestions.isEmpty {
                lines.append("## Open questions")
                lines.append("")
                lines.append(contentsOf: summary.followUpQuestions.map { "- \($0)" })
                lines.append("")
            }
        } else if !document.actionItems.isEmpty {
            lines.append("## Action items")
            lines.append("")
            lines.append(contentsOf: document.actionItems.map { "- [ ] \($0.text)" })
            lines.append("")
        }

        let notes = document.scratchpad.trimmingCharacters(in: .whitespacesAndNewlines)
        if !notes.isEmpty {
            lines.append("## My notes")
            lines.append("")
            lines.append(notes)
            lines.append("")
        }

        let transcript = document.transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        if !transcript.isEmpty {
            lines.append("## Transcript")
            lines.append("")
            lines.append(transcript)
            lines.append("")
        }

        return lines.joined(separator: "\n")
    }

    /// File name used inside the shared app group, for example
    /// `2026-11-04-team-sync.md`.
    public static func fileName(for document: Document) -> String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        let datePart = formatter.string(from: document.date)
        return "\(datePart)-\(slug(for: document.title)).md"
    }

    /// A lower case, dash separated version of a title.
    public static func slug(for title: String) -> String {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let lowered = trimmed.lowercased()
        let cleaned = lowered.map { character -> Character in
            if character.isLetter || character.isNumber { return character }
            return "-"
        }
        var slug = String(cleaned)
        while slug.contains("--") {
            slug = slug.replacingOccurrences(of: "--", with: "-")
        }
        slug = slug.trimmingCharacters(in: CharacterSet(charactersIn: "-"))
        return slug.isEmpty ? "meeting" : slug
    }

    /// `12 min 30 s` style duration.
    public static func durationText(_ duration: TimeInterval) -> String {
        let total = max(0, Int(duration.rounded()))
        let minutes = total / 60
        let seconds = total % 60
        if minutes == 0 { return "\(seconds) s" }
        return "\(minutes) min \(seconds) s"
    }

    private static func longDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale.current
        formatter.dateStyle = .long
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
}
