//
//  ReadingAchievementsManagerTests.swift
//  FeedReaderTests
//
//  Tests for the Reading Achievements gamification system.
//

import XCTest
@testable import FeedReader

class ReadingAchievementsManagerTests: XCTestCase {

    var manager: ReadingAchievementsManager!
    let now = Date(timeIntervalSince1970: 1700000000)

    override func setUp() {
        super.setUp()
        UserDefaults.standard.removeObject(forKey: "ReadingAchievementsManager.progress")
        manager = ReadingAchievementsManager()
    }

    override func tearDown() {
        UserDefaults.standard.removeObject(forKey: "ReadingAchievementsManager.progress")
        super.tearDown()
    }

    // MARK: - Registry

    func testRegistryHasDefinitions() {
        XCTAssertGreaterThan(AchievementRegistry.count, 30)
    }

    func testRegistryLookup() {
        let def = AchievementRegistry.definition(for: "vol_first")
        XCTAssertNotNil(def)
        XCTAssertEqual(def?.name, "First Steps")
        XCTAssertEqual(def?.category, .volume)
        XCTAssertEqual(def?.rarity, .common)
    }

    func testRegistryLookupUnknown() {
        XCTAssertNil(AchievementRegistry.definition(for: "nonexistent"))
    }

    func testRegistryUniqueIds() {
        let ids = AchievementRegistry.all.map { $0.id }
        XCTAssertEqual(ids.count, Set(ids).count)
    }

    func testRegistryAllCategoriesCovered() {
        let categories = Set(AchievementRegistry.all.map { $0.category })
        for cat in AchievementCategory.allCases {
            XCTAssertTrue(categories.contains(cat))
        }
    }

    func testRegistryPoints() {
        XCTAssertEqual(AchievementRegistry.points(for: .common), 10)
        XCTAssertEqual(AchievementRegistry.points(for: .legendary), 250)
    }

    func testRarityComparable() {
        XCTAssertTrue(AchievementRarity.common < AchievementRarity.legendary)
        XCTAssertTrue(AchievementRarity.rare < AchievementRarity.epic)
    }

    // MARK: - Initial State

    func testInitialStateAllLocked() {
        XCTAssertTrue(manager.unlockedAchievements().isEmpty)
    }

    func testInitialProgressEntries() {
        XCTAssertEqual(manager.allProgress().count, AchievementRegistry.count)
    }

    func testInitialPointsZero() {
        XCTAssertEqual(manager.totalPoints(), 0)
    }

    func testMaxPointsPositive() {
        XCTAssertGreaterThan(manager.maxPoints(), 0)
    }

    // MARK: - Volume Updates

    func testUnlockFirstArticle() {
        var s = ReadingActivitySnapshot()
        s.totalArticlesRead = 1
        let unlocked = manager.updateProgress(from: s, now: now)
        XCTAssertTrue(unlocked.contains("vol_first"))
    }

    func testUnlockMultipleVolumeTiers() {
        var s = ReadingActivitySnapshot()
        s.totalArticlesRead = 100
        let unlocked = manager.updateProgress(from: s, now: now)
        XCTAssertTrue(unlocked.contains("vol_first"))
        XCTAssertTrue(unlocked.contains("vol_10"))
        XCTAssertTrue(unlocked.contains("vol_50"))
        XCTAssertTrue(unlocked.contains("vol_100"))
        XCTAssertFalse(unlocked.contains("vol_500"))
    }

    // MARK: - Streak Updates

    func testUnlockStreaks() {
        var s = ReadingActivitySnapshot()
        s.currentStreak = 7
        let unlocked = manager.updateProgress(from: s, now: now)
        XCTAssertTrue(unlocked.contains("str_3"))
        XCTAssertTrue(unlocked.contains("str_7"))
        XCTAssertFalse(unlocked.contains("str_14"))
    }

    func testLongestStreakUsed() {
        var s = ReadingActivitySnapshot()
        s.currentStreak = 2
        s.longestStreak = 8
        let unlocked = manager.updateProgress(from: s, now: now)
        XCTAssertTrue(unlocked.contains("str_7"))
    }

    // MARK: - Diversity Updates

    func testUnlockDiversity() {
        var s = ReadingActivitySnapshot()
        s.uniqueFeedsRead = 10
        s.uniqueCategoriesRead = 5
        let unlocked = manager.updateProgress(from: s, now: now)
        XCTAssertTrue(unlocked.contains("div_3feeds"))
        XCTAssertTrue(unlocked.contains("div_10feeds"))
        XCTAssertTrue(unlocked.contains("div_5cats"))
    }

    // MARK: - Dedication Updates

    func testUnlockDedication() {
        var s = ReadingActivitySnapshot()
        s.longestSessionMinutes = 60
        s.articlesToday = 10
        s.totalReadingMinutes = 500
        let unlocked = manager.updateProgress(from: s, now: now)
        XCTAssertTrue(unlocked.contains("ded_60min"))
        XCTAssertTrue(unlocked.contains("ded_10day"))
        XCTAssertTrue(unlocked.contains("ded_500min"))
    }

    // MARK: - Exploration Updates

    func testUnlockExploration() {
        var s = ReadingActivitySnapshot()
        s.feedsSubscribed = 20
        s.searchesPerformed = 10
        let unlocked = manager.updateProgress(from: s, now: now)
        XCTAssertTrue(unlocked.contains("exp_sub5"))
        XCTAssertTrue(unlocked.contains("exp_sub20"))
        XCTAssertTrue(unlocked.contains("exp_search10"))
    }

    // MARK: - Social Updates

    func testUnlockSocial() {
        var s = ReadingActivitySnapshot()
        s.sharedArticles = 1
        s.bookmarkedArticles = 10
        s.collectionsCreated = 3
        s.highlightsMade = 50
        s.notesWritten = 25
        let unlocked = manager.updateProgress(from: s, now: now)
        XCTAssertTrue(unlocked.contains("soc_share1"))
        XCTAssertTrue(unlocked.contains("soc_bookmark10"))
        XCTAssertTrue(unlocked.contains("soc_collection3"))
        XCTAssertTrue(unlocked.contains("soc_highlight50"))
        XCTAssertTrue(unlocked.contains("soc_notes25"))
    }

    // MARK: - Secret Achievements

    func testUnlockSecrets() {
        var s = ReadingActivitySnapshot()
        s.nightOwlArticles = 20
        s.earlyBirdArticles = 10
        s.weekendArticles = 50
        let unlocked = manager.updateProgress(from: s, now: now)
        XCTAssertTrue(unlocked.contains("sec_nightowl"))
        XCTAssertTrue(unlocked.contains("sec_earlybird"))
        XCTAssertTrue(unlocked.contains("sec_weekend"))
    }

    // MARK: - Mastery

    func testUnlockMasteryAllCats() {
        var s = ReadingActivitySnapshot()
        s.uniqueCategoriesRead = 10
        let unlocked = manager.updateProgress(from: s, now: now)
        XCTAssertTrue(unlocked.contains("mas_allcats"))
    }

    func testUnlockMasteryTags() {
        var s = ReadingActivitySnapshot()
        s.tagsUsed = 20
        let unlocked = manager.updateProgress(from: s, now: now)
        XCTAssertTrue(unlocked.contains("mas_tags20"))
    }

    // MARK: - No Double Unlock

    func testNoDoubleUnlock() {
        var s = ReadingActivitySnapshot()
        s.totalArticlesRead = 1
        let first = manager.updateProgress(from: s, now: now)
        XCTAssertTrue(first.contains("vol_first"))
        let second = manager.updateProgress(from: s, now: now)
        XCTAssertFalse(second.contains("vol_first"))
    }

    // MARK: - Progress Percentage

    func testProgressPercentage() {
        var s = ReadingActivitySnapshot()
        s.totalArticlesRead = 5
        manager.updateProgress(from: s, now: now)
        let p = manager.progress(for: "vol_10")
        XCTAssertEqual(p?.percentage ?? 0, 50.0, accuracy: 0.01)
    }

    func testProgressDoesNotExceed100() {
        var s = ReadingActivitySnapshot()
        s.totalArticlesRead = 999999
        manager.updateProgress(from: s, now: now)
        XCTAssertEqual(manager.progress(for: "vol_first")?.percentage, 100.0)
    }

    // MARK: - Increment

    func testIncrementUnlocks() {
        XCTAssertTrue(manager.incrementProgress(for: "vol_first", now: now))
        XCTAssertTrue(manager.progress(for: "vol_first")?.isUnlocked == true)
    }

    func testIncrementPartial() {
        XCTAssertFalse(manager.incrementProgress(for: "vol_10", by: 3, now: now))
        XCTAssertEqual(manager.progress(for: "vol_10")?.currentValue, 3)
    }

    func testIncrementAlreadyUnlocked() {
        manager.incrementProgress(for: "vol_first", now: now)
        XCTAssertFalse(manager.incrementProgress(for: "vol_first", now: now))
    }

    func testIncrementUnknown() {
        XCTAssertFalse(manager.incrementProgress(for: "nonexistent"))
    }

    // MARK: - Filtering

    func testByCategory() {
        let volume = manager.achievements(in: .volume)
        XCTAssertGreaterThan(volume.count, 0)
        for p in volume {
            XCTAssertEqual(AchievementRegistry.definition(for: p.achievementId)?.category, .volume)
        }
    }

    func testByRarity() {
        let common = manager.achievements(ofRarity: .common)
        XCTAssertGreaterThan(common.count, 0)
    }

    func testLockedExcludesSecrets() {
        let locked = manager.lockedAchievements(includeSecrets: false)
        let secretIds = Set(AchievementRegistry.all.filter { $0.isSecret }.map { $0.id })
        for p in locked {
            if secretIds.contains(p.achievementId) {
                XCTAssertGreaterThan(p.currentValue, 0)
            }
        }
    }

    func testLockedShowsSecretsWithProgress() {
        var s = ReadingActivitySnapshot()
        s.nightOwlArticles = 5
        manager.updateProgress(from: s, now: now)
        let locked = manager.lockedAchievements(includeSecrets: false)
        XCTAssertTrue(locked.contains { $0.achievementId == "sec_nightowl" })
    }

    // MARK: - Nearest To Unlock

    func testNearestToUnlock() {
        var s = ReadingActivitySnapshot()
        s.totalArticlesRead = 9
        manager.updateProgress(from: s, now: now)
        let nearest = manager.nearestToUnlock(limit: 5)
        XCTAssertGreaterThan(nearest.count, 0)
        XCTAssertTrue(nearest[0].percentage >= nearest.last!.percentage)
    }

    func testNearestToUnlockEmpty() {
        XCTAssertTrue(manager.nearestToUnlock().isEmpty)
    }

    // MARK: - Points

    func testPointsAfterUnlock() {
        var s = ReadingActivitySnapshot()
        s.totalArticlesRead = 1
        manager.updateProgress(from: s, now: now)
        XCTAssertEqual(manager.totalPoints(), 10)
    }

    func testPointsMultipleTiers() {
        var s = ReadingActivitySnapshot()
        s.totalArticlesRead = 50
        manager.updateProgress(from: s, now: now)
        // vol_first(10) + vol_10(10) + vol_50(25) = 45
        XCTAssertEqual(manager.totalPoints(), 45)
    }

    // MARK: - Report

    func testReportEmpty() {
        let r = manager.generateReport()
        XCTAssertEqual(r.unlockedCount, 0)
        XCTAssertEqual(r.pointsEarned, 0)
        XCTAssertGreaterThan(r.totalAchievements, 30)
    }

    func testReportAfterUnlocks() {
        var s = ReadingActivitySnapshot()
        s.totalArticlesRead = 100
        s.currentStreak = 7
        manager.updateProgress(from: s, now: now)
        let r = manager.generateReport()
        XCTAssertGreaterThan(r.unlockedCount, 0)
        XCTAssertGreaterThan(r.pointsEarned, 0)
        XCTAssertFalse(r.recentUnlocks.isEmpty)
    }

    func testReportCategoryStats() {
        let r = manager.generateReport()
        for cat in AchievementCategory.allCases {
            XCTAssertNotNil(r.byCategory[cat])
        }
    }

    func testReportRarityStats() {
        let r = manager.generateReport()
        for rarity in AchievementRarity.allCases {
            XCTAssertNotNil(r.rarityBreakdown[rarity])
        }
    }

    func testReportTextSummary() {
        var s = ReadingActivitySnapshot()
        s.totalArticlesRead = 10
        manager.updateProgress(from: s, now: now)
        let text = manager.generateReport().textSummary()
        XCTAssertTrue(text.contains("Reading Achievements Report"))
        XCTAssertTrue(text.contains("Progress:"))
        XCTAssertTrue(text.contains("Points:"))
    }

    // MARK: - Reset

    func testReset() {
        var s = ReadingActivitySnapshot()
        s.totalArticlesRead = 100
        manager.updateProgress(from: s, now: now)
        XCTAssertGreaterThan(manager.unlockedAchievements().count, 0)
        manager.resetAll()
        XCTAssertEqual(manager.unlockedAchievements().count, 0)
        XCTAssertEqual(manager.totalPoints(), 0)
    }

    // MARK: - Export / Import

    func testExportJSON() {
        var s = ReadingActivitySnapshot()
        s.totalArticlesRead = 10
        manager.updateProgress(from: s, now: now)
        XCTAssertNotNil(manager.exportJSON())
    }

    func testImportJSON() {
        var s = ReadingActivitySnapshot()
        s.totalArticlesRead = 50
        manager.updateProgress(from: s, now: now)
        let data = manager.exportJSON()!
        manager.resetAll()
        XCTAssertGreaterThan(manager.importJSON(data), 0)
        XCTAssertGreaterThan(manager.unlockedAchievements().count, 0)
    }

    func testImportInvalidJSON() {
        XCTAssertEqual(manager.importJSON(Data("bad".utf8)), 0)
    }

    // MARK: - Persistence

    func testPersistence() {
        var s = ReadingActivitySnapshot()
        s.totalArticlesRead = 10
        manager.updateProgress(from: s, now: now)
        let m2 = ReadingAchievementsManager()
        XCTAssertTrue(m2.unlockedAchievements().contains { $0.achievementId == "vol_10" })
    }

    // MARK: - Notifications

    func testUnlockNotification() {
        let exp = XCTestExpectation(description: "unlock")
        let obs = NotificationCenter.default.addObserver(forName: .achievementUnlocked, object: nil, queue: nil) { _ in exp.fulfill() }
        manager.incrementProgress(for: "vol_first", now: now)
        wait(for: [exp], timeout: 1.0)
        NotificationCenter.default.removeObserver(obs)
    }

    func testProgressNotification() {
        let exp = XCTestExpectation(description: "progress")
        let obs = NotificationCenter.default.addObserver(forName: .achievementProgressDidChange, object: nil, queue: nil) { _ in exp.fulfill() }
        manager.incrementProgress(for: "vol_10", by: 3, now: now)
        wait(for: [exp], timeout: 1.0)
        NotificationCenter.default.removeObserver(obs)
    }

    // MARK: - Edge Cases

    func testProgressForUnknown() {
        XCTAssertNil(manager.progress(for: "nonexistent"))
    }

    func testEmptySnapshot() {
        let unlocked = manager.updateProgress(from: ReadingActivitySnapshot(), now: now)
        XCTAssertTrue(unlocked.isEmpty)
    }

    func testAllCategoriesHaveAchievements() {
        for cat in AchievementCategory.allCases {
            XCTAssertGreaterThan(manager.achievements(in: cat).count, 0)
        }
    }
}
