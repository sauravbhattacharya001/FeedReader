//
//  ArticleThreadComposer.swift
//  FeedReader
//
//  Composes social media thread breakdowns from articles. Splits long content
//  into numbered posts respecting platform character limits, adds hooks,
//  hashtags, and thread connectors. Supports Twitter/X, Mastodon, Bluesky,
//  and LinkedIn formatting. Useful for sharing article insights as threads.
//

import Foundation

// MARK: - Models

/// Social platform with specific thread constraints.
enum ThreadPlatform: String, Codable, CaseIterable {
    case twitter = "twitter"
    case mastodon = "mastodon"
    case bluesky = "bluesky"
    case linkedin = "linkedin"

    var displayName: String {
        switch self {
        case .twitter: return "Twitter/X"
        case .mastodon: return "Mastodon"
        case .bluesky: return "Bluesky"
        case .linkedin: return "LinkedIn"
        }
    }

    /// Maximum characters per post.
    var charLimit: Int {
        switch self {
        case .twitter: return 280
        case .mastodon: return 500
        case .bluesky: return 300
        case .linkedin: return 3000
        }
    }

    /// Maximum number of posts in a thread.
    var maxPosts: Int {
        switch self {
        case .twitter: return 25
        case .mastodon: return 20
        case .bluesky: return 20
        case .linkedin: return 10
        }
    }

    /// Whether the platform natively supports threads.
    var supportsNativeThreads: Bool {
        switch self {
        case .twitter, .mastodon, .bluesky: return true
        case .linkedin: return false
        }
    }
}

/// Style for thread composition.
enum ThreadStyle: String, Codable, CaseIterable {
    case summary = "summary"
    case keyPoints = "key_points"
    case quotes = "quotes"
    case narrative = "narrative"
    case listicle = "listicle"

    var displayName: String {
        switch self {
        case .summary: return "Summary Thread"
        case .keyPoints: return "Key Points"
        case .quotes: return "Notable Quotes"
        case .narrative: return "Story Thread"
        case .listicle: return "Listicle"
        }
    }
}

/// Options for composing a thread.
struct ThreadComposerOptions: Codable {
    var platform: ThreadPlatform = .twitter
    var style: ThreadStyle = .keyPoints
    var includeHook: Bool = true
    var includeSource: Bool = true
    var includeNumbering: Bool = true
    var hashtags: [String] = []
    var maxPosts: Int? = nil
    var includeCallToAction: Bool = true
    var callToAction: String = "Read the full article"
    var emojiStyle: EmojiStyle = .moderate

    enum EmojiStyle: String, Codable, CaseIterable {
        case none = "none"
        case minimal = "minimal"
        case moderate = "moderate"
        case heavy = "heavy"
    }
}

/// A single post in a thread.
struct ThreadPost: Codable {
    let index: Int
    let totalPosts: Int
    let content: String
    let charCount: Int
    let isHook: Bool
    let isCloser: Bool

    var numbering: String {
        return "\(index)/\(totalPosts)"
    }

    var remainingChars: Int {
        return 0 // Set by composer based on platform
    }
}

/// A composed thread ready for posting.
struct ComposedThread: Codable {
    let articleTitle: String
    let articleURL: String?
    let platform: ThreadPlatform
    let style: ThreadStyle
    let posts: [ThreadPost]
    let composedAt: Date
    let totalCharacters: Int
    let estimatedReadTime: String

    var postCount: Int { posts.count }

    /// Full thread as a single string with separators.
    var fullText: String {
        return posts.map { $0.content }.joined(separator: "\n\n---\n\n")
    }

    /// Copy-paste friendly version with post numbers.
    var copyableText: String {
        return posts.map { "[\($0.numbering)]\n\($0.content)" }.joined(separator: "\n\n")
    }
}

/// Statistics about thread composition.
struct ThreadStats: Codable {
    let totalThreadsComposed: Int
    let platformBreakdown: [String: Int]
    let styleBreakdown: [String: Int]
    let averagePostsPerThread: Double
    let totalPostsComposed: Int
    let mostUsedHashtags: [(String, Int)]

    enum CodingKeys: String, CodingKey {
        case totalThreadsComposed, platformBreakdown, styleBreakdown
        case averagePostsPerThread, totalPostsComposed
    }

    init(totalThreadsComposed: Int, platformBreakdown: [String: Int],
         styleBreakdown: [String: Int], averagePostsPerThread: Double,
         totalPostsComposed: Int, mostUsedHashtags: [(String, Int)]) {
        self.totalThreadsComposed = totalThreadsComposed
        self.platformBreakdown = platformBreakdown
        self.styleBreakdown = styleBreakdown
        self.averagePostsPerThread = averagePostsPerThread
        self.totalPostsComposed = totalPostsComposed
        self.mostUsedHashtags = mostUsedHashtags
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        totalThreadsComposed = try container.decode(Int.self, forKey: .totalThreadsComposed)
        platformBreakdown = try container.decode([String: Int].self, forKey: .platformBreakdown)
        styleBreakdown = try container.decode([String: Int].self, forKey: .styleBreakdown)
        averagePostsPerThread = try container.decode(Double.self, forKey: .averagePostsPerThread)
        totalPostsComposed = try container.decode(Int.self, forKey: .totalPostsComposed)
        mostUsedHashtags = []
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(totalThreadsComposed, forKey: .totalThreadsComposed)
        try container.encode(platformBreakdown, forKey: .platformBreakdown)
        try container.encode(styleBreakdown, forKey: .styleBreakdown)
        try container.encode(averagePostsPerThread, forKey: .averagePostsPerThread)
        try container.encode(totalPostsComposed, forKey: .totalPostsComposed)
    }
}

// MARK: - Thread Composer

/// Composes social media threads from article content.
class ArticleThreadComposer {
    private var history: [ComposedThread] = []
    private let sentenceEnders: CharacterSet = CharacterSet(charactersIn: ".!?")

    init() {}

    // MARK: - Compose Thread

    /// Compose a thread from article text.
    func compose(title: String, text: String, url: String? = nil,
                 options: ThreadComposerOptions = ThreadComposerOptions()) -> ComposedThread {
        let effectiveMaxPosts = min(options.maxPosts ?? options.platform.maxPosts,
                                     options.platform.maxPosts)
        let charLimit = options.platform.charLimit

        var posts: [ThreadPost] = []
        let sentences = extractSentences(from: text)
        let keyPoints = extractKeyPoints(sentences: sentences, style: options.style)

        // Build hook post
        if options.includeHook {
            let hook = buildHook(title: title, options: options, charLimit: charLimit,
                                 reserveForNumbering: options.includeNumbering)
            posts.append(hook)
        }

        // Build body posts
        let bodyBudget = effectiveMaxPosts - posts.count - (options.includeCallToAction ? 1 : 0)
        let bodyPosts = buildBodyPosts(keyPoints: keyPoints, options: options,
                                        charLimit: charLimit, maxPosts: bodyBudget)
        posts.append(contentsOf: bodyPosts)

        // Build closer post
        if options.includeCallToAction {
            let closer = buildCloser(title: title, url: url, options: options, charLimit: charLimit)
            posts.append(closer)
        }

        // Apply numbering and finalize
        let totalPosts = posts.count
        let finalPosts = posts.enumerated().map { index, post in
            let numbering = options.includeNumbering ? "[\(index + 1)/\(totalPosts)] " : ""
            let content = numbering + post.content
            return ThreadPost(index: index + 1, totalPosts: totalPosts,
                            content: content, charCount: content.count,
                            isHook: index == 0 && options.includeHook,
                            isCloser: index == totalPosts - 1 && options.includeCallToAction)
        }

        let totalChars = finalPosts.reduce(0) { $0 + $1.charCount }
        let wordCount = text.split(separator: " ").count
        let readMinutes = max(1, wordCount / 200)

        let thread = ComposedThread(
            articleTitle: title, articleURL: url, platform: options.platform,
            style: options.style, posts: finalPosts, composedAt: Date(),
            totalCharacters: totalChars,
            estimatedReadTime: "\(readMinutes) min read"
        )

        history.append(thread)
        return thread
    }

    // MARK: - Quick Compose Presets

    /// Quick thread for Twitter with key points.
    func quickTwitterThread(title: String, text: String, url: String? = nil) -> ComposedThread {
        var opts = ThreadComposerOptions()
        opts.platform = .twitter
        opts.style = .keyPoints
        return compose(title: title, text: text, url: url, options: opts)
    }

    /// Quick thread for Mastodon with summary style.
    func quickMastodonThread(title: String, text: String, url: String? = nil) -> ComposedThread {
        var opts = ThreadComposerOptions()
        opts.platform = .mastodon
        opts.style = .summary
        opts.emojiStyle = .minimal
        return compose(title: title, text: text, url: url, options: opts)
    }

    /// Quick thread for Bluesky with listicle style.
    func quickBlueskyThread(title: String, text: String, url: String? = nil) -> ComposedThread {
        var opts = ThreadComposerOptions()
        opts.platform = .bluesky
        opts.style = .listicle
        return compose(title: title, text: text, url: url, options: opts)
    }

    /// Quick LinkedIn post (single long post with highlights).
    func quickLinkedInPost(title: String, text: String, url: String? = nil) -> ComposedThread {
        var opts = ThreadComposerOptions()
        opts.platform = .linkedin
        opts.style = .narrative
        opts.includeNumbering = false
        opts.emojiStyle = .minimal
        return compose(title: title, text: text, url: url, options: opts)
    }

    // MARK: - Statistics

    /// Get composition statistics.
    func getStats() -> ThreadStats {
        var platformCounts: [String: Int] = [:]
        var styleCounts: [String: Int] = [:]
        var hashtagCounts: [String: Int] = [:]
        var totalPosts = 0

        for thread in history {
            platformCounts[thread.platform.rawValue, default: 0] += 1
            styleCounts[thread.style.rawValue, default: 0] += 1
            totalPosts += thread.postCount
        }

        let avgPosts = history.isEmpty ? 0.0 : Double(totalPosts) / Double(history.count)
        let sortedTags = hashtagCounts.sorted { $0.value > $1.value }.map { ($0.key, $0.value) }

        return ThreadStats(
            totalThreadsComposed: history.count,
            platformBreakdown: platformCounts,
            styleBreakdown: styleCounts,
            averagePostsPerThread: avgPosts,
            totalPostsComposed: totalPosts,
            mostUsedHashtags: Array(sortedTags.prefix(10))
        )
    }

    /// Get composition history.
    func getHistory() -> [ComposedThread] { return history }

    /// Clear history.
    func clearHistory() { history.removeAll() }

    // MARK: - Export

    /// Export thread as JSON.
    func exportJSON(thread: ComposedThread) -> String? {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(thread) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    /// Export thread as Markdown.
    func exportMarkdown(thread: ComposedThread) -> String {
        var md = "# Thread: \(thread.articleTitle)\n\n"
        md += "**Platform:** \(thread.platform.displayName) | "
        md += "**Style:** \(thread.style.displayName) | "
        md += "**Posts:** \(thread.postCount)\n\n"

        if let url = thread.articleURL {
            md += "**Source:** \(url)\n\n"
        }

        md += "---\n\n"

        for post in thread.posts {
            md += "### Post \(post.numbering)\n\n"
            md += "\(post.content)\n\n"
            md += "*\(post.charCount) characters*\n\n"
        }

        md += "---\n\n"
        md += "*Composed: \(ISO8601DateFormatter().string(from: thread.composedAt)) | "
        md += "Total: \(thread.totalCharacters) characters | \(thread.estimatedReadTime)*\n"

        return md
    }

    /// Export thread as plain text ready to paste.
    func exportPlainText(thread: ComposedThread) -> String {
        return thread.copyableText
    }

    // MARK: - Private Helpers

    private func extractSentences(from text: String) -> [String] {
        var sentences: [String] = []
        var current = ""

        for char in text {
            current.append(char)
            if ".!?".contains(char) {
                let trimmed = current.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty && trimmed.count > 10 {
                    sentences.append(trimmed)
                }
                current = ""
            }
        }

        let remaining = current.trimmingCharacters(in: .whitespacesAndNewlines)
        if !remaining.isEmpty && remaining.count > 10 {
            sentences.append(remaining)
        }

        return sentences
    }

    private func extractKeyPoints(sentences: [String], style: ThreadStyle) -> [String] {
        switch style {
        case .keyPoints, .listicle:
            // Pick sentences that are informative (longer, contain key indicators)
            let scored = sentences.map { sentence -> (String, Double) in
                var score = 0.0
                let lower = sentence.lowercased()
                // Prefer sentences with substance indicators
                let indicators = ["important", "key", "significant", "found", "shows",
                                  "reveals", "according", "study", "research", "percent",
                                  "million", "billion", "first", "new", "however",
                                  "because", "therefore", "result"]
                for indicator in indicators {
                    if lower.contains(indicator) { score += 1.0 }
                }
                // Prefer medium-length sentences
                if sentence.count > 40 && sentence.count < 200 { score += 1.0 }
                // Penalize very short
                if sentence.count < 30 { score -= 1.0 }
                return (sentence, score)
            }
            return scored.sorted { $0.1 > $1.1 }.map { $0.0 }

        case .quotes:
            // Look for quoted text
            let quoted = sentences.filter { $0.contains("\"") || $0.contains("\u{201C}") }
            return quoted.isEmpty ? Array(sentences.prefix(10)) : quoted

        case .summary, .narrative:
            // Take first and spread evenly through article
            guard sentences.count > 1 else { return sentences }
            var picks: [String] = [sentences[0]]
            let step = max(1, sentences.count / 8)
            for i in stride(from: step, to: sentences.count, by: step) {
                picks.append(sentences[i])
            }
            if let last = sentences.last, picks.last != last {
                picks.append(last)
            }
            return picks
        }
    }

    private func buildHook(title: String, options: ThreadComposerOptions,
                           charLimit: Int, reserveForNumbering: Bool) -> ThreadPost {
        let emojis: [ThreadStyle: String] = [
            .summary: "📝", .keyPoints: "🔑", .quotes: "💬",
            .narrative: "📖", .listicle: "📋"
        ]
        let emoji = options.emojiStyle != .none ? (emojis[options.style] ?? "🧵") + " " : ""
        let threadIndicator = "A thread:\n\n"

        var hook = "\(emoji)\(title)\n\n\(threadIndicator)"
        if hook.count > charLimit - 10 {
            // Truncate title
            let available = charLimit - 30
            let truncTitle = String(title.prefix(available)) + "..."
            hook = "\(emoji)\(truncTitle)\n\n\(threadIndicator)"
        }

        return ThreadPost(index: 0, totalPosts: 0, content: hook.trimmingCharacters(in: .whitespacesAndNewlines),
                          charCount: hook.count, isHook: true, isCloser: false)
    }

    private func buildBodyPosts(keyPoints: [String], options: ThreadComposerOptions,
                                 charLimit: Int, maxPosts: Int) -> [ThreadPost] {
        var posts: [ThreadPost] = []
        guard maxPosts > 0 else { return posts }

        let numberingReserve = 8 // e.g., "[3/10] "
        let available = charLimit - numberingReserve
        var currentContent = ""

        let bulletEmoji: String
        switch options.emojiStyle {
        case .none: bulletEmoji = "•"
        case .minimal: bulletEmoji = "▸"
        case .moderate: bulletEmoji = "→"
        case .heavy: bulletEmoji = "✦"
        }

        for point in keyPoints {
            let entry: String
            switch options.style {
            case .listicle:
                entry = "\(bulletEmoji) \(point)"
            case .quotes:
                entry = "\"\(point)\""
            default:
                entry = point
            }

            let tentative = currentContent.isEmpty ? entry : currentContent + "\n\n" + entry
            if tentative.count > available {
                // Flush current
                if !currentContent.isEmpty {
                    posts.append(ThreadPost(index: 0, totalPosts: 0,
                                           content: currentContent, charCount: currentContent.count,
                                           isHook: false, isCloser: false))
                    if posts.count >= maxPosts { break }
                }
                // Start new with this entry (truncate if needed)
                currentContent = String(entry.prefix(available))
            } else {
                currentContent = tentative
            }
        }

        // Flush remaining
        if !currentContent.isEmpty && posts.count < maxPosts {
            posts.append(ThreadPost(index: 0, totalPosts: 0,
                                   content: currentContent, charCount: currentContent.count,
                                   isHook: false, isCloser: false))
        }

        return posts
    }

    private func buildCloser(title: String, url: String?, options: ThreadComposerOptions,
                              charLimit: Int) -> ThreadPost {
        var closer = ""

        if options.includeCallToAction {
            closer += "\(options.callToAction):"
            if let url = url {
                closer += "\n\(url)"
            }
        }

        if options.includeSource {
            closer += "\n\n📰 \(title)"
        }

        if !options.hashtags.isEmpty {
            let tags = options.hashtags.map { $0.hasPrefix("#") ? $0 : "#\($0)" }.joined(separator: " ")
            closer += "\n\n\(tags)"
        }

        // Truncate if needed
        if closer.count > charLimit - 10 {
            closer = String(closer.prefix(charLimit - 13)) + "..."
        }

        return ThreadPost(index: 0, totalPosts: 0,
                          content: closer.trimmingCharacters(in: .whitespacesAndNewlines),
                          charCount: closer.count, isHook: false, isCloser: true)
    }
}
