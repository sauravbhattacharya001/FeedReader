//
//  FeedReadingGoalTracker.swift
//  FeedReaderCore
//
//  Tracks reading goals: daily/weekly article targets, topic diversity,
//  reading streaks, and progress reporting. Helps users build consistent
//  reading habits with adaptive goal suggestions.
//

import Foundation

// MARK: - Models

/// A reading goal configuration.
public struct ReadingGoal: Sendable {
    public enum Period: String, Sendable, CaseIterable {
        case daily = "daily"
        case weekly = "weekly"
    }

    public enum GoalType: String, Sendable, CaseIterable {
        case articleCount = "articleCount"
        case topicDiversity = "topicDiversity"
        case minutesRead = "minutesRead"
    }

    /// The type of goal.
    public let type: GoalType
    /// The period over which the goal applies.
    public let period: Period
    /// Target value (e.g. 5 articles, 3 topics, 30 minutes).
    public let target: Int
    /// Optional label for display.
    public let label: String?

    public init(type: GoalType, period: Period, target: Int, label: String? = nil) {
        self.type = type
        self.period = period
        self.target = target
        self.label = label
    }
}

/// A record of a read article for goal tracking.
public struct ReadEvent: Sendable {
    /// Article identifier.
    public let articleId: String
    /// Topic/category of the article.
    public let topic: String
    /// When the article was read.
    public let readAt: Date
    /// Estimated reading time in minutes.
    public let minutesSpent: Double
    /// Source feed name.
    public let feedName: String

    public init(articleId: String, topic: String, readAt: Date, minutesSpent: Double, feedName: String) {
        self.articleId = articleId
        self.topic = topic
        self.readAt = readAt
        self.minutesSpent = minutesSpent
        self.feedName = feedName
    }
}

/// Progress toward a single goal.
public struct GoalProgress: Sendable {
    /// The goal being tracked.
    public let goal: ReadingGoal
    /// Current value achieved.
    public let current: Int
    /// Target value.
    public let target: Int
    /// Percentage complete (0.0 - 1.0+).
    public let progress: Double
    /// Whether the goal is met.
    public let isComplete: Bool
    /// Remaining to reach the goal.
    public let remaining: Int
    /// Trend compared to previous period (-1 declining, 0 flat, 1 improving).
    public let trend: Int
    /// Human-readable status message.
    public let statusMessage: String
}

/// Reading streak information.
public struct ReadingStreak: Sendable {
    /// Current consecutive days with at least one article read.
    public let currentDays: Int
    /// Longest streak ever.
    public let longestDays: Int
    /// Whether today has reading activity.
    public let activeToday: Bool
    /// Days since last read (0 if read today).
    public let daysSinceLastRead: Int
    /// Motivational message.
    public let message: String
}

/// Overall reading progress report.
public struct ReadingProgressReport: Sendable {
    /// Per-goal progress.
    public let goals: [GoalProgress]
    /// Streak information.
    public let streak: ReadingStreak
    /// Total articles read in the current week.
    public let weeklyArticleCount: Int
    /// Total articles read today.
    public let dailyArticleCount: Int
    /// Unique topics read this week.
    public let weeklyTopicCount: Int
    /// Total reading minutes this week.
    public let weeklyMinutes: Double
    /// Grade (A-F) based on overall goal completion.
    public let grade: String
    /// Suggested goal adjustments.
    public let suggestions: [String]
    /// Generated at timestamp.
    public let generatedAt: Date

    /// Markdown-formatted report.
    public var markdown: String {
        var lines: [String] = []
        lines.append("# Reading Progress Report")
        lines.append("")
        lines.append("## Summary")
        lines.append("| Metric | Value |")
        lines.append("|--------|-------|")
        lines.append("| Grade | \(grade) |")
        lines.append("| Today | \(dailyArticleCount) articles |")
        lines.append("| This Week | \(weeklyArticleCount) articles |")
        lines.append("| Topics This Week | \(weeklyTopicCount) |")
        lines.append("| Reading Time | \(String(format: "%.0f", weeklyMinutes)) min |")
        lines.append("| Streak | \(streak.currentDays) days |")
        lines.append("")
        lines.append("## Goals")
        lines.append("| Goal | Progress | Status |")
        lines.append("|------|----------|--------|")
        for g in goals {
            let pct = Int(g.progress * 100)
            let icon = g.isComplete ? "✅" : (g.progress >= 0.5 ? "🟡" : "🔴")
            lines.append("| \(g.goal.label ?? g.goal.type.rawValue) (\(g.goal.period.rawValue)) | \(g.current)/\(g.target) (\(pct)%) | \(icon) |")
        }
        lines.append("")
        lines.append("## Streak")
        lines.append("- \(streak.message)")
        if !suggestions.isEmpty {
            lines.append("")
            lines.append("## Suggestions")
            for s in suggestions {
                lines.append("- \(s)")
            }
        }
        return lines.joined(separator: "\n")
    }

    /// Plain text headline.
    public var headline: String {
        let completedCount = goals.filter { $0.isComplete }.count
        return "READING: grade=\(grade) goals=\(completedCount)/\(goals.count) streak=\(streak.currentDays)d weekly=\(weeklyArticleCount)"
    }
}

// MARK: - Tracker

/// Tracks reading goals and produces progress reports.
public final class FeedReadingGoalTracker: @unchecked Sendable {
    private let goals: [ReadingGoal]
    private let calendar: Calendar
    private let nowFn: () -> Date

    /// Initialize with goals and optional clock injection.
    /// - Parameters:
    ///   - goals: The reading goals to track.
    ///   - calendar: Calendar for date calculations (default: current).
    ///   - now: Injectable clock for deterministic testing.
    public init(goals: [ReadingGoal], calendar: Calendar = .current, now: @escaping () -> Date = { Date() }) {
        self.goals = goals
        self.calendar = calendar
        self.nowFn = now
    }

    /// Generate a progress report from reading events.
    /// - Parameter events: All read events to consider.
    /// - Returns: A full progress report.
    public func report(from events: [ReadEvent]) -> ReadingProgressReport {
        let now = nowFn()
        let todayStart = calendar.startOfDay(for: now)
        let weekStart = calendar.date(from: calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: now)) ?? todayStart

        let todayEvents = events.filter { $0.readAt >= todayStart }
        let weekEvents = events.filter { $0.readAt >= weekStart }

        let dailyArticleCount = todayEvents.count
        let weeklyArticleCount = weekEvents.count
        let weeklyTopics = Set(weekEvents.map { $0.topic })
        let weeklyMinutes = weekEvents.reduce(0.0) { $0 + $1.minutesSpent }

        // Previous period for trend
        let prevWeekStart = calendar.date(byAdding: .day, value: -7, to: weekStart) ?? weekStart
        let prevWeekEvents = events.filter { $0.readAt >= prevWeekStart && $0.readAt < weekStart }
        let prevDayStart = calendar.date(byAdding: .day, value: -1, to: todayStart) ?? todayStart
        let prevDayEvents = events.filter { $0.readAt >= prevDayStart && $0.readAt < todayStart }

        // Goal progress
        var goalProgress: [GoalProgress] = []
        for goal in goals {
            let (current, prev) = computeGoalValues(
                goal: goal,
                todayEvents: todayEvents, weekEvents: weekEvents,
                prevDayEvents: prevDayEvents, prevWeekEvents: prevWeekEvents,
                weeklyTopics: weeklyTopics
            )
            let progress = goal.target > 0 ? Double(current) / Double(goal.target) : 0.0
            let isComplete = current >= goal.target
            let remaining = max(0, goal.target - current)
            let trend: Int
            if current > prev { trend = 1 }
            else if current < prev { trend = -1 }
            else { trend = 0 }

            let statusMessage = isComplete
                ? "Goal achieved! \(current)/\(goal.target)"
                : "\(remaining) more to go (\(Int(progress * 100))% complete)"

            goalProgress.append(GoalProgress(
                goal: goal, current: current, target: goal.target,
                progress: progress, isComplete: isComplete,
                remaining: remaining, trend: trend,
                statusMessage: statusMessage
            ))
        }

        // Streak
        let streak = computeStreak(events: events, now: now)

        // Grade
        let grade = computeGrade(goalProgress: goalProgress, streak: streak)

        // Suggestions
        let suggestions = buildSuggestions(
            goalProgress: goalProgress, streak: streak,
            weeklyArticleCount: weeklyArticleCount,
            weeklyTopics: weeklyTopics
        )

        return ReadingProgressReport(
            goals: goalProgress,
            streak: streak,
            weeklyArticleCount: weeklyArticleCount,
            dailyArticleCount: dailyArticleCount,
            weeklyTopicCount: weeklyTopics.count,
            weeklyMinutes: weeklyMinutes,
            grade: grade,
            suggestions: suggestions,
            generatedAt: now
        )
    }

    // MARK: - Private

    private func computeGoalValues(
        goal: ReadingGoal,
        todayEvents: [ReadEvent], weekEvents: [ReadEvent],
        prevDayEvents: [ReadEvent], prevWeekEvents: [ReadEvent],
        weeklyTopics: Set<String>
    ) -> (current: Int, previous: Int) {
        switch (goal.type, goal.period) {
        case (.articleCount, .daily):
            return (todayEvents.count, prevDayEvents.count)
        case (.articleCount, .weekly):
            return (weekEvents.count, prevWeekEvents.count)
        case (.topicDiversity, .daily):
            let todayTopics = Set(todayEvents.map { $0.topic })
            let prevTopics = Set(prevDayEvents.map { $0.topic })
            return (todayTopics.count, prevTopics.count)
        case (.topicDiversity, .weekly):
            let prevTopics = Set(prevWeekEvents.map { $0.topic })
            return (weeklyTopics.count, prevTopics.count)
        case (.minutesRead, .daily):
            let todayMin = Int(todayEvents.reduce(0.0) { $0 + $1.minutesSpent })
            let prevMin = Int(prevDayEvents.reduce(0.0) { $0 + $1.minutesSpent })
            return (todayMin, prevMin)
        case (.minutesRead, .weekly):
            let weekMin = Int(weekEvents.reduce(0.0) { $0 + $1.minutesSpent })
            let prevMin = Int(prevWeekEvents.reduce(0.0) { $0 + $1.minutesSpent })
            return (weekMin, prevMin)
        }
    }

    private func computeStreak(events: [ReadEvent], now: Date) -> ReadingStreak {
        let todayStart = calendar.startOfDay(for: now)
        let hasToday = events.contains { $0.readAt >= todayStart }

        // Find consecutive days going backward
        var currentStreak = 0
        var checkDate = hasToday ? todayStart : calendar.date(byAdding: .day, value: -1, to: todayStart)!
        if hasToday { currentStreak = 1; checkDate = calendar.date(byAdding: .day, value: -1, to: todayStart)! }

        while true {
            let nextDay = calendar.date(byAdding: .day, value: 1, to: checkDate)!
            let dayHasReading = events.contains { $0.readAt >= checkDate && $0.readAt < nextDay }
            if dayHasReading {
                currentStreak += 1
                checkDate = calendar.date(byAdding: .day, value: -1, to: checkDate)!
            } else {
                break
            }
        }

        // Longest streak (simple scan over sorted dates)
        let readDays = Set(events.map { calendar.startOfDay(for: $0.readAt) }).sorted()
        var longest = 0
        var run = 0
        var prev: Date?
        for day in readDays {
            if let p = prev, calendar.date(byAdding: .day, value: 1, to: p) == day {
                run += 1
            } else {
                run = 1
            }
            longest = max(longest, run)
            prev = day
        }

        let daysSinceLastRead: Int
        if let lastRead = events.map({ $0.readAt }).max() {
            daysSinceLastRead = max(0, calendar.dateComponents([.day], from: calendar.startOfDay(for: lastRead), to: todayStart).day ?? 0)
        } else {
            daysSinceLastRead = -1
        }

        let message: String
        if currentStreak >= 7 {
            message = "🔥 \(currentStreak)-day streak! Outstanding consistency."
        } else if currentStreak >= 3 {
            message = "📈 \(currentStreak)-day streak — keep it going!"
        } else if hasToday {
            message = "✅ Read today. Building momentum."
        } else if daysSinceLastRead == 1 {
            message = "⚡ Read yesterday — don't break the chain!"
        } else if daysSinceLastRead > 1 {
            message = "📖 \(daysSinceLastRead) days since last read. Time to pick it up!"
        } else {
            message = "🌱 Start your reading journey today."
        }

        return ReadingStreak(
            currentDays: currentStreak,
            longestDays: longest,
            activeToday: hasToday,
            daysSinceLastRead: max(0, daysSinceLastRead),
            message: message
        )
    }

    private func computeGrade(goalProgress: [GoalProgress], streak: ReadingStreak) -> String {
        guard !goalProgress.isEmpty else { return "A" }
        let completionRate = Double(goalProgress.filter { $0.isComplete }.count) / Double(goalProgress.count)
        let avgProgress = goalProgress.map { min(1.0, $0.progress) }.reduce(0.0, +) / Double(goalProgress.count)

        // Weighted: 60% completion, 30% avg progress, 10% streak bonus
        let streakBonus = min(1.0, Double(streak.currentDays) / 7.0)
        let score = completionRate * 0.6 + avgProgress * 0.3 + streakBonus * 0.1

        if score >= 0.90 { return "A" }
        if score >= 0.75 { return "B" }
        if score >= 0.55 { return "C" }
        if score >= 0.35 { return "D" }
        return "F"
    }

    private func buildSuggestions(
        goalProgress: [GoalProgress], streak: ReadingStreak,
        weeklyArticleCount: Int, weeklyTopics: Set<String>
    ) -> [String] {
        var suggestions: [String] = []

        let declining = goalProgress.filter { $0.trend == -1 }
        if !declining.isEmpty {
            suggestions.append("Some goals are trending down — consider shorter reading sessions to stay consistent.")
        }

        if streak.currentDays == 0 && streak.daysSinceLastRead >= 3 {
            suggestions.append("Try setting a micro-goal: just one article today to restart your streak.")
        }

        if weeklyTopics.count <= 1 && weeklyArticleCount >= 3 {
            suggestions.append("Diversify your reading — explore a new topic category this week.")
        }

        let overachieved = goalProgress.filter { $0.progress >= 1.5 }
        if !overachieved.isEmpty {
            suggestions.append("You're exceeding some goals by 50%+. Consider raising your targets to stay challenged.")
        }

        if suggestions.isEmpty {
            suggestions.append("You're on track — keep up the great work!")
        }

        return suggestions
    }
}
