import Foundation
import FluidAudio

/// On-device neural voice for the spoken briefing: Kokoro 82M with the British "Emma" voice.
///
/// The models ship in the bundle (Resources/KokoroModels) and load from disk, so nothing is
/// downloaded and no briefing text leaves the phone. Synthesis is per chunk so playback can
/// start after the first sentence while the rest renders.
public actor NaturalVoice {
    public static let shared = NaturalVoice()

    /// Kokoro voice id. `bf_` voices get British phonemes.
    public static let voiceID = "bf_emma"

    private var manager: KokoroAneManager?

    /// Root that contains `kokoro-82m-coreml/ANE/` and `kokoro/` (FluidAudio's models layout).
    public static var modelsDirectory: URL? {
        Bundle.module.url(forResource: "KokoroModels", withExtension: nil)
    }

    public init() {}

    public var isReady: Bool { manager != nil }

    /// Loads the seven Core ML stages, the G2P frontend and the voice pack. Idempotent.
    public func prepare() async throws {
        if manager != nil { return }
        guard let directory = Self.modelsDirectory else { throw NaturalVoiceError.modelsMissing }
        let manager = KokoroAneManager(defaultVoice: Self.voiceID, directory: directory)
        try await manager.initialize(preloadVoices: [Self.voiceID])
        self.manager = manager
    }

    /// Mono Float32 samples for `text`, and their sample rate.
    public func synthesize(_ text: String, speed: Float = 1.0) async throws -> NaturalVoiceAudio {
        try await prepare()
        guard let manager else { throw NaturalVoiceError.modelsMissing }
        let result = try await manager.synthesizeDetailed(text: text, voice: Self.voiceID, speed: speed)
        return NaturalVoiceAudio(samples: result.samples, sampleRate: Double(result.sampleRate))
    }

    /// Splits a briefing into speakable chunks: sentences, merged up to ~`limit` characters,
    /// so the first chunk renders fast and none exceeds Kokoro's per-utterance phoneme cap.
    public nonisolated static func chunks(of text: String, limit: Int = 220) -> [String] {
        var sentences: [String] = []
        text.enumerateSubstrings(in: text.startIndex..., options: [.bySentences, .localized]) { sub, _, _, _ in
            if let s = sub?.trimmingCharacters(in: .whitespacesAndNewlines), !s.isEmpty { sentences.append(s) }
        }
        if sentences.isEmpty {
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? [] : [trimmed]
        }
        var out: [String] = []
        var current = ""
        for sentence in sentences {
            // Keep the first chunk to one sentence: it decides time-to-first-audio.
            if current.isEmpty {
                current = sentence
            } else if out.isEmpty || current.count + sentence.count + 1 > limit {
                out.append(current)
                current = sentence
            } else {
                current += " " + sentence
            }
        }
        if !current.isEmpty { out.append(current) }
        return out
    }
}

public struct NaturalVoiceAudio: Sendable {
    public let samples: [Float]
    public let sampleRate: Double
}

public enum NaturalVoiceError: Error {
    case modelsMissing
}
