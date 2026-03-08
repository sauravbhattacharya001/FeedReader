//
//  ContentCalendarTests.swift
//  FeedReaderTests
//
//  Tests for ContentCalendar publishing pattern analysis.
//

import XCTest
@testable import FeedReader

class ContentCalendarTests: XCTestCase {
    
    var calendar: ContentCalendar!
    var dateCalendar: Calendar!
    
    override func setUp() {
        super.setUp()
        calendar = ContentCalendar()
        dateCalendar = Calendar.current
    }
    
    // MARK: - Helpers
    
    private func makeDate(year: Int = 2026, month: Int = 2, day: Int,
                          hour: Int = 9, minute: Int = 0) -> Date {
        var comps = DateComponents()
        comps.year = year
        comps.month = month
        comps.day = day
        comps.hour = hour
        comps.minute = minute
        comps.timeZone = TimeZone.current
        return dateCalendar.date(from: comps)!
    }
    
    private func makeEvent(feed: String = "https://example.com/feed",
                           feedName: String = "Example",
                           title: String = "Article",
                           date: Date,
                           wordCount: Int = 500) -> PublishEvent {
        return PublishEvent(feedURL: feed, feedName: feedName,
                           articleTitle: title, publishedDate: date,
                           wordCount: wordCount)
    }
    
    /// Generate daily events for a date range.
    private func generateDailyEvents(feedURL: String = "https://daily.com/feed",
                                     feedName: String = "Daily Feed",
                                     startDay: Int = 1, endDay: Int = 28,
                                     hour: Int = 9) -> [PublishEvent] {
        return (startDay...endDay).map { day in
            makeEvent(feed: feedURL, feedName: feedName,
                      title: "Article \(day)", date: makeDate(day: day, hour: hour))
        }
    }
    
    // MARK: - Basic Recording
    
    func testRecordEvent() {
        let event = makeEvent(date: makeDate(day: 1))
        calendar.recordEvent(event)
        XCTAssertEqual(calendar.eventCount, 1)
    }
    
    func testRecordMultipleEvents() {
        let events = [
            makeEvent(title: "A", date: makeDate(day: 1)),
            makeEvent(title: "B", date: makeDate(day: 2)),
            makeEvent(title: "C", date: makeDate(day: 3))
        ]
        calendar.recordEvents(events)
        XCTAssertEqual(calendar.eventCount, 3)
    }
    
    func testClearEvents() {
        calendar.recordEvent(makeEvent(date: makeDate(day: 1)))
        calendar.clearEvents()
        XCTAssertEqual(calendar.eventCount, 0)
    }
    
    func testEventsForFeed() {
        calendar.recordEvent(makeEvent(feed: "https://a.com/feed", date: makeDate(day: 1)))
        calendar.recordEvent(makeEvent(feed: "https://b.com/feed", date: makeDate(day: 2)))
        calendar.recordEvent(makeEvent(feed: "https://a.com/feed", date: makeDate(day: 3)))
        
        let aEvents = calendar.events(forFeed: "https://a.com/feed")
        XCTAssertEqual(aEvents.count, 2)
    }
    
    func testMaxEventsLimit() {
        // Record more than max (internal limit 10000) — just verify it doesn't crash
        let events = (1...100).map { i in
            makeEvent(title: "Article \(i)", date: makeDate(day: (i % 28) + 1))
        }
        calendar.recordEvents(events)
        XCTAssertEqual(calendar.eventCount, 100)
    }
    
    // MARK: - PublishEvent
    
    func testPublishEventNegativeWordCount() {
        let event = PublishEvent(feedURL: "https://x.com", feedName: "X",
                                articleTitle: "T", publishedDate: Date(), wordCount: -5)
        XCTAssertEqual(event.wordCount, 0)
    }
    
    func testPublishEventEquality() {
        let date = makeDate(day: 1)
        let a = PublishEvent(feedURL: "https://x.com", feedName: "X",
                             articleTitle: "T", publishedDate: date, wordCount: 100)
        let b = PublishEvent(feedURL: "https://x.com", feedName: "X",
                             articleTitle: "T", publishedDate: date, wordCount: 100)
        XCTAssertEqual(a, b)
    }
    
    // MARK: - Schedule Analysis
    
    func testAnalyzeEmptyFeed() {
        let result = calendar.analyzeSchedule(forFeed: "https://empty.com/feed")
        XCTAssertNil(result)
    }
    
    func testAnalyzeDailyFeed() {
        let events = generateDailyEvents()
        calendar.recordEvents(events)
        
        let profile = calendar.analyzeSchedule(forFeed: "https://daily.com/feed",
                                               referenceDate: makeDate(day: 28))
        XCTAssertNotNil(profile)
        XCTAssertEqual(profile!.feedName, "Daily Feed")
        XCTAssertEqual(profile!.totalArticles, 28)
        XCTAssertTrue(profile!.avgArticlesPerDay >= 0.8)
        XCTAssertTrue([.daily, .multipleDaily].contains(profile!.cadence),
                       "Expected daily cadence, got \(profile!.cadence)")
    }
    
    func testAnalyzeWeekdayOnlyFeed() {
        // Only Monday-Friday events over 3 weeks
        var events: [PublishEvent] = []
        for week in 0..<3 {
            for dayOffset in [0, 1, 2, 3, 4] { // Mon-Fri
                let day = 2 + (week * 7) + dayOffset // Feb 2 2026 is Monday
                if day <= 28 {
                    events.append(makeEvent(feed: "https://biz.com/feed",
                                            feedName: "Business",
                                            title: "Article \(day)",
                                            date: makeDate(day: day, hour: 8)))
                }
            }
        }
        calendar.recordEvents(events)
        
        let profile = calendar.analyzeSchedule(forFeed: "https://biz.com/feed",
                                               referenceDate: makeDate(day: 28))
        XCTAssertNotNil(profile)
        XCTAssertEqual(profile!.quietDays.isEmpty, false)
    }
    
    func testAnalyzeMultipleDailyFeed() {
        // 3 articles per day
        var events: [PublishEvent] = []
        for day in 1...14 {
            for hour in [8, 12, 17] {
                events.append(makeEvent(feed: "https://news.com/feed",
                                        feedName: "Breaking News",
                                        title: "Article \(day)-\(hour)",
                                        date: makeDate(day: day, hour: hour)))
            }
        }
        calendar.recordEvents(events)
        
        let profile = calendar.analyzeSchedule(forFeed: "https://news.com/feed",
                                               referenceDate: makeDate(day: 14))
        XCTAssertNotNil(profile)
        XCTAssertEqual(profile!.cadence, .multipleDaily)
        XCTAssertGreaterThanOrEqual(profile!.avgArticlesPerDay, 2.0)
    }
    
    func testAnalyzeWeeklyFeed() {
        // One article per week (every Monday)
        let events = [1, 8, 15, 22].map { day in
            makeEvent(feed: "https://weekly.com/feed", feedName: "Weekly Digest",
                      title: "Week \(day)", date: makeDate(day: day, hour: 10))
        }
        calendar.recordEvents(events)
        
        let profile = calendar.analyzeSchedule(forFeed: "https://weekly.com/feed",
                                               referenceDate: makeDate(day: 28))
        XCTAssertNotNil(profile)
        // Weekly: ~0.14 articles/day
        XCTAssertTrue(profile!.avgArticlesPerDay < 0.5)
    }
    
    func testPredictedNextUpdate() {
        let events = generateDailyEvents(startDay: 1, endDay: 10)
        calendar.recordEvents(events)
        
        let profile = calendar.analyzeSchedule(forFeed: "https://daily.com/feed",
                                               referenceDate: makeDate(day: 10))
        XCTAssertNotNil(profile?.predictedNextUpdate)
        
        // Predicted next should be roughly 1 day after last
        if let predicted = profile?.predictedNextUpdate {
            let dayAfterLast = makeDate(day: 11, hour: 9)
            let diff = abs(predicted.timeIntervalSince(dayAfterLast))
            XCTAssertLessThan(diff, 7200, "Predicted next update should be ~1 day after last")
        }
    }
    
    func testPeakHoursDetection() {
        // Articles at 9 AM and 3 PM
        var events: [PublishEvent] = []
        for day in 1...14 {
            events.append(makeEvent(title: "Morning \(day)", date: makeDate(day: day, hour: 9)))
            events.append(makeEvent(title: "Afternoon \(day)", date: makeDate(day: day, hour: 15)))
        }
        calendar.recordEvents(events)
        
        let profile = calendar.analyzeSchedule(forFeed: "https://example.com/feed",
                                               referenceDate: makeDate(day: 14))
        XCTAssertNotNil(profile)
        let peakHourValues = profile!.peakHours.map { $0.hour }
        XCTAssertTrue(peakHourValues.contains(9) || peakHourValues.contains(15))
    }
    
    func testSingleEventFeed() {
        calendar.recordEvent(makeEvent(date: makeDate(day: 15)))
        let profile = calendar.analyzeSchedule(forFeed: "https://example.com/feed",
                                               referenceDate: makeDate(day: 20))
        XCTAssertNotNil(profile)
        XCTAssertEqual(profile!.totalArticles, 1)
    }
    
    // MARK: - Cadence Detection
    
    func testCadenceLabels() {
        XCTAssertEqual(PublishingCadence.daily.rawValue, "Daily")
        XCTAssertEqual(PublishingCadence.multipleDaily.rawValue, "Multiple times daily")
        XCTAssertEqual(PublishingCadence.weekly.rawValue, "Weekly")
        XCTAssertEqual(PublishingCadence.irregular.rawValue, "Irregular")
        XCTAssertEqual(PublishingCadence.inactive.rawValue, "Inactive")
    }
    
    func testCadenceEmojis() {
        XCTAssertFalse(PublishingCadence.daily.emoji.isEmpty)
        XCTAssertFalse(PublishingCadence.multipleDaily.emoji.isEmpty)
        XCTAssertFalse(PublishingCadence.inactive.emoji.isEmpty)
    }
    
    // MARK: - Reading Windows
    
    func testReadingWindowsEmpty() {
        let windows = calendar.findReadingWindows()
        XCTAssertTrue(windows.isEmpty)
    }
    
    func testReadingWindowsDetection() {
        // Articles concentrated at 9 AM and 3 PM
        var events: [PublishEvent] = []
        for day in 1...21 {
            events.append(makeEvent(feed: "https://a.com/feed", feedName: "Feed A",
                                    title: "A-\(day)", date: makeDate(day: day, hour: 9)))
            events.append(makeEvent(feed: "https://b.com/feed", feedName: "Feed B",
                                    title: "B-\(day)", date: makeDate(day: day, hour: 15)))
        }
        calendar.recordEvents(events)
        
        let windows = calendar.findReadingWindows()
        XCTAssertFalse(windows.isEmpty)
        XCTAssertLessThanOrEqual(windows.count, 3)
        
        // First window should be optimal
        if let first = windows.first {
            XCTAssertEqual(first.quality, .optimal)
            XCTAssertGreaterThan(first.expectedNewArticles, 0)
            XCTAssertFalse(first.feedNames.isEmpty)
        }
    }
    
    func testReadingWindowLabels() {
        let window = ReadingWindow(startHour: 9, endHour: 12,
                                   expectedNewArticles: 3.5,
                                   feedNames: ["Feed A"], quality: .optimal)
        XCTAssertEqual(window.label, "9 AM – 12 PM")
    }
    
    func testReadingWindowMidnight() {
        let window = ReadingWindow(startHour: 0, endHour: 3,
                                   expectedNewArticles: 1.0,
                                   feedNames: ["Night Feed"], quality: .fair)
        XCTAssertEqual(window.label, "12 AM – 3 AM")
    }
    
    func testReadingWindowNoon() {
        let window = ReadingWindow(startHour: 12, endHour: 15,
                                   expectedNewArticles: 2.0,
                                   feedNames: ["Lunch Feed"], quality: .good)
        XCTAssertEqual(window.label, "12 PM – 3 PM")
    }
    
    // MARK: - Hour Slot
    
    func testHourSlotLabels() {
        XCTAssertEqual(HourSlot(hour: 0).label, "12 AM")
        XCTAssertEqual(HourSlot(hour: 6).label, "6 AM")
        XCTAssertEqual(HourSlot(hour: 12).label, "12 PM")
        XCTAssertEqual(HourSlot(hour: 15).label, "3 PM")
        XCTAssertEqual(HourSlot(hour: 23).label, "11 PM")
    }
    
    func testHourSlotComparable() {
        XCTAssertTrue(HourSlot(hour: 8) < HourSlot(hour: 14))
        XCTAssertFalse(HourSlot(hour: 14) < HourSlot(hour: 8))
    }
    
    // MARK: - Weekday
    
    func testWeekdayNames() {
        XCTAssertEqual(Weekday.monday.name, "Monday")
        XCTAssertEqual(Weekday.friday.shortName, "Fri")
        XCTAssertEqual(Weekday.sunday.rawValue, 1)
        XCTAssertEqual(Weekday.saturday.rawValue, 7)
    }
    
    func testWeekdayComparable() {
        XCTAssertTrue(Weekday.monday < Weekday.friday)
    }
    
    func testWeekdayAllCases() {
        XCTAssertEqual(Weekday.allCases.count, 7)
    }
    
    // MARK: - Weekly Forecast
    
    func testForecastEmpty() {
        let forecast = calendar.generateWeeklyForecast()
        XCTAssertTrue(forecast.isEmpty)
    }
    
    func testForecastSevenDays() {
        let events = generateDailyEvents()
        calendar.recordEvents(events)
        
        let forecast = calendar.generateWeeklyForecast(startDate: makeDate(month: 3, day: 1))
        XCTAssertEqual(forecast.count, 7)
        
        for day in forecast {
            XCTAssertGreaterThanOrEqual(day.expectedArticleCount, 0)
            XCTAssertNotNil(day.intensity)
        }
    }
    
    func testForecastIntensityLevels() {
        // High volume feed
        var events: [PublishEvent] = []
        for day in 1...28 {
            for hour in [6, 9, 12, 15, 18, 21] {
                events.append(makeEvent(title: "Art \(day)-\(hour)",
                                        date: makeDate(day: day, hour: hour)))
            }
        }
        calendar.recordEvents(events)
        
        let forecast = calendar.generateWeeklyForecast(startDate: makeDate(month: 3, day: 1))
        XCTAssertFalse(forecast.isEmpty)
        
        // Should have some non-light days given high volume
        let nonLight = forecast.filter { $0.intensity != .light }
        XCTAssertFalse(nonLight.isEmpty)
    }
    
    func testContentIntensityEmoji() {
        XCTAssertEqual(ContentIntensity.light.emoji, "🟢")
        XCTAssertEqual(ContentIntensity.moderate.emoji, "🟡")
        XCTAssertEqual(ContentIntensity.heavy.emoji, "🟠")
        XCTAssertEqual(ContentIntensity.veryHeavy.emoji, "🔴")
    }
    
    // MARK: - Full Report
    
    func testReportEmpty() {
        let report = calendar.generateReport()
        XCTAssertEqual(report.totalFeedsAnalyzed, 0)
        XCTAssertTrue(report.feedProfiles.isEmpty)
        XCTAssertTrue(report.readingWindows.isEmpty)
    }
    
    func testReportMultipleFeeds() {
        let feedA = generateDailyEvents(feedURL: "https://a.com/feed",
                                         feedName: "Feed A", hour: 8)
        let feedB = (1...28).filter { $0 % 7 == 0 }.map { day in
            makeEvent(feed: "https://b.com/feed", feedName: "Feed B",
                      title: "Weekly \(day)", date: makeDate(day: day, hour: 14))
        }
        calendar.recordEvents(feedA + feedB)
        
        let report = calendar.generateReport(referenceDate: makeDate(day: 28))
        XCTAssertEqual(report.totalFeedsAnalyzed, 2)
        XCTAssertEqual(report.feedProfiles.count, 2)
        XCTAssertNotNil(report.busiestDay)
        XCTAssertNotNil(report.busiestHour)
        XCTAssertGreaterThan(report.overallAvgArticlesPerDay, 0)
        
        // Profiles sorted by avg articles per day (descending)
        if report.feedProfiles.count == 2 {
            XCTAssertGreaterThanOrEqual(report.feedProfiles[0].avgArticlesPerDay,
                                         report.feedProfiles[1].avgArticlesPerDay)
        }
    }
    
    func testReportBusiestQuietestDay() {
        // Only weekday events
        var events: [PublishEvent] = []
        for day in [2, 3, 4, 5, 6, 9, 10, 11, 12, 13] { // Weekdays only
            let count = day % 3 + 1 // Vary count
            for i in 0..<count {
                events.append(makeEvent(title: "Art \(day)-\(i)",
                                        date: makeDate(day: day, hour: 9 + i)))
            }
        }
        calendar.recordEvents(events)
        
        let report = calendar.generateReport(referenceDate: makeDate(day: 15))
        XCTAssertNotNil(report.busiestDay)
        XCTAssertNotNil(report.quietestDay)
    }
    
    // MARK: - JSON Export
    
    func testExportJSON() {
        let events = generateDailyEvents(startDay: 1, endDay: 7)
        calendar.recordEvents(events)
        
        let json = calendar.exportJSON(referenceDate: makeDate(day: 7))
        XCTAssertNotNil(json)
        XCTAssertTrue(json!.contains("feedProfiles"))
        XCTAssertTrue(json!.contains("readingWindows"))
        XCTAssertTrue(json!.contains("weeklyForecast"))
    }
    
    func testExportJSONEmpty() {
        let json = calendar.exportJSON()
        XCTAssertNotNil(json)
        XCTAssertTrue(json!.contains("totalFeedsAnalyzed"))
    }
    
    // MARK: - Edge Cases
    
    func testMixedFeedsAnalysis() {
        // 3 feeds with different cadences
        let daily = generateDailyEvents(feedURL: "https://daily.com/feed", feedName: "Daily")
        let weekly = [1, 8, 15, 22].map { day in
            makeEvent(feed: "https://weekly.com/feed", feedName: "Weekly",
                      title: "W-\(day)", date: makeDate(day: day, hour: 14))
        }
        let sporadic = [3, 11, 19].map { day in
            makeEvent(feed: "https://sporadic.com/feed", feedName: "Sporadic",
                      title: "S-\(day)", date: makeDate(day: day, hour: 20))
        }
        
        calendar.recordEvents(daily + weekly + sporadic)
        
        let report = calendar.generateReport(referenceDate: makeDate(day: 28))
        XCTAssertEqual(report.totalFeedsAnalyzed, 3)
        
        // Daily feed should have highest avg
        if let firstProfile = report.feedProfiles.first {
            XCTAssertEqual(firstProfile.feedName, "Daily")
        }
    }
    
    func testAnalyzeScheduleWithReferenceDate() {
        let events = generateDailyEvents(startDay: 1, endDay: 5)
        calendar.recordEvents(events)
        
        // Reference date far in the future should lower avg articles per day
        let farFuture = makeDate(month: 6, day: 1)
        let profile = calendar.analyzeSchedule(forFeed: "https://daily.com/feed",
                                               referenceDate: farFuture)
        XCTAssertNotNil(profile)
        XCTAssertLessThan(profile!.avgArticlesPerDay, 1.0)
    }
    
    func testReadingWindowQualityValues() {
        XCTAssertEqual(ReadingWindowQuality.optimal.rawValue, "Optimal")
        XCTAssertEqual(ReadingWindowQuality.good.rawValue, "Good")
        XCTAssertEqual(ReadingWindowQuality.fair.rawValue, "Fair")
    }
    
    func testDailyForecastBusyAndQuietFeeds() {
        let feedA = generateDailyEvents(feedURL: "https://a.com/feed", feedName: "Busy Feed")
        // Feed B only publishes on day 1
        let feedB = [makeEvent(feed: "https://b.com/feed", feedName: "Quiet Feed",
                               title: "One", date: makeDate(day: 1, hour: 12))]
        calendar.recordEvents(feedA + feedB)
        
        let forecast = calendar.generateWeeklyForecast(startDate: makeDate(month: 3, day: 1))
        XCTAssertFalse(forecast.isEmpty)
        
        // At least some forecasts should mention feeds
        let hasBusy = forecast.contains { !$0.busyFeeds.isEmpty }
        XCTAssertTrue(hasBusy)
    }
    
    func testAvgIntervalHours() {
        // Articles every 12 hours
        var events: [PublishEvent] = []
        for day in 1...7 {
            events.append(makeEvent(title: "AM \(day)", date: makeDate(day: day, hour: 6)))
            events.append(makeEvent(title: "PM \(day)", date: makeDate(day: day, hour: 18)))
        }
        calendar.recordEvents(events)
        
        let profile = calendar.analyzeSchedule(forFeed: "https://example.com/feed",
                                               referenceDate: makeDate(day: 7))
        XCTAssertNotNil(profile)
        // Average interval should be roughly 12 hours
        XCTAssertGreaterThan(profile!.avgIntervalHours, 8)
        XCTAssertLessThan(profile!.avgIntervalHours, 16)
    }
    
    func testNotificationName() {
        XCTAssertEqual(Notification.Name.contentCalendarDidUpdate.rawValue,
                       "ContentCalendarDidUpdateNotification")
    }
}
