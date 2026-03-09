//
//  ReadingActivityHeatmapTests.swift
//  FeedReaderTests
//

import XCTest
@testable import FeedReader

final class ReadingActivityHeatmapTests: XCTestCase {

    private var heatmap: ReadingActivityHeatmap!
    private let calendar = Calendar.current
    private let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.locale = Locale(identifier: "en_US_POSIX")
        return f
    }()

    override func setUp() {
        super.setUp()
        heatmap = ReadingActivityHeatmap(state: .empty)
    }

    // MARK: - Helper

    private func date(_ str: String) -> Date {
        dateFormatter.date(from: str)!
    }

    private func recordDays(_ entries: [(id: String, date: String)]) {
        for entry in entries {
            heatmap.recordReading(articleID: entry.id, date: date(entry.date))
        }
    }

    // MARK: - Recording

    func testRecordSingleArticle() {
        let cell = heatmap.recordReading(articleID: "a1", date: date("2026-01-15"))
        XCTAssertEqual(cell.count, 1)
        XCTAssertEqual(cell.intensity, .low)
        XCTAssertEqual(cell.articles, ["a1"])
    }

    func testRecordMultipleArticlesSameDay() {
        heatmap.recordReading(articleID: "a1", date: date("2026-01-15"))
        heatmap.recordReading(articleID: "a2", date: date("2026-01-15"))
        let cell = heatmap.recordReading(articleID: "a3", date: date("2026-01-15"))
        XCTAssertEqual(cell.count, 3)
        XCTAssertEqual(cell.intensity, .medium)
        XCTAssertEqual(cell.articles, ["a1", "a2", "a3"])
    }

    func testDuplicateArticleIDIgnored() {
        heatmap.recordReading(articleID: "a1", date: date("2026-01-15"))
        let cell = heatmap.recordReading(articleID: "a1", date: date("2026-01-15"))
        XCTAssertEqual(cell.count, 1, "Duplicate article ID should not increment count")
        XCTAssertEqual(cell.articles.count, 1)
    }

    func testRecordBatch() {
        let entries: [(articleID: String, date: Date)] = [
            ("b1", date("2026-01-10")),
            ("b2", date("2026-01-10")),
            ("b3", date("2026-01-11")),
        ]
        heatmap.recordBatch(entries)

        let grid = heatmap.generateGrid(range: .threeMonths, from: date("2026-01-15"))
        let jan10 = grid.flatMap(\.cells).first { dateFormatter.string(from: $0.date) == "2026-01-10" }
        let jan11 = grid.flatMap(\.cells).first { dateFormatter.string(from: $0.date) == "2026-01-11" }
        XCTAssertEqual(jan10?.count, 2)
        XCTAssertEqual(jan11?.count, 1)
    }

    func testBatchDuplicatesIgnored() {
        let entries: [(articleID: String, date: Date)] = [
            ("b1", date("2026-02-01")),
            ("b1", date("2026-02-01")),  // duplicate
        ]
        heatmap.recordBatch(entries)
        let grid = heatmap.generateGrid(range: .threeMonths, from: date("2026-02-05"))
        let feb1 = grid.flatMap(\.cells).first { dateFormatter.string(from: $0.date) == "2026-02-01" }
        XCTAssertEqual(feb1?.count, 1)
    }

    // MARK: - Intensity Thresholds

    func testDefaultThresholds() {
        let t = HeatmapThresholds.default
        XCTAssertEqual(t.intensity(for: 0), .none)
        XCTAssertEqual(t.intensity(for: 1), .low)
        XCTAssertEqual(t.intensity(for: 2), .low)
        XCTAssertEqual(t.intensity(for: 3), .medium)
        XCTAssertEqual(t.intensity(for: 5), .medium)
        XCTAssertEqual(t.intensity(for: 6), .high)
        XCTAssertEqual(t.intensity(for: 9), .high)
        XCTAssertEqual(t.intensity(for: 10), .intense)
        XCTAssertEqual(t.intensity(for: 100), .intense)
    }

    func testCustomThresholds() {
        let custom = HeatmapThresholds(low: 2, medium: 5, high: 10, intense: 20)
        XCTAssertEqual(custom.intensity(for: 0), .none)
        XCTAssertEqual(custom.intensity(for: 1), .none)
        XCTAssertEqual(custom.intensity(for: 2), .low)
        XCTAssertEqual(custom.intensity(for: 5), .medium)
        XCTAssertEqual(custom.intensity(for: 10), .high)
        XCTAssertEqual(custom.intensity(for: 20), .intense)
    }

    func testSetThresholds() {
        let custom = HeatmapThresholds(low: 2, medium: 4, high: 8, intense: 15)
        heatmap.setThresholds(custom)
        XCTAssertEqual(heatmap.state.thresholds, custom)

        // 1 article should now be .none with threshold=2
        let cell = heatmap.recordReading(articleID: "t1", date: date("2026-03-01"))
        XCTAssertEqual(cell.intensity, .none)
    }

    // MARK: - Grid Generation

    func testGridCoversTimeRange() {
        let endDate = date("2026-03-01")
        let grid = heatmap.generateGrid(range: .threeMonths, from: endDate)
        let totalCells = grid.flatMap(\.cells).count
        // 91 days + alignment padding — should be at least 91
        XCTAssertGreaterThanOrEqual(totalCells, 91)
    }

    func testGridOneYearCoversFullYear() {
        let grid = heatmap.generateGrid(range: .oneYear, from: date("2026-12-31"))
        let totalCells = grid.flatMap(\.cells).count
        XCTAssertGreaterThanOrEqual(totalCells, 365)
    }

    func testGridCellsReflectRecordings() {
        recordDays([
            (id: "x1", date: "2026-02-10"),
            (id: "x2", date: "2026-02-10"),
            (id: "x3", date: "2026-02-15"),
        ])
        let grid = heatmap.generateGrid(range: .threeMonths, from: date("2026-03-01"))
        let cells = grid.flatMap(\.cells)

        let feb10 = cells.first { dateFormatter.string(from: $0.date) == "2026-02-10" }
        let feb15 = cells.first { dateFormatter.string(from: $0.date) == "2026-02-15" }
        let feb20 = cells.first { dateFormatter.string(from: $0.date) == "2026-02-20" }

        XCTAssertEqual(feb10?.count, 2)
        XCTAssertEqual(feb15?.count, 1)
        XCTAssertEqual(feb20?.count, 0)
    }

    func testGridWeeksHaveUpTo7Cells() {
        let grid = heatmap.generateGrid(range: .sixMonths, from: date("2026-06-15"))
        for week in grid {
            XCTAssertLessThanOrEqual(week.cells.count, 7)
            XCTAssertGreaterThan(week.cells.count, 0)
        }
    }

    func testWeekTotalCount() {
        recordDays([
            (id: "w1", date: "2026-01-05"),  // Sunday
            (id: "w2", date: "2026-01-06"),  // Monday
            (id: "w3", date: "2026-01-06"),
        ])
        let grid = heatmap.generateGrid(range: .threeMonths, from: date("2026-01-10"))
        let targetWeek = grid.first { w in
            w.cells.contains { dateFormatter.string(from: $0.date) == "2026-01-05" }
        }
        XCTAssertNotNil(targetWeek)
        XCTAssertEqual(targetWeek?.totalCount, 3)
    }

    // MARK: - Streaks

    func testEmptyStreakWhenNoData() {
        let streak = heatmap.currentStreak(from: date("2026-03-01"))
        XCTAssertEqual(streak.length, 0)
    }

    func testCurrentStreakSingleDay() {
        heatmap.recordReading(articleID: "s1", date: date("2026-03-01"))
        let streak = heatmap.currentStreak(from: date("2026-03-01"))
        XCTAssertEqual(streak.length, 1)
    }

    func testCurrentStreakConsecutiveDays() {
        recordDays([
            (id: "s1", date: "2026-02-27"),
            (id: "s2", date: "2026-02-28"),
            (id: "s3", date: "2026-03-01"),
        ])
        let streak = heatmap.currentStreak(from: date("2026-03-01"))
        XCTAssertEqual(streak.length, 3)
    }

    func testCurrentStreakBrokenByGap() {
        recordDays([
            (id: "s1", date: "2026-02-25"),
            // gap on 2026-02-26
            (id: "s2", date: "2026-02-27"),
            (id: "s3", date: "2026-02-28"),
            (id: "s4", date: "2026-03-01"),
        ])
        let streak = heatmap.currentStreak(from: date("2026-03-01"))
        XCTAssertEqual(streak.length, 3, "Streak should not bridge the gap")
    }

    func testCurrentStreakFromYesterday() {
        // No reading today, but yesterday has one — streak is still 1
        recordDays([
            (id: "s1", date: "2026-02-28"),
        ])
        let streak = heatmap.currentStreak(from: date("2026-03-01"))
        XCTAssertEqual(streak.length, 1)
    }

    func testLongestStreak() {
        // First streak: 3 days
        recordDays([
            (id: "a1", date: "2026-01-10"),
            (id: "a2", date: "2026-01-11"),
            (id: "a3", date: "2026-01-12"),
        ])
        // Second streak: 5 days (longer)
        recordDays([
            (id: "b1", date: "2026-02-01"),
            (id: "b2", date: "2026-02-02"),
            (id: "b3", date: "2026-02-03"),
            (id: "b4", date: "2026-02-04"),
            (id: "b5", date: "2026-02-05"),
        ])
        let longest = heatmap.longestStreak()
        XCTAssertEqual(longest.length, 5)
    }

    func testLongestStreakEmpty() {
        let longest = heatmap.longestStreak()
        XCTAssertEqual(longest.length, 0)
    }

    // MARK: - Monthly Summaries

    func testMonthlySummariesGroupByMonth() {
        recordDays([
            (id: "m1", date: "2026-01-15"),
            (id: "m2", date: "2026-01-20"),
            (id: "m3", date: "2026-02-10"),
        ])
        let summaries = heatmap.monthlySummaries(range: .threeMonths, from: date("2026-03-01"))
        XCTAssertEqual(summaries.count, 2)  // Jan and Feb

        let jan = summaries.first { $0.month == 1 }
        XCTAssertNotNil(jan)
        XCTAssertEqual(jan?.totalArticles, 2)
        XCTAssertEqual(jan?.activeDays, 2)

        let feb = summaries.first { $0.month == 2 }
        XCTAssertNotNil(feb)
        XCTAssertEqual(feb?.totalArticles, 1)
    }

    func testMonthlySummaryPeakDay() {
        recordDays([
            (id: "p1", date: "2026-01-15"),
            (id: "p2", date: "2026-01-15"),
            (id: "p3", date: "2026-01-15"),
            (id: "p4", date: "2026-01-20"),
        ])
        let summaries = heatmap.monthlySummaries(range: .threeMonths, from: date("2026-02-01"))
        let jan = summaries.first { $0.month == 1 }
        XCTAssertEqual(jan?.peakCount, 3)
    }

    func testMonthlySummaryAveragePerDay() {
        recordDays([
            (id: "a1", date: "2026-01-10"),
            (id: "a2", date: "2026-01-10"),
            (id: "a3", date: "2026-01-20"),
        ])
        let summaries = heatmap.monthlySummaries(range: .threeMonths, from: date("2026-02-01"))
        let jan = summaries.first { $0.month == 1 }
        // 3 articles / 2 active days = 1.5
        XCTAssertEqual(jan?.averagePerDay, 1.5, accuracy: 0.01)
    }

    func testMonthlySummariesSortedChronologically() {
        recordDays([
            (id: "c1", date: "2026-03-01"),
            (id: "c2", date: "2026-01-01"),
            (id: "c3", date: "2026-02-01"),
        ])
        let summaries = heatmap.monthlySummaries(range: .sixMonths, from: date("2026-03-15"))
        XCTAssertEqual(summaries.map(\.month), [1, 2, 3])
    }

    // MARK: - Weekday Distribution

    func testWeekdayDistributionCoversAllDays() {
        let dist = heatmap.weekdayDistribution()
        XCTAssertEqual(dist.count, 7)
        XCTAssertEqual(dist.map(\.weekday), [1, 2, 3, 4, 5, 6, 7])
    }

    func testWeekdayDistributionCounts() {
        // 2026-01-12 = Monday (weekday 2)
        recordDays([
            (id: "d1", date: "2026-01-12"),
            (id: "d2", date: "2026-01-12"),
            (id: "d3", date: "2026-01-19"),  // Also Monday
        ])
        let dist = heatmap.weekdayDistribution()
        let monday = dist.first { $0.weekday == 2 }
        XCTAssertEqual(monday?.totalArticles, 3)
        XCTAssertEqual(monday?.activeDays, 2)
        XCTAssertEqual(monday?.averagePerActiveDay, 1.5, accuracy: 0.01)
    }

    func testWeekdayDistributionEmptyData() {
        let dist = heatmap.weekdayDistribution()
        for day in dist {
            XCTAssertEqual(day.totalArticles, 0)
            XCTAssertEqual(day.activeDays, 0)
            XCTAssertEqual(day.averagePerActiveDay, 0)
        }
    }

    func testWeekdayLabels() {
        let dist = heatmap.weekdayDistribution()
        XCTAssertEqual(dist[0].weekdayLabel, "Sun")
        XCTAssertEqual(dist[1].weekdayLabel, "Mon")
        XCTAssertEqual(dist[6].weekdayLabel, "Sat")
    }

    // MARK: - Year-over-Year

    func testYearOverYearWithNoHistory() {
        let yoy = heatmap.yearOverYear(days: 30, from: date("2026-03-01"))
        XCTAssertEqual(yoy.currentTotal, 0)
        XCTAssertEqual(yoy.previousTotal, 0)
        XCTAssertEqual(yoy.delta, 0)
        XCTAssertNil(yoy.percentChange)
    }

    func testYearOverYearGrowth() {
        // Last year: 2 articles in Feb
        recordDays([
            (id: "y1", date: "2025-02-10"),
            (id: "y2", date: "2025-02-20"),
        ])
        // This year: 5 articles in Feb
        recordDays([
            (id: "y3", date: "2026-02-05"),
            (id: "y4", date: "2026-02-10"),
            (id: "y5", date: "2026-02-15"),
            (id: "y6", date: "2026-02-20"),
            (id: "y7", date: "2026-02-25"),
        ])
        let yoy = heatmap.yearOverYear(days: 30, from: date("2026-02-28"))
        XCTAssertEqual(yoy.currentTotal, 5)
        XCTAssertEqual(yoy.previousTotal, 2)
        XCTAssertEqual(yoy.delta, 3)
        XCTAssertEqual(yoy.percentChange!, 150.0, accuracy: 0.1)
    }

    func testYearOverYearDecline() {
        recordDays([
            (id: "y1", date: "2025-02-10"),
            (id: "y2", date: "2025-02-15"),
            (id: "y3", date: "2025-02-20"),
        ])
        recordDays([
            (id: "y4", date: "2026-02-15"),
        ])
        let yoy = heatmap.yearOverYear(days: 30, from: date("2026-02-28"))
        XCTAssertEqual(yoy.delta, -2)
        XCTAssertLessThan(yoy.percentChange!, 0)
    }

    // MARK: - Statistics

    func testTotalArticlesInRange() {
        recordDays([
            (id: "r1", date: "2026-01-10"),
            (id: "r2", date: "2026-01-15"),
            (id: "r3", date: "2026-02-01"),
        ])
        let total = heatmap.totalArticles(from: date("2026-01-01"), to: date("2026-01-31"))
        XCTAssertEqual(total, 2)
    }

    func testActiveDaysInRange() {
        recordDays([
            (id: "a1", date: "2026-01-10"),
            (id: "a2", date: "2026-01-10"),
            (id: "a3", date: "2026-01-15"),
        ])
        let active = heatmap.activeDays(from: date("2026-01-01"), to: date("2026-01-31"))
        XCTAssertEqual(active, 2)
    }

    func testOverallAverage() {
        recordDays([
            (id: "o1", date: "2026-01-10"),
            (id: "o2", date: "2026-01-10"),
            (id: "o3", date: "2026-01-10"),
            (id: "o4", date: "2026-01-15"),
        ])
        // 4 articles / 2 active days = 2.0
        XCTAssertEqual(heatmap.overallAverage(), 2.0, accuracy: 0.01)
    }

    func testOverallAverageEmpty() {
        XCTAssertEqual(heatmap.overallAverage(), 0)
    }

    func testPeakDay() {
        recordDays([
            (id: "p1", date: "2026-01-10"),
            (id: "p2", date: "2026-01-15"),
            (id: "p3", date: "2026-01-15"),
            (id: "p4", date: "2026-01-15"),
        ])
        let peak = heatmap.peakDay()
        XCTAssertNotNil(peak)
        XCTAssertEqual(peak?.count, 3)
        XCTAssertEqual(dateFormatter.string(from: peak!.date), "2026-01-15")
    }

    func testPeakDayEmpty() {
        XCTAssertNil(heatmap.peakDay())
    }

    // MARK: - Export

    func testExportDataContainsAllFields() {
        recordDays([
            (id: "e1", date: "2026-02-01"),
            (id: "e2", date: "2026-02-02"),
        ])
        let export = heatmap.exportData(range: .threeMonths)
        XCTAssertNotNil(export["range"])
        XCTAssertNotNil(export["totalArticles"])
        XCTAssertNotNil(export["totalDays"])
        XCTAssertNotNil(export["activeDays"])
        XCTAssertNotNil(export["currentStreak"])
        XCTAssertNotNil(export["longestStreak"])
        XCTAssertNotNil(export["averagePerActiveDay"])
        XCTAssertNotNil(export["weekCount"])
        XCTAssertNotNil(export["monthlySummaries"])
    }

    func testExportRangeLabel() {
        let export = heatmap.exportData(range: .sixMonths)
        XCTAssertEqual(export["range"] as? String, "6 months")
    }

    // MARK: - Reset

    func testResetClearsAllData() {
        recordDays([
            (id: "r1", date: "2026-02-01"),
        ])
        heatmap.reset()
        XCTAssertTrue(heatmap.state.dailyCounts.isEmpty)
        XCTAssertEqual(heatmap.overallAverage(), 0)
    }

    // MARK: - Model Properties

    func testHeatmapIntensityLabels() {
        XCTAssertEqual(HeatmapIntensity.none.label, "No reading")
        XCTAssertEqual(HeatmapIntensity.low.label, "Light reading")
        XCTAssertEqual(HeatmapIntensity.intense.label, "Intense reading")
    }

    func testHeatmapIntensityComparable() {
        XCTAssertLessThan(HeatmapIntensity.none, HeatmapIntensity.low)
        XCTAssertLessThan(HeatmapIntensity.low, HeatmapIntensity.medium)
        XCTAssertLessThan(HeatmapIntensity.medium, HeatmapIntensity.high)
        XCTAssertLessThan(HeatmapIntensity.high, HeatmapIntensity.intense)
    }

    func testTimeRangeProperties() {
        XCTAssertEqual(HeatmapTimeRange.threeMonths.days, 91)
        XCTAssertEqual(HeatmapTimeRange.sixMonths.days, 182)
        XCTAssertEqual(HeatmapTimeRange.oneYear.days, 365)
        XCTAssertEqual(HeatmapTimeRange.oneYear.label, "1 year")
    }

    func testCellWeekday() {
        let cell = HeatmapCell(
            date: date("2026-01-12"),  // Monday
            count: 1,
            intensity: .low,
            articles: ["a1"]
        )
        XCTAssertEqual(cell.weekday, 2)  // Monday = 2
    }

    func testMonthSummaryLabel() {
        let summary = HeatmapMonthSummary(
            year: 2026, month: 3,
            totalArticles: 10, activeDays: 5,
            averagePerDay: 2.0,
            peakDay: nil, peakCount: 4
        )
        XCTAssertEqual(summary.monthLabel, "Mar 2026")
    }

    func testNotificationPosted() {
        let expectation = self.expectation(forNotification: .readingHeatmapDidUpdate, object: heatmap)
        heatmap.recordReading(articleID: "n1", date: date("2026-01-01"))
        wait(for: [expectation], timeout: 1.0)
    }

    func testResetNotificationPosted() {
        let expectation = self.expectation(forNotification: .readingHeatmapDidUpdate, object: heatmap)
        heatmap.reset()
        wait(for: [expectation], timeout: 1.0)
    }
}
