//
//  FeedWeatherReportTests.swift
//  FeedReaderTests
//

import XCTest
@testable import FeedReader

class FeedWeatherReportTests: XCTestCase {

    var reporter: FeedWeatherReporter!

    override func setUp() {
        super.setUp()
        reporter = FeedWeatherReporter()
        reporter.clearHistory()
        reporter.reportPeriodDays = 7
        reporter.forecastDays = 5
    }

    override func tearDown() {
        reporter.clearHistory()
        super.tearDown()
    }

    // MARK: - Helper

    private func makeStory(
        title: String = "Test Article",
        body: String = "This is a test article body with enough words to be meaningful.",
        source: String? = "TestFeed",
        link: String = "https://example.com/article"
    ) -> Story {
        let story = Story(title: title, body: body, link: link)
        story.sourceFeedName = source
        return story
    }

    private func makeStories(count: Int, source: String = "TestFeed") -> [Story] {
        return (0..<count).map { i in
            makeStory(
                title: "Article \(i)",
                body: "Body text for article number \(i). This article discusses various topics.",
                source: source,
                link: "https://example.com/\(i)"
            )
        }
    }

    // MARK: - Temperature

    func testTemperatureFromArticleCount() {
        XCTAssertEqual(FeedTemperature.from(articlesPerDay: 0), .freezing)
        XCTAssertEqual(FeedTemperature.from(articlesPerDay: 1), .freezing)
        XCTAssertEqual(FeedTemperature.from(articlesPerDay: 3), .cold)
        XCTAssertEqual(FeedTemperature.from(articlesPerDay: 7), .cool)
        XCTAssertEqual(FeedTemperature.from(articlesPerDay: 15), .mild)
        XCTAssertEqual(FeedTemperature.from(articlesPerDay: 30), .warm)
        XCTAssertEqual(FeedTemperature.from(articlesPerDay: 45), .hot)
        XCTAssertEqual(FeedTemperature.from(articlesPerDay: 100), .scorching)
    }

    func testTemperatureHasDescription() {
        for temp in [FeedTemperature.freezing, .cold, .cool, .mild, .warm, .hot, .scorching] {
            XCTAssertFalse(temp.description.isEmpty)
            XCTAssertFalse(temp.rawValue.isEmpty)
        }
    }

    // MARK: - Pressure

    func testPressureFromWordCount() {
        XCTAssertEqual(FeedPressure.from(avgWordCount: 100), .low)
        XCTAssertEqual(FeedPressure.from(avgWordCount: 300), .moderate)
        XCTAssertEqual(FeedPressure.from(avgWordCount: 700), .high)
        XCTAssertEqual(FeedPressure.from(avgWordCount: 1500), .extreme)
    }

    func testPressureHasDescription() {
        for p in [FeedPressure.low, .moderate, .high, .extreme] {
            XCTAssertFalse(p.description.isEmpty)
        }
    }

    // MARK: - Wind Speed

    func testWindSpeedFromChangeRatio() {
        XCTAssertEqual(FeedWindSpeed.from(changeRatio: 0.5), .calm)
        XCTAssertEqual(FeedWindSpeed.from(changeRatio: 1.0), .breeze)
        XCTAssertEqual(FeedWindSpeed.from(changeRatio: 2.0), .gusty)
        XCTAssertEqual(FeedWindSpeed.from(changeRatio: 3.0), .gale)
        XCTAssertEqual(FeedWindSpeed.from(changeRatio: 5.0), .hurricane)
    }

    func testWindSpeedHasDescription() {
        for w in [FeedWindSpeed.calm, .breeze, .gusty, .gale, .hurricane] {
            XCTAssertFalse(w.description.isEmpty)
        }
    }

    // MARK: - UV Index

    func testUVIndexFromFleschScore() {
        XCTAssertEqual(FeedUVIndex.from(fleschScore: 80), .low)
        XCTAssertEqual(FeedUVIndex.from(fleschScore: 60), .moderate)
        XCTAssertEqual(FeedUVIndex.from(fleschScore: 40), .high)
        XCTAssertEqual(FeedUVIndex.from(fleschScore: 20), .veryHigh)
        XCTAssertEqual(FeedUVIndex.from(fleschScore: 5), .extreme)
    }

    // MARK: - Weather Condition

    func testAllConditionsHaveAdvisory() {
        for condition in FeedWeatherCondition.allCases {
            XCTAssertFalse(condition.advisory.isEmpty, "\(condition.rawValue) has no advisory")
        }
    }

    // MARK: - Report Generation

    func testReportRequiresMinimumArticles() {
        let report = reporter.generateReport(from: makeStories(count: 2))
        XCTAssertNil(report)
    }

    func testReportGeneratesWithSufficientData() {
        let report = reporter.generateReport(from: makeStories(count: 10))
        XCTAssertNotNil(report)
    }

    func testReportContainsAllMetrics() {
        let report = reporter.generateReport(from: makeStories(count: 20))!
        XCTAssertGreaterThan(report.totalArticles, 0)
        XCTAssertGreaterThan(report.articlesPerDay, 0)
        XCTAssertGreaterThanOrEqual(report.avgWordCount, 0)
        XCTAssertGreaterThanOrEqual(report.positiveRatio, 0)
        XCTAssertLessThanOrEqual(report.positiveRatio, 1.0)
    }

    func testReportHasPeriodDates() {
        let report = reporter.generateReport(from: makeStories(count: 5))!
        XCTAssertTrue(report.periodStart < report.periodEnd)
    }

    func testReportGeneratesForecast() {
        reporter.forecastDays = 3
        let report = reporter.generateReport(from: makeStories(count: 10))!
        XCTAssertEqual(report.forecast.count, 3)
        for day in report.forecast {
            XCTAssertGreaterThanOrEqual(day.expectedArticles, 0)
            XCTAssertGreaterThan(day.confidence, 0)
            XCTAssertLessThanOrEqual(day.confidence, 1.0)
        }
    }

    func testForecastConfidenceDecreases() {
        reporter.forecastDays = 5
        let report = reporter.generateReport(from: makeStories(count: 10))!
        if report.forecast.count >= 2 {
            XCTAssertGreaterThanOrEqual(
                report.forecast[0].confidence,
                report.forecast.last!.confidence
            )
        }
    }

    // MARK: - Per-Feed Breakdown

    func testReportGroupsByFeed() {
        var stories: [Story] = []
        stories.append(contentsOf: makeStories(count: 5, source: "TechNews"))
        stories.append(contentsOf: makeStories(count: 3, source: "ScienceBlog"))
        let report = reporter.generateReport(from: stories)!

        XCTAssertEqual(report.feedTemperatures.count, 2)
        let tech = report.feedTemperatures.first { $0.feedName == "TechNews" }
        XCTAssertEqual(tech?.articleCount, 5)
    }

    func testFeedTemperaturesSortedByCount() {
        var stories: [Story] = []
        stories.append(contentsOf: makeStories(count: 10, source: "Popular"))
        stories.append(contentsOf: makeStories(count: 3, source: "Niche"))
        stories.append(contentsOf: makeStories(count: 7, source: "Medium"))
        let report = reporter.generateReport(from: stories)!

        XCTAssertEqual(report.feedTemperatures[0].feedName, "Popular")
        XCTAssertEqual(report.feedTemperatures[1].feedName, "Medium")
        XCTAssertEqual(report.feedTemperatures[2].feedName, "Niche")
    }

    // MARK: - Sentiment

    func testPositiveSentiment() {
        let score = reporter.analyzeSentiment(text: "great wonderful amazing excellent brilliant")
        XCTAssertGreaterThan(score, 0)
    }

    func testNegativeSentiment() {
        let score = reporter.analyzeSentiment(text: "terrible awful horrible disaster crisis failure")
        XCTAssertLessThan(score, 0)
    }

    func testNeutralSentiment() {
        let score = reporter.analyzeSentiment(text: "The meeting will be held on Tuesday in the conference room")
        XCTAssertEqual(score, 0, accuracy: 0.3)
    }

    func testEmptyTextSentiment() {
        XCTAssertEqual(reporter.analyzeSentiment(text: ""), 0)
    }

    // MARK: - Word Count

    func testWordCount() {
        XCTAssertEqual(reporter.countWords(in: "Hello world"), 2)
        XCTAssertEqual(reporter.countWords(in: ""), 0)
        XCTAssertEqual(reporter.countWords(in: "one"), 1)
        XCTAssertEqual(reporter.countWords(in: "  multiple   spaces   here  "), 3)
    }

    // MARK: - Syllable Count

    func testSyllableCount() {
        XCTAssertEqual(reporter.countSyllables(in: "cat"), 1)
        XCTAssertEqual(reporter.countSyllables(in: "hello"), 2)
        XCTAssertEqual(reporter.countSyllables(in: "beautiful"), 3)
        XCTAssertEqual(reporter.countSyllables(in: ""), 0)
    }

    func testSyllableCountMinimumOne() {
        XCTAssertGreaterThanOrEqual(reporter.countSyllables(in: "rhythm"), 1)
    }

    // MARK: - Flesch Reading Ease

    func testFleschEaseEasyText() {
        let score = reporter.computeFleschEase(text: "The cat sat on the mat. The dog ran fast. It was fun.")
        XCTAssertGreaterThan(score, 60)
    }

    func testFleschEaseComplexText() {
        let score = reporter.computeFleschEase(text: "The epistemological ramifications of quantum decoherence in macroscopic thermodynamic systems necessitate a fundamental reconceptualization of observer-dependent measurement paradigms.")
        XCTAssertLessThan(score, 30)
    }

    // MARK: - History

    func testReportStoredInHistory() {
        let _ = reporter.generateReport(from: makeStories(count: 5))
        XCTAssertEqual(reporter.getReportHistory().count, 1)
    }

    func testMultipleReportsStored() {
        for _ in 0..<3 {
            let _ = reporter.generateReport(from: makeStories(count: 5))
        }
        XCTAssertEqual(reporter.getReportHistory().count, 3)
    }

    func testLatestReport() {
        let _ = reporter.generateReport(from: makeStories(count: 5))
        let second = reporter.generateReport(from: makeStories(count: 5))
        let latest = reporter.latestReport()
        XCTAssertEqual(latest?.generatedAt, second?.generatedAt)
    }

    func testClearHistory() {
        let _ = reporter.generateReport(from: makeStories(count: 5))
        reporter.clearHistory()
        XCTAssertTrue(reporter.getReportHistory().isEmpty)
    }

    // MARK: - Summary

    func testReportSummaryNotEmpty() {
        let report = reporter.generateReport(from: makeStories(count: 10))!
        XCTAssertFalse(report.summary.isEmpty)
        XCTAssertTrue(report.summary.contains("Feed Weather Report"))
        XCTAssertTrue(report.summary.contains("Temperature"))
    }

    func testReportAdvisoryNotEmpty() {
        let report = reporter.generateReport(from: makeStories(count: 10))!
        XCTAssertFalse(report.advisory.isEmpty)
    }

    // MARK: - Alerts

    func testTopicFloodAlert() {
        var stories: [Story] = []
        stories.append(contentsOf: makeStories(count: 20, source: "Dominant"))
        stories.append(contentsOf: makeStories(count: 2, source: "Tiny"))
        let report = reporter.generateReport(from: stories)!
        XCTAssertFalse(report.alerts.filter { $0.type == .topicFlood }.isEmpty)
    }

    func testLongReadSurgeAlert() {
        let stories = (0..<5).map { i in
            makeStory(title: "Art \(i)", body: String(repeating: "word ", count: 1000), source: "Long")
        }
        let report = reporter.generateReport(from: stories)!
        XCTAssertFalse(report.alerts.filter { $0.type == .longReadSurge }.isEmpty)
    }

    // MARK: - Comparison

    func testCompareIdenticalReports() {
        let report = reporter.generateReport(from: makeStories(count: 10))!
        let comparison = reporter.compareReports(report, report)
        XCTAssertTrue(comparison.contains("No significant changes"))
    }

    // MARK: - Edge Cases

    func testEmptyStoriesReturnsNil() {
        XCTAssertNil(reporter.generateReport(from: []))
    }

    func testSingleFeedStories() {
        let report = reporter.generateReport(from: makeStories(count: 5, source: "Only"))!
        XCTAssertEqual(report.feedTemperatures.count, 1)
    }

    func testStoriesWithNoSource() {
        let stories = (0..<5).map { i in
            makeStory(title: "No source \(i)", body: "Body.", source: nil)
        }
        let report = reporter.generateReport(from: stories)!
        XCTAssertNotNil(report.feedTemperatures.first { $0.feedName == "Unknown" })
    }

    func testReportHistoryLimitedTo30() {
        for _ in 0..<35 {
            let _ = reporter.generateReport(from: makeStories(count: 5))
        }
        XCTAssertLessThanOrEqual(reporter.getReportHistory().count, 30)
    }

    func testNegativeContentLowPositiveRatio() {
        let stories = (0..<10).map { i in
            makeStory(
                title: "Crisis disaster failure terrible \(i)",
                body: "War conflict death tragedy corruption scandal collapse.",
                source: "NegFeed"
            )
        }
        let report = reporter.generateReport(from: stories)!
        XCTAssertLessThan(report.positiveRatio, 0.5)
    }

    func testPositiveContentHighPositiveRatio() {
        let stories = (0..<5).map { i in
            makeStory(
                title: "Great amazing wonderful success \(i)",
                body: "Excellent brilliant outstanding achievement progress.",
                source: "PosFeed"
            )
        }
        let report = reporter.generateReport(from: stories)!
        XCTAssertGreaterThan(report.positiveRatio, 0.5)
    }
}
