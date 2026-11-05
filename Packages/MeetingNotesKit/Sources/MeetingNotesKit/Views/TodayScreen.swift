import SwiftUI

/// The day view: today's calendar events, each with a record button.
struct TodayScreen: View {
    @StateObject private var calendar = CalendarService()
    @State private var recordingEvent: CalendarEventInfo?

    var body: some View {
        NavigationStack {
            Group {
                if calendar.events.isEmpty {
                    if calendar.access == .denied {
                        EmptyStateView(
                            symbol: "calendar.badge.exclamationmark",
                            title: "Calendar is off",
                            message: calendar.message ?? "Turn on calendar access to see today's meetings."
                        )
                    } else {
                        EmptyStateView(
                            symbol: "calendar",
                            title: "Nothing on the calendar",
                            message: "Meetings you have today will show up here, ready to record."
                        )
                    }
                } else {
                    List {
                        Section {
                            ForEach(calendar.events) { event in
                                EventRow(event: event) {
                                    recordingEvent = event
                                }
                            }
                        } header: {
                            Text(Date.now.formatted(date: .complete, time: .omitted))
                        }
                    }
                }
            }
            .navigationTitle("Today")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        Task { await calendar.loadToday() }
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    .accessibilityLabel("Refresh the calendar")
                }
            }
            .task {
                await calendar.loadToday()
            }
            .sheet(item: $recordingEvent) { event in
                RecordSheetView(
                    calendarEventID: event.id,
                    title: event.title,
                    attendees: event.attendeeNames
                )
            }
        }
    }
}

/// One calendar event with a record button.
struct EventRow: View {
    let event: CalendarEventInfo
    let onRecord: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(event.start, format: .dateTime.hour().minute())
                    .font(.subheadline.monospacedDigit())
                    .foregroundStyle(.secondary)
                Text(event.title)
                    .font(.headline)
                if !event.attendeeNames.isEmpty {
                    Text(event.attendeeNames.joined(separator: ", "))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 0)
            Button(action: onRecord) {
                Image(systemName: "record.circle")
                    .font(.title2)
            }
            .buttonStyle(.borderless)
            .accessibilityLabel("Record \(event.title)")
        }
        .padding(.vertical, 4)
    }
}
