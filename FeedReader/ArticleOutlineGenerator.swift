//
//  ArticleOutlineGenerator.swift
//  FeedReader
//
//  Generates a hierarchical outline / table of contents from article text.
//  Helps users quickly skim long articles by extracting structure:
//    - Section detection via heading patterns and topic transitions
//    - Key sentence extraction per section (topic sentences)
//    - Nested outline with depth levels
//    - Word count and reading time per section
//    - Outline export as plain text, Markdown, or JSON
//    - Outline comparison between articles
//    - Section importance scoring based on keyword density
//
//  Persistence: UserDefaults via UserDefaultsCodableStore.
//  Works entirely offline with no external dependencies.
//

import Foundation

// MARK: - Notifications

extension Notification.Name {
    /// Posted when an article outline is generated or updated.
    static let articleOutlineDidUpdate = Notification.Name("ArticleOutlineDidUpdateNotification")
}

// MARK: - Models

/// A single section in an article outline.
struct OutlineSection: Codable, Equatable, Identifiable {
    let id: String
    let title: String
    let depth: Int              // 0 = top-level, 1 = subsection, etc.
    let startIndex: Int         // Character offset in original text
    let endIndex: Int
    let wordCount: Int
    let readingTimeSeconds: Int // At ~238 WPM average
    let topicSentence: String   // First meaningful sentence
    let keywords: [String]      // Top keywords for this section
    let importanceScore: Double // 0.0–1.0, based on keyword density + position
    let children: [OutlineSection]
}

/// Complete outline for an article.
struct ArticleOutline: Codable, Equatable {
    let articleURL: String
    let articleTitle: String
    let generatedAt: Date
    let totalWordCount: Int
    let totalReadingTimeSeconds: Int
    let sections: [OutlineSection]
    let summaryKeywords: [String] // Top keywords across entire article
}

/// Comparison result between two outlines.
struct OutlineComparison: Codable {
    let articleA: String
    let articleB: String
    let sharedKeywords: [String]
    let structuralSimilarity: Double // 0.0–1.0
    let depthDifference: Int
    let sectionCountDifference: Int
}

/// Cached outline entry with metadata.
private struct OutlineEntry: Codable {
    let outline: ArticleOutline
    let textHash: Int // For invalidation when content changes
}

// MARK: - Outline Generator

/// Generates hierarchical outlines from article text for quick skimming.
///
/// Usage:
/// ```
/// let generator = ArticleOutlineGenerator()
/// let outline = generator.generateOutline(
///     url: "https://example.com/article",
///     title: "Long Article",
///     text: articleBody
/// )
/// print(generator.renderMarkdown(outline))
/// let stats = generator.sectionStats(outline)
/// ```
class ArticleOutlineGenerator {

    // MARK: - Constants

    private static let wordsPerMinute: Double = 238.0
    private static let minSectionWords = 30
    private static let maxKeywordsPerSection = 5
    private static let maxSummaryKeywords = 10
    private static let maxCachedOutlines = 200

    // MARK: - Persistence

    private let store = UserDefaultsCodableStore<[String: OutlineEntry]>(key: "ArticleOutlineGenerator.cache")

    private var cache: [String: OutlineEntry] {
        get { store.load() ?? [:] }
        set { store.save(newValue) }
    }

    // MARK: - Stop Words

    private static let stopWords: Set<String> = [
        "the", "a", "an", "and", "or", "but", "in", "on", "at", "to", "for",
        "of", "with", "by", "from", "is", "it", "as", "was", "are", "be",
        "been", "being", "have", "has", "had", "do", "does", "did", "will",
        "would", "could", "should", "may", "might", "can", "this", "that",
        "these", "those", "i", "you", "he", "she", "we", "they", "me",
        "him", "her", "us", "them", "my", "your", "his", "its", "our",
        "their", "what", "which", "who", "when", "where", "how", "not",
        "no", "if", "then", "than", "so", "just", "also", "very", "much",
        "more", "most", "some", "any", "all", "each", "every", "both",
        "few", "many", "such", "about", "up", "out", "into", "over",
        "after", "before", "between", "under", "again", "there", "here",
        "through", "during", "above", "below", "while", "because", "until"
    ]

    // MARK: - Heading Patterns

    /// Patterns that indicate a heading or section break in article text.
    private static let headingPatterns: [NSRegularExpression] = {
        let patterns = [
            // Markdown-style headings
            "^#{1,6}\\s+.+$",
            // ALL CAPS lines (likely headings)
            "^[A-Z][A-Z\\s:]{4,}$",
            // Numbered sections: "1.", "1.1", "I.", "A."
            "^\\d+\\.\\d*\\s+.+$",
            "^[IVXLC]+\\.\\s+.+$",
            "^[A-Z]\\.\\s+.+$",
            // Lines ending with colon (often sub-headings)
            "^[A-Z][^.!?]{3,50}:$"
        ]
        return patterns.compactMap { try? NSRegularExpression(pattern: $0, options: .anchorsMatchLines) }
    }()

    /// Transition phrases that may indicate a new logical section.
    private static let transitionPhrases: Set<String> = [
        "however", "moreover", "furthermore", "in addition", "on the other hand",
        "in contrast", "meanwhile", "nevertheless", "consequently", "as a result",
        "in conclusion", "to summarize", "first", "second", "third", "finally",
        "next", "then", "additionally", "alternatively", "specifically",
        "for example", "for instance", "in particular", "notably"
    ]

    // MARK: - Public API

    /// Generate an outline from article text.
    func generateOutline(url: String, title: String, text: String) -> ArticleOutline {
        let textHash = text.hashValue

        // Return cached if text hasn't changed
        if let entry = cache[url], entry.textHash == textHash {
            return entry.outline
        }

        let paragraphs = splitIntoParagraphs(text)
        let allWords = extractWords(from: text)
        let totalWordCount = allWords.count
        let totalReadingTime = Int(ceil(Double(totalWordCount) / Self.wordsPerMinute * 60.0))

        // Detect sections
        let rawSections = detectSections(paragraphs: paragraphs, fullText: text)

        // Build hierarchical outline
        let sections = buildHierarchy(from: rawSections)

        // Extract summary keywords
        let summaryKeywords = extractTopKeywords(from: allWords, limit: Self.maxSummaryKeywords)

        let outline = ArticleOutline(
            articleURL: url,
            articleTitle: title,
            generatedAt: Date(),
            totalWordCount: totalWordCount,
            totalReadingTimeSeconds: totalReadingTime,
            sections: sections,
            summaryKeywords: summaryKeywords
        )

        // Cache the result
        var current = cache
        current[url] = OutlineEntry(outline: outline, textHash: textHash)
        // Evict oldest if over limit
        if current.count > Self.maxCachedOutlines {
            let sorted = current.sorted { ($0.value.outline.generatedAt) < ($1.value.outline.generatedAt) }
            let toRemove = current.count - Self.maxCachedOutlines
            for i in 0..<toRemove {
                current.removeValue(forKey: sorted[i].key)
            }
        }
        cache = current

        NotificationCenter.default.post(name: .articleOutlineDidUpdate, object: self)

        return outline
    }

    /// Get cached outline for a URL, if available.
    func cachedOutline(for url: String) -> ArticleOutline? {
        return cache[url]?.outline
    }

    /// Remove cached outline.
    func removeCachedOutline(for url: String) {
        var current = cache
        current.removeValue(forKey: url)
        cache = current
    }

    /// Clear all cached outlines.
    func clearCache() {
        cache = [:]
    }

    /// Number of cached outlines.
    var cachedCount: Int {
        return cache.count
    }

    // MARK: - Rendering

    /// Render outline as Markdown.
    func renderMarkdown(_ outline: ArticleOutline) -> String {
        var lines: [String] = []
        lines.append("# \(outline.articleTitle)")
        lines.append("")
        let totalMin = max(1, outline.totalReadingTimeSeconds / 60)
        lines.append("*\(outline.totalWordCount) words · \(totalMin) min read*")
        lines.append("")
        lines.append("**Keywords:** \(outline.summaryKeywords.joined(separator: ", "))")
        lines.append("")
        lines.append("---")
        lines.append("")

        func renderSections(_ sections: [OutlineSection], indent: Int) {
            for section in sections {
                let prefix = String(repeating: "#", count: min(indent + 2, 6))
                let secMin = max(1, section.readingTimeSeconds / 60)
                lines.append("\(prefix) \(section.title)")
                lines.append("")
                lines.append("> \(section.topicSentence)")
                lines.append("")
                lines.append("*\(section.wordCount) words · \(secMin) min · importance: \(String(format: "%.0f%%", section.importanceScore * 100))*")
                if !section.keywords.isEmpty {
                    lines.append("")
                    lines.append("Tags: \(section.keywords.joined(separator: ", "))")
                }
                lines.append("")
                if !section.children.isEmpty {
                    renderSections(section.children, indent: indent + 1)
                }
            }
        }
        renderSections(outline.sections, indent: 0)
        return lines.joined(separator: "\n")
    }

    /// Render outline as plain text with indentation.
    func renderPlainText(_ outline: ArticleOutline) -> String {
        var lines: [String] = []
        let totalMin = max(1, outline.totalReadingTimeSeconds / 60)
        lines.append("\(outline.articleTitle) (\(outline.totalWordCount) words, \(totalMin) min)")
        lines.append(String(repeating: "=", count: min(outline.articleTitle.count + 20, 60)))

        func renderSections(_ sections: [OutlineSection], indent: Int) {
            for (i, section) in sections.enumerated() {
                let prefix = String(repeating: "  ", count: indent)
                let number = "\(i + 1)."
                let secMin = max(1, section.readingTimeSeconds / 60)
                lines.append("\(prefix)\(number) \(section.title) [\(section.wordCount)w, \(secMin)m]")
                lines.append("\(prefix)   \(section.topicSentence)")
                if !section.children.isEmpty {
                    renderSections(section.children, indent: indent + 1)
                }
            }
        }
        renderSections(outline.sections, indent: 0)
        return lines.joined(separator: "\n")
    }

    /// Export outline as JSON string.
    func renderJSON(_ outline: ArticleOutline) -> String? {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(outline) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    // MARK: - Section Stats

    /// Get per-section statistics as a flat list.
    func sectionStats(_ outline: ArticleOutline) -> [(title: String, depth: Int, wordCount: Int, readingTime: Int, importance: Double)] {
        var result: [(String, Int, Int, Int, Double)] = []
        func collect(_ sections: [OutlineSection]) {
            for section in sections {
                result.append((section.title, section.depth, section.wordCount, section.readingTimeSeconds, section.importanceScore))
                collect(section.children)
            }
        }
        collect(outline.sections)
        return result
    }

    /// Find the longest section.
    func longestSection(_ outline: ArticleOutline) -> OutlineSection? {
        var longest: OutlineSection?
        func scan(_ sections: [OutlineSection]) {
            for section in sections {
                if longest == nil || section.wordCount > (longest?.wordCount ?? 0) {
                    longest = section
                }
                scan(section.children)
            }
        }
        scan(outline.sections)
        return longest
    }

    /// Find the most important section.
    func mostImportantSection(_ outline: ArticleOutline) -> OutlineSection? {
        var best: OutlineSection?
        func scan(_ sections: [OutlineSection]) {
            for section in sections {
                if best == nil || section.importanceScore > (best?.importanceScore ?? 0) {
                    best = section
                }
                scan(section.children)
            }
        }
        scan(outline.sections)
        return best
    }

    // MARK: - Comparison

    /// Compare structure of two outlines.
    func compare(_ a: ArticleOutline, _ b: ArticleOutline) -> OutlineComparison {
        let keywordsA = Set(a.summaryKeywords)
        let keywordsB = Set(b.summaryKeywords)
        let shared = keywordsA.intersection(keywordsB)

        let depthA = maxDepth(a.sections)
        let depthB = maxDepth(b.sections)

        let countA = flatSectionCount(a.sections)
        let countB = flatSectionCount(b.sections)

        // Structural similarity: Jaccard on keyword sets + section count ratio
        let keywordSim = keywordsA.isEmpty && keywordsB.isEmpty ? 0.0 :
            Double(shared.count) / Double(keywordsA.union(keywordsB).count)
        let countRatio = countA == 0 && countB == 0 ? 1.0 :
            Double(min(countA, countB)) / Double(max(countA, countB))
        let structural = (keywordSim + countRatio) / 2.0

        return OutlineComparison(
            articleA: a.articleURL,
            articleB: b.articleURL,
            sharedKeywords: Array(shared).sorted(),
            structuralSimilarity: structural,
            depthDifference: abs(depthA - depthB),
            sectionCountDifference: abs(countA - countB)
        )
    }

    // MARK: - Private Helpers

    private func maxDepth(_ sections: [OutlineSection]) -> Int {
        var d = 0
        for s in sections {
            d = max(d, s.depth)
            if !s.children.isEmpty {
                d = max(d, maxDepth(s.children))
            }
        }
        return d
    }

    private func flatSectionCount(_ sections: [OutlineSection]) -> Int {
        return sections.reduce(0) { $0 + 1 + flatSectionCount($1.children) }
    }

    private func splitIntoParagraphs(_ text: String) -> [String] {
        let raw = text.components(separatedBy: "\n\n")
        return raw.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    private func extractWords(from text: String) -> [String] {
        let lower = text.lowercased()
        let cleaned = lower.unicodeScalars.map { CharacterSet.letters.contains($0) || $0 == " " ? Character($0) : Character(" ") }
        return String(cleaned).split(separator: " ").map(String.init).filter { $0.count > 1 }
    }

    private func extractTopKeywords(from words: [String], limit: Int) -> [String] {
        let meaningful = words.filter { !Self.stopWords.contains($0) && $0.count > 2 }
        var freq: [String: Int] = [:]
        for w in meaningful { freq[w, default: 0] += 1 }
        return freq.sorted { $0.value > $1.value }.prefix(limit).map { $0.key }
    }

    /// A raw detected section before hierarchy building.
    private struct RawSection {
        let title: String
        let text: String
        let startOffset: Int
        let endOffset: Int
        let depthHint: Int // Lower = more top-level
        let isExplicitHeading: Bool
    }

    private func detectSections(paragraphs: [String], fullText: String) -> [RawSection] {
        var sections: [RawSection] = []
        var currentTitle = "Introduction"
        var currentParagraphs: [String] = []
        var currentStart = 0
        var currentDepth = 0
        var charOffset = 0

        for paragraph in paragraphs {
            let trimmed = paragraph.trimmingCharacters(in: .whitespacesAndNewlines)
            let lines = trimmed.components(separatedBy: "\n")

            // Check if first line is a heading
            if let firstLine = lines.first {
                let headingInfo = detectHeading(firstLine)
                if let heading = headingInfo {
                    // Save current section
                    if !currentParagraphs.isEmpty {
                        let text = currentParagraphs.joined(separator: "\n\n")
                        let words = extractWords(from: text)
                        if words.count >= Self.minSectionWords {
                            sections.append(RawSection(
                                title: currentTitle,
                                text: text,
                                startOffset: currentStart,
                                endOffset: charOffset,
                                depthHint: currentDepth,
                                isExplicitHeading: false
                            ))
                        }
                    }
                    currentTitle = heading.title
                    currentDepth = heading.depth
                    currentParagraphs = []
                    currentStart = charOffset
                    // Add remaining lines of paragraph as content
                    if lines.count > 1 {
                        currentParagraphs.append(lines.dropFirst().joined(separator: "\n"))
                    }
                } else if isTransitionStart(trimmed) && currentParagraphs.count >= 3 {
                    // Transition phrase after enough content — split section
                    let text = currentParagraphs.joined(separator: "\n\n")
                    let words = extractWords(from: text)
                    if words.count >= Self.minSectionWords {
                        sections.append(RawSection(
                            title: currentTitle,
                            text: text,
                            startOffset: currentStart,
                            endOffset: charOffset,
                            depthHint: currentDepth,
                            isExplicitHeading: false
                        ))
                    }
                    // Derive title from transition paragraph
                    currentTitle = deriveSectionTitle(from: trimmed)
                    currentParagraphs = [trimmed]
                    currentStart = charOffset
                    currentDepth = max(currentDepth, 1)
                } else {
                    currentParagraphs.append(trimmed)
                }
            }
            charOffset += paragraph.count + 2 // +2 for \n\n separator
        }

        // Flush remaining
        if !currentParagraphs.isEmpty {
            let text = currentParagraphs.joined(separator: "\n\n")
            let words = extractWords(from: text)
            if words.count >= Self.minSectionWords {
                // Use "Conclusion" for last section if it seems like a wrap-up
                let finalTitle: String
                if sections.count > 0 && looksLikeConclusion(text) {
                    finalTitle = "Conclusion"
                } else {
                    finalTitle = currentTitle
                }
                sections.append(RawSection(
                    title: finalTitle,
                    text: text,
                    startOffset: currentStart,
                    endOffset: charOffset,
                    depthHint: currentDepth,
                    isExplicitHeading: false
                ))
            }
        }

        // If no sections detected, create one for the whole article
        if sections.isEmpty {
            sections.append(RawSection(
                title: "Full Article",
                text: fullText,
                startOffset: 0,
                endOffset: fullText.count,
                depthHint: 0,
                isExplicitHeading: false
            ))
        }

        return sections
    }

    private func detectHeading(_ line: String) -> (title: String, depth: Int)? {
        let trimmed = line.trimmingCharacters(in: .whitespaces)

        // Markdown headings
        if trimmed.hasPrefix("#") {
            let hashes = trimmed.prefix(while: { $0 == "#" })
            let depth = hashes.count - 1
            let title = trimmed.dropFirst(hashes.count).trimmingCharacters(in: .whitespaces)
            if !title.isEmpty { return (title, min(depth, 4)) }
        }

        // ALL CAPS (at least 5 chars, not a sentence)
        if trimmed.count >= 5 && trimmed.count <= 60 &&
           trimmed == trimmed.uppercased() &&
           !trimmed.contains(".") &&
           trimmed.rangeOfCharacter(from: .letters) != nil {
            return (trimmed.capitalized, 0)
        }

        // Numbered section
        if let match = trimmed.range(of: "^\\d+\\.\\s+", options: .regularExpression) {
            let title = String(trimmed[match.upperBound...]).trimmingCharacters(in: .whitespaces)
            if !title.isEmpty && title.count <= 80 { return (title, 0) }
        }
        if let match = trimmed.range(of: "^\\d+\\.\\d+\\s+", options: .regularExpression) {
            let title = String(trimmed[match.upperBound...]).trimmingCharacters(in: .whitespaces)
            if !title.isEmpty && title.count <= 80 { return (title, 1) }
        }

        // Line ending with colon, short enough to be a heading
        if trimmed.hasSuffix(":") && trimmed.count <= 50 && trimmed.count >= 4 {
            let title = String(trimmed.dropLast()).trimmingCharacters(in: .whitespaces)
            if !title.isEmpty { return (title, 1) }
        }

        return nil
    }

    private func isTransitionStart(_ paragraph: String) -> Bool {
        let lower = paragraph.lowercased()
        for phrase in Self.transitionPhrases {
            if lower.hasPrefix(phrase) {
                return true
            }
        }
        return false
    }

    private func deriveSectionTitle(from paragraph: String) -> String {
        // Extract first sentence as title, capped at 60 chars
        let sentences = paragraph.components(separatedBy: CharacterSet(charactersIn: ".!?"))
        let first = sentences.first?.trimmingCharacters(in: .whitespacesAndNewlines) ?? paragraph
        if first.count <= 60 { return first }
        let words = first.split(separator: " ")
        var title = ""
        for word in words {
            if title.count + word.count + 1 > 57 { break }
            title += (title.isEmpty ? "" : " ") + word
        }
        return title + "..."
    }

    private func looksLikeConclusion(_ text: String) -> Bool {
        let lower = text.lowercased()
        let markers = ["in conclusion", "to summarize", "in summary", "to conclude",
                       "final thoughts", "wrapping up", "takeaway", "key points"]
        return markers.contains { lower.contains($0) }
    }

    private func buildHierarchy(from rawSections: [RawSection]) -> [OutlineSection] {
        // Simple approach: depth 0 = top-level, depth > 0 = children of previous top-level
        var topLevel: [OutlineSection] = []
        var pendingChildren: [OutlineSection] = []
        var lastTopSection: RawSection?

        for raw in rawSections {
            let section = makeOutlineSection(from: raw)

            if raw.depthHint == 0 {
                // Flush pending children to previous top-level
                if !pendingChildren.isEmpty, var last = topLevel.last {
                    last = OutlineSection(
                        id: last.id, title: last.title, depth: last.depth,
                        startIndex: last.startIndex, endIndex: last.endIndex,
                        wordCount: last.wordCount, readingTimeSeconds: last.readingTimeSeconds,
                        topicSentence: last.topicSentence, keywords: last.keywords,
                        importanceScore: last.importanceScore, children: pendingChildren
                    )
                    topLevel[topLevel.count - 1] = last
                    pendingChildren = []
                }
                topLevel.append(section)
                lastTopSection = raw
            } else {
                pendingChildren.append(section)
            }
        }

        // Flush remaining children
        if !pendingChildren.isEmpty, var last = topLevel.last {
            last = OutlineSection(
                id: last.id, title: last.title, depth: last.depth,
                startIndex: last.startIndex, endIndex: last.endIndex,
                wordCount: last.wordCount, readingTimeSeconds: last.readingTimeSeconds,
                topicSentence: last.topicSentence, keywords: last.keywords,
                importanceScore: last.importanceScore, children: pendingChildren
            )
            topLevel[topLevel.count - 1] = last
        }

        return topLevel
    }

    private func makeOutlineSection(from raw: RawSection) -> OutlineSection {
        let words = extractWords(from: raw.text)
        let wordCount = words.count
        let readingTime = Int(ceil(Double(wordCount) / Self.wordsPerMinute * 60.0))
        let keywords = extractTopKeywords(from: words, limit: Self.maxKeywordsPerSection)

        // Topic sentence: first sentence of the section
        let topicSentence = extractFirstSentence(from: raw.text)

        // Importance: combination of keyword density and position bonus
        let meaningfulWords = words.filter { !Self.stopWords.contains($0) && $0.count > 2 }
        let density = wordCount > 0 ? Double(meaningfulWords.count) / Double(wordCount) : 0
        let importance = min(1.0, density * 1.5)

        return OutlineSection(
            id: UUID().uuidString,
            title: raw.title,
            depth: raw.depthHint,
            startIndex: raw.startOffset,
            endIndex: raw.endOffset,
            wordCount: wordCount,
            readingTimeSeconds: readingTime,
            topicSentence: topicSentence,
            keywords: keywords,
            importanceScore: round(importance * 100) / 100,
            children: []
        )
    }

    private func extractFirstSentence(from text: String) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        // Find first sentence-ending punctuation
        for (i, char) in trimmed.enumerated() {
            if (char == "." || char == "!" || char == "?") && i > 10 {
                let sentence = String(trimmed.prefix(i + 1))
                if sentence.count <= 200 { return sentence }
                // Truncate long sentences
                return String(sentence.prefix(197)) + "..."
            }
        }
        // No sentence boundary found — return first 200 chars
        if trimmed.count <= 200 { return trimmed }
        return String(trimmed.prefix(197)) + "..."
    }
}
