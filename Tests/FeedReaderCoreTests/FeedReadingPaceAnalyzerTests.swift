import XCTest
@testable import FeedReaderCore

final class FeedReadingPaceAnalyzerTests: XCTestCase {
    let fixedNow = Date(timeIntervalSince1970: 1_750_000_000) // ~June 2025

    func makeSession(_ id: String, feed: String = "BBC", topic: String = "tech",
                     words: Int = 500, seconds: Double = 120, daysAgo: Double = 0) -> PaceSession {
        PaceSession(articleId: id, feedName: feed, topic: topic, wordCount: words,
                    readingSeconds: seconds, readAt: fixedNow.addingTimeInterval(-daysAgo * 86400))
    }

    func makeAnalyzer() -> FeedReadingPaceAnalyzer {
        FeedReadingPaceAnalyzer(now: { self.fixedNow })
    }

    // MARK: - Basic

    func testEmptySessionsReturnsNil() {
        XCTAssertNil(makeAnalyzer().analyze(sessions: []))
    }

    func testInvalidSessionsFiltered() {
        let s = [makeSession("a", words: 0), makeSession("b", seconds: 0)]
        XCTAssertNil(makeAnalyzer().analyze(sessions: s))
    }

    func testSingleSession() {
        let s = [makeSession("a", words: 500, seconds: 120)]
        let r = makeAnalyzer().analyze(sessions: s)!
        XCTAssertEqual(r.totalSessions, 1)
        XCTAssertEqual(r.dominantPace, .normal)  // 250 WPM
        XCTAssertTrue(r.overallWPM > 200 && r.overallWPM < 300)
    }

    // MARK: - Pace Classification

    func testPaceClassification() {
        XCTAssertEqual(ReadingPace.classify(700), .skimming)
        XCTAssertEqual(ReadingPace.classify(400), .fast)
        XCTAssertEqual(ReadingPace.classify(250), .normal)
        XCTAssertEqual(ReadingPace.classify(150), .slow)
        XCTAssertEqual(ReadingPace.classify(80), .deepReading)
    }

    func testPaceComparable() {
        XCTAssertTrue(ReadingPace.deepReading < ReadingPace.normal)
        XCTAssertTrue(ReadingPace.normal < ReadingPace.skimming)
    }

    // MARK: - WPM Calculation

    func testWPMCalculation() {
        let s = PaceSession(articleId: "a", feedName: "f", topic: "t",
                            wordCount: 600, readingSeconds: 120, readAt: fixedNow)
        XCTAssertEqual(s.wpm, 300.0, accuracy: 0.1)
        XCTAssertEqual(s.pace, .normal)
    }

    func testZeroWordCountWPM() {
        let s = makeSession("a", words: 0, seconds: 60)
        XCTAssertEqual(s.wpm, 0)
    }

    // MARK: - Distribution

    func testDistributionCoversAllPaces() {
        let sessions = [
            makeSession("a", words: 500, seconds: 120),  // 250 WPM normal
            makeSession("b", words: 500, seconds: 50),   // 600 WPM skimming
        ]
        let r = makeAnalyzer().analyze(sessions: sessions)!
        for pace in ReadingPace.allCases {
            XCTAssertNotNil(r.paceDistribution[pace])
        }
        XCTAssertEqual(r.paceDistribution[.normal], 1)
        XCTAssertEqual(r.paceDistribution[.skimming], 1)
    }

    // MARK: - Anomaly Detection

    func testRushingLongContent() {
        // 1000 words in 60s = 1000 WPM, >500 WPM on >800 words
        let s = [makeSession("a", words: 1000, seconds: 60),
                 makeSession("b", words: 900, seconds: 50)]
        let r = makeAnalyzer().analyze(sessions: s)!
        XCTAssertTrue(r.anomalies.contains { $0.kind == .rushingLongContent })
    }

    func testDwellingShortContent() {
        // 100 words in 120s = 50 WPM, <150 words and <120 WPM
        let s = [makeSession("a", words: 100, seconds: 120),
                 makeSession("b", words: 500, seconds: 120)] // normal for average
        let r = makeAnalyzer().analyze(sessions: s)!
        XCTAssertTrue(r.anomalies.contains { $0.kind == .dwellingShortContent })
    }

    func testPaceSpike() {
        // Normal sessions + one very fast one
        var sessions = (0..<5).map { i in makeSession("n\(i)", words: 500, seconds: 120) }
        sessions.append(makeSession("fast", words: 500, seconds: 20)) // 1500 WPM
        let r = makeAnalyzer().analyze(sessions: sessions)!
        XCTAssertTrue(r.anomalies.contains { $0.kind == .paceSpike })
    }

    func testPaceDrop() {
        var sessions = (0..<5).map { i in makeSession("n\(i)", words: 500, seconds: 120) }
        sessions.append(makeSession("slow", words: 500, seconds: 2000)) // 15 WPM
        let r = makeAnalyzer().analyze(sessions: sessions)!
        XCTAssertTrue(r.anomalies.contains { $0.kind == .paceDrop })
    }

    func testFatiguePattern() {
        // 5 sessions with decreasing speed
        let sessions = (0..<5).map { i in
            makeSession("f\(i)", words: 500, seconds: Double(80 + i * 40), daysAgo: Double(4 - i))
        }
        let r = makeAnalyzer().analyze(sessions: sessions)!
        XCTAssertTrue(r.anomalies.contains { $0.kind == .fatiguePattern })
    }

    func testNoFatigueWhenStable() {
        let sessions = (0..<5).map { i in
            makeSession("s\(i)", words: 500, seconds: 120, daysAgo: Double(4 - i))
        }
        let r = makeAnalyzer().analyze(sessions: sessions)!
        XCTAssertFalse(r.anomalies.contains { $0.kind == .fatiguePattern })
    }

    // MARK: - Profiles

    func testTopicProfiles() {
        let sessions = [
            makeSession("a", topic: "tech", words: 500, seconds: 120),
            makeSession("b", topic: "tech", words: 600, seconds: 150),
            makeSession("c", topic: "sports", words: 400, seconds: 100),
            makeSession("d", topic: "sports", words: 300, seconds: 80),
        ]
        let r = makeAnalyzer().analyze(sessions: sessions)!
        XCTAssertEqual(r.topicProfiles.count, 2)
        XCTAssertTrue(r.topicProfiles.contains { $0.name == "tech" })
        XCTAssertTrue(r.topicProfiles.contains { $0.name == "sports" })
    }

    func testFeedProfiles() {
        let sessions = [
            makeSession("a", feed: "BBC", words: 500, seconds: 120),
            makeSession("b", feed: "BBC", words: 600, seconds: 150),
            makeSession("c", feed: "NPR", words: 400, seconds: 100),
            makeSession("d", feed: "NPR", words: 300, seconds: 80),
        ]
        let r = makeAnalyzer().analyze(sessions: sessions)!
        XCTAssertEqual(r.feedProfiles.count, 2)
    }

    func testProfileRequiresMinSessions() {
        let sessions = [
            makeSession("a", topic: "tech", words: 500, seconds: 120),
            makeSession("b", topic: "solo", words: 400, seconds: 100),
        ]
        let r = makeAnalyzer().analyze(sessions: sessions)!
        // "solo" only has 1 session, should not appear in profiles
        XCTAssertFalse(r.topicProfiles.contains { $0.name == "solo" })
    }

    // MARK: - Grading

    func testCleanSessionsGetGoodGrade() {
        let sessions = (0..<5).map { i in
            makeSession("g\(i)", words: 500, seconds: 120, daysAgo: Double(i))
        }
        let r = makeAnalyzer().analyze(sessions: sessions)!
        XCTAssertTrue(["A", "B"].contains(r.paceGrade))
    }

    func testManyAnomaliesGivePoorGrade() {
        var sessions = (0..<3).map { i in makeSession("n\(i)", words: 500, seconds: 120) }
        // Add many rushing-long-content anomalies
        sessions += (0..<5).map { i in makeSession("r\(i)", words: 1000, seconds: 30) }
        let r = makeAnalyzer().analyze(sessions: sessions)!
        XCTAssertTrue(["D", "F"].contains(r.paceGrade))
    }

    // MARK: - Recommendations

    func testHealthySessionsGetMaintainRec() {
        let sessions = (0..<3).map { i in
            makeSession("h\(i)", words: 500, seconds: 120, daysAgo: Double(i))
        }
        let r = makeAnalyzer().analyze(sessions: sessions)!
        XCTAssertTrue(r.recommendations.contains { $0.id == "maintain_pace" })
    }

    func testRushingTriggersSlowDownRec() {
        let sessions = (0..<3).map { i in
            makeSession("r\(i)", words: 1000, seconds: 40, daysAgo: Double(i))
        }
        let r = makeAnalyzer().analyze(sessions: sessions)!
        XCTAssertTrue(r.recommendations.contains { $0.id == "slow_down_long_articles" })
    }

    func testRecsSortedByPriority() {
        var sessions = (0..<3).map { i in makeSession("n\(i)", words: 500, seconds: 120) }
        sessions += (0..<3).map { i in makeSession("r\(i)", words: 1000, seconds: 40) }
        let r = makeAnalyzer().analyze(sessions: sessions)!
        for i in 1..<r.recommendations.count {
            XCTAssertTrue(r.recommendations[i-1].priority <= r.recommendations[i].priority)
        }
    }

    // MARK: - Estimates

    func testEstimateWithNoData() {
        let e = makeAnalyzer().estimateReadingTime(wordCount: 1000)
        XCTAssertEqual(e.source, "default")
        XCTAssertEqual(e.estimatedWPM, 238.0)
        XCTAssertTrue(e.estimatedMinutes > 0)
    }

    func testEstimateWithTopicData() {
        let sessions = [
            makeSession("a", topic: "tech", words: 600, seconds: 120),
            makeSession("b", topic: "tech", words: 400, seconds: 80),
        ]
        let e = makeAnalyzer().estimateReadingTime(wordCount: 1000, topic: "tech",
                                                    sessions: sessions)
        XCTAssertEqual(e.source, "topic")
        XCTAssertTrue(e.confidence >= 0.1)
    }

    func testEstimateWithFeedFallback() {
        let sessions = [
            makeSession("a", feed: "BBC", topic: "unknown1", words: 600, seconds: 120),
            makeSession("b", feed: "BBC", topic: "unknown2", words: 400, seconds: 80),
        ]
        let e = makeAnalyzer().estimateReadingTime(wordCount: 1000, topic: "other",
                                                    feedName: "BBC", sessions: sessions)
        XCTAssertEqual(e.source, "feed")
    }

    func testEstimateZeroWords() {
        let e = makeAnalyzer().estimateReadingTime(wordCount: 0)
        XCTAssertEqual(e.estimatedMinutes, 0)
    }

    // MARK: - Insights

    func testInsightsContainWPM() {
        let sessions = [makeSession("a", words: 500, seconds: 120)]
        let r = makeAnalyzer().analyze(sessions: sessions)!
        XCTAssertTrue(r.insights.contains { $0.hasPrefix("average_wpm_") })
    }

    func testInsightsContainDominantPace() {
        let sessions = [makeSession("a", words: 500, seconds: 120)]
        let r = makeAnalyzer().analyze(sessions: sessions)!
        XCTAssertTrue(r.insights.contains { $0.hasPrefix("dominant_pace_") })
    }

    func testLimitedDataInsight() {
        let sessions = [makeSession("a", words: 500, seconds: 120)]
        let r = makeAnalyzer().analyze(sessions: sessions)!
        XCTAssertTrue(r.insights.contains { $0.hasPrefix("limited_data_") })
    }

    // MARK: - Headline

    func testHeadlineFormat() {
        let sessions = [makeSession("a", words: 500, seconds: 120)]
        let r = makeAnalyzer().analyze(sessions: sessions)!
        XCTAssertTrue(r.headline.contains("Grade"))
        XCTAssertTrue(r.headline.contains("WPM"))
    }

    // MARK: - Anomaly Severity

    func testSeverityBands() {
        let low = PaceAnomaly(kind: .paceSpike, severityScore: 20, detail: "")
        XCTAssertEqual(low.severity, .low)
        let med = PaceAnomaly(kind: .paceSpike, severityScore: 50, detail: "")
        XCTAssertEqual(med.severity, .medium)
        let high = PaceAnomaly(kind: .paceSpike, severityScore: 80, detail: "")
        XCTAssertEqual(high.severity, .high)
    }

    func testSeverityScoreClamped() {
        let a = PaceAnomaly(kind: .paceSpike, severityScore: 150, detail: "")
        XCTAssertEqual(a.severityScore, 100)
        let b = PaceAnomaly(kind: .paceSpike, severityScore: -10, detail: "")
        XCTAssertEqual(b.severityScore, 0)
    }

    // MARK: - Determinism

    func testDeterministicOutput() {
        let sessions = (0..<10).map { i in
            makeSession("d\(i)", words: 500, seconds: 120, daysAgo: Double(i))
        }
        let r1 = makeAnalyzer().analyze(sessions: sessions)!
        let r2 = makeAnalyzer().analyze(sessions: sessions)!
        XCTAssertEqual(r1.overallWPM, r2.overallWPM)
        XCTAssertEqual(r1.paceGrade, r2.paceGrade)
        XCTAssertEqual(r1.totalSessions, r2.totalSessions)
    }
}
