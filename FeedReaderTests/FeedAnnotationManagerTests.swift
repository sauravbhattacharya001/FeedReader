//
//  FeedAnnotationManagerTests.swift
//  FeedReaderTests
//
//  Tests for positional annotation manager.
//

import XCTest
@testable import FeedReader

final class FeedAnnotationManagerTests: XCTestCase {

    private var manager: FeedAnnotationManager!
    private var defaults: UserDefaults!

    override func setUp() {
        super.setUp()
        defaults = UserDefaults(suiteName: "FeedAnnotationManagerTests")!
        defaults.removePersistentDomain(forName: "FeedAnnotationManagerTests")
        manager = FeedAnnotationManager(userDefaults: defaults)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: "FeedAnnotationManagerTests")
        super.tearDown()
    }

    // MARK: - Add

    func testAddAnnotation() {
        let a = manager.addAnnotation(
            articleLink: "https://example.com/1",
            articleTitle: "Test Article",
            feedName: "Test Feed",
            selectedText: "important passage",
            comment: "This is key"
        )
        XCTAssertNotNil(a)
        XCTAssertEqual(manager.annotations.count, 1)
        XCTAssertEqual(a?.selectedText, "important passage")
        XCTAssertEqual(a?.comment, "This is key")
        XCTAssertEqual(a?.category, .other)
        XCTAssertFalse(a!.isResolved)
    }

    func testAddWithCategory() {
        let a = manager.addAnnotation(
            articleLink: "https://example.com/1",
            articleTitle: "Article",
            feedName: "Feed",
            selectedText: "Why does this work?",
            comment: "Need to investigate",
            category: .question
        )
        XCTAssertEqual(a?.category, .question)
    }

    func testAddWithContext() {
        let a = manager.addAnnotation(
            articleLink: "https://example.com/1",
            articleTitle: "Article",
            feedName: "Feed",
            selectedText: "key phrase",
            comment: "Interesting",
            contextBefore: "before text",
            contextAfter: "after text",
            characterOffset: 150
        )
        XCTAssertEqual(a?.contextBefore, "before text")
        XCTAssertEqual(a?.contextAfter, "after text")
        XCTAssertEqual(a?.characterOffset, 150)
    }

    func testAddRejectsEmptyArticleLink() {
        let a = manager.addAnnotation(
            articleLink: "",
            articleTitle: "Article",
            feedName: "Feed",
            selectedText: "text",
            comment: "comment"
        )
        XCTAssertNil(a)
        XCTAssertEqual(manager.annotations.count, 0)
    }

    func testAddRejectsEmptySelectedText() {
        let a = manager.addAnnotation(
            articleLink: "https://example.com/1",
            articleTitle: "Article",
            feedName: "Feed",
            selectedText: "   ",
            comment: "comment"
        )
        XCTAssertNil(a)
    }

    func testAddRejectsEmptyComment() {
        let a = manager.addAnnotation(
            articleLink: "https://example.com/1",
            articleTitle: "Article",
            feedName: "Feed",
            selectedText: "text",
            comment: "  "
        )
        XCTAssertNil(a)
    }

    func testAddTruncatesLongText() {
        let longText = String(repeating: "a", count: 2000)
        let a = manager.addAnnotation(
            articleLink: "https://example.com/1",
            articleTitle: "Article",
            feedName: "Feed",
            selectedText: longText,
            comment: longText
        )
        XCTAssertNotNil(a)
        XCTAssertEqual(a?.selectedText.count, FeedAnnotationManager.maxSelectedTextLength)
        XCTAssertEqual(a?.comment.count, FeedAnnotationManager.maxCommentLength)
    }

    func testAddTruncatesContext() {
        let longCtx = String(repeating: "b", count: 200)
        let a = manager.addAnnotation(
            articleLink: "https://example.com/1",
            articleTitle: "Article",
            feedName: "Feed",
            selectedText: "text",
            comment: "comment",
            contextBefore: longCtx,
            contextAfter: longCtx
        )
        XCTAssertEqual(a?.contextBefore.count, FeedAnnotationManager.maxContextLength)
        XCTAssertEqual(a?.contextAfter.count, FeedAnnotationManager.maxContextLength)
    }

    func testAddRespectsMaxAnnotations() {
        for i in 0..<FeedAnnotationManager.maxAnnotations {
            manager.addAnnotation(
                articleLink: "https://example.com/\(i)",
                articleTitle: "A\(i)",
                feedName: "Feed",
                selectedText: "text \(i)",
                comment: "comment \(i)"
            )
        }
        XCTAssertEqual(manager.annotations.count, FeedAnnotationManager.maxAnnotations)
        let overflow = manager.addAnnotation(
            articleLink: "https://example.com/overflow",
            articleTitle: "Overflow",
            feedName: "Feed",
            selectedText: "no room",
            comment: "sorry"
        )
        XCTAssertNil(overflow)
    }

    func testNegativeOffsetClampedToZero() {
        let a = manager.addAnnotation(
            articleLink: "https://example.com/1",
            articleTitle: "Article",
            feedName: "Feed",
            selectedText: "text",
            comment: "comment",
            characterOffset: -50
        )
        XCTAssertEqual(a?.characterOffset, 0)
    }

    // MARK: - Update

    func testUpdateComment() {
        let a = manager.addAnnotation(
            articleLink: "https://example.com/1",
            articleTitle: "Article",
            feedName: "Feed",
            selectedText: "text",
            comment: "original"
        )!
        let result = manager.updateAnnotation(id: a.id, newComment: "updated comment")
        XCTAssertTrue(result)
        XCTAssertEqual(manager.annotation(withId: a.id)?.comment, "updated comment")
    }

    func testUpdateCategory() {
        let a = manager.addAnnotation(
            articleLink: "https://example.com/1",
            articleTitle: "Article",
            feedName: "Feed",
            selectedText: "text",
            comment: "original",
            category: .other
        )!
        let result = manager.updateAnnotation(id: a.id, newCategory: .insight)
        XCTAssertTrue(result)
        XCTAssertEqual(manager.annotation(withId: a.id)?.category, .insight)
    }

    func testUpdateBothCommentAndCategory() {
        let a = manager.addAnnotation(
            articleLink: "https://example.com/1",
            articleTitle: "Article",
            feedName: "Feed",
            selectedText: "text",
            comment: "original"
        )!
        let result = manager.updateAnnotation(id: a.id, newComment: "new", newCategory: .question)
        XCTAssertTrue(result)
        let updated = manager.annotation(withId: a.id)!
        XCTAssertEqual(updated.comment, "new")
        XCTAssertEqual(updated.category, .question)
    }

    func testUpdateRejectsEmptyComment() {
        let a = manager.addAnnotation(
            articleLink: "https://example.com/1",
            articleTitle: "Article",
            feedName: "Feed",
            selectedText: "text",
            comment: "original"
        )!
        let result = manager.updateAnnotation(id: a.id, newComment: "  ")
        XCTAssertFalse(result)
        XCTAssertEqual(manager.annotation(withId: a.id)?.comment, "original")
    }

    func testUpdateNonexistentId() {
        let result = manager.updateAnnotation(id: "nonexistent", newComment: "hello")
        XCTAssertFalse(result)
    }

    func testUpdateSetsUpdatedAt() {
        let a = manager.addAnnotation(
            articleLink: "https://example.com/1",
            articleTitle: "Article",
            feedName: "Feed",
            selectedText: "text",
            comment: "original"
        )!
        let originalDate = a.updatedAt
        Thread.sleep(forTimeInterval: 0.01)
        manager.updateAnnotation(id: a.id, newCategory: .insight)
        let updated = manager.annotation(withId: a.id)!
        XCTAssertTrue(updated.updatedAt >= originalDate)
    }

    // MARK: - Toggle Resolved

    func testToggleResolved() {
        let a = manager.addAnnotation(
            articleLink: "https://example.com/1",
            articleTitle: "Article",
            feedName: "Feed",
            selectedText: "text",
            comment: "question",
            category: .question
        )!
        XCTAssertFalse(a.isResolved)
        XCTAssertTrue(manager.toggleResolved(id: a.id))
        XCTAssertTrue(manager.annotation(withId: a.id)!.isResolved)
        XCTAssertTrue(manager.toggleResolved(id: a.id))
        XCTAssertFalse(manager.annotation(withId: a.id)!.isResolved)
    }

    func testToggleResolvedNonexistent() {
        XCTAssertFalse(manager.toggleResolved(id: "nope"))
    }

    // MARK: - Remove

    func testRemoveAnnotation() {
        let a = manager.addAnnotation(
            articleLink: "https://example.com/1",
            articleTitle: "Article",
            feedName: "Feed",
            selectedText: "text",
            comment: "comment"
        )!
        XCTAssertTrue(manager.removeAnnotation(id: a.id))
        XCTAssertEqual(manager.annotations.count, 0)
    }

    func testRemoveNonexistent() {
        XCTAssertFalse(manager.removeAnnotation(id: "nope"))
    }

    func testRemoveAnnotationsForArticle() {
        manager.addAnnotation(articleLink: "https://a.com/1", articleTitle: "A1", feedName: "F", selectedText: "t1", comment: "c1")
        manager.addAnnotation(articleLink: "https://a.com/1", articleTitle: "A1", feedName: "F", selectedText: "t2", comment: "c2")
        manager.addAnnotation(articleLink: "https://a.com/2", articleTitle: "A2", feedName: "F", selectedText: "t3", comment: "c3")
        let removed = manager.removeAnnotations(forArticle: "https://a.com/1")
        XCTAssertEqual(removed, 2)
        XCTAssertEqual(manager.annotations.count, 1)
    }

    func testRemoveAllAnnotations() {
        manager.addAnnotation(articleLink: "https://a.com/1", articleTitle: "A", feedName: "F", selectedText: "t", comment: "c")
        manager.addAnnotation(articleLink: "https://a.com/2", articleTitle: "B", feedName: "F", selectedText: "t", comment: "c")
        manager.removeAllAnnotations()
        XCTAssertEqual(manager.annotations.count, 0)
    }

    func testRemoveAllOnEmpty() {
        manager.removeAllAnnotations()
        XCTAssertEqual(manager.annotations.count, 0)
    }

    // MARK: - Queries

    func testAnnotationsForArticle() {
        manager.addAnnotation(articleLink: "https://a.com/1", articleTitle: "A1", feedName: "F", selectedText: "t1", comment: "c1", characterOffset: 200)
        manager.addAnnotation(articleLink: "https://a.com/1", articleTitle: "A1", feedName: "F", selectedText: "t2", comment: "c2", characterOffset: 50)
        manager.addAnnotation(articleLink: "https://a.com/2", articleTitle: "A2", feedName: "F", selectedText: "t3", comment: "c3")

        let result = manager.annotations(forArticle: "https://a.com/1")
        XCTAssertEqual(result.count, 2)
        XCTAssertEqual(result[0].characterOffset, 50)
        XCTAssertEqual(result[1].characterOffset, 200)
    }

    func testAnnotationsForFeed() {
        manager.addAnnotation(articleLink: "https://a.com/1", articleTitle: "A1", feedName: "TechFeed", selectedText: "t", comment: "c")
        manager.addAnnotation(articleLink: "https://a.com/2", articleTitle: "A2", feedName: "NewsFeed", selectedText: "t", comment: "c")
        manager.addAnnotation(articleLink: "https://a.com/3", articleTitle: "A3", feedName: "TechFeed", selectedText: "t", comment: "c")

        let result = manager.annotations(forFeed: "TechFeed")
        XCTAssertEqual(result.count, 2)
    }

    func testAnnotationsInCategory() {
        manager.addAnnotation(articleLink: "https://a.com/1", articleTitle: "A", feedName: "F", selectedText: "t", comment: "c", category: .insight)
        manager.addAnnotation(articleLink: "https://a.com/2", articleTitle: "B", feedName: "F", selectedText: "t", comment: "c", category: .question)
        manager.addAnnotation(articleLink: "https://a.com/3", articleTitle: "C", feedName: "F", selectedText: "t", comment: "c", category: .insight)

        XCTAssertEqual(manager.annotations(inCategory: .insight).count, 2)
        XCTAssertEqual(manager.annotations(inCategory: .question).count, 1)
        XCTAssertEqual(manager.annotations(inCategory: .other).count, 0)
    }

    func testUnresolvedAnnotations() {
        let q = manager.addAnnotation(articleLink: "https://a.com/1", articleTitle: "A", feedName: "F", selectedText: "t", comment: "c", category: .question)!
        manager.addAnnotation(articleLink: "https://a.com/2", articleTitle: "B", feedName: "F", selectedText: "t", comment: "c", category: .actionItem)
        manager.addAnnotation(articleLink: "https://a.com/3", articleTitle: "C", feedName: "F", selectedText: "t", comment: "c", category: .insight)

        XCTAssertEqual(manager.unresolvedAnnotations().count, 2)
        manager.toggleResolved(id: q.id)
        XCTAssertEqual(manager.unresolvedAnnotations().count, 1)
    }

    func testSearch() {
        manager.addAnnotation(articleLink: "https://a.com/1", articleTitle: "Swift Guide", feedName: "F", selectedText: "protocol oriented", comment: "great pattern")
        manager.addAnnotation(articleLink: "https://a.com/2", articleTitle: "Rust Tutorial", feedName: "F", selectedText: "ownership model", comment: "similar to Swift")

        XCTAssertEqual(manager.search(query: "swift").count, 2)
        XCTAssertEqual(manager.search(query: "protocol").count, 1)
        XCTAssertEqual(manager.search(query: "ownership").count, 1)
        XCTAssertEqual(manager.search(query: "").count, 0)
    }

    func testSearchCaseInsensitive() {
        manager.addAnnotation(articleLink: "https://a.com/1", articleTitle: "Article", feedName: "F", selectedText: "IMPORTANT", comment: "note")
        XCTAssertEqual(manager.search(query: "important").count, 1)
    }

    func testAnnotationsInDateRange() {
        let a = manager.addAnnotation(articleLink: "https://a.com/1", articleTitle: "A", feedName: "F", selectedText: "t", comment: "c")!
        let start = a.createdAt.addingTimeInterval(-1)
        let end = a.createdAt.addingTimeInterval(1)
        XCTAssertEqual(manager.annotations(from: start, to: end).count, 1)
        XCTAssertEqual(manager.annotations(from: end, to: end.addingTimeInterval(100)).count, 0)
    }

    func testRecentlyAnnotatedArticles() {
        manager.addAnnotation(articleLink: "https://a.com/1", articleTitle: "A1", feedName: "F", selectedText: "t1", comment: "c1")
        manager.addAnnotation(articleLink: "https://a.com/1", articleTitle: "A1", feedName: "F", selectedText: "t2", comment: "c2")
        manager.addAnnotation(articleLink: "https://a.com/2", articleTitle: "A2", feedName: "F", selectedText: "t3", comment: "c3")

        let recent = manager.recentlyAnnotatedArticles(limit: 5)
        XCTAssertEqual(recent.count, 2)
        XCTAssertEqual(recent[0].count, 1)
        XCTAssertEqual(recent[1].count, 2)
    }

    // MARK: - Statistics

    func testComputeStats() {
        manager.addAnnotation(articleLink: "https://a.com/1", articleTitle: "A1", feedName: "Feed1", selectedText: "text", comment: "comment", category: .insight)
        manager.addAnnotation(articleLink: "https://a.com/1", articleTitle: "A1", feedName: "Feed1", selectedText: "text2", comment: "comment2", category: .question)
        manager.addAnnotation(articleLink: "https://a.com/2", articleTitle: "A2", feedName: "Feed2", selectedText: "text3", comment: "comment3", category: .insight)

        let stats = manager.computeStats()
        XCTAssertEqual(stats.totalAnnotations, 3)
        XCTAssertEqual(stats.totalArticlesAnnotated, 2)
        XCTAssertEqual(stats.totalFeedsAnnotated, 2)
        XCTAssertEqual(stats.categoryBreakdown[.insight], 2)
        XCTAssertEqual(stats.categoryBreakdown[.question], 1)
        XCTAssertEqual(stats.averageAnnotationsPerArticle, 1.5, accuracy: 0.01)
        XCTAssertNotNil(stats.oldestAnnotation)
        XCTAssertNotNil(stats.newestAnnotation)
        XCTAssertFalse(stats.topFeedsByAnnotations.isEmpty)
    }

    func testStatsEmpty() {
        let stats = manager.computeStats()
        XCTAssertEqual(stats.totalAnnotations, 0)
        XCTAssertEqual(stats.averageAnnotationsPerArticle, 0.0)
        XCTAssertEqual(stats.averageCommentLength, 0.0)
        XCTAssertNil(stats.oldestAnnotation)
    }

    // MARK: - Export/Import

    func testExportImportJSON() {
        manager.addAnnotation(articleLink: "https://a.com/1", articleTitle: "A1", feedName: "F", selectedText: "t1", comment: "c1", category: .insight)
        manager.addAnnotation(articleLink: "https://a.com/2", articleTitle: "A2", feedName: "F", selectedText: "t2", comment: "c2", category: .question)

        let json = manager.exportJSON()
        XCTAssertNotNil(json)

        let defaults2 = UserDefaults(suiteName: "FeedAnnotationImport")!
        defaults2.removePersistentDomain(forName: "FeedAnnotationImport")
        let manager2 = FeedAnnotationManager(userDefaults: defaults2)
        let imported = manager2.importJSON(json!)
        XCTAssertEqual(imported, 2)
        XCTAssertEqual(manager2.annotations.count, 2)

        let reimported = manager2.importJSON(json!)
        XCTAssertEqual(reimported, 0)

        defaults2.removePersistentDomain(forName: "FeedAnnotationImport")
    }

    func testImportInvalidJSON() {
        let bad = "not json".data(using: .utf8)!
        let imported = manager.importJSON(bad)
        XCTAssertEqual(imported, 0)
    }

    func testExportText() {
        manager.addAnnotation(articleLink: "https://a.com/1", articleTitle: "Test Article", feedName: "Tech Feed", selectedText: "important passage", comment: "Great insight here", category: .insight)
        let text = manager.exportText()
        XCTAssertTrue(text.contains("Annotations Export"))
        XCTAssertTrue(text.contains("Test Article"))
        XCTAssertTrue(text.contains("important passage"))
        XCTAssertTrue(text.contains("Great insight here"))
        XCTAssertTrue(text.contains("Tech Feed"))
    }

    // MARK: - Persistence

    func testPersistence() {
        manager.addAnnotation(articleLink: "https://a.com/1", articleTitle: "A", feedName: "F", selectedText: "t", comment: "c")
        let manager2 = FeedAnnotationManager(userDefaults: defaults)
        XCTAssertEqual(manager2.annotations.count, 1)
        XCTAssertEqual(manager2.annotations[0].selectedText, "t")
    }

    // MARK: - Notification

    func testNotificationPosted() {
        let expectation = XCTestExpectation(description: "Notification posted")
        let observer = NotificationCenter.default.addObserver(
            forName: .feedAnnotationsDidChange,
            object: nil,
            queue: nil
        ) { _ in expectation.fulfill() }
        manager.addAnnotation(articleLink: "https://a.com/1", articleTitle: "A", feedName: "F", selectedText: "t", comment: "c")
        wait(for: [expectation], timeout: 1.0)
        NotificationCenter.default.removeObserver(observer)
    }

    // MARK: - Categories

    func testAllCategoriesHaveEmojis() {
        for cat in FeedAnnotationManager.AnnotationCategory.allCases {
            XCTAssertFalse(cat.emoji.isEmpty, "\(cat) missing emoji")
            XCTAssertFalse(cat.label.isEmpty, "\(cat) missing label")
        }
    }

    func testCategoryCount() {
        XCTAssertEqual(FeedAnnotationManager.AnnotationCategory.allCases.count, 10)
    }
}
