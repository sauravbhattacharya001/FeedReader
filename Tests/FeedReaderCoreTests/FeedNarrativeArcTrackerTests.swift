//
//  FeedNarrativeArcTrackerTests.swift
//  FeedReaderCoreTests
//
//  Tests for the FeedNarrativeArcTracker engine.
//

import XCTest
@testable import FeedReaderCore

final class FeedNarrativeArcTrackerTests: XCTestCase {

    private func makeDate(daysAgo: Int) -> Date {
        Calendar.current.date(byAdding: .day, value: -daysAgo, to: Date())!
    }

    private func makeArticle(id: String, title: String, keywords: [String],
                              entities: [String], source: String = "TechCrunch",
                              daysAgo: Int = 0, sentiment: Double = 0.0) -> NarrativeArticle {
        NarrativeArticle(id: id, title: title, keywords: keywords, entities: entities,
                         feedSource: source, publishDate: makeDate(daysAgo: daysAgo),
                         sentiment: sentiment)
    }

    // MARK: - Initialization

    func testInitializationDefaults() {
        let tracker = FeedNarrativeArcTracker()
        XCTAssertEqual(tracker.storyCount, 0)
        XCTAssertEqual(tracker.articleCount, 0)
    }

    func testInitializationCustomParams() {
        let tracker = FeedNarrativeArcTracker(similarityThreshold: 0.5, dormantDays: 7)
        XCTAssertEqual(tracker.storyCount, 0)
    }

    // MARK: - Ingestion

    func testIngestSingleArticleCreatesStory() {
        let tracker = FeedNarrativeArcTracker()
        let article = makeArticle(id: "1", title: "AI Advances",
                                   keywords: ["ai", "machine learning"],
                                   entities: ["openai", "google"])
        let storyId = tracker.ingest(article)
        XCTAssertEqual(tracker.storyCount, 1)
        XCTAssertEqual(tracker.articleCount, 1)
        XCTAssertTrue(storyId.hasPrefix("story_"))
    }

    func testIngestRelatedArticlesClusterTogether() {
        let tracker = FeedNarrativeArcTracker()
        let a1 = makeArticle(id: "1", title: "AI Policy",
                              keywords: ["ai", "regulation", "policy"],
                              entities: ["openai", "congress"], daysAgo: 5)
        let a2 = makeArticle(id: "2", title: "AI Regulation Update",
                              keywords: ["ai", "regulation", "safety"],
                              entities: ["openai", "congress"], daysAgo: 3)

        let id1 = tracker.ingest(a1)
        let id2 = tracker.ingest(a2)
        XCTAssertEqual(id1, id2, "Related articles should cluster into same story")
        XCTAssertEqual(tracker.storyCount, 1)
    }

    func testIngestUnrelatedArticlesCreateSeparateStories() {
        let tracker = FeedNarrativeArcTracker()
        let a1 = makeArticle(id: "1", title: "AI News",
                              keywords: ["ai", "technology"],
                              entities: ["openai"])
        let a2 = makeArticle(id: "2", title: "Sports Update",
                              keywords: ["football", "championship"],
                              entities: ["nfl", "kansas city"])

        let id1 = tracker.ingest(a1)
        let id2 = tracker.ingest(a2)
        XCTAssertNotEqual(id1, id2, "Unrelated articles should create separate stories")
        XCTAssertEqual(tracker.storyCount, 2)
    }

    func testIngestBatch() {
        let tracker = FeedNarrativeArcTracker()
        let articles = [
            makeArticle(id: "1", title: "Story A", keywords: ["topic1"], entities: ["entity1"]),
            makeArticle(id: "2", title: "Story B", keywords: ["topic2"], entities: ["entity2"]),
        ]
        tracker.ingestBatch(articles)
        XCTAssertEqual(tracker.articleCount, 2)
    }

    // MARK: - Following

    func testFollowAndUnfollowStory() {
        let tracker = FeedNarrativeArcTracker()
        let article = makeArticle(id: "1", title: "Test", keywords: ["test"], entities: ["test"])
        let storyId = tracker.ingest(article)

        tracker.followStory(storyId)
        XCTAssertEqual(tracker.getFollowedStories().count, 1)

        tracker.unfollowStory(storyId)
        XCTAssertEqual(tracker.getFollowedStories().count, 0)
    }

    func testFollowNonexistentStoryNoOp() {
        let tracker = FeedNarrativeArcTracker()
        tracker.followStory("nonexistent")
        XCTAssertEqual(tracker.getFollowedStories().count, 0)
    }

    // MARK: - Phase Classification

    func testNewStoriesAreEmerging() {
        let tracker = FeedNarrativeArcTracker()
        let article = makeArticle(id: "1", title: "New Topic",
                                   keywords: ["new"], entities: ["entity"])
        tracker.ingest(article)
        let stories = tracker.getStories()
        XCTAssertEqual(stories.first?.phase, .emerging)
    }

    func testGetStoriesByPhase() {
        let tracker = FeedNarrativeArcTracker()
        let article = makeArticle(id: "1", title: "Test",
                                   keywords: ["test"], entities: ["entity"])
        tracker.ingest(article)
        let emerging = tracker.getStories(inPhase: .emerging)
        XCTAssertEqual(emerging.count, 1)
        let climax = tracker.getStories(inPhase: .climax)
        XCTAssertEqual(climax.count, 0)
    }

    // MARK: - Momentum

    func testMomentumIncreasesWithMoreArticles() {
        let tracker = FeedNarrativeArcTracker()
        let a1 = makeArticle(id: "1", title: "Topic",
                              keywords: ["ai", "safety"], entities: ["openai"],
                              source: "Source1", daysAgo: 5)
        tracker.ingest(a1)
        let m1 = tracker.getStories().first!.momentum

        let a2 = makeArticle(id: "2", title: "Topic Update",
                              keywords: ["ai", "safety"], entities: ["openai"],
                              source: "Source2", daysAgo: 3)
        tracker.ingest(a2)
        let m2 = tracker.getStories().first!.momentum

        XCTAssertGreaterThan(m2, m1, "Momentum should increase with more articles")
    }

    func testSourceDiversityBoostsMomentum() {
        let tracker = FeedNarrativeArcTracker()
        for i in 0..<5 {
            let a = makeArticle(id: "\(i)", title: "AI Story",
                                keywords: ["ai", "regulation"],
                                entities: ["openai", "congress"],
                                source: "Source\(i)", daysAgo: 5 - i)
            tracker.ingest(a)
        }
        let story = tracker.getStories().first!
        XCTAssertEqual(story.sourceCount, 5)
        XCTAssertGreaterThan(story.momentum, 30.0)
    }

    // MARK: - Analysis

    func testAnalyzeProducesReport() {
        let tracker = FeedNarrativeArcTracker()
        for i in 0..<5 {
            let a = makeArticle(id: "\(i)", title: "AI News \(i)",
                                keywords: ["ai", "technology"],
                                entities: ["openai", "google"],
                                source: "Source\(i)", daysAgo: 10 - i)
            tracker.ingest(a)
        }
        let report = tracker.analyze()
        XCTAssertFalse(report.activeStories.isEmpty)
        XCTAssertFalse(report.recentTurningPoints.isEmpty)
        XCTAssertGreaterThanOrEqual(report.healthScore, 0.0)
        XCTAssertLessThanOrEqual(report.healthScore, 100.0)
    }

    func testAnalyzeDetectsConvergences() {
        let tracker = FeedNarrativeArcTracker(similarityThreshold: 0.6)
        // Story A
        tracker.ingest(makeArticle(id: "a1", title: "AI Policy",
                                    keywords: ["ai", "regulation"],
                                    entities: ["openai", "congress"], daysAgo: 5))
        // Story B - shares "openai" entity
        tracker.ingest(makeArticle(id: "b1", title: "OpenAI Product",
                                    keywords: ["product", "launch"],
                                    entities: ["openai", "startup"], daysAgo: 3))

        let report = tracker.analyze()
        // If convergence detected, it should have shared entities
        if !report.convergences.isEmpty {
            XCTAssertTrue(report.convergences.first!.sharedEntities.contains("openai"))
        }
    }

    func testAnalyzeGeneratesForecasts() {
        let tracker = FeedNarrativeArcTracker()
        // Build story with enough articles for forecast
        for i in 0..<6 {
            tracker.ingest(makeArticle(id: "\(i)", title: "Big Story \(i)",
                                       keywords: ["ai", "safety", "regulation"],
                                       entities: ["openai", "google"],
                                       source: "Source\(i % 3)", daysAgo: 10 - i))
        }
        let report = tracker.analyze()
        XCTAssertFalse(report.forecasts.isEmpty, "Should produce forecasts for active stories")
        if let forecast = report.forecasts.first {
            XCTAssertGreaterThan(forecast.confidence, 0.0)
            XCTAssertLessThanOrEqual(forecast.confidence, 1.0)
            XCTAssertFalse(forecast.reasoning.isEmpty)
        }
    }

    func testAnalyzeGeneratesInsights() {
        let tracker = FeedNarrativeArcTracker()
        for i in 0..<5 {
            tracker.ingest(makeArticle(id: "\(i)", title: "Topic \(i)",
                                       keywords: ["tech", "innovation"],
                                       entities: ["company", "market"],
                                       source: "Source\(i)", daysAgo: 3 - min(i, 3)))
        }
        let report = tracker.analyze()
        XCTAssertFalse(report.insights.isEmpty)
    }

    // MARK: - Sentiment Tracking

    func testSentimentTrajectoryCalculation() {
        let tracker = FeedNarrativeArcTracker()
        // Start negative, trend positive
        tracker.ingest(makeArticle(id: "1", title: "Bad News",
                                    keywords: ["crisis"], entities: ["company"],
                                    daysAgo: 5, sentiment: -0.8))
        tracker.ingest(makeArticle(id: "2", title: "Improving",
                                    keywords: ["crisis"], entities: ["company"],
                                    daysAgo: 3, sentiment: -0.2))
        tracker.ingest(makeArticle(id: "3", title: "Recovery",
                                    keywords: ["crisis"], entities: ["company"],
                                    daysAgo: 1, sentiment: 0.5))
        tracker.ingest(makeArticle(id: "4", title: "Thriving",
                                    keywords: ["crisis"], entities: ["company"],
                                    daysAgo: 0, sentiment: 0.8))

        let story = tracker.getStories().first!
        XCTAssertGreaterThan(story.sentimentTrajectory, 0.0,
                             "Sentiment trajectory should be positive")
    }

    func testSentimentClamping() {
        let article = NarrativeArticle(id: "1", title: "Test",
                                        keywords: ["test"], entities: ["test"],
                                        feedSource: "src", publishDate: Date(),
                                        sentiment: 5.0)
        XCTAssertEqual(article.sentiment, 1.0, "Sentiment should be clamped to 1.0")

        let article2 = NarrativeArticle(id: "2", title: "Test2",
                                         keywords: ["test"], entities: ["test"],
                                         feedSource: "src", publishDate: Date(),
                                         sentiment: -3.0)
        XCTAssertEqual(article2.sentiment, -1.0, "Sentiment should be clamped to -1.0")
    }

    // MARK: - Health Score

    func testHealthScoreZeroWhenEmpty() {
        let tracker = FeedNarrativeArcTracker()
        let report = tracker.analyze()
        XCTAssertEqual(report.healthScore, 0.0)
    }

    func testHealthScoreInRange() {
        let tracker = FeedNarrativeArcTracker()
        for i in 0..<10 {
            tracker.ingest(makeArticle(id: "\(i)", title: "Story \(i)",
                                       keywords: ["tech", "ai"],
                                       entities: ["openai", "google"],
                                       source: "Source\(i)", daysAgo: 5 - min(i, 5)))
        }
        let report = tracker.analyze()
        XCTAssertGreaterThanOrEqual(report.healthScore, 0.0)
        XCTAssertLessThanOrEqual(report.healthScore, 100.0)
    }

    // MARK: - Reset

    func testReset() {
        let tracker = FeedNarrativeArcTracker()
        tracker.ingest(makeArticle(id: "1", title: "Test",
                                    keywords: ["test"], entities: ["entity"]))
        XCTAssertEqual(tracker.storyCount, 1)
        tracker.reset()
        XCTAssertEqual(tracker.storyCount, 0)
        XCTAssertEqual(tracker.articleCount, 0)
    }

    // MARK: - Narrative Phase Enum

    func testNarrativePhaseOrdering() {
        XCTAssertTrue(NarrativePhase.emerging < NarrativePhase.rising)
        XCTAssertTrue(NarrativePhase.rising < NarrativePhase.climax)
        XCTAssertTrue(NarrativePhase.climax < NarrativePhase.falling)
        XCTAssertTrue(NarrativePhase.falling < NarrativePhase.resolution)
        XCTAssertTrue(NarrativePhase.resolution < NarrativePhase.dormant)
    }

    func testNarrativePhaseAllCases() {
        XCTAssertEqual(NarrativePhase.allCases.count, 6)
    }

    // MARK: - Turning Point Types

    func testTurningPointTypeAllCases() {
        XCTAssertEqual(TurningPointType.allCases.count, 8)
    }

    // MARK: - Edge Cases

    func testEmptyKeywordsAndEntities() {
        let tracker = FeedNarrativeArcTracker()
        let a = makeArticle(id: "1", title: "Empty", keywords: [], entities: [])
        let storyId = tracker.ingest(a)
        XCTAssertEqual(tracker.storyCount, 1)
        XCTAssertTrue(storyId.hasPrefix("story_"))
    }

    func testNegativeWordCountClamped() {
        let article = NarrativeArticle(id: "1", title: "Test",
                                        keywords: ["test"], entities: ["test"],
                                        feedSource: "src", publishDate: Date(),
                                        sentiment: 0.0, wordCount: -100)
        XCTAssertEqual(article.wordCount, 0)
    }

    func testKeywordsLowercased() {
        let article = NarrativeArticle(id: "1", title: "Test",
                                        keywords: ["AI", "Machine Learning"],
                                        entities: ["OpenAI"],
                                        feedSource: "src", publishDate: Date())
        XCTAssertEqual(article.keywords, ["ai", "machine learning"])
        XCTAssertEqual(article.entities, ["openai"])
    }

    // MARK: - Followed Story Updates in Report

    func testFollowedStoriesAppearInReport() {
        let tracker = FeedNarrativeArcTracker()
        let storyId = tracker.ingest(makeArticle(id: "1", title: "Followed",
                                                  keywords: ["test"],
                                                  entities: ["entity"]))
        tracker.followStory(storyId)
        let report = tracker.analyze()
        XCTAssertEqual(report.followedStoryUpdates.count, 1)
        XCTAssertTrue(report.followedStoryUpdates.first!.isFollowed)
    }

    // MARK: - Thread Properties

    func testNarrativeThreadProperties() {
        let tracker = FeedNarrativeArcTracker()
        tracker.ingest(makeArticle(id: "1", title: "Topic A",
                                    keywords: ["alpha", "beta"],
                                    entities: ["org1", "org2"],
                                    source: "Source1", daysAgo: 3))
        tracker.ingest(makeArticle(id: "2", title: "Topic A cont",
                                    keywords: ["alpha", "beta"],
                                    entities: ["org1", "org2"],
                                    source: "Source2", daysAgo: 1))

        let thread = tracker.getStories().first!
        XCTAssertEqual(thread.articleIds.count, 2)
        XCTAssertEqual(thread.sourceCount, 2)
        XCTAssertFalse(thread.label.isEmpty)
        XCTAssertFalse(thread.id.isEmpty)
    }
}
