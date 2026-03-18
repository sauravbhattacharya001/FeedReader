//
//  ArticleReactionManagerTests.swift
//  FeedReaderTests
//

import XCTest
@testable import FeedReader

class ArticleReactionManagerTests: XCTestCase {

    var manager: ArticleReactionManager!
    var tempDir: URL!

    override func setUp() {
        super.setUp()
        tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        manager = ArticleReactionManager(directory: tempDir)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: tempDir)
        super.tearDown()
    }

    // MARK: - Toggle

    func testToggleAddsReaction() {
        let added = manager.toggleReaction(.heart, articleURL: "https://example.com/1", articleTitle: "Test Article")
        XCTAssertTrue(added)
        XCTAssertEqual(manager.count, 1)
        XCTAssertTrue(manager.hasReaction(.heart, for: "https://example.com/1"))
    }

    func testToggleRemovesExistingReaction() {
        manager.toggleReaction(.heart, articleURL: "https://example.com/1", articleTitle: "Test")
        let removed = manager.toggleReaction(.heart, articleURL: "https://example.com/1", articleTitle: "Test")
        XCTAssertFalse(removed)
        XCTAssertEqual(manager.count, 0)
    }

    func testMultipleReactionsOnSameArticle() {
        manager.toggleReaction(.heart, articleURL: "https://example.com/1", articleTitle: "Test")
        manager.toggleReaction(.laugh, articleURL: "https://example.com/1", articleTitle: "Test")
        XCTAssertEqual(manager.totalReactions(for: "https://example.com/1"), 2)
    }

    // MARK: - Counts

    func testReactionCounts() {
        manager.toggleReaction(.heart, articleURL: "https://example.com/1", articleTitle: "A")
        manager.toggleReaction(.thumbsUp, articleURL: "https://example.com/1", articleTitle: "A")
        let counts = manager.reactionCounts(for: "https://example.com/1")
        XCTAssertEqual(counts[.heart], 1)
        XCTAssertEqual(counts[.thumbsUp], 1)
        XCTAssertNil(counts[.angry])
    }

    // MARK: - Filter by Reaction

    func testArticlesWithReaction() {
        manager.toggleReaction(.heart, articleURL: "https://example.com/1", articleTitle: "A")
        manager.toggleReaction(.laugh, articleURL: "https://example.com/2", articleTitle: "B")
        manager.toggleReaction(.heart, articleURL: "https://example.com/3", articleTitle: "C")

        let hearted = manager.articles(with: .heart)
        XCTAssertEqual(hearted.count, 2)
    }

    // MARK: - Trending

    func testTrending() {
        // Article 1 gets 3 reactions, article 2 gets 1
        manager.toggleReaction(.heart, articleURL: "https://example.com/1", articleTitle: "Popular")
        manager.toggleReaction(.thumbsUp, articleURL: "https://example.com/1", articleTitle: "Popular")
        manager.toggleReaction(.laugh, articleURL: "https://example.com/1", articleTitle: "Popular")
        manager.toggleReaction(.heart, articleURL: "https://example.com/2", articleTitle: "Less Popular")

        let trending = manager.trending(limit: 10)
        XCTAssertEqual(trending.count, 2)
        XCTAssertEqual(trending.first?.url, "https://example.com/1")
        XCTAssertEqual(trending.first?.count, 3)
    }

    // MARK: - Stats

    func testStats() {
        manager.toggleReaction(.heart, articleURL: "https://example.com/1", articleTitle: "A", feedName: "Tech")
        manager.toggleReaction(.heart, articleURL: "https://example.com/2", articleTitle: "B", feedName: "Tech")
        manager.toggleReaction(.laugh, articleURL: "https://example.com/3", articleTitle: "C", feedName: "News")

        let stats = manager.stats()
        XCTAssertEqual(stats.totalReactions, 3)
        XCTAssertEqual(stats.uniqueArticlesReacted, 3)
        XCTAssertEqual(stats.favoriteReaction, .heart)
        XCTAssertEqual(stats.mostReactedFeed, "Tech")
    }

    // MARK: - History

    func testRecentHistory() {
        manager.toggleReaction(.heart, articleURL: "https://example.com/1", articleTitle: "A")
        manager.toggleReaction(.laugh, articleURL: "https://example.com/2", articleTitle: "B")
        let history = manager.recentHistory(limit: 10)
        XCTAssertEqual(history.count, 2)
        // Most recent first
        XCTAssertEqual(history.first?.reaction, .laugh)
    }

    // MARK: - Bulk Operations

    func testRemoveAllForArticle() {
        manager.toggleReaction(.heart, articleURL: "https://example.com/1", articleTitle: "A")
        manager.toggleReaction(.laugh, articleURL: "https://example.com/1", articleTitle: "A")
        manager.toggleReaction(.heart, articleURL: "https://example.com/2", articleTitle: "B")

        manager.removeAllReactions(for: "https://example.com/1")
        XCTAssertEqual(manager.count, 1)
        XCTAssertEqual(manager.totalReactions(for: "https://example.com/1"), 0)
    }

    func testClearAll() {
        manager.toggleReaction(.heart, articleURL: "https://example.com/1", articleTitle: "A")
        manager.toggleReaction(.laugh, articleURL: "https://example.com/2", articleTitle: "B")
        manager.clearAll()
        XCTAssertEqual(manager.count, 0)
    }

    // MARK: - Export

    func testExportJSON() {
        manager.toggleReaction(.heart, articleURL: "https://example.com/1", articleTitle: "A")
        let json = manager.exportJSON()
        XCTAssertNotNil(json)
        let str = String(data: json!, encoding: .utf8)!
        XCTAssertTrue(str.contains("❤️"))
    }

    func testExportCSV() {
        manager.toggleReaction(.thumbsUp, articleURL: "https://example.com/1", articleTitle: "Test \"Quoted\"", feedName: "Tech")
        let csv = manager.exportCSV()
        XCTAssertTrue(csv.contains("article_url"))
        XCTAssertTrue(csv.contains("Test \"\"Quoted\"\""))
    }

    // MARK: - Persistence

    func testPersistence() {
        manager.toggleReaction(.heart, articleURL: "https://example.com/1", articleTitle: "Persist Test")

        // Create new manager from same directory
        let manager2 = ArticleReactionManager(directory: tempDir)
        XCTAssertEqual(manager2.count, 1)
        XCTAssertTrue(manager2.hasReaction(.heart, for: "https://example.com/1"))
    }

    // MARK: - Stats Summary

    func testStatsSummary() {
        manager.toggleReaction(.heart, articleURL: "https://example.com/1", articleTitle: "A")
        let summary = manager.stats().summary
        XCTAssertTrue(summary.contains("Reaction Stats"))
        XCTAssertTrue(summary.contains("Total reactions: 1"))
    }
}
