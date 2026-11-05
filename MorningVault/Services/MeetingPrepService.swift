import Foundation
#if canImport(FoundationModels)
import FoundationModels
#endif

/// Prepares meeting intelligence before the user's first event.
/// Reads the first calendar event of the day, generates talking points
/// via AIService (if within 2 hours), and persists past positions per subject.
@MainActor
final class MeetingPrepService {
    static let shared = MeetingPrepService()

    private let calendarService = CalendarService.shared
    private let aiService = AIService.shared

    private init() {}

    // MARK: - Public API

    /// Returns MeetingPrep for today's first event, if one exists within 2 hours.
    /// Skips AI generation if the first meeting is more than 2 hours away.
    /// Returns nil if no events today or meeting is too far out.
    func prepareMeetingPrep() async -> MeetingPrep? {
        let events = await calendarService.fetchTodayEvents()
        // First timed meeting still ahead — not an all-day entry or one that already ended.
        let now = Date()
        guard let firstEvent = events.first(where: { !$0.isAllDay && $0.endDate > now }) else { return nil }

        // Don't call LLM if meeting is > 2 hours away
        let timeUntil = firstEvent.startDate.timeIntervalSinceNow
        guard timeUntil > 0 && timeUntil <= 7200 else {
            // Still surface the meeting info without AI points
            let attendees = extractAttendees(from: firstEvent)
            let pastPositions = MeetingPositionStore.loadPositions(forSubject: firstEvent.title)
            return MeetingPrep(
                meetingTitle: firstEvent.title,
                startTime: firstEvent.startDate,
                attendees: attendees,
                agenda: firstEvent.notes,
                talkingPoints: [],
                yourPastPositions: pastPositions
            )
        }

        // Generate talking points via AI
        let attendees = extractAttendees(from: firstEvent)
        let pastPositions = MeetingPositionStore.loadPositions(forSubject: firstEvent.title)

        let talkingPoints = await generateTalkingPoints(
            title: firstEvent.title,
            attendees: attendees,
            agenda: firstEvent.notes
        )

        let prep = MeetingPrep(
            meetingTitle: firstEvent.title,
            startTime: firstEvent.startDate,
            attendees: attendees,
            agenda: firstEvent.notes,
            talkingPoints: talkingPoints,
            yourPastPositions: pastPositions
        )

        // Persist for display
        prep.save()

        return prep
    }

    /// Saves positions taken in a meeting for future reference.
    func recordPositions(_ positions: [String], forMeetingTitle title: String) {
        MeetingPositionStore.savePositions(positions, forSubject: title)
    }

    // MARK: - Private Helpers

    /// Extracts attendee names from a calendar event.
    /// EKEvent doesn't expose attendees directly via standard API,
    /// so we return the location or a placeholder.
    private func extractAttendees(from event: CalendarEvent) -> [String] {
        var attendees: [String] = []
        if let location = event.location, !location.isEmpty {
            attendees.append(location)
        }
        // Note: EventKit attendees require separate attendee query.
        // For now, we return location as a proxy for room/remote attendees.
        return attendees
    }

    /// Generates 3-5 talking points via the on-device AI service (structured output).
    private func generateTalkingPoints(
        title: String,
        attendees: [String],
        agenda: String?
    ) async -> [String] {
        await aiService.talkingPoints(title: title, attendees: attendees, agenda: agenda)
    }

    private func parseBulletPoints(from text: String) -> [String] {
        // Parse "- Point" or "1. Point" formats
        var points: [String] = []
        let lines = text.components(separatedBy: .newlines)
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("-") {
                points.append(String(trimmed.dropFirst()).trimmingCharacters(in: .whitespaces))
            } else if trimmed.first?.isNumber == true && trimmed.contains(".") {
                // "1. Point" format
                if let dotIndex = trimmed.firstIndex(of: ".") {
                    let point = String(trimmed[trimmed.index(after: dotIndex)...]).trimmingCharacters(in: .whitespaces)
                    if !point.isEmpty { points.append(point) }
                }
            }
        }
        // If nothing parsed, fall back to returning the whole text as single point
        if points.isEmpty && !text.isEmpty {
            points = text.components(separatedBy: ". ").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        }
        return Array(points.prefix(5))  // Max 5 points
    }
}