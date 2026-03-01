//
//  DigestGeneratorTests.swift
//  FeedReaderTests
//
//  Tests for the DigestGenerator reading digest feature.
//

import XCTest
@testable import FeedReader

class DigestGeneratorTests: XCTestCase {
    
    var generator: DigestGenerator!
    
    override func setUp() {
        super.setUp()
        generator = DigestGenerator()
    }
    
    // MARK: - Test Helpers
    
    private func makeEntry(title: String = "Test Article", link: String = "https://example.com/1",
                           feedName: String = "Test Feed", readAt: Date = Date(),
                           timeSpent: Double = 120, visitCount: Int = 1,
                           scrollProgress: Double = 0.8) -> HistoryEntry {
        return HistoryEntry(link: link, title: title, feedName: feedName,
                            readAt: readAt, visitCount: visitCount,
                            scrollProgress: scrollProgress, timeSpentSeconds: timeSpent)
    }
    
    private func daysAgo(_ days: Int, from now: Date = Date()) -> Date {
        return Calendar.current.date(byAdding: .day, value: -days, to: now)!
    }
    
    private func hoursAgo(_ hours: Int, from now: Date = Date()) -> Date {
        return Calendar.current.date(byAdding: .hour, value: -hours, to: now)!
    }
    
    // MARK: - DigestPeriod Tests
    
    func testPeriodLabel_Today() {
        XCTAssertEqual(DigestPeriod.today.label, "Today")
    }
    
    func testPeriodLabel_Yesterday() {
        XCTAssertEqual(DigestPeriod.yesterday.label, "Yesterday")
    }
    
    func testPeriodLabel_ThisWeek() {
        XCTAssertEqual(DigestPeriod.thisWeek.label, "This Week")
    }
    
    func testPeriodLabel_LastWeek() {
        XCTAssertEqual(DigestPeriod.lastWeek.label, "Last Week")
    }
    
    func testPeriodLabel_ThisMonth() {
        XCTAssertEqual(DigestPeriod.thisMonth.label, "This Month")
    }
    
    func testPeriodLabel_Last7Days() {
        XCTAssertEqual(DigestPeriod.last7Days.label, "Last 7 Days")
    }
    
    func testPeriodLabel_Last30Days() {
        XCTAssertEqual(DigestPeriod.last30Days.label, "Last 30 Days")
    }
    
    func testPeriodLabel_Custom() {
        XCTAssertEqual(DigestPeriod.custom.label, "Custom")
    }
    
    func testPeriodDateRange_Today_StartsAtMidnight() {
        let now = Date()
        let (start, end) = DigestPeriod.today.dateRange(relativeTo: now)
        let midnight = Calendar.current.startOfDay(for: now)
        XCTAssertEqual(start, midnight)
        XCTAssertEqual(end, now)
    }
    
    func testPeriodDateRange_Yesterday_FullDay() {
        let now = Date()
        let (start, end) = DigestPeriod.yesterday.dateRange(relativeTo: now)
        let todayStart = Calendar.current.startOfDay(for: now)
        let yesterdayStart = Calendar.current.date(byAdding: .day, value: -1, to: todayStart)!
        XCTAssertEqual(start, yesterdayStart)
        XCTAssertEqual(end, todayStart)
    }
    
    func testPeriodDateRange_Last7Days_SpansCorrectly() {
        let now = Date()
        let (start, end) = DigestPeriod.last7Days.dateRange(relativeTo: now)
        let expected = Calendar.current.date(byAdding: .day, value: -7, to: now)!
        XCTAssertEqual(start.timeIntervalSince1970, expected.timeIntervalSince1970, accuracy: 1.0)
        XCTAssertEqual(end, now)
    }
    
    func testPeriodDateRange_Last30Days_SpansCorrectly() {
        let now = Date()
        let (start, _) = DigestPeriod.last30Days.dateRange(relativeTo: now)
        let expected = Calendar.current.date(byAdding: .day, value: -30, to: now)!
        XCTAssertEqual(start.timeIntervalSince1970, expected.timeIntervalSince1970, accuracy: 1.0)
    }
    
    // MARK: - DigestFormat Tests
    
    func testFormat_PlainText() {
        XCTAssertEqual(DigestFormat.plainText.label, "Plain Text")
        XCTAssertEqual(DigestFormat.plainText.fileExtension, "txt")
    }
    
    func testFormat_Markdown() {
        XCTAssertEqual(DigestFormat.markdown.label, "Markdown")
        XCTAssertEqual(DigestFormat.markdown.fileExtension, "md")
    }
    
    func testFormat_HTML() {
        XCTAssertEqual(DigestFormat.html.label, "HTML")
        XCTAssertEqual(DigestFormat.html.fileExtension, "html")
    }
    
    // MARK: - DigestOptions Tests
    
    func testOptions_DefaultValues() {
        let opts = DigestOptions()
        XCTAssertEqual(opts.period, .last7Days)
        XCTAssertEqual(opts.format, .markdown)
        XCTAssertTrue(opts.groupByFeed)
        XCTAssertTrue(opts.includeReadingTime)
        XCTAssertTrue(opts.includeStats)
        XCTAssertEqual(opts.maxArticles, 0)
    }
    
    func testOptions_EffectiveDateRange_UsesCustomWhenSet() {
        var opts = DigestOptions()
        opts.period = .custom
        let start = daysAgo(14)
        let end = daysAgo(7)
        opts.customStart = start
        opts.customEnd = end
        let (s, e) = opts.effectiveDateRange()
        XCTAssertEqual(s, start)
        XCTAssertEqual(e, end)
    }
    
    func testOptions_EffectiveDateRange_FallsToPeriodWhenNoCustom() {
        var opts = DigestOptions()
        opts.period = .last7Days
        let now = Date()
        let (start, _) = opts.effectiveDateRange(relativeTo: now)
        let expected = Calendar.current.date(byAdding: .day, value: -7, to: now)!
        XCTAssertEqual(start.timeIntervalSince1970, expected.timeIntervalSince1970, accuracy: 1.0)
    }
    
    // MARK: - DigestArticle Tests
    
    func testArticle_ReadingTimeLabel_LessThan60() {
        let article = DigestArticle(title: "T", link: "L", feedName: "F",
                                    readAt: Date(), timeSpentSeconds: 30,
                                    visitCount: 1, scrollProgress: 0.5)
        XCTAssertEqual(article.readingTimeLabel, "<1 min")
    }
    
    func testArticle_ReadingTimeLabel_Minutes() {
        let article = DigestArticle(title: "T", link: "L", feedName: "F",
                                    readAt: Date(), timeSpentSeconds: 300,
                                    visitCount: 1, scrollProgress: 0.5)
        XCTAssertEqual(article.readingTimeLabel, "5 min")
    }
    
    func testArticle_ReadingTimeLabel_Hours() {
        let article = DigestArticle(title: "T", link: "L", feedName: "F",
                                    readAt: Date(), timeSpentSeconds: 3900,
                                    visitCount: 1, scrollProgress: 0.5)
        XCTAssertEqual(article.readingTimeLabel, "1h 5m")
    }
    
    func testArticle_ReadingTimeLabel_ExactHour() {
        let article = DigestArticle(title: "T", link: "L", feedName: "F",
                                    readAt: Date(), timeSpentSeconds: 3600,
                                    visitCount: 1, scrollProgress: 0.5)
        XCTAssertEqual(article.readingTimeLabel, "1h")
    }
    
    func testArticle_ProgressLabel() {
        let article = DigestArticle(title: "T", link: "L", feedName: "F",
                                    readAt: Date(), timeSpentSeconds: 60,
                                    visitCount: 1, scrollProgress: 0.75)
        XCTAssertEqual(article.progressLabel, "75%")
    }
    
    func testArticle_ProgressLabel_Zero() {
        let article = DigestArticle(title: "T", link: "L", feedName: "F",
                                    readAt: Date(), timeSpentSeconds: 60,
                                    visitCount: 1, scrollProgress: 0.0)
        XCTAssertEqual(article.progressLabel, "0%")
    }
    
    func testArticle_ProgressLabel_Full() {
        let article = DigestArticle(title: "T", link: "L", feedName: "F",
                                    readAt: Date(), timeSpentSeconds: 60,
                                    visitCount: 1, scrollProgress: 1.0)
        XCTAssertEqual(article.progressLabel, "100%")
    }
    
    // MARK: - FeedGroup Tests
    
    func testFeedGroup_TotalTimeLabel_Minutes() {
        let group = FeedGroup(feedName: "Test", articles: [], totalTimeSeconds: 600)
        XCTAssertEqual(group.totalTimeLabel, "10 min")
    }
    
    func testFeedGroup_TotalTimeLabel_LessThanMinute() {
        let group = FeedGroup(feedName: "Test", articles: [], totalTimeSeconds: 30)
        XCTAssertEqual(group.totalTimeLabel, "<1 min")
    }
    
    func testFeedGroup_TotalTimeLabel_HoursAndMinutes() {
        let group = FeedGroup(feedName: "Test", articles: [], totalTimeSeconds: 5400)
        XCTAssertEqual(group.totalTimeLabel, "1h 30m")
    }
    
    // MARK: - DigestResult Tests
    
    func testDigestResult_IsEmpty_WhenNoArticles() {
        let result = DigestResult(title: "T", periodLabel: "P", dateRangeLabel: "D",
                                  generatedAt: Date(), totalArticles: 0, totalFeeds: 0,
                                  totalReadingTimeSeconds: 0, feedGroups: [],
                                  formattedOutput: "", format: .markdown)
        XCTAssertTrue(result.isEmpty)
    }
    
    func testDigestResult_IsNotEmpty_WhenHasArticles() {
        let result = DigestResult(title: "T", periodLabel: "P", dateRangeLabel: "D",
                                  generatedAt: Date(), totalArticles: 5, totalFeeds: 2,
                                  totalReadingTimeSeconds: 600, feedGroups: [],
                                  formattedOutput: "", format: .markdown)
        XCTAssertFalse(result.isEmpty)
    }
    
    func testDigestResult_ReadingTimeLabel() {
        let result = DigestResult(title: "T", periodLabel: "P", dateRangeLabel: "D",
                                  generatedAt: Date(), totalArticles: 1, totalFeeds: 1,
                                  totalReadingTimeSeconds: 3660, feedGroups: [],
                                  formattedOutput: "", format: .markdown)
        XCTAssertEqual(result.totalReadingTimeLabel, "1h 1m")
    }
    
    // MARK: - Generation — Empty Input
    
    func testGenerate_EmptyEntries_ReturnsEmptyResult() {
        let result = generator.generate(from: [])
        XCTAssertTrue(result.isEmpty)
        XCTAssertEqual(result.totalArticles, 0)
        XCTAssertEqual(result.totalFeeds, 0)
    }
    
    func testGenerate_EmptyEntries_HasFormattedOutput() {
        let result = generator.generate(from: [])
        XCTAssertFalse(result.formattedOutput.isEmpty)
    }
    
    // MARK: - Generation — Filtering
    
    func testGenerate_FiltersToDateRange() {
        let now = Date()
        let entries = [
            makeEntry(title: "Recent", readAt: hoursAgo(2, from: now)),
            makeEntry(title: "Old", link: "https://old.com", readAt: daysAgo(30, from: now)),
        ]
        var opts = DigestOptions()
        opts.period = .last7Days
        let result = generator.generate(from: entries, options: opts, now: now)
        XCTAssertEqual(result.totalArticles, 1)
    }
    
    func testGenerate_ExcludesEntriesOutsideRange() {
        let now = Date()
        let entries = [
            makeEntry(title: "Ancient", readAt: daysAgo(60, from: now)),
        ]
        var opts = DigestOptions()
        opts.period = .last7Days
        let result = generator.generate(from: entries, options: opts, now: now)
        XCTAssertTrue(result.isEmpty)
    }
    
    // MARK: - Generation — Sorting
    
    func testGenerate_SortNewestFirst() {
        let now = Date()
        let entries = [
            makeEntry(title: "Oldest", link: "https://1.com", readAt: hoursAgo(5, from: now)),
            makeEntry(title: "Newest", link: "https://2.com", readAt: hoursAgo(1, from: now)),
            makeEntry(title: "Middle", link: "https://3.com", readAt: hoursAgo(3, from: now)),
        ]
        var opts = DigestOptions()
        opts.period = .today
        opts.sortOrder = .newestFirst
        opts.groupByFeed = false
        let result = generator.generate(from: entries, options: opts, now: now)
        XCTAssertEqual(result.feedGroups.first?.articles.first?.title, "Newest")
        XCTAssertEqual(result.feedGroups.first?.articles.last?.title, "Oldest")
    }
    
    func testGenerate_SortOldestFirst() {
        let now = Date()
        let entries = [
            makeEntry(title: "Newest", link: "https://2.com", readAt: hoursAgo(1, from: now)),
            makeEntry(title: "Oldest", link: "https://1.com", readAt: hoursAgo(5, from: now)),
        ]
        var opts = DigestOptions()
        opts.period = .today
        opts.sortOrder = .oldestFirst
        opts.groupByFeed = false
        let result = generator.generate(from: entries, options: opts, now: now)
        XCTAssertEqual(result.feedGroups.first?.articles.first?.title, "Oldest")
    }
    
    func testGenerate_SortByTimeSpent() {
        let now = Date()
        let entries = [
            makeEntry(title: "Short", link: "https://1.com", readAt: hoursAgo(1, from: now), timeSpent: 60),
            makeEntry(title: "Long", link: "https://2.com", readAt: hoursAgo(2, from: now), timeSpent: 600),
        ]
        var opts = DigestOptions()
        opts.period = .today
        opts.sortOrder = .mostTimeSpent
        opts.groupByFeed = false
        let result = generator.generate(from: entries, options: opts, now: now)
        XCTAssertEqual(result.feedGroups.first?.articles.first?.title, "Long")
    }
    
    func testGenerate_SortAlphabetical() {
        let now = Date()
        let entries = [
            makeEntry(title: "Zebra", link: "https://1.com", readAt: hoursAgo(1, from: now)),
            makeEntry(title: "Apple", link: "https://2.com", readAt: hoursAgo(2, from: now)),
        ]
        var opts = DigestOptions()
        opts.period = .today
        opts.sortOrder = .alphabetical
        opts.groupByFeed = false
        let result = generator.generate(from: entries, options: opts, now: now)
        XCTAssertEqual(result.feedGroups.first?.articles.first?.title, "Apple")
    }
    
    // MARK: - Generation — Grouping
    
    func testGenerate_GroupByFeed() {
        let now = Date()
        let entries = [
            makeEntry(title: "A1", link: "https://1.com", feedName: "Feed A", readAt: hoursAgo(1, from: now)),
            makeEntry(title: "B1", link: "https://2.com", feedName: "Feed B", readAt: hoursAgo(2, from: now)),
            makeEntry(title: "A2", link: "https://3.com", feedName: "Feed A", readAt: hoursAgo(3, from: now)),
        ]
        var opts = DigestOptions()
        opts.period = .today
        opts.groupByFeed = true
        let result = generator.generate(from: entries, options: opts, now: now)
        XCTAssertEqual(result.feedGroups.count, 2)
        // Feed A has more articles, should be first
        XCTAssertEqual(result.feedGroups.first?.feedName, "Feed A")
        XCTAssertEqual(result.feedGroups.first?.articles.count, 2)
    }
    
    func testGenerate_NoGrouping_SingleGroup() {
        let now = Date()
        let entries = [
            makeEntry(title: "A1", link: "https://1.com", feedName: "Feed A", readAt: hoursAgo(1, from: now)),
            makeEntry(title: "B1", link: "https://2.com", feedName: "Feed B", readAt: hoursAgo(2, from: now)),
        ]
        var opts = DigestOptions()
        opts.period = .today
        opts.groupByFeed = false
        let result = generator.generate(from: entries, options: opts, now: now)
        XCTAssertEqual(result.feedGroups.count, 1)
        XCTAssertEqual(result.feedGroups.first?.feedName, "All Articles")
        XCTAssertEqual(result.feedGroups.first?.articles.count, 2)
    }
    
    // MARK: - Generation — Max Articles
    
    func testGenerate_MaxArticles_Limits() {
        let now = Date()
        let entries = (0..<10).map { i in
            makeEntry(title: "Article \(i)", link: "https://\(i).com", readAt: hoursAgo(i + 1, from: now))
        }
        var opts = DigestOptions()
        opts.period = .today
        opts.maxArticles = 3
        opts.groupByFeed = false
        let result = generator.generate(from: entries, options: opts, now: now)
        XCTAssertEqual(result.totalArticles, 3)
    }
    
    func testGenerate_MaxArticles_Zero_NoLimit() {
        let now = Date()
        let entries = (0..<5).map { i in
            makeEntry(title: "Article \(i)", link: "https://\(i).com", readAt: hoursAgo(i + 1, from: now))
        }
        var opts = DigestOptions()
        opts.period = .today
        opts.maxArticles = 0
        opts.groupByFeed = false
        let result = generator.generate(from: entries, options: opts, now: now)
        XCTAssertEqual(result.totalArticles, 5)
    }
    
    // MARK: - Generation — Stats
    
    func testGenerate_ComputesTotalReadingTime() {
        let now = Date()
        let entries = [
            makeEntry(title: "A", link: "https://1.com", readAt: hoursAgo(1, from: now), timeSpent: 120),
            makeEntry(title: "B", link: "https://2.com", readAt: hoursAgo(2, from: now), timeSpent: 180),
        ]
        var opts = DigestOptions()
        opts.period = .today
        let result = generator.generate(from: entries, options: opts, now: now)
        XCTAssertEqual(result.totalReadingTimeSeconds, 300, accuracy: 0.1)
    }
    
    func testGenerate_CountsUniqueFeeds() {
        let now = Date()
        let entries = [
            makeEntry(title: "A", link: "https://1.com", feedName: "F1", readAt: hoursAgo(1, from: now)),
            makeEntry(title: "B", link: "https://2.com", feedName: "F2", readAt: hoursAgo(2, from: now)),
            makeEntry(title: "C", link: "https://3.com", feedName: "F1", readAt: hoursAgo(3, from: now)),
        ]
        var opts = DigestOptions()
        opts.period = .today
        let result = generator.generate(from: entries, options: opts, now: now)
        XCTAssertEqual(result.totalFeeds, 2)
    }
    
    // MARK: - Markdown Output
    
    func testMarkdown_ContainsTitle() {
        let now = Date()
        let entries = [makeEntry(readAt: hoursAgo(1, from: now))]
        var opts = DigestOptions()
        opts.period = .today
        opts.format = .markdown
        let result = generator.generate(from: entries, options: opts, now: now)
        XCTAssertTrue(result.formattedOutput.contains("# 📖 Reading Digest"))
    }
    
    func testMarkdown_ContainsArticleLink() {
        let now = Date()
        let entries = [makeEntry(title: "Great Article", link: "https://great.com", readAt: hoursAgo(1, from: now))]
        var opts = DigestOptions()
        opts.period = .today
        opts.format = .markdown
        let result = generator.generate(from: entries, options: opts, now: now)
        XCTAssertTrue(result.formattedOutput.contains("[Great Article](https://great.com)"))
    }
    
    func testMarkdown_ContainsOverview() {
        let now = Date()
        let entries = [makeEntry(readAt: hoursAgo(1, from: now))]
        var opts = DigestOptions()
        opts.period = .today
        opts.format = .markdown
        opts.includeStats = true
        let result = generator.generate(from: entries, options: opts, now: now)
        XCTAssertTrue(result.formattedOutput.contains("## 📊 Overview"))
    }
    
    func testMarkdown_ExcludesOverview_WhenDisabled() {
        let now = Date()
        let entries = [makeEntry(readAt: hoursAgo(1, from: now))]
        var opts = DigestOptions()
        opts.period = .today
        opts.format = .markdown
        opts.includeStats = false
        let result = generator.generate(from: entries, options: opts, now: now)
        XCTAssertFalse(result.formattedOutput.contains("## 📊 Overview"))
    }
    
    func testMarkdown_ContainsReadingTime() {
        let now = Date()
        let entries = [makeEntry(readAt: hoursAgo(1, from: now), timeSpent: 300)]
        var opts = DigestOptions()
        opts.period = .today
        opts.format = .markdown
        opts.includeReadingTime = true
        let result = generator.generate(from: entries, options: opts, now: now)
        XCTAssertTrue(result.formattedOutput.contains("⏱ 5 min"))
    }
    
    func testMarkdown_Empty_ShowsMessage() {
        let result = generator.generate(from: [])
        XCTAssertTrue(result.formattedOutput.contains("No articles read"))
    }
    
    // MARK: - Plain Text Output
    
    func testPlainText_ContainsTitle() {
        let now = Date()
        let entries = [makeEntry(readAt: hoursAgo(1, from: now))]
        var opts = DigestOptions()
        opts.period = .today
        opts.format = .plainText
        let result = generator.generate(from: entries, options: opts, now: now)
        XCTAssertTrue(result.formattedOutput.contains("READING DIGEST"))
    }
    
    func testPlainText_ContainsSeparator() {
        let now = Date()
        let entries = [makeEntry(readAt: hoursAgo(1, from: now))]
        var opts = DigestOptions()
        opts.format = .plainText
        opts.period = .today
        let result = generator.generate(from: entries, options: opts, now: now)
        XCTAssertTrue(result.formattedOutput.contains("========"))
    }
    
    func testPlainText_ContainsArticleTitle() {
        let now = Date()
        let entries = [makeEntry(title: "My Article", readAt: hoursAgo(1, from: now))]
        var opts = DigestOptions()
        opts.format = .plainText
        opts.period = .today
        let result = generator.generate(from: entries, options: opts, now: now)
        XCTAssertTrue(result.formattedOutput.contains("My Article"))
    }
    
    // MARK: - HTML Output
    
    func testHTML_ContainsDoctype() {
        let now = Date()
        let entries = [makeEntry(readAt: hoursAgo(1, from: now))]
        var opts = DigestOptions()
        opts.format = .html
        opts.period = .today
        let result = generator.generate(from: entries, options: opts, now: now)
        XCTAssertTrue(result.formattedOutput.contains("<!DOCTYPE html>"))
    }
    
    func testHTML_ContainsStyle() {
        let now = Date()
        let entries = [makeEntry(readAt: hoursAgo(1, from: now))]
        var opts = DigestOptions()
        opts.format = .html
        opts.period = .today
        let result = generator.generate(from: entries, options: opts, now: now)
        XCTAssertTrue(result.formattedOutput.contains("<style>"))
    }
    
    func testHTML_EscapesSpecialChars() {
        let now = Date()
        let entries = [makeEntry(title: "A <b>Bold</b> & \"Quoted\" Title",
                                 readAt: hoursAgo(1, from: now))]
        var opts = DigestOptions()
        opts.format = .html
        opts.period = .today
        let result = generator.generate(from: entries, options: opts, now: now)
        XCTAssertTrue(result.formattedOutput.contains("&lt;b&gt;"))
        XCTAssertTrue(result.formattedOutput.contains("&amp;"))
        XCTAssertTrue(result.formattedOutput.contains("&quot;"))
    }
    
    func testHTML_ContainsArticleLink() {
        let now = Date()
        let entries = [makeEntry(title: "Test", link: "https://example.com",
                                 readAt: hoursAgo(1, from: now))]
        var opts = DigestOptions()
        opts.format = .html
        opts.period = .today
        let result = generator.generate(from: entries, options: opts, now: now)
        XCTAssertTrue(result.formattedOutput.contains("href=\"https://example.com\""))
    }
    
    func testHTML_Empty_ShowsMessage() {
        var opts = DigestOptions()
        opts.format = .html
        let result = generator.generate(from: [], options: opts)
        XCTAssertTrue(result.formattedOutput.contains("No articles read"))
    }
    
    // MARK: - Result Metadata
    
    func testResult_HasCorrectFormat() {
        var opts = DigestOptions()
        opts.format = .html
        let result = generator.generate(from: [], options: opts)
        XCTAssertEqual(result.format, .html)
    }
    
    func testResult_HasPeriodLabel() {
        var opts = DigestOptions()
        opts.period = .thisMonth
        let result = generator.generate(from: [], options: opts)
        XCTAssertEqual(result.periodLabel, "This Month")
    }
    
    func testResult_Title_IncludesPeriod() {
        var opts = DigestOptions()
        opts.period = .thisWeek
        let result = generator.generate(from: [], options: opts)
        XCTAssertTrue(result.title.contains("This Week"))
    }
    
    func testResult_HasGeneratedAt() {
        let now = Date()
        let result = generator.generate(from: [], now: now)
        XCTAssertEqual(result.generatedAt, now)
    }
    
    func testResult_DateRangeLabel_NotEmpty() {
        let result = generator.generate(from: [])
        XCTAssertFalse(result.dateRangeLabel.isEmpty)
    }
    
    // MARK: - CaseIterable
    
    func testDigestPeriod_AllCases() {
        XCTAssertEqual(DigestPeriod.allCases.count, 8)
    }
    
    func testDigestFormat_AllCases() {
        XCTAssertEqual(DigestFormat.allCases.count, 3)
    }
}
