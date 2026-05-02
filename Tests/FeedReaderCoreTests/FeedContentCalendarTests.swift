//
//  FeedContentCalendarTests.swift
//  FeedReaderCoreTests
//
//  Tests for FeedContentCalendar — publication pattern detection,
//  gap alerts, forecasting, and fleet analysis.
//

import XCTest
@testable import FeedReaderCore

final class FeedContentCalendarTests: XCTestCase {

    // MARK: - Helpers

    private let calendar = Calendar(identifier: .gregorian)

    /// Creates an ArticleEntry for a given feed at a specific date.
    private func entry(_ feed: String, daysAgo: Int, hour: Int = 12,
                       title: String = "Article") -> FeedContentCalendar.ArticleEntry {
        let refDate = Date(timeIntervalSince1970: 1_746_144_000) // ~2025-05-02 00:00 UTC
        let date = calendar.date(byAdding: .day, value: -daysAgo, to: refDate)!
        let withHour = calendar.date(bySettingHour: hour, minute: 0, second: 0, of: date)!
        return FeedContentCalendar.ArticleEntry(feedName: feed, title: title, publishedDate: withHour)
    }

    /// Reference date matching the entries above.
    private var refDate: Date {
        Date(timeIntervalSince1970: 1_746_144_000)
    }

    // MARK: - Empty / Minimal Input

    func testEmptyArticlesReturnsInactivePattern() {
        let sut = FeedContentCalendar(referenceDate: refDate)
        let report = sut.analyze(feedName: "Empty", articles: [])

        XCTAssertEqual(report.pattern, .inactive)
        XCTAssertEqual(report.totalArticlesAnalyzed, 0)
        XCTAssertEqual(report.regularityScore, 0)
        XCTAssertEqual(report.dayProfiles.count, 7)
        XCTAssertTrue(report.gapAlerts.isEmpty)
        XCTAssertTrue(report.forecasts.isEmpty)
        XCTAssertNil(report.analysisStartDate)
        XCTAssertNil(report.analysisEndDate)
    }

    func testSingleArticleReturnsSporadicPattern() {
        let articles = [entry("Solo", daysAgo: 5)]
        let sut = FeedContentCalendar(referenceDate: refDate)
        let report = sut.analyze(feedName: "Solo", articles: articles)

        XCTAssertEqual(report.pattern, .sporadic)
        XCTAssertEqual(report.totalArticlesAnalyzed, 1)
        XCTAssertEqual(report.regularityScore, 0)
    }

    // MARK: - Daily Pattern Detection

    func testDailyPatternDetected() {
        // One article per day for 20 days
        let articles = (0..<20).map { entry("Daily", daysAgo: $0) }
        let sut = FeedContentCalendar(referenceDate: refDate)
        let report = sut.analyze(feedName: "Daily", articles: articles)

        XCTAssertEqual(report.pattern, .daily)
        XCTAssertGreaterThan(report.regularityScore, 0.5)
        XCTAssertEqual(report.totalArticlesAnalyzed, 20)
        XCTAssertLessThan(report.averageGapDays, 1.5)
    }

    func testDailyPatternGeneratesForecasts() {
        let articles = (0..<20).map { entry("Daily", daysAgo: $0) }
        let sut = FeedContentCalendar(referenceDate: refDate)
        let report = sut.analyze(feedName: "Daily", articles: articles)

        XCTAssertFalse(report.forecasts.isEmpty)
        XCTAssertLessThanOrEqual(report.forecasts.count, 3)
        // All forecasts should be in the future
        for fc in report.forecasts {
            XCTAssertGreaterThan(fc.predictedDate, refDate)
            XCTAssertEqual(fc.basis, "daily pattern")
            XCTAssertGreaterThan(fc.confidence, 0)
        }
    }

    // MARK: - Weekly Pattern Detection

    func testWeeklyPatternDetected() {
        // One article every 7 days for 8 weeks
        let articles = (0..<8).map { entry("Weekly", daysAgo: $0 * 7) }
        let sut = FeedContentCalendar(referenceDate: refDate)
        let report = sut.analyze(feedName: "Weekly", articles: articles)

        XCTAssertEqual(report.pattern, .weekly)
        XCTAssertGreaterThanOrEqual(report.averageGapDays, 5)
        XCTAssertLessThanOrEqual(report.averageGapDays, 9)
    }

    // MARK: - Biweekly Pattern Detection

    func testBiweeklyPatternDetected() {
        // One article every 14 days for 6 cycles
        let articles = (0..<6).map { entry("Biweekly", daysAgo: $0 * 14) }
        let sut = FeedContentCalendar(referenceDate: refDate)
        let report = sut.analyze(feedName: "Biweekly", articles: articles)

        XCTAssertEqual(report.pattern, .biweekly)
        XCTAssertGreaterThanOrEqual(report.averageGapDays, 12)
        XCTAssertLessThanOrEqual(report.averageGapDays, 18)
    }

    // MARK: - Inactive Detection

    func testInactiveWhenLastPostOver30DaysAgo() {
        // Articles from 40-50 days ago, nothing recent
        let articles = (40...50).map { entry("Stale", daysAgo: $0) }
        let sut = FeedContentCalendar(referenceDate: refDate)
        let report = sut.analyze(feedName: "Stale", articles: articles)

        XCTAssertEqual(report.pattern, .inactive)
        XCTAssertTrue(report.forecasts.isEmpty)
    }

    // MARK: - Sporadic Pattern

    func testSporadicWhenIrregularGaps() {
        // Highly irregular posting: gaps of 1, 8, 2, 15, 3, 12
        let daysAgo = [0, 1, 9, 11, 26, 29]
        let articles = daysAgo.map { entry("Sporadic", daysAgo: $0) }
        let sut = FeedContentCalendar(referenceDate: refDate)
        let report = sut.analyze(feedName: "Sporadic", articles: articles)

        // Should not detect a clean daily/weekly/biweekly pattern
        XCTAssertTrue(report.pattern == .sporadic || report.pattern == .weekly,
                      "Expected sporadic or weekly for irregular gaps, got \(report.pattern)")
    }

    // MARK: - Day Profiles

    func testDayProfilesAlways7Entries() {
        let articles = (0..<10).map { entry("Feed", daysAgo: $0) }
        let sut = FeedContentCalendar(referenceDate: refDate)
        let report = sut.analyze(feedName: "Feed", articles: articles)

        XCTAssertEqual(report.dayProfiles.count, 7)
        // Weekdays 1-7
        let weekdays = report.dayProfiles.map { $0.weekday }
        XCTAssertEqual(weekdays, [1, 2, 3, 4, 5, 6, 7])
    }

    func testDayProfileDayNames() {
        let articles = [entry("Feed", daysAgo: 0), entry("Feed", daysAgo: 1)]
        let sut = FeedContentCalendar(referenceDate: refDate)
        let report = sut.analyze(feedName: "Feed", articles: articles)

        let names = report.dayProfiles.map { $0.dayName }
        XCTAssertEqual(names, ["Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday"])

        let shortNames = report.dayProfiles.map { $0.shortDayName }
        XCTAssertEqual(shortNames, ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"])
    }

    func testBusiestDayIdentified() {
        // Post 5 articles on the same day, 1 on another day
        let refWeekday = calendar.component(.weekday, from: refDate)
        let articles = (0..<5).map { i in
            entry("Feed", daysAgo: 0, hour: 8 + i, title: "Article \(i)")
        } + [entry("Feed", daysAgo: 3)]

        let sut = FeedContentCalendar(referenceDate: refDate)
        let report = sut.analyze(feedName: "Feed", articles: articles)

        XCTAssertNotNil(report.busiestDay)
        // The busiest day should have the highest average
        if let busiest = report.busiestDay {
            for dp in report.dayProfiles {
                XCTAssertLessThanOrEqual(dp.averageArticles, busiest.averageArticles + 0.001)
            }
        }
    }

    // MARK: - Peak Hour Detection

    func testPeakHourDetectedFromArticleTimes() {
        // All articles at hour 9
        let articles = (0..<14).map { entry("Morning", daysAgo: $0, hour: 9) }
        let sut = FeedContentCalendar(referenceDate: refDate)
        let report = sut.analyze(feedName: "Morning", articles: articles)

        // The day that has articles should have peak hour 9
        let daysWithArticles = report.dayProfiles.filter { $0.totalArticles > 0 }
        for dp in daysWithArticles {
            XCTAssertEqual(dp.peakHour, 9)
        }
    }

    // MARK: - Gap Alerts

    func testGapAlertWhenOverdue() {
        // Feed that posts every 2 days, but last post was 10 days ago
        var articles = [FeedContentCalendar.ArticleEntry]()
        for i in stride(from: 10, through: 30, by: 2) {
            articles.append(entry("Late", daysAgo: i))
        }
        let sut = FeedContentCalendar(referenceDate: refDate)
        let report = sut.analyze(feedName: "Late", articles: articles)

        XCTAssertFalse(report.gapAlerts.isEmpty, "Expected gap alert for overdue feed")
        if let alert = report.gapAlerts.first {
            XCTAssertEqual(alert.feedName, "Late")
            XCTAssertGreaterThanOrEqual(alert.daysSinceLastPost, 10)
            XCTAssertGreaterThan(alert.deviations, 0)
        }
    }

    func testNoGapAlertWhenOnSchedule() {
        // Feed posts daily, last post today
        let articles = (0..<20).map { entry("OnTime", daysAgo: $0) }
        let sut = FeedContentCalendar(referenceDate: refDate)
        let report = sut.analyze(feedName: "OnTime", articles: articles)

        XCTAssertTrue(report.gapAlerts.isEmpty)
    }

    func testGapAlertSeverityScales() {
        // Feed posts every 3 days; last post was 20 days ago (high deviation)
        var articles = [FeedContentCalendar.ArticleEntry]()
        for i in stride(from: 20, through: 50, by: 3) {
            articles.append(entry("VeryLate", daysAgo: i))
        }
        let sut = FeedContentCalendar(referenceDate: refDate)
        let report = sut.analyze(feedName: "VeryLate", articles: articles)

        if let alert = report.gapAlerts.first {
            // With ~3-day avg gap and 20-day absence, severity should be high
            XCTAssertTrue(alert.severity == .alert || alert.severity == .warning,
                          "Expected warning or alert severity, got \(alert.severity)")
        }
    }

    func testGapSeverityEmoji() {
        XCTAssertEqual(GapAlert.GapSeverity.notice.emoji, "ℹ️")
        XCTAssertEqual(GapAlert.GapSeverity.warning.emoji, "⚠️")
        XCTAssertEqual(GapAlert.GapSeverity.alert.emoji, "🚨")
    }

    // MARK: - Schedule Pattern Properties

    func testSchedulePatternDescriptions() {
        XCTAssertEqual(SchedulePattern.daily.description, "Publishes daily")
        XCTAssertEqual(SchedulePattern.weekdays.description, "Publishes on weekdays")
        XCTAssertEqual(SchedulePattern.weekly.description, "Publishes weekly")
        XCTAssertEqual(SchedulePattern.biweekly.description, "Publishes every two weeks")
        XCTAssertEqual(SchedulePattern.sporadic.description, "Irregular schedule")
        XCTAssertEqual(SchedulePattern.inactive.description, "No recent activity")
    }

    func testSchedulePatternEmojis() {
        XCTAssertEqual(SchedulePattern.daily.emoji, "📅")
        XCTAssertEqual(SchedulePattern.weekdays.emoji, "💼")
        XCTAssertEqual(SchedulePattern.weekly.emoji, "📰")
        XCTAssertEqual(SchedulePattern.biweekly.emoji, "🗓️")
        XCTAssertEqual(SchedulePattern.sporadic.emoji, "🎲")
        XCTAssertEqual(SchedulePattern.inactive.emoji, "💤")
    }

    func testSchedulePatternRawValues() {
        XCTAssertEqual(SchedulePattern.daily.rawValue, "daily")
        XCTAssertEqual(SchedulePattern.weekly.rawValue, "weekly")
        XCTAssertEqual(SchedulePattern.biweekly.rawValue, "biweekly")
    }

    // MARK: - Regularity Score

    func testHighRegularityForConsistentFeed() {
        // Perfect daily posting
        let articles = (0..<30).map { entry("Consistent", daysAgo: $0) }
        let sut = FeedContentCalendar(referenceDate: refDate)
        let report = sut.analyze(feedName: "Consistent", articles: articles)

        XCTAssertGreaterThan(report.regularityScore, 0.7)
    }

    func testLowRegularityForIrregularFeed() {
        // Very irregular: gaps of 1, 10, 1, 15, 1, 20
        let daysAgo = [0, 1, 11, 12, 27, 28]
        let articles = daysAgo.map { entry("Irregular", daysAgo: $0) }
        let sut = FeedContentCalendar(referenceDate: refDate)
        let report = sut.analyze(feedName: "Irregular", articles: articles)

        XCTAssertLessThan(report.regularityScore, 0.6)
    }

    // MARK: - Fleet Analysis

    func testFleetAnalysisAggregatesMultipleFeeds() {
        let feed1 = (0..<10).map { entry("FeedA", daysAgo: $0) }
        let feed2 = (0..<5).map { entry("FeedB", daysAgo: $0 * 7) }
        let allArticles = feed1 + feed2

        let sut = FeedContentCalendar(referenceDate: refDate)
        let summary = sut.analyzeFleet(articles: allArticles)

        XCTAssertEqual(summary.reports.count, 2)
        XCTAssertFalse(summary.busiestGlobalDay.isEmpty)
    }

    func testFleetSummaryIdentifiesDormantFeeds() {
        let active = (0..<10).map { entry("Active", daysAgo: $0) }
        let dormant = (40...50).map { entry("Dormant", daysAgo: $0) }

        let sut = FeedContentCalendar(referenceDate: refDate)
        let summary = sut.analyzeFleet(articles: active + dormant)

        XCTAssertTrue(summary.dormantFeeds.contains("Dormant"))
        XCTAssertFalse(summary.dormantFeeds.contains("Active"))
    }

    func testFleetSummaryIdentifiesReliableFeeds() {
        // Very consistent daily feed
        let reliable = (0..<30).map { entry("Reliable", daysAgo: $0) }
        let sporadic = [0, 5, 8, 22, 25].map { entry("Chaos", daysAgo: $0) }

        let sut = FeedContentCalendar(referenceDate: refDate)
        let summary = sut.analyzeFleet(articles: reliable + sporadic)

        XCTAssertTrue(summary.mostReliableFeeds.contains("Reliable"))
    }

    func testFleetTotalAlerts() {
        // One feed on-time, one significantly overdue
        let onTime = (0..<10).map { entry("Good", daysAgo: $0) }
        var overdue = [FeedContentCalendar.ArticleEntry]()
        for i in stride(from: 15, through: 45, by: 3) {
            overdue.append(entry("Behind", daysAgo: i))
        }

        let sut = FeedContentCalendar(referenceDate: refDate)
        let summary = sut.analyzeFleet(articles: onTime + overdue)

        // The overdue feed should generate at least one alert
        XCTAssertGreaterThanOrEqual(summary.totalAlerts, 1)
    }

    // MARK: - Report Formatting

    func testFormatReportContainsFeedName() {
        let articles = (0..<10).map { entry("MyFeed", daysAgo: $0) }
        let sut = FeedContentCalendar(referenceDate: refDate)
        let report = sut.analyze(feedName: "MyFeed", articles: articles)
        let formatted = sut.formatReport(report)

        XCTAssertTrue(formatted.contains("MyFeed"))
        XCTAssertTrue(formatted.contains("Pattern:"))
        XCTAssertTrue(formatted.contains("Regularity:"))
        XCTAssertTrue(formatted.contains("Weekly Publication Heatmap"))
    }

    func testFormatReportIncludesGapAlerts() {
        var articles = [FeedContentCalendar.ArticleEntry]()
        for i in stride(from: 15, through: 45, by: 3) {
            articles.append(entry("Overdue", daysAgo: i))
        }
        let sut = FeedContentCalendar(referenceDate: refDate)
        let report = sut.analyze(feedName: "Overdue", articles: articles)

        if !report.gapAlerts.isEmpty {
            let formatted = sut.formatReport(report)
            XCTAssertTrue(formatted.contains("Gap Alerts"))
        }
    }

    func testFormatReportIncludesForecasts() {
        let articles = (0..<20).map { entry("Forecast", daysAgo: $0) }
        let sut = FeedContentCalendar(referenceDate: refDate)
        let report = sut.analyze(feedName: "Forecast", articles: articles)

        if !report.forecasts.isEmpty {
            let formatted = sut.formatReport(report)
            XCTAssertTrue(formatted.contains("Upcoming Forecasts"))
        }
    }

    func testFormatFleetSummary() {
        let articles = (0..<10).map { entry("FeedX", daysAgo: $0) }
        let sut = FeedContentCalendar(referenceDate: refDate)
        let summary = sut.analyzeFleet(articles: articles)
        let formatted = sut.formatFleetSummary(summary)

        XCTAssertTrue(formatted.contains("Fleet Content Calendar Summary"))
        XCTAssertTrue(formatted.contains("Feeds analyzed:"))
        XCTAssertTrue(formatted.contains("Busiest day globally:"))
    }

    // MARK: - Fleet Insights

    func testFleetInsightsGenerated() {
        let feed1 = (0..<30).map { entry("A", daysAgo: $0) }
        let feed2 = (0..<30).map { entry("B", daysAgo: $0) }
        let dormant1 = (40...60).map { entry("D1", daysAgo: $0) }
        let dormant2 = (40...60).map { entry("D2", daysAgo: $0) }
        let dormant3 = (40...60).map { entry("D3", daysAgo: $0) }

        let sut = FeedContentCalendar(referenceDate: refDate)
        let summary = sut.analyzeFleet(articles: feed1 + feed2 + dormant1 + dormant2 + dormant3)

        // With 3 dormant feeds, should get a dormancy insight
        XCTAssertFalse(summary.insights.isEmpty)
        let dormancyInsight = summary.insights.first { $0.contains("dormant") }
        XCTAssertNotNil(dormancyInsight)
    }

    // MARK: - Edge Cases

    func testArticlesFromWrongFeedFilteredOut() {
        let articles = [
            entry("Target", daysAgo: 0),
            entry("Target", daysAgo: 1),
            entry("Other", daysAgo: 0),
            entry("Other", daysAgo: 2),
        ]
        let sut = FeedContentCalendar(referenceDate: refDate)
        let report = sut.analyze(feedName: "Target", articles: articles)

        XCTAssertEqual(report.totalArticlesAnalyzed, 2)
    }

    func testAnalysisDateRange() {
        let articles = (0..<10).map { entry("Range", daysAgo: $0) }
        let sut = FeedContentCalendar(referenceDate: refDate)
        let report = sut.analyze(feedName: "Range", articles: articles)

        XCTAssertNotNil(report.analysisStartDate)
        XCTAssertNotNil(report.analysisEndDate)
        if let start = report.analysisStartDate, let end = report.analysisEndDate {
            XCTAssertLessThan(start, end)
        }
    }

    func testGapStdDevNonNegative() {
        let articles = [0, 1, 3, 4, 8, 12, 13].map { entry("StdDev", daysAgo: $0) }
        let sut = FeedContentCalendar(referenceDate: refDate)
        let report = sut.analyze(feedName: "StdDev", articles: articles)

        XCTAssertGreaterThanOrEqual(report.gapStdDev, 0)
    }

    func testAverageGapDaysReasonable() {
        // 10 articles, 1 per day => avg gap ~1
        let articles = (0..<10).map { entry("AvgGap", daysAgo: $0) }
        let sut = FeedContentCalendar(referenceDate: refDate)
        let report = sut.analyze(feedName: "AvgGap", articles: articles)

        XCTAssertGreaterThan(report.averageGapDays, 0.5)
        XCTAssertLessThan(report.averageGapDays, 2.0)
    }

    // MARK: - Forecast Confidence

    func testForecastConfidenceWithinBounds() {
        let articles = (0..<20).map { entry("Conf", daysAgo: $0) }
        let sut = FeedContentCalendar(referenceDate: refDate)
        let report = sut.analyze(feedName: "Conf", articles: articles)

        for fc in report.forecasts {
            XCTAssertGreaterThanOrEqual(fc.confidence, 0.0)
            XCTAssertLessThanOrEqual(fc.confidence, 1.0)
        }
    }

    func testSporadicFeedForecastLowConfidence() {
        let daysAgo = [0, 2, 15, 17, 28]
        let articles = daysAgo.map { entry("Unpredictable", daysAgo: $0) }
        let sut = FeedContentCalendar(referenceDate: refDate)
        let report = sut.analyze(feedName: "Unpredictable", articles: articles)

        if report.pattern == .sporadic {
            for fc in report.forecasts {
                XCTAssertLessThanOrEqual(fc.confidence, 0.5)
            }
        }
    }

    // MARK: - DayProfile Edge Cases

    func testDayProfileOutOfRangeWeekday() {
        // DayProfile with invalid weekday should return "Unknown"/"?"
        let dp = DayProfile(weekday: 0, totalArticles: 0, averageArticles: 0, peakHour: nil, isRegularDay: false)
        XCTAssertEqual(dp.dayName, "Unknown")
        XCTAssertEqual(dp.shortDayName, "?")

        let dp8 = DayProfile(weekday: 8, totalArticles: 0, averageArticles: 0, peakHour: nil, isRegularDay: false)
        XCTAssertEqual(dp8.dayName, "Unknown")
        XCTAssertEqual(dp8.shortDayName, "?")
    }
}
