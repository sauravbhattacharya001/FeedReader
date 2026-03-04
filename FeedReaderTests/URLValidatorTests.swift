//
//  URLValidatorTests.swift
//  FeedReaderTests
//
//  Tests for URLValidator SSRF protection and URL validation.
//

import XCTest
@testable import FeedReader

final class URLValidatorTests: XCTestCase {

    // MARK: - isSafe — allowed URLs

    func testPublicHTTPSIsSafe() {
        XCTAssertTrue(URLValidator.isSafe("https://feeds.bbci.co.uk/news/rss.xml"))
    }

    func testPublicHTTPIsSafe() {
        XCTAssertTrue(URLValidator.isSafe("http://example.com/rss"))
    }

    func testPublicIPIsSafe() {
        // Public IP (Google DNS)
        XCTAssertTrue(URLValidator.isSafe("https://8.8.8.8/feed"))
    }

    // MARK: - isSafe — rejected schemes

    func testFTPSchemeRejected() {
        XCTAssertFalse(URLValidator.isSafe("ftp://example.com/rss"))
    }

    func testFileSchemeRejected() {
        XCTAssertFalse(URLValidator.isSafe("file:///etc/passwd"))
    }

    func testJavaScriptSchemeRejected() {
        XCTAssertFalse(URLValidator.isSafe("javascript:alert(1)"))
    }

    func testNoSchemeRejected() {
        XCTAssertFalse(URLValidator.isSafe("example.com/rss"))
    }

    func testNilRejected() {
        XCTAssertFalse(URLValidator.isSafe(nil))
    }

    func testEmptyStringRejected() {
        XCTAssertFalse(URLValidator.isSafe(""))
    }

    // MARK: - isSafe — SSRF: loopback

    func testLocalhostRejected() {
        XCTAssertFalse(URLValidator.isSafe("http://localhost/admin"))
    }

    func testLocalhostWithPortRejected() {
        XCTAssertFalse(URLValidator.isSafe("http://localhost:8080/"))
    }

    func testSubdomainOfLocalhostRejected() {
        XCTAssertFalse(URLValidator.isSafe("http://foo.localhost/x"))
    }

    func testIPv4LoopbackRejected() {
        XCTAssertFalse(URLValidator.isSafe("http://127.0.0.1/"))
    }

    func testIPv4LoopbackAltRejected() {
        XCTAssertFalse(URLValidator.isSafe("http://127.1.2.3/admin"))
    }

    // MARK: - SSRF: private networks

    func testPrivate10Rejected() {
        XCTAssertFalse(URLValidator.isSafe("http://10.0.0.1/"))
    }

    func testPrivate172Rejected() {
        XCTAssertFalse(URLValidator.isSafe("http://172.16.0.1/"))
    }

    func testPrivate172UpperRejected() {
        XCTAssertFalse(URLValidator.isSafe("http://172.31.255.255/"))
    }

    func testPrivate192Rejected() {
        XCTAssertFalse(URLValidator.isSafe("http://192.168.1.1/"))
    }

    func testNonPrivate172Allowed() {
        // 172.15.x.x is NOT private
        XCTAssertTrue(URLValidator.isSafe("http://172.15.0.1/feed"))
    }

    func testNonPrivate172UpperAllowed() {
        // 172.32.x.x is NOT private
        XCTAssertTrue(URLValidator.isSafe("http://172.32.0.1/feed"))
    }

    // MARK: - SSRF: cloud metadata

    func testCloudMetadataIPRejected() {
        XCTAssertFalse(URLValidator.isSafe("http://169.254.169.254/latest/meta-data/"))
    }

    func testLinkLocalRejected() {
        XCTAssertFalse(URLValidator.isSafe("http://169.254.0.1/"))
    }

    // MARK: - SSRF: CGN / shared

    func testCGNRejected() {
        XCTAssertFalse(URLValidator.isSafe("http://100.64.0.1/"))
    }

    func testCGNUpperRejected() {
        XCTAssertFalse(URLValidator.isSafe("http://100.127.255.255/"))
    }

    func testNonCGNAllowed() {
        XCTAssertTrue(URLValidator.isSafe("http://100.128.0.1/feed"))
    }

    // MARK: - SSRF: IPv6

    func testIPv6LoopbackRejected() {
        XCTAssertFalse(URLValidator.isSafe("http://[::1]/"))
    }

    func testIPv6LinkLocalRejected() {
        XCTAssertFalse(URLValidator.isSafe("http://[fe80::1]/"))
    }

    func testIPv6UniqueLocalRejected() {
        XCTAssertFalse(URLValidator.isSafe("http://[fd12::1]/"))
    }

    // MARK: - SSRF: special hostnames

    func testDotLocalRejected() {
        XCTAssertFalse(URLValidator.isSafe("http://router.local/admin"))
    }

    func testDotInternalRejected() {
        XCTAssertFalse(URLValidator.isSafe("http://service.internal/"))
    }

    func testGoogleMetadataRejected() {
        XCTAssertFalse(URLValidator.isSafe("http://metadata.google.internal/"))
    }

    // MARK: - SSRF: zero network

    func testZeroNetworkRejected() {
        XCTAssertFalse(URLValidator.isSafe("http://0.0.0.0/"))
    }

    // MARK: - SSRF: broadcast

    func testBroadcastRejected() {
        XCTAssertFalse(URLValidator.isSafe("http://255.255.255.255/"))
    }

    // MARK: - SSRF: test nets

    func testTestNet1Rejected() {
        XCTAssertFalse(URLValidator.isSafe("http://192.0.2.1/"))
    }

    func testTestNet2Rejected() {
        XCTAssertFalse(URLValidator.isSafe("http://198.51.100.1/"))
    }

    func testTestNet3Rejected() {
        XCTAssertFalse(URLValidator.isSafe("http://203.0.113.1/"))
    }

    // MARK: - validateFeedURL

    func testValidateFeedURLPublic() {
        let url = URLValidator.validateFeedURL("https://example.com/feed.xml")
        XCTAssertNotNil(url)
        XCTAssertEqual(url?.host, "example.com")
    }

    func testValidateFeedURLPrivateReturnsNil() {
        XCTAssertNil(URLValidator.validateFeedURL("http://192.168.1.1/rss"))
    }

    func testValidateFeedURLLocalhostReturnsNil() {
        XCTAssertNil(URLValidator.validateFeedURL("http://localhost:3000/api"))
    }

    func testValidateFeedURLInvalidReturnsNil() {
        XCTAssertNil(URLValidator.validateFeedURL("not a url"))
    }

    func testValidateFeedURLEmptyReturnsNil() {
        XCTAssertNil(URLValidator.validateFeedURL(""))
    }

    // MARK: - isPrivateOrReserved direct tests

    func testPublicHostNotPrivate() {
        XCTAssertFalse(URLValidator.isPrivateOrReserved(host: "feeds.bbci.co.uk"))
    }

    func testPublicIPNotPrivate() {
        XCTAssertFalse(URLValidator.isPrivateOrReserved(host: "93.184.216.34"))
    }

    func testLocalhostIsPrivate() {
        XCTAssertTrue(URLValidator.isPrivateOrReserved(host: "localhost"))
    }

    func testLoopbackIsPrivate() {
        XCTAssertTrue(URLValidator.isPrivateOrReserved(host: "127.0.0.1"))
    }

    func testMetadataIPIsPrivate() {
        XCTAssertTrue(URLValidator.isPrivateOrReserved(host: "169.254.169.254"))
    }

    // MARK: - Story.isSafeURL integration

    func testStoryIsSafeURLRejectsPrivate() {
        XCTAssertFalse(Story.isSafeURL("http://192.168.1.1/article"))
    }

    func testStoryIsSafeURLAllowsPublic() {
        XCTAssertTrue(Story.isSafeURL("https://example.com/article"))
    }

    func testStoryIsSafeURLRejectsNil() {
        XCTAssertFalse(Story.isSafeURL(nil))
    }
}
