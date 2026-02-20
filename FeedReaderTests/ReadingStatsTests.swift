//
//  ReadingStatsTests.swift
//  FeedReaderTests
//
//  Tests for ReadingStatsManager — event recording, statistics computation,
//  streaks, hourly distribution, feed breakdown, persistence, edge cases.
//

import XCTest
@testable import FeedReader

class ReadingStatsTests: XCTestCase {
    
    // MARK: - Helpers
    
    private func makeStory(title: String = "Test Story", description: String = "A test description", link: String = "https://example.com/story1") -> Story {
        return Story(title: title, photo: nil, description: description, link: link)!
    }
    
    private func daysAgo(_ days: Int) -> Date {
        return Calendar.current.date(byAdding: .day, value: -days, to: Date())!
    }
    
    private func hoursAgo(_ hours: Int) -> Date {
        return Calendar.current.date(byAdding: .hour, value: -hours, to: Date())!
    }
    
    override func setUp() {
        super.setUp()
        ReadingStatsManager.shared.clearAll()
    }
    
    override func tearDown() {
        ReadingStatsManager.shared.clearAll()
        super.tearDown()
    }
    
    // MARK: - Recording Events
    
    func testRecordRead() {
        let story = makeStory()
        ReadingStatsManager.shared.recordRead(story: story, feedName: "BBC")
        
        XCTAssertEqual(ReadingStatsManager.shared.eventCount, 1)
    }
    
    func testRecordMultipleReads() {
        let story1 = makeStory(link: "https://example.com/1")
        let story2 = makeStory(link: "https://example.com/2")
        
        ReadingStatsManager.shared.recordRead(story: story1, feedName: "BBC")
        ReadingStatsManager.shared.recordRead(story: story2, feedName: "NPR")
        
        XCTAssertEqual(ReadingStatsManager.shared.eventCount, 2)
    }
    
    func testRecordSameStoryMultipleTimes() {
        let story = makeStory()
        ReadingStatsManager.shared.recordRead(story: story, feedName: "BBC")
        ReadingStatsManager.shared.recordRead(story: story, feedName: "BBC")
        
        // Each read is recorded as a separate event
        XCTAssertEqual(ReadingStatsManager.shared.eventCount, 2)
    }
    
    func testRecordEventWithExplicitTimestamp() {
        let yesterday = daysAgo(1)
        ReadingStatsManager.shared.recordEvent(
            link: "https://example.com/1",
            title: "Test",
            feedName: "BBC",
            timestamp: yesterday
        )
        
        XCTAssertEqual(ReadingStatsManager.shared.eventCount, 1)
        XCTAssertEqual(ReadingStatsManager.shared.events.first?.feedName, "BBC")
    }
    
    func testEventsOrderedNewestFirst() {
        ReadingStatsManager.shared.recordEvent(
            link: "https://example.com/old",
            title: "Old",
            feedName: "BBC",
            timestamp: daysAgo(2)
        )
        ReadingStatsManager.shared.recordEvent(
            link: "https://example.com/new",
            title: "New",
            feedName: "BBC",
            timestamp: Date()
        )
        
        XCTAssertEqual(ReadingStatsManager.shared.events.first?.title, "New")
    }
    
    // MARK: - Clear
    
    func testClearAll() {
        let story = makeStory()
        ReadingStatsManager.shared.recordRead(story: story, feedName: "BBC")
        ReadingStatsManager.shared.clearAll()
        
        XCTAssertEqual(ReadingStatsManager.shared.eventCount, 0)
    }
    
    // MARK: - Statistics Computation
    
    func testEmptyStats() {
        let stats = ReadingStatsManager.shared.computeStats()
        
        XCTAssertEqual(stats.totalStoriesRead, 0)
        XCTAssertEqual(stats.readToday, 0)
        XCTAssertEqual(stats.readThisWeek, 0)
        XCTAssertEqual(stats.readThisMonth, 0)
        XCTAssertEqual(stats.dailyAverage, 0)
        XCTAssertEqual(stats.currentStreak, 0)
        XCTAssertEqual(stats.longestStreak, 0)
        XCTAssertNil(stats.mostActiveHour)
        XCTAssertTrue(stats.hourlyDistribution.isEmpty)
        XCTAssertTrue(stats.feedBreakdown.isEmpty)
        XCTAssertNil(stats.firstReadDate)
        XCTAssertEqual(stats.daysTracking, 0)
    }
    
    func testTotalStoriesRead() {
        for i in 0..<5 {
            ReadingStatsManager.shared.recordEvent(
                link: "https://example.com/\(i)",
                title: "Story \(i)",
                feedName: "BBC",
                timestamp: Date()
            )
        }
        
        let stats = ReadingStatsManager.shared.computeStats()
        XCTAssertEqual(stats.totalStoriesRead, 5)
    }
    
    func testReadToday() {
        // Add events today
        ReadingStatsManager.shared.recordEvent(
            link: "https://example.com/today1",
            title: "Today 1",
            feedName: "BBC",
            timestamp: Date()
        )
        
        // Add event yesterday
        ReadingStatsManager.shared.recordEvent(
            link: "https://example.com/yesterday",
            title: "Yesterday",
            feedName: "BBC",
            timestamp: daysAgo(1)
        )
        
        let stats = ReadingStatsManager.shared.computeStats()
        XCTAssertEqual(stats.readToday, 1)
    }
    
    func testReadThisWeek() {
        // Today
        ReadingStatsManager.shared.recordEvent(
            link: "https://example.com/today",
            title: "Today",
            feedName: "BBC",
            timestamp: Date()
        )
        // 3 days ago
        ReadingStatsManager.shared.recordEvent(
            link: "https://example.com/3days",
            title: "3 Days",
            feedName: "BBC",
            timestamp: daysAgo(3)
        )
        // 10 days ago
        ReadingStatsManager.shared.recordEvent(
            link: "https://example.com/10days",
            title: "10 Days",
            feedName: "BBC",
            timestamp: daysAgo(10)
        )
        
        let stats = ReadingStatsManager.shared.computeStats()
        XCTAssertEqual(stats.readThisWeek, 2)
    }
    
    func testReadThisMonth() {
        // Today
        ReadingStatsManager.shared.recordEvent(
            link: "https://example.com/today",
            title: "Today",
            feedName: "BBC",
            timestamp: Date()
        )
        // 15 days ago
        ReadingStatsManager.shared.recordEvent(
            link: "https://example.com/15days",
            title: "15 Days",
            feedName: "BBC",
            timestamp: daysAgo(15)
        )
        // 45 days ago
        ReadingStatsManager.shared.recordEvent(
            link: "https://example.com/45days",
            title: "45 Days",
            feedName: "BBC",
            timestamp: daysAgo(45)
        )
        
        let stats = ReadingStatsManager.shared.computeStats()
        XCTAssertEqual(stats.readThisMonth, 2)
    }
    
    // MARK: - Daily Average
    
    func testDailyAverage() {
        // Record 6 events over 3 days
        for i in 0..<3 {
            ReadingStatsManager.shared.recordEvent(
                link: "https://example.com/a\(i)",
                title: "A\(i)",
                feedName: "BBC",
                timestamp: daysAgo(i)
            )
            ReadingStatsManager.shared.recordEvent(
                link: "https://example.com/b\(i)",
                title: "B\(i)",
                feedName: "BBC",
                timestamp: daysAgo(i)
            )
        }
        
        let stats = ReadingStatsManager.shared.computeStats()
        // 6 events over 3 days = 2.0 avg
        XCTAssertEqual(stats.dailyAverage, 2.0, accuracy: 0.01)
    }
    
    // MARK: - Streaks
    
    func testNoStreak() {
        // Only read 5 days ago — no current streak
        ReadingStatsManager.shared.recordEvent(
            link: "https://example.com/1",
            title: "Test",
            feedName: "BBC",
            timestamp: daysAgo(5)
        )
        
        let stats = ReadingStatsManager.shared.computeStats()
        XCTAssertEqual(stats.currentStreak, 0)
    }
    
    func testOneDayStreak() {
        ReadingStatsManager.shared.recordEvent(
            link: "https://example.com/1",
            title: "Test",
            feedName: "BBC",
            timestamp: Date()
        )
        
        let stats = ReadingStatsManager.shared.computeStats()
        XCTAssertEqual(stats.currentStreak, 1)
    }
    
    func testMultiDayStreak() {
        for i in 0..<4 {
            ReadingStatsManager.shared.recordEvent(
                link: "https://example.com/\(i)",
                title: "Story \(i)",
                feedName: "BBC",
                timestamp: daysAgo(i)
            )
        }
        
        let stats = ReadingStatsManager.shared.computeStats()
        XCTAssertEqual(stats.currentStreak, 4)
    }
    
    func testStreakFromYesterday() {
        // Streak starting from yesterday (today not yet read)
        for i in 1..<4 {
            ReadingStatsManager.shared.recordEvent(
                link: "https://example.com/\(i)",
                title: "Story \(i)",
                feedName: "BBC",
                timestamp: daysAgo(i)
            )
        }
        
        let stats = ReadingStatsManager.shared.computeStats()
        XCTAssertEqual(stats.currentStreak, 3)
    }
    
    func testLongestStreak() {
        // Current: 2 day streak (today + yesterday)
        for i in 0..<2 {
            ReadingStatsManager.shared.recordEvent(
                link: "https://example.com/recent\(i)",
                title: "Recent \(i)",
                feedName: "BBC",
                timestamp: daysAgo(i)
            )
        }
        // Old: 5 day streak (10-14 days ago)
        for i in 10..<15 {
            ReadingStatsManager.shared.recordEvent(
                link: "https://example.com/old\(i)",
                title: "Old \(i)",
                feedName: "BBC",
                timestamp: daysAgo(i)
            )
        }
        
        let stats = ReadingStatsManager.shared.computeStats()
        XCTAssertEqual(stats.currentStreak, 2)
        XCTAssertEqual(stats.longestStreak, 5)
    }
    
    func testMultipleReadsPerDayCountAsOneStreakDay() {
        // Read 3 stories today — should be streak of 1, not 3
        for i in 0..<3 {
            ReadingStatsManager.shared.recordEvent(
                link: "https://example.com/\(i)",
                title: "Story \(i)",
                feedName: "BBC",
                timestamp: Date()
            )
        }
        
        let stats = ReadingStatsManager.shared.computeStats()
        XCTAssertEqual(stats.currentStreak, 1)
    }
    
    // MARK: - Hourly Distribution
    
    func testHourlyDistribution() {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        
        // Add events at specific hours
        let hour9 = calendar.date(byAdding: .hour, value: 9, to: today)!
        let hour14 = calendar.date(byAdding: .hour, value: 14, to: today)!
        
        ReadingStatsManager.shared.recordEvent(
            link: "https://example.com/morning1",
            title: "Morning 1",
            feedName: "BBC",
            timestamp: hour9
        )
        ReadingStatsManager.shared.recordEvent(
            link: "https://example.com/morning2",
            title: "Morning 2",
            feedName: "BBC",
            timestamp: hour9
        )
        ReadingStatsManager.shared.recordEvent(
            link: "https://example.com/afternoon",
            title: "Afternoon",
            feedName: "BBC",
            timestamp: hour14
        )
        
        let stats = ReadingStatsManager.shared.computeStats()
        XCTAssertEqual(stats.hourlyDistribution[9], 2)
        XCTAssertEqual(stats.hourlyDistribution[14], 1)
        XCTAssertEqual(stats.mostActiveHour, 9)
    }
    
    // MARK: - Feed Breakdown
    
    func testFeedBreakdown() {
        ReadingStatsManager.shared.recordEvent(
            link: "https://example.com/bbc1",
            title: "BBC 1",
            feedName: "BBC World News",
            timestamp: Date()
        )
        ReadingStatsManager.shared.recordEvent(
            link: "https://example.com/bbc2",
            title: "BBC 2",
            feedName: "BBC World News",
            timestamp: Date()
        )
        ReadingStatsManager.shared.recordEvent(
            link: "https://example.com/npr1",
            title: "NPR 1",
            feedName: "NPR News",
            timestamp: Date()
        )
        
        let stats = ReadingStatsManager.shared.computeStats()
        XCTAssertEqual(stats.feedBreakdown.count, 2)
        // Sorted by count descending
        XCTAssertEqual(stats.feedBreakdown[0].name, "BBC World News")
        XCTAssertEqual(stats.feedBreakdown[0].count, 2)
        XCTAssertEqual(stats.feedBreakdown[1].name, "NPR News")
        XCTAssertEqual(stats.feedBreakdown[1].count, 1)
    }
    
    func testFeedBreakdownMultipleFeeds() {
        let feeds = ["BBC", "NPR", "TechCrunch", "The Verge"]
        for (i, feed) in feeds.enumerated() {
            for j in 0..<(feeds.count - i) {
                ReadingStatsManager.shared.recordEvent(
                    link: "https://example.com/\(feed)/\(j)",
                    title: "\(feed) \(j)",
                    feedName: feed,
                    timestamp: Date()
                )
            }
        }
        
        let stats = ReadingStatsManager.shared.computeStats()
        XCTAssertEqual(stats.feedBreakdown.count, 4)
        // Should be sorted by count descending
        XCTAssertEqual(stats.feedBreakdown[0].name, "BBC")
        XCTAssertEqual(stats.feedBreakdown[0].count, 4)
    }
    
    // MARK: - First Read Date
    
    func testFirstReadDate() {
        let fiveDaysAgo = daysAgo(5)
        ReadingStatsManager.shared.recordEvent(
            link: "https://example.com/old",
            title: "Old Story",
            feedName: "BBC",
            timestamp: fiveDaysAgo
        )
        ReadingStatsManager.shared.recordEvent(
            link: "https://example.com/new",
            title: "New Story",
            feedName: "BBC",
            timestamp: Date()
        )
        
        let stats = ReadingStatsManager.shared.computeStats()
        XCTAssertNotNil(stats.firstReadDate)
        // First read date should be the earliest event
        let calendar = Calendar.current
        let firstDay = calendar.startOfDay(for: stats.firstReadDate!)
        let fiveDaysAgoDay = calendar.startOfDay(for: fiveDaysAgo)
        XCTAssertEqual(firstDay, fiveDaysAgoDay)
    }
    
    // MARK: - Days Tracking
    
    func testDaysTracking() {
        ReadingStatsManager.shared.recordEvent(
            link: "https://example.com/old",
            title: "Old Story",
            feedName: "BBC",
            timestamp: daysAgo(10)
        )
        
        let stats = ReadingStatsManager.shared.computeStats()
        XCTAssertEqual(stats.daysTracking, 11) // 10 days ago + today = 11 days
    }
    
    func testDaysTrackingSameDay() {
        ReadingStatsManager.shared.recordEvent(
            link: "https://example.com/today",
            title: "Today",
            feedName: "BBC",
            timestamp: Date()
        )
        
        let stats = ReadingStatsManager.shared.computeStats()
        XCTAssertEqual(stats.daysTracking, 1)
    }
    
    // MARK: - Notification
    
    func testNotificationPostedOnRecord() {
        let expectation = self.expectation(forNotification: .readingStatsDidChange, object: nil)
        
        let story = makeStory()
        ReadingStatsManager.shared.recordRead(story: story, feedName: "BBC")
        
        wait(for: [expectation], timeout: 1.0)
    }
    
    func testNotificationPostedOnClear() {
        let story = makeStory()
        ReadingStatsManager.shared.recordRead(story: story, feedName: "BBC")
        
        let expectation = self.expectation(forNotification: .readingStatsDidChange, object: nil)
        
        ReadingStatsManager.shared.clearAll()
        
        wait(for: [expectation], timeout: 1.0)
    }
    
    // MARK: - Pruning
    
    func testPruning() {
        // Record more events than the max
        let max = ReadingStatsManager.maxStoredEvents
        for i in 0..<(max + 100) {
            ReadingStatsManager.shared.recordEvent(
                link: "https://example.com/\(i)",
                title: "Story \(i)",
                feedName: "BBC",
                timestamp: Date()
            )
        }
        
        XCTAssertLessThanOrEqual(ReadingStatsManager.shared.eventCount, max)
    }
    
    // MARK: - Edge Cases
    
    func testStreakWithGap() {
        // Days: today, yesterday, 2 days ago — then gap — 5, 6, 7 days ago
        for i in 0..<3 {
            ReadingStatsManager.shared.recordEvent(
                link: "https://example.com/recent\(i)",
                title: "Recent \(i)",
                feedName: "BBC",
                timestamp: daysAgo(i)
            )
        }
        for i in 5..<8 {
            ReadingStatsManager.shared.recordEvent(
                link: "https://example.com/old\(i)",
                title: "Old \(i)",
                feedName: "BBC",
                timestamp: daysAgo(i)
            )
        }
        
        let stats = ReadingStatsManager.shared.computeStats()
        XCTAssertEqual(stats.currentStreak, 3)
        XCTAssertEqual(stats.longestStreak, 3) // both runs are 3 days
    }
    
    func testEmptyFeedName() {
        ReadingStatsManager.shared.recordEvent(
            link: "https://example.com/1",
            title: "Test",
            feedName: "",
            timestamp: Date()
        )
        
        let stats = ReadingStatsManager.shared.computeStats()
        XCTAssertEqual(stats.feedBreakdown.count, 1)
        XCTAssertEqual(stats.feedBreakdown[0].name, "")
    }
    
    func testStatsWithOnlyOldEvents() {
        // Events only from 60 days ago — not in today/week/month
        ReadingStatsManager.shared.recordEvent(
            link: "https://example.com/old",
            title: "Old Story",
            feedName: "BBC",
            timestamp: daysAgo(60)
        )
        
        let stats = ReadingStatsManager.shared.computeStats()
        XCTAssertEqual(stats.totalStoriesRead, 1)
        XCTAssertEqual(stats.readToday, 0)
        XCTAssertEqual(stats.readThisWeek, 0)
        XCTAssertEqual(stats.readThisMonth, 0)
        XCTAssertEqual(stats.currentStreak, 0)
    }
    
    // MARK: - Story Model: sourceFeedName
    
    func testStorySourceFeedNameDefault() {
        let story = makeStory()
        XCTAssertNil(story.sourceFeedName)
    }
    
    func testStorySourceFeedNameAssignment() {
        let story = makeStory()
        story.sourceFeedName = "BBC World News"
        XCTAssertEqual(story.sourceFeedName, "BBC World News")
    }
    
    func testStorySourceFeedNameEncoding() {
        let story = makeStory()
        story.sourceFeedName = "TechCrunch"
        
        // Encode
        guard let data = try? NSKeyedArchiver.archivedData(withRootObject: story, requiringSecureCoding: true) else {
            XCTFail("Failed to encode story")
            return
        }
        
        // Decode
        guard let decoded = (try? NSKeyedUnarchiver.unarchivedObject(ofClass: Story.self, from: data)) else {
            XCTFail("Failed to decode story")
            return
        }
        
        XCTAssertEqual(decoded.sourceFeedName, "TechCrunch")
    }
    
    func testStorySourceFeedNameNilEncoding() {
        let story = makeStory()
        // sourceFeedName is nil
        
        guard let data = try? NSKeyedArchiver.archivedData(withRootObject: story, requiringSecureCoding: true) else {
            XCTFail("Failed to encode story")
            return
        }
        
        guard let decoded = (try? NSKeyedUnarchiver.unarchivedObject(ofClass: Story.self, from: data)) else {
            XCTFail("Failed to decode story")
            return
        }
        
        XCTAssertNil(decoded.sourceFeedName)
    }
}
