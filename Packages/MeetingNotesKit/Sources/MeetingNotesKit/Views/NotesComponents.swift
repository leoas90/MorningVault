import SwiftData
import SwiftUI

/// Which notes the user is looking at after the meeting was enhanced.
enum NotesMode: String, CaseIterable, Identifiable {
    case enhanced
    case mine

    var id: String { rawValue }

    var title: String {
        switch self {
        case .enhanced: return "Enhanced"
        case .mine: return "My notes"
        }
    }
}

/// A segmented switch between the enhanced notes and the user's own.
struct NotesModeToggle: View {
    @Binding var mode: NotesMode

    var body: some View {
        Picker("Notes", selection: $mode) {
            ForEach(NotesMode.allCases) { item in
                Text(item.title).tag(item)
            }
        }
        .pickerStyle(.segmented)
    }
}

/// The full-width plain text scratchpad.
struct NotesEditor: View {
    @Binding var text: String
    var placeholder: String = "Type what matters to you. The transcript takes care of the rest."
    var minHeight: CGFloat = 280
    var focus: FocusState<Bool>.Binding?

    var body: some View {
        ZStack(alignment: .topLeading) {
            if text.isEmpty {
                Text(placeholder)
                    .font(.body)
                    .foregroundStyle(.tertiary)
                    .padding(.top, 8)
                    .padding(.leading, 5)
                    .allowsHitTesting(false)
            }
            editor
                .font(.body)
                .scrollContentBackground(.hidden)
                .scrollDisabled(true)
                .frame(minHeight: minHeight)
        }
        .accessibilityLabel("My notes")
    }

    @ViewBuilder
    private var editor: some View {
        if let focus {
            TextEditor(text: $text).focused(focus)
        } else {
            TextEditor(text: $text)
        }
    }
}

/// The editable title at the top of a meeting page.
struct MeetingTitleField: View {
    @Binding var title: String

    var body: some View {
        TextField("Untitled meeting", text: $title, axis: .vertical)
            .font(.title.weight(.bold))
            .lineLimit(1...3)
            .sentenceCapitalization()
            .accessibilityLabel("Meeting title")
    }
}

/// The enhanced notes rendered as clean sections.
struct EnhancedNotesView: View {
    let summary: MeetingSummary
    /// Meeting the action items belong to. When set, items are checkable.
    var meetingID: UUID?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            if !summary.summary.isEmpty {
                section("Summary", symbol: "text.alignleft") {
                    Text(summary.summary)
                        .font(.body)
                }
            }

            if !summary.keyPoints.isEmpty {
                section("Key points", symbol: "list.bullet") {
                    ForEach(Array(summary.keyPoints.enumerated()), id: \.offset) { _, point in
                        BulletRow(text: point)
                    }
                }
            }

            if !summary.decisions.isEmpty {
                section("Decisions", symbol: "checkmark.seal") {
                    ForEach(Array(summary.decisions.enumerated()), id: \.offset) { _, decision in
                        BulletRow(text: decision)
                    }
                }
            }

            if !summary.actionItems.isEmpty {
                section("Action items", symbol: "checklist") {
                    if let meetingID {
                        ActionItemsList(meetingID: meetingID, fallback: summary.actionItems)
                    } else {
                        ForEach(Array(summary.actionItems.enumerated()), id: \.offset) { _, item in
                            BulletRow(text: ActionItemsList.detail(for: item.text, owner: item.owner, due: item.due))
                        }
                    }
                }
            }

            if !summary.followUpQuestions.isEmpty {
                section("Follow-ups", symbol: "questionmark.circle") {
                    ForEach(Array(summary.followUpQuestions.enumerated()), id: \.offset) { _, question in
                        BulletRow(text: question)
                    }
                }
            }
        }
    }

    private func section<Content: View>(
        _ title: String,
        symbol: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionHeader(title, systemImage: symbol)
            content()
        }
        .card()
    }
}

/// Checkable action items of one meeting, read live from the store.
struct ActionItemsList: View {
    @Environment(\.modelContext) private var context
    @Query private var items: [ActionItemRecord]
    private let fallback: [ActionItem]

    init(meetingID: UUID, fallback: [ActionItem] = []) {
        _items = Query(
            filter: #Predicate<ActionItemRecord> { $0.meetingID == meetingID },
            sort: [SortDescriptor(\ActionItemRecord.createdAt)]
        )
        self.fallback = fallback
    }

    var body: some View {
        if items.isEmpty {
            ForEach(Array(fallback.enumerated()), id: \.offset) { _, item in
                BulletRow(text: Self.detail(for: item.text, owner: item.owner, due: item.due))
            }
        } else {
            ForEach(items) { item in
                Button {
                    item.isDone.toggle()
                    try? context.save()
                    MeetingsSnapshotPublisher.publishStoreChanges(context: context)
                } label: {
                    HStack(alignment: .firstTextBaseline, spacing: 10) {
                        Image(systemName: item.isDone ? "checkmark.circle.fill" : "circle")
                            .foregroundStyle(item.isDone ? Color.accentColor : Color.secondary)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(item.text)
                                .font(.body)
                                .strikethrough(item.isDone)
                                .foregroundStyle(item.isDone ? Color.secondary : Color.primary)
                            if let meta = Self.meta(owner: item.owner, due: item.due.map { DueFormatter.string(from: $0) }) {
                                Text(meta)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        Spacer(minLength: 0)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(item.text)
                .accessibilityValue(item.isDone ? "Done" : "Open")
                .accessibilityHint("Double tap to mark \(item.isDone ? "open" : "done")")
            }
        }
    }

    static func meta(owner: String?, due: String?) -> String? {
        var extras: [String] = []
        if let owner, !owner.isEmpty { extras.append(owner) }
        if let due, !due.isEmpty { extras.append("due \(due)") }
        return extras.isEmpty ? nil : extras.joined(separator: " · ")
    }

    static func detail(for text: String, owner: String?, due: String?) -> String {
        guard let meta = meta(owner: owner, due: due) else { return text }
        return text + " — " + meta
    }
}

/// A single bullet line.
struct BulletRow: View {
    let text: String

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Circle()
                .fill(Color.secondary.opacity(0.5))
                .frame(width: 5, height: 5)
            Text(text)
                .font(.body)
            Spacer(minLength: 0)
        }
    }
}

/// The transcript, shown in a sheet so the notes page stays clean.
///
/// Once speakers are known the text is shown as "Name: text" turns; tapping a
/// name renames that speaker everywhere in the meeting.
struct TranscriptSheet: View {
    @Environment(\.dismiss) private var dismiss
    let finalText: String
    let volatileText: String
    let isLive: Bool
    var isWorking = false
    /// Turns with speaker names. Empty until diarization finished.
    var turns: [SpokenTurn] = []
    var isIdentifyingSpeakers = false
    var speakerBanner: String?
    /// Called with the speaker key and the new name.
    var onRename: ((String, String) -> Void)?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    if isWorking {
                        HStack(spacing: 8) {
                            ProgressView()
                            Text("Transcribing the recording on device…")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                    }
                    if isIdentifyingSpeakers {
                        HStack(spacing: 8) {
                            ProgressView()
                            Text("Identifying speakers…")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                    }
                    if let speakerBanner {
                        Text(speakerBanner)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                    if finalText.isEmpty && volatileText.isEmpty && turns.isEmpty {
                        if !isWorking {
                            EmptyStateView(
                                symbol: "text.alignleft",
                                title: isLive ? "Listening…" : "No transcript",
                                message: isLive
                                    ? "Words show up here as they are recognized."
                                    : "Nothing was recognized for this meeting."
                            )
                        }
                    } else if hasSpeakers {
                        SpeakerTurnsView(turns: turns, onRename: onRename)
                    } else {
                        Text("\(finalText)\(Text(volatileText.isEmpty ? "" : " " + volatileText).foregroundStyle(.secondary))")
                            .font(.body)
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .padding()
            }
            .navigationTitle("Transcript")
            .inlineTitle()
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    private var hasSpeakers: Bool {
        !isLive && turns.contains { $0.name != nil }
    }
}

/// "Name: text" blocks, one per turn, with tap-to-rename on the name.
struct SpeakerTurnsView: View {
    let turns: [SpokenTurn]
    var onRename: ((String, String) -> Void)?
    @State private var renaming: SpokenTurn?
    @State private var newName = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            ForEach(turns) { turn in
                VStack(alignment: .leading, spacing: 3) {
                    if let key = turn.speakerKey, onRename != nil {
                        Button {
                            newName = turn.name ?? ""
                            renaming = turn
                        } label: {
                            Label(turn.name ?? "Unknown", systemImage: "person.fill")
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(turn.name == SpeakerLabel.youName ? Color.accentColor : Color.primary)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Speaker \(turn.name ?? "Unknown")")
                        .accessibilityHint("Double tap to rename")
                        .accessibilityIdentifier("rename-\(key)")
                    } else {
                        Label(turn.name ?? "Unknown", systemImage: "person.fill")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.secondary)
                    }
                    Text(turn.text)
                        .font(.body)
                        .textSelection(.enabled)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .alert("Rename speaker", isPresented: Binding(
            get: { renaming != nil },
            set: { if !$0 { renaming = nil } }
        ), presenting: renaming) { turn in
            TextField("Name", text: $newName)
            Button("Rename") {
                if let key = turn.speakerKey { onRename?(key, newName) }
                renaming = nil
            }
            Button("This is me") {
                if let key = turn.speakerKey { onRename?(key, SpeakerLabel.youName) }
                renaming = nil
            }
            Button("Cancel", role: .cancel) { renaming = nil }
        } message: { _ in
            Text("The name is used for every turn of this speaker in this meeting. “This is me” labels the speaker as You.")
        }
    }
}
