//
//  ReadingGoalsTracker.swift
//  FeedReader
//
//  Set and track daily/weekly/monthly article reading goals with streak
//  tracking, milestone badges, and progress analytics.
//
//  Key features:
//  - Configure goals: daily articles, weekly articles, monthly articles
//  - Track progress against each goal with percentage completion
//  - Streak tracking: consecutive days meeting daily goal
//  - Milestone badges at 7, 30, 100, 365-day streaks
//  - Historical completion rates by period
//  - Best streak tracking
//  - Adjustable goals with history preserved
//  - JSON persistence in Documents directory
//  - Export goal reports as JSON/Markdown
//

import Foundation

// MARK: - Notifications

extension Notification.Name {
    /// Posted when reading goals tracker data changes (streaks, milestones).
    /// Note: ReadingGoalsManager defines .readingGoalsDidChange for basic goal progress.
    static let readingGoalsTrackerDidChange = Notification.Name("ReadingGoalsTrackerDidChangeNotification")
}

// MARK: - Models

/// A reading goal configuration
public struct ReadingGoal: Codable, Equatable {
    public enum Period: String, Codable, CaseIterable {
        case daily
        case weekly
        case monthly
    }
    
    public let period: Period
    public var target: Int
    public var isActive: Bool
    
    public init(period: Period, target: Int, isActive: Bool = true) {
        self.period = period
        self.target = max(1, target)
        self.isActive = isActive
    }
}

/// A single reading log entry
public struct ReadingLogEntry: Codable, Equatable {
    public let date: Date
    public let articleId: String
    public let feedTitle: String?
    
    public init(date: Date = Date(), articleId: String, feedTitle: String? = nil) {
        self.date = date
        self.articleId = articleId
        self.feedTitle = feedTitle
    }
}

/// A milestone badge earned by the reader
public struct ReadingBadge: Codable, Equatable {
    public let name: String
    public let description: String
    public let streakRequired: Int
    public let dateEarned: Date
    
    public init(name: String, description: String, streakRequired: Int, dateEarned: Date = Date()) {
        self.name = name
        self.description = description
        self.streakRequired = streakRequired
        self.dateEarned = dateEarned
    }
}

/// Progress snapshot for a specific period
public struct GoalProgress: Equatable {
    public let period: ReadingGoal.Period
    public let target: Int
    public let current: Int
    public let percentage: Double
    public let isComplete: Bool
    
    public init(period: ReadingGoal.Period, target: Int, current: Int) {
        self.period = period
        self.target = target
        self.current = current
        self.percentage = target > 0 ? min(100.0, Double(current) / Double(target) * 100.0) : 0
        self.isComplete = current >= target
    }
}

/// Historical completion record for a period
public struct PeriodCompletion: Codable, Equatable {
    public let periodStart: Date
    public let periodEnd: Date
    public let period: ReadingGoal.Period
    public let target: Int
    public let achieved: Int
    public let completed: Bool
    
    public init(periodStart: Date, periodEnd: Date, period: ReadingGoal.Period, target: Int, achieved: Int) {
        self.periodStart = periodStart
        self.periodEnd = periodEnd
        self.period = period
        self.target = target
        self.achieved = achieved
        self.completed = achieved >= target
    }
}

/// Persisted state
struct ReadingGoalsState: Codable {
    var goals: [ReadingGoal]
    var readingLog: [ReadingLogEntry]
    var badges: [ReadingBadge]
    var completionHistory: [PeriodCompletion]
    var currentStreak: Int
    var bestStreak: Int
    var lastStreakDate: Date?
    
    static let empty = ReadingGoalsState(
        goals: [],
        readingLog: [],
        badges: [],
        completionHistory: [],
        currentStreak: 0,
        bestStreak: 0,
        lastStreakDate: nil
    )
}

// MARK: - Badge Definitions

private let badgeDefinitions: [(name: String, description: String, streak: Int)] = [
    ("🔥 Week Warrior", "7-day reading streak", 7),
    ("📚 Monthly Master", "30-day reading streak", 30),
    ("⭐ Century Reader", "100-day reading streak", 100),
    ("🏆 Year-Long Legend", "365-day reading streak", 365)
]

// MARK: - ReadingGoalsTracker

/// Manages reading goals, tracks progress, and awards streak badges.
public final class ReadingGoalsTracker {
    
    // MARK: - Properties
    
    private var state: ReadingGoalsState
    private let fileURL: URL
    private let calendar: Calendar
    
    /// Current goals
    public var goals: [ReadingGoal] { state.goals }
    
    /// All reading log entries
    public var readingLog: [ReadingLogEntry] { state.readingLog }
    
    /// Earned badges
    public var badges: [ReadingBadge] { state.badges }
    
    /// Current consecutive-day streak
    public var currentStreak: Int { state.currentStreak }
    
    /// Best ever streak
    public var bestStreak: Int { state.bestStreak }
    
    /// Historical completions
    public var completionHistory: [PeriodCompletion] { state.completionHistory }
    
    // MARK: - Init
    
    public init(directory: URL? = nil, calendar: Calendar = .current) {
        self.calendar = calendar
        let dir = directory ?? FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        self.fileURL = dir.appendingPathComponent("reading_goals.json")
        
        if let data = try? Data(contentsOf: fileURL),
           let loaded = try? JSONDecoder.withISO8601.decode(ReadingGoalsState.self, from: data) {
            self.state = loaded
        } else {
            self.state = .empty
        }
    }
    
    // MARK: - Goal Management
    
    /// Set or update a goal for a period.
    @discardableResult
    public func setGoal(period: ReadingGoal.Period, target: Int) -> ReadingGoal {
        let goal = ReadingGoal(period: period, target: target)
        if let idx = state.goals.firstIndex(where: { $0.period == period }) {
            state.goals[idx] = goal
        } else {
            state.goals.append(goal)
        }
        save()
        return goal
    }
    
    /// Remove a goal.
    public func removeGoal(period: ReadingGoal.Period) {
        state.goals.removeAll { $0.period == period }
        save()
    }
    
    /// Toggle a goal active/inactive.
    public func toggleGoal(period: ReadingGoal.Period, active: Bool) {
        if let idx = state.goals.firstIndex(where: { $0.period == period }) {
            state.goals[idx].isActive = active
            save()
        }
    }
    
    // MARK: - Reading Log
    
    /// Log an article as read. Updates streaks and checks badges.
    public func logArticleRead(articleId: String, feedTitle: String? = nil, date: Date = Date()) {
        let entry = ReadingLogEntry(date: date, articleId: articleId, feedTitle: feedTitle)
        state.readingLog.append(entry)
        updateStreak(for: date)
        checkBadges()
        save()
    }
    
    /// Number of articles read on a specific date.
    public func articlesRead(on date: Date) -> Int {
        let dayStart = calendar.startOfDay(for: date)
        let dayEnd = calendar.date(byAdding: .day, value: 1, to: dayStart)!
        return state.readingLog.filter { $0.date >= dayStart && $0.date < dayEnd }.count
    }
    
    /// Number of articles read in the current week (starting Monday).
    public func articlesReadThisWeek(from referenceDate: Date = Date()) -> Int {
        guard let weekInterval = calendar.dateInterval(of: .weekOfYear, for: referenceDate) else { return 0 }
        return state.readingLog.filter { $0.date >= weekInterval.start && $0.date < weekInterval.end }.count
    }
    
    /// Number of articles read in the current month.
    public func articlesReadThisMonth(from referenceDate: Date = Date()) -> Int {
        guard let monthInterval = calendar.dateInterval(of: .month, for: referenceDate) else { return 0 }
        return state.readingLog.filter { $0.date >= monthInterval.start && $0.date < monthInterval.end }.count
    }
    
    // MARK: - Progress
    
    /// Get current progress for all active goals.
    public func currentProgress(at date: Date = Date()) -> [GoalProgress] {
        return state.goals.filter { $0.isActive }.map { goal in
            let count: Int
            switch goal.period {
            case .daily:
                count = articlesRead(on: date)
            case .weekly:
                count = articlesReadThisWeek(from: date)
            case .monthly:
                count = articlesReadThisMonth(from: date)
            }
            return GoalProgress(period: goal.period, target: goal.target, current: count)
        }
    }
    
    /// Get progress for a specific period.
    public func progress(for period: ReadingGoal.Period, at date: Date = Date()) -> GoalProgress? {
        guard let goal = state.goals.first(where: { $0.period == period && $0.isActive }) else { return nil }
        let count: Int
        switch period {
        case .daily:
            count = articlesRead(on: date)
        case .weekly:
            count = articlesReadThisWeek(from: date)
        case .monthly:
            count = articlesReadThisMonth(from: date)
        }
        return GoalProgress(period: period, target: goal.target, current: count)
    }
    
    // MARK: - Period Completion
    
    /// Record completion of a period (call at end of day/week/month or on-demand).
    public func recordPeriodCompletion(period: ReadingGoal.Period, at date: Date = Date()) {
        guard let goal = state.goals.first(where: { $0.period == period }) else { return }
        
        let (start, end): (Date, Date)
        switch period {
        case .daily:
            start = calendar.startOfDay(for: date)
            end = calendar.date(byAdding: .day, value: 1, to: start)!
        case .weekly:
            guard let interval = calendar.dateInterval(of: .weekOfYear, for: date) else { return }
            start = interval.start
            end = interval.end
        case .monthly:
            guard let interval = calendar.dateInterval(of: .month, for: date) else { return }
            start = interval.start
            end = interval.end
        }
        
        let achieved = state.readingLog.filter { $0.date >= start && $0.date < end }.count
        
        // Don't duplicate
        if state.completionHistory.contains(where: { $0.periodStart == start && $0.period == period }) {
            return
        }
        
        let completion = PeriodCompletion(periodStart: start, periodEnd: end, period: period, target: goal.target, achieved: achieved)
        state.completionHistory.append(completion)
        save()
    }
    
    /// Completion rate for a period type over recorded history (0-100%).
    public func completionRate(for period: ReadingGoal.Period) -> Double {
        let records = state.completionHistory.filter { $0.period == period }
        guard !records.isEmpty else { return 0 }
        let completed = records.filter { $0.completed }.count
        return Double(completed) / Double(records.count) * 100.0
    }
    
    // MARK: - Streaks
    
    private func updateStreak(for date: Date) {
        let today = calendar.startOfDay(for: date)
        
        guard let dailyGoal = state.goals.first(where: { $0.period == .daily }) else {
            // No daily goal — streak is just consecutive days with any read
            if let lastDate = state.lastStreakDate {
                let lastDay = calendar.startOfDay(for: lastDate)
                let yesterday = calendar.date(byAdding: .day, value: -1, to: today)!
                if lastDay == today {
                    // Same day, no change
                } else if lastDay == calendar.startOfDay(for: yesterday) {
                    state.currentStreak += 1
                } else {
                    state.currentStreak = 1
                }
            } else {
                state.currentStreak = 1
            }
            state.lastStreakDate = date
            state.bestStreak = max(state.bestStreak, state.currentStreak)
            return
        }
        
        // With daily goal: streak counts only if target met
        let todayCount = articlesRead(on: date)
        if todayCount >= dailyGoal.target {
            if let lastDate = state.lastStreakDate {
                let lastDay = calendar.startOfDay(for: lastDate)
                let yesterday = calendar.date(byAdding: .day, value: -1, to: today)!
                if lastDay == today {
                    // Already counted today
                } else if lastDay == calendar.startOfDay(for: yesterday) {
                    state.currentStreak += 1
                    state.lastStreakDate = date
                } else {
                    state.currentStreak = 1
                    state.lastStreakDate = date
                }
            } else {
                state.currentStreak = 1
                state.lastStreakDate = date
            }
            state.bestStreak = max(state.bestStreak, state.currentStreak)
        }
    }
    
    // MARK: - Badges
    
    private func checkBadges() {
        for def in badgeDefinitions {
            if state.currentStreak >= def.streak &&
               !state.badges.contains(where: { $0.streakRequired == def.streak }) {
                let badge = ReadingBadge(name: def.name, description: def.description, streakRequired: def.streak)
                state.badges.append(badge)
                NotificationCenter.default.post(name: .readingGoalsTrackerDidChange, object: self, userInfo: ["newBadge": badge])
            }
        }
    }
    
    // MARK: - Analytics
    
    /// Articles per day over the last N days.
    public func dailyReadCounts(days: Int = 30, from referenceDate: Date = Date()) -> [(date: Date, count: Int)] {
        var results: [(Date, Int)] = []
        for i in (0..<days).reversed() {
            guard let day = calendar.date(byAdding: .day, value: -i, to: calendar.startOfDay(for: referenceDate)) else { continue }
            results.append((day, articlesRead(on: day)))
        }
        return results
    }
    
    /// Top feeds by articles read.
    public func topFeeds(limit: Int = 10) -> [(feed: String, count: Int)] {
        var counts: [String: Int] = [:]
        for entry in state.readingLog {
            let feed = entry.feedTitle ?? "Unknown"
            counts[feed, default: 0] += 1
        }
        return counts.sorted { $0.value > $1.value }.prefix(limit).map { ($0.key, $0.value) }
    }
    
    /// Total articles read all-time.
    public var totalArticlesRead: Int { state.readingLog.count }
    
    // MARK: - Export
    
    /// Export goal report as JSON string.
    public func exportJSON() -> String {
        let progress = currentProgress()
        var report: [String: Any] = [
            "totalArticlesRead": totalArticlesRead,
            "currentStreak": currentStreak,
            "bestStreak": bestStreak,
            "badgesEarned": badges.count,
            "goals": goals.map { ["period": $0.period.rawValue, "target": $0.target, "active": $0.isActive] },
            "progress": progress.map { ["period": $0.period.rawValue, "target": $0.target, "current": $0.current, "percentage": $0.percentage, "complete": $0.isComplete] }
        ]
        
        let topFeedsList = topFeeds(limit: 5)
        report["topFeeds"] = topFeedsList.map { ["feed": $0.feed, "count": $0.count] }
        
        if let data = try? JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys]),
           let str = String(data: data, encoding: .utf8) {
            return str
        }
        return "{}"
    }
    
    /// Export as human-readable Markdown.
    public func exportMarkdown() -> String {
        let progress = currentProgress()
        var md = "# 📖 Reading Goals Report\n\n"
        
        md += "## Stats\n"
        md += "- **Total articles read:** \(totalArticlesRead)\n"
        md += "- **Current streak:** \(currentStreak) days\n"
        md += "- **Best streak:** \(bestStreak) days\n"
        md += "- **Badges earned:** \(badges.count)\n\n"
        
        if !progress.isEmpty {
            md += "## Current Progress\n"
            for p in progress {
                let bar = progressBar(p.percentage)
                md += "- **\(p.period.rawValue.capitalized):** \(p.current)/\(p.target) \(bar) \(String(format: "%.0f", p.percentage))%"
                if p.isComplete { md += " ✅" }
                md += "\n"
            }
            md += "\n"
        }
        
        if !badges.isEmpty {
            md += "## Badges\n"
            for badge in badges {
                md += "- \(badge.name) — \(badge.description)\n"
            }
            md += "\n"
        }
        
        let feeds = topFeeds(limit: 5)
        if !feeds.isEmpty {
            md += "## Top Feeds\n"
            for (i, f) in feeds.enumerated() {
                md += "\(i + 1). \(f.feed) (\(f.count) articles)\n"
            }
        }
        
        return md
    }
    
    // MARK: - Persistence
    
    private func save() {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        if let data = try? encoder.encode(state) {
            try? data.write(to: fileURL, options: .atomic)
        }
        NotificationCenter.default.post(name: .readingGoalsTrackerDidChange, object: self)
    }
    
    /// Clear all data (for testing).
    public func reset() {
        state = .empty
        save()
    }
    
    // MARK: - Helpers
    
    private func progressBar(_ pct: Double, width: Int = 20) -> String {
        let filled = Int(pct / 100.0 * Double(width))
        let empty = width - filled
        return "[" + String(repeating: "█", count: filled) + String(repeating: "░", count: empty) + "]"
    }
}

// MARK: - JSON Decoder Extension

private extension JSONDecoder {
    static var withISO8601: JSONDecoder {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }
}
