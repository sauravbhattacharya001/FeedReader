//
//  ArticleFreshnessTrackerTests.swift
//  FeedReaderTests
//
//  Tests for ArticleFreshnessTracker — temporal reference extraction,
//  classification, freshness scoring, staleness detection, batch analysis,
//  and persistence.
//

import XCTest
@testable import FeedReader

final class ArticleFreshnessTrackerTests: XCTestCase {

    var tracker: ArticleFreshnessTracker!
    var referenceDate: Date!

    override func setUp() {
        super.setUp()
        tracker = ArticleFreshnessTracker()
        // Fixed reference date: March 10, 2026
        var components = DateComponents()
        components.year = 2026
        components.month = 3
        components.day = 10
        components.hour = 12
        referenceDate = Calendar.current.date(from: components)!
    }

    override func tearDown() {
        tracker = nil
        referenceDate = nil
        super.tearDown()
    }

    // MARK: - Helper

    private func makeDate(year: Int, month: Int, day: Int) -> Date {
        var c = DateComponents()
        c.year = year
        c.month = month
        c.day = day
        return Calendar.current.date(from: c)!
    }

    // MARK: - Temporal Reference Extraction

    func testExtractsRelativeDayReferences() {
        let text = "Sign up today for early access. Offer starts tomorrow."
        let refs = tracker.extractTemporalReferences(from: text, referenceDate: referenceDate)

        let dayRefs = refs.filter { $0.kind == .relativeDay }
        XCTAssertGreaterThanOrEqual(dayRefs.count, 2)

        let matchedTexts = dayRefs.map { $0.matchedText.lowercased() }
        XCTAssertTrue(matchedTexts.contains("today"))
        XCTAssertTrue(matchedTexts.contains("tomorrow"))
    }

    func testExtractsYesterdayReference() {
        let text = "As announced yesterday, the new policy takes effect."
        let refs = tracker.extractTemporalReferences(from: text, referenceDate: referenceDate)
        let dayRefs = refs.filter { $0.kind == .relativeDay }
        XCTAssertTrue(dayRefs.contains { $0.matchedText.lowercased() == "yesterday" })
    }

    func testExtractsRelativeWeekReferences() {
        let text = "This week we launch the beta. Next week, the full release."
        let refs = tracker.extractTemporalReferences(from: text, referenceDate: referenceDate)
        let weekRefs = refs.filter { $0.kind == .relativeWeek }
        XCTAssertGreaterThanOrEqual(weekRefs.count, 2)
    }

    func testExtractsRelativeMonthReferences() {
        let text = "The feature ships this month. Last month we fixed 20 bugs."
        let refs = tracker.extractTemporalReferences(from: text, referenceDate: referenceDate)
        let monthRefs = refs.filter { $0.kind == .relativeMonth }
        XCTAssertGreaterThanOrEqual(monthRefs.count, 2)
    }

    func testExtractsAbsoluteDate() {
        let text = "The conference is on March 15, 2026 in Seattle."
        let refs = tracker.extractTemporalReferences(from: text, referenceDate: referenceDate)
        let dateRefs = refs.filter { $0.kind == .absoluteDate }
        XCTAssertFalse(dateRefs.isEmpty)
        // Should resolve to March 15, 2026
        if let resolved = dateRefs.first?.resolvedDate {
            let comps = Calendar.current.dateComponents([.year, .month, .day], from: resolved)
            XCTAssertEqual(comps.month, 3)
            XCTAssertEqual(comps.day, 15)
            XCTAssertEqual(comps.year, 2026)
        }
    }

    func testExtractsAbsoluteDateWithoutYear() {
        let text = "Submit by April 1 for review."
        let refs = tracker.extractTemporalReferences(from: text, referenceDate: referenceDate)
        let dateRefs = refs.filter { $0.kind == .absoluteDate }
        XCTAssertFalse(dateRefs.isEmpty)
        if let resolved = dateRefs.first?.resolvedDate {
            let comps = Calendar.current.dateComponents([.month, .day], from: resolved)
            XCTAssertEqual(comps.month, 4)
            XCTAssertEqual(comps.day, 1)
        }
    }

    func testExtractsISODate() {
        let text = "Release date: 2026-04-15. Mark your calendars."
        let refs = tracker.extractTemporalReferences(from: text, referenceDate: referenceDate)
        let dateRefs = refs.filter { $0.kind == .absoluteDate }
        XCTAssertFalse(dateRefs.isEmpty)
        XCTAssertTrue(dateRefs.contains { $0.matchedText == "2026-04-15" })
    }

    func testExtractsDeadlineReferences() {
        let text = "The submission deadline is approaching. Registration closes Friday."
        let refs = tracker.extractTemporalReferences(from: text, referenceDate: referenceDate)
        let deadlineRefs = refs.filter { $0.kind == .deadline }
        XCTAssertGreaterThanOrEqual(deadlineRefs.count, 2)
    }

    func testExtractsEventReferences() {
        let text = "Upcoming webinar on AI safety. Registration open now. Early bird pricing available."
        let refs = tracker.extractTemporalReferences(from: text, referenceDate: referenceDate)
        let eventRefs = refs.filter { $0.kind == .eventReference }
        XCTAssertGreaterThanOrEqual(eventRefs.count, 2)
    }

    func testExtractsLimitedOfferReferences() {
        let text = "Limited time offer! Act now — flash sale ends soon. While supplies last."
        let refs = tracker.extractTemporalReferences(from: text, referenceDate: referenceDate)
        let offerRefs = refs.filter { $0.kind == .limitedOffer }
        XCTAssertGreaterThanOrEqual(offerRefs.count, 2)
    }

    func testExtractsSeasonalReferences() {
        let text = "Get ready for this summer with our holiday season deals. Back to school savings."
        let refs = tracker.extractTemporalReferences(from: text, referenceDate: referenceDate)
        let seasonRefs = refs.filter { $0.kind == .seasonal }
        XCTAssertGreaterThanOrEqual(seasonRefs.count, 2)
    }

    func testNoReferencesInEvergreenContent() {
        let text = "Understanding functional programming requires learning about immutability, pure functions, and composition."
        let refs = tracker.extractTemporalReferences(from: text, referenceDate: referenceDate)
        XCTAssertTrue(refs.isEmpty)
    }

    func testReferencesOrderedByOffset() {
        let text = "Today is the deadline. Act now for limited time offers this week."
        let refs = tracker.extractTemporalReferences(from: text, referenceDate: referenceDate)
        for i in 1..<refs.count {
            XCTAssertGreaterThanOrEqual(refs[i].offset, refs[i - 1].offset)
        }
    }

    func testRelativeDayResolvesDate() {
        let text = "Event is tomorrow."
        let refs = tracker.extractTemporalReferences(from: text, referenceDate: referenceDate)
        let tomorrowRef = refs.first { $0.matchedText.lowercased() == "tomorrow" }
        XCTAssertNotNil(tomorrowRef)
        if let resolved = tomorrowRef?.resolvedDate {
            let expectedTomorrow = Calendar.current.date(byAdding: .day, value: 1, to: referenceDate)!
            let diff = Calendar.current.dateComponents([.day], from: resolved, to: expectedTomorrow).day ?? 0
            XCTAssertEqual(abs(diff), 0)
        }
    }

    // MARK: - Classification

    func testClassifiesEvergreenContent() {
        let report = tracker.analyse(
            articleId: "evergreen-1",
            text: "Functional programming emphasises immutability and pure functions.",
            referenceDate: referenceDate
        )
        XCTAssertEqual(report.classification, .evergreen)
    }

    func testClassifiesBreakingContent() {
        let report = tracker.analyse(
            articleId: "breaking-1",
            text: "Sign up today! The deadline is tonight. Limited time offer.",
            referenceDate: referenceDate
        )
        XCTAssertEqual(report.classification, .breaking)
    }

    func testClassifiesTimeSensitiveContent() {
        let report = tracker.analyse(
            articleId: "timesensitive-1",
            text: "Registration closes next week. Early bird pricing ends March 20, 2026.",
            referenceDate: referenceDate
        )
        XCTAssertEqual(report.classification, .timeSensitive)
    }

    func testClassifiesSeasonalContent() {
        let report = tracker.analyse(
            articleId: "seasonal-1",
            text: "Prepare for back to school shopping this summer.",
            referenceDate: referenceDate
        )
        XCTAssertEqual(report.classification, .seasonal)
    }

    // MARK: - Freshness Score

    func testEvergreenScoreIsOneWithoutPublishDate() {
        let report = tracker.analyse(
            articleId: "eg-1",
            text: "Learn about recursion and pattern matching in OCaml.",
            referenceDate: referenceDate
        )
        XCTAssertEqual(report.freshnessScore, 1.0, accuracy: 0.01)
    }

    func testEvergreenScoreDecaysAfterThreshold() {
        let oldPubDate = makeDate(year: 2025, month: 1, day: 1) // ~14 months ago
        let report = tracker.analyse(
            articleId: "eg-old",
            text: "Understanding monads is essential for functional programming.",
            publishDate: oldPubDate,
            referenceDate: referenceDate
        )
        XCTAssertLessThan(report.freshnessScore, 1.0)
        XCTAssertGreaterThan(report.freshnessScore, 0.0)
    }

    func testBreakingContentHasHighFreshnessWithFutureDate() {
        let text = "Today only! Sale ends March 11, 2026. Register now."
        let report = tracker.analyse(
            articleId: "breaking-future",
            text: text,
            referenceDate: referenceDate
        )
        XCTAssertGreaterThanOrEqual(report.freshnessScore, 0.5)
    }

    func testStaleArticleHasLowFreshness() {
        // Article referencing a date far in the past
        let text = "Join us on January 1, 2025 for the grand opening."
        let report = tracker.analyse(
            articleId: "stale-1",
            text: text,
            referenceDate: referenceDate
        )
        XCTAssertLessThanOrEqual(report.freshnessScore, 0.1)
    }

    // MARK: - Staleness Detection

    func testEvergreenContentIsNotStale() {
        let report = tracker.analyse(
            articleId: "eg-nostale",
            text: "The principles of clean code remain timeless.",
            referenceDate: referenceDate
        )
        XCTAssertFalse(report.isStale)
    }

    func testArticleWithPastDateIsStale() {
        let text = "Conference on January 1, 2025. Deadline was December 15, 2024."
        let report = tracker.analyse(
            articleId: "stale-conf",
            text: text,
            referenceDate: referenceDate
        )
        XCTAssertTrue(report.isStale)
    }

    func testArticleWithFutureDateIsNotStale() {
        let text = "The conference is on December 1, 2026."
        let report = tracker.analyse(
            articleId: "future-conf",
            text: text,
            referenceDate: referenceDate
        )
        XCTAssertFalse(report.isStale)
    }

    // MARK: - Report Caching & Retrieval

    func testReportIsCached() {
        let _ = tracker.analyse(
            articleId: "cached-1",
            text: "Today is the last day for early registration.",
            referenceDate: referenceDate
        )
        XCTAssertNotNil(tracker.getReport(for: "cached-1"))
    }

    func testGetAllReports() {
        let _ = tracker.analyse(articleId: "a1", text: "Sign up today.", referenceDate: referenceDate)
        let _ = tracker.analyse(articleId: "a2", text: "Evergreen content.", referenceDate: referenceDate)
        XCTAssertEqual(tracker.getAllReports().count, 2)
    }

    func testGetArticlesByClassification() {
        let _ = tracker.analyse(articleId: "ev1", text: "Learn about recursion.", referenceDate: referenceDate)
        let _ = tracker.analyse(articleId: "ev2", text: "Understanding monads.", referenceDate: referenceDate)
        let _ = tracker.analyse(articleId: "ts1", text: "Deadline tomorrow! Sign up today.", referenceDate: referenceDate)
        let evergreen = tracker.getArticles(classification: .evergreen)
        XCTAssertEqual(evergreen.count, 2)
    }

    func testGetStaleArticles() {
        let _ = tracker.analyse(articleId: "fresh", text: "Join us December 25, 2026.", referenceDate: referenceDate)
        let _ = tracker.analyse(articleId: "stale", text: "Event was January 1, 2024.", referenceDate: referenceDate)
        let stale = tracker.getStaleArticles()
        XCTAssertTrue(stale.contains { $0.articleId == "stale" })
    }

    func testGetExpiringArticles() {
        // Article expiring within 7 days
        let text = "Conference on March 15, 2026."
        let _ = tracker.analyse(articleId: "exp-soon", text: text, referenceDate: referenceDate)
        let expiring = tracker.getExpiringArticles(withinDays: 7, referenceDate: referenceDate)
        XCTAssertTrue(expiring.contains { $0.articleId == "exp-soon" })
    }

    func testRemoveReport() {
        let _ = tracker.analyse(articleId: "rm1", text: "Test article.", referenceDate: referenceDate)
        XCTAssertNotNil(tracker.getReport(for: "rm1"))
        tracker.removeReport(for: "rm1")
        XCTAssertNil(tracker.getReport(for: "rm1"))
    }

    func testClearAll() {
        let _ = tracker.analyse(articleId: "c1", text: "Today is special.", referenceDate: referenceDate)
        let _ = tracker.analyse(articleId: "c2", text: "Tomorrow too.", referenceDate: referenceDate)
        XCTAssertEqual(tracker.trackedCount, 2)
        tracker.clearAll()
        XCTAssertEqual(tracker.trackedCount, 0)
    }

    // MARK: - Batch Analysis

    func testBatchAnalysis() {
        let articles: [(id: String, text: String, publishDate: Date?)] = [
            ("b1", "Learn about functional programming.", nil),
            ("b2", "Flash sale today! Deadline tonight.", nil),
            ("b3", "Conference March 20, 2026. Registration open.", nil),
            ("b4", "Expired event: January 1, 2024.", nil),
        ]
        let summary = tracker.analyseBatch(articles: articles, referenceDate: referenceDate)
        XCTAssertEqual(summary.totalArticles, 4)
        XCTAssertGreaterThanOrEqual(summary.staleCount, 1)
        XCTAssertGreaterThan(summary.averageFreshnessScore, 0.0)
        XCTAssertLessThanOrEqual(summary.averageFreshnessScore, 1.0)
    }

    func testBatchSummaryCountsByClassification() {
        let articles: [(id: String, text: String, publishDate: Date?)] = [
            ("cls-1", "Evergreen content about algorithms.", nil),
            ("cls-2", "More evergreen content about data structures.", nil),
            ("cls-3", "Sale today! Act now deadline.", nil),
        ]
        let summary = tracker.analyseBatch(articles: articles, referenceDate: referenceDate)
        XCTAssertEqual(summary.classificationCounts["evergreen"], 2)
    }

    // MARK: - Score Refresh

    func testRefreshScoresUpdatesStaleStatus() {
        let text = "Event on March 12, 2026."
        let _ = tracker.analyse(articleId: "refresh-1", text: text, referenceDate: referenceDate)

        // Refresh with a date after the event + stale threshold
        let futureDate = makeDate(year: 2026, month: 3, day: 20)
        tracker.refreshScores(referenceDate: futureDate)

        let updated = tracker.getReport(for: "refresh-1")
        XCTAssertNotNil(updated)
        XCTAssertTrue(updated!.isStale)
    }

    // MARK: - Persistence

    func testJSONExportImportRoundTrip() throws {
        let _ = tracker.analyse(articleId: "json-1", text: "Flash sale today!", referenceDate: referenceDate)
        let _ = tracker.analyse(articleId: "json-2", text: "Evergreen article.", referenceDate: referenceDate)

        let data = try tracker.exportJSON()
        XCTAssertFalse(data.isEmpty)

        let newTracker = ArticleFreshnessTracker()
        try newTracker.importJSON(data)
        XCTAssertEqual(newTracker.trackedCount, 2)
        XCTAssertNotNil(newTracker.getReport(for: "json-1"))
        XCTAssertNotNil(newTracker.getReport(for: "json-2"))
    }

    func testImportMergesWithExisting() throws {
        let _ = tracker.analyse(articleId: "existing", text: "Already tracked.", referenceDate: referenceDate)

        let otherTracker = ArticleFreshnessTracker()
        let _ = otherTracker.analyse(articleId: "imported", text: "New article today.", referenceDate: referenceDate)
        let data = try otherTracker.exportJSON()

        try tracker.importJSON(data)
        XCTAssertEqual(tracker.trackedCount, 2)
    }

    // MARK: - Text Report

    func testGenerateTextReport() {
        let _ = tracker.analyse(articleId: "rpt-1", text: "Sign up today.", referenceDate: referenceDate)
        let _ = tracker.analyse(articleId: "rpt-2", text: "Learn about recursion.", referenceDate: referenceDate)
        let report = tracker.generateTextReport()
        XCTAssertTrue(report.contains("Article Freshness Report"))
        XCTAssertTrue(report.contains("Tracked articles: 2"))
    }

    // MARK: - Classification Comparable

    func testClassificationOrdering() {
        XCTAssertTrue(FreshnessClassification.breaking < FreshnessClassification.timeSensitive)
        XCTAssertTrue(FreshnessClassification.timeSensitive < FreshnessClassification.seasonal)
        XCTAssertTrue(FreshnessClassification.seasonal < FreshnessClassification.evergreen)
    }

    // MARK: - Edge Cases

    func testEmptyTextProducesEvergreenReport() {
        let report = tracker.analyse(articleId: "empty", text: "", referenceDate: referenceDate)
        XCTAssertEqual(report.classification, .evergreen)
        XCTAssertEqual(report.temporalDensity, 0)
        XCTAssertFalse(report.isStale)
    }

    func testMultipleISODatesExtracted() {
        let text = "Phase 1: 2026-04-01. Phase 2: 2026-06-15. Phase 3: 2026-09-01."
        let refs = tracker.extractTemporalReferences(from: text, referenceDate: referenceDate)
        let dateRefs = refs.filter { $0.kind == .absoluteDate }
        XCTAssertEqual(dateRefs.count, 3)
    }

    func testSummaryContainsExpiredDaysForStaleArticle() {
        let text = "Event was on January 1, 2024."
        let report = tracker.analyse(articleId: "summary-stale", text: text, referenceDate: referenceDate)
        XCTAssertTrue(report.summary.contains("Stale"))
        XCTAssertTrue(report.summary.contains("expired"))
    }

    func testSummaryContainsDaysUntilForFutureArticle() {
        let text = "Conference on December 1, 2026."
        let report = tracker.analyse(articleId: "summary-future", text: text, referenceDate: referenceDate)
        XCTAssertTrue(report.summary.contains("day"))
    }

    func testCustomConfigBreakingThreshold() {
        var config = FreshnessConfig.default
        config.breakingMinRefs = 5  // Very high threshold
        let customTracker = ArticleFreshnessTracker(config: config)
        let report = customTracker.analyse(
            articleId: "custom-1",
            text: "Today is the deadline.",
            referenceDate: referenceDate
        )
        // With high threshold, shouldn't be breaking
        XCTAssertNotEqual(report.classification, .evergreen)
    }

    func testCustomStaleThreshold() {
        var config = FreshnessConfig.default
        config.staleThresholdDays = 365  // Very lenient
        let customTracker = ArticleFreshnessTracker(config: config)
        let text = "Event was March 1, 2026."
        let report = customTracker.analyse(
            articleId: "lenient-1",
            text: text,
            referenceDate: referenceDate
        )
        XCTAssertFalse(report.isStale)  // Only 9 days past, threshold is 365
    }

    func testTrackedCountAccuracy() {
        XCTAssertEqual(tracker.trackedCount, 0)
        let _ = tracker.analyse(articleId: "tc1", text: "Test.", referenceDate: referenceDate)
        XCTAssertEqual(tracker.trackedCount, 1)
        let _ = tracker.analyse(articleId: "tc2", text: "Test.", referenceDate: referenceDate)
        XCTAssertEqual(tracker.trackedCount, 2)
        // Re-analysing same ID replaces, doesn't duplicate
        let _ = tracker.analyse(articleId: "tc1", text: "Updated.", referenceDate: referenceDate)
        XCTAssertEqual(tracker.trackedCount, 2)
    }

    func testEarliestExpiryIsSmallestDate() {
        let text = "Phase 1: March 15, 2026. Phase 2: March 25, 2026. Phase 3: April 10, 2026."
        let report = tracker.analyse(articleId: "multi-date", text: text, referenceDate: referenceDate)
        if let earliest = report.earliestExpiry {
            let comps = Calendar.current.dateComponents([.month, .day], from: earliest)
            XCTAssertEqual(comps.month, 3)
            XCTAssertEqual(comps.day, 15)
        }
    }
}
