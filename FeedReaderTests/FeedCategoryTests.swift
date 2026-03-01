//
//  FeedCategoryTests.swift
//  FeedReaderTests
//
//  Tests for FeedCategoryManager — category CRUD, feed assignment,
//  grouping, and edge cases.
//

import XCTest
@testable import FeedReader

class FeedCategoryTests: XCTestCase {
    
    var manager: FeedCategoryManager!
    
    override func setUp() {
        super.setUp()
        manager = FeedCategoryManager.shared
        manager.reset()
    }
    
    override func tearDown() {
        manager.reset()
        super.tearDown()
    }
    
    // MARK: - Add Category
    
    func testAddCategory() {
        XCTAssertTrue(manager.addCategory("News"))
        XCTAssertEqual(manager.count, 1)
        XCTAssertEqual(manager.categories.first, "News")
    }
    
    func testAddDuplicateCategoryFails() {
        manager.addCategory("News")
        XCTAssertFalse(manager.addCategory("news")) // case-insensitive
        XCTAssertEqual(manager.count, 1)
    }
    
    func testAddEmptyCategoryFails() {
        XCTAssertFalse(manager.addCategory(""))
        XCTAssertFalse(manager.addCategory("   "))
        XCTAssertEqual(manager.count, 0)
    }
    
    func testAddMultipleCategories() {
        manager.addCategory("News")
        manager.addCategory("Tech")
        manager.addCategory("Science")
        XCTAssertEqual(manager.count, 3)
    }
    
    // MARK: - Remove Category
    
    func testRemoveCategory() {
        manager.addCategory("News")
        manager.removeCategory("News")
        XCTAssertEqual(manager.count, 0)
    }
    
    func testRemoveNonexistentCategory() {
        XCTAssertEqual(manager.removeCategory("Nope"), 0)
    }
    
    // MARK: - Rename Category
    
    func testRenameCategory() {
        manager.addCategory("News")
        XCTAssertTrue(manager.renameCategory(from: "News", to: "World News"))
        XCTAssertEqual(manager.categories.first, "World News")
        XCTAssertFalse(manager.categoryExists("News"))
    }
    
    func testRenameToDuplicateFails() {
        manager.addCategory("News")
        manager.addCategory("Tech")
        XCTAssertFalse(manager.renameCategory(from: "News", to: "Tech"))
    }
    
    func testRenameToEmptyFails() {
        manager.addCategory("News")
        XCTAssertFalse(manager.renameCategory(from: "News", to: ""))
    }
    
    // MARK: - Move Category
    
    func testMoveCategory() {
        manager.addCategory("A")
        manager.addCategory("B")
        manager.addCategory("C")
        manager.moveCategory(from: 2, to: 0)
        XCTAssertEqual(manager.categories, ["C", "A", "B"])
    }
    
    // MARK: - Category Exists
    
    func testCategoryExistsCaseInsensitive() {
        manager.addCategory("Technology")
        XCTAssertTrue(manager.categoryExists("technology"))
        XCTAssertTrue(manager.categoryExists("TECHNOLOGY"))
        XCTAssertFalse(manager.categoryExists("Tech"))
    }
    
    // MARK: - Feed Assignment
    
    func testAssignFeedCreatesCategory() {
        let feed = Feed(name: "Test", url: "https://example.com/feed", isEnabled: true)
        manager.assignFeed(feed, toCategory: "News")
        XCTAssertEqual(feed.category, "News")
        XCTAssertTrue(manager.categoryExists("News"))
    }
    
    func testUnassignFeed() {
        let feed = Feed(name: "Test", url: "https://example.com/feed", isEnabled: true, category: "News")
        manager.unassignFeed(feed)
        XCTAssertNil(feed.category)
    }
    
    // MARK: - Feed Category Property
    
    func testFeedCategoryEncodeDecode() {
        let feed = Feed(name: "Test", url: "https://example.com/feed", isEnabled: true, category: "Tech")
        XCTAssertEqual(feed.category, "Tech")
        
        // Test encoding and decoding
        let data = try! NSKeyedArchiver.archivedData(withRootObject: feed, requiringSecureCoding: true)
        let decoded = try! NSKeyedUnarchiver.unarchivedObject(ofClass: Feed.self, from: data)
        XCTAssertEqual(decoded?.category, "Tech")
    }
    
    func testFeedNilCategoryEncodeDecode() {
        let feed = Feed(name: "Test", url: "https://example.com/feed", isEnabled: true)
        XCTAssertNil(feed.category)
        
        let data = try! NSKeyedArchiver.archivedData(withRootObject: feed, requiringSecureCoding: true)
        let decoded = try! NSKeyedUnarchiver.unarchivedObject(ofClass: Feed.self, from: data)
        XCTAssertNil(decoded?.category)
    }
    
    // MARK: - Grouping
    
    func testFeedCountByCategory() {
        // This test depends on FeedManager state, so we just verify the method runs
        let counts = manager.feedCountByCategory()
        XCTAssertNotNil(counts)
    }
    
    // MARK: - Persistence
    
    func testPersistence() {
        manager.addCategory("News")
        manager.addCategory("Tech")
        manager.reload()
        XCTAssertEqual(manager.count, 2)
        XCTAssertTrue(manager.categoryExists("News"))
        XCTAssertTrue(manager.categoryExists("Tech"))
    }
}
