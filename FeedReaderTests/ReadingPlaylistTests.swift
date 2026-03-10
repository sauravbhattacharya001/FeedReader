//
//  ReadingPlaylistTests.swift
//  FeedReaderTests
//

import XCTest
@testable import FeedReader

class ReadingPlaylistTests: XCTestCase {

    var manager: ReadingPlaylistManager!
    var testDefaults: UserDefaults!

    override func setUp() {
        super.setUp()
        testDefaults = UserDefaults(suiteName: "ReadingPlaylistTests")!
        testDefaults.removePersistentDomain(forName: "ReadingPlaylistTests")
        manager = ReadingPlaylistManager(defaults: testDefaults)
    }

    override func tearDown() {
        testDefaults.removePersistentDomain(forName: "ReadingPlaylistTests")
        manager = nil
        testDefaults = nil
        super.tearDown()
    }

    // MARK: - Creation

    func testCreatePlaylist() {
        let pl = manager.createPlaylist(name: "Morning News", description: "Daily reads", icon: "☀️")
        XCTAssertEqual(pl.name, "Morning News")
        XCTAssertEqual(pl.description, "Daily reads")
        XCTAssertEqual(pl.icon, "☀️")
        XCTAssertEqual(manager.count, 1)
    }

    func testCreatePlaylistTrimsWhitespace() {
        let pl = manager.createPlaylist(name: "  Trimmed  ")
        XCTAssertEqual(pl.name, "Trimmed")
    }

    func testCreateEmptyNameFallback() {
        let pl = manager.createPlaylist(name: "   ")
        XCTAssertEqual(pl.name, "Untitled")
    }

    func testMultiplePlaylists() {
        manager.createPlaylist(name: "A")
        manager.createPlaylist(name: "B")
        manager.createPlaylist(name: "C")
        XCTAssertEqual(manager.count, 3)
    }

    // MARK: - CRUD

    func testGetById() {
        let pl = manager.createPlaylist(name: "Test")
        let found = manager.playlist(byId: pl.id)
        XCTAssertNotNil(found)
        XCTAssertEqual(found?.name, "Test")
    }

    func testRenamePlaylist() {
        let pl = manager.createPlaylist(name: "Old")
        XCTAssertTrue(manager.renamePlaylist(id: pl.id, newName: "New"))
        XCTAssertEqual(manager.playlist(byId: pl.id)?.name, "New")
    }

    func testRenameEmptyFails() {
        let pl = manager.createPlaylist(name: "Keep")
        XCTAssertFalse(manager.renamePlaylist(id: pl.id, newName: "  "))
        XCTAssertEqual(manager.playlist(byId: pl.id)?.name, "Keep")
    }

    func testDeletePlaylist() {
        let pl = manager.createPlaylist(name: "Delete Me")
        XCTAssertTrue(manager.deletePlaylist(id: pl.id))
        XCTAssertEqual(manager.count, 0)
        XCTAssertNil(manager.playlist(byId: pl.id))
    }

    func testDeleteNonexistent() {
        XCTAssertFalse(manager.deletePlaylist(id: "nope"))
    }

    func testDeleteAll() {
        manager.createPlaylist(name: "A")
        manager.createPlaylist(name: "B")
        manager.deleteAll()
        XCTAssertEqual(manager.count, 0)
    }

    func testUpdateDescription() {
        let pl = manager.createPlaylist(name: "Test")
        XCTAssertTrue(manager.updateDescription(id: pl.id, description: "Updated"))
        XCTAssertEqual(manager.playlist(byId: pl.id)?.description, "Updated")
    }

    // MARK: - Item Management

    func testAddItem() {
        let pl = manager.createPlaylist(name: "Test")
        XCTAssertTrue(manager.addItem(to: pl.id, articleLink: "https://a.com",
                                       articleTitle: "Article A", wordCount: 500))
        XCTAssertEqual(manager.playlist(byId: pl.id)?.items.count, 1)
    }

    func testAddDuplicateItemFails() {
        let pl = manager.createPlaylist(name: "Test")
        manager.addItem(to: pl.id, articleLink: "https://a.com", articleTitle: "A")
        XCTAssertFalse(manager.addItem(to: pl.id, articleLink: "https://a.com", articleTitle: "A copy"))
        XCTAssertEqual(manager.playlist(byId: pl.id)?.items.count, 1)
    }

    func testRemoveItem() {
        let pl = manager.createPlaylist(name: "Test")
        manager.addItem(to: pl.id, articleLink: "https://a.com", articleTitle: "A")
        let itemId = manager.playlist(byId: pl.id)!.items[0].id
        XCTAssertTrue(manager.removeItem(from: pl.id, itemId: itemId))
        XCTAssertEqual(manager.playlist(byId: pl.id)?.items.count, 0)
    }

    func testMoveItem() {
        let pl = manager.createPlaylist(name: "Test")
        manager.addItem(to: pl.id, articleLink: "https://a.com", articleTitle: "A")
        manager.addItem(to: pl.id, articleLink: "https://b.com", articleTitle: "B")
        manager.addItem(to: pl.id, articleLink: "https://c.com", articleTitle: "C")
        XCTAssertTrue(manager.moveItem(in: pl.id, from: 2, to: 0))
        XCTAssertEqual(manager.playlist(byId: pl.id)?.items[0].articleTitle, "C")
    }

    func testMoveItemOutOfBounds() {
        let pl = manager.createPlaylist(name: "Test")
        manager.addItem(to: pl.id, articleLink: "https://a.com", articleTitle: "A")
        XCTAssertFalse(manager.moveItem(in: pl.id, from: 0, to: 5))
    }

    // MARK: - Playback

    func testAdvanceToNext() {
        let pl = manager.createPlaylist(name: "Test")
        manager.addItem(to: pl.id, articleLink: "https://a.com", articleTitle: "A")
        manager.addItem(to: pl.id, articleLink: "https://b.com", articleTitle: "B")
        let next = manager.advanceToNext(in: pl.id)
        XCTAssertNotNil(next)
        XCTAssertEqual(next?.articleTitle, "B")
    }

    func testAdvancePastEnd() {
        let pl = manager.createPlaylist(name: "Test")
        manager.addItem(to: pl.id, articleLink: "https://a.com", articleTitle: "A")
        let next = manager.advanceToNext(in: pl.id)
        XCTAssertNil(next)
    }

    func testGoToPrevious() {
        let pl = manager.createPlaylist(name: "Test")
        manager.addItem(to: pl.id, articleLink: "https://a.com", articleTitle: "A")
        manager.addItem(to: pl.id, articleLink: "https://b.com", articleTitle: "B")
        manager.advanceToNext(in: pl.id)
        let prev = manager.goToPrevious(in: pl.id)
        XCTAssertNotNil(prev)
        XCTAssertEqual(prev?.articleTitle, "A")
    }

    func testGoToPreviousAtStart() {
        let pl = manager.createPlaylist(name: "Test")
        manager.addItem(to: pl.id, articleLink: "https://a.com", articleTitle: "A")
        XCTAssertNil(manager.goToPrevious(in: pl.id))
    }

    func testJumpTo() {
        let pl = manager.createPlaylist(name: "Test")
        manager.addItem(to: pl.id, articleLink: "https://a.com", articleTitle: "A")
        manager.addItem(to: pl.id, articleLink: "https://b.com", articleTitle: "B")
        manager.addItem(to: pl.id, articleLink: "https://c.com", articleTitle: "C")
        let item = manager.jumpTo(in: pl.id, position: 2)
        XCTAssertEqual(item?.articleTitle, "C")
    }

    func testCompleteCurrentAndAdvance() {
        let pl = manager.createPlaylist(name: "Test")
        manager.addItem(to: pl.id, articleLink: "https://a.com", articleTitle: "A", wordCount: 100)
        manager.addItem(to: pl.id, articleLink: "https://b.com", articleTitle: "B", wordCount: 200)
        let next = manager.completeCurrentAndAdvance(in: pl.id, timeSpentSeconds: 30)
        XCTAssertNotNil(next)
        XCTAssertEqual(next?.articleTitle, "B")
        // First item should be completed
        let updated = manager.playlist(byId: pl.id)!
        XCTAssertTrue(updated.items[0].isCompleted)
        XCTAssertEqual(updated.items[0].timeSpentSeconds, 30)
    }

    func testResetPlayback() {
        let pl = manager.createPlaylist(name: "Test")
        manager.addItem(to: pl.id, articleLink: "https://a.com", articleTitle: "A")
        manager.addItem(to: pl.id, articleLink: "https://b.com", articleTitle: "B")
        manager.advanceToNext(in: pl.id)
        manager.resetPlayback(in: pl.id)
        XCTAssertEqual(manager.playlist(byId: pl.id)?.currentIndex, 0)
    }

    // MARK: - Shuffle

    func testToggleShuffle() {
        let pl = manager.createPlaylist(name: "Test")
        manager.addItem(to: pl.id, articleLink: "https://a.com", articleTitle: "A")
        manager.addItem(to: pl.id, articleLink: "https://b.com", articleTitle: "B")
        let isShuffled = manager.toggleShuffle(in: pl.id)
        XCTAssertTrue(isShuffled)
        let updated = manager.playlist(byId: pl.id)!
        XCTAssertTrue(updated.isShuffled)
        XCTAssertEqual(updated.shuffleOrder.count, 2)
        XCTAssertEqual(updated.currentIndex, 0)
    }

    func testToggleShuffleOff() {
        let pl = manager.createPlaylist(name: "Test")
        manager.addItem(to: pl.id, articleLink: "https://a.com", articleTitle: "A")
        manager.toggleShuffle(in: pl.id)
        let isShuffled = manager.toggleShuffle(in: pl.id)
        XCTAssertFalse(isShuffled)
        XCTAssertTrue(manager.playlist(byId: pl.id)!.shuffleOrder.isEmpty)
    }

    // MARK: - Time Estimates

    func testEstimatedReadingTime() {
        let pl = manager.createPlaylist(name: "Test")
        manager.addItem(to: pl.id, articleLink: "https://a.com", articleTitle: "A", wordCount: 238)
        manager.addItem(to: pl.id, articleLink: "https://b.com", articleTitle: "B", wordCount: 238)
        let time = manager.estimatedReadingTime(for: pl.id)
        XCTAssertEqual(time, 2.0, accuracy: 0.01)
    }

    func testFormattedTimeMinutes() {
        XCTAssertEqual(manager.formattedTime(minutes: 45), "45m")
    }

    func testFormattedTimeHours() {
        XCTAssertEqual(manager.formattedTime(minutes: 90), "1h 30m")
    }

    func testFormattedTimeExactHour() {
        XCTAssertEqual(manager.formattedTime(minutes: 120), "2h")
    }

    // MARK: - Smart Playlists

    func testCreateSmartPlaylist() {
        let rules = [SmartPlaylistRule(type: .keyword, value: "AI")]
        let pl = manager.createSmartPlaylist(name: "AI Articles", rules: rules)
        XCTAssertTrue(pl.isSmart)
        XCTAssertEqual(pl.smartRules.count, 1)
    }

    func testMatchesRulesKeyword() {
        let rules = [SmartPlaylistRule(type: .keyword, value: "swift")]
        XCTAssertTrue(manager.matchesRules(rules, title: "Swift Programming", body: "",
                                            feedName: "Tech", wordCount: 500))
        XCTAssertFalse(manager.matchesRules(rules, title: "Python Tips", body: "",
                                             feedName: "Tech", wordCount: 500))
    }

    func testMatchesRulesFeed() {
        let rules = [SmartPlaylistRule(type: .feed, value: "Reuters")]
        XCTAssertTrue(manager.matchesRules(rules, title: "News", body: "",
                                            feedName: "Reuters", wordCount: 300))
        XCTAssertFalse(manager.matchesRules(rules, title: "News", body: "",
                                             feedName: "BBC", wordCount: 300))
    }

    func testMatchesRulesWordCount() {
        let rules = [SmartPlaylistRule(type: .minWordCount, value: "1000")]
        XCTAssertTrue(manager.matchesRules(rules, title: "Long", body: "",
                                            feedName: "", wordCount: 1500))
        XCTAssertFalse(manager.matchesRules(rules, title: "Short", body: "",
                                             feedName: "", wordCount: 500))
    }

    func testRefreshSmartPlaylist() {
        let rules = [SmartPlaylistRule(type: .keyword, value: "AI")]
        let pl = manager.createSmartPlaylist(name: "AI", rules: rules)
        let articles = [
            (link: "https://a.com", title: "AI Revolution", body: "", feedName: "Tech", wordCount: 500),
            (link: "https://b.com", title: "Cooking Tips", body: "", feedName: "Food", wordCount: 300),
            (link: "https://c.com", title: "AI Ethics", body: "", feedName: "Tech", wordCount: 800),
        ]
        let added = manager.refreshSmartPlaylist(id: pl.id, articles: articles)
        XCTAssertEqual(added, 2)
        XCTAssertEqual(manager.playlist(byId: pl.id)?.items.count, 2)
    }

    // MARK: - Export / Import

    func testExportImport() {
        let pl = manager.createPlaylist(name: "Export Me", icon: "🎯")
        manager.addItem(to: pl.id, articleLink: "https://a.com", articleTitle: "A", wordCount: 100)
        let json = manager.exportPlaylistAsString(id: pl.id)
        XCTAssertNotNil(json)
        // Import into fresh manager
        let manager2 = ReadingPlaylistManager(defaults: testDefaults)
        let imported = manager2.importPlaylist(from: json!)
        XCTAssertNotNil(imported)
        XCTAssertEqual(imported?.name, "Export Me")
        XCTAssertEqual(imported?.items.count, 1)
    }

    func testImportInvalidJson() {
        XCTAssertNil(manager.importPlaylist(from: "not json"))
    }

    // MARK: - Statistics

    func testPlaylistStats() {
        let pl = manager.createPlaylist(name: "Test")
        manager.addItem(to: pl.id, articleLink: "https://a.com", articleTitle: "A", wordCount: 500)
        manager.addItem(to: pl.id, articleLink: "https://b.com", articleTitle: "B",
                        sourceFeedName: "Reuters", wordCount: 300)
        manager.completeCurrentAndAdvance(in: pl.id, timeSpentSeconds: 120)
        let stats = manager.playlistStats(id: pl.id)!
        XCTAssertEqual(stats.totalItems, 2)
        XCTAssertEqual(stats.completedItems, 1)
        XCTAssertEqual(stats.completionRate, 0.5, accuracy: 0.01)
        XCTAssertEqual(stats.totalWordCount, 800)
        XCTAssertEqual(stats.totalTimeSpentSeconds, 120)
        XCTAssertEqual(stats.uniqueFeeds, 1) // only "Reuters" is non-empty
    }

    func testGlobalStats() {
        manager.createPlaylist(name: "A")
        manager.createSmartPlaylist(name: "B", rules: [SmartPlaylistRule(type: .keyword, value: "x")])
        let stats = manager.globalStats()
        XCTAssertEqual(stats.playlistCount, 2)
        XCTAssertEqual(stats.smartPlaylistCount, 1)
        XCTAssertEqual(stats.manualPlaylistCount, 1)
    }

    // MARK: - Sorting

    func testSortByName() {
        manager.createPlaylist(name: "Zebra")
        manager.createPlaylist(name: "Apple")
        manager.createPlaylist(name: "Mango")
        let sorted = manager.sortedPlaylists(by: .name)
        XCTAssertEqual(sorted.map { $0.name }, ["Apple", "Mango", "Zebra"])
    }

    func testSortByItemCount() {
        let a = manager.createPlaylist(name: "A")
        let b = manager.createPlaylist(name: "B")
        manager.addItem(to: b.id, articleLink: "https://x.com", articleTitle: "X")
        manager.addItem(to: b.id, articleLink: "https://y.com", articleTitle: "Y")
        manager.addItem(to: a.id, articleLink: "https://z.com", articleTitle: "Z")
        let sorted = manager.sortedPlaylists(by: .itemCount)
        XCTAssertEqual(sorted[0].name, "B")
    }

    // MARK: - Playlist Model

    func testCompletionRateEmpty() {
        let pl = ReadingPlaylist(name: "Empty")
        XCTAssertEqual(pl.completionRate, 0.0)
    }

    func testRemainingCount() {
        let pl = manager.createPlaylist(name: "Test")
        manager.addItem(to: pl.id, articleLink: "https://a.com", articleTitle: "A")
        manager.addItem(to: pl.id, articleLink: "https://b.com", articleTitle: "B")
        manager.addItem(to: pl.id, articleLink: "https://c.com", articleTitle: "C")
        manager.advanceToNext(in: pl.id)
        XCTAssertEqual(manager.playlist(byId: pl.id)?.remainingCount, 2)
    }

    // MARK: - Persistence

    func testPersistenceAcrossInstances() {
        let pl = manager.createPlaylist(name: "Persist Me")
        manager.addItem(to: pl.id, articleLink: "https://a.com", articleTitle: "A")
        // Create new manager with same defaults
        let manager2 = ReadingPlaylistManager(defaults: testDefaults)
        XCTAssertEqual(manager2.count, 1)
        XCTAssertEqual(manager2.allPlaylists()[0].name, "Persist Me")
        XCTAssertEqual(manager2.allPlaylists()[0].items.count, 1)
    }

    // MARK: - Notifications

    func testNotificationPosted() {
        let expectation = self.expectation(forNotification: .readingPlaylistsDidChange, object: nil)
        manager.createPlaylist(name: "Test")
        wait(for: [expectation], timeout: 1.0)
    }
}
