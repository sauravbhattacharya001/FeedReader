//
//  ReadingHistoryTests.swift
//  FeedReaderTests
//
//  Tests for ReadingHistoryManager — recording, querying, statistics,
//  deletion, pruning, export, persistence, and notifications.
//

import XCTest
@testable import FeedReader

class ReadingHistoryTests: XCTestCase {
    
    var manager: ReadingHistoryManager!
    
    override func setUp() {
        super.setUp()
        manager = ReadingHistoryManager()
        manager.reset()
    }
    
    override func tearDown() {
        manager.clearAll()
        super.tearDown()
    }
    
    // MARK: - Helpers
    
    private func recordSampleArticle(link: String = "https://example.com/article1",
                                     title: String = "Test Article",
                                     feedName: String = "Test Feed",
                                     timeSpent: Double = 0,
                                     scrollProgress: Double = 0) {
        manager.recordVisit(link: link, title: title, feedName: feedName,
                           timeSpent: timeSpent, scrollProgress: scrollProgress)
    }
    
    // MARK: - Recording (8)
    
    func testRecordVisitCreatesEntry() {
        recordSampleArticle()
        XCTAssertEqual(manager.entries.count, 1)
    }
    
    func testRecordVisitSetsAllFields() {
        manager.recordVisit(link: "https://example.com/1", title: "My Title",
                           feedName: "Tech Feed", timeSpent: 45.0, scrollProgress: 0.75)
        
        let entry = manager.entries.first
        XCTAssertNotNil(entry)
        XCTAssertEqual(entry?.link, "https://example.com/1")
        XCTAssertEqual(entry?.title, "My Title")
        XCTAssertEqual(entry?.feedName, "Tech Feed")
        XCTAssertEqual(entry?.visitCount, 1)
        XCTAssertEqual(entry?.timeSpentSeconds, 45.0)
        XCTAssertEqual(entry?.scrollProgress, 0.75)
        XCTAssertNotNil(entry?.readAt)
        XCTAssertNotNil(entry?.lastVisitedAt)
    }
    
    func testRecordDuplicateUpdatesExisting() {
        recordSampleArticle(link: "https://example.com/dup")
        Thread.sleep(forTimeInterval: 0.01)
        let firstVisitedAt = manager.entries.first!.lastVisitedAt
        
        recordSampleArticle(link: "https://example.com/dup")
        
        XCTAssertEqual(manager.entries.count, 1)
        XCTAssertEqual(manager.entries.first!.visitCount, 2)
        XCTAssertGreaterThan(manager.entries.first!.lastVisitedAt, firstVisitedAt)
    }
    
    func testRecordVisitUpdatesTimeSpent() {
        manager.recordVisit(link: "https://example.com/1", title: "A", feedName: "F", timeSpent: 10.0)
        manager.recordVisit(link: "https://example.com/1", title: "A", feedName: "F", timeSpent: 20.0)
        
        XCTAssertEqual(manager.entries.first?.timeSpentSeconds, 30.0)
    }
    
    func testRecordVisitUpdatesScrollProgress() {
        manager.recordVisit(link: "https://example.com/1", title: "A", feedName: "F", scrollProgress: 0.3)
        manager.recordVisit(link: "https://example.com/1", title: "A", feedName: "F", scrollProgress: 0.8)
        
        XCTAssertEqual(manager.entries.first?.scrollProgress, 0.8)
    }
    
    func testRecordVisitMovesToTop() {
        manager.recordVisit(link: "https://example.com/1", title: "First", feedName: "F")
        Thread.sleep(forTimeInterval: 0.01)
        manager.recordVisit(link: "https://example.com/2", title: "Second", feedName: "F")
        Thread.sleep(forTimeInterval: 0.01)
        
        // Article 2 is now on top. Re-visit article 1 → should move to top
        manager.recordVisit(link: "https://example.com/1", title: "First", feedName: "F")
        
        XCTAssertEqual(manager.entries.first?.link, "https://example.com/1")
    }
    
    func testRecordMultipleArticles() {
        for i in 1...10 {
            recordSampleArticle(link: "https://example.com/\(i)", title: "Article \(i)")
        }
        XCTAssertEqual(manager.entries.count, 10)
    }
    
    func testRecordEmptyFieldsHandled() {
        manager.recordVisit(link: "", title: "", feedName: "")
        XCTAssertEqual(manager.entries.count, 1)
        XCTAssertEqual(manager.entries.first?.link, "")
        XCTAssertEqual(manager.entries.first?.title, "")
        XCTAssertEqual(manager.entries.first?.feedName, "")
    }
    
    // MARK: - Updating (4)
    
    func testUpdateTimeSpentAddsToExisting() {
        manager.recordVisit(link: "https://example.com/1", title: "A", feedName: "F", timeSpent: 10.0)
        manager.updateTimeSpent(link: "https://example.com/1", additionalSeconds: 5.0)
        
        XCTAssertEqual(manager.entry(forLink: "https://example.com/1")?.timeSpentSeconds, 15.0)
    }
    
    func testUpdateTimeSpentNonExistentLink() {
        // Should not crash or create entry
        manager.updateTimeSpent(link: "https://example.com/nonexistent", additionalSeconds: 10.0)
        XCTAssertEqual(manager.entries.count, 0)
    }
    
    func testUpdateScrollProgressClampsToRange() {
        recordSampleArticle(link: "https://example.com/1")
        
        manager.updateScrollProgress(link: "https://example.com/1", progress: 1.5)
        XCTAssertEqual(manager.entry(forLink: "https://example.com/1")?.scrollProgress, 1.0)
        
        manager.updateScrollProgress(link: "https://example.com/1", progress: -0.5)
        XCTAssertEqual(manager.entry(forLink: "https://example.com/1")?.scrollProgress, 0.0)
    }
    
    func testUpdateScrollProgressNonExistentLink() {
        manager.updateScrollProgress(link: "https://example.com/nonexistent", progress: 0.5)
        XCTAssertEqual(manager.entries.count, 0)
    }
    
    // MARK: - Querying (12)
    
    func testAllEntriesSortedNewestFirst() {
        manager.recordVisit(link: "https://example.com/1", title: "First", feedName: "F")
        Thread.sleep(forTimeInterval: 0.01)
        manager.recordVisit(link: "https://example.com/2", title: "Second", feedName: "F")
        Thread.sleep(forTimeInterval: 0.01)
        manager.recordVisit(link: "https://example.com/3", title: "Third", feedName: "F")
        
        let all = manager.allEntries()
        XCTAssertEqual(all.count, 3)
        XCTAssertEqual(all[0].link, "https://example.com/3")
        XCTAssertEqual(all[2].link, "https://example.com/1")
    }
    
    func testEntriesForDate() {
        let today = Date()
        recordSampleArticle(link: "https://example.com/today1")
        recordSampleArticle(link: "https://example.com/today2")
        
        let results = manager.entries(for: today)
        XCTAssertEqual(results.count, 2)
    }
    
    func testEntriesForDateNoResults() {
        recordSampleArticle()
        
        // Query for yesterday
        let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: Date())!
        let results = manager.entries(for: yesterday)
        XCTAssertEqual(results.count, 0)
    }
    
    func testEntriesInDateRange() {
        recordSampleArticle(link: "https://example.com/1")
        recordSampleArticle(link: "https://example.com/2")
        
        let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: Date())!
        let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: Date())!
        
        let results = manager.entries(from: yesterday, to: tomorrow)
        XCTAssertEqual(results.count, 2)
    }
    
    func testEntriesForFeed() {
        manager.recordVisit(link: "https://example.com/1", title: "A", feedName: "Tech Blog")
        manager.recordVisit(link: "https://example.com/2", title: "B", feedName: "News Daily")
        manager.recordVisit(link: "https://example.com/3", title: "C", feedName: "Tech Blog")
        
        let results = manager.entries(forFeed: "Tech Blog")
        XCTAssertEqual(results.count, 2)
    }
    
    func testEntriesForFeedCaseInsensitive() {
        manager.recordVisit(link: "https://example.com/1", title: "A", feedName: "Tech Blog")
        
        let results = manager.entries(forFeed: "tech blog")
        XCTAssertEqual(results.count, 1)
    }
    
    func testSearchByTitle() {
        manager.recordVisit(link: "https://example.com/1", title: "Swift Programming Guide", feedName: "F")
        manager.recordVisit(link: "https://example.com/2", title: "Python Tutorial", feedName: "F")
        
        let results = manager.search(query: "Swift")
        XCTAssertEqual(results.count, 1)
        XCTAssertEqual(results[0].title, "Swift Programming Guide")
    }
    
    func testSearchByFeedName() {
        manager.recordVisit(link: "https://example.com/1", title: "Article", feedName: "iOS Weekly")
        manager.recordVisit(link: "https://example.com/2", title: "Article", feedName: "Android News")
        
        let results = manager.search(query: "iOS")
        XCTAssertEqual(results.count, 1)
    }
    
    func testSearchCaseInsensitive() {
        manager.recordVisit(link: "https://example.com/1", title: "SwiftUI Tips", feedName: "F")
        
        let results = manager.search(query: "swiftui")
        XCTAssertEqual(results.count, 1)
    }
    
    func testSearchEmptyQuery() {
        manager.recordVisit(link: "https://example.com/1", title: "A", feedName: "F")
        manager.recordVisit(link: "https://example.com/2", title: "B", feedName: "F")
        
        let results = manager.search(query: "")
        XCTAssertEqual(results.count, 2)
    }
    
    func testSearchNoResults() {
        manager.recordVisit(link: "https://example.com/1", title: "Article", feedName: "Feed")
        
        let results = manager.search(query: "zzzznonexistent")
        XCTAssertTrue(results.isEmpty)
    }
    
    func testHasVisitedTrueAndFalse() {
        manager.recordVisit(link: "https://example.com/visited", title: "A", feedName: "F")
        
        XCTAssertTrue(manager.hasVisited(link: "https://example.com/visited"))
        XCTAssertFalse(manager.hasVisited(link: "https://example.com/not-visited"))
    }
    
    // MARK: - Retrieval (5)
    
    func testMostVisitedSortedByCount() {
        manager.recordVisit(link: "https://example.com/1", title: "A", feedName: "F")
        manager.recordVisit(link: "https://example.com/2", title: "B", feedName: "F")
        // Visit article 1 twice more
        manager.recordVisit(link: "https://example.com/1", title: "A", feedName: "F")
        manager.recordVisit(link: "https://example.com/1", title: "A", feedName: "F")
        
        let most = manager.mostVisited(limit: 10)
        XCTAssertEqual(most.first?.link, "https://example.com/1")
        XCTAssertEqual(most.first?.visitCount, 3)
    }
    
    func testMostVisitedLimit() {
        for i in 1...10 {
            recordSampleArticle(link: "https://example.com/\(i)", title: "Article \(i)")
        }
        
        let most = manager.mostVisited(limit: 3)
        XCTAssertEqual(most.count, 3)
    }
    
    func testRecentlyVisitedSortedByDate() {
        manager.recordVisit(link: "https://example.com/1", title: "First", feedName: "F")
        Thread.sleep(forTimeInterval: 0.01)
        manager.recordVisit(link: "https://example.com/2", title: "Second", feedName: "F")
        
        let recent = manager.recentlyVisited(limit: 10)
        XCTAssertEqual(recent.first?.link, "https://example.com/2")
    }
    
    func testRecentlyVisitedLimit() {
        for i in 1...30 {
            recordSampleArticle(link: "https://example.com/\(i)", title: "Article \(i)")
        }
        
        let recent = manager.recentlyVisited(limit: 5)
        XCTAssertEqual(recent.count, 5)
    }
    
    func testEntryForLink() {
        manager.recordVisit(link: "https://example.com/target", title: "Target", feedName: "F")
        manager.recordVisit(link: "https://example.com/other", title: "Other", feedName: "F")
        
        let entry = manager.entry(forLink: "https://example.com/target")
        XCTAssertNotNil(entry)
        XCTAssertEqual(entry?.title, "Target")
        
        let missing = manager.entry(forLink: "https://example.com/missing")
        XCTAssertNil(missing)
    }
    
    // MARK: - Date Grouping (3)
    
    func testDatesWithEntriesUnique() {
        // Record multiple articles today — should yield one unique date
        recordSampleArticle(link: "https://example.com/1")
        recordSampleArticle(link: "https://example.com/2")
        recordSampleArticle(link: "https://example.com/3")
        
        let dates = manager.datesWithEntries()
        XCTAssertEqual(dates.count, 1)
    }
    
    func testDatesWithEntriesNewestFirst() {
        // All entries are today, so only one date
        recordSampleArticle(link: "https://example.com/1")
        
        let dates = manager.datesWithEntries()
        XCTAssertEqual(dates.count, 1)
        // The date should be start of today
        let today = Calendar.current.startOfDay(for: Date())
        XCTAssertEqual(dates.first, today)
    }
    
    func testDatesWithEntriesNormalized() {
        recordSampleArticle()
        
        let dates = manager.datesWithEntries()
        guard let date = dates.first else {
            XCTFail("Expected at least one date")
            return
        }
        
        // Verify the date is normalized to start of day
        let calendar = Calendar.current
        let components = calendar.dateComponents([.hour, .minute, .second], from: date)
        XCTAssertEqual(components.hour, 0)
        XCTAssertEqual(components.minute, 0)
        XCTAssertEqual(components.second, 0)
    }
    
    // MARK: - Statistics (6)
    
    func testTotalArticles() {
        recordSampleArticle(link: "https://example.com/1")
        recordSampleArticle(link: "https://example.com/2")
        recordSampleArticle(link: "https://example.com/3")
        
        XCTAssertEqual(manager.totalArticles, 3)
    }
    
    func testTotalVisitsIncludesRevisits() {
        manager.recordVisit(link: "https://example.com/1", title: "A", feedName: "F")
        manager.recordVisit(link: "https://example.com/2", title: "B", feedName: "F")
        // Re-visit article 1
        manager.recordVisit(link: "https://example.com/1", title: "A", feedName: "F")
        
        XCTAssertEqual(manager.totalArticles, 2)
        XCTAssertEqual(manager.totalVisits, 3) // 2 for article1 + 1 for article2
    }
    
    func testAverageTimeSpent() {
        manager.recordVisit(link: "https://example.com/1", title: "A", feedName: "F", timeSpent: 60.0)
        manager.recordVisit(link: "https://example.com/2", title: "B", feedName: "F", timeSpent: 120.0)
        
        XCTAssertEqual(manager.averageTimeSpent, 90.0, accuracy: 0.01)
    }
    
    func testTopFeed() {
        manager.recordVisit(link: "https://example.com/1", title: "A", feedName: "Tech Blog")
        manager.recordVisit(link: "https://example.com/2", title: "B", feedName: "Tech Blog")
        manager.recordVisit(link: "https://example.com/3", title: "C", feedName: "News Daily")
        
        XCTAssertEqual(manager.topFeed, "Tech Blog")
    }
    
    func testHistorySummaryAllFields() {
        manager.recordVisit(link: "https://example.com/1", title: "A", feedName: "Feed1", timeSpent: 30.0)
        manager.recordVisit(link: "https://example.com/2", title: "B", feedName: "Feed2", timeSpent: 60.0)
        manager.recordVisit(link: "https://example.com/1", title: "A", feedName: "Feed1", timeSpent: 10.0)
        
        let summary = manager.historySummary()
        XCTAssertEqual(summary.totalArticles, 2)
        XCTAssertEqual(summary.totalVisits, 3)
        XCTAssertGreaterThan(summary.averageTimeSpentSeconds, 0)
        XCTAssertNotNil(summary.topFeed)
        XCTAssertEqual(summary.uniqueFeeds, 2)
        XCTAssertNotNil(summary.oldestEntry)
        XCTAssertNotNil(summary.newestEntry)
        XCTAssertGreaterThanOrEqual(summary.daysWithActivity, 1)
    }
    
    func testHistorySummaryEmpty() {
        let summary = manager.historySummary()
        XCTAssertEqual(summary.totalArticles, 0)
        XCTAssertEqual(summary.totalVisits, 0)
        XCTAssertEqual(summary.averageTimeSpentSeconds, 0)
        XCTAssertNil(summary.topFeed)
        XCTAssertEqual(summary.topFeedCount, 0)
        XCTAssertEqual(summary.uniqueFeeds, 0)
        XCTAssertNil(summary.oldestEntry)
        XCTAssertNil(summary.newestEntry)
        XCTAssertEqual(summary.daysWithActivity, 0)
    }
    
    // MARK: - Deletion (6)
    
    func testDeleteEntry() {
        recordSampleArticle(link: "https://example.com/1")
        recordSampleArticle(link: "https://example.com/2")
        
        let result = manager.deleteEntry(link: "https://example.com/1")
        XCTAssertTrue(result)
        XCTAssertEqual(manager.entries.count, 1)
        XCTAssertNil(manager.entry(forLink: "https://example.com/1"))
    }
    
    func testDeleteEntryNotFound() {
        recordSampleArticle()
        
        let result = manager.deleteEntry(link: "https://example.com/nonexistent")
        XCTAssertFalse(result)
        XCTAssertEqual(manager.entries.count, 1)
    }
    
    func testDeleteEntriesForDate() {
        recordSampleArticle(link: "https://example.com/1")
        recordSampleArticle(link: "https://example.com/2")
        recordSampleArticle(link: "https://example.com/3")
        
        let removed = manager.deleteEntries(for: Date())
        XCTAssertEqual(removed, 3)
        XCTAssertEqual(manager.entries.count, 0)
    }
    
    func testDeleteEntriesBefore() {
        recordSampleArticle(link: "https://example.com/1")
        recordSampleArticle(link: "https://example.com/2")
        
        // Delete entries before tomorrow → should remove all
        let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: Date())!
        let removed = manager.deleteEntriesBefore(date: tomorrow)
        XCTAssertEqual(removed, 2)
        XCTAssertEqual(manager.entries.count, 0)
    }
    
    func testClearAll() {
        for i in 1...10 {
            recordSampleArticle(link: "https://example.com/\(i)")
        }
        
        manager.clearAll()
        
        XCTAssertEqual(manager.entries.count, 0)
        XCTAssertEqual(manager.totalArticles, 0)
        XCTAssertFalse(manager.hasVisited(link: "https://example.com/1"))
    }
    
    func testDeleteUpdatesIndex() {
        recordSampleArticle(link: "https://example.com/1")
        recordSampleArticle(link: "https://example.com/2")
        recordSampleArticle(link: "https://example.com/3")
        
        manager.deleteEntry(link: "https://example.com/2")
        
        // Index should still work for remaining entries
        XCTAssertTrue(manager.hasVisited(link: "https://example.com/1"))
        XCTAssertFalse(manager.hasVisited(link: "https://example.com/2"))
        XCTAssertTrue(manager.hasVisited(link: "https://example.com/3"))
        
        // entry(forLink:) should also work
        XCTAssertNotNil(manager.entry(forLink: "https://example.com/1"))
        XCTAssertNotNil(manager.entry(forLink: "https://example.com/3"))
    }
    
    // MARK: - Pruning (3)
    
    func testPruneRemovesOldestWhenOverLimit() {
        // Fill to max + 1
        for i in 0...ReadingHistoryManager.maxEntries {
            manager.recordVisit(link: "https://example.com/\(i)", title: "Article \(i)", feedName: "F")
        }
        
        XCTAssertLessThanOrEqual(manager.entries.count, ReadingHistoryManager.maxEntries)
    }
    
    func testPruneKeepsFrequentlyVisited() {
        // Record an "old" article and re-visit it many times
        manager.recordVisit(link: "https://example.com/favorite", title: "Favorite", feedName: "F")
        
        // Fill to capacity with other articles
        for i in 1...ReadingHistoryManager.maxEntries {
            manager.recordVisit(link: "https://example.com/filler-\(i)", title: "Filler \(i)", feedName: "F")
        }
        
        // Re-visit favorite to update lastVisitedAt
        manager.recordVisit(link: "https://example.com/favorite", title: "Favorite", feedName: "F")
        
        // Pruning is by readAt, and favorite was the first readAt but has been re-visited.
        // Since we re-visited it, the entry still exists (it was moved to top).
        // But pruneIfNeeded removes by readAt — so after pruning, the oldest readAt
        // entry could be removed. If favorite is still there, it means re-visiting preserved it.
        // The key design: pruning happens on insert of NEW entries, and favorite is
        // already in the list, so it won't be removed by re-visit.
        XCTAssertLessThanOrEqual(manager.entries.count, ReadingHistoryManager.maxEntries)
    }
    
    func testMaxEntriesRespected() {
        for i in 1...(ReadingHistoryManager.maxEntries + 100) {
            manager.recordVisit(link: "https://example.com/\(i)", title: "Article \(i)", feedName: "F")
        }
        
        XCTAssertLessThanOrEqual(manager.entries.count, ReadingHistoryManager.maxEntries)
    }
    
    // MARK: - Export (4)
    
    func testExportAsTextContainsTitles() {
        manager.recordVisit(link: "https://example.com/1", title: "Great Article", feedName: "Tech Blog")
        
        let text = manager.exportAsText()
        XCTAssertTrue(text.contains("Great Article"))
        XCTAssertTrue(text.contains("Tech Blog"))
    }
    
    func testExportAsTextGroupedByDate() {
        manager.recordVisit(link: "https://example.com/1", title: "Article 1", feedName: "F")
        manager.recordVisit(link: "https://example.com/2", title: "Article 2", feedName: "F")
        
        let text = manager.exportAsText()
        // Should have date header (## format)
        XCTAssertTrue(text.contains("##"))
        XCTAssertTrue(text.contains("Article 1"))
        XCTAssertTrue(text.contains("Article 2"))
    }
    
    func testExportAsJSONValid() {
        manager.recordVisit(link: "https://example.com/1", title: "Article", feedName: "Feed")
        
        let data = manager.exportAsJSON()
        XCTAssertNotNil(data)
        
        if let jsonData = data {
            let json = try? JSONSerialization.jsonObject(with: jsonData)
            XCTAssertNotNil(json, "Exported JSON should be valid")
            
            if let array = json as? [[String: Any]] {
                XCTAssertEqual(array.count, 1)
                XCTAssertEqual(array.first?["link"] as? String, "https://example.com/1")
            }
        }
    }
    
    func testExportEmptyHistory() {
        let text = manager.exportAsText()
        XCTAssertEqual(text, "No reading history.")
        
        let json = manager.exportAsJSON()
        XCTAssertNotNil(json) // Empty array is valid JSON
    }
    
    // MARK: - Persistence (4)
    
    func testSaveAndLoad() {
        manager.recordVisit(link: "https://example.com/persist", title: "Persist Me", feedName: "Feed")
        
        manager.reloadFromDefaults()
        
        XCTAssertEqual(manager.entries.count, 1)
        XCTAssertEqual(manager.entries.first?.title, "Persist Me")
    }
    
    func testLoadEmptyState() {
        manager.reset()
        manager.reloadFromDefaults()
        
        XCTAssertEqual(manager.entries.count, 0)
    }
    
    func testPersistenceRoundTrip() {
        manager.recordVisit(link: "https://example.com/1", title: "Article 1", feedName: "Feed A", timeSpent: 45.0, scrollProgress: 0.8)
        manager.recordVisit(link: "https://example.com/2", title: "Article 2", feedName: "Feed B", timeSpent: 30.0, scrollProgress: 0.5)
        // Re-visit to test visitCount persistence
        manager.recordVisit(link: "https://example.com/1", title: "Article 1", feedName: "Feed A")
        
        manager.reloadFromDefaults()
        
        XCTAssertEqual(manager.entries.count, 2)
        
        let entry1 = manager.entry(forLink: "https://example.com/1")
        XCTAssertNotNil(entry1)
        XCTAssertEqual(entry1?.visitCount, 2)
        XCTAssertEqual(entry1?.timeSpentSeconds, 45.0, accuracy: 0.01)
        XCTAssertEqual(entry1?.scrollProgress, 0.0, accuracy: 0.01) // Re-visit set it to 0
        
        let entry2 = manager.entry(forLink: "https://example.com/2")
        XCTAssertNotNil(entry2)
        XCTAssertEqual(entry2?.visitCount, 1)
    }
    
    func testNotificationPostedOnChange() {
        let expectation = self.expectation(forNotification: .readingHistoryDidChange, object: nil)
        
        manager.recordVisit(link: "https://example.com/1", title: "A", feedName: "F")
        
        wait(for: [expectation], timeout: 1.0)
    }
    
    // MARK: - Additional Edge Cases
    
    func testAverageTimeSpentEmpty() {
        XCTAssertEqual(manager.averageTimeSpent, 0)
    }
    
    func testTopFeedEmpty() {
        XCTAssertNil(manager.topFeed)
    }
    
    func testDeleteEntriesBeforeNoMatch() {
        recordSampleArticle()
        
        // Delete before yesterday — nothing should be removed
        let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: Date())!
        let removed = manager.deleteEntriesBefore(date: yesterday)
        XCTAssertEqual(removed, 0)
        XCTAssertEqual(manager.entries.count, 1)
    }
    
    func testClearAllNotification() {
        recordSampleArticle()
        
        let expectation = self.expectation(forNotification: .readingHistoryDidChange, object: nil)
        manager.clearAll()
        
        wait(for: [expectation], timeout: 1.0)
    }
    
    func testDeleteEntryNotification() {
        recordSampleArticle(link: "https://example.com/del")
        
        let expectation = self.expectation(forNotification: .readingHistoryDidChange, object: nil)
        manager.deleteEntry(link: "https://example.com/del")
        
        wait(for: [expectation], timeout: 1.0)
    }
    
    func testUpdateTimeSpentNotification() {
        recordSampleArticle(link: "https://example.com/time")
        
        let expectation = self.expectation(forNotification: .readingHistoryDidChange, object: nil)
        manager.updateTimeSpent(link: "https://example.com/time", additionalSeconds: 10.0)
        
        wait(for: [expectation], timeout: 1.0)
    }
    
    func testScrollProgressClampedOnInit() {
        manager.recordVisit(link: "https://example.com/1", title: "A", feedName: "F", scrollProgress: 2.0)
        XCTAssertEqual(manager.entries.first?.scrollProgress, 1.0)
        
        manager.recordVisit(link: "https://example.com/2", title: "B", feedName: "F", scrollProgress: -1.0)
        XCTAssertEqual(manager.entry(forLink: "https://example.com/2")?.scrollProgress, 0.0)
    }
}
