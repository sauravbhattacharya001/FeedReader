//
//  ArticleSummarizer.swift
//  FeedReader
//
//  Extractive article summarization using TF-IDF sentence scoring.
//  Selects the most informative sentences from an article body to
//  produce a concise summary. Supports configurable sentence count,
//  ratio-based summarization, and title-boosted relevance.
//

import Foundation

/// Configuration for summary generation.
struct SummaryConfig {
    /// Maximum number of sentences in the summary.
    let maxSentences: Int
    /// Ratio of original sentences to keep (0.0–1.0). Overridden by maxSentences if both set.
    let ratio: Double
    /// Boost score of sentences containing title keywords.
    let titleBoost: Double
    /// Boost score of sentences appearing in the first paragraph.
    let positionBoost: Double
    /// Minimum word count for a sentence to be considered.
    let minSentenceWords: Int

    init(maxSentences: Int = 3,
         ratio: Double = 0.3,
         titleBoost: Double = 1.5,
         positionBoost: Double = 1.2,
         minSentenceWords: Int = 4) {
        self.maxSentences = maxSentences
        self.ratio = min(max(ratio, 0.0), 1.0)
        self.titleBoost = titleBoost
        self.positionBoost = positionBoost
        self.minSentenceWords = max(1, minSentenceWords)
    }

    static let `default` = SummaryConfig()
}

/// Result of an extractive summarization.
struct SummaryResult {
    /// The generated summary text.
    let summary: String
    /// Individual scored sentences, sorted by their score (highest first).
    let rankedSentences: [(sentence: String, score: Double)]
    /// Number of sentences in original text.
    let originalSentenceCount: Int
    /// Number of sentences selected for the summary.
    let summarySentenceCount: Int
    /// Compression ratio (summary length / original length).
    let compressionRatio: Double
    /// Keywords extracted from the text, sorted by TF-IDF score.
    let topKeywords: [(word: String, score: Double)]
}

/// Extractive summarizer using TF-IDF scoring with position and title boosts.
///
/// The algorithm:
/// 1. Split text into sentences.
/// 2. Tokenize each sentence, removing stop words.
/// 3. Compute TF-IDF for each term across sentences.
/// 4. Score each sentence by summing its term TF-IDF values.
/// 5. Apply title-keyword boost and position boost.
/// 6. Select top-scoring sentences, preserving original order.
class ArticleSummarizer {

    // MARK: - Singleton

    static let shared = ArticleSummarizer()

    // MARK: - HTML Stripping

    /// Strip HTML tags and decode common entities.
    private func stripHTML(_ html: String) -> String {
        var text = html
        // Remove tags
        text = text.replacingOccurrences(of: "<[^>]+>", with: " ", options: .regularExpression)
        // Decode common entities
        let entities: [(String, String)] = [
            ("&amp;", "&"), ("&lt;", "<"), ("&gt;", ">"),
            ("&quot;", "\""), ("&#39;", "'"), ("&apos;", "'"),
            ("&nbsp;", " "), ("&#x27;", "'"), ("&#x2F;", "/")
        ]
        for (entity, char) in entities {
            text = text.replacingOccurrences(of: entity, with: char)
        }
        // Collapse whitespace
        text = text.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression).trimmingCharacters(in: .whitespacesAndNewlines)
        return text
    }

    // MARK: - Sentence Splitting

    /// Split text into sentences using linguistic tagger.
    private func splitSentences(_ text: String) -> [String] {
        var sentences: [String] = []
        let range = text.startIndex..<text.endIndex
        text.enumerateSubstrings(in: range, options: [.bySentences, .localized]) { substring, _, _, _ in
            if let sentence = substring?.trimmingCharacters(in: .whitespacesAndNewlines), !sentence.isEmpty {
                sentences.append(sentence)
            }
        }
        // Fallback: split on sentence-ending punctuation if linguistic splitter returns nothing
        if sentences.isEmpty {
            sentences = text.components(separatedBy: CharacterSet(charactersIn: ".!?"))
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
        }
        return sentences
    }

    // MARK: - Tokenization

    /// Tokenize text into lowercased words, filtering stop words and short terms.
    /// Delegates to `TextAnalyzer.shared` for consistent tokenization across modules.
    private func tokenize(_ text: String, minLength: Int = TextAnalyzer.defaultMinTermLength) -> [String] {
        return TextAnalyzer.shared.tokenize(text, minLength: minLength)
    }

    // MARK: - TF-IDF

    /// Compute term frequency for a list of tokens.
    private func termFrequency(_ tokens: [String]) -> [String: Double] {
        guard !tokens.isEmpty else { return [:] }
        var counts: [String: Int] = [:]
        for token in tokens {
            counts[token, default: 0] += 1
        }
        let total = Double(tokens.count)
        return counts.mapValues { Double($0) / total }
    }

    /// Compute inverse document frequency across sentence documents.
    private func inverseDocumentFrequency(_ sentenceTokens: [[String]]) -> [String: Double] {
        let n = Double(sentenceTokens.count)
        guard n > 0 else { return [:] }
        var docCounts: [String: Int] = [:]
        for tokens in sentenceTokens {
            let unique = Set(tokens)
            for word in unique {
                docCounts[word, default: 0] += 1
            }
        }
        return docCounts.mapValues { log(n / Double($0)) + 1.0 }
    }

    // MARK: - Summarize

    /// Generate an extractive summary of the given text.
    ///
    /// - Parameters:
    ///   - text: The article body (plain text or HTML).
    ///   - title: Optional article title for relevance boosting.
    ///   - config: Summary configuration.
    /// - Returns: A `SummaryResult`, or `nil` if the text is too short.
    func summarize(_ text: String, title: String? = nil, config: SummaryConfig = .default) -> SummaryResult? {
        let cleanText = stripHTML(text)
        guard !cleanText.isEmpty else { return nil }

        let sentences = splitSentences(cleanText)
        guard sentences.count >= 2 else { return nil }

        // Tokenize each sentence
        let sentenceTokens = sentences.map { tokenize($0) }

        // Filter out sentences that are too short
        let validIndices = sentenceTokens.enumerated()
            .filter { $0.element.count >= config.minSentenceWords }
            .map { $0.offset }

        guard !validIndices.isEmpty else { return nil }

        // TF-IDF
        let idf = inverseDocumentFrequency(sentenceTokens)

        // Score each sentence
        var scores: [(index: Int, score: Double)] = []

        // Title keywords for boosting
        let titleKeywords: Set<String>
        if let title = title {
            titleKeywords = Set(tokenize(title, minLength: 2))
        } else {
            titleKeywords = []
        }

        // Determine first paragraph boundary (first sentence)
        let firstParagraphEnd = min(1, sentences.count - 1)

        for i in validIndices {
            let tokens = sentenceTokens[i]
            let tf = termFrequency(tokens)

            // TF-IDF score
            var score = 0.0
            for (term, freq) in tf {
                let idfVal = idf[term] ?? 1.0
                score += freq * idfVal
            }

            // Title boost
            if !titleKeywords.isEmpty {
                let titleOverlap = Double(Set(tokens).intersection(titleKeywords).count)
                let titleRatio = titleOverlap / Double(titleKeywords.count)
                score *= (1.0 + titleRatio * (config.titleBoost - 1.0))
            }

            // Position boost (first sentence)
            if i <= firstParagraphEnd {
                score *= config.positionBoost
            }

            scores.append((index: i, score: score))
        }

        // Sort by score descending
        scores.sort { $0.score > $1.score }

        // Determine how many sentences to include
        let byRatio = max(1, Int(ceil(Double(sentences.count) * config.ratio)))
        let targetCount = min(config.maxSentences, byRatio, validIndices.count)

        // Select top sentences
        let selected = Array(scores.prefix(targetCount))

        // Ranked sentences for result
        let ranked = scores.map { (sentence: sentences[$0.index], score: $0.score) }

        // Re-order selected by original position for natural reading
        let orderedSelected = selected.sorted { $0.index < $1.index }
        let summaryText = orderedSelected.map { sentences[$0.index] }.joined(separator: " ")

        // Top keywords
        var globalTFIDF: [String: Double] = [:]
        for i in validIndices {
            let tf = termFrequency(sentenceTokens[i])
            for (term, freq) in tf {
                let idfVal = idf[term] ?? 1.0
                globalTFIDF[term, default: 0] += freq * idfVal
            }
        }
        let topKeywords = globalTFIDF.sorted { $0.value > $1.value }
            .prefix(10)
            .map { (word: $0.key, score: $0.value) }

        let originalLength = cleanText.count
        let summaryLength = summaryText.count
        let compression = originalLength > 0 ? Double(summaryLength) / Double(originalLength) : 0

        return SummaryResult(
            summary: summaryText,
            rankedSentences: ranked,
            originalSentenceCount: sentences.count,
            summarySentenceCount: targetCount,
            compressionRatio: compression,
            topKeywords: topKeywords
        )
    }

    // MARK: - Batch Summarize

    /// Summarize multiple articles at once.
    func batchSummarize(_ articles: [(text: String, title: String?)],
                        config: SummaryConfig = .default) -> [SummaryResult?] {
        return articles.map { summarize($0.text, title: $0.title, config: config) }
    }

    // MARK: - Multi-Article Summary

    /// Generate a combined summary across multiple article texts.
    /// Useful for feed digests — picks the best sentences from all articles combined.
    func multiArticleSummary(_ articles: [(text: String, title: String?)],
                             maxSentences: Int = 5) -> SummaryResult? {
        let combined = articles
            .map { stripHTML($0.text) }
            .filter { !$0.isEmpty }
            .joined(separator: " ")

        guard !combined.isEmpty else { return nil }

        let config = SummaryConfig(maxSentences: maxSentences, ratio: 0.1, minSentenceWords: 4)
        return summarize(combined, config: config)
    }
}
