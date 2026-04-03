//
//  ArticleReadabilityAnalyzer.swift
//  FeedReader
//
//  Computes readability metrics for article text: Flesch Reading Ease,
//  Flesch-Kincaid Grade Level, estimated reading time, word/sentence
//  counts, and a human-friendly difficulty classification.
//
//  Uses syllable estimation heuristics (English-optimised) and standard
//  readability formulas. All methods are pure and stateless.
//

import Foundation

/// Result of a readability analysis on an article body.
struct ReadabilityResult {
    /// Total word count.
    let wordCount: Int
    /// Total sentence count.
    let sentenceCount: Int
    /// Total estimated syllable count.
    let syllableCount: Int
    /// Average words per sentence.
    let averageWordsPerSentence: Double
    /// Average syllables per word.
    let averageSyllablesPerWord: Double
    /// Flesch Reading Ease score (0–100+, higher = easier).
    let fleschReadingEase: Double
    /// Flesch-Kincaid Grade Level (US school grade).
    let fleschKincaidGradeLevel: Double
    /// Estimated reading time in seconds (at 238 wpm average).
    let estimatedReadingTimeSeconds: Double
    /// Human-friendly difficulty label.
    let difficulty: ReadabilityDifficulty
}

/// Difficulty classification derived from Flesch Reading Ease score.
enum ReadabilityDifficulty: String, CaseIterable {
    case veryEasy = "Very Easy"
    case easy = "Easy"
    case fairlyEasy = "Fairly Easy"
    case standard = "Standard"
    case fairlyDifficult = "Fairly Difficult"
    case difficult = "Difficult"
    case veryDifficult = "Very Difficult"

    /// Short emoji label for UI display.
    var emoji: String {
        switch self {
        case .veryEasy: return "🟢"
        case .easy: return "🟢"
        case .fairlyEasy: return "🟡"
        case .standard: return "🟡"
        case .fairlyDifficult: return "🟠"
        case .difficult: return "🔴"
        case .veryDifficult: return "🔴"
        }
    }

    /// Approximate grade range (US school system).
    var gradeRange: String {
        switch self {
        case .veryEasy: return "5th grade"
        case .easy: return "6th grade"
        case .fairlyEasy: return "7th grade"
        case .standard: return "8th-9th grade"
        case .fairlyDifficult: return "10th-12th grade"
        case .difficult: return "College"
        case .veryDifficult: return "College graduate"
        }
    }
}

/// Analyzes article text for readability using standard linguistic formulas.
///
/// Usage:
/// ```swift
/// let result = ArticleReadabilityAnalyzer.shared.analyze("Your article text here...")
/// print("Grade level: \(result.fleschKincaidGradeLevel)")
/// print("Difficulty: \(result.difficulty.rawValue)")
/// print("Reading time: \(result.estimatedReadingTimeSeconds)s")
/// ```
class ArticleReadabilityAnalyzer {

    // MARK: - Singleton

    static let shared = ArticleReadabilityAnalyzer()

    // MARK: - Constants

    /// Average adult reading speed in words per minute (Brysbaert, 2019).
    static let wordsPerMinute: Double = 238.0

    /// Sentence-ending punctuation.
    private static let sentenceEnders: CharacterSet = CharacterSet(charactersIn: ".!?")

    /// Characters to strip before syllable counting.
    private static let nonAlpha = CharacterSet.letters.inverted

    // MARK: - Initialization

    private init() {}

    // MARK: - Public API

    /// Analyze the readability of the given text.
    ///
    /// Returns `nil` if the text is empty or contains no words.
    func analyze(_ text: String) -> ReadabilityResult? {
        let cleaned = TextAnalyzer.shared.stripHTML(text)
        let words = tokenize(cleaned)
        guard !words.isEmpty else { return nil }

        let wordCount = words.count
        let sentenceCount = max(countSentences(cleaned), 1)
        let syllableCount = words.reduce(0) { $0 + countSyllables($1) }

        let avgWordsPerSentence = Double(wordCount) / Double(sentenceCount)
        let avgSyllablesPerWord = Double(syllableCount) / Double(wordCount)

        let fre = fleschReadingEase(
            avgWordsPerSentence: avgWordsPerSentence,
            avgSyllablesPerWord: avgSyllablesPerWord
        )
        let fkgl = fleschKincaidGradeLevel(
            avgWordsPerSentence: avgWordsPerSentence,
            avgSyllablesPerWord: avgSyllablesPerWord
        )
        let readingTime = Double(wordCount) / ArticleReadabilityAnalyzer.wordsPerMinute * 60.0
        let difficulty = classifyDifficulty(fre)

        return ReadabilityResult(
            wordCount: wordCount,
            sentenceCount: sentenceCount,
            syllableCount: syllableCount,
            averageWordsPerSentence: avgWordsPerSentence,
            averageSyllablesPerWord: avgSyllablesPerWord,
            fleschReadingEase: fre,
            fleschKincaidGradeLevel: fkgl,
            estimatedReadingTimeSeconds: readingTime,
            difficulty: difficulty
        )
    }

    /// Convenience: analyze a Story object's body text.
    func analyzeStory(_ story: Story) -> ReadabilityResult? {
        return analyze(story.body)
    }

    /// Batch-analyze multiple texts, returning results keyed by index.
    func analyzeBatch(_ texts: [String]) -> [Int: ReadabilityResult] {
        var results: [Int: ReadabilityResult] = [:]
        for (i, text) in texts.enumerated() {
            if let result = analyze(text) {
                results[i] = result
            }
        }
        return results
    }

    /// Format reading time as a human-friendly string.
    static func formatReadingTime(_ seconds: Double) -> String {
        if seconds < 60 {
            return "< 1 min"
        }
        let minutes = Int(seconds / 60.0)
        if minutes == 1 {
            return "1 min"
        }
        return "\(minutes) min"
    }

    /// Returns a one-line summary string for UI display.
    func summary(_ result: ReadabilityResult) -> String {
        let time = ArticleReadabilityAnalyzer.formatReadingTime(
            result.estimatedReadingTimeSeconds
        )
        return "\(result.difficulty.emoji) \(result.difficulty.rawValue) · \(time) · \(result.wordCount) words"
    }

    // MARK: - Flesch Formulas

    /// Flesch Reading Ease = 206.835 - 1.015 × ASL - 84.6 × ASW
    /// where ASL = average sentence length, ASW = average syllables per word.
    func fleschReadingEase(avgWordsPerSentence: Double,
                           avgSyllablesPerWord: Double) -> Double {
        return 206.835 - (1.015 * avgWordsPerSentence) - (84.6 * avgSyllablesPerWord)
    }

    /// Flesch-Kincaid Grade Level = 0.39 × ASL + 11.8 × ASW - 15.59
    func fleschKincaidGradeLevel(avgWordsPerSentence: Double,
                                  avgSyllablesPerWord: Double) -> Double {
        return (0.39 * avgWordsPerSentence) + (11.8 * avgSyllablesPerWord) - 15.59
    }

    /// Classify difficulty from Flesch Reading Ease score.
    func classifyDifficulty(_ fre: Double) -> ReadabilityDifficulty {
        switch fre {
        case 90...:               return .veryEasy
        case 80..<90:             return .easy
        case 70..<80:             return .fairlyEasy
        case 60..<70:             return .standard
        case 50..<60:             return .fairlyDifficult
        case 30..<50:             return .difficult
        default:                  return .veryDifficult
        }
    }

    // MARK: - Text Processing

    /// Tokenize text into lowercase words (letters only, min 1 char).
    func tokenize(_ text: String) -> [String] {
        let lower = text.lowercased()
        let components = lower.components(separatedBy: .whitespacesAndNewlines)
        return components.compactMap { word -> String? in
            // Strip non-letter characters from edges
            let trimmed = word.trimmingCharacters(in: ArticleReadabilityAnalyzer.nonAlpha)
            return trimmed.isEmpty ? nil : trimmed
        }
    }

    /// Count sentences by splitting on `.`, `!`, `?` and filtering empties.
    func countSentences(_ text: String) -> Int {
        // Split on sentence-ending punctuation
        let parts = text.components(separatedBy: ArticleReadabilityAnalyzer.sentenceEnders)
        // Count non-empty segments (each represents a sentence before the delimiter)
        let nonEmpty = parts.filter { segment in
            !segment.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
        return max(nonEmpty.count, 1)
    }

    /// Estimate syllable count for a single word using English heuristics.
    ///
    /// Rules:
    /// 1. Count vowel groups (consecutive vowels = one syllable).
    /// 2. Silent 'e' at end: subtract 1 if word ends in 'e' (but not "le").
    /// 3. Special endings: "-le" at end of word with consonant before → +1.
    /// 4. Minimum of 1 syllable per word.
    func countSyllables(_ word: String) -> Int {
        let w = word.lowercased()
        guard w.count > 0 else { return 0 }

        // Single-letter words
        if w.count <= 2 { return 1 }

        let vowels: Set<Character> = ["a", "e", "i", "o", "u", "y"]
        let chars = Array(w)
        var count = 0
        var prevWasVowel = false

        // Count vowel groups
        for ch in chars {
            let isVowel = vowels.contains(ch)
            if isVowel && !prevWasVowel {
                count += 1
            }
            prevWasVowel = isVowel
        }

        // Silent 'e' at end (but not "-le" preceded by consonant)
        if chars.last == "e" && count > 1 {
            if chars.count >= 3 {
                let beforeE = chars[chars.count - 2]
                let beforeThat = chars[chars.count - 3]
                // Keep the syllable for "-le" when preceded by a consonant
                if beforeE == "l" && !vowels.contains(beforeThat) {
                    // "-Cle" ending — the 'e' was already counted as part
                    // of the "le" vowel group, so no adjustment needed
                } else {
                    count -= 1
                }
            } else {
                count -= 1
            }
        }

        // Common suffixes that add syllables
        let suffixes = ["tion", "sion", "cious", "tious", "gious"]
        for suffix in suffixes {
            if w.hasSuffix(suffix) {
                // These are typically 1 syllable but counted as 2 vowel groups
                // Adjust down by 1 if we over-counted
                break // already handled by vowel-group counting
            }
        }

        return max(count, 1)
    }

    /// Compare two ReadabilityResults and describe the difference.
    func compare(_ a: ReadabilityResult, _ b: ReadabilityResult) -> String {
        let gradeA = a.fleschKincaidGradeLevel
        let gradeB = b.fleschKincaidGradeLevel
        let diff = abs(gradeA - gradeB)
        if diff < 0.5 {
            return "Similar difficulty (both \(a.difficulty.rawValue))"
        }
        let easier = gradeA < gradeB ? "A" : "B"
        return "\(easier) is easier by \(String(format: "%.1f", diff)) grade levels"
    }

    /// Get statistics across multiple results.
    func aggregateStats(_ results: [ReadabilityResult]) -> AggregateReadability? {
        guard !results.isEmpty else { return nil }
        let totalWords = results.reduce(0) { $0 + $1.wordCount }
        let totalSentences = results.reduce(0) { $0 + $1.sentenceCount }
        let avgFRE = results.reduce(0.0) { $0 + $1.fleschReadingEase } / Double(results.count)
        let avgGrade = results.reduce(0.0) { $0 + $1.fleschKincaidGradeLevel } / Double(results.count)
        let totalTime = results.reduce(0.0) { $0 + $1.estimatedReadingTimeSeconds }
        let difficulties = results.map { $0.difficulty }
        let diffCounts = Dictionary(grouping: difficulties) { $0 }.mapValues { $0.count }
        let mostCommon = diffCounts.max { $0.value < $1.value }?.key ?? .standard

        return AggregateReadability(
            articleCount: results.count,
            totalWordCount: totalWords,
            totalSentenceCount: totalSentences,
            averageFleschReadingEase: avgFRE,
            averageGradeLevel: avgGrade,
            totalReadingTimeSeconds: totalTime,
            predominantDifficulty: mostCommon
        )
    }
}

/// Aggregate readability statistics across multiple articles.
struct AggregateReadability {
    let articleCount: Int
    let totalWordCount: Int
    let totalSentenceCount: Int
    let averageFleschReadingEase: Double
    let averageGradeLevel: Double
    let totalReadingTimeSeconds: Double
    let predominantDifficulty: ReadabilityDifficulty
}
