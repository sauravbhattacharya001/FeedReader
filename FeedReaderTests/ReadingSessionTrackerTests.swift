//
//  ReadingSessionTrackerTests.swift
//  FeedReaderTests
//

import XCTest
@testable import FeedReader

class ReadingSessionTrackerTests: XCTestCase {

    var tracker: ReadingSessionTracker!

    override func setUp() {
        super.setUp()
        tracker = ReadingSessionTracker()
        // Clear any persisted state
        UserDefaults.standard.removeObject(forKey: "ReadingSessionTracker.sessions")
    }

    override func tearDown() {
        tracker.clearHistory()
        if tracker.activeSession != nil {
            tracker.endSession()
        }
        super.tearDown()
    }

    // MARK: - Session Lifecycle

    func testStartSession() {
        let session = tracker.startSession()
        XCTAssertNotNil(tracker.activeSession)
        XCTAssertTrue(session.isActive)
        XCTAssertEqual(session.articleCount, 0)
        XCTAssertNil(session.endedAt)
        XCTAssertTrue(tracker.isReading)
        XCTAssertFalse(tracker.isPaused)
    }

    func testStartSessionWithTag() {
        let session = tracker.startSession(tag: "commute")
        XCTAssertEqual(session.tag, "commute")
    }

    func testStartSessionEndsExisting() {
        tracker.startSession(tag: "first")
        tracker.startSession(tag: "second")
        XCTAssertEqual(tracker.activeSession?.tag, "second")
        XCTAssertEqual(tracker.totalSessionCount, 1) // first session archived
    }

    func testEndSession() {
        tracker.startSession()
        let completed = tracker.endSession()
        XCTAssertNotNil(completed)
        XCTAssertNotNil(completed?.endedAt)
        XCTAssertFalse(completed!.isActive)
        XCTAssertNil(tracker.activeSession)
        XCTAssertFalse(tracker.isReading)
        XCTAssertEqual(tracker.totalSessionCount, 1)
    }

    func testEndSessionWhenNoneActive() {
        let result = tracker.endSession()
        XCTAssertNil(result)
    }

    func testPauseAndResume() {
        tracker.startSession()
        XCTAssertTrue(tracker.isReading)
        XCTAssertFalse(tracker.isPaused)

        tracker.pauseSession()
        XCTAssertFalse(tracker.isReading)
        XCTAssertTrue(tracker.isPaused)

        tracker.resumeSession()
        XCTAssertTrue(tracker.isReading)
        XCTAssertFalse(tracker.isPaused)
    }

    func testPauseWhenNotActive() {
        tracker.pauseSession() // should be no-op
        XCTAssertFalse(tracker.isPaused)
    }

    func testResumeWhenNotPaused() {
        tracker.startSession()
        tracker.resumeSession() // should be no-op, already running
        XCTAssertTrue(tracker.isReading)
    }

    func testPauseAccumulatesTime() {
        tracker.startSession()
        tracker.pauseSession()
        // Simulate a small delay by checking totalPauseTime after resume
        tracker.resumeSession()
        let session = tracker.activeSession!
        XCTAssertGreaterThanOrEqual(session.totalPauseTime, 0)
    }

    func testEndSessionWhilePaused() {
        tracker.startSession()
        tracker.pauseSession()
        let completed = tracker.endSession()
        XCTAssertNotNil(completed)
        XCTAssertNotNil(completed?.endedAt)
        XCTAssertGreaterThanOrEqual(completed!.totalPauseTime, 0)
    }

    // MARK: - Article Tracking

    func testStartArticle() {
        tracker.startSession()
        tracker.startArticle(link: "https://example.com/1", title: "Test Article", feedName: "Test Feed")
        XCTAssertEqual(tracker.currentSessionArticleCount, 1)
    }

    func testStartArticleWithNoSession() {
        tracker.startArticle(link: "https://example.com/1", title: "Test", feedName: "Feed")
        // No crash, just no-op
        XCTAssertEqual(tracker.currentSessionArticleCount, 0)
    }

    func testStartArticleWhilePaused() {
        tracker.startSession()
        tracker.pauseSession()
        tracker.startArticle(link: "https://example.com/1", title: "Test", feedName: "Feed")
        XCTAssertEqual(tracker.currentSessionArticleCount, 0) // ignored while paused
    }

    func testMultipleArticles() {
        tracker.startSession()
        tracker.startArticle(link: "https://example.com/1", title: "Article 1", feedName: "Feed A")
        tracker.startArticle(link: "https://example.com/2", title: "Article 2", feedName: "Feed B")
        tracker.startArticle(link: "https://example.com/3", title: "Article 3", feedName: "Feed A")
        XCTAssertEqual(tracker.currentSessionArticleCount, 3)
    }

    func testFinishArticle() {
        tracker.startSession()
        tracker.startArticle(link: "https://example.com/1", title: "Test", feedName: "Feed")
        tracker.finishArticle()
        // Should still have 1 article, just stopped timing
        XCTAssertEqual(tracker.currentSessionArticleCount, 1)
    }

    func testArticlesSurviveSessionEnd() {
        tracker.startSession()
        tracker.startArticle(link: "https://example.com/1", title: "Article 1", feedName: "Feed A")
        tracker.finishArticle()
        tracker.startArticle(link: "https://example.com/2", title: "Article 2", feedName: "Feed B")

        let completed = tracker.endSession()!
        XCTAssertEqual(completed.articleCount, 2)
        XCTAssertEqual(completed.articles[0].title, "Article 1")
        XCTAssertEqual(completed.articles[0].feedName, "Feed A")
        XCTAssertEqual(completed.articles[1].title, "Article 2")
    }

    // MARK: - ReadingSession Model

    func testSessionActiveDuration() {
        var session = ReadingSession(startedAt: Date(timeIntervalSinceNow: -300)) // 5 min ago
        session.totalPauseTime = 60 // 1 min paused
        // activeDuration should be ~240s (5 min - 1 min pause)
        XCTAssertGreaterThan(session.activeDuration, 230)
        XCTAssertLessThan(session.activeDuration, 250)
    }

    func testSessionActiveDurationCompleted() {
        var session = ReadingSession(startedAt: Date(timeIntervalSinceNow: -600))
        session.endedAt = Date(timeIntervalSinceNow: -300) // ran for 5 min
        session.totalPauseTime = 0
        let duration = session.activeDuration
        XCTAssertGreaterThan(duration, 290)
        XCTAssertLessThan(duration, 310)
    }

    func testSessionAverageTimePerArticle() {
        var session = ReadingSession()
        XCTAssertNil(session.averageTimePerArticle) // no articles

        session.articles = [
            SessionArticle(link: "a", title: "A", feedName: "F", timeSpent: 60),
            SessionArticle(link: "b", title: "B", feedName: "F", timeSpent: 120),
        ]
        XCTAssertEqual(session.averageTimePerArticle, 90) // (60 + 120) / 2
    }

    func testSessionArticlesPerMinute() {
        var session = ReadingSession(startedAt: Date(timeIntervalSinceNow: -600))
        session.endedAt = Date() // 10 min session
        session.totalPauseTime = 0
        session.articles = [
            SessionArticle(link: "a", title: "A", feedName: "F", timeSpent: 60),
            SessionArticle(link: "b", title: "B", feedName: "F", timeSpent: 120),
            SessionArticle(link: "c", title: "C", feedName: "F", timeSpent: 180),
        ]
        let rate = session.articlesPerMinute!
        XCTAssertGreaterThan(rate, 0.25) // 3 articles / 10 min = 0.3
        XCTAssertLessThan(rate, 0.35)
    }

    func testSessionArticlesPerMinuteZeroDuration() {
        var session = ReadingSession()
        session.endedAt = session.startedAt // zero duration
        XCTAssertNil(session.articlesPerMinute)
    }

    // MARK: - Query

    func testCompletedSessions() {
        tracker.startSession(tag: "one")
        tracker.endSession()
        tracker.startSession(tag: "two")
        tracker.endSession()

        let completed = tracker.completedSessions
        XCTAssertEqual(completed.count, 2)
        // Newest first
        XCTAssertEqual(completed[0].tag, "two")
        XCTAssertEqual(completed[1].tag, "one")
    }

    func testSessionsLastDays() {
        tracker.startSession()
        tracker.endSession()
        // Should find the session we just completed (within last 7 days)
        let recent = tracker.sessions(lastDays: 7)
        XCTAssertEqual(recent.count, 1)
    }

    func testSessionsWithTag() {
        tracker.startSession(tag: "commute")
        tracker.endSession()
        tracker.startSession(tag: "research")
        tracker.endSession()
        tracker.startSession(tag: "commute")
        tracker.endSession()

        let commute = tracker.sessions(withTag: "commute")
        XCTAssertEqual(commute.count, 2)
        let research = tracker.sessions(withTag: "research")
        XCTAssertEqual(research.count, 1)
    }

    func testAllTags() {
        tracker.startSession(tag: "commute")
        tracker.endSession()
        tracker.startSession(tag: "research")
        tracker.endSession()
        tracker.startSession() // no tag
        tracker.endSession()
        tracker.startSession(tag: "commute") // duplicate
        tracker.endSession()

        let tags = tracker.allTags
        XCTAssertEqual(tags.count, 2)
        XCTAssertTrue(tags.contains("commute"))
        XCTAssertTrue(tags.contains("research"))
    }

    func testSessionById() {
        let started = tracker.startSession()
        let found = tracker.session(byId: started.id)
        XCTAssertEqual(found?.id, started.id)
    }

    func testSessionByIdCompleted() {
        let started = tracker.startSession()
        let id = started.id
        tracker.endSession()
        let found = tracker.session(byId: id)
        XCTAssertEqual(found?.id, id)
    }

    func testSessionByIdNotFound() {
        let result = tracker.session(byId: "nonexistent")
        XCTAssertNil(result)
    }

    // MARK: - Summary

    func testSummaryEmpty() {
        let summary = tracker.summary(for: [])
        XCTAssertEqual(summary.sessionCount, 0)
        XCTAssertEqual(summary.totalReadingTime, 0)
        XCTAssertEqual(summary.totalArticles, 0)
        XCTAssertNil(summary.topTag)
    }

    func testSummaryWithSessions() {
        var s1 = ReadingSession(startedAt: Date(timeIntervalSinceNow: -600), tag: "commute")
        s1.endedAt = Date(timeIntervalSinceNow: -300) // 5 min
        s1.articles = [
            SessionArticle(link: "a", title: "A", feedName: "TechCrunch", timeSpent: 120),
            SessionArticle(link: "b", title: "B", feedName: "Ars", timeSpent: 180),
        ]

        var s2 = ReadingSession(startedAt: Date(timeIntervalSinceNow: -1200), tag: "commute")
        s2.endedAt = Date(timeIntervalSinceNow: -900) // 5 min
        s2.articles = [
            SessionArticle(link: "c", title: "C", feedName: "TechCrunch", timeSpent: 300),
        ]

        let summary = tracker.summary(for: [s1, s2])
        XCTAssertEqual(summary.sessionCount, 2)
        XCTAssertEqual(summary.totalArticles, 3)
        XCTAssertEqual(summary.topTag, "commute")
        XCTAssertGreaterThan(summary.averageSessionDuration, 0)
        XCTAssertEqual(summary.averageArticlesPerSession, 1.5)
        // TechCrunch should be top feed (2 articles)
        XCTAssertEqual(summary.topFeeds.first?.name, "TechCrunch")
        XCTAssertEqual(summary.topFeeds.first?.count, 2)
    }

    func testWeeklySummary() {
        tracker.startSession()
        tracker.startArticle(link: "https://example.com/1", title: "Test", feedName: "Feed")
        tracker.endSession()

        let weekly = tracker.weeklySummary
        XCTAssertEqual(weekly.sessionCount, 1)
        XCTAssertEqual(weekly.totalArticles, 1)
    }

    func testMonthlySummary() {
        tracker.startSession()
        tracker.endSession()

        let monthly = tracker.monthlySummary
        XCTAssertEqual(monthly.sessionCount, 1)
    }

    // MARK: - Export

    func testExportAsJSON() {
        tracker.startSession(tag: "test")
        tracker.startArticle(link: "https://example.com/1", title: "Article", feedName: "Feed")
        tracker.endSession()

        let json = tracker.exportAsJSON()
        XCTAssertNotNil(json)
        // Should be valid JSON array
        if let data = json {
            let parsed = try? JSONSerialization.jsonObject(with: data)
            XCTAssertNotNil(parsed as? [[String: Any]])
        }
    }

    func testExportAsText() {
        tracker.startSession(tag: "research")
        tracker.startArticle(link: "https://example.com/1", title: "Deep Learning", feedName: "ArXiv")
        tracker.endSession()

        let text = tracker.exportAsText()
        XCTAssertTrue(text.contains("Reading Session History"))
        XCTAssertTrue(text.contains("[research]"))
        XCTAssertTrue(text.contains("Deep Learning"))
        XCTAssertTrue(text.contains("ArXiv"))
    }

    func testExportEmptyHistory() {
        let text = tracker.exportAsText()
        XCTAssertTrue(text.contains("Reading Session History"))
        // Should still produce header even with no sessions
    }

    // MARK: - Management

    func testDeleteSession() {
        tracker.startSession()
        let session = tracker.endSession()!
        XCTAssertEqual(tracker.totalSessionCount, 1)

        let deleted = tracker.deleteSession(id: session.id)
        XCTAssertTrue(deleted)
        XCTAssertEqual(tracker.totalSessionCount, 0)
    }

    func testDeleteNonexistentSession() {
        let deleted = tracker.deleteSession(id: "nope")
        XCTAssertFalse(deleted)
    }

    func testClearHistory() {
        tracker.startSession()
        tracker.endSession()
        tracker.startSession()
        tracker.endSession()
        XCTAssertEqual(tracker.totalSessionCount, 2)

        tracker.clearHistory()
        XCTAssertEqual(tracker.totalSessionCount, 0)
    }

    // MARK: - Notifications

    func testSessionChangeNotification() {
        let expectation = XCTNSNotificationExpectation(
            name: .readingSessionDidChange,
            object: tracker
        )
        tracker.startSession()
        wait(for: [expectation], timeout: 1.0)
    }

    func testSessionCompleteNotification() {
        tracker.startSession()
        let expectation = XCTNSNotificationExpectation(
            name: .readingSessionDidComplete,
            object: tracker
        )
        tracker.endSession()
        wait(for: [expectation], timeout: 1.0)
    }

    // MARK: - SessionArticle Model

    func testSessionArticleDefaults() {
        let article = SessionArticle(link: "https://example.com", title: "Test", feedName: "Feed")
        XCTAssertEqual(article.timeSpent, 0)
        XCTAssertEqual(article.link, "https://example.com")
        XCTAssertEqual(article.title, "Test")
        XCTAssertEqual(article.feedName, "Feed")
    }

    // MARK: - Duration Formatting (via export)

    func testDurationFormatting() {
        // Create sessions with known durations and export to verify formatting
        var session = ReadingSession(startedAt: Date(timeIntervalSinceNow: -3661)) // 1h 1m 1s ago
        session.endedAt = Date()
        session.totalPauseTime = 0
        session.articles = []

        let summary = tracker.summary(for: [session])
        // Just verify it doesn't crash and produces reasonable values
        XCTAssertGreaterThan(summary.totalReadingTime, 3650)
        XCTAssertLessThan(summary.totalReadingTime, 3670)
    }

    // MARK: - Edge Cases

    func testSessionWithNoArticlesHasNilAverages() {
        let session = ReadingSession()
        XCTAssertNil(session.averageTimePerArticle)
        XCTAssertNil(session.articlesPerMinute)
        XCTAssertEqual(session.articleCount, 0)
    }

    func testActiveDurationNeverNegative() {
        var session = ReadingSession()
        session.totalPauseTime = 999999 // Way more than wall time
        XCTAssertGreaterThanOrEqual(session.activeDuration, 0)
    }

    func testMultipleStartEndCycles() {
        for i in 0..<5 {
            tracker.startSession(tag: "cycle-\(i)")
            tracker.startArticle(link: "https://example.com/\(i)", title: "Art \(i)", feedName: "F")
            tracker.endSession()
        }
        XCTAssertEqual(tracker.totalSessionCount, 5)
        XCTAssertEqual(tracker.completedSessions[0].tag, "cycle-4") // newest first
    }
}
