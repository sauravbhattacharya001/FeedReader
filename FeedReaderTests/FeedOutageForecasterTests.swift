//
//  FeedOutageForecasterTests.swift
//  FeedReaderTests
//

import XCTest
@testable import FeedReaderCore

final class FeedOutageForecasterTests: XCTestCase {

    private let fixedDate = ISO8601DateFormatter().date(from: "2026-06-02T22:00:00Z")!

    private func makeForecaster(appetite: OutageRiskAppetite = .balanced) -> FeedOutageForecaster {
        let f = FeedOutageForecaster(now: { [fixedDate] in fixedDate })
        f.riskAppetite = appetite
        return f
    }

    private func makeAttempts(count: Int, allSuccess: Bool = true, latencyMs: Double = 200, size: Int = 5000) -> [FetchAttempt] {
        (0..<count).map { i in
            FetchAttempt(
                timestamp: fixedDate.addingTimeInterval(Double(-count + i) * 3600),
                statusCode: allSuccess ? 200 : (i >= count / 2 ? 500 : 200),
                latencyMs: latencyMs,
                responseSizeBytes: allSuccess ? size : (i >= count / 2 ? 0 : size),
                succeeded: allSuccess ? true : (i < count / 2)
            )
        }
    }

    // MARK: - Tests

    func testEmptyInput() {
        let report = makeForecaster().analyze(feeds: [])
        XCTAssertEqual(report.forecasts.count, 0)
        XCTAssertEqual(report.portfolioRisk, 0)
        XCTAssertEqual(report.grade, .A)
        XCTAssertFalse(report.insights.isEmpty)
    }

    func testInsufficientData() {
        let feed = FeedTelemetry(feedName: "Short", feedURL: "https://example.com/rss", attempts: [
            FetchAttempt(timestamp: fixedDate, statusCode: 200, latencyMs: 100, responseSizeBytes: 1000, succeeded: true)
        ])
        let report = makeForecaster().analyze(feeds: [feed])
        XCTAssertEqual(report.forecasts[0].reasons, [.insufficientData])
        XCTAssertEqual(report.forecasts[0].verdict, .stable)
    }

    func testHealthyFeed() {
        let feed = FeedTelemetry(feedName: "Healthy", feedURL: "https://healthy.com/rss",
                                 attempts: makeAttempts(count: 20, allSuccess: true))
        let report = makeForecaster().analyze(feeds: [feed])
        XCTAssertEqual(report.forecasts[0].verdict, .stable)
        XCTAssertEqual(report.grade, .A)
    }

    func testRisingErrorRate() {
        // Older half succeeds, recent half fails
        let attempts = makeAttempts(count: 20, allSuccess: false)
        let feed = FeedTelemetry(feedName: "Failing", feedURL: "https://failing.com/rss", attempts: attempts)
        let report = makeForecaster().analyze(feeds: [feed])
        XCTAssertTrue(report.forecasts[0].reasons.contains(.errorRateRising))
        XCTAssertTrue(report.forecasts[0].outageRisk > 30)
    }

    func testLatencyDegradation() {
        var attempts: [FetchAttempt] = []
        for i in 0..<20 {
            let latency = i < 10 ? 200.0 : 800.0  // 4x increase
            attempts.append(FetchAttempt(
                timestamp: fixedDate.addingTimeInterval(Double(-20 + i) * 3600),
                statusCode: 200, latencyMs: latency, responseSizeBytes: 5000, succeeded: true
            ))
        }
        let feed = FeedTelemetry(feedName: "Slow", feedURL: "https://slow.com/rss", attempts: attempts)
        let report = makeForecaster().analyze(feeds: [feed])
        XCTAssertTrue(report.forecasts[0].reasons.contains(.latencyDegrading))
    }

    func testCertificateExpiringSoon() {
        let certExpiry = fixedDate.addingTimeInterval(3 * 86400)  // 3 days
        var attempts = makeAttempts(count: 10, allSuccess: true)
        attempts[attempts.count - 1] = FetchAttempt(
            timestamp: attempts.last!.timestamp,
            statusCode: 200, latencyMs: 200, responseSizeBytes: 5000,
            succeeded: true, certExpiryDate: certExpiry
        )
        let feed = FeedTelemetry(feedName: "CertFeed", feedURL: "https://cert.com/rss", attempts: attempts)
        let report = makeForecaster().analyze(feeds: [feed])
        XCTAssertTrue(report.forecasts[0].reasons.contains(.certificateExpiring))
    }

    func testConsecutiveSoftErrors() {
        var attempts = makeAttempts(count: 10, allSuccess: true)
        // Last 5 fail
        for i in 5..<10 {
            attempts[i] = FetchAttempt(
                timestamp: attempts[i].timestamp,
                statusCode: 503, latencyMs: 200, responseSizeBytes: 0, succeeded: false
            )
        }
        let feed = FeedTelemetry(feedName: "Soft", feedURL: "https://soft.com/rss", attempts: attempts)
        let report = makeForecaster().analyze(feeds: [feed])
        XCTAssertTrue(report.forecasts[0].reasons.contains(.consecutiveSoftErrors))
    }

    func testCriticalFeedBumpsRisk() {
        let attempts = makeAttempts(count: 20, allSuccess: false)
        let normal = FeedTelemetry(feedName: "Normal", feedURL: "https://a.com/rss", attempts: attempts, isCritical: false)
        let critical = FeedTelemetry(feedName: "Critical", feedURL: "https://b.com/rss", attempts: attempts, isCritical: true)

        let forecaster = makeForecaster()
        let r1 = forecaster.analyze(feeds: [normal]).forecasts[0].outageRisk
        let r2 = forecaster.analyze(feeds: [critical]).forecasts[0].outageRisk
        XCTAssertGreaterThan(r2, r1)
    }

    func testCautiousRaisesRisk() {
        let attempts = makeAttempts(count: 20, allSuccess: false)
        let feed = FeedTelemetry(feedName: "Test", feedURL: "https://t.com/rss", attempts: attempts)

        let cautious = makeForecaster(appetite: .cautious).analyze(feeds: [feed]).forecasts[0].outageRisk
        let balanced = makeForecaster(appetite: .balanced).analyze(feeds: [feed]).forecasts[0].outageRisk
        let aggressive = makeForecaster(appetite: .aggressive).analyze(feeds: [feed]).forecasts[0].outageRisk

        XCTAssertGreaterThanOrEqual(cautious, balanced)
        XCTAssertGreaterThanOrEqual(balanced, aggressive)
    }

    func testPlaybookP0ForImminent() {
        // Build a feed with very high risk
        var attempts: [FetchAttempt] = []
        for i in 0..<20 {
            let succeed = i < 5
            attempts.append(FetchAttempt(
                timestamp: fixedDate.addingTimeInterval(Double(-20 + i) * 3600),
                statusCode: succeed ? 200 : 503,
                latencyMs: succeed ? 200 : 5000,
                responseSizeBytes: succeed ? 5000 : 0,
                succeeded: succeed
            ))
        }
        let feed = FeedTelemetry(feedName: "Dying", feedURL: "https://dying.com/rss", attempts: attempts, isCritical: true)
        let report = makeForecaster().analyze(feeds: [feed])
        XCTAssertTrue(report.playbook.contains { $0.priority == .p0 })
    }

    func testGradeFWhenCriticalP0() {
        var attempts: [FetchAttempt] = []
        for i in 0..<20 {
            let succeed = i < 3
            attempts.append(FetchAttempt(
                timestamp: fixedDate.addingTimeInterval(Double(-20 + i) * 3600),
                statusCode: succeed ? 200 : 500,
                latencyMs: succeed ? 100 : 8000,
                responseSizeBytes: succeed ? 5000 : 0,
                succeeded: succeed
            ))
        }
        let feed = FeedTelemetry(feedName: "Dead", feedURL: "https://dead.com/rss", attempts: attempts, isCritical: true)
        let report = makeForecaster().analyze(feeds: [feed])
        XCTAssertEqual(report.grade, .F)
    }

    func testMarkdownContainsSections() {
        let feed = FeedTelemetry(feedName: "Test", feedURL: "https://t.com/rss",
                                 attempts: makeAttempts(count: 10))
        let report = makeForecaster().analyze(feeds: [feed])
        let md = report.renderMarkdown()
        XCTAssertTrue(md.contains("## Summary"))
        XCTAssertTrue(md.contains("## Feeds"))
        XCTAssertTrue(md.contains("## Playbook"))
        XCTAssertTrue(md.contains("## Insights"))
    }

    func testJSONContainsRequiredKeys() {
        let feed = FeedTelemetry(feedName: "Test", feedURL: "https://t.com/rss",
                                 attempts: makeAttempts(count: 10))
        let report = makeForecaster().analyze(feeds: [feed])
        let json = report.renderJSON()
        XCTAssertTrue(json.contains("\"grade\""))
        XCTAssertTrue(json.contains("\"portfolioRisk\""))
        XCTAssertTrue(json.contains("\"forecasts\""))
        XCTAssertTrue(json.contains("\"playbook\""))
        XCTAssertTrue(json.contains("\"insights\""))
    }

    func testJSONByteStability() {
        let feed = FeedTelemetry(feedName: "Stable", feedURL: "https://stable.com/rss",
                                 attempts: makeAttempts(count: 10))
        let forecaster = makeForecaster()
        let json1 = forecaster.analyze(feeds: [feed]).renderJSON()
        let json2 = forecaster.analyze(feeds: [feed]).renderJSON()
        XCTAssertEqual(json1, json2)
    }

    func testTextHeadline() {
        let feed = FeedTelemetry(feedName: "H", feedURL: "https://h.com/rss",
                                 attempts: makeAttempts(count: 10))
        let report = makeForecaster().analyze(feeds: [feed])
        XCTAssertTrue(report.headline.hasPrefix("VERDICT:"))
    }

    func testAggressiveTrimsP3() {
        var attempts: [FetchAttempt] = []
        for i in 0..<20 {
            let succeed = i < 3
            attempts.append(FetchAttempt(
                timestamp: fixedDate.addingTimeInterval(Double(-20 + i) * 3600),
                statusCode: succeed ? 200 : 500,
                latencyMs: succeed ? 100 : 5000,
                responseSizeBytes: succeed ? 5000 : 0,
                succeeded: succeed
            ))
        }
        let feed = FeedTelemetry(feedName: "Bad", feedURL: "https://bad.com/rss", attempts: attempts, isCritical: true)
        let report = makeForecaster(appetite: .aggressive).analyze(feeds: [feed])
        XCTAssertFalse(report.playbook.contains { $0.priority == .p3 })
    }

    func testInputImmutability() {
        let attempts = makeAttempts(count: 10)
        let feed = FeedTelemetry(feedName: "Immut", feedURL: "https://immut.com/rss", attempts: attempts)
        let feeds = [feed]
        let countBefore = feeds[0].attempts.count
        _ = makeForecaster().analyze(feeds: feeds)
        XCTAssertEqual(feeds[0].attempts.count, countBefore)
    }
}
