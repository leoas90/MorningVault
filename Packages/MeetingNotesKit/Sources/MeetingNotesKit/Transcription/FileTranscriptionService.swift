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

    /// Transcribes the recording at `fileURL` and returns the full text.
    public static func transcribe(
        fileURL: URL,
        locale: Locale = Locale.current,
        chunkDuration: TimeInterval = 60
    ) async throws -> String {
        guard await isAuthorized() else { throw Failure.notAuthorized }
        guard let recognizer = SFSpeechRecognizer(locale: locale), recognizer.isAvailable else {
            throw Failure.recognizerUnavailable
        }
        guard recognizer.supportsOnDeviceRecognition else { throw Failure.onDeviceUnavailable }

        let buffers = try readBuffers(from: fileURL)
        guard !buffers.isEmpty else { throw Failure.unreadableFile("the recording is empty") }

        var pieces: [String] = []
        var chunk: [AVAudioPCMBuffer] = []
        var chunkSeconds: TimeInterval = 0

        for buffer in buffers {
            chunk.append(buffer)
            chunkSeconds += buffer.durationSeconds
            if chunkSeconds >= chunkDuration {
                let text = try await recognize(buffers: chunk, recognizer: recognizer)
                if !text.isEmpty { pieces.append(text) }
                chunk.removeAll(keepingCapacity: true)
                chunkSeconds = 0
            }
        }

        if !chunk.isEmpty {
            let text = try await recognize(buffers: chunk, recognizer: recognizer)
            if !text.isEmpty { pieces.append(text) }
        }

        return pieces.joined(separator: "\n")
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

    private static func recognize(buffers: [AVAudioPCMBuffer], recognizer: SFSpeechRecognizer) async throws -> String {
        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = false
        request.requiresOnDeviceRecognition = true
        request.addsPunctuation = true
        request.taskHint = .dictation

        return try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<String, Error>) in
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
                    continuation.resume(returning: result.bestTranscription.formattedString)
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
