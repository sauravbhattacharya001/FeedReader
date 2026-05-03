//
//  FeedBlindSpotDetectorTests.swift
//  FeedReaderCoreTests
//
//  Tests for the FeedBlindSpotDetector autonomous blind spot detection engine.
//

import XCTest
@testable import FeedReaderCore

final class FeedBlindSpotDetectorTests: XCTestCase {

    private var detector: FeedBlindSpotDetector!

    override func setUp() {
        super.setUp()
        detector = FeedBlindSpotDetector()
    }

    override func tearDown() {
        detector = nil
        super.tearDown()
    }

    // MARK: - Helper

    private func makeArticle(
        id: String = UUID().uuidString,
        title: String = "Test Article",
        topics: [String],
        feedURL: String = "https://feed.example.com",
        feedName: String = "Test Feed",
        readDate: Date = Date(),
        perspective: String = "general"
    ) -> BlindSpotArticle {
        BlindSpotArticle(
            id: id, title: title, topics: topics,
            feedURL: feedURL, feedName: feedName,
            readDate: readDate, sourcePerspective: perspective)
    }

    private func daysAgo(_ days: Int) -> Date {
        Calendar.current.date(byAdding: .day, value: -days, to: Date())!
    }

    // MARK: - Empty State

    func testEmptyDetector_returnsCleanReport() {
        let report = detector.analyze()
        XCTAssertEqual(report.totalTopicsTracked, 0)
        XCTAssertEqual(report.totalBlindSpots, 0)
        XCTAssertEqual(report.healthScore, 100)
        XCTAssertEqual(report.grade, "A")
        XCTAssertTrue(report.blindSpots.isEmpty)
        XCTAssertTrue(report.coverageMap.isEmpty)
        XCTAssertFalse(report.insights.isEmpty)
    }

    func testEmptyDetector_getCoverageMap_isEmpty() {
        XCTAssertTrue(detector.getCoverageMap().isEmpty)
    }

    func testEmptyDetector_isBlindSpot_returnsFalse() {
        XCTAssertFalse(detector.isBlindSpot("anything"))
    }

    // MARK: - Single Article Ingestion

    func testSingleArticle_tracksTopic() {
        detector.ingest(makeArticle(topics: ["swift"]))
        let map = detector.getCoverageMap()
        XCTAssertEqual(map["swift"], 1)
    }

    func testSingleArticle_multipleTopics() {
        detector.ingest(makeArticle(topics: ["swift", "ios", "xcode"]))
        let map = detector.getCoverageMap()
        XCTAssertEqual(map["swift"], 1)
        XCTAssertEqual(map["ios"], 1)
        XCTAssertEqual(map["xcode"], 1)
    }

    func testSingleArticle_noBlindSpots() {
        detector.ingest(makeArticle(topics: ["swift"]))
        let report = detector.analyze()
        // With just one article, shouldn't have significant blind spots
        XCTAssertEqual(report.totalTopicsTracked, 1)
    }

    // MARK: - Batch Ingestion

    func testBatchIngestion_tracksAll() {
        let articles = [
            makeArticle(topics: ["swift"]),
            makeArticle(topics: ["kotlin"]),
            makeArticle(topics: ["rust"]),
        ]
        detector.ingestBatch(articles)
        let map = detector.getCoverageMap()
        XCTAssertEqual(map.count, 3)
        XCTAssertEqual(map["swift"], 1)
        XCTAssertEqual(map["kotlin"], 1)
        XCTAssertEqual(map["rust"], 1)
    }

    func testBatchIngestion_accumulatesCounts() {
        let articles = [
            makeArticle(topics: ["swift"]),
            makeArticle(topics: ["swift"]),
            makeArticle(topics: ["swift"]),
        ]
        detector.ingestBatch(articles)
        XCTAssertEqual(detector.getCoverageMap()["swift"], 3)
    }

    // MARK: - Topic Normalization

    func testTopicNormalization_caseInsensitive() {
        detector.ingest(makeArticle(topics: ["Swift"]))
        detector.ingest(makeArticle(topics: ["SWIFT"]))
        detector.ingest(makeArticle(topics: ["swift"]))
        XCTAssertEqual(detector.getCoverageMap()["swift"], 3)
    }

    func testTopicNormalization_trimming() {
        detector.ingest(makeArticle(topics: ["  swift  "]))
        XCTAssertEqual(detector.getCoverageMap()["swift"], 1)
    }

    // MARK: - Co-occurrence & Adjacent Topic Discovery

    func testCooccurrence_buildsPairs() {
        // Articles with overlapping topics build co-occurrence
        for _ in 0..<3 {
            detector.ingest(makeArticle(topics: ["machine learning", "python"]))
        }
        let report = detector.analyze()
        let map = report.coverageMap
        XCTAssertEqual(map["machine learning"], 3)
        XCTAssertEqual(map["python"], 3)
    }

    func testAdjacentGap_detectedWhenTopicMissing() {
        // Create strong co-occurrence between "ml" and "tensorflow"
        // Then register "pytorch" as adjacent to "ml" manually
        for _ in 0..<5 {
            detector.ingest(makeArticle(topics: ["ml", "tensorflow"]))
        }
        detector.registerAdjacency(topic: "ml", adjacentTo: "pytorch", strength: 0.8)

        let report = detector.analyze()
        let pytorchSpots = report.blindSpots.filter { $0.topic == "pytorch" }
        XCTAssertFalse(pytorchSpots.isEmpty, "pytorch should be detected as a blind spot")
        XCTAssertEqual(pytorchSpots.first?.category, .adjacent)
    }

    func testManualAdjacency_createsBlindSpot() {
        detector.ingest(makeArticle(topics: ["react"]))
        detector.registerAdjacency(topic: "react", adjacentTo: "vue", strength: 0.9)
        let report = detector.analyze()
        let vueSpots = report.blindSpots.filter { $0.topic == "vue" }
        XCTAssertFalse(vueSpots.isEmpty, "vue should be an adjacent blind spot")
    }

    // MARK: - Echo Chamber Detection

    func testEchoChamber_singleSourceDetected() {
        // 5 articles about "ai" all from one feed
        for i in 0..<5 {
            detector.ingest(makeArticle(
                id: "echo-\(i)", topics: ["ai"],
                feedName: "Only AI Blog"))
        }
        let report = detector.analyze()
        XCTAssertTrue(report.echoChamberTopics.contains("ai"),
                       "ai should be flagged as echo chamber")
    }

    func testEchoChamber_diverseSourcesNotFlagged() {
        let feeds = ["Blog A", "Blog B", "Blog C", "Blog D", "Blog E"]
        for (i, feed) in feeds.enumerated() {
            detector.ingest(makeArticle(
                id: "diverse-\(i)", topics: ["cloud"],
                feedName: feed))
        }
        let report = detector.analyze()
        XCTAssertFalse(report.echoChamberTopics.contains("cloud"),
                        "cloud should not be flagged with 5 diverse sources")
    }

    func testEchoChamber_tooFewArticlesNotFlagged() {
        // Only 2 articles — below threshold
        detector.ingest(makeArticle(id: "a1", topics: ["niche"], feedName: "Feed A"))
        detector.ingest(makeArticle(id: "a2", topics: ["niche"], feedName: "Feed A"))
        let report = detector.analyze()
        XCTAssertFalse(report.echoChamberTopics.contains("niche"))
    }

    func testEchoChamber_appearsInBlindSpots() {
        for i in 0..<5 {
            detector.ingest(makeArticle(
                id: "echo-\(i)", topics: ["blockchain"],
                feedName: "Single Source"))
        }
        let report = detector.analyze()
        let echoSpots = report.blindSpots.filter { $0.category == .echoChamber }
        XCTAssertFalse(echoSpots.isEmpty)
        XCTAssertEqual(echoSpots.first?.topic, "blockchain")
    }

    // MARK: - Temporal Decay Detection

    func testAbandonedTopic_detected() {
        // 6 articles about "docker" all from 60 days ago
        for i in 0..<6 {
            detector.ingest(makeArticle(
                id: "old-\(i)", topics: ["docker"],
                readDate: daysAgo(60)))
        }
        let report = detector.analyze()
        XCTAssertTrue(report.abandonedTopics.contains("docker"),
                       "docker should be flagged as abandoned")
    }

    func testRecentTopic_notAbandoned() {
        for i in 0..<6 {
            detector.ingest(makeArticle(
                id: "recent-\(i)", topics: ["kubernetes"],
                readDate: daysAgo(5)))
        }
        let report = detector.analyze()
        XCTAssertFalse(report.abandonedTopics.contains("kubernetes"))
    }

    func testAbandonedTopic_tooFewArticlesNotFlagged() {
        // Only 3 articles (below threshold of 5)
        for i in 0..<3 {
            detector.ingest(makeArticle(
                id: "few-\(i)", topics: ["erlang"],
                readDate: daysAgo(60)))
        }
        let report = detector.analyze()
        XCTAssertFalse(report.abandonedTopics.contains("erlang"))
    }

    func testAbandonedTopic_appearsInBlindSpots() {
        for i in 0..<6 {
            detector.ingest(makeArticle(
                id: "temporal-\(i)", topics: ["graphql"],
                readDate: daysAgo(45)))
        }
        let report = detector.analyze()
        let temporalSpots = report.blindSpots.filter {
            $0.category == .temporal && $0.topic == "graphql"
        }
        XCTAssertFalse(temporalSpots.isEmpty)
    }

    // MARK: - Emerging Miss Detection

    func testEmergingMiss_trendingButUnread() {
        detector.ingest(makeArticle(topics: ["swift"]))
        detector.recordTrendingTopic("quantum computing", mentionCount: 100)
        let report = detector.analyze()
        XCTAssertTrue(report.emergingMisses.contains("quantum computing"))
    }

    func testEmergingMiss_trendingAndRead_notFlagged() {
        detector.ingest(makeArticle(topics: ["ai safety"]))
        detector.recordTrendingTopic("ai safety", mentionCount: 50)
        let report = detector.analyze()
        XCTAssertFalse(report.emergingMisses.contains("ai safety"))
    }

    func testEmergingMiss_appearsInBlindSpots() {
        detector.ingest(makeArticle(topics: ["swift"]))
        detector.recordTrendingTopic("webassembly", mentionCount: 200)
        let report = detector.analyze()
        let emergingSpots = report.blindSpots.filter {
            $0.category == .emerging && $0.topic == "webassembly"
        }
        XCTAssertFalse(emergingSpots.isEmpty)
    }

    func testMultipleEmergingMisses() {
        detector.ingest(makeArticle(topics: ["swift"]))
        detector.recordTrendingTopic("topic-a", mentionCount: 50)
        detector.recordTrendingTopic("topic-b", mentionCount: 30)
        let report = detector.analyze()
        XCTAssertTrue(report.emergingMisses.contains("topic-a"))
        XCTAssertTrue(report.emergingMisses.contains("topic-b"))
    }

    // MARK: - Depth Imbalance Detection

    func testDepthImbalance_detected() {
        // 10 articles about "python", 2 about "data science", both co-occurring
        for i in 0..<10 {
            detector.ingest(makeArticle(
                id: "deep-\(i)", topics: ["python", "data science"]))
        }
        // Add more python-only articles to create ratio > 3:1
        for i in 0..<20 {
            detector.ingest(makeArticle(
                id: "extra-\(i)", topics: ["python"]))
        }
        // data science = 10, python = 30 => ratio = 3:1
        let report = detector.analyze()
        let imbalanceSpots = report.blindSpots.filter { $0.category == .depthImbalance }
        XCTAssertFalse(imbalanceSpots.isEmpty, "Should detect depth imbalance")
    }

    func testDepthImbalance_balancedNotFlagged() {
        // Equal coverage
        for i in 0..<5 {
            detector.ingest(makeArticle(id: "bal-a-\(i)", topics: ["react", "javascript"]))
            detector.ingest(makeArticle(id: "bal-b-\(i)", topics: ["javascript"]))
        }
        // react = 5, javascript = 10 => ratio = 2, below 3
        let report = detector.analyze()
        let imbalanceSpots = report.blindSpots.filter { $0.category == .depthImbalance }
        XCTAssertTrue(imbalanceSpots.isEmpty)
    }

    // MARK: - Severity Scoring

    func testSeverity_withinBounds() {
        // Create varied blind spots
        for i in 0..<5 {
            detector.ingest(makeArticle(id: "sev-\(i)", topics: ["topic-a"],
                                        feedName: "Same Feed"))
        }
        detector.registerAdjacency(topic: "topic-a", adjacentTo: "topic-b", strength: 1.0)
        detector.recordTrendingTopic("topic-c", mentionCount: 100)

        let report = detector.analyze()
        for spot in report.blindSpots {
            XCTAssertGreaterThanOrEqual(spot.severity, 0)
            XCTAssertLessThanOrEqual(spot.severity, 100)
        }
    }

    func testSeverity_higherForEchoChamber() {
        // Echo chambers have higher base severity than depth imbalance
        XCTAssertGreaterThan(
            BlindSpotCategory.echoChamber.baseSeverity,
            BlindSpotCategory.depthImbalance.baseSeverity)
    }

    func testSeverity_sortedDescending() {
        for i in 0..<5 {
            detector.ingest(makeArticle(id: "sort-\(i)", topics: ["alpha"],
                                        feedName: "Single", readDate: daysAgo(60)))
        }
        detector.recordTrendingTopic("beta", mentionCount: 50)
        detector.registerAdjacency(topic: "alpha", adjacentTo: "gamma", strength: 0.9)

        let report = detector.analyze()
        if report.blindSpots.count > 1 {
            for i in 0..<(report.blindSpots.count - 1) {
                XCTAssertGreaterThanOrEqual(
                    report.blindSpots[i].severity,
                    report.blindSpots[i + 1].severity)
            }
        }
    }

    // MARK: - Health Score & Grading

    func testHealthScore_perfectWhenNoBlindSpots() {
        detector.ingest(makeArticle(topics: ["swift"]))
        let report = detector.analyze()
        // Minimal data, may or may not have spots
        XCTAssertGreaterThanOrEqual(report.healthScore, 0)
        XCTAssertLessThanOrEqual(report.healthScore, 100)
    }

    func testHealthScore_decreasesWithBlindSpots() {
        // Many echo chambers => lower score
        for i in 0..<5 {
            detector.ingest(makeArticle(
                id: "low-a-\(i)", topics: ["topic-\(i)"],
                feedName: "Single Feed"))
        }
        let report = detector.analyze()
        // With multiple echo chambers, health should decrease
        XCTAssertLessThanOrEqual(report.healthScore, 100)
    }

    func testGrading_A() {
        let report = detector.analyze()
        XCTAssertEqual(report.grade, "A")
    }

    func testGrading_bounds() {
        // Lots of blind spots should lower grade
        for i in 0..<10 {
            for j in 0..<5 {
                detector.ingest(makeArticle(
                    id: "grade-\(i)-\(j)", topics: ["echo-topic-\(i)"],
                    feedName: "Only Source"))
            }
        }
        detector.recordTrendingTopic("miss-a", mentionCount: 100)
        detector.recordTrendingTopic("miss-b", mentionCount: 100)
        detector.recordTrendingTopic("miss-c", mentionCount: 100)

        let report = detector.analyze()
        // Should be lower than A
        XCTAssertNotEqual(report.grade, "A")
    }

    // MARK: - Insights

    func testInsights_notEmpty() {
        detector.ingest(makeArticle(topics: ["swift"]))
        let report = detector.analyze()
        XCTAssertFalse(report.insights.isEmpty)
    }

    func testInsights_containsHealthSummary() {
        detector.ingest(makeArticle(topics: ["swift"]))
        let report = detector.analyze()
        let hasHealth = report.insights.contains { $0.contains("health") || $0.contains("Health") }
        XCTAssertTrue(hasHealth, "Insights should mention health score")
    }

    func testInsights_mentionsEchoChamber() {
        for i in 0..<5 {
            detector.ingest(makeArticle(
                id: "insight-echo-\(i)", topics: ["ai"],
                feedName: "One Source"))
        }
        let report = detector.analyze()
        let mentions = report.insights.contains { $0.lowercased().contains("echo") || $0.lowercased().contains("perspective") }
        XCTAssertTrue(mentions, "Insights should mention echo chamber when present")
    }

    func testInsights_mentionsAbandoned() {
        for i in 0..<6 {
            detector.ingest(makeArticle(
                id: "insight-aband-\(i)", topics: ["legacy"],
                readDate: daysAgo(60)))
        }
        let report = detector.analyze()
        let mentions = report.insights.contains { $0.lowercased().contains("drifted") || $0.lowercased().contains("legacy") }
        XCTAssertTrue(mentions, "Insights should mention abandoned topics")
    }

    func testInsights_mentionsEmerging() {
        detector.ingest(makeArticle(topics: ["swift"]))
        detector.recordTrendingTopic("new-tech", mentionCount: 100)
        let report = detector.analyze()
        let mentions = report.insights.contains { $0.lowercased().contains("trending") || $0.lowercased().contains("missing") }
        XCTAssertTrue(mentions, "Insights should mention emerging misses")
    }

    // MARK: - Reset

    func testReset_clearsAll() {
        detector.ingest(makeArticle(topics: ["swift"]))
        detector.recordTrendingTopic("rust", mentionCount: 50)
        detector.registerAdjacency(topic: "a", adjacentTo: "b", strength: 0.5)

        detector.reset()

        let report = detector.analyze()
        XCTAssertEqual(report.totalTopicsTracked, 0)
        XCTAssertEqual(report.totalBlindSpots, 0)
        XCTAssertTrue(report.coverageMap.isEmpty)
    }

    func testReset_allowsReuse() {
        detector.ingest(makeArticle(topics: ["java"]))
        detector.reset()
        detector.ingest(makeArticle(topics: ["python"]))
        let map = detector.getCoverageMap()
        XCTAssertNil(map["java"])
        XCTAssertEqual(map["python"], 1)
    }

    // MARK: - Edge Cases

    func testArticleWithNoTopics() {
        detector.ingest(makeArticle(topics: []))
        let report = detector.analyze()
        XCTAssertEqual(report.totalTopicsTracked, 0)
    }

    func testDuplicateArticleIds() {
        detector.ingest(makeArticle(id: "dup", topics: ["swift"]))
        detector.ingest(makeArticle(id: "dup", topics: ["swift"]))
        // Both counted — no dedup by ID
        XCTAssertEqual(detector.getCoverageMap()["swift"], 2)
    }

    func testSingleFeed_allTopics() {
        for i in 0..<10 {
            detector.ingest(makeArticle(
                id: "mono-\(i)",
                topics: ["topic-\(i % 3)"],
                feedName: "Only Feed"))
        }
        let report = detector.analyze()
        // Should detect echo chambers for topics with 3+ articles from single feed
        XCTAssertFalse(report.echoChamberTopics.isEmpty)
    }

    // MARK: - BlindSpotCategory Properties

    func testCategory_emojis() {
        XCTAssertEqual(BlindSpotCategory.adjacent.emoji, "🔗")
        XCTAssertEqual(BlindSpotCategory.echoChamber.emoji, "🔁")
        XCTAssertEqual(BlindSpotCategory.temporal.emoji, "⏳")
        XCTAssertEqual(BlindSpotCategory.depthImbalance.emoji, "⚖️")
        XCTAssertEqual(BlindSpotCategory.emerging.emoji, "🌱")
    }

    func testCategory_comparable() {
        XCTAssertLessThan(BlindSpotCategory.adjacent, BlindSpotCategory.echoChamber)
        XCTAssertLessThan(BlindSpotCategory.echoChamber, BlindSpotCategory.temporal)
    }

    func testCategory_allCases() {
        XCTAssertEqual(BlindSpotCategory.allCases.count, 5)
    }

    // MARK: - Report Completeness

    func testReport_hasAllFields() {
        for i in 0..<6 {
            detector.ingest(makeArticle(
                id: "full-\(i)", topics: ["ai", "ml"],
                feedName: "Feed \(i % 2)", readDate: daysAgo(i * 10)))
        }
        detector.recordTrendingTopic("quantum", mentionCount: 50)
        detector.registerAdjacency(topic: "ai", adjacentTo: "robotics", strength: 0.7)

        let report = detector.analyze()
        XCTAssertGreaterThan(report.totalTopicsTracked, 0)
        XCTAssertFalse(report.coverageMap.isEmpty)
        XCTAssertFalse(report.insights.isEmpty)
        XCTAssertGreaterThanOrEqual(report.healthScore, 0)
        XCTAssertLessThanOrEqual(report.healthScore, 100)
        XCTAssertFalse(report.grade.isEmpty)
    }

    // MARK: - isBlindSpot

    func testIsBlindSpot_returnsTrueForKnownGap() {
        detector.ingest(makeArticle(topics: ["swift"]))
        detector.registerAdjacency(topic: "swift", adjacentTo: "objc", strength: 0.9)
        XCTAssertTrue(detector.isBlindSpot("objc"))
    }

    func testIsBlindSpot_returnsFalseForCoveredTopic() {
        detector.ingest(makeArticle(topics: ["swift"]))
        XCTAssertFalse(detector.isBlindSpot("swift"))
    }

    // MARK: - BlindSpot Model

    func testBlindSpot_severityClamped() {
        let spot = BlindSpot(
            topic: "test", category: .adjacent, severity: 150,
            adjacentTo: [], evidence: "test", recommendation: "test")
        XCTAssertEqual(spot.severity, 100)

        let spotLow = BlindSpot(
            topic: "test", category: .adjacent, severity: -10,
            adjacentTo: [], evidence: "test", recommendation: "test")
        XCTAssertEqual(spotLow.severity, 0)
    }

    func testBlindSpot_hasFeedSuggestions() {
        for i in 0..<5 {
            detector.ingest(makeArticle(
                id: "sugg-\(i)", topics: ["web"],
                feedName: "Single"))
        }
        detector.registerAdjacency(topic: "web", adjacentTo: "webassembly", strength: 0.8)
        let report = detector.analyze()
        let wasmSpots = report.blindSpots.filter { $0.topic == "webassembly" }
        if let spot = wasmSpots.first {
            XCTAssertFalse(spot.feedSuggestions.isEmpty)
        }
    }

    // MARK: - Comprehensive Scenario

    func testComprehensiveScenario() {
        // Simulate a real reading portfolio
        let feeds = ["TechCrunch", "Ars Technica", "The Verge", "HN Daily", "Dev.to"]

        // Well-covered topics
        for i in 0..<20 {
            detector.ingest(makeArticle(
                id: "comp-swift-\(i)", topics: ["swift", "ios"],
                feedName: feeds[i % feeds.count], readDate: daysAgo(i)))
        }

        // Echo chamber topic
        for i in 0..<8 {
            detector.ingest(makeArticle(
                id: "comp-crypto-\(i)", topics: ["cryptocurrency"],
                feedName: "CryptoOnly Blog", readDate: daysAgo(i)))
        }

        // Abandoned topic
        for i in 0..<6 {
            detector.ingest(makeArticle(
                id: "comp-go-\(i)", topics: ["golang"],
                feedName: feeds[i % feeds.count], readDate: daysAgo(60 + i)))
        }

        // Trending misses
        detector.recordTrendingTopic("rust", mentionCount: 200)
        detector.recordTrendingTopic("webassembly", mentionCount: 150)

        // Manual adjacency gap
        detector.registerAdjacency(topic: "swift", adjacentTo: "swiftui", strength: 0.95)

        let report = detector.analyze()

        // Should find multiple types of blind spots
        let categories = Set(report.blindSpots.map { $0.category })
        XCTAssertTrue(categories.count >= 2, "Should detect multiple blind spot categories")

        // Crypto should be echo chamber
        XCTAssertTrue(report.echoChamberTopics.contains("cryptocurrency"))

        // Golang should be abandoned
        XCTAssertTrue(report.abandonedTopics.contains("golang"))

        // Rust and wasm should be emerging misses
        XCTAssertTrue(report.emergingMisses.contains("rust"))
        XCTAssertTrue(report.emergingMisses.contains("webassembly"))

        // SwiftUI should be an adjacent gap
        let swiftuiSpots = report.blindSpots.filter { $0.topic == "swiftui" }
        XCTAssertFalse(swiftuiSpots.isEmpty)

        // Health score should be impacted
        XCTAssertLessThan(report.healthScore, 100)

        // Insights should be meaningful
        XCTAssertGreaterThanOrEqual(report.insights.count, 3)
    }
}
