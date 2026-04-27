//
//  FeedInterestEvolverTests.swift
//  FeedReaderCoreTests
//
//  Tests for FeedInterestEvolver: snapshot recording, phase classification,
//  trajectory analysis, prediction, biography generation, and curiosity metrics.
//

import XCTest
@testable import FeedReaderCore

final class FeedInterestEvolverTests: XCTestCase {

    private func daysAgo(_ n: Int) -> Date {
        return Calendar.current.date(byAdding: .day, value: -n, to: Date())!
    }

    private func makeEvolver() -> FeedInterestEvolver {
        let e = FeedInterestEvolver()
        e.minimumTopicWeight = 0.02
        return e
    }

    // MARK: - Snapshot Recording

    func testRecordSnapshotReturnsNilForEmptyArticles() {
        let evolver = makeEvolver()
        let snapshot = evolver.recordSnapshot(articles: [])
        XCTAssertNil(snapshot)
        XCTAssertEqual(evolver.snapshotCount, 0)
    }

    func testRecordSnapshotCreatesSnapshot() {
        let evolver = makeEvolver()
        let snapshot = evolver.recordSnapshot(articles: [
            (title: "Machine learning advances in healthcare",
             body: "Researchers used machine learning to predict patient outcomes in clinical trials.",
             feedName: "TechNews")
        ])
        XCTAssertNotNil(snapshot)
        XCTAssertEqual(evolver.snapshotCount, 1)
        XCTAssertEqual(snapshot?.articleCount, 1)
        XCTAssertFalse(snapshot!.topicWeights.isEmpty)
    }

    func testRecordMultipleSnapshots() {
        let evolver = makeEvolver()
        evolver.recordSnapshot(articles: [
            (title: "AI breakthroughs", body: "AI models improving", feedName: "Tech")
        ], timestamp: daysAgo(30))
        evolver.recordSnapshot(articles: [
            (title: "Climate change report", body: "Global temperatures rising", feedName: "Science")
        ], timestamp: daysAgo(15))
        evolver.recordSnapshot(articles: [
            (title: "Space exploration updates", body: "NASA launches new mission", feedName: "Space")
        ], timestamp: Date())

        XCTAssertEqual(evolver.snapshotCount, 3)
    }

    func testSnapshotWeightsNormalizeToApproxOne() {
        let evolver = makeEvolver()
        let snapshot = evolver.recordSnapshot(articles: [
            (title: "Python programming tutorial", body: "Learn Python basics for data science", feedName: "Dev"),
            (title: "JavaScript framework review", body: "React vs Vue comparison for web development", feedName: "Dev"),
            (title: "Database optimization guide", body: "SQL performance tuning tips for production databases", feedName: "Dev")
        ])
        XCTAssertNotNil(snapshot)
        let total = snapshot!.topicWeights.values.reduce(0, +)
        XCTAssertEqual(total, 1.0, accuracy: 0.01)
    }

    // MARK: - Reset

    func testResetClearsSnapshots() {
        let evolver = makeEvolver()
        evolver.recordSnapshot(articles: [
            (title: "Test article", body: "Some content here", feedName: "Feed")
        ])
        XCTAssertEqual(evolver.snapshotCount, 1)
        evolver.reset()
        XCTAssertEqual(evolver.snapshotCount, 0)
    }

    // MARK: - Evolution Analysis

    func testAnalyzeEvolutionWithInsufficientSnapshots() {
        let evolver = makeEvolver()
        evolver.recordSnapshot(articles: [
            (title: "Test", body: "Just one snapshot", feedName: "Feed")
        ])
        let report = evolver.analyzeEvolution()
        XCTAssertTrue(report.trajectories.isEmpty)
        XCTAssertEqual(report.snapshotCount, 1)
    }

    func testAnalyzeEvolutionWithTwoSnapshots() {
        let evolver = makeEvolver()
        evolver.recordSnapshot(articles: [
            (title: "Quantum computing research", body: "Quantum processors reach new milestone in computing power", feedName: "Physics")
        ], timestamp: daysAgo(14))
        evolver.recordSnapshot(articles: [
            (title: "Quantum computing breakthrough", body: "New quantum algorithm solves optimization problems faster", feedName: "Physics")
        ], timestamp: Date())

        let report = evolver.analyzeEvolution()
        XCTAssertFalse(report.trajectories.isEmpty)
        XCTAssertEqual(report.snapshotCount, 2)
        XCTAssertGreaterThan(report.timeSpanDays, 0)
    }

    func testEmergingTopicDetection() {
        let evolver = makeEvolver()
        // Snapshot 1: no mention of "blockchain"
        evolver.addSnapshot(InterestSnapshot(
            timestamp: daysAgo(30),
            topicWeights: ["climate": 0.4, "politics": 0.3, "sports": 0.3],
            articleCount: 10
        ))
        // Snapshot 2: still no blockchain
        evolver.addSnapshot(InterestSnapshot(
            timestamp: daysAgo(20),
            topicWeights: ["climate": 0.35, "politics": 0.35, "sports": 0.3],
            articleCount: 10
        ))
        // Snapshot 3: blockchain emerges
        evolver.addSnapshot(InterestSnapshot(
            timestamp: daysAgo(10),
            topicWeights: ["climate": 0.25, "politics": 0.25, "sports": 0.2, "blockchain": 0.15, "crypto": 0.15],
            articleCount: 12
        ))
        // Snapshot 4: blockchain growing
        evolver.addSnapshot(InterestSnapshot(
            timestamp: Date(),
            topicWeights: ["climate": 0.15, "politics": 0.15, "blockchain": 0.35, "crypto": 0.25, "sports": 0.1],
            articleCount: 15
        ))

        let report = evolver.analyzeEvolution()
        let emergingTopics = report.emergingTopics.map { $0.topic }
        // blockchain or crypto should be emerging/growing
        let hasBlockchainOrCrypto = emergingTopics.contains("blockchain") || emergingTopics.contains("crypto")
        XCTAssertTrue(hasBlockchainOrCrypto, "Expected blockchain or crypto to be emerging, got: \(emergingTopics)")
    }

    func testFadingTopicDetection() {
        let evolver = makeEvolver()
        // Topic starts strong, fades away
        evolver.addSnapshot(InterestSnapshot(
            timestamp: daysAgo(30),
            topicWeights: ["cooking": 0.5, "travel": 0.3, "music": 0.2],
            articleCount: 10
        ))
        evolver.addSnapshot(InterestSnapshot(
            timestamp: daysAgo(20),
            topicWeights: ["cooking": 0.3, "travel": 0.4, "music": 0.3],
            articleCount: 10
        ))
        evolver.addSnapshot(InterestSnapshot(
            timestamp: daysAgo(10),
            topicWeights: ["cooking": 0.1, "travel": 0.5, "music": 0.4],
            articleCount: 10
        ))
        evolver.addSnapshot(InterestSnapshot(
            timestamp: Date(),
            topicWeights: ["travel": 0.5, "music": 0.45, "cooking": 0.05],
            articleCount: 10
        ))

        let report = evolver.analyzeEvolution()
        let fadingTopics = report.fadingTopics.map { $0.topic }
        XCTAssertTrue(fadingTopics.contains("cooking"), "Expected cooking to be fading, got: \(fadingTopics)")
    }

    func testStablePassionDetection() {
        let evolver = makeEvolver()
        // Topic stays consistently high
        evolver.addSnapshot(InterestSnapshot(
            timestamp: daysAgo(30),
            topicWeights: ["programming": 0.35, "gaming": 0.35, "news": 0.3],
            articleCount: 10
        ))
        evolver.addSnapshot(InterestSnapshot(
            timestamp: daysAgo(20),
            topicWeights: ["programming": 0.33, "gaming": 0.34, "news": 0.33],
            articleCount: 10
        ))
        evolver.addSnapshot(InterestSnapshot(
            timestamp: daysAgo(10),
            topicWeights: ["programming": 0.34, "gaming": 0.33, "news": 0.33],
            articleCount: 10
        ))
        evolver.addSnapshot(InterestSnapshot(
            timestamp: Date(),
            topicWeights: ["programming": 0.35, "gaming": 0.33, "news": 0.32],
            articleCount: 10
        ))

        let report = evolver.analyzeEvolution()
        let stableTopics = report.stablePassions.map { $0.topic }
        // At least one topic should be detected as stable
        XCTAssertFalse(stableTopics.isEmpty, "Expected at least one stable passion")
    }

    func testCyclicalTopicDetection() {
        let evolver = makeEvolver()
        // Topic that oscillates: high, low, high, low, high
        evolver.addSnapshot(InterestSnapshot(
            timestamp: daysAgo(50), topicWeights: ["elections": 0.5, "science": 0.5], articleCount: 10
        ))
        evolver.addSnapshot(InterestSnapshot(
            timestamp: daysAgo(40), topicWeights: ["elections": 0.1, "science": 0.9], articleCount: 10
        ))
        evolver.addSnapshot(InterestSnapshot(
            timestamp: daysAgo(30), topicWeights: ["elections": 0.6, "science": 0.4], articleCount: 10
        ))
        evolver.addSnapshot(InterestSnapshot(
            timestamp: daysAgo(20), topicWeights: ["elections": 0.1, "science": 0.9], articleCount: 10
        ))
        evolver.addSnapshot(InterestSnapshot(
            timestamp: daysAgo(10), topicWeights: ["elections": 0.5, "science": 0.5], articleCount: 10
        ))

        let report = evolver.analyzeEvolution()
        let cyclicalTopics = report.cyclicalTopics.map { $0.topic }
        // "elections" should be cyclical with its oscillating pattern
        XCTAssertTrue(cyclicalTopics.contains("elections"), "Expected elections to be cyclical, got: \(cyclicalTopics)")
    }

    // MARK: - Predictions

    func testPredictionsAreGenerated() {
        let evolver = makeEvolver()
        evolver.addSnapshot(InterestSnapshot(
            timestamp: daysAgo(20), topicWeights: ["ai": 0.3, "robotics": 0.4, "art": 0.3], articleCount: 10
        ))
        evolver.addSnapshot(InterestSnapshot(
            timestamp: daysAgo(10), topicWeights: ["ai": 0.4, "robotics": 0.35, "art": 0.25], articleCount: 10
        ))
        evolver.addSnapshot(InterestSnapshot(
            timestamp: Date(), topicWeights: ["ai": 0.5, "robotics": 0.3, "art": 0.2], articleCount: 10
        ))

        let report = evolver.analyzeEvolution()
        XCTAssertFalse(report.predictions.isEmpty, "Expected predictions to be generated")
        // AI should be predicted high given its upward trend
        if let aiPrediction = report.predictions.first(where: { $0.topic == "ai" }) {
            XCTAssertGreaterThan(aiPrediction.weight, 0)
            XCTAssertGreaterThan(aiPrediction.confidence, 0)
        }
    }

    // MARK: - Curiosity Metrics

    func testCuriosityBreadth() {
        let evolver = makeEvolver()
        evolver.addSnapshot(InterestSnapshot(
            timestamp: daysAgo(10),
            topicWeights: ["a": 0.25, "b": 0.25, "c": 0.25, "d": 0.25],
            articleCount: 10
        ))
        evolver.addSnapshot(InterestSnapshot(
            timestamp: Date(),
            topicWeights: ["a": 0.2, "b": 0.2, "c": 0.2, "d": 0.2, "e": 0.2],
            articleCount: 10
        ))

        let report = evolver.analyzeEvolution()
        XCTAssertEqual(report.curiosityBreadth, 5) // 5 unique topics across all snapshots
    }

    func testDiversityEntropyHigherForEvenDistribution() {
        let evolver = makeEvolver()
        // Even distribution
        evolver.addSnapshot(InterestSnapshot(
            timestamp: daysAgo(10),
            topicWeights: ["a": 0.25, "b": 0.25, "c": 0.25, "d": 0.25],
            articleCount: 10
        ))
        evolver.addSnapshot(InterestSnapshot(
            timestamp: Date(),
            topicWeights: ["a": 0.25, "b": 0.25, "c": 0.25, "d": 0.25],
            articleCount: 10
        ))
        let evenReport = evolver.analyzeEvolution()

        let evolver2 = makeEvolver()
        // Concentrated distribution
        evolver2.addSnapshot(InterestSnapshot(
            timestamp: daysAgo(10),
            topicWeights: ["a": 0.9, "b": 0.1],
            articleCount: 10
        ))
        evolver2.addSnapshot(InterestSnapshot(
            timestamp: Date(),
            topicWeights: ["a": 0.9, "b": 0.1],
            articleCount: 10
        ))
        let concentratedReport = evolver2.analyzeEvolution()

        XCTAssertGreaterThan(evenReport.diversityEntropy, concentratedReport.diversityEntropy)
    }

    // MARK: - Biography

    func testBiographyEntriesGenerated() {
        let evolver = makeEvolver()
        evolver.addSnapshot(InterestSnapshot(
            timestamp: daysAgo(30),
            topicWeights: ["cooking": 0.5, "travel": 0.5],
            articleCount: 10
        ))
        evolver.addSnapshot(InterestSnapshot(
            timestamp: daysAgo(20),
            topicWeights: ["cooking": 0.3, "travel": 0.3, "photography": 0.4],
            articleCount: 10
        ))
        evolver.addSnapshot(InterestSnapshot(
            timestamp: daysAgo(10),
            topicWeights: ["cooking": 0.1, "photography": 0.5, "travel": 0.4],
            articleCount: 10
        ))
        evolver.addSnapshot(InterestSnapshot(
            timestamp: Date(),
            topicWeights: ["photography": 0.6, "travel": 0.35, "cooking": 0.05],
            articleCount: 10
        ))

        let report = evolver.analyzeEvolution()
        XCTAssertFalse(report.biography.isEmpty, "Expected biography entries")

        // Should have at least a discovery event for photography
        let discoveries = report.biography.filter { $0.eventType == .discoveredTopic }
        XCTAssertFalse(discoveries.isEmpty, "Expected at least one topic discovery")
    }

    func testBiographyChronologicalOrder() {
        let evolver = makeEvolver()
        evolver.addSnapshot(InterestSnapshot(
            timestamp: daysAgo(20), topicWeights: ["a": 0.5, "b": 0.5], articleCount: 5
        ))
        evolver.addSnapshot(InterestSnapshot(
            timestamp: daysAgo(10), topicWeights: ["a": 0.3, "c": 0.7], articleCount: 5
        ))
        evolver.addSnapshot(InterestSnapshot(
            timestamp: Date(), topicWeights: ["c": 0.8, "d": 0.2], articleCount: 5
        ))

        let report = evolver.analyzeEvolution()
        for i in 1..<report.biography.count {
            XCTAssertLessThanOrEqual(
                report.biography[i - 1].date, report.biography[i].date,
                "Biography should be in chronological order"
            )
        }
    }

    // MARK: - Edge Cases

    func testAddPrebuiltSnapshot() {
        let evolver = makeEvolver()
        let snapshot = InterestSnapshot(
            timestamp: Date(), topicWeights: ["test": 0.5, "code": 0.5], articleCount: 5
        )
        evolver.addSnapshot(snapshot)
        XCTAssertEqual(evolver.snapshotCount, 1)
    }

    func testSnapshotsAreSortedChronologically() {
        let evolver = makeEvolver()
        // Add out of order
        evolver.addSnapshot(InterestSnapshot(
            timestamp: Date(), topicWeights: ["c": 1.0], articleCount: 1
        ))
        evolver.addSnapshot(InterestSnapshot(
            timestamp: daysAgo(30), topicWeights: ["a": 1.0], articleCount: 1
        ))
        evolver.addSnapshot(InterestSnapshot(
            timestamp: daysAgo(15), topicWeights: ["b": 1.0], articleCount: 1
        ))

        // Analysis should still work (internally sorted)
        let report = evolver.analyzeEvolution()
        XCTAssertEqual(report.snapshotCount, 3)
        XCTAssertGreaterThan(report.timeSpanDays, 0)
    }

    func testMomentumPositiveForGrowingTopic() {
        let evolver = makeEvolver()
        evolver.addSnapshot(InterestSnapshot(
            timestamp: daysAgo(30), topicWeights: ["growing": 0.1, "other": 0.9], articleCount: 10
        ))
        evolver.addSnapshot(InterestSnapshot(
            timestamp: daysAgo(20), topicWeights: ["growing": 0.3, "other": 0.7], articleCount: 10
        ))
        evolver.addSnapshot(InterestSnapshot(
            timestamp: daysAgo(10), topicWeights: ["growing": 0.5, "other": 0.5], articleCount: 10
        ))
        evolver.addSnapshot(InterestSnapshot(
            timestamp: Date(), topicWeights: ["growing": 0.7, "other": 0.3], articleCount: 10
        ))

        let report = evolver.analyzeEvolution()
        if let growingTrajectory = report.trajectories.first(where: { $0.topic == "growing" }) {
            XCTAssertGreaterThan(growingTrajectory.momentum, 0, "Growing topic should have positive momentum")
        } else {
            XCTFail("Expected to find trajectory for 'growing'")
        }
    }

    func testMomentumNegativeForFadingTopic() {
        let evolver = makeEvolver()
        evolver.addSnapshot(InterestSnapshot(
            timestamp: daysAgo(30), topicWeights: ["fading": 0.7, "other": 0.3], articleCount: 10
        ))
        evolver.addSnapshot(InterestSnapshot(
            timestamp: daysAgo(20), topicWeights: ["fading": 0.5, "other": 0.5], articleCount: 10
        ))
        evolver.addSnapshot(InterestSnapshot(
            timestamp: daysAgo(10), topicWeights: ["fading": 0.3, "other": 0.7], articleCount: 10
        ))
        evolver.addSnapshot(InterestSnapshot(
            timestamp: Date(), topicWeights: ["fading": 0.1, "other": 0.9], articleCount: 10
        ))

        let report = evolver.analyzeEvolution()
        if let fadingTrajectory = report.trajectories.first(where: { $0.topic == "fading" }) {
            XCTAssertLessThan(fadingTrajectory.momentum, 0, "Fading topic should have negative momentum")
        } else {
            XCTFail("Expected to find trajectory for 'fading'")
        }
    }

    func testTrajectoryPhaseEnumProperties() {
        for phase in InterestPhase.allCases {
            XCTAssertFalse(phase.emoji.isEmpty, "\(phase) should have an emoji")
            XCTAssertFalse(phase.displayName.isEmpty, "\(phase) should have a display name")
            XCTAssertFalse(phase.rawValue.isEmpty, "\(phase) should have a raw value")
        }
    }

    func testBiographyEventTypeEnumCoverage() {
        let allTypes = BiographyEventType.allCases
        XCTAssertEqual(allTypes.count, 7, "Expected 7 biography event types")
        for eventType in allTypes {
            XCTAssertFalse(eventType.rawValue.isEmpty)
        }
    }
}
