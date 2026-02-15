//
//  FeedManagerTests.swift
//  FeedReaderTests
//
//  Tests for Feed model and FeedManager functionality including
//  CRUD operations, persistence, presets, custom feeds, and validation.
//

import XCTest
@testable import FeedReader

class FeedTests: XCTestCase {
    
    // MARK: - Feed Model Tests
    
    func testFeedInit() {
        let feed = Feed(name: "Test Feed", url: "https://example.com/rss.xml", isEnabled: true)
        XCTAssertEqual(feed.name, "Test Feed")
        XCTAssertEqual(feed.url, "https://example.com/rss.xml")
        XCTAssertTrue(feed.isEnabled)
    }
    
    func testFeedDefaultEnabled() {
        let feed = Feed(name: "Test", url: "https://example.com/rss.xml")
        XCTAssertTrue(feed.isEnabled, "Feed should be enabled by default")
    }
    
    func testFeedIdentifier() {
        let feed = Feed(name: "Test", url: "https://Example.COM/RSS.xml")
        XCTAssertEqual(feed.identifier, "https://example.com/rss.xml")
    }
    
    func testFeedEquality() {
        let feed1 = Feed(name: "Feed One", url: "https://example.com/rss.xml")
        let feed2 = Feed(name: "Feed Two", url: "https://example.com/rss.xml")
        XCTAssertEqual(feed1, feed2, "Feeds with same URL should be equal")
    }
    
    func testFeedInequality() {
        let feed1 = Feed(name: "Feed", url: "https://example.com/rss1.xml")
        let feed2 = Feed(name: "Feed", url: "https://example.com/rss2.xml")
        XCTAssertNotEqual(feed1, feed2, "Feeds with different URLs should not be equal")
    }
    
    func testFeedEqualityCaseInsensitive() {
        let feed1 = Feed(name: "Feed", url: "https://Example.COM/rss.xml")
        let feed2 = Feed(name: "Feed", url: "https://example.com/rss.xml")
        XCTAssertEqual(feed1, feed2, "Feed URL comparison should be case-insensitive")
    }
    
    func testPresetsExist() {
        XCTAssertGreaterThan(Feed.presets.count, 0, "Should have at least one preset feed")
    }
    
    func testPresetBBCWorldFirst() {
        let firstPreset = Feed.presets[0]
        XCTAssertEqual(firstPreset.name, "BBC World News")
        XCTAssertTrue(firstPreset.isEnabled)
    }
    
    func testPresetsHaveValidURLs() {
        for preset in Feed.presets {
            XCTAssertFalse(preset.name.isEmpty, "Preset name should not be empty")
            XCTAssertFalse(preset.url.isEmpty, "Preset URL should not be empty")
            XCTAssertNotNil(URL(string: preset.url), "Preset URL should be valid: \(preset.url)")
        }
    }
    
    func testFeedNSCoding() {
        let original = Feed(name: "Test Feed", url: "https://example.com/rss.xml", isEnabled: false)
        
        guard let data = try? NSKeyedArchiver.archivedData(withRootObject: original, requiringSecureCoding: true) else {
            XCTFail("Failed to archive Feed")
            return
        }
        
        guard let decoded = (try? NSKeyedUnarchiver.unarchivedObject(ofClass: Feed.self, from: data)) else {
            XCTFail("Failed to unarchive Feed")
            return
        }
        
        XCTAssertEqual(decoded.name, "Test Feed")
        XCTAssertEqual(decoded.url, "https://example.com/rss.xml")
        XCTAssertFalse(decoded.isEnabled)
    }
    
    func testFeedNSCodingEnabled() {
        let original = Feed(name: "Enabled Feed", url: "https://example.com/feed.xml", isEnabled: true)
        
        guard let data = try? NSKeyedArchiver.archivedData(withRootObject: original, requiringSecureCoding: true) else {
            XCTFail("Failed to archive Feed")
            return
        }
        
        guard let decoded = (try? NSKeyedUnarchiver.unarchivedObject(ofClass: Feed.self, from: data)) else {
            XCTFail("Failed to unarchive Feed")
            return
        }
        
        XCTAssertTrue(decoded.isEnabled)
    }
    
    func testFeedHashConsistency() {
        let feed1 = Feed(name: "A", url: "https://example.com/rss.xml")
        let feed2 = Feed(name: "B", url: "https://example.com/rss.xml")
        XCTAssertEqual(feed1.hash, feed2.hash, "Equal feeds should have equal hash values")
    }
}

class FeedManagerTests: XCTestCase {
    
    override func setUp() {
        super.setUp()
        FeedManager.shared.resetToDefaults()
    }
    
    // MARK: - Basic Operations
    
    func testInitialState() {
        XCTAssertGreaterThan(FeedManager.shared.count, 0, "Should have at least the default feed")
    }
    
    func testAddFeed() {
        let initialCount = FeedManager.shared.count
        let feed = Feed(name: "New Feed", url: "https://newsite.com/rss.xml")
        let added = FeedManager.shared.addFeed(feed)
        
        XCTAssertTrue(added, "Should successfully add a new feed")
        XCTAssertEqual(FeedManager.shared.count, initialCount + 1)
    }
    
    func testAddDuplicateFeed() {
        let feed = Feed(name: "Duplicate", url: "https://duplicate.com/rss.xml")
        FeedManager.shared.addFeed(feed)
        let initialCount = FeedManager.shared.count
        
        let duplicate = Feed(name: "Duplicate Again", url: "https://duplicate.com/rss.xml")
        let added = FeedManager.shared.addFeed(duplicate)
        
        XCTAssertFalse(added, "Should not add duplicate feed")
        XCTAssertEqual(FeedManager.shared.count, initialCount)
    }
    
    func testRemoveFeedByIndex() {
        let feed = Feed(name: "To Remove", url: "https://remove.com/rss.xml")
        FeedManager.shared.addFeed(feed)
        let indexToRemove = FeedManager.shared.count - 1
        let initialCount = FeedManager.shared.count
        
        FeedManager.shared.removeFeed(at: indexToRemove)
        XCTAssertEqual(FeedManager.shared.count, initialCount - 1)
    }
    
    func testRemoveFeedByObject() {
        let feed = Feed(name: "To Remove", url: "https://removethis.com/rss.xml")
        FeedManager.shared.addFeed(feed)
        let initialCount = FeedManager.shared.count
        
        FeedManager.shared.removeFeed(feed)
        XCTAssertEqual(FeedManager.shared.count, initialCount - 1)
        XCTAssertFalse(FeedManager.shared.feedExists(url: "https://removethis.com/rss.xml"))
    }
    
    func testRemoveFeedInvalidIndex() {
        let initialCount = FeedManager.shared.count
        FeedManager.shared.removeFeed(at: -1)
        FeedManager.shared.removeFeed(at: 9999)
        XCTAssertEqual(FeedManager.shared.count, initialCount, "Invalid index should not remove anything")
    }
    
    // MARK: - Toggle
    
    func testToggleFeed() {
        let feed = Feed(name: "Toggleable", url: "https://toggle.com/rss.xml", isEnabled: true)
        FeedManager.shared.addFeed(feed)
        let index = FeedManager.shared.count - 1
        
        let newState = FeedManager.shared.toggleFeed(at: index)
        XCTAssertFalse(newState, "Should be disabled after toggle")
        
        let newState2 = FeedManager.shared.toggleFeed(at: index)
        XCTAssertTrue(newState2, "Should be enabled after second toggle")
    }
    
    func testToggleInvalidIndex() {
        let result = FeedManager.shared.toggleFeed(at: -1)
        XCTAssertFalse(result, "Invalid index toggle should return false")
    }
    
    // MARK: - Enabled Feeds
    
    func testEnabledFeeds() {
        FeedManager.shared.resetToDefaults()
        let enabledFeed = Feed(name: "Enabled", url: "https://enabled.com/rss.xml", isEnabled: true)
        let disabledFeed = Feed(name: "Disabled", url: "https://disabled.com/rss.xml", isEnabled: false)
        
        FeedManager.shared.addFeed(enabledFeed)
        FeedManager.shared.addFeed(disabledFeed)
        
        let enabled = FeedManager.shared.enabledFeeds
        XCTAssertTrue(enabled.contains { $0.url == "https://enabled.com/rss.xml" })
        XCTAssertFalse(enabled.contains { $0.url == "https://disabled.com/rss.xml" })
    }
    
    func testEnabledURLs() {
        FeedManager.shared.resetToDefaults()
        let urls = FeedManager.shared.enabledURLs
        XCTAssertGreaterThan(urls.count, 0)
        for url in urls {
            XCTAssertFalse(url.isEmpty)
        }
    }
    
    // MARK: - Custom Feed
    
    func testAddCustomFeedValid() {
        let feed = FeedManager.shared.addCustomFeed(name: "Custom", url: "https://custom.com/feed.xml")
        XCTAssertNotNil(feed, "Should create feed with valid URL")
        XCTAssertEqual(feed?.name, "Custom")
        XCTAssertTrue(feed?.isEnabled ?? false)
    }
    
    func testAddCustomFeedInvalidURL() {
        let feed = FeedManager.shared.addCustomFeed(name: "Bad", url: "not-a-url")
        XCTAssertNil(feed, "Should reject invalid URL")
    }
    
    func testAddCustomFeedJavascriptURL() {
        let feed = FeedManager.shared.addCustomFeed(name: "XSS", url: "javascript:alert(1)")
        XCTAssertNil(feed, "Should reject javascript: URL")
    }
    
    func testAddCustomFeedFileURL() {
        let feed = FeedManager.shared.addCustomFeed(name: "File", url: "file:///etc/passwd")
        XCTAssertNil(feed, "Should reject file: URL")
    }
    
    func testAddCustomFeedDuplicate() {
        FeedManager.shared.addCustomFeed(name: "First", url: "https://dup.com/rss.xml")
        let second = FeedManager.shared.addCustomFeed(name: "Second", url: "https://dup.com/rss.xml")
        XCTAssertNil(second, "Should reject duplicate URL")
    }
    
    func testAddCustomFeedEmptyHost() {
        let feed = FeedManager.shared.addCustomFeed(name: "No Host", url: "https://")
        XCTAssertNil(feed, "Should reject URL with no host")
    }
    
    // MARK: - Feed Exists
    
    func testFeedExists() {
        FeedManager.shared.addFeed(Feed(name: "Exists", url: "https://exists.com/rss.xml"))
        XCTAssertTrue(FeedManager.shared.feedExists(url: "https://exists.com/rss.xml"))
        XCTAssertFalse(FeedManager.shared.feedExists(url: "https://notexists.com/rss.xml"))
    }
    
    // MARK: - Reorder
    
    func testMoveFeed() {
        FeedManager.shared.resetToDefaults()
        FeedManager.shared.addFeed(Feed(name: "Feed A", url: "https://feeda.com/rss.xml"))
        FeedManager.shared.addFeed(Feed(name: "Feed B", url: "https://feedb.com/rss.xml"))
        
        // Move last to first
        let lastIndex = FeedManager.shared.count - 1
        FeedManager.shared.moveFeed(from: lastIndex, to: 0)
        XCTAssertEqual(FeedManager.shared.feeds[0].name, "Feed B")
    }
    
    func testMoveFeedSameIndex() {
        let initialOrder = FeedManager.shared.feeds.map { $0.url }
        FeedManager.shared.moveFeed(from: 0, to: 0)
        let afterOrder = FeedManager.shared.feeds.map { $0.url }
        XCTAssertEqual(initialOrder, afterOrder, "Moving to same index should not change order")
    }
    
    func testMoveFeedInvalidIndex() {
        let initialCount = FeedManager.shared.count
        FeedManager.shared.moveFeed(from: -1, to: 0)
        FeedManager.shared.moveFeed(from: 0, to: 9999)
        XCTAssertEqual(FeedManager.shared.count, initialCount, "Invalid move should not change anything")
    }
    
    // MARK: - Preset
    
    func testAddPreset() {
        FeedManager.shared.resetToDefaults()
        // Preset at index 1 should be BBC Technology
        let added = FeedManager.shared.addPreset(at: 1)
        XCTAssertTrue(added)
        XCTAssertTrue(FeedManager.shared.feeds.contains { $0.name == "BBC Technology" })
    }
    
    func testAddPresetInvalidIndex() {
        let added = FeedManager.shared.addPreset(at: -1)
        XCTAssertFalse(added)
        let added2 = FeedManager.shared.addPreset(at: 9999)
        XCTAssertFalse(added2)
    }
    
    func testAddPresetDuplicate() {
        FeedManager.shared.resetToDefaults()
        // Default already has BBC World News (preset 0)
        let added = FeedManager.shared.addPreset(at: 0)
        XCTAssertFalse(added, "Should not add duplicate preset")
    }
    
    // MARK: - Reset
    
    func testResetToDefaults() {
        FeedManager.shared.addFeed(Feed(name: "Extra", url: "https://extra.com/rss.xml"))
        FeedManager.shared.addFeed(Feed(name: "More", url: "https://more.com/rss.xml"))
        
        FeedManager.shared.resetToDefaults()
        
        XCTAssertEqual(FeedManager.shared.count, 1, "Should have only default feed after reset")
        XCTAssertEqual(FeedManager.shared.feeds[0].name, "BBC World News")
    }
}
