import Foundation

/// Builds the greeting line from the time of day and the weekday, with a little variety so
/// it does not read the same every morning. Pure and deterministic for a given date and
/// name, so the widget and the app agree. No model, no network.
///
/// Examples: "Good morning, Yezid", "Happy Friday, Yezid", "Late one tonight, Yezid",
/// "Good morning" when the name is empty — never "Good morning, .".
enum GreetingComposer {
    enum Slot: Equatable {
        case earlyMorning   // 00:00–04:59
        case morning        // 05:00–11:59
        case afternoon      // 12:00–16:59
        case evening        // 17:00–20:59
        case night          // 21:00–23:59
    }

    static func slot(for date: Date, calendar: Calendar = .current) -> Slot {
        let hour = calendar.component(.hour, from: date)
        switch hour {
        case 0..<5: return .earlyMorning
        case 5..<12: return .morning
        case 12..<17: return .afternoon
        case 17..<21: return .evening
        default: return .night
        }
    }

    /// Candidate greetings for the slot, most generic first. `weekday` is 1 = Sunday … 7 = Saturday.
    static func candidates(slot: Slot, weekday: Int, calendar: Calendar = .current) -> [String] {
        let dayName = calendar.weekdaySymbols[max(0, min(6, weekday - 1))]
        switch slot {
        case .earlyMorning:
            return ["Up early", "Early start", "Still dark out"]
        case .morning:
            var list = ["Good morning", "Morning", "Rise and shine"]
            switch weekday {
            case 2: list.append("Happy Monday")
            case 6: list.append("Happy Friday")
            case 1, 7: list.append("Easy \(dayName) morning")
            default: list.append("Happy \(dayName)")
            }
            return list
        case .afternoon:
            return ["Good afternoon", "Afternoon", "Hope the day is going well"]
        case .evening:
            var list = ["Good evening", "Evening"]
            if weekday == 6 { list.append("Friday evening") }
            return list
        case .night:
            return ["Late one tonight", "Burning the midnight oil", "Still up"]
        }
    }

    /// The greeting without a name, chosen deterministically for the day so it stays the
    /// same across refreshes but changes from one day to the next.
    static func base(for date: Date, calendar: Calendar = .current) -> String {
        let slot = slot(for: date, calendar: calendar)
        let weekday = calendar.component(.weekday, from: date)
        let list = candidates(slot: slot, weekday: weekday, calendar: calendar)
        let dayOrdinal = calendar.ordinality(of: .day, in: .era, for: date) ?? 0
        // Weekday-specific lines sit last; give them extra weight so "Happy Friday" shows up.
        let index = (dayOrdinal + slot.hashSeed) % (list.count + 1)
        return list[min(index, list.count - 1)]
    }

    /// Full line, e.g. "Good morning, Yezid". Trims the name; empty names give just the base.
    static func line(name: String, date: Date = Date(), calendar: Calendar = .current) -> String {
        let base = base(for: date, calendar: calendar)
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return base }
        return "\(base), \(trimmed)"
    }
}

private extension GreetingComposer.Slot {
    var hashSeed: Int {
        switch self {
        case .earlyMorning: return 0
        case .morning: return 1
        case .afternoon: return 2
        case .evening: return 3
        case .night: return 4
        }
    }
}
