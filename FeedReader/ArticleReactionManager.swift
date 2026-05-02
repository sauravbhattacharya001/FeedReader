//
//  ArticleReactionManager.swift
//  FeedReader
//
//  Quick-react emoji reactions on articles. Users can react to any article
//  with predefined emoji (👍 ❤️ 😂 😮 😡 🔖), view reaction counts,
//  discover trending articles by reaction volume, and filter articles
//  by reaction type.
//
//  Features:
//  - Toggle reactions on/off per article (tap again to remove)
//  - Reaction summary per article (counts by type)
//  - Trending articles ranked by total reactions
//  - Filter: "articles I loved", "articles that surprised me", etc.
//  - Reaction history with timestamps
//  - Stats: most-reacted feed, favorite reaction, reactions over time
//  - Export reaction data as JSON or CSV
//
//  Persistence: JSON file in Documents directory.
//

import Foundation

// MARK: - Notifications

extension Notification.Name {
    /// Posted when a reaction is added or removed.
    static let articleReactionDidChange = Notification.Name("ArticleReactionDidChangeNotification")
}

// MARK: - ReactionType

/// Available emoji reactions for articles.
enum ReactionType: String, Codable, CaseIterable {
    case thumbsUp = "👍"
    case heart = "❤️"
    case laugh = "😂"
    case surprised = "😮"
    case angry = "😡"
    case bookmark = "🔖"

    /// Human-readable label for the reaction.
    var label: String {
        switch self {
        case .thumbsUp: return "Like"
        case .heart: return "Love"
        case .laugh: return "Funny"
        case .surprised: return "Wow"
        case .angry: return "Angry"
        case .bookmark: return "Save"
        }
    }
}

// MARK: - ReactionEntry

/// A single reaction event tied to an article.
struct ReactionEntry: Codable {
    /// Unique identifier for this reaction entry.
    let id: String
    /// The article URL (used as article identifier).
    let articleURL: String
    /// The article title at the time of reaction.
    let articleTitle: String
    /// The feed name the article belongs to (if known).
    let feedName: String?
    /// The reaction type.
    let reaction: ReactionType
    /// When the reaction was added.
    let timestamp: Date

    init(articleURL: String, articleTitle: String, feedName: String?, reaction: ReactionType) {
        self.id = UUID().uuidString
        self.articleURL = articleURL
        self.articleTitle = articleTitle
        self.feedName = feedName
        self.reaction = reaction
        self.timestamp = Date()
    }
}

// MARK: - ReactionStore

/// Codable container for persistence.
private struct ReactionStore: Codable {
    var entries: [ReactionEntry]
    var version: Int = 1
}

// MARK: - ArticleReactionManager

/// Manages emoji reactions on articles with persistence, querying, and export.
class ArticleReactionManager {

    // MARK: - Singleton

    static let shared = ArticleReactionManager()

    // MARK: - Properties

    private var entries: [ReactionEntry] = []
    private let fileURL: URL
    private let queue = DispatchQueue(label: "com.feedreader.reactions", attributes: .concurrent)

    // MARK: - Init

    init(directory: URL? = nil) {
        let dir = directory ?? FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        self.fileURL = dir.appendingPathComponent("article_reactions.json")
        load()
    }

    // MARK: - Persistence

    private func load() {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return }
        do {
            let data = try Data(contentsOf: fileURL)
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            let store = try decoder.decode(ReactionStore.self, from: data)
            entries = store.entries
        } catch {
            entries = []
        }
    }

    private func save() {
        do {
            let store = ReactionStore(entries: entries)
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(store)
            try data.write(to: fileURL, options: .atomic)
        } catch {
            // Silent failure — non-critical data
        }
    }

    // MARK: - Toggle Reaction

    /// Toggle a reaction on an article. Returns `true` if reaction was added, `false` if removed.
    @discardableResult
    func toggleReaction(_ reaction: ReactionType, articleURL: String, articleTitle: String, feedName: String? = nil) -> Bool {
        return queue.sync(flags: .barrier) {
            // Check if this exact reaction already exists
            if let index = entries.firstIndex(where: { $0.articleURL == articleURL && $0.reaction == reaction }) {
                entries.remove(at: index)
                save()
                NotificationCenter.default.post(name: .articleReactionDidChange, object: nil)
                return false
            } else {
                let entry = ReactionEntry(articleURL: articleURL, articleTitle: articleTitle, feedName: feedName, reaction: reaction)
                entries.append(entry)
                save()
                NotificationCenter.default.post(name: .articleReactionDidChange, object: nil)
                return true
            }
        }
    }

    // MARK: - Query: Single Article

    /// Get all reactions for a specific article URL.
    func reactions(for articleURL: String) -> [ReactionEntry] {
        return queue.sync { entries.filter { $0.articleURL == articleURL } }
    }

    /// Get reaction counts by type for a specific article.
    func reactionCounts(for articleURL: String) -> [ReactionType: Int] {
        return queue.sync {
            var counts: [ReactionType: Int] = [:]
            for entry in entries where entry.articleURL == articleURL {
                counts[entry.reaction, default: 0] += 1
            }
            return counts
        }
    }

    /// Check if a specific reaction exists for an article.
    func hasReaction(_ reaction: ReactionType, for articleURL: String) -> Bool {
        return queue.sync { entries.contains { $0.articleURL == articleURL && $0.reaction == reaction } }
    }

    /// Total reaction count for an article.
    func totalReactions(for articleURL: String) -> Int {
        return queue.sync { entries.filter { $0.articleURL == articleURL }.count }
    }

    // MARK: - Query: By Reaction Type

    /// Get all articles with a specific reaction type, most recent first.
    func articles(with reaction: ReactionType) -> [ReactionEntry] {
        return queue.sync {
            entries
                .filter { $0.reaction == reaction }
                .sorted { $0.timestamp > $1.timestamp }
        }
    }

    // MARK: - Trending

    /// Article URLs ranked by total reaction count (descending).
    /// Returns array of (articleURL, articleTitle, feedName, totalCount).
    func trending(limit: Int = 20) -> [(url: String, title: String, feed: String?, count: Int)] {
        return queue.sync {
            var urlCounts: [String: Int] = [:]
            var urlMeta: [String: (title: String, feed: String?)] = [:]

            for entry in entries {
                urlCounts[entry.articleURL, default: 0] += 1
                // Keep most recent title/feed
                urlMeta[entry.articleURL] = (entry.articleTitle, entry.feedName)
            }

            return urlCounts
                .sorted { $0.value > $1.value }
                .prefix(limit)
                .map { (url: $0.key, title: urlMeta[$0.key]?.title ?? "", feed: urlMeta[$0.key]?.feed, count: $0.value) }
        }
    }

    // MARK: - Stats

    /// Overall statistics about reactions.
    func stats() -> ReactionStats {
        return queue.sync {
            let totalCount = entries.count

            // Count by type
            var byType: [ReactionType: Int] = [:]
            for entry in entries {
                byType[entry.reaction, default: 0] += 1
            }

            // Favorite reaction (most used)
            let favoriteReaction = byType.max(by: { $0.value < $1.value })?.key

            // Unique articles reacted to
            let uniqueArticles = Set(entries.map { $0.articleURL }).count

            // Most reacted feed
            var feedCounts: [String: Int] = [:]
            for entry in entries {
                if let feed = entry.feedName {
                    feedCounts[feed, default: 0] += 1
                }
            }
            let topFeed = feedCounts.max(by: { $0.value < $1.value })?.key

            // Reactions per day (last 30 days)
            let calendar = Calendar.current
            let thirtyDaysAgo = calendar.date(byAdding: .day, value: -30, to: Date()) ?? Date()
            let recentEntries = entries.filter { $0.timestamp >= thirtyDaysAgo }
            let daysWithReactions = Set(recentEntries.map { calendar.startOfDay(for: $0.timestamp) }).count
            let avgPerDay = daysWithReactions > 0 ? Double(recentEntries.count) / Double(daysWithReactions) : 0

            return ReactionStats(
                totalReactions: totalCount,
                uniqueArticlesReacted: uniqueArticles,
                countsByType: byType,
                favoriteReaction: favoriteReaction,
                mostReactedFeed: topFeed,
                averageReactionsPerActiveDay: avgPerDay
            )
        }
    }

    // MARK: - History

    /// Recent reaction history, newest first.
    func recentHistory(limit: Int = 50) -> [ReactionEntry] {
        return queue.sync { Array(entries.sorted { $0.timestamp > $1.timestamp }.prefix(limit)) }
    }

    /// Reactions within a date range.
    func reactions(from startDate: Date, to endDate: Date) -> [ReactionEntry] {
        return queue.sync { entries.filter { $0.timestamp >= startDate && $0.timestamp <= endDate } }
    }

    // MARK: - Bulk Operations

    /// Remove all reactions for a specific article.
    func removeAllReactions(for articleURL: String) {
        queue.sync(flags: .barrier) {
            entries.removeAll { $0.articleURL == articleURL }
            save()
        }
        NotificationCenter.default.post(name: .articleReactionDidChange, object: nil)
    }

    /// Clear all reaction data.
    func clearAll() {
        queue.sync(flags: .barrier) {
            entries.removeAll()
            save()
        }
        NotificationCenter.default.post(name: .articleReactionDidChange, object: nil)
    }

    /// Total number of reaction entries.
    var count: Int {
        return queue.sync { entries.count }
    }

    // MARK: - Export

    /// Export all reactions as JSON data.
    func exportJSON() -> Data? {
        return queue.sync {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            return try? encoder.encode(ReactionStore(entries: entries))
        }
    }

    /// Export all reactions as CSV string.
    func exportCSV() -> String {
        return queue.sync {
            var csv = "id,article_url,article_title,feed_name,reaction,reaction_label,timestamp\n"
            let formatter = ISO8601DateFormatter()
            for entry in entries.sorted(by: { $0.timestamp > $1.timestamp }) {
                let title = entry.articleTitle.replacingOccurrences(of: "\"", with: "\"\"")
                let feed = (entry.feedName ?? "").replacingOccurrences(of: "\"", with: "\"\"")
                csv += "\"\(entry.id)\",\"\(entry.articleURL)\",\"\(title)\",\"\(feed)\",\"\(entry.reaction.rawValue)\",\"\(entry.reaction.label)\",\"\(formatter.string(from: entry.timestamp))\"\n"
            }
            return csv
        }
    }
}

// MARK: - ReactionStats

/// Summary statistics for article reactions.
struct ReactionStats {
    let totalReactions: Int
    let uniqueArticlesReacted: Int
    let countsByType: [ReactionType: Int]
    let favoriteReaction: ReactionType?
    let mostReactedFeed: String?
    let averageReactionsPerActiveDay: Double

    /// Formatted summary string.
    var summary: String {
        var lines: [String] = []
        lines.append("📊 Reaction Stats")
        lines.append("Total reactions: \(totalReactions)")
        lines.append("Articles reacted to: \(uniqueArticlesReacted)")
        if let fav = favoriteReaction {
            lines.append("Favorite reaction: \(fav.rawValue) \(fav.label)")
        }
        if let feed = mostReactedFeed {
            lines.append("Most reacted feed: \(feed)")
        }
        lines.append(String(format: "Avg reactions/active day: %.1f", averageReactionsPerActiveDay))
        lines.append("")
        lines.append("By type:")
        for type in ReactionType.allCases {
            let count = countsByType[type] ?? 0
            lines.append("  \(type.rawValue) \(type.label): \(count)")
        }
        return lines.joined(separator: "\n")
    }
}
