//
//  FeedHealthTests.swift
//  FeedReaderTests
//
//  Tests for FeedHealthManager — fetch recording, health classification,
//  response time statistics, staleness detection, error tracking,
//  health reports, summaries, data management, edge cases.
//

import XCTest
@testable import FeedReader

class FeedHealthTests: XCTestCase {
    
    // MARK: - Helpers
    
    private let testURL1 = "https://feeds.example.com/rss1"
    private let testURL2 = "https://feeds.example.com/rss2"
    private let testURL3 = "https://feeds.example.com/rss3"
    
    private func makeRecord(
        feedURL: String = "https://feeds.example.com/rss1",
        timestamp: Date = Date(),
        success: Bool = true,
        responseTimeMs: Int = 200,
        errorMessage: String? = nil,
        storiesFound: Int = 10
    ) -> FetchRecord {
        return FetchRecord(
            feedURL: feedURL,
            timestamp: timestamp,
            success: success,
            responseTimeMs: responseTimeMs,
            errorMessage: errorMessage,
            storiesFound: storiesFound
        )
    }
    
    private func daysAgo(_ days: Int) -> Date {
        return Calendar.current.date(byAdding: .day, value: -days, to: Date())!
    }
    
    private func hoursAgo(_ hours: Int) -> Date {
        return Calendar.current.date(byAdding: .hour, value: -hours, to: Date())!
    }
    
    override func setUp() {
        super.setUp()
        FeedHealthManager.shared.clearAll()
    }
    
    override func tearDown() {
        FeedHealthManager.shared.clearAll()
        super.tearDown()
    }
    
    // MARK: - Recording Fetches
    
    func testRecordSingleFetch() {
        FeedHealthManager.shared.recordFetch(
            feedURL: testURL1, feedName: "Test Feed",
            success: true, responseTimeMs: 150,
            storiesFound: 5
        )
        XCTAssertEqual(FeedHealthManager.shared.totalRecordCount(), 1)
        XCTAssertEqual(FeedHealthManager.shared.trackedFeedCount(), 1)
    }
    
    func testRecordMultipleFetches() {
        for i in 0..<5 {
            FeedHealthManager.shared.recordFetch(
                feedURL: testURL1, feedName: "Feed 1",
                success: true, responseTimeMs: 100 + i * 10,
                storiesFound: 10
            )
        }
        XCTAssertEqual(FeedHealthManager.shared.totalRecordCount(), 5)
        XCTAssertEqual(FeedHealthManager.shared.trackedFeedCount(), 1)
    }
    
    func testRecordMultipleFeeds() {
        FeedHealthManager.shared.recordFetch(
            feedURL: testURL1, feedName: "Feed 1",
            success: true, responseTimeMs: 100, storiesFound: 5
        )
        FeedHealthManager.shared.recordFetch(
            feedURL: testURL2, feedName: "Feed 2",
            success: true, responseTimeMs: 200, storiesFound: 8
        )
        XCTAssertEqual(FeedHealthManager.shared.trackedFeedCount(), 2)
        XCTAssertEqual(FeedHealthManager.shared.totalRecordCount(), 2)
    }
    
    func testRecordWithPrebuiltRecord() {
        let record = makeRecord(success: true, responseTimeMs: 300, storiesFound: 15)
        FeedHealthManager.shared.recordFetch(record: record, feedName: "Direct Record")
        XCTAssertEqual(FeedHealthManager.shared.totalRecordCount(), 1)
    }
    
    func testRecordFetchClampsNegativeResponseTime() {
        FeedHealthManager.shared.recordFetch(
            feedURL: testURL1, feedName: "Test",
            success: true, responseTimeMs: -50,
            storiesFound: 3
        )
        let history = FeedHealthManager.shared.fetchHistory(for: testURL1)
        XCTAssertEqual(history.first?.responseTimeMs, 0)
    }
    
    func testRecordFetchClampsNegativeStoryCount() {
        FeedHealthManager.shared.recordFetch(
            feedURL: testURL1, feedName: "Test",
            success: true, responseTimeMs: 100,
            storiesFound: -5
        )
        let history = FeedHealthManager.shared.fetchHistory(for: testURL1)
        XCTAssertEqual(history.first?.storiesFound, 0)
    }
    
    func testSuccessfulRecordClearsErrorMessage() {
        FeedHealthManager.shared.recordFetch(
            feedURL: testURL1, feedName: "Test",
            success: true, responseTimeMs: 100,
            storiesFound: 5, errorMessage: "should be nil"
        )
        let history = FeedHealthManager.shared.fetchHistory(for: testURL1)
        XCTAssertNil(history.first?.errorMessage)
    }
    
    func testFailedRecordKeepsErrorMessage() {
        FeedHealthManager.shared.recordFetch(
            feedURL: testURL1, feedName: "Test",
            success: false, responseTimeMs: 0,
            storiesFound: 0, errorMessage: "Connection timeout"
        )
        let history = FeedHealthManager.shared.fetchHistory(for: testURL1)
        XCTAssertEqual(history.first?.errorMessage, "Connection timeout")
    }
    
    func testFeedNameTracking() {
        FeedHealthManager.shared.recordFetch(
            feedURL: testURL1, feedName: "BBC News",
            success: true, responseTimeMs: 100, storiesFound: 5
        )
        XCTAssertEqual(FeedHealthManager.shared.feedNames[testURL1], "BBC News")
    }
    
    func testFeedNameUpdatesOnSubsequentFetch() {
        FeedHealthManager.shared.recordFetch(
            feedURL: testURL1, feedName: "Old Name",
            success: true, responseTimeMs: 100, storiesFound: 5
        )
        FeedHealthManager.shared.recordFetch(
            feedURL: testURL1, feedName: "New Name",
            success: true, responseTimeMs: 100, storiesFound: 5
        )
        XCTAssertEqual(FeedHealthManager.shared.feedNames[testURL1], "New Name")
    }
    
    // MARK: - Health Status Classification
    
    func testHealthyFeedClassification() {
        // 5 successful fetches → healthy
        for _ in 0..<5 {
            FeedHealthManager.shared.recordFetch(
                feedURL: testURL1, feedName: "Good Feed",
                success: true, responseTimeMs: 150, storiesFound: 10
            )
        }
        let report = FeedHealthManager.shared.healthReport(for: testURL1)
        XCTAssertEqual(report.status, .healthy)
        XCTAssertEqual(report.successRate, 1.0)
    }
    
    func testDegradedFeedLowSuccessRate() {
        // 7 successes + 3 failures = 70% → degraded
        for _ in 0..<7 {
            FeedHealthManager.shared.recordFetch(
                feedURL: testURL1, feedName: "Shaky Feed",
                success: true, responseTimeMs: 200, storiesFound: 10
            )
        }
        for _ in 0..<3 {
            FeedHealthManager.shared.recordFetch(
                feedURL: testURL1, feedName: "Shaky Feed",
                success: false, responseTimeMs: 0, storiesFound: 0,
                errorMessage: "Timeout"
            )
        }
        let report = FeedHealthManager.shared.healthReport(for: testURL1)
        XCTAssertEqual(report.status, .degraded)
    }
    
    func testDegradedFeedSlowResponse() {
        // All successful but very slow → degraded
        for _ in 0..<5 {
            FeedHealthManager.shared.recordFetch(
                feedURL: testURL1, feedName: "Slow Feed",
                success: true, responseTimeMs: 6000, storiesFound: 10
            )
        }
        let report = FeedHealthManager.shared.healthReport(for: testURL1)
        XCTAssertEqual(report.status, .degraded)
    }
    
    func testDegradedFeedConsecutiveFailures() {
        // 3 successes then 2 consecutive failures → degraded
        for _ in 0..<3 {
            FeedHealthManager.shared.recordFetch(
                feedURL: testURL1, feedName: "Failing Feed",
                success: true, responseTimeMs: 200, storiesFound: 10
            )
        }
        for _ in 0..<2 {
            FeedHealthManager.shared.recordFetch(
                feedURL: testURL1, feedName: "Failing Feed",
                success: false, responseTimeMs: 0, storiesFound: 0
            )
        }
        let report = FeedHealthManager.shared.healthReport(for: testURL1)
        XCTAssertEqual(report.status, .degraded)
        XCTAssertEqual(report.consecutiveFailures, 2)
    }
    
    func testUnhealthyFeedVeryLowSuccessRate() {
        // 1 success + 4 failures = 20% → unhealthy
        FeedHealthManager.shared.recordFetch(
            feedURL: testURL1, feedName: "Broken Feed",
            success: true, responseTimeMs: 200, storiesFound: 5
        )
        for _ in 0..<4 {
            FeedHealthManager.shared.recordFetch(
                feedURL: testURL1, feedName: "Broken Feed",
                success: false, responseTimeMs: 0, storiesFound: 0,
                errorMessage: "DNS resolution failed"
            )
        }
        let report = FeedHealthManager.shared.healthReport(for: testURL1)
        XCTAssertEqual(report.status, .unhealthy)
    }
    
    func testUnhealthyFeedManyConsecutiveFailures() {
        // 3 successes then 5 consecutive failures → unhealthy
        for _ in 0..<3 {
            FeedHealthManager.shared.recordFetch(
                feedURL: testURL1, feedName: "Dead Feed",
                success: true, responseTimeMs: 200, storiesFound: 10
            )
        }
        for _ in 0..<5 {
            FeedHealthManager.shared.recordFetch(
                feedURL: testURL1, feedName: "Dead Feed",
                success: false, responseTimeMs: 0, storiesFound: 0,
                errorMessage: "Server down"
            )
        }
        let report = FeedHealthManager.shared.healthReport(for: testURL1)
        XCTAssertEqual(report.status, .unhealthy)
        XCTAssertEqual(report.consecutiveFailures, 5)
    }
    
    func testUnknownWithTooFewFetches() {
        // Only 2 fetches → unknown (minimum is 3)
        FeedHealthManager.shared.recordFetch(
            feedURL: testURL1, feedName: "New Feed",
            success: true, responseTimeMs: 200, storiesFound: 5
        )
        FeedHealthManager.shared.recordFetch(
            feedURL: testURL1, feedName: "New Feed",
            success: true, responseTimeMs: 200, storiesFound: 5
        )
        let report = FeedHealthManager.shared.healthReport(for: testURL1)
        XCTAssertEqual(report.status, .unknown)
    }
    
    func testUnknownWithNoData() {
        let report = FeedHealthManager.shared.healthReport(for: "https://nonexistent.com/rss")
        XCTAssertEqual(report.status, .unknown)
        XCTAssertEqual(report.totalFetches, 0)
        XCTAssertNil(report.lastFetchDate)
    }
    
    // MARK: - Staleness Detection
    
    func testStaleFeedDetection() {
        let manager = FeedHealthManager.shared
        // Record fetches with same story count over many days
        let staleRecord1 = makeRecord(timestamp: daysAgo(10), storiesFound: 5)
        let staleRecord2 = makeRecord(timestamp: daysAgo(8), storiesFound: 5)
        let staleRecord3 = makeRecord(timestamp: daysAgo(5), storiesFound: 5)
        
        manager.recordFetch(record: staleRecord1, feedName: "Stale Feed")
        manager.recordFetch(record: staleRecord2, feedName: "Stale Feed")
        manager.recordFetch(record: staleRecord3, feedName: "Stale Feed")
        
        let report = manager.healthReport(for: testURL1)
        XCTAssertEqual(report.status, .stale)
    }
    
    func testNotStaleWithRecentContentChange() {
        let manager = FeedHealthManager.shared
        // Record with changing story count → content updating
        let rec1 = makeRecord(timestamp: daysAgo(3), storiesFound: 5)
        let rec2 = makeRecord(timestamp: daysAgo(2), storiesFound: 7)
        let rec3 = makeRecord(timestamp: daysAgo(1), storiesFound: 9)
        
        manager.recordFetch(record: rec1, feedName: "Active Feed")
        manager.recordFetch(record: rec2, feedName: "Active Feed")
        manager.recordFetch(record: rec3, feedName: "Active Feed")
        
        let report = manager.healthReport(for: testURL1)
        XCTAssertNotEqual(report.status, .stale)
    }
    
    func testStaleOverridesHealthyForWorkingButStagnantFeed() {
        let manager = FeedHealthManager.shared
        // Feed works perfectly but never has new content
        for i in 0..<5 {
            let rec = makeRecord(
                timestamp: daysAgo(15 - i),
                success: true,
                responseTimeMs: 100,
                storiesFound: 5 // same count every time
            )
            manager.recordFetch(record: rec, feedName: "Stagnant Feed")
        }
        let report = manager.healthReport(for: testURL1)
        XCTAssertEqual(report.status, .stale)
    }
    
    func testDaysSinceNewContent() {
        let manager = FeedHealthManager.shared
        let rec1 = makeRecord(timestamp: daysAgo(5), storiesFound: 5)
        let rec2 = makeRecord(timestamp: daysAgo(3), storiesFound: 7)  // content changed here
        let rec3 = makeRecord(timestamp: daysAgo(1), storiesFound: 7)  // same count
        
        manager.recordFetch(record: rec1, feedName: "Test")
        manager.recordFetch(record: rec2, feedName: "Test")
        manager.recordFetch(record: rec3, feedName: "Test")
        
        let report = manager.healthReport(for: testURL1)
        XCTAssertNotNil(report.daysSinceNewContent)
        XCTAssertEqual(report.daysSinceNewContent, 3) // last change was 3 days ago
    }
    
    // MARK: - Response Time Statistics
    
    func testAvgResponseTime() {
        let times = [100, 200, 300, 400, 500]
        for t in times {
            FeedHealthManager.shared.recordFetch(
                feedURL: testURL1, feedName: "Test",
                success: true, responseTimeMs: t, storiesFound: 5
            )
        }
        let report = FeedHealthManager.shared.healthReport(for: testURL1)
        XCTAssertEqual(report.avgResponseTimeMs, 300.0, accuracy: 0.01)
    }
    
    func testMinMaxResponseTime() {
        FeedHealthManager.shared.recordFetch(
            feedURL: testURL1, feedName: "Test",
            success: true, responseTimeMs: 50, storiesFound: 5
        )
        FeedHealthManager.shared.recordFetch(
            feedURL: testURL1, feedName: "Test",
            success: true, responseTimeMs: 500, storiesFound: 5
        )
        FeedHealthManager.shared.recordFetch(
            feedURL: testURL1, feedName: "Test",
            success: true, responseTimeMs: 200, storiesFound: 5
        )
        let report = FeedHealthManager.shared.healthReport(for: testURL1)
        XCTAssertEqual(report.minResponseTimeMs, 50)
        XCTAssertEqual(report.maxResponseTimeMs, 500)
    }
    
    func testP95ResponseTime() {
        // 20 records: 100ms each, plus 1 outlier at 5000ms
        for _ in 0..<20 {
            FeedHealthManager.shared.recordFetch(
                feedURL: testURL1, feedName: "Test",
                success: true, responseTimeMs: 100, storiesFound: 5
            )
        }
        FeedHealthManager.shared.recordFetch(
            feedURL: testURL1, feedName: "Test",
            success: true, responseTimeMs: 5000, storiesFound: 5
        )
        let report = FeedHealthManager.shared.healthReport(for: testURL1)
        // P95 of 20×100 + 1×5000: index 19 of 21 sorted values = 100 (since only last is 5000)
        XCTAssertTrue(report.p95ResponseTimeMs <= 5000)
    }
    
    func testResponseTimeExcludesFailedFetches() {
        FeedHealthManager.shared.recordFetch(
            feedURL: testURL1, feedName: "Test",
            success: true, responseTimeMs: 200, storiesFound: 5
        )
        FeedHealthManager.shared.recordFetch(
            feedURL: testURL1, feedName: "Test",
            success: false, responseTimeMs: 30000, storiesFound: 0,
            errorMessage: "Timeout"
        )
        FeedHealthManager.shared.recordFetch(
            feedURL: testURL1, feedName: "Test",
            success: true, responseTimeMs: 300, storiesFound: 5
        )
        let report = FeedHealthManager.shared.healthReport(for: testURL1)
        XCTAssertEqual(report.avgResponseTimeMs, 250.0, accuracy: 0.01) // Only successful fetches
    }
    
    func testResponseTimeZeroWhenAllFailed() {
        for _ in 0..<3 {
            FeedHealthManager.shared.recordFetch(
                feedURL: testURL1, feedName: "Test",
                success: false, responseTimeMs: 0, storiesFound: 0,
                errorMessage: "Failed"
            )
        }
        let report = FeedHealthManager.shared.healthReport(for: testURL1)
        XCTAssertEqual(report.avgResponseTimeMs, 0)
        XCTAssertEqual(report.minResponseTimeMs, 0)
        XCTAssertEqual(report.maxResponseTimeMs, 0)
    }
    
    // MARK: - Consecutive Failures
    
    func testConsecutiveFailuresCount() {
        FeedHealthManager.shared.recordFetch(
            feedURL: testURL1, feedName: "Test",
            success: true, responseTimeMs: 100, storiesFound: 5
        )
        for _ in 0..<3 {
            FeedHealthManager.shared.recordFetch(
                feedURL: testURL1, feedName: "Test",
                success: false, responseTimeMs: 0, storiesFound: 0
            )
        }
        let report = FeedHealthManager.shared.healthReport(for: testURL1)
        XCTAssertEqual(report.consecutiveFailures, 3)
    }
    
    func testConsecutiveFailuresResetOnSuccess() {
        for _ in 0..<3 {
            FeedHealthManager.shared.recordFetch(
                feedURL: testURL1, feedName: "Test",
                success: false, responseTimeMs: 0, storiesFound: 0
            )
        }
        FeedHealthManager.shared.recordFetch(
            feedURL: testURL1, feedName: "Test",
            success: true, responseTimeMs: 100, storiesFound: 5
        )
        let report = FeedHealthManager.shared.healthReport(for: testURL1)
        XCTAssertEqual(report.consecutiveFailures, 0)
    }
    
    func testZeroConsecutiveFailuresWhenAllSuccessful() {
        for _ in 0..<5 {
            FeedHealthManager.shared.recordFetch(
                feedURL: testURL1, feedName: "Test",
                success: true, responseTimeMs: 200, storiesFound: 10
            )
        }
        let report = FeedHealthManager.shared.healthReport(for: testURL1)
        XCTAssertEqual(report.consecutiveFailures, 0)
    }
    
    // MARK: - Error Tracking
    
    func testRecentErrors() {
        for i in 0..<8 {
            FeedHealthManager.shared.recordFetch(
                feedURL: testURL1, feedName: "Test",
                success: false, responseTimeMs: 0, storiesFound: 0,
                errorMessage: "Error \(i)"
            )
        }
        let report = FeedHealthManager.shared.healthReport(for: testURL1)
        XCTAssertEqual(report.recentErrors.count, 5) // Capped at 5
    }
    
    func testLastErrorMessage() {
        FeedHealthManager.shared.recordFetch(
            feedURL: testURL1, feedName: "Test",
            success: false, responseTimeMs: 0, storiesFound: 0,
            errorMessage: "Connection refused"
        )
        FeedHealthManager.shared.recordFetch(
            feedURL: testURL1, feedName: "Test",
            success: false, responseTimeMs: 0, storiesFound: 0,
            errorMessage: "DNS lookup failed"
        )
        let report = FeedHealthManager.shared.healthReport(for: testURL1)
        XCTAssertEqual(report.lastErrorMessage, "DNS lookup failed")
    }
    
    func testMostRecentErrorAcrossFeeds() {
        let oldRecord = makeRecord(
            feedURL: testURL1,
            timestamp: hoursAgo(2),
            success: false,
            responseTimeMs: 0,
            errorMessage: "Old error",
            storiesFound: 0
        )
        let newRecord = makeRecord(
            feedURL: testURL2,
            timestamp: hoursAgo(1),
            success: false,
            responseTimeMs: 0,
            errorMessage: "Recent error",
            storiesFound: 0
        )
        FeedHealthManager.shared.recordFetch(record: oldRecord, feedName: "Feed 1")
        FeedHealthManager.shared.recordFetch(record: newRecord, feedName: "Feed 2")
        
        let mostRecent = FeedHealthManager.shared.mostRecentError()
        XCTAssertNotNil(mostRecent)
        XCTAssertEqual(mostRecent?.errorMessage, "Recent error")
    }
    
    func testMostRecentErrorNilWhenAllSuccessful() {
        FeedHealthManager.shared.recordFetch(
            feedURL: testURL1, feedName: "Test",
            success: true, responseTimeMs: 100, storiesFound: 5
        )
        XCTAssertNil(FeedHealthManager.shared.mostRecentError())
    }
    
    // MARK: - Health Reports
    
    func testHealthReportSuccessRate() {
        for _ in 0..<7 {
            FeedHealthManager.shared.recordFetch(
                feedURL: testURL1, feedName: "Test",
                success: true, responseTimeMs: 100, storiesFound: 5
            )
        }
        for _ in 0..<3 {
            FeedHealthManager.shared.recordFetch(
                feedURL: testURL1, feedName: "Test",
                success: false, responseTimeMs: 0, storiesFound: 0
            )
        }
        let report = FeedHealthManager.shared.healthReport(for: testURL1)
        XCTAssertEqual(report.successRate, 0.7, accuracy: 0.001)
        XCTAssertEqual(report.successCount, 7)
        XCTAssertEqual(report.failureCount, 3)
        XCTAssertEqual(report.totalFetches, 10)
    }
    
    func testAllHealthReportsSortedWorstFirst() {
        // Healthy feed
        for _ in 0..<5 {
            FeedHealthManager.shared.recordFetch(
                feedURL: testURL1, feedName: "Healthy",
                success: true, responseTimeMs: 100, storiesFound: 10
            )
        }
        // Unhealthy feed
        for _ in 0..<5 {
            FeedHealthManager.shared.recordFetch(
                feedURL: testURL2, feedName: "Unhealthy",
                success: false, responseTimeMs: 0, storiesFound: 0,
                errorMessage: "Dead"
            )
        }
        // Degraded feed
        for _ in 0..<3 {
            FeedHealthManager.shared.recordFetch(
                feedURL: testURL3, feedName: "Degraded",
                success: true, responseTimeMs: 200, storiesFound: 5
            )
        }
        for _ in 0..<2 {
            FeedHealthManager.shared.recordFetch(
                feedURL: testURL3, feedName: "Degraded",
                success: false, responseTimeMs: 0, storiesFound: 0
            )
        }
        
        let reports = FeedHealthManager.shared.allHealthReports()
        XCTAssertEqual(reports.count, 3)
        // Worst first: unhealthy → degraded → healthy
        XCTAssertEqual(reports[0].status, .unhealthy)
        XCTAssertEqual(reports[1].status, .degraded)
        XCTAssertEqual(reports[2].status, .healthy)
    }
    
    func testEmptyAllHealthReports() {
        let reports = FeedHealthManager.shared.allHealthReports()
        XCTAssertTrue(reports.isEmpty)
    }
    
    // MARK: - Health Summary
    
    func testHealthSummaryWithMixedFeeds() {
        // Healthy feed
        for _ in 0..<5 {
            FeedHealthManager.shared.recordFetch(
                feedURL: testURL1, feedName: "Healthy",
                success: true, responseTimeMs: 100, storiesFound: 10
            )
        }
        // Unhealthy feed
        for _ in 0..<5 {
            FeedHealthManager.shared.recordFetch(
                feedURL: testURL2, feedName: "Unhealthy",
                success: false, responseTimeMs: 0, storiesFound: 0
            )
        }
        
        let summary = FeedHealthManager.shared.healthSummary()
        XCTAssertEqual(summary.totalFeeds, 2)
        XCTAssertEqual(summary.healthyCount, 1)
        XCTAssertEqual(summary.unhealthyCount, 1)
        XCTAssertEqual(summary.overallSuccessRate, 0.5, accuracy: 0.01)
        XCTAssertEqual(summary.overallStatus, .unhealthy)
        XCTAssertEqual(summary.feedsNeedingAttention, 1) // unhealthy needs attention
    }
    
    func testHealthSummaryAllHealthy() {
        for url in [testURL1, testURL2, testURL3] {
            for _ in 0..<5 {
                FeedHealthManager.shared.recordFetch(
                    feedURL: url, feedName: "Feed",
                    success: true, responseTimeMs: 100, storiesFound: 10
                )
            }
        }
        let summary = FeedHealthManager.shared.healthSummary()
        XCTAssertEqual(summary.overallStatus, .healthy)
        XCTAssertEqual(summary.feedsNeedingAttention, 0)
        XCTAssertTrue(summary.overallDescription.contains("All 3 feeds healthy"))
    }
    
    func testHealthSummaryEmpty() {
        let summary = FeedHealthManager.shared.healthSummary()
        XCTAssertEqual(summary.totalFeeds, 0)
        XCTAssertEqual(summary.overallStatus, .unknown)
        XCTAssertEqual(summary.overallDescription, "No feeds configured")
    }
    
    func testHealthSummaryWeightedAvgResponseTime() {
        // Feed 1: 5 fetches at 100ms
        for _ in 0..<5 {
            FeedHealthManager.shared.recordFetch(
                feedURL: testURL1, feedName: "Fast",
                success: true, responseTimeMs: 100, storiesFound: 5
            )
        }
        // Feed 2: 1 fetch at 1000ms
        FeedHealthManager.shared.recordFetch(
            feedURL: testURL2, feedName: "Slow",
            success: true, responseTimeMs: 1000, storiesFound: 5
        )
        
        let summary = FeedHealthManager.shared.healthSummary()
        // Weighted: (5×100 + 1×1000) / 6 = 250ms
        XCTAssertEqual(summary.avgResponseTimeMs, 250.0, accuracy: 0.01)
    }
    
    // MARK: - Feeds Needing Attention
    
    func testFeedsNeedingAttention() {
        // Healthy feed
        for _ in 0..<5 {
            FeedHealthManager.shared.recordFetch(
                feedURL: testURL1, feedName: "OK Feed",
                success: true, responseTimeMs: 100, storiesFound: 10
            )
        }
        // Feed with 3+ consecutive failures
        for _ in 0..<3 {
            FeedHealthManager.shared.recordFetch(
                feedURL: testURL2, feedName: "Trouble Feed",
                success: true, responseTimeMs: 100, storiesFound: 5
            )
        }
        for _ in 0..<3 {
            FeedHealthManager.shared.recordFetch(
                feedURL: testURL2, feedName: "Trouble Feed",
                success: false, responseTimeMs: 0, storiesFound: 0
            )
        }
        
        let attention = FeedHealthManager.shared.feedsNeedingAttention()
        XCTAssertEqual(attention.count, 1)
        XCTAssertEqual(attention.first?.feedURL, testURL2)
    }
    
    // MARK: - Fetch History
    
    func testFetchHistoryNewestFirst() {
        for i in 0..<5 {
            let rec = makeRecord(timestamp: daysAgo(5 - i), storiesFound: i + 1)
            FeedHealthManager.shared.recordFetch(record: rec, feedName: "Test")
        }
        let history = FeedHealthManager.shared.fetchHistory(for: testURL1)
        XCTAssertEqual(history.count, 5)
        // Should be newest first
        XCTAssertTrue(history.first!.timestamp > history.last!.timestamp)
    }
    
    func testFetchHistoryWithLimit() {
        for i in 0..<10 {
            let rec = makeRecord(timestamp: daysAgo(10 - i), storiesFound: i)
            FeedHealthManager.shared.recordFetch(record: rec, feedName: "Test")
        }
        let history = FeedHealthManager.shared.fetchHistory(for: testURL1, limit: 3)
        XCTAssertEqual(history.count, 3)
    }
    
    func testFetchHistoryForUnknownFeed() {
        let history = FeedHealthManager.shared.fetchHistory(for: "https://no-such-feed.com")
        XCTAssertTrue(history.isEmpty)
    }
    
    // MARK: - Overall Statistics
    
    func testOverallAvgResponseTime() {
        FeedHealthManager.shared.recordFetch(
            feedURL: testURL1, feedName: "Fast",
            success: true, responseTimeMs: 100, storiesFound: 5
        )
        FeedHealthManager.shared.recordFetch(
            feedURL: testURL2, feedName: "Slow",
            success: true, responseTimeMs: 500, storiesFound: 5
        )
        XCTAssertEqual(FeedHealthManager.shared.overallAvgResponseTimeMs(), 300.0, accuracy: 0.01)
    }
    
    func testOverallAvgResponseTimeExcludesFailures() {
        FeedHealthManager.shared.recordFetch(
            feedURL: testURL1, feedName: "Good",
            success: true, responseTimeMs: 200, storiesFound: 5
        )
        FeedHealthManager.shared.recordFetch(
            feedURL: testURL2, feedName: "Bad",
            success: false, responseTimeMs: 99999, storiesFound: 0
        )
        XCTAssertEqual(FeedHealthManager.shared.overallAvgResponseTimeMs(), 200.0, accuracy: 0.01)
    }
    
    func testOverallAvgResponseTimeZeroWithNoData() {
        XCTAssertEqual(FeedHealthManager.shared.overallAvgResponseTimeMs(), 0)
    }
    
    // MARK: - Data Management
    
    func testClearFeed() {
        FeedHealthManager.shared.recordFetch(
            feedURL: testURL1, feedName: "Feed 1",
            success: true, responseTimeMs: 100, storiesFound: 5
        )
        FeedHealthManager.shared.recordFetch(
            feedURL: testURL2, feedName: "Feed 2",
            success: true, responseTimeMs: 100, storiesFound: 5
        )
        
        FeedHealthManager.shared.clearFeed(testURL1)
        
        XCTAssertEqual(FeedHealthManager.shared.trackedFeedCount(), 1)
        XCTAssertTrue(FeedHealthManager.shared.fetchHistory(for: testURL1).isEmpty)
        XCTAssertFalse(FeedHealthManager.shared.fetchHistory(for: testURL2).isEmpty)
    }
    
    func testClearAll() {
        FeedHealthManager.shared.recordFetch(
            feedURL: testURL1, feedName: "Feed 1",
            success: true, responseTimeMs: 100, storiesFound: 5
        )
        FeedHealthManager.shared.recordFetch(
            feedURL: testURL2, feedName: "Feed 2",
            success: true, responseTimeMs: 200, storiesFound: 8
        )
        
        FeedHealthManager.shared.clearAll()
        
        XCTAssertEqual(FeedHealthManager.shared.totalRecordCount(), 0)
        XCTAssertEqual(FeedHealthManager.shared.trackedFeedCount(), 0)
    }
    
    func testClearFeedAlsoCleansFeedName() {
        FeedHealthManager.shared.recordFetch(
            feedURL: testURL1, feedName: "Named Feed",
            success: true, responseTimeMs: 100, storiesFound: 5
        )
        FeedHealthManager.shared.clearFeed(testURL1)
        XCTAssertNil(FeedHealthManager.shared.feedNames[testURL1])
    }
    
    // MARK: - Record Limits
    
    func testPerFeedRecordLimit() {
        for i in 0..<(FeedHealthManager.maxRecordsPerFeed + 20) {
            let rec = makeRecord(
                timestamp: Date(timeIntervalSinceNow: Double(i)),
                storiesFound: i
            )
            FeedHealthManager.shared.recordFetch(record: rec, feedName: "Test")
        }
        let feedRecords = FeedHealthManager.shared.records[testURL1] ?? []
        XCTAssertLessThanOrEqual(feedRecords.count, FeedHealthManager.maxRecordsPerFeed)
    }
    
    // MARK: - FeedHealthStatus Properties
    
    func testStatusLabels() {
        XCTAssertEqual(FeedHealthStatus.healthy.label, "Healthy")
        XCTAssertEqual(FeedHealthStatus.degraded.label, "Degraded")
        XCTAssertEqual(FeedHealthStatus.unhealthy.label, "Unhealthy")
        XCTAssertEqual(FeedHealthStatus.stale.label, "Stale")
        XCTAssertEqual(FeedHealthStatus.unknown.label, "Unknown")
    }
    
    func testStatusColors() {
        XCTAssertEqual(FeedHealthStatus.healthy.colorName, "green")
        XCTAssertEqual(FeedHealthStatus.degraded.colorName, "yellow")
        XCTAssertEqual(FeedHealthStatus.unhealthy.colorName, "red")
        XCTAssertEqual(FeedHealthStatus.stale.colorName, "orange")
        XCTAssertEqual(FeedHealthStatus.unknown.colorName, "gray")
    }
    
    func testStatusPrioritySortOrder() {
        let statuses: [FeedHealthStatus] = [.healthy, .unknown, .stale, .degraded, .unhealthy]
        let sorted = statuses.sorted { $0.priority < $1.priority }
        XCTAssertEqual(sorted, [.unhealthy, .degraded, .stale, .unknown, .healthy])
    }
    
    // MARK: - FeedHealthReport Properties
    
    func testNeedsAttentionForUnhealthy() {
        for _ in 0..<5 {
            FeedHealthManager.shared.recordFetch(
                feedURL: testURL1, feedName: "Broken",
                success: false, responseTimeMs: 0, storiesFound: 0
            )
        }
        let report = FeedHealthManager.shared.healthReport(for: testURL1)
        XCTAssertTrue(report.needsAttention)
    }
    
    func testNeedsAttentionForHealthy() {
        for _ in 0..<5 {
            FeedHealthManager.shared.recordFetch(
                feedURL: testURL1, feedName: "Good",
                success: true, responseTimeMs: 100, storiesFound: 10
            )
        }
        let report = FeedHealthManager.shared.healthReport(for: testURL1)
        XCTAssertFalse(report.needsAttention)
    }
    
    func testNeedsAttentionWith3ConsecutiveFailures() {
        // Even if overall rate is fine, 3+ consecutive failures = attention
        for _ in 0..<10 {
            FeedHealthManager.shared.recordFetch(
                feedURL: testURL1, feedName: "Flaky",
                success: true, responseTimeMs: 100, storiesFound: 5
            )
        }
        for _ in 0..<3 {
            FeedHealthManager.shared.recordFetch(
                feedURL: testURL1, feedName: "Flaky",
                success: false, responseTimeMs: 0, storiesFound: 0
            )
        }
        let report = FeedHealthManager.shared.healthReport(for: testURL1)
        XCTAssertTrue(report.needsAttention)
    }
    
    // MARK: - Summary Text
    
    func testHealthySummaryText() {
        for _ in 0..<5 {
            FeedHealthManager.shared.recordFetch(
                feedURL: testURL1, feedName: "Good",
                success: true, responseTimeMs: 200, storiesFound: 10
            )
        }
        let report = FeedHealthManager.shared.healthReport(for: testURL1)
        XCTAssertTrue(report.summary.contains("100%"))
        XCTAssertTrue(report.summary.contains("200ms"))
    }
    
    func testUnknownSummaryText() {
        let report = FeedHealthManager.shared.healthReport(for: "https://new.com")
        XCTAssertEqual(report.summary, "No fetch data available")
    }
    
    func testUnhealthySummaryIncludesError() {
        FeedHealthManager.shared.recordFetch(
            feedURL: testURL1, feedName: "Bad",
            success: true, responseTimeMs: 100, storiesFound: 5
        )
        for _ in 0..<5 {
            FeedHealthManager.shared.recordFetch(
                feedURL: testURL1, feedName: "Bad",
                success: false, responseTimeMs: 0, storiesFound: 0,
                errorMessage: "Server error"
            )
        }
        let report = FeedHealthManager.shared.healthReport(for: testURL1)
        XCTAssertTrue(report.summary.contains("Server error"))
    }
    
    // MARK: - HealthSummary Description
    
    func testOverallDescriptionWithAttention() {
        for _ in 0..<5 {
            FeedHealthManager.shared.recordFetch(
                feedURL: testURL1, feedName: "Broken",
                success: false, responseTimeMs: 0, storiesFound: 0
            )
        }
        let summary = FeedHealthManager.shared.healthSummary()
        XCTAssertTrue(summary.overallDescription.contains("attention"))
    }
    
    func testOverallDescriptionSingularFeed() {
        for _ in 0..<5 {
            FeedHealthManager.shared.recordFetch(
                feedURL: testURL1, feedName: "Only Feed",
                success: true, responseTimeMs: 100, storiesFound: 10
            )
        }
        let summary = FeedHealthManager.shared.healthSummary()
        // "All 1 feeds healthy"
        XCTAssertTrue(summary.overallDescription.contains("healthy"))
    }
    
    // MARK: - Notifications
    
    func testRecordFetchPostsNotification() {
        let expectation = XCTNSNotificationExpectation(
            name: .feedHealthDidChange,
            object: nil
        )
        FeedHealthManager.shared.recordFetch(
            feedURL: testURL1, feedName: "Test",
            success: true, responseTimeMs: 100, storiesFound: 5
        )
        wait(for: [expectation], timeout: 1.0)
    }
    
    func testClearAllPostsNotification() {
        FeedHealthManager.shared.recordFetch(
            feedURL: testURL1, feedName: "Test",
            success: true, responseTimeMs: 100, storiesFound: 5
        )
        let expectation = XCTNSNotificationExpectation(
            name: .feedHealthDidChange,
            object: nil
        )
        FeedHealthManager.shared.clearAll()
        wait(for: [expectation], timeout: 1.0)
    }
    
    func testClearFeedPostsNotification() {
        FeedHealthManager.shared.recordFetch(
            feedURL: testURL1, feedName: "Test",
            success: true, responseTimeMs: 100, storiesFound: 5
        )
        let expectation = XCTNSNotificationExpectation(
            name: .feedHealthDidChange,
            object: nil
        )
        FeedHealthManager.shared.clearFeed(testURL1)
        wait(for: [expectation], timeout: 1.0)
    }
    
    // MARK: - Edge Cases
    
    func testSingleFetchReport() {
        FeedHealthManager.shared.recordFetch(
            feedURL: testURL1, feedName: "One Shot",
            success: true, responseTimeMs: 500, storiesFound: 3
        )
        let report = FeedHealthManager.shared.healthReport(for: testURL1)
        XCTAssertEqual(report.status, .unknown) // Below minimum for classification
        XCTAssertEqual(report.totalFetches, 1)
        XCTAssertEqual(report.avgResponseTimeMs, 500.0)
    }
    
    func testAllFailuresFeed() {
        for _ in 0..<5 {
            FeedHealthManager.shared.recordFetch(
                feedURL: testURL1, feedName: "Dead Feed",
                success: false, responseTimeMs: 0, storiesFound: 0,
                errorMessage: "Unreachable"
            )
        }
        let report = FeedHealthManager.shared.healthReport(for: testURL1)
        XCTAssertEqual(report.status, .unhealthy)
        XCTAssertEqual(report.successRate, 0.0)
        XCTAssertEqual(report.consecutiveFailures, 5)
    }
    
    func testLastStoryCountTracking() {
        FeedHealthManager.shared.recordFetch(
            feedURL: testURL1, feedName: "Test",
            success: true, responseTimeMs: 100, storiesFound: 15
        )
        XCTAssertEqual(FeedHealthManager.shared.lastStoryCount[testURL1], 15)
        
        FeedHealthManager.shared.recordFetch(
            feedURL: testURL1, feedName: "Test",
            success: true, responseTimeMs: 100, storiesFound: 20
        )
        XCTAssertEqual(FeedHealthManager.shared.lastStoryCount[testURL1], 20)
    }
    
    func testFailedFetchDoesNotUpdateStoryCount() {
        FeedHealthManager.shared.recordFetch(
            feedURL: testURL1, feedName: "Test",
            success: true, responseTimeMs: 100, storiesFound: 10
        )
        FeedHealthManager.shared.recordFetch(
            feedURL: testURL1, feedName: "Test",
            success: false, responseTimeMs: 0, storiesFound: 0
        )
        XCTAssertEqual(FeedHealthManager.shared.lastStoryCount[testURL1], 10)
    }
    
    func testZeroStoriesDoesNotUpdateStoryCount() {
        FeedHealthManager.shared.recordFetch(
            feedURL: testURL1, feedName: "Test",
            success: true, responseTimeMs: 100, storiesFound: 10
        )
        FeedHealthManager.shared.recordFetch(
            feedURL: testURL1, feedName: "Test",
            success: true, responseTimeMs: 100, storiesFound: 0
        )
        XCTAssertEqual(FeedHealthManager.shared.lastStoryCount[testURL1], 10)
    }
    
    // MARK: - FetchRecord Equatable
    
    func testFetchRecordEquality() {
        let date = Date()
        let r1 = FetchRecord(feedURL: testURL1, timestamp: date, success: true, responseTimeMs: 100, errorMessage: nil, storiesFound: 5)
        let r2 = FetchRecord(feedURL: testURL1, timestamp: date, success: true, responseTimeMs: 100, errorMessage: nil, storiesFound: 5)
        XCTAssertEqual(r1, r2)
    }
    
    func testFetchRecordInequality() {
        let date = Date()
        let r1 = FetchRecord(feedURL: testURL1, timestamp: date, success: true, responseTimeMs: 100, errorMessage: nil, storiesFound: 5)
        let r2 = FetchRecord(feedURL: testURL2, timestamp: date, success: true, responseTimeMs: 100, errorMessage: nil, storiesFound: 5)
        XCTAssertNotEqual(r1, r2)
    }
}
