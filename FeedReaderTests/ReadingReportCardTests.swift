//
//  ReadingReportCardTests.swift
//  FeedReaderTests
//

import XCTest
@testable import FeedReader

final class ReadingReportCardTests: XCTestCase {

    var manager: ReadingReportCard!

    override func setUp() {
        super.setUp()
        manager = ReadingReportCard()
        manager.clearAll()
    }

    // MARK: - Helpers

    private func makeEvents(count: Int, days: Int = 7, feedName: String = "TechFeed",
                            category: String? = "Tech", avgTime: Double = 120) -> [ReadEventInput] {
        let calendar = Calendar.current
        let end = Date()
        var events: [ReadEventInput] = []
        for i in 0..<count {
            let dayOffset = -(i % days)
            let date = calendar.date(byAdding: .day, value: dayOffset, to: end)!
            events.append(ReadEventInput(
                articleTitle: "Article \(i)",
                feedName: feedName,
                category: category,
                date: date,
                readingTimeSeconds: avgTime
            ))
        }
        return events
    }

    private func makeDiverseEvents(feedCount: Int, articlesPerFeed: Int = 3) -> [ReadEventInput] {
        let calendar = Calendar.current
        let end = Date()
        var events: [ReadEventInput] = []
        for f in 0..<feedCount {
            for a in 0..<articlesPerFeed {
                let date = calendar.date(byAdding: .day, value: -(a % 7), to: end)!
                events.append(ReadEventInput(
                    articleTitle: "Feed\(f) Art\(a)",
                    feedName: "Feed \(f)",
                    category: "Category \(f % 5)",
                    date: date,
                    readingTimeSeconds: 150
                ))
            }
        }
        return events
    }

    // MARK: - Report Generation

    func testGenerateWeeklyReport() {
        let events = makeEvents(count: 28, days: 7) // 4/day
        let report = manager.generateReport(period: .weekly, readEvents: events, engagementCount: 5, newFeedsCount: 1, currentStreak: 3)

        XCTAssertEqual(report.period, .weekly)
        XCTAssertEqual(report.dimensionScores.count, 6)
        XCTAssertFalse(report.id.isEmpty)
        XCTAssertEqual(manager.reportCount, 1)
    }

    func testGenerateMonthlyReport() {
        let events = makeEvents(count: 60, days: 30)
        let report = manager.generateReport(period: .monthly, readEvents: events, engagementCount: 10)

        XCTAssertEqual(report.period, .monthly)
        XCTAssertEqual(report.data.totalArticlesRead, 60)
    }

    func testEmptyReportGivesLowGrades() {
        let report = manager.generateReport(period: .weekly, readEvents: [])

        XCTAssertEqual(report.overallGrade, .f)
        XCTAssertEqual(report.compositeGPA, 0.0)
        XCTAssertEqual(report.data.totalArticlesRead, 0)
    }

    func testHighVolumeGivesGoodVolumeGrade() {
        let events = makeEvents(count: 35, days: 7) // 5/day = 100%
        let report = manager.generateReport(period: .weekly, readEvents: events)

        let volumeScore = report.dimensionScores.first { $0.dimension == .volume }
        XCTAssertNotNil(volumeScore)
        XCTAssertGreaterThanOrEqual(volumeScore!.score, 90)
    }

    func testConsistencyAllDaysActive() {
        // 1 article per day for 7 days
        let calendar = Calendar.current
        let end = Date()
        var events: [ReadEventInput] = []
        for d in 0..<7 {
            let date = calendar.date(byAdding: .day, value: -d, to: end)!
            events.append(ReadEventInput(
                articleTitle: "Day \(d)", feedName: "F", category: nil,
                date: date, readingTimeSeconds: 60
            ))
        }
        let report = manager.generateReport(period: .weekly, readEvents: events)
        let consistency = report.dimensionScores.first { $0.dimension == .consistency }
        XCTAssertNotNil(consistency)
        XCTAssertEqual(consistency!.score, 100.0)
    }

    func testDiversityMultipleFeeds() {
        let events = makeDiverseEvents(feedCount: 8)
        let report = manager.generateReport(period: .weekly, readEvents: events)

        let diversity = report.dimensionScores.first { $0.dimension == .diversity }
        XCTAssertNotNil(diversity)
        XCTAssertGreaterThan(diversity!.score, 80)
    }

    func testDepthLongReadingTime() {
        let events = makeEvents(count: 10, avgTime: 300) // 5 min avg
        let report = manager.generateReport(period: .weekly, readEvents: events)

        let depth = report.dimensionScores.first { $0.dimension == .depth }
        XCTAssertNotNil(depth)
        XCTAssertGreaterThan(depth!.score, 90)
    }

    func testDiscoveryScore() {
        let report = manager.generateReport(period: .weekly, readEvents: makeEvents(count: 5), newFeedsCount: 2)
        let discovery = report.dimensionScores.first { $0.dimension == .discovery }
        XCTAssertNotNil(discovery)
        XCTAssertEqual(discovery!.score, 100.0)
    }

    func testEngagementScore() {
        let events = makeEvents(count: 10)
        let report = manager.generateReport(period: .weekly, readEvents: events, engagementCount: 3) // 30%
        let engagement = report.dimensionScores.first { $0.dimension == .engagement }
        XCTAssertNotNil(engagement)
        XCTAssertEqual(engagement!.score, 100.0)
    }

    // MARK: - Trends

    func testTrendImprovingOnSecondReport() {
        // First report: low volume
        _ = manager.generateReport(period: .weekly, readEvents: makeEvents(count: 5))
        // Second report: high volume
        let report = manager.generateReport(period: .weekly, readEvents: makeEvents(count: 35))
        XCTAssertTrue(report.trend == .improving || report.trend == .newMetric)
    }

    func testTrendNewOnFirstReport() {
        let report = manager.generateReport(period: .weekly, readEvents: makeEvents(count: 10))
        XCTAssertEqual(report.trend, .newMetric)
    }

    // MARK: - Achievements

    func testBookwormAchievement() {
        let events = makeEvents(count: 55)
        let report = manager.generateReport(period: .weekly, readEvents: events)
        let hasBookworm = report.achievements.contains { $0.id == "bookworm" }
        XCTAssertTrue(hasBookworm)
    }

    func testExplorerAchievement() {
        let events = makeDiverseEvents(feedCount: 12, articlesPerFeed: 1)
        let report = manager.generateReport(period: .weekly, readEvents: events)
        let hasExplorer = report.achievements.contains { $0.id == "explorer" }
        XCTAssertTrue(hasExplorer)
    }

    func testStreakMasterAchievement() {
        let report = manager.generateReport(period: .weekly, readEvents: makeEvents(count: 7, days: 7), currentStreak: 8)
        let hasStreak = report.achievements.contains { $0.id == "streak_master" }
        XCTAssertTrue(hasStreak)
    }

    func testDeepDiverAchievement() {
        let events = makeEvents(count: 10, avgTime: 360)
        let report = manager.generateReport(period: .weekly, readEvents: events)
        let hasDiver = report.achievements.contains { $0.id == "deep_diver" }
        XCTAssertTrue(hasDiver)
    }

    func testNoDuplicateAchievements() {
        let events = makeEvents(count: 55)
        _ = manager.generateReport(period: .weekly, readEvents: events)
        let report2 = manager.generateReport(period: .weekly, readEvents: events)
        let bookworms = report2.achievements.filter { $0.id == "bookworm" }
        XCTAssertEqual(bookworms.count, 0) // Already earned
    }

    // MARK: - Recommendations

    func testRecommendationsForWeakAreas() {
        let report = manager.generateReport(period: .weekly, readEvents: [])
        XCTAssertFalse(report.recommendations.isEmpty)
        XCTAssertLessThanOrEqual(report.recommendations.count, 3)
    }

    func testStrongReaderGetsPraise() {
        let events = makeDiverseEvents(feedCount: 10, articlesPerFeed: 5)
        let report = manager.generateReport(period: .weekly, readEvents: events,
                                            engagementCount: 15, newFeedsCount: 3)
        // Should still have recommendations (even good ones)
        XCTAssertFalse(report.recommendations.isEmpty)
    }

    // MARK: - Report Access

    func testAllReportsNewestFirst() {
        _ = manager.generateReport(period: .weekly, readEvents: makeEvents(count: 5))
        _ = manager.generateReport(period: .monthly, readEvents: makeEvents(count: 10))
        _ = manager.generateReport(period: .weekly, readEvents: makeEvents(count: 15))

        let all = manager.allReports()
        XCTAssertEqual(all.count, 3)
        XCTAssertTrue(all[0].generatedDate >= all[1].generatedDate)
    }

    func testFilterByPeriod() {
        _ = manager.generateReport(period: .weekly, readEvents: makeEvents(count: 5))
        _ = manager.generateReport(period: .monthly, readEvents: makeEvents(count: 10))

        XCTAssertEqual(manager.reports(for: .weekly).count, 1)
        XCTAssertEqual(manager.reports(for: .monthly).count, 1)
    }

    func testLatestReport() {
        _ = manager.generateReport(period: .weekly, readEvents: makeEvents(count: 5))
        let second = manager.generateReport(period: .weekly, readEvents: makeEvents(count: 10))

        let latest = manager.latestReport(for: .weekly)
        XCTAssertEqual(latest?.id, second.id)
    }

    func testGPAHistory() {
        _ = manager.generateReport(period: .weekly, readEvents: makeEvents(count: 5))
        _ = manager.generateReport(period: .weekly, readEvents: makeEvents(count: 20))

        let history = manager.gpaHistory(period: .weekly)
        XCTAssertEqual(history.count, 2)
    }

    func testAllAchievementsDeduplicates() {
        _ = manager.generateReport(period: .weekly, readEvents: makeEvents(count: 55), currentStreak: 8)
        _ = manager.generateReport(period: .weekly, readEvents: makeEvents(count: 55), currentStreak: 8)

        let achievements = manager.allAchievements()
        let ids = achievements.map { $0.id }
        XCTAssertEqual(Set(ids).count, ids.count) // No duplicates
    }

    func testClearAll() {
        _ = manager.generateReport(period: .weekly, readEvents: makeEvents(count: 5))
        XCTAssertEqual(manager.reportCount, 1)
        manager.clearAll()
        XCTAssertEqual(manager.reportCount, 0)
    }

    // MARK: - Export

    func testExportJSON() {
        let report = manager.generateReport(period: .weekly, readEvents: makeEvents(count: 10))
        let json = manager.exportJSON(report: report)
        XCTAssertTrue(json.contains("compositeGPA"))
        XCTAssertTrue(json.contains("dimensionScores"))
    }

    func testExportMarkdown() {
        let report = manager.generateReport(period: .weekly, readEvents: makeEvents(count: 10), engagementCount: 2)
        let md = manager.exportMarkdown(report: report)
        XCTAssertTrue(md.contains("# 📋 Reading Report Card"))
        XCTAssertTrue(md.contains("Dimension Grades"))
        XCTAssertTrue(md.contains("Recommendations"))
    }

    func testExportHTML() {
        let report = manager.generateReport(period: .weekly, readEvents: makeEvents(count: 10))
        let html = manager.exportHTML(report: report)
        XCTAssertTrue(html.contains("<!DOCTYPE html>"))
        XCTAssertTrue(html.contains("Report Card"))
        XCTAssertTrue(html.contains("Dimensions"))
    }

    // MARK: - Data Integrity

    func testTopFeedsSorted() {
        var events = makeEvents(count: 20, feedName: "BigFeed")
        events += makeEvents(count: 5, feedName: "SmallFeed")
        let report = manager.generateReport(period: .weekly, readEvents: events)
        if let first = report.topFeeds.first {
            XCTAssertEqual(first.name, "BigFeed")
        }
    }

    func testNightAndMorningReads() {
        let calendar = Calendar.current
        let today = Date()
        var events: [ReadEventInput] = []

        // Night reads (11pm)
        for i in 0..<5 {
            var comps = calendar.dateComponents([.year, .month, .day], from: today)
            comps.hour = 23
            comps.day! -= i
            let date = calendar.date(from: comps)!
            events.append(ReadEventInput(articleTitle: "Night \(i)", feedName: "F", category: nil, date: date, readingTimeSeconds: 60))
        }

        // Morning reads (6am)
        for i in 0..<3 {
            var comps = calendar.dateComponents([.year, .month, .day], from: today)
            comps.hour = 6
            comps.day! -= i
            let date = calendar.date(from: comps)!
            events.append(ReadEventInput(articleTitle: "Morning \(i)", feedName: "F", category: nil, date: date, readingTimeSeconds: 60))
        }

        let report = manager.generateReport(period: .weekly, readEvents: events)
        XCTAssertGreaterThan(report.data.nightReads, 0)
        XCTAssertGreaterThan(report.data.morningReads, 0)
    }

    func testReportPeriodDays() {
        XCTAssertEqual(ReportPeriod.weekly.days, 7)
        XCTAssertEqual(ReportPeriod.monthly.days, 30)
    }

    func testLetterGradeFromScore() {
        XCTAssertEqual(LetterGrade.from(score: 96), .aPlus)
        XCTAssertEqual(LetterGrade.from(score: 91), .a)
        XCTAssertEqual(LetterGrade.from(score: 84), .bPlus)
        XCTAssertEqual(LetterGrade.from(score: 71), .c)
        XCTAssertEqual(LetterGrade.from(score: 30), .f)
    }

    func testLetterGradeComparable() {
        XCTAssertTrue(LetterGrade.f < LetterGrade.a)
        XCTAssertTrue(LetterGrade.c < LetterGrade.bPlus)
    }

    func testGradingDimensionCaseIterable() {
        XCTAssertEqual(GradingDimension.allCases.count, 6)
    }

    func testTrendDirectionProperties() {
        XCTAssertFalse(TrendDirection.improving.emoji.isEmpty)
        XCTAssertFalse(TrendDirection.declining.label.isEmpty)
    }

    func testNotificationPosted() {
        let expectation = XCTestExpectation(description: "Notification posted")
        let observer = NotificationCenter.default.addObserver(
            forName: .reportCardGenerated, object: nil, queue: nil
        ) { _ in expectation.fulfill() }

        _ = manager.generateReport(period: .weekly, readEvents: makeEvents(count: 5))
        wait(for: [expectation], timeout: 1.0)
        NotificationCenter.default.removeObserver(observer)
    }
}
