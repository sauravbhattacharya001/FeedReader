//
//  FeedSnoozeManagerTests.swift
//  FeedReaderTests
//
//  Tests for the FeedSnoozeManager — temporary feed muting.
//

import XCTest
@testable import FeedReader

class FeedSnoozeManagerTests: XCTestCase {

    var sut: FeedSnoozeManager!
    var testDefaults: UserDefaults!

    override func setUp() {
        super.setUp()
        testDefaults = UserDefaults(suiteName: "FeedSnoozeManagerTests")!
        testDefaults.removePersistentDomain(forName: "FeedSnoozeManagerTests")
        sut = FeedSnoozeManager(defaults: testDefaults)
    }

    override func tearDown() {
        testDefaults.removePersistentDomain(forName: "FeedSnoozeManagerTests")
        testDefaults = nil
        sut = nil
        super.tearDown()
    }

    // MARK: - Basic Snooze/Unsnooze

    func testSnoozeAndCheck() {
        let url = "https://example.com/feed"
        sut.snooze(feedURL: url, duration: .hours(2))
        XCTAssertTrue(sut.isSnoozed(feedURL: url))
    }

    func testNotSnoozedByDefault() {
        XCTAssertFalse(sut.isSnoozed(feedURL: "https://example.com/feed"))
    }

    func testUnsnooze() {
        let url = "https://example.com/feed"
        sut.snooze(feedURL: url, duration: .hours(1))
        sut.unsnooze(feedURL: url)
        XCTAssertFalse(sut.isSnoozed(feedURL: url))
    }

    func testUnsnoozeAll() {
        sut.snooze(feedURL: "https://a.com/feed", duration: .hours(1))
        sut.snooze(feedURL: "https://b.com/feed", duration: .hours(2))
        sut.unsnoozeAll()
        XCTAssertEqual(sut.activeSnoozes().count, 0)
    }

    // MARK: - URL Normalization

    func testURLNormalization() {
        sut.snooze(feedURL: "HTTPS://EXAMPLE.COM/Feed", duration: .hours(1))
        XCTAssertTrue(sut.isSnoozed(feedURL: "https://example.com/feed"))
    }

    // MARK: - Presets

    func testSnoozeWithPreset() {
        let url = "https://example.com/feed"
        let entry = sut.snooze(feedURL: url, preset: .oneHour)
        XCTAssertTrue(sut.isSnoozed(feedURL: url))
        XCTAssertTrue(entry.remainingSeconds > 3500) // ~1 hour
        XCTAssertTrue(entry.remainingSeconds <= 3600)
    }

    func testAllPresetsHavePositiveDuration() {
        for preset in FeedSnoozeManager.SnoozePreset.allCases {
            XCTAssertGreaterThan(preset.timeInterval, 0, "\(preset.rawValue) should have positive duration")
        }
    }

    // MARK: - Snooze Entry

    func testSnoozeEntryDetails() {
        let url = "https://example.com/feed"
        sut.snooze(feedURL: url, duration: .days(1), reason: "Too noisy")
        let entry = sut.snoozeEntry(for: url)
        XCTAssertNotNil(entry)
        XCTAssertEqual(entry?.reason, "Too noisy")
        XCTAssertFalse(entry!.isExpired)
    }

    func testSnoozeEntryNilForUnknownFeed() {
        XCTAssertNil(sut.snoozeEntry(for: "https://unknown.com/feed"))
    }

    // MARK: - Active Snoozes

    func testActiveSnoozes() {
        sut.snooze(feedURL: "https://a.com/feed", duration: .hours(1))
        sut.snooze(feedURL: "https://b.com/feed", duration: .hours(2))
        let active = sut.activeSnoozes()
        XCTAssertEqual(active.count, 2)
        // Should be sorted by expiry (earlier first)
        XCTAssertTrue(active[0].expiresAt <= active[1].expiresAt)
    }

    // MARK: - Extend Snooze

    func testExtendSnooze() {
        let url = "https://example.com/feed"
        let original = sut.snooze(feedURL: url, duration: .hours(1))
        let extended = sut.extendSnooze(feedURL: url, by: 2)
        XCTAssertNotNil(extended)
        XCTAssertTrue(extended!.expiresAt > original.expiresAt)
    }

    func testExtendNonExistentSnooze() {
        let result = sut.extendSnooze(feedURL: "https://none.com/feed", by: 1)
        XCTAssertNil(result)
    }

    // MARK: - Filter Snoozed Feeds

    func testFilterSnoozed() {
        let feeds = [
            Feed(name: "A", url: "https://a.com/feed"),
            Feed(name: "B", url: "https://b.com/feed"),
            Feed(name: "C", url: "https://c.com/feed")
        ]
        sut.snooze(feedURL: "https://b.com/feed", duration: .hours(1))
        let filtered = sut.filterSnoozed(feeds: feeds)
        XCTAssertEqual(filtered.count, 2)
        XCTAssertFalse(filtered.contains { $0.url == "https://b.com/feed" })
    }

    // MARK: - Stats

    func testStats() {
        sut.snooze(feedURL: "https://a.com/feed", duration: .hours(2))
        sut.snooze(feedURL: "https://a.com/feed", duration: .hours(4))
        sut.snooze(feedURL: "https://b.com/feed", duration: .hours(1))
        let stats = sut.stats()
        XCTAssertEqual(stats.activeSnoozesCount, 2)
        XCTAssertEqual(stats.totalSnoozesEver, 3)
        XCTAssertEqual(stats.mostSnoozedFeedURL, "https://a.com/feed")
        XCTAssertGreaterThan(stats.averageSnoozeDurationHours, 0)
    }

    // MARK: - Remaining Description

    func testRemainingDescription() {
        let entry = FeedSnoozeManager.SnoozeEntry(
            feedURL: "test",
            snoozedAt: Date(),
            expiresAt: Date().addingTimeInterval(7200),
            reason: nil
        )
        let desc = entry.remainingDescription
        XCTAssertTrue(desc.contains("h"), "Should contain hours: \(desc)")
    }

    func testExpiredDescription() {
        let entry = FeedSnoozeManager.SnoozeEntry(
            feedURL: "test",
            snoozedAt: Date().addingTimeInterval(-7200),
            expiresAt: Date().addingTimeInterval(-3600),
            reason: nil
        )
        XCTAssertEqual(entry.remainingDescription, "Expired")
    }

    // MARK: - Persistence

    func testPersistence() {
        sut.snooze(feedURL: "https://example.com/feed", duration: .hours(2))
        let newManager = FeedSnoozeManager(defaults: testDefaults)
        XCTAssertTrue(newManager.isSnoozed(feedURL: "https://example.com/feed"))
    }

    // MARK: - Snooze Until Date

    func testSnoozeUntilDate() {
        let future = Date().addingTimeInterval(86400)
        sut.snooze(feedURL: "https://example.com/feed", duration: .until(future))
        XCTAssertTrue(sut.isSnoozed(feedURL: "https://example.com/feed"))
    }
}
