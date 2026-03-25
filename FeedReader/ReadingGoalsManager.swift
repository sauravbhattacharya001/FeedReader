//
//  ReadingGoalsManager.swift
//  FeedReader
//
//  Lets users set daily and weekly reading goals (number of articles)
//  and tracks progress against those goals. Provides stats on goal
//  completion rates, best days, and motivational nudges.
//
//  Features:
//  - Set daily article goal (e.g. "read 5 articles per day")
//  - Set weekly article goal (e.g. "read 25 articles per week")
//  - Track progress for current day and current week
//  - Historical goal completion rate (last 7, 30, 90 days)
//  - Best day/week records
//  - Goal adjustment suggestions based on actual reading patterns
//  - Export goal history as JSON
//
//  Persistence: JSON file in Documents directory.
//  Integrates with ReadingStreakTracker for article-read events.
//

import Foundation

// MARK: - Notifications

extension Notification.Name {
    /// Posted when reading goal progress changes or a goal is met.
    static let readingGoalProgressDidChange = Notification.Name("ReadingGoalProgressDidChangeNotification")
    /// Posted when a daily or weekly goal is completed.
    static let readingGoalCompleted = Notification.Name("ReadingGoalCompletedNotification")
}

// MARK: - Models

/// The user's configured reading goals.
struct ReadingGoals: Codable {
    var dailyArticleTarget: Int      // 0 = no daily goal
    var weeklyArticleTarget: Int     // 0 = no weekly goal
    var dailyMinutesTarget: Int      // 0 = no time-based daily goal
    var weeklyMinutesTarget: Int     // 0 = no time-based weekly goal
}

/// A single day's progress toward goals.
struct DailyGoalProgress: Codable {
    let date: String                 // "yyyy-MM-dd"
    var articlesRead: Int
    var minutesRead: Int
    var dailyArticleGoalMet: Bool
    var dailyMinutesGoalMet: Bool
}

/// A week's progress toward goals.
struct WeeklyGoalSummary: Codable {
    let weekStartDate: String        // "yyyy-MM-dd" (Monday)
    var totalArticles: Int
    var totalMinutes: Int
    var daysActive: Int
    var weeklyArticleGoalMet: Bool
    var weeklyMinutesGoalMet: Bool
}

/// Overall goal statistics.
struct GoalStatistics: Codable {
    var currentDayProgress: DailyGoalProgress?
    var currentWeekSummary: WeeklyGoalSummary?
    var bestDayArticles: Int
    var bestDayDate: String?
    var bestWeekArticles: Int
    var bestWeekDate: String?
    var totalGoalDaysMet: Int
    var totalGoalDaysTracked: Int
    var totalGoalWeeksMet: Int
    var totalGoalWeeksTracked: Int
}

/// Persisted state.
private struct GoalStore: Codable {
    var goals: ReadingGoals
    var dailyProgress: [DailyGoalProgress]
    var weeklySummaries: [WeeklyGoalSummary]
}

// MARK: - ReadingGoalsManager

class ReadingGoalsManager {

    // MARK: - Singleton

    static let shared = ReadingGoalsManager()

    // MARK: - Properties

    private var store: GoalStore
    private let fileURL: URL

    private let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone.current
        return f
    }()

    private let calendar: Calendar = {
        var c = Calendar(identifier: .iso8601)
        c.firstWeekday = 2  // Monday
        return c
    }()

    // MARK: - Init

    private init() {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        fileURL = docs.appendingPathComponent("reading_goals.json")
        store = GoalStore(
            goals: ReadingGoals(dailyArticleTarget: 5, weeklyArticleTarget: 25,
                                dailyMinutesTarget: 0, weeklyMinutesTarget: 0),
            dailyProgress: [],
            weeklySummaries: []
        )
        load()
    }

    // MARK: - Public API – Goals

    /// The current reading goals.
    var goals: ReadingGoals {
        return store.goals
    }

    /// Update the reading goals.
    func setGoals(dailyArticles: Int? = nil, weeklyArticles: Int? = nil,
                  dailyMinutes: Int? = nil, weeklyMinutes: Int? = nil) {
        if let d = dailyArticles { store.goals.dailyArticleTarget = max(0, d) }
        if let w = weeklyArticles { store.goals.weeklyArticleTarget = max(0, w) }
        if let dm = dailyMinutes { store.goals.dailyMinutesTarget = max(0, dm) }
        if let wm = weeklyMinutes { store.goals.weeklyMinutesTarget = max(0, wm) }
        save()
    }

    // MARK: - Public API – Record Reading

    /// Record that an article was read. Call this when a user finishes reading.
    /// - Parameters:
    ///   - articleId: Unique identifier for the article.
    ///   - minutesSpent: Approximate reading time in minutes (0 if unknown).
    func recordArticleRead(articleId: String, minutesSpent: Int = 0) {
        let today = dateFormatter.string(from: Date())

        // Update daily progress
        var daily = todayProgress() ?? DailyGoalProgress(
            date: today, articlesRead: 0, minutesRead: 0,
            dailyArticleGoalMet: false, dailyMinutesGoalMet: false
        )
        daily.articlesRead += 1
        daily.minutesRead += minutesSpent

        // Check daily goals
        if store.goals.dailyArticleTarget > 0 {
            daily.dailyArticleGoalMet = daily.articlesRead >= store.goals.dailyArticleTarget
        }
        if store.goals.dailyMinutesTarget > 0 {
            daily.dailyMinutesGoalMet = daily.minutesRead >= store.goals.dailyMinutesTarget
        }

        // Upsert
        if let idx = store.dailyProgress.firstIndex(where: { $0.date == today }) {
            let wasMetBefore = store.dailyProgress[idx].dailyArticleGoalMet
            store.dailyProgress[idx] = daily
            if daily.dailyArticleGoalMet && !wasMetBefore {
                NotificationCenter.default.post(name: .readingGoalCompleted,
                                                object: self, userInfo: ["type": "daily"])
            }
        } else {
            store.dailyProgress.append(daily)
            if daily.dailyArticleGoalMet {
                NotificationCenter.default.post(name: .readingGoalCompleted,
                                                object: self, userInfo: ["type": "daily"])
            }
        }

        // Update weekly summary
        updateCurrentWeekSummary()

        save()
        NotificationCenter.default.post(name: .readingGoalProgressDidChange, object: self)
    }

    // MARK: - Public API – Progress

    /// Get today's progress.
    func todayProgress() -> DailyGoalProgress? {
        let today = dateFormatter.string(from: Date())
        return store.dailyProgress.first(where: { $0.date == today })
    }

    /// Get the current week's summary.
    func currentWeekSummary() -> WeeklyGoalSummary {
        let weekStart = mondayOfCurrentWeek()
        return buildWeekSummary(weekStart: weekStart)
    }

    /// Daily goal completion rate for the last N days.
    func dailyCompletionRate(lastDays: Int = 30) -> Double {
        guard store.goals.dailyArticleTarget > 0 else { return 0 }
        let cutoff = calendar.date(byAdding: .day, value: -lastDays, to: Date())!
        let cutoffStr = dateFormatter.string(from: cutoff)
        let recent = store.dailyProgress.filter { $0.date >= cutoffStr }
        guard !recent.isEmpty else { return 0 }
        let met = recent.filter { $0.dailyArticleGoalMet }.count
        return Double(met) / Double(recent.count)
    }

    /// Full statistics overview.
    func statistics() -> GoalStatistics {
        let today = todayProgress()
        let week = currentWeekSummary()

        // Best day
        let bestDay = store.dailyProgress.max(by: { $0.articlesRead < $1.articlesRead })
        // Best week
        let bestWeek = store.weeklySummaries.max(by: { $0.totalArticles < $1.totalArticles })

        let daysMetCount = store.dailyProgress.filter { $0.dailyArticleGoalMet }.count
        let weeksMetCount = store.weeklySummaries.filter { $0.weeklyArticleGoalMet }.count

        return GoalStatistics(
            currentDayProgress: today,
            currentWeekSummary: week,
            bestDayArticles: bestDay?.articlesRead ?? 0,
            bestDayDate: bestDay?.date,
            bestWeekArticles: bestWeek?.totalArticles ?? 0,
            bestWeekDate: bestWeek?.weekStartDate,
            totalGoalDaysMet: daysMetCount,
            totalGoalDaysTracked: store.dailyProgress.count,
            totalGoalWeeksMet: weeksMetCount,
            totalGoalWeeksTracked: store.weeklySummaries.count
        )
    }

    /// Suggest a goal adjustment based on recent reading patterns.
    func suggestedDailyGoal(basedOnLast days: Int = 14) -> Int {
        let cutoff = calendar.date(byAdding: .day, value: -days, to: Date())!
        let cutoffStr = dateFormatter.string(from: cutoff)
        let recent = store.dailyProgress.filter { $0.date >= cutoffStr }
        guard !recent.isEmpty else { return store.goals.dailyArticleTarget }
        let avg = Double(recent.map { $0.articlesRead }.reduce(0, +)) / Double(recent.count)
        // Suggest ~20% above current average, rounded up
        return max(1, Int(ceil(avg * 1.2)))
    }

    // MARK: - Public API – Export

    /// Export goal history as JSON data.
    func exportJSON() -> Data? {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try? encoder.encode(store)
    }

    /// Reset all goal progress (keeps the goal targets).
    func resetProgress() {
        store.dailyProgress.removeAll()
        store.weeklySummaries.removeAll()
        save()
        NotificationCenter.default.post(name: .readingGoalProgressDidChange, object: self)
    }

    // MARK: - Private

    private func mondayOfCurrentWeek() -> String {
        let comps = calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: Date())
        let monday = calendar.date(from: comps)!
        return dateFormatter.string(from: monday)
    }

    private func buildWeekSummary(weekStart: String) -> WeeklyGoalSummary {
        guard let startDate = dateFormatter.date(from: weekStart) else {
            return WeeklyGoalSummary(weekStartDate: weekStart, totalArticles: 0,
                                     totalMinutes: 0, daysActive: 0,
                                     weeklyArticleGoalMet: false, weeklyMinutesGoalMet: false)
        }
        let endDate = calendar.date(byAdding: .day, value: 7, to: startDate)!
        let endStr = dateFormatter.string(from: endDate)

        let daysInWeek = store.dailyProgress.filter { $0.date >= weekStart && $0.date < endStr }
        let totalArticles = daysInWeek.map { $0.articlesRead }.reduce(0, +)
        let totalMinutes = daysInWeek.map { $0.minutesRead }.reduce(0, +)
        let daysActive = daysInWeek.filter { $0.articlesRead > 0 }.count

        var articleGoalMet = false
        if store.goals.weeklyArticleTarget > 0 {
            articleGoalMet = totalArticles >= store.goals.weeklyArticleTarget
        }
        var minutesGoalMet = false
        if store.goals.weeklyMinutesTarget > 0 {
            minutesGoalMet = totalMinutes >= store.goals.weeklyMinutesTarget
        }

        return WeeklyGoalSummary(
            weekStartDate: weekStart, totalArticles: totalArticles,
            totalMinutes: totalMinutes, daysActive: daysActive,
            weeklyArticleGoalMet: articleGoalMet, weeklyMinutesGoalMet: minutesGoalMet
        )
    }

    private func updateCurrentWeekSummary() {
        let weekStart = mondayOfCurrentWeek()
        let summary = buildWeekSummary(weekStart: weekStart)

        if let idx = store.weeklySummaries.firstIndex(where: { $0.weekStartDate == weekStart }) {
            let wasMet = store.weeklySummaries[idx].weeklyArticleGoalMet
            store.weeklySummaries[idx] = summary
            if summary.weeklyArticleGoalMet && !wasMet {
                NotificationCenter.default.post(name: .readingGoalCompleted,
                                                object: self, userInfo: ["type": "weekly"])
            }
        } else {
            store.weeklySummaries.append(summary)
            if summary.weeklyArticleGoalMet {
                NotificationCenter.default.post(name: .readingGoalCompleted,
                                                object: self, userInfo: ["type": "weekly"])
            }
        }
    }

    private func load() {
        guard FileManager.default.fileExists(atPath: fileURL.path),
              let data = try? Data(contentsOf: fileURL),
              let decoded = try? JSONDecoder().decode(GoalStore.self, from: data) else { return }
        store = decoded
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(store) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }
}
