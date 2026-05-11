import Foundation

// MARK: - Highlight Model

struct Highlight: Codable, Identifiable, Equatable {
    let id: String
    let sectionId: String
    let text: String
    var note: String?
    let createdAt: Date
    var mood: String?

    init(sectionId: String, text: String, note: String? = nil, mood: String? = nil) {
        self.id = UUID().uuidString
        self.sectionId = sectionId
        self.text = text
        self.note = note
        self.createdAt = Date()
        self.mood = mood
    }
}

// MARK: - Mood Types

enum MoodType: String, Codable, CaseIterable {
    case inspired = "inspired"
    case focused = "focused"
    case alert = "alert"
    case calm = "calm"
    case energetic = "energetic"
    case reflective = "reflective"
    case motivated = "motivated"
    case neutral = "neutral"

    var emoji: String {
        switch self {
        case .inspired: return "✨"
        case .focused: return "🎯"
        case .alert: return "⚡"
        case .calm: return "🧘"
        case .energetic: return "🚀"
        case .reflective: return "🤔"
        case .motivated: return "💪"
        case .neutral: return "😐"
        }
    }

    var label: String {
        rawValue.capitalized
    }
}

// MARK: - Briefing Archive Entry

struct BriefingArchiveEntry: Codable, Identifiable {
    let id: String
    let date: Date
    let sections: [BriefingSection]
    let aiSummary: String?
    let mood: MoodType?
    let highlights: [Highlight]

    var formattedDate: String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        return formatter.string(from: date)
    }

    var dayOfWeek: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEEE"
        return formatter.string(from: date)
    }
}

// MARK: - Share Item

struct ShareItem: Codable, Identifiable {
    let id: String
    let type: ShareType
    let content: String
    let createdAt: Date
    let recipientName: String?
    let recipientEmail: String?

    enum ShareType: String, Codable {
        case briefing = "briefing"
        case section = "section"
        case highlight = "highlight"
    }
}

// MARK: - Later Service Models

struct LaterItem: Codable, Identifiable {
    let id: String
    let title: String
    let url: String
    let source: String
    let addedAt: Date
    let sectionId: String?

    enum Source: String, Codable {
        case pocket = "pocket"
        case instapaper = "instapaper"
    }
}

struct LaterServiceConfig: Codable {
    var pocketAuthToken: String?
    var instapaperUsername: String?
    var instapaperPassword: String?
    var isPocketEnabled: Bool
    var isInstapaperEnabled: Bool
}

// MARK: - Contextual Signal

struct ContextualSignal: Codable, Identifiable {
    let id: String
    let type: SignalType
    let title: String
    let message: String
    let icon: String
    let priority: Int
    let createdAt: Date

    enum SignalType: String, Codable {
        case greeting = "greeting"
        case weather = "weather"
        case health = "health"
        case calendar = "calendar"
        case market = "market"
        case custom = "custom"
    }

    var isHighPriority: Bool {
        priority >= 8
    }
}