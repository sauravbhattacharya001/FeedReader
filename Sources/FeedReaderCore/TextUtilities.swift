//
//  TextUtilities.swift
//  FeedReaderCore
//
//  Shared text processing utilities used across multiple modules.
//  Centralizes stop words, character escaping, and word counting
//  to eliminate duplication and ensure consistent behavior.
//

import Foundation

/// Shared text processing utilities for the FeedReaderCore library.
public enum TextUtilities {

    // MARK: - Stop Words

    /// Common English stop words excluded from keyword extraction and quiz generation.
    /// Maintained in a single location to avoid divergence between modules.
    public static let stopWords: Set<String> = [
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
        "were",
    ]

    // MARK: - Character Escaping

    /// Escapes XML special characters (`&`, `<`, `>`, `"`, `'`) in a single pass.
    ///
    /// Suitable for both XML attribute values and text content. Uses a fast
    /// path that returns the input unchanged when no special characters are
    /// present, avoiding any allocation.
    ///
    /// - Parameter string: The raw string to escape.
    /// - Returns: The XML-safe string.
    public static func escapeXML(_ string: String) -> String {
        guard string.contains(where: { $0 == "&" || $0 == "<" || $0 == ">" || $0 == "\"" || $0 == "'" }) else {
            return string
        }

        var result = ""
        result.reserveCapacity(string.count + string.count / 8)
        for ch in string {
            switch ch {
            case "&":  result += "&amp;"
            case "<":  result += "&lt;"
            case ">":  result += "&gt;"
            case "\"": result += "&quot;"
            case "'":  result += "&apos;"
            default:   result.append(ch)
            }
        }
        return result
    }

    /// Escapes HTML special characters (`&`, `<`, `>`, `"`) in a single pass.
    ///
    /// Unlike `escapeXML`, does not escape single quotes — HTML attributes
    /// are conventionally double-quoted, so `'` is left unescaped for
    /// readability in generated HTML output.
    ///
    /// - Parameter string: The raw string to escape.
    /// - Returns: The HTML-safe string.
    public static func escapeHTML(_ string: String) -> String {
        guard string.contains(where: { $0 == "&" || $0 == "<" || $0 == ">" || $0 == "\"" }) else {
            return string
        }

        var result = ""
        result.reserveCapacity(string.count + string.count / 8)
        for ch in string {
            switch ch {
            case "&":  result += "&amp;"
            case "<":  result += "&lt;"
            case ">":  result += "&gt;"
            case "\"": result += "&quot;"
            default:   result.append(ch)
            }
        }
        return result
    }

    // MARK: - Word Counting

    /// Counts words in a text string by splitting on whitespace.
    /// - Parameter text: The input text.
    /// - Returns: Number of whitespace-delimited, non-empty tokens.
    public static func countWords(_ text: String) -> Int {
        return text.components(separatedBy: .whitespacesAndNewlines).filter { !$0.isEmpty }.count
    }

    /// Estimates reading time in minutes assuming 200 words per minute.
    /// - Parameter wordCount: Number of words.
    /// - Returns: Estimated minutes (minimum 1).
    public static func estimateReadTime(wordCount: Int) -> Int {
        return max(1, wordCount / 200)
    }

    // MARK: - Significant Word Extraction

    /// Extracts significant (non-stop, non-numeric) words from text.
    /// - Parameters:
    ///   - text: The input text to analyze.
    ///   - minimumLength: Minimum word length to include (default 3).
    /// - Returns: Array of lowercase significant words in order of appearance.
    public static func extractSignificantWords(from text: String, minimumLength: Int = 3) -> [String] {
        let lowered = text.lowercased()
        var words: [String] = []
        lowered.enumerateSubstrings(in: lowered.startIndex..., options: .byWords) { word, _, _, _ in
            guard let word = word,
                  word.count >= minimumLength,
                  !stopWords.contains(word),
                  !word.allSatisfy({ $0.isNumber }) else { return }
            words.append(word)
        }
        return words
    }

    // MARK: - Word Frequency Analysis

    /// Computes word frequencies from text, filtering stop words and short/numeric tokens.
    ///
    /// This is the frequency-counting counterpart to `extractSignificantWords`.
    /// Use this when you need term-frequency data (e.g. keyword extraction,
    /// TF-IDF scoring) rather than just the word list.
    ///
    /// - Parameters:
    ///   - text: The input text to analyze.
    ///   - minimumLength: Minimum word length to include (default 3).
    /// - Returns: Dictionary mapping lowercase significant words to their occurrence counts.
    public static func computeWordFrequencies(from text: String, minimumLength: Int = 3) -> [String: Int] {
        let words = extractSignificantWords(from: text, minimumLength: minimumLength)
        var frequencies: [String: Int] = [:]
        frequencies.reserveCapacity(words.count / 2)
        for word in words {
            frequencies[word, default: 0] += 1
        }
        return frequencies
    }
}
