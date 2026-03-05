//
//  FeedMergeManager.swift
//  FeedReader
//
//  Virtual merged feeds that combine multiple feed sources into a single
//  unified stream. Users can create named merged feeds, pick which source
//  feeds to include, choose a sort order, and get a deduplicated article
//  list across all member feeds.
//

import Foundation

// MARK: - Sort Order

/// How articles in a merged feed are ordered.
enum MergedFeedSortOrder: String, Codable, CaseIterable {
    case newestFirst = "newest"
    case oldestFirst = "oldest"
    case alphabetical = "alphabetical"
    case sourceThenDate = "sourceThenDate"

    var displayName: String {
        switch self {
        case .newestFirst: return "Newest First"
        case .oldestFirst: return "Oldest First"
        case .alphabetical: return "A → Z by Title"
        case .sourceThenDate: return "By Source, then Date"
        }
    }
}

// MARK: - Merged Feed Model

/// A virtual feed that aggregates articles from multiple source feed URLs.
struct MergedFeed: Codable, Equatable {
    let id: String
    var name: String
    var icon: String              // emoji icon
    var feedURLs: [String]        // URLs of member feeds
    var sortOrder: MergedFeedSortOrder
    var deduplicationEnabled: Bool
    var maxArticles: Int          // 0 = unlimited
    let createdAt: Date
    var updatedAt: Date

    init(name: String,
         icon: String = "📦",
         feedURLs: [String] = [],
         sortOrder: MergedFeedSortOrder = .newestFirst,
         deduplicationEnabled: Bool = true,
         maxArticles: Int = 0) {
        self.id = UUID().uuidString
        self.name = name
        self.icon = icon
        self.feedURLs = feedURLs
        self.sortOrder = sortOrder
        self.deduplicationEnabled = deduplicationEnabled
        self.maxArticles = maxArticles
        let now = Date()
        self.createdAt = now
        self.updatedAt = now
    }

    /// Number of source feeds in this merge.
    var sourceCount: Int { feedURLs.count }
}

// MARK: - Merged Article

/// An article produced by merging, with its source feed URL attached.
struct MergedArticle: Equatable {
    let title: String
    let link: String
    let body: String
    let sourceFeedURL: String
    let sourceFeedName: String?
    let date: Date?

    /// Fingerprint for deduplication — lowercased title trimmed of whitespace.
    var fingerprint: String {
        return title.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

// MARK: - Manager

/// Creates, stores, and resolves virtual merged feeds.
class FeedMergeManager {

    // MARK: - Singleton

    static let shared = FeedMergeManager()

    // MARK: - Storage

    private(set) var mergedFeeds: [MergedFeed] = []

    private static var storageURL: URL {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        return docs.appendingPathComponent("mergedFeeds.json")
    }

    // MARK: - Init

    init() {
        load()
    }

    // MARK: - CRUD

    /// Create a new merged feed. Returns the created feed.
    @discardableResult
    func create(name: String,
                icon: String = "📦",
                feedURLs: [String] = [],
                sortOrder: MergedFeedSortOrder = .newestFirst,
                deduplicationEnabled: Bool = true,
                maxArticles: Int = 0) -> MergedFeed {
        guard !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return MergedFeed(name: "Untitled", icon: icon, feedURLs: feedURLs,
                              sortOrder: sortOrder, deduplicationEnabled: deduplicationEnabled,
                              maxArticles: maxArticles)
        }
        var feed = MergedFeed(name: name, icon: icon, feedURLs: feedURLs,
                              sortOrder: sortOrder, deduplicationEnabled: deduplicationEnabled,
                              maxArticles: maxArticles)
        mergedFeeds.append(feed)
        save()
        return feed
    }

    /// Find a merged feed by id.
    func find(id: String) -> MergedFeed? {
        return mergedFeeds.first { $0.id == id }
    }

    /// Update a merged feed in-place. Returns updated feed or nil if not found.
    @discardableResult
    func update(id: String, _ mutate: (inout MergedFeed) -> Void) -> MergedFeed? {
        guard let idx = mergedFeeds.firstIndex(where: { $0.id == id }) else { return nil }
        mutate(&mergedFeeds[idx])
        mergedFeeds[idx].updatedAt = Date()
        save()
        return mergedFeeds[idx]
    }

    /// Delete a merged feed by id. Returns true if found and removed.
    @discardableResult
    func delete(id: String) -> Bool {
        guard let idx = mergedFeeds.firstIndex(where: { $0.id == id }) else { return false }
        mergedFeeds.remove(at: idx)
        save()
        return true
    }

    /// Delete all merged feeds.
    func deleteAll() {
        mergedFeeds.removeAll()
        save()
    }

    // MARK: - Feed URL Management

    /// Add a source feed URL to a merged feed.
    @discardableResult
    func addFeed(url: String, to mergedFeedId: String) -> Bool {
        return update(id: mergedFeedId) { feed in
            let normalized = url.lowercased()
            if !feed.feedURLs.map({ $0.lowercased() }).contains(normalized) {
                feed.feedURLs.append(url)
            }
        } != nil
    }

    /// Remove a source feed URL from a merged feed.
    @discardableResult
    func removeFeed(url: String, from mergedFeedId: String) -> Bool {
        return update(id: mergedFeedId) { feed in
            let normalized = url.lowercased()
            feed.feedURLs.removeAll { $0.lowercased() == normalized }
        } != nil
    }

    // MARK: - Article Resolution

    /// Resolve articles for a merged feed from a provider closure.
    /// The closure maps a feed URL → array of (title, link, body, date?) tuples.
    func resolveArticles(
        for mergedFeedId: String,
        articleProvider: (String) -> [(title: String, link: String, body: String, sourceName: String?, date: Date?)]
    ) -> [MergedArticle] {
        guard let feed = find(id: mergedFeedId) else { return [] }
        return resolveArticles(for: feed, articleProvider: articleProvider)
    }

    /// Resolve articles for a given merged feed struct.
    func resolveArticles(
        for feed: MergedFeed,
        articleProvider: (String) -> [(title: String, link: String, body: String, sourceName: String?, date: Date?)]
    ) -> [MergedArticle] {
        var articles: [MergedArticle] = []

        for feedURL in feed.feedURLs {
            let items = articleProvider(feedURL)
            for item in items {
                let article = MergedArticle(
                    title: item.title,
                    link: item.link,
                    body: item.body,
                    sourceFeedURL: feedURL,
                    sourceFeedName: item.sourceName,
                    date: item.date
                )
                articles.append(article)
            }
        }

        // Deduplicate
        if feed.deduplicationEnabled {
            articles = deduplicate(articles)
        }

        // Sort
        articles = sort(articles, by: feed.sortOrder)

        // Limit
        if feed.maxArticles > 0 && articles.count > feed.maxArticles {
            articles = Array(articles.prefix(feed.maxArticles))
        }

        return articles
    }

    // MARK: - Deduplication

    /// Remove duplicate articles by title fingerprint, keeping the first occurrence.
    func deduplicate(_ articles: [MergedArticle]) -> [MergedArticle] {
        var seen = Set<String>()
        var result: [MergedArticle] = []
        for article in articles {
            let fp = article.fingerprint
            if !seen.contains(fp) {
                seen.insert(fp)
                result.append(article)
            }
        }
        return result
    }

    // MARK: - Sorting

    /// Sort articles by the given order.
    func sort(_ articles: [MergedArticle], by order: MergedFeedSortOrder) -> [MergedArticle] {
        switch order {
        case .newestFirst:
            return articles.sorted { ($0.date ?? .distantPast) > ($1.date ?? .distantPast) }
        case .oldestFirst:
            return articles.sorted { ($0.date ?? .distantFuture) < ($1.date ?? .distantFuture) }
        case .alphabetical:
            return articles.sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
        case .sourceThenDate:
            return articles.sorted {
                let srcCmp = ($0.sourceFeedURL).localizedCaseInsensitiveCompare($1.sourceFeedURL)
                if srcCmp != .orderedSame { return srcCmp == .orderedAscending }
                return ($0.date ?? .distantPast) > ($1.date ?? .distantPast)
            }
        }
    }

    // MARK: - Search

    /// Search merged feeds by name (case-insensitive substring).
    func search(query: String) -> [MergedFeed] {
        let q = query.lowercased()
        return mergedFeeds.filter { $0.name.lowercased().contains(q) }
    }

    /// Find all merged feeds that include a given feed URL.
    func mergedFeedsContaining(feedURL: String) -> [MergedFeed] {
        let normalized = feedURL.lowercased()
        return mergedFeeds.filter { feed in
            feed.feedURLs.contains { $0.lowercased() == normalized }
        }
    }

    // MARK: - Statistics

    /// Stats for a merged feed.
    struct MergedFeedStats {
        let id: String
        let name: String
        let sourceCount: Int
        let totalArticles: Int
        let uniqueArticles: Int
        let duplicatesRemoved: Int
        let oldestArticle: Date?
        let newestArticle: Date?
    }

    /// Compute stats for a merged feed using an article provider.
    func stats(
        for mergedFeedId: String,
        articleProvider: (String) -> [(title: String, link: String, body: String, sourceName: String?, date: Date?)]
    ) -> MergedFeedStats? {
        guard let feed = find(id: mergedFeedId) else { return nil }

        var allArticles: [MergedArticle] = []
        for feedURL in feed.feedURLs {
            for item in articleProvider(feedURL) {
                allArticles.append(MergedArticle(
                    title: item.title, link: item.link, body: item.body,
                    sourceFeedURL: feedURL, sourceFeedName: item.sourceName, date: item.date
                ))
            }
        }

        let deduped = deduplicate(allArticles)
        let dates = allArticles.compactMap { $0.date }

        return MergedFeedStats(
            id: feed.id,
            name: feed.name,
            sourceCount: feed.sourceCount,
            totalArticles: allArticles.count,
            uniqueArticles: deduped.count,
            duplicatesRemoved: allArticles.count - deduped.count,
            oldestArticle: dates.min(),
            newestArticle: dates.max()
        )
    }

    // MARK: - Text Report

    /// Human-readable report of all merged feeds.
    func textReport(
        articleProvider: ((String) -> [(title: String, link: String, body: String, sourceName: String?, date: Date?)])? = nil
    ) -> String {
        var lines: [String] = []
        lines.append("=== Feed Merge Report ===")
        lines.append("Total merged feeds: \(mergedFeeds.count)")
        lines.append("")

        for feed in mergedFeeds {
            lines.append("\(feed.icon) \(feed.name)")
            lines.append("  Sources: \(feed.sourceCount)")
            lines.append("  Sort: \(feed.sortOrder.displayName)")
            lines.append("  Dedup: \(feed.deduplicationEnabled ? "On" : "Off")")
            if feed.maxArticles > 0 {
                lines.append("  Max articles: \(feed.maxArticles)")
            }

            if let provider = articleProvider,
               let s = stats(for: feed.id, articleProvider: provider) {
                lines.append("  Articles: \(s.totalArticles) total, \(s.uniqueArticles) unique, \(s.duplicatesRemoved) dupes removed")
            }
            lines.append("")
        }

        return lines.joined(separator: "\n")
    }

    // MARK: - Export / Import

    /// Export all merged feeds as JSON data.
    func exportJSON() -> Data? {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try? encoder.encode(mergedFeeds)
    }

    /// Import merged feeds from JSON data. Appends to existing, skipping duplicates by id.
    func importJSON(_ data: Data) -> Int {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let imported = try? decoder.decode([MergedFeed].self, from: data) else { return 0 }
        let existingIds = Set(mergedFeeds.map { $0.id })
        var count = 0
        for feed in imported {
            if !existingIds.contains(feed.id) {
                mergedFeeds.append(feed)
                count += 1
            }
        }
        if count > 0 { save() }
        return count
    }

    // MARK: - Persistence

    func save() {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        if let data = try? encoder.encode(mergedFeeds) {
            try? data.write(to: Self.storageURL, options: .atomic)
        }
    }

    func load() {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let data = try? Data(contentsOf: Self.storageURL),
              let feeds = try? decoder.decode([MergedFeed].self, from: data) else { return }
        self.mergedFeeds = feeds
    }

    /// Reset in-memory state (for testing).
    func reset() {
        mergedFeeds.removeAll()
    }
}
