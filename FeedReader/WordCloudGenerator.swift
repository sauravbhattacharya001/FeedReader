//
//  WordCloudGenerator.swift
//  FeedReader
//
//  Generates word cloud data from article text — word frequencies
//  with sizing weights for visual rendering. Uses TextAnalyzer for
//  consistent tokenization and stop-word filtering.
//

import UIKit

/// A single word entry in a word cloud with its display properties.
struct WordCloudEntry {
    /// The word/term.
    let word: String
    /// Raw count of occurrences.
    let count: Int
    /// Normalized weight (0.0–1.0) relative to the most frequent word.
    let weight: Double
    /// Suggested font size for rendering.
    let fontSize: CGFloat
    /// Suggested color based on weight tier.
    let color: UIColor
}

/// Generates word cloud data from articles for visual display.
///
/// Takes one or more article bodies, tokenizes them via `TextAnalyzer`,
/// computes word frequencies, and produces sized/colored entries ready
/// for rendering in a collection view or custom layout.
///
/// Usage:
/// ```swift
/// let generator = WordCloudGenerator()
/// let entries = generator.generate(from: stories, maxWords: 50)
/// // entries are sorted by frequency, each with fontSize and color
/// ```
class WordCloudGenerator {

    // MARK: - Configuration

    /// Minimum font size for the least frequent words.
    var minFontSize: CGFloat = 12.0

    /// Maximum font size for the most frequent words.
    var maxFontSize: CGFloat = 48.0

    /// Maximum number of words to include in the cloud.
    var maxWords: Int = 60

    /// Minimum number of occurrences for a word to be included.
    var minimumOccurrences: Int = 2

    /// Color palette for word tiers (highest frequency first).
    var colorPalette: [UIColor] = [
        UIColor(red: 0.20, green: 0.29, blue: 0.37, alpha: 1.0), // dark blue-gray
        UIColor(red: 0.16, green: 0.50, blue: 0.73, alpha: 1.0), // blue
        UIColor(red: 0.10, green: 0.74, blue: 0.61, alpha: 1.0), // teal
        UIColor(red: 0.95, green: 0.61, blue: 0.07, alpha: 1.0), // orange
        UIColor(red: 0.75, green: 0.22, blue: 0.17, alpha: 1.0), // red
        UIColor(red: 0.56, green: 0.27, blue: 0.68, alpha: 1.0), // purple
    ]

    // MARK: - Generation

    /// Generate word cloud entries from an array of stories.
    ///
    /// - Parameters:
    ///   - stories: Array of `Story` objects to analyze.
    ///   - maxWords: Override for maximum words (uses instance default if nil).
    /// - Returns: Array of `WordCloudEntry` sorted by frequency (descending).
    func generate(from stories: [Story], maxWords: Int? = nil) -> [WordCloudEntry] {
        let combinedText = stories.map { "\($0.title) \($0.body)" }.joined(separator: " ")
        return generate(from: combinedText, maxWords: maxWords)
    }

    /// Generate word cloud entries from raw text.
    ///
    /// - Parameters:
    ///   - text: The input text to analyze.
    ///   - maxWords: Override for maximum words (uses instance default if nil).
    /// - Returns: Array of `WordCloudEntry` sorted by frequency (descending).
    func generate(from text: String, maxWords: Int? = nil) -> [WordCloudEntry] {
        let limit = maxWords ?? self.maxWords
        let tokens = TextAnalyzer.shared.tokenize(text)

        // Count occurrences
        var counts: [String: Int] = [:]
        for token in tokens {
            counts[token, default: 0] += 1
        }

        // Filter by minimum occurrences and sort by count
        let sorted = counts
            .filter { $0.value >= minimumOccurrences }
            .sorted { $0.value > $1.value }
            .prefix(limit)

        guard let maxCount = sorted.first?.value, maxCount > 0 else {
            return []
        }

        return sorted.map { word, count in
            let weight = Double(count) / Double(maxCount)
            let fontSize = minFontSize + CGFloat(weight) * (maxFontSize - minFontSize)
            let colorIndex = colorForWeight(weight)
            return WordCloudEntry(
                word: word,
                count: count,
                weight: weight,
                fontSize: fontSize,
                color: colorIndex
            )
        }
    }

    /// Generate word cloud entries from multiple text sources,
    /// useful for analyzing feeds or categories separately then merging.
    ///
    /// - Parameters:
    ///   - texts: Array of text strings.
    ///   - maxWords: Override for maximum words.
    /// - Returns: Array of `WordCloudEntry` sorted by frequency (descending).
    func generate(fromMultiple texts: [String], maxWords: Int? = nil) -> [WordCloudEntry] {
        let combined = texts.joined(separator: " ")
        return generate(from: combined, maxWords: maxWords)
    }

    /// Compare word clouds between two text sources, returning words
    /// unique to each and words in common.
    ///
    /// - Parameters:
    ///   - textA: First text source.
    ///   - textB: Second text source.
    ///   - topN: Number of top words to compare.
    /// - Returns: Tuple of (onlyInA, onlyInB, common) word arrays.
    func compare(textA: String, textB: String, topN: Int = 30) -> (onlyInA: [String], onlyInB: [String], common: [String]) {
        let entriesA = Set(generate(from: textA, maxWords: topN).map { $0.word })
        let entriesB = Set(generate(from: textB, maxWords: topN).map { $0.word })

        let common = entriesA.intersection(entriesB).sorted()
        let onlyA = entriesA.subtracting(entriesB).sorted()
        let onlyB = entriesB.subtracting(entriesA).sorted()

        return (onlyInA: onlyA, onlyInB: onlyB, common: common)
    }

    /// Export word cloud data as a simple JSON-compatible dictionary array.
    ///
    /// - Parameter entries: Word cloud entries to export.
    /// - Returns: Array of dictionaries with word, count, and weight keys.
    func exportAsJSON(_ entries: [WordCloudEntry]) -> [[String: Any]] {
        return entries.map { entry in
            [
                "word": entry.word,
                "count": entry.count,
                "weight": entry.weight,
                "fontSize": entry.fontSize,
            ]
        }
    }

    /// Export word cloud as CSV string.
    ///
    /// - Parameter entries: Word cloud entries to export.
    /// - Returns: CSV-formatted string with header row.
    func exportAsCSV(_ entries: [WordCloudEntry]) -> String {
        var lines = ["word,count,weight,fontSize"]
        for entry in entries {
            lines.append("\"\(entry.word)\",\(entry.count),\(String(format: "%.3f", entry.weight)),\(String(format: "%.1f", entry.fontSize))")
        }
        return lines.joined(separator: "\n")
    }

    // MARK: - Private

    /// Pick a color from the palette based on weight.
    private func colorForWeight(_ weight: Double) -> UIColor {
        guard !colorPalette.isEmpty else {
            return .darkGray
        }
        // Higher weight → lower index (more prominent color)
        let index = Int((1.0 - weight) * Double(colorPalette.count - 1))
        let clampedIndex = max(0, min(index, colorPalette.count - 1))
        return colorPalette[clampedIndex]
    }
}
