//
//  ReadingGoalsTrackerTests.swift
//  FeedReaderTests
//

import XCTest
@testable import FeedReader

final class ReadingGoalsTrackerTests: XCTestCase {
    
    var tracker: ReadingGoalsTracker!
    var tempDir: URL!
    var calendar: Calendar!
    
    override func setUp() {
        super.setUp()
        tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try! FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        calendar = Calendar.current
        tracker = ReadingGoalsTracker(directory: tempDir, calendar: calendar)
    }
    
    override func tearDown() {
        try? FileManager.default.removeItem(at: tempDir)
        super.tearDown()
    }
    
    // MARK: - Goal Management
    
    func testSetGoal() {
        let goal = tracker.setGoal(period: .daily, target: 5)
        XCTAssertEqual(goal.period, .daily)
        XCTAssertEqual(goal.target, 5)
        XCTAssertTrue(goal.isActive)
        XCTAssertEqual(tracker.goals.count, 1)
    }
    
    func testSetGoalMinimumTarget() {
        let goal = tracker.setGoal(period: .daily, target: 0)
        XCTAssertEqual(goal.target, 1, "Target should be at least 1")
    }
    
    func testUpdateGoal() {
        tracker.setGoal(period: .daily, target: 3)
        tracker.setGoal(period: .daily, target: 7)
        XCTAssertEqual(tracker.goals.count, 1)
        XCTAssertEqual(tracker.goals.first?.target, 7)
    }
    
    func testRemoveGoal() {
        tracker.setGoal(period: .daily, target: 3)
        tracker.removeGoal(period: .daily)
        XCTAssertTrue(tracker.goals.isEmpty)
    }
    
    func testToggleGoal() {
        tracker.setGoal(period: .weekly, target: 10)
        tracker.toggleGoal(period: .weekly, active: false)
        XCTAssertEqual(tracker.goals.first?.isActive, false)
    }
    
    func testMultipleGoals() {
        tracker.setGoal(period: .daily, target: 3)
        tracker.setGoal(period: .weekly, target: 15)
        tracker.setGoal(period: .monthly, target: 50)
        XCTAssertEqual(tracker.goals.count, 3)
    }
    
    // MARK: - Reading Log
    
    func testLogArticle() {
        tracker.logArticleRead(articleId: "art-1", feedTitle: "Tech Blog")
        XCTAssertEqual(tracker.readingLog.count, 1)
        XCTAssertEqual(tracker.totalArticlesRead, 1)
    }
    
    func testArticlesReadOnDate() {
        let today = Date()
        tracker.logArticleRead(articleId: "a1", date: today)
        tracker.logArticleRead(articleId: "a2", date: today)
        XCTAssertEqual(tracker.articlesRead(on: today), 2)
    }
    
    func testArticlesReadDifferentDays() {
        let today = Date()
        let yesterday = calendar.date(byAdding: .day, value: -1, to: today)!
        tracker.logArticleRead(articleId: "a1", date: today)
        tracker.logArticleRead(articleId: "a2", date: yesterday)
        XCTAssertEqual(tracker.articlesRead(on: today), 1)
        XCTAssertEqual(tracker.articlesRead(on: yesterday), 1)
    }
    
    func testArticlesReadThisWeek() {
        let today = Date()
        tracker.logArticleRead(articleId: "a1", date: today)
        tracker.logArticleRead(articleId: "a2", date: today)
        XCTAssertGreaterThanOrEqual(tracker.articlesReadThisWeek(from: today), 2)
    }
    
    func testArticlesReadThisMonth() {
        let today = Date()
        tracker.logArticleRead(articleId: "a1", date: today)
        XCTAssertGreaterThanOrEqual(tracker.articlesReadThisMonth(from: today), 1)
    }
    
    // MARK: - Progress
    
    func testCurrentProgress() {
        tracker.setGoal(period: .daily, target: 3)
        tracker.logArticleRead(articleId: "a1")
        let progress = tracker.currentProgress()
        XCTAssertEqual(progress.count, 1)
        XCTAssertEqual(progress.first?.current, 1)
        XCTAssertEqual(progress.first?.target, 3)
        XCTAssertFalse(progress.first?.isComplete ?? true)
    }
    
    func testProgressPercentage() {
        tracker.setGoal(period: .daily, target: 4)
        tracker.logArticleRead(articleId: "a1")
        tracker.logArticleRead(articleId: "a2")
        let p = tracker.progress(for: .daily)!
        XCTAssertEqual(p.percentage, 50.0, accuracy: 0.1)
    }
    
    func testProgressComplete() {
        tracker.setGoal(period: .daily, target: 2)
        tracker.logArticleRead(articleId: "a1")
        tracker.logArticleRead(articleId: "a2")
        let p = tracker.progress(for: .daily)!
        XCTAssertTrue(p.isComplete)
        XCTAssertEqual(p.percentage, 100.0, accuracy: 0.1)
    }
    
    func testProgressCapsAt100() {
        tracker.setGoal(period: .daily, target: 1)
        tracker.logArticleRead(articleId: "a1")
        tracker.logArticleRead(articleId: "a2")
        tracker.logArticleRead(articleId: "a3")
        let p = tracker.progress(for: .daily)!
        XCTAssertEqual(p.percentage, 100.0, accuracy: 0.1)
    }
    
    func testProgressForInactiveGoalReturnsNil() {
        tracker.setGoal(period: .daily, target: 5)
        tracker.toggleGoal(period: .daily, active: false)
        XCTAssertNil(tracker.progress(for: .daily))
    }
    
    // MARK: - Streaks
    
    func testStreakStartsAtOne() {
        tracker.logArticleRead(articleId: "a1")
        XCTAssertEqual(tracker.currentStreak, 1)
    }
    
    func testStreakIncrementsOnConsecutiveDays() {
        let today = Date()
        let yesterday = calendar.date(byAdding: .day, value: -1, to: today)!
        tracker.logArticleRead(articleId: "a1", date: yesterday)
        tracker.logArticleRead(articleId: "a2", date: today)
        XCTAssertEqual(tracker.currentStreak, 2)
    }
    
    func testStreakResetsOnGap() {
        let today = Date()
        let twoDaysAgo = calendar.date(byAdding: .day, value: -2, to: today)!
        tracker.logArticleRead(articleId: "a1", date: twoDaysAgo)
        tracker.logArticleRead(articleId: "a2", date: today)
        XCTAssertEqual(tracker.currentStreak, 1)
    }
    
    func testBestStreakTracked() {
        let today = Date()
        let d1 = calendar.date(byAdding: .day, value: -3, to: today)!
        let d2 = calendar.date(byAdding: .day, value: -2, to: today)!
        let d3 = calendar.date(byAdding: .day, value: -1, to: today)!
        tracker.logArticleRead(articleId: "a1", date: d1)
        tracker.logArticleRead(articleId: "a2", date: d2)
        tracker.logArticleRead(articleId: "a3", date: d3)
        XCTAssertEqual(tracker.bestStreak, 3)
        // Gap then new read
        tracker.logArticleRead(articleId: "a4", date: calendar.date(byAdding: .day, value: 2, to: today)!)
        XCTAssertEqual(tracker.currentStreak, 1)
        XCTAssertEqual(tracker.bestStreak, 3)
    }
    
    func testSameDayDoesNotDoubleStreak() {
        tracker.logArticleRead(articleId: "a1")
        tracker.logArticleRead(articleId: "a2")
        XCTAssertEqual(tracker.currentStreak, 1)
    }
    
    // MARK: - Badges
    
    func testNoBadgesInitially() {
        XCTAssertTrue(tracker.badges.isEmpty)
    }
    
    func testBadgeEarnedAt7DayStreak() {
        let today = Date()
        for i in (0..<7).reversed() {
            let day = calendar.date(byAdding: .day, value: -i, to: today)!
            tracker.logArticleRead(articleId: "a\(i)", date: day)
        }
        XCTAssertEqual(tracker.currentStreak, 7)
        XCTAssertTrue(tracker.badges.contains(where: { $0.streakRequired == 7 }))
    }
    
    // MARK: - Period Completion
    
    func testRecordPeriodCompletion() {
        tracker.setGoal(period: .daily, target: 2)
        tracker.logArticleRead(articleId: "a1")
        tracker.logArticleRead(articleId: "a2")
        tracker.recordPeriodCompletion(period: .daily)
        XCTAssertEqual(tracker.completionHistory.count, 1)
        XCTAssertTrue(tracker.completionHistory.first?.completed ?? false)
    }
    
    func testCompletionRateCalculation() {
        tracker.setGoal(period: .daily, target: 1)
        tracker.logArticleRead(articleId: "a1")
        tracker.recordPeriodCompletion(period: .daily)
        let rate = tracker.completionRate(for: .daily)
        XCTAssertEqual(rate, 100.0, accuracy: 0.1)
    }
    
    func testNoDuplicateCompletion() {
        tracker.setGoal(period: .daily, target: 1)
        tracker.logArticleRead(articleId: "a1")
        tracker.recordPeriodCompletion(period: .daily)
        tracker.recordPeriodCompletion(period: .daily)
        XCTAssertEqual(tracker.completionHistory.count, 1)
    }
    
    // MARK: - Analytics
    
    func testDailyReadCounts() {
        let today = Date()
        tracker.logArticleRead(articleId: "a1", date: today)
        let counts = tracker.dailyReadCounts(days: 7, from: today)
        XCTAssertEqual(counts.count, 7)
        XCTAssertEqual(counts.last?.1, 1)
    }
    
    func testTopFeeds() {
        tracker.logArticleRead(articleId: "a1", feedTitle: "Tech")
        tracker.logArticleRead(articleId: "a2", feedTitle: "Tech")
        tracker.logArticleRead(articleId: "a3", feedTitle: "News")
        let top = tracker.topFeeds()
        XCTAssertEqual(top.first?.feed, "Tech")
        XCTAssertEqual(top.first?.count, 2)
    }
    
    // MARK: - Export
    
    func testExportJSON() {
        tracker.setGoal(period: .daily, target: 3)
        tracker.logArticleRead(articleId: "a1", feedTitle: "Blog")
        let json = tracker.exportJSON()
        XCTAssertTrue(json.contains("totalArticlesRead"))
        XCTAssertTrue(json.contains("currentStreak"))
    }
    
    func testExportMarkdown() {
        tracker.setGoal(period: .daily, target: 3)
        tracker.logArticleRead(articleId: "a1")
        let md = tracker.exportMarkdown()
        XCTAssertTrue(md.contains("Reading Goals Report"))
        XCTAssertTrue(md.contains("Current Progress"))
    }
    
    // MARK: - Persistence
    
    func testPersistence() {
        tracker.setGoal(period: .daily, target: 5)
        tracker.logArticleRead(articleId: "a1")
        
        let tracker2 = ReadingGoalsTracker(directory: tempDir, calendar: calendar)
        XCTAssertEqual(tracker2.goals.count, 1)
        XCTAssertEqual(tracker2.totalArticlesRead, 1)
        XCTAssertEqual(tracker2.currentStreak, 1)
    }
    
    func testReset() {
        tracker.setGoal(period: .daily, target: 5)
        tracker.logArticleRead(articleId: "a1")
        tracker.reset()
        XCTAssertTrue(tracker.goals.isEmpty)
        XCTAssertEqual(tracker.totalArticlesRead, 0)
        XCTAssertEqual(tracker.currentStreak, 0)
    }
}
