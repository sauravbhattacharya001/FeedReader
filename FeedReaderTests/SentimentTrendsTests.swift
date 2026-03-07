//
//  SentimentTrendsTests.swift
//  FeedReaderTests
//

import XCTest
@testable import FeedReader

class SentimentTrendsTests: XCTestCase {

    // MARK: - Helpers

    /// Build a sample with explicit values for testing.
    private func makeSample(
        title: String = "Test Article",
        feed: String = "Test Feed",
        score: Double = 0.5,
        label: String = "Positive",
        emotion: String = "Joy",
        positiveWords: Int = 10,
        negativeWords: Int = 2,
        wordCount: Int = 200,
        at date: Date = Date()
    ) -> SentimentSample {
        return SentimentSample(
            articleTitle: title, feedName: feed,
            score: score, label: label, dominantEmotion: emotion,
            positiveWords: positiveWords, negativeWords: negativeWords,
            wordCount: wordCount, recordedAt: date
        )
    }

    private func daysAgo(_ n: Int, from ref: Date = Date()) -> Date {
        return Calendar.current.date(byAdding: .day, value: -n, to: ref)!
    }

    // MARK: - Init

    func testInitWithEmptySamples() {
        let tracker = SentimentTrendsTracker(samples: [])
        XCTAssertEqual(tracker.totalSamples, 0)
        XCTAssertEqual(tracker.overallAverageScore, 0)
        XCTAssertTrue(tracker.trackedFeeds.isEmpty)
    }

    func testInitWithPreloadedSamples() {
        let s = [makeSample(score: 0.3), makeSample(score: -0.1)]
        let tracker = SentimentTrendsTracker(samples: s)
        XCTAssertEqual(tracker.totalSamples, 2)
    }

    // MARK: - Recording

    func testRecordSampleAddsToList() {
        let tracker = SentimentTrendsTracker(samples: [])
        let sample = makeSample(score: 0.6)
        tracker.recordSample(sample)
        XCTAssertEqual(tracker.totalSamples, 1)
        XCTAssertEqual(tracker.samples.first?.score, 0.6)
    }

    func testRecordSampleNewestFirst() {
        let tracker = SentimentTrendsTracker(samples: [])
        let old = makeSample(title: "Old", score: 0.1, at: daysAgo(1))
        let new = makeSample(title: "New", score: 0.9, at: Date())
        tracker.recordSample(old)
        tracker.recordSample(new)
        XCTAssertEqual(tracker.samples.first?.articleTitle, "New")
    }

    func testRemoveSampleById() {
        let tracker = SentimentTrendsTracker(samples: [])
        let sample = makeSample(score: 0.5)
        tracker.recordSample(sample)
        XCTAssertTrue(tracker.removeSample(id: sample.id))
        XCTAssertEqual(tracker.totalSamples, 0)
    }

    func testRemoveNonexistentReturnsFalse() {
        let tracker = SentimentTrendsTracker(samples: [])
        XCTAssertFalse(tracker.removeSample(id: "nope"))
    }

    func testClearAll() {
        let tracker = SentimentTrendsTracker(samples: [makeSample(), makeSample()])
        tracker.clearAll()
        XCTAssertEqual(tracker.totalSamples, 0)
    }

    func testScoreClampedToRange() {
        let sample = makeSample(score: 5.0)
        XCTAssertEqual(sample.score, 1.0)
        let sample2 = makeSample(score: -3.0)
        XCTAssertEqual(sample2.score, -1.0)
    }

    // MARK: - Aggregation

    func testDailyAverages() {
        let now = Date()
        let samples = [
            makeSample(score: 0.8, at: now),
            makeSample(score: 0.4, at: now),
            makeSample(score: -0.2, at: daysAgo(1, from: now)),
        ]
        let tracker = SentimentTrendsTracker(samples: samples)
        let daily = tracker.dailyAverages(lastDays: 7, asOf: now)
        XCTAssertGreaterThanOrEqual(daily.count, 1)

        // Today should have avg of (0.8 + 0.4) / 2 = 0.6
        if let today = daily.first {
            XCTAssertEqual(today.sampleCount, 2)
            XCTAssertEqual(today.averageScore, 0.6, accuracy: 0.01)
        }
    }

    func testDailyAveragesSkipsEmptyDays() {
        let tracker = SentimentTrendsTracker(samples: [
            makeSample(score: 0.5, at: daysAgo(3))
        ])
        let daily = tracker.dailyAverages(lastDays: 7)
        // Only 1 day has data
        XCTAssertEqual(daily.count, 1)
    }

    func testWeeklyAverages() {
        let now = Date()
        let samples = (0..<7).map { i in
            makeSample(score: Double(i) * 0.1, at: daysAgo(i, from: now))
        }
        let tracker = SentimentTrendsTracker(samples: samples)
        let weekly = tracker.weeklyAverages(lastWeeks: 4, asOf: now)
        XCTAssertGreaterThanOrEqual(weekly.count, 1)
    }

    func testMonthlyAverages() {
        let tracker = SentimentTrendsTracker(samples: [
            makeSample(score: 0.5, at: Date())
        ])
        let monthly = tracker.monthlyAverages(lastMonths: 3)
        XCTAssertGreaterThanOrEqual(monthly.count, 1)
    }

    func testAggregateMedianOddCount() {
        let tracker = SentimentTrendsTracker(samples: [
            makeSample(score: 0.1, at: Date()),
            makeSample(score: 0.5, at: Date()),
            makeSample(score: 0.9, at: Date()),
        ])
        let daily = tracker.dailyAverages(lastDays: 1)
        XCTAssertEqual(daily.first?.medianScore ?? -1, 0.5, accuracy: 0.01)
    }

    func testAggregatePositivityRatio() {
        let tracker = SentimentTrendsTracker(samples: [
            makeSample(score: 0.5, at: Date()),
            makeSample(score: 0.3, at: Date()),
            makeSample(score: -0.2, at: Date()),
        ])
        let daily = tracker.dailyAverages(lastDays: 1)
        // 2 out of 3 are positive
        XCTAssertEqual(daily.first?.positivityRatio ?? 0, 2.0 / 3.0, accuracy: 0.01)
    }

    // MARK: - Feed Profiles

    func testFeedProfileReturnsNilForUnknownFeed() {
        let tracker = SentimentTrendsTracker(samples: [])
        XCTAssertNil(tracker.feedProfile(feedName: "Unknown"))
    }

    func testFeedProfileCalculatesAverage() {
        let tracker = SentimentTrendsTracker(samples: [
            makeSample(feed: "TechCrunch", score: 0.6, at: daysAgo(0)),
            makeSample(feed: "TechCrunch", score: 0.2, at: daysAgo(1)),
            makeSample(feed: "TechCrunch", score: -0.1, at: daysAgo(2)),
            makeSample(feed: "CNN", score: -0.5, at: daysAgo(0)),
        ])
        let profile = tracker.feedProfile(feedName: "TechCrunch")
        XCTAssertNotNil(profile)
        XCTAssertEqual(profile?.sampleCount, 3)
        // avg = (0.6 + 0.2 + -0.1) / 3 ≈ 0.233
        XCTAssertEqual(profile?.averageScore ?? 0, 0.233, accuracy: 0.01)
    }

    func testAllFeedProfilesSortedByScore() {
        let tracker = SentimentTrendsTracker(samples: [
            makeSample(feed: "Happy News", score: 0.8, at: Date()),
            makeSample(feed: "Doom Feed", score: -0.7, at: Date()),
            makeSample(feed: "Neutral", score: 0.0, at: Date()),
        ])
        let profiles = tracker.allFeedProfiles()
        XCTAssertEqual(profiles.count, 3)
        XCTAssertEqual(profiles.first?.feedName, "Happy News")
        XCTAssertEqual(profiles.last?.feedName, "Doom Feed")
    }

    func testTopPositiveAndNegativeFeeds() {
        let tracker = SentimentTrendsTracker(samples: [
            makeSample(feed: "A", score: 0.9, at: Date()),
            makeSample(feed: "B", score: 0.3, at: Date()),
            makeSample(feed: "C", score: -0.1, at: Date()),
            makeSample(feed: "D", score: -0.8, at: Date()),
        ])
        let pos = tracker.topPositiveFeeds(limit: 2)
        XCTAssertEqual(pos.count, 2)
        XCTAssertEqual(pos.first?.feedName, "A")

        let neg = tracker.topNegativeFeeds(limit: 2)
        XCTAssertEqual(neg.count, 2)
        XCTAssertEqual(neg.first?.feedName, "D")
    }

    func testFeedSentimentDescription() {
        let profile = FeedSentimentProfile(
            feedName: "Test", sampleCount: 1, averageScore: 0.5,
            medianScore: 0.5, dominantEmotion: "Joy",
            positivityRatio: 1.0, trend: .steady, recentScore: 0.5
        )
        XCTAssertEqual(profile.sentimentDescription, "Positive")

        let negProfile = FeedSentimentProfile(
            feedName: "Test", sampleCount: 1, averageScore: -0.5,
            medianScore: -0.5, dominantEmotion: "Anger",
            positivityRatio: 0, trend: .steady, recentScore: -0.5
        )
        XCTAssertEqual(negProfile.sentimentDescription, "Negative")
    }

    // MARK: - Emotional Composition

    func testEmotionalCompositionEmpty() {
        let tracker = SentimentTrendsTracker(samples: [])
        let comp = tracker.emotionalComposition()
        XCTAssertEqual(comp.sampleCount, 0)
        XCTAssertEqual(comp.diversity, 0)
        XCTAssertEqual(comp.dominant, "None")
    }

    func testEmotionalCompositionSingleEmotion() {
        let tracker = SentimentTrendsTracker(samples: [
            makeSample(emotion: "Joy", at: Date()),
            makeSample(emotion: "Joy", at: Date()),
        ])
        let comp = tracker.emotionalComposition()
        XCTAssertEqual(comp.dominant, "Joy")
        XCTAssertEqual(comp.emotionShares["Joy"], 1.0)
        XCTAssertEqual(comp.diversity, 0, accuracy: 0.01) // no diversity with 1 emotion
    }

    func testEmotionalCompositionMultipleEmotions() {
        let tracker = SentimentTrendsTracker(samples: [
            makeSample(emotion: "Joy", at: Date()),
            makeSample(emotion: "Fear", at: Date()),
            makeSample(emotion: "Anger", at: Date()),
            makeSample(emotion: "Joy", at: Date()),
        ])
        let comp = tracker.emotionalComposition()
        XCTAssertEqual(comp.sampleCount, 4)
        XCTAssertEqual(comp.dominant, "Joy")
        XCTAssertEqual(comp.emotionShares["Joy"] ?? 0, 0.5, accuracy: 0.01)
        XCTAssertGreaterThan(comp.diversity, 0)
    }

    func testCompareCompositionBetweenPeriods() {
        let now = Date()
        let tracker = SentimentTrendsTracker(samples: [
            makeSample(emotion: "Joy", at: daysAgo(10, from: now)),
            makeSample(emotion: "Fear", at: daysAgo(2, from: now)),
        ])
        let (p1, p2) = tracker.compareComposition(
            period1Start: daysAgo(15, from: now), period1End: daysAgo(5, from: now),
            period2Start: daysAgo(5, from: now), period2End: now
        )
        XCTAssertEqual(p1.dominant, "Joy")
        XCTAssertEqual(p2.dominant, "Fear")
    }

    // MARK: - Trend Detection

    func testTrendInsufficientData() {
        let tracker = SentimentTrendsTracker(samples: [
            makeSample(score: 0.5, at: Date()),
        ])
        XCTAssertEqual(tracker.overallTrend(), .insufficientData)
    }

    func testTrendImproving() {
        let now = Date()
        // Old samples negative, recent positive
        var samples: [SentimentSample] = []
        for i in 0..<10 {
            let score = Double(i) * 0.15 - 0.5  // -0.5 → 0.85
            samples.append(makeSample(score: score, at: daysAgo(10 - i, from: now)))
        }
        let tracker = SentimentTrendsTracker(samples: samples)
        XCTAssertEqual(tracker.overallTrend(lastDays: 15, asOf: now), .improving)
    }

    func testTrendWorsening() {
        let now = Date()
        var samples: [SentimentSample] = []
        for i in 0..<10 {
            let score = 0.8 - Double(i) * 0.15  // 0.8 → -0.55
            samples.append(makeSample(score: score, at: daysAgo(10 - i, from: now)))
        }
        let tracker = SentimentTrendsTracker(samples: samples)
        XCTAssertEqual(tracker.overallTrend(lastDays: 15, asOf: now), .worsening)
    }

    func testTrendSteady() {
        let now = Date()
        let samples = (0..<10).map { i in
            makeSample(score: 0.3, at: daysAgo(i, from: now))
        }
        let tracker = SentimentTrendsTracker(samples: samples)
        XCTAssertEqual(tracker.overallTrend(lastDays: 15, asOf: now), .steady)
    }

    func testFeedTrend() {
        let now = Date()
        var samples: [SentimentSample] = []
        for i in 0..<10 {
            samples.append(makeSample(feed: "MyFeed", score: Double(i) * 0.1, at: daysAgo(10 - i, from: now)))
        }
        let tracker = SentimentTrendsTracker(samples: samples)
        XCTAssertEqual(tracker.feedTrend(feedName: "MyFeed", lastDays: 15, asOf: now), .improving)
    }

    // MARK: - Diet Report

    func testDietReportEmpty() {
        let tracker = SentimentTrendsTracker(samples: [])
        let report = tracker.dietReport()
        XCTAssertEqual(report.totalSamples, 0)
        XCTAssertEqual(report.overallAverage, 0)
        XCTAssertEqual(report.positivityRatio, 0)
    }

    func testDietReportWithData() {
        let now = Date()
        let samples = [
            makeSample(feed: "Good", score: 0.7, at: now),
            makeSample(feed: "Good", score: 0.5, at: daysAgo(1, from: now)),
            makeSample(feed: "Bad", score: -0.3, at: daysAgo(2, from: now)),
            makeSample(feed: "Bad", score: -0.6, at: daysAgo(3, from: now)),
            makeSample(feed: "Ok", score: 0.1, at: daysAgo(4, from: now)),
        ]
        let tracker = SentimentTrendsTracker(samples: samples)
        let report = tracker.dietReport(asOf: now)
        XCTAssertEqual(report.totalSamples, 5)
        XCTAssertGreaterThan(report.positivityRatio, 0)
        XCTAssertFalse(report.recommendation.isEmpty)
        XCTAssertFalse(report.topPositiveFeeds.isEmpty)
        XCTAssertFalse(report.topNegativeFeeds.isEmpty)
    }

    func testDietReportRecommendationNegative() {
        let now = Date()
        let samples = (0..<10).map { _ in
            makeSample(score: -0.5, at: now)
        }
        let tracker = SentimentTrendsTracker(samples: samples)
        let report = tracker.dietReport(asOf: now)
        XCTAssertTrue(report.recommendation.contains("negative"))
    }

    func testDietReportRecommendationBalanced() {
        let now = Date()
        let samples = [
            makeSample(score: 0.3, emotion: "Joy", at: now),
            makeSample(score: 0.1, emotion: "Trust", at: now),
            makeSample(score: -0.1, emotion: "Sadness", at: now),
            makeSample(score: 0.2, emotion: "Anticipation", at: now),
            makeSample(score: 0.0, emotion: "Surprise", at: now),
        ]
        let tracker = SentimentTrendsTracker(samples: samples)
        let report = tracker.dietReport(asOf: now)
        XCTAssertTrue(report.recommendation.lowercased().contains("balanced") ||
                       report.recommendation.lowercased().contains("neutral"))
    }

    // MARK: - Statistics

    func testOverallAverageScore() {
        let tracker = SentimentTrendsTracker(samples: [
            makeSample(score: 0.4, at: Date()),
            makeSample(score: 0.2, at: Date()),
            makeSample(score: -0.3, at: Date()),
        ])
        // (0.4 + 0.2 + -0.3) / 3 = 0.1
        XCTAssertEqual(tracker.overallAverageScore, 0.1, accuracy: 0.01)
    }

    func testTrackedFeeds() {
        let tracker = SentimentTrendsTracker(samples: [
            makeSample(feed: "BBC", at: Date()),
            makeSample(feed: "CNN", at: Date()),
            makeSample(feed: "BBC", at: Date()),
        ])
        let feeds = tracker.trackedFeeds
        XCTAssertEqual(feeds.count, 2)
        XCTAssertTrue(feeds.contains("BBC"))
        XCTAssertTrue(feeds.contains("CNN"))
    }

    func testWeeklyPositivityRatio() {
        let now = Date()
        let tracker = SentimentTrendsTracker(samples: [
            makeSample(score: 0.5, at: now),
            makeSample(score: 0.3, at: daysAgo(1, from: now)),
            makeSample(score: -0.4, at: daysAgo(2, from: now)),
            makeSample(score: -0.1, at: daysAgo(3, from: now)),
        ])
        // 2 positive out of 4
        XCTAssertEqual(tracker.weeklyPositivityRatio(asOf: now), 0.5, accuracy: 0.01)
    }

    // MARK: - Export / Import

    func testExportJSONProducesValidJSON() {
        let tracker = SentimentTrendsTracker(samples: [
            makeSample(score: 0.5, at: Date())
        ])
        let json = tracker.exportJSON()
        XCTAssertNotNil(json)
        XCTAssertTrue(json?.contains("articleTitle") ?? false)
    }

    func testImportJSONAddsSamples() {
        let source = SentimentTrendsTracker(samples: [
            makeSample(title: "Imported", score: 0.7, at: Date())
        ])
        let json = source.exportJSON()!

        let target = SentimentTrendsTracker(samples: [])
        let count = target.importJSON(json)
        XCTAssertEqual(count, 1)
        XCTAssertEqual(target.totalSamples, 1)
        XCTAssertEqual(target.samples.first?.articleTitle, "Imported")
    }

    func testImportJSONSkipsDuplicates() {
        let sample = makeSample(score: 0.5, at: Date())
        let tracker = SentimentTrendsTracker(samples: [sample])
        let json = tracker.exportJSON()!

        let count = tracker.importJSON(json)
        XCTAssertEqual(count, 0) // already exists
        XCTAssertEqual(tracker.totalSamples, 1)
    }

    func testImportInvalidJSONReturnsZero() {
        let tracker = SentimentTrendsTracker(samples: [])
        XCTAssertEqual(tracker.importJSON("not json"), 0)
    }

    // MARK: - Edge Cases

    func testPruningKeepsMaxSamples() {
        var samples: [SentimentSample] = []
        for i in 0..<(SentimentTrendsTracker.maxSamples + 100) {
            samples.append(makeSample(title: "Article \(i)", score: 0.1, at: Date()))
        }
        let tracker = SentimentTrendsTracker(samples: samples)
        // After pruning, should not exceed max
        XCTAssertLessThanOrEqual(tracker.totalSamples, SentimentTrendsTracker.maxSamples)
    }

    func testEmptyDailyAverages() {
        let tracker = SentimentTrendsTracker(samples: [])
        XCTAssertTrue(tracker.dailyAverages().isEmpty)
    }

    func testSingleSampleMedian() {
        let tracker = SentimentTrendsTracker(samples: [
            makeSample(score: 0.42, at: Date())
        ])
        let daily = tracker.dailyAverages(lastDays: 1)
        XCTAssertEqual(daily.first?.medianScore, 0.42, accuracy: 0.01)
    }
}
