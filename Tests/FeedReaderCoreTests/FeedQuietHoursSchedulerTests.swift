//
//  FeedQuietHoursSchedulerTests.swift
//  FeedReaderCoreTests
//

import XCTest
@testable import FeedReaderCore

final class FeedQuietHoursSchedulerTests: XCTestCase {

    private func makeDate(hour: Int, weekday: Int = 2) -> Date {
        // weekday: 1=Sun, 2=Mon, ..., 7=Sat
        var components = DateComponents()
        components.year = 2026
        components.month = 6
        // Pick a day that matches the weekday
        // June 2026: 1=Mon, 7=Sun
        // weekday 2 (Mon) = June 1, weekday 7 (Sat) = June 6, weekday 1 (Sun) = June 7
        switch weekday {
        case 1: components.day = 7  // Sunday
        case 2: components.day = 1  // Monday
        case 3: components.day = 2
        case 4: components.day = 3
        case 5: components.day = 4
        case 6: components.day = 5
        case 7: components.day = 6  // Saturday
        default: components.day = 1
        }
        components.hour = hour
        components.minute = 30
        return Calendar.current.date(from: components) ?? Date()
    }

    private func generateEvents(activeHours: [Int], count: Int = 5, weekday: Int = 2) -> [ReadingTimestamp] {
        var events = [ReadingTimestamp]()
        for hour in activeHours {
            for i in 0..<count {
                events.append(ReadingTimestamp(date: makeDate(hour: hour, weekday: weekday), articleId: "art-\(hour)-\(i)"))
            }
        }
        return events
    }

    func testInsufficientData() {
        let scheduler = FeedQuietHoursScheduler()
        let events = [ReadingTimestamp(date: Date(), articleId: "a1")]
        let report = scheduler.analyze(events: events)
        XCTAssertEqual(report.currentVerdict, .insufficientData)
        XCTAssertEqual(report.totalEventsAnalyzed, 1)
        XCTAssertTrue(report.weekdayQuietWindows.isEmpty)
    }

    func testDetectsQuietHours() {
        // User reads heavily at 8,9,10,18,19,20 — so 0-7 and 11-17 and 21-23 should be quiet
        let activeHours = [8, 9, 10, 18, 19, 20]
        let events = generateEvents(activeHours: activeHours, count: 5)
        let scheduler = FeedQuietHoursScheduler(config: QuietHoursConfig(minEventsForRecommendation: 10))
        let report = scheduler.analyze(events: events)

        XCTAssertFalse(report.weekdayQuietWindows.isEmpty)
        XCTAssertEqual(report.totalEventsAnalyzed, 30)

        // Hour 3 should be quiet
        XCTAssertTrue(report.isQuiet(hour: 3, dayType: .weekday))
        // Hour 9 should be active
        XCTAssertFalse(report.isQuiet(hour: 9, dayType: .weekday))
    }

    func testPeakHoursIdentified() {
        let events = generateEvents(activeHours: [9, 10, 11, 14, 15], count: 10)
        let scheduler = FeedQuietHoursScheduler(config: QuietHoursConfig(minEventsForRecommendation: 10))
        let report = scheduler.analyze(events: events)

        XCTAssertFalse(report.peakReadingHours.isEmpty)
        XCTAssertTrue(report.peakReadingHours.count <= 3)
    }

    func testShouldSuppressNow() {
        // Create events only at 9-11 so current hour (if not 9-11) should be quiet
        let events = generateEvents(activeHours: [9, 10, 11], count: 10)
        let fixedHour = 3 // 3AM should be quiet
        let fixedDate = makeDate(hour: fixedHour, weekday: 2)
        let scheduler = FeedQuietHoursScheduler(
            config: QuietHoursConfig(minEventsForRecommendation: 10),
            now: { fixedDate }
        )
        XCTAssertTrue(scheduler.shouldSuppressNow(events: events))
    }

    func testActiveHourNotSuppressed() {
        let events = generateEvents(activeHours: [9, 10, 11], count: 10)
        let fixedDate = makeDate(hour: 10, weekday: 2)
        let scheduler = FeedQuietHoursScheduler(
            config: QuietHoursConfig(minEventsForRecommendation: 10),
            now: { fixedDate }
        )
        XCTAssertFalse(scheduler.shouldSuppressNow(events: events))
    }

    func testWeekendSeparation() {
        // Weekday active at 9, weekend active at 14
        var events = generateEvents(activeHours: [9, 10], count: 10, weekday: 2)
        events += generateEvents(activeHours: [14, 15], count: 10, weekday: 7) // Saturday

        let scheduler = FeedQuietHoursScheduler(config: QuietHoursConfig(
            minEventsForRecommendation: 10,
            separateWeekends: true
        ))
        let report = scheduler.analyze(events: events)

        // Hour 9 on weekday = active
        XCTAssertFalse(report.isQuiet(hour: 9, dayType: .weekday))
        // Hour 14 on weekend = active
        XCTAssertFalse(report.isQuiet(hour: 14, dayType: .weekend))
    }

    func testNextFetchTimeReturnsNilWhenActive() {
        let events = generateEvents(activeHours: [9, 10, 11], count: 10)
        let fixedDate = makeDate(hour: 10, weekday: 2)
        let scheduler = FeedQuietHoursScheduler(
            config: QuietHoursConfig(minEventsForRecommendation: 10),
            now: { fixedDate }
        )
        XCTAssertNil(scheduler.nextFetchTime(events: events))
    }

    func testFormatMarkdown() {
        let events = generateEvents(activeHours: [8, 9, 10, 18, 19, 20], count: 5)
        let scheduler = FeedQuietHoursScheduler(config: QuietHoursConfig(minEventsForRecommendation: 10))
        let report = scheduler.analyze(events: events)
        let md = scheduler.formatMarkdown(report: report)

        XCTAssertTrue(md.contains("## Quiet Hours Schedule"))
        XCTAssertTrue(md.contains("Events analyzed"))
    }

    func testQuietWindowDuration() {
        let window = QuietWindow(startHour: 22, endHour: 6, confidence: 0.9)
        XCTAssertEqual(window.durationHours, 8)

        let window2 = QuietWindow(startHour: 1, endHour: 5, confidence: 0.8)
        XCTAssertEqual(window2.durationHours, 4)
    }

    func testEmptyEventsInsufficientData() {
        let scheduler = FeedQuietHoursScheduler()
        let report = scheduler.analyze(events: [])
        XCTAssertEqual(report.currentVerdict, .insufficientData)
        XCTAssertEqual(report.quietHoursPerDay, 0)
    }
}
