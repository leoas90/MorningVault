import AVFoundation
import XCTest
@testable import MeetingNotesKit

final class AudioRecorderMixingTests: XCTestCase {
    private func buffer(channels: AVAudioChannelCount, interleaved: Bool, frames: [[Float]]) -> AVAudioPCMBuffer {
        let format = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: 48_000,
            channels: channels,
            interleaved: interleaved
        )!
        let count = frames[0].count
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(count))!
        buffer.frameLength = AVAudioFrameCount(count)
        let data = buffer.floatChannelData!
        if interleaved {
            for frame in 0..<count {
                for channel in 0..<Int(channels) {
                    data[0][frame * Int(channels) + channel] = frames[channel][frame]
                }
            }
        } else {
            for channel in 0..<Int(channels) {
                for frame in 0..<count {
                    data[channel][frame] = frames[channel][frame]
                }
            }
        }
        return buffer
    }

    func testMonoBufferPassesThrough() {
        let samples = AudioRecorder.monoSamples(from: buffer(channels: 1, interleaved: false, frames: [[0.1, 0.2, 0.3]]))
        XCTAssertEqual(samples, [0.1, 0.2, 0.3])
    }

    func testStereoNonInterleavedIsAveraged() {
        let samples = AudioRecorder.monoSamples(
            from: buffer(channels: 2, interleaved: false, frames: [[1, 0, 0.5], [0, 1, 0.5]])
        )
        XCTAssertEqual(samples, [0.5, 0.5, 0.5])
    }

    func testStereoInterleavedIsAveraged() {
        let samples = AudioRecorder.monoSamples(
            from: buffer(channels: 2, interleaved: true, frames: [[1, 0], [0, 1]])
        )
        XCTAssertEqual(samples, [0.5, 0.5])
    }

    func testEmptyBufferGivesNothing() {
        let format = AVAudioFormat(standardFormatWithSampleRate: 48_000, channels: 1)!
        let empty = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 16)!
        XCTAssertNil(AudioRecorder.monoSamples(from: empty))
    }

    func testLevelIsClampedToUnitRange() {
        XCTAssertEqual(AudioRecorder.level(of: []), 0)
        XCTAssertEqual(AudioRecorder.level(of: [0, 0, 0]), 0)
        XCTAssertEqual(AudioRecorder.level(of: [1, -1, 1, -1]), 1)
    }

    func testMonoBufferRoundTrips() {
        let buffer = AudioRecorder.monoBuffer(samples: [0.25, -0.25], sampleRate: 16_000)
        XCTAssertEqual(buffer?.frameLength, 2)
        XCTAssertEqual(buffer?.format.channelCount, 1)
        XCTAssertEqual(buffer?.format.sampleRate, 16_000)
        XCTAssertEqual(buffer.flatMap { AudioRecorder.monoSamples(from: $0) }, [0.25, -0.25])
        XCTAssertNil(AudioRecorder.monoBuffer(samples: [], sampleRate: 16_000))
    }
}
