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
    /// Speech that has been finalised by the recogniser.
    @Published public private(set) var finalText: String = ""
    /// Speech that may still change, shown in lighter grey.
    @Published public private(set) var volatileText: String = ""

    /// Called on the main actor whenever the transcript changes.
    public var onUpdate: (@MainActor @Sendable (String) -> Void)?

    private var transcriber: SpeechTranscriber?
    private var analyzer: SpeechAnalyzer?
    private var feeder: (any AnalyzerInputFeeder)?
    private var continuation: AsyncStream<AnalyzerInput>.Continuation?
    private var resultsTask: Task<Void, Never>?
    private var captureFormat: AVAudioFormat?

    /// The transcript as the user should read it right now.
    public var text: String {
        let trimmedVolatile = volatileText.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmedVolatile.isEmpty { return finalText }
        if finalText.isEmpty { return trimmedVolatile }
        return finalText + " " + trimmedVolatile
    }

    /// Starts the analyser. Returns `false` when live transcription is not possible.
    @discardableResult
    public func start(locale: Locale = Locale.current) async -> Bool {
        guard transcriber == nil else { return true }
        status = .preparing

        guard SpeechTranscriber.isAvailable else {
            status = .unavailable("On-device transcription is not available on this device.")
            return false
        }

        let transcriber = SpeechTranscriber(
            locale: locale,
            transcriptionOptions: [],
            reportingOptions: [.volatileResults],
            attributeOptions: []
        )
        self.transcriber = transcriber

        let assetStatus = await AssetInventory.status(forModules: [transcriber])
        if assetStatus == .supported {
            if let request = try? await AssetInventory.assetInstallationRequest(supporting: [transcriber]) {
                try? await request.downloadAndInstall()
            }
        } else if assetStatus == .unsupported {
            status = .unavailable("The language pack for \(locale.identifier) is not supported on this device.")
            return false
        }

        do {
            feeder = try await makeFeeder(for: transcriber)
        } catch {
            status = .failed("Could not prepare the audio pipeline: \(error.localizedDescription)")
            return false
        }

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
                    let text = String(result.text.characters)
                    let range = result.range
                    await self?.apply(text: text, range: range)
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
        finalText = ""
        volatileText = ""
    }

    private func apply(text: String, range: CMTimeRange) async {
        let volatileRange = await analyzer?.volatileRange
        let isVolatile: Bool
        if let volatileRange {
            isVolatile = CMTimeCompare(range.start, volatileRange.start) >= 0
        } else {
            isVolatile = false
        }

        if isVolatile {
            volatileText = text
        } else {
            let piece = text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !piece.isEmpty else { return }
            if finalText.isEmpty {
                finalText = piece
            } else {
                finalText += " " + piece
            }
        }
        onUpdate?(self.text)
    }

    private func teardown() async {
        resultsTask?.cancel()
        resultsTask = nil
        continuation?.finish()
        continuation = nil
        if let analyzer {
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
