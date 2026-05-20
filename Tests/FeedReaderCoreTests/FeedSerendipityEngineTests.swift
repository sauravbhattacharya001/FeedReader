//
//  FeedSerendipityEngineTests.swift
//  FeedReaderCoreTests
//
//  Tests for the FeedSerendipityEngine - autonomous serendipitous article
//  discovery. Exercises keyword extraction, scoring, classification, the
//  novelty (already-surfaced) decay, recommendation generation, and the
//  formatting / JSON export helpers.
//

import XCTest
@testable import FeedReaderCore

final class FeedSerendipityEngineTests: XCTestCase {

    // MARK: - Helpers

    private func techArticle(
        id: String = UUID().uuidString,
        feed: String = "TechCrunch"
    ) -> SerendipityArticle {
        SerendipityArticle(
            title: "AI Breakthrough in Healthcare",
            body: """
            Researchers announced a new breakthrough where artificial intelligence software
            is helping hospitals diagnose patients. The technology platform analyzes patient
            data faster than any previous computer system, marking an emerging milestone for
            medical research and digital health applications across hospitals worldwide.
            """,
            link: "https://example.com/tech/\(id)",
            feedName: feed
        )
    }

    private func healthArticle(
        id: String = UUID().uuidString,
        feed: String = "BBC Health"
    ) -> SerendipityArticle {
        SerendipityArticle(
            title: "Hospital Robots Transform Patient Care",
            body: """
            Modern hospitals are deploying robotic systems and intelligent software to assist
            with patient diagnose workflows. Medical research suggests that data-driven tools
            and emerging artificial platforms can shorten treatment time for patients across
            the healthcare system, though some doctors debate the ethical implications.
            """,
            link: "https://example.com/health/\(id)",
            feedName: feed
        )
    }

    private func sportsArticle(
        id: String = UUID().uuidString,
        feed: String = "ESPN"
    ) -> SerendipityArticle {
        SerendipityArticle(
            title: "Championship Team Wins Title",
            body: """
            The league championship game ended with the home team defeating the visiting
            players in overtime. Fans celebrated across the stadium as the team captured
            their first title in two decades.
            """,
            link: "https://example.com/sports/\(id)",
            feedName: feed
        )
    }

    // MARK: - SerendipityArticle

    func testArticleExtractsKeywordsAndIgnoresStopWords() {
        let article = techArticle()
        XCTAssertFalse(article.keywords.isEmpty, "Keywords should be extracted")
        XCTAssertLessThanOrEqual(article.keywords.count, 20, "Keyword list is capped at 20")

        // None of the extractor's declared stop words should appear.
        let stopWordsLeak: Set<String> = ["that", "this", "with", "from", "have", "been",
                                          "their", "about", "would", "could", "should",
                                          "which", "there", "when", "what"]
        let leaked = Set(article.keywords).intersection(stopWordsLeak)
        XCTAssertTrue(leaked.isEmpty, "Stop words must not survive extraction; leaked: \(leaked)")

        // Short tokens (<= 3 chars) should be filtered out.
        XCTAssertFalse(article.keywords.contains(where: { $0.count <= 3 }),
                       "Short tokens must be filtered")

        // Domain-relevant substantive words should appear.
        let substantive: Set<String> = ["hospitals", "patient", "research", "medical",
                                       "technology", "data", "software"]
        XCTAssertFalse(Set(article.keywords).isDisjoint(with: substantive),
                       "Extractor should surface at least one substantive keyword")
    }

    func testDomainInferenceFromFeedName() {
        let tech = SerendipityArticle(title: "Quarterly Report", body: "ok",
                                     link: "https://x.test/1", feedName: "TechCrunch")
        XCTAssertEqual(tech.domain, "technology")

        let health = SerendipityArticle(title: "Patient outcomes", body: "ok",
                                       link: "https://x.test/2", feedName: "BBC Health")
        XCTAssertEqual(health.domain, "health")

        let sports = SerendipityArticle(title: "Game recap", body: "ok",
                                       link: "https://x.test/3", feedName: "ESPN Sports")
        XCTAssertEqual(sports.domain, "sports")

        let unknown = SerendipityArticle(title: "Cooking", body: "ok",
                                        link: "https://x.test/4", feedName: "Recipes Weekly")
        XCTAssertEqual(unknown.domain, "general", "Unrecognized feeds fall back to 'general'")
    }

    // MARK: - SerendipityConfig

    func testConfigClampsOutOfRangeValues() {
        let low = SerendipityConfig(minSharedKeywords: -5, maxConnections: 0,
                                    minSerendipityScore: -1.5)
        XCTAssertEqual(low.minSharedKeywords, 1)
        XCTAssertEqual(low.maxConnections, 1)
        XCTAssertEqual(low.minSerendipityScore, 0)

        let high = SerendipityConfig(minSharedKeywords: 999, maxConnections: 999,
                                     minSerendipityScore: 2.0)
        XCTAssertEqual(high.minSharedKeywords, 10)
        XCTAssertEqual(high.maxConnections, 50)
        XCTAssertEqual(high.minSerendipityScore, 1)
    }

    // MARK: - Discovery: empty / trivial inputs

    func testDiscoveryWithFewerThanTwoArticlesReturnsEmpty() {
        let engine = FeedSerendipityEngine()

        let empty = engine.discover(articles: [])
        XCTAssertTrue(empty.connections.isEmpty)
        XCTAssertEqual(empty.articlesAnalyzed, 0)
        XCTAssertEqual(empty.feedsInvolved, 0)
        XCTAssertFalse(empty.recommendations.isEmpty, "Should still emit a recommendation")

        let single = engine.discover(articles: [techArticle()])
        XCTAssertTrue(single.connections.isEmpty)
        XCTAssertEqual(single.articlesAnalyzed, 1)
        XCTAssertEqual(single.feedsInvolved, 0)
    }

    func testSameFeedPairsAreNeverConnected() {
        // Two articles sharing the same feed name should be skipped even
        // when they have heavy keyword overlap.
        let a = techArticle(id: "a", feed: "OnlyFeed")
        let b = techArticle(id: "b", feed: "OnlyFeed")

        // Use permissive config so the only thing rejecting the pair is the
        // same-feed rule.
        let cfg = SerendipityConfig(minSharedKeywords: 1, maxConnections: 10,
                                    minSerendipityScore: 0)
        let report = FeedSerendipityEngine(config: cfg).discover(articles: [a, b])
        XCTAssertTrue(report.connections.isEmpty,
                      "Articles from the same feed must not produce connections")
    }

    // MARK: - Discovery: real cross-feed connection

    func testDiscoveryFindsCrossDomainConnection() {
        let tech = techArticle()
        let health = healthArticle()
        let cfg = SerendipityConfig(minSharedKeywords: 1, maxConnections: 10,
                                    minSerendipityScore: 0.0)
        let engine = FeedSerendipityEngine(config: cfg)

        let report = engine.discover(articles: [tech, health])
        XCTAssertEqual(report.articlesAnalyzed, 2)
        XCTAssertEqual(report.feedsInvolved, 2)
        XCTAssertFalse(report.connections.isEmpty,
                       "Tech + health articles share keywords; expected at least one connection")

        let conn = report.connections[0]
        XCTAssertGreaterThan(conn.bridgeKeywords.count, 0)
        XCTAssertEqual(conn.bridgeKeywords, conn.bridgeKeywords.sorted(),
                       "Bridge keywords should be returned in sorted order")
        XCTAssertGreaterThanOrEqual(conn.serendipityScore, 0)
        XCTAssertLessThanOrEqual(conn.serendipityScore, 1)
        XCTAssertFalse(conn.explanation.isEmpty)
    }

    func testUnrelatedArticlesProduceNoConnection() {
        let tech = techArticle()
        let sports = sportsArticle()
        // Tech and sports share essentially no keywords; require at least
        // 5 shared keywords so any happenstance match is rejected.
        let cfg = SerendipityConfig(minSharedKeywords: 5, maxConnections: 10,
                                    minSerendipityScore: 0)
        let report = FeedSerendipityEngine(config: cfg).discover(articles: [tech, sports])
        XCTAssertTrue(report.connections.isEmpty,
                      "Tech vs Sports should have insufficient overlap")
    }

    func testRespectsMinSerendipityScoreThreshold() {
        let tech = techArticle()
        let health = healthArticle()
        // A score threshold of 1.01 is unreachable - we should get no
        // connections back.
        let cfg = SerendipityConfig(minSharedKeywords: 1, maxConnections: 10,
                                    minSerendipityScore: 1.01)
        let report = FeedSerendipityEngine(config: cfg).discover(articles: [tech, health])
        XCTAssertTrue(report.connections.isEmpty,
                      "Threshold above 1.0 must filter out every connection")
    }

    func testMaxConnectionsCapsResults() {
        var articles: [SerendipityArticle] = []
        // Build several distinct feeds so cross-feed pairs are abundant.
        for i in 0..<5 {
            articles.append(techArticle(id: "t\(i)", feed: "TechFeed\(i)"))
            articles.append(healthArticle(id: "h\(i)", feed: "HealthFeed\(i)"))
        }
        let cfg = SerendipityConfig(minSharedKeywords: 1, maxConnections: 3,
                                    minSerendipityScore: 0)
        let report = FeedSerendipityEngine(config: cfg).discover(articles: articles)
        XCTAssertLessThanOrEqual(report.connections.count, 3,
                                 "Result count must respect maxConnections cap")
        // The sort order should be strictly non-increasing by serendipityScore.
        let scores = report.connections.map { $0.serendipityScore }
        XCTAssertEqual(scores, scores.sorted(by: >),
                       "Connections must be sorted by serendipityScore descending")
    }

    // MARK: - Novelty decay

    func testRepeatedDiscoveryDecaysAlreadySurfacedConnections() {
        let tech = techArticle(id: "stable-tech", feed: "TechCrunch")
        let health = healthArticle(id: "stable-health", feed: "BBC Health")
        let cfg = SerendipityConfig(minSharedKeywords: 1, maxConnections: 10,
                                    minSerendipityScore: 0.0)
        let engine = FeedSerendipityEngine(config: cfg)

        let firstReport = engine.discover(articles: [tech, health])
        XCTAssertFalse(firstReport.connections.isEmpty)
        let firstScore = firstReport.connections[0].serendipityScore

        let secondReport = engine.discover(articles: [tech, health])
        XCTAssertFalse(secondReport.connections.isEmpty)
        let secondScore = secondReport.connections[0].serendipityScore

        // After a connection has been surfaced once, re-encountering the same
        // pair multiplies the score by 0.7 - it must be strictly smaller.
        XCTAssertLessThan(secondScore, firstScore,
                          "Already-surfaced pair should have its score decayed")
        XCTAssertEqual(secondScore, firstScore * 0.7, accuracy: 1e-9,
                       "Decay factor should be exactly 0.7")
    }

    // MARK: - Report aggregation

    func testReportAggregatesTypeBreakdownAndBridges() {
        let articles = [
            techArticle(id: "a", feed: "TechCrunch"),
            healthArticle(id: "b", feed: "BBC Health"),
            techArticle(id: "c", feed: "Wired"),
        ]
        let cfg = SerendipityConfig(minSharedKeywords: 1, maxConnections: 10,
                                    minSerendipityScore: 0.0)
        let report = FeedSerendipityEngine(config: cfg).discover(articles: articles)

        XCTAssertEqual(report.feedsInvolved, 3)
        XCTAssertEqual(report.articlesAnalyzed, 3)

        let typeSum = report.typeBreakdown.values.reduce(0, +)
        XCTAssertEqual(typeSum, report.connections.count,
                       "Type breakdown counts must sum to the number of returned connections")

        if !report.connections.isEmpty {
            XCTAssertFalse(report.topBridgeKeywords.isEmpty,
                           "Top bridge keywords should be populated when connections exist")
            XCTAssertLessThanOrEqual(report.topBridgeKeywords.count, 10)
            let avg = report.connections.reduce(0.0) { $0 + $1.serendipityScore }
                / Double(report.connections.count)
            XCTAssertEqual(report.averageSerendipity, avg, accuracy: 1e-9)
        }
    }

    // MARK: - Recommendations

    func testRecommendationsMentionMissingDomainsWhenSparse() {
        // Only sports feeds: every other domain is missing - the engine
        // should suggest broader coverage.
        let articles = [
            sportsArticle(id: "s1", feed: "ESPN"),
            sportsArticle(id: "s2", feed: "BBC Sports"),
        ]
        let report = FeedSerendipityEngine().discover(articles: articles)
        let joined = report.recommendations.joined(separator: " | ").lowercased()
        XCTAssertTrue(
            joined.contains("technology") || joined.contains("science")
                || joined.contains("health") || joined.contains("more diverse"),
            "Recommendations should call out missing domains / low diversity; got: \(joined)"
        )
    }

    // MARK: - Formatting and JSON export

    func testFormatReportProducesNonEmptyOutputForReport() {
        let engine = FeedSerendipityEngine(config: SerendipityConfig(
            minSharedKeywords: 1, maxConnections: 5, minSerendipityScore: 0))
        let report = engine.discover(articles: [techArticle(), healthArticle()])
        let formatted = engine.formatReport(report)
        XCTAssertFalse(formatted.isEmpty)
        XCTAssertTrue(formatted.contains("Articles analyzed:"),
                      "Formatted report should include the overview header")
        XCTAssertTrue(formatted.contains("\(report.articlesAnalyzed)"))
    }

    func testExportJSONShapeMatchesReport() {
        let engine = FeedSerendipityEngine(config: SerendipityConfig(
            minSharedKeywords: 1, maxConnections: 5, minSerendipityScore: 0))
        let report = engine.discover(articles: [techArticle(), healthArticle()])
        let json = engine.exportJSON(report)

        XCTAssertEqual(json["articlesAnalyzed"] as? Int, report.articlesAnalyzed)
        XCTAssertEqual(json["feedsInvolved"] as? Int, report.feedsInvolved)
        XCTAssertNotNil(json["averageSerendipity"] as? Double)
        XCTAssertNotNil(json["topBridgeKeywords"] as? [String])
        XCTAssertNotNil(json["recommendations"] as? [String])

        let conns = json["connections"] as? [[String: Any]]
        XCTAssertNotNil(conns)
        XCTAssertEqual(conns?.count, report.connections.count)

        if let first = conns?.first {
            XCTAssertNotNil(first["articleA"] as? [String: String])
            XCTAssertNotNil(first["articleB"] as? [String: String])
            XCTAssertNotNil(first["bridgeKeywords"] as? [String])
            XCTAssertNotNil(first["serendipityScore"] as? Double)
            XCTAssertNotNil(first["connectionType"] as? String)
            XCTAssertNotNil(first["explanation"] as? String)
        }
    }

    // MARK: - Performance regression guard

    /// Smoke-perf check: discovery on a few dozen articles must finish quickly.
    /// This is mostly a regression sentinel for the inner-loop hoisting -
    /// if anyone reintroduces per-pair Set construction or per-pair body
    /// tokenization, the wall-clock blows up well past the budget.
    func testDiscoveryPerformanceIsReasonable() {
        var articles: [SerendipityArticle] = []
        for i in 0..<20 {
            articles.append(techArticle(id: "t\(i)", feed: "TechFeed\(i)"))
            articles.append(healthArticle(id: "h\(i)", feed: "HealthFeed\(i)"))
        }
        let cfg = SerendipityConfig(minSharedKeywords: 1, maxConnections: 25,
                                    minSerendipityScore: 0)
        let engine = FeedSerendipityEngine(config: cfg)

        let start = Date()
        let report = engine.discover(articles: articles)
        let elapsed = Date().timeIntervalSince(start)

        XCTAssertEqual(report.articlesAnalyzed, articles.count)
        // Generous ceiling - locally this runs in ~10-50ms. Failing this
        // means an O(N^3)-ish regression slipped in.
        XCTAssertLessThan(elapsed, 5.0, "Discovery should not take more than 5s for 40 articles")
    }
}
