import Foundation

/// Joins finalised and volatile speech into the transcript the user reads.
///
/// Pure value type so the join rules can be tested without the Speech
/// framework. `LiveTranscriber` feeds it results; `RecordingSession` uses
/// `join` for the same rule.
public struct TranscriptAssembler: Equatable, Sendable {
    /// Speech the recogniser has settled on.
    public private(set) var finalText: String = ""
    /// Speech that may still change. Replaced by every volatile result and
    /// cleared by the final one that covers it.
    public private(set) var volatileText: String = ""

    public init() {}

    /// The transcript as it should read right now.
    public var text: String {
        Self.join(final: finalText, volatile: volatileText)
    }

    /// Applies one recogniser result.
    ///
    /// - Returns: the trimmed piece that was added to `finalText`, when `isFinal`
    ///   and the text was not empty; `nil` otherwise.
    @discardableResult
    public mutating func apply(text: String, isFinal: Bool) -> String? {
        guard isFinal else {
            volatileText = text
            return nil
        }
        // A final result supersedes the volatile text it was a draft of.
        volatileText = ""
        let piece = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !piece.isEmpty else { return nil }
        if finalText.isEmpty {
            finalText = piece
        } else {
            finalText += " " + piece
        }
        return piece
    }

    /// Forgets everything.
    public mutating func reset() {
        finalText = ""
        volatileText = ""
    }

    /// `final`, a space, and the trimmed `volatile` tail when there is one.
    public static func join(final: String, volatile: String) -> String {
        let tail = volatile.trimmingCharacters(in: .whitespacesAndNewlines)
        if tail.isEmpty { return final }
        if final.isEmpty { return tail }
        return final + " " + tail
    }
}
