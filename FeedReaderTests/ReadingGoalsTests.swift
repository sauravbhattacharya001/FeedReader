//
//  ReadingGoalsTests.swift
//  FeedReaderTests
//
//  Tests for ReadingGoalsManager — daily/weekly goal setting and progress tracking.
//

import XCTest
@testable import FeedReader

class ReadingGoalsTests: XCTestCase {
    
    override func setUp() {
        super.setUp()
        ReadingGoalsManager.shared.clearGoals()
        ReadingStatsManager.shared.clearAll()
    }
    
    override func tearDown() {
        ReadingGoalsManager.shared.clearGoals()
        ReadingStatsManager.shared.clearAll()
        super.tearDown()
    }
    
    // MARK: - Goal Setting
    
    func testDefaultGoalsAreZero() {
        let goals = ReadingGoalsManager.shared.goals
        XCTAssertEqual(goals.dailyTarget, 0)
        XCTAssertEqual(goals.weeklyTarget, 0)
    }
    
    func testSetDailyGoal() {
        ReadingGoalsManager.shared.setDailyGoal(5)
        XCTAssertEqual(ReadingGoalsManager.shared.goals.dailyTarget, 5)
    }
    
    func testSetWeeklyGoal() {
        ReadingGoalsManager.shared.setWeeklyGoal(20)
        XCTAssertEqual(ReadingGoalsManager.shared.goals.weeklyTarget, 20)
    }
    
    func testNegativeGoalClampedToZero() {
        ReadingGoalsManager.shared.setDailyGoal(-3)
        XCTAssertEqual(ReadingGoalsManager.shared.goals.dailyTarget, 0)
        
        ReadingGoalsManager.shared.setWeeklyGoal(-10)
        XCTAssertEqual(ReadingGoalsManager.shared.goals.weeklyTarget, 0)
    }
    
    func testClearGoals() {
        ReadingGoalsManager.shared.setDailyGoal(10)
        ReadingGoalsManager.shared.setWeeklyGoal(50)
        ReadingGoalsManager.shared.clearGoals()
        
        XCTAssertEqual(ReadingGoalsManager.shared.goals.dailyTarget, 0)
        XCTAssertEqual(ReadingGoalsManager.shared.goals.weeklyTarget, 0)
    }
    
    // MARK: - Progress Tracking
    
    func testProgressWithNoGoals() {
        let progress = ReadingGoalsManager.shared.currentProgress()
        XCTAssertFalse(progress.hasGoals)
        XCTAssertEqual(progress.dailyPercentage, 0)
        XCTAssertEqual(progress.weeklyPercentage, 0)
    }
    
    func testDailyProgressTracking() {
        ReadingGoalsManager.shared.setDailyGoal(3)
        
        // Read 1 story
        ReadingStatsManager.shared.recordEvent(
            link: "https://example.com/1",
            title: "Story 1",
            feedName: "Test Feed",
            timestamp: Date()
        )
        
        let progress = ReadingGoalsManager.shared.currentProgress()
        XCTAssertEqual(progress.dailyRead, 1)
        XCTAssertEqual(progress.dailyTarget, 3)
        XCTAssertEqual(progress.dailyPercentage, 100.0 / 3.0, accuracy: 0.1)
        XCTAssertFalse(progress.dailyAchieved)
    }
    
    func testDailyGoalAchieved() {
        ReadingGoalsManager.shared.setDailyGoal(2)
        
        for i in 1...2 {
            ReadingStatsManager.shared.recordEvent(
                link: "https://example.com/\(i)",
                title: "Story \(i)",
                feedName: "Test Feed",
                timestamp: Date()
            )
        }
        
        let progress = ReadingGoalsManager.shared.currentProgress()
        XCTAssertTrue(progress.dailyAchieved)
        XCTAssertEqual(progress.dailyPercentage, 100.0)
    }
    
    func testWeeklyProgressTracking() {
        ReadingGoalsManager.shared.setWeeklyGoal(10)
        
        for i in 1...5 {
            ReadingStatsManager.shared.recordEvent(
                link: "https://example.com/\(i)",
                title: "Story \(i)",
                feedName: "Test Feed",
                timestamp: Date()
            )
        }
        
        let progress = ReadingGoalsManager.shared.currentProgress()
        XCTAssertEqual(progress.weeklyRead, 5)
        XCTAssertEqual(progress.weeklyTarget, 10)
        XCTAssertEqual(progress.weeklyPercentage, 50.0, accuracy: 0.1)
        XCTAssertFalse(progress.weeklyAchieved)
    }
    
    func testPercentageCappedAt100() {
        ReadingGoalsManager.shared.setDailyGoal(1)
        
        for i in 1...5 {
            ReadingStatsManager.shared.recordEvent(
                link: "https://example.com/\(i)",
                title: "Story \(i)",
                feedName: "Test Feed",
                timestamp: Date()
            )
        }
        
        let progress = ReadingGoalsManager.shared.currentProgress()
        XCTAssertEqual(progress.dailyPercentage, 100.0)
        XCTAssertTrue(progress.dailyAchieved)
    }
    
    // MARK: - Goal Achievement Notification
    
    func testGoalAchievedNotificationPosted() {
        let expectation = self.expectation(forNotification: .readingGoalAchieved, object: nil) { notification in
            let goalType = notification.userInfo?["goalType"] as? String
            return goalType == "daily"
        }
        
        ReadingGoalsManager.shared.setDailyGoal(1)
        ReadingStatsManager.shared.recordEvent(
            link: "https://example.com/1",
            title: "Goal Story",
            feedName: "Test Feed",
            timestamp: Date()
        )
        
        wait(for: [expectation], timeout: 2.0)
    }
    
    // MARK: - Persistence
    
    func testGoalsPersistAcrossReload() {
        ReadingGoalsManager.shared.setDailyGoal(7)
        ReadingGoalsManager.shared.setWeeklyGoal(35)
        ReadingGoalsManager.shared.reload()
        
        XCTAssertEqual(ReadingGoalsManager.shared.goals.dailyTarget, 7)
        XCTAssertEqual(ReadingGoalsManager.shared.goals.weeklyTarget, 35)
    }
}
