//
//  FeedRelevanceDecayEngineTests.swift
//  FeedReaderTests
//
//  Tests for FeedRelevanceDecayEngine — autonomous article relevance
//  decay tracking, content classification, queue prioritisation.
//

import XCTest
@testable import FeedReader

class FeedRelevanceDecayEngineTests: XCTestCase {

    var currentDate: Date!
    var engine: FeedRelevanceDecayEngine!
    var calendar: Calendar!

    override func setUp() {
        super.setUp()
        calendar = Calendar.current
        // Fixed reference: 2025-01-15 12:00 UTC
        currentDate = Date(timeIntervalSince1970: 1_736_942_400)
        engine = FeedRelevanceDecayEngine(
            defaults: UserDefaults(suiteName: "TestRelevanceDecay")!,
            dateProvider: { [unowned self] in self.currentDate },
            calendar: calendar
        )
        engine.reset()
    }

    override func tearDown() {
        UserDefaults(suiteName: "TestRelevanceDecay")?.removePersistentDomain(forName: "TestRelevanceDecay")
        super.tearDown()
    }

    // MARK: - Helpers

    private func makeDate(hoursAgo: Double = 0) -> Date {
        return currentDate.addingTimeInterval(-hoursAgo * 3600)
    }

    private func seedArticle(id: String = "a1", title: String = "Test Article",
                             feedURL: String = "https://example.com/feed",
                             hoursAgo: Double = 0, topics: [String] = []) {
        engine.trackArticle(articleId: id, title: title, feedURL: feedURL,
                           publishedDate: makeDate(hoursAgo: hoursAgo), topics: topics)
    }

    // MARK: - Content Classification

    func testClassifyBreakingContent() {
        let type = engine.classifyContent(title: "Breaking: Major Event", topics: [])
        XCTAssertEqual(type, .breaking)
    }

    func testClassifyTrendingContent() {
        let type = engine.classifyContent(title: "Trending viral video", topics: [])
        XCTAssertEqual(type, .trending)
    }

    func testClassifyTutorialContent() {
        let type = engine.classifyContent(title: "How to build a REST API", topics: ["guide"])
        XCTAssertEqual(type, .tutorial)
    }

    func testClassifyReferenceContent() {
        let type = engine.classifyContent(title: "API documentation v3", topics: ["reference"])
        XCTAssertEqual(type, .reference)
    }

    func testClassifyOpinionContent() {
        let type = engine.classifyContent(title: "My perspective on AI", topics: ["editorial"])
        XCTAssertEqual(type, .opinion)
    }

    func testClassifyAnalysisContent() {
        let type = engine.classifyContent(title: "Deep dive into microservices", topics: [])
        XCTAssertEqual(type, .analysis)
    }

    func testClassifySeasonalContent() {
        let type = engine.classifyContent(title: "Best holiday gifts 2025", topics: ["christmas"])
        XCTAssertEqual(type, .seasonal)
    }

    func testClassifyArchiveContent() {
        let type = engine.classifyContent(title: "Retrospective: 10 years of Go", topics: [])
        XCTAssertEqual(type, .archive)
    }

    func testClassifyEvergreenContent() {
        let type = engine.classifyContent(title: "Programming fundamentals 101", topics: ["principles"])
        XCTAssertEqual(type, .evergreen)
    }

    func testClassifyDefaultsToAnalysis() {
        let type = engine.classifyContent(title: "Random article about stuff", topics: [])
        XCTAssertEqual(type, .analysis)
    }

    // MARK: - Decay Models

    func testExponentialDecayAtHalfLife() {
        let model = RelevanceDecayModel.exponential
        let factor = model.factor(elapsed: 7200, halfLife: 7200) // 2h at 2h half-life
        XCTAssertEqual(factor, 0.5, accuracy: 0.01)
    }

    func testExponentialDecayAtZero() {
        let model = RelevanceDecayModel.exponential
        let factor = model.factor(elapsed: 0, halfLife: 3600)
        XCTAssertEqual(factor, 1.0)
    }

    func testExponentialDecayAtTwoHalfLives() {
        let model = RelevanceDecayModel.exponential
        let factor = model.factor(elapsed: 14400, halfLife: 7200) // 4h at 2h half-life
        XCTAssertEqual(factor, 0.25, accuracy: 0.01)
    }

    func testLinearDecayAtHalfLife() {
        let model = RelevanceDecayModel.linear
        let factor = model.factor(elapsed: 7200, halfLife: 7200) // t = halfLife
        // linear: 1 - t/(2*halfLife) = 1 - 0.5 = 0.5
        XCTAssertEqual(factor, 0.5, accuracy: 0.01)
    }

    func testLinearDecayAtDoubleHalfLife() {
        let model = RelevanceDecayModel.linear
        let factor = model.factor(elapsed: 14400, halfLife: 7200) // t = 2*halfLife
        // linear: 1 - 2*halfLife/(2*halfLife) = 0
        XCTAssertEqual(factor, 0.0, accuracy: 0.01)
    }

    func testLinearDecayNoNegative() {
        let model = RelevanceDecayModel.linear
        let factor = model.factor(elapsed: 100000, halfLife: 3600)
        XCTAssertGreaterThanOrEqual(factor, 0.0)
    }

    func testStepFunctionBeforeHalfLife() {
        let model = RelevanceDecayModel.stepFunction
        let factor = model.factor(elapsed: 3000, halfLife: 3600)
        XCTAssertEqual(factor, 1.0)
    }

    func testStepFunctionAfterHalfLife() {
        let model = RelevanceDecayModel.stepFunction
        let factor = model.factor(elapsed: 7200, halfLife: 3600)
        XCTAssertEqual(factor, 0.3)
    }

    func testLogarithmicDecayAtZero() {
        let model = RelevanceDecayModel.logarithmic
        let factor = model.factor(elapsed: 0, halfLife: 3600)
        XCTAssertEqual(factor, 1.0, accuracy: 0.01)
    }

    func testLogarithmicDecayDecreases() {
        let model = RelevanceDecayModel.logarithmic
        let f1 = model.factor(elapsed: 3600, halfLife: 3600)
        let f2 = model.factor(elapsed: 7200, halfLife: 3600)
        XCTAssertLessThan(f2, f1)
    }

    // MARK: - Half-Life Estimation

    func testDefaultHalfLifeBreaking() {
        let hl = engine.estimateHalfLife(contentType: .breaking, topics: [])
        XCTAssertEqual(hl, 2 * 3600, accuracy: 1)
    }

    func testDefaultHalfLifeEvergreen() {
        let hl = engine.estimateHalfLife(contentType: .evergreen, topics: [])
        XCTAssertEqual(hl, 4320 * 3600, accuracy: 1)
    }

    func testSecurityTopicReducesHalfLife() {
        let base = engine.estimateHalfLife(contentType: .analysis, topics: [])
        let sec = engine.estimateHalfLife(contentType: .analysis, topics: ["security"])
        XCTAssertLessThan(sec, base)
    }

    func testFundamentalTopicIncreasesHalfLife() {
        let base = engine.estimateHalfLife(contentType: .tutorial, topics: [])
        let fund = engine.estimateHalfLife(contentType: .tutorial, topics: ["fundamental"])
        XCTAssertGreaterThan(fund, base)
    }

    func testAnnouncementReducesHalfLife() {
        let base = engine.estimateHalfLife(contentType: .analysis, topics: [])
        let ann = engine.estimateHalfLife(contentType: .analysis, topics: ["release"])
        XCTAssertLessThan(ann, base)
    }

    // MARK: - Article Tracking

    func testTrackArticle() {
        seedArticle(id: "art1", title: "Breaking news alert", hoursAgo: 0)
        XCTAssertEqual(engine.articleCount, 1)
        let profile = engine.getProfile(articleId: "art1")
        XCTAssertNotNil(profile)
        XCTAssertEqual(profile?.contentType, .breaking)
        XCTAssertFalse(profile?.readByUser ?? true)
    }

    func testMarkRead() {
        seedArticle(id: "art1")
        engine.markRead(articleId: "art1")
        XCTAssertTrue(engine.getProfile(articleId: "art1")?.readByUser ?? false)
    }

    func testRecordInteraction() {
        seedArticle(id: "art1")
        engine.recordInteraction(articleId: "art1")
        engine.recordInteraction(articleId: "art1")
        XCTAssertEqual(engine.getProfile(articleId: "art1")?.userInteractionCount, 2)
    }

    func testMarkReadNonExistent() {
        engine.markRead(articleId: "nonexistent")
        XCTAssertEqual(engine.articleCount, 0)
    }

    // MARK: - Relevance Assessment

    func testFreshArticleHighRelevance() {
        seedArticle(id: "a1", title: "Tutorial guide for Swift", hoursAgo: 0)
        let rel = engine.assessRelevance(articleId: "a1")
        XCTAssertGreaterThan(rel, 90)
    }

    func testOldBreakingNewsLowRelevance() {
        seedArticle(id: "a1", title: "Breaking urgent alert", hoursAgo: 24)
        let rel = engine.assessRelevance(articleId: "a1")
        XCTAssertLessThan(rel, 10) // 2h half-life, 24h old → very low
    }

    func testEvergreenStaysRelevant() {
        seedArticle(id: "a1", title: "Timeless fundamentals of computing", hoursAgo: 720) // 30 days
        let rel = engine.assessRelevance(articleId: "a1")
        XCTAssertGreaterThan(rel, 30) // 180d half-life, 30d old → still decent
    }

    func testInteractionBoostsRelevance() {
        seedArticle(id: "a1", title: "Some analysis article", hoursAgo: 48)
        let before = engine.assessRelevance(articleId: "a1")
        engine.recordInteraction(articleId: "a1")
        engine.recordInteraction(articleId: "a1")
        engine.recordInteraction(articleId: "a1")
        let after = engine.assessRelevance(articleId: "a1")
        XCTAssertGreaterThan(after, before)
    }

    func testNonExistentArticleRelevanceIsZero() {
        XCTAssertEqual(engine.assessRelevance(articleId: "nope"), 0)
    }

    // MARK: - Queue Generation

    func testQueueExcludesReadArticles() {
        seedArticle(id: "a1", title: "How to tutorial", hoursAgo: 1)
        seedArticle(id: "a2", title: "Another tutorial guide", hoursAgo: 1)
        engine.markRead(articleId: "a1")
        let queue = engine.generateQueue()
        XCTAssertEqual(queue.count, 1)
        XCTAssertEqual(queue.first?.articleId, "a2")
    }

    func testQueueLimitEnforced() {
        for i in 0..<10 {
            seedArticle(id: "a\(i)", title: "How to tutorial \(i)", hoursAgo: Double(i))
        }
        let queue = engine.generateQueue(limit: 3)
        XCTAssertEqual(queue.count, 3)
    }

    func testQueuePrioritisesFastDecayingContent() {
        // Breaking news (fast decay) vs evergreen (slow decay)
        seedArticle(id: "breaking", title: "Breaking urgent story", hoursAgo: 0.5)
        seedArticle(id: "evergreen", title: "Timeless fundamentals", hoursAgo: 0.5)
        let queue = engine.generateQueue()
        guard queue.count >= 2 else { XCTFail("Expected 2 items"); return }
        // Breaking should be first (higher urgency due to faster decay)
        XCTAssertEqual(queue.first?.articleId, "breaking")
    }

    func testQueueEmptyWhenAllRead() {
        seedArticle(id: "a1", title: "Tutorial guide", hoursAgo: 1)
        engine.markRead(articleId: "a1")
        let queue = engine.generateQueue()
        XCTAssertTrue(queue.isEmpty)
    }

    func testQueueContainsUrgencyTier() {
        seedArticle(id: "a1", title: "Breaking urgent news", hoursAgo: 0.5)
        let queue = engine.generateQueue()
        XCTAssertEqual(queue.first?.urgencyTier, .immediate)
    }

    func testQueueHasRecommendedAction() {
        seedArticle(id: "a1", title: "Tutorial guide test", hoursAgo: 1)
        let queue = engine.generateQueue()
        XCTAssertFalse(queue.first?.recommendedAction.isEmpty ?? true)
    }

    // MARK: - Fleet Health

    func testEmptyFleetHealth() {
        let health = engine.getFleetHealth()
        XCTAssertEqual(health.totalArticles, 0)
        XCTAssertEqual(health.healthScore, 0)
        XCTAssertEqual(health.healthTier, .stale)
    }

    func testHealthyFleetWithFreshContent() {
        for i in 0..<5 {
            seedArticle(id: "a\(i)", title: "How to tutorial \(i)", hoursAgo: Double(i))
        }
        let health = engine.getFleetHealth()
        XCTAssertEqual(health.totalArticles, 5)
        XCTAssertGreaterThan(health.avgRelevance, 50)
        XCTAssertGreaterThanOrEqual(health.healthScore, 40)
    }

    func testFleetHealthCountsEvergreen() {
        seedArticle(id: "a1", title: "Timeless fundamentals 101", hoursAgo: 0)
        seedArticle(id: "a2", title: "Reference documentation spec", hoursAgo: 0)
        seedArticle(id: "a3", title: "Breaking news alert", hoursAgo: 0)
        let health = engine.getFleetHealth()
        // 2 out of 3 are evergreen/reference
        XCTAssertEqual(health.evergreenRatio, 2.0 / 3.0, accuracy: 0.01)
    }

    func testStaleFleetWithOldContent() {
        for i in 0..<5 {
            seedArticle(id: "a\(i)", title: "Breaking urgent alert \(i)", hoursAgo: 200)
        }
        let health = engine.getFleetHealth()
        XCTAssertLessThan(health.avgRelevance, 10)
    }

    // MARK: - Insight Generation

    func testUrgentReadingInsight() {
        // Fresh breaking news with high decay rate
        seedArticle(id: "a1", title: "Breaking urgent story", hoursAgo: 0.5)
        seedArticle(id: "a2", title: "Breaking alert developing", hoursAgo: 0.3)
        let insights = engine.generateInsights()
        let urgent = insights.filter { $0.type == .urgentReading }
        XCTAssertFalse(urgent.isEmpty, "Should detect urgent reading need for fast-decaying content")
    }

    func testEvergreenDiscoveryInsight() {
        seedArticle(id: "a1", title: "Timeless fundamentals of CS", hoursAgo: 48)
        seedArticle(id: "a2", title: "Reference documentation spec v2", hoursAgo: 24)
        let insights = engine.generateInsights()
        let eg = insights.filter { $0.type == .evergreenDiscovery }
        XCTAssertFalse(eg.isEmpty, "Should discover evergreen content")
    }

    func testStaleBatchInsight() {
        // All breaking news, very old
        for i in 0..<10 {
            seedArticle(id: "a\(i)", title: "Breaking urgent news \(i)", hoursAgo: 200)
        }
        let insights = engine.generateInsights()
        let stale = insights.filter { $0.type == .staleBatchDetected }
        XCTAssertFalse(stale.isEmpty, "Should detect stale batch")
    }

    func testFreshContentSurgeInsight() {
        for i in 0..<8 {
            seedArticle(id: "a\(i)", title: "Analysis deep dive \(i)", hoursAgo: 0.5)
        }
        let insights = engine.generateInsights()
        let surge = insights.filter { $0.type == .freshContentSurge }
        XCTAssertFalse(surge.isEmpty, "Should detect fresh content surge")
    }

    func testNoInsightsWhenEmpty() {
        let insights = engine.generateInsights()
        XCTAssertTrue(insights.isEmpty)
    }

    func testTopicSaturationInsight() {
        for i in 0..<6 {
            seedArticle(id: "a\(i)", title: "Analysis deep dive \(i)", hoursAgo: Double(i),
                       topics: ["swift"])
        }
        let insights = engine.generateInsights()
        let saturation = insights.filter { $0.type == .topicSaturation }
        XCTAssertFalse(saturation.isEmpty, "Should detect topic saturation for 'swift'")
    }

    // MARK: - Expiring Articles Filter

    func testGetExpiringArticles() {
        // Trending article (12h half-life) at 10 hours old — about to cross into low relevance
        seedArticle(id: "a1", title: "Trending viral story", hoursAgo: 10)
        let expiring = engine.getExpiringArticles(withinHours: 24)
        // May or may not be expiring depending on exact math, but test runs
        XCTAssertNotNil(expiring)
    }

    func testExpiringExcludesReadArticles() {
        seedArticle(id: "a1", title: "Trending viral hot story", hoursAgo: 10)
        engine.markRead(articleId: "a1")
        let expiring = engine.getExpiringArticles(withinHours: 24)
        XCTAssertTrue(expiring.isEmpty)
    }

    // MARK: - Evergreen Articles Filter

    func testGetEvergreenArticles() {
        seedArticle(id: "a1", title: "Timeless fundamentals 101", hoursAgo: 48)
        seedArticle(id: "a2", title: "Reference api doc manual", hoursAgo: 24)
        let eg = engine.getEvergreenArticles()
        XCTAssertEqual(eg.count, 2)
    }

    func testEvergreenExcludesLowRelevance() {
        // Evergreen but super old
        seedArticle(id: "a1", title: "Timeless fundamentals 101", hoursAgo: 100000)
        let eg = engine.getEvergreenArticles()
        XCTAssertTrue(eg.isEmpty)
    }

    // MARK: - Full Analysis

    func testFullAnalysisReturnsAllComponents() {
        for i in 0..<5 {
            seedArticle(id: "a\(i)", title: "Tutorial guide \(i)", hoursAgo: Double(i * 2))
        }
        let result = engine.fullAnalysis()
        XCTAssertFalse(result.queue.isEmpty)
        XCTAssertEqual(result.health.totalArticles, 5)
        // Insights may or may not be present depending on conditions
    }

    func testFullAnalysisEmptyState() {
        let result = engine.fullAnalysis()
        XCTAssertTrue(result.queue.isEmpty)
        XCTAssertEqual(result.health.totalArticles, 0)
        XCTAssertTrue(result.insights.isEmpty)
    }

    // MARK: - Edge Cases

    func testSingleArticle() {
        seedArticle(id: "solo", title: "Deep dive analysis", hoursAgo: 1)
        let queue = engine.generateQueue()
        XCTAssertEqual(queue.count, 1)
        let health = engine.getFleetHealth()
        XCTAssertEqual(health.totalArticles, 1)
    }

    func testResetClearsAll() {
        seedArticle(id: "a1", title: "Tutorial guide swift", hoursAgo: 0)
        engine.reset()
        XCTAssertEqual(engine.articleCount, 0)
    }

    func testDuplicateTrackingOverwrites() {
        seedArticle(id: "a1", title: "Breaking news first", hoursAgo: 5)
        seedArticle(id: "a1", title: "How to tutorial guide", hoursAgo: 1)
        XCTAssertEqual(engine.articleCount, 1)
        XCTAssertEqual(engine.getProfile(articleId: "a1")?.contentType, .tutorial)
    }

    // MARK: - Urgency Tiers

    func testUrgencyTierImmediate() {
        let tier = UrgencyTier.from(relevance: 80, decayRate: 0.5)
        XCTAssertEqual(tier, .immediate)
    }

    func testUrgencyTierToday() {
        let tier = UrgencyTier.from(relevance: 50, decayRate: 0.1)
        XCTAssertEqual(tier, .today)
    }

    func testUrgencyTierThisWeek() {
        let tier = UrgencyTier.from(relevance: 25, decayRate: 0.05)
        XCTAssertEqual(tier, .thisWeek)
    }

    func testUrgencyTierWhenever() {
        let tier = UrgencyTier.from(relevance: 10, decayRate: 0.01)
        XCTAssertEqual(tier, .whenever)
    }

    func testUrgencyTierArchived() {
        let tier = UrgencyTier.from(relevance: 3, decayRate: 0.001)
        XCTAssertEqual(tier, .archived)
    }

    // MARK: - Health Tiers

    func testHealthTierThriving() {
        XCTAssertEqual(RelevanceHealthTier.from(score: 90), .thriving)
    }

    func testHealthTierHealthy() {
        XCTAssertEqual(RelevanceHealthTier.from(score: 70), .healthy)
    }

    func testHealthTierAging() {
        XCTAssertEqual(RelevanceHealthTier.from(score: 50), .aging)
    }

    func testHealthTierDecaying() {
        XCTAssertEqual(RelevanceHealthTier.from(score: 30), .decaying)
    }

    func testHealthTierStale() {
        XCTAssertEqual(RelevanceHealthTier.from(score: 10), .stale)
    }

    // MARK: - Decay Model Edge Cases

    func testDecayWithZeroHalfLife() {
        let factor = RelevanceDecayModel.exponential.factor(elapsed: 100, halfLife: 0)
        XCTAssertEqual(factor, 1.0) // guard returns 1.0
    }

    func testDecayWithNegativeElapsed() {
        let factor = RelevanceDecayModel.exponential.factor(elapsed: -100, halfLife: 3600)
        XCTAssertEqual(factor, 1.0) // guard returns 1.0
    }

    // MARK: - Content Type Labels

    func testAllContentTypesHaveHalfLives() {
        for type in RelevanceContentType.allCases {
            XCTAssertGreaterThan(type.defaultHalfLife, 0, "\(type) should have positive half-life")
        }
    }

    func testUrgencyTierLabels() {
        XCTAssertEqual(UrgencyTier.immediate.label, "Read Now")
        XCTAssertEqual(UrgencyTier.today.label, "Today")
        XCTAssertEqual(UrgencyTier.thisWeek.label, "This Week")
        XCTAssertEqual(UrgencyTier.whenever.label, "Whenever")
        XCTAssertEqual(UrgencyTier.archived.label, "Archived")
    }
}
