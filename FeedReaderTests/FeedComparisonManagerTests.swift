//
//  FeedComparisonManagerTests.swift
//  FeedReaderTests
//
//  Tests for FeedComparisonManager — feed overlap analysis, topic
//  similarity, recommendation logic, pairwise comparison, redundancy
//  detection, and comparison history.
//

import XCTest
@testable import FeedReader

class FeedComparisonManagerTests: XCTestCase {

    var manager: FeedComparisonManager!

    override func setUp() {
        super.setUp()
        manager = FeedComparisonManager.shared
        manager.clearHistory()
    }

    override func tearDown() {
        manager.clearHistory()
        super.tearDown()
    }

    // MARK: - Test Helpers

    private func makeFeed(name: String, url: String) -> Feed {
        return Feed(name: name, url: url, isEnabled: true)
    }

    private func makeStory(title: String, link: String, body: String = "Some article body text content for testing.") -> Story {
        return Story(title: title, photo: nil, description: body, link: link)!
    }

    private func makeStories(prefix: String, count: Int, linkBase: String = "https://example.com/") -> [Story] {
        return (0..<count).map { i in
            makeStory(
                title: "\(prefix) Article \(i) about topic number \(i)",
                link: "\(linkBase)\(prefix.lowercased())-\(i)",
                body: "Body of \(prefix) article \(i) with some content words."
            )
        }
    }

    // MARK: - Basic Comparison

    func testCompareEmptyFeeds() {
        let feedA = makeFeed(name: "Feed A", url: "https://a.com/rss")
        let feedB = makeFeed(name: "Feed B", url: "https://b.com/rss")

        let result = manager.compare(feedA: feedA, feedB: feedB, storiesA: [], storiesB: [])

        XCTAssertEqual(result.feedA.articleCount, 0)
        XCTAssertEqual(result.feedB.articleCount, 0)
        XCTAssertEqual(result.overlap.exactMatches, 0)
        XCTAssertEqual(result.overlap.overlapRatio, 0.0)
    }

    func testCompareDisjointFeeds() {
        let feedA = makeFeed(name: "Feed A", url: "https://a.com/rss")
        let feedB = makeFeed(name: "Feed B", url: "https://b.com/rss")
        let storiesA = makeStories(prefix: "Alpha", count: 5, linkBase: "https://a.com/")
        let storiesB = makeStories(prefix: "Beta", count: 5, linkBase: "https://b.com/")

        let result = manager.compare(feedA: feedA, feedB: feedB,
                                     storiesA: storiesA, storiesB: storiesB)

        XCTAssertEqual(result.overlap.exactMatches, 0)
        XCTAssertEqual(result.overlap.titleMatches, 0)
        XCTAssertEqual(result.feedA.articleCount, 5)
        XCTAssertEqual(result.feedB.articleCount, 5)
    }

    func testCompareIdenticalURLs() {
        let feedA = makeFeed(name: "Feed A", url: "https://a.com/rss")
        let feedB = makeFeed(name: "Feed B", url: "https://b.com/rss")
        let shared = makeStories(prefix: "Shared", count: 3, linkBase: "https://shared.com/")

        let result = manager.compare(feedA: feedA, feedB: feedB,
                                     storiesA: shared, storiesB: shared)

        XCTAssertEqual(result.overlap.exactMatches, 3)
        XCTAssertEqual(result.overlap.overlapRatio, 1.0)
    }

    func testComparePartialURLOverlap() {
        let feedA = makeFeed(name: "Feed A", url: "https://a.com/rss")
        let feedB = makeFeed(name: "Feed B", url: "https://b.com/rss")
        let shared = makeStories(prefix: "Shared", count: 2, linkBase: "https://shared.com/")
        let uniqueA = makeStories(prefix: "UniqueA", count: 3, linkBase: "https://a.com/")
        let uniqueB = makeStories(prefix: "UniqueB", count: 3, linkBase: "https://b.com/")

        let result = manager.compare(feedA: feedA, feedB: feedB,
                                     storiesA: shared + uniqueA,
                                     storiesB: shared + uniqueB)

        XCTAssertEqual(result.overlap.exactMatches, 2)
        XCTAssertEqual(result.feedA.articleCount, 5)
        XCTAssertEqual(result.feedB.articleCount, 5)
    }

    // MARK: - Title Similarity Matching

    func testTitleSimilarityMatch() {
        let feedA = makeFeed(name: "Feed A", url: "https://a.com/rss")
        let feedB = makeFeed(name: "Feed B", url: "https://b.com/rss")

        // Very similar titles but different URLs
        let storyA = makeStory(title: "Breaking News Technology Update Today",
                               link: "https://a.com/breaking-tech")
        let storyB = makeStory(title: "Breaking News Technology Update Today",
                               link: "https://b.com/breaking-tech-repost")

        let result = manager.compare(feedA: feedA, feedB: feedB,
                                     storiesA: [storyA], storiesB: [storyB])

        // Should detect title similarity even with different URLs
        XCTAssertEqual(result.overlap.exactMatches, 0)
        XCTAssertGreaterThanOrEqual(result.overlap.titleMatches, 1)
    }

    // MARK: - Overlap Ratio

    func testOverlapRatioCappedAtOne() {
        let feedA = makeFeed(name: "Feed A", url: "https://a.com/rss")
        let feedB = makeFeed(name: "Feed B", url: "https://b.com/rss")
        let shared = makeStories(prefix: "Shared", count: 5, linkBase: "https://shared.com/")

        let result = manager.compare(feedA: feedA, feedB: feedB,
                                     storiesA: shared, storiesB: shared)

        XCTAssertLessThanOrEqual(result.overlap.overlapRatio, 1.0)
    }

    // MARK: - Topic Similarity

    func testTopicSimilaritySameContent() {
        let feedA = makeFeed(name: "Feed A", url: "https://a.com/rss")
        let feedB = makeFeed(name: "Feed B", url: "https://b.com/rss")

        // Stories with very similar keywords
        let storiesA = (0..<5).map { i in
            makeStory(title: "Swift programming language update \(i)",
                      link: "https://a.com/\(i)",
                      body: "Swift programming Apple iOS development Xcode compiler")
        }
        let storiesB = (0..<5).map { i in
            makeStory(title: "Swift coding language release \(i)",
                      link: "https://b.com/\(i)",
                      body: "Swift programming Apple iOS development Xcode compiler")
        }

        let result = manager.compare(feedA: feedA, feedB: feedB,
                                     storiesA: storiesA, storiesB: storiesB)

        XCTAssertGreaterThan(result.topicSimilarity.score, 0.5,
                             "Feeds with similar content should have high topic similarity")
        XCTAssertFalse(result.topicSimilarity.sharedKeywords.isEmpty)
    }

    func testTopicSimilarityDifferentContent() {
        let feedA = makeFeed(name: "Feed A", url: "https://a.com/rss")
        let feedB = makeFeed(name: "Feed B", url: "https://b.com/rss")

        let storiesA = (0..<5).map { i in
            makeStory(title: "Football soccer match results \(i)",
                      link: "https://a.com/\(i)",
                      body: "Football soccer goals stadium league championship")
        }
        let storiesB = (0..<5).map { i in
            makeStory(title: "Quantum physics research paper \(i)",
                      link: "https://b.com/\(i)",
                      body: "Quantum physics particles experiments laboratory electrons")
        }

        let result = manager.compare(feedA: feedA, feedB: feedB,
                                     storiesA: storiesA, storiesB: storiesB)

        XCTAssertLessThan(result.topicSimilarity.score, 0.5,
                          "Feeds with different topics should have low similarity")
    }

    // MARK: - Recommendations

    func testRecommendationNoData() {
        let feedA = makeFeed(name: "Feed A", url: "https://a.com/rss")
        let feedB = makeFeed(name: "Feed B", url: "https://b.com/rss")

        // Less than 3 articles each → noData
        let result = manager.compare(feedA: feedA, feedB: feedB,
                                     storiesA: [makeStory(title: "One", link: "https://a.com/1")],
                                     storiesB: [makeStory(title: "Two", link: "https://b.com/1")])

        XCTAssertEqual(result.recommendation, .noData)
    }

    func testRecommendationComplementary() {
        let feedA = makeFeed(name: "Feed A", url: "https://a.com/rss")
        let feedB = makeFeed(name: "Feed B", url: "https://b.com/rss")

        // Completely different stories → complementary
        let storiesA = (0..<5).map { i in
            makeStory(title: "Cooking recipe dish meal \(i)",
                      link: "https://a.com/cooking-\(i)",
                      body: "Cooking recipe ingredients kitchen chef meal preparation")
        }
        let storiesB = (0..<5).map { i in
            makeStory(title: "Astronomy telescope galaxy space \(i)",
                      link: "https://b.com/space-\(i)",
                      body: "Astronomy telescope galaxy space nebula constellation")
        }

        let result = manager.compare(feedA: feedA, feedB: feedB,
                                     storiesA: storiesA, storiesB: storiesB)

        // With no overlap and different topics, should be complementary
        XCTAssertTrue(result.recommendation == .complementary || result.recommendation == .partialOverlap,
                      "Disjoint feeds should be complementary or partial overlap")
    }

    // MARK: - Summary

    func testSummaryContainsExpectedSections() {
        let feedA = makeFeed(name: "Tech News", url: "https://a.com/rss")
        let feedB = makeFeed(name: "Dev Blog", url: "https://b.com/rss")
        let storiesA = makeStories(prefix: "Tech", count: 4, linkBase: "https://a.com/")
        let storiesB = makeStories(prefix: "Dev", count: 4, linkBase: "https://b.com/")

        let result = manager.compare(feedA: feedA, feedB: feedB,
                                     storiesA: storiesA, storiesB: storiesB)

        let summary = result.summary
        XCTAssertTrue(summary.contains("Feed Comparison"))
        XCTAssertTrue(summary.contains("Tech News"))
        XCTAssertTrue(summary.contains("Dev Blog"))
        XCTAssertTrue(summary.contains("Overlap"))
        XCTAssertTrue(summary.contains("Topic Similarity"))
        XCTAssertTrue(summary.contains("Recommendation"))
    }

    // MARK: - Compare All Feeds

    func testCompareAllFeedsPairwise() {
        let feeds = (0..<3).map { i in makeFeed(name: "Feed \(i)", url: "https://\(i).com/rss") }
        var storiesByFeed: [String: [Story]] = [:]
        for feed in feeds {
            storiesByFeed[feed.url] = makeStories(prefix: "F\(feed.name.last!)", count: 4,
                                                   linkBase: "https://\(feed.name.last!).com/")
        }

        let results = manager.compareAllFeeds(feeds: feeds, storiesByFeed: storiesByFeed)

        // 3 feeds → 3 pairwise comparisons (3 choose 2)
        XCTAssertEqual(results.count, 3)

        // Results should be sorted by overlap ratio (descending)
        for i in 0..<(results.count - 1) {
            XCTAssertGreaterThanOrEqual(results[i].overlap.overlapRatio,
                                        results[i + 1].overlap.overlapRatio)
        }
    }

    // MARK: - Find Redundant Feeds

    func testFindRedundantFeedsAboveThreshold() {
        let feedA = makeFeed(name: "Feed A", url: "https://a.com/rss")
        let feedB = makeFeed(name: "Feed B", url: "https://b.com/rss")
        let shared = makeStories(prefix: "Shared", count: 5, linkBase: "https://shared.com/")

        let redundant = manager.findRedundantFeeds(
            feeds: [feedA, feedB],
            storiesByFeed: [
                feedA.url: shared,
                feedB.url: shared,
            ],
            threshold: 0.5
        )

        XCTAssertFalse(redundant.isEmpty, "Identical feeds should be detected as redundant")
        XCTAssertGreaterThanOrEqual(redundant[0].2, 0.5)
    }

    func testFindRedundantFeedsBelowThreshold() {
        let feedA = makeFeed(name: "Feed A", url: "https://a.com/rss")
        let feedB = makeFeed(name: "Feed B", url: "https://b.com/rss")
        let storiesA = makeStories(prefix: "Alpha", count: 5, linkBase: "https://a.com/")
        let storiesB = makeStories(prefix: "Beta", count: 5, linkBase: "https://b.com/")

        let redundant = manager.findRedundantFeeds(
            feeds: [feedA, feedB],
            storiesByFeed: [
                feedA.url: storiesA,
                feedB.url: storiesB,
            ],
            threshold: 0.5
        )

        XCTAssertTrue(redundant.isEmpty, "Disjoint feeds should not be redundant")
    }

    // MARK: - History

    func testComparisonSavesToHistory() {
        let feedA = makeFeed(name: "Feed A", url: "https://a.com/rss")
        let feedB = makeFeed(name: "Feed B", url: "https://b.com/rss")
        let storiesA = makeStories(prefix: "Alpha", count: 4, linkBase: "https://a.com/")
        let storiesB = makeStories(prefix: "Beta", count: 4, linkBase: "https://b.com/")

        _ = manager.compare(feedA: feedA, feedB: feedB,
                            storiesA: storiesA, storiesB: storiesB)

        let history = manager.getHistory()
        XCTAssertFalse(history.isEmpty)
        XCTAssertEqual(history[0].feedAName, "Feed A")
        XCTAssertEqual(history[0].feedBName, "Feed B")
    }

    func testClearHistory() {
        let feedA = makeFeed(name: "Feed A", url: "https://a.com/rss")
        let feedB = makeFeed(name: "Feed B", url: "https://b.com/rss")
        _ = manager.compare(feedA: feedA, feedB: feedB,
                            storiesA: makeStories(prefix: "A", count: 4),
                            storiesB: makeStories(prefix: "B", count: 4))

        manager.clearHistory()
        XCTAssertTrue(manager.getHistory().isEmpty)
    }

    // MARK: - Notification

    func testComparisonPostsNotification() {
        let feedA = makeFeed(name: "Feed A", url: "https://a.com/rss")
        let feedB = makeFeed(name: "Feed B", url: "https://b.com/rss")

        let expectation = self.expectation(forNotification: .feedComparisonDidComplete,
                                            object: nil, handler: nil)

        _ = manager.compare(feedA: feedA, feedB: feedB,
                            storiesA: makeStories(prefix: "A", count: 4),
                            storiesB: makeStories(prefix: "B", count: 4))

        wait(for: [expectation], timeout: 1.0)
    }

    // MARK: - Edge Cases

    func testCompareOneFeedEmpty() {
        let feedA = makeFeed(name: "Feed A", url: "https://a.com/rss")
        let feedB = makeFeed(name: "Feed B", url: "https://b.com/rss")

        let result = manager.compare(feedA: feedA, feedB: feedB,
                                     storiesA: makeStories(prefix: "A", count: 5),
                                     storiesB: [])

        XCTAssertEqual(result.overlap.exactMatches, 0)
        XCTAssertEqual(result.overlap.overlapRatio, 0.0)
        XCTAssertEqual(result.feedA.articleCount, 5)
        XCTAssertEqual(result.feedB.articleCount, 0)
    }

    func testCaseInsensitiveURLMatching() {
        let feedA = makeFeed(name: "Feed A", url: "https://a.com/rss")
        let feedB = makeFeed(name: "Feed B", url: "https://b.com/rss")
        let storyA = makeStory(title: "Test", link: "https://Example.COM/Article")
        let storyB = makeStory(title: "Test", link: "https://example.com/article")

        let result = manager.compare(feedA: feedA, feedB: feedB,
                                     storiesA: [storyA], storiesB: [storyB])

        XCTAssertEqual(result.overlap.exactMatches, 1,
                       "URL matching should be case-insensitive")
    }
}
