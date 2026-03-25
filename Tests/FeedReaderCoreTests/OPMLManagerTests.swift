//
//  OPMLManagerTests.swift
//  FeedReaderCoreTests
//
//  Tests for OPML import/export functionality.
//

import XCTest
@testable import FeedReaderCore

final class OPMLManagerTests: XCTestCase {

    // MARK: - Export Tests

    func testExportProducesValidOPML() throws {
        let feeds = [
            FeedItem(name: "BBC News", url: "https://feeds.bbci.co.uk/news/rss.xml", isEnabled: true),
            FeedItem(name: "TechCrunch", url: "https://techcrunch.com/feed/", isEnabled: false),
        ]

        let opml = try OPMLManager.exportString(feeds: feeds, title: "Test Export")

        XCTAssertTrue(opml.contains("<?xml version=\"1.0\""))
        XCTAssertTrue(opml.contains("<opml version=\"2.0\">"))
        XCTAssertTrue(opml.contains("<title>Test Export</title>"))
        XCTAssertTrue(opml.contains("xmlUrl=\"https://feeds.bbci.co.uk/news/rss.xml\""))
        XCTAssertTrue(opml.contains("xmlUrl=\"https://techcrunch.com/feed/\""))
        XCTAssertTrue(opml.contains("text=\"BBC News\""))
        XCTAssertTrue(opml.contains("text=\"TechCrunch\""))
    }

    func testExportEscapesSpecialCharacters() throws {
        let feeds = [
            FeedItem(name: "Feed & <Friends>", url: "https://example.com/feed?a=1&b=2", isEnabled: true),
        ]

        let opml = try OPMLManager.exportString(feeds: feeds)

        XCTAssertTrue(opml.contains("Feed &amp; &lt;Friends&gt;"))
        XCTAssertTrue(opml.contains("a=1&amp;b=2"))
    }

    func testExportEmptyFeedList() throws {
        let opml = try OPMLManager.exportString(feeds: [])
        XCTAssertTrue(opml.contains("<body>"))
        XCTAssertTrue(opml.contains("</body>"))
    }

    // MARK: - Import Tests

    func testImportValidOPML() throws {
        let opml = """
        <?xml version="1.0" encoding="UTF-8"?>
        <opml version="2.0">
          <head><title>My Feeds</title></head>
          <body>
            <outline text="BBC" title="BBC News" type="rss" xmlUrl="https://feeds.bbci.co.uk/news/rss.xml" />
            <outline text="TC" type="rss" xmlUrl="https://techcrunch.com/feed/" />
          </body>
        </opml>
        """

        let feeds = try OPMLManager.importOPML(from: opml)

        XCTAssertEqual(feeds.count, 2)
        // title attribute preferred over text
        XCTAssertEqual(feeds[0].name, "BBC News")
        XCTAssertEqual(feeds[0].url, "https://feeds.bbci.co.uk/news/rss.xml")
        XCTAssertTrue(feeds[0].isEnabled)
        // Falls back to text when no title
        XCTAssertEqual(feeds[1].name, "TC")
    }

    func testImportNestedOutlines() throws {
        let opml = """
        <?xml version="1.0" encoding="UTF-8"?>
        <opml version="1.0">
          <body>
            <outline text="News">
              <outline text="BBC" xmlUrl="https://bbc.co.uk/feed" />
            </outline>
            <outline text="Tech">
              <outline text="TC" xmlUrl="https://tc.com/feed" />
            </outline>
          </body>
        </opml>
        """

        let feeds = try OPMLManager.importOPML(from: opml)
        XCTAssertEqual(feeds.count, 2)
    }

    func testImportDeduplicates() throws {
        let opml = """
        <?xml version="1.0" encoding="UTF-8"?>
        <opml version="2.0">
          <body>
            <outline text="Feed A" xmlUrl="https://example.com/feed" />
            <outline text="Feed B" xmlUrl="https://EXAMPLE.COM/feed" />
          </body>
        </opml>
        """

        let feeds = try OPMLManager.importOPML(from: opml)
        XCTAssertEqual(feeds.count, 1)
    }

    func testImportEmptyDataThrows() {
        XCTAssertThrowsError(try OPMLManager.importOPML(from: Data())) { error in
            XCTAssertTrue(error is OPMLError)
        }
    }

    func testImportNoFeedsThrows() {
        let opml = """
        <?xml version="1.0"?>
        <opml version="2.0"><body></body></opml>
        """
        XCTAssertThrowsError(try OPMLManager.importOPML(from: opml)) { error in
            guard let opmlError = error as? OPMLError else { return XCTFail() }
            if case .noFeedsFound = opmlError {} else { XCTFail("Expected noFeedsFound") }
        }
    }

    // MARK: - Round-Trip

    func testRoundTrip() throws {
        let original = FeedItem.presets
        let data = try OPMLManager.export(feeds: original)
        let imported = try OPMLManager.importOPML(from: data)

        XCTAssertEqual(imported.count, original.count)
        for (orig, imp) in zip(original, imported) {
            XCTAssertEqual(orig.name, imp.name)
            XCTAssertEqual(orig.url, imp.url)
        }
    }
}
