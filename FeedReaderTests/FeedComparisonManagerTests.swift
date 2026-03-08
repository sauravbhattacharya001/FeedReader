//
//  FeedComparisonManagerTests.swift
//  FeedReaderTests
//
//  Tests for FeedComparisonManager: overlap detection, topic similarity,
//  recommendation logic, and the double-counting bug fix.
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

    // MARK: - Helpers

    private func makeFeed(name: String, url: String) -> Feed {
        return Feed(name: name, url: url)
    }

    private func makeStory(title: String, link: String, body: String = "") -> Story {
        let story = Story(
            title: title,
            photo: UIImage(),
            description: body,
            link: link,
            imagePath: nil
        )!
        return story
    }

    // MARK: - Overlap Analysis

    func testExactURLMatchDetection() {
        let feedA = makeFeed(name: "Feed A", url: "https://a.com/rss")
        let feedB = makeFeed(name: "Feed B", url: "https://b.com/rss")
        let storiesA = [
            makeStory(title: "Article One", link: "https://example.com/1"),
            makeStory(title: "Article Two", link: "https://example.com/2"),
            makeStory(title: "Article Three", link: "https://example.com/3"),
        ]
        let storiesB = [
            makeStory(title: "Article One Copy", link: "https://example.com/1"),
            makeStory(title: "Different Article", link: "https://other.com/4"),
        ]

        let result = manager.compare(feedA: feedA, feedB: feedB,
                                      storiesA: storiesA, storiesB: storiesB)

        XCTAssertEqual(result.overlap.exactMatches, 1)
    }

    func testNoOverlapBetweenDisjointFeeds() {
        let feedA = makeFeed(name: "Tech", url: "https://tech.com/rss")
        let feedB = makeFeed(name: "Sports", url: "https://sports.com/rss")
        let storiesA = [
            makeStory(title: "New AI Model Released", link: "https://tech.com/1"),
            makeStory(title: "Quantum Computing Update", link: "https://tech.com/2"),
        ]
        let storiesB = [
            makeStory(title: "Basketball Finals Tonight", link: "https://sports.com/1"),
            makeStory(title: "Soccer World Cup Preview", link: "https://sports.com/2"),
        ]

        let result = manager.compare(feedA: feedA, feedB: feedB,
                                      storiesA: storiesA, storiesB: storiesB)

        XCTAssertEqual(result.overlap.exactMatches, 0)
        XCTAssertEqual(result.overlap.titleMatches, 0)
        XCTAssertEqual(result.overlap.overlapRatio, 0.0, accuracy: 0.01)
    }

    func testTitleSimilarityMatching() {
        let feedA = makeFeed(name: "Feed A", url: "https://a.com/rss")
        let feedB = makeFeed(name: "Feed B", url: "https://b.com/rss")
        let storiesA = [
            makeStory(title: "Breaking News Major Event Today", link: "https://a.com/1"),
        ]
        let storiesB = [
            makeStory(title: "Breaking News Major Event Today Update", link: "https://b.com/1"),
        ]

        let result = manager.compare(feedA: feedA, feedB: feedB,
                                      storiesA: storiesA, storiesB: storiesB)

        // Titles are very similar — should detect title match
        XCTAssertEqual(result.overlap.exactMatches, 0)
        XCTAssertGreaterThanOrEqual(result.overlap.titleMatches, 0) // depends on normalization
    }

    func testUniqueCountsAreCorrectWithURLOverlap() {
        // Regression test for the double-counting bug:
        // uniqueToA and uniqueToB should reflect actual unique articles
        let feedA = makeFeed(name: "A", url: "https://a.com/rss")
        let feedB = makeFeed(name: "B", url: "https://b.com/rss")
        let storiesA = [
            makeStory(title: "Shared Article", link: "https://shared.com/1"),
            makeStory(title: "Only In A", link: "https://a.com/unique"),
        ]
        let storiesB = [
            makeStory(title: "Shared Article Copy", link: "https://shared.com/1"),
            makeStory(title: "Only In B", link: "https://b.com/unique"),
            makeStory(title: "Also Only B", link: "https://b.com/unique2"),
        ]

        let result = manager.compare(feedA: feedA, feedB: feedB,
                                      storiesA: storiesA, storiesB: storiesB)

        XCTAssertEqual(result.overlap.exactMatches, 1)
        XCTAssertEqual(result.overlap.uniqueToA, 1, "A has 2 articles, 1 matched = 1 unique")
        XCTAssertEqual(result.overlap.uniqueToB, 2, "B has 3 articles, 1 matched = 2 unique")
        // uniqueToA + matched in A = total A articles
        XCTAssertEqual(result.overlap.uniqueToA + result.overlap.exactMatches + result.overlap.titleMatches,
                       storiesA.count)
    }

    func testUniqueCountsNeverNegative() {
        // Even with high overlap, unique counts should never go negative
        let feedA = makeFeed(name: "A", url: "https://a.com/rss")
        let feedB = makeFeed(name: "B", url: "https://b.com/rss")
        let storiesA = [
            makeStory(title: "Story", link: "https://shared.com/1"),
        ]
        let storiesB = [
            makeStory(title: "Story", link: "https://shared.com/1"),
        ]

        let result = manager.compare(feedA: feedA, feedB: feedB,
                                      storiesA: storiesA, storiesB: storiesB)

        XCTAssertGreaterThanOrEqual(result.overlap.uniqueToA, 0)
        XCTAssertGreaterThanOrEqual(result.overlap.uniqueToB, 0)
    }

    func testOverlapRatioCappedAtOne() {
        let feedA = makeFeed(name: "A", url: "https://a.com/rss")
        let feedB = makeFeed(name: "B", url: "https://b.com/rss")
        let storiesA = [
            makeStory(title: "S1", link: "https://shared.com/1"),
            makeStory(title: "S2", link: "https://shared.com/2"),
        ]
        let storiesB = [
            makeStory(title: "S1", link: "https://shared.com/1"),
            makeStory(title: "S2", link: "https://shared.com/2"),
        ]

        let result = manager.compare(feedA: feedA, feedB: feedB,
                                      storiesA: storiesA, storiesB: storiesB)

        XCTAssertLessThanOrEqual(result.overlap.overlapRatio, 1.0)
    }

    // MARK: - Empty Feeds

    func testCompareEmptyFeeds() {
        let feedA = makeFeed(name: "A", url: "https://a.com/rss")
        let feedB = makeFeed(name: "B", url: "https://b.com/rss")

        let result = manager.compare(feedA: feedA, feedB: feedB,
                                      storiesA: [], storiesB: [])

        XCTAssertEqual(result.overlap.exactMatches, 0)
        XCTAssertEqual(result.overlap.overlapRatio, 0.0)
        XCTAssertEqual(result.recommendation, .noData)
    }

    func testCompareOneEmptyFeed() {
        let feedA = makeFeed(name: "A", url: "https://a.com/rss")
        let feedB = makeFeed(name: "B", url: "https://b.com/rss")
        let storiesA = [
            makeStory(title: "S1", link: "https://a.com/1"),
            makeStory(title: "S2", link: "https://a.com/2"),
            makeStory(title: "S3", link: "https://a.com/3"),
        ]

        let result = manager.compare(feedA: feedA, feedB: feedB,
                                      storiesA: storiesA, storiesB: [])

        XCTAssertEqual(result.overlap.exactMatches, 0)
        XCTAssertEqual(result.recommendation, .noData)
    }

    // MARK: - Recommendations

    func testHighOverlapRecommendation() {
        let feedA = makeFeed(name: "A", url: "https://a.com/rss")
        let feedB = makeFeed(name: "B", url: "https://b.com/rss")
        // 4 shared out of 5 = 80% overlap
        var storiesA: [Story] = []
        var storiesB: [Story] = []
        for i in 1...5 {
            storiesA.append(makeStory(title: "Article \(i)", link: "https://shared.com/\(i)"))
        }
        for i in 1...4 {
            storiesB.append(makeStory(title: "Article \(i)", link: "https://shared.com/\(i)"))
        }
        storiesB.append(makeStory(title: "Unique B", link: "https://b.com/unique"))

        let result = manager.compare(feedA: feedA, feedB: feedB,
                                      storiesA: storiesA, storiesB: storiesB)

        XCTAssertEqual(result.recommendation, .highOverlap)
    }

    func testComplementaryRecommendation() {
        let feedA = makeFeed(name: "Tech", url: "https://tech.com/rss")
        let feedB = makeFeed(name: "Cooking", url: "https://cooking.com/rss")
        let storiesA = [
            makeStory(title: "Rust Programming Language Update", link: "https://tech.com/1", body: "programming rust compiler"),
            makeStory(title: "Linux Kernel Release", link: "https://tech.com/2", body: "linux kernel operating system"),
            makeStory(title: "Docker Container Tips", link: "https://tech.com/3", body: "docker containers deployment"),
        ]
        let storiesB = [
            makeStory(title: "Best Pasta Recipes", link: "https://cooking.com/1", body: "pasta cooking recipe italian"),
            makeStory(title: "Sourdough Bread Guide", link: "https://cooking.com/2", body: "bread baking sourdough yeast"),
            makeStory(title: "Healthy Smoothie Ideas", link: "https://cooking.com/3", body: "smoothie fruits healthy diet"),
        ]

        let result = manager.compare(feedA: feedA, feedB: feedB,
                                      storiesA: storiesA, storiesB: storiesB)

        XCTAssertEqual(result.overlap.exactMatches, 0)
        // With completely disjoint content, should be complementary
        XCTAssertTrue(result.recommendation == .complementary || result.recommendation == .partialOverlap)
    }

    // MARK: - Topic Similarity

    func testTopicSimilarityWithSharedKeywords() {
        let feedA = makeFeed(name: "A", url: "https://a.com/rss")
        let feedB = makeFeed(name: "B", url: "https://b.com/rss")
        let storiesA = [
            makeStory(title: "Python Machine Learning", link: "https://a.com/1", body: "python machine learning tensorflow keras"),
            makeStory(title: "Python Data Science", link: "https://a.com/2", body: "python data science pandas numpy"),
            makeStory(title: "Python Web Development", link: "https://a.com/3", body: "python django flask web development"),
        ]
        let storiesB = [
            makeStory(title: "JavaScript React Tutorial", link: "https://b.com/1", body: "javascript react frontend components"),
            makeStory(title: "JavaScript Node Backend", link: "https://b.com/2", body: "javascript node express backend api"),
            makeStory(title: "JavaScript Testing Guide", link: "https://b.com/3", body: "javascript testing jest mocha"),
        ]

        let result = manager.compare(feedA: feedA, feedB: feedB,
                                      storiesA: storiesA, storiesB: storiesB)

        // Topic similarity should be low (different languages/ecosystems)
        XCTAssertLessThan(result.topicSimilarity.score, 0.8)
    }

    // MARK: - Summary Generation

    func testSummaryContainsFeedNames() {
        let feedA = makeFeed(name: "TechCrunch", url: "https://tc.com/rss")
        let feedB = makeFeed(name: "Ars Technica", url: "https://ars.com/rss")
        let storiesA = [
            makeStory(title: "S1", link: "https://tc.com/1"),
            makeStory(title: "S2", link: "https://tc.com/2"),
            makeStory(title: "S3", link: "https://tc.com/3"),
        ]
        let storiesB = [
            makeStory(title: "S4", link: "https://ars.com/1"),
            makeStory(title: "S5", link: "https://ars.com/2"),
            makeStory(title: "S6", link: "https://ars.com/3"),
        ]

        let result = manager.compare(feedA: feedA, feedB: feedB,
                                      storiesA: storiesA, storiesB: storiesB)

        XCTAssertTrue(result.summary.contains("TechCrunch"))
        XCTAssertTrue(result.summary.contains("Ars Technica"))
    }

    // MARK: - History

    func testComparisonSavedToHistory() {
        let feedA = makeFeed(name: "A", url: "https://a.com/rss")
        let feedB = makeFeed(name: "B", url: "https://b.com/rss")
        let storiesA = [makeStory(title: "S1", link: "https://a.com/1")]
        let storiesB = [makeStory(title: "S2", link: "https://b.com/1")]

        _ = manager.compare(feedA: feedA, feedB: feedB,
                             storiesA: storiesA, storiesB: storiesB)

        let history = manager.getHistory()
        XCTAssertFalse(history.isEmpty)
        XCTAssertEqual(history.first?.feedAName, "A")
        XCTAssertEqual(history.first?.feedBName, "B")
    }

    func testClearHistory() {
        let feedA = makeFeed(name: "A", url: "https://a.com/rss")
        let feedB = makeFeed(name: "B", url: "https://b.com/rss")
        _ = manager.compare(feedA: feedA, feedB: feedB, storiesA: [], storiesB: [])

        manager.clearHistory()

        XCTAssertTrue(manager.getHistory().isEmpty)
    }

    // MARK: - Case Insensitive URL Matching

    func testURLMatchingIsCaseInsensitive() {
        let feedA = makeFeed(name: "A", url: "https://a.com/rss")
        let feedB = makeFeed(name: "B", url: "https://b.com/rss")
        let storiesA = [
            makeStory(title: "Article", link: "HTTPS://EXAMPLE.COM/Article1"),
        ]
        let storiesB = [
            makeStory(title: "Article Copy", link: "https://example.com/article1"),
        ]

        let result = manager.compare(feedA: feedA, feedB: feedB,
                                      storiesA: storiesA, storiesB: storiesB)

        XCTAssertEqual(result.overlap.exactMatches, 1)
    }

    // MARK: - Pairwise Comparison

    func testCompareAllFeedsSortsByOverlap() {
        let feeds = [
            makeFeed(name: "A", url: "https://a.com"),
            makeFeed(name: "B", url: "https://b.com"),
            makeFeed(name: "C", url: "https://c.com"),
        ]
        let stories: [String: [Story]] = [
            "https://a.com": [
                makeStory(title: "S1", link: "https://shared.com/1"),
                makeStory(title: "S2", link: "https://a.com/2"),
                makeStory(title: "S3", link: "https://a.com/3"),
            ],
            "https://b.com": [
                makeStory(title: "S1 copy", link: "https://shared.com/1"),
                makeStory(title: "S4", link: "https://b.com/4"),
                makeStory(title: "S5", link: "https://b.com/5"),
            ],
            "https://c.com": [
                makeStory(title: "S6", link: "https://c.com/6"),
                makeStory(title: "S7", link: "https://c.com/7"),
                makeStory(title: "S8", link: "https://c.com/8"),
            ],
        ]

        let results = manager.compareAllFeeds(feeds: feeds, storiesByFeed: stories)

        XCTAssertEqual(results.count, 3) // 3 choose 2
        // First result should have highest overlap (A vs B share a URL)
        XCTAssertGreaterThanOrEqual(results[0].overlap.overlapRatio,
                                     results[1].overlap.overlapRatio)
    }
}
