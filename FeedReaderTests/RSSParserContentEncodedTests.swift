import XCTest
@testable import FeedReader

/// Tests for content:encoded RSS element support.
///
/// Many RSS feeds (especially WordPress) use <content:encoded> to provide
/// the full article body, while <description> contains only a truncated summary.
/// The parser should prefer content:encoded when available.
class RSSParserContentEncodedTests: XCTestCase {

    // MARK: - Helpers

    private func parseStories(from data: Data) -> [Story] {
        let context = FeedParseContext()
        return context.parse(data: data)
    }

    // MARK: - Tests

    func testContentEncodedPreferredOverDescription() {
        let xml = """
        <?xml version="1.0" encoding="UTF-8"?>
        <rss version="2.0" xmlns:content="http://purl.org/rss/1.0/modules/content/">
          <channel>
            <title>Test Feed</title>
            <item>
              <title>Article With Full Content</title>
              <description>This is just a summary.</description>
              <content:encoded><![CDATA[<p>This is the full article body with <b>rich HTML content</b> that is much longer than the description.</p>]]></content:encoded>
              <link>https://example.com/article</link>
            </item>
          </channel>
        </rss>
        """
        let data = xml.data(using: .utf8)!
        let stories = parseStories(from: data)

        XCTAssertEqual(stories.count, 1)
        // Should use content:encoded, not the truncated description
        XCTAssertTrue(stories[0].body.contains("full article body"),
                      "Parser should prefer content:encoded over description")
        XCTAssertFalse(stories[0].body.contains("just a summary"),
                       "Description should not be used when content:encoded is available")
    }

    func testFallsBackToDescriptionWhenNoContentEncoded() {
        let xml = """
        <?xml version="1.0" encoding="UTF-8"?>
        <rss version="2.0">
          <channel>
            <title>Test Feed</title>
            <item>
              <title>Simple Article</title>
              <description>This is the article description only.</description>
              <link>https://example.com/simple</link>
            </item>
          </channel>
        </rss>
        """
        let data = xml.data(using: .utf8)!
        let stories = parseStories(from: data)

        XCTAssertEqual(stories.count, 1)
        XCTAssertTrue(stories[0].body.contains("article description only"),
                      "Parser should fall back to description when content:encoded is absent")
    }

    func testEmptyContentEncodedFallsBackToDescription() {
        let xml = """
        <?xml version="1.0" encoding="UTF-8"?>
        <rss version="2.0" xmlns:content="http://purl.org/rss/1.0/modules/content/">
          <channel>
            <title>Test Feed</title>
            <item>
              <title>Empty Content Article</title>
              <description>Fallback description text.</description>
              <content:encoded></content:encoded>
              <link>https://example.com/empty-content</link>
            </item>
          </channel>
        </rss>
        """
        let data = xml.data(using: .utf8)!
        let stories = parseStories(from: data)

        XCTAssertEqual(stories.count, 1)
        XCTAssertTrue(stories[0].body.contains("Fallback description"),
                      "Empty content:encoded should fall back to description")
    }
}
