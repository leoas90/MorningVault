import XCTest
@testable import MeetingNotesKit

final class NaturalVoiceTests: XCTestCase {
    func testChunksKeepFirstSentenceAlone() {
        let text = "Good morning. It is 58 degrees and clear. You have three meetings today. The first is at nine thirty."
        let chunks = NaturalVoice.chunks(of: text)
        XCTAssertEqual(chunks.first, "Good morning.")
        XCTAssertEqual(chunks.joined(separator: " "), text)
        XCTAssertTrue(chunks.allSatisfy { $0.count <= 220 })
    }

    func testChunksEmpty() {
        XCTAssertEqual(NaturalVoice.chunks(of: "   "), [])
    }

    /// Loads the bundled models (no network) and renders one sentence with Emma.
    func testSynthesizesFromBundledModels() async throws {
        XCTAssertNotNil(NaturalVoice.modelsDirectory)
        let voice = NaturalVoice()
        let audio = try await voice.synthesize("Good morning, Yezid. It's 58 degrees and clear in Murrieta.")
        XCTAssertEqual(audio.sampleRate, 24_000)
        XCTAssertGreaterThan(Double(audio.samples.count) / audio.sampleRate, 2.0)
        XCTAssertGreaterThan(audio.samples.map(abs).max() ?? 0, 0.01)
    }
}
