import Foundation

/// Ollama-based briefing generator for MorningVault.
///
/// Uses Ollama running on the local network (Mac Mini at 100.79.215.108)
/// to generate the morning briefing from all data sources.
///
/// **Privacy contract:**
/// - Health data is SANITIZED before entering prompts (no raw HRV, sleep stages, etc.)
/// - `localOnly` mode is enforced: when enabled, no external AI calls
/// - Only uses Ollama when on-device Foundation Models are unavailable OR user explicitly opts in
///
/// Fallback: if Ollama is unreachable, returns nil and lets the caller
/// display the raw data sections without AI enhancement.
@MainActor
final class BriefingGeneratorService: ObservableObject {
    static let shared = BriefingGeneratorService()

    // MARK: - Config

    /// Ollama endpoint (Mac Mini on local network)
    private let ollamaURL = URL(string: "http://100.79.215.108:11434/api/generate")!

    /// Model to use
    private let model = "llama3.2:3b"

    // MARK: - State

    @Published private(set) var isGenerating = false
    @Published private(set) var lastError: String?

    // MARK: - Public API

    /// Generate a morning briefing by calling Ollama with all data sections.
    ///
    /// - Parameter sections: BriefingSection data from all sources (health, weather, calendar, markets, headlines)
    /// - Parameter localOnly: When true, skips external AI and returns nil
    /// - Returns: Generated briefing text, or nil if Ollama unreachable / localOnly / unavailable
    func generateBriefing(
        from sections: [BriefingSection],
        localOnly: Bool
    ) async -> String? {
        // Enforce localOnly — no external AI calls when enabled
        guard !localOnly else {
            print("[BriefingGenerator] localOnly=true — skipping Ollama")
            return nil
        }

        isGenerating = true
        lastError = nil
        defer { isGenerating = false }

        // Build the prompt from sections
        let prompt = buildBriefingPrompt(from: sections)

        // Call Ollama
        do {
            let result = try await callOllama(prompt: prompt)
            print("[BriefingGenerator] Ollama success: \(result.count) chars")
            return result
        } catch {
            lastError = error.localizedDescription
            print("[BriefingGenerator] Ollama failed: \(error.localizedDescription)")
            return nil
        }
    }

    // MARK: - Ollama API call

    private func callOllama(prompt: String) async throws -> String {
        var request = URLRequest(url: ollamaURL)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 30

        let body: [String: Any] = [
            "model": model,
            "prompt": prompt,
            "stream": false
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw OllamaError.invalidResponse
        }

        guard httpResponse.statusCode == 200 else {
            throw OllamaError.httpError(statusCode: httpResponse.statusCode)
        }

        // Parse Ollama response
        let json = try JSONDecoder().decode(OllamaResponse.self, from: data)

        guard !json.response.isEmpty else {
            throw OllamaError.emptyResponse
        }

        return json.response
    }

    // MARK: - Prompt building

    /// Builds a concise prompt for the morning briefing.
    /// Health data is sanitized — raw values replaced with qualitative descriptors.
    private func buildBriefingPrompt(from sections: [BriefingSection]) -> String {
        // Sanitize sections (strip raw health data before including in prompt)
        let sanitized = sections.map { sanitizeForAI($0) }

        // Format sections as a readable summary
        let sectionTexts = sanitized.map { section in
            "[\(section.title)]\n\(section.content)"
        }.joined(separator: "\n\n")

        return """
        You are a concise morning briefing assistant. Based on the following data, write a 2-3 paragraph morning briefing with key highlights from each section. Be actionable and specific.

        Do NOT include any raw health metrics (like exact HRV ms or step counts) — use qualitative descriptions only (e.g., "good sleep", "moderate activity").

        \(sectionTexts)

        Format your response as a clean 2-3 paragraph briefing. Start directly with the briefing — no preamble like "Here's your briefing."
        """
    }

    // MARK: - Health data sanitization (before AI prompt)

    /// Strip raw health values, replace with qualitative bands.
    /// This ensures biometric precision never leaves the device.
    private func sanitizeForAI(_ section: BriefingSection) -> BriefingSection {
        guard section.id == "health" else { return section }

        var content = section.content

        // Replace raw HRV values with qualitative bands
        if let hrvRange = content.range(of: "HRV: \\d+ms", options: .regularExpression) {
            let hrvSubstring = String(content[hrvRange])
            if let digits = hrvSubstring.components(separatedBy: CharacterSet.decimalDigits.inverted)
                .compactMap({ Int($0) }).first {
                let band: String
                if digits < 20 { band = "low HRV" }
                else if digits < 40 { band = "moderate HRV" }
                else if digits < 60 { band = "good HRV" }
                else { band = "excellent HRV" }
                content.replaceSubrange(hrvRange, with: band)
            }
        }

        // Replace exact step counts with activity bands
        if let stepsRange = content.range(of: "Today: \\d+ steps", options: .regularExpression) {
            let stepsSubstring = String(content[stepsRange])
            if let digits = stepsSubstring.components(separatedBy: CharacterSet.decimalDigits.inverted)
                .compactMap({ Int($0) }).first {
                let band: String
                if digits < 3000 { band = "low activity" }
                else if digits < 7000 { band = "moderate activity" }
                else if digits < 10000 { band = "good activity" }
                else { band = "excellent activity" }
                content.replaceSubrange(stepsRange, with: "Today: \(band)")
            }
        }

        // Replace raw sleep durations with qualitative
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

        return BriefingSection(
            id: section.id,
            title: section.title,
            icon: section.icon,
            content: content,
            sentiment: section.sentiment
        )
    }
}

// MARK: - Ollama Response

private struct OllamaResponse: Codable {
    let response: String
}

// MARK: - Errors

enum OllamaError: LocalizedError {
    case invalidResponse
    case httpError(statusCode: Int)
    case emptyResponse

    var errorDescription: String? {
        switch self {
        case .invalidResponse:
            return "Invalid response from Ollama"
        case .httpError(let code):
            return "Ollama HTTP error: \(code)"
        case .emptyResponse:
            return "Ollama returned empty response"
        }
    }
}