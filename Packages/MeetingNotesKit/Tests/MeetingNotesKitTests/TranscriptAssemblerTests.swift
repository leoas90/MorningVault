import Foundation
import XCTest
@testable import MeetingNotesKit

/// H1: a final result replaces the volatile draft it supersedes, so nothing is shown twice.
final class TranscriptAssemblerTests: XCTestCase {
    func testVolatileResultReplacesPreviousVolatile() {
        var assembler = TranscriptAssembler()
        XCTAssertNil(assembler.apply(text: "hello", isFinal: false))
        XCTAssertNil(assembler.apply(text: "hello there", isFinal: false))
        XCTAssertEqual(assembler.finalText, "")
        XCTAssertEqual(assembler.volatileText, "hello there")
        XCTAssertEqual(assembler.text, "hello there")
    }

    func testFinalResultClearsVolatileAndAppends() {
        var assembler = TranscriptAssembler()
        assembler.apply(text: "hello there", isFinal: false)
        XCTAssertEqual(assembler.apply(text: " hello there ", isFinal: true), "hello there")
        XCTAssertEqual(assembler.finalText, "hello there")
        XCTAssertEqual(assembler.volatileText, "", "the draft must not linger after it was finalised")
        XCTAssertEqual(assembler.text, "hello there", "the phrase must appear once, not twice")

        assembler.apply(text: "how are", isFinal: false)
        XCTAssertEqual(assembler.text, "hello there how are")
        assembler.apply(text: "how are you?", isFinal: true)
        XCTAssertEqual(assembler.finalText, "hello there how are you?")
        XCTAssertEqual(assembler.volatileText, "")
        XCTAssertEqual(assembler.text, "hello there how are you?")
    }

    func testEmptyFinalResultStillClearsVolatile() {
        var assembler = TranscriptAssembler()
        assembler.apply(text: "um", isFinal: false)
        XCTAssertNil(assembler.apply(text: "   ", isFinal: true))
        XCTAssertEqual(assembler.finalText, "")
        XCTAssertEqual(assembler.volatileText, "")
        XCTAssertEqual(assembler.text, "")
    }

    func testJoinRules() {
        XCTAssertEqual(TranscriptAssembler.join(final: "", volatile: ""), "")
        XCTAssertEqual(TranscriptAssembler.join(final: "a", volatile: ""), "a")
        XCTAssertEqual(TranscriptAssembler.join(final: "", volatile: " b "), "b")
        XCTAssertEqual(TranscriptAssembler.join(final: "a", volatile: " b "), "a b")
    }

    func testResetForgetsEverything() {
        var assembler = TranscriptAssembler()
        assembler.apply(text: "one", isFinal: true)
        assembler.apply(text: "two", isFinal: false)
        assembler.reset()
        XCTAssertEqual(assembler, TranscriptAssembler())
    }
}
