//
//  ArticleComparisonEngine.swift
//  FeedReader
//
//  Side-by-side comparison of two articles covering the same topic.
//  Useful when multiple feeds report on the same story — shows which
//  source gives more depth, clearer writing, or different perspective.
//
//  Compares: readability, sentiment, length, keyword overlap, unique
//  angles, source diversity, and produces an overall verdict.
//
//  All methods are pure and stateless — delegates to existing analyzers
//  (ArticleReadabilityAnalyzer, ArticleSentimentAnalyzer, TextAnalyzer).
//

import Foundation

// MARK: - Notifications

extension Notification.Name {
    /// Posted when an article comparison completes.
    static let articleComparisonDidComplete = Notification.Name("ArticleComparisonDidCompleteNotification")
}

// MARK: - ComparisonVerdict

/// High-level verdict from comparing two articles.
enum ComparisonVerdict: String {
    case articleABetter   = "Article A is stronger"
    case articleBBetter   = "Article B is stronger"
    case roughlyEqual     = "Roughly equal"
    case complementary    = "Complementary — read both"

    var emoji: String {
        switch self {
        case .articleABetter: return "🅰️"
        case .articleBBetter: return "🅱️"
        case .roughlyEqual:  return "🤝"
        case .complementary: return "📖"
        }
    }
}

// MARK: - ComparisonDimension

/// A single axis of comparison with per-article values.
struct ComparisonDimension: Equatable {
    /// Name of the dimension (e.g., "Word Count", "Reading Level").
    let name: String
    /// Value for article A (human-readable).
    let valueA: String
    /// Value for article B (human-readable).
    let valueB: String
    /// Which article "wins" on this dimension (nil = tie).
    let winner: ComparisonWinner?
    /// Explanation of the difference.
    let explanation: String
}

/// Which article is better on a given dimension.
enum ComparisonWinner: String, Equatable {
    case articleA = "A"
    case articleB = "B"
}

// MARK: - KeywordAnalysis

/// Keyword overlap and uniqueness between two articles.
struct KeywordAnalysis: Equatable {
    /// Keywords appearing in both articles.
    let shared: [String]
    /// Keywords only in article A.
    let uniqueToA: [String]
    /// Keywords only in article B.
    let uniqueToB: [String]
    /// Jaccard similarity coefficient (0.0–1.0).
    let overlapScore: Double
    /// How many total distinct keywords across both.
    let totalUniqueKeywords: Int
}

// MARK: - ComparisonResult

/// Full result of comparing two articles.
struct ArticleComparisonResult {
    /// Title of article A.
    let titleA: String
    /// Title of article B.
    let titleB: String
    /// Source feed of article A.
    let sourceA: String
    /// Source feed of article B.
    let sourceB: String
    /// Per-dimension breakdowns.
    let dimensions: [ComparisonDimension]
    /// Keyword overlap analysis.
    let keywordAnalysis: KeywordAnalysis
    /// Overall verdict.
    let verdict: ComparisonVerdict
    /// Numeric similarity score (0.0–1.0) — how similar are the articles?
    let similarityScore: Double
    /// One-paragraph human-readable summary.
    let summary: String
    /// Timestamp of comparison.
    let comparedAt: Date
}

// MARK: - ArticleComparisonEngine

/// Compares two articles across multiple dimensions to help users
/// choose the better source or understand different perspectives.
class ArticleComparisonEngine {

    // MARK: - Singleton

    static let shared = ArticleComparisonEngine()

    // MARK: - Dependencies

    private let readabilityAnalyzer = ArticleReadabilityAnalyzer()
    private let sentimentAnalyzer = ArticleSentimentAnalyzer()

    // MARK: - Configuration

    /// Minimum word count for meaningful comparison.
    static let minimumWordCount = 10

    /// Number of top keywords to extract per article.
    static let keywordCount = 30

    /// Minimum keyword length.
    static let minKeywordLength = 4

    // MARK: - Public API

    /// Compare two articles across all dimensions.
    ///
    /// - Parameters:
    ///   - storyA: First article to compare.
    ///   - storyB: Second article to compare.
    /// - Returns: Full comparison result, or nil if either article is too short.
    func compare(_ storyA: Story, _ storyB: Story) -> ArticleComparisonResult? {
        let bodyA = storyA.body.trimmingCharacters(in: .whitespacesAndNewlines)
        let bodyB = storyB.body.trimmingCharacters(in: .whitespacesAndNewlines)

        guard wordCount(bodyA) >= ArticleComparisonEngine.minimumWordCount,
              wordCount(bodyB) >= ArticleComparisonEngine.minimumWordCount else {
            return nil
        }

        // Analyze both articles
        let readA = readabilityAnalyzer.analyze(bodyA)
        let readB = readabilityAnalyzer.analyze(bodyB)
        let sentA = sentimentAnalyzer.analyze(bodyA)
        let sentB = sentimentAnalyzer.analyze(bodyB)
        let kwA = Set(extractKeywords(bodyA))
        let kwB = Set(extractKeywords(bodyB))

        // Build dimensions
        var dimensions: [ComparisonDimension] = []
        var aWins = 0
        var bWins = 0

        // 1. Word Count (depth)
        let depthWinner = depthComparison(readA.wordCount, readB.wordCount)
        dimensions.append(ComparisonDimension(
            name: "Depth (Word Count)",
            valueA: "\(readA.wordCount) words",
            valueB: "\(readB.wordCount) words",
            winner: depthWinner,
            explanation: depthExplanation(readA.wordCount, readB.wordCount)
        ))
        if depthWinner == .articleA { aWins += 1 } else if depthWinner == .articleB { bWins += 1 }

        // 2. Readability
        let readWinner = readabilityComparison(readA.fleschReadingEase, readB.fleschReadingEase)
        dimensions.append(ComparisonDimension(
            name: "Readability",
            valueA: "\(readA.difficulty.rawValue) (\(String(format: "%.0f", readA.fleschReadingEase)))",
            valueB: "\(readB.difficulty.rawValue) (\(String(format: "%.0f", readB.fleschReadingEase)))",
            winner: readWinner,
            explanation: readabilityExplanation(readA, readB)
        ))
        if readWinner == .articleA { aWins += 1 } else if readWinner == .articleB { bWins += 1 }

        // 3. Sentence Complexity
        let sentenceWinner = sentenceComparison(readA.averageWordsPerSentence, readB.averageWordsPerSentence)
        dimensions.append(ComparisonDimension(
            name: "Sentence Length",
            valueA: String(format: "%.1f words/sentence", readA.averageWordsPerSentence),
            valueB: String(format: "%.1f words/sentence", readB.averageWordsPerSentence),
            winner: sentenceWinner,
            explanation: sentenceExplanation(readA.averageWordsPerSentence, readB.averageWordsPerSentence)
        ))
        if sentenceWinner == .articleA { aWins += 1 } else if sentenceWinner == .articleB { bWins += 1 }

        // 4. Sentiment
        let sentWinner = sentimentComparison(sentA.overallLabel, sentB.overallLabel)
        dimensions.append(ComparisonDimension(
            name: "Sentiment / Tone",
            valueA: "\(sentA.overallLabel.emoji) \(sentA.overallLabel.rawValue)",
            valueB: "\(sentB.overallLabel.emoji) \(sentB.overallLabel.rawValue)",
            winner: sentWinner,
            explanation: sentimentExplanation(sentA, sentB)
        ))
        // Sentiment is perspective, not win/loss — don't count

        // 5. Emotional Depth
        let emotionDim = emotionComparison(sentA, sentB)
        dimensions.append(emotionDim)

        // 6. Reading Time
        let timeWinner = readingTimeComparison(readA.estimatedReadingTimeSeconds, readB.estimatedReadingTimeSeconds)
        dimensions.append(ComparisonDimension(
            name: "Reading Time",
            valueA: formatTime(readA.estimatedReadingTimeSeconds),
            valueB: formatTime(readB.estimatedReadingTimeSeconds),
            winner: timeWinner,
            explanation: "Shorter isn't always better — it depends on your available time."
        ))
        // Reading time is preference, not win/loss

        // 7. Keyword Coverage
        let kwAnalysis = analyzeKeywords(kwA, kwB)
        let coverageWinner = kwA.count > kwB.count + 3 ? ComparisonWinner.articleA :
                             kwB.count > kwA.count + 3 ? ComparisonWinner.articleB : nil
        dimensions.append(ComparisonDimension(
            name: "Topic Coverage",
            valueA: "\(kwA.count) keywords",
            valueB: "\(kwB.count) keywords",
            winner: coverageWinner,
            explanation: coverageExplanation(kwAnalysis)
        ))
        if coverageWinner == .articleA { aWins += 1 } else if coverageWinner == .articleB { bWins += 1 }

        // Calculate similarity
        let titleSim = jaccardSimilarity(
            Set(extractKeywords(storyA.title)),
            Set(extractKeywords(storyB.title))
        )
        let contentSim = kwAnalysis.overlapScore
        let similarityScore = titleSim * 0.4 + contentSim * 0.6

        // Determine verdict
        let verdict = determineVerdict(aWins: aWins, bWins: bWins,
                                        similarity: similarityScore,
                                        kwAnalysis: kwAnalysis)

        // Generate summary
        let summary = generateSummary(
            titleA: storyA.title, titleB: storyB.title,
            sourceA: storyA.sourceFeedName ?? "Unknown",
            sourceB: storyB.sourceFeedName ?? "Unknown",
            verdict: verdict, dimensions: dimensions,
            kwAnalysis: kwAnalysis, similarity: similarityScore
        )

        let result = ArticleComparisonResult(
            titleA: storyA.title,
            titleB: storyB.title,
            sourceA: storyA.sourceFeedName ?? "Unknown",
            sourceB: storyB.sourceFeedName ?? "Unknown",
            dimensions: dimensions,
            keywordAnalysis: kwAnalysis,
            verdict: verdict,
            similarityScore: similarityScore,
            summary: summary,
            comparedAt: Date()
        )

        NotificationCenter.default.post(name: .articleComparisonDidComplete, object: result)
        return result
    }

    /// Quick similarity check without full comparison (cheaper).
    ///
    /// Returns Jaccard similarity of keyword sets (0.0–1.0).
    func quickSimilarity(_ storyA: Story, _ storyB: Story) -> Double {
        let kwA = Set(extractKeywords(storyA.body))
        let kwB = Set(extractKeywords(storyB.body))
        return jaccardSimilarity(kwA, kwB)
    }

    /// Format a comparison result as a human-readable text report.
    func formatReport(_ result: ArticleComparisonResult) -> String {
        var lines: [String] = []

        lines.append("Article Comparison Report")
        lines.append(String(repeating: "=", count: 40))
        lines.append("")
        lines.append("A: \"\(result.titleA)\" (\(result.sourceA))")
        lines.append("B: \"\(result.titleB)\" (\(result.sourceB))")
        lines.append("")
        lines.append("Similarity: \(Int(result.similarityScore * 100))%")
        lines.append("Verdict: \(result.verdict.emoji) \(result.verdict.rawValue)")
        lines.append("")

        lines.append("Dimensions")
        lines.append(String(repeating: "-", count: 40))
        for dim in result.dimensions {
            let winnerStr: String
            switch dim.winner {
            case .articleA: winnerStr = " ← winner"
            case .articleB: winnerStr = " → winner"
            case nil:       winnerStr = " (tie)"
            }
            lines.append("\(dim.name):")
            lines.append("  A: \(dim.valueA)")
            lines.append("  B: \(dim.valueB)\(winnerStr)")
            lines.append("  \(dim.explanation)")
            lines.append("")
        }

        lines.append("Keyword Analysis")
        lines.append(String(repeating: "-", count: 40))
        lines.append("Overlap: \(Int(result.keywordAnalysis.overlapScore * 100))% (\(result.keywordAnalysis.shared.count) shared keywords)")
        if !result.keywordAnalysis.shared.isEmpty {
            lines.append("Shared: \(result.keywordAnalysis.shared.prefix(10).joined(separator: ", "))")
        }
        if !result.keywordAnalysis.uniqueToA.isEmpty {
            lines.append("Only in A: \(result.keywordAnalysis.uniqueToA.prefix(8).joined(separator: ", "))")
        }
        if !result.keywordAnalysis.uniqueToB.isEmpty {
            lines.append("Only in B: \(result.keywordAnalysis.uniqueToB.prefix(8).joined(separator: ", "))")
        }
        lines.append("")

        lines.append("Summary")
        lines.append(String(repeating: "-", count: 40))
        lines.append(result.summary)

        return lines.joined(separator: "\n")
    }

    /// Format a comparison result as JSON.
    func formatJSON(_ result: ArticleComparisonResult) -> String? {
        var dict: [String: Any] = [
            "titleA": result.titleA,
            "titleB": result.titleB,
            "sourceA": result.sourceA,
            "sourceB": result.sourceB,
            "similarityScore": result.similarityScore,
            "verdict": result.verdict.rawValue,
            "summary": result.summary,
            "comparedAt": ISO8601DateFormatter().string(from: result.comparedAt)
        ]

        var dimArray: [[String: Any]] = []
        for dim in result.dimensions {
            dimArray.append([
                "name": dim.name,
                "valueA": dim.valueA,
                "valueB": dim.valueB,
                "winner": dim.winner?.rawValue ?? "tie",
                "explanation": dim.explanation
            ])
        }
        dict["dimensions"] = dimArray

        dict["keywords"] = [
            "shared": result.keywordAnalysis.shared,
            "uniqueToA": result.keywordAnalysis.uniqueToA,
            "uniqueToB": result.keywordAnalysis.uniqueToB,
            "overlapScore": result.keywordAnalysis.overlapScore,
            "totalUnique": result.keywordAnalysis.totalUniqueKeywords
        ] as [String: Any]

        guard let data = try? JSONSerialization.data(withJSONObject: dict,
                                                     options: [.prettyPrinted, .sortedKeys]) else {
            return nil
        }
        return String(data: data, encoding: .utf8)
    }

    // MARK: - Private: Keyword Extraction

    private func extractKeywords(_ text: String) -> [String] {
        return TextAnalyzer.shared.extractKeywords(
            from: text,
            minLength: ArticleComparisonEngine.minKeywordLength
        )
    }

    // MARK: - Private: Keyword Analysis

    private func analyzeKeywords(_ kwA: Set<String>, _ kwB: Set<String>) -> KeywordAnalysis {
        let shared = kwA.intersection(kwB).sorted()
        let uniqueA = kwA.subtracting(kwB).sorted()
        let uniqueB = kwB.subtracting(kwA).sorted()
        let union = kwA.union(kwB)
        let overlap = union.isEmpty ? 0.0 : Double(shared.count) / Double(union.count)

        return KeywordAnalysis(
            shared: shared,
            uniqueToA: uniqueA,
            uniqueToB: uniqueB,
            overlapScore: overlap,
            totalUniqueKeywords: union.count
        )
    }

    private func jaccardSimilarity(_ setA: Set<String>, _ setB: Set<String>) -> Double {
        let union = setA.union(setB)
        guard !union.isEmpty else { return 0.0 }
        return Double(setA.intersection(setB).count) / Double(union.count)
    }

    // MARK: - Private: Dimension Comparisons

    private func depthComparison(_ countA: Int, _ countB: Int) -> ComparisonWinner? {
        let ratio = Double(max(countA, countB)) / Double(max(min(countA, countB), 1))
        guard ratio > 1.25 else { return nil } // Within 25% = tie
        return countA > countB ? .articleA : .articleB
    }

    private func depthExplanation(_ countA: Int, _ countB: Int) -> String {
        let diff = abs(countA - countB)
        if diff < 50 { return "Both articles are similar in length." }
        let longer = countA > countB ? "A" : "B"
        let ratio = String(format: "%.1f", Double(max(countA, countB)) / Double(max(min(countA, countB), 1)))
        return "Article \(longer) is \(ratio)x longer (+\(diff) words), suggesting more in-depth coverage."
    }

    private func readabilityComparison(_ easeA: Double, _ easeB: Double) -> ComparisonWinner? {
        let diff = abs(easeA - easeB)
        guard diff > 10 else { return nil } // Within 10 points = tie
        // Higher Flesch = easier to read (generally better for news)
        return easeA > easeB ? .articleA : .articleB
    }

    private func readabilityExplanation(_ readA: ReadabilityResult, _ readB: ReadabilityResult) -> String {
        let diff = abs(readA.fleschReadingEase - readB.fleschReadingEase)
        if diff < 10 { return "Both articles are at a similar reading level." }
        let easier = readA.fleschReadingEase > readB.fleschReadingEase ? "A" : "B"
        return "Article \(easier) is easier to read (grade \(String(format: "%.0f", min(readA.fleschKincaidGradeLevel, readB.fleschKincaidGradeLevel))) vs \(String(format: "%.0f", max(readA.fleschKincaidGradeLevel, readB.fleschKincaidGradeLevel))))."
    }

    private func sentenceComparison(_ avgA: Double, _ avgB: Double) -> ComparisonWinner? {
        // Shorter sentences are generally clearer for news; ideal ~15-20 words
        let idealTarget = 17.5
        let distA = abs(avgA - idealTarget)
        let distB = abs(avgB - idealTarget)
        guard abs(distA - distB) > 3 else { return nil }
        return distA < distB ? .articleA : .articleB
    }

    private func sentenceExplanation(_ avgA: Double, _ avgB: Double) -> String {
        let diff = abs(avgA - avgB)
        if diff < 3 { return "Both articles use similar sentence lengths." }
        let shorter = avgA < avgB ? "A" : "B"
        return "Article \(shorter) uses shorter sentences, which may be clearer for quick reading."
    }

    private func sentimentComparison(_ labelA: SentimentLabel, _ labelB: SentimentLabel) -> ComparisonWinner? {
        // Sentiment isn't a competition — just show the difference
        return nil
    }

    private func sentimentExplanation(_ sentA: SentimentResult, _ sentB: SentimentResult) -> String {
        if sentA.overallLabel == sentB.overallLabel {
            return "Both articles have a similar tone."
        }
        return "Different perspectives: A is \(sentA.overallLabel.rawValue.lowercased()), B is \(sentB.overallLabel.rawValue.lowercased()). Reading both gives a fuller picture."
    }

    private func emotionComparison(_ sentA: SentimentResult, _ sentB: SentimentResult) -> ComparisonDimension {
        let emotionA = sentA.dominantEmotion
        let emotionB = sentB.dominantEmotion

        let explanation: String
        if emotionA == emotionB {
            explanation = "Both articles convey \(emotionA.rawValue.lowercased())."
        } else if emotionA == .none && emotionB == .none {
            explanation = "Neither article has a strong emotional tone."
        } else {
            explanation = "A leans toward \(emotionA.rawValue.lowercased()), B toward \(emotionB.rawValue.lowercased()) — they frame the story differently."
        }

        return ComparisonDimension(
            name: "Emotional Tone",
            valueA: "\(emotionA.emoji) \(emotionA.rawValue)",
            valueB: "\(emotionB.emoji) \(emotionB.rawValue)",
            winner: nil, // Emotion isn't a competition
            explanation: explanation
        )
    }

    private func readingTimeComparison(_ timeA: Double, _ timeB: Double) -> ComparisonWinner? {
        // Shorter reading time wins (for users in a hurry)
        let ratio = max(timeA, timeB) / max(min(timeA, timeB), 1)
        guard ratio > 1.5 else { return nil }
        return timeA < timeB ? .articleA : .articleB
    }

    private func coverageExplanation(_ kw: KeywordAnalysis) -> String {
        if kw.overlapScore > 0.6 {
            return "High topic overlap (\(Int(kw.overlapScore * 100))%) — these articles cover very similar ground."
        } else if kw.overlapScore > 0.3 {
            return "Moderate overlap (\(Int(kw.overlapScore * 100))%) — same general topic but with different angles."
        } else {
            return "Low overlap (\(Int(kw.overlapScore * 100))%) — these articles may cover different aspects of the story."
        }
    }

    // MARK: - Private: Verdict

    private func determineVerdict(aWins: Int, bWins: Int,
                                   similarity: Double,
                                   kwAnalysis: KeywordAnalysis) -> ComparisonVerdict {
        // If articles are very different, they're complementary
        if similarity < 0.15 && kwAnalysis.uniqueToA.count > 5 && kwAnalysis.uniqueToB.count > 5 {
            return .complementary
        }

        // If each has significant unique coverage, complementary
        if kwAnalysis.uniqueToA.count > 8 && kwAnalysis.uniqueToB.count > 8
            && kwAnalysis.overlapScore < 0.4 {
            return .complementary
        }

        // Clear winner
        if aWins >= bWins + 2 { return .articleABetter }
        if bWins >= aWins + 2 { return .articleBBetter }

        // Slight edge
        if aWins > bWins { return .articleABetter }
        if bWins > aWins { return .articleBBetter }

        return .roughlyEqual
    }

    // MARK: - Private: Summary Generation

    private func generateSummary(titleA: String, titleB: String,
                                  sourceA: String, sourceB: String,
                                  verdict: ComparisonVerdict,
                                  dimensions: [ComparisonDimension],
                                  kwAnalysis: KeywordAnalysis,
                                  similarity: Double) -> String {
        var parts: [String] = []

        // Similarity context
        if similarity > 0.5 {
            parts.append("These articles from \(sourceA) and \(sourceB) cover very similar ground (\(Int(similarity * 100))% similarity).")
        } else if similarity > 0.2 {
            parts.append("These articles from \(sourceA) and \(sourceB) share some common themes (\(Int(similarity * 100))% similarity).")
        } else {
            parts.append("These articles from \(sourceA) and \(sourceB) take quite different approaches to the topic.")
        }

        // Verdict-specific advice
        switch verdict {
        case .articleABetter:
            parts.append("\"\(truncate(titleA, to: 50))\" is the stronger article overall — more thorough and/or clearer.")
        case .articleBBetter:
            parts.append("\"\(truncate(titleB, to: 50))\" is the stronger article overall — more thorough and/or clearer.")
        case .roughlyEqual:
            parts.append("Both articles are comparable in quality — pick whichever source you prefer.")
        case .complementary:
            parts.append("Each article covers unique angles. Reading both gives the most complete picture.")
        }

        // Unique keyword highlights
        if !kwAnalysis.uniqueToA.isEmpty && !kwAnalysis.uniqueToB.isEmpty {
            let aTopics = kwAnalysis.uniqueToA.prefix(3).joined(separator: ", ")
            let bTopics = kwAnalysis.uniqueToB.prefix(3).joined(separator: ", ")
            parts.append("A uniquely covers \(aTopics); B uniquely covers \(bTopics).")
        }

        return parts.joined(separator: " ")
    }

    // MARK: - Private: Utilities

    private func wordCount(_ text: String) -> Int {
        return text.split(whereSeparator: { $0.isWhitespace || $0.isNewline }).count
    }

    private func formatTime(_ seconds: Double) -> String {
        let minutes = Int(ceil(seconds / 60.0))
        if minutes < 1 { return "< 1 min" }
        if minutes < 60 { return "\(minutes) min" }
        let hours = minutes / 60
        let remaining = minutes % 60
        if remaining == 0 { return "\(hours) hr" }
        return "\(hours) hr \(remaining) min"
    }

    private func truncate(_ text: String, to maxLength: Int) -> String {
        if text.count <= maxLength { return text }
        return String(text.prefix(maxLength - 3)) + "..."
    }
}