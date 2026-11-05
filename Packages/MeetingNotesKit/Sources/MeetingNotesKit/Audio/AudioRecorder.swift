import AVFoundation
import Foundation

/// Errors surfaced by the recorder.
public enum RecorderError: LocalizedError, Sendable {
    case noInputAvailable
    case couldNotCreateFile(String)

    public var errorDescription: String? {
        switch self {
        case .noInputAvailable:
            return "No microphone is available on this device."
        case .couldNotCreateFile(let reason):
            return "Could not create the recording file: \(reason)"
        }
    }
}

/// A block of mono audio handed from the capture tap to the transcriber.
public struct AudioChunk: Sendable {
    public let samples: [Float]
    public let sampleRate: Double

    public init(samples: [Float], sampleRate: Double) {
        self.samples = samples
        self.sampleRate = sampleRate
    }
}

/// Writes AAC audio into an `.m4a` file.
///
/// The writer lives in an actor so the capture tap never touches the file
/// system directly: it hands plain samples over and the actor does the writing.
actor AudioFileSink {
    private var file: AVAudioFile?
    private var targetFormat: AVAudioFormat?

    func begin(url: URL, sampleRate: Double) throws {
        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVSampleRateKey: sampleRate,
            AVNumberOfChannelsKey: 1,
            AVEncoderBitRateKey: 96000,
            AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue
        ]
        do {
            let newFile = try AVAudioFile(
                forWriting: url,
                settings: settings,
                commonFormat: .pcmFormatFloat32,
                interleaved: false
            )
            file = newFile
            targetFormat = newFile.processingFormat
        } catch {
            throw RecorderError.couldNotCreateFile(error.localizedDescription)
        }
    }

    func append(samples: [Float]) {
        guard let file, let targetFormat else { return }
        let frames = samples.count
        guard frames > 0 else { return }
        guard let buffer = AVAudioPCMBuffer(
            pcmFormat: targetFormat,
            frameCapacity: AVAudioFrameCount(frames)
        ) else { return }
        buffer.frameLength = AVAudioFrameCount(frames)
        if let channel = buffer.floatChannelData?[0] {
            samples.withUnsafeBufferPointer { pointer in
                guard let base = pointer.baseAddress else { return }
                channel.update(from: base, count: frames)
            }
        }
        try? file.write(from: buffer)
    }

    func finish() {
        file = nil
        targetFormat = nil
    }
}

/// Records mono audio from the microphone into an `.m4a` file while the app runs.
@MainActor
public final class AudioRecorder: ObservableObject {
    public enum State: Equatable, Sendable {
        case idle
        case recording
        case paused
        case failed(String)
    }

    @Published public private(set) var state: State = .idle
    @Published public private(set) var elapsed: TimeInterval = 0
    /// Smoothed microphone level between 0 and 1.
    @Published public private(set) var level: Double = 0
    /// Short message shown as a banner, for example after a phone call.
    @Published public private(set) var banner: String?

    /// Called on the main actor for every captured block of audio.
    public var onChunk: (@MainActor @Sendable (AudioChunk) -> Void)?
    /// Called on the main actor whenever the microphone level changes.
    public var onLevel: (@MainActor @Sendable (Double) -> Void)?
    /// Called on the main actor whenever the elapsed time changes.
    public var onElapsed: (@MainActor @Sendable (TimeInterval) -> Void)?
    /// Called on the main actor when a banner message appears or disappears.
    public var onBanner: (@MainActor @Sendable (String?) -> Void)?

    public private(set) var recordingURL: URL?

    private let engine = AVAudioEngine()
    private let sink = AudioFileSink()
    private var ticker: Task<Void, Never>?
    private var startedAt: Date?
    private var pausedAt: Date?
    private var accumulated: TimeInterval = 0
    private var interruptionObserver: NSObjectProtocol?
    private var routeObserver: NSObjectProtocol?

    public init() {
        installObservers()
    }

    isolated deinit {
        if let interruptionObserver {
            NotificationCenter.default.removeObserver(interruptionObserver)
        }
        if let routeObserver {
            NotificationCenter.default.removeObserver(routeObserver)
        }
    }

    /// True while audio is being captured.
    public var isRecording: Bool {
        state == .recording || state == .paused
    }

    /// Starts capture. The file lands in Application Support/Meetings/<id>/.
    public func start(meetingID: UUID) async throws {
        guard !isRecording else { return }

        #if os(iOS)
        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker, .allowBluetoothHFP])
            try session.setActive(true)
        } catch {
            throw RecorderError.couldNotCreateFile(error.localizedDescription)
        }
        #endif

        let input = engine.inputNode
        let hardwareFormat = input.outputFormat(forBus: 0)
        guard hardwareFormat.sampleRate > 0, hardwareFormat.channelCount > 0 else {
            throw RecorderError.noInputAvailable
        }

        let captureFormat = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: hardwareFormat.sampleRate,
            channels: 1,
            interleaved: false
        )

        let url = MeetingNotesStore.audioURL(for: meetingID)
        try await sink.begin(url: url, sampleRate: hardwareFormat.sampleRate)

        input.installTap(onBus: 0, bufferSize: 4096, format: captureFormat) { [weak self] buffer, _ in
            guard let self else { return }
            guard let channel = buffer.floatChannelData?[0] else { return }
            let frames = Int(buffer.frameLength)
            guard frames > 0 else { return }

            var samples = [Float](repeating: 0, count: frames)
            samples.withUnsafeMutableBufferPointer { destination in
                guard let base = destination.baseAddress else { return }
                base.update(from: channel, count: frames)
            }

            var sum: Float = 0
            for sample in samples { sum += sample * sample }
            let rms = (sum / Float(frames)).squareRoot()
            let normalised = max(0, min(1, Double((rms - 0.004) * 14)))
            let rate = buffer.format.sampleRate

            Task { @MainActor in
                self.handle(samples: samples, sampleRate: rate, level: normalised)
            }
        }

        engine.prepare()
        do {
            try engine.start()
        } catch {
            input.removeTap(onBus: 0)
            throw RecorderError.couldNotCreateFile(error.localizedDescription)
        }

        recordingURL = url
        accumulated = 0
        elapsed = 0
        startedAt = Date()
        state = .recording
        startTicker()
    }

    /// Pauses capture, keeping the recording file intact.
    public func pause() {
        guard state == .recording else { return }
        engine.pause()
        pausedAt = Date()
        state = .paused
        banner = "Recording paused."
        onBanner?(banner)
    }

    /// Resumes a paused recording.
    public func resume() {
        guard state == .paused else { return }
        do {
            try engine.start()
            if let pausedAt {
                accumulated += Date().timeIntervalSince(pausedAt)
                self.pausedAt = nil
            }
            state = .recording
            banner = nil
            onBanner?(nil)
        } catch {
            banner = "Could not resume recording: \(error.localizedDescription)"
            onBanner?(banner)
        }
    }

    /// Stops capture and finalises the `.m4a` file.
    public func stop() async -> TimeInterval {
        guard isRecording else { return elapsed }
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        await sink.finish()

        if let startedAt {
            let end = Date()
            accumulated += end.timeIntervalSince(startedAt)
            self.startedAt = nil
        }
        pausedAt = nil
        stopTicker()

        #if os(iOS)
        try? AVAudioSession.sharedInstance().setActive(false, options: [.notifyOthersOnDeactivation])
        #endif

        state = .idle
        elapsed = accumulated
        return accumulated
    }

    /// Discards the current recording and deletes the file.
    public func cancel() async {
        _ = await stop()
        if let recordingURL {
            try? FileManager.default.removeItem(at: recordingURL)
        }
        recordingURL = nil
        accumulated = 0
        elapsed = 0
    }

    /// Clears the banner message.
    public func clearBanner() {
        banner = nil
        onBanner?(nil)
    }

    private func handle(samples: [Float], sampleRate: Double, level: Double) {
        self.level = level
        onLevel?(level)
        onChunk?(AudioChunk(samples: samples, sampleRate: sampleRate))
    }

    private func startTicker() {
        ticker?.cancel()
        ticker = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(100))
                guard let self else { return }
                if self.state == .recording, let startedAt = self.startedAt {
                    self.elapsed = self.accumulated + Date().timeIntervalSince(startedAt)
                    self.onElapsed?(self.elapsed)
                }
            }
        }
    }

    private func stopTicker() {
        ticker?.cancel()
        ticker = nil
    }

    private func installObservers() {
        #if os(iOS)
        interruptionObserver = NotificationCenter.default.addObserver(
            forName: AVAudioSession.interruptionNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            let userInfo = notification.userInfo ?? [:]
            let rawType = userInfo[AVAudioSessionInterruptionTypeKey] as? UInt
            let rawOptions = userInfo[AVAudioSessionInterruptionOptionKey] as? UInt
            let type = rawType.flatMap { AVAudioSession.InterruptionType(rawValue: $0) }
            let options = rawOptions.flatMap { AVAudioSession.InterruptionOptions(rawValue: $0) }
            Task { @MainActor in
                self?.handleInterruption(type: type, options: options)
            }
        }

        routeObserver = NotificationCenter.default.addObserver(
            forName: AVAudioSession.routeChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            let userInfo = notification.userInfo ?? [:]
            let rawReason = userInfo[AVAudioSessionRouteChangeReasonKey] as? UInt
            let reason = rawReason.flatMap { AVAudioSession.RouteChangeReason(rawValue: $0) }
            Task { @MainActor in
                guard let self, let reason else { return }
                if reason == .oldDeviceUnavailable {
                    self.banner = "Headphones were unplugged. Recording continues with the built-in microphone."
                    self.onBanner?(self.banner)
                }
            }
        }
        #endif
    }

    #if os(iOS)
    private func handleInterruption(
        type: AVAudioSession.InterruptionType?,
        options: AVAudioSession.InterruptionOptions?
    ) {
        switch type {
        case .began:
            if state == .recording {
                pause()
                banner = "Paused because of a phone call or another interruption."
                onBanner?(banner)
            }
        case .ended:
            if options?.contains(.shouldResume) == true {
                resume()
            } else {
                banner = "Recording stayed paused after the interruption."
                onBanner?(banner)
            }
        default:
            break
        }
    }
    #endif
}
