//
//  FeedIntelligenceBrief.swift
//  FeedReaderCore
//
//  Autonomous daily intelligence briefing generator that correlates
//  articles across feeds to produce a structured, prioritized brief.
//
//  Analyses include:
//  - Narrative thread detection (clustering articles by keyword overlap)
//  - Signal-to-noise assessment (clustered vs standalone articles)
//  - Emerging signal detection (new keywords vs previous period)
//  - Cross-feed correlation (topics spanning multiple sources)
//  - Blind spot identification (uncovered news categories)
//  - Actionable insight generation
//
//  Usage:
//  ```swift
//  let briefer = FeedIntelligenceBrief()
//  let brief = briefer.generateBrief(
//      articles: stories,
//      feedMap: feedMap,          // link → feed name
//      previousKeywords: lastPeriodKeywords
//  )
//  print(brief?.executiveSummary)
//  print(brief?.narrativeThreads)
//  print(brief?.actionableInsights)
//  ```
//
//  All processing is on-device. No network calls or external deps.
//

import Foundation

// MARK: - Intelligence Priority

/// Priority level for a detected narrative thread.
public enum IntelligencePriority: Int, Comparable, CaseIterable, Sendable {
    case critical = 0
    case high     = 1
    case medium   = 2
    case low      = 3
    case noise    = 4

    public static func < (lhs: IntelligencePriority, rhs: IntelligencePriority) -> Bool {
        return lhs.rawValue < rhs.rawValue
    }

    /// Emoji representation for display.
    public var emoji: String {
        switch self {
        case .critical: return "🔴"
        case .high:     return "🟠"
        case .medium:   return "🟡"
        case .low:      return "🔵"
        case .noise:    return "⚪"
        }
    }

    /// Human-readable description.
    public var displayName: String {
        switch self {
        case .critical: return "Critical"
        case .high:     return "High Priority"
        case .medium:   return "Medium Priority"
        case .low:      return "Low Priority"
        case .noise:    return "Noise"
        }
    }
}

// MARK: - Narrative Thread

/// A detected narrative or storyline spanning multiple articles.
public struct NarrativeThread: Sendable {
    /// Unique identifier derived from sorted keywords.
    public let id: String
    /// Auto-generated summary headline from top keywords.
    public let headline: String
    /// Keywords that define this narrative.
    public let keywords: [String]
    /// Number of articles in this thread.
    public let articleCount: Int
    /// Number of distinct feed sources contributing.
    public let sourceCount: Int
    /// Priority classification.
    public let priority: IntelligencePriority
    /// Momentum indicator: negative = fading, positive = accelerating.
    public let momentum: Double
    /// When the earliest article in this thread appeared.
    public let firstSeen: Date
    /// Articles belonging to this thread.
    public let articles: [RSSStory]
}

// MARK: - Signal / Noise Verdict

/// Assessment of the signal-to-noise ratio across the feed landscape.
public struct SignalNoiseVerdict: Sendable {
    /// Articles that belong to a narrative thread with 2+ articles.
    public let signalCount: Int
    /// Standalone articles not in any multi-article thread.
    public let noiseCount: Int
    /// Signal / total ratio (0.0–1.0).
    public let ratio: Double
    /// Human-readable grade.
    public let grade: String
}

// MARK: - Cross-Feed Correlation

/// A keyword appearing across multiple feed sources.
public struct CrossFeedCorrelation: Sendable {
    /// The correlated keyword.
    public let keyword: String
    /// Feed names where this keyword appeared.
    public let feedNames: [String]
    /// Total article count for this keyword.
    public let count: Int
}

// MARK: - Intelligence Brief

/// The final output: a structured intelligence briefing.
public struct IntelligenceBrief: Sendable {
    /// When this brief was generated.
    public let generatedAt: Date
    /// Start of the analysis period.
    public let periodStart: Date
    /// End of the analysis period.
    public let periodEnd: Date
    /// Detected narrative threads sorted by priority then momentum.
    public let narrativeThreads: [NarrativeThread]
    /// Top 15 cross-feed keywords.
    public let topKeywords: [String]
    /// Signal-to-noise assessment.
    public let signalNoise: SignalNoiseVerdict
    /// Topic categories with zero coverage.
    public let blindSpots: [String]
    /// Keywords appearing for the first time in this period.
    public let emergingSignals: [String]
    /// Keywords trending across multiple feeds.
    public let crossFeedCorrelations: [CrossFeedCorrelation]
    /// Auto-generated 2-3 sentence executive summary.
    public let executiveSummary: String
    /// Prioritized actionable insights for the reader.
    public let actionableInsights: [String]
}

// MARK: - Feed Intelligence Brief Engine

/// Autonomous intelligence briefing generator.
///
/// Correlates articles across feeds, clusters them into narrative threads,
/// assesses signal quality, detects emerging topics, and produces a
/// structured brief with actionable insights.
public class FeedIntelligenceBrief {

    // MARK: - Configuration

    /// Minimum articles required to generate a brief.
    public var minimumArticlesForBrief: Int = 5

    /// Keyword frequency threshold for signal classification.
    public var signalThreshold: Double = 0.3

    /// Maximum narrative threads to include in a brief.
    public var maxNarrativeThreads: Int = 10

    /// Common news categories for blind spot detection.
    public static let newsCategories: [String] = [
        "politics", "technology", "science", "health", "business",
        "sports", "entertainment", "environment", "education"
    ]

    /// Keyword extractor instance.
    private let extractor = KeywordExtractor()

    // MARK: - Initialization

    public init() {
        extractor.defaultCount = 8
    }

    // MARK: - Public API

    /// Generates a full intelligence brief from a set of articles.
    ///
    /// - Parameters:
    ///   - articles: All articles in the analysis period.
    ///   - feedMap: Maps article `link` → feed display name.
    ///   - previousKeywords: Keywords from the last briefing period (for emerging signal detection).
    /// - Returns: A structured `IntelligenceBrief`, or `nil` if too few articles.
    public func generateBrief(
        articles: [RSSStory],
        feedMap: [String: String] = [:],
        previousKeywords: Set<String> = []
    ) -> IntelligenceBrief? {
        guard articles.count >= minimumArticlesForBrief else { return nil }

        let now = Date()
        let threads = detectNarrativeThreads(articles: articles, feedMap: feedMap)
        let topThreads = Array(threads.prefix(maxNarrativeThreads))

        // Top keywords across all articles
        let allKeywords = extractAllKeywords(articles: articles)
        let topKW = Array(
            allKeywords.sorted { $0.value > $1.value }.prefix(15).map { $0.key }
        )

        let signalNoise = computeSignalNoise(threads: threads, totalArticles: articles.count)
        let emerging = detectEmergingSignals(
            currentKeywords: Set(allKeywords.keys),
            previousKeywords: previousKeywords
        )
        let correlations = findCrossFeedCorrelations(articles: articles, feedMap: feedMap)
        let blindSpots = detectBlindSpots(keywords: Set(allKeywords.keys))
        let summary = generateExecutiveSummary(threads: topThreads, signalNoise: signalNoise, emergingCount: emerging.count)
        let insights = generateActionableInsights(
            threads: topThreads,
            emerging: emerging,
            signalNoise: signalNoise,
            blindSpots: blindSpots,
            correlations: correlations
        )

        return IntelligenceBrief(
            generatedAt: now,
            periodStart: now.addingTimeInterval(-86400),
            periodEnd: now,
            narrativeThreads: topThreads,
            topKeywords: topKW,
            signalNoise: signalNoise,
            blindSpots: blindSpots,
            emergingSignals: emerging,
            crossFeedCorrelations: correlations,
            executiveSummary: summary,
            actionableInsights: insights
        )
    }

    // MARK: - Narrative Thread Detection

    /// Detects narrative threads by clustering articles with keyword overlap.
    ///
    /// Articles sharing 2+ keywords are grouped into the same thread via
    /// iterative union-find merging.
    ///
    /// - Parameters:
    ///   - articles: Articles to cluster.
    ///   - feedMap: Maps article link → feed name.
    /// - Returns: Sorted array of `NarrativeThread` (priority ascending, momentum descending).
    public func detectNarrativeThreads(
        articles: [RSSStory],
        feedMap: [String: String] = [:]
    ) -> [NarrativeThread] {
        guard !articles.isEmpty else { return [] }

        // Extract keywords per article
        let articleKeywords: [[String]] = articles.map { story in
            extractor.extractTags(from: story, count: 8)
        }

        // Union-Find for clustering
        var parent = Array(0..<articles.count)

        func find(_ x: Int) -> Int {
            var x = x
            while parent[x] != x {
                parent[x] = parent[parent[x]]
                x = parent[x]
            }
            return x
        }

        func union(_ a: Int, _ b: Int) {
            let ra = find(a)
            let rb = find(b)
            if ra != rb { parent[ra] = rb }
        }

        // Merge articles sharing 2+ keywords
        for i in 0..<articles.count {
            let setI = Set(articleKeywords[i])
            for j in (i + 1)..<articles.count {
                let setJ = Set(articleKeywords[j])
                if setI.intersection(setJ).count >= 2 {
                    union(i, j)
                }
            }
        }

        // Group by cluster root
        var clusters: [Int: [Int]] = [:]
        for i in 0..<articles.count {
            let root = find(i)
            clusters[root, default: []].append(i)
        }

        // Build narrative threads from clusters with 2+ articles
        var threads: [NarrativeThread] = []
        let now = Date()

        for (_, indices) in clusters where indices.count >= 2 {
            // Aggregate keywords
            var keywordFreq: [String: Int] = [:]
            var feedNames: Set<String> = []
            var clusterArticles: [RSSStory] = []

            for idx in indices {
                let story = articles[idx]
                clusterArticles.append(story)
                if let feedName = feedMap[story.link] {
                    feedNames.insert(feedName)
                }
                for kw in articleKeywords[idx] {
                    keywordFreq[kw, default: 0] += 1
                }
            }

            let sortedKW = keywordFreq.sorted { $0.value > $1.value }.map { $0.key }
            let topKW = Array(sortedKW.prefix(5))
            let headline = topKW.prefix(3).map { $0.capitalized }.joined(separator: " / ")

            // Momentum: compare first half vs second half article density
            let momentum = computeMomentum(indices: indices, totalCount: articles.count)

            let priority = classifyPriority(
                articleCount: indices.count,
                sourceCount: feedNames.count,
                momentum: momentum
            )

            let id = topKW.sorted().joined(separator: "-")

            threads.append(NarrativeThread(
                id: id,
                headline: headline,
                keywords: topKW,
                articleCount: indices.count,
                sourceCount: max(feedNames.count, 1),
                priority: priority,
                momentum: momentum,
                firstSeen: now.addingTimeInterval(-86400),
                articles: clusterArticles
            ))
        }

        // Sort: highest priority first, then highest momentum
        threads.sort { a, b in
            if a.priority != b.priority { return a.priority < b.priority }
            return a.momentum > b.momentum
        }

        return threads
    }

    // MARK: - Priority Classification

    /// Classifies a narrative thread's priority level.
    ///
    /// - Parameters:
    ///   - articleCount: Number of articles in the thread.
    ///   - sourceCount: Number of distinct feed sources.
    ///   - momentum: Momentum score (-1.0 to 1.0).
    /// - Returns: The priority classification.
    public func classifyPriority(
        articleCount: Int,
        sourceCount: Int,
        momentum: Double
    ) -> IntelligencePriority {
        // Composite score: weighted sum of factors
        let articleScore = min(Double(articleCount) / 10.0, 1.0)
        let sourceScore = min(Double(sourceCount) / 5.0, 1.0)
        let momentumScore = (momentum + 1.0) / 2.0  // normalize to 0–1

        let composite = articleScore * 0.4 + sourceScore * 0.35 + momentumScore * 0.25

        if composite >= 0.75 { return .critical }
        if composite >= 0.55 { return .high }
        if composite >= 0.35 { return .medium }
        if composite >= 0.15 { return .low }
        return .noise
    }

    // MARK: - Signal / Noise Analysis

    /// Computes the signal-to-noise ratio of the article landscape.
    ///
    /// Articles in narrative threads (2+ articles) are signal; standalone articles are noise.
    ///
    /// - Parameters:
    ///   - threads: Detected narrative threads.
    ///   - totalArticles: Total article count.
    /// - Returns: A `SignalNoiseVerdict`.
    public func computeSignalNoise(
        threads: [NarrativeThread],
        totalArticles: Int
    ) -> SignalNoiseVerdict {
        guard totalArticles > 0 else {
            return SignalNoiseVerdict(signalCount: 0, noiseCount: 0, ratio: 0, grade: "Critical")
        }

        let signalCount = threads.reduce(0) { $0 + $1.articleCount }
        let noiseCount = max(totalArticles - signalCount, 0)
        let ratio = Double(signalCount) / Double(totalArticles)

        let grade: String
        if ratio >= 0.8 { grade = "Excellent" }
        else if ratio >= 0.6 { grade = "Good" }
        else if ratio >= 0.4 { grade = "Fair" }
        else if ratio >= 0.2 { grade = "Poor" }
        else { grade = "Critical" }

        return SignalNoiseVerdict(
            signalCount: signalCount,
            noiseCount: noiseCount,
            ratio: ratio,
            grade: grade
        )
    }

    // MARK: - Emerging Signals

    /// Detects keywords appearing for the first time compared to the previous period.
    ///
    /// - Parameters:
    ///   - currentKeywords: Keywords extracted from the current period.
    ///   - previousKeywords: Keywords from the previous briefing period.
    /// - Returns: Sorted array of newly emerging keyword strings.
    public func detectEmergingSignals(
        currentKeywords: Set<String>,
        previousKeywords: Set<String>
    ) -> [String] {
        guard !previousKeywords.isEmpty else { return [] }
        return currentKeywords.subtracting(previousKeywords).sorted()
    }

    // MARK: - Cross-Feed Correlations

    /// Finds keywords that appear across multiple feed sources.
    ///
    /// - Parameters:
    ///   - articles: Articles to analyze.
    ///   - feedMap: Maps article link → feed name.
    /// - Returns: Correlations sorted by feed count descending, limited to those spanning 2+ feeds.
    public func findCrossFeedCorrelations(
        articles: [RSSStory],
        feedMap: [String: String]
    ) -> [CrossFeedCorrelation] {
        guard !feedMap.isEmpty else { return [] }

        // keyword → set of feed names
        var keywordFeeds: [String: Set<String>] = [:]
        // keyword → article count
        var keywordCounts: [String: Int] = [:]

        for story in articles {
            guard let feedName = feedMap[story.link] else { continue }
            let keywords = extractor.extractTags(from: story, count: 8)
            for kw in keywords {
                keywordFeeds[kw, default: []].insert(feedName)
                keywordCounts[kw, default: 0] += 1
            }
        }

        return keywordFeeds
            .filter { $0.value.count >= 2 }
            .map { kw, feeds in
                CrossFeedCorrelation(
                    keyword: kw,
                    feedNames: feeds.sorted(),
                    count: keywordCounts[kw] ?? 0
                )
            }
            .sorted { $0.feedNames.count > $1.feedNames.count }
    }

    // MARK: - Blind Spot Detection

    /// Identifies news categories with zero keyword coverage.
    ///
    /// - Parameter keywords: All extracted keywords from the current period.
    /// - Returns: Category names with no matches.
    public func detectBlindSpots(keywords: Set<String>) -> [String] {
        return FeedIntelligenceBrief.newsCategories.filter { category in
            !keywords.contains(category)
        }.sorted()
    }

    // MARK: - Executive Summary

    /// Generates a 2-3 sentence executive summary.
    ///
    /// - Parameters:
    ///   - threads: Top narrative threads.
    ///   - signalNoise: Signal-to-noise verdict.
    ///   - emergingCount: Number of emerging signals.
    /// - Returns: Summary string.
    public func generateExecutiveSummary(
        threads: [NarrativeThread],
        signalNoise: SignalNoiseVerdict,
        emergingCount: Int
    ) -> String {
        var parts: [String] = []

        if let top = threads.first {
            parts.append("Your feed landscape is dominated by \(top.headline).")
        } else {
            parts.append("Your feed landscape has no dominant narrative threads.")
        }

        parts.append("\(signalNoise.grade) signal-to-noise ratio with \(threads.count) active narrative\(threads.count == 1 ? "" : "s").")

        if emergingCount > 0 {
            parts.append("\(emergingCount) new signal\(emergingCount == 1 ? "" : "s") detected.")
        }

        return parts.joined(separator: " ")
    }

    // MARK: - Actionable Insights

    /// Generates prioritized actionable insights from the analysis.
    ///
    /// - Parameters:
    ///   - threads: Narrative threads.
    ///   - emerging: Emerging signal keywords.
    ///   - signalNoise: Signal-to-noise verdict.
    ///   - blindSpots: Uncovered categories.
    ///   - correlations: Cross-feed correlations.
    /// - Returns: Array of insight strings.
    public func generateActionableInsights(
        threads: [NarrativeThread],
        emerging: [String],
        signalNoise: SignalNoiseVerdict,
        blindSpots: [String] = [],
        correlations: [CrossFeedCorrelation] = []
    ) -> [String] {
        var insights: [String] = []

        // Accelerating threads
        for thread in threads where thread.momentum > 0.5 {
            insights.append("📈 '\(thread.headline)' is accelerating — worth close monitoring")
        }

        // Emerging signals (top 3)
        for kw in emerging.prefix(3) {
            insights.append("🆕 New topic '\(kw)' appearing for the first time")
        }

        // Signal-to-noise warning
        if signalNoise.grade == "Poor" || signalNoise.grade == "Critical" {
            insights.append("🔇 High noise level — consider pruning low-value feeds")
        }

        // Blind spots
        if !blindSpots.isEmpty {
            let categories = blindSpots.prefix(4).joined(separator: ", ")
            insights.append("🔍 No coverage in: \(categories) — consider adding feeds")
        }

        // Cross-feed trending
        for corr in correlations where corr.feedNames.count >= 3 {
            insights.append("🔗 '\(corr.keyword)' trending across \(corr.feedNames.count) feeds")
        }

        // Fading narratives
        for thread in threads where thread.momentum < -0.5 {
            insights.append("📉 '\(thread.headline)' is fading — may need less attention")
        }

        return insights
    }

    // MARK: - Private Helpers

    /// Extracts aggregated keyword frequencies across all articles.
    private func extractAllKeywords(articles: [RSSStory]) -> [String: Int] {
        var freq: [String: Int] = [:]
        freq.reserveCapacity(200)
        for story in articles {
            let keywords = extractor.extractTags(from: story, count: 8)
            for kw in keywords {
                freq[kw, default: 0] += 1
            }
        }
        return freq
    }

    /// Computes momentum from article position distribution.
    ///
    /// Positive momentum means more articles appear in the second half
    /// of the array (assumed to be more recent). Range: -1.0 to 1.0.
    private func computeMomentum(indices: [Int], totalCount: Int) -> Double {
        guard totalCount > 1 else { return 0.0 }
        let midpoint = totalCount / 2
        let firstHalf = indices.filter { $0 < midpoint }.count
        let secondHalf = indices.filter { $0 >= midpoint }.count
        let total = Double(firstHalf + secondHalf)
        guard total > 0 else { return 0.0 }
        return (Double(secondHalf) - Double(firstHalf)) / total
    }
}
