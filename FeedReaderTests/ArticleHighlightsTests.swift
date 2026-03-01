//
//  ArticleHighlightsTests.swift
//  FeedReaderTests
//
//  Tests for ArticleHighlight and ArticleHighlightsManager.
//

import XCTest
@testable import FeedReader

class ArticleHighlightsTests: XCTestCase {
    
    var manager: ArticleHighlightsManager!
    
    override func setUp() {
        super.setUp()
        manager = ArticleHighlightsManager.shared
        manager.reset()
    }
    
    override func tearDown() {
        manager.reset()
        super.tearDown()
    }
    
    // MARK: - ArticleHighlight Model Tests
    
    func testHighlightCreation() {
        let highlight = ArticleHighlight(
            articleLink: "https://example.com/article",
            articleTitle: "Test Article",
            selectedText: "Important quote from article"
        )
        XCTAssertNotNil(highlight)
        XCTAssertEqual(highlight?.selectedText, "Important quote from article")
        XCTAssertEqual(highlight?.color, .yellow)
        XCTAssertNil(highlight?.annotation)
    }
    
    func testHighlightRejectsEmptyText() {
        let highlight = ArticleHighlight(
            articleLink: "https://example.com",
            articleTitle: "Test",
            selectedText: "   "
        )
        XCTAssertNil(highlight)
    }
    
    func testHighlightRejectsEmptyLink() {
        let highlight = ArticleHighlight(
            articleLink: "",
            articleTitle: "Test",
            selectedText: "Some text"
        )
        XCTAssertNil(highlight)
    }
    
    func testHighlightTruncatesLongText() {
        let longText = String(repeating: "x", count: 3000)
        let highlight = ArticleHighlight(
            articleLink: "https://example.com",
            articleTitle: "Test",
            selectedText: longText
        )
        XCTAssertNotNil(highlight)
        XCTAssertEqual(highlight?.selectedText.count, ArticleHighlight.maxTextLength)
    }
    
    func testHighlightWithAnnotation() {
        let highlight = ArticleHighlight(
            articleLink: "https://example.com",
            articleTitle: "Test",
            selectedText: "Quote",
            annotation: "My thoughts on this"
        )
        XCTAssertEqual(highlight?.annotation, "My thoughts on this")
    }
    
    func testHighlightColorEnum() {
        XCTAssertEqual(HighlightColor.yellow.displayName, "Yellow")
        XCTAssertEqual(HighlightColor.green.displayName, "Green")
        XCTAssertEqual(HighlightColor.blue.displayName, "Blue")
        XCTAssertEqual(HighlightColor.pink.displayName, "Pink")
        XCTAssertEqual(HighlightColor.orange.displayName, "Orange")
    }
    
    // MARK: - NSSecureCoding Tests
    
    func testHighlightSecureCoding() throws {
        let original = ArticleHighlight(
            articleLink: "https://example.com/article",
            articleTitle: "Coding Test",
            selectedText: "Persist this text",
            color: .blue,
            annotation: "Important"
        )!
        
        let data = try NSKeyedArchiver.archivedData(withRootObject: original, requiringSecureCoding: true)
        let decoded = try NSKeyedUnarchiver.unarchivedObject(ofClass: ArticleHighlight.self, from: data)
        
        XCTAssertNotNil(decoded)
        XCTAssertEqual(decoded?.id, original.id)
        XCTAssertEqual(decoded?.articleLink, original.articleLink)
        XCTAssertEqual(decoded?.selectedText, original.selectedText)
        XCTAssertEqual(decoded?.color, .blue)
        XCTAssertEqual(decoded?.annotation, "Important")
    }
    
    // MARK: - Manager CRUD Tests
    
    func testAddHighlight() {
        let h = manager.addHighlight(
            articleLink: "https://example.com",
            articleTitle: "Test",
            selectedText: "Highlighted text"
        )
        XCTAssertNotNil(h)
        XCTAssertEqual(manager.count, 1)
    }
    
    func testRemoveHighlight() {
        let h = manager.addHighlight(
            articleLink: "https://example.com",
            articleTitle: "Test",
            selectedText: "Text"
        )!
        XCTAssertTrue(manager.removeHighlight(id: h.id))
        XCTAssertEqual(manager.count, 0)
    }
    
    func testRemoveNonexistentHighlight() {
        XCTAssertFalse(manager.removeHighlight(id: "fake-id"))
    }
    
    func testUpdateColor() {
        let h = manager.addHighlight(
            articleLink: "https://example.com",
            articleTitle: "Test",
            selectedText: "Text"
        )!
        manager.updateColor(id: h.id, color: .green)
        XCTAssertEqual(manager.getHighlight(id: h.id)?.color, .green)
    }
    
    func testUpdateAnnotation() {
        let h = manager.addHighlight(
            articleLink: "https://example.com",
            articleTitle: "Test",
            selectedText: "Text"
        )!
        manager.updateAnnotation(id: h.id, annotation: "New note")
        XCTAssertEqual(manager.getHighlight(id: h.id)?.annotation, "New note")
        
        manager.updateAnnotation(id: h.id, annotation: nil)
        XCTAssertNil(manager.getHighlight(id: h.id)?.annotation)
    }
    
    // MARK: - Query Tests
    
    func testHighlightsForArticle() {
        manager.addHighlight(articleLink: "https://a.com", articleTitle: "A", selectedText: "Text 1")
        manager.addHighlight(articleLink: "https://a.com", articleTitle: "A", selectedText: "Text 2")
        manager.addHighlight(articleLink: "https://b.com", articleTitle: "B", selectedText: "Text 3")
        
        XCTAssertEqual(manager.highlights(for: "https://a.com").count, 2)
        XCTAssertEqual(manager.highlights(for: "https://b.com").count, 1)
        XCTAssertEqual(manager.highlights(for: "https://c.com").count, 0)
    }
    
    func testHighlightsByColor() {
        manager.addHighlight(articleLink: "https://a.com", articleTitle: "A", selectedText: "T1", color: .yellow)
        manager.addHighlight(articleLink: "https://a.com", articleTitle: "A", selectedText: "T2", color: .blue)
        manager.addHighlight(articleLink: "https://a.com", articleTitle: "A", selectedText: "T3", color: .yellow)
        
        XCTAssertEqual(manager.highlights(byColor: .yellow).count, 2)
        XCTAssertEqual(manager.highlights(byColor: .blue).count, 1)
        XCTAssertEqual(manager.highlights(byColor: .green).count, 0)
    }
    
    func testSearch() {
        manager.addHighlight(articleLink: "https://a.com", articleTitle: "Swift Guide", selectedText: "Protocol-oriented programming")
        manager.addHighlight(articleLink: "https://b.com", articleTitle: "Python Tips", selectedText: "List comprehensions are powerful")
        
        XCTAssertEqual(manager.search(query: "protocol").count, 1)
        XCTAssertEqual(manager.search(query: "python").count, 1)
        XCTAssertEqual(manager.search(query: "").count, 2)
        XCTAssertEqual(manager.search(query: "rust").count, 0)
    }
    
    func testArticlesWithHighlights() {
        manager.addHighlight(articleLink: "https://a.com", articleTitle: "Article A", selectedText: "T1")
        manager.addHighlight(articleLink: "https://a.com", articleTitle: "Article A", selectedText: "T2")
        manager.addHighlight(articleLink: "https://b.com", articleTitle: "Article B", selectedText: "T3")
        
        let articles = manager.articlesWithHighlights()
        XCTAssertEqual(articles.count, 2)
        // Most recent first — b.com was added last
        XCTAssertEqual(articles[0].articleLink, "https://b.com")
        XCTAssertEqual(articles[1].count, 2)
    }
    
    // MARK: - Bulk Operations
    
    func testRemoveHighlightsForArticle() {
        manager.addHighlight(articleLink: "https://a.com", articleTitle: "A", selectedText: "T1")
        manager.addHighlight(articleLink: "https://a.com", articleTitle: "A", selectedText: "T2")
        manager.addHighlight(articleLink: "https://b.com", articleTitle: "B", selectedText: "T3")
        
        let removed = manager.removeHighlights(for: "https://a.com")
        XCTAssertEqual(removed, 2)
        XCTAssertEqual(manager.count, 1)
    }
    
    func testClearAll() {
        manager.addHighlight(articleLink: "https://a.com", articleTitle: "A", selectedText: "T1")
        manager.addHighlight(articleLink: "https://b.com", articleTitle: "B", selectedText: "T2")
        
        let cleared = manager.clearAll()
        XCTAssertEqual(cleared, 2)
        XCTAssertEqual(manager.count, 0)
    }
    
    // MARK: - Export Tests
    
    func testExportEmpty() {
        XCTAssertEqual(manager.exportAsText(), "No highlights.")
    }
    
    func testExportWithHighlights() {
        manager.addHighlight(
            articleLink: "https://a.com",
            articleTitle: "Test Article",
            selectedText: "Important text",
            color: .green,
            annotation: "My note"
        )
        let export = manager.exportAsText()
        XCTAssertTrue(export.contains("Test Article"))
        XCTAssertTrue(export.contains("Important text"))
        XCTAssertTrue(export.contains("Green"))
        XCTAssertTrue(export.contains("My note"))
    }
    
    // MARK: - Persistence Tests
    
    func testPersistenceRoundTrip() {
        manager.addHighlight(
            articleLink: "https://example.com",
            articleTitle: "Persist Test",
            selectedText: "Saved text",
            color: .pink
        )
        
        manager.reloadFromDefaults()
        
        XCTAssertEqual(manager.count, 1)
        let all = manager.getAllHighlights()
        XCTAssertEqual(all.first?.selectedText, "Saved text")
        XCTAssertEqual(all.first?.color, .pink)
    }
}
