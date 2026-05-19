//
//  FeedReadingFatigueAdvisorTests.swift
//  FeedReaderCoreTests
//
//  Tests for the FeedReadingFatigueAdvisor agentic advisor.
//

import XCTest
@testable import FeedReaderCore

final class FeedReadingFatigueAdvisorTests: XCTestCase {

    // MARK: - Helpers

    private let fixedNow: Date = {
        var comps = DateComponents()
        comps.year = 2026
        comps.month = 5
        comps.day = 18
        comps.hour = 22
        comps.minute = 0
        comps.timeZone = TimeZone(identifier: "UTC")
        let cal = Calendar(identifier: .gregorian)
        return cal.date(from: comps)!
    }()

    private func makeAdvisor(
        appetite: FatigueRiskAppetite = .balanced,
        lookback: Int = 14
    ) -> FeedReadingFatigueAdvisor {
        let advisor = FeedReadingFatigueAdvisor(now: { self.fixedNow })
        advisor.riskAppetite = appetite
        advisor.lookbackDays = lookback
        return advisor
    }

    private func daysAgo(_ d: Int, hour: Int = 12, minute: Int = 0) -> Date {
        let cal = Calendar(identifier: .gregorian)
        let base = cal.date(byAdding: .day, value: -d, to: fixedNow)!
        var comps = cal.dateComponents([.year, .month, .day], from: base)
        comps.hour = hour
        comps.minute = minute
        comps.second = 0
        return cal.date(from: comps) ?? base
    }

    private func session(
        _ id: String,
        offsetDays: Int,
        hour: Int = 12,
        articles: Int = 5,
        dwellSec: TimeInterval = 1200,
        scrolls: Int = 5,
        topics: [String] = ["tech"],
        feeds: [String] = ["https://a/feed"],
        sentiment: Double? = nil,
        interruptions: Int = 0
    ) -> ReadingSession {
        ReadingSession(
            id: id,
            startedAt: daysAgo(offsetDays, hour: hour),
            articleCount: articles,
            totalDwellSeconds: dwellSec,
            scrollEventCount: scrolls,
            topicsRead: topics,
            feedsRead: feeds,
            sentimentScore: sentiment,
            interruptionCount: interruptions
        )
    }

    // MARK: - Tests

    func testEmptySessionsProducesFreshVerdict() {
        let advisor = makeAdvisor()
        let report = advisor.analyze(sessions: [])
        XCTAssertEqual(report.verdict, .fresh)
        XCTAssertEqual(report.grade, "A")
        XCTAssertFalse(report.summaryHeadline.isEmpty)
        XCTAssertTrue(report.findings.isEmpty)
        XCTAssertFalse(report.playbook.isEmpty, "Should include P3 celebrateProgress fallback")
        XCTAssertTrue(report.insights.contains("HEALTHY_READING_PATTERN"))
        XCTAssertTrue(report.playbook.contains { $0.action == .celebrateProgress })
    }

    func testLookbackFilterDropsOldSessions() {
        let advisor = makeAdvisor(lookback: 7)
        // 30 days ago should be ignored.
        let old = session("old", offsetDays: 30, articles: 50, dwellSec: 6000, scrolls: 500)
        let report = advisor.analyze(sessions: [old])
        XCTAssertEqual(report.verdict, .fresh)
        XCTAssertTrue(report.findings.isEmpty)
    }

    func testSessionOverloadFiresP0() {
        let advisor = makeAdvisor()
        // 5 long sessions in a single day -> overload.
        var sessions: [ReadingSession] = []
        for i in 0..<5 {
            sessions.append(session("o\(i)", offsetDays: 1, hour: 8 + i, articles: 10, dwellSec: 1800))
        }
        let report = advisor.analyze(sessions: sessions)
        XCTAssertTrue(report.findings.contains { $0.signal == .sessionOverload })
        let overload = report.findings.first { $0.signal == .sessionOverload }!
        XCTAssertEqual(overload.priority, .p0)
    }

    func testDwellCollapseDetected() {
        let advisor = makeAdvisor()
        var sessions: [ReadingSession] = []
        // Baseline 6 sessions with long dwell (300s/article).
        for i in 0..<6 {
            sessions.append(session("b\(i)", offsetDays: 12 - i, articles: 5, dwellSec: 1500, scrolls: 5))
        }
        // Recent 6 sessions with much shorter dwell (60s/article).
        for i in 0..<6 {
            sessions.append(session("r\(i)", offsetDays: 6 - i, articles: 5, dwellSec: 300, scrolls: 5))
        }
        let report = advisor.analyze(sessions: sessions)
        XCTAssertTrue(report.findings.contains { $0.signal == .dwellCollapse })
    }

    func testSkimDominanceFires() {
        let advisor = makeAdvisor()
        var sessions: [ReadingSession] = []
        for i in 0..<3 {
            sessions.append(session("s\(i)", offsetDays: i + 1, articles: 10, dwellSec: 600, scrolls: 200))
        }
        let report = advisor.analyze(sessions: sessions)
        XCTAssertTrue(report.findings.contains { $0.signal == .skimDominance })
    }

    func testTopicMonocultureLowEntropy() {
        let advisor = makeAdvisor()
        var sessions: [ReadingSession] = []
        for i in 0..<3 {
            sessions.append(session(
                "t\(i)", offsetDays: i + 1,
                articles: 5, dwellSec: 1500, scrolls: 5,
                topics: ["politics", "politics", "politics", "politics", "politics", "politics", "politics", "politics", "politics", "tech"]
            ))
        }
        let report = advisor.analyze(sessions: sessions)
        XCTAssertTrue(report.findings.contains { $0.signal == .topicMonoculture })
    }

    func testNegativeSentimentSpike() {
        let advisor = makeAdvisor()
        var sessions: [ReadingSession] = []
        for i in 0..<5 {
            sessions.append(session(
                "n\(i)", offsetDays: i + 1,
                articles: 5, dwellSec: 1500, scrolls: 5,
                sentiment: -0.7
            ))
        }
        let report = advisor.analyze(sessions: sessions)
        XCTAssertTrue(report.findings.contains { $0.signal == .negativeSentimentSpike })
    }

    func testLateNightBingeingDetectedWithFixedClock() {
        let advisor = makeAdvisor()
        var sessions: [ReadingSession] = []
        // 4 sessions starting at 1am over the last week
        for i in 0..<4 {
            sessions.append(session("late\(i)", offsetDays: i + 1, hour: 1, articles: 5, dwellSec: 900))
        }
        let report = advisor.analyze(sessions: sessions)
        XCTAssertTrue(report.findings.contains { $0.signal == .lateNightBingeing })
    }

    func testSourceMonoculture() {
        let advisor = makeAdvisor()
        var sessions: [ReadingSession] = []
        // Most articles from one feed.
        for i in 0..<3 {
            sessions.append(session(
                "src\(i)", offsetDays: i + 1,
                articles: 5, dwellSec: 1500, scrolls: 5,
                feeds: Array(repeating: "https://dominant/feed", count: 5)
            ))
        }
        // One session with a different feed.
        sessions.append(session(
            "alt", offsetDays: 5, articles: 1, dwellSec: 600,
            feeds: ["https://other/feed"]
        ))
        let report = advisor.analyze(sessions: sessions)
        XCTAssertTrue(report.findings.contains { $0.signal == .sourceMonoculture })
    }

    func testRiskAppetiteMonotonicity() {
        let buildSessions: () -> [ReadingSession] = {
            var s: [ReadingSession] = []
            for i in 0..<4 {
                s.append(self.session("a\(i)", offsetDays: 1, hour: 8 + i, articles: 10, dwellSec: 1800))
            }
            for i in 0..<5 {
                s.append(self.session("n\(i)", offsetDays: i + 1, articles: 5, dwellSec: 1500, sentiment: -0.6))
            }
            return s
        }
        let cautious = makeAdvisor(appetite: .cautious).analyze(sessions: buildSessions())
        let balanced = makeAdvisor(appetite: .balanced).analyze(sessions: buildSessions())
        let aggressive = makeAdvisor(appetite: .aggressive).analyze(sessions: buildSessions())
        XCTAssertGreaterThanOrEqual(cautious.fatigueScore, balanced.fatigueScore - 0.0001)
        XCTAssertGreaterThanOrEqual(balanced.fatigueScore, aggressive.fatigueScore - 0.0001)
    }

    func testBurnoutComboForcesGradeF() {
        let advisor = makeAdvisor()
        var sessions: [ReadingSession] = []
        // Session overload.
        for i in 0..<5 {
            sessions.append(session("o\(i)", offsetDays: 1, hour: 8 + i, articles: 10, dwellSec: 1800, sentiment: -0.7))
        }
        // Sentiment spike across more days.
        for i in 0..<4 {
            sessions.append(session("s\(i)", offsetDays: i + 2, articles: 5, dwellSec: 1500, sentiment: -0.8))
        }
        let report = advisor.analyze(sessions: sessions)
        XCTAssertEqual(report.verdict, .burnout)
        XCTAssertEqual(report.grade, "F")
        XCTAssertTrue(report.insights.contains { $0.contains("BURNOUT_COMBO") })
    }

    func testPlaybookDedupAndP0First() {
        let advisor = makeAdvisor()
        var sessions: [ReadingSession] = []
        for i in 0..<5 {
            sessions.append(session("o\(i)", offsetDays: 1, hour: 8 + i, articles: 10, dwellSec: 1800))
        }
        let report = advisor.analyze(sessions: sessions)
        // No duplicate ids.
        let ids = report.playbook.map { $0.id }
        XCTAssertEqual(ids.count, Set(ids).count)
        // P0-first: any P0 must come before any P1+.
        var seenLower = false
        for item in report.playbook {
            if item.priority != .p0 { seenLower = true }
            else if seenLower {
                XCTFail("P0 item appeared after a lower-priority item")
            }
        }
    }

    func testJSONByteStableAcrossCalls() throws {
        let advisor = makeAdvisor()
        var sessions: [ReadingSession] = []
        for i in 0..<4 {
            sessions.append(session("o\(i)", offsetDays: 1, hour: 8 + i, articles: 10, dwellSec: 1800))
        }
        let report1 = advisor.analyze(sessions: sessions)
        let report2 = advisor.analyze(sessions: sessions)
        let json1 = try report1.renderJSON()
        let json2 = try report2.renderJSON()
        XCTAssertEqual(json1, json2)
        XCTAssertFalse(json1.isEmpty)
    }

    func testMarkdownContainsRequiredSections() {
        let advisor = makeAdvisor()
        let report = advisor.analyze(sessions: [])
        let md = report.renderMarkdown()
        XCTAssertTrue(md.contains("## Summary"))
        XCTAssertTrue(md.contains("## Findings"))
        XCTAssertTrue(md.contains("## Playbook"))
        XCTAssertTrue(md.contains("## Insights"))
    }

    func testInputsAreNotMutated() {
        let advisor = makeAdvisor()
        let original = [
            session("o0", offsetDays: 1, hour: 8, articles: 10, dwellSec: 1800),
            session("o1", offsetDays: 2, hour: 9, articles: 8, dwellSec: 900)
        ]
        let snapshot = original
        _ = advisor.analyze(sessions: original)
        XCTAssertEqual(original, snapshot)
    }

    func testDeterminismSameInputsSameOutput() throws {
        let advisor1 = makeAdvisor()
        let advisor2 = makeAdvisor()
        var sessions: [ReadingSession] = []
        for i in 0..<3 {
            sessions.append(session(
                "d\(i)", offsetDays: i + 1,
                articles: 5, dwellSec: 1500,
                topics: ["a", "b", "a"],
                feeds: ["https://x/feed"],
                sentiment: -0.5
            ))
        }
        let r1 = advisor1.analyze(sessions: sessions)
        let r2 = advisor2.analyze(sessions: sessions)
        XCTAssertEqual(r1.verdict, r2.verdict)
        XCTAssertEqual(r1.grade, r2.grade)
        XCTAssertEqual(r1.fatigueScore, r2.fatigueScore, accuracy: 0.0001)
        XCTAssertEqual(try r1.renderJSON(), try r2.renderJSON())
    }

    func testEnumDescriptionsAndEmojisNonEmpty() {
        for v in FatigueVerdict.allCases {
            XCTAssertFalse(v.emoji.isEmpty)
            XCTAssertFalse(v.description.isEmpty)
        }
        for s in FatigueSignal.allCases {
            XCTAssertFalse(s.emoji.isEmpty)
            XCTAssertFalse(s.description.isEmpty)
            XCTAssertGreaterThan(s.baseSeverity, 0)
            XCTAssertLessThanOrEqual(s.baseSeverity, 1)
        }
        for a in FatigueAction.allCases {
            XCTAssertFalse(a.emoji.isEmpty)
            XCTAssertFalse(a.description.isEmpty)
        }
    }

    func testCautiousAppendsAuditOnPoorGrade() {
        let advisor = makeAdvisor(appetite: .cautious)
        var sessions: [ReadingSession] = []
        for i in 0..<5 {
            sessions.append(session("o\(i)", offsetDays: 1, hour: 8 + i, articles: 10, dwellSec: 1800))
        }
        let report = advisor.analyze(sessions: sessions)
        if report.grade == "C" || report.grade == "D" || report.grade == "F" {
            XCTAssertTrue(report.playbook.contains { $0.action == .scheduleReadingAudit })
        }
    }

    func testVerdictComparable() {
        XCTAssertTrue(FatigueVerdict.fresh < FatigueVerdict.engaged)
        XCTAssertTrue(FatigueVerdict.engaged < FatigueVerdict.mildFatigue)
        XCTAssertTrue(FatigueVerdict.mildFatigue < FatigueVerdict.heavyFatigue)
        XCTAssertTrue(FatigueVerdict.heavyFatigue < FatigueVerdict.burnout)
    }
}
