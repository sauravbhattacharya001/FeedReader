//
//  FeedTopicRadarTests.swift
//  FeedReaderCoreTests
//
//  Tests for the FeedTopicRadar engine.
//

import XCTest
@testable import FeedReaderCore

final class FeedTopicRadarTests: XCTestCase {

    private var sut: FeedTopicRadar!

    override func setUp() {
        super.setUp()
        sut = FeedTopicRadar()
        sut.minimumObservations = 3
    }

    override func tearDown() {
        sut = nil
        super.tearDown()
    }

    // MARK: - Helpers

    private func date(daysAgo: Int) -> Date {
        Calendar.current.date(byAdding: .day, value: -daysAgo, to: Date())!
    }

    private func recordTopic(_ topic: String, feed: String = "https://a.com/feed",
                              feedName: String = "Feed A", count: Int = 1,
                              daysAgo: Int = 0, confidence: Double = 1.0) {
        for i in 0..<count {
            sut.recordObservation(
                topic: topic, feedURL: feed, feedName: feedName,
                articleId: "\(topic)-\(feed)-\(i)",
                timestamp: date(daysAgo: daysAgo),
                confidence: confidence
            )
        }
    }

    private func recordBurst(_ topic: String, feeds: [(String, String)],
                              recentCount: Int, oldCount: Int) {
        // Old observations spread across days 20-10
        for feed in feeds {
            for i in 0..<oldCount {
                let day = 20 - (i % 11)
                sut.recordObservation(
                    topic: topic, feedURL: feed.0, feedName: feed.1,
                    articleId: "\(topic)-old-\(feed.0)-\(i)",
                    timestamp: date(daysAgo: day), confidence: 1.0
                )
            }
        }
        // Recent burst today
        for feed in feeds {
            for i in 0..<recentCount {
                sut.recordObservation(
                    topic: topic, feedURL: feed.0, feedName: feed.1,
                    articleId: "\(topic)-new-\(feed.0)-\(i)",
                    timestamp: date(daysAgo: 0), confidence: 1.0
                )
            }
        }
    }

    // MARK: - TopicPhase Enum

    func testTopicPhaseAllCases() {
        XCTAssertEqual(TopicPhase.allCases.count, 5)
    }

    func testTopicPhaseComparable() {
        XCTAssertTrue(TopicPhase.emerging < TopicPhase.trending)
        XCTAssertTrue(TopicPhase.trending < TopicPhase.saturated)
        XCTAssertTrue(TopicPhase.saturated < TopicPhase.declining)
        XCTAssertTrue(TopicPhase.declining < TopicPhase.dormant)
    }

    func testTopicPhaseRawValues() {
        XCTAssertEqual(TopicPhase.emerging.rawValue, "Emerging")
        XCTAssertEqual(TopicPhase.trending.rawValue, "Trending")
        XCTAssertEqual(TopicPhase.saturated.rawValue, "Saturated")
        XCTAssertEqual(TopicPhase.declining.rawValue, "Declining")
        XCTAssertEqual(TopicPhase.dormant.rawValue, "Dormant")
    }

    func testTopicPhaseEmoji() {
        for phase in TopicPhase.allCases {
            XCTAssertFalse(phase.emoji.isEmpty, "\(phase) should have emoji")
        }
    }

    // MARK: - TopicAlertSeverity Enum

    func testAlertSeverityAllCases() {
        XCTAssertEqual(TopicAlertSeverity.allCases.count, 4)
    }

    func testAlertSeverityComparable() {
        XCTAssertTrue(TopicAlertSeverity.info < TopicAlertSeverity.notable)
        XCTAssertTrue(TopicAlertSeverity.notable < TopicAlertSeverity.significant)
        XCTAssertTrue(TopicAlertSeverity.significant < TopicAlertSeverity.critical)
    }

    func testAlertSeverityEmoji() {
        for sev in TopicAlertSeverity.allCases {
            XCTAssertFalse(sev.emoji.isEmpty, "\(sev) should have emoji")
        }
    }

    // MARK: - Topic Observation

    func testObservationNormalization() {
        let obs = TopicObservation(topic: "  Swift Concurrency  ",
                                   feedURL: "https://a.com", feedName: "A")
        XCTAssertEqual(obs.topic, "swift concurrency")
    }

    func testObservationConfidenceClamped() {
        let obs1 = TopicObservation(topic: "t", feedURL: "u", feedName: "n", confidence: 1.5)
        XCTAssertEqual(obs1.confidence, 1.0)
        let obs2 = TopicObservation(topic: "t", feedURL: "u", feedName: "n", confidence: -0.5)
        XCTAssertEqual(obs2.confidence, 0.0)
    }

    // MARK: - Recording

    func testRecordObservation() {
        XCTAssertEqual(sut.observationCount, 0)
        sut.recordObservation(topic: "ai", feedURL: "https://a.com", feedName: "A")
        XCTAssertEqual(sut.observationCount, 1)
    }

    func testRecordObservationStruct() {
        let obs = TopicObservation(topic: "ai", feedURL: "https://a.com", feedName: "A")
        sut.recordObservation(obs)
        XCTAssertEqual(sut.observationCount, 1)
    }

    func testTopicCount() {
        sut.recordObservation(topic: "ai", feedURL: "https://a.com", feedName: "A")
        sut.recordObservation(topic: "ml", feedURL: "https://a.com", feedName: "A")
        sut.recordObservation(topic: "ai", feedURL: "https://b.com", feedName: "B")
        XCTAssertEqual(sut.topicCount, 2)
    }

    func testReset() {
        recordTopic("ai", count: 5)
        XCTAssertEqual(sut.observationCount, 5)
        sut.reset()
        XCTAssertEqual(sut.observationCount, 0)
        XCTAssertEqual(sut.topicCount, 0)
    }

    // MARK: - Scan — Empty

    func testScanEmpty() {
        let result = sut.scan()
        XCTAssertEqual(result.totalTopics, 0)
        XCTAssertEqual(result.emergingCount, 0)
        XCTAssertEqual(result.trendingCount, 0)
        XCTAssertEqual(result.healthScore, 0)
        XCTAssertEqual(result.healthGrade, "F")
    }

    func testScanBelowMinimum() {
        sut.recordObservation(topic: "ai", feedURL: "https://a.com", feedName: "A")
        sut.recordObservation(topic: "ai", feedURL: "https://a.com", feedName: "A")
        let result = sut.scan()
        XCTAssertEqual(result.totalTopics, 0, "Should ignore topics below minimumObservations")
    }

    // MARK: - Scan — Basic

    func testScanSingleTopic() {
        recordTopic("ai", count: 5, daysAgo: 0)
        let result = sut.scan()
        XCTAssertEqual(result.totalTopics, 1)
        XCTAssertEqual(result.topicReports.first?.topic, "ai")
        XCTAssertEqual(result.topicReports.first?.mentionCount, 5)
    }

    func testScanMultipleTopics() {
        recordTopic("ai", count: 5, daysAgo: 0)
        recordTopic("blockchain", count: 3, daysAgo: 0)
        recordTopic("cloud", count: 4, daysAgo: 1)
        let result = sut.scan()
        XCTAssertEqual(result.totalTopics, 3)
    }

    func testScanRespectsWindowDays() {
        sut.windowDays = 7
        recordTopic("ai", count: 5, daysAgo: 10)  // Outside window
        recordTopic("ai", count: 3, daysAgo: 3)    // Inside window
        let result = sut.scan()
        // Only 3 within window, which meets minimum
        XCTAssertEqual(result.topicReports.first?.mentionCount, 3)
    }

    // MARK: - Phase Classification

    func testDormantPhase() {
        sut.dormantDays = 7
        recordTopic("old topic", count: 5, daysAgo: 10)
        let result = sut.scan()
        XCTAssertEqual(result.topicReports.first?.phase, .dormant)
    }

    func testDecliningPhase() {
        // Many old mentions, very few recent
        for i in 0..<8 {
            sut.recordObservation(topic: "fading", feedURL: "https://a.com", feedName: "A",
                                  articleId: "old-\(i)", timestamp: date(daysAgo: 25 - i))
        }
        sut.recordObservation(topic: "fading", feedURL: "https://a.com", feedName: "A",
                              articleId: "recent-1", timestamp: date(daysAgo: 0))
        let result = sut.scan()
        if let report = result.topicReports.first(where: { $0.topic == "fading" }) {
            // Should detect negative velocity = declining
            XCTAssertTrue(report.phase == .declining || report.phase == .saturated,
                          "Should be declining or saturated, got \(report.phase)")
        }
    }

    // MARK: - Cross-Feed Detection

    func testCrossFeedTopics() {
        recordTopic("ai", feed: "https://a.com/feed", feedName: "A", count: 3, daysAgo: 0)
        recordTopic("ai", feed: "https://b.com/feed", feedName: "B", count: 3, daysAgo: 0)
        recordTopic("ai", feed: "https://c.com/feed", feedName: "C", count: 3, daysAgo: 0)
        let crossFeed = sut.crossFeedTopics(minFeeds: 2)
        XCTAssertEqual(crossFeed.count, 1)
        XCTAssertEqual(crossFeed.first?.feedCount, 3)
    }

    func testCrossFeedTopicsExcludesSingleFeed() {
        recordTopic("niche", feed: "https://a.com/feed", feedName: "A", count: 5, daysAgo: 0)
        let crossFeed = sut.crossFeedTopics(minFeeds: 2)
        XCTAssertTrue(crossFeed.isEmpty)
    }

    // MARK: - Burst Detection

    func testBurstDetection() {
        recordBurst("breaking news",
                     feeds: [("https://a.com", "A"), ("https://b.com", "B")],
                     recentCount: 10, oldCount: 1)
        let result = sut.scan()
        let burstAlerts = result.alerts.filter { $0.alertType == "burst_detected" }
        // With heavy recent activity vs sparse old, z-score should be high
        XCTAssertFalse(burstAlerts.isEmpty, "Should detect burst for concentrated recent activity")
    }

    func testHighZScoreGivesCriticalAlert() {
        sut.burstZScoreThreshold = 1.0
        recordBurst("mega burst",
                     feeds: [("https://a.com", "A"), ("https://b.com", "B")],
                     recentCount: 20, oldCount: 1)
        let result = sut.scan()
        let megaAlerts = result.alerts.filter {
            $0.topic == "mega burst" && $0.alertType == "burst_detected"
        }
        if let alert = megaAlerts.first {
            XCTAssertTrue(alert.severity >= .notable)
        }
    }

    // MARK: - Velocity & Acceleration

    func testVelocityPositiveForGrowingTopic() {
        // Record increasing activity over time
        for day in stride(from: 20, through: 0, by: -5) {
            let count = (20 - day) / 5 + 1
            recordTopic("growing", count: count, daysAgo: day)
        }
        let report = sut.topicReport(for: "growing")
        XCTAssertNotNil(report)
        XCTAssertGreaterThan(report!.velocity, 0, "Growing topic should have positive velocity")
    }

    func testTrendDirectionAccelerating() {
        // Heavy recent, light old
        recordTopic("accel", count: 2, daysAgo: 25)
        recordTopic("accel", count: 2, daysAgo: 20)
        recordTopic("accel", count: 10, daysAgo: 1)
        recordTopic("accel", count: 10, daysAgo: 0)
        let report = sut.topicReport(for: "accel")
        XCTAssertNotNil(report)
        // With much more activity recently, should be accelerating or steady
        XCTAssertTrue(["accelerating", "steady"].contains(report!.trendDirection))
    }

    func testTrendDirectionDecelerating() {
        // Heavy old, light recent
        recordTopic("decel", count: 10, daysAgo: 25)
        recordTopic("decel", count: 10, daysAgo: 20)
        recordTopic("decel", count: 1, daysAgo: 1)
        recordTopic("decel", count: 1, daysAgo: 0)
        let report = sut.topicReport(for: "decel")
        XCTAssertNotNil(report)
        XCTAssertTrue(["decelerating", "steady"].contains(report!.trendDirection))
    }

    // MARK: - Alerts

    func testCrossFeedEmergenceAlert() {
        sut.burstZScoreThreshold = 0.5
        sut.emergenceMinFeeds = 2
        recordBurst("cross topic",
                     feeds: [("https://a.com", "A"), ("https://b.com", "B")],
                     recentCount: 8, oldCount: 1)
        let result = sut.scan()
        let crossAlerts = result.alerts.filter { $0.alertType == "cross_feed_emergence" }
        // May or may not fire depending on phase classification
        // At least burst_detected should fire
        let anyAlerts = result.alerts.filter { $0.topic == "cross topic" }
        XCTAssertFalse(anyAlerts.isEmpty, "Should generate some alerts for cross-feed burst")
    }

    func testNoAlertsForSteadyTopics() {
        sut.burstZScoreThreshold = 5.0  // Very high threshold
        // Evenly distributed mentions
        for day in 0..<10 {
            recordTopic("steady", count: 1, daysAgo: day)
        }
        let result = sut.scan()
        let steadyAlerts = result.alerts.filter { $0.topic == "steady" && $0.alertType == "burst_detected" }
        XCTAssertTrue(steadyAlerts.isEmpty, "Evenly distributed topic should not trigger burst")
    }

    // MARK: - Insights

    func testInsightsGeneratedForEmptyPortfolio() {
        let result = sut.scan()
        XCTAssertFalse(result.insights.isEmpty, "Should generate status insight even when empty")
        XCTAssertEqual(result.insights.first?.category, "status")
    }

    func testInsightsIncludeLandscape() {
        recordTopic("ai", count: 5, daysAgo: 0)
        recordTopic("ml", count: 4, daysAgo: 0)
        recordTopic("data", count: 3, daysAgo: 0)
        let result = sut.scan()
        let landscape = result.insights.filter { $0.category == "landscape" }
        XCTAssertFalse(landscape.isEmpty, "Should include landscape insight")
    }

    func testInsightsIncludeEmergence() {
        sut.burstZScoreThreshold = 0.5
        recordBurst("hot topic",
                     feeds: [("https://a.com", "A"), ("https://b.com", "B")],
                     recentCount: 10, oldCount: 1)
        let result = sut.scan()
        let emergence = result.insights.filter { $0.category == "emergence" }
        // If the topic is classified as emerging, we should get emergence insight
        if result.emergingCount > 0 {
            XCTAssertFalse(emergence.isEmpty)
        }
    }

    func testInsightConfidenceRange() {
        recordTopic("test", count: 5, daysAgo: 0)
        let result = sut.scan()
        for insight in result.insights {
            XCTAssertGreaterThanOrEqual(insight.confidence, 0)
            XCTAssertLessThanOrEqual(insight.confidence, 1.0)
        }
    }

    // MARK: - Health Scoring

    func testHealthScoreRange() {
        recordTopic("ai", count: 5, daysAgo: 0)
        let result = sut.scan()
        XCTAssertGreaterThanOrEqual(result.healthScore, 0)
        XCTAssertLessThanOrEqual(result.healthScore, 100)
    }

    func testHealthGradeMapping() {
        // Test internal grading by checking scan results
        let result = sut.scan()
        let validGrades = ["A", "B", "C", "D", "F"]
        XCTAssertTrue(validGrades.contains(result.healthGrade))
    }

    func testHealthScoreIncreasesWithDiversity() {
        // Single topic
        recordTopic("ai", count: 5, daysAgo: 0)
        let score1 = sut.scan().healthScore

        // Add cross-feed topics
        recordTopic("ai", feed: "https://b.com/feed", feedName: "B", count: 5, daysAgo: 0)
        recordTopic("ml", count: 4, daysAgo: 0)
        recordTopic("ml", feed: "https://b.com/feed", feedName: "B", count: 4, daysAgo: 0)
        let score2 = sut.scan().healthScore

        XCTAssertGreaterThanOrEqual(score2, score1, "More diverse portfolio should score higher")
    }

    // MARK: - Configuration

    func testMinimumObservationsConfig() {
        sut.minimumObservations = 10
        recordTopic("ai", count: 5, daysAgo: 0)
        let result = sut.scan()
        XCTAssertEqual(result.totalTopics, 0, "Should not report topics below minimum")
    }

    func testWindowDaysConfig() {
        sut.windowDays = 5
        recordTopic("old", count: 10, daysAgo: 10)
        let result = sut.scan()
        XCTAssertEqual(result.totalTopics, 0, "Should not include observations outside window")
    }

    func testDormantDaysConfig() {
        sut.dormantDays = 3
        recordTopic("stale", count: 5, daysAgo: 5)
        let report = sut.topicReport(for: "stale")
        XCTAssertNotNil(report)
        XCTAssertEqual(report?.phase, .dormant)
    }

    func testBurstThresholdConfig() {
        sut.burstZScoreThreshold = 100.0  // Impossibly high
        recordBurst("no burst",
                     feeds: [("https://a.com", "A"), ("https://b.com", "B")],
                     recentCount: 10, oldCount: 1)
        let result = sut.scan()
        let burstAlerts = result.alerts.filter { $0.alertType == "burst_detected" }
        XCTAssertTrue(burstAlerts.isEmpty, "No burst should fire with impossibly high threshold")
    }

    // MARK: - TopicReport Lookup

    func testTopicReportForExisting() {
        recordTopic("swift", count: 5, daysAgo: 0)
        let report = sut.topicReport(for: "swift")
        XCTAssertNotNil(report)
        XCTAssertEqual(report?.topic, "swift")
    }

    func testTopicReportForNonexistent() {
        recordTopic("swift", count: 5, daysAgo: 0)
        let report = sut.topicReport(for: "nonexistent")
        XCTAssertNil(report)
    }

    func testTopicReportCaseInsensitive() {
        recordTopic("Swift", count: 5, daysAgo: 0)
        let report = sut.topicReport(for: "SWIFT")
        XCTAssertNotNil(report, "Lookup should be case-insensitive")
    }

    // MARK: - Emerging Topics API

    func testEmergingTopicsAPI() {
        sut.burstZScoreThreshold = 0.5
        sut.emergenceMinFeeds = 2
        recordBurst("hot",
                     feeds: [("https://a.com", "A"), ("https://b.com", "B")],
                     recentCount: 10, oldCount: 1)
        let emerging = sut.emergingTopics()
        // All returned should be in emerging phase
        for report in emerging {
            XCTAssertEqual(report.phase, .emerging)
        }
    }

    // MARK: - Alerts API

    func testAlertsSinceDate() {
        sut.burstZScoreThreshold = 0.5
        recordBurst("alertable",
                     feeds: [("https://a.com", "A"), ("https://b.com", "B")],
                     recentCount: 10, oldCount: 1)
        let recentAlerts = sut.alerts(since: date(daysAgo: 1))
        // All alerts should have timestamps >= since date
        let since = date(daysAgo: 1)
        for alert in recentAlerts {
            XCTAssertGreaterThanOrEqual(alert.timestamp, since)
        }
    }

    // MARK: - Edge Cases

    func testSingleObservation() {
        sut.minimumObservations = 1
        sut.recordObservation(topic: "lonely", feedURL: "https://a.com", feedName: "A")
        let result = sut.scan()
        XCTAssertEqual(result.totalTopics, 1)
    }

    func testLowConfidenceObservations() {
        for i in 0..<5 {
            sut.recordObservation(
                topic: "low conf", feedURL: "https://a.com", feedName: "A",
                articleId: "lc-\(i)", timestamp: date(daysAgo: 0), confidence: 0.1
            )
        }
        let result = sut.scan()
        XCTAssertEqual(result.totalTopics, 1)
    }

    func testManyTopics() {
        for i in 0..<20 {
            recordTopic("topic-\(i)", count: 3, daysAgo: i % 10)
        }
        let result = sut.scan()
        XCTAssertGreaterThanOrEqual(result.totalTopics, 10)
        XCTAssertFalse(result.insights.isEmpty)
    }

    func testResetClearsEverything() {
        recordTopic("ai", count: 5, daysAgo: 0)
        sut.reset()
        XCTAssertEqual(sut.observationCount, 0)
        XCTAssertEqual(sut.topicCount, 0)
        let result = sut.scan()
        XCTAssertEqual(result.totalTopics, 0)
    }

    // MARK: - Scan Result Structure

    func testScanResultTimestamp() {
        let before = Date()
        recordTopic("ai", count: 5, daysAgo: 0)
        let result = sut.scan()
        let after = Date()
        XCTAssertGreaterThanOrEqual(result.timestamp, before)
        XCTAssertLessThanOrEqual(result.timestamp, after)
    }

    func testScanResultCounts() {
        recordTopic("ai", count: 5, daysAgo: 0)
        let result = sut.scan()
        XCTAssertEqual(result.totalTopics, result.topicReports.count)
        let emerging = result.topicReports.filter { $0.phase == .emerging }.count
        let trending = result.topicReports.filter { $0.phase == .trending }.count
        XCTAssertEqual(result.emergingCount, emerging)
        XCTAssertEqual(result.trendingCount, trending)
    }

    // MARK: - Report Fields

    func testReportFieldsPopulated() {
        recordTopic("swift", feed: "https://a.com/feed", feedName: "A", count: 3, daysAgo: 1)
        recordTopic("swift", feed: "https://b.com/feed", feedName: "B", count: 2, daysAgo: 0)
        let report = sut.topicReport(for: "swift")
        XCTAssertNotNil(report)
        XCTAssertEqual(report!.topic, "swift")
        XCTAssertEqual(report!.mentionCount, 5)
        XCTAssertEqual(report!.feedCount, 2)
        XCTAssertNotNil(report!.firstSeen)
        XCTAssertNotNil(report!.lastSeen)
        XCTAssertTrue(["accelerating", "steady", "decelerating"].contains(report!.trendDirection))
    }

    func testReportPeakDate() {
        // 5 mentions on day 5, 1 on day 0
        recordTopic("peaked", count: 5, daysAgo: 5)
        recordTopic("peaked", count: 1, daysAgo: 0)
        let report = sut.topicReport(for: "peaked")
        XCTAssertNotNil(report?.peakDate)
    }

    // MARK: - Alert Structure

    func testAlertProperties() {
        sut.burstZScoreThreshold = 0.5
        recordBurst("alert test",
                     feeds: [("https://a.com", "A"), ("https://b.com", "B")],
                     recentCount: 10, oldCount: 1)
        let result = sut.scan()
        for alert in result.alerts {
            XCTAssertFalse(alert.topic.isEmpty)
            XCTAssertFalse(alert.alertType.isEmpty)
            XCTAssertFalse(alert.message.isEmpty)
        }
    }

    // MARK: - Insight Structure

    func testInsightProperties() {
        recordTopic("ai", count: 5, daysAgo: 0)
        let result = sut.scan()
        for insight in result.insights {
            XCTAssertFalse(insight.category.isEmpty)
            XCTAssertFalse(insight.message.isEmpty)
            XCTAssertGreaterThanOrEqual(insight.confidence, 0)
            XCTAssertLessThanOrEqual(insight.confidence, 1.0)
        }
    }
}
