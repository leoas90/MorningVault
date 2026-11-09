import Foundation

// MARK: - Suggestion rules (data)
//
// Keyword map from calendar event title + location to a thing to prepare. Data, not code:
// tune the table without touching `SuggestionEngine`. Matching is case-insensitive; a rule
// scores by how many of its keywords appear; the best rule wins, one suggestion per event.

struct SuggestionRule: Identifiable, Equatable, Sendable {
    var id: String
    var keywords: [String]
    /// Suggestion title. `[sport]` is replaced by the matched keyword, capitalised.
    var title: String
    var icon: String
    /// All-day events are skipped unless the rule says otherwise (field trip, birthday).
    var allowsAllDay: Bool = false
    /// Weekday-only rules (school) never fire on weekends.
    var weekdaysOnly: Bool = false

    static let all: [SuggestionRule] = [
        SuggestionRule(id: "practice", keywords: ["practice", "soccer", "baseball", "swim", "gymnastics", "dance", "karate"],
                       title: "Pack [sport] bag", icon: "duffle.bag"),
        SuggestionRule(id: "game", keywords: ["game", "match", "tournament"],
                       title: "Pack game bag, water bottle", icon: "sportscourt"),
        SuggestionRule(id: "school", keywords: ["school", "class"],
                       title: "Pack lunch", icon: "fork.knife", weekdaysOnly: true),
        SuggestionRule(id: "fieldtrip", keywords: ["field trip"],
                       title: "Permission slip, packed lunch", icon: "signature", allowsAllDay: true),
        SuggestionRule(id: "doctor", keywords: ["doctor", "dentist", "pediatric", "checkup", "check-up"],
                       title: "Insurance card, questions", icon: "cross.case"),
        SuggestionRule(id: "flight", keywords: ["flight", "airport"],
                       title: "Passports or IDs, chargers", icon: "airplane"),
        SuggestionRule(id: "birthday", keywords: ["birthday", "party"],
                       title: "Gift, card", icon: "gift", allowsAllDay: true),
        SuggestionRule(id: "music", keywords: ["piano", "lesson", "recital"],
                       title: "Bring music books", icon: "pianokeys"),
        SuggestionRule(id: "library", keywords: ["library"],
                       title: "Return library books", icon: "books.vertical"),
        SuggestionRule(id: "dinner", keywords: ["dinner at", "reservation"],
                       title: "Book confirmed", icon: "fork.knife"),
    ]

    /// Sports that fill the `[sport]` placeholder; "practice" alone gives "Pack practice bag".
    static let sportWords: Set<String> = ["soccer", "baseball", "swim", "gymnastics", "dance", "karate"]

    /// Score = number of keywords found in `text` (already lowercased). 0 = no match.
    func score(in text: String) -> Int {
        keywords.filter { text.contains($0) }.count
    }

    /// Fills `[sport]` from the first sport word found, else "practice".
    func resolvedTitle(for text: String) -> String {
        guard title.contains("[sport]") else { return title }
        let sport = keywords.first { Self.sportWords.contains($0) && text.contains($0) } ?? "practice"
        return title.replacingOccurrences(of: "[sport]", with: sport)
    }
}

// MARK: - Decisions

/// "Never for this": the user turned a suggestion down for good. Keyed by rule + event title
/// so the same practice never suggests again, while a different event with the same rule can.
struct SuggestionDecision: Codable, Equatable, Hashable, Sendable {
    enum Decision: String, Codable, Sendable { case neverForTitle }
    var ruleID: String
    var titlePattern: String
    var decision: Decision = .neverForTitle

    /// Lowercased, trimmed title the engine compares against.
    static func pattern(for title: String) -> String {
        title.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }
}

// MARK: - Suggestion

/// One proposal in the "Suggested from today's calendar" row.
struct Suggestion: Codable, Identifiable, Equatable, Hashable, Sendable {
    var id: String { "\(eventID)|\(Int(eventStart.timeIntervalSince1970))|\(ruleID)" }
    var eventID: String
    var eventTitle: String
    var eventStart: Date
    var isAllDay: Bool
    var ruleID: String
    var title: String
    var icon: String
    /// Inferred member; nil = Home.
    var forMember: UUID?

    /// "Riley, practice 4:00 PM" style caption; the caller supplies the member name.
    func caption(memberName: String?) -> String {
        let time = isAllDay ? "all day" : eventStart.formatted(date: .omitted, time: .shortened)
        if let memberName, !memberName.isEmpty { return "\(memberName), \(eventTitle) \(time)" }
        return "\(eventTitle) \(time)"
    }
}

extension Suggestion {
    /// Two previews worth of proposals for the fictional household.
    static let sample: [Suggestion] = [
        Suggestion(eventID: "evt-1", eventTitle: "Soccer practice", eventStart: Date(timeIntervalSince1970: 1_762_560_000),
                   isAllDay: false, ruleID: "practice", title: "Pack soccer bag", icon: "duffle.bag", forMember: HouseholdMember.sampleChild1.id),
        Suggestion(eventID: "evt-2", eventTitle: "Dentist", eventStart: Date(timeIntervalSince1970: 1_762_545_600),
                   isAllDay: false, ruleID: "doctor", title: "Insurance card, questions", icon: "cross.case", forMember: nil),
    ]
}

/// The day's suggestions, cached in the App Group as `suggestions_today_v1`.
struct SuggestionsCache: Codable, Equatable, Sendable {
    var day: String
    var computedAt: Date
    var suggestions: [Suggestion]
    /// Event ids the user said "Not today" to; cleared with the day.
    var dismissed: [String] = []

    static let key = "suggestions_today_v1"
    static let previewStartedKey = "suggestions_preview_started"
    static let previewDays = 7
    static let appGroup = "group.com.morningvault.app"

    static func load(defaults: UserDefaults? = UserDefaults(suiteName: appGroup)) -> SuggestionsCache? {
        guard let data = (defaults ?? .standard).data(forKey: key) else { return nil }
        let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(SuggestionsCache.self, from: data)
    }

    func save(defaults: UserDefaults? = UserDefaults(suiteName: appGroup)) {
        let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(self) else { return }
        (defaults ?? .standard).set(data, forKey: Self.key)
    }

    /// True while the free 7-day look at suggestions is still running. First call starts it.
    static func previewActive(now: Date = Date(), defaults: UserDefaults = .standard, calendar: Calendar = .current) -> Bool {
        if let started = defaults.object(forKey: previewStartedKey) as? Date {
            return previewElapsed(started: started, now: now, calendar: calendar) == false
        }
        defaults.set(now, forKey: previewStartedKey)
        return true
    }

    static func previewElapsed(started: Date, now: Date, calendar: Calendar = .current) -> Bool {
        let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: started), to: calendar.startOfDay(for: now)).day ?? 0
        return days >= previewDays
    }
}
