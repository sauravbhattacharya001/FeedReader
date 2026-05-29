//
//  FeedSourceDiversityGuardianTests.swift
//  FeedReaderCoreTests
//
//  Tests for the FeedSourceDiversityGuardian — echo chamber detection
//  and source diversity advisor.
//

import XCTest
@testable import FeedReaderCore

final class FeedSourceDiversityGuardianTests: XCTestCase {

    private let guardian = FeedSourceDiversityGuardian()

    // MARK: - Helpers

    private func record(
        feed: String = "TechCrunch",
        topics: [String] = ["technology"],
        region: SourceRegion = .domestic,
        pubType: PublicationType = .mainstream,
        depth: ContentDepth = .standard
    ) -> DiversityReadRecord {
        DiversityReadRecord(
            articleId: UUID().uuidString,
            title: "Article from \(feed)",
            feedName: feed,
            topics: topics,
            region: region,
            publicationType: pubType,
            contentDepth: depth,
            readAt: Date()
        )
    }

    // MARK: - Insufficient Data

    func testInsufficientData() {
        let records = [record(), record()]
        let report = guardian.analyze(readingHistory: records)

        XCTAssertEqual(report.grade, "C")
        XCTAssertEqual(report.echoChamberRisk, .low)
        XCTAssertEqual(report.articleCount, 2)
        XCTAssertTrue(report.axes.isEmpty)
        XCTAssertEqual(report.alerts.count, 1)
        XCTAssertEqual(report.alerts.first?.severity, .info)
    }

    // MARK: - Perfect Diversity

    func testHighDiversity() {
        let records = [
            record(feed: "BBC", topics: ["politics"], region: .europe, pubType: .mainstream, depth: .analysis),
            record(feed: "ArXiv", topics: ["science"], region: .northAmerica, pubType: .academic, depth: .research),
            record(feed: "IndieWire", topics: ["culture"], region: .domestic, pubType: .independent, depth: .longform),
            record(feed: "Al Jazeera", topics: ["world"], region: .middleEast, pubType: .mainstream, depth: .standard),
            record(feed: "DevBlog", topics: ["technology"], region: .asia, pubType: .blog, depth: .breaking),
            record(feed: "Nature", topics: ["health"], region: .europe, pubType: .academic, depth: .research),
        ]
        let report = guardian.analyze(readingHistory: records)

        XCTAssertGreaterThan(report.overallScore, 70)
        XCTAssertTrue(report.echoChamberRisk <= .low)
    }

    // MARK: - Echo Chamber (Single Source)

    func testEchoChamber() {
        // All from one source, one topic, one region
        let records = (0..<20).map { _ in
            record(feed: "TechCrunch", topics: ["technology"], region: .domestic, pubType: .mainstream, depth: .breaking)
        }
        let report = guardian.analyze(readingHistory: records)

        XCTAssertLessThan(report.overallScore, 20)
        XCTAssertEqual(report.grade, "F")
        XCTAssertTrue(report.echoChamberRisk >= .high)
        XCTAssertFalse(report.alerts.isEmpty)
        XCTAssertFalse(report.recommendations.isEmpty)
    }

    // MARK: - Alerts Fire on Concentration

    func testConcentrationAlert() {
        // 8 out of 10 from same feed
        var records = (0..<8).map { _ in record(feed: "HackerNews", topics: ["tech"]) }
        records += [
            record(feed: "BBC", topics: ["world"]),
            record(feed: "Nature", topics: ["science"]),
        ]
        let report = guardian.analyze(readingHistory: records)

        let sourceAlerts = report.alerts.filter { $0.axis == .sourceConcentration }
        XCTAssertFalse(sourceAlerts.isEmpty)
        XCTAssertTrue(sourceAlerts.contains { $0.severity == .critical })
    }

    // MARK: - Recommendations Generated

    func testRecommendationsForLowScore() {
        let records = (0..<10).map { _ in
            record(feed: "TechCrunch", topics: ["ai"], region: .domestic, pubType: .mainstream, depth: .breaking)
        }
        let report = guardian.analyze(readingHistory: records)

        XCTAssertFalse(report.recommendations.isEmpty)
        // Should recommend diversity challenge for high risk
        let challenges = report.recommendations.filter { $0.actionType == .diversityChallenge }
        XCTAssertFalse(challenges.isEmpty)
    }

    // MARK: - Summary String

    func testSummary() {
        let records = (0..<6).map { _ in record() }
        let report = guardian.analyze(readingHistory: records)

        XCTAssertTrue(report.summary.contains("Diversity grade"))
        XCTAssertTrue(report.summary.contains("Echo chamber risk"))
    }

    // MARK: - Custom Config

    func testCustomConfig() {
        let config = DiversityGuardianConfig(
            minArticlesForAnalysis: 3,
            windowDays: 7,
            concentrationAlertThreshold: 0.9
        )
        let records = [
            record(feed: "A", topics: ["x"]),
            record(feed: "A", topics: ["x"]),
            record(feed: "B", topics: ["y"]),
        ]
        let report = guardian.analyze(readingHistory: records, config: config)

        // With threshold at 0.9, 66% concentration shouldn't fire alert
        let critAlerts = report.alerts.filter { $0.severity == .critical && $0.axis == .sourceConcentration }
        XCTAssertTrue(critAlerts.isEmpty)
    }

    // MARK: - Window Filtering

    func testOldArticlesFiltered() {
        let old = DiversityReadRecord(
            articleId: "old",
            title: "Old Article",
            feedName: "OldFeed",
            topics: ["history"],
            region: .europe,
            publicationType: .academic,
            contentDepth: .research,
            readAt: Calendar.current.date(byAdding: .day, value: -60, to: Date())!
        )
        let recent = (0..<5).map { _ in record() }
        let report = guardian.analyze(readingHistory: [old] + recent)

        // Old article should be filtered out of 30-day window
        XCTAssertEqual(report.articleCount, 5)
    }

    // MARK: - EchoChamberRisk Comparable

    func testRiskComparable() {
        XCTAssertTrue(EchoChamberRisk.none < EchoChamberRisk.low)
        XCTAssertTrue(EchoChamberRisk.low < EchoChamberRisk.moderate)
        XCTAssertTrue(EchoChamberRisk.high < EchoChamberRisk.severe)
    }

    // MARK: - Geographic Diversity Scoring

    func testGeographicDiversityScoring() {
        let records = [
            record(region: .domestic),
            record(region: .europe),
            record(region: .asia),
            record(region: .africa),
            record(region: .latinAmerica),
        ]
        let report = guardian.analyze(readingHistory: records)

        let geoAxis = report.axes.first { $0.axis == .geographicSpread }
        XCTAssertNotNil(geoAxis)
        XCTAssertGreaterThan(geoAxis!.score, 80)
        XCTAssertEqual(geoAxis!.uniqueCount, 5)
    }

    // MARK: - Empty Topics Handled

    func testEmptyTopicsFallback() {
        let records = (0..<5).map { _ in
            DiversityReadRecord(
                articleId: UUID().uuidString,
                title: "No Topic",
                feedName: "Feed",
                topics: [],
                readAt: Date()
            )
        }
        let report = guardian.analyze(readingHistory: records)

        let topicAxis = report.axes.first { $0.axis == .topicConcentration }
        XCTAssertNotNil(topicAxis)
        XCTAssertEqual(topicAxis!.dominantValue, "uncategorized")
    }
}
