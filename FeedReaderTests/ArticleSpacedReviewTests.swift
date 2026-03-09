//
//  ArticleSpacedReviewTests.swift
//  FeedReaderTests
//
//  Tests for the spaced repetition review system.
//

import XCTest
@testable import FeedReader

class ArticleSpacedReviewTests: XCTestCase {

    var sut: ArticleSpacedReview!
    let now = Date()

    override func setUp() {
        super.setUp()
        sut = ArticleSpacedReview()
        sut.clearAll()
    }

    override func tearDown() {
        sut.clearAll()
        super.tearDown()
    }

    // MARK: - Add Item

    func testAddItem_CreatesReviewItem() {
        let item = sut.addItem(link: "https://example.com/1",
                               title: "Test Article",
                               feedName: "Test Feed",
                               keyPoints: "Key concept here")
        XCTAssertNotNil(item)
        XCTAssertEqual(item?.articleLink, "https://example.com/1")
        XCTAssertEqual(item?.articleTitle, "Test Article")
        XCTAssertEqual(item?.feedName, "Test Feed")
        XCTAssertEqual(item?.keyPoints, "Key concept here")
        XCTAssertEqual(item?.intervalLevel, 0)
        XCTAssertEqual(item?.reviewCount, 0)
        XCTAssertEqual(item?.successCount, 0)
        XCTAssertFalse(item?.isFlagged ?? true)
        XCTAssertFalse(item?.isMastered ?? true)
    }

    func testAddItem_DuplicateReturnsNil() {
        sut.addItem(link: "https://example.com/1", title: "A",
                    feedName: "F", keyPoints: "P")
        let dup = sut.addItem(link: "https://example.com/1", title: "B",
                              feedName: "F", keyPoints: "P")
        XCTAssertNil(dup)
    }

    func testAddItem_EmptyLinkReturnsNil() {
        let item = sut.addItem(link: "", title: "A",
                               feedName: "F", keyPoints: "P")
        XCTAssertNil(item)
    }

    func testAddItem_FlaggedItem() {
        let item = sut.addItem(link: "https://example.com/1",
                               title: "A", feedName: "F",
                               keyPoints: "P", flagged: true)
        XCTAssertTrue(item?.isFlagged ?? false)
    }

    func testAddItem_SetsNextReviewTo1Day() {
        let item = sut.addItem(link: "https://example.com/1",
                               title: "A", feedName: "F", keyPoints: "P")
        let expected = Date().addingTimeInterval(86400)
        // Allow 5 second tolerance
        XCTAssertEqual(item!.nextReviewDate.timeIntervalSince1970,
                       expected.timeIntervalSince1970, accuracy: 5)
    }

    // MARK: - Remove Item

    func testRemoveItem_ReturnsTrue() {
        sut.addItem(link: "https://example.com/1", title: "A",
                    feedName: "F", keyPoints: "P")
        XCTAssertTrue(sut.removeItem(link: "https://example.com/1"))
        XCTAssertEqual(sut.count, 0)
    }

    func testRemoveItem_NonexistentReturnsFalse() {
        XCTAssertFalse(sut.removeItem(link: "nope"))
    }

    // MARK: - Update & Toggle

    func testUpdateKeyPoints() {
        sut.addItem(link: "https://example.com/1", title: "A",
                    feedName: "F", keyPoints: "Old")
        sut.updateKeyPoints(link: "https://example.com/1", keyPoints: "New")
        let item = sut.getItem(link: "https://example.com/1")
        XCTAssertEqual(item?.keyPoints, "New")
    }

    func testToggleFlag() {
        sut.addItem(link: "https://example.com/1", title: "A",
                    feedName: "F", keyPoints: "P")
        XCTAssertFalse(sut.getItem(link: "https://example.com/1")!.isFlagged)
        sut.toggleFlag(link: "https://example.com/1")
        XCTAssertTrue(sut.getItem(link: "https://example.com/1")!.isFlagged)
        sut.toggleFlag(link: "https://example.com/1")
        XCTAssertFalse(sut.getItem(link: "https://example.com/1")!.isFlagged)
    }

    // MARK: - Due Items

    func testDueItems_NewItemNotDue() {
        sut.addItem(link: "https://example.com/1", title: "A",
                    feedName: "F", keyPoints: "P")
        let due = sut.dueItems(at: now)
        XCTAssertTrue(due.isEmpty)
    }

    func testDueItems_ItemDueAfter1Day() {
        sut.addItem(link: "https://example.com/1", title: "A",
                    feedName: "F", keyPoints: "P")
        let tomorrow = now.addingTimeInterval(86400 + 60) // 1 day + 1 min
        let due = sut.dueItems(at: tomorrow)
        XCTAssertEqual(due.count, 1)
        XCTAssertEqual(due.first?.articleLink, "https://example.com/1")
    }

    func testDueItems_FlaggedItemsFirst() {
        sut.addItem(link: "https://example.com/1", title: "Normal",
                    feedName: "F", keyPoints: "P")
        sut.addItem(link: "https://example.com/2", title: "Flagged",
                    feedName: "F", keyPoints: "P", flagged: true)
        let future = now.addingTimeInterval(86400 * 2)
        let due = sut.dueItems(at: future)
        XCTAssertEqual(due.count, 2)
        XCTAssertEqual(due.first?.articleTitle, "Flagged")
    }

    func testDueCount() {
        sut.addItem(link: "https://example.com/1", title: "A",
                    feedName: "F", keyPoints: "P")
        sut.addItem(link: "https://example.com/2", title: "B",
                    feedName: "F", keyPoints: "P")
        XCTAssertEqual(sut.dueCount(at: now), 0)
        let future = now.addingTimeInterval(86400 * 2)
        XCTAssertEqual(sut.dueCount(at: future), 2)
    }

    // MARK: - Upcoming Items

    func testUpcomingItems() {
        sut.addItem(link: "https://example.com/1", title: "A",
                    feedName: "F", keyPoints: "P")
        // Due in 1 day, so should appear in upcoming 2-day window
        let upcoming = sut.upcomingItems(withinDays: 2, from: now)
        XCTAssertEqual(upcoming.count, 1)
    }

    // MARK: - Record Review

    func testRecordReview_Good_AdvancesLevel() {
        sut.addItem(link: "https://example.com/1", title: "A",
                    feedName: "F", keyPoints: "P")
        let reviewDate = now.addingTimeInterval(86400 * 2)
        let updated = sut.recordReview(link: "https://example.com/1",
                                       quality: .good, at: reviewDate)
        XCTAssertNotNil(updated)
        XCTAssertEqual(updated?.intervalLevel, 1) // 0 → 1
        XCTAssertEqual(updated?.reviewCount, 1)
        XCTAssertEqual(updated?.successCount, 1)
        XCTAssertEqual(updated?.reviewHistory.count, 1)
    }

    func testRecordReview_Easy_SkipsTwoLevels() {
        sut.addItem(link: "https://example.com/1", title: "A",
                    feedName: "F", keyPoints: "P")
        let updated = sut.recordReview(link: "https://example.com/1",
                                       quality: .easy, at: now)
        XCTAssertEqual(updated?.intervalLevel, 2) // 0 → 2
    }

    func testRecordReview_Hard_StaysSameLevel() {
        sut.addItem(link: "https://example.com/1", title: "A",
                    feedName: "F", keyPoints: "P")
        let updated = sut.recordReview(link: "https://example.com/1",
                                       quality: .hard, at: now)
        XCTAssertEqual(updated?.intervalLevel, 0)
        XCTAssertEqual(updated?.successCount, 0) // hard is not a success
    }

    func testRecordReview_Forgot_ResetsToLevel0() {
        sut.addItem(link: "https://example.com/1", title: "A",
                    feedName: "F", keyPoints: "P")
        // Advance to level 2
        sut.recordReview(link: "https://example.com/1",
                         quality: .easy, at: now)
        // Then forget
        let updated = sut.recordReview(link: "https://example.com/1",
                                       quality: .forgot,
                                       at: now.addingTimeInterval(86400 * 8))
        XCTAssertEqual(updated?.intervalLevel, 0) // Reset
    }

    func testRecordReview_NonexistentReturnsNil() {
        let result = sut.recordReview(link: "nope", quality: .good)
        XCTAssertNil(result)
    }

    func testRecordReview_MaxLevel_Mastered() {
        sut.addItem(link: "https://example.com/1", title: "A",
                    feedName: "F", keyPoints: "P")
        // Fast-track to max level with easy reviews
        var date = now
        for _ in 0..<10 {
            sut.recordReview(link: "https://example.com/1",
                             quality: .easy, at: date)
            date = date.addingTimeInterval(86400 * 100)
        }
        let item = sut.getItem(link: "https://example.com/1")
        XCTAssertTrue(item?.isMastered ?? false)
        XCTAssertEqual(item?.intervalLevel, ArticleSpacedReview.maxLevel)
    }

    // MARK: - Complete Session

    func testCompleteSession_ReturnsStats() {
        sut.addItem(link: "https://example.com/1", title: "A",
                    feedName: "F", keyPoints: "P")
        sut.addItem(link: "https://example.com/2", title: "B",
                    feedName: "F", keyPoints: "P")
        sut.addItem(link: "https://example.com/3", title: "C",
                    feedName: "F", keyPoints: "P")

        let reviews: [(link: String, quality: ReviewQuality)] = [
            ("https://example.com/1", .easy),
            ("https://example.com/2", .good),
            ("https://example.com/3", .forgot),
        ]

        let stats = sut.completeSession(reviews: reviews, at: now)
        XCTAssertEqual(stats.totalReviewed, 3)
        XCTAssertEqual(stats.easyCount, 1)
        XCTAssertEqual(stats.goodCount, 1)
        XCTAssertEqual(stats.forgotCount, 1)
        XCTAssertEqual(stats.retentionRate, 2.0 / 3.0, accuracy: 0.01)
    }

    // MARK: - Statistics

    func testGetStats_Empty() {
        let stats = sut.getStats()
        XCTAssertEqual(stats.totalItems, 0)
        XCTAssertEqual(stats.masteredItems, 0)
        XCTAssertEqual(stats.totalReviews, 0)
        XCTAssertEqual(stats.currentStreak, 0)
    }

    func testGetStats_WithItems() {
        sut.addItem(link: "https://example.com/1", title: "A",
                    feedName: "Feed A", keyPoints: "P")
        sut.addItem(link: "https://example.com/2", title: "B",
                    feedName: "Feed B", keyPoints: "P")
        sut.recordReview(link: "https://example.com/1",
                         quality: .good, at: now)

        let stats = sut.getStats(at: now)
        XCTAssertEqual(stats.totalItems, 2)
        XCTAssertEqual(stats.totalReviews, 1)
        XCTAssertEqual(stats.overallRetentionRate, 1.0) // 1 success / 1 review
        XCTAssertEqual(stats.itemsByFeed.count, 2)
    }

    // MARK: - Search

    func testSearch_ByTitle() {
        sut.addItem(link: "https://example.com/1", title: "Swift Programming",
                    feedName: "F", keyPoints: "P")
        sut.addItem(link: "https://example.com/2", title: "Python Guide",
                    feedName: "F", keyPoints: "P")
        let results = sut.search(query: "swift")
        XCTAssertEqual(results.count, 1)
        XCTAssertEqual(results.first?.articleTitle, "Swift Programming")
    }

    func testSearch_ByFeedName() {
        sut.addItem(link: "https://example.com/1", title: "A",
                    feedName: "Tech Blog", keyPoints: "P")
        let results = sut.search(query: "tech")
        XCTAssertEqual(results.count, 1)
    }

    func testSearch_ByKeyPoints() {
        sut.addItem(link: "https://example.com/1", title: "A",
                    feedName: "F", keyPoints: "memory management is key")
        let results = sut.search(query: "memory")
        XCTAssertEqual(results.count, 1)
    }

    func testSearch_EmptyQuery_ReturnsAll() {
        sut.addItem(link: "https://example.com/1", title: "A",
                    feedName: "F", keyPoints: "P")
        sut.addItem(link: "https://example.com/2", title: "B",
                    feedName: "F", keyPoints: "P")
        XCTAssertEqual(sut.search(query: "").count, 2)
    }

    // MARK: - Export

    func testExportJSON_NotEmpty() {
        sut.addItem(link: "https://example.com/1", title: "A",
                    feedName: "F", keyPoints: "P")
        let json = sut.exportJSON()
        XCTAssertTrue(json.contains("example.com"))
        XCTAssertTrue(json.contains("articleLink"))
    }

    func testExportSummary_ContainsStats() {
        sut.addItem(link: "https://example.com/1", title: "A",
                    feedName: "F", keyPoints: "P")
        let summary = sut.exportSummary()
        XCTAssertTrue(summary.contains("Total items: 1"))
        XCTAssertTrue(summary.contains("Spaced Review Summary"))
    }

    // MARK: - Bulk Operations

    func testClearMastered() {
        sut.addItem(link: "https://example.com/1", title: "A",
                    feedName: "F", keyPoints: "P")
        // Fast-track to mastery
        var date = now
        for _ in 0..<10 {
            sut.recordReview(link: "https://example.com/1",
                             quality: .easy, at: date)
            date = date.addingTimeInterval(86400 * 100)
        }
        sut.addItem(link: "https://example.com/2", title: "B",
                    feedName: "F", keyPoints: "P")

        let cleared = sut.clearMastered()
        XCTAssertEqual(cleared, 1)
        XCTAssertEqual(sut.count, 1)
        XCTAssertNotNil(sut.getItem(link: "https://example.com/2"))
    }

    func testClearAll() {
        sut.addItem(link: "https://example.com/1", title: "A",
                    feedName: "F", keyPoints: "P")
        sut.addItem(link: "https://example.com/2", title: "B",
                    feedName: "F", keyPoints: "P")
        sut.clearAll()
        XCTAssertEqual(sut.count, 0)
    }

    // MARK: - Streaks

    func testCurrentStreak_NoReviews_Zero() {
        XCTAssertEqual(sut.currentStreak(), 0)
    }

    func testCurrentStreak_ReviewToday_One() {
        sut.addItem(link: "https://example.com/1", title: "A",
                    feedName: "F", keyPoints: "P")
        sut.recordReview(link: "https://example.com/1",
                         quality: .good, at: now)
        XCTAssertEqual(sut.currentStreak(at: now), 1)
    }

    func testCurrentStreak_ConsecutiveDays() {
        sut.addItem(link: "https://example.com/1", title: "A",
                    feedName: "F", keyPoints: "P")
        // Review 3 consecutive days
        for day in 0..<3 {
            let date = now.addingTimeInterval(Double(day) * 86400)
            sut.recordReview(link: "https://example.com/1",
                             quality: .good, at: date)
        }
        let day3 = now.addingTimeInterval(2 * 86400)
        XCTAssertEqual(sut.currentStreak(at: day3), 3)
    }

    // MARK: - Interval Schedule

    func testIntervalSchedule_HasExpectedLevels() {
        XCTAssertEqual(ArticleSpacedReview.intervalSchedule.count, 7)
        XCTAssertEqual(ArticleSpacedReview.intervalSchedule[0], 1)   // 1 day
        XCTAssertEqual(ArticleSpacedReview.intervalSchedule[1], 3)   // 3 days
        XCTAssertEqual(ArticleSpacedReview.intervalSchedule[2], 7)   // 1 week
        XCTAssertEqual(ArticleSpacedReview.intervalSchedule[6], 90)  // 3 months
    }

    // MARK: - Review Quality

    func testReviewQuality_Descriptions() {
        XCTAssertEqual(ReviewQuality.forgot.description, "Forgot")
        XCTAssertEqual(ReviewQuality.easy.description, "Easy")
    }

    func testReviewQuality_IntervalMultipliers() {
        XCTAssertEqual(ReviewQuality.forgot.intervalMultiplier, 0.0)
        XCTAssertEqual(ReviewQuality.good.intervalMultiplier, 1.0)
        XCTAssertEqual(ReviewQuality.easy.intervalMultiplier, 1.5)
    }

    // MARK: - AllItems Sorting

    func testAllItems_SortedByNextReview() {
        sut.addItem(link: "https://example.com/1", title: "A",
                    feedName: "F", keyPoints: "P")
        // Advance first item so its next review is further out
        sut.recordReview(link: "https://example.com/1",
                         quality: .easy, at: now)
        sut.addItem(link: "https://example.com/2", title: "B",
                    feedName: "F", keyPoints: "P")

        let all = sut.allItems()
        XCTAssertEqual(all.count, 2)
        // Second item (newly added, 1-day interval) should come first
        XCTAssertEqual(all.first?.articleLink, "https://example.com/2")
    }

    // MARK: - Count

    func testCount() {
        XCTAssertEqual(sut.count, 0)
        sut.addItem(link: "https://example.com/1", title: "A",
                    feedName: "F", keyPoints: "P")
        XCTAssertEqual(sut.count, 1)
        sut.addItem(link: "https://example.com/2", title: "B",
                    feedName: "F", keyPoints: "P")
        XCTAssertEqual(sut.count, 2)
    }
}
