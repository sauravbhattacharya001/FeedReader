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

        // Archive
        guard let data = try? NSKeyedArchiver.archivedData(
            withRootObject: original,
            requiringSecureCoding: false
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
            requiringSecureCoding: false
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
            requiringSecureCoding: false
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
        // The parser strips HTML by splitting on "<div", but the model
        // itself should accept HTML in description.
        let story = Story(
            title: "HTML Test",
            photo: nil,
            description: "<p>Bold <b>text</b></p>",
            link: "http://example.com"
        )
        XCTAssertNotNil(story)
        XCTAssertEqual(story?.body, "<p>Bold <b>text</b></p>")
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
}
