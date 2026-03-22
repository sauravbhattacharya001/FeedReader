//
//  ReadingPositionManagerTests.swift
//  FeedReaderTests
//

import XCTest
@testable import FeedReader

class ReadingPositionManagerTests: XCTestCase {
    
    var manager: ReadingPositionManager!
    
    override func setUp() {
        super.setUp()
        manager = ReadingPositionManager.shared
        manager.clearAll()
    }
    
    override func tearDown() {
        manager.clearAll()
        super.tearDown()
    }
    
    // MARK: - Save & Retrieve
    
    func testSaveAndRetrievePosition() {
        manager.savePosition(for: "https://example.com/article1", percentage: 0.5, title: "Test Article")
        
        let pos = manager.position(for: "https://example.com/article1")
        XCTAssertNotNil(pos)
        XCTAssertEqual(pos?.percentage, 0.5, accuracy: 0.001)
        XCTAssertEqual(pos?.title, "Test Article")
    }
    
    func testNonExistentArticleReturnsNil() {
        let pos = manager.position(for: "https://example.com/nonexistent")
        XCTAssertNil(pos)
    }
    
    // MARK: - Auto-removal at Extremes
    
    func testNearTopPositionNotSaved() {
        manager.savePosition(for: "https://example.com/a", percentage: 0.01)
        XCTAssertNil(manager.position(for: "https://example.com/a"))
    }
    
    func testNearBottomPositionAutoCleared() {
        // First save a mid-point
        manager.savePosition(for: "https://example.com/b", percentage: 0.5)
        XCTAssertNotNil(manager.position(for: "https://example.com/b"))
        
        // Then scroll to end — should be removed
        manager.savePosition(for: "https://example.com/b", percentage: 0.99)
        XCTAssertNil(manager.position(for: "https://example.com/b"))
    }
    
    // MARK: - Percentage Clamping
    
    func testPercentageClampedToValidRange() {
        manager.savePosition(for: "https://example.com/c", percentage: -0.5)
        // Negative gets clamped to 0, which is < minimum, so not saved
        XCTAssertNil(manager.position(for: "https://example.com/c"))
        
        manager.savePosition(for: "https://example.com/d", percentage: 1.5)
        // > 0.97, so auto-cleared as "finished"
        XCTAssertNil(manager.position(for: "https://example.com/d"))
    }
    
    // MARK: - In-Progress List
    
    func testInProgressArticlesSortedByRecent() {
        manager.savePosition(for: "https://example.com/old", percentage: 0.3, title: "Old")
        // Small delay to ensure different timestamps
        Thread.sleep(forTimeInterval: 0.01)
        manager.savePosition(for: "https://example.com/new", percentage: 0.7, title: "New")
        
        let list = manager.inProgressArticles()
        XCTAssertEqual(list.count, 2)
        XCTAssertEqual(list.first?.url, "https://example.com/new")
    }
    
    // MARK: - Clear
    
    func testClearPositionRemovesEntry() {
        manager.savePosition(for: "https://example.com/e", percentage: 0.5)
        manager.clearPosition(for: "https://example.com/e")
        XCTAssertNil(manager.position(for: "https://example.com/e"))
    }
    
    func testClearAllRemovesEverything() {
        manager.savePosition(for: "https://example.com/f", percentage: 0.4)
        manager.savePosition(for: "https://example.com/g", percentage: 0.6)
        XCTAssertEqual(manager.count, 2)
        
        manager.clearAll()
        XCTAssertEqual(manager.count, 0)
    }
    
    // MARK: - Update Overwrites
    
    func testUpdatingPositionOverwritesPrevious() {
        manager.savePosition(for: "https://example.com/h", percentage: 0.3)
        manager.savePosition(for: "https://example.com/h", percentage: 0.8)
        
        let pos = manager.position(for: "https://example.com/h")
        XCTAssertEqual(pos?.percentage, 0.8, accuracy: 0.001)
    }
}
