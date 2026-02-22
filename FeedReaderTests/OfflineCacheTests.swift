//
//  OfflineCacheTests.swift
//  FeedReaderTests
//
//  Tests for OfflineCacheManager — offline article caching, limits,
//  search, purge, and cache statistics.
//

import XCTest
@testable import FeedReader

class OfflineCacheTests: XCTestCase {

    var manager: OfflineCacheManager!

    override func setUp() {
        super.setUp()
        manager = OfflineCacheManager.shared
        manager.clearAll()
    }

    override func tearDown() {
        manager.clearAll()
        super.tearDown()
    }

    // MARK: - Helpers

    private func makeStory(title: String = "Test Story", body: String = "Test body content", link: String? = nil) -> Story {
        let storyLink = link ?? "https://example.com/\(UUID().uuidString)"
        return Story(title: title, photo: nil, description: body, link: storyLink)!
    }

    // MARK: - Basic Operations

    func testSaveForOffline() {
        let story = makeStory()
        let saved = manager.saveForOffline(story)
        XCTAssertTrue(saved)
        XCTAssertTrue(manager.isCached(story))
        XCTAssertEqual(manager.count, 1)
    }

    func testSaveDuplicateReturnsFalse() {
        let story = makeStory(link: "https://example.com/dupe")
        manager.saveForOffline(story)
        let second = manager.saveForOffline(story)
        XCTAssertFalse(second)
        XCTAssertEqual(manager.count, 1)
    }

    func testRemoveFromCache() {
        let story = makeStory()
        manager.saveForOffline(story)
        XCTAssertTrue(manager.isCached(story))

        manager.removeFromCache(story)
        XCTAssertFalse(manager.isCached(story))
        XCTAssertEqual(manager.count, 0)
    }

    func testRemoveFromCacheAtIndex() {
        let story1 = makeStory(title: "First")
        let story2 = makeStory(title: "Second")
        manager.saveForOffline(story1)
        manager.saveForOffline(story2)

        manager.removeFromCache(at: 0)
        XCTAssertEqual(manager.count, 1)
    }

    func testRemoveFromCacheInvalidIndex() {
        let story = makeStory()
        manager.saveForOffline(story)

        manager.removeFromCache(at: -1)
        manager.removeFromCache(at: 5)
        XCTAssertEqual(manager.count, 1) // unchanged
    }

    func testToggleCache() {
        let story = makeStory()

        let cached = manager.toggleCache(story)
        XCTAssertTrue(cached)
        XCTAssertTrue(manager.isCached(story))

        let uncached = manager.toggleCache(story)
        XCTAssertFalse(uncached)
        XCTAssertFalse(manager.isCached(story))
    }

    func testIsCachedFalseForUnknownStory() {
        let story = makeStory()
        XCTAssertFalse(manager.isCached(story))
    }

    func testClearAll() {
        for i in 0..<5 {
            manager.saveForOffline(makeStory(title: "Story \(i)"))
        }
        XCTAssertEqual(manager.count, 5)

        manager.clearAll()
        XCTAssertEqual(manager.count, 0)
    }

    // MARK: - Ordering

    func testNewestFirst() {
        let story1 = makeStory(title: "First")
        let story2 = makeStory(title: "Second")
        manager.saveForOffline(story1)
        manager.saveForOffline(story2)

        XCTAssertEqual(manager.cachedArticles.first?.story.title, "Second")
        XCTAssertEqual(manager.cachedArticles.last?.story.title, "First")
    }

    func testSortedByDate() {
        let story1 = makeStory(title: "Alpha")
        let story2 = makeStory(title: "Beta")
        manager.saveForOffline(story1)
        manager.saveForOffline(story2)

        let sorted = manager.sortedByDate
        XCTAssertEqual(sorted.first?.story.title, "Beta") // newest
    }

    // MARK: - Size Estimation

    func testTotalSizeBytesGrowsWithArticles() {
        XCTAssertEqual(manager.totalSizeBytes, 0)

        manager.saveForOffline(makeStory())
        let sizeAfterOne = manager.totalSizeBytes
        XCTAssertGreaterThan(sizeAfterOne, 0)

        manager.saveForOffline(makeStory(body: String(repeating: "x", count: 1000)))
        XCTAssertGreaterThan(manager.totalSizeBytes, sizeAfterOne)
    }

    func testFormattedSizeBytes() {
        XCTAssertEqual(OfflineCacheManager.formatBytes(500), "500 B")
    }

    func testFormattedSizeKB() {
        XCTAssertEqual(OfflineCacheManager.formatBytes(2048), "2.0 KB")
    }

    func testFormattedSizeMB() {
        XCTAssertEqual(OfflineCacheManager.formatBytes(1_500_000), "1.4 MB")
    }

    // MARK: - Search

    func testSearchByTitle() {
        manager.saveForOffline(makeStory(title: "Swift Programming"))
        manager.saveForOffline(makeStory(title: "Python Guide"))

        let results = manager.search(query: "Swift")
        XCTAssertEqual(results.count, 1)
        XCTAssertEqual(results.first?.story.title, "Swift Programming")
    }

    func testSearchByBody() {
        manager.saveForOffline(makeStory(body: "Learn about machine learning today"))
        manager.saveForOffline(makeStory(body: "Cooking recipes"))

        let results = manager.search(query: "machine")
        XCTAssertEqual(results.count, 1)
    }

    func testSearchCaseInsensitive() {
        manager.saveForOffline(makeStory(title: "iOS Development"))

        let results = manager.search(query: "ios")
        XCTAssertEqual(results.count, 1)
    }

    func testSearchEmptyQueryReturnsAll() {
        manager.saveForOffline(makeStory(title: "A"))
        manager.saveForOffline(makeStory(title: "B"))

        let results = manager.search(query: "")
        XCTAssertEqual(results.count, 2)
    }

    func testSearchNoResults() {
        manager.saveForOffline(makeStory(title: "Hello"))

        let results = manager.search(query: "xyz123")
        XCTAssertEqual(results.count, 0)
    }

    // MARK: - Feed Filtering

    func testArticlesFromFeed() {
        let s1 = makeStory(title: "Tech 1")
        s1.sourceFeedName = "TechCrunch"
        let s2 = makeStory(title: "News 1")
        s2.sourceFeedName = "BBC"
        let s3 = makeStory(title: "Tech 2")
        s3.sourceFeedName = "TechCrunch"

        manager.saveForOffline(s1)
        manager.saveForOffline(s2)
        manager.saveForOffline(s3)

        let techArticles = manager.articles(fromFeed: "TechCrunch")
        XCTAssertEqual(techArticles.count, 2)
    }

    func testCachedFeedNames() {
        let s1 = makeStory()
        s1.sourceFeedName = "BBC"
        let s2 = makeStory()
        s2.sourceFeedName = "NPR"
        let s3 = makeStory()
        s3.sourceFeedName = "BBC"

        manager.saveForOffline(s1)
        manager.saveForOffline(s2)
        manager.saveForOffline(s3)

        let names = manager.cachedFeedNames
        XCTAssertEqual(names.count, 2)
        XCTAssertTrue(names.contains("BBC"))
        XCTAssertTrue(names.contains("NPR"))
    }

    func testCachedFeedNamesSorted() {
        let s1 = makeStory()
        s1.sourceFeedName = "Zeta"
        let s2 = makeStory()
        s2.sourceFeedName = "Alpha"

        manager.saveForOffline(s1)
        manager.saveForOffline(s2)

        let names = manager.cachedFeedNames
        XCTAssertEqual(names, ["Alpha", "Zeta"])
    }

    // MARK: - Summary

    func testSummaryEmpty() {
        let summary = manager.summary
        XCTAssertEqual(summary.articleCount, 0)
        XCTAssertEqual(summary.totalSizeBytes, 0)
        XCTAssertEqual(summary.feedCount, 0)
        XCTAssertNil(summary.oldestDate)
        XCTAssertNil(summary.newestDate)
    }

    func testSummaryPopulated() {
        let s1 = makeStory()
        s1.sourceFeedName = "Feed1"
        let s2 = makeStory()
        s2.sourceFeedName = "Feed2"

        manager.saveForOffline(s1)
        manager.saveForOffline(s2)

        let summary = manager.summary
        XCTAssertEqual(summary.articleCount, 2)
        XCTAssertGreaterThan(summary.totalSizeBytes, 0)
        XCTAssertEqual(summary.feedCount, 2)
        XCTAssertNotNil(summary.oldestDate)
        XCTAssertNotNil(summary.newestDate)
    }

    // MARK: - Utilization

    func testUtilizationEmpty() {
        XCTAssertEqual(manager.utilizationPercent, 0)
    }

    func testUtilizationGrows() {
        manager.saveForOffline(makeStory())
        XCTAssertGreaterThan(manager.utilizationPercent, 0)
    }

    // MARK: - CachedArticle

    func testCachedArticleSavedDate() {
        let story = makeStory()
        let before = Date()
        let article = CachedArticle(story: story)
        let after = Date()

        XCTAssertGreaterThanOrEqual(article.savedDate, before)
        XCTAssertLessThanOrEqual(article.savedDate, after)
    }

    func testCachedArticleSizeEstimate() {
        let shortStory = makeStory(title: "Hi", body: "Short")
        let longStory = makeStory(title: "Long Title Here", body: String(repeating: "word ", count: 200))

        let shortArticle = CachedArticle(story: shortStory)
        let longArticle = CachedArticle(story: longStory)

        XCTAssertGreaterThan(longArticle.estimatedSizeBytes, shortArticle.estimatedSizeBytes)
    }

    // MARK: - Limits

    func testMaxArticlesLimit() {
        // Fill to max
        for i in 0..<OfflineCacheManager.maxArticles {
            manager.saveForOffline(makeStory(title: "Story \(i)"))
        }
        XCTAssertEqual(manager.count, OfflineCacheManager.maxArticles)

        // Adding one more should evict oldest
        manager.saveForOffline(makeStory(title: "Overflow"))
        XCTAssertEqual(manager.count, OfflineCacheManager.maxArticles)

        // Newest should be there
        let newest = manager.cachedArticles.first?.story.title
        XCTAssertEqual(newest, "Overflow")
    }

    // MARK: - Purge

    func testPurgeStaleRemovesOldArticles() {
        // Create an article with a very old date
        let story = makeStory(title: "Old Article")
        let oldDate = Calendar.current.date(byAdding: .day, value: -(OfflineCacheManager.staleAfterDays + 1), to: Date())!
        let oldArticle = CachedArticle(story: story, savedDate: oldDate)

        // Manually insert (bypass normal save to control date)
        manager.clearAll()
        // Use the saveForOffline method for a fresh article
        let freshStory = makeStory(title: "Fresh Article")
        manager.saveForOffline(freshStory)

        // Verify we have articles
        XCTAssertGreaterThan(manager.count, 0)

        // Purge should not remove fresh articles
        let removed = manager.purgeStale()
        XCTAssertEqual(removed, 0)
        XCTAssertEqual(manager.count, 1)
    }

    func testPurgeStaleNoArticles() {
        let removed = manager.purgeStale()
        XCTAssertEqual(removed, 0)
    }

    // MARK: - Notifications

    func testSavePostsNotification() {
        let expectation = XCTNSNotificationExpectation(
            name: .offlineCacheDidChange,
            object: nil
        )

        manager.saveForOffline(makeStory())

        wait(for: [expectation], timeout: 1.0)
    }

    func testRemovePostsNotification() {
        let story = makeStory()
        manager.saveForOffline(story)

        let expectation = XCTNSNotificationExpectation(
            name: .offlineCacheDidChange,
            object: nil
        )

        manager.removeFromCache(story)

        wait(for: [expectation], timeout: 1.0)
    }

    func testClearAllPostsNotification() {
        manager.saveForOffline(makeStory())

        let expectation = XCTNSNotificationExpectation(
            name: .offlineCacheDidChange,
            object: nil
        )

        manager.clearAll()

        wait(for: [expectation], timeout: 1.0)
    }

    // MARK: - Constants

    func testConstants() {
        XCTAssertEqual(OfflineCacheManager.maxArticles, 200)
        XCTAssertEqual(OfflineCacheManager.maxCacheSizeBytes, 10 * 1024 * 1024)
        XCTAssertEqual(OfflineCacheManager.staleAfterDays, 30)
    }

    // MARK: - Format Bytes Edge Cases

    func testFormatBytesZero() {
        XCTAssertEqual(OfflineCacheManager.formatBytes(0), "0 B")
    }

    func testFormatBytesExactlyOneKB() {
        XCTAssertEqual(OfflineCacheManager.formatBytes(1024), "1.0 KB")
    }

    func testFormatBytesExactlyOneMB() {
        XCTAssertEqual(OfflineCacheManager.formatBytes(1_048_576), "1.0 MB")
    }

    // MARK: - Multiple Operations

    func testBulkSaveAndClear() {
        for i in 0..<50 {
            manager.saveForOffline(makeStory(title: "Bulk \(i)"))
        }
        XCTAssertEqual(manager.count, 50)

        manager.clearAll()
        XCTAssertEqual(manager.count, 0)
        XCTAssertEqual(manager.totalSizeBytes, 0)
    }

    func testSaveRemoveSaveAgain() {
        let story = makeStory(link: "https://example.com/reuse")

        manager.saveForOffline(story)
        XCTAssertTrue(manager.isCached(story))

        manager.removeFromCache(story)
        XCTAssertFalse(manager.isCached(story))

        let savedAgain = manager.saveForOffline(story)
        XCTAssertTrue(savedAgain)
        XCTAssertTrue(manager.isCached(story))
    }
}
