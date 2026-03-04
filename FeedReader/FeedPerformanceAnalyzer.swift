//
//  FeedPerformanceAnalyzer.swift
//  FeedReader
//
//  Aggregates per-feed analytics into a unified feed "report card".
//  Combines publishing frequency, readability, sentiment, content
//  diversity, and reading engagement into a composite quality score.
//  Helps users decide which feeds are worth keeping and surfaces
//  feeds that may have gone stale or declined in quality.
//
//  Fully offline — no network, no dependencies beyond Foundation.
//

import Foundation

// MARK: - Notification

extension Notification.Name {
    static let feedPerformanceDidUpdate = Notification.Name("FeedPerformanceDidUpdateNotification")
}

// MARK: - FeedGrade

/// Letter grade derived from composite quality score.
enum FeedGrade: String, CaseIterable, Comparable {
    case aPlus  = "A+"
    case a      = "A"
    case bPlus  = "B+"
    case b      = "B"
    case cPlus  = "C+"
    case c      = "C"
    case d      = "D"
    case f      = "F"

    /// Numeric rank for ordering (lower = better).
    var rank: Int {
        switch self {
        case .aPlus: return 0
        case .a:     return 1
        case .bPlus: return 2
        case .b:     return 3
        case .cPlus: return 4
        case .c:     return 5
        case .d:     return 6
        case .f:     return 7
        }
    }

    static func < (lhs: FeedGrade, rhs: FeedGrade) -> Bool {
        return lhs.rank < rhs.rank
    }

    /// Derive grade from a 0-100 composite score.
    static func from(score: Double) -> FeedGrade {
        switch score {
        case 90...:       return .aPlus
        case 80..<90:     return .a
        case 70..<80:     return .bPlus
        case 60..<70:     return .b
        case 50..<60:     return .cPlus
        case 40..<50:     return .c
        case 25..<40:     return .d
        default:          return .f
        }
    }

    /// Emoji for display.
    var emoji: String {
        switch self {
        case .aPlus, .a:       return "🌟"
        case .bPlus, .b:       return "👍"
        case .cPlus, .c:       return "🤷"
        case .d:               return "👎"
        case .f:               return "🚫"
        }
    }
}

// MARK: - FeedHealthStatus

/// Whether a feed appears active, slowing down, or dead.
enum FeedHealthStatus: String {
    case active     = "Active"
    case slowing    = "Slowing Down"
    case stale      = "Stale"
    case dead       = "Dead"
}

// MARK: - PublishingMetrics

/// Statistics about a feed's publishing frequency and consistency.
struct PublishingMetrics: Equatable {
    /// Total articles analyzed.
    let articleCount: Int
    /// Average articles published per day.
    let articlesPerDay: Double
    /// Standard deviation of daily article counts (consistency).
    let publishingConsistency: Double
    /// Days since the most recent article.
    let daysSinceLastArticle: Int
    /// Average gap between articles in hours.
    let averageGapHours: Double
    /// Longest gap between articles in hours.
    let longestGapHours: Double
    /// Health status based on recency and frequency.
    let healthStatus: FeedHealthStatus
}

// MARK: - ContentQualityMetrics

/// Aggregated readability and content quality for a feed's articles.
struct ContentQualityMetrics: Equatable {
    /// Average Flesch Reading Ease across articles.
    let averageReadability: Double
    /// Average word count per article.
    let averageWordCount: Double
    /// Median word count per article.
    let medianWordCount: Int
    /// Percentage of articles with substantial content (>100 words).
    let substantiveRatio: Double
    /// Number of unique topics/keywords across articles.
    let topicDiversity: Int
    /// Top keywords by frequency.
    let topKeywords: [(keyword: String, count: Int)]

    static func == (lhs: ContentQualityMetrics, rhs: ContentQualityMetrics) -> Bool {
        return lhs.averageReadability == rhs.averageReadability
            && lhs.averageWordCount == rhs.averageWordCount
            && lhs.medianWordCount == rhs.medianWordCount
            && lhs.substantiveRatio == rhs.substantiveRatio
            && lhs.topicDiversity == rhs.topicDiversity
            && lhs.topKeywords.count == rhs.topKeywords.count
    }
}

// MARK: - SentimentProfile

/// Sentiment distribution across a feed's articles.
struct SentimentProfile: Equatable {
    /// Average sentiment score (-1.0 to 1.0).
    let averageSentiment: Double
    /// Percentage of positive articles (score > 0.1).
    let positiveRatio: Double
    /// Percentage of negative articles (score < -0.1).
    let negativeRatio: Double
    /// Percentage of neutral articles.
    let neutralRatio: Double
    /// Sentiment volatility (standard deviation).
    let volatility: Double
    /// Human-readable label for the feed's overall tone.
    let tone: String
}

// MARK: - EngagementMetrics

/// How much the user actually reads and engages with a feed.
struct EngagementMetrics: Equatable {
    /// Percentage of articles from this feed that were read.
    let readRate: Double
    /// Number of articles read.
    let articlesRead: Int
    /// Number of articles bookmarked.
    let articlesBookmarked: Int
    /// Average time between article publish and user read (hours).
    let averageReadLagHours: Double
}

// MARK: - FeedReportCard

/// Complete performance report for a single feed.
struct FeedReportCard: Equatable {
    /// Feed name.
    let feedName: String
    /// Feed URL.
    let feedURL: String
    /// Composite quality score (0-100).
    let compositeScore: Double
    /// Letter grade.
    let grade: FeedGrade
    /// Publishing frequency and consistency.
    let publishing: PublishingMetrics
    /// Content quality and readability.
    let contentQuality: ContentQualityMetrics
    /// Sentiment distribution.
    let sentiment: SentimentProfile
    /// User engagement.
    let engagement: EngagementMetrics
    /// Actionable recommendation.
    let recommendation: String
    /// Analysis timestamp.
    let analyzedAt: Date

    static func == (lhs: FeedReportCard, rhs: FeedReportCard) -> Bool {
        return lhs.feedName == rhs.feedName
            && lhs.feedURL == rhs.feedURL
            && lhs.compositeScore == rhs.compositeScore
            && lhs.grade == rhs.grade
    }
}

// MARK: - Score Weights

/// Configurable weights for composite score calculation.
struct FeedScoreWeights: Equatable {
    /// Weight for publishing frequency/consistency (0-1).
    let publishing: Double
    /// Weight for content quality (0-1).
    let contentQuality: Double
    /// Weight for engagement rate (0-1).
    let engagement: Double
    /// Weight for content freshness (0-1).
    let freshness: Double

    /// Default balanced weights.
    static let `default` = FeedScoreWeights(
        publishing: 0.25,
        contentQuality: 0.30,
        engagement: 0.25,
        freshness: 0.20
    )

    /// Weights emphasizing content quality over frequency.
    static let qualityFirst = FeedScoreWeights(
        publishing: 0.15,
        contentQuality: 0.45,
        engagement: 0.25,
        freshness: 0.15
    )

    /// Weights emphasizing user engagement.
    static let engagementFirst = FeedScoreWeights(
        publishing: 0.15,
        contentQuality: 0.20,
        engagement: 0.50,
        freshness: 0.15
    )

    /// Sum of all weights (should be 1.0 for normalized scoring).
    var total: Double {
        return publishing + contentQuality + engagement + freshness
    }
}

// MARK: - FeedPerformanceAnalyzer

/// Analyzes feed performance by aggregating multiple quality signals
/// into a composite score and actionable recommendations.
class FeedPerformanceAnalyzer {

    // MARK: - Properties

    /// Score weights for composite calculation.
    let weights: FeedScoreWeights

    /// Stop words excluded from keyword extraction.
    private static let stopWords: Set<String> = [
        "the", "a", "an", "and", "or", "but", "in", "on", "at", "to",
        "for", "of", "with", "by", "from", "is", "it", "that", "this",
        "was", "are", "be", "has", "had", "have", "will", "would",
        "could", "should", "may", "might", "can", "do", "does", "did",
        "not", "no", "so", "if", "than", "too", "very", "just", "about",
        "also", "into", "over", "after", "before", "between", "through",
        "been", "being", "its", "their", "our", "your", "his", "her",
        "they", "them", "we", "us", "he", "she", "who", "which", "what",
        "when", "where", "how", "all", "each", "every", "both", "more",
        "most", "other", "some", "such", "only", "own", "same", "then",
        "up", "out", "new", "one", "two", "now", "way", "many", "any",
        "said", "like", "get", "got", "make", "made", "see", "use"
    ]

    // MARK: - Initialization

    /// Create an analyzer with custom score weights.
    /// - Parameter weights: Weights for composite score components.
    init(weights: FeedScoreWeights = .default) {
        self.weights = weights
    }

    // MARK: - Analysis

    /// Analyze a single feed and produce a report card.
    ///
    /// - Parameters:
    ///   - feedName: Display name of the feed.
    ///   - feedURL: URL of the feed.
    ///   - articles: Articles from this feed (title + body + link + date).
    ///   - readLinks: Set of article links the user has read.
    ///   - bookmarkedLinks: Set of article links the user has bookmarked.
    ///   - now: Reference time for freshness calculations.
    /// - Returns: A complete FeedReportCard with scores and recommendations.
    func analyze(
        feedName: String,
        feedURL: String,
        articles: [(title: String, body: String, link: String, date: Date)],
        readLinks: Set<String> = [],
        bookmarkedLinks: Set<String> = [],
        now: Date = Date()
    ) -> FeedReportCard {
        let publishing = analyzePublishing(articles: articles, now: now)
        let content = analyzeContent(articles: articles)
        let sentiment = analyzeSentiment(articles: articles)
        let engagement = analyzeEngagement(
            articles: articles,
            readLinks: readLinks,
            bookmarkedLinks: bookmarkedLinks,
            now: now
        )

        let composite = computeComposite(
            publishing: publishing,
            content: content,
            engagement: engagement,
            now: now,
            daysSinceLast: publishing.daysSinceLastArticle
        )

        let recommendation = generateRecommendation(
            grade: FeedGrade.from(score: composite),
            publishing: publishing,
            content: content,
            engagement: engagement
        )

        return FeedReportCard(
            feedName: feedName,
            feedURL: feedURL,
            compositeScore: composite,
            grade: FeedGrade.from(score: composite),
            publishing: publishing,
            contentQuality: content,
            sentiment: sentiment,
            engagement: engagement,
            recommendation: recommendation,
            analyzedAt: now
        )
    }

    /// Analyze all feeds and return report cards sorted by composite score.
    ///
    /// - Parameters:
    ///   - feeds: Array of (name, url, articles) tuples.
    ///   - readLinks: All read article links.
    ///   - bookmarkedLinks: All bookmarked article links.
    ///   - now: Reference time.
    /// - Returns: Array of FeedReportCards sorted by score descending.
    func analyzeAll(
        feeds: [(name: String, url: String, articles: [(title: String, body: String, link: String, date: Date)])],
        readLinks: Set<String> = [],
        bookmarkedLinks: Set<String> = [],
        now: Date = Date()
    ) -> [FeedReportCard] {
        return feeds
            .map { feed in
                analyze(
                    feedName: feed.name,
                    feedURL: feed.url,
                    articles: feed.articles,
                    readLinks: readLinks,
                    bookmarkedLinks: bookmarkedLinks,
                    now: now
                )
            }
            .sorted { $0.compositeScore > $1.compositeScore }
    }

    /// Generate a text summary comparing all feeds.
    ///
    /// - Parameter reports: Array of FeedReportCards.
    /// - Returns: Human-readable comparison summary.
    func summary(from reports: [FeedReportCard]) -> String {
        guard !reports.isEmpty else {
            return "No feeds to analyze."
        }

        var lines: [String] = []
        lines.append("Feed Performance Summary")
        lines.append(String(repeating: "=", count: 50))
        lines.append("")

        let sorted = reports.sorted { $0.compositeScore > $1.compositeScore }

        for (i, report) in sorted.enumerated() {
            let rank = i + 1
            lines.append("\(rank). \(report.grade.emoji) \(report.feedName) — \(report.grade.rawValue) (\(String(format: "%.0f", report.compositeScore))/100)")
            lines.append("   Publishing: \(String(format: "%.1f", report.publishing.articlesPerDay)) articles/day (\(report.publishing.healthStatus.rawValue))")
            lines.append("   Readability: \(String(format: "%.0f", report.contentQuality.averageReadability)) Flesch, \(String(format: "%.0f", report.contentQuality.averageWordCount)) avg words")
            lines.append("   Sentiment: \(report.sentiment.tone) (avg \(String(format: "%.2f", report.sentiment.averageSentiment)))")
            lines.append("   Engagement: \(String(format: "%.0f%%", report.engagement.readRate * 100)) read rate")
            lines.append("   → \(report.recommendation)")
            lines.append("")
        }

        let avgScore = sorted.reduce(0.0) { $0 + $1.compositeScore } / Double(sorted.count)
        lines.append("Overall: \(sorted.count) feeds, average score \(String(format: "%.0f", avgScore))/100")

        let stale = sorted.filter { $0.publishing.healthStatus == .dead || $0.publishing.healthStatus == .stale }
        if !stale.isEmpty {
            lines.append("⚠️ \(stale.count) feed(s) appear stale or dead — consider removing.")
        }

        return lines.joined(separator: "\n")
    }

    // MARK: - Publishing Analysis

    func analyzePublishing(
        articles: [(title: String, body: String, link: String, date: Date)],
        now: Date
    ) -> PublishingMetrics {
        guard !articles.isEmpty else {
            return PublishingMetrics(
                articleCount: 0,
                articlesPerDay: 0,
                publishingConsistency: 0,
                daysSinceLastArticle: Int.max,
                averageGapHours: 0,
                longestGapHours: 0,
                healthStatus: .dead
            )
        }

        let sorted = articles.sorted { $0.date < $1.date }
        let earliest = sorted.first!.date
        let latest = sorted.last!.date
        let daysSinceLast = max(0, Int(now.timeIntervalSince(latest) / 86400))

        let totalDays = max(1, now.timeIntervalSince(earliest) / 86400)
        let articlesPerDay = Double(articles.count) / totalDays

        // Calculate gaps between consecutive articles
        var gaps: [Double] = []
        for i in 1..<sorted.count {
            let gap = sorted[i].date.timeIntervalSince(sorted[i - 1].date) / 3600
            gaps.append(gap)
        }
        let avgGap = gaps.isEmpty ? 0 : gaps.reduce(0, +) / Double(gaps.count)
        let maxGap = gaps.max() ?? 0

        // Daily counts for consistency
        let calendar = Calendar.current
        var dailyCounts: [String: Int] = [:]
        for article in sorted {
            let key = Self.dayKey(article.date, calendar: calendar)
            dailyCounts[key, default: 0] += 1
        }
        let counts = Array(dailyCounts.values)
        let mean = Double(counts.reduce(0, +)) / Double(max(1, counts.count))
        let variance = counts.reduce(0.0) { $0 + pow(Double($1) - mean, 2) } / Double(max(1, counts.count))
        let stdDev = sqrt(variance)
        // Consistency: 1.0 = perfectly consistent, 0.0 = wildly inconsistent
        let consistency = mean > 0 ? max(0, 1.0 - stdDev / mean) : 0

        let healthStatus: FeedHealthStatus
        switch daysSinceLast {
        case 0...3:   healthStatus = .active
        case 4...14:  healthStatus = .slowing
        case 15...60: healthStatus = .stale
        default:      healthStatus = .dead
        }

        return PublishingMetrics(
            articleCount: articles.count,
            articlesPerDay: articlesPerDay,
            publishingConsistency: consistency,
            daysSinceLastArticle: daysSinceLast,
            averageGapHours: avgGap,
            longestGapHours: maxGap,
            healthStatus: healthStatus
        )
    }

    // MARK: - Content Quality Analysis

    func analyzeContent(
        articles: [(title: String, body: String, link: String, date: Date)]
    ) -> ContentQualityMetrics {
        guard !articles.isEmpty else {
            return ContentQualityMetrics(
                averageReadability: 0,
                averageWordCount: 0,
                medianWordCount: 0,
                substantiveRatio: 0,
                topicDiversity: 0,
                topKeywords: []
            )
        }

        var readabilityScores: [Double] = []
        var wordCounts: [Int] = []
        var keywordFreq: [String: Int] = [:]

        for article in articles {
            let text = article.title + " " + article.body
            let words = Self.extractWords(from: text)
            wordCounts.append(words.count)

            // Flesch Reading Ease (simplified)
            let sentences = max(1, Self.countSentences(in: text))
            let syllables = words.reduce(0) { $0 + Self.estimateSyllables($1) }
            let asl = Double(words.count) / Double(sentences)
            let asw = Double(syllables) / Double(max(1, words.count))
            let flesch = 206.835 - 1.015 * asl - 84.6 * asw
            readabilityScores.append(max(0, min(100, flesch)))

            // Keyword extraction
            for word in words {
                let lower = word.lowercased()
                if lower.count >= 3 && !Self.stopWords.contains(lower) {
                    keywordFreq[lower, default: 0] += 1
                }
            }
        }

        let avgReadability = readabilityScores.reduce(0, +) / Double(readabilityScores.count)
        let avgWordCount = Double(wordCounts.reduce(0, +)) / Double(wordCounts.count)
        let sortedWC = wordCounts.sorted()
        let medianWC = sortedWC[sortedWC.count / 2]
        let substantive = Double(wordCounts.filter { $0 > 100 }.count) / Double(wordCounts.count)

        let topKW = keywordFreq
            .sorted { $0.value > $1.value }
            .prefix(10)
            .map { (keyword: $0.key, count: $0.value) }

        // Topic diversity: unique keywords appearing 2+ times
        let diversity = keywordFreq.filter { $0.value >= 2 }.count

        return ContentQualityMetrics(
            averageReadability: avgReadability,
            averageWordCount: avgWordCount,
            medianWordCount: medianWC,
            substantiveRatio: substantive,
            topicDiversity: diversity,
            topKeywords: topKW
        )
    }

    // MARK: - Sentiment Analysis

    func analyzeSentiment(
        articles: [(title: String, body: String, link: String, date: Date)]
    ) -> SentimentProfile {
        guard !articles.isEmpty else {
            return SentimentProfile(
                averageSentiment: 0,
                positiveRatio: 0,
                negativeRatio: 0,
                neutralRatio: 1.0,
                volatility: 0,
                tone: "No data"
            )
        }

        var scores: [Double] = []
        for article in articles {
            let text = article.title + " " + article.body
            let score = Self.simpleSentiment(text)
            scores.append(score)
        }

        let avg = scores.reduce(0, +) / Double(scores.count)
        let positive = Double(scores.filter { $0 > 0.1 }.count) / Double(scores.count)
        let negative = Double(scores.filter { $0 < -0.1 }.count) / Double(scores.count)
        let neutral = 1.0 - positive - negative

        let variance = scores.reduce(0.0) { $0 + pow($1 - avg, 2) } / Double(scores.count)
        let volatility = sqrt(variance)

        let tone: String
        if avg > 0.3 {
            tone = "Very Positive"
        } else if avg > 0.1 {
            tone = "Positive"
        } else if avg > -0.1 {
            tone = "Neutral"
        } else if avg > -0.3 {
            tone = "Negative"
        } else {
            tone = "Very Negative"
        }

        return SentimentProfile(
            averageSentiment: avg,
            positiveRatio: positive,
            negativeRatio: negative,
            neutralRatio: neutral,
            volatility: volatility,
            tone: tone
        )
    }

    // MARK: - Engagement Analysis

    func analyzeEngagement(
        articles: [(title: String, body: String, link: String, date: Date)],
        readLinks: Set<String>,
        bookmarkedLinks: Set<String>,
        now: Date
    ) -> EngagementMetrics {
        guard !articles.isEmpty else {
            return EngagementMetrics(
                readRate: 0,
                articlesRead: 0,
                articlesBookmarked: 0,
                averageReadLagHours: 0
            )
        }

        let feedLinks = Set(articles.map { $0.link })
        let readFromFeed = feedLinks.intersection(readLinks)
        let bookmarkedFromFeed = feedLinks.intersection(bookmarkedLinks)

        let readRate = Double(readFromFeed.count) / Double(articles.count)

        // Estimate average read lag (proxy: time from publish to now / 2)
        // Real implementation would track actual read timestamps
        let avgLag: Double
        if !readFromFeed.isEmpty {
            let readArticles = articles.filter { readFromFeed.contains($0.link) }
            let totalLag = readArticles.reduce(0.0) { $0 + now.timeIntervalSince($1.date) / 3600 }
            avgLag = totalLag / Double(readArticles.count)
        } else {
            avgLag = 0
        }

        return EngagementMetrics(
            readRate: readRate,
            articlesRead: readFromFeed.count,
            articlesBookmarked: bookmarkedFromFeed.count,
            averageReadLagHours: avgLag
        )
    }

    // MARK: - Composite Score

    func computeComposite(
        publishing: PublishingMetrics,
        content: ContentQualityMetrics,
        engagement: EngagementMetrics,
        now: Date,
        daysSinceLast: Int
    ) -> Double {
        let total = max(0.01, weights.total)

        // Publishing score: articles per day mapped to 0-100
        // 0.5-5 articles/day is ideal range
        let pubScore: Double
        if publishing.articleCount == 0 {
            pubScore = 0
        } else {
            let freq = min(publishing.articlesPerDay / 2.0, 1.0) * 70 // up to 70 for frequency
            let consistency = publishing.publishingConsistency * 30     // up to 30 for consistency
            pubScore = freq + consistency
        }

        // Content quality score
        // Readability 40-70 is "standard" range (best for general audience)
        let readabilityScore: Double
        let r = content.averageReadability
        if r >= 30 && r <= 70 {
            readabilityScore = 40  // good range
        } else if r > 70 {
            readabilityScore = max(20, 40 - (r - 70) * 0.5)  // too easy = slightly lower
        } else {
            readabilityScore = max(10, 40 - (30 - r) * 1.0)  // too hard = lower
        }
        let substantiveScore = content.substantiveRatio * 30
        let diversityScore = min(Double(content.topicDiversity) / 20.0, 1.0) * 30
        let contentScore = readabilityScore + substantiveScore + diversityScore

        // Engagement score
        let engScore = engagement.readRate * 100

        // Freshness score: penalty for stale feeds
        let freshnessScore: Double
        switch daysSinceLast {
        case 0...3:   freshnessScore = 100
        case 4...7:   freshnessScore = 80
        case 8...14:  freshnessScore = 60
        case 15...30: freshnessScore = 40
        case 31...60: freshnessScore = 20
        default:      freshnessScore = 5
        }

        let composite = (
            pubScore * weights.publishing +
            contentScore * weights.contentQuality +
            engScore * weights.engagement +
            freshnessScore * weights.freshness
        ) / total

        return min(100, max(0, composite))
    }

    // MARK: - Recommendations

    func generateRecommendation(
        grade: FeedGrade,
        publishing: PublishingMetrics,
        content: ContentQualityMetrics,
        engagement: EngagementMetrics
    ) -> String {
        if publishing.healthStatus == .dead {
            return "This feed appears dead (no articles in 60+ days). Consider removing it."
        }
        if publishing.healthStatus == .stale {
            return "This feed has gone quiet. Check if it has moved to a new URL."
        }
        if engagement.readRate < 0.05 && publishing.articleCount > 10 {
            return "You rarely read this feed. Consider removing or recategorizing it."
        }
        if content.substantiveRatio < 0.3 {
            return "Most articles are very short. This feed may be low-quality or truncated."
        }

        switch grade {
        case .aPlus, .a:
            return "Excellent feed — active, readable, and engaging. Keep it!"
        case .bPlus, .b:
            if engagement.readRate < 0.3 {
                return "Good content but low read rate. Move to a higher-priority category?"
            }
            return "Solid feed. Content quality is good."
        case .cPlus, .c:
            if publishing.publishingConsistency < 0.3 {
                return "Publishing is inconsistent — articles come in bursts."
            }
            return "Average feed. Content could be better."
        case .d:
            return "Below average. Review whether this feed still matches your interests."
        case .f:
            return "Poor performance across the board. Consider unsubscribing."
        }
    }

    // MARK: - Text Utilities

    /// Extract words from text, stripping punctuation.
    static func extractWords(from text: String) -> [String] {
        let separated = text.components(separatedBy: CharacterSet.alphanumerics.inverted)
        return separated.filter { !$0.isEmpty }
    }

    /// Count sentences using period, question mark, exclamation mark.
    static func countSentences(in text: String) -> Int {
        let terminators = CharacterSet(charactersIn: ".!?")
        let parts = text.unicodeScalars.split { terminators.contains($0) }
        return max(1, parts.count)
    }

    /// Estimate syllable count for an English word.
    static func estimateSyllables(_ word: String) -> Int {
        let w = word.lowercased()
        if w.count <= 2 { return 1 }

        let vowels: Set<Character> = ["a", "e", "i", "o", "u", "y"]
        var count = 0
        var prevVowel = false

        for ch in w {
            if vowels.contains(ch) {
                if !prevVowel { count += 1 }
                prevVowel = true
            } else {
                prevVowel = false
            }
        }

        // Silent e
        if w.hasSuffix("e") && count > 1 { count -= 1 }
        // -le at end is a syllable
        if w.hasSuffix("le") && w.count > 2 && !vowels.contains(w[w.index(w.endIndex, offsetBy: -3)]) {
            count += 1
        }

        return max(1, count)
    }

    /// Simple lexicon-based sentiment scoring.
    static func simpleSentiment(_ text: String) -> Double {
        let positive: Set<String> = [
            "good", "great", "excellent", "amazing", "wonderful", "best",
            "love", "happy", "success", "win", "improve", "benefit",
            "strong", "positive", "growth", "innovative", "breakthrough",
            "impressive", "outstanding", "remarkable", "brilliant"
        ]
        let negative: Set<String> = [
            "bad", "worst", "terrible", "awful", "horrible", "hate",
            "fail", "loss", "problem", "crisis", "danger", "threat",
            "weak", "negative", "decline", "crash", "disaster",
            "alarming", "devastating", "catastrophic", "disappointing"
        ]

        let words = extractWords(from: text).map { $0.lowercased() }
        guard !words.isEmpty else { return 0 }

        var score = 0
        for word in words {
            if positive.contains(word) { score += 1 }
            if negative.contains(word) { score -= 1 }
        }

        // Normalize: cap at ±1.0
        return max(-1.0, min(1.0, Double(score) / max(1.0, sqrt(Double(words.count)))))
    }

    /// Format a date as "YYYY-MM-DD" for daily grouping.
    private static func dayKey(_ date: Date, calendar: Calendar) -> String {
        let comps = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", comps.year ?? 0, comps.month ?? 0, comps.day ?? 0)
    }
}
