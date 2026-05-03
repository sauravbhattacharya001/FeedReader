//
//  FeedTopicRadar.swift
//  FeedReaderCore
//
//  Autonomous emerging topic detection engine that monitors topic
//  frequency across the user's RSS feed portfolio, detects bursts
//  and trends, classifies topic lifecycle phases, and generates
//  early-warning alerts when new subjects gain cross-feed traction.
//
//  Key capabilities:
//  - Tracks topic frequency across time windows with daily bucketing
//  - Burst detection via z-score analysis on daily mention rates
//  - Lifecycle phase classification: Emerging → Trending → Saturated → Declining → Dormant
//  - Cross-feed correlation (same topic appearing in N+ distinct feeds)
//  - Velocity (mentions/day slope) and acceleration tracking
//  - Early-warning alerts for bursts, phase transitions, cross-feed emergence
//  - Autonomous natural-language insights about the topic landscape
//  - Portfolio health scoring 0-100 with letter grades
//
//  Usage:
//  ```swift
//  let radar = FeedTopicRadar()
//
//  radar.recordObservation(topic: "swift concurrency",
//                          feedURL: "https://blog.example.com/feed",
//                          feedName: "Example Blog",
//                          articleId: "a1", timestamp: Date(),
//                          confidence: 0.9)
//
//  let scan = radar.scan()
//  print(scan.healthScore)       // 0-100
//  print(scan.emergingCount)     // topics in Emerging phase
//  print(scan.alerts)            // early-warning alerts
//  print(scan.insights)          // autonomous observations
//  ```
//
//  All processing is on-device. No network calls or external deps.
//

import Foundation

// MARK: - Topic Phase

/// Lifecycle phase of a detected topic.
public enum TopicPhase: String, CaseIterable, Comparable, Sendable {
    case emerging   = "Emerging"    // New topic, few mentions but accelerating
    case trending   = "Trending"    // Rapidly growing coverage
    case saturated  = "Saturated"   // Peak coverage, growth plateaued
    case declining  = "Declining"   // Coverage dropping
    case dormant    = "Dormant"     // Minimal recent activity

    private var ordinal: Int {
        switch self {
        case .emerging:  return 0
        case .trending:  return 1
        case .saturated: return 2
        case .declining: return 3
        case .dormant:   return 4
        }
    }

    public static func < (lhs: TopicPhase, rhs: TopicPhase) -> Bool {
        lhs.ordinal < rhs.ordinal
    }

    /// Emoji for display.
    public var emoji: String {
        switch self {
        case .emerging:  return "🌱"
        case .trending:  return "🔥"
        case .saturated: return "📊"
        case .declining: return "📉"
        case .dormant:   return "💤"
        }
    }
}

// MARK: - Alert Severity

/// Severity of a topic early-warning alert.
public enum TopicAlertSeverity: String, CaseIterable, Comparable, Sendable {
    case info        = "Info"
    case notable     = "Notable"
    case significant = "Significant"
    case critical    = "Critical"

    private var ordinal: Int {
        switch self {
        case .info:        return 0
        case .notable:     return 1
        case .significant: return 2
        case .critical:    return 3
        }
    }

    public static func < (lhs: TopicAlertSeverity, rhs: TopicAlertSeverity) -> Bool {
        lhs.ordinal < rhs.ordinal
    }

    public var emoji: String {
        switch self {
        case .info:        return "ℹ️"
        case .notable:     return "📢"
        case .significant: return "⚠️"
        case .critical:    return "🚨"
        }
    }
}

// MARK: - Topic Observation

/// A single topic mention extracted from an article.
public struct TopicObservation: Sendable {
    public let topic: String
    public let feedURL: String
    public let feedName: String
    public let articleId: String
    public let timestamp: Date
    public let confidence: Double

    public init(topic: String, feedURL: String, feedName: String,
                articleId: String = UUID().uuidString,
                timestamp: Date = Date(), confidence: Double = 1.0) {
        self.topic = topic.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        self.feedURL = feedURL
        self.feedName = feedName
        self.articleId = articleId
        self.timestamp = timestamp
        self.confidence = max(0, min(1, confidence))
    }
}

// MARK: - Topic Radar Report

/// Per-topic analysis result from a radar scan.
public struct TopicRadarReport: Sendable {
    public let topic: String
    public let phase: TopicPhase
    public let mentionCount: Int
    public let feedCount: Int
    public let velocity: Double
    public let acceleration: Double
    public let zScore: Double
    public let firstSeen: Date
    public let lastSeen: Date
    public let peakDate: Date?
    public let trendDirection: String

    public init(topic: String, phase: TopicPhase, mentionCount: Int,
                feedCount: Int, velocity: Double, acceleration: Double,
                zScore: Double, firstSeen: Date, lastSeen: Date,
                peakDate: Date?, trendDirection: String) {
        self.topic = topic
        self.phase = phase
        self.mentionCount = mentionCount
        self.feedCount = feedCount
        self.velocity = velocity
        self.acceleration = acceleration
        self.zScore = zScore
        self.firstSeen = firstSeen
        self.lastSeen = lastSeen
        self.peakDate = peakDate
        self.trendDirection = trendDirection
    }
}

// MARK: - Topic Alert

/// An early-warning alert for a significant topic event.
public struct TopicAlert: Sendable {
    public let topic: String
    public let severity: TopicAlertSeverity
    public let alertType: String
    public let message: String
    public let timestamp: Date

    public init(topic: String, severity: TopicAlertSeverity,
                alertType: String, message: String,
                timestamp: Date = Date()) {
        self.topic = topic
        self.severity = severity
        self.alertType = alertType
        self.message = message
        self.timestamp = timestamp
    }
}

// MARK: - Topic Insight

/// An autonomous observation about the topic landscape.
public struct TopicInsight: Sendable {
    public let category: String
    public let message: String
    public let relatedTopics: [String]
    public let confidence: Double

    public init(category: String, message: String,
                relatedTopics: [String] = [], confidence: Double = 0.8) {
        self.category = category
        self.message = message
        self.relatedTopics = relatedTopics
        self.confidence = max(0, min(1, confidence))
    }
}

// MARK: - Radar Scan Result

/// Complete result of a radar scan across the topic landscape.
public struct RadarScanResult: Sendable {
    public let timestamp: Date
    public let topicReports: [TopicRadarReport]
    public let alerts: [TopicAlert]
    public let insights: [TopicInsight]
    public let healthScore: Double
    public let healthGrade: String
    public let totalTopics: Int
    public let emergingCount: Int
    public let trendingCount: Int

    public init(timestamp: Date, topicReports: [TopicRadarReport],
                alerts: [TopicAlert], insights: [TopicInsight],
                healthScore: Double, healthGrade: String,
                totalTopics: Int, emergingCount: Int, trendingCount: Int) {
        self.timestamp = timestamp
        self.topicReports = topicReports
        self.alerts = alerts
        self.insights = insights
        self.healthScore = healthScore
        self.healthGrade = healthGrade
        self.totalTopics = totalTopics
        self.emergingCount = emergingCount
        self.trendingCount = trendingCount
    }
}

// MARK: - FeedTopicRadar

/// Autonomous emerging topic detection engine.
///
/// Records topic observations from articles, then performs radar scans
/// to detect bursts, classify lifecycle phases, generate alerts,
/// and produce natural-language insights.
public class FeedTopicRadar {

    // MARK: Configuration

    /// Z-score threshold for burst detection.
    public var burstZScoreThreshold: Double = 2.0

    /// Minimum distinct feeds for a topic to qualify as cross-feed emergence.
    public var emergenceMinFeeds: Int = 2

    /// Days without mentions before a topic is classified as dormant.
    public var dormantDays: Int = 14

    /// Minimum observations before a topic is included in reports.
    public var minimumObservations: Int = 3

    /// Analysis window in days.
    public var windowDays: Int = 30

    // MARK: Storage

    private var observations: [TopicObservation] = []
    private var previousAlerts: [TopicAlert] = []

    // MARK: Init

    public init() {}

    // MARK: Public API — Recording

    /// Record a topic observation.
    public func recordObservation(_ observation: TopicObservation) {
        observations.append(observation)
    }

    /// Convenience: record a topic observation from components.
    public func recordObservation(topic: String, feedURL: String, feedName: String,
                                  articleId: String = UUID().uuidString,
                                  timestamp: Date = Date(), confidence: Double = 1.0) {
        let obs = TopicObservation(topic: topic, feedURL: feedURL,
                                   feedName: feedName, articleId: articleId,
                                   timestamp: timestamp, confidence: confidence)
        recordObservation(obs)
    }

    // MARK: Public API — Analysis

    /// Run a full radar scan across the topic landscape.
    public func scan() -> RadarScanResult {
        let now = Date()
        let windowStart = Calendar.current.date(byAdding: .day, value: -windowDays, to: now) ?? now
        let windowObs = observations.filter { $0.timestamp >= windowStart }

        // Group observations by normalized topic
        let grouped = Dictionary(grouping: windowObs, by: { $0.topic })

        // Build reports for topics meeting minimumObservations
        var reports: [TopicRadarReport] = []
        var alerts: [TopicAlert] = []

        for (topic, obs) in grouped {
            guard obs.count >= minimumObservations else { continue }

            let feedURLs = Set(obs.map { $0.feedURL })
            let feedCount = feedURLs.count
            let timestamps = obs.map { $0.timestamp }
            let firstSeen = timestamps.min() ?? now
            let lastSeen = timestamps.max() ?? now

            // Daily buckets
            let dailyCounts = Self.dailyBuckets(observations: obs, windowStart: windowStart, now: now)
            let velocity = Self.computeVelocity(dailyCounts: dailyCounts)
            let acceleration = Self.computeAcceleration(dailyCounts: dailyCounts)
            let zScore = Self.computeZScore(dailyCounts: dailyCounts)
            let peakDate = Self.findPeakDate(observations: obs, windowStart: windowStart)
            let daysSinceLastSeen = Calendar.current.dateComponents([.day], from: lastSeen, to: now).day ?? 0

            // Phase classification
            let phase = Self.classifyPhase(
                velocity: velocity,
                acceleration: acceleration,
                zScore: zScore,
                feedCount: feedCount,
                mentionCount: obs.count,
                daysSinceLastSeen: daysSinceLastSeen,
                burstThreshold: burstZScoreThreshold,
                emergenceMinFeeds: emergenceMinFeeds,
                dormantDays: dormantDays
            )

            let trendDirection: String
            if acceleration > 0.05 {
                trendDirection = "accelerating"
            } else if acceleration < -0.05 {
                trendDirection = "decelerating"
            } else {
                trendDirection = "steady"
            }

            let report = TopicRadarReport(
                topic: topic, phase: phase, mentionCount: obs.count,
                feedCount: feedCount, velocity: velocity,
                acceleration: acceleration, zScore: zScore,
                firstSeen: firstSeen, lastSeen: lastSeen,
                peakDate: peakDate, trendDirection: trendDirection
            )
            reports.append(report)

            // Generate alerts
            let topicAlerts = Self.generateAlerts(
                topic: topic, phase: phase, velocity: velocity,
                acceleration: acceleration, zScore: zScore,
                feedCount: feedCount, burstThreshold: burstZScoreThreshold,
                emergenceMinFeeds: emergenceMinFeeds, now: now
            )
            alerts.append(contentsOf: topicAlerts)
        }

        // Sort by velocity descending
        reports.sort { abs($0.velocity) > abs($1.velocity) }

        let emergingCount = reports.filter { $0.phase == .emerging }.count
        let trendingCount = reports.filter { $0.phase == .trending }.count

        // Insights
        let insights = Self.generateInsights(reports: reports, alerts: alerts)

        // Health scoring
        let healthScore = Self.computeHealthScore(
            reports: reports, alerts: alerts,
            totalObservations: windowObs.count
        )
        let healthGrade = Self.gradeFromScore(healthScore)

        previousAlerts = alerts

        return RadarScanResult(
            timestamp: now, topicReports: reports,
            alerts: alerts, insights: insights,
            healthScore: healthScore, healthGrade: healthGrade,
            totalTopics: reports.count,
            emergingCount: emergingCount, trendingCount: trendingCount
        )
    }

    /// Get a report for a specific topic.
    public func topicReport(for topic: String) -> TopicRadarReport? {
        let result = scan()
        let normalized = topic.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        return result.topicReports.first { $0.topic == normalized }
    }

    /// Get only emerging topics.
    public func emergingTopics() -> [TopicRadarReport] {
        scan().topicReports.filter { $0.phase == .emerging }
    }

    /// Get alerts since a date.
    public func alerts(since date: Date) -> [TopicAlert] {
        scan().alerts.filter { $0.timestamp >= date }
    }

    /// Get topics appearing in at least `minFeeds` distinct feeds.
    public func crossFeedTopics(minFeeds: Int = 2) -> [TopicRadarReport] {
        scan().topicReports.filter { $0.feedCount >= minFeeds }
    }

    /// Clear all data.
    public func reset() {
        observations.removeAll()
        previousAlerts.removeAll()
    }

    /// Total number of recorded observations.
    public var observationCount: Int { observations.count }

    /// Number of distinct topics observed.
    public var topicCount: Int {
        Set(observations.map { $0.topic }).count
    }

    // MARK: - Private Helpers

    /// Build daily mention counts for a topic.
    private static func dailyBuckets(observations: [TopicObservation],
                                      windowStart: Date, now: Date) -> [Double] {
        let cal = Calendar.current
        let totalDays = max(1, (cal.dateComponents([.day], from: windowStart, to: now).day ?? 1))
        var buckets = [Double](repeating: 0, count: totalDays + 1)
        for obs in observations {
            let dayIndex = cal.dateComponents([.day], from: windowStart, to: obs.timestamp).day ?? 0
            let idx = max(0, min(totalDays, dayIndex))
            buckets[idx] += obs.confidence
        }
        return buckets
    }

    /// Compute velocity (mentions/day) via simple linear regression slope.
    private static func computeVelocity(dailyCounts: [Double]) -> Double {
        let n = Double(dailyCounts.count)
        guard n >= 2 else { return 0 }
        var sumX = 0.0, sumY = 0.0, sumXY = 0.0, sumX2 = 0.0
        for (i, y) in dailyCounts.enumerated() {
            let x = Double(i)
            sumX += x
            sumY += y
            sumXY += x * y
            sumX2 += x * x
        }
        let denom = n * sumX2 - sumX * sumX
        guard abs(denom) > 1e-12 else { return 0 }
        return (n * sumXY - sumX * sumY) / denom
    }

    /// Compute acceleration: velocity of recent half minus velocity of earlier half.
    private static func computeAcceleration(dailyCounts: [Double]) -> Double {
        guard dailyCounts.count >= 4 else { return 0 }
        let mid = dailyCounts.count / 2
        let firstHalf = Array(dailyCounts[0..<mid])
        let secondHalf = Array(dailyCounts[mid...])
        let v1 = computeVelocity(dailyCounts: firstHalf)
        let v2 = computeVelocity(dailyCounts: secondHalf)
        return v2 - v1
    }

    /// Compute z-score of the most recent day relative to the series mean/stddev.
    private static func computeZScore(dailyCounts: [Double]) -> Double {
        guard dailyCounts.count >= 2 else { return 0 }
        let recent = dailyCounts.last ?? 0
        let mean = dailyCounts.reduce(0, +) / Double(dailyCounts.count)
        let variance = dailyCounts.map { ($0 - mean) * ($0 - mean) }.reduce(0, +) / Double(dailyCounts.count)
        let stddev = sqrt(variance)
        guard stddev > 1e-12 else { return recent > mean ? 1.0 : 0.0 }
        return (recent - mean) / stddev
    }

    /// Find the date with the most mentions.
    private static func findPeakDate(observations: [TopicObservation],
                                      windowStart: Date) -> Date? {
        let cal = Calendar.current
        var dayToCount: [Int: (count: Int, date: Date)] = [:]
        for obs in observations {
            let dayIndex = cal.dateComponents([.day], from: windowStart, to: obs.timestamp).day ?? 0
            if let existing = dayToCount[dayIndex] {
                dayToCount[dayIndex] = (existing.count + 1, existing.date)
            } else {
                dayToCount[dayIndex] = (1, obs.timestamp)
            }
        }
        return dayToCount.max(by: { $0.value.count < $1.value.count })?.value.date
    }

    /// Classify a topic into a lifecycle phase.
    private static func classifyPhase(velocity: Double, acceleration: Double,
                                       zScore: Double, feedCount: Int,
                                       mentionCount: Int, daysSinceLastSeen: Int,
                                       burstThreshold: Double, emergenceMinFeeds: Int,
                                       dormantDays: Int) -> TopicPhase {
        if daysSinceLastSeen >= dormantDays {
            return .dormant
        }
        if velocity < -0.05 {
            return .declining
        }
        if zScore >= burstThreshold && feedCount >= emergenceMinFeeds && velocity > 0 {
            return .emerging
        }
        if velocity > 0.1 && mentionCount >= 5 {
            return .trending
        }
        if abs(velocity) <= 0.1 && mentionCount >= 5 {
            return .saturated
        }
        // Default: emerging if positive velocity, saturated otherwise
        if velocity > 0 {
            return .emerging
        }
        return .saturated
    }

    /// Generate alerts for a topic.
    private static func generateAlerts(topic: String, phase: TopicPhase,
                                        velocity: Double, acceleration: Double,
                                        zScore: Double, feedCount: Int,
                                        burstThreshold: Double,
                                        emergenceMinFeeds: Int,
                                        now: Date) -> [TopicAlert] {
        var alerts: [TopicAlert] = []

        // Burst detection
        if zScore >= burstThreshold {
            let severity: TopicAlertSeverity = zScore >= burstThreshold * 2
                ? .critical
                : zScore >= burstThreshold * 1.5
                    ? .significant
                    : .notable
            alerts.append(TopicAlert(
                topic: topic, severity: severity,
                alertType: "burst_detected",
                message: "Topic '\(topic)' is experiencing a burst (z-score: \(String(format: "%.1f", zScore)))",
                timestamp: now
            ))
        }

        // Cross-feed emergence
        if feedCount >= emergenceMinFeeds && phase == .emerging {
            alerts.append(TopicAlert(
                topic: topic, severity: .significant,
                alertType: "cross_feed_emergence",
                message: "Topic '\(topic)' is emerging across \(feedCount) distinct feeds",
                timestamp: now
            ))
        }

        // Velocity spike
        if acceleration > 0.2 {
            alerts.append(TopicAlert(
                topic: topic, severity: .notable,
                alertType: "velocity_spike",
                message: "Topic '\(topic)' is accelerating rapidly (accel: \(String(format: "%.2f", acceleration)))",
                timestamp: now
            ))
        }

        return alerts
    }

    /// Generate autonomous insights from scan results.
    private static func generateInsights(reports: [TopicRadarReport],
                                          alerts: [TopicAlert]) -> [TopicInsight] {
        var insights: [TopicInsight] = []
        guard !reports.isEmpty else {
            insights.append(TopicInsight(
                category: "status",
                message: "No topics meet the minimum observation threshold. Record more articles to see topic trends.",
                confidence: 1.0
            ))
            return insights
        }

        // Emergence insights
        let emerging = reports.filter { $0.phase == .emerging }
        if !emerging.isEmpty {
            let topEmerging = emerging.prefix(3).map { $0.topic }
            insights.append(TopicInsight(
                category: "emergence",
                message: "Detected \(emerging.count) emerging topic(s). Top: \(topEmerging.joined(separator: ", ")). These topics are gaining traction across multiple feeds.",
                relatedTopics: topEmerging,
                confidence: 0.85
            ))
        }

        // Trending insights
        let trending = reports.filter { $0.phase == .trending }
        if !trending.isEmpty {
            let topTrending = trending.prefix(3).map { $0.topic }
            insights.append(TopicInsight(
                category: "trend",
                message: "\(trending.count) topic(s) actively trending. Leaders: \(topTrending.joined(separator: ", ")).",
                relatedTopics: topTrending,
                confidence: 0.9
            ))
        }

        // Cross-feed convergence
        let crossFeed = reports.filter { $0.feedCount >= 3 }
        if !crossFeed.isEmpty {
            let convergent = crossFeed.prefix(3).map { $0.topic }
            insights.append(TopicInsight(
                category: "convergence",
                message: "\(crossFeed.count) topic(s) appearing across 3+ feeds, suggesting broad industry relevance.",
                relatedTopics: convergent,
                confidence: 0.88
            ))
        }

        // Declining topics
        let declining = reports.filter { $0.phase == .declining }
        if !declining.isEmpty {
            let topDeclining = declining.prefix(3).map { $0.topic }
            insights.append(TopicInsight(
                category: "decline",
                message: "\(declining.count) topic(s) losing momentum: \(topDeclining.joined(separator: ", ")).",
                relatedTopics: topDeclining,
                confidence: 0.8
            ))
        }

        // Dormant topics
        let dormant = reports.filter { $0.phase == .dormant }
        if !dormant.isEmpty {
            insights.append(TopicInsight(
                category: "dormancy",
                message: "\(dormant.count) topic(s) have gone dormant with no recent mentions.",
                confidence: 0.75
            ))
        }

        // Phase distribution insight
        let phaseDistribution = Dictionary(grouping: reports, by: { $0.phase })
        let phaseSummary = phaseDistribution.map { "\($0.key.rawValue): \($0.value.count)" }
            .sorted()
            .joined(separator: ", ")
        insights.append(TopicInsight(
            category: "landscape",
            message: "Topic landscape: \(reports.count) active topics. Distribution — \(phaseSummary).",
            confidence: 0.95
        ))

        // Alert volume insight
        if alerts.count > 5 {
            insights.append(TopicInsight(
                category: "anomaly",
                message: "High alert volume (\(alerts.count) alerts). Multiple topics experiencing significant activity shifts simultaneously.",
                confidence: 0.82
            ))
        }

        // Velocity extremes
        if let fastest = reports.first, fastest.velocity > 0 {
            insights.append(TopicInsight(
                category: "forecast",
                message: "Fastest-moving topic: '\(fastest.topic)' at \(String(format: "%.2f", fastest.velocity)) mentions/day. If this rate continues, expect \(String(format: "%.0f", fastest.velocity * 7)) additional mentions this week.",
                relatedTopics: [fastest.topic],
                confidence: 0.7
            ))
        }

        return insights
    }

    /// Compute portfolio health score (0-100).
    private static func computeHealthScore(reports: [TopicRadarReport],
                                            alerts: [TopicAlert],
                                            totalObservations: Int) -> Double {
        guard !reports.isEmpty else { return 0 }

        // Factor 1: Phase diversity (healthy portfolio has variety) — 30 pts
        let phases = Set(reports.map { $0.phase })
        let diversityScore = min(30.0, Double(phases.count) / Double(TopicPhase.allCases.count) * 30.0)

        // Factor 2: Emerging/trending ratio (sign of active landscape) — 25 pts
        let activeCount = reports.filter { $0.phase == .emerging || $0.phase == .trending }.count
        let activeRatio = Double(activeCount) / Double(reports.count)
        let activityScore = min(25.0, activeRatio * 25.0)

        // Factor 3: Cross-feed breadth (topics spanning multiple feeds) — 25 pts
        let crossFeedCount = reports.filter { $0.feedCount >= 2 }.count
        let crossFeedRatio = Double(crossFeedCount) / Double(max(1, reports.count))
        let breadthScore = min(25.0, crossFeedRatio * 25.0)

        // Factor 4: Observation volume (enough data for meaningful analysis) — 20 pts
        let volumeScore = min(20.0, Double(totalObservations) / 50.0 * 20.0)

        return min(100, max(0, diversityScore + activityScore + breadthScore + volumeScore))
    }

    /// Map a score to a letter grade.
    private static func gradeFromScore(_ score: Double) -> String {
        switch score {
        case 90...100: return "A"
        case 80..<90:  return "B"
        case 70..<80:  return "C"
        case 60..<70:  return "D"
        default:       return "F"
        }
    }
}
