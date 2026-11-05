import SwiftData
import SwiftUI

/// What a new meeting is started for: a calendar event, or nothing.
struct NewMeetingRequest: Identifiable {
    let id = UUID()
    var calendarEventID: String?
    var title: String = ""
    var attendees: [String] = []

    init() {}

    init(event: CalendarEventInfo) {
        calendarEventID = event.id
        title = event.title
        attendees = event.attendeeNames
    }
}

/// The first screen: what is coming up, what was recorded, and one button to
/// start a new meeting.
struct HomeScreen: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \Meeting.startedAt, order: .reverse) private var meetings: [Meeting]
    @StateObject private var calendar = CalendarService()
    @ObservedObject private var router = MeetingsRouter.shared
    @AppStorage(MarkdownCopiesSetting.key) private var saveMarkdownCopies = false
    @State private var searchText = ""
    @State private var newMeeting: NewMeetingRequest?
    @State private var showVoiceEnrollment = false
    @State private var now = Date()
    @State private var path: [UUID] = []

    var body: some View {
        NavigationStack(path: $path) {
            List {
                if isSearching == false, !upcomingEvents.isEmpty {
                    Section {
                        ForEach(upcomingEvents) { event in
                            UpNextRow(event: event, now: now) {
                                newMeeting = NewMeetingRequest(event: event)
                            }
                        }
                    } header: {
                        Text("Up next")
                    }
                }

                if meetings.isEmpty {
                    Section {
                        EmptyStateView(
                            symbol: "waveform",
                            title: "No meetings yet",
                            message: "Tap New meeting to record. Notes, transcript and a summary stay on this device."
                        )
                        .listRowBackground(Color.clear)
                    }
                } else if filteredMeetings.isEmpty {
                    Section {
                        EmptyStateView(
                            symbol: "magnifyingglass",
                            title: "No matches",
                            message: "Nothing in your titles, notes or transcripts matches “\(searchText)”."
                        )
                        .listRowBackground(Color.clear)
                    }
                } else {
                    ForEach(groupedMeetings, id: \.group) { bucket in
                        Section {
                            ForEach(bucket.items) { meeting in
                                NavigationLink(value: meeting.id) {
                                    MeetingRow(meeting: meeting)
                                }
                            }
                            .onDelete { offsets in
                                delete(offsets.map { bucket.items[$0] })
                            }
                        } header: {
                            Text(bucket.group.title)
                        }
                    }
                }
            }
            .listStyle(.automatic)
            .navigationTitle("Meetings")
            .inlineTitle()
            .navigationDestination(for: UUID.self) { meetingID in
                if let meeting = meetings.first(where: { $0.id == meetingID }) {
                    MeetingDetailScreen(meeting: meeting)
                } else {
                    EmptyStateView(symbol: "waveform.slash", title: "Meeting not found",
                                   message: "It may have been deleted.")
                }
            }
            .searchable(text: $searchText, prompt: "Search titles, notes and transcripts")
            .refreshable { await refresh() }
            .safeAreaInset(edge: .bottom) { newMeetingButton }
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Menu {
                        Button {
                            showVoiceEnrollment = true
                        } label: {
                            Label("Your voice", systemImage: "person.wave.2")
                        }
                        Toggle(isOn: $saveMarkdownCopies) {
                            Label("Also save Markdown copies", systemImage: "doc.text")
                        }
                    } label: {
                        Label("More", systemImage: "ellipsis.circle")
                    }
                    .accessibilityLabel("More actions")
                }
            }
            .sheet(isPresented: $showVoiceEnrollment) {
                VoiceEnrollmentScreen()
            }
            .sheet(item: $newMeeting) { request in
                MeetingScreen(
                    initialTitle: request.title,
                    initialAttendees: request.attendees,
                    calendarEventID: request.calendarEventID,
                    autoStart: true,
                    isModal: true
                )
            }
            .task {
                await refresh()
            }
            .onReceive(router.$pending) { route in
                // Emits the current route on appear and each new one (before `pending`
                // is set, so the value comes from the closure, and clearing waits a turn).
                guard let route else { return }
                Task { @MainActor in
                    router.clear(route)
                    await perform(route)
                }
            }
            .onChange(of: newMeeting?.id) { _, id in
                if id == nil { MeetingsSnapshotPublisher.publishStoreChanges(context: context) }
            }
        }
    }

    /// Reloads the calendar and republishes the widget snapshot.
    private func refresh() async {
        now = Date()
        if !ActiveRecordingRegistry.shared.isRecording {
            // A Live Activity left behind by a crash would otherwise stay on the Lock Screen.
            RecordingLiveActivity.endAll()
        }
        await calendar.loadToday()
        MeetingsSnapshotPublisher.publish(events: calendar.events, now: now, context: context)
    }

    /// Runs a route from a deep link or another tab's Record button.
    private func perform(_ route: MeetingsRoute) async {
        switch route {
        case .home:
            path.removeAll()
        case .record(let eventID, let title, let attendees):
            // One recording at a time: a tap while the recorder is up is ignored.
            guard newMeeting == nil, !ActiveRecordingRegistry.shared.isRecording else { return }
            path.removeAll()
            if let eventID, calendar.event(with: eventID) == nil {
                await calendar.loadToday()
            }
            guard newMeeting == nil else { return }
            var request = NewMeetingRequest()
            if let eventID, let event = calendar.event(with: eventID) {
                request = NewMeetingRequest(event: event)
            } else {
                request.calendarEventID = eventID
                request.title = title
                request.attendees = attendees
            }
            newMeeting = request
        case .open(let meetingID):
            guard meetings.contains(where: { $0.id == meetingID }) else { return }
            path = [meetingID]
        }
    }

    private var isSearching: Bool {
        !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// Today's events that have not ended yet.
    private var upcomingEvents: [CalendarEventInfo] {
        calendar.events.filter { $0.end > now }
    }

    private var filteredMeetings: [Meeting] {
        meetings.filter { meeting in
            MeetingSearch.matches(query: searchText, fields: [meeting.title, meeting.scratchpad, meeting.transcript])
        }
    }

    private var groupedMeetings: [(group: MeetingDayGroup, items: [Meeting])] {
        MeetingDayGroup.grouped(filteredMeetings, date: \.startedAt, now: now)
    }

    private var newMeetingButton: some View {
        Button {
            newMeeting = NewMeetingRequest()
        } label: {
            Label("New meeting", systemImage: "plus")
                .font(.headline)
                .padding(.horizontal, 22)
                .padding(.vertical, 14)
                .background(.tint, in: Capsule())
                .foregroundStyle(.white)
                .shadow(color: .black.opacity(0.15), radius: 12, y: 4)
        }
        .buttonStyle(.plain)
        .padding(.bottom, 8)
        .accessibilityLabel("New meeting")
        .accessibilityHint("Starts recording right away")
    }

    private func delete(_ items: [Meeting]) {
        for meeting in items {
            MeetingPersistence.delete(meeting, context: context)
        }
        try? context.save()
        MeetingsSnapshotPublisher.publishStoreChanges(context: context)
    }
}

/// One calendar event with a record button.
struct UpNextRow: View {
    let event: CalendarEventInfo
    let now: Date
    let onRecord: () -> Void

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(event.title.isEmpty ? "Untitled event" : event.title)
                    .font(.headline)
                    .lineLimit(2)
                HStack(spacing: 6) {
                    Text(timeText)
                    if !event.attendeeNames.isEmpty {
                        Text("·")
                        Text(event.attendeeNames.joined(separator: ", "))
                            .lineLimit(1)
                    }
                }
                .font(.footnote)
                .foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            Button(action: onRecord) {
                Label("Record", systemImage: "record.circle")
                    .font(.subheadline.weight(.semibold))
                    .labelStyle(.titleAndIcon)
            }
            .buttonStyle(.bordered)
            .tint(.red)
            .accessibilityLabel("Record \(event.title)")
        }
        .padding(.vertical, 4)
    }

    private var timeText: String {
        if event.start <= now, event.end > now {
            return "Now · until \(event.end.formatted(date: .omitted, time: .shortened))"
        }
        return "\(event.start.formatted(date: .omitted, time: .shortened)) – \(event.end.formatted(date: .omitted, time: .shortened))"
    }
}

/// One past meeting in the home list.
struct MeetingRow: View {
    let meeting: Meeting

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(meeting.displayTitle)
                .font(.headline)
                .lineLimit(1)
            HStack(spacing: 6) {
                Text(meeting.startedAt.formatted(date: .omitted, time: .shortened))
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
            if let line = summaryLine {
                Text(line)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .padding(.vertical, 3)
    }

    private var summaryLine: String? {
        guard let summary = MeetingPersistence.summary(of: meeting) else { return nil }
        let text = summary.summary.trimmingCharacters(in: .whitespacesAndNewlines)
        return text.isEmpty ? nil : text
    }
}
