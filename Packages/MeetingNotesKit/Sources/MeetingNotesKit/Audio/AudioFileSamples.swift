import AVFoundation
import Foundation

/// Reads a recording back as 16 kHz mono samples, in blocks, so a long
/// meeting never has to sit in memory all at once.
enum AudioFileSamples {
    static let targetSampleRate = 16_000.0

    enum Failure: LocalizedError {
        case unreadable(String)
        case conversion(String)

        var errorDescription: String? {
            switch self {
            case .unreadable(let reason): return "Could not read the recording: \(reason)"
            case .conversion(let reason): return "Could not prepare the recording: \(reason)"
            }
        }
    }

    /// Calls `body` with consecutive blocks of about `blockSeconds` seconds and
    /// the block's start time in seconds. Returning `false` from `body` stops reading.
    static func read(
        url: URL,
        blockSeconds: Double,
        body: ([Float], TimeInterval) throws -> Bool
    ) throws {
        let file: AVAudioFile
        do {
            file = try AVAudioFile(forReading: url)
        } catch {
            throw Failure.unreadable(error.localizedDescription)
        }
        let sourceFormat = file.processingFormat
        guard sourceFormat.sampleRate > 0, sourceFormat.channelCount > 0 else {
            throw Failure.unreadable("the recording has an empty audio format")
        }
        guard let targetFormat = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: targetSampleRate,
            channels: 1,
            interleaved: false
        ) else {
            throw Failure.conversion("no usable output format")
        }
        let needsConversion = abs(sourceFormat.sampleRate - targetSampleRate) > 1 || sourceFormat.channelCount != 1
        var converter: AVAudioConverter?
        if needsConversion {
            guard let made = AVAudioConverter(from: sourceFormat, to: targetFormat) else {
                throw Failure.conversion("no converter between the audio formats")
            }
            converter = made
        }

        let readFrames: AVAudioFrameCount = 8_192
        guard let readBuffer = AVAudioPCMBuffer(pcmFormat: sourceFormat, frameCapacity: readFrames) else {
            throw Failure.conversion("no usable read buffer")
        }

        let blockFrames = max(1, Int(blockSeconds * targetSampleRate))
        var block: [Float] = []
        block.reserveCapacity(blockFrames)
        var emitted = 0

        func flush() throws -> Bool {
            guard !block.isEmpty else { return true }
            let start = Double(emitted) / targetSampleRate
            let keepGoing = try body(block, start)
            emitted += block.count
            block.removeAll(keepingCapacity: true)
            return keepGoing
        }

        while file.framePosition < file.length {
            readBuffer.frameLength = 0
            do {
                try file.read(into: readBuffer, frameCount: readFrames)
            } catch {
                throw Failure.unreadable(error.localizedDescription)
            }
            if readBuffer.frameLength == 0 { break }

            let samples: [Float]
            if let converter {
                guard let converted = AudioResampler.resample(readBuffer, with: converter, to: targetFormat) else {
                    continue
                }
                samples = AudioRecorder.monoSamples(from: converted) ?? []
            } else {
                samples = AudioRecorder.monoSamples(from: readBuffer) ?? []
            }
            block.append(contentsOf: samples)
            if block.count >= blockFrames {
                if try !flush() { return }
            }
        }
        _ = try flush()
    }

    /// Everything in the file, 16 kHz mono.
    static func all(url: URL) throws -> [Float] {
        var samples: [Float] = []
        try read(url: url, blockSeconds: 60) { block, _ in
            samples.append(contentsOf: block)
            return true
        }
        return samples
    }

    /// Resamples in-memory chunks captured at any rate to 16 kHz mono.
    static func resample(_ samples: [Float], from sampleRate: Double) -> [Float] {
        guard !samples.isEmpty else { return [] }
        if abs(sampleRate - targetSampleRate) < 1 { return samples }
        guard
            let input = AudioRecorder.monoBuffer(samples: samples, sampleRate: sampleRate),
            let targetFormat = AVAudioFormat(
                commonFormat: .pcmFormatFloat32,
                sampleRate: targetSampleRate,
                channels: 1,
                interleaved: false
            ),
            let converter = AVAudioConverter(from: input.format, to: targetFormat),
            let output = AudioResampler.resample(input, with: converter, to: targetFormat)
        else { return [] }
        return AudioRecorder.monoSamples(from: output) ?? []
    }
}
