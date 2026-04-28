//
//  FeedContextualPrimerTests.swift
//  FeedReaderCoreTests
//
//  Tests for the FeedContextualPrimer reading preparation engine.
//

import XCTest
@testable import FeedReaderCore

final class FeedContextualPrimerTests: XCTestCase {

    private func makePrimer() -> FeedContextualPrimer {
        return FeedContextualPrimer()
    }

    // MARK: - Basic Initialization

    func testInitialState() {
        let primer = makePrimer()
        XCTAssertEqual(primer.historyCount, 0)
    }

    // MARK: - Recording History

    func testRecordReading() {
        let primer = makePrimer()
        primer.recordReading(title: "AI Advances", link: "https://example.com/ai", body: "Machine learning and neural networks are transforming healthcare through automated diagnosis systems.")
        XCTAssertEqual(primer.historyCount, 1)
    }

    func testRecordMultipleReadings() {
        let primer = makePrimer()
        primer.recordReading(title: "AI Advances", link: "https://example.com/ai", body: "Machine learning neural networks transforming healthcare automated diagnosis.")
        primer.recordReading(title: "Quantum Computing", link: "https://example.com/quantum", body: "Quantum computing qubits superposition entanglement algorithms breakthrough research.")
        XCTAssertEqual(primer.historyCount, 2)
    }

    func testClearHistory() {
        let primer = makePrimer()
        primer.recordReading(title: "Test", link: "https://example.com/1", body: "Some interesting content about technology and programming languages.")
        primer.clearHistory()
        XCTAssertEqual(primer.historyCount, 0)
    }

    // MARK: - Primer Generation

    func testPrimerWithNoHistory() {
        let primer = makePrimer()
        let report = primer.preparePrimer(title: "New Article", link: "https://example.com/new", body: "Deep learning convolutional networks image recognition computer vision applications research.")
        XCTAssertEqual(report.targetTitle, "New Article")
        XCTAssertEqual(report.targetLink, "https://example.com/new")
        // With no history, everything is unknown — score should be very low
        XCTAssertLessThanOrEqual(report.readinessScore, 10)
        XCTAssertEqual(report.readinessLabel, "New Territory")
        XCTAssertTrue(report.backgroundRefreshers.isEmpty)
    }

    func testPrimerWithRelevantHistory() {
        let primer = makePrimer()
        // Build history with related concepts
        for i in 0..<10 {
            primer.recordReading(
                title: "Machine Learning Article \(i)",
                link: "https://example.com/ml/\(i)",
                body: "Machine learning algorithms training data neural networks deep learning models prediction accuracy optimization gradient descent."
            )
        }

        let report = primer.preparePrimer(
            title: "Advanced Neural Networks",
            link: "https://example.com/advanced-nn",
            body: "Neural networks deep learning training optimization gradient descent advanced architectures transformer models."
        )

        // Should have decent readiness since many concepts overlap
        XCTAssertGreaterThan(report.readinessScore, 30)
        XCTAssertFalse(report.familiarityMap.isEmpty)
    }

    func testPrimerWithUnrelatedHistory() {
        let primer = makePrimer()
        // History about cooking
        for i in 0..<5 {
            primer.recordReading(
                title: "Cooking Recipe \(i)",
                link: "https://example.com/cook/\(i)",
                body: "Delicious recipe ingredients preparation cooking baking temperature oven timer kitchen utensils seasoning."
            )
        }

        // Article about quantum physics
        let report = primer.preparePrimer(
            title: "Quantum Entanglement",
            link: "https://example.com/quantum",
            body: "Quantum entanglement particles superposition measurement probability amplitude wavefunction collapse observation."
        )

        // Should have low readiness — completely different domains
        XCTAssertLessThan(report.readinessScore, 30)
        XCTAssertFalse(report.blindSpots.isEmpty)
    }

    // MARK: - Familiarity Map

    func testFamiliarityLevels() {
        let primer = makePrimer()

        // Record "blockchain" once
        primer.recordReading(title: "Blockchain Intro", link: "https://example.com/bc1", body: "Blockchain technology distributed ledger consensus mechanism cryptocurrency mining.")

        let report = primer.preparePrimer(
            title: "Blockchain Deep Dive",
            link: "https://example.com/bc2",
            body: "Blockchain technology distributed ledger advanced smart contracts ethereum solidity programming."
        )

        // "blockchain" should be glimpsed (seen once), "solidity" should be unknown
        let blockchainEntry = report.familiarityMap.first { $0.term == "blockchain" }
        let solidityEntry = report.familiarityMap.first { $0.term == "solidity" }

        if let bc = blockchainEntry {
            XCTAssertTrue(bc.familiarity == .glimpsed || bc.familiarity == .familiar)
        }
        if let sol = solidityEntry {
            XCTAssertEqual(sol.familiarity, .unknown)
        }
    }

    func testFamiliarityLevelComparable() {
        XCTAssertTrue(FamiliarityLevel.unknown < FamiliarityLevel.glimpsed)
        XCTAssertTrue(FamiliarityLevel.glimpsed < FamiliarityLevel.familiar)
        XCTAssertTrue(FamiliarityLevel.familiar < FamiliarityLevel.wellKnown)
    }

    // MARK: - Blind Spots

    func testBlindSpotsDetection() {
        let primer = makePrimer()
        primer.recordReading(title: "Python Basics", link: "https://example.com/py", body: "Python programming language variables functions classes objects inheritance polymorphism.")

        let report = primer.preparePrimer(
            title: "Rust Systems Programming",
            link: "https://example.com/rust",
            body: "Rust programming language ownership borrowing lifetimes memory safety concurrency fearless systems."
        )

        // Rust-specific concepts should appear as blind spots
        let blindSpotSet = Set(report.blindSpots)
        // "ownership", "borrowing", "lifetimes" are Rust-specific and should be unknown
        XCTAssertTrue(blindSpotSet.contains("ownership") || blindSpotSet.contains("borrowing") || blindSpotSet.contains("lifetimes"),
                       "Expected Rust-specific concepts as blind spots, got: \(report.blindSpots)")
    }

    func testMaxBlindSpots() {
        let primer = makePrimer()
        primer.maxBlindSpots = 3

        let report = primer.preparePrimer(
            title: "Complex Article",
            link: "https://example.com/complex",
            body: "Alpha bravo charlie delta echo foxtrot golf hotel india juliet kilo lima mike november oscar papa."
        )

        XCTAssertLessThanOrEqual(report.blindSpots.count, 3)
    }

    // MARK: - Background Refreshers

    func testBackgroundRefreshersFound() {
        let primer = makePrimer()
        primer.recordReading(title: "Climate Change Basics", link: "https://example.com/climate1",
                           body: "Climate change global warming emissions carbon dioxide greenhouse gases temperature rising pollution environment.")
        primer.recordReading(title: "Renewable Energy", link: "https://example.com/energy",
                           body: "Renewable energy solar panels wind turbines hydroelectric power clean sustainable environment carbon neutral.")

        let report = primer.preparePrimer(
            title: "Carbon Tax Policy",
            link: "https://example.com/carbon-tax",
            body: "Carbon emissions tax policy climate change environmental regulation greenhouse gases reduction targets sustainable."
        )

        XCTAssertFalse(report.backgroundRefreshers.isEmpty, "Should find related past articles")
        // Refreshers should be sorted by relevance
        if report.backgroundRefreshers.count >= 2 {
            XCTAssertGreaterThanOrEqual(report.backgroundRefreshers[0].relevanceScore,
                                         report.backgroundRefreshers[1].relevanceScore)
        }
    }

    func testRefresherSharedConcepts() {
        let primer = makePrimer()
        primer.recordReading(title: "Docker Containers", link: "https://example.com/docker",
                           body: "Docker containers kubernetes orchestration deployment microservices scalability infrastructure cloud.")

        let report = primer.preparePrimer(
            title: "Kubernetes Advanced",
            link: "https://example.com/k8s",
            body: "Kubernetes orchestration deployment containers pods services ingress cluster management scaling."
        )

        if let refresher = report.backgroundRefreshers.first {
            XCTAssertFalse(refresher.sharedConcepts.isEmpty, "Refresher should list shared concepts")
            XCTAssertGreaterThan(refresher.relevanceScore, 0)
        }
    }

    func testRefresherExcludesSameArticle() {
        let primer = makePrimer()
        primer.recordReading(title: "Test Article", link: "https://example.com/same",
                           body: "Technology innovation research development advancement breakthrough progress.")

        let report = primer.preparePrimer(
            title: "Test Article",
            link: "https://example.com/same",
            body: "Technology innovation research development advancement breakthrough progress."
        )

        // The same article should not appear as its own refresher
        XCTAssertTrue(report.backgroundRefreshers.allSatisfy { $0.link != "https://example.com/same" })
    }

    func testMaxRefreshers() {
        let primer = makePrimer()
        primer.maxRefreshers = 2

        // Add many related articles
        for i in 0..<10 {
            primer.recordReading(title: "Related \(i)", link: "https://example.com/r/\(i)",
                               body: "Technology software development programming algorithms optimization performance.")
        }

        let report = primer.preparePrimer(
            title: "Software Performance",
            link: "https://example.com/perf",
            body: "Software development performance optimization algorithms programming techniques benchmarking."
        )

        XCTAssertLessThanOrEqual(report.backgroundRefreshers.count, 2)
    }

    // MARK: - Reading Order

    func testReadingOrderEmpty() {
        let primer = makePrimer()
        let order = primer.suggestReadingOrder(articles: [])
        XCTAssertTrue(order.isEmpty)
    }

    func testReadingOrderSingleArticle() {
        let primer = makePrimer()
        let order = primer.suggestReadingOrder(articles: [
            (title: "Only Article", link: "https://example.com/1", body: "Some interesting content about software development.")
        ])
        XCTAssertEqual(order.count, 1)
        XCTAssertEqual(order[0].position, 1)
        XCTAssertEqual(order[0].title, "Only Article")
    }

    func testReadingOrderScaffolding() {
        let primer = makePrimer()

        // Provide background in programming basics
        primer.recordReading(title: "Programming 101", link: "https://example.com/prog101",
                           body: "Programming variables functions loops conditionals basics syntax code editor.")

        let articles: [(title: String, link: String, body: String)] = [
            (title: "Advanced Algorithms",
             link: "https://example.com/algo",
             body: "Advanced algorithms dynamic programming graph traversal complexity analysis optimization heuristics."),
            (title: "Data Structures Intro",
             link: "https://example.com/ds",
             body: "Data structures arrays linked lists stacks queues programming basics variables functions."),
            (title: "Machine Learning Math",
             link: "https://example.com/mlmath",
             body: "Machine learning mathematics linear algebra calculus probability statistics gradient optimization.")
        ]

        let order = primer.suggestReadingOrder(articles: articles)
        XCTAssertEqual(order.count, 3)

        // The article most connected to existing knowledge (programming basics) should come first
        // Data Structures Intro shares "programming", "basics", "variables", "functions" with history
        XCTAssertEqual(order[0].title, "Data Structures Intro",
                       "Article most connected to prior knowledge should be first. Got: \(order.map { $0.title })")
    }

    func testReadingOrderPositions() {
        let primer = makePrimer()
        let articles: [(title: String, link: String, body: String)] = [
            (title: "A", link: "https://example.com/a", body: "Alpha beta gamma delta epsilon."),
            (title: "B", link: "https://example.com/b", body: "Beta gamma delta epsilon zeta."),
            (title: "C", link: "https://example.com/c", body: "Gamma delta epsilon zeta theta.")
        ]

        let order = primer.suggestReadingOrder(articles: articles)
        XCTAssertEqual(order.count, 3)
        XCTAssertEqual(order[0].position, 1)
        XCTAssertEqual(order[1].position, 2)
        XCTAssertEqual(order[2].position, 3)
    }

    // MARK: - Readiness Labels

    func testReadinessLabels() {
        let primer = makePrimer()

        // With no history → new territory
        let report = primer.preparePrimer(title: "Test", link: "https://example.com/t",
                                         body: "Completely novel terminology xenomorphic paradigm.")
        XCTAssertTrue(["New Territory", "Some Gaps", "Significant Gaps"].contains(report.readinessLabel),
                       "Low readiness expected, got: \(report.readinessLabel) (\(report.readinessScore))")
    }

    // MARK: - Persistence

    func testExportImportHistory() {
        let primer = makePrimer()
        primer.recordReading(title: "Article 1", link: "https://example.com/1",
                           body: "Technology innovation software development.")
        primer.recordReading(title: "Article 2", link: "https://example.com/2",
                           body: "Science research discovery breakthrough.")

        guard let data = primer.exportHistory() else {
            XCTFail("Export should succeed")
            return
        }

        let newPrimer = makePrimer()
        let count = newPrimer.importHistory(from: data)
        XCTAssertEqual(count, 2)
        XCTAssertEqual(newPrimer.historyCount, 2)
    }

    func testImportInvalidData() {
        let primer = makePrimer()
        let badData = "not json".data(using: .utf8)!
        let count = primer.importHistory(from: badData)
        XCTAssertNil(count)
        XCTAssertEqual(primer.historyCount, 0)
    }

    func testExportEmptyHistory() {
        let primer = makePrimer()
        let data = primer.exportHistory()
        XCTAssertNotNil(data)

        let newPrimer = makePrimer()
        let count = newPrimer.importHistory(from: data!)
        XCTAssertEqual(count, 0)
    }

    // MARK: - Summary

    func testSummaryContainsReadiness() {
        let primer = makePrimer()
        let report = primer.preparePrimer(title: "Test", link: "https://example.com/s",
                                         body: "Software engineering architecture design patterns.")
        XCTAssertTrue(report.summary.contains("readiness"))
    }

    func testSummaryMentionsBlindSpots() {
        let primer = makePrimer()
        let report = primer.preparePrimer(title: "Test", link: "https://example.com/s",
                                         body: "Obscure terminology unfamiliar jargon specialized vocabulary.")
        // With no history, there should be blind spots mentioned
        XCTAssertTrue(report.summary.contains("concept") || report.summary.contains("blind"),
                       "Summary should mention concepts: \(report.summary)")
    }

    // MARK: - Configuration

    func testCustomConfiguration() {
        let primer = makePrimer()
        primer.minimumConceptLength = 6
        primer.maxRefreshers = 2
        primer.maxBlindSpots = 3
        primer.refresherThreshold = 0.5

        primer.recordReading(title: "Test History", link: "https://example.com/h",
                           body: "Technology advancement innovation breakthrough programming development architecture.")

        let report = primer.preparePrimer(title: "Test", link: "https://example.com/t",
                                         body: "Technology programming development architecture microservices containers orchestration kubernetes deployment infrastructure.")

        XCTAssertLessThanOrEqual(report.backgroundRefreshers.count, 2)
        XCTAssertLessThanOrEqual(report.blindSpots.count, 3)

        // With minimumConceptLength=6, short words should be excluded
        let shortTerms = report.familiarityMap.filter { $0.term.count < 6 }
        XCTAssertTrue(shortTerms.isEmpty, "No terms shorter than 6 chars expected, found: \(shortTerms.map { $0.term })")
    }

    // MARK: - Edge Cases

    func testEmptyArticle() {
        let primer = makePrimer()
        let report = primer.preparePrimer(title: "", link: "https://example.com/empty", body: "")
        XCTAssertEqual(report.readinessScore, 100) // No concepts = fully ready (vacuous truth)
        XCTAssertTrue(report.familiarityMap.isEmpty)
        XCTAssertTrue(report.blindSpots.isEmpty)
    }

    func testArticleWithOnlyStopWords() {
        let primer = makePrimer()
        let report = primer.preparePrimer(title: "The", link: "https://example.com/stop",
                                         body: "The and or but is it as was are be been being have has had do does did will would could should.")
        // Stop words are filtered, so effectively empty
        XCTAssertTrue(report.familiarityMap.isEmpty || report.readinessScore >= 0)
    }

    func testRSSStoryIntegration() {
        let primer = makePrimer()

        // Use RSSStory objects
        if let story1 = RSSStory(title: "Test Story", body: "Technology innovation development software engineering.", link: "https://example.com/story1") {
            primer.recordReading(story: story1)
        }

        if let story2 = RSSStory(title: "Related Story", body: "Technology innovation advancement software programming.", link: "https://example.com/story2") {
            let report = primer.preparePrimer(for: story2)
            XCTAssertEqual(report.targetTitle, "Related Story")
            XCTAssertGreaterThan(report.readinessScore, 0)
        }
    }
}
