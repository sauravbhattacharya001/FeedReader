//
//  RSSParserXXETests.swift
//  FeedReaderCoreTests
//
//  Hardening tests for `RSSParser`'s defenses against XML External Entity
//  (XXE / CWE-611) attacks. A malicious feed publisher could craft an RSS
//  payload whose DTD declares a SYSTEM entity pointing at a local file
//  (`file:///etc/passwd`) or an internal HTTP endpoint
//  (`http://169.254.169.254/...`). XMLParser's defaults disable external
//  entity resolution, but defense-in-depth is required because:
//
//   1. Default behaviour has shifted across iOS/macOS SDK versions.
//   2. Callers can inadvertently flip the setting.
//   3. Even when the entity is not *resolved*, partial story collection
//      should not be exposed to the caller from a malicious feed.
//
//  These tests pin the contract: any feed declaring an external/unparsed
//  entity yields zero stories, never partially-parsed content.
//

import XCTest
@testable import FeedReaderCore

final class RSSParserXXETests: XCTestCase {

    private func data(_ s: String) -> Data {
        return s.data(using: .utf8)!
    }

    /// Baseline: a benign RSS document with no DTD still parses normally
    /// after the XXE callbacks were added. Locks down a regression where
    /// the hardening could accidentally make normal feeds parse as empty.
    func testBenignRSSStillParses() {
        let xml = """
        <?xml version="1.0" encoding="UTF-8"?>
        <rss version="2.0">
          <channel>
            <title>Test Channel</title>
            <item>
              <title>Hello</title>
              <description>World</description>
              <link>https://example.com/1</link>
            </item>
          </channel>
        </rss>
        """
        let parser = RSSParser()
        let stories = parser.parseData(data(xml))
        XCTAssertEqual(stories.count, 1)
        XCTAssertEqual(stories.first?.title, "Hello")
    }

    /// Classic XXE payload: declare `<!ENTITY xxe SYSTEM "file:///etc/passwd">`
    /// and reference it in a title. The parser must NOT surface any
    /// stories from a feed that contains an external SYSTEM entity.
    func testRSSWithExternalFileEntityYieldsNoStories() {
        let xml = """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE rss [
          <!ENTITY xxe SYSTEM "file:///etc/passwd">
        ]>
        <rss version="2.0">
          <channel>
            <title>Pwned</title>
            <item>
              <title>Leak &xxe;</title>
              <description>This should not appear in results.</description>
              <link>https://attacker.example.com/1</link>
            </item>
          </channel>
        </rss>
        """
        let parser = RSSParser()
        let stories = parser.parseData(data(xml))
        XCTAssertEqual(stories.count, 0,
                       "Stories from a feed declaring an external SYSTEM entity must be discarded.")
    }

    /// XXE-driven SSRF variant: SYSTEM URI is the AWS instance metadata
    /// endpoint. Even though XMLParser will not resolve the entity, the
    /// declaration is treated as hostile and the entire feed is dropped.
    func testRSSWithExternalHTTPEntityYieldsNoStories() {
        let xml = """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE rss [
          <!ENTITY ssrf SYSTEM "http://169.254.169.254/latest/meta-data/">
        ]>
        <rss version="2.0">
          <channel>
            <item>
              <title>Hi &ssrf;</title>
              <description>x</description>
              <link>https://x.example.com/2</link>
            </item>
          </channel>
        </rss>
        """
        let parser = RSSParser()
        let stories = parser.parseData(data(xml))
        XCTAssertEqual(stories.count, 0)
    }

    /// Atom feeds traverse the same parser path - verify the XXE
    /// callbacks fire for Atom as well, not just RSS 2.0.
    func testAtomWithExternalEntityYieldsNoStories() {
        let xml = """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE feed [
          <!ENTITY xxe SYSTEM "file:///etc/hostname">
        ]>
        <feed xmlns="http://www.w3.org/2005/Atom">
          <title>Bad Atom</title>
          <entry>
            <title>X &xxe;</title>
            <summary>y</summary>
            <link href="https://atom.example.com/e1"/>
          </entry>
        </feed>
        """
        let parser = RSSParser()
        let stories = parser.parseData(data(xml))
        XCTAssertEqual(stories.count, 0)
    }
}
