//
//  FeedAttentionAllocatorTests.swift
//  FeedReaderCoreTests
//
//  Tests for FeedAttentionAllocator — autonomous attention budget manager.
//

import XCTest
@testable import FeedReaderCore

final class FeedAttentionAllocatorTests: XCTestCase {

    private var allocator: FeedAttentionAllocator!

    override func setUp() {
        super.setUp()
        allocator = FeedAttentionAllocator()
    }

    // MARK: - Helpers

    private func makeRecord(topic: String = "Tech",
                            source: String = "TechCrunch",
                            minutes: Double = 5.0,
                            articleId: String? = nil) -> AttentionRecord {
        AttentionRecord(
            articleId: articleId ?? UUID().uuidString,
            topic: topic,
            source: source,
            minutesSpent: minutes,
            timestamp: Date()
        )
    }

    private func makeRecords(count: Int, topic: String = "Tech",
                              source: String = "TechCrunch",
                              minutes: Double = 5.0) -> [AttentionRecord] {
        (0..<count).map { _ in makeRecord(topic: topic, source: source, minutes: minutes) }
    }

    private func makeDiverseRecords() -> [AttentionRecord] {
        [
            makeRecord(topic: "Tech", source: "TechCrunch", minutes: 10),
            makeRecord(topic: "Science", source: "Nature", minutes: 8),
            makeRecord(topic: "Politics", source: "BBC", minutes: 7),
            makeRecord(topic: "Sports", source: "ESPN", minutes: 6),
            makeRecord(topic: "Arts", source: "Guardian", minutes: 5),
        ]
    }

    // MARK: - Basic Analysis

    func testAnalyzeReturnsNilForTooFewRecords() {
        let records = makeRecords(count: 3)
        XCTAssertNil(allocator.analyze(records: records))
    }

    func testAnalyzeReturnsNilForEmptyRecords() {
        XCTAssertNil(allocator.analyze(records: []))
    }

    func testAnalyzeReturnsReportForMinimumRecords() {
        allocator.minRecordsForAnalysis = 5
        let records = makeDiverseRecords()
        let report = allocator.analyze(records: records)
        XCTAssertNotNil(report)
    }

    func testAnalyzeReturnsReportWithCorrectRecordCount() {
        let records = makeDiverseRecords()
        let report = allocator.analyze(records: records)
        XCTAssertEqual(report?.records.count, 5)
    }

    func testAnalyzeGeneratesReportDate() {
        let records = makeDiverseRecords()
        let report = allocator.analyze(records: records)!
        XCTAssertTrue(report.generatedAt.timeIntervalSinceNow < 1)
    }

    func testAnalyzeWithCustomMinRecords() {
        allocator.minRecordsForAnalysis = 2
        let records = makeRecords(count: 2, topic: "Tech")
        let report = allocator.analyze(records: records)
        XCTAssertNotNil(report)
    }

    // MARK: - Diversity Score

    func testPerfectDiversityScore() {
        let topicMinutes: [String: Double] = [
            "A": 10, "B": 10, "C": 10, "D": 10, "E": 10
        ]
        let score = allocator.computeDiversityScore(topicMinutes: topicMinutes)
        XCTAssertEqual(score, 100.0, accuracy: 0.1)
    }

    func testZeroDiversitySingleTopic() {
        let topicMinutes: [String: Double] = ["Only": 100]
        let score = allocator.computeDiversityScore(topicMinutes: topicMinutes)
        XCTAssertEqual(score, 0.0, accuracy: 0.1)
    }

    func testZeroDiversityEmptyTopics() {
        let score = allocator.computeDiversityScore(topicMinutes: [:])
        XCTAssertEqual(score, 0.0)
    }

    func testLowDiversityDominantTopic() {
        let topicMinutes: [String: Double] = ["Dominant": 90, "Tiny": 5, "Small": 5]
        let score = allocator.computeDiversityScore(topicMinutes: topicMinutes)
        XCTAssertLessThan(score, 50)
    }

    func testHighDiversityEvenDistribution() {
        let topicMinutes: [String: Double] = [
            "A": 12, "B": 11, "C": 13, "D": 10, "E": 14
        ]
        let score = allocator.computeDiversityScore(topicMinutes: topicMinutes)
        XCTAssertGreaterThan(score, 90)
    }

    func testDiversityScoreTwoTopicsEqual() {
        let topicMinutes: [String: Double] = ["A": 50, "B": 50]
        let score = allocator.computeDiversityScore(topicMinutes: topicMinutes)
        XCTAssertEqual(score, 100.0, accuracy: 0.1)
    }

    func testDiversityScoreTwoTopicsUnequal() {
        let topicMinutes: [String: Double] = ["A": 95, "B": 5]
        let score = allocator.computeDiversityScore(topicMinutes: topicMinutes)
        XCTAssertLessThan(score, 50)
    }

    // MARK: - Efficiency

    func testPerfectEfficiency() {
        let budgets = [
            AttentionBudget(category: "A", budgetMinutes: 20, actualMinutes: 20),
            AttentionBudget(category: "B", budgetMinutes: 30, actualMinutes: 30),
        ]
        let eff = allocator.computeEfficiency(budgets: budgets)
        XCTAssertEqual(eff, 100.0, accuracy: 0.1)
    }

    func testZeroEfficiency() {
        let budgets = [
            AttentionBudget(category: "A", budgetMinutes: 10, actualMinutes: 0),
        ]
        let eff = allocator.computeEfficiency(budgets: budgets)
        XCTAssertEqual(eff, 0.0, accuracy: 0.1)
    }

    func testMixedEfficiency() {
        let budgets = [
            AttentionBudget(category: "A", budgetMinutes: 20, actualMinutes: 20), // perfect
            AttentionBudget(category: "B", budgetMinutes: 20, actualMinutes: 0),  // zero
        ]
        let eff = allocator.computeEfficiency(budgets: budgets)
        XCTAssertEqual(eff, 50.0, accuracy: 0.1)
    }

    func testEfficiencyEmptyBudgets() {
        let eff = allocator.computeEfficiency(budgets: [])
        XCTAssertEqual(eff, 0.0)
    }

    func testEfficiencyOverBudget() {
        // 200% utilization → deviation = 1.0 → score = 0
        let budgets = [
            AttentionBudget(category: "A", budgetMinutes: 10, actualMinutes: 20),
        ]
        let eff = allocator.computeEfficiency(budgets: budgets)
        XCTAssertEqual(eff, 0.0, accuracy: 0.1)
    }

    func testEfficiencySlightlyOver() {
        // 120% utilization → deviation = 0.2 → score = 80
        let budgets = [
            AttentionBudget(category: "A", budgetMinutes: 10, actualMinutes: 12),
        ]
        let eff = allocator.computeEfficiency(budgets: budgets)
        XCTAssertEqual(eff, 80.0, accuracy: 0.1)
    }

    // MARK: - Budget Computation

    func testDefaultBudgetsSplitEvenly() {
        allocator.defaultDailyBudgetMinutes = 60
        let records = makeDiverseRecords() // 5 topics
        let report = allocator.analyze(records: records)!
        // 60 / 5 = 12 per topic
        for budget in report.budgets {
            XCTAssertEqual(budget.budgetMinutes, 12.0, accuracy: 0.01)
        }
    }

    func testCustomBudgetsUsed() {
        let records = makeDiverseRecords()
        let customBudgets = [
            AttentionBudget(category: "Tech", budgetMinutes: 20, actualMinutes: 0),
            AttentionBudget(category: "Science", budgetMinutes: 15, actualMinutes: 0),
        ]
        let report = allocator.analyze(records: records, customBudgets: customBudgets)!
        let techBudget = report.budgets.first { $0.category == "Tech" }
        XCTAssertEqual(techBudget?.budgetMinutes, 20.0)
    }

    func testBudgetUtilizationRatio() {
        let budget = AttentionBudget(category: "A", budgetMinutes: 20, actualMinutes: 30)
        XCTAssertEqual(budget.utilizationRatio, 1.5, accuracy: 0.01)
    }

    func testBudgetUtilizationZeroBudget() {
        let budget = AttentionBudget(category: "A", budgetMinutes: 0, actualMinutes: 5)
        XCTAssertTrue(budget.utilizationRatio.isInfinite)
    }

    func testBudgetUtilizationBothZero() {
        let budget = AttentionBudget(category: "A", budgetMinutes: 0, actualMinutes: 0)
        XCTAssertEqual(budget.utilizationRatio, 0)
    }

    // MARK: - Sink Detection: Rabbit Hole

    func testRabbitHoleDetected() {
        // One topic with >35% and >3 articles
        var records = makeRecords(count: 5, topic: "AI", minutes: 15)
        records.append(makeRecord(topic: "Other", minutes: 5))
        records.append(makeRecord(topic: "Sports", minutes: 5))
        let report = allocator.analyze(records: records)!
        let rabbitHoles = report.sinks.filter { $0.sinkType == .rabbitHole }
        XCTAssertFalse(rabbitHoles.isEmpty)
        XCTAssertEqual(rabbitHoles.first?.category, "AI")
    }

    func testNoRabbitHoleWhenBelowThreshold() {
        // Spread evenly — no single topic dominates
        let records = makeDiverseRecords()
        let report = allocator.analyze(records: records)!
        let rabbitHoles = report.sinks.filter { $0.sinkType == .rabbitHole }
        XCTAssertTrue(rabbitHoles.isEmpty)
    }

    func testRabbitHoleNeedsMoreThan3Articles() {
        // High ratio but only 3 articles
        var records = makeRecords(count: 3, topic: "AI", minutes: 30)
        records += makeRecords(count: 2, topic: "Other", minutes: 2)
        let report = allocator.analyze(records: records)!
        let rabbitHoles = report.sinks.filter { $0.sinkType == .rabbitHole }
        XCTAssertTrue(rabbitHoles.isEmpty)
    }

    // MARK: - Sink Detection: Doom Scroll

    func testDoomScrollDetected() {
        // One source > 40% of total time
        var records = makeRecords(count: 4, topic: "News", source: "CNN", minutes: 15)
        records.append(makeRecord(topic: "Tech", source: "TC", minutes: 5))
        records.append(makeRecord(topic: "Sci", source: "Nature", minutes: 5))
        let report = allocator.analyze(records: records)!
        let doomScrolls = report.sinks.filter { $0.sinkType == .doomScroll }
        XCTAssertFalse(doomScrolls.isEmpty)
    }

    func testNoDoomScrollWhenSourcesBalanced() {
        let records = makeDiverseRecords() // all different sources
        let report = allocator.analyze(records: records)!
        let doomScrolls = report.sinks.filter { $0.sinkType == .doomScroll }
        XCTAssertTrue(doomScrolls.isEmpty)
    }

    // MARK: - Sink Detection: Echo Chamber

    func testEchoChamberDetected() {
        // >60% articles same topic + low diversity
        var records = makeRecords(count: 8, topic: "Politics", source: "Fox", minutes: 5)
        records.append(makeRecord(topic: "Weather", source: "WC", minutes: 2))
        records.append(makeRecord(topic: "Local", source: "Local", minutes: 1))
        allocator.minRecordsForAnalysis = 5
        let report = allocator.analyze(records: records)!
        let echoChambers = report.sinks.filter { $0.sinkType == .echoChamber }
        XCTAssertFalse(echoChambers.isEmpty)
    }

    // MARK: - Sink Detection: Novelty Trap

    func testNoveltyTrapDetected() {
        // Many topics with <2 min each
        let records = [
            makeRecord(topic: "A", minutes: 1),
            makeRecord(topic: "B", minutes: 1.5),
            makeRecord(topic: "C", minutes: 0.5),
            makeRecord(topic: "D", minutes: 1),
            makeRecord(topic: "E", minutes: 0.8),
            makeRecord(topic: "F", minutes: 1.2),
        ]
        allocator.minRecordsForAnalysis = 5
        let report = allocator.analyze(records: records)!
        let traps = report.sinks.filter { $0.sinkType == .noveltyTrap }
        XCTAssertFalse(traps.isEmpty)
    }

    func testNoNoveltyTrapWithDeepReading() {
        let records = makeDiverseRecords() // all > 2 min
        let report = allocator.analyze(records: records)!
        let traps = report.sinks.filter { $0.sinkType == .noveltyTrap }
        XCTAssertTrue(traps.isEmpty)
    }

    // MARK: - Sink Detection: Obligation Read

    func testObligationReadDetected() {
        // 5+ articles on a topic, high total time but <1.5 min avg
        var records = makeRecords(count: 8, topic: "Newsletters", source: "Mail", minutes: 1.2)
        records.append(makeRecord(topic: "Fun", source: "Reddit", minutes: 2))
        records.append(makeRecord(topic: "Tech", source: "HN", minutes: 3))
        allocator.minRecordsForAnalysis = 5
        let report = allocator.analyze(records: records)!
        let obligations = report.sinks.filter { $0.sinkType == .obligationRead }
        XCTAssertFalse(obligations.isEmpty)
    }

    // MARK: - Reallocation

    func testReallocationFromOverToUnder() {
        let records = [
            makeRecord(topic: "Over", minutes: 30),
            makeRecord(topic: "Over", minutes: 25),
            makeRecord(topic: "Under", minutes: 1),
            makeRecord(topic: "Under2", minutes: 1),
            makeRecord(topic: "Normal", minutes: 5),
        ]
        let report = allocator.analyze(records: records)!
        // Over topic is way over any equal-split budget
        XCTAssertFalse(report.reallocations.isEmpty)
    }

    func testReallocationHasPositiveShift() {
        let records = [
            makeRecord(topic: "Heavy", minutes: 40),
            makeRecord(topic: "Heavy", minutes: 30),
            makeRecord(topic: "Light", minutes: 1),
            makeRecord(topic: "Light2", minutes: 1),
            makeRecord(topic: "Med", minutes: 5),
        ]
        let report = allocator.analyze(records: records)!
        for realloc in report.reallocations {
            XCTAssertGreaterThan(realloc.minutesToShift, 0)
        }
    }

    func testNoReallocationWhenBalanced() {
        let records = makeDiverseRecords() // roughly equal
        allocator.defaultDailyBudgetMinutes = 200 // generous budget
        let report = allocator.analyze(records: records)!
        // With large enough budget, nothing should be over
        XCTAssertTrue(report.reallocations.isEmpty)
    }

    // MARK: - Top Consumers

    func testTopConsumersLimitedToFive() {
        var records: [AttentionRecord] = []
        for i in 0..<8 {
            records.append(makeRecord(topic: "Topic\(i)", minutes: Double(10 - i)))
        }
        allocator.minRecordsForAnalysis = 5
        let report = allocator.analyze(records: records)!
        XCTAssertEqual(report.topConsumers.count, 5)
    }

    func testTopConsumersOrderedDescending() {
        let records = makeDiverseRecords()
        let report = allocator.analyze(records: records)!
        for i in 0..<(report.topConsumers.count - 1) {
            XCTAssertGreaterThanOrEqual(report.topConsumers[i].minutes,
                                         report.topConsumers[i + 1].minutes)
        }
    }

    // MARK: - Neglected Topics

    func testNeglectedTopicsDetected() {
        let records = makeDiverseRecords()
        let customBudgets = [
            AttentionBudget(category: "Tech", budgetMinutes: 10, actualMinutes: 0),
            AttentionBudget(category: "Science", budgetMinutes: 10, actualMinutes: 0),
            AttentionBudget(category: "Music", budgetMinutes: 10, actualMinutes: 0),
        ]
        let report = allocator.analyze(records: records, customBudgets: customBudgets)!
        XCTAssertTrue(report.neglectedTopics.contains("Music"))
    }

    func testNoNeglectedTopicsWhenAllUsed() {
        let records = makeDiverseRecords()
        let report = allocator.analyze(records: records)!
        XCTAssertTrue(report.neglectedTopics.isEmpty)
    }

    // MARK: - Verdict Generation

    func testExcellentVerdict() {
        allocator.defaultDailyBudgetMinutes = 200
        let records = makeDiverseRecords()
        let report = allocator.analyze(records: records)!
        // Diverse, no sinks expected, generous budget
        XCTAssertTrue(report.overallVerdict.contains("✅") ||
                      report.overallVerdict.contains("Excellent") ||
                      report.overallVerdict.contains("Decent") ||
                      report.overallVerdict.contains("🟡"))
    }

    func testCriticalVerdictWithMassiveSink() {
        var records = makeRecords(count: 8, topic: "Doom", source: "Doom", minutes: 20)
        records.append(makeRecord(topic: "Other", minutes: 1))
        records.append(makeRecord(topic: "Other2", minutes: 1))
        let report = allocator.analyze(records: records)!
        XCTAssertTrue(report.overallVerdict.contains("🚨") ||
                      report.overallVerdict.contains("🔴") ||
                      report.overallVerdict.contains("Critical") ||
                      report.overallVerdict.contains("Significant"))
    }

    // MARK: - Recommendations

    func testRecommendationsNotEmpty() {
        var records = makeRecords(count: 6, topic: "Mono", minutes: 10)
        records.append(makeRecord(topic: "Tiny", minutes: 1))
        let report = allocator.analyze(records: records)!
        XCTAssertFalse(report.recommendations.isEmpty)
    }

    // MARK: - Edge Cases

    func testNegativeMinutesClamped() {
        let record = AttentionRecord(articleId: "x", topic: "T", source: "S",
                                      minutesSpent: -5, timestamp: Date())
        XCTAssertEqual(record.minutesSpent, 0)
    }

    func testSingleTopicReport() {
        let records = makeRecords(count: 5, topic: "Only")
        let report = allocator.analyze(records: records)!
        XCTAssertEqual(report.diversityScore, 0, accuracy: 0.1)
    }

    func testManyTopicsHighDiversity() {
        var records: [AttentionRecord] = []
        for i in 0..<20 {
            records.append(makeRecord(topic: "Topic\(i)", source: "Source\(i)", minutes: 5))
        }
        allocator.minRecordsForAnalysis = 5
        let report = allocator.analyze(records: records)!
        XCTAssertGreaterThan(report.diversityScore, 95)
    }

    // MARK: - AttentionSinkType Properties

    func testSinkTypeEmojis() {
        XCTAssertEqual(AttentionSinkType.rabbitHole.emoji, "🕳️")
        XCTAssertEqual(AttentionSinkType.doomScroll.emoji, "📱")
        XCTAssertEqual(AttentionSinkType.echoChamber.emoji, "🔁")
        XCTAssertEqual(AttentionSinkType.noveltyTrap.emoji, "🦋")
        XCTAssertEqual(AttentionSinkType.obligationRead.emoji, "😩")
    }

    func testSinkTypeDescriptions() {
        for sinkType in AttentionSinkType.allCases {
            XCTAssertFalse(sinkType.description.isEmpty)
        }
    }

    // MARK: - AttentionSeverity Properties

    func testSeverityComparison() {
        XCTAssertTrue(AttentionSeverity.mild < AttentionSeverity.moderate)
        XCTAssertTrue(AttentionSeverity.moderate < AttentionSeverity.severe)
        XCTAssertTrue(AttentionSeverity.severe < AttentionSeverity.critical)
    }

    func testSeverityEmojis() {
        XCTAssertEqual(AttentionSeverity.mild.emoji, "🟡")
        XCTAssertEqual(AttentionSeverity.moderate.emoji, "🟠")
        XCTAssertEqual(AttentionSeverity.severe.emoji, "🔴")
        XCTAssertEqual(AttentionSeverity.critical.emoji, "🚨")
    }

    // MARK: - Reallocation Properties

    func testReallocationExpectedGainClamped() {
        let realloc = AttentionReallocation(
            fromCategory: "A", toCategory: "B",
            minutesToShift: 10, reason: "test",
            expectedDiversityGain: 150
        )
        XCTAssertEqual(realloc.expectedDiversityGain, 100)
    }

    func testReallocationNegativeMinutesClamped() {
        let realloc = AttentionReallocation(
            fromCategory: "A", toCategory: "B",
            minutesToShift: -5, reason: "test",
            expectedDiversityGain: 10
        )
        XCTAssertEqual(realloc.minutesToShift, 0)
    }
}
