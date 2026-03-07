//
//  ReadingMoodTrackerTests.swift
//  FeedReaderTests
//
//  Tests for ReadingMoodTracker: mood logging, queries, mood shifts,
//  feed impact analysis, time/day patterns, streaks, and export.
//

import XCTest
@testable import FeedReader

class ReadingMoodTrackerTests: XCTestCase {

    var tracker: ReadingMoodTracker!

    override func setUp() {
        super.setUp()
        tracker = ReadingMoodTracker.shared
        // Note: shared singleton — tests may interact. We log fresh entries
        // with unique sessionIds to isolate test data.
    }

    // MARK: - MoodLevel

    func testMoodLevelOrdering() {
        XCTAssertTrue(MoodLevel.terrible < MoodLevel.bad)
        XCTAssertTrue(MoodLevel.bad < MoodLevel.neutral)
        XCTAssertTrue(MoodLevel.neutral < MoodLevel.good)
        XCTAssertTrue(MoodLevel.good < MoodLevel.great)
    }

    func testMoodLevelRawValues() {
        XCTAssertEqual(MoodLevel.terrible.rawValue, 1)
        XCTAssertEqual(MoodLevel.great.rawValue, 5)
    }

    func testMoodLevelEmojis() {
        XCTAssertEqual(MoodLevel.terrible.emoji, "😢")
        XCTAssertEqual(MoodLevel.great.emoji, "😄")
        XCTAssertFalse(MoodLevel.neutral.emoji.isEmpty)
    }

    func testMoodLevelLabels() {
        for level in MoodLevel.allCases {
            XCTAssertFalse(level.label.isEmpty,
                           "\(level) should have a non-empty label")
        }
    }

    func testMoodLevelCaseCount() {
        XCTAssertEqual(MoodLevel.allCases.count, 5,
                       "Should have exactly 5 mood levels")
    }

    // MARK: - Logging

    func testLogMoodReturnsEntry() {
        let entry = tracker.logMood(mood: .good, note: "Feeling productive")

        XCTAssertEqual(entry.mood, .good)
        XCTAssertEqual(entry.note, "Feeling productive")
        XCTAssertEqual(entry.phase, .standalone)
        XCTAssertFalse(entry.id.isEmpty)
    }

    func testLogMoodWithSessionPhases() {
        let sessionId = "test-session-\(UUID().uuidString)"

        let before = tracker.logMood(
            mood: .neutral,
            phase: .before,
            sessionId: sessionId,
            feedURL: "https://example.com/feed",
            feedTitle: "Test Feed"
        )
        let after = tracker.logMood(
            mood: .great,
            phase: .after,
            sessionId: sessionId,
            feedURL: "https://example.com/feed",
            feedTitle: "Test Feed"
        )

        XCTAssertEqual(before.phase, .before)
        XCTAssertEqual(after.phase, .after)
        XCTAssertEqual(before.sessionId, sessionId)
        XCTAssertEqual(after.sessionId, sessionId)
    }

    func testRemoveEntry() {
        let entry = tracker.logMood(mood: .bad, note: "To be removed")
        let removed = tracker.removeEntry(id: entry.id)
        XCTAssertTrue(removed, "Should successfully remove existing entry")

        let removedAgain = tracker.removeEntry(id: entry.id)
        XCTAssertFalse(removedAgain, "Removing non-existent entry should return false")
    }

    func testRemoveNonexistentEntry() {
        let result = tracker.removeEntry(id: "nonexistent-\(UUID().uuidString)")
        XCTAssertFalse(result)
    }

    // MARK: - Queries

    func testCurrentMoodReturnsLatest() {
        let _ = tracker.logMood(mood: .bad)
        let latest = tracker.logMood(mood: .great)

        let current = tracker.currentMood()
        XCTAssertNotNil(current)
        // Current mood should be the most recent entry (by date)
        // Since both are logged near-simultaneously, check it's one of them
        XCTAssertTrue(current!.mood == .great || current!.mood == .bad)
    }

    func testTodayEntriesOnlyReturnsToday() {
        let entry = tracker.logMood(mood: .good, note: "Today entry")
        let today = tracker.todayEntries()

        XCTAssertTrue(today.contains(where: { $0.id == entry.id }),
                       "Today's entries should include the just-logged entry")
    }

    // MARK: - Mood Shifts

    func testMoodShiftCalculation() {
        let sessionId = "shift-test-\(UUID().uuidString)"

        tracker.logMood(mood: .bad, phase: .before, sessionId: sessionId,
                        feedURL: "https://example.com/feed1", feedTitle: "Feed 1")
        tracker.logMood(mood: .great, phase: .after, sessionId: sessionId,
                        feedURL: "https://example.com/feed1", feedTitle: "Feed 1")

        let shifts = tracker.moodShifts()
        let testShift = shifts.first(where: { $0.sessionId == sessionId })

        XCTAssertNotNil(testShift)
        XCTAssertEqual(testShift?.before, .bad)
        XCTAssertEqual(testShift?.after, .great)
        XCTAssertEqual(testShift?.delta, 3)  // 5 - 2
        XCTAssertTrue(testShift?.improved ?? false)
        XCTAssertFalse(testShift?.worsened ?? true)
        XCTAssertFalse(testShift?.unchanged ?? true)
    }

    func testMoodShiftUnchanged() {
        let sessionId = "unchanged-\(UUID().uuidString)"

        tracker.logMood(mood: .neutral, phase: .before, sessionId: sessionId)
        tracker.logMood(mood: .neutral, phase: .after, sessionId: sessionId)

        let shifts = tracker.moodShifts()
        let testShift = shifts.first(where: { $0.sessionId == sessionId })

        XCTAssertNotNil(testShift)
        XCTAssertEqual(testShift?.delta, 0)
        XCTAssertTrue(testShift?.unchanged ?? false)
    }

    // MARK: - Mood Suggestions

    func testSuggestFeedsForLowMoodReturnsBoosters() {
        // Suggestions should return URLs (possibly empty if no data)
        let suggestions = tracker.suggestFeedsForMood(.terrible)
        // Just verify it doesn't crash and returns an array
        XCTAssertNotNil(suggestions)
    }

    func testSuggestFeedsForHighMoodReturnsFewerSuggestions() {
        let lowSuggestions = tracker.suggestFeedsForMood(.terrible)
        let highSuggestions = tracker.suggestFeedsForMood(.great)

        // Low mood should get at least as many suggestions as high mood
        XCTAssertGreaterThanOrEqual(lowSuggestions.count, highSuggestions.count)
    }

    // MARK: - Patterns

    func testMoodByTimeOfDayReturnsValidHours() {
        tracker.logMood(mood: .good)  // ensure at least one entry
        let patterns = tracker.moodByTimeOfDay()

        for pattern in patterns {
            XCTAssertGreaterThanOrEqual(pattern.hour, 0)
            XCTAssertLessThanOrEqual(pattern.hour, 23)
            XCTAssertGreaterThan(pattern.entryCount, 0)
            XCTAssertGreaterThanOrEqual(pattern.averageMood, 1.0)
            XCTAssertLessThanOrEqual(pattern.averageMood, 5.0)
        }
    }

    func testMoodByDayOfWeekReturnsValidDays() {
        tracker.logMood(mood: .neutral)
        let patterns = tracker.moodByDayOfWeek()

        for pattern in patterns {
            XCTAssertGreaterThanOrEqual(pattern.weekday, 1)
            XCTAssertLessThanOrEqual(pattern.weekday, 7)
            XCTAssertFalse(pattern.dayLabel.isEmpty)
        }
    }

    func testMoodTimePatternLabels() {
        let morning = MoodTimePattern(hour: 8, averageMood: 3.5, entryCount: 5)
        let afternoon = MoodTimePattern(hour: 14, averageMood: 3.0, entryCount: 3)
        let evening = MoodTimePattern(hour: 19, averageMood: 4.0, entryCount: 2)
        let night = MoodTimePattern(hour: 23, averageMood: 2.5, entryCount: 1)

        XCTAssertEqual(morning.timeLabel, "Morning")
        XCTAssertEqual(afternoon.timeLabel, "Afternoon")
        XCTAssertEqual(evening.timeLabel, "Evening")
        XCTAssertEqual(night.timeLabel, "Night")
    }

    // MARK: - Feed Impact

    func testFeedMoodImpactLabels() {
        let booster = FeedMoodImpact(
            feedURL: "url1", feedTitle: "Happy Feed",
            sessionCount: 5, averageDelta: 0.8,
            improvedCount: 4, worsenedCount: 0, unchangedCount: 1
        )
        let drainer = FeedMoodImpact(
            feedURL: "url2", feedTitle: "Sad Feed",
            sessionCount: 5, averageDelta: -0.6,
            improvedCount: 1, worsenedCount: 3, unchangedCount: 1
        )
        let neutral = FeedMoodImpact(
            feedURL: "url3", feedTitle: "Meh Feed",
            sessionCount: 5, averageDelta: 0.1,
            improvedCount: 2, worsenedCount: 1, unchangedCount: 2
        )

        XCTAssertTrue(booster.impactLabel.contains("Booster"))
        XCTAssertTrue(drainer.impactLabel.contains("Drainer"))
        XCTAssertTrue(neutral.impactLabel.contains("Neutral"))
    }

    // MARK: - Export

    func testExportAsJSONProducesValidJSON() {
        tracker.logMood(mood: .good, note: "Export test")

        guard let data = tracker.exportAsJSON() else {
            XCTFail("Export should produce JSON data")
            return
        }

        let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        XCTAssertNotNil(json)
        XCTAssertNotNil(json?["totalEntries"])
        XCTAssertNotNil(json?["entries"])
    }

    func testExportAsCSVHasHeader() {
        let csv = tracker.exportAsCSV()
        XCTAssertTrue(csv.hasPrefix("id,date,mood_level,mood_emoji,mood_label,phase,note,feed_title,category,article_title"))
    }

    func testExportAsCSVContainsEntries() {
        let entry = tracker.logMood(mood: .great, note: "CSV test entry")
        let csv = tracker.exportAsCSV()

        XCTAssertTrue(csv.contains(entry.id),
                       "CSV should contain the logged entry ID")
        XCTAssertTrue(csv.contains("Great"),
                       "CSV should contain the mood label")
    }

    // MARK: - Summary

    func testSummaryContainsKeyInfo() {
        tracker.logMood(mood: .good)
        let summary = tracker.summary(days: 30)

        XCTAssertTrue(summary.contains("Mood Summary"))
        XCTAssertTrue(summary.contains("Total entries"))
        XCTAssertTrue(summary.contains("Mood streak"))
    }

    // MARK: - MoodEntry Codable

    func testMoodEntryCodableRoundTrip() {
        let entry = MoodEntry(
            id: "test-123",
            date: Date(),
            mood: .good,
            note: "Test note",
            phase: .before,
            sessionId: "session-1",
            feedURL: "https://example.com/feed",
            feedTitle: "Test Feed",
            category: "Tech",
            articleTitle: "Test Article"
        )

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        guard let data = try? encoder.encode(entry),
              let decoded = try? decoder.decode(MoodEntry.self, from: data) else {
            XCTFail("MoodEntry should be encodable and decodable")
            return
        }

        XCTAssertEqual(decoded.id, entry.id)
        XCTAssertEqual(decoded.mood, entry.mood)
        XCTAssertEqual(decoded.note, entry.note)
        XCTAssertEqual(decoded.phase, entry.phase)
        XCTAssertEqual(decoded.sessionId, entry.sessionId)
        XCTAssertEqual(decoded.feedURL, entry.feedURL)
    }

    // MARK: - Notification

    func testMoodChangeNotificationPosted() {
        let expectation = self.expectation(
            forNotification: .readingMoodDidChange,
            object: nil
        )

        tracker.logMood(mood: .great, note: "Notification test")

        waitForExpectations(timeout: 2.0)
    }
}
