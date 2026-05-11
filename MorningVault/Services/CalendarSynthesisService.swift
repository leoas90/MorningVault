import Foundation
import EventKit

/// Smart Calendar Synthesis service:
/// - Detects time conflicts between events
/// - Extracts action items from event notes
/// - Summarizes the day's schedule
extension CalendarService {

    // MARK: - Conflict Detection

    /// Returns all overlapping event pairs for the given events.
    func detectConflicts(in events: [CalendarEvent]) -> [CalendarConflict] {
        var conflicts: [CalendarConflict] = []

        for i in 0..<events.count {
            for j in (i + 1)..<events.count {
                let a = events[i]
                let b = events[j]

                // Skip all-day events
                if a.isAllDay || b.isAllDay { continue }

                if doOverlap(a, b) {
                    let overlap = computeOverlap(a, b)
                    conflicts.append(CalendarConflict(
                        eventA: a,
                        eventB: b,
                        overlapMinutes: overlap
                    ))
                }
            }
        }

        return conflicts.sorted { $0.overlapMinutes > $1.overlapMinutes }
    }

    private func doOverlap(_ a: CalendarEvent, _ b: CalendarEvent) -> Bool {
        // a.start < b.end AND b.start < a.end
        return a.startDate < b.endDate && b.startDate < a.endDate
    }

    private func computeOverlap(_ a: CalendarEvent, _ b: CalendarEvent) -> Int {
        let start = max(a.startDate, b.startDate)
        let end = min(a.endDate, b.endDate)
        return max(0, Int(end.timeIntervalSince(start) / 60))
    }

    // MARK: - Action Item Extraction

    /// Parses event notes and description for action items.
    /// Looks for patterns like: "TODO:", "Action:", "- [ ]", "discuss", "review", "follow up"
    func extractActionItems(from events: [CalendarEvent]) -> [ActionItem] {
        var items: [ActionItem] = []

        for event in events {
            guard let notes = event.notes, !notes.isEmpty else { continue }

            let lines = notes.components(separatedBy: .newlines)
            for line in lines {
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                if let action = parseActionItem(trimmed, event: event) {
                    items.append(action)
                }
            }
        }

        return items
    }

    private func parseActionItem(_ line: String, event: CalendarEvent) -> ActionItem? {
        let lower = line.lowercased()

        // Strong signals
        let strongTriggers = ["todo:", "action:", "task:", "- [ ]", "[ ]", "☐", "☑"]
        for trigger in strongTriggers {
            if lower.contains(trigger) {
                let text = line
                    .replacingOccurrences(of: trigger, with: "", options: .caseInsensitive)
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                    .trimmingCharacters(in: CharacterSet(charactersIn: "[]"))
                    .trimmingCharacters(in: .punctuationCharacters)
                if !text.isEmpty {
                    return ActionItem(
                        id: UUID().uuidString,
                        description: text,
                        sourceEvent: event.title,
                        dueTime: event.startDate,
                        priority: .high
                    )
                }
            }
        }

        // Medium signals — verb-based action phrases
        let actionVerbs = ["review", "follow up", "send", "call", "schedule", "prepare", "check", "update", "complete", "finish"]
        for verb in actionVerbs {
            if lower.contains(verb) && line.count < 200 {
                return ActionItem(
                    id: UUID().uuidString,
                    description: line.trimmingCharacters(in: .whitespacesAndNewlines),
                    sourceEvent: event.title,
                    dueTime: event.startDate,
                    priority: .medium
                )
            }
        }

        return nil
    }

    // MARK: - Daily Summary

    /// Generates a structured summary of the day's schedule.
    func generateDaySummary(events: [CalendarEvent]) -> CalendarDaySummary {
        let conflicts = detectConflicts(in: events)
        let actionItems = extractActionItems(from: events)

        // Group events by time block
        let morning = events.filter { Calendar.current.component(.hour, from: $0.startDate) < 12 }
        let afternoon = events.filter {
            let h = Calendar.current.component(.hour, from: $0.startDate)
            return h >= 12 && h < 17
        }
        let evening = events.filter {
            Calendar.current.component(.hour, from: $0.startDate) >= 17
        }

        // Find gaps (free time blocks > 60 min)
        let freeBlocks = computeFreeBlocks(events: events)

        return CalendarDaySummary(
            totalEvents: events.count,
            conflictCount: conflicts.count,
            actionItemCount: actionItems.count,
            morningCount: morning.count,
            afternoonCount: afternoon.count,
            eveningCount: evening.count,
            freeBlocks: freeBlocks,
            conflicts: conflicts,
            actionItems: actionItems
        )
    }

    private func computeFreeBlocks(events: [CalendarEvent]) -> [FreeTimeBlock] {
        let sorted = events.filter { !$0.isAllDay }.sorted { $0.startDate < $1.startDate }
        var blocks: [FreeTimeBlock] = []

        let calendar = Calendar.current
        let now = Date()
        let startOfDay = calendar.startOfDay(for: now)
        let endOfDay = calendar.date(byAdding: .day, value: 1, to: startOfDay)!

        var cursor = max(now, startOfDay)  // Don't flag past time as free

        for event in sorted {
            if event.startDate > cursor {
                let gapMinutes = Int(event.startDate.timeIntervalSince(cursor) / 60)
                if gapMinutes >= 60 {
                    blocks.append(FreeTimeBlock(start: cursor, end: event.startDate, minutesFree: gapMinutes))
                }
            }
            cursor = max(cursor, event.endDate)
        }

        // End of day
        if cursor < endOfDay {
            let gapMinutes = Int(endOfDay.timeIntervalSince(cursor) / 60)
            if gapMinutes >= 60 {
                blocks.append(FreeTimeBlock(start: cursor, end: endOfDay, minutesFree: gapMinutes))
            }
        }

        return blocks
    }
}

// MARK: - Conflict Model

struct CalendarConflict: Identifiable {
    let id = UUID()
    let eventA: CalendarEvent
    let eventB: CalendarEvent
    let overlapMinutes: Int

    var description: String {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        let aTime = formatter.string(from: eventA.startDate)
        let bTime = formatter.string(from: eventB.startDate)
        return "\(overlapMinutes)min overlap: \"\(eventA.title)\" (\(aTime)) ↔ \"\(eventB.title)\" (\(bTime))"
    }
}

// MARK: - Action Item Model

struct ActionItem: Identifiable {
    let id: String
    let description: String
    let sourceEvent: String
    let dueTime: Date
    let priority: Priority

    enum Priority: String {
        case high, medium, low
    }

    var priorityIcon: String {
        switch priority {
        case .high: return "exclamationmark.circle.fill"
        case .medium: return "circle.fill"
        case .low: return "circle"
        }
    }
}

// MARK: - Free Time Block

struct FreeTimeBlock: Identifiable {
    let id = UUID()
    let start: Date
    let end: Date
    let minutesFree: Int

    var formatted: String {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        return "\(formatter.string(from: start)) – \(formatter.string(from: end)) (\(minutesFree / 60)h free)"
    }
}

// MARK: - Day Summary

struct CalendarDaySummary {
    let totalEvents: Int
    let conflictCount: Int
    let actionItemCount: Int
    let morningCount: Int
    let afternoonCount: Int
    let eveningCount: Int
    let freeBlocks: [FreeTimeBlock]
    let conflicts: [CalendarConflict]
    let actionItems: [ActionItem]

    var hasConflicts: Bool { conflictCount > 0 }
    var isBusy: Bool { totalEvents >= 5 }
    var hasFreeTime: Bool { !freeBlocks.isEmpty }
}