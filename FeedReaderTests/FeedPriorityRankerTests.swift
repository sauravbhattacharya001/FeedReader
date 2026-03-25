//
//  FeedPriorityRankerTests.swift
//  FeedReaderTests
//
//  Tests for FeedPriorityRanker - feed priority assignment and article sorting.
//

import XCTest
@testable import FeedReader

class FeedPriorityRankerTests: XCTestCase {

    var ranker: FeedPriorityRanker!

    override func setUp() {
        super.setUp()
        ranker = FeedPriorityRanker()
        ranker.resetAll()
    }

    override func tearDown() {
        ranker.resetAll()
        ranker = nil
        super.tearDown()
    }

    // MARK: - Helpers

    private func makeStory(title: String, link: String, feedName: String) -> Story {
        let story = Story(title: title, photo: nil, description: "Test body content here.", link: link)!
        story.sourceFeedName = feedName
        return story
    }

    // MARK: - Priority Assignment

    func testSetAndGetPriority() {
        ranker.setPriority(.high, for: "https://example.com/feed")
        XCTAssertEqual(ranker.priority(for: "https://example.com/feed"), .high)
    }

    func testDefaultPriority() {
        XCTAssertEqual(ranker.priority(for: "https://unknown.com/feed"), .medium)
    }

    func testCaseInsensitiveURL() {
        ranker.setPriority(.critical, for: "HTTPS://Example.COM/Feed")
        XCTAssertEqual(ranker.priority(for: "https://example.com/feed"), .critical)
    }

    func testRemovePriority() {
        ranker.setPriority(.high, for: "https://example.com/feed")
        ranker.removePriority(for: "https://example.com/feed")
        XCTAssertEqual(ranker.priority(for: "https://example.com/feed"), .medium)
    }

    func testOverwritePriority() {
        ranker.setPriority(.low, for: "https://example.com/feed")
        ranker.setPriority(.critical, for: "https://example.com/feed")
        XCTAssertEqual(ranker.priority(for: "https://example.com/feed"), .critical)
    }

    // MARK: - Priority Comparison

    func testPriorityOrdering() {
        XCTAssertTrue(FeedPriorityRanker.Priority.critical < .high)
        XCTAssertTrue(FeedPriorityRanker.Priority.high < .medium)
        XCTAssertTrue(FeedPriorityRanker.Priority.medium < .low)
    }

    // MARK: - Article Ranking

    func testRankArticlesByPriority() {
        ranker.setPriority(.low, for: "low-feed")
        ranker.setPriority(.critical, for: "critical-feed")
        ranker.setPriority(.high, for: "high-feed")

        let stories = [
            makeStory(title: "Low", link: "https://example.com/1", feedName: "low-feed"),
            makeStory(title: "Critical", link: "https://example.com/2", feedName: "critical-feed"),
            makeStory(title: "High", link: "https://example.com/3", feedName: "high-feed"),
        ]

        let ranked = ranker.rankArticles(stories) { $0.sourceFeedName }
        XCTAssertEqual(ranked[0].title, "Critical")
        XCTAssertEqual(ranked[1].title, "High")
        XCTAssertEqual(ranked[2].title, "Low")
    }

    func testFilterArticlesByMinPriority() {
        ranker.setPriority(.critical, for: "news")
        ranker.setPriority(.low, for: "memes")

        let stories = [
            makeStory(title: "News", link: "https://example.com/1", feedName: "news"),
            makeStory(title: "Memes", link: "https://example.com/2", feedName: "memes"),
        ]

        let filtered = ranker.filterArticles(stories, minPriority: .high) { $0.sourceFeedName }
        XCTAssertEqual(filtered.count, 1)
        XCTAssertEqual(filtered[0].title, "News")
    }

    // MARK: - Statistics

    func testPriorityDistribution() {
        ranker.setPriority(.critical, for: "feed1")
        ranker.setPriority(.critical, for: "feed2")
        ranker.setPriority(.low, for: "feed3")

        let stats = ranker.priorityDistribution(totalFeeds: 5)
        XCTAssertEqual(stats.critical, 2)
        XCTAssertEqual(stats.low, 1)
        XCTAssertEqual(stats.unranked, 2)
    }

    // MARK: - Import/Export

    func testExportImportRoundTrip() {
        ranker.setPriority(.high, for: "https://a.com/feed")
        ranker.setPriority(.low, for: "https://b.com/feed")

        let exported = ranker.exportPriorities()
        ranker.resetAll()
        let imported = ranker.importPriorities(exported)

        XCTAssertEqual(imported, 2)
        XCTAssertEqual(ranker.priority(for: "https://a.com/feed"), .high)
        XCTAssertEqual(ranker.priority(for: "https://b.com/feed"), .low)
    }

    // MARK: - Display

    func testDisplayNames() {
        XCTAssertEqual(FeedPriorityRanker.Priority.critical.displayName, "🔴 Critical")
        XCTAssertEqual(FeedPriorityRanker.Priority.low.displayName, "🟢 Low")
    }

    func testSummaryReport() {
        ranker.setPriority(.critical, for: "feed1")
        let report = ranker.summaryReport(totalFeeds: 3)
        XCTAssertTrue(report.contains("Critical"))
        XCTAssertTrue(report.contains("Unranked"))
    }

    // MARK: - Reset

    func testResetAll() {
        ranker.setPriority(.high, for: "feed1")
        ranker.resetAll()
        XCTAssertEqual(ranker.priority(for: "feed1"), .medium)
        XCTAssertTrue(ranker.allEntries().isEmpty)
    }
}
