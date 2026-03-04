import XCTest
@testable import FeedReader

class ReadingQueueManagerTests: XCTestCase {

    // MARK: - Helpers

    func makeManager(_ items: [ReadingQueueManager.QueueItem] = []) -> ReadingQueueManager {
        return ReadingQueueManager(testItems: items)
    }

    func makeStory(_ title: String = "Test Article",
                   link: String = "https://example.com/article",
                   feed: String = "Test Feed",
                   words: Int = 1000) -> ReadingQueueManager.StoryRef {
        return ReadingQueueManager.StoryRef(
            title: title, link: link, sourceFeedName: feed, wordCount: words)
    }

    // MARK: - Enqueue

    func testEnqueueAddsItem() {
        let mgr = makeManager()
        let item = mgr.enqueue(story: makeStory())
        XCTAssertNotNil(item)
        XCTAssertEqual(mgr.items.count, 1)
        XCTAssertEqual(mgr.items.first?.articleTitle, "Test Article")
    }

    func testEnqueueDefaultsToNormalPriority() {
        let mgr = makeManager()
        let item = mgr.enqueue(story: makeStory())!
        XCTAssertEqual(item.priority, .normal)
    }

    func testEnqueueRespectsCustomPriority() {
        let mgr = makeManager()
        let item = mgr.enqueue(story: makeStory(), priority: .urgent)!
        XCTAssertEqual(item.priority, .urgent)
    }

    func testEnqueueDuplicateLinkReturnsNil() {
        let mgr = makeManager()
        _ = mgr.enqueue(story: makeStory(link: "https://a.com/1"))
        let dup = mgr.enqueue(story: makeStory(link: "https://a.com/1"))
        XCTAssertNil(dup)
        XCTAssertEqual(mgr.items.count, 1)
    }

    func testEnqueueDifferentLinksAllowed() {
        let mgr = makeManager()
        _ = mgr.enqueue(story: makeStory(link: "https://a.com/1"))
        _ = mgr.enqueue(story: makeStory(link: "https://a.com/2"))
        XCTAssertEqual(mgr.items.count, 2)
    }

    func testEnqueueCustomReadingTime() {
        let mgr = makeManager()
        let item = mgr.enqueue(story: makeStory(), estimatedMinutes: 15.0)!
        XCTAssertEqual(item.estimatedReadingTimeMinutes, 15.0)
    }

    // MARK: - Dequeue

    func testDequeueById() {
        let mgr = makeManager()
        let item = mgr.enqueue(story: makeStory())!
        let removed = mgr.dequeue(id: item.id)
        XCTAssertNotNil(removed)
        XCTAssertEqual(mgr.items.count, 0)
    }

    func testDequeueByLink() {
        let mgr = makeManager()
        _ = mgr.enqueue(story: makeStory(link: "https://a.com/1"))
        let removed = mgr.dequeue(link: "https://a.com/1")
        XCTAssertNotNil(removed)
        XCTAssertEqual(mgr.items.count, 0)
    }

    func testDequeueNonexistentReturnsNil() {
        let mgr = makeManager()
        XCTAssertNil(mgr.dequeue(id: "nonexistent"))
    }

    func testDequeueRemovesFromIndex() {
        let mgr = makeManager()
        let item = mgr.enqueue(story: makeStory(link: "https://a.com/1"))!
        _ = mgr.dequeue(id: item.id)
        XCTAssertFalse(mgr.isQueued(link: "https://a.com/1"))
        // Can re-add after removal
        let reAdded = mgr.enqueue(story: makeStory(link: "https://a.com/1"))
        XCTAssertNotNil(reAdded)
    }

    // MARK: - IsQueued

    func testIsQueuedTrue() {
        let mgr = makeManager()
        _ = mgr.enqueue(story: makeStory(link: "https://a.com/1"))
        XCTAssertTrue(mgr.isQueued(link: "https://a.com/1"))
    }

    func testIsQueuedFalse() {
        let mgr = makeManager()
        XCTAssertFalse(mgr.isQueued(link: "https://a.com/unknown"))
    }

    // MARK: - NextUp

    func testNextUpReturnsPending() {
        let mgr = makeManager()
        let item = mgr.enqueue(story: makeStory())!
        XCTAssertEqual(mgr.nextUp()?.id, item.id)
    }

    func testNextUpSkipsCompleted() {
        let mgr = makeManager()
        let first = mgr.enqueue(story: makeStory(link: "https://a.com/1"))!
        let second = mgr.enqueue(story: makeStory(link: "https://a.com/2"))!
        _ = mgr.markCompleted(id: first.id)
        XCTAssertEqual(mgr.nextUp()?.id, second.id)
    }

    func testNextUpNilWhenAllCompleted() {
        let mgr = makeManager()
        let item = mgr.enqueue(story: makeStory())!
        _ = mgr.markCompleted(id: item.id)
        XCTAssertNil(mgr.nextUp())
    }

    func testNextUpNilWhenEmpty() {
        let mgr = makeManager()
        XCTAssertNil(mgr.nextUp())
    }

    // MARK: - Completion

    func testMarkCompletedSetsFlag() {
        let mgr = makeManager()
        let item = mgr.enqueue(story: makeStory())!
        XCTAssertTrue(mgr.markCompleted(id: item.id))
        XCTAssertTrue(mgr.items.first!.isCompleted)
        XCTAssertNotNil(mgr.items.first!.completedDate)
    }

    func testMarkCompletedAlreadyCompletedReturnsFalse() {
        let mgr = makeManager()
        let item = mgr.enqueue(story: makeStory())!
        _ = mgr.markCompleted(id: item.id)
        XCTAssertFalse(mgr.markCompleted(id: item.id))
    }

    func testMarkIncomplete() {
        let mgr = makeManager()
        let item = mgr.enqueue(story: makeStory())!
        _ = mgr.markCompleted(id: item.id)
        XCTAssertTrue(mgr.markIncomplete(id: item.id))
        XCTAssertFalse(mgr.items.first!.isCompleted)
        XCTAssertNil(mgr.items.first!.completedDate)
    }

    func testMarkIncompleteAlreadyPendingReturnsFalse() {
        let mgr = makeManager()
        let item = mgr.enqueue(story: makeStory())!
        XCTAssertFalse(mgr.markIncomplete(id: item.id))
    }

    func testClearCompleted() {
        let mgr = makeManager()
        let a = mgr.enqueue(story: makeStory(link: "https://a.com/1"))!
        _ = mgr.enqueue(story: makeStory(link: "https://a.com/2"))
        _ = mgr.markCompleted(id: a.id)
        let removed = mgr.clearCompleted()
        XCTAssertEqual(removed, 1)
        XCTAssertEqual(mgr.items.count, 1)
    }

    func testClearCompletedNoneCompleted() {
        let mgr = makeManager()
        _ = mgr.enqueue(story: makeStory())
        XCTAssertEqual(mgr.clearCompleted(), 0)
    }

    // MARK: - Reordering

    func testMoveToTop() {
        let mgr = makeManager()
        _ = mgr.enqueue(story: makeStory("A", link: "https://a.com/a"))
        _ = mgr.enqueue(story: makeStory("B", link: "https://a.com/b"))
        let c = mgr.enqueue(story: makeStory("C", link: "https://a.com/c"))!
        XCTAssertTrue(mgr.moveToTop(id: c.id))
        XCTAssertEqual(mgr.items[0].articleTitle, "C")
    }

    func testMoveToBottom() {
        let mgr = makeManager()
        let a = mgr.enqueue(story: makeStory("A", link: "https://a.com/a"))!
        _ = mgr.enqueue(story: makeStory("B", link: "https://a.com/b"))
        _ = mgr.enqueue(story: makeStory("C", link: "https://a.com/c"))
        XCTAssertTrue(mgr.moveToBottom(id: a.id))
        XCTAssertEqual(mgr.items.last?.articleTitle, "A")
    }

    func testMoveUp() {
        let mgr = makeManager()
        _ = mgr.enqueue(story: makeStory("A", link: "https://a.com/a"))
        let b = mgr.enqueue(story: makeStory("B", link: "https://a.com/b"))!
        XCTAssertTrue(mgr.moveUp(id: b.id))
        XCTAssertEqual(mgr.items[0].articleTitle, "B")
    }

    func testMoveDown() {
        let mgr = makeManager()
        let a = mgr.enqueue(story: makeStory("A", link: "https://a.com/a"))!
        _ = mgr.enqueue(story: makeStory("B", link: "https://a.com/b"))
        XCTAssertTrue(mgr.moveDown(id: a.id))
        XCTAssertEqual(mgr.items[0].articleTitle, "B")
    }

    func testMoveUpAtTopReturnsFalse() {
        let mgr = makeManager()
        let a = mgr.enqueue(story: makeStory("A", link: "https://a.com/a"))!
        XCTAssertFalse(mgr.moveUp(id: a.id))
    }

    func testMoveDownAtBottomReturnsFalse() {
        let mgr = makeManager()
        let a = mgr.enqueue(story: makeStory("A", link: "https://a.com/a"))!
        XCTAssertFalse(mgr.moveDown(id: a.id))
    }

    func testMoveNonexistentReturnsFalse() {
        let mgr = makeManager()
        XCTAssertFalse(mgr.move(id: "fake", to: 0))
    }

    // MARK: - Priority

    func testSetPriority() {
        let mgr = makeManager()
        let item = mgr.enqueue(story: makeStory())!
        XCTAssertTrue(mgr.setPriority(id: item.id, priority: .urgent))
        XCTAssertEqual(mgr.items.first?.priority, .urgent)
    }

    func testSetSamePriorityReturnsFalse() {
        let mgr = makeManager()
        let item = mgr.enqueue(story: makeStory())!
        XCTAssertFalse(mgr.setPriority(id: item.id, priority: .normal))
    }

    func testSortByPriority() {
        let mgr = makeManager()
        let a = mgr.enqueue(story: makeStory("Low", link: "https://a.com/lo"), priority: .low)!
        let b = mgr.enqueue(story: makeStory("Urgent", link: "https://a.com/ur"), priority: .urgent)!
        let c = mgr.enqueue(story: makeStory("Normal", link: "https://a.com/no"), priority: .normal)!
        mgr.sortByPriority()
        XCTAssertEqual(mgr.items[0].id, b.id) // urgent first
        XCTAssertEqual(mgr.items[1].id, c.id) // normal
        XCTAssertEqual(mgr.items[2].id, a.id) // low last
    }

    // MARK: - Sorting

    func testSortByReadingTime() {
        let mgr = makeManager()
        _ = mgr.enqueue(story: makeStory("Long", link: "https://a.com/1"), estimatedMinutes: 30)
        _ = mgr.enqueue(story: makeStory("Short", link: "https://a.com/2"), estimatedMinutes: 2)
        _ = mgr.enqueue(story: makeStory("Medium", link: "https://a.com/3"), estimatedMinutes: 10)
        mgr.sortByReadingTime()
        XCTAssertEqual(mgr.items[0].articleTitle, "Short")
        XCTAssertEqual(mgr.items[1].articleTitle, "Medium")
        XCTAssertEqual(mgr.items[2].articleTitle, "Long")
    }

    func testSortByDateAdded() {
        let mgr = makeManager()
        // Add in order — oldest first by default (FIFO)
        _ = mgr.enqueue(story: makeStory("First", link: "https://a.com/1"))
        _ = mgr.enqueue(story: makeStory("Second", link: "https://a.com/2"))
        // Rearrange then sort back
        mgr.moveToTop(id: mgr.items.last!.id)
        mgr.sortByDateAdded()
        XCTAssertEqual(mgr.items[0].articleTitle, "First")
    }

    // MARK: - Notes

    func testSetNote() {
        let mgr = makeManager()
        let item = mgr.enqueue(story: makeStory())!
        XCTAssertTrue(mgr.setNote(id: item.id, note: "Important context"))
        XCTAssertEqual(mgr.items.first?.notes, "Important context")
    }

    func testClearNote() {
        let mgr = makeManager()
        let item = mgr.enqueue(story: makeStory())!
        _ = mgr.setNote(id: item.id, note: "Some note")
        _ = mgr.setNote(id: item.id, note: nil)
        XCTAssertNil(mgr.items.first?.notes)
    }

    func testSetNoteNonexistentReturnsFalse() {
        let mgr = makeManager()
        XCTAssertFalse(mgr.setNote(id: "fake", note: "x"))
    }

    // MARK: - Filtering

    func testPendingItems() {
        let mgr = makeManager()
        let a = mgr.enqueue(story: makeStory(link: "https://a.com/1"))!
        _ = mgr.enqueue(story: makeStory(link: "https://a.com/2"))
        _ = mgr.markCompleted(id: a.id)
        XCTAssertEqual(mgr.pendingItems().count, 1)
    }

    func testCompletedItems() {
        let mgr = makeManager()
        let a = mgr.enqueue(story: makeStory(link: "https://a.com/1"))!
        _ = mgr.enqueue(story: makeStory(link: "https://a.com/2"))
        _ = mgr.markCompleted(id: a.id)
        XCTAssertEqual(mgr.completedItems().count, 1)
    }

    func testItemsByPriority() {
        let mgr = makeManager()
        _ = mgr.enqueue(story: makeStory(link: "https://a.com/1"), priority: .high)
        _ = mgr.enqueue(story: makeStory(link: "https://a.com/2"), priority: .low)
        _ = mgr.enqueue(story: makeStory(link: "https://a.com/3"), priority: .high)
        XCTAssertEqual(mgr.items(withPriority: .high).count, 2)
        XCTAssertEqual(mgr.items(withPriority: .low).count, 1)
    }

    func testItemsByFeed() {
        let mgr = makeManager()
        _ = mgr.enqueue(story: makeStory(link: "https://a.com/1", feed: "TechCrunch"))
        _ = mgr.enqueue(story: makeStory(link: "https://a.com/2", feed: "Ars Technica"))
        _ = mgr.enqueue(story: makeStory(link: "https://a.com/3", feed: "TechCrunch"))
        XCTAssertEqual(mgr.items(fromFeed: "TechCrunch").count, 2)
    }

    // MARK: - Statistics

    func testStatsEmpty() {
        let mgr = makeManager()
        let s = mgr.stats()
        XCTAssertEqual(s.totalItems, 0)
        XCTAssertEqual(s.pendingItems, 0)
        XCTAssertEqual(s.completedItems, 0)
        XCTAssertEqual(s.completionRate, 0.0)
        XCTAssertNil(s.oldestPendingDate)
    }

    func testStatsWithItems() {
        let mgr = makeManager()
        let a = mgr.enqueue(story: makeStory(link: "https://a.com/1"), estimatedMinutes: 10)!
        _ = mgr.enqueue(story: makeStory(link: "https://a.com/2"), estimatedMinutes: 20)
        _ = mgr.markCompleted(id: a.id)
        let s = mgr.stats()
        XCTAssertEqual(s.totalItems, 2)
        XCTAssertEqual(s.pendingItems, 1)
        XCTAssertEqual(s.completedItems, 1)
        XCTAssertEqual(s.completionRate, 50.0)
        XCTAssertEqual(s.totalEstimatedMinutes, 30.0)
        XCTAssertEqual(s.pendingEstimatedMinutes, 20.0)
        XCTAssertEqual(s.averageReadingTime, 15.0)
    }

    func testStatsByPriority() {
        let mgr = makeManager()
        _ = mgr.enqueue(story: makeStory(link: "https://a.com/1"), priority: .high)
        _ = mgr.enqueue(story: makeStory(link: "https://a.com/2"), priority: .high)
        _ = mgr.enqueue(story: makeStory(link: "https://a.com/3"), priority: .low)
        let s = mgr.stats()
        XCTAssertEqual(s.itemsByPriority[.high], 2)
        XCTAssertEqual(s.itemsByPriority[.low], 1)
        XCTAssertEqual(s.itemsByPriority[.normal], 0)
    }

    // MARK: - Estimated Time To Empty

    func testEstimatedTimeEmpty() {
        let mgr = makeManager()
        XCTAssertEqual(mgr.estimatedTimeToEmpty(), "Queue empty")
    }

    func testEstimatedTimeMinutes() {
        let mgr = makeManager()
        _ = mgr.enqueue(story: makeStory(link: "https://a.com/1"), estimatedMinutes: 25)
        XCTAssertEqual(mgr.estimatedTimeToEmpty(), "25min")
    }

    func testEstimatedTimeHours() {
        let mgr = makeManager()
        _ = mgr.enqueue(story: makeStory(link: "https://a.com/1"), estimatedMinutes: 90)
        XCTAssertEqual(mgr.estimatedTimeToEmpty(), "1h 30min")
    }

    func testEstimatedTimeExcludesCompleted() {
        let mgr = makeManager()
        let a = mgr.enqueue(story: makeStory(link: "https://a.com/1"), estimatedMinutes: 60)!
        _ = mgr.enqueue(story: makeStory(link: "https://a.com/2"), estimatedMinutes: 10)
        _ = mgr.markCompleted(id: a.id)
        XCTAssertEqual(mgr.estimatedTimeToEmpty(), "10min")
    }

    // MARK: - Reading Time Estimation

    func testEstimateReadingTimeDefault() {
        let time = ReadingQueueManager.QueueItem.estimateReadingTime(wordCount: 238)
        XCTAssertEqual(time, 1.0)
    }

    func testEstimateReadingTimeLongArticle() {
        let time = ReadingQueueManager.QueueItem.estimateReadingTime(wordCount: 2380)
        XCTAssertEqual(time, 10.0)
    }

    func testEstimateReadingTimeMinimumOneMinute() {
        let time = ReadingQueueManager.QueueItem.estimateReadingTime(wordCount: 10)
        XCTAssertEqual(time, 1.0)
    }

    func testEstimateReadingTimeZeroWords() {
        let time = ReadingQueueManager.QueueItem.estimateReadingTime(wordCount: 0)
        XCTAssertEqual(time, 1.0)
    }

    // MARK: - Bulk Operations

    func testClearAll() {
        let mgr = makeManager()
        _ = mgr.enqueue(story: makeStory(link: "https://a.com/1"))
        _ = mgr.enqueue(story: makeStory(link: "https://a.com/2"))
        let removed = mgr.clearAll()
        XCTAssertEqual(removed, 2)
        XCTAssertTrue(mgr.items.isEmpty)
    }

    func testEnqueueBatch() {
        let mgr = makeManager()
        let stories = [
            makeStory("A", link: "https://a.com/1"),
            makeStory("B", link: "https://a.com/2"),
            makeStory("C", link: "https://a.com/3"),
        ]
        let added = mgr.enqueueBatch(stories: stories, priority: .high)
        XCTAssertEqual(added, 3)
        XCTAssertEqual(mgr.items.count, 3)
        XCTAssertTrue(mgr.items.allSatisfy { $0.priority == .high })
    }

    func testEnqueueBatchSkipsDuplicates() {
        let mgr = makeManager()
        _ = mgr.enqueue(story: makeStory(link: "https://a.com/1"))
        let stories = [
            makeStory("A", link: "https://a.com/1"),  // dupe
            makeStory("B", link: "https://a.com/2"),   // new
        ]
        let added = mgr.enqueueBatch(stories: stories)
        XCTAssertEqual(added, 1)
        XCTAssertEqual(mgr.items.count, 2)
    }

    // MARK: - Priority Comparable

    func testPriorityComparable() {
        XCTAssertTrue(ReadingQueueManager.Priority.low < .normal)
        XCTAssertTrue(ReadingQueueManager.Priority.normal < .high)
        XCTAssertTrue(ReadingQueueManager.Priority.high < .urgent)
    }

    func testPriorityLabels() {
        XCTAssertEqual(ReadingQueueManager.Priority.low.label, "Low")
        XCTAssertEqual(ReadingQueueManager.Priority.normal.label, "Normal")
        XCTAssertEqual(ReadingQueueManager.Priority.high.label, "High")
        XCTAssertEqual(ReadingQueueManager.Priority.urgent.label, "Urgent")
    }
}
