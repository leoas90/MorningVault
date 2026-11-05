import SwiftData
import SwiftUI

/// One meeting, with notes, transcript and audio.
struct MeetingDetailScreen: View {
    @Bindable var meeting: Meeting
    @Environment(\.modelContext) private var context
    @StateObject private var playback = AudioPlaybackController()
    @StateObject private var reminders = RemindersService()
    @State private var tab: DetailTab = .notes
    @State private var message: String?

    enum DetailTab: String, CaseIterable, Identifiable {
        case notes
        case transcript
        case audio

        var id: String { rawValue }

        var title: String {
            switch self {
            case .notes: return "Notes"
            case .transcript: return "Transcript"
            case .audio: return "Audio"
            }
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            Picker("Section", selection: $tab) {
                ForEach(DetailTab.allCases) { item in
                    Text(item.title).tag(item)
                }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal)
            .padding(.vertical, 8)

            switch tab {
            case .notes: notesTab
            case .transcript: transcriptTab
            case .audio: audioTab
            }
        }
        .navigationTitle(meeting.displayTitle)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                ShareLink(item: MeetingPersistence.markdown(for: meeting, context: context)) {
                    Label("Share", systemImage: "square.and.arrow.up")
                }
            }
        }
        .alert("Reminders", isPresented: Binding(
            get: { reminders.message != nil || message != nil },
            set: { if !$0 { reminders.message = nil; message = nil } }
        )) {
            Button("OK", role: .cancel) { reminders.message = nil; message = nil }
        } message: {
            Text(reminders.message ?? message ?? "")
        }
    }

    private var notesTab: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                if let summary = MeetingPersistence.summary(of: meeting) {
                    SummaryCard(summary: summary)
                }

                VStack(alignment: .leading, spacing: 8) {
                    SectionHeader("My notes", systemImage: "square.and.pencil")
                    TextEditor(text: $meeting.scratchpad)
                        .font(.body)
                        .scrollContentBackground(.hidden)
                        .padding(8)
                        .frame(minHeight: 120)
                        .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                        .onChange(of: meeting.scratchpad) {
                            try? context.save()
                        }
                }

                actionItems
            }
            .padding(.horizontal)
            .padding(.bottom, 24)
        }
    }

    private var actionItems: some View {
        let items = MeetingPersistence.fetchActionItems(for: meeting.id, context: context)
        return VStack(alignment: .leading, spacing: 8) {
            SectionHeader("Action items", systemImage: "checklist")
            if items.isEmpty {
                Text("No action items yet. Enhance the notes to pull them out.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(items) { item in
                    Button {
                        item.isDone.toggle()
                        try? context.save()
                    } label: {
                        HStack(alignment: .firstTextBaseline, spacing: 10) {
                            Image(systemName: item.isDone ? "checkmark.circle.fill" : "circle")
                                .foregroundStyle(item.isDone ? Color.accentColor : Color.secondary)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(item.text)
                                    .strikethrough(item.isDone)
                                    .foregroundStyle(item.isDone ? Color.secondary : Color.primary)
                                if let owner = item.owner, !owner.isEmpty {
                                    Text(owner)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            Spacer(minLength: 0)
                        }
                    }
                    .buttonStyle(.plain)
                }

                Button {
                    let drafts = items.filter { !$0.isDone }.map {
                        ActionItem(text: $0.text, owner: $0.owner, due: $0.due.map { DueFormatter.string(from: $0) })
                    }
                    Task {
                        do {
                            let count = try await reminders.export(drafts)
                            for item in items {
                                item.exportedToReminders = true
                            }
                            try? context.save()
                            if count == 0 {
                                message = "There was nothing open to send."
                            }
                        } catch {
                            message = error.localizedDescription
                        }
                    }
                } label: {
                    Label("Send open items to Reminders", systemImage: "list.bullet.clipboard")
                }
                .buttonStyle(.bordered)
            }
        }
    }

    private var transcriptTab: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                if meeting.transcript.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    EmptyStateView(
                        symbol: "text.alignleft",
                        title: "No transcript",
                        message: "This recording was not transcribed on device."
                    )
                } else {
                    Text(meeting.transcript)
                        .font(.body)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .padding(.horizontal)
            .padding(.bottom, 24)
        }
    }

    private var audioTab: some View {
        VStack(spacing: 16) {
            if let url = audioURL, FileManager.default.fileExists(atPath: url.path) {
                Button {
                    playback.toggle(url: url)
                } label: {
                    Label(
                        playback.isPlaying ? "Pause" : "Play recording",
                        systemImage: playback.isPlaying ? "pause.circle.fill" : "play.circle.fill"
                    )
                    .font(.title2)
                }
                .buttonStyle(.plain)

                Text(MarkdownExporter.durationText(meeting.duration))
                    .font(.system(.body, design: .monospaced))
                    .foregroundStyle(.secondary)
            } else {
                EmptyStateView(
                    symbol: "waveform",
                    title: "No recording",
                    message: "The audio file for this meeting is not on this device."
                )
            }

            if let error = playback.errorMessage {
                BannerView(message: error)
            }
        }
        .padding()
        .frame(maxWidth: .infinity)
    }

    private var audioURL: URL? {
        guard let fileName = meeting.audioFileName else { return nil }
        return MeetingNotesStore.audioFolder(for: meeting.id).appendingPathComponent(fileName)
    }
}
