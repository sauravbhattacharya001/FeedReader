//
//  ArticleEngagementPredictorTests.swift
//  FeedReaderTests
//
//  Tests for ArticleEngagementPredictor — verifies prediction scoring,
//  model training, analytics, outcome recording, and edge cases.
//

import XCTest
@testable import FeedReader

class ArticleEngagementPredictorTests: XCTestCase {

    var predictor: ArticleEngagementPredictor!

    override func setUp() {
        super.setUp()
        predictor = ArticleEngagementPredictor()
        predictor.resetAll()
    }

    override func tearDown() {
        predictor.resetAll()
        predictor = nil
        super.tearDown()
    }

    // MARK: - Cold Start (Insufficient Data)

    func testPredictWithNoDataReturnsNeutral() {
        let result = predictor.predict(feedTitle: "TechCrunch", wordCount: 800, hour: 10, dayOfWeek: 2)
        XCTAssertEqual(result.value, 0.5, accuracy: 0.001)
        XCTAssertEqual(result.label, "Not enough data yet")
        XCTAssertEqual(result.factors.count, 1)
        XCTAssertEqual(result.factors.first?.name, "sample_size")
    }

    func testPredictWithFourOutcomesStillReturnsNeutral() {
        for i in 0..<4 {
            predictor.recordOutcome(articleId: "a\(i)", feedTitle: "Feed", wordCount: 500,
                                    hour: 10, dayOfWeek: 2, keywords: [], completed: true)
        }
        let result = predictor.predict(feedTitle: "Feed", wordCount: 500, hour: 10, dayOfWeek: 2)
        XCTAssertEqual(result.label, "Not enough data yet")
    }

    // MARK: - Basic Prediction After Training

    func testPredictWithEnoughDataReturnsScoreAboveBaseline() {
        // Record 10 completed articles from "GoodFeed"
        for i in 0..<10 {
            predictor.recordOutcome(articleId: "g\(i)", feedTitle: "GoodFeed", wordCount: 800,
                                    hour: 9, dayOfWeek: 3, keywords: ["swift"], completed: true)
        }
        let result = predictor.predict(feedTitle: "GoodFeed", wordCount: 800, hour: 9, dayOfWeek: 3, keywords: ["swift"])
        XCTAssertGreaterThan(result.value, 0.7)
        XCTAssertEqual(result.label, "Likely to finish")
    }

    func testPredictLowEngagementFeed() {
        // 10 completed from GoodFeed, 10 abandoned from BadFeed
        for i in 0..<10 {
            predictor.recordOutcome(articleId: "g\(i)", feedTitle: "GoodFeed", wordCount: 800,
                                    hour: 9, dayOfWeek: 3, keywords: [], completed: true)
            predictor.recordOutcome(articleId: "b\(i)", feedTitle: "BadFeed", wordCount: 800,
                                    hour: 9, dayOfWeek: 3, keywords: [], completed: false)
        }
        let good = predictor.predict(feedTitle: "GoodFeed", wordCount: 800, hour: 9, dayOfWeek: 3)
        let bad = predictor.predict(feedTitle: "BadFeed", wordCount: 800, hour: 9, dayOfWeek: 3)
        XCTAssertGreaterThan(good.value, bad.value,
                             "GoodFeed (100% completion) should score higher than BadFeed (0%)")
    }

    // MARK: - Factor Contributions

    func testFeedAffinityFactorPresent() {
        seedMinimalData()
        let result = predictor.predict(feedTitle: "TestFeed", wordCount: 800, hour: 10, dayOfWeek: 2)
        let feedFactor = result.factors.first { $0.name == "feed_affinity" }
        XCTAssertNotNil(feedFactor, "Should include feed_affinity factor")
    }

    func testTimeOfDayFactorPresent() {
        seedMinimalData()
        let result = predictor.predict(feedTitle: "TestFeed", wordCount: 800, hour: 10, dayOfWeek: 2)
        let hourFactor = result.factors.first { $0.name == "time_of_day" }
        XCTAssertNotNil(hourFactor)
    }

    func testWordCountFactorPresent() {
        seedMinimalData()
        let result = predictor.predict(feedTitle: "TestFeed", wordCount: 800, hour: 10, dayOfWeek: 2)
        let wcFactor = result.factors.first { $0.name == "word_count" }
        XCTAssertNotNil(wcFactor)
    }

    func testKeywordFactorAppearsWhenKeywordsMatch() {
        for i in 0..<10 {
            predictor.recordOutcome(articleId: "k\(i)", feedTitle: "Feed", wordCount: 800,
                                    hour: 10, dayOfWeek: 2, keywords: ["rust", "wasm"],
                                    completed: true)
        }
        let result = predictor.predict(feedTitle: "Feed", wordCount: 800, hour: 10, dayOfWeek: 2,
                                       keywords: ["rust"])
        let kwFactor = result.factors.first { $0.name == "topic_keywords" }
        XCTAssertNotNil(kwFactor, "Should include keyword factor when keywords match")
    }

    func testKeywordFactorAbsentWhenNoKeywordsProvided() {
        seedMinimalData()
        let result = predictor.predict(feedTitle: "TestFeed", wordCount: 800, hour: 10, dayOfWeek: 2,
                                       keywords: [])
        let kwFactor = result.factors.first { $0.name == "topic_keywords" }
        XCTAssertNil(kwFactor)
    }

    // MARK: - Score Clamping

    func testScoreClampedBetweenZeroAndOne() {
        // All completed → high score, should not exceed 1.0
        for i in 0..<20 {
            predictor.recordOutcome(articleId: "c\(i)", feedTitle: "Great", wordCount: 1000,
                                    hour: 9, dayOfWeek: 3, keywords: ["ai"], completed: true)
        }
        let result = predictor.predict(feedTitle: "Great", wordCount: 1000, hour: 9, dayOfWeek: 3,
                                       keywords: ["ai"])
        XCTAssertLessThanOrEqual(result.value, 1.0)
        XCTAssertGreaterThanOrEqual(result.value, 0.0)
    }

    // MARK: - Outcome Recording

    func testRecordOutcomeAddsToList() {
        predictor.recordOutcome(articleId: "test1", feedTitle: "Feed", wordCount: 500,
                                hour: 8, dayOfWeek: 1, keywords: [], completed: true)
        XCTAssertEqual(predictor.outcomes.count, 1)
        XCTAssertEqual(predictor.outcomes.first?.id, "test1")
        XCTAssertTrue(predictor.outcomes.first?.completed ?? false)
    }

    func testOutcomeTrimmingAtMaxLimit() {
        // Record maxOutcomes + 10 outcomes
        let limit = predictor.maxOutcomes
        for i in 0..<(limit + 10) {
            predictor.recordOutcome(articleId: "a\(i)", feedTitle: "Feed", wordCount: 500,
                                    hour: 10, dayOfWeek: 2, keywords: [], completed: true,
                                    autoRetrain: false)
        }
        XCTAssertLessThanOrEqual(predictor.outcomes.count, limit,
                                 "Should trim to maxOutcomes")
        // Oldest should be trimmed — first remaining should be "a10"
        XCTAssertEqual(predictor.outcomes.first?.id, "a10")
    }

    // MARK: - Retrain

    func testRetrainUpdatesModelSampleCount() {
        for i in 0..<8 {
            predictor.recordOutcome(articleId: "r\(i)", feedTitle: "Feed", wordCount: 600,
                                    hour: 14, dayOfWeek: 5, keywords: [], completed: i % 2 == 0,
                                    autoRetrain: false)
        }
        predictor.retrain()
        XCTAssertEqual(predictor.model.sampleCount, 8)
        XCTAssertEqual(predictor.model.baselineRate, 0.5, accuracy: 0.001)
    }

    func testRetrainComputesFeedRates() {
        for i in 0..<6 {
            predictor.recordOutcome(articleId: "f\(i)", feedTitle: "AlwaysRead", wordCount: 500,
                                    hour: 10, dayOfWeek: 2, keywords: [], completed: true,
                                    autoRetrain: false)
        }
        for i in 0..<6 {
            predictor.recordOutcome(articleId: "n\(i)", feedTitle: "NeverRead", wordCount: 500,
                                    hour: 10, dayOfWeek: 2, keywords: [], completed: false,
                                    autoRetrain: false)
        }
        predictor.retrain()
        XCTAssertEqual(predictor.model.feedCompletionRates["AlwaysRead"], 1.0, accuracy: 0.001)
        XCTAssertEqual(predictor.model.feedCompletionRates["NeverRead"], 0.0, accuracy: 0.001)
    }

    func testRetrainComputesOptimalWordCountRange() {
        // Completed articles with word counts 200, 400, 600, 800, 1000, 1200, 1400, 1600
        for wc in stride(from: 200, through: 1600, by: 200) {
            predictor.recordOutcome(articleId: "w\(wc)", feedTitle: "Feed", wordCount: wc,
                                    hour: 10, dayOfWeek: 2, keywords: [], completed: true,
                                    autoRetrain: false)
        }
        predictor.retrain()
        // Q1 = 200 + (1600-200)*0.25 ≈ 400, Q3 ≈ 1200 (depends on integer division)
        XCTAssertGreaterThan(predictor.model.optimalWordCountMax, predictor.model.optimalWordCountMin)
    }

    func testRetrainComputesKeywordScores() {
        for i in 0..<5 {
            predictor.recordOutcome(articleId: "kw\(i)", feedTitle: "Feed", wordCount: 800,
                                    hour: 10, dayOfWeek: 2, keywords: ["Swift"], completed: true,
                                    autoRetrain: false)
        }
        predictor.retrain()
        XCTAssertEqual(predictor.model.keywordScores["swift"], 1.0, accuracy: 0.001,
                       "Keyword 'swift' (lowercased) should have 100% completion rate")
    }

    func testRetrainIgnoresKeywordsWithFewerThan3Occurrences() {
        predictor.recordOutcome(articleId: "r1", feedTitle: "Feed", wordCount: 800,
                                hour: 10, dayOfWeek: 2, keywords: ["rare"], completed: true,
                                autoRetrain: false)
        predictor.recordOutcome(articleId: "r2", feedTitle: "Feed", wordCount: 800,
                                hour: 10, dayOfWeek: 2, keywords: ["rare"], completed: true,
                                autoRetrain: false)
        predictor.retrain()
        XCTAssertNil(predictor.model.keywordScores["rare"],
                     "Keywords with <3 occurrences should not be in model")
    }

    // MARK: - Analytics

    func testTopFeedsRequiresMinimum3Articles() {
        predictor.recordOutcome(articleId: "t1", feedTitle: "Tiny", wordCount: 500,
                                hour: 10, dayOfWeek: 2, keywords: [], completed: true)
        predictor.recordOutcome(articleId: "t2", feedTitle: "Tiny", wordCount: 500,
                                hour: 10, dayOfWeek: 2, keywords: [], completed: true)
        let top = predictor.topFeeds()
        XCTAssertTrue(top.isEmpty, "Feed with only 2 articles should be excluded")
    }

    func testTopFeedsSortedByCompletionRate() {
        for i in 0..<5 {
            predictor.recordOutcome(articleId: "a\(i)", feedTitle: "A", wordCount: 500,
                                    hour: 10, dayOfWeek: 2, keywords: [], completed: true)
            predictor.recordOutcome(articleId: "b\(i)", feedTitle: "B", wordCount: 500,
                                    hour: 10, dayOfWeek: 2, keywords: [], completed: i < 2)
        }
        let top = predictor.topFeeds()
        XCTAssertEqual(top.first?.feed, "A")
        XCTAssertEqual(top.first?.rate, 1.0, accuracy: 0.001)
    }

    func testBestHoursReturnsSortedByRate() {
        seedMinimalData()
        let hours = predictor.bestHours()
        if hours.count >= 2 {
            XCTAssertGreaterThanOrEqual(hours[0].rate, hours[1].rate)
        }
    }

    func testSummaryWithInsufficientData() {
        let summary = predictor.summary()
        XCTAssertTrue(summary.contains("Not enough reading data"))
    }

    func testSummaryWithSufficientData() {
        seedMinimalData()
        let summary = predictor.summary()
        XCTAssertTrue(summary.contains("Engagement Summary"))
        XCTAssertTrue(summary.contains("completion rate"))
    }

    // MARK: - Label Classification

    func testLabelClassification() {
        XCTAssertEqual(EngagementPrediction.labelFor(score: 0.9), "Likely to finish")
        XCTAssertEqual(EngagementPrediction.labelFor(score: 0.8), "Likely to finish")
        XCTAssertEqual(EngagementPrediction.labelFor(score: 0.6), "Might skim")
        XCTAssertEqual(EngagementPrediction.labelFor(score: 0.5), "Might skim")
        XCTAssertEqual(EngagementPrediction.labelFor(score: 0.4), "Probably skip")
        XCTAssertEqual(EngagementPrediction.labelFor(score: 0.3), "Probably skip")
        XCTAssertEqual(EngagementPrediction.labelFor(score: 0.2), "Very unlikely to read")
        XCTAssertEqual(EngagementPrediction.labelFor(score: 0.0), "Very unlikely to read")
    }

    // MARK: - Reset

    func testResetAllClearsEverything() {
        seedMinimalData()
        predictor.resetAll()
        XCTAssertTrue(predictor.outcomes.isEmpty)
        XCTAssertEqual(predictor.model.sampleCount, 0)
        XCTAssertEqual(predictor.model.baselineRate, 0.5, accuracy: 0.001)
    }

    // MARK: - Export

    func testExportJSONProducesValidData() {
        seedMinimalData()
        let data = predictor.exportJSON()
        XCTAssertNotNil(data)
        XCTAssertGreaterThan(data?.count ?? 0, 0)
    }

    // MARK: - Helpers

    /// Seeds 10 outcomes so the model has enough data to make predictions.
    private func seedMinimalData() {
        for i in 0..<10 {
            predictor.recordOutcome(
                articleId: "seed\(i)", feedTitle: "TestFeed", wordCount: 800,
                hour: 10, dayOfWeek: 2, keywords: ["tech"],
                completed: i < 7 // 70% completion rate
            )
        }
    }
}
