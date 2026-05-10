import Foundation

/// RSS feed parser — fetches user-selected news sources
/// No user tracking, no analytics.
final class RSSService: ObservableObject {
    static let shared = RSSService()

    @Published var feeds: [RSSFeedData] = []
    @Published var lastError: String?

    private let rssCacheKey = "com.morningvault.rssCache"

    /// URL map for available news sources
    private let sourceURLs: [String: String] = [
        "hacker-news": "https://hnrss.org/frontpage",
        "techcrunch": "https://techcrunch.com/feed/",
        "ars-technica": "https://feeds.arstechnica.com/arstechnica/index",
        "bbc": "https://feeds.bbci.co.uk/news/rss.xml",
        "reuters": "https://www.reutersagency.com/feed/",
        "ap": "https://apnews.com/rss",
        "npr": "https://feeds.npr.org/1001/rss.xml",
        "the-verge": "https://www.theverge.com/rss/index.xml",
        "wired": "https://www.wired.com/feed/rss",
        "bloomberg": "https://feeds.bloomberg.com/markets/news.rss"
    ]

    // MARK: - Cache

    private func cacheFeeds(_ feeds: [RSSFeedData]) {
        if let data = try? JSONEncoder().encode(feeds) {
            UserDefaults.standard.set(data, forKey: rssCacheKey)
        }
    }

    private func getCachedFeeds() -> [RSSFeedData] {
        guard let data = UserDefaults.standard.data(forKey: rssCacheKey),
              let feeds = try? JSONDecoder().decode([RSSFeedData].self, from: data) else {
            return []
        }
        return feeds
    }

    // MARK: - Fetch All Feeds

    func fetchAllFeeds() async -> [RSSFeedData] {
        if UserDefaults.standard.bool(forKey: "local_only") {
            return getCachedFeeds()
        }
        let selectedIds = loadSelectedSources()
        await fetchFeeds(ids: selectedIds)
        return feeds
    }

    func fetchFeeds(ids: [String]) async -> [RSSFeedData] {
        // Respect localOnly — no network calls if enabled
        if UserDefaults.standard.bool(forKey: "local_only") {
            let cached = getCachedFeeds()
            if !cached.isEmpty { return cached }
        }

        let results: [RSSFeedData] = await withTaskGroup(of: RSSFeedData?.self) { group in
            for id in ids {
                guard let urlString = sourceURLs[id] else { continue }
                group.addTask {
                    await self.fetchFeed(name: self.sourceDisplayName(for: id), urlString: urlString)
                }
            }

            var results: [RSSFeedData] = []
            for await result in group {
                if let feed = result {
                    results.append(feed)
                }
            }
            await MainActor.run { feeds = results
                cacheFeeds(results)
            }
            return results
        }
        return results
    }

    private func loadSelectedSources() -> [String] {
        let defaults = UserDefaults.standard
        guard let data = defaults.data(forKey: "selected_news_sources"),
              let decoded = try? JSONDecoder().decode([String].self, from: data) else {
            // Default to hacker-news if nothing selected
            return ["hacker-news"]
        }
        return decoded
    }

    private func sourceDisplayName(for id: String) -> String {
        let names: [String: String] = [
            "hacker-news": "Hacker News",
            "techcrunch": "TechCrunch",
            "ars-technica": "Ars Technica",
            "bbc": "BBC News",
            "reuters": "Reuters",
            "ap": "Associated Press",
            "npr": "NPR",
            "the-verge": "The Verge",
            "wired": "Wired",
            "bloomberg": "Bloomberg"
        ]
        return names[id] ?? id.capitalized
    }

    // MARK: - Fetch Single Feed

    private func fetchFeed(name: String, urlString: String) async -> RSSFeedData? {
        guard let url = URL(string: urlString) else { return nil }

        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            return parseFeed(name: name, data: data)
        } catch {
            await MainActor.run { lastError = "Failed to fetch \(name): \(error.localizedDescription)" }
            return nil
        }
    }

    // MARK: - Parse RSS/Atom

    private func parseFeed(name: String, data: Data) -> RSSFeedData {
        let parser = RSSParser(data: data)
        let articles = parser.parse()
        return RSSFeedData(id: name.lowercased().replacingOccurrences(of: " ", with: "-"),
                           sourceName: name,
                           articles: articles)
    }
}

// MARK: - Simple on-device RSS/Atom Parser

final class RSSParser {
    private let data: Data

    init(data: Data) {
        self.data = data
    }

    func parse() -> [RSSArticle] {
        if let articles = parseRSS2() { return articles }
        if let articles = parseAtom() { return articles }
        return []
    }

    private func parseRSS2() -> [RSSArticle]? {
        guard let xmlString = String(data: data, encoding: .utf8) else { return nil }
        guard xmlString.contains("<rss") else { return nil }

        var articles: [RSSArticle] = []
        let itemPattern = #"<item>(.*?)</item>"#
        guard let regex = try? NSRegularExpression(pattern: itemPattern, options: [.dotMatchesLineSeparators]) else { return nil }
        let range = NSRange(xmlString.startIndex..., in: xmlString)
        let matches = regex.matches(in: xmlString, options: [], range: range)

        for match in matches.prefix(10) {
            guard let itemRange = Range(match.range(at: 1), in: xmlString) else { continue }
            let itemXML = String(xmlString[itemRange])

            let title = extractTag("title", from: itemXML)
            let link = extractTag("link", from: itemXML)
            let description = extractTag("description", from: itemXML)
            let pubDate = extractTag("pubDate", from: itemXML)

            guard !title.isEmpty else { continue }

            articles.append(RSSArticle(
                id: link.hashValue.description,
                title: cleanHTML(title),
                url: link,
                publishedAt: parseDate(pubDate),
                summary: cleanHTML(description).prefix(200).description
            ))
        }

        return articles
    }

    private func parseAtom() -> [RSSArticle]? {
        guard let xmlString = String(data: data, encoding: .utf8) else { return nil }
        guard xmlString.contains("<feed") else { return nil }

        var articles: [RSSArticle] = []
        let entryPattern = #"<entry>(.*?)</entry>"#
        guard let regex = try? NSRegularExpression(pattern: entryPattern, options: [.dotMatchesLineSeparators]) else { return nil }
        let range = NSRange(xmlString.startIndex..., in: xmlString)
        let matches = regex.matches(in: xmlString, options: [], range: range)

        for match in matches.prefix(10) {
            guard let entryRange = Range(match.range(at: 1), in: xmlString) else { continue }
            let entryXML = String(xmlString[entryRange])

            let title = extractTag("title", from: entryXML)
            let link = extractAtomLink(from: entryXML)
            let summary = extractTag("summary", from: entryXML)
            let updated = extractTag("updated", from: entryXML)

            guard !title.isEmpty else { continue }

            articles.append(RSSArticle(
                id: link.hashValue.description,
                title: cleanHTML(title),
                url: link,
                publishedAt: parseDate(updated),
                summary: cleanHTML(summary).prefix(200).description
            ))
        }

        return articles
    }

    private func extractTag(_ tag: String, from xml: String) -> String {
        let pattern = "<\(tag)[^>]*><!\\[CDATA\\[(.*?)\\]\\]></\(tag)>|<\(tag)[^>]*>(.*?)</\(tag)>"
        let regex = try? NSRegularExpression(pattern: pattern, options: [.dotMatchesLineSeparators])
        let range = NSRange(xml.startIndex..., in: xml)
        if let match = regex?.firstMatch(in: xml, options: [], range: range) {
            for i in 1..<match.numberOfRanges {
                if let r = Range(match.range(at: i), in: xml) {
                    return String(xml[r]).trimmingCharacters(in: .whitespacesAndNewlines)
                }
            }
        }
        return ""
    }

    private func extractAtomLink(from xml: String) -> String {
        let pattern = ##"<link[^>]*href=["']([^"']+)["'][^>]*>"##
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else { return "" }
        let range = NSRange(xml.startIndex..., in: xml)
        if let match = regex.firstMatch(in: xml, options: [], range: range),
           let r = Range(match.range(at: 1), in: xml) {
            return String(xml[r])
        }
        return ""
    }

    private func cleanHTML(_ text: String) -> String {
        text.replacingOccurrences(of: #"<[^>]+>"# , with: "", options: .regularExpression)
            .replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&#8216;", with: "'")
            .replacingOccurrences(of: "&#8217;", with: "'")
            .replacingOccurrences(of: "&#39;", with: "'")
            .replacingOccurrences(of: "&nbsp;", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func parseDate(_ string: String) -> Date? {
        let formatters: [DateFormatter] = [
            {
                let f = DateFormatter()
                f.dateFormat = "EEE, dd MMM yyyy HH:mm:ss Z"
                f.locale = Locale(identifier: "en_US_POSIX")
                return f
            }(),
            {
                let f = DateFormatter()
                f.dateFormat = "yyyy-MM-dd'T'HH:mm:ssZ"
                f.locale = Locale(identifier: "en_US_POSIX")
                return f
            }()
        ]
        for f in formatters {
            if let d = f.date(from: string) { return d }
        }
        return nil
    }
}