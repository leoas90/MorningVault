import AVFoundation
@preconcurrency import CoreML
import FluidAudio
import Foundation

/// On-device speaker diarization built on FluidAudio's pyannote + WeSpeaker
/// CoreML models.
///
/// Offline by construction: the models ship inside this package
/// (`Resources/DiarizerModels`) and are opened with `MLModel(contentsOf:)`
/// through `DiarizerModels.load(localSegmentationModel:localEmbeddingModel:)`.
/// That entry point never touches `ModelHub`, the only part of FluidAudio
/// that can reach the network. `DiarizerModels.download`/`load(from:)` are
/// never called anywhere in this package.
///
/// `DiarizerManager` is not `Sendable`, so it lives inside this actor and
/// never escapes it.
public actor SpeakerDiarizer {
    public static let shared = SpeakerDiarizer()

    public enum Failure: LocalizedError, Sendable {
        case modelsMissing(String)
        case modelsUnloadable(String)
        case noSpeech
        case processing(String)

        public var errorDescription: String? {
            switch self {
            case .modelsMissing(let name):
                return "The speaker model “\(name)” is missing from the app."
            case .modelsUnloadable(let reason):
                return "The speaker models could not be loaded: \(reason)"
            case .noSpeech:
                return "No speech was found in the recording."
            case .processing(let reason):
                return "Speaker identification failed: \(reason)"
            }
        }
    }

    /// Sample rate the models expect.
    public static let sampleRate = 16_000
    /// The embedding model looks at 10 s windows.
    public static let windowSamples = 160_000
    /// How much audio is handed to the diarizer at once (bounded memory).
    static let blockSeconds: Double = 300

    private var models: DiarizerModels?

    private init() {}

    // MARK: - Models

    /// Bundle folder that holds the CoreML models.
    nonisolated static func modelsDirectory() -> URL? {
        Bundle.module.url(forResource: "DiarizerModels", withExtension: nil)
    }

    private func loadedModels() throws -> DiarizerModels {
        if let models { return models }
        guard let directory = Self.modelsDirectory() else {
            throw Failure.modelsMissing("DiarizerModels")
        }
        let segmentation = directory.appendingPathComponent(ModelNames.Diarizer.segmentationFile)
        let embedding = directory.appendingPathComponent(ModelNames.Diarizer.embeddingFile)
        for url in [segmentation, embedding] where !FileManager.default.fileExists(atPath: url.path) {
            throw Failure.modelsMissing(url.lastPathComponent)
        }
        let configuration = MLModelConfiguration()
        configuration.computeUnits = .all
        do {
            let loaded = try DiarizerModels.load(
                localSegmentationModel: segmentation,
                localEmbeddingModel: embedding,
                configuration: configuration
            )
            models = loaded
            return loaded
        } catch {
            throw Failure.modelsUnloadable(error.localizedDescription)
        }
    }

    /// True when the bundled models are present. Does not load them.
    public nonisolated static var isAvailable: Bool {
        guard let directory = modelsDirectory() else { return false }
        return [ModelNames.Diarizer.segmentationFile, ModelNames.Diarizer.embeddingFile].allSatisfy {
            FileManager.default.fileExists(atPath: directory.appendingPathComponent($0).path)
        }
    }

    // MARK: - Diarization

    /// Finds who spoke when in the recording at `url`.
    ///
    /// Returns the turns and one label per speaker. Labels are keyed by the
    /// diarizer's own ids and carry the duration weighted voice centroid; the
    /// caller decides the names.
    public func diarize(fileURL: URL, progress: (@Sendable (Double) -> Void)? = nil) throws -> SpeakerIdentification {
        let models = try loadedModels()
        let manager = DiarizerManager(config: DiarizerConfig(
            clusteringThreshold: 0.7,
            minSpeechDuration: 0.5,
            minSilenceGap: 0.4
        ))
        manager.initialize(models: models)
        defer { manager.cleanup() }

        let totalSeconds = Self.duration(of: fileURL)
        var turns: [SpeakerTurn] = []
        var embeddings: [String: [(embedding: [Float], weight: Float)]] = [:]
        var firstSeen: [String] = []

        do {
            try AudioFileSamples.read(url: fileURL, blockSeconds: Self.blockSeconds) { block, start in
                let result = try manager.performCompleteDiarization(
                    block,
                    sampleRate: Self.sampleRate,
                    atTime: start
                )
                for segment in result.segments {
                    let key = segment.speakerId
                    turns.append(SpeakerTurn(
                        speakerKey: key,
                        start: TimeInterval(segment.startTimeSeconds),
                        end: TimeInterval(segment.endTimeSeconds)
                    ))
                    if !firstSeen.contains(key) { firstSeen.append(key) }
                    embeddings[key, default: []].append((segment.embedding, max(segment.durationSeconds, 0.1)))
                }
                if let progress, totalSeconds > 0 {
                    progress(min(1, (start + Double(block.count) / Double(Self.sampleRate)) / totalSeconds))
                }
                return !Task.isCancelled
            }
        } catch let failure as Failure {
            throw failure
        } catch {
            throw Failure.processing(error.localizedDescription)
        }

        guard !turns.isEmpty else { throw Failure.noSpeech }

        let merged = Self.mergeAdjacent(turns)
        let labels = firstSeen.map { key -> SpeakerLabel in
            let seconds = merged.filter { $0.speakerKey == key }.reduce(0) { $0 + ($1.end - $1.start) }
            return SpeakerLabel(
                key: key,
                name: key,
                centroid: SpeakerAssignment.centroid(of: embeddings[key] ?? []),
                seconds: seconds
            )
        }
        return SpeakerIdentification(turns: merged, labels: labels)
    }

    /// Voice embedding of a clip of one person (16 kHz mono).
    ///
    /// The clip is cut into 10 s windows; windows are embedded one by one and
    /// averaged. Anything shorter than 10 s is loop padded by the extractor.
    public func embedding(of samples: [Float]) throws -> [Float] {
        let models = try loadedModels()
        let manager = DiarizerManager()
        manager.initialize(models: models)
        defer { manager.cleanup() }

        guard samples.count >= Self.sampleRate else { throw Failure.noSpeech }
        var windows: [(embedding: [Float], weight: Float)] = []
        var offset = 0
        while offset < samples.count {
            let end = min(offset + Self.windowSamples, samples.count)
            let window = Array(samples[offset..<end])
            // Skip a short tail; a 2 s scrap would be loop padded five times over.
            if window.count >= Self.windowSamples / 2 || windows.isEmpty {
                do {
                    let vector = try manager.extractSpeakerEmbedding(from: window)
                    windows.append((vector, Float(window.count)))
                } catch {
                    throw Failure.processing(error.localizedDescription)
                }
            }
            offset = end
        }
        let centroid = SpeakerAssignment.centroid(of: windows)
        guard !centroid.isEmpty else { throw Failure.noSpeech }
        return centroid
    }

    // MARK: - Helpers

    /// Joins back-to-back turns of the same speaker.
    nonisolated static func mergeAdjacent(_ turns: [SpeakerTurn], gap: TimeInterval = 0.3) -> [SpeakerTurn] {
        var result: [SpeakerTurn] = []
        for turn in turns.sorted(by: { $0.start < $1.start }) {
            if var last = result.last, last.speakerKey == turn.speakerKey, turn.start - last.end <= gap {
                last.end = max(last.end, turn.end)
                result[result.count - 1] = last
            } else {
                result.append(turn)
            }
        }
        return result
    }

    nonisolated private static func duration(of url: URL) -> Double {
        guard let file = try? AVAudioFile(forReading: url), file.processingFormat.sampleRate > 0 else { return 0 }
        return Double(file.length) / file.processingFormat.sampleRate
    }
}
