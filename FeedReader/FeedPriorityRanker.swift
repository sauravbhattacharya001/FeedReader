//
//  FeedPriorityRanker.swift
//  FeedReader
//
//  Assign priority levels to feeds so that articles from important
//  sources always surface first. Each feed can be tagged as critical,
//  high, medium, or low priority. Articles are then sorted by priority
//  first and recency second, giving users a "most important first" view.
//

import Foundation

/// Ranks feeds by user-assigned priority and sorts articles accordingly.
///
/// Usage:
/// ```
/// let ranker = FeedPriorityRanker()
///
/// // Assign priorities
/// ranker.setPriority(.critical, for: "https://breaking-news.com/feed")
/// ranker.setPriority(.high, for: "https://tech-blog.com/rss")
/// ranker.setPriority(.low, for: "https://memes-daily.com/feed")
///
/// // Get priority for a feed
/// let p = ranker.priority(for: "https://tech-blog.com/rss")  // .high
///
/// // Sort stories by priority then recency
/// let sorted = ranker.rankArticles(stories, feedURLForStory: { $0.sourceFeedName })
///
/// // Bulk operations
/// ranker.setPriorityForCategory("News", priority: .critical)
/// let stats = ranker.priorityDistribution()
/// ```
class FeedPriorityRanker {

    // MARK: - Types

    /// Priority levels for feeds, ordered from most to least important.
    enum Priority: Int, Comparable, CaseIterable, Codable {
        case critical = 0
        case high = 1
        case medium = 2
        case low = 3

        static func < (lhs: Priority, rhs: Priority) -> Bool {
            return lhs.rawValue < rhs.rawValue
        }

        var displayName: String {
            switch self {
            case .critical: return "🔴 Critical"
            case .high:     return "🟠 High"
            case .medium:   return "🟡 Medium"
            case .low:      return "🟢 Low"
            }
        }

        var shortName: String {
            switch self {
            case .critical: return "critical"
            case .high:     return "high"
            case .medium:   return "medium"
            case .low:      return "low"
            }
        }
    }

    /// A record of a feed's priority assignment with metadata.
    struct PriorityEntry: Codable {
        let feedURL: String
        var priority: Priority
        var assignedDate: Date
        var reason: String?

        init(feedURL: String, priority: Priority, reason: String? = nil) {
            self.feedURL = feedURL
            self.priority = priority
            self.assignedDate = Date()
            self.reason = reason
        }
    }

    /// Summary statistics for priority distribution.
    struct PriorityStats {
        let critical: Int
        let high: Int
        let medium: Int
        let low: Int
        let unranked: Int
        let total: Int

        var summary: String {
            return "Critical: \(critical), High: \(high), Medium: \(medium), Low: \(low), Unranked: \(unranked)"
        }
    }

    // MARK: - Storage

    private static let storageKey = "FeedPriorityRanker_entries"
    private var entries: [String: PriorityEntry] = [:]

    /// Default priority for feeds that haven't been explicitly ranked.
    var defaultPriority: Priority = .medium

    // MARK: - Initialization

    init() {
        load()
    }

    // MARK: - Priority Management

    /// Set the priority for a specific feed URL.
    ///
    /// - Parameters:
    ///   - priority: The priority level to assign.
    ///   - feedURL: The feed's URL (used as identifier).
    ///   - reason: Optional note explaining why this priority was chosen.
    func setPriority(_ priority: Priority, for feedURL: String, reason: String? = nil) {
        let normalized = feedURL.lowercased()
        entries[normalized] = PriorityEntry(feedURL: normalized, priority: priority, reason: reason)
        save()
    }

    /// Get the priority for a feed URL. Returns `defaultPriority` if not set.
    func priority(for feedURL: String) -> Priority {
        let normalized = feedURL.lowercased()
        return entries[normalized]?.priority ?? defaultPriority
    }

    /// Get the full priority entry for a feed URL, if one exists.
    func entry(for feedURL: String) -> PriorityEntry? {
        return entries[feedURL.lowercased()]
    }

    /// Remove the priority assignment for a feed (reverts to default).
    func removePriority(for feedURL: String) {
        entries.removeValue(forKey: feedURL.lowercased())
        save()
    }

    /// Set priority for all feeds matching a category name.
    ///
    /// - Parameters:
    ///   - category: The category to match (requires Feed objects).
    ///   - priority: The priority level to assign.
    ///   - feeds: Array of Feed objects to search through.
    func setPriorityForCategory(_ category: String, priority: Priority, feeds: [Feed]) {
        for feed in feeds where feed.category?.lowercased() == category.lowercased() {
            setPriority(priority, for: feed.url, reason: "Category: \(category)")
        }
    }

    /// Get all feeds with a specific priority level.
    func feeds(withPriority priority: Priority) -> [PriorityEntry] {
        return entries.values.filter { $0.priority == priority }
    }

    /// Get all priority entries sorted by priority (critical first).
    func allEntries() -> [PriorityEntry] {
        return entries.values.sorted { $0.priority < $1.priority }
    }

    // MARK: - Article Ranking

    /// Sort stories by feed priority (critical first) then by title as tiebreaker.
    ///
    /// Stories from higher-priority feeds appear first. Stories from the same
    /// priority level are kept in their original relative order.
    ///
    /// - Parameters:
    ///   - stories: The articles to sort.
    ///   - feedURLForStory: Closure that extracts the feed URL from a story.
    /// - Returns: Stories sorted by priority.
    func rankArticles(_ stories: [Story], feedURLForStory: (Story) -> String?) -> [Story] {
        return stories.sorted { a, b in
            let pA = priority(for: feedURLForStory(a) ?? "")
            let pB = priority(for: feedURLForStory(b) ?? "")
            if pA != pB {
                return pA < pB  // Lower raw value = higher priority
            }
            return false  // Stable sort: preserve original order for same priority
        }
    }

    /// Filter stories to only include those from feeds at or above a priority threshold.
    ///
    /// - Parameters:
    ///   - stories: The articles to filter.
    ///   - minPriority: Minimum priority level (e.g., .high includes critical and high).
    ///   - feedURLForStory: Closure that extracts the feed URL from a story.
    /// - Returns: Filtered stories.
    func filterArticles(_ stories: [Story], minPriority: Priority, feedURLForStory: (Story) -> String?) -> [Story] {
        return stories.filter { story in
            let p = priority(for: feedURLForStory(story) ?? "")
            return p <= minPriority  // Lower raw value = higher priority
        }
    }

    /// Group stories by their feed's priority level.
    func groupArticlesByPriority(_ stories: [Story], feedURLForStory: (Story) -> String?) -> [Priority: [Story]] {
        var groups: [Priority: [Story]] = [:]
        for p in Priority.allCases {
            groups[p] = []
        }
        for story in stories {
            let p = priority(for: feedURLForStory(story) ?? "")
            groups[p, default: []].append(story)
        }
        return groups
    }

    // MARK: - Statistics

    /// Get distribution of feeds across priority levels.
    ///
    /// - Parameter totalFeeds: Total number of feeds (to calculate unranked count).
    func priorityDistribution(totalFeeds: Int = 0) -> PriorityStats {
        var counts: [Priority: Int] = [:]
        for p in Priority.allCases { counts[p] = 0 }
        for entry in entries.values {
            counts[entry.priority, default: 0] += 1
        }
        let ranked = entries.count
        return PriorityStats(
            critical: counts[.critical] ?? 0,
            high: counts[.high] ?? 0,
            medium: counts[.medium] ?? 0,
            low: counts[.low] ?? 0,
            unranked: max(0, totalFeeds - ranked),
            total: totalFeeds
        )
    }

    /// Get a quick text summary of how feeds are prioritized.
    func summaryReport(totalFeeds: Int = 0) -> String {
        let stats = priorityDistribution(totalFeeds: totalFeeds)
        var lines: [String] = ["📊 Feed Priority Report"]
        lines.append("─────────────────────")
        for p in Priority.allCases {
            let count: Int
            switch p {
            case .critical: count = stats.critical
            case .high: count = stats.high
            case .medium: count = stats.medium
            case .low: count = stats.low
            }
            lines.append("\(p.displayName): \(count) feed\(count == 1 ? "" : "s")")
        }
        if stats.unranked > 0 {
            lines.append("⚪ Unranked: \(stats.unranked) feed\(stats.unranked == 1 ? "" : "s")")
        }
        lines.append("─────────────────────")
        lines.append("Total: \(stats.total) feeds")
        return lines.joined(separator: "\n")
    }

    // MARK: - Bulk Operations

    /// Import priorities from a dictionary of [feedURL: priorityString].
    /// Valid priority strings: "critical", "high", "medium", "low".
    func importPriorities(_ mapping: [String: String]) -> Int {
        var imported = 0
        for (url, priorityStr) in mapping {
            if let priority = Priority.allCases.first(where: { $0.shortName == priorityStr.lowercased() }) {
                setPriority(priority, for: url, reason: "Imported")
                imported += 1
            }
        }
        return imported
    }

    /// Export all priorities as a dictionary of [feedURL: priorityString].
    func exportPriorities() -> [String: String] {
        var result: [String: String] = [:]
        for (url, entry) in entries {
            result[url] = entry.priority.shortName
        }
        return result
    }

    /// Reset all priority assignments.
    func resetAll() {
        entries.removeAll()
        save()
    }

    // MARK: - Persistence

    private func save() {
        if let data = try? JSONEncoder().encode(entries) {
            UserDefaults.standard.set(data, forKey: FeedPriorityRanker.storageKey)
        }
    }

    private func load() {
        guard let data = UserDefaults.standard.data(forKey: FeedPriorityRanker.storageKey),
              let decoded = try? JSONDecoder().decode([String: PriorityEntry].self, from: data) else {
            return
        }
        entries = decoded
    }
}
