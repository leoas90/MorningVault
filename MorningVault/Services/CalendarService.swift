import Foundation
import EventKit

/// EventKit service — reads today's calendar events
/// No write access requested. Data stays on-device.
///
/// Main-actor isolated: `isAuthorized` is read straight from SwiftUI view bodies and was
/// previously also written from a background thread, which is the data race this removes.
/// One store, one thread — EKEventStore is not documented as thread-safe.
@MainActor
final class CalendarService: ObservableObject {
    static let shared = CalendarService()

    private let store = EKEventStore()
    @Published var isAuthorized = false
    @Published var lastError: String?

    init() {
        // Reflect an existing grant at launch; previously the Settings row showed "not
        // authorized" until the user tapped it again in this session.
        isAuthorized = EKEventStore.authorizationStatus(for: .event) == .fullAccess
    }

    // MARK: - Authorization

    func requestAuthorization() async -> Bool {
        do {
            let granted = try await store.requestFullAccessToEvents()
            isAuthorized = granted
            return granted
        } catch {
            lastError = error.localizedDescription
            return false
        }
    }

    // MARK: - Fetch Today's Events

    func fetchTodayEvents() async -> [CalendarEvent] {
        guard isAuthorized else { _ = await requestAuthorization(); return [] }

        let calendar = Calendar.current
        let now = Date()
        let startOfDay = calendar.startOfDay(for: now)
        let endOfDay = calendar.date(byAdding: .day, value: 1, to: startOfDay)!

        let predicate = store.predicateForEvents(withStart: startOfDay, end: endOfDay, calendars: nil)
        let events = Self.uniqueEvents(store.events(matching: predicate))

        return events.map { ek in
            CalendarEvent(
                id: ek.eventIdentifier ?? ek.calendarItemIdentifier,
                title: ek.title ?? "(No title)",
                startDate: ek.startDate,
                endDate: ek.endDate,
                isAllDay: ek.isAllDay,
                location: ek.location,
                notes: ek.notes,
                calendarColor: ek.calendar.cgColor.hexString
            )
        }
    }

    // MARK: - Fetch Upcoming (next 7 days)

    func fetchUpcomingEvents(days: Int = 7) async -> [CalendarEvent] {
        guard isAuthorized else { _ = await requestAuthorization(); return [] }

        let calendar = Calendar.current
        let now = Date()
        let startOfDay = calendar.startOfDay(for: now)
        let endDate = calendar.date(byAdding: .day, value: days, to: startOfDay)!

        let predicate = store.predicateForEvents(withStart: startOfDay, end: endDate, calendars: nil)
        let events = Self.uniqueEvents(store.events(matching: predicate))

        return events.map { ek in
            CalendarEvent(
                id: ek.eventIdentifier ?? ek.calendarItemIdentifier,
                title: ek.title ?? "(No title)",
                startDate: ek.startDate,
                endDate: ek.endDate,
                isAllDay: ek.isAllDay,
                location: ek.location,
                notes: ek.notes,
                calendarColor: ek.calendar.cgColor.hexString
            )
        }
    }
}

extension CalendarService {
    /// Mirrored calendars hand back one real event twice; keep one per title + start.
    static func uniqueEvents(_ events: [EKEvent]) -> [EKEvent] {
        CalendarEventDeduper.uniqued(events, title: { $0.title ?? "" }, start: { $0.startDate },
                                     isAllDay: { $0.isAllDay })
    }
}

// MARK: - Calendars and scoped events (household suggestions)

/// One calendar as the picker shows it.
struct CalendarInfo: Identifiable, Equatable, Hashable, Sendable {
    var id: String
    var title: String
    var source: String
    var colorHex: String
}

extension CalendarService {
    /// Every event calendar on the device, grouped by account (iCloud, Google, Exchange...).
    func eventCalendars() -> [CalendarInfo] {
        guard isAuthorized else { return [] }
        return store.calendars(for: .event).map {
            CalendarInfo(id: $0.calendarIdentifier, title: $0.title, source: $0.source.title, colorHex: $0.cgColor.hexString)
        }
        .sorted { ($0.source, $0.title) < ($1.source, $1.title) }
    }

    /// Calendars grouped by source title, sources alphabetical, calendars alphabetical.
    func eventCalendarsBySource() -> [(source: String, calendars: [CalendarInfo])] {
        let grouped = Dictionary(grouping: eventCalendars(), by: \.source)
        return grouped.keys.sorted().map { (source: $0, calendars: grouped[$0] ?? []) }
    }

    /// Events on the calendar day containing `day`, from the given calendars only
    /// (`predicateForEvents(withStart:end:calendars:)` instead of `nil`). Empty set = nothing.
    func events(on day: Date, in calendarIDs: Set<String>) -> [SuggestionEvent] {
        guard isAuthorized, !calendarIDs.isEmpty else { return [] }
        let cal = Calendar.current
        let start = cal.startOfDay(for: day)
        guard let end = cal.date(byAdding: .day, value: 1, to: start) else { return [] }
        let calendars = store.calendars(for: .event).filter { calendarIDs.contains($0.calendarIdentifier) }
        guard !calendars.isEmpty else { return [] }
        let predicate = store.predicateForEvents(withStart: start, end: end, calendars: calendars)
        return store.events(matching: predicate).map { ek in
            SuggestionEvent(
                id: ek.eventIdentifier ?? ek.calendarItemIdentifier,
                title: ek.title ?? "",
                location: ek.location,
                start: ek.startDate,
                isAllDay: ek.isAllDay,
                calendarIdentifier: ek.calendar.calendarIdentifier)
        }
    }
}

// MARK: - CGColor Hex Support
import UIKit

extension CGColor {
    var hexString: String {
        guard let components = components, components.count >= 3 else { return "gray" }
        guard colorSpace != nil else { return "gray" }

        // Always convert through UIColor for reliable cross-color-space conversion
        let uiColor = UIColor(cgColor: self)
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        uiColor.getRed(&r, green: &g, blue: &b, alpha: &a)
        return String(format: "%02X%02X%02X", Int(r * 255), Int(g * 255), Int(b * 255))
    }
}
