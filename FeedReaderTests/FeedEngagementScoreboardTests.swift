//
//  FeedEngagementScoreboardTests.swift
//  FeedReaderTests
//

import XCTest
@testable import FeedReader

class FeedEngagementScoreboardTests: XCTestCase {

    var board: FeedEngagementScoreboard!

    override func setUp() {
        super.setUp()
        board = FeedEngagementScoreboard()
        board.resetAll()
    }

    override func tearDown() {
        board.resetAll()
        board = nil
        super.tearDown()
    }

    // MARK: - Basic Recording

    func testRecordArticleReceived() {
        board.recordArticleReceived(feedURL: "https://example.com/feed", feedTitle: "Example")
        XCTAssertEqual(board.trackedFeedCount, 1)
    }

    func testRecordMultipleArticles() {
        board.recordArticleReceived(feedURL: "https://a.com/feed", feedTitle: "A", count: 10)
        board.recordArticleReceived(feedURL: "https://b.com/feed", feedTitle: "B", count: 5)
        XCTAssertEqual(board.trackedFeedCount, 2)
    }

    func testReadRateCalculation() {
        let url = "https://example.com/feed"
        board.recordArticleReceived(feedURL: url, feedTitle: "Example", count: 10)
        board.recordArticleRead(feedURL: url, readingTimeSec: 60)
        board.recordArticleRead(feedURL: url, readingTimeSec: 120)

        let scores = board.rankings()
        XCTAssertEqual(scores.count, 1)
        XCTAssertEqual(scores[0].readRate, 0.20, accuracy: 0.01)
    }

    // MARK: - Ranking

    func testRankingOrder() {
        let urlA = "https://a.com/feed"
        let urlB = "https://b.com/feed"

        board.recordArticleReceived(feedURL: urlA, feedTitle: "A", count: 10)
        board.recordArticleReceived(feedURL: urlB, feedTitle: "B", count: 10)

        // A gets more engagement
        for _ in 0..<8 {
            board.recordArticleRead(feedURL: urlA, readingTimeSec: 120)
        }
        board.recordArticleRead(feedURL: urlB, readingTimeSec: 30)

        let scores = board.rankings()
        XCTAssertEqual(scores[0].feedTitle, "A")
        XCTAssertEqual(scores[0].rank, 1)
        XCTAssertEqual(scores[1].rank, 2)
    }

    func testTopFeeds() {
        for i in 0..<10 {
            let url = "https://feed\(i).com/rss"
            board.recordArticleReceived(feedURL: url, feedTitle: "Feed \(i)", count: 10)
            for _ in 0..<i {
                board.recordArticleRead(feedURL: url, readingTimeSec: 60)
            }
        }
        let top = board.topFeeds(limit: 3)
        XCTAssertEqual(top.count, 3)
        XCTAssertEqual(top[0].rank, 1)
    }

    // MARK: - Tiers

    func testEngagementTiers() {
        XCTAssertEqual(EngagementTier.from(score: 0.90), .star)
        XCTAssertEqual(EngagementTier.from(score: 0.65), .high)
        XCTAssertEqual(EngagementTier.from(score: 0.40), .moderate)
        XCTAssertEqual(EngagementTier.from(score: 0.15), .low)
        XCTAssertEqual(EngagementTier.from(score: 0.05), .dormant)
    }

    // MARK: - Summary & Suggestions

    func testSummaryEmpty() {
        let summary = board.summary()
        XCTAssertNotNil(summary["message"])
    }

    func testSuggestionsNotEmpty() {
        let url = "https://example.com/feed"
        board.recordArticleReceived(feedURL: url, feedTitle: "Example", count: 20)
        let suggestions = board.suggestions()
        XCTAssertFalse(suggestions.isEmpty)
    }

    // MARK: - Weights

    func testCustomWeights() {
        let custom = EngagementWeights(
            readWeight: 1.0,
            bookmarkWeight: 0,
            shareWeight: 0,
            readingTimeWeight: 0,
            recencyWeight: 0
        )
        board.updateWeights(custom)
        let w = board.currentWeights()
        XCTAssertEqual(w.readWeight, 1.0, accuracy: 0.01)
    }

    // MARK: - Export

    func testExportJSON() {
        board.recordArticleReceived(feedURL: "https://a.com/feed", feedTitle: "A", count: 5)
        let data = board.exportJSON()
        XCTAssertNotNil(data)
    }

    // MARK: - Removal

    func testRemoveRecord() {
        let url = "https://example.com/feed"
        board.recordArticleReceived(feedURL: url, feedTitle: "Example")
        XCTAssertEqual(board.trackedFeedCount, 1)
        board.removeRecord(feedURL: url)
        XCTAssertEqual(board.trackedFeedCount, 0)
    }
}
