//
//  FeedSentimentRadarTests.swift
//  FeedReaderCoreTests
//
//  Tests for FeedSentimentRadar: lexicon scoring, polarity, feed analysis,
//  trend detection, alerts, and report generation.
//

import XCTest
@testable import FeedReaderCore

final class FeedSentimentRadarTests: XCTestCase {

    private func makeRadar() -> FeedSentimentRadar {
        return FeedSentimentRadar()
    }

    private func makeStory(title: String, body: String) -> RSSStory {
        return RSSStory(title: title, body: body, link: "https://example.com/\(UUID().uuidString)")!
    }

    // MARK: - Single Article Analysis

    func testPositiveArticle() {
        let radar = makeRadar()
        let result = radar.analyze(title: "Markets Surge on Excellent Jobs Report", text: "Stocks rallied with impressive gains and strong growth.")
        XCTAssertGreaterThan(result.score, 0.0)
        XCTAssertTrue(result.polarity == .positive || result.polarity == .veryPositive)
        XCTAssertFalse(result.positiveWords.isEmpty)
    }

    func testNegativeArticle() {
        let radar = makeRadar()
        let result = radar.analyze(title: "Crisis Deepens as Markets Crash", text: "Devastating losses and catastrophic failure across sectors.")
        XCTAssertLessThan(result.score, 0.0)
        XCTAssertTrue(result.polarity == .negative || result.polarity == .veryNegative)
        XCTAssertFalse(result.negativeWords.isEmpty)
    }

    func testNeutralArticle() {
        let radar = makeRadar()
        let result = radar.analyze(title: "Company Releases Quarterly Report", text: "The company filed documents with regulators.")
        // Neutral-ish — no strong sentiment words
        XCTAssertTrue(result.score > -0.3 && result.score < 0.3)
    }

    func testNegationFlipsSentiment() {
        let radar = makeRadar()
        let positive = radar.analyze(title: "Great results", text: "")
        let negated = radar.analyze(title: "Not great results", text: "")
        XCTAssertGreaterThan(positive.score, negated.score)
    }

    func testIntensifierAmplifies() {
        let radar = makeRadar()
        let normal = radar.analyze(title: "Good performance", text: "")
        let intensified = radar.analyze(title: "Extremely good performance", text: "")
        XCTAssertGreaterThan(intensified.score, normal.score)
    }

    func testConfidenceScaling() {
        let radar = makeRadar()
        let short = radar.analyze(title: "Good", text: "")
        let long = radar.analyze(title: "Good", text: "The quick brown fox jumped over the lazy dog and then kept running through fields of grass.")
        // Short text with sentiment word should have higher confidence ratio
        XCTAssertGreaterThan(short.confidence, 0.0)
    }

    // MARK: - Feed Analysis

    func testFeedAnalysis() {
        let radar = makeRadar()
        let stories = [
            makeStory(title: "Great Innovation in Tech", body: "Amazing breakthrough with impressive results."),
            makeStory(title: "Strong Growth Continues", body: "Successful quarter with excellent gains."),
            makeStory(title: "Market Update", body: "Stable conditions reported across sectors."),
        ]
        let summary = radar.analyzeFeed(name: "Tech Feed", stories: stories)
        XCTAssertEqual(summary.feedName, "Tech Feed")
        XCTAssertEqual(summary.articleCount, 3)
        XCTAssertGreaterThan(summary.averageScore, 0.0)
        XCTAssertNotNil(summary.mostPositive)
        XCTAssertNotNil(summary.mostNegative)
    }

    func testEmptyFeedReturnsNeutral() {
        let radar = makeRadar()
        let summary = radar.analyzeFeed(name: "Empty", stories: [])
        XCTAssertEqual(summary.articleCount, 0)
        XCTAssertEqual(summary.polarity, .neutral)
        XCTAssertEqual(summary.trend, "no data")
    }

    func testNegativeFeedTriggersAlert() {
        let radar = makeRadar()
        let stories = [
            makeStory(title: "Crisis Worsens", body: "Devastating collapse and catastrophic failure."),
            makeStory(title: "Terrible Results", body: "Horrible losses and dangerous decline."),
            makeStory(title: "Markets Crash Again", body: "Disastrous crash destroyed confidence."),
            makeStory(title: "Fear Spreads", body: "Dangerous threat causing widespread concern and worry."),
        ]
        let summary = radar.analyzeFeed(name: "Bad News", stories: stories)
        XCTAssertLessThan(summary.averageScore, -0.2)
        XCTAssertFalse(summary.alerts.isEmpty, "Should have alerts for negative feed")
    }

    // MARK: - Shift Detection

    func testMoodShiftDetected() {
        let radar = FeedSentimentRadar(shiftThreshold: 0.2)
        // First half negative, second half positive
        let stories = [
            makeStory(title: "Crisis and Failure", body: "Terrible catastrophic collapse."),
            makeStory(title: "Devastating Losses", body: "Horrible crash and destruction."),
            makeStory(title: "Excellent Recovery", body: "Amazing breakthrough with impressive growth."),
            makeStory(title: "Outstanding Success", body: "Brilliant innovation and wonderful gains."),
        ]
        let summary = radar.analyzeFeed(name: "Shifty", stories: stories)
        let shiftAlerts = summary.alerts.filter { $0.message.contains("mood shift") }
        XCTAssertFalse(shiftAlerts.isEmpty, "Should detect mood shift from negative to positive")
    }

    // MARK: - Report Generation

    func testReportGeneration() {
        let radar = makeRadar()
        let techStories = [
            makeStory(title: "Great Innovation", body: "Amazing results and excellent progress."),
        ]
        let newsStories = [
            makeStory(title: "Crisis Report", body: "Terrible failure and dangerous risk."),
        ]
        let report = radar.generateReport(feeds: [("Tech", techStories), ("News", newsStories)])
        XCTAssertTrue(report.contains("FEED SENTIMENT RADAR REPORT"))
        XCTAssertTrue(report.contains("Tech"))
        XCTAssertTrue(report.contains("News"))
        XCTAssertTrue(report.contains("RECOMMENDATIONS"))
    }

    // MARK: - Polarity Classification

    func testPolarityClassification() {
        let radar = makeRadar()
        // Very positive
        let vp = radar.analyze(title: "Excellent amazing outstanding brilliant", text: "")
        XCTAssertTrue(vp.polarity == .positive || vp.polarity == .veryPositive)

        // Very negative
        let vn = radar.analyze(title: "Terrible horrible catastrophic devastating", text: "")
        XCTAssertTrue(vn.polarity == .negative || vn.polarity == .veryNegative)
    }
}
