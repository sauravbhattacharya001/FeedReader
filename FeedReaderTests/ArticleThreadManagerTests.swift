//
//  ArticleThreadManagerTests.swift
//  FeedReaderTests
//
//  Tests for ArticleThreadManager — story thread CRUD, auto-matching,
//  timeline generation, staleness detection, queries, and export.
//

import XCTest
@testable import FeedReader

class ArticleThreadManagerTests: XCTestCase {

    var manager: ArticleThreadManager!

    override func setUp() {
        super.setUp()
        manager = ArticleThreadManager.shared
        // Clear any persisted threads
        for thread in manager.threads {
            manager.deleteThread(id: thread.id)
        }
    }

    override func tearDown() {
        // Clean up
        for thread in manager.threads {
            manager.deleteThread(id: thread.id)
        }
        super.tearDown()
    }

    // MARK: - Thread Creation

    func testCreateThread() {
        let thread = manager.createThread(title: "2026 Election", keywords: ["election", "vote", "candidate"])
        XCTAssertEqual(thread.title, "2026 Election")
        XCTAssertEqual(thread.keywords, ["election", "vote", "candidate"])
        XCTAssertEqual(thread.status, .active)
        XCTAssertTrue(thread.entries.isEmpty)
        XCTAssertEqual(manager.threads.count, 1)
    }

    func testCreateThreadLowercasesKeywords() {
        let thread = manager.createThread(title: "Test", keywords: ["AI", "Machine", "LEARNING"])
        XCTAssertEqual(thread.keywords, ["ai", "machine", "learning"])
    }

    func testCreateThreadWithColorTag() {
        let thread = manager.createThread(title: "Test", keywords: ["test"], colorTag: "#FF5733")
        XCTAssertEqual(thread.colorTag, "#FF5733")
    }

    func testCreateMultipleThreads() {
        manager.createThread(title: "Thread A", keywords: ["a"])
        manager.createThread(title: "Thread B", keywords: ["b"])
        manager.createThread(title: "Thread C", keywords: ["c"])
        XCTAssertEqual(manager.threads.count, 3)
    }

    func testThreadHasUniqueId() {
        let t1 = manager.createThread(title: "T1", keywords: ["a"])
        let t2 = manager.createThread(title: "T2", keywords: ["b"])
        XCTAssertNotEqual(t1.id, t2.id)
    }

    // MARK: - Thread Deletion

    func testDeleteThread() {
        let thread = manager.createThread(title: "Deletable", keywords: ["test"])
        XCTAssertEqual(manager.threads.count, 1)
        manager.deleteThread(id: thread.id)
        XCTAssertEqual(manager.threads.count, 0)
    }

    func testDeleteNonexistentThreadNoOp() {
        manager.createThread(title: "Keep", keywords: ["keep"])
        manager.deleteThread(id: "nonexistent-id")
        XCTAssertEqual(manager.threads.count, 1)
    }

    // MARK: - Status Updates

    func testUpdateStatus() {
        let thread = manager.createThread(title: "Status Test", keywords: ["test"])
        manager.updateStatus(threadId: thread.id, status: .archived)
        let updated = manager.threads.first { $0.id == thread.id }
        XCTAssertEqual(updated?.status, .archived)
    }

    func testUpdateStatusToResolved() {
        let thread = manager.createThread(title: "Resolved", keywords: ["done"])
        manager.updateStatus(threadId: thread.id, status: .resolved)
        let updated = manager.threads.first { $0.id == thread.id }
        XCTAssertEqual(updated?.status, .resolved)
    }

    func testUpdateStatusNonexistentThreadNoOp() {
        manager.updateStatus(threadId: "fake-id", status: .stale)
        // No crash, no effect
        XCTAssertTrue(manager.threads.isEmpty)
    }

    // MARK: - Renaming

    func testRenameThread() {
        let thread = manager.createThread(title: "Old Name", keywords: ["test"])
        manager.renameThread(threadId: thread.id, newTitle: "New Name")
        let updated = manager.threads.first { $0.id == thread.id }
        XCTAssertEqual(updated?.title, "New Name")
    }

    // MARK: - Keyword Updates

    func testUpdateKeywords() {
        let thread = manager.createThread(title: "KW", keywords: ["old"])
        manager.updateKeywords(threadId: thread.id, keywords: ["New", "Words"])
        let updated = manager.threads.first { $0.id == thread.id }
        XCTAssertEqual(updated?.keywords, ["new", "words"])
    }

    // MARK: - Adding Articles

    func testAddArticle() {
        let thread = manager.createThread(title: "AI News", keywords: ["ai", "machine learning"])
        let added = manager.addArticle(
            toThread: thread.id,
            title: "AI breakthrough in machine learning",
            link: "https://example.com/article1",
            feedSource: "TechFeed"
        )
        XCTAssertTrue(added)
        let updated = manager.threads.first { $0.id == thread.id }
        XCTAssertEqual(updated?.entries.count, 1)
        XCTAssertEqual(updated?.entries.first?.title, "AI breakthrough in machine learning")
        XCTAssertEqual(updated?.entries.first?.feedSource, "TechFeed")
    }

    func testAddArticleWithNote() {
        let thread = manager.createThread(title: "Notes", keywords: ["test"])
        manager.addArticle(
            toThread: thread.id,
            title: "Article",
            link: "https://example.com/a",
            feedSource: "Feed",
            note: "Important context"
        )
        let entry = manager.threads.first { $0.id == thread.id }?.entries.first
        XCTAssertEqual(entry?.note, "Important context")
    }

    func testAddArticlePreventsDuplicates() {
        let thread = manager.createThread(title: "Dedup", keywords: ["test"])
        let first = manager.addArticle(
            toThread: thread.id, title: "Article", link: "https://example.com/dup", feedSource: "Feed"
        )
        let second = manager.addArticle(
            toThread: thread.id, title: "Article Again", link: "https://example.com/dup", feedSource: "Feed2"
        )
        XCTAssertTrue(first)
        XCTAssertFalse(second)
        let updated = manager.threads.first { $0.id == thread.id }
        XCTAssertEqual(updated?.entries.count, 1)
    }

    func testAddArticleToNonexistentThread() {
        let result = manager.addArticle(
            toThread: "fake", title: "X", link: "https://example.com/x", feedSource: "F"
        )
        XCTAssertFalse(result)
    }

    func testAddArticleReactivatesStaleThread() {
        let thread = manager.createThread(title: "Stale", keywords: ["test"])
        manager.updateStatus(threadId: thread.id, status: .stale)
        manager.addArticle(
            toThread: thread.id, title: "New", link: "https://example.com/new", feedSource: "Feed"
        )
        let updated = manager.threads.first { $0.id == thread.id }
        XCTAssertEqual(updated?.status, .active)
    }

    func testAddArticleRelevanceScoreComputed() {
        let thread = manager.createThread(title: "AI", keywords: ["ai", "neural", "deep"])
        manager.addArticle(
            toThread: thread.id,
            title: "AI neural network breakthrough using deep learning",
            link: "https://example.com/ai",
            feedSource: "Feed"
        )
        let entry = manager.threads.first { $0.id == thread.id }?.entries.first
        XCTAssertNotNil(entry)
        XCTAssertGreaterThan(entry!.relevanceScore, 0.0)
    }

    // MARK: - Remove Article

    func testRemoveArticle() {
        let thread = manager.createThread(title: "Remove", keywords: ["test"])
        manager.addArticle(toThread: thread.id, title: "A", link: "https://example.com/a", feedSource: "F")
        manager.addArticle(toThread: thread.id, title: "B", link: "https://example.com/b", feedSource: "F")
        XCTAssertEqual(manager.threads.first { $0.id == thread.id }?.entries.count, 2)
        manager.removeArticle(fromThread: thread.id, link: "https://example.com/a")
        XCTAssertEqual(manager.threads.first { $0.id == thread.id }?.entries.count, 1)
        XCTAssertEqual(manager.threads.first { $0.id == thread.id }?.entries.first?.link, "https://example.com/b")
    }

    // MARK: - Auto-Matching

    func testFindMatches() {
        let thread = manager.createThread(title: "Election", keywords: ["election", "vote", "campaign"])
        let suggestions = manager.findMatches(
            title: "Voters head to polls in key election campaign",
            link: "https://example.com/election",
            feedSource: "NewsFeed"
        )
        XCTAssertFalse(suggestions.isEmpty)
        if case .addToThread(let threadId, _) = suggestions.first?.kind {
            XCTAssertEqual(threadId, thread.id)
        } else {
            XCTFail("Expected addToThread suggestion")
        }
    }

    func testFindMatchesNoMatch() {
        manager.createThread(title: "AI", keywords: ["artificial", "intelligence", "neural"])
        let suggestions = manager.findMatches(
            title: "Best pizza restaurants in Seattle",
            link: "https://example.com/pizza",
            feedSource: "FoodFeed"
        )
        XCTAssertTrue(suggestions.isEmpty)
    }

    func testFindMatchesSkipsAlreadyAdded() {
        let thread = manager.createThread(title: "AI", keywords: ["ai"])
        manager.addArticle(toThread: thread.id, title: "AI News", link: "https://example.com/ai", feedSource: "Feed")
        let suggestions = manager.findMatches(
            title: "AI breakthroughs", link: "https://example.com/ai", feedSource: "Feed"
        )
        XCTAssertTrue(suggestions.isEmpty)
    }

    func testFindMatchesOnlyActive() {
        let thread = manager.createThread(title: "Test", keywords: ["test", "testing", "tests"])
        manager.updateStatus(threadId: thread.id, status: .archived)
        let suggestions = manager.findMatches(
            title: "Test results from testing suite", link: "https://example.com/test", feedSource: "Feed"
        )
        XCTAssertTrue(suggestions.isEmpty)
    }

    func testAutoMatch() {
        let thread = manager.createThread(title: "AI", keywords: ["ai", "artificial", "intelligence", "neural", "learning"])
        let matched = manager.autoMatch(
            title: "ai artificial intelligence neural learning breakthrough",
            link: "https://example.com/ai",
            feedSource: "Feed",
            threshold: 0.3
        )
        XCTAssertTrue(matched.contains(thread.id))
        XCTAssertEqual(manager.threads.first { $0.id == thread.id }?.entries.count, 1)
    }

    func testAutoMatchBelowThreshold() {
        manager.createThread(title: "Science", keywords: ["physics", "chemistry", "biology", "research"])
        let matched = manager.autoMatch(
            title: "Physics experiment results",
            link: "https://example.com/phys",
            feedSource: "Feed",
            threshold: 0.9  // Very high threshold
        )
        XCTAssertTrue(matched.isEmpty)
    }

    // MARK: - Timeline

    func testGenerateTimeline() {
        let thread = manager.createThread(title: "Timeline", keywords: ["test"])
        manager.addArticle(toThread: thread.id, title: "Day 1 Article", link: "https://example.com/d1", feedSource: "Feed")
        manager.addArticle(toThread: thread.id, title: "Day 1 Another", link: "https://example.com/d1b", feedSource: "Feed2")

        let timeline = manager.generateTimeline(threadId: thread.id)
        XCTAssertNotNil(timeline)
        XCTAssertEqual(timeline?.threadTitle, "Timeline")
        XCTAssertEqual(timeline?.totalArticles, 2)
        XCTAssertGreaterThanOrEqual(timeline?.segments.count ?? 0, 1)
    }

    func testGenerateTimelineEmptyThread() {
        let thread = manager.createThread(title: "Empty", keywords: ["test"])
        let timeline = manager.generateTimeline(threadId: thread.id)
        XCTAssertNil(timeline)
    }

    func testGenerateTimelineNonexistentThread() {
        let timeline = manager.generateTimeline(threadId: "nonexistent")
        XCTAssertNil(timeline)
    }

    // MARK: - Queries

    func testActiveThreads() {
        let t1 = manager.createThread(title: "Active", keywords: ["a"])
        manager.createThread(title: "Archived", keywords: ["b"])
        manager.updateStatus(threadId: manager.threads.last!.id, status: .archived)

        let active = manager.activeThreads()
        XCTAssertEqual(active.count, 1)
        XCTAssertEqual(active.first?.id, t1.id)
    }

    func testThreadsContaining() {
        let t1 = manager.createThread(title: "T1", keywords: ["a"])
        let t2 = manager.createThread(title: "T2", keywords: ["b"])
        manager.addArticle(toThread: t1.id, title: "Shared", link: "https://example.com/shared", feedSource: "F")
        manager.addArticle(toThread: t2.id, title: "Shared", link: "https://example.com/shared", feedSource: "F")

        let containing = manager.threadsContaining(link: "https://example.com/shared")
        XCTAssertEqual(containing.count, 2)
    }

    func testThreadsContainingNoMatch() {
        manager.createThread(title: "T", keywords: ["x"])
        let containing = manager.threadsContaining(link: "https://example.com/nope")
        XCTAssertTrue(containing.isEmpty)
    }

    func testSearchThreadsByTitle() {
        manager.createThread(title: "Climate Change Coverage", keywords: ["climate"])
        manager.createThread(title: "AI Research", keywords: ["ai"])

        let results = manager.searchThreads(query: "climate")
        XCTAssertEqual(results.count, 1)
        XCTAssertEqual(results.first?.title, "Climate Change Coverage")
    }

    func testSearchThreadsByKeyword() {
        manager.createThread(title: "Tech", keywords: ["blockchain", "crypto"])
        let results = manager.searchThreads(query: "blockchain")
        XCTAssertEqual(results.count, 1)
    }

    func testSearchThreadsCaseInsensitive() {
        manager.createThread(title: "AI News", keywords: ["ai"])
        let results = manager.searchThreads(query: "AI NEWS")
        XCTAssertEqual(results.count, 1)
    }

    // MARK: - Statistics

    func testStatisticsEmpty() {
        let stats = manager.statistics()
        XCTAssertEqual(stats.active, 0)
        XCTAssertEqual(stats.stale, 0)
        XCTAssertEqual(stats.archived, 0)
        XCTAssertEqual(stats.totalArticles, 0)
        XCTAssertEqual(stats.avgArticlesPerThread, 0.0)
    }

    func testStatistics() {
        let t1 = manager.createThread(title: "Active", keywords: ["a"])
        manager.addArticle(toThread: t1.id, title: "A1", link: "https://example.com/1", feedSource: "F")
        manager.addArticle(toThread: t1.id, title: "A2", link: "https://example.com/2", feedSource: "F")

        let t2 = manager.createThread(title: "Archived", keywords: ["b"])
        manager.addArticle(toThread: t2.id, title: "A3", link: "https://example.com/3", feedSource: "F")
        manager.updateStatus(threadId: t2.id, status: .archived)

        let stats = manager.statistics()
        XCTAssertEqual(stats.active, 1)
        XCTAssertEqual(stats.archived, 1)
        XCTAssertEqual(stats.totalArticles, 3)
        XCTAssertEqual(stats.avgArticlesPerThread, 1.5)
    }

    // MARK: - Thread Properties

    func testFeedCount() {
        let thread = manager.createThread(title: "Multi-Feed", keywords: ["test"])
        manager.addArticle(toThread: thread.id, title: "A", link: "https://example.com/a", feedSource: "Feed1")
        manager.addArticle(toThread: thread.id, title: "B", link: "https://example.com/b", feedSource: "Feed2")
        manager.addArticle(toThread: thread.id, title: "C", link: "https://example.com/c", feedSource: "Feed1")

        let updated = manager.threads.first { $0.id == thread.id }!
        XCTAssertEqual(updated.feedCount, 2)
    }

    func testTimeSpanDescription() {
        let thread = StoryThread(
            id: "test",
            title: "Test",
            keywords: [],
            entries: [],
            status: .active,
            createdDate: Date(),
            lastUpdatedDate: Date()
        )
        XCTAssertEqual(thread.timeSpanDescription, "No articles")
    }

    // MARK: - Export as Markdown

    func testExportAsMarkdown() {
        let thread = manager.createThread(title: "Export Test", keywords: ["export", "test"])
        manager.addArticle(
            toThread: thread.id,
            title: "First Article",
            link: "https://example.com/first",
            feedSource: "TestFeed"
        )

        let md = manager.exportAsMarkdown(threadId: thread.id)
        XCTAssertNotNil(md)
        XCTAssertTrue(md!.contains("# Export Test"))
        XCTAssertTrue(md!.contains("First Article"))
        XCTAssertTrue(md!.contains("https://example.com/first"))
        XCTAssertTrue(md!.contains("export, test"))
    }

    func testExportAsMarkdownWithNote() {
        let thread = manager.createThread(title: "Notes", keywords: ["test"])
        manager.addArticle(
            toThread: thread.id,
            title: "Noted Article",
            link: "https://example.com/noted",
            feedSource: "Feed",
            note: "Key development"
        )

        let md = manager.exportAsMarkdown(threadId: thread.id)
        XCTAssertNotNil(md)
        XCTAssertTrue(md!.contains("Key development"))
    }

    func testExportAsMarkdownNonexistent() {
        let md = manager.exportAsMarkdown(threadId: "nonexistent")
        XCTAssertNil(md)
    }

    // MARK: - ThreadEntry Equality

    func testThreadEntryEquality() {
        let e1 = ThreadEntry(title: "A", link: "https://a.com", feedSource: "F", addedDate: Date(), relevanceScore: 0.5)
        let e2 = ThreadEntry(title: "B", link: "https://a.com", feedSource: "G", addedDate: Date(), relevanceScore: 0.9)
        // Equality is based on link only
        XCTAssertEqual(e1, e2)
    }

    func testThreadEntryInequality() {
        let e1 = ThreadEntry(title: "A", link: "https://a.com", feedSource: "F", addedDate: Date(), relevanceScore: 0.5)
        let e2 = ThreadEntry(title: "A", link: "https://b.com", feedSource: "F", addedDate: Date(), relevanceScore: 0.5)
        XCTAssertNotEqual(e1, e2)
    }

    // MARK: - ThreadStatus

    func testAllStatusValues() {
        let statuses: [ThreadStatus] = [.active, .stale, .archived, .resolved]
        for status in statuses {
            XCTAssertFalse(status.rawValue.isEmpty)
        }
    }

    // MARK: - Notification

    func testCreateThreadPostsNotification() {
        let expectation = XCTNSNotificationExpectation(
            name: .threadsDidUpdate,
            object: nil
        )
        manager.createThread(title: "Notify", keywords: ["test"])
        wait(for: [expectation], timeout: 1.0)
    }

    func testDeleteThreadPostsNotification() {
        let thread = manager.createThread(title: "Delete", keywords: ["test"])
        let expectation = XCTNSNotificationExpectation(
            name: .threadsDidUpdate,
            object: nil
        )
        manager.deleteThread(id: thread.id)
        wait(for: [expectation], timeout: 1.0)
    }

    // MARK: - Edge Cases

    func testCreateThreadEmptyKeywords() {
        let thread = manager.createThread(title: "No Keywords", keywords: [])
        XCTAssertTrue(thread.keywords.isEmpty)
    }

    func testFindMatchesEmptyKeywords() {
        manager.createThread(title: "Empty KW", keywords: [])
        let suggestions = manager.findMatches(
            title: "Any article title",
            link: "https://example.com/any",
            feedSource: "Feed"
        )
        // No keywords → no match
        XCTAssertTrue(suggestions.isEmpty)
    }

    func testSuggestionsSortedByConfidence() {
        let t1 = manager.createThread(title: "AI Full", keywords: ["ai", "neural", "deep", "learning"])
        let t2 = manager.createThread(title: "AI Partial", keywords: ["ai", "robotics", "automation", "industry"])

        let suggestions = manager.findMatches(
            title: "ai neural deep learning advances in ai research",
            link: "https://example.com/ai",
            feedSource: "Feed"
        )

        // Should be sorted descending by confidence
        for i in 0..<(suggestions.count - 1) {
            XCTAssertGreaterThanOrEqual(suggestions[i].confidence, suggestions[i + 1].confidence)
        }
        _ = t1; _ = t2
    }
}
