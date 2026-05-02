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

    func testURLNormalizationCaseInsensitive() {
        let cache = FeedCacheManager()
        let url1 = URL(string: "HTTPS://Example.COM/Feed")!
        let url2 = URL(string: "https://example.com/feed")!

        cache.updateCache(from: mockResponse(url: url1, status: 200, headers: ["ETag": "\"x\""]), for: url1)

        let exp = expectation(description: "wait")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { exp.fulfill() }
        wait(for: [exp], timeout: 1.0)

        XCTAssertTrue(cache.hasCacheEntry(for: url2))
        XCTAssertEqual(cache.count, 1)
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
