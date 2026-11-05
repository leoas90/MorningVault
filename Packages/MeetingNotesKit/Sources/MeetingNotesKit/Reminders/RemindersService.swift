import EventKit
import Foundation

/// Sends action items to a Reminders list.
@MainActor
public final class RemindersService: ObservableObject {
    /// Name of the list action items are filed under.
    public static let defaultListName = "Meetings"

    @Published public internal(set) var message: String?
    @Published public internal(set) var exportedCount: Int = 0

    private let store = EKEventStore()

    /// Exports the given action items into the Reminders list called `listName`.
    ///
    /// - Returns: the number of reminders that were created.
    @discardableResult
    public func export(_ items: [ActionItem], to listName: String = RemindersService.defaultListName) async throws -> Int {
        guard !items.isEmpty else {
            exportedCount = 0
            return 0
        }

        let granted = try await requestAccess()
        guard granted else {
            throw RemindersError.accessDenied
        }

        let list = try await list(named: listName)
        var created = 0
        for item in items {
            let reminder = EKReminder(eventStore: store)
            reminder.calendar = list
            reminder.title = item.text
            var notes: [String] = []
            if let owner = item.owner, !owner.isEmpty { notes.append("Owner: \(owner)") }
            if let due = item.due, !due.isEmpty { notes.append("Due: \(due)") }
            reminder.notes = notes.joined(separator: "\n")
            try store.save(reminder, commit: false)
            created += 1
        }
        try store.commit()
        exportedCount = created
        message = "Sent \(created) action item\(created == 1 ? "" : "s") to \(list.title)."
        return created
    }

    private func requestAccess() async throws -> Bool {
        let status = EKEventStore.authorizationStatus(for: .reminder)
        switch status {
        case .fullAccess, .writeOnly:
            return true
        case .denied, .restricted:
            return false
        default:
            return try await store.requestFullAccessToReminders()
        }
    }

    private func list(named name: String) async throws -> EKCalendar {
        let calendars = store.calendars(for: .reminder)
        if let existing = calendars.first(where: { $0.title.caseInsensitiveCompare(name) == .orderedSame }) {
            return existing
        }

        let calendar = EKCalendar(for: .reminder, eventStore: store)
        calendar.title = name
        if let source = store.sources.first(where: { $0.sourceType == .local }) {
            calendar.source = source
        } else if let source = store.defaultCalendarForNewReminders()?.source {
            calendar.source = source
        }
        try store.saveCalendar(calendar, commit: true)
        return calendar
    }

    /// Errors raised while exporting to Reminders.
    public enum RemindersError: LocalizedError, Sendable {
        case accessDenied

        public var errorDescription: String? {
            switch self {
            case .accessDenied:
                return "Reminders access is off. Turn it on in Settings › MorningVault › Reminders."
            }
        }
    }
}
