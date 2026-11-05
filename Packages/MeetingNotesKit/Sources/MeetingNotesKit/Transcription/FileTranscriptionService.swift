import AVFoundation
import Foundation
import Speech

/// Fallback transcription: reads a finished recording back on the device when
/// live transcription was not available.
///
/// Uses `SFSpeechRecognizer` with on-device recognition forced on. The file is
/// streamed block by block into the recogniser (never held whole in memory)
/// and worked through in chunks so long meetings stay manageable.
public enum FileTranscriptionService {
    /// Sample rate the recogniser is happiest with.
    public static let recognitionSampleRate = 16_000.0

    /// Frames read from the file per block (about a quarter second at 16 kHz).
    static let blockFrames: AVAudioFrameCount = 4096

    public enum Failure: LocalizedError, Sendable {
        case notAuthorized
        case recognizerUnavailable
        case onDeviceUnavailable
        case unreadableFile(String)
        case conversionFailed(String)

        public var errorDescription: String? {
            switch self {
            case .notAuthorized:
                return "Speech recognition permission was not granted."
            case .recognizerUnavailable:
                return "Speech recognition is not available for this language."
            case .onDeviceUnavailable:
                return "On-device recognition is not available for this language."
            case .unreadableFile(let reason):
                return "Could not read the recording: \(reason)"
            case .conversionFailed(let reason):
                return "Could not prepare the audio for recognition: \(reason)"
            }
        }
    }

    /// What file transcription produces: the text and its timed pieces.
    public struct Result: Sendable {
        public var text: String
        public var pieces: [TranscriptPiece]

        public init(text: String, pieces: [TranscriptPiece]) {
            self.text = text
            self.pieces = pieces
        }
    }

    /// Transcribes the recording at `fileURL` and returns the full text.
    public static func transcribe(
        fileURL: URL,
        locale: Locale = Locale.current,
        chunkDuration: TimeInterval = 60
    ) async throws -> String {
        try await transcribeWithTiming(fileURL: fileURL, locale: locale, chunkDuration: chunkDuration).text
    }

    /// Transcribes the recording at `fileURL` and keeps where each piece sits
    /// in the recording.
    public static func transcribeWithTiming(
        fileURL: URL,
        locale: Locale = Locale.current,
        chunkDuration: TimeInterval = 60
    ) async throws -> Result {
        guard await isAuthorized() else { throw Failure.notAuthorized }
        // Checked up front so an unsupported language fails before the user
        // waits for the whole file to be read. The requirement itself is set
        // on every request below, so nothing can fall back to a server.
        guard let probe = SFSpeechRecognizer(locale: locale), probe.isAvailable else {
            throw Failure.recognizerUnavailable
        }
        guard probe.supportsOnDeviceRecognition else { throw Failure.onDeviceUnavailable }

        let worker = FileRecognizer(locale: locale)
        return try await worker.transcribe(fileURL: fileURL, chunkDuration: chunkDuration)
    }

    /// Groups recognised words into pieces: a new piece starts after a pause
    /// longer than `pause` seconds or once `maxWords` words are in it.
    static func pieces(
        from words: [RecognizedWord],
        offset: TimeInterval,
        pause: TimeInterval = 0.8,
        maxWords: Int = 24
    ) -> [TranscriptPiece] {
        var result: [TranscriptPiece] = []
        var current: [String] = []
        var currentStart: TimeInterval = 0
        var currentEnd: TimeInterval = 0

        func close() {
            guard !current.isEmpty else { return }
            result.append(TranscriptPiece(
                text: current.joined(separator: " "),
                start: currentStart + offset,
                end: currentEnd + offset
            ))
            current = []
        }

        for word in words {
            let text = word.text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { continue }
            if !current.isEmpty, word.start - currentEnd > pause || current.count >= maxWords {
                close()
            }
            if current.isEmpty { currentStart = word.start }
            current.append(text)
            currentEnd = max(currentEnd, word.start + word.duration)
        }
        close()
        return result
    }

    /// One recognised word with its place in the chunk.
    struct RecognizedWord: Sendable {
        var text: String
        var start: TimeInterval
        var duration: TimeInterval
    }

    /// Asks for speech recognition permission when it has not been decided yet.
    public static func isAuthorized() async -> Bool {
        switch SFSpeechRecognizer.authorizationStatus() {
        case .authorized:
            return true
        case .notDetermined:
            return await withCheckedContinuation { continuation in
                SFSpeechRecognizer.requestAuthorization { status in
                    continuation.resume(returning: status == .authorized)
                }
            }
        default:
            return false
        }
    }
}

// MARK: - Recognition worker

/// Owns everything that is not `Sendable` during one file transcription: the
/// recogniser, the open file, the converter, the current request and task, and
/// the continuation waiting for a result.
///
/// The Speech framework calls its result handler on its own queue. The handler
/// only extracts plain values and hops back into the actor; the actor settles
/// the continuation exactly once, because its isolation makes "is there still
/// a continuation?" an atomic question.
private actor FileRecognizer {
    typealias Result = FileTranscriptionService.Result
    typealias Failure = FileTranscriptionService.Failure
    typealias RecognizedWord = FileTranscriptionService.RecognizedWord

    private let locale: Locale
    private var recognizer: SFSpeechRecognizer?
    private var task: SFSpeechRecognitionTask?
    private var continuation: CheckedContinuation<Result, Error>?
    private var currentOffset: TimeInterval = 0

    init(locale: Locale) {
        self.locale = locale
    }

    /// Reads the file in blocks, feeding each chunk of `chunkDuration` seconds
    /// to its own recognition request as it goes.
    func transcribe(fileURL: URL, chunkDuration: TimeInterval) async throws -> Result {
        guard let recognizer = SFSpeechRecognizer(locale: locale), recognizer.isAvailable else {
            throw Failure.recognizerUnavailable
        }
        guard recognizer.supportsOnDeviceRecognition else { throw Failure.onDeviceUnavailable }
        self.recognizer = recognizer

        let reader = try BlockReader(url: fileURL)
        var texts: [String] = []
        var pieces: [TranscriptPiece] = []
        var request: SFSpeechAudioBufferRecognitionRequest?
        var chunkSeconds: TimeInterval = 0
        var chunkStart: TimeInterval = 0
        var elapsed: TimeInterval = 0
        var sawAudio = false

        while let block = try reader.next() {
            try Task.checkCancellation()
            sawAudio = true
            if request == nil {
                request = Self.makeRequest()
            }
            request?.append(block)
            let seconds = block.durationSeconds
            chunkSeconds += seconds
            elapsed += seconds

            if chunkSeconds >= chunkDuration, let open = request {
                let recognized = try await recognize(request: open, offset: chunkStart)
                if !recognized.text.isEmpty { texts.append(recognized.text) }
                pieces.append(contentsOf: recognized.pieces)
                request = nil
                chunkSeconds = 0
                chunkStart = elapsed
            }
        }
        guard sawAudio else { throw Failure.unreadableFile("the recording is empty") }

        if let open = request {
            let recognized = try await recognize(request: open, offset: chunkStart)
            if !recognized.text.isEmpty { texts.append(recognized.text) }
            pieces.append(contentsOf: recognized.pieces)
        }
        return Result(text: texts.joined(separator: "\n"), pieces: pieces)
    }

    private static func makeRequest() -> SFSpeechAudioBufferRecognitionRequest {
        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = false
        request.requiresOnDeviceRecognition = true
        request.addsPunctuation = true
        request.taskHint = .dictation
        return request
    }

    /// Ends the audio of `request` and waits for its one final result.
    private func recognize(request: SFSpeechAudioBufferRecognitionRequest, offset: TimeInterval) async throws -> Result {
        guard let recognizer else { throw Failure.recognizerUnavailable }
        currentOffset = offset
        return try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation
            self.task = recognizer.recognitionTask(with: request) { [weak self] result, error in
                // Arbitrary thread. Take only plain values across.
                let payload = result.map(Payload.init)
                let failure = error
                Task { await self?.settle(payload: payload, error: failure) }
            }
            request.endAudio()
        }
    }

    /// Resumes the waiting continuation once. Later callbacks are ignored.
    private func settle(payload: Payload?, error: Error?) {
        guard let continuation else { return }
        if let error {
            self.continuation = nil
            task?.cancel()
            task = nil
            continuation.resume(throwing: error)
            return
        }
        guard let payload, payload.isFinal else { return }
        self.continuation = nil
        task?.cancel()
        task = nil
        var pieces = FileTranscriptionService.pieces(from: payload.words, offset: currentOffset)
        if pieces.isEmpty, !payload.text.isEmpty {
            pieces = [TranscriptPiece(text: payload.text, start: currentOffset, end: currentOffset)]
        }
        continuation.resume(returning: Result(text: payload.text, pieces: pieces))
    }

    /// The `Sendable` part of an `SFSpeechRecognitionResult`.
    private struct Payload: Sendable {
        var isFinal: Bool
        var text: String
        var words: [RecognizedWord]

        init(_ result: SFSpeechRecognitionResult) {
            isFinal = result.isFinal
            let transcription = result.bestTranscription
            text = transcription.formattedString
            words = transcription.segments.map {
                RecognizedWord(text: $0.substring, start: $0.timestamp, duration: $0.duration)
            }
        }
    }
}

// MARK: - Block reader

/// Reads a recording one block at a time as mono float at the recognition
/// sample rate. Only one block is alive at once.
private final class BlockReader {
    typealias Failure = FileTranscriptionService.Failure

    private let file: AVAudioFile
    private let sourceFormat: AVAudioFormat
    private let targetFormat: AVAudioFormat
    private let readBuffer: AVAudioPCMBuffer
    private let converter: AVAudioConverter?
    private let capacity = FileTranscriptionService.blockFrames

    init(url: URL) throws {
        do {
            file = try AVAudioFile(forReading: url)
        } catch {
            throw Failure.unreadableFile(error.localizedDescription)
        }
        sourceFormat = file.processingFormat
        guard sourceFormat.sampleRate > 0, sourceFormat.channelCount > 0 else {
            throw Failure.unreadableFile("the recording has an empty audio format")
        }
        guard let target = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: FileTranscriptionService.recognitionSampleRate,
            channels: 1,
            interleaved: false
        ) else {
            throw Failure.conversionFailed("no usable output format")
        }
        targetFormat = target
        guard let buffer = AVAudioPCMBuffer(pcmFormat: sourceFormat, frameCapacity: capacity) else {
            throw Failure.conversionFailed("no usable read buffer")
        }
        readBuffer = buffer
        if sourceFormat.sampleRate == target.sampleRate, sourceFormat.channelCount == target.channelCount {
            converter = nil
        } else {
            guard let made = AVAudioConverter(from: sourceFormat, to: target) else {
                throw Failure.conversionFailed("no converter between the audio formats")
            }
            converter = made
        }
    }

    /// The next block, or `nil` at the end of the file. Blocks that convert to
    /// nothing (possible at the very end) are skipped.
    func next() throws -> AVAudioPCMBuffer? {
        while true {
            readBuffer.frameLength = 0
            do {
                try file.read(into: readBuffer, frameCount: capacity)
            } catch {
                throw Failure.unreadableFile(error.localizedDescription)
            }
            if readBuffer.frameLength == 0 { return nil }

            guard let converter else {
                return try copy(readBuffer)
            }
            if let converted = try convert(readBuffer, with: converter) {
                return converted
            }
        }
    }

    private func copy(_ buffer: AVAudioPCMBuffer) throws -> AVAudioPCMBuffer {
        guard let copy = AVAudioPCMBuffer(pcmFormat: sourceFormat, frameCapacity: buffer.frameLength) else {
            throw Failure.conversionFailed("no usable copy buffer")
        }
        copy.frameLength = buffer.frameLength
        let frames = Int(buffer.frameLength)
        if let source = buffer.floatChannelData?[0], let destination = copy.floatChannelData?[0] {
            destination.update(from: source, count: frames)
        }
        return copy
    }

    private func convert(_ buffer: AVAudioPCMBuffer, with converter: AVAudioConverter) throws -> AVAudioPCMBuffer? {
        let ratio = targetFormat.sampleRate / sourceFormat.sampleRate
        let outCapacity = AVAudioFrameCount(Double(buffer.frameLength) * ratio) + 1024
        guard let output = AVAudioPCMBuffer(pcmFormat: targetFormat, frameCapacity: outCapacity) else {
            throw Failure.conversionFailed("no usable output buffer")
        }

        var provided = false
        var conversionError: NSError?
        let status = converter.convert(to: output, error: &conversionError) { _, outStatus in
            if provided {
                outStatus.pointee = .noDataNow
                return nil
            }
            provided = true
            outStatus.pointee = .haveData
            return buffer
        }

        if let conversionError {
            throw Failure.conversionFailed(conversionError.localizedDescription)
        }
        guard status == .haveData || status == .inputRanDry else {
            throw Failure.conversionFailed("the converter produced no audio")
        }
        return output.frameLength > 0 ? output : nil
    }
}

private extension AVAudioPCMBuffer {
    /// Length of the buffer in seconds.
    var durationSeconds: TimeInterval {
        guard format.sampleRate > 0 else { return 0 }
        return Double(frameLength) / format.sampleRate
    }
}
