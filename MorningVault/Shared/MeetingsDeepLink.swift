import Foundation

// Shared by the app (parses), the widget (builds) and MeetingNotesKit (routes, tests).
// Foundation only.

/// The `morningvault://meetings…` links the widgets and the Live Activity open.
///
/// - `morningvault://meetings` — the Meetings tab.
/// - `morningvault://meetings/record` — start a new recording.
/// - `morningvault://meetings/record?event=<calendar event id>` — start one for that event.
/// - `morningvault://meetings/open?id=<meeting UUID>` — open a saved meeting.
enum MeetingsDeepLink: Equatable, Sendable {
    case meetings
    case record(calendarEventID: String?)
    case open(meetingID: UUID)

    static let scheme = "morningvault"
    static let host = "meetings"

    /// Parses a URL; `nil` when it is not a Meetings link.
    init?(url: URL) {
        guard url.scheme?.lowercased() == Self.scheme,
              url.host()?.lowercased() == Self.host,
              let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        else { return nil }

        let path = components.path.split(separator: "/", omittingEmptySubsequences: true).map(String.init)
        func query(_ name: String) -> String? {
            components.queryItems?.first { $0.name == name }?.value.flatMap { $0.isEmpty ? nil : $0 }
        }

        switch path.first {
        case nil:
            self = .meetings
        case "record":
            self = .record(calendarEventID: query("event"))
        case "open":
            guard let raw = query("id"), let id = UUID(uuidString: raw) else { return nil }
            self = .open(meetingID: id)
        default:
            return nil
        }
    }

    /// The link for this destination.
    var url: URL {
        var components = URLComponents()
        components.scheme = Self.scheme
        components.host = Self.host
        switch self {
        case .meetings:
            components.path = ""
        case .record(let eventID):
            components.path = "/record"
            if let eventID, !eventID.isEmpty {
                components.queryItems = [URLQueryItem(name: "event", value: eventID)]
            }
        case .open(let meetingID):
            components.path = "/open"
            components.queryItems = [URLQueryItem(name: "id", value: meetingID.uuidString)]
        }
        // Every piece above is URL-safe once URLComponents has percent-encoded the query.
        return components.url ?? URL(string: "\(Self.scheme)://\(Self.host)")!
    }
}
