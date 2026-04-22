//
//  FeedTrendForecasterTests.swift
//  FeedReaderCoreTests
//
//  Tests for FeedTrendForecaster: momentum computation, phase classification,
//  breakout detection, early signals, and forecast comparison.
//

import XCTest
@testable import FeedReaderCore

final class FeedTrendForecasterTests: XCTestCase {

    private func makeForecaster(minMentions: Int = 2, windowDays: Int = 7) -> FeedTrendForecaster {
        return FeedTrendForecaster(minimumMentions: minMentions, windowDays: windowDays)
    }

    private func daysAgo(_ n: Int) -> Date {
        return Calendar.current.date(byAdding: .day, value: -n, to: Date())!
    }

    // MARK: - Basic Forecast

    func testEmptyArticlesReturnsEmptyForecast() {
        let forecaster = makeForecaster()
        let forecast = forecaster.forecast(articles: [])
        XCTAssertTrue(forecast.signals.isEmpty)
        XCTAssertTrue(forecast.topBreakouts.isEmpty)
    }

    func testSingleMentionBelowThresholdFiltered() {
        let forecaster = makeForecaster(minMentions: 3)
        let articles = [
            (title: "Quantum computing breakthrough", feedName: "TechNews", publishedDate: Date() as Date?)
        ]
        let forecast = forecaster.forecast(articles: articles)
        // "quantum" and "computing" each appear once, below threshold of 3
        XCTAssertTrue(forecast.signals.isEmpty)
    }

    func testRepeatedKeywordDetected() {
        let forecaster = makeForecaster(minMentions: 2)
        let articles = [
            (title: "Blockchain revolution in finance", feedName: "CryptoDaily", publishedDate: daysAgo(1) as Date?),
            (title: "Blockchain adoption surges globally", feedName: "TechCrunch", publishedDate: Date() as Date?),
            (title: "New blockchain standard proposed", feedName: "ArsTechnica", publishedDate: Date() as Date?)
        ]
        let forecast = forecaster.forecast(articles: articles)
        let topics = forecast.signals.map { $0.topic }
        XCTAssertTrue(topics.contains("blockchain"))
    }

    func testTopBreakoutsMaxFive() {
        let forecaster = makeForecaster(minMentions: 2)
        // Create 10 distinct trending keywords
        var articles: [(title: String, feedName: String, publishedDate: Date?)] = []
        let words = ["alpha", "bravo", "charlie", "delta", "echo",
                     "foxtrot", "golf", "hotel", "india", "juliet"]
        for word in words {
            for i in 0..<3 {
                articles.append((title: "\(word) topic discussed", feedName: "Feed\(i)", publishedDate: Date()))
            }
        }
        let forecast = forecaster.forecast(articles: articles)
        XCTAssertLessThanOrEqual(forecast.topBreakouts.count, 5)
    }

    // MARK: - Early Signals

    func testDetectEarlySignals() {
        let forecaster = makeForecaster(minMentions: 2)
        let articles = [
            (title: "Robotics startup raises funding", feedName: "VentureBeat", publishedDate: daysAgo(1) as Date?),
            (title: "Robotics industry grows rapidly", feedName: "TechCrunch", publishedDate: Date() as Date?),
            (title: "Robotics competition results announced", feedName: "IEEE", publishedDate: Date() as Date?)
        ]
        let early = forecaster.detectEarlySignals(articles: articles)
        // All should be emerging or accelerating
        for signal in early {
            XCTAssertTrue(signal.phase == .emerging || signal.phase == .accelerating)
        }
    }

    // MARK: - Forecast Comparison

    func testCompareForecasts() {
        let forecaster = makeForecaster(minMentions: 2)

        let olderArticles = [
            (title: "Climate summit begins today", feedName: "BBC", publishedDate: daysAgo(5) as Date?),
            (title: "Climate talks continue", feedName: "CNN", publishedDate: daysAgo(4) as Date?)
        ]
        let older = forecaster.forecast(articles: olderArticles)

        var newerArticles = olderArticles
        newerArticles.append((title: "Quantum physics breakthrough paper", feedName: "Nature", publishedDate: daysAgo(1) as Date?))
        newerArticles.append((title: "Quantum computing milestone", feedName: "Wired", publishedDate: Date() as Date?))
        let newer = forecaster.forecast(articles: newerArticles)

        let diff = forecaster.compareForecasts(older, newer)
        XCTAssertFalse(diff.textSummary.isEmpty)
    }

    // MARK: - Signal Properties

    func testSignalSummaryContainsTopic() {
        let signal = TrendSignal(
            topic: "testing",
            momentum: 0.8,
            articleCount: 5,
            firstSeen: Date(),
            lastSeen: Date(),
            feedSources: ["A", "B"],
            phase: .accelerating,
            breakoutProbability: 0.7
        )
        XCTAssertTrue(signal.summary.contains("testing"))
        XCTAssertTrue(signal.summary.contains("🚀"))
    }

    func testTrendPhaseEmoji() {
        XCTAssertEqual(TrendPhase.emerging.emoji, "🌱")
        XCTAssertEqual(TrendPhase.accelerating.emoji, "🚀")
        XCTAssertEqual(TrendPhase.peaking.emoji, "🔥")
        XCTAssertEqual(TrendPhase.declining.emoji, "📉")
    }

    // MARK: - Text Report

    func testTextReportNotEmpty() {
        let forecaster = makeForecaster(minMentions: 2)
        let articles = [
            (title: "Space exploration funding increased", feedName: "NASA", publishedDate: daysAgo(2) as Date?),
            (title: "Space mission launches successfully", feedName: "SpaceNews", publishedDate: daysAgo(1) as Date?),
            (title: "Space tourism company expands", feedName: "Bloomberg", publishedDate: Date() as Date?)
        ]
        let forecast = forecaster.forecast(articles: articles)
        XCTAssertTrue(forecast.textReport.contains("TREND FORECAST REPORT"))
    }

    // MARK: - Feed Source Tracking

    func testMultipleFeedSourcesTracked() {
        let forecaster = makeForecaster(minMentions: 2)
        let articles = [
            (title: "Security vulnerability discovered", feedName: "SecurityWeek", publishedDate: Date() as Date?),
            (title: "Security patch released urgently", feedName: "ArsTechnica", publishedDate: Date() as Date?),
            (title: "Security experts warn users", feedName: "Wired", publishedDate: Date() as Date?)
        ]
        let forecast = forecaster.forecast(articles: articles)
        let securitySignal = forecast.signals.first { $0.topic == "security" }
        XCTAssertNotNil(securitySignal)
        if let signal = securitySignal {
            XCTAssertEqual(signal.feedSources.count, 3)
        }
    }

    // MARK: - Proactive Insights

    func testProactiveInsightsGenerated() {
        let forecaster = makeForecaster(minMentions: 2)
        var articles: [(title: String, feedName: String, publishedDate: Date?)] = []
        // Create cross-feed trend
        for feed in ["Feed1", "Feed2", "Feed3", "Feed4"] {
            articles.append((title: "Innovation drives growth", feedName: feed, publishedDate: Date()))
        }
        let forecast = forecaster.forecast(articles: articles)
        // Should generate at least one insight about cross-feed appearance
        XCTAssertFalse(forecast.proactiveInsights.isEmpty)
    }
}
