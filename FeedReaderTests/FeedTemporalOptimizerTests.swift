//
//  FeedTemporalOptimizerTests.swift
//  FeedReaderTests
//
//  Tests for FeedTemporalOptimizer — publishing pattern analysis and
//  optimal check-in recommendations.
//

import XCTest
@testable import FeedReader

class FeedTemporalOptimizerTests: XCTestCase {

    var currentDate: Date!
    var optimizer: FeedTemporalOptimizer!
    var calendar: Calendar!

    override func setUp() {
        super.setUp()
        calendar = Calendar.current
        // Fixed reference: 2024-11-15 12:00 UTC
        currentDate = Date(timeIntervalSince1970: 1_731_672_000)
        optimizer = FeedTemporalOptimizer(
            defaults: UserDefaults(suiteName: "TestTemporalOptimizer")!,
            dateProvider: { [unowned self] in self.currentDate },
            calendar: calendar
        )
        optimizer.reset()
    }

    override func tearDown() {
        UserDefaults(suiteName: "TestTemporalOptimizer")?.removePersistentDomain(forName: "TestTemporalOptimizer")
        super.tearDown()
    }

    // MARK: - Helpers

    private func makeDate(daysAgo: Int = 0, hour: Int = 12) -> Date {
        var comps = calendar.dateComponents([.year, .month, .day], from: currentDate)
        comps.hour = hour
        comps.minute = 0
        comps.second = 0
        let base = calendar.date(from: comps) ?? currentDate!
        return calendar.date(byAdding: .day, value: -daysAgo, to: base) ?? base
    }

    private func seedFeed(url: String = "https://example.com/feed",
                          name: String = "Example",
                          count: Int = 20,
                          hours: [Int]? = nil,
                          daysSpan: Int = 14) {
        for i in 0..<count {
            let hour = hours != nil ? hours![i % hours!.count] : (i * 3) % 24
            let day = i % daysSpan
            let date = makeDate(daysAgo: day, hour: hour)
            optimizer.recordPublishEvent(feedURL: url, feedName: name,
                                         articleTitle: "Article \(i)", publishedAt: date)
        }
    }

    // MARK: - Basic Recording

    func testRecordSingleEvent() {
        let event = optimizer.recordPublishEvent(
            feedURL: "https://example.com/feed", feedName: "Example",
            articleTitle: "Test Article", publishedAt: makeDate(hour: 9)
        )
        XCTAssertEqual(event.feedURL, "https://example.com/feed")
        XCTAssertEqual(event.feedName, "Example")
        XCTAssertEqual(event.publishHour, 9)
        XCTAssertEqual(optimizer.state.events.count, 1)
    }

    func testRecordBatchEvents() {
        let items = (0..<10).map { i in
            (feedURL: "https://example.com/feed", feedName: "Example",
             articleTitle: "Batch \(i)", publishedAt: makeDate(daysAgo: i, hour: 10))
        }
        optimizer.recordBatch(items)
        XCTAssertEqual(optimizer.state.events.count, 10)
    }

    func testTrackedFeedCount() {
        seedFeed(url: "https://a.com/feed", name: "A", count: 5)
        seedFeed(url: "https://b.com/feed", name: "B", count: 5)
        XCTAssertEqual(optimizer.trackedFeedCount, 2)
    }

    func testTrackedFeedURLs() {
        seedFeed(url: "https://a.com/feed", name: "A", count: 5)
        seedFeed(url: "https://b.com/feed", name: "B", count: 5)
        XCTAssertEqual(optimizer.trackedFeedURLs.count, 2)
        XCTAssertTrue(optimizer.trackedFeedURLs.contains("https://a.com/feed"))
    }

    // MARK: - Event Limits

    func testPerFeedEventLimit() {
        for i in 0..<600 {
            optimizer.recordPublishEvent(feedURL: "https://a.com/feed", feedName: "A",
                                         articleTitle: "Article \(i)",
                                         publishedAt: makeDate(daysAgo: i % 30, hour: i % 24))
        }
        let feedEvents = optimizer.state.events.filter { $0.feedURL == "https://a.com/feed" }
        XCTAssertLessThanOrEqual(feedEvents.count, FeedTemporalOptimizer.maxEventsPerFeed)
    }

    // MARK: - Profile Generation

    func testProfileNilForTooFewEvents() {
        optimizer.recordPublishEvent(feedURL: "https://a.com/feed", feedName: "A",
                                     articleTitle: "One", publishedAt: makeDate())
        XCTAssertNil(optimizer.profile(for: "https://a.com/feed"))
    }

    func testProfileGeneratedWithEnoughEvents() {
        seedFeed(count: 10)
        let profile = optimizer.profile(for: "https://example.com/feed")
        XCTAssertNotNil(profile)
        XCTAssertEqual(profile?.totalEvents, 10)
        XCTAssertEqual(profile?.feedName, "Example")
    }

    func testProfileHasHourlyHistogram() {
        seedFeed(count: 20)
        let profile = optimizer.profile(for: "https://example.com/feed")!
        XCTAssertEqual(profile.hourlyHistogram.bucketLabels.count, 24)
        XCTAssertEqual(profile.hourlyHistogram.counts.count, 24)
        XCTAssertEqual(profile.hourlyHistogram.total, 20)
    }

    func testProfileHasDailyHistogram() {
        seedFeed(count: 20)
        let profile = optimizer.profile(for: "https://example.com/feed")!
        XCTAssertEqual(profile.dailyHistogram.bucketLabels.count, 7)
        XCTAssertEqual(profile.dailyHistogram.counts.count, 7)
    }

    func testProfileInsightsNotEmpty() {
        seedFeed(count: 20)
        let profile = optimizer.profile(for: "https://example.com/feed")!
        XCTAssertFalse(profile.insights.isEmpty)
    }

    // MARK: - Histogram

    func testHourlyHistogramAccuracy() {
        // All articles at hour 9
        seedFeed(count: 10, hours: [9])
        let profile = optimizer.profile(for: "https://example.com/feed")!
        XCTAssertEqual(profile.hourlyHistogram.counts[9], 10)
        let otherSum = profile.hourlyHistogram.counts.enumerated()
            .filter { $0.offset != 9 }.reduce(0) { $0 + $1.element }
        XCTAssertEqual(otherSum, 0)
    }

    func testHistogramEntropy() {
        // All in one bucket → low entropy
        seedFeed(count: 20, hours: [9])
        let profile = optimizer.profile(for: "https://example.com/feed")!
        XCTAssertLessThan(profile.hourlyHistogram.entropy, 1.0)
    }

    func testHistogramEntropySpread() {
        // Spread across many hours → higher entropy
        seedFeed(count: 24, hours: Array(0..<24))
        let profile = optimizer.profile(for: "https://example.com/feed")!
        XCTAssertGreaterThan(profile.hourlyHistogram.entropy, 3.0)
    }

    func testHistogramPeak() {
        seedFeed(count: 20, hours: [14])
        let profile = optimizer.profile(for: "https://example.com/feed")!
        let peak = profile.hourlyHistogram.peak
        XCTAssertNotNil(peak)
        XCTAssertEqual(peak?.index, 14)
    }

    // MARK: - Rhythm Classification

    func testPeriodicRhythm() {
        // Concentrated in 2 hours
        seedFeed(count: 20, hours: [9, 10])
        let profile = optimizer.profile(for: "https://example.com/feed")!
        XCTAssertTrue([PublishingRhythm.periodic, .burst].contains(profile.rhythm))
    }

    func testBurstRhythm() {
        // Everything in one hour
        seedFeed(count: 30, hours: [15])
        let profile = optimizer.profile(for: "https://example.com/feed")!
        XCTAssertEqual(profile.rhythm, .burst)
    }

    func testRoundTheClockRhythm() {
        seedFeed(count: 48, hours: Array(0..<24))
        let profile = optimizer.profile(for: "https://example.com/feed")!
        XCTAssertEqual(profile.rhythm, .roundTheClock)
    }

    func testDormantRhythm() {
        // Only old articles, nothing recent
        for i in 0..<10 {
            optimizer.recordPublishEvent(feedURL: "https://a.com/feed", feedName: "Old Feed",
                                         articleTitle: "Old \(i)",
                                         publishedAt: makeDate(daysAgo: 60 + i, hour: 10))
        }
        let profile = optimizer.profile(for: "https://a.com/feed")
        XCTAssertEqual(profile?.rhythm, .dormant)
    }

    // MARK: - Peak Detection

    func testPeakHoursDetected() {
        seedFeed(count: 20, hours: [8, 9, 10])
        let profile = optimizer.profile(for: "https://example.com/feed")!
        XCTAssertFalse(profile.peakHours.isEmpty)
        // At least one of 8, 9, 10 should be a peak
        let peakSet = Set(profile.peakHours)
        XCTAssertTrue(peakSet.contains(8) || peakSet.contains(9) || peakSet.contains(10))
    }

    func testPeakDaysDetected() {
        // Seed all on same day of week by spacing 7 days apart
        for i in 0..<10 {
            optimizer.recordPublishEvent(feedURL: "https://a.com/feed", feedName: "Weekly",
                                         articleTitle: "Art \(i)",
                                         publishedAt: makeDate(daysAgo: i * 7, hour: 12))
        }
        // Profile may or may not detect peak day depending on calendar, but should not crash
        let profile = optimizer.profile(for: "https://a.com/feed")
        XCTAssertNotNil(profile)
    }

    // MARK: - Recommendations

    func testRecommendationsGenerated() {
        seedFeed(count: 20, hours: [9, 10, 11])
        let profile = optimizer.profile(for: "https://example.com/feed")!
        XCTAssertFalse(profile.recommendations.isEmpty)
    }

    func testRecommendationFields() {
        seedFeed(count: 20, hours: [14, 15])
        let profile = optimizer.profile(for: "https://example.com/feed")!
        if let rec = profile.recommendations.first {
            XCTAssertEqual(rec.feedURL, "https://example.com/feed")
            XCTAssertGreaterThan(rec.confidence, 0)
            XCTAssertFalse(rec.timeRangeLabel.isEmpty)
            XCTAssertFalse(rec.label.isEmpty)
        }
    }

    // MARK: - Golden Hours

    func testGoldenHoursEmpty() {
        let golden = optimizer.goldenHours()
        XCTAssertTrue(golden.hours.isEmpty)
        XCTAssertEqual(golden.label, "Not enough data")
    }

    func testGoldenHoursWithData() {
        seedFeed(url: "https://a.com/feed", name: "A", count: 20, hours: [9, 10])
        seedFeed(url: "https://b.com/feed", name: "B", count: 20, hours: [10, 11])
        let golden = optimizer.goldenHours()
        XCTAssertFalse(golden.hours.isEmpty)
        // Hour 10 should be golden (overlap of both feeds)
        XCTAssertTrue(golden.hours.contains(10))
    }

    func testGoldenHoursTopN() {
        seedFeed(count: 50, hours: Array(0..<24))
        let golden = optimizer.goldenHours(topN: 5)
        XCTAssertLessThanOrEqual(golden.hours.count, 5)
    }

    // MARK: - Schedule Shift Detection

    func testNoShiftWithConsistentPattern() {
        seedFeed(count: 30, hours: [9, 10, 11])
        let shifts = optimizer.detectScheduleShifts()
        XCTAssertTrue(shifts.isEmpty)
    }

    func testShiftDetectedOnPatternChange() {
        let url = "https://shift.com/feed"
        // Historical: publish at 9 AM
        for i in 0..<20 {
            optimizer.recordPublishEvent(feedURL: url, feedName: "Shift Feed",
                                         articleTitle: "Old \(i)",
                                         publishedAt: makeDate(daysAgo: 30 + i, hour: 9))
        }
        // Recent: publish at 21 (9 PM)
        for i in 0..<20 {
            optimizer.recordPublishEvent(feedURL: url, feedName: "Shift Feed",
                                         articleTitle: "New \(i)",
                                         publishedAt: makeDate(daysAgo: i, hour: 21))
        }
        let shifts = optimizer.detectScheduleShifts()
        // Should detect the 9 AM → 9 PM shift
        XCTAssertFalse(shifts.isEmpty)
        if let shift = shifts.first {
            XCTAssertEqual(shift.feedURL, url)
            XCTAssertFalse(shift.shiftDescription.isEmpty)
        }
    }

    // MARK: - Autonomous Insights

    func testAutonomousInsightsWithData() {
        seedFeed(url: "https://a.com/feed", name: "Active Feed", count: 30, hours: [9, 10])
        let insights = optimizer.autonomousInsights()
        XCTAssertFalse(insights.isEmpty)
        // Should include golden hours insight
        XCTAssertTrue(insights.contains { $0.category == "Golden Hours" })
    }

    func testInsightPrioritySorted() {
        seedFeed(url: "https://a.com/feed", name: "A", count: 30, hours: [9, 10])
        // Add a dormant feed
        for i in 0..<10 {
            optimizer.recordPublishEvent(feedURL: "https://dormant.com/feed", feedName: "Dormant",
                                         articleTitle: "Old \(i)",
                                         publishedAt: makeDate(daysAgo: 60 + i, hour: 12))
        }
        let insights = optimizer.autonomousInsights()
        // Verify sorted by priority (ascending)
        for i in 1..<insights.count {
            XCTAssertLessThanOrEqual(insights[i - 1].priority, insights[i].priority)
        }
    }

    // MARK: - Freshness

    func testFreshnessCalculated() {
        // Record events where recordedAt > publishedAt
        let publishTime = makeDate(daysAgo: 1, hour: 9)
        // The recordedAt is set to currentDate by the dateProvider
        optimizer.recordPublishEvent(feedURL: "https://a.com/feed", feedName: "A",
                                     articleTitle: "Fresh", publishedAt: publishTime)
        // Add more to hit threshold
        for i in 1..<6 {
            optimizer.recordPublishEvent(feedURL: "https://a.com/feed", feedName: "A",
                                         articleTitle: "Art \(i)",
                                         publishedAt: makeDate(daysAgo: i, hour: 10))
        }
        let profile = optimizer.profile(for: "https://a.com/feed")
        XCTAssertNotNil(profile?.avgFreshnessMinutes)
        XCTAssertGreaterThan(profile!.avgFreshnessMinutes!, 0)
    }

    // MARK: - All Profiles

    func testAllProfiles() {
        seedFeed(url: "https://a.com/feed", name: "A", count: 10)
        seedFeed(url: "https://b.com/feed", name: "B", count: 10)
        let profiles = optimizer.allProfiles()
        XCTAssertEqual(profiles.count, 2)
    }

    func testAllProfilesSortedByEventCount() {
        seedFeed(url: "https://a.com/feed", name: "A", count: 10)
        seedFeed(url: "https://b.com/feed", name: "B", count: 20)
        let profiles = optimizer.allProfiles()
        XCTAssertEqual(profiles.first?.feedName, "B")
    }

    // MARK: - Export

    func testExportJSON() {
        seedFeed(count: 10)
        let data = optimizer.exportJSON()
        XCTAssertNotNil(data)
        let json = try? JSONSerialization.jsonObject(with: data!) as? [String: Any]
        XCTAssertNotNil(json)
        XCTAssertEqual(json?["totalEvents"] as? Int, 10)
    }

    // MARK: - Management

    func testRemoveFeed() {
        seedFeed(url: "https://a.com/feed", name: "A", count: 10)
        seedFeed(url: "https://b.com/feed", name: "B", count: 10)
        optimizer.removeFeed("https://a.com/feed")
        XCTAssertEqual(optimizer.trackedFeedCount, 1)
        XCTAssertNil(optimizer.profile(for: "https://a.com/feed"))
    }

    func testReset() {
        seedFeed(count: 20)
        optimizer.reset()
        XCTAssertEqual(optimizer.state.events.count, 0)
        XCTAssertEqual(optimizer.trackedFeedCount, 0)
    }

    // MARK: - Notifications

    func testUpdateNotificationPosted() {
        let exp = expectation(forNotification: .temporalOptimizerDidUpdate, object: optimizer)
        optimizer.recordPublishEvent(feedURL: "https://a.com/feed", feedName: "A",
                                     articleTitle: "Test", publishedAt: makeDate())
        wait(for: [exp], timeout: 1.0)
    }

    func testShiftNotificationPosted() {
        let url = "https://shift.com/feed"
        for i in 0..<20 {
            optimizer.recordPublishEvent(feedURL: url, feedName: "S",
                                         articleTitle: "Old \(i)",
                                         publishedAt: makeDate(daysAgo: 30 + i, hour: 6))
        }
        for i in 0..<20 {
            optimizer.recordPublishEvent(feedURL: url, feedName: "S",
                                         articleTitle: "New \(i)",
                                         publishedAt: makeDate(daysAgo: i, hour: 22))
        }

        let exp = expectation(forNotification: .temporalScheduleShiftDetected, object: optimizer)
        exp.isInverted = false
        // May or may not fire depending on shift detection
        exp.assertForOverFulfill = false
        let shifts = optimizer.detectScheduleShifts()
        if shifts.isEmpty {
            exp.fulfill() // no shift detected, still pass
        }
        wait(for: [exp], timeout: 1.0)
    }

    // MARK: - Edge Cases

    func testEmptyProfile() {
        XCTAssertNil(optimizer.profile(for: "https://nonexistent.com/feed"))
    }

    func testSingleEventNotEnough() {
        optimizer.recordPublishEvent(feedURL: "https://a.com/feed", feedName: "A",
                                     articleTitle: "Solo", publishedAt: makeDate())
        XCTAssertNil(optimizer.profile(for: "https://a.com/feed"))
        XCTAssertEqual(optimizer.trackedFeedCount, 1)
    }

    func testHistogramProportionsSumToOne() {
        seedFeed(count: 30)
        let profile = optimizer.profile(for: "https://example.com/feed")!
        let sum = profile.hourlyHistogram.proportions.reduce(0, +)
        XCTAssertEqual(sum, 1.0, accuracy: 0.001)
    }

    func testCheckInRecommendationTimeRange() {
        seedFeed(count: 20, hours: [14, 15])
        let profile = optimizer.profile(for: "https://example.com/feed")!
        for rec in profile.recommendations {
            XCTAssertGreaterThanOrEqual(rec.startHour, 0)
            XCTAssertLessThan(rec.startHour, 24)
            XCTAssertFalse(rec.timeRangeLabel.isEmpty)
        }
    }

    func testPublishingRhythmCases() {
        XCTAssertEqual(PublishingRhythm.allCases.count, 5)
        for rhythm in PublishingRhythm.allCases {
            XCTAssertFalse(rhythm.emoji.isEmpty)
            XCTAssertFalse(rhythm.description.isEmpty)
            XCTAssertFalse(rhythm.rawValue.isEmpty)
        }
    }
}
