//
//  ArticleWordCloudGenerator.swift
//  FeedReader
//
//  Word cloud data generator using TF-IDF scoring across articles.
//  Produces ranked word entries suitable for rendering word clouds.
//

import Foundation

/// A single word cloud entry with its computed weight and metadata.
struct WordCloudEntry: Codable, Equatable {
    /// The word/term.
    let word: String
    /// TF-IDF score (higher = more distinctive/important).
    let score: Double
    /// Raw frequency across all matched articles.
    let frequency: Int
    /// Number of articles containing this word.
    let documentCount: Int
    /// Normalized size (0.0–1.0) for rendering.
    let normalizedSize: Double
}

/// Configuration for word cloud generation.
struct WordCloudConfig {
    /// Maximum number of words in the cloud.
    var maxWords: Int = 50
    /// Minimum document frequency — words must appear in at least this many articles.
    var minDocumentFrequency: Int = 2
    /// Maximum document frequency ratio (0.0–1.0) — words in more than this fraction of docs are excluded.
    var maxDocumentFrequencyRatio: Double = 0.8
    /// Minimum word length.
    var minWordLength: Int = 3
    /// Optional feed name filter — only include articles from this feed.
    var feedFilter: String? = nil
    /// Optional time window — only include articles read/added after this date.
    var sinceDate: Date? = nil

    static let `default` = WordCloudConfig()
}

/// Generates word cloud data from a collection of articles using TF-IDF scoring.
///
/// TF-IDF (Term Frequency-Inverse Document Frequency) highlights words that are
/// frequent within articles but distinctive across the corpus - surfacing the
/// most characteristic vocabulary rather than the most common words.
class ArticleWordCloudGenerator {

    // MARK: - Types

    private struct DocumentStats {
        let tokens: [String]
        let termFrequency: [String: Double]
    }

    // MARK: - Properties

    private let textAnalyzer: TextAnalyzer

    // MARK: - Initialization

    init(textAnalyzer: TextAnalyzer = .shared) {
        self.textAnalyzer = textAnalyzer
    }

    // MARK: - Generation

    /// Generate word cloud entries from articles.
    ///
    /// - Parameters:
    ///   - articles: Array of (title, body, feedName, date) tuples.
    ///   - config: Generation configuration.
    /// - Returns: Array of `WordCloudEntry` sorted by score descending.
    func generate(
        from articles: [(title: String, body: String, feedName: String?, date: Date?)],
        config: WordCloudConfig = .default
    ) -> [WordCloudEntry] {
        let filtered = articles.filter { article in
            if let feedFilter = config.feedFilter,
               article.feedName?.lowercased() != feedFilter.lowercased() {
                return false
            }
            if let sinceDate = config.sinceDate,
               let articleDate = article.date,
               articleDate < sinceDate {
                return false
            }
            return true
        }

        guard filtered.count >= 1 else { return [] }

        let docStats: [DocumentStats] = filtered.map { article in
            let titleTokens = textAnalyzer.tokenize(article.title, minLength: config.minWordLength)
            let bodyTokens = textAnalyzer.tokenize(article.body, minLength: config.minWordLength)
            let combined = titleTokens + titleTokens + bodyTokens
            let tf = textAnalyzer.computeTermFrequency(combined)
            return DocumentStats(tokens: combined, termFrequency: tf)
        }

        let totalDocs = Double(docStats.count)

        var documentFrequency: [String: Int] = [:]
        for doc in docStats {
            let uniqueTerms = Set(doc.tokens)
            for term in uniqueTerms {
                documentFrequency[term, default: 0] += 1
            }
        }

        var globalFrequency: [String: Int] = [:]
        for doc in docStats {
            for token in doc.tokens {
                globalFrequency[token, default: 0] += 1
            }
        }

        var tfidfScores: [String: Double] = [:]
        let maxDfCount = Int(config.maxDocumentFrequencyRatio * totalDocs)

        for (term, df) in documentFrequency {
            if df < config.minDocumentFrequency { continue }
            if df > maxDfCount && maxDfCount > 0 { continue }

            let idf = log(totalDocs / Double(df))

            var sumTf = 0.0
            for doc in docStats {
                if let tf = doc.termFrequency[term] {
                    sumTf += tf
                }
            }
            let avgTf = sumTf / Double(df)
            tfidfScores[term] = avgTf * idf
        }

        let sorted = tfidfScores.sorted { $0.value > $1.value }
        let topWords = sorted.prefix(config.maxWords)

        guard let maxScore = topWords.first?.value, maxScore > 0 else { return [] }

        return topWords.map { (word, score) in
            WordCloudEntry(
                word: word,
                score: round(score * 1000) / 1000,
                frequency: globalFrequency[word] ?? 0,
                documentCount: documentFrequency[word] ?? 0,
                normalizedSize: round((score / maxScore) * 1000) / 1000
            )
        }
    }

    // MARK: - Per-Feed Breakdown

    /// Generate separate word clouds for each feed.
    func generatePerFeed(
        from articles: [(title: String, body: String, feedName: String?, date: Date?)],
        config: WordCloudConfig = .default
    ) -> [String: [WordCloudEntry]] {
        let feedNames = Set(articles.compactMap { $0.feedName })
        var result: [String: [WordCloudEntry]] = [:]

        for feed in feedNames {
            var feedConfig = config
            feedConfig.feedFilter = feed
            feedConfig.minDocumentFrequency = 1
            let entries = generate(from: articles, config: feedConfig)
            if !entries.isEmpty {
                result[feed] = entries
            }
        }

        return result
    }

    // MARK: - Comparative Cloud

    /// Generate a comparative word cloud showing words distinctive to one feed vs others.
    func generateComparative(
        from articles: [(title: String, body: String, feedName: String?, date: Date?)],
        maxWordsPerFeed: Int = 20
    ) -> [String: [WordCloudEntry]] {
        let feedNames = Set(articles.compactMap { $0.feedName })
        guard feedNames.count >= 2 else { return [:] }

        var feedCorpus: [String: [String]] = [:]
        for article in articles {
            guard let feed = article.feedName else { continue }
            let tokens = textAnalyzer.tokenize(article.title) + textAnalyzer.tokenize(article.body)
            feedCorpus[feed, default: []].append(contentsOf: tokens)
        }

        let totalFeeds = Double(feedCorpus.count)

        var feedDocFreq: [String: Int] = [:]
        for (_, tokens) in feedCorpus {
            let unique = Set(tokens)
            for term in unique {
                feedDocFreq[term, default: 0] += 1
            }
        }

        var result: [String: [WordCloudEntry]] = [:]

        for (feed, tokens) in feedCorpus {
            guard !tokens.isEmpty else { continue }

            var counts: [String: Int] = [:]
            for t in tokens { counts[t, default: 0] += 1 }
            let maxCount = Double(counts.values.max() ?? 1)

            var scores: [(String, Double, Int)] = []
            for (term, count) in counts {
                let df = feedDocFreq[term] ?? 1
                let idf = log(totalFeeds / Double(df))
                let tf = Double(count) / maxCount
                let score = tf * idf
                if score > 0 {
                    scores.append((term, score, count))
                }
            }

            scores.sort { $0.1 > $1.1 }
            let top = scores.prefix(maxWordsPerFeed)

            guard let maxScore = top.first?.1, maxScore > 0 else { continue }

            result[feed] = top.map { (word, score, freq) in
                WordCloudEntry(
                    word: word,
                    score: round(score * 1000) / 1000,
                    frequency: freq,
                    documentCount: feedDocFreq[word] ?? 0,
                    normalizedSize: round((score / maxScore) * 1000) / 1000
                )
            }
        }

        return result
    }

    // MARK: - Export

    /// Export word cloud entries to JSON data.
    func exportJSON(_ entries: [WordCloudEntry]) -> Data? {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try? encoder.encode(entries)
    }

    /// Generate a text report of word cloud data.
    func textReport(_ entries: [WordCloudEntry], title: String = "Word Cloud") -> String {
        guard !entries.isEmpty else { return "\(title)\n(no data)\n" }

        var lines: [String] = []
        lines.append(title)
        lines.append(String(repeating: "=", count: title.count))
        lines.append("")
        lines.append(String(format: "%-20s %8s %6s %5s %5s", "Word", "Score", "Freq", "Docs", "Size"))
        lines.append(String(repeating: "-", count: 50))

        for entry in entries {
            let bar = String(repeating: "█", count: max(1, Int(entry.normalizedSize * 20)))
            lines.append(String(format: "%-20s %8.3f %6d %5d  %@",
                                entry.word.prefix(20),
                                entry.score,
                                entry.frequency,
                                entry.documentCount,
                                bar))
        }

        lines.append("")
        lines.append("Total words: \(entries.count)")
        lines.append("Top word: \"\(entries[0].word)\" (score: \(entries[0].score))")
        return lines.joined(separator: "\n")
    }
}
