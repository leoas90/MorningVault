import AVFoundation
import Foundation
import Speech

/// Live, on-device transcription while the user is recording.
///
/// Uses the modern `SpeechAnalyzer` pipeline. Everything runs on the device:
/// no audio and no text ever leaves the phone.
@MainActor
public final class LiveTranscriber: ObservableObject {
    public enum Status: Equatable, Sendable {
        case idle
        case preparing
        case listening
        case unavailable(String)
        case failed(String)
    }

    @Published public private(set) var status: Status = .idle
    /// Finalised and volatile text, kept apart so a final result can replace
    /// the draft it supersedes instead of being shown twice.
    @Published private var assembler = TranscriptAssembler()

    /// Speech that has been finalised by the recogniser.
    public var finalText: String { assembler.finalText }
    /// Speech that may still change, shown in lighter grey.
    public var volatileText: String { assembler.volatileText }

    /// Called on the main actor whenever the transcript changes, with the
    /// finalised text first and the part that may still change second.
    public var onUpdate: (@MainActor @Sendable (String, String) -> Void)?
    /// Called on the main actor for every finalised piece of speech with its
    /// position in the recording, so speakers can be matched to it later.
    public var onPiece: (@MainActor @Sendable (TranscriptPiece) -> Void)?

    private var transcriber: SpeechTranscriber?
    private var analyzer: SpeechAnalyzer?
    private var feeder: (any AnalyzerInputFeeder)?
    private var continuation: AsyncStream<AnalyzerInput>.Continuation?
    private var resultsTask: Task<Void, Never>?
    private var captureFormat: AVAudioFormat?

    /// The transcript as the user should read it right now.
    public var text: String { assembler.text }

    /// Why live transcription is off, when it is.
    public var unavailableReason: String? {
        switch status {
        case .unavailable(let message), .failed(let message): return message
        case .idle, .preparing, .listening: return nil
        }
    }

    /// Starts the analyser. Returns `false` when live transcription is not possible.
    ///
    /// Safe to cancel: the language pack download and the analyser start both
    /// stop cleanly, and a cancelled start reports `false`.
    @discardableResult
    public func start(locale: Locale = Locale.current) async -> Bool {
        guard transcriber == nil else { return true }
        status = .preparing

        guard SpeechTranscriber.isAvailable else {
            status = .unavailable("On-device transcription is not available on this device.")
            return false
        }

        // SpeechAnalyzer runs fully on device, but the Speech framework still
        // honours the speech recognition switch in Settings.
        guard await RecordingPermissions.requestSpeech() else {
            status = .unavailable("Speech recognition is off in Settings.")
            return false
        }
        guard !Task.isCancelled else { status = .idle; return false }

        let transcriber = SpeechTranscriber(
            locale: locale,
            transcriptionOptions: [],
            reportingOptions: [.volatileResults],
            // Word timings: without them every piece lacks a time range, the
            // meeting is saved as one block, and speaker identification has
            // nothing to split (every word lands on one speaker).
            attributeOptions: [.audioTimeRange]
        )
        self.transcriber = transcriber

        let assetStatus = await AssetInventory.status(forModules: [transcriber])
        switch assetStatus {
        case .unsupported:
            status = .unavailable("The language pack for \(locale.identifier) is not supported on this device.")
            self.transcriber = nil
            return false
        case .installed:
            break
        default:
            // Downloading the language pack can take a while on first use. The
            // recording keeps running meanwhile; a failure here only means the
            // file is transcribed when the meeting ends.
            do {
                if let request = try await AssetInventory.assetInstallationRequest(supporting: [transcriber]) {
                    try await request.downloadAndInstall()
                }
            } catch {
                status = .failed("The language pack is not ready: \(error.localizedDescription)")
                self.transcriber = nil
                return false
            }
        }
        guard !Task.isCancelled else { await teardown(); status = .idle; return false }

        do {
            feeder = try await makeFeeder(for: transcriber)
        } catch {
            status = .failed("Could not prepare the audio pipeline: \(error.localizedDescription)")
            await teardown()
            return false
        }
        guard !Task.isCancelled else { await teardown(); status = .idle; return false }

        let stream = AsyncStream<AnalyzerInput> { continuation in
            self.continuation = continuation
        }

        let analyzer = SpeechAnalyzer(
            modules: [transcriber],
            options: .init(priority: .userInitiated, modelRetention: .whileInUse)
        )
        self.analyzer = analyzer

        do {
            try await analyzer.start(inputSequence: stream)
        } catch {
            status = .failed("Could not start transcription: \(error.localizedDescription)")
            await teardown()
            return false
        }

        let results = transcriber.results
        resultsTask = Task.detached { [weak self] in
            do {
                for try await result in results {
                    // The SDK says whether a result is settled. The analyser's
                    // `volatileRange` is its current window, not a property of
                    // this result, so it is not used to decide that.
                    let text = String(result.text.characters)
                    let range = result.range
                    let isFinal = result.isFinal
                    let words = isFinal ? Self.words(in: result.text) : []
                    await self?.apply(text: text, isFinal: isFinal, range: range, words: words)
                }
            } catch {
                // The recogniser stopped. Whatever was recognised stays on screen.
            }
        }

        status = .listening
        return true
    }

    /// Feeds captured audio into the analyser.
    public func ingest(_ chunk: AudioChunk) {
        guard let feeder, let continuation else { return }
        let frames = chunk.samples.count
        guard frames > 0 else { return }

        if captureFormat == nil || captureFormat?.sampleRate != chunk.sampleRate {
            captureFormat = AVAudioFormat(
                commonFormat: .pcmFormatFloat32,
                sampleRate: chunk.sampleRate,
                channels: 1,
                interleaved: false
            )
        }
        guard let format = captureFormat else { return }
        guard let buffer = AVAudioPCMBuffer(
            pcmFormat: format,
            frameCapacity: AVAudioFrameCount(frames)
        ) else { return }
        buffer.frameLength = AVAudioFrameCount(frames)

        if let channel = buffer.floatChannelData?[0] {
            chunk.samples.withUnsafeBufferPointer { pointer in
                guard let base = pointer.baseAddress else { return }
                channel.update(from: base, count: frames)
            }
        }

        do {
            for input in try feeder.inputs(from: buffer) {
                continuation.yield(input)
            }
        } catch {
            // A dropped buffer is not worth interrupting the recording for.
        }
    }

    /// Stops transcription and keeps whatever was recognised.
    public func stop() async {
        await teardown()
        status = .idle
    }

    /// Clears the transcript.
    public func reset() {
        assembler.reset()
    }

    private func apply(text: String, isFinal: Bool, range: CMTimeRange, words: [FileTranscriptionService.RecognizedWord]) {
        if let piece = assembler.apply(text: text, isFinal: isFinal) {
            // Prefer word-level pieces (split at pauses) so each speaker turn
            // can get its own piece; fall back to the whole result's range.
            let split = FileTranscriptionService.pieces(from: words, offset: 0)
            if !split.isEmpty {
                split.forEach { onPiece?($0) }
            } else if range.start.isNumeric, range.end.isNumeric {
                onPiece?(TranscriptPiece(
                    text: piece,
                    start: CMTimeGetSeconds(range.start),
                    end: CMTimeGetSeconds(range.end)
                ))
            }
        }
        onUpdate?(assembler.finalText, assembler.volatileText)
    }

    /// Words of a finalized result with their place in the recording, read
    /// from the `audioTimeRange` attribute. Empty when timings are missing.
    nonisolated static func words(in text: AttributedString) -> [FileTranscriptionService.RecognizedWord] {
        var words: [FileTranscriptionService.RecognizedWord] = []
        for run in text.runs {
            guard let timeRange = run.audioTimeRange,
                  timeRange.start.isNumeric, timeRange.duration.isNumeric else { continue }
            let word = String(text[run.range].characters).trimmingCharacters(in: .whitespacesAndNewlines)
            guard !word.isEmpty else { continue }
            words.append(.init(
                text: word,
                start: CMTimeGetSeconds(timeRange.start),
                duration: CMTimeGetSeconds(timeRange.duration)
            ))
        }
        return words
    }

    private func teardown() async {
        resultsTask?.cancel()
        resultsTask = nil
        continuation?.finish()
        continuation = nil
        if let analyzer {
            // Immediate stop; the volatile tail is kept by the caller as plain
            // text, so nothing the user saw disappears.
            await analyzer.cancelAndFinishNow()
        }
        analyzer = nil
        transcriber = nil
        feeder = nil
        captureFormat = nil
    }

    /// Picks the best way to hand captured audio to the analyser.
    private func makeFeeder(for transcriber: SpeechTranscriber) async throws -> any AnalyzerInputFeeder {
        if #available(iOS 27.0, macOS 27.0, *) {
            let converter = try await AnalyzerInputConverter.converter(compatibleWith: [transcriber])
            return SystemConverterFeeder(converter: converter)
        }

        let formats = await transcriber.availableCompatibleAudioFormats
        guard let format = preferredFormat(from: formats) else {
            throw CocoaError(.featureUnsupported)
        }
        return ResampledFeeder(outputFormat: format)
    }

    /// The 16 kHz mono format the speech module prefers, when it is offered.
    private func preferredFormat(from formats: [AVAudioFormat]) -> AVAudioFormat? {
        let mono = formats.filter { $0.channelCount == 1 }
        let preferred = mono.first { $0.sampleRate == 16_000 }
        return preferred ?? mono.first ?? formats.first
    }
}
