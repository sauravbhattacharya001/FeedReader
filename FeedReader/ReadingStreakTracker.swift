//
//  ReadingStreakTracker.swift
//  FeedReader
//
//  Tracks daily reading streaks to motivate consistent reading habits.
//  Records each day an article is read, computes current & longest streak,
//  awards milestones (3, 7, 14, 30, 60, 100, 365 days), and provides
//  weekly/monthly activity heatmap data.
//
//  Features:
//  - Automatic streak tracking on article read
//  - Current streak & longest streak with start dates
//  - Milestone achievements with unlock dates
//  - Weekly activity heatmap (articles per day)
//  - Monthly reading stats (total articles, active days, avg per day)
//  - Streak freeze: 1 grace day that doesn't break the streak
//  - Export streak data as JSON or CSV
//  - Streak recovery window: if you missed yesterday, reading today
//    continues the streak (configurable grace period)
//
//  Persistence: JSON file in Documents directory.
//

import Foundation

// MARK: - Notifications

extension Notification.Name {
    /// Posted when the reading streak changes (new day recorded, streak broken, milestone unlocked).
    static let readingStreakDidChange = Notification.Name("ReadingStreakDidChangeNotification")
}

// MARK: - Models

/// A single day's reading activity.
struct DailyReadingRecord: Codable {
    let date: String          // "yyyy-MM-dd"
    var articleCount: Int
    var articleIds: [String]   // IDs/URLs of articles read
    var totalReadingSeconds: Int
}

/// A milestone achievement.
struct StreakMilestone: Codable {
    let days: Int
    let title: String
    let emoji: String
    let unlockedDate: String?  // nil if not yet unlocked
}

/// Summary of current streak status.
struct StreakStatus {
    let currentStreak: Int
    let longestStreak: Int
    let longestStreakStart: String?
    let longestStreakEnd: String?
    let todayArticleCount: Int
    let totalArticlesRead: Int
    let totalActiveDays: Int
    let freezesRemaining: Int
    let milestones: [StreakMilestone]
}

/// Weekly activity for heatmap display.
struct WeeklyActivity {
    let weekStart: String   // "yyyy-MM-dd" (Monday)
    let days: [(date: String, count: Int)]
}

/// Monthly reading summary.
struct MonthlyStats {
    let month: String       // "yyyy-MM"
    let totalArticles: Int
    let activeDays: Int
    let averagePerDay: Double
    let longestStreakInMonth: Int
}

// MARK: - Persistence

/// Root object stored on disk.
struct StreakData: Codable {
    var dailyRecords: [String: DailyReadingRecord]  // keyed by "yyyy-MM-dd"
    var longestStreak: Int
    var longestStreakStart: String?
    var longestStreakEnd: String?
    var freezesUsedDates: [String]      // dates where a freeze was consumed
    var maxFreezesPerMonth: Int
    var milestoneDays: [Int: String]    // milestone day count -> unlock date
    var gracePeriodDays: Int            // how many days you can miss (default 1)
}

// MARK: - ReadingStreakTracker

/// Tracks reading streaks, milestones, and activity patterns.
final class ReadingStreakTracker {

    static let shared = ReadingStreakTracker()

    // MARK: - Configuration

    private static let defaultMilestones: [(days: Int, title: String, emoji: String)] = [
        (3, "Getting Started", "🌱"),
        (7, "One Week Strong", "🔥"),
        (14, "Two Week Warrior", "⚔️"),
        (30, "Monthly Master", "🏆"),
        (60, "Dedicated Reader", "📚"),
        (100, "Century Club", "💯"),
        (365, "Year of Reading", "🎉"),
    ]

    // MARK: - State

    private var data: StreakData
    private let fileURL: URL
    private let calendar: Calendar
    private let dateFormatter: DateFormatter

    // MARK: - Init

    private init() {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        self.fileURL = docs.appendingPathComponent("reading_streaks.json")

        var cal = Calendar(identifier: .gregorian)
        cal.firstWeekday = 2  // Monday
        self.calendar = cal

        let df = DateFormatter()
        df.dateFormat = "yyyy-MM-dd"
        df.locale = Locale(identifier: "en_US_POSIX")
        self.dateFormatter = df

        self.data = StreakData(
            dailyRecords: [:],
            longestStreak: 0,
            longestStreakStart: nil,
            longestStreakEnd: nil,
            freezesUsedDates: [],
            maxFreezesPerMonth: 2,
            milestoneDays: [:],
            gracePeriodDays: 1
        )
        load()
    }

    // MARK: - Public API

    /// Record that an article was read. Call this whenever the user finishes/opens an article.
    func recordArticleRead(articleId: String, readingSeconds: Int = 0) {
        let today = dateFormatter.string(from: Date())

        if var record = data.dailyRecords[today] {
            record.articleCount += 1
            if !record.articleIds.contains(articleId) {
                record.articleIds.append(articleId)
            }
            record.totalReadingSeconds += readingSeconds
            data.dailyRecords[today] = record
        } else {
            data.dailyRecords[today] = DailyReadingRecord(
                date: today,
                articleCount: 1,
                articleIds: [articleId],
                totalReadingSeconds: readingSeconds
            )
        }

        updateStreakAndMilestones()
        save()
        NotificationCenter.default.post(name: .readingStreakDidChange, object: self)
    }

    /// Get current streak status.
    func getStatus() -> StreakStatus {
        let today = dateFormatter.string(from: Date())
        let current = computeCurrentStreak()
        let todayCount = data.dailyRecords[today]?.articleCount ?? 0
        let totalArticles = data.dailyRecords.values.reduce(0) { $0 + $1.articleCount }
        let totalDays = data.dailyRecords.count
        let freezesUsedThisMonth = freezesUsedInCurrentMonth()
        let freezesRemaining = max(0, data.maxFreezesPerMonth - freezesUsedThisMonth)

        let milestones = Self.defaultMilestones.map { m in
            StreakMilestone(
                days: m.days,
                title: m.title,
                emoji: m.emoji,
                unlockedDate: data.milestoneDays[m.days]
            )
        }

        return StreakStatus(
            currentStreak: current,
            longestStreak: data.longestStreak,
            longestStreakStart: data.longestStreakStart,
            longestStreakEnd: data.longestStreakEnd,
            todayArticleCount: todayCount,
            totalArticlesRead: totalArticles,
            totalActiveDays: totalDays,
            freezesRemaining: freezesRemaining,
            milestones: milestones
        )
    }

    /// Use a streak freeze for yesterday (prevents streak from breaking).
    /// Returns true if freeze was successfully applied.
    func useStreakFreeze() -> Bool {
        let yesterday = dateString(daysAgo: 1)

        // Already have a record for yesterday — no freeze needed
        if data.dailyRecords[yesterday] != nil { return false }

        // Check monthly freeze budget
        let usedThisMonth = freezesUsedInCurrentMonth()
        guard usedThisMonth < data.maxFreezesPerMonth else { return false }

        data.freezesUsedDates.append(yesterday)
        // Create a synthetic record so streak computation sees it
        data.dailyRecords[yesterday] = DailyReadingRecord(
            date: yesterday,
            articleCount: 0,
            articleIds: [],
            totalReadingSeconds: 0
        )

        updateStreakAndMilestones()
        save()
        NotificationCenter.default.post(name: .readingStreakDidChange, object: self)
        return true
    }

    /// Get weekly activity data for the last N weeks.
    func getWeeklyActivity(weeks: Int = 12) -> [WeeklyActivity] {
        var result: [WeeklyActivity] = []
        let today = Date()

        for w in 0..<weeks {
            let weekEnd = calendar.date(byAdding: .weekOfYear, value: -w, to: today)!
            let weekStart = calendar.date(from: calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: weekEnd))!

            var days: [(String, Int)] = []
            for d in 0..<7 {
                let day = calendar.date(byAdding: .day, value: d, to: weekStart)!
                let key = dateFormatter.string(from: day)
                let count = data.dailyRecords[key]?.articleCount ?? 0
                days.append((key, count))
            }

            let startStr = dateFormatter.string(from: weekStart)
            result.append(WeeklyActivity(weekStart: startStr, days: days))
        }

        return result.reversed()
    }

    /// Get monthly stats for the last N months.
    func getMonthlyStats(months: Int = 6) -> [MonthlyStats] {
        let today = Date()
        var result: [MonthlyStats] = []
        let monthFormatter = DateFormatter()
        monthFormatter.dateFormat = "yyyy-MM"
        monthFormatter.locale = Locale(identifier: "en_US_POSIX")

        for m in 0..<months {
            guard let monthDate = calendar.date(byAdding: .month, value: -m, to: today) else { continue }
            let monthKey = monthFormatter.string(from: monthDate)

            let records = data.dailyRecords.filter { $0.key.hasPrefix(monthKey) }
            let totalArticles = records.values.reduce(0) { $0 + $1.articleCount }
            let activeDays = records.count
            let daysInMonth = calendar.range(of: .day, in: .month, for: monthDate)?.count ?? 30
            let avg = activeDays > 0 ? Double(totalArticles) / Double(daysInMonth) : 0

            // Compute longest streak within the month
            let sortedDates = records.keys.sorted()
            var longestInMonth = 0
            var currentRun = 0
            var prevDate: Date?
            for dateStr in sortedDates {
                if let d = dateFormatter.date(from: dateStr) {
                    if let prev = prevDate, calendar.dateComponents([.day], from: prev, to: d).day == 1 {
                        currentRun += 1
                    } else {
                        currentRun = 1
                    }
                    longestInMonth = max(longestInMonth, currentRun)
                    prevDate = d
                }
            }

            result.append(MonthlyStats(
                month: monthKey,
                totalArticles: totalArticles,
                activeDays: activeDays,
                averagePerDay: avg,
                longestStreakInMonth: longestInMonth
            ))
        }

        return result.reversed()
    }

    /// Export streak data as JSON string.
    func exportJSON() -> String {
        let status = getStatus()
        let records = data.dailyRecords.values.sorted { $0.date > $1.date }

        var dict: [String: Any] = [
            "currentStreak": status.currentStreak,
            "longestStreak": status.longestStreak,
            "totalArticlesRead": status.totalArticlesRead,
            "totalActiveDays": status.totalActiveDays,
            "freezesRemaining": status.freezesRemaining,
            "milestones": status.milestones.map { [
                "days": $0.days,
                "title": $0.title,
                "emoji": $0.emoji,
                "unlocked": $0.unlockedDate ?? "locked"
            ] as [String: Any] },
            "dailyRecords": records.map { [
                "date": $0.date,
                "articleCount": $0.articleCount,
                "readingSeconds": $0.totalReadingSeconds
            ] as [String: Any] }
        ]
        if let start = status.longestStreakStart { dict["longestStreakStart"] = start }
        if let end = status.longestStreakEnd { dict["longestStreakEnd"] = end }

        guard let jsonData = try? JSONSerialization.data(
            withJSONObject: dict, options: [.prettyPrinted, .sortedKeys]
        ) else { return "{}" }
        return String(data: jsonData, encoding: .utf8) ?? "{}"
    }

    /// Export streak data as CSV string.
    func exportCSV() -> String {
        var lines = ["date,article_count,reading_seconds,article_ids"]
        let records = data.dailyRecords.values.sorted { $0.date > $1.date }
        for r in records {
            let ids = r.articleIds.joined(separator: ";")
            lines.append("\(r.date),\(r.articleCount),\(r.totalReadingSeconds),\"\(ids)\"")
        }
        return lines.joined(separator: "\n")
    }

    /// Configure grace period (default 1 day).
    func setGracePeriod(days: Int) {
        data.gracePeriodDays = max(0, min(days, 3))
        save()
    }

    /// Configure monthly freeze budget.
    func setMaxFreezesPerMonth(_ count: Int) {
        data.maxFreezesPerMonth = max(0, min(count, 10))
        save()
    }

    /// Reset all streak data.
    func reset() {
        data = StreakData(
            dailyRecords: [:],
            longestStreak: 0,
            longestStreakStart: nil,
            longestStreakEnd: nil,
            freezesUsedDates: [],
            maxFreezesPerMonth: data.maxFreezesPerMonth,
            milestoneDays: [:],
            gracePeriodDays: data.gracePeriodDays
        )
        save()
        NotificationCenter.default.post(name: .readingStreakDidChange, object: self)
    }

    // MARK: - Private Helpers

    private func computeCurrentStreak() -> Int {
        let today = Date()
        var streak = 0
        var gapsUsed = 0
        let maxGaps = data.gracePeriodDays

        // Start from today and walk backwards
        var checkDate = today

        // If today has no record, start from yesterday
        let todayStr = dateFormatter.string(from: today)
        if data.dailyRecords[todayStr] == nil {
            guard let yesterday = calendar.date(byAdding: .day, value: -1, to: today) else { return 0 }
            let yesterdayStr = dateFormatter.string(from: yesterday)
            if data.dailyRecords[yesterdayStr] == nil { return 0 }
            checkDate = yesterday
        }

        while true {
            let key = dateFormatter.string(from: checkDate)
            if data.dailyRecords[key] != nil {
                streak += 1
            } else if gapsUsed < maxGaps {
                gapsUsed += 1
                // Don't count the gap day itself
            } else {
                break
            }
            guard let prev = calendar.date(byAdding: .day, value: -1, to: checkDate) else { break }
            checkDate = prev
        }

        return streak
    }

    private func updateStreakAndMilestones() {
        let current = computeCurrentStreak()

        // Update longest streak
        if current > data.longestStreak {
            data.longestStreak = current
            let today = Date()
            data.longestStreakEnd = dateFormatter.string(from: today)
            if let start = calendar.date(byAdding: .day, value: -(current - 1), to: today) {
                data.longestStreakStart = dateFormatter.string(from: start)
            }
        }

        // Check milestones
        for milestone in Self.defaultMilestones {
            if current >= milestone.days && data.milestoneDays[milestone.days] == nil {
                data.milestoneDays[milestone.days] = dateFormatter.string(from: Date())
            }
        }
    }

    private func freezesUsedInCurrentMonth() -> Int {
        let monthFormatter = DateFormatter()
        monthFormatter.dateFormat = "yyyy-MM"
        monthFormatter.locale = Locale(identifier: "en_US_POSIX")
        let currentMonth = monthFormatter.string(from: Date())
        return data.freezesUsedDates.filter { $0.hasPrefix(currentMonth) }.count
    }

    private func dateString(daysAgo: Int) -> String {
        let date = calendar.date(byAdding: .day, value: -daysAgo, to: Date())!
        return dateFormatter.string(from: date)
    }

    // MARK: - Persistence

    private func save() {
        guard let jsonData = try? JSONEncoder().encode(data) else { return }
        try? jsonData.write(to: fileURL, options: .atomic)
    }

    private func load() {
        guard let jsonData = try? Data(contentsOf: fileURL),
              let loaded = try? JSONDecoder().decode(StreakData.self, from: jsonData)
        else { return }
        data = loaded
    }
}
