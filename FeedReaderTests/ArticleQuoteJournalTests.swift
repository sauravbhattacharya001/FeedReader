//
//  ArticleQuoteJournalTests.swift
//  FeedReaderTests
//
//  Tests for ArticleQuoteJournal.
//

import XCTest
@testable import FeedReader

final class ArticleQuoteJournalTests: XCTestCase {

    private var journal: ArticleQuoteJournal!
    private var tempDir: URL!

    override func setUp() {
        super.setUp()
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        journal = ArticleQuoteJournal(directory: tempDir)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: tempDir)
        super.tearDown()
    }

    // MARK: - Save & Retrieve

    func testSaveQuoteIncreasesCount() {
        XCTAssertEqual(journal.count, 0)
        journal.saveQuote(
            text: "The only way to do great work is to love what you do.",
            articleTitle: "Commencement Speech",
            articleURL: "https://example.com/speech"
        )
        XCTAssertEqual(journal.count, 1)
    }

    func testSaveQuoteWithAllFields() {
        let q = journal.saveQuote(
            text: "Test quote",
            articleTitle: "Test Article",
            articleURL: "https://example.com/test",
            articleAuthor: "Jane Doe",
            feedName: "Tech Blog",
            reflection: "This resonated with me.",
            tags: ["wisdom", "tech"],
            isFavorite: true
        )
        XCTAssertEqual(q.text, "Test quote")
        XCTAssertEqual(q.articleAuthor, "Jane Doe")
        XCTAssertEqual(q.feedName, "Tech Blog")
        XCTAssertEqual(q.reflection, "This resonated with me.")
        XCTAssertEqual(q.tags, ["wisdom", "tech"])
        XCTAssertTrue(q.isFavorite)
    }

    func testRetrieveByID() {
        let q = journal.saveQuote(
            text: "Hello world",
            articleTitle: "Intro",
            articleURL: "https://example.com"
        )
        let found = journal.quote(byID: q.id)
        XCTAssertNotNil(found)
        XCTAssertEqual(found?.text, "Hello world")
    }

    func testAllQuotesReturnedNewestFirst() {
        journal.saveQuote(text: "First", articleTitle: "A", articleURL: "https://a.com")
        journal.saveQuote(text: "Second", articleTitle: "B", articleURL: "https://b.com")
        let all = journal.allQuotes()
        XCTAssertEqual(all.count, 2)
        XCTAssertEqual(all[0].text, "Second")
        XCTAssertEqual(all[1].text, "First")
    }

    // MARK: - Update

    func testUpdateQuoteText() {
        let q = journal.saveQuote(text: "Original", articleTitle: "A", articleURL: "https://a.com")
        let updated = journal.updateQuote(id: q.id, text: "Modified")
        XCTAssertEqual(updated?.text, "Modified")
        XCTAssertNotNil(updated?.lastEdited)
    }

    func testUpdateTags() {
        let q = journal.saveQuote(text: "Quote", articleTitle: "A", articleURL: "https://a.com", tags: ["old"])
        let updated = journal.updateQuote(id: q.id, tags: ["new", "Fresh"])
        XCTAssertEqual(updated?.tags, ["new", "fresh"]) // lowercased
    }

    // MARK: - Delete

    func testDeleteQuote() {
        let q = journal.saveQuote(text: "Bye", articleTitle: "A", articleURL: "https://a.com")
        XCTAssertTrue(journal.deleteQuote(id: q.id))
        XCTAssertEqual(journal.count, 0)
    }

    func testDeleteNonexistentReturnsFalse() {
        XCTAssertFalse(journal.deleteQuote(id: "nope"))
    }

    // MARK: - Favorites

    func testToggleFavorite() {
        let q = journal.saveQuote(text: "Fav", articleTitle: "A", articleURL: "https://a.com")
        XCTAssertFalse(q.isFavorite)
        let status = journal.toggleFavorite(id: q.id)
        XCTAssertEqual(status, true)
        XCTAssertEqual(journal.favorites().count, 1)
    }

    // MARK: - Search

    func testSearchByTextQuery() {
        journal.saveQuote(text: "The quick brown fox", articleTitle: "A", articleURL: "https://a.com")
        journal.saveQuote(text: "Lazy dog sleeps", articleTitle: "B", articleURL: "https://b.com")
        let results = journal.search(QuoteSearchCriteria(textQuery: "fox"))
        XCTAssertEqual(results.count, 1)
        XCTAssertEqual(results[0].text, "The quick brown fox")
    }

    func testSearchByTag() {
        journal.saveQuote(text: "Q1", articleTitle: "A", articleURL: "https://a.com", tags: ["science"])
        journal.saveQuote(text: "Q2", articleTitle: "B", articleURL: "https://b.com", tags: ["art"])
        let results = journal.search(QuoteSearchCriteria(tags: ["science"]))
        XCTAssertEqual(results.count, 1)
    }

    func testSearchFavoritesOnly() {
        journal.saveQuote(text: "Q1", articleTitle: "A", articleURL: "https://a.com", isFavorite: true)
        journal.saveQuote(text: "Q2", articleTitle: "B", articleURL: "https://b.com")
        var criteria = QuoteSearchCriteria()
        criteria.favoritesOnly = true
        let results = journal.search(criteria)
        XCTAssertEqual(results.count, 1)
        XCTAssertEqual(results[0].text, "Q1")
    }

    // MARK: - Tags

    func testAllTagsSortedByFrequency() {
        journal.saveQuote(text: "Q1", articleTitle: "A", articleURL: "https://a.com", tags: ["alpha", "beta"])
        journal.saveQuote(text: "Q2", articleTitle: "B", articleURL: "https://b.com", tags: ["alpha"])
        let tags = journal.allTags()
        XCTAssertEqual(tags[0].tag, "alpha")
        XCTAssertEqual(tags[0].count, 2)
    }

    // MARK: - Statistics

    func testStatisticsComputation() {
        journal.saveQuote(text: "Hello world", articleTitle: "A", articleURL: "https://a.com",
                          feedName: "Blog", tags: ["greet"], isFavorite: true)
        journal.saveQuote(text: "Goodbye", articleTitle: "B", articleURL: "https://b.com",
                          feedName: "Blog", tags: ["greet", "farewell"])
        let stats = journal.statistics()
        XCTAssertEqual(stats.totalQuotes, 2)
        XCTAssertEqual(stats.totalFavorites, 1)
        XCTAssertEqual(stats.uniqueTags, 2)
        XCTAssertEqual(stats.uniqueSources, 2)
        XCTAssertEqual(stats.quotesPerFeed.first?.feed, "Blog")
        XCTAssertEqual(stats.topTags.first?.tag, "greet")
    }

    // MARK: - Export

    func testExportMarkdown() {
        journal.saveQuote(text: "Deep thought", articleTitle: "Philosophy 101",
                          articleURL: "https://example.com/philo", tags: ["philosophy"])
        let md = journal.export(format: .markdown)
        XCTAssertTrue(md.contains("> Deep thought"))
        XCTAssertTrue(md.contains("#philosophy"))
    }

    func testExportJSON() {
        journal.saveQuote(text: "JSON quote", articleTitle: "A", articleURL: "https://a.com")
        let json = journal.export(format: .json)
        XCTAssertTrue(json.contains("JSON quote"))
        XCTAssertTrue(json.contains("articleURL"))
    }

    func testExportPlainText() {
        journal.saveQuote(text: "Plain quote", articleTitle: "A", articleURL: "https://a.com")
        let txt = journal.export(format: .plainText)
        XCTAssertTrue(txt.contains("\"Plain quote\""))
        XCTAssertTrue(txt.contains("QUOTE JOURNAL"))
    }

    // MARK: - Persistence

    func testPersistenceAcrossInstances() {
        journal.saveQuote(text: "Persisted", articleTitle: "A", articleURL: "https://a.com")
        let journal2 = ArticleQuoteJournal(directory: tempDir)
        XCTAssertEqual(journal2.count, 1)
        XCTAssertEqual(journal2.allQuotes()[0].text, "Persisted")
    }

    // MARK: - Quote of the Day

    func testQuoteOfTheDayReturnsNilWhenEmpty() {
        XCTAssertNil(journal.quoteOfTheDay())
    }

    func testQuoteOfTheDayIsConsistentWithinSameCall() {
        journal.saveQuote(text: "Q1", articleTitle: "A", articleURL: "https://a.com")
        journal.saveQuote(text: "Q2", articleTitle: "B", articleURL: "https://b.com")
        let first = journal.quoteOfTheDay()
        let second = journal.quoteOfTheDay()
        XCTAssertEqual(first?.id, second?.id)
    }

    // MARK: - Reset

    func testResetClearsAll() {
        journal.saveQuote(text: "Q1", articleTitle: "A", articleURL: "https://a.com")
        journal.reset()
        XCTAssertEqual(journal.count, 0)
    }

    // MARK: - Edge Cases

    func testTagsAreLowercased() {
        let q = journal.saveQuote(text: "Q", articleTitle: "A", articleURL: "https://a.com",
                                  tags: ["Science", "ART"])
        XCTAssertEqual(q.tags, ["science", "art"])
    }

    func testQuotesFromArticle() {
        let url = "https://example.com/article"
        journal.saveQuote(text: "Q1", articleTitle: "A", articleURL: url)
        journal.saveQuote(text: "Q2", articleTitle: "A", articleURL: url)
        journal.saveQuote(text: "Q3", articleTitle: "B", articleURL: "https://other.com")
        XCTAssertEqual(journal.quotes(fromArticle: url).count, 2)
    }
}
