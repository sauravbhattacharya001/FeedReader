import XCTest
@testable import FeedReader

/// Security tests for RSS feed parsing URL scheme validation.
///
/// Ensures that malicious URL schemes (javascript:, data:, file:, etc.)
/// are rejected at parse time, not just at click time.
class RSSParserSecurityTests: XCTestCase {

    // MARK: - Helpers

    /// Builds a minimal valid RSS XML feed with the given link and optional image URL.
    private func rssXML(link: String, imageURL: String? = nil) -> Data {
        var mediaTag = ""
        if let imageURL = imageURL {
            mediaTag = "<media:thumbnail url=\"\(imageURL)\"/>"
        }
        let xml = """
        <?xml version="1.0" encoding="UTF-8"?>
        <rss version="2.0" xmlns:media="http://search.yahoo.com/mrss/">
          <channel>
            <title>Test Feed</title>
            <item>
              <title>Test Story</title>
              <description>A test story body that is long enough.</description>
              <link>\(link)</link>
              <guid>guid-001</guid>
              \(mediaTag)
            </item>
          </channel>
        </rss>
        """
        return xml.data(using: .utf8)!
    }

    /// Parses the given RSS data and returns the parsed stories.
    private func parseStories(from data: Data) -> [Story] {
        let context = FeedParseContext()
        return context.parse(data: data)
    }

    // MARK: - Link validation: unsafe schemes rejected

    func testJavascriptLinkIsRejected() {
        let data = rssXML(link: "javascript:alert(document.cookie)")
        let stories = parseStories(from: data)
        XCTAssertTrue(stories.isEmpty, "Stories with javascript: link should be rejected at parse time")
    }

    func testDataLinkIsRejected() {
        let data = rssXML(link: "data:text/html,<h1>evil</h1>")
        let stories = parseStories(from: data)
        XCTAssertTrue(stories.isEmpty, "Stories with data: link should be rejected at parse time")
    }

    func testFileLinkIsRejected() {
        let data = rssXML(link: "file:///etc/passwd")
        let stories = parseStories(from: data)
        XCTAssertTrue(stories.isEmpty, "Stories with file: link should be rejected at parse time")
    }

    func testFTPLinkIsRejected() {
        let data = rssXML(link: "ftp://evil.com/payload")
        let stories = parseStories(from: data)
        XCTAssertTrue(stories.isEmpty, "Stories with ftp: link should be rejected at parse time")
    }

    // MARK: - Link validation: safe schemes accepted

    func testHTTPSLinkIsAccepted() {
        let data = rssXML(link: "https://example.com/article")
        let stories = parseStories(from: data)
        XCTAssertEqual(stories.count, 1, "Stories with https: link should be accepted")
        XCTAssertEqual(stories.first?.link, "https://example.com/article")
    }

    func testHTTPLinkIsAccepted() {
        let data = rssXML(link: "http://example.com/article")
        let stories = parseStories(from: data)
        XCTAssertEqual(stories.count, 1, "Stories with http: link should be accepted")
        XCTAssertEqual(stories.first?.link, "http://example.com/article")
    }

    // MARK: - Image path validation

    func testMaliciousImagePathIsSanitizedToNil() {
        let data = rssXML(link: "https://example.com/article", imageURL: "javascript:x")
        let stories = parseStories(from: data)
        // Story may or may not be present (link is safe) but image must be nil
        if let story = stories.first {
            XCTAssertNil(story.imagePath, "Image path with javascript: scheme should be sanitized to nil")
        }
    }

    func testDataImagePathIsSanitizedToNil() {
        let data = rssXML(link: "https://example.com/article", imageURL: "data:image/png;base64,evil")
        let stories = parseStories(from: data)
        if let story = stories.first {
            XCTAssertNil(story.imagePath, "Image path with data: scheme should be sanitized to nil")
        }
    }

    func testValidImagePathIsKept() {
        let data = rssXML(link: "https://example.com/article", imageURL: "https://img.example.com/photo.jpg")
        let stories = parseStories(from: data)
        XCTAssertEqual(stories.count, 1)
        XCTAssertEqual(stories.first?.imagePath, "https://img.example.com/photo.jpg",
                       "Valid https image path should be preserved")
    }

    func testHTTPImagePathIsKept() {
        let data = rssXML(link: "https://example.com/article", imageURL: "http://img.example.com/photo.jpg")
        let stories = parseStories(from: data)
        XCTAssertEqual(stories.count, 1)
        XCTAssertEqual(stories.first?.imagePath, "http://img.example.com/photo.jpg",
                       "Valid http image path should be preserved")
    }

    // MARK: - Edge cases

    func testEmptyLinkIsRejected() {
        let data = rssXML(link: "")
        let stories = parseStories(from: data)
        XCTAssertTrue(stories.isEmpty, "Stories with empty link should be rejected")
    }

    func testMultipleStoriesMixedSchemes() {
        let xml = """
        <?xml version="1.0" encoding="UTF-8"?>
        <rss version="2.0">
          <channel>
            <title>Mixed Feed</title>
            <item>
              <title>Good Story</title>
              <description>A valid story with enough body text.</description>
              <link>https://good.example.com</link>
            </item>
            <item>
              <title>Evil Story</title>
              <description>A malicious story with enough body text.</description>
              <link>javascript:alert(1)</link>
            </item>
            <item>
              <title>Another Good Story</title>
              <description>Another valid story with enough body text.</description>
              <link>http://also-good.example.com</link>
            </item>
          </channel>
        </rss>
        """
        let data = xml.data(using: .utf8)!
        let stories = parseStories(from: data)
        XCTAssertEqual(stories.count, 2, "Only stories with safe URL schemes should be parsed")
        XCTAssertEqual(stories[0].link, "https://good.example.com")
        XCTAssertEqual(stories[1].link, "http://also-good.example.com")
    }
}
