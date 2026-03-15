//
//  FeedNotificationManagerTests.swift
//  FeedReaderTests
//

import XCTest
@testable import FeedReader

class FeedNotificationManagerTests: XCTestCase {

    var manager: FeedNotificationManager!

    override func setUp() {
        super.setUp()
        manager = FeedNotificationManager()
        manager.rules = [:]
        manager.globalQuietHours = nil
        manager.isGloballyMuted = false
        manager.batchQueue = [:]
    }

    // MARK: - Helper

    func makeStory(title: String = "Test Article", body: String = "Some content", link: String = "https://example.com/1") -> Story {
        return Story(title: title, photo: nil, body: body, link: link)!
    }

    // MARK: - Default Rule

    func testDefaultRuleIsImmediate() {
        let rule = manager.effectiveRule(for: "MyFeed")
        XCTAssertEqual(rule.mode, .immediate)
        XCTAssertNil(rule.minimumPriority)
        XCTAssertTrue(rule.boostKeywords.isEmpty)
        XCTAssertNil(rule.snoozedUntil)
    }

    // MARK: - Rule CRUD

    func testSetAndRemoveRule() {
        let rule = FeedNotificationRule(feedName: "TechNews", mode: .batched, batchIntervalMinutes: 30)
        manager.setRule(rule)
        XCTAssertEqual(manager.rules["TechNews"]?.mode, .batched)

        manager.removeRule(for: "TechNews")
        XCTAssertNil(manager.rules["TechNews"])
    }

    // MARK: - Global Mute

    func testGlobalMuteSuppresses() {
        manager.isGloballyMuted = true
        let decision = manager.evaluate(story: makeStory(), feedName: "Feed1")
        XCTAssertEqual(decision, .suppress(reason: "globally_muted"))
    }

    // MARK: - Silent Mode

    func testSilentModeSuppresses() {
        manager.setRule(FeedNotificationRule(feedName: "Boring", mode: .silent))
        let decision = manager.evaluate(story: makeStory(), feedName: "Boring")
        XCTAssertEqual(decision, .suppress(reason: "silent_mode"))
    }

    func testSilentFeedsList() {
        manager.setRule(FeedNotificationRule(feedName: "A", mode: .silent))
        manager.setRule(FeedNotificationRule(feedName: "B", mode: .immediate))
        XCTAssertEqual(manager.silentFeeds(), ["A"])
    }

    // MARK: - Snooze

    func testSnoozedFeedSuppresses() {
        manager.snoozeFeed("News", for: 3600)
        let decision = manager.evaluate(story: makeStory(), feedName: "News")
        XCTAssertEqual(decision, .suppress(reason: "snoozed"))
    }

    func testExpiredSnoozDoesNotSuppress() {
        let rule = FeedNotificationRule(
            feedName: "News",
            mode: .immediate,
            snoozedUntil: Date().addingTimeInterval(-100)
        )
        manager.setRule(rule)
        let decision = manager.evaluate(story: makeStory(), feedName: "News")
        XCTAssertEqual(decision, .deliver)
    }

    func testUnsnoozeFeed() {
        manager.snoozeFeed("News", for: 3600)
        XCTAssertTrue(manager.effectiveRule(for: "News").isSnoozed)
        manager.unsnoozeFeed("News")
        XCTAssertFalse(manager.effectiveRule(for: "News").isSnoozed)
    }

    func testSnoozedFeedsList() {
        manager.snoozeFeed("A", for: 3600)
        manager.setRule(FeedNotificationRule(feedName: "B", mode: .immediate))
        XCTAssertEqual(manager.snoozedFeeds().count, 1)
        XCTAssertEqual(manager.snoozedFeeds().first?.feedName, "A")
    }

    // MARK: - Priority Filter

    func testBelowPrioritySuppresses() {
        let rule = FeedNotificationRule(feedName: "Alerts", mode: .immediate, minimumPriority: .high)
        manager.setRule(rule)
        let decision = manager.evaluate(story: makeStory(), feedName: "Alerts", priority: .low)
        XCTAssertEqual(decision, .suppress(reason: "below_priority"))
    }

    func testMeetsPriorityDelivers() {
        let rule = FeedNotificationRule(feedName: "Alerts", mode: .immediate, minimumPriority: .high)
        manager.setRule(rule)
        let decision = manager.evaluate(story: makeStory(), feedName: "Alerts", priority: .high)
        XCTAssertEqual(decision, .deliver)
    }

    // MARK: - Keyword Boost

    func testKeywordBoostOverridesBatchMode() {
        let rule = FeedNotificationRule(feedName: "Tech", mode: .batched, boostKeywords: ["breaking"])
        manager.setRule(rule)
        let story = makeStory(title: "Breaking: New Discovery", body: "Details here")
        let decision = manager.evaluate(story: story, feedName: "Tech")
        XCTAssertEqual(decision, .deliver)
    }

    func testNoBoostKeywordBatches() {
        let rule = FeedNotificationRule(feedName: "Tech", mode: .batched, boostKeywords: ["breaking"])
        manager.setRule(rule)
        let story = makeStory(title: "Regular Update", body: "Nothing special")
        let decision = manager.evaluate(story: story, feedName: "Tech")
        XCTAssertEqual(decision, .queue)
    }

    // MARK: - Quiet Hours

    func testQuietHoursSuppresses() {
        var calendar = Calendar.current
        calendar.timeZone = TimeZone.current
        let now = Date()
        let hour = calendar.component(.hour, from: now)
        let qh = QuietHoursRule(startHour: hour, startMinute: 0, endHour: (hour + 1) % 24, endMinute: 0, activeDays: [])
        manager.globalQuietHours = qh
        let decision = manager.evaluate(story: makeStory(), feedName: "Feed1", at: now)
        XCTAssertEqual(decision, .suppress(reason: "quiet_hours"))
    }

    func testQuietHoursWithDayFilter() {
        let calendar = Calendar.current
        let now = Date()
        let weekday = calendar.component(.weekday, from: now)
        let hour = calendar.component(.hour, from: now)
        // Rule for a different day should not suppress
        let otherDay = (weekday % 7) + 1
        let qh = QuietHoursRule(startHour: hour, startMinute: 0, endHour: (hour + 1) % 24, endMinute: 0, activeDays: [otherDay])
        manager.globalQuietHours = qh
        let decision = manager.evaluate(story: makeStory(), feedName: "Feed1", at: now)
        XCTAssertEqual(decision, .deliver)
    }

    func testMidnightWrappingQuietHours() {
        let qh = QuietHoursRule(startHour: 22, startMinute: 0, endHour: 7, endMinute: 0, activeDays: [])
        var calendar = Calendar.current
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        // 23:30 should be quiet
        XCTAssertTrue(qh.isQuiet(at: makeDate(hour: 23, minute: 30), calendar: calendar))
        // 06:00 should be quiet
        XCTAssertTrue(qh.isQuiet(at: makeDate(hour: 6, minute: 0), calendar: calendar))
        // 12:00 should not be quiet
        XCTAssertFalse(qh.isQuiet(at: makeDate(hour: 12, minute: 0), calendar: calendar))
    }

    private func makeDate(hour: Int, minute: Int) -> Date {
        var calendar = Calendar.current
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        var components = calendar.dateComponents([.year, .month, .day], from: Date())
        components.hour = hour
        components.minute = minute
        components.second = 0
        components.timeZone = TimeZone(secondsFromGMT: 0)
        return calendar.date(from: components)!
    }

    // MARK: - Batching

    func testBatchModeQueues() {
        manager.setRule(FeedNotificationRule(feedName: "Digest", mode: .batched, batchIntervalMinutes: 60))
        let decision = manager.evaluate(story: makeStory(), feedName: "Digest")
        XCTAssertEqual(decision, .queue)
    }

    func testEnqueueAndFlush() {
        manager.setRule(FeedNotificationRule(feedName: "Digest", mode: .batched, batchIntervalMinutes: 0))
        manager.enqueue(title: "A1", link: "https://a.com/1", feedName: "Digest")
        manager.enqueue(title: "A2", link: "https://a.com/2", feedName: "Digest")
        XCTAssertEqual(manager.feedsWithPendingBatches(), ["Digest"])

        let records = manager.flushBatch(for: "Digest")
        XCTAssertEqual(records.count, 2)
        XCTAssertTrue(records.allSatisfy { $0.wasBatched })
        XCTAssertTrue(manager.batchQueue["Digest"]?.isEmpty ?? true)
    }

    // MARK: - History & Deduplication

    func testDeliveryRecordsHistory() {
        let story = makeStory()
        let record = manager.recordDelivery(story: story, feedName: "Feed1")
        XCTAssertEqual(record.articleTitle, "Test Article")
        XCTAssertEqual(manager.recentHistory(limit: 10).count, 1)
    }

    func testDuplicateSuppresses() {
        let story = makeStory(link: "https://example.com/dup")
        _ = manager.recordDelivery(story: story, feedName: "Feed1")
        let decision = manager.evaluate(story: story, feedName: "Feed1")
        XCTAssertEqual(decision, .suppress(reason: "duplicate"))
    }

    func testClearHistory() {
        _ = manager.recordDelivery(story: makeStory(), feedName: "Feed1")
        manager.clearHistory()
        XCTAssertTrue(manager.recentHistory().isEmpty)
    }

    func testNotificationCount() {
        let cutoff = Date().addingTimeInterval(-10)
        _ = manager.recordDelivery(story: makeStory(), feedName: "Feed1")
        XCTAssertEqual(manager.notificationCount(for: "Feed1", since: cutoff), 1)
        XCTAssertEqual(manager.notificationCount(for: "Other", since: cutoff), 0)
    }

    // MARK: - Summary

    func testSummary() {
        manager.setRule(FeedNotificationRule(feedName: "A", mode: .silent))
        manager.setRule(FeedNotificationRule(feedName: "B", mode: .batched))
        manager.snoozeFeed("C", for: 3600)
        manager.enqueue(title: "X", link: "x", feedName: "B")

        let s = manager.summary()
        XCTAssertEqual(s.totalRules, 3)
        XCTAssertEqual(s.silent, 1)
        XCTAssertEqual(s.batched, 1)
        XCTAssertEqual(s.snoozed, 1)
        XCTAssertEqual(s.pendingBatchItems, 1)
    }

    // MARK: - Export / Import

    func testExportImportRoundTrip() {
        manager.setRule(FeedNotificationRule(feedName: "Tech", mode: .batched, batchIntervalMinutes: 30))
        manager.isGloballyMuted = true

        guard let data = manager.exportRulesJSON() else {
            XCTFail("Export failed")
            return
        }

        let newManager = FeedNotificationManager()
        newManager.rules = [:]
        XCTAssertTrue(newManager.importRulesJSON(data))
        XCTAssertEqual(newManager.rules["Tech"]?.mode, .batched)
        XCTAssertTrue(newManager.isGloballyMuted)
    }

    // MARK: - Immediate Mode Delivers

    func testImmediateModeDelivers() {
        let decision = manager.evaluate(story: makeStory(), feedName: "AnyFeed")
        XCTAssertEqual(decision, .deliver)
    }
}
