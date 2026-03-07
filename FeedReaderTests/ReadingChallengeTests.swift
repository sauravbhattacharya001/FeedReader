//
//  ReadingChallengeTests.swift
//  FeedReaderTests
//
//  Tests for ReadingChallengeManager — time-limited reading challenges.
//

import XCTest
@testable import FeedReader

class ReadingChallengeTests: XCTestCase {

    var manager: ReadingChallengeManager!
    let calendar = Calendar.current

    override func setUp() {
        super.setUp()
        manager = ReadingChallengeManager(calendar: calendar)
        manager.reset()
    }

    override func tearDown() {
        manager.reset()
        super.tearDown()
    }

    // MARK: - Helpers

    private func makeDate(daysFromNow: Int) -> Date {
        return calendar.date(byAdding: .day, value: daysFromNow, to: Date())!
    }

    private func makePastDate(daysAgo: Int) -> Date {
        return calendar.date(byAdding: .day, value: -daysAgo, to: Date())!
    }

    // MARK: - Creation Tests

    func testCreateChallenge() {
        let challenge = manager.createChallenge(
            name: "Test Challenge",
            type: .articleCount,
            target: 10,
            endDate: makeDate(daysFromNow: 7)
        )
        XCTAssertNotNil(challenge)
        XCTAssertEqual(challenge?.name, "Test Challenge")
        XCTAssertEqual(challenge?.type, .articleCount)
        XCTAssertEqual(challenge?.target, 10)
        XCTAssertEqual(challenge?.progress, 0)
        XCTAssertEqual(challenge?.status, .active)
        XCTAssertEqual(manager.challenges.count, 1)
    }

    func testCreateChallengeEmptyNameFails() {
        let result = manager.createChallenge(
            name: "",
            type: .articleCount,
            target: 10,
            endDate: makeDate(daysFromNow: 7)
        )
        XCTAssertNil(result)
        XCTAssertEqual(manager.challenges.count, 0)
    }

    func testCreateChallengeWhitespaceOnlyNameFails() {
        let result = manager.createChallenge(
            name: "   ",
            type: .articleCount,
            target: 10,
            endDate: makeDate(daysFromNow: 7)
        )
        XCTAssertNil(result)
    }

    func testCreateChallengeZeroTargetFails() {
        let result = manager.createChallenge(
            name: "Zero",
            type: .articleCount,
            target: 0,
            endDate: makeDate(daysFromNow: 7)
        )
        XCTAssertNil(result)
    }

    func testCreateChallengeNegativeTargetFails() {
        let result = manager.createChallenge(
            name: "Negative",
            type: .articleCount,
            target: -5,
            endDate: makeDate(daysFromNow: 7)
        )
        XCTAssertNil(result)
    }

    func testCreateChallengeExceedsMaxTargetFails() {
        let result = manager.createChallenge(
            name: "Huge",
            type: .articleCount,
            target: ReadingChallengeManager.maxTarget + 1,
            endDate: makeDate(daysFromNow: 7)
        )
        XCTAssertNil(result)
    }

    func testCreateChallengeEndDateBeforeStartFails() {
        let result = manager.createChallenge(
            name: "Backwards",
            type: .articleCount,
            target: 10,
            startDate: Date(),
            endDate: makePastDate(daysAgo: 1)
        )
        XCTAssertNil(result)
    }

    func testCreateChallengeFeedSpecificRequiresFeedURL() {
        let noFeed = manager.createChallenge(
            name: "Focus",
            type: .feedSpecific,
            target: 20,
            endDate: makeDate(daysFromNow: 7)
        )
        XCTAssertNil(noFeed)

        let withFeed = manager.createChallenge(
            name: "Focus",
            type: .feedSpecific,
            target: 20,
            endDate: makeDate(daysFromNow: 7),
            feedURL: "https://example.com/feed"
        )
        XCTAssertNotNil(withFeed)
    }

    func testMaxActiveChallengesLimit() {
        for i in 0..<ReadingChallengeManager.maxActiveChallenges {
            let result = manager.createChallenge(
                name: "Challenge \(i)",
                type: .articleCount,
                target: 10,
                endDate: makeDate(daysFromNow: 7)
            )
            XCTAssertNotNil(result)
        }

        // One more should fail
        let overflow = manager.createChallenge(
            name: "Too Many",
            type: .articleCount,
            target: 10,
            endDate: makeDate(daysFromNow: 7)
        )
        XCTAssertNil(overflow)
    }

    // MARK: - Template Tests

    func testCreateFromTemplate() {
        let template = ReadingChallengeManager.templates[0] // Weekend Reader
        let challenge = manager.createFromTemplate(template)
        XCTAssertNotNil(challenge)
        XCTAssertEqual(challenge?.name, template.name)
        XCTAssertEqual(challenge?.type, template.type)
        XCTAssertEqual(challenge?.target, template.target)
        XCTAssertEqual(challenge?.icon, template.icon)
    }

    func testAllTemplatesAreValid() {
        for template in ReadingChallengeManager.templates {
            XCTAssertFalse(template.name.isEmpty)
            XCTAssertFalse(template.icon.isEmpty)
            XCTAssertGreaterThan(template.target, 0)
            XCTAssertNotNil(template.duration.seconds)
            XCTAssertFalse(template.description.isEmpty)
        }
    }

    // MARK: - Progress Recording Tests

    func testRecordReadingArticleCount() {
        manager.createChallenge(
            name: "Read 5",
            type: .articleCount,
            target: 5,
            endDate: makeDate(daysFromNow: 7)
        )

        manager.recordReading(feedURL: "https://example.com/feed")
        XCTAssertEqual(manager.challenges[0].progress, 1)

        manager.recordReading(feedURL: "https://example.com/feed")
        XCTAssertEqual(manager.challenges[0].progress, 2)
    }

    func testRecordReadingTimeSpent() {
        manager.createChallenge(
            name: "Read 60 min",
            type: .timeSpent,
            target: 60,
            endDate: makeDate(daysFromNow: 7)
        )

        manager.recordReading(feedURL: "https://a.com", minutesSpent: 15)
        XCTAssertEqual(manager.challenges[0].progress, 15)

        manager.recordReading(feedURL: "https://b.com", minutesSpent: 30)
        XCTAssertEqual(manager.challenges[0].progress, 45)
    }

    func testRecordReadingFeedDiversity() {
        manager.createChallenge(
            name: "Diverse",
            type: .feedDiversity,
            target: 3,
            endDate: makeDate(daysFromNow: 7)
        )

        manager.recordReading(feedURL: "https://a.com")
        XCTAssertEqual(manager.challenges[0].progress, 1)

        // Same feed again — no increase
        manager.recordReading(feedURL: "https://a.com")
        XCTAssertEqual(manager.challenges[0].progress, 1)

        manager.recordReading(feedURL: "https://b.com")
        XCTAssertEqual(manager.challenges[0].progress, 2)

        manager.recordReading(feedURL: "https://c.com")
        XCTAssertEqual(manager.challenges[0].progress, 3)
    }

    func testRecordReadingFeedSpecific() {
        let targetFeed = "https://target.com/feed"
        manager.createChallenge(
            name: "Focus",
            type: .feedSpecific,
            target: 5,
            endDate: makeDate(daysFromNow: 7),
            feedURL: targetFeed
        )

        // Reading from different feed — no progress
        manager.recordReading(feedURL: "https://other.com/feed")
        XCTAssertEqual(manager.challenges[0].progress, 0)

        // Reading from target feed
        manager.recordReading(feedURL: targetFeed)
        XCTAssertEqual(manager.challenges[0].progress, 1)
    }

    func testRecordReadingFeedSpecificCaseInsensitive() {
        manager.createChallenge(
            name: "Focus",
            type: .feedSpecific,
            target: 5,
            endDate: makeDate(daysFromNow: 7),
            feedURL: "https://Example.COM/Feed"
        )

        manager.recordReading(feedURL: "https://example.com/feed")
        XCTAssertEqual(manager.challenges[0].progress, 1)
    }

    func testRecordReadingActiveDays() {
        manager.createChallenge(
            name: "Active",
            type: .activeDays,
            target: 5,
            endDate: makeDate(daysFromNow: 14)
        )

        // Two readings on same day — progress should be 1
        manager.recordReading(feedURL: "https://a.com", date: Date())
        manager.recordReading(feedURL: "https://b.com", date: Date())
        XCTAssertEqual(manager.challenges[0].progress, 1)
    }

    // MARK: - Completion Tests

    func testAutoCompletionOnTarget() {
        manager.createChallenge(
            name: "Read 2",
            type: .articleCount,
            target: 2,
            endDate: makeDate(daysFromNow: 7)
        )

        manager.recordReading(feedURL: "https://a.com")
        XCTAssertEqual(manager.challenges[0].status, .active)

        manager.recordReading(feedURL: "https://b.com")
        XCTAssertEqual(manager.challenges[0].status, .completed)
        XCTAssertNotNil(manager.challenges[0].completedAt)
    }

    func testCompletionNotification() {
        let expectation = self.expectation(forNotification: .readingChallengeCompleted, object: nil)

        manager.createChallenge(
            name: "Quick",
            type: .articleCount,
            target: 1,
            endDate: makeDate(daysFromNow: 7)
        )

        manager.recordReading(feedURL: "https://a.com")
        wait(for: [expectation], timeout: 1.0)
    }

    // MARK: - Expiration Tests

    func testCheckExpirationMarksFailedChallenges() {
        manager.createChallenge(
            name: "Expired",
            type: .articleCount,
            target: 100,
            startDate: makePastDate(daysAgo: 10),
            endDate: makePastDate(daysAgo: 1)
        )

        let expired = manager.checkExpiration()
        XCTAssertEqual(expired.count, 1)
        XCTAssertEqual(manager.challenges[0].status, .failed)
    }

    func testCheckExpirationDoesNotAffectCompletedChallenges() {
        manager.createChallenge(
            name: "Done",
            type: .articleCount,
            target: 1,
            startDate: makePastDate(daysAgo: 10),
            endDate: makePastDate(daysAgo: 1)
        )
        manager.recordReading(feedURL: "https://a.com")
        XCTAssertEqual(manager.challenges[0].status, .completed)

        let expired = manager.checkExpiration()
        XCTAssertTrue(expired.isEmpty)
        XCTAssertEqual(manager.challenges[0].status, .completed)
    }

    // MARK: - Abandon Tests

    func testAbandonChallenge() {
        let challenge = manager.createChallenge(
            name: "Abandon Me",
            type: .articleCount,
            target: 10,
            endDate: makeDate(daysFromNow: 7)
        )!

        let result = manager.abandonChallenge(id: challenge.id)
        XCTAssertTrue(result)
        XCTAssertEqual(manager.challenges[0].status, .abandoned)
    }

    func testAbandonNonExistentChallengeFails() {
        XCTAssertFalse(manager.abandonChallenge(id: "nonexistent"))
    }

    func testAbandonCompletedChallengeFails() {
        let challenge = manager.createChallenge(
            name: "Done",
            type: .articleCount,
            target: 1,
            endDate: makeDate(daysFromNow: 7)
        )!
        manager.recordReading(feedURL: "https://a.com")

        XCTAssertFalse(manager.abandonChallenge(id: challenge.id))
    }

    // MARK: - Query Tests

    func testActiveChallenges() {
        manager.createChallenge(name: "A", type: .articleCount, target: 10, endDate: makeDate(daysFromNow: 7))
        manager.createChallenge(name: "B", type: .articleCount, target: 1, endDate: makeDate(daysFromNow: 7))
        manager.recordReading(feedURL: "https://a.com") // completes B

        let active = manager.activeChallenges()
        XCTAssertEqual(active.count, 1)
        XCTAssertEqual(active[0].name, "A")
    }

    func testClosestToCompletion() {
        manager.createChallenge(name: "Far", type: .articleCount, target: 100, endDate: makeDate(daysFromNow: 30))
        manager.createChallenge(name: "Close", type: .articleCount, target: 2, endDate: makeDate(daysFromNow: 7))

        manager.recordReading(feedURL: "https://a.com")

        let closest = manager.closestToCompletion()
        XCTAssertEqual(closest?.name, "Close")
    }

    func testMostUrgent() {
        manager.createChallenge(name: "Later", type: .articleCount, target: 10, endDate: makeDate(daysFromNow: 30))
        manager.createChallenge(name: "Soon", type: .articleCount, target: 10, endDate: makeDate(daysFromNow: 2))

        let urgent = manager.mostUrgent()
        XCTAssertEqual(urgent?.name, "Soon")
    }

    func testCompletedChallengesSortedByDate() {
        let c1 = manager.createChallenge(name: "First", type: .articleCount, target: 1, endDate: makeDate(daysFromNow: 7))!
        manager.recordReading(feedURL: "https://a.com")

        let c2 = manager.createChallenge(name: "Second", type: .articleCount, target: 1, endDate: makeDate(daysFromNow: 7))!
        manager.recordReading(feedURL: "https://b.com")

        let completed = manager.completedChallenges()
        XCTAssertEqual(completed.count, 2)
        // Most recent first
        XCTAssertEqual(completed[0].id, c2.id)
        XCTAssertEqual(completed[1].id, c1.id)
    }

    // MARK: - Statistics Tests

    func testStatsEmpty() {
        let stats = manager.stats()
        XCTAssertEqual(stats.totalCreated, 0)
        XCTAssertEqual(stats.totalCompleted, 0)
        XCTAssertEqual(stats.totalFailed, 0)
        XCTAssertEqual(stats.totalAbandoned, 0)
        XCTAssertEqual(stats.activeCount, 0)
        XCTAssertEqual(stats.completionRate, 0.0)
    }

    func testStatsAfterActivity() {
        // Create and complete one
        manager.createChallenge(name: "Done", type: .articleCount, target: 1, endDate: makeDate(daysFromNow: 7))
        manager.recordReading(feedURL: "https://a.com")

        // Create and abandon one
        let abandoned = manager.createChallenge(name: "Quit", type: .articleCount, target: 100, endDate: makeDate(daysFromNow: 7))!
        manager.abandonChallenge(id: abandoned.id)

        // Create an active one
        manager.createChallenge(name: "Active", type: .articleCount, target: 50, endDate: makeDate(daysFromNow: 14))

        let stats = manager.stats()
        XCTAssertEqual(stats.totalCreated, 3)
        XCTAssertEqual(stats.totalCompleted, 1)
        XCTAssertEqual(stats.totalAbandoned, 1)
        XCTAssertEqual(stats.activeCount, 1)
        XCTAssertEqual(stats.completionRate, 1.0) // 1 completed / 1 finished (abandoned doesn't count)
    }

    // MARK: - Streak Tests

    func testStreakTracking() {
        manager.createChallenge(
            name: "Streak",
            type: .streakDays,
            target: 3,
            startDate: makePastDate(daysAgo: 5),
            endDate: makeDate(daysFromNow: 7)
        )

        // Day 1
        let day1 = makePastDate(daysAgo: 2)
        manager.recordReading(feedURL: "https://a.com", date: day1)
        XCTAssertEqual(manager.challenges[0].currentStreak, 1)

        // Day 2 (consecutive)
        let day2 = makePastDate(daysAgo: 1)
        manager.recordReading(feedURL: "https://a.com", date: day2)
        XCTAssertEqual(manager.challenges[0].currentStreak, 2)

        // Day 3 (consecutive)
        manager.recordReading(feedURL: "https://a.com", date: Date())
        XCTAssertEqual(manager.challenges[0].currentStreak, 3)
        XCTAssertEqual(manager.challenges[0].longestStreak, 3)
    }

    // MARK: - Percent Complete Tests

    func testPercentComplete() {
        manager.createChallenge(name: "Half", type: .articleCount, target: 4, endDate: makeDate(daysFromNow: 7))

        manager.recordReading(feedURL: "https://a.com")
        manager.recordReading(feedURL: "https://b.com")
        XCTAssertEqual(manager.challenges[0].percentComplete, 0.5, accuracy: 0.001)
    }

    func testPercentCompleteClampsAtOne() {
        manager.createChallenge(name: "Over", type: .articleCount, target: 1, endDate: makeDate(daysFromNow: 7))
        manager.recordReading(feedURL: "https://a.com")
        // After completion, progress can't exceed target in percentage
        XCTAssertEqual(manager.challenges[0].percentComplete, 1.0)
    }

    // MARK: - Pace Tests

    func testPaceCalculation() {
        let start = makePastDate(daysAgo: 5)
        let end = makeDate(daysFromNow: 5) // 10 day challenge

        manager.createChallenge(
            name: "Paced",
            type: .articleCount,
            target: 10,
            startDate: start,
            endDate: end
        )

        // Read 5 articles by day 5 of 10 — exactly on pace
        for _ in 0..<5 {
            manager.recordReading(feedURL: "https://a.com")
        }

        let pace = manager.challenges[0].pace()
        XCTAssertEqual(pace, 1.0, accuracy: 0.01)
    }

    // MARK: - Delete Tests

    func testDeleteChallenge() {
        let challenge = manager.createChallenge(
            name: "Delete Me",
            type: .articleCount,
            target: 10,
            endDate: makeDate(daysFromNow: 7)
        )!

        XCTAssertTrue(manager.deleteChallenge(id: challenge.id))
        XCTAssertEqual(manager.challenges.count, 0)
    }

    func testDeleteNonExistentChallenge() {
        XCTAssertFalse(manager.deleteChallenge(id: "nonexistent"))
    }

    func testClearHistory() {
        // Create a completed challenge
        manager.createChallenge(name: "Done", type: .articleCount, target: 1, endDate: makeDate(daysFromNow: 7))
        manager.recordReading(feedURL: "https://a.com")

        // Create an active challenge
        manager.createChallenge(name: "Active", type: .articleCount, target: 100, endDate: makeDate(daysFromNow: 30))

        let removed = manager.clearHistory()
        XCTAssertEqual(removed, 1) // only the completed one
        XCTAssertEqual(manager.challenges.count, 1)
        XCTAssertEqual(manager.challenges[0].name, "Active")
    }

    // MARK: - JSON Export/Import Tests

    func testExportJSON() {
        manager.createChallenge(name: "Export", type: .articleCount, target: 10, endDate: makeDate(daysFromNow: 7))
        let json = manager.exportJSON()
        XCTAssertNotNil(json)
        XCTAssertTrue(json!.contains("Export"))
        XCTAssertTrue(json!.contains("article_count"))
    }

    func testImportJSON() {
        manager.createChallenge(name: "Original", type: .articleCount, target: 5, endDate: makeDate(daysFromNow: 7))
        let json = manager.exportJSON()!

        // Reset and import
        manager.reset()
        XCTAssertEqual(manager.challenges.count, 0)

        let imported = manager.importJSON(json)
        XCTAssertEqual(imported, 1)
        XCTAssertEqual(manager.challenges[0].name, "Original")
    }

    func testImportJSONSkipsDuplicates() {
        manager.createChallenge(name: "Existing", type: .articleCount, target: 5, endDate: makeDate(daysFromNow: 7))
        let json = manager.exportJSON()!

        // Import again — should skip duplicate
        let imported = manager.importJSON(json)
        XCTAssertEqual(imported, 0)
        XCTAssertEqual(manager.challenges.count, 1)
    }

    func testImportInvalidJSON() {
        let imported = manager.importJSON("not valid json")
        XCTAssertEqual(imported, 0)
    }

    // MARK: - Summary Tests

    func testSummaryActive() {
        let challenge = manager.createChallenge(
            name: "Summary Test",
            type: .articleCount,
            target: 10,
            endDate: makeDate(daysFromNow: 7),
            icon: "📖"
        )!

        manager.recordReading(feedURL: "https://a.com")
        let text = manager.summary(for: manager.challenge(id: challenge.id)!)

        XCTAssertTrue(text.contains("📖 Summary Test"))
        XCTAssertTrue(text.contains("1/10"))
        XCTAssertTrue(text.contains("Article Count"))
    }

    func testSummaryCompleted() {
        let challenge = manager.createChallenge(
            name: "Done",
            type: .articleCount,
            target: 1,
            endDate: makeDate(daysFromNow: 7)
        )!

        manager.recordReading(feedURL: "https://a.com")
        let text = manager.summary(for: manager.challenge(id: challenge.id)!)
        XCTAssertTrue(text.contains("Completed ✅"))
    }

    // MARK: - ChallengeType Tests

    func testAllChallengeTypesHaveLabels() {
        for type in ChallengeType.allCases {
            XCTAssertFalse(type.label.isEmpty)
        }
    }

    func testTargetUnitSingularPlural() {
        XCTAssertEqual(ChallengeType.articleCount.targetUnit(value: 1), "article")
        XCTAssertEqual(ChallengeType.articleCount.targetUnit(value: 5), "articles")
        XCTAssertEqual(ChallengeType.timeSpent.targetUnit(value: 1), "minute")
        XCTAssertEqual(ChallengeType.timeSpent.targetUnit(value: 10), "minutes")
    }

    // MARK: - ChallengeDuration Tests

    func testDurationSeconds() {
        XCTAssertEqual(ChallengeDuration.threeDay.seconds, 3 * 24 * 3600)
        XCTAssertEqual(ChallengeDuration.oneWeek.seconds, 7 * 24 * 3600)
        XCTAssertEqual(ChallengeDuration.twoWeek.seconds, 14 * 24 * 3600)
        XCTAssertEqual(ChallengeDuration.oneMonth.seconds, 30 * 24 * 3600)
        XCTAssertNil(ChallengeDuration.custom.seconds)
    }

    func testDurationLabels() {
        for duration in ChallengeDuration.allCases {
            XCTAssertFalse(duration.label.isEmpty)
        }
    }

    // MARK: - Edge Cases

    func testRecordReadingIgnoresCompletedChallenges() {
        manager.createChallenge(name: "Done", type: .articleCount, target: 1, endDate: makeDate(daysFromNow: 7))
        manager.recordReading(feedURL: "https://a.com")
        XCTAssertEqual(manager.challenges[0].status, .completed)

        // Further readings don't increase progress
        manager.recordReading(feedURL: "https://b.com")
        XCTAssertEqual(manager.challenges[0].progress, 1)
    }

    func testRecordReadingBeforeStartDateIgnored() {
        let futureStart = makeDate(daysFromNow: 3)
        manager.createChallenge(
            name: "Future",
            type: .articleCount,
            target: 10,
            startDate: futureStart,
            endDate: makeDate(daysFromNow: 10)
        )

        // Reading now is before start
        manager.recordReading(feedURL: "https://a.com", date: Date())
        XCTAssertEqual(manager.challenges[0].progress, 0)
    }

    func testMultipleChallengesProgressSimultaneously() {
        manager.createChallenge(name: "Count", type: .articleCount, target: 10, endDate: makeDate(daysFromNow: 7))
        manager.createChallenge(name: "Time", type: .timeSpent, target: 60, endDate: makeDate(daysFromNow: 7))

        manager.recordReading(feedURL: "https://a.com", minutesSpent: 10)

        XCTAssertEqual(manager.challenges[0].progress, 1) // article count
        XCTAssertEqual(manager.challenges[1].progress, 10) // time spent
    }

    func testResetClearsEverything() {
        manager.createChallenge(name: "Gone", type: .articleCount, target: 10, endDate: makeDate(daysFromNow: 7))
        manager.reset()
        XCTAssertEqual(manager.challenges.count, 0)
    }

    // MARK: - Time Remaining Tests

    func testTimeRemainingPositive() {
        let challenge = manager.createChallenge(
            name: "Timer",
            type: .articleCount,
            target: 10,
            endDate: makeDate(daysFromNow: 3)
        )!
        XCTAssertGreaterThan(challenge.timeRemaining(), 0)
    }

    func testTimeRemainingExpired() {
        // Manually create an expired-seeming scenario
        manager.createChallenge(
            name: "Old",
            type: .articleCount,
            target: 100,
            startDate: makePastDate(daysAgo: 10),
            endDate: makePastDate(daysAgo: 1)
        )
        XCTAssertEqual(manager.challenges[0].timeRemaining(), 0)
    }
}
