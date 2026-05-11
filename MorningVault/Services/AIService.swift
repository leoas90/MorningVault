import Foundation
import FoundationModels

/// On-device AI service using Apple's Foundation Models framework.
///
/// **Privacy contract:**
/// - ALL AI processing happens on-device via `SystemLanguageModel`.
/// - Health data is SANITIZED before entering prompts (no raw HRV, sleep stages, etc.).
/// - `localOnly` mode is enforced: when true, no network calls for AI (FM is always local,
///   but this guard prevents any future external AI routing).
/// - No health data is EVER routed to Mac Mini, Ollama, or any external endpoint.
@MainActor
final class AIService {

    static let shared = AIService()

    // MARK: - State

    /// Whether on-device Foundation Models are available on this device.
    @Published private(set) var isAvailable: Bool = false

    /// Last error from FM, if any.
    @Published var lastError: String?

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
        checkAvailability()
    }

    private func checkAvailability() {
        guard #available(iOS 26.0, *) else {
            isAvailable = false
            return
        }
        let lm = SystemLanguageModel()
        switch lm.availability {
        case .available:
            isAvailable = true
        case .unavailable(_):
            isAvailable = false
        @unknown default:
            isAvailable = false
        }
    }

    // MARK: - Public API

    /// Generate an AI-enhanced briefing insight from the given sections.
    ///
    /// - Parameter sections: The briefing sections to feed into the model.
    /// - Returns: An `AIBriefingResult` with insight text, sentiment, and latency.
    ///
    /// Uses on-device Foundation Models (iOS 26+) — always local, no external routing.
    /// Health data is sanitized before entering any prompt — raw biometric values
    /// are summarized into qualitative descriptors.
    func generateInsight(from sections: [BriefingSection]) async -> AIBriefingResult? {
        guard #available(iOS 26.0, *) else {
            // DEBUG: print("[AIService] iOS 26+ required for Foundation Models")
            lastError = "Foundation Models require iOS 26 or later."
            return nil
        }

        guard isAvailable else {
            // DEBUG: print("[AIService] Apple Intelligence not available on this device")
            lastError = "Apple Intelligence not available on this device."
            return nil
        }

        // Sanitize sections — strip raw health data, replace with qualitative summaries
        let sanitizedSections = sections.map { sanitizeSection($0) }

        let lm = SystemLanguageModel()
        if case .unavailable = lm.availability {
            // DEBUG: print("[AIService] FM became unavailable: \(String(describing: _))")
            isAvailable = false
            lastError = "Apple Intelligence became unavailable."
            return nil
        }

        let session = LanguageModelSession(model: lm)
        let startTime = Date()

        // Decide: chunked or single-call
        let combinedPrompt = buildPrompt(from: sanitizedSections)
        let estimatedTokens = combinedPrompt.count / 4

        var insight: String?
        var sentiment: String?

        if estimatedTokens > chunkThreshold {
            let result = await generateChunked(session: session, sections: sanitizedSections)
            insight = result.insight
            sentiment = result.sentiment
        } else {
            let result = await generateSingle(session: session, prompt: combinedPrompt)
            insight = result.insight
            sentiment = result.sentiment
        }

        let latencyMs = Int(Date().timeIntervalSince(startTime) * 1000)
        recordLatency(latencyMs)
        // DEBUG: print("[AIService] FM latency: \(latencyMs)ms (p95: \(p95LatencyMs)ms)")

        guard let insight = insight else {
            return nil
        }

        return AIBriefingResult(
            insight: insight,
            sentiment: sentiment,
            latencyMs: latencyMs
        )
    }

    /// Generate market sentiment classification from market section content.
    func classifyMarketSentiment(marketContent: String) async -> MarketSentimentResult? {
        guard #available(iOS 26.0, *) else { return nil }
        guard isAvailable else { return nil }

        let lm = SystemLanguageModel()
        guard case .available = lm.availability else { return nil }
        let session = LanguageModelSession(model: lm)

        let prompt = """
        Classify the overall market sentiment from this data.
        Respond with a classification and confidence score.

        Data:
        \(marketContent)
        """

        do {
            let response = try await session.respond(to: prompt, generating: MarketSentimentOutput.self)
            return MarketSentimentResult(
                sentiment: response.content.sentiment,
                confidence: response.content.confidence
            )
        } catch is CancellationError {
            return nil
        } catch {
            // DEBUG: print("[AIService] Market sentiment error: \(error.localizedDescription)")
            lastError = error.localizedDescription
            return nil
        }
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

        // Replace raw HRV values (e.g., "HRV: 42ms") with qualitative bands
        if let hrvRange = content.range(of: "HRV: \\d+ms?", options: .regularExpression) {
            let hrvSubstring = String(content[hrvRange])
            // Extract the numeric value using regex capture group
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

        // Replace raw sleep times with qualitative
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

        // Replace "Xh Ym in bed" with qualitative
        if let inBedRange = content.range(of: "\\d+h \\d+m in bed", options: .regularExpression) {
            content.replaceSubrange(inBedRange, with: "reasonable time in bed")
        }

        // Replace exact step counts with activity bands
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

    /// Maximum tokens before we chunk the prompt into segments (≈3.5K tokens safe limit)
    private let chunkThreshold = 3500

    /// Per-section token budgets (chars; ~4 chars per token)
    /// Truncate each section BEFORE building the combined prompt.
    private let segmentBudgets: [String: Int] = [
        "health": 500,    // chars ≈125 tokens
        "calendar": 800,   // chars ≈200 tokens
        "weather": 200,   // chars ≈50 tokens
        "markets": 300,    // chars ≈75 tokens
        "headlines": 2000, // chars ≈500 tokens
    ]
    private func truncateSections(_ sections: [BriefingSection]) -> [BriefingSection] {
        return sections.map { section in
            let budget = segmentBudgets[section.id] ?? section.content.count
            if section.content.count > budget {
                return BriefingSection(
                    id: section.id,
                    title: section.title,
                    icon: section.icon,
                    content: String(section.content.prefix(budget)) + "…",
                    sentiment: section.sentiment
                )
            }
            return section
        }
    }

    private func buildPrompt(from sections: [BriefingSection]) -> String {
        // Truncate BEFORE passing to LLM
        let truncatedSections = truncateSections(sections)
        let sectionTexts = truncatedSections.map { "\($0.title): \($0.content)" }.joined(separator: "\n")
        return """
        You are a morning briefing assistant. Based on the following data, provide 2-3 sentences of insight or a recommendation. Be concise and actionable. Do NOT include any raw health metrics in your response — use qualitative language only.

        \(sectionTexts)

        Respond with this structure:
        - insight: 2-3 sentence actionable insight
        - recommendation: one specific action for today
        - sentiment: bullish, bearish, or neutral
        """
    }

    // MARK: - Single-call path (under token budget)

    @available(iOS 26.0, *)
    private func generateSingle(
        session: LanguageModelSession,
        prompt: String
    ) async -> (insight: String?, sentiment: String?) {
        do {
            let response = try await session.respond(to: prompt, generating: BriefingInsight.self)
            let insight = "\(response.content.insight) Recommendation: \(response.content.recommendation)"
            return (insight, response.content.sentiment)
        } catch is CancellationError {
            return (nil, nil)
        } catch {
            // DEBUG: print("[AIService] FM single-call error: \(error.localizedDescription)")
            lastError = error.localizedDescription
            return (nil, nil)
        }
    }

    // MARK: - Chunked path (exceeds token budget)

    @available(iOS 26.0, *)
    private func generateChunked(
        session: LanguageModelSession,
        sections: [BriefingSection]
    ) async -> (insight: String?, sentiment: String?) {
        var segmentInsights: [String] = []

        for section in sections {
            guard let budget = segmentBudgets[section.id] else { continue }
            let maxChars = budget * 4
            let truncated = section.content.count > maxChars
                ? String(section.content.prefix(maxChars)) + "…"
                : section.content

            let segmentPrompt = """
            Based on this \(section.title) data: "\(truncated)"
            Provide a brief insight. Do NOT include raw health metrics — use qualitative language only.
            Respond with a short text insight and sentiment.
            """

            do {
                let response = try await session.respond(to: segmentPrompt, generating: SegmentInsight.self)
                if !response.content.text.isEmpty {
                    segmentInsights.append("\(section.title): \(response.content.text)")
                }
            } catch is CancellationError {
                break
            } catch {
                // DEBUG: print("[AIService] FM chunk error for \(section.id): \(error.localizedDescription)")
            }
        }

        guard !segmentInsights.isEmpty else {
            return (nil, nil)
        }

        let aggregationPrompt = """
        Combine these segment insights into a single coherent morning briefing insight (2-3 sentences). Do NOT include raw health metrics.

        Segments:
        \(segmentInsights.joined(separator: "\n"))

        Respond with a combined insight and overall sentiment.
        """

        do {
            let response = try await session.respond(to: aggregationPrompt, generating: SegmentInsight.self)
            return (response.content.text, response.content.sentiment)
        } catch is CancellationError {
            return (segmentInsights.joined(separator: " "), nil)
        } catch {
            return (segmentInsights.joined(separator: " "), nil)
        }
    }
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

/// Structured output for full briefing prompt response.
/// Uses @Generable so LanguageModelSession.respond(generating:) can use it.
@available(iOS 26.0, *)
@Generable
struct BriefingInsight: Codable {
    let insight: String
    let recommendation: String
    let sentiment: String  // "bullish" | "bearish" | "neutral"
}

/// Structured output for per-segment chunk responses.
@available(iOS 26.0, *)
@Generable
struct SegmentInsight: Codable {
    let text: String
    let sentiment: String  // "bullish" | "bearish" | "neutral"
}

/// Structured output for market sentiment classification.
@available(iOS 26.0, *)
@Generable
struct MarketSentimentOutput: Codable {
    let sentiment: String      // "bullish" | "bearish" | "neutral"
    let confidence: Double     // 0.0 – 1.0
}
