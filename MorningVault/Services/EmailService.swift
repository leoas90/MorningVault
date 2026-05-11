import Foundation
import MessageUI

/// Service for sharing briefings and highlights via email.
/// Uses MFMailComposeViewController via UIKit integration.
actor EmailService {
    private let defaults = UserDefaults.standard
    private let storageKey = "email_share_config"

    struct EmailConfig: Codable {
        var recipientEmail: String?
        var defaultSubject: String
        var includeAIHighlights: Bool
        var includeSections: [String]
    }

    private var config: EmailConfig {
        get {
            guard let data = defaults.data(forKey: storageKey),
                  let config = try? JSONDecoder().decode(EmailConfig.self, from: data) else {
                return EmailConfig(defaultSubject: "My Morning Briefing", includeAIHighlights: true, includeSections: [])
            }
            return config
        }
        set {
            if let data = try? JSONEncoder().encode(newValue) {
                defaults.set(data, forKey: storageKey)
            }
        }
    }

    func setRecipientEmail(_ email: String) async {
        var current = config
        current.recipientEmail = email
        config = current
    }

    func getRecipientEmail() -> String? {
        config.recipientEmail
    }

    func setDefaultSubject(_ subject: String) async {
        var current = config
        current.defaultSubject = subject
        config = current
    }

    func setIncludeAIHighlights(_ include: Bool) async {
        var current = config
        current.includeAIHighlights = include
        config = current
    }

    // MARK: - Email Composition

    @MainActor
    func canSendEmail() -> Bool {
        MFMailComposeViewController.canSendMail()
    }

    /// Build email body from briefing sections
    func buildEmailBody(
        sections: [BriefingSection],
        aiSummary: String?,
        highlights: [Highlight],
        mood: MoodType?,
        includeHighlights: Bool
    ) -> String {
        var body = ""

        // Header
        let dateFormatter = DateFormatter()
        dateFormatter.dateStyle = .full
        body += "☀️ Morning Briefing — \(dateFormatter.string(from: Date()))\n"
        if let mood = mood {
            body += "Mood: \(mood.emoji) \(mood.label)\n"
        }
        body += "\n"

        // AI Summary
        if let summary = aiSummary {
            body += "🤖 AI Summary\n"
            body += "\(summary)\n\n"
        }

        // Sections
        body += "📋 Briefing Sections\n"
        body += "—" + String(repeating: "—", count: 30) + "\n\n"

        for section in sections {
            body += "\(section.icon) \(section.title)\n"
            body += "\(section.content)\n\n"
        }

        // Highlights
        if includeHighlights && !highlights.isEmpty {
            body += "✨ Your Highlights\n"
            body += "—" + String(repeating: "—", count: 20) + "\n"
            for highlight in highlights {
                body += "• \"\(highlight.text)\"\n"
                if let note = highlight.note {
                    body += "  Note: \(note)\n"
                }
            }
            body += "\n"
        }

        // Footer
        body += "\n---\n"
        body += "Sent from MorningVault — Your privacy-first morning briefing app.\n"
        body += "All data stays on your device.\n"

        return body
    }

    /// Build plain text email for mailto: fallback
    func buildMailtoBody(
        sections: [BriefingSection],
        aiSummary: String?,
        mood: MoodType?
    ) -> String {
        var body = ""

        let dateFormatter = DateFormatter()
        dateFormatter.dateStyle = .full
        body += "Morning Briefing — \(dateFormatter.string(from: Date()))\n\n"

        if let summary = aiSummary {
            body += "AI: \(summary)\n\n"
        }

        for section in sections {
            body += "\(section.icon) \(section.title): \(section.content)\n\n"
        }

        return body
    }
}

// MARK: - Shared Instance

let emailService = EmailService()