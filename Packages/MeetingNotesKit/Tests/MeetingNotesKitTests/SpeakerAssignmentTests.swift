import AVFoundation
import XCTest
@testable import MeetingNotesKit

final class SpeakerAssignmentTests: XCTestCase {
    // MARK: - Overlap assignment

    func testPieceTakesSpeakerWithMostOverlap() {
        let turns = [
            SpeakerTurn(speakerKey: "A", start: 0, end: 5),
            SpeakerTurn(speakerKey: "B", start: 5, end: 12)
        ]
        let pieces = [
            TranscriptPiece(text: "hello", start: 1, end: 4),      // all A
            TranscriptPiece(text: "there", start: 4, end: 8),      // 1 s A, 3 s B
            TranscriptPiece(text: "friend", start: 9, end: 11)     // all B
        ]
        XCTAssertEqual(SpeakerAssignment.assign(pieces: pieces, to: turns), ["A", "B", "B"])
    }

    func testOverlapAddsUpAcrossSeveralTurnsOfOneSpeaker() {
        let turns = [
            SpeakerTurn(speakerKey: "A", start: 0, end: 2),
            SpeakerTurn(speakerKey: "B", start: 2, end: 4.5),
            SpeakerTurn(speakerKey: "A", start: 4.5, end: 7)
        ]
        // A: 2 + 2.5 = 4.5 s, B: 2.5 s
        let piece = TranscriptPiece(text: "long", start: 0, end: 7)
        XCTAssertEqual(SpeakerAssignment.assign(pieces: [piece], to: turns), ["A"])
    }

    func testNoOverlapUsesNearestTurnWithinTolerance() {
        let turns = [
            SpeakerTurn(speakerKey: "A", start: 0, end: 5),
            SpeakerTurn(speakerKey: "B", start: 9, end: 12)
        ]
        let near = TranscriptPiece(text: "gap", start: 5.2, end: 5.8)   // 0.2 s after A
        let far = TranscriptPiece(text: "silence", start: 6.5, end: 7.5) // 1.5 s from both
        XCTAssertEqual(SpeakerAssignment.assign(pieces: [near, far], to: turns), ["A", nil])
    }

    func testNoTurnsGivesNoSpeakers() {
        let pieces = [TranscriptPiece(text: "a", start: 0, end: 1)]
        XCTAssertEqual(SpeakerAssignment.assign(pieces: pieces, to: []), [nil])
    }

    func testZeroLengthPieceInsideTurnIsAssigned() {
        let turns = [SpeakerTurn(speakerKey: "A", start: 2, end: 6)]
        let piece = TranscriptPiece(text: "point", start: 3, end: 3)
        XCTAssertEqual(SpeakerAssignment.assign(pieces: [piece], to: turns), ["A"])
    }

    // MARK: - Cosine similarity and threshold

    func testCosineSimilarityOfIdenticalAndOrthogonalVectors() {
        XCTAssertEqual(SpeakerAssignment.cosineSimilarity([1, 0, 0], [2, 0, 0]), 1, accuracy: 1e-6)
        XCTAssertEqual(SpeakerAssignment.cosineSimilarity([1, 0, 0], [0, 1, 0]), 0, accuracy: 1e-6)
        XCTAssertEqual(SpeakerAssignment.cosineSimilarity([1, 0], [-1, 0]), -1, accuracy: 1e-6)
        XCTAssertEqual(SpeakerAssignment.cosineSimilarity([], []), 0)
        XCTAssertEqual(SpeakerAssignment.cosineSimilarity([1, 2], [1, 2, 3]), 0)
        XCTAssertEqual(SpeakerAssignment.cosineSimilarity([0, 0], [1, 1]), 0)
    }

    func testBestMatchRespectsThreshold() {
        let enrolled: [Float] = [1, 0, 0]
        let labels = [
            SpeakerLabel(key: "1", name: "1", centroid: [0.6, 0.8, 0]),   // sim 0.6
            SpeakerLabel(key: "2", name: "2", centroid: [0.3, 0.954, 0]), // sim 0.3
            SpeakerLabel(key: "3", name: "3", centroid: [])
        ]
        XCTAssertEqual(SpeakerAssignment.bestMatch(among: labels, enrolled: enrolled, threshold: 0.5), "1")
        XCTAssertNil(SpeakerAssignment.bestMatch(among: labels, enrolled: enrolled, threshold: 0.7))
        XCTAssertNil(SpeakerAssignment.bestMatch(among: labels, enrolled: [], threshold: 0.1))
        XCTAssertEqual(SpeakerAssignment.youMatchThreshold, 0.5)
    }

    func testDefaultNamesNumberOthersAndCallMatchYou() {
        let names = SpeakerAssignment.defaultNames(for: ["s7", "s2", "s9"], youKey: "s2")
        XCTAssertEqual(names, ["s7": "Speaker 1", "s2": "You", "s9": "Speaker 2"])
        let plain = SpeakerAssignment.defaultNames(for: ["a", "b"], youKey: nil)
        XCTAssertEqual(plain, ["a": "Speaker 1", "b": "Speaker 2"])
    }

    func testCentroidIsDurationWeightedAndUnitLength() {
        let centroid = SpeakerAssignment.centroid(of: [
            ([1, 0], 3),
            ([0, 1], 1),
            ([0, 0], 5),          // zero vectors are ignored
            ([5, 5], 0)           // zero weight is ignored
        ])
        XCTAssertEqual(centroid.count, 2)
        let norm = (centroid[0] * centroid[0] + centroid[1] * centroid[1]).squareRoot()
        XCTAssertEqual(norm, 1, accuracy: 1e-5)
        XCTAssertGreaterThan(centroid[0], centroid[1])
        XCTAssertEqual(centroid[0] / centroid[1], 3, accuracy: 1e-4)
        XCTAssertTrue(SpeakerAssignment.centroid(of: []).isEmpty)
    }

    // MARK: - Running average

    func testRunningAverageWeightsEarlierSamples() {
        let current: [Float] = [1, 0]
        let updated = SpeakerAssignment.runningAverage(current: current, count: 3, adding: [0, 1])
        // (3·[1,0] + [0,1]) / 4 = [0.75, 0.25], then unit length.
        XCTAssertEqual(updated[0] / updated[1], 3, accuracy: 1e-5)
        let norm = (updated[0] * updated[0] + updated[1] * updated[1]).squareRoot()
        XCTAssertEqual(norm, 1, accuracy: 1e-5)
    }

    func testRunningAverageStartsFromSampleWhenNothingStored() {
        let updated = SpeakerAssignment.runningAverage(current: [], count: 0, adding: [0, 2])
        XCTAssertEqual(updated, [0, 1])
        let mismatched = SpeakerAssignment.runningAverage(current: [1, 0, 0], count: 2, adding: [0, 2])
        XCTAssertEqual(mismatched, [0, 1])
    }

    func testVoiceProfileAddingSampleBumpsCount() {
        let profile = VoiceProfile(embedding: [1, 0], sampleCount: 1)
        let next = profile.adding(sample: [0, 1])
        XCTAssertEqual(next.sampleCount, 2)
        XCTAssertEqual(next.embedding[0], next.embedding[1], accuracy: 1e-5)
    }

    func testVoiceProfileStoreRoundTripAndLearn() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("voice-profile-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        XCTAssertNil(VoiceProfileStore.load(from: directory))
        XCTAssertFalse(VoiceProfileStore.learn(from: [0, 1], in: directory), "no profile, nothing to learn")

        try VoiceProfileStore.save(VoiceProfile(embedding: [1, 0], sampleCount: 1), to: directory)
        XCTAssertEqual(VoiceProfileStore.load(from: directory)?.embedding, [1, 0])

        XCTAssertTrue(VoiceProfileStore.learn(from: [0, 1], in: directory))
        let learned = try XCTUnwrap(VoiceProfileStore.load(from: directory))
        XCTAssertEqual(learned.sampleCount, 2)
        XCTAssertEqual(learned.embedding[0], learned.embedding[1], accuracy: 1e-5)

        try VoiceProfileStore.save(VoiceProfile(embedding: [1, 0], sampleCount: 1, learnsFromRenames: false), to: directory)
        XCTAssertFalse(VoiceProfileStore.learn(from: [0, 1], in: directory), "opt-out blocks learning")

        VoiceProfileStore.delete(from: directory)
        XCTAssertNil(VoiceProfileStore.load(from: directory))
    }

    // MARK: - Text

    func testTurnsMergeConsecutivePiecesOfOneSpeaker() {
        let pieces = [
            TranscriptPiece(text: "Hi all.", start: 0, end: 1),
            TranscriptPiece(text: "Let's start.", start: 1, end: 2),
            TranscriptPiece(text: "Sure.", start: 2, end: 3),
            TranscriptPiece(text: "", start: 3, end: 3)
        ]
        let names: [String: String] = ["a": "You", "b": "Speaker 1"]
        let turns = SpeakerAssignment.turns(from: pieces, keys: ["a", "a", "b", "b"], names: { $0.flatMap { names[$0] } })
        XCTAssertEqual(turns.map(\.name), ["You", "Speaker 1"])
        XCTAssertEqual(turns.map(\.text), ["Hi all. Let's start.", "Sure."])

        let labelled = SpeakerAssignment.labelledTranscript(pieces: pieces, keys: ["a", "a", "b", nil], names: { $0.flatMap { names[$0] } })
        XCTAssertEqual(labelled, "[You] Hi all. Let's start.\n[Speaker 1] Sure.")
    }

    func testSpeakerLabelJSONRoundTrip() {
        let labels = [SpeakerLabel(key: "1", name: "You", centroid: [0.5, 0.5], seconds: 12)]
        let json = SpeakerLabel.encode(labels)
        XCTAssertEqual(SpeakerLabel.decode(json), labels)
        XCTAssertTrue(SpeakerLabel.decode(nil).isEmpty)
        XCTAssertNil(SpeakerLabel.encode([]))
        XCTAssertTrue(labels[0].isYou)
    }

    func testFilePiecesSplitOnPausesAndWordBudget() {
        let words: [FileTranscriptionService.RecognizedWord] = [
            .init(text: "one", start: 0, duration: 0.3), .init(text: "two", start: 0.4, duration: 0.3),
            .init(text: "three", start: 2.0, duration: 0.3), .init(text: "four", start: 2.4, duration: 0.3)
        ]
        let pieces = FileTranscriptionService.pieces(from: words, offset: 60, pause: 0.8, maxWords: 24)
        XCTAssertEqual(pieces.map(\.text), ["one two", "three four"])
        XCTAssertEqual(pieces[0].start, 60, accuracy: 1e-9)
        XCTAssertEqual(pieces[0].end, 60.7, accuracy: 1e-9)
        XCTAssertEqual(pieces[1].start, 62, accuracy: 1e-9)

        let budget = FileTranscriptionService.pieces(from: words, offset: 0, pause: 10, maxWords: 3)
        XCTAssertEqual(budget.map(\.text), ["one two three", "four"])
    }

    func testMergeAdjacentTurns() {
        let merged = SpeakerDiarizer.mergeAdjacent([
            SpeakerTurn(speakerKey: "A", start: 0, end: 2),
            SpeakerTurn(speakerKey: "A", start: 2.1, end: 4),
            SpeakerTurn(speakerKey: "B", start: 4, end: 5),
            SpeakerTurn(speakerKey: "A", start: 5, end: 6)
        ])
        XCTAssertEqual(merged, [
            SpeakerTurn(speakerKey: "A", start: 0, end: 4),
            SpeakerTurn(speakerKey: "B", start: 4, end: 5),
            SpeakerTurn(speakerKey: "A", start: 5, end: 6)
        ])
    }

    func testBundledModelsArePresent() {
        XCTAssertTrue(SpeakerDiarizer.isAvailable, "DiarizerModels must be copied into the package bundle")
    }
}

final class SpeakerDiarizerModelTests: XCTestCase {
    /// Loads the bundled CoreML models and embeds a synthetic voice-like clip.
    /// Proves the offline load path works without any network.
    func testBundledModelsProduceAnEmbedding() async throws {
        let rate = 16_000
        var samples = [Float](repeating: 0, count: rate * 12)
        for index in samples.indices {
            let t = Float(index) / Float(rate)
            // Harmonic buzz with a slow amplitude wobble, enough for the model to run.
            let envelope = 0.5 + 0.5 * sin(2 * .pi * 3 * t)
            samples[index] = envelope * 0.2 * (sin(2 * .pi * 140 * t) + 0.5 * sin(2 * .pi * 280 * t) + 0.25 * sin(2 * .pi * 560 * t))
        }
        let embedding = try await SpeakerDiarizer.shared.embedding(of: samples)
        XCTAssertEqual(embedding.count, 256)
        let norm = embedding.reduce(0) { $0 + $1 * $1 }.squareRoot()
        XCTAssertEqual(norm, 1, accuracy: 1e-3)
        XCTAssertFalse(embedding.contains { $0.isNaN })
    }

    /// Diarizes a synthetic file with two different "voices" and expects turns back.
    func testBundledModelsDiarizeAFile() async throws {
        let rate = 16_000.0
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("diarize-\(UUID().uuidString).caf")
        defer { try? FileManager.default.removeItem(at: url) }
        // 44.1 kHz stereo PCM so the loader's resample-to-16k-mono path is exercised too.
        let sourceRate = 44_100.0
        var samples = [Float](repeating: 0, count: Int(rate) * 24)
        for index in samples.indices {
            let t = Float(index) / Float(rate)
            let second = Int(t) / 6 % 2 == 0
            let f0: Float = second ? 120 : 230
            let envelope = 0.5 + 0.5 * sin(2 * .pi * 4 * t)
            samples[index] = envelope * 0.2 * (sin(2 * .pi * f0 * t) + 0.5 * sin(2 * .pi * 2 * f0 * t) + 0.3 * sin(2 * .pi * 3 * f0 * t))
        }
        let format = try XCTUnwrap(AVAudioFormat(standardFormatWithSampleRate: sourceRate, channels: 2))
        do {
        let file = try AVAudioFile(forWriting: url, settings: format.settings)
        let frames = Int(Double(samples.count) * sourceRate / rate)
        let buffer = try XCTUnwrap(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(frames)))
        buffer.frameLength = AVAudioFrameCount(frames)
        for frame in 0..<frames {
            let value = samples[min(samples.count - 1, Int(Double(frame) * rate / sourceRate))]
            buffer.floatChannelData?[0][frame] = value
            buffer.floatChannelData?[1][frame] = value
        }
        try file.write(from: buffer)
        file.close()
        }

        let result = try await SpeakerDiarizer.shared.diarize(fileURL: url)
        XCTAssertFalse(result.turns.isEmpty)
        XCTAssertFalse(result.labels.isEmpty)
        for label in result.labels {
            XCTAssertEqual(label.centroid.count, 256, "speaker \(label.key) has no centroid")
        }
        XCTAssertLessThanOrEqual(result.turns.map(\.end).max() ?? 0, 25)
    }
}
