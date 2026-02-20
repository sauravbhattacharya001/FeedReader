//
//  ReadStatusTests.swift
//  FeedReaderTests
//
//  Tests for ReadStatusManager — mark read/unread, toggle, filter,
//  count, persistence, edge cases.
//

import XCTest
@testable import FeedReader

class ReadStatusTests: XCTestCase {
    
    // MARK: - Helpers
    
    private func makeStory(title: String = "Test Story", description: String = "A test description", link: String = "https://example.com/story1") -> Story {
        return Story(title: title, photo: nil, description: description, link: link)!
    }
    
    override func setUp() {
        super.setUp()
        ReadStatusManager.shared.clearAll()
    }
    
    override func tearDown() {
        ReadStatusManager.shared.clearAll()
        super.tearDown()
    }
    
    // MARK: - Mark Read
    
    func testMarkAsRead() {
        let story = makeStory()
        ReadStatusManager.shared.markAsRead(story)
        
        XCTAssertTrue(ReadStatusManager.shared.isRead(story))
    }
    
    func testMarkAsReadReturnsTrueWhenNewlyMarked() {
        let story = makeStory()
        let result = ReadStatusManager.shared.markAsRead(story)
        
        XCTAssertTrue(result, "Should return true for newly marked story")
    }
    
    func testMarkAsReadReturnsFalseWhenAlreadyRead() {
        let story = makeStory()
        ReadStatusManager.shared.markAsRead(story)
        let result = ReadStatusManager.shared.markAsRead(story)
        
        XCTAssertFalse(result, "Should return false when already read")
    }
    
    func testMarkAsReadByLink() {
        let link = "https://example.com/test"
        ReadStatusManager.shared.markAsRead(link: link)
        
        XCTAssertTrue(ReadStatusManager.shared.isRead(link: link))
    }
    
    // MARK: - Mark Unread
    
    func testMarkAsUnread() {
        let story = makeStory()
        ReadStatusManager.shared.markAsRead(story)
        ReadStatusManager.shared.markAsUnread(story)
        
        XCTAssertFalse(ReadStatusManager.shared.isRead(story))
    }
    
    func testMarkAsUnreadReturnsTrueWhenWasRead() {
        let story = makeStory()
        ReadStatusManager.shared.markAsRead(story)
        let result = ReadStatusManager.shared.markAsUnread(story)
        
        XCTAssertTrue(result, "Should return true when story was previously read")
    }
    
    func testMarkAsUnreadReturnsFalseWhenAlreadyUnread() {
        let story = makeStory()
        let result = ReadStatusManager.shared.markAsUnread(story)
        
        XCTAssertFalse(result, "Should return false when already unread")
    }
    
    func testMarkAsUnreadByLink() {
        let link = "https://example.com/test"
        ReadStatusManager.shared.markAsRead(link: link)
        ReadStatusManager.shared.markAsUnread(link: link)
        
        XCTAssertFalse(ReadStatusManager.shared.isRead(link: link))
    }
    
    // MARK: - Toggle
    
    func testToggleMarksAsRead() {
        let story = makeStory()
        let result = ReadStatusManager.shared.toggleReadStatus(story)
        
        XCTAssertTrue(result, "Toggle should return true when marking as read")
        XCTAssertTrue(ReadStatusManager.shared.isRead(story))
    }
    
    func testToggleMarksAsUnread() {
        let story = makeStory()
        ReadStatusManager.shared.markAsRead(story)
        let result = ReadStatusManager.shared.toggleReadStatus(story)
        
        XCTAssertFalse(result, "Toggle should return false when marking as unread")
        XCTAssertFalse(ReadStatusManager.shared.isRead(story))
    }
    
    func testDoubleToggle() {
        let story = makeStory()
        ReadStatusManager.shared.toggleReadStatus(story) // read
        ReadStatusManager.shared.toggleReadStatus(story) // unread
        
        XCTAssertFalse(ReadStatusManager.shared.isRead(story))
    }
    
    // MARK: - isRead
    
    func testIsReadDefaultsFalse() {
        let story = makeStory(link: "https://example.com/never-read")
        XCTAssertFalse(ReadStatusManager.shared.isRead(story))
    }
    
    func testIsReadMatchesByLink() {
        let story1 = makeStory(title: "Title A", link: "https://example.com/same")
        ReadStatusManager.shared.markAsRead(story1)
        
        // Different title, same link — should be considered read
        let story2 = makeStory(title: "Title B", link: "https://example.com/same")
        XCTAssertTrue(ReadStatusManager.shared.isRead(story2), "Read status should match by link URL")
    }
    
    // MARK: - Mark All Read
    
    func testMarkAllAsRead() {
        let stories = (1...5).map { makeStory(title: "Story \($0)", link: "https://example.com/\($0)") }
        
        ReadStatusManager.shared.markAllAsRead(stories)
        
        for story in stories {
            XCTAssertTrue(ReadStatusManager.shared.isRead(story), "\(story.title) should be read")
        }
    }
    
    func testMarkAllAsReadWithSomeAlreadyRead() {
        let stories = (1...5).map { makeStory(title: "Story \($0)", link: "https://example.com/\($0)") }
        ReadStatusManager.shared.markAsRead(stories[0])
        ReadStatusManager.shared.markAsRead(stories[2])
        
        ReadStatusManager.shared.markAllAsRead(stories)
        
        for story in stories {
            XCTAssertTrue(ReadStatusManager.shared.isRead(story))
        }
    }
    
    func testMarkAllAsReadEmptyArray() {
        ReadStatusManager.shared.markAllAsRead([])
        XCTAssertEqual(ReadStatusManager.shared.readCount, 0)
    }
    
    // MARK: - Unread Count
    
    func testUnreadCountAllUnread() {
        let stories = (1...5).map { makeStory(title: "Story \($0)", link: "https://example.com/\($0)") }
        
        XCTAssertEqual(ReadStatusManager.shared.unreadCount(in: stories), 5)
    }
    
    func testUnreadCountSomeRead() {
        let stories = (1...5).map { makeStory(title: "Story \($0)", link: "https://example.com/\($0)") }
        ReadStatusManager.shared.markAsRead(stories[0])
        ReadStatusManager.shared.markAsRead(stories[2])
        
        XCTAssertEqual(ReadStatusManager.shared.unreadCount(in: stories), 3)
    }
    
    func testUnreadCountAllRead() {
        let stories = (1...5).map { makeStory(title: "Story \($0)", link: "https://example.com/\($0)") }
        ReadStatusManager.shared.markAllAsRead(stories)
        
        XCTAssertEqual(ReadStatusManager.shared.unreadCount(in: stories), 0)
    }
    
    func testUnreadCountEmptyArray() {
        XCTAssertEqual(ReadStatusManager.shared.unreadCount(in: []), 0)
    }
    
    // MARK: - Filter
    
    func testFilterAll() {
        let stories = (1...5).map { makeStory(title: "Story \($0)", link: "https://example.com/\($0)") }
        ReadStatusManager.shared.markAsRead(stories[0])
        
        let result = ReadStatusManager.shared.filterStories(stories, readStatus: .all)
        XCTAssertEqual(result.count, 5)
    }
    
    func testFilterUnread() {
        let stories = (1...5).map { makeStory(title: "Story \($0)", link: "https://example.com/\($0)") }
        ReadStatusManager.shared.markAsRead(stories[0])
        ReadStatusManager.shared.markAsRead(stories[2])
        
        let result = ReadStatusManager.shared.filterStories(stories, readStatus: .unread)
        XCTAssertEqual(result.count, 3)
        XCTAssertFalse(result.contains { $0.link == "https://example.com/1" })
        XCTAssertFalse(result.contains { $0.link == "https://example.com/3" })
    }
    
    func testFilterRead() {
        let stories = (1...5).map { makeStory(title: "Story \($0)", link: "https://example.com/\($0)") }
        ReadStatusManager.shared.markAsRead(stories[0])
        ReadStatusManager.shared.markAsRead(stories[2])
        
        let result = ReadStatusManager.shared.filterStories(stories, readStatus: .read)
        XCTAssertEqual(result.count, 2)
        XCTAssertTrue(result.contains { $0.link == "https://example.com/1" })
        XCTAssertTrue(result.contains { $0.link == "https://example.com/3" })
    }
    
    func testFilterUnreadWithNoneRead() {
        let stories = (1...3).map { makeStory(title: "Story \($0)", link: "https://example.com/\($0)") }
        
        let result = ReadStatusManager.shared.filterStories(stories, readStatus: .unread)
        XCTAssertEqual(result.count, 3)
    }
    
    func testFilterReadWithNoneRead() {
        let stories = (1...3).map { makeStory(title: "Story \($0)", link: "https://example.com/\($0)") }
        
        let result = ReadStatusManager.shared.filterStories(stories, readStatus: .read)
        XCTAssertEqual(result.count, 0)
    }
    
    // MARK: - Clear All
    
    func testClearAll() {
        let stories = (1...5).map { makeStory(title: "Story \($0)", link: "https://example.com/\($0)") }
        ReadStatusManager.shared.markAllAsRead(stories)
        
        ReadStatusManager.shared.clearAll()
        
        XCTAssertEqual(ReadStatusManager.shared.readCount, 0)
        for story in stories {
            XCTAssertFalse(ReadStatusManager.shared.isRead(story))
        }
    }
    
    func testClearAllWhenEmpty() {
        ReadStatusManager.shared.clearAll()
        XCTAssertEqual(ReadStatusManager.shared.readCount, 0)
    }
    
    // MARK: - Read Count
    
    func testReadCount() {
        let stories = (1...5).map { makeStory(title: "Story \($0)", link: "https://example.com/\($0)") }
        ReadStatusManager.shared.markAsRead(stories[0])
        ReadStatusManager.shared.markAsRead(stories[2])
        ReadStatusManager.shared.markAsRead(stories[4])
        
        XCTAssertEqual(ReadStatusManager.shared.readCount, 3)
    }
    
    func testReadCountAfterToggle() {
        let story = makeStory()
        ReadStatusManager.shared.markAsRead(story)
        XCTAssertEqual(ReadStatusManager.shared.readCount, 1)
        
        ReadStatusManager.shared.markAsUnread(story)
        XCTAssertEqual(ReadStatusManager.shared.readCount, 0)
    }
    
    // MARK: - Multiple Stories
    
    func testMultipleStoriesIndependent() {
        let story1 = makeStory(title: "Story 1", link: "https://example.com/1")
        let story2 = makeStory(title: "Story 2", link: "https://example.com/2")
        
        ReadStatusManager.shared.markAsRead(story1)
        
        XCTAssertTrue(ReadStatusManager.shared.isRead(story1))
        XCTAssertFalse(ReadStatusManager.shared.isRead(story2))
    }
    
    func testManyStories() {
        for i in 1...100 {
            let story = makeStory(title: "Story \(i)", link: "https://example.com/\(i)")
            ReadStatusManager.shared.markAsRead(story)
        }
        
        XCTAssertEqual(ReadStatusManager.shared.readCount, 100)
    }
    
    // MARK: - Notification
    
    func testMarkAsReadNotification() {
        let story = makeStory()
        let expectation = self.expectation(forNotification: .readStatusDidChange, object: nil)
        
        ReadStatusManager.shared.markAsRead(story)
        
        wait(for: [expectation], timeout: 1.0)
    }
    
    func testMarkAsUnreadNotification() {
        let story = makeStory()
        ReadStatusManager.shared.markAsRead(story)
        
        let expectation = self.expectation(forNotification: .readStatusDidChange, object: nil)
        ReadStatusManager.shared.markAsUnread(story)
        
        wait(for: [expectation], timeout: 1.0)
    }
    
    func testToggleNotification() {
        let story = makeStory()
        let expectation = self.expectation(forNotification: .readStatusDidChange, object: nil)
        
        ReadStatusManager.shared.toggleReadStatus(story)
        
        wait(for: [expectation], timeout: 1.0)
    }
    
    func testMarkAllReadNotification() {
        let stories = (1...3).map { makeStory(title: "Story \($0)", link: "https://example.com/\($0)") }
        let expectation = self.expectation(forNotification: .readStatusDidChange, object: nil)
        
        ReadStatusManager.shared.markAllAsRead(stories)
        
        wait(for: [expectation], timeout: 1.0)
    }
    
    func testClearAllNotification() {
        let story = makeStory()
        ReadStatusManager.shared.markAsRead(story)
        
        let expectation = self.expectation(forNotification: .readStatusDidChange, object: nil)
        ReadStatusManager.shared.clearAll()
        
        wait(for: [expectation], timeout: 1.0)
    }
    
    func testNoNotificationWhenAlreadyRead() {
        let story = makeStory()
        ReadStatusManager.shared.markAsRead(story)
        
        // Second markAsRead should NOT fire notification
        let expectation = self.expectation(forNotification: .readStatusDidChange, object: nil)
        expectation.isInverted = true
        
        ReadStatusManager.shared.markAsRead(story)
        
        wait(for: [expectation], timeout: 0.5)
    }
    
    func testNoNotificationWhenAlreadyUnread() {
        let story = makeStory()
        
        // markAsUnread on an unread story should NOT fire notification
        let expectation = self.expectation(forNotification: .readStatusDidChange, object: nil)
        expectation.isInverted = true
        
        ReadStatusManager.shared.markAsUnread(story)
        
        wait(for: [expectation], timeout: 0.5)
    }
    
    // MARK: - ReadFilter Enum
    
    func testReadFilterTitles() {
        XCTAssertEqual(ReadStatusManager.ReadFilter.all.title, "All")
        XCTAssertEqual(ReadStatusManager.ReadFilter.unread.title, "Unread")
        XCTAssertEqual(ReadStatusManager.ReadFilter.read.title, "Read")
    }
    
    func testReadFilterRawValues() {
        XCTAssertEqual(ReadStatusManager.ReadFilter.all.rawValue, 0)
        XCTAssertEqual(ReadStatusManager.ReadFilter.unread.rawValue, 1)
        XCTAssertEqual(ReadStatusManager.ReadFilter.read.rawValue, 2)
    }
    
    func testReadFilterAllCases() {
        XCTAssertEqual(ReadStatusManager.ReadFilter.allCases.count, 3)
    }
}
