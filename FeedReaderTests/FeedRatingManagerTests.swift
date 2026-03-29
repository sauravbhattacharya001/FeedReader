//
//  FeedRatingManagerTests.swift
//  FeedReaderTests
//
//  Tests for the feed rating system.
//

import XCTest
@testable import FeedReader

class FeedRatingManagerTests: XCTestCase {
    
    var manager: FeedRatingManager!
    
    override func setUp() {
        super.setUp()
        manager = FeedRatingManager.shared
        manager.clearAllRatings()
    }
    
    override func tearDown() {
        manager.clearAllRatings()
        super.tearDown()
    }
    
    // MARK: - Rating Tests
    
    func testSetAndGetRating() {
        let feed = Feed(name: "Test", url: "https://example.com/feed")
        XCTAssertNil(manager.rating(for: feed))
        
        manager.setRating(4, for: feed)
        XCTAssertEqual(manager.rating(for: feed), 4)
    }
    
    func testRatingClamping() {
        manager.setRating(10, forIdentifier: "test")
        XCTAssertEqual(manager.rating(forIdentifier: "test"), 5)
        
        manager.setRating(-1, forIdentifier: "test")
        XCTAssertEqual(manager.rating(forIdentifier: "test"), 1)
    }
    
    func testClearRating() {
        manager.setRating(3, forIdentifier: "test")
        manager.setRating(nil, forIdentifier: "test")
        XCTAssertNil(manager.rating(forIdentifier: "test"))
    }
    
    // MARK: - Star String Tests
    
    func testStarString() {
        XCTAssertEqual(FeedRatingManager.starString(for: 0), "☆☆☆☆☆")
        XCTAssertEqual(FeedRatingManager.starString(for: 3), "★★★☆☆")
        XCTAssertEqual(FeedRatingManager.starString(for: 5), "★★★★★")
    }
    
    // MARK: - Sorting Tests
    
    func testSortByRating() {
        let feedA = Feed(name: "A", url: "https://a.com/feed")
        let feedB = Feed(name: "B", url: "https://b.com/feed")
        let feedC = Feed(name: "C", url: "https://c.com/feed")
        
        manager.setRating(2, for: feedA)
        manager.setRating(5, for: feedB)
        // feedC unrated
        
        let sorted = manager.sortedByRating([feedA, feedB, feedC])
        XCTAssertEqual(sorted[0].name, "B")
        XCTAssertEqual(sorted[1].name, "A")
        XCTAssertEqual(sorted[2].name, "C")
    }
    
    // MARK: - Distribution Tests
    
    func testRatingDistribution() {
        manager.setRating(5, forIdentifier: "a")
        manager.setRating(5, forIdentifier: "b")
        manager.setRating(3, forIdentifier: "c")
        
        let dist = manager.ratingDistribution()
        XCTAssertEqual(dist[5], 2)
        XCTAssertEqual(dist[3], 1)
        XCTAssertEqual(dist[1], 0)
    }
    
    // MARK: - Average Tests
    
    func testAverageRating() {
        XCTAssertNil(manager.averageRating())
        
        manager.setRating(4, forIdentifier: "a")
        manager.setRating(2, forIdentifier: "b")
        XCTAssertEqual(manager.averageRating(), 3.0)
    }
    
    // MARK: - Import/Export Tests
    
    func testExportImport() {
        manager.setRating(3, forIdentifier: "feed1")
        manager.setRating(5, forIdentifier: "feed2")
        
        let exported = manager.exportRatings()
        manager.clearAllRatings()
        XCTAssertEqual(manager.ratedCount, 0)
        
        manager.importRatings(exported)
        XCTAssertEqual(manager.rating(forIdentifier: "feed1"), 3)
        XCTAssertEqual(manager.rating(forIdentifier: "feed2"), 5)
    }
    
    // MARK: - Filter Tests
    
    func testMinimumRatingFilter() {
        let feedA = Feed(name: "A", url: "https://a.com/feed")
        let feedB = Feed(name: "B", url: "https://b.com/feed")
        
        manager.setRating(2, for: feedA)
        manager.setRating(4, for: feedB)
        
        let filtered = manager.feeds([feedA, feedB], withMinimumRating: 3)
        XCTAssertEqual(filtered.count, 1)
        XCTAssertEqual(filtered[0].name, "B")
    }
}
