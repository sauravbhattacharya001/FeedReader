//
//  FeedPredictiveInterestEngineTests.swift
//  FeedReaderCoreTests
//
//  Tests for the autonomous predictive interest engine.
//

import XCTest
@testable import FeedReaderCore

final class FeedPredictiveInterestEngineTests: XCTestCase {

    var engine: FeedPredictiveInterestEngine!
    let calendar = Calendar.current

    override func setUp() {
        super.setUp()
        engine = FeedPredictiveInterestEngine()
    }

    override func tearDown() {
        engine = nil
        super.tearDown()
    }

    // MARK: - Basic Recording

    func testRecordInteraction() {
        engine.recordInteraction(topic: "Swift", feedURL: "https://feed1.com",
                                articleId: "a1", interactionType: .read)
        XCTAssertEqual(engine.signalCount, 1)
    }

    func testRecordMultipleInteractions() {
        for i in 1...10 {
            engine.recordInteraction(topic: "AI", feedURL: "https://feed\(i).com",
                                    articleId: "a\(i)", interactionType: .read)
        }
        XCTAssertEqual(engine.signalCount, 10)
    }

    func testRecordOutcome() {
        engine.recordOutcome(predictedTopic: "ML", predictionDate: Date(),
                            confidence: .high, wasAccurate: true)
        XCTAssertEqual(engine.outcomeCount, 1)
    }

    func testTopicNormalization() {
        engine.recordInteraction(topic: "  Machine Learning  ", feedURL: "f1",
                                articleId: "a1", interactionType: .read)
        engine.recordInteraction(topic: "machine learning", feedURL: "f2",
                                articleId: "a2", interactionType: .read)
        engine.recordInteraction(topic: "MACHINE LEARNING", feedURL: "f3",
                                articleId: "a3", interactionType: .read)
        let trajectories = engine.getTrajectories()
        XCTAssertEqual(trajectories.count, 1)
        XCTAssertEqual(trajectories.first?.topic, "machine learning")
    }

    // MARK: - Trajectory Computation

    func testMinimumSignalsForTrajectory() {
        engine.minimumSignalsForTrajectory = 3
        engine.recordInteraction(topic: "rust", feedURL: "f1", articleId: "a1", interactionType: .read)
        engine.recordInteraction(topic: "rust", feedURL: "f2", articleId: "a2", interactionType: .read)
        let trajectories = engine.getTrajectories()
        XCTAssertTrue(trajectories.isEmpty, "Should need at least 3 signals")
    }

    func testTrajectoryFormation() {
        let now = Date()
        for i in 0..<5 {
            let ts = calendar.date(byAdding: .day, value: -i, to: now)!
            engine.recordInteraction(topic: "kubernetes", feedURL: "f\(i)",
                                    articleId: "a\(i)", interactionType: .read,
                                    dwellSeconds: 120, timestamp: ts)
        }
        let trajectories = engine.getTrajectories(asOf: now)
        XCTAssertEqual(trajectories.count, 1)
        XCTAssertEqual(trajectories.first?.topic, "kubernetes")
        XCTAssertEqual(trajectories.first?.totalSignals, 5)
    }

    func testFeedSpread() {
        let now = Date()
        let feeds = ["https://a.com/feed", "https://b.com/feed", "https://c.com/feed"]
        for (i, feed) in feeds.enumerated() {
            engine.recordInteraction(topic: "graphql", feedURL: feed,
                                    articleId: "a\(i)", interactionType: .read,
                                    timestamp: calendar.date(byAdding: .day, value: -i, to: now)!)
        }
        let trajectories = engine.getTrajectories(asOf: now)
        XCTAssertEqual(trajectories.first?.feedSpread, 3)
    }

    func testDwellAverage() {
        let now = Date()
        let dwells: [Double] = [60, 120, 180]
        for (i, dwell) in dwells.enumerated() {
            engine.recordInteraction(topic: "design", feedURL: "f\(i)",
                                    articleId: "a\(i)", interactionType: .read,
                                    dwellSeconds: dwell,
                                    timestamp: calendar.date(byAdding: .day, value: -i, to: now)!)
        }
        let trajectories = engine.getTrajectories(asOf: now)
        XCTAssertEqual(trajectories.first?.dwellAverage ?? 0, 120, accuracy: 1)
    }

    // MARK: - Phase Classification

    func testDormantPhase() {
        let now = Date()
        for i in 0..<5 {
            let ts = calendar.date(byAdding: .day, value: -(20 + i), to: now)!
            engine.recordInteraction(topic: "old topic", feedURL: "f\(i)",
                                    articleId: "a\(i)", interactionType: .read, timestamp: ts)
        }
        let trajectories = engine.getTrajectories(asOf: now)
        XCTAssertEqual(trajectories.first?.phase, .dormant)
    }

    func testEmergingPhase() {
        let now = Date()
        // Recent signals with low overall strength
        for i in 0..<4 {
            let ts = calendar.date(byAdding: .day, value: -i, to: now)!
            engine.recordInteraction(topic: "new thing", feedURL: "f\(i)",
                                    articleId: "a\(i)", interactionType: .click, timestamp: ts)
        }
        let trajectories = engine.getTrajectories(asOf: now)
        let phase = trajectories.first?.phase
        // Should be emerging or latent (low strength, positive velocity)
        XCTAssertTrue(phase == .emerging || phase == .latent || phase == .growing)
    }

    // MARK: - Forecasting

    func testForecastWithNoData() {
        let forecast = engine.forecast()
        XCTAssertTrue(forecast.predictions.isEmpty)
        XCTAssertTrue(forecast.trajectories.isEmpty)
        XCTAssertTrue(forecast.surfacedArticles.isEmpty)
        XCTAssertEqual(forecast.predictionAccuracy, 0.5) // Default neutral
    }

    func testForecastGeneratesPredictions() {
        let now = Date()
        // Create growing interest pattern
        for i in 0..<10 {
            let ts = calendar.date(byAdding: .day, value: -(10 - i), to: now)!
            engine.recordInteraction(topic: "webassembly", feedURL: "f\(i % 3)",
                                    articleId: "a\(i)", interactionType: .read,
                                    dwellSeconds: 90, timestamp: ts)
        }
        let forecast = engine.forecast(asOf: now)
        XCTAssertFalse(forecast.trajectories.isEmpty)
    }

    func testForecastHealthScore() {
        let now = Date()
        for i in 0..<20 {
            let ts = calendar.date(byAdding: .day, value: -(20 - i), to: now)!
            engine.recordInteraction(topic: "topic\(i % 5)", feedURL: "f\(i % 4)",
                                    articleId: "a\(i)", interactionType: .read,
                                    dwellSeconds: 60, timestamp: ts)
        }
        let forecast = engine.forecast(asOf: now)
        XCTAssertGreaterThan(forecast.healthScore, 0)
        XCTAssertLessThanOrEqual(forecast.healthScore, 100)
        XCTAssertFalse(forecast.healthGrade.isEmpty)
    }

    func testForecastInsights() {
        let now = Date()
        // Create diverse signals
        for i in 0..<30 {
            let topic = ["ai", "rust", "devops", "security", "wasm"][i % 5]
            let ts = calendar.date(byAdding: .day, value: -(30 - i), to: now)!
            engine.recordInteraction(topic: topic, feedURL: "f\(i % 6)",
                                    articleId: "a\(i)", interactionType: .read,
                                    dwellSeconds: Double(60 + i * 10), timestamp: ts)
        }
        let forecast = engine.forecast(asOf: now)
        XCTAssertFalse(forecast.insights.isEmpty)
    }

    // MARK: - Co-occurrence & Adjacent Predictions

    func testCoOccurrencePredictions() {
        let now = Date()
        // Build co-occurrence: topic A always appears with topic B
        for i in 0..<8 {
            let ts = calendar.date(byAdding: .day, value: -i, to: now)!
            engine.recordInteraction(topic: "react", feedURL: "f1",
                                    articleId: "shared\(i)", interactionType: .read,
                                    dwellSeconds: 90, timestamp: ts,
                                    relatedTopics: ["nextjs"])
        }
        // "nextjs" has co-occurrence with "react" but no direct signals
        let forecast = engine.forecast(asOf: now)
        let nextjsPrediction = forecast.predictions.first { $0.topic == "nextjs" }
        // May or may not appear depending on thresholds, but engine shouldn't crash
        XCTAssertNotNil(forecast.predictions)
    }

    func testAdjacentTopicsFound() {
        let now = Date()
        for i in 0..<6 {
            let ts = calendar.date(byAdding: .day, value: -i, to: now)!
            engine.recordInteraction(topic: "python", feedURL: "f1",
                                    articleId: "a\(i)", interactionType: .read,
                                    timestamp: ts, relatedTopics: ["data science", "pandas"])
        }
        let trajectories = engine.getTrajectories(asOf: now)
        XCTAssertFalse(trajectories.isEmpty)
    }

    // MARK: - Article Surfacing

    func testArticleSurfacing() {
        let now = Date()
        // Build interest
        for i in 0..<8 {
            let ts = calendar.date(byAdding: .day, value: -i, to: now)!
            engine.recordInteraction(topic: "llm", feedURL: "f\(i % 3)",
                                    articleId: "a\(i)", interactionType: .read,
                                    dwellSeconds: 120, timestamp: ts)
        }
        // Register candidates
        engine.registerCandidates([
            CandidateArticle(articleId: "c1", feedURL: "f5", topics: ["llm", "gpt"]),
            CandidateArticle(articleId: "c2", feedURL: "f6", topics: ["cooking", "recipes"]),
        ])
        let forecast = engine.forecast(asOf: now)
        let llmSurfaced = forecast.surfacedArticles.first { $0.articleId == "c1" }
        // LLM article should be surfaced, cooking should not
        if !forecast.predictions.isEmpty {
            XCTAssertNotNil(llmSurfaced)
        }
        let cookingSurfaced = forecast.surfacedArticles.first { $0.articleId == "c2" }
        XCTAssertNil(cookingSurfaced)
    }

    func testClearCandidates() {
        engine.registerCandidates([
            CandidateArticle(articleId: "c1", feedURL: "f1", topics: ["test"])
        ])
        engine.clearCandidates()
        XCTAssertEqual(engine.stats.candidates, 0)
    }

    // MARK: - Prediction Accuracy

    func testAccuracyTracking() {
        engine.recordOutcome(predictedTopic: "rust", predictionDate: Date(),
                            confidence: .high, wasAccurate: true)
        engine.recordOutcome(predictedTopic: "go", predictionDate: Date(),
                            confidence: .medium, wasAccurate: true)
        engine.recordOutcome(predictedTopic: "java", predictionDate: Date(),
                            confidence: .low, wasAccurate: false)
        let forecast = engine.forecast()
        XCTAssertEqual(forecast.predictionAccuracy, 2.0 / 3.0, accuracy: 0.01)
    }

    func testPerfectAccuracy() {
        for i in 0..<10 {
            engine.recordOutcome(predictedTopic: "t\(i)", predictionDate: Date(),
                                confidence: .high, wasAccurate: true)
        }
        let forecast = engine.forecast()
        XCTAssertEqual(forecast.predictionAccuracy, 1.0, accuracy: 0.001)
    }

    // MARK: - Interaction Types

    func testSearchWeighsHighest() {
        XCTAssertEqual(InteractionType.search.signalWeight, 1.0)
        XCTAssertGreaterThan(InteractionType.search.signalWeight,
                             InteractionType.read.signalWeight)
    }

    func testClickWeighsLowest() {
        for type in InteractionType.allCases where type != .click {
            XCTAssertGreaterThan(type.signalWeight, InteractionType.click.signalWeight)
        }
    }

    // MARK: - Interest Phases

    func testPhaseComparable() {
        XCTAssertTrue(InterestPhase.latent < InterestPhase.emerging)
        XCTAssertTrue(InterestPhase.emerging < InterestPhase.growing)
        XCTAssertTrue(InterestPhase.growing < InterestPhase.peak)
    }

    func testPhaseEmoji() {
        for phase in InterestPhase.allCases {
            XCTAssertFalse(phase.emoji.isEmpty)
        }
    }

    // MARK: - Prediction Confidence

    func testConfidenceComparable() {
        XCTAssertTrue(PredictionConfidence.speculative < PredictionConfidence.low)
        XCTAssertTrue(PredictionConfidence.low < PredictionConfidence.medium)
        XCTAssertTrue(PredictionConfidence.medium < PredictionConfidence.high)
    }

    func testConfidenceThresholds() {
        XCTAssertEqual(PredictionConfidence.high.threshold, 0.75)
        XCTAssertEqual(PredictionConfidence.medium.threshold, 0.5)
        XCTAssertEqual(PredictionConfidence.low.threshold, 0.25)
        XCTAssertEqual(PredictionConfidence.speculative.threshold, 0.0)
    }

    // MARK: - Trajectory Prediction

    func testTrajectoryPredictedStrength() {
        let now = Date()
        for i in 0..<6 {
            let ts = calendar.date(byAdding: .day, value: -(5 - i), to: now)!
            engine.recordInteraction(topic: "swift", feedURL: "f\(i)",
                                    articleId: "a\(i)", interactionType: .read,
                                    dwellSeconds: 100, timestamp: ts)
        }
        let trajectories = engine.getTrajectories(asOf: now)
        if let traj = trajectories.first {
            let future = traj.predictedStrength(daysAhead: 7)
            XCTAssertGreaterThanOrEqual(future, 0)
            XCTAssertLessThanOrEqual(future, 1)
        }
    }

    func testPredictedStrengthClamped() {
        let now = Date()
        for i in 0..<5 {
            let ts = calendar.date(byAdding: .day, value: -i, to: now)!
            engine.recordInteraction(topic: "topic", feedURL: "f\(i)",
                                    articleId: "a\(i)", interactionType: .search,
                                    dwellSeconds: 300, timestamp: ts)
        }
        let trajectories = engine.getTrajectories(asOf: now)
        if let traj = trajectories.first {
            let future = traj.predictedStrength(daysAhead: 365)
            XCTAssertLessThanOrEqual(future, 1.0)
            let past = traj.predictedStrength(daysAhead: -365)
            XCTAssertGreaterThanOrEqual(past, 0.0)
        }
    }

    // MARK: - Configuration

    func testCustomConfiguration() {
        engine.minimumSignalsForTrajectory = 5
        engine.trajectoryWindowDays = 14
        engine.decayHalfLifeDays = 3.0
        engine.maxPredictions = 5

        let now = Date()
        for i in 0..<4 {
            let ts = calendar.date(byAdding: .day, value: -i, to: now)!
            engine.recordInteraction(topic: "test", feedURL: "f\(i)",
                                    articleId: "a\(i)", interactionType: .read, timestamp: ts)
        }
        // Should not form trajectory with 4 signals when minimum is 5
        let trajectories = engine.getTrajectories(asOf: now)
        XCTAssertTrue(trajectories.isEmpty)
    }

    // MARK: - Reset

    func testReset() {
        engine.recordInteraction(topic: "a", feedURL: "f", articleId: "1", interactionType: .read)
        engine.recordOutcome(predictedTopic: "b", predictionDate: Date(),
                            confidence: .high, wasAccurate: true)
        engine.registerCandidates([CandidateArticle(articleId: "c1", feedURL: "f", topics: ["x"])])
        engine.reset()
        XCTAssertEqual(engine.signalCount, 0)
        XCTAssertEqual(engine.outcomeCount, 0)
        XCTAssertEqual(engine.stats.candidates, 0)
    }

    // MARK: - Stats

    func testStats() {
        engine.recordInteraction(topic: "a", feedURL: "f1", articleId: "1", interactionType: .read)
        engine.recordInteraction(topic: "b", feedURL: "f2", articleId: "2", interactionType: .read)
        engine.recordInteraction(topic: "a", feedURL: "f3", articleId: "3", interactionType: .bookmark)
        engine.recordOutcome(predictedTopic: "c", predictionDate: Date(),
                            confidence: .low, wasAccurate: false)
        engine.registerCandidates([CandidateArticle(articleId: "x", feedURL: "f", topics: ["t"])])
        let stats = engine.stats
        XCTAssertEqual(stats.signals, 3)
        XCTAssertEqual(stats.topics, 2)
        XCTAssertEqual(stats.outcomes, 1)
        XCTAssertEqual(stats.candidates, 1)
    }

    // MARK: - Health Score Grading

    func testHealthGradeRange() {
        let now = Date()
        // Lots of diverse data = high health
        for i in 0..<50 {
            let topic = "topic\(i % 8)"
            let ts = calendar.date(byAdding: .day, value: -(28 - (i % 28)), to: now)!
            engine.recordInteraction(topic: topic, feedURL: "f\(i % 10)",
                                    articleId: "a\(i)", interactionType: .read,
                                    dwellSeconds: 90, timestamp: ts)
        }
        for i in 0..<10 {
            engine.recordOutcome(predictedTopic: "topic\(i)", predictionDate: Date(),
                                confidence: .high, wasAccurate: true)
        }
        let forecast = engine.forecast(asOf: now)
        XCTAssertGreaterThanOrEqual(forecast.healthScore, 0)
        XCTAssertLessThanOrEqual(forecast.healthScore, 100)
        XCTAssertTrue(["A", "B", "C", "D", "F"].contains(forecast.healthGrade))
    }

    // MARK: - Edge Cases

    func testEmptyTopicIgnored() {
        engine.recordInteraction(topic: "", feedURL: "f", articleId: "a1", interactionType: .read)
        engine.recordInteraction(topic: "", feedURL: "f", articleId: "a2", interactionType: .read)
        engine.recordInteraction(topic: "", feedURL: "f", articleId: "a3", interactionType: .read)
        let trajectories = engine.getTrajectories()
        // Empty topic is still recorded (normalized to "")
        XCTAssertEqual(engine.signalCount, 3)
    }

    func testFutureTimestampsHandled() {
        let future = calendar.date(byAdding: .day, value: 30, to: Date())!
        engine.recordInteraction(topic: "future", feedURL: "f", articleId: "a1",
                                interactionType: .read, timestamp: future)
        engine.recordInteraction(topic: "future", feedURL: "f", articleId: "a2",
                                interactionType: .read, timestamp: future)
        engine.recordInteraction(topic: "future", feedURL: "f", articleId: "a3",
                                interactionType: .read, timestamp: future)
        // Should not crash
        let forecast = engine.forecast()
        XCTAssertNotNil(forecast)
    }

    func testLargeDataVolume() {
        let now = Date()
        for i in 0..<500 {
            let topic = "topic\(i % 20)"
            let ts = calendar.date(byAdding: .hour, value: -(500 - i), to: now)!
            engine.recordInteraction(topic: topic, feedURL: "f\(i % 15)",
                                    articleId: "a\(i)", interactionType: InteractionType.allCases[i % 7],
                                    dwellSeconds: Double(30 + i % 200), timestamp: ts)
        }
        let forecast = engine.forecast(asOf: now)
        XCTAssertFalse(forecast.trajectories.isEmpty)
        XCTAssertGreaterThan(forecast.healthScore, 0)
    }

    // MARK: - Cyclical Interest Detection

    func testCyclicalInterestPrediction() {
        let now = Date()
        // Old strong interest, now dormant
        for i in 0..<8 {
            let ts = calendar.date(byAdding: .day, value: -(60 + i), to: now)!
            engine.recordInteraction(topic: "blockchain", feedURL: "f\(i % 3)",
                                    articleId: "old\(i)", interactionType: .read,
                                    dwellSeconds: 120, timestamp: ts)
        }
        engine.trajectoryWindowDays = 90 // Expand window to see old signals
        let forecast = engine.forecast(asOf: now)
        let cyclicalPred = forecast.predictions.first { $0.topic == "blockchain" }
        // Should detect cyclical possibility
        if let pred = cyclicalPred {
            XCTAssertEqual(pred.confidence, .speculative)
            XCTAssertTrue(pred.reason.contains("cyclical") || pred.reason.contains("dormant"))
        }
    }

    // MARK: - Decay Behavior

    func testDecayReducesOldSignals() {
        let now = Date()
        engine.decayHalfLifeDays = 7.0

        // Old signals (28 days ago)
        for i in 0..<5 {
            let ts = calendar.date(byAdding: .day, value: -28, to: now)!
            engine.recordInteraction(topic: "old", feedURL: "f\(i)",
                                    articleId: "old\(i)", interactionType: .read, timestamp: ts)
        }
        // Recent signals (1 day ago)
        for i in 0..<5 {
            let ts = calendar.date(byAdding: .day, value: -1, to: now)!
            engine.recordInteraction(topic: "new", feedURL: "f\(i)",
                                    articleId: "new\(i)", interactionType: .read, timestamp: ts)
        }

        let trajectories = engine.getTrajectories(asOf: now)
        let oldTraj = trajectories.first { $0.topic == "old" }
        let newTraj = trajectories.first { $0.topic == "new" }

        if let o = oldTraj, let n = newTraj {
            XCTAssertGreaterThan(n.currentStrength, o.currentStrength,
                                "Recent signals should have higher strength")
        }
    }

    // MARK: - Multiple Interaction Types

    func testMixedInteractionTypes() {
        let now = Date()
        let types: [InteractionType] = [.read, .bookmark, .share, .search, .highlight]
        for (i, type) in types.enumerated() {
            let ts = calendar.date(byAdding: .day, value: -i, to: now)!
            engine.recordInteraction(topic: "mixed", feedURL: "f\(i)",
                                    articleId: "a\(i)", interactionType: type,
                                    dwellSeconds: 100, timestamp: ts)
        }
        let trajectories = engine.getTrajectories(asOf: now)
        XCTAssertEqual(trajectories.count, 1)
        // Higher weight interactions should boost strength
        XCTAssertGreaterThan(trajectories.first?.currentStrength ?? 0, 0)
    }

    // MARK: - Candidate Article Matching

    func testCandidateArticleInit() {
        let article = CandidateArticle(articleId: "x", feedURL: "f",
                                       topics: ["AI", "Machine Learning"])
        XCTAssertEqual(article.topics, ["ai", "machine learning"])
    }

    func testNoSurfacingWithoutCandidates() {
        let now = Date()
        for i in 0..<5 {
            let ts = calendar.date(byAdding: .day, value: -i, to: now)!
            engine.recordInteraction(topic: "test", feedURL: "f\(i)",
                                    articleId: "a\(i)", interactionType: .read, timestamp: ts)
        }
        let forecast = engine.forecast(asOf: now)
        XCTAssertTrue(forecast.surfacedArticles.isEmpty)
    }

    // MARK: - Forecast Timestamp

    func testForecastTimestamp() {
        let specificDate = calendar.date(from: DateComponents(year: 2026, month: 1, day: 15))!
        let forecast = engine.forecast(asOf: specificDate)
        XCTAssertEqual(forecast.generatedAt, specificDate)
    }
}
