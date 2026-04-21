//
//  FeedSentimentRadar.swift
//  FeedReaderCore
//
//  Autonomous sentiment tracking across RSS feeds. Analyzes article tone
//  using lexicon-based scoring, detects mood shifts over time, and generates
//  proactive alerts when sentiment changes significantly.
//

import Foundation

// MARK: - Sentiment Types

/// Sentiment polarity for a piece of text.
public enum SentimentPolarity: String, CaseIterable, Sendable {
    case veryNegative = "very_negative"
    case negative = "negative"
    case neutral = "neutral"
    case positive = "positive"
    case veryPositive = "very_positive"

    /// Numeric value from -1.0 (very negative) to +1.0 (very positive).
    public var numericValue: Double {
        switch self {
        case .veryNegative: return -1.0
        case .negative: return -0.5
        case .neutral: return 0.0
        case .positive: return 0.5
        case .veryPositive: return 1.0
        }
    }
}

/// Sentiment analysis result for a single article.
public struct ArticleSentiment: Sendable {
    /// Article title.
    public let title: String
    /// Compound sentiment score from -1.0 to +1.0.
    public let score: Double
    /// Polarity classification.
    public let polarity: SentimentPolarity
    /// Top positive words found.
    public let positiveWords: [String]
    /// Top negative words found.
    public let negativeWords: [String]
    /// Confidence level 0.0-1.0 based on word coverage.
    public let confidence: Double

}

/// Mood shift alert when sentiment changes significantly.
public struct SentimentAlert: Sendable {
    /// Alert severity.
    public enum Severity: String, Sendable {
        case info = "info"
        case warning = "warning"
        case critical = "critical"
    }

    /// Feed name.
    public let feedName: String
    /// Alert severity.
    public let severity: Severity
    /// Description of the shift.
    public let message: String
    /// Previous average sentiment.
    public let previousScore: Double
    /// Current average sentiment.
    public let currentScore: Double
    /// Magnitude of change.
    public let delta: Double
}

/// Feed-level sentiment summary.
public struct FeedSentimentSummary: Sendable {
    /// Feed name.
    public let feedName: String
    /// Average sentiment score.
    public let averageScore: Double
    /// Overall polarity.
    public let polarity: SentimentPolarity
    /// Score standard deviation.
    public let volatility: Double
    /// Number of articles analyzed.
    public let articleCount: Int
    /// Most positive article.
    public let mostPositive: ArticleSentiment?
    /// Most negative article.
    public let mostNegative: ArticleSentiment?
    /// Trend direction: positive, negative, or stable.
    public let trend: String
    /// Any alerts generated.
    public let alerts: [SentimentAlert]
}

// MARK: - Sentiment Lexicon

/// Built-in sentiment lexicon for scoring words.
internal enum SentimentLexicon {

    /// Positive words with intensity weights.
    static let positive: [String: Double] = [
        // Strong positive
        "excellent": 0.9, "amazing": 0.9, "outstanding": 0.9, "brilliant": 0.9,
        "exceptional": 0.9, "superb": 0.85, "fantastic": 0.85, "wonderful": 0.85,
        "incredible": 0.85, "magnificent": 0.85, "triumph": 0.85, "breakthrough": 0.85,
        // Moderate positive
        "great": 0.7, "good": 0.6, "nice": 0.5, "well": 0.5, "best": 0.7,
        "better": 0.6, "love": 0.7, "happy": 0.7, "pleased": 0.6, "glad": 0.6,
        "enjoy": 0.6, "success": 0.7, "successful": 0.7, "win": 0.6, "won": 0.6,
        "improve": 0.6, "improved": 0.6, "improvement": 0.6, "growth": 0.6,
        "grow": 0.5, "growing": 0.5, "gain": 0.5, "gains": 0.5, "profit": 0.6,
        "profitable": 0.6, "benefit": 0.6, "beneficial": 0.6, "advantage": 0.6,
        "innovative": 0.7, "innovation": 0.7, "progress": 0.6, "advance": 0.6,
        "advanced": 0.6, "positive": 0.5, "optimistic": 0.6, "hope": 0.5,
        "hopeful": 0.6, "promising": 0.6, "strong": 0.5, "strength": 0.5,
        "reliable": 0.5, "efficient": 0.6, "effective": 0.6, "impressive": 0.7,
        "remarkable": 0.7, "celebrate": 0.7, "achievement": 0.7, "award": 0.6,
        "praise": 0.6, "recommended": 0.6, "popular": 0.5, "leading": 0.5,
        "surge": 0.6, "soar": 0.7, "boost": 0.6, "record": 0.5, "upgrade": 0.5,
        // Mild positive
        "okay": 0.2, "fine": 0.3, "decent": 0.3, "fair": 0.3, "adequate": 0.2,
        "accept": 0.3, "acceptable": 0.3, "stable": 0.3, "steady": 0.3,
        "support": 0.4, "helpful": 0.5, "useful": 0.5, "interesting": 0.4,
        "launch": 0.4, "released": 0.4, "announce": 0.3, "expand": 0.4,
    ]

    /// Negative words with intensity weights.
    static let negative: [String: Double] = [
        // Strong negative
        "terrible": 0.9, "horrible": 0.9, "awful": 0.9, "catastrophic": 0.95,
        "devastating": 0.9, "disastrous": 0.9, "tragic": 0.9, "crisis": 0.85,
        "emergency": 0.8, "collapse": 0.85, "crashed": 0.85, "crash": 0.85,
        "destroy": 0.85, "destroyed": 0.85, "destruction": 0.85, "fatal": 0.9,
        "death": 0.8, "died": 0.8, "killed": 0.85, "murder": 0.9,
        // Moderate negative
        "bad": 0.6, "poor": 0.6, "worst": 0.7, "worse": 0.6, "fail": 0.7,
        "failed": 0.7, "failure": 0.7, "loss": 0.6, "lost": 0.6, "lose": 0.6,
        "losing": 0.6, "decline": 0.6, "declining": 0.6, "drop": 0.5, "dropped": 0.5,
        "fall": 0.5, "fell": 0.5, "falling": 0.5, "down": 0.3, "risk": 0.5,
        "risky": 0.5, "danger": 0.6, "dangerous": 0.7, "threat": 0.6,
        "threatening": 0.6, "concern": 0.5, "concerned": 0.5, "worry": 0.5,
        "worried": 0.5, "fear": 0.6, "afraid": 0.6, "problem": 0.5,
        "issue": 0.4, "trouble": 0.5, "difficult": 0.5, "struggle": 0.5,
        "struggling": 0.5, "weak": 0.5, "weakness": 0.5, "damage": 0.6,
        "damaged": 0.6, "harm": 0.6, "harmful": 0.6, "negative": 0.5,
        "pessimistic": 0.6, "deficit": 0.5, "debt": 0.5, "recession": 0.7,
        "inflation": 0.5, "scandal": 0.7, "corrupt": 0.7, "corruption": 0.7,
        "fraud": 0.7, "lawsuit": 0.5, "penalty": 0.5, "fine": 0.0,
        "violation": 0.6, "ban": 0.5, "banned": 0.5, "reject": 0.6,
        "rejected": 0.6, "plunge": 0.7, "plummeted": 0.7, "slump": 0.6,
        // Mild negative
        "slow": 0.3, "slower": 0.3, "delay": 0.4, "delayed": 0.4,
        "cut": 0.3, "cuts": 0.3, "reduce": 0.3, "reduced": 0.3,
        "miss": 0.4, "missed": 0.4, "lack": 0.4, "lacking": 0.4,
        "limited": 0.3, "uncertain": 0.4, "uncertainty": 0.4, "volatile": 0.4,
    ]

    /// Negation words that flip sentiment.
    static let negators: Set<String> = [
        "not", "no", "never", "neither", "nobody", "nothing",
        "nowhere", "nor", "cannot", "cant", "dont", "doesnt",
        "didnt", "wont", "wouldnt", "shouldnt", "couldnt",
        "isnt", "arent", "wasnt", "werent", "hardly", "barely",
        "scarcely", "rarely", "seldom",
    ]

    /// Intensifier words that amplify sentiment.
    static let intensifiers: [String: Double] = [
        "very": 1.3, "extremely": 1.5, "incredibly": 1.5,
        "absolutely": 1.4, "completely": 1.3, "totally": 1.3,
        "highly": 1.3, "really": 1.2, "truly": 1.2,
        "particularly": 1.2, "especially": 1.2, "remarkably": 1.3,
        "significantly": 1.3, "substantially": 1.2, "deeply": 1.3,
        "quite": 1.1, "rather": 1.1, "somewhat": 0.8,
        "slightly": 0.7, "a bit": 0.7, "mildly": 0.7,
    ]
}

// MARK: - FeedSentimentRadar

/// Autonomous sentiment radar for RSS feeds.
///
/// Analyzes article titles and descriptions for emotional tone, tracks
/// sentiment over time, detects significant mood shifts, and generates
/// proactive alerts.
///
/// ## Usage
/// ```swift
/// let radar = FeedSentimentRadar()
///
/// // Analyze a single article
/// let sentiment = radar.analyze(title: "Markets Surge on Strong Jobs Report",
///                                text: "Stocks rallied today as employment numbers exceeded expectations...")
/// print(sentiment.polarity)  // .positive
/// print(sentiment.score)     // 0.62
///
/// // Analyze an entire feed
/// let summary = radar.analyzeFeed(name: "Tech News", stories: stories)
/// print(summary.trend)       // "improving"
/// for alert in summary.alerts {
///     print("[\(alert.severity)] \(alert.message)")
/// }
///
/// // Compare feeds
/// let report = radar.generateReport(feeds: [("Tech", techStories), ("Finance", finStories)])
/// print(report)
/// ```
public class FeedSentimentRadar {

    // MARK: - Configuration

    /// Minimum score change to trigger a shift alert.
    public var shiftThreshold: Double

    /// Window size for trend detection (number of recent articles).
    public var trendWindow: Int

    /// Whether to use negation detection.
    public var useNegation: Bool

    /// Whether to use intensifier detection.
    public var useIntensifiers: Bool

    // MARK: - State

    /// Historical feed scores for drift detection.
    private var feedHistory: [String: [Double]] = [:]

    // MARK: - Init

    /// Creates a new sentiment radar.
    /// - Parameters:
    ///   - shiftThreshold: Minimum delta to trigger an alert (default 0.3).
    ///   - trendWindow: Articles to consider for trend (default 5).
    ///   - useNegation: Enable negation handling (default true).
    ///   - useIntensifiers: Enable intensifier handling (default true).
    public init(
        shiftThreshold: Double = 0.3,
        trendWindow: Int = 5,
        useNegation: Bool = true,
        useIntensifiers: Bool = true
    ) {
        self.shiftThreshold = shiftThreshold
        self.trendWindow = trendWindow
        self.useNegation = useNegation
        self.useIntensifiers = useIntensifiers
    }

    // MARK: - Single Text Analysis

    /// Analyze sentiment of a text string.
    /// - Parameters:
    ///   - title: Article title (given extra weight).
    ///   - text: Article body or description.
    ///   - date: Optional article date.
    /// - Returns: Sentiment analysis result.
    public func analyze(title: String, text: String = "") -> ArticleSentiment {
        let combinedText = title + " " + text
        let words = tokenize(combinedText)

        var positiveSum: Double = 0
        var negativeSum: Double = 0
        var matchedWords: Int = 0
        var posWords: [String] = []
        var negWords: [String] = []

        for i in 0..<words.count {
            let word = words[i]

            // Check for negation in preceding words
            let isNegated = useNegation && isNegatedAt(index: i, words: words)

            // Check for intensifier in preceding word
            let intensifier = useIntensifiers ? intensifierAt(index: i, words: words) : 1.0

            if let posScore = SentimentLexicon.positive[word] {
                let adjusted = posScore * intensifier
                if isNegated {
                    negativeSum += adjusted * 0.75  // Negated positive becomes weaker negative
                    negWords.append("not-\(word)")
                } else {
                    positiveSum += adjusted
                    posWords.append(word)
                }
                matchedWords += 1
            } else if let negScore = SentimentLexicon.negative[word], negScore > 0 {
                let adjusted = negScore * intensifier
                if isNegated {
                    positiveSum += adjusted * 0.5  // Negated negative becomes weaker positive
                    posWords.append("not-\(word)")
                } else {
                    negativeSum += adjusted
                    negWords.append(word)
                }
                matchedWords += 1
            }
        }

        // Also score the title separately with a boost
        let titleWords = tokenize(title)
        for word in titleWords {
            if let posScore = SentimentLexicon.positive[word] {
                positiveSum += posScore * 0.5  // Title boost
            } else if let negScore = SentimentLexicon.negative[word], negScore > 0 {
                negativeSum += negScore * 0.5  // Title boost
            }
        }

        // Compute compound score
        let rawScore = positiveSum - negativeSum
        let normalizer = positiveSum + negativeSum + 1.0  // +1 to prevent div by zero
        let compound = rawScore / normalizer  // Bounded roughly -1 to +1
        let clampedScore = max(-1.0, min(1.0, compound))

        // Confidence based on how many words matched the lexicon
        let totalWords = max(1, words.count)
        let confidence = min(1.0, Double(matchedWords) / Double(totalWords) * 3.0)

        let polarity = classifyPolarity(score: clampedScore)

        return ArticleSentiment(
            title: title,
            score: clampedScore,
            polarity: polarity,
            positiveWords: Array(Set(posWords)).sorted().prefix(5).map { $0 },
            negativeWords: Array(Set(negWords)).sorted().prefix(5).map { $0 },
            confidence: confidence
        )
    }

    // MARK: - Feed Analysis

    /// Analyze sentiment across an entire feed's articles.
    /// - Parameters:
    ///   - name: Feed name.
    ///   - stories: Array of RSSStory items.
    /// - Returns: Feed sentiment summary with trend and alerts.
    public func analyzeFeed(name: String, stories: [RSSStory]) -> FeedSentimentSummary {
        guard !stories.isEmpty else {
            return FeedSentimentSummary(
                feedName: name, averageScore: 0, polarity: .neutral,
                volatility: 0, articleCount: 0, mostPositive: nil,
                mostNegative: nil, trend: "no data", alerts: []
            )
        }

        let sentiments = stories.map { story in
            analyze(
                title: story.title,
                text: story.body
            )
        }

        let scores = sentiments.map { $0.score }
        let avg = scores.reduce(0, +) / Double(scores.count)
        let variance = scores.map { ($0 - avg) * ($0 - avg) }.reduce(0, +) / Double(scores.count)
        let stddev = sqrt(variance)

        let mostPos = sentiments.max(by: { $0.score < $1.score })
        let mostNeg = sentiments.min(by: { $0.score < $1.score })

        // Trend detection: compare recent window to older articles
        let trend = detectTrend(scores: scores)

        // Shift alerts
        var alerts: [SentimentAlert] = []
        alerts.append(contentsOf: detectShifts(feedName: name, scores: scores))

        // Volatility alert
        if stddev > 0.4 {
            alerts.append(SentimentAlert(
                feedName: name, severity: .warning,
                message: "High sentiment volatility detected (σ=\(String(format: "%.2f", stddev))). Feed content has wildly mixed tone.",
                previousScore: avg, currentScore: avg, delta: stddev
            ))
        }

        // Extreme negativity alert
        if avg < -0.3 {
            alerts.append(SentimentAlert(
                feedName: name, severity: .critical,
                message: "Feed is predominantly negative (avg=\(String(format: "%.2f", avg))). Consider reviewing content sources.",
                previousScore: 0, currentScore: avg, delta: avg
            ))
        }

        // Store history for future drift detection
        feedHistory[name, default: []].append(avg)

        return FeedSentimentSummary(
            feedName: name, averageScore: avg, polarity: classifyPolarity(score: avg),
            volatility: stddev, articleCount: sentiments.count,
            mostPositive: mostPos, mostNegative: mostNeg,
            trend: trend, alerts: alerts
        )
    }

    // MARK: - Cross-Feed Report

    /// Generate a comparative sentiment report across multiple feeds.
    /// - Parameter feeds: Array of (feedName, stories) tuples.
    /// - Returns: Formatted text report.
    public func generateReport(feeds: [(String, [RSSStory])]) -> String {
        var lines: [String] = []
        lines.append("═══════════════════════════════════════════════════")
        lines.append("  FEED SENTIMENT RADAR REPORT")
        lines.append("═══════════════════════════════════════════════════")
        lines.append("")

        var summaries: [FeedSentimentSummary] = []
        for (name, stories) in feeds {
            let summary = analyzeFeed(name: name, stories: stories)
            summaries.append(summary)
        }

        // Overall stats
        let allScores = summaries.map { $0.averageScore }
        let overallAvg = allScores.isEmpty ? 0 : allScores.reduce(0, +) / Double(allScores.count)
        lines.append("  Overall Mood: \(moodEmoji(overallAvg)) \(classifyPolarity(score: overallAvg).rawValue)")
        lines.append("  Feeds Analyzed: \(summaries.count)")
        lines.append("  Total Articles: \(summaries.map { $0.articleCount }.reduce(0, +))")
        lines.append("")

        // Per-feed breakdown
        lines.append("───────────────────────────────────────────────────")
        lines.append("  FEED BREAKDOWN")
        lines.append("───────────────────────────────────────────────────")

        for summary in summaries.sorted(by: { $0.averageScore > $1.averageScore }) {
            lines.append("")
            lines.append("  \(moodEmoji(summary.averageScore)) \(summary.feedName)")
            lines.append("    Score: \(String(format: "%+.2f", summary.averageScore)) (\(summary.polarity.rawValue))")
            lines.append("    Trend: \(summary.trend)")
            lines.append("    Volatility: \(String(format: "%.2f", summary.volatility))")
            lines.append("    Articles: \(summary.articleCount)")

            if let best = summary.mostPositive {
                lines.append("    Most Positive: \"\(best.title)\" (\(String(format: "%+.2f", best.score)))")
            }
            if let worst = summary.mostNegative {
                lines.append("    Most Negative: \"\(worst.title)\" (\(String(format: "%+.2f", worst.score)))")
            }
        }

        // Alerts section
        let allAlerts = summaries.flatMap { $0.alerts }
        if !allAlerts.isEmpty {
            lines.append("")
            lines.append("───────────────────────────────────────────────────")
            lines.append("  ⚠️  ALERTS")
            lines.append("───────────────────────────────────────────────────")
            for alert in allAlerts {
                let icon = alert.severity == .critical ? "🔴" : alert.severity == .warning ? "🟡" : "🔵"
                lines.append("  \(icon) [\(alert.feedName)] \(alert.message)")
            }
        }

        // Recommendations
        lines.append("")
        lines.append("───────────────────────────────────────────────────")
        lines.append("  💡 RECOMMENDATIONS")
        lines.append("───────────────────────────────────────────────────")
        lines.append(contentsOf: generateRecommendations(summaries: summaries).map { "  • \($0)" })

        lines.append("")
        lines.append("═══════════════════════════════════════════════════")
        return lines.joined(separator: "\n")
    }

    // MARK: - Private Helpers

    private func tokenize(_ text: String) -> [String] {
        let lower = text.lowercased()
        let cleaned = lower.unicodeScalars.map { char -> Character in
            if CharacterSet.letters.contains(char) || CharacterSet.whitespaces.contains(char) {
                return Character(char)
            }
            return " "
        }
        return String(cleaned)
            .split(separator: " ")
            .map { String($0) }
            .filter { $0.count > 1 && !TextUtilities.stopWords.contains($0) }
    }

    private func isNegatedAt(index: Int, words: [String]) -> Bool {
        // Check up to 3 words before for negation
        let start = max(0, index - 3)
        for j in start..<index {
            if SentimentLexicon.negators.contains(words[j]) {
                return true
            }
        }
        return false
    }

    private func intensifierAt(index: Int, words: [String]) -> Double {
        if index > 0, let mult = SentimentLexicon.intensifiers[words[index - 1]] {
            return mult
        }
        return 1.0
    }

    private func classifyPolarity(score: Double) -> SentimentPolarity {
        switch score {
        case ..<(-0.4): return .veryNegative
        case ..<(-0.1): return .negative
        case ...0.1: return .neutral
        case ...0.4: return .positive
        default: return .veryPositive
        }
    }

    private func detectTrend(scores: [Double]) -> String {
        guard scores.count >= 3 else { return "insufficient data" }

        let window = min(trendWindow, scores.count)
        let recent = Array(scores.suffix(window))
        let older = Array(scores.prefix(max(1, scores.count - window)))

        let recentAvg = recent.reduce(0, +) / Double(recent.count)
        let olderAvg = older.reduce(0, +) / Double(older.count)
        let diff = recentAvg - olderAvg

        if diff > 0.15 { return "improving ↑" }
        if diff < -0.15 { return "declining ↓" }
        return "stable →"
    }

    private func detectShifts(feedName: String, scores: [Double]) -> [SentimentAlert] {
        guard scores.count >= 4 else { return [] }

        var alerts: [SentimentAlert] = []
        let mid = scores.count / 2
        let firstHalf = Array(scores.prefix(mid))
        let secondHalf = Array(scores.suffix(scores.count - mid))

        let firstAvg = firstHalf.reduce(0, +) / Double(firstHalf.count)
        let secondAvg = secondHalf.reduce(0, +) / Double(secondHalf.count)
        let delta = secondAvg - firstAvg

        if abs(delta) >= shiftThreshold {
            let direction = delta > 0 ? "positive" : "negative"
            let severity: SentimentAlert.Severity = abs(delta) >= 0.5 ? .critical : .warning
            alerts.append(SentimentAlert(
                feedName: feedName, severity: severity,
                message: "Significant \(direction) mood shift detected (Δ=\(String(format: "%+.2f", delta))). Recent articles are notably \(delta > 0 ? "more upbeat" : "more concerning").",
                previousScore: firstAvg, currentScore: secondAvg, delta: delta
            ))
        }

        return alerts
    }

    private func moodEmoji(_ score: Double) -> String {
        switch score {
        case ..<(-0.4): return "😡"
        case ..<(-0.1): return "😟"
        case ...0.1: return "😐"
        case ...0.4: return "🙂"
        default: return "😄"
        }
    }

    private func generateRecommendations(summaries: [FeedSentimentSummary]) -> [String] {
        var recs: [String] = []

        let negative = summaries.filter { $0.averageScore < -0.2 }
        if !negative.isEmpty {
            recs.append("Consider balancing your reading diet — \(negative.count) feed(s) skew negative.")
        }

        let volatile = summaries.filter { $0.volatility > 0.35 }
        if !volatile.isEmpty {
            recs.append("High-volatility feeds (\(volatile.map { $0.feedName }.joined(separator: ", "))) may benefit from article-level filtering.")
        }

        let declining = summaries.filter { $0.trend.contains("declining") }
        if !declining.isEmpty {
            recs.append("Declining sentiment in \(declining.map { $0.feedName }.joined(separator: ", ")) — worth monitoring for developing negative stories.")
        }

        let improving = summaries.filter { $0.trend.contains("improving") }
        if !improving.isEmpty {
            recs.append("Good news: \(improving.map { $0.feedName }.joined(separator: ", ")) showing improving sentiment trends.")
        }

        if recs.isEmpty {
            recs.append("Feed sentiment is balanced and stable. No action needed.")
        }

        return recs
    }
}
