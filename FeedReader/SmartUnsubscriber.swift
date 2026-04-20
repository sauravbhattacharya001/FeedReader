//
//  SmartUnsubscriber.swift
//  FeedReader
//
//  Autonomous feed subscription hygiene manager that analyzes
//  engagement patterns and proactively identifies feeds the user
//  should consider unsubscribing from. Detects:
//  - Dormant feeds (no new articles for extended periods)
//  - Ignored feeds (very low read rate)
//  - Declining engagement (EMA-based trend detection)
//  - Noise feeds (high volume, near-zero engagement)
//  - Duplicate coverage (keyword overlap via Jaccard similarity)
//
//  Produces an UnsubscribeReport with per-feed recommendations,
//  confidence scores, and an overall subscription health score.
//  Supports auto-mute for feeds ignored after recommendation.
//
//  All analysis on-device. No network calls or external deps.
//  Persistence: JSON file in Documents directory.
//

import Foundation

// MARK: - Notifications

extension Notification.Name {
    /// Posted when a new unsubscribe report is generated.
    static let unsubscribeReportDidUpdate = Notification.Name("UnsubscribeReportDidUpdateNotification")
}

// MARK: - Configuration

/// Configurable thresholds for unsubscribe analysis.
struct UnsubscribeConfig: Codable {
    /// Days without new articles to flag as dormant.
    var dormantDaysThreshold: Int = 30
    /// Read rate below which a feed is considered ignored (0-1).
    var ignoredReadRateThreshold: Double = 0.05
    /// EMA trend decline threshold to flag declining engagement.
    var engagementDeclineThreshold: Double = 0.4
    /// Articles per evaluation window above which feed is high-volume.
    var noiseVolumeThreshold: Int = 50
    /// Read rate below which a high-volume feed is noise (0-1).
    var noiseReadRateThreshold: Double = 0.03
    /// Jaccard similarity above which feeds are considered overlapping.
    var overlapSimilarityThreshold: Double = 0.6
    /// Days to look back for analysis.
    var evaluationWindowDays: Int = 30
    /// Whether to automatically mute feeds after recommendation period.
    var autoMuteEnabled: Bool = false
    /// Days after recommendation before auto-muting.
    var autoMuteAfterDays: Int = 14
}

// MARK: - Models

/// Reason for an unsubscribe recommendation.
enum UnsubscribeReason: String, Codable, CaseIterable {
    case dormant
    case ignored
    case decliningEngagement
    case noise
    case duplicateCoverage

    /// Human-readable description of the reason.
    var displayDescription: String {
        switch self {
        case .dormant: return "No new articles published recently"
        case .ignored: return "You rarely read articles from this feed"
        case .decliningEngagement: return "Your engagement with this feed is declining"
        case .noise: return "High volume with very low read rate"
        case .duplicateCoverage: return "Content overlaps significantly with other feeds"
        }
    }
}

/// Recommended action for a feed.
enum RecommendedAction: String, Codable {
    case unsubscribe
    case mute
    case reduceFrequency
    case monitor
}

/// Engagement statistics for a single feed.
struct FeedEngagementStats: Codable {
    let totalArticles: Int
    let readArticles: Int
    let readRate: Double
    let daysSinceLastArticle: Int
    let daysSinceLastRead: Int
    let avgArticlesPerDay: Double
    /// Negative values indicate declining engagement.
    let engagementTrend: Double
}

/// A single unsubscribe recommendation.
struct UnsubscribeRecommendation: Codable {
    let feedURL: String
    let feedTitle: String
    let reasons: [UnsubscribeReason]
    /// Confidence from 0 (low) to 1 (very confident).
    let confidenceScore: Double
    let recommendedAction: RecommendedAction
    let stats: FeedEngagementStats
    let firstRecommendedDate: Date
}

/// Full unsubscribe analysis report.
struct UnsubscribeReport: Codable {
    let generatedAt: Date
    let evaluationWindowDays: Int
    let totalFeedsAnalyzed: Int
    let recommendations: [UnsubscribeRecommendation]
    let healthyFeeds: Int
    let autoMutedFeeds: [String]
    /// Overall subscription health from 0 (poor) to 100 (excellent).
    let overallSubscriptionHealthScore: Int
    /// Dynamically generated top insight.
    let topInsight: String
}

/// Snapshot of a feed's recent state for analysis.
struct FeedSnapshot {
    let url: String
    let title: String
    let lastArticleDate: Date?
    let articleDates: [Date]
    /// Top keywords extracted from recent articles.
    let keywords: [String]
}

/// A single read event for analysis.
struct ReadHistoryEntry {
    let feedURL: String
    let articleDate: Date
    let readDate: Date
}

// MARK: - Persistence Models

/// Persisted state for tracking recommendations over time.
private struct UnsubscriberState: Codable {
    var config: UnsubscribeConfig
    var dismissedFeeds: [String: Date]
    var firstRecommendedDates: [String: Date]
    var autoMutedFeeds: [String]
    var reportHistory: [UnsubscribeReport]

    static var empty: UnsubscriberState {
        UnsubscriberState(
            config: UnsubscribeConfig(),
            dismissedFeeds: [:],
            firstRecommendedDates: [:],
            autoMutedFeeds: [],
            reportHistory: []
        )
    }
}

// MARK: - SmartUnsubscriber

/// Autonomous feed subscription hygiene manager.
final class SmartUnsubscriber {

    /// Shared singleton instance.
    static let shared = SmartUnsubscriber()

    private var state: UnsubscriberState
    private let persistenceURL: URL
    private let maxHistoryCount = 30

    private init() {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        self.persistenceURL = docs.appendingPathComponent("smart_unsubscriber_state.json")
        self.state = UnsubscriberState.empty
        loadState()
    }

    /// Current configuration.
    var config: UnsubscribeConfig {
        get { state.config }
        set { state.config = newValue; saveState() }
    }

    // MARK: - Public API

    /// Generate an unsubscribe report analyzing the given feeds and read history.
    func generateReport(feeds: [FeedSnapshot], readHistory: [ReadHistoryEntry]) -> UnsubscribeReport {
        let now = Date()
        let windowStart = Calendar.current.date(byAdding: .day, value: -state.config.evaluationWindowDays, to: now)!

        // Filter read history to evaluation window
        let recentReads = readHistory.filter { $0.readDate >= windowStart }

        // Build per-feed read counts
        var readCountsByFeed: [String: Int] = [:]
        for entry in recentReads {
            readCountsByFeed[entry.feedURL, default: 0] += 1
        }

        // Analyze each feed
        var recommendations: [UnsubscribeRecommendation] = []
        var healthyCount = 0

        for feed in feeds {
            // Skip dismissed feeds
            if let dismissDate = state.dismissedFeeds[feed.url],
               now.timeIntervalSince(dismissDate) < Double(state.config.evaluationWindowDays * 86400) {
                healthyCount += 1
                continue
            }

            let stats = computeStats(feed: feed, readCount: readCountsByFeed[feed.url] ?? 0, now: now, windowStart: windowStart)
            let reasons = detectReasons(feed: feed, stats: stats, allFeeds: feeds)

            if reasons.isEmpty {
                healthyCount += 1
            } else {
                let confidence = computeConfidence(reasons: reasons, stats: stats)
                let action = determineAction(reasons: reasons, confidence: confidence)

                // Track first recommended date
                if state.firstRecommendedDates[feed.url] == nil {
                    state.firstRecommendedDates[feed.url] = now
                }

                let rec = UnsubscribeRecommendation(
                    feedURL: feed.url,
                    feedTitle: feed.title,
                    reasons: reasons,
                    confidenceScore: confidence,
                    recommendedAction: action,
                    stats: stats,
                    firstRecommendedDate: state.firstRecommendedDates[feed.url] ?? now
                )
                recommendations.append(rec)
            }
        }

        // Sort by confidence descending
        let sorted = recommendations.sorted { $0.confidenceScore > $1.confidenceScore }

        // Auto-mute processing
        let newlyMuted = processAutoMute(recommendations: sorted, now: now)

        // Compute health score
        let healthScore = computeHealthScore(totalFeeds: feeds.count, healthyFeeds: healthyCount, recommendations: sorted)

        // Generate insight
        let insight = generateTopInsight(recommendations: sorted, healthScore: healthScore, totalFeeds: feeds.count)

        let report = UnsubscribeReport(
            generatedAt: now,
            evaluationWindowDays: state.config.evaluationWindowDays,
            totalFeedsAnalyzed: feeds.count,
            recommendations: sorted,
            healthyFeeds: healthyCount,
            autoMutedFeeds: newlyMuted,
            overallSubscriptionHealthScore: healthScore,
            topInsight: insight
        )

        // Persist
        state.reportHistory.insert(report, at: 0)
        if state.reportHistory.count > maxHistoryCount {
            state.reportHistory = Array(state.reportHistory.prefix(maxHistoryCount))
        }
        saveState()

        NotificationCenter.default.post(name: .unsubscribeReportDidUpdate, object: report)
        return report
    }

    /// Apply auto-mute to feeds that have been recommended for long enough.
    /// Returns URLs of newly muted feeds.
    func applyAutoMute(report: UnsubscribeReport) -> [String] {
        return processAutoMute(recommendations: report.recommendations, now: Date())
    }

    /// Dismiss a recommendation (user wants to keep the feed).
    func dismissRecommendation(feedURL: String) {
        state.dismissedFeeds[feedURL] = Date()
        state.firstRecommendedDates.removeValue(forKey: feedURL)
        saveState()
    }

    /// Get historical reports.
    func getHistory() -> [UnsubscribeReport] {
        return state.reportHistory
    }

    /// Get list of currently auto-muted feed URLs.
    func getAutoMutedFeeds() -> [String] {
        return state.autoMutedFeeds
    }

    /// Unmute a previously auto-muted feed.
    func unmuteFeed(url: String) {
        state.autoMutedFeeds.removeAll { $0 == url }
        saveState()
    }

    /// Reset all state (for testing or fresh start).
    func reset() {
        state = .empty
        saveState()
    }

    // MARK: - Analysis

    private func computeStats(feed: FeedSnapshot, readCount: Int, now: Date, windowStart: Date) -> FeedEngagementStats {
        let articlesInWindow = feed.articleDates.filter { $0 >= windowStart }.count
        let totalArticles = max(articlesInWindow, 1)
        let readRate = Double(readCount) / Double(totalArticles)

        let daysSinceLastArticle: Int
        if let lastDate = feed.lastArticleDate {
            daysSinceLastArticle = max(0, Int(now.timeIntervalSince(lastDate) / 86400))
        } else {
            daysSinceLastArticle = state.config.dormantDaysThreshold + 1
        }

        let windowDays = Double(state.config.evaluationWindowDays)
        let avgPerDay = Double(articlesInWindow) / max(windowDays, 1.0)

        // EMA-based engagement trend (compare weekly read rates)
        let trend = computeEngagementTrend(feedURL: feed.url, articleDates: feed.articleDates, readCount: readCount, windowStart: windowStart, now: now)

        return FeedEngagementStats(
            totalArticles: articlesInWindow,
            readArticles: readCount,
            readRate: readRate,
            daysSinceLastArticle: daysSinceLastArticle,
            daysSinceLastRead: daysSinceLastArticle, // simplified
            avgArticlesPerDay: avgPerDay,
            engagementTrend: trend
        )
    }

    private func computeEngagementTrend(feedURL: String, articleDates: [Date], readCount: Int, windowStart: Date, now: Date) -> Double {
        // Split window into weekly buckets and compute EMA
        let alpha = 0.3
        let weekCount = 4
        var weeklyRates: [Double] = []

        for week in 0..<weekCount {
            let weekEnd = Calendar.current.date(byAdding: .day, value: -(week * 7), to: now)!
            let weekStart = Calendar.current.date(byAdding: .day, value: -7, to: weekEnd)!
            let articlesThisWeek = articleDates.filter { $0 >= weekStart && $0 < weekEnd }.count
            // Approximate: distribute reads evenly (simplified)
            let readsThisWeek = articlesThisWeek > 0 ? Double(readCount) / Double(weekCount) : 0
            let rate = articlesThisWeek > 0 ? readsThisWeek / Double(articlesThisWeek) : 0
            weeklyRates.append(rate)
        }

        // EMA from oldest to newest
        guard !weeklyRates.isEmpty else { return 0.0 }
        let reversed = weeklyRates.reversed().map { $0 }
        var ema = reversed[0]
        for i in 1..<reversed.count {
            ema = alpha * reversed[i] + (1.0 - alpha) * ema
        }

        // Trend = newest rate vs EMA (negative = declining)
        let newest = weeklyRates[0]
        if ema == 0 { return 0.0 }
        return (newest - ema) / max(ema, 0.001)
    }

    private func detectReasons(feed: FeedSnapshot, stats: FeedEngagementStats, allFeeds: [FeedSnapshot]) -> [UnsubscribeReason] {
        var reasons: [UnsubscribeReason] = []
        let config = state.config

        // Dormant
        if stats.daysSinceLastArticle >= config.dormantDaysThreshold {
            reasons.append(.dormant)
        }

        // Ignored
        if stats.totalArticles > 0 && stats.readRate < config.ignoredReadRateThreshold {
            reasons.append(.ignored)
        }

        // Declining engagement
        if stats.engagementTrend < -config.engagementDeclineThreshold {
            reasons.append(.decliningEngagement)
        }

        // Noise
        if stats.totalArticles >= config.noiseVolumeThreshold && stats.readRate < config.noiseReadRateThreshold {
            reasons.append(.noise)
        }

        // Duplicate coverage (Jaccard similarity)
        if !feed.keywords.isEmpty {
            let feedKeywords = Set(feed.keywords.map { $0.lowercased() })
            for other in allFeeds where other.url != feed.url {
                let otherKeywords = Set(other.keywords.map { $0.lowercased() })
                let intersection = feedKeywords.intersection(otherKeywords).count
                let union = feedKeywords.union(otherKeywords).count
                if union > 0 {
                    let jaccard = Double(intersection) / Double(union)
                    if jaccard >= config.overlapSimilarityThreshold {
                        reasons.append(.duplicateCoverage)
                        break
                    }
                }
            }
        }

        return reasons
    }

    private func computeConfidence(reasons: [UnsubscribeReason], stats: FeedEngagementStats) -> Double {
        // Weighted confidence based on reason severity
        let weights: [UnsubscribeReason: Double] = [
            .dormant: 0.8,
            .ignored: 0.7,
            .decliningEngagement: 0.5,
            .noise: 0.9,
            .duplicateCoverage: 0.4
        ]

        var totalWeight = 0.0
        for reason in reasons {
            totalWeight += weights[reason] ?? 0.5
        }

        // Normalize to 0-1, boosted by multiple reasons
        let base = min(totalWeight / 1.5, 1.0)

        // Boost if read rate is very low
        let readRateBoost = stats.readRate < 0.01 ? 0.1 : 0.0

        return min(base + readRateBoost, 1.0)
    }

    private func determineAction(reasons: [UnsubscribeReason], confidence: Double) -> RecommendedAction {
        if confidence >= 0.8 {
            return .unsubscribe
        } else if confidence >= 0.6 || reasons.contains(.noise) {
            return .mute
        } else if reasons.contains(.decliningEngagement) {
            return .reduceFrequency
        } else {
            return .monitor
        }
    }

    private func processAutoMute(recommendations: [UnsubscribeRecommendation], now: Date) -> [String] {
        guard state.config.autoMuteEnabled else { return [] }

        var newlyMuted: [String] = []
        let muteThreshold = Double(state.config.autoMuteAfterDays * 86400)

        for rec in recommendations {
            guard rec.recommendedAction == .unsubscribe || rec.recommendedAction == .mute else { continue }
            guard !state.autoMutedFeeds.contains(rec.feedURL) else { continue }
            guard state.dismissedFeeds[rec.feedURL] == nil else { continue }

            if let firstDate = state.firstRecommendedDates[rec.feedURL],
               now.timeIntervalSince(firstDate) >= muteThreshold {
                state.autoMutedFeeds.append(rec.feedURL)
                newlyMuted.append(rec.feedURL)
            }
        }

        if !newlyMuted.isEmpty {
            saveState()
        }
        return newlyMuted
    }

    private func computeHealthScore(totalFeeds: Int, healthyFeeds: Int, recommendations: [UnsubscribeRecommendation]) -> Int {
        guard totalFeeds > 0 else { return 100 }

        let healthyRatio = Double(healthyFeeds) / Double(totalFeeds)
        let baseScore = Int(healthyRatio * 80.0)

        // Penalty for high-confidence unsubscribe recommendations
        let highConfCount = recommendations.filter { $0.confidenceScore >= 0.8 }.count
        let penalty = min(highConfCount * 5, 20)

        return max(0, min(100, baseScore + 20 - penalty))
    }

    private func generateTopInsight(recommendations: [UnsubscribeRecommendation], healthScore: Int, totalFeeds: Int) -> String {
        if recommendations.isEmpty {
            return "All \(totalFeeds) feeds are healthy — great subscription hygiene!"
        }

        let unsubCount = recommendations.filter { $0.recommendedAction == .unsubscribe }.count
        let dormantCount = recommendations.filter { $0.reasons.contains(.dormant) }.count
        let noiseCount = recommendations.filter { $0.reasons.contains(.noise) }.count

        if unsubCount > 0 {
            return "\(unsubCount) feed\(unsubCount == 1 ? "" : "s") can be safely removed — you haven't engaged with \(unsubCount == 1 ? "it" : "them") meaningfully."
        } else if dormantCount > 0 {
            return "\(dormantCount) feed\(dormantCount == 1 ? " has" : "s have") gone silent — consider removing dead weight."
        } else if noiseCount > 0 {
            return "\(noiseCount) noisy feed\(noiseCount == 1 ? " is" : "s are") drowning out content you care about."
        } else {
            return "Your subscription list could use some tidying — \(recommendations.count) feed\(recommendations.count == 1 ? " needs" : "s need") attention."
        }
    }

    // MARK: - Persistence

    private func loadState() {
        guard FileManager.default.fileExists(atPath: persistenceURL.path) else { return }
        do {
            let data = try Data(contentsOf: persistenceURL)
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            state = try decoder.decode(UnsubscriberState.self, from: data)
        } catch {
            state = .empty
        }
    }

    private func saveState() {
        do {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            encoder.outputFormatting = .prettyPrinted
            let data = try encoder.encode(state)
            try data.write(to: persistenceURL, options: .atomic)
        } catch {
            // Silent failure — non-critical persistence
        }
    }
}
