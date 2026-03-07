//
//  ReadingInsightsGeneratorTests.swift
//  FeedReaderTests
//
//  Tests for ReadingInsightsGenerator: personality classification,
//  diversity scoring, consistency rating, trend comparisons, fun stats,
//  highlights, period window filtering, and export formatting.
//

import XCTest
@testable import FeedReader

class ReadingInsightsGeneratorTests: XCTestCase {

    // MARK: - Helpers

    private var generator: ReadingInsightsGenerator!
    private let cal = Calendar.current

    override func setUp() {
        super.setUp()
        generator = ReadingInsightsGenerator.shared
        generator.clearHistory()
    }

    /// Create events at a specific hour on a given day offset from the base date.
    private func makeEvent(title: String = "Article",
                           feedName: String = "TechFeed",
                           category: String? = "tech",
                           wordCount: Int? = 1000,
                           daysAgo: Int = 0,
                           hour: Int = 12,
                           from baseDate: Date = Date()) -> InsightReadEvent {
        var components = cal.dateComponents([.year, .month, .day], from: baseDate)
        components.hour = hour
        components.minute = 0
        components.second = 0
        let dayDate = cal.date(from: components)!
        let ts = cal.date(byAdding: .day, value: -daysAgo, to: dayDate)!
        return InsightReadEvent(
            link: "https://example.com/\(title.lowercased().replacingOccurrences(of: " ", with: "-"))",
            title: title,
            feedName: feedName,
            category: category,
            wordCount: wordCount,
            timestamp: ts
        )
    }

    /// Generate events spread across days with given feeds/categories.
    private func makeSpreadEvents(count: Int,
                                  feeds: [String] = ["Feed A"],
                                  categories: [String] = ["tech"],
                                  daysSpread: Int = 7,
                                  baseDate: Date = Date()) -> [InsightReadEvent] {
        var events: [InsightReadEvent] = []
        for i in 0..<count {
            let day = i % daysSpread
            let feed = feeds[i % feeds.count]
            let cat = categories[i % categories.count]
            events.append(makeEvent(
                title: "Article \(i)",
                feedName: feed,
                category: cat,
                daysAgo: day,
                hour: 10 + (i % 12),
                from: baseDate
            ))
        }
        return events
    }

    // MARK: - TrendComparison Tests

    func testTrendComparison_PercentChange() {
        let trend = TrendComparison(currentValue: 15, previousValue: 10)
        XCTAssertEqual(trend.percentChange!, 50.0, accuracy: 0.1)
        XCTAssertEqual(trend.direction, "up")
    }

    func testTrendComparison_Decrease() {
        let trend = TrendComparison(currentValue: 5, previousValue: 10)
        XCTAssertEqual(trend.percentChange!, -50.0, accuracy: 0.1)
        XCTAssertEqual(trend.direction, "down")
    }

    func testTrendComparison_Steady() {
        let trend = TrendComparison(currentValue: 10, previousValue: 10)
        XCTAssertEqual(trend.percentChange!, 0.0, accuracy: 0.1)
        XCTAssertEqual(trend.direction, "steady")
    }

    func testTrendComparison_ZeroPrevious() {
        let trend = TrendComparison(currentValue: 10, previousValue: 0)
        XCTAssertNil(trend.percentChange)
        XCTAssertEqual(trend.direction, "new")
    }

    func testTrendComparison_BothZero() {
        let trend = TrendComparison(currentValue: 0, previousValue: 0)
        XCTAssertNil(trend.percentChange)
        XCTAssertEqual(trend.direction, "new")
    }

    func testTrendComparison_SmallChange_Steady() {
        // Less than 5% change should be "steady"
        let trend = TrendComparison(currentValue: 10.3, previousValue: 10)
        XCTAssertEqual(trend.direction, "steady")
    }

    // MARK: - DiversityScore Tests

    func testDiversityScore_Overall() {
        let score = DiversityScore(topicDiversity: 0.8, feedDiversity: 0.6)
        XCTAssertEqual(score.overall, 0.7, accuracy: 0.01)
    }

    func testDiversityScore_Labels() {
        XCTAssertEqual(DiversityScore(topicDiversity: 0.9, feedDiversity: 0.9).label,
                       "Extremely diverse")
        XCTAssertEqual(DiversityScore(topicDiversity: 0.7, feedDiversity: 0.7).label,
                       "Well-rounded")
        XCTAssertEqual(DiversityScore(topicDiversity: 0.5, feedDiversity: 0.5).label,
                       "Moderately focused")
        XCTAssertEqual(DiversityScore(topicDiversity: 0.3, feedDiversity: 0.3).label,
                       "Narrowly focused")
        XCTAssertEqual(DiversityScore(topicDiversity: 0.1, feedDiversity: 0.1).label,
                       "Hyper-specialized")
    }

    func testDiversityScore_BoundaryAt08() {
        XCTAssertEqual(DiversityScore(topicDiversity: 0.8, feedDiversity: 0.8).label,
                       "Extremely diverse")
    }

    // MARK: - ReadingPersonality Tests

    func testPersonality_AllCasesHaveTaglines() {
        for p in ReadingPersonality.allCases {
            XCTAssertFalse(p.tagline.isEmpty, "\(p.rawValue) has no tagline")
        }
    }

    func testPersonality_RawValues() {
        XCTAssertEqual(ReadingPersonality.nightOwl.rawValue, "The Night Owl")
        XCTAssertEqual(ReadingPersonality.earlyBird.rawValue, "The Early Bird")
        XCTAssertEqual(ReadingPersonality.explorer.rawValue, "The Explorer")
        XCTAssertEqual(ReadingPersonality.specialist.rawValue, "The Specialist")
        XCTAssertEqual(ReadingPersonality.weekendWarrior.rawValue, "The Weekend Warrior")
        XCTAssertEqual(ReadingPersonality.marathoner.rawValue, "The Marathoner")
        XCTAssertEqual(ReadingPersonality.snacker.rawValue, "The Snacker")
        XCTAssertEqual(ReadingPersonality.consistent.rawValue, "The Steady Reader")
    }

    // MARK: - InsightPeriod Tests

    func testInsightPeriod_RawValues() {
        XCTAssertEqual(InsightPeriod.weekly.rawValue, "weekly")
        XCTAssertEqual(InsightPeriod.monthly.rawValue, "monthly")
    }

    // MARK: - Weekly Insight Generation

    func testWeeklyInsight_BasicGeneration() {
        let events = makeSpreadEvents(count: 14, daysSpread: 7)
        let report = generator.generateWeeklyInsight(from: events)

        XCTAssertEqual(report.period, .weekly)
        XCTAssertGreaterThan(report.totalArticlesRead, 0)
        XCTAssertFalse(report.id.isEmpty)
        XCTAssertFalse(report.peakHours.isEmpty)
    }

    func testWeeklyInsight_FiltersToWindow() {
        // Events outside the 7-day window should not be counted
        var events = makeSpreadEvents(count: 7, daysSpread: 7)
        // Add events from 20 days ago (outside window)
        events.append(makeEvent(title: "Old", daysAgo: 20))
        events.append(makeEvent(title: "Very Old", daysAgo: 30))

        let report = generator.generateWeeklyInsight(from: events)
        XCTAssertEqual(report.totalArticlesRead, 7)
    }

    func testWeeklyInsight_EmptyEvents() {
        let report = generator.generateWeeklyInsight(from: [])
        XCTAssertEqual(report.totalArticlesRead, 0)
        XCTAssertEqual(report.period, .weekly)
        XCTAssertEqual(report.consistencyRating, 0, accuracy: 0.01)
    }

    func testWeeklyInsight_TrendComparison() {
        // 10 events this week, 5 events last week
        var events: [InsightReadEvent] = []
        for i in 0..<10 {
            events.append(makeEvent(title: "This Week \(i)", daysAgo: i % 7))
        }
        for i in 0..<5 {
            events.append(makeEvent(title: "Last Week \(i)", daysAgo: 7 + i))
        }

        let report = generator.generateWeeklyInsight(from: events)
        XCTAssertEqual(report.articlesTrend.currentValue, 10.0, accuracy: 0.1)
        XCTAssertEqual(report.articlesTrend.previousValue, 5.0, accuracy: 0.1)
        XCTAssertEqual(report.articlesTrend.direction, "up")
    }

    // MARK: - Monthly Insight Generation

    func testMonthlyInsight_BasicGeneration() {
        let events = makeSpreadEvents(count: 30, daysSpread: 30)
        let report = generator.generateMonthlyInsight(from: events)

        XCTAssertEqual(report.period, .monthly)
        XCTAssertGreaterThan(report.totalArticlesRead, 0)
    }

    func testMonthlyInsight_FiltersToWindow() {
        var events = makeSpreadEvents(count: 20, daysSpread: 20)
        events.append(makeEvent(title: "Way Old", daysAgo: 60))

        let report = generator.generateMonthlyInsight(from: events)
        XCTAssertEqual(report.totalArticlesRead, 20)
    }

    // MARK: - Top Feeds and Categories

    func testTopFeeds_SortedByCount() {
        let events = [
            makeEvent(feedName: "A"), makeEvent(feedName: "A"), makeEvent(feedName: "A"),
            makeEvent(feedName: "B"), makeEvent(feedName: "B"),
            makeEvent(feedName: "C"),
        ]
        let report = generator.generateWeeklyInsight(from: events)

        XCTAssertEqual(report.topFeeds.first?.name, "A")
        XCTAssertEqual(report.topFeeds.first?.count, 3)
        XCTAssertGreaterThanOrEqual(report.topFeeds.count, 3)
    }

    func testTopCategories_FiltersNil() {
        let events = [
            makeEvent(category: "tech"),
            makeEvent(category: "tech"),
            makeEvent(category: nil),
            makeEvent(category: "science"),
        ]
        let report = generator.generateWeeklyInsight(from: events)

        let catNames = report.topCategories.map { $0.name }
        XCTAssertTrue(catNames.contains("tech"))
        // nil categories should not appear
        XCTAssertFalse(catNames.contains(""))
    }

    // MARK: - Peak Hours

    func testPeakHours_ReturnsTopThree() {
        var events: [InsightReadEvent] = []
        // 5 events at hour 22, 4 at hour 10, 3 at hour 14, 1 at hour 8
        for _ in 0..<5 { events.append(makeEvent(hour: 22)) }
        for _ in 0..<4 { events.append(makeEvent(hour: 10)) }
        for _ in 0..<3 { events.append(makeEvent(hour: 14)) }
        events.append(makeEvent(hour: 8))

        let report = generator.generateWeeklyInsight(from: events)
        XCTAssertLessThanOrEqual(report.peakHours.count, 3)
        XCTAssertTrue(report.peakHours.contains(22))
        XCTAssertTrue(report.peakHours.contains(10))
    }

    // MARK: - Fun Stats

    func testFunStats_WordCountEstimate() {
        // Events with explicit word counts
        let events = [
            makeEvent(wordCount: 500),
            makeEvent(wordCount: 1500),
            makeEvent(wordCount: 1000),
        ]
        let report = generator.generateWeeklyInsight(from: events)

        XCTAssertEqual(report.funStats.totalWordsRead, 3000)
        XCTAssertEqual(report.funStats.bookPagesEquivalent, 12)  // 3000 / 250
    }

    func testFunStats_DefaultWordCount() {
        // Events without word counts should use 800 default
        let events = [
            makeEvent(wordCount: nil),
            makeEvent(wordCount: nil),
        ]
        let report = generator.generateWeeklyInsight(from: events)
        XCTAssertEqual(report.funStats.totalWordsRead, 1600)  // 2 * 800
    }

    func testFunStats_UniqueFeeds() {
        let events = [
            makeEvent(feedName: "A"),
            makeEvent(feedName: "A"),
            makeEvent(feedName: "B"),
            makeEvent(feedName: "C"),
        ]
        let report = generator.generateWeeklyInsight(from: events)
        XCTAssertEqual(report.funStats.uniqueFeedsRead, 3)
    }

    func testFunStats_UniqueCategories() {
        let events = [
            makeEvent(category: "tech"),
            makeEvent(category: "science"),
            makeEvent(category: "tech"),
            makeEvent(category: nil),
        ]
        let report = generator.generateWeeklyInsight(from: events)
        XCTAssertEqual(report.funStats.uniqueCategories, 2)
    }

    func testFunStats_LongestStreak() {
        // 3 consecutive days of reading, then a gap, then 2 more
        let events = [
            makeEvent(daysAgo: 0),
            makeEvent(daysAgo: 1),
            makeEvent(daysAgo: 2),
            // gap at daysAgo: 3
            makeEvent(daysAgo: 4),
            makeEvent(daysAgo: 5),
        ]
        let report = generator.generateWeeklyInsight(from: events)
        XCTAssertEqual(report.funStats.longestStreakDays, 3)
    }

    func testFunStats_AvgArticlesPerActiveDay() {
        // 6 articles spread across 3 active days
        let events = [
            makeEvent(daysAgo: 0), makeEvent(daysAgo: 0),
            makeEvent(daysAgo: 2), makeEvent(daysAgo: 2),
            makeEvent(daysAgo: 4), makeEvent(daysAgo: 4),
        ]
        let report = generator.generateWeeklyInsight(from: events)
        XCTAssertEqual(report.funStats.avgArticlesPerActiveDay, 2.0, accuracy: 0.01)
    }

    func testFunStats_BusiestDay() {
        let events = [
            makeEvent(daysAgo: 0),
            makeEvent(title: "Second", daysAgo: 0),
            makeEvent(title: "Third", daysAgo: 0),
            makeEvent(daysAgo: 1),
        ]
        let report = generator.generateWeeklyInsight(from: events)
        XCTAssertNotNil(report.funStats.busiestDay)
        XCTAssertEqual(report.funStats.busiestDay?.count, 3)
    }

    // MARK: - Consistency Rating

    func testConsistency_PerfectlyEven() {
        // One article each day for 7 days
        let events = (0..<7).map { makeEvent(daysAgo: $0) }
        let report = generator.generateWeeklyInsight(from: events)
        // Perfect distribution = high consistency
        XCTAssertGreaterThan(report.consistencyRating, 0.8)
    }

    func testConsistency_AllOnOneDay() {
        // All articles on the same day
        let events = (0..<7).map { _ in makeEvent(daysAgo: 0) }
        let report = generator.generateWeeklyInsight(from: events)
        // Concentrated on one day = low consistency
        XCTAssertLessThan(report.consistencyRating, 0.5)
    }

    func testConsistency_NoEvents() {
        let report = generator.generateWeeklyInsight(from: [])
        XCTAssertEqual(report.consistencyRating, 0.0, accuracy: 0.01)
    }

    // MARK: - Diversity Scoring

    func testDiversity_SingleFeed_ZeroFeedDiversity() {
        let events = (0..<5).map { makeEvent(title: "Art \($0)", feedName: "OnlyFeed") }
        let report = generator.generateWeeklyInsight(from: events)
        XCTAssertEqual(report.diversity.feedDiversity, 0.0, accuracy: 0.01)
    }

    func testDiversity_ManyFeeds_HighDiversity() {
        let feeds = ["A", "B", "C", "D", "E", "F", "G", "H"]
        let events = feeds.map { makeEvent(feedName: $0) }
        let report = generator.generateWeeklyInsight(from: events)
        XCTAssertGreaterThan(report.diversity.feedDiversity, 0.8)
    }

    func testDiversity_SingleCategory_ZeroTopicDiversity() {
        let events = (0..<5).map { makeEvent(title: "Art \($0)", category: "tech") }
        let report = generator.generateWeeklyInsight(from: events)
        XCTAssertEqual(report.diversity.topicDiversity, 0.0, accuracy: 0.01)
    }

    func testDiversity_NilCategories_Excluded() {
        let events = (0..<5).map { makeEvent(title: "Art \($0)", category: nil) }
        let report = generator.generateWeeklyInsight(from: events)
        // No categories = 0 diversity (all are nil, compactMap filters them)
        XCTAssertEqual(report.diversity.topicDiversity, 0.0, accuracy: 0.01)
    }

    // MARK: - Personality Classification

    func testPersonality_NightOwl() {
        // >40% of events between 22:00-04:00
        var events: [InsightReadEvent] = []
        for i in 0..<6 { events.append(makeEvent(title: "Night \(i)", hour: 23)) }
        for i in 0..<4 { events.append(makeEvent(title: "Day \(i)", hour: 14)) }

        let report = generator.generateWeeklyInsight(from: events)
        XCTAssertEqual(report.personality, .nightOwl)
    }

    func testPersonality_EarlyBird() {
        // >40% of events between 05:00-09:00
        var events: [InsightReadEvent] = []
        for i in 0..<6 { events.append(makeEvent(title: "Morning \(i)", hour: 7)) }
        for i in 0..<4 { events.append(makeEvent(title: "Afternoon \(i)", hour: 15)) }

        let report = generator.generateWeeklyInsight(from: events)
        XCTAssertEqual(report.personality, .earlyBird)
    }

    func testPersonality_Explorer() {
        // 8+ unique feeds
        let feeds = ["A","B","C","D","E","F","G","H"]
        let events = feeds.enumerated().map { i, f in
            makeEvent(title: "Art \(i)", feedName: f, hour: 12)
        }
        let report = generator.generateWeeklyInsight(from: events)
        XCTAssertEqual(report.personality, .explorer)
    }

    func testPersonality_Specialist() {
        // ≤2 unique feeds, ≥5 articles, not night/morning-heavy
        let events = (0..<6).map { i in
            makeEvent(title: "Art \(i)", feedName: i < 4 ? "MainFeed" : "SecondFeed", hour: 12 + i)
        }
        let report = generator.generateWeeklyInsight(from: events)
        XCTAssertEqual(report.personality, .specialist)
    }

    func testPersonality_EmptyEvents() {
        let report = generator.generateWeeklyInsight(from: [])
        XCTAssertEqual(report.personality, .consistent)
    }

    // MARK: - Report Storage

    func testReportStorage_InsertsNewestFirst() {
        let events1 = [makeEvent(daysAgo: 0)]
        let events2 = [makeEvent(daysAgo: 0)]
        let r1 = generator.generateWeeklyInsight(from: events1)
        let r2 = generator.generateWeeklyInsight(from: events2)

        XCTAssertEqual(generator.reports.count, 2)
        XCTAssertEqual(generator.reports.first?.id, r2.id)
        XCTAssertEqual(generator.reports.last?.id, r1.id)
    }

    func testReportStorage_CapsAtMax() {
        for i in 0..<(ReadingInsightsGenerator.maxReports + 5) {
            _ = generator.generateWeeklyInsight(from: [makeEvent(title: "Art \(i)")])
        }
        XCTAssertEqual(generator.reports.count, ReadingInsightsGenerator.maxReports)
    }

    func testLatestReport_FindsByPeriod() {
        _ = generator.generateWeeklyInsight(from: [makeEvent()])
        _ = generator.generateMonthlyInsight(from: [makeEvent()])

        XCTAssertNotNil(generator.latestReport(for: .weekly))
        XCTAssertNotNil(generator.latestReport(for: .monthly))
        XCTAssertEqual(generator.latestReport(for: .monthly)?.period, .monthly)
    }

    func testClearHistory() {
        _ = generator.generateWeeklyInsight(from: [makeEvent()])
        XCTAssertEqual(generator.reports.count, 1)

        generator.clearHistory()
        XCTAssertEqual(generator.reports.count, 0)
    }

    // MARK: - Export: Text

    func testExportAsText_ContainsKeySections() {
        let events = makeSpreadEvents(count: 10, feeds: ["TechBlog", "AIWeekly"],
                                       categories: ["tech", "ai"], daysSpread: 7)
        let report = generator.generateWeeklyInsight(from: events)
        let text = generator.exportAsText(report)

        XCTAssertTrue(text.contains("Weekly Reading Insights"))
        XCTAssertTrue(text.contains("Your Reading Personality:"))
        XCTAssertTrue(text.contains("Articles Read:"))
        XCTAssertTrue(text.contains("Diversity:"))
        XCTAssertTrue(text.contains("Consistency:"))
    }

    func testExportAsText_IncludesTopFeeds() {
        let events = [
            makeEvent(feedName: "MyFeed"),
            makeEvent(title: "Another", feedName: "MyFeed"),
        ]
        let report = generator.generateWeeklyInsight(from: events)
        let text = generator.exportAsText(report)

        XCTAssertTrue(text.contains("MyFeed"))
    }

    // MARK: - Export: JSON

    func testExportAsJSON_ValidJSON() {
        let events = makeSpreadEvents(count: 5)
        let report = generator.generateWeeklyInsight(from: events)
        let jsonStr = generator.exportAsJSON(report)

        XCTAssertNotNil(jsonStr)
        if let data = jsonStr?.data(using: .utf8) {
            let parsed = try? JSONSerialization.jsonObject(with: data)
            XCTAssertNotNil(parsed, "Export should produce valid JSON")
        }
    }

    func testExportAsJSON_RoundTrips() {
        let events = makeSpreadEvents(count: 8, feeds: ["A", "B"], categories: ["x", "y"])
        let original = generator.generateWeeklyInsight(from: events)
        guard let jsonStr = generator.exportAsJSON(original),
              let data = jsonStr.data(using: .utf8) else {
            XCTFail("Failed to export JSON")
            return
        }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try? decoder.decode(InsightReport.self, from: data)

        XCTAssertNotNil(decoded)
        XCTAssertEqual(decoded?.id, original.id)
        XCTAssertEqual(decoded?.period, original.period)
        XCTAssertEqual(decoded?.totalArticlesRead, original.totalArticlesRead)
        XCTAssertEqual(decoded?.personality, original.personality)
    }

    // MARK: - Highlights

    func testHighlights_FirstPeriod() {
        // No previous events = "first insight period" highlight
        let events = [makeEvent()]
        let report = generator.generateWeeklyInsight(from: events)
        let hasFirstMessage = report.highlights.contains { $0.contains("first insight period") }
        XCTAssertTrue(hasFirstMessage)
    }

    func testHighlights_BigIncrease() {
        var events: [InsightReadEvent] = []
        // 10 this week
        for i in 0..<10 { events.append(makeEvent(title: "New \(i)", daysAgo: i % 7)) }
        // 3 last week
        for i in 0..<3 { events.append(makeEvent(title: "Old \(i)", daysAgo: 7 + i)) }

        let report = generator.generateWeeklyInsight(from: events)
        let hasUpTrend = report.highlights.contains { $0.contains("more than last period") }
        XCTAssertTrue(hasUpTrend)
    }

    func testHighlights_BigDecrease() {
        var events: [InsightReadEvent] = []
        // 3 this week
        for i in 0..<3 { events.append(makeEvent(title: "New \(i)", daysAgo: i)) }
        // 10 last week
        for i in 0..<10 { events.append(makeEvent(title: "Old \(i)", daysAgo: 7 + (i % 7))) }

        let report = generator.generateWeeklyInsight(from: events)
        let hasDownTrend = report.highlights.contains { $0.contains("dipped") }
        XCTAssertTrue(hasDownTrend)
    }

    func testHighlights_NewFeedsDiscovered() {
        var events: [InsightReadEvent] = []
        events.append(makeEvent(feedName: "NewFeed", daysAgo: 0))
        events.append(makeEvent(feedName: "OldFeed", daysAgo: 0))
        events.append(makeEvent(feedName: "OldFeed", daysAgo: 10))  // last week

        let report = generator.generateWeeklyInsight(from: events)
        let hasNewFeeds = report.highlights.contains { $0.contains("new feed") }
        XCTAssertTrue(hasNewFeeds)
    }

    func testHighlights_HighDiversityNote() {
        let feeds = ["A","B","C","D","E","F","G","H","I","J"]
        let cats = ["a","b","c","d","e","f","g","h","i","j"]
        let events = makeSpreadEvents(count: 20, feeds: feeds, categories: cats)
        let report = generator.generateWeeklyInsight(from: events)
        let hasDiversityNote = report.highlights.contains { $0.contains("generalist") || $0.contains("diverse") }
        // May or may not trigger depending on entropy — don't force it
        if report.diversity.overall > 0.7 {
            XCTAssertTrue(hasDiversityNote)
        }
    }

    // MARK: - InsightReadEvent Equality

    func testInsightReadEvent_Equatable() {
        let e1 = makeEvent(title: "A", feedName: "F", daysAgo: 0)
        let e2 = makeEvent(title: "A", feedName: "F", daysAgo: 0)
        XCTAssertEqual(e1, e2)
    }

    func testInsightReadEvent_NotEqual_DifferentTitle() {
        let e1 = makeEvent(title: "A")
        let e2 = makeEvent(title: "B")
        XCTAssertNotEqual(e1, e2)
    }

    // MARK: - FunStats Codable

    func testFunStats_Codable_RoundTrip() {
        let stats = FunStats(
            totalWordsRead: 5000,
            bookPagesEquivalent: 20,
            longestStreakDays: 3,
            uniqueFeedsRead: 5,
            uniqueCategories: 3,
            busiestDay: ("2026-03-01", 8),
            avgArticlesPerActiveDay: 2.5
        )
        let encoder = JSONEncoder()
        let decoder = JSONDecoder()
        guard let data = try? encoder.encode(stats),
              let decoded = try? decoder.decode(FunStats.self, from: data) else {
            XCTFail("FunStats round-trip failed")
            return
        }
        XCTAssertEqual(decoded.totalWordsRead, 5000)
        XCTAssertEqual(decoded.bookPagesEquivalent, 20)
        XCTAssertEqual(decoded.longestStreakDays, 3)
        XCTAssertEqual(decoded.busiestDay?.date, "2026-03-01")
        XCTAssertEqual(decoded.busiestDay?.count, 8)
    }

    func testFunStats_Codable_NilBusiestDay() {
        let stats = FunStats(
            totalWordsRead: 0, bookPagesEquivalent: 0, longestStreakDays: 0,
            uniqueFeedsRead: 0, uniqueCategories: 0,
            busiestDay: nil, avgArticlesPerActiveDay: 0
        )
        let encoder = JSONEncoder()
        let decoder = JSONDecoder()
        guard let data = try? encoder.encode(stats),
              let decoded = try? decoder.decode(FunStats.self, from: data) else {
            XCTFail("FunStats nil busiestDay round-trip failed")
            return
        }
        XCTAssertNil(decoded.busiestDay)
    }

    // MARK: - Edge Cases

    func testSingleEvent_ProducesReport() {
        let events = [makeEvent()]
        let report = generator.generateWeeklyInsight(from: events)

        XCTAssertEqual(report.totalArticlesRead, 1)
        XCTAssertEqual(report.funStats.uniqueFeedsRead, 1)
        XCTAssertEqual(report.funStats.longestStreakDays, 1)
    }

    func testLargeEventSet() {
        let events = makeSpreadEvents(count: 500,
                                       feeds: ["A","B","C","D","E"],
                                       categories: ["tech","sci","art","biz"],
                                       daysSpread: 7)
        let report = generator.generateWeeklyInsight(from: events)

        XCTAssertEqual(report.totalArticlesRead, 500)
        XCTAssertLessThanOrEqual(report.topFeeds.count, 10)
        XCTAssertLessThanOrEqual(report.peakHours.count, 3)
    }

    func testWeekendWarrior_Personality() {
        // Calendar: weekday 1 = Sunday, 7 = Saturday
        // Make events that land on weekends
        // Find the most recent Sunday
        var events: [InsightReadEvent] = []
        let today = Date()
        let weekday = cal.component(.weekday, from: today)
        // Days to most recent Sunday (weekday 1)
        let sundayOffset = (weekday - 1) % 7
        let saturdayOffset = (weekday + 5) % 7  // weekday 7

        // 6 events on weekend days, 2 on weekdays
        for i in 0..<3 {
            events.append(makeEvent(title: "Sun \(i)", daysAgo: sundayOffset, hour: 12 + i))
        }
        for i in 0..<3 {
            let satOffset = saturdayOffset == 0 ? 7 : saturdayOffset
            events.append(makeEvent(title: "Sat \(i)", daysAgo: satOffset, hour: 12 + i))
        }
        // 2 weekday events
        let monOffset = (weekday + 5) % 7 + 1
        events.append(makeEvent(title: "Mon 1", daysAgo: monOffset, hour: 12))
        events.append(makeEvent(title: "Mon 2", daysAgo: monOffset, hour: 14))

        let report = generator.generateWeeklyInsight(from: events)
        // Weekend events > 50% should give weekendWarrior
        // (may not trigger if night/morning tests fire first)
        if report.personality != .nightOwl && report.personality != .earlyBird {
            XCTAssertEqual(report.personality, .weekendWarrior)
        }
    }

    // MARK: - Notification

    func testNotification_PostedOnGeneration() {
        let expectation = XCTestExpectation(description: "Insight notification posted")
        let observer = NotificationCenter.default.addObserver(
            forName: .readingInsightGenerated,
            object: nil, queue: nil
        ) { _ in
            expectation.fulfill()
        }

        _ = generator.generateWeeklyInsight(from: [makeEvent()])

        wait(for: [expectation], timeout: 1.0)
        NotificationCenter.default.removeObserver(observer)
    }
}
