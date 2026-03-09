//
//  FeedSourceHealthMonitorTests.swift
//  FeedReaderTests
//
//  Tests for FeedSourceHealthMonitor.
//

import XCTest
@testable import FeedReader

class FeedSourceHealthMonitorTests: XCTestCase {

    var monitor: FeedSourceHealthMonitor!
    var cal: Calendar!

    override func setUp() {
        super.setUp()
        monitor = FeedSourceHealthMonitor(
            staleThresholdDays: 14,
            deadThresholdDays: 30,
            slowResponseMs: 5000
        )
        cal = Calendar.current
    }

    // MARK: - Helpers

    private func date(daysAgo: Int, hour: Int = 12) -> Date {
        cal.date(byAdding: .day, value: -daysAgo, to: Date())!
    }

    private func recordSuccess(feed: String = "https://example.com/feed",
                               title: String = "Example",
                               responseMs: Int = 500,
                               newArticles: Int = 2,
                               daysAgo: Int = 0) {
        monitor.recordFetch(
            feedURL: feed,
            feedTitle: title,
            result: .success,
            responseTimeMs: responseMs,
            newArticleCount: newArticles,
            date: date(daysAgo: daysAgo)
        )
    }

    private func recordError(feed: String = "https://example.com/feed",
                             result: FetchResult = .httpError,
                             responseMs: Int = 1000,
                             daysAgo: Int = 0) {
        monitor.recordFetch(
            feedURL: feed,
            result: result,
            responseTimeMs: responseMs,
            httpStatus: 500,
            errorMessage: "Server error",
            date: date(daysAgo: daysAgo)
        )
    }

    // MARK: - Recording

    func testRecordFetchReturnsEvent() {
        let event = monitor.recordFetch(
            feedURL: "https://test.com/feed",
            feedTitle: "Test",
            result: .success,
            responseTimeMs: 300,
            newArticleCount: 5
        )
        XCTAssertEqual(event.feedURL, "https://test.com/feed")
        XCTAssertEqual(event.result, .success)
        XCTAssertEqual(event.responseTimeMs, 300)
        XCTAssertEqual(event.newArticleCount, 5)
    }

    func testTotalEventsIncrementsOnRecord() {
        XCTAssertEqual(monitor.totalEvents, 0)
        recordSuccess()
        XCTAssertEqual(monitor.totalEvents, 1)
        recordError()
        XCTAssertEqual(monitor.totalEvents, 2)
    }

    func testMonitoredFeedsListsAllFeeds() {
        recordSuccess(feed: "https://a.com/feed")
        recordSuccess(feed: "https://b.com/feed")
        XCTAssertEqual(monitor.monitoredFeeds.count, 2)
    }

    func testNegativeResponseTimeClampedToZero() {
        let event = monitor.recordFetch(
            feedURL: "https://test.com/feed",
            result: .success,
            responseTimeMs: -100,
            newArticleCount: 0
        )
        XCTAssertEqual(event.responseTimeMs, 0)
    }

    // MARK: - Health Summary

    func testHealthSummaryReturnsNilForUnknownFeed() {
        XCTAssertNil(monitor.healthSummary(for: "https://unknown.com/feed"))
    }

    func testHealthySummaryForPerfectFeed() {
        for i in 0..<10 {
            recordSuccess(daysAgo: i, newArticles: 1)
        }
        let summary = monitor.healthSummary(for: "https://example.com/feed")!
        XCTAssertEqual(summary.totalFetches, 10)
        XCTAssertEqual(summary.successCount, 10)
        XCTAssertEqual(summary.errorCount, 0)
        XCTAssertEqual(summary.uptimePercent, 100.0)
        XCTAssertEqual(summary.status, .healthy)
        XCTAssertEqual(summary.grade, .a)
        XCTAssertGreaterThanOrEqual(summary.healthScore, 80)
    }

    func testDegradedFeedWithErrors() {
        for i in 0..<6 {
            recordSuccess(daysAgo: i * 2)
        }
        for i in 0..<4 {
            recordError(daysAgo: i * 2 + 1)
        }
        let summary = monitor.healthSummary(for: "https://example.com/feed")!
        XCTAssertEqual(summary.successCount, 6)
        XCTAssertEqual(summary.errorCount, 4)
        XCTAssertEqual(summary.uptimePercent, 60.0)
    }

    func testUptimePercentCalculation() {
        recordSuccess()
        recordSuccess()
        recordError()
        let summary = monitor.healthSummary(for: "https://example.com/feed")!
        XCTAssertEqual(summary.uptimePercent, 66.7, accuracy: 0.1)
    }

    func testAvgResponseTimeMs() {
        recordSuccess(responseMs: 200)
        recordSuccess(responseMs: 400)
        let summary = monitor.healthSummary(for: "https://example.com/feed")!
        XCTAssertEqual(summary.avgResponseTimeMs, 300.0)
    }

    func testP95ResponseTime() {
        // 20 events: 19 fast, 1 slow
        for _ in 0..<19 {
            recordSuccess(responseMs: 200)
        }
        recordSuccess(responseMs: 5000)
        let summary = monitor.healthSummary(for: "https://example.com/feed")!
        // P95 should be 5000 (the slow one)
        XCTAssertEqual(summary.p95ResponseTimeMs, 5000)
    }

    func testErrorBreakdownCounts() {
        recordError(result: .httpError)
        recordError(result: .httpError)
        recordError(result: .timeout)
        recordSuccess()
        let summary = monitor.healthSummary(for: "https://example.com/feed")!
        XCTAssertEqual(summary.errorBreakdown[.httpError], 2)
        XCTAssertEqual(summary.errorBreakdown[.timeout], 1)
    }

    func testLastSuccessAndErrorDates() {
        recordSuccess(daysAgo: 2)
        recordError(daysAgo: 1)
        recordSuccess(daysAgo: 0)
        let summary = monitor.healthSummary(for: "https://example.com/feed")!
        XCTAssertNotNil(summary.lastSuccessDate)
        XCTAssertNotNil(summary.lastErrorDate)
    }

    func testLastNewContentDate() {
        recordSuccess(newArticles: 0, daysAgo: 2)
        recordSuccess(newArticles: 3, daysAgo: 1)
        recordSuccess(newArticles: 0, daysAgo: 0)
        let summary = monitor.healthSummary(for: "https://example.com/feed")!
        XCTAssertNotNil(summary.lastNewContentDate)
    }

    func testAvgUpdateIntervalHours() {
        // Two content updates 24 hours apart
        recordSuccess(newArticles: 2, daysAgo: 2)
        recordSuccess(newArticles: 1, daysAgo: 1)
        let summary = monitor.healthSummary(for: "https://example.com/feed")!
        XCTAssertNotNil(summary.avgUpdateIntervalHours)
        XCTAssertEqual(summary.avgUpdateIntervalHours!, 24.0, accuracy: 1.0)
    }

    func testAvgUpdateIntervalNilForSingleContent() {
        recordSuccess(newArticles: 5, daysAgo: 0)
        let summary = monitor.healthSummary(for: "https://example.com/feed")!
        XCTAssertNil(summary.avgUpdateIntervalHours)
    }

    func testFeedTitle() {
        recordSuccess(title: "My Feed")
        let summary = monitor.healthSummary(for: "https://example.com/feed")!
        XCTAssertEqual(summary.feedTitle, "My Feed")
    }

    // MARK: - Health Grades

    func testGradeA() {
        XCTAssertEqual(HealthGrade.from(score: 95), .a)
        XCTAssertEqual(HealthGrade.from(score: 90), .a)
    }

    func testGradeB() {
        XCTAssertEqual(HealthGrade.from(score: 85), .b)
        XCTAssertEqual(HealthGrade.from(score: 80), .b)
    }

    func testGradeC() {
        XCTAssertEqual(HealthGrade.from(score: 70), .c)
    }

    func testGradeD() {
        XCTAssertEqual(HealthGrade.from(score: 55), .d)
    }

    func testGradeF() {
        XCTAssertEqual(HealthGrade.from(score: 30), .f)
        XCTAssertEqual(HealthGrade.from(score: 0), .f)
    }

    // MARK: - Status Classification

    func testHealthyStatus() {
        for i in 0..<10 {
            recordSuccess(daysAgo: i)
        }
        let summary = monitor.healthSummary(for: "https://example.com/feed")!
        XCTAssertEqual(summary.status, .healthy)
    }

    func testUnreliableStatus() {
        for _ in 0..<8 {
            recordError()
        }
        recordSuccess(daysAgo: 0)
        recordSuccess(daysAgo: 0)
        let summary = monitor.healthSummary(for: "https://example.com/feed")!
        // 20% uptime → unreliable
        XCTAssertEqual(summary.status, .unreliable)
    }

    func testStaleFeed() {
        // Only old content, but still fetching successfully
        recordSuccess(newArticles: 5, daysAgo: 20)
        for i in 0..<5 {
            recordSuccess(newArticles: 0, daysAgo: i)
        }
        let summary = monitor.healthSummary(for: "https://example.com/feed")!
        XCTAssertEqual(summary.status, .stale)
    }

    // MARK: - Incidents

    func testNoIncidentUnder3Errors() {
        recordError()
        recordError()
        XCTAssertEqual(monitor.getIncidents().count, 0)
    }

    func testIncidentAfter3ConsecutiveErrors() {
        recordError(daysAgo: 2)
        recordError(daysAgo: 1)
        recordError(daysAgo: 0)
        let incidents = monitor.getIncidents()
        XCTAssertEqual(incidents.count, 1)
        XCTAssertFalse(incidents[0].isResolved)
    }

    func testIncidentResolvedOnSuccess() {
        recordError(daysAgo: 3)
        recordError(daysAgo: 2)
        recordError(daysAgo: 1)
        recordSuccess(daysAgo: 0)
        let incidents = monitor.getIncidents()
        XCTAssertEqual(incidents.count, 1)
        XCTAssertTrue(incidents[0].isResolved)
    }

    func testIncidentFilterByFeed() {
        for _ in 0..<3 {
            recordError(feed: "https://a.com/feed")
        }
        for _ in 0..<3 {
            recordError(feed: "https://b.com/feed")
        }
        XCTAssertEqual(monitor.getIncidents(feedURL: "https://a.com/feed").count, 1)
    }

    func testUnresolvedOnlyFilter() {
        recordError(daysAgo: 3)
        recordError(daysAgo: 2)
        recordError(daysAgo: 1)
        recordSuccess(daysAgo: 0) // resolves incident
        for _ in 0..<3 {
            recordError(feed: "https://other.com/feed")
        }
        let unresolved = monitor.getIncidents(unresolvedOnly: true)
        XCTAssertEqual(unresolved.count, 1)
        XCTAssertEqual(unresolved[0].feedURL, "https://other.com/feed")
    }

    // MARK: - Fleet Dashboard

    func testFleetDashboardWithMultipleFeeds() {
        for i in 0..<5 {
            recordSuccess(feed: "https://healthy.com/feed", daysAgo: i)
        }
        for _ in 0..<8 {
            recordError(feed: "https://bad.com/feed")
        }
        recordSuccess(feed: "https://bad.com/feed")
        let dashboard = monitor.fleetDashboard()
        XCTAssertEqual(dashboard.totalFeeds, 2)
        XCTAssertGreaterThan(dashboard.fleetUptimePercent, 0)
    }

    func testFleetDashboardEmpty() {
        let dashboard = monitor.fleetDashboard()
        XCTAssertEqual(dashboard.totalFeeds, 0)
        XCTAssertEqual(dashboard.avgHealthScore, 0)
    }

    func testFleetDashboardCountsStatuses() {
        for i in 0..<10 {
            recordSuccess(feed: "https://good.com/feed", daysAgo: i)
        }
        for _ in 0..<8 {
            recordError(feed: "https://bad.com/feed")
        }
        recordSuccess(feed: "https://bad.com/feed")
        let dashboard = monitor.fleetDashboard()
        XCTAssertGreaterThanOrEqual(dashboard.healthyCount, 1)
    }

    func testTopPerformersCappedAt5() {
        for i in 0..<8 {
            for j in 0..<5 {
                recordSuccess(feed: "https://feed\(i).com/rss", daysAgo: j)
            }
        }
        let dashboard = monitor.fleetDashboard()
        XCTAssertLessThanOrEqual(dashboard.topPerformers.count, 5)
    }

    // MARK: - Cleanup Recommendations

    func testCleanupRecommendsUnreliableFeeds() {
        for _ in 0..<10 {
            recordError(feed: "https://bad.com/feed")
        }
        let recs = monitor.cleanupRecommendations()
        XCTAssertFalse(recs.isEmpty)
        XCTAssertTrue(recs[0].reason.contains("unreliable") || recs[0].reason.contains("dead"))
    }

    func testCleanupSortedByScore() {
        // Two bad feeds with different error counts
        for _ in 0..<10 {
            recordError(feed: "https://worst.com/feed")
        }
        for _ in 0..<5 {
            recordError(feed: "https://bad.com/feed")
        }
        for _ in 0..<5 {
            recordSuccess(feed: "https://bad.com/feed")
        }
        let recs = monitor.cleanupRecommendations()
        if recs.count >= 2 {
            XCTAssertLessThanOrEqual(recs[0].score, recs[1].score)
        }
    }

    func testNoRecommendationsForHealthyFeeds() {
        for i in 0..<10 {
            recordSuccess(daysAgo: i)
        }
        let recs = monitor.cleanupRecommendations()
        XCTAssertTrue(recs.isEmpty)
    }

    // MARK: - Recommendations Text

    func testRecommendationForSSLError() {
        for _ in 0..<8 {
            recordError(result: .sslError)
        }
        recordSuccess()
        recordSuccess()
        let summary = monitor.healthSummary(for: "https://example.com/feed")!
        if let rec = summary.recommendation {
            XCTAssertTrue(rec.contains("SSL") || rec.lowercased().contains("error"))
        }
    }

    // MARK: - Export

    func testExportReportContainsFields() {
        recordSuccess()
        let report = monitor.exportReport()
        XCTAssertNotNil(report["generatedAt"])
        XCTAssertNotNil(report["totalFeeds"])
        XCTAssertNotNil(report["fleetUptime"])
        XCTAssertNotNil(report["avgHealthScore"])
        XCTAssertNotNil(report["healthy"])
    }

    // MARK: - Reset

    func testResetClearsAll() {
        recordSuccess()
        recordError()
        monitor.reset()
        XCTAssertEqual(monitor.totalEvents, 0)
        XCTAssertTrue(monitor.monitoredFeeds.isEmpty)
        XCTAssertTrue(monitor.getIncidents().isEmpty)
    }

    // MARK: - Custom Thresholds

    func testCustomStaleThreshold() {
        let strictMonitor = FeedSourceHealthMonitor(
            staleThresholdDays: 3,
            deadThresholdDays: 7,
            slowResponseMs: 2000
        )
        strictMonitor.recordFetch(
            feedURL: "https://test.com/feed",
            result: .success,
            responseTimeMs: 200,
            newArticleCount: 5,
            date: cal.date(byAdding: .day, value: -5, to: Date())!
        )
        for i in 0..<3 {
            strictMonitor.recordFetch(
                feedURL: "https://test.com/feed",
                result: .success,
                responseTimeMs: 200,
                newArticleCount: 0,
                date: cal.date(byAdding: .day, value: -i, to: Date())!
            )
        }
        let summary = strictMonitor.healthSummary(for: "https://test.com/feed")!
        XCTAssertEqual(summary.status, .stale)
    }

    // MARK: - Enum Cases

    func testFetchResultHasAllCases() {
        XCTAssertEqual(FetchResult.allCases.count, 7)
    }

    func testFeedHealthStatusHasAllCases() {
        XCTAssertEqual(FeedHealthStatus.allCases.count, 5)
    }

    func testHealthGradeHasAllCases() {
        XCTAssertEqual(HealthGrade.allCases.count, 5)
    }
}
