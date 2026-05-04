//
//  ArticleDigestComposer.swift
//  FeedReader
//
//  Generates newsletter-style digest emails from recent articles.
//  Groups articles by topic/feed, includes reading time estimates,
//  and exports as HTML or Markdown for sharing via email or messaging.
//

import Foundation

// MARK: - Models

/// A digest newsletter composed from recent articles.
struct ArticleDigest: Codable, Identifiable {
    let id: String
    var title: String
    var subtitle: String
    var period: DigestPeriod
    var sections: [DigestSection]
    var createdAt: Date
    var articleCount: Int
    var totalReadingMinutes: Int
    var greeting: String
    var signoff: String
    
    init(title: String, period: DigestPeriod = .weekly) {
        self.id = UUID().uuidString
        self.title = title
        self.subtitle = ""
        self.period = period
        self.sections = []
        self.createdAt = Date()
        self.articleCount = 0
        self.totalReadingMinutes = 0
        self.greeting = DigestGreeting.random()
        self.signoff = DigestSignoff.random()
    }
}

/// Time period for the digest.
enum DigestPeriod: String, Codable, CaseIterable {
    case daily = "Daily"
    case weekly = "Weekly"
    case monthly = "Monthly"
    
    var days: Int {
        switch self {
        case .daily: return 1
        case .weekly: return 7
        case .monthly: return 30
        }
    }
    
    var emoji: String {
        switch self {
        case .daily: return "☀️"
        case .weekly: return "📅"
        case .monthly: return "📆"
        }
    }
}

/// A themed section within a digest.
struct DigestSection: Codable, Identifiable {
    let id: String
    var title: String
    var emoji: String
    var items: [DigestItem]
    var note: String?
    
    init(title: String, emoji: String = "📰") {
        self.id = UUID().uuidString
        self.title = title
        self.emoji = emoji
        self.items = []
        self.note = nil
    }
}

/// An individual article entry in a digest section.
struct DigestItem: Codable, Identifiable {
    let id: String
    var title: String
    var feedName: String
    var url: String
    var snippet: String
    var readingMinutes: Int
    var publishedAt: Date?
    var isStarred: Bool
    var tags: [String]
    
    init(title: String, feedName: String, url: String, snippet: String = "") {
        self.id = UUID().uuidString
        self.title = title
        self.feedName = feedName
        self.url = url
        self.snippet = snippet
        self.readingMinutes = 0
        self.publishedAt = nil
        self.isStarred = false
        self.tags = []
    }
}

/// Export format for digest output.
enum DigestExportFormat: String, CaseIterable {
    case html = "HTML"
    case markdown = "Markdown"
    case plainText = "Plain Text"
    
    var fileExtension: String {
        switch self {
        case .html: return "html"
        case .markdown: return "md"
        case .plainText: return "txt"
        }
    }
}

// MARK: - Greetings & Signoffs

struct DigestGreeting {
    static let greetings = [
        "Here's what caught our eye this week.",
        "Your curated reading, fresh and ready.",
        "The best articles, handpicked for you.",
        "Time to catch up on great reads.",
        "Your reading digest is served!",
        "Dive into this batch of great articles.",
        "Fresh stories await — grab your coffee.",
        "Here are the highlights you won't want to miss."
    ]
    
    static func random() -> String {
        greetings.randomElement() ?? greetings[0]
    }
}

struct DigestSignoff {
    static let signoffs = [
        "Happy reading! 📚",
        "Until next time — keep reading!",
        "That's a wrap. See you next digest!",
        "Stay curious. 🌟",
        "Keep exploring. 🚀",
        "Read on! ✨"
    ]
    
    static func random() -> String {
        signoffs.randomElement() ?? signoffs[0]
    }
}

// MARK: - Composer

/// Composes newsletter-style digests from articles.
class ArticleDigestComposer {
    
    private let store: UserDefaultsCodableStore<[ArticleDigest]>
    private(set) var savedDigests: [ArticleDigest]
    
    init() {
        self.store = UserDefaultsCodableStore(key: "ArticleDigestComposer.digests")
        self.savedDigests = store.load() ?? []
    }
    
    // MARK: - Compose
    
    /// Compose a digest from a list of stories, grouped by feed.
    func compose(
        from stories: [Story],
        title: String? = nil,
        period: DigestPeriod = .weekly,
        maxPerSection: Int = 5,
        starredOnly: Bool = false
    ) -> ArticleDigest {
        let cutoff = Date().addingTimeInterval(-Double(period.days * 86400))
        
        // Filter stories by period
        var filtered = stories.filter { story in
            if let pub = story.publishedAt {
                return pub >= cutoff
            }
            return true  // include stories without dates
        }
        
        if starredOnly {
            filtered = filtered.filter { $0.isStarred }
        }
        
        let digestTitle = title ?? "\(period.emoji) \(period.rawValue) Digest — \(Self.formatDate(Date()))"
        var digest = ArticleDigest(title: digestTitle, period: period)
        
        // Group by feed name
        let grouped = Dictionary(grouping: filtered) { $0.feedName ?? "Uncategorized" }
        let sortedFeeds = grouped.keys.sorted()
        
        let sectionEmojis = ["📰", "🔬", "💻", "🌍", "📖", "🎯", "⚡", "🧠", "🚀", "🎨"]
        
        for (index, feedName) in sortedFeeds.enumerated() {
            guard let feedStories = grouped[feedName] else { continue }
            
            let emoji = sectionEmojis[index % sectionEmojis.count]
            var section = DigestSection(title: feedName, emoji: emoji)
            
            let topStories = Array(feedStories
                .sorted { ($0.publishedAt ?? .distantPast) > ($1.publishedAt ?? .distantPast) }
                .prefix(maxPerSection))
            
            for story in topStories {
                let snippet = Self.generateSnippet(from: story.content ?? story.summary ?? "", maxLength: 150)
                let readingMins = Self.estimateReadingMinutes(story.content ?? story.summary ?? "")
                
                var item = DigestItem(
                    title: story.title ?? "(untitled)",
                    feedName: feedName,
                    url: story.link ?? "",
                    snippet: snippet
                )
                item.readingMinutes = readingMins
                item.publishedAt = story.publishedAt
                item.isStarred = story.isStarred
                
                section.items.append(item)
                digest.totalReadingMinutes += readingMins
            }
            
            if !section.items.isEmpty {
                digest.sections.append(section)
                digest.articleCount += section.items.count
            }
        }
        
        // Add a "Starred Highlights" section at the top if there are starred items
        let starredItems = filtered.filter { $0.isStarred }
        if !starredItems.isEmpty && !starredOnly {
            var starredSection = DigestSection(title: "⭐ Starred Highlights", emoji: "⭐")
            starredSection.note = "Your favorites from this period"
            
            for story in starredItems.prefix(3) {
                let snippet = Self.generateSnippet(from: story.content ?? story.summary ?? "", maxLength: 120)
                var item = DigestItem(
                    title: story.title ?? "(untitled)",
                    feedName: story.feedName ?? "Unknown",
                    url: story.link ?? "",
                    snippet: snippet
                )
                item.isStarred = true
                item.readingMinutes = Self.estimateReadingMinutes(story.content ?? story.summary ?? "")
                starredSection.items.append(item)
            }
            
            digest.sections.insert(starredSection, at: 0)
        }
        
        digest.subtitle = "\(digest.articleCount) articles · ~\(digest.totalReadingMinutes) min read"
        
        return digest
    }
    
    // MARK: - Export
    
    /// Export digest in the specified format.
    func export(_ digest: ArticleDigest, format: DigestExportFormat) -> String {
        switch format {
        case .html: return exportHTML(digest)
        case .markdown: return exportMarkdown(digest)
        case .plainText: return exportPlainText(digest)
        }
    }
    
    // MARK: - HTML Export
    
    private func exportHTML(_ digest: ArticleDigest) -> String {
        var html = """
        <!DOCTYPE html>
        <html lang="en">
        <head>
        <meta charset="UTF-8">
        <meta name="viewport" content="width=device-width, initial-scale=1.0">
        <title>\(Self.digest.title.htmlEscaped)</title>
        <style>
        * { margin: 0; padding: 0; box-sizing: border-box; }
        body { font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', system-ui, sans-serif;
               background: #f8f9fa; color: #1a1a2e; line-height: 1.6; }
        .container { max-width: 640px; margin: 0 auto; background: #fff; }
        .header { background: linear-gradient(135deg, #667eea, #764ba2);
                   color: white; padding: 40px 32px; text-align: center; }
        .header h1 { font-size: 26px; margin-bottom: 8px; }
        .header .subtitle { opacity: 0.9; font-size: 14px; }
        .greeting { padding: 24px 32px; font-style: italic; color: #555;
                     border-bottom: 1px solid #eee; font-size: 15px; }
        .section { padding: 24px 32px; border-bottom: 1px solid #eee; }
        .section-title { font-size: 18px; font-weight: 700; margin-bottom: 16px;
                          color: #333; display: flex; align-items: center; gap: 8px; }
        .section-note { font-size: 13px; color: #888; margin-bottom: 12px; font-style: italic; }
        .article { margin-bottom: 20px; padding-bottom: 16px; border-bottom: 1px solid #f0f0f0; }
        .article:last-child { border-bottom: none; margin-bottom: 0; padding-bottom: 0; }
        .article-title { font-size: 16px; font-weight: 600; }
        .article-title a { color: #4a4a8a; text-decoration: none; }
        .article-title a:hover { text-decoration: underline; }
        .article-meta { font-size: 12px; color: #999; margin: 4px 0 8px; }
        .article-snippet { font-size: 14px; color: #555; }
        .star { color: #f5a623; }
        .footer { padding: 24px 32px; text-align: center; color: #888;
                   font-size: 13px; background: #fafafa; }
        .stats { display: flex; justify-content: center; gap: 24px;
                  padding: 16px 32px; background: #f5f3ff; font-size: 13px; color: #666; }
        .stat-item { text-align: center; }
        .stat-value { font-size: 24px; font-weight: 700; color: #667eea; }
        </style>
        </head>
        <body>
        <div class="container">
        <div class="header">
        <h1>\(Self.digest.title.htmlEscaped)</h1>
        <div class="subtitle">\(Self.digest.subtitle.htmlEscaped)</div>
        </div>
        <div class="stats">
        <div class="stat-item"><div class="stat-value">\(digest.articleCount)</div>articles</div>
        <div class="stat-item"><div class="stat-value">\(digest.sections.count)</div>feeds</div>
        <div class="stat-item"><div class="stat-value">~\(digest.totalReadingMinutes)m</div>reading</div>
        </div>
        <div class="greeting">\(Self.digest.greeting.htmlEscaped)</div>
        """
        
        for section in digest.sections {
            html += """
            <div class="section">
            <div class="section-title">\(section.emoji) \(Self.section.title.htmlEscaped)</div>
            """
            
            if let note = section.note {
                html += "<div class=\"section-note\">\(Self.note.htmlEscaped)</div>"
            }
            
            for item in section.items {
                let starBadge = item.isStarred ? " <span class=\"star\">★</span>" : ""
                let dateStr = item.publishedAt.map { Self.formatDate($0) } ?? ""
                let metaParts = [item.feedName, dateStr, "\(item.readingMinutes) min read"]
                    .filter { !$0.isEmpty }
                    .joined(separator: " · ")
                
                html += """
                <div class="article">
                <div class="article-title"><a href="\(Self.item.url.htmlEscaped)">\(Self.item.title.htmlEscaped)</a>\(starBadge)</div>
                <div class="article-meta">\(Self.metaParts.htmlEscaped)</div>
                """
                
                if !item.snippet.isEmpty {
                    html += "<div class=\"article-snippet\">\(Self.item.snippet.htmlEscaped)</div>"
                }
                
                html += "</div>"
            }
            
            html += "</div>"
        }
        
        html += """
        <div class="footer">
        <p>\(Self.digest.signoff.htmlEscaped)</p>
        <p style="margin-top:8px;font-size:11px;color:#bbb;">
        Generated by FeedReader on \(Self.formatDate(digest.createdAt))
        </p>
        </div>
        </div>
        </body>
        </html>
        """
        
        return html
    }
    
    // MARK: - Markdown Export
    
    private func exportMarkdown(_ digest: ArticleDigest) -> String {
        var md = "# \(digest.title)\n\n"
        md += "*\(digest.subtitle)*\n\n"
        md += "> \(digest.greeting)\n\n"
        md += "---\n\n"
        
        for section in digest.sections {
            md += "## \(section.emoji) \(section.title)\n\n"
            
            if let note = section.note {
                md += "*\(note)*\n\n"
            }
            
            for item in section.items {
                let star = item.isStarred ? " ⭐" : ""
                md += "### [\(item.title)](\(item.url))\(star)\n\n"
                
                var meta: [String] = []
                meta.append("📡 \(item.feedName)")
                if let pub = item.publishedAt {
                    meta.append("📅 \(Self.formatDate(pub))")
                }
                meta.append("⏱️ \(item.readingMinutes) min")
                md += meta.joined(separator: " · ") + "\n\n"
                
                if !item.snippet.isEmpty {
                    md += "\(item.snippet)\n\n"
                }
                
                md += "---\n\n"
            }
        }
        
        md += "*\(digest.signoff)*\n\n"
        md += "_Generated by FeedReader on \(Self.formatDate(digest.createdAt))_\n"
        
        return md
    }
    
    // MARK: - Plain Text Export
    
    private func exportPlainText(_ digest: ArticleDigest) -> String {
        var txt = "\(digest.title)\n"
        txt += String(repeating: "=", count: digest.title.count) + "\n\n"
        txt += "\(digest.subtitle)\n\n"
        txt += "\"\(digest.greeting)\"\n\n"
        txt += String(repeating: "-", count: 50) + "\n\n"
        
        for section in digest.sections {
            txt += "\(section.emoji) \(section.title)\n"
            txt += String(repeating: "-", count: section.title.count + 3) + "\n\n"
            
            if let note = section.note {
                txt += "  \(note)\n\n"
            }
            
            for (index, item) in section.items.enumerated() {
                let star = item.isStarred ? " [★]" : ""
                txt += "  \(index + 1). \(item.title)\(star)\n"
                txt += "     \(item.url)\n"
                
                var meta: [String] = [item.feedName]
                if let pub = item.publishedAt {
                    meta.append(Self.formatDate(pub))
                }
                meta.append("\(item.readingMinutes) min read")
                txt += "     \(meta.joined(separator: " | "))\n"
                
                if !item.snippet.isEmpty {
                    txt += "     \(item.snippet)\n"
                }
                txt += "\n"
            }
        }
        
        txt += String(repeating: "-", count: 50) + "\n"
        txt += "\(digest.signoff)\n"
        txt += "Generated by FeedReader on \(Self.formatDate(digest.createdAt))\n"
        
        return txt
    }
    
    // MARK: - Persistence
    
    /// Save a digest for later reference.
    func save(_ digest: ArticleDigest) {
        savedDigests.insert(digest, at: 0)
        if savedDigests.count > 50 {
            savedDigests = Array(savedDigests.prefix(50))
        }
        store.save(savedDigests)
    }
    
    /// Delete a saved digest by ID.
    func delete(id: String) {
        savedDigests.removeAll { $0.id == id }
        store.save(savedDigests)
    }
    
    /// Get all saved digests.
    func allDigests() -> [ArticleDigest] {
        return savedDigests
    }
    
    // MARK: - Stats
    
    /// Digest generation statistics.
    func stats() -> DigestStats {
        let total = savedDigests.count
        let totalArticles = savedDigests.reduce(0) { $0 + $1.articleCount }
        let totalMinutes = savedDigests.reduce(0) { $0 + $1.totalReadingMinutes }
        let avgArticles = total > 0 ? Double(totalArticles) / Double(total) : 0
        
        let periodCounts = Dictionary(grouping: savedDigests) { $0.period }
            .mapValues { $0.count }
        
        return DigestStats(
            totalDigests: total,
            totalArticlesCurated: totalArticles,
            totalReadingMinutes: totalMinutes,
            averageArticlesPerDigest: avgArticles,
            digestsByPeriod: periodCounts
        )
    }
    
    // MARK: - Helpers
    
    private static func generateSnippet(from text: String, maxLength: Int) -> String {
        // Strip HTML tags
        let stripped = text.replacingOccurrences(
            of: "<[^>]+>",
            with: "",
            options: .regularExpression
        )
        .replacingOccurrences(of: "&nbsp;", with: " ")
        .replacingOccurrences(of: "&amp;", with: "&")
        .replacingOccurrences(of: "&lt;", with: "<")
        .replacingOccurrences(of: "&gt;", with: ">")
        .trimmingCharacters(in: .whitespacesAndNewlines)
        
        if stripped.count <= maxLength { return stripped }
        
        let truncated = String(stripped.prefix(maxLength))
        // Try to break at a word boundary
        if let lastSpace = truncated.lastIndex(of: " ") {
            return String(truncated[..<lastSpace]) + "…"
        }
        return truncated + "…"
    }
    
    private static func estimateReadingMinutes(_ text: String) -> Int {
        let wordCount = text.components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .count
        let minutes = max(1, Int(ceil(Double(wordCount) / 200.0)))
        return minutes
    }
    
    static func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter.string(from: date)
    }
    
    private static func _ text: String.htmlEscaped -> String {
        text.replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "'", with: "&#39;")
    }
}

// MARK: - Stats Model

struct DigestStats {
    let totalDigests: Int
    let totalArticlesCurated: Int
    let totalReadingMinutes: Int
    let averageArticlesPerDigest: Double
    let digestsByPeriod: [DigestPeriod: Int]
}
