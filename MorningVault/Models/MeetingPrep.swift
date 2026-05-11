import Foundation

/// Pre-meeting intelligence: surface talking points + past positions
/// before the user's first event of the day.
struct MeetingPrep: Codable {
    let meetingTitle: String
    let startTime: Date
    let attendees: [String]
    let agenda: String?
    var talkingPoints: [String]
    var yourPastPositions: [String]
    var isExpanded: Bool = false

    var timeUntilMeeting: TimeInterval {
        startTime.timeIntervalSinceNow
    }

    var isUpcoming: Bool {
        timeUntilMeeting > 0 && timeUntilMeeting <= 7200 // within 2 hours
    }

    var formattedStartTime: String {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        return formatter.string(from: startTime)
    }

    var isWithin2Hours: Bool {
        timeUntilMeeting > 0 && timeUntilMeeting <= 7200
    }
}

// MARK: - Persistence

extension MeetingPrep {
    private static let userDefaultsKey = "com.morningvault.meeting_prep"

    /// Saves current meeting prep to UserDefaults (small JSON).
    func save() {
        if let encoded = try? JSONEncoder().encode(self) {
            UserDefaults.standard.set(encoded, forKey: Self.userDefaultsKey)
        }
    }

    /// Loads persisted meeting prep from UserDefaults.
    static func load() -> MeetingPrep? {
        guard let data = UserDefaults.standard.data(forKey: userDefaultsKey),
              let decoded = try? JSONDecoder().decode(MeetingPrep.self, from: data) else {
            return nil
        }
        return decoded
    }

    /// Clears persisted meeting prep.
    static func clear() {
        UserDefaults.standard.removeObject(forKey: userDefaultsKey)
    }
}

// MARK: - Past positions per meeting subject

/// Stores past positions taken in meetings with similar titles/subjects.
/// Used to surface "you've argued X in similar meetings before."
struct MeetingPositionStore {
    private static let key = "com.morningvault.past_positions"

    /// Persists positions for a given meeting subject (normalized title).
    static func savePositions(_ positions: [String], forSubject subject: String) {
        var store = loadStore()
        store[normalized(subject)] = positions
        if let encoded = try? JSONEncoder().encode(store) {
            UserDefaults.standard.set(encoded, forKey: key)
        }
    }

    /// Loads past positions for a given meeting subject.
    static func loadPositions(forSubject subject: String) -> [String] {
        let store = loadStore()
        return store[normalized(subject)] ?? []
    }

    private static func loadStore() -> [String: [String]] {
        guard let data = UserDefaults.standard.data(forKey: key),
              let decoded = try? JSONDecoder().decode([String: [String]].self, from: data) else {
            return [:]
        }
        return decoded
    }

    private static func normalized(_ title: String) -> String {
        // Normalize to lowercase, strip common meeting prefixes/suffixes
        let lower = title.lowercased()
        let trimmed = lower.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed
    }
}