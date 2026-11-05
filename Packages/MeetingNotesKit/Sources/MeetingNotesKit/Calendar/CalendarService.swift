import EventKit
import Foundation

/// A calendar event the user can attach a recording to.
public struct CalendarEventInfo: Identifiable, Hashable, Sendable {
    public let id: String
    public let title: String
    public let start: Date
    public let end: Date
    public let attendeeNames: [String]
    public let location: String?

    public init(
        id: String,
        title: String,
        start: Date,
        end: Date,
        attendeeNames: [String] = [],
        location: String? = nil
    ) {
        self.id = id
        self.title = title
        self.start = start
        self.end = end
        self.attendeeNames = attendeeNames
        self.location = location
    }
}

/// Reads today's calendar events so a recording can be attached to one.
@MainActor
public final class CalendarService: ObservableObject {
    public enum Access: Equatable, Sendable {
        case unknown
        case granted
        case denied
        case restricted
    }

    @Published public private(set) var access: Access = .unknown
    @Published public private(set) var events: [CalendarEventInfo] = []
    @Published public private(set) var message: String?

    private let store = EKEventStore()

    /// Asks for calendar access and loads today's events.
    public func loadToday() async {
        let granted = await requestAccess()
        guard granted else { return }

        let calendar = Calendar.current
        let startOfDay = calendar.startOfDay(for: Date())
        let endOfDay = calendar.date(byAdding: .day, value: 1, to: startOfDay) ?? Date()
        let predicate = store.predicateForEvents(withStart: startOfDay, end: endOfDay, calendars: nil)
        let matches = store.events(matching: predicate)
        var infos: [CalendarEventInfo] = []
        for event in matches {
            let identifier = event.eventIdentifier ?? event.calendarItemIdentifier
            let names: [String] = (event.attendees ?? []).map { $0.name ?? "" }
            infos.append(
                CalendarEventInfo(
                    id: identifier,
                    title: event.title ?? "",
                    start: event.startDate,
                    end: event.endDate,
                    attendeeNames: names,
                    location: event.location
                )
            )
        }
        events = infos.sorted { $0.start < $1.start }
        message = nil
    }

    /// Finds one event by identifier.
    public func event(with identifier: String) -> CalendarEventInfo? {
        events.first { $0.id == identifier }
    }

    /// Asks the system for calendar access.
    @discardableResult
    public func requestAccess() async -> Bool {
        let status = EKEventStore.authorizationStatus(for: .event)
        switch status {
        case .fullAccess, .writeOnly:
            access = .granted
            return true
        case .denied:
            access = .denied
            message = "Calendar access is off. Turn it on in Settings › MorningVault › Calendar."
            return false
        case .restricted:
            access = .restricted
            message = "Calendar access is restricted on this device."
            return false
        default:
            do {
                let granted = try await store.requestFullAccessToEvents()
                access = granted ? .granted : .denied
                if !granted {
                    message = "Calendar access is off. Turn it on in Settings › MorningVault › Calendar."
                }
                return granted
            } catch {
                access = .denied
                message = "Could not reach the calendar: \(error.localizedDescription)"
                return false
            }
        }
    }
}
