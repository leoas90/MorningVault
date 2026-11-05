import Foundation
import FoundationModels

/// Turns a transcript plus the user's own notes into a structured summary using
/// Apple's on-device language model.
///
/// Nothing is sent to a server: the model runs inside the app.
@MainActor
public final class MeetingSummarizer: ObservableObject {
    public enum State: Equatable, Sendable {
        case idle
        case working
        case finished(MeetingSummary)
        case unavailable(String)
        case failed(String)
    }

    @Published public private(set) var state: State = .idle

    private static let instructions = """
    You are a precise meeting scribe. You turn raw transcripts into short, \
    factual notes. Never invent facts that are not in the material you are given. \
    If the user's own notes mention something, treat those notes as the most \
    reliable source and prefer them over the transcript. \
    Transcript lines may start with the speaker in square brackets, for example \
    `[You] I'll send the deck` or `[Speaker 2] Can we ship Friday?`. "You" is the \
    person whose notes these are. Use these labels to set the owner of each \
    action item: write "You" when the user took it on, otherwise the speaker's \
    name or the person the speaker assigned it to. Leave the owner empty when \
    it is not clear.
    """

    /// Produces a summary for the given material.
    public func summarize(transcript: String, scratchpad: String, title: String) async {
        let material = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        let notes = scratchpad.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !material.isEmpty && !notes.isEmpty || !material.isEmpty else {
            state = .failed("There is nothing to summarise yet.")
            return
        }

        switch SystemLanguageModel.default.availability {
        case .available:
            break
        case .unavailable(let reason):
            state = .unavailable(Self.message(for: reason))
            return
        }

        state = .working
        do {
            let summary = try await run(transcript: material, scratchpad: notes, title: title)
            state = .finished(summary)
        } catch {
            state = .failed(error.localizedDescription)
        }
    }

    /// Human readable reason why the on-device model cannot be used.
    public static func message(for reason: SystemLanguageModel.Availability.UnavailableReason) -> String {
        switch reason {
        case .deviceNotEligible:
            return "This device cannot run the on-device model, so notes are kept as a plain transcript."
        case .appleIntelligenceNotEnabled:
            return "Apple Intelligence is switched off. Turn it on in Settings › Apple Intelligence to get enhanced notes."
        case .modelNotReady:
            return "The on-device model is still downloading. Try again in a moment."
        @unknown default:
            return "The on-device model is unavailable right now."
        }
    }

    private func run(transcript: String, scratchpad: String, title: String) async throws -> MeetingSummary {
        let chunks = TextChunker.chunks(for: transcript)
        let notesBlock = scratchpad.isEmpty
            ? "The user did not write any notes of their own."
            : "The user's own notes (prioritise these):\n\(scratchpad)"

        if chunks.count <= 1 {
            let prompt = Self.prompt(
                transcript: transcript,
                notes: notesBlock,
                title: title,
                part: 1,
                parts: 1
            )
            let session = LanguageModelSession(instructions: Self.instructions)
            let response = try await session.respond(to: prompt, generating: MeetingSummary.self)
            return response.content
        }

        var partials: [String] = []
        for (index, chunk) in chunks.enumerated() {
            let prompt = Self.prompt(
                transcript: chunk,
                notes: notesBlock,
                title: title,
                part: index + 1,
                parts: chunks.count
            )
            // A fresh session for every chunk: the context window is small and
            // must not fill up with earlier parts of the meeting.
            let session = LanguageModelSession(instructions: Self.instructions)
            let response = try await session.respond(to: prompt, generating: MeetingSummary.self)
            partials.append(response.content.condensedText)
        }

        let merged = try await merge(partials: partials, scratchpad: notesBlock, title: title)
        return merged
    }

    private func merge(partials: [String], scratchpad: String, title: String) async throws -> MeetingSummary {
        let body = partials.joined(separator: "\n\n---\n\n")
        let prompt = """
        Below are summaries of each part of one long meeting. Merge them into a \
        single summary of the whole meeting. Remove duplicates, keep the order the \
        work happened in, and keep every action item.

        \(scratchpad)

        Part summaries:
        \(body)

        Meeting title hint: \(title.isEmpty ? "not given" : title)
        """
        // Another fresh session so the merge starts with an empty context.
        let session = LanguageModelSession(instructions: Self.instructions)
        let response = try await session.respond(to: prompt, generating: MeetingSummary.self)
        return response.content
    }

    private static func prompt(
        transcript: String,
        notes: String,
        title: String,
        part: Int,
        parts: Int
    ) -> String {
        let partLine = parts > 1 ? "This is part \(part) of \(parts) of one meeting." : "This is the whole meeting."
        return """
        \(partLine) Write the notes for it.

        \(notes)

        Transcript:
        \(transcript)

        Meeting title hint: \(title.isEmpty ? "not given" : title)
        """
    }
}
