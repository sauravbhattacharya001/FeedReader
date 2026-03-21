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

    // MARK: - Stop Words

    /// Common English stop words to exclude from keyword extraction.
    private static let stopWords: Set<String> = [
        "the", "a", "an", "and", "or", "but", "in", "on", "at", "to",
        "for", "of", "with", "by", "from", "is", "it", "as", "was",
        "are", "be", "been", "being", "have", "has", "had", "do", "does",
        "did", "will", "would", "could", "should", "may", "might", "can",
        "shall", "this", "that", "these", "those", "i", "you", "he", "she",
        "we", "they", "me", "him", "her", "us", "them", "my", "your",
        "his", "its", "our", "their", "what", "which", "who", "whom",
        "how", "when", "where", "why", "all", "each", "every", "both",
        "few", "more", "most", "other", "some", "such", "no", "nor",
        "not", "only", "own", "same", "so", "than", "too", "very",
        "just", "about", "above", "after", "again", "also", "any",
        "because", "before", "between", "during", "if", "into", "new",
        "now", "over", "then", "there", "through", "under", "up", "out",
        "said", "says", "say", "get", "got", "like", "make", "made",
        "many", "much", "one", "two", "first", "also", "well", "way",
        "even", "back", "still", "since", "while", "here", "off",
        "however", "yet", "per", "via", "around", "among", "upon",
    ]

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
    /// - Parameters:
    ///   - stories: Array of RSS stories.
    ///   - count: Maximum number of keywords to return.
    /// - Returns: Array of keywords representing common themes across all stories.
    public func extractThemes(from stories: [RSSStory], count: Int? = nil) -> [String] {
        let limit = count ?? defaultCount
        var combined: [String: Int] = [:]

        // Count in how many stories each keyword appears (document frequency)
        for story in stories {
            let storyKeywords = Set(extractKeywords(from: "\(story.title) \(story.body)", count: 20))
            for keyword in storyKeywords {
                combined[keyword, default: 0] += 1
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
    private func computeFrequencies(_ text: String) -> [String: Int] {
        let lowered = text.lowercased()
        var frequencies: [String: Int] = [:]

        lowered.enumerateSubstrings(in: lowered.startIndex..., options: .byWords) { word, _, _, _ in
            guard let word = word,
                  word.count >= self.minimumWordLength,
                  !KeywordExtractor.stopWords.contains(word),
                  !word.allSatisfy({ $0.isNumber }) else { return }
            frequencies[word, default: 0] += 1
        }

        return frequencies
    }
}
