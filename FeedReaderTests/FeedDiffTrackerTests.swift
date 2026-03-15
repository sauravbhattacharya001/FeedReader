//
//  FeedDiffTrackerTests.swift
//  FeedReaderTests
//
//  Tests for FeedDiffTracker — feed-level diff tracking between refreshes.
//

import XCTest
@testable import FeedReader

class FeedDiffTrackerTests: XCTestCase {
    
    var tracker: FeedDiffTracker!
    
    override func setUp() {
        super.setUp()
        tracker = FeedDiffTracker.shared
        tracker.clearAll()
    }
    
    override func tearDown() {
        tracker.clearAll()
        super.tearDown()
    }
    
    // MARK: - Helper
    
    private func makeStory(title: String, link: String) -> Story {
        return Story(title: title, photo: nil, description: "Body of \(title)",
                     link: link)!
    }
    
    // MARK: - StoryFingerprint Tests
    
    func testFingerprintEquality() {
        let a = StoryFingerprint(link: "https://example.com/1", title: "A")
        let b = StoryFingerprint(link: "https://example.com/1", title: "B different title")
        // Equality is link-based
        XCTAssertEqual(a, b)
    }
    
    func testFingerprintCaseInsensitiveLink() {
        let a = StoryFingerprint(link: "https://Example.com/PATH", title: "A")
        let b = StoryFingerprint(link: "https://example.com/path", title: "B")
        XCTAssertEqual(a, b)
    }
    
    func testFingerprintInequality() {
        let a = StoryFingerprint(link: "https://example.com/1", title: "A")
        let b = StoryFingerprint(link: "https://example.com/2", title: "A")
        XCTAssertNotEqual(a, b)
    }
    
    // MARK: - First Snapshot
    
    func testFirstSnapshotReturnsNil() {
        let stories = [makeStory(title: "S1", link: "https://example.com/1")]
        let diff = tracker.recordRefresh(feedURL: "https://feed.example.com/rss", stories: stories)
        XCTAssertNil(diff, "First snapshot should return nil diff")
    }
    
    func testFirstSnapshotStoresSnapshot() {
        let stories = [makeStory(title: "S1", link: "https://example.com/1")]
        tracker.recordRefresh(feedURL: "https://feed.example.com/rss", stories: stories)
        
        let snapshot = tracker.latestSnapshot(for: "https://feed.example.com/rss")
        XCTAssertNotNil(snapshot)
        XCTAssertEqual(snapshot?.storyCount, 1)
    }
    
    // MARK: - Diff Computation
    
    func testDiffDetectsNewStories() {
        let stories1 = [makeStory(title: "S1", link: "https://example.com/1")]
        tracker.recordRefresh(feedURL: "https://feed.example.com/rss", stories: stories1)
        
        let stories2 = [
            makeStory(title: "S1", link: "https://example.com/1"),
            makeStory(title: "S2", link: "https://example.com/2")
        ]
        let diff = tracker.recordRefresh(feedURL: "https://feed.example.com/rss", stories: stories2)
        
        XCTAssertNotNil(diff)
        XCTAssertEqual(diff?.added.count, 1)
        XCTAssertEqual(diff?.removed.count, 0)
        XCTAssertEqual(diff?.persisted.count, 1)
    }
    
    func testDiffDetectsRemovedStories() {
        let stories1 = [
            makeStory(title: "S1", link: "https://example.com/1"),
            makeStory(title: "S2", link: "https://example.com/2")
        ]
        tracker.recordRefresh(feedURL: "https://feed.example.com/rss", stories: stories1)
        
        let stories2 = [makeStory(title: "S1", link: "https://example.com/1")]
        let diff = tracker.recordRefresh(feedURL: "https://feed.example.com/rss", stories: stories2)
        
        XCTAssertEqual(diff?.added.count, 0)
        XCTAssertEqual(diff?.removed.count, 1)
        XCTAssertEqual(diff?.persisted.count, 1)
    }
    
    func testDiffCompleteReplacement() {
        let stories1 = [makeStory(title: "S1", link: "https://example.com/1")]
        tracker.recordRefresh(feedURL: "https://feed.example.com/rss", stories: stories1)
        
        let stories2 = [makeStory(title: "S2", link: "https://example.com/2")]
        let diff = tracker.recordRefresh(feedURL: "https://feed.example.com/rss", stories: stories2)
        
        XCTAssertEqual(diff?.added.count, 1)
        XCTAssertEqual(diff?.removed.count, 1)
        XCTAssertEqual(diff?.persisted.count, 0)
        XCTAssertEqual(diff?.churnRate, 1.0)
    }
    
    func testEmptyDiff() {
        let stories = [makeStory(title: "S1", link: "https://example.com/1")]
        tracker.recordRefresh(feedURL: "https://feed.example.com/rss", stories: stories)
        let diff = tracker.recordRefresh(feedURL: "https://feed.example.com/rss", stories: stories)
        
        XCTAssertNotNil(diff)
        XCTAssertTrue(diff!.isEmpty)
        XCTAssertEqual(diff?.churnRate, 0.0)
    }
    
    // MARK: - Queries
    
    func testLatestDiff() {
        let s1 = [makeStory(title: "A", link: "https://example.com/a")]
        let s2 = [makeStory(title: "B", link: "https://example.com/b")]
        
        tracker.recordRefresh(feedURL: "https://feed.example.com/rss", stories: s1)
        tracker.recordRefresh(feedURL: "https://feed.example.com/rss", stories: s2)
        
        let latest = tracker.latestDiff(for: "https://feed.example.com/rss")
        XCTAssertNotNil(latest)
        XCTAssertEqual(latest?.added.count, 1)
        XCTAssertEqual(latest?.added.first?.link, "https://example.com/b")
    }
    
    func testNewStoriesSince() {
        let s1 = [makeStory(title: "A", link: "https://example.com/a")]
        tracker.recordRefresh(feedURL: "https://feed.example.com/rss", stories: s1)
        
        let beforeAdd = Date()
        
        let s2 = [
            makeStory(title: "A", link: "https://example.com/a"),
            makeStory(title: "B", link: "https://example.com/b")
        ]
        tracker.recordRefresh(feedURL: "https://feed.example.com/rss", stories: s2)
        
        let newStories = tracker.newStoriesSince(beforeAdd)
        XCTAssertEqual(newStories.count, 1)
        XCTAssertEqual(newStories.first?.stories.count, 1)
    }
    
    // MARK: - Stats
    
    func testStats() {
        let s1 = [makeStory(title: "A", link: "https://example.com/a")]
        let s2 = [
            makeStory(title: "A", link: "https://example.com/a"),
            makeStory(title: "B", link: "https://example.com/b")
        ]
        let s3 = [makeStory(title: "B", link: "https://example.com/b")]
        
        tracker.recordRefresh(feedURL: "https://feed.example.com/rss", stories: s1)
        tracker.recordRefresh(feedURL: "https://feed.example.com/rss", stories: s2)
        tracker.recordRefresh(feedURL: "https://feed.example.com/rss", stories: s3)
        
        let stats = tracker.stats(for: "https://feed.example.com/rss")
        XCTAssertNotNil(stats)
        XCTAssertEqual(stats?.totalDiffs, 2)
        XCTAssertEqual(stats?.totalAdded, 1)   // B added in 2nd refresh
        XCTAssertEqual(stats?.totalRemoved, 1) // A removed in 3rd refresh
    }
    
    // MARK: - Summary
    
    func testDiffSummary() {
        let s1 = [makeStory(title: "A", link: "https://example.com/a")]
        let s2 = [
            makeStory(title: "A", link: "https://example.com/a"),
            makeStory(title: "B", link: "https://example.com/b"),
            makeStory(title: "C", link: "https://example.com/c")
        ]
        
        tracker.recordRefresh(feedURL: "https://feed.example.com/rss", stories: s1)
        let diff = tracker.recordRefresh(feedURL: "https://feed.example.com/rss", stories: s2)
        
        XCTAssertTrue(diff!.summary.contains("+2 new"))
        XCTAssertTrue(diff!.summary.contains("1 unchanged"))
    }
    
    // MARK: - URL Normalization
    
    func testURLNormalization() {
        let stories = [makeStory(title: "A", link: "https://example.com/a")]
        tracker.recordRefresh(feedURL: "https://Feed.Example.COM/rss", stories: stories)
        
        let snapshot = tracker.latestSnapshot(for: "https://feed.example.com/rss")
        XCTAssertNotNil(snapshot)
    }
    
    // MARK: - Multiple Feeds
    
    func testMultipleFeedsIndependent() {
        let s1 = [makeStory(title: "A", link: "https://example.com/a")]
        let s2 = [makeStory(title: "B", link: "https://example.com/b")]
        
        tracker.recordRefresh(feedURL: "https://feed1.com/rss", stories: s1)
        tracker.recordRefresh(feedURL: "https://feed2.com/rss", stories: s2)
        
        XCTAssertEqual(tracker.trackedFeeds.count, 2)
        
        let snap1 = tracker.latestSnapshot(for: "https://feed1.com/rss")
        let snap2 = tracker.latestSnapshot(for: "https://feed2.com/rss")
        
        XCTAssertEqual(snap1?.storyFingerprints.first?.link, "https://example.com/a")
        XCTAssertEqual(snap2?.storyFingerprints.first?.link, "https://example.com/b")
    }
    
    // MARK: - Maintenance
    
    func testClearHistory() {
        let stories = [makeStory(title: "A", link: "https://example.com/a")]
        tracker.recordRefresh(feedURL: "https://feed.example.com/rss", stories: stories)
        
        tracker.clearHistory(for: "https://feed.example.com/rss")
        
        XCTAssertNil(tracker.latestSnapshot(for: "https://feed.example.com/rss"))
        XCTAssertTrue(tracker.diffs(for: "https://feed.example.com/rss").isEmpty)
    }
    
    func testClearAll() {
        let stories = [makeStory(title: "A", link: "https://example.com/a")]
        tracker.recordRefresh(feedURL: "https://feed1.com/rss", stories: stories)
        tracker.recordRefresh(feedURL: "https://feed2.com/rss", stories: stories)
        
        tracker.clearAll()
        
        XCTAssertEqual(tracker.trackedFeeds.count, 0)
        XCTAssertEqual(tracker.totalDiffCount, 0)
    }
    
    // MARK: - Export
    
    func testExportJSON() {
        let s1 = [makeStory(title: "A", link: "https://example.com/a")]
        let s2 = [
            makeStory(title: "A", link: "https://example.com/a"),
            makeStory(title: "B", link: "https://example.com/b")
        ]
        
        tracker.recordRefresh(feedURL: "https://feed.example.com/rss", stories: s1)
        tracker.recordRefresh(feedURL: "https://feed.example.com/rss", stories: s2)
        
        let json = tracker.exportJSONString()
        XCTAssertNotNil(json)
        XCTAssertTrue(json!.contains("feed.example.com"))
    }
}
