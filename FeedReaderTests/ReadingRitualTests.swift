//
//  ReadingRitualTests.swift
//  FeedReaderTests
//
//  Tests for ReadingRitualManager, RitualSchedule, and related models.
//

import XCTest
@testable import FeedReader

// MARK: - RitualSchedule Tests

class RitualScheduleTests: XCTestCase {

    func testWeekdaySchedule() {
        let schedule = RitualSchedule.weekdays
        XCTAssertEqual(schedule.activeDays, [2, 3, 4, 5, 6])
        XCTAssertEqual(schedule.startHour, 7)
        XCTAssertEqual(schedule.endHour, 9)
    }

    func testWeekendSchedule() {
        let schedule = RitualSchedule.weekends
        XCTAssertEqual(schedule.activeDays, [1, 7])
        XCTAssertEqual(schedule.startHour, 10)
        XCTAssertEqual(schedule.endHour, 12)
    }

    func testIsActiveMatchingDayAndHour() {
        let schedule = RitualSchedule(activeDays: [2], startHour: 9, endHour: 11) // Monday 9-11
        // Create a Monday at 10:00
        var components = DateComponents()
        components.year = 2026
        components.month = 3
        components.day = 9  // Monday
        components.hour = 10
        let date = Calendar.current.date(from: components)!
        XCTAssertTrue(schedule.isActive(at: date))
    }

    func testIsActiveOutsideHour() {
        let schedule = RitualSchedule(activeDays: [2], startHour: 9, endHour: 11)
        var components = DateComponents()
        components.year = 2026
        components.month = 3
        components.day = 9  // Monday
        components.hour = 12
        let date = Calendar.current.date(from: components)!
        XCTAssertFalse(schedule.isActive(at: date))
    }

    func testIsActiveWrongDay() {
        let schedule = RitualSchedule(activeDays: [2], startHour: 9, endHour: 11) // Monday only
        var components = DateComponents()
        components.year = 2026
        components.month = 3
        components.day = 10  // Tuesday
        components.hour = 10
        let date = Calendar.current.date(from: components)!
        XCTAssertFalse(schedule.isActive(at: date))
    }

    func testIsActiveAtStartHour() {
        let schedule = RitualSchedule(activeDays: Set(1...7), startHour: 8, endHour: 10)
        var components = DateComponents()
        components.year = 2026; components.month = 3; components.day = 10
        components.hour = 8
        let date = Calendar.current.date(from: components)!
        XCTAssertTrue(schedule.isActive(at: date))
    }

    func testIsActiveAtEndHourExcluded() {
        let schedule = RitualSchedule(activeDays: Set(1...7), startHour: 8, endHour: 10)
        var components = DateComponents()
        components.year = 2026; components.month = 3; components.day = 10
        components.hour = 10
        let date = Calendar.current.date(from: components)!
        XCTAssertFalse(schedule.isActive(at: date))
    }

    func testDisplayText() {
        let schedule = RitualSchedule(activeDays: [2, 4, 6], startHour: 9, endHour: 17)
        let text = schedule.displayText
        XCTAssertTrue(text.contains("Mon"))
        XCTAssertTrue(text.contains("Wed"))
        XCTAssertTrue(text.contains("Fri"))
        XCTAssertTrue(text.contains("9:00"))
        XCTAssertTrue(text.contains("17:00"))
    }

    func testScheduleEquality() {
        let a = RitualSchedule(activeDays: [1, 2], startHour: 8, endHour: 10)
        let b = RitualSchedule(activeDays: [1, 2], startHour: 8, endHour: 10)
        XCTAssertEqual(a, b)
    }
}

// MARK: - ReadingRitual Tests

class ReadingRitualTests: XCTestCase {

    func testRitualCreation() {
        let ritual = ReadingRitual(
            name: "Test Ritual",
            icon: "🧪",
            schedule: .weekdays,
            articleGoal: 7,
            description: "A test"
        )
        XCTAssertEqual(ritual.name, "Test Ritual")
        XCTAssertEqual(ritual.icon, "🧪")
        XCTAssertEqual(ritual.articleGoal, 7)
        XCTAssertTrue(ritual.isEnabled)
        XCTAssertFalse(ritual.id.isEmpty)
    }

    func testRitualDefaults() {
        let ritual = ReadingRitual(name: "Default", schedule: .weekdays)
        XCTAssertEqual(ritual.icon, "📖")
        XCTAssertEqual(ritual.articleGoal, 5)
        XCTAssertEqual(ritual.minWordCount, 0)
        XCTAssertEqual(ritual.maxWordCount, 0)
        XCTAssertTrue(ritual.feedFilter.isEmpty)
    }

    func testRitualEqualityById() {
        let a = ReadingRitual(name: "A", schedule: .weekdays)
        var b = a
        b.name = "B"
        XCTAssertEqual(a, b) // Same ID
    }
}

// MARK: - RitualSession Tests

class RitualSessionTests: XCTestCase {

    func testSessionCreation() {
        let session = RitualSession(ritualId: "abc-123")
        XCTAssertEqual(session.ritualId, "abc-123")
        XCTAssertNil(session.completedAt)
        XCTAssertTrue(session.articlesRead.isEmpty)
        XCTAssertFalse(session.goalMet)
        XCTAssertFalse(session.dateKey.isEmpty)
    }
}

// MARK: - ReadingRitualManager Tests

class ReadingRitualManagerTests: XCTestCase {

    var manager: ReadingRitualManager!

    override func setUp() {
        super.setUp()
        manager = ReadingRitualManager()
        // Clear any persisted data
        for ritual in manager.rituals {
            _ = manager.deleteRitual(ritual.id)
        }
    }

    // MARK: - CRUD

    func testCreateRitual() {
        let ritual = manager.createRitual(name: "Morning", schedule: .weekdays, articleGoal: 5)
        XCTAssertEqual(manager.rituals.count, 1)
        XCTAssertEqual(ritual.name, "Morning")
    }

    func testUpdateRitual() {
        let ritual = manager.createRitual(name: "Old Name", schedule: .weekdays)
        let updated = manager.updateRitual(ritual.id) { $0.name = "New Name" }
        XCTAssertTrue(updated)
        XCTAssertEqual(manager.ritual(byId: ritual.id)?.name, "New Name")
    }

    func testUpdateNonexistentRitualReturnsFalse() {
        let result = manager.updateRitual("nonexistent") { $0.name = "X" }
        XCTAssertFalse(result)
    }

    func testDeleteRitual() {
        let ritual = manager.createRitual(name: "To Delete", schedule: .weekdays)
        XCTAssertEqual(manager.rituals.count, 1)
        let deleted = manager.deleteRitual(ritual.id)
        XCTAssertTrue(deleted)
        XCTAssertEqual(manager.rituals.count, 0)
    }

    func testDeleteNonexistentReturnsFalse() {
        XCTAssertFalse(manager.deleteRitual("nope"))
    }

    func testRitualByName() {
        manager.createRitual(name: "Test Ritual", schedule: .weekdays)
        XCTAssertNotNil(manager.ritual(byName: "test ritual"))
        XCTAssertNil(manager.ritual(byName: "nonexistent"))
    }

    // MARK: - Sessions

    func testStartSession() {
        let ritual = manager.createRitual(name: "R", schedule: .weekdays)
        let session = manager.startSession(ritualId: ritual.id)
        XCTAssertNotNil(session)
        XCTAssertEqual(manager.sessions.count, 1)
    }

    func testStartSessionForNonexistentRitual() {
        let session = manager.startSession(ritualId: "fake")
        XCTAssertNil(session)
    }

    func testDuplicateSessionSameDay() {
        let ritual = manager.createRitual(name: "R", schedule: .weekdays)
        _ = manager.startSession(ritualId: ritual.id)
        _ = manager.startSession(ritualId: ritual.id)
        XCTAssertEqual(manager.sessions.count, 1)
    }

    func testLogArticleRead() {
        let ritual = manager.createRitual(name: "R", schedule: .weekdays, articleGoal: 2)
        _ = manager.startSession(ritualId: ritual.id)
        let logged = manager.logArticleRead(ritualId: ritual.id, articleLink: "https://a.com/1")
        XCTAssertTrue(logged)
        XCTAssertEqual(manager.sessions.first?.articlesRead.count, 1)
    }

    func testGoalCompletionOnArticleRead() {
        let ritual = manager.createRitual(name: "R", schedule: .weekdays, articleGoal: 2)
        _ = manager.startSession(ritualId: ritual.id)
        _ = manager.logArticleRead(ritualId: ritual.id, articleLink: "https://a.com/1")
        _ = manager.logArticleRead(ritualId: ritual.id, articleLink: "https://a.com/2")
        XCTAssertTrue(manager.sessions.first?.goalMet ?? false)
        XCTAssertNotNil(manager.sessions.first?.completedAt)
    }

    func testDuplicateArticleNotCounted() {
        let ritual = manager.createRitual(name: "R", schedule: .weekdays)
        _ = manager.startSession(ritualId: ritual.id)
        _ = manager.logArticleRead(ritualId: ritual.id, articleLink: "https://a.com/1")
        _ = manager.logArticleRead(ritualId: ritual.id, articleLink: "https://a.com/1")
        XCTAssertEqual(manager.sessions.first?.articlesRead.count, 1)
    }

    func testCompleteSessionManually() {
        let ritual = manager.createRitual(name: "R", schedule: .weekdays, articleGoal: 10)
        _ = manager.startSession(ritualId: ritual.id)
        _ = manager.logArticleRead(ritualId: ritual.id, articleLink: "https://a.com/1")
        let completed = manager.completeSession(ritualId: ritual.id)
        XCTAssertTrue(completed)
        XCTAssertNotNil(manager.sessions.first?.completedAt)
        XCTAssertFalse(manager.sessions.first?.goalMet ?? true) // goal not met
    }

    // MARK: - Analytics

    func testAnalyticsForRitual() {
        let ritual = manager.createRitual(name: "R", schedule: .weekdays, articleGoal: 2)
        _ = manager.startSession(ritualId: ritual.id)
        _ = manager.logArticleRead(ritualId: ritual.id, articleLink: "https://a.com/1")
        _ = manager.logArticleRead(ritualId: ritual.id, articleLink: "https://a.com/2")
        let stats = manager.analytics(for: ritual.id)
        XCTAssertNotNil(stats)
        XCTAssertEqual(stats?.totalSessions, 1)
        XCTAssertEqual(stats?.completedSessions, 1)
        XCTAssertEqual(stats?.totalArticlesRead, 2)
    }

    func testAnalyticsForNonexistentRitual() {
        XCTAssertNil(manager.analytics(for: "nope"))
    }

    // MARK: - Suggested Queue

    func testSuggestedQueueFiltering() {
        let ritual = manager.createRitual(
            name: "Tech",
            schedule: .weekdays,
            feedFilter: ["TechCrunch"],
            minWordCount: 100,
            articleGoal: 3
        )
        _ = manager.startSession(ritualId: ritual.id)

        let stories = [
            SuggestedStory(link: "https://tc.com/1", title: "AI News", feedName: "TechCrunch", publishDate: Date(), wordCount: 500),
            SuggestedStory(link: "https://tc.com/2", title: "Startup", feedName: "TechCrunch", publishDate: Date().addingTimeInterval(-100), wordCount: 200),
            SuggestedStory(link: "https://nyt.com/1", title: "Politics", feedName: "NYTimes", publishDate: Date(), wordCount: 800),
            SuggestedStory(link: "https://tc.com/3", title: "Short", feedName: "TechCrunch", publishDate: Date(), wordCount: 50),
        ]

        let queue = manager.suggestedQueue(for: ritual.id, from: stories)
        XCTAssertEqual(queue.count, 2) // Only TechCrunch with >= 100 words
        XCTAssertTrue(queue.allSatisfy { $0.feedName == "TechCrunch" })
        XCTAssertTrue(queue.allSatisfy { $0.wordCount >= 100 })
    }

    // MARK: - Presets

    func testMorningBriefingPreset() {
        let ritual = manager.createMorningBriefing()
        XCTAssertEqual(ritual.name, "Morning Briefing")
        XCTAssertEqual(ritual.icon, "☀️")
        XCTAssertEqual(ritual.articleGoal, 5)
    }

    func testWeekendDeepDivePreset() {
        let ritual = manager.createWeekendDeepDive()
        XCTAssertEqual(ritual.name, "Weekend Deep Dive")
        XCTAssertEqual(ritual.minWordCount, 1000)
    }

    // MARK: - Export

    func testExportPlainText() {
        manager.createRitual(name: "Morning", icon: "☀️", schedule: .weekdays)
        let text = manager.exportPlainText()
        XCTAssertTrue(text.contains("Morning"))
        XCTAssertTrue(text.contains("☀️"))
        XCTAssertTrue(text.contains("Reading Rituals"))
    }

    func testExportPlainTextEmpty() {
        let text = manager.exportPlainText()
        XCTAssertTrue(text.contains("No rituals defined"))
    }

    func testExportJSON() {
        manager.createRitual(name: "Test", schedule: .weekdays)
        let json = manager.exportJSON()
        XCTAssertTrue(json.contains("Test"))
        XCTAssertTrue(json.contains("rituals"))
    }

    // MARK: - Delete Cascades Sessions

    func testDeleteCascadesSessions() {
        let ritual = manager.createRitual(name: "R", schedule: .weekdays)
        _ = manager.startSession(ritualId: ritual.id)
        _ = manager.logArticleRead(ritualId: ritual.id, articleLink: "https://a.com")
        XCTAssertEqual(manager.sessions.count, 1)
        _ = manager.deleteRitual(ritual.id)
        XCTAssertEqual(manager.sessions.count, 0)
    }
}
