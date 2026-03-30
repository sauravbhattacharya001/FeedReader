//
//  ArticleWordCountTrackerTests.swift
//  FeedReaderTests
//
//  Tests for ArticleWordCountTracker.
//

import XCTest
@testable import FeedReader

class ArticleWordCountTrackerTests: XCTestCase {

    var tracker: ArticleWordCountTracker!
    var testDefaults: UserDefaults!

    override func setUp() {
        super.setUp()
        testDefaults = UserDefaults(suiteName: "ArticleWordCountTrackerTests")!
        testDefaults.removePersistentDomain(forName: "ArticleWordCountTrackerTests")
        tracker = ArticleWordCountTracker(defaults: testDefaults)
    }

    override func tearDown() {
        testDefaults.removePersistentDomain(forName: "ArticleWordCountTrackerTests")
        super.tearDown()
    }

    // MARK: - Word Counting

    func testCountWordsInText() {
        XCTAssertEqual(ArticleWordCountTracker.countWords(in: "hello world"), 2)
        XCTAssertEqual(ArticleWordCountTracker.countWords(in: ""), 0)
        XCTAssertEqual(ArticleWordCountTracker.countWords(in: "   "), 0)
        XCTAssertEqual(ArticleWordCountTracker.countWords(in: "one  two   three"), 3)
        XCTAssertEqual(ArticleWordCountTracker.countWords(in: "a\nb\tc"), 3)
    }

    // MARK: - Recording

    func testRecordArticle() {
        let record = tracker.recordArticle(title: "Test", wordCount: 500, feedName: "TechCrunch")
        XCTAssertEqual(record.articleTitle, "Test")
        XCTAssertEqual(record.wordCount, 500)
        XCTAssertEqual(record.feedName, "TechCrunch")
        XCTAssertEqual(tracker.recordCount, 1)
    }

    func testRecordMultipleArticles() {
        tracker.recordArticle(title: "A", wordCount: 100, feedName: "Feed1")
        tracker.recordArticle(title: "B", wordCount: 200, feedName: "Feed2")
        tracker.recordArticle(title: "C", wordCount: 300, feedName: "Feed1")
        XCTAssertEqual(tracker.recordCount, 3)
    }

    func testNegativeWordCountClampedToZero() {
        let record = tracker.recordArticle(title: "Bad", wordCount: -50, feedName: "Feed")
        XCTAssertEqual(record.wordCount, 0)
    }

    func testRemoveRecord() {
        let record = tracker.recordArticle(title: "Remove Me", wordCount: 100, feedName: "Feed")
        XCTAssertEqual(tracker.recordCount, 1)
        tracker.removeRecord(id: record.id)
        XCTAssertEqual(tracker.recordCount, 0)
    }

    // MARK: - Overall Stats

    func testOverallStatsEmpty() {
        let stats = tracker.overallStats()
        XCTAssertEqual(stats.totalArticles, 0)
        XCTAssertEqual(stats.totalWords, 0)
        XCTAssertNil(stats.shortestArticle)
    }

    func testOverallStatsWithData() {
        tracker.recordArticle(title: "Short", wordCount: 100, feedName: "A")
        tracker.recordArticle(title: "Long", wordCount: 3000, feedName: "B")
        tracker.recordArticle(title: "Medium", wordCount: 800, feedName: "A")

        let stats = tracker.overallStats()
        XCTAssertEqual(stats.totalArticles, 3)
        XCTAssertEqual(stats.totalWords, 3900)
        XCTAssertEqual(stats.averageWordCount, 1300)
        XCTAssertEqual(stats.shortestArticle, 100)
        XCTAssertEqual(stats.longestArticle, 3000)
        XCTAssertEqual(stats.topFeedsByVolume.first?.feedName, "A")
    }

    // MARK: - Length Distribution

    func testLengthDistribution() {
        tracker.recordArticle(title: "Micro", wordCount: 50, feedName: "F")
        tracker.recordArticle(title: "Short", wordCount: 300, feedName: "F")
        tracker.recordArticle(title: "Long", wordCount: 2000, feedName: "F")
        tracker.recordArticle(title: "Longform", wordCount: 5000, feedName: "F")

        let dist = tracker.lengthDistribution()
        XCTAssertEqual(dist.count, 4)
        let categories = dist.map { $0.category }
        XCTAssertTrue(categories.contains { $0.contains("Micro") })
        XCTAssertTrue(categories.contains { $0.contains("Longform") })
    }

    // MARK: - Article Length Category

    func testLengthCategoryClassification() {
        XCTAssertEqual(ArticleLengthCategory.from(wordCount: 50), .micro)
        XCTAssertEqual(ArticleLengthCategory.from(wordCount: 300), .short)
        XCTAssertEqual(ArticleLengthCategory.from(wordCount: 800), .medium)
        XCTAssertEqual(ArticleLengthCategory.from(wordCount: 2000), .long)
        XCTAssertEqual(ArticleLengthCategory.from(wordCount: 5000), .longform)
    }

    // MARK: - Daily Volumes

    func testDailyVolumes() {
        tracker.recordArticle(title: "Today", wordCount: 500, feedName: "F")
        let volumes = tracker.dailyVolumes(days: 7)
        XCTAssertEqual(volumes.count, 7)
        XCTAssertEqual(volumes.last?.articleCount, 1)
        XCTAssertEqual(volumes.last?.wordCount, 500)
    }

    // MARK: - Velocity Trend

    func testVelocityTrend() {
        tracker.recordArticle(title: "Recent", wordCount: 1000, feedName: "F")
        let trend = tracker.velocityTrend(weeks: 4)
        XCTAssertEqual(trend.count, 4)
        // Most recent week should have some velocity
        XCTAssertGreaterThan(trend.last?.wordsPerDay ?? 0, 0)
    }

    // MARK: - Clear

    func testClearAll() {
        tracker.recordArticle(title: "A", wordCount: 100, feedName: "F")
        tracker.recordArticle(title: "B", wordCount: 200, feedName: "F")
        tracker.clearAll()
        XCTAssertEqual(tracker.recordCount, 0)
    }

    // MARK: - All Records

    func testAllRecordsSortedByDate() {
        let older = Calendar.current.date(byAdding: .day, value: -1, to: Date())!
        tracker.recordArticle(title: "Old", wordCount: 100, feedName: "F", readAt: older)
        tracker.recordArticle(title: "New", wordCount: 200, feedName: "F")
        let records = tracker.allRecords()
        XCTAssertEqual(records.first?.articleTitle, "New")
        XCTAssertEqual(records.last?.articleTitle, "Old")
    }
}
