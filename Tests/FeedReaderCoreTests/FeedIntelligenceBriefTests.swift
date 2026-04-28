//
//  FeedIntelligenceBriefTests.swift
//  FeedReaderCoreTests
//
//  Tests for the FeedIntelligenceBrief autonomous intelligence briefing engine.
//

import XCTest
@testable import FeedReaderCore

final class FeedIntelligenceBriefTests: XCTestCase {

    private var briefer: FeedIntelligenceBrief!

    override func setUp() {
        super.setUp()
        briefer = FeedIntelligenceBrief()
    }

    // MARK: - Helpers

    private func makeStory(
        title: String,
        body: String,
        link: String = "https://example.com/\(UUID().uuidString)"
    ) -> RSSStory {
        return RSSStory(title: title, body: body, link: link)!
    }

    private func makeTechStories(count: Int) -> [RSSStory] {
        return (0..<count).map { i in
            makeStory(
                title: "Apple launches new iPhone technology \(i)",
                body: "Apple announced new technology features for the iPhone including artificial intelligence capabilities.",
                link: "https://tech.example.com/article-\(i)"
            )
        }
    }

    private func makeHealthStories(count: Int) -> [RSSStory] {
        return (0..<count).map { i in
            makeStory(
                title: "Health researchers discover vaccine breakthrough \(i)",
                body: "Scientists researching health topics have made a breakthrough in vaccine development using clinical trials.",
                link: "https://health.example.com/article-\(i)"
            )
        }
    }

    private func makeSportsStories(count: Int) -> [RSSStory] {
        return (0..<count).map { i in
            makeStory(
                title: "Championship tournament results sports \(i)",
                body: "The championship tournament concluded with exciting sports results and athletic performances.",
                link: "https://sports.example.com/article-\(i)"
            )
        }
    }

    // MARK: - Brief Generation

    func testBriefRequiresMinimumArticles() {
        let stories = [makeStory(title: "Hello", body: "World of testing")]
        let brief = briefer.generateBrief(articles: stories)
        XCTAssertNil(brief, "Should return nil with too few articles")
    }

    func testBriefNilForEmptyArticles() {
        let brief = briefer.generateBrief(articles: [])
        XCTAssertNil(brief)
    }

    func testBriefGeneratesWithSufficientArticles() {
        let stories = makeTechStories(count: 6)
        let brief = briefer.generateBrief(articles: stories)
        XCTAssertNotNil(brief)
    }

    func testBriefContainsNarrativeThreads() {
        let stories = makeTechStories(count: 6)
        let brief = briefer.generateBrief(articles: stories)!
        XCTAssertFalse(brief.narrativeThreads.isEmpty, "Should detect at least one narrative thread")
    }

    func testBriefContainsTopKeywords() {
        let stories = makeTechStories(count: 6)
        let brief = briefer.generateBrief(articles: stories)!
        XCTAssertFalse(brief.topKeywords.isEmpty)
        XCTAssertTrue(brief.topKeywords.count <= 15)
    }

    func testBriefContainsSignalNoise() {
        let stories = makeTechStories(count: 6)
        let brief = briefer.generateBrief(articles: stories)!
        XCTAssertGreaterThan(brief.signalNoise.signalCount + brief.signalNoise.noiseCount, 0)
    }

    func testBriefCustomMinimumArticles() {
        briefer.minimumArticlesForBrief = 2
        let stories = [
            makeStory(title: "Test one apple technology", body: "Apple launches new technology product"),
            makeStory(title: "Test two apple technology", body: "Apple technology advancement announced")
        ]
        let brief = briefer.generateBrief(articles: stories)
        XCTAssertNotNil(brief)
    }

    // MARK: - Narrative Thread Detection

    func testNarrativeThreadsClustering() {
        let stories = makeTechStories(count: 4)
        let threads = briefer.detectNarrativeThreads(articles: stories)
        XCTAssertFalse(threads.isEmpty, "Similar articles should cluster into threads")
    }

    func testNarrativeThreadsNoOverlapNoClustering() {
        let stories = [
            makeStory(title: "Quantum physics breakthrough", body: "Scientists discovered new quantum phenomena"),
            makeStory(title: "Basketball championship results", body: "The Lakers won the championship tonight"),
            makeStory(title: "Cooking recipe pasta", body: "A delicious Italian pasta recipe with tomatoes"),
        ]
        let threads = briefer.detectNarrativeThreads(articles: stories)
        XCTAssertTrue(threads.isEmpty, "Unrelated articles should not cluster")
    }

    func testNarrativeThreadHeadline() {
        let stories = makeTechStories(count: 4)
        let threads = briefer.detectNarrativeThreads(articles: stories)
        guard let thread = threads.first else {
            XCTFail("Expected at least one thread")
            return
        }
        XCTAssertFalse(thread.headline.isEmpty)
    }

    func testNarrativeThreadKeywords() {
        let stories = makeTechStories(count: 4)
        let threads = briefer.detectNarrativeThreads(articles: stories)
        guard let thread = threads.first else {
            XCTFail("Expected at least one thread")
            return
        }
        XCTAssertFalse(thread.keywords.isEmpty)
        XCTAssertTrue(thread.keywords.count <= 5)
    }

    func testNarrativeThreadSortedByPriority() {
        var stories = makeTechStories(count: 6)
        stories.append(contentsOf: makeHealthStories(count: 3))
        let threads = briefer.detectNarrativeThreads(articles: stories)
        guard threads.count >= 2 else { return }
        // First thread should have equal or higher priority (lower rawValue)
        XCTAssertTrue(threads[0].priority <= threads[1].priority)
    }

    func testNarrativeThreadSourceCount() {
        let stories = makeTechStories(count: 4)
        let feedMap: [String: String] = Dictionary(
            uniqueKeysWithValues: stories.enumerated().map { idx, s in
                (s.link, idx % 2 == 0 ? "TechCrunch" : "Ars Technica")
            }
        )
        let threads = briefer.detectNarrativeThreads(articles: stories, feedMap: feedMap)
        guard let thread = threads.first else {
            XCTFail("Expected at least one thread")
            return
        }
        XCTAssertEqual(thread.sourceCount, 2)
    }

    // MARK: - Priority Classification

    func testPriorityCritical() {
        let priority = briefer.classifyPriority(articleCount: 10, sourceCount: 5, momentum: 1.0)
        XCTAssertEqual(priority, .critical)
    }

    func testPriorityHigh() {
        let priority = briefer.classifyPriority(articleCount: 6, sourceCount: 3, momentum: 0.5)
        XCTAssertEqual(priority, .high)
    }

    func testPriorityLow() {
        let priority = briefer.classifyPriority(articleCount: 1, sourceCount: 1, momentum: -0.5)
        XCTAssertEqual(priority, .low)
    }

    func testPriorityNoise() {
        let priority = briefer.classifyPriority(articleCount: 0, sourceCount: 0, momentum: -1.0)
        XCTAssertEqual(priority, .noise)
    }

    // MARK: - Signal / Noise

    func testSignalNoiseExcellent() {
        let threads = [
            NarrativeThread(id: "t1", headline: "Test", keywords: [], articleCount: 8,
                           sourceCount: 1, priority: .high, momentum: 0, firstSeen: Date(), articles: []),
        ]
        let verdict = briefer.computeSignalNoise(threads: threads, totalArticles: 10)
        XCTAssertEqual(verdict.grade, "Excellent")
        XCTAssertEqual(verdict.signalCount, 8)
        XCTAssertEqual(verdict.noiseCount, 2)
    }

    func testSignalNoiseCritical() {
        let verdict = briefer.computeSignalNoise(threads: [], totalArticles: 10)
        XCTAssertEqual(verdict.grade, "Critical")
        XCTAssertEqual(verdict.ratio, 0.0)
    }

    func testSignalNoiseZeroArticles() {
        let verdict = briefer.computeSignalNoise(threads: [], totalArticles: 0)
        XCTAssertEqual(verdict.grade, "Critical")
        XCTAssertEqual(verdict.ratio, 0.0)
    }

    func testSignalNoiseGood() {
        let threads = [
            NarrativeThread(id: "t1", headline: "Test", keywords: [], articleCount: 7,
                           sourceCount: 1, priority: .high, momentum: 0, firstSeen: Date(), articles: []),
        ]
        let verdict = briefer.computeSignalNoise(threads: threads, totalArticles: 10)
        XCTAssertEqual(verdict.grade, "Good")
    }

    func testSignalNoiseFair() {
        let threads = [
            NarrativeThread(id: "t1", headline: "Test", keywords: [], articleCount: 5,
                           sourceCount: 1, priority: .medium, momentum: 0, firstSeen: Date(), articles: []),
        ]
        let verdict = briefer.computeSignalNoise(threads: threads, totalArticles: 10)
        XCTAssertEqual(verdict.grade, "Fair")
    }

    // MARK: - Emerging Signals

    func testEmergingSignalsDetected() {
        let current: Set<String> = ["apple", "quantum", "blockchain", "climate"]
        let previous: Set<String> = ["apple", "climate"]
        let emerging = briefer.detectEmergingSignals(currentKeywords: current, previousKeywords: previous)
        XCTAssertTrue(emerging.contains("quantum"))
        XCTAssertTrue(emerging.contains("blockchain"))
        XCTAssertFalse(emerging.contains("apple"))
    }

    func testEmergingSignalsEmptyWhenNoPrevious() {
        let current: Set<String> = ["apple", "quantum"]
        let emerging = briefer.detectEmergingSignals(currentKeywords: current, previousKeywords: [])
        XCTAssertTrue(emerging.isEmpty, "No emerging signals without a baseline")
    }

    func testEmergingSignalsSorted() {
        let current: Set<String> = ["zebra", "alpha", "middle"]
        let previous: Set<String> = ["other"]
        let emerging = briefer.detectEmergingSignals(currentKeywords: current, previousKeywords: previous)
        XCTAssertEqual(emerging, emerging.sorted())
    }

    // MARK: - Cross-Feed Correlations

    func testCrossFeedCorrelations() {
        let stories = [
            makeStory(title: "Apple technology innovation", body: "Apple technology product launch innovation", link: "https://a.com/1"),
            makeStory(title: "Apple technology review", body: "Review of Apple technology innovation product", link: "https://b.com/1"),
        ]
        let feedMap = ["https://a.com/1": "TechCrunch", "https://b.com/1": "Ars Technica"]
        let correlations = briefer.findCrossFeedCorrelations(articles: stories, feedMap: feedMap)
        XCTAssertFalse(correlations.isEmpty)
        // At least one keyword should span both feeds
        XCTAssertTrue(correlations.contains { $0.feedNames.count >= 2 })
    }

    func testCrossFeedCorrelationsEmptyWithoutFeedMap() {
        let stories = makeTechStories(count: 3)
        let correlations = briefer.findCrossFeedCorrelations(articles: stories, feedMap: [:])
        XCTAssertTrue(correlations.isEmpty)
    }

    // MARK: - Blind Spot Detection

    func testBlindSpotsDetected() {
        let keywords: Set<String> = ["technology", "science"]
        let blindSpots = briefer.detectBlindSpots(keywords: keywords)
        XCTAssertTrue(blindSpots.contains("sports"))
        XCTAssertTrue(blindSpots.contains("politics"))
        XCTAssertFalse(blindSpots.contains("technology"))
        XCTAssertFalse(blindSpots.contains("science"))
    }

    func testBlindSpotsAllCovered() {
        let keywords = Set(FeedIntelligenceBrief.newsCategories)
        let blindSpots = briefer.detectBlindSpots(keywords: keywords)
        XCTAssertTrue(blindSpots.isEmpty)
    }

    func testBlindSpotsNoneCovered() {
        let blindSpots = briefer.detectBlindSpots(keywords: [])
        XCTAssertEqual(blindSpots.count, FeedIntelligenceBrief.newsCategories.count)
    }

    // MARK: - Executive Summary

    func testExecutiveSummaryWithThreads() {
        let threads = [
            NarrativeThread(id: "t1", headline: "Apple / Technology", keywords: ["apple"],
                           articleCount: 5, sourceCount: 2, priority: .high, momentum: 0.5,
                           firstSeen: Date(), articles: []),
        ]
        let sn = SignalNoiseVerdict(signalCount: 5, noiseCount: 2, ratio: 0.71, grade: "Good")
        let summary = briefer.generateExecutiveSummary(threads: threads, signalNoise: sn, emergingCount: 3)
        XCTAssertTrue(summary.contains("Apple / Technology"))
        XCTAssertTrue(summary.contains("Good"))
        XCTAssertTrue(summary.contains("3 new signals"))
    }

    func testExecutiveSummaryNoThreads() {
        let sn = SignalNoiseVerdict(signalCount: 0, noiseCount: 5, ratio: 0, grade: "Critical")
        let summary = briefer.generateExecutiveSummary(threads: [], signalNoise: sn, emergingCount: 0)
        XCTAssertTrue(summary.contains("no dominant narrative"))
    }

    func testExecutiveSummarySingularNarrative() {
        let threads = [
            NarrativeThread(id: "t1", headline: "Test", keywords: [],
                           articleCount: 3, sourceCount: 1, priority: .medium, momentum: 0,
                           firstSeen: Date(), articles: []),
        ]
        let sn = SignalNoiseVerdict(signalCount: 3, noiseCount: 2, ratio: 0.6, grade: "Good")
        let summary = briefer.generateExecutiveSummary(threads: threads, signalNoise: sn, emergingCount: 0)
        XCTAssertTrue(summary.contains("1 active narrative."))
    }

    // MARK: - Actionable Insights

    func testInsightsAcceleratingThread() {
        let threads = [
            NarrativeThread(id: "t1", headline: "AI Boom", keywords: ["ai"],
                           articleCount: 5, sourceCount: 2, priority: .high, momentum: 0.8,
                           firstSeen: Date(), articles: []),
        ]
        let sn = SignalNoiseVerdict(signalCount: 5, noiseCount: 0, ratio: 1.0, grade: "Excellent")
        let insights = briefer.generateActionableInsights(threads: threads, emerging: [], signalNoise: sn)
        XCTAssertTrue(insights.contains { $0.contains("accelerating") })
    }

    func testInsightsEmergingSignals() {
        let sn = SignalNoiseVerdict(signalCount: 5, noiseCount: 0, ratio: 1.0, grade: "Excellent")
        let insights = briefer.generateActionableInsights(threads: [], emerging: ["quantum"], signalNoise: sn)
        XCTAssertTrue(insights.contains { $0.contains("quantum") && $0.contains("🆕") })
    }

    func testInsightsHighNoise() {
        let sn = SignalNoiseVerdict(signalCount: 1, noiseCount: 9, ratio: 0.1, grade: "Critical")
        let insights = briefer.generateActionableInsights(threads: [], emerging: [], signalNoise: sn)
        XCTAssertTrue(insights.contains { $0.contains("pruning") })
    }

    func testInsightsBlindSpots() {
        let sn = SignalNoiseVerdict(signalCount: 5, noiseCount: 0, ratio: 1.0, grade: "Excellent")
        let insights = briefer.generateActionableInsights(
            threads: [], emerging: [], signalNoise: sn,
            blindSpots: ["sports", "entertainment"]
        )
        XCTAssertTrue(insights.contains { $0.contains("No coverage") })
    }

    func testInsightsCrossFeedTrending() {
        let sn = SignalNoiseVerdict(signalCount: 5, noiseCount: 0, ratio: 1.0, grade: "Excellent")
        let corr = [CrossFeedCorrelation(keyword: "climate", feedNames: ["BBC", "NPR", "Reuters"], count: 5)]
        let insights = briefer.generateActionableInsights(
            threads: [], emerging: [], signalNoise: sn, correlations: corr
        )
        XCTAssertTrue(insights.contains { $0.contains("climate") && $0.contains("3 feeds") })
    }

    func testInsightsFadingThread() {
        let threads = [
            NarrativeThread(id: "t1", headline: "Old Story", keywords: ["old"],
                           articleCount: 3, sourceCount: 1, priority: .low, momentum: -0.8,
                           firstSeen: Date(), articles: []),
        ]
        let sn = SignalNoiseVerdict(signalCount: 3, noiseCount: 2, ratio: 0.6, grade: "Good")
        let insights = briefer.generateActionableInsights(threads: threads, emerging: [], signalNoise: sn)
        XCTAssertTrue(insights.contains { $0.contains("fading") })
    }

    // MARK: - Intelligence Priority

    func testPriorityOrdering() {
        XCTAssertTrue(IntelligencePriority.critical < IntelligencePriority.high)
        XCTAssertTrue(IntelligencePriority.high < IntelligencePriority.medium)
        XCTAssertTrue(IntelligencePriority.medium < IntelligencePriority.low)
        XCTAssertTrue(IntelligencePriority.low < IntelligencePriority.noise)
    }

    func testPriorityEmoji() {
        XCTAssertEqual(IntelligencePriority.critical.emoji, "🔴")
        XCTAssertEqual(IntelligencePriority.noise.emoji, "⚪")
    }

    func testPriorityDisplayName() {
        XCTAssertEqual(IntelligencePriority.critical.displayName, "Critical")
        XCTAssertEqual(IntelligencePriority.noise.displayName, "Noise")
    }

    // MARK: - Edge Cases

    func testSingleArticleBelowMinimum() {
        let brief = briefer.generateBrief(articles: [
            makeStory(title: "Solo article", body: "This is the only article")
        ])
        XCTAssertNil(brief)
    }

    func testAllIdenticalArticles() {
        let stories = (0..<6).map { i in
            makeStory(
                title: "Identical headline technology apple",
                body: "Identical body about apple technology innovation",
                link: "https://example.com/identical-\(i)"
            )
        }
        let brief = briefer.generateBrief(articles: stories)
        XCTAssertNotNil(brief)
        XCTAssertFalse(brief!.narrativeThreads.isEmpty, "Identical articles should cluster")
    }

    func testMixedTopicsBrief() {
        var stories = makeTechStories(count: 4)
        stories.append(contentsOf: makeHealthStories(count: 3))
        let brief = briefer.generateBrief(articles: stories)
        XCTAssertNotNil(brief)
        // Should have threads for both tech and health
        XCTAssertGreaterThanOrEqual(brief!.narrativeThreads.count, 1)
    }

    func testMaxNarrativeThreadsRespected() {
        briefer.maxNarrativeThreads = 2
        var stories = makeTechStories(count: 4)
        stories.append(contentsOf: makeHealthStories(count: 4))
        stories.append(contentsOf: makeSportsStories(count: 4))
        let brief = briefer.generateBrief(articles: stories)
        XCTAssertNotNil(brief)
        XCTAssertLessThanOrEqual(brief!.narrativeThreads.count, 2)
    }
}
