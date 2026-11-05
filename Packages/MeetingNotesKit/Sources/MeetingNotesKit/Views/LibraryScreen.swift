import SwiftData
import SwiftUI

/// The library of past meetings, with search over titles, notes and transcripts.
struct LibraryScreen: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \Meeting.startedAt, order: .reverse) private var meetings: [Meeting]
    @State private var searchText = ""

    var body: some View {
        NavigationStack {
            Group {
                if meetings.isEmpty {
                    EmptyStateView(
                        symbol: "waveform",
                        title: "No meetings yet",
                        message: "Record a meeting and it will show up here with its notes and transcript."
                    )
                } else {
                    List {
                        ForEach(filteredMeetings) { meeting in
                            NavigationLink {
                                MeetingDetailScreen(meeting: meeting)
                            } label: {
                                MeetingRow(meeting: meeting)
                            }
                        }
                        .onDelete(perform: delete)
                    }
                }
            }
            .navigationTitle("Meetings")
            .searchable(text: $searchText, prompt: "Search titles, notes and transcripts")
        }
    }

    private var filteredMeetings: [Meeting] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !query.isEmpty else { return meetings }
        return meetings.filter { meeting in
            meeting.title.lowercased().contains(query)
                || meeting.transcript.lowercased().contains(query)
                || meeting.scratchpad.lowercased().contains(query)
        }
    }

    private func delete(at offsets: IndexSet) {
        for index in offsets {
            let meeting = filteredMeetings[index]
            MeetingPersistence.deleteRecordings(for: meeting)
            context.delete(meeting)
        }
        try? context.save()
    }
}

/// One meeting in the library list.
struct MeetingRow: View {
    let meeting: Meeting

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(meeting.displayTitle)
                .font(.headline)
                .lineLimit(1)
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
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .padding(.vertical, 2)
    }
}
