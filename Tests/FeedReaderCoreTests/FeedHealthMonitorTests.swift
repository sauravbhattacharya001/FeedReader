//
//  FeedHealthMonitorTests.swift
//  FeedReaderCoreTests
//
//  Tests for FeedHealthMonitor: staleness, scoring, reports, trends.
//

import XCTest
@testable import FeedReaderCore

final class FeedHealthMonitorTests: XCTestCase {

    private let referenceDate = ISO8601DateFormatter().date(from: "2026-03-17T00:00:00Z")!

    private func makeMonitor(config: FeedHealthConfig = .default) -> FeedHealthMonitor {
        return FeedHealthMonitor(config: config, now: { [referenceDate] in referenceDate })
    }

    private func daysAgo(_ days: Int) -> Date {
        return Calendar.current.date(byAdding: .day, value: -days, to: referenceDate)!
    }

    // MARK: - Empty Feed

    func testEmptyFeedIsDead() {
        let monitor = makeMonitor()
        let result = monitor.checkFeed(feedName: "Empty", feedURL: "https://example.com/rss", articleDates: [])
        XCTAssertEqual(result.status, .dead)
        XCTAssertEqual(result.score, 0)
        XCTAssertEqual(result.articleCount, 0)
        XCTAssertNil(result.daysSinceLastArticle)
        XCTAssertFalse(result.issues.isEmpty)
    }

    // MARK: - Healthy Feed

    func testRecentArticlesAreHealthy() {
        let monitor = makeMonitor()
        let dates = (0..<10).map { daysAgo($0) }
        let result = monitor.checkFeed(feedName: "Active", feedURL: "https://active.com/rss", articleDates: dates)
        XCTAssertEqual(result.status, .healthy)
        XCTAssertGreaterThanOrEqual(result.score, 80)
        XCTAssertEqual(result.daysSinceLastArticle, 0)
        XCTAssertEqual(result.articleCount, 10)
    }

    // MARK: - Warning Status

    func testWarningWhenNoRecentArticles() {
        let monitor = makeMonitor()
        let dates = (10..<20).map { daysAgo($0) }
        let result = monitor.checkFeed(feedName: "Slowing", feedURL: "https://slow.com/rss", articleDates: dates)
        XCTAssertEqual(result.status, .warning)
        XCTAssertEqual(result.daysSinceLastArticle, 10)
    }

    // MARK: - Stale Status

    func testStaleWhenMonthOld() {
        let monitor = makeMonitor()
        let dates = (35..<45).map { daysAgo($0) }
        let result = monitor.checkFeed(feedName: "Old", feedURL: "https://old.com/rss", articleDates: dates)
        XCTAssertEqual(result.status, .stale)
    }

    // MARK: - Dead Status

    func testDeadWhenVeryOld() {
        let monitor = makeMonitor()
        let dates = (100..<105).map { daysAgo($0) }
        let result = monitor.checkFeed(feedName: "Dead", feedURL: "https://dead.com/rss", articleDates: dates)
        XCTAssertEqual(result.status, .dead)
    }

    // MARK: - Custom Config

    func testCustomThresholds() {
        let config = FeedHealthConfig(warningDays: 3, staleDays: 10, deadDays: 20)
        let monitor = makeMonitor(config: config)
        let dates = [daysAgo(5), daysAgo(6), daysAgo(7), daysAgo(8), daysAgo(9)]
        let result = monitor.checkFeed(feedName: "Custom", feedURL: "https://custom.com/rss", articleDates: dates)
        XCTAssertEqual(result.status, .warning)
    }

    func testCustomConfigDead() {
        let config = FeedHealthConfig(warningDays: 3, staleDays: 10, deadDays: 20)
        let monitor = makeMonitor(config: config)
        let dates = [daysAgo(25)]
        let result = monitor.checkFeed(feedName: "Custom", feedURL: "https://custom.com/rss", articleDates: dates)
        XCTAssertEqual(result.status, .dead)
    }

    // MARK: - Low Article Count

    func testLowArticleCountPenalty() {
        let monitor = makeMonitor()
        let dates = [daysAgo(0), daysAgo(1)]
        let result = monitor.checkFeed(feedName: "Sparse", feedURL: "https://sparse.com/rss", articleDates: dates)
        XCTAssertLessThan(result.score, 100)
        XCTAssertTrue(result.issues.contains(where: { $0.contains("Low article count") }))
    }

    // MARK: - Update Interval

    func testAverageUpdateInterval() {
        let monitor = makeMonitor()
        // Articles every 2 days
        let dates = stride(from: 0, to: 20, by: 2).map { daysAgo($0) }
        let result = monitor.checkFeed(feedName: "Biweekly", feedURL: "https://bi.com/rss", articleDates: dates)
        XCTAssertNotNil(result.averageUpdateInterval)
        XCTAssertEqual(result.averageUpdateInterval!, 2.0, accuracy: 0.1)
    }

    func testInfrequentUpdatePenalty() {
        let config = FeedHealthConfig(maxUpdateIntervalDays: 5.0)
        let monitor = makeMonitor(config: config)
        // Articles every 10 days
        let dates = stride(from: 0, to: 60, by: 10).map { daysAgo($0) }
        let result = monitor.checkFeed(feedName: "Slow", feedURL: "https://slow.com/rss", articleDates: dates)
        XCTAssertTrue(result.issues.contains(where: { $0.contains("Infrequent") }))
    }

    // MARK: - Single Article

    func testSingleArticle() {
        let monitor = makeMonitor()
        let result = monitor.checkFeed(feedName: "One", feedURL: "https://one.com/rss", articleDates: [daysAgo(2)])
        XCTAssertNil(result.averageUpdateInterval)
        XCTAssertEqual(result.articleCount, 1)
        XCTAssertEqual(result.daysSinceLastArticle, 2)
    }

    // MARK: - Report

    func testReportGeneration() {
        let monitor = makeMonitor()
        let feeds: [(name: String, url: String, dates: [Date])] = [
            ("Active", "https://a.com/rss", (0..<10).map { daysAgo($0) }),
            ("Dead", "https://d.com/rss", (100..<105).map { daysAgo($0) }),
            ("Empty", "https://e.com/rss", [])
        ]
        let report = monitor.generateReport(feeds: feeds)
        XCTAssertEqual(report.results.count, 3)
        XCTAssertEqual(report.statusCounts[.healthy], 1)
        XCTAssertEqual(report.statusCounts[.dead], 2)
        XCTAssertEqual(report.overallStatus, .dead)
        XCTAssertLessThan(report.overallScore, 50)
    }

    func testEmptyReport() {
        let monitor = makeMonitor()
        let report = monitor.generateReport(feeds: [])
        XCTAssertEqual(report.results.count, 0)
        XCTAssertEqual(report.overallScore, 0)
        XCTAssertEqual(report.overallStatus, .healthy)
    }

    func testReportSummaryContainsHeader() {
        let monitor = makeMonitor()
        let report = monitor.generateReport(feeds: [("Test", "https://t.com/rss", [daysAgo(0)])])
        XCTAssertTrue(report.summary.contains("Feed Health Report"))
    }

    func testReportJsonDict() {
        let monitor = makeMonitor()
        let report = monitor.generateReport(feeds: [("Test", "https://t.com/rss", (0..<5).map { daysAgo($0) })])
        let json = report.jsonDict
        XCTAssertEqual(json.count, 1)
        XCTAssertEqual(json[0]["feedName"] as? String, "Test")
        XCTAssertEqual(json[0]["status"] as? String, "healthy")
    }

    // MARK: - Trend Detection

    func testTrendSlowingDown() {
        let monitor = makeMonitor()
        // Older articles daily, recent articles every 5 days
        var dates: [Date] = []
        for i in 0..<5 { dates.append(daysAgo(50 + i)) } // older: daily
        for i in 0..<5 { dates.append(daysAgo(i * 5)) }  // recent: every 5 days
        let trend = monitor.detectTrend(articleDates: dates)
        XCTAssertNotNil(trend)
        XCTAssertGreaterThan(trend!, 1.0) // slowing down
    }

    func testTrendSpeedingUp() {
        let monitor = makeMonitor()
        var dates: [Date] = []
        for i in 0..<5 { dates.append(daysAgo(50 + i * 5)) } // older: every 5 days
        for i in 0..<5 { dates.append(daysAgo(i)) }          // recent: daily
        let trend = monitor.detectTrend(articleDates: dates)
        XCTAssertNotNil(trend)
        XCTAssertLessThan(trend!, 1.0) // speeding up
    }

    func testTrendInsufficientData() {
        let monitor = makeMonitor()
        let trend = monitor.detectTrend(articleDates: [daysAgo(0), daysAgo(1)])
        XCTAssertNil(trend)
    }

    // MARK: - Summary Text

    func testHealthyResultSummary() {
        let monitor = makeMonitor()
        let dates = (0..<10).map { daysAgo($0) }
        let result = monitor.checkFeed(feedName: "Good Feed", feedURL: "https://good.com/rss", articleDates: dates)
        XCTAssertTrue(result.summary.contains("Good Feed"))
        XCTAssertTrue(result.summary.contains("HEALTHY"))
    }

    func testDeadResultSummaryContainsSkull() {
        let monitor = makeMonitor()
        let result = monitor.checkFeed(feedName: "Gone", feedURL: "https://gone.com/rss", articleDates: [])
        XCTAssertTrue(result.summary.contains("💀"))
    }

    // MARK: - Status Comparable

    func testStatusOrdering() {
        XCTAssertLessThan(FeedHealthStatus.dead, FeedHealthStatus.stale)
        XCTAssertLessThan(FeedHealthStatus.stale, FeedHealthStatus.warning)
        XCTAssertLessThan(FeedHealthStatus.warning, FeedHealthStatus.healthy)
    }

    // MARK: - Config Validation

    func testConfigClampsMinimums() {
        let config = FeedHealthConfig(warningDays: 0, staleDays: 0, deadDays: 0, minimumArticleCount: 0, maxUpdateIntervalDays: 0)
        XCTAssertGreaterThanOrEqual(config.warningDays, 1)
        XCTAssertGreaterThan(config.staleDays, config.warningDays)
        XCTAssertGreaterThan(config.deadDays, config.staleDays)
        XCTAssertGreaterThanOrEqual(config.minimumArticleCount, 1)
        XCTAssertGreaterThanOrEqual(config.maxUpdateIntervalDays, 1.0)
    }

    // MARK: - Recommendations

    func testStaleRecommendations() {
        let monitor = makeMonitor()
        let dates = (40..<50).map { daysAgo($0) }
        let result = monitor.checkFeed(feedName: "Stale", feedURL: "https://stale.com/rss", articleDates: dates)
        XCTAssertTrue(result.recommendations.contains(where: { $0.contains("replacing") }))
    }

    func testWarningRecommendations() {
        let monitor = makeMonitor()
        let dates = (10..<20).map { daysAgo($0) }
        let result = monitor.checkFeed(feedName: "Warn", feedURL: "https://warn.com/rss", articleDates: dates)
        XCTAssertTrue(result.recommendations.contains(where: { $0.contains("Monitor") }))
    }

    // MARK: - Irregular Schedule

    func testIrregularScheduleDetected() {
        let monitor = makeMonitor()
        // Highly irregular: 1, 1, 1, 50, 1, 1, 50 days apart
        let dates = [daysAgo(0), daysAgo(1), daysAgo(2), daysAgo(3), daysAgo(53), daysAgo(54), daysAgo(55), daysAgo(105)]
        let result = monitor.checkFeed(feedName: "Irregular", feedURL: "https://irr.com/rss", articleDates: dates)
        XCTAssertTrue(result.issues.contains(where: { $0.contains("irregular") || $0.contains("Irregular") }))
    }

    // MARK: - Checked At

    func testCheckedAtIsSet() {
        let monitor = makeMonitor()
        let result = monitor.checkFeed(feedName: "Test", feedURL: "https://t.com/rss", articleDates: [daysAgo(0)])
        XCTAssertEqual(result.checkedAt, referenceDate)
    }

    func testReportGeneratedAtIsSet() {
        let monitor = makeMonitor()
        let report = monitor.generateReport(feeds: [])
        XCTAssertEqual(report.generatedAt, referenceDate)
    }
}
