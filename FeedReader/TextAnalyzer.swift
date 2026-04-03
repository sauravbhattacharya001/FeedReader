//
//  TextAnalyzer.swift
//  FeedReader
//
//  Shared text analysis utilities — tokenization, stop word filtering,
//  and keyword extraction. Consolidates logic previously duplicated
//  across ArticleRecommendationEngine and ArticleSimilarityManager.
//

import Foundation

/// Shared text analysis utilities for keyword extraction and tokenization.
///
/// Both `ArticleRecommendationEngine` and `ArticleSimilarityManager`
/// need consistent tokenization. This class provides a single canonical
/// implementation, ensuring that the same text produces identical tokens
/// regardless of which module processes it.
class TextAnalyzer {

    // MARK: - Singleton

    static let shared = TextAnalyzer()

    // MARK: - Constants

    /// Default minimum term length for tokenization.
    static let defaultMinTermLength = 3

    /// Common English stop words filtered during tokenization.
    /// This is the canonical list — both recommendation and similarity
    /// engines delegate here instead of maintaining their own copies.
    static let stopWords: Set<String> = [
        // Articles & determiners
        "a", "an", "the", "this", "that", "these", "those",
        // Pronouns
        "i", "you", "he", "she", "we", "they", "me", "him", "her", "us",
        "them", "my", "your", "his", "our", "their", "its",
        // Prepositions
        "in", "on", "at", "to", "for", "of", "with", "by", "from", "into",
        "about", "above", "after", "around", "before", "between", "through",
        "under", "upon", "over", "out", "up",
        // Conjunctions
        "and", "or", "but", "nor", "so", "if", "then", "than", "as",
        // Be verbs
        "is", "are", "was", "were", "be", "been", "being",
        // Have verbs
        "have", "has", "had",
        // Do verbs
        "do", "does", "did", "done",
        // Modal verbs
        "will", "would", "could", "should", "shall", "may", "might",
        "must", "can",
        // Common verbs & adverbs
        "not", "no", "just", "very", "too", "also", "again", "still",
        "now", "only", "even", "back", "here", "there", "where",
        "when", "how", "what", "which", "who", "whom", "why",
        // Common adjectives & words
        "all", "each", "every", "both", "few", "more", "most", "other",
        "some", "such", "any", "same", "own", "new", "first", "last",
        "long", "high", "good", "great", "many", "much",
        // High-frequency filler
        "get", "got", "give", "going", "come", "take", "make", "know",
        "look", "like", "need", "want", "use", "used", "using",
        "say", "says", "said", "tell", "show", "think", "find",
        "work", "well", "way", "time", "year", "part", "people",
        "state", "world", "two", "open", "while", "because",
        "it",
    ]

    // MARK: - Tokenization

    /// Tokenize text into lowercase terms, filtering stop words and short terms.
    ///
    /// Splits on non-alphanumeric boundaries, lowercases, removes stop words,
    /// and filters by minimum length. This is the canonical tokenization
    /// used by both similarity and recommendation engines.
    ///
    /// - Parameters:
    ///   - text: The input text to tokenize.
    ///   - minLength: Minimum term length to keep (default: 3).
    /// - Returns: Array of filtered, lowercased tokens (may contain duplicates).
    func tokenize(_ text: String, minLength: Int = TextAnalyzer.defaultMinTermLength) -> [String] {
        let lowered = text.lowercased()
        return lowered
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { token in
                token.count >= minLength &&
                !TextAnalyzer.stopWords.contains(token)
            }
    }

    /// Extract unique keywords from text, preserving first-occurrence order.
    ///
    /// - Parameters:
    ///   - text: The input text.
    ///   - minLength: Minimum keyword length (default: 3).
    /// - Returns: Deduplicated keywords in order of first appearance.
    func extractKeywords(from text: String, minLength: Int = TextAnalyzer.defaultMinTermLength) -> [String] {
        let tokens = tokenize(text, minLength: minLength)
        var seen = Set<String>()
        return tokens.filter { seen.insert($0).inserted }
    }

    /// Compute normalized term frequency vector for a list of tokens.
    ///
    /// - Parameter tokens: Pre-tokenized terms.
    /// - Returns: Dictionary mapping each term to its normalized frequency (0.0–1.0).
    func computeTermFrequency(_ tokens: [String]) -> [String: Double] {
        guard !tokens.isEmpty else { return [:] }
        var counts: [String: Int] = [:]
        for token in tokens {
            counts[token, default: 0] += 1
        }
        let maxCount = Double(counts.values.max() ?? 1)
        return counts.mapValues { Double($0) / maxCount }
    }

    // MARK: - HTML Processing

    /// Strip HTML tags and decode common entities from text.
    ///
    /// Removes `<script>` and `<style>` blocks entirely, strips remaining
    /// tags, decodes the six most common HTML entities, and collapses
    /// whitespace. This is the canonical implementation — other modules
    /// should delegate here instead of maintaining private copies.
    ///
    /// - Parameter text: Raw text potentially containing HTML markup.
    /// - Returns: Plain text with tags removed and entities decoded.
    func stripHTML(_ text: String) -> String {
        // Remove <script> and <style> blocks entirely
        var result = text.replacingOccurrences(
            of: "<(script|style)[^>]*>[\\s\\S]*?</\\1>",
            with: " ",
            options: [.regularExpression, .caseInsensitive]
        )
        // Remove all remaining tags
        result = result.replacingOccurrences(
            of: "<[^>]+>",
            with: " ",
            options: .regularExpression
        )
        // Decode common HTML entities
        result = result.replacingOccurrences(of: "&amp;", with: "&")
        result = result.replacingOccurrences(of: "&lt;", with: "<")
        result = result.replacingOccurrences(of: "&gt;", with: ">")
        result = result.replacingOccurrences(of: "&quot;", with: "\"")
        result = result.replacingOccurrences(of: "&#39;", with: "'")
        result = result.replacingOccurrences(of: "&nbsp;", with: " ")
        // Collapse whitespace
        result = result.replacingOccurrences(
            of: "\\s+",
            with: " ",
            options: .regularExpression
        ).trimmingCharacters(in: .whitespacesAndNewlines)
        return result
    }
}
