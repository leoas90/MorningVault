import AVFoundation
import Foundation
import Speech

/// Fallback transcription: reads a finished recording back on the device when
/// live transcription was not available.
///
/// Uses `SFSpeechRecognizer` with on-device recognition forced on, and works
/// through the recording in chunks so long meetings stay manageable.
public enum FileTranscriptionService {
    /// Sample rate the recogniser is happiest with.
    public static let recognitionSampleRate = 16_000.0

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
        guard let recognizer = SFSpeechRecognizer(locale: locale), recognizer.isAvailable else {
            throw Failure.recognizerUnavailable
        }
        guard recognizer.supportsOnDeviceRecognition else { throw Failure.onDeviceUnavailable }

        let buffers = try readBuffers(from: fileURL)
        guard !buffers.isEmpty else { throw Failure.unreadableFile("the recording is empty") }

        var texts: [String] = []
        var pieces: [TranscriptPiece] = []
        var chunk: [AVAudioPCMBuffer] = []
        var chunkSeconds: TimeInterval = 0
        var chunkStart: TimeInterval = 0
        var elapsed: TimeInterval = 0

        for buffer in buffers {
            chunk.append(buffer)
            chunkSeconds += buffer.durationSeconds
            elapsed += buffer.durationSeconds
            if chunkSeconds >= chunkDuration {
                let recognized = try await recognize(buffers: chunk, recognizer: recognizer, offset: chunkStart)
                if !recognized.text.isEmpty { texts.append(recognized.text) }
                pieces.append(contentsOf: recognized.pieces)
                chunk.removeAll(keepingCapacity: true)
                chunkSeconds = 0
                chunkStart = elapsed
            }
        }

        if !chunk.isEmpty {
            let recognized = try await recognize(buffers: chunk, recognizer: recognizer, offset: chunkStart)
            if !recognized.text.isEmpty { texts.append(recognized.text) }
            pieces.append(contentsOf: recognized.pieces)
        }

        return Result(text: texts.joined(separator: "\n"), pieces: pieces)
    }

    /// Groups recognised words into pieces: a new piece starts after a pause
    /// longer than `pause` seconds or once `maxWords` words are in it.
    static func pieces(
        from words: [(text: String, start: TimeInterval, duration: TimeInterval)],
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

    /// Reads the recording and returns mono PCM at the recognition sample rate.
    private static func readBuffers(from url: URL) throws -> [AVAudioPCMBuffer] {
        let file: AVAudioFile
        do {
            file = try AVAudioFile(forReading: url)
        } catch {
            throw Failure.unreadableFile(error.localizedDescription)
        }

        let sourceFormat = file.processingFormat
        guard sourceFormat.sampleRate > 0, sourceFormat.channelCount > 0 else {
            throw Failure.unreadableFile("the recording has an empty audio format")
        }
        guard let targetFormat = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: recognitionSampleRate,
            channels: 1,
            interleaved: false
        ) else {
            throw Failure.conversionFailed("no usable output format")
        }

        let capacity: AVAudioFrameCount = 4096
        guard let readBuffer = AVAudioPCMBuffer(pcmFormat: sourceFormat, frameCapacity: capacity) else {
            throw Failure.conversionFailed("no usable read buffer")
        }

        var results: [AVAudioPCMBuffer] = []
        while true {
            readBuffer.frameLength = 0
            do {
                try file.read(into: readBuffer, frameCount: capacity)
            } catch {
                throw Failure.unreadableFile(error.localizedDescription)
            }
            if readBuffer.frameLength == 0 { break }

            if sourceFormat.sampleRate == targetFormat.sampleRate && sourceFormat.channelCount == targetFormat.channelCount {
                results.append(try copy(buffer: readBuffer, format: sourceFormat))
            } else {
                results.append(contentsOf: try convert(buffer: readBuffer, from: sourceFormat, to: targetFormat))
            }
        }
        return results
    }

    private static func copy(buffer: AVAudioPCMBuffer, format: AVAudioFormat) throws -> AVAudioPCMBuffer {
        guard let copy = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: buffer.frameLength) else {
            throw Failure.conversionFailed("no usable copy buffer")
        }
        copy.frameLength = buffer.frameLength
        let frames = Int(buffer.frameLength)
        if let source = buffer.floatChannelData?[0], let destination = copy.floatChannelData?[0] {
            destination.update(from: source, count: frames)
        }
        return copy
    }

    private static func convert(
        buffer: AVAudioPCMBuffer,
        from sourceFormat: AVAudioFormat,
        to targetFormat: AVAudioFormat
    ) throws -> [AVAudioPCMBuffer] {
        guard let converter = AVAudioConverter(from: sourceFormat, to: targetFormat) else {
            throw Failure.conversionFailed("no converter between the audio formats")
        }
        let ratio = targetFormat.sampleRate / sourceFormat.sampleRate
        let capacity = AVAudioFrameCount(Double(buffer.frameLength) * ratio) + 1024
        guard let output = AVAudioPCMBuffer(pcmFormat: targetFormat, frameCapacity: capacity) else {
            throw Failure.conversionFailed("no usable output buffer")
        }

        var provided: AVAudioFrameCount = 0
        var conversionError: NSError?
        let status = converter.convert(to: output, error: &conversionError) { _, outStatus in
            if provided >= buffer.frameLength {
                outStatus.pointee = .noDataNow
                return nil
            }
            provided = buffer.frameLength
            outStatus.pointee = .haveData
            return buffer
        }

        if conversionError != nil {
            throw Failure.conversionFailed(conversionError?.localizedDescription ?? "unknown")
        }
        guard status == .haveData || status == .inputRanDry else {
            throw Failure.conversionFailed("the converter produced no audio")
        }
        guard output.frameLength > 0 else { return [] }
        return [output]
    }

    private static func recognize(
        buffers: [AVAudioPCMBuffer],
        recognizer: SFSpeechRecognizer,
        offset: TimeInterval
    ) async throws -> Result {
        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = false
        request.requiresOnDeviceRecognition = true
        request.addsPunctuation = true
        request.taskHint = .dictation

        return try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Result, Error>) in
            var settled = false
            var task: SFSpeechRecognitionTask?
            task = recognizer.recognitionTask(with: request) { result, error in
                guard !settled else { return }
                if let error {
                    settled = true
                    task?.cancel()
                    continuation.resume(throwing: error)
                    return
                }
                if let result, result.isFinal {
                    settled = true
                    task?.cancel()
                    let transcription = result.bestTranscription
                    let words = transcription.segments.map { segment in
                        (text: segment.substring, start: segment.timestamp, duration: segment.duration)
                    }
                    var pieces = Self.pieces(from: words, offset: offset)
                    if pieces.isEmpty, !transcription.formattedString.isEmpty {
                        pieces = [TranscriptPiece(text: transcription.formattedString, start: offset, end: offset)]
                    }
                    continuation.resume(returning: Result(text: transcription.formattedString, pieces: pieces))
                }
            }
            for buffer in buffers {
                request.append(buffer)
            }
            request.endAudio()
        }
    }
}

private extension AVAudioPCMBuffer {
    /// Length of the buffer in seconds.
    var durationSeconds: TimeInterval {
        guard format.sampleRate > 0 else { return 0 }
        return Double(frameLength) / format.sampleRate
    }
}
