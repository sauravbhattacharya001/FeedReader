//
//  FeedUpdateSchedulerTests.swift
//  FeedReaderTests
//
//  Tests for FeedUpdateScheduler — adaptive feed polling intervals.
//

import XCTest
@testable import FeedReader

class FeedUpdateSchedulerTests: XCTestCase {

    var currentDate: Date!
    var scheduler: FeedUpdateScheduler!

    override func setUp() {
        super.setUp()
        currentDate = Date(timeIntervalSince1970: 1_700_000_000) // fixed reference
        scheduler = FeedUpdateScheduler(dateProvider: { [unowned self] in self.currentDate })
    }

    // MARK: - Initial State

    func testNewSchedulerHasNoSchedules() {
        XCTAssertTrue(scheduler.allStats().isEmpty)
        XCTAssertEqual(scheduler.feedsDueNow().count, 0)
    }

    func testNewFeedGetsDefaultInterval() {
        let schedule = scheduler.recordCheck(feedURL: "https://example.com/feed", newArticleCount: 0)
        XCTAssertEqual(schedule.currentInterval, FeedUpdateScheduler.defaultInterval * FeedUpdateScheduler.backoffMultiplier,
                       accuracy: 0.01)
    }

    // MARK: - Back-off Behavior

    func testEmptyCheckIncreasesInterval() {
        let url = "https://example.com/feed"
        let s1 = scheduler.recordCheck(feedURL: url, newArticleCount: 2)
        let interval1 = s1.currentInterval
        let s2 = scheduler.recordCheck(feedURL: url, newArticleCount: 0)
        XCTAssertGreaterThan(s2.currentInterval, interval1)
    }

    func testConsecutiveEmptyChecksBackOff() {
        let url = "https://example.com/feed"
        scheduler.recordCheck(feedURL: url, newArticleCount: 5) // start fast
        let initialInterval = scheduler.schedules[url.lowercased()]!.currentInterval

        for _ in 0..<5 {
            scheduler.recordCheck(feedURL: url, newArticleCount: 0)
        }

        let finalInterval = scheduler.schedules[url.lowercased()]!.currentInterval
        XCTAssertGreaterThan(finalInterval, initialInterval)
    }

    func testBackoffDoesNotExceedMaximum() {
        let url = "https://example.com/feed"
        for _ in 0..<100 {
            scheduler.recordCheck(feedURL: url, newArticleCount: 0)
        }
        let interval = scheduler.schedules[url.lowercased()]!.currentInterval
        XCTAssertLessThanOrEqual(interval, FeedUpdateScheduler.maximumInterval)
    }

    func testConsecutiveEmptyCountTracked() {
        let url = "https://example.com/feed"
        scheduler.recordCheck(feedURL: url, newArticleCount: 3)
        XCTAssertEqual(scheduler.schedules[url.lowercased()]!.consecutiveEmpty, 0)

        scheduler.recordCheck(feedURL: url, newArticleCount: 0)
        scheduler.recordCheck(feedURL: url, newArticleCount: 0)
        scheduler.recordCheck(feedURL: url, newArticleCount: 0)
        XCTAssertEqual(scheduler.schedules[url.lowercased()]!.consecutiveEmpty, 3)

        scheduler.recordCheck(feedURL: url, newArticleCount: 1) // resets
        XCTAssertEqual(scheduler.schedules[url.lowercased()]!.consecutiveEmpty, 0)
    }

    // MARK: - Speed-up Behavior

    func testNewArticlesDecreaseInterval() {
        let url = "https://example.com/feed"
        // Back off first
        for _ in 0..<5 {
            scheduler.recordCheck(feedURL: url, newArticleCount: 0)
        }
        let slowInterval = scheduler.schedules[url.lowercased()]!.currentInterval

        scheduler.recordCheck(feedURL: url, newArticleCount: 3)
        let fastInterval = scheduler.schedules[url.lowercased()]!.currentInterval

        XCTAssertLessThan(fastInterval, slowInterval)
    }

    func testHighVolumeSpeedsUpFaster() {
        let url1 = "https://example.com/feed1"
        let url2 = "https://example.com/feed2"

        // Both back off the same amount
        for _ in 0..<5 {
            scheduler.recordCheck(feedURL: url1, newArticleCount: 0)
            scheduler.recordCheck(feedURL: url2, newArticleCount: 0)
        }

        // Feed1 gets 1 article, feed2 gets 10
        scheduler.recordCheck(feedURL: url1, newArticleCount: 1)
        scheduler.recordCheck(feedURL: url2, newArticleCount: 10)

        let interval1 = scheduler.schedules[url1.lowercased()]!.currentInterval
        let interval2 = scheduler.schedules[url2.lowercased()]!.currentInterval

        XCTAssertLessThan(interval2, interval1, "High volume should speed up faster")
    }

    func testSpeedupDoesNotGoBelowMinimum() {
        let url = "https://example.com/feed"
        for _ in 0..<100 {
            scheduler.recordCheck(feedURL: url, newArticleCount: 50)
        }
        let interval = scheduler.schedules[url.lowercased()]!.currentInterval
        XCTAssertGreaterThanOrEqual(interval, FeedUpdateScheduler.minimumInterval)
    }

    // MARK: - Next Check Date

    func testNextCheckDateForNewFeed() {
        let url = "https://example.com/feed"
        // Never seen — should be now
        let next = scheduler.nextCheckDate(for: url)
        XCTAssertEqual(next, currentDate)
    }

    func testNextCheckDateAfterRecord() {
        let url = "https://example.com/feed"
        let schedule = scheduler.recordCheck(feedURL: url, newArticleCount: 0, at: currentDate)
        let expected = currentDate.addingTimeInterval(schedule.currentInterval)
        let next = scheduler.nextCheckDate(for: url)
        XCTAssertEqual(next.timeIntervalSince1970, expected.timeIntervalSince1970, accuracy: 0.001)
    }

    func testIsDueReturnsTrueWhenPastNextCheck() {
        let url = "https://example.com/feed"
        scheduler.recordCheck(feedURL: url, newArticleCount: 0, at: currentDate)
        // Advance time past the interval
        currentDate = currentDate.addingTimeInterval(FeedUpdateScheduler.maximumInterval + 1)
        XCTAssertTrue(scheduler.isDue(feedURL: url))
    }

    func testIsDueReturnsFalseWhenNotYetDue() {
        let url = "https://example.com/feed"
        scheduler.recordCheck(feedURL: url, newArticleCount: 0, at: currentDate)
        // Don't advance time
        XCTAssertFalse(scheduler.isDue(feedURL: url))
    }

    // MARK: - Feeds Due

    func testFeedsDueSoonestOrdering() {
        let url1 = "https://example.com/feed1"
        let url2 = "https://example.com/feed2"

        // Feed2 checked later, so its next check is later
        scheduler.recordCheck(feedURL: url1, newArticleCount: 0, at: currentDate)
        scheduler.recordCheck(feedURL: url2, newArticleCount: 0,
                             at: currentDate.addingTimeInterval(60))

        let sorted = scheduler.feedsDueSoonest()
        XCTAssertEqual(sorted.count, 2)
        XCTAssertEqual(sorted[0].feedURL.lowercased(), url1.lowercased())
    }

    func testFeedsDueNowReturnsOnlyDueFeeds() {
        let url1 = "https://example.com/feed1"
        let url2 = "https://example.com/feed2"

        scheduler.recordCheck(feedURL: url1, newArticleCount: 0, at: currentDate)
        scheduler.recordCheck(feedURL: url2, newArticleCount: 0, at: currentDate)

        // Not due yet
        XCTAssertEqual(scheduler.feedsDueNow().count, 0)

        // Advance time enough for both
        currentDate = currentDate.addingTimeInterval(FeedUpdateScheduler.maximumInterval + 1)
        XCTAssertEqual(scheduler.feedsDueNow().count, 2)
    }

    // MARK: - Tier Classification

    func testTierForRealtimeInterval() {
        XCTAssertEqual(FeedUpdateScheduler.tierForInterval(60), .realtime)
        XCTAssertEqual(FeedUpdateScheduler.tierForInterval(300), .realtime)
    }

    func testTierForFrequentInterval() {
        XCTAssertEqual(FeedUpdateScheduler.tierForInterval(600), .frequent)
        XCTAssertEqual(FeedUpdateScheduler.tierForInterval(1800), .frequent)
    }

    func testTierForStandardInterval() {
        XCTAssertEqual(FeedUpdateScheduler.tierForInterval(3600), .standard)
        XCTAssertEqual(FeedUpdateScheduler.tierForInterval(7200), .standard)
    }

    func testTierForRelaxedInterval() {
        XCTAssertEqual(FeedUpdateScheduler.tierForInterval(14400), .relaxed)
    }

    func testTierForInfrequentInterval() {
        XCTAssertEqual(FeedUpdateScheduler.tierForInterval(43200), .infrequent)
    }

    func testTierForDormantInterval() {
        XCTAssertEqual(FeedUpdateScheduler.tierForInterval(100000), .dormant)
    }

    func testTierComparable() {
        XCTAssertTrue(FeedUpdateScheduler.UpdateTier.realtime < .dormant)
        XCTAssertTrue(FeedUpdateScheduler.UpdateTier.frequent < .relaxed)
        XCTAssertFalse(FeedUpdateScheduler.UpdateTier.dormant < .realtime)
    }

    func testTierSummary() {
        // Set intervals manually
        scheduler.setInterval(60, for: "https://fast.com/feed")      // realtime → clamped to 300
        scheduler.setInterval(3600, for: "https://medium.com/feed")   // standard
        scheduler.setInterval(100000, for: "https://slow.com/feed")   // dormant

        let summary = scheduler.tierSummary()
        // 300s (minimum) = realtime
        XCTAssertEqual(summary[.realtime], 1)
        XCTAssertEqual(summary[.standard], 1)
        XCTAssertEqual(summary[.dormant], 1)
    }

    // MARK: - Statistics

    func testStatsForUnknownFeedReturnsNil() {
        XCTAssertNil(scheduler.stats(for: "https://unknown.com/feed"))
    }

    func testStatsAfterChecks() {
        let url = "https://example.com/feed"
        scheduler.recordCheck(feedURL: url, newArticleCount: 3, at: currentDate)
        scheduler.recordCheck(feedURL: url, newArticleCount: 0,
                             at: currentDate.addingTimeInterval(1800))
        scheduler.recordCheck(feedURL: url, newArticleCount: 2,
                             at: currentDate.addingTimeInterval(3600))

        let stats = scheduler.stats(for: url)!
        XCTAssertEqual(stats.totalChecks, 3)
        XCTAssertEqual(stats.totalNewArticles, 5)
        XCTAssertEqual(stats.averageArticlesPerCheck, 5.0 / 3.0, accuracy: 0.01)
        XCTAssertEqual(stats.consecutiveEmpty, 0)
        XCTAssertGreaterThan(stats.efficiency, 0)
    }

    func testAggregateStats() {
        scheduler.recordCheck(feedURL: "https://a.com/feed", newArticleCount: 5)
        scheduler.recordCheck(feedURL: "https://b.com/feed", newArticleCount: 3)
        scheduler.recordCheck(feedURL: "https://a.com/feed", newArticleCount: 0)

        let agg = scheduler.aggregateStats()
        XCTAssertEqual(agg.totalFeeds, 2)
        XCTAssertEqual(agg.totalChecks, 3)
        XCTAssertEqual(agg.totalArticles, 8)
        XCTAssertGreaterThan(agg.averageInterval, 0)
    }

    func testAggregateStatsEfficiencyUsesHistoryWindow() {
        // Issue #24: efficiency should use history-window counts for both
        // numerator and denominator, not mix history with lifetime totals.
        let url = "https://example.com/feed"
        // Record many checks so totalChecks >> history window
        for _ in 0..<60 {
            scheduler.recordCheck(feedURL: url, newArticleCount: 0)
        }
        // Now record some productive checks (these stay in history)
        for _ in 0..<25 {
            scheduler.recordCheck(feedURL: url, newArticleCount: 1)
        }
        // History has 50 entries (last 25 empty + 25 productive),
        // but totalChecks = 85. Efficiency should be 25/50 = 0.5,
        // NOT 25/85 ≈ 0.29.
        let agg = scheduler.aggregateStats()
        XCTAssertEqual(agg.overallEfficiency, 0.5, accuracy: 0.01)
    }

    func testAggregateStatsEmpty() {
        let agg = scheduler.aggregateStats()
        XCTAssertEqual(agg.totalFeeds, 0)
        XCTAssertEqual(agg.totalChecks, 0)
        XCTAssertEqual(agg.overallEfficiency, 0)
    }

    // MARK: - History Management

    func testHistoryDoesNotExceedMax() {
        let url = "https://example.com/feed"
        for i in 0..<100 {
            scheduler.recordCheck(feedURL: url, newArticleCount: i % 3)
        }
        let schedule = scheduler.schedules[url.lowercased()]!
        XCTAssertLessThanOrEqual(schedule.checkHistory.count, FeedUpdateScheduler.maxHistorySize)
    }

    // MARK: - Case Insensitivity

    func testURLCaseInsensitive() {
        scheduler.recordCheck(feedURL: "HTTPS://EXAMPLE.COM/FEED", newArticleCount: 5)
        let stats = scheduler.stats(for: "https://example.com/feed")
        XCTAssertNotNil(stats)
        XCTAssertEqual(stats!.totalNewArticles, 5)
    }

    // MARK: - Manual Overrides

    func testSetIntervalClampsToRange() {
        let url = "https://example.com/feed"

        scheduler.setInterval(1, for: url) // below minimum
        XCTAssertEqual(scheduler.schedules[url.lowercased()]!.currentInterval,
                       FeedUpdateScheduler.minimumInterval)

        scheduler.setInterval(999999, for: url) // above maximum
        XCTAssertEqual(scheduler.schedules[url.lowercased()]!.currentInterval,
                       FeedUpdateScheduler.maximumInterval)
    }

    func testSetIntervalCreatesScheduleIfNeeded() {
        let url = "https://new.com/feed"
        XCTAssertNil(scheduler.schedules[url.lowercased()])

        scheduler.setInterval(3600, for: url)
        XCTAssertNotNil(scheduler.schedules[url.lowercased()])
        XCTAssertEqual(scheduler.schedules[url.lowercased()]!.currentInterval, 3600)
    }

    func testResetSchedule() {
        let url = "https://example.com/feed"
        scheduler.recordCheck(feedURL: url, newArticleCount: 5)
        XCTAssertNotNil(scheduler.schedules[url.lowercased()])

        scheduler.resetSchedule(for: url)
        XCTAssertNil(scheduler.schedules[url.lowercased()])
    }

    func testPruneFeeds() {
        scheduler.recordCheck(feedURL: "https://a.com/feed", newArticleCount: 1)
        scheduler.recordCheck(feedURL: "https://b.com/feed", newArticleCount: 1)
        scheduler.recordCheck(feedURL: "https://c.com/feed", newArticleCount: 1)

        scheduler.pruneFeeds(keeping: ["https://a.com/feed", "https://c.com/feed"])
        XCTAssertEqual(scheduler.schedules.count, 2)
        XCTAssertNil(scheduler.schedules["https://b.com/feed"])
    }

    // MARK: - Serialization

    func testSerializeAndDeserialize() throws {
        scheduler.recordCheck(feedURL: "https://a.com/feed", newArticleCount: 5, at: currentDate)
        scheduler.recordCheck(feedURL: "https://b.com/feed", newArticleCount: 0, at: currentDate)

        let data = try scheduler.serialize()
        let restored = try FeedUpdateScheduler.deserialize(from: data)

        XCTAssertEqual(restored.schedules.count, 2)
        XCTAssertEqual(restored.schedules["https://a.com/feed"]?.totalNewArticles, 5)
        XCTAssertEqual(restored.schedules["https://b.com/feed"]?.totalChecks, 1)
    }

    func testDeserializeInvalidDataThrows() {
        let badData = "not json".data(using: .utf8)!
        XCTAssertThrowsError(try FeedUpdateScheduler.deserialize(from: badData))
    }

    // MARK: - Format Interval

    func testFormatIntervalSeconds() {
        XCTAssertEqual(FeedUpdateScheduler.formatInterval(30), "30s")
    }

    func testFormatIntervalMinutes() {
        XCTAssertEqual(FeedUpdateScheduler.formatInterval(300), "5 min")
        XCTAssertEqual(FeedUpdateScheduler.formatInterval(1800), "30 min")
    }

    func testFormatIntervalHours() {
        XCTAssertEqual(FeedUpdateScheduler.formatInterval(3600), "1h")
        XCTAssertEqual(FeedUpdateScheduler.formatInterval(5400), "1.5h")
    }

    func testFormatIntervalDays() {
        XCTAssertEqual(FeedUpdateScheduler.formatInterval(86400), "1d")
        XCTAssertEqual(FeedUpdateScheduler.formatInterval(129600), "1.5d")
    }

    // MARK: - Adaptive Scenario Tests

    func testFrequentFeedConvergesToShortInterval() {
        let url = "https://breaking-news.com/feed"
        // Simulate a feed that consistently has new articles
        for _ in 0..<20 {
            scheduler.recordCheck(feedURL: url, newArticleCount: 5)
        }
        let interval = scheduler.schedules[url.lowercased()]!.currentInterval
        XCTAssertEqual(interval, FeedUpdateScheduler.minimumInterval,
                       "Consistently active feed should converge to minimum interval")
    }

    func testDormantFeedConvergesToLongInterval() {
        let url = "https://abandoned-blog.com/feed"
        // Simulate a feed that never has new articles
        for _ in 0..<30 {
            scheduler.recordCheck(feedURL: url, newArticleCount: 0)
        }
        let interval = scheduler.schedules[url.lowercased()]!.currentInterval
        XCTAssertEqual(interval, FeedUpdateScheduler.maximumInterval,
                       "Consistently empty feed should converge to maximum interval")
    }

    func testBurstyFeedRecoversFast() {
        let url = "https://bursty.com/feed"
        // Back off
        for _ in 0..<5 {
            scheduler.recordCheck(feedURL: url, newArticleCount: 0)
        }
        let slowInterval = scheduler.schedules[url.lowercased()]!.currentInterval

        // Burst of content
        scheduler.recordCheck(feedURL: url, newArticleCount: 10)
        let fastInterval = scheduler.schedules[url.lowercased()]!.currentInterval

        // Should have dropped significantly
        XCTAssertLessThan(fastInterval, slowInterval / 2)
    }
}
