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
        switch EKEventStore.authorizationStatus(for: .reminder) {
        case .fullAccess:
            return true
        case .denied, .restricted:
            return false
        default:
            // `.notDetermined`, and `.writeOnly` (which EventKit does not grant for
            // reminders, but would not let `calendars(for:)` find the list): ask for
            // full access, the only level that lets the list be found or created.
            return try await store.requestFullAccessToReminders()
        }
    }

    private func list(named name: String) async throws -> EKCalendar {
        let calendars = store.calendars(for: .reminder)
        if let existing = calendars.first(where: { $0.title.caseInsensitiveCompare(name) == .orderedSame }) {
            return existing
        }

        let source = store.sources.first(where: { $0.sourceType == .local })
            ?? store.defaultCalendarForNewReminders()?.source
        guard let source else {
            throw RemindersError.noSource
        }
        let calendar = EKCalendar(for: .reminder, eventStore: store)
        calendar.title = name
        calendar.source = source
        try store.saveCalendar(calendar, commit: true)
        return calendar
    }

    /// Errors raised while exporting to Reminders.
    public enum RemindersError: LocalizedError, Sendable {
        case accessDenied
        /// No account can hold a new list (no local source, no default list).
        case noSource

        public var errorDescription: String? {
            switch self {
            case .accessDenied:
                return "Reminders access is off. Turn it on in Settings › MorningVault › Reminders."
            case .noSource:
                return "No Reminders account can hold a new list. Add a list in Reminders first."
            }
        }
    }
}
