//
//  FeedSubscriptionROI.swift
//  FeedReaderCore
//
//  Autonomous subscription return-on-investment engine that measures the
//  value each feed delivers relative to the attention it demands. Tracks
//  engagement metrics (read rate, dwell time, save/share actions), content
//  volume, and quality signals to compute a per-feed ROI score.
//
//  Key capabilities:
//  - Calculates per-feed ROI score 0-100 based on engagement vs. volume
//  - Classifies feeds into 5 ROI tiers (Platinum/Gold/Silver/Bronze/Deficit)
//  - Detects 6 subscription anti-patterns (zombie feed, firehose, guilt sub, etc.)
//  - Tracks ROI trends over time with momentum detection
//  - Generates autonomous prune/promote/adjust recommendations
//  - Portfolio-level subscription health scoring
//  - Optimal subscription count estimation
//
//  Usage:
//  ```swift
//  let roi = FeedSubscriptionROI()
//
//  roi.recordArticle(feedURL: "https://blog.example.com/feed",
//                    feedName: "Example Blog",
//                    wasRead: true, dwellSeconds: 180,
//                    wasSaved: true, wasShared: false)
//
//  let report = roi.analyzePortfolio()
//  print(report.portfolioHealth)       // 0-100
//  print(report.feedReports)           // per-feed ROI details
//  print(report.antiPatterns)          // detected problems
//  print(report.recommendations)       // autonomous suggestions
//  ```
//
//  All processing is on-device. No network calls or external deps.
//

import Foundation

// MARK: - ROI Tier

/// Return-on-investment classification for a feed subscription.
public enum ROITier: String, CaseIterable, Comparable, Sendable {
    case platinum = "Platinum"   // 85-100: Exceptional value
    case gold     = "Gold"       // 70-84:  High value
    case silver   = "Silver"     // 50-69:  Moderate value
    case bronze   = "Bronze"     // 30-49:  Low value
    case deficit  = "Deficit"    // 0-29:   Negative ROI

    public static func from(score: Double) -> ROITier {
        switch score {
        case 85...100: return .platinum
        case 70..<85:  return .gold
        case 50..<70:  return .silver
        case 30..<50:  return .bronze
        default:       return .deficit
        }
    }

    private var ordinal: Int {
        switch self {
        case .deficit:  return 0
        case .bronze:   return 1
        case .silver:   return 2
        case .gold:     return 3
        case .platinum: return 4
        }
    }

    public static func < (lhs: ROITier, rhs: ROITier) -> Bool {
        lhs.ordinal < rhs.ordinal
    }

    /// Emoji for display.
    public var emoji: String {
        switch self {
        case .platinum: return "💎"
        case .gold:     return "🥇"
        case .silver:   return "🥈"
        case .bronze:   return "🥉"
        case .deficit:  return "📉"
        }
    }
}

// MARK: - Subscription Anti-Pattern

/// Detected subscription usage anti-patterns.
public enum SubscriptionAntiPattern: String, CaseIterable, Sendable {
    /// Feed publishes but you never read it.
    case zombieFeed      = "zombie_feed"
    /// Feed publishes too much to keep up with.
    case firehose        = "firehose"
    /// You subscribe out of obligation, not interest.
    case guiltSub        = "guilt_subscription"
    /// Feed quality has declined but you haven't noticed.
    case boilingFrog     = "boiling_frog"
    /// Duplicate coverage — multiple feeds cover the same ground.
    case redundantCoverage = "redundant_coverage"
    /// Feed is dormant — hasn't published in a long time.
    case dormantFeed     = "dormant_feed"

    public var emoji: String {
        switch self {
        case .zombieFeed:        return "🧟"
        case .firehose:          return "🚿"
        case .guiltSub:          return "😬"
        case .boilingFrog:       return "🐸"
        case .redundantCoverage: return "♊"
        case .dormantFeed:       return "💤"
        }
    }

    public var description: String {
        switch self {
        case .zombieFeed:
            return "This feed publishes regularly but you rarely or never read its articles"
        case .firehose:
            return "This feed publishes more than you can keep up with, causing scroll fatigue"
        case .guiltSub:
            return "Low engagement despite reading — you skim out of obligation, not interest"
        case .boilingFrog:
            return "Engagement has been declining gradually over time"
        case .redundantCoverage:
            return "Multiple feeds in your portfolio cover the same topics"
        case .dormantFeed:
            return "This feed hasn't published new content recently"
        }
    }
}

// MARK: - Recommendation Action

/// Autonomous action suggestions for subscription management.
public enum ROIAction: String, CaseIterable, Sendable {
    case promote      = "promote"       // Increase visibility/priority
    case maintain     = "maintain"      // Keep as-is
    case monitor      = "monitor"       // Watch for further decline
    case reduce       = "reduce"        // Decrease check frequency
    case prune        = "prune"         // Unsubscribe

    public var emoji: String {
        switch self {
        case .promote:  return "⬆️"
        case .maintain: return "✅"
        case .monitor:  return "👁️"
        case .reduce:   return "⬇️"
        case .prune:    return "✂️"
        }
    }
}

// MARK: - Article Engagement Record

/// A single article engagement event for ROI tracking.
public struct ArticleEngagement: Sendable {
    public let feedURL: String
    public let feedName: String
    public let articleId: String
    public let timestamp: Date
    public let wasRead: Bool
    public let dwellSeconds: Double
    public let wasSaved: Bool
    public let wasShared: Bool
    public let topics: [String]

    public init(feedURL: String, feedName: String, articleId: String = UUID().uuidString,
                timestamp: Date = Date(), wasRead: Bool, dwellSeconds: Double = 0,
                wasSaved: Bool = false, wasShared: Bool = false, topics: [String] = []) {
        self.feedURL = feedURL
        self.feedName = feedName
        self.articleId = articleId
        self.timestamp = timestamp
        self.wasRead = wasRead
        self.dwellSeconds = max(0, dwellSeconds)
        self.wasSaved = wasSaved
        self.wasShared = wasShared
        self.topics = topics
    }
}

// MARK: - Feed ROI Report

/// ROI analysis for a single feed subscription.
public struct FeedROIReport: Sendable {
    public let feedURL: String
    public let feedName: String
    /// Composite ROI score 0-100.
    public let roiScore: Double
    /// Classification tier.
    public let tier: ROITier
    /// Total articles published.
    public let totalArticles: Int
    /// Articles actually read.
    public let articlesRead: Int
    /// Read rate (0-1).
    public let readRate: Double
    /// Average dwell time in seconds for read articles.
    public let avgDwellSeconds: Double
    /// Fraction of read articles that were saved.
    public let saveRate: Double
    /// Fraction of read articles that were shared.
    public let shareRate: Double
    /// Detected anti-patterns for this feed.
    public let antiPatterns: [SubscriptionAntiPattern]
    /// Recommended action.
    public let recommendation: ROIAction
    /// Human-readable recommendation text.
    public let recommendationText: String
    /// ROI trend direction: positive, negative, or stable.
    public let trend: String
    /// Per-topic engagement breakdown.
    public let topicBreakdown: [String: Double]

    public init(feedURL: String, feedName: String, roiScore: Double, tier: ROITier,
                totalArticles: Int, articlesRead: Int, readRate: Double,
                avgDwellSeconds: Double, saveRate: Double, shareRate: Double,
                antiPatterns: [SubscriptionAntiPattern], recommendation: ROIAction,
                recommendationText: String, trend: String,
                topicBreakdown: [String: Double]) {
        self.feedURL = feedURL
        self.feedName = feedName
        self.roiScore = roiScore
        self.tier = tier
        self.totalArticles = totalArticles
        self.articlesRead = articlesRead
        self.readRate = readRate
        self.avgDwellSeconds = avgDwellSeconds
        self.saveRate = saveRate
        self.shareRate = shareRate
        self.antiPatterns = antiPatterns
        self.recommendation = recommendation
        self.recommendationText = recommendationText
        self.trend = trend
        self.topicBreakdown = topicBreakdown
    }
}

// MARK: - Portfolio Report

/// Aggregate ROI analysis across all subscriptions.
public struct PortfolioROIReport: Sendable {
    /// Composite portfolio health score 0-100.
    public let portfolioHealth: Double
    /// Per-feed reports sorted by ROI score descending.
    public let feedReports: [FeedROIReport]
    /// All detected anti-patterns across the portfolio.
    public let antiPatterns: [(feed: String, pattern: SubscriptionAntiPattern)]
    /// Autonomous recommendations.
    public let recommendations: [String]
    /// Total subscriptions analyzed.
    public let totalFeeds: Int
    /// Estimated optimal subscription count.
    public let optimalFeedCount: Int
    /// Distribution across tiers.
    public let tierDistribution: [ROITier: Int]
    /// Overall read rate across all feeds.
    public let overallReadRate: Double
    /// Autonomous insights.
    public let insights: [String]

    public init(portfolioHealth: Double, feedReports: [FeedROIReport],
                antiPatterns: [(feed: String, pattern: SubscriptionAntiPattern)],
                recommendations: [String], totalFeeds: Int, optimalFeedCount: Int,
                tierDistribution: [ROITier: Int], overallReadRate: Double,
                insights: [String]) {
        self.portfolioHealth = portfolioHealth
        self.feedReports = feedReports
        self.antiPatterns = antiPatterns
        self.recommendations = recommendations
        self.totalFeeds = totalFeeds
        self.optimalFeedCount = optimalFeedCount
        self.tierDistribution = tierDistribution
        self.overallReadRate = overallReadRate
        self.insights = insights
    }
}

// MARK: - Feed Subscription ROI Engine

/// Autonomous subscription ROI analyzer.
///
/// Tracks engagement per feed and computes value-for-attention metrics,
/// detects anti-patterns, and generates portfolio-level recommendations.
public final class FeedSubscriptionROI: @unchecked Sendable {

    // MARK: - Storage

    private var engagements: [ArticleEngagement] = []
    private var roiHistory: [String: [Double]] = [:]  // feedURL → historical ROI scores
    private let lock = NSLock()

    // MARK: - Configuration

    /// Minimum articles before a feed is analyzed (below this → insufficient data).
    public var minimumArticles: Int = 5
    /// Weight for read rate in ROI calculation (0-1).
    public var readRateWeight: Double = 0.35
    /// Weight for dwell time in ROI calculation (0-1).
    public var dwellWeight: Double = 0.25
    /// Weight for save/share actions in ROI calculation (0-1).
    public var actionWeight: Double = 0.25
    /// Weight for consistency/trend in ROI calculation (0-1).
    public var trendWeight: Double = 0.15
    /// Firehose threshold — articles per week above this triggers detection.
    public var firehoseThreshold: Int = 30
    /// Zombie threshold — read rate below this triggers zombie detection.
    public var zombieReadRate: Double = 0.05
    /// Dormant threshold in days — no articles for this long triggers dormant.
    public var dormantDays: Int = 30
    /// Guilt threshold — read but low dwell time (seconds).
    public var guiltDwellThreshold: Double = 15.0
    /// Overlap threshold for redundant coverage detection (0-1).
    public var redundancyOverlap: Double = 0.6

    // MARK: - Init

    public init() {}

    // MARK: - Data Ingestion

    /// Record an article engagement event.
    public func recordArticle(feedURL: String, feedName: String,
                              articleId: String = UUID().uuidString,
                              timestamp: Date = Date(),
                              wasRead: Bool, dwellSeconds: Double = 0,
                              wasSaved: Bool = false, wasShared: Bool = false,
                              topics: [String] = []) {
        let engagement = ArticleEngagement(
            feedURL: feedURL, feedName: feedName, articleId: articleId,
            timestamp: timestamp, wasRead: wasRead, dwellSeconds: dwellSeconds,
            wasSaved: wasSaved, wasShared: wasShared, topics: topics
        )
        lock.lock()
        engagements.append(engagement)
        lock.unlock()
    }

    /// Bulk import engagement records.
    public func importEngagements(_ records: [ArticleEngagement]) {
        lock.lock()
        engagements.append(contentsOf: records)
        lock.unlock()
    }

    /// Clear all data.
    public func reset() {
        lock.lock()
        engagements.removeAll()
        roiHistory.removeAll()
        lock.unlock()
    }

    // MARK: - Single Feed Analysis

    /// Analyze ROI for a single feed.
    public func analyzeFeed(feedURL: String) -> FeedROIReport? {
        lock.lock()
        let feedRecords = engagements.filter { $0.feedURL == feedURL }
        lock.unlock()

        guard !feedRecords.isEmpty else { return nil }

        let feedName = feedRecords.last?.feedName ?? feedURL
        return computeFeedReport(feedURL: feedURL, feedName: feedName, records: feedRecords)
    }

    // MARK: - Portfolio Analysis

    /// Analyze the entire subscription portfolio.
    public func analyzePortfolio() -> PortfolioROIReport {
        lock.lock()
        let allRecords = engagements
        lock.unlock()

        // Group by feed
        var feedGroups: [String: [ArticleEngagement]] = [:]
        for record in allRecords {
            feedGroups[record.feedURL, default: []].append(record)
        }

        // Compute per-feed reports
        var feedReports: [FeedROIReport] = []
        for (url, records) in feedGroups {
            let name = records.last?.feedName ?? url
            let report = computeFeedReport(feedURL: url, feedName: name, records: records)
            feedReports.append(report)
        }
        feedReports.sort { $0.roiScore > $1.roiScore }

        // Store history
        lock.lock()
        for report in feedReports {
            roiHistory[report.feedURL, default: []].append(report.roiScore)
        }
        lock.unlock()

        // Detect portfolio-level anti-patterns
        var allAntiPatterns: [(feed: String, pattern: SubscriptionAntiPattern)] = []
        for report in feedReports {
            for ap in report.antiPatterns {
                allAntiPatterns.append((feed: report.feedName, pattern: ap))
            }
        }

        // Detect redundant coverage across feeds
        let redundancies = detectRedundantCoverage(feedGroups: feedGroups)
        allAntiPatterns.append(contentsOf: redundancies)

        // Tier distribution
        var tierDist: [ROITier: Int] = [:]
        for tier in ROITier.allCases { tierDist[tier] = 0 }
        for report in feedReports {
            tierDist[report.tier, default: 0] += 1
        }

        // Overall read rate
        let totalArticles = allRecords.count
        let totalRead = allRecords.filter { $0.wasRead }.count
        let overallReadRate = totalArticles > 0 ? Double(totalRead) / Double(totalArticles) : 0

        // Portfolio health: weighted average of feed ROIs + penalty for anti-patterns
        let avgROI = feedReports.isEmpty ? 0 :
            feedReports.reduce(0.0) { $0 + $1.roiScore } / Double(feedReports.count)
        let antiPatternPenalty = min(30.0, Double(allAntiPatterns.count) * 3.0)
        let portfolioHealth = max(0, min(100, avgROI - antiPatternPenalty))

        // Optimal feed count heuristic: feeds where readRate > 0.3
        let engagedFeeds = feedReports.filter { $0.readRate > 0.3 }.count
        let optimalCount = max(engagedFeeds, min(feedReports.count, max(5, Int(Double(feedReports.count) * overallReadRate * 2))))

        // Generate recommendations
        let recommendations = generatePortfolioRecommendations(
            feedReports: feedReports, antiPatterns: allAntiPatterns,
            overallReadRate: overallReadRate, optimalCount: optimalCount
        )

        // Generate insights
        let insights = generateInsights(
            feedReports: feedReports, tierDist: tierDist,
            overallReadRate: overallReadRate, portfolioHealth: portfolioHealth
        )

        return PortfolioROIReport(
            portfolioHealth: round(portfolioHealth * 10) / 10,
            feedReports: feedReports,
            antiPatterns: allAntiPatterns,
            recommendations: recommendations,
            totalFeeds: feedGroups.count,
            optimalFeedCount: optimalCount,
            tierDistribution: tierDist,
            overallReadRate: round(overallReadRate * 1000) / 1000,
            insights: insights
        )
    }

    // MARK: - Private: Compute Feed Report

    private func computeFeedReport(feedURL: String, feedName: String,
                                   records: [ArticleEngagement]) -> FeedROIReport {
        let total = records.count
        let readRecords = records.filter { $0.wasRead }
        let readCount = readRecords.count
        let readRate = total > 0 ? Double(readCount) / Double(total) : 0

        // Average dwell for read articles
        let avgDwell: Double
        if readCount > 0 {
            avgDwell = readRecords.reduce(0.0) { $0 + $1.dwellSeconds } / Double(readCount)
        } else {
            avgDwell = 0
        }

        // Save and share rates (among read articles)
        let saveCount = readRecords.filter { $0.wasSaved }.count
        let shareCount = readRecords.filter { $0.wasShared }.count
        let saveRate = readCount > 0 ? Double(saveCount) / Double(readCount) : 0
        let shareRate = readCount > 0 ? Double(shareCount) / Double(readCount) : 0

        // Per-topic engagement
        var topicEngagement: [String: (read: Int, total: Int)] = [:]
        for r in records {
            for t in r.topics {
                var entry = topicEngagement[t, default: (read: 0, total: 0)]
                entry.total += 1
                if r.wasRead { entry.read += 1 }
                topicEngagement[t] = entry
            }
        }
        var topicBreakdown: [String: Double] = [:]
        for (topic, counts) in topicEngagement {
            topicBreakdown[topic] = counts.total > 0 ? Double(counts.read) / Double(counts.total) : 0
        }

        // Compute composite ROI score
        let readRateScore = min(1.0, readRate / 0.8) * 100   // normalize: 80% read rate = perfect
        let dwellScore = min(1.0, avgDwell / 180.0) * 100     // normalize: 3 min avg = perfect
        let actionScore = (saveRate * 0.6 + shareRate * 0.4) * 100
        let trendScore = computeTrendScore(feedURL: feedURL, currentReadRate: readRate)

        let roiScore = max(0, min(100,
            readRateScore * readRateWeight +
            dwellScore * dwellWeight +
            actionScore * actionWeight +
            trendScore * trendWeight
        ))
        let tier = ROITier.from(score: roiScore)

        // Detect anti-patterns
        var antiPatterns: [SubscriptionAntiPattern] = []

        // Zombie feed: published but almost never read
        if total >= minimumArticles && readRate < zombieReadRate {
            antiPatterns.append(.zombieFeed)
        }

        // Firehose: too many articles per week
        if let earliest = records.map({ $0.timestamp }).min(),
           let latest = records.map({ $0.timestamp }).max() {
            let weeks = max(1, latest.timeIntervalSince(earliest) / (7 * 86400))
            let articlesPerWeek = Double(total) / weeks
            if articlesPerWeek > Double(firehoseThreshold) {
                antiPatterns.append(.firehose)
            }

            // Dormant feed: no recent articles
            let daysSinceLatest = Date().timeIntervalSince(latest) / 86400
            if daysSinceLatest > Double(dormantDays) {
                antiPatterns.append(.dormantFeed)
            }
        }

        // Guilt subscription: reads but very low dwell
        if readRate > 0.3 && avgDwell < guiltDwellThreshold && readCount >= minimumArticles {
            antiPatterns.append(.guiltSub)
        }

        // Boiling frog: declining trend
        lock.lock()
        let history = roiHistory[feedURL] ?? []
        lock.unlock()
        if history.count >= 3 {
            let recentHalf = Array(history.suffix(history.count / 2))
            let olderHalf = Array(history.prefix(history.count / 2))
            let recentAvg = recentHalf.reduce(0, +) / Double(recentHalf.count)
            let olderAvg = olderHalf.reduce(0, +) / Double(olderHalf.count)
            if olderAvg > 0 && (olderAvg - recentAvg) / olderAvg > 0.2 {
                antiPatterns.append(.boilingFrog)
            }
        }

        // Trend direction
        let trend: String
        if history.count >= 2 {
            let last = history.last ?? 0
            let prev = history[history.count - 2]
            if last > prev + 5 { trend = "improving" }
            else if last < prev - 5 { trend = "declining" }
            else { trend = "stable" }
        } else {
            trend = "new"
        }

        // Generate recommendation
        let (action, text) = generateRecommendation(
            tier: tier, antiPatterns: antiPatterns, readRate: readRate,
            feedName: feedName, trend: trend
        )

        return FeedROIReport(
            feedURL: feedURL, feedName: feedName,
            roiScore: round(roiScore * 10) / 10, tier: tier,
            totalArticles: total, articlesRead: readCount,
            readRate: round(readRate * 1000) / 1000,
            avgDwellSeconds: round(avgDwell * 10) / 10,
            saveRate: round(saveRate * 1000) / 1000,
            shareRate: round(shareRate * 1000) / 1000,
            antiPatterns: antiPatterns, recommendation: action,
            recommendationText: text, trend: trend,
            topicBreakdown: topicBreakdown
        )
    }

    // MARK: - Private: Trend Score

    private func computeTrendScore(feedURL: String, currentReadRate: Double) -> Double {
        lock.lock()
        let history = roiHistory[feedURL] ?? []
        lock.unlock()

        guard history.count >= 2 else { return 50.0 }  // neutral for new feeds

        let recentHalf = Array(history.suffix(max(1, history.count / 2)))
        let olderHalf = Array(history.prefix(max(1, history.count / 2)))

        let recentAvg = recentHalf.reduce(0, +) / Double(recentHalf.count)
        let olderAvg = olderHalf.reduce(0, +) / Double(olderHalf.count)

        if olderAvg == 0 { return recentAvg > 0 ? 75.0 : 50.0 }

        let changeRatio = (recentAvg - olderAvg) / olderAvg
        // Map [-0.5, +0.5] change ratio to [0, 100] score
        return max(0, min(100, 50.0 + changeRatio * 100.0))
    }

    // MARK: - Private: Recommendation

    private func generateRecommendation(tier: ROITier, antiPatterns: [SubscriptionAntiPattern],
                                        readRate: Double, feedName: String,
                                        trend: String) -> (ROIAction, String) {
        // Prune: deficit tier with zombie or dormant
        if tier == .deficit && (antiPatterns.contains(.zombieFeed) || antiPatterns.contains(.dormantFeed)) {
            return (.prune, "\(feedName) provides negligible value — consider unsubscribing to reduce noise")
        }

        // Reduce: low tier or firehose
        if tier <= .bronze || antiPatterns.contains(.firehose) {
            return (.reduce, "\(feedName) has low engagement ROI — reduce check frequency or filter to key topics")
        }

        // Monitor: declining trend
        if trend == "declining" {
            return (.monitor, "\(feedName) engagement is declining — monitor for further drops before taking action")
        }

        // Promote: high tier and improving
        if tier >= .gold && (trend == "improving" || trend == "stable") {
            return (.promote, "\(feedName) delivers strong value — consider prioritizing it in your reading queue")
        }

        // Maintain: everything else
        return (.maintain, "\(feedName) provides moderate value — keep in your current rotation")
    }

    // MARK: - Private: Redundant Coverage Detection

    private func detectRedundantCoverage(feedGroups: [String: [ArticleEngagement]])
        -> [(feed: String, pattern: SubscriptionAntiPattern)] {
        var results: [(feed: String, pattern: SubscriptionAntiPattern)] = []

        // Build topic profiles per feed
        var feedTopics: [String: Set<String>] = [:]
        var feedNames: [String: String] = [:]
        for (url, records) in feedGroups {
            let topics = Set(records.flatMap { $0.topics })
            if !topics.isEmpty {
                feedTopics[url] = topics
                feedNames[url] = records.last?.feedName ?? url
            }
        }

        // Compare all pairs
        let urls = Array(feedTopics.keys)
        var flagged: Set<String> = []
        for i in 0..<urls.count {
            for j in (i+1)..<urls.count {
                let a = feedTopics[urls[i]]!
                let b = feedTopics[urls[j]]!
                let intersection = a.intersection(b)
                let union = a.union(b)
                guard !union.isEmpty else { continue }
                let overlap = Double(intersection.count) / Double(union.count)
                if overlap >= redundancyOverlap {
                    if !flagged.contains(urls[i]) {
                        results.append((feed: feedNames[urls[i]] ?? urls[i], pattern: .redundantCoverage))
                        flagged.insert(urls[i])
                    }
                    if !flagged.contains(urls[j]) {
                        results.append((feed: feedNames[urls[j]] ?? urls[j], pattern: .redundantCoverage))
                        flagged.insert(urls[j])
                    }
                }
            }
        }

        return results
    }

    // MARK: - Private: Portfolio Recommendations

    private func generatePortfolioRecommendations(
        feedReports: [FeedROIReport],
        antiPatterns: [(feed: String, pattern: SubscriptionAntiPattern)],
        overallReadRate: Double,
        optimalCount: Int
    ) -> [String] {
        var recs: [String] = []

        // Prune candidates
        let pruneFeeds = feedReports.filter { $0.recommendation == .prune }
        if !pruneFeeds.isEmpty {
            let names = pruneFeeds.map { $0.feedName }.joined(separator: ", ")
            recs.append("✂️ Consider unsubscribing from \(pruneFeeds.count) low-value feed(s): \(names)")
        }

        // Overall read rate warning
        if overallReadRate < 0.2 {
            recs.append("📊 Your overall read rate is \(Int(overallReadRate * 100))% — you may be subscribed to more feeds than you can consume")
        }

        // Optimal count suggestion
        if feedReports.count > optimalCount + 3 {
            recs.append("🎯 Optimal subscription count estimated at ~\(optimalCount) feeds (you have \(feedReports.count))")
        }

        // Promote candidates
        let promoteFeeds = feedReports.filter { $0.recommendation == .promote }
        if !promoteFeeds.isEmpty {
            let names = promoteFeeds.prefix(3).map { $0.feedName }.joined(separator: ", ")
            recs.append("⬆️ Prioritize high-value feeds: \(names)")
        }

        // Firehose warnings
        let firehoseCount = antiPatterns.filter { $0.pattern == .firehose }.count
        if firehoseCount > 0 {
            recs.append("🚿 \(firehoseCount) feed(s) are firehoses — consider filtering or reducing check frequency")
        }

        // Redundancy warnings
        let redundantCount = antiPatterns.filter { $0.pattern == .redundantCoverage }.count
        if redundantCount > 0 {
            recs.append("♊ \(redundantCount) feed(s) have redundant topic coverage — consolidate to reduce noise")
        }

        if recs.isEmpty {
            recs.append("✅ Your subscription portfolio is well-balanced — no immediate actions needed")
        }

        return recs
    }

    // MARK: - Private: Insights

    private func generateInsights(feedReports: [FeedROIReport],
                                  tierDist: [ROITier: Int],
                                  overallReadRate: Double,
                                  portfolioHealth: Double) -> [String] {
        var insights: [String] = []

        // Top performer
        if let top = feedReports.first {
            insights.append("🏆 Top performer: \(top.feedName) with ROI score \(top.roiScore)")
        }

        // Bottom performer
        if feedReports.count > 1, let bottom = feedReports.last {
            insights.append("📉 Lowest ROI: \(bottom.feedName) with score \(bottom.roiScore)")
        }

        // Tier distribution insight
        let deficitCount = tierDist[.deficit] ?? 0
        let platinumCount = tierDist[.platinum] ?? 0
        if deficitCount > 0 {
            insights.append("⚠️ \(deficitCount) feed(s) are in deficit — costing attention without returning value")
        }
        if platinumCount > 0 {
            insights.append("💎 \(platinumCount) feed(s) deliver platinum-tier value — these are your knowledge anchors")
        }

        // Engagement spread
        if feedReports.count >= 3 {
            let scores = feedReports.map { $0.roiScore }
            let maxScore = scores.max() ?? 0
            let minScore = scores.min() ?? 0
            let spread = maxScore - minScore
            if spread > 60 {
                insights.append("📊 Wide ROI spread (\(Int(minScore))-\(Int(maxScore))) — your feeds vary dramatically in value")
            }
        }

        // Health bracket
        if portfolioHealth >= 80 {
            insights.append("🌟 Excellent portfolio health (\(Int(portfolioHealth))) — your subscriptions are well-curated")
        } else if portfolioHealth >= 60 {
            insights.append("👍 Good portfolio health (\(Int(portfolioHealth))) — some room for optimization")
        } else if portfolioHealth >= 40 {
            insights.append("⚠️ Fair portfolio health (\(Int(portfolioHealth))) — consider pruning low-value feeds")
        } else {
            insights.append("🚨 Poor portfolio health (\(Int(portfolioHealth))) — significant subscription cleanup recommended")
        }

        return insights
    }
}
