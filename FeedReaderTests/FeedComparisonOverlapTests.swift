//
//  FeedComparisonOverlapTests.swift
//  FeedReaderTests
//
//  Tests for FeedComparisonManager overlap analysis edge cases,
//  especially verifying uniqueToA/uniqueToB never go negative
//  when feeds have asymmetric sizes or high overlap.
//

import XCTest
@testable import FeedReader

class FeedComparisonOverlapTests: XCTestCase {

    // MARK: - Helpers

    private func makeStory(title: String, link: String, body: String = "") -> Story {
        return Story(title: title, link: link, body: body, imageURL: "", source: "")
    }

    private func makeFeed(name: String, url: String) -> Feed {
        return Feed(name: name, url: url)
    }

    // MARK: - Tests

    /// When both feeds have identical articles (same URLs), uniqueToA and uniqueToB should be 0.
    func testFullOverlapBothDirections() {
        let feedA = makeFeed(name: "A", url: "https://a.com/rss")
        let feedB = makeFeed(name: "B", url: "https://b.com/rss")

        let stories = [
            makeStory(title: "Article One", link: "https://example.com/1"),
            makeStory(title: "Article Two", link: "https://example.com/2"),
            makeStory(title: "Article Three", link: "https://example.com/3"),
        ]

        let result = FeedComparisonManager.shared.compare(
            feedA: feedA, feedB: feedB,
            storiesA: stories, storiesB: stories
        )

        XCTAssertEqual(result.overlap.exactMatches, 3)
        XCTAssertEqual(result.overlap.uniqueToA, 0)
        XCTAssertEqual(result.overlap.uniqueToB, 0)
        XCTAssertGreaterThanOrEqual(result.overlap.uniqueToA, 0, "uniqueToA must never be negative")
        XCTAssertGreaterThanOrEqual(result.overlap.uniqueToB, 0, "uniqueToB must never be negative")
    }

    /// When feed A has fewer articles than the overlap count from feed B,
    /// uniqueToA should be 0, not negative.
    func testAsymmetricFeedSizesNoNegativeUnique() {
        let feedA = makeFeed(name: "Small", url: "https://small.com/rss")
        let feedB = makeFeed(name: "Big", url: "https://big.com/rss")

        // Feed A: 2 articles
        let storiesA = [
            makeStory(title: "Shared Article Alpha", link: "https://example.com/shared1"),
            makeStory(title: "Shared Article Beta", link: "https://example.com/shared2"),
        ]

        // Feed B: 5 articles including both shared ones
        let storiesB = [
            makeStory(title: "Shared Article Alpha", link: "https://example.com/shared1"),
            makeStory(title: "Shared Article Beta", link: "https://example.com/shared2"),
            makeStory(title: "Extra Article Gamma", link: "https://example.com/extra1"),
            makeStory(title: "Extra Article Delta", link: "https://example.com/extra2"),
            makeStory(title: "Extra Article Epsilon", link: "https://example.com/extra3"),
        ]

        let result = FeedComparisonManager.shared.compare(
            feedA: feedA, feedB: feedB,
            storiesA: storiesA, storiesB: storiesB
        )

        XCTAssertEqual(result.overlap.exactMatches, 2)
        XCTAssertEqual(result.overlap.uniqueToA, 0)
        XCTAssertEqual(result.overlap.uniqueToB, 3)
        XCTAssertGreaterThanOrEqual(result.overlap.uniqueToA, 0)
        XCTAssertGreaterThanOrEqual(result.overlap.uniqueToB, 0)
    }

    /// When feeds have no overlap at all, unique counts should equal article counts.
    func testNoOverlap() {
        let feedA = makeFeed(name: "Tech", url: "https://tech.com/rss")
        let feedB = makeFeed(name: "Sports", url: "https://sports.com/rss")

        let storiesA = [
            makeStory(title: "Rust 2.0 Released", link: "https://tech.com/rust"),
            makeStory(title: "New GPU Architecture", link: "https://tech.com/gpu"),
        ]
        let storiesB = [
            makeStory(title: "World Cup Finals", link: "https://sports.com/wc"),
            makeStory(title: "Olympics 2028 Preview", link: "https://sports.com/olympics"),
            makeStory(title: "Tennis Grand Slam", link: "https://sports.com/tennis"),
        ]

        let result = FeedComparisonManager.shared.compare(
            feedA: feedA, feedB: feedB,
            storiesA: storiesA, storiesB: storiesB
        )

        XCTAssertEqual(result.overlap.exactMatches, 0)
        XCTAssertEqual(result.overlap.titleMatches, 0)
        XCTAssertEqual(result.overlap.uniqueToA, 2)
        XCTAssertEqual(result.overlap.uniqueToB, 3)
        XCTAssertEqual(result.overlap.overlapRatio, 0.0, accuracy: 0.001)
    }

    /// Empty feeds should produce zero overlap and zero unique counts.
    func testEmptyFeeds() {
        let feedA = makeFeed(name: "Empty1", url: "https://e1.com/rss")
        let feedB = makeFeed(name: "Empty2", url: "https://e2.com/rss")

        let result = FeedComparisonManager.shared.compare(
            feedA: feedA, feedB: feedB,
            storiesA: [], storiesB: []
        )

        XCTAssertEqual(result.overlap.exactMatches, 0)
        XCTAssertEqual(result.overlap.uniqueToA, 0)
        XCTAssertEqual(result.overlap.uniqueToB, 0)
        XCTAssertEqual(result.overlap.overlapRatio, 0.0)
    }

    /// Overlap ratio should be capped at 1.0 even with title matches + URL matches.
    func testOverlapRatioCappedAtOne() {
        let feedA = makeFeed(name: "A", url: "https://a.com/rss")
        let feedB = makeFeed(name: "B", url: "https://b.com/rss")

        // Single article in each, same URL
        let storiesA = [makeStory(title: "Breaking News Today", link: "https://shared.com/1")]
        let storiesB = [makeStory(title: "Breaking News Today", link: "https://shared.com/1")]

        let result = FeedComparisonManager.shared.compare(
            feedA: feedA, feedB: feedB,
            storiesA: storiesA, storiesB: storiesB
        )

        XCTAssertLessThanOrEqual(result.overlap.overlapRatio, 1.0,
                                  "Overlap ratio must never exceed 1.0")
    }
}
