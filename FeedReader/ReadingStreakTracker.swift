//
//  ReadingStreakTracker.swift
//  FeedReader
//
//  Tracks consecutive-day reading streaks. Maintains current streak,
//  longest streak, and per-day reading counts. Integrates with
//  ReadingGoalsManager for goal-based streaks and ReadingHistoryManager
//  for automatic recording.
//
//  Persistence: UserDefaults via NSSecureCoding-compatible Codable models.
//

import Foundation

// MARK: - Notifications

extension Notification.Name {
    /// Posted when streak data changes (new day logged, streak broken, reset).
    static let readingStreakDidChange = Notification.Name("ReadingStreakDidChangeNotification")
    /// Posted when the user hits a streak milestone (7, 14, 30, 50, 100, 365 days).
    static let readingStreakMilestone = Notification.Name("ReadingStreakMilestoneNotification")
}

// MARK: - Models

/// Record of articles read on a single calendar day.
struct DailyReadingRecord: Codable, Equatable {
    /// Calendar date as "yyyy-MM-dd".
    let date: String
    /// Number of articles read that day.
    var articlesRead: Int
    /// Whether the daily goal was met (if a goal was set).
    var goalMet: Bool

    init(date: String, articlesRead: Int = 0, goalMet: Bool = false) {
        self.date = date
        self.articlesRead = articlesRead
        self.goalMet = goalMet
    }
}

/// Snapshot of streak statistics.
struct StreakStats: Equatable {
    /// Current consecutive days with at least one article read.
    let currentStreak: Int
    /// Longest consecutive streak ever recorded.
    let longestStreak: Int
    /// Total number of distinct days with reading activity.
    let totalActiveDays: Int
    /// Total articles read across all tracked days.
    let totalArticlesRead: Int
    /// Average articles per active day.
    let averagePerDay: Double
    /// Whether the user has read today.
    let readToday: Bool
    /// Days since last reading activity (0 if read today).
    let daysSinceLastRead: Int
    /// Current streak is the longest ever.
    let isPersonalBest: Bool
    /// Next milestone to reach (7, 14, 30, 50, 100, 365).
    let nextMilestone: Int?
    /// Days remaining until next milestone.
    let daysToNextMilestone: Int?
}

/// Weekly summary for display.
struct WeekSummary: Equatable {
    /// Start date of the week (Monday) as "yyyy-MM-dd".
    let weekStart: String
    /// Number of days with reading activity (0–7).
    let activeDays: Int
    /// Total articles read that week.
    let totalArticles: Int
    /// Whether every day had at least one article.
    let perfectWeek: Bool
}

// MARK: - ReadingStreakTracker

class ReadingStreakTracker {

    // MARK: - Singleton

    static let shared = ReadingStreakTracker()

    // MARK: - Constants

    private static let storageKey = "ReadingStreakTracker.records"
    private static let milestones = [7, 14, 30, 50, 100, 365]
    /// Keep at most 400 daily records (~13 months of history).
    private static let maxRecords = 400

    // MARK: - Properties

    /// Daily records keyed by date string for O(1) lookup.
    private var records: [String: DailyReadingRecord] = [:]

    /// Calendar used for date calculations (Gregorian, user's timezone).
    private let calendar: Calendar

    /// Persistence via the shared UserDefaultsCodableStore helper,
    /// replacing hand-rolled JSONEncoder/JSONDecoder boilerplate.
    private let store: UserDefaultsCodableStore<[DailyReadingRecord]>

    // MARK: - Initializer

    init(defaults: UserDefaults = .standard, calendar: Calendar? = nil) {
        var cal = calendar ?? Calendar(identifier: .gregorian)
        cal.firstWeekday = 2 // Monday
        self.calendar = cal
        self.store = UserDefaultsCodableStore<[DailyReadingRecord]>(
            key: ReadingStreakTracker.storageKey,
            dateStrategy: .deferredToDate,
            defaults: defaults
        )
        let fmt = DateFormatter()
        fmt.dateFormat = "yyyy-MM-dd"
        fmt.locale = Locale(identifier: "en_US_POSIX")
        fmt.calendar = cal
        self.iso8601DayFormatter = fmt
        loadRecords()
    }

    // MARK: - Public API

    /// Record that an article was read. Call this each time a user reads
    /// an article. Increments today's count and updates streak state.
    ///
    /// - Parameter goalTarget: Optional daily goal target. If the day's
    ///   count reaches this value, `goalMet` is set to true.
    /// - Returns: The updated stats snapshot.
    @discardableResult
    func recordArticleRead(goalTarget: Int = 0) -> StreakStats {
        let today = dateKey(for: Date())
        var record = records[today] ?? DailyReadingRecord(date: today)
        record.articlesRead += 1
        if goalTarget > 0 && record.articlesRead >= goalTarget {
            record.goalMet = true
        }
        records[today] = record
        saveRecords()

        let stats = computeStats()
        NotificationCenter.default.post(name: .readingStreakDidChange, object: nil)
        checkMilestone(stats: stats)
        return stats
    }

    /// Record multiple articles at once (e.g., batch import).
    @discardableResult
    func recordArticles(count: Int, goalTarget: Int = 0) -> StreakStats {
        guard count > 0 else { return computeStats() }
        let today = dateKey(for: Date())
        var record = records[today] ?? DailyReadingRecord(date: today)
        record.articlesRead += count
        if goalTarget > 0 && record.articlesRead >= goalTarget {
            record.goalMet = true
        }
        records[today] = record
        saveRecords()

        let stats = computeStats()
        NotificationCenter.default.post(name: .readingStreakDidChange, object: nil)
        checkMilestone(stats: stats)
        return stats
    }

    /// Get a snapshot of current streak statistics.
    func getStats() -> StreakStats {
        return computeStats()
    }

    /// Get the daily record for a specific date, if any.
    func record(for date: Date) -> DailyReadingRecord? {
        return records[dateKey(for: date)]
    }

    /// Get records for a date range (inclusive).
    ///
    /// Filters the records dictionary directly instead of iterating
    /// day-by-day through the range. For sparse data over long ranges
    /// (e.g., 365-day queries with 30 active days), this avoids
    /// creating ~335 unnecessary Date objects and string conversions.
    func records(from startDate: Date, to endDate: Date) -> [DailyReadingRecord] {
        let startKey = dateKey(for: calendar.startOfDay(for: startDate))
        let endKey = dateKey(for: calendar.startOfDay(for: endDate))
        return records.values
            .filter { $0.date >= startKey && $0.date <= endKey }
            .sorted { $0.date < $1.date }
    }

    /// Get weekly summaries for the last N weeks.
    func weeklySummaries(weeks: Int = 4) -> [WeekSummary] {
        guard weeks > 0 else { return [] }
        var summaries: [WeekSummary] = []
        let today = calendar.startOfDay(for: Date())

        for i in 0..<weeks {
            guard let weekEnd = calendar.date(byAdding: .weekOfYear, value: -i, to: today),
                  let weekStart = calendar.date(from: mondayComponents(for: weekEnd)) else {
                continue
            }
            var activeDays = 0
            var totalArticles = 0
            for d in 0..<7 {
                guard let day = calendar.date(byAdding: .day, value: d, to: weekStart) else { continue }
                // Don't count future days
                if day > today { continue }
                let key = dateKey(for: day)
                if let rec = records[key], rec.articlesRead > 0 {
                    activeDays += 1
                    totalArticles += rec.articlesRead
                }
            }
            // A "perfect week" only counts if all 7 days have passed (or it's the current week and all past days are active)
            let daysInScope = min(7, daysBetween(weekStart, today) + 1)
            let perfectWeek = activeDays >= daysInScope && daysInScope == 7

            summaries.append(WeekSummary(
                weekStart: dateKey(for: weekStart),
                activeDays: activeDays,
                totalArticles: totalArticles,
                perfectWeek: perfectWeek
            ))
        }
        return summaries
    }

    /// Whether the streak is at risk (read yesterday but not yet today).
    var isStreakAtRisk: Bool {
        let today = dateKey(for: Date())
        if records[today] != nil { return false }
        guard let yesterday = calendar.date(byAdding: .day, value: -1, to: Date()) else { return false }
        return records[dateKey(for: yesterday)] != nil
    }

    /// Days on which the daily goal was met in the last N days.
    func goalStreakDays(last days: Int = 30) -> Int {
        let today = calendar.startOfDay(for: Date())
        var count = 0
        for i in 0..<days {
            guard let day = calendar.date(byAdding: .day, value: -i, to: today) else { continue }
            if let rec = records[dateKey(for: day)], rec.goalMet {
                count += 1
            }
        }
        return count
    }

    /// Reset all streak data.
    func resetAll() {
        records.removeAll()
        saveRecords()
        NotificationCenter.default.post(name: .readingStreakDidChange, object: nil)
    }

    /// Total number of tracked days.
    var trackedDaysCount: Int {
        return records.count
    }

    // MARK: - Private: Stats Computation

    private func computeStats() -> StreakStats {
        let today = calendar.startOfDay(for: Date())
        let todayKey = dateKey(for: today)

        // Sort all record dates (only active days — those with articlesRead > 0)
        let sortedDates = records.filter { $0.value.articlesRead > 0 }.keys.sorted()
        guard !sortedDates.isEmpty else {
            return StreakStats(
                currentStreak: 0, longestStreak: 0,
                totalActiveDays: 0, totalArticlesRead: 0,
                averagePerDay: 0, readToday: false,
                daysSinceLastRead: 0, isPersonalBest: false,
                nextMilestone: ReadingStreakTracker.milestones.first,
                daysToNextMilestone: ReadingStreakTracker.milestones.first
            )
        }

        let readToday = records[todayKey] != nil && (records[todayKey]?.articlesRead ?? 0) > 0
        let totalArticles = records.values.reduce(0) { $0 + $1.articlesRead }
        let activeDays = records.values.filter { $0.articlesRead > 0 }.count
        let average = activeDays > 0 ? Double(totalArticles) / Double(activeDays) : 0

        // Current streak: count backwards from today (or yesterday if not read today)
        var currentStreak = 0
        var checkDate = today
        if !readToday {
            // If haven't read today, streak might still be alive from yesterday
            guard let yesterday = calendar.date(byAdding: .day, value: -1, to: today) else {
                return makeStats(current: 0, longest: 0, activeDays: activeDays,
                                 totalArticles: totalArticles, average: average,
                                 readToday: false, sortedDates: sortedDates, today: today)
            }
            checkDate = yesterday
        }

        while true {
            let key = dateKey(for: checkDate)
            guard let rec = records[key], rec.articlesRead > 0 else { break }
            currentStreak += 1
            guard let prev = calendar.date(byAdding: .day, value: -1, to: checkDate) else { break }
            checkDate = prev
        }

        // Longest streak: scan all sorted dates
        var longestStreak = 0
        var runLength = 1
        for i in 1..<sortedDates.count {
            let prevDate = parseDate(sortedDates[i - 1])
            let currDate = parseDate(sortedDates[i])
            if let p = prevDate, let c = currDate, daysBetween(p, c) == 1 {
                runLength += 1
            } else {
                longestStreak = max(longestStreak, runLength)
                runLength = 1
            }
        }
        longestStreak = max(longestStreak, runLength)

        return makeStats(current: currentStreak, longest: longestStreak,
                         activeDays: activeDays, totalArticles: totalArticles,
                         average: average, readToday: readToday,
                         sortedDates: sortedDates, today: today)
    }

    private func makeStats(current: Int, longest: Int, activeDays: Int,
                           totalArticles: Int, average: Double,
                           readToday: Bool, sortedDates: [String],
                           today: Date) -> StreakStats {
        let longestFinal = max(longest, current)
        let isPersonalBest = current > 0 && current >= longestFinal

        // Days since last read
        var daysSinceLastRead = 0
        if let lastDateStr = sortedDates.last, let lastDate = parseDate(lastDateStr) {
            daysSinceLastRead = daysBetween(lastDate, today)
        }

        // Next milestone
        var nextMilestone: Int? = nil
        var daysToNext: Int? = nil
        for m in ReadingStreakTracker.milestones {
            if current < m {
                nextMilestone = m
                daysToNext = m - current
                break
            }
        }

        return StreakStats(
            currentStreak: current,
            longestStreak: longestFinal,
            totalActiveDays: activeDays,
            totalArticlesRead: totalArticles,
            averagePerDay: average,
            readToday: readToday,
            daysSinceLastRead: daysSinceLastRead,
            isPersonalBest: isPersonalBest,
            nextMilestone: nextMilestone,
            daysToNextMilestone: daysToNext
        )
    }

    // MARK: - Private: Milestone Check

    private func checkMilestone(stats: StreakStats) {
        for m in ReadingStreakTracker.milestones {
            if stats.currentStreak == m {
                NotificationCenter.default.post(
                    name: .readingStreakMilestone,
                    object: nil,
                    userInfo: ["milestone": m, "streak": stats.currentStreak]
                )
                break
            }
        }
    }

    // MARK: - Private: Date Helpers

    /// Reusable date formatter — DateFormatter is expensive to create and
    /// was previously allocated on every dateKey() / parseDate() call.
    /// computeStats() calls these in tight loops making the overhead
    /// significant (DateFormatter init involves locale + ICU setup).
    /// Thread-safe date formatter — initialized once in init() rather
    /// than using lazy var (which is not atomic in Swift and would be
    /// a race condition on the shared singleton). DateFormatter itself
    /// is also not thread-safe, but since ReadingStreakTracker's public
    /// methods are only called from the main thread, a single instance
    /// is safe. Fixes #21.
    private let iso8601DayFormatter: DateFormatter

    private func dateKey(for date: Date) -> String {
        return iso8601DayFormatter.string(from: date)
    }

    private func parseDate(_ key: String) -> Date? {
        return iso8601DayFormatter.date(from: key)
    }

    private func daysBetween(_ from: Date, _ to: Date) -> Int {
        let fromDay = calendar.startOfDay(for: from)
        let toDay = calendar.startOfDay(for: to)
        return calendar.dateComponents([.day], from: fromDay, to: toDay).day ?? 0
    }

    private func mondayComponents(for date: Date) -> DateComponents {
        let weekday = calendar.component(.weekday, from: date)
        // Calculate days since Monday (weekday 2 in Gregorian)
        let daysSinceMonday = (weekday + 5) % 7
        let monday = calendar.date(byAdding: .day, value: -daysSinceMonday, to: date)!
        return calendar.dateComponents([.year, .month, .day], from: monday)
    }

    // MARK: - Private: Persistence

    private func saveRecords() {
        // Trim to max records (keep most recent)
        var allRecords = Array(records.values)
        if allRecords.count > ReadingStreakTracker.maxRecords {
            allRecords.sort { $0.date > $1.date }
            allRecords = Array(allRecords.prefix(ReadingStreakTracker.maxRecords))
            records = Dictionary(uniqueKeysWithValues: allRecords.map { ($0.date, $0) })
        }

        store.save(Array(records.values))
    }

    private func loadRecords() {
        guard let loaded = store.load() else { return }
        records = Dictionary(uniqueKeysWithValues: loaded.map { ($0.date, $0) })
    }
}
