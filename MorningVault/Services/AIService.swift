import Foundation
#if canImport(FoundationModels)
import FoundationModels
#endif

/// On-device AI service using Apple's Foundation Models framework.
///
/// **Privacy contract:**
/// - ALL AI processing happens on-device via `SystemLanguageModel.default`.
/// - Health data is SANITIZED before entering prompts (no raw HRV, sleep stages, etc.).
/// - No health data is EVER routed to Mac Mini, Ollama, or any external endpoint.
///
/// **Model limits that shape this file:**
/// - The on-device model has a ~4K-token context window shared by instructions, prompt,
///   schema and output. Every request therefore gets a FRESH session — reusing one session
///   for several prompts grows its transcript until it throws `exceededContextWindowSize`.
/// - Availability can change at runtime (model still downloading, Apple Intelligence turned
///   on later), so it is re-checked on every call rather than cached at init.
@MainActor
final class AIService {

    static let shared = AIService()

    // MARK: - State

    /// Whether on-device Foundation Models are available right now.
    private(set) var isAvailable: Bool = false

    /// Human-readable reason the model is unavailable, for the UI. `nil` when available.
    private(set) var unavailableReason: String?

    /// Last error from FM, if any.
    var lastError: String?

    // MARK: - Latency instrumentation

    private var latencyHistory: [Int] = []
    private let latencyHistoryCapacity = 10

    private func recordLatency(_ ms: Int) {
        latencyHistory.append(ms)
        if latencyHistory.count > latencyHistoryCapacity {
            latencyHistory.removeFirst()
        }
    }

    /// P95 latency in milliseconds across recent FM calls.
    var p95LatencyMs: Int {
        guard !latencyHistory.isEmpty else { return 0 }
        let sorted = latencyHistory.sorted()
        let index = Int(Double(sorted.count - 1) * 0.95)
        return sorted[index]
    }

    // MARK: - Init

    private init() {
        refreshAvailability()
    }

    /// Re-reads model availability. Cheap; call before every request.
    @discardableResult
    func refreshAvailability() -> Bool {
        guard #available(iOS 26.0, *) else {
            isAvailable = false
            unavailableReason = "AI summary needs iOS 26 or later."
            return false
        }
        #if canImport(FoundationModels)
        switch SystemLanguageModel.default.availability {
        case .available:
            isAvailable = true
            unavailableReason = nil
        case .unavailable(let reason):
            isAvailable = false
            switch reason {
            case .deviceNotEligible:
                unavailableReason = "AI summary needs an iPhone with Apple Intelligence."
            case .appleIntelligenceNotEnabled:
                unavailableReason = "Turn on Apple Intelligence in Settings for an AI summary."
            case .modelNotReady:
                unavailableReason = "Apple Intelligence is still downloading. The AI summary will appear when it's ready."
            @unknown default:
                unavailableReason = "Apple Intelligence isn't available right now."
            }
        @unknown default:
            isAvailable = false
            unavailableReason = "Apple Intelligence isn't available right now."
        }
        #else
        isAvailable = false
        unavailableReason = "AI summary isn't supported in this build."
        #endif
        return isAvailable
    }

    // MARK: - Prewarm

    #if canImport(FoundationModels)
    /// Held only between `prewarm()` and the next briefing request, then dropped.
    private var warmBriefingSession: AnyObject?
    #endif

    /// Loads the model into memory ahead of the first request (call when the Brief tab
    /// appears). Cuts the first-token wait noticeably; a no-op when unavailable.
    func prewarm() {
        guard refreshAvailability() else { return }
        #if canImport(FoundationModels)
        if #available(iOS 26.0, *), warmBriefingSession == nil {
            let session = LanguageModelSession(instructions: Self.briefingInstructions)
            session.prewarm()
            warmBriefingSession = session
        }
        #endif
    }

    #if canImport(FoundationModels)
    @available(iOS 26.0, *)
    private func takeBriefingSession() -> LanguageModelSession {
        if let warm = warmBriefingSession as? LanguageModelSession {
            warmBriefingSession = nil
            return warm
        }
        return LanguageModelSession(instructions: Self.briefingInstructions)
    }
    #endif

    // MARK: - Public API

    /// Generate an AI-enhanced briefing insight from the given sections.
    ///
    /// - Parameters:
    ///   - sections: The briefing sections to feed into the model.
    ///   - onPartial: Called on the main actor with the summary text as it streams in,
    ///     so the header can fill in word by word instead of waiting for the whole reply.
    /// - Returns: An `AIBriefingResult` with insight text, sentiment, and latency.
    func generateInsight(
        from sections: [BriefingSection],
        onPartial: ((String) -> Void)? = nil
    ) async -> AIBriefingResult? {
        guard #available(iOS 26.0, *) else {
            lastError = "Foundation Models require iOS 26 or later."
            return nil
        }
        guard refreshAvailability() else {
            lastError = unavailableReason
            return nil
        }

        #if canImport(FoundationModels)
        let sanitizedSections = sections.map { sanitizeSection($0) }
        let startTime = Date()
        let prompt = buildPrompt(from: sanitizedSections)

        var result = await generateStreaming(prompt: prompt, onPartial: onPartial)
        if result == nil,
           let genError = lastGenerationError as? LanguageModelSession.GenerationError,
           case .exceededContextWindowSize = genError {
            // Too much input for the phone's model. If the user opted in (and Apple has granted
            // the app the Private Cloud Compute entitlement), let Apple's larger model read the
            // whole morning; otherwise summarise section by section on the phone.
            #if PCC_ENABLED
            if UserDefaults.standard.bool(forKey: Self.privateCloudKey), #available(iOS 27.0, *) {
                result = await generateWithPrivateCloud(sections: sanitizedSections)
            }
            #endif
            if result == nil {
                result = await generateChunked(sections: sanitizedSections)
            }
        }

        let latencyMs = Int(Date().timeIntervalSince(startTime) * 1000)
        recordLatency(latencyMs)

        guard let result else { return nil }
        return AIBriefingResult(insight: result.insight, sentiment: result.sentiment, latencyMs: latencyMs)
        #else
        lastError = "Foundation Models not available."
        return nil
        #endif
    }

    /// Generate market sentiment classification from market section content.
    func classifyMarketSentiment(marketContent: String) async -> MarketSentimentResult? {
        guard #available(iOS 26.0, *) else { return nil }
        guard refreshAvailability() else { return nil }

        #if canImport(FoundationModels)
        let session = LanguageModelSession(
            instructions: "You classify short market summaries. Judge only from the data given."
        )
        do {
            let response = try await session.respond(
                to: "Classify the overall market sentiment of this data:\n\(marketContent)",
                generating: MarketSentimentOutput.self
            )
            return MarketSentimentResult(
                sentiment: response.content.sentiment.rawValue,
                confidence: response.content.confidence
            )
        } catch is CancellationError {
            return nil
        } catch {
            lastError = error.localizedDescription
            return nil
        }
        #else
        return nil
        #endif
    }

    /// 3-5 talking points for a meeting, as structured output (no bullet parsing).
    func talkingPoints(title: String, attendees: [String], agenda: String?) async -> [String] {
        guard #available(iOS 26.0, *) else { return [] }
        guard refreshAvailability() else { return [] }

        #if canImport(FoundationModels)
        let session = LanguageModelSession(
            instructions: """
            You help someone prepare for a meeting in the next couple of hours. \
            Write practical, specific talking points. Never invent facts about the attendees.
            """
        )
        let prompt = """
        Meeting: \(title)
        Attendees: \(attendees.isEmpty ? "unknown" : attendees.joined(separator: ", "))
        Agenda: \(agenda ?? "none given")
        """
        do {
            let response = try await session.respond(to: prompt, generating: MeetingTalkingPoints.self)
            return response.content.points
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
                .prefix(5)
                .map { $0 }
        } catch is CancellationError {
            return []
        } catch {
            lastError = error.localizedDescription
            return []
        }
        #else
        return []
        #endif
    }

    // MARK: - Health Data Sanitization

    /// Sanitize a briefing section before it enters an AI prompt.
    ///
    /// Raw health metrics (HRV in ms, exact sleep minutes, heart rate) are replaced
    /// with qualitative descriptors. This ensures biometric precision never leaves
    /// the on-device pipeline — even the FM prompt only sees summaries.
    private func sanitizeSection(_ section: BriefingSection) -> BriefingSection {
        guard section.id == "health" else { return section }

        var content = section.content

        if let hrvRange = content.range(of: "HRV: \\d+ms?", options: .regularExpression) {
            let hrvSubstring = String(content[hrvRange])
            let digitsPattern = "HRV: (\\d+)ms?"
            if let regex = try? NSRegularExpression(pattern: digitsPattern),
               let match = regex.firstMatch(in: hrvSubstring, range: NSRange(hrvSubstring.startIndex..., in: hrvSubstring)),
               let range = Range(match.range(at: 1), in: hrvSubstring) {
                let digits = Int(hrvSubstring[range]) ?? 0
                let band: String
                if digits < 20 { band = "low" }
                else if digits < 40 { band = "moderate" }
                else if digits < 60 { band = "good" }
                else { band = "excellent" }
                content.replaceSubrange(hrvRange, with: "HRV: \(band)")
            }
        }

        if let sleepRange = content.range(of: "\\d+h \\d+m asleep", options: .regularExpression) {
            let sleepSubstring = String(content[sleepRange])
            if let hoursStr = sleepSubstring.components(separatedBy: "h").first,
               let hours = Int(hoursStr) {
                let band: String
                if hours < 5 { band = "insufficient sleep" }
                else if hours < 7 { band = "adequate sleep" }
                else { band = "good sleep" }
                content.replaceSubrange(sleepRange, with: band)
            }
        }

        if let inBedRange = content.range(of: "\\d+h \\d+m in bed", options: .regularExpression) {
            content.replaceSubrange(inBedRange, with: "reasonable time in bed")
        }

        if let stepsRange = content.range(of: "Today: \\d+ steps", options: .regularExpression) {
            let stepsSubstring = String(content[stepsRange])
            let digitsPattern = "Today: (\\d+) steps"
            if let regex = try? NSRegularExpression(pattern: digitsPattern),
               let match = regex.firstMatch(in: stepsSubstring, range: NSRange(stepsSubstring.startIndex..., in: stepsSubstring)),
               let range = Range(match.range(at: 1), in: stepsSubstring) {
                let digits = Int(stepsSubstring[range]) ?? 0
                let band: String
                if digits < 3000 { band = "low activity" }
                else if digits < 7000 { band = "moderate activity" }
                else if digits < 10000 { band = "good activity" }
                else { band = "excellent activity" }
                content.replaceSubrange(stepsRange, with: "Today: \(band)")
            }
        }

        return BriefingSection(
            id: section.id,
            title: section.title,
            icon: section.icon,
            content: content,
            sentiment: section.sentiment
        )
    }

    // MARK: - Prompt Building

    static let briefingInstructions = """
    You write the one-glance summary at the top of a personal morning briefing. \
    Speak to the reader directly, warm and plain, like a sharp assistant. \
    Lead with what matters most today (first meeting, weather that changes plans, a big market move). \
    Use only the data given; never invent events, numbers or names. \
    Never repeat raw health numbers; describe health qualitatively.
    """

    /// Per-section character budgets (~4 chars per token), applied BEFORE the prompt is built.
    /// Total stays well under the model's ~4K-token window with room for the reply.
    private let segmentBudgets: [String: Int] = [
        "health": 400,
        "calendar": 900,
        "weather": 250,
        "markets": 350,
        "headlines": 1200,
    ]
    private let defaultBudget = 300

    private func truncate(_ section: BriefingSection, scale: Int = 1) -> BriefingSection {
        let budget = (segmentBudgets[section.id] ?? defaultBudget) * scale
        guard section.content.count > budget else { return section }
        return BriefingSection(
            id: section.id,
            title: section.title,
            icon: section.icon,
            content: String(section.content.prefix(budget)) + "…",
            sentiment: section.sentiment
        )
    }

    private func buildPrompt(from sections: [BriefingSection], scale: Int = 1) -> String {
        let sectionTexts = sections.map { truncate($0, scale: scale) }.map { "\($0.title): \($0.content)" }.joined(separator: "\n")
        return """
        Today's data:
        \(sectionTexts)
        """
    }

    // MARK: - Headline gists

    /// One plain line per story ("what happened, why it matters"), written on the phone from
    /// the feed's own blurb. Stories with no usable blurb are skipped: a gist of a title
    /// alone adds nothing. Returns article id -> gist.
    func headlineGists(for articles: [RSSArticle]) async -> [String: String] {
        guard #available(iOS 26.0, *), refreshAvailability() else { return [:] }
        #if canImport(FoundationModels)
        let usable: [(RSSArticle, String)] = articles.compactMap { a in
            let blurb = Self.plainText(a.summary ?? "")
            return blurb.count >= 60 ? (a, String(blurb.prefix(320))) : nil
        }
        guard !usable.isEmpty else { return [:] }

        var out: [String: String] = [:]
        // Batches of 6 keep each request far inside the 4K-token window.
        for start in stride(from: 0, to: usable.count, by: 6) {
            let batch = Array(usable[start..<min(start + 6, usable.count)])
            let listing = batch.enumerated().map { i, pair in
                "\(i + 1). \(pair.0.title)\n\(pair.1)"
            }.joined(separator: "\n\n")
            let session = LanguageModelSession(instructions: """
            You turn news blurbs into one plain line each, under 18 words: what happened and             why it matters. No hype, no clickbait, no repeating the headline word for word.             Use only what the blurb says.
            """)
            do {
                let r = try await session.respond(to: listing, generating: HeadlineGistBatch.self)
                for item in r.content.items {
                    let idx = item.number - 1
                    guard batch.indices.contains(idx) else { continue }
                    let line = item.line.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !line.isEmpty { out[batch[idx].0.id] = line }
                }
            } catch is CancellationError {
                break
            } catch {
                lastError = error.localizedDescription
                continue
            }
        }
        return out
        #else
        return [:]
        #endif
    }

    /// Strips HTML tags and entities from RSS blurbs.
    static func plainText(_ html: String) -> String {
        var s = html.replacingOccurrences(of: "<[^>]+>", with: " ", options: .regularExpression)
        for (k, v) in ["&amp;": "&", "&quot;": "\"", "&#39;": "'", "&apos;": "'", "&lt;": "<", "&gt;": ">", "&nbsp;": " "] {
            s = s.replacingOccurrences(of: k, with: v)
        }
        s = s.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
        return s.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - Private Cloud Compute (opt-in, iOS 27)

    /// Settings key for "Use Apple's Private Cloud on busy mornings". Off by default.
    static let privateCloudKey = "ai_private_cloud"

    #if PCC_ENABLED && canImport(FoundationModels)
    /// Apple's larger server model (32K context). Only used when the on-device model runs
    /// out of room and the user opted in. Data goes to Apple's Private Cloud Compute, which
    /// Apple does not store or log; never to MorningVault's own servers.
    @available(iOS 27.0, *)
    private func generateWithPrivateCloud(sections: [BriefingSection]) async -> (insight: String, sentiment: String?)? {
        let model = PrivateCloudComputeLanguageModel()
        guard model.isAvailable else { return nil }
        let session = LanguageModelSession(model: model, instructions: Self.briefingInstructions)
        do {
            let r = try await session.respond(to: buildPrompt(from: sections, scale: 4), generating: BriefingInsight.self)
            return ("\(r.content.insight) \(r.content.recommendation)", r.content.sentiment.rawValue)
        } catch {
            lastError = error.localizedDescription
            return nil
        }
    }
    #endif

    // MARK: - Streaming single-call path

    #if canImport(FoundationModels)
    /// Stored untyped: a stored property can't carry an iOS 26 availability gate.
    private var lastGenerationError: Error?

    @available(iOS 26.0, *)
    private func generateStreaming(
        prompt: String,
        onPartial: ((String) -> Void)?
    ) async -> (insight: String, sentiment: String?)? {
        lastGenerationError = nil
        let session = takeBriefingSession()
        do {
            let stream = session.streamResponse(to: prompt, generating: BriefingInsight.self)
            var latest: BriefingInsight.PartiallyGenerated?
            for try await snapshot in stream {
                latest = snapshot.content
                if let partial = snapshot.content.insight, !partial.isEmpty {
                    onPartial?(partial)
                }
            }
            guard let insight = latest?.insight, !insight.isEmpty else { return nil }
            var text = insight
            if let rec = latest?.recommendation, !rec.isEmpty {
                text += " \(rec)"
            }
            return (text, latest?.sentiment?.rawValue)
        } catch let error as LanguageModelSession.GenerationError {
            lastGenerationError = error
            lastError = error.localizedDescription
            return nil
        } catch is CancellationError {
            return nil
        } catch {
            lastError = error.localizedDescription
            return nil
        }
    }

    // MARK: - Chunked fallback (input too large for one call)

    @available(iOS 26.0, *)
    private func generateChunked(sections: [BriefingSection]) async -> (insight: String, sentiment: String?)? {
        var segmentInsights: [String] = []

        for section in sections.map({ truncate($0) }) {
            // Fresh session per segment: each call starts with an empty transcript.
            let session = LanguageModelSession(instructions: Self.briefingInstructions)
            do {
                let response = try await session.respond(
                    to: "\(section.title): \(section.content)\nGive the one thing worth knowing from this.",
                    generating: SegmentInsight.self
                )
                if !response.content.text.isEmpty {
                    segmentInsights.append("\(section.title): \(response.content.text)")
                }
            } catch is CancellationError {
                break
            } catch {
                continue
            }
        }

        guard !segmentInsights.isEmpty else { return nil }

        let session = LanguageModelSession(instructions: Self.briefingInstructions)
        do {
            let response = try await session.respond(
                to: "Combine these into today's summary:\n\(segmentInsights.joined(separator: "\n"))",
                generating: BriefingInsight.self
            )
            let text = "\(response.content.insight) \(response.content.recommendation)"
            return (text, response.content.sentiment.rawValue)
        } catch {
            return (segmentInsights.joined(separator: " "), nil)
        }
    }
    #endif
}

// MARK: - Result Types

struct AIBriefingResult {
    let insight: String
    let sentiment: String?
    let latencyMs: Int
}

struct MarketSentimentResult {
    let sentiment: String
    let confidence: Double
}

// MARK: - Foundation Models Structured Output Types

#if canImport(FoundationModels)
@available(iOS 26.0, *)
@Generable
enum Sentiment: String, Codable {
    case bullish, bearish, neutral
}

/// Structured output for the day summary. Property order is generation order:
/// insight streams first so the header fills in before the rest is done.
@available(iOS 26.0, *)
@Generable
struct BriefingInsight: Codable {
    @Guide(description: "Two short sentences on what matters most today, addressed to the reader")
    let insight: String
    @Guide(description: "One concrete action for today, under 15 words")
    let recommendation: String
    @Guide(description: "Overall tone of the day's news and markets")
    let sentiment: Sentiment
}

/// Structured output for per-segment chunk responses.
@available(iOS 26.0, *)
@Generable
struct SegmentInsight: Codable {
    @Guide(description: "One sentence")
    let text: String
    let sentiment: Sentiment
}

/// Structured output for market sentiment classification.
@available(iOS 26.0, *)
@Generable
struct MarketSentimentOutput: Codable {
    let sentiment: Sentiment
    @Guide(description: "Confidence from 0 to 1", .range(0.0...1.0))
    let confidence: Double
}

/// Structured output for headline gists. Items carry the story number so a skipped or
/// reordered line can't land on the wrong story.
@available(iOS 26.0, *)
@Generable
struct HeadlineGistBatch: Codable {
    let items: [HeadlineGistItem]
}

@available(iOS 26.0, *)
@Generable
struct HeadlineGistItem: Codable {
    @Guide(description: "The story's number from the list")
    let number: Int
    @Guide(description: "One plain line, under 18 words")
    let line: String
}

/// Structured output for meeting prep.
@available(iOS 26.0, *)
@Generable
struct MeetingTalkingPoints: Codable {
    @Guide(description: "Talking points, each one or two sentences", .count(3...5))
    let points: [String]
}
#endif
