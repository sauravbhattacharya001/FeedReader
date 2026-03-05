//
//  FeedMergeManagerTests.swift
//  FeedReaderTests
//
//  Tests for FeedMergeManager — virtual merged feeds with deduplication and sorting.
//

import XCTest
@testable import FeedReader

class FeedMergeManagerTests: XCTestCase {

    var manager: FeedMergeManager!

    override func setUp() {
        super.setUp()
        manager = FeedMergeManager()
        manager.reset()
    }

    // MARK: - Creation

    func testCreateMergedFeed() {
        let feed = manager.create(name: "News Mix", icon: "📰", feedURLs: ["https://a.com/rss", "https://b.com/rss"])
        XCTAssertEqual(feed.name, "News Mix")
        XCTAssertEqual(feed.icon, "📰")
        XCTAssertEqual(feed.sourceCount, 2)
        XCTAssertEqual(manager.mergedFeeds.count, 1)
    }

    func testCreateWithDefaults() {
        let feed = manager.create(name: "Test")
        XCTAssertEqual(feed.icon, "📦")
        XCTAssertEqual(feed.sortOrder, .newestFirst)
        XCTAssertTrue(feed.deduplicationEnabled)
        XCTAssertEqual(feed.maxArticles, 0)
    }

    func testCreateEmptyNameFallsBackToUntitled() {
        let feed = manager.create(name: "   ")
        // Empty name creates feed but doesn't add to list
        XCTAssertEqual(feed.name, "Untitled")
    }

    func testCreateMultiple() {
        manager.create(name: "A")
        manager.create(name: "B")
        manager.create(name: "C")
        XCTAssertEqual(manager.mergedFeeds.count, 3)
    }

    // MARK: - Find

    func testFindById() {
        let feed = manager.create(name: "Findable")
        XCTAssertNotNil(manager.find(id: feed.id))
        XCTAssertEqual(manager.find(id: feed.id)?.name, "Findable")
    }

    func testFindNonexistent() {
        XCTAssertNil(manager.find(id: "nope"))
    }

    // MARK: - Update

    func testUpdateName() {
        let feed = manager.create(name: "Old Name")
        let updated = manager.update(id: feed.id) { $0.name = "New Name" }
        XCTAssertEqual(updated?.name, "New Name")
        XCTAssertEqual(manager.find(id: feed.id)?.name, "New Name")
    }

    func testUpdateSortOrder() {
        let feed = manager.create(name: "Test")
        manager.update(id: feed.id) { $0.sortOrder = .alphabetical }
        XCTAssertEqual(manager.find(id: feed.id)?.sortOrder, .alphabetical)
    }

    func testUpdateNonexistent() {
        let result = manager.update(id: "nope") { $0.name = "X" }
        XCTAssertNil(result)
    }

    func testUpdateSetsUpdatedAt() {
        let feed = manager.create(name: "Test")
        let before = feed.updatedAt
        Thread.sleep(forTimeInterval: 0.01)
        let updated = manager.update(id: feed.id) { $0.icon = "🌟" }
        XCTAssertGreaterThan(updated!.updatedAt, before)
    }

    // MARK: - Delete

    func testDelete() {
        let feed = manager.create(name: "Doomed")
        XCTAssertTrue(manager.delete(id: feed.id))
        XCTAssertEqual(manager.mergedFeeds.count, 0)
    }

    func testDeleteNonexistent() {
        XCTAssertFalse(manager.delete(id: "nope"))
    }

    func testDeleteAll() {
        manager.create(name: "A")
        manager.create(name: "B")
        manager.deleteAll()
        XCTAssertEqual(manager.mergedFeeds.count, 0)
    }

    // MARK: - Feed URL Management

    func testAddFeedURL() {
        let feed = manager.create(name: "Test")
        XCTAssertTrue(manager.addFeed(url: "https://x.com/rss", to: feed.id))
        XCTAssertEqual(manager.find(id: feed.id)?.feedURLs.count, 1)
    }

    func testAddDuplicateFeedURL() {
        let feed = manager.create(name: "Test", feedURLs: ["https://x.com/rss"])
        manager.addFeed(url: "https://X.COM/rss", to: feed.id) // case-insensitive
        XCTAssertEqual(manager.find(id: feed.id)?.feedURLs.count, 1)
    }

    func testRemoveFeedURL() {
        let feed = manager.create(name: "Test", feedURLs: ["https://x.com/rss", "https://y.com/rss"])
        XCTAssertTrue(manager.removeFeed(url: "https://x.com/rss", from: feed.id))
        XCTAssertEqual(manager.find(id: feed.id)?.feedURLs.count, 1)
    }

    func testAddFeedToNonexistent() {
        XCTAssertFalse(manager.addFeed(url: "https://x.com", to: "nope"))
    }

    // MARK: - Article Resolution

    private func makeProvider(_ data: [String: [(String, String, String, String?, Date?)]]) ->
        (String) -> [(title: String, link: String, body: String, sourceName: String?, date: Date?)] {
        return { url in
            return (data[url] ?? []).map { (title: $0.0, link: $0.1, body: $0.2, sourceName: $0.3, date: $0.4) }
        }
    }

    private func date(_ offset: TimeInterval) -> Date {
        return Date(timeIntervalSince1970: offset)
    }

    func testResolveArticlesBasic() {
        let feed = manager.create(name: "Mix", feedURLs: ["https://a.com", "https://b.com"])
        let provider = makeProvider([
            "https://a.com": [("Title A", "https://a.com/1", "Body A", "Feed A", date(100))],
            "https://b.com": [("Title B", "https://b.com/1", "Body B", "Feed B", date(200))]
        ])
        let articles = manager.resolveArticles(for: feed.id, articleProvider: provider)
        XCTAssertEqual(articles.count, 2)
    }

    func testResolveWithDeduplication() {
        let feed = manager.create(name: "Mix", feedURLs: ["https://a.com", "https://b.com"])
        let provider = makeProvider([
            "https://a.com": [("Same Title", "https://a.com/1", "Body A", "Feed A", date(100))],
            "https://b.com": [("same title", "https://b.com/1", "Body B", "Feed B", date(200))]
        ])
        let articles = manager.resolveArticles(for: feed.id, articleProvider: provider)
        XCTAssertEqual(articles.count, 1) // deduplicated by title
    }

    func testResolveWithoutDeduplication() {
        let feed = manager.create(name: "Mix", feedURLs: ["https://a.com", "https://b.com"], deduplicationEnabled: false)
        let provider = makeProvider([
            "https://a.com": [("Same Title", "https://a.com/1", "Body A", nil, nil)],
            "https://b.com": [("same title", "https://b.com/1", "Body B", nil, nil)]
        ])
        let articles = manager.resolveArticles(for: feed.id, articleProvider: provider)
        XCTAssertEqual(articles.count, 2)
    }

    func testResolveNewestFirst() {
        let feed = manager.create(name: "Mix", feedURLs: ["https://a.com"], sortOrder: .newestFirst)
        let provider = makeProvider([
            "https://a.com": [
                ("Old", "https://a.com/1", "B", nil, date(100)),
                ("New", "https://a.com/2", "B", nil, date(200))
            ]
        ])
        let articles = manager.resolveArticles(for: feed, articleProvider: provider)
        XCTAssertEqual(articles.first?.title, "New")
    }

    func testResolveOldestFirst() {
        let feed = manager.create(name: "Mix", feedURLs: ["https://a.com"], sortOrder: .oldestFirst)
        let provider = makeProvider([
            "https://a.com": [
                ("New", "https://a.com/2", "B", nil, date(200)),
                ("Old", "https://a.com/1", "B", nil, date(100))
            ]
        ])
        let articles = manager.resolveArticles(for: feed, articleProvider: provider)
        XCTAssertEqual(articles.first?.title, "Old")
    }

    func testResolveAlphabetical() {
        let feed = manager.create(name: "Mix", feedURLs: ["https://a.com"], sortOrder: .alphabetical)
        let provider = makeProvider([
            "https://a.com": [
                ("Banana", "https://a.com/2", "B", nil, nil),
                ("Apple", "https://a.com/1", "B", nil, nil)
            ]
        ])
        let articles = manager.resolveArticles(for: feed, articleProvider: provider)
        XCTAssertEqual(articles.first?.title, "Apple")
    }

    func testResolveSourceThenDate() {
        let feed = manager.create(name: "Mix", feedURLs: ["https://b.com", "https://a.com"], sortOrder: .sourceThenDate)
        let provider = makeProvider([
            "https://a.com": [("A1", "https://a.com/1", "B", nil, date(100))],
            "https://b.com": [("B1", "https://b.com/1", "B", nil, date(200))]
        ])
        let articles = manager.resolveArticles(for: feed, articleProvider: provider)
        XCTAssertEqual(articles.first?.sourceFeedURL, "https://a.com")
    }

    func testResolveWithMaxArticles() {
        let feed = manager.create(name: "Mix", feedURLs: ["https://a.com"], maxArticles: 2)
        let provider = makeProvider([
            "https://a.com": [
                ("A", "https://a.com/1", "B", nil, date(100)),
                ("B", "https://a.com/2", "B", nil, date(200)),
                ("C", "https://a.com/3", "B", nil, date(300))
            ]
        ])
        let articles = manager.resolveArticles(for: feed, articleProvider: provider)
        XCTAssertEqual(articles.count, 2)
    }

    func testResolveNonexistentFeed() {
        let articles = manager.resolveArticles(for: "nope", articleProvider: { _ in [] })
        XCTAssertTrue(articles.isEmpty)
    }

    // MARK: - Deduplication

    func testDeduplicateKeepsFirst() {
        let articles = [
            MergedArticle(title: "Test", link: "https://a.com/1", body: "First", sourceFeedURL: "a", sourceFeedName: nil, date: nil),
            MergedArticle(title: "test", link: "https://b.com/1", body: "Second", sourceFeedURL: "b", sourceFeedName: nil, date: nil)
        ]
        let result = manager.deduplicate(articles)
        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result.first?.body, "First")
    }

    func testDeduplicateDistinctTitles() {
        let articles = [
            MergedArticle(title: "A", link: "l", body: "b", sourceFeedURL: "x", sourceFeedName: nil, date: nil),
            MergedArticle(title: "B", link: "l", body: "b", sourceFeedURL: "x", sourceFeedName: nil, date: nil)
        ]
        XCTAssertEqual(manager.deduplicate(articles).count, 2)
    }

    // MARK: - Search

    func testSearchByName() {
        manager.create(name: "Tech News")
        manager.create(name: "Sports Mix")
        let results = manager.search(query: "tech")
        XCTAssertEqual(results.count, 1)
        XCTAssertEqual(results.first?.name, "Tech News")
    }

    func testSearchNoMatch() {
        manager.create(name: "ABC")
        XCTAssertTrue(manager.search(query: "xyz").isEmpty)
    }

    func testMergedFeedsContainingURL() {
        manager.create(name: "A", feedURLs: ["https://x.com/rss"])
        manager.create(name: "B", feedURLs: ["https://y.com/rss"])
        manager.create(name: "C", feedURLs: ["https://x.com/rss", "https://z.com/rss"])
        let results = manager.mergedFeedsContaining(feedURL: "https://x.com/rss")
        XCTAssertEqual(results.count, 2)
    }

    // MARK: - Statistics

    func testStats() {
        let feed = manager.create(name: "Mix", feedURLs: ["https://a.com", "https://b.com"])
        let provider = makeProvider([
            "https://a.com": [
                ("Shared Title", "https://a.com/1", "B", nil, date(100)),
                ("Unique A", "https://a.com/2", "B", nil, date(200))
            ],
            "https://b.com": [
                ("shared title", "https://b.com/1", "B", nil, date(150))
            ]
        ])
        let s = manager.stats(for: feed.id, articleProvider: provider)
        XCTAssertNotNil(s)
        XCTAssertEqual(s?.totalArticles, 3)
        XCTAssertEqual(s?.uniqueArticles, 2)
        XCTAssertEqual(s?.duplicatesRemoved, 1)
        XCTAssertEqual(s?.sourceCount, 2)
    }

    func testStatsNonexistent() {
        XCTAssertNil(manager.stats(for: "nope", articleProvider: { _ in [] }))
    }

    // MARK: - Text Report

    func testTextReport() {
        manager.create(name: "Mix", icon: "🌐", feedURLs: ["https://a.com"])
        let report = manager.textReport()
        XCTAssertTrue(report.contains("Mix"))
        XCTAssertTrue(report.contains("🌐"))
        XCTAssertTrue(report.contains("Total merged feeds: 1"))
    }

    func testTextReportEmpty() {
        let report = manager.textReport()
        XCTAssertTrue(report.contains("Total merged feeds: 0"))
    }

    // MARK: - Export / Import

    func testExportImportRoundTrip() {
        manager.create(name: "Export Test", icon: "🔄", feedURLs: ["https://x.com"])
        guard let data = manager.exportJSON() else {
            XCTFail("Export failed"); return
        }

        let manager2 = FeedMergeManager()
        manager2.reset()
        let count = manager2.importJSON(data)
        XCTAssertEqual(count, 1)
        XCTAssertEqual(manager2.mergedFeeds.first?.name, "Export Test")
    }

    func testImportSkipsDuplicates() {
        let feed = manager.create(name: "Test")
        guard let data = manager.exportJSON() else {
            XCTFail("Export failed"); return
        }
        let count = manager.importJSON(data)
        XCTAssertEqual(count, 0) // already exists
    }

    func testImportInvalidData() {
        let count = manager.importJSON(Data("garbage".utf8))
        XCTAssertEqual(count, 0)
    }

    // MARK: - Sort Order

    func testSortOrderDisplayNames() {
        XCTAssertEqual(MergedFeedSortOrder.newestFirst.displayName, "Newest First")
        XCTAssertEqual(MergedFeedSortOrder.oldestFirst.displayName, "Oldest First")
        XCTAssertEqual(MergedFeedSortOrder.alphabetical.displayName, "A → Z by Title")
        XCTAssertEqual(MergedFeedSortOrder.sourceThenDate.displayName, "By Source, then Date")
    }

    func testAllSortOrders() {
        XCTAssertEqual(MergedFeedSortOrder.allCases.count, 4)
    }

    // MARK: - MergedArticle

    func testArticleFingerprint() {
        let a = MergedArticle(title: "  Hello World  ", link: "l", body: "b", sourceFeedURL: "u", sourceFeedName: nil, date: nil)
        XCTAssertEqual(a.fingerprint, "hello world")
    }

    // MARK: - MergedFeed Equatable

    func testMergedFeedEquatable() {
        let a = MergedFeed(name: "A")
        let b = a
        XCTAssertEqual(a, b)
    }

    // MARK: - Edge Cases

    func testResolveEmptyFeedURLs() {
        let feed = manager.create(name: "Empty")
        let articles = manager.resolveArticles(for: feed, articleProvider: { _ in [] })
        XCTAssertTrue(articles.isEmpty)
    }

    func testMaxArticlesZeroMeansUnlimited() {
        let feed = manager.create(name: "Test", feedURLs: ["https://a.com"], maxArticles: 0)
        let provider = makeProvider([
            "https://a.com": (1...50).map { ("Title \($0)", "https://a.com/\($0)", "B", nil, date(Double($0))) }
        ])
        let articles = manager.resolveArticles(for: feed, articleProvider: provider)
        XCTAssertEqual(articles.count, 50)
    }

    func testResolveWithNilDates() {
        let feed = manager.create(name: "Mix", feedURLs: ["https://a.com"], sortOrder: .newestFirst)
        let provider = makeProvider([
            "https://a.com": [
                ("No Date", "https://a.com/1", "B", nil, nil),
                ("Has Date", "https://a.com/2", "B", nil, date(100))
            ]
        ])
        let articles = manager.resolveArticles(for: feed, articleProvider: provider)
        XCTAssertEqual(articles.count, 2)
        XCTAssertEqual(articles.first?.title, "Has Date") // dated articles sort first for newestFirst
    }

    func testTextReportWithArticleProvider() {
        let feed = manager.create(name: "Mix", feedURLs: ["https://a.com"])
        let provider = makeProvider([
            "https://a.com": [("T", "https://a.com/1", "B", nil, nil)]
        ])
        let report = manager.textReport(articleProvider: provider)
        XCTAssertTrue(report.contains("1 total"))
        XCTAssertTrue(report.contains("1 unique"))
    }

    func testRemoveFeedURLCaseInsensitive() {
        let feed = manager.create(name: "Test", feedURLs: ["https://X.com/rss"])
        manager.removeFeed(url: "https://x.com/rss", from: feed.id)
        XCTAssertEqual(manager.find(id: feed.id)?.feedURLs.count, 0)
    }
}
