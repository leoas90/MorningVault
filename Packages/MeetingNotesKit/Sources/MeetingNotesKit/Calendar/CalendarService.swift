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
        /// Full access: events can be listed.
        case granted
        /// The user allowed adding events only. Nothing can be listed.
        case writeOnly
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
        events = matches.map(Self.info(for:)).sorted { $0.start < $1.start }
        message = nil
    }

    /// Finds one of today's loaded events by identifier.
    public func event(with identifier: String) -> CalendarEventInfo? {
        events.first { $0.id == identifier }
    }

    /// Looks an event up in the calendar by the identifier a meeting stored.
    ///
    /// Reads only; never prompts. Returns `nil` without full access or when
    /// the event is gone.
    public func resolveEvent(identifier: String) -> CalendarEventInfo? {
        guard Self.currentStatus() == .fullAccess else { return nil }
        if let event = store.event(withIdentifier: identifier) {
            return Self.info(for: event)
        }
        if let event = store.calendarItem(withIdentifier: identifier) as? EKEvent {
            return Self.info(for: event)
        }
        return nil
    }

    /// Asks the system for calendar access. Only full access counts: listing
    /// events needs it, and write-only access would make `events(matching:)`
    /// come back empty.
    @discardableResult
    public func requestAccess() async -> Bool {
        switch Self.currentStatus() {
        case .fullAccess:
            access = .granted
            return true
        case .writeOnly:
            access = .writeOnly
            message = "Calendar access is add-only. Allow full access in Settings › MorningVault › Calendar to see today's events."
            return false
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

    /// The system's answer right now. The class method is the only form
    /// EventKit offers (there is no instance variant in the iOS 27.2 SDK).
    static func currentStatus() -> EKAuthorizationStatus {
        EKEventStore.authorizationStatus(for: .event)
    }

    private static func info(for event: EKEvent) -> CalendarEventInfo {
        let identifier = event.eventIdentifier ?? event.calendarItemIdentifier
        let names = (event.attendees ?? [])
            .compactMap { $0.name?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        return CalendarEventInfo(
            id: identifier,
            title: event.title ?? "",
            start: event.startDate,
            end: event.endDate,
            attendeeNames: names,
            location: event.location
        )
    }
}
