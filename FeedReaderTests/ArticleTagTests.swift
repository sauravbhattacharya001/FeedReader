//
//  ArticleTagTests.swift
//  FeedReaderTests
//
//  Tests for ArticleTagManager: tag CRUD, article tagging,
//  querying, suggestions, statistics, and bulk operations.
//

import XCTest
@testable import FeedReader

class ArticleTagTests: XCTestCase {
    
    var manager: ArticleTagManager!
    
    override func setUp() {
        super.setUp()
        manager = ArticleTagManager.shared
        manager.removeAll()
    }
    
    override func tearDown() {
        manager.removeAll()
        super.tearDown()
    }
    
    // MARK: - Tag Creation
    
    func testCreateTag() {
        let tag = manager.createTag(name: "Swift")
        XCTAssertNotNil(tag)
        XCTAssertEqual(tag?.id, "swift")
        XCTAssertEqual(tag?.displayName, "Swift")
        XCTAssertEqual(manager.tagCount, 1)
    }
    
    func testCreateTagWithColor() {
        let tag = manager.createTag(name: "Urgent", colorHex: "#FF0000")
        XCTAssertNotNil(tag)
        XCTAssertEqual(tag?.colorHex, "#FF0000")
    }
    
    func testCreateDuplicateTagFails() {
        manager.createTag(name: "Swift")
        let duplicate = manager.createTag(name: "swift")
        XCTAssertNil(duplicate)
        XCTAssertEqual(manager.tagCount, 1)
    }
    
    func testCreateEmptyTagFails() {
        let tag = manager.createTag(name: "   ")
        XCTAssertNil(tag)
        XCTAssertEqual(manager.tagCount, 0)
    }
    
    func testCreateTagTrimsWhitespace() {
        let tag = manager.createTag(name: "  AI Research  ")
        XCTAssertNotNil(tag)
        XCTAssertEqual(tag?.id, "ai research")
        XCTAssertEqual(tag?.displayName, "AI Research")
    }
    
    // MARK: - Tag Deletion
    
    func testDeleteTag() {
        manager.createTag(name: "Temp")
        XCTAssertEqual(manager.tagCount, 1)
        manager.deleteTag(id: "temp")
        XCTAssertEqual(manager.tagCount, 0)
    }
    
    func testDeleteTagRemovesFromArticles() {
        manager.createTag(name: "iOS")
        manager.tagArticle(link: "https://example.com/1", title: "Article 1", feedName: "Blog", tagId: "ios")
        XCTAssertEqual(manager.tagsForArticle(link: "https://example.com/1").count, 1)
        
        manager.deleteTag(id: "ios")
        XCTAssertEqual(manager.tagsForArticle(link: "https://example.com/1").count, 0)
    }
    
    // MARK: - Tag Rename
    
    func testRenameTag() {
        manager.createTag(name: "ML")
        let renamed = manager.renameTag(id: "ml", newName: "Machine Learning")
        XCTAssertNotNil(renamed)
        XCTAssertEqual(renamed?.displayName, "Machine Learning")
        XCTAssertEqual(manager.tagCount, 1)
        XCTAssertNil(manager.tags["ml"])
        XCTAssertNotNil(manager.tags["machine learning"])
    }
    
    func testRenameTagPreservesAssociations() {
        manager.createTag(name: "ML")
        manager.tagArticle(link: "https://example.com/1", title: "Art", feedName: "F", tagId: "ml")
        manager.renameTag(id: "ml", newName: "Machine Learning")
        
        let tags = manager.tagsForArticle(link: "https://example.com/1")
        XCTAssertEqual(tags.count, 1)
        XCTAssertEqual(tags.first?.displayName, "Machine Learning")
    }
    
    // MARK: - Tag Color
    
    func testSetTagColor() {
        manager.createTag(name: "Red")
        manager.setTagColor(id: "red", colorHex: "#FF0000")
        XCTAssertEqual(manager.tags["red"]?.colorHex, "#FF0000")
        
        manager.setTagColor(id: "red", colorHex: nil)
        XCTAssertNil(manager.tags["red"]?.colorHex)
    }
    
    // MARK: - Article Tagging
    
    func testTagArticle() {
        manager.createTag(name: "Tech")
        manager.tagArticle(link: "https://example.com/1", title: "Article", feedName: "Blog", tagId: "tech")
        
        let tags = manager.tagsForArticle(link: "https://example.com/1")
        XCTAssertEqual(tags.count, 1)
        XCTAssertEqual(tags.first?.id, "tech")
        XCTAssertEqual(manager.taggedArticleCount, 1)
    }
    
    func testTagArticleMultipleTags() {
        manager.createTag(name: "Tech")
        manager.createTag(name: "AI")
        manager.tagArticle(link: "https://example.com/1", title: "Art", feedName: "F", tagId: "tech")
        manager.tagArticle(link: "https://example.com/1", title: "Art", feedName: "F", tagId: "ai")
        
        XCTAssertEqual(manager.tagsForArticle(link: "https://example.com/1").count, 2)
        XCTAssertEqual(manager.taggedArticleCount, 1)
    }
    
    func testUntagArticle() {
        manager.createTag(name: "Tech")
        manager.tagArticle(link: "https://example.com/1", title: "Art", feedName: "F", tagId: "tech")
        manager.untagArticle(link: "https://example.com/1", tagId: "tech")
        
        XCTAssertEqual(manager.tagsForArticle(link: "https://example.com/1").count, 0)
        XCTAssertEqual(manager.taggedArticleCount, 0)
    }
    
    func testArticleHasTag() {
        manager.createTag(name: "Tech")
        manager.tagArticle(link: "https://example.com/1", title: "Art", feedName: "F", tagId: "tech")
        
        XCTAssertTrue(manager.articleHasTag(link: "https://example.com/1", tagId: "tech"))
        XCTAssertFalse(manager.articleHasTag(link: "https://example.com/1", tagId: "other"))
        XCTAssertFalse(manager.articleHasTag(link: "https://example.com/2", tagId: "tech"))
    }
    
    // MARK: - Querying
    
    func testArticlesWithTag() {
        manager.createTag(name: "AI")
        manager.tagArticle(link: "https://example.com/1", title: "A1", feedName: "F", tagId: "ai")
        manager.tagArticle(link: "https://example.com/2", title: "A2", feedName: "F", tagId: "ai")
        
        let articles = manager.articlesWithTag(tagId: "ai")
        XCTAssertEqual(articles.count, 2)
    }
    
    func testArticlesWithAllTags() {
        manager.createTag(name: "AI")
        manager.createTag(name: "Tutorial")
        manager.tagArticle(link: "https://example.com/1", title: "A1", feedName: "F", tagId: "ai")
        manager.tagArticle(link: "https://example.com/1", title: "A1", feedName: "F", tagId: "tutorial")
        manager.tagArticle(link: "https://example.com/2", title: "A2", feedName: "F", tagId: "ai")
        
        let both = manager.articlesWithAllTags(tagIds: ["ai", "tutorial"])
        XCTAssertEqual(both.count, 1)
        XCTAssertEqual(both.first?.articleLink, "https://example.com/1")
    }
    
    func testArticlesWithAnyTag() {
        manager.createTag(name: "AI")
        manager.createTag(name: "Web")
        manager.tagArticle(link: "https://example.com/1", title: "A1", feedName: "F", tagId: "ai")
        manager.tagArticle(link: "https://example.com/2", title: "A2", feedName: "F", tagId: "web")
        
        let any = manager.articlesWithAnyTag(tagIds: ["ai", "web"])
        XCTAssertEqual(any.count, 2)
    }
    
    // MARK: - Suggestions & Search
    
    func testSuggestTags() {
        manager.createTag(name: "AI")
        manager.createTag(name: "Web")
        manager.createTag(name: "iOS")
        // Tag multiple articles with AI to boost its use count
        manager.tagArticle(link: "https://example.com/1", title: "A1", feedName: "F", tagId: "ai")
        manager.tagArticle(link: "https://example.com/2", title: "A2", feedName: "F", tagId: "ai")
        manager.tagArticle(link: "https://example.com/3", title: "A3", feedName: "F", tagId: "web")
        
        // For article 1 (already has AI), suggestions should not include AI
        let suggestions = manager.suggestTags(forArticle: "https://example.com/1", limit: 5)
        XCTAssertFalse(suggestions.contains { $0.id == "ai" })
        XCTAssertTrue(suggestions.contains { $0.id == "web" })
    }
    
    func testSearchTags() {
        manager.createTag(name: "Swift")
        manager.createTag(name: "SwiftUI")
        manager.createTag(name: "Python")
        
        let results = manager.searchTags(query: "swift")
        XCTAssertEqual(results.count, 2)
        
        let all = manager.searchTags(query: "")
        XCTAssertEqual(all.count, 3)
    }
    
    // MARK: - Statistics
    
    func testTagUsageSummary() {
        manager.createTag(name: "AI")
        manager.createTag(name: "Web")
        manager.tagArticle(link: "https://example.com/1", title: "A1", feedName: "F", tagId: "ai")
        manager.tagArticle(link: "https://example.com/2", title: "A2", feedName: "F", tagId: "ai")
        manager.tagArticle(link: "https://example.com/3", title: "A3", feedName: "F", tagId: "web")
        
        let summary = manager.tagUsageSummary()
        XCTAssertEqual(summary.count, 2)
        XCTAssertEqual(summary.first?.tag.id, "ai")
        XCTAssertEqual(summary.first?.articleCount, 2)
    }
    
    // MARK: - Bulk Operations
    
    func testRemoveAllTagsFromArticle() {
        manager.createTag(name: "A")
        manager.createTag(name: "B")
        manager.tagArticle(link: "https://example.com/1", title: "Art", feedName: "F", tagId: "a")
        manager.tagArticle(link: "https://example.com/1", title: "Art", feedName: "F", tagId: "b")
        
        manager.removeAllTags(fromArticle: "https://example.com/1")
        XCTAssertEqual(manager.tagsForArticle(link: "https://example.com/1").count, 0)
        XCTAssertEqual(manager.taggedArticleCount, 0)
    }
    
    func testRemoveAll() {
        manager.createTag(name: "X")
        manager.tagArticle(link: "https://example.com/1", title: "Art", feedName: "F", tagId: "x")
        
        manager.removeAll()
        XCTAssertEqual(manager.tagCount, 0)
        XCTAssertEqual(manager.taggedArticleCount, 0)
    }
    
    // MARK: - Use Count Tracking
    
    func testUseCountIncrementsOnTag() {
        manager.createTag(name: "Track")
        manager.tagArticle(link: "https://example.com/1", title: "A1", feedName: "F", tagId: "track")
        manager.tagArticle(link: "https://example.com/2", title: "A2", feedName: "F", tagId: "track")
        
        XCTAssertEqual(manager.tags["track"]?.useCount, 2)
    }
    
    func testUseCountDecrementsOnUntag() {
        manager.createTag(name: "Track")
        manager.tagArticle(link: "https://example.com/1", title: "A1", feedName: "F", tagId: "track")
        manager.untagArticle(link: "https://example.com/1", tagId: "track")
        
        XCTAssertEqual(manager.tags["track"]?.useCount, 0)
    }
    
    // MARK: - Notification
    
    func testNotificationPostedOnChange() {
        let expectation = self.expectation(forNotification: .articleTagsDidChange, object: nil)
        manager.createTag(name: "Notify")
        wait(for: [expectation], timeout: 1.0)
    }
    
    // MARK: - Sorting
    
    func testAllTagsAlphabetical() {
        manager.createTag(name: "Zebra")
        manager.createTag(name: "Alpha")
        manager.createTag(name: "Mid")
        
        let sorted = manager.allTagsAlphabetical()
        XCTAssertEqual(sorted.map { $0.displayName }, ["Alpha", "Mid", "Zebra"])
    }
    
    func testAllTagsByPopularity() {
        manager.createTag(name: "Low")
        manager.createTag(name: "High")
        manager.tagArticle(link: "https://example.com/1", title: "A", feedName: "F", tagId: "high")
        manager.tagArticle(link: "https://example.com/2", title: "B", feedName: "F", tagId: "high")
        manager.tagArticle(link: "https://example.com/3", title: "C", feedName: "F", tagId: "low")
        
        let popular = manager.allTagsByPopularity()
        XCTAssertEqual(popular.first?.id, "high")
    }
}
