//
//  FeedTests.swift
//  FeedReaderTests
//
//  Tests for the Feed data model — initialization, identity,
//  equality, NSSecureCoding, and preset feeds.
//

import XCTest
@testable import FeedReader

class FeedTests: XCTestCase {

    // MARK: - Initialization

    func testInitWithDefaults() {
        let feed = Feed(name: "Test Feed", url: "https://example.com/rss.xml")
        XCTAssertEqual(feed.name, "Test Feed")
        XCTAssertEqual(feed.url, "https://example.com/rss.xml")
        XCTAssertTrue(feed.isEnabled)
        XCTAssertNil(feed.category)
    }

    func testInitWithAllParameters() {
        let feed = Feed(name: "Tech News", url: "https://tech.example.com/feed",
                        isEnabled: false, category: "Technology")
        XCTAssertEqual(feed.name, "Tech News")
        XCTAssertEqual(feed.url, "https://tech.example.com/feed")
        XCTAssertFalse(feed.isEnabled)
        XCTAssertEqual(feed.category, "Technology")
    }

    func testInitDisabled() {
        let feed = Feed(name: "Disabled", url: "https://example.com/feed", isEnabled: false)
        XCTAssertFalse(feed.isEnabled)
    }

    // MARK: - Identifier

    func testIdentifierIsLowercasedURL() {
        let feed = Feed(name: "Test", url: "HTTPS://Example.COM/Feed")
        XCTAssertEqual(feed.identifier, "https://example.com/feed")
    }

    func testIdentifierIsDeterministic() {
        let feed1 = Feed(name: "A", url: "https://example.com/rss")
        let feed2 = Feed(name: "B", url: "https://example.com/rss")
        XCTAssertEqual(feed1.identifier, feed2.identifier)
    }

    func testIdentifierDiffersForDifferentURLs() {
        let feed1 = Feed(name: "A", url: "https://a.example.com/rss")
        let feed2 = Feed(name: "A", url: "https://b.example.com/rss")
        XCTAssertNotEqual(feed1.identifier, feed2.identifier)
    }

    // MARK: - Equality

    func testEqualityBasedOnURL() {
        let feed1 = Feed(name: "Feed One", url: "https://example.com/rss")
        let feed2 = Feed(name: "Feed Two", url: "https://example.com/rss")
        XCTAssertEqual(feed1, feed2, "Feeds with the same URL should be equal regardless of name")
    }

    func testEqualityCaseInsensitive() {
        let feed1 = Feed(name: "A", url: "https://EXAMPLE.com/RSS")
        let feed2 = Feed(name: "B", url: "https://example.com/rss")
        XCTAssertEqual(feed1, feed2, "URL comparison should be case-insensitive")
    }

    func testInequalityForDifferentURLs() {
        let feed1 = Feed(name: "Same", url: "https://a.example.com/feed")
        let feed2 = Feed(name: "Same", url: "https://b.example.com/feed")
        XCTAssertNotEqual(feed1, feed2)
    }

    func testIsEqualWithNonFeedObject() {
        let feed = Feed(name: "Test", url: "https://example.com")
        XCTAssertFalse(feed.isEqual("not a feed"))
        XCTAssertFalse(feed.isEqual(nil))
        XCTAssertFalse(feed.isEqual(42))
    }

    // MARK: - Hash

    func testHashConsistentWithEquality() {
        let feed1 = Feed(name: "A", url: "https://example.com/rss")
        let feed2 = Feed(name: "B", url: "https://example.com/rss")
        XCTAssertEqual(feed1.hash, feed2.hash,
                       "Equal feeds must produce the same hash")
    }

    func testHashDiffersForDifferentFeeds() {
        let feed1 = Feed(name: "A", url: "https://a.example.com/rss")
        let feed2 = Feed(name: "A", url: "https://b.example.com/rss")
        XCTAssertNotEqual(feed1.hash, feed2.hash)
    }

    func testFeedsWorkInSet() {
        let feed1 = Feed(name: "A", url: "https://example.com/rss")
        let feed2 = Feed(name: "B", url: "https://example.com/rss")
        let feed3 = Feed(name: "C", url: "https://other.example.com/rss")
        let set: Set<Feed> = [feed1, feed2, feed3]
        XCTAssertEqual(set.count, 2, "Set should deduplicate feeds with same URL")
    }

    // MARK: - NSSecureCoding

    func testSupportsSecureCoding() {
        XCTAssertTrue(Feed.supportsSecureCoding)
    }

    func testArchiveAndUnarchive() throws {
        let original = Feed(name: "BBC", url: "https://feeds.bbc.co.uk/news/rss.xml",
                            isEnabled: true, category: "News")

        let data = try NSKeyedArchiver.archivedData(withRootObject: original,
                                                     requiringSecureCoding: true)
        let decoded = try NSKeyedUnarchiver.unarchivedObject(ofClass: Feed.self, from: data)

        XCTAssertNotNil(decoded)
        XCTAssertEqual(decoded?.name, "BBC")
        XCTAssertEqual(decoded?.url, "https://feeds.bbc.co.uk/news/rss.xml")
        XCTAssertTrue(decoded?.isEnabled ?? false)
        XCTAssertEqual(decoded?.category, "News")
    }

    func testArchiveAndUnarchiveWithoutCategory() throws {
        let original = Feed(name: "No Cat", url: "https://example.com/feed", isEnabled: false)

        let data = try NSKeyedArchiver.archivedData(withRootObject: original,
                                                     requiringSecureCoding: true)
        let decoded = try NSKeyedUnarchiver.unarchivedObject(ofClass: Feed.self, from: data)

        XCTAssertNotNil(decoded)
        XCTAssertEqual(decoded?.name, "No Cat")
        XCTAssertFalse(decoded?.isEnabled ?? true)
        XCTAssertNil(decoded?.category)
    }

    func testArchivePreservesEquality() throws {
        let original = Feed(name: "Test", url: "https://example.com/rss")

        let data = try NSKeyedArchiver.archivedData(withRootObject: original,
                                                     requiringSecureCoding: true)
        let decoded = try NSKeyedUnarchiver.unarchivedObject(ofClass: Feed.self, from: data)

        XCTAssertEqual(original, decoded)
    }

    // MARK: - Presets

    func testPresetsNotEmpty() {
        XCTAssertFalse(Feed.presets.isEmpty, "Should have built-in preset feeds")
    }

    func testPresetsHaveValidURLs() {
        for feed in Feed.presets {
            XCTAssertFalse(feed.name.isEmpty, "Preset feed name should not be empty")
            XCTAssertFalse(feed.url.isEmpty, "Preset feed URL should not be empty")
            XCTAssertNotNil(URL(string: feed.url), "Preset URL '\(feed.url)' should be a valid URL")
            XCTAssertTrue(feed.url.hasPrefix("https://"),
                          "Preset URL '\(feed.url)' should use HTTPS")
        }
    }

    func testPresetsHaveUniqueURLs() {
        let urls = Feed.presets.map { $0.identifier }
        let uniqueURLs = Set(urls)
        XCTAssertEqual(urls.count, uniqueURLs.count, "Preset feeds should have unique URLs")
    }

    func testPresetsHaveUniqueNames() {
        let names = Feed.presets.map { $0.name }
        let uniqueNames = Set(names)
        XCTAssertEqual(names.count, uniqueNames.count, "Preset feeds should have unique names")
    }

    func testPresetsDefaultEnablement() {
        let enabledPresets = Feed.presets.filter { $0.isEnabled }
        XCTAssertEqual(enabledPresets.count, 1,
                       "Exactly one preset should be enabled by default")
        XCTAssertEqual(enabledPresets.first?.name, "BBC World News")
    }

    func testPresetsKnownFeeds() {
        let names = Set(Feed.presets.map { $0.name })
        XCTAssertTrue(names.contains("BBC World News"))
        XCTAssertTrue(names.contains("Hacker News"))
        XCTAssertTrue(names.contains("TechCrunch"))
    }

    // MARK: - Mutability

    func testMutableProperties() {
        let feed = Feed(name: "Original", url: "https://example.com/feed")
        feed.name = "Updated"
        feed.isEnabled = false
        feed.category = "Tech"
        XCTAssertEqual(feed.name, "Updated")
        XCTAssertFalse(feed.isEnabled)
        XCTAssertEqual(feed.category, "Tech")
    }

    func testCategoryCanBeCleared() {
        let feed = Feed(name: "Test", url: "https://example.com", category: "News")
        XCTAssertEqual(feed.category, "News")
        feed.category = nil
        XCTAssertNil(feed.category)
    }
}
