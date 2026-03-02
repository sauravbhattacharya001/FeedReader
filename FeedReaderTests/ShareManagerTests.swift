//
//  ShareManagerTests.swift
//  FeedReaderTests
//
//  Tests for ShareManager — article sharing in multiple formats.
//

import XCTest
@testable import FeedReader

class ShareManagerTests: XCTestCase {
    
    var manager: ShareManager!
    var sampleStory: Story!
    
    override func setUp() {
        super.setUp()
        manager = ShareManager.shared
        manager.defaultOptions = ShareOptions()
        manager.clearHistory()
        
        sampleStory = Story(
            title: "Swift 6 Released with Full Concurrency",
            photo: nil,
            description: "Apple has released Swift 6 with complete concurrency checking enabled by default. The new version brings data race safety guarantees at compile time, making concurrent programming significantly safer and more accessible to developers worldwide.",
            link: "https://swift.org/blog/swift-6-released",
            imagePath: nil
        )
        sampleStory?.sourceFeedName = "Swift Blog"
    }
    
    // MARK: - Plain Text Format
    
    func testPlainTextFormat() {
        guard let story = sampleStory else { XCTFail("Story nil"); return }
        let result = manager.share(story: story, format: .plainText)
        
        XCTAssertTrue(result.content.contains("Swift 6 Released"))
        XCTAssertTrue(result.content.contains("Source: Swift Blog"))
        XCTAssertTrue(result.content.contains("Read more: https://swift.org"))
        XCTAssertEqual(result.format, .plainText)
        XCTAssertEqual(result.title, story.title)
        XCTAssertTrue(result.characterCount > 0)
    }
    
    func testPlainTextWithoutSource() {
        guard let story = sampleStory else { XCTFail("Story nil"); return }
        var opts = ShareOptions()
        opts.includeSource = false
        let result = manager.share(story: story, format: .plainText, options: opts)
        
        XCTAssertFalse(result.content.contains("Source:"))
    }
    
    func testPlainTextWithReadingTime() {
        guard let story = sampleStory else { XCTFail("Story nil"); return }
        var opts = ShareOptions()
        opts.includeReadingTime = true
        let result = manager.share(story: story, format: .plainText, options: opts)
        
        XCTAssertTrue(result.content.contains("min read"))
    }
    
    func testPlainTextWithAttribution() {
        guard let story = sampleStory else { XCTFail("Story nil"); return }
        var opts = ShareOptions()
        opts.includeAttribution = true
        opts.attributionText = "Shared via TestApp"
        let result = manager.share(story: story, format: .plainText, options: opts)
        
        XCTAssertTrue(result.content.contains("Shared via TestApp"))
    }
    
    // MARK: - Markdown Format
    
    func testMarkdownFormat() {
        guard let story = sampleStory else { XCTFail("Story nil"); return }
        let result = manager.share(story: story, format: .markdown)
        
        XCTAssertTrue(result.content.contains("## [Swift 6 Released"))
        XCTAssertTrue(result.content.contains("](https://swift.org"))
        XCTAssertTrue(result.content.contains("**Source:** Swift Blog"))
        XCTAssertTrue(result.content.contains("> "))
    }
    
    // MARK: - HTML Format
    
    func testHTMLFormat() {
        guard let story = sampleStory else { XCTFail("Story nil"); return }
        let result = manager.share(story: story, format: .html)
        
        XCTAssertTrue(result.content.contains("<h2>"))
        XCTAssertTrue(result.content.contains("<a href="))
        XCTAssertTrue(result.content.contains("shared-article"))
        XCTAssertTrue(result.content.contains("<blockquote>"))
    }
    
    func testHTMLEscaping() {
        let story = Story(
            title: "Test <script>alert('xss')</script>",
            photo: nil,
            description: "Body with <b>tags</b> & \"quotes\"",
            link: "https://example.com/test",
            imagePath: nil
        )
        // Story strips HTML in init, so title stays but body gets stripped
        guard let s = story else { XCTFail("Story nil"); return }
        let result = manager.share(story: s, format: .html)
        
        XCTAssertFalse(result.content.contains("<script>"))
    }
    
    // MARK: - Social Post Format
    
    func testSocialPostFormat() {
        guard let story = sampleStory else { XCTFail("Story nil"); return }
        var opts = ShareOptions()
        opts.hashtags = ["swift", "#programming"]
        let result = manager.share(story: story, format: .socialPost, options: opts)
        
        XCTAssertTrue(result.content.contains(story.title))
        XCTAssertTrue(result.content.contains(story.link))
        XCTAssertTrue(result.content.contains("#swift"))
        XCTAssertTrue(result.content.contains("#programming"))
    }
    
    // MARK: - Email Format
    
    func testEmailFormat() {
        guard let story = sampleStory else { XCTFail("Story nil"); return }
        let result = manager.share(story: story, format: .email)
        
        XCTAssertTrue(result.content.contains("Subject: Swift 6"))
        XCTAssertTrue(result.content.contains("Hi,"))
        XCTAssertTrue(result.content.contains("Read the full article:"))
    }
    
    // MARK: - Excerpt Truncation
    
    func testExcerptTruncation() {
        guard let story = sampleStory else { XCTFail("Story nil"); return }
        var opts = ShareOptions()
        opts.excerptLength = 50
        let result = manager.share(story: story, format: .plainText, options: opts)
        
        // Excerpt should be truncated
        XCTAssertTrue(result.content.contains("…"))
    }
    
    func testNoExcerpt() {
        guard let story = sampleStory else { XCTFail("Story nil"); return }
        var opts = ShareOptions()
        opts.includeExcerpt = false
        let result = manager.share(story: story, format: .plainText, options: opts)
        
        // Should still have title and link but shorter overall
        XCTAssertTrue(result.content.contains(story.title))
        XCTAssertTrue(result.content.contains(story.link))
    }
    
    // MARK: - Digest
    
    func testDigestPlainText() {
        guard let story = sampleStory else { XCTFail("Story nil"); return }
        let story2 = Story(
            title: "Rust 2.0 Announced",
            photo: nil,
            description: "The Rust team announces version 2.0.",
            link: "https://rust-lang.org/2.0",
            imagePath: nil
        )!
        
        let result = manager.shareDigest(
            stories: [story, story2],
            format: .plainText,
            title: "Tech News Roundup"
        )
        
        XCTAssertTrue(result.content.contains("Tech News Roundup"))
        XCTAssertTrue(result.content.contains("1. Swift 6"))
        XCTAssertTrue(result.content.contains("2. Rust 2.0"))
    }
    
    func testDigestMarkdown() {
        guard let story = sampleStory else { XCTFail("Story nil"); return }
        let result = manager.shareDigest(stories: [story], format: .markdown)
        
        XCTAssertTrue(result.content.contains("# Article Digest"))
        XCTAssertTrue(result.content.contains("**[Swift 6"))
    }
    
    // MARK: - Share History
    
    func testShareHistoryTracking() {
        guard let story = sampleStory else { XCTFail("Story nil"); return }
        
        XCTAssertEqual(manager.shareHistory.count, 0)
        
        _ = manager.share(story: story, format: .plainText)
        _ = manager.share(story: story, format: .markdown)
        
        XCTAssertEqual(manager.shareHistory.count, 2)
        XCTAssertEqual(manager.shareCount(for: story.link), 2)
    }
    
    func testMostShared() {
        guard let story = sampleStory else { XCTFail("Story nil"); return }
        
        _ = manager.share(story: story, format: .plainText)
        _ = manager.share(story: story, format: .markdown)
        _ = manager.share(story: story, format: .html)
        
        let most = manager.mostShared(limit: 5)
        XCTAssertEqual(most.count, 1)
        XCTAssertEqual(most.first?.count, 3)
    }
    
    func testClearHistory() {
        guard let story = sampleStory else { XCTFail("Story nil"); return }
        _ = manager.share(story: story, format: .plainText)
        XCTAssertTrue(manager.shareHistory.count > 0)
        
        manager.clearHistory()
        XCTAssertEqual(manager.shareHistory.count, 0)
    }
}
