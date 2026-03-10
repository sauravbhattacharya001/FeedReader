//
//  ReadingTimeBudgetTests.swift
//  FeedReaderTests
//

import XCTest
@testable import FeedReader

class ReadingTimeBudgetTests: XCTestCase {

    var manager: ReadingTimeBudgetManager!
    var calendar: Calendar!

    override func setUp() {
        super.setUp()
        calendar = Calendar.current
        manager = ReadingTimeBudgetManager(
            config: TimeBudgetConfig(dailyMinutes: 30, weeklyMinutes: 150, wordsPerMinute: 200, includeWeekends: true),
            calendar: calendar
        )
    }

    // MARK: - Config Tests

    func testDefaultConfig() {
        let cfg = TimeBudgetConfig.default
        XCTAssertEqual(cfg.dailyMinutes, 30)
        XCTAssertEqual(cfg.weeklyMinutes, 150)
        XCTAssertEqual(cfg.wordsPerMinute, 238)
        XCTAssertTrue(cfg.includeWeekends)
        XCTAssertTrue(cfg.isValid)
    }

    func testInvalidConfig() {
        let bad = TimeBudgetConfig(dailyMinutes: -1, weeklyMinutes: 0, wordsPerMinute: 200, includeWeekends: true)
        XCTAssertFalse(bad.isValid)
        let bad2 = TimeBudgetConfig(dailyMinutes: 30, weeklyMinutes: 0, wordsPerMinute: 0, includeWeekends: true)
        XCTAssertFalse(bad2.isValid)
    }

    func testUpdateConfig() {
        let newCfg = TimeBudgetConfig(dailyMinutes: 60, weeklyMinutes: 300, wordsPerMinute: 250, includeWeekends: false)
        manager.updateConfig(newCfg)
        XCTAssertEqual(manager.getConfig(), newCfg)
    }

    func testUpdateConfigRejectsInvalid() {
        let original = manager.getConfig()
        let bad = TimeBudgetConfig(dailyMinutes: -5, weeklyMinutes: 0, wordsPerMinute: 0, includeWeekends: true)
        manager.updateConfig(bad)
        XCTAssertEqual(manager.getConfig(), original)
    }

    // MARK: - Session Tests

    func testStartStopSession() {
        let start = Date()
        manager.startSession(at: start, articleTitle: "Test Article", feedName: "Test Feed", wordCount: 1000)
        XCTAssertTrue(manager.isSessionActive)

        let end = start.addingTimeInterval(600) // 10 minutes
        let entry = manager.stopSession(at: end)
        XCTAssertFalse(manager.isSessionActive)
        XCTAssertNotNil(entry)
        XCTAssertEqual(entry?.articleTitle, "Test Article")
        XCTAssertEqual(entry?.feedName, "Test Feed")
        XCTAssertEqual(entry?.wordCount, 1000)
        XCTAssertEqual(entry?.duration, 600, accuracy: 0.1)
        XCTAssertEqual(entry?.durationMinutes ?? 0, 10.0, accuracy: 0.1)
    }

    func testStopSessionWithNoActive() {
        let entry = manager.stopSession()
        XCTAssertNil(entry)
    }

    func testZeroDurationSession() {
        let t = Date()
        manager.startSession(at: t)
        let entry = manager.stopSession(at: t)
        XCTAssertNil(entry)
        XCTAssertFalse(manager.isSessionActive)
    }

    func testActualWPM() {
        let entry = ReadingTimeEntry(id: "1", date: Date(), duration: 300, articleTitle: nil, feedName: nil, wordCount: 1500)
        XCTAssertEqual(entry.actualWPM, 300) // 1500 words / 5 min
    }

    func testActualWPMNilWithoutWordCount() {
        let entry = ReadingTimeEntry(id: "1", date: Date(), duration: 300, articleTitle: nil, feedName: nil, wordCount: nil)
        XCTAssertNil(entry.actualWPM)
    }

    // MARK: - Manual Logging

    func testLogEntry() {
        let entry = manager.logEntry(date: Date(), durationSeconds: 900, articleTitle: "Manual", feedName: "Blog")
        XCTAssertNotNil(entry)
        XCTAssertEqual(manager.allEntries().count, 1)
    }

    func testLogEntryRejectsZeroDuration() {
        let entry = manager.logEntry(date: Date(), durationSeconds: 0)
        XCTAssertNil(entry)
    }

    func testRemoveEntry() {
        let entry = manager.logEntry(date: Date(), durationSeconds: 600)!
        XCTAssertTrue(manager.removeEntry(id: entry.id))
        XCTAssertEqual(manager.allEntries().count, 0)
    }

    func testRemoveNonexistent() {
        XCTAssertFalse(manager.removeEntry(id: "nope"))
    }

    // MARK: - Budget Calculations

    func testMinutesUsed() {
        let today = Date()
        manager.logEntry(date: today, durationSeconds: 600) // 10 min
        manager.logEntry(date: today, durationSeconds: 300) // 5 min
        XCTAssertEqual(manager.minutesUsed(on: today), 15.0, accuracy: 0.1)
    }

    func testRemainingToday() {
        let today = Date()
        manager.logEntry(date: today, durationSeconds: 600) // 10 min
        let remaining = manager.remainingToday(as: today)
        XCTAssertEqual(remaining, 20.0, accuracy: 0.1) // 30 - 10
    }

    func testRemainingTodayNoBudget() {
        manager.updateConfig(TimeBudgetConfig(dailyMinutes: 0, weeklyMinutes: 0, wordsPerMinute: 200, includeWeekends: true))
        XCTAssertEqual(manager.remainingToday(), Double.infinity)
    }

    func testEntriesOnDate() {
        let today = Date()
        let yesterday = calendar.date(byAdding: .day, value: -1, to: today)!
        manager.logEntry(date: today, durationSeconds: 600)
        manager.logEntry(date: yesterday, durationSeconds: 300)
        XCTAssertEqual(manager.entries(on: today).count, 1)
        XCTAssertEqual(manager.entries(on: yesterday).count, 1)
    }

    func testEntriesInRange() {
        let today = Date()
        let d1 = calendar.date(byAdding: .day, value: -3, to: today)!
        let d2 = calendar.date(byAdding: .day, value: -1, to: today)!
        manager.logEntry(date: d1, durationSeconds: 600)
        manager.logEntry(date: d2, durationSeconds: 300)
        manager.logEntry(date: today, durationSeconds: 900)
        let rangeEntries = manager.entries(from: d1, to: d2)
        XCTAssertEqual(rangeEntries.count, 2)
    }

    // MARK: - Pace

    func testCurrentPace() {
        let today = Date()
        manager.logEntry(date: today, durationSeconds: 600) // 10 min
        let pace = manager.currentPace(as: today)
        XCTAssertEqual(pace.usedToday, 10.0, accuracy: 0.1)
        XCTAssertEqual(pace.dailyBudget, 30)
        XCTAssertEqual(pace.remainingToday, 20.0, accuracy: 0.1)
        XCTAssertTrue(pace.paceDescription.contains("Today:"))
    }

    func testPaceNoBudget() {
        manager.updateConfig(TimeBudgetConfig(dailyMinutes: 0, weeklyMinutes: 0, wordsPerMinute: 200, includeWeekends: true))
        let pace = manager.currentPace()
        XCTAssertEqual(pace.paceDescription, "No budget set")
    }

    // MARK: - Daily Summary

    func testDailySummary() {
        let today = Date()
        manager.logEntry(date: today, durationSeconds: 1200, articleTitle: "A", wordCount: 2000) // 20 min
        manager.logEntry(date: today, durationSeconds: 300, articleTitle: "B", wordCount: 500) // 5 min
        let summary = manager.dailySummary(for: today)
        XCTAssertEqual(summary.budgetMinutes, 30)
        XCTAssertEqual(summary.usedMinutes, 25.0, accuracy: 0.1)
        XCTAssertEqual(summary.articleCount, 2)
        XCTAssertFalse(summary.isOverBudget)
        XCTAssertNotNil(summary.averageWPM)
    }

    func testDailySummaryOverBudget() {
        let today = Date()
        manager.logEntry(date: today, durationSeconds: 2400) // 40 min > 30 budget
        let summary = manager.dailySummary(for: today)
        XCTAssertTrue(summary.isOverBudget)
        XCTAssertEqual(summary.overtimeMinutes, 10.0, accuracy: 0.1)
    }

    func testDailySummaryGrade() {
        let today = Date()
        // 28 min out of 30 = 93% -> A (90-110%)
        manager.logEntry(date: today, durationSeconds: 1680)
        let summary = manager.dailySummary(for: today)
        XCTAssertEqual(summary.grade, "A")
    }

    func testDailySummaryGradeB() {
        let today = Date()
        // 24 min out of 30 = 80% -> B (75-125%)
        manager.logEntry(date: today, durationSeconds: 1440)
        let summary = manager.dailySummary(for: today)
        XCTAssertEqual(summary.grade, "B")
    }

    func testDailySummaryGradeF() {
        let today = Date()
        // 1 min out of 30 = 3% -> F
        manager.logEntry(date: today, durationSeconds: 60)
        let summary = manager.dailySummary(for: today)
        XCTAssertEqual(summary.grade, "F")
    }

    func testDailySummaryNoGradeNoBudget() {
        manager.updateConfig(TimeBudgetConfig(dailyMinutes: 0, weeklyMinutes: 0, wordsPerMinute: 200, includeWeekends: true))
        let summary = manager.dailySummary(for: Date())
        XCTAssertEqual(summary.grade, "-")
    }

    // MARK: - Weekly Report

    func testWeeklyReport() {
        let today = Date()
        manager.logEntry(date: today, durationSeconds: 1800) // 30 min
        let report = manager.weeklyReport(containing: today)
        XCTAssertEqual(report.dailySummaries.count, 7)
        XCTAssertEqual(report.totalBudgetMinutes, 150)
        XCTAssertGreaterThan(report.totalUsedMinutes, 0)
        XCTAssertEqual(report.totalArticles, 0) // no article title
    }

    func testWeeklyReportAdherence() {
        let today = Date()
        // Log perfect 30 min for today
        manager.logEntry(date: today, durationSeconds: 1800)
        let report = manager.weeklyReport(containing: today)
        XCTAssertGreaterThan(report.adherenceScore, 0)
    }

    // MARK: - Article Recommendations

    func testSuggestArticles() {
        let today = Date()
        // Used 20 min, 10 remaining
        manager.logEntry(date: today, durationSeconds: 1200)

        let candidates = [
            TimeFitArticle(title: "Short", feedName: "A", estimatedMinutes: 3, wordCount: 600),
            TimeFitArticle(title: "Perfect", feedName: "B", estimatedMinutes: 9, wordCount: 1800),
            TimeFitArticle(title: "Long", feedName: "C", estimatedMinutes: 25, wordCount: 5000),
            TimeFitArticle(title: "Medium", feedName: "D", estimatedMinutes: 7, wordCount: 1400),
        ]

        let suggestions = manager.suggestArticles(candidates, on: today, maxResults: 3)
        XCTAssertEqual(suggestions.count, 3)
        // "Perfect" (9 min) should score highest for 10 min remaining
        XCTAssertEqual(suggestions.first?.title, "Perfect")
    }

    func testSuggestArticlesNoBudgetRemaining() {
        let today = Date()
        manager.logEntry(date: today, durationSeconds: 3600) // 60 min, way over 30 budget
        let candidates = [
            TimeFitArticle(title: "Any", feedName: "A", estimatedMinutes: 5, wordCount: 1000),
        ]
        let suggestions = manager.suggestArticles(candidates, on: today)
        XCTAssertTrue(suggestions.isEmpty)
    }

    func testEstimateReadingMinutes() {
        XCTAssertEqual(manager.estimateReadingMinutes(wordCount: 1000), 5.0, accuracy: 0.1) // 1000/200
        XCTAssertEqual(manager.estimateReadingMinutes(wordCount: 0), 0.0)
    }

    // MARK: - Statistics

    func testAverageDailyMinutes() {
        let today = Date()
        let yesterday = calendar.date(byAdding: .day, value: -1, to: today)!
        manager.logEntry(date: today, durationSeconds: 1200) // 20 min
        manager.logEntry(date: yesterday, durationSeconds: 600) // 10 min
        let avg = manager.averageDailyMinutes(lastDays: 2, as: today)
        XCTAssertEqual(avg, 15.0, accuracy: 0.1)
    }

    func testTotalMinutesAllTime() {
        manager.logEntry(date: Date(), durationSeconds: 600)
        manager.logEntry(date: Date(), durationSeconds: 300)
        XCTAssertEqual(manager.totalMinutesAllTime(), 15.0, accuracy: 0.1)
    }

    func testTotalArticlesAllTime() {
        manager.logEntry(date: Date(), durationSeconds: 600, articleTitle: "A")
        manager.logEntry(date: Date(), durationSeconds: 300) // no title
        XCTAssertEqual(manager.totalArticlesAllTime(), 1)
    }

    func testUniqueReadingDays() {
        let today = Date()
        let yesterday = calendar.date(byAdding: .day, value: -1, to: today)!
        manager.logEntry(date: today, durationSeconds: 600)
        manager.logEntry(date: today, durationSeconds: 300)
        manager.logEntry(date: yesterday, durationSeconds: 600)
        XCTAssertEqual(manager.uniqueReadingDays(), 2)
    }

    func testTopFeedsByTime() {
        manager.logEntry(date: Date(), durationSeconds: 600, feedName: "Blog A")
        manager.logEntry(date: Date(), durationSeconds: 1200, feedName: "Blog B")
        manager.logEntry(date: Date(), durationSeconds: 300, feedName: "Blog A")
        let top = manager.topFeedsByTime(limit: 2)
        XCTAssertEqual(top.count, 2)
        XCTAssertEqual(top[0].feedName, "Blog B")
        XCTAssertEqual(top[1].feedName, "Blog A")
    }

    // MARK: - Text Report

    func testTextReport() {
        let today = Date()
        manager.logEntry(date: today, durationSeconds: 1800, articleTitle: "Test")
        let report = manager.textReport(containing: today)
        XCTAssertTrue(report.contains("Reading Time Budget Report"))
        XCTAssertTrue(report.contains("Adherence Score"))
        XCTAssertTrue(report.contains("Daily Breakdown"))
    }

    // MARK: - JSON Export/Import

    func testExportImportJSON() {
        manager.logEntry(date: Date(), durationSeconds: 600, articleTitle: "Test")
        let json = manager.exportJSON()
        XCTAssertNotNil(json)

        let newManager = ReadingTimeBudgetManager()
        let result = newManager.importJSON(json!)
        XCTAssertTrue(result)
        XCTAssertEqual(newManager.allEntries().count, 1)
        XCTAssertEqual(newManager.getConfig(), manager.getConfig())
    }

    func testImportInvalidJSON() {
        XCTAssertFalse(manager.importJSON("not json"))
    }

    // MARK: - Edge Cases

    func testEmptyManagerStats() {
        XCTAssertEqual(manager.totalMinutesAllTime(), 0)
        XCTAssertEqual(manager.totalArticlesAllTime(), 0)
        XCTAssertEqual(manager.uniqueReadingDays(), 0)
        XCTAssertTrue(manager.topFeedsByTime().isEmpty)
    }

    func testMultipleSessionsSameDay() {
        let today = Date()
        for i in 0..<5 {
            let start = today.addingTimeInterval(Double(i * 1000))
            manager.startSession(at: start, articleTitle: "Article \(i)")
            manager.stopSession(at: start.addingTimeInterval(360)) // 6 min each
        }
        XCTAssertEqual(manager.minutesUsed(on: today), 30.0, accuracy: 0.1)
        XCTAssertEqual(manager.allEntries().count, 5)
    }

    func testUsagePercentCapped() {
        let summary = DailyBudgetSummary(date: Date(), budgetMinutes: 1, usedMinutes: 1000, remainingMinutes: 0, articleCount: 0, averageWPM: nil)
        XCTAssertEqual(summary.usagePercent, 999.9, accuracy: 0.1)
    }

    func testOvertimeMinutesZeroWhenUnder() {
        let summary = DailyBudgetSummary(date: Date(), budgetMinutes: 30, usedMinutes: 20, remainingMinutes: 10, articleCount: 0, averageWPM: nil)
        XCTAssertEqual(summary.overtimeMinutes, 0)
    }

    func testWeeklyReportIsOverBudget() {
        let report = WeeklyBudgetReport(
            weekStartDate: Date(), weekEndDate: Date(), config: .default,
            dailySummaries: [], totalBudgetMinutes: 100, totalUsedMinutes: 150,
            totalArticles: 0, adherenceScore: 50, streak: 0, longestStreak: 0,
            averageDailyMinutes: 0, busiestDay: nil, quietestDay: nil
        )
        XCTAssertTrue(report.isOverBudget)
    }

    func testAverageDailyMinutesZeroDays() {
        XCTAssertEqual(manager.averageDailyMinutes(lastDays: 0), 0)
    }

    // MARK: - Entry Cap Tests (Issue #55)

    func testEntryCapEvictsOldest() {
        let small = TimeBudgetConfig(dailyMinutes: 30, weeklyMinutes: 150, wordsPerMinute: 200, includeWeekends: true, maxEntries: 5)
        let mgr = ReadingTimeBudgetManager(config: small, calendar: calendar)

        // Log 8 entries — oldest 3 should be evicted
        let now = Date()
        for i in 0..<8 {
            let d = calendar.date(byAdding: .hour, value: -i, to: now)!
            mgr.logEntry(date: d, durationSeconds: 60, articleTitle: "Article \(i)")
        }

        XCTAssertEqual(mgr.entryCount, 5, "Should cap at 5 entries")
        // Most recent entries should survive (entries are sorted by date, suffix kept)
        let all = mgr.allEntries()
        XCTAssertTrue(all.allSatisfy { $0.articleTitle != nil })
    }

    func testEntryCapZeroMeansUnlimited() {
        let unlimited = TimeBudgetConfig(dailyMinutes: 30, weeklyMinutes: 150, wordsPerMinute: 200, includeWeekends: true, maxEntries: 0)
        let mgr = ReadingTimeBudgetManager(config: unlimited, calendar: calendar)

        for i in 0..<20 {
            mgr.logEntry(date: Date(), durationSeconds: 60, articleTitle: "A\(i)")
        }
        XCTAssertEqual(mgr.entryCount, 20, "maxEntries=0 should not evict")
    }

    func testPruneEntriesRemovesOld() {
        let now = Date()
        let old1 = calendar.date(byAdding: .day, value: -100, to: now)!
        let old2 = calendar.date(byAdding: .day, value: -91, to: now)!
        let recent = calendar.date(byAdding: .day, value: -5, to: now)!
        let cutoff = calendar.date(byAdding: .day, value: -90, to: now)!

        manager.logEntry(date: old1, durationSeconds: 600, articleTitle: "Old1")
        manager.logEntry(date: old2, durationSeconds: 600, articleTitle: "Old2")
        manager.logEntry(date: recent, durationSeconds: 600, articleTitle: "Recent")

        let removed = manager.pruneEntries(olderThan: cutoff)
        XCTAssertEqual(removed, 2, "Should remove 2 entries older than 90 days")
        XCTAssertEqual(manager.entryCount, 1, "Should keep 1 recent entry")
        XCTAssertEqual(manager.allEntries().first?.articleTitle, "Recent")
    }

    func testPruneEntriesReturnsZeroWhenNothingToRemove() {
        manager.logEntry(date: Date(), durationSeconds: 600)
        let cutoff = calendar.date(byAdding: .day, value: -90, to: Date())!
        let removed = manager.pruneEntries(olderThan: cutoff)
        XCTAssertEqual(removed, 0)
    }

    func testMaxEntriesConfigValidation() {
        let bad = TimeBudgetConfig(dailyMinutes: 30, weeklyMinutes: 150, wordsPerMinute: 200, includeWeekends: true, maxEntries: -1)
        XCTAssertFalse(bad.isValid, "Negative maxEntries should be invalid")
    }

    func testDefaultConfigMaxEntries() {
        let cfg = TimeBudgetConfig.default
        XCTAssertEqual(cfg.maxEntries, 10_000)
    }

}
