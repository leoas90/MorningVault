import Foundation
import FoundationModels
import Observation

/// The Brief header greeting: a static line from `GreetingComposer` plus, when the on-device
/// model is available and quick, a one-line opener about the first event or the weather.
///
/// Cached per day (and per name) in UserDefaults so a refresh never regenerates it, and the
/// widget reads the same text from `SharedBriefingStore`.
@MainActor
@Observable
final class GreetingService {
    static let shared = GreetingService()

    /// "Good morning, Yezid" — always available, never empty.
    private(set) var line: String = GreetingComposer.line(name: "")
    /// Optional opener written by the model, 12 words max. Nil until generated or when the model is unavailable.
    private(set) var opener: String?

    private static let cacheKey = "greeting_cache_v1"
    private static let modelTimeout: Duration = .seconds(2)

    private struct Cache: Codable {
        var day: String
        var name: String
        var line: String
        var opener: String?
    }

    private init() {}

    /// Context the opener may mention. Both optional; nothing is sent anywhere.
    struct Context: Sendable {
        var firstEventTitle: String?
        var firstEventStart: Date?
        var weatherLine: String?
    }

    /// Returns the greeting for today, generating the opener once per day.
    @discardableResult
    func refresh(name: String, context: Context, now: Date = Date()) async -> String {
        let day = SharedBriefing.today(now)
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let staticLine = GreetingComposer.line(name: trimmed, date: now)

        if let cached = loadCache(), cached.day == day, cached.name == trimmed, cached.line == staticLine {
            line = cached.line
            opener = cached.opener
            publish()
            return line
        }

        line = staticLine
        opener = nil
        publish()

        let generated = await generateOpener(context: context)
        opener = generated
        saveCache(Cache(day: day, name: trimmed, line: staticLine, opener: generated))
        publish()
        return line
    }

    /// Static line only — for callers that must not wait (e.g. the background refresh).
    func staticLine(name: String, now: Date = Date()) -> String {
        GreetingComposer.line(name: name, date: now)
    }

    // MARK: - Model

    private func generateOpener(context: Context) async -> String? {
        guard SystemLanguageModel.default.availability == .available else { return nil }
        var facts: [String] = []
        if let title = context.firstEventTitle, !title.isEmpty {
            if let start = context.firstEventStart {
                facts.append("First calendar event: \(title) at \(start.formatted(date: .omitted, time: .shortened)).")
            } else {
                facts.append("First calendar event: \(title).")
            }
        }
        if let weather = context.weatherLine, !weather.isEmpty {
            facts.append("Weather now: \(weather).")
        }
        guard !facts.isEmpty else { return nil }

        let prompt = """
        Write one friendly opener for a morning app. At most 12 words. Plain text, no emoji, \
        no quotes, no greeting word (the greeting is already shown). Mention exactly one fact.
        \(facts.joined(separator: "\n"))
        """

        // A fresh session each time: no history, nothing to leak between days.
        let session = LanguageModelSession(
            instructions: "You write one short, warm sentence. Never exceed 12 words. Never invent facts."
        )
        let work = Task { () -> String? in
            do {
                let response = try await session.respond(to: prompt)
                return response.content
            } catch {
                return nil
            }
        }
        let timeout = Task { () -> String? in
            try? await Task.sleep(for: Self.modelTimeout)
            return nil
        }
        // First result wins; a slow model falls back silently to the static greeting.
        let result: String? = await withTaskGroup(of: String?.self) { group in
            group.addTask { await work.value }
            group.addTask { await timeout.value }
            let first = await group.next() ?? nil
            group.cancelAll()
            work.cancel()
            timeout.cancel()
            return first
        }
        return Self.clean(result)
    }

    /// Enforces the 12-word cap and drops anything that does not look like one sentence.
    static func clean(_ text: String?) -> String? {
        guard var t = text?.trimmingCharacters(in: .whitespacesAndNewlines), !t.isEmpty else { return nil }
        t = t.replacingOccurrences(of: "\"", with: "")
        if let newline = t.firstIndex(of: "\n") { t = String(t[..<newline]) }
        let words = t.split(separator: " ")
        guard words.count <= 12 else { return nil }
        return t
    }

    // MARK: - Cache / widget

    private func loadCache() -> Cache? {
        guard let data = UserDefaults.standard.data(forKey: Self.cacheKey) else { return nil }
        return try? JSONDecoder().decode(Cache.self, from: data)
    }

    private func saveCache(_ cache: Cache) {
        if let data = try? JSONEncoder().encode(cache) {
            UserDefaults.standard.set(data, forKey: Self.cacheKey)
        }
    }

    private func publish() {
        let line = line
        let opener = opener
        // Skip the write (and the widget reload it triggers) when nothing changed.
        if let b = SharedBriefingStore.loadToday(), b.greeting == line, b.greetingOpener == opener { return }
        SharedBriefingStore.update { b in
            b.greeting = line
            b.greetingOpener = opener
        }
    }
}
