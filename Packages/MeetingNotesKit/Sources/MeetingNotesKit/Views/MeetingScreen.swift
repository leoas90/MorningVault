import SwiftData
import SwiftUI

/// The meeting page: the timer as the hero, the live transcript underneath, and the user's
/// own notes. After Stop the on-device model can turn the transcript plus the notes into
/// enhanced notes.
struct MeetingScreen: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Environment(\.meetingsTheme) private var theme
    @Environment(\.meetingSampleMode) private var sampleMode
    @StateObject private var session: RecordingSession
    @StateObject private var reminders = RemindersService()
    @State private var showTranscript = false
    @State private var notesMode: NotesMode = .enhanced
    @State private var confirmDiscard = false
    @State private var confirmClose = false
    @State private var infoMessage: String?
    @FocusState private var notesFocused: Bool

    /// Title the recording starts with, for example from a calendar event.
    var initialTitle: String = ""
    /// People taking part, filled in from a calendar event.
    var initialAttendees: [String] = []
    /// Calendar event the recording belongs to.
    var calendarEventID: String?
    /// Start recording as soon as the screen appears.
    var autoStart: Bool = false
    /// Shown in a sheet: adds a Close button.
    var isModal: Bool = false
    /// True when the session is owned by the home screen, so the sheet can close while the
    /// meeting keeps recording.
    private let sharesSession: Bool

    /// - Parameter session: a session owned by the caller (the home screen hands in its
    ///   own so the page can be closed and reopened while recording). `nil` makes one.
    init(
        session: RecordingSession? = nil,
        initialTitle: String = "",
        initialAttendees: [String] = [],
        calendarEventID: String? = nil,
        autoStart: Bool = false,
        isModal: Bool = false
    ) {
        _session = StateObject(wrappedValue: session ?? RecordingSession())
        sharesSession = session != nil
        self.initialTitle = initialTitle
        self.initialAttendees = initialAttendees
        self.calendarEventID = calendarEventID
        self.autoStart = autoStart
        self.isModal = isModal
    }

    var body: some View {
        if sampleMode {
            samplePage
        } else {
            livePage
        }
    }

    /// In a sheet the page brings its own navigation stack; pushed from the Meetings home
    /// it lives on the home's stack, so Back keeps the recording running in the inline
    /// block there.
    @ViewBuilder
    private var livePage: some View {
        if isModal {
            NavigationStack {
                page
            }
            .interactiveDismissDisabled(session.isRecording)
        } else {
            page
        }
    }

    /// The picture mode drops the navigation stack and the scroll view, because neither
    /// can be drawn outside a running window.
    private var samplePage: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Product weekly")
                .font(MeetingsType.meetingTitle)
                .foregroundStyle(theme.ink)
            Text("Ana, Ben, Chi")
                .font(MeetingsType.meta)
                .foregroundStyle(theme.inkSoft)
                .padding(.top, 4)
            RecordingHero(
                status: .recording,
                elapsed: 1_262,
                levels: MeetingPreviewData.waveform(phase: 0.8)
            )
            .padding(.top, 20)
            NotesSection("Transcript · live") {
                TranscriptRows(
                    rows: [TranscriptRowModel(id: 0, speakerKey: nil, name: nil, start: nil, text: "Ana opened the meeting and asked where the release checklist stands. Ben said the beta build is done and the review is booked for Friday.")],
                    volatileText: "Chi asked about the"
                )
            }
            .padding(.top, MeetingsSpace.sectionGap)
            NotesSection("My notes") {
                Text(MeetingPreviewData.sampleScratchpad)
                    .font(MeetingsType.body)
                    .lineSpacing(6)
                    .foregroundStyle(theme.ink)
            }
            .padding(.top, MeetingsSpace.sectionGap)
            Spacer(minLength: 0)
            Hairline()
                .padding(.horizontal, -MeetingsSpace.margin)
            HStack(spacing: 12) {
                MeetingsButton(title: "Pause", systemImage: "pause.fill", role: .secondary) {}
                MeetingsButton(title: "Stop", systemImage: "stop.fill", role: .negative) {}
            }
            .padding(.top, 12)
        }
        .padding(.horizontal, MeetingsSpace.margin)
        .padding(.vertical, 20)
        .themedPageBackground()
    }

    // MARK: - Page

    private var page: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                MeetingTitleField(title: $session.title, style: .hero)
                    .disabled(session.phase == .starting)

                if !session.attendees.isEmpty {
                    Text(session.attendees.joined(separator: ", "))
                        .font(MeetingsType.meta)
                        .foregroundStyle(theme.inkSoft)
                        .lineLimit(1)
                        .padding(.top, 4)
                }

                hero
                    .padding(.top, 20)

                messages

                if session.phase == .finished, let summary = session.summary {
                    NotesModeToggle(mode: $notesMode)
                        .padding(.top, MeetingsSpace.sectionGap)
                    Group {
                        switch notesMode {
                        case .enhanced:
                            EnhancedNotesView(summary: summary, meetingID: session.meetingID)
                        case .mine:
                            NotesSection("My notes") {
                                NotesEditor(text: $session.scratchpad, focus: $notesFocused)
                            }
                        }
                    }
                    .padding(.top, 20)
                } else {
                    transcriptSection
                        .padding(.top, MeetingsSpace.sectionGap)
                    NotesSection("My notes") {
                        NotesEditor(text: $session.scratchpad, focus: $notesFocused)
                    }
                    .padding(.top, MeetingsSpace.sectionGap)
                }
            }
            .padding(.horizontal, MeetingsSpace.margin)
            .padding(.top, 8)
            .padding(.bottom, 24)
        }
        .scrollDismissesKeyboard(.interactively)
        .themedPageBackground()
        .navigationTitle("")
        .inlineTitle()
        .safeAreaInset(edge: .bottom) { bottomBar }
        .toolbar { toolbarContent }
        .sheet(isPresented: $showTranscript) {
            TranscriptSheet(
                finalText: session.finalTranscript,
                volatileText: session.volatileTranscript,
                isLive: session.isRecording,
                isWorking: session.isTranscribingFile,
                turns: session.speakerTurns,
                isIdentifyingSpeakers: session.isIdentifyingSpeakers,
                speakerBanner: session.speakerBanner,
                onRename: { key, name in session.renameSpeaker(key: key, to: name, context: context) }
            )
            .meetingsTheme(theme)
        }
        .confirmationDialog("Discard this recording?", isPresented: $confirmDiscard, titleVisibility: .visible) {
            Button("Discard recording", role: .destructive) {
                Task {
                    await session.cancel()
                    if isModal { dismiss() }
                }
            }
            Button("Keep recording", role: .cancel) {}
        } message: {
            Text("The audio and the transcript are deleted. Your notes are not saved.")
        }
        .confirmationDialog("Still recording", isPresented: $confirmClose, titleVisibility: .visible) {
            Button("Stop and save") {
                Task {
                    await session.stop(context: context)
                    dismiss()
                }
            }
            Button("Discard recording", role: .destructive) {
                Task {
                    await session.cancel()
                    dismiss()
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Closing this sheet ends the recording.")
        }
        .alert("Reminders", isPresented: Binding(
            get: { reminders.message != nil || infoMessage != nil },
            set: { if !$0 { reminders.message = nil; infoMessage = nil } }
        )) {
            Button("OK", role: .cancel) { reminders.message = nil; infoMessage = nil }
        } message: {
            Text(reminders.message ?? infoMessage ?? "")
        }
        .onChange(of: session.scratchpad) { _, _ in
            if session.phase == .finished { session.persistEdits(context: context) }
        }
        .onChange(of: session.title) { _, _ in
            if session.phase == .finished {
                session.persistEdits(context: context)
            } else if session.isRecording {
                session.syncLiveActivityTitle()
            }
        }
        .task {
            if session.title.isEmpty, !initialTitle.isEmpty { session.title = initialTitle }
            if autoStart, session.phase == .idle || session.phase == .finished {
                await session.start(
                    calendarEventID: calendarEventID,
                    title: initialTitle,
                    attendees: initialAttendees,
                    context: context
                )
            }
        }
    }

    // MARK: - Hero

    private var hero: some View {
        RecordingHero(
            status: pillMode,
            elapsed: session.elapsed,
            levels: session.phase == .recording ? session.levelHistory : []
        )
    }

    @ViewBuilder
    private var transcriptSection: some View {
        let hasText = !session.finalTranscript.isEmpty || !session.volatileTranscript.isEmpty
        let turns = session.speakerTurns.contains { $0.name != nil } ? session.speakerTurns : []
        NotesSection(session.isRecording ? "Transcript · live" : "Transcript") {
            if session.isTranscribingFile {
                WorkingLine("Transcribing the recording on device…")
                    .padding(.vertical, 8)
            } else if session.isIdentifyingSpeakers, !turns.isEmpty {
                WorkingLine("Identifying speakers…")
                    .padding(.vertical, 8)
            }
            if !turns.isEmpty {
                TranscriptRows(
                    rows: TranscriptRowModel.rows(from: turns),
                    onRename: { key, name in session.renameSpeaker(key: key, to: name, context: context) }
                )
            } else if hasText {
                TranscriptRows(
                    rows: [TranscriptRowModel(id: 0, speakerKey: nil, name: nil, start: nil, text: session.finalTranscript)],
                    volatileText: session.volatileTranscript
                )
            } else if !session.isTranscribingFile {
                Text(session.isRecording ? "Words show up here as they are recognized." : "Nothing was recognized yet.")
                    .font(MeetingsType.secondary)
                    .foregroundStyle(theme.inkSoft)
                    .padding(.vertical, 8)
            }
        }
    }

    @ViewBuilder
    private var messages: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let error = session.errorMessage {
                BannerView(
                    message: error,
                    details: session.errorDetails,
                    symbol: "mic.slash",
                    actionTitle: session.errorNeedsSettings ? "Open Settings" : nil,
                    action: session.errorNeedsSettings ? { RecordingPermissions.openSettings() } : nil,
                    onDismiss: { session.clearError() }
                )
            }
            if let banner = session.banner {
                BannerView(message: banner, details: session.bannerDetails, onDismiss: { session.recorder.clearBanner() })
            }
            if session.isIdentifyingSpeakers, session.speakerTurns.isEmpty {
                WorkingLine("Identifying speakers…")
            } else if let speakerBanner = session.speakerBanner {
                BannerView(message: speakerBanner, details: session.speakerBannerDetails, symbol: "person.2.slash")
            }
        }
        .padding(.top, session.errorMessage != nil || session.banner != nil || session.isIdentifyingSpeakers || session.speakerBanner != nil ? 16 : 0)
    }

    private var pillMode: RecordingStatusPill.Mode {
        switch session.phase {
        case .idle: return .idle
        case .starting: return .starting
        case .recording: return .recording
        case .paused: return .paused
        case .finished: return .saved
        }
    }

    // MARK: - Bottom bar

    @ViewBuilder
    private var bottomBar: some View {
        VStack(spacing: 0) {
            Hairline()
            Group {
                switch session.phase {
                case .idle:
                    MeetingsButton(title: "Start recording", systemImage: "mic.fill", role: .primary) {
                        Task {
                            await session.start(
                                calendarEventID: calendarEventID,
                                title: session.title,
                                attendees: initialAttendees,
                                context: context
                            )
                        }
                    }

                case .starting:
                    WorkingLine("Starting…")
                        .frame(maxWidth: .infinity)
                        .frame(height: MeetingsSpace.control)

                case .recording, .paused:
                    HStack(spacing: 12) {
                        MeetingsButton(
                            title: session.phase == .paused ? "Resume" : "Pause",
                            systemImage: session.phase == .paused ? "play.fill" : "pause.fill",
                            role: .secondary
                        ) {
                            if session.phase == .paused { session.resume() } else { session.pause() }
                        }
                        MeetingsButton(title: "Stop", systemImage: "stop.fill", role: .negative) {
                            Task { await session.stop(context: context) }
                        }
                    }

                case .finished:
                    finishedBar
                }
            }
            .padding(.horizontal, MeetingsSpace.margin)
            .padding(.vertical, 12)
        }
        .background(theme.backgroundColor.opacity(0.96))
    }

    @ViewBuilder
    private var finishedBar: some View {
        switch session.summaryState {
        case .working:
            WorkingLine("Writing the notes on device…")
                .frame(maxWidth: .infinity)
                .frame(height: MeetingsSpace.control)

        case .finished:
            if isModal {
                MeetingsButton(title: "Done", role: .primary) {
                    session.persistEdits(context: context)
                    dismiss()
                }
            } else {
                EmptyView()
            }

        case .idle, .unavailable, .failed:
            VStack(spacing: 8) {
                if case .unavailable(let message) = session.summaryState {
                    Text(message)
                        .font(MeetingsType.meta)
                        .foregroundStyle(theme.inkSoft)
                        .multilineTextAlignment(.center)
                } else if case .failed(let message) = session.summaryState {
                    Text(message)
                        .font(MeetingsType.meta)
                        .foregroundStyle(theme.inkSoft)
                        .multilineTextAlignment(.center)
                }
                MeetingsButton(title: "Enhance notes", systemImage: "sparkles", role: .primary) {
                    Task { await session.enhance(context: context) }
                }
                .disabled(session.isTranscribingFile)
            }
        }
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        if isModal {
            ToolbarItem(placement: .cancellationAction) {
                Button("Close") {
                    if session.isRecording, !sharesSession {
                        confirmClose = true
                    } else {
                        session.persistEdits(context: context)
                        dismiss()
                    }
                }
            }
        }
        ToolbarItem(placement: .primaryAction) {
            Button {
                showTranscript = true
            } label: {
                Label("Transcript", systemImage: "text.quote")
            }
            .accessibilityLabel("Show transcript")
        }
        ToolbarItem(placement: .primaryAction) {
            Menu {
                if session.phase == .finished, let id = session.meetingID {
                    Button {
                        sendToReminders(meetingID: id)
                    } label: {
                        Label("Add to Reminders", systemImage: "list.bullet.clipboard")
                    }
                    .disabled(session.summary == nil)
                    ShareLink(item: markdown(for: id)) {
                        Label("Share notes", systemImage: "square.and.arrow.up")
                    }
                    if session.summary != nil {
                        Button {
                            Task { await session.enhance(context: context) }
                        } label: {
                            Label("Enhance again", systemImage: "sparkles")
                        }
                    }
                }
                if session.isRecording {
                    Button(role: .destructive) {
                        confirmDiscard = true
                    } label: {
                        Label("Discard recording", systemImage: "trash")
                    }
                }
            } label: {
                Label("More", systemImage: "ellipsis.circle")
            }
            .accessibilityLabel("More actions")
        }
    }

    private func markdown(for meetingID: UUID) -> String {
        var descriptor = FetchDescriptor<Meeting>(predicate: #Predicate { $0.id == meetingID })
        descriptor.fetchLimit = 1
        guard let meeting = (try? context.fetch(descriptor))?.first else { return "" }
        return MeetingPersistence.markdown(for: meeting, context: context)
    }

    private func sendToReminders(meetingID: UUID) {
        let items = MeetingPersistence.fetchActionItems(for: meetingID, context: context)
        // Items already sent are skipped, so a second tap does not duplicate them.
        let pending = MeetingPersistence.actionItemsToExport(from: items)
        let drafts = pending.map {
            ActionItem(text: $0.text, owner: $0.owner, due: $0.due.map { DueFormatter.string(from: $0) })
        }
        Task {
            do {
                let count = try await reminders.export(drafts)
                if count == 0 {
                    infoMessage = items.contains(where: \.exportedToReminders)
                        ? "Everything open was already sent to Reminders."
                        : "There was nothing open to send."
                } else {
                    try MeetingPersistence.markExported(pending, context: context)
                }
            } catch {
                infoMessage = error.localizedDescription
            }
        }
    }
}

/// The recording status and the timer as the hero of the page: eyebrow with the breathing
/// dot, the 56 pt timer, the live meter, a hairline underneath. No box.
struct RecordingHero: View {
    @Environment(\.meetingsTheme) private var theme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let status: RecordingStatusPill.Mode
    let elapsed: TimeInterval
    let levels: [Double]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                BreathingDot(color: dotColor, isActive: status == .recording)
                Eyebrow(label, color: status == .recording ? theme.negativeColor : nil)
                    .contentTransition(.numericText())
            }
            ElapsedTimeLabel(elapsed: elapsed)
                .padding(.top, 12)
                .opacity(status == .idle ? 0.5 : 1)
            LevelMeter(history: status == .paused ? [] : levels, isActive: status == .recording || status == .starting, themed: true)
                .padding(.top, 12)
                .opacity(status == .saved || status == .idle ? 0.35 : 1)
            Hairline()
                .padding(.top, 20)
        }
        .animation(reduceMotion ? nil : .smooth(duration: 0.35), value: status)
        .accessibilityElement(children: .contain)
    }

    private var label: String {
        switch status {
        case .idle: return "Not recording"
        case .starting: return "Starting…"
        case .recording: return "Recording"
        case .paused: return "Paused"
        case .saved: return "Saved"
        }
    }

    private var dotColor: Color {
        switch status {
        case .recording: return theme.negativeColor
        case .saved: return theme.positiveColor
        case .idle, .starting, .paused: return theme.inkSoft
        }
    }
}

// MARK: - Previews

#Preview("Recording · light") {
    MeetingShowcaseView()
        .meetingsTheme(MeetingPreviewData.warmTheme(.light))
        .preferredColorScheme(.light)
}

#Preview("Recording · dark") {
    MeetingShowcaseView()
        .meetingsTheme(MeetingPreviewData.warmTheme(.dark))
        .preferredColorScheme(.dark)
}

#Preview("Recording · idle · pushed") {
    NavigationStack {
        MeetingScreen(isModal: false)
    }
    .modelContainer(MeetingPreviewData.previewContainer(empty: true))
    .meetingsTheme(MeetingPreviewData.warmTheme(.light))
    .preferredColorScheme(.light)
}
