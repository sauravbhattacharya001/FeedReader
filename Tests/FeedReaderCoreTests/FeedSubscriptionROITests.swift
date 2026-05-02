//
//  FeedSubscriptionROITests.swift
//  FeedReaderCoreTests
//
//  Tests for the FeedSubscriptionROI engine.
//

import XCTest
@testable import FeedReaderCore

final class FeedSubscriptionROITests: XCTestCase {

    private var sut: FeedSubscriptionROI!

    override func setUp() {
        super.setUp()
        sut = FeedSubscriptionROI()
        sut.minimumArticles = 3
    }

    override func tearDown() {
        sut = nil
        super.tearDown()
    }

    // MARK: - ROI Tier

    func testROITierFromScore() {
        XCTAssertEqual(ROITier.from(score: 95), .platinum)
        XCTAssertEqual(ROITier.from(score: 85), .platinum)
        XCTAssertEqual(ROITier.from(score: 75), .gold)
        XCTAssertEqual(ROITier.from(score: 55), .silver)
        XCTAssertEqual(ROITier.from(score: 35), .bronze)
        XCTAssertEqual(ROITier.from(score: 10), .deficit)
        XCTAssertEqual(ROITier.from(score: 0), .deficit)
    }

    func testROITierComparable() {
        XCTAssertTrue(ROITier.deficit < ROITier.bronze)
        XCTAssertTrue(ROITier.bronze < ROITier.silver)
        XCTAssertTrue(ROITier.silver < ROITier.gold)
        XCTAssertTrue(ROITier.gold < ROITier.platinum)
    }

    func testROITierEmoji() {
        XCTAssertFalse(ROITier.platinum.emoji.isEmpty)
        XCTAssertFalse(ROITier.deficit.emoji.isEmpty)
    }

    // MARK: - Anti-Pattern Enum

    func testAntiPatternProperties() {
        for pattern in SubscriptionAntiPattern.allCases {
            XCTAssertFalse(pattern.emoji.isEmpty, "\(pattern) should have emoji")
            XCTAssertFalse(pattern.description.isEmpty, "\(pattern) should have description")
        }
    }

    // MARK: - ROI Action Enum

    func testROIActionEmoji() {
        for action in ROIAction.allCases {
            XCTAssertFalse(action.emoji.isEmpty, "\(action) should have emoji")
        }
    }

    // MARK: - Article Engagement

    func testArticleEngagementInit() {
        let e = ArticleEngagement(
            feedURL: "https://example.com/feed",
            feedName: "Example",
            wasRead: true,
            dwellSeconds: 120,
            wasSaved: true
        )
        XCTAssertEqual(e.feedURL, "https://example.com/feed")
        XCTAssertTrue(e.wasRead)
        XCTAssertEqual(e.dwellSeconds, 120)
        XCTAssertTrue(e.wasSaved)
    }

    func testNegativeDwellClampedToZero() {
        let e = ArticleEngagement(feedURL: "f", feedName: "F", wasRead: true, dwellSeconds: -50)
        XCTAssertEqual(e.dwellSeconds, 0)
    }

    // MARK: - Single Feed Analysis

    func testAnalyzeFeedReturnsNilForUnknown() {
        XCTAssertNil(sut.analyzeFeed(feedURL: "https://nonexistent.com/feed"))
    }

    func testAnalyzeFeedWithHighEngagement() {
        for i in 0..<10 {
            sut.recordArticle(feedURL: "https://good.com/feed", feedName: "Good Blog",
                              articleId: "a\(i)", wasRead: true, dwellSeconds: 200,
                              wasSaved: i % 3 == 0, wasShared: i % 5 == 0,
                              topics: ["tech"])
        }

        let report = sut.analyzeFeed(feedURL: "https://good.com/feed")
        XCTAssertNotNil(report)
        XCTAssertEqual(report!.totalArticles, 10)
        XCTAssertEqual(report!.articlesRead, 10)
        XCTAssertEqual(report!.readRate, 1.0)
        XCTAssertTrue(report!.roiScore >= 70, "High engagement should yield high ROI, got \(report!.roiScore)")
        XCTAssertTrue(report!.tier >= .gold)
    }

    func testAnalyzeFeedWithLowEngagement() {
        for i in 0..<20 {
            sut.recordArticle(feedURL: "https://bad.com/feed", feedName: "Bad Blog",
                              articleId: "b\(i)", wasRead: i == 0,
                              dwellSeconds: i == 0 ? 5 : 0)
        }

        let report = sut.analyzeFeed(feedURL: "https://bad.com/feed")
        XCTAssertNotNil(report)
        XCTAssertTrue(report!.roiScore < 30, "Low engagement should yield low ROI, got \(report!.roiScore)")
        XCTAssertEqual(report!.tier, .deficit)
    }

    // MARK: - Anti-Pattern Detection

    func testZombieFeedDetection() {
        for i in 0..<10 {
            sut.recordArticle(feedURL: "https://zombie.com/feed", feedName: "Zombie",
                              articleId: "z\(i)", wasRead: false)
        }

        let report = sut.analyzeFeed(feedURL: "https://zombie.com/feed")!
        XCTAssertTrue(report.antiPatterns.contains(.zombieFeed))
    }

    func testFirehoseDetection() {
        let now = Date()
        // 50 articles in one week
        for i in 0..<50 {
            let ts = now.addingTimeInterval(Double(i) * 3600)  // hourly
            sut.recordArticle(feedURL: "https://firehose.com/feed", feedName: "Firehose",
                              articleId: "fh\(i)", timestamp: ts, wasRead: i % 2 == 0,
                              dwellSeconds: 30)
        }

        let report = sut.analyzeFeed(feedURL: "https://firehose.com/feed")!
        XCTAssertTrue(report.antiPatterns.contains(.firehose))
    }

    func testGuiltSubscriptionDetection() {
        for i in 0..<10 {
            sut.recordArticle(feedURL: "https://guilt.com/feed", feedName: "Guilt Feed",
                              articleId: "g\(i)", wasRead: true, dwellSeconds: 5)
        }

        let report = sut.analyzeFeed(feedURL: "https://guilt.com/feed")!
        XCTAssertTrue(report.antiPatterns.contains(.guiltSub))
    }

    func testDormantFeedDetection() {
        let oldDate = Date().addingTimeInterval(-60 * 86400)  // 60 days ago
        for i in 0..<5 {
            sut.recordArticle(feedURL: "https://dormant.com/feed", feedName: "Dormant",
                              articleId: "d\(i)", timestamp: oldDate, wasRead: true,
                              dwellSeconds: 100)
        }

        let report = sut.analyzeFeed(feedURL: "https://dormant.com/feed")!
        XCTAssertTrue(report.antiPatterns.contains(.dormantFeed))
    }

    // MARK: - Portfolio Analysis

    func testPortfolioAnalysis() {
        // Feed A: high engagement
        for i in 0..<10 {
            sut.recordArticle(feedURL: "https://a.com/feed", feedName: "Feed A",
                              articleId: "a\(i)", wasRead: true, dwellSeconds: 180,
                              wasSaved: true, topics: ["tech"])
        }
        // Feed B: low engagement
        for i in 0..<10 {
            sut.recordArticle(feedURL: "https://b.com/feed", feedName: "Feed B",
                              articleId: "b\(i)", wasRead: false, topics: ["news"])
        }

        let report = sut.analyzePortfolio()
        XCTAssertEqual(report.totalFeeds, 2)
        XCTAssertEqual(report.feedReports.count, 2)
        XCTAssertTrue(report.feedReports[0].roiScore > report.feedReports[1].roiScore)
        XCTAssertTrue(report.overallReadRate > 0)
        XCTAssertTrue(report.overallReadRate < 1)
    }

    func testPortfolioHealthScore() {
        for i in 0..<10 {
            sut.recordArticle(feedURL: "https://good.com/feed", feedName: "Good",
                              articleId: "g\(i)", wasRead: true, dwellSeconds: 150,
                              topics: ["tech"])
        }

        let report = sut.analyzePortfolio()
        XCTAssertTrue(report.portfolioHealth > 0)
        XCTAssertTrue(report.portfolioHealth <= 100)
    }

    func testPortfolioTierDistribution() {
        for i in 0..<5 {
            sut.recordArticle(feedURL: "https://plat.com/feed", feedName: "Platinum",
                              articleId: "p\(i)", wasRead: true, dwellSeconds: 300,
                              wasSaved: true, wasShared: true, topics: ["ai"])
        }
        for i in 0..<5 {
            sut.recordArticle(feedURL: "https://def.com/feed", feedName: "Deficit",
                              articleId: "d\(i)", wasRead: false, topics: ["spam"])
        }

        let report = sut.analyzePortfolio()
        let totalFromDist = report.tierDistribution.values.reduce(0, +)
        XCTAssertEqual(totalFromDist, report.totalFeeds)
    }

    func testPortfolioInsightsGenerated() {
        for i in 0..<10 {
            sut.recordArticle(feedURL: "https://a.com", feedName: "A", articleId: "a\(i)",
                              wasRead: true, dwellSeconds: 120, topics: ["tech"])
        }
        for i in 0..<10 {
            sut.recordArticle(feedURL: "https://b.com", feedName: "B", articleId: "b\(i)",
                              wasRead: false, topics: ["news"])
        }

        let report = sut.analyzePortfolio()
        XCTAssertFalse(report.insights.isEmpty)
    }

    func testPortfolioRecommendationsGenerated() {
        for i in 0..<10 {
            sut.recordArticle(feedURL: "https://z.com", feedName: "Zombie", articleId: "z\(i)",
                              wasRead: false, topics: ["junk"])
        }

        let report = sut.analyzePortfolio()
        XCTAssertFalse(report.recommendations.isEmpty)
    }

    // MARK: - Redundant Coverage Detection

    func testRedundantCoverageDetected() {
        for i in 0..<5 {
            sut.recordArticle(feedURL: "https://tech1.com/feed", feedName: "Tech Blog 1",
                              articleId: "t1_\(i)", wasRead: true, dwellSeconds: 60,
                              topics: ["swift", "ios", "apple"])
        }
        for i in 0..<5 {
            sut.recordArticle(feedURL: "https://tech2.com/feed", feedName: "Tech Blog 2",
                              articleId: "t2_\(i)", wasRead: true, dwellSeconds: 60,
                              topics: ["swift", "ios", "apple"])
        }

        let report = sut.analyzePortfolio()
        let redundantPatterns = report.antiPatterns.filter { $0.pattern == .redundantCoverage }
        XCTAssertTrue(redundantPatterns.count >= 2, "Should detect redundant coverage")
    }

    func testNoRedundancyForDifferentTopics() {
        for i in 0..<5 {
            sut.recordArticle(feedURL: "https://tech.com/feed", feedName: "Tech",
                              articleId: "t\(i)", wasRead: true, dwellSeconds: 60,
                              topics: ["swift", "ios"])
        }
        for i in 0..<5 {
            sut.recordArticle(feedURL: "https://cook.com/feed", feedName: "Cooking",
                              articleId: "c\(i)", wasRead: true, dwellSeconds: 60,
                              topics: ["recipes", "food"])
        }

        let report = sut.analyzePortfolio()
        let redundant = report.antiPatterns.filter { $0.pattern == .redundantCoverage }
        XCTAssertEqual(redundant.count, 0)
    }

    // MARK: - Topic Breakdown

    func testTopicBreakdownComputed() {
        sut.recordArticle(feedURL: "https://f.com", feedName: "F", articleId: "1",
                          wasRead: true, dwellSeconds: 60, topics: ["swift", "ios"])
        sut.recordArticle(feedURL: "https://f.com", feedName: "F", articleId: "2",
                          wasRead: false, topics: ["swift", "android"])

        let report = sut.analyzeFeed(feedURL: "https://f.com")!
        XCTAssertNotNil(report.topicBreakdown["swift"])
        XCTAssertEqual(report.topicBreakdown["swift"]!, 0.5, accuracy: 0.01)
    }

    // MARK: - Recommendation Logic

    func testPruneRecommendation() {
        for i in 0..<10 {
            sut.recordArticle(feedURL: "https://prune.com/feed", feedName: "Prune Me",
                              articleId: "p\(i)", wasRead: false)
        }

        let report = sut.analyzeFeed(feedURL: "https://prune.com/feed")!
        XCTAssertEqual(report.recommendation, .prune)
    }

    func testPromoteRecommendation() {
        for i in 0..<10 {
            sut.recordArticle(feedURL: "https://star.com/feed", feedName: "Star Feed",
                              articleId: "s\(i)", wasRead: true, dwellSeconds: 250,
                              wasSaved: true, wasShared: i % 2 == 0, topics: ["ai"])
        }

        let report = sut.analyzeFeed(feedURL: "https://star.com/feed")!
        // High ROI should get promote or maintain
        XCTAssertTrue(report.recommendation == .promote || report.recommendation == .maintain)
    }

    // MARK: - Reset

    func testReset() {
        sut.recordArticle(feedURL: "https://x.com", feedName: "X", wasRead: true)
        sut.reset()
        XCTAssertNil(sut.analyzeFeed(feedURL: "https://x.com"))
    }

    // MARK: - Bulk Import

    func testBulkImport() {
        let records = (0..<5).map { i in
            ArticleEngagement(feedURL: "https://bulk.com", feedName: "Bulk",
                              articleId: "b\(i)", wasRead: true, dwellSeconds: 100)
        }
        sut.importEngagements(records)
        let report = sut.analyzeFeed(feedURL: "https://bulk.com")
        XCTAssertNotNil(report)
        XCTAssertEqual(report!.totalArticles, 5)
    }

    // MARK: - Edge Cases

    func testEmptyPortfolio() {
        let report = sut.analyzePortfolio()
        XCTAssertEqual(report.totalFeeds, 0)
        XCTAssertEqual(report.feedReports.count, 0)
    }

    func testSingleArticleFeed() {
        sut.recordArticle(feedURL: "https://single.com", feedName: "Single",
                          wasRead: true, dwellSeconds: 300)
        let report = sut.analyzeFeed(feedURL: "https://single.com")
        XCTAssertNotNil(report)
        XCTAssertEqual(report!.totalArticles, 1)
    }

    func testAllUnreadPortfolio() {
        for i in 0..<20 {
            sut.recordArticle(feedURL: "https://unread\(i % 4).com", feedName: "Feed \(i % 4)",
                              articleId: "u\(i)", wasRead: false)
        }
        let report = sut.analyzePortfolio()
        XCTAssertEqual(report.overallReadRate, 0)
        XCTAssertTrue(report.portfolioHealth < 30)
    }

    func testROIScoreBounds() {
        // Extreme high engagement
        for i in 0..<10 {
            sut.recordArticle(feedURL: "https://max.com", feedName: "Max", articleId: "m\(i)",
                              wasRead: true, dwellSeconds: 500, wasSaved: true, wasShared: true)
        }
        let report = sut.analyzeFeed(feedURL: "https://max.com")!
        XCTAssertTrue(report.roiScore >= 0)
        XCTAssertTrue(report.roiScore <= 100)
    }

    // MARK: - Configuration

    func testCustomThresholds() {
        sut.zombieReadRate = 0.5  // stricter zombie detection
        for i in 0..<10 {
            sut.recordArticle(feedURL: "https://half.com", feedName: "Half Read",
                              articleId: "h\(i)", wasRead: i < 3, dwellSeconds: 60)
        }
        let report = sut.analyzeFeed(feedURL: "https://half.com")!
        XCTAssertTrue(report.antiPatterns.contains(.zombieFeed))
    }

    // MARK: - Optimal Feed Count

    func testOptimalFeedCount() {
        // 3 good feeds, 5 bad feeds
        for f in 0..<3 {
            for i in 0..<10 {
                sut.recordArticle(feedURL: "https://good\(f).com", feedName: "Good \(f)",
                                  articleId: "g\(f)_\(i)", wasRead: true, dwellSeconds: 120)
            }
        }
        for f in 0..<5 {
            for i in 0..<10 {
                sut.recordArticle(feedURL: "https://bad\(f).com", feedName: "Bad \(f)",
                                  articleId: "b\(f)_\(i)", wasRead: false)
            }
        }

        let report = sut.analyzePortfolio()
        XCTAssertTrue(report.optimalFeedCount <= report.totalFeeds)
        XCTAssertTrue(report.optimalFeedCount >= 3, "Should include at least the 3 engaged feeds")
    }

    // MARK: - Save/Share Rate

    func testSaveShareRateComputation() {
        for i in 0..<10 {
            sut.recordArticle(feedURL: "https://active.com", feedName: "Active",
                              articleId: "a\(i)", wasRead: true, dwellSeconds: 100,
                              wasSaved: i < 4, wasShared: i < 2)
        }
        let report = sut.analyzeFeed(feedURL: "https://active.com")!
        XCTAssertEqual(report.saveRate, 0.4, accuracy: 0.01)
        XCTAssertEqual(report.shareRate, 0.2, accuracy: 0.01)
    }

    // MARK: - Feed Name Preservation

    func testFeedNameFromLastRecord() {
        sut.recordArticle(feedURL: "https://x.com", feedName: "Old Name", wasRead: true)
        sut.recordArticle(feedURL: "https://x.com", feedName: "New Name", wasRead: true)
        let report = sut.analyzeFeed(feedURL: "https://x.com")!
        XCTAssertEqual(report.feedName, "New Name")
    }

    // MARK: - Portfolio Sorting

    func testFeedReportsSortedByROI() {
        for i in 0..<5 {
            sut.recordArticle(feedURL: "https://low.com", feedName: "Low", articleId: "l\(i)",
                              wasRead: false)
        }
        for i in 0..<5 {
            sut.recordArticle(feedURL: "https://high.com", feedName: "High", articleId: "h\(i)",
                              wasRead: true, dwellSeconds: 200, wasSaved: true)
        }

        let report = sut.analyzePortfolio()
        XCTAssertEqual(report.feedReports.first?.feedName, "High")
        XCTAssertEqual(report.feedReports.last?.feedName, "Low")
    }
}
