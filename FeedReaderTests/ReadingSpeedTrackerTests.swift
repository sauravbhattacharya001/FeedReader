//
//  ReadingSpeedTrackerTests.swift
//  FeedReaderTests
//

import XCTest
@testable import FeedReader

class ReadingSpeedTrackerTests: XCTestCase {

    var tracker: ReadingSpeedTracker!

    override func setUp() {
        super.setUp()
        tracker = ReadingSpeedTracker()
        UserDefaults.standard.removeObject(forKey: "ReadingSpeedTracker.samples")
        tracker.clearAll()
    }

    override func tearDown() {
        tracker.clearAll()
        super.tearDown()
    }

    // MARK: - Sample Recording

    func testRecordValidSample() {
        let sample = tracker.recordSample(
            articleTitle: "Test Article",
            feedName: "Tech Blog",
            wordCount: 500,
            readingTimeSeconds: 120
        )
        XCTAssertNotNil(sample)
        XCTAssertEqual(tracker.samples.count, 1)
        XCTAssertEqual(sample?.feedName, "Tech Blog")
        XCTAssertEqual(sample?.wordCount, 500)
    }

    func testRecordSampleCalculatesWPM() {
        let sample = tracker.recordSample(
            articleTitle: "Test",
            feedName: "Feed",
            wordCount: 500,
            readingTimeSeconds: 120 // 2 minutes → 250 WPM
        )
        XCTAssertNotNil(sample)
        XCTAssertEqual(sample!.wordsPerMinute, 250, accuracy: 0.1)
    }

    func testRejectTooFewWords() {
        let sample = tracker.recordSample(
            articleTitle: "Short",
            feedName: "Feed",
            wordCount: 10, // Below minimum 50
            readingTimeSeconds: 30
        )
        XCTAssertNil(sample)
        XCTAssertTrue(tracker.samples.isEmpty)
    }

    func testRejectTooShortReadingTime() {
        let sample = tracker.recordSample(
            articleTitle: "Quick",
            feedName: "Feed",
            wordCount: 500,
            readingTimeSeconds: 5 // Below minimum 10s
        )
        XCTAssertNil(sample)
    }

    func testRejectTooSlowWPM() {
        // 500 words in 20 minutes = 25 WPM (below 50 minimum)
        let sample = tracker.recordSample(
            articleTitle: "Idle",
            feedName: "Feed",
            wordCount: 500,
            readingTimeSeconds: 1200
        )
        XCTAssertNil(sample)
    }

    func testRejectTooFastWPM() {
        // 500 words in 5 seconds = 6000 WPM (above 1200 maximum)
        let sample = tracker.recordSample(
            articleTitle: "Skimmed",
            feedName: "Feed",
            wordCount: 5000,
            readingTimeSeconds: 10
        )
        XCTAssertNil(sample)
    }

    func testRecordSampleWithCategory() {
        let sample = tracker.recordSample(
            articleTitle: "AI News",
            feedName: "TechCrunch",
            wordCount: 800,
            readingTimeSeconds: 180,
            category: "tech"
        )
        XCTAssertNotNil(sample)
        XCTAssertEqual(sample?.category, "tech")
    }

    func testSamplesOrderedNewestFirst() {
        tracker.recordSample(articleTitle: "First", feedName: "F", wordCount: 500, readingTimeSeconds: 120)
        tracker.recordSample(articleTitle: "Second", feedName: "F", wordCount: 500, readingTimeSeconds: 120)
        XCTAssertEqual(tracker.samples.first?.articleTitle, "Second")
        XCTAssertEqual(tracker.samples.last?.articleTitle, "First")
    }

    // MARK: - Speed Calculations

    func testCurrentWPMWithNoData() {
        XCTAssertEqual(tracker.currentWPM, ReadingSpeedTracker.defaultWPM)
    }

    func testCurrentWPMWithData() {
        // Add samples at 200 WPM
        for i in 0..<5 {
            tracker.recordSample(
                articleTitle: "Article \(i)",
                feedName: "Feed",
                wordCount: 400,
                readingTimeSeconds: 120 // 200 WPM
            )
        }
        XCTAssertEqual(tracker.currentWPM, 200, accuracy: 1.0)
    }

    func testMedianWPMWithNoData() {
        XCTAssertNil(tracker.medianWPM)
    }

    func testMedianWPMOddCount() {
        // 3 samples: 200, 250, 300
        tracker.recordSample(articleTitle: "A", feedName: "F", wordCount: 400, readingTimeSeconds: 120) // 200
        tracker.recordSample(articleTitle: "B", feedName: "F", wordCount: 500, readingTimeSeconds: 120) // 250
        tracker.recordSample(articleTitle: "C", feedName: "F", wordCount: 300, readingTimeSeconds: 60)  // 300
        XCTAssertNotNil(tracker.medianWPM)
        XCTAssertEqual(tracker.medianWPM!, 250, accuracy: 1.0)
    }

    func testMedianWPMEvenCount() {
        tracker.recordSample(articleTitle: "A", feedName: "F", wordCount: 400, readingTimeSeconds: 120) // 200
        tracker.recordSample(articleTitle: "B", feedName: "F", wordCount: 300, readingTimeSeconds: 60)  // 300
        // Median of [200, 300] = 250
        XCTAssertNotNil(tracker.medianWPM)
        XCTAssertEqual(tracker.medianWPM!, 250, accuracy: 1.0)
    }

    func testStandardDeviationNeedsMinSamples() {
        tracker.recordSample(articleTitle: "A", feedName: "F", wordCount: 500, readingTimeSeconds: 120)
        XCTAssertNil(tracker.speedStandardDeviation) // Need at least 2
    }

    func testStandardDeviationCalculation() {
        // Uniform speed → std dev ≈ 0
        for i in 0..<5 {
            tracker.recordSample(articleTitle: "A\(i)", feedName: "F", wordCount: 500, readingTimeSeconds: 120)
        }
        XCTAssertNotNil(tracker.speedStandardDeviation)
        XCTAssertEqual(tracker.speedStandardDeviation!, 0, accuracy: 1.0)
    }

    // MARK: - Estimated Reading Time

    func testEstimatedReadingTimeDefault() {
        // No samples → uses 238 WPM
        let time = tracker.estimatedReadingTime(wordCount: 238)
        XCTAssertEqual(time, 60, accuracy: 1.0) // 238 words at 238 WPM = 1 minute
    }

    func testEstimatedReadingTimePersonalized() {
        // Add samples at 200 WPM
        for i in 0..<5 {
            tracker.recordSample(articleTitle: "A\(i)", feedName: "F", wordCount: 400, readingTimeSeconds: 120)
        }
        let time = tracker.estimatedReadingTime(wordCount: 400)
        XCTAssertEqual(time, 120, accuracy: 5.0) // 400 words at ~200 WPM ≈ 120s
    }

    func testFormattedEstimateLessThanMinute() {
        XCTAssertEqual(tracker.formattedEstimate(wordCount: 10), "< 1 min")
    }

    func testFormattedEstimateMinutes() {
        let result = tracker.formattedEstimate(wordCount: 238 * 5) // ~5 min at default
        XCTAssertTrue(result.contains("min"))
        XCTAssertFalse(result.contains("hr"))
    }

    func testFormattedEstimateHours() {
        let result = tracker.formattedEstimate(wordCount: 238 * 90) // ~90 min
        XCTAssertTrue(result.contains("hr"))
    }

    // MARK: - Length-Adjusted Speed

    func testLengthAdjustedWPMInsufficientData() {
        // Need at least 3 samples per bucket
        tracker.recordSample(articleTitle: "A", feedName: "F", wordCount: 200, readingTimeSeconds: 60)
        XCTAssertNil(tracker.lengthAdjustedWPM(wordCount: 200))
    }

    func testLengthAdjustedWPMWithData() {
        // Add 3 short article samples (< 500 words)
        for i in 0..<3 {
            tracker.recordSample(articleTitle: "Short\(i)", feedName: "F",
                                 wordCount: 300, readingTimeSeconds: 60) // 300 WPM
        }
        let wpm = tracker.lengthAdjustedWPM(wordCount: 200)
        XCTAssertNotNil(wpm)
        XCTAssertEqual(wpm!, 300, accuracy: 1.0)
    }

    // MARK: - Trend Analysis

    func testTrendInsufficientData() {
        XCTAssertEqual(tracker.speedTrend(), .insufficientData)
    }

    func testTrendSteady() {
        // Add 10 samples all at same speed
        for i in 0..<10 {
            let sample = SpeedSample(
                articleTitle: "A\(i)", feedName: "F",
                wordCount: 500, readingTimeSeconds: 120,
                recordedAt: Date().addingTimeInterval(Double(-i) * 3600)
            )
            tracker.samples.append(sample)
        }
        XCTAssertEqual(tracker.speedTrend(), .steady)
    }

    // MARK: - Feed Breakdown

    func testFeedBreakdownGroupsByFeed() {
        tracker.recordSample(articleTitle: "A", feedName: "TechCrunch", wordCount: 500, readingTimeSeconds: 120)
        tracker.recordSample(articleTitle: "B", feedName: "TechCrunch", wordCount: 500, readingTimeSeconds: 120)
        tracker.recordSample(articleTitle: "C", feedName: "Ars Technica", wordCount: 500, readingTimeSeconds: 150)

        let breakdown = tracker.feedBreakdown()
        XCTAssertEqual(breakdown.count, 2)

        let techCrunch = breakdown.first { $0.label == "TechCrunch" }
        XCTAssertNotNil(techCrunch)
        XCTAssertEqual(techCrunch?.sampleCount, 2)
    }

    func testCategoryBreakdownFiltersUncategorized() {
        tracker.recordSample(articleTitle: "A", feedName: "F", wordCount: 500, readingTimeSeconds: 120, category: "tech")
        tracker.recordSample(articleTitle: "B", feedName: "F", wordCount: 500, readingTimeSeconds: 120) // no category

        let breakdown = tracker.categoryBreakdown()
        XCTAssertEqual(breakdown.count, 1)
        XCTAssertEqual(breakdown.first?.label, "tech")
    }

    // MARK: - Population Comparison

    func testPopulationPercentileDefault() {
        // Default 238 WPM → 50th percentile
        let percentile = tracker.populationPercentile()
        XCTAssertEqual(percentile, 50)
    }

    func testSpeedLabelDefault() {
        XCTAssertEqual(tracker.speedLabel(), "Average")
    }

    func testSpeedLabelFast() {
        // Add samples at 400 WPM
        for i in 0..<5 {
            tracker.recordSample(articleTitle: "A\(i)", feedName: "F",
                                 wordCount: 400, readingTimeSeconds: 60)
        }
        XCTAssertEqual(tracker.speedLabel(), "Above Average")
    }

    func testSpeedLabelSlow() {
        // Add samples at 120 WPM
        for i in 0..<5 {
            tracker.recordSample(articleTitle: "A\(i)", feedName: "F",
                                 wordCount: 120, readingTimeSeconds: 60)
        }
        XCTAssertEqual(tracker.speedLabel(), "Slow")
    }

    // MARK: - Profile

    func testBuildProfileEmpty() {
        let profile = tracker.buildProfile()
        XCTAssertEqual(profile.averageWPM, ReadingSpeedTracker.defaultWPM)
        XCTAssertEqual(profile.totalSamples, 0)
        XCTAssertEqual(profile.recentTrend, .insufficientData)
        XCTAssertNil(profile.trackingSince)
    }

    func testBuildProfileWithData() {
        for i in 0..<5 {
            tracker.recordSample(articleTitle: "A\(i)", feedName: "TechBlog",
                                 wordCount: 500, readingTimeSeconds: 120, category: "tech")
        }
        let profile = tracker.buildProfile()
        XCTAssertEqual(profile.totalSamples, 5)
        XCTAssertGreaterThan(profile.averageWPM, 0)
        XCTAssertEqual(profile.feedBreakdown.count, 1)
        XCTAssertEqual(profile.categoryBreakdown.count, 1)
        XCTAssertNotNil(profile.trackingSince)
    }

    // MARK: - Export / Import

    func testExportJSON() {
        tracker.recordSample(articleTitle: "Test", feedName: "Feed", wordCount: 500, readingTimeSeconds: 120)
        let json = tracker.exportJSON()
        XCTAssertNotNil(json)
        XCTAssertTrue(json!.contains("Test"))
        XCTAssertTrue(json!.contains("Feed"))
    }

    func testImportJSON() {
        tracker.recordSample(articleTitle: "Existing", feedName: "Feed", wordCount: 500, readingTimeSeconds: 120)
        let json = tracker.exportJSON()!

        let newTracker = ReadingSpeedTracker()
        newTracker.clearAll()
        let imported = newTracker.importJSON(json)
        XCTAssertEqual(imported, 1)
        XCTAssertEqual(newTracker.samples.count, 1)
    }

    func testImportDeduplicates() {
        tracker.recordSample(articleTitle: "Test", feedName: "Feed", wordCount: 500, readingTimeSeconds: 120)
        let json = tracker.exportJSON()!
        let imported = tracker.importJSON(json) // Same data
        XCTAssertEqual(imported, 0) // No new samples
    }

    func testImportInvalidJSON() {
        let imported = tracker.importJSON("not valid json")
        XCTAssertEqual(imported, 0)
    }

    // MARK: - Management

    func testClearAll() {
        tracker.recordSample(articleTitle: "A", feedName: "F", wordCount: 500, readingTimeSeconds: 120)
        tracker.recordSample(articleTitle: "B", feedName: "F", wordCount: 500, readingTimeSeconds: 120)
        tracker.clearAll()
        XCTAssertTrue(tracker.samples.isEmpty)
    }

    func testRemoveSamplesBefore() {
        let old = SpeedSample(
            articleTitle: "Old", feedName: "F",
            wordCount: 500, readingTimeSeconds: 120,
            recordedAt: Date().addingTimeInterval(-86400 * 60) // 60 days ago
        )
        tracker.samples.append(old)
        tracker.recordSample(articleTitle: "New", feedName: "F", wordCount: 500, readingTimeSeconds: 120)

        let cutoff = Date().addingTimeInterval(-86400 * 30) // 30 days ago
        let removed = tracker.removeSamplesBefore(cutoff)
        XCTAssertEqual(removed, 1)
        XCTAssertEqual(tracker.samples.count, 1)
    }

    // MARK: - Edge Cases

    func testZeroWordCountSample() {
        let sample = SpeedSample(articleTitle: "Empty", feedName: "F",
                                 wordCount: 0, readingTimeSeconds: 60)
        XCTAssertEqual(sample.wordsPerMinute, 0)
    }

    func testZeroReadingTimeSample() {
        let sample = SpeedSample(articleTitle: "Instant", feedName: "F",
                                 wordCount: 500, readingTimeSeconds: 0)
        XCTAssertEqual(sample.wordsPerMinute, 0)
    }

    func testMaxSamplesEnforced() {
        // Add more than maxSamples
        for i in 0..<(ReadingSpeedTracker.maxSamples + 10) {
            tracker.recordSample(articleTitle: "A\(i)", feedName: "F",
                                 wordCount: 500, readingTimeSeconds: 120)
        }
        XCTAssertLessThanOrEqual(tracker.samples.count, ReadingSpeedTracker.maxSamples)
    }

    // MARK: - SpeedSample Model

    func testSpeedSampleEquatable() {
        let a = SpeedSample(articleTitle: "A", feedName: "F", wordCount: 500, readingTimeSeconds: 120)
        let b = a // Same instance values
        XCTAssertEqual(a, b)
    }

    func testSpeedBreakdownEquatable() {
        let a = SpeedBreakdown(label: "Tech", sampleCount: 5, averageWPM: 250, minWPM: 200, maxWPM: 300)
        let b = SpeedBreakdown(label: "Tech", sampleCount: 5, averageWPM: 250, minWPM: 200, maxWPM: 300)
        XCTAssertEqual(a, b)
    }

    // MARK: - Notification

    func testRecordSamplePostsNotification() {
        let expectation = self.expectation(forNotification: .readingSpeedDidUpdate, object: tracker)
        tracker.recordSample(articleTitle: "A", feedName: "F", wordCount: 500, readingTimeSeconds: 120)
        wait(for: [expectation], timeout: 1.0)
    }
}
