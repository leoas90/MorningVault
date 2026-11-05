import AVFoundation
import Foundation
import Synchronization

/// Errors surfaced by the recorder.
public enum RecorderError: LocalizedError, Sendable, Equatable {
    case microphoneDenied
    case noInputAvailable
    case audioSessionFailed(String)
    case couldNotCreateFile(String)
    case engineFailed(String)

    public var errorDescription: String? {
        switch self {
        case .microphoneDenied:
            return "Microphone access is off. Turn it on in Settings to record meetings."
        case .noInputAvailable:
            return "No microphone is available right now. Check your audio input and try again."
        case .audioSessionFailed(let reason):
            return "The audio session could not be started: \(reason)"
        case .couldNotCreateFile(let reason):
            return "Could not create the recording file: \(reason)"
        case .engineFailed(let reason):
            return "The microphone could not be started: \(reason)"
        }
    }

    /// True when the fix lives in Settings rather than in the app.
    public var needsSettings: Bool {
        self == .microphoneDenied
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
/// Samples that arrive at a different rate (after a route change, for example)
/// are resampled so the file stays valid.
actor AudioFileSink {
    private var file: AVAudioFile?
    private var fileFormat: AVAudioFormat?
    private var converter: AVAudioConverter?
    private var converterSampleRate: Double = 0

    func begin(url: URL, sampleRate: Double) throws {
        try? FileManager.default.removeItem(at: url)
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
            fileFormat = newFile.processingFormat
        } catch {
            throw RecorderError.couldNotCreateFile(error.localizedDescription)
        }
    }

    func append(samples: [Float], sampleRate: Double) {
        guard let file, let fileFormat, !samples.isEmpty else { return }
        guard let input = AudioRecorder.monoBuffer(samples: samples, sampleRate: sampleRate) else { return }

        if abs(sampleRate - fileFormat.sampleRate) < 1 {
            try? file.write(from: input)
            return
        }

        if converter == nil || converterSampleRate != sampleRate {
            converterSampleRate = sampleRate
            converter = nil
            if let inputFormat = AVAudioFormat(
                commonFormat: .pcmFormatFloat32,
                sampleRate: sampleRate,
                channels: 1,
                interleaved: false
            ) {
                converter = AVAudioConverter(from: inputFormat, to: fileFormat)
            }
        }
        guard let converter else { return }
        guard let output = AudioResampler.resample(input, with: converter, to: fileFormat) else { return }
        try? file.write(from: output)
    }

    func finish() {
        file = nil
        fileFormat = nil
        converter = nil
        converterSampleRate = 0
    }
}

/// A handful of preallocated sample arrays shared between the capture tap and
/// the main-actor drain.
///
/// The tap takes an array, fills it and yields it; the drain gives it back once
/// the file sink and the transcriber copied what they needed. While the pool
/// has arrays the realtime thread never allocates. If a consumer still holds a
/// reference when the tap reuses an array, copy-on-write keeps it correct and
/// only that block pays for an allocation.
final class SamplePool: Sendable {
    private let slots: Mutex<[[Float]]>
    private let capacity: Int
    private let maxSlots: Int

    init(slots: Int, capacity: Int) {
        self.capacity = capacity
        self.maxSlots = slots
        var pool: [[Float]] = []
        pool.reserveCapacity(slots)
        for _ in 0..<slots {
            var array: [Float] = []
            array.reserveCapacity(capacity)
            pool.append(array)
        }
        self.slots = Mutex(pool)
    }

    /// An empty array with reserved capacity, or `nil` when the pool ran dry.
    func take() -> [Float]? {
        slots.withLock { $0.popLast() }
    }

    /// Returns `samples` to the pool. Anything beyond `slots` is dropped.
    func recycle(_ samples: [Float]) {
        var array = samples
        array.removeAll(keepingCapacity: true)
        slots.withLock { pool in
            guard pool.count < maxSlots else { return }
            pool.append(array)
        }
    }
}

/// One-shot sample rate conversion of a single buffer.
enum AudioResampler {
    static func resample(
        _ input: AVAudioPCMBuffer,
        with converter: AVAudioConverter,
        to format: AVAudioFormat
    ) -> AVAudioPCMBuffer? {
        guard input.format.sampleRate > 0 else { return nil }
        let ratio = format.sampleRate / input.format.sampleRate
        let capacity = AVAudioFrameCount(Double(input.frameLength) * ratio) + 1_024
        guard let output = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: capacity) else { return nil }

        var supplied = false
        var conversionError: NSError?
        let status = converter.convert(to: output, error: &conversionError) { _, outStatus in
            if supplied {
                outStatus.pointee = .noDataNow
                return nil
            }
            supplied = true
            outStatus.pointee = .haveData
            return input
        }
        guard status != .error, conversionError == nil, output.frameLength > 0 else { return nil }
        return output
    }
}

/// Records mono audio from the microphone into an `.m4a` file while the app runs.
///
/// Hard rules that keep this from trapping:
/// - microphone permission is requested before anything touches the engine;
/// - the tap uses the input node's own format (never a hand-built one) and the
///   kit downmixes to mono itself, so stereo, Bluetooth and USB inputs all work;
/// - a fresh `AVAudioEngine` is built for every recording so no stale input
///   format from a previous route can leak into the next session.
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

    private var engine: AVAudioEngine?
    private let sink = AudioFileSink()
    /// Sample arrays the tap writes into and the drain hands back, so the
    /// realtime thread does not allocate once the pool has warmed up.
    private let samplePool = SamplePool(slots: 8, capacity: Int(AudioRecorder.tapBufferSize))
    /// Captured chunks, in order. The tap yields here from its own thread; one
    /// main-actor task drains it so the file and the transcriber both see the
    /// audio in the order it was recorded.
    private var chunkContinuation: AsyncStream<AudioChunk>.Continuation?
    private var drainTask: Task<Void, Never>?
    private var ticker: Task<Void, Never>?
    private var startedAt: Date?
    private var pausedAt: Date?
    private var accumulated: TimeInterval = 0
    private var interruptionObserver: NSObjectProtocol?
    private var routeObserver: NSObjectProtocol?
    private var configurationObserver: NSObjectProtocol?

    public init() {
        installObservers()
    }

    isolated deinit {
        for observer in [interruptionObserver, routeObserver, configurationObserver] {
            if let observer {
                NotificationCenter.default.removeObserver(observer)
            }
        }
    }

    /// True while audio is being captured.
    public var isRecording: Bool {
        state == .recording || state == .paused
    }

    /// Starts capture. The file lands in Application Support/Meetings/<id>/.
    public func start(meetingID: UUID) async throws {
        let folder: URL
        do {
            folder = try MeetingNotesStore.ensureAudioFolder(for: meetingID)
        } catch {
            let failure = RecorderError.couldNotCreateFile(error.localizedDescription)
            state = .failed(failure.localizedDescription)
            throw failure
        }
        try await start(fileURL: folder.appendingPathComponent("recording.m4a"))
    }

    /// Starts capture into `fileURL`. Its folder must exist.
    public func start(fileURL url: URL) async throws {
        guard !isRecording else { return }

        guard await RecordingPermissions.requestMicrophone() else {
            state = .failed(RecorderError.microphoneDenied.localizedDescription)
            throw RecorderError.microphoneDenied
        }

        do {
            try activateSession()
        } catch {
            state = .failed(error.localizedDescription)
            throw error
        }

        // A brand new engine every time: the input node of a reused engine can
        // keep reporting the format of the previous route, and a mismatch
        // between that and the real hardware traps inside AVAudioEngine.
        let engine = AVAudioEngine()
        self.engine = engine
        let input = engine.inputNode

        // Read the format only now, after the session is active and permission
        // is granted. Before that it is 0 Hz / 0 channels.
        let hardwareFormat = input.outputFormat(forBus: 0)
        guard hardwareFormat.sampleRate > 0, hardwareFormat.channelCount > 0 else {
            self.engine = nil
            releaseSession()
            state = .failed(RecorderError.noInputAvailable.localizedDescription)
            throw RecorderError.noInputAvailable
        }

        do {
            try await sink.begin(url: url, sampleRate: hardwareFormat.sampleRate)
        } catch {
            self.engine = nil
            releaseSession()
            state = .failed(error.localizedDescription)
            throw error
        }

        startDraining()
        do {
            try installTap(on: input)
            engine.prepare()
            try engine.start()
        } catch {
            input.removeTap(onBus: 0)
            self.engine = nil
            stopDraining()
            await sink.finish()
            releaseSession()
            let failure = RecorderError.engineFailed(error.localizedDescription)
            state = .failed(failure.localizedDescription)
            throw failure
        }

        recordingURL = url
        accumulated = 0
        elapsed = 0
        startedAt = Date()
        pausedAt = nil
        state = .recording
        banner = nil
        startTicker()
    }

    /// Pauses capture, keeping the recording file intact.
    public func pause() {
        guard state == .recording else { return }
        engine?.pause()
        pausedAt = Date()
        state = .paused
    }

    /// Resumes a paused recording.
    public func resume() {
        guard state == .paused, let engine else { return }
        do {
            try activateSession()
            try engine.start()
            if let pausedAt {
                accumulated -= Date().timeIntervalSince(pausedAt)
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
        if let engine {
            engine.inputNode.removeTap(onBus: 0)
            engine.stop()
        }
        engine = nil
        // Let everything already captured reach the file before closing it.
        chunkContinuation?.finish()
        chunkContinuation = nil
        await drainTask?.value
        drainTask = nil
        await sink.finish()

        if let startedAt {
            let end = pausedAt ?? Date()
            accumulated += end.timeIntervalSince(startedAt)
            self.startedAt = nil
        }
        pausedAt = nil
        stopTicker()
        releaseSession()

        state = .idle
        elapsed = max(0, accumulated)
        return elapsed
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

    // MARK: - Capture

    private func installTap(on input: AVAudioInputNode) throws {
        // `format: nil` means "whatever the node produces". Passing a format with
        // a different sample rate or channel count than the hardware is the
        // classic `IsFormatSampleRateAndChannelCountValid` trap.
        let continuation = chunkContinuation
        let pool = samplePool
        let block: AVAudioNodeTapBlock = { buffer, _ in
            // Realtime thread: the mixdown writes into a pooled array, so the
            // steady state allocates nothing here. (`yield` itself may enqueue.)
            guard let samples = AudioRecorder.monoSamples(from: buffer, reusing: pool.take()) else { return }
            continuation?.yield(AudioChunk(samples: samples, sampleRate: buffer.format.sampleRate))
        }
        if #available(iOS 27.0, macOS 27.0, *) {
            // iOS 27 reports a bad tap as an error instead of trapping. The
            // refined import keeps the `error:` label with an empty argument.
            do {
                try input.__installTap(onBus: 0, bufferSize: Self.tapBufferSize, format: nil, error: (), block: block)
            } catch {
                throw RecorderError.engineFailed(error.localizedDescription)
            }
        } else {
            #if os(iOS)
            // iOS 26 (the deployment target) has only the older `installTap`,
            // which traps instead of throwing when the node's format is unusable:
            // 0 Hz / 0 channels, or a node format that no longer matches the
            // hardware after a route change. Check both first so the worst case
            // is a thrown error, never a crash.
            try Self.validateTapFormat(of: input)
            input.installTap(onBus: 0, bufferSize: Self.tapBufferSize, format: nil, block: block)
            #endif
        }
    }

    /// Frames per tap callback.
    private static let tapBufferSize: AVAudioFrameCount = 4_096

    /// Throws when the node's output format is empty or disagrees with the
    /// hardware input format, the two states `installTap` traps on.
    static func validateTapFormat(of input: AVAudioInputNode) throws {
        let output = input.outputFormat(forBus: 0)
        let hardware = input.inputFormat(forBus: 0)
        guard output.sampleRate > 0, output.channelCount > 0 else {
            throw RecorderError.noInputAvailable
        }
        guard hardware.sampleRate > 0, hardware.channelCount > 0 else {
            throw RecorderError.noInputAvailable
        }
        guard output.sampleRate == hardware.sampleRate, output.channelCount == hardware.channelCount else {
            throw RecorderError.engineFailed(
                "the input format (\(Int(hardware.sampleRate)) Hz, \(hardware.channelCount) ch) does not match the node (\(Int(output.sampleRate)) Hz, \(output.channelCount) ch)"
            )
        }
    }

    private func startDraining() {
        stopDraining()
        let stream = AsyncStream<AudioChunk> { continuation in
            self.chunkContinuation = continuation
        }
        drainTask = Task { @MainActor [weak self] in
            for await chunk in stream {
                guard let self else { return }
                await self.handle(chunk)
            }
        }
    }

    private func stopDraining() {
        chunkContinuation?.finish()
        chunkContinuation = nil
        drainTask?.cancel()
        drainTask = nil
    }

    private func handle(_ chunk: AudioChunk) async {
        guard state == .recording else { return }
        let level = AudioRecorder.level(of: chunk.samples)
        self.level = level
        onLevel?(level)
        onChunk?(chunk)
        await sink.append(samples: chunk.samples, sampleRate: chunk.sampleRate)
        // Everyone above copied what they needed; hand the storage back to the tap.
        samplePool.recycle(chunk.samples)
    }

    /// Averages every channel of `buffer` into one mono channel.
    nonisolated static func monoSamples(from buffer: AVAudioPCMBuffer) -> [Float]? {
        monoSamples(from: buffer, reusing: nil)
    }

    /// Averages every channel of `buffer` into one mono channel, writing into
    /// `storage` when given so a uniquely held array of enough capacity is
    /// filled without a new allocation.
    nonisolated static func monoSamples(from buffer: AVAudioPCMBuffer, reusing storage: [Float]?) -> [Float]? {
        let frames = Int(buffer.frameLength)
        let channels = Int(buffer.format.channelCount)
        guard frames > 0, channels > 0 else { return nil }
        let scale = 1 / Float(channels)

        var out = storage ?? []
        out.removeAll(keepingCapacity: true)
        if out.capacity < frames { out.reserveCapacity(frames) }

        if let data = buffer.floatChannelData {
            if channels == 1 {
                out.append(contentsOf: UnsafeBufferPointer(start: data[0], count: frames))
                return out
            }
            out.append(contentsOf: repeatElement(0, count: frames))
            out.withUnsafeMutableBufferPointer { mixed in
                if buffer.format.isInterleaved {
                    let base = data[0]
                    for frame in 0..<frames {
                        var sum: Float = 0
                        for channel in 0..<channels { sum += base[frame * channels + channel] }
                        mixed[frame] = sum * scale
                    }
                } else {
                    for channel in 0..<channels {
                        let source = data[channel]
                        for frame in 0..<frames { mixed[frame] += source[frame] }
                    }
                    for frame in 0..<frames { mixed[frame] *= scale }
                }
            }
            return out
        }

        if let data = buffer.int16ChannelData {
            let norm = scale / Float(Int16.max)
            out.append(contentsOf: repeatElement(0, count: frames))
            out.withUnsafeMutableBufferPointer { mixed in
                if buffer.format.isInterleaved {
                    let base = data[0]
                    for frame in 0..<frames {
                        var sum: Float = 0
                        for channel in 0..<channels { sum += Float(base[frame * channels + channel]) }
                        mixed[frame] = sum * norm
                    }
                } else {
                    for channel in 0..<channels {
                        let source = data[channel]
                        for frame in 0..<frames { mixed[frame] += Float(source[frame]) }
                    }
                    for frame in 0..<frames { mixed[frame] *= norm }
                }
            }
            return out
        }

        return nil
    }

    /// A buffer holding `samples` as float32 mono at `sampleRate`.
    nonisolated static func monoBuffer(samples: [Float], sampleRate: Double) -> AVAudioPCMBuffer? {
        guard !samples.isEmpty, sampleRate > 0 else { return nil }
        guard let format = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: sampleRate,
            channels: 1,
            interleaved: false
        ) else { return nil }
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(samples.count)) else {
            return nil
        }
        buffer.frameLength = AVAudioFrameCount(samples.count)
        guard let channel = buffer.floatChannelData?[0] else { return nil }
        samples.withUnsafeBufferPointer { pointer in
            guard let base = pointer.baseAddress else { return }
            channel.update(from: base, count: samples.count)
        }
        return buffer
    }

    /// RMS level of `samples` mapped to 0...1 for a meter.
    nonisolated static func level(of samples: [Float]) -> Double {
        guard !samples.isEmpty else { return 0 }
        var sum: Float = 0
        for sample in samples { sum += sample * sample }
        let rms = (sum / Float(samples.count)).squareRoot()
        return max(0, min(1, Double((rms - 0.004) * 14)))
    }

    // MARK: - Session

    private func activateSession() throws {
        #if os(iOS)
        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(
                .playAndRecord,
                mode: .default,
                options: [.defaultToSpeaker, .allowBluetoothHFP]
            )
            try session.setActive(true, options: [])
        } catch {
            throw RecorderError.audioSessionFailed(error.localizedDescription)
        }
        #endif
    }

    /// Hands the session back in a playback-friendly shape so the host's
    /// spoken briefing (AVSpeechSynthesizer) keeps working after a recording.
    private func releaseSession() {
        #if os(iOS)
        let session = AVAudioSession.sharedInstance()
        try? session.setActive(false, options: [.notifyOthersOnDeactivation])
        try? session.setCategory(.playback, mode: .spokenAudio, options: [])
        #endif
    }

    // MARK: - Timer

    private func startTicker() {
        ticker?.cancel()
        ticker = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(200))
                guard let self else { return }
                if self.state == .recording, let startedAt = self.startedAt {
                    self.elapsed = max(0, self.accumulated + Date().timeIntervalSince(startedAt))
                    self.onElapsed?(self.elapsed)
                }
            }
        }
    }

    private func stopTicker() {
        ticker?.cancel()
        ticker = nil
    }

    // MARK: - Observers

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
                guard let self, let reason, self.isRecording else { return }
                if reason == .oldDeviceUnavailable {
                    self.banner = "Headphones were disconnected. Recording continues with the built-in microphone."
                    self.onBanner?(self.banner)
                }
            }
        }
        #endif

        configurationObserver = NotificationCenter.default.addObserver(
            forName: .AVAudioEngineConfigurationChange,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            let changed = notification.object as? AVAudioEngine
            Task { @MainActor in
                self?.handleConfigurationChange(of: changed)
            }
        }
    }

    /// The hardware format changed under a running engine (new route, new
    /// sample rate). The engine stops itself; rebuild the tap and restart.
    ///
    /// State moves first and the banner follows, so anyone reading both sees
    /// `.paused` together with the reason, never "recording" with a failure.
    private func handleConfigurationChange(of changed: AVAudioEngine?) {
        guard let engine, changed === engine, state == .recording else { return }
        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        guard format.sampleRate > 0, format.channelCount > 0 else {
            input.removeTap(onBus: 0)
            pause()
            banner = "The microphone went away. Recording is paused."
            onBanner?(banner)
            return
        }
        input.removeTap(onBus: 0)
        do {
            try installTap(on: input)
            try engine.start()
        } catch {
            pause()
            banner = "The audio route changed and recording could not continue: \(error.localizedDescription)"
            onBanner?(banner)
        }
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
            guard state == .paused else { return }
            if options?.contains(.shouldResume) == true {
                resume()
            } else {
                banner = "Recording stayed paused after the interruption. Tap Resume to continue."
                onBanner?(banner)
            }
        default:
            break
        }
    }
    #endif
}
