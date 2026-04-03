//
//  ArticleSummarizer.swift
//  FeedReader
//
//  Extractive text summarizer using TF-IDF scoring with title boosting,
//  position boosting, and sentence-length filtering. Produces ranked
//  sentence lists, top keywords, and compression metrics.
//

import Foundation

// MARK: - SummaryConfig

/// Configuration for summarization behavior.
struct SummaryConfig: Equatable {
    /// Maximum number of sentences in the summary.
    var maxSentences: Int
    /// Target ratio of summary sentences to total (0.0–1.0). Actual count
    /// is `min(maxSentences, ceil(totalSentences * ratio))`.
    var ratio: Double
    /// Multiplier applied to sentence scores that share words with the title.
    var titleBoost: Double
    /// Multiplier that favors earlier sentences (decays linearly).
    var positionBoost: Double
    /// Minimum word count for a sentence to be considered.
    var minSentenceWords: Int
    /// Maximum characters for the summary text (0 = unlimited).
    var maxCharacters: Int

    init(maxSentences: Int = 3,
         ratio: Double = 0.3,
         titleBoost: Double = 1.5,
         positionBoost: Double = 1.2,
         minSentenceWords: Int = 4,
         maxCharacters: Int = 0) {
        self.maxSentences = Swift.max(maxSentences, 1)
        self.ratio = Swift.min(Swift.max(ratio, 0.0), 1.0)
        self.titleBoost = Swift.max(titleBoost, 0.0)
        self.positionBoost = Swift.max(positionBoost, 0.0)
        self.minSentenceWords = Swift.max(minSentenceWords, 1)
        self.maxCharacters = Swift.max(maxCharacters, 0)
    }

    /// Default configuration.
    static let `default` = SummaryConfig()

    /// Brief configuration with tighter limits.
    static let brief = SummaryConfig(maxSentences: 2, ratio: 0.2, maxCharacters: 280)
}

// MARK: - SummaryResult

/// Result of summarizing an article.
struct SummaryResult {
    /// The summary text (selected sentences joined).
    let summary: String
    /// Number of sentences in the summary.
    let summarySentenceCount: Int
    /// Total sentence count in the original text.
    let originalSentenceCount: Int
    /// Ratio of summary length to original length (by character count).
    let compressionRatio: Double
    /// All sentences ranked by score (descending).
    let rankedSentences: [(sentence: String, score: Double)]
    /// Top keywords extracted by TF-IDF score.
    let topKeywords: [(word: String, score: Double)]
}

// MARK: - ArticleSummarizer

/// Singleton extractive summarizer using TF-IDF with positional and title boosts.
///
/// Delegates tokenization, stop-word filtering, and HTML stripping to the
/// shared `TextAnalyzer` to avoid duplicating those utilities.
class ArticleSummarizer {

    static let shared = ArticleSummarizer()

    private let textAnalyzer = TextAnalyzer.shared

    // MARK: - Public API

    /// Summarize a single text, optionally boosted by a title.
    func summarize(_ text: String, title: String? = nil, config: SummaryConfig = .default) -> SummaryResult? {
        let cleaned = textAnalyzer.stripHTML(text).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else { return nil }

        let sentences = splitSentences(cleaned)
        let validSentences = sentences.filter { wordCount($0) >= config.minSentenceWords }
        guard validSentences.count >= 2 else { return nil }

        // Tokenize each sentence
        let tokenized = validSentences.map { textAnalyzer.tokenize($0, minLength: 2) }

        // Build document frequency map
        var docFreq: [String: Int] = [:]
        for tokens in tokenized {
            for word in Set(tokens) {
                docFreq[word, default: 0] += 1
            }
        }

        let n = Double(validSentences.count)
        let titleWords = title.map { textAnalyzer.tokenize($0, minLength: 2) } ?? []

        // Score each sentence
        var scored: [(index: Int, sentence: String, score: Double)] = []

        for (i, tokens) in tokenized.enumerated() {
            guard !tokens.isEmpty else { continue }

            // TF-IDF score
            var tfIdfSum = 0.0
            var termFreq: [String: Int] = [:]
            for t in tokens { termFreq[t, default: 0] += 1 }

            for (term, count) in termFreq {
                let tf = Double(count) / Double(tokens.count)
                let idf = log(n / Double(docFreq[term] ?? 1))
                tfIdfSum += tf * idf
            }

            var score = tfIdfSum

            // Title boost
            if !titleWords.isEmpty {
                let overlap = Set(tokens).intersection(Set(titleWords)).count
                if overlap > 0 {
                    score *= config.titleBoost * Double(overlap)
                }
            }

            // Position boost (linear decay)
            let positionFactor = 1.0 + config.positionBoost * (1.0 - Double(i) / n)
            score *= positionFactor

            scored.append((i, validSentences[i], score))
        }

        // Sort by score descending for ranking
        let ranked = scored.sorted { $0.score > $1.score }

        // Determine how many sentences to pick
        let ratioCount = Int(ceil(Double(validSentences.count) * config.ratio))
        let targetCount = min(config.maxSentences, ratioCount)
        let pickCount = min(targetCount, ranked.count)

        // Pick top sentences, then restore original order
        let selected = ranked.prefix(pickCount).sorted { $0.index < $1.index }

        var summaryText = selected.map { $0.sentence }.joined(separator: " ")

        // Trim to maxCharacters if set
        if config.maxCharacters > 0 && summaryText.count > config.maxCharacters {
            // Trim to last complete sentence within budget
            var trimmed = ""
            for s in selected {
                let candidate = trimmed.isEmpty ? s.sentence : trimmed + " " + s.sentence
                if candidate.count <= config.maxCharacters {
                    trimmed = candidate
                } else {
                    break
                }
            }
            if !trimmed.isEmpty { summaryText = trimmed }
        }

        // Top keywords
        var globalTF: [String: Double] = [:]
        let allTokens = tokenized.flatMap { $0 }
        let totalTokenCount = Double(allTokens.count)
        for t in allTokens { globalTF[t, default: 0] += 1.0 }
        var keywords: [(String, Double)] = []
        for (term, count) in globalTF {
            let tf = count / totalTokenCount
            let idf = log(n / Double(docFreq[term] ?? 1))
            keywords.append((term, tf * idf))
        }
        keywords.sort { $0.1 > $1.1 }
        let topKeywords = Array(keywords.prefix(10))

        let compressionRatio = cleaned.isEmpty ? 0.0 : Double(summaryText.count) / Double(cleaned.count)

        return SummaryResult(
            summary: summaryText,
            summarySentenceCount: selected.count,
            originalSentenceCount: validSentences.count,
            compressionRatio: compressionRatio,
            rankedSentences: ranked.map { ($0.sentence, $0.score) },
            topKeywords: topKeywords.map { (word: $0.0, score: $0.1) }
        )
    }

    /// Summarize multiple texts at once.
    func batchSummarize(_ articles: [(text: String, title: String?)], config: SummaryConfig = .default) -> [SummaryResult?] {
        return articles.map { summarize($0.text, title: $0.title, config: config) }
    }

    /// Generate a combined summary across multiple articles.
    func multiArticleSummary(_ articles: [(text: String, title: String?)], maxSentences: Int = 3, config: SummaryConfig = .default) -> SummaryResult? {
        let combined = articles.map { textAnalyzer.stripHTML($0.text).trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        guard !combined.isEmpty else { return nil }
        let mergedText = combined.joined(separator: " ")
        let mergedTitle = articles.compactMap { $0.title }.joined(separator: " ")
        var cfg = config
        cfg.maxSentences = maxSentences
        return summarize(mergedText, title: mergedTitle.isEmpty ? nil : mergedTitle, config: cfg)
    }

    // MARK: - Text Processing

    /// Split text into sentences, handling common abbreviations.
    func splitSentences(_ text: String) -> [String] {
        let abbreviations = ["dr", "mr", "mrs", "ms", "prof", "sr", "jr", "st",
                             "ave", "inc", "ltd", "corp", "vs", "etc", "al", "eg", "ie"]
        // Replace abbreviation periods with placeholder
        var processed = text
        for abbr in abbreviations {
            let pattern = "\\b\(abbr)\\."
            if let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) {
                processed = regex.stringByReplacingMatches(
                    in: processed,
                    range: NSRange(processed.startIndex..., in: processed),
                    withTemplate: "\(abbr)§"
                )
            }
        }

        // Split on sentence-ending punctuation
        let parts = processed.components(separatedBy: CharacterSet(charactersIn: ".!?"))
            .map { $0.replacingOccurrences(of: "§", with: ".").trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        return parts
    }

    /// Count words in a string.
    private func wordCount(_ text: String) -> Int {
        return text.components(separatedBy: .whitespaces).filter { !$0.isEmpty }.count
    }
}
