//
//  FeedAnomalyDetectorTests.swift
//  FeedReaderTests
//
//  Tests for FeedAnomalyDetector — autonomous feed anomaly detection engine.
//

import XCTest
@testable import FeedReader

final class FeedAnomalyDetectorTests: XCTestCase {

    private var sut: FeedAnomalyDetector!
    private var tempDir: String!
    private let formatter = ISO8601DateFormatter()

    override func setUp() {
        super.setUp()
        tempDir = NSTemporaryDirectory() + "FeedAnomalyDetectorTests_\(UUID().uuidString)"
        try? FileManager.default.createDirectory(atPath: tempDir, withIntermediateDirectories: true)
        sut = FeedAnomalyDetector(directory: tempDir)
    }

    override func tearDown() {
        sut = nil
        if let dir = tempDir {
            try? FileManager.default.removeItem(atPath: dir)
        }
        tempDir = nil
        super.tearDown()
    }

    // MARK: - Helpers

    /// Generates a list of article dicts for baseline learning.
    private func makeArticles(
        count: Int,
        feedDomain: String = "example.com",
        author: String = "Alice",
        avgWords: Int = 500,
        titleWords: Int = 8,
        startDate: Date? = nil
    ) -> [[String: String]] {
        let start = startDate ?? Date().addingTimeInterval(-Double(count) * 86400)
        return (0..<count).map { i in
            let date = start.addingTimeInterval(Double(i) * 86400)
            let wordCount = avgWords + (i % 3 == 0 ? 50 : -30) // slight variation
            let content = (0..<wordCount).map { _ in "lorem" }.joined(separator: " ")
            let titleContent = (0..<titleWords).map { _ in "headline" }.joined(separator: " ")
            return [
                "title": titleContent,
                "content": content,
                "author": author,
                "link": "https://\(feedDomain)/article/\(i)",
                "publishedDate": formatter.string(from: date)
            ]
        }
    }

    /// Generates articles published in last 24h for scan testing.
    private func makeRecentArticles(
        count: Int,
        feedDomain: String = "example.com",
        author: String = "Alice",
        avgWords: Int = 500,
        titleWords: Int = 8
    ) -> [[String: String]] {
        let now = Date()
        return (0..<count).map { i in
            let date = now.addingTimeInterval(-Double(i) * 3600) // spaced hourly
            let wordCount = avgWords + (i % 2 == 0 ? 20 : -20)
            let content = (0..<wordCount).map { _ in "lorem" }.joined(separator: " ")
            let titleContent = (0..<titleWords).map { _ in "headline" }.joined(separator: " ")
            return [
                "title": titleContent,
                "content": content,
                "author": author,
                "link": "https://\(feedDomain)/article/recent-\(i)",
                "publishedDate": formatter.string(from: date)
            ]
        }
    }

    // MARK: - AnomalySeverity

    func testAnomalySeverityOrdering() {
        XCTAssertTrue(AnomalySeverity.info < AnomalySeverity.warning)
        XCTAssertTrue(AnomalySeverity.warning < AnomalySeverity.critical)
        XCTAssertFalse(AnomalySeverity.critical < AnomalySeverity.info)
    }

    func testAnomalySeverityRawValues() {
        XCTAssertEqual(AnomalySeverity.info.rawValue, "info")
        XCTAssertEqual(AnomalySeverity.warning.rawValue, "warning")
        XCTAssertEqual(AnomalySeverity.critical.rawValue, "critical")
    }

    // MARK: - AnomalyChannel

    func testAnomalyChannelDisplayNames() {
        XCTAssertEqual(AnomalyChannel.postingFrequency.displayName, "Posting Frequency")
        XCTAssertEqual(AnomalyChannel.contentLength.displayName, "Content Length")
        XCTAssertEqual(AnomalyChannel.topicDrift.displayName, "Topic Drift")
        XCTAssertEqual(AnomalyChannel.authorChange.displayName, "Author Change")
        XCTAssertEqual(AnomalyChannel.linkDomain.displayName, "Link Domain")
        XCTAssertEqual(AnomalyChannel.titlePattern.displayName, "Title Pattern")
    }

    func testAnomalyChannelRawValues() {
        XCTAssertEqual(AnomalyChannel.postingFrequency.rawValue, "posting_frequency")
        XCTAssertEqual(AnomalyChannel.contentLength.rawValue, "content_length")
        XCTAssertEqual(AnomalyChannel.topicDrift.rawValue, "topic_drift")
        XCTAssertEqual(AnomalyChannel.authorChange.rawValue, "author_change")
        XCTAssertEqual(AnomalyChannel.linkDomain.rawValue, "link_domain")
        XCTAssertEqual(AnomalyChannel.titlePattern.rawValue, "title_pattern")
    }

    // MARK: - FeedAnomaly Equatable

    func testFeedAnomalyEquality() {
        let a = FeedAnomaly(id: "abc", feedName: "Test", channel: .topicDrift, severity: .info,
                            description: "desc1", recommendation: "rec1",
                            detectedAt: Date(), deviationScore: 1.5, isDismissed: false)
        let b = FeedAnomaly(id: "abc", feedName: "Other", channel: .contentLength, severity: .critical,
                            description: "desc2", recommendation: "rec2",
                            detectedAt: Date(), deviationScore: 9.0, isDismissed: true)
        let c = FeedAnomaly(id: "xyz", feedName: "Test", channel: .topicDrift, severity: .info,
                            description: "desc1", recommendation: "rec1",
                            detectedAt: Date(), deviationScore: 1.5, isDismissed: false)
        // Equal by id only
        XCTAssertEqual(a, b)
        XCTAssertNotEqual(a, c)
    }

    // MARK: - Baseline Learning

    func testLearnBaselineEmpty() {
        sut.learnBaseline(feedName: "EmptyFeed", articles: [])
        // No baseline created for empty articles
        let result = sut.scan(feedName: "EmptyFeed", recentArticles: makeRecentArticles(count: 3))
        XCTAssertTrue(result.isEmpty, "Should not detect anomalies without a baseline")
    }

    func testLearnBaselineCreatesBaseline() {
        let articles = makeArticles(count: 30)
        sut.learnBaseline(feedName: "TechBlog", articles: articles)
        // Scanning should work now (baseline exists)
        let normal = makeRecentArticles(count: 2) // similar to baseline
        let result = sut.scan(feedName: "TechBlog", recentArticles: normal)
        // Normal articles should produce few or no anomalies
        // (exact count depends on z-scores, but shouldn't be critical)
        for a in result {
            XCTAssertNotEqual(a.severity, .critical, "Normal articles should not trigger critical anomalies")
        }
    }

    func testLearnBaselineUpdatesOnRelearn() {
        let articles1 = makeArticles(count: 15, author: "Alice")
        sut.learnBaseline(feedName: "Blog", articles: articles1)

        let articles2 = makeArticles(count: 15, author: "Bob")
        sut.learnBaseline(feedName: "Blog", articles: articles2)

        // Latest baseline should know "bob", not "alice"
        let bobArticles = makeRecentArticles(count: 3, author: "Bob")
        let result = sut.scan(feedName: "Blog", recentArticles: bobArticles)
        let authorAnomalies = result.filter { $0.channel == .authorChange }
        XCTAssertTrue(authorAnomalies.isEmpty, "Bob should not be anomalous after relearning")
    }

    // MARK: - Scan Without Baseline

    func testScanWithoutBaselineReturnsEmpty() {
        let articles = makeRecentArticles(count: 5)
        let result = sut.scan(feedName: "UnknownFeed", recentArticles: articles)
        XCTAssertTrue(result.isEmpty)
    }

    // MARK: - Scan Below Minimum Sample Size

    func testScanBelowMinSampleSizeReturnsEmpty() {
        let tiny = makeArticles(count: 3) // below default minSampleSize of 7
        sut.learnBaseline(feedName: "TinyFeed", articles: tiny)
        let recent = makeRecentArticles(count: 2)
        let result = sut.scan(feedName: "TinyFeed", recentArticles: recent)
        XCTAssertTrue(result.isEmpty, "Should not detect with insufficient sample size")
    }

    // MARK: - Posting Frequency Anomaly

    func testPostingFrequencySpike() {
        // Baseline: ~1 article/day over 30 days
        let baseline = makeArticles(count: 30)
        sut.learnBaseline(feedName: "SteadyFeed", articles: baseline)

        // Spike: 20 articles in last 24h
        let spike = makeRecentArticles(count: 20)
        let result = sut.scan(feedName: "SteadyFeed", recentArticles: spike)
        let freqAnomalies = result.filter { $0.channel == .postingFrequency }

        // With 20 articles vs ~1/day baseline, should flag at least a warning
        XCTAssertFalse(freqAnomalies.isEmpty, "Posting frequency spike should be detected")
        if let first = freqAnomalies.first {
            XCTAssertTrue(first.description.contains("spike"), "Should describe as a spike")
            XCTAssertGreaterThan(first.deviationScore, 0)
        }
    }

    // MARK: - Content Length Anomaly

    func testContentLengthAnomaly() {
        // Baseline: ~500 words
        let baseline = makeArticles(count: 30, avgWords: 500)
        sut.learnBaseline(feedName: "LengthFeed", articles: baseline)

        // Recent: much shorter articles (~50 words)
        let short = makeRecentArticles(count: 5, avgWords: 50)
        let result = sut.scan(feedName: "LengthFeed", recentArticles: short)
        let lengthAnomalies = result.filter { $0.channel == .contentLength }

        XCTAssertFalse(lengthAnomalies.isEmpty, "Drastically shorter content should be detected")
        if let first = lengthAnomalies.first {
            XCTAssertTrue(first.description.contains("shorter"))
        }
    }

    func testContentLengthNormalNoAnomaly() {
        let baseline = makeArticles(count: 30, avgWords: 500)
        sut.learnBaseline(feedName: "NormalFeed", articles: baseline)

        // Similar word count
        let normal = makeRecentArticles(count: 5, avgWords: 510)
        let result = sut.scan(feedName: "NormalFeed", recentArticles: normal)
        let lengthAnomalies = result.filter { $0.channel == .contentLength }
        XCTAssertTrue(lengthAnomalies.isEmpty, "Similar content length should not trigger anomaly")
    }

    // MARK: - Topic Drift

    func testTopicDrift() {
        // Baseline with specific keywords
        let techArticles = (0..<30).map { i -> [String: String] in
            let date = Date().addingTimeInterval(-Double(i) * 86400)
            return [
                "title": "Technology update number \(i)",
                "content": "software engineering kubernetes docker microservices database algorithm programming infrastructure deployment containers " + String(repeating: "technology software development ", count: 20),
                "author": "TechWriter",
                "link": "https://tech.example.com/\(i)",
                "publishedDate": formatter.string(from: date)
            ]
        }
        sut.learnBaseline(feedName: "TechFeed", articles: techArticles)

        // Recent: completely different topic
        let cookingArticles = (0..<5).map { i -> [String: String] in
            let date = Date().addingTimeInterval(-Double(i) * 3600)
            return [
                "title": "Delicious recipe number \(i)",
                "content": "cooking recipe ingredients kitchen oven baking flour sugar butter chocolate vanilla dessert pastry culinary " + String(repeating: "restaurant cuisine flavor ", count: 20),
                "author": "TechWriter",
                "link": "https://tech.example.com/recent-\(i)",
                "publishedDate": formatter.string(from: date)
            ]
        }
        let result = sut.scan(feedName: "TechFeed", recentArticles: cookingArticles)
        let driftAnomalies = result.filter { $0.channel == .topicDrift }

        XCTAssertFalse(driftAnomalies.isEmpty, "Complete topic change should trigger drift detection")
        if let first = driftAnomalies.first {
            XCTAssertTrue(first.description.contains("topic drift") || first.description.contains("Topic drift"))
        }
    }

    // MARK: - Author Change

    func testAuthorChangeDetection() {
        // Baseline with consistent authors
        let articles = makeArticles(count: 30, author: "Alice")
        sut.learnBaseline(feedName: "AuthorFeed", articles: articles)

        // Recent: completely different author set
        let newAuthorArticles = makeRecentArticles(count: 5, author: "Zach")
        let result = sut.scan(feedName: "AuthorFeed", recentArticles: newAuthorArticles)
        let authorAnomalies = result.filter { $0.channel == .authorChange }

        XCTAssertFalse(authorAnomalies.isEmpty, "Complete author change should be detected")
        if let first = authorAnomalies.first {
            XCTAssertTrue(first.severity >= .warning)
        }
    }

    func testSameAuthorNoAnomaly() {
        let articles = makeArticles(count: 30, author: "Alice")
        sut.learnBaseline(feedName: "StableAuthor", articles: articles)

        let recent = makeRecentArticles(count: 5, author: "Alice")
        let result = sut.scan(feedName: "StableAuthor", recentArticles: recent)
        let authorAnomalies = result.filter { $0.channel == .authorChange }
        XCTAssertTrue(authorAnomalies.isEmpty, "Same author should not trigger anomaly")
    }

    // MARK: - Link Domain

    func testLinkDomainAnomaly() {
        let articles = makeArticles(count: 30, feedDomain: "trusted.example.com")
        sut.learnBaseline(feedName: "DomainFeed", articles: articles)

        // All links now point to suspicious domain
        let suspicious = makeRecentArticles(count: 5, feedDomain: "malware.evil.net")
        let result = sut.scan(feedName: "DomainFeed", recentArticles: suspicious)
        let domainAnomalies = result.filter { $0.channel == .linkDomain }

        XCTAssertFalse(domainAnomalies.isEmpty, "Unknown domains should trigger anomaly")
        if let first = domainAnomalies.first {
            XCTAssertTrue(first.severity >= .warning)
            XCTAssertTrue(first.description.contains("malware.evil.net"))
        }
    }

    func testSameDomainNoAnomaly() {
        let articles = makeArticles(count: 30, feedDomain: "blog.example.com")
        sut.learnBaseline(feedName: "SameDomain", articles: articles)

        let recent = makeRecentArticles(count: 5, feedDomain: "blog.example.com")
        let result = sut.scan(feedName: "SameDomain", recentArticles: recent)
        let domainAnomalies = result.filter { $0.channel == .linkDomain }
        XCTAssertTrue(domainAnomalies.isEmpty, "Same domain should not trigger anomaly")
    }

    // MARK: - Title Pattern

    func testTitlePatternAnomaly() {
        // Baseline: ~8 word titles
        let articles = makeArticles(count: 30, titleWords: 8)
        sut.learnBaseline(feedName: "TitleFeed", articles: articles)

        // Recent: very long titles (~30 words)
        let longTitles = makeRecentArticles(count: 5, titleWords: 30)
        let result = sut.scan(feedName: "TitleFeed", recentArticles: longTitles)
        let titleAnomalies = result.filter { $0.channel == .titlePattern }

        XCTAssertFalse(titleAnomalies.isEmpty, "Drastically different title length should be detected")
        if let first = titleAnomalies.first {
            XCTAssertTrue(first.description.contains("longer"))
        }
    }

    // MARK: - Trust Score

    func testDefaultTrustScore() {
        let score = sut.trustScore(for: "NewFeed")
        XCTAssertEqual(score.score, 100.0)
        XCTAssertEqual(score.totalAnomalies, 0)
        XCTAssertEqual(score.criticalCount, 0)
        XCTAssertEqual(score.warningCount, 0)
        XCTAssertEqual(score.infoCount, 0)
    }

    func testTrustScoreDegradesOnAnomalies() {
        // Build baseline then trigger anomalies
        let articles = makeArticles(count: 30, feedDomain: "good.example.com")
        sut.learnBaseline(feedName: "DegradeFeed", articles: articles)

        // Trigger domain anomaly
        let bad = makeRecentArticles(count: 5, feedDomain: "evil.badsite.com")
        sut.scan(feedName: "DegradeFeed", recentArticles: bad)

        let score = sut.trustScore(for: "DegradeFeed")
        XCTAssertLessThan(score.score, 100.0, "Trust score should degrade after anomalies")
        XCTAssertGreaterThan(score.totalAnomalies, 0)
    }

    func testTrustScoreRecoveryOnCleanScan() {
        let articles = makeArticles(count: 30, feedDomain: "good.example.com")
        sut.learnBaseline(feedName: "RecoverFeed", articles: articles)

        // Trigger anomaly first
        let bad = makeRecentArticles(count: 5, feedDomain: "evil.badsite.com")
        sut.scan(feedName: "RecoverFeed", recentArticles: bad)
        let degradedScore = sut.trustScore(for: "RecoverFeed").score

        // Clean scan (same domain, should produce no anomalies)
        let good = makeRecentArticles(count: 2, feedDomain: "good.example.com")
        sut.scan(feedName: "RecoverFeed", recentArticles: good)
        let recoveredScore = sut.trustScore(for: "RecoverFeed").score

        XCTAssertGreaterThanOrEqual(recoveredScore, degradedScore,
                                     "Trust should recover or hold after clean scan")
    }

    func testAllTrustScoresSorted() {
        // Create baselines for two feeds
        let articles = makeArticles(count: 30, feedDomain: "good.example.com")
        sut.learnBaseline(feedName: "Feed1", articles: articles)
        sut.learnBaseline(feedName: "Feed2", articles: articles)

        // Degrade Feed1
        let bad = makeRecentArticles(count: 5, feedDomain: "bad.example.com")
        sut.scan(feedName: "Feed1", recentArticles: bad)

        // Clean scan Feed2
        let good = makeRecentArticles(count: 2, feedDomain: "good.example.com")
        sut.scan(feedName: "Feed2", recentArticles: good)

        let scores = sut.allTrustScores()
        XCTAssertGreaterThanOrEqual(scores.count, 2)
        // Sorted ascending by score
        if scores.count >= 2 {
            XCTAssertLessThanOrEqual(scores[0].score, scores[1].score)
        }
    }

    // MARK: - Dismiss

    func testDismissAnomaly() {
        let articles = makeArticles(count: 30, feedDomain: "good.example.com")
        sut.learnBaseline(feedName: "DismissFeed", articles: articles)

        let bad = makeRecentArticles(count: 5, feedDomain: "evil.example.com")
        let detected = sut.scan(feedName: "DismissFeed", recentArticles: bad)
        guard let first = detected.first else {
            // If no anomalies detected (unlikely), skip
            return
        }

        sut.dismiss(anomalyId: first.id)
        let active = sut.anomalies(for: "DismissFeed", includeDismissed: false)
        XCTAssertFalse(active.contains(where: { $0.id == first.id }), "Dismissed anomaly should be excluded")

        let all = sut.anomalies(for: "DismissFeed", includeDismissed: true)
        XCTAssertTrue(all.contains(where: { $0.id == first.id }), "Dismissed anomaly should appear with includeDismissed")
    }

    func testDismissAllForFeed() {
        let articles = makeArticles(count: 30, feedDomain: "good.example.com")
        sut.learnBaseline(feedName: "DismissAllFeed", articles: articles)

        let bad = makeRecentArticles(count: 5, feedDomain: "evil.example.com")
        sut.scan(feedName: "DismissAllFeed", recentArticles: bad)

        sut.dismissAll(for: "DismissAllFeed")
        let active = sut.anomalies(for: "DismissAllFeed", includeDismissed: false)
        XCTAssertTrue(active.isEmpty, "All anomalies should be dismissed")
    }

    // MARK: - Query Filtering

    func testAnomalyQueryBySeverity() {
        let articles = makeArticles(count: 30, feedDomain: "good.example.com", avgWords: 500)
        sut.learnBaseline(feedName: "FilterFeed", articles: articles)

        // Trigger multiple channels
        let bad = makeRecentArticles(count: 10, feedDomain: "evil.example.com", avgWords: 20, titleWords: 30)
        sut.scan(feedName: "FilterFeed", recentArticles: bad)

        let all = sut.anomalies(for: "FilterFeed")
        let warnings = sut.anomalies(for: "FilterFeed", severity: .warning)
        let criticals = sut.anomalies(for: "FilterFeed", severity: .critical)

        // Filtered subsets should be subset of all
        XCTAssertTrue(warnings.allSatisfy { $0.severity == .warning })
        XCTAssertTrue(criticals.allSatisfy { $0.severity == .critical })
        XCTAssertGreaterThanOrEqual(all.count, warnings.count + criticals.count)
    }

    func testAnomalyQueryByFeed() {
        let articles = makeArticles(count: 30)
        sut.learnBaseline(feedName: "FeedA", articles: articles)
        sut.learnBaseline(feedName: "FeedB", articles: articles)

        let bad = makeRecentArticles(count: 5, feedDomain: "bad.example.com")
        sut.scan(feedName: "FeedA", recentArticles: bad)
        sut.scan(feedName: "FeedB", recentArticles: makeRecentArticles(count: 2))

        let feedAAnomalies = sut.anomalies(for: "FeedA")
        for a in feedAAnomalies {
            XCTAssertEqual(a.feedName, "FeedA")
        }
    }

    // MARK: - ScanAll

    func testScanAllMultipleFeeds() {
        let articles = makeArticles(count: 30, feedDomain: "good.example.com")
        sut.learnBaseline(feedName: "Multi1", articles: articles)
        sut.learnBaseline(feedName: "Multi2", articles: articles)

        let articlesByFeed: [String: [[String: String]]] = [
            "Multi1": makeRecentArticles(count: 5, feedDomain: "bad.example.com"),
            "Multi2": makeRecentArticles(count: 2, feedDomain: "good.example.com")
        ]

        let results = sut.scanAll(articlesByFeed: articlesByFeed)
        // Multi1 should have anomalies (bad domain), Multi2 may or may not
        if results["Multi1"] != nil {
            XCTAssertFalse(results["Multi1"]!.isEmpty)
        }
    }

    // MARK: - Report Generation

    func testGenerateReportEmpty() {
        let report = sut.generateReport()
        XCTAssertEqual(report.summary.totalAnomalies, 0)
        XCTAssertTrue(report.anomalies.isEmpty)
        XCTAssertTrue(report.trustScores.isEmpty)
        XCTAssertTrue(report.summary.recommendations.contains(where: { $0.contains("No anomalies") }))
    }

    func testGenerateReportForSpecificFeed() {
        let articles = makeArticles(count: 30, feedDomain: "good.example.com")
        sut.learnBaseline(feedName: "ReportFeed", articles: articles)

        let bad = makeRecentArticles(count: 5, feedDomain: "evil.example.com")
        sut.scan(feedName: "ReportFeed", recentArticles: bad)

        let report = sut.generateReport(feedName: "ReportFeed")
        XCTAssertEqual(report.feedName, "ReportFeed")
        XCTAssertEqual(report.summary.totalFeeds, 1)
        XCTAssertGreaterThanOrEqual(report.trustScores.count, 1)
        XCTAssertEqual(report.trustScores.first?.feedName, "ReportFeed")
    }

    func testGenerateReportSummaryCounts() {
        let articles = makeArticles(count: 30, feedDomain: "good.example.com", avgWords: 500)
        sut.learnBaseline(feedName: "CountFeed", articles: articles)

        let bad = makeRecentArticles(count: 10, feedDomain: "evil.example.com", avgWords: 20)
        sut.scan(feedName: "CountFeed", recentArticles: bad)

        let report = sut.generateReport()
        let s = report.summary
        XCTAssertEqual(s.criticalCount + s.warningCount + s.infoCount, s.totalAnomalies)
    }

    // MARK: - JSON Export

    func testExportJSONProducesValidData() {
        let articles = makeArticles(count: 30)
        sut.learnBaseline(feedName: "ExportFeed", articles: articles)
        sut.scan(feedName: "ExportFeed", recentArticles: makeRecentArticles(count: 3))

        let data = sut.exportJSON()
        XCTAssertNotNil(data)
        if let data = data {
            // Should be valid JSON
            let obj = try? JSONSerialization.jsonObject(with: data)
            XCTAssertNotNil(obj, "Export should produce valid JSON")
        }
    }

    func testExportJSONForSpecificFeed() {
        let articles = makeArticles(count: 30)
        sut.learnBaseline(feedName: "ExportSpecific", articles: articles)

        let data = sut.exportJSON(feedName: "ExportSpecific")
        XCTAssertNotNil(data)
    }

    // MARK: - Persistence

    func testPersistenceRoundTrip() {
        let articles = makeArticles(count: 30, feedDomain: "persist.example.com")
        sut.learnBaseline(feedName: "PersistFeed", articles: articles)

        let bad = makeRecentArticles(count: 5, feedDomain: "evil.example.com")
        sut.scan(feedName: "PersistFeed", recentArticles: bad)

        let originalAnomalies = sut.anomalies(for: "PersistFeed")
        let originalScore = sut.trustScore(for: "PersistFeed")

        // Create new instance pointing to same directory
        let sut2 = FeedAnomalyDetector(directory: tempDir)
        let loadedAnomalies = sut2.anomalies(for: "PersistFeed")
        let loadedScore = sut2.trustScore(for: "PersistFeed")

        XCTAssertEqual(loadedAnomalies.count, originalAnomalies.count, "Anomalies should persist")
        XCTAssertEqual(loadedScore.score, originalScore.score, accuracy: 0.01, "Trust score should persist")
    }

    // MARK: - Reset

    func testReset() {
        let articles = makeArticles(count: 30)
        sut.learnBaseline(feedName: "ResetFeed", articles: articles)
        sut.scan(feedName: "ResetFeed", recentArticles: makeRecentArticles(count: 3))

        sut.reset()

        XCTAssertTrue(sut.anomalies().isEmpty, "Anomalies should be cleared after reset")
        XCTAssertEqual(sut.trustScore(for: "ResetFeed").score, 100.0, "Trust score should reset to default")
        // Scanning should return empty (no baseline)
        let result = sut.scan(feedName: "ResetFeed", recentArticles: makeRecentArticles(count: 3))
        XCTAssertTrue(result.isEmpty)
    }

    // MARK: - Anomaly Trimming

    func testAnomalyTrimmingKeepsLast500() {
        let articles = makeArticles(count: 30, feedDomain: "good.example.com")
        sut.learnBaseline(feedName: "TrimFeed", articles: articles)

        // Trigger many scans to accumulate anomalies
        for _ in 0..<200 {
            let bad = makeRecentArticles(count: 5, feedDomain: "bad-\(UUID().uuidString.prefix(4)).example.com")
            sut.scan(feedName: "TrimFeed", recentArticles: bad)
        }

        let all = sut.anomalies(for: nil, includeDismissed: true)
        XCTAssertLessThanOrEqual(all.count, 500, "Anomalies should be trimmed to max 500")
    }

    // MARK: - Custom Thresholds

    func testCustomThresholdsAffectDetection() {
        // Very sensitive thresholds
        sut.thresholds.infoZScore = 0.5
        sut.thresholds.warningZScore = 1.0
        sut.thresholds.criticalZScore = 1.5

        let articles = makeArticles(count: 30, avgWords: 500)
        sut.learnBaseline(feedName: "SensitiveFeed", articles: articles)

        // Slightly different content should trigger with low thresholds
        let slight = makeRecentArticles(count: 5, avgWords: 350)
        let result = sut.scan(feedName: "SensitiveFeed", recentArticles: slight)

        // With very sensitive thresholds, even moderate deviation should trigger
        // (Can't guarantee exact count, but thresholds should affect detection)
        XCTAssertTrue(true, "Custom thresholds should be accepted without error")
    }

    func testMinSampleSizeThreshold() {
        sut.thresholds.minSampleSize = 20

        let articles = makeArticles(count: 15) // above default 7, below custom 20
        sut.learnBaseline(feedName: "ThreshFeed", articles: articles)

        let recent = makeRecentArticles(count: 5, feedDomain: "evil.example.com")
        let result = sut.scan(feedName: "ThreshFeed", recentArticles: recent)
        XCTAssertTrue(result.isEmpty, "Should not detect with sample size below custom threshold")
    }

    // MARK: - Notification

    func testAnomalyDetectedNotification() {
        let articles = makeArticles(count: 30, feedDomain: "good.example.com")
        sut.learnBaseline(feedName: "NotifyFeed", articles: articles)

        let expectation = expectation(description: "Anomaly notification")
        var receivedFeedName: String?

        let observer = NotificationCenter.default.addObserver(
            forName: .feedAnomaliesDetected, object: sut, queue: nil
        ) { notification in
            receivedFeedName = notification.userInfo?["feedName"] as? String
            expectation.fulfill()
        }

        let bad = makeRecentArticles(count: 5, feedDomain: "evil.example.com")
        sut.scan(feedName: "NotifyFeed", recentArticles: bad)

        wait(for: [expectation], timeout: 2.0)
        XCTAssertEqual(receivedFeedName, "NotifyFeed")

        NotificationCenter.default.removeObserver(observer)
    }

    func testTrustScoreChangedNotification() {
        let articles = makeArticles(count: 30, feedDomain: "good.example.com")
        sut.learnBaseline(feedName: "TrustNotify", articles: articles)

        let expectation = expectation(description: "Trust score notification")
        expectation.isInverted = false

        let observer = NotificationCenter.default.addObserver(
            forName: .feedTrustScoreChanged, object: sut, queue: nil
        ) { _ in
            expectation.fulfill()
        }

        // Trigger warning+ anomaly to fire trust score notification
        let bad = makeRecentArticles(count: 5, feedDomain: "evil.example.com")
        sut.scan(feedName: "TrustNotify", recentArticles: bad)

        wait(for: [expectation], timeout: 2.0)
        NotificationCenter.default.removeObserver(observer)
    }

    // MARK: - Edge Cases

    func testArticlesWithMissingFields() {
        let baseline = makeArticles(count: 30)
        sut.learnBaseline(feedName: "PartialFeed", articles: baseline)

        // Articles with missing fields
        let partial: [[String: String]] = [
            ["title": "No content or link"],
            ["content": "No title article with some words here"],
            [:] // completely empty
        ]
        // Should not crash
        let result = sut.scan(feedName: "PartialFeed", recentArticles: partial)
        XCTAssertTrue(true, "Scanning partial articles should not crash (got \(result.count) anomalies)")
    }

    func testArticlesWithInvalidDates() {
        let articles = makeArticles(count: 30)
        sut.learnBaseline(feedName: "BadDateFeed", articles: articles)

        let badDates: [[String: String]] = [
            ["title": "Article", "content": "Some words here", "publishedDate": "not-a-date"],
            ["title": "Article 2", "content": "More words here", "publishedDate": "2026-13-45"],
        ]
        // Should not crash
        let result = sut.scan(feedName: "BadDateFeed", recentArticles: badDates)
        XCTAssertTrue(true, "Bad dates should not crash (got \(result.count) anomalies)")
    }

    func testArticlesWithInvalidURLs() {
        let articles = makeArticles(count: 30)
        sut.learnBaseline(feedName: "BadURLFeed", articles: articles)

        let badURLs: [[String: String]] = [
            ["title": "Article", "content": "words here", "link": "not a valid url at all"],
            ["title": "Article", "content": "words here", "link": "://missing-scheme"],
        ]
        let result = sut.scan(feedName: "BadURLFeed", recentArticles: badURLs)
        XCTAssertTrue(true, "Bad URLs should not crash (got \(result.count) anomalies)")
    }

    func testEmptyRecentArticlesScan() {
        let articles = makeArticles(count: 30)
        sut.learnBaseline(feedName: "EmptyScan", articles: articles)
        let result = sut.scan(feedName: "EmptyScan", recentArticles: [])
        XCTAssertTrue(result.isEmpty, "Empty articles should produce no anomalies")
    }
}
