import Foundation
import SwiftData

/// Drives one recording: audio in, saved meeting out.
@MainActor
public final class RecordingSession: ObservableObject {
    public enum Phase: Equatable, Sendable {
        case idle
        case recording
        case paused
        case finished
    }

    /// The user's own notes, typed while the meeting runs.
    @Published public var scratchpad: String = ""
    /// What has been said so far.
    @Published public private(set) var transcript: String = ""
    @Published public private(set) var phase: Phase = .idle
    @Published public private(set) var elapsed: TimeInterval = 0
    /// Current microphone level, 0 to 1.
    @Published public private(set) var level: Double = 0
    /// Recent microphone levels, used to draw the meter.
    @Published public private(set) var levelHistory: [Double] = []
    @Published public private(set) var banner: String?
    @Published public private(set) var errorMessage: String?
    @Published public private(set) var summary: MeetingSummary?
    @Published public private(set) var summaryState: MeetingSummarizer.State = .idle
    /// Identifier of the meeting that was saved.
    @Published public private(set) var meetingID: UUID?
    /// Title the meeting starts with.
    @Published public private(set) var title: String = ""
    /// People taking part.
    @Published public private(set) var attendees: [String] = []
    /// Calendar event the recording belongs to.
    @Published public private(set) var calendarEventID: String?

    public let recorder = AudioRecorder()
    public let transcriber = LiveTranscriber()
    public let summarizer = MeetingSummarizer()

    private var startedAt = Date()
    private var recordingID = UUID()
    private var liveTranscriptionWorked = false

    public init() {
        recorder.onChunk = { [weak self] chunk in
            self?.transcriber.ingest(chunk)
        }
        recorder.onLevel = { [weak self] value in
            guard let self else { return }
            self.level = value
            self.levelHistory.append(value)
            if self.levelHistory.count > 48 {
                self.levelHistory.removeFirst(self.levelHistory.count - 48)
            }
        }
        recorder.onElapsed = { [weak self] value in
            self?.elapsed = value
        }
        recorder.onBanner = { [weak self] message in
            self?.banner = message
        }
        transcriber.onUpdate = { [weak self] text in
            self?.transcript = text
        }
    }

    /// True while the microphone is running.
    public var isRecording: Bool {
        phase == .recording || phase == .paused
    }

    /// Starts a new recording.
    public func start(
        calendarEventID: String? = nil,
        title: String = "",
        attendees: [String] = []
    ) async {
        guard !isRecording else { return }
        errorMessage = nil
        summary = nil
        summaryState = .idle
        transcript = ""
        levelHistory = []
        elapsed = 0
        scratchpad = ""
        recordingID = UUID()
        startedAt = Date()
        self.calendarEventID = calendarEventID
        self.title = title
        self.attendees = attendees

        do {
            try await recorder.start(meetingID: recordingID)
        } catch {
            errorMessage = error.localizedDescription
            phase = .idle
            return
        }

        phase = .recording
        liveTranscriptionWorked = await transcriber.start()
        if !liveTranscriptionWorked {
            banner = "Live transcription is not available. The recording is transcribed when you stop."
        }
    }

    /// Pauses the recording.
    public func pause() {
        recorder.pause()
        phase = .paused
    }

    /// Resumes the recording.
    public func resume() {
        recorder.resume()
        phase = .recording
    }

    /// Stops the recording and saves the meeting.
    public func stop(context: ModelContext) async {
        guard isRecording else { return }
        let duration = await recorder.stop()
        await transcriber.stop()
        phase = .finished
        elapsed = duration

        let meeting = Meeting(
            id: recordingID,
            title: title,
            startedAt: startedAt,
            endedAt: Date(),
            duration: duration,
            scratchpad: scratchpad,
            transcript: transcript,
            audioFileName: recorder.recordingURL?.lastPathComponent,
            calendarEventID: calendarEventID,
            attendeeNames: attendees
        )
        context.insert(meeting)
        try? context.save()
        meetingID = meeting.id

        if !liveTranscriptionWorked, let url = recorder.recordingURL {
            await transcribeSavedRecording(url: url)
        }

        MeetingPersistence.writeToAppGroup(for: meeting, context: context)
    }

    /// Throws the recording away.
    public func cancel() async {
        await recorder.cancel()
        await transcriber.stop()
        phase = .idle
        transcript = ""
        elapsed = 0
        summary = nil
        summaryState = .idle
        meetingID = nil
    }

    /// Saves the notes the user typed.
    public func saveScratchpad(context: ModelContext) {
        guard let meetingID, let meeting = fetchMeeting(meetingID, context: context) else { return }
        meeting.scratchpad = scratchpad
        try? context.save()
    }

    /// Runs the on-device model over the transcript and the user's notes.
    public func enhance(context: ModelContext) async {
        guard let meetingID, let meeting = fetchMeeting(meetingID, context: context) else { return }
        meeting.scratchpad = scratchpad
        await summarizer.summarize(transcript: meeting.transcript, scratchpad: scratchpad, title: meeting.title)
        switch summarizer.state {
        case .finished(let result):
            summary = result
            MeetingPersistence.update(meeting: meeting, summary: result, context: context)
            MeetingPersistence.replaceActionItems(of: meeting, with: result.actionItems, context: context)
            meeting.title = result.title.isEmpty ? meeting.title : result.title
            try? context.save()
            MeetingPersistence.writeToAppGroup(for: meeting, context: context)
        case .unavailable(let message):
            summaryState = .unavailable(message)
        case .failed(let message):
            summaryState = .failed(message)
        case .idle, .working:
            break
        }
    }

    private func fetchMeeting(_ id: UUID, context: ModelContext) -> Meeting? {
        var descriptor = FetchDescriptor<Meeting>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        return (try? context.fetch(descriptor))?.first
    }

    private func transcribeSavedRecording(url: URL) async {
        do {
            let text = try await FileTranscriptionService.transcribe(fileURL: url)
            if !text.isEmpty {
                transcript = text
            }
        } catch {
            banner = "The recording could not be transcribed: \(error.localizedDescription)"
        }
    }
}
