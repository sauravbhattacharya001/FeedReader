//
//  ReadingStreakTests.swift
//  FeedReaderTests
//
//  Tests for ReadingStreakTracker — consecutive reading day tracking,
//  milestones, weekly summaries, and streak statistics.
//

import XCTest
@testable import FeedReader

class ReadingStreakTests: XCTestCase {

    /// Fresh tracker with isolated UserDefaults for each test.
    private var tracker: ReadingStreakTracker!
    private var testDefaults: UserDefaults!

    override func setUp() {
        super.setUp()
        testDefaults = UserDefaults(suiteName: "ReadingStreakTests")!
        testDefaults.removePersistentDomain(forName: "ReadingStreakTests")
        tracker = ReadingStreakTracker(defaults: testDefaults)
    }

    override func tearDown() {
        tracker.resetAll()
        testDefaults.removePersistentDomain(forName: "ReadingStreakTests")
        tracker = nil
        testDefaults = nil
        super.tearDown()
    }

    // MARK: - Initial State

    func testInitialStatsAreEmpty() {
        let stats = tracker.getStats()
        XCTAssertEqual(stats.currentStreak, 0)
        XCTAssertEqual(stats.longestStreak, 0)
        XCTAssertEqual(stats.totalActiveDays, 0)
        XCTAssertEqual(stats.totalArticlesRead, 0)
        XCTAssertEqual(stats.averagePerDay, 0)
        XCTAssertFalse(stats.readToday)
        XCTAssertFalse(stats.isPersonalBest)
    }

    func testTrackedDaysCountInitiallyZero() {
        XCTAssertEqual(tracker.trackedDaysCount, 0)
    }

    // MARK: - Recording Articles

    func testRecordSingleArticle() {
        let stats = tracker.recordArticleRead()
        XCTAssertEqual(stats.totalArticlesRead, 1)
        XCTAssertEqual(stats.totalActiveDays, 1)
        XCTAssertTrue(stats.readToday)
        XCTAssertEqual(stats.currentStreak, 1)
    }

    func testRecordMultipleArticlesSameDay() {
        tracker.recordArticleRead()
        tracker.recordArticleRead()
        let stats = tracker.recordArticleRead()
        XCTAssertEqual(stats.totalArticlesRead, 3)
        XCTAssertEqual(stats.totalActiveDays, 1)
        XCTAssertEqual(stats.currentStreak, 1)
    }

    func testRecordBatchArticles() {
        let stats = tracker.recordArticles(count: 5)
        XCTAssertEqual(stats.totalArticlesRead, 5)
        XCTAssertEqual(stats.totalActiveDays, 1)
        XCTAssertTrue(stats.readToday)
    }

    func testRecordBatchZeroIsNoOp() {
        let stats = tracker.recordArticles(count: 0)
        XCTAssertEqual(stats.totalArticlesRead, 0)
        XCTAssertFalse(stats.readToday)
    }

    // MARK: - Goal Integration

    func testGoalMetWhenTargetReached() {
        tracker.recordArticleRead(goalTarget: 3)
        tracker.recordArticleRead(goalTarget: 3)
        tracker.recordArticleRead(goalTarget: 3)
        let rec = tracker.record(for: Date())
        XCTAssertNotNil(rec)
        XCTAssertTrue(rec!.goalMet)
    }

    func testGoalNotMetWhenBelowTarget() {
        tracker.recordArticleRead(goalTarget: 5)
        tracker.recordArticleRead(goalTarget: 5)
        let rec = tracker.record(for: Date())
        XCTAssertNotNil(rec)
        XCTAssertFalse(rec!.goalMet)
    }

    func testGoalMetWithBatchRecord() {
        tracker.recordArticles(count: 10, goalTarget: 5)
        let rec = tracker.record(for: Date())
        XCTAssertTrue(rec!.goalMet)
    }

    // MARK: - Streak Computation

    func testStreakStartsAtOne() {
        let stats = tracker.recordArticleRead()
        XCTAssertEqual(stats.currentStreak, 1)
        XCTAssertEqual(stats.longestStreak, 1)
    }

    func testAveragePerDayCalculation() {
        tracker.recordArticles(count: 6)
        let stats = tracker.getStats()
        XCTAssertEqual(stats.averagePerDay, 6.0, accuracy: 0.01)
    }

    func testIsPersonalBestOnFirstStreak() {
        let stats = tracker.recordArticleRead()
        XCTAssertTrue(stats.isPersonalBest)
    }

    // MARK: - Streak at Risk

    func testStreakNotAtRiskAfterReadingToday() {
        tracker.recordArticleRead()
        XCTAssertFalse(tracker.isStreakAtRisk)
    }

    func testStreakNotAtRiskWithNoHistory() {
        XCTAssertFalse(tracker.isStreakAtRisk)
    }

    // MARK: - Record Retrieval

    func testRecordForDate() {
        tracker.recordArticleRead()
        let rec = tracker.record(for: Date())
        XCTAssertNotNil(rec)
        XCTAssertEqual(rec!.articlesRead, 1)
    }

    func testRecordForDateWithNoData() {
        let rec = tracker.record(for: Date())
        XCTAssertNil(rec)
    }

    func testRecordsForDateRange() {
        tracker.recordArticleRead()
        let records = tracker.records(from: Date(), to: Date())
        XCTAssertEqual(records.count, 1)
    }

    func testRecordsForEmptyRange() {
        let future = Calendar.current.date(byAdding: .day, value: 10, to: Date())!
        let farFuture = Calendar.current.date(byAdding: .day, value: 15, to: Date())!
        let records = tracker.records(from: future, to: farFuture)
        XCTAssertTrue(records.isEmpty)
    }

    // MARK: - Weekly Summaries

    func testWeeklySummariesReturnRequestedCount() {
        tracker.recordArticleRead()
        let summaries = tracker.weeklySummaries(weeks: 2)
        XCTAssertEqual(summaries.count, 2)
    }

    func testWeeklySummariesZeroWeeks() {
        let summaries = tracker.weeklySummaries(weeks: 0)
        XCTAssertTrue(summaries.isEmpty)
    }

    func testWeeklySummaryCurrentWeekHasActivity() {
        tracker.recordArticleRead()
        let summaries = tracker.weeklySummaries(weeks: 1)
        XCTAssertFalse(summaries.isEmpty)
        XCTAssertGreaterThanOrEqual(summaries[0].activeDays, 1)
        XCTAssertGreaterThanOrEqual(summaries[0].totalArticles, 1)
    }

    // MARK: - Goal Streak Days

    func testGoalStreakDaysWithNoGoals() {
        tracker.recordArticleRead()
        let goalDays = tracker.goalStreakDays(last: 7)
        XCTAssertEqual(goalDays, 0)
    }

    func testGoalStreakDaysWithGoalMet() {
        tracker.recordArticles(count: 5, goalTarget: 3)
        let goalDays = tracker.goalStreakDays(last: 7)
        XCTAssertEqual(goalDays, 1)
    }

    // MARK: - Reset

    func testResetClearsAllData() {
        tracker.recordArticleRead()
        tracker.recordArticleRead()
        tracker.resetAll()

        let stats = tracker.getStats()
        XCTAssertEqual(stats.currentStreak, 0)
        XCTAssertEqual(stats.longestStreak, 0)
        XCTAssertEqual(stats.totalArticlesRead, 0)
        XCTAssertEqual(stats.totalActiveDays, 0)
        XCTAssertEqual(tracker.trackedDaysCount, 0)
    }

    // MARK: - Persistence

    func testDataPersistsAcrossInstances() {
        tracker.recordArticles(count: 3)
        XCTAssertEqual(tracker.getStats().totalArticlesRead, 3)

        // Create a new tracker with the same defaults
        let tracker2 = ReadingStreakTracker(defaults: testDefaults)
        XCTAssertEqual(tracker2.getStats().totalArticlesRead, 3)
        XCTAssertTrue(tracker2.getStats().readToday)
    }

    func testResetPersists() {
        tracker.recordArticleRead()
        tracker.resetAll()

        let tracker2 = ReadingStreakTracker(defaults: testDefaults)
        XCTAssertEqual(tracker2.getStats().totalArticlesRead, 0)
    }

    // MARK: - Next Milestone

    func testNextMilestoneIsSevenForNewStreak() {
        let stats = tracker.recordArticleRead()
        XCTAssertEqual(stats.nextMilestone, 7)
        XCTAssertEqual(stats.daysToNextMilestone, 6)
    }

    func testNoMilestoneWhenNoStreak() {
        let stats = tracker.getStats()
        // Milestone fields should still be set (first milestone = 7)
        XCTAssertEqual(stats.nextMilestone, 7)
    }

    // MARK: - DailyReadingRecord Model

    func testDailyReadingRecordDefaults() {
        let record = DailyReadingRecord(date: "2026-03-01")
        XCTAssertEqual(record.date, "2026-03-01")
        XCTAssertEqual(record.articlesRead, 0)
        XCTAssertFalse(record.goalMet)
    }

    func testDailyReadingRecordEquality() {
        let a = DailyReadingRecord(date: "2026-03-01", articlesRead: 5, goalMet: true)
        let b = DailyReadingRecord(date: "2026-03-01", articlesRead: 5, goalMet: true)
        XCTAssertEqual(a, b)
    }

    func testDailyReadingRecordCodable() {
        let original = DailyReadingRecord(date: "2026-03-01", articlesRead: 7, goalMet: true)
        let data = try! JSONEncoder().encode(original)
        let decoded = try! JSONDecoder().decode(DailyReadingRecord.self, from: data)
        XCTAssertEqual(original, decoded)
    }

    // MARK: - StreakStats Model

    func testStreakStatsEquality() {
        let a = StreakStats(currentStreak: 5, longestStreak: 10, totalActiveDays: 20,
                           totalArticlesRead: 100, averagePerDay: 5.0, readToday: true,
                           daysSinceLastRead: 0, isPersonalBest: false,
                           nextMilestone: 7, daysToNextMilestone: 2)
        let b = StreakStats(currentStreak: 5, longestStreak: 10, totalActiveDays: 20,
                           totalArticlesRead: 100, averagePerDay: 5.0, readToday: true,
                           daysSinceLastRead: 0, isPersonalBest: false,
                           nextMilestone: 7, daysToNextMilestone: 2)
        XCTAssertEqual(a, b)
    }

    // MARK: - WeekSummary Model

    func testWeekSummaryEquality() {
        let a = WeekSummary(weekStart: "2026-03-02", activeDays: 5,
                           totalArticles: 20, perfectWeek: false)
        let b = WeekSummary(weekStart: "2026-03-02", activeDays: 5,
                           totalArticles: 20, perfectWeek: false)
        XCTAssertEqual(a, b)
    }

    // MARK: - Notification

    func testNotificationPostedOnRecord() {
        let expectation = self.expectation(forNotification: .readingStreakDidChange,
                                            object: nil, handler: nil)
        tracker.recordArticleRead()
        wait(for: [expectation], timeout: 1.0)
    }

    func testNotificationPostedOnReset() {
        tracker.recordArticleRead()
        let expectation = self.expectation(forNotification: .readingStreakDidChange,
                                            object: nil, handler: nil)
        tracker.resetAll()
        wait(for: [expectation], timeout: 1.0)
    }

    // MARK: - Edge Cases

    func testMultipleBatchRecordsAccumulate() {
        tracker.recordArticles(count: 3)
        tracker.recordArticles(count: 4)
        let stats = tracker.getStats()
        XCTAssertEqual(stats.totalArticlesRead, 7)
        XCTAssertEqual(stats.totalActiveDays, 1) // Same day
    }

    func testDaysSinceLastReadIsZeroWhenReadToday() {
        tracker.recordArticleRead()
        let stats = tracker.getStats()
        XCTAssertEqual(stats.daysSinceLastRead, 0)
    }

    func testStatsSnapshotFromRecordArticleRead() {
        // The return value of recordArticleRead should match getStats()
        let fromRecord = tracker.recordArticleRead()
        let fromGet = tracker.getStats()
        XCTAssertEqual(fromRecord.currentStreak, fromGet.currentStreak)
        XCTAssertEqual(fromRecord.totalArticlesRead, fromGet.totalArticlesRead)
        XCTAssertEqual(fromRecord.readToday, fromGet.readToday)
    }
}
