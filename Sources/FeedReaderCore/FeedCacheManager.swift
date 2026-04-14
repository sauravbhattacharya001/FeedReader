//
//  FeedCacheManager.swift
//  FeedReaderCore
//
//  Implements HTTP conditional GET caching for RSS feeds using
//  ETag and Last-Modified headers. Avoids re-downloading unchanged
//  feed content, reducing bandwidth and server load significantly
//  for feeds that update infrequently.
//

import Foundation

/// Stores HTTP caching metadata (ETag, Last-Modified) for feed URLs.
///
/// When a feed server supports conditional requests, subsequent fetches
/// can receive a 304 Not Modified response instead of the full feed body,
/// saving bandwidth and parse time. This is especially impactful for
/// users subscribed to many feeds with varying update frequencies.
///
/// ## Usage
/// ```swift
/// let cache = FeedCacheManager()
///
/// // Before fetching, apply cached headers:
/// var request = URLRequest(url: feedURL)
/// cache.applyCacheHeaders(to: &request, for: feedURL)
///
/// // After receiving a response:
/// if cache.isNotModified(response) {
///     // Use previously cached stories instead of re-parsing
/// } else {
///     cache.updateCache(from: response, for: feedURL)
///     // Parse the new data
/// }
/// ```
public final class FeedCacheManager: @unchecked Sendable {

    // MARK: - Types

    /// Cached HTTP metadata for a single feed URL.
    struct CacheEntry: Codable {
        /// ETag header value from the server.
        var etag: String?
        /// Last-Modified header value from the server.
        var lastModified: String?
        /// When this cache entry was last updated.
        var updatedAt: Date
    }

    // MARK: - Properties

    /// In-memory cache keyed by normalized URL string.
    private var entries: [String: CacheEntry] = [:]

    /// Serial queue protecting the entries dictionary.
    private let queue = DispatchQueue(label: "com.feedreadercore.cacheManager")

    /// File URL for persisting cache to disk (nil = memory-only).
    private let persistenceURL: URL?

    /// Pending save work item — used to debounce rapid cache updates.
    /// When multiple feeds complete in quick succession (e.g. during a
    /// bulk refresh of 50+ subscriptions), coalescing disk writes into
    /// a single save avoids redundant JSON encoding + I/O overhead.
    private var pendingSave: DispatchWorkItem?

    /// Debounce interval for disk persistence (seconds).
    /// Cache updates within this window are coalesced into one write.
    private let saveDebounceInterval: TimeInterval

    // MARK: - Initialization

    /// Creates a cache manager.
    /// - Parameters:
    ///   - persistenceURL: Optional file URL to persist cache across launches.
    ///     Pass `nil` for in-memory-only caching (useful for testing).
    ///   - saveDebounceInterval: Seconds to wait before flushing to disk
    ///     (default 0.5). Subsequent saves within the window reset the timer,
    ///     coalescing many updates into one I/O operation.
    public init(persistenceURL: URL? = nil, saveDebounceInterval: TimeInterval = 0.5) {
        self.persistenceURL = persistenceURL
        self.saveDebounceInterval = saveDebounceInterval
        if let url = persistenceURL {
            loadFromDisk(url)
        }
    }

    /// Convenience initializer that stores cache in the app's caches directory.
    public convenience init(cacheDirectory: URL) {
        let fileURL = cacheDirectory.appendingPathComponent("feed_cache_metadata.json")
        self.init(persistenceURL: fileURL)
    }

    deinit {
        // Flush any pending save synchronously so data isn't lost on teardown.
        queue.sync {
            pendingSave?.cancel()
            saveToDiskNow()
        }
    }

    // MARK: - Public API

    /// Applies cached ETag/Last-Modified headers to a URL request
    /// for conditional GET support.
    ///
    /// If the server returns 304 Not Modified, the client can skip
    /// downloading and parsing the feed body entirely.
    ///
    /// - Parameters:
    ///   - request: The URLRequest to modify (inout).
    ///   - url: The feed URL to look up cached headers for.
    public func applyCacheHeaders(to request: inout URLRequest, for url: URL) {
        let key = normalizeURL(url)
        let entry = queue.sync { entries[key] }

        if let etag = entry?.etag {
            request.setValue(etag, forHTTPHeaderField: "If-None-Match")
        }
        if let lastModified = entry?.lastModified {
            request.setValue(lastModified, forHTTPHeaderField: "If-Modified-Since")
        }
    }

    /// Checks whether an HTTP response indicates the content has not changed.
    /// - Parameter response: The URLResponse from the feed request.
    /// - Returns: `true` if the server returned 304 Not Modified.
    public func isNotModified(_ response: URLResponse?) -> Bool {
        guard let httpResponse = response as? HTTPURLResponse else { return false }
        return httpResponse.statusCode == 304
    }

    /// Updates the cache with ETag and Last-Modified values from a response.
    ///
    /// Call this after receiving a successful (200) response. The cached
    /// values will be sent as conditional headers on the next request.
    ///
    /// - Parameters:
    ///   - response: The HTTP response containing cache headers.
    ///   - url: The feed URL to associate the cache entry with.
    public func updateCache(from response: URLResponse?, for url: URL) {
        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else { return }

        let etag = httpResponse.value(forHTTPHeaderField: "ETag")
        let lastModified = httpResponse.value(forHTTPHeaderField: "Last-Modified")

        // Only cache if the server provided at least one conditional header
        guard etag != nil || lastModified != nil else { return }

        let key = normalizeURL(url)
        let entry = CacheEntry(etag: etag, lastModified: lastModified, updatedAt: Date())

        queue.async { [weak self] in
            self?.entries[key] = entry
            self?.scheduleSave()
        }
    }

    /// Removes the cache entry for a specific feed URL.
    public func invalidate(for url: URL) {
        let key = normalizeURL(url)
        queue.async { [weak self] in
            self?.entries.removeValue(forKey: key)
            self?.scheduleSave()
        }
    }

    /// Removes all cache entries.
    public func invalidateAll() {
        queue.async { [weak self] in
            self?.entries.removeAll()
            self?.scheduleSave()
        }
    }

    /// Returns the number of cached feed entries.
    public var count: Int {
        return queue.sync { entries.count }
    }

    /// Returns whether a cache entry exists for the given URL.
    public func hasCacheEntry(for url: URL) -> Bool {
        let key = normalizeURL(url)
        return queue.sync { entries[key] != nil }
    }

    /// Removes cache entries older than the specified interval.
    /// - Parameter maxAge: Maximum age in seconds (default: 30 days).
    public func evictStaleEntries(olderThan maxAge: TimeInterval = 30 * 24 * 3600) {
        let cutoff = Date().addingTimeInterval(-maxAge)
        queue.async { [weak self] in
            self?.entries = self?.entries.filter { $0.value.updatedAt > cutoff } ?? [:]
            self?.scheduleSave()
        }
    }

    /// Immediately flushes any pending debounced save to disk.
    ///
    /// Call before app suspension or when you need to guarantee persistence.
    /// Safe to call from any thread.
    public func flush() {
        queue.sync {
            pendingSave?.cancel()
            pendingSave = nil
            saveToDiskNow()
        }
    }

    // MARK: - Private

    /// Normalizes a URL for use as a cache key (lowercased, no trailing slash).
    private func normalizeURL(_ url: URL) -> String {
        var s = url.absoluteString.lowercased()
        if s.hasSuffix("/") { s.removeLast() }
        return s
    }

    /// Loads cache from disk if available.
    private func loadFromDisk(_ url: URL) {
        guard let data = try? Data(contentsOf: url),
              let decoded = try? JSONDecoder().decode([String: CacheEntry].self, from: data) else {
            return
        }
        entries = decoded
    }

    /// Schedules a debounced save. Must be called on `queue`.
    ///
    /// Cancels any previously scheduled save and starts a new timer.
    /// When many feeds complete within a short window (common during
    /// bulk refresh), this collapses N disk writes into one.
    private func scheduleSave() {
        pendingSave?.cancel()
        let item = DispatchWorkItem { [weak self] in
            self?.saveToDiskNow()
        }
        pendingSave = item
        queue.asyncAfter(deadline: .now() + saveDebounceInterval, execute: item)
    }

    /// Persists cache to disk immediately. Must be called on `queue`.
    private func saveToDiskNow() {
        guard let url = persistenceURL else { return }
        guard let data = try? JSONEncoder().encode(entries) else { return }
        try? data.write(to: url, options: .atomic)
    }
}
