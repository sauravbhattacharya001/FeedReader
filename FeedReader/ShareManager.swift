//
//  ShareManager.swift
//  FeedReader
//
//  Generates shareable article content in multiple formats for sharing
//  via social media, messaging, email, or clipboard. Supports plain text,
//  Markdown, HTML, and social-optimized formats with configurable options.
//

import Foundation
import os.log

/// Format for shared article content.
enum ShareFormat {
    case plainText
    case markdown
    case html
    case socialPost
    case email
}

/// Options for customizing shared content.
struct ShareOptions {
    /// Include article body excerpt.
    var includeExcerpt: Bool = true
    /// Maximum excerpt length in characters.
    var excerptLength: Int = 280
    /// Include source feed name.
    var includeSource: Bool = true
    /// Include a "shared via" attribution.
    var includeAttribution: Bool = false
    /// Attribution text (when includeAttribution is true).
    var attributionText: String = "Shared via FeedReader"
    /// Hashtags to append (social post format).
    var hashtags: [String] = []
    /// Include reading time estimate.
    var includeReadingTime: Bool = false
    /// Average words per minute for reading time calculation.
    var wordsPerMinute: Int = 200
}

/// Result of a share generation operation.
struct ShareResult {
    /// The formatted content string.
    let content: String
    /// The format used.
    let format: ShareFormat
    /// Character count of the content.
    let characterCount: Int
    /// The article title.
    let title: String
    /// The article URL.
    let url: String
}

/// Manages generation of shareable article content in various formats.
class ShareManager {
    
    // MARK: - Singleton
    
    static let shared = ShareManager()
    
    // MARK: - Properties
    
    /// Default options for sharing.
    var defaultOptions = ShareOptions()
    
    /// History of shared articles (URLs) for tracking.
    private(set) var shareHistory: [ShareHistoryEntry] = []
    
    /// Maximum history entries to retain.
    private let maxHistoryEntries = 100
    
    /// File URL for persisting share history.
    private static let historyURL: URL = {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        return docs.appendingPathComponent("shareHistory.json")
    }()
    
    // MARK: - History Entry
    
    struct ShareHistoryEntry: Codable {
        let title: String
        let url: String
        let format: String
        let timestamp: Date
        let characterCount: Int
    }
    
    // MARK: - Initialization
    
    private init() {
        loadHistory()
    }
    
    // MARK: - Share Generation
    
    /// Generate shareable content for a story in the specified format.
    func share(story: Story, format: ShareFormat, options: ShareOptions? = nil) -> ShareResult {
        let opts = options ?? defaultOptions
        let content: String
        
        switch format {
        case .plainText:
            content = generatePlainText(story: story, options: opts)
        case .markdown:
            content = generateMarkdown(story: story, options: opts)
        case .html:
            content = generateHTML(story: story, options: opts)
        case .socialPost:
            content = generateSocialPost(story: story, options: opts)
        case .email:
            content = generateEmail(story: story, options: opts)
        }
        
        let result = ShareResult(
            content: content,
            format: format,
            characterCount: content.count,
            title: story.title,
            url: story.link
        )
        
        recordShare(result: result, format: format)
        
        return result
    }
    
    /// Generate shareable content for multiple stories (digest format).
    func shareDigest(stories: [Story], format: ShareFormat, title: String = "Article Digest", options: ShareOptions? = nil) -> ShareResult {
        let opts = options ?? defaultOptions
        let content: String
        
        switch format {
        case .plainText:
            content = generateDigestPlainText(stories: stories, title: title, options: opts)
        case .markdown:
            content = generateDigestMarkdown(stories: stories, title: title, options: opts)
        case .html:
            content = generateDigestHTML(stories: stories, title: title, options: opts)
        case .socialPost:
            // Social posts use first story only
            if let first = stories.first {
                content = generateSocialPost(story: first, options: opts)
            } else {
                content = ""
            }
        case .email:
            content = generateDigestEmail(stories: stories, title: title, options: opts)
        }
        
        return ShareResult(
            content: content,
            format: format,
            characterCount: content.count,
            title: title,
            url: stories.first?.link ?? ""
        )
    }
    
    // MARK: - Format Generators
    
    private func generatePlainText(story: Story, options: ShareOptions) -> String {
        var lines: [String] = []
        
        lines.append(story.title)
        lines.append("")
        
        if options.includeSource, let source = story.sourceFeedName {
            lines.append("Source: \(source)")
        }
        
        if options.includeReadingTime {
            let time = estimateReadingTime(text: story.body, wpm: options.wordsPerMinute)
            lines.append("Reading time: \(time)")
        }
        
        if options.includeExcerpt {
            lines.append("")
            lines.append(truncate(story.body, to: options.excerptLength))
        }
        
        lines.append("")
        lines.append("Read more: \(story.link)")
        
        if options.includeAttribution {
            lines.append("")
            lines.append("— \(options.attributionText)")
        }
        
        return lines.joined(separator: "\n")
    }
    
    private func generateMarkdown(story: Story, options: ShareOptions) -> String {
        var lines: [String] = []
        
        lines.append("## [\(story.title)](\(story.link))")
        lines.append("")
        
        var meta: [String] = []
        if options.includeSource, let source = story.sourceFeedName {
            meta.append("**Source:** \(source)")
        }
        if options.includeReadingTime {
            let time = estimateReadingTime(text: story.body, wpm: options.wordsPerMinute)
            meta.append("**Reading time:** \(time)")
        }
        if !meta.isEmpty {
            lines.append(meta.joined(separator: " | "))
            lines.append("")
        }
        
        if options.includeExcerpt {
            lines.append("> \(truncate(story.body, to: options.excerptLength))")
            lines.append("")
        }
        
        if options.includeAttribution {
            lines.append("*\(options.attributionText)*")
        }
        
        return lines.joined(separator: "\n")
    }
    
    private func generateHTML(story: Story, options: ShareOptions) -> String {
        var html = "<div class=\"shared-article\">\n"
        html += "  <h2><a href=\"\(story.link.htmlEscaped)\">\(story.title.htmlEscaped)</a></h2>\n"
        
        var meta: [String] = []
        if options.includeSource, let source = story.sourceFeedName {
            meta.append("<span class=\"source\">\(source.htmlEscaped)</span>")
        }
        if options.includeReadingTime {
            let time = estimateReadingTime(text: story.body, wpm: options.wordsPerMinute)
            meta.append("<span class=\"reading-time\">\(time)</span>")
        }
        if !meta.isEmpty {
            html += "  <p class=\"meta\">\(meta.joined(separator: " &middot; "))</p>\n"
        }
        
        if options.includeExcerpt {
            html += "  <blockquote>\(truncate(story.body, to: options.excerptLength).htmlEscaped)</blockquote>\n"
        }
        
        if options.includeAttribution {
            html += "  <p class=\"attribution\"><em>\(options.attributionText.htmlEscaped)</em></p>\n"
        }
        
        html += "</div>"
        return html
    }
    
    private func generateSocialPost(story: Story, options: ShareOptions) -> String {
        var parts: [String] = []
        
        // Title — truncate if needed to leave room for URL and hashtags
        let maxTitleLen = 200
        let title = story.title.count > maxTitleLen
            ? String(story.title.prefix(maxTitleLen - 1)) + "…"
            : story.title
        parts.append(title)
        
        if options.includeExcerpt {
            let excerpt = truncate(story.body, to: 100)
            if !excerpt.isEmpty {
                parts.append(excerpt)
            }
        }
        
        parts.append(story.link)
        
        if !options.hashtags.isEmpty {
            let tags = options.hashtags.map { $0.hasPrefix("#") ? $0 : "#\($0)" }
            parts.append(tags.joined(separator: " "))
        }
        
        return parts.joined(separator: "\n\n")
    }
    
    private func generateEmail(story: Story, options: ShareOptions) -> String {
        var lines: [String] = []
        
        lines.append("Subject: \(story.title)")
        lines.append("")
        lines.append("Hi,")
        lines.append("")
        lines.append("I thought you might find this article interesting:")
        lines.append("")
        lines.append(story.title)
        
        if options.includeSource, let source = story.sourceFeedName {
            lines.append("From: \(source)")
        }
        
        if options.includeExcerpt {
            lines.append("")
            lines.append(truncate(story.body, to: options.excerptLength))
        }
        
        lines.append("")
        lines.append("Read the full article: \(story.link)")
        
        if options.includeAttribution {
            lines.append("")
            lines.append("— \(options.attributionText)")
        }
        
        return lines.joined(separator: "\n")
    }
    
    // MARK: - Digest Generators
    
    private func generateDigestPlainText(stories: [Story], title: String, options: ShareOptions) -> String {
        var lines: [String] = []
        lines.append(title)
        lines.append(String(repeating: "=", count: title.count))
        lines.append("")
        
        for (index, story) in stories.enumerated() {
            lines.append("\(index + 1). \(story.title)")
            if options.includeSource, let source = story.sourceFeedName {
                lines.append("   Source: \(source)")
            }
            if options.includeExcerpt {
                lines.append("   \(truncate(story.body, to: 150))")
            }
            lines.append("   Link: \(story.link)")
            lines.append("")
        }
        
        if options.includeAttribution {
            lines.append("— \(options.attributionText)")
        }
        
        return lines.joined(separator: "\n")
    }
    
    private func generateDigestMarkdown(stories: [Story], title: String, options: ShareOptions) -> String {
        var lines: [String] = []
        lines.append("# \(title)")
        lines.append("")
        
        for story in stories {
            lines.append("- **[\(story.title)](\(story.link))**")
            if options.includeSource, let source = story.sourceFeedName {
                lines.append("  *\(source)*")
            }
            if options.includeExcerpt {
                lines.append("  \(truncate(story.body, to: 150))")
            }
        }
        
        if options.includeAttribution {
            lines.append("")
            lines.append("*\(options.attributionText)*")
        }
        
        return lines.joined(separator: "\n")
    }
    
    private func generateDigestHTML(stories: [Story], title: String, options: ShareOptions) -> String {
        var html = "<div class=\"article-digest\">\n"
        html += "  <h1>\(title.htmlEscaped)</h1>\n"
        html += "  <ul>\n"
        
        for story in stories {
            html += "    <li>\n"
            html += "      <a href=\"\(story.link.htmlEscaped)\">\(story.title.htmlEscaped)</a>\n"
            if options.includeSource, let source = story.sourceFeedName {
                html += "      <span class=\"source\"> — \(source.htmlEscaped)</span>\n"
            }
            if options.includeExcerpt {
                html += "      <p>\(truncate(story.body, to: 150).htmlEscaped)</p>\n"
            }
            html += "    </li>\n"
        }
        
        html += "  </ul>\n"
        
        if options.includeAttribution {
            html += "  <p class=\"attribution\"><em>\(options.attributionText.htmlEscaped)</em></p>\n"
        }
        
        html += "</div>"
        return html
    }
    
    private func generateDigestEmail(stories: [Story], title: String, options: ShareOptions) -> String {
        var lines: [String] = []
        
        lines.append("Subject: \(title)")
        lines.append("")
        lines.append("Hi,")
        lines.append("")
        lines.append("Here are some articles I wanted to share:")
        lines.append("")
        
        for (index, story) in stories.enumerated() {
            lines.append("\(index + 1). \(story.title)")
            if options.includeExcerpt {
                lines.append("   \(truncate(story.body, to: 150))")
            }
            lines.append("   \(story.link)")
            lines.append("")
        }
        
        if options.includeAttribution {
            lines.append("— \(options.attributionText)")
        }
        
        return lines.joined(separator: "\n")
    }
    
    // MARK: - Utilities
    
    /// Truncate text to a maximum length, adding ellipsis if truncated.
    private func truncate(_ text: String, to maxLength: Int) -> String {
        guard text.count > maxLength else { return text }
        let truncated = String(text.prefix(maxLength - 1))
        // Try to break at a word boundary
        if let lastSpace = truncated.lastIndex(of: " ") {
            return String(truncated[..<lastSpace]) + "…"
        }
        return truncated + "…"
    }
    
    /// Estimate reading time for a text.
    private func estimateReadingTime(text: String, wpm: Int) -> String {
        let wordCount = text.split(separator: " ").count
        let minutes = max(1, Int(ceil(Double(wordCount) / Double(wpm))))
        return minutes == 1 ? "1 min read" : "\(minutes) min read"
    }
    
    /// Escape HTML special characters.
    private func _ text: String.htmlEscaped -> String {
        return text
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "'", with: "&#39;")
    }
    
    // MARK: - Share History
    
    private func recordShare(result: ShareResult, format: ShareFormat) {
        let formatName: String
        switch format {
        case .plainText: formatName = "plainText"
        case .markdown: formatName = "markdown"
        case .html: formatName = "html"
        case .socialPost: formatName = "socialPost"
        case .email: formatName = "email"
        }
        
        let entry = ShareHistoryEntry(
            title: result.title,
            url: result.url,
            format: formatName,
            timestamp: Date(),
            characterCount: result.characterCount
        )
        
        shareHistory.insert(entry, at: 0)
        
        // Trim history
        if shareHistory.count > maxHistoryEntries {
            shareHistory = Array(shareHistory.prefix(maxHistoryEntries))
        }
        
        saveHistory()
    }
    
    /// Get share count for a specific URL.
    func shareCount(for url: String) -> Int {
        return shareHistory.filter { $0.url == url }.count
    }
    
    /// Get most shared articles.
    func mostShared(limit: Int = 10) -> [(url: String, title: String, count: Int)] {
        var counts: [String: (title: String, count: Int)] = [:]
        for entry in shareHistory {
            if let existing = counts[entry.url] {
                counts[entry.url] = (title: existing.title, count: existing.count + 1)
            } else {
                counts[entry.url] = (title: entry.title, count: 1)
            }
        }
        return counts.map { (url: $0.key, title: $0.value.title, count: $0.value.count) }
            .sorted { $0.count > $1.count }
            .prefix(limit)
            .map { $0 }
    }
    
    /// Clear share history.
    func clearHistory() {
        shareHistory = []
        saveHistory()
    }
    
    // MARK: - Persistence
    
    private func saveHistory() {
        do {
            let data = try JSONEncoder().encode(shareHistory)
            try data.write(to: ShareManager.historyURL)
        } catch {
            os_log("Failed to save share history: %{private}s", log: FeedReaderLogger.share, type: .error, error.localizedDescription)
        }
    }
    
    private func loadHistory() {
        guard let data = try? Data(contentsOf: ShareManager.historyURL) else {
            shareHistory = []
            return
        }
        shareHistory = (try? JSONDecoder().decode([ShareHistoryEntry].self, from: data)) ?? []
    }
}
