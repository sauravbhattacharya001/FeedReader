//
//  ContentFilterRegexCacheTests.swift
//  FeedReaderTests
//
//  Tests for ContentFilterManager regex caching refactor.
//  Verifies that cached regex patterns produce correct results
//  and that cache invalidation works on filter update/remove/clear.
//

import XCTest
@testable import FeedReader

class ContentFilterRegexCacheTests: XCTestCase {

    var manager: ContentFilterManager!

    override func setUp() {
        super.setUp()
        manager = ContentFilterManager()
        manager.clearAll()
    }

    override func tearDown() {
        manager.clearAll()
        super.tearDown()
    }

    // MARK: - Helpers

    private func makeStory(title: String, body: String = "", link: String? = nil) -> Story {
        return Story(
            title: title,
            photo: nil,
            body: body,
            link: link ?? "https://example.com/\(UUID().uuidString)",
            imagePath: nil
        )
    }

    // MARK: - Exact Word Caching

    func testExactWordMatchUsesCache() {
        // First call compiles the regex; second should use cache
        let filter = ContentFilter(
            keyword: "swift",
            matchScope: .title,
            matchMode: .exactWord
        )!
        manager.addFilter(filter)

        let story1 = makeStory(title: "Learning Swift today")
        let story2 = makeStory(title: "Swift programming guide")

        // Both should match via the same cached regex
        XCTAssertTrue(manager.matchesFilter(story1, filter: filter))
        XCTAssertTrue(manager.matchesFilter(story2, filter: filter))
    }

    func testExactWordDoesNotMatchSubstring() {
        let filter = ContentFilter(
            keyword: "art",
            matchScope: .title,
            matchMode: .exactWord
        )!
        manager.addFilter(filter)

        let story = makeStory(title: "Starting something new")
        XCTAssertFalse(manager.matchesFilter(story, filter: filter))
    }

    func testExactWordMatchesStandalone() {
        let filter = ContentFilter(
            keyword: "art",
            matchScope: .title,
            matchMode: .exactWord
        )!
        manager.addFilter(filter)

        let story = makeStory(title: "Modern art exhibition")
        XCTAssertTrue(manager.matchesFilter(story, filter: filter))
    }

    // MARK: - Regex Mode Caching

    func testRegexMatchUsesCache() {
        let filter = ContentFilter(
            keyword: "\\d{4}-\\d{2}-\\d{2}",
            matchScope: .body,
            matchMode: .regex
        )!
        manager.addFilter(filter)

        let story1 = makeStory(title: "Event", body: "Date: 2026-03-03")
        let story2 = makeStory(title: "Event", body: "Published: 2025-12-31")

        // Both should match via the same cached regex
        XCTAssertTrue(manager.matchesFilter(story1, filter: filter))
        XCTAssertTrue(manager.matchesFilter(story2, filter: filter))
    }

    func testRegexNoMatchReturnsFalse() {
        let filter = ContentFilter(
            keyword: "^ERROR:",
            matchScope: .title,
            matchMode: .regex
        )!
        manager.addFilter(filter)

        let story = makeStory(title: "Warning: something happened")
        XCTAssertFalse(manager.matchesFilter(story, filter: filter))
    }

    func testRegexMatchWorks() {
        let filter = ContentFilter(
            keyword: "^ERROR:",
            matchScope: .title,
            matchMode: .regex
        )!
        manager.addFilter(filter)

        let story = makeStory(title: "ERROR: something broke")
        XCTAssertTrue(manager.matchesFilter(story, filter: filter))
    }

    // MARK: - Cache Invalidation on Update

    func testUpdateFilterInvalidatesCache() {
        let filter = ContentFilter(
            keyword: "old-keyword",
            matchScope: .title,
            matchMode: .exactWord
        )!
        manager.addFilter(filter)

        let storyOld = makeStory(title: "old-keyword in title")
        let storyNew = makeStory(title: "new-keyword in title")

        XCTAssertTrue(manager.matchesFilter(storyOld, filter: filter))

        // Update keyword — cache should be invalidated
        manager.updateFilter(
            id: filter.id,
            keyword: "new-keyword",
            matchScope: .title,
            matchMode: .exactWord
        )

        let updatedFilter = manager.getFilter(id: filter.id)!
        XCTAssertFalse(manager.matchesFilter(storyOld, filter: updatedFilter))
        XCTAssertTrue(manager.matchesFilter(storyNew, filter: updatedFilter))
    }

    // MARK: - Cache Invalidation on Remove

    func testRemoveFilterEvictsCacheEntry() {
        let filter = ContentFilter(
            keyword: "cached-pattern",
            matchScope: .title,
            matchMode: .regex
        )!
        manager.addFilter(filter)

        let story = makeStory(title: "cached-pattern test")
        XCTAssertTrue(manager.matchesFilter(story, filter: filter))

        // Remove — should not crash or affect other filters
        manager.removeFilter(id: filter.id)
        XCTAssertEqual(manager.filterCount, 0)
    }

    // MARK: - Cache Invalidation on Clear

    func testClearAllInvalidatesCache() {
        let filter1 = ContentFilter(keyword: "alpha", matchScope: .title, matchMode: .exactWord)!
        let filter2 = ContentFilter(keyword: "\\d+", matchScope: .body, matchMode: .regex)!
        manager.addFilter(filter1)
        manager.addFilter(filter2)

        // Warm the cache
        let story = makeStory(title: "alpha test", body: "has 42 items")
        _ = manager.shouldMute(story)

        // Clear all — cache should be empty
        manager.clearAll()
        XCTAssertEqual(manager.filterCount, 0)

        // Re-add same keyword — should work (cache was cleared, not stale)
        let filter3 = ContentFilter(keyword: "alpha", matchScope: .body, matchMode: .exactWord)!
        manager.addFilter(filter3)
        let bodyStory = makeStory(title: "Test", body: "alpha channel")
        XCTAssertTrue(manager.matchesFilter(bodyStory, filter: filter3))
    }

    // MARK: - Contains Mode Not Cached

    func testContainsModeStillWorks() {
        let filter = ContentFilter(keyword: "swift", matchScope: .title, matchMode: .contains)!
        manager.addFilter(filter)

        let story = makeStory(title: "Learning Swift")
        XCTAssertTrue(manager.matchesFilter(story, filter: filter))
    }

    func testContainsModeMatchesSubstring() {
        let filter = ContentFilter(keyword: "art", matchScope: .title, matchMode: .contains)!
        manager.addFilter(filter)

        let story = makeStory(title: "Starting something")
        XCTAssertTrue(manager.matchesFilter(story, filter: filter))
    }

    // MARK: - Multiple Filters

    func testMultipleFiltersCachedIndependently() {
        let f1 = ContentFilter(keyword: "swift", matchScope: .title, matchMode: .exactWord)!
        let f2 = ContentFilter(keyword: "rust", matchScope: .title, matchMode: .exactWord)!
        manager.addFilter(f1)
        manager.addFilter(f2)

        let swiftStory = makeStory(title: "Swift programming")
        let rustStory = makeStory(title: "Rust systems programming")

        // Each filter should match independently
        XCTAssertTrue(manager.matchesFilter(swiftStory, filter: f1))
        XCTAssertFalse(manager.matchesFilter(swiftStory, filter: f2))
        XCTAssertFalse(manager.matchesFilter(rustStory, filter: f1))
        XCTAssertTrue(manager.matchesFilter(rustStory, filter: f2))
    }

    // MARK: - Batch Filtering

    func testFilteredStoriesWithCache() {
        let filter = ContentFilter(keyword: "sponsored", matchScope: .title, matchMode: .contains)!
        manager.addFilter(filter)

        let stories = [
            makeStory(title: "Great article"),
            makeStory(title: "Sponsored: Buy now"),
            makeStory(title: "Another good one"),
            makeStory(title: "Sponsored content"),
        ]

        let result = manager.filteredStories(from: stories)
        XCTAssertEqual(result.count, 2) // only non-sponsored
    }

    func testMutedStoriesWithRegexCache() {
        let filter = ContentFilter(keyword: "\\[AD\\]", matchScope: .title, matchMode: .regex)!
        manager.addFilter(filter)

        let stories = [
            makeStory(title: "Normal article"),
            makeStory(title: "[AD] Buy this product"),
            makeStory(title: "[AD] Another ad"),
        ]

        let muted = manager.mutedStories(from: stories)
        XCTAssertEqual(muted.count, 2)
    }
}
