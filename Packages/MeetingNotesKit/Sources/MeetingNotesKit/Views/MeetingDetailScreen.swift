import SwiftData
import SwiftUI

/// Which part of a saved meeting is on screen.
enum DetailTab: String, CaseIterable, Identifiable {
    case summary
    case transcript
    case actions

    var id: String { rawValue }

    var title: String {
        switch self {
        case .summary: return "Summary"
        case .transcript: return "Transcript"
        case .actions: return "Actions"
        }
    }
}

/// A saved meeting: title, meta line, then Summary / Transcript / Actions.
struct MeetingDetailScreen: View {
    @Bindable var meeting: Meeting
    @Environment(\.modelContext) private var context
    @Environment(\.meetingsTheme) private var theme
    @StateObject private var playback = AudioPlaybackController()
    @StateObject private var reminders = RemindersService()
    @StateObject private var summarizer = MeetingSummarizer()
    @StateObject private var calendar = CalendarService()
    @State private var tab: DetailTab = .summary
    @State private var notesMode: NotesMode = .enhanced
    @State private var infoMessage: String?
    @State private var transcriptRows: [TranscriptRowModel] = []
    /// The calendar event this meeting was recorded for, when it still exists.
    @State private var linkedEvent: CalendarEventInfo?
    /// A write to the store that failed, shown until dismissed.
    @State private var saveError: UserMessage?
    @FocusState private var notesFocused: Bool

    /// Previews only: the tab to open on.
    init(meeting: Meeting, tab: DetailTab = .summary) {
        _meeting = Bindable(wrappedValue: meeting)
        _tab = State(initialValue: tab)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                MeetingTitleField(title: $meeting.title, style: .hero)

                Eyebrow(metaLine)
                    .padding(.top, MeetingsSpace.label)

                if let linkedEvent {
                    LinkedEventRow(event: linkedEvent)
                        .padding(.top, 12)
                }

                VStack(alignment: .leading, spacing: 12) {
                    if let saveError {
                        BannerView(saveError, symbol: "exclamationmark.triangle", onDismiss: { self.saveError = nil })
                    }
                    if let error = playback.errorMessage {
                        BannerView(message: error)
                    }
                    if case .unavailable(let message) = summarizer.state {
                        BannerView(message: message)
                    } else if case .failed(let message) = summarizer.state {
                        BannerView(message: message)
                    }
                }
                .padding(.top, hasBanners ? 16 : 0)

                SegmentedTabs(items: DetailTab.allCases, title: \.title, selection: $tab)
                    .padding(.top, 20)
                    .accessibilityLabel("Section")

                Group {
                    switch tab {
                    case .summary: summaryTab
                    case .transcript: transcriptTab
                    case .actions: actionsTab
                    }
                }
                .padding(.top, 24)
            }
            .padding(.horizontal, MeetingsSpace.margin)
            .padding(.top, 8)
            .padding(.bottom, 32)
        }
        .scrollDismissesKeyboard(.interactively)
        .themedPageBackground()
        .navigationTitle("")
        .inlineTitle()
        .safeAreaInset(edge: .bottom) {
            if tab == .summary, summary == nil || summarizer.state == .working {
                bottomBar
            }
        }
        .toolbar { toolbarContent }
        .onAppear {
            loadTranscript()
            if let id = meeting.calendarEventID {
                linkedEvent = calendar.resolveEvent(identifier: id)
            }
        }
        .alert("Reminders", isPresented: Binding(
            get: { reminders.message != nil || infoMessage != nil },
            set: { if !$0 { reminders.message = nil; infoMessage = nil } }
        )) {
            Button("OK", role: .cancel) { reminders.message = nil; infoMessage = nil }
        } message: {
            Text(reminders.message ?? infoMessage ?? "")
        }
        .onChange(of: meeting.scratchpad) { _, _ in
            attempt("Your notes could not be saved.") { try context.save() }
        }
        .onChange(of: meeting.title) { oldTitle, _ in
            attempt("The title could not be saved.") { try context.save() }
            MeetingPersistence.appGroupCopyRetitled(meeting, from: oldTitle)
            MeetingsSnapshotPublisher.publishStoreChanges(context: context)
        }
        .onDisappear { playback.stop() }
    }

    // MARK: - Tabs

    @ViewBuilder
    private var summaryTab: some View {
        if let summary {
            VStack(alignment: .leading, spacing: 0) {
                EnhancedNotesView(summary: summary, meetingID: meeting.id, includesActionItems: false)
                NotesSection("My notes") {
                    NotesEditor(text: $meeting.scratchpad, minHeight: 120, focus: $notesFocused)
                }
                .padding(.top, MeetingsSpace.sectionGap)
            }
        } else {
            VStack(alignment: .leading, spacing: 0) {
                Hairline()
                EmptyStateView(symbol: "sparkles", title: "No summary yet",
                               message: meeting.transcript.isEmpty
                                   ? "This meeting has no transcript, so there is nothing to summarize."
                                   : "Enhance notes turns the transcript and your notes into a summary, talking points and action items, on device.")
                Hairline()
                NotesSection("My notes") {
                    NotesEditor(text: $meeting.scratchpad, focus: $notesFocused)
                }
                .padding(.top, MeetingsSpace.sectionGap)
            }
        }
    }

    @ViewBuilder
    private var transcriptTab: some View {
        if transcriptRows.isEmpty {
            if meeting.transcript.isEmpty {
                EmptyStateView(symbol: "text.alignleft", title: "No transcript",
                               message: "Nothing was recognized for this meeting.")
            } else {
                TranscriptRows(rows: [TranscriptRowModel(id: 0, speakerKey: nil, name: nil, start: nil, text: meeting.transcript)])
            }
        } else {
            TranscriptRows(rows: transcriptRows, onRename: { key, name in
                attempt("The speaker name could not be saved.") {
                    try MeetingPersistence.renameSpeaker(key: key, to: name, in: meeting, context: context)
                }
                loadTranscript()
                MeetingPersistence.writeToAppGroup(for: meeting, context: context)
            })
        }
    }

    @ViewBuilder
    private var actionsTab: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let summary, !summary.actionItems.isEmpty {
                ActionItemsList(meetingID: meeting.id, fallback: summary.actionItems)
                MeetingsButton(title: "Add to Reminders", systemImage: "list.bullet.clipboard", role: .secondary) {
                    sendToReminders()
                }
                .padding(.top, 24)
            } else {
                EmptyStateView(symbol: "checklist", title: "No action items",
                               message: summary == nil
                                   ? "Enhance the notes on the Summary tab to pull out who does what."
                                   : "Nothing in this meeting needed a follow-up.")
            }
        }
    }

    // MARK: - Data

    private var summary: MeetingSummary? {
        MeetingPersistence.summary(of: meeting)
    }

    private var hasBanners: Bool {
        if saveError != nil || playback.errorMessage != nil { return true }
        if case .unavailable = summarizer.state { return true }
        if case .failed = summarizer.state { return true }
        return false
    }

    /// "Nov 6 · 25 min · 3 speakers"
    private var metaLine: String {
        let speakers = max(meeting.speakerLabels.count, meeting.attendeeNames.count)
        return MetaLine.join([
            meeting.startedAt.formatted(date: .abbreviated, time: .omitted),
            meeting.startedAt.formatted(date: .omitted, time: .shortened),
            MetaLine.duration(meeting.duration),
            speakers > 0 ? MetaLine.count(speakers, "speaker", "speakers") : nil
        ])
    }

    /// Runs a store write and turns a failure into the banner.
    private func attempt(_ what: String, _ work: () throws -> Void) {
        do {
            try work()
        } catch {
            saveError = UserMessage.from(error, context: what)
        }
    }

    private func loadTranscript() {
        let segments = MeetingPersistence.fetchTranscriptSegments(for: meeting.id, context: context)
        transcriptRows = TranscriptRowModel.rows(from: segments, labels: meeting.speakerLabels)
    }

    private var bottomBar: some View {
        VStack(spacing: 0) {
            Hairline()
            Group {
                if summarizer.state == .working {
                    WorkingLine("Writing the notes on device…")
                        .frame(maxWidth: .infinity)
                        .frame(height: MeetingsSpace.control)
                } else {
                    MeetingsButton(title: "Enhance notes", systemImage: "sparkles", role: .primary) {
                        Task { await enhance() }
                    }
                    .disabled(meeting.transcript.isEmpty && meeting.scratchpad.isEmpty)
                }
            }
            .padding(.horizontal, MeetingsSpace.margin)
            .padding(.vertical, 12)
        }
        .background(theme.backgroundColor.opacity(0.96))
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .primaryAction) {
            ShareLink(item: MeetingPersistence.markdown(for: meeting, context: context)) {
                Label("Export", systemImage: "square.and.arrow.up")
            }
            .accessibilityLabel("Export notes")
        }
        ToolbarItem(placement: .primaryAction) {
            Menu {
                Button {
                    sendToReminders()
                } label: {
                    Label("Add to Reminders", systemImage: "list.bullet.clipboard")
                }
                .disabled(summary == nil)
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
        return MeetingNotesStore.audioURL(for: meeting.id, fileName: fileName)
    }

    private func enhance() async {
        attempt("Your notes could not be saved.") { try context.save() }
        let material = MeetingPersistence.labelledTranscript(for: meeting, context: context)
        await summarizer.summarize(transcript: material, scratchpad: meeting.scratchpad, title: meeting.title)
        if case .finished(let result) = summarizer.state {
            attempt("The enhanced notes could not be saved.") {
                try MeetingPersistence.update(meeting: meeting, summary: result, context: context)
                // Matched by text, so ticked and exported items keep their state.
                try MeetingPersistence.replaceActionItems(of: meeting, with: result.actionItems, context: context)
                if meeting.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, !result.title.isEmpty {
                    let oldTitle = meeting.title
                    meeting.title = result.title
                    MeetingPersistence.appGroupCopyRetitled(meeting, from: oldTitle)
                }
                try context.save()
            }
            MeetingPersistence.writeToAppGroup(for: meeting, context: context)
            MeetingsSnapshotPublisher.publishStoreChanges(context: context)
            notesMode = .enhanced
            tab = .summary
        }
    }

    private func sendToReminders() {
        let items = MeetingPersistence.fetchActionItems(for: meeting.id, context: context)
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

/// The calendar event a meeting was recorded for: its time and place.
struct LinkedEventRow: View {
    @Environment(\.meetingsTheme) private var theme
    let event: CalendarEventInfo

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Image(systemName: "calendar")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(theme.inkSoft)
            Text(MetaLine.join([event.title.isEmpty ? "Calendar event" : event.title, timeText, event.location]))
                .font(MeetingsType.meta)
                .foregroundStyle(theme.inkSoft)
                .lineLimit(2)
        }
        .accessibilityElement(children: .combine)
    }

    private var timeText: String {
        let from = event.start.formatted(date: .omitted, time: .shortened)
        let to = event.end.formatted(date: .omitted, time: .shortened)
        return "\(from) – \(to)"
    }
}

// MARK: - Previews

#Preview("Detail · summary") {
    MeetingDetailPreview(scheme: .light, tab: .summary)
}

#Preview("Detail · summary · dark") {
    MeetingDetailPreview(scheme: .dark, tab: .summary)
}

#Preview("Detail · actions") {
    MeetingDetailPreview(scheme: .light, tab: .actions)
}

#Preview("Detail · actions · dark") {
    MeetingDetailPreview(scheme: .dark, tab: .actions)
}

#Preview("Detail · transcript") {
    MeetingDetailPreview(scheme: .light, tab: .transcript)
}

/// The enhanced sample meeting in a navigation stack, with the Warm palette.
struct MeetingDetailPreview: View {
    let scheme: ColorScheme
    let tab: DetailTab
    private let container = MeetingPreviewData.previewContainer()

    var body: some View {
        NavigationStack {
            if let meeting = MeetingPreviewData.sampleMeeting(in: container.mainContext) {
                MeetingDetailScreen(meeting: meeting, tab: tab)
            } else {
                Text("No sample meeting")
            }
        }
        .modelContainer(container)
        .meetingsTheme(MeetingPreviewData.warmTheme(scheme))
        .preferredColorScheme(scheme)
    }
}
