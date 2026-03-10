//
//  ArticleEditTrackerTests.swift
//  FeedReaderTests
//
//  Tests for the Article Edit Tracker — stealth edit detection.
//

import XCTest
@testable import FeedReader

class ArticleEditTrackerTests: XCTestCase {

    var tracker: ArticleEditTracker!

    override func setUp() {
        super.setUp()
        tracker = ArticleEditTracker()
        tracker.clearAll()
    }

    // MARK: - Basic Recording

    func testFirstSnapshotReturnsNil() {
        let result = tracker.recordSnapshot(link: "https://example.com/article1", title: "Title", body: "Body text")
        XCTAssertNil(result, "First snapshot should return nil (no previous revision to compare)")
    }

    func testIdenticalSnapshotReturnsNil() {
        tracker.recordSnapshot(link: "https://example.com/a", title: "T", body: "Body")
        let result = tracker.recordSnapshot(link: "https://example.com/a", title: "T", body: "Body")
        XCTAssertNil(result, "Identical content should not be recorded as a change")
    }

    func testChangedBodyReturnsSummary() {
        tracker.recordSnapshot(link: "https://example.com/b", title: "T", body: "The cat sat on the mat")
        let summary = tracker.recordSnapshot(link: "https://example.com/b", title: "T", body: "The dog sat on the mat")
        XCTAssertNotNil(summary)
        XCTAssertFalse(summary!.titleChanged)
        XCTAssertGreaterThan(summary!.wordsAdded, 0)
        XCTAssertGreaterThan(summary!.wordsRemoved, 0)
    }

    func testChangedTitleDetected() {
        tracker.recordSnapshot(link: "https://example.com/c", title: "Original Title", body: "Body")
        let summary = tracker.recordSnapshot(link: "https://example.com/c", title: "Updated Title", body: "Body")
        XCTAssertNotNil(summary)
        XCTAssertTrue(summary!.titleChanged)
    }

    func testEmptyLinkIgnored() {
        let result = tracker.recordSnapshot(link: "", title: "T", body: "B")
        XCTAssertNil(result)
        XCTAssertEqual(tracker.trackedArticleCount, 0)
    }

    // MARK: - Revision History

    func testRevisionHistoryTracked() {
        let link = "https://example.com/d"
        tracker.recordSnapshot(link: link, title: "V1", body: "Version one")
        tracker.recordSnapshot(link: link, title: "V2", body: "Version two")
        tracker.recordSnapshot(link: link, title: "V3", body: "Version three")

        let revisions = tracker.getRevisions(for: link)
        XCTAssertEqual(revisions.count, 3)
        XCTAssertEqual(revisions[0].title, "V1")
        XCTAssertEqual(revisions[2].title, "V3")
    }

    func testEditCount() {
        let link = "https://example.com/e"
        XCTAssertEqual(tracker.editCount(for: link), 0)
        tracker.recordSnapshot(link: link, title: "T", body: "V1")
        XCTAssertEqual(tracker.editCount(for: link), 0)
        tracker.recordSnapshot(link: link, title: "T", body: "V2")
        XCTAssertEqual(tracker.editCount(for: link), 1)
        tracker.recordSnapshot(link: link, title: "T", body: "V3")
        XCTAssertEqual(tracker.editCount(for: link), 2)
    }

    // MARK: - Edited Articles List

    func testEditedArticlesOnlyReturnsEdited() {
        tracker.recordSnapshot(link: "https://a.com/1", title: "T", body: "B1")
        tracker.recordSnapshot(link: "https://a.com/2", title: "T", body: "B1")
        tracker.recordSnapshot(link: "https://a.com/2", title: "T", body: "B2") // edited

        let edited = tracker.editedArticles()
        XCTAssertEqual(edited.count, 1)
        XCTAssertEqual(edited[0].link, "https://a.com/2")
        XCTAssertEqual(edited[0].editCount, 1)
    }

    // MARK: - Change History

    func testChangeHistory() {
        let link = "https://example.com/f"
        tracker.recordSnapshot(link: link, title: "T", body: "Word one")
        tracker.recordSnapshot(link: link, title: "T", body: "Word two")
        tracker.recordSnapshot(link: link, title: "T2", body: "Word three")

        let history = tracker.changeHistory(for: link)
        XCTAssertEqual(history.count, 2)
        XCTAssertFalse(history[0].titleChanged)
        XCTAssertTrue(history[1].titleChanged)
    }

    // MARK: - Link Normalization

    func testLinkNormalizationCaseInsensitive() {
        tracker.recordSnapshot(link: "HTTPS://EXAMPLE.COM/G", title: "T", body: "V1")
        let summary = tracker.recordSnapshot(link: "https://example.com/g", title: "T", body: "V2")
        XCTAssertNotNil(summary, "Links should be case-insensitive")
    }

    // MARK: - Clear

    func testClearAll() {
        tracker.recordSnapshot(link: "https://a.com/1", title: "T", body: "B")
        tracker.recordSnapshot(link: "https://a.com/2", title: "T", body: "B")
        tracker.clearAll()
        XCTAssertEqual(tracker.trackedArticleCount, 0)
    }

    func testClearRevisionsForLink() {
        tracker.recordSnapshot(link: "https://a.com/1", title: "T", body: "B")
        tracker.recordSnapshot(link: "https://a.com/2", title: "T", body: "B")
        tracker.clearRevisions(for: "https://a.com/1")
        XCTAssertEqual(tracker.trackedArticleCount, 1)
        XCTAssertEqual(tracker.getRevisions(for: "https://a.com/1").count, 0)
    }

    // MARK: - Totals

    func testTotalEditsDetected() {
        tracker.recordSnapshot(link: "https://a.com/1", title: "T", body: "V1")
        tracker.recordSnapshot(link: "https://a.com/1", title: "T", body: "V2")
        tracker.recordSnapshot(link: "https://a.com/2", title: "T", body: "V1")
        tracker.recordSnapshot(link: "https://a.com/2", title: "T", body: "V2")
        tracker.recordSnapshot(link: "https://a.com/2", title: "T", body: "V3")
        XCTAssertEqual(tracker.totalEditsDetected, 3)
    }

    // MARK: - Diff Engine

    func testComputeChangeSummaryWordsAddedRemoved() {
        let old = ArticleRevision(timestamp: Date(), title: "T", body: "The quick brown fox", link: "x")
        let new = ArticleRevision(timestamp: Date(), title: "T", body: "The slow brown fox jumps", link: "x")
        let summary = tracker.computeChangeSummary(old: old, new: new)
        XCTAssertEqual(summary.wordsAdded, 2) // "slow", "jumps"
        XCTAssertEqual(summary.wordsRemoved, 1) // "quick"
        XCTAssertFalse(summary.titleChanged)
    }

    func testChangeSummaryDescription() {
        let summary = ArticleRevision.ChangeSummary(
            wordsAdded: 5, wordsRemoved: 2, titleChanged: true,
            addedSegments: [], removedSegments: []
        )
        XCTAssertEqual(summary.description, "title changed, +5 words, -2 words")
    }

    func testChangeSummaryNoChanges() {
        let summary = ArticleRevision.ChangeSummary(
            wordsAdded: 0, wordsRemoved: 0, titleChanged: false,
            addedSegments: [], removedSegments: []
        )
        XCTAssertFalse(summary.hasChanges)
        XCTAssertEqual(summary.description, "no changes")
    }

    // MARK: - Sentence-Level Segments

    func testAddedRemovedSegments() {
        let old = ArticleRevision(timestamp: Date(), title: "T",
            body: "The president spoke today. Markets were down.", link: "x")
        let new = ArticleRevision(timestamp: Date(), title: "T",
            body: "The president spoke today. Markets rallied sharply.", link: "x")
        let summary = tracker.computeChangeSummary(old: old, new: new)
        XCTAssertTrue(summary.addedSegments.contains("Markets rallied sharply."))
        XCTAssertTrue(summary.removedSegments.contains("Markets were down."))
    }

    // MARK: - Max Revisions Cap

    func testMaxRevisionsCapped() {
        let link = "https://example.com/capped"
        for i in 0..<25 {
            tracker.recordSnapshot(link: link, title: "T", body: "Version \(i)")
        }
        let revisions = tracker.getRevisions(for: link)
        XCTAssertLessThanOrEqual(revisions.count, 20)
    }

    // MARK: - Pruning

    func testPruneStaleRemovesOldUnedited() {
        // Manually inject an old single-revision entry
        tracker.recordSnapshot(link: "https://old.com/stale", title: "T", body: "Old body")
        tracker.recordSnapshot(link: "https://new.com/fresh", title: "T", body: "Fresh body")

        // Both have 1 revision, but pruneStale with 0 interval should remove both
        tracker.pruneStale(olderThan: 0)
        // They were just created so timestamp is ~now, interval=0 means cutoff=now
        // so they should be pruned
        XCTAssertEqual(tracker.trackedArticleCount, 0)
    }

    func testPruneDoesNotRemoveEditedArticles() {
        tracker.recordSnapshot(link: "https://edited.com/1", title: "T", body: "V1")
        tracker.recordSnapshot(link: "https://edited.com/1", title: "T", body: "V2")
        tracker.pruneStale(olderThan: 0)
        // Edited articles (>1 revision) should NOT be pruned
        XCTAssertEqual(tracker.trackedArticleCount, 1)
    }
}
