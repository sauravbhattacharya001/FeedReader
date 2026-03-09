//
//  FeedSourceHealthMonitor.swift
//  FeedReader
//
//  Monitors the health and reliability of RSS/Atom feed sources.
//  Tracks update frequency, error rates, response times, content
//  staleness, and computes an overall health score per feed.
//
//  Key features:
//  - Record fetch results (success/failure with response time)
//  - Track update cadence and detect stale feeds
//  - Per-feed error rate and uptime percentage
//  - Health scoring (0-100) with letter grades
//  - Automatic feed status classification (healthy/degraded/stale/dead)
//  - Fleet-wide health dashboard summary
//  - Feed cleanup recommendations (dead feeds, chronically slow, etc.)
//  - Incident log for tracking recurring issues
//  - Export health report as JSON
//

import Foundation

// MARK: - Models

/// Result of a feed fetch attempt.
enum FetchResult: String, Codable, CaseIterable {
    case success = "success"
    case timeout = "timeout"
    case httpError = "http_error"
    case parseError = "parse_error"
    case networkError = "network_error"
    case dnsError = "dns_error"
    case sslError = "ssl_error"
}

/// Health status classification.
enum FeedHealthStatus: String, Codable, CaseIterable {
    case healthy = "healthy"         // 80-100 score
    case degraded = "degraded"       // 50-79 score
    case stale = "stale"             // feed not updated recently
    case unreliable = "unreliable"   // high error rate
    case dead = "dead"               // no successful fetch in threshold
}

/// Letter grade for health score.
enum HealthGrade: String, Codable, CaseIterable {
    case a = "A"
    case b = "B"
    case c = "C"
    case d = "D"
    case f = "F"

    static func from(score: Double) -> HealthGrade {
        switch score {
        case 90...100: return .a
        case 80..<90:  return .b
        case 65..<80:  return .c
        case 50..<65:  return .d
        default:       return .f
        }
    }
}

/// A single feed fetch event.
struct FetchEvent: Codable, Identifiable {
    let id: String
    let feedURL: String
    let date: Date
    let result: FetchResult
    let responseTimeMs: Int
    let httpStatus: Int?
    let newArticleCount: Int
    let errorMessage: String?
}

/// Per-feed health summary.
struct FeedHealthSummary: Codable {
    let feedURL: String
    let feedTitle: String
    let totalFetches: Int
    let successCount: Int
    let errorCount: Int
    let uptimePercent: Double
    let avgResponseTimeMs: Double
    let p95ResponseTimeMs: Int
    let healthScore: Double
    let grade: HealthGrade
    let status: FeedHealthStatus
    let lastSuccessDate: Date?
    let lastErrorDate: Date?
    let lastNewContentDate: Date?
    let avgUpdateIntervalHours: Double?
    let daysSinceLastUpdate: Int?
    let errorBreakdown: [FetchResult: Int]
    let recommendation: String?
}

/// Fleet-wide health dashboard.
struct FleetHealthDashboard: Codable {
    let totalFeeds: Int
    let healthyCount: Int
    let degradedCount: Int
    let staleCount: Int
    let unreliableCount: Int
    let deadCount: Int
    let fleetUptimePercent: Double
    let avgHealthScore: Double
    let avgResponseTimeMs: Double
    let feedsNeedingAttention: [FeedHealthSummary]
    let topPerformers: [FeedHealthSummary]
}

/// An incident record for a feed.
struct FeedIncident: Codable, Identifiable {
    let id: String
    let feedURL: String
    let startDate: Date
    var endDate: Date?
    let errorType: FetchResult
    var consecutiveErrors: Int
    var isResolved: Bool
}

// MARK: - FeedSourceHealthMonitor

/// Monitors reliability and health of feed sources.
class FeedSourceHealthMonitor {

    private var fetchEvents: [FetchEvent] = []
    private var feedTitles: [String: String] = [:]
    private var incidents: [FeedIncident] = []
    private var consecutiveErrors: [String: Int] = [:]

    /// Staleness threshold: days without new content.
    let staleThresholdDays: Int
    /// Dead feed threshold: days since last successful fetch.
    let deadThresholdDays: Int
    /// Slow response threshold (ms).
    let slowResponseMs: Int

    init(staleThresholdDays: Int = 14,
         deadThresholdDays: Int = 30,
         slowResponseMs: Int = 5000) {
        self.staleThresholdDays = max(1, staleThresholdDays)
        self.deadThresholdDays = max(1, deadThresholdDays)
        self.slowResponseMs = max(100, slowResponseMs)
    }

    // MARK: - Recording

    /// Record a feed fetch result.
    @discardableResult
    func recordFetch(feedURL: String,
                     feedTitle: String? = nil,
                     result: FetchResult,
                     responseTimeMs: Int,
                     httpStatus: Int? = nil,
                     newArticleCount: Int = 0,
                     errorMessage: String? = nil,
                     date: Date = Date()) -> FetchEvent {
        if let title = feedTitle {
            feedTitles[feedURL] = title
        }

        let event = FetchEvent(
            id: UUID().uuidString,
            feedURL: feedURL,
            date: date,
            result: result,
            responseTimeMs: max(0, responseTimeMs),
            httpStatus: httpStatus,
            newArticleCount: max(0, newArticleCount),
            errorMessage: errorMessage
        )
        fetchEvents.append(event)

        // Track consecutive errors for incident detection
        if result != .success {
            let count = (consecutiveErrors[feedURL] ?? 0) + 1
            consecutiveErrors[feedURL] = count

            if count == 3 {
                // Open incident after 3 consecutive errors
                let incident = FeedIncident(
                    id: UUID().uuidString,
                    feedURL: feedURL,
                    startDate: date,
                    endDate: nil,
                    errorType: result,
                    consecutiveErrors: count,
                    isResolved: false
                )
                incidents.append(incident)
            } else if count > 3 {
                // Update existing incident
                if let idx = incidents.lastIndex(where: {
                    $0.feedURL == feedURL && !$0.isResolved
                }) {
                    incidents[idx].consecutiveErrors = count
                }
            }
        } else {
            // Resolve open incidents on success
            if let count = consecutiveErrors[feedURL], count >= 3 {
                if let idx = incidents.lastIndex(where: {
                    $0.feedURL == feedURL && !$0.isResolved
                }) {
                    incidents[idx].endDate = date
                    incidents[idx].isResolved = true
                }
            }
            consecutiveErrors[feedURL] = 0
        }

        return event
    }

    // MARK: - Per-Feed Health

    /// Compute health summary for a specific feed.
    func healthSummary(for feedURL: String) -> FeedHealthSummary? {
        let events = fetchEvents.filter { $0.feedURL == feedURL }
        guard !events.isEmpty else { return nil }

        let sorted = events.sorted { $0.date < $1.date }
        let successes = events.filter { $0.result == .success }
        let errors = events.filter { $0.result != .success }

        let uptimePercent = Double(successes.count) / Double(events.count) * 100.0
        let avgResponseMs = Double(events.map { $0.responseTimeMs }.reduce(0, +))
            / Double(events.count)

        // P95 response time
        let sortedTimes = events.map { $0.responseTimeMs }.sorted()
        let p95Index = min(Int(Double(sortedTimes.count) * 0.95), sortedTimes.count - 1)
        let p95 = sortedTimes[p95Index]

        // Last dates
        let lastSuccess = successes.max(by: { $0.date < $1.date })?.date
        let lastError = errors.max(by: { $0.date < $1.date })?.date

        // Last new content date
        let lastNewContent = successes
            .filter { $0.newArticleCount > 0 }
            .max(by: { $0.date < $1.date })?.date

        // Update interval: average gap between fetches with new content
        let contentDates = successes
            .filter { $0.newArticleCount > 0 }
            .map { $0.date }
            .sorted()
        var avgInterval: Double? = nil
        if contentDates.count >= 2 {
            var totalGap = 0.0
            for i in 1..<contentDates.count {
                totalGap += contentDates[i].timeIntervalSince(contentDates[i - 1])
            }
            avgInterval = (totalGap / Double(contentDates.count - 1)) / 3600.0
        }

        // Days since last update
        var daysSince: Int? = nil
        if let lcd = lastNewContent {
            daysSince = max(0, Calendar.current.dateComponents(
                [.day], from: lcd, to: Date()
            ).day ?? 0)
        }

        // Error breakdown
        var errorBreakdown: [FetchResult: Int] = [:]
        for e in errors {
            errorBreakdown[e.result, default: 0] += 1
        }

        // Health score (0-100)
        let score = computeHealthScore(
            uptimePercent: uptimePercent,
            avgResponseMs: avgResponseMs,
            daysSinceUpdate: daysSince,
            errorCount: errors.count,
            totalFetches: events.count
        )

        let status = classifyStatus(
            score: score,
            daysSinceUpdate: daysSince,
            uptimePercent: uptimePercent,
            lastSuccess: lastSuccess
        )

        let recommendation = generateRecommendation(
            status: status,
            uptimePercent: uptimePercent,
            avgResponseMs: avgResponseMs,
            daysSinceUpdate: daysSince,
            errorBreakdown: errorBreakdown
        )

        return FeedHealthSummary(
            feedURL: feedURL,
            feedTitle: feedTitles[feedURL] ?? feedURL,
            totalFetches: events.count,
            successCount: successes.count,
            errorCount: errors.count,
            uptimePercent: round(uptimePercent * 10) / 10,
            avgResponseTimeMs: round(avgResponseMs * 10) / 10,
            p95ResponseTimeMs: p95,
            healthScore: round(score * 10) / 10,
            grade: HealthGrade.from(score: score),
            status: status,
            lastSuccessDate: lastSuccess,
            lastErrorDate: lastError,
            lastNewContentDate: lastNewContent,
            avgUpdateIntervalHours: avgInterval.map { round($0 * 10) / 10 },
            daysSinceLastUpdate: daysSince,
            errorBreakdown: errorBreakdown,
            recommendation: recommendation
        )
    }

    // MARK: - Fleet Dashboard

    /// Generate fleet-wide health dashboard.
    func fleetDashboard() -> FleetHealthDashboard {
        let feedURLs = Set(fetchEvents.map { $0.feedURL })
        let summaries = feedURLs.compactMap { healthSummary(for: $0) }

        let healthy = summaries.filter { $0.status == .healthy }.count
        let degraded = summaries.filter { $0.status == .degraded }.count
        let stale = summaries.filter { $0.status == .stale }.count
        let unreliable = summaries.filter { $0.status == .unreliable }.count
        let dead = summaries.filter { $0.status == .dead }.count

        let totalSuccess = summaries.map { $0.successCount }.reduce(0, +)
        let totalFetches = summaries.map { $0.totalFetches }.reduce(0, +)
        let fleetUptime = totalFetches > 0
            ? Double(totalSuccess) / Double(totalFetches) * 100
            : 0

        let avgScore = summaries.isEmpty
            ? 0 : summaries.map { $0.healthScore }.reduce(0, +) / Double(summaries.count)
        let avgResponse = summaries.isEmpty
            ? 0 : summaries.map { $0.avgResponseTimeMs }.reduce(0, +) / Double(summaries.count)

        let needsAttention = summaries
            .filter { $0.status != .healthy }
            .sorted { $0.healthScore < $1.healthScore }

        let topPerformers = summaries
            .sorted { $0.healthScore > $1.healthScore }
            .prefix(5)

        return FleetHealthDashboard(
            totalFeeds: summaries.count,
            healthyCount: healthy,
            degradedCount: degraded,
            staleCount: stale,
            unreliableCount: unreliable,
            deadCount: dead,
            fleetUptimePercent: round(fleetUptime * 10) / 10,
            avgHealthScore: round(avgScore * 10) / 10,
            avgResponseTimeMs: round(avgResponse * 10) / 10,
            feedsNeedingAttention: Array(needsAttention.prefix(10)),
            topPerformers: Array(topPerformers)
        )
    }

    // MARK: - Incidents

    /// Get all incidents, optionally filtered by feed URL.
    func getIncidents(feedURL: String? = nil, unresolvedOnly: Bool = false) -> [FeedIncident] {
        var result = incidents
        if let url = feedURL {
            result = result.filter { $0.feedURL == url }
        }
        if unresolvedOnly {
            result = result.filter { !$0.isResolved }
        }
        return result.sorted { $0.startDate > $1.startDate }
    }

    // MARK: - Cleanup Recommendations

    /// Get feeds recommended for removal/review.
    func cleanupRecommendations() -> [(feedURL: String, reason: String, score: Double)] {
        let feedURLs = Set(fetchEvents.map { $0.feedURL })
        var recommendations: [(feedURL: String, reason: String, score: Double)] = []

        for url in feedURLs {
            guard let summary = healthSummary(for: url) else { continue }

            if summary.status == .dead {
                recommendations.append((url, "Feed appears dead — no successful fetches recently", summary.healthScore))
            } else if summary.status == .unreliable && summary.uptimePercent < 30 {
                recommendations.append((url, "Chronically unreliable — \(Int(summary.uptimePercent))% uptime", summary.healthScore))
            } else if summary.status == .stale {
                let days = summary.daysSinceLastUpdate ?? staleThresholdDays
                recommendations.append((url, "Stale — no new content in \(days) days", summary.healthScore))
            } else if summary.avgResponseTimeMs > Double(slowResponseMs) * 2 {
                recommendations.append((url, "Chronically slow — avg \(Int(summary.avgResponseTimeMs))ms response", summary.healthScore))
            }
        }

        return recommendations.sorted { $0.score < $1.score }
    }

    // MARK: - Monitored Feeds

    /// List of all monitored feed URLs.
    var monitoredFeeds: [String] {
        Array(Set(fetchEvents.map { $0.feedURL })).sorted()
    }

    /// Total fetch events recorded.
    var totalEvents: Int { fetchEvents.count }

    // MARK: - Export

    /// Export health report as JSON-serializable dictionary.
    func exportReport() -> [String: Any] {
        let dashboard = fleetDashboard()
        return [
            "generatedAt": ISO8601DateFormatter().string(from: Date()),
            "totalFeeds": dashboard.totalFeeds,
            "fleetUptime": dashboard.fleetUptimePercent,
            "avgHealthScore": dashboard.avgHealthScore,
            "healthy": dashboard.healthyCount,
            "degraded": dashboard.degradedCount,
            "stale": dashboard.staleCount,
            "unreliable": dashboard.unreliableCount,
            "dead": dashboard.deadCount,
            "totalIncidents": incidents.count,
            "unresolvedIncidents": incidents.filter { !$0.isResolved }.count,
        ]
    }

    // MARK: - Reset

    /// Clear all recorded data.
    func reset() {
        fetchEvents.removeAll()
        feedTitles.removeAll()
        incidents.removeAll()
        consecutiveErrors.removeAll()
    }

    // MARK: - Private Helpers

    private func computeHealthScore(uptimePercent: Double,
                                    avgResponseMs: Double,
                                    daysSinceUpdate: Int?,
                                    errorCount: Int,
                                    totalFetches: Int) -> Double {
        // Uptime component: 0-40 points
        let uptimeScore = min(40, uptimePercent / 100.0 * 40.0)

        // Response time component: 0-20 points
        let responseScore: Double
        if avgResponseMs <= 1000 {
            responseScore = 20
        } else if avgResponseMs <= Double(slowResponseMs) {
            responseScore = 20.0 * (1.0 - (avgResponseMs - 1000) / Double(slowResponseMs - 1000))
        } else {
            responseScore = 0
        }

        // Freshness component: 0-20 points
        let freshnessScore: Double
        if let days = daysSinceUpdate {
            if days <= 1 {
                freshnessScore = 20
            } else if days <= staleThresholdDays {
                freshnessScore = 20.0 * (1.0 - Double(days) / Double(staleThresholdDays))
            } else {
                freshnessScore = 0
            }
        } else {
            freshnessScore = 10 // Unknown: middle score
        }

        // Error diversity penalty: 0-10 points
        let errorDiversityScore: Double
        if errorCount == 0 {
            errorDiversityScore = 10
        } else {
            let errorRate = Double(errorCount) / Double(totalFetches)
            errorDiversityScore = max(0, 10.0 * (1.0 - errorRate * 2))
        }

        // Consistency bonus: 0-10 points
        let consistencyScore: Double
        if totalFetches >= 5 && uptimePercent >= 95 {
            consistencyScore = 10
        } else if totalFetches >= 3 && uptimePercent >= 80 {
            consistencyScore = 7
        } else if uptimePercent >= 60 {
            consistencyScore = 4
        } else {
            consistencyScore = 0
        }

        return min(100, max(0,
            uptimeScore + responseScore + freshnessScore +
            errorDiversityScore + consistencyScore
        ))
    }

    private func classifyStatus(score: Double,
                                daysSinceUpdate: Int?,
                                uptimePercent: Double,
                                lastSuccess: Date?) -> FeedHealthStatus {
        // Dead: no success in threshold
        if let ls = lastSuccess {
            let daysSinceSuccess = Calendar.current.dateComponents(
                [.day], from: ls, to: Date()
            ).day ?? 0
            if daysSinceSuccess >= deadThresholdDays {
                return .dead
            }
        }

        // Stale: no new content in threshold
        if let days = daysSinceUpdate, days >= staleThresholdDays {
            return .stale
        }

        // Unreliable: low uptime
        if uptimePercent < 50 {
            return .unreliable
        }

        // Healthy vs degraded based on score
        if score >= 80 {
            return .healthy
        } else {
            return .degraded
        }
    }

    private func generateRecommendation(status: FeedHealthStatus,
                                        uptimePercent: Double,
                                        avgResponseMs: Double,
                                        daysSinceUpdate: Int?,
                                        errorBreakdown: [FetchResult: Int]) -> String? {
        switch status {
        case .dead:
            return "Consider removing — feed appears dead"
        case .stale:
            return "Feed may have stopped publishing — check source website"
        case .unreliable:
            let topError = errorBreakdown.max(by: { $0.value < $1.value })
            if let err = topError {
                switch err.key {
                case .sslError:
                    return "SSL certificate issues — feed may need HTTPS update"
                case .dnsError:
                    return "DNS resolution failing — domain may have moved"
                case .timeout:
                    return "Frequent timeouts — server may be overloaded"
                default:
                    return "High error rate (\(Int(100 - uptimePercent))%) — investigate source"
                }
            }
            return "High error rate — investigate source"
        case .degraded:
            if avgResponseMs > Double(slowResponseMs) {
                return "Slow responses — consider if feed is worth the wait"
            }
            return nil
        case .healthy:
            return nil
        }
    }
}
