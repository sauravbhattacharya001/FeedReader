//
//  ArticleLinkExtractor.swift
//  FeedReader
//
//  Extracts, categorizes, and analyzes outbound links found in article content.
//  Useful for researchers who want to explore references, find related resources,
//  build a link graph across articles, and detect broken links.
//
//  Features:
//  - Extract all outbound URLs from article HTML/text content
//  - Categorize links: article, social, image, video, document, code, reference, other
//  - Domain frequency analysis (most-linked domains)
//  - Cross-article link graph: which articles share common outbound links
//  - Dead link detection via HEAD request status codes
//  - Link density scoring (links per 1000 words)
//  - Export extracted links as JSON, CSV, or Markdown
//  - Filter by category, domain, or date range
//
//  Persistence: UserDefaults via Codable.
//

import Foundation

// MARK: - Notifications

extension Notification.Name {
    /// Posted when links are extracted from an article.
    static let linksDidExtract = Notification.Name("ArticleLinksDidExtractNotification")
    /// Posted when a dead link is detected.
    static let deadLinkDetected = Notification.Name("ArticleDeadLinkDetectedNotification")
}

// MARK: - Models

/// Category of an extracted link.
enum LinkCategory: String, Codable, CaseIterable, Comparable {
    case article = "article"
    case social = "social"
    case image = "image"
    case video = "video"
    case document = "document"
    case code = "code"
    case reference = "reference"
    case other = "other"

    var displayName: String {
        return rawValue.capitalized
    }

    var emoji: String {
        switch self {
        case .article: return "📰"
        case .social: return "💬"
        case .image: return "🖼️"
        case .video: return "🎬"
        case .document: return "📄"
        case .code: return "💻"
        case .reference: return "📚"
        case .other: return "🔗"
        }
    }

    static func < (lhs: LinkCategory, rhs: LinkCategory) -> Bool {
        return lhs.rawValue < rhs.rawValue
    }
}

/// Status of a link health check.
enum LinkHealthStatus: String, Codable {
    case unchecked = "unchecked"
    case alive = "alive"
    case dead = "dead"
    case timeout = "timeout"
    case redirected = "redirected"

    var emoji: String {
        switch self {
        case .unchecked: return "❓"
        case .alive: return "✅"
        case .dead: return "❌"
        case .timeout: return "⏳"
        case .redirected: return "↪️"
        }
    }
}

/// A single extracted link from an article.
struct ExtractedLink: Codable, Identifiable {
    let id: String
    let url: String
    let anchorText: String
    let category: LinkCategory
    let domain: String
    let sourceArticleId: String
    let sourceArticleTitle: String
    let extractedDate: Date
    var healthStatus: LinkHealthStatus
    var httpStatusCode: Int?
    var redirectTarget: String?

    init(url: String, anchorText: String, category: LinkCategory,
         sourceArticleId: String, sourceArticleTitle: String) {
        self.id = UUID().uuidString
        self.url = url
        self.anchorText = anchorText.trimmingCharacters(in: .whitespacesAndNewlines)
        self.category = category
        self.domain = Self.extractDomain(from: url)
        self.sourceArticleId = sourceArticleId
        self.sourceArticleTitle = sourceArticleTitle
        self.extractedDate = Date()
        self.healthStatus = .unchecked
    }

    private static func extractDomain(from urlString: String) -> String {
        guard let url = URL(string: urlString), let host = url.host else {
            return "unknown"
        }
        // Strip www. prefix
        if host.hasPrefix("www.") {
            return String(host.dropFirst(4))
        }
        return host
    }
}

/// Summary of links for a single article.
struct ArticleLinkSummary: Codable {
    let articleId: String
    let articleTitle: String
    let totalLinks: Int
    let categoryCounts: [String: Int]
    let topDomains: [(String, Int)]
    let linkDensity: Double // links per 1000 words
    let extractedDate: Date

    enum CodingKeys: String, CodingKey {
        case articleId, articleTitle, totalLinks, categoryCounts
        case topDomainKeys, topDomainValues, linkDensity, extractedDate
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(articleId, forKey: .articleId)
        try container.encode(articleTitle, forKey: .articleTitle)
        try container.encode(totalLinks, forKey: .totalLinks)
        try container.encode(categoryCounts, forKey: .categoryCounts)
        try container.encode(topDomains.map { $0.0 }, forKey: .topDomainKeys)
        try container.encode(topDomains.map { $0.1 }, forKey: .topDomainValues)
        try container.encode(linkDensity, forKey: .linkDensity)
        try container.encode(extractedDate, forKey: .extractedDate)
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        articleId = try container.decode(String.self, forKey: .articleId)
        articleTitle = try container.decode(String.self, forKey: .articleTitle)
        totalLinks = try container.decode(Int.self, forKey: .totalLinks)
        categoryCounts = try container.decode([String: Int].self, forKey: .categoryCounts)
        let keys = try container.decode([String].self, forKey: .topDomainKeys)
        let values = try container.decode([Int].self, forKey: .topDomainValues)
        topDomains = Array(zip(keys, values))
        linkDensity = try container.decode(Double.self, forKey: .linkDensity)
        extractedDate = try container.decode(Date.self, forKey: .extractedDate)
    }

    init(articleId: String, articleTitle: String, totalLinks: Int,
         categoryCounts: [String: Int], topDomains: [(String, Int)],
         linkDensity: Double) {
        self.articleId = articleId
        self.articleTitle = articleTitle
        self.totalLinks = totalLinks
        self.categoryCounts = categoryCounts
        self.topDomains = topDomains
        self.linkDensity = linkDensity
        self.extractedDate = Date()
    }
}

/// Cross-article link overlap.
struct LinkOverlap: Codable {
    let articleIdA: String
    let articleIdB: String
    let sharedDomains: [String]
    let sharedUrls: [String]
    let overlapScore: Double // 0.0-1.0, Jaccard similarity
}

// MARK: - Link Extractor

/// Extracts and manages outbound links from article content.
final class ArticleLinkExtractor {

    // MARK: - Singleton

    static let shared = ArticleLinkExtractor()

    // MARK: - Storage Keys

    private let linksKey = "ArticleLinkExtractor_Links"
    private let summariesKey = "ArticleLinkExtractor_Summaries"

    // MARK: - State

    private(set) var links: [ExtractedLink] = []
    private(set) var summaries: [ArticleLinkSummary] = []

    // MARK: - Social Domains

    private let socialDomains: Set<String> = [
        "twitter.com", "x.com", "facebook.com", "instagram.com", "linkedin.com",
        "reddit.com", "mastodon.social", "threads.net", "tiktok.com", "youtube.com",
        "bsky.app", "discord.com", "slack.com", "t.me", "telegram.org"
    ]

    private let videoDomains: Set<String> = [
        "youtube.com", "youtu.be", "vimeo.com", "dailymotion.com", "twitch.tv",
        "rumble.com", "bitchute.com", "odysee.com"
    ]

    private let codeDomains: Set<String> = [
        "github.com", "gitlab.com", "bitbucket.org", "codepen.io", "jsfiddle.net",
        "replit.com", "stackblitz.com", "codesandbox.io", "gist.github.com"
    ]

    private let referenceDomains: Set<String> = [
        "wikipedia.org", "en.wikipedia.org", "arxiv.org", "doi.org", "scholar.google.com",
        "pubmed.ncbi.nlm.nih.gov", "semanticscholar.org", "jstor.org",
        "stackoverflow.com", "stackexchange.com", "mdn.io", "developer.mozilla.org"
    ]

    private let imageExtensions: Set<String> = ["jpg", "jpeg", "png", "gif", "webp", "svg", "bmp", "ico"]
    private let documentExtensions: Set<String> = ["pdf", "doc", "docx", "xls", "xlsx", "ppt", "pptx", "txt", "csv"]

    // MARK: - Init

    private init() {
        loadData()
    }

    // MARK: - Persistence

    private func loadData() {
        if let data = UserDefaults.standard.data(forKey: linksKey),
           let decoded = try? JSONDecoder().decode([ExtractedLink].self, from: data) {
            links = decoded
        }
        if let data = UserDefaults.standard.data(forKey: summariesKey),
           let decoded = try? JSONDecoder().decode([ArticleLinkSummary].self, from: data) {
            summaries = decoded
        }
    }

    private func saveLinks() {
        if let data = try? JSONEncoder().encode(links) {
            UserDefaults.standard.set(data, forKey: linksKey)
        }
    }

    private func saveSummaries() {
        if let data = try? JSONEncoder().encode(summaries) {
            UserDefaults.standard.set(data, forKey: summariesKey)
        }
    }

    // MARK: - Extraction

    /// Extract all outbound links from article HTML content.
    /// - Parameters:
    ///   - html: The HTML content of the article.
    ///   - articleId: Unique identifier for the source article.
    ///   - articleTitle: Display title of the source article.
    ///   - wordCount: Word count of the article text (for density calculation).
    /// - Returns: Array of extracted links.
    @discardableResult
    func extractLinks(from html: String, articleId: String,
                      articleTitle: String, wordCount: Int = 0) -> [ExtractedLink] {
        // Remove existing links for this article (re-extraction)
        links.removeAll { $0.sourceArticleId == articleId }

        let extracted = parseLinks(from: html, articleId: articleId, articleTitle: articleTitle)
        links.append(contentsOf: extracted)
        saveLinks()

        // Build summary
        let summary = buildSummary(for: articleId, title: articleTitle,
                                   links: extracted, wordCount: wordCount)
        summaries.removeAll { $0.articleId == articleId }
        summaries.append(summary)
        saveSummaries()

        NotificationCenter.default.post(name: .linksDidExtract, object: self,
                                        userInfo: ["articleId": articleId, "count": extracted.count])

        return extracted
    }

    /// Parse links from HTML using regex-based extraction.
    private func parseLinks(from html: String, articleId: String,
                           articleTitle: String) -> [ExtractedLink] {
        var results: [ExtractedLink] = []
        var seenUrls: Set<String> = []

        // Match <a href="...">...</a> patterns
        let pattern = #"<a\s+[^>]*href\s*=\s*"([^"]+)"[^>]*>(.*?)</a>"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive, .dotMatchesLineSeparators]) else {
            return results
        }

        let nsString = html as NSString
        let matches = regex.matches(in: html, range: NSRange(location: 0, length: nsString.length))

        for match in matches {
            guard match.numberOfRanges >= 3 else { continue }

            let urlString = nsString.substring(with: match.range(at: 1))
            let anchorHtml = nsString.substring(with: match.range(at: 2))

            // Clean anchor text (strip inner HTML tags)
            let anchorText = stripHtmlTags(anchorHtml)

            // Skip empty, anchor-only, or javascript links
            guard !urlString.isEmpty,
                  urlString.hasPrefix("http://") || urlString.hasPrefix("https://"),
                  !seenUrls.contains(urlString) else { continue }

            seenUrls.insert(urlString)

            let category = categorize(url: urlString)
            let link = ExtractedLink(url: urlString, anchorText: anchorText,
                                     category: category, sourceArticleId: articleId,
                                     sourceArticleTitle: articleTitle)
            results.append(link)
        }

        return results
    }

    /// Strip HTML tags from a string.
    private func stripHtmlTags(_ html: String) -> String {
        guard let regex = try? NSRegularExpression(pattern: "<[^>]+>", options: []) else {
            return html
        }
        let range = NSRange(location: 0, length: (html as NSString).length)
        return regex.stringByReplacingMatches(in: html, range: range, withTemplate: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Categorize a URL based on domain and file extension.
    private func categorize(url: String) -> LinkCategory {
        let lowered = url.lowercased()

        // Check file extension
        if let ext = URL(string: lowered)?.pathExtension, !ext.isEmpty {
            if imageExtensions.contains(ext) { return .image }
            if documentExtensions.contains(ext) { return .document }
        }

        // Check domain
        guard let urlObj = URL(string: lowered), let host = urlObj.host else {
            return .other
        }

        let domain = host.hasPrefix("www.") ? String(host.dropFirst(4)) : host

        if videoDomains.contains(domain) { return .video }
        if codeDomains.contains(domain) { return .code }
        if socialDomains.contains(domain) { return .social }
        if referenceDomains.contains(domain) ||
           referenceDomains.contains(where: { domain.hasSuffix($0) }) { return .reference }

        // Heuristic: if it looks like a news/blog article URL
        let articlePatterns = ["/article/", "/post/", "/blog/", "/news/", "/story/", "/p/"]
        if articlePatterns.contains(where: { lowered.contains($0) }) { return .article }

        return .other
    }

    // MARK: - Summary

    private func buildSummary(for articleId: String, title: String,
                              links: [ExtractedLink], wordCount: Int) -> ArticleLinkSummary {
        var categoryCounts: [String: Int] = [:]
        var domainCounts: [String: Int] = [:]

        for link in links {
            categoryCounts[link.category.rawValue, default: 0] += 1
            domainCounts[link.domain, default: 0] += 1
        }

        let topDomains = domainCounts.sorted { $0.value > $1.value }
            .prefix(10)
            .map { ($0.key, $0.value) }

        let density = wordCount > 0 ? (Double(links.count) / Double(wordCount)) * 1000.0 : 0.0

        return ArticleLinkSummary(articleId: articleId, articleTitle: title,
                                  totalLinks: links.count, categoryCounts: categoryCounts,
                                  topDomains: Array(topDomains), linkDensity: density)
    }

    // MARK: - Queries

    /// Get all links for a specific article.
    func links(forArticle articleId: String) -> [ExtractedLink] {
        return links.filter { $0.sourceArticleId == articleId }
    }

    /// Get all links of a specific category.
    func links(byCategory category: LinkCategory) -> [ExtractedLink] {
        return links.filter { $0.category == category }
    }

    /// Get all links from a specific domain.
    func links(fromDomain domain: String) -> [ExtractedLink] {
        let normalized = domain.lowercased()
        return links.filter { $0.domain.lowercased() == normalized }
    }

    /// Get domain frequency across all extracted links.
    func domainFrequency() -> [(domain: String, count: Int)] {
        var counts: [String: Int] = [:]
        for link in links {
            counts[link.domain, default: 0] += 1
        }
        return counts.sorted { $0.value > $1.value }.map { (domain: $0.key, count: $0.value) }
    }

    /// Get category distribution across all extracted links.
    func categoryDistribution() -> [(category: LinkCategory, count: Int, percentage: Double)] {
        guard !links.isEmpty else { return [] }
        var counts: [LinkCategory: Int] = [:]
        for link in links {
            counts[link.category, default: 0] += 1
        }
        let total = Double(links.count)
        return counts.sorted { $0.key < $1.key }.map {
            (category: $0.key, count: $0.value, percentage: Double($0.value) / total * 100.0)
        }
    }

    /// Find articles that share outbound links (link overlap).
    func findOverlaps(minSharedUrls: Int = 2) -> [LinkOverlap] {
        var articleLinks: [String: Set<String>] = [:]
        var articleDomains: [String: Set<String>] = [:]

        for link in links {
            articleLinks[link.sourceArticleId, default: []].insert(link.url)
            articleDomains[link.sourceArticleId, default: []].insert(link.domain)
        }

        let articleIds = Array(articleLinks.keys)
        var overlaps: [LinkOverlap] = []

        for i in 0..<articleIds.count {
            for j in (i + 1)..<articleIds.count {
                let idA = articleIds[i]
                let idB = articleIds[j]

                let sharedUrls = articleLinks[idA, default: []].intersection(articleLinks[idB, default: []])
                let sharedDomains = articleDomains[idA, default: []].intersection(articleDomains[idB, default: []])

                guard sharedUrls.count >= minSharedUrls else { continue }

                let unionUrls = articleLinks[idA, default: []].union(articleLinks[idB, default: []])
                let jaccard = unionUrls.isEmpty ? 0.0 : Double(sharedUrls.count) / Double(unionUrls.count)

                overlaps.append(LinkOverlap(
                    articleIdA: idA, articleIdB: idB,
                    sharedDomains: Array(sharedDomains).sorted(),
                    sharedUrls: Array(sharedUrls).sorted(),
                    overlapScore: jaccard
                ))
            }
        }

        return overlaps.sorted { $0.overlapScore > $1.overlapScore }
    }

    /// Search links by URL or anchor text.
    func search(query: String) -> [ExtractedLink] {
        let q = query.lowercased()
        return links.filter {
            $0.url.lowercased().contains(q) ||
            $0.anchorText.lowercased().contains(q) ||
            $0.domain.lowercased().contains(q)
        }
    }

    // MARK: - Health Check

    /// Check if a link is alive using a HEAD request.
    /// - Parameters:
    ///   - linkId: The ID of the link to check.
    ///   - completion: Called with updated health status.
    func checkLinkHealth(linkId: String, completion: @escaping (LinkHealthStatus) -> Void) {
        guard let index = links.firstIndex(where: { $0.id == linkId }),
              let url = URL(string: links[index].url) else {
            completion(.dead)
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = "HEAD"
        request.timeoutInterval = 10

        let task = URLSession.shared.dataTask(with: request) { [weak self] _, response, error in
            guard let self = self else { return }

            let status: LinkHealthStatus
            let httpCode: Int?

            if let error = error {
                if (error as NSError).code == NSURLErrorTimedOut {
                    status = .timeout
                } else {
                    status = .dead
                }
                httpCode = nil
            } else if let httpResponse = response as? HTTPURLResponse {
                httpCode = httpResponse.statusCode
                switch httpResponse.statusCode {
                case 200...299:
                    status = .alive
                case 301, 302, 307, 308:
                    status = .redirected
                case 404, 410:
                    status = .dead
                default:
                    status = httpResponse.statusCode >= 400 ? .dead : .alive
                }
            } else {
                status = .dead
                httpCode = nil
            }

            // Update stored link
            if let idx = self.links.firstIndex(where: { $0.id == linkId }) {
                self.links[idx].healthStatus = status
                self.links[idx].httpStatusCode = httpCode
                if status == .redirected, let httpResponse = response as? HTTPURLResponse,
                   let location = httpResponse.value(forHTTPHeaderField: "Location") {
                    self.links[idx].redirectTarget = location
                }
                self.saveLinks()

                if status == .dead {
                    NotificationCenter.default.post(name: .deadLinkDetected, object: self,
                                                    userInfo: ["linkId": linkId])
                }
            }

            completion(status)
        }
        task.resume()
    }

    /// Batch health check all unchecked links for an article.
    func checkAllLinks(forArticle articleId: String, completion: @escaping (Int, Int) -> Void) {
        let articleLinks = links.filter { $0.sourceArticleId == articleId && $0.healthStatus == .unchecked }
        guard !articleLinks.isEmpty else {
            completion(0, 0)
            return
        }

        var alive = 0
        var dead = 0
        let group = DispatchGroup()

        for link in articleLinks {
            group.enter()
            checkLinkHealth(linkId: link.id) { status in
                if status == .alive || status == .redirected {
                    alive += 1
                } else {
                    dead += 1
                }
                group.leave()
            }
        }

        group.notify(queue: .main) {
            completion(alive, dead)
        }
    }

    // MARK: - Export

    /// Export extracted links as JSON.
    func exportJSON(forArticle articleId: String? = nil) -> String {
        let toExport = articleId != nil ? links.filter { $0.sourceArticleId == articleId } : links
        guard let data = try? JSONEncoder().encode(toExport),
              let json = String(data: data, encoding: .utf8) else {
            return "[]"
        }
        return json
    }

    /// Export extracted links as CSV.
    func exportCSV(forArticle articleId: String? = nil) -> String {
        let toExport = articleId != nil ? links.filter { $0.sourceArticleId == articleId } : links
        var csv = "URL,Anchor Text,Category,Domain,Source Article,Health Status,HTTP Code\n"

        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"

        for link in toExport {
            let anchor = link.anchorText.replacingOccurrences(of: "\"", with: "\"\"")
            let title = link.sourceArticleTitle.replacingOccurrences(of: "\"", with: "\"\"")
            let code = link.httpStatusCode.map { String($0) } ?? ""
            csv += "\"\(link.url)\",\"\(anchor)\",\(link.category.rawValue),\(link.domain),\"\(title)\",\(link.healthStatus.rawValue),\(code)\n"
        }

        return csv
    }

    /// Export extracted links as Markdown.
    func exportMarkdown(forArticle articleId: String? = nil) -> String {
        let toExport = articleId != nil ? links.filter { $0.sourceArticleId == articleId } : links
        guard !toExport.isEmpty else { return "# Extracted Links\n\nNo links found.\n" }

        var md = "# Extracted Links\n\n"
        md += "**Total:** \(toExport.count) links\n\n"

        // Group by category
        let grouped = Dictionary(grouping: toExport) { $0.category }
        for category in LinkCategory.allCases {
            guard let categoryLinks = grouped[category], !categoryLinks.isEmpty else { continue }
            md += "## \(category.emoji) \(category.displayName) (\(categoryLinks.count))\n\n"
            for link in categoryLinks {
                let text = link.anchorText.isEmpty ? link.domain : link.anchorText
                md += "- [\(text)](\(link.url)) \(link.healthStatus.emoji)\n"
            }
            md += "\n"
        }

        return md
    }

    // MARK: - Statistics

    /// Get overall link extraction statistics.
    func statistics() -> [String: Any] {
        let totalLinks = links.count
        let totalArticles = Set(links.map { $0.sourceArticleId }).count
        let uniqueDomains = Set(links.map { $0.domain }).count
        let aliveCount = links.filter { $0.healthStatus == .alive }.count
        let deadCount = links.filter { $0.healthStatus == .dead }.count
        let uncheckedCount = links.filter { $0.healthStatus == .unchecked }.count

        return [
            "totalLinks": totalLinks,
            "totalArticles": totalArticles,
            "uniqueDomains": uniqueDomains,
            "averageLinksPerArticle": totalArticles > 0 ? Double(totalLinks) / Double(totalArticles) : 0.0,
            "healthChecked": totalLinks - uncheckedCount,
            "aliveLinks": aliveCount,
            "deadLinks": deadCount,
            "uncheckedLinks": uncheckedCount
        ]
    }

    // MARK: - Cleanup

    /// Remove all extracted links for an article.
    func removeLinks(forArticle articleId: String) {
        links.removeAll { $0.sourceArticleId == articleId }
        summaries.removeAll { $0.articleId == articleId }
        saveLinks()
        saveSummaries()
    }

    /// Remove all extracted links.
    func removeAllLinks() {
        links.removeAll()
        summaries.removeAll()
        saveLinks()
        saveSummaries()
    }
}
