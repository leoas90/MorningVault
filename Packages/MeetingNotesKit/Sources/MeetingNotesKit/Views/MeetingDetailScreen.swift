import SwiftData
import SwiftUI

/// A saved meeting: the same notes-first page as the live one, without the recorder.
struct MeetingDetailScreen: View {
    @Bindable var meeting: Meeting
    @Environment(\.modelContext) private var context
    @StateObject private var playback = AudioPlaybackController()
    @StateObject private var reminders = RemindersService()
    @StateObject private var summarizer = MeetingSummarizer()
    @State private var notesMode: NotesMode = .enhanced
    @State private var showTranscript = false
    @State private var infoMessage: String?
    @State private var speakerTurns: [SpokenTurn] = []
    @FocusState private var notesFocused: Bool

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                MeetingTitleField(title: $meeting.title)

                HStack(spacing: 6) {
                    Text(meeting.startedAt.formatted(date: .abbreviated, time: .shortened))
                    Text("·")
                    Text(MarkdownExporter.durationText(meeting.duration))
                    if !meeting.attendeeNames.isEmpty {
                        Text("·")
                        Text(meeting.attendeeNames.joined(separator: ", "))
                            .lineLimit(1)
                    }
                }
                .font(.footnote)
                .foregroundStyle(.secondary)

                if let error = playback.errorMessage {
                    BannerView(message: error)
                }
                if case .unavailable(let message) = summarizer.state {
                    BannerView(message: message)
                } else if case .failed(let message) = summarizer.state {
                    BannerView(message: message)
                }

                if let summary {
                    NotesModeToggle(mode: $notesMode)
                    switch notesMode {
                    case .enhanced:
                        EnhancedNotesView(summary: summary, meetingID: meeting.id)
                    case .mine:
                        NotesEditor(text: $meeting.scratchpad, focus: $notesFocused)
                    }
                } else {
                    NotesEditor(text: $meeting.scratchpad, focus: $notesFocused)
                }
            }
            .padding(.horizontal)
            .padding(.top, 8)
            .padding(.bottom, 24)
        }
        .scrollDismissesKeyboard(.interactively)
        .navigationTitle("")
        .safeAreaInset(edge: .bottom) {
            if summary == nil || summarizer.state == .working {
                bottomBar
            }
        }
        .toolbar { toolbarContent }
        .sheet(isPresented: $showTranscript) {
            TranscriptSheet(
                finalText: meeting.transcript,
                volatileText: "",
                isLive: false,
                turns: speakerTurns,
                onRename: { key, name in
                    MeetingPersistence.renameSpeaker(key: key, to: name, in: meeting, context: context)
                    loadSpeakerTurns()
                    MeetingPersistence.writeToAppGroup(for: meeting, context: context)
                }
            )
        }
        .onAppear { loadSpeakerTurns() }
        .alert("Reminders", isPresented: Binding(
            get: { reminders.message != nil || infoMessage != nil },
            set: { if !$0 { reminders.message = nil; infoMessage = nil } }
        )) {
            Button("OK", role: .cancel) { reminders.message = nil; infoMessage = nil }
        } message: {
            Text(reminders.message ?? infoMessage ?? "")
        }
        .onChange(of: meeting.scratchpad) { _, _ in try? context.save() }
        .onChange(of: meeting.title) { oldTitle, _ in
            try? context.save()
            MeetingPersistence.appGroupCopyRetitled(meeting, from: oldTitle)
            MeetingsSnapshotPublisher.publishStoreChanges(context: context)
        }
        .onDisappear { playback.stop() }
    }

    private var summary: MeetingSummary? {
        MeetingPersistence.summary(of: meeting)
    }

    private func loadSpeakerTurns() {
        let segments = MeetingPersistence.fetchTranscriptSegments(for: meeting.id, context: context)
        let labels = meeting.speakerLabels
        speakerTurns = SpeakerAssignment.turns(
            from: segments.map { TranscriptPiece(text: $0.text, start: $0.startTime, end: $0.endTime) },
            keys: segments.map(\.speakerKey),
            names: { key in labels.first { $0.key == key }?.name }
        )
    }

    private var bottomBar: some View {
        VStack(spacing: 0) {
            Divider()
            Group {
                if summarizer.state == .working {
                    HStack(spacing: 10) {
                        ProgressView()
                        Text("Writing the notes on device…")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                } else {
                    Button {
                        Task { await enhance() }
                    } label: {
                        Label("Enhance notes", systemImage: "sparkles")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 12)
        }
        .background(.bar)
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
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
                Button {
                    sendToReminders()
                } label: {
                    Label("Add to Reminders", systemImage: "list.bullet.clipboard")
                }
                .disabled(summary == nil)
                ShareLink(item: MeetingPersistence.markdown(for: meeting, context: context)) {
                    Label("Share notes", systemImage: "square.and.arrow.up")
                }
                if summary != nil {
                    Button {
                        Task { await enhance() }
                    } label: {
                        Label("Enhance again", systemImage: "sparkles")
                    }
                    .disabled(summarizer.state == .working)
                }
                if let url = audioURL, FileManager.default.fileExists(atPath: url.path) {
                    Button {
                        playback.toggle(url: url)
                    } label: {
                        Label(
                            playback.isPlaying ? "Pause recording" : "Play recording",
                            systemImage: playback.isPlaying ? "pause.circle" : "play.circle"
                        )
                    }
                }
            } label: {
                Label("More", systemImage: "ellipsis.circle")
            }
            .accessibilityLabel("More actions")
        }
    }

    private var audioURL: URL? {
        guard let fileName = meeting.audioFileName else { return nil }
        return MeetingNotesStore.audioFolder(for: meeting.id).appendingPathComponent(fileName)
    }

    private func enhance() async {
        try? context.save()
        let material = MeetingPersistence.labelledTranscript(for: meeting, context: context)
        await summarizer.summarize(transcript: material, scratchpad: meeting.scratchpad, title: meeting.title)
        if case .finished(let result) = summarizer.state {
            MeetingPersistence.update(meeting: meeting, summary: result, context: context)
            MeetingPersistence.replaceActionItems(of: meeting, with: result.actionItems, context: context)
            if meeting.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, !result.title.isEmpty {
                let oldTitle = meeting.title
                meeting.title = result.title
                MeetingPersistence.appGroupCopyRetitled(meeting, from: oldTitle)
            }
            try? context.save()
            MeetingPersistence.writeToAppGroup(for: meeting, context: context)
            MeetingsSnapshotPublisher.publishStoreChanges(context: context)
            notesMode = .enhanced
        }
    }

    private func sendToReminders() {
        let items = MeetingPersistence.fetchActionItems(for: meeting.id, context: context)
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
