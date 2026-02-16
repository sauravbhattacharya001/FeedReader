//
//  RSSStoryTests.swift
//  FeedReaderCoreTests
//
//  Tests for the RSSStory model and HTML sanitization.
//

import XCTest
@testable import FeedReaderCore

final class RSSStoryTests: XCTestCase {

    func testValidStoryCreation() {
        let story = RSSStory(
            title: "Test Title",
            body: "Test body content",
            link: "https://example.com/story"
        )
        XCTAssertNotNil(story)
        XCTAssertEqual(story?.title, "Test Title")
        XCTAssertEqual(story?.body, "Test body content")
        XCTAssertEqual(story?.link, "https://example.com/story")
        XCTAssertNil(story?.imagePath)
    }

    func testStoryWithImagePath() {
        let story = RSSStory(
            title: "With Image",
            body: "Has image",
            link: "https://example.com/1",
            imagePath: "https://cdn.example.com/img.jpg"
        )
        XCTAssertNotNil(story)
        XCTAssertEqual(story?.imagePath, "https://cdn.example.com/img.jpg")
    }

    func testStoryRejectsUnsafeImagePath() {
        let story = RSSStory(
            title: "Unsafe Image",
            body: "Has unsafe image",
            link: "https://example.com/2",
            imagePath: "javascript:alert(1)"
        )
        XCTAssertNotNil(story) // Story created, but imagePath is nil
        XCTAssertNil(story?.imagePath)
    }

    func testStoryRejectsEmptyTitle() {
        let story = RSSStory(title: "", body: "Content", link: "https://example.com")
        XCTAssertNil(story)
    }

    func testStoryRejectsEmptyBody() {
        let story = RSSStory(title: "Title", body: "", link: "https://example.com")
        XCTAssertNil(story)
    }

    func testStoryRejectsUnsafeLink() {
        let story = RSSStory(
            title: "Title",
            body: "Content",
            link: "javascript:void(0)"
        )
        XCTAssertNil(story)
    }

    func testIsSafeURL() {
        XCTAssertTrue(RSSStory.isSafeURL("https://example.com"))
        XCTAssertTrue(RSSStory.isSafeURL("http://example.com"))
        XCTAssertFalse(RSSStory.isSafeURL("javascript:alert(1)"))
        XCTAssertFalse(RSSStory.isSafeURL("file:///etc/passwd"))
        XCTAssertFalse(RSSStory.isSafeURL("data:text/html,<h1>"))
        XCTAssertFalse(RSSStory.isSafeURL(nil))
        XCTAssertFalse(RSSStory.isSafeURL(""))
    }

    func testStripHTML() {
        XCTAssertEqual(
            RSSStory.stripHTML("<p>Hello <b>world</b></p>"),
            "Hello world"
        )
    }

    func testStripHTMLDecodesEntities() {
        XCTAssertEqual(
            RSSStory.stripHTML("Tom &amp; Jerry &lt;3"),
            "Tom & Jerry <3"
        )
    }

    func testStripHTMLHandlesNoEntities() {
        XCTAssertEqual(RSSStory.stripHTML("plain text"), "plain text")
    }

    func testEqualityByLink() {
        let a = RSSStory(title: "A", body: "Body A", link: "https://x.com/1")
        let b = RSSStory(title: "B", body: "Body B", link: "https://x.com/1")
        XCTAssertEqual(a, b)
    }

    func testInequalityByLink() {
        let a = RSSStory(title: "A", body: "Body", link: "https://x.com/1")
        let b = RSSStory(title: "A", body: "Body", link: "https://x.com/2")
        XCTAssertNotEqual(a, b)
    }
}

final class FeedItemTests: XCTestCase {

    func testFeedItemCreation() {
        let feed = FeedItem(name: "Test Feed", url: "https://example.com/rss")
        XCTAssertEqual(feed.name, "Test Feed")
        XCTAssertEqual(feed.url, "https://example.com/rss")
        XCTAssertFalse(feed.isEnabled)
    }

    func testFeedItemEnabled() {
        let feed = FeedItem(name: "Feed", url: "https://example.com/rss", isEnabled: true)
        XCTAssertTrue(feed.isEnabled)
    }

    func testFeedItemIdentifier() {
        let feed = FeedItem(name: "Feed", url: "HTTPS://Example.COM/RSS")
        XCTAssertEqual(feed.identifier, "https://example.com/rss")
    }

    func testFeedItemEquality() {
        let a = FeedItem(name: "A", url: "https://x.com/feed")
        let b = FeedItem(name: "B", url: "https://x.com/feed")
        XCTAssertEqual(a, b) // Same URL = equal
    }

    func testPresetsNotEmpty() {
        XCTAssertFalse(FeedItem.presets.isEmpty)
        XCTAssertGreaterThanOrEqual(FeedItem.presets.count, 5)
    }
}

final class RSSParserTests: XCTestCase {

    func testParseValidRSS() {
        let xml = """
        <?xml version="1.0" encoding="UTF-8"?>
        <rss version="2.0">
        <channel>
          <title>Test Feed</title>
          <item>
            <title>Story One</title>
            <description>First story description</description>
            <guid>https://example.com/story-1</guid>
          </item>
          <item>
            <title>Story Two</title>
            <description>Second story description</description>
            <guid>https://example.com/story-2</guid>
          </item>
        </channel>
        </rss>
        """.data(using: .utf8)!

        let parser = RSSParser()
        let stories = parser.parseData(xml)

        XCTAssertEqual(stories.count, 2)
        XCTAssertEqual(stories[0].title, "Story One")
        XCTAssertEqual(stories[1].title, "Story Two")
    }

    func testDeduplicatesByLink() {
        let xml = """
        <?xml version="1.0" encoding="UTF-8"?>
        <rss version="2.0">
        <channel>
          <item>
            <title>Duplicate A</title>
            <description>Body</description>
            <guid>https://example.com/same</guid>
          </item>
          <item>
            <title>Duplicate B</title>
            <description>Body</description>
            <guid>https://example.com/same</guid>
          </item>
        </channel>
        </rss>
        """.data(using: .utf8)!

        let parser = RSSParser()
        let stories = parser.parseData(xml)
        XCTAssertEqual(stories.count, 1)
    }

    func testEmptyFeed() {
        let xml = """
        <?xml version="1.0" encoding="UTF-8"?>
        <rss version="2.0"><channel><title>Empty</title></channel></rss>
        """.data(using: .utf8)!

        let parser = RSSParser()
        let stories = parser.parseData(xml)
        XCTAssertTrue(stories.isEmpty)
    }

    func testParseMediaThumbnail() {
        let xml = """
        <?xml version="1.0" encoding="UTF-8"?>
        <rss version="2.0" xmlns:media="http://search.yahoo.com/mrss/">
        <channel>
          <item>
            <title>With Image</title>
            <description>Has thumbnail</description>
            <guid>https://example.com/img-story</guid>
            <media:thumbnail url="https://cdn.example.com/thumb.jpg"/>
          </item>
        </channel>
        </rss>
        """.data(using: .utf8)!

        let parser = RSSParser()
        let stories = parser.parseData(xml)
        XCTAssertEqual(stories.count, 1)
        XCTAssertEqual(stories[0].imagePath, "https://cdn.example.com/thumb.jpg")
    }
}
