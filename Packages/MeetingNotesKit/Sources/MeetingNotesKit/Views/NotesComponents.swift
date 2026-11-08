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
        SegmentedTabs(items: NotesMode.allCases, title: \.title, selection: $mode)
            .accessibilityLabel("Notes")
    }
}

/// The full-width plain text scratchpad.
struct NotesEditor: View {
    @Environment(\.meetingsTheme) private var theme
    @Binding var text: String
    var placeholder: String = "Type what matters to you. The transcript takes care of the rest."
    var minHeight: CGFloat = 200
    var focus: FocusState<Bool>.Binding?

    var body: some View {
        ZStack(alignment: .topLeading) {
            if text.isEmpty {
                Text(placeholder)
                    .font(MeetingsType.body)
                    .lineSpacing(6)
                    .foregroundStyle(theme.inkSoft.opacity(0.7))
                    .padding(.top, 8)
                    .padding(.leading, 5)
                    .allowsHitTesting(false)
            }
            editor
                .font(MeetingsType.body)
                .lineSpacing(6)
                .foregroundStyle(theme.ink)
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
    enum Style { case hero, compact }

    @Environment(\.meetingsTheme) private var theme
    @Binding var title: String
    var style: Style = .hero

    var body: some View {
        TextField("", text: $title, prompt: Text("Untitled meeting").foregroundStyle(theme.inkSoft), axis: .vertical)
            .font(style == .hero ? MeetingsType.meetingTitle : .system(size: 20, weight: .semibold))
            .foregroundStyle(theme.ink)
            .lineLimit(1...3)
            .sentenceCapitalization()
            .accessibilityLabel("Meeting title")
    }
}

/// The enhanced notes rendered as eyebrow sections with hairline lists.
struct EnhancedNotesView: View {
    @Environment(\.meetingsTheme) private var theme
    let summary: MeetingSummary
    /// Meeting the action items belong to. When set, items are checkable.
    var meetingID: UUID?
    /// Leave the action items out (the detail screen shows them on their own tab).
    var includesActionItems = true

    var body: some View {
        VStack(alignment: .leading, spacing: MeetingsSpace.sectionGap) {
            if !summary.summary.isEmpty {
                NotesSection("Summary") {
                    Text(summary.summary)
                        .font(MeetingsType.body)
                        .lineSpacing(6)
                        .foregroundStyle(theme.ink)
                        .textSelection(.enabled)
                }
            }

            if !summary.keyPoints.isEmpty {
                NotesSection("Talking points") {
                    HairlineList(summary.keyPoints)
                }
            }

            if !summary.decisions.isEmpty {
                NotesSection("Decisions") {
                    HairlineList(summary.decisions)
                }
            }

            if includesActionItems, !summary.actionItems.isEmpty {
                NotesSection("Action items") {
                    if let meetingID {
                        ActionItemsList(meetingID: meetingID, fallback: summary.actionItems)
                    } else {
                        HairlineList(summary.actionItems.map {
                            ActionItemsList.detail(for: $0.text, owner: $0.owner, due: $0.due)
                        })
                    }
                }
            }

            if !summary.followUpQuestions.isEmpty {
                NotesSection("Open questions") {
                    HairlineList(summary.followUpQuestions)
                }
            }
        }
    }
}

/// Eyebrow label, 8 pt gap, then the content.
struct NotesSection<Content: View>: View {
    let title: String
    @ViewBuilder let content: () -> Content

    init(_ title: String, @ViewBuilder content: @escaping () -> Content) {
        self.title = title
        self.content = content
    }

    var body: some View {
        VStack(alignment: .leading, spacing: MeetingsSpace.label) {
            Eyebrow(title)
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Plain sentences separated by hairlines.
struct HairlineList: View {
    @Environment(\.meetingsTheme) private var theme
    let items: [String]

    init(_ items: [String]) {
        self.items = items
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(items.enumerated()), id: \.offset) { index, item in
                Text(item)
                    .font(MeetingsType.body)
                    .lineSpacing(6)
                    .foregroundStyle(theme.ink)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 12)
                    .textSelection(.enabled)
                if index < items.count - 1 {
                    Hairline()
                }
            }
        }
    }
}

/// Checkable action items of one meeting, read live from the store.
struct ActionItemsList: View {
    @Environment(\.modelContext) private var context
    @Query private var items: [ActionItemRecord]
    @State private var saveError: UserMessage?
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
            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(fallback.enumerated()), id: \.offset) { index, item in
                    ActionItemRow(
                        text: item.text,
                        owner: item.owner,
                        due: item.due,
                        isDone: false,
                        onToggle: nil
                    )
                    if index < fallback.count - 1 { Hairline() }
                }
            }
        } else {
            VStack(alignment: .leading, spacing: 0) {
                if let saveError {
                    BannerView(saveError, symbol: "exclamationmark.triangle", onDismiss: { self.saveError = nil })
                        .padding(.bottom, 12)
                }
                ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                    ActionItemRow(
                        text: item.text,
                        owner: item.owner,
                        due: item.due.map { DueFormatter.string(from: $0) },
                        isDone: item.isDone,
                        onToggle: { toggle(item) }
                    )
                    if index < items.count - 1 { Hairline() }
                }
            }
        }
    }

    private func toggle(_ item: ActionItemRecord) {
        item.isDone.toggle()
        do {
            try context.save()
            saveError = nil
        } catch {
            saveError = UserMessage.from(error, context: "The change could not be saved.")
        }
        MeetingsSnapshotPublisher.publishStoreChanges(context: context)
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

/// One action item: 22 pt circle checkbox, text, owner and due pills.
struct ActionItemRow: View {
    @Environment(\.meetingsTheme) private var theme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let text: String
    var owner: String?
    var due: String?
    /// Shown as a 13 pt eyebrow above the text on the cross-meeting list.
    var context: String?
    let isDone: Bool
    let onToggle: (() -> Void)?

    var body: some View {
        Button {
            withAnimation(reduceMotion ? nil : .smooth(duration: 0.2)) { onToggle?() }
        } label: {
            HStack(alignment: .top, spacing: 12) {
                CheckCircle(isDone: isDone)
                    .padding(.top, 1)
                VStack(alignment: .leading, spacing: 6) {
                    if let context {
                        Eyebrow(context)
                    }
                    Text(text)
                        .font(MeetingsType.body)
                        .lineSpacing(4)
                        .strikethrough(isDone, color: theme.inkSoft)
                        .foregroundStyle(isDone ? theme.inkSoft : theme.ink)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    if owner != nil || due != nil {
                        HStack(spacing: 6) {
                            if let owner, !owner.isEmpty {
                                TintPill(text: owner)
                            }
                            if let due, !due.isEmpty {
                                TintPill(text: "Due \(due)")
                            }
                        }
                    }
                }
            }
            .padding(.vertical, 12)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(onToggle == nil)
        .accessibilityLabel(text)
        .accessibilityValue(isDone ? "Done" : "Open")
        .accessibilityHint(onToggle == nil ? "" : "Double tap to mark \(isDone ? "open" : "done")")
    }
}

/// One transcript row as the screens show it: who, when, and what was said.
struct TranscriptRowModel: Identifiable, Equatable {
    let id: Int
    var speakerKey: String?
    var name: String?
    var start: TimeInterval?
    var text: String

    /// Groups consecutive segments of one speaker, keeping the first start time.
    static func rows(from segments: [TranscriptSegment], labels: [SpeakerLabel]) -> [TranscriptRowModel] {
        var result: [TranscriptRowModel] = []
        for segment in segments.sorted(by: { $0.index < $1.index }) {
            let text = segment.text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { continue }
            let name = labels.first { $0.key == segment.speakerKey }?.name
            if let last = result.last, last.name == name, last.speakerKey == segment.speakerKey {
                result[result.count - 1].text += " " + text
            } else {
                result.append(TranscriptRowModel(
                    id: result.count,
                    speakerKey: segment.speakerKey,
                    name: name,
                    start: segment.startTime,
                    text: text
                ))
            }
        }
        return result
    }

    /// Rows from turns that carry no timing.
    static func rows(from turns: [SpokenTurn]) -> [TranscriptRowModel] {
        turns.map { TranscriptRowModel(id: $0.index, speakerKey: $0.speakerKey, name: $0.name, start: nil, text: $0.text) }
    }

    /// `3:07` or `1:02:07`.
    static func timestamp(_ seconds: TimeInterval) -> String {
        let total = max(0, Int(seconds))
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        let secs = total % 60
        if hours > 0 { return String(format: "%d:%02d:%02d", hours, minutes, secs) }
        return String(format: "%d:%02d", minutes, secs)
    }
}

/// Hairline-separated transcript rows: speaker eyebrow, timestamp, text 17/25. Tapping a
/// speaker renames that speaker everywhere in the meeting.
struct TranscriptRows: View {
    @Environment(\.meetingsTheme) private var theme
    let rows: [TranscriptRowModel]
    /// Text the recogniser has not settled on yet, appended to the last row in soft ink.
    var volatileText: String = ""
    /// Called with the speaker key and the new name.
    var onRename: ((String, String) -> Void)?
    @State private var renaming: TranscriptRowModel?
    @State private var newName = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(rows.enumerated()), id: \.element.id) { index, row in
                VStack(alignment: .leading, spacing: 6) {
                    if row.speakerKey != nil || row.name != nil || row.start != nil {
                        HStack(spacing: 8) {
                            speakerLabel(row)
                            if let start = row.start {
                                Text(TranscriptRowModel.timestamp(start))
                                    .font(MeetingsType.metaMono)
                                    .foregroundStyle(theme.inkSoft)
                                    .monospacedDigit()
                            }
                        }
                    }
                    if index == rows.count - 1, !volatileText.isEmpty {
                        Text("\(row.text) \(Text(volatileText).foregroundStyle(theme.inkSoft))")
                            .font(MeetingsType.body)
                            .lineSpacing(6)
                            .foregroundStyle(theme.ink)
                            .textSelection(.enabled)
                    } else {
                        Text(row.text)
                            .font(MeetingsType.body)
                            .lineSpacing(6)
                            .foregroundStyle(theme.ink)
                            .textSelection(.enabled)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 14)
                if index < rows.count - 1 { Hairline() }
            }
        }
        .alert("Rename speaker", isPresented: Binding(
            get: { renaming != nil },
            set: { if !$0 { renaming = nil } }
        ), presenting: renaming) { row in
            TextField("Name", text: $newName)
            Button("Rename") {
                if let key = row.speakerKey { onRename?(key, newName) }
                renaming = nil
            }
            Button("This is me") {
                if let key = row.speakerKey { onRename?(key, SpeakerLabel.youName) }
                renaming = nil
            }
            Button("Cancel", role: .cancel) { renaming = nil }
        } message: { _ in
            Text("The name is used for every turn of this speaker in this meeting. “This is me” labels the speaker as You.")
        }
    }

    @ViewBuilder
    private func speakerLabel(_ row: TranscriptRowModel) -> some View {
        let isYou = row.name == SpeakerLabel.youName
        let title = row.name ?? (row.speakerKey == nil ? "Transcript" : "Unknown")
        if let key = row.speakerKey, onRename != nil {
            Button {
                newName = row.name ?? ""
                renaming = row
            } label: {
                Eyebrow(title, color: isYou ? theme.accentColor : nil)
                    .frame(minHeight: 22)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Speaker \(title)")
            .accessibilityHint("Double tap to rename")
            .accessibilityIdentifier("rename-\(key)")
        } else {
            Eyebrow(title, color: isYou ? theme.accentColor : nil)
        }
    }
}

/// The transcript in a sheet, used by the recording screen's toolbar.
///
/// Once speakers are known the text is shown as speaker rows; tapping a name renames that
/// speaker everywhere in the meeting.
struct TranscriptSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.meetingsTheme) private var theme
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
                        WorkingLine("Transcribing the recording on device…")
                    }
                    if isIdentifyingSpeakers {
                        WorkingLine("Identifying speakers…")
                    }
                    if let speakerBanner {
                        Text(speakerBanner)
                            .font(MeetingsType.meta)
                            .foregroundStyle(theme.inkSoft)
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
                        TranscriptRows(rows: TranscriptRowModel.rows(from: turns), onRename: onRename)
                    } else {
                        TranscriptRows(
                            rows: [TranscriptRowModel(id: 0, speakerKey: nil, name: nil, start: nil, text: finalText)],
                            volatileText: volatileText
                        )
                    }
                }
                .padding(MeetingsSpace.margin)
            }
            .themedPageBackground()
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

/// Spinner plus a short sentence, for work that runs on device.
struct WorkingLine: View {
    @Environment(\.meetingsTheme) private var theme
    let text: String

    init(_ text: String) {
        self.text = text
    }

    var body: some View {
        HStack(spacing: 10) {
            ProgressView()
                .controlSize(.small)
            Text(text)
                .font(MeetingsType.secondary)
                .foregroundStyle(theme.inkSoft)
        }
        .accessibilityElement(children: .combine)
    }
}
