import AVFoundation
import Speech

/// Turns captured audio buffers into input the speech analyser understands.
protocol AnalyzerInputFeeder: AnyObject {
    /// Converts a captured buffer into analyser input.
    func inputs(from buffer: AVAudioPCMBuffer) throws -> [AnalyzerInput]
}

/// Uses the system converter, so the buffer matches the speech module exactly.
///
/// Only available from iOS 27 / macOS 27, where Apple ships `AnalyzerInputConverter`.
@available(iOS 27.0, macOS 27.0, *)
final class SystemConverterFeeder: AnalyzerInputFeeder {
    private let converter: AnalyzerInputConverter

    init(converter: AnalyzerInputConverter) {
        self.converter = converter
    }

    func inputs(from buffer: AVAudioPCMBuffer) throws -> [AnalyzerInput] {
        try converter.convert(buffer, at: nil)
    }
}

/// Resamples the captured audio to a format the speech module accepts.
///
/// This is the path used on iOS 26, where the system converter does not exist yet.
final class ResampledFeeder: AnalyzerInputFeeder {
    private let outputFormat: AVAudioFormat
    private var converter: AVAudioConverter?
    private var inputFormat: AVAudioFormat?

    /// - Parameter outputFormat: a format the speech module accepts.
    init(outputFormat: AVAudioFormat) {
        self.outputFormat = outputFormat
    }

    func inputs(from buffer: AVAudioPCMBuffer) throws -> [AnalyzerInput] {
        if converter == nil || inputFormat != buffer.format {
            inputFormat = buffer.format
            converter = AVAudioConverter(from: buffer.format, to: outputFormat)
        }
        guard let converter else { return [] }

        let ratio = outputFormat.sampleRate / buffer.format.sampleRate
        let capacity = AVAudioFrameCount(Double(buffer.frameLength) * ratio) + 2_048
        guard let output = AVAudioPCMBuffer(pcmFormat: outputFormat, frameCapacity: capacity) else {
            return []
        }

        var supplied = false
        var conversionError: NSError?
        let status = converter.convert(to: output, error: &conversionError, withInputFrom: { _, inputStatus in
            if supplied {
                inputStatus.pointee = .noDataNow
                return nil
            }
            supplied = true
            return buffer
        })

        guard status != .error, conversionError == nil, output.frameLength > 0 else { return [] }
        return [AnalyzerInput(buffer: output)]
    }
}
