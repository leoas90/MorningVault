import SwiftData
import SwiftUI

/// The recording screen: timer, level meter, notes and live transcript.
struct RecordScreen: View {
    @Environment(\.modelContext) private var context
    @Environment(\.vaultNotesSampleMode) private var sampleMode
    @StateObject private var session = RecordingSession()
    @State private var pane: Pane = .notes
    @State private var samplePhase: Double = 0

    /// Title the recording starts with, for example from a calendar event.
    var initialTitle: String = ""
    /// People taking part, filled in from a calendar event.
    var initialAttendees: [String] = []
    /// Calendar event the recording belongs to.
    var calendarEventID: String?
    /// Start recording as soon as the screen appears.
    var autoStart: Bool = false

    enum Pane: String, CaseIterable, Identifiable {
        case notes
        case transcript

        var id: String { rawValue }

        var title: String {
            switch self {
            case .notes: return "My notes"
            case .transcript: return "Transcript"
            }
        }

        var symbol: String {
            switch self {
            case .notes: return "square.and.pencil"
            case .transcript: return "text.alignleft"
            }
        }
    }

    var body: some View {
        if sampleMode {
            // The picture mode drops the navigation stack and the scroll view,
            // because neither can be drawn outside a running window.
            stack
                .padding(.horizontal)
                .padding(.bottom, 28)
                .task { runSampleAnimation() }
        } else {
            NavigationStack {
                ScrollView { stack }
                    .padding(.horizontal)
                    .padding(.bottom, 28)
                    .navigationTitle("Record")
                    .scrollDismissesKeyboard(.interactively)
                    .task {
                        if autoStart {
                            await session.start(
                                calendarEventID: calendarEventID,
                                title: initialTitle,
                                attendees: initialAttendees
                            )
                        }
                    }
            }
        }
    }

    private var stack: some View {
        VStack(spacing: 18) {
            if sampleMode {
                Text("Record")
                    .font(.largeTitle.weight(.bold))
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            if let banner = session.banner {
                BannerView(message: banner)
            }
            if let error = session.errorMessage {
                BannerView(message: error)
            }

            header
            meter
            controls
            panes

            if session.phase == .finished {
                finishedSection
            }
        }
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                Text(statusTitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                if !attendeeText.isEmpty {
                    Text(attendeeText)
                        .font(.footnote)
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            ElapsedTimeLabel(elapsed: displayedElapsed)
        }
    }

    private var attendeeText: String {
        if sampleMode { return "Ana, Ben, Chi" }
        return session.attendees.joined(separator: ", ")
    }

    private var displayedElapsed: TimeInterval {
        sampleMode ? 42 : session.elapsed
    }

    private var displayedHistory: [Double] {
        if sampleMode { return MeetingPreviewData.waveform(phase: samplePhase) }
        return session.levelHistory
    }

    private var displayedTranscript: String {
        if sampleMode { return MeetingPreviewData.sampleTranscript }
        return session.transcript
    }

    private var displayedNotes: String {
        if sampleMode { return MeetingPreviewData.sampleScratchpad }
        return session.scratchpad
    }

    private var statusTitle: String {
        if sampleMode { return "Recording" }
        switch session.phase {
        case .idle: return "Ready to record"
        case .recording: return "Recording"
        case .paused: return "Paused"
        case .finished: return "Saved"
        }
    }

    private var meter: some View {
        LevelMeter(history: displayedHistory)
            .padding(.vertical, 4)
    }

    private var controls: some View {
        VStack(spacing: 14) {
            RecordButton(
                isRecording: session.isRecording,
                isPaused: session.phase == .paused
            ) {
                toggleRecording()
            }

            if session.isRecording {
                HStack(spacing: 12) {
                    Button {
                        if session.phase == .paused {
                            session.resume()
                        } else {
                            session.pause()
                        }
                    } label: {
                        Label(
                            session.phase == .paused ? "Resume" : "Pause",
                            systemImage: session.phase == .paused ? "play.fill" : "pause.fill"
                        )
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)

                    Button(role: .destructive) {
                        Task { await session.stop(context: context) }
                    } label: {
                        Label("Stop", systemImage: "stop.fill")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                }
                .padding(.horizontal, 24)
            }
        }
        .frame(maxWidth: .infinity)
    }

    @ViewBuilder
    private var panes: some View {
        if sampleMode {
            VStack(spacing: 14) {
                notesPane
                transcriptPane
            }
        } else {
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .top, spacing: 14) {
                    notesPane
                    transcriptPane
                }
                VStack(spacing: 14) {
                    Picker("Show", selection: $pane) {
                        ForEach(Pane.allCases) { item in
                            Text(item.title).tag(item)
                        }
                    }
                    .pickerStyle(.segmented)

                    switch pane {
                    case .notes: notesPane
                    case .transcript: transcriptPane
                    }
                }
            }
        }
    }

    private var notesPane: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionHeader("My notes", systemImage: "square.and.pencil")
            ZStack(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color.primary.opacity(0.04))
                if displayedNotes.isEmpty {
                    Text("Type the points you want to remember. They are mixed with the transcript later.")
                        .font(.footnote)
                        .foregroundStyle(.tertiary)
                        .padding(12)
                }
                if sampleMode {
                    Text(displayedNotes)
                        .font(.body)
                        .padding(12)
                } else {
                    TextEditor(text: $session.scratchpad)
                        .font(.body)
                        .scrollContentBackground(.hidden)
                        .padding(8)
                }
            }
            .frame(minHeight: 150)
        }
    }

    private var transcriptPane: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionHeader("Transcript", systemImage: "text.alignleft")
            ZStack(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color.primary.opacity(0.04))
                if displayedTranscript.isEmpty {
                    Text(transcriptPlaceholder)
                        .font(.footnote)
                        .foregroundStyle(.tertiary)
                        .padding(12)
                } else {
                    Text(displayedTranscript)
                        .font(.body)
                        .textSelection(.enabled)
                        .padding(12)
                }
            }
            .frame(minHeight: 150)
        }
    }

    private var transcriptPlaceholder: String {
        switch session.phase {
        case .idle: return "The transcript shows up here while you record."
        case .recording, .paused: return "Listening…"
        case .finished: return "No speech was recognised for this recording."
        }
    }

    private var finishedSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            if case .finished(let summary) = session.summarizer.state {
                SummaryCard(summary: summary)
            } else {
                Button {
                    Task { await session.enhance(context: context) }
                } label: {
                    Label("Enhance notes", systemImage: "sparkles")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .disabled(session.summarizer.state == .working)

                switch session.summarizer.state {
                case .working:
                    HStack(spacing: 8) {
                        ProgressView()
                        Text("Writing the notes on device…")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                case .unavailable(let message):
                    BannerView(message: message)
                case .failed(let message):
                    BannerView(message: message)
                case .idle, .finished:
                    EmptyView()
                }
            }
        }
    }

    private func runSampleAnimation() {
        Task { @MainActor in
            while !Task.isCancelled {
                withAnimation(.linear(duration: 0.12)) {
                    samplePhase += 0.45
                }
                try? await Task.sleep(for: .milliseconds(80))
            }
        }
    }

    private func toggleRecording() {
        if session.isRecording {
            Task { await session.stop(context: context) }
        } else {
            Task { await session.start() }
        }
    }
}
