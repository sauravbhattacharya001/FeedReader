//
//  XMLParserTests.swift
//  FeedReaderTests
//
//  Tests for the XML/RSS parsing logic in StoryTableViewController,
//  including multi-item feeds, image paths, HTML stripping, and
//  malformed/empty data handling.
//

import XCTest
import UIKit
@testable import FeedReader

class XMLParserTests: XCTestCase {

    var viewController: StoryTableViewController!

    override func setUp() {
        super.setUp()
        let storyboard = UIStoryboard(name: "Main", bundle: Bundle.main)
        viewController = storyboard.instantiateViewController(
            withIdentifier: "StoryTable"
        ) as? StoryTableViewController
        UIApplication.shared.keyWindow!.rootViewController = viewController
        let _ = viewController.view
    }

    override func tearDown() {
        viewController = nil
        super.tearDown()
    }

    // MARK: - Multi-Item Parsing

    func testParsingMultipleItems() {
        guard let path = Bundle.main.path(
            forResource: "multiStoriesTest", ofType: "xml"
        ) else {
            XCTFail("multiStoriesTest.xml not found in test bundle")
            return
        }

        viewController.beginParsingTest(path)

        XCTAssertEqual(viewController.stories.count, 3,
                       "Should parse all 3 items from the multi-item feed")
    }

    func testParsedStoryTitles() {
        guard let path = Bundle.main.path(
            forResource: "multiStoriesTest", ofType: "xml"
        ) else { return }

        viewController.beginParsingTest(path)

        XCTAssertTrue(viewController.stories[0].title.contains("First Story"))
        XCTAssertTrue(viewController.stories[1].title.contains("Second Story"))
        XCTAssertTrue(viewController.stories[2].title.contains("Third Story"))
    }

    func testParsedStoryLinks() {
        guard let path = Bundle.main.path(
            forResource: "multiStoriesTest", ofType: "xml"
        ) else { return }

        viewController.beginParsingTest(path)

        XCTAssertTrue(viewController.stories[0].link.contains("story1"))
        XCTAssertTrue(viewController.stories[1].link.contains("story2"))
        XCTAssertTrue(viewController.stories[2].link.contains("story3"))
    }

    // MARK: - Image Path Handling

    func testStoryWithImagePath() {
        guard let path = Bundle.main.path(
            forResource: "multiStoriesTest", ofType: "xml"
        ) else { return }

        viewController.beginParsingTest(path)

        // Second item has an <image> element
        XCTAssertEqual(
            viewController.stories[1].imagePath,
            "http://example.com/image2.jpg",
            "Story should capture the image path from the <image> element"
        )
    }

    func testStoryWithoutImagePath() {
        guard let path = Bundle.main.path(
            forResource: "multiStoriesTest", ofType: "xml"
        ) else { return }

        viewController.beginParsingTest(path)

        // First item has no <image> element; imagePath should be nil
        // (empty string is trimmed and set to nil in didEndElement)
        XCTAssertNil(
            viewController.stories[0].imagePath,
            "Story without <image> element should have nil imagePath"
        )
    }

    // MARK: - HTML Stripping in Description

    func testHTMLStrippingInDescription() {
        guard let path = Bundle.main.path(
            forResource: "multiStoriesTest", ofType: "xml"
        ) else { return }

        viewController.beginParsingTest(path)

        // Third item has "<div" in description; parser splits on it
        let description = viewController.stories[2].body
        XCTAssertFalse(
            description.contains("<div"),
            "Description should have HTML <div> content stripped"
        )
    }

    // MARK: - Malformed Data Handling

    func testMalformedFeedSkipsInvalidStories() {
        guard let path = Bundle.main.path(
            forResource: "malformedStoriesTest", ofType: "xml"
        ) else {
            XCTFail("malformedStoriesTest.xml not found in test bundle")
            return
        }

        viewController.beginParsingTest(path)

        // Feed has 3 items but 2 are invalid (empty title, empty description).
        // Story.init returns nil for empty title or empty description,
        // so only the valid one should be added.
        XCTAssertEqual(
            viewController.stories.count, 1,
            "Should skip stories with empty title or description"
        )
        XCTAssertTrue(viewController.stories[0].title.contains("Valid Story"))
    }

    // MARK: - Empty Feed

    func testEmptyFeed() {
        // Parse an XML with no <item> elements
        let emptyXML = """
        <?xml version="1.0" encoding="UTF-8"?>
        <rss><channel><title>Empty</title></channel></rss>
        """
        let tempDir = FileManager.default.temporaryDirectory
        let tempFile = tempDir.appendingPathComponent("emptyFeed.xml")
        try? emptyXML.data(using: .utf8)?.write(to: tempFile)

        viewController.beginParsingTest(tempFile.path)
        XCTAssertEqual(viewController.stories.count, 0,
                       "Empty feed should produce zero stories")

        try? FileManager.default.removeItem(at: tempFile)
    }

    // MARK: - Parsing Resets Stories Array

    func testParsingResetsStoriesArray() {
        guard let path = Bundle.main.path(
            forResource: "storiesTest", ofType: "xml"
        ) else { return }

        // Parse once
        viewController.beginParsingTest(path)
        let countAfterFirst = viewController.stories.count

        // Parse again — should not accumulate
        viewController.beginParsingTest(path)
        XCTAssertEqual(
            viewController.stories.count, countAfterFirst,
            "Re-parsing should reset stories, not accumulate"
        )
    }

    // MARK: - Table View Data Source

    func testNumberOfSections() {
        XCTAssertEqual(viewController.numberOfSections(in: viewController.tableView), 1)
    }

    func testNumberOfRowsMatchesStories() {
        guard let path = Bundle.main.path(
            forResource: "multiStoriesTest", ofType: "xml"
        ) else { return }

        viewController.beginParsingTest(path)
        viewController.saveStories()

        let rows = viewController.tableView(
            viewController.tableView,
            numberOfRowsInSection: 0
        )
        XCTAssertEqual(rows, viewController.stories.count)
    }

    // MARK: - Data Persistence Round-Trip

    func testSaveAndLoadPreservesStoryOrder() {
        guard let path = Bundle.main.path(
            forResource: "multiStoriesTest", ofType: "xml"
        ) else { return }

        viewController.beginParsingTest(path)
        viewController.saveStories()

        let loaded = viewController.loadStories()
        XCTAssertNotNil(loaded)
        XCTAssertEqual(loaded?.count, viewController.stories.count)

        // Verify order is preserved
        for (i, story) in (loaded ?? []).enumerated() {
            XCTAssertEqual(story.title, viewController.stories[i].title)
            XCTAssertEqual(story.link, viewController.stories[i].link)
        }
    }
}
