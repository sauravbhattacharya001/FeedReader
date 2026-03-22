//
//  ArticleSummaryGenerator.swift
//  FeedReader
//
//  Extractive article summarizer — picks the most important sentences
//  from an article using TF-based scoring with positional bias.
//  No network or ML dependencies; runs entirely offline.
//
//  Features:
//  - Configurable summary length (sentence count or character budget)
//  - Sentence scoring via term frequency + position weight
//  - Title relevance boost (sentences sharing keywords with the title)
//  - Bullet-point and paragraph output formats
//  - Batch summarization for feed digests
//  - Summary quality confidence score
//
//  Usage:
//    let summary = ArticleSummaryGenerator.summarize(
//        title: "Climate Change Impact",
//        text: articleBody,
//        maxSentences: 3
//    )
//    print(summary.text)
//    print(summary.confidence) // 0.0–1.0
//

import Foundation

// MARK: - Models

/// A scored sentence within an article.
struct ScoredSentence: Equatable {
    /// Original sentence text (trimmed).
    let text: String
    /// Zero-based index in the original article.
    let position: Int
    /// Composite importance score (higher = more important).
    let score: Double
}

/// Result of summarizing a single article.
struct ArticleSummary: Equatable {
    /// The article title.
    let title: String
    /// Selected sentences joined as a paragraph.
    let text: String
    /// Selected sentences as an array (in original order).
    let sentences: [String]
    /// Number of sentences in the original article.
    let originalSentenceCount: Int
    /// Number of sentences selected.
    let selectedCount: Int
    /// Compression ratio (selected / original).
    let compressionRatio: Double
    /// Confidence in summary quality (0.0–1.0).
    let confidence: Double
}

/// Configuration for summary generation.
struct SummaryConfig {
    /// Maximum sentences to include.
    var maxSentences: Int = 3
    /// Maximum character budget (0 = unlimited).
    var maxCharacters: Int = 0
    /// Weight for term-frequency score (0.0–1.0).
    var tfWeight: Double = 0.5
    /// Weight for positional bias (0.0–1.0). Earlier sentences score higher.
    var positionWeight: Double = 0.3
    /// Weight for title-relevance boost (0.0–1.0).
    var titleWeight: Double = 0.2
    /// Minimum sentence length (characters) to consider.
    var minSentenceLength: Int = 20

    static let `default` = SummaryConfig()
    static let brief = SummaryConfig(maxSentences: 2, maxCharacters: 280)
    static let detailed = SummaryConfig(maxSentences: 5)
}

/// Output format for summaries.
enum SummaryFormat {
    /// Sentences joined by spaces into a paragraph.
    case paragraph
    /// Each sentence prefixed with "• ".
    case bullets
    /// Each sentence on its own line, numbered.
    case numbered
}

// MARK: - ArticleSummaryGenerator

/// Generates extractive summaries from article text.
class ArticleSummaryGenerator {

    // MARK: - Singleton

    static let shared = ArticleSummaryGenerator()

    private let analyzer = TextAnalyzer.shared

    // MARK: - Public API

    /// Summarize a single article.
    ///
    /// - Parameters:
    ///   - title: Article title (used for relevance boosting).
    ///   - text: Full article body text.
    ///   - config: Summary configuration (default: `.default`).
    /// - Returns: An `ArticleSummary` with the extracted sentences.
    static func summarize(title: String, text: String,
                          config: SummaryConfig = .default) -> ArticleSummary {
        return shared.generateSummary(title: title, text: text, config: config)
    }

    /// Summarize with a simple sentence count parameter.
    static func summarize(title: String, text: String,
                          maxSentences: Int) -> ArticleSummary {
        var config = SummaryConfig.default
        config.maxSentences = max(1, maxSentences)
        return shared.generateSummary(title: title, text: text, config: config)
    }

    /// Format a summary in the specified style.
    static func format(_ summary: ArticleSummary, as style: SummaryFormat) -> String {
        switch style {
        case .paragraph:
            return summary.sentences.joined(separator: " ")
        case .bullets:
            return summary.sentences.map { "• \($0)" }.joined(separator: "\n")
        case .numbered:
            return summary.sentences.enumerated()
                .map { "\($0.offset + 1). \($0.element)" }
                .joined(separator: "\n")
        }
    }

    /// Batch-summarize multiple articles (e.g., for a digest email).
    ///
    /// - Parameters:
    ///   - articles: Array of (title, text) tuples.
    ///   - config: Shared summary configuration.
    /// - Returns: Array of summaries in the same order.
    static func batchSummarize(articles: [(title: String, text: String)],
                               config: SummaryConfig = .brief) -> [ArticleSummary] {
        return articles.map { shared.generateSummary(title: $0.title, text: $0.text, config: config) }
    }

    // MARK: - Core Algorithm

    func generateSummary(title: String, text: String,
                         config: SummaryConfig) -> ArticleSummary {
        let sentences = splitSentences(text)
        let filtered = sentences.filter { $0.count >= config.minSentenceLength }

        guard !filtered.isEmpty else {
            return ArticleSummary(
                title: title,
                text: text.prefix(200).trimmingCharacters(in: .whitespacesAndNewlines),
                sentences: [String(text.prefix(200))],
                originalSentenceCount: sentences.count,
                selectedCount: sentences.isEmpty ? 0 : 1,
                compressionRatio: 1.0,
                confidence: 0.1
            )
        }

        // Tokenize all sentences and build document TF
        let allTokens = filtered.flatMap { analyzer.tokenize($0) }
        let docTF = analyzer.computeTermFrequency(allTokens)
        let titleTokens = Set(analyzer.tokenize(title))

        // Score each sentence
        var scored: [ScoredSentence] = []
        for (index, sentence) in filtered.enumerated() {
            let tokens = analyzer.tokenize(sentence)
            guard !tokens.isEmpty else { continue }

            // Term frequency score: average TF of sentence tokens
            let tfScore = tokens.compactMap { docTF[$0] }.reduce(0, +) / Double(tokens.count)

            // Position score: earlier sentences get higher scores
            let positionScore = 1.0 - (Double(index) / Double(max(filtered.count, 1)))

            // Title relevance: fraction of sentence tokens that appear in title
            let titleOverlap = titleTokens.isEmpty ? 0.0 :
                Double(tokens.filter { titleTokens.contains($0) }.count) / Double(tokens.count)

            let composite = config.tfWeight * tfScore
                + config.positionWeight * positionScore
                + config.titleWeight * titleOverlap

            scored.append(ScoredSentence(text: sentence, position: index, score: composite))
        }

        // Select top sentences
        let sortedByScore = scored.sorted { $0.score > $1.score }
        var selected: [ScoredSentence] = []
        var charBudget = config.maxCharacters > 0 ? config.maxCharacters : Int.max

        for candidate in sortedByScore {
            if selected.count >= config.maxSentences { break }
            if candidate.text.count > charBudget { continue }
            selected.append(candidate)
            charBudget -= candidate.text.count
        }

        // Restore original order
        selected.sort { $0.position < $1.position }

        let selectedTexts = selected.map { $0.text }
        let summaryText = selectedTexts.joined(separator: " ")

        // Confidence based on coverage and score spread
        let avgScore = selected.isEmpty ? 0.0 :
            selected.map { $0.score }.reduce(0, +) / Double(selected.count)
        let coverage = Double(selected.count) / Double(max(filtered.count, 1))
        let confidence = min(1.0, avgScore * 0.6 + (1.0 - coverage) * 0.4)

        let compressionRatio = filtered.isEmpty ? 1.0 :
            Double(selected.count) / Double(filtered.count)

        return ArticleSummary(
            title: title,
            text: summaryText,
            sentences: selectedTexts,
            originalSentenceCount: sentences.count,
            selectedCount: selected.count,
            compressionRatio: compressionRatio,
            confidence: max(0, min(1, confidence))
        )
    }

    // MARK: - Sentence Splitting

    /// Split text into sentences using punctuation boundaries.
    func splitSentences(_ text: String) -> [String] {
        // Use a simple regex-based approach: split on .!? followed by whitespace or end
        let cleaned = text
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "\r", with: " ")
            .replacingOccurrences(of: "  ", with: " ")

        var sentences: [String] = []
        var current = ""

        let chars = Array(cleaned)
        for i in 0..<chars.count {
            current.append(chars[i])
            let ch = chars[i]
            if ch == "." || ch == "!" || ch == "?" {
                // Check if this is a real sentence boundary
                let nextIsSpace = (i + 1 < chars.count && chars[i + 1] == " ") || i + 1 == chars.count
                let isAbbreviation = isLikelyAbbreviation(current)
                if nextIsSpace && !isAbbreviation && current.count > 10 {
                    let trimmed = current.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !trimmed.isEmpty {
                        sentences.append(trimmed)
                    }
                    current = ""
                }
            }
        }

        // Remaining text
        let trimmed = current.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.count >= 10 {
            sentences.append(trimmed)
        }

        return sentences
    }

    /// Simple heuristic to detect abbreviations (e.g., "Dr.", "U.S.", "etc.").
    private func isLikelyAbbreviation(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 2 else { return false }

        // Common abbreviations
        let abbrevs = ["mr.", "mrs.", "ms.", "dr.", "prof.", "sr.", "jr.",
                       "vs.", "etc.", "inc.", "ltd.", "corp.", "dept.",
                       "st.", "ave.", "blvd.", "approx.", "govt.",
                       "e.g.", "i.e.", "a.m.", "p.m."]
        let lower = trimmed.lowercased()
        for abbr in abbrevs {
            if lower.hasSuffix(abbr) { return true }
        }

        // Single uppercase letter followed by period (initials like "U.S.")
        if trimmed.count >= 2 {
            let lastTwo = String(trimmed.suffix(2))
            if lastTwo.first?.isUpperCase == true && lastTwo.last == "." {
                return true
            }
        }

        return false
    }
}
