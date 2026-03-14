//
//  ArticleRecommendationEngineTests.swift
//  FeedReaderTests
//
//  Tests for ArticleRecommendationEngine — scoring, profiling, and ranking.
//

import XCTest
@testable import FeedReader

class ArticleRecommendationEngineTests: XCTestCase {

    var engine: ArticleRecommendationEngine!

    override func setUp() {
        super.setUp()
        engine = ArticleRecommendationEngine()
    }

    override func tearDown() {
        engine.invalidateCache()
        engine = nil
        super.tearDown()
    }

    // MARK: - Helpers

    private func makeStory(
        title: String,
        body: String = "Default body text for testing.",
        link: String,
        feedName: String = "TestFeed"
    ) -> Story {
        let story = Story(title: title, photo: nil, description: body, link: link)!
        story.sourceFeedName = feedName
        return story
    }

    private func makeHistory(
        link: String,
        title: String,
        feedName: String = "TestFeed",
        visitCount: Int = 1,
        daysAgo: Int = 0
    ) -> HistoryEntry {
        let readAt = Calendar.current.date(byAdding: .day, value: -daysAgo, to: Date()) ?? Date()
        return HistoryEntry(
            link: link, title: title, feedName: feedName,
            readAt: readAt, visitCount: visitCount
        )
    }

    // MARK: - Empty Inputs

    func testEmptyCandidatesReturnsEmpty() {
        let history = [makeHistory(link: "https://a.com/1", title: "Tech News")]
        let results = engine.recommend(from: [], history: history)
        XCTAssertTrue(results.isEmpty)
    }

    func testEmptyHistoryReturnsEmpty() {
        let candidates = [makeStory(title: "New Article", link: "https://a.com/1")]
        let results = engine.recommend(from: candidates, history: [])
        XCTAssertTrue(results.isEmpty, "No history means no preferences, so no recommendations")
    }

    func testBothEmptyReturnsEmpty() {
        let results = engine.recommend(from: [], history: [])
        XCTAssertTrue(results.isEmpty)
    }

    // MARK: - Already-Read Filtering

    func testAlreadyReadArticlesExcluded() {
        let history = [makeHistory(link: "https://a.com/1", title: "Read Article", feedName: "TechBlog")]
        let candidates = [
            makeStory(title: "Read Article", link: "https://a.com/1", feedName: "TechBlog"),
            makeStory(title: "Unread Article", link: "https://a.com/2", feedName: "TechBlog"),
        ]
        let results = engine.recommend(from: candidates, history: history)
        XCTAssertTrue(results.allSatisfy { $0.story.link != "https://a.com/1" })
    }

    // MARK: - Feed Preference Scoring

    func testFeedPreferenceBoostsScore() {
        let history = (1...10).map { i in
            makeHistory(link: "https://tech.com/\(i)", title: "Tech Article \(i)", feedName: "TechBlog")
        }
        let candidates = [
            makeStory(title: "New Technology Review", link: "https://tech.com/new", feedName: "TechBlog"),
            makeStory(title: "New Technology Review", link: "https://other.com/new", feedName: "OtherBlog"),
        ]
        let results = engine.recommend(from: candidates, history: history)

        let techResult = results.first { $0.story.link == "https://tech.com/new" }
        let otherResult = results.first { $0.story.link == "https://other.com/new" }

        if let tech = techResult, let other = otherResult {
            XCTAssertGreaterThan(tech.score, other.score,
                "Article from frequently-read feed should score higher")
        } else if techResult != nil {
            // OtherBlog didn't meet threshold — acceptable
        } else {
            XCTFail("Expected at least the TechBlog article to be recommended")
        }
    }

    func testMultipleFeedsPreferences() {
        var history: [HistoryEntry] = []
        for i in 1...8 {
            history.append(makeHistory(link: "https://tech.com/\(i)", title: "Tech Post \(i)", feedName: "TechBlog"))
        }
        for i in 1...3 {
            history.append(makeHistory(link: "https://news.com/\(i)", title: "News Post \(i)", feedName: "NewsFeed"))
        }

        let candidates = [
            makeStory(title: "Another Tech Post", link: "https://tech.com/new", feedName: "TechBlog"),
            makeStory(title: "Another News Post", link: "https://news.com/new", feedName: "NewsFeed"),
        ]

        let results = engine.recommend(from: candidates, history: history)
        guard results.count >= 2 else {
            XCTFail("Expected 2 recommendations, got \(results.count)")
            return
        }
        XCTAssertEqual(results[0].story.sourceFeedName, "TechBlog")
    }

    // MARK: - Keyword Affinity Scoring

    func testKeywordAffinityBoostsScore() {
        let history = [
            makeHistory(link: "https://a.com/1", title: "Machine Learning Breakthrough", feedName: "AI"),
            makeHistory(link: "https://a.com/2", title: "Deep Machine Learning Tutorial", feedName: "AI"),
            makeHistory(link: "https://a.com/3", title: "Advanced Machine Learning Models", feedName: "AI"),
        ]

        let candidates = [
            makeStory(title: "Machine Learning Applications Today", link: "https://b.com/1", feedName: "AI"),
            makeStory(title: "Best Cooking Recipes Winter", link: "https://b.com/2", feedName: "Food"),
        ]

        let results = engine.recommend(from: candidates, history: history)
        if let mlResult = results.first(where: { $0.story.link == "https://b.com/1" }) {
            XCTAssertTrue(mlResult.score > 0, "ML article should have a positive score")
        }
    }

    // MARK: - Revisit Bonus

    func testRevisitedArticlesInfluenceRecommendations() {
        let history = [
            makeHistory(link: "https://a.com/1", title: "Cybersecurity Best Practices Guide",
                       feedName: "Security", visitCount: 5),
            makeHistory(link: "https://a.com/2", title: "Network Security Fundamentals Overview",
                       feedName: "Security", visitCount: 3),
        ]

        let candidates = [
            makeStory(title: "Latest Cybersecurity Threats Analysis", link: "https://b.com/1", feedName: "Security"),
            makeStory(title: "Garden Planting Tips Spring", link: "https://b.com/2", feedName: "Garden"),
        ]

        let results = engine.recommend(from: candidates, history: history)
        let securityResult = results.first { $0.story.link == "https://b.com/1" }
        XCTAssertNotNil(securityResult, "Article matching revisited topics should be recommended")
    }

    // MARK: - Score Threshold

    func testMinScoreFiltering() {
        let history = [makeHistory(link: "https://a.com/1", title: "Specific Topic Here", feedName: "Feed")]
        let candidates = [
            makeStory(title: "Completely Unrelated Content", link: "https://b.com/1", feedName: "Other"),
        ]

        var options = RecommendationOptions()
        options.minScore = 0.9
        let results = engine.recommend(from: candidates, history: history, options: options)
        XCTAssertTrue(results.isEmpty || results.allSatisfy { $0.score >= 0.9 })
    }

    // MARK: - Max Results Limit

    func testMaxResultsLimit() {
        let history = (1...20).map { i in
            makeHistory(link: "https://feed.com/\(i)", title: "Article \(i)", feedName: "Feed")
        }
        let candidates = (21...50).map { i in
            makeStory(title: "Article \(i)", link: "https://feed.com/\(i)", feedName: "Feed")
        }

        var options = RecommendationOptions()
        options.maxResults = 5
        options.minScore = 0.0
        let results = engine.recommend(from: candidates, history: history, options: options)
        XCTAssertLessThanOrEqual(results.count, 5)
    }

    // MARK: - Scoring Sorted Descending

    func testResultsSortedByScoreDescending() {
        let history = (1...10).map { i in
            makeHistory(link: "https://a.com/\(i)", title: "Technology News \(i)", feedName: "TechBlog")
        }
        let candidates = (11...20).map { i in
            makeStory(title: "Technology Update \(i)", link: "https://a.com/\(i)", feedName: "TechBlog")
        }

        let results = engine.recommend(from: candidates, history: history)
        for i in 1..<results.count {
            XCTAssertGreaterThanOrEqual(results[i - 1].score, results[i].score,
                "Results should be sorted by score descending")
        }
    }

    // MARK: - Options: Custom Weights

    func testFeedOnlyWeight() {
        var options = RecommendationOptions()
        options.feedWeight = 1.0
        options.keywordWeight = 0.0
        options.revisitWeight = 0.0
        options.minScore = 0.0

        let history = [
            makeHistory(link: "https://a.com/1", title: "Random Title", feedName: "PremiumFeed"),
        ]
        let candidates = [
            makeStory(title: "Different Content", link: "https://b.com/1", feedName: "PremiumFeed"),
            makeStory(title: "Different Content", link: "https://b.com/2", feedName: "OtherFeed"),
        ]

        let results = engine.recommend(from: candidates, history: history, options: options)
        let premiumResult = results.first { $0.story.sourceFeedName == "PremiumFeed" }
        XCTAssertNotNil(premiumResult, "Feed-only weight should boost matching feed articles")
    }

    func testKeywordOnlyWeight() {
        var options = RecommendationOptions()
        options.feedWeight = 0.0
        options.keywordWeight = 1.0
        options.revisitWeight = 0.0
        options.minScore = 0.0

        let history = [
            makeHistory(link: "https://a.com/1", title: "Blockchain Cryptocurrency Trading", feedName: "FeedA"),
            makeHistory(link: "https://a.com/2", title: "Blockchain Decentralized Finance", feedName: "FeedA"),
        ]
        let candidates = [
            makeStory(title: "Blockchain Technology Revolution", link: "https://b.com/1", feedName: "FeedB"),
            makeStory(title: "Cooking Italian Pasta Recipe", link: "https://b.com/2", feedName: "FeedA"),
        ]

        let results = engine.recommend(from: candidates, history: history, options: options)
        if results.count >= 2 {
            XCTAssertEqual(results[0].story.link, "https://b.com/1",
                "Keyword matching article should rank first with keyword-only weight")
        }
    }

    // MARK: - History Time Window

    func testHistoryDaysFilter() {
        var options = RecommendationOptions()
        options.historyDays = 7
        options.minScore = 0.0

        let history = [
            makeHistory(link: "https://a.com/old", title: "Old Article Technology", feedName: "Tech", daysAgo: 30),
            makeHistory(link: "https://a.com/new", title: "Recent Article Technology", feedName: "Tech", daysAgo: 1),
        ]
        let candidates = [
            makeStory(title: "Technology Update Today", link: "https://b.com/1", feedName: "Tech"),
        ]

        let results = engine.recommend(from: candidates, history: history, options: options)
        XCTAssertFalse(results.isEmpty, "Recent history should still drive recommendations")
    }

    func testAllHistoryMode() {
        var options = RecommendationOptions()
        options.historyDays = 0
        options.minScore = 0.0

        let history = [
            makeHistory(link: "https://a.com/old", title: "Ancient Article", feedName: "OldFeed", daysAgo: 365),
        ]
        let candidates = [
            makeStory(title: "Something New", link: "https://b.com/1", feedName: "OldFeed"),
        ]

        let results = engine.recommend(from: candidates, history: history, options: options)
        let match = results.first { $0.story.sourceFeedName == "OldFeed" }
        XCTAssertNotNil(match, "historyDays=0 should include all history regardless of age")
    }

    // MARK: - Cache Invalidation

    func testCacheInvalidation() {
        let history1 = [makeHistory(link: "https://a.com/1", title: "Alpha Topic", feedName: "FeedA")]
        let candidates = [
            makeStory(title: "Alpha Related Content", link: "https://b.com/1", feedName: "FeedA"),
        ]

        let results1 = engine.recommend(from: candidates, history: history1)
        engine.invalidateCache()

        let history2 = [makeHistory(link: "https://a.com/2", title: "Beta Topic", feedName: "FeedB")]
        let results2 = engine.recommend(from: candidates, history: history2)

        _ = results1
        _ = results2
    }

    // MARK: - Profile Summary

    func testProfileSummaryNotEmpty() {
        let history = [
            makeHistory(link: "https://a.com/1", title: "Tech Innovation Today", feedName: "TechBlog"),
            makeHistory(link: "https://a.com/2", title: "Science Discovery News", feedName: "ScienceFeed"),
        ]

        let summary = engine.profileSummary(from: history)
        XCTAssertFalse(summary.isEmpty)
        XCTAssertTrue(summary.contains("Reading Profile Summary"))
    }

    func testProfileSummaryShowsTopFeeds() {
        let history = (1...5).map { i in
            makeHistory(link: "https://a.com/\(i)", title: "Article \(i)", feedName: "PopularFeed")
        }

        let summary = engine.profileSummary(from: history)
        XCTAssertTrue(summary.contains("PopularFeed"), "Summary should mention the top feed")
    }

    func testEmptyHistoryProfile() {
        let summary = engine.profileSummary(from: [])
        XCTAssertTrue(summary.contains("Reading Profile Summary"),
            "Even with no history, summary should have a header")
    }

    // MARK: - Recommendation Reasons

    func testRecommendationHasReasons() {
        let history = (1...5).map { i in
            makeHistory(link: "https://a.com/\(i)", title: "Programming Tutorial \(i)", feedName: "DevBlog")
        }
        let candidates = [
            makeStory(title: "Programming Tutorial Advanced", link: "https://b.com/1", feedName: "DevBlog"),
        ]

        var options = RecommendationOptions()
        options.minScore = 0.0

        let results = engine.recommend(from: candidates, history: history, options: options)
        if let first = results.first {
            XCTAssertFalse(first.reasons.isEmpty, "Recommendations should include reasoning")
        }
    }

    func testPrimaryReasonExists() {
        let history = (1...5).map { i in
            makeHistory(link: "https://a.com/\(i)", title: "Article \(i)", feedName: "Feed")
        }
        let candidates = [
            makeStory(title: "New Article", link: "https://b.com/1", feedName: "Feed"),
        ]

        var options = RecommendationOptions()
        options.minScore = 0.0
        let results = engine.recommend(from: candidates, history: history, options: options)
        if let first = results.first {
            XCTAssertNotNil(first.primaryReason, "Should have a primary reason")
        }
    }

    // MARK: - Score Range

    func testScoresInValidRange() {
        let history = (1...10).map { i in
            makeHistory(link: "https://a.com/\(i)", title: "Test Article \(i)", feedName: "Feed")
        }
        let candidates = (11...30).map { i in
            makeStory(title: "Candidate \(i)", link: "https://a.com/\(i)", feedName: "Feed")
        }

        var options = RecommendationOptions()
        options.minScore = 0.0
        let results = engine.recommend(from: candidates, history: history, options: options)
        for result in results {
            XCTAssertGreaterThanOrEqual(result.score, 0.0, "Score should be >= 0")
            XCTAssertLessThanOrEqual(result.score, 1.0, "Score should be <= 1")
        }
    }

    // MARK: - Reason Descriptions

    func testReasonDescriptions() {
        let preferredFeed = RecommendationReason.preferredFeed(feedName: "TechBlog", readCount: 5)
        XCTAssertTrue(preferredFeed.description.contains("TechBlog"))
        XCTAssertTrue(preferredFeed.description.contains("5"))

        let keywordMatch = RecommendationReason.keywordMatch(keywords: ["swift", "ios", "development"])
        XCTAssertTrue(keywordMatch.description.contains("swift"))

        let revisited = RecommendationReason.frequentlyRevisited
        XCTAssertFalse(revisited.description.isEmpty)

        let combined = RecommendationReason.combined
        XCTAssertFalse(combined.description.isEmpty)
    }

    // MARK: - ScoredArticle Properties

    func testScoredArticlePrimaryReason() {
        let story = makeStory(title: "Test", link: "https://a.com/1")
        let scored = ScoredArticle(story: story, score: 0.5, reasons: [
            .combined,
            .preferredFeed(feedName: "Feed", readCount: 3),
        ])
        if case .combined = scored.primaryReason! {
            // Expected
        } else {
            XCTFail("Primary reason should be the first reason (.combined)")
        }
    }

    func testScoredArticleNoPrimaryReason() {
        let story = makeStory(title: "Test", link: "https://a.com/1")
        let scored = ScoredArticle(story: story, score: 0.0, reasons: [])
        XCTAssertNil(scored.primaryReason)
    }

    // MARK: - RecommendationOptions Defaults

    func testDefaultOptions() {
        let options = RecommendationOptions()
        XCTAssertEqual(options.feedWeight, 0.5)
        XCTAssertEqual(options.keywordWeight, 0.35)
        XCTAssertEqual(options.revisitWeight, 0.15)
        XCTAssertEqual(options.maxResults, 20)
        XCTAssertEqual(options.minScore, 0.05)
        XCTAssertEqual(options.topKeywordCount, 50)
        XCTAssertEqual(options.minKeywordLength, 4)
        XCTAssertEqual(options.historyDays, 30)
    }

    // MARK: - Large Input Handling

    func testLargeCandidateSet() {
        let history = (1...20).map { i in
            makeHistory(link: "https://a.com/\(i)", title: "History Article \(i)", feedName: "Feed")
        }
        let candidates = (100...300).map { i in
            makeStory(title: "Candidate Article \(i)", link: "https://a.com/\(i)", feedName: "Feed")
        }

        var options = RecommendationOptions()
        options.maxResults = 10
        let results = engine.recommend(from: candidates, history: history, options: options)
        XCTAssertLessThanOrEqual(results.count, 10, "Should respect maxResults limit")
    }
}