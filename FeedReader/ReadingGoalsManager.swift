//
//  ReadingGoalsManager.swift
//  FeedReader
//
//  Allows users to set daily and weekly reading goals,
//  tracks progress against them, and posts notifications
//  when goals are achieved.
//

import Foundation

/// Notification posted when reading goals or progress change.
extension Notification.Name {
    static let readingGoalsDidChange = Notification.Name("ReadingGoalsDidChangeNotification")
    static let readingGoalAchieved = Notification.Name("ReadingGoalAchievedNotification")
}

class ReadingGoalsManager {
    
    // MARK: - Singleton
    
    static let shared = ReadingGoalsManager()
    
    // MARK: - Types
    
    /// User-configurable reading goals.
    struct ReadingGoals: Codable, Equatable {
        /// Target number of stories to read per day. 0 = no goal.
        var dailyTarget: Int
        /// Target number of stories to read per week. 0 = no goal.
        var weeklyTarget: Int
        
        static let `default` = ReadingGoals(dailyTarget: 0, weeklyTarget: 0)
    }
    
    /// Current progress toward goals.
    struct GoalProgress {
        let dailyTarget: Int
        let dailyRead: Int
        let dailyPercentage: Double
        let dailyAchieved: Bool
        
        let weeklyTarget: Int
        let weeklyRead: Int
        let weeklyPercentage: Double
        let weeklyAchieved: Bool
        
        /// Whether any goal is set (target > 0).
        var hasGoals: Bool {
            return dailyTarget > 0 || weeklyTarget > 0
        }
    }
    
    // MARK: - Properties
    
    /// Current reading goals.
    private(set) var goals: ReadingGoals {
        didSet {
            saveGoals()
            NotificationCenter.default.post(name: .readingGoalsDidChange, object: nil)
        }
    }
    
    /// Tracks which goals were already achieved today to avoid duplicate notifications.
    private var achievedToday: Set<String> = []
    private var achievedThisWeek: Set<String> = []
    
    private static let goalsKey = "ReadingGoalsManager.goals"
    private static let achievedTodayKey = "ReadingGoalsManager.achievedToday"
    private static let achievedThisWeekKey = "ReadingGoalsManager.achievedThisWeek"
    private static let achievedDateKey = "ReadingGoalsManager.achievedDate"
    private static let achievedWeekKey = "ReadingGoalsManager.achievedWeek"

    /// Persistence store for goals.
    private let goalsStore = UserDefaultsCodableStore<ReadingGoals>(
        key: ReadingGoalsManager.goalsKey,
        dateStrategy: .deferredToDate
    )
    
    // MARK: - Initialization
    
    private init() {
        goals = ReadingGoals.default
        loadGoals()
        loadAchievements()
        
        // Listen for new reads to check goal progress
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(statsDidChange),
            name: .readingStatsDidChange,
            object: nil
        )
    }
    
    deinit {
        NotificationCenter.default.removeObserver(self)
    }
    
    // MARK: - Public Methods
    
    /// Update the daily reading goal.
    /// - Parameter target: Number of stories per day (0 to disable).
    func setDailyGoal(_ target: Int) {
        goals.dailyTarget = max(0, target)
        resetDailyAchievement()
    }
    
    /// Update the weekly reading goal.
    /// - Parameter target: Number of stories per week (0 to disable).
    func setWeeklyGoal(_ target: Int) {
        goals.weeklyTarget = max(0, target)
        resetWeeklyAchievement()
    }
    
    /// Compute current progress toward all goals.
    func currentProgress() -> GoalProgress {
        let stats = ReadingStatsManager.shared.computeStats()
        
        let dailyPct = goals.dailyTarget > 0
            ? min(Double(stats.readToday) / Double(goals.dailyTarget) * 100.0, 100.0)
            : 0.0
        let weeklyPct = goals.weeklyTarget > 0
            ? min(Double(stats.readThisWeek) / Double(goals.weeklyTarget) * 100.0, 100.0)
            : 0.0
        
        return GoalProgress(
            dailyTarget: goals.dailyTarget,
            dailyRead: stats.readToday,
            dailyPercentage: dailyPct,
            dailyAchieved: goals.dailyTarget > 0 && stats.readToday >= goals.dailyTarget,
            weeklyTarget: goals.weeklyTarget,
            weeklyRead: stats.readThisWeek,
            weeklyPercentage: weeklyPct,
            weeklyAchieved: goals.weeklyTarget > 0 && stats.readThisWeek >= goals.weeklyTarget
        )
    }
    
    /// Clear all goals (set to 0).
    func clearGoals() {
        goals = .default
        achievedToday.removeAll()
        achievedThisWeek.removeAll()
        saveAchievements()
    }
    
    /// Force reload from storage (useful for testing).
    func reload() {
        loadGoals()
        loadAchievements()
    }
    
    // MARK: - Private Methods
    
    @objc private func statsDidChange() {
        checkAndNotifyGoals()
    }
    
    /// Check if any goals were just achieved and post notifications.
    private func checkAndNotifyGoals() {
        resetAchievementsIfNewPeriod()
        let progress = currentProgress()
        
        if progress.dailyAchieved && !achievedToday.contains("daily") {
            achievedToday.insert("daily")
            saveAchievements()
            NotificationCenter.default.post(
                name: .readingGoalAchieved,
                object: nil,
                userInfo: ["goalType": "daily", "target": progress.dailyTarget, "read": progress.dailyRead]
            )
        }
        
        if progress.weeklyAchieved && !achievedThisWeek.contains("weekly") {
            achievedThisWeek.insert("weekly")
            saveAchievements()
            NotificationCenter.default.post(
                name: .readingGoalAchieved,
                object: nil,
                userInfo: ["goalType": "weekly", "target": progress.weeklyTarget, "read": progress.weeklyRead]
            )
        }
    }
    
    /// Reset daily achievement tracking if the date has changed.
    private func resetAchievementsIfNewPeriod() {
        let today = dateString(Date())
        let storedDate = UserDefaults.standard.string(forKey: ReadingGoalsManager.achievedDateKey) ?? ""
        if today != storedDate {
            achievedToday.removeAll()
            UserDefaults.standard.set(today, forKey: ReadingGoalsManager.achievedDateKey)
        }
        
        let thisWeek = weekString(Date())
        let storedWeek = UserDefaults.standard.string(forKey: ReadingGoalsManager.achievedWeekKey) ?? ""
        if thisWeek != storedWeek {
            achievedThisWeek.removeAll()
            UserDefaults.standard.set(thisWeek, forKey: ReadingGoalsManager.achievedWeekKey)
        }
    }
    
    private func resetDailyAchievement() {
        achievedToday.remove("daily")
        saveAchievements()
    }
    
    private func resetWeeklyAchievement() {
        achievedThisWeek.remove("weekly")
        saveAchievements()
    }
    
    // MARK: - Helpers
    
    private static let iso8601DayFormatter = DateFormatting.isoDate

    private func dateString(_ date: Date) -> String {
        return Self.iso8601DayFormatter.string(from: date)
    }
    
    private func weekString(_ date: Date) -> String {
        let calendar = Calendar.current
        let components = calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: date)
        return "\(components.yearForWeekOfYear ?? 0)-W\(components.weekOfYear ?? 0)"
    }
    
    // MARK: - Persistence
    
    private func saveGoals() {
        goalsStore.save(goals)
    }
    
    private func loadGoals() {
        guard let loaded = goalsStore.load() else {
            goals = .default
            return
        }
        goals = loaded
    }
    
    private func saveAchievements() {
        UserDefaults.standard.set(Array(achievedToday), forKey: ReadingGoalsManager.achievedTodayKey)
        UserDefaults.standard.set(Array(achievedThisWeek), forKey: ReadingGoalsManager.achievedThisWeekKey)
    }
    
    private func loadAchievements() {
        if let arr = UserDefaults.standard.stringArray(forKey: ReadingGoalsManager.achievedTodayKey) {
            achievedToday = Set(arr)
        }
        if let arr = UserDefaults.standard.stringArray(forKey: ReadingGoalsManager.achievedThisWeekKey) {
            achievedThisWeek = Set(arr)
        }
        resetAchievementsIfNewPeriod()
    }
}
