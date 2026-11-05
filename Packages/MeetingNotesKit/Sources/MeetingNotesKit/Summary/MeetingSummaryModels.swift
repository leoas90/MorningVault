import Foundation
import FoundationModels

/// One thing somebody promised to do.
@Generable
public struct ActionItem: Codable, Sendable, Equatable {
    /// What has to happen.
    public var text: String
    /// Who is doing it, when the meeting mentioned it.
    public var owner: String?
    /// When it is due, in the words used in the meeting.
    public var due: String?

    public init(text: String, owner: String? = nil, due: String? = nil) {
        self.text = text
        self.owner = owner
        self.due = due
    }
}

/// The on-device summary of a meeting.
@Generable
public struct MeetingSummary: Codable, Sendable, Equatable {
    /// A short title for the meeting.
    public var title: String
    /// Three to five sentences describing what happened.
    public var summary: String
    /// The points worth remembering.
    public var keyPoints: [String]
    /// Decisions that were made.
    public var decisions: [String]
    /// Things to do next.
    public var actionItems: [ActionItem]
    /// Questions that were left open.
    public var followUpQuestions: [String]

    public init(
        title: String,
        summary: String,
        keyPoints: [String] = [],
        decisions: [String] = [],
        actionItems: [ActionItem] = [],
        followUpQuestions: [String] = []
    ) {
        self.title = title
        self.summary = summary
        self.keyPoints = keyPoints
        self.decisions = decisions
        self.actionItems = actionItems
        self.followUpQuestions = followUpQuestions
    }

    /// Plain text rendering used when chunk summaries are merged together.
    public var condensedText: String {
        var lines: [String] = []
        if !title.isEmpty { lines.append("Title: \(title)") }
        if !summary.isEmpty { lines.append("Summary: \(summary)") }
        if !keyPoints.isEmpty { lines.append("Key points: " + keyPoints.joined(separator: "; ")) }
        if !decisions.isEmpty { lines.append("Decisions: " + decisions.joined(separator: "; ")) }
        if !actionItems.isEmpty {
            let rendered = actionItems.map { item -> String in
                var text = item.text
                if let owner = item.owner, !owner.isEmpty { text += " (owner: \(owner))" }
                if let due = item.due, !due.isEmpty { text += " (due: \(due))" }
                return text
            }
            lines.append("Action items: " + rendered.joined(separator: "; "))
        }
        if !followUpQuestions.isEmpty {
            lines.append("Open questions: " + followUpQuestions.joined(separator: "; "))
        }
        return lines.joined(separator: "\n")
    }
}
