import Foundation

/// The main user's voice: one unit length embedding kept in Application
/// Support. No audio is ever stored, only the 256 numbers.
public struct VoiceProfile: Sendable, Equatable, Codable {
    public var embedding: [Float]
    /// How many samples went into `embedding` (enrolment counts as one).
    public var sampleCount: Int
    public var updatedAt: Date
    /// When true, renaming a meeting speaker to "You" pulls the profile
    /// towards that speaker's voice.
    public var learnsFromRenames: Bool

    public init(embedding: [Float], sampleCount: Int = 1, updatedAt: Date = Date(), learnsFromRenames: Bool = true) {
        self.embedding = embedding
        self.sampleCount = sampleCount
        self.updatedAt = updatedAt
        self.learnsFromRenames = learnsFromRenames
    }

    /// The profile after one more voice sample.
    public func adding(sample: [Float]) -> VoiceProfile {
        var copy = self
        copy.embedding = SpeakerAssignment.runningAverage(current: embedding, count: sampleCount, adding: sample)
        copy.sampleCount += 1
        copy.updatedAt = Date()
        return copy
    }
}

/// Reads and writes the voice profile file.
public enum VoiceProfileStore {
    public static let fileName = "VoiceProfile.json"

    /// Where the profile lives. Override `directory` in tests.
    public static func url(in directory: URL? = nil) -> URL {
        (directory ?? MeetingNotesStore.applicationSupport).appendingPathComponent(fileName)
    }

    public static func load(from directory: URL? = nil) -> VoiceProfile? {
        let fileURL = url(in: directory)
        guard let data = try? Data(contentsOf: fileURL) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let profile = try? decoder.decode(VoiceProfile.self, from: data), !profile.embedding.isEmpty else {
            return nil
        }
        return profile
    }

    public static func save(_ profile: VoiceProfile, to directory: URL? = nil) throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(profile)
        let fileURL = url(in: directory)
        try data.write(to: fileURL, options: [.atomic, .completeFileProtection])
    }

    public static func delete(from directory: URL? = nil) {
        try? FileManager.default.removeItem(at: url(in: directory))
    }

    /// Learns from a speaker the user renamed to "You", when the profile allows it.
    ///
    /// Without a profile nothing happens: enrolment stays an explicit choice.
    @discardableResult
    public static func learn(from centroid: [Float], in directory: URL? = nil) -> Bool {
        guard !centroid.isEmpty, let profile = load(from: directory), profile.learnsFromRenames else { return false }
        guard profile.embedding.count == centroid.count else { return false }
        do {
            try save(profile.adding(sample: centroid), to: directory)
            return true
        } catch {
            return false
        }
    }
}
