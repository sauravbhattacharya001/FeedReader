//
//  OfflineCacheManager.swift
//  FeedReader
//
//  Manages offline article caching — save stories for reading without
//  an internet connection. Stores full article content (title, body,
//  source feed) with per-article metadata (save date, size estimate).
//  Uses NSSecureCoding for persistence with automatic cache eviction.
//

import UIKit

/// Notification posted when the offline cache changes (save/remove/clear).
extension Notification.Name {
    static let offlineCacheDidChange = Notification.Name("OfflineCacheDidChangeNotification")
}

/// Metadata for a cached article.
class CachedArticle: NSObject, NSSecureCoding {

    static var supportsSecureCoding: Bool { return true }

    let story: Story
    let savedDate: Date
    let estimatedSizeBytes: Int

    struct Keys {
        static let story = "cachedStory"
        static let savedDate = "cachedSavedDate"
        static let estimatedSizeBytes = "cachedEstimatedSize"
    }

    init(story: Story, savedDate: Date = Date()) {
        self.story = story
        self.savedDate = savedDate
        self.estimatedSizeBytes = CachedArticle.estimateSize(story)
        super.init()
    }

    func encode(with coder: NSCoder) {
        coder.encode(story, forKey: Keys.story)
        coder.encode(savedDate, forKey: Keys.savedDate)
        coder.encode(estimatedSizeBytes, forKey: Keys.estimatedSizeBytes)
    }

    required convenience init?(coder: NSCoder) {
        guard let story = coder.decodeObject(of: Story.self, forKey: Keys.story) else {
            return nil
        }
        let savedDate = coder.decodeObject(of: NSDate.self, forKey: Keys.savedDate) as Date? ?? Date()
        let size = coder.decodeInteger(forKey: Keys.estimatedSizeBytes)
        self.init(story: story, savedDate: savedDate)
        // Ignore stored size — recalculate
        _ = size
    }

    /// Estimate the storage size of a story in bytes (title + body + link + metadata).
    static func estimateSize(_ story: Story) -> Int {
        var size = story.title.utf8.count
        size += story.body.utf8.count
        size += story.link.utf8.count
        size += (story.sourceFeedName?.utf8.count ?? 0)
        size += 64 // overhead for dates, keys, etc.
        return size
    }
}

class OfflineCacheManager {

    // MARK: - Singleton

    static let shared = OfflineCacheManager()

    // MARK: - Constants

    /// Maximum number of articles that can be cached.
    static let maxArticles = 200

    /// Maximum total cache size in bytes (10 MB).
    static let maxCacheSizeBytes = 10 * 1024 * 1024

    /// Days before a cached article is considered stale (auto-cleanup).
    static let staleAfterDays = 30

    // MARK: - Properties

    private(set) var cachedArticles: [CachedArticle] = []

    /// O(1) lookup index for cache checks.
    private var cacheIndex = Set<String>()

    /// Running total of estimated cache size in bytes.
    private var _totalSizeBytes: Int = 0

    /// Serial queue protecting all mutable state. All reads and writes
    /// to `cachedArticles`, `cacheIndex`, and `_totalSizeBytes` must
    /// happen on this queue to avoid data races when the cache is
    /// accessed from background threads (e.g., notification handlers,
    /// prefetch operations).
    private let queue = DispatchQueue(label: "com.feedreader.offlineCache")

    private static let archiveURL: URL = {
        let documentsDirectory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        return documentsDirectory.appendingPathComponent("offlineCache")
    }()

    // MARK: - Initialization

    private init() {
        loadCache()
    }

    // MARK: - Public API

    /// Check if a story is cached for offline reading (O(1) lookup).
    func isCached(_ story: Story) -> Bool {
        return queue.sync { cacheIndex.contains(story.link) }
    }

    /// Save a story for offline reading. Returns true if saved, false if
    /// already cached or cache limits are reached.
    @discardableResult
    func saveForOffline(_ story: Story) -> Bool {
        return queue.sync {
            guard !cacheIndex.contains(story.link) else { return false }

            let article = CachedArticle(story: story)

            // Check article count limit
            if cachedArticles.count >= OfflineCacheManager.maxArticles {
                // Remove oldest to make room
                removeOldestUnsafe()
            }

            // Check total size limit
            while _totalSizeBytes + article.estimatedSizeBytes > OfflineCacheManager.maxCacheSizeBytes
                    && !cachedArticles.isEmpty {
                removeOldestUnsafe()
            }

            cachedArticles.insert(article, at: 0) // newest first
            cacheIndex.insert(story.link)
            _totalSizeBytes += article.estimatedSizeBytes
            persistCache()
            NotificationCenter.default.post(name: .offlineCacheDidChange, object: nil)
            return true
        }
    }

    /// Remove a story from the offline cache.
    func removeFromCache(_ story: Story) {
        queue.sync {
            if let idx = cachedArticles.firstIndex(where: { $0.story.link == story.link }) {
                let removed = cachedArticles.remove(at: idx)
                _totalSizeBytes -= removed.estimatedSizeBytes
            }
            cacheIndex.remove(story.link)
            persistCache()
            NotificationCenter.default.post(name: .offlineCacheDidChange, object: nil)
        }
    }

    /// Remove a cached article at a specific index.
    func removeFromCache(at index: Int) {
        queue.sync {
            guard index >= 0 && index < cachedArticles.count else { return }
            let removed = cachedArticles.remove(at: index)
            cacheIndex.remove(removed.story.link)
            _totalSizeBytes -= removed.estimatedSizeBytes
            persistCache()
            NotificationCenter.default.post(name: .offlineCacheDidChange, object: nil)
        }
    }

    /// Toggle offline cache state for a story. Returns true if now cached.
    @discardableResult
    func toggleCache(_ story: Story) -> Bool {
        return queue.sync {
            if cacheIndex.contains(story.link) {
                if let idx = cachedArticles.firstIndex(where: { $0.story.link == story.link }) {
                    let removed = cachedArticles.remove(at: idx)
                    _totalSizeBytes -= removed.estimatedSizeBytes
                }
                cacheIndex.remove(story.link)
                persistCache()
                NotificationCenter.default.post(name: .offlineCacheDidChange, object: nil)
                return false
            } else {
                let article = CachedArticle(story: story)
                if cachedArticles.count >= OfflineCacheManager.maxArticles {
                    removeOldestUnsafe()
                }
                while _totalSizeBytes + article.estimatedSizeBytes > OfflineCacheManager.maxCacheSizeBytes
                        && !cachedArticles.isEmpty {
                    removeOldestUnsafe()
                }
                cachedArticles.insert(article, at: 0)
                cacheIndex.insert(story.link)
                _totalSizeBytes += article.estimatedSizeBytes
                persistCache()
                NotificationCenter.default.post(name: .offlineCacheDidChange, object: nil)
                return true
            }
        }
    }

    /// Number of cached articles.
    var count: Int {
        return queue.sync { cachedArticles.count }
    }

    /// Total estimated cache size in bytes (O(1) lookup).
    var totalSizeBytes: Int {
        return queue.sync { _totalSizeBytes }
    }

    /// Formatted cache size string (e.g., "1.2 MB", "345 KB").
    var formattedSize: String {
        return OfflineCacheManager.formatBytes(totalSizeBytes)
    }

    /// Remove all cached articles.
    func clearAll() {
        queue.sync {
            cachedArticles.removeAll()
            cacheIndex.removeAll()
            _totalSizeBytes = 0
            persistCache()
            NotificationCenter.default.post(name: .offlineCacheDidChange, object: nil)
        }
    }

    /// Remove articles older than the stale threshold.
    /// Returns the number of articles removed.
    @discardableResult
    func purgeStale() -> Int {
        return queue.sync {
            let cutoff = Calendar.current.date(byAdding: .day, value: -OfflineCacheManager.staleAfterDays, to: Date())!
            let before = cachedArticles.count
            cachedArticles.removeAll { $0.savedDate < cutoff }
            cacheIndex = Set(cachedArticles.map { $0.story.link })
            _totalSizeBytes = cachedArticles.reduce(0) { $0 + $1.estimatedSizeBytes }
            let removed = before - cachedArticles.count
            if removed > 0 {
                persistCache()
                NotificationCenter.default.post(name: .offlineCacheDidChange, object: nil)
            }
            return removed
        }
    }

    /// Get cached articles sorted by save date (newest first).
    var sortedByDate: [CachedArticle] {
        return queue.sync { cachedArticles.sorted { $0.savedDate > $1.savedDate } }
    }

    /// Get cached articles from a specific feed.
    func articles(fromFeed feedName: String) -> [CachedArticle] {
        return queue.sync { cachedArticles.filter { $0.story.sourceFeedName == feedName } }
    }

    /// Get a list of unique feed names in the cache.
    var cachedFeedNames: [String] {
        return queue.sync {
            let names = Set(cachedArticles.compactMap { $0.story.sourceFeedName })
            return names.sorted()
        }
    }

    /// Search cached articles by title or body text.
    func search(query: String) -> [CachedArticle] {
        return queue.sync {
            guard !query.isEmpty else { return cachedArticles }
            let lowered = query.lowercased()
            return cachedArticles.filter {
                $0.story.title.lowercased().contains(lowered)
                    || $0.story.body.lowercased().contains(lowered)
            }
        }
    }

    /// Cache utilization as a percentage (0-100).
    var utilizationPercent: Double {
        return queue.sync {
            let countPercent = Double(cachedArticles.count) / Double(OfflineCacheManager.maxArticles) * 100
            let sizePercent = Double(_totalSizeBytes) / Double(OfflineCacheManager.maxCacheSizeBytes) * 100
            return max(countPercent, sizePercent)
        }
    }

    /// Summary statistics for display.
    var summary: CacheSummary {
        return queue.sync {
            CacheSummary(
                articleCount: cachedArticles.count,
                totalSizeBytes: _totalSizeBytes,
                formattedSize: OfflineCacheManager.formatBytes(_totalSizeBytes),
                feedCount: Set(cachedArticles.compactMap { $0.story.sourceFeedName }).count,
                utilizationPercent: {
                    let countPercent = Double(cachedArticles.count) / Double(OfflineCacheManager.maxArticles) * 100
                    let sizePercent = Double(_totalSizeBytes) / Double(OfflineCacheManager.maxCacheSizeBytes) * 100
                    return max(countPercent, sizePercent)
                }(),
                oldestDate: cachedArticles.last?.savedDate,
                newestDate: cachedArticles.first?.savedDate
            )
        }
    }

    // MARK: - Helpers

    /// Format bytes into a human-readable string.
    static func formatBytes(_ bytes: Int) -> String {
        if bytes < 1024 {
            return "\(bytes) B"
        } else if bytes < 1024 * 1024 {
            let kb = Double(bytes) / 1024.0
            return String(format: "%.1f KB", kb)
        } else {
            let mb = Double(bytes) / (1024.0 * 1024.0)
            return String(format: "%.1f MB", mb)
        }
    }

    /// Remove the oldest cached article. Must be called on `queue`.
    private func removeOldestUnsafe() {
        guard !cachedArticles.isEmpty else { return }
        let removed = cachedArticles.removeLast()
        cacheIndex.remove(removed.story.link)
        _totalSizeBytes -= removed.estimatedSizeBytes
    }

    // MARK: - Persistence

    private func persistCache() {
        do {
            let data = try NSKeyedArchiver.archivedData(
                withRootObject: cachedArticles,
                requiringSecureCoding: true
            )
            try data.write(to: OfflineCacheManager.archiveURL)
        } catch {
            print("Failed to save offline cache: \(error)")
        }
    }

    private func loadCache() {
        guard let data = try? Data(contentsOf: OfflineCacheManager.archiveURL) else {
            cachedArticles = []
            cacheIndex = Set<String>()
            _totalSizeBytes = 0
            return
        }
        if let loaded = (try? NSKeyedUnarchiver.unarchivedObject(
            ofClasses: [NSArray.self, CachedArticle.self, Story.self],
            from: data
        )) as? [CachedArticle] {
            cachedArticles = loaded
            cacheIndex = Set(loaded.map { $0.story.link })
            _totalSizeBytes = cachedArticles.reduce(0) { $0 + $1.estimatedSizeBytes }
        } else {
            cachedArticles = []
            cacheIndex = Set<String>()
            _totalSizeBytes = 0
        }
    }

    /// Force a reload from disk (useful for testing).
    func reload() {
        loadCache()
    }
}

/// Summary statistics for the offline cache.
struct CacheSummary {
    let articleCount: Int
    let totalSizeBytes: Int
    let formattedSize: String
    let feedCount: Int
    let utilizationPercent: Double
    let oldestDate: Date?
    let newestDate: Date?
}
