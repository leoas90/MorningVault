import Foundation

// MARK: - Suggestion engine (rules pass)
//
// Deterministic: events in, up to three suggestions out. The data lives in
// `Models/SuggestionRules.swift`. No model pass here; a second engine can add to the result
// later. Pure function first so the tests pin every rule; the `refreshCache` entry points
// below do the EventKit and App Group plumbing.

/// What the engine needs from a calendar event. Built from EventKit in the app, by hand in tests.
struct SuggestionEvent: Equatable, Sendable {
    var id: String
    var title: String
    var location: String?
    var start: Date
    var isAllDay: Bool
    /// `EKCalendar.calendarIdentifier`; nil when unknown.
    var calendarIdentifier: String?
}

enum SuggestionEngine {
    struct Input: Sendable {
        var events: [SuggestionEvent]
        var members: [HouseholdMember] = []
        /// Calendar id -> member (nil value = Home). Missing key = no mapping.
        var calendarMembers: [String: UUID?] = [:]
        /// Calendars the user turned on; nil = all.
        var selectedCalendars: Set<String>? = nil
        var decisions: [SuggestionDecision] = []
        /// Titles of items already on the list for the day, so nothing is suggested twice.
        var existingTitles: [String] = []
        /// "eventID|ruleID" for items already added from a suggestion.
        var addedFromEvents: Set<String> = []
        var now: Date
        var calendar: Calendar = .current
    }

    static let maxPerDay = 3
    /// Events starting sooner than this are too late to prepare for.
    static let leadTime: TimeInterval = 60 * 60

    static func rules(_ input: Input) -> [Suggestion] {
        let existing = Set(input.existingTitles.map { ChecklistDeduper.normalizedTitle($0) })
        var result: [Suggestion] = []
        // Households that mirror every event into two calendars hand us the same real event
        // twice with different ids. One suggestion per (title, rule, start); the first wins.
        var seen = Set<String>()

        for event in input.events.sorted(by: { $0.start < $1.start }) {
            if let selected = input.selectedCalendars, let cal = event.calendarIdentifier, !selected.contains(cal) { continue }
            let text = ((event.title) + " " + (event.location ?? "")).lowercased()
            guard let rule = bestRule(for: text) else { continue }
            if event.isAllDay {
                guard rule.allowsAllDay else { continue }
            } else {
                // Starting within the hour (or already started): skip.
                guard event.start.timeIntervalSince(input.now) >= leadTime else { continue }
            }
            if rule.weekdaysOnly, Weekday.weekends.contains(Weekday.of(event.start, calendar: input.calendar)) { continue }

            let pattern = SuggestionDecision.pattern(for: event.title)
            if input.decisions.contains(where: { $0.ruleID == rule.id && $0.titlePattern == pattern && $0.decision == .neverForTitle }) { continue }

            let title = rule.resolvedTitle(for: text)
            if existing.contains(ChecklistDeduper.normalizedTitle(title)) { continue }
            if input.addedFromEvents.contains("\(event.id)|\(rule.id)") { continue }
            let fingerprint = Self.eventFingerprint(title: title, ruleID: rule.id, start: event.start, isAllDay: event.isAllDay, calendar: input.calendar)
            guard seen.insert(fingerprint).inserted else { continue }

            result.append(Suggestion(
                eventID: event.id,
                eventTitle: event.title,
                eventStart: event.start,
                isAllDay: event.isAllDay,
                ruleID: rule.id,
                title: title,
                icon: rule.icon,
                forMember: inferMember(event: event, input: input)))
            if result.count >= maxPerDay { break }
        }
        return result
    }

    /// Identity of the real-world event behind a suggestion: the resolved title (case and
    /// whitespace insensitive), the rule, and the start. All-day events match on the day,
    /// timed events on the minute, so the same event mirrored into a second calendar with a
    /// different event id collapses into one suggestion.
    static func eventFingerprint(title: String, ruleID: String, start: Date, isAllDay: Bool, calendar: Calendar) -> String {
        let when: String
        if isAllDay {
            when = "day-\(ChecklistDay.key(for: start, calendar: calendar))"
        } else {
            when = "min-\(Int(start.timeIntervalSinceReferenceDate / 60))"
        }
        return "\(ChecklistDeduper.normalizedTitle(title))|\(ruleID)|\(when)"
    }

    /// Highest keyword count wins; ties go to the earlier rule in the table.
    static func bestRule(for text: String) -> SuggestionRule? {
        var best: (SuggestionRule, Int)?
        for rule in SuggestionRule.all {
            let score = rule.score(in: text)
            guard score > 0 else { continue }
            if best == nil || score > best!.1 { best = (rule, score) }
        }
        return best?.0
    }

    /// Calendar mapping first, then a member name in the title, then Home (nil).
    static func inferMember(event: SuggestionEvent, input: Input) -> UUID? {
        if let cal = event.calendarIdentifier, let mapped = input.calendarMembers[cal] {
            return mapped
        }
        let title = event.title.lowercased()
        for member in input.members {
            let name = member.name.trimmingCharacters(in: .whitespaces).lowercased()
            guard name.count >= 2 else { continue }
            if title.range(of: "\\b\(NSRegularExpression.escapedPattern(for: name))\\b", options: .regularExpression) != nil {
                return member.id
            }
        }
        return nil
    }
}

// MARK: - Calendar selection (local)

/// Which calendars feed the suggestion engine and whose events they are. Per device, never
/// synced: calendar identifiers differ between phones. Unknown calendars are on with no member.
struct CalendarPreference: Codable, Equatable, Sendable {
    var enabled: Bool = true
    var member: UUID? = nil
}

enum CalendarSelectionStore {
    static let key = "household_calendar_selection_v1"

    nonisolated static func load(defaults: UserDefaults = .standard) -> [String: CalendarPreference] {
        guard let data = defaults.data(forKey: key),
              let decoded = try? JSONDecoder().decode([String: CalendarPreference].self, from: data) else { return [:] }
        return decoded
    }

    nonisolated static func save(_ prefs: [String: CalendarPreference], defaults: UserDefaults = .standard) {
        guard let data = try? JSONEncoder().encode(prefs) else { return }
        defaults.set(data, forKey: key)
    }

    /// Calendar ids turned off explicitly; everything else is on.
    nonisolated static func isEnabled(_ identifier: String, in prefs: [String: CalendarPreference]) -> Bool {
        prefs[identifier]?.enabled ?? true
    }

    /// Calendar id -> member for the engine (only calendars with a chosen member).
    nonisolated static func memberMapping(_ prefs: [String: CalendarPreference]) -> [String: UUID?] {
        var map: [String: UUID?] = [:]
        for (id, pref) in prefs where pref.enabled && pref.member != nil { map[id] = pref.member }
        return map
    }
}

// MARK: - Cache refresh (app side)

extension SuggestionEngine {
    /// Recomputes the suggestions for `day` from this phone's selected calendars and stores
    /// them in the App Group. Morning refresh passes today; the 8 pm precompute passes
    /// tomorrow. Dismissals for the same day survive the recompute.
    @MainActor
    static func refreshCache(for day: Date, now: Date = Date(), store: ChecklistStore = .shared, calendarService: CalendarService = .shared) async {
        guard BriefSectionPrefs.isHouseholdEnabled else { return }
        let cal = Calendar.current
        let prefs = CalendarSelectionStore.load()
        let allCalendars = calendarService.eventCalendars()
        let selected = Set(allCalendars.map(\.id).filter { CalendarSelectionStore.isEnabled($0, in: prefs) })
        let events = calendarService.events(on: day, in: selected)

        let ledger = (try? await store.ledger(asOf: day)) ?? ChecklistLedger()
        let members = (try? await store.members()) ?? []
        let decisions = (try? await store.suggestionDecisions()) ?? []
        // Hand-typed items only: items made from a suggestion are matched by event below.
        let existing = ledger.scheduled(on: day, calendar: cal).filter { $0.sourceEventID == nil }.map(\.title)
        let addedFromEvents = Set(ledger.items.filter { !$0.isArchived }.compactMap { item in
            item.sourceEventID.map { "\($0)|\(item.sourceRuleID ?? "")" } })

        let suggestions = rules(Input(
            events: events, members: members,
            calendarMembers: CalendarSelectionStore.memberMapping(prefs),
            selectedCalendars: selected,
            decisions: decisions, existingTitles: existing, addedFromEvents: addedFromEvents, now: now, calendar: cal))

        let dayKey = ChecklistDay.key(for: day, calendar: cal)
        let previous = SuggestionsCache.load()
        let dismissed = previous?.day == dayKey ? (previous?.dismissed ?? []) : []
        SuggestionsCache(day: dayKey, computedAt: now, suggestions: suggestions, dismissed: dismissed).save()
    }

    /// Morning: today. Evening (after 19:00): tomorrow, so the row is ready the night before.
    @MainActor
    static func refreshCacheForNow(now: Date = Date()) async {
        let cal = Calendar.current
        let hour = cal.component(.hour, from: now)
        let day = hour >= 19 ? (cal.date(byAdding: .day, value: 1, to: now) ?? now) : now
        await refreshCache(for: day, now: now)
    }
}
