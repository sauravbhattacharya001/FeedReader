//
//  FeedUpdateScheduler.swift
//  FeedReader
//
//  Adaptive feed polling scheduler that learns each feed's publishing
//  frequency and adjusts check intervals accordingly. Frequently
//  updated feeds are checked more often; dormant feeds are checked
//  rarely — saving bandwidth and battery.
//

import Foundation

/// Manages adaptive polling intervals for RSS feeds based on their
/// observed publishing frequency.
///
/// Usage:
/// ```
/// let scheduler = FeedUpdateScheduler()
/// scheduler.recordNewArticles(feedURL: url, count: 3, at: Date())
/// let nextCheck = scheduler.nextCheckDate(for: url)
/// let stats = scheduler.stats(for: url)
/// ```
class FeedUpdateScheduler {

    // MARK: - Types

    /// A single observation of a feed check — records how many new
    /// articles appeared since the last check.
    struct CheckRecord: Codable, Equatable {
        let timestamp: Date
        let newArticleCount: Int
    }

    /// Per-feed scheduling state persisted between sessions.
    struct FeedSchedule: Codable, Equatable {
        let feedURL: String
        var currentInterval: TimeInterval
        var lastChecked: Date?
        var checkHistory: [CheckRecord]
        var consecutiveEmpty: Int
        var totalChecks: Int
        var totalNewArticles: Int
    }

    /// Summary statistics for display in the UI.
    struct FeedScheduleStats {
        let feedURL: String
        let currentInterval: TimeInterval
        let currentIntervalLabel: String
        let lastChecked: Date?
        let nextCheck: Date?
        let averageArticlesPerCheck: Double
        let consecutiveEmpty: Int
        let totalChecks: Int
        let totalNewArticles: Int
        let efficiency: Double  // ratio of checks that found content
    }

    /// Represents the urgency tier of a feed's update frequency.
    enum UpdateTier: String, CaseIterable, Comparable {
        case realtime   = "Realtime"    // ≤ 5 min
        case frequent   = "Frequent"    // ≤ 30 min
        case standard   = "Standard"    // ≤ 2 hours
        case relaxed    = "Relaxed"     // ≤ 8 hours
        case infrequent = "Infrequent"  // ≤ 24 hours
        case dormant    = "Dormant"     // > 24 hours

        static func < (lhs: UpdateTier, rhs: UpdateTier) -> Bool {
            let order: [UpdateTier] = [.realtime, .frequent, .standard, .relaxed, .infrequent, .dormant]
            guard let l = order.firstIndex(of: lhs),
                  let r = order.firstIndex(of: rhs) else { return false }
            return l < r
        }
    }

    // MARK: - Configuration

    /// Minimum polling interval (seconds). Prevents hammering servers.
    static let minimumInterval: TimeInterval = 5 * 60        // 5 minutes

    /// Maximum polling interval (seconds). Even dormant feeds get checked.
    static let maximumInterval: TimeInterval = 48 * 60 * 60  // 48 hours

    /// Default interval for new feeds before any history is gathered.
    static let defaultInterval: TimeInterval = 30 * 60       // 30 minutes

    /// How many check records to retain per feed.
    static let maxHistorySize: Int = 50

    /// Back-off multiplier when no new articles are found.
    static let backoffMultiplier: Double = 1.5

    /// Speed-up divisor when new articles are found.
    static let speedupDivisor: Double = 2.0

    /// Number of consecutive empty checks before reaching max back-off.
    static let maxConsecutiveEmpty: Int = 10

    // MARK: - State

    private(set) var schedules: [String: FeedSchedule]

    /// Injected date source for testability.
    private let dateProvider: () -> Date

    // MARK: - Initialization

    /// Creates a scheduler.
    /// - Parameter dateProvider: Closure returning the current date (default: `Date()`).
    init(dateProvider: @escaping () -> Date = { Date() }) {
        self.schedules = [:]
        self.dateProvider = dateProvider
    }

    /// Restores a scheduler from previously saved schedules.
    init(schedules: [String: FeedSchedule], dateProvider: @escaping () -> Date = { Date() }) {
        self.schedules = schedules
        self.dateProvider = dateProvider
    }

    // MARK: - Core API

    /// Records the result of checking a feed for new articles.
    ///
    /// This is the primary input to the adaptive algorithm. Call this
    /// after each feed refresh with the number of new articles found.
    ///
    /// - Parameters:
    ///   - feedURL: The feed's canonical URL.
    ///   - count: Number of new articles discovered (0 if none).
    ///   - date: When the check occurred (default: now).
    @discardableResult
    func recordCheck(feedURL: String, newArticleCount count: Int, at date: Date? = nil) -> FeedSchedule {
        let now = date ?? dateProvider()
        let key = feedURL.lowercased()

        var schedule = schedules[key] ?? FeedSchedule(
            feedURL: feedURL,
            currentInterval: Self.defaultInterval,
            lastChecked: nil,
            checkHistory: [],
            consecutiveEmpty: 0,
            totalChecks: 0,
            totalNewArticles: 0
        )

        // Record history
        let record = CheckRecord(timestamp: now, newArticleCount: count)
        schedule.checkHistory.append(record)
        if schedule.checkHistory.count > Self.maxHistorySize {
            schedule.checkHistory.removeFirst(schedule.checkHistory.count - Self.maxHistorySize)
        }

        // Update counters
        schedule.totalChecks += 1
        schedule.totalNewArticles += count
        schedule.lastChecked = now

        if count == 0 {
            schedule.consecutiveEmpty += 1
            // Back off: increase interval
            let newInterval = schedule.currentInterval * Self.backoffMultiplier
            schedule.currentInterval = min(newInterval, Self.maximumInterval)
        } else {
            schedule.consecutiveEmpty = 0
            // Speed up: decrease interval proportional to volume
            let volumeFactor = count > 3 ? Self.speedupDivisor * 1.5 : Self.speedupDivisor
            let newInterval = schedule.currentInterval / volumeFactor
            schedule.currentInterval = max(newInterval, Self.minimumInterval)
        }

        schedules[key] = schedule
        return schedule
    }

    /// Returns when the given feed should next be checked.
    func nextCheckDate(for feedURL: String) -> Date {
        let key = feedURL.lowercased()
        guard let schedule = schedules[key],
              let lastChecked = schedule.lastChecked else {
            // Never checked — check immediately
            return dateProvider()
        }
        return lastChecked.addingTimeInterval(schedule.currentInterval)
    }

    /// Returns `true` if the feed is due for a check now.
    func isDue(feedURL: String) -> Bool {
        return nextCheckDate(for: feedURL) <= dateProvider()
    }

    /// Returns all feeds sorted by next check date (soonest first).
    func feedsDueSoonest() -> [(feedURL: String, nextCheck: Date)] {
        return schedules.map { (key, schedule) in
            let next = nextCheckDate(for: key)
            return (feedURL: schedule.feedURL, nextCheck: next)
        }
        .sorted { $0.nextCheck < $1.nextCheck }
    }

    /// Returns only feeds that are currently due for checking.
    func feedsDueNow() -> [String] {
        let now = dateProvider()
        return schedules
            .filter { nextCheckDate(for: $0.key) <= now }
            .sorted { nextCheckDate(for: $0.key) < nextCheckDate(for: $1.key) }
            .map { $0.value.feedURL }
    }

    // MARK: - Tier Classification

    /// Returns the update tier for a feed based on its current interval.
    func tier(for feedURL: String) -> UpdateTier {
        let key = feedURL.lowercased()
        guard let schedule = schedules[key] else { return .standard }
        return Self.tierForInterval(schedule.currentInterval)
    }

    /// Classifies an interval into an update tier.
    static func tierForInterval(_ interval: TimeInterval) -> UpdateTier {
        switch interval {
        case ...300:        return .realtime    // ≤ 5 min
        case ...1800:       return .frequent    // ≤ 30 min
        case ...7200:       return .standard    // ≤ 2 hours
        case ...28800:      return .relaxed     // ≤ 8 hours
        case ...86400:      return .infrequent  // ≤ 24 hours
        default:            return .dormant     // > 24 hours
        }
    }

    /// Returns a count of feeds in each tier.
    func tierSummary() -> [UpdateTier: Int] {
        var counts: [UpdateTier: Int] = [:]
        for schedule in schedules.values {
            let t = Self.tierForInterval(schedule.currentInterval)
            counts[t, default: 0] += 1
        }
        return counts
    }

    // MARK: - Statistics

    /// Returns detailed stats for a single feed.
    func stats(for feedURL: String) -> FeedScheduleStats? {
        let key = feedURL.lowercased()
        guard let schedule = schedules[key] else { return nil }
        return buildStats(schedule)
    }

    /// Returns stats for all tracked feeds.
    func allStats() -> [FeedScheduleStats] {
        return schedules.values.map { buildStats($0) }
    }

    /// Returns aggregate statistics across all feeds.
    func aggregateStats() -> (totalFeeds: Int, totalChecks: Int, totalArticles: Int,
                               averageInterval: TimeInterval, overallEfficiency: Double) {
        guard !schedules.isEmpty else {
            return (0, 0, 0, 0, 0)
        }
        let total = schedules.values.reduce((checks: 0, articles: 0, intervals: 0.0)) { acc, s in
            (acc.checks + s.totalChecks, acc.articles + s.totalNewArticles,
             acc.intervals + s.currentInterval)
        }
        let avgInterval = total.intervals / Double(schedules.count)
        let efficiency = total.checks > 0
            ? Double(total.checks - schedules.values.reduce(0) { $0 + $1.consecutiveEmpty }) / Double(total.checks)
            : 0
        return (schedules.count, total.checks, total.articles, avgInterval, efficiency)
    }

    // MARK: - Manual Overrides

    /// Manually sets a feed's polling interval, clamped to valid range.
    func setInterval(_ interval: TimeInterval, for feedURL: String) {
        let key = feedURL.lowercased()
        let clamped = max(Self.minimumInterval, min(interval, Self.maximumInterval))
        if var schedule = schedules[key] {
            schedule.currentInterval = clamped
            schedules[key] = schedule
        } else {
            schedules[key] = FeedSchedule(
                feedURL: feedURL,
                currentInterval: clamped,
                lastChecked: nil,
                checkHistory: [],
                consecutiveEmpty: 0,
                totalChecks: 0,
                totalNewArticles: 0
            )
        }
    }

    /// Resets a feed's schedule to defaults, clearing all history.
    func resetSchedule(for feedURL: String) {
        let key = feedURL.lowercased()
        schedules.removeValue(forKey: key)
    }

    /// Removes tracking data for feeds not in the provided list.
    func pruneFeeds(keeping activeFeedURLs: [String]) {
        let activeKeys = Set(activeFeedURLs.map { $0.lowercased() })
        schedules = schedules.filter { activeKeys.contains($0.key) }
    }

    // MARK: - Persistence

    /// Encodes all schedules to JSON data for storage.
    func serialize() throws -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(schedules)
    }

    /// Restores schedules from JSON data.
    static func deserialize(from data: Data, dateProvider: @escaping () -> Date = { Date() }) throws -> FeedUpdateScheduler {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let schedules = try decoder.decode([String: FeedSchedule].self, from: data)
        return FeedUpdateScheduler(schedules: schedules, dateProvider: dateProvider)
    }

    // MARK: - Private

    private func buildStats(_ schedule: FeedSchedule) -> FeedScheduleStats {
        let avg = schedule.totalChecks > 0
            ? Double(schedule.totalNewArticles) / Double(schedule.totalChecks)
            : 0
        let nonEmptyChecks = schedule.checkHistory.filter { $0.newArticleCount > 0 }.count
        let efficiency = schedule.checkHistory.isEmpty
            ? 0
            : Double(nonEmptyChecks) / Double(schedule.checkHistory.count)

        return FeedScheduleStats(
            feedURL: schedule.feedURL,
            currentInterval: schedule.currentInterval,
            currentIntervalLabel: Self.formatInterval(schedule.currentInterval),
            lastChecked: schedule.lastChecked,
            nextCheck: schedule.lastChecked.map { $0.addingTimeInterval(schedule.currentInterval) },
            averageArticlesPerCheck: avg,
            consecutiveEmpty: schedule.consecutiveEmpty,
            totalChecks: schedule.totalChecks,
            totalNewArticles: schedule.totalNewArticles,
            efficiency: efficiency
        )
    }

    /// Human-readable label for a time interval.
    static func formatInterval(_ interval: TimeInterval) -> String {
        if interval < 60 {
            return "\(Int(interval))s"
        } else if interval < 3600 {
            let mins = Int(interval / 60)
            return "\(mins) min"
        } else if interval < 86400 {
            let hours = interval / 3600
            if hours == Double(Int(hours)) {
                return "\(Int(hours))h"
            }
            return String(format: "%.1fh", hours)
        } else {
            let days = interval / 86400
            if days == Double(Int(days)) {
                return "\(Int(days))d"
            }
            return String(format: "%.1fd", days)
        }
    }
}
