//
//  FeedHealthMonitor.swift
//  FeedReaderCore
//
//  Monitors RSS feed health: staleness detection, update frequency analysis,
//  consistency scoring, and health reports.
//

import Foundation

/// Health status level for a feed.
public enum FeedHealthStatus: String, Comparable, CaseIterable, Sendable {
    case healthy = "healthy"
    case warning = "warning"
    case stale = "stale"
    case dead = "dead"

    private var order: Int {
        switch self {
        case .healthy: return 3
        case .warning: return 2
        case .stale: return 1
        case .dead: return 0
        }
    }

    public static func < (lhs: FeedHealthStatus, rhs: FeedHealthStatus) -> Bool {
        return lhs.order < rhs.order
    }
}

/// Health check result for a single feed.
public struct FeedHealthResult: Sendable {
    /// Feed name.
    public let feedName: String
    /// Feed URL.
    public let feedURL: String
    /// Overall health status.
    public let status: FeedHealthStatus
    /// Health score 0-100.
    public let score: Int
    /// Days since last article was published.
    public let daysSinceLastArticle: Int?
    /// Average days between articles.
    public let averageUpdateInterval: Double?
    /// Total articles analyzed.
    public let articleCount: Int
    /// Issues found.
    public let issues: [String]
    /// Recommendations.
    public let recommendations: [String]
    /// Timestamp of the check.
    public let checkedAt: Date

    /// Text summary of the health result.
    public var summary: String {
        var lines: [String] = []
        let emoji: String
        switch status {
        case .healthy: emoji = "✅"
        case .warning: emoji = "⚠️"
        case .stale: emoji = "🟡"
        case .dead: emoji = "💀"
        }
        lines.append("\(emoji) \(feedName) — \(status.rawValue.uppercased()) (score: \(score)/100)")
        if let days = daysSinceLastArticle {
            lines.append("  Last article: \(days) day\(days == 1 ? "" : "s") ago")
        }
        if let interval = averageUpdateInterval {
            lines.append("  Avg update interval: \(String(format: "%.1f", interval)) days")
        }
        lines.append("  Articles analyzed: \(articleCount)")
        for issue in issues {
            lines.append("  ⛔ \(issue)")
        }
        for rec in recommendations {
            lines.append("  💡 \(rec)")
        }
        return lines.joined(separator: "\n")
    }
}

/// Aggregate health report across multiple feeds.
public struct FeedHealthReport: Sendable {
    /// Individual feed results.
    public let results: [FeedHealthResult]
    /// Overall health score (average).
    public let overallScore: Int
    /// Overall status (worst among feeds).
    public let overallStatus: FeedHealthStatus
    /// Count of feeds by status.
    public let statusCounts: [FeedHealthStatus: Int]
    /// Timestamp of the report.
    public let generatedAt: Date

    /// Text summary of the report.
    public var summary: String {
        var lines: [String] = []
        lines.append("═══ Feed Health Report ═══")
        lines.append("Generated: \(ISO8601DateFormatter().string(from: generatedAt))")
        lines.append("Overall: \(overallStatus.rawValue.uppercased()) (score: \(overallScore)/100)")
        lines.append("")
        for s in FeedHealthStatus.allCases.reversed() {
            let count = statusCounts[s] ?? 0
            if count > 0 {
                lines.append("  \(s.rawValue): \(count)")
            }
        }
        lines.append("")
        for result in results.sorted(by: { $0.score < $1.score }) {
            lines.append(result.summary)
            lines.append("")
        }
        return lines.joined(separator: "\n")
    }

    /// Export as JSON-compatible dictionary.
    public var jsonDict: [[String: Any]] {
        return results.map { r in
            var d: [String: Any] = [
                "feedName": r.feedName,
                "feedURL": r.feedURL,
                "status": r.status.rawValue,
                "score": r.score,
                "articleCount": r.articleCount,
                "issues": r.issues,
                "recommendations": r.recommendations,
                "checkedAt": ISO8601DateFormatter().string(from: r.checkedAt)
            ]
            if let days = r.daysSinceLastArticle { d["daysSinceLastArticle"] = days }
            if let interval = r.averageUpdateInterval { d["averageUpdateInterval"] = interval }
            return d
        }
    }
}

/// Configuration for health monitoring thresholds.
public struct FeedHealthConfig: Sendable {
    /// Days without new articles before "warning" status.
    public let warningDays: Int
    /// Days without new articles before "stale" status.
    public let staleDays: Int
    /// Days without new articles before "dead" status.
    public let deadDays: Int
    /// Minimum articles expected for a healthy feed.
    public let minimumArticleCount: Int
    /// Maximum acceptable average update interval in days.
    public let maxUpdateIntervalDays: Double

    public init(
        warningDays: Int = 7,
        staleDays: Int = 30,
        deadDays: Int = 90,
        minimumArticleCount: Int = 5,
        maxUpdateIntervalDays: Double = 14.0
    ) {
        self.warningDays = max(1, warningDays)
        self.staleDays = max(self.warningDays + 1, staleDays)
        self.deadDays = max(self.staleDays + 1, deadDays)
        self.minimumArticleCount = max(1, minimumArticleCount)
        self.maxUpdateIntervalDays = max(1.0, maxUpdateIntervalDays)
    }

    /// Default configuration.
    public static let `default` = FeedHealthConfig()
}

/// Monitors health of RSS feeds based on article publication patterns.
public class FeedHealthMonitor {

    /// Configuration thresholds.
    public let config: FeedHealthConfig

    /// Date provider for testability.
    private let now: () -> Date

    /// Creates a health monitor with optional configuration.
    public init(config: FeedHealthConfig = .default, now: @escaping () -> Date = { Date() }) {
        self.config = config
        self.now = now
    }

    // MARK: - Single Feed Check

    /// Check health of a single feed given its article dates.
    /// - Parameters:
    ///   - feedName: Display name of the feed.
    ///   - feedURL: URL of the feed.
    ///   - articleDates: Publication dates of articles (any order).
    /// - Returns: Health check result.
    public func checkFeed(feedName: String, feedURL: String, articleDates: [Date]) -> FeedHealthResult {
        let currentDate = now()
        let sorted = articleDates.sorted()
        var issues: [String] = []
        var recommendations: [String] = []
        var score = 100

        // Article count check
        let count = sorted.count
        if count == 0 {
            return FeedHealthResult(
                feedName: feedName, feedURL: feedURL,
                status: .dead, score: 0,
                daysSinceLastArticle: nil, averageUpdateInterval: nil,
                articleCount: 0,
                issues: ["No articles found"],
                recommendations: ["Verify the feed URL is correct", "Consider removing this feed"],
                checkedAt: currentDate
            )
        }

        if count < config.minimumArticleCount {
            issues.append("Low article count: \(count) (minimum: \(config.minimumArticleCount))")
            score -= 15
        }

        // Staleness check
        let lastDate = sorted.last!
        let daysSinceLast = Calendar.current.dateComponents([.day], from: lastDate, to: currentDate).day ?? 0
        let daysSincePositive = max(0, daysSinceLast)

        if daysSincePositive >= config.deadDays {
            issues.append("No updates in \(daysSincePositive) days — feed appears dead")
            score -= 60
        } else if daysSincePositive >= config.staleDays {
            issues.append("No updates in \(daysSincePositive) days — feed is stale")
            score -= 40
        } else if daysSincePositive >= config.warningDays {
            issues.append("No updates in \(daysSincePositive) days")
            score -= 20
        }

        // Update frequency analysis
        var avgInterval: Double? = nil
        if count >= 2 {
            var intervals: [Double] = []
            for i in 1..<sorted.count {
                let diff = sorted[i].timeIntervalSince(sorted[i - 1]) / 86400.0
                intervals.append(diff)
            }
            let avg = intervals.reduce(0, +) / Double(intervals.count)
            avgInterval = avg

            if avg > config.maxUpdateIntervalDays {
                issues.append("Infrequent updates: avg \(String(format: "%.1f", avg)) days between articles")
                score -= 15
            }

            // Irregularity check — high coefficient of variation
            if intervals.count >= 3 {
                let mean = avg
                let variance = intervals.map { ($0 - mean) * ($0 - mean) }.reduce(0, +) / Double(intervals.count)
                let stddev = sqrt(variance)
                let cv = mean > 0 ? stddev / mean : 0
                if cv > 1.5 {
                    issues.append("Highly irregular update schedule (CV: \(String(format: "%.2f", cv)))")
                    score -= 10
                }
            }
        }

        // Generate recommendations
        if daysSincePositive >= config.staleDays {
            recommendations.append("Consider replacing with an alternative feed")
        }
        if daysSincePositive >= config.warningDays && daysSincePositive < config.staleDays {
            recommendations.append("Monitor this feed — it may be slowing down")
        }
        if count < config.minimumArticleCount {
            recommendations.append("Feed may be new or have limited content")
        }
        if let avg = avgInterval, avg > config.maxUpdateIntervalDays {
            recommendations.append("Look for a more frequently updated feed in this category")
        }

        // Determine status
        let finalScore = max(0, min(100, score))
        let status: FeedHealthStatus
        if daysSincePositive >= config.deadDays || finalScore <= 20 {
            status = .dead
        } else if daysSincePositive >= config.staleDays || finalScore <= 40 {
            status = .stale
        } else if daysSincePositive >= config.warningDays || finalScore <= 70 {
            status = .warning
        } else {
            status = .healthy
        }

        return FeedHealthResult(
            feedName: feedName, feedURL: feedURL,
            status: status, score: finalScore,
            daysSinceLastArticle: daysSincePositive,
            averageUpdateInterval: avgInterval,
            articleCount: count,
            issues: issues, recommendations: recommendations,
            checkedAt: currentDate
        )
    }

    // MARK: - Multi-Feed Report

    /// Generate a health report for multiple feeds.
    /// - Parameter feeds: Array of tuples (name, url, articleDates).
    /// - Returns: Aggregate health report.
    public func generateReport(feeds: [(name: String, url: String, dates: [Date])]) -> FeedHealthReport {
        let results = feeds.map { checkFeed(feedName: $0.name, feedURL: $0.url, articleDates: $0.dates) }
        let overall = results.isEmpty ? 0 : results.map(\.score).reduce(0, +) / results.count
        let worst = results.map(\.status).min() ?? .healthy

        var counts: [FeedHealthStatus: Int] = [:]
        for r in results {
            counts[r.status, default: 0] += 1
        }

        return FeedHealthReport(
            results: results,
            overallScore: overall,
            overallStatus: worst,
            statusCounts: counts,
            generatedAt: now()
        )
    }

    // MARK: - Trend Detection

    /// Detect if a feed's update frequency is declining.
    /// Compares the average interval of the recent half vs older half.
    /// - Parameter articleDates: Publication dates.
    /// - Returns: Ratio > 1.0 means slowing down, < 1.0 means speeding up, nil if insufficient data.
    public func detectTrend(articleDates: [Date]) -> Double? {
        let sorted = articleDates.sorted()
        guard sorted.count >= 4 else { return nil }

        func intervals(_ dates: [Date]) -> [Double] {
            var result: [Double] = []
            for i in 1..<dates.count {
                result.append(dates[i].timeIntervalSince(dates[i - 1]) / 86400.0)
            }
            return result
        }

        let mid = sorted.count / 2
        let olderIntervals = intervals(Array(sorted[0...mid]))
        let recentIntervals = intervals(Array(sorted[mid...]))

        guard !olderIntervals.isEmpty, !recentIntervals.isEmpty else { return nil }
        let olderAvg = olderIntervals.reduce(0, +) / Double(olderIntervals.count)
        let recentAvg = recentIntervals.reduce(0, +) / Double(recentIntervals.count)

        guard olderAvg > 0 else { return nil }
        return recentAvg / olderAvg
    }
}
