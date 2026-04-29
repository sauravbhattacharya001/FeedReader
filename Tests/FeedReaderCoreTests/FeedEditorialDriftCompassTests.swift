//
//  FeedEditorialDriftCompassTests.swift
//  FeedReaderCoreTests
//
//  Tests for the Feed Editorial Drift Compass engine.
//

import XCTest
@testable import FeedReaderCore

final class FeedEditorialDriftCompassTests: XCTestCase {

    var compass: FeedEditorialDriftCompass!

    override func setUp() {
        super.setUp()
        compass = FeedEditorialDriftCompass()
        compass.minimumIdentityArticles = 5 // Lower threshold for tests
    }

    override func tearDown() {
        compass = nil
        super.tearDown()
    }

    // MARK: - Basic Functionality

    func testEmptyCompassReturnsNilReport() {
        let report = compass.analyzeDrift(feedURL: "https://example.com/feed")
        XCTAssertNil(report)
    }

    func testIngestArticleStoresObservations() {
        compass.ingestArticle(feedURL: "https://tech.com/feed", topics: ["technology", "ai"])
        XCTAssertEqual(compass.totalObservations, 2)
        XCTAssertEqual(compass.monitoredFeeds.count, 1)
    }

    func testIngestBatchMultipleArticles() {
        let articles: [(title: String, topics: [String], timestamp: Date)] = [
            ("Article 1", ["tech"], Date()),
            ("Article 2", ["science"], Date()),
            ("Article 3", ["tech"], Date()),
        ]
        compass.ingestBatch(feedURL: "https://blog.com/rss", articles: articles)
        XCTAssertEqual(compass.totalObservations, 4)
    }

    func testFeedURLNormalization() {
        compass.ingestArticle(feedURL: "HTTPS://EXAMPLE.COM/Feed", topics: ["tech"])
        compass.ingestArticle(feedURL: "https://example.com/feed", topics: ["science"])
        XCTAssertEqual(compass.monitoredFeeds.count, 1)
        XCTAssertEqual(compass.totalObservations, 2)
    }

    func testClearFeed() {
        compass.ingestArticle(feedURL: "https://a.com/feed", topics: ["tech"])
        compass.ingestArticle(feedURL: "https://b.com/feed", topics: ["science"])
        compass.clearFeed(feedURL: "https://a.com/feed")
        XCTAssertEqual(compass.monitoredFeeds.count, 1)
    }

    func testClearAll() {
        compass.ingestArticle(feedURL: "https://a.com/feed", topics: ["tech"])
        compass.ingestArticle(feedURL: "https://b.com/feed", topics: ["science"])
        compass.clearAll()
        XCTAssertEqual(compass.monitoredFeeds.count, 0)
        XCTAssertEqual(compass.totalObservations, 0)
    }

    // MARK: - Insufficient Data

    func testInsufficientDataReturnsDriftTypeInsufficient() {
        // Only 2 articles, below minimumIdentityArticles threshold of 5
        compass.ingestArticle(feedURL: "https://test.com/feed", topics: ["tech"], timestamp: Date())
        compass.ingestArticle(feedURL: "https://test.com/feed", topics: ["tech"], timestamp: Date())

        let report = compass.analyzeDrift(feedURL: "https://test.com/feed")
        XCTAssertNotNil(report)
        XCTAssertEqual(report?.driftType, .insufficient)
        XCTAssertEqual(report?.driftScore, 0)
    }

    // MARK: - Stable Feed Detection

    func testStableFeedDetectedCorrectly() {
        let feedURL = "https://techblog.com/feed"
        let baseDate = Date().addingTimeInterval(-90 * 86400) // 90 days ago

        // Consistently tech-focused over time
        for i in 0..<20 {
            let timestamp = baseDate.addingTimeInterval(Double(i) * 86400)
            compass.ingestArticle(
                feedURL: feedURL,
                feedName: "TechBlog",
                topics: ["technology", "programming"],
                timestamp: timestamp
            )
        }

        let report = compass.analyzeDrift(feedURL: feedURL)
        XCTAssertNotNil(report)
        XCTAssertEqual(report?.driftType, .stable)
        XCTAssertLessThan(report?.driftScore ?? 100, 15)
        XCTAssertEqual(report?.severity, .none)
    }

    // MARK: - Topic Invasion Detection

    func testTopicInvasionDetected() {
        let feedURL = "https://techblog.com/feed"
        let baseDate = Date().addingTimeInterval(-90 * 86400)

        // Establish tech identity (first 60 days)
        for i in 0..<15 {
            let timestamp = baseDate.addingTimeInterval(Double(i) * 4 * 86400)
            compass.ingestArticle(feedURL: feedURL, topics: ["technology", "programming"], timestamp: timestamp)
        }

        // Recent: suddenly politics-heavy
        for i in 0..<10 {
            let timestamp = Date().addingTimeInterval(-Double(i) * 86400)
            compass.ingestArticle(feedURL: feedURL, topics: ["politics", "government"], timestamp: timestamp)
        }

        let report = compass.analyzeDrift(feedURL: feedURL)
        XCTAssertNotNil(report)
        XCTAssertGreaterThan(report?.driftScore ?? 0, 15)
        XCTAssertTrue(report?.invadingTopics.contains("politics") ?? false)
    }

    // MARK: - Identity Erosion Detection

    func testIdentityErosionDetected() {
        let feedURL = "https://sciencedaily.com/feed"
        let baseDate = Date().addingTimeInterval(-90 * 86400)

        // Establish science identity
        for i in 0..<15 {
            let timestamp = baseDate.addingTimeInterval(Double(i) * 4 * 86400)
            compass.ingestArticle(feedURL: feedURL, topics: ["science", "research"], timestamp: timestamp)
        }

        // Recent: science disappearing, replaced by general content
        for i in 0..<10 {
            let timestamp = Date().addingTimeInterval(-Double(i) * 86400)
            compass.ingestArticle(feedURL: feedURL, topics: ["general"], timestamp: timestamp)
        }

        let report = compass.analyzeDrift(feedURL: feedURL)
        XCTAssertNotNil(report)
        XCTAssertGreaterThan(report?.driftScore ?? 0, 15)
        XCTAssertTrue(report?.erodingTopics.contains("science") ?? false || report?.erodingTopics.contains("research") ?? false)
    }

    // MARK: - Editorial Identity

    func testEditorialIdentityBuilt() {
        let feedURL = "https://techblog.com/feed"
        let baseDate = Date().addingTimeInterval(-30 * 86400)

        for i in 0..<10 {
            let timestamp = baseDate.addingTimeInterval(Double(i) * 86400)
            compass.ingestArticle(feedURL: feedURL, topics: ["technology"], timestamp: timestamp)
            compass.ingestArticle(feedURL: feedURL, topics: ["programming"], timestamp: timestamp)
            compass.ingestArticle(feedURL: feedURL, topics: ["technology"], timestamp: timestamp)
        }

        let identity = compass.getIdentity(feedURL: feedURL)
        XCTAssertNotNil(identity)
        XCTAssertTrue(identity?.brandTopics.contains("technology") ?? false)
        XCTAssertGreaterThan(identity?.coreTopics["technology"] ?? 0, 0.5)
    }

    func testFocusScoreHighForSingleTopic() {
        let feedURL = "https://mono.com/feed"
        for i in 0..<10 {
            let timestamp = Date().addingTimeInterval(-Double(i) * 86400)
            compass.ingestArticle(feedURL: feedURL, topics: ["technology"], timestamp: timestamp)
        }
        let identity = compass.getIdentity(feedURL: feedURL)
        XCTAssertNotNil(identity)
        // Single topic = max focus
        XCTAssertEqual(identity?.focusScore ?? 0, 1.0, accuracy: 0.01)
    }

    func testFocusScoreLowerForDiverseFeed() {
        let feedURL = "https://diverse.com/feed"
        let topics = ["tech", "science", "politics", "sports", "health"]
        for i in 0..<10 {
            let timestamp = Date().addingTimeInterval(-Double(i) * 86400)
            for topic in topics {
                compass.ingestArticle(feedURL: feedURL, topics: [topic], timestamp: timestamp)
            }
        }
        let identity = compass.getIdentity(feedURL: feedURL)
        XCTAssertNotNil(identity)
        XCTAssertLessThan(identity?.focusScore ?? 1.0, 0.3)
    }

    // MARK: - Drift Vectors

    func testDriftVectorsComputedCorrectly() {
        let feedURL = "https://drifty.com/feed"
        let baseDate = Date().addingTimeInterval(-90 * 86400)

        // Baseline: heavy tech
        for i in 0..<12 {
            let timestamp = baseDate.addingTimeInterval(Double(i) * 5 * 86400)
            compass.ingestArticle(feedURL: feedURL, topics: ["technology"], timestamp: timestamp)
        }

        // Recent: heavy politics
        for i in 0..<8 {
            let timestamp = Date().addingTimeInterval(-Double(i) * 86400)
            compass.ingestArticle(feedURL: feedURL, topics: ["politics"], timestamp: timestamp)
        }

        let report = compass.analyzeDrift(feedURL: feedURL)
        XCTAssertNotNil(report)
        XCTAssertFalse(report?.driftVectors.isEmpty ?? true)

        // Politics should be growing
        let politicsVector = report?.driftVectors.first(where: { $0.topic == "politics" })
        XCTAssertNotNil(politicsVector)
        XCTAssertEqual(politicsVector?.direction, .growing)
        XCTAssertGreaterThan(politicsVector?.delta ?? 0, 0)
    }

    // MARK: - Severity Classification

    func testSeverityNoneForLowDrift() {
        let feedURL = "https://stable.com/feed"
        let baseDate = Date().addingTimeInterval(-90 * 86400)

        for i in 0..<20 {
            let timestamp = baseDate.addingTimeInterval(Double(i) * 4 * 86400)
            compass.ingestArticle(feedURL: feedURL, topics: ["technology"], timestamp: timestamp)
        }

        let report = compass.analyzeDrift(feedURL: feedURL)
        XCTAssertEqual(report?.severity, .none)
    }

    // MARK: - Predictions

    func testPredictedTopicsNotEmpty() {
        let feedURL = "https://pred.com/feed"
        let baseDate = Date().addingTimeInterval(-90 * 86400)

        for i in 0..<15 {
            let timestamp = baseDate.addingTimeInterval(Double(i) * 4 * 86400)
            compass.ingestArticle(feedURL: feedURL, topics: ["technology"], timestamp: timestamp)
        }
        for i in 0..<10 {
            let timestamp = Date().addingTimeInterval(-Double(i) * 86400)
            compass.ingestArticle(feedURL: feedURL, topics: ["politics"], timestamp: timestamp)
        }

        let report = compass.analyzeDrift(feedURL: feedURL)
        XCTAssertNotNil(report)
        XCTAssertFalse(report?.predictedTopics.isEmpty ?? true)
    }

    // MARK: - Fleet Analysis

    func testFleetAnalysisMultipleFeeds() {
        let feeds = ["https://a.com/feed", "https://b.com/feed", "https://c.com/feed"]
        let baseDate = Date().addingTimeInterval(-90 * 86400)

        for feed in feeds {
            for i in 0..<10 {
                let timestamp = baseDate.addingTimeInterval(Double(i) * 86400)
                compass.ingestArticle(feedURL: feed, topics: ["technology"], timestamp: timestamp)
            }
        }

        let fleet = compass.analyzeFleet()
        XCTAssertEqual(fleet.feedReports.count, 3)
        XCTAssertGreaterThanOrEqual(fleet.subscriptionHealthScore, 0)
        XCTAssertLessThanOrEqual(fleet.subscriptionHealthScore, 100)
    }

    func testFleetReportSortedByDriftScore() {
        let baseDate = Date().addingTimeInterval(-90 * 86400)

        // Stable feed
        for i in 0..<15 {
            compass.ingestArticle(feedURL: "https://stable.com/feed", topics: ["tech"], timestamp: baseDate.addingTimeInterval(Double(i) * 5 * 86400))
        }

        // Drifting feed
        for i in 0..<12 {
            compass.ingestArticle(feedURL: "https://drifty.com/feed", topics: ["tech"], timestamp: baseDate.addingTimeInterval(Double(i) * 5 * 86400))
        }
        for i in 0..<8 {
            compass.ingestArticle(feedURL: "https://drifty.com/feed", topics: ["politics"], timestamp: Date().addingTimeInterval(-Double(i) * 86400))
        }

        let fleet = compass.analyzeFleet()
        if fleet.feedReports.count >= 2 {
            XCTAssertGreaterThanOrEqual(fleet.feedReports[0].driftScore, fleet.feedReports[1].driftScore)
        }
    }

    // MARK: - Topic Extraction from Title

    func testTopicExtractionFromTitle() {
        compass.ingestArticle(
            feedURL: "https://news.com/feed",
            title: "New AI Model Breaks Machine Learning Records",
            topics: [],
            timestamp: Date()
        )
        XCTAssertGreaterThan(compass.totalObservations, 0)
    }

    // MARK: - Report Content

    func testReportContainsSummary() {
        let feedURL = "https://summarized.com/feed"
        let baseDate = Date().addingTimeInterval(-90 * 86400)

        for i in 0..<15 {
            compass.ingestArticle(feedURL: feedURL, feedName: "SumFeed", topics: ["tech"], timestamp: baseDate.addingTimeInterval(Double(i) * 5 * 86400))
        }
        for i in 0..<8 {
            compass.ingestArticle(feedURL: feedURL, topics: ["politics"], timestamp: Date().addingTimeInterval(-Double(i) * 86400))
        }

        let report = compass.analyzeDrift(feedURL: feedURL)
        XCTAssertNotNil(report)
        XCTAssertFalse(report?.summary.isEmpty ?? true)
        XCTAssertFalse(report?.recommendations.isEmpty ?? true)
    }

    func testReportIncludesFeedName() {
        let feedURL = "https://named.com/feed"
        for i in 0..<10 {
            compass.ingestArticle(feedURL: feedURL, feedName: "My Named Feed", topics: ["tech"], timestamp: Date().addingTimeInterval(-Double(i) * 86400))
        }

        let report = compass.analyzeDrift(feedURL: feedURL)
        XCTAssertEqual(report?.feedName, "My Named Feed")
    }

    // MARK: - Edge Cases

    func testEmptyTopicsUseTitleExtraction() {
        compass.ingestArticle(
            feedURL: "https://edge.com/feed",
            title: "Government Policy Changes Election Results",
            topics: []
        )
        // Should extract "politics" from title keywords
        XCTAssertGreaterThan(compass.totalObservations, 0)
    }

    func testSingleArticleFeedHandled() {
        compass.ingestArticle(feedURL: "https://single.com/feed", topics: ["tech"])
        let report = compass.analyzeDrift(feedURL: "https://single.com/feed")
        XCTAssertNotNil(report)
        XCTAssertEqual(report?.driftType, .insufficient)
    }

    func testDuplicateTopicsInSingleArticle() {
        compass.ingestArticle(feedURL: "https://dup.com/feed", topics: ["tech", "tech", "tech"])
        XCTAssertEqual(compass.totalObservations, 3)
    }

    // MARK: - Days Until Identity Loss

    func testDaysUntilIdentityLossNilForStable() {
        let feedURL = "https://stable2.com/feed"
        let baseDate = Date().addingTimeInterval(-90 * 86400)

        for i in 0..<20 {
            compass.ingestArticle(feedURL: feedURL, topics: ["technology"], timestamp: baseDate.addingTimeInterval(Double(i) * 4 * 86400))
        }

        let report = compass.analyzeDrift(feedURL: feedURL)
        XCTAssertNil(report?.daysUntilIdentityLoss)
    }

    // MARK: - Drift Type Enum

    func testDriftTypeDescriptions() {
        for driftType in EditorialDriftType.allCases {
            XCTAssertFalse(driftType.description.isEmpty)
            XCTAssertFalse(driftType.emoji.isEmpty)
        }
    }

    func testDriftSeverityComparable() {
        XCTAssertLessThan(DriftSeverity.none, DriftSeverity.mild)
        XCTAssertLessThan(DriftSeverity.mild, DriftSeverity.moderate)
        XCTAssertLessThan(DriftSeverity.moderate, DriftSeverity.significant)
        XCTAssertLessThan(DriftSeverity.significant, DriftSeverity.extreme)
    }

    // MARK: - Subscription Health Score

    func testSubscriptionHealthScoreBounded() {
        let fleet = compass.analyzeFleet()
        XCTAssertGreaterThanOrEqual(fleet.subscriptionHealthScore, 0)
        XCTAssertLessThanOrEqual(fleet.subscriptionHealthScore, 100)
    }

    func testEmptyFleetReturnsFullHealth() {
        let fleet = compass.analyzeFleet()
        XCTAssertEqual(fleet.subscriptionHealthScore, 100)
        XCTAssertEqual(fleet.driftingFeedCount, 0)
    }

    // MARK: - Configuration

    func testCustomConfigurationAffectsResults() {
        compass.minimumIdentityArticles = 3

        let feedURL = "https://config.com/feed"
        for i in 0..<4 {
            compass.ingestArticle(feedURL: feedURL, topics: ["tech"], timestamp: Date().addingTimeInterval(-Double(i) * 86400))
        }

        let report = compass.analyzeDrift(feedURL: feedURL)
        // With threshold 3, 4 articles should be sufficient (not .insufficient)
        XCTAssertNotEqual(report?.driftType, .insufficient)
    }

    // MARK: - Concurrency Safety

    func testConcurrentIngestAndAnalyze() {
        let expectation = XCTestExpectation(description: "concurrent access")
        expectation.expectedFulfillmentCount = 20

        let feedURL = "https://concurrent.com/feed"
        let queue = DispatchQueue(label: "test.concurrent", attributes: .concurrent)

        for i in 0..<10 {
            queue.async {
                self.compass.ingestArticle(feedURL: feedURL, topics: ["topic_\(i)"], timestamp: Date())
                expectation.fulfill()
            }
            queue.async {
                _ = self.compass.analyzeDrift(feedURL: feedURL)
                expectation.fulfill()
            }
        }

        wait(for: [expectation], timeout: 5.0)
        XCTAssertGreaterThan(compass.totalObservations, 0)
    }
}
