import CoreMedia
import Speech
import XCTest
@testable import MeetingNotesKit

/// Live transcription must keep word timings, or every meeting is saved as one
/// block and speaker identification has nothing to split.
@MainActor
final class LiveTranscriberTimingTests: XCTestCase {
    private func word(_ text: String, _ start: Double, _ duration: Double) -> AttributedString {
        var piece = AttributedString(text)
        piece.audioTimeRange = CMTimeRange(
            start: CMTime(seconds: start, preferredTimescale: 600),
            duration: CMTime(seconds: duration, preferredTimescale: 600)
        )
        return piece
    }

    func testWordsReadFromAudioTimeRange() {
        var text = word("Welcome", 0.0, 0.4)
        text += word(" to", 0.4, 0.2)
        text += word(" the", 0.6, 0.2)
        text += word(" tour.", 0.8, 0.4)
        text += word(" Thanks", 3.0, 0.4)
        text += word(" for", 3.4, 0.2)
        text += word(" coming.", 3.6, 0.4)

        let words = LiveTranscriber.words(in: text)
        XCTAssertEqual(words.map(\.text), ["Welcome", "to", "the", "tour.", "Thanks", "for", "coming."])

        // A pause longer than 0.8 s starts a new piece, so a turn change can be found.
        let pieces = FileTranscriptionService.pieces(from: words, offset: 0)
        XCTAssertEqual(pieces.count, 2)
        XCTAssertEqual(pieces[0].text, "Welcome to the tour.")
        XCTAssertEqual(pieces[1].start, 3.0, accuracy: 0.01)
    }

    func testNoTimingsGivesNoWords() {
        XCTAssertTrue(LiveTranscriber.words(in: AttributedString("No timing here")).isEmpty)
    }
}
