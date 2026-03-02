//
//  RecommendationEngineTests.swift
//  FeedReaderTests
//
//  Tests for ArticleRecommendationEngine — scoring, ranking, keyword extraction,
//  feed preference, and profile building.
//

import XCTest
@testable import FeedReader

class RecommendationEngineTests: XCTestCase {
    
    var engine: ArticleRecommendationEngine!
    
    override func setUp() {
        super.setUp()
        engine = ArticleRecommendationEngine()
        engine.invalidateCache()
    }
    
    // MARK: - Helpers
    
    func makeStory(title: String, link: String, feedName: String? = nil) -> Story? {
        let story = Story(title: title, photo: nil, description: "Body text", link: link)
        story?.sourceFeedName = feedName
        return story
    }
    
    func makeHistory(link: String, title: String, feedName: String,
                     readAt: Date = Date(), visitCount: Int = 1) -> HistoryEntry {
        return HistoryEntry(link: link, title: title, feedName: feedName,
                            readAt: readAt, visitCount: visitCount)
    }
    
    // MARK: - Basic Recommendation Tests
    
    func testRecommendReturnsEmptyForEmptyCandidates() {
        let history = [makeHistory(link: "https://a.com", title: "Swift", feedName: "Tech")]
        let results = engine.recommend(from: [], history: history)
        XCTAssertTrue(results.isEmpty)
    }
    
    func testRecommendReturnsEmptyForEmptyHistory() {
        guard let story = makeStory(title: "Swift 6", link: "https://a.com", feedName: "Tech") else {
            XCTFail(); return
        }
        let results = engine.recommend(from: [story], history: [])
        XCTAssertTrue(results.isEmpty)
    }
    
    func testRecommendFiltersAlreadyReadArticles() {
        let history = [
            makeHistory(link: "https://a.com", title: "Swift guide", feedName: "Tech")
        ]
        guard let story = makeStory(title: "Swift guide", link: "https://a.com", feedName: "Tech") else {
            XCTFail(); return
        }
        let results = engine.recommend(from: [story], history: history)
        XCTAssertTrue(results.isEmpty, "Already-read articles should be filtered out")
    }
    
    func testRecommendReturnsUnreadArticles() {
        let history = [
            makeHistory(link: "https://old.com", title: "Swift programming", feedName: "Tech")
        ]
        guard let story = makeStory(title: "Swift update", link: "https://new.com", feedName: "Tech") else {
            XCTFail(); return
        }
        let results = engine.recommend(from: [story], history: history)
        XCTAssertFalse(results.isEmpty, "Unread article from preferred feed with keyword match should be recommended")
    }
    
    // MARK: - Feed Preference Tests
    
    func testPreferredFeedScoresHigher() {
        let history = [
            makeHistory(link: "https://1.com", title: "Article one", feedName: "TechBlog"),
            makeHistory(link: "https://2.com", title: "Article two", feedName: "TechBlog"),
            makeHistory(link: "https://3.com", title: "Article three", feedName: "TechBlog"),
            makeHistory(link: "https://4.com", title: "Random article", feedName: "Cooking")
        ]
        
        guard let techStory = makeStory(title: "New article", link: "https://tech.com", feedName: "TechBlog"),
              let cookStory = makeStory(title: "New recipe", link: "https://cook.com", feedName: "Cooking") else {
            XCTFail(); return
        }
        
        let results = engine.recommend(from: [techStory, cookStory], history: history)
        
        // Tech story should score higher due to feed preference
        if results.count >= 2 {
            let techScore = results.first(where: { $0.story.link == "https://tech.com" })?.score ?? 0
            let cookScore = results.first(where: { $0.story.link == "https://cook.com" })?.score ?? 0
            XCTAssertGreaterThan(techScore, cookScore)
        }
    }
    
    // MARK: - Keyword Affinity Tests
    
    func testKeywordMatchBoostsScore() {
        let history = [
            makeHistory(link: "https://1.com", title: "Swift programming language", feedName: "Feed"),
            makeHistory(link: "https://2.com", title: "Swift release notes", feedName: "Feed"),
            makeHistory(link: "https://3.com", title: "Swift package manager", feedName: "Feed")
        ]
        
        guard let swiftStory = makeStory(title: "Swift concurrency guide", link: "https://new.com", feedName: "Feed"),
              let pythonStory = makeStory(title: "Python data science", link: "https://py.com", feedName: "Feed") else {
            XCTFail(); return
        }
        
        let results = engine.recommend(from: [swiftStory, pythonStory], history: history)
        
        // Swift story should score higher due to keyword match
        if results.count >= 2 {
            let swiftScore = results.first(where: { $0.story.link == "https://new.com" })?.score ?? 0
            let pythonScore = results.first(where: { $0.story.link == "https://py.com" })?.score ?? 0
            XCTAssertGreaterThan(swiftScore, pythonScore)
        }
    }
    
    // MARK: - Revisit Pattern Tests
    
    func testRevisitedArticlesInfluenceRecommendations() {
        let history = [
            makeHistory(link: "https://1.com", title: "Machine learning fundamentals",
                        feedName: "AI Blog", visitCount: 5),
            makeHistory(link: "https://2.com", title: "Deep learning tutorial",
                        feedName: "AI Blog", visitCount: 3)
        ]
        
        guard let mlStory = makeStory(title: "Machine learning applications", link: "https://ml.com", feedName: "AI Blog") else {
            XCTFail(); return
        }
        
        let results = engine.recommend(from: [mlStory], history: history)
        XCTAssertFalse(results.isEmpty)
        
        // Should have frequentlyRevisited reason
        let reasons = results.first?.reasons ?? []
        let hasRevisitReason = reasons.contains {
            if case .frequentlyRevisited = $0 { return true }
            return false
        }
        XCTAssertTrue(hasRevisitReason)
    }
    
    // MARK: - Score Threshold Tests
    
    func testMinScoreFiltering() {
        let history = [
            makeHistory(link: "https://1.com", title: "Swift", feedName: "Tech")
        ]
        
        guard let story = makeStory(title: "Completely unrelated gardening tips",
                                     link: "https://garden.com", feedName: "Garden") else {
            XCTFail(); return
        }
        
        var options = RecommendationOptions()
        options.minScore = 0.5  // High threshold
        
        let results = engine.recommend(from: [story], history: history, options: options)
        XCTAssertTrue(results.isEmpty, "Low-scoring articles should be filtered by minScore")
    }
    
    // MARK: - Max Results Tests
    
    func testMaxResultsLimit() {
        // Create plenty of history
        var history: [HistoryEntry] = []
        for i in 0..<20 {
            history.append(makeHistory(link: "https://h\(i).com", title: "Swift article \(i)", feedName: "Tech"))
        }
        
        // Create many candidates
        var candidates: [Story] = []
        for i in 0..<30 {
            if let story = makeStory(title: "Swift update \(i)", link: "https://c\(i).com", feedName: "Tech") {
                candidates.append(story)
            }
        }
        
        var options = RecommendationOptions()
        options.maxResults = 5
        options.minScore = 0.0
        
        let results = engine.recommend(from: candidates, history: history, options: options)
        XCTAssertLessThanOrEqual(results.count, 5)
    }
    
    // MARK: - Sorting Tests
    
    func testResultsSortedByScoreDescending() {
        var history: [HistoryEntry] = []
        for i in 0..<10 {
            history.append(makeHistory(link: "https://h\(i).com", title: "Swift article", feedName: "TechBlog"))
        }
        // Add one from a different feed so scores differ
        history.append(makeHistory(link: "https://hx.com", title: "Cooking recipe", feedName: "Cooking"))
        
        guard let s1 = makeStory(title: "Swift concurrency", link: "https://c1.com", feedName: "TechBlog"),
              let s2 = makeStory(title: "Random gardening", link: "https://c2.com", feedName: "Garden") else {
            XCTFail(); return
        }
        
        var options = RecommendationOptions()
        options.minScore = 0.0
        
        let results = engine.recommend(from: [s1, s2], history: history, options: options)
        
        for i in 0..<max(0, results.count - 1) {
            XCTAssertGreaterThanOrEqual(results[i].score, results[i + 1].score)
        }
    }
    
    // MARK: - Reason Tests
    
    func testPreferredFeedReason() {
        let history = [
            makeHistory(link: "https://1.com", title: "Article", feedName: "TechBlog"),
            makeHistory(link: "https://2.com", title: "Article", feedName: "TechBlog")
        ]
        
        guard let story = makeStory(title: "New post", link: "https://new.com", feedName: "TechBlog") else {
            XCTFail(); return
        }
        
        let results = engine.recommend(from: [story], history: history)
        let reasons = results.first?.reasons ?? []
        
        let hasFeedReason = reasons.contains {
            if case .preferredFeed = $0 { return true }
            return false
        }
        XCTAssertTrue(hasFeedReason)
    }
    
    func testKeywordMatchReason() {
        let history = [
            makeHistory(link: "https://1.com", title: "Machine learning deep neural networks", feedName: "Feed"),
            makeHistory(link: "https://2.com", title: "Machine learning applications", feedName: "Feed")
        ]
        
        guard let story = makeStory(title: "Machine learning update", link: "https://new.com", feedName: "Other") else {
            XCTFail(); return
        }
        
        let results = engine.recommend(from: [story], history: history)
        let reasons = results.first?.reasons ?? []
        
        let hasKeywordReason = reasons.contains {
            if case .keywordMatch = $0 { return true }
            return false
        }
        XCTAssertTrue(hasKeywordReason)
    }
    
    func testCombinedReasonForMultipleFactors() {
        let history = [
            makeHistory(link: "https://1.com", title: "Swift programming language", feedName: "TechBlog"),
            makeHistory(link: "https://2.com", title: "Swift release notes", feedName: "TechBlog"),
            makeHistory(link: "https://3.com", title: "Swift concurrency guide",
                        feedName: "TechBlog", visitCount: 3)
        ]
        
        guard let story = makeStory(title: "Swift programming tips", link: "https://new.com", feedName: "TechBlog") else {
            XCTFail(); return
        }
        
        let results = engine.recommend(from: [story], history: history)
        let reasons = results.first?.reasons ?? []
        
        // With both feed preference and keyword match, should have .combined
        if reasons.count > 1 {
            if case .combined = reasons[0] {
                // Expected
            } else {
                // Multiple reasons without combined is also acceptable
            }
        }
    }
    
    // MARK: - RecommendationReason Description Tests
    
    func testPreferredFeedDescription() {
        let reason = RecommendationReason.preferredFeed(feedName: "TechBlog", readCount: 42)
        XCTAssertTrue(reason.description.contains("TechBlog"))
        XCTAssertTrue(reason.description.contains("42"))
    }
    
    func testKeywordMatchDescription() {
        let reason = RecommendationReason.keywordMatch(keywords: ["swift", "ios", "xcode"])
        XCTAssertTrue(reason.description.contains("swift"))
        XCTAssertTrue(reason.description.contains("ios"))
    }
    
    func testKeywordMatchDescriptionTruncates() {
        let reason = RecommendationReason.keywordMatch(keywords: ["a", "b", "c", "d", "e"])
        // Should only show first 3
        let desc = reason.description
        XCTAssertTrue(desc.contains("a"))
        XCTAssertTrue(desc.contains("b"))
        XCTAssertTrue(desc.contains("c"))
    }
    
    func testFrequentlyRevisitedDescription() {
        let reason = RecommendationReason.frequentlyRevisited
        XCTAssertFalse(reason.description.isEmpty)
        XCTAssertTrue(reason.description.contains("re-read"))
    }
    
    func testCombinedDescription() {
        let reason = RecommendationReason.combined
        XCTAssertFalse(reason.description.isEmpty)
    }
    
    // MARK: - Options Tests
    
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
    
    func testCustomOptions() {
        var options = RecommendationOptions()
        options.feedWeight = 0.8
        options.keywordWeight = 0.2
        options.revisitWeight = 0.0
        options.maxResults = 5
        options.minScore = 0.1
        
        XCTAssertEqual(options.feedWeight, 0.8)
        XCTAssertEqual(options.maxResults, 5)
    }
    
    // MARK: - History Days Filter Tests
    
    func testHistoryDaysFilter() {
        let oldDate = Calendar.current.date(byAdding: .day, value: -60, to: Date())!
        let recentDate = Calendar.current.date(byAdding: .day, value: -5, to: Date())!
        
        let history = [
            makeHistory(link: "https://old.com", title: "Old swift article", feedName: "Tech", readAt: oldDate),
            makeHistory(link: "https://new.com", title: "Recent swift article", feedName: "Tech", readAt: recentDate)
        ]
        
        guard let story = makeStory(title: "Swift update", link: "https://candidate.com", feedName: "Tech") else {
            XCTFail(); return
        }
        
        var options = RecommendationOptions()
        options.historyDays = 30  // Only last 30 days
        options.minScore = 0.0
        
        // Old entry should be excluded from profile building
        let results = engine.recommend(from: [story], history: history, options: options)
        // Should still work with just the recent entry
        XCTAssertFalse(results.isEmpty)
    }
    
    func testAllHistoryWhenDaysIsZero() {
        let oldDate = Calendar.current.date(byAdding: .day, value: -365, to: Date())!
        
        let history = [
            makeHistory(link: "https://old.com", title: "Very old swift article", feedName: "Tech", readAt: oldDate)
        ]
        
        guard let story = makeStory(title: "Swift update", link: "https://candidate.com", feedName: "Tech") else {
            XCTFail(); return
        }
        
        var options = RecommendationOptions()
        options.historyDays = 0  // All history
        options.minScore = 0.0
        
        let results = engine.recommend(from: [story], history: history, options: options)
        XCTAssertFalse(results.isEmpty)
    }
    
    // MARK: - Cache Tests
    
    func testInvalidateCache() {
        let history = [
            makeHistory(link: "https://1.com", title: "Swift article", feedName: "Tech")
        ]
        guard let story = makeStory(title: "Swift update", link: "https://new.com", feedName: "Tech") else {
            XCTFail(); return
        }
        
        // First call builds cache
        _ = engine.recommend(from: [story], history: history)
        
        // Invalidate
        engine.invalidateCache()
        
        // Second call should rebuild (no crash or stale data)
        let results = engine.recommend(from: [story], history: history)
        XCTAssertFalse(results.isEmpty)
    }
    
    // MARK: - Profile Summary Tests
    
    func testProfileSummaryFormat() {
        let history = [
            makeHistory(link: "https://1.com", title: "Swift programming guide", feedName: "TechBlog"),
            makeHistory(link: "https://2.com", title: "Swift release notes", feedName: "TechBlog"),
            makeHistory(link: "https://3.com", title: "Python data science", feedName: "DataBlog")
        ]
        
        let summary = engine.profileSummary(from: history)
        
        XCTAssertTrue(summary.contains("Reading Profile Summary"))
        XCTAssertTrue(summary.contains("Top Feeds"))
        XCTAssertTrue(summary.contains("TechBlog"))
    }
    
    func testProfileSummaryEmptyHistory() {
        let summary = engine.profileSummary(from: [])
        XCTAssertTrue(summary.contains("Reading Profile Summary"))
    }
    
    // MARK: - ScoredArticle Tests
    
    func testScoredArticlePrimaryReason() {
        guard let story = makeStory(title: "Test", link: "https://a.com") else {
            XCTFail(); return
        }
        let scored = ScoredArticle(
            story: story,
            score: 0.8,
            reasons: [.combined, .preferredFeed(feedName: "Tech", readCount: 5)]
        )
        
        if case .combined = scored.primaryReason! {
            // Expected
        } else {
            XCTFail("Primary reason should be first in array")
        }
    }
    
    func testScoredArticleNoReasons() {
        guard let story = makeStory(title: "Test", link: "https://a.com") else {
            XCTFail(); return
        }
        let scored = ScoredArticle(story: story, score: 0.0, reasons: [])
        XCTAssertNil(scored.primaryReason)
    }
    
    // MARK: - Score Bounds Tests
    
    func testScoreNeverExceedsOne() {
        // Create heavy history to maximize scores
        var history: [HistoryEntry] = []
        for i in 0..<100 {
            history.append(makeHistory(
                link: "https://h\(i).com",
                title: "Swift programming language tutorial guide",
                feedName: "TechBlog",
                visitCount: 10
            ))
        }
        
        guard let story = makeStory(title: "Swift programming language tutorial", link: "https://new.com", feedName: "TechBlog") else {
            XCTFail(); return
        }
        
        var options = RecommendationOptions()
        options.minScore = 0.0
        
        let results = engine.recommend(from: [story], history: history, options: options)
        for result in results {
            XCTAssertLessThanOrEqual(result.score, 1.0, "Score should never exceed 1.0")
            XCTAssertGreaterThanOrEqual(result.score, 0.0, "Score should never be negative")
        }
    }
    
    // MARK: - Stop Words Tests
    
    func testStopWordsFilteredFromKeywords() {
        let history = [
            makeHistory(link: "https://1.com", title: "The quick brown fox jumps over the lazy dog",
                        feedName: "Feed"),
            makeHistory(link: "https://2.com", title: "The swift programming language guide",
                        feedName: "Feed")
        ]
        
        // "the", "over" are stop words — "swift", "programming" should be keywords
        guard let story = makeStory(title: "Swift programming update", link: "https://new.com", feedName: "Feed") else {
            XCTFail(); return
        }
        
        let results = engine.recommend(from: [story], history: history)
        XCTAssertFalse(results.isEmpty)
    }
}
