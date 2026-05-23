//
//  FeedCacheManagerTests.swift
//  FeedReaderCoreTests
//
//  Tests for FeedCacheManager — HTTP conditional GET caching with
//  ETag/Last-Modified, persistence, eviction, and debounced saves.
//

import XCTest
@testable import FeedReaderCore

final class FeedCacheManagerTests: XCTestCase {

    // MARK: - Helpers

    private func makeURL(_ path: String = "/feed") -> URL {
        URL(string: "https://example.com\(path)")!
    }

    /// Creates a mock HTTPURLResponse with given status and headers.
    private func mockResponse(url: URL, status: Int,
                              headers: [String: String] = [:]) -> HTTPURLResponse {
        HTTPURLResponse(url: url, statusCode: status,
                        httpVersion: "HTTP/1.1", headerFields: headers)!
    }

    private func tempFileURL() -> URL {
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("feedcache-\(UUID().uuidString).json")
        return tmp
    }

    // MARK: - Basic Operations

    func testNewCacheIsEmpty() {
        let cache = FeedCacheManager()
        XCTAssertEqual(cache.count, 0)
    }

    func testUpdateCacheStoresEntry() {
        let cache = FeedCacheManager()
        let url = makeURL()
        let resp = mockResponse(url: url, status: 200,
                                headers: ["ETag": "\"abc123\"",
                                          "Last-Modified": "Wed, 01 Jan 2025 00:00:00 GMT"])
        cache.updateCache(from: resp, for: url)

        // Allow async queue to process
        let exp = expectation(description: "cache update")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { exp.fulfill() }
        wait(for: [exp], timeout: 1.0)

        XCTAssertEqual(cache.count, 1)
        XCTAssertTrue(cache.hasCacheEntry(for: url))
    }

    func testApplyCacheHeadersSetsETagAndLastModified() {
        let cache = FeedCacheManager()
        let url = makeURL()

        let resp = mockResponse(url: url, status: 200,
                                headers: ["ETag": "\"etag-value\"",
                                          "Last-Modified": "Fri, 01 Feb 2025 12:00:00 GMT"])
        cache.updateCache(from: resp, for: url)

        let exp = expectation(description: "wait")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { exp.fulfill() }
        wait(for: [exp], timeout: 1.0)

        var request = URLRequest(url: url)
        cache.applyCacheHeaders(to: &request, for: url)

        XCTAssertEqual(request.value(forHTTPHeaderField: "If-None-Match"), "\"etag-value\"")
        XCTAssertEqual(request.value(forHTTPHeaderField: "If-Modified-Since"), "Fri, 01 Feb 2025 12:00:00 GMT")
    }

    func testApplyCacheHeadersNoopWhenNoCacheEntry() {
        let cache = FeedCacheManager()
        let url = makeURL("/uncached")

        var request = URLRequest(url: url)
        cache.applyCacheHeaders(to: &request, for: url)

        XCTAssertNil(request.value(forHTTPHeaderField: "If-None-Match"))
        XCTAssertNil(request.value(forHTTPHeaderField: "If-Modified-Since"))
    }

    // MARK: - Not Modified Detection

    func testIsNotModifiedFor304() {
        let cache = FeedCacheManager()
        let resp = mockResponse(url: makeURL(), status: 304, headers: [:])
        XCTAssertTrue(cache.isNotModified(resp))
    }

    func testIsNotModifiedFalseFor200() {
        let cache = FeedCacheManager()
        let resp = mockResponse(url: makeURL(), status: 200, headers: [:])
        XCTAssertFalse(cache.isNotModified(resp))
    }

    func testIsNotModifiedFalseForNilResponse() {
        let cache = FeedCacheManager()
        XCTAssertFalse(cache.isNotModified(nil))
    }

    func testIsNotModifiedFalseForNonHTTPResponse() {
        let cache = FeedCacheManager()
        let resp = URLResponse(url: makeURL(), mimeType: nil,
                               expectedContentLength: 0, textEncodingName: nil)
        XCTAssertFalse(cache.isNotModified(resp))
    }

    // MARK: - Update Filtering

    func testUpdateIgnoresNon2xxResponses() {
        let cache = FeedCacheManager()
        let url = makeURL()
        let resp = mockResponse(url: url, status: 404,
                                headers: ["ETag": "\"should-not-cache\""])
        cache.updateCache(from: resp, for: url)

        let exp = expectation(description: "wait")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { exp.fulfill() }
        wait(for: [exp], timeout: 1.0)

        XCTAssertEqual(cache.count, 0)
    }

    func testUpdateIgnoresResponseWithoutCacheHeaders() {
        let cache = FeedCacheManager()
        let url = makeURL()
        let resp = mockResponse(url: url, status: 200, headers: [:])
        cache.updateCache(from: resp, for: url)

        let exp = expectation(description: "wait")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { exp.fulfill() }
        wait(for: [exp], timeout: 1.0)

        XCTAssertEqual(cache.count, 0)
    }

    func testUpdateAcceptsETagOnly() {
        let cache = FeedCacheManager()
        let url = makeURL()
        let resp = mockResponse(url: url, status: 200,
                                headers: ["ETag": "\"etag-only\""])
        cache.updateCache(from: resp, for: url)

        let exp = expectation(description: "wait")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { exp.fulfill() }
        wait(for: [exp], timeout: 1.0)

        XCTAssertEqual(cache.count, 1)
    }

    func testUpdateAcceptsLastModifiedOnly() {
        let cache = FeedCacheManager()
        let url = makeURL()
        let resp = mockResponse(url: url, status: 200,
                                headers: ["Last-Modified": "Wed, 01 Jan 2025 00:00:00 GMT"])
        cache.updateCache(from: resp, for: url)

        let exp = expectation(description: "wait")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { exp.fulfill() }
        wait(for: [exp], timeout: 1.0)

        XCTAssertEqual(cache.count, 1)
    }

    // MARK: - Invalidation

    func testInvalidateSingleURL() {
        let cache = FeedCacheManager()
        let url1 = makeURL("/feed1")
        let url2 = makeURL("/feed2")

        cache.updateCache(from: mockResponse(url: url1, status: 200, headers: ["ETag": "\"a\""]), for: url1)
        cache.updateCache(from: mockResponse(url: url2, status: 200, headers: ["ETag": "\"b\""]), for: url2)

        let exp1 = expectation(description: "wait")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { exp1.fulfill() }
        wait(for: [exp1], timeout: 1.0)

        XCTAssertEqual(cache.count, 2)

        cache.invalidate(for: url1)

        let exp2 = expectation(description: "wait2")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { exp2.fulfill() }
        wait(for: [exp2], timeout: 1.0)

        XCTAssertEqual(cache.count, 1)
        XCTAssertFalse(cache.hasCacheEntry(for: url1))
        XCTAssertTrue(cache.hasCacheEntry(for: url2))
    }

    func testInvalidateAll() {
        let cache = FeedCacheManager()
        for i in 1...5 {
            let url = makeURL("/feed\(i)")
            cache.updateCache(from: mockResponse(url: url, status: 200, headers: ["ETag": "\"\(i)\""]), for: url)
        }

        let exp1 = expectation(description: "wait")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { exp1.fulfill() }
        wait(for: [exp1], timeout: 1.0)

        XCTAssertEqual(cache.count, 5)

        cache.invalidateAll()

        let exp2 = expectation(description: "wait2")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { exp2.fulfill() }
        wait(for: [exp2], timeout: 1.0)

        XCTAssertEqual(cache.count, 0)
    }

    // MARK: - URL Normalization

    /// Scheme and host are case-insensitive per RFC 3986; the cache must
    /// collapse case-only differences in those components.
    func testURLNormalizationCaseInsensitiveSchemeAndHost() {
        let cache = FeedCacheManager()
        let url1 = URL(string: "HTTPS://Example.COM/feed")!
        let url2 = URL(string: "https://example.com/feed")!

        cache.updateCache(from: mockResponse(url: url1, status: 200, headers: ["ETag": "\"x\""]), for: url1)

        let exp = expectation(description: "wait")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { exp.fulfill() }
        wait(for: [exp], timeout: 1.0)

        XCTAssertTrue(cache.hasCacheEntry(for: url2))
        XCTAssertEqual(cache.count, 1)
    }

    /// Path is case-sensitive per RFC 3986 §6.2.2.1. Two URLs that
    /// differ only in path case MUST get separate cache entries -
    /// otherwise the wrong ETag could be sent back to the server,
    /// triggering spurious 304 Not Modified responses for unrelated
    /// resources.
    func testURLNormalizationPathIsCaseSensitive() {
        let cache = FeedCacheManager()
        let url1 = URL(string: "https://example.com/Articles/Foo")!
        let url2 = URL(string: "https://example.com/articles/Foo")!
        let url3 = URL(string: "https://example.com/Articles/foo")!

        cache.updateCache(from: mockResponse(url: url1, status: 200, headers: ["ETag": "\"A\""]), for: url1)

        let exp = expectation(description: "wait")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { exp.fulfill() }
        wait(for: [exp], timeout: 1.0)

        XCTAssertTrue(cache.hasCacheEntry(for: url1))
        XCTAssertFalse(cache.hasCacheEntry(for: url2),
                       "Path '/articles/Foo' must NOT collide with '/Articles/Foo'")
        XCTAssertFalse(cache.hasCacheEntry(for: url3),
                       "Path '/Articles/foo' must NOT collide with '/Articles/Foo'")
    }

    func testURLNormalizationTrailingSlash() {
        let cache = FeedCacheManager()
        let url1 = URL(string: "https://example.com/feed/")!
        let url2 = URL(string: "https://example.com/feed")!

        cache.updateCache(from: mockResponse(url: url1, status: 200, headers: ["ETag": "\"y\""]), for: url1)

        let exp = expectation(description: "wait")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { exp.fulfill() }
        wait(for: [exp], timeout: 1.0)

        XCTAssertTrue(cache.hasCacheEntry(for: url2))
    }

    /// Root-only paths (`https://example.com/`) must keep their `/` so
    /// they do not collapse onto anything else.
    func testURLNormalizationKeepsRootSlash() {
        let cache = FeedCacheManager()
        let url1 = URL(string: "https://example.com/")!

        cache.updateCache(from: mockResponse(url: url1, status: 200, headers: ["ETag": "\"r\""]), for: url1)

        let exp = expectation(description: "wait")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { exp.fulfill() }
        wait(for: [exp], timeout: 1.0)

        XCTAssertTrue(cache.hasCacheEntry(for: url1))
        XCTAssertEqual(cache.count, 1)
    }

    /// Default port (`:443` on https, `:80` on http) must be stripped
    /// so explicit-port URLs share a cache entry with implicit-port ones.
    func testURLNormalizationStripsDefaultPort() {
        let cache = FeedCacheManager()
        let urlExplicit = URL(string: "https://example.com:443/feed")!
        let urlImplicit = URL(string: "https://example.com/feed")!

        cache.updateCache(from: mockResponse(url: urlExplicit, status: 200, headers: ["ETag": "\"d\""]),
                          for: urlExplicit)

        let exp = expectation(description: "wait")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { exp.fulfill() }
        wait(for: [exp], timeout: 1.0)

        XCTAssertTrue(cache.hasCacheEntry(for: urlImplicit))
        XCTAssertEqual(cache.count, 1)
    }

    /// Non-default ports must NOT be stripped - they identify a
    /// genuinely different resource.
    func testURLNormalizationKeepsNonDefaultPort() {
        let cache = FeedCacheManager()
        let url8080 = URL(string: "https://example.com:8080/feed")!
        let url443 = URL(string: "https://example.com/feed")!

        cache.updateCache(from: mockResponse(url: url8080, status: 200, headers: ["ETag": "\"p\""]),
                          for: url8080)

        let exp = expectation(description: "wait")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { exp.fulfill() }
        wait(for: [exp], timeout: 1.0)

        XCTAssertTrue(cache.hasCacheEntry(for: url8080))
        XCTAssertFalse(cache.hasCacheEntry(for: url443),
                       "Port 8080 must not collide with port 443 entry")
    }

    /// Fragments (`#section`) are never sent to the server and must not
    /// influence the cache key.
    func testURLNormalizationStripsFragment() {
        let cache = FeedCacheManager()
        let urlWithFragment = URL(string: "https://example.com/feed#top")!
        let urlWithoutFragment = URL(string: "https://example.com/feed")!

        cache.updateCache(from: mockResponse(url: urlWithFragment, status: 200, headers: ["ETag": "\"f\""]),
                          for: urlWithFragment)

        let exp = expectation(description: "wait")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { exp.fulfill() }
        wait(for: [exp], timeout: 1.0)

        XCTAssertTrue(cache.hasCacheEntry(for: urlWithoutFragment))
        XCTAssertEqual(cache.count, 1)
    }

    /// Query strings are case-sensitive and must NOT be collapsed.
    /// A server treating `?Page=1` and `?page=1` as different URLs
    /// would otherwise see mismatched If-None-Match headers.
    func testURLNormalizationKeepsQueryCase() {
        let cache = FeedCacheManager()
        let url1 = URL(string: "https://example.com/feed?Page=1&Sort=DESC")!
        let url2 = URL(string: "https://example.com/feed?page=1&sort=desc")!

        cache.updateCache(from: mockResponse(url: url1, status: 200, headers: ["ETag": "\"q\""]), for: url1)

        let exp = expectation(description: "wait")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { exp.fulfill() }
        wait(for: [exp], timeout: 1.0)

        XCTAssertTrue(cache.hasCacheEntry(for: url1))
        XCTAssertFalse(cache.hasCacheEntry(for: url2),
                       "Query case differences must not collapse")
    }

    // MARK: - Stale Entry Eviction

    func testEvictStaleEntriesRemovesOldEntries() {
        let cache = FeedCacheManager()
        let url = makeURL("/old")
        cache.updateCache(from: mockResponse(url: url, status: 200, headers: ["ETag": "\"old\""]), for: url)

        let exp1 = expectation(description: "wait")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { exp1.fulfill() }
        wait(for: [exp1], timeout: 1.0)

        XCTAssertEqual(cache.count, 1)

        // Evict entries older than 0 seconds (everything)
        cache.evictStaleEntries(olderThan: 0)

        let exp2 = expectation(description: "wait2")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { exp2.fulfill() }
        wait(for: [exp2], timeout: 1.0)

        XCTAssertEqual(cache.count, 0)
    }

    func testEvictStaleEntriesKeepsRecentEntries() {
        let cache = FeedCacheManager()
        let url = makeURL("/recent")
        cache.updateCache(from: mockResponse(url: url, status: 200, headers: ["ETag": "\"new\""]), for: url)

        let exp1 = expectation(description: "wait")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { exp1.fulfill() }
        wait(for: [exp1], timeout: 1.0)

        // Evict entries older than 1 day — recent entry should survive
        cache.evictStaleEntries(olderThan: 86400)

        let exp2 = expectation(description: "wait2")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { exp2.fulfill() }
        wait(for: [exp2], timeout: 1.0)

        XCTAssertEqual(cache.count, 1)
    }

    // MARK: - Disk Persistence

    func testPersistenceRoundTrip() {
        let fileURL = tempFileURL()
        defer { try? FileManager.default.removeItem(at: fileURL) }

        // Write cache
        let cache1 = FeedCacheManager(persistenceURL: fileURL)
        let url = makeURL("/persist")
        cache1.updateCache(from: mockResponse(url: url, status: 200,
                                              headers: ["ETag": "\"persisted\""]), for: url)
        cache1.flush()

        // Load into new cache
        let cache2 = FeedCacheManager(persistenceURL: fileURL)
        XCTAssertEqual(cache2.count, 1)
        XCTAssertTrue(cache2.hasCacheEntry(for: url))

        var request = URLRequest(url: url)
        cache2.applyCacheHeaders(to: &request, for: url)
        XCTAssertEqual(request.value(forHTTPHeaderField: "If-None-Match"), "\"persisted\"")
    }

    func testMemoryOnlyCacheWorks() {
        // No persistence URL
        let cache = FeedCacheManager(persistenceURL: nil)
        let url = makeURL()
        cache.updateCache(from: mockResponse(url: url, status: 200,
                                             headers: ["ETag": "\"mem\""]), for: url)

        let exp = expectation(description: "wait")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { exp.fulfill() }
        wait(for: [exp], timeout: 1.0)

        XCTAssertEqual(cache.count, 1)
        // flush on memory-only cache should not crash
        cache.flush()
    }

    func testCacheOverwritesExistingEntry() {
        let cache = FeedCacheManager()
        let url = makeURL()

        cache.updateCache(from: mockResponse(url: url, status: 200, headers: ["ETag": "\"v1\""]), for: url)
        let exp1 = expectation(description: "w1")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { exp1.fulfill() }
        wait(for: [exp1], timeout: 1.0)

        cache.updateCache(from: mockResponse(url: url, status: 200, headers: ["ETag": "\"v2\""]), for: url)
        let exp2 = expectation(description: "w2")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { exp2.fulfill() }
        wait(for: [exp2], timeout: 1.0)

        XCTAssertEqual(cache.count, 1)

        var request = URLRequest(url: url)
        cache.applyCacheHeaders(to: &request, for: url)
        XCTAssertEqual(request.value(forHTTPHeaderField: "If-None-Match"), "\"v2\"")
    }

    // MARK: - Multiple Feeds

    func testMultipleFeedsCachedIndependently() {
        let cache = FeedCacheManager()
        let urls = (1...10).map { makeURL("/feed\($0)") }

        for (i, url) in urls.enumerated() {
            cache.updateCache(from: mockResponse(url: url, status: 200,
                                                 headers: ["ETag": "\"\(i)\""]), for: url)
        }

        let exp = expectation(description: "wait")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { exp.fulfill() }
        wait(for: [exp], timeout: 2.0)

        XCTAssertEqual(cache.count, 10)

        for (i, url) in urls.enumerated() {
            var request = URLRequest(url: url)
            cache.applyCacheHeaders(to: &request, for: url)
            XCTAssertEqual(request.value(forHTTPHeaderField: "If-None-Match"), "\"\(i)\"")
        }
    }
}
