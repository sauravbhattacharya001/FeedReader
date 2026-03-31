//
//  ArticleSummaryGenerator.swift
//  FeedReader
//
//  Higher-level summary generator wrapping ArticleSummarizer with
//  convenience APIs for title-aware summarization, batch processing,
//  formatting (plain, bullets, numbered), and confidence scoring.
//

import Foundation

// MARK: - Summary Output

/// Formatted summary result from ArticleSummaryGenerator.
struct ArticleSummary {
    /// Article title (echoed back for batch identification).
    let title: String
    /// Selected summary sentences in original order.
    let sentences: [String]
    /// Number of sentences selected.
    var selectedCount: Int { sentences.count }
    /// Total sentences in the original text.
    let originalSentenceCount: Int
    /// Combined summary text.
    var text: String { sentences.joined(separator: " ") }
    /// Confidence score 0.0–1.0 based on compression quality.
    let confidence: Double
    /// Character-based compression ratio (summary / original).
    let compressionRatio: Double
}

/// Output format for summary text.
enum SummaryFormat {
    case plain
    case bullets
    case numbered
}

// MARK: - ArticleSummaryGenerator

/// Static + singleton convenience layer over ArticleSummarizer.
class ArticleSummaryGenerator {

    static let shared = ArticleSummaryGenerator()

    private let summarizer = ArticleSummarizer.shared

    // MARK: - Static API

    /// Summarize a single article with title relevance boosting.
    static func summarize(title: String, text: String, maxSentences: Int = 3, config: SummaryConfig = .default) -> ArticleSummary {
        var cfg = config
        cfg.maxSentences = maxSentences

        guard let result = shared.summarizer.summarize(text, title: title, config: cfg) else {
            return ArticleSummary(
                title: title,
                sentences: [],
                originalSentenceCount: 0,
                confidence: 0.0,
                compressionRatio: 0.0
            )
        }

        // Extract selected sentences (top N in original order)
        let selectedSentences = result.rankedSentences.prefix(result.summarySentenceCount).map { $0.sentence }

        // Confidence heuristic: higher when we have enough sentences and good compression
        let sentenceRatio = result.originalSentenceCount > 0
            ? min(Double(result.summarySentenceCount) / Double(result.originalSentenceCount), 1.0)
            : 0.0
        let confidence = min(1.0, max(0.0, (1.0 - result.compressionRatio) * 0.7 + sentenceRatio * 0.3))

        return ArticleSummary(
            title: title,
            sentences: Array(selectedSentences),
            originalSentenceCount: result.originalSentenceCount,
            confidence: confidence,
            compressionRatio: result.compressionRatio
        )
    }

    /// Format a summary as bullets, numbered list, or plain text.
    static func format(_ summary: ArticleSummary, as fmt: SummaryFormat) -> String {
        switch fmt {
        case .plain:
            return summary.text
        case .bullets:
            return summary.sentences.map { "• \($0)" }.joined(separator: "\n")
        case .numbered:
            return summary.sentences.enumerated().map { "\($0.offset + 1). \($0.element)" }.joined(separator: "\n")
        }
    }

    /// Batch summarize multiple articles.
    static func batchSummarize(articles: [(title: String, text: String)], maxSentences: Int = 3, config: SummaryConfig = .default) -> [ArticleSummary] {
        return articles.map { summarize(title: $0.title, text: $0.text, maxSentences: maxSentences, config: config) }
    }

    // MARK: - Instance API

    /// Split text into sentences (exposed for testing).
    func splitSentences(_ text: String) -> [String] {
        return summarizer.splitSentences(text)
    }
}
