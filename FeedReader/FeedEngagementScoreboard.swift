//
//  FeedEngagementScoreboard.swift
//  FeedReader
//
//  Ranks all subscribed feeds by a weighted composite of user
//  engagement metrics: read rate, bookmark rate, share rate, and
//  average time spent reading. Helps users discover which feeds
//  they actually engage with vs. which ones just add noise.
//
//  Fully offline — no network, no dependencies beyond Foundation.
//

import Foundation

// MARK: - Notification

extension Notification.Name {
    static let engagementScoreboardDidUpdate = Notification.Name("FeedEngagementScoreboardDidUpdateNotification")
}

// MARK: - EngagementTier

/// Visual tier for quick glancing at engagement level.
enum EngagementTier: String, CaseIterable, Comparable {
    case star     = "⭐ Star"
    case high     = "🔥 High"
    case moderate = "👍 Moderate"
    case low      = "😴 Low"
    case dormant  = "💤 Dormant"

    private var sortOrder: Int {
        switch self {
        case .star:     return 4
        case .high:     return 3
        case .moderate: return 2
        case .low:      return 1
        case .dormant:  return 0
        }
    }

    static func < (lhs: EngagementTier, rhs: EngagementTier) -> Bool {
        lhs.sortOrder < rhs.sortOrder
    }

    static func from(score: Double) -> EngagementTier {
        switch score {
        case 0.80...:   return .star
        case 0.60..<0.80: return .high
        case 0.35..<0.60: return .moderate
        case 0.10..<0.35: return .low
        default:          return .dormant
        }
    }
}

// MARK: - FeedEngagementRecord

/// Tracks raw engagement events for a single feed.
struct FeedEngagementRecord: Codable, Equatable {
    let feedURL: String
    var feedTitle: String
    var totalArticles: Int
    var readArticles: Int
    var bookmarkedArticles: Int
    var sharedArticles: Int
    var totalReadingTimeSeconds: TimeInterval
    var lastEngagedDate: Date?
    var firstTrackedDate: Date

    var readRate: Double {
        guard totalArticles > 0 else { return 0 }
        return Double(readArticles) / Double(totalArticles)
    }

    var bookmarkRate: Double {
        guard totalArticles > 0 else { return 0 }
        return Double(bookmarkedArticles) / Double(totalArticles)
    }

    var shareRate: Double {
        guard totalArticles > 0 else { return 0 }
        return Double(sharedArticles) / Double(totalArticles)
    }

    var averageReadingTime: TimeInterval {
        guard readArticles > 0 else { return 0 }
        return totalReadingTimeSeconds / Double(readArticles)
    }

    var daysSinceLastEngagement: Int? {
        guard let last = lastEngagedDate else { return nil }
        return Calendar.current.dateComponents([.day], from: last, to: Date()).day
    }
}

// MARK: - FeedEngagementScore

/// Computed composite score for a feed.
struct FeedEngagementScore: Codable, Equatable {
    let feedURL: String
    let feedTitle: String
    let compositeScore: Double
    let readRate: Double
    let bookmarkRate: Double
    let shareRate: Double
    let averageReadingTimeSec: Double
    let tier: String
    let rank: Int
    let totalArticles: Int
    let engagedArticles: Int
    let recencyBonus: Double
    let computedAt: Date
}

// MARK: - EngagementWeights

/// Configurable weights for the composite score calculation.
struct EngagementWeights: Codable, Equatable {
    var readWeight: Double
    var bookmarkWeight: Double
    var shareWeight: Double
    var readingTimeWeight: Double
    var recencyWeight: Double

    static let `default` = EngagementWeights(
        readWeight: 0.35,
        bookmarkWeight: 0.20,
        shareWeight: 0.15,
        readingTimeWeight: 0.15,
        recencyWeight: 0.15
    )

    /// Normalizes weights so they sum to 1.0.
    var normalized: EngagementWeights {
        let total = readWeight + bookmarkWeight + shareWeight + readingTimeWeight + recencyWeight
        guard total > 0 else { return .default }
        return EngagementWeights(
            readWeight: readWeight / total,
            bookmarkWeight: bookmarkWeight / total,
            shareWeight: shareWeight / total,
            readingTimeWeight: readingTimeWeight / total,
            recencyWeight: recencyWeight / total
        )
    }
}

// MARK: - FeedEngagementScoreboard

/// Computes and persists per-feed engagement rankings.
///
/// Usage:
/// ```swift
/// let board = FeedEngagementScoreboard()
///
/// // Record events
/// board.recordArticleReceived(feedURL: url, feedTitle: "TechCrunch")
/// board.recordArticleRead(feedURL: url, readingTimeSec: 120)
/// board.recordArticleBookmarked(feedURL: url)
/// board.recordArticleShared(feedURL: url)
///
/// // Get rankings
/// let scores = board.rankings()          // sorted by composite score
/// let top = board.topFeeds(limit: 5)     // top 5
/// let bottom = board.bottomFeeds(limit: 3) // least engaged
///
/// // Insights
/// let summary = board.summary()
/// let suggestions = board.suggestions()
/// ```
class FeedEngagementScoreboard {

    // MARK: - Storage

    private let storageKey = "FeedEngagementScoreboard_Records"
    private let weightsKey = "FeedEngagementScoreboard_Weights"
    private var records: [String: FeedEngagementRecord] = [:]
    private var weights: EngagementWeights

    // MARK: - Init

    init() {
        weights = .default
        loadRecords()
        loadWeights()
    }

    // MARK: - Recording Events

    /// Call when a new article arrives for a feed.
    func recordArticleReceived(feedURL: String, feedTitle: String, count: Int = 1) {
        var record = getOrCreateRecord(feedURL: feedURL, feedTitle: feedTitle)
        record.totalArticles += count
        records[feedURL] = record
        saveRecords()
    }

    /// Call when the user reads an article.
    func recordArticleRead(feedURL: String, readingTimeSec: TimeInterval = 0) {
        guard var record = records[feedURL] else { return }
        record.readArticles += 1
        record.totalReadingTimeSeconds += readingTimeSec
        record.lastEngagedDate = Date()
        records[feedURL] = record
        saveRecords()
        postNotification()
    }

    /// Call when the user bookmarks an article.
    func recordArticleBookmarked(feedURL: String) {
        guard var record = records[feedURL] else { return }
        record.bookmarkedArticles += 1
        record.lastEngagedDate = Date()
        records[feedURL] = record
        saveRecords()
        postNotification()
    }

    /// Call when the user shares an article.
    func recordArticleShared(feedURL: String) {
        guard var record = records[feedURL] else { return }
        record.sharedArticles += 1
        record.lastEngagedDate = Date()
        records[feedURL] = record
        saveRecords()
        postNotification()
    }

    // MARK: - Weights

    /// Update scoring weights (auto-normalizes).
    func updateWeights(_ newWeights: EngagementWeights) {
        weights = newWeights.normalized
        saveWeights()
        postNotification()
    }

    func currentWeights() -> EngagementWeights {
        return weights
    }

    // MARK: - Scoring

    /// Compute composite score for a single feed record.
    private func computeScore(for record: FeedEngagementRecord) -> Double {
        let w = weights.normalized

        // Read rate component (0-1)
        let readComponent = min(record.readRate, 1.0)

        // Bookmark rate component — cap at 0.5 (50% bookmark rate = perfect)
        let bookmarkComponent = min(record.bookmarkRate / 0.5, 1.0)

        // Share rate component — cap at 0.3 (30% share rate = perfect)
        let shareComponent = min(record.shareRate / 0.3, 1.0)

        // Reading time component — normalize against 3-minute ideal
        let idealReadingTime: TimeInterval = 180
        let timeComponent: Double
        if record.averageReadingTime <= 0 {
            timeComponent = 0
        } else {
            timeComponent = min(record.averageReadingTime / idealReadingTime, 1.0)
        }

        // Recency bonus — decays over 30 days
        let recencyComponent: Double
        if let days = record.daysSinceLastEngagement {
            recencyComponent = max(0, 1.0 - Double(days) / 30.0)
        } else {
            recencyComponent = 0
        }

        return (readComponent * w.readWeight)
             + (bookmarkComponent * w.bookmarkWeight)
             + (shareComponent * w.shareWeight)
             + (timeComponent * w.readingTimeWeight)
             + (recencyComponent * w.recencyWeight)
    }

    /// Returns all feeds ranked by engagement score (descending).
    func rankings() -> [FeedEngagementScore] {
        let now = Date()
        let scored = records.values.map { record -> (FeedEngagementRecord, Double, Double) in
            let recency: Double
            if let days = record.daysSinceLastEngagement {
                recency = max(0, 1.0 - Double(days) / 30.0)
            } else {
                recency = 0
            }
            return (record, computeScore(for: record), recency)
        }
        .sorted { $0.1 > $1.1 }

        return scored.enumerated().map { index, item in
            let (record, score, recency) = item
            return FeedEngagementScore(
                feedURL: record.feedURL,
                feedTitle: record.feedTitle,
                compositeScore: (score * 100).rounded() / 100,
                readRate: (record.readRate * 100).rounded() / 100,
                bookmarkRate: (record.bookmarkRate * 100).rounded() / 100,
                shareRate: (record.shareRate * 100).rounded() / 100,
                averageReadingTimeSec: record.averageReadingTime.rounded(),
                tier: EngagementTier.from(score: score).rawValue,
                rank: index + 1,
                totalArticles: record.totalArticles,
                engagedArticles: record.readArticles,
                recencyBonus: (recency * 100).rounded() / 100,
                computedAt: now
            )
        }
    }

    /// Top N most-engaged feeds.
    func topFeeds(limit: Int = 5) -> [FeedEngagementScore] {
        Array(rankings().prefix(limit))
    }

    /// Bottom N least-engaged feeds (candidates for unsubscribe).
    func bottomFeeds(limit: Int = 5) -> [FeedEngagementScore] {
        Array(rankings().suffix(limit))
    }

    /// Feeds in a given tier.
    func feeds(in tier: EngagementTier) -> [FeedEngagementScore] {
        rankings().filter { $0.tier == tier.rawValue }
    }

    // MARK: - Insights

    /// High-level summary of engagement across all feeds.
    func summary() -> [String: Any] {
        let all = rankings()
        guard !all.isEmpty else {
            return ["message": "No feeds tracked yet."]
        }

        let avgScore = all.map(\.compositeScore).reduce(0, +) / Double(all.count)
        let tierCounts = Dictionary(grouping: all, by: \.tier).mapValues(\.count)
        let totalRead = records.values.map(\.readArticles).reduce(0, +)
        let totalArticles = records.values.map(\.totalArticles).reduce(0, +)
        let overallReadRate = totalArticles > 0 ? Double(totalRead) / Double(totalArticles) : 0

        return [
            "totalFeeds": all.count,
            "averageScore": (avgScore * 100).rounded() / 100,
            "overallReadRate": "\(Int(overallReadRate * 100))%",
            "tierDistribution": tierCounts,
            "topFeed": all.first?.feedTitle ?? "N/A",
            "leastEngaged": all.last?.feedTitle ?? "N/A"
        ]
    }

    /// Actionable suggestions based on engagement patterns.
    func suggestions() -> [String] {
        var tips: [String] = []
        let all = rankings()

        let dormant = all.filter { $0.tier == EngagementTier.dormant.rawValue }
        if dormant.count > 0 {
            let names = dormant.prefix(3).map(\.feedTitle).joined(separator: ", ")
            tips.append("Consider unsubscribing from dormant feeds: \(names)")
        }

        let lowRead = all.filter { $0.readRate < 0.10 && $0.totalArticles >= 10 }
        if lowRead.count > 0 {
            tips.append("\(lowRead.count) feed(s) have <10% read rate — you may be missing content or it's not relevant.")
        }

        let stars = all.filter { $0.tier == EngagementTier.star.rawValue }
        if stars.isEmpty && all.count >= 5 {
            tips.append("No star-tier feeds! Try spending more time with feeds you enjoy.")
        }

        let highBookmark = all.filter { $0.bookmarkRate > 0.3 }
        if highBookmark.count > 0 {
            let names = highBookmark.prefix(2).map(\.feedTitle).joined(separator: ", ")
            tips.append("You bookmark heavily from \(names) — these are your reference sources!")
        }

        if tips.isEmpty {
            tips.append("Your engagement looks healthy across your feeds. Keep reading! 📚")
        }

        return tips
    }

    // MARK: - Data Management

    /// Remove tracking data for a feed.
    func removeRecord(feedURL: String) {
        records.removeValue(forKey: feedURL)
        saveRecords()
        postNotification()
    }

    /// Reset all engagement data.
    func resetAll() {
        records.removeAll()
        saveRecords()
        postNotification()
    }

    /// Number of tracked feeds.
    var trackedFeedCount: Int {
        records.count
    }

    /// Export all records as JSON data.
    func exportJSON() -> Data? {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return try? encoder.encode(Array(records.values))
    }

    // MARK: - Private Helpers

    private func getOrCreateRecord(feedURL: String, feedTitle: String) -> FeedEngagementRecord {
        if let existing = records[feedURL] {
            return existing
        }
        return FeedEngagementRecord(
            feedURL: feedURL,
            feedTitle: feedTitle,
            totalArticles: 0,
            readArticles: 0,
            bookmarkedArticles: 0,
            sharedArticles: 0,
            totalReadingTimeSeconds: 0,
            lastEngagedDate: nil,
            firstTrackedDate: Date()
        )
    }

    private func postNotification() {
        NotificationCenter.default.post(name: .engagementScoreboardDidUpdate, object: self)
    }

    // MARK: - Persistence

    private func saveRecords() {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        if let data = try? encoder.encode(records) {
            UserDefaults.standard.set(data, forKey: storageKey)
        }
    }

    private func loadRecords() {
        guard let data = UserDefaults.standard.data(forKey: storageKey) else { return }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        if let loaded = try? decoder.decode([String: FeedEngagementRecord].self, from: data) {
            records = loaded
        }
    }

    private func saveWeights() {
        if let data = try? JSONEncoder().encode(weights) {
            UserDefaults.standard.set(data, forKey: weightsKey)
        }
    }

    private func loadWeights() {
        guard let data = UserDefaults.standard.data(forKey: weightsKey) else { return }
        if let loaded = try? JSONDecoder().decode(EngagementWeights.self, from: data) {
            weights = loaded
        }
    }
}
