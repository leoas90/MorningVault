import Foundation

/// Pure maths behind speaker labels: who said which transcript piece, how
/// close two voices are, and how a voice profile learns.
///
/// Nothing in here touches CoreML, so it is fully unit tested.
public enum SpeakerAssignment {
    /// Lowest cosine similarity between a meeting speaker's centroid and the
    /// enrolled voice for the speaker to be labelled "You".
    ///
    /// WeSpeaker embeddings of the same person in different recordings
    /// typically land around 0.6–0.8 cosine similarity, while different
    /// people sit well under 0.4. FluidAudio's own clustering accepts a far
    /// looser gate (cosine distance ≤ 0.7, i.e. similarity ≥ 0.3) because it
    /// merges fragments of one recording. Picking "You" is a stronger claim
    /// and a false "You" is worse than an unnamed speaker, so the bar is 0.5.
    public static let youMatchThreshold: Float = 0.5

    /// When a piece overlaps no turn, the nearest turn still claims it if
    /// it starts or ends within this many seconds.
    public static let nearestTurnTolerance: TimeInterval = 1.0

    // MARK: - Overlap

    /// For every piece, the key of the turn that overlaps it most.
    ///
    /// A piece without any overlap takes the nearest turn when it is within
    /// `nearestTurnTolerance`, and `nil` otherwise. Pieces with no length are
    /// treated as a point in time.
    public static func assign(pieces: [TranscriptPiece], to turns: [SpeakerTurn]) -> [String?] {
        guard !turns.isEmpty else { return pieces.map { _ in nil } }
        let sorted = turns.sorted { $0.start < $1.start }
        return pieces.map { piece in
            assign(piece: piece, sortedTurns: sorted)
        }
    }

    static func assign(piece: TranscriptPiece, sortedTurns: [SpeakerTurn]) -> String? {
        let pieceStart = piece.start
        let pieceEnd = max(piece.end, piece.start)
        var overlapBySpeaker: [String: TimeInterval] = [:]
        var bestGap = TimeInterval.greatestFiniteMagnitude
        var nearest: String?

        for turn in sortedTurns {
            if turn.start > pieceEnd + nearestTurnTolerance { break }
            let overlapStart = max(pieceStart, turn.start)
            let overlapEnd = min(pieceEnd, turn.end)
            var overlap = overlapEnd - overlapStart
            if pieceEnd == pieceStart, pieceStart >= turn.start, pieceStart <= turn.end {
                // A point inside a turn counts as a hit.
                overlap = .leastNonzeroMagnitude
            }
            if overlap > 0 {
                overlapBySpeaker[turn.speakerKey, default: 0] += overlap
                continue
            }
            let gap = turn.end < pieceStart ? pieceStart - turn.end : turn.start - pieceEnd
            if gap < bestGap {
                bestGap = gap
                nearest = turn.speakerKey
            }
        }

        if let best = overlapBySpeaker.max(by: { lhs, rhs in
            if lhs.value != rhs.value { return lhs.value < rhs.value }
            return lhs.key > rhs.key
        }) {
            return best.key
        }
        if bestGap <= nearestTurnTolerance { return nearest }
        return nil
    }

    // MARK: - Embeddings

    /// Cosine similarity in -1...1; 0 when either vector is empty, zero or of a different length.
    public static func cosineSimilarity(_ a: [Float], _ b: [Float]) -> Float {
        guard a.count == b.count, !a.isEmpty else { return 0 }
        var dot: Float = 0
        var normA: Float = 0
        var normB: Float = 0
        for index in a.indices {
            dot += a[index] * b[index]
            normA += a[index] * a[index]
            normB += b[index] * b[index]
        }
        guard normA > 0, normB > 0 else { return 0 }
        return dot / (normA.squareRoot() * normB.squareRoot())
    }

    /// The vector scaled to unit length. A zero vector stays zero.
    public static func normalized(_ vector: [Float]) -> [Float] {
        let norm = vector.reduce(0) { $0 + $1 * $1 }.squareRoot()
        guard norm > 0 else { return vector }
        return vector.map { $0 / norm }
    }

    /// Duration weighted mean of embeddings, unit length. Empty when nothing usable came in.
    public static func centroid(of embeddings: [(embedding: [Float], weight: Float)]) -> [Float] {
        let usable = embeddings.filter { !$0.embedding.isEmpty && $0.weight > 0 && $0.embedding.contains { $0 != 0 } }
        guard let first = usable.first else { return [] }
        var sum = [Float](repeating: 0, count: first.embedding.count)
        for item in usable where item.embedding.count == sum.count {
            let unit = normalized(item.embedding)
            for index in sum.indices {
                sum[index] += unit[index] * item.weight
            }
        }
        return normalized(sum)
    }

    /// Key of the label whose centroid is closest to `enrolled`, when it clears `threshold`.
    public static func bestMatch(
        among labels: [SpeakerLabel],
        enrolled: [Float],
        threshold: Float = youMatchThreshold
    ) -> String? {
        guard !enrolled.isEmpty else { return nil }
        var bestKey: String?
        var bestScore: Float = -2
        for label in labels where !label.centroid.isEmpty {
            let score = cosineSimilarity(label.centroid, enrolled)
            if score > bestScore {
                bestScore = score
                bestKey = label.key
            }
        }
        return bestScore >= threshold ? bestKey : nil
    }

    /// Default names, with the matched speaker called "You" and the others
    /// numbered in order of appearance: "Speaker 1", "Speaker 2", ...
    public static func defaultNames(for keys: [String], youKey: String?) -> [String: String] {
        var names: [String: String] = [:]
        var number = 1
        for key in keys {
            if key == youKey {
                names[key] = SpeakerLabel.youName
            } else {
                names[key] = "Speaker \(number)"
                number += 1
            }
        }
        return names
    }

    /// Running average of a voice profile: `count` earlier samples pulled
    /// towards one new embedding. The result is unit length.
    public static func runningAverage(current: [Float], count: Int, adding sample: [Float]) -> [Float] {
        let unitSample = normalized(sample)
        guard !current.isEmpty, current.count == unitSample.count, count > 0 else { return unitSample }
        let unitCurrent = normalized(current)
        let weight = Float(count)
        var mixed = [Float](repeating: 0, count: current.count)
        for index in mixed.indices {
            mixed[index] = (unitCurrent[index] * weight + unitSample[index]) / (weight + 1)
        }
        return normalized(mixed)
    }

    // MARK: - Text

    /// Groups consecutive pieces of one speaker into turns of text.
    public static func turns(
        from pieces: [TranscriptPiece],
        keys: [String?],
        names: (String?) -> String?
    ) -> [SpokenTurn] {
        var result: [SpokenTurn] = []
        for (index, piece) in pieces.enumerated() {
            let text = piece.text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { continue }
            let key = index < keys.count ? keys[index] : nil
            let name = names(key)
            if let last = result.last, last.name == name, last.speakerKey == key {
                result[result.count - 1].text += " " + text
            } else {
                result.append(SpokenTurn(index: result.count, speakerKey: key, name: name, text: text))
            }
        }
        return result
    }

    /// The transcript as `[Name] text` lines, one per turn, for the summarizer and exports.
    public static func labelledTranscript(
        pieces: [TranscriptPiece],
        keys: [String?],
        names: (String?) -> String?,
        unknownName: String = "Unknown"
    ) -> String {
        turns(from: pieces, keys: keys, names: names)
            .map { "[\($0.name ?? unknownName)] \($0.text)" }
            .joined(separator: "\n")
    }
}
