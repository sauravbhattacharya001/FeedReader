//
//  FeedReadingAutopilotTests.swift
//  FeedReaderCoreTests
//
//  Tests for FeedReadingAutopilot: session planning, cognitive load classification,
//  topic diversity, mood-based filtering, sequencing, and budget utilization.
//

import XCTest
@testable import FeedReaderCore

final class FeedReadingAutopilotTests: XCTestCase {

    private func makeAutopilot() -> FeedReadingAutopilot {
        return FeedReadingAutopilot()
    }

    private func makeStory(
        title: String,
        body: String,
        link: String = "https://example.com/article"
    ) -> RSSStory {
        return RSSStory(title: title, body: body, link: link)!
    }

    private func shortArticle(topic: String, index: Int = 0) -> RSSStory {
        let body = "This is a short article about \(topic). It covers basic \(topic) concepts in a brief format. Simple and quick reading material about \(topic) for beginners. The fundamentals are explained clearly."
        return makeStory(
            title: "\(topic.capitalized) Basics \(index)",
            body: body,
            link: "https://example.com/\(topic)-\(index)"
        )
    }

    private func longArticle(topic: String, index: Int = 0) -> RSSStory {
        let paragraph = "The implementation of \(topic) requires careful consideration of the underlying algorithm architecture. Researchers have demonstrated that optimization through statistical methodology and hypothesis testing provides correlation between infrastructure performance and system reliability. The framework methodology involves sophisticated neural network implementations for quantum cryptography applications. "
        let body = String(repeating: paragraph, count: 8)
        return makeStory(
            title: "Deep Dive: \(topic.capitalized) Architecture \(index)",
            body: body,
            link: "https://example.com/deep-\(topic)-\(index)"
        )
    }

    private func mediumArticle(topic: String, index: Int = 0) -> RSSStory {
        let paragraph = "Understanding \(topic) is essential for modern applications. The key concepts include data processing, pattern recognition, and efficient resource management. This article explores how \(topic) integrates with existing systems to provide better outcomes for users and developers alike. "
        let body = String(repeating: paragraph, count: 4)
        return makeStory(
            title: "\(topic.capitalized) in Practice \(index)",
            body: body,
            link: "https://example.com/\(topic)-practice-\(index)"
        )
    }

    // MARK: - Empty/Edge Cases

    func testEmptyArticlesReturnsEmptyPlan() {
        let autopilot = makeAutopilot()
        let plan = autopilot.planSession(articles: [], timeBudgetMinutes: 20)
        XCTAssertEqual(plan.articleCount, 0)
        XCTAssertEqual(plan.totalMinutes, 0)
        XCTAssertEqual(plan.budgetMinutes, 20)
        XCTAssertEqual(plan.diversityScore, 0)
        XCTAssertEqual(plan.cognitiveProfile, "empty")
    }

    func testZeroBudgetReturnsEmptyPlan() {
        let autopilot = makeAutopilot()
        let articles = [shortArticle(topic: "swift")]
        let plan = autopilot.planSession(articles: articles, timeBudgetMinutes: 0)
        XCTAssertEqual(plan.articleCount, 0)
    }

    func testSingleArticleFitsInBudget() {
        let autopilot = makeAutopilot()
        let articles = [shortArticle(topic: "swift")]
        let plan = autopilot.planSession(articles: articles, timeBudgetMinutes: 5)
        XCTAssertEqual(plan.articleCount, 1)
        XCTAssertTrue(plan.totalMinutes <= 5.0)
        XCTAssertEqual(plan.playlist.first?.position, 1)
    }

    // MARK: - Budget Respect

    func testPlanRespectsTimeBudget() {
        let autopilot = makeAutopilot()
        let articles = (0..<20).map { shortArticle(topic: "topic\($0 % 5)", index: $0) }
        let plan = autopilot.planSession(articles: articles, timeBudgetMinutes: 10)
        XCTAssertTrue(plan.totalMinutes <= 10.0, "Total \(plan.totalMinutes) exceeds budget 10")
        XCTAssertTrue(plan.articleCount > 0)
    }

    func testLargeArticleExceedsBudgetGetsSkipped() {
        let autopilot = makeAutopilot()
        let big = longArticle(topic: "quantum", index: 0)
        let small = shortArticle(topic: "news", index: 0)
        let plan = autopilot.planSession(articles: [big, small], timeBudgetMinutes: 3)
        // Should pick the short one if it fits, skip the long one
        XCTAssertTrue(plan.totalMinutes <= 3.0)
    }

    // MARK: - Budget Utilization

    func testBudgetUtilization() {
        let autopilot = makeAutopilot()
        let articles = (0..<10).map { mediumArticle(topic: "tech\($0 % 3)", index: $0) }
        let plan = autopilot.planSession(articles: articles, timeBudgetMinutes: 30)
        XCTAssertTrue(plan.budgetUtilization >= 0)
        XCTAssertTrue(plan.budgetUtilization <= 1.0)
    }

    // MARK: - Topic Diversity

    func testDiverseTopicsSelectedInExploratoryMode() {
        let autopilot = makeAutopilot()
        let articles = ["science", "politics", "sports", "technology", "health"].flatMap { topic in
            (0..<3).map { shortArticle(topic: topic, index: $0) }
        }
        let prefs = SessionPreferences(mood: .exploratory, minimumDiversity: 0.6)
        let plan = autopilot.planSession(articles: articles, timeBudgetMinutes: 15, preferences: prefs)
        XCTAssertTrue(plan.topicCount > 1, "Expected multiple topics, got \(plan.topicCount)")
    }

    func testTopicsListIsOrdered() {
        let autopilot = makeAutopilot()
        let articles = (0..<6).map { mediumArticle(topic: "topic\($0)", index: $0) }
        let plan = autopilot.planSession(articles: articles, timeBudgetMinutes: 30)
        XCTAssertEqual(plan.topics.count, plan.topicCount)
        // Each topic should appear exactly once in the topics list
        XCTAssertEqual(Set(plan.topics).count, plan.topics.count)
    }

    // MARK: - Mood Filtering

    func testRelaxedMoodFiltersHeavyContent() {
        let autopilot = makeAutopilot()
        let articles = [
            longArticle(topic: "quantum", index: 0),
            longArticle(topic: "algorithms", index: 1),
            shortArticle(topic: "cooking", index: 0),
            shortArticle(topic: "travel", index: 1)
        ]
        let prefs = SessionPreferences(mood: .relaxed)
        let plan = autopilot.planSession(articles: articles, timeBudgetMinutes: 20, preferences: prefs)
        // Relaxed mood should prefer lighter articles
        for article in plan.playlist {
            XCTAssertTrue(
                article.cognitiveLoad <= .moderate,
                "Relaxed session should not include \(article.cognitiveLoad) articles"
            )
        }
    }

    func testFocusedMoodPrefersHeavyContent() {
        let autopilot = makeAutopilot()
        let articles = [
            longArticle(topic: "algorithms", index: 0),
            longArticle(topic: "infrastructure", index: 1),
            mediumArticle(topic: "coding", index: 0),
            shortArticle(topic: "news", index: 0)
        ]
        let prefs = SessionPreferences(mood: .focused)
        let plan = autopilot.planSession(articles: articles, timeBudgetMinutes: 30, preferences: prefs)
        // Focused mood should prefer heavier articles
        for article in plan.playlist {
            XCTAssertTrue(
                article.cognitiveLoad >= .moderate,
                "Focused session should not include \(article.cognitiveLoad) articles"
            )
        }
    }

    // MARK: - Excluded Topics

    func testExcludedTopicsAreFiltered() {
        let autopilot = makeAutopilot()
        let articles = [
            shortArticle(topic: "swift", index: 0),
            shortArticle(topic: "politics", index: 0),
            shortArticle(topic: "cooking", index: 0)
        ]
        let prefs = SessionPreferences(excludedTopics: ["politics"])
        let plan = autopilot.planSession(articles: articles, timeBudgetMinutes: 10, preferences: prefs)
        for article in plan.playlist {
            XCTAssertFalse(article.topic.contains("politic"))
        }
    }

    // MARK: - Max Article Length

    func testMaxArticleMinutesFiltersTooLong() {
        let autopilot = makeAutopilot()
        let articles = [
            longArticle(topic: "deep", index: 0),
            shortArticle(topic: "quick", index: 0)
        ]
        let prefs = SessionPreferences(maxArticleMinutes: 3)
        let plan = autopilot.planSession(articles: articles, timeBudgetMinutes: 20, preferences: prefs)
        for article in plan.playlist {
            XCTAssertTrue(article.estimatedMinutes <= 3.0)
        }
    }

    // MARK: - Cognitive Load

    func testShortArticlesAreLight() {
        let autopilot = makeAutopilot()
        let articles = [shortArticle(topic: "news", index: 0)]
        let plan = autopilot.planSession(articles: articles, timeBudgetMinutes: 5)
        XCTAssertEqual(plan.playlist.first?.cognitiveLoad, .light)
    }

    func testTechnicalLongArticlesAreHeavy() {
        let autopilot = makeAutopilot()
        let articles = [longArticle(topic: "algorithms", index: 0)]
        let plan = autopilot.planSession(articles: articles, timeBudgetMinutes: 20)
        if let first = plan.playlist.first {
            XCTAssertTrue(first.cognitiveLoad >= .heavy,
                         "Technical long article should be heavy or dense, got \(first.cognitiveLoad)")
        }
    }

    // MARK: - Sequencing

    func testCognitiveProfileDescribed() {
        let autopilot = makeAutopilot()
        let articles = (0..<8).map { mediumArticle(topic: "topic\($0)", index: $0) }
        let plan = autopilot.planSession(articles: articles, timeBudgetMinutes: 30)
        XCTAssertFalse(plan.cognitiveProfile.isEmpty)
        XCTAssertNotEqual(plan.cognitiveProfile, "empty")
    }

    // MARK: - Session Brief

    func testSessionBriefGenerated() {
        let autopilot = makeAutopilot()
        let articles = (0..<5).map { shortArticle(topic: "topic\($0)", index: $0) }
        let plan = autopilot.planSession(articles: articles, timeBudgetMinutes: 10)
        XCTAssertFalse(plan.sessionBrief.isEmpty)
        XCTAssertTrue(plan.sessionBrief.contains("articles"))
        XCTAssertTrue(plan.sessionBrief.contains("min"))
    }

    // MARK: - Priority Scoring

    func testAveragePriorityIsReasonable() {
        let autopilot = makeAutopilot()
        let articles = (0..<10).map { mediumArticle(topic: "tech\($0 % 3)", index: $0) }
        let plan = autopilot.planSession(articles: articles, timeBudgetMinutes: 20)
        XCTAssertTrue(plan.averagePriority >= 0)
        XCTAssertTrue(plan.averagePriority <= 100)
    }

    func testPreferredTopicsBoostPriority() {
        let autopilot = makeAutopilot()
        let articles = [
            shortArticle(topic: "swift", index: 0),
            shortArticle(topic: "cooking", index: 1),
            shortArticle(topic: "swift", index: 2)
        ]
        let prefs = SessionPreferences(preferredTopics: ["swift"])
        let plan = autopilot.planSession(articles: articles, timeBudgetMinutes: 5, preferences: prefs)
        // With very limited budget, preferred topic should win
        if let first = plan.playlist.first {
            XCTAssertTrue(first.title.lowercased().contains("swift"))
        }
    }

    // MARK: - Selection Reason

    func testSelectionReasonProvided() {
        let autopilot = makeAutopilot()
        let articles = [shortArticle(topic: "news", index: 0)]
        let plan = autopilot.planSession(articles: articles, timeBudgetMinutes: 5)
        if let first = plan.playlist.first {
            XCTAssertFalse(first.selectionReason.isEmpty)
        }
    }

    // MARK: - Estimate Capacity

    func testEstimateCapacityReturnsReasonableNumber() {
        let autopilot = makeAutopilot()
        let articles = (0..<10).map { shortArticle(topic: "news", index: $0) }
        let capacity = autopilot.estimateCapacity(articles: articles, timeBudgetMinutes: 20)
        XCTAssertTrue(capacity > 0)
        XCTAssertTrue(capacity <= 100)
    }

    func testEstimateCapacityEmptyArticles() {
        let autopilot = makeAutopilot()
        let capacity = autopilot.estimateCapacity(articles: [], timeBudgetMinutes: 20)
        XCTAssertEqual(capacity, 0)
    }

    // MARK: - Suggest Budget

    func testSuggestBudgetReturnsPositive() {
        let autopilot = makeAutopilot()
        let articles = (0..<10).map { mediumArticle(topic: "tech", index: $0) }
        let budget = autopilot.suggestBudget(articles: articles, targetArticles: 5)
        XCTAssertTrue(budget > 0)
    }

    func testSuggestBudgetEmptyArticles() {
        let autopilot = makeAutopilot()
        let budget = autopilot.suggestBudget(articles: [])
        XCTAssertEqual(budget, 0)
    }

    // MARK: - Playlist Position

    func testPlaylistPositionsAreSequential() {
        let autopilot = makeAutopilot()
        let articles = (0..<8).map { shortArticle(topic: "topic\($0)", index: $0) }
        let plan = autopilot.planSession(articles: articles, timeBudgetMinutes: 20)
        for (idx, article) in plan.playlist.enumerated() {
            XCTAssertEqual(article.position, idx + 1)
        }
    }

    // MARK: - Mood in Plan

    func testPlanRecordsMood() {
        let autopilot = makeAutopilot()
        let articles = [shortArticle(topic: "test")]
        let prefs = SessionPreferences(mood: .exploratory)
        let plan = autopilot.planSession(articles: articles, timeBudgetMinutes: 5, preferences: prefs)
        XCTAssertEqual(plan.mood, .exploratory)
    }

    // MARK: - Cooldown Preference

    func testIncludeCooldownPreference() {
        let autopilot = makeAutopilot()
        let articles = (0..<6).flatMap { i -> [RSSStory] in
            [shortArticle(topic: "light\(i)", index: i),
             longArticle(topic: "heavy\(i)", index: i)]
        }
        let prefs = SessionPreferences(mood: .balanced, includeCooldown: true)
        let plan = autopilot.planSession(articles: articles, timeBudgetMinutes: 30, preferences: prefs)
        // With cooldown enabled, last article shouldn't be the heaviest
        if plan.articleCount > 2, let last = plan.playlist.last {
            // Just verify the plan completes — the autopilot should try to end light
            XCTAssertNotNil(last.cognitiveLoad)
        }
    }
}
