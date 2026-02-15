//
//  BookmarkTests.swift
//  FeedReaderTests
//
//  Tests for BookmarkManager — add, remove, toggle, persistence, edge cases.
//

import XCTest
@testable import FeedReader

class BookmarkTests: XCTestCase {
    
    // MARK: - Helpers
    
    private func makeStory(title: String = "Test Story", description: String = "A test description", link: String = "https://example.com/story1") -> Story {
        return Story(title: title, photo: nil, description: description, link: link)!
    }
    
    override func setUp() {
        super.setUp()
        // Clear bookmarks before each test
        BookmarkManager.shared.clearAll()
    }
    
    override func tearDown() {
        BookmarkManager.shared.clearAll()
        super.tearDown()
    }
    
    // MARK: - Add / Remove
    
    func testAddBookmark() {
        let story = makeStory()
        BookmarkManager.shared.addBookmark(story)
        
        XCTAssertEqual(BookmarkManager.shared.count, 1)
        XCTAssertTrue(BookmarkManager.shared.isBookmarked(story))
    }
    
    func testAddDuplicateBookmark() {
        let story = makeStory()
        BookmarkManager.shared.addBookmark(story)
        BookmarkManager.shared.addBookmark(story) // duplicate
        
        XCTAssertEqual(BookmarkManager.shared.count, 1, "Duplicate bookmarks should not be added")
    }
    
    func testRemoveBookmark() {
        let story = makeStory()
        BookmarkManager.shared.addBookmark(story)
        BookmarkManager.shared.removeBookmark(story)
        
        XCTAssertEqual(BookmarkManager.shared.count, 0)
        XCTAssertFalse(BookmarkManager.shared.isBookmarked(story))
    }
    
    func testRemoveNonexistentBookmark() {
        let story = makeStory()
        BookmarkManager.shared.removeBookmark(story) // not added
        
        XCTAssertEqual(BookmarkManager.shared.count, 0, "Removing a non-bookmarked story should be a no-op")
    }
    
    func testRemoveBookmarkAtIndex() {
        let story1 = makeStory(title: "Story 1", link: "https://example.com/1")
        let story2 = makeStory(title: "Story 2", link: "https://example.com/2")
        BookmarkManager.shared.addBookmark(story1)
        BookmarkManager.shared.addBookmark(story2)
        
        BookmarkManager.shared.removeBookmark(at: 0)
        
        XCTAssertEqual(BookmarkManager.shared.count, 1)
    }
    
    func testRemoveBookmarkAtInvalidIndex() {
        let story = makeStory()
        BookmarkManager.shared.addBookmark(story)
        
        BookmarkManager.shared.removeBookmark(at: 5) // out of bounds
        BookmarkManager.shared.removeBookmark(at: -1) // negative
        
        XCTAssertEqual(BookmarkManager.shared.count, 1, "Invalid index should not remove anything")
    }
    
    // MARK: - Toggle
    
    func testToggleBookmarkAdds() {
        let story = makeStory()
        let result = BookmarkManager.shared.toggleBookmark(story)
        
        XCTAssertTrue(result, "Toggle should return true when adding")
        XCTAssertTrue(BookmarkManager.shared.isBookmarked(story))
    }
    
    func testToggleBookmarkRemoves() {
        let story = makeStory()
        BookmarkManager.shared.addBookmark(story)
        let result = BookmarkManager.shared.toggleBookmark(story)
        
        XCTAssertFalse(result, "Toggle should return false when removing")
        XCTAssertFalse(BookmarkManager.shared.isBookmarked(story))
    }
    
    func testDoubleToggle() {
        let story = makeStory()
        BookmarkManager.shared.toggleBookmark(story) // add
        BookmarkManager.shared.toggleBookmark(story) // remove
        
        XCTAssertEqual(BookmarkManager.shared.count, 0)
        XCTAssertFalse(BookmarkManager.shared.isBookmarked(story))
    }
    
    // MARK: - isBookmarked
    
    func testIsBookmarkedMatchesByLink() {
        let story1 = makeStory(title: "Title A", link: "https://example.com/same")
        BookmarkManager.shared.addBookmark(story1)
        
        // Different title, same link — should still be considered bookmarked
        let story2 = makeStory(title: "Title B", link: "https://example.com/same")
        XCTAssertTrue(BookmarkManager.shared.isBookmarked(story2), "Bookmark matching should use link URL")
    }
    
    func testIsBookmarkedReturnsFalse() {
        let story = makeStory(link: "https://example.com/not-bookmarked")
        XCTAssertFalse(BookmarkManager.shared.isBookmarked(story))
    }
    
    // MARK: - Ordering
    
    func testNewestBookmarkFirst() {
        let story1 = makeStory(title: "First", link: "https://example.com/1")
        let story2 = makeStory(title: "Second", link: "https://example.com/2")
        let story3 = makeStory(title: "Third", link: "https://example.com/3")
        
        BookmarkManager.shared.addBookmark(story1)
        BookmarkManager.shared.addBookmark(story2)
        BookmarkManager.shared.addBookmark(story3)
        
        XCTAssertEqual(BookmarkManager.shared.bookmarks[0].title, "Third", "Most recently bookmarked should be first")
        XCTAssertEqual(BookmarkManager.shared.bookmarks[2].title, "First", "Oldest bookmark should be last")
    }
    
    // MARK: - Clear All
    
    func testClearAll() {
        let story1 = makeStory(title: "Story 1", link: "https://example.com/1")
        let story2 = makeStory(title: "Story 2", link: "https://example.com/2")
        BookmarkManager.shared.addBookmark(story1)
        BookmarkManager.shared.addBookmark(story2)
        
        BookmarkManager.shared.clearAll()
        
        XCTAssertEqual(BookmarkManager.shared.count, 0)
        XCTAssertFalse(BookmarkManager.shared.isBookmarked(story1))
        XCTAssertFalse(BookmarkManager.shared.isBookmarked(story2))
    }
    
    func testClearAllWhenEmpty() {
        BookmarkManager.shared.clearAll()
        XCTAssertEqual(BookmarkManager.shared.count, 0, "Clearing empty bookmarks should be a no-op")
    }
    
    // MARK: - Multiple Stories
    
    func testMultipleBookmarks() {
        for i in 1...10 {
            let story = makeStory(title: "Story \(i)", link: "https://example.com/\(i)")
            BookmarkManager.shared.addBookmark(story)
        }
        
        XCTAssertEqual(BookmarkManager.shared.count, 10)
    }
    
    func testRemoveMiddleBookmark() {
        let stories = (1...5).map { makeStory(title: "Story \($0)", link: "https://example.com/\($0)") }
        stories.forEach { BookmarkManager.shared.addBookmark($0) }
        
        BookmarkManager.shared.removeBookmark(stories[2]) // remove story 3
        
        XCTAssertEqual(BookmarkManager.shared.count, 4)
        XCTAssertFalse(BookmarkManager.shared.isBookmarked(stories[2]))
        XCTAssertTrue(BookmarkManager.shared.isBookmarked(stories[0]))
        XCTAssertTrue(BookmarkManager.shared.isBookmarked(stories[4]))
    }
    
    // MARK: - Notification
    
    func testBookmarkChangeNotification() {
        let story = makeStory()
        let expectation = self.expectation(forNotification: .bookmarksDidChange, object: nil)
        
        BookmarkManager.shared.addBookmark(story)
        
        wait(for: [expectation], timeout: 1.0)
    }
    
    func testRemoveNotification() {
        let story = makeStory()
        BookmarkManager.shared.addBookmark(story)
        
        let expectation = self.expectation(forNotification: .bookmarksDidChange, object: nil)
        BookmarkManager.shared.removeBookmark(story)
        
        wait(for: [expectation], timeout: 1.0)
    }
}
