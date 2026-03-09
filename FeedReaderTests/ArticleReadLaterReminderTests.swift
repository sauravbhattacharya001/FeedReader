//
//  ArticleReadLaterReminderTests.swift
//  FeedReaderTests
//
//  Tests for ArticleReadLaterReminder.
//

import XCTest
@testable import FeedReader

class ArticleReadLaterReminderTests: XCTestCase {

    var reminder: ArticleReadLaterReminder!

    override func setUp() {
        super.setUp()
        reminder = ArticleReadLaterReminder()
        reminder.clearAll()
    }

    override func tearDown() {
        reminder.clearAll()
        super.tearDown()
    }

    // MARK: - Save / Remove

    func testSaveForLater_BasicItem() {
        let item = reminder.saveForLater(link: "https://example.com/1", title: "Test Article", feedName: "Tech Blog")
        XCTAssertNotNil(item)
        XCTAssertEqual(item?.articleTitle, "Test Article")
        XCTAssertEqual(item?.feedName, "Tech Blog")
        XCTAssertEqual(item?.priority, .normal)
        XCTAssertEqual(item?.status, .pending)
        XCTAssertEqual(item?.snoozeCount, 0)
    }

    func testSaveForLater_DuplicateReturnsNil() {
        reminder.saveForLater(link: "https://example.com/1", title: "First")
        let dup = reminder.saveForLater(link: "https://example.com/1", title: "Duplicate")
        XCTAssertNil(dup)
    }

    func testSaveForLater_WithPriorityAndTags() {
        let item = reminder.saveForLater(
            link: "https://example.com/2", title: "High Priority",
            priority: .high, notes: "Must read", tags: ["AI", "Research"]
        )
        XCTAssertEqual(item?.priority, .high)
        XCTAssertEqual(item?.notes, "Must read")
        XCTAssertEqual(item?.tags, ["ai", "research"])
    }

    func testSaveForLater_TagNormalization() {
        let item = reminder.saveForLater(
            link: "https://example.com/3", title: "Tagged",
            tags: [" Swift ", "iOS", "", "  "]
        )
        XCTAssertEqual(item?.tags, ["swift", "ios"])
    }

    func testRemoveItem_ById() {
        let item = reminder.saveForLater(link: "https://example.com/1", title: "Test")!
        XCTAssertTrue(reminder.removeItem(id: item.id))
        XCTAssertNil(reminder.item(withId: item.id))
    }

    func testRemoveItem_ByLink() {
        reminder.saveForLater(link: "https://example.com/1", title: "Test")
        XCTAssertTrue(reminder.removeItem(link: "https://example.com/1"))
        XCTAssertFalse(reminder.isSaved(link: "https://example.com/1"))
    }

    func testRemoveItem_NonexistentReturnsFalse() {
        XCTAssertFalse(reminder.removeItem(id: "nonexistent"))
        XCTAssertFalse(reminder.removeItem(link: "https://nope.com"))
    }

    func testClearAll() {
        reminder.saveForLater(link: "https://example.com/1", title: "A")
        reminder.saveForLater(link: "https://example.com/2", title: "B")
        reminder.clearAll()
        XCTAssertTrue(reminder.allItemsSorted().isEmpty)
    }

    // MARK: - Status Updates

    func testMarkCompleted() {
        let item = reminder.saveForLater(link: "https://example.com/1", title: "Test")!
        XCTAssertTrue(reminder.markCompleted(id: item.id))
        XCTAssertEqual(reminder.item(withId: item.id)?.status, .completed)
        XCTAssertNotNil(reminder.item(withId: item.id)?.completedAt)
    }

    func testMarkCompleted_ByLink() {
        reminder.saveForLater(link: "https://example.com/1", title: "Test")
        XCTAssertTrue(reminder.markCompleted(link: "https://example.com/1"))
    }

    func testMarkCompleted_AlreadyCompleted() {
        let item = reminder.saveForLater(link: "https://example.com/1", title: "Test")!
        reminder.markCompleted(id: item.id)
        XCTAssertFalse(reminder.markCompleted(id: item.id))
    }

    func testDismiss() {
        let item = reminder.saveForLater(link: "https://example.com/1", title: "Test")!
        XCTAssertTrue(reminder.dismiss(id: item.id))
        XCTAssertEqual(reminder.item(withId: item.id)?.status, .dismissed)
    }

    func testDismiss_CompletedItemFails() {
        let item = reminder.saveForLater(link: "https://example.com/1", title: "Test")!
        reminder.markCompleted(id: item.id)
        XCTAssertFalse(reminder.dismiss(id: item.id))
    }

    // MARK: - Snooze

    func testSnooze_Preset() {
        let now = Date()
        let item = reminder.saveForLater(link: "https://example.com/1", title: "Test", at: now)!
        XCTAssertTrue(reminder.snooze(id: item.id, preset: .fourHours, from: now))
        let updated = reminder.item(withId: item.id)!
        XCTAssertEqual(updated.status, .snoozed)
        XCTAssertEqual(updated.snoozeCount, 1)
        let diff = updated.nextReminderDate.timeIntervalSince(now)
        XCTAssertEqual(diff, 4 * 3600, accuracy: 60)
    }

    func testSnooze_CustomDate() {
        let now = Date()
        let future = now.addingTimeInterval(86400)
        let item = reminder.saveForLater(link: "https://example.com/1", title: "Test", at: now)!
        XCTAssertTrue(reminder.snoozeUntil(id: item.id, date: future, from: now))
        XCTAssertEqual(reminder.item(withId: item.id)?.snoozeCount, 1)
    }

    func testSnooze_PastDateFails() {
        let now = Date()
        let past = now.addingTimeInterval(-3600)
        let item = reminder.saveForLater(link: "https://example.com/1", title: "Test", at: now)!
        XCTAssertFalse(reminder.snoozeUntil(id: item.id, date: past, from: now))
    }

    func testSnooze_MaxSnoozesEnforced() {
        let now = Date()
        let item = reminder.saveForLater(link: "https://example.com/1", title: "Test", at: now)!
        for i in 0..<ReadLaterItem.maxSnoozes {
            let result = reminder.snooze(id: item.id, preset: .oneHour, from: now)
            XCTAssertTrue(result, "Snooze \(i+1) should succeed")
        }
        XCTAssertFalse(reminder.snooze(id: item.id, preset: .oneHour, from: now))
    }

    func testSnooze_DismissedItemFails() {
        let item = reminder.saveForLater(link: "https://example.com/1", title: "Test")!
        reminder.dismiss(id: item.id)
        XCTAssertFalse(reminder.snooze(id: item.id, preset: .tomorrow))
    }

    // MARK: - Priority & Notes

    func testUpdatePriority() {
        let item = reminder.saveForLater(link: "https://example.com/1", title: "Test")!
        XCTAssertTrue(reminder.updatePriority(id: item.id, to: .urgent))
        XCTAssertEqual(reminder.item(withId: item.id)?.priority, .urgent)
    }

    func testUpdateNotes() {
        let item = reminder.saveForLater(link: "https://example.com/1", title: "Test")!
        XCTAssertTrue(reminder.updateNotes(id: item.id, notes: "Important context"))
        XCTAssertEqual(reminder.item(withId: item.id)?.notes, "Important context")
    }

    func testAddTag() {
        let item = reminder.saveForLater(link: "https://example.com/1", title: "Test")!
        XCTAssertTrue(reminder.addTag(id: item.id, tag: "tech"))
        XCTAssertTrue(reminder.item(withId: item.id)!.tags.contains("tech"))
    }

    func testAddTag_DuplicateFails() {
        let item = reminder.saveForLater(link: "https://example.com/1", title: "Test", tags: ["tech"])!
        XCTAssertFalse(reminder.addTag(id: item.id, tag: "tech"))
    }

    func testRemoveTag() {
        let item = reminder.saveForLater(link: "https://example.com/1", title: "Test", tags: ["tech", "ai"])!
        XCTAssertTrue(reminder.removeTag(id: item.id, tag: "tech"))
        XCTAssertFalse(reminder.item(withId: item.id)!.tags.contains("tech"))
    }

    // MARK: - Queries

    func testIsSaved() {
        reminder.saveForLater(link: "https://example.com/1", title: "Test")
        XCTAssertTrue(reminder.isSaved(link: "https://example.com/1"))
        XCTAssertFalse(reminder.isSaved(link: "https://example.com/nope"))
    }

    func testIsSaved_CompletedReturnsFalse() {
        let item = reminder.saveForLater(link: "https://example.com/1", title: "Test")!
        reminder.markCompleted(id: item.id)
        XCTAssertFalse(reminder.isSaved(link: "https://example.com/1"))
    }

    func testAllItemsSorted_ByPriorityThenDate() {
        let now = Date()
        reminder.saveForLater(link: "https://example.com/1", title: "Low", priority: .low, at: now)
        reminder.saveForLater(link: "https://example.com/2", title: "High", priority: .high, at: now)
        reminder.saveForLater(link: "https://example.com/3", title: "Normal", priority: .normal, at: now)
        let sorted = reminder.allItemsSorted()
        XCTAssertEqual(sorted[0].articleTitle, "High")
        XCTAssertEqual(sorted[1].articleTitle, "Normal")
        XCTAssertEqual(sorted[2].articleTitle, "Low")
    }

    func testItemsByStatus() {
        let item1 = reminder.saveForLater(link: "https://example.com/1", title: "A")!
        reminder.saveForLater(link: "https://example.com/2", title: "B")
        reminder.markCompleted(id: item1.id)
        XCTAssertEqual(reminder.items(withStatus: .completed).count, 1)
        XCTAssertEqual(reminder.items(withStatus: .pending).count, 1)
    }

    func testItemsByPriority() {
        reminder.saveForLater(link: "https://example.com/1", title: "A", priority: .high)
        reminder.saveForLater(link: "https://example.com/2", title: "B", priority: .low)
        reminder.saveForLater(link: "https://example.com/3", title: "C", priority: .high)
        XCTAssertEqual(reminder.items(withPriority: .high).count, 2)
    }

    func testItemsByTag() {
        reminder.saveForLater(link: "https://example.com/1", title: "A", tags: ["tech"])
        reminder.saveForLater(link: "https://example.com/2", title: "B", tags: ["science"])
        reminder.saveForLater(link: "https://example.com/3", title: "C", tags: ["tech", "ai"])
        XCTAssertEqual(reminder.items(taggedWith: "tech").count, 2)
    }

    func testItemsByFeed() {
        reminder.saveForLater(link: "https://example.com/1", title: "A", feedName: "TechBlog")
        reminder.saveForLater(link: "https://example.com/2", title: "B", feedName: "ScienceDaily")
        XCTAssertEqual(reminder.items(fromFeed: "TechBlog").count, 1)
    }

    func testSearch() {
        reminder.saveForLater(link: "https://example.com/1", title: "Swift Programming Guide")
        reminder.saveForLater(link: "https://example.com/2", title: "Python Tutorial",
                             notes: "Great swift comparison")
        reminder.saveForLater(link: "https://example.com/3", title: "Rust Basics")
        XCTAssertEqual(reminder.search(query: "swift").count, 2)
    }

    func testSearch_ByTag() {
        reminder.saveForLater(link: "https://example.com/1", title: "Article", tags: ["machine-learning"])
        XCTAssertEqual(reminder.search(query: "machine").count, 1)
    }

    func testSearch_EmptyQuery() {
        reminder.saveForLater(link: "https://example.com/1", title: "Test")
        XCTAssertEqual(reminder.search(query: "nonexistent").count, 0)
    }

    // MARK: - Reminder Generation

    func testDueReminders_NoneWhenFresh() {
        reminder.saveForLater(link: "https://example.com/1", title: "Test")
        let batch = reminder.dueReminders()
        XCTAssertTrue(batch.isEmpty)
    }

    func testDueReminders_AfterIntervalPassed() {
        let past = Date().addingTimeInterval(-4 * 3600 - 1)
        reminder.saveForLater(link: "https://example.com/1", title: "Urgent", priority: .urgent, at: past)
        let batch = reminder.dueReminders()
        XCTAssertEqual(batch.urgent.count, 1)
        XCTAssertFalse(batch.isEmpty)
    }

    func testDueReminders_GroupedByPriority() {
        let past = Date().addingTimeInterval(-8 * 24 * 3600)
        reminder.saveForLater(link: "https://example.com/1", title: "U", priority: .urgent, at: past)
        reminder.saveForLater(link: "https://example.com/2", title: "H", priority: .high, at: past)
        reminder.saveForLater(link: "https://example.com/3", title: "N", priority: .normal, at: past)
        reminder.saveForLater(link: "https://example.com/4", title: "L", priority: .low, at: past)
        let batch = reminder.dueReminders()
        XCTAssertEqual(batch.urgent.count, 1)
        XCTAssertEqual(batch.high.count, 1)
        XCTAssertEqual(batch.normal.count, 1)
        XCTAssertEqual(batch.low.count, 1)
        XCTAssertEqual(batch.totalCount, 4)
    }

    func testAcknowledgeReminder() {
        let past = Date().addingTimeInterval(-5 * 3600)
        let item = reminder.saveForLater(link: "https://example.com/1", title: "Test", priority: .urgent, at: past)!
        XCTAssertTrue(reminder.acknowledgeReminder(id: item.id))
        XCTAssertTrue(reminder.dueReminders().isEmpty)
    }

    func testAcknowledgeReminder_SetsLastRemindedAt() {
        let past = Date().addingTimeInterval(-5 * 3600)
        let item = reminder.saveForLater(link: "https://example.com/1", title: "Test", priority: .urgent, at: past)!
        reminder.acknowledgeReminder(id: item.id)
        XCTAssertNotNil(reminder.item(withId: item.id)?.lastRemindedAt)
    }

    // MARK: - Expiration

    func testProcessExpirations() {
        let old = Date().addingTimeInterval(-91 * 24 * 3600)
        reminder.saveForLater(link: "https://example.com/1", title: "Old Article", at: old)
        let expired = reminder.processExpirations()
        XCTAssertEqual(expired, 1)
        XCTAssertEqual(reminder.item(forLink: "https://example.com/1")?.status, .expired)
    }

    func testProcessExpirations_CompletedNotExpired() {
        let old = Date().addingTimeInterval(-91 * 24 * 3600)
        let item = reminder.saveForLater(link: "https://example.com/1", title: "Done", at: old)!
        reminder.markCompleted(id: item.id)
        let expired = reminder.processExpirations()
        XCTAssertEqual(expired, 0)
    }

    func testProcessExpirations_RecentNotExpired() {
        reminder.saveForLater(link: "https://example.com/1", title: "Fresh")
        let expired = reminder.processExpirations()
        XCTAssertEqual(expired, 0)
    }

    // MARK: - Auto-Escalation

    func testAutoEscalate() {
        let old = Date().addingTimeInterval(-150 * 3600)
        reminder.saveForLater(link: "https://example.com/1", title: "Test", priority: .normal, at: old)
        let escalated = reminder.autoEscalate()
        XCTAssertEqual(escalated, 1)
        XCTAssertEqual(reminder.item(forLink: "https://example.com/1")?.priority, .high)
    }

    func testAutoEscalate_UrgentNotEscalated() {
        let old = Date().addingTimeInterval(-50 * 3600)
        reminder.saveForLater(link: "https://example.com/1", title: "Test", priority: .urgent, at: old)
        let escalated = reminder.autoEscalate()
        XCTAssertEqual(escalated, 0)
    }

    func testAutoEscalate_RecentNotEscalated() {
        reminder.saveForLater(link: "https://example.com/1", title: "Test", priority: .low)
        let escalated = reminder.autoEscalate()
        XCTAssertEqual(escalated, 0)
    }

    // MARK: - Statistics

    func testStatistics() {
        let now = Date()
        let past = now.addingTimeInterval(-5 * 24 * 3600)

        let item1 = reminder.saveForLater(link: "https://example.com/1", title: "A",
                                          priority: .high, tags: ["tech"], at: past)!
        reminder.saveForLater(link: "https://example.com/2", title: "B",
                             priority: .normal, tags: ["tech", "ai"], at: past)
        let item3 = reminder.saveForLater(link: "https://example.com/3", title: "C",
                                          priority: .low, at: past)!
        reminder.markCompleted(id: item1.id)
        reminder.dismiss(id: item3.id)

        let stats = reminder.statistics(at: now)
        XCTAssertEqual(stats.totalItems, 3)
        XCTAssertEqual(stats.completedCount, 1)
        XCTAssertEqual(stats.dismissedCount, 1)
        XCTAssertEqual(stats.pendingCount, 1)
        XCTAssertEqual(stats.completionRate, 0.5, accuracy: 0.01)
        XCTAssertEqual(stats.topTags.first?.tag, "tech")
        XCTAssertEqual(stats.topTags.first?.count, 2)
    }

    func testStatistics_EmptyQueue() {
        let stats = reminder.statistics()
        XCTAssertEqual(stats.totalItems, 0)
        XCTAssertEqual(stats.completionRate, 0)
        XCTAssertEqual(stats.averageAgeInDays, 0)
    }

    func testStatistics_SnoozeTracking() {
        let now = Date()
        let item = reminder.saveForLater(link: "https://example.com/1", title: "Test", at: now)!
        reminder.snooze(id: item.id, preset: .oneHour, from: now)
        reminder.snooze(id: item.id, preset: .fourHours, from: now)
        let stats = reminder.statistics(at: now)
        XCTAssertEqual(stats.totalSnoozes, 2)
        XCTAssertEqual(stats.snoozedCount, 1)
    }

    // MARK: - Export

    func testExportJSON() {
        reminder.saveForLater(link: "https://example.com/1", title: "Test")
        let json = reminder.exportJSON()
        XCTAssertNotNil(json)
        XCTAssertTrue(json!.contains("Test"))
        XCTAssertTrue(json!.contains("example.com"))
    }

    func testExportJSON_EmptyQueue() {
        let json = reminder.exportJSON()
        XCTAssertNotNil(json)
        XCTAssertTrue(json!.contains("[]"))
    }

    func testExportMarkdown() {
        reminder.saveForLater(link: "https://example.com/1", title: "Normal Item")
        reminder.saveForLater(link: "https://example.com/2", title: "Urgent Item", priority: .urgent)
        let md = reminder.exportMarkdown()
        XCTAssertTrue(md.contains("# Read Later"))
        XCTAssertTrue(md.contains("Urgent Priority"))
        XCTAssertTrue(md.contains("[Normal Item]"))
        XCTAssertTrue(md.contains("[Urgent Item]"))
    }

    func testExportMarkdown_WithNotes() {
        reminder.saveForLater(link: "https://example.com/1", title: "Test",
                             notes: "Important context here")
        let md = reminder.exportMarkdown()
        XCTAssertTrue(md.contains("> Important context here"))
    }

    func testExportMarkdown_SnoozeCount() {
        let now = Date()
        let item = reminder.saveForLater(link: "https://example.com/1", title: "Snoozed", at: now)!
        reminder.snooze(id: item.id, preset: .oneHour, from: now)
        let md = reminder.exportMarkdown()
        XCTAssertTrue(md.contains("snoozed 1x"))
    }

    func testExportMarkdown_EmptyQueue() {
        let md = reminder.exportMarkdown()
        XCTAssertTrue(md.contains("No items saved"))
    }

    func testExportMarkdown_FeedName() {
        reminder.saveForLater(link: "https://example.com/1", title: "Test", feedName: "TechCrunch")
        let md = reminder.exportMarkdown()
        XCTAssertTrue(md.contains("TechCrunch"))
    }

    // MARK: - SnoozePreset

    func testSnoozePreset_OneHour() {
        let now = Date()
        let snoozeDate = SnoozePreset.oneHour.snoozeDate(from: now)
        XCTAssertEqual(snoozeDate.timeIntervalSince(now), 3600, accuracy: 1)
    }

    func testSnoozePreset_FourHours() {
        let now = Date()
        let snoozeDate = SnoozePreset.fourHours.snoozeDate(from: now)
        XCTAssertEqual(snoozeDate.timeIntervalSince(now), 4 * 3600, accuracy: 1)
    }

    func testSnoozePreset_Tomorrow() {
        let now = Date()
        let snoozeDate = SnoozePreset.tomorrow.snoozeDate(from: now)
        XCTAssertEqual(snoozeDate.timeIntervalSince(now), 24 * 3600, accuracy: 1)
    }

    func testSnoozePreset_NextWeek() {
        let now = Date()
        let snoozeDate = SnoozePreset.nextWeek.snoozeDate(from: now)
        XCTAssertEqual(snoozeDate.timeIntervalSince(now), 7 * 24 * 3600, accuracy: 1)
    }

    func testSnoozePreset_NextMonth() {
        let now = Date()
        let snoozeDate = SnoozePreset.nextMonth.snoozeDate(from: now)
        XCTAssertEqual(snoozeDate.timeIntervalSince(now), 30 * 24 * 3600, accuracy: 1)
    }

    // MARK: - ReminderPriority

    func testPriorityComparable() {
        XCTAssertTrue(ReminderPriority.low < ReminderPriority.normal)
        XCTAssertTrue(ReminderPriority.normal < ReminderPriority.high)
        XCTAssertTrue(ReminderPriority.high < ReminderPriority.urgent)
    }

    func testPriorityLabels() {
        XCTAssertEqual(ReminderPriority.low.label, "Low")
        XCTAssertEqual(ReminderPriority.normal.label, "Normal")
        XCTAssertEqual(ReminderPriority.high.label, "High")
        XCTAssertEqual(ReminderPriority.urgent.label, "Urgent")
    }

    func testPriorityEscalation() {
        XCTAssertEqual(ReminderPriority.low.escalated, .normal)
        XCTAssertEqual(ReminderPriority.normal.escalated, .high)
        XCTAssertEqual(ReminderPriority.high.escalated, .urgent)
        XCTAssertNil(ReminderPriority.urgent.escalated)
    }

    func testPriorityIntervals() {
        XCTAssertEqual(ReminderPriority.urgent.defaultInterval, 4 * 3600)
        XCTAssertEqual(ReminderPriority.high.defaultInterval, 24 * 3600)
        XCTAssertEqual(ReminderPriority.normal.defaultInterval, 3 * 24 * 3600)
        XCTAssertEqual(ReminderPriority.low.defaultInterval, 7 * 24 * 3600)
    }

    // MARK: - ReadLaterItem

    func testIsDue_PendingAndPastDate() {
        let past = Date().addingTimeInterval(-3600)
        let item = ReadLaterItem(
            id: "test", articleLink: "https://example.com", articleTitle: "Test",
            feedName: "", savedAt: Date(), priority: .normal, status: .pending,
            nextReminderDate: past, snoozeCount: 0, tags: []
        )
        XCTAssertTrue(item.isDue())
    }

    func testIsDue_CompletedNotDue() {
        let past = Date().addingTimeInterval(-3600)
        let item = ReadLaterItem(
            id: "test", articleLink: "https://example.com", articleTitle: "Test",
            feedName: "", savedAt: Date(), priority: .normal, status: .completed,
            nextReminderDate: past, snoozeCount: 0, tags: []
        )
        XCTAssertFalse(item.isDue())
    }

    func testIsDue_FutureDateNotDue() {
        let future = Date().addingTimeInterval(3600)
        let item = ReadLaterItem(
            id: "test", articleLink: "https://example.com", articleTitle: "Test",
            feedName: "", savedAt: Date(), priority: .normal, status: .pending,
            nextReminderDate: future, snoozeCount: 0, tags: []
        )
        XCTAssertFalse(item.isDue())
    }

    func testIsExpired_OldItem() {
        let old = Date().addingTimeInterval(-91 * 24 * 3600)
        let item = ReadLaterItem(
            id: "test", articleLink: "https://example.com", articleTitle: "Test",
            feedName: "", savedAt: old, priority: .normal, status: .pending,
            nextReminderDate: Date(), snoozeCount: 0, tags: []
        )
        XCTAssertTrue(item.isExpired())
    }

    func testIsExpired_RecentItem() {
        let item = ReadLaterItem(
            id: "test", articleLink: "https://example.com", articleTitle: "Test",
            feedName: "", savedAt: Date(), priority: .normal, status: .pending,
            nextReminderDate: Date(), snoozeCount: 0, tags: []
        )
        XCTAssertFalse(item.isExpired())
    }

    func testAgeInDays() {
        let fiveDaysAgo = Date().addingTimeInterval(-5 * 24 * 3600)
        let item = ReadLaterItem(
            id: "test", articleLink: "https://example.com", articleTitle: "Test",
            feedName: "", savedAt: fiveDaysAgo, priority: .normal, status: .pending,
            nextReminderDate: Date(), snoozeCount: 0, tags: []
        )
        XCTAssertEqual(item.ageInDays(), 5, accuracy: 0.1)
    }

    func testMaxSnoozes() {
        XCTAssertEqual(ReadLaterItem.maxSnoozes, 10)
    }

    func testExpirationDays() {
        XCTAssertEqual(ReadLaterItem.expirationDays, 90)
    }
}
