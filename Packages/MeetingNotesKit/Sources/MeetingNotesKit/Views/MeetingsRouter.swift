import Combine
import Foundation

/// Where the Meetings screen should go next. Set by deep links (widgets, Live Activity)
/// and by `MeetingRecordButton` on other tabs; consumed by the home screen.
public enum MeetingsRoute: Equatable, Sendable {
    /// Show the Meetings home.
    case home
    /// Start a new recording, filed under a calendar event when one is given. The home
    /// screen fills in the title and attendees from the calendar when it knows the event.
    case record(calendarEventID: String?, title: String, attendees: [String])
    /// Open a saved meeting.
    case open(meetingID: UUID)
}

/// Single entry point for "go to Meetings and do X".
///
/// The host app switches to the Meetings tab whenever `pending` becomes non-nil
/// (`ContentView` observes it); `HomeScreen` then performs the route and clears it.
/// A route set before the home screen exists is kept until it appears.
@MainActor
public final class MeetingsRouter: ObservableObject {
    public static let shared = MeetingsRouter()

    @Published public private(set) var pending: MeetingsRoute?

    private init() {}

    /// Queues a route.
    public func go(_ route: MeetingsRoute) {
        pending = route
    }

    /// Routes a `morningvault://meetings…` URL. Returns `false` for any other URL.
    @discardableResult
    public func handle(url: URL) -> Bool {
        guard let link = MeetingsDeepLink(url: url) else { return false }
        switch link {
        case .meetings:
            go(.home)
        case .record(let eventID):
            go(.record(calendarEventID: eventID, title: "", attendees: []))
        case .open(let meetingID):
            go(.open(meetingID: meetingID))
        }
        return true
    }

    /// Starts a recording for a calendar event (or a blank one).
    public func requestRecording(calendarEventID: String? = nil, title: String = "", attendees: [String] = []) {
        go(.record(calendarEventID: calendarEventID, title: title, attendees: attendees))
    }

    /// Clears `route` once the home screen has taken it; a newer route stays queued.
    func clear(_ route: MeetingsRoute) {
        if pending == route { pending = nil }
    }
}
