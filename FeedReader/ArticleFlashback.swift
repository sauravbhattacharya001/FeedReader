//
//  ArticleFlashback.swift
//  FeedReader
//
//  "On This Day" feature — resurfaces articles read on the same calendar
//  date in previous years.  Gives users a nostalgic look-back at what they
//  were reading one, two, or more years ago.
//
//  Usage:
//    let flashback = ArticleFlashback()
//    let memories = flashback.memoriesForToday()
//    // → grouped by year: [2025: [entry1, entry2], 2024: [entry3]]
//

import Foundation

// MARK: - FlashbackItem

/// A lightweight snapshot of a historical reading moment.
struct FlashbackItem: Codable, Equatable {
    /// Article URL.
    let link: String
    /// Article title at the time it was read.
    let title: String
    /// Feed/source name.
    let feedName: String
    /// When the article was originally read.
    let readDate: Date
    /// How many years ago (computed at query time, not stored).
    var yearsAgo: Int = 0

    enum CodingKeys: String, CodingKey {
        case link, title, feedName, readDate
    }

    static func == (lhs: FlashbackItem, rhs: FlashbackItem) -> Bool {
        return lhs.link == rhs.link && lhs.readDate == rhs.readDate
    }
}

// MARK: - FlashbackGroup

/// Articles grouped by how many years ago they were read.
struct FlashbackGroup {
    let yearsAgo: Int
    let year: Int
    let items: [FlashbackItem]

    /// Human-readable label, e.g. "1 Year Ago" or "3 Years Ago".
    var label: String {
        switch yearsAgo {
        case 1: return "1 Year Ago"
        default: return "\(yearsAgo) Years Ago"
        }
    }
}

// MARK: - Notification

extension Notification.Name {
    static let flashbackDidUpdate = Notification.Name("ArticleFlashbackDidUpdateNotification")
}

// MARK: - ArticleFlashback

/// Queries reading history to find articles read on the same month/day in
/// prior years.  Optionally widens the window to ±N days for more results.
class ArticleFlashback {

    // MARK: - Properties

    /// How many days around today to include (0 = exact date only).
    var windowDays: Int = 0

    /// Minimum years ago to surface (default 1 — skip current year).
    var minimumYearsAgo: Int = 1

    /// Maximum items per year group.
    var maxPerYear: Int = 20

    /// Persistent key for last-shown date (avoids re-notifying same day).
    private let lastShownKey = "ArticleFlashback_lastShownDate"

    /// UserDefaults-backed dismissed links for the current day.
    private let dismissedKey = "ArticleFlashback_dismissedLinks"

    private let calendar = Calendar.current
    private let defaults = UserDefaults.standard

    // MARK: - Public API

    /// Returns flashback groups for today (or a given date), sorted by
    /// most-recent year first.
    func memories(for date: Date = Date()) -> [FlashbackGroup] {
        let history = ReadingHistoryManager.shared
        let allEntries = history.allEntries()

        let targetMonth = calendar.component(.month, from: date)
        let targetDay = calendar.component(.day, from: date)
        let currentYear = calendar.component(.year, from: date)

        let dismissed = dismissedLinks()

        var buckets: [Int: [FlashbackItem]] = [:]

        for entry in allEntries {
            let entryYear = calendar.component(.year, from: entry.readAt)
            let yearsAgo = currentYear - entryYear

            guard yearsAgo >= minimumYearsAgo else { continue }
            guard !dismissed.contains(entry.link) else { continue }

            let entryMonth = calendar.component(.month, from: entry.readAt)
            let entryDay = calendar.component(.day, from: entry.readAt)

            if matchesWindow(targetMonth: targetMonth, targetDay: targetDay,
                             entryMonth: entryMonth, entryDay: entryDay) {
                var item = FlashbackItem(
                    link: entry.link,
                    title: entry.title,
                    feedName: entry.feedName,
                    readDate: entry.readAt
                )
                item.yearsAgo = yearsAgo

                var list = buckets[yearsAgo] ?? []
                if list.count < maxPerYear {
                    list.append(item)
                    buckets[yearsAgo] = list
                }
            }
        }

        return buckets
            .sorted { $0.key < $1.key }
            .map { FlashbackGroup(yearsAgo: $0.key, year: currentYear - $0.key, items: $0.value) }
    }

    /// Convenience: returns true when there are memories to show today.
    func hasMemoriesToday() -> Bool {
        return !memories().isEmpty
    }

    /// Total number of flashback items across all year groups for a date.
    func totalCount(for date: Date = Date()) -> Int {
        return memories(for: date).reduce(0) { $0 + $1.items.count }
    }

    /// Mark the current day as "shown" so we don't re-notify.
    func markShownToday() {
        let key = dayKey(for: Date())
        defaults.set(key, forKey: lastShownKey)
    }

    /// Whether we already showed flashbacks today.
    func hasShownToday() -> Bool {
        let key = dayKey(for: Date())
        return defaults.string(forKey: lastShownKey) == key
    }

    /// Dismiss a specific article from today's flashback.
    func dismiss(link: String) {
        var set = dismissedLinks()
        set.insert(link)
        defaults.set(Array(set), forKey: dismissedKey)
        NotificationCenter.default.post(name: .flashbackDidUpdate, object: nil)
    }

    /// Reset dismissed list (happens automatically on a new day).
    func resetDismissed() {
        defaults.removeObject(forKey: dismissedKey)
    }

    /// Get a random flashback item from today's memories (for widgets/banners).
    func randomMemory(for date: Date = Date()) -> FlashbackItem? {
        let all = memories(for: date).flatMap { $0.items }
        return all.randomElement()
    }

    /// Memories for a specific number of years ago only.
    func memories(yearsAgo: Int, for date: Date = Date()) -> [FlashbackItem] {
        return memories(for: date)
            .first(where: { $0.yearsAgo == yearsAgo })?
            .items ?? []
    }

    /// Summary string, e.g. "5 articles from 2 years".
    func summaryString(for date: Date = Date()) -> String {
        let groups = memories(for: date)
        guard !groups.isEmpty else { return "No memories for today" }
        let total = groups.reduce(0) { $0 + $1.items.count }
        let years = groups.count
        let articleWord = total == 1 ? "article" : "articles"
        let yearWord = years == 1 ? "year" : "years"
        return "\(total) \(articleWord) from \(years) past \(yearWord)"
    }

    // MARK: - Private Helpers

    private func matchesWindow(targetMonth: Int, targetDay: Int,
                                entryMonth: Int, entryDay: Int) -> Bool {
        if windowDays == 0 {
            return entryMonth == targetMonth && entryDay == targetDay
        }
        // For windowed matching, compute day-of-year proximity.
        // Simplified: just check if month/day are within ±windowDays.
        let targetDOY = targetMonth * 31 + targetDay
        let entryDOY = entryMonth * 31 + entryDay
        return abs(targetDOY - entryDOY) <= windowDays
    }

    private func dayKey(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }

    private func dismissedLinks() -> Set<String> {
        let arr = defaults.stringArray(forKey: dismissedKey) ?? []
        return Set(arr)
    }
}
