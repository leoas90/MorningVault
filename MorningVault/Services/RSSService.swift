import Foundation

/// RSS feed parser — fetches user-selected news sources.
/// No user tracking, no analytics.
/// Uses shared NewsSource enum as single source of truth for all source URLs.
final class RSSService: ObservableObject {
    static let shared = RSSService()

    @Published var feeds: [RSSFeedData] = []
    @Published var lastError: String?

    private let rssCacheKey = "com.morningvault.rssCache"

    // MARK: - Public API

    func fetchAllFeeds() async -> [RSSFeedData] {
        if UserDefaults.standard.bool(forKey: "local_only") {
            return getCachedFeeds()
        }
        return await fetchFeeds(sources: loadSelectedSources())
    }

    func fetchFeeds(sources: [NewsSource]) async -> [RSSFeedData] {
        // Respect localOnly — no network calls if enabled
        if UserDefaults.standard.bool(forKey: "local_only") {
            let cached = getCachedFeeds()
            if !cached.isEmpty { return cached }
        }

        let results = await withTaskGroup(of: RSSFeedData?.self) { group in
            for source in sources {
                group.addTask {
                    await self.fetchFeed(source: source)
                }
            }

            var all: [RSSFeedData] = []
            for await result in group {
                if let feed = result { all.append(feed) }
            }
            return all
        }

        await MainActor.run {
            self.feeds = results
            self.cacheFeeds(results)
        }
        return results
    }

    // MARK: - Fetch Single Feed

    private func fetchFeed(source: NewsSource) async -> RSSFeedData? {
        guard let url = URL(string: source.feedURL) else { return nil }
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            let articles = parseFeed(data: data, sourceName: source.displayName)
            return RSSFeedData(
                id: source.rawValue,
                sourceName: source.displayName,
                articles: articles
            )
        } catch {
            return nil
        }
    }

    // MARK: - XML Parsing

    private func parseFeed(data: Data, sourceName: String) -> [RSSArticle] {
        guard let xmlString = String(data: data, encoding: .utf8) else { return [] }
        if let articles = parseRSS2(xmlString, source: sourceName) { return articles }
        if let articles = parseAtom(xmlString, source: sourceName) { return articles }
        return []
    }

    private func parseRSS2(_ xml: String, source: String) -> [RSSArticle]? {
        guard let regex = try? NSRegularExpression(pattern: "<item>(.*?)</item>", options: [.dotMatchesLineSeparators]) else {
            return nil
        }
        let range = NSRange(xml.startIndex..., in: xml)
        let matches = regex.matches(in: xml, options: [], range: range)
        var articles: [RSSArticle] = []
        for match in matches.prefix(10) {
            guard let itemRange = Range(match.range(at: 1), in: xml) else { continue }
            let itemXML = String(xml[itemRange])
            guard let title = extractTag("title", from: itemXML),
                  let link = extractTag("link", from: itemXML) else { continue }
            let pubDate = extractTag("pubDate", from: itemXML).flatMap { parseDate($0) }
            let summary = extractTag("description", from: itemXML).map { stripHTML($0) }
            articles.append(RSSArticle(id: link, title: title, url: link, publishedAt: pubDate, summary: summary))
        }
        return articles.isEmpty ? nil : articles
    }

    private func parseAtom(_ xml: String, source: String) -> [RSSArticle]? {
        guard let regex = try? NSRegularExpression(pattern: "<entry>(.*?)</entry>", options: [.dotMatchesLineSeparators]) else {
            return nil
        }
        let range = NSRange(xml.startIndex..., in: xml)
        let matches = regex.matches(in: xml, options: [], range: range)
        var articles: [RSSArticle] = []
        for match in matches.prefix(10) {
            guard let entryRange = Range(match.range(at: 1), in: xml) else { continue }
            let entryXML = String(xml[entryRange])
            guard let title = extractTag("title", from: entryXML) else { continue }
            let link = extractTag("link", from: entryXML) ?? extractAtomLink(entryXML)
            let pubDate = extractTag("published", from: entryXML).flatMap { parseDate($0) }
            let summary = extractTag("summary", from: entryXML).map { stripHTML($0) }
            articles.append(RSSArticle(id: link ?? UUID().uuidString, title: title, url: link ?? "", publishedAt: pubDate, summary: summary))
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
        // Match <link href="..." rel="alternate"...> — the alternate link for the entry
        let pattern = "<link[^>]*href=[\"']([^\"']*)[\"'][^>]*>"
        guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) else { return nil }
        let range = NSRange(xml.startIndex..., in: xml)
        // Find the first link (usually the alternate/canonical one)
        let matches = regex.matches(in: xml, options: [], range: range)
        for match in matches {
            if let r = Range(match.range(at: 1), in: xml) {
                let href = String(xml[r])
                if !href.isEmpty { return href }
            }
        }
        return nil
    }

    private func parseDate(_ string: String) -> Date? {
        let rfc822 = DateFormatter()
        rfc822.dateFormat = "EEE, dd MMM yyyy HH:mm:ss Z"
        rfc822.locale = Locale(identifier: "en_US_POSIX")
        let iso8601 = DateFormatter()
        iso8601.dateFormat = "yyyy-MM-dd'T'HH:mm:ssZ"
        iso8601.locale = Locale(identifier: "en_US_POSIX")
        let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
        return rfc822.date(from: trimmed) ?? iso8601.date(from: trimmed)
    }

    private func stripHTML(_ html: String) -> String {
        html.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
            .replacingOccurrences(of: "&nbsp;", with: " ")
            .replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&#39;", with: "'")
            .replacingOccurrences(of: "&apos;", with: "'")
            .replacingOccurrences(of: "&eacute;", with: "é")
            .replacingOccurrences(of: "&nbsp;", with: " ")
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