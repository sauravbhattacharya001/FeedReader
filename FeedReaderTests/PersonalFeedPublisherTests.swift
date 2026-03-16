//
//  PersonalFeedPublisherTests.swift
//  FeedReaderTests
//
//  Tests for the Personal Feed Publisher — RSS/OPML/JSON feed generation from bookmarks.
//

import XCTest
@testable import FeedReader

class PersonalFeedPublisherTests: XCTestCase {
    
    // MARK: - Helpers
    
    private func makeStory(title: String = "Test Article", body: String = "Article body text", link: String = "https://example.com/article", source: String? = "Tech Blog") -> Story {
        let story = Story(title: title, photo: nil, body: body, link: link, imagePath: nil)
        story.sourceFeedName = source
        return story
    }
    
    // MARK: - RSS Generation
    
    func testGenerateRSSProducesValidXML() {
        let publisher = PersonalFeedPublisher()
        let stories = [makeStory()]
        let rss = publisher.generateRSS(from: stories)
        
        XCTAssertTrue(rss.hasPrefix("<?xml version=\"1.0\""))
        XCTAssertTrue(rss.contains("<rss version=\"2.0\""))
        XCTAssertTrue(rss.contains("<channel>"))
        XCTAssertTrue(rss.contains("</rss>"))
    }
    
    func testRSSContainsChannelMetadata() {
        let config = PersonalFeedPublisher.FeedConfig(
            title: "My Feed",
            description: "Curated articles",
            link: "https://myblog.com",
            language: "en-us",
            authorName: "Alice",
            maxItems: 10
        )
        let publisher = PersonalFeedPublisher(config: config)
        let rss = publisher.generateRSS(from: [])
        
        XCTAssertTrue(rss.contains("<title>My Feed</title>"))
        XCTAssertTrue(rss.contains("<description>Curated articles</description>"))
        XCTAssertTrue(rss.contains("<managingEditor>Alice</managingEditor>"))
        XCTAssertTrue(rss.contains("<language>en-us</language>"))
    }
    
    func testRSSContainsItems() {
        let publisher = PersonalFeedPublisher()
        let stories = [
            makeStory(title: "First", link: "https://example.com/1"),
            makeStory(title: "Second", link: "https://example.com/2")
        ]
        let rss = publisher.generateRSS(from: stories)
        
        XCTAssertTrue(rss.contains("<title>First</title>"))
        XCTAssertTrue(rss.contains("<title>Second</title>"))
        XCTAssertTrue(rss.contains("<guid isPermaLink=\"true\">https://example.com/1</guid>"))
    }
    
    func testRSSRespectsMaxItems() {
        let config = PersonalFeedPublisher.FeedConfig.default
        var limited = config
        limited.maxItems = 2
        let publisher = PersonalFeedPublisher(config: limited)
        let stories = (1...5).map { makeStory(title: "Article \($0)", link: "https://example.com/\($0)") }
        let rss = publisher.generateRSS(from: stories)
        
        XCTAssertTrue(rss.contains("Article 1"))
        XCTAssertTrue(rss.contains("Article 2"))
        XCTAssertFalse(rss.contains("Article 3"))
    }
    
    func testRSSEscapesSpecialCharacters() {
        let publisher = PersonalFeedPublisher()
        let story = makeStory(title: "Tom & Jerry <3", link: "https://example.com/t&j")
        let rss = publisher.generateRSS(from: [story])
        
        XCTAssertTrue(rss.contains("Tom &amp; Jerry &lt;3"))
        XCTAssertFalse(rss.contains("Tom & Jerry <3"))
    }
    
    func testRSSIncludesSourceAsCategory() {
        let publisher = PersonalFeedPublisher()
        let story = makeStory(source: "Hacker News")
        let rss = publisher.generateRSS(from: [story])
        
        XCTAssertTrue(rss.contains("<category>Hacker News</category>"))
    }
    
    func testRSSEmptyStoriesProducesValidFeed() {
        let publisher = PersonalFeedPublisher()
        let rss = publisher.generateRSS(from: [])
        
        XCTAssertTrue(rss.contains("<channel>"))
        XCTAssertTrue(rss.contains("</channel>"))
        XCTAssertFalse(rss.contains("<item>"))
    }
    
    func testRSSTruncatesLongBody() {
        let publisher = PersonalFeedPublisher()
        let longBody = String(repeating: "x", count: 1000)
        let story = makeStory(body: longBody)
        let rss = publisher.generateRSS(from: [story])
        
        // Description should be at most 500 chars of body
        let descContent = rss.components(separatedBy: "<description>").last?.components(separatedBy: "</description>").first ?? ""
        XCTAssertLessThanOrEqual(descContent.count, 500)
    }
    
    // MARK: - OPML Generation
    
    func testGenerateOPMLProducesValidStructure() {
        let publisher = PersonalFeedPublisher()
        let stories = [makeStory(title: "My Article", link: "https://example.com/a")]
        let opml = publisher.generateOPML(from: stories)
        
        XCTAssertTrue(opml.contains("<opml version=\"2.0\">"))
        XCTAssertTrue(opml.contains("<head>"))
        XCTAssertTrue(opml.contains("<body>"))
        XCTAssertTrue(opml.contains("text=\"My Article\""))
        XCTAssertTrue(opml.contains("url=\"https://example.com/a\""))
    }
    
    // MARK: - JSON Feed
    
    func testGenerateJSONFeedProducesValidJSON() {
        let publisher = PersonalFeedPublisher()
        let stories = [makeStory(title: "JSON Test", source: "Dev Blog")]
        let json = publisher.generateJSONFeed(from: stories)
        
        XCTAssertTrue(json.contains("\"version\""))
        XCTAssertTrue(json.contains("jsonfeed.org"))
        XCTAssertTrue(json.contains("JSON Test"))
        XCTAssertTrue(json.contains("Dev Blog"))
    }
    
    func testJSONFeedEmptyStories() {
        let publisher = PersonalFeedPublisher()
        let json = publisher.generateJSONFeed(from: [])
        
        guard let data = json.data(using: .utf8),
              let parsed = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let items = parsed["items"] as? [[String: Any]] else {
            XCTFail("Invalid JSON output")
            return
        }
        XCTAssertEqual(items.count, 0)
    }
    
    // MARK: - Preview
    
    func testPreviewReturnsSummary() {
        let publisher = PersonalFeedPublisher()
        let stories = [
            makeStory(source: "Blog A"),
            makeStory(source: "Blog B"),
            makeStory(source: "Blog A")
        ]
        let preview = publisher.preview(stories: stories)
        
        XCTAssertEqual(preview.articleCount, 3)
        XCTAssertEqual(preview.sourceFeedCount, 2)
        XCTAssertTrue(preview.sources.contains("Blog A"))
        XCTAssertTrue(preview.sources.contains("Blog B"))
        XCTAssertGreaterThan(preview.estimatedSizeBytes, 0)
    }
    
    func testPreviewEstimatedSizeKB() {
        let publisher = PersonalFeedPublisher()
        let preview = publisher.preview(stories: [makeStory()])
        
        XCTAssertGreaterThan(preview.estimatedSizeKB, 0)
        XCTAssertEqual(preview.estimatedSizeKB, Double(preview.estimatedSizeBytes) / 1024.0, accuracy: 0.001)
    }
    
    // MARK: - Export to File
    
    func testExportToFileCreatesRSSFile() {
        let publisher = PersonalFeedPublisher()
        let stories = [makeStory()]
        
        let url = publisher.exportToFile(stories: stories, filename: "test-feed", format: .rss)
        XCTAssertNotNil(url)
        
        if let url = url {
            XCTAssertTrue(url.lastPathComponent.hasSuffix(".xml"))
            // Clean up
            try? FileManager.default.removeItem(at: url)
        }
    }
    
    func testExportToFileCreatesJSONFile() {
        let publisher = PersonalFeedPublisher()
        let stories = [makeStory()]
        
        let url = publisher.exportToFile(stories: stories, filename: "test-feed", format: .json)
        XCTAssertNotNil(url)
        
        if let url = url {
            XCTAssertTrue(url.lastPathComponent.hasSuffix(".json"))
            try? FileManager.default.removeItem(at: url)
        }
    }
    
    func testExportToFileCreatesOPMLFile() {
        let publisher = PersonalFeedPublisher()
        let stories = [makeStory()]
        
        let url = publisher.exportToFile(stories: stories, filename: "test-feed", format: .opml)
        XCTAssertNotNil(url)
        
        if let url = url {
            XCTAssertTrue(url.lastPathComponent.hasSuffix(".opml"))
            try? FileManager.default.removeItem(at: url)
        }
    }
    
    // MARK: - Default Config
    
    func testDefaultConfigValues() {
        let config = PersonalFeedPublisher.FeedConfig.default
        
        XCTAssertEqual(config.title, "My Curated Feed")
        XCTAssertEqual(config.maxItems, 50)
        XCTAssertEqual(config.language, "en-us")
    }
}
