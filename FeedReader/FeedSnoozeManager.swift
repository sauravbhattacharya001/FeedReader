//
//  FeedSnoozeManager.swift
//  FeedReader
//
//  Temporarily mute (snooze) feeds for a specified duration without
//  unsubscribing. Snoozed feeds are automatically unmuted when their
//  snooze period expires. Useful for high-volume feeds during busy
//  periods or feeds covering topics you want to ignore temporarily.
//

import Foundation

/// Manages temporary snooze state for RSS feeds.
///
/// Usage:
/// ```
/// let manager = FeedSnoozeManager()
/// manager.snooze(feedURL: "https://example.com/feed", duration: .hours(4))
/// manager.isSnoozed(feedURL: "https://example.com/feed")  // true
/// // ... 4 hours later ...
/// manager.isSnoozed(feedURL: "https://example.com/feed")  // false
///
/// // Snooze with a preset
/// manager.snooze(feedURL: url, preset: .untilTomorrow)
///
/// // Check all active snoozes
/// let active = manager.activeSnoozes()
///
/// // Unsnooze early
/// manager.unsnooze(feedURL: url)
/// ```
class FeedSnoozeManager {

    // MARK: - Types

    /// Predefined snooze durations for common use cases.
    enum SnoozePreset: String, CaseIterable, Codable {
        case oneHour = "1 Hour"
        case fourHours = "4 Hours"
        case oneDay = "1 Day"
        case threeDays = "3 Days"
        case oneWeek = "1 Week"
        case twoWeeks = "2 Weeks"
        case untilTomorrow = "Until Tomorrow"
        case untilMonday = "Until Monday"

        /// The duration in seconds for this preset.
        /// For calendar-relative presets (untilTomorrow, untilMonday),
        /// returns the interval from the current time.
        var timeInterval: TimeInterval {
            switch self {
            case .oneHour:
                return 3600
            case .fourHours:
                return 3600 * 4
            case .oneDay:
                return 86400
            case .threeDays:
                return 86400 * 3
            case .oneWeek:
                return 86400 * 7
            case .twoWeeks:
                return 86400 * 14
            case .untilTomorrow:
                return FeedSnoozeManager.secondsUntilTomorrow()
            case .untilMonday:
                return FeedSnoozeManager.secondsUntilNextMonday()
            }
        }
    }

    /// Duration specification for snoozing.
    enum SnoozeDuration {
        case hours(Int)
        case days(Int)
        case preset(SnoozePreset)
        case until(Date)

        /// Compute the expiry date from now.
        var expiryDate: Date {
            switch self {
            case .hours(let h):
                return Date().addingTimeInterval(TimeInterval(h) * 3600)
            case .days(let d):
                return Date().addingTimeInterval(TimeInterval(d) * 86400)
            case .preset(let p):
                return Date().addingTimeInterval(p.timeInterval)
            case .until(let date):
                return date
            }
        }
    }

    /// A single snooze entry for a feed.
    struct SnoozeEntry: Codable, Equatable {
        let feedURL: String
        let snoozedAt: Date
        let expiresAt: Date
        let reason: String?

        /// Whether this snooze has expired.
        var isExpired: Bool {
            return Date() >= expiresAt
        }

        /// Remaining seconds until this snooze expires. Returns 0 if expired.
        var remainingSeconds: TimeInterval {
            return max(0, expiresAt.timeIntervalSince(Date()))
        }

        /// Human-readable remaining time string.
        var remainingDescription: String {
            let remaining = remainingSeconds
            if remaining <= 0 { return "Expired" }
            if remaining < 3600 {
                let mins = Int(remaining / 60)
                return "\(mins)m remaining"
            }
            if remaining < 86400 {
                let hours = Int(remaining / 3600)
                let mins = Int((remaining.truncatingRemainder(dividingBy: 3600)) / 60)
                return "\(hours)h \(mins)m remaining"
            }
            let days = Int(remaining / 86400)
            let hours = Int((remaining.truncatingRemainder(dividingBy: 86400)) / 3600)
            return "\(days)d \(hours)h remaining"
        }
    }

    /// Summary statistics for snooze usage.
    struct SnoozeStats: Equatable {
        let activeSnoozesCount: Int
        let totalSnoozesEver: Int
        let averageSnoozeDurationHours: Double
        let mostSnoozedFeedURL: String?
    }

    // MARK: - Properties

    private var entries: [String: SnoozeEntry] = [:]
    private var snoozeHistory: [SnoozeEntry] = []
    private let storageKey = "feedSnoozeEntries"
    private let historyKey = "feedSnoozeHistory"
    private let defaults: UserDefaults

    // MARK: - Initialization

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        loadEntries()
    }

    // MARK: - Public API

    /// Snooze a feed for the given duration.
    @discardableResult
    func snooze(feedURL: String, duration: SnoozeDuration, reason: String? = nil) -> SnoozeEntry {
        let normalized = feedURL.lowercased()
        let entry = SnoozeEntry(
            feedURL: normalized,
            snoozedAt: Date(),
            expiresAt: duration.expiryDate,
            reason: reason
        )
        entries[normalized] = entry
        snoozeHistory.append(entry)
        saveEntries()
        return entry
    }

    /// Snooze a feed using a preset duration.
    @discardableResult
    func snooze(feedURL: String, preset: SnoozePreset, reason: String? = nil) -> SnoozeEntry {
        return snooze(feedURL: feedURL, duration: .preset(preset), reason: reason)
    }

    /// Check if a feed is currently snoozed (and not expired).
    func isSnoozed(feedURL: String) -> Bool {
        let normalized = feedURL.lowercased()
        guard let entry = entries[normalized] else { return false }
        if entry.isExpired {
            entries.removeValue(forKey: normalized)
            saveEntries()
            return false
        }
        return true
    }

    /// Get the snooze entry for a feed, if active.
    func snoozeEntry(for feedURL: String) -> SnoozeEntry? {
        let normalized = feedURL.lowercased()
        guard let entry = entries[normalized], !entry.isExpired else { return nil }
        return entry
    }

    /// Remove snooze for a feed (unsnooze early).
    func unsnooze(feedURL: String) {
        let normalized = feedURL.lowercased()
        entries.removeValue(forKey: normalized)
        saveEntries()
    }

    /// Get all currently active (non-expired) snoozes.
    func activeSnoozes() -> [SnoozeEntry] {
        pruneExpired()
        return entries.values.sorted { $0.expiresAt < $1.expiresAt }
    }

    /// Unsnooze all feeds.
    func unsnoozeAll() {
        entries.removeAll()
        saveEntries()
    }

    /// Extend an existing snooze by additional time.
    @discardableResult
    func extendSnooze(feedURL: String, by additionalHours: Int) -> SnoozeEntry? {
        let normalized = feedURL.lowercased()
        guard let existing = entries[normalized], !existing.isExpired else { return nil }
        let newExpiry = existing.expiresAt.addingTimeInterval(TimeInterval(additionalHours) * 3600)
        let updated = SnoozeEntry(
            feedURL: normalized,
            snoozedAt: existing.snoozedAt,
            expiresAt: newExpiry,
            reason: existing.reason
        )
        entries[normalized] = updated
        saveEntries()
        return updated
    }

    /// Get snooze statistics.
    func stats() -> SnoozeStats {
        pruneExpired()
        let activeCount = entries.count
        let totalCount = snoozeHistory.count

        let avgHours: Double
        if snoozeHistory.isEmpty {
            avgHours = 0
        } else {
            let totalHours = snoozeHistory.reduce(0.0) {
                $0 + $1.expiresAt.timeIntervalSince($1.snoozedAt) / 3600
            }
            avgHours = totalHours / Double(snoozeHistory.count)
        }

        // Find most snoozed feed
        var feedCounts: [String: Int] = [:]
        for entry in snoozeHistory {
            feedCounts[entry.feedURL, default: 0] += 1
        }
        let mostSnoozed = feedCounts.max(by: { $0.value < $1.value })?.key

        return SnoozeStats(
            activeSnoozesCount: activeCount,
            totalSnoozesEver: totalCount,
            averageSnoozeDurationHours: avgHours,
            mostSnoozedFeedURL: mostSnoozed
        )
    }

    /// Filter an array of feeds, removing snoozed ones.
    func filterSnoozed(feeds: [Feed]) -> [Feed] {
        return feeds.filter { !isSnoozed(feedURL: $0.url) }
    }

    /// Prune all expired entries.
    @discardableResult
    func pruneExpired() -> Int {
        let before = entries.count
        entries = entries.filter { !$0.value.isExpired }
        let removed = before - entries.count
        if removed > 0 { saveEntries() }
        return removed
    }

    // MARK: - Persistence

    private func saveEntries() {
        if let data = try? JSONEncoder().encode(Array(entries.values)) {
            defaults.set(data, forKey: storageKey)
        }
        if let histData = try? JSONEncoder().encode(snoozeHistory) {
            defaults.set(histData, forKey: historyKey)
        }
    }

    private func loadEntries() {
        if let data = defaults.data(forKey: storageKey),
           let loaded = try? JSONDecoder().decode([SnoozeEntry].self, from: data) {
            entries = Dictionary(uniqueKeysWithValues: loaded.map { ($0.feedURL, $0) })
        }
        if let histData = defaults.data(forKey: historyKey),
           let loaded = try? JSONDecoder().decode([SnoozeEntry].self, from: histData) {
            snoozeHistory = loaded
        }
    }

    // MARK: - Calendar Helpers

    /// Seconds from now until tomorrow at 8:00 AM.
    static func secondsUntilTomorrow() -> TimeInterval {
        let calendar = Calendar.current
        let now = Date()
        guard let tomorrow = calendar.date(byAdding: .day, value: 1, to: now) else { return 86400 }
        let morning = calendar.date(bySettingHour: 8, minute: 0, second: 0, of: tomorrow) ?? tomorrow
        return morning.timeIntervalSince(now)
    }

    /// Seconds from now until next Monday at 8:00 AM.
    static func secondsUntilNextMonday() -> TimeInterval {
        let calendar = Calendar.current
        let now = Date()
        let weekday = calendar.component(.weekday, from: now) // 1=Sun, 2=Mon, ...
        let daysUntilMonday = weekday == 2 ? 7 : ((9 - weekday) % 7)
        guard let monday = calendar.date(byAdding: .day, value: daysUntilMonday, to: now) else {
            return 86400 * 7
        }
        let morning = calendar.date(bySettingHour: 8, minute: 0, second: 0, of: monday) ?? monday
        return morning.timeIntervalSince(now)
    }
}
