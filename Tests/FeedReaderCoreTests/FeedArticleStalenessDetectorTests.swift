//
//  FeedArticleStalenessDetectorTests.swift
//  FeedReaderTests
//

import XCTest
@testable import FeedReaderCore

final class FeedArticleStalenessDetectorTests: XCTestCase {

    private let fixedDate = ISO8601DateFormatter().date(from: "2026-06-04T22:00:00Z")!

    private func makeDetector(appetite: StalenessRiskAppetite = .balanced) -> FeedArticleStalenessDetector {
        let d = FeedArticleStalenessDetector(now: { [fixedDate] in fixedDate })
        d.riskAppetite = appetite
        return d
    }

    private func makeArticle(
        id: String = "art1",
        title: String = "Test Article",
        feedName: String = "TestFeed",
        daysOld: Double = 0,
        keywords: [String] = ["swift", "ios"],
        isTimeSensitive: Bool = false,
        eventDate: Date? = nil,
        hasCorrection: Bool = false,
        topicInterest: Double = 0.5
    ) -> UnreadArticle {
        UnreadArticle(
            id: id,
            title: title,
            feedName: feedName,
            publishedAt: fixedDate.addingTimeInterval(-daysOld * 86400),
            keywords: keywords,
            isTimeSensitive: isTimeSensitive,
            eventDate: eventDate,
            hasCorrection: hasCorrection,
            topicInterest: topicInterest
        )
    }

    // MARK: - Empty Input

    func testEmptyInput() {
        let report = makeDetector().analyze(articles: [])
        XCTAssertEqual(report.results.count, 0)
        XCTAssertEqual(report.backlogScore, 0)
        XCTAssertEqual(report.grade, .A)
        XCTAssertTrue(report.insights.contains(.emptyQueue))
        XCTAssertTrue(report.archiveCandidateIds.isEmpty)
    }

    // MARK: - Fresh Article

    func testFreshArticle() {
        let article = makeArticle(daysOld: 1)
        let report = makeDetector().analyze(articles: [article])
        XCTAssertEqual(report.results[0].verdict, .fresh)
        XCTAssertEqual(report.results[0].stalenessScore, 0)
        XCTAssertEqual(report.grade, .A)
        XCTAssertTrue(report.insights.contains(.backlogFresh))
    }

    // MARK: - Aged Article

    func testAgedArticle() {
        let article = makeArticle(daysOld: 14)
        let report = makeDetector().analyze(articles: [article])
        XCTAssertTrue(report.results[0].reasons.contains(.aged))
        XCTAssertGreaterThan(report.results[0].stalenessScore, 0)
    }

    func testVeryOldArticleExpired() {
        let article = makeArticle(daysOld: 30)
        let report = makeDetector().analyze(articles: [article])
        // 30 days old: min(40, 15 + (30-7)*2.5) = 40, * 1.0 = 40 -> fading
        XCTAssertTrue(report.results[0].stalenessScore >= 30)
        XCTAssertTrue(report.results[0].verdict == .fading || report.results[0].verdict == .stale)
    }

    // MARK: - Supersession

    func testSupersededArticle() {
        let older = makeArticle(id: "old", daysOld: 5, keywords: ["swift", "ios", "update"])
        let newer = makeArticle(id: "new", daysOld: 1, keywords: ["swift", "ios", "update"])
        let report = makeDetector().analyze(articles: [older, newer])
        let olderResult = report.results.first { $0.articleId == "old" }!
        XCTAssertTrue(olderResult.reasons.contains(.superseded))
    }

    func testNoSupersessionDifferentKeywords() {
        let older = makeArticle(id: "old", daysOld: 5, keywords: ["swift", "ios"])
        let newer = makeArticle(id: "new", daysOld: 1, keywords: ["python", "machine-learning"])
        let report = makeDetector().analyze(articles: [older, newer])
        let olderResult = report.results.first { $0.articleId == "old" }!
        XCTAssertFalse(olderResult.reasons.contains(.superseded))
    }

    // MARK: - Event Expired

    func testEventExpired() {
        let pastEvent = fixedDate.addingTimeInterval(-86400) // yesterday
        let article = makeArticle(isTimeSensitive: true, eventDate: pastEvent)
        let report = makeDetector().analyze(articles: [article])
        XCTAssertTrue(report.results[0].reasons.contains(.eventExpired))
    }

    func testTimeSensitiveNoDateOld() {
        // Time-sensitive with no event date, 4 days old
        let article = makeArticle(daysOld: 4, isTimeSensitive: true)
        let report = makeDetector().analyze(articles: [article])
        XCTAssertTrue(report.results[0].reasons.contains(.eventExpired))
    }

    func testFutureEventNotExpired() {
        let futureEvent = fixedDate.addingTimeInterval(86400) // tomorrow
        let article = makeArticle(isTimeSensitive: true, eventDate: futureEvent)
        let report = makeDetector().analyze(articles: [article])
        XCTAssertFalse(report.results[0].reasons.contains(.eventExpired))
    }

    // MARK: - Topic Saturation

    func testTopicSaturation() {
        let articles = (0..<5).map { i in
            makeArticle(id: "art\(i)", daysOld: 2, keywords: ["ai", "gpt"])
        }
        let report = makeDetector().analyze(articles: articles)
        let saturated = report.results.filter { $0.reasons.contains(.topicSaturated) }
        XCTAssertEqual(saturated.count, 5)
    }

    // MARK: - Correction

    func testCorrectionIssued() {
        let article = makeArticle(hasCorrection: true)
        let report = makeDetector().analyze(articles: [article])
        XCTAssertTrue(report.results[0].reasons.contains(.correctionIssued))
        XCTAssertGreaterThanOrEqual(report.results[0].stalenessScore, 25)
    }

    // MARK: - Interest Decay

    func testInterestDecayed() {
        let article = makeArticle(topicInterest: 0.1)
        let report = makeDetector().analyze(articles: [article])
        XCTAssertTrue(report.results[0].reasons.contains(.interestDecayed))
    }

    func testHighInterestNoDecay() {
        let article = makeArticle(topicInterest: 0.8)
        let report = makeDetector().analyze(articles: [article])
        XCTAssertFalse(report.results[0].reasons.contains(.interestDecayed))
    }

    // MARK: - Insufficient Data

    func testInsufficientData() {
        let article = makeArticle(daysOld: 0.5, keywords: [])
        let report = makeDetector().analyze(articles: [article])
        XCTAssertTrue(report.results[0].reasons.contains(.insufficientData))
        XCTAssertEqual(report.results[0].stalenessScore, 0)
    }

    // MARK: - Risk Appetite

    func testCautiousLowersScores() {
        let article = makeArticle(daysOld: 14, hasCorrection: true)
        let balanced = makeDetector(appetite: .balanced).analyze(articles: [article])
        let cautious = makeDetector(appetite: .cautious).analyze(articles: [article])
        XCTAssertLessThan(cautious.results[0].stalenessScore, balanced.results[0].stalenessScore)
    }

    func testAggressiveRaisesScores() {
        let article = makeArticle(daysOld: 14, hasCorrection: true)
        let balanced = makeDetector(appetite: .balanced).analyze(articles: [article])
        let aggressive = makeDetector(appetite: .aggressive).analyze(articles: [article])
        XCTAssertGreaterThan(aggressive.results[0].stalenessScore, balanced.results[0].stalenessScore)
    }

    // MARK: - Grade Computation

    func testGradeF() {
        // 3+ expired articles
        let articles = (0..<4).map { i in
            makeArticle(id: "art\(i)", daysOld: 14, hasCorrection: true,
                       isTimeSensitive: true, eventDate: fixedDate.addingTimeInterval(-86400))
        }
        let report = makeDetector().analyze(articles: articles)
        XCTAssertEqual(report.grade, .F)
    }

    // MARK: - Archive Candidates

    func testArchiveCandidates() {
        let expired = makeArticle(id: "expired", daysOld: 14, hasCorrection: true,
                                  isTimeSensitive: true, eventDate: fixedDate.addingTimeInterval(-86400))
        let fresh = makeArticle(id: "fresh", daysOld: 1)
        let report = makeDetector().analyze(articles: [expired, fresh])
        XCTAssertTrue(report.archiveCandidateIds.contains("expired"))
        XCTAssertFalse(report.archiveCandidateIds.contains("fresh"))
    }

    // MARK: - Playbook

    func testPlaybookContainsArchiveExpired() {
        let article = makeArticle(daysOld: 14, hasCorrection: true,
                                  isTimeSensitive: true, eventDate: fixedDate.addingTimeInterval(-86400))
        let report = makeDetector().analyze(articles: [article])
        let labels = report.playbook.map(\.label)
        XCTAssertTrue(labels.contains("ARCHIVE_EXPIRED_ARTICLES"))
    }

    func testAggressiveTrimsP3() {
        let article = makeArticle(daysOld: 14, hasCorrection: true,
                                  isTimeSensitive: true, eventDate: fixedDate.addingTimeInterval(-86400))
        let report = makeDetector(appetite: .aggressive).analyze(articles: [article])
        let p3Actions = report.playbook.filter { $0.priority == 3 }
        XCTAssertTrue(p3Actions.isEmpty)
    }

    func testCautiousAddsBacklogReview() {
        let articles = (0..<4).map { i in
            makeArticle(id: "art\(i)", daysOld: 14, hasCorrection: true,
                       isTimeSensitive: true, eventDate: fixedDate.addingTimeInterval(-86400))
        }
        let report = makeDetector(appetite: .cautious).analyze(articles: articles)
        let labels = report.playbook.map(\.label)
        XCTAssertTrue(labels.contains("SCHEDULE_BACKLOG_REVIEW"))
    }

    // MARK: - Insights

    func testInsightsEventArticlesExpired() {
        let articles = (0..<3).map { i in
            makeArticle(id: "ev\(i)", isTimeSensitive: true,
                       eventDate: fixedDate.addingTimeInterval(-86400))
        }
        let report = makeDetector().analyze(articles: articles)
        XCTAssertTrue(report.insights.contains(.eventArticlesExpired))
    }

    func testInsightsCorrectionsPresent() {
        let article = makeArticle(hasCorrection: true)
        let report = makeDetector().analyze(articles: [article])
        XCTAssertTrue(report.insights.contains(.correctionsPresent))
    }

    // MARK: - Renderers

    func testRenderTextNotEmpty() {
        let article = makeArticle(daysOld: 10)
        let report = makeDetector().analyze(articles: [article])
        let text = report.renderText()
        XCTAssertTrue(text.contains("VERDICT:"))
        XCTAssertTrue(text.contains("Grade:"))
    }

    func testRenderMarkdownContainsSections() {
        let article = makeArticle(daysOld: 10)
        let report = makeDetector().analyze(articles: [article])
        let md = report.renderMarkdown()
        XCTAssertTrue(md.contains("## Summary"))
        XCTAssertTrue(md.contains("## Articles"))
        XCTAssertTrue(md.contains("## Insights"))
    }

    func testRenderJSONByteStable() {
        let article = makeArticle(daysOld: 10)
        let report = makeDetector().analyze(articles: [article])
        let json1 = report.renderJSON()
        let json2 = report.renderJSON()
        XCTAssertEqual(json1, json2)
    }

    // MARK: - Input Immutability

    func testInputNotMutated() {
        let articles = [
            makeArticle(id: "a1", daysOld: 10),
            makeArticle(id: "a2", daysOld: 1)
        ]
        let snapshot = articles.map(\.id)
        _ = makeDetector().analyze(articles: articles)
        XCTAssertEqual(articles.map(\.id), snapshot)
    }

    // MARK: - Determinism

    func testDeterministic() {
        let articles = [
            makeArticle(id: "a1", daysOld: 10, keywords: ["swift"]),
            makeArticle(id: "a2", daysOld: 3, keywords: ["python"]),
            makeArticle(id: "a3", daysOld: 1, keywords: ["swift", "ios"])
        ]
        let r1 = makeDetector().analyze(articles: articles)
        let r2 = makeDetector().analyze(articles: articles)
        XCTAssertEqual(r1.backlogScore, r2.backlogScore)
        XCTAssertEqual(r1.grade, r2.grade)
        XCTAssertEqual(r1.results.map(\.stalenessScore), r2.results.map(\.stalenessScore))
    }
}
