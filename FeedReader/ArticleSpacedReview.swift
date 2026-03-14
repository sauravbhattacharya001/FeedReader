//
//  ArticleSpacedReview.swift
//  FeedReader
//
//  Spaced repetition review system for article retention. Uses a
//  simplified SM-2 algorithm to schedule articles for review based
//  on how well the user remembers them. Articles start with a 1-day
//  interval that grows with each successful recall.
//
//  Key features:
//  - Add any read article to the review queue
//  - SM-2-inspired scheduling (intervals: 1d → 3d → 7d → 14d → 30d → 60d → 90d)
//  - Self-assessment after review (Easy/Good/Hard/Forgot)
//  - Review statistics (retention rate, streak, mastered count)
//  - Daily review queue with due items
//  - Priority review for flagged articles
//  - Export review history as JSON
//  - Search review queue by title/feed
//
//  Persistence: JSON file in Documents directory.
//  Fully offline — no network, no dependencies beyond Foundation.
//

import Foundation

// MARK: - Notifications

extension Notification.Name {
    /// Posted when review items are added, reviewed, or removed.
    static let spacedReviewDidChange = Notification.Name("SpacedReviewDidChangeNotification")
    /// Posted when a review session is completed.
    static let spacedReviewSessionComplete = Notification.Name("SpacedReviewSessionCompleteNotification")
}

// MARK: - Review Quality

/// Self-assessment after reviewing an article's key points.
enum ReviewQuality: Int, Codable, CaseIterable, CustomStringConvertible {
    case forgot = 0     // Couldn't remember anything
    case hard = 1       // Remembered with significant effort
    case good = 2       // Remembered with some effort
    case easy = 3       // Remembered effortlessly

    var description: String {
        switch self {
        case .forgot: return "Forgot"
        case .hard:   return "Hard"
        case .good:   return "Good"
        case .easy:   return "Easy"
        }
    }

    /// How this quality affects the interval multiplier.
    var intervalMultiplier: Double {
        switch self {
        case .forgot: return 0.0   // Reset to beginning
        case .hard:   return 0.8   // Slightly shorter interval
        case .good:   return 1.0   // Normal progression
        case .easy:   return 1.5   // Skip ahead
        }
    }
}

// MARK: - Review Item

/// A single article in the spaced repetition queue.
struct ReviewItem: Codable, Equatable {
    /// Article link (unique identifier).
    let articleLink: String
    /// Article title for display.
    let articleTitle: String
    /// Feed name for context.
    let feedName: String
    /// Brief summary/key points the user wants to remember.
    var keyPoints: String
    /// When this item was added to the review queue.
    let addedAt: Date
    /// When the next review is due.
    var nextReviewDate: Date
    /// Current interval level (index into the interval schedule).
    var intervalLevel: Int
    /// Total number of times reviewed.
    var reviewCount: Int
    /// Number of times recalled successfully (quality >= .good).
    var successCount: Int
    /// Whether this item is flagged for priority review.
    var isFlagged: Bool
    /// Whether this item is considered mastered (reached max interval).
    var isMastered: Bool
    /// History of review outcomes.
    var reviewHistory: [ReviewRecord]

    static func == (lhs: ReviewItem, rhs: ReviewItem) -> Bool {
        return lhs.articleLink == rhs.articleLink
    }
}

// MARK: - Review Record

/// A single review event in the history.
struct ReviewRecord: Codable {
    let date: Date
    let quality: ReviewQuality
    let intervalLevel: Int
    let nextReviewDate: Date
}

// MARK: - Review Session Stats

/// Statistics for a review session.
struct ReviewSessionStats {
    let totalReviewed: Int
    let easyCount: Int
    let goodCount: Int
    let hardCount: Int
    let forgotCount: Int
    let retentionRate: Double    // (easy + good) / total
    let averageQuality: Double
    let date: Date
}

// MARK: - Overall Stats

/// Aggregate statistics across all review items.
struct ReviewStats {
    let totalItems: Int
    let masteredItems: Int
    let dueItems: Int
    let flaggedItems: Int
    let totalReviews: Int
    let overallRetentionRate: Double
    let currentStreak: Int      // consecutive days with reviews
    let longestStreak: Int
    let averageInterval: Double // average current interval in days
    let lastReviewDate: Date?
    let itemsByFeed: [(name: String, count: Int)]
}

// MARK: - ArticleSpacedReview

/// Manages a spaced repetition review queue for article retention.
class ArticleSpacedReview {

    // MARK: - Singleton

    static let shared = ArticleSpacedReview()

    // MARK: - Constants

    /// Review interval schedule in days. Each successful review advances
    /// to the next level. Based on SM-2 with simplified fixed intervals.
    static let intervalSchedule: [Double] = [
        1,      // Level 0: review tomorrow
        3,      // Level 1: 3 days
        7,      // Level 2: 1 week
        14,     // Level 3: 2 weeks
        30,     // Level 4: 1 month
        60,     // Level 5: 2 months
        90,     // Level 6: 3 months (mastered)
    ]

    /// Maximum interval level (index into intervalSchedule).
    static let maxLevel = intervalSchedule.count - 1

    // MARK: - Properties

    /// All review items, keyed by article link for O(1) lookup.
    private var items: [String: ReviewItem] = [:]

    /// Dates on which reviews were performed (for streak calculation).
    private var reviewDates: Set<String> = []  // "yyyy-MM-dd" format

    /// Longest consecutive review streak.
    private var longestStreak: Int = 0

    // MARK: - Persistence

    private static let fileName = "spaced_review_data.json"

    private static var fileURL: URL {
        let docs = FileManager.default.urls(for: .documentDirectory,
                                            in: .userDomainMask).first!
        return docs.appendingPathComponent(fileName)
    }

    // MARK: - Codable Storage

    private struct StorageModel: Codable {
        let items: [ReviewItem]
        let reviewDates: [String]
        let longestStreak: Int
    }

    // MARK: - Init

    init() {
        load()
    }

    // MARK: - CRUD Operations

    /// Add an article to the spaced review queue.
    ///
    /// - Parameters:
    ///   - link: Article URL (unique identifier).
    ///   - title: Article title.
    ///   - feedName: Source feed name.
    ///   - keyPoints: Brief notes about what to remember.
    ///   - flagged: Whether to flag for priority review.
    /// - Returns: The created ReviewItem, or nil if already in queue.
    @discardableResult
    func addItem(link: String, title: String, feedName: String,
                 keyPoints: String, flagged: Bool = false) -> ReviewItem? {
        guard !link.isEmpty else { return nil }
        guard items[link] == nil else { return nil }

        let now = Date()
        let firstIntervalDays = Int(Self.intervalSchedule[0])
        let nextReviewDate = Calendar.current.date(
            byAdding: .day, value: firstIntervalDays, to: now
        ) ?? now.addingTimeInterval(Double(firstIntervalDays) * 86400)
        let item = ReviewItem(
            articleLink: link,
            articleTitle: title,
            feedName: feedName,
            keyPoints: keyPoints,
            addedAt: now,
            nextReviewDate: nextReviewDate,
            intervalLevel: 0,
            reviewCount: 0,
            successCount: 0,
            isFlagged: flagged,
            isMastered: false,
            reviewHistory: []
        )

        items[link] = item
        save()
        NotificationCenter.default.post(name: .spacedReviewDidChange, object: nil)
        return item
    }

    /// Remove an article from the review queue.
    ///
    /// - Parameter link: Article link to remove.
    /// - Returns: True if the item existed and was removed.
    @discardableResult
    func removeItem(link: String) -> Bool {
        guard items.removeValue(forKey: link) != nil else { return false }
        save()
        NotificationCenter.default.post(name: .spacedReviewDidChange, object: nil)
        return true
    }

    /// Update key points for an existing review item.
    func updateKeyPoints(link: String, keyPoints: String) {
        guard var item = items[link] else { return }
        item.keyPoints = keyPoints
        items[link] = item
        save()
    }

    /// Toggle the flagged status of an item.
    func toggleFlag(link: String) {
        guard var item = items[link] else { return }
        item.isFlagged = !item.isFlagged
        items[link] = item
        save()
    }

    /// Get a specific review item by link.
    func getItem(link: String) -> ReviewItem? {
        return items[link]
    }

    /// Get all review items sorted by next review date (earliest first).
    func allItems() -> [ReviewItem] {
        return items.values.sorted { $0.nextReviewDate < $1.nextReviewDate }
    }

    // MARK: - Review Queue

    /// Get items that are due for review (nextReviewDate <= now).
    /// Flagged items appear first, then sorted by most overdue.
    func dueItems(at date: Date = Date()) -> [ReviewItem] {
        return items.values
            .filter { $0.nextReviewDate <= date }
            .sorted { a, b in
                if a.isFlagged != b.isFlagged { return a.isFlagged }
                return a.nextReviewDate < b.nextReviewDate
            }
    }

    /// Number of items due for review.
    func dueCount(at date: Date = Date()) -> Int {
        return items.values.filter { $0.nextReviewDate <= date }.count
    }

    /// Get items coming up for review in the next N days.
    func upcomingItems(withinDays days: Int, from date: Date = Date()) -> [ReviewItem] {
        let cutoff = Calendar.current.date(
            byAdding: .day, value: days, to: date
        ) ?? date.addingTimeInterval(Double(days) * 86400)
        return items.values
            .filter { $0.nextReviewDate > date && $0.nextReviewDate <= cutoff }
            .sorted { $0.nextReviewDate < $1.nextReviewDate }
    }

    // MARK: - Review Execution

    /// Record a review for an article.
    ///
    /// Updates the item's interval, next review date, and statistics
    /// based on the self-assessment quality.
    ///
    /// - Parameters:
    ///   - link: Article link being reviewed.
    ///   - quality: How well the user remembered the content.
    ///   - date: When the review occurred (defaults to now).
    /// - Returns: The updated ReviewItem, or nil if not found.
    @discardableResult
    func recordReview(link: String, quality: ReviewQuality,
                      at date: Date = Date()) -> ReviewItem? {
        guard var item = items[link] else { return nil }

        // Calculate new interval level
        var newLevel: Int
        switch quality {
        case .forgot:
            // Reset to level 0
            newLevel = 0
        case .hard:
            // Stay at current level (review again at same interval)
            newLevel = item.intervalLevel
        case .good:
            // Advance one level
            newLevel = min(item.intervalLevel + 1, Self.maxLevel)
        case .easy:
            // Skip ahead two levels
            newLevel = min(item.intervalLevel + 2, Self.maxLevel)
        }

        // Calculate next review date
        let intervalDays = Self.intervalSchedule[newLevel]
        let adjustedInterval = intervalDays * quality.intervalMultiplier
        let actualInterval = max(adjustedInterval, Self.intervalSchedule[0])  // minimum 1 day
        let actualDays = Int(actualInterval.rounded())
        let nextDate = Calendar.current.date(
            byAdding: .day, value: actualDays, to: date
        ) ?? date.addingTimeInterval(actualInterval * 86400)

        // Create review record
        let record = ReviewRecord(
            date: date,
            quality: quality,
            intervalLevel: newLevel,
            nextReviewDate: nextDate
        )

        // Update item
        item.intervalLevel = newLevel
        item.nextReviewDate = nextDate
        item.reviewCount += 1
        if quality == .good || quality == .easy {
            item.successCount += 1
        }
        item.isMastered = (newLevel >= Self.maxLevel)
        item.reviewHistory.append(record)

        items[link] = item

        // Track review date for streaks
        let dateStr = Self.dateString(from: date)
        reviewDates.insert(dateStr)
        longestStreak = max(longestStreak, currentStreak(at: date))

        save()
        NotificationCenter.default.post(name: .spacedReviewDidChange, object: nil)
        return item
    }

    /// Complete a review session and return session stats.
    func completeSession(reviews: [(link: String, quality: ReviewQuality)],
                         at date: Date = Date()) -> ReviewSessionStats {
        var easyCount = 0
        var goodCount = 0
        var hardCount = 0
        var forgotCount = 0

        for review in reviews {
            recordReview(link: review.link, quality: review.quality, at: date)
            switch review.quality {
            case .easy:   easyCount += 1
            case .good:   goodCount += 1
            case .hard:   hardCount += 1
            case .forgot: forgotCount += 1
            }
        }

        let total = reviews.count
        let retention = total > 0 ? Double(easyCount + goodCount) / Double(total) : 0
        let avgQuality = total > 0
            ? Double(reviews.map { $0.quality.rawValue }.reduce(0, +)) / Double(total)
            : 0

        let stats = ReviewSessionStats(
            totalReviewed: total,
            easyCount: easyCount,
            goodCount: goodCount,
            hardCount: hardCount,
            forgotCount: forgotCount,
            retentionRate: retention,
            averageQuality: avgQuality,
            date: date
        )

        NotificationCenter.default.post(
            name: .spacedReviewSessionComplete,
            object: nil,
            userInfo: ["stats": stats]
        )
        return stats
    }

    // MARK: - Statistics

    /// Get aggregate review statistics.
    func getStats(at date: Date = Date()) -> ReviewStats {
        let allItems = Array(items.values)
        let totalReviews = allItems.reduce(0) { $0 + $1.reviewCount }
        let totalSuccesses = allItems.reduce(0) { $0 + $1.successCount }
        let retention = totalReviews > 0
            ? Double(totalSuccesses) / Double(totalReviews)
            : 0

        // Average interval
        let avgInterval: Double
        if allItems.isEmpty {
            avgInterval = 0
        } else {
            let totalIntervalDays = allItems.reduce(0.0) { acc, item in
                acc + Self.intervalSchedule[item.intervalLevel]
            }
            avgInterval = totalIntervalDays / Double(allItems.count)
        }

        // Items by feed
        var feedCounts: [String: Int] = [:]
        for item in allItems {
            feedCounts[item.feedName, default: 0] += 1
        }
        let itemsByFeed = feedCounts.sorted { $0.value > $1.value }
            .map { (name: $0.key, count: $0.value) }

        // Last review date
        let lastReview = allItems
            .flatMap { $0.reviewHistory }
            .max { $0.date < $1.date }?.date

        return ReviewStats(
            totalItems: allItems.count,
            masteredItems: allItems.filter { $0.isMastered }.count,
            dueItems: dueCount(at: date),
            flaggedItems: allItems.filter { $0.isFlagged }.count,
            totalReviews: totalReviews,
            overallRetentionRate: retention,
            currentStreak: currentStreak(at: date),
            longestStreak: longestStreak,
            averageInterval: avgInterval,
            lastReviewDate: lastReview,
            itemsByFeed: itemsByFeed
        )
    }

    // MARK: - Search

    /// Search review items by title or feed name.
    func search(query: String) -> [ReviewItem] {
        let q = query.lowercased().trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return allItems() }
        return items.values
            .filter {
                $0.articleTitle.lowercased().contains(q) ||
                $0.feedName.lowercased().contains(q) ||
                $0.keyPoints.lowercased().contains(q)
            }
            .sorted { $0.nextReviewDate < $1.nextReviewDate }
    }

    // MARK: - Export

    /// Export all review data as JSON.
    func exportJSON() -> String {
        let allItems = self.allItems()
        let encoder = JSONCoding.iso8601PrettyEncoder
        guard let data = try? encoder.encode(allItems),
              let json = String(data: data, encoding: .utf8) else {
            return "[]"
        }
        return json
    }

    /// Export a text summary of review statistics.
    func exportSummary(at date: Date = Date()) -> String {
        let stats = getStats(at: date)
        var lines: [String] = []
        lines.append("=== Spaced Review Summary ===")
        lines.append("Total items: \(stats.totalItems)")
        lines.append("Mastered: \(stats.masteredItems)")
        lines.append("Due for review: \(stats.dueItems)")
        lines.append("Flagged: \(stats.flaggedItems)")
        lines.append("Total reviews: \(stats.totalReviews)")
        lines.append(String(format: "Retention rate: %.1f%%",
                            stats.overallRetentionRate * 100))
        lines.append("Current streak: \(stats.currentStreak) day(s)")
        lines.append("Longest streak: \(stats.longestStreak) day(s)")
        lines.append(String(format: "Average interval: %.1f days",
                            stats.averageInterval))
        if !stats.itemsByFeed.isEmpty {
            lines.append("\nItems by feed:")
            for (name, count) in stats.itemsByFeed {
                lines.append("  \(name): \(count)")
            }
        }
        return lines.joined(separator: "\n")
    }

    // MARK: - Bulk Operations

    /// Remove all mastered items from the queue.
    @discardableResult
    func clearMastered() -> Int {
        let mastered = items.values.filter { $0.isMastered }
        for item in mastered {
            items.removeValue(forKey: item.articleLink)
        }
        if !mastered.isEmpty {
            save()
            NotificationCenter.default.post(name: .spacedReviewDidChange, object: nil)
        }
        return mastered.count
    }

    /// Remove all items from the queue.
    func clearAll() {
        items.removeAll()
        reviewDates.removeAll()
        longestStreak = 0
        save()
        NotificationCenter.default.post(name: .spacedReviewDidChange, object: nil)
    }

    /// Total number of items in the queue.
    var count: Int { return items.count }

    // MARK: - Streaks

    /// Calculate current consecutive review streak.
    ///
    /// Uses `Calendar.date(byAdding:)` instead of raw `TimeInterval` arithmetic
    /// to correctly handle DST transitions and leap seconds.
    func currentStreak(at date: Date = Date()) -> Int {
        let calendar = Calendar.current
        var streak = 0
        var checkDate = date

        // Check if today has reviews
        let todayStr = Self.dateString(from: checkDate)
        if !reviewDates.contains(todayStr) {
            // Check yesterday — streak might still be alive
            guard let yesterday = calendar.date(byAdding: .day, value: -1, to: checkDate) else {
                return 0
            }
            checkDate = yesterday
            let yesterdayStr = Self.dateString(from: checkDate)
            if !reviewDates.contains(yesterdayStr) {
                return 0
            }
        }

        // Count backwards
        while true {
            let dateStr = Self.dateString(from: checkDate)
            if reviewDates.contains(dateStr) {
                streak += 1
                guard let prevDay = calendar.date(byAdding: .day, value: -1, to: checkDate) else {
                    break
                }
                checkDate = prevDay
            } else {
                break
            }
        }

        return streak
    }

    // MARK: - Helpers

    private static func dateString(from date: Date) -> String {
        return DateFormatting.isoDate.string(from: date)
    }

    // MARK: - Persistence

    private func save() {
        let model = StorageModel(
            items: Array(items.values),
            reviewDates: Array(reviewDates),
            longestStreak: longestStreak
        )
        let encoder = JSONCoding.iso8601Encoder
        if let data = try? encoder.encode(model) {
            try? data.write(to: Self.fileURL, options: .atomic)
        }
    }

    private func load() {
        guard let data = try? Data(contentsOf: Self.fileURL) else { return }
        let decoder = JSONCoding.iso8601Decoder
        guard let model = try? decoder.decode(StorageModel.self, from: data) else { return }

        items = [:]
        for item in model.items {
            items[item.articleLink] = item
        }
        reviewDates = Set(model.reviewDates)
        longestStreak = model.longestStreak
    }
}
