import SwiftUI

/// The recording screen in a sheet, used by the record button and the calendar.
struct RecordSheetView: View {
    @Environment(\.dismiss) private var dismiss

    let calendarEventID: String?
    let title: String
    let attendees: [String]

    var body: some View {
        NavigationStack {
            RecordScreen(
                initialTitle: title,
                initialAttendees: attendees,
                calendarEventID: calendarEventID,
                autoStart: true
            )
            .navigationTitle("Recording")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
        }
    }
}
