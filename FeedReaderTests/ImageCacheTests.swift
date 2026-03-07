//
//  ImageCacheTests.swift
//  FeedReaderTests
//
//  Tests for ImageCache: in-memory caching, cache eviction,
//  prefetch deduplication, and disk path hashing stability.
//

import XCTest
@testable import FeedReader

class ImageCacheTests: XCTestCase {

    var cache: ImageCache!

    override func setUp() {
        super.setUp()
        cache = ImageCache.shared
        cache.clearCache()
    }

    override func tearDown() {
        cache.clearCache()
        super.tearDown()
    }

    // MARK: - In-Memory Cache

    func testSetAndRetrieveImage() {
        let image = createTestImage(color: .red, size: CGSize(width: 100, height: 100))
        let key = "https://example.com/test-image.jpg"

        cache.setImage(image, forKey: key)
        let retrieved = cache.image(forKey: key)

        XCTAssertNotNil(retrieved, "Cached image should be retrievable")
    }

    func testCacheMissReturnsNil() {
        let result = cache.image(forKey: "https://example.com/nonexistent.jpg")
        XCTAssertNil(result, "Cache miss should return nil")
    }

    func testOverwriteExistingKey() {
        let key = "https://example.com/overwrite.jpg"
        let image1 = createTestImage(color: .red, size: CGSize(width: 50, height: 50))
        let image2 = createTestImage(color: .blue, size: CGSize(width: 80, height: 80))

        cache.setImage(image1, forKey: key)
        cache.setImage(image2, forKey: key)
        let retrieved = cache.image(forKey: key)

        XCTAssertNotNil(retrieved)
        // The second image should have replaced the first
        XCTAssertEqual(retrieved?.size.width, 80, accuracy: 1.0,
                       "Overwritten image should have new dimensions")
    }

    func testClearCacheRemovesAllEntries() {
        let keys = (0..<10).map { "https://example.com/image\($0).jpg" }
        for key in keys {
            cache.setImage(createTestImage(color: .green, size: CGSize(width: 20, height: 20)), forKey: key)
        }

        cache.clearCache()

        for key in keys {
            XCTAssertNil(cache.image(forKey: key),
                         "All entries should be cleared after clearCache()")
        }
    }

    func testDifferentKeysAreSeparate() {
        let key1 = "https://example.com/a.jpg"
        let key2 = "https://example.com/b.jpg"
        let image1 = createTestImage(color: .red, size: CGSize(width: 30, height: 30))
        let image2 = createTestImage(color: .blue, size: CGSize(width: 60, height: 60))

        cache.setImage(image1, forKey: key1)
        cache.setImage(image2, forKey: key2)

        let r1 = cache.image(forKey: key1)
        let r2 = cache.image(forKey: key2)

        XCTAssertNotNil(r1)
        XCTAssertNotNil(r2)
        XCTAssertEqual(r1?.size.width, 30, accuracy: 1.0)
        XCTAssertEqual(r2?.size.width, 60, accuracy: 1.0)
    }

    // MARK: - Thumbnail Max Pixels

    func testMaxThumbnailPixelsIsReasonable() {
        // Sanity check: thumbnails shouldn't be too large (wastes memory)
        // or too small (looks blurry on retina)
        XCTAssertGreaterThanOrEqual(ImageCache.maxThumbnailPixels, 200,
                                    "Thumbnails should be at least 200px for retina displays")
        XCTAssertLessThanOrEqual(ImageCache.maxThumbnailPixels, 1200,
                                 "Thumbnails above 1200px defeat the purpose of downsampling")
    }

    // MARK: - Cancel Prefetches

    func testCancelPrefetchesDoesNotCrash() {
        // Cancelling with no active tasks should be safe
        cache.cancelPrefetches()

        // Start some prefetches then cancel immediately
        let urls = (0..<5).map { "https://httpbin.org/image/png?id=\($0)" }
        cache.prefetch(urls: urls)
        cache.cancelPrefetches()
        // No crash = pass
    }

    // MARK: - Load Image Validation

    func testLoadImageRejectsEmptyURL() {
        let expectation = self.expectation(description: "Empty URL rejected")

        cache.loadImage(from: "") { image in
            XCTAssertNil(image, "Empty URL should return nil")
            expectation.fulfill()
        }

        waitForExpectations(timeout: 2.0)
    }

    func testLoadImageRejectsJavascriptURL() {
        let expectation = self.expectation(description: "JavaScript URL rejected")

        cache.loadImage(from: "javascript:alert(1)") { image in
            XCTAssertNil(image, "JavaScript URLs should be rejected by safety check")
            expectation.fulfill()
        }

        waitForExpectations(timeout: 2.0)
    }

    func testLoadImageRejectsDataURL() {
        let expectation = self.expectation(description: "Data URL rejected")

        cache.loadImage(from: "data:text/html,<script>alert(1)</script>") { image in
            XCTAssertNil(image, "Data URLs should be rejected by safety check")
            expectation.fulfill()
        }

        waitForExpectations(timeout: 2.0)
    }

    // MARK: - Prefetch Deduplication

    func testPrefetchSkipsAlreadyCachedImages() {
        let key = "https://example.com/already-cached.jpg"
        let image = createTestImage(color: .cyan, size: CGSize(width: 40, height: 40))
        cache.setImage(image, forKey: key)

        // Prefetching an already-cached URL should be a no-op (no network request)
        cache.prefetch(urls: [key])

        // Image should still be the same
        let retrieved = cache.image(forKey: key)
        XCTAssertNotNil(retrieved)
        XCTAssertEqual(retrieved?.size.width, 40, accuracy: 1.0)
    }

    // MARK: - Helpers

    /// Create a solid-color test image.
    private func createTestImage(color: UIColor, size: CGSize) -> UIImage {
        let renderer = UIGraphicsImageRenderer(size: size)
        return renderer.image { context in
            color.setFill()
            context.fill(CGRect(origin: .zero, size: size))
        }
    }
}
