//
//  ReadingYearInReviewTests.swift
//  FeedReaderTests
//

import XCTest
@testable import FeedReader

class ReadingYearInReviewTests: XCTestCase {
    
    let reviewer = ReadingYearInReview()
    let cal = Calendar.current
    
    // MARK: - Helpers
    
    private func makeEvent(title: String = "Test Article",
                           feed: String = "Tech Blog",
                           date: Date) -> ReadingStatsManager.ReadEvent {
        return ReadingStatsManager.ReadEvent(
            link: "https://example.com/\(UUID().uuidString)",
            title: title,
            feedName: feed,
            timestamp: date
        )
    }
    
    private func date(_ year: Int, _ month: Int, _ day: Int, hour: Int = 12) -> Date {
        return cal.date(from: DateComponents(year: year, month: month, day: day, hour: hour))!
    }
    
    // MARK: - Empty Report
    
    func testEmptyReportForNoEvents() {
        let report = reviewer.generateReport(for: 2025, from: [])
        XCTAssertEqual(report.year, 2025)
        XCTAssertEqual(report.totalArticles, 0)
        XCTAssertEqual(report.totalFeeds, 0)
        XCTAssertEqual(report.longestStreak, 0)
        XCTAssertNil(report.busiestDay)
        XCTAssertNil(report.busiestHour)
        XCTAssertNil(report.peakMonth)
        XCTAssertNil(report.quietestMonth)
    }
    
    // MARK: - Year Filtering
    
    func testFiltersEventsByYear() {
        let events = [
            makeEvent(date: date(2024, 6, 15)),
            makeEvent(date: date(2025, 3, 10)),
            makeEvent(date: date(2025, 7, 20)),
            makeEvent(date: date(2026, 1, 1)),
        ]
        let report = reviewer.generateReport(for: 2025, from: events)
        XCTAssertEqual(report.totalArticles, 2)
    }
    
    // MARK: - Monthly Breakdown
    
    func testMonthlyBreakdown() {
        let events = [
            makeEvent(date: date(2025, 1, 5)),
            makeEvent(date: date(2025, 1, 10)),
            makeEvent(date: date(2025, 1, 15)),
            makeEvent(date: date(2025, 6, 1)),
        ]
        let report = reviewer.generateReport(for: 2025, from: events)
        XCTAssertEqual(report.monthlyBreakdown[1], 3)
        XCTAssertEqual(report.monthlyBreakdown[6], 1)
        XCTAssertNil(report.monthlyBreakdown[2])
    }
    
    // MARK: - Top Feeds
    
    func testTopFeedsSortedByCount() {
        let events = [
            makeEvent(feed: "Alpha", date: date(2025, 1, 1)),
            makeEvent(feed: "Beta", date: date(2025, 2, 1)),
            makeEvent(feed: "Beta", date: date(2025, 3, 1)),
            makeEvent(feed: "Beta", date: date(2025, 4, 1)),
            makeEvent(feed: "Alpha", date: date(2025, 5, 1)),
        ]
        let report = reviewer.generateReport(for: 2025, from: events)
        XCTAssertEqual(report.topFeeds.first?.name, "Beta")
        XCTAssertEqual(report.topFeeds.first?.count, 3)
        XCTAssertEqual(report.totalFeeds, 2)
    }
    
    // MARK: - Top Topics
    
    func testTopTopicsExtractsKeywords() {
        let events = [
            makeEvent(title: "Swift Programming Tips", date: date(2025, 1, 1)),
            makeEvent(title: "Advanced Swift Techniques", date: date(2025, 2, 1)),
            makeEvent(title: "Python Data Science", date: date(2025, 3, 1)),
            makeEvent(title: "Swift vs Kotlin comparison", date: date(2025, 4, 1)),
        ]
        let report = reviewer.generateReport(for: 2025, from: events)
        XCTAssertEqual(report.topTopics.first?.topic, "swift")
        XCTAssertEqual(report.topTopics.first?.count, 3)
    }
    
    func testStopWordsExcluded() {
        let events = [
            makeEvent(title: "The best way to learn", date: date(2025, 1, 1)),
            makeEvent(title: "The best way for learning", date: date(2025, 2, 1)),
        ]
        let report = reviewer.generateReport(for: 2025, from: events)
        let topics = report.topTopics.map { $0.topic }
        XCTAssertFalse(topics.contains("the"))
        XCTAssertFalse(topics.contains("for"))
    }
    
    // MARK: - Busiest Day
    
    func testBusiestDayFindsMaxDay() {
        let events = [
            makeEvent(date: date(2025, 3, 15, hour: 9)),
            makeEvent(date: date(2025, 3, 15, hour: 10)),
            makeEvent(date: date(2025, 3, 15, hour: 14)),
            makeEvent(date: date(2025, 5, 1)),
        ]
        let report = reviewer.generateReport(for: 2025, from: events)
        XCTAssertNotNil(report.busiestDay)
        XCTAssertEqual(report.busiestDay?.count, 3)
    }
    
    // MARK: - Busiest Hour
    
    func testBusiestHour() {
        let events = [
            makeEvent(date: date(2025, 1, 1, hour: 8)),
            makeEvent(date: date(2025, 1, 2, hour: 8)),
            makeEvent(date: date(2025, 1, 3, hour: 8)),
            makeEvent(date: date(2025, 1, 4, hour: 20)),
        ]
        let report = reviewer.generateReport(for: 2025, from: events)
        XCTAssertEqual(report.busiestHour, 8)
    }
    
    // MARK: - Longest Streak
    
    func testLongestStreak() {
        let events = [
            makeEvent(date: date(2025, 1, 1)),
            makeEvent(date: date(2025, 1, 2)),
            makeEvent(date: date(2025, 1, 3)),
            makeEvent(date: date(2025, 1, 5)),
            makeEvent(date: date(2025, 1, 6)),
        ]
        let report = reviewer.generateReport(for: 2025, from: events)
        XCTAssertEqual(report.longestStreak, 3)
    }
    
    func testSingleDayStreak() {
        let events = [makeEvent(date: date(2025, 6, 15))]
        let report = reviewer.generateReport(for: 2025, from: events)
        XCTAssertEqual(report.longestStreak, 1)
    }
    
    // MARK: - Averages
    
    func testAveragePerDay() {
        let events = [
            makeEvent(date: date(2025, 1, 1)),
            makeEvent(date: date(2025, 1, 1)),
            makeEvent(date: date(2025, 1, 3)),
        ]
        // 3 articles over 3 days (Jan 1-3)
        let report = reviewer.generateReport(for: 2025, from: events)
        XCTAssertEqual(report.averagePerDay, 1.0, accuracy: 0.01)
    }
    
    // MARK: - Peak / Quietest Month
    
    func testPeakAndQuietestMonth() {
        let events = [
            makeEvent(date: date(2025, 3, 1)),
            makeEvent(date: date(2025, 3, 5)),
            makeEvent(date: date(2025, 3, 10)),
            makeEvent(date: date(2025, 9, 1)),
        ]
        let report = reviewer.generateReport(for: 2025, from: events)
        XCTAssertEqual(report.peakMonth, 3)
        XCTAssertEqual(report.quietestMonth, 9)
    }
    
    // MARK: - Weekday vs Weekend
    
    func testWeekdayVsWeekend() {
        // Jan 4 2025 = Saturday, Jan 5 = Sunday, Jan 6 = Monday
        let events = [
            makeEvent(date: date(2025, 1, 4)),  // Sat
            makeEvent(date: date(2025, 1, 5)),  // Sun
            makeEvent(date: date(2025, 1, 6)),  // Mon
            makeEvent(date: date(2025, 1, 7)),  // Tue
            makeEvent(date: date(2025, 1, 8)),  // Wed
        ]
        let report = reviewer.generateReport(for: 2025, from: events)
        XCTAssertEqual(report.weekdayVsWeekend.weekend, 2)
        XCTAssertEqual(report.weekdayVsWeekend.weekday, 3)
    }
    
    // MARK: - Format Summary
    
    func testFormatSummaryContainsKey() {
        let events = [
            makeEvent(feed: "My Feed", date: date(2025, 1, 1)),
            makeEvent(feed: "My Feed", date: date(2025, 1, 2)),
        ]
        let report = reviewer.generateReport(for: 2025, from: events)
        let summary = reviewer.formatSummary(report)
        XCTAssertTrue(summary.contains("2025"))
        XCTAssertTrue(summary.contains("Total articles read: 2"))
        XCTAssertTrue(summary.contains("My Feed"))
    }
    
    func testFormatSummaryEmptyReport() {
        let report = reviewer.generateReport(for: 2025, from: [])
        let summary = reviewer.formatSummary(report)
        XCTAssertTrue(summary.contains("Total articles read: 0"))
    }
    
    // MARK: - Busiest Day of Week
    
    func testBusiestDayOfWeek() {
        // Jan 6, 13, 20 2025 are all Mondays (weekday = 2)
        let events = [
            makeEvent(date: date(2025, 1, 6)),
            makeEvent(date: date(2025, 1, 13)),
            makeEvent(date: date(2025, 1, 20)),
            makeEvent(date: date(2025, 1, 7)),  // Tuesday
        ]
        let report = reviewer.generateReport(for: 2025, from: events)
        XCTAssertEqual(report.busiestDayOfWeek, 2) // Monday
    }
    
    // MARK: - Top Feeds Limited to 10
    
    func testTopFeedsCappedAtTen() {
        var events: [ReadingStatsManager.ReadEvent] = []
        for i in 0..<15 {
            events.append(makeEvent(feed: "Feed\(i)", date: date(2025, 1, i + 1)))
        }
        let report = reviewer.generateReport(for: 2025, from: events)
        XCTAssertEqual(report.topFeeds.count, 10)
    }
    
    // MARK: - Topics Capped at 10
    
    func testTopTopicsCappedAtTen() {
        var events: [ReadingStatsManager.ReadEvent] = []
        let words = ["alpha", "bravo", "charlie", "delta", "echo",
                     "foxtrot", "golf", "hotel", "india", "juliet",
                     "kilo", "lima"]
        for (i, word) in words.enumerated() {
            events.append(makeEvent(title: "\(word) article content", date: date(2025, 1, i + 1)))
        }
        let report = reviewer.generateReport(for: 2025, from: events)
        XCTAssertLessThanOrEqual(report.topTopics.count, 10)
    }
    
    // MARK: - First and Last Article Date
    
    func testFirstAndLastArticleDate() {
        let events = [
            makeEvent(date: date(2025, 3, 15)),
            makeEvent(date: date(2025, 1, 1)),
            makeEvent(date: date(2025, 12, 31)),
        ]
        let report = reviewer.generateReport(for: 2025, from: events)
        let firstDay = cal.component(.day, from: report.firstArticleDate!)
        let firstMonth = cal.component(.month, from: report.firstArticleDate!)
        XCTAssertEqual(firstMonth, 1)
        XCTAssertEqual(firstDay, 1)
        let lastMonth = cal.component(.month, from: report.lastArticleDate!)
        XCTAssertEqual(lastMonth, 12)
    }
}
