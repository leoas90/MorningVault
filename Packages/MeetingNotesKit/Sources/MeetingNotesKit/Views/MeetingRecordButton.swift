import SwiftUI

/// A button that starts a recording, optionally attached to a calendar event.
///
/// MorningVault can put this on the calendar card: the meeting page opens in a
/// sheet, asks for permission, starts recording and is filed under the event.
public struct MeetingRecordButton: View {
    private let calendarEventID: String?
    private let title: String
    private let attendees: [String]
    private let label: String

    @State private var isPresenting = false

    /// Creates the button.
    ///
    /// - Parameters:
    ///   - calendarEventID: identifier of the calendar event the recording belongs to.
    ///   - title: title used for the meeting.
    ///   - attendees: people taking part.
    ///   - label: text on the button.
    public init(
        calendarEventID: String? = nil,
        title: String = "",
        attendees: [String] = [],
        label: String = "Record"
    ) {
        self.calendarEventID = calendarEventID
        self.title = title
        self.attendees = attendees
        self.label = label
    }

    public var body: some View {
        Button {
            isPresenting = true
        } label: {
            Label(label, systemImage: "record.circle")
        }
        .accessibilityLabel(title.isEmpty ? label : "\(label) \(title)")
        .sheet(isPresented: $isPresenting) {
            MeetingScreen(
                initialTitle: title,
                initialAttendees: attendees,
                calendarEventID: calendarEventID,
                autoStart: true,
                isModal: true
            )
        }
    }
}
