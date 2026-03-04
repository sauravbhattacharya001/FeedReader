//
//  FeedPerformanceAnalyzerTests.swift
//  FeedReaderTests
//
//  Tests for FeedPerformanceAnalyzer — per-feed analytics and scoring.
//

import XCTest
@testable import FeedReader

class FeedPerformanceAnalyzerTests: XCTestCase {

    var analyzer: FeedPerformanceAnalyzer!
    let now = Date(timeIntervalSince1970: 1_700_000_000) // 2023-11-14

    override func setUp() {
        super.setUp()
        analyzer = FeedPerformanceAnalyzer()
    }

    // MARK: - Helpers

    func makeArticle(
        title: String = "Test Article",
        body: String = "This is a test article with some content for analysis. It has multiple sentences. The readability should be fairly standard.",
        link: String? = nil,
        daysAgo: Double = 0
    ) -> (title: String, body: String, link: String, date: Date) {
        let date = now.addingTimeInterval(-daysAgo * 86400)
        let articleLink = link ?? "https://example.com/\(UUID().uuidString)"
        return (title: title, body: body, link: articleLink, date: date)
    }

    func makeArticles(count: Int, startDaysAgo: Double = 0, gapDays: Double = 1) -> [(title: String, body: String, link: String, date: Date)] {
        return (0..<count).map { i in
            makeArticle(
                title: "Article \(i)",
                body: "This is article number \(i) with enough content to be considered substantive for testing purposes. It covers various topics including technology, science, and education.",
                daysAgo: startDaysAgo + Double(i) * gapDays
            )
        }
    }

    // MARK: - FeedGrade Tests

    func testGradeFromScore() {
        XCTAssertEqual(FeedGrade.from(score: 95), .aPlus)
        XCTAssertEqual(FeedGrade.from(score: 90), .aPlus)
        XCTAssertEqual(FeedGrade.from(score: 85), .a)
        XCTAssertEqual(FeedGrade.from(score: 80), .a)
        XCTAssertEqual(FeedGrade.from(score: 75), .bPlus)
        XCTAssertEqual(FeedGrade.from(score: 70), .bPlus)
        XCTAssertEqual(FeedGrade.from(score: 65), .b)
        XCTAssertEqual(FeedGrade.from(score: 60), .b)
        XCTAssertEqual(FeedGrade.from(score: 55), .cPlus)
        XCTAssertEqual(FeedGrade.from(score: 45), .c)
        XCTAssertEqual(FeedGrade.from(score: 30), .d)
        XCTAssertEqual(FeedGrade.from(score: 10), .f)
        XCTAssertEqual(FeedGrade.from(score: 0), .f)
    }

    func testGradeComparable() {
        XCTAssertTrue(FeedGrade.aPlus < FeedGrade.a)
        XCTAssertTrue(FeedGrade.a < FeedGrade.bPlus)
        XCTAssertTrue(FeedGrade.d < FeedGrade.f)
        XCTAssertFalse(FeedGrade.f < FeedGrade.aPlus)
    }

    func testGradeEmoji() {
        XCTAssertEqual(FeedGrade.aPlus.emoji, "🌟")
        XCTAssertEqual(FeedGrade.b.emoji, "👍")
        XCTAssertEqual(FeedGrade.c.emoji, "🤷")
        XCTAssertEqual(FeedGrade.d.emoji, "👎")
        XCTAssertEqual(FeedGrade.f.emoji, "🚫")
    }

    // MARK: - Publishing Metrics Tests

    func testPublishingEmptyArticles() {
        let result = analyzer.analyzePublishing(articles: [], now: now)
        XCTAssertEqual(result.articleCount, 0)
        XCTAssertEqual(result.articlesPerDay, 0)
        XCTAssertEqual(result.healthStatus, .dead)
    }

    func testPublishingActiveDaily() {
        let articles = makeArticles(count: 10, startDaysAgo: 0, gapDays: 1)
        let result = analyzer.analyzePublishing(articles: articles, now: now)
        XCTAssertEqual(result.articleCount, 10)
        XCTAssertGreaterThan(result.articlesPerDay, 0.5)
        XCTAssertEqual(result.healthStatus, .active)
        XCTAssertEqual(result.daysSinceLastArticle, 0)
    }

    func testPublishingStaleFeed() {
        let articles = makeArticles(count: 5, startDaysAgo: 30, gapDays: 2)
        let result = analyzer.analyzePublishing(articles: articles, now: now)
        XCTAssertEqual(result.healthStatus, .stale)
        XCTAssertGreaterThanOrEqual(result.daysSinceLastArticle, 15)
    }

    func testPublishingDeadFeed() {
        let articles = makeArticles(count: 3, startDaysAgo: 90, gapDays: 1)
        let result = analyzer.analyzePublishing(articles: articles, now: now)
        XCTAssertEqual(result.healthStatus, .dead)
        XCTAssertGreaterThan(result.daysSinceLastArticle, 60)
    }

    func testPublishingSlowingFeed() {
        let articles = makeArticles(count: 3, startDaysAgo: 10, gapDays: 2)
        let result = analyzer.analyzePublishing(articles: articles, now: now)
        XCTAssertEqual(result.healthStatus, .slowing)
    }

    func testPublishingGapCalculation() {
        let articles = [
            makeArticle(daysAgo: 0),
            makeArticle(daysAgo: 2),
            makeArticle(daysAgo: 10),
        ]
        let result = analyzer.analyzePublishing(articles: articles, now: now)
        XCTAssertGreaterThan(result.averageGapHours, 0)
        XCTAssertGreaterThanOrEqual(result.longestGapHours, result.averageGapHours)
    }

    func testPublishingConsistency() {
        // Daily articles should have high consistency
        let consistent = makeArticles(count: 7, startDaysAgo: 0, gapDays: 1)
        let result = analyzer.analyzePublishing(articles: consistent, now: now)
        XCTAssertGreaterThan(result.publishingConsistency, 0.5)
    }

    func testPublishingSingleArticle() {
        let articles = [makeArticle(daysAgo: 1)]
        let result = analyzer.analyzePublishing(articles: articles, now: now)
        XCTAssertEqual(result.articleCount, 1)
        XCTAssertEqual(result.averageGapHours, 0) // no gap with 1 article
    }

    // MARK: - Content Quality Tests

    func testContentEmptyArticles() {
        let result = analyzer.analyzeContent(articles: [])
        XCTAssertEqual(result.averageReadability, 0)
        XCTAssertEqual(result.averageWordCount, 0)
        XCTAssertEqual(result.medianWordCount, 0)
        XCTAssertEqual(result.topicDiversity, 0)
    }

    func testContentSubstantiveRatio() {
        let articles = [
            makeArticle(body: "Short."),
            makeArticle(body: "Also short."),
            makeArticle(body: String(repeating: "word ", count: 150)), // long
        ]
        let result = analyzer.analyzeContent(articles: articles)
        // 1 out of 3 is substantive (>100 words)
        XCTAssertGreaterThan(result.substantiveRatio, 0)
        XCTAssertLessThanOrEqual(result.substantiveRatio, 1.0)
    }

    func testContentTopKeywords() {
        let articles = [
            makeArticle(title: "Swift Programming", body: "Swift is a great programming language for iOS development. Swift makes programming fun."),
            makeArticle(title: "Swift Update", body: "The latest Swift update brings new programming features."),
        ]
        let result = analyzer.analyzeContent(articles: articles)
        XCTAssertFalse(result.topKeywords.isEmpty)
        // "swift" and "programming" should be top keywords
        let keywords = result.topKeywords.map { $0.keyword }
        XCTAssertTrue(keywords.contains("swift"))
    }

    func testContentReadability() {
        let articles = makeArticles(count: 5)
        let result = analyzer.analyzeContent(articles: articles)
        XCTAssertGreaterThan(result.averageReadability, 0)
        XCTAssertLessThanOrEqual(result.averageReadability, 100)
    }

    func testContentMedianWordCount() {
        let articles = [
            makeArticle(body: String(repeating: "word ", count: 10)),   // 10 words
            makeArticle(body: String(repeating: "word ", count: 50)),   // 50 words
            makeArticle(body: String(repeating: "word ", count: 200)),  // 200 words
        ]
        let result = analyzer.analyzeContent(articles: articles)
        // Median should be the middle value
        XCTAssertGreaterThan(result.medianWordCount, 10)
        XCTAssertLessThan(result.medianWordCount, 200)
    }

    func testContentTopicDiversity() {
        // Articles with diverse topics
        let diverse = [
            makeArticle(title: "AI Technology", body: "Artificial intelligence is transforming technology and computing."),
            makeArticle(title: "Climate Science", body: "Climate change affects weather patterns and ocean temperatures."),
            makeArticle(title: "Space Exploration", body: "NASA launches rockets for space exploration and satellite deployment."),
        ]
        let resultDiverse = analyzer.analyzeContent(articles: diverse)

        // Articles with repetitive topics
        let repetitive = [
            makeArticle(title: "Swift Code", body: "Swift code examples for programming."),
            makeArticle(title: "Swift Tutorial", body: "Swift tutorial for programming beginners."),
            makeArticle(title: "Swift Guide", body: "Swift programming guide for developers."),
        ]
        let resultRepetitive = analyzer.analyzeContent(articles: repetitive)

        XCTAssertGreaterThanOrEqual(resultDiverse.topicDiversity, resultRepetitive.topicDiversity)
    }

    // MARK: - Sentiment Tests

    func testSentimentEmptyArticles() {
        let result = analyzer.analyzeSentiment(articles: [])
        XCTAssertEqual(result.averageSentiment, 0)
        XCTAssertEqual(result.neutralRatio, 1.0)
        XCTAssertEqual(result.tone, "No data")
    }

    func testSentimentPositive() {
        let articles = [
            makeArticle(body: "This is excellent amazing wonderful great news! The best breakthrough impressive results."),
        ]
        let result = analyzer.analyzeSentiment(articles: articles)
        XCTAssertGreaterThan(result.averageSentiment, 0)
        XCTAssertEqual(result.positiveRatio, 1.0)
    }

    func testSentimentNegative() {
        let articles = [
            makeArticle(body: "Terrible awful horrible disaster. The worst crisis and devastating failure. Bad problems."),
        ]
        let result = analyzer.analyzeSentiment(articles: articles)
        XCTAssertLessThan(result.averageSentiment, 0)
        XCTAssertEqual(result.negativeRatio, 1.0)
    }

    func testSentimentMixed() {
        let articles = [
            makeArticle(body: "Great excellent amazing wonderful."),
            makeArticle(body: "Terrible awful horrible disaster."),
        ]
        let result = analyzer.analyzeSentiment(articles: articles)
        // Average should be near zero
        XCTAssertGreaterThanOrEqual(result.averageSentiment, -0.5)
        XCTAssertLessThanOrEqual(result.averageSentiment, 0.5)
        XCTAssertGreaterThan(result.volatility, 0)
    }

    func testSentimentToneLabels() {
        // Very positive
        let vp = analyzer.analyzeSentiment(articles: [
            makeArticle(body: "Amazing excellent wonderful brilliant outstanding remarkable great love")
        ])
        XCTAssertTrue(vp.tone.contains("Positive"))

        // Very negative
        let vn = analyzer.analyzeSentiment(articles: [
            makeArticle(body: "Terrible awful horrible devastating catastrophic disaster crash fail")
        ])
        XCTAssertTrue(vn.tone.contains("Negative"))
    }

    // MARK: - Engagement Tests

    func testEngagementEmptyArticles() {
        let result = analyzer.analyzeEngagement(articles: [], readLinks: [], bookmarkedLinks: [], now: now)
        XCTAssertEqual(result.readRate, 0)
        XCTAssertEqual(result.articlesRead, 0)
    }

    func testEngagementFullyRead() {
        let articles = [
            makeArticle(link: "https://a.com/1", daysAgo: 1),
            makeArticle(link: "https://a.com/2", daysAgo: 2),
        ]
        let readLinks: Set<String> = ["https://a.com/1", "https://a.com/2"]
        let result = analyzer.analyzeEngagement(articles: articles, readLinks: readLinks, bookmarkedLinks: [], now: now)
        XCTAssertEqual(result.readRate, 1.0)
        XCTAssertEqual(result.articlesRead, 2)
    }

    func testEngagementPartiallyRead() {
        let articles = [
            makeArticle(link: "https://b.com/1", daysAgo: 1),
            makeArticle(link: "https://b.com/2", daysAgo: 2),
            makeArticle(link: "https://b.com/3", daysAgo: 3),
            makeArticle(link: "https://b.com/4", daysAgo: 4),
        ]
        let readLinks: Set<String> = ["https://b.com/1"]
        let result = analyzer.analyzeEngagement(articles: articles, readLinks: readLinks, bookmarkedLinks: [], now: now)
        XCTAssertEqual(result.readRate, 0.25)
        XCTAssertEqual(result.articlesRead, 1)
    }

    func testEngagementBookmarks() {
        let articles = [
            makeArticle(link: "https://c.com/1", daysAgo: 1),
            makeArticle(link: "https://c.com/2", daysAgo: 2),
        ]
        let bookmarks: Set<String> = ["https://c.com/1"]
        let result = analyzer.analyzeEngagement(articles: articles, readLinks: [], bookmarkedLinks: bookmarks, now: now)
        XCTAssertEqual(result.articlesBookmarked, 1)
    }

    func testEngagementIgnoresUnrelatedLinks() {
        let articles = [
            makeArticle(link: "https://d.com/1", daysAgo: 1),
        ]
        // Read links from other feeds should not count
        let readLinks: Set<String> = ["https://other.com/unrelated"]
        let result = analyzer.analyzeEngagement(articles: articles, readLinks: readLinks, bookmarkedLinks: [], now: now)
        XCTAssertEqual(result.readRate, 0)
    }

    // MARK: - Composite Score Tests

    func testCompositeScoreRange() {
        let articles = makeArticles(count: 10, startDaysAgo: 0, gapDays: 1)
        let report = analyzer.analyze(
            feedName: "Test",
            feedURL: "https://test.com/feed",
            articles: articles,
            readLinks: Set(articles.map { $0.link }),
            now: now
        )
        XCTAssertGreaterThanOrEqual(report.compositeScore, 0)
        XCTAssertLessThanOrEqual(report.compositeScore, 100)
    }

    func testCompositeActiveFeedScoresHigher() {
        let active = makeArticles(count: 10, startDaysAgo: 0, gapDays: 1)
        let stale = makeArticles(count: 10, startDaysAgo: 40, gapDays: 1)

        let activeReport = analyzer.analyze(feedName: "Active", feedURL: "https://active.com", articles: active, now: now)
        let staleReport = analyzer.analyze(feedName: "Stale", feedURL: "https://stale.com", articles: stale, now: now)

        XCTAssertGreaterThan(activeReport.compositeScore, staleReport.compositeScore)
    }

    func testCompositeEngagedFeedScoresHigher() {
        let articles = makeArticles(count: 10, startDaysAgo: 0, gapDays: 1)
        let allLinks = Set(articles.map { $0.link })

        let engaged = analyzer.analyze(feedName: "Engaged", feedURL: "https://a.com", articles: articles, readLinks: allLinks, now: now)
        let ignored = analyzer.analyze(feedName: "Ignored", feedURL: "https://b.com", articles: articles, readLinks: [], now: now)

        XCTAssertGreaterThan(engaged.compositeScore, ignored.compositeScore)
    }

    func testCompositeEmptyFeed() {
        let report = analyzer.analyze(feedName: "Empty", feedURL: "https://empty.com", articles: [], now: now)
        XCTAssertEqual(report.compositeScore, 0)
        XCTAssertEqual(report.grade, .f)
    }

    // MARK: - Custom Weights

    func testCustomWeightsQualityFirst() {
        let qualityAnalyzer = FeedPerformanceAnalyzer(weights: .qualityFirst)
        let articles = makeArticles(count: 10, startDaysAgo: 0, gapDays: 1)
        let report = qualityAnalyzer.analyze(feedName: "Q", feedURL: "https://q.com", articles: articles, now: now)
        XCTAssertGreaterThanOrEqual(report.compositeScore, 0)
        XCTAssertLessThanOrEqual(report.compositeScore, 100)
    }

    func testCustomWeightsEngagementFirst() {
        let engAnalyzer = FeedPerformanceAnalyzer(weights: .engagementFirst)
        let articles = makeArticles(count: 10, startDaysAgo: 0, gapDays: 1)

        // With engagement-first weights, fully-read feeds should score much higher
        let readReport = engAnalyzer.analyze(feedName: "Read", feedURL: "https://r.com", articles: articles, readLinks: Set(articles.map { $0.link }), now: now)
        let unreadReport = engAnalyzer.analyze(feedName: "Unread", feedURL: "https://u.com", articles: articles, readLinks: [], now: now)

        XCTAssertGreaterThan(readReport.compositeScore, unreadReport.compositeScore)
    }

    func testWeightsTotal() {
        XCTAssertEqual(FeedScoreWeights.default.total, 1.0, accuracy: 0.01)
        XCTAssertEqual(FeedScoreWeights.qualityFirst.total, 1.0, accuracy: 0.01)
        XCTAssertEqual(FeedScoreWeights.engagementFirst.total, 1.0, accuracy: 0.01)
    }

    // MARK: - Analyze All Tests

    func testAnalyzeAllSortsByScore() {
        let feeds = [
            (name: "Dead", url: "https://dead.com", articles: makeArticles(count: 3, startDaysAgo: 100, gapDays: 1)),
            (name: "Active", url: "https://active.com", articles: makeArticles(count: 10, startDaysAgo: 0, gapDays: 1)),
        ]
        let reports = analyzer.analyzeAll(feeds: feeds, now: now)
        XCTAssertEqual(reports.count, 2)
        XCTAssertEqual(reports[0].feedName, "Active") // higher score first
        XCTAssertGreaterThan(reports[0].compositeScore, reports[1].compositeScore)
    }

    func testAnalyzeAllEmptyFeeds() {
        let reports = analyzer.analyzeAll(feeds: [], now: now)
        XCTAssertTrue(reports.isEmpty)
    }

    // MARK: - Recommendation Tests

    func testRecommendationDeadFeed() {
        let articles = makeArticles(count: 3, startDaysAgo: 90, gapDays: 1)
        let report = analyzer.analyze(feedName: "Dead", feedURL: "https://dead.com", articles: articles, now: now)
        XCTAssertTrue(report.recommendation.contains("dead") || report.recommendation.contains("removing"))
    }

    func testRecommendationStaleFeed() {
        let articles = makeArticles(count: 5, startDaysAgo: 30, gapDays: 2)
        let report = analyzer.analyze(feedName: "Stale", feedURL: "https://stale.com", articles: articles, now: now)
        XCTAssertTrue(report.recommendation.contains("quiet") || report.recommendation.contains("dead") || report.recommendation.contains("removing"))
    }

    func testRecommendationLowEngagement() {
        let articles = makeArticles(count: 20, startDaysAgo: 0, gapDays: 1)
        let report = analyzer.analyze(feedName: "Ignored", feedURL: "https://ign.com", articles: articles, readLinks: [], now: now)
        // Should suggest removing or recategorizing
        XCTAssertFalse(report.recommendation.isEmpty)
    }

    // MARK: - Summary Tests

    func testSummaryNoFeeds() {
        let result = analyzer.summary(from: [])
        XCTAssertEqual(result, "No feeds to analyze.")
    }

    func testSummaryIncludesAllFeeds() {
        let feeds = [
            (name: "A", url: "https://a.com", articles: makeArticles(count: 5, startDaysAgo: 0, gapDays: 1)),
            (name: "B", url: "https://b.com", articles: makeArticles(count: 5, startDaysAgo: 0, gapDays: 1)),
        ]
        let reports = analyzer.analyzeAll(feeds: feeds, now: now)
        let summary = analyzer.summary(from: reports)
        XCTAssertTrue(summary.contains("Feed Performance Summary"))
        XCTAssertTrue(summary.contains("2 feeds"))
    }

    func testSummaryFlagsStaleFeeeds() {
        let feeds = [
            (name: "Good", url: "https://g.com", articles: makeArticles(count: 5, startDaysAgo: 0, gapDays: 1)),
            (name: "Dead", url: "https://d.com", articles: makeArticles(count: 3, startDaysAgo: 100, gapDays: 1)),
        ]
        let reports = analyzer.analyzeAll(feeds: feeds, now: now)
        let summary = analyzer.summary(from: reports)
        XCTAssertTrue(summary.contains("stale or dead"))
    }

    // MARK: - Text Utility Tests

    func testExtractWords() {
        let words = FeedPerformanceAnalyzer.extractWords(from: "Hello, world! This is a test.")
        XCTAssertEqual(words, ["Hello", "world", "This", "is", "a", "test"])
    }

    func testExtractWordsEmpty() {
        XCTAssertTrue(FeedPerformanceAnalyzer.extractWords(from: "").isEmpty)
        XCTAssertTrue(FeedPerformanceAnalyzer.extractWords(from: "   ").isEmpty)
    }

    func testCountSentences() {
        XCTAssertEqual(FeedPerformanceAnalyzer.countSentences(in: "One. Two. Three."), 3)
        XCTAssertEqual(FeedPerformanceAnalyzer.countSentences(in: "Hello! How are you? Fine."), 3)
        XCTAssertGreaterThanOrEqual(FeedPerformanceAnalyzer.countSentences(in: "No period"), 1)
    }

    func testEstimateSyllables() {
        XCTAssertEqual(FeedPerformanceAnalyzer.estimateSyllables("cat"), 1)
        XCTAssertEqual(FeedPerformanceAnalyzer.estimateSyllables("hello"), 2)
        XCTAssertGreaterThanOrEqual(FeedPerformanceAnalyzer.estimateSyllables("beautiful"), 3)
        XCTAssertEqual(FeedPerformanceAnalyzer.estimateSyllables("a"), 1) // short word
    }

    func testSimpleSentiment() {
        XCTAssertGreaterThan(FeedPerformanceAnalyzer.simpleSentiment("great excellent wonderful"), 0)
        XCTAssertLessThan(FeedPerformanceAnalyzer.simpleSentiment("terrible awful horrible"), 0)
        XCTAssertEqual(FeedPerformanceAnalyzer.simpleSentiment(""), 0)
    }

    func testSimpleSentimentBounded() {
        // Even extreme text should stay in [-1, 1]
        let extreme = String(repeating: "great ", count: 100)
        let score = FeedPerformanceAnalyzer.simpleSentiment(extreme)
        XCTAssertGreaterThanOrEqual(score, -1.0)
        XCTAssertLessThanOrEqual(score, 1.0)
    }

    // MARK: - Report Card Structure Tests

    func testReportCardHasAllFields() {
        let articles = makeArticles(count: 5, startDaysAgo: 0, gapDays: 1)
        let report = analyzer.analyze(
            feedName: "Test Feed",
            feedURL: "https://test.com/rss",
            articles: articles,
            now: now
        )
        XCTAssertEqual(report.feedName, "Test Feed")
        XCTAssertEqual(report.feedURL, "https://test.com/rss")
        XCTAssertFalse(report.recommendation.isEmpty)
        XCTAssertEqual(report.analyzedAt, now)
    }

    func testReportCardGradeMatchesScore() {
        let articles = makeArticles(count: 10, startDaysAgo: 0, gapDays: 1)
        let report = analyzer.analyze(feedName: "T", feedURL: "https://t.com", articles: articles, now: now)
        XCTAssertEqual(report.grade, FeedGrade.from(score: report.compositeScore))
    }
}
