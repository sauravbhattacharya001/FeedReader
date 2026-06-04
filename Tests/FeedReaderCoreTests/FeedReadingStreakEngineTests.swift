//
//  FeedReadingStreakEngineTests.swift
//  FeedReaderCoreTests
//
//  Tests for the reading streak & gamification engine.
//

import XCTest
@testable import FeedReaderCore

final class FeedReadingStreakEngineTests: XCTestCase {

    // MARK: - Helpers

    private var fixedDate: Date!
    private var calendar: Calendar!
    private var engine: FeedReadingStreakEngine!

    override func setUp() {
        super.setUp()
        calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        // June 4, 2026 at noon UTC
        var components = DateComponents()
        components.year = 2026
        components.month = 6
        components.day = 4
        components.hour = 12
        fixedDate = calendar.date(from: components)!
        engine = FeedReadingStreakEngine(calendar: calendar, now: { [unowned self] in self.fixedDate })
    }

    private func makeSession(daysAgo: Int, topic: String = "tech", feed: String = "TechCrunch", wordCount: Int = 500, duration: Double = 180.0, hour: Int? = nil) -> ReadingSession {
        var date = calendar.date(byAdding: .day, value: -daysAgo, to: fixedDate)!
        if let h = hour {
            date = calendar.date(bySettingHour: h, minute: 30, second: 0, of: date)!
        }
        return ReadingSession(
            articleId: "art_\(daysAgo)_\(topic)_\(UUID().uuidString.prefix(4))",
            feedName: feed,
            topic: topic,
            startedAt: date,
            durationSeconds: duration,
            wordCount: wordCount
        )
    }

    // MARK: - Streak Tests

    func testEmptySessionsReturnsZeroStreak() {
        let streak = engine.computeStreak(sessions: [])
        XCTAssertEqual(streak.currentStreak, 0)
        XCTAssertEqual(streak.longestStreak, 0)
        XCTAssertFalse(streak.isActive)
        XCTAssertNil(streak.streakStartDate)
    }

    func testSingleSessionTodayGivesStreakOfOne() {
        let sessions = [makeSession(daysAgo: 0)]
        let streak = engine.computeStreak(sessions: sessions)
        XCTAssertEqual(streak.currentStreak, 1)
        XCTAssertEqual(streak.longestStreak, 1)
        XCTAssertTrue(streak.isActive)
        XCTAssertNotNil(streak.streakStartDate)
    }

    func testConsecutiveDaysFormStreak() {
        let sessions = (0...6).map { makeSession(daysAgo: $0) }
        let streak = engine.computeStreak(sessions: sessions)
        XCTAssertEqual(streak.currentStreak, 7)
        XCTAssertEqual(streak.longestStreak, 7)
        XCTAssertTrue(streak.isActive)
    }

    func testBrokenStreakResetsCurrentButKeepsLongest() {
        // Read days 5,4,3 (3-day streak in the past) then gap, then day 0
        let sessions = [
            makeSession(daysAgo: 0),
            makeSession(daysAgo: 5),
            makeSession(daysAgo: 4),
            makeSession(daysAgo: 3),
        ]
        let streak = engine.computeStreak(sessions: sessions)
        XCTAssertEqual(streak.currentStreak, 1) // Only today
        XCTAssertEqual(streak.longestStreak, 3) // Days 5-4-3
        XCTAssertTrue(streak.isActive)
    }

    func testStreakInactiveWhenLastReadTwoDaysAgo() {
        let sessions = [makeSession(daysAgo: 2)]
        let streak = engine.computeStreak(sessions: sessions)
        XCTAssertEqual(streak.currentStreak, 0)
        XCTAssertFalse(streak.isActive)
    }

    func testNextMilestoneCalculation() {
        // 5-day streak -> next milestone is 7, 2 days away
        let sessions = (0...4).map { makeSession(daysAgo: $0) }
        let streak = engine.computeStreak(sessions: sessions)
        XCTAssertEqual(streak.currentStreak, 5)
        XCTAssertEqual(streak.nextMilestone, 7)
        XCTAssertEqual(streak.daysToNextMilestone, 2)
    }

    func testMultipleSessionsSameDayCountAsOneStreakDay() {
        let sessions = [
            makeSession(daysAgo: 0, topic: "tech"),
            makeSession(daysAgo: 0, topic: "science"),
            makeSession(daysAgo: 0, topic: "art"),
        ]
        let streak = engine.computeStreak(sessions: sessions)
        XCTAssertEqual(streak.currentStreak, 1)
    }

    // MARK: - Achievement Tests

    func testArticleMilestoneUnlocked() {
        let sessions = (0..<50).map { makeSession(daysAgo: $0 % 10) }
        let summary = engine.computeSummary(sessions: sessions)
        let articlesAchievement = summary.unlockedAchievements.first { $0.id == "articles_50" }
        XCTAssertNotNil(articlesAchievement)
        XCTAssertEqual(articlesAchievement?.name, "Avid Reader")
    }

    func testTopicDiversityAchievement() {
        let topics = ["tech", "science", "politics", "sports", "health"]
        let sessions = topics.map { makeSession(daysAgo: 0, topic: $0) }
        let summary = engine.computeSummary(sessions: sessions)
        let topicAch = summary.unlockedAchievements.first { $0.id == "topics_5" }
        XCTAssertNotNil(topicAch)
        XCTAssertEqual(topicAch?.name, "Topic Explorer")
    }

    func testSpeedAchievementUnlocked() {
        // 500 words in 60 seconds = 500 WPM
        let sessions = [ReadingSession(
            articleId: "fast1", feedName: "Feed", topic: "tech",
            startedAt: fixedDate, durationSeconds: 60, wordCount: 500
        )]
        let summary = engine.computeSummary(sessions: sessions)
        let speedAch = summary.unlockedAchievements.first { $0.id == "speed_500" }
        XCTAssertNotNil(speedAch)
        XCTAssertEqual(speedAch?.name, "Lightning Eyes")
    }

    func testWeekendWarriorAchievement() {
        // June 4, 2026 is Thursday. Saturday = June 6 is +2, Sunday = May 31 is -4
        // Let's compute exact weekend dates
        var satComponents = DateComponents()
        satComponents.year = 2026
        satComponents.month = 5
        satComponents.day = 30 // Saturday
        satComponents.hour = 10
        let saturday = calendar.date(from: satComponents)!

        var sunComponents = DateComponents()
        sunComponents.year = 2026
        sunComponents.month = 5
        sunComponents.day = 31 // Sunday
        sunComponents.hour = 10
        let sunday = calendar.date(from: sunComponents)!

        let sessions = [
            ReadingSession(articleId: "sat1", feedName: "Feed", topic: "tech", startedAt: saturday, durationSeconds: 120, wordCount: 300),
            ReadingSession(articleId: "sun1", feedName: "Feed", topic: "tech", startedAt: sunday, durationSeconds: 120, wordCount: 300),
        ]
        let summary = engine.computeSummary(sessions: sessions)
        let weekendAch = summary.unlockedAchievements.first { $0.id == "weekend_warrior" }
        XCTAssertNotNil(weekendAch)
    }

    func testNightOwlAchievement() {
        let sessions = (0..<5).map { makeSession(daysAgo: $0, hour: 23) }
        let summary = engine.computeSummary(sessions: sessions)
        let nightOwl = summary.unlockedAchievements.first { $0.id == "night_owl" }
        XCTAssertNotNil(nightOwl)
        XCTAssertEqual(nightOwl?.name, "Night Owl")
    }

    func testEarlyBirdAchievement() {
        let sessions = (0..<5).map { makeSession(daysAgo: $0, hour: 6) }
        let summary = engine.computeSummary(sessions: sessions)
        let earlyBird = summary.unlockedAchievements.first { $0.id == "early_bird" }
        XCTAssertNotNil(earlyBird)
        XCTAssertEqual(earlyBird?.name, "Early Bird")
    }

    func testProgressTrackedForLockedAchievements() {
        let sessions = (0..<3).map { makeSession(daysAgo: $0) }
        let summary = engine.computeSummary(sessions: sessions)
        let locked50 = summary.lockedAchievements.first { $0.id == "articles_50" }
        XCTAssertNotNil(locked50)
        XCTAssertEqual(locked50!.progress, 3.0 / 50.0, accuracy: 0.001)
    }

    // MARK: - Nudge Tests

    func testStreakAtRiskNudgeGenerated() {
        // Active 5-day streak
        let sessions = (0...4).map { makeSession(daysAgo: $0) }
        let summary = engine.computeSummary(sessions: sessions)
        let streakNudge = summary.nudges.first { $0.type == .streakAtRisk }
        XCTAssertNotNil(streakNudge)
        XCTAssertTrue(streakNudge!.message.contains("5-day"))
    }

    func testMilestoneCloseNudge() {
        // 6-day streak, 1 day from 7
        let sessions = (0...5).map { makeSession(daysAgo: $0) }
        let summary = engine.computeSummary(sessions: sessions)
        let milestoneNudge = summary.nudges.first { $0.type == .milestoneClose }
        XCTAssertNotNil(milestoneNudge)
        XCTAssertTrue(milestoneNudge!.message.contains("1 day"))
    }

    func testCelebrateNudgeOnMilestone() {
        // Exactly 7-day streak
        let sessions = (0...6).map { makeSession(daysAgo: $0) }
        let summary = engine.computeSummary(sessions: sessions)
        let celebrateNudge = summary.nudges.first { $0.type == .celebrate }
        XCTAssertNotNil(celebrateNudge)
        XCTAssertTrue(celebrateNudge!.message.contains("7-day"))
    }

    func testComeBackNudgeWhenStreakBroken() {
        // Had a 5-day streak in the past, not active now
        let sessions = (3...7).map { makeSession(daysAgo: $0) }
        let summary = engine.computeSummary(sessions: sessions)
        let comeBack = summary.nudges.first { $0.type == .comeBack }
        XCTAssertNotNil(comeBack)
        XCTAssertTrue(comeBack!.message.contains("5 days"))
    }

    func testChallengeNudgeForLowDiversity() {
        // 15 articles, all same topic
        let sessions = (0..<15).map { makeSession(daysAgo: $0 % 5, topic: "tech") }
        let summary = engine.computeSummary(sessions: sessions)
        let challenge = summary.nudges.first { $0.type == .challenge }
        XCTAssertNotNil(challenge)
    }

    // MARK: - Tier and XP Tests

    func testBronzeTierWithFewAchievements() {
        let sessions = [makeSession(daysAgo: 0)]
        let summary = engine.computeSummary(sessions: sessions)
        XCTAssertEqual(summary.tier, .bronze)
    }

    func testXPCalculation() {
        let sessions = (0...6).map { makeSession(daysAgo: $0) }
        let summary = engine.computeSummary(sessions: sessions)
        // 7 articles (7 XP) + 7 streak * 2 (14 XP) + 7 longest * 3 (21 XP) + achievements * 10
        let expectedBase = 7 + 14 + 21
        XCTAssertTrue(summary.xp >= expectedBase)
    }

    func testStatsSummary() {
        let sessions = [
            makeSession(daysAgo: 0, topic: "tech", feed: "TechCrunch", wordCount: 1000, duration: 300),
            makeSession(daysAgo: 1, topic: "science", feed: "BBC Science", wordCount: 800, duration: 240),
        ]
        let summary = engine.computeSummary(sessions: sessions)
        XCTAssertEqual(summary.totalArticlesRead, 2)
        XCTAssertEqual(summary.totalWordsRead, 1800)
        XCTAssertEqual(summary.uniqueTopics, 2)
        XCTAssertEqual(summary.uniqueFeeds, 2)
        XCTAssertEqual(summary.totalReadingHours, 540.0 / 3600.0, accuracy: 0.001)
    }

    // MARK: - New Unlock Detection

    func testCheckNewUnlocksDetectsNewAchievement() {
        let existing = (0..<9).map { makeSession(daysAgo: $0 % 3, topic: "tech") }
        let newSession = makeSession(daysAgo: 0, topic: "tech")
        let newUnlocks = engine.checkNewUnlocks(session: newSession, existingSessions: existing)
        // Should unlock articles_10 (going from 9 to 10)
        XCTAssertTrue(newUnlocks.contains("articles_10"))
    }

    func testCheckNewUnlocksEmptyWhenNoNewBadge() {
        let existing = [makeSession(daysAgo: 0)]
        let newSession = makeSession(daysAgo: 0, topic: "tech")
        let newUnlocks = engine.checkNewUnlocks(session: newSession, existingSessions: existing)
        // Going from 1 to 2 articles doesn't hit any milestone
        XCTAssertFalse(newUnlocks.contains("articles_10"))
    }

    // MARK: - Edge Cases

    func testFeedExplorerAchievement() {
        let feeds = ["A", "B", "C", "D", "E"]
        let sessions = feeds.map { makeSession(daysAgo: 0, feed: $0) }
        let summary = engine.computeSummary(sessions: sessions)
        let feedAch = summary.unlockedAchievements.first { $0.id == "feeds_5" }
        XCTAssertNotNil(feedAch)
        XCTAssertEqual(feedAch?.name, "Feed Explorer")
    }

    func testHoursAchievementUnlocked() {
        // 1 hour = 3600 seconds
        let sessions = [ReadingSession(
            articleId: "long1", feedName: "Feed", topic: "tech",
            startedAt: fixedDate, durationSeconds: 3600, wordCount: 10000
        )]
        let summary = engine.computeSummary(sessions: sessions)
        let hoursAch = summary.unlockedAchievements.first { $0.id == "hours_1" }
        XCTAssertNotNil(hoursAch)
        XCTAssertEqual(hoursAch?.name, "First Hour")
    }

    func testNudgesSortedByPriority() {
        let sessions = (0...5).map { makeSession(daysAgo: $0) }
        let summary = engine.computeSummary(sessions: sessions)
        let priorities = summary.nudges.map { $0.priority }
        XCTAssertEqual(priorities, priorities.sorted())
    }

    func testAchievementProgressClampedZeroToOne() {
        let achievement = Achievement(
            id: "test", name: "Test", description: "Test",
            category: .streak, icon: "🔥",
            unlockedAt: nil, progress: 1.5
        )
        XCTAssertEqual(achievement.progress, 1.0)

        let achievementNeg = Achievement(
            id: "test2", name: "Test", description: "Test",
            category: .streak, icon: "🔥",
            unlockedAt: nil, progress: -0.5
        )
        XCTAssertEqual(achievementNeg.progress, 0.0)
    }
}
