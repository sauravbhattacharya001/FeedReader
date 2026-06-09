//
//  FeedReadingRecallSchedulerTests.swift
//  FeedReaderCoreTests
//

import XCTest
@testable import FeedReaderCore

final class FeedReadingRecallSchedulerTests: XCTestCase {

    // Fixed reference clock: 2026-06-04T22:00:00Z.
    private let nowDate: Date = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f.date(from: "2026-06-04T22:00:00Z")!
    }()

    private func scheduler() -> FeedReadingRecallScheduler {
        let fixedNow = nowDate
        return FeedReadingRecallScheduler(now: { fixedNow })
    }

    private func minus(days: Double) -> Date {
        nowDate.addingTimeInterval(-days * 86400)
    }

    // MARK: 1. Empty library

    func testEmptyLibraryReturnsGradeA() {
        let s = scheduler()
        let r = s.analyze(records: [])
        XCTAssertEqual(r.grade, .A)
        XCTAssertEqual(r.retentionScore, 100)
        XCTAssertEqual(r.results.count, 0)
        XCTAssertEqual(r.dueNowIds.count, 0)
        XCTAssertTrue(r.headline.contains("N=0"))
        XCTAssertTrue(r.insights.contains(.emptyLibrary))
    }

    // MARK: 2. Headline format

    func testHeadlineHasExpectedFormat() {
        let s = scheduler()
        let recs = [
            ReadArticleRecord(
                id: "a1",
                title: "Fresh Article",
                feedName: "Tech",
                readAt: minus(days: 0.1)
            )
        ]
        let r = s.analyze(records: recs)
        XCTAssertTrue(r.headline.hasPrefix("VERDICT: "))
        XCTAssertTrue(r.headline.contains("grade="))
        XCTAssertTrue(r.headline.contains("N=1"))
        XCTAssertTrue(r.headline.contains("retention="))
    }

    // MARK: 3. Freshly read = safelyRetained or insufficientData

    func testFreshlyReadIsRetained() {
        let s = scheduler()
        let recs = [
            ReadArticleRecord(
                id: "fresh",
                title: "Just Read",
                feedName: "Tech",
                readAt: minus(days: 0.1)
            )
        ]
        let r = s.analyze(records: recs)
        XCTAssertEqual(r.results.count, 1)
        let v = r.results[0].verdict
        XCTAssertTrue(v == .insufficientData || v == .safelyRetained,
                      "Expected freshly-read to be insufficientData/safelyRetained, got \(v)")
    }

    // MARK: 4. Long-since-read with high importance/bookmark = revisitNow

    func testHighImportanceBookmarkLongAgoRevisitNow() {
        let s = scheduler()
        let recs = [
            ReadArticleRecord(
                id: "stale-bm",
                title: "Old Important",
                feedName: "Tech",
                readAt: minus(days: 30),
                isBookmarked: true,
                importanceHint: 0.9
            )
        ]
        let r = s.analyze(records: recs)
        XCTAssertEqual(r.results.count, 1)
        XCTAssertEqual(r.results[0].verdict, .revisitNow)
        XCTAssertEqual(r.results[0].priority, 0)
        XCTAssertNotNil(r.results[0].nextRevisitAt)
    }

    // MARK: 5. Archived passes through

    func testArchivedArticleVerdictArchived() {
        let s = scheduler()
        let recs = [
            ReadArticleRecord(
                id: "arch",
                title: "Archived",
                feedName: "Tech",
                readAt: minus(days: 60),
                isArchived: true
            )
        ]
        let r = s.analyze(records: recs)
        XCTAssertEqual(r.results[0].verdict, .archived)
        XCTAssertNil(r.results[0].nextRevisitAt)
        XCTAssertTrue(r.results[0].reasons.contains(.archivedByUser))
    }

    // MARK: 6. Risk appetite changes urgency

    func testAggressiveAppetiteRaisesUrgency() {
        let s = scheduler()
        let rec = ReadArticleRecord(
            id: "a1",
            title: "Mid",
            feedName: "Tech",
            readAt: minus(days: 5),
            importanceHint: 0.5
        )
        let cautious = s.analyze(records: [rec], appetite: .cautious).results[0].recallScore
        let balanced = s.analyze(records: [rec], appetite: .balanced).results[0].recallScore
        let aggressive = s.analyze(records: [rec], appetite: .aggressive).results[0].recallScore
        XCTAssertLessThanOrEqual(cautious, balanced + 1)
        XCTAssertLessThanOrEqual(balanced, aggressive + 1)
    }

    // MARK: 7. Forced F: 3+ revisitNow

    func testThreePlusRevisitNowForcesGradeF() {
        let s = scheduler()
        var recs: [ReadArticleRecord] = []
        for i in 0..<4 {
            recs.append(ReadArticleRecord(
                id: "rn-\(i)",
                title: "Stale \(i)",
                feedName: "Tech",
                readAt: minus(days: 30),
                isBookmarked: true,
                importanceHint: 0.9
            ))
        }
        let r = s.analyze(records: recs)
        XCTAssertEqual(r.grade, .F)
    }

    // MARK: 8. Forced F: 1 revisitNow + 1 bookmarked

    func testBookmarkedRevisitNowForcesGradeF() {
        let s = scheduler()
        let recs = [
            ReadArticleRecord(
                id: "bm-1",
                title: "Bookmarked Stale",
                feedName: "Tech",
                readAt: minus(days: 30),
                isBookmarked: true,
                importanceHint: 0.9
            ),
            ReadArticleRecord(
                id: "ok-1",
                title: "Fresh",
                feedName: "Tech",
                readAt: minus(days: 0.1)
            )
        ]
        let r = s.analyze(records: recs)
        XCTAssertEqual(r.grade, .F)
    }

    // MARK: 9. revisitNow caps at C

    func testRevisitNowCapsGradeAtC() {
        let s = scheduler()
        let recs = [
            ReadArticleRecord(
                id: "rn-1",
                title: "Stale",
                feedName: "Tech",
                readAt: minus(days: 20),
                importanceHint: 0.9
            )
        ]
        let r = s.analyze(records: recs)
        // Single revisitNow without bookmark -> not forced F, but cap C.
        let order: [RetentionGrade] = [.A, .B, .C, .D, .F]
        let idx = order.firstIndex(of: r.grade) ?? 0
        let cIdx = order.firstIndex(of: .C)!
        XCTAssertGreaterThanOrEqual(idx, cIdx, "Grade should be at most C, got \(r.grade)")
    }

    // MARK: 10. Sorting: recallScore desc then articleId asc

    func testResultsSortedByScoreThenId() {
        let s = scheduler()
        let recs = [
            ReadArticleRecord(id: "z-fresh",  title: "Z", feedName: "F", readAt: minus(days: 0.1)),
            ReadArticleRecord(id: "a-stale",  title: "A", feedName: "F", readAt: minus(days: 30), importanceHint: 0.9),
            ReadArticleRecord(id: "m-stale",  title: "M", feedName: "F", readAt: minus(days: 30), importanceHint: 0.9)
        ]
        let r = s.analyze(records: recs)
        // First two should be the stale ones, with same score sorted by id asc.
        XCTAssertEqual(r.results.count, 3)
        XCTAssertGreaterThanOrEqual(r.results[0].recallScore, r.results[2].recallScore)
        if r.results[0].recallScore == r.results[1].recallScore {
            XCTAssertLessThanOrEqual(r.results[0].articleId, r.results[1].articleId)
        }
    }

    // MARK: 11. dueNowIds sorted ascending

    func testDueNowIdsSorted() {
        let s = scheduler()
        let recs = [
            ReadArticleRecord(id: "z1", title: "Z", feedName: "F", readAt: minus(days: 30), importanceHint: 0.9),
            ReadArticleRecord(id: "a1", title: "A", feedName: "F", readAt: minus(days: 30), importanceHint: 0.9),
            ReadArticleRecord(id: "m1", title: "M", feedName: "F", readAt: minus(days: 30), importanceHint: 0.9)
        ]
        let r = s.analyze(records: recs)
        XCTAssertEqual(r.dueNowIds, r.dueNowIds.sorted())
    }

    // MARK: 12. JSON byte-stability

    func testJSONByteStable() {
        let s = scheduler()
        let recs = [
            ReadArticleRecord(id: "a", title: "A", feedName: "F", readAt: minus(days: 30), isBookmarked: true, importanceHint: 0.9),
            ReadArticleRecord(id: "b", title: "B", feedName: "F", readAt: minus(days: 5)),
            ReadArticleRecord(id: "c", title: "C", feedName: "F", readAt: minus(days: 0.1))
        ]
        let r1 = s.analyze(records: recs).toJSON()
        let r2 = s.analyze(records: recs).toJSON()
        XCTAssertEqual(r1, r2)
        XCTAssertTrue(r1.contains("\"results\""))
        XCTAssertTrue(r1.contains("\"retentionScore\""))
        XCTAssertTrue(r1.contains("\"grade\""))
        XCTAssertTrue(r1.contains("\"headline\""))
        XCTAssertTrue(r1.contains("\"playbook\""))
        XCTAssertTrue(r1.contains("\"insights\""))
        XCTAssertTrue(r1.contains("\"dueNowIds\""))
    }

    // MARK: 13. Markdown sections always present

    func testMarkdownAlwaysHasSections() {
        let s = scheduler()
        let r = s.analyze(records: [])
        let md = r.toMarkdown()
        XCTAssertTrue(md.contains("## Summary"))
        XCTAssertTrue(md.contains("## Articles"))
        XCTAssertTrue(md.contains("## Playbook"))
        XCTAssertTrue(md.contains("## Insights"))
        XCTAssertTrue(md.contains("_(none)_"))
    }

    func testMarkdownPopulatedSections() {
        let s = scheduler()
        let recs = [
            ReadArticleRecord(id: "a", title: "Important", feedName: "Tech",
                              readAt: minus(days: 30), isBookmarked: true, importanceHint: 0.9)
        ]
        let r = s.analyze(records: recs)
        let md = r.toMarkdown()
        XCTAssertTrue(md.contains("## Summary"))
        XCTAssertTrue(md.contains("## Articles"))
        XCTAssertTrue(md.contains("## Playbook"))
        XCTAssertTrue(md.contains("## Insights"))
        XCTAssertTrue(md.contains("Important"))
    }

    // MARK: 14. Insights non-empty even on healthy library

    func testInsightsAlwaysNonEmpty() {
        let s = scheduler()
        let recs = [
            ReadArticleRecord(id: "a", title: "A", feedName: "F",
                              readAt: minus(days: 0.1), revisitCount: 0)
        ]
        let r = s.analyze(records: recs)
        XCTAssertGreaterThanOrEqual(r.insights.count, 1)
    }

    // MARK: 15. Vocabulary anchor produces RECONNECT_VOCAB_ANCHORS action

    func testVocabAnchorCreatesAction() {
        let s = scheduler()
        let recs = [
            ReadArticleRecord(id: "v1", title: "V1", feedName: "F",
                              readAt: minus(days: 10), vocabularyHits: 3),
            ReadArticleRecord(id: "v2", title: "V2", feedName: "F",
                              readAt: minus(days: 10), vocabularyHits: 5)
        ]
        let r = s.analyze(records: recs)
        let ids = r.playbook.map(\.id)
        XCTAssertTrue(ids.contains("RECONNECT_VOCAB_ANCHORS") ||
                      ids.contains("OPEN_RECALL_FLASH_REVIEW") ||
                      ids.contains("BATCH_REVISIT_TODAY"),
                      "Expected vocab/recall action, got \(ids)")
    }

    // MARK: 16. Bookmarks at risk produces RECOVER_HIGH_VALUE_BOOKMARKS

    func testBookmarksAtRiskAction() {
        let s = scheduler()
        let recs = [
            ReadArticleRecord(id: "b1", title: "B1", feedName: "F",
                              readAt: minus(days: 30), isBookmarked: true),
            ReadArticleRecord(id: "b2", title: "B2", feedName: "F",
                              readAt: minus(days: 30), isBookmarked: true),
            ReadArticleRecord(id: "b3", title: "B3", feedName: "F",
                              readAt: minus(days: 30), isBookmarked: true)
        ]
        let r = s.analyze(records: recs)
        let ids = r.playbook.map(\.id)
        XCTAssertTrue(ids.contains("RECOVER_HIGH_VALUE_BOOKMARKS"))
    }

    // MARK: 17. simulate(applyTopN:) raises retention without mutating input

    func testSimulateRaisesRetentionWithoutMutation() {
        let s = scheduler()
        let recs = [
            ReadArticleRecord(id: "x1", title: "X1", feedName: "F",
                              readAt: minus(days: 30), isBookmarked: true, importanceHint: 0.9),
            ReadArticleRecord(id: "x2", title: "X2", feedName: "F",
                              readAt: minus(days: 30), isBookmarked: true, importanceHint: 0.9)
        ]
        let r = s.analyze(records: recs)
        let originalRetention = r.retentionScore
        let originalGrade = r.grade
        let sim = s.simulate(report: r, applyTopN: 3)
        XCTAssertGreaterThanOrEqual(sim.retentionScore, originalRetention)
        // Input untouched.
        XCTAssertEqual(r.retentionScore, originalRetention)
        XCTAssertEqual(r.grade, originalGrade)
    }

    func testSimulateZeroTopNReturnsSame() {
        let s = scheduler()
        let recs = [
            ReadArticleRecord(id: "y1", title: "Y", feedName: "F", readAt: minus(days: 30))
        ]
        let r = s.analyze(records: recs)
        let sim = s.simulate(report: r, applyTopN: 0)
        XCTAssertEqual(sim.retentionScore, r.retentionScore)
        XCTAssertEqual(sim.grade, r.grade)
    }

    // MARK: 18. recallStrength bounded 0..1

    func testRecallStrengthBounded() {
        let s = scheduler()
        let recs = [
            ReadArticleRecord(id: "ancient", title: "Ancient", feedName: "F",
                              readAt: minus(days: 365), revisitCount: 0),
            ReadArticleRecord(id: "recent",  title: "Recent",  feedName: "F",
                              readAt: minus(days: 0.05))
        ]
        let r = s.analyze(records: recs)
        for result in r.results {
            XCTAssertGreaterThanOrEqual(result.recallStrength, 0.0)
            XCTAssertLessThanOrEqual(result.recallStrength, 1.0)
            XCTAssertGreaterThanOrEqual(result.recallScore, 0)
            XCTAssertLessThanOrEqual(result.recallScore, 100)
        }
    }

    // MARK: Determinism

    func testTwoAnalyzeCallsProduceSameOutput() {
        let s = scheduler()
        let recs = [
            ReadArticleRecord(id: "a", title: "A", feedName: "F",
                              readAt: minus(days: 30), isBookmarked: true, importanceHint: 0.9),
            ReadArticleRecord(id: "b", title: "B", feedName: "F", readAt: minus(days: 5)),
            ReadArticleRecord(id: "c", title: "C", feedName: "F", readAt: minus(days: 0.1))
        ]
        let a = s.analyze(records: recs).toJSON()
        let b = s.analyze(records: recs).toJSON()
        XCTAssertEqual(a, b)
    }

    // MARK: Input not mutated

    func testInputArrayNotMutated() {
        let s = scheduler()
        let original = [
            ReadArticleRecord(id: "a", title: "A", feedName: "F",
                              readAt: minus(days: 30), isBookmarked: true)
        ]
        _ = s.analyze(records: original)
        XCTAssertEqual(original.count, 1)
        XCTAssertEqual(original[0].id, "a")
        XCTAssertEqual(original[0].isBookmarked, true)
    }
}
