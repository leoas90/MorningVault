import Foundation
import SwiftData

/// Drives one recording: audio in, saved meeting out.
///
/// Live transcription is best effort. If it cannot start, or produces nothing,
/// the recording keeps going and the saved file is transcribed when the user
/// stops. Nothing in here can take the recording down with it.
@MainActor
public final class RecordingSession: ObservableObject {
    public enum Phase: Equatable, Sendable {
        case idle
        case starting
        case recording
        case paused
        case finished
    }

    /// Title the meeting is saved with. Editable while recording.
    @Published public var title: String = ""
    /// The user's own notes, typed while the meeting runs.
    @Published public var scratchpad: String = ""
    /// What has been said so far, finalised and volatile text joined.
    @Published public private(set) var transcript: String = ""
    /// Speech the recogniser has settled on.
    @Published public private(set) var finalTranscript: String = ""
    /// Speech that may still change.
    @Published public private(set) var volatileTranscript: String = ""
    @Published public private(set) var phase: Phase = .idle
    @Published public private(set) var elapsed: TimeInterval = 0
    /// Current microphone level, 0 to 1.
    @Published public private(set) var level: Double = 0
    /// Recent microphone levels, used to draw a meter.
    @Published public private(set) var levelHistory: [Double] = []
    @Published public private(set) var banner: String?
    /// Raw framework text behind `banner`, shown under a Details disclosure.
    @Published public private(set) var bannerDetails: String?
    @Published public private(set) var errorMessage: String?
    /// Raw framework text behind `errorMessage`.
    @Published public private(set) var errorDetails: String?
    /// True when `errorMessage` can only be fixed in Settings.
    @Published public private(set) var errorNeedsSettings = false
    @Published public private(set) var summary: MeetingSummary?
    @Published public private(set) var summaryState: MeetingSummarizer.State = .idle
    /// True while the saved file is being transcribed after Stop.
    @Published public private(set) var isTranscribingFile = false
    /// True while speakers are being told apart after Stop.
    @Published public private(set) var isIdentifyingSpeakers = false
    /// Why speakers could not be identified, when they could not.
    @Published public private(set) var speakerBanner: String?
    /// Raw framework text behind `speakerBanner`.
    @Published public private(set) var speakerBannerDetails: String?
    /// Speakers found in the recording, with their names.
    @Published public private(set) var speakerLabels: [SpeakerLabel] = []
    /// Who said what, one entry per finalised transcript piece.
    @Published public private(set) var speakerTurns: [SpokenTurn] = []
    /// Identifier of the meeting that was saved.
    @Published public private(set) var meetingID: UUID?
    /// People taking part.
    @Published public private(set) var attendees: [String] = []
    /// Calendar event the recording belongs to.
    @Published public private(set) var calendarEventID: String?

    /// Identifier of the recording in progress (its folder has no `Meeting`
    /// row until Stop), or `nil` when nothing is being recorded.
    public var activeRecordingID: UUID? {
        isRecording ? recordingID : nil
    }

    public let recorder = AudioRecorder()
    public let transcriber = LiveTranscriber()
    public let summarizer = MeetingSummarizer()

    private var startedAt = Date()
    private var recordingID = UUID()
    private let liveActivity = RecordingLiveActivity()
    private var liveTranscriptionWorked = false
    private var speechAuthorized = false
    private var liveStartTask: Task<Void, Never>?
    private var speakerTask: Task<Void, Never>?
    /// Finalised transcript pieces with their place in the recording.
    private var pieces: [TranscriptPiece] = []

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
            self?.bannerDetails = nil
        }
        transcriber.onUpdate = { [weak self] final, volatile in
            guard let self else { return }
            self.finalTranscript = final
            self.volatileTranscript = volatile
            self.transcript = Self.join(final: final, volatile: volatile)
        }
        transcriber.onPiece = { [weak self] piece in
            self?.pieces.append(piece)
        }
    }

    /// True while the microphone is running.
    public var isRecording: Bool {
        phase == .recording || phase == .paused
    }

    /// Starts a new recording. Asks for permissions first and never throws.
    ///
    /// - Parameter context: where the meeting is saved when the Live Activity's Stop
    ///   button (or anything else outside the owning view) stops the recording.
    public func start(
        calendarEventID: String? = nil,
        title: String = "",
        attendees: [String] = [],
        context: ModelContext? = nil
    ) async {
        guard phase == .idle || phase == .finished else { return }
        phase = .starting
        errorMessage = nil
        errorDetails = nil
        errorNeedsSettings = false
        banner = nil
        bannerDetails = nil
        summary = nil
        summaryState = .idle
        transcript = ""
        finalTranscript = ""
        volatileTranscript = ""
        transcriber.reset()
        pieces = []
        speakerTask?.cancel()
        speakerTask = nil
        isIdentifyingSpeakers = false
        speakerBanner = nil
        speakerBannerDetails = nil
        speakerLabels = []
        speakerTurns = []
        levelHistory = []
        elapsed = 0
        scratchpad = ""
        meetingID = nil
        recordingID = UUID()
        startedAt = Date()
        self.calendarEventID = calendarEventID
        self.title = title
        self.attendees = attendees

        // Microphone first: without it there is nothing to record.
        guard await RecordingPermissions.requestMicrophone() else {
            fail(RecorderError.microphoneDenied)
            return
        }
        // Speech second, so both prompts show before the timer starts. A
        // refusal only turns transcription off.
        speechAuthorized = await RecordingPermissions.requestSpeech()

        do {
            try await recorder.start(meetingID: recordingID)
        } catch {
            fail(error)
            return
        }

        phase = .recording
        startLiveTranscription()
        if let context {
            ActiveRecordingRegistry.shared.register(self) { [weak self] in
                await self?.stop(context: context)
            }
        }
        liveActivity.start(title: self.title, startedAt: Date())
        MeetingsSnapshotPublisher.setRecording(true)
    }

    /// Pauses the recording.
    public func pause() {
        guard phase == .recording else { return }
        recorder.pause()
        phase = .paused
        liveActivity.pause()
    }

    /// Resumes the recording.
    public func resume() {
        guard phase == .paused else { return }
        recorder.resume()
        if recorder.state == .recording {
            phase = .recording
            liveActivity.resume(elapsed: elapsed)
        }
    }

    /// Pushes a title typed while recording to the Live Activity.
    public func syncLiveActivityTitle() {
        guard isRecording else { return }
        liveActivity.setTitle(title)
    }

    /// Stops the recording and saves the meeting.
    public func stop(context: ModelContext) async {
        guard isRecording else { return }
        liveStartTask?.cancel()
        liveStartTask = nil
        liveActivity.end()
        ActiveRecordingRegistry.shared.unregister(self)
        let duration = await recorder.stop()
        await transcriber.stop()
        phase = .finished
        elapsed = duration

        let meeting = Meeting(
            id: recordingID,
            title: title.trimmingCharacters(in: .whitespacesAndNewlines),
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
        save(context, what: "The meeting could not be saved.")
        meetingID = meeting.id

        // Fall back to transcribing the file when live transcription was off
        // or came back empty (for example when the language pack finished
        // downloading after the meeting had already started).
        let liveText = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        if liveText.isEmpty, speechAuthorized, let url = recorder.recordingURL, duration > 1 {
            await transcribeSavedRecording(url: url)
            meeting.transcript = transcript
            save(context, what: "The transcript could not be saved.")
        } else if liveText.isEmpty, !speechAuthorized {
            banner = "Speech recognition is off in Settings, so this meeting has no transcript."
        } else if !liveText.isEmpty, pieces.count <= 1, speechAuthorized, let url = recorder.recordingURL, duration > 20 {
            // Live text came back without timings, so speakers could not be
            // told apart. Re-read the file for timed pieces; keep the live
            // text if that fails.
            if let timed = try? await FileTranscriptionService.transcribeWithTiming(fileURL: url),
               timed.pieces.count > 1 {
                pieces = timed.pieces
            } else if pieces.isEmpty {
                pieces = [TranscriptPiece(text: liveText, start: 0, end: duration)]
            }
        } else if !liveText.isEmpty, pieces.isEmpty {
            // Live transcription without timing: keep the text as one piece so
            // the transcript sheet and exports still have something to show.
            pieces = [TranscriptPiece(text: liveText, start: 0, end: duration)]
        }
        do {
            try MeetingPersistence.replaceTranscriptPieces(of: meeting, with: pieces, context: context)
        } catch {
            report(error, what: "The transcript could not be saved.")
        }
        refreshSpeakerTurns(meeting: meeting, context: context)

        MeetingPersistence.writeToAppGroup(for: meeting, context: context)
        MeetingsSnapshotStore.update { $0.isRecording = false }
        MeetingsSnapshotPublisher.publishStoreChanges(context: context)

        if !pieces.isEmpty, let url = recorder.recordingURL, duration > 1 {
            startSpeakerIdentification(meetingID: meeting.id, url: url, context: context)
        }
    }

    /// Renames a speaker of the saved meeting.
    public func renameSpeaker(key: String, to name: String, context: ModelContext) {
        guard let meetingID, let meeting = fetchMeeting(meetingID, context: context) else { return }
        do {
            try MeetingPersistence.renameSpeaker(key: key, to: name, in: meeting, context: context)
        } catch {
            report(error, what: "The speaker name could not be saved.")
        }
        refreshSpeakerTurns(meeting: meeting, context: context)
        MeetingPersistence.writeToAppGroup(for: meeting, context: context)
    }

    /// Throws the recording away.
    public func cancel() async {
        liveStartTask?.cancel()
        liveStartTask = nil
        speakerTask?.cancel()
        speakerTask = nil
        isIdentifyingSpeakers = false
        speakerLabels = []
        speakerTurns = []
        pieces = []
        liveActivity.end()
        ActiveRecordingRegistry.shared.unregister(self)
        MeetingsSnapshotPublisher.setRecording(false)
        await recorder.cancel()
        await transcriber.stop()
        phase = .idle
        transcript = ""
        finalTranscript = ""
        volatileTranscript = ""
        elapsed = 0
        summary = nil
        summaryState = .idle
        meetingID = nil
        banner = nil
        bannerDetails = nil
    }

    /// Clears the error so the user can try again.
    public func clearError() {
        errorMessage = nil
        errorDetails = nil
        errorNeedsSettings = false
    }

    /// Saves the title and notes the user typed after the meeting was stored.
    public func persistEdits(context: ModelContext) {
        guard let meetingID, let meeting = fetchMeeting(meetingID, context: context) else { return }
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        var changed = false
        if meeting.title != trimmed {
            let oldTitle = meeting.title
            meeting.title = trimmed
            changed = true
            MeetingPersistence.appGroupCopyRetitled(meeting, from: oldTitle)
        }
        if meeting.scratchpad != scratchpad { meeting.scratchpad = scratchpad; changed = true }
        if changed {
            save(context, what: "Your edits could not be saved.")
            MeetingsSnapshotPublisher.publishStoreChanges(context: context)
        }
    }

    /// Runs the on-device model over the transcript and the user's notes.
    public func enhance(context: ModelContext) async {
        guard let meetingID, let meeting = fetchMeeting(meetingID, context: context) else { return }
        persistEdits(context: context)
        summaryState = .working
        let material = MeetingPersistence.labelledTranscript(for: meeting, context: context)
        await summarizer.summarize(transcript: material, scratchpad: scratchpad, title: meeting.title)
        switch summarizer.state {
        case .finished(let result):
            summary = result
            summaryState = .finished(result)
            do {
                try MeetingPersistence.update(meeting: meeting, summary: result, context: context)
                try MeetingPersistence.replaceActionItems(of: meeting, with: result.actionItems, context: context)
                if meeting.title.isEmpty, !result.title.isEmpty {
                    let oldTitle = meeting.title
                    meeting.title = result.title
                    title = result.title
                    MeetingPersistence.appGroupCopyRetitled(meeting, from: oldTitle)
                }
                try context.save()
            } catch {
                report(error, what: "The enhanced notes could not be saved.")
            }
            MeetingPersistence.writeToAppGroup(for: meeting, context: context)
            MeetingsSnapshotPublisher.publishStoreChanges(context: context)
        case .unavailable(let message):
            summaryState = .unavailable(message)
        case .failed(let message):
            summaryState = .failed(message)
        case .idle, .working:
            summaryState = .idle
        }
    }

    // MARK: - Private

    /// Saves `context`, turning a failure into a banner instead of losing it quietly.
    private func save(_ context: ModelContext, what: String) {
        do {
            try context.save()
        } catch {
            report(error, what: what)
        }
    }

    private func report(_ error: Error, what: String) {
        let text = UserMessage.from(error, context: what)
        banner = text.message
        bannerDetails = text.details
    }

    private func fail(_ error: Error) {
        let text = UserMessage.from(error, context: "The recording could not start.")
        errorMessage = text.message
        errorDetails = text.details
        errorNeedsSettings = (error as? RecorderError)?.needsSettings ?? false
        phase = .idle
    }

    private func startLiveTranscription() {
        liveStartTask?.cancel()
        liveStartTask = Task { @MainActor [weak self] in
            guard let self else { return }
            let worked = await self.transcriber.start()
            guard !Task.isCancelled else { return }
            self.liveTranscriptionWorked = worked
            if !worked, self.isRecording {
                let reason = self.transcriber.unavailableReason ?? "Live transcription is not available."
                self.banner = "\(reason) The recording is transcribed when you stop."
                self.bannerDetails = nil
            }
        }
    }

    private func fetchMeeting(_ id: UUID, context: ModelContext) -> Meeting? {
        var descriptor = FetchDescriptor<Meeting>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        return (try? context.fetch(descriptor))?.first
    }

    private func transcribeSavedRecording(url: URL) async {
        isTranscribingFile = true
        defer { isTranscribingFile = false }
        do {
            let result = try await FileTranscriptionService.transcribeWithTiming(fileURL: url)
            if !result.text.isEmpty {
                finalTranscript = result.text
                volatileTranscript = ""
                transcript = result.text
                pieces = result.pieces
            }
        } catch {
            let text = UserMessage.from(error, context: "The recording could not be transcribed.")
            banner = text.message
            bannerDetails = text.details
        }
    }

    /// Runs diarization off the main actor and files the result when it lands.
    ///
    /// The notes stay usable meanwhile; a failure only leaves the transcript
    /// without names and explains why in `speakerBanner`.
    private func startSpeakerIdentification(meetingID: UUID, url: URL, context: ModelContext) {
        speakerTask?.cancel()
        guard SpeakerDiarizer.isAvailable else {
            speakerBanner = "Speaker identification is not available in this build."
            return
        }
        isIdentifyingSpeakers = true
        speakerBanner = nil
        speakerBannerDetails = nil
        let profile = VoiceProfileStore.load()
        speakerTask = Task { @MainActor [weak self] in
            let outcome: Result<SpeakerIdentification, Error> = await Task.detached(priority: .utility) {
                do {
                    var found = try await SpeakerDiarizer.shared.diarize(fileURL: url)
                    let youKey = profile.flatMap { SpeakerAssignment.bestMatch(among: found.labels, enrolled: $0.embedding) }
                    let names = SpeakerAssignment.defaultNames(for: found.labels.map(\.key), youKey: youKey)
                    found.labels = found.labels.map { label in
                        var copy = label
                        copy.name = names[label.key] ?? label.name
                        return copy
                    }
                    return .success(found)
                } catch {
                    return .failure(error)
                }
            }.value
            guard let self, !Task.isCancelled else { return }
            self.isIdentifyingSpeakers = false
            guard let meeting = self.fetchMeeting(meetingID, context: context) else { return }
            switch outcome {
            case .success(let identification):
                do {
                    try MeetingPersistence.applySpeakers(identification, to: meeting, context: context)
                } catch {
                    let text = UserMessage.from(error, context: "Speaker names could not be saved.")
                    self.speakerBanner = text.message
                    self.speakerBannerDetails = text.details
                }
                self.refreshSpeakerTurns(meeting: meeting, context: context)
                MeetingPersistence.writeToAppGroup(for: meeting, context: context)
            case .failure(let error):
                let text = UserMessage.from(error, context: "Speakers could not be identified.")
                self.speakerBanner = text.message
                self.speakerBannerDetails = text.details
            }
        }
    }

    private func refreshSpeakerTurns(meeting: Meeting, context: ModelContext) {
        speakerLabels = meeting.speakerLabels
        let segments = MeetingPersistence.fetchTranscriptSegments(for: meeting.id, context: context)
        let labels = speakerLabels
        speakerTurns = SpeakerAssignment.turns(
            from: segments.map { TranscriptPiece(text: $0.text, start: $0.startTime, end: $0.endTime) },
            keys: segments.map(\.speakerKey),
            names: { key in labels.first { $0.key == key }?.name }
        )
    }

    private static func join(final: String, volatile: String) -> String {
        TranscriptAssembler.join(final: final, volatile: volatile)
    }
}
