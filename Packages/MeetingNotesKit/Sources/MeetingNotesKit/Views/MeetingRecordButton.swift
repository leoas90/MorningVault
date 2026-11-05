import SwiftUI

/// A button that starts a recording, optionally attached to a calendar event.
///
/// MorningVault puts this on the Brief tab's meeting card. By default a tap routes to
/// the Meetings tab through `MeetingsRouter` and starts the recording there, so the
/// widget, the Brief card and the Meetings home share one recording flow. Hosts
/// without the Meetings home can ask for a sheet instead.
public struct MeetingRecordButton: View {
    /// Where the recorder opens.
    public enum Presentation: Sendable {
        /// Switch to the Meetings home and record there (the default).
        case meetingsTab
        /// Present the recorder in a sheet over this view.
        case sheet
    }

    private let calendarEventID: String?
    private let title: String
    private let attendees: [String]
    private let label: String
    private let presentation: Presentation

    @State private var isPresenting = false

    /// Creates the button.
    ///
    /// - Parameters:
    ///   - calendarEventID: identifier of the calendar event the recording belongs to.
    ///   - title: title used for the meeting.
    ///   - attendees: people taking part.
    ///   - label: text on the button.
    ///   - presentation: route to the Meetings tab (default) or open a sheet.
    public init(
        calendarEventID: String? = nil,
        title: String = "",
        attendees: [String] = [],
        label: String = "Record",
        presentation: Presentation = .meetingsTab
    ) {
        self.calendarEventID = calendarEventID
        self.title = title
        self.attendees = attendees
        self.label = label
        self.presentation = presentation
    }

    public var body: some View {
        Button {
            switch presentation {
            case .meetingsTab:
                MeetingsRouter.shared.requestRecording(calendarEventID: calendarEventID, title: title, attendees: attendees)
            case .sheet:
                isPresenting = true
            }
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
