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
        "mit": "https://news.mit.edu/rss/research"
    ]

    /// Sources with default enabled state
    private let defaultEnabledSources = ["hacker-news"]

    // MARK: - Public API

    func fetchAllFeeds() async -> [RSSFeedData] {
        if UserDefaults.standard.bool(forKey: "local_only") {
            return getCachedFeeds()
        }
        _ = await fetchFeeds(ids: loadSelectedSources())
        return feeds
    }

    func fetchFeeds(ids: [String]) async -> [RSSFeedData] {
        // Respect localOnly — no network calls if enabled
        if UserDefaults.standard.bool(forKey: "local_only") {
            let cached = getCachedFeeds()
            if !cached.isEmpty { return cached }
        }

        let collected: [RSSFeedData] = await withTaskGroup(of: RSSFeedData?.self) { group in
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
            return results
        }

        await MainActor.run {
            feeds = collected
            cacheFeeds(collected)
        }
        return collected
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
            "mit": "MIT News"
        ]
        return names[id] ?? id
    }

    // MARK: - Fetch Single Feed

    private func fetchFeed(name: String, urlString: String) async -> RSSFeedData? {
        guard let url = URL(string: urlString) else { return nil }

        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            let articles = parseFeed(data: data, sourceName: name)

            return RSSFeedData(
                id: name.lowercased().replacingOccurrences(of: " ", with: "-"),
                sourceName: name,
                articles: articles
            )
        } catch {
            return nil
        }
    }

    // MARK: - XML Parsing

    private func parseFeed(data: Data, sourceName: String) -> [RSSArticle] {
        guard let xmlString = String(data: data, encoding: .utf8) else { return [] }

        // Try RSS2 first
        if let articles = parseRSS2(xmlString, source: sourceName) {
            return articles
        }
        // Fall back to Atom
        if let articles = parseAtom(xmlString, source: sourceName) {
            return articles
        }
        return []
    }

    private func parseRSS2(_ xml: String, source: String) -> [RSSArticle]? {
        var articles: [RSSArticle] = []

        // Use NSRegularExpression for better XML parsing
        guard let regex = try? NSRegularExpression(pattern: "<item>(.*?)</item>", options: [.dotMatchesLineSeparators]) else {
            return nil
        }

        let range = NSRange(xml.startIndex..., in: xml)
        let matches = regex.matches(in: xml, options: [], range: range)

        for match in matches.prefix(10) {
            guard let itemRange = Range(match.range(at: 1), in: xml) else { continue }
            let itemXML = String(xml[itemRange])

            guard let title = extractTag("title", from: itemXML),
                  let link = extractTag("link", from: itemXML) else { continue }

            let pubDate = extractTag("pubDate", from: itemXML).flatMap { parseDate($0) }
            let summary = extractTag("description", from: itemXML).map { stripHTML($0) }

            articles.append(RSSArticle(
                id: link,
                title: title,
                url: link,
                publishedAt: pubDate,
                summary: summary
            ))
        }

        return articles.isEmpty ? nil : articles
    }

    private func parseAtom(_ xml: String, source: String) -> [RSSArticle]? {
        var articles: [RSSArticle] = []

        guard let regex = try? NSRegularExpression(pattern: "<entry>(.*?)</entry>", options: [.dotMatchesLineSeparators]) else {
            return nil
        }

        let range = NSRange(xml.startIndex..., in: xml)
        let matches = regex.matches(in: xml, options: [], range: range)

        for match in matches.prefix(10) {
            guard let entryRange = Range(match.range(at: 1), in: xml) else { continue }
            let entryXML = String(xml[entryRange])

            guard let title = extractTag("title", from: entryXML) else { continue }
            let link = extractTag("link", from: entryXML) ?? extractAtomLink(entryXML)
            let pubDate = extractTag("published", from: entryXML).flatMap { parseDate($0) }
            let summary = extractTag("summary", from: entryXML).map { stripHTML($0) }

            articles.append(RSSArticle(
                id: link ?? UUID().uuidString,
                title: title,
                url: link ?? "",
                publishedAt: pubDate,
                summary: summary
            ))
        }

        return articles.isEmpty ? nil : articles
    }

    private func extractTag(_ tag: String, from xml: String) -> String? {
        let pattern = "<\(tag)><!\\[CDATA\\[([^\\]]*)\\]\\]></\(tag)>|<\(tag)>([^<]*)</\(tag)>"
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else { return nil }
        let range = NSRange(xml.startIndex..., in: xml)

        if let match = regex.firstMatch(in: xml, options: [], range: range) {
            for i in 1..<match.numberOfRanges {
                if let r = Range(match.range(at: i), in: xml) {
                    return String(xml[r]).trimmingCharacters(in: .whitespacesAndNewlines)
                }
            }
        }
        return nil
    }

    private func extractAtomLink(_ xml: String) -> String? {
        let pattern = "<link[^>]*href=[\"']([^\"']*)[\"'][^>]*>"
        guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) else { return nil }
        let range = NSRange(xml.startIndex..., in: xml)

        if let match = regex.firstMatch(in: xml, options: [], range: range),
           let r = Range(match.range(at: 1), in: xml) {
            return String(xml[r])
        }
        return nil
    }

    private func parseDate(_ string: String) -> Date? {
        let formatters: [DateFormatter] = {
            let rfc822 = DateFormatter()
            rfc822.dateFormat = "EEE, dd MMM yyyy HH:mm:ss Z"
            rfc822.locale = Locale(identifier: "en_US_POSIX")

            let iso8601 = DateFormatter()
            iso8601.dateFormat = "yyyy-MM-dd'T'HH:mm:ssZ"
            iso8601.locale = Locale(identifier: "en_US_POSIX")

            return [rfc822, iso8601]
        }()

        let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
        for formatter in formatters {
            if let date = formatter.date(from: trimmed) {
                return date
            }
        }
        return nil
    }

    private func stripHTML(_ html: String) -> String {
        html.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
            .replacingOccurrences(of: "&nbsp;", with: " ")
            .replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - Cache

    private func getCachedFeeds() -> [RSSFeedData] {
        guard let data = UserDefaults.standard.data(forKey: rssCacheKey),
              let feeds = try? JSONDecoder().decode([RSSFeedData].self, from: data) else {
            return []
        }
        return feeds
    }

    private func cacheFeeds(_ feeds: [RSSFeedData]) {
        if let encoded = try? JSONEncoder().encode(feeds) {
            UserDefaults.standard.set(encoded, forKey: rssCacheKey)
        }
    }
}