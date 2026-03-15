//
//  FeedNotificationManager.swift
//  FeedReader
//
//  Configurable per-feed notification rules — control how and when
//  you're notified about new articles from each feed.
//
//  Key features:
//  - Per-feed notification profiles (immediate, batched, silent)
//  - Quiet hours with day-of-week support
//  - Priority-based filtering (only notify for high-priority matches)
//  - Keyword boost: escalate notification priority when keywords match
//  - Snooze individual feeds for a configurable duration
//  - Batch/digest mode: collect articles and notify at intervals
//  - Global mute toggle
//  - Notification history log with deduplication
//  - JSON persistence in Documents directory
//

import Foundation

// MARK: - Notifications

extension Notification.Name {
    /// Posted when notification rules change.
    static let feedNotificationRulesDidChange = Notification.Name("FeedNotificationRulesDidChangeNotification")
    /// Posted when a notification is delivered (or queued).
    static let feedNotificationDelivered = Notification.Name("FeedNotificationDeliveredNotification")
}

// MARK: - NotificationMode

/// How notifications are delivered for a feed.
enum NotificationMode: String, Codable {
    /// Notify immediately for each new article.
    case immediate
    /// Collect articles and deliver as a batch at intervals.
    case batched
    /// No notifications — articles still appear in feed.
    case silent
}

// MARK: - QuietHoursRule

/// Defines a quiet period during which notifications are suppressed.
struct QuietHoursRule: Codable, Equatable {
    /// Start hour (0-23).
    let startHour: Int
    /// Start minute (0-59).
    let startMinute: Int
    /// End hour (0-23).
    let endHour: Int
    /// End minute (0-59).
    let endMinute: Int
    /// Days of week this rule applies (1=Sunday, 7=Saturday). Empty = every day.
    let activeDays: Set<Int>

    /// Check if a given date falls within quiet hours.
    func isQuiet(at date: Date, calendar: Calendar = .current) -> Bool {
        let weekday = calendar.component(.weekday, from: date)
        if !activeDays.isEmpty && !activeDays.contains(weekday) {
            return false
        }
        let hour = calendar.component(.hour, from: date)
        let minute = calendar.component(.minute, from: date)
        let current = hour * 60 + minute
        let start = startHour * 60 + startMinute
        let end = endHour * 60 + endMinute

        if start <= end {
            return current >= start && current < end
        } else {
            // Wraps midnight (e.g. 22:00 - 07:00)
            return current >= start || current < end
        }
    }
}

// MARK: - FeedNotificationRule

/// Per-feed notification configuration.
struct FeedNotificationRule: Codable, Equatable {
    /// Feed name or identifier this rule applies to.
    let feedName: String
    /// Notification delivery mode.
    var mode: NotificationMode
    /// Minimum alert priority to trigger notifications (nil = all priorities).
    var minimumPriority: AlertPriority?
    /// Keywords that boost an article to immediate notification regardless of mode.
    var boostKeywords: [String]
    /// Whether this feed is currently snoozed.
    var snoozedUntil: Date?
    /// Custom quiet hours for this feed (overrides global).
    var quietHours: QuietHoursRule?
    /// Batch interval in minutes (only used when mode == .batched).
    var batchIntervalMinutes: Int

    init(feedName: String,
         mode: NotificationMode = .immediate,
         minimumPriority: AlertPriority? = nil,
         boostKeywords: [String] = [],
         snoozedUntil: Date? = nil,
         quietHours: QuietHoursRule? = nil,
         batchIntervalMinutes: Int = 60) {
        self.feedName = feedName
        self.mode = mode
        self.minimumPriority = minimumPriority
        self.boostKeywords = boostKeywords
        self.snoozedUntil = snoozedUntil
        self.quietHours = quietHours
        self.batchIntervalMinutes = batchIntervalMinutes
    }

    /// Whether the feed is currently snoozed.
    var isSnoozed: Bool {
        guard let until = snoozedUntil else { return false }
        return Date() < until
    }
}

// MARK: - NotificationRecord

/// A log entry for a delivered or queued notification.
struct NotificationRecord: Codable, Equatable {
    let id: String
    let feedName: String
    let articleTitle: String
    let articleLink: String
    let timestamp: Date
    let wasBatched: Bool
    let wasBoosted: Bool
}

// MARK: - NotificationDecision

/// Result of evaluating whether to notify for an article.
enum NotificationDecision: Equatable {
    /// Deliver notification immediately.
    case deliver
    /// Queue for batch delivery.
    case queue
    /// Suppress notification.
    case suppress(reason: String)
}

// MARK: - FeedNotificationManager

class FeedNotificationManager {

    // MARK: - Singleton

    static let shared = FeedNotificationManager()

    // MARK: - Properties

    /// Per-feed notification rules.
    private(set) var rules: [String: FeedNotificationRule] = [:]

    /// Global quiet hours (applies to feeds without custom quiet hours).
    var globalQuietHours: QuietHoursRule?

    /// Global mute — suppresses all notifications when true.
    var isGloballyMuted: Bool = false

    /// Notification history log.
    private(set) var history: [NotificationRecord] = []

    /// Queued articles waiting for batch delivery, keyed by feed name.
    private(set) var batchQueue: [String: [(title: String, link: String, date: Date)]] = [:]

    /// Maximum history entries to keep.
    let maxHistorySize: Int = 500

    /// Deduplication window in seconds (don't re-notify same article within window).
    let deduplicationWindow: TimeInterval = 3600

    // MARK: - Persistence

    private static let rulesFileName = "feed_notification_rules.json"
    private static let historyFileName = "feed_notification_history.json"

    private var rulesFileURL: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent(Self.rulesFileName)
    }

    private var historyFileURL: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent(Self.historyFileName)
    }

    // MARK: - Codable Wrappers

    private struct RulesStore: Codable {
        let rules: [String: FeedNotificationRule]
        let globalQuietHours: QuietHoursRule?
        let isGloballyMuted: Bool
    }

    // MARK: - Init

    init() {
        loadRules()
        loadHistory()
    }

    // MARK: - Rule Management

    /// Set or update a notification rule for a feed.
    func setRule(_ rule: FeedNotificationRule) {
        rules[rule.feedName] = rule
        saveRules()
        NotificationCenter.default.post(name: .feedNotificationRulesDidChange, object: self)
    }

    /// Remove the notification rule for a feed (falls back to defaults).
    func removeRule(for feedName: String) {
        rules.removeValue(forKey: feedName)
        saveRules()
        NotificationCenter.default.post(name: .feedNotificationRulesDidChange, object: self)
    }

    /// Get the effective rule for a feed (or a default immediate rule).
    func effectiveRule(for feedName: String) -> FeedNotificationRule {
        return rules[feedName] ?? FeedNotificationRule(feedName: feedName)
    }

    /// Snooze a feed for the given duration.
    func snoozeFeed(_ feedName: String, for duration: TimeInterval) {
        var rule = effectiveRule(for: feedName)
        rule.snoozedUntil = Date().addingTimeInterval(duration)
        // Need to create a new rule since feedName is let
        let updated = FeedNotificationRule(
            feedName: feedName,
            mode: rule.mode,
            minimumPriority: rule.minimumPriority,
            boostKeywords: rule.boostKeywords,
            snoozedUntil: rule.snoozedUntil,
            quietHours: rule.quietHours,
            batchIntervalMinutes: rule.batchIntervalMinutes
        )
        setRule(updated)
    }

    /// Unsnooze a feed.
    func unsnoozeFeed(_ feedName: String) {
        guard var rule = rules[feedName] else { return }
        let updated = FeedNotificationRule(
            feedName: feedName,
            mode: rule.mode,
            minimumPriority: rule.minimumPriority,
            boostKeywords: rule.boostKeywords,
            snoozedUntil: nil,
            quietHours: rule.quietHours,
            batchIntervalMinutes: rule.batchIntervalMinutes
        )
        setRule(updated)
    }

    /// List all snoozed feeds (with active snooze).
    func snoozedFeeds() -> [FeedNotificationRule] {
        return rules.values.filter { $0.isSnoozed }
    }

    /// List all feeds set to silent mode.
    func silentFeeds() -> [String] {
        return rules.values.filter { $0.mode == .silent }.map { $0.feedName }
    }

    // MARK: - Notification Evaluation

    /// Evaluate whether a story from a feed should trigger a notification.
    func evaluate(story: Story, feedName: String, priority: AlertPriority? = nil, at date: Date = Date()) -> NotificationDecision {
        // Global mute
        if isGloballyMuted {
            return .suppress(reason: "globally_muted")
        }

        let rule = effectiveRule(for: feedName)

        // Snoozed
        if let until = rule.snoozedUntil, date < until {
            return .suppress(reason: "snoozed")
        }

        // Silent mode
        if rule.mode == .silent {
            return .suppress(reason: "silent_mode")
        }

        // Priority filter
        if let minPriority = rule.minimumPriority, let storyPriority = priority {
            if storyPriority.sortOrder > minPriority.sortOrder {
                return .suppress(reason: "below_priority")
            }
        }

        // Check keyword boost — if matched, always deliver immediately
        if !rule.boostKeywords.isEmpty {
            let text = (story.title + " " + story.body).lowercased()
            let boosted = rule.boostKeywords.contains { text.contains($0.lowercased()) }
            if boosted {
                return .deliver
            }
        }

        // Quiet hours check
        let quietRule = rule.quietHours ?? globalQuietHours
        if let qh = quietRule, qh.isQuiet(at: date) {
            return .suppress(reason: "quiet_hours")
        }

        // Deduplication
        if isDuplicate(articleLink: story.link, feedName: feedName, at: date) {
            return .suppress(reason: "duplicate")
        }

        // Mode-based decision
        switch rule.mode {
        case .immediate:
            return .deliver
        case .batched:
            return .queue
        case .silent:
            return .suppress(reason: "silent_mode")
        }
    }

    // MARK: - Batch Management

    /// Add an article to the batch queue for later delivery.
    func enqueue(title: String, link: String, feedName: String, at date: Date = Date()) {
        var queue = batchQueue[feedName] ?? []
        queue.append((title: title, link: link, date: date))
        batchQueue[feedName] = queue
    }

    /// Get queued articles for a feed that are ready for batch delivery.
    func pendingBatch(for feedName: String, at date: Date = Date()) -> [(title: String, link: String, date: Date)] {
        let rule = effectiveRule(for: feedName)
        guard rule.mode == .batched else { return [] }
        guard let queue = batchQueue[feedName], !queue.isEmpty else { return [] }

        let interval = TimeInterval(rule.batchIntervalMinutes * 60)
        guard let earliest = queue.first?.date,
              date.timeIntervalSince(earliest) >= interval else {
            return []
        }

        return queue
    }

    /// Flush the batch queue for a feed, recording delivered notifications.
    func flushBatch(for feedName: String, at date: Date = Date()) -> [NotificationRecord] {
        guard let queue = batchQueue[feedName], !queue.isEmpty else { return [] }

        let records = queue.map { item in
            NotificationRecord(
                id: UUID().uuidString,
                feedName: feedName,
                articleTitle: item.title,
                articleLink: item.link,
                timestamp: date,
                wasBatched: true,
                wasBoosted: false
            )
        }

        for record in records {
            addHistoryRecord(record)
        }

        batchQueue[feedName] = []
        return records
    }

    /// Get all feeds with pending batch items.
    func feedsWithPendingBatches() -> [String] {
        return batchQueue.keys.filter { !(batchQueue[$0]?.isEmpty ?? true) }
    }

    // MARK: - Notification Delivery

    /// Record that a notification was delivered for a story.
    func recordDelivery(story: Story, feedName: String, wasBoosted: Bool = false) -> NotificationRecord {
        let record = NotificationRecord(
            id: UUID().uuidString,
            feedName: feedName,
            articleTitle: story.title,
            articleLink: story.link,
            timestamp: Date(),
            wasBatched: false,
            wasBoosted: wasBoosted
        )
        addHistoryRecord(record)
        NotificationCenter.default.post(name: .feedNotificationDelivered, object: self,
                                        userInfo: ["record": record])
        return record
    }

    // MARK: - History

    /// Recent notification history, newest first.
    func recentHistory(limit: Int = 50) -> [NotificationRecord] {
        return Array(history.suffix(limit).reversed())
    }

    /// Notification count for a feed within a time window.
    func notificationCount(for feedName: String, since date: Date) -> Int {
        return history.filter { $0.feedName == feedName && $0.timestamp >= date }.count
    }

    /// Clear all notification history.
    func clearHistory() {
        history.removeAll()
        saveHistory()
    }

    // MARK: - Summary / Stats

    /// Summary statistics across all feeds.
    func summary() -> (totalRules: Int, snoozed: Int, silent: Int, batched: Int, pendingBatchItems: Int, historyCount: Int) {
        let snoozed = rules.values.filter { $0.isSnoozed }.count
        let silent = rules.values.filter { $0.mode == .silent }.count
        let batched = rules.values.filter { $0.mode == .batched }.count
        let pending = batchQueue.values.reduce(0) { $0 + $1.count }
        return (rules.count, snoozed, silent, batched, pending, history.count)
    }

    /// Export all rules as JSON data.
    func exportRulesJSON() -> Data? {
        let store = RulesStore(rules: rules, globalQuietHours: globalQuietHours, isGloballyMuted: isGloballyMuted)
        return try? JSONEncoder().encode(store)
    }

    /// Import rules from JSON data.
    func importRulesJSON(_ data: Data) -> Bool {
        guard let store = try? JSONDecoder().decode(RulesStore.self, from: data) else { return false }
        self.rules = store.rules
        self.globalQuietHours = store.globalQuietHours
        self.isGloballyMuted = store.isGloballyMuted
        saveRules()
        NotificationCenter.default.post(name: .feedNotificationRulesDidChange, object: self)
        return true
    }

    // MARK: - Private Helpers

    private func isDuplicate(articleLink: String, feedName: String, at date: Date) -> Bool {
        let cutoff = date.addingTimeInterval(-deduplicationWindow)
        return history.contains { $0.articleLink == articleLink && $0.feedName == feedName && $0.timestamp >= cutoff }
    }

    private func addHistoryRecord(_ record: NotificationRecord) {
        history.append(record)
        if history.count > maxHistorySize {
            history.removeFirst(history.count - maxHistorySize)
        }
        saveHistory()
    }

    // MARK: - Persistence

    func saveRules() {
        let store = RulesStore(rules: rules, globalQuietHours: globalQuietHours, isGloballyMuted: isGloballyMuted)
        if let data = try? JSONEncoder().encode(store) {
            try? data.write(to: rulesFileURL)
        }
    }

    func loadRules() {
        guard let data = try? Data(contentsOf: rulesFileURL),
              let store = try? JSONDecoder().decode(RulesStore.self, from: data) else { return }
        self.rules = store.rules
        self.globalQuietHours = store.globalQuietHours
        self.isGloballyMuted = store.isGloballyMuted
    }

    func saveHistory() {
        if let data = try? JSONEncoder().encode(history) {
            try? data.write(to: historyFileURL)
        }
    }

    func loadHistory() {
        guard let data = try? Data(contentsOf: historyFileURL),
              let loaded = try? JSONDecoder().decode([NotificationRecord].self, from: data) else { return }
        self.history = loaded
    }
}
