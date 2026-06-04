//
//  FeedReadingStreakEngine.swift
//  FeedReaderCore
//
//  Gamification engine for reading habits: streaks, achievements/badges,
//  milestone tracking, and motivational nudges. Encourages consistent
//  reading through visible progress and unlockable rewards.
//

import Foundation

// MARK: - Models

/// Represents a single reading session logged by the user.
public struct ReadingSession: Sendable {
    /// Unique identifier for the article read.
    public let articleId: String
    /// Feed source name.
    public let feedName: String
    /// Topic/category of the article.
    public let topic: String
    /// When the reading session started.
    public let startedAt: Date
    /// Duration in seconds.
    public let durationSeconds: Double
    /// Word count of the article.
    public let wordCount: Int

    public init(articleId: String, feedName: String, topic: String, startedAt: Date, durationSeconds: Double, wordCount: Int) {
        self.articleId = articleId
        self.feedName = feedName
        self.topic = topic
        self.startedAt = startedAt
        self.durationSeconds = durationSeconds
        self.wordCount = wordCount
    }
}

/// A reading streak period.
public struct StreakInfo: Sendable {
    /// Number of consecutive days with at least one reading session.
    public let currentStreak: Int
    /// Longest streak ever achieved.
    public let longestStreak: Int
    /// Whether the streak is still active (read today or yesterday).
    public let isActive: Bool
    /// Date the current streak started.
    public let streakStartDate: Date?
    /// Days until the next milestone streak (7, 14, 30, 60, 90, 180, 365).
    public let daysToNextMilestone: Int?
    /// The next milestone value.
    public let nextMilestone: Int?

    public init(currentStreak: Int, longestStreak: Int, isActive: Bool, streakStartDate: Date?, daysToNextMilestone: Int?, nextMilestone: Int?) {
        self.currentStreak = currentStreak
        self.longestStreak = longestStreak
        self.isActive = isActive
        self.streakStartDate = streakStartDate
        self.daysToNextMilestone = daysToNextMilestone
        self.nextMilestone = nextMilestone
    }
}

/// Achievement badge category.
public enum BadgeCategory: String, Sendable, CaseIterable {
    case streak = "streak"
    case volume = "volume"
    case diversity = "diversity"
    case speed = "speed"
    case dedication = "dedication"
    case exploration = "exploration"
}

/// A single achievement/badge earned by the user.
public struct Achievement: Sendable, Equatable {
    /// Unique identifier for the achievement.
    public let id: String
    /// Display name.
    public let name: String
    /// Description of how to earn it.
    public let description: String
    /// Badge category.
    public let category: BadgeCategory
    /// Emoji icon for display.
    public let icon: String
    /// When this achievement was unlocked (nil if locked).
    public let unlockedAt: Date?
    /// Progress toward unlocking (0.0 to 1.0).
    public let progress: Double
    /// Whether this achievement is unlocked.
    public var isUnlocked: Bool { unlockedAt != nil }

    public init(id: String, name: String, description: String, category: BadgeCategory, icon: String, unlockedAt: Date?, progress: Double) {
        self.id = id
        self.name = name
        self.description = description
        self.category = category
        self.icon = icon
        self.unlockedAt = unlockedAt
        self.progress = min(max(progress, 0.0), 1.0)
    }

    public static func == (lhs: Achievement, rhs: Achievement) -> Bool {
        return lhs.id == rhs.id
    }
}

/// Tier level for achievements that have multiple levels.
public enum AchievementTier: Int, Sendable, CaseIterable, Comparable {
    case bronze = 1
    case silver = 2
    case gold = 3
    case platinum = 4
    case diamond = 5

    public var label: String {
        switch self {
        case .bronze: return "Bronze"
        case .silver: return "Silver"
        case .gold: return "Gold"
        case .platinum: return "Platinum"
        case .diamond: return "Diamond"
        }
    }

    public static func < (lhs: AchievementTier, rhs: AchievementTier) -> Bool {
        return lhs.rawValue < rhs.rawValue
    }
}

/// A motivational nudge to encourage reading.
public struct Nudge: Sendable {
    public enum NudgeType: String, Sendable {
        case streakAtRisk = "streakAtRisk"
        case milestoneClose = "milestoneClose"
        case newBadgeAvailable = "newBadgeAvailable"
        case comeBack = "comeBack"
        case celebrate = "celebrate"
        case challenge = "challenge"
    }

    /// Type of nudge.
    public let type: NudgeType
    /// User-facing message.
    public let message: String
    /// Priority (1 = highest).
    public let priority: Int
    /// Relevant achievement ID if applicable.
    public let relatedAchievementId: String?

    public init(type: NudgeType, message: String, priority: Int, relatedAchievementId: String? = nil) {
        self.type = type
        self.message = message
        self.priority = priority
        self.relatedAchievementId = relatedAchievementId
    }
}

/// Summary statistics for the reading gamification.
public struct GamificationSummary: Sendable {
    /// Current streak info.
    public let streak: StreakInfo
    /// Total articles read all-time.
    public let totalArticlesRead: Int
    /// Total reading time in hours.
    public let totalReadingHours: Double
    /// Unique topics explored.
    public let uniqueTopics: Int
    /// Unique feeds read from.
    public let uniqueFeeds: Int
    /// Total words read.
    public let totalWordsRead: Int
    /// Unlocked achievements.
    public let unlockedAchievements: [Achievement]
    /// Locked achievements with progress.
    public let lockedAchievements: [Achievement]
    /// Active nudges sorted by priority.
    public let nudges: [Nudge]
    /// Current tier based on total achievements unlocked.
    public let tier: AchievementTier
    /// XP points (1 per article + bonus for streaks/achievements).
    public let xp: Int

    public init(streak: StreakInfo, totalArticlesRead: Int, totalReadingHours: Double, uniqueTopics: Int, uniqueFeeds: Int, totalWordsRead: Int, unlockedAchievements: [Achievement], lockedAchievements: [Achievement], nudges: [Nudge], tier: AchievementTier, xp: Int) {
        self.streak = streak
        self.totalArticlesRead = totalArticlesRead
        self.totalReadingHours = totalReadingHours
        self.uniqueTopics = uniqueTopics
        self.uniqueFeeds = uniqueFeeds
        self.totalWordsRead = totalWordsRead
        self.unlockedAchievements = unlockedAchievements
        self.lockedAchievements = lockedAchievements
        self.nudges = nudges
        self.tier = tier
        self.xp = xp
    }
}

// MARK: - Engine

/// Gamification engine that tracks reading streaks, computes achievements,
/// and generates motivational nudges based on reading history.
public final class FeedReadingStreakEngine: @unchecked Sendable {

    // MARK: - Configuration

    /// Streak milestone thresholds.
    public static let streakMilestones: [Int] = [3, 7, 14, 30, 60, 90, 180, 365]

    /// Article count milestones.
    public static let articleMilestones: [Int] = [10, 50, 100, 250, 500, 1000, 5000]

    /// Topic diversity milestones.
    public static let topicMilestones: [Int] = [3, 5, 10, 15, 25, 50]

    /// Reading hours milestones.
    public static let hoursMilestones: [Int] = [1, 5, 10, 25, 50, 100, 500]

    /// Words-per-minute thresholds for speed badges.
    public static let speedThresholds: [Int] = [200, 300, 400, 500]

    // MARK: - Properties

    private let calendar: Calendar
    private let now: () -> Date

    // MARK: - Initialization

    /// Creates a new streak engine.
    /// - Parameters:
    ///   - calendar: Calendar for date calculations (default: current).
    ///   - now: Clock function for testability (default: `Date()`).
    public init(calendar: Calendar = .current, now: @escaping () -> Date = { Date() }) {
        self.calendar = calendar
        self.now = now
    }

    // MARK: - Public API

    /// Computes the full gamification summary from reading sessions.
    /// - Parameter sessions: All recorded reading sessions.
    /// - Returns: A complete gamification summary with streak, achievements, and nudges.
    public func computeSummary(sessions: [ReadingSession]) -> GamificationSummary {
        let streak = computeStreak(sessions: sessions)
        let stats = computeStats(sessions: sessions)
        let achievements = computeAchievements(sessions: sessions, streak: streak, stats: stats)
        let nudges = computeNudges(streak: streak, achievements: achievements, stats: stats)
        let unlocked = achievements.filter { $0.isUnlocked }
        let locked = achievements.filter { !$0.isUnlocked }
        let tier = computeTier(unlockedCount: unlocked.count)
        let xp = computeXP(sessions: sessions, streak: streak, unlockedCount: unlocked.count)

        return GamificationSummary(
            streak: streak,
            totalArticlesRead: stats.totalArticles,
            totalReadingHours: stats.totalHours,
            uniqueTopics: stats.uniqueTopics,
            uniqueFeeds: stats.uniqueFeeds,
            totalWordsRead: stats.totalWords,
            unlockedAchievements: unlocked,
            lockedAchievements: locked,
            nudges: nudges.sorted { $0.priority < $1.priority },
            tier: tier,
            xp: xp
        )
    }

    /// Computes just the streak information.
    /// - Parameter sessions: All recorded reading sessions.
    /// - Returns: Streak details.
    public func computeStreak(sessions: [ReadingSession]) -> StreakInfo {
        guard !sessions.isEmpty else {
            return StreakInfo(currentStreak: 0, longestStreak: 0, isActive: false, streakStartDate: nil, daysToNextMilestone: nil, nextMilestone: nil)
        }

        let today = calendar.startOfDay(for: now())
        let readingDays = Set(sessions.map { calendar.startOfDay(for: $0.startedAt) }).sorted(by: >)

        guard !readingDays.isEmpty else {
            return StreakInfo(currentStreak: 0, longestStreak: 0, isActive: false, streakStartDate: nil, daysToNextMilestone: nil, nextMilestone: nil)
        }

        // Check if streak is active (read today or yesterday)
        let mostRecentDay = readingDays[0]
        let daysSinceLast = calendar.dateComponents([.day], from: mostRecentDay, to: today).day ?? 0
        let isActive = daysSinceLast <= 1

        // Compute current streak
        var currentStreak = 0
        var checkDate = isActive ? mostRecentDay : today
        if !isActive {
            // Streak is broken
            currentStreak = 0
        } else {
            let daySet = Set(readingDays)
            var d = mostRecentDay
            while daySet.contains(d) {
                currentStreak += 1
                guard let prevDay = calendar.date(byAdding: .day, value: -1, to: d) else { break }
                d = prevDay
            }
        }

        // Compute longest streak
        var longestStreak = 0
        var tempStreak = 1
        let sortedAsc = readingDays.sorted()
        for i in 1..<sortedAsc.count {
            let diff = calendar.dateComponents([.day], from: sortedAsc[i-1], to: sortedAsc[i]).day ?? 0
            if diff == 1 {
                tempStreak += 1
            } else {
                longestStreak = max(longestStreak, tempStreak)
                tempStreak = 1
            }
        }
        longestStreak = max(longestStreak, tempStreak)

        // Streak start date
        let streakStartDate: Date? = currentStreak > 0
            ? calendar.date(byAdding: .day, value: -(currentStreak - 1), to: mostRecentDay)
            : nil

        // Next milestone
        let nextMilestone = Self.streakMilestones.first { $0 > currentStreak }
        let daysToNext = nextMilestone.map { $0 - currentStreak }

        return StreakInfo(
            currentStreak: currentStreak,
            longestStreak: longestStreak,
            isActive: isActive,
            streakStartDate: streakStartDate,
            daysToNextMilestone: daysToNext,
            nextMilestone: nextMilestone
        )
    }

    /// Checks which achievements would be newly unlocked given an additional session.
    /// - Parameters:
    ///   - session: The new reading session.
    ///   - existingSessions: Previously recorded sessions.
    /// - Returns: Array of newly unlocked achievement IDs.
    public func checkNewUnlocks(session: ReadingSession, existingSessions: [ReadingSession]) -> [String] {
        let before = computeAchievements(
            sessions: existingSessions,
            streak: computeStreak(sessions: existingSessions),
            stats: computeStats(sessions: existingSessions)
        )
        let allSessions = existingSessions + [session]
        let after = computeAchievements(
            sessions: allSessions,
            streak: computeStreak(sessions: allSessions),
            stats: computeStats(sessions: allSessions)
        )

        let beforeUnlocked = Set(before.filter { $0.isUnlocked }.map { $0.id })
        let afterUnlocked = after.filter { $0.isUnlocked }.map { $0.id }
        return afterUnlocked.filter { !beforeUnlocked.contains($0) }
    }

    // MARK: - Private Helpers

    private struct Stats {
        let totalArticles: Int
        let totalHours: Double
        let totalWords: Int
        let uniqueTopics: Int
        let uniqueFeeds: Int
        let avgWPM: Double
        let topicSet: Set<String>
        let feedSet: Set<String>
    }

    private func computeStats(sessions: [ReadingSession]) -> Stats {
        let totalArticles = sessions.count
        let totalSeconds = sessions.reduce(0.0) { $0 + $1.durationSeconds }
        let totalHours = totalSeconds / 3600.0
        let totalWords = sessions.reduce(0) { $0 + $1.wordCount }
        let topicSet = Set(sessions.map { $0.topic })
        let feedSet = Set(sessions.map { $0.feedName })
        let avgWPM: Double
        if totalSeconds > 0 {
            avgWPM = Double(totalWords) / (totalSeconds / 60.0)
        } else {
            avgWPM = 0
        }
        return Stats(
            totalArticles: totalArticles,
            totalHours: totalHours,
            totalWords: totalWords,
            uniqueTopics: topicSet.count,
            uniqueFeeds: feedSet.count,
            avgWPM: avgWPM,
            topicSet: topicSet,
            feedSet: feedSet
        )
    }

    private func computeAchievements(sessions: [ReadingSession], streak: StreakInfo, stats: Stats) -> [Achievement] {
        let currentDate = now()
        var achievements: [Achievement] = []

        // Streak achievements
        for milestone in Self.streakMilestones {
            let best = max(streak.currentStreak, streak.longestStreak)
            let progress = min(Double(best) / Double(milestone), 1.0)
            let unlocked = best >= milestone
            achievements.append(Achievement(
                id: "streak_\(milestone)",
                name: streakName(milestone),
                description: "Maintain a \(milestone)-day reading streak",
                category: .streak,
                icon: streakIcon(milestone),
                unlockedAt: unlocked ? currentDate : nil,
                progress: progress
            ))
        }

        // Volume achievements
        for milestone in Self.articleMilestones {
            let progress = min(Double(stats.totalArticles) / Double(milestone), 1.0)
            let unlocked = stats.totalArticles >= milestone
            achievements.append(Achievement(
                id: "articles_\(milestone)",
                name: articleName(milestone),
                description: "Read \(milestone) articles",
                category: .volume,
                icon: "📚",
                unlockedAt: unlocked ? currentDate : nil,
                progress: progress
            ))
        }

        // Topic diversity achievements
        for milestone in Self.topicMilestones {
            let progress = min(Double(stats.uniqueTopics) / Double(milestone), 1.0)
            let unlocked = stats.uniqueTopics >= milestone
            achievements.append(Achievement(
                id: "topics_\(milestone)",
                name: topicName(milestone),
                description: "Explore \(milestone) different topics",
                category: .diversity,
                icon: "🌍",
                unlockedAt: unlocked ? currentDate : nil,
                progress: progress
            ))
        }

        // Speed reading achievements
        if stats.avgWPM > 0 {
            for threshold in Self.speedThresholds {
                let progress = min(stats.avgWPM / Double(threshold), 1.0)
                let unlocked = stats.avgWPM >= Double(threshold)
                achievements.append(Achievement(
                    id: "speed_\(threshold)",
                    name: speedName(threshold),
                    description: "Average reading speed of \(threshold)+ WPM",
                    category: .speed,
                    icon: "⚡",
                    unlockedAt: unlocked ? currentDate : nil,
                    progress: progress
                ))
            }
        }

        // Reading hours achievements
        for milestone in Self.hoursMilestones {
            let progress = min(stats.totalHours / Double(milestone), 1.0)
            let unlocked = stats.totalHours >= Double(milestone)
            achievements.append(Achievement(
                id: "hours_\(milestone)",
                name: hoursName(milestone),
                description: "Spend \(milestone) hours reading",
                category: .dedication,
                icon: "⏰",
                unlockedAt: unlocked ? currentDate : nil,
                progress: progress
            ))
        }

        // Exploration: feeds read from
        let feedMilestones = [3, 5, 10, 20]
        for milestone in feedMilestones {
            let progress = min(Double(stats.uniqueFeeds) / Double(milestone), 1.0)
            let unlocked = stats.uniqueFeeds >= milestone
            achievements.append(Achievement(
                id: "feeds_\(milestone)",
                name: feedExplorerName(milestone),
                description: "Read articles from \(milestone) different feeds",
                category: .exploration,
                icon: "🗺️",
                unlockedAt: unlocked ? currentDate : nil,
                progress: progress
            ))
        }

        // Special: Weekend warrior (read on both Saturday and Sunday)
        let weekendDays = sessions.filter { session in
            let weekday = calendar.component(.weekday, from: session.startedAt)
            return weekday == 1 || weekday == 7 // Sunday or Saturday
        }
        let weekendDaySet = Set(weekendDays.map { calendar.component(.weekday, from: $0.startedAt) })
        let hasWeekendWarrior = weekendDaySet.count >= 2
        achievements.append(Achievement(
            id: "weekend_warrior",
            name: "Weekend Warrior",
            description: "Read on both Saturday and Sunday",
            category: .dedication,
            icon: "🏆",
            unlockedAt: hasWeekendWarrior ? currentDate : nil,
            progress: Double(weekendDaySet.count) / 2.0
        ))

        // Special: Night Owl (read after 11 PM)
        let nightSessions = sessions.filter { session in
            let hour = calendar.component(.hour, from: session.startedAt)
            return hour >= 23 || hour < 4
        }
        let hasNightOwl = nightSessions.count >= 5
        achievements.append(Achievement(
            id: "night_owl",
            name: "Night Owl",
            description: "Read 5 articles between 11 PM and 4 AM",
            category: .dedication,
            icon: "🦉",
            unlockedAt: hasNightOwl ? currentDate : nil,
            progress: min(Double(nightSessions.count) / 5.0, 1.0)
        ))

        // Special: Early Bird (read before 7 AM)
        let earlySessions = sessions.filter { session in
            let hour = calendar.component(.hour, from: session.startedAt)
            return hour >= 5 && hour < 7
        }
        let hasEarlyBird = earlySessions.count >= 5
        achievements.append(Achievement(
            id: "early_bird",
            name: "Early Bird",
            description: "Read 5 articles between 5 AM and 7 AM",
            category: .dedication,
            icon: "🐦",
            unlockedAt: hasEarlyBird ? currentDate : nil,
            progress: min(Double(earlySessions.count) / 5.0, 1.0)
        ))

        return achievements
    }

    private func computeNudges(streak: StreakInfo, achievements: [Achievement], stats: Stats) -> [Nudge] {
        var nudges: [Nudge] = []

        // Streak at risk
        if streak.isActive && streak.currentStreak >= 3 {
            let today = calendar.startOfDay(for: now())
            // If they haven't read today, warn them
            nudges.append(Nudge(
                type: .streakAtRisk,
                message: "🔥 Your \(streak.currentStreak)-day streak is going strong! Keep it alive today.",
                priority: 1
            ))
        }

        // Close to milestone
        if let daysToNext = streak.daysToNextMilestone, let next = streak.nextMilestone, daysToNext <= 3, streak.isActive {
            nudges.append(Nudge(
                type: .milestoneClose,
                message: "🎯 Just \(daysToNext) day\(daysToNext == 1 ? "" : "s") away from a \(next)-day streak!",
                priority: 2,
                relatedAchievementId: "streak_\(next)"
            ))
        }

        // Nearly unlocked achievements
        let nearlyUnlocked = achievements.filter { !$0.isUnlocked && $0.progress >= 0.8 }
        for achievement in nearlyUnlocked.prefix(2) {
            nudges.append(Nudge(
                type: .newBadgeAvailable,
                message: "\(achievement.icon) Almost there! \(achievement.name) is \(Int(achievement.progress * 100))% complete.",
                priority: 3,
                relatedAchievementId: achievement.id
            ))
        }

        // Come back nudge when streak is broken
        if !streak.isActive && streak.longestStreak >= 3 {
            nudges.append(Nudge(
                type: .comeBack,
                message: "📖 Your best streak was \(streak.longestStreak) days. Start a new one today!",
                priority: 4
            ))
        }

        // Celebrate when streak hits milestone
        if streak.isActive && Self.streakMilestones.contains(streak.currentStreak) {
            nudges.append(Nudge(
                type: .celebrate,
                message: "🎉 Amazing! You've hit a \(streak.currentStreak)-day reading streak!",
                priority: 1,
                relatedAchievementId: "streak_\(streak.currentStreak)"
            ))
        }

        // Challenge: try a new topic
        if stats.totalArticles >= 10 && stats.uniqueTopics < 3 {
            nudges.append(Nudge(
                type: .challenge,
                message: "🌟 Challenge: Try reading an article from a new topic today!",
                priority: 5
            ))
        }

        return nudges
    }

    private func computeTier(unlockedCount: Int) -> AchievementTier {
        switch unlockedCount {
        case 0..<5: return .bronze
        case 5..<12: return .silver
        case 12..<20: return .gold
        case 20..<30: return .platinum
        default: return .diamond
        }
    }

    private func computeXP(sessions: [ReadingSession], streak: StreakInfo, unlockedCount: Int) -> Int {
        var xp = sessions.count  // 1 XP per article
        xp += streak.currentStreak * 2  // 2 XP per streak day
        xp += streak.longestStreak * 3  // 3 XP for longest streak days
        xp += unlockedCount * 10  // 10 XP per achievement
        return xp
    }

    // MARK: - Name Helpers

    private func streakName(_ days: Int) -> String {
        switch days {
        case 3: return "Getting Started"
        case 7: return "Week Warrior"
        case 14: return "Fortnight Focus"
        case 30: return "Monthly Maven"
        case 60: return "Devoted Reader"
        case 90: return "Quarter Champion"
        case 180: return "Half-Year Hero"
        case 365: return "Year of Reading"
        default: return "\(days)-Day Streak"
        }
    }

    private func streakIcon(_ days: Int) -> String {
        switch days {
        case 3...7: return "🔥"
        case 8...30: return "💪"
        case 31...90: return "🏅"
        case 91...180: return "🏆"
        default: return "👑"
        }
    }

    private func articleName(_ count: Int) -> String {
        switch count {
        case 10: return "First Steps"
        case 50: return "Avid Reader"
        case 100: return "Century Reader"
        case 250: return "Bookworm"
        case 500: return "Knowledge Seeker"
        case 1000: return "Thousand Tales"
        case 5000: return "Living Library"
        default: return "\(count) Articles"
        }
    }

    private func topicName(_ count: Int) -> String {
        switch count {
        case 3: return "Curious Mind"
        case 5: return "Topic Explorer"
        case 10: return "Renaissance Reader"
        case 15: return "Polymath"
        case 25: return "Knowledge Web"
        case 50: return "Universal Scholar"
        default: return "\(count) Topics"
        }
    }

    private func speedName(_ wpm: Int) -> String {
        switch wpm {
        case 200: return "Steady Reader"
        case 300: return "Quick Scanner"
        case 400: return "Speed Reader"
        case 500: return "Lightning Eyes"
        default: return "\(wpm) WPM"
        }
    }

    private func hoursName(_ hours: Int) -> String {
        switch hours {
        case 1: return "First Hour"
        case 5: return "Five Hours In"
        case 10: return "Time Well Spent"
        case 25: return "Dedicated Reader"
        case 50: return "Reading Marathon"
        case 100: return "Centurion"
        case 500: return "Reading Legend"
        default: return "\(hours) Hours"
        }
    }

    private func feedExplorerName(_ count: Int) -> String {
        switch count {
        case 3: return "Source Sampler"
        case 5: return "Feed Explorer"
        case 10: return "Information Hunter"
        case 20: return "Feed Connoisseur"
        default: return "\(count) Feeds"
        }
    }
}
