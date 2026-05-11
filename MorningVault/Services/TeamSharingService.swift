import Foundation

/// Service for team sharing of briefings and highlights.
/// Shares via deep links, airdrop, or export.
actor TeamSharingService {
    private let defaults = UserDefaults.standard
    private let storageKey = "team_share_config"

    struct TeamConfig: Codable {
        var teamName: String?
        var sharedWithEmails: [String]
        var shareHighlights: Bool
        var shareCalendar: Bool
        var shareMarketPositions: Bool
    }

    private var config: TeamConfig {
        get {
            guard let data = defaults.data(forKey: storageKey),
                  let config = try? JSONDecoder().decode(TeamConfig.self, from: data) else {
                return TeamConfig(sharedWithEmails: [], shareHighlights: true, shareCalendar: false, shareMarketPositions: false)
            }
            return config
        }
        set {
            if let data = try? JSONEncoder().encode(newValue) {
                defaults.set(data, forKey: storageKey)
            }
        }
    }

    // MARK: - Configuration

    func setTeamName(_ name: String) async {
        var current = config
        current.teamName = name
        config = current
    }

    func getTeamName() -> String? {
        config.teamName
    }

    func addTeamMember(email: String) async {
        var current = config
        if !current.sharedWithEmails.contains(email) {
            current.sharedWithEmails.append(email)
            config = current
        }
    }

    func removeTeamMember(email: String) async {
        var current = config
        current.sharedWithEmails.removeAll { $0 == email }
        config = current
    }

    func getTeamMembers() -> [String] {
        config.sharedWithEmails
    }

    func setShareHighlights(_ share: Bool) async {
        var current = config
        current.shareHighlights = share
        config = current
    }

    func setShareCalendar(_ share: Bool) async {
        var current = config
        current.shareCalendar = share
        config = current
    }

    func setShareMarketPositions(_ share: Bool) async {
        var current = config
        current.shareMarketPositions = share
        config = current
    }

    // MARK: - Share Item Creation

    func createShareItem(type: ShareItem.ShareType, content: String, recipientName: String? = nil, recipientEmail: String? = nil) async -> ShareItem {
        ShareItem(
            id: UUID().uuidString,
            type: type,
            content: content,
            createdAt: Date(),
            recipientName: recipientName,
            recipientEmail: recipientEmail
        )
    }

    /// Build shareable text from briefing sections
    func buildShareText(
        sections: [BriefingSection],
        aiSummary: String?,
        highlights: [Highlight],
        mood: MoodType?
    ) async -> String {
        var text = ""

        // Header
        let dateFormatter = DateFormatter()
        dateFormatter.dateStyle = .medium
        text += "☀️ Morning Briefing — \(dateFormatter.string(from: Date()))\n"
        if let mood = mood {
            text += "Mood: \(mood.emoji) \(mood.label)\n"
        }
        text += "\n"

        // AI Summary
        if let summary = aiSummary {
            text += "🤖 \(summary)\n\n"
        }

        // Filter sections based on config
        let shareableSections = sections.filter { section in
            switch section.id {
            case "health": return config.shareHighlights
            case "calendar": return config.shareCalendar
            case "markets": return config.shareMarketPositions
            default: return true
            }
        }

        // Sections
        for section in shareableSections {
            text += "\(section.icon) \(section.title)\n"
            text += "\(section.content)\n\n"
        }

        // Highlights
        if config.shareHighlights && !highlights.isEmpty {
            text += "✨ Highlights\n"
            for highlight in highlights {
                text += "• \"\(highlight.text)\"\n"
                if let note = highlight.note {
                    text += "  → \(note)\n"
                }
            }
            text += "\n"
        }

        text += "— Shared via MorningVault"

        return text
    }

    /// Build a deep link for sharing a specific briefing
    func buildDeepLink(briefingId: String) -> URL? {
        URL(string: "morningvault://briefing/\(briefingId)")
    }

    /// Build an AirDrop-compatible share text
    func buildAirDropText(
        sections: [BriefingSection],
        aiSummary: String?
    ) async -> String {
        var text = "Morning Briefing\n"

        if let summary = aiSummary {
            text += "\(summary)\n\n"
        }

        for section in sections {
            text += "\(section.icon) \(section.title): \(section.content)\n"
        }

        return text
    }
}

// MARK: - Shared Instance

let teamSharing = TeamSharingService()