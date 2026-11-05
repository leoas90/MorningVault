import XCTest
@testable import MeetingNotesKit

final class TextChunkerTests: XCTestCase {
    func testEmptyTextHasNoChunks() {
        XCTAssertTrue(TextChunker.chunks(for: "   ").isEmpty)
    }

    func testShortTextIsOneChunk() {
        let text = "We talked about the launch date and the budget."
        let chunks = TextChunker.chunks(for: text, maxWords: 100)
        XCTAssertEqual(chunks.count, 1)
        XCTAssertEqual(chunks[0], text)
    }

    func testSplitsOnParagraphBoundaries() {
        let paragraph = String(repeating: "word ", count: 10).trimmingCharacters(in: .whitespaces)
        let text = "\(paragraph)\n\n\(paragraph)\n\n\(paragraph)"
        let chunks = TextChunker.chunks(for: text, maxWords: 15)
        XCTAssertEqual(chunks.count, 3)
        for chunk in chunks {
            XCTAssertLessThanOrEqual(TextChunker.wordCount(chunk), 15)
        }
    }

    func testLongParagraphIsSplitOnSentences() {
        let sentence = "The team agreed on the new timeline for the release."
        let text = Array(repeating: sentence, count: 8).joined(separator: " ")
        let chunks = TextChunker.chunks(for: text, maxWords: 20)
        XCTAssertGreaterThan(chunks.count, 1)
        for chunk in chunks {
            XCTAssertLessThanOrEqual(TextChunker.wordCount(chunk), 20)
        }
    }

    func testWordCount() {
        XCTAssertEqual(TextChunker.wordCount("one two three"), 3)
        XCTAssertEqual(TextChunker.wordCount("  spaced \n out  "), 2)
        XCTAssertEqual(TextChunker.wordCount(""), 0)
    }

    func testDefaultChunkSizeMatchesTheBrief() {
        XCTAssertEqual(TextChunker.defaultChunkSize, 2_500)
    }
}
