//
//  FeedReadingGoalTrackerTests.swift
//  FeedReaderCoreTests
//

import XCTest
@testable import FeedReaderCore

final class FeedReadingGoalTrackerTests: XCTestCase {

    private var calendar: Calendar {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        return cal
    }

    private func fixedDate(_ year: Int, _ month: Int, _ day: Int, _ hour: Int = 12) -> Date {
        var components = DateComponents()
        components.year = year
        components.month = month
        components.day = day
        components.hour = hour
        components.timeZone = TimeZone(identifier: "UTC")
        return calendar.date(from: components)!
    }

    private func makeEvent(_ id: String, topic: String, date: Date, minutes: Double = 5.0) -> ReadEvent {
        return ReadEvent(articleId: id, topic: topic, readAt: date, minutesSpent: minutes, feedName: "TestFeed")
    }

    // MARK: - Tests

    func testEmptyEventsReturnsZeroProgress() {
        let goals = [ReadingGoal(type: .articleCount, period: .daily, target: 5)]
        let now = fixedDate(2026, 6, 1)
        let tracker = FeedReadingGoalTracker(goals: goals, calendar: calendar, now: { now })
        let report = tracker.report(from: [])

        XCTAssertEqual(report.dailyArticleCount, 0)
        XCTAssertEqual(report.weeklyArticleCount, 0)
        XCTAssertEqual(report.goals.first?.current, 0)
        XCTAssertEqual(report.goals.first?.isComplete, false)
        XCTAssertEqual(report.grade, "F")
    }

    func testDailyArticleGoalComplete() {
        let now = fixedDate(2026, 6, 1, 18)
        let goals = [ReadingGoal(type: .articleCount, period: .daily, target: 3)]
        let events = (1...3).map { i in
            makeEvent("art\(i)", topic: "tech", date: fixedDate(2026, 6, 1, 10 + i))
        }
        let tracker = FeedReadingGoalTracker(goals: goals, calendar: calendar, now: { now })
        let report = tracker.report(from: events)

        XCTAssertEqual(report.goals.first?.isComplete, true)
        XCTAssertEqual(report.goals.first?.current, 3)
        XCTAssertEqual(report.goals.first?.remaining, 0)
    }

    func testWeeklyTopicDiversity() {
        let now = fixedDate(2026, 6, 5, 12)
        let goals = [ReadingGoal(type: .topicDiversity, period: .weekly, target: 3)]
        let events = [
            makeEvent("a1", topic: "tech", date: fixedDate(2026, 6, 2)),
            makeEvent("a2", topic: "science", date: fixedDate(2026, 6, 3)),
            makeEvent("a3", topic: "politics", date: fixedDate(2026, 6, 4)),
        ]
        let tracker = FeedReadingGoalTracker(goals: goals, calendar: calendar, now: { now })
        let report = tracker.report(from: events)

        XCTAssertEqual(report.weeklyTopicCount, 3)
        XCTAssertEqual(report.goals.first?.isComplete, true)
    }

    func testMinutesReadGoal() {
        let now = fixedDate(2026, 6, 1, 20)
        let goals = [ReadingGoal(type: .minutesRead, period: .daily, target: 30)]
        let events = [
            makeEvent("a1", topic: "tech", date: fixedDate(2026, 6, 1, 10), minutes: 15.0),
            makeEvent("a2", topic: "tech", date: fixedDate(2026, 6, 1, 14), minutes: 20.0),
        ]
        let tracker = FeedReadingGoalTracker(goals: goals, calendar: calendar, now: { now })
        let report = tracker.report(from: events)

        XCTAssertEqual(report.goals.first?.current, 35)
        XCTAssertEqual(report.goals.first?.isComplete, true)
    }

    func testStreakCalculation() {
        let now = fixedDate(2026, 6, 5, 12)
        let events = [
            makeEvent("a1", topic: "t", date: fixedDate(2026, 6, 3)),
            makeEvent("a2", topic: "t", date: fixedDate(2026, 6, 4)),
            makeEvent("a3", topic: "t", date: fixedDate(2026, 6, 5, 9)),
        ]
        let goals = [ReadingGoal(type: .articleCount, period: .daily, target: 1)]
        let tracker = FeedReadingGoalTracker(goals: goals, calendar: calendar, now: { now })
        let report = tracker.report(from: events)

        XCTAssertEqual(report.streak.currentDays, 3)
        XCTAssertTrue(report.streak.activeToday)
    }

    func testStreakBroken() {
        let now = fixedDate(2026, 6, 5, 12)
        // Gap on June 4
        let events = [
            makeEvent("a1", topic: "t", date: fixedDate(2026, 6, 2)),
            makeEvent("a2", topic: "t", date: fixedDate(2026, 6, 3)),
            makeEvent("a3", topic: "t", date: fixedDate(2026, 6, 5, 9)),
        ]
        let goals = [ReadingGoal(type: .articleCount, period: .daily, target: 1)]
        let tracker = FeedReadingGoalTracker(goals: goals, calendar: calendar, now: { now })
        let report = tracker.report(from: events)

        XCTAssertEqual(report.streak.currentDays, 1) // Only today
    }

    func testGradeA() {
        let now = fixedDate(2026, 6, 5, 20)
        let goals = [ReadingGoal(type: .articleCount, period: .daily, target: 2)]
        // 7-day streak + goal met
        var events: [ReadEvent] = []
        for day in 0..<7 {
            let d = fixedDate(2026, 5, 30 + day, 10)
            events.append(makeEvent("a\(day)a", topic: "t", date: d))
            events.append(makeEvent("a\(day)b", topic: "s", date: d))
        }
        let tracker = FeedReadingGoalTracker(goals: goals, calendar: calendar, now: { now })
        let report = tracker.report(from: events)

        XCTAssertEqual(report.grade, "A")
    }

    func testMarkdownContainsSections() {
        let now = fixedDate(2026, 6, 1, 12)
        let goals = [ReadingGoal(type: .articleCount, period: .daily, target: 1)]
        let events = [makeEvent("a1", topic: "t", date: now)]
        let tracker = FeedReadingGoalTracker(goals: goals, calendar: calendar, now: { now })
        let report = tracker.report(from: events)
        let md = report.markdown

        XCTAssertTrue(md.contains("## Summary"))
        XCTAssertTrue(md.contains("## Goals"))
        XCTAssertTrue(md.contains("## Streak"))
    }

    func testHeadlineFormat() {
        let now = fixedDate(2026, 6, 1, 12)
        let goals = [ReadingGoal(type: .articleCount, period: .daily, target: 1)]
        let events = [makeEvent("a1", topic: "t", date: now)]
        let tracker = FeedReadingGoalTracker(goals: goals, calendar: calendar, now: { now })
        let report = tracker.report(from: events)

        XCTAssertTrue(report.headline.hasPrefix("READING:"))
    }

    func testSuggestionsWhenDiversityLow() {
        let now = fixedDate(2026, 6, 5, 12)
        let goals = [ReadingGoal(type: .topicDiversity, period: .weekly, target: 3)]
        let events = (1...5).map { i in
            makeEvent("a\(i)", topic: "tech", date: fixedDate(2026, 6, 2 + (i % 3)))
        }
        let tracker = FeedReadingGoalTracker(goals: goals, calendar: calendar, now: { now })
        let report = tracker.report(from: events)

        XCTAssertTrue(report.suggestions.contains { $0.contains("Diversify") })
    }

    func testNoGoalsGradeA() {
        let now = fixedDate(2026, 6, 1)
        let tracker = FeedReadingGoalTracker(goals: [], calendar: calendar, now: { now })
        let report = tracker.report(from: [])
        XCTAssertEqual(report.grade, "A")
    }

    func testTrendImproving() {
        let now = fixedDate(2026, 6, 2, 18)
        let goals = [ReadingGoal(type: .articleCount, period: .daily, target: 5)]
        let events = [
            // Yesterday: 1 article
            makeEvent("y1", topic: "t", date: fixedDate(2026, 6, 1, 10)),
            // Today: 3 articles
            makeEvent("t1", topic: "t", date: fixedDate(2026, 6, 2, 10)),
            makeEvent("t2", topic: "t", date: fixedDate(2026, 6, 2, 11)),
            makeEvent("t3", topic: "t", date: fixedDate(2026, 6, 2, 12)),
        ]
        let tracker = FeedReadingGoalTracker(goals: goals, calendar: calendar, now: { now })
        let report = tracker.report(from: events)

        XCTAssertEqual(report.goals.first?.trend, 1) // Improving
    }
}
