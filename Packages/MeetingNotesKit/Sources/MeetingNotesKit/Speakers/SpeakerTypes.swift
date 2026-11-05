import Foundation

/// A piece of recognised speech with its position in the recording.
///
/// Produced by live transcription (one per finalised result) and by file
/// transcription (grouped word runs). Times are seconds from the start of
/// the recording, the same timeline the diarizer uses.
public struct TranscriptPiece: Sendable, Equatable, Codable {
    public var text: String
    public var start: TimeInterval
    public var end: TimeInterval

    public init(text: String, start: TimeInterval, end: TimeInterval) {
        self.text = text
        self.start = start
        self.end = min(max(start, end), .greatestFiniteMagnitude)
    }
}

/// One stretch where one speaker was talking, as found by diarization.
public struct SpeakerTurn: Sendable, Equatable {
    public var speakerKey: String
    public var start: TimeInterval
    public var end: TimeInterval

    public init(speakerKey: String, start: TimeInterval, end: TimeInterval) {
        self.speakerKey = speakerKey
        self.start = start
        self.end = max(start, end)
    }
}

/// A speaker of one meeting: the diarizer's key, the name shown to the user
/// and the average voice embedding, kept so a later rename to "You" can teach
/// the voice profile.
public struct SpeakerLabel: Sendable, Equatable, Codable, Identifiable {
    /// Name used for the main user, both as default label and in prompts.
    public static let youName = "You"

    public var key: String
    public var name: String
    /// Unit length voice embedding, empty when unknown.
    public var centroid: [Float]
    /// How long this speaker talked, in seconds.
    public var seconds: TimeInterval

    public var id: String { key }

    public init(key: String, name: String, centroid: [Float] = [], seconds: TimeInterval = 0) {
        self.key = key
        self.name = name
        self.centroid = centroid
        self.seconds = seconds
    }

    /// True when this speaker is the main user.
    public var isYou: Bool {
        name.trimmingCharacters(in: .whitespacesAndNewlines).caseInsensitiveCompare(Self.youName) == .orderedSame
    }

    /// Encodes labels for `Meeting.speakerLabelsJSON`.
    public static func encode(_ labels: [SpeakerLabel]) -> String? {
        guard !labels.isEmpty, let data = try? JSONEncoder().encode(labels) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    /// Decodes labels from `Meeting.speakerLabelsJSON`.
    public static func decode(_ json: String?) -> [SpeakerLabel] {
        guard let json, let data = json.data(using: .utf8) else { return [] }
        return (try? JSONDecoder().decode([SpeakerLabel].self, from: data)) ?? []
    }
}

/// Consecutive transcript pieces of one speaker, ready to show as "Name: text".
public struct SpokenTurn: Sendable, Equatable, Identifiable {
    public var index: Int
    public var speakerKey: String?
    public var name: String?
    public var text: String

    public var id: Int { index }

    public init(index: Int, speakerKey: String?, name: String?, text: String) {
        self.index = index
        self.speakerKey = speakerKey
        self.name = name
        self.text = text
    }
}

/// What came out of diarizing one recording.
public struct SpeakerIdentification: Sendable, Equatable {
    public var turns: [SpeakerTurn]
    public var labels: [SpeakerLabel]

    public init(turns: [SpeakerTurn], labels: [SpeakerLabel]) {
        self.turns = turns
        self.labels = labels
    }
}

extension Meeting {
    /// Speakers of this meeting, decoded from `speakerLabelsJSON`.
    public var speakerLabels: [SpeakerLabel] {
        get { SpeakerLabel.decode(speakerLabelsJSON) }
        set { speakerLabelsJSON = SpeakerLabel.encode(newValue) }
    }

    /// The display name of a speaker key, or `nil` when the key is unknown.
    public func speakerName(for key: String?) -> String? {
        guard let key else { return nil }
        return speakerLabels.first { $0.key == key }?.name
    }
}
