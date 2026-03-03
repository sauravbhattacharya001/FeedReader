//
//  ArticleTrendTests.swift
//  FeedReaderTests
//
//  Tests for ArticleTrendDetector — topic frequency tracking across feeds.
//

import XCTest
@testable import FeedReader

class ArticleTrendTests: XCTestCase {

    var detector: ArticleTrendDetector!
    var config: TrendConfig!
    let now = Date()

    override func setUp() {
        super.setUp()
        config = TrendConfig()
        config.currentWindowHours = 24
        config.previousWindowHours = 48
        config.minMentions = 2
        detector = ArticleTrendDetector(config: config, snapshots: [])
    }

    // MARK: - Ingest Tests

    func testIngestCreatesSnapshot() {
        detector.ingest(articles: [
            (title: "Apple releases iPhone", body: "New phone from Apple", feedName: "TechCrunch")
        ], timestamp: now)

        XCTAssertEqual(detector.snapshots.count, 1)
        XCTAssertEqual(detector.snapshots[0].totalArticles, 1)
    }

    func testIngestExtractsKeywords() {
        detector.ingest(articles: [
            (title: "Quantum computing breakthrough", body: "Scientists achieve quantum advantage", feedName: "Science")
        ], timestamp: now)

        let counts = detector.snapshots[0].keywordCounts
        XCTAssertTrue(counts.keys.contains("quantum"))
        XCTAssertEqual(counts["quantum"], 1) // once per article even if repeated
    }

    func testIngestMultipleArticles() {
        detector.ingest(articles: [
            (title: "Bitcoin surges past 100k", body: "Crypto market rallies", feedName: "Finance"),
            (title: "Bitcoin ETF approved", body: "SEC approves bitcoin ETF", feedName: "Reuters"),
            (title: "Ethereum update coming", body: "Ethereum blockchain upgrade", feedName: "Crypto")
        ], timestamp: now)

        let counts = detector.snapshots[0].keywordCounts
        XCTAssertEqual(counts["bitcoin"], 2)
        XCTAssertEqual(counts["ethereum"], 1)
    }

    func testIngestFiltersStopWords() {
        detector.ingest(articles: [
            (title: "The new update is here", body: "This is a test for the system", feedName: "Test")
        ], timestamp: now)

        let counts = detector.snapshots[0].keywordCounts
        XCTAssertNil(counts["the"])
        XCTAssertNil(counts["this"])
        XCTAssertNil(counts["for"])
    }

    func testIngestFiltersShortWords() {
        detector.ingest(articles: [
            (title: "AI is on US ban", body: "US AI", feedName: "Test")
        ], timestamp: now)

        let counts = detector.snapshots[0].keywordCounts
        XCTAssertNil(counts["ai"]) // 2 chars
        XCTAssertNil(counts["us"]) // 2 chars
    }

    func testIngestCountsKeywordOncePerArticle() {
        detector.ingest(articles: [
            (title: "Apple Apple Apple", body: "Apple launches Apple product from Apple", feedName: "News")
        ], timestamp: now)

        let counts = detector.snapshots[0].keywordCounts
        XCTAssertEqual(counts["apple"], 1)
    }

    func testMultipleIngestsCreateMultipleSnapshots() {
        detector.ingest(articles: [(title: "Test one", body: "body", feedName: "A")], timestamp: now.addingTimeInterval(-3600))
        detector.ingest(articles: [(title: "Test two", body: "body", feedName: "B")], timestamp: now)

        XCTAssertEqual(detector.snapshots.count, 2)
    }

    // MARK: - Trend Detection Tests

    func testDetectRisingTrend() {
        // Previous window: low count
        let prevTime = now.addingTimeInterval(-30 * 3600) // 30 hours ago
        detector.ingest(articles: [
            (title: "Climate change report", body: "Global warming data", feedName: "BBC")
        ], timestamp: prevTime)

        // Current window: higher count
        let curTime = now.addingTimeInterval(-2 * 3600)
        detector.ingest(articles: [
            (title: "Climate crisis deepens", body: "Climate emergency declared", feedName: "BBC"),
            (title: "Climate summit begins", body: "World leaders discuss climate", feedName: "NPR"),
            (title: "Climate action needed", body: "Scientists urge climate action", feedName: "Reuters")
        ], timestamp: curTime)

        let trends = detector.detectTrends(referenceDate: now)
        let climateTrend = trends.first { $0.topic == "climate" }
        XCTAssertNotNil(climateTrend)
        XCTAssertEqual(climateTrend?.direction, .rising)
        XCTAssertTrue(climateTrend!.changePercent > 0)
    }

    func testDetectSpike() {
        // No previous window data, only current
        let curTime = now.addingTimeInterval(-2 * 3600)
        detector.ingest(articles: [
            (title: "Earthquake hits region", body: "Major earthquake devastation", feedName: "BBC"),
            (title: "Earthquake rescue efforts", body: "Earthquake aftermath", feedName: "NPR")
        ], timestamp: curTime)

        let trends = detector.detectTrends(referenceDate: now)
        let quakeTrend = trends.first { $0.topic == "earthquake" }
        XCTAssertNotNil(quakeTrend)
        XCTAssertEqual(quakeTrend?.direction, .spike)
    }

    func testDetectFadingTrend() {
        // Previous window: topic was hot
        let prevTime = now.addingTimeInterval(-30 * 3600)
        detector.ingest(articles: [
            (title: "Olympics opening ceremony", body: "Olympics begin today", feedName: "ESPN"),
            (title: "Olympics medal count", body: "Olympics day two results", feedName: "BBC")
        ], timestamp: prevTime)

        // Current window: no mentions
        // (don't ingest anything in current window)

        let trends = detector.detectTrends(referenceDate: now)
        let olympicsTrend = trends.first { $0.topic == "olympics" }
        XCTAssertNotNil(olympicsTrend)
        XCTAssertEqual(olympicsTrend?.direction, .fading)
        XCTAssertEqual(olympicsTrend?.currentCount, 0)
    }

    func testDetectStableTrend() {
        // Previous and current roughly equal
        let prevTime = now.addingTimeInterval(-30 * 3600)
        detector.ingest(articles: [
            (title: "Technology stocks rally", body: "Tech sector gains", feedName: "Finance"),
            (title: "Technology industry outlook", body: "Tech growth continues", feedName: "Bloomberg")
        ], timestamp: prevTime)

        let curTime = now.addingTimeInterval(-2 * 3600)
        detector.ingest(articles: [
            (title: "Technology advances continue", body: "Tech innovation report", feedName: "Wired"),
            (title: "Technology jobs growing", body: "Tech employment boom", feedName: "BBC")
        ], timestamp: curTime)

        let trends = detector.detectTrends(referenceDate: now)
        let techTrend = trends.first { $0.topic == "technology" }
        XCTAssertNotNil(techTrend)
        XCTAssertEqual(techTrend?.direction, .stable)
    }

    func testMinMentionsFilter() {
        config.minMentions = 3
        detector = ArticleTrendDetector(config: config, snapshots: [])

        let curTime = now.addingTimeInterval(-2 * 3600)
        detector.ingest(articles: [
            (title: "Rare topic mentioned", body: "Unique subject", feedName: "A"),
            (title: "Rare topic again", body: "Unique subject repeated", feedName: "B")
        ], timestamp: curTime)

        let trends = detector.detectTrends(referenceDate: now)
        // "rare" only appears twice, below minMentions of 3
        let rareTrend = trends.first { $0.topic == "rare" }
        XCTAssertNil(rareTrend)
    }

    func testMaxTrendsLimit() {
        config.maxTrends = 3
        config.minMentions = 1
        detector = ArticleTrendDetector(config: config, snapshots: [])

        let curTime = now.addingTimeInterval(-2 * 3600)
        var articles: [(title: String, body: String, feedName: String)] = []
        for word in ["alpha", "bravo", "charlie", "delta", "echo"] {
            articles.append((title: "\(word) news today", body: "\(word) report details", feedName: "Feed"))
        }
        detector.ingest(articles: articles, timestamp: curTime)

        let trends = detector.detectTrends(referenceDate: now)
        XCTAssertLessThanOrEqual(trends.count, 3)
    }

    func testTrendsSortedByMomentum() {
        let curTime = now.addingTimeInterval(-2 * 3600)

        // Low momentum topic
        detector.ingest(articles: [
            (title: "Weather forecast sunny", body: "Weather mild", feedName: "A"),
            (title: "Weather update cloudy", body: "Weather report", feedName: "B")
        ], timestamp: now.addingTimeInterval(-30 * 3600))

        detector.ingest(articles: [
            (title: "Weather forecast rain", body: "Weather turns", feedName: "A"),
            (title: "Weather update storm", body: "Weather warning", feedName: "B")
        ], timestamp: curTime)

        // High momentum topic (spike, no previous data)
        detector.ingest(articles: [
            (title: "Volcano eruption massive", body: "Volcano emergency declared", feedName: "BBC"),
            (title: "Volcano evacuation ordered", body: "Volcano ash cloud", feedName: "NPR"),
            (title: "Volcano destroys village", body: "Volcano lava flow", feedName: "Reuters")
        ], timestamp: curTime)

        let trends = detector.detectTrends(referenceDate: now)
        guard let volcanoIdx = trends.firstIndex(where: { $0.topic == "volcano" }),
              let weatherIdx = trends.firstIndex(where: { $0.topic == "weather" }) else {
            XCTFail("Expected both volcano and weather trends")
            return
        }
        XCTAssertTrue(volcanoIdx < weatherIdx, "Volcano (spike) should rank higher than weather (stable)")
    }

    // MARK: - Top Keywords Tests

    func testTopKeywords() {
        detector.ingest(articles: [
            (title: "Python programming guide", body: "Learn python today", feedName: "Dev"),
            (title: "Python machine learning", body: "Python data science", feedName: "AI"),
            (title: "JavaScript framework new", body: "React update released", feedName: "Dev")
        ], timestamp: now.addingTimeInterval(-1 * 3600))

        let top = detector.topKeywords(hours: 24, limit: 5, referenceDate: now)
        XCTAssertFalse(top.isEmpty)
        XCTAssertEqual(top[0].keyword, "python")
        XCTAssertEqual(top[0].count, 2)
    }

    func testTopKeywordsRespectsTimeRange() {
        // Old article (outside range)
        detector.ingest(articles: [
            (title: "Ancient history topic", body: "Historical event details", feedName: "History")
        ], timestamp: now.addingTimeInterval(-100 * 3600))

        // Recent article
        detector.ingest(articles: [
            (title: "Recent news today", body: "Current events update", feedName: "News")
        ], timestamp: now.addingTimeInterval(-1 * 3600))

        let top = detector.topKeywords(hours: 24, limit: 10, referenceDate: now)
        let ancientTopic = top.first { $0.keyword == "ancient" }
        XCTAssertNil(ancientTopic, "Keywords outside time range should not appear")
    }

    // MARK: - Topic History Tests

    func testTopicHistory() {
        for i in 1...5 {
            detector.ingest(articles: [
                (title: "Space exploration news", body: "NASA mission update", feedName: "Science")
            ], timestamp: now.addingTimeInterval(-Double(i) * 3600))
        }

        let history = detector.topicHistory(for: "space")
        XCTAssertEqual(history.count, 5)
    }

    func testTopicHistoryCaseInsensitive() {
        detector.ingest(articles: [
            (title: "MARS mission launches", body: "Mars rover deployed", feedName: "NASA")
        ], timestamp: now)

        let history = detector.topicHistory(for: "Mars")
        XCTAssertEqual(history.count, 1)
    }

    func testTopicHistoryEmpty() {
        let history = detector.topicHistory(for: "nonexistent")
        XCTAssertTrue(history.isEmpty)
    }

    // MARK: - Summary Tests

    func testSummaryEmpty() {
        let summary = detector.summary(referenceDate: now)
        XCTAssertEqual(summary, "No trending topics detected.")
    }

    func testSummaryWithTrends() {
        let curTime = now.addingTimeInterval(-2 * 3600)
        detector.ingest(articles: [
            (title: "Election results announced", body: "Election day voting", feedName: "CNN"),
            (title: "Election coverage continues", body: "Election updates live", feedName: "BBC"),
            (title: "Election winner declared", body: "Election final results", feedName: "NPR")
        ], timestamp: curTime)

        let summary = detector.summary(referenceDate: now)
        XCTAssertTrue(summary.contains("📈 Trending Topics"))
        XCTAssertTrue(summary.contains("election"))
    }

    // MARK: - Reset Tests

    func testReset() {
        detector.ingest(articles: [
            (title: "Test article", body: "Test body", feedName: "Test")
        ], timestamp: now)

        XCTAssertEqual(detector.snapshots.count, 1)
        detector.reset()
        XCTAssertEqual(detector.snapshots.count, 0)
    }

    // MARK: - Edge Cases

    func testEmptyArticles() {
        detector.ingest(articles: [], timestamp: now)
        XCTAssertEqual(detector.snapshots.count, 1)
        XCTAssertEqual(detector.snapshots[0].totalArticles, 0)
        XCTAssertTrue(detector.snapshots[0].keywordCounts.isEmpty)
    }

    func testArticleWithOnlyStopWords() {
        detector.ingest(articles: [
            (title: "The and or but", body: "Is it was are be", feedName: "Test")
        ], timestamp: now)

        XCTAssertTrue(detector.snapshots[0].keywordCounts.isEmpty)
    }

    func testSnapshotTrimming() {
        // Ingest more than maxSnapshots
        for i in 0..<250 {
            detector.ingest(articles: [
                (title: "Article \(i)", body: "Body \(i)", feedName: "Feed")
            ], timestamp: now.addingTimeInterval(-Double(250 - i) * 60))
        }

        XCTAssertLessThanOrEqual(detector.snapshots.count, 200)
    }

    func testChangePercentCalculation() {
        // Previous: 1 mention, Current: 3 mentions → 200% increase
        detector.ingest(articles: [
            (title: "Robotics advancement today", body: "Robot technology", feedName: "A")
        ], timestamp: now.addingTimeInterval(-30 * 3600))

        detector.ingest(articles: [
            (title: "Robotics revolution begins", body: "Robotics future", feedName: "B"),
            (title: "Robotics company IPO", body: "Robotics market", feedName: "C"),
            (title: "Robotics conference opens", body: "Robotics demo day", feedName: "D")
        ], timestamp: now.addingTimeInterval(-2 * 3600))

        let trends = detector.detectTrends(referenceDate: now)
        let robotTrend = trends.first { $0.topic == "robotics" }
        XCTAssertNotNil(robotTrend)
        XCTAssertEqual(robotTrend!.changePercent, 200.0, accuracy: 0.1)
    }

    func testMomentumBounds() {
        detector.ingest(articles: [
            (title: "Fusion energy breakthrough announced", body: "Fusion reactor success", feedName: "A"),
            (title: "Fusion power milestone reached", body: "Nuclear fusion advance", feedName: "B")
        ], timestamp: now.addingTimeInterval(-2 * 3600))

        let trends = detector.detectTrends(referenceDate: now)
        for trend in trends {
            XCTAssertGreaterThanOrEqual(trend.momentum, 0.0)
            XCTAssertLessThanOrEqual(trend.momentum, 1.0)
        }
    }

    // MARK: - TrendDirection Tests

    func testAllDirectionsRepresentable() {
        let directions: [TrendDirection] = [.rising, .stable, .declining, .spike, .fading]
        XCTAssertEqual(directions.count, 5)
        for d in directions {
            XCTAssertFalse(d.rawValue.isEmpty)
        }
    }

    // MARK: - TrendSnapshot Codable Tests

    func testSnapshotCodable() throws {
        let snapshot = TrendSnapshot(
            timestamp: now,
            keywordCounts: ["test": 5, "swift": 3],
            totalArticles: 10
        )

        let data = try JSONEncoder().encode(snapshot)
        let decoded = try JSONDecoder().decode(TrendSnapshot.self, from: data)
        XCTAssertEqual(decoded, snapshot)
    }

    // MARK: - Notification Test

    func testTrendsDidUpdateNotification() {
        let expectation = self.expectation(forNotification: .trendsDidUpdate, object: nil)

        detector.ingest(articles: [
            (title: "Test notification", body: "Should fire", feedName: "Test")
        ], timestamp: now)

        wait(for: [expectation], timeout: 1.0)
    }

    // MARK: - Custom Stop Words

    func testCustomStopWords() {
        config.stopWords = config.stopWords.union(["python", "javascript"])
        detector = ArticleTrendDetector(config: config, snapshots: [])

        detector.ingest(articles: [
            (title: "Python programming guide", body: "Learn python", feedName: "Dev")
        ], timestamp: now)

        let counts = detector.snapshots[0].keywordCounts
        XCTAssertNil(counts["python"])
    }

    // MARK: - Declining Detection

    func testDetectDecliningTrend() {
        // Previous: high, Current: low
        detector.ingest(articles: [
            (title: "Scandal rocks government", body: "Scandal investigation", feedName: "A"),
            (title: "Scandal details emerge", body: "Scandal coverage continues", feedName: "B"),
            (title: "Scandal hearings begin", body: "Scandal testimony today", feedName: "C"),
            (title: "Scandal witnesses speak", body: "Scandal evidence presented", feedName: "D")
        ], timestamp: now.addingTimeInterval(-30 * 3600))

        detector.ingest(articles: [
            (title: "Scandal update minor", body: "Scandal fading away", feedName: "A")
        ], timestamp: now.addingTimeInterval(-2 * 3600))

        // Need minMentions to be 1 for "scandal" with count 1 in current window
        config.minMentions = 1
        detector = ArticleTrendDetector(config: config, snapshots: detector.snapshots)

        let trends = detector.detectTrends(referenceDate: now)
        let scandalTrend = trends.first { $0.topic == "scandal" }
        XCTAssertNotNil(scandalTrend)
        XCTAssertEqual(scandalTrend?.direction, .declining)
    }
}
