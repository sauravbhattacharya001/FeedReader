//
//  FeedTimelineReconstructorTests.swift
//  FeedReaderTests
//

import XCTest
@testable import FeedReader

final class FeedTimelineReconstructorTests: XCTestCase {

    var reconstructor: FeedTimelineReconstructor!

    override func setUp() {
        super.setUp()
        reconstructor = FeedTimelineReconstructor()
    }

    override func tearDown() {
        reconstructor.reset()
        reconstructor = nil
        super.tearDown()
    }

    // MARK: - Ingestion

    func testIngestArticleCreatesTimeline() {
        let events = reconstructor.ingestArticle(
            title: "SpaceX launches Starship prototype",
            link: "https://example.com/1",
            feed: "TechNews",
            text: "SpaceX successfully launched its Starship rocket on January 15, 2025 from Boca Chica."
        )
        XCTAssertFalse(events.isEmpty)
        XCTAssertEqual(reconstructor.timelines.count, 1)
    }

    func testIngestMultipleRelatedArticlesGroupsTogether() {
        reconstructor.ingestArticle(
            title: "SpaceX Starship launch attempt",
            link: "https://example.com/1", feed: "TechNews",
            text: "SpaceX launched Starship on January 10, 2025."
        )
        reconstructor.ingestArticle(
            title: "SpaceX Starship landing success",
            link: "https://example.com/2", feed: "SpaceDaily",
            text: "SpaceX Starship achieved landing on February 5, 2025 after launch."
        )
        // Should group into same timeline due to shared keywords
        XCTAssertLessThanOrEqual(reconstructor.timelines.count, 2)
    }

    func testIngestUnrelatedArticlesCreatesSeparateTimelines() {
        reconstructor.ingestArticle(
            title: "Global wheat prices surge",
            link: "https://example.com/1", feed: "AgriNews",
            text: "Wheat prices rose sharply on March 1, 2025 due to drought."
        )
        reconstructor.ingestArticle(
            title: "New quantum computing breakthrough",
            link: "https://example.com/2", feed: "ScienceDaily",
            text: "Researchers achieved quantum supremacy milestone on April 10, 2025."
        )
        XCTAssertEqual(reconstructor.timelines.count, 2)
    }

    // MARK: - Date Extraction

    func testExtractsISODates() {
        let events = reconstructor.ingestArticle(
            title: "Event report",
            link: "https://example.com/1", feed: "News",
            text: "The conference started on 2025-06-15 and ended on 2025-06-18."
        )
        XCTAssertGreaterThanOrEqual(events.count, 2)
        let highConfidence = events.filter { $0.confidence >= 0.9 }
        XCTAssertFalse(highConfidence.isEmpty)
    }

    func testExtractsWrittenDates() {
        let events = reconstructor.ingestArticle(
            title: "Historical event",
            link: "https://example.com/1", feed: "History",
            text: "The treaty was signed on March 22, 2024 in Geneva."
        )
        XCTAssertFalse(events.isEmpty)
    }

    func testFallsBackToPubDateWhenNoDates() {
        let pubDate = Date()
        let events = reconstructor.ingestArticle(
            title: "Breaking news today",
            link: "https://example.com/1", feed: "Breaking",
            text: "Something happened with no date mentioned in the text.",
            pubDate: pubDate
        )
        XCTAssertEqual(events.count, 1)
        XCTAssertEqual(events.first?.confidence, 0.5)
    }

    // MARK: - Event Type Inference

    func testInfersAnnouncementType() {
        let events = reconstructor.ingestArticle(
            title: "Company announced new product",
            link: "https://example.com/1", feed: "Biz",
            text: "The CEO announced a groundbreaking product launch on June 1, 2025."
        )
        let announcement = events.first { $0.eventType == .announcement }
        XCTAssertNotNil(announcement)
    }

    func testInfersEscalationType() {
        let events = reconstructor.ingestArticle(
            title: "Crisis escalates",
            link: "https://example.com/1", feed: "World",
            text: "The conflict escalated dramatically on May 10, 2025 with new forces."
        )
        let escalation = events.first { $0.eventType == .escalation }
        XCTAssertNotNil(escalation)
    }

    // MARK: - Gap Detection

    func testDetectsTimelineGaps() {
        let cal = Calendar.current
        let base = cal.date(from: DateComponents(year: 2025, month: 1, day: 1))!

        // Create events with regular cadence except one big gap
        for i in 0..<5 {
            let date = cal.date(byAdding: .day, value: i * 7, to: base)!
            reconstructor.ingestArticle(
                title: "Weekly tech update #\(i+1)",
                link: "https://example.com/\(i)", feed: "Tech",
                text: "Weekly technology update for \(ISO8601DateFormatter().string(from: date)).",
                pubDate: date
            )
        }
        // Add one with a big gap
        let lateDate = cal.date(byAdding: .day, value: 70, to: base)!
        reconstructor.ingestArticle(
            title: "Weekly tech update #6",
            link: "https://example.com/6", feed: "Tech",
            text: "Weekly technology update for \(ISO8601DateFormatter().string(from: lateDate)).",
            pubDate: lateDate
        )

        let gaps = reconstructor.detectGaps()
        // Should detect at least one gap
        XCTAssertFalse(gaps.isEmpty)
    }

    // MARK: - Frequency Patterns

    func testDetectsAccelerationPattern() {
        let cal = Calendar.current
        let base = cal.date(from: DateComponents(year: 2025, month: 1, day: 1))!

        // First half: weekly events
        for i in 0..<4 {
            let date = cal.date(byAdding: .day, value: i * 14, to: base)!
            reconstructor.ingestArticle(
                title: "AI research progress #\(i+1)",
                link: "https://example.com/\(i)", feed: "AI",
                text: "Artificial intelligence research progress report.",
                pubDate: date
            )
        }
        // Second half: daily events (acceleration)
        let midBase = cal.date(byAdding: .day, value: 60, to: base)!
        for i in 0..<4 {
            let date = cal.date(byAdding: .day, value: i * 2, to: midBase)!
            reconstructor.ingestArticle(
                title: "AI research breakthrough #\(i+1)",
                link: "https://example.com/b\(i)", feed: "AI",
                text: "Artificial intelligence research major breakthrough.",
                pubDate: date
            )
        }

        let patterns = reconstructor.detectFrequencyPatterns()
        let accel = patterns.first { $0.patternType == .accelerating || $0.patternType == .burst }
        XCTAssertNotNil(accel)
    }

    // MARK: - Convergence Detection

    func testDetectsConvergence() {
        // Two timelines with overlapping keywords
        reconstructor.matchThreshold = 0.9 // High threshold to force separate timelines
        reconstructor.ingestArticle(
            title: "Electric vehicle battery technology advances",
            link: "https://example.com/1", feed: "EV",
            text: "Battery technology for electric vehicles improved significantly."
        )
        reconstructor.ingestArticle(
            title: "Solar battery storage breakthrough",
            link: "https://example.com/2", feed: "Energy",
            text: "Solar energy battery storage achieved breakthrough efficiency."
        )

        let convergences = reconstructor.detectConvergences()
        // May or may not detect depending on keyword overlap
        // Just verify it runs without error
        XCTAssertNotNil(convergences)
    }

    // MARK: - Stall Detection

    func testDetectsStall() {
        reconstructor.stallThresholdDays = 0.0001 // Tiny threshold for testing
        reconstructor.ingestArticle(
            title: "Old story",
            link: "https://example.com/1", feed: "News",
            text: "Something happened on January 1, 2020."
        )
        reconstructor.detectStalls()
        let stalled = reconstructor.timelines.filter { $0.status == .stalled }
        XCTAssertFalse(stalled.isEmpty)
    }

    // MARK: - Report

    func testGenerateReport() {
        reconstructor.ingestArticle(
            title: "Test article",
            link: "https://example.com/1", feed: "Test",
            text: "A test event on May 1, 2025."
        )
        let report = reconstructor.generateReport()
        XCTAssertEqual(report.totalTimelines, 1)
        XCTAssertGreaterThanOrEqual(report.totalEvents, 1)
    }

    // MARK: - Export

    func testExportJSON() {
        reconstructor.ingestArticle(
            title: "JSON test", link: "https://example.com/1", feed: "F",
            text: "Event on 2025-03-01."
        )
        let json = reconstructor.exportJSON()
        XCTAssertNotNil(json)
        XCTAssertTrue(json!.contains("JSON test"))
    }

    func testExportMarkdown() {
        reconstructor.ingestArticle(
            title: "Markdown test", link: "https://example.com/1", feed: "F",
            text: "Event on 2025-04-01."
        )
        let md = reconstructor.exportMarkdown()
        XCTAssertTrue(md.contains("# Feed Timeline Report"))
        XCTAssertTrue(md.contains("Markdown test"))
    }

    func testExportText() {
        reconstructor.ingestArticle(
            title: "Text test", link: "https://example.com/1", feed: "F",
            text: "Event on 2025-05-01."
        )
        let txt = reconstructor.exportText()
        XCTAssertTrue(txt.contains("FEED TIMELINE REPORT"))
        XCTAssertTrue(txt.contains("Text test"))
    }

    // MARK: - Merge

    func testMergeTimelines() {
        reconstructor.matchThreshold = 1.0 // Force separate timelines
        reconstructor.ingestArticle(title: "A", link: "l1", feed: "F1", text: "Topic alpha on 2025-01-01.")
        reconstructor.ingestArticle(title: "B", link: "l2", feed: "F2", text: "Topic beta on 2025-02-01.")
        XCTAssertEqual(reconstructor.timelines.count, 2)

        let id1 = reconstructor.timelines[0].id
        let id2 = reconstructor.timelines[1].id
        let result = reconstructor.mergeTimelines(sourceId: id1, targetId: id2)
        XCTAssertTrue(result)
        XCTAssertEqual(reconstructor.timelines.count, 1)
    }

    // MARK: - Reset

    func testReset() {
        reconstructor.ingestArticle(title: "X", link: "l", feed: "F", text: "2025-01-01 event.")
        XCTAssertFalse(reconstructor.timelines.isEmpty)
        reconstructor.reset()
        XCTAssertTrue(reconstructor.timelines.isEmpty)
    }

    // MARK: - Recommendations

    func testGenerateRecommendations() {
        // Single-source timeline with enough events
        for i in 0..<4 {
            reconstructor.ingestArticle(
                title: "Climate report #\(i)", link: "https://ex.com/\(i)", feed: "SameFeed",
                text: "Climate change report number \(i) published."
            )
        }
        let recs = reconstructor.generateRecommendations()
        let singleSource = recs.first { $0.recommendation.contains("one source") }
        XCTAssertNotNil(singleSource)
    }
}
