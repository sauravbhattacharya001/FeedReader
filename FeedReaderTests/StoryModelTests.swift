//
//  StoryModelTests.swift
//  FeedReaderTests
//
//  Tests for Story model edge cases, NSCoding round-trip, and PropertyKey integrity.
//

import XCTest
@testable import FeedReader

class StoryModelTests: XCTestCase {

    // MARK: - PropertyKey Constants

    func testPropertyKeyValues() {
        // Verify PropertyKey constants haven't been accidentally changed,
        // which would break NSCoding deserialization of archived data.
        XCTAssertEqual(Story.PropertyKey.titleKey, "title")
        XCTAssertEqual(Story.PropertyKey.photoKey, "photo")
        XCTAssertEqual(Story.PropertyKey.descriptionKey, "description")
        XCTAssertEqual(Story.PropertyKey.linkKey, "link")
        XCTAssertEqual(Story.PropertyKey.imagePathKey, "imagePath")
    }

    // MARK: - Initialization with imagePath

    func testStoryInitWithImagePath() {
        let story = Story(
            title: "Test",
            photo: nil,
            description: "Desc",
            link: "http://example.com",
            imagePath: "http://example.com/image.jpg"
        )
        XCTAssertNotNil(story)
        XCTAssertEqual(story?.imagePath, "http://example.com/image.jpg")
    }

    func testStoryInitWithoutImagePath() {
        let story = Story(
            title: "Test",
            photo: nil,
            description: "Desc",
            link: "http://example.com"
        )
        XCTAssertNotNil(story)
        XCTAssertNil(story?.imagePath, "imagePath should default to nil when omitted")
    }

    func testStoryInitWithNilImagePath() {
        let story = Story(
            title: "Test",
            photo: nil,
            description: "Desc",
            link: "http://example.com",
            imagePath: nil
        )
        XCTAssertNotNil(story)
        XCTAssertNil(story?.imagePath)
    }

    // MARK: - Link Validation Edge Cases

    func testStoryWithHTTPSLink() {
        let story = Story(
            title: "Secure",
            photo: nil,
            description: "HTTPS link",
            link: "https://www.example.com"
        )
        XCTAssertNotNil(story, "HTTPS links should be valid")
    }

    func testStoryWithLinkContainingQueryParams() {
        let story = Story(
            title: "Query",
            photo: nil,
            description: "Link with params",
            link: "http://example.com/page?key=value&foo=bar"
        )
        XCTAssertNotNil(story, "Links with query parameters should be valid")
    }

    func testStoryWithLinkContainingFragment() {
        let story = Story(
            title: "Fragment",
            photo: nil,
            description: "Link with fragment",
            link: "http://example.com/page#section"
        )
        XCTAssertNotNil(story, "Links with fragments should be valid")
    }

    func testStoryWithWhitespaceOnlyTitle() {
        // A title with only whitespace still has count > 0, so isEmpty returns false.
        // This test documents the current behavior.
        let story = Story(
            title: "   ",
            photo: nil,
            description: "Desc",
            link: "http://example.com"
        )
        XCTAssertNotNil(story, "Whitespace-only title passes isEmpty check — documents current behavior")
    }

    func testStoryWithWhitespaceOnlyDescription() {
        let story = Story(
            title: "Title",
            photo: nil,
            description: "   ",
            link: "http://example.com"
        )
        XCTAssertNotNil(story, "Whitespace-only description passes isEmpty check — documents current behavior")
    }

    // MARK: - NSCoding Round-Trip

    func testNSCodingRoundTrip() {
        let original = Story(
            title: "Archive Test",
            photo: nil,
            description: "Testing archival",
            link: "http://example.com",
            imagePath: "http://example.com/thumb.png"
        )!

        // Archive with secure coding enabled
        guard let data = try? NSKeyedArchiver.archivedData(
            withRootObject: original,
            requiringSecureCoding: true
        ) else {
            XCTFail("Failed to archive Story")
            return
        }

        // Unarchive
        guard let decoded = try? NSKeyedUnarchiver.unarchivedObject(
            ofClasses: [Story.self],
            from: data
        ) as? Story else {
            XCTFail("Failed to unarchive Story")
            return
        }

        XCTAssertEqual(decoded.title, original.title)
        XCTAssertEqual(decoded.body, original.body)
        XCTAssertEqual(decoded.link, original.link)
        XCTAssertEqual(decoded.imagePath, original.imagePath)
    }

    func testNSCodingRoundTripWithNilOptionals() {
        let original = Story(
            title: "Nil Test",
            photo: nil,
            description: "No image path",
            link: "http://example.com",
            imagePath: nil
        )!

        guard let data = try? NSKeyedArchiver.archivedData(
            withRootObject: original,
            requiringSecureCoding: true
        ) else {
            XCTFail("Failed to archive Story with nil optionals")
            return
        }

        guard let decoded = try? NSKeyedUnarchiver.unarchivedObject(
            ofClasses: [Story.self],
            from: data
        ) as? Story else {
            XCTFail("Failed to unarchive Story with nil optionals")
            return
        }

        XCTAssertEqual(decoded.title, "Nil Test")
        XCTAssertNil(decoded.photo)
        XCTAssertNil(decoded.imagePath)
    }

    func testNSCodingArrayRoundTrip() {
        let stories: [Story] = [
            Story(title: "First", photo: nil, description: "One", link: "http://one.com")!,
            Story(title: "Second", photo: nil, description: "Two", link: "http://two.com")!,
            Story(title: "Third", photo: nil, description: "Three", link: "http://three.com", imagePath: "http://img.com/3.jpg")!,
        ]

        guard let data = try? NSKeyedArchiver.archivedData(
            withRootObject: stories,
            requiringSecureCoding: true
        ) else {
            XCTFail("Failed to archive Story array")
            return
        }

        guard let decoded = try? NSKeyedUnarchiver.unarchivedObject(
            ofClasses: [NSArray.self, Story.self],
            from: data
        ) as? [Story] else {
            XCTFail("Failed to unarchive Story array")
            return
        }

        XCTAssertEqual(decoded.count, 3)
        XCTAssertEqual(decoded[0].title, "First")
        XCTAssertEqual(decoded[1].title, "Second")
        XCTAssertEqual(decoded[2].title, "Third")
        XCTAssertEqual(decoded[2].imagePath, "http://img.com/3.jpg")
    }

    // MARK: - Archive Paths

    func testArchiveURLIsInDocumentsDirectory() {
        let docsDir = FileManager.default.urls(
            for: .documentDirectory,
            in: .userDomainMask
        ).first!
        let expected = docsDir.appendingPathComponent("stories")
        XCTAssertEqual(Story.ArchiveURL, expected)
    }

    // MARK: - Special Characters

    func testStoryWithUnicodeContent() {
        let story = Story(
            title: "新闻标题 📰",
            photo: nil,
            description: "Ünïcödé déscription with émojis 🚀✨",
            link: "http://example.com"
        )
        XCTAssertNotNil(story)
        XCTAssertEqual(story?.title, "新闻标题 📰")
    }

    func testStoryWithHTMLInDescription() {
        // Story now strips HTML tags for security (prevents XSS/injection)
        let story = Story(
            title: "HTML Test",
            photo: nil,
            description: "<p>Bold <b>text</b></p>",
            link: "http://example.com"
        )
        XCTAssertNotNil(story)
        XCTAssertEqual(story?.body, "Bold text", "HTML tags should be stripped from description")
    }

    func testStoryWithNewlinesInTitle() {
        // The XML parser appends "\n" to titles; model should accept this.
        let story = Story(
            title: "Title With Newline\n",
            photo: nil,
            description: "Description\n",
            link: "http://example.com"
        )
        XCTAssertNotNil(story)
    }

    // MARK: - Security: URL Scheme Validation

    func testIsSafeURLAcceptsHTTP() {
        XCTAssertTrue(Story.isSafeURL("http://example.com"))
    }

    func testIsSafeURLAcceptsHTTPS() {
        XCTAssertTrue(Story.isSafeURL("https://example.com"))
    }

    func testIsSafeURLRejectsJavascript() {
        XCTAssertFalse(Story.isSafeURL("javascript:alert(1)"), "javascript: scheme must be blocked")
    }

    func testIsSafeURLRejectsFileScheme() {
        XCTAssertFalse(Story.isSafeURL("file:///etc/passwd"), "file: scheme must be blocked")
    }

    func testIsSafeURLRejectsDataScheme() {
        XCTAssertFalse(Story.isSafeURL("data:text/html,<script>alert(1)</script>"), "data: scheme must be blocked")
    }

    func testIsSafeURLRejectsTelScheme() {
        XCTAssertFalse(Story.isSafeURL("tel:+1234567890"), "tel: scheme must be blocked")
    }

    func testIsSafeURLRejectsCustomScheme() {
        XCTAssertFalse(Story.isSafeURL("myapp://callback"), "Custom schemes must be blocked")
    }

    func testIsSafeURLRejectsNil() {
        XCTAssertFalse(Story.isSafeURL(nil))
    }

    func testIsSafeURLRejectsEmptyString() {
        XCTAssertFalse(Story.isSafeURL(""))
    }

    func testIsSafeURLRejectsNoScheme() {
        XCTAssertFalse(Story.isSafeURL("example.com"))
    }

    func testStoryRejectsJavascriptLink() {
        let story = Story(
            title: "XSS",
            photo: nil,
            description: "Test",
            link: "javascript:alert(document.cookie)"
        )
        XCTAssertNil(story, "Story with javascript: link must fail initialization")
    }

    func testStoryRejectsFileLink() {
        let story = Story(
            title: "File Access",
            photo: nil,
            description: "Test",
            link: "file:///etc/passwd"
        )
        XCTAssertNil(story, "Story with file: link must fail initialization")
    }

    // MARK: - Security: Image Path Validation

    func testStoryRejectsFileImagePath() {
        let story = Story(
            title: "Test",
            photo: nil,
            description: "Desc",
            link: "http://example.com",
            imagePath: "file:///etc/passwd"
        )
        XCTAssertNotNil(story, "Story should still init")
        XCTAssertNil(story?.imagePath, "file: image path must be rejected")
    }

    func testStoryRejectsJavascriptImagePath() {
        let story = Story(
            title: "Test",
            photo: nil,
            description: "Desc",
            link: "http://example.com",
            imagePath: "javascript:alert(1)"
        )
        XCTAssertNotNil(story)
        XCTAssertNil(story?.imagePath, "javascript: image path must be rejected")
    }

    func testStoryAcceptsHTTPSImagePath() {
        let story = Story(
            title: "Test",
            photo: nil,
            description: "Desc",
            link: "http://example.com",
            imagePath: "https://cdn.example.com/img.jpg"
        )
        XCTAssertNotNil(story)
        XCTAssertEqual(story?.imagePath, "https://cdn.example.com/img.jpg")
    }

    // MARK: - Security: HTML Stripping

    func testStripHTMLRemovesTags() {
        let result = Story.stripHTML("<p>Hello <b>world</b></p>")
        XCTAssertEqual(result, "Hello world")
    }

    func testStripHTMLDecodesEntities() {
        let result = Story.stripHTML("Tom &amp; Jerry &lt;3&gt;")
        XCTAssertEqual(result, "Tom & Jerry <3>")
    }

    func testStripHTMLRemovesScriptTags() {
        let result = Story.stripHTML("Safe<script>alert('xss')</script> content")
        XCTAssertEqual(result, "Safealert('xss') content")
    }

    func testStripHTMLHandlesNestedTags() {
        let result = Story.stripHTML("<div><span class=\"cls\">Text</span></div>")
        XCTAssertEqual(result, "Text")
    }

    func testStripHTMLPreservesPlainText() {
        let result = Story.stripHTML("No HTML here")
        XCTAssertEqual(result, "No HTML here")
    }

    // MARK: - Security: NSSecureCoding

    func testSupportsSecureCoding() {
        XCTAssertTrue(Story.supportsSecureCoding, "Story must support NSSecureCoding")
    }
}
