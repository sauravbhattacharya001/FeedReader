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

    // MARK: - SSRF Protection (CWE-918)

    func testImportRejectsFileScheme() {
        let opml = """
        <?xml version="1.0"?>
        <opml version="2.0">
          <body>
            <outline text="Evil" xmlUrl="file:///etc/passwd" />
          </body>
        </opml>
        """
        XCTAssertThrowsError(try OPMLManager.importOPML(from: opml)) { error in
            guard let opmlError = error as? OPMLError else { return XCTFail() }
            if case .noFeedsFound = opmlError {} else { XCTFail("Expected noFeedsFound") }
        }
    }

    func testImportRejectsJavascriptScheme() {
        let opml = """
        <?xml version="1.0"?>
        <opml version="2.0">
          <body>
            <outline text="XSS" xmlUrl="javascript:alert(1)" />
          </body>
        </opml>
        """
        XCTAssertThrowsError(try OPMLManager.importOPML(from: opml)) { error in
            guard let opmlError = error as? OPMLError else { return XCTFail() }
            if case .noFeedsFound = opmlError {} else { XCTFail("Expected noFeedsFound") }
        }
    }

    func testImportRejectsLocalhostURL() {
        let opml = """
        <?xml version="1.0"?>
        <opml version="2.0">
          <body>
            <outline text="Local" xmlUrl="http://localhost:8080/feed" />
          </body>
        </opml>
        """
        XCTAssertThrowsError(try OPMLManager.importOPML(from: opml)) { error in
            guard let opmlError = error as? OPMLError else { return XCTFail() }
            if case .noFeedsFound = opmlError {} else { XCTFail("Expected noFeedsFound") }
        }
    }

    func testImportRejectsPrivateIPURL() {
        let opml = """
        <?xml version="1.0"?>
        <opml version="2.0">
          <body>
            <outline text="Internal" xmlUrl="http://192.168.1.1/feed" />
          </body>
        </opml>
        """
        XCTAssertThrowsError(try OPMLManager.importOPML(from: opml)) { error in
            guard let opmlError = error as? OPMLError else { return XCTFail() }
            if case .noFeedsFound = opmlError {} else { XCTFail("Expected noFeedsFound") }
        }
    }

    func testImportRejectsCloudMetadataURL() {
        let opml = """
        <?xml version="1.0"?>
        <opml version="2.0">
          <body>
            <outline text="Metadata" xmlUrl="http://169.254.169.254/latest/meta-data/" />
          </body>
        </opml>
        """
        XCTAssertThrowsError(try OPMLManager.importOPML(from: opml)) { error in
            guard let opmlError = error as? OPMLError else { return XCTFail() }
            if case .noFeedsFound = opmlError {} else { XCTFail("Expected noFeedsFound") }
        }
    }

    func testImportRejectsLinkLocalIPv6() {
        let opml = """
        <?xml version="1.0"?>
        <opml version="2.0">
          <body>
            <outline text="IPv6" xmlUrl="http://[::1]/feed" />
          </body>
        </opml>
        """
        XCTAssertThrowsError(try OPMLManager.importOPML(from: opml)) { error in
            guard let opmlError = error as? OPMLError else { return XCTFail() }
            if case .noFeedsFound = opmlError {} else { XCTFail("Expected noFeedsFound") }
        }
    }

    func testImportFiltersMixedSafeAndUnsafeURLs() throws {
        let opml = """
        <?xml version="1.0"?>
        <opml version="2.0">
          <body>
            <outline text="Good" xmlUrl="https://example.com/feed" />
            <outline text="Evil" xmlUrl="http://10.0.0.1/internal" />
            <outline text="Also Good" xmlUrl="https://news.ycombinator.com/rss" />
          </body>
        </opml>
        """
        let feeds = try OPMLManager.importOPML(from: opml)
        XCTAssertEqual(feeds.count, 2)
        XCTAssertEqual(feeds[0].name, "Good")
        XCTAssertEqual(feeds[1].name, "Also Good")
    }

    func testIsSafeFeedURLAcceptsPublicHTTPS() {
        XCTAssertTrue(OPMLManager.isSafeFeedURL("https://example.com/feed"))
        XCTAssertTrue(OPMLManager.isSafeFeedURL("http://news.ycombinator.com/rss"))
    }

    func testIsSafeFeedURLRejectsUnsafeSchemes() {
        XCTAssertFalse(OPMLManager.isSafeFeedURL("ftp://example.com/feed"))
        XCTAssertFalse(OPMLManager.isSafeFeedURL("javascript:void(0)"))
        XCTAssertFalse(OPMLManager.isSafeFeedURL("data:text/xml,<rss/>"))
        XCTAssertFalse(OPMLManager.isSafeFeedURL("file:///etc/passwd"))
    }

    func testIsSafeFeedURLRejectsPrivateNetworks() {
        XCTAssertFalse(OPMLManager.isSafeFeedURL("http://127.0.0.1/feed"))
        XCTAssertFalse(OPMLManager.isSafeFeedURL("http://10.0.0.1/feed"))
        XCTAssertFalse(OPMLManager.isSafeFeedURL("http://172.16.0.1/feed"))
        XCTAssertFalse(OPMLManager.isSafeFeedURL("http://192.168.0.1/feed"))
        XCTAssertFalse(OPMLManager.isSafeFeedURL("http://169.254.169.254/meta"))
        XCTAssertFalse(OPMLManager.isSafeFeedURL("http://localhost/feed"))
    }

    // MARK: - XXE / DoS Hardening

    /// An OPML payload that declares a SYSTEM entity pointing at a
    /// local file must be rejected with `externalEntityRejected`,
    /// never silently expanded. Validates CWE-611 defense.
    func testImportRejectsExternalEntityFileSystemRef() {
        let opml = """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE opml [
          <!ENTITY xxe SYSTEM "file:///etc/passwd">
        ]>
        <opml version="2.0">
          <head><title>Pwned &xxe;</title></head>
          <body>
            <outline xmlUrl="https://example.com/feed" text="Decoy"/>
          </body>
        </opml>
        """
        XCTAssertThrowsError(try OPMLManager.importOPML(from: opml)) { error in
            guard case OPMLError.externalEntityRejected = error else {
                XCTFail("Expected externalEntityRejected, got \(error)")
                return
            }
        }
    }

    /// An OPML payload that declares an external entity referencing
    /// the cloud metadata endpoint must also be rejected. This guards
    /// against an XXE-driven SSRF where the resolver would issue an
    /// outbound HTTP request from the app's network context.
    func testImportRejectsExternalEntityHTTPRef() {
        let opml = """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE opml [
          <!ENTITY xxe SYSTEM "http://169.254.169.254/latest/meta-data/">
        ]>
        <opml version="2.0">
          <body>
            <outline xmlUrl="https://example.com/feed" text="Decoy"/>
          </body>
        </opml>
        """
        XCTAssertThrowsError(try OPMLManager.importOPML(from: opml)) { error in
            guard case OPMLError.externalEntityRejected = error else {
                XCTFail("Expected externalEntityRejected, got \(error)")
                return
            }
        }
    }

    /// Inputs larger than the configured cap must throw
    /// `payloadTooLarge` before any parsing work happens.
    func testImportRejectsOversizedPayload() {
        // 32 bytes of arbitrary content, with a 16-byte cap.
        let payload = Data(repeating: 0x20, count: 32)
        XCTAssertThrowsError(try OPMLManager.importOPML(from: payload, maxBytes: 16)) { error in
            guard case OPMLError.payloadTooLarge(let bytes, let max) = error else {
                XCTFail("Expected payloadTooLarge, got \(error)")
                return
            }
            XCTAssertEqual(bytes, 32)
            XCTAssertEqual(max, 16)
        }
    }

    /// The default cap should be high enough to accept any realistic
    /// OPML export. This regression-locks the constant so we don't
    /// accidentally tighten it to a value that breaks normal users.
    func testDefaultMaxOPMLBytesIsReasonable() {
        XCTAssertGreaterThanOrEqual(OPMLManager.defaultMaxOPMLBytes, 1 * 1024 * 1024,
                                    "Default OPML size cap should be at least 1 MiB")
    }

    /// A normal OPML file (no DTD, no entities) must still parse fine
    /// after the XXE callbacks were added.
    func testImportSucceedsForBenignDocumentAfterHardening() throws {
        let opml = """
        <?xml version="1.0" encoding="UTF-8"?>
        <opml version="2.0">
          <body>
            <outline xmlUrl="https://example.com/a" text="A"/>
            <outline xmlUrl="https://example.com/b" text="B"/>
          </body>
        </opml>
        """
        let feeds = try OPMLManager.importOPML(from: opml)
        XCTAssertEqual(feeds.count, 2)
    }
}
