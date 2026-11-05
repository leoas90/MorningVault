import SwiftData
import SwiftUI

/// The meeting page: one editable notes document with the recorder underneath.
///
/// The user types in their own words; the transcript lives behind a toolbar
/// button so the page stays calm. After Stop the on-device model can turn the
/// transcript plus the notes into enhanced notes.
struct MeetingScreen: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Environment(\.meetingSampleMode) private var sampleMode
    @StateObject private var session = RecordingSession()
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

    var body: some View {
        if sampleMode {
            // The picture mode drops the navigation stack and the scroll view,
            // because neither can be drawn outside a running window.
            VStack(alignment: .leading, spacing: 16) {
                Text("Product weekly")
                    .font(.title.weight(.bold))
                RecordingStatusPill(mode: .recording, elapsed: 42)
                Text(MeetingPreviewData.sampleScratchpad)
                    .font(.body)
                Spacer(minLength: 0)
                sampleBar
            }
            .padding(.horizontal)
            .padding(.vertical, 20)
        } else {
            NavigationStack {
                page
            }
            .interactiveDismissDisabled(session.isRecording)
        }
    }

    // MARK: - Page

    private var page: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                MeetingTitleField(title: $session.title)
                    .disabled(session.phase == .starting)

                HStack(spacing: 10) {
                    RecordingStatusPill(mode: pillMode, elapsed: session.elapsed)
                    if !session.attendees.isEmpty {
                        Text(session.attendees.joined(separator: ", "))
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    Spacer(minLength: 0)
                }

                messages

                if session.phase == .finished, let summary = session.summary {
                    NotesModeToggle(mode: $notesMode)
                    switch notesMode {
                    case .enhanced:
                        EnhancedNotesView(summary: summary, meetingID: session.meetingID)
                    case .mine:
                        NotesEditor(text: $session.scratchpad, focus: $notesFocused)
                    }
                } else {
                    NotesEditor(text: $session.scratchpad, focus: $notesFocused)
                }
            }
            .padding(.horizontal)
            .padding(.top, 8)
            .padding(.bottom, 24)
        }
        .scrollDismissesKeyboard(.interactively)
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
            Button("Keep recording", role: .cancel) {}
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
            if autoStart, session.phase == .idle {
                await session.start(
                    calendarEventID: calendarEventID,
                    title: initialTitle,
                    attendees: initialAttendees,
                    context: context
                )
            }
        }
    }

    @ViewBuilder
    private var messages: some View {
        if let error = session.errorMessage {
            BannerView(
                message: error,
                symbol: "mic.slash.fill",
                actionTitle: session.errorNeedsSettings ? "Open Settings" : nil,
                action: session.errorNeedsSettings ? { RecordingPermissions.openSettings() } : nil,
                onDismiss: { session.clearError() }
            )
        }
        if let banner = session.banner {
            BannerView(message: banner, onDismiss: { session.recorder.clearBanner() })
        }
        if session.isTranscribingFile {
            HStack(spacing: 8) {
                ProgressView()
                Text("Transcribing the recording on device…")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        if session.isIdentifyingSpeakers {
            HStack(spacing: 8) {
                ProgressView()
                Text("Identifying speakers…")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            .accessibilityElement(children: .combine)
        } else if let speakerBanner = session.speakerBanner {
            BannerView(message: speakerBanner, symbol: "person.2.slash")
        }
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
            Divider()
            Group {
                switch session.phase {
                case .idle:
                    Button {
                        Task {
                            await session.start(
                                calendarEventID: calendarEventID,
                                title: session.title,
                                attendees: initialAttendees,
                                context: context
                            )
                        }
                    } label: {
                        HStack(spacing: 12) {
                            RecordButton(isRecording: false, size: 44) {}
                                .allowsHitTesting(false)
                                .accessibilityHidden(true)
                            Text("Start recording")
                                .font(.headline)
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Start recording")

                case .starting:
                    HStack(spacing: 10) {
                        ProgressView()
                        Text("Starting…")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity)

                case .recording, .paused:
                    HStack(spacing: 24) {
                        Button {
                            if session.phase == .paused { session.resume() } else { session.pause() }
                        } label: {
                            Label(
                                session.phase == .paused ? "Resume" : "Pause",
                                systemImage: session.phase == .paused ? "play.fill" : "pause.fill"
                            )
                            .frame(minWidth: 100)
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.large)

                        VStack(spacing: 4) {
                            RecordButton(isRecording: true, isPaused: session.phase == .paused, size: 64) {
                                Task { await session.stop(context: context) }
                            }
                            Text("Stop")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .accessibilityHidden(true)
                        }

                        Color.clear
                            .frame(minWidth: 100, maxHeight: 1)
                            .accessibilityHidden(true)
                    }

                case .finished:
                    finishedBar
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 12)
        }
        .background(.bar)
    }

    @ViewBuilder
    private var finishedBar: some View {
        switch session.summaryState {
        case .working:
            HStack(spacing: 10) {
                ProgressView()
                Text("Writing the notes on device…")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)

        case .finished:
            if isModal {
                Button {
                    session.persistEdits(context: context)
                    dismiss()
                } label: {
                    Text("Done")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
            } else {
                EmptyView()
            }

        case .idle, .unavailable, .failed:
            VStack(spacing: 8) {
                if case .unavailable(let message) = session.summaryState {
                    Text(message)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                } else if case .failed(let message) = session.summaryState {
                    Text(message)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                Button {
                    Task { await session.enhance(context: context) }
                } label: {
                    Label("Enhance notes", systemImage: "sparkles")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(session.isTranscribingFile)
            }
        }
    }

    private var sampleBar: some View {
        HStack(spacing: 24) {
            Label("Pause", systemImage: "pause.fill")
                .frame(minWidth: 100)
                .padding(.vertical, 10)
                .background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            RecordButton(isRecording: true, size: 64) {}
            Color.clear.frame(minWidth: 100, maxHeight: 1)
        }
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        if isModal {
            ToolbarItem(placement: .cancellationAction) {
                Button("Close") {
                    if session.isRecording {
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
        let drafts = items.filter { !$0.isDone }.map {
            ActionItem(text: $0.text, owner: $0.owner, due: $0.due.map { DueFormatter.string(from: $0) })
        }
        Task {
            do {
                let count = try await reminders.export(drafts)
                for item in items { item.exportedToReminders = true }
                try? context.save()
                if count == 0 { infoMessage = "There was nothing open to send." }
            } catch {
                infoMessage = error.localizedDescription
            }
        }
    }
}
