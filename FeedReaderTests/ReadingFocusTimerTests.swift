//
//  ReadingFocusTimerTests.swift
//  FeedReaderTests
//

import XCTest
@testable import FeedReader

class ReadingFocusTimerTests: XCTestCase {

    var timer: ReadingFocusTimer!

    override func setUp() {
        super.setUp()
        timer = ReadingFocusTimer()
        UserDefaults.standard.removeObject(forKey: "ReadingFocusTimer.sessions")
        UserDefaults.standard.removeObject(forKey: "ReadingFocusTimer.streak")
        UserDefaults.standard.removeObject(forKey: "ReadingFocusTimer.activePreset")
    }

    override func tearDown() {
        timer.clearHistory()
        if timer.isActive || timer.isPaused {
            timer.cancel()
        }
        super.tearDown()
    }

    // MARK: - Initial State

    func testInitialState() {
        XCTAssertEqual(timer.phase, .idle)
        XCTAssertFalse(timer.isActive)
        XCTAssertFalse(timer.isPaused)
        XCTAssertEqual(timer.currentRound, 0)
        XCTAssertFalse(timer.distractionFreeMode)
        XCTAssertEqual(timer.currentArticleCount, 0)
        XCTAssertEqual(timer.totalFocusTime, 0)
        XCTAssertEqual(timer.totalArticlesRead, 0)
        XCTAssertEqual(timer.streak.currentStreak, 0)
        XCTAssertEqual(timer.streak.longestStreak, 0)
    }

    func testDefaultPreset() {
        XCTAssertEqual(timer.activePreset, TimerPreset.pomodoro)
        XCTAssertEqual(timer.activePreset.focusMinutes, 25)
        XCTAssertEqual(timer.activePreset.shortBreakMinutes, 5)
        XCTAssertEqual(timer.activePreset.longBreakMinutes, 15)
        XCTAssertEqual(timer.activePreset.roundsBeforeLongBreak, 4)
    }

    func testCustomPresetInit() {
        let t = ReadingFocusTimer(preset: .deepRead)
        XCTAssertEqual(t.activePreset, TimerPreset.deepRead)
        XCTAssertEqual(t.activePreset.focusMinutes, 50)
    }

    // MARK: - Timer Presets

    func testAllPresetsExist() {
        XCTAssertEqual(TimerPreset.allPresets.count, 4)
        let names = TimerPreset.allPresets.map(\.name)
        XCTAssertTrue(names.contains("Pomodoro"))
        XCTAssertTrue(names.contains("Deep Read"))
        XCTAssertTrue(names.contains("Sprint"))
        XCTAssertTrue(names.contains("Marathon"))
    }

    func testPresetValues() {
        XCTAssertEqual(TimerPreset.sprint.focusMinutes, 15)
        XCTAssertEqual(TimerPreset.sprint.shortBreakMinutes, 3)
        XCTAssertEqual(TimerPreset.sprint.roundsBeforeLongBreak, 6)

        XCTAssertEqual(TimerPreset.marathon.focusMinutes, 90)
        XCTAssertEqual(TimerPreset.marathon.longBreakMinutes, 30)
        XCTAssertEqual(TimerPreset.marathon.roundsBeforeLongBreak, 2)
    }

    func testSetPresetWhileIdle() {
        let result = timer.setPreset(.deepRead)
        XCTAssertTrue(result)
        XCTAssertEqual(timer.activePreset, TimerPreset.deepRead)
    }

    func testSetPresetWhileActiveFails() {
        timer.startFocus()
        let result = timer.setPreset(.sprint)
        XCTAssertFalse(result)
        XCTAssertEqual(timer.activePreset, TimerPreset.pomodoro)
    }

    // MARK: - Focus Lifecycle

    func testStartFocus() {
        let result = timer.startFocus()
        XCTAssertTrue(result)
        XCTAssertEqual(timer.phase, .focus)
        XCTAssertTrue(timer.isActive)
        XCTAssertFalse(timer.isPaused)
    }

    func testStartFocusWithDistractionFreeMode() {
        timer.startFocus(distractionFree: true)
        XCTAssertTrue(timer.distractionFreeMode)
    }

    func testDoubleStartFails() {
        timer.startFocus()
        let result = timer.startFocus()
        XCTAssertFalse(result)
    }

    func testEndFocusCompletedProducesRecord() {
        timer.startFocus()
        let record = timer.endFocus(completed: true)
        XCTAssertNotNil(record)
        XCTAssertTrue(record!.completed)
        XCTAssertEqual(record!.preset, "Pomodoro")
    }

    func testEndFocusIncreasesRound() {
        timer.startFocus()
        _ = timer.endFocus(completed: true)
        XCTAssertEqual(timer.currentRound, 1)
    }

    func testEndFocusTransitionsToShortBreak() {
        timer.startFocus()
        _ = timer.endFocus(completed: true)
        XCTAssertEqual(timer.phase, .shortBreak)
    }

    func testLongBreakAfterAllRounds() {
        let t = ReadingFocusTimer(preset: .pomodoro) // 4 rounds
        for _ in 0..<3 {
            t.startFocus()
            _ = t.endFocus(completed: true)
            t.endBreak()
        }
        // 4th round → long break
        t.startFocus()
        _ = t.endFocus(completed: true)
        XCTAssertEqual(t.phase, .longBreak)
        XCTAssertEqual(t.currentRound, 0) // reset after long break
    }

    func testEndFocusWhileIdleReturnsNil() {
        let record = timer.endFocus()
        XCTAssertNil(record)
    }

    func testCancelDoesNotSaveRecord() {
        timer.startFocus()
        timer.cancel()
        XCTAssertEqual(timer.phase, .idle)
        XCTAssertEqual(timer.allSessions.count, 0)
    }

    // MARK: - Pause/Resume

    func testPauseFocus() {
        timer.startFocus()
        let result = timer.pause()
        XCTAssertTrue(result)
        XCTAssertEqual(timer.phase, .paused)
        XCTAssertTrue(timer.isPaused)
        XCTAssertFalse(timer.isActive)
    }

    func testPauseWhileIdleFails() {
        let result = timer.pause()
        XCTAssertFalse(result)
    }

    func testResumePause() {
        timer.startFocus()
        timer.pause()
        let result = timer.resume()
        XCTAssertTrue(result)
        XCTAssertEqual(timer.phase, .focus)
    }

    func testResumeWhileFocusFails() {
        timer.startFocus()
        let result = timer.resume()
        XCTAssertFalse(result)
    }

    func testEndFocusWhilePaused() {
        timer.startFocus()
        timer.pause()
        let record = timer.endFocus(completed: true)
        XCTAssertNotNil(record)
        XCTAssertTrue(record!.completed)
    }

    // MARK: - Article Tracking

    func testRecordArticleDuringFocus() {
        timer.startFocus()
        timer.recordArticle(link: "https://example.com/1", title: "Article 1")
        XCTAssertEqual(timer.currentArticleCount, 1)
    }

    func testRecordArticleDuringPause() {
        timer.startFocus()
        timer.pause()
        timer.recordArticle(link: "https://example.com/1", title: "Article 1")
        XCTAssertEqual(timer.currentArticleCount, 1)
    }

    func testRecordArticleWhileIdleIgnored() {
        timer.recordArticle(link: "https://example.com/1", title: "Article 1")
        XCTAssertEqual(timer.currentArticleCount, 0)
    }

    func testArticlesInRecord() {
        timer.startFocus()
        timer.recordArticle(link: "https://a.com", title: "A")
        timer.recordArticle(link: "https://b.com", title: "B")
        let record = timer.endFocus(completed: true)
        XCTAssertEqual(record?.articlesRead.count, 2)
        XCTAssertEqual(record?.articlesRead[0].title, "A")
        XCTAssertEqual(record?.articlesRead[1].link, "https://b.com")
    }

    func testArticlesClearedAfterEndFocus() {
        timer.startFocus()
        timer.recordArticle(link: "https://a.com", title: "A")
        _ = timer.endFocus(completed: true)
        XCTAssertEqual(timer.currentArticleCount, 0)
    }

    // MARK: - Break Control

    func testEndBreak() {
        timer.startFocus()
        _ = timer.endFocus(completed: true)
        XCTAssertEqual(timer.phase, .shortBreak)
        timer.endBreak()
        XCTAssertEqual(timer.phase, .idle)
    }

    func testSkipBreak() {
        timer.startFocus()
        _ = timer.endFocus(completed: true)
        timer.skipBreak()
        XCTAssertEqual(timer.phase, .idle)
    }

    func testStartFocusFromBreak() {
        timer.startFocus()
        _ = timer.endFocus(completed: true)
        XCTAssertEqual(timer.phase, .shortBreak)
        let result = timer.startFocus()
        XCTAssertTrue(result)
        XCTAssertEqual(timer.phase, .focus)
    }

    // MARK: - Session History

    func testSessionsAccumulate() {
        for _ in 0..<3 {
            timer.startFocus()
            _ = timer.endFocus(completed: true)
            timer.endBreak()
        }
        XCTAssertEqual(timer.allSessions.count, 3)
    }

    func testAllSessionsSortedRecentFirst() {
        timer.startFocus()
        _ = timer.endFocus(completed: true)
        timer.endBreak()

        timer.startFocus()
        _ = timer.endFocus(completed: true)

        let sessions = timer.allSessions
        XCTAssertEqual(sessions.count, 2)
        XCTAssertTrue(sessions[0].startedAt >= sessions[1].startedAt)
    }

    func testDailySummary() {
        timer.startFocus()
        timer.recordArticle(link: "https://a.com", title: "A")
        _ = timer.endFocus(completed: true)
        timer.endBreak()

        timer.startFocus()
        _ = timer.endFocus(completed: false)

        let summary = timer.dailySummary(for: Date())
        XCTAssertEqual(summary.sessions.count, 2)
        XCTAssertEqual(summary.completedSessions, 1)
        XCTAssertEqual(summary.totalArticles, 1)
    }

    func testRecentDailySummaries() {
        timer.startFocus()
        _ = timer.endFocus(completed: true)

        let summaries = timer.recentDailySummaries(days: 7)
        XCTAssertEqual(summaries.count, 7)
        XCTAssertTrue(summaries[0].sessions.count >= 1) // today
    }

    // MARK: - Stats

    func testTotalFocusTime() {
        timer.startFocus()
        _ = timer.endFocus(completed: true)
        XCTAssertTrue(timer.totalFocusTime >= 0)
    }

    func testCompletionRate() {
        timer.startFocus()
        _ = timer.endFocus(completed: true)
        timer.endBreak()

        timer.startFocus()
        _ = timer.endFocus(completed: false)

        XCTAssertEqual(timer.completionRate, 50.0, accuracy: 0.1)
    }

    func testTotalArticlesRead() {
        timer.startFocus()
        timer.recordArticle(link: "https://a.com", title: "A")
        timer.recordArticle(link: "https://b.com", title: "B")
        _ = timer.endFocus(completed: true)

        XCTAssertEqual(timer.totalArticlesRead, 2)
    }

    func testEmptyStatsDefaults() {
        XCTAssertEqual(timer.completionRate, 0)
        XCTAssertEqual(timer.averageSessionDuration, 0)
        XCTAssertEqual(timer.overallArticlesPerHour, 0)
        XCTAssertNil(timer.preferredReadingHour)
        XCTAssertNil(timer.favoritePreset)
    }

    func testFavoritePreset() {
        timer.startFocus()
        _ = timer.endFocus(completed: true)
        timer.endBreak()

        timer.startFocus()
        _ = timer.endFocus(completed: true)

        XCTAssertEqual(timer.favoritePreset, "Pomodoro")
    }

    // MARK: - FocusSessionRecord Properties

    func testSessionRecordCompletionPercent() {
        let record = FocusSessionRecord(
            id: "test",
            startedAt: Date(),
            endedAt: Date(),
            durationSeconds: 750,
            targetDurationSeconds: 1500,
            articlesRead: [],
            preset: "Pomodoro",
            completed: false,
            distractionFreeMode: false
        )
        XCTAssertEqual(record.completionPercent, 50.0, accuracy: 0.1)
    }

    func testSessionRecordArticlesPerHour() {
        let articles = [
            FocusArticle(link: "https://a.com", title: "A", readAt: Date()),
            FocusArticle(link: "https://b.com", title: "B", readAt: Date()),
        ]
        let record = FocusSessionRecord(
            id: "test",
            startedAt: Date(),
            endedAt: Date(),
            durationSeconds: 1800, // 30 min
            targetDurationSeconds: 1800,
            articlesRead: articles,
            preset: "Pomodoro",
            completed: true,
            distractionFreeMode: false
        )
        XCTAssertEqual(record.articlesPerHour, 4.0, accuracy: 0.1)
    }

    func testSessionRecordZeroDuration() {
        let record = FocusSessionRecord(
            id: "test",
            startedAt: Date(),
            endedAt: Date(),
            durationSeconds: 0,
            targetDurationSeconds: 0,
            articlesRead: [],
            preset: "Pomodoro",
            completed: false,
            distractionFreeMode: false
        )
        XCTAssertEqual(record.articlesPerHour, 0)
        XCTAssertEqual(record.completionPercent, 0)
    }

    // MARK: - DailyFocusSummary

    func testDailyFocusSummaryEmpty() {
        let summary = DailyFocusSummary(date: Date(), sessions: [])
        XCTAssertEqual(summary.totalFocusSeconds, 0)
        XCTAssertEqual(summary.completedSessions, 0)
        XCTAssertEqual(summary.totalArticles, 0)
        XCTAssertEqual(summary.averageArticlesPerHour, 0)
        XCTAssertEqual(summary.completionRate, 0)
    }

    // MARK: - Streak

    func testStreakInitiallyZero() {
        XCTAssertEqual(timer.streak.currentStreak, 0)
        XCTAssertEqual(timer.streak.longestStreak, 0)
    }

    func testCompletedSessionUpdatesStreak() {
        timer.startFocus()
        _ = timer.endFocus(completed: true)
        XCTAssertEqual(timer.streak.currentStreak, 1)
        XCTAssertEqual(timer.streak.longestStreak, 1)
        XCTAssertNotNil(timer.streak.lastActiveDate)
    }

    func testIncompleteSessionDoesNotUpdateStreak() {
        timer.startFocus()
        _ = timer.endFocus(completed: false)
        XCTAssertEqual(timer.streak.currentStreak, 0)
    }

    func testMultipleSessionsSameDayNoStreakIncrease() {
        timer.startFocus()
        _ = timer.endFocus(completed: true)
        timer.endBreak()

        timer.startFocus()
        _ = timer.endFocus(completed: true)

        XCTAssertEqual(timer.streak.currentStreak, 1) // same day
    }

    // MARK: - JSON Export/Import

    func testExportJSON() {
        timer.startFocus()
        timer.recordArticle(link: "https://a.com", title: "A")
        _ = timer.endFocus(completed: true)

        let json = timer.exportJSON()
        XCTAssertFalse(json.isEmpty)
        XCTAssertTrue(json.contains("Pomodoro"))
        XCTAssertTrue(json.contains("totalSessions"))
    }

    func testImportJSON() {
        timer.startFocus()
        _ = timer.endFocus(completed: true)

        let json = timer.exportJSON()

        let newTimer = ReadingFocusTimer()
        newTimer.clearHistory()
        let imported = newTimer.importJSON(json)
        XCTAssertEqual(imported, 1)
    }

    func testImportDuplicatesSkipped() {
        timer.startFocus()
        _ = timer.endFocus(completed: true)

        let json = timer.exportJSON()
        let imported = timer.importJSON(json) // same timer — should skip
        XCTAssertEqual(imported, 0)
    }

    func testImportInvalidJSON() {
        let imported = timer.importJSON("not json")
        XCTAssertEqual(imported, 0)
    }

    // MARK: - Text Report

    func testGenerateReport() {
        timer.startFocus()
        timer.recordArticle(link: "https://a.com", title: "A")
        _ = timer.endFocus(completed: true)

        let report = timer.generateReport()
        XCTAssertTrue(report.contains("Reading Focus Timer Report"))
        XCTAssertTrue(report.contains("Streak:"))
        XCTAssertTrue(report.contains("Total sessions:"))
        XCTAssertTrue(report.contains("Articles read:"))
        XCTAssertTrue(report.contains("Last 7 days:"))
    }

    func testEmptyReport() {
        let report = timer.generateReport()
        XCTAssertTrue(report.contains("Total sessions: 0"))
        XCTAssertTrue(report.contains("Articles read: 0"))
    }

    // MARK: - Data Management

    func testClearHistory() {
        timer.startFocus()
        _ = timer.endFocus(completed: true)
        XCTAssertEqual(timer.allSessions.count, 1)

        timer.clearHistory()
        XCTAssertEqual(timer.allSessions.count, 0)
        XCTAssertEqual(timer.streak.currentStreak, 0)
    }

    func testPruneOldSessions() {
        timer.startFocus()
        _ = timer.endFocus(completed: true)

        let future = Calendar.current.date(byAdding: .day, value: 1, to: Date())!
        let removed = timer.pruneSessionsBefore(future)
        XCTAssertEqual(removed, 1)
        XCTAssertEqual(timer.allSessions.count, 0)
    }

    func testPruneNothingRemoved() {
        timer.startFocus()
        _ = timer.endFocus(completed: true)

        let past = Calendar.current.date(byAdding: .day, value: -1, to: Date())!
        let removed = timer.pruneSessionsBefore(past)
        XCTAssertEqual(removed, 0)
        XCTAssertEqual(timer.allSessions.count, 1)
    }

    // MARK: - Notifications

    func testFocusStartNotification() {
        let exp = expectation(forNotification: .focusTimerDidStart, object: timer)
        timer.startFocus()
        wait(for: [exp], timeout: 1.0)
    }

    func testFocusCompleteNotification() {
        timer.startFocus()
        let exp = expectation(forNotification: .focusTimerDidComplete, object: timer)
        _ = timer.endFocus(completed: true)
        wait(for: [exp], timeout: 1.0)
    }

    func testBreakStartNotification() {
        timer.startFocus()
        let exp = expectation(forNotification: .focusTimerBreakDidStart, object: timer)
        _ = timer.endFocus(completed: true)
        wait(for: [exp], timeout: 1.0)
    }

    func testBreakEndNotification() {
        timer.startFocus()
        _ = timer.endFocus(completed: true)
        let exp = expectation(forNotification: .focusTimerBreakDidEnd, object: timer)
        timer.endBreak()
        wait(for: [exp], timeout: 1.0)
    }

    func testPauseNotification() {
        timer.startFocus()
        let exp = expectation(forNotification: .focusTimerDidPause, object: timer)
        timer.pause()
        wait(for: [exp], timeout: 1.0)
    }

    func testStreakChangeNotification() {
        let exp = expectation(forNotification: .focusTimerStreakDidChange, object: timer)
        timer.startFocus()
        _ = timer.endFocus(completed: true)
        wait(for: [exp], timeout: 1.0)
    }

    // MARK: - Edge Cases

    func testEndBreakWhileIdleNoOp() {
        timer.endBreak() // should not crash
        XCTAssertEqual(timer.phase, .idle)
    }

    func testCancelWhileIdleNoOp() {
        timer.cancel() // should not crash
        XCTAssertEqual(timer.phase, .idle)
    }

    func testRapidStartEndCycles() {
        for _ in 0..<10 {
            timer.startFocus()
            _ = timer.endFocus(completed: true)
            timer.endBreak()
        }
        XCTAssertEqual(timer.allSessions.count, 10)
        XCTAssertEqual(timer.totalCompletedSessions, 10)
    }

    func testDistractionFreeModeRecordedInSession() {
        timer.startFocus(distractionFree: true)
        let record = timer.endFocus(completed: true)
        XCTAssertTrue(record!.distractionFreeMode)
    }

    func testDistractionFreeModeClearedAfterEnd() {
        timer.startFocus(distractionFree: true)
        _ = timer.endFocus(completed: true)
        XCTAssertFalse(timer.distractionFreeMode)
    }

    func testRecentDailySummariesZeroDays() {
        let summaries = timer.recentDailySummaries(days: 0)
        XCTAssertEqual(summaries.count, 0)
    }

    func testFocusStreakEmpty() {
        let empty = FocusStreak.empty
        XCTAssertEqual(empty.currentStreak, 0)
        XCTAssertEqual(empty.longestStreak, 0)
        XCTAssertNil(empty.lastActiveDate)
    }
}
