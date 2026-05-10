import Foundation

/// Canonical list of available RSS news sources for MorningVault.
/// Shared between RSSService, SourcesView, and OnboardingSourcesStep.
/// Single source of truth — one place to add/remove sources.
enum NewsSource: String, CaseIterable, Codable, Identifiable {
    case hackerNews = "hacker-news"
    case techCrunch = "techcrunch"
    case arsTechnica = "ars-technica"
    case bbc = "bbc"
    case reuters = "reuters"
    case associatedPress = "ap"
    case npr = "npr"
    case theVerge = "the-verge"
    case wired = "wired"
    case bloomberg = "bloomberg"
    case mit = "mit"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .hackerNews: return "Hacker News"
        case .techCrunch: return "TechCrunch"
        case .arsTechnica: return "Ars Technica"
        case .bbc: return "BBC News"
        case .reuters: return "Reuters"
        case .associatedPress: return "Associated Press"
        case .npr: return "NPR"
        case .theVerge: return "The Verge"
        case .wired: return "Wired"
        case .bloomberg: return "Bloomberg"
        case .mit: return "MIT News"
        }
    }

    var feedURL: String {
        switch self {
        case .hackerNews: return "https://hnrss.org/frontpage"
        case .techCrunch: return "https://techcrunch.com/feed/"
        case .arsTechnica: return "https://feeds.arstechnica.com/arstechnica/index"
        case .bbc: return "https://feeds.bbci.co.uk/news/rss.xml"
        case .reuters: return "https://www.reutersagency.com/feed/"
        case .associatedPress: return "https://apnews.com/rss"
        case .npr: return "https://feeds.npr.org/1001/rss.xml"
        case .theVerge: return "https://www.theverge.com/rss/index.xml"
        case .wired: return "https://www.wired.com/feed/rss"
        case .bloomberg: return "https://feeds.bloomberg.com/markets/news.rss"
        case .mit: return "https://news.mit.edu/rss/research"
        }
    }

    var icon: String {
        switch self {
        case .hackerNews: return "chevron.left.forwardslash.chevron.right"
        case .techCrunch: return "dollarsign.circle"
        case .arsTechnica: return "atom"
        case .bbc: return "globe"
        case .reuters: return "bolt"
        case .associatedPress: return "newspaper"
        case .npr: return "waveform"
        case .theVerge: return "desktopcomputer"
        case .wired: return "wifi"
        case .bloomberg: return "chart.line.uptrend.xyaxis"
        case .mit: return "graduationcap"
        }
    }

    var description: String {
        switch self {
        case .hackerNews: return "Tech & startup news from the community"
        case .techCrunch: return "Startup and tech industry coverage"
        case .arsTechnica: return "In-depth tech, science and policy"
        case .bbc: return "World news and UK coverage"
        case .reuters: return "Breaking news and financial updates"
        case .associatedPress: return "Reliable national and world news"
        case .npr: return "National public radio news"
        case .theVerge: return "Tech culture and product news"
        case .wired: return "Tech magazine longform stories"
        case .bloomberg: return "Business and financial news"
        case .mit: return "MIT research and innovation news"
        }
    }
}

/// Loads the user's selected news sources from UserDefaults.
func loadSelectedSources() -> [NewsSource] {
    guard let data = UserDefaults.standard.data(forKey: "selected_news_sources"),
          let ids = try? JSONDecoder().decode([String].self, from: data) else {
        // Default: Hacker News only
        return [.hackerNews]
    }
    return ids.compactMap { NewsSource(rawValue: $0) }
}

/// Saves the user's selected news sources to UserDefaults.
func saveSelectedSources(_ sources: [NewsSource]) {
    let ids = sources.map { $0.rawValue }
    if let encoded = try? JSONEncoder().encode(ids) {
        UserDefaults.standard.set(encoded, forKey: "selected_news_sources")
    }
}