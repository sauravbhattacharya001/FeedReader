//
//  FeedSourceDiversityAuditorTests.swift
//  FeedReaderTests
//
//  Unit tests for echo chamber detection and source diversity analysis.
//

import XCTest
@testable import FeedReader

final class FeedSourceDiversityAuditorTests: XCTestCase {

    private var auditor: FeedSourceDiversityAuditor!

    override func setUp() {
        super.setUp()
        auditor = FeedSourceDiversityAuditor()
    }

    // MARK: - Helpers

    private func makeFeed(name: String, enabled: Bool = true) -> Feed {
        return Feed(name: name, url: "https://example.com/\(name)", isEnabled: enabled)
    }

    private func makeStory(title: String, body: String, link: String, source: String) -> Story {
        let story = Story(title: title, body: body, link: link)
        story.sourceFeedName = source
        return story
    }

    // MARK: - Basic Report Generation

    func testEmptyInputProducesReport() {
        let report = auditor.runAudit(feeds: [], stories: [], readStoryLinks: [])
        XCTAssertEqual(report.totalFeedsAnalyzed, 0)
        XCTAssertEqual(report.totalArticlesAnalyzed, 0)
        XCTAssertNotNil(report.echoChamberRisk)
        XCTAssertEqual(report.dimensionScores.count, 6)
    }

    func testSingleFeedReport() {
        let feed = makeFeed(name: "TechNews")
        let stories = (0..<10).map { i in
            makeStory(title: "Tech article \(i)", body: "Technology software programming development",
                      link: "https://example.com/\(i)", source: "TechNews")
        }
        let readLinks = Set(stories.prefix(5).map { $0.link })

        let report = auditor.runAudit(feeds: [feed], stories: stories, readStoryLinks: readLinks)
        XCTAssertEqual(report.totalFeedsAnalyzed, 1)
        XCTAssertEqual(report.totalArticlesAnalyzed, 10)
    }

    func testDiverseFeedsScoreHigher() {
        let feeds = ["Tech", "Sports", "Science", "Culture", "Business"].map { makeFeed(name: $0) }
        var stories: [Story] = []
        let topicWords = [
            "Tech": "software programming algorithms computers engineering",
            "Sports": "football basketball soccer tennis athletes",
            "Science": "physics biology chemistry research experiments",
            "Culture": "music painting theater literature poetry",
            "Business": "finance markets investing economy startups"
        ]
        var readLinks = Set<String>()
        for feed in feeds {
            for i in 0..<10 {
                let link = "https://\(feed.name)/\(i)"
                let story = makeStory(title: "\(feed.name) article \(i)",
                                      body: topicWords[feed.name] ?? "",
                                      link: link, source: feed.name)
                stories.append(story)
                readLinks.insert(link) // Read everything evenly
            }
        }

        let report = auditor.runAudit(feeds: feeds, stories: stories, readStoryLinks: readLinks)
        // Diverse feeds + even reading should score well
        XCTAssertGreaterThan(report.overallDiversityIndex, 50)
    }

    func testConcentratedFeedsScoreLower() {
        let feeds = ["Dominant", "Tiny"].map { makeFeed(name: $0) }
        var stories: [Story] = []
        // 95 articles from Dominant, 5 from Tiny
        for i in 0..<95 {
            stories.append(makeStory(title: "Dominant \(i)", body: "same topic words repeated",
                                     link: "https://dom/\(i)", source: "Dominant"))
        }
        for i in 0..<5 {
            stories.append(makeStory(title: "Tiny \(i)", body: "same topic words repeated",
                                     link: "https://tiny/\(i)", source: "Tiny"))
        }

        let report = auditor.runAudit(feeds: feeds, stories: stories, readStoryLinks: [])
        // Source concentration should be flagged
        let srcScore = report.dimensionScores.first { $0.dimension == .sourceConcentration }
        XCTAssertNotNil(srcScore)
        XCTAssertLessThan(srcScore!.score, 50)
    }

    // MARK: - Viewpoint Clustering

    func testOverlappingFeedsDetected() {
        let config = DiversityAuditConfig(viewpointClusterThreshold: 0.3)
        let auditor = FeedSourceDiversityAuditor(config: config)
        let feeds = ["NewsA", "NewsB"].map { makeFeed(name: $0) }
        let sharedBody = "politics government election voting democracy policy legislation congress"
        let stories = feeds.flatMap { feed in
            (0..<10).map { i in
                makeStory(title: "\(feed.name) politics \(i)", body: sharedBody,
                          link: "https://\(feed.name)/\(i)", source: feed.name)
            }
        }

        let report = auditor.runAudit(feeds: feeds, stories: stories, readStoryLinks: [])
        // Should detect the cluster
        XCTAssertFalse(report.viewpointClusters.isEmpty, "Should detect overlapping feeds")
    }

    // MARK: - Recommendations

    func testRecommendationsGeneratedForLowScores() {
        let feed = makeFeed(name: "OnlyFeed")
        let stories = (0..<20).map { i in
            makeStory(title: "Same topic \(i)", body: "identical words repeated here",
                      link: "https://only/\(i)", source: "OnlyFeed")
        }

        let report = auditor.runAudit(feeds: [feed], stories: stories, readStoryLinks: [])
        XCTAssertFalse(report.recommendations.isEmpty, "Should produce recommendations for single-source setup")
    }

    // MARK: - History & Trends

    func testHistoryTracking() {
        let feed = makeFeed(name: "Test")
        let stories = [makeStory(title: "A", body: "words", link: "l1", source: "Test")]

        _ = auditor.runAudit(feeds: [feed], stories: stories, readStoryLinks: [])
        _ = auditor.runAudit(feeds: [feed], stories: stories, readStoryLinks: [])

        XCTAssertEqual(auditor.history.count, 2)
        let trend = auditor.getTrend()
        XCTAssertEqual(trend.count, 2)
    }

    // MARK: - Report Formatting

    func testFormatReportProducesText() {
        let feed = makeFeed(name: "Test")
        let stories = [makeStory(title: "A", body: "some content here today", link: "l1", source: "Test")]
        let report = auditor.runAudit(feeds: [feed], stories: stories, readStoryLinks: ["l1"])

        let text = auditor.formatReport(report)
        XCTAssertTrue(text.contains("Diversity Audit Report"))
        XCTAssertTrue(text.contains("Echo Chamber Risk"))
    }

    // MARK: - Config

    func testConfigUpdate() {
        var newConfig = DiversityAuditConfig()
        newConfig.evaluationWindowDays = 60
        auditor.updateConfig(newConfig)
        XCTAssertEqual(auditor.config.evaluationWindowDays, 60)
    }

    // MARK: - Echo Chamber Risk Levels

    func testEchoChamberRiskEmoji() {
        XCTAssertEqual(EchoChamberRisk.minimal.emoji, "🟢")
        XCTAssertEqual(EchoChamberRisk.critical.emoji, "🚨")
    }

    func testDiversityDimensionCoverage() {
        XCTAssertEqual(DiversityDimension.allCases.count, 6)
    }

    // MARK: - Disabled Feeds Excluded

    func testDisabledFeedsExcluded() {
        let feeds = [makeFeed(name: "Active"), makeFeed(name: "Disabled", enabled: false)]
        let stories = [
            makeStory(title: "A", body: "words", link: "l1", source: "Active"),
            makeStory(title: "B", body: "words", link: "l2", source: "Disabled")
        ]

        let report = auditor.runAudit(feeds: feeds, stories: stories, readStoryLinks: [])
        XCTAssertEqual(report.totalFeedsAnalyzed, 1)
    }
}
