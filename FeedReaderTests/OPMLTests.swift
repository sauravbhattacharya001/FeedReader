//
//  OPMLTests.swift
//  FeedReaderTests
//
//  Tests for OPML import/export functionality.
//

import XCTest
@testable import FeedReader

class OPMLTests: XCTestCase {
    
    var opmlManager: OPMLManager!
    
    override func setUp() {
        super.setUp()
        opmlManager = OPMLManager.shared
        // Reset FeedManager to known state
        FeedManager.shared.resetToDefaults()
    }
    
    // MARK: - Export Tests
    
    func testExportGeneratesValidOPML() {
        let feeds = [
            Feed(name: "Test Feed", url: "https://example.com/rss.xml", isEnabled: true)
        ]
        let opml = opmlManager.generateOPML(feeds: feeds)
        
        XCTAssertTrue(opml.hasPrefix("<?xml version=\"1.0\" encoding=\"UTF-8\"?>"))
        XCTAssertTrue(opml.contains("<opml version=\"2.0\">"))
        XCTAssertTrue(opml.contains("<title>FeedReader Subscriptions</title>"))
        XCTAssertTrue(opml.contains("<body>"))
        XCTAssertTrue(opml.contains("</body>"))
        XCTAssertTrue(opml.contains("</opml>"))
    }
    
    func testExportContainsFeedData() {
        let feeds = [
            Feed(name: "My Feed", url: "https://example.com/feed.xml", isEnabled: true)
        ]
        let opml = opmlManager.generateOPML(feeds: feeds)
        
        XCTAssertTrue(opml.contains("text=\"My Feed\""))
        XCTAssertTrue(opml.contains("title=\"My Feed\""))
        XCTAssertTrue(opml.contains("xmlUrl=\"https://example.com/feed.xml\""))
        XCTAssertTrue(opml.contains("type=\"rss\""))
    }
    
    func testExportMultipleFeeds() {
        let feeds = [
            Feed(name: "Feed 1", url: "https://example.com/1.xml", isEnabled: true),
            Feed(name: "Feed 2", url: "https://example.com/2.xml", isEnabled: false),
            Feed(name: "Feed 3", url: "https://example.com/3.xml", isEnabled: true)
        ]
        let opml = opmlManager.generateOPML(feeds: feeds)
        
        XCTAssertTrue(opml.contains("text=\"Feed 1\""))
        XCTAssertTrue(opml.contains("text=\"Feed 2\""))
        XCTAssertTrue(opml.contains("text=\"Feed 3\""))
    }
    
    func testExportEmptyFeeds() {
        let opml = opmlManager.generateOPML(feeds: [])
        
        XCTAssertTrue(opml.contains("<body>"))
        XCTAssertTrue(opml.contains("</body>"))
        // Should have no outline elements
        XCTAssertFalse(opml.contains("<outline"))
    }
    
    func testExportEscapesXMLCharacters() {
        let feeds = [
            Feed(name: "Feed & News <World>", url: "https://example.com/rss.xml", isEnabled: true)
        ]
        let opml = opmlManager.generateOPML(feeds: feeds)
        
        XCTAssertTrue(opml.contains("text=\"Feed &amp; News &lt;World&gt;\""))
        XCTAssertFalse(opml.contains("text=\"Feed & News <World>\""))
    }
    
    func testExportContainsDateCreated() {
        let opml = opmlManager.generateOPML(feeds: [])
        XCTAssertTrue(opml.contains("<dateCreated>"))
        XCTAssertTrue(opml.contains("</dateCreated>"))
    }
    
    func testExportContainsDocsLink() {
        let opml = opmlManager.generateOPML(feeds: [])
        XCTAssertTrue(opml.contains("<docs>http://opml.org/spec2.opml</docs>"))
    }
    
    // MARK: - XML Escaping Tests
    
    func testEscapeXMLAmpersand() {
        XCTAssertEqual(opmlManager.escapeXML("A & B"), "A &amp; B")
    }
    
    func testEscapeXMLAngleBrackets() {
        XCTAssertEqual(opmlManager.escapeXML("<hello>"), "&lt;hello&gt;")
    }
    
    func testEscapeXMLQuotes() {
        XCTAssertEqual(opmlManager.escapeXML("Say \"hello\""), "Say &quot;hello&quot;")
    }
    
    func testEscapeXMLApostrophe() {
        XCTAssertEqual(opmlManager.escapeXML("it's"), "it&#39;s")
    }
    
    func testEscapeXMLNoSpecialChars() {
        XCTAssertEqual(opmlManager.escapeXML("plain text"), "plain text")
    }
    
    func testEscapeXMLMultipleSpecialChars() {
        let result = opmlManager.escapeXML("<A & B's \"value\">")
        XCTAssertEqual(result, "&lt;A &amp; B&#39;s &quot;value&quot;&gt;")
    }
    
    // MARK: - Parse Tests
    
    func testParseValidOPML() {
        let opml = """
        <?xml version="1.0" encoding="UTF-8"?>
        <opml version="2.0">
          <head><title>Test</title></head>
          <body>
            <outline type="rss" text="BBC News" xmlUrl="https://feeds.bbci.co.uk/news/rss.xml"/>
            <outline type="rss" text="TechCrunch" xmlUrl="https://techcrunch.com/feed/"/>
          </body>
        </opml>
        """
        
        let outlines = opmlManager.parseOPML(opml)
        XCTAssertEqual(outlines.count, 2)
        XCTAssertEqual(outlines[0].title, "BBC News")
        XCTAssertEqual(outlines[0].xmlUrl, "https://feeds.bbci.co.uk/news/rss.xml")
        XCTAssertEqual(outlines[1].title, "TechCrunch")
        XCTAssertEqual(outlines[1].xmlUrl, "https://techcrunch.com/feed/")
    }
    
    func testParseOPMLWithCategories() {
        let opml = """
        <?xml version="1.0" encoding="UTF-8"?>
        <opml version="2.0">
          <head><title>Test</title></head>
          <body>
            <outline text="Technology">
              <outline type="rss" text="TechCrunch" xmlUrl="https://techcrunch.com/feed/"/>
              <outline type="rss" text="Ars Technica" xmlUrl="https://feeds.arstechnica.com/arstechnica/index"/>
            </outline>
            <outline text="News">
              <outline type="rss" text="BBC" xmlUrl="https://feeds.bbci.co.uk/news/rss.xml"/>
            </outline>
          </body>
        </opml>
        """
        
        let outlines = opmlManager.parseOPML(opml)
        XCTAssertEqual(outlines.count, 3)
        XCTAssertEqual(outlines[0].category, "Technology")
        XCTAssertEqual(outlines[1].category, "Technology")
        XCTAssertEqual(outlines[2].category, "News")
    }
    
    func testParseFallsBackToTitleAttribute() {
        let opml = """
        <?xml version="1.0" encoding="UTF-8"?>
        <opml version="2.0">
          <body>
            <outline type="rss" title="Title Only" xmlUrl="https://example.com/feed.xml"/>
          </body>
        </opml>
        """
        
        let outlines = opmlManager.parseOPML(opml)
        XCTAssertEqual(outlines.count, 1)
        XCTAssertEqual(outlines[0].title, "Title Only")
    }
    
    func testParseFallsBackToURLForTitle() {
        let opml = """
        <?xml version="1.0" encoding="UTF-8"?>
        <opml version="2.0">
          <body>
            <outline type="rss" xmlUrl="https://example.com/feed.xml"/>
          </body>
        </opml>
        """
        
        let outlines = opmlManager.parseOPML(opml)
        XCTAssertEqual(outlines.count, 1)
        XCTAssertEqual(outlines[0].title, "https://example.com/feed.xml")
    }
    
    func testParseSkipsOutlinesWithoutXmlUrl() {
        let opml = """
        <?xml version="1.0" encoding="UTF-8"?>
        <opml version="2.0">
          <body>
            <outline text="Just a folder"/>
            <outline type="rss" text="Valid" xmlUrl="https://example.com/feed.xml"/>
          </body>
        </opml>
        """
        
        let outlines = opmlManager.parseOPML(opml)
        XCTAssertEqual(outlines.count, 1)
        XCTAssertEqual(outlines[0].title, "Valid")
    }
    
    func testParseEmptyOPML() {
        let opml = """
        <?xml version="1.0" encoding="UTF-8"?>
        <opml version="2.0">
          <body></body>
        </opml>
        """
        
        let outlines = opmlManager.parseOPML(opml)
        XCTAssertTrue(outlines.isEmpty)
    }
    
    func testParseInvalidXML() {
        let opml = "this is not xml"
        let outlines = opmlManager.parseOPML(opml)
        XCTAssertTrue(outlines.isEmpty)
    }
    
    func testParseCaseInsensitiveXmlUrl() {
        let opml = """
        <?xml version="1.0" encoding="UTF-8"?>
        <opml version="2.0">
          <body>
            <outline text="Feed" xmlurl="https://example.com/feed.xml"/>
          </body>
        </opml>
        """
        
        let outlines = opmlManager.parseOPML(opml)
        XCTAssertEqual(outlines.count, 1)
        XCTAssertEqual(outlines[0].xmlUrl, "https://example.com/feed.xml")
    }
    
    func testParseExtractsHtmlUrl() {
        let opml = """
        <?xml version="1.0" encoding="UTF-8"?>
        <opml version="2.0">
          <body>
            <outline text="Feed" xmlUrl="https://example.com/rss.xml" htmlUrl="https://example.com"/>
          </body>
        </opml>
        """
        
        let outlines = opmlManager.parseOPML(opml)
        XCTAssertEqual(outlines[0].htmlUrl, "https://example.com")
    }
    
    // MARK: - Import Tests
    
    func testImportNewFeeds() {
        let opml = """
        <?xml version="1.0" encoding="UTF-8"?>
        <opml version="2.0">
          <body>
            <outline type="rss" text="New Feed 1" xmlUrl="https://example.com/feed1.xml"/>
            <outline type="rss" text="New Feed 2" xmlUrl="https://example.com/feed2.xml"/>
          </body>
        </opml>
        """
        
        let result = opmlManager.importFromString(opml)
        
        XCTAssertEqual(result.imported.count, 2)
        XCTAssertTrue(result.duplicates.isEmpty)
        XCTAssertEqual(result.skipped, 0)
        XCTAssertEqual(result.totalOutlines, 2)
    }
    
    func testImportSkipsDuplicates() {
        // BBC is already in FeedManager (default feed)
        let opml = """
        <?xml version="1.0" encoding="UTF-8"?>
        <opml version="2.0">
          <body>
            <outline type="rss" text="BBC World News" xmlUrl="https://feeds.bbci.co.uk/news/world/rss.xml"/>
            <outline type="rss" text="New Feed" xmlUrl="https://example.com/new.xml"/>
          </body>
        </opml>
        """
        
        let result = opmlManager.importFromString(opml)
        
        XCTAssertEqual(result.imported.count, 1)
        XCTAssertEqual(result.duplicates.count, 1)
        XCTAssertEqual(result.imported[0].name, "New Feed")
        XCTAssertEqual(result.duplicates[0].name, "BBC World News")
    }
    
    func testImportSkipsInvalidURLs() {
        let opml = """
        <?xml version="1.0" encoding="UTF-8"?>
        <opml version="2.0">
          <body>
            <outline type="rss" text="Invalid" xmlUrl="not-a-url"/>
            <outline type="rss" text="FTP" xmlUrl="ftp://example.com/feed"/>
            <outline type="rss" text="Valid" xmlUrl="https://example.com/feed.xml"/>
          </body>
        </opml>
        """
        
        let result = opmlManager.importFromString(opml)
        
        XCTAssertEqual(result.imported.count, 1)
        XCTAssertEqual(result.skipped, 2)
        XCTAssertEqual(result.imported[0].name, "Valid")
    }
    
    func testImportEnableAllFlag() {
        let opml = """
        <?xml version="1.0" encoding="UTF-8"?>
        <opml version="2.0">
          <body>
            <outline type="rss" text="Feed" xmlUrl="https://example.com/feed.xml"/>
          </body>
        </opml>
        """
        
        // enableAll = true (default)
        let result1 = opmlManager.importFromString(opml, enableAll: true)
        XCTAssertTrue(result1.imported[0].isEnabled)
        
        // Clean up for next test
        FeedManager.shared.resetToDefaults()
        
        // enableAll = false
        let result2 = opmlManager.importFromString(opml, enableAll: false)
        XCTAssertFalse(result2.imported[0].isEnabled)
    }
    
    func testImportEmptyOPML() {
        let result = opmlManager.importFromString("")
        XCTAssertTrue(result.imported.isEmpty)
        XCTAssertEqual(result.totalOutlines, 0)
    }
    
    // MARK: - Import Result Summary Tests
    
    func testImportResultSummaryImportedOnly() {
        let result = OPMLImportResult(imported: [
            Feed(name: "A", url: "https://a.com", isEnabled: true),
            Feed(name: "B", url: "https://b.com", isEnabled: true)
        ], duplicates: [], skipped: 0, totalOutlines: 2)
        
        XCTAssertEqual(result.summary, "2 feeds imported")
    }
    
    func testImportResultSummarySingleFeed() {
        let result = OPMLImportResult(imported: [
            Feed(name: "A", url: "https://a.com", isEnabled: true)
        ], duplicates: [], skipped: 0, totalOutlines: 1)
        
        XCTAssertEqual(result.summary, "1 feed imported")
    }
    
    func testImportResultSummaryWithDuplicates() {
        let result = OPMLImportResult(imported: [
            Feed(name: "A", url: "https://a.com", isEnabled: true)
        ], duplicates: [
            Feed(name: "B", url: "https://b.com", isEnabled: true)
        ], skipped: 0, totalOutlines: 2)
        
        XCTAssertEqual(result.summary, "1 feed imported, 1 duplicate skipped")
    }
    
    func testImportResultSummaryWithSkipped() {
        let result = OPMLImportResult(imported: [], duplicates: [], skipped: 3, totalOutlines: 3)
        XCTAssertEqual(result.summary, "0 feeds imported, 3 invalid outlines skipped")
    }
    
    func testImportResultSummaryFull() {
        let result = OPMLImportResult(imported: [
            Feed(name: "A", url: "https://a.com", isEnabled: true),
            Feed(name: "B", url: "https://b.com", isEnabled: true)
        ], duplicates: [
            Feed(name: "C", url: "https://c.com", isEnabled: true)
        ], skipped: 1, totalOutlines: 4)
        
        XCTAssertEqual(result.summary, "2 feeds imported, 1 duplicate skipped, 1 invalid outline skipped")
    }
    
    // MARK: - Round-Trip Tests
    
    func testExportThenImportRoundTrip() {
        // Start fresh with known feeds
        FeedManager.shared.resetToDefaults()
        FeedManager.shared.addCustomFeed(name: "Test Feed A", url: "https://example.com/a.xml")
        FeedManager.shared.addCustomFeed(name: "Test Feed B", url: "https://example.com/b.xml")
        
        let originalCount = FeedManager.shared.count
        let opml = opmlManager.exportToString()
        
        // Reset and import
        FeedManager.shared.resetToDefaults()
        let result = opmlManager.importFromString(opml)
        
        // BBC (default) is still there, so it's a duplicate
        // The two test feeds should be imported
        XCTAssertEqual(result.imported.count, 2)
        XCTAssertEqual(result.duplicates.count, 1) // BBC World News
        XCTAssertEqual(FeedManager.shared.count, 3) // BBC + A + B
    }
    
    func testExportPreservesSpecialCharactersInRoundTrip() {
        FeedManager.shared.resetToDefaults()
        FeedManager.shared.addCustomFeed(name: "Tech & Science", url: "https://example.com/tech-science.xml")
        
        let opml = opmlManager.exportToString()
        
        FeedManager.shared.resetToDefaults()
        let result = opmlManager.importFromString(opml)
        
        let techFeed = result.imported.first { $0.name == "Tech & Science" }
        XCTAssertNotNil(techFeed, "Feed with special characters should round-trip correctly")
    }
    
    // MARK: - File Export Tests
    
    func testExportToTemporaryFile() {
        do {
            let fileURL = try opmlManager.exportToTemporaryFile()
            XCTAssertTrue(FileManager.default.fileExists(atPath: fileURL.path))
            XCTAssertTrue(fileURL.lastPathComponent.hasPrefix("FeedReader-"))
            XCTAssertTrue(fileURL.lastPathComponent.hasSuffix(".opml"))
            
            let content = try String(contentsOf: fileURL, encoding: .utf8)
            XCTAssertTrue(content.contains("<opml"))
            
            // Clean up
            try? FileManager.default.removeItem(at: fileURL)
        } catch {
            XCTFail("Export to temporary file failed: \(error)")
        }
    }
    
    func testExportToFile() {
        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent("test-export.opml")
        
        do {
            try opmlManager.exportToFile(tempURL)
            
            let content = try String(contentsOf: tempURL, encoding: .utf8)
            XCTAssertTrue(content.contains("<opml version=\"2.0\">"))
            XCTAssertTrue(content.contains("BBC World News"))
            
            // Clean up
            try FileManager.default.removeItem(at: tempURL)
        } catch {
            XCTFail("Export to file failed: \(error)")
        }
    }
    
    // MARK: - Real-World OPML Tests
    
    func testParseRealWorldFeedly() {
        // Feedly-style OPML with htmlUrl and category attributes
        let opml = """
        <?xml version="1.0" encoding="UTF-8"?>
        <opml version="1.0">
          <head><title>My Feedly subscriptions</title></head>
          <body>
            <outline text="Tech" title="Tech">
              <outline type="rss" text="Hacker News" title="Hacker News" xmlUrl="https://hnrss.org/frontpage" htmlUrl="https://news.ycombinator.com/"/>
              <outline type="rss" text="TechCrunch" title="TechCrunch" xmlUrl="https://techcrunch.com/feed/" htmlUrl="https://techcrunch.com"/>
            </outline>
            <outline text="News" title="News">
              <outline type="rss" text="BBC News" title="BBC News - World" xmlUrl="https://feeds.bbci.co.uk/news/world/rss.xml" htmlUrl="https://www.bbc.co.uk/news/world"/>
            </outline>
          </body>
        </opml>
        """
        
        let outlines = opmlManager.parseOPML(opml)
        XCTAssertEqual(outlines.count, 3)
        XCTAssertEqual(outlines[0].title, "Hacker News")
        XCTAssertEqual(outlines[0].htmlUrl, "https://news.ycombinator.com/")
        XCTAssertEqual(outlines[0].category, "Tech")
    }
    
    func testParseLargeOPML() {
        var opml = """
        <?xml version="1.0" encoding="UTF-8"?>
        <opml version="2.0">
          <body>
        """
        
        // Generate 50 feeds
        for i in 1...50 {
            opml += "    <outline type=\"rss\" text=\"Feed \(i)\" xmlUrl=\"https://example.com/feed\(i).xml\"/>\n"
        }
        
        opml += """
          </body>
        </opml>
        """
        
        let outlines = opmlManager.parseOPML(opml)
        XCTAssertEqual(outlines.count, 50)
        XCTAssertEqual(outlines[0].title, "Feed 1")
        XCTAssertEqual(outlines[49].title, "Feed 50")
    }
}
