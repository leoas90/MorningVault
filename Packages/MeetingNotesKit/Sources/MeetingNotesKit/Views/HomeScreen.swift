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
    @State private var searchText = ""
    @State private var newMeeting: NewMeetingRequest?
    @State private var now = Date()

    var body: some View {
        NavigationStack {
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
                                NavigationLink {
                                    MeetingDetailScreen(meeting: meeting)
                                } label: {
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
            .searchable(text: $searchText, prompt: "Search titles, notes and transcripts")
            .refreshable { await calendar.loadToday() }
            .safeAreaInset(edge: .bottom) { newMeetingButton }
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
                now = Date()
                await calendar.loadToday()
            }
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
            MeetingPersistence.deleteRecordings(for: meeting)
            for item in MeetingPersistence.fetchActionItems(for: meeting.id, context: context) {
                context.delete(item)
            }
            context.delete(meeting)
        }
        try? context.save()
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
