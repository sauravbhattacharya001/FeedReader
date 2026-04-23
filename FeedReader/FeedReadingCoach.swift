//
//  FeedReadingCoach.swift
//  FeedReader
//
//  Autonomous personal reading coach that analyzes reading behavior
//  patterns and provides personalized coaching to help users read
//  more effectively.
//
//  How it works:
//  1. Tracks reading sessions (article, duration, completion, time of day)
//  2. Detects habit patterns: peak hours, preferred lengths, speed trends, streaks
//  3. Generates actionable coaching insights based on patterns
//  4. Manages reading goals with progress tracking
//  5. Produces weekly coaching reports with metrics and recommendations
//  6. Calculates per-session focus scores
//
//  Usage:
//  ```
//  let coach = FeedReadingCoach.shared
//
//  // Record a session
//  let session = ReadingSession(
//      articleId: "abc", feedTitle: "TechCrunch", topic: "tech",
//      startTime: Date(), durationSeconds: 240,
//      wordCount: 800, completionPercent: 0.95
//  )
//  coach.recordSession(session)
//
//  // Get coaching insights
//  let insights = coach.generateInsights()
//  for insight in insights {
//      print("[\(insight.category)] \(insight.message)")
//  }
//
//  // Set a goal
//  coach.setGoal(ReadingGoal(type: .articlesPerDay, target: 5))
//
//  // Suggest next reads
//  let suggestions = coach.suggestNextReads(from: [("AI News", "TechCrunch"), ("Recipe", "FoodBlog")])
//
//  // Weekly report
//  let report = coach.generateWeeklyReport()
//  print(report.summary)
//  ```
//
//  All processing is on-device. No network calls.
//

import Foundation

// MARK: - Notifications

extension Notification.Name {
    static let coachInsightGenerated = Notification.Name("FeedReadingCoachInsightGenerated")
    static let coachGoalAchieved = Notification.Name("FeedReadingCoachGoalAchieved")
    static let coachStreakMilestone = Notification.Name("FeedReadingCoachStreakMilestone")
}

// MARK: - Insight Category

enum InsightCategory: String, Codable, CaseIterable {
    case timing
    case pacing
    case diversity
    case streak
    case completion
    case focus
    case growth
    case challenge
}

// MARK: - Goal Type

enum GoalType: String, Codable, CaseIterable {
    case articlesPerDay
    case minutesPerDay
    case topicsPerWeek
    case completionRate
    case streakDays
}

// MARK: - Goal Status

enum GoalStatus: String, Codable {
    case active
    case achieved
    case missed
}

// MARK: - Models

struct ReadingSession: Codable, Identifiable {
    let id: String
    let articleId: String
    let feedTitle: String
    let topic: String
    let startTime: Date
    let durationSeconds: Int
    let wordCount: Int
    let completionPercent: Double

    init(articleId: String, feedTitle: String, topic: String,
         startTime: Date = Date(), durationSeconds: Int,
         wordCount: Int, completionPercent: Double) {
        self.id = UUID().uuidString
        self.articleId = articleId
        self.feedTitle = feedTitle
        self.topic = topic
        self.startTime = startTime
        self.durationSeconds = durationSeconds
        self.wordCount = wordCount
        self.completionPercent = min(max(completionPercent, 0), 1)
    }

    var wordsPerMinute: Double {
        guard durationSeconds > 0 else { return 0 }
        let wordsRead = Double(wordCount) * completionPercent
        return wordsRead / (Double(durationSeconds) / 60.0)
    }

    var hourOfDay: Int {
        Calendar.current.component(.hour, from: startTime)
    }
}

struct CoachingInsight: Codable, Identifiable {
    let id: String
    let category: InsightCategory
    let message: String
    let priority: Int // 1-5, higher = more important
    let generatedAt: Date
    let tip: String

    init(category: InsightCategory, message: String, priority: Int, tip: String) {
        self.id = UUID().uuidString
        self.category = category
        self.message = message
        self.priority = min(max(priority, 1), 5)
        self.generatedAt = Date()
        self.tip = tip
    }
}

struct ReadingGoal: Codable, Identifiable {
    let id: String
    let type: GoalType
    let target: Double
    var current: Double
    let createdAt: Date
    var deadline: Date?
    var status: GoalStatus

    init(type: GoalType, target: Double, deadline: Date? = nil) {
        self.id = UUID().uuidString
        self.type = type
        self.target = target
        self.current = 0
        self.createdAt = Date()
        self.deadline = deadline
        self.status = .active
    }
}

struct HabitProfile: Codable {
    let peakHours: [Int]
    let avgSessionMinutes: Double
    let avgWordsPerMinute: Double
    let preferredWordCount: ClosedRange<Int>
    let topTopics: [String]
    let topFeeds: [String]
    let consistencyScore: Double // 0-1
    let focusScore: Double // 0-1
    let currentStreak: Int
    let longestStreak: Int
    let totalSessions: Int
    let totalMinutes: Double

    private enum CodingKeys: String, CodingKey {
        case peakHours, avgSessionMinutes, avgWordsPerMinute
        case preferredWordCountLower, preferredWordCountUpper
        case topTopics, topFeeds, consistencyScore, focusScore
        case currentStreak, longestStreak, totalSessions, totalMinutes
    }

    init(peakHours: [Int], avgSessionMinutes: Double, avgWordsPerMinute: Double,
         preferredWordCount: ClosedRange<Int>, topTopics: [String], topFeeds: [String],
         consistencyScore: Double, focusScore: Double,
         currentStreak: Int, longestStreak: Int, totalSessions: Int, totalMinutes: Double) {
        self.peakHours = peakHours
        self.avgSessionMinutes = avgSessionMinutes
        self.avgWordsPerMinute = avgWordsPerMinute
        self.preferredWordCount = preferredWordCount
        self.topTopics = topTopics
        self.topFeeds = topFeeds
        self.consistencyScore = consistencyScore
        self.focusScore = focusScore
        self.currentStreak = currentStreak
        self.longestStreak = longestStreak
        self.totalSessions = totalSessions
        self.totalMinutes = totalMinutes
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        peakHours = try c.decode([Int].self, forKey: .peakHours)
        avgSessionMinutes = try c.decode(Double.self, forKey: .avgSessionMinutes)
        avgWordsPerMinute = try c.decode(Double.self, forKey: .avgWordsPerMinute)
        let lo = try c.decode(Int.self, forKey: .preferredWordCountLower)
        let hi = try c.decode(Int.self, forKey: .preferredWordCountUpper)
        preferredWordCount = lo...hi
        topTopics = try c.decode([String].self, forKey: .topTopics)
        topFeeds = try c.decode([String].self, forKey: .topFeeds)
        consistencyScore = try c.decode(Double.self, forKey: .consistencyScore)
        focusScore = try c.decode(Double.self, forKey: .focusScore)
        currentStreak = try c.decode(Int.self, forKey: .currentStreak)
        longestStreak = try c.decode(Int.self, forKey: .longestStreak)
        totalSessions = try c.decode(Int.self, forKey: .totalSessions)
        totalMinutes = try c.decode(Double.self, forKey: .totalMinutes)
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(peakHours, forKey: .peakHours)
        try c.encode(avgSessionMinutes, forKey: .avgSessionMinutes)
        try c.encode(avgWordsPerMinute, forKey: .avgWordsPerMinute)
        try c.encode(preferredWordCount.lowerBound, forKey: .preferredWordCountLower)
        try c.encode(preferredWordCount.upperBound, forKey: .preferredWordCountUpper)
        try c.encode(topTopics, forKey: .topTopics)
        try c.encode(topFeeds, forKey: .topFeeds)
        try c.encode(consistencyScore, forKey: .consistencyScore)
        try c.encode(focusScore, forKey: .focusScore)
        try c.encode(currentStreak, forKey: .currentStreak)
        try c.encode(longestStreak, forKey: .longestStreak)
        try c.encode(totalSessions, forKey: .totalSessions)
        try c.encode(totalMinutes, forKey: .totalMinutes)
    }
}

struct WeeklyReport: Codable {
    let weekStart: Date
    let weekEnd: Date
    let totalSessions: Int
    let totalMinutes: Double
    let articlesCompleted: Int
    let avgCompletionRate: Double
    let avgWordsPerMinute: Double
    let topTopics: [String]
    let insights: [CoachingInsight]
    let achievements: [String]
    let recommendations: [String]
    let summary: String
}

// MARK: - Reading Coach Configuration

struct ReadingCoachConfig: Codable {
    var insightCooldownHours: Int = 12
    var minSessionsForInsights: Int = 5
    var streakMilestones: [Int] = [3, 7, 14, 30, 60, 100]
    var maxInsightsPerBatch: Int = 5
    var abandonmentThreshold: Double = 0.3
    var speedOutlierMultiplier: Double = 2.0
}

// MARK: - FeedReadingCoach

final class FeedReadingCoach {
    static let shared = FeedReadingCoach()

    var config = ReadingCoachConfig()
    private(set) var sessions: [ReadingSession] = []
    private(set) var goals: [ReadingGoal] = []
    private var lastInsightDate: Date?

    private let sessionsKey = "FeedReadingCoach_sessions"
    private let goalsKey = "FeedReadingCoach_goals"
    private let configKey = "FeedReadingCoach_config"
    private let lastInsightKey = "FeedReadingCoach_lastInsight"

    private init() {
        load()
    }

    // MARK: - Session Recording

    func recordSession(_ session: ReadingSession) {
        sessions.append(session)
        updateGoalProgress(with: session)
        checkStreakMilestones()
        save()
    }

    // MARK: - Habit Analysis

    func analyzeHabits() -> HabitProfile {
        guard !sessions.isEmpty else {
            return HabitProfile(
                peakHours: [], avgSessionMinutes: 0, avgWordsPerMinute: 0,
                preferredWordCount: 0...0, topTopics: [], topFeeds: [],
                consistencyScore: 0, focusScore: 0,
                currentStreak: 0, longestStreak: 0, totalSessions: 0, totalMinutes: 0
            )
        }

        // Peak hours
        var hourCounts: [Int: Int] = [:]
        for s in sessions { hourCounts[s.hourOfDay, default: 0] += 1 }
        let sortedHours = hourCounts.sorted { $0.value > $1.value }
        let peakHours = Array(sortedHours.prefix(3).map { $0.key })

        // Averages
        let totalSec = sessions.reduce(0) { $0 + $1.durationSeconds }
        let avgMin = Double(totalSec) / Double(sessions.count) / 60.0
        let wpms = sessions.compactMap { $0.wordsPerMinute }.filter { $0 > 0 }
        let avgWpm = wpms.isEmpty ? 0 : wpms.reduce(0, +) / Double(wpms.count)

        // Preferred word count range
        let wcs = sessions.map { $0.wordCount }.sorted()
        let p25 = wcs[max(0, wcs.count / 4)]
        let p75 = wcs[min(wcs.count - 1, wcs.count * 3 / 4)]

        // Top topics
        var topicCounts: [String: Int] = [:]
        for s in sessions { topicCounts[s.topic, default: 0] += 1 }
        let topTopics = Array(topicCounts.sorted { $0.value > $1.value }.prefix(5).map { $0.key })

        // Top feeds
        var feedCounts: [String: Int] = [:]
        for s in sessions { feedCounts[s.feedTitle, default: 0] += 1 }
        let topFeeds = Array(feedCounts.sorted { $0.value > $1.value }.prefix(5).map { $0.key })

        // Consistency & streaks
        let (current, longest, consistency) = computeStreaks()

        // Focus
        let avgFocus = sessions.map { focusScore(for: $0) }.reduce(0, +) / Double(sessions.count)

        return HabitProfile(
            peakHours: peakHours,
            avgSessionMinutes: avgMin,
            avgWordsPerMinute: avgWpm,
            preferredWordCount: p25...p75,
            topTopics: topTopics,
            topFeeds: topFeeds,
            consistencyScore: consistency,
            focusScore: avgFocus,
            currentStreak: current,
            longestStreak: longest,
            totalSessions: sessions.count,
            totalMinutes: Double(totalSec) / 60.0
        )
    }

    // MARK: - Focus Score

    /// Computes a 0-1 focus score for a single session based on completion, speed consistency, and duration.
    func focusScore(for session: ReadingSession) -> Double {
        // Completion factor (0-1)
        let completionFactor = session.completionPercent

        // Duration factor — sessions 2-20 min are optimal
        let mins = Double(session.durationSeconds) / 60.0
        let durationFactor: Double
        if mins < 0.5 { durationFactor = 0.2 }
        else if mins <= 2 { durationFactor = 0.5 + 0.5 * (mins / 2.0) }
        else if mins <= 20 { durationFactor = 1.0 }
        else if mins <= 45 { durationFactor = 1.0 - 0.3 * ((mins - 20) / 25.0) }
        else { durationFactor = 0.5 }

        // Speed factor — closer to user's average is better
        let wpms = sessions.compactMap { $0.wordsPerMinute }.filter { $0 > 0 }
        let avgWpm = wpms.isEmpty ? 220 : wpms.reduce(0, +) / Double(wpms.count)
        let speedFactor: Double
        if session.wordsPerMinute > 0 && avgWpm > 0 {
            let ratio = session.wordsPerMinute / avgWpm
            speedFactor = max(0, 1.0 - abs(ratio - 1.0))
        } else {
            speedFactor = 0.5
        }

        return min(1.0, (completionFactor * 0.5 + durationFactor * 0.25 + speedFactor * 0.25))
    }

    // MARK: - Coaching Insights

    func generateInsights() -> [CoachingInsight] {
        guard sessions.count >= config.minSessionsForInsights else { return [] }

        var insights: [CoachingInsight] = []
        let profile = analyzeHabits()
        let recent = recentSessions(days: 7)
        let older = recentSessions(days: 30)

        // 1. Peak timing
        if let peak = profile.peakHours.first {
            let period = peak < 12 ? "morning" : (peak < 17 ? "afternoon" : "evening")
            insights.append(CoachingInsight(
                category: .timing,
                message: "You read most actively in the \(period) (around \(peak):00).",
                priority: 3,
                tip: "Schedule your most important reads for the \(period) when your engagement is highest."
            ))
        }

        // 2. Morning vs evening speed
        let morningSessions = recent.filter { $0.hourOfDay >= 6 && $0.hourOfDay < 12 }
        let eveningSessions = recent.filter { $0.hourOfDay >= 18 && $0.hourOfDay < 24 }
        if morningSessions.count >= 2 && eveningSessions.count >= 2 {
            let morningWpm = morningSessions.map { $0.wordsPerMinute }.reduce(0, +) / Double(morningSessions.count)
            let eveningWpm = eveningSessions.map { $0.wordsPerMinute }.reduce(0, +) / Double(eveningSessions.count)
            if morningWpm > eveningWpm * 1.2 {
                let pct = Int((morningWpm / max(eveningWpm, 1) - 1) * 100)
                insights.append(CoachingInsight(
                    category: .timing,
                    message: "You read \(pct)% faster in the morning than in the evening.",
                    priority: 4,
                    tip: "Try scheduling deep, complex reads before noon for better comprehension."
                ))
            }
        }

        // 3. Abandonment pattern
        let abandoned = recent.filter { $0.completionPercent < config.abandonmentThreshold }
        if abandoned.count >= 3 {
            let avgWords = abandoned.map { $0.wordCount }.reduce(0, +) / abandoned.count
            insights.append(CoachingInsight(
                category: .completion,
                message: "You abandoned \(abandoned.count) articles this week, mostly over \(avgWords) words.",
                priority: 4,
                tip: "Try the speed-read mode for long articles, or save them for high-focus periods."
            ))
        }

        // 4. Completion improvement
        if older.count >= 10 && recent.count >= 5 {
            let olderAvg = older.prefix(older.count / 2).map { $0.completionPercent }.reduce(0, +)
                / Double(older.count / 2)
            let recentAvg = recent.map { $0.completionPercent }.reduce(0, +) / Double(recent.count)
            if recentAvg > olderAvg + 0.1 {
                let pct = Int((recentAvg - olderAvg) * 100)
                insights.append(CoachingInsight(
                    category: .growth,
                    message: "Your completion rate improved by \(pct)% — nice progress!",
                    priority: 3,
                    tip: "Keep it up! Consistency in finishing articles builds stronger reading habits."
                ))
            }
        }

        // 5. Streak celebration
        let (currentStreak, _, _) = computeStreaks()
        if config.streakMilestones.contains(currentStreak) {
            insights.append(CoachingInsight(
                category: .streak,
                message: "🔥 \(currentStreak)-day reading streak! Outstanding commitment.",
                priority: 5,
                tip: "You're building a strong habit. Even a short session tomorrow keeps the streak alive."
            ))
        }

        // 6. Diversity drop
        let recentTopics = Set(recent.map { $0.topic })
        if recentTopics.count <= 1 && recent.count >= 5 {
            insights.append(CoachingInsight(
                category: .diversity,
                message: "You've only read about \"\(recentTopics.first ?? "one topic")\" this week.",
                priority: 3,
                tip: "Exploring different topics improves creative thinking. Try a feed you haven't visited lately."
            ))
        }

        // 7. Speed trend
        if recent.count >= 5 {
            let recentWpms = recent.map { $0.wordsPerMinute }.filter { $0 > 0 }
            let olderWpms = older.dropLast(recent.count).map { $0.wordsPerMinute }.filter { $0 > 0 }
            if !recentWpms.isEmpty && olderWpms.count >= 3 {
                let recentAvg = recentWpms.reduce(0, +) / Double(recentWpms.count)
                let olderAvg = olderWpms.reduce(0, +) / Double(olderWpms.count)
                if recentAvg > olderAvg * 1.15 {
                    insights.append(CoachingInsight(
                        category: .pacing,
                        message: "Your reading speed is trending up — \(Int(recentAvg)) wpm vs \(Int(olderAvg)) wpm previously.",
                        priority: 3,
                        tip: "Great improvement! Make sure comprehension is keeping up — try the quiz feature on a few articles."
                    ))
                }
            }
        }

        // 8. Focus score alert
        if recent.count >= 3 {
            let avgFocus = recent.map { focusScore(for: $0) }.reduce(0, +) / Double(recent.count)
            if avgFocus < 0.4 {
                insights.append(CoachingInsight(
                    category: .focus,
                    message: "Your focus score this week is \(Int(avgFocus * 100))% — below your usual.",
                    priority: 4,
                    tip: "Try shorter articles or use a timer to create focused reading blocks."
                ))
            } else if avgFocus > 0.8 {
                insights.append(CoachingInsight(
                    category: .focus,
                    message: "Excellent focus this week! Score: \(Int(avgFocus * 100))%.",
                    priority: 2,
                    tip: "You're in the zone — this would be a great time to tackle longer or more complex articles."
                ))
            }
        }

        // 9. Weekend vs weekday
        let weekday = recent.filter { !isWeekend($0.startTime) }
        let weekend = recent.filter { isWeekend($0.startTime) }
        if weekday.count >= 3 && weekend.count >= 2 {
            let wdAvg = Double(weekday.map { $0.durationSeconds }.reduce(0, +)) / Double(weekday.count)
            let weAvg = Double(weekend.map { $0.durationSeconds }.reduce(0, +)) / Double(weekend.count)
            if weAvg > wdAvg * 1.5 {
                insights.append(CoachingInsight(
                    category: .timing,
                    message: "You spend \(Int(weAvg / 60))min per session on weekends vs \(Int(wdAvg / 60))min on weekdays.",
                    priority: 2,
                    tip: "Save your longer, in-depth reads for weekends when you have more time."
                ))
            }
        }

        // 10. New feed exploration
        let allFeeds = Set(sessions.map { $0.feedTitle })
        let recentFeeds = Set(recent.map { $0.feedTitle })
        let neglected = allFeeds.subtracting(recentFeeds)
        if neglected.count >= 3 {
            let sample = Array(neglected.prefix(2)).joined(separator: ", ")
            insights.append(CoachingInsight(
                category: .diversity,
                message: "\(neglected.count) feeds haven't gotten attention lately, including \(sample).",
                priority: 2,
                tip: "Revisit a neglected feed — you subscribed for a reason!"
            ))
        }

        // 11. Short session pattern
        let shortSessions = recent.filter { $0.durationSeconds < 60 }
        if shortSessions.count > recent.count / 2 && recent.count >= 4 {
            insights.append(CoachingInsight(
                category: .pacing,
                message: "Most of your recent sessions are under 1 minute — you might be skimming.",
                priority: 3,
                tip: "Try committing to at least 3 minutes per article for better retention."
            ))
        }

        // 12. Long session fatigue
        let longSessions = recent.filter { $0.durationSeconds > 1800 }
        if longSessions.count >= 2 {
            let avgCompletion = longSessions.map { $0.completionPercent }.reduce(0, +) / Double(longSessions.count)
            if avgCompletion < 0.6 {
                insights.append(CoachingInsight(
                    category: .focus,
                    message: "Long sessions (30+ min) have only \(Int(avgCompletion * 100))% completion.",
                    priority: 3,
                    tip: "Break long reads into 15-minute chunks with short breaks for better focus."
                ))
            }
        }

        // 13. Topic growth opportunity
        let allTopics = Set(sessions.map { $0.topic })
        if allTopics.count >= 3 && recentTopics.count < allTopics.count / 2 {
            insights.append(CoachingInsight(
                category: .challenge,
                message: "You've explored \(allTopics.count) topics total but only \(recentTopics.count) recently.",
                priority: 2,
                tip: "Challenge yourself: pick one unfamiliar topic this week and read 3 articles about it."
            ))
        }

        // 14. Consistency nudge
        if currentStreak == 0 && sessions.count >= 10 {
            insights.append(CoachingInsight(
                category: .streak,
                message: "Your reading streak was broken. Time to start a new one!",
                priority: 4,
                tip: "Even reading one short article today restarts your streak."
            ))
        }

        // 15. Reading volume growth
        let thisWeekCount = recent.count
        let priorWeek = sessions.filter {
            let daysAgo = Calendar.current.dateComponents([.day], from: $0.startTime, to: Date()).day ?? 0
            return daysAgo >= 7 && daysAgo < 14
        }
        if thisWeekCount > priorWeek.count + 3 {
            insights.append(CoachingInsight(
                category: .growth,
                message: "You read \(thisWeekCount) articles this week vs \(priorWeek.count) last week — big jump!",
                priority: 3,
                tip: "Great momentum! Make sure quality stays high alongside quantity."
            ))
        }

        // Sort by priority descending, cap
        let sorted = insights.sorted { $0.priority > $1.priority }
        let result = Array(sorted.prefix(config.maxInsightsPerBatch))
        lastInsightDate = Date()
        save()

        if !result.isEmpty {
            NotificationCenter.default.post(name: .coachInsightGenerated, object: self,
                                            userInfo: ["insights": result])
        }

        return result
    }

    // MARK: - Goals

    func setGoal(_ goal: ReadingGoal) {
        // Replace existing goal of same type
        goals.removeAll { $0.type == goal.type }
        goals.append(goal)
        save()
    }

    func removeGoal(type: GoalType) {
        goals.removeAll { $0.type == type }
        save()
    }

    func checkGoals() -> [ReadingGoal] {
        let today = Calendar.current.startOfDay(for: Date())
        let todaySessions = sessions.filter { Calendar.current.isDate($0.startTime, inSameDayAs: today) }
        let weekSessions = recentSessions(days: 7)

        for i in goals.indices {
            guard goals[i].status == .active else { continue }
            switch goals[i].type {
            case .articlesPerDay:
                goals[i].current = Double(todaySessions.count)
            case .minutesPerDay:
                goals[i].current = Double(todaySessions.map { $0.durationSeconds }.reduce(0, +)) / 60.0
            case .topicsPerWeek:
                goals[i].current = Double(Set(weekSessions.map { $0.topic }).count)
            case .completionRate:
                if !todaySessions.isEmpty {
                    goals[i].current = todaySessions.map { $0.completionPercent }.reduce(0, +)
                        / Double(todaySessions.count)
                }
            case .streakDays:
                let (streak, _, _) = computeStreaks()
                goals[i].current = Double(streak)
            }

            if goals[i].current >= goals[i].target && goals[i].status == .active {
                goals[i].status = .achieved
                NotificationCenter.default.post(name: .coachGoalAchieved, object: self,
                                                userInfo: ["goal": goals[i]])
            }

            if let deadline = goals[i].deadline, Date() > deadline && goals[i].status == .active {
                goals[i].status = .missed
            }
        }

        save()
        return goals
    }

    // MARK: - Weekly Report

    func generateWeeklyReport() -> WeeklyReport {
        let calendar = Calendar.current
        let now = Date()
        let weekStart = calendar.date(byAdding: .day, value: -7, to: now)!
        let week = sessions.filter { $0.startTime >= weekStart }

        let totalMin = Double(week.map { $0.durationSeconds }.reduce(0, +)) / 60.0
        let completed = week.filter { $0.completionPercent > 0.8 }
        let avgCompletion = week.isEmpty ? 0 :
            week.map { $0.completionPercent }.reduce(0, +) / Double(week.count)
        let wpms = week.compactMap { $0.wordsPerMinute }.filter { $0 > 0 }
        let avgWpm = wpms.isEmpty ? 0 : wpms.reduce(0, +) / Double(wpms.count)
        let topTopics = Array(
            Dictionary(grouping: week, by: { $0.topic })
                .sorted { $0.value.count > $1.value.count }
                .prefix(3)
                .map { $0.key }
        )

        let insights = generateInsights()
        let profile = analyzeHabits()

        var achievements: [String] = []
        if profile.currentStreak >= 7 { achievements.append("📅 7+ day reading streak") }
        if completed.count >= 20 { achievements.append("📚 Read 20+ articles") }
        if avgCompletion > 0.85 { achievements.append("✅ 85%+ completion rate") }
        if avgWpm > 300 { achievements.append("⚡ Speed reader: \(Int(avgWpm)) wpm") }

        var recommendations: [String] = []
        if avgCompletion < 0.5 { recommendations.append("Focus on finishing articles — try shorter ones first.") }
        if topTopics.count <= 1 { recommendations.append("Diversify your reading — explore a new topic this week.") }
        if totalMin < 30 { recommendations.append("Try to read at least 5 minutes a day to build the habit.") }
        if profile.focusScore < 0.5 { recommendations.append("Your focus score is low — try dedicated reading blocks.") }

        let summary = """
        📊 Weekly Reading Report (\(formatDate(weekStart)) – \(formatDate(now)))
        Sessions: \(week.count) | Time: \(Int(totalMin)) min | Completed: \(completed.count)
        Avg completion: \(Int(avgCompletion * 100))% | Speed: \(Int(avgWpm)) wpm
        Streak: \(profile.currentStreak) days | Focus: \(Int(profile.focusScore * 100))%
        """

        return WeeklyReport(
            weekStart: weekStart, weekEnd: now,
            totalSessions: week.count, totalMinutes: totalMin,
            articlesCompleted: completed.count, avgCompletionRate: avgCompletion,
            avgWordsPerMinute: avgWpm, topTopics: topTopics,
            insights: insights, achievements: achievements,
            recommendations: recommendations, summary: summary
        )
    }

    // MARK: - Suggest Next Reads

    /// Suggests next reads from a list of story titles, scored by reading habit alignment.
    /// - Parameters:
    ///   - titles: Array of (title, feedName) tuples representing available articles.
    ///   - count: Maximum number of suggestions to return.
    /// - Returns: Ranked suggestions with reasons.
    func suggestNextReads(from titles: [(title: String, feed: String)], count: Int = 5) -> [(title: String, feed: String, reason: String)] {
        let profile = analyzeHabits()
        guard !titles.isEmpty else { return [] }

        var scored: [(title: String, feed: String, score: Double, reason: String)] = []

        for item in titles {
            var score = 0.5
            var reasons: [String] = []

            // Feed match
            if profile.topFeeds.contains(item.feed) {
                score += 0.2
                reasons.append("from a feed you enjoy")
            }

            // Time-appropriate
            let hour = Calendar.current.component(.hour, from: Date())
            if profile.peakHours.contains(hour) {
                score += 0.15
                reasons.append("it's your peak reading time")
            }

            // Diversity bonus
            if !profile.topFeeds.contains(item.feed) && profile.topFeeds.count >= 3 {
                score += 0.1
                reasons.append("diversifies your reading")
            }

            let reason = reasons.isEmpty ? "good match for your habits" : reasons.joined(separator: "; ")
            scored.append((title: item.title, feed: item.feed, score: score, reason: reason))
        }

        let sorted = scored.sorted { $0.score > $1.score }
        return Array(sorted.prefix(count).map { (title: $0.title, feed: $0.feed, reason: $0.reason) })
    }

    // MARK: - Helpers

    private func recentSessions(days: Int) -> [ReadingSession] {
        let cutoff = Calendar.current.date(byAdding: .day, value: -days, to: Date())!
        return sessions.filter { $0.startTime >= cutoff }
    }

    private func computeStreaks() -> (current: Int, longest: Int, consistency: Double) {
        guard !sessions.isEmpty else { return (0, 0, 0) }

        let calendar = Calendar.current
        let days = Set(sessions.map { calendar.startOfDay(for: $0.startTime) }).sorted()
        guard !days.isEmpty else { return (0, 0, 0) }

        var current = 1
        var longest = 1
        var streak = 1

        // Check if today continues the streak
        let today = calendar.startOfDay(for: Date())
        let lastDay = days.last!
        let daysSinceLast = calendar.dateComponents([.day], from: lastDay, to: today).day ?? 0
        let isCurrent = daysSinceLast <= 1

        for i in stride(from: days.count - 1, through: 1, by: -1) {
            let diff = calendar.dateComponents([.day], from: days[i - 1], to: days[i]).day ?? 0
            if diff == 1 {
                streak += 1
                longest = max(longest, streak)
            } else {
                longest = max(longest, streak)
                streak = 1
            }
        }
        longest = max(longest, streak)

        // Current streak: count backwards from most recent
        current = 1
        for i in stride(from: days.count - 1, through: 1, by: -1) {
            let diff = calendar.dateComponents([.day], from: days[i - 1], to: days[i]).day ?? 0
            if diff == 1 { current += 1 } else { break }
        }
        if !isCurrent { current = 0 }

        // Consistency: fraction of last 30 days with reading
        let thirtyAgo = calendar.date(byAdding: .day, value: -30, to: today)!
        let recentDays = days.filter { $0 >= thirtyAgo }
        let consistency = Double(recentDays.count) / 30.0

        return (current, longest, min(1.0, consistency))
    }

    private func isWeekend(_ date: Date) -> Bool {
        let weekday = Calendar.current.component(.weekday, from: date)
        return weekday == 1 || weekday == 7
    }

    private func formatDate(_ date: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "MMM d"
        return f.string(from: date)
    }

    private func checkStreakMilestones() {
        let (current, _, _) = computeStreaks()
        if config.streakMilestones.contains(current) {
            NotificationCenter.default.post(name: .coachStreakMilestone, object: self,
                                            userInfo: ["streak": current])
        }
    }

    private func updateGoalProgress(with session: ReadingSession) {
        _ = checkGoals()
    }

    // MARK: - Persistence

    private func save() {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        if let data = try? encoder.encode(sessions) {
            UserDefaults.standard.set(data, forKey: sessionsKey)
        }
        if let data = try? encoder.encode(goals) {
            UserDefaults.standard.set(data, forKey: goalsKey)
        }
        if let data = try? encoder.encode(config) {
            UserDefaults.standard.set(data, forKey: configKey)
        }
        if let date = lastInsightDate {
            UserDefaults.standard.set(date.timeIntervalSince1970, forKey: lastInsightKey)
        }
    }

    private func load() {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        if let data = UserDefaults.standard.data(forKey: sessionsKey),
           let loaded = try? decoder.decode([ReadingSession].self, from: data) {
            sessions = loaded
        }
        if let data = UserDefaults.standard.data(forKey: goalsKey),
           let loaded = try? decoder.decode([ReadingGoal].self, from: data) {
            goals = loaded
        }
        if let data = UserDefaults.standard.data(forKey: configKey),
           let loaded = try? decoder.decode(ReadingCoachConfig.self, from: data) {
            config = loaded
        }
        let ts = UserDefaults.standard.double(forKey: lastInsightKey)
        if ts > 0 { lastInsightDate = Date(timeIntervalSince1970: ts) }
    }

    /// Clears all coach data. Useful for testing.
    func reset() {
        sessions = []
        goals = []
        lastInsightDate = nil
        config = ReadingCoachConfig()
        save()
    }
}
