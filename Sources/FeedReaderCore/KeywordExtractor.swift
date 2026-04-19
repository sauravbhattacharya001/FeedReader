//
//  KeywordExtractor.swift
//  FeedReaderCore
//
//  Extracts top keywords from article text using term-frequency analysis
//  with common stop-word filtering. Useful for generating tags, topic
//  summaries, or grouping related articles.
//

import Foundation

/// Extracts meaningful keywords from text content.
///
/// Uses term-frequency analysis with stop-word filtering to surface
/// the most relevant words from article bodies or titles.
///
/// ## Usage
/// ```swift
/// let extractor = KeywordExtractor()
/// let keywords = extractor.extractKeywords(from: "Apple announced a new iPhone today...")
/// // ["apple", "iphone", "announced"]
///
/// // Extract from an RSSStory
/// let tags = extractor.extractTags(from: story, count: 5)
/// // ["climate", "emissions", "carbon", "policy", "renewable"]
/// ```
public class KeywordExtractor {

    // MARK: - Configuration

    /// Minimum word length to consider as a keyword.
    public var minimumWordLength: Int = 3

    /// Maximum number of keywords to return by default.
    public var defaultCount: Int = 5

    // Stop words are provided by TextUtilities.stopWords

    // MARK: - Initialization

    public init() {}

    // MARK: - Public API

    /// Extracts top keywords from raw text.
    /// - Parameters:
    ///   - text: The input text to analyze.
    ///   - count: Maximum number of keywords to return.
    /// - Returns: Array of keywords sorted by frequency (most frequent first).
    public func extractKeywords(from text: String, count: Int? = nil) -> [String] {
        let limit = count ?? defaultCount
        let frequencies = computeFrequencies(text)

        return frequencies
            .sorted { $0.value > $1.value }
            .prefix(limit)
            .map { $0.key }
    }

    /// Extracts keywords from an RSS story, combining title and body.
    /// Title words are weighted 3× to reflect their importance.
    /// - Parameters:
    ///   - story: The RSS story to extract keywords from.
    ///   - count: Maximum number of keywords to return.
    /// - Returns: Array of keyword strings.
    public func extractTags(from story: RSSStory, count: Int? = nil) -> [String] {
        let limit = count ?? defaultCount

        // Weight title words more heavily
        var frequencies = computeFrequencies(story.body)
        let titleFreqs = computeFrequencies(story.title)
        for (word, freq) in titleFreqs {
            frequencies[word, default: 0] += freq * 3
        }

        return frequencies
            .sorted { $0.value > $1.value }
            .prefix(limit)
            .map { $0.key }
    }

    /// Extracts keywords from multiple stories, finding common themes.
    ///
    /// Uses document-frequency (DF) scoring: a word is a "theme" if it
    /// appears in multiple stories. Previously this called `extractKeywords`
    /// per story (which sorts all frequencies to pick the top-20), wasting
    /// work since we only need the *set* of significant words per document.
    /// Now we compute the significant-word set directly, skipping the
    /// frequency sort entirely — O(W) per story instead of O(W log W).
    ///
    /// - Parameters:
    ///   - stories: Array of RSS stories.
    ///   - count: Maximum number of keywords to return.
    /// - Returns: Array of keywords representing common themes across all stories.
    public func extractThemes(from stories: [RSSStory], count: Int? = nil) -> [String] {
        let limit = count ?? defaultCount
        var combined: [String: Int] = [:]
        combined.reserveCapacity(200)

        // Count in how many stories each significant word appears (document frequency).
        // Using extractSignificantWords + Set avoids the full frequency-count +
        // sort pipeline that extractKeywords performs — we only need presence, not rank.
        for story in stories {
            let words = TextUtilities.extractSignificantWords(
                from: "\(story.title) \(story.body)",
                minimumLength: minimumWordLength
            )
            let uniqueWords = Set(words)
            for word in uniqueWords {
                combined[word, default: 0] += 1
            }
        }

        // Filter: keyword must appear in at least 2 stories to be a theme
        let minDocs = min(2, stories.count)
        return combined
            .filter { $0.value >= minDocs }
            .sorted { $0.value > $1.value }
            .prefix(limit)
            .map { $0.key }
    }

    // MARK: - Private

    /// Tokenizes text and computes word frequencies, filtering stop words.
    /// Delegates to `TextUtilities.computeWordFrequencies` to avoid
    /// duplicating the tokenization and stop-word filtering logic.
    private func computeFrequencies(_ text: String) -> [String: Int] {
        return TextUtilities.computeWordFrequencies(from: text, minimumLength: minimumWordLength)
    }
}
