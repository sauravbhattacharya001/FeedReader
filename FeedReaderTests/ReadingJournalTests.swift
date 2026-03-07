//
//  ReadingJournalTests.swift
//  FeedReaderTests
//
//  Tests for ReadingJournalManager — daily reading journal with
//  Markdown export, reflections, streaks, and digests.
//

import XCTest
@testable import FeedReader

final class ReadingJournalTests: XCTestCase {

    // MARK: - Setup

    override func setUp() {
        super.setUp()
        ReadingJournalManager.shared.clearAll()
    }

    override func tearDown() {
        ReadingJournalManager.shared.clearAll()
        super.tearDown()
    }

    // MARK: - Entry Creation

    func testTodayEntryCreation() {
        let entry = ReadingJournalManager.shared.todayEntry()
        XCTAssertEqual(entry.articleCount, 0)
        XCTAssertEqual(entry.highlights.count, 0)
        XCTAssertEqual(entry.notes.count, 0)
        XCTAssertNil(entry.reflection)
        XCTAssertNil(entry.moodTag)
    }

    func testTodayEntryIsSingleton() {
        let a = ReadingJournalManager.shared.todayEntry()
        let b = ReadingJournalManager.shared.todayEntry()
        XCTAssertEqual(a.dateKey, b.dateKey)
    }

    // MARK: - Recording

    func testRecordArticle() {
        let entry = ReadingJournalManager.shared.recordArticleRead(
            link: "https://example.com/1", title: "Test Article",
            feedName: "Test Feed", timeSpent: 120
        )
        XCTAssertEqual(entry.articleCount, 1)
        XCTAssertEqual(entry.totalReadingTime, 120)
        XCTAssertEqual(entry.articlesRead.first?.title, "Test Article")
    }

    func testRecordArticleDeduplication() {
        ReadingJournalManager.shared.recordArticleRead(
            link: "https://example.com/1", title: "Article", feedName: "Feed"
        )
        ReadingJournalManager.shared.recordArticleRead(
            link: "https://example.com/1", title: "Article", feedName: "Feed"
        )
        let entry = ReadingJournalManager.shared.todayEntry()
        XCTAssertEqual(entry.articleCount, 1, "Duplicate articles should not be added")
    }

    func testRecordMultipleArticles() {
        for i in 1...5 {
            ReadingJournalManager.shared.recordArticleRead(
                link: "https://example.com/\(i)", title: "Article \(i)",
                feedName: "Feed \(i)", timeSpent: Double(i * 60)
            )
        }
        let entry = ReadingJournalManager.shared.todayEntry()
        XCTAssertEqual(entry.articleCount, 5)
        XCTAssertEqual(entry.totalReadingTime, 900)
    }

    func testRecordHighlight() {
        let entry = ReadingJournalManager.shared.recordHighlight(
            text: "Important quote", articleTitle: "Article", color: "Green"
        )
        XCTAssertEqual(entry.highlights.count, 1)
        XCTAssertEqual(entry.highlights.first?.text, "Important quote")
        XCTAssertEqual(entry.highlights.first?.color, "Green")
    }

    func testRecordNote() {
        let entry = ReadingJournalManager.shared.recordNote(
            text: "My thoughts on this", articleTitle: "Test Article"
        )
        XCTAssertEqual(entry.notes.count, 1)
        XCTAssertEqual(entry.notes.first?.text, "My thoughts on this")
    }

    // MARK: - Reflections

    func testSetReflection() {
        ReadingJournalManager.shared.recordArticleRead(
            link: "https://example.com/1", title: "A", feedName: "F"
        )
        ReadingJournalManager.shared.setReflection("Today was insightful.", for: Date())
        let entry = ReadingJournalManager.shared.todayEntry()
        XCTAssertEqual(entry.reflection, "Today was insightful.")
    }

    func testEmptyReflectionClearsIt() {
        ReadingJournalManager.shared.recordArticleRead(
            link: "https://example.com/1", title: "A", feedName: "F"
        )
        ReadingJournalManager.shared.setReflection("Thoughts", for: Date())
        ReadingJournalManager.shared.setReflection("  ", for: Date())
        let entry = ReadingJournalManager.shared.todayEntry()
        XCTAssertNil(entry.reflection)
    }

    func testReflectionPromptNotEmpty() {
        let prompt = ReadingJournalManager.shared.todayReflectionPrompt()
        XCTAssertFalse(prompt.isEmpty)
    }

    // MARK: - Mood Tags

    func testSetMoodTag() {
        ReadingJournalManager.shared.recordArticleRead(
            link: "https://example.com/1", title: "A", feedName: "F"
        )
        ReadingJournalManager.shared.setMoodTag("Curious", for: Date())
        let entry = ReadingJournalManager.shared.todayEntry()
        XCTAssertEqual(entry.moodTag, "curious")
    }

    func testMoodFrequency() {
        ReadingJournalManager.shared.recordArticleRead(
            link: "https://example.com/1", title: "A", feedName: "F"
        )
        ReadingJournalManager.shared.setMoodTag("curious", for: Date())
        let freq = ReadingJournalManager.shared.moodFrequency()
        XCTAssertTrue(freq.contains(where: { $0.mood == "curious" }))
    }

    // MARK: - Markdown Export

    func testMarkdownExport() {
        ReadingJournalManager.shared.recordArticleRead(
            link: "https://example.com/1", title: "Swift Concurrency",
            feedName: "Apple Blog", timeSpent: 300
        )
        ReadingJournalManager.shared.recordHighlight(
            text: "Actors are great", articleTitle: "Swift Concurrency", color: "Yellow"
        )
        ReadingJournalManager.shared.recordNote(
            text: "Look into structured concurrency", articleTitle: "Swift Concurrency"
        )
        ReadingJournalManager.shared.setReflection("Concurrency is the future.", for: Date())

        let entry = ReadingJournalManager.shared.todayEntry()
        let md = ReadingJournalManager.shared.exportEntryAsMarkdown(entry)

        XCTAssertTrue(md.contains("# 📖 Reading Journal"))
        XCTAssertTrue(md.contains("Swift Concurrency"))
        XCTAssertTrue(md.contains("Actors are great"))
        XCTAssertTrue(md.contains("Look into structured concurrency"))
        XCTAssertTrue(md.contains("Concurrency is the future."))
        XCTAssertTrue(md.contains("1 articles"))
        XCTAssertTrue(md.contains("5 min"))
    }

    func testEmptyExport() {
        let entry = ReadingJournalManager.shared.todayEntry()
        let md = ReadingJournalManager.shared.exportEntryAsMarkdown(entry)
        XCTAssertTrue(md.contains("0 articles"))
    }

    // MARK: - JSON Export

    func testJSONExport() {
        ReadingJournalManager.shared.recordArticleRead(
            link: "https://example.com/1", title: "Test", feedName: "Feed"
        )
        let data = ReadingJournalManager.shared.exportAsJSON()
        XCTAssertNotNil(data)
        XCTAssertTrue(data!.count > 0)
    }

    // MARK: - Search

    func testSearchByArticleTitle() {
        ReadingJournalManager.shared.recordArticleRead(
            link: "https://example.com/1", title: "SwiftUI Navigation",
            feedName: "iOS Blog"
        )
        let results = ReadingJournalManager.shared.search(query: "swiftui")
        XCTAssertEqual(results.count, 1)
    }

    func testSearchByHighlight() {
        ReadingJournalManager.shared.recordHighlight(
            text: "Remember this pattern", articleTitle: "Design"
        )
        let results = ReadingJournalManager.shared.search(query: "pattern")
        XCTAssertEqual(results.count, 1)
    }

    func testSearchByReflection() {
        ReadingJournalManager.shared.recordArticleRead(
            link: "https://example.com/1", title: "A", feedName: "F"
        )
        ReadingJournalManager.shared.setReflection("Mind-blowing insights today", for: Date())
        let results = ReadingJournalManager.shared.search(query: "mind-blowing")
        XCTAssertEqual(results.count, 1)
    }

    func testEmptySearchReturnsNothing() {
        let results = ReadingJournalManager.shared.search(query: "")
        XCTAssertTrue(results.isEmpty)
    }

    // MARK: - Statistics

    func testStatistics() {
        ReadingJournalManager.shared.recordArticleRead(
            link: "https://example.com/1", title: "A", feedName: "F", timeSpent: 300
        )
        ReadingJournalManager.shared.recordHighlight(
            text: "hl", articleTitle: "A"
        )
        ReadingJournalManager.shared.recordNote(text: "note", articleTitle: "A")

        let stats = ReadingJournalManager.shared.statistics()
        XCTAssertEqual(stats.totalEntries, 1)
        XCTAssertEqual(stats.totalArticles, 1)
        XCTAssertEqual(stats.totalReadingTime, 300)
        XCTAssertEqual(stats.totalHighlights, 1)
        XCTAssertEqual(stats.totalNotes, 1)
    }

    // MARK: - Streaks

    func testCurrentStreak() {
        ReadingJournalManager.shared.recordArticleRead(
            link: "https://example.com/1", title: "A", feedName: "F"
        )
        let streak = ReadingJournalManager.shared.currentStreak
        XCTAssertEqual(streak, 1)
    }

    // MARK: - Weekly Digest

    func testWeeklyDigest() {
        ReadingJournalManager.shared.recordArticleRead(
            link: "https://example.com/1", title: "A", feedName: "Tech", timeSpent: 180
        )
        ReadingJournalManager.shared.recordHighlight(
            text: "hl", articleTitle: "A"
        )
        let digest = ReadingJournalManager.shared.weeklyDigest()
        XCTAssertGreaterThanOrEqual(digest.daysActive, 1)
        XCTAssertGreaterThanOrEqual(digest.totalArticles, 1)
        XCTAssertTrue(digest.topFeeds.contains("Tech"))
    }

    // MARK: - Delete

    func testRemoveEntry() {
        ReadingJournalManager.shared.recordArticleRead(
            link: "https://example.com/1", title: "A", feedName: "F"
        )
        XCTAssertEqual(ReadingJournalManager.shared.entryCount, 1)
        ReadingJournalManager.shared.removeEntry(for: Date())
        XCTAssertEqual(ReadingJournalManager.shared.entryCount, 0)
    }

    func testClearAll() {
        ReadingJournalManager.shared.recordArticleRead(
            link: "https://example.com/1", title: "A", feedName: "F"
        )
        ReadingJournalManager.shared.clearAll()
        XCTAssertEqual(ReadingJournalManager.shared.entryCount, 0)
    }

    // MARK: - Entry Count

    func testEntryCount() {
        XCTAssertEqual(ReadingJournalManager.shared.entryCount, 0)
        ReadingJournalManager.shared.recordArticleRead(
            link: "https://example.com/1", title: "A", feedName: "F"
        )
        XCTAssertEqual(ReadingJournalManager.shared.entryCount, 1)
    }
}
