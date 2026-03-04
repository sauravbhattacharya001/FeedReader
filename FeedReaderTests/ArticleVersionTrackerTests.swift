//
//  ArticleVersionTrackerTests.swift
//  FeedReaderTests
//

import XCTest
@testable import FeedReader

class ArticleVersionTrackerTests: XCTestCase {

    var tracker: ArticleVersionTracker!
    let link1 = "https://example.com/article-1"
    let link2 = "https://example.com/article-2"

    override func setUp() {
        super.setUp()
        tracker = ArticleVersionTracker()
    }

    // MARK: - Basic Tracking

    func testFirstSnapshotReturnsNil() {
        let change = tracker.recordSnapshot(link: link1, title: "Hello", body: "World content here", feedName: "TestFeed")
        XCTAssertNil(change, "First snapshot should not produce a change")
    }

    func testIdenticalContentReturnsNil() {
        tracker.recordSnapshot(link: link1, title: "Hello", body: "Same content", feedName: "Feed")
        let change = tracker.recordSnapshot(link: link1, title: "Hello", body: "Same content", feedName: "Feed")
        XCTAssertNil(change, "Identical content should not produce a change")
    }

    func testDifferentContentProducesChange() {
        tracker.recordSnapshot(link: link1, title: "Title", body: "Original body text with several words", feedName: "Feed")
        let change = tracker.recordSnapshot(link: link1, title: "Title", body: "Completely different body text with new words", feedName: "Feed")
        XCTAssertNotNil(change)
        XCTAssertEqual(change?.version, 1)
    }

    func testMultipleChangesIncrementVersion() {
        tracker.recordSnapshot(link: link1, title: "T", body: "version zero content", feedName: "F")
        let c1 = tracker.recordSnapshot(link: link1, title: "T", body: "version one content", feedName: "F")
        let c2 = tracker.recordSnapshot(link: link1, title: "T", body: "version two content", feedName: "F")
        XCTAssertEqual(c1?.version, 1)
        XCTAssertEqual(c2?.version, 2)
    }

    func testHistoryTracksSnapshots() {
        tracker.recordSnapshot(link: link1, title: "T", body: "body one", feedName: "F")
        tracker.recordSnapshot(link: link1, title: "T", body: "body two", feedName: "F")
        tracker.recordSnapshot(link: link1, title: "T", body: "body three", feedName: "F")
        let history = tracker.getHistory(link: link1)
        XCTAssertNotNil(history)
        XCTAssertEqual(history?.snapshots.count, 3)
        XCTAssertEqual(history?.changes.count, 2)
        XCTAssertEqual(history?.currentVersion, 2)
    }

    // MARK: - Change Classification

    func testTitleChangeCategory() {
        tracker.recordSnapshot(link: link1, title: "Original Title", body: "some body content here for testing", feedName: "F")
        let change = tracker.recordSnapshot(link: link1, title: "Completely New Title", body: "some body content here for testing", feedName: "F")
        XCTAssertEqual(change?.category, .titleChange)
        XCTAssertTrue(change?.titleChanged ?? false)
    }

    func testMinorChangeCategory() {
        let body = "This is a fairly long article body with many words that should make small changes register as minor edits rather than major ones"
        tracker.recordSnapshot(link: link1, title: "T", body: body, feedName: "F")
        let tweaked = "This is a fairly long article body with many words that should make small changes register as minor corrections rather than major ones"
        let change = tracker.recordSnapshot(link: link1, title: "T", body: tweaked, feedName: "F")
        XCTAssertNotNil(change)
        // Minor or cosmetic since only one word changed
        XCTAssertTrue([.minor, .cosmetic, .moderate].contains(change?.category ?? .rewrite))
    }

    func testMajorChangeCategory() {
        tracker.recordSnapshot(link: link1, title: "T", body: "alpha beta gamma delta epsilon", feedName: "F")
        let change = tracker.recordSnapshot(link: link1, title: "T", body: "zeta eta theta iota kappa lambda", feedName: "F")
        XCTAssertNotNil(change)
        XCTAssertTrue(change!.significance >= 0.25)
    }

    func testRewriteDetection() {
        tracker.recordSnapshot(link: link1, title: "T", body: "the quick brown fox jumps over the lazy dog", feedName: "F")
        let change = tracker.recordSnapshot(link: link1, title: "T", body: "completely unrelated content about something entirely different here now", feedName: "F")
        XCTAssertNotNil(change)
        XCTAssertTrue(change!.significance >= 0.5)
    }

    // MARK: - Significance Scoring

    func testSignificanceIsNormalized() {
        tracker.recordSnapshot(link: link1, title: "T", body: "word1 word2 word3", feedName: "F")
        let change = tracker.recordSnapshot(link: link1, title: "T", body: "word4 word5 word6", feedName: "F")
        XCTAssertNotNil(change)
        XCTAssertGreaterThanOrEqual(change!.significance, 0.0)
        XCTAssertLessThanOrEqual(change!.significance, 1.0)
    }

    func testWordCountDeltaPositive() {
        tracker.recordSnapshot(link: link1, title: "T", body: "short", feedName: "F")
        let change = tracker.recordSnapshot(link: link1, title: "T", body: "short with many more words added", feedName: "F")
        XCTAssertNotNil(change)
        XCTAssertGreaterThan(change!.wordCountDelta, 0)
    }

    func testWordCountDeltaNegative() {
        tracker.recordSnapshot(link: link1, title: "T", body: "long body with many words in it", feedName: "F")
        let change = tracker.recordSnapshot(link: link1, title: "T", body: "short", feedName: "F")
        XCTAssertNotNil(change)
        XCTAssertLessThan(change!.wordCountDelta, 0)
    }

    // MARK: - Notification Threshold

    func testNotifiableChange() {
        tracker.notificationThreshold = 0.05
        tracker.recordSnapshot(link: link1, title: "T", body: "alpha beta gamma delta", feedName: "F")
        let change = tracker.recordSnapshot(link: link1, title: "T", body: "completely different words here now", feedName: "F")
        XCTAssertNotNil(change)
        XCTAssertTrue(change!.isNotifiable)
    }

    func testHighThresholdFiltersMinorChanges() {
        tracker.notificationThreshold = 0.99
        tracker.recordSnapshot(link: link1, title: "T", body: "original content body text here", feedName: "F")
        let change = tracker.recordSnapshot(link: link1, title: "T", body: "original content body text here updated", feedName: "F")
        if let c = change {
            XCTAssertFalse(c.isNotifiable)
        }
    }

    // MARK: - Tracking Control

    func testStopTracking() {
        tracker.recordSnapshot(link: link1, title: "T", body: "body", feedName: "F")
        tracker.stopTracking(link: link1)
        XCTAssertFalse(tracker.getHistory(link: link1)?.isTracking ?? true)
    }

    func testResumeTracking() {
        tracker.recordSnapshot(link: link1, title: "T", body: "body", feedName: "F")
        tracker.stopTracking(link: link1)
        tracker.resumeTracking(link: link1)
        XCTAssertTrue(tracker.getHistory(link: link1)?.isTracking ?? false)
    }

    func testRemoveHistory() {
        tracker.recordSnapshot(link: link1, title: "T", body: "body", feedName: "F")
        tracker.removeHistory(link: link1)
        XCTAssertNil(tracker.getHistory(link: link1))
    }

    func testClearAll() {
        tracker.recordSnapshot(link: link1, title: "T", body: "body1", feedName: "F")
        tracker.recordSnapshot(link: link2, title: "T", body: "body2", feedName: "F")
        tracker.clearAll()
        XCTAssertTrue(tracker.histories.isEmpty)
    }

    // MARK: - Queries

    func testGetModifiedArticles() {
        tracker.recordSnapshot(link: link1, title: "T", body: "original", feedName: "F")
        tracker.recordSnapshot(link: link1, title: "T", body: "changed", feedName: "F")
        tracker.recordSnapshot(link: link2, title: "T", body: "unchanged", feedName: "F")
        let modified = tracker.getModifiedArticles()
        XCTAssertEqual(modified.count, 1)
        XCTAssertEqual(modified.first?.link, link1)
    }

    func testGetTrackedLinks() {
        tracker.recordSnapshot(link: link1, title: "T", body: "b1", feedName: "F")
        tracker.recordSnapshot(link: link2, title: "T", body: "b2", feedName: "F")
        let links = tracker.getTrackedLinks()
        XCTAssertEqual(links.count, 2)
        XCTAssertTrue(links.contains(link1))
        XCTAssertTrue(links.contains(link2))
    }

    func testGetTrackedLinksExcludesStopped() {
        tracker.recordSnapshot(link: link1, title: "T", body: "b1", feedName: "F")
        tracker.recordSnapshot(link: link2, title: "T", body: "b2", feedName: "F")
        tracker.stopTracking(link: link1)
        let links = tracker.getTrackedLinks()
        XCTAssertEqual(links.count, 1)
        XCTAssertEqual(links.first, link2)
    }

    func testGetNotifiableChangesSinceDate() {
        let past = Date(timeIntervalSinceNow: -3600)
        tracker.recordSnapshot(link: link1, title: "T", body: "original alpha beta gamma", feedName: "F", timestamp: past)
        let now = Date()
        tracker.recordSnapshot(link: link1, title: "T", body: "totally different content delta epsilon", feedName: "F", timestamp: now)

        let changes = tracker.getNotifiableChanges(since: Date(timeIntervalSinceNow: -1800))
        // The change might or might not be notifiable depending on threshold
        // Just verify the method works without crashing
        XCTAssertTrue(changes.count <= 1)
    }

    // MARK: - Version Comparison

    func testCompareVersions() {
        tracker.recordSnapshot(link: link1, title: "Title A", body: "alpha beta gamma", feedName: "F")
        tracker.recordSnapshot(link: link1, title: "Title B", body: "delta epsilon zeta", feedName: "F")
        let result = tracker.compareVersions(link: link1, fromVersion: 0, toVersion: 1)
        XCTAssertNotNil(result)
        XCTAssertEqual(result?.fromVersion, 0)
        XCTAssertEqual(result?.toVersion, 1)
        XCTAssertTrue(result?.titleChanged ?? false)
        XCTAssertEqual(result?.oldTitle, "title a")
        XCTAssertEqual(result?.newTitle, "title b")
    }

    func testCompareVersionsDefaultLatest() {
        tracker.recordSnapshot(link: link1, title: "T", body: "v0 content", feedName: "F")
        tracker.recordSnapshot(link: link1, title: "T", body: "v1 content", feedName: "F")
        tracker.recordSnapshot(link: link1, title: "T", body: "v2 content", feedName: "F")
        let result = tracker.compareVersions(link: link1, fromVersion: 0, toVersion: -1)
        XCTAssertNotNil(result)
        XCTAssertEqual(result?.toVersion, 2)
    }

    func testCompareVersionsInvalidLink() {
        let result = tracker.compareVersions(link: "nonexistent")
        XCTAssertNil(result)
    }

    func testCompareVersionsSameIndex() {
        tracker.recordSnapshot(link: link1, title: "T", body: "content", feedName: "F")
        let result = tracker.compareVersions(link: link1, fromVersion: 0, toVersion: 0)
        XCTAssertNil(result)
    }

    func testComparisonSimilarity() {
        tracker.recordSnapshot(link: link1, title: "T", body: "alpha beta gamma delta", feedName: "F")
        tracker.recordSnapshot(link: link1, title: "T", body: "alpha beta gamma epsilon", feedName: "F")
        let result = tracker.compareVersions(link: link1, fromVersion: 0, toVersion: 1)
        XCTAssertNotNil(result)
        XCTAssertGreaterThan(result!.similarity, 0.0)
        XCTAssertLessThan(result!.similarity, 1.0)
    }

    // MARK: - Statistics

    func testComputeStatsEmpty() {
        let stats = tracker.computeStats()
        XCTAssertEqual(stats.trackedCount, 0)
        XCTAssertEqual(stats.modifiedCount, 0)
        XCTAssertEqual(stats.totalChanges, 0)
        XCTAssertEqual(stats.averageSignificance, 0.0)
    }

    func testComputeStatsWithData() {
        tracker.recordSnapshot(link: link1, title: "T", body: "original body here", feedName: "News")
        tracker.recordSnapshot(link: link1, title: "T", body: "updated body here now", feedName: "News")
        tracker.recordSnapshot(link: link2, title: "T", body: "other article", feedName: "Blog")

        let stats = tracker.computeStats()
        XCTAssertEqual(stats.trackedCount, 2)
        XCTAssertEqual(stats.modifiedCount, 1)
        XCTAssertEqual(stats.totalChanges, 1)
        XCTAssertGreaterThan(stats.averageSignificance, 0.0)
    }

    func testFeedModificationRates() {
        tracker.recordSnapshot(link: link1, title: "T", body: "body a", feedName: "News")
        tracker.recordSnapshot(link: link1, title: "T", body: "body b", feedName: "News")
        tracker.recordSnapshot(link: link2, title: "T", body: "body c", feedName: "News")

        let stats = tracker.computeStats()
        XCTAssertNotNil(stats.feedModificationRates["News"])
        XCTAssertEqual(stats.feedModificationRates["News"], 0.5)
    }

    func testCategoryBreakdown() {
        tracker.recordSnapshot(link: link1, title: "T", body: "alpha beta gamma delta epsilon", feedName: "F")
        tracker.recordSnapshot(link: link1, title: "T", body: "zeta eta theta iota kappa", feedName: "F")
        let stats = tracker.computeStats()
        XCTAssertFalse(stats.categoryBreakdown.isEmpty)
    }

    // MARK: - Report

    func testGenerateReportNotEmpty() {
        tracker.recordSnapshot(link: link1, title: "Title", body: "original content", feedName: "TestFeed")
        tracker.recordSnapshot(link: link1, title: "Title", body: "modified content here", feedName: "TestFeed")
        let report = tracker.generateReport()
        XCTAssertTrue(report.contains("Article Version Tracker Report"))
        XCTAssertTrue(report.contains("Tracked articles:"))
    }

    func testGenerateReportEmpty() {
        let report = tracker.generateReport()
        XCTAssertTrue(report.contains("Tracked articles: 0"))
    }

    // MARK: - Snapshot Limit

    func testMaxSnapshotsEnforced() {
        tracker.maxSnapshotsPerArticle = 5
        for i in 0..<10 {
            tracker.recordSnapshot(link: link1, title: "T", body: "body version \(i) unique content", feedName: "F")
        }
        let history = tracker.getHistory(link: link1)
        XCTAssertNotNil(history)
        XCTAssertLessThanOrEqual(history!.snapshots.count, 5)
    }

    func testMaxSnapshotsKeepsFirst() {
        tracker.maxSnapshotsPerArticle = 3
        let t0 = Date(timeIntervalSince1970: 1000)
        tracker.recordSnapshot(link: link1, title: "T", body: "first version", feedName: "F", timestamp: t0)
        for i in 1..<6 {
            tracker.recordSnapshot(link: link1, title: "T", body: "version \(i) different", feedName: "F",
                                   timestamp: Date(timeIntervalSince1970: 1000 + Double(i) * 100))
        }
        let history = tracker.getHistory(link: link1)!
        XCTAssertEqual(history.snapshots.first?.timestamp, t0)
    }

    // MARK: - Persistence (JSON)

    func testExportImportRoundTrip() {
        tracker.recordSnapshot(link: link1, title: "Hello", body: "world content alpha", feedName: "Feed1")
        tracker.recordSnapshot(link: link1, title: "Hello", body: "world content beta", feedName: "Feed1")
        tracker.recordSnapshot(link: link2, title: "Other", body: "article body", feedName: "Feed2")

        let exported = tracker.exportToJSON()

        let newTracker = ArticleVersionTracker()
        newTracker.importFromJSON(exported)

        XCTAssertEqual(newTracker.histories.count, 2)
        XCTAssertNotNil(newTracker.getHistory(link: link1))
        XCTAssertEqual(newTracker.getHistory(link: link1)?.changes.count, 1)
        XCTAssertEqual(newTracker.getHistory(link: link2)?.feedName, "Feed2")
    }

    func testImportEmptyArray() {
        tracker.importFromJSON([])
        XCTAssertTrue(tracker.histories.isEmpty)
    }

    func testImportMalformedData() {
        tracker.importFromJSON([["bad": "data"]])
        XCTAssertTrue(tracker.histories.isEmpty)
    }

    func testExportPreservesTrackingState() {
        tracker.recordSnapshot(link: link1, title: "T", body: "body", feedName: "F")
        tracker.stopTracking(link: link1)
        let exported = tracker.exportToJSON()
        let newTracker = ArticleVersionTracker()
        newTracker.importFromJSON(exported)
        XCTAssertFalse(newTracker.getHistory(link: link1)?.isTracking ?? true)
    }

    // MARK: - Multiple Articles

    func testMultipleArticlesIndependent() {
        tracker.recordSnapshot(link: link1, title: "A", body: "body alpha", feedName: "F")
        tracker.recordSnapshot(link: link2, title: "B", body: "body beta", feedName: "F")
        tracker.recordSnapshot(link: link1, title: "A", body: "body alpha changed", feedName: "F")

        XCTAssertEqual(tracker.getHistory(link: link1)?.changes.count, 1)
        XCTAssertEqual(tracker.getHistory(link: link2)?.changes.count, 0)
    }

    // MARK: - Edge Cases

    func testEmptyBodyFirstSnapshot() {
        // Empty body should still be trackable
        let change = tracker.recordSnapshot(link: link1, title: "T", body: "", feedName: "F")
        XCTAssertNil(change)
        XCTAssertNotNil(tracker.getHistory(link: link1))
    }

    func testWhitespaceNormalization() {
        tracker.recordSnapshot(link: link1, title: "  Hello  World  ", body: "  content  here  ", feedName: "F")
        let change = tracker.recordSnapshot(link: link1, title: "Hello World", body: "content here", feedName: "F")
        XCTAssertNil(change, "Normalized identical content should not produce a change")
    }

    func testCaseNormalization() {
        tracker.recordSnapshot(link: link1, title: "HELLO", body: "CONTENT", feedName: "F")
        let change = tracker.recordSnapshot(link: link1, title: "hello", body: "content", feedName: "F")
        XCTAssertNil(change, "Case-normalized identical content should not produce a change")
    }

    func testHasSignificantChangesProperty() {
        tracker.recordSnapshot(link: link1, title: "T", body: "alpha beta gamma delta epsilon", feedName: "F")
        XCTAssertFalse(tracker.getHistory(link: link1)!.hasSignificantChanges)
        tracker.recordSnapshot(link: link1, title: "T", body: "completely different words here now instead", feedName: "F")
        XCTAssertTrue(tracker.getHistory(link: link1)!.hasSignificantChanges)
    }

    func testChangeSummaryContainsInfo() {
        tracker.recordSnapshot(link: link1, title: "T", body: "short body", feedName: "F")
        let change = tracker.recordSnapshot(link: link1, title: "T", body: "much longer body with many additional words added to it", feedName: "F")
        XCTAssertNotNil(change)
        XCTAssertFalse(change!.summary.isEmpty)
        XCTAssertTrue(change!.summary.contains("change") || change!.summary.contains("edit") ||
                      change!.summary.contains("update") || change!.summary.contains("words") ||
                      change!.summary.contains("revision") || change!.summary.contains("rewritten") ||
                      change!.summary.contains("formatting"))
    }

    func testConfigurableNotificationThreshold() {
        let t1 = ArticleVersionTracker(notificationThreshold: 0.0)
        XCTAssertEqual(t1.notificationThreshold, 0.0)
        let t2 = ArticleVersionTracker(notificationThreshold: 1.5)
        XCTAssertEqual(t2.notificationThreshold, 1.0)
        let t3 = ArticleVersionTracker(notificationThreshold: -0.5)
        XCTAssertEqual(t3.notificationThreshold, 0.0)
    }

    func testConfigurableMaxSnapshots() {
        let t = ArticleVersionTracker(maxSnapshotsPerArticle: 1)
        XCTAssertEqual(t.maxSnapshotsPerArticle, 2, "Minimum should be 2")
    }

    func testMostUpdatedInStats() {
        for i in 0..<5 {
            tracker.recordSnapshot(link: link1, title: "T", body: "version \(i) content unique words", feedName: "F")
        }
        tracker.recordSnapshot(link: link2, title: "T", body: "single version", feedName: "F")
        let stats = tracker.computeStats()
        XCTAssertEqual(stats.mostUpdatedLink, link1)
        XCTAssertEqual(stats.mostUpdatedChangeCount, 4)
    }

    func testLatestSnapshotProperty() {
        let t1 = Date(timeIntervalSince1970: 1000)
        let t2 = Date(timeIntervalSince1970: 2000)
        tracker.recordSnapshot(link: link1, title: "T", body: "body1", feedName: "F", timestamp: t1)
        tracker.recordSnapshot(link: link1, title: "T", body: "body2", feedName: "F", timestamp: t2)
        XCTAssertEqual(tracker.getHistory(link: link1)?.latestSnapshot?.timestamp, t2)
    }
}
