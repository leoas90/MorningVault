import Foundation
import EventKit

/// EventKit service — reads today's calendar events
/// No write access requested. Data stays on-device.
final class CalendarService: ObservableObject {
    static let shared = CalendarService()

    private let store = EKEventStore()
    @Published var isAuthorized = false
    @Published var lastError: String?

    // MARK: - Authorization

    func requestAuthorization() async -> Bool {
        do {
            let granted = try await store.requestFullAccessToEvents()
            await MainActor.run { isAuthorized = granted }
            return granted
        } catch {
            await MainActor.run { lastError = error.localizedDescription }
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
        let events = store.events(matching: predicate)

        return events.map { ek in
            CalendarEvent(
                id: ek.eventIdentifier ?? UUID().uuidString,
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
        let events = store.events(matching: predicate)

        return events.map { ek in
            CalendarEvent(
                id: ek.eventIdentifier ?? UUID().uuidString,
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

// MARK: - CGColor Hex Support
import CoreImage
extension CGColor {
    var hexString: String {
        guard let components = components, components.count >= 3 else { return "gray" }
        let r = Int(components[0] * 255)
        let g = Int(components[1] * 255)
        let b = Int(components[2] * 255)
        return String(format: "%02X%02X%02X", r, g, b)
    }
}
