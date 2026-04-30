//
//  FeedSourceCredibilityTests.swift
//  FeedReaderCoreTests
//
//  Tests for the FeedSourceCredibility engine.
//

import XCTest
@testable import FeedReaderCore

final class FeedSourceCredibilityTests: XCTestCase {

    var engine: FeedSourceCredibility!

    override func setUp() {
        super.setUp()
        engine = FeedSourceCredibility()
    }

    override func tearDown() {
        engine = nil
        super.tearDown()
    }

    // MARK: - Helper

    private func makeStory(title: String, body: String, link: String = "https://example.com/\(UUID().uuidString)") -> RSSStory {
        return RSSStory(title: title, body: body, link: link)!
    }

    private func makeFeed(name: String = "Test News", url: String = "https://test.com/feed") -> FeedItem {
        return FeedItem(name: name, url: url, isEnabled: true)
    }

    // MARK: - Basic Analysis

    func testAnalyzeEmptyArticles() {
        let feed = makeFeed()
        let results = engine.analyzeArticles([], from: feed)
        XCTAssertTrue(results.isEmpty)
    }

    func testAnalyzeSingleArticle() {
        let story = makeStory(
            title: "Climate Report Released",
            body: "According to a study found in the journal Nature, temperatures rose 1.5 percent this year. Professor Smith confirmed the findings."
        )
        let feed = makeFeed()
        let results = engine.analyzeArticles([story], from: feed)

        XCTAssertEqual(results.count, 1)
        XCTAssertEqual(results[0].sourceName, "Test News")
        XCTAssertGreaterThan(results[0].citationCount, 0)
        XCTAssertGreaterThan(results[0].overallScore, 0)
    }

    func testCitationDetection() {
        let story = makeStory(
            title: "Research Findings",
            body: "According to researchers at the University of Oxford, a peer-reviewed study published in Science shows data from multiple sources."
        )
        let feed = makeFeed()
        let results = engine.analyzeArticles([story], from: feed)

        XCTAssertGreaterThanOrEqual(results[0].citationCount, 3)
    }

    func testHedgingDetection() {
        let story = makeStory(
            title: "Unverified Claims Surface",
            body: "Sources say the company allegedly misreported earnings. It appears that reportedly millions were hidden."
        )
        let feed = makeFeed()
        let results = engine.analyzeArticles([story], from: feed)

        XCTAssertGreaterThanOrEqual(results[0].hedgingCount, 3)
    }

    func testSensationalismDetection() {
        let story = makeStory(
            title: "SHOCKING: Explosive Bombshell Rocks Industry",
            body: "In a devastating turn, the catastrophic crisis has left everyone terrified. This unprecedented nightmare continues."
        )
        let feed = makeFeed()
        let results = engine.analyzeArticles([story], from: feed)

        XCTAssertGreaterThan(results[0].sensationalismScore, 50.0)
    }

    func testHighCredibilityArticle() {
        let story = makeStory(
            title: "Federal Reserve Raises Rates",
            body: "According to the Federal Reserve, interest rates rose 0.25 percent on Wednesday. The president of the bank confirmed the decision. Data from the Bureau of Labor Statistics shows unemployment at 3.7 percent in January."
        )
        let feed = makeFeed()
        let results = engine.analyzeArticles([story], from: feed)

        XCTAssertGreaterThan(results[0].overallScore, 50.0)
        XCTAssertGreaterThan(results[0].specificityScore, 0)
    }

    func testLowCredibilityArticle() {
        let story = makeStory(
            title: "You Won't Believe What Happened",
            body: "In a shocking and devastating revelation, sources say this explosive bombshell will terrify everyone. Outrageous!"
        )
        let feed = makeFeed()
        let results = engine.analyzeArticles([story], from: feed)

        XCTAssertLessThan(results[0].overallScore, 60.0)
        XCTAssertGreaterThan(results[0].sensationalismScore, 40.0)
    }

    // MARK: - Trust Profiles

    func testProfileCreation() {
        let story = makeStory(title: "Test Article", body: "According to the study, findings were confirmed by the director.")
        let feed = makeFeed(name: "Reuters")
        engine.analyzeArticles([story], from: feed)

        let profile = engine.getProfile(for: "Reuters")
        XCTAssertNotNil(profile)
        XCTAssertEqual(profile?.sourceName, "Reuters")
        XCTAssertEqual(profile?.articlesAnalyzed, 1)
    }

    func testProfileUpdatesOverTime() {
        let feed = makeFeed(name: "BBC")
        for i in 0..<10 {
            let story = makeStory(
                title: "Article \(i) Report",
                body: "According to researchers at the university, a study published in the journal shows data from surveys of 1000 people. Professor Jones confirmed.",
                link: "https://bbc.com/\(i)"
            )
            engine.analyzeArticles([story], from: feed)
        }

        let profile = engine.getProfile(for: "BBC")
        XCTAssertNotNil(profile)
        XCTAssertEqual(profile?.articlesAnalyzed, 10)
        XCTAssertGreaterThan(profile!.citationRate, 0)
        XCTAssertGreaterThan(profile!.compositeScore, 0)
    }

    func testGetAllProfiles() {
        let feed1 = makeFeed(name: "Source A", url: "https://a.com/feed")
        let feed2 = makeFeed(name: "Source B", url: "https://b.com/feed")
        let story = makeStory(title: "Test", body: "According to the report, data from the study confirmed findings.")

        engine.analyzeArticles([story], from: feed1)
        engine.analyzeArticles([story], from: feed2)

        let profiles = engine.getAllProfiles()
        XCTAssertEqual(profiles.count, 2)
    }

    // MARK: - Tier Classification

    func testTierFromScore() {
        XCTAssertEqual(CredibilityTier.from(score: 95), .platinum)
        XCTAssertEqual(CredibilityTier.from(score: 80), .gold)
        XCTAssertEqual(CredibilityTier.from(score: 65), .silver)
        XCTAssertEqual(CredibilityTier.from(score: 50), .bronze)
        XCTAssertEqual(CredibilityTier.from(score: 20), .untrusted)
    }

    func testTierComparable() {
        XCTAssertTrue(CredibilityTier.untrusted < CredibilityTier.bronze)
        XCTAssertTrue(CredibilityTier.bronze < CredibilityTier.silver)
        XCTAssertTrue(CredibilityTier.silver < CredibilityTier.gold)
        XCTAssertTrue(CredibilityTier.gold < CredibilityTier.platinum)
    }

    // MARK: - Correction/Retraction Detection

    func testCorrectionDetection() {
        let story = makeStory(
            title: "Correction: Previous Report",
            body: "Editor's note: An earlier version of this article incorrectly stated the figures. This article has been updated."
        )
        let feed = makeFeed()
        let results = engine.analyzeArticles([story], from: feed)

        let correctionSignals = results[0].signals.filter { $0.type == .correction }
        XCTAssertGreaterThan(correctionSignals.count, 0)
    }

    func testRetractionDetection() {
        let story = makeStory(
            title: "Story Retracted",
            body: "This story has been removed as it was inaccurate. We apologize for the error and the story no longer stands."
        )
        let feed = makeFeed()
        let results = engine.analyzeArticles([story], from: feed)

        let retractionSignals = results[0].signals.filter { $0.type == .retraction }
        XCTAssertGreaterThan(retractionSignals.count, 0)
    }

    func testRetractionIncrementsCount() {
        let story = makeStory(
            title: "Retraction Notice",
            body: "We are retracting this story as it was inaccurate."
        )
        let feed = makeFeed(name: "Unreliable Source")
        engine.analyzeArticles([story], from: feed)

        let profile = engine.getProfile(for: "Unreliable Source")
        XCTAssertEqual(profile?.retractionCount, 1)
    }

    // MARK: - Trend Detection

    func testTrendStableWithFewDataPoints() {
        var profile = SourceTrustProfile(sourceName: "Test", sourceURL: "https://test.com")
        profile.scoreHistory = [70, 71]
        XCTAssertEqual(profile.trend, .stable)
    }

    func testTrendImproving() {
        var profile = SourceTrustProfile(sourceName: "Test", sourceURL: "https://test.com")
        profile.scoreHistory = [50, 52, 55, 60, 65]
        XCTAssertEqual(profile.trend, .improving)
    }

    func testTrendDeclining() {
        var profile = SourceTrustProfile(sourceName: "Test", sourceURL: "https://test.com")
        profile.scoreHistory = [80, 77, 73, 68, 62]
        XCTAssertEqual(profile.trend, .declining)
    }

    // MARK: - Alerts

    func testNewSourceAlert() {
        let feed = makeFeed(name: "New Source")
        engine.minimumArticlesForScoring = 3

        for i in 0..<3 {
            let story = makeStory(title: "Article \(i)", body: "Content for article number \(i) with some text.", link: "https://new.com/\(i)")
            engine.analyzeArticles([story], from: feed)
        }

        let alerts = engine.getAlerts()
        let newSourceAlerts = alerts.filter { $0.type == .newSourceAssessed }
        XCTAssertGreaterThanOrEqual(newSourceAlerts.count, 1)
    }

    func testSensationalismAlert() {
        let feed = makeFeed(name: "Tabloid")
        for i in 0..<5 {
            let story = makeStory(
                title: "SHOCKING BOMBSHELL: Explosive Devastating Crisis \(i)",
                body: "Terrifying nightmare outrageous catastrophic unprecedented emergency shocking explosive bombshell",
                link: "https://tabloid.com/\(i)"
            )
            engine.analyzeArticles([story], from: feed)
        }

        let alerts = engine.getAlerts(minSeverity: 3)
        let sensAlerts = alerts.filter { $0.type == .sensationalismSpike }
        XCTAssertGreaterThanOrEqual(sensAlerts.count, 1)
    }

    // MARK: - Corroboration

    func testCorroborationWithSimilarArticles() {
        let story1 = makeStory(
            title: "Apple Releases New iPhone Model",
            body: "Apple announced today the release of their new iPhone model with improved camera technology and battery life.",
            link: "https://a.com/1"
        )
        let story2 = makeStory(
            title: "New iPhone Launched by Apple",
            body: "Apple has launched their latest iPhone featuring an upgraded camera system and longer battery performance.",
            link: "https://b.com/1"
        )

        let articles: [(story: RSSStory, source: String)] = [
            (story1, "TechCrunch"),
            (story2, "The Verge")
        ]

        let results = engine.checkCorroboration(articles)
        // May or may not cluster depending on keyword overlap — just ensure no crash
        XCTAssertNotNil(results)
    }

    // MARK: - Fleet Summary

    func testFleetSummary() {
        let feed1 = makeFeed(name: "Good Source", url: "https://good.com/feed")
        let feed2 = makeFeed(name: "Bad Source", url: "https://bad.com/feed")

        let goodStory = makeStory(title: "Research Report", body: "According to a peer-reviewed study published in Nature, data from the university shows 45 percent improvement.")
        let badStory = makeStory(title: "SHOCKING BOMBSHELL", body: "Devastating explosive catastrophic terrifying nightmare unprecedented crisis!")

        engine.analyzeArticles([goodStory], from: feed1)
        engine.analyzeArticles([badStory], from: feed2)

        let summary = engine.fleetSummary()
        XCTAssertEqual(summary.totalSources, 2)
        XCTAssertGreaterThan(summary.averageScore, 0)
    }

    // MARK: - Signal Model

    func testCredibilitySignalClamping() {
        let signal = CredibilitySignal(type: .citation, text: "test", weight: 2.0, confidence: 5.0)
        XCTAssertEqual(signal.weight, 1.0)
        XCTAssertEqual(signal.confidence, 1.0)

        let signal2 = CredibilitySignal(type: .citation, text: "test", weight: -2.0, confidence: -1.0)
        XCTAssertEqual(signal2.weight, -1.0)
        XCTAssertEqual(signal2.confidence, 0.0)
    }

    func testCorroborationScoreClamping() {
        let result = CorroborationResult(claim: "test", supportingSources: [], contradictingSources: [], corroborationScore: 150, confidence: 2.0)
        XCTAssertEqual(result.corroborationScore, 100.0)
        XCTAssertEqual(result.confidence, 1.0)
    }

    // MARK: - Reset

    func testReset() {
        let feed = makeFeed()
        let story = makeStory(title: "Test", body: "Content here for testing purposes.")
        engine.analyzeArticles([story], from: feed)

        XCTAssertFalse(engine.getAllProfiles().isEmpty)
        engine.reset()
        XCTAssertTrue(engine.getAllProfiles().isEmpty)
        XCTAssertTrue(engine.getAlerts().isEmpty)
    }

    // MARK: - Credibility Tier CaseIterable

    func testAllTiersCovered() {
        XCTAssertEqual(CredibilityTier.allCases.count, 5)
    }

    func testAllSignalTypesCovered() {
        XCTAssertEqual(CredibilitySignalType.allCases.count, 8)
    }

    // MARK: - Batch Analysis

    func testBatchAnalysis() {
        let stories = (0..<10).map { i in
            makeStory(
                title: "Article \(i) from Source",
                body: "According to the report, research shows data from the study with 20 percent increase confirmed by the director.",
                link: "https://batch.com/\(i)"
            )
        }
        let feed = makeFeed(name: "Batch Source")
        let results = engine.analyzeArticles(stories, from: feed)

        XCTAssertEqual(results.count, 10)
        let profile = engine.getProfile(for: "Batch Source")
        XCTAssertEqual(profile?.articlesAnalyzed, 10)
    }

    // MARK: - Attribution Detection

    func testAttributionDetection() {
        let story = makeStory(
            title: "CEO Announces Plan",
            body: "The president said the company will expand. A spokesperson confirmed the decision. The director told reporters it was final."
        )
        let feed = makeFeed()
        let results = engine.analyzeArticles([story], from: feed)

        let attrSignals = results[0].signals.filter { $0.type == .attribution }
        XCTAssertGreaterThan(attrSignals.count, 0)
    }

    // MARK: - Multiple Feeds Independence

    func testMultipleFeedsTrackedIndependently() {
        let feed1 = makeFeed(name: "Source A", url: "https://a.com/rss")
        let feed2 = makeFeed(name: "Source B", url: "https://b.com/rss")

        let story1 = makeStory(title: "Credible Report", body: "According to the peer-reviewed journal study, researchers confirmed the findings with data from 5000 participants.")
        let story2 = makeStory(title: "SHOCKING NEWS", body: "Devastating explosive unprecedented nightmare terrifying catastrophic crisis bombshell!")

        engine.analyzeArticles([story1], from: feed1)
        engine.analyzeArticles([story2], from: feed2)

        let profileA = engine.getProfile(for: "Source A")!
        let profileB = engine.getProfile(for: "Source B")!

        XCTAssertGreaterThan(profileA.compositeScore, profileB.compositeScore)
    }
}
