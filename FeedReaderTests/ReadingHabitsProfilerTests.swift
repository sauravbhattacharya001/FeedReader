//
//  ReadingHabitsProfilerTests.swift
//  FeedReaderTests
//
//  Tests for reading behavior pattern analysis.
//

import XCTest
@testable import FeedReader

class ReadingHabitsProfilerTests: XCTestCase {

    var profiler: ReadingHabitsProfiler!

    override func setUp() {
        super.setUp()
        profiler = ReadingHabitsProfiler()
    }

    // MARK: - Helpers

    private func makeDate(daysAgo: Int = 0, hour: Int = 10, minute: Int = 0) -> Date {
        var calendar = Calendar.current
        calendar.timeZone = TimeZone.current
        var comps = calendar.dateComponents([.year, .month, .day], from: Date())
        comps.hour = hour
        comps.minute = minute
        comps.second = 0
        let base = calendar.date(from: comps)!
        return calendar.date(byAdding: .day, value: -daysAgo, to: base)!
    }

    private func makeDateOnWeekday(_ weekday: Int, hour: Int = 10) -> Date {
        var calendar = Calendar.current
        calendar.timeZone = TimeZone.current
        let today = Date()
        let currentWeekday = calendar.component(.weekday, from: today)
        let diff = weekday - currentWeekday
        let target = calendar.date(byAdding: .day, value: diff, to: today)!
        var comps = calendar.dateComponents([.year, .month, .day], from: target)
        comps.hour = hour
        comps.minute = 0
        comps.second = 0
        return calendar.date(from: comps)!
    }

    // MARK: - TimeSlot

    func testTimeSlotFromHour() {
        XCTAssertEqual(TimeSlot.from(hour: 5), .earlyMorning)
        XCTAssertEqual(TimeSlot.from(hour: 8), .earlyMorning)
        XCTAssertEqual(TimeSlot.from(hour: 9), .morning)
        XCTAssertEqual(TimeSlot.from(hour: 11), .morning)
        XCTAssertEqual(TimeSlot.from(hour: 12), .afternoon)
        XCTAssertEqual(TimeSlot.from(hour: 16), .afternoon)
        XCTAssertEqual(TimeSlot.from(hour: 17), .evening)
        XCTAssertEqual(TimeSlot.from(hour: 20), .evening)
        XCTAssertEqual(TimeSlot.from(hour: 21), .night)
        XCTAssertEqual(TimeSlot.from(hour: 23), .night)
        XCTAssertEqual(TimeSlot.from(hour: 0), .night)
        XCTAssertEqual(TimeSlot.from(hour: 2), .lateNight)
        XCTAssertEqual(TimeSlot.from(hour: 4), .lateNight)
    }

    func testTimeSlotLabels() {
        XCTAssertTrue(TimeSlot.earlyMorning.label.contains("5-9"))
        XCTAssertTrue(TimeSlot.morning.label.contains("9am"))
        XCTAssertTrue(TimeSlot.afternoon.label.contains("12"))
        XCTAssertTrue(TimeSlot.evening.label.contains("5-9"))
        XCTAssertTrue(TimeSlot.night.label.contains("9pm"))
        XCTAssertTrue(TimeSlot.lateNight.label.contains("1-5"))
    }

    func testTimeSlotComparable() {
        XCTAssertTrue(TimeSlot.earlyMorning < TimeSlot.morning)
        XCTAssertTrue(TimeSlot.morning < TimeSlot.afternoon)
        XCTAssertTrue(TimeSlot.evening < TimeSlot.night)
    }

    // MARK: - SessionCategory

    func testSessionCategoryFromMinutes() {
        XCTAssertEqual(SessionCategory.from(minutes: 2), .quickScan)
        XCTAssertEqual(SessionCategory.from(minutes: 4.9), .quickScan)
        XCTAssertEqual(SessionCategory.from(minutes: 5), .shortRead)
        XCTAssertEqual(SessionCategory.from(minutes: 14.9), .shortRead)
        XCTAssertEqual(SessionCategory.from(minutes: 15), .mediumRead)
        XCTAssertEqual(SessionCategory.from(minutes: 29), .mediumRead)
        XCTAssertEqual(SessionCategory.from(minutes: 30), .deepRead)
        XCTAssertEqual(SessionCategory.from(minutes: 59), .deepRead)
        XCTAssertEqual(SessionCategory.from(minutes: 60), .marathon)
        XCTAssertEqual(SessionCategory.from(minutes: 120), .marathon)
    }

    func testSessionCategoryLabels() {
        XCTAssertTrue(SessionCategory.quickScan.label.contains("5m"))
        XCTAssertTrue(SessionCategory.marathon.label.contains("60m"))
    }

    // MARK: - Event Recording

    func testRecordEvent() {
        let event = profiler.recordEvent(date: makeDate(hour: 10), durationMinutes: 15, articlesRead: 3, feedName: "TechCrunch")
        XCTAssertNotNil(event)
        XCTAssertEqual(profiler.eventCount, 1)
        XCTAssertEqual(event?.feedName, "TechCrunch")
        XCTAssertEqual(event?.durationMinutes, 15)
        XCTAssertEqual(event?.articlesRead, 3)
    }

    func testRecordEventWithTopic() {
        let event = profiler.recordEvent(date: makeDate(hour: 14), durationMinutes: 20, articlesRead: 4, feedName: "Ars Technica", topic: "Technology")
        XCTAssertNotNil(event)
        XCTAssertEqual(event?.topic, "Technology")
        XCTAssertEqual(event?.timeSlot, .afternoon)
    }

    func testRecordEventRejectsZeroDuration() {
        let event = profiler.recordEvent(date: makeDate(), durationMinutes: 0, articlesRead: 1, feedName: "Test")
        XCTAssertNil(event)
        XCTAssertEqual(profiler.eventCount, 0)
    }

    func testRecordEventRejectsNegativeDuration() {
        let event = profiler.recordEvent(date: makeDate(), durationMinutes: -5, articlesRead: 1, feedName: "Test")
        XCTAssertNil(event)
    }

    func testRecordEventRejectsZeroArticles() {
        let event = profiler.recordEvent(date: makeDate(), durationMinutes: 10, articlesRead: 0, feedName: "Test")
        XCTAssertNil(event)
    }

    func testMaxEventsEnforced() {
        let profiler = ReadingHabitsProfiler()
        for i in 0..<ReadingHabitsProfiler.maxEvents {
            let result = profiler.recordEvent(date: makeDate(daysAgo: i % 365), durationMinutes: 10, articlesRead: 1, feedName: "Feed")
            XCTAssertNotNil(result, "Event \(i) should be accepted")
        }
        let overflow = profiler.recordEvent(date: makeDate(), durationMinutes: 10, articlesRead: 1, feedName: "Overflow")
        XCTAssertNil(overflow)
        XCTAssertEqual(profiler.eventCount, ReadingHabitsProfiler.maxEvents)
    }

    func testClearEvents() {
        profiler.recordEvent(date: makeDate(), durationMinutes: 10, articlesRead: 1, feedName: "A")
        profiler.recordEvent(date: makeDate(), durationMinutes: 20, articlesRead: 2, feedName: "B")
        XCTAssertEqual(profiler.eventCount, 2)
        profiler.clearEvents()
        XCTAssertEqual(profiler.eventCount, 0)
        XCTAssertTrue(profiler.allEvents().isEmpty)
    }

    func testEventsDateRange() {
        profiler.recordEvent(date: makeDate(daysAgo: 5), durationMinutes: 10, articlesRead: 1, feedName: "A")
        profiler.recordEvent(date: makeDate(daysAgo: 3), durationMinutes: 10, articlesRead: 1, feedName: "B")
        profiler.recordEvent(date: makeDate(daysAgo: 1), durationMinutes: 10, articlesRead: 1, feedName: "C")
        let filtered = profiler.events(from: makeDate(daysAgo: 4), to: makeDate(daysAgo: 2))
        XCTAssertEqual(filtered.count, 1)
        XCTAssertEqual(filtered[0].feedName, "B")
    }

    // MARK: - ReadingEvent Model

    func testReadingEventTimeSlotAssignment() {
        let morning = ReadingEvent(date: makeDate(hour: 10), durationMinutes: 10, articlesRead: 1, feedName: "Test")
        XCTAssertEqual(morning.timeSlot, .morning)
        let evening = ReadingEvent(date: makeDate(hour: 19), durationMinutes: 10, articlesRead: 1, feedName: "Test")
        XCTAssertEqual(evening.timeSlot, .evening)
    }

    func testReadingEventNegativesClamped() {
        let event = ReadingEvent(date: makeDate(), durationMinutes: -10, articlesRead: -5, feedName: "Test")
        XCTAssertEqual(event.durationMinutes, 0)
        XCTAssertEqual(event.articlesRead, 0)
    }

    // MARK: - Time Slot Distribution

    func testTimeSlotDistributionEmpty() {
        let dist = profiler.computeTimeSlotDistribution()
        XCTAssertEqual(dist.count, TimeSlot.allCases.count)
        XCTAssertTrue(dist.allSatisfy { $0.eventCount == 0 })
    }

    func testTimeSlotDistributionCounts() {
        profiler.recordEvent(date: makeDate(hour: 10), durationMinutes: 20, articlesRead: 3, feedName: "A")
        profiler.recordEvent(date: makeDate(hour: 11), durationMinutes: 15, articlesRead: 2, feedName: "B")
        profiler.recordEvent(date: makeDate(hour: 19), durationMinutes: 30, articlesRead: 5, feedName: "C")
        let dist = profiler.computeTimeSlotDistribution()
        let morning = dist.first { $0.slot == .morning }!
        let evening = dist.first { $0.slot == .evening }!
        XCTAssertEqual(morning.eventCount, 2)
        XCTAssertEqual(morning.totalMinutes, 35)
        XCTAssertEqual(morning.totalArticles, 5)
        XCTAssertEqual(evening.eventCount, 1)
        XCTAssertEqual(evening.totalMinutes, 30)
    }

    func testTimeSlotTopics() {
        profiler.recordEvent(date: makeDate(hour: 10), durationMinutes: 10, articlesRead: 1, feedName: "A", topic: "Tech")
        profiler.recordEvent(date: makeDate(hour: 11), durationMinutes: 10, articlesRead: 1, feedName: "B", topic: "Tech")
        profiler.recordEvent(date: makeDate(hour: 10), durationMinutes: 10, articlesRead: 1, feedName: "C", topic: "Science")
        let dist = profiler.computeTimeSlotDistribution()
        let morning = dist.first { $0.slot == .morning }!
        XCTAssertEqual(morning.topics["Tech"], 2)
        XCTAssertEqual(morning.topics["Science"], 1)
        XCTAssertEqual(morning.topTopics.first, "Tech")
    }

    func testPeakTimeSlot() {
        profiler.recordEvent(date: makeDate(hour: 10), durationMinutes: 10, articlesRead: 1, feedName: "A")
        profiler.recordEvent(date: makeDate(hour: 19), durationMinutes: 30, articlesRead: 3, feedName: "B")
        XCTAssertEqual(profiler.peakTimeSlot(), .evening)
    }

    func testPeakTimeSlotEmpty() {
        XCTAssertNil(profiler.peakTimeSlot())
    }

    // MARK: - Day of Week Distribution

    func testDayOfWeekDistributionEmpty() {
        let dist = profiler.computeDayOfWeekDistribution()
        XCTAssertEqual(dist.count, 7)
        XCTAssertTrue(dist.allSatisfy { $0.eventCount == 0 })
    }

    func testDayOfWeekDistribution() {
        let mondayDate = makeDateOnWeekday(2, hour: 10)
        profiler.recordEvent(date: mondayDate, durationMinutes: 20, articlesRead: 3, feedName: "A")
        let dist = profiler.computeDayOfWeekDistribution()
        let monday = dist.first { $0.dayOfWeek == 2 }!
        XCTAssertEqual(monday.eventCount, 1)
        XCTAssertEqual(monday.dayName, "Monday")
        XCTAssertFalse(monday.isWeekend)
    }

    func testDayOfWeekNames() {
        let sunday = DayOfWeekStats(dayOfWeek: 1)
        XCTAssertEqual(sunday.dayName, "Sunday")
        XCTAssertTrue(sunday.isWeekend)
        let saturday = DayOfWeekStats(dayOfWeek: 7)
        XCTAssertEqual(saturday.dayName, "Saturday")
        XCTAssertTrue(saturday.isWeekend)
        let wednesday = DayOfWeekStats(dayOfWeek: 4)
        XCTAssertEqual(wednesday.dayName, "Wednesday")
        XCTAssertFalse(wednesday.isWeekend)
    }

    func testPeakDayOfWeek() {
        let sunday = makeDateOnWeekday(1, hour: 10)
        let monday = makeDateOnWeekday(2, hour: 10)
        profiler.recordEvent(date: sunday, durationMinutes: 60, articlesRead: 5, feedName: "A")
        profiler.recordEvent(date: monday, durationMinutes: 10, articlesRead: 1, feedName: "B")
        XCTAssertEqual(profiler.peakDayOfWeek(), 1)
    }

    // MARK: - Weekday/Weekend Ratio

    func testWeekdayWeekendRatioEmpty() {
        XCTAssertEqual(profiler.computeWeekdayWeekendRatio(), 0)
    }

    func testWeekdayOnlyRatio() {
        let monday = makeDateOnWeekday(2, hour: 10)
        profiler.recordEvent(date: monday, durationMinutes: 10, articlesRead: 1, feedName: "A")
        XCTAssertEqual(profiler.computeWeekdayWeekendRatio(), .infinity)
    }

    func testWeekendOnlyRatio() {
        let sunday = makeDateOnWeekday(1, hour: 10)
        profiler.recordEvent(date: sunday, durationMinutes: 10, articlesRead: 1, feedName: "A")
        XCTAssertEqual(profiler.computeWeekdayWeekendRatio(), 0)
    }

    // MARK: - Session Categories

    func testSessionCategories() {
        profiler.recordEvent(date: makeDate(), durationMinutes: 3, articlesRead: 1, feedName: "A")
        profiler.recordEvent(date: makeDate(), durationMinutes: 10, articlesRead: 2, feedName: "B")
        profiler.recordEvent(date: makeDate(), durationMinutes: 25, articlesRead: 4, feedName: "C")
        profiler.recordEvent(date: makeDate(), durationMinutes: 45, articlesRead: 6, feedName: "D")
        profiler.recordEvent(date: makeDate(), durationMinutes: 90, articlesRead: 10, feedName: "E")
        let cats = profiler.computeSessionCategories()
        XCTAssertEqual(cats["quick_scan"], 1)
        XCTAssertEqual(cats["short_read"], 1)
        XCTAssertEqual(cats["medium_read"], 1)
        XCTAssertEqual(cats["deep_read"], 1)
        XCTAssertEqual(cats["marathon"], 1)
    }

    func testSessionCategoriesEmpty() {
        let cats = profiler.computeSessionCategories()
        XCTAssertTrue(cats.values.allSatisfy { $0 == 0 })
    }

    // MARK: - Consistency Score

    func testConsistencyTooFewEvents() {
        profiler.recordEvent(date: makeDate(), durationMinutes: 10, articlesRead: 1, feedName: "A")
        profiler.recordEvent(date: makeDate(), durationMinutes: 10, articlesRead: 1, feedName: "B")
        XCTAssertEqual(profiler.computeConsistencyScore(), 0)
    }

    func testConsistencyPerfect() {
        for day in 0..<7 {
            profiler.recordEvent(date: makeDate(daysAgo: day, hour: 10), durationMinutes: 10, articlesRead: 1, feedName: "Feed")
        }
        XCTAssertGreaterThan(profiler.computeConsistencyScore(), 0.8)
    }

    func testConsistencyPoor() {
        profiler.recordEvent(date: makeDate(daysAgo: 0), durationMinutes: 10, articlesRead: 1, feedName: "A")
        profiler.recordEvent(date: makeDate(daysAgo: 15), durationMinutes: 10, articlesRead: 1, feedName: "B")
        profiler.recordEvent(date: makeDate(daysAgo: 30), durationMinutes: 10, articlesRead: 1, feedName: "C")
        XCTAssertLessThan(profiler.computeConsistencyScore(), 0.2)
    }

    func testConsistencyBetweenZeroAndOne() {
        for day in stride(from: 0, to: 20, by: 3) {
            profiler.recordEvent(date: makeDate(daysAgo: day, hour: 10), durationMinutes: 10, articlesRead: 1, feedName: "Feed")
        }
        let score = profiler.computeConsistencyScore()
        XCTAssertGreaterThanOrEqual(score, 0)
        XCTAssertLessThanOrEqual(score, 1)
    }

    // MARK: - Optimal Windows

    func testOptimalWindowsEmpty() {
        XCTAssertTrue(profiler.computeOptimalWindows().isEmpty)
    }

    func testOptimalWindowsNeedMinimumEvents() {
        profiler.recordEvent(date: makeDate(hour: 10), durationMinutes: 20, articlesRead: 5, feedName: "A")
        XCTAssertTrue(profiler.computeOptimalWindows().isEmpty)
    }

    func testOptimalWindowsIdentifiesBest() {
        profiler.recordEvent(date: makeDate(daysAgo: 0, hour: 10), durationMinutes: 10, articlesRead: 5, feedName: "A")
        profiler.recordEvent(date: makeDate(daysAgo: 1, hour: 11), durationMinutes: 10, articlesRead: 5, feedName: "B")
        profiler.recordEvent(date: makeDate(daysAgo: 0, hour: 19), durationMinutes: 30, articlesRead: 2, feedName: "C")
        profiler.recordEvent(date: makeDate(daysAgo: 1, hour: 20), durationMinutes: 30, articlesRead: 2, feedName: "D")
        let windows = profiler.computeOptimalWindows()
        XCTAssertFalse(windows.isEmpty)
        XCTAssertEqual(windows.first?.timeSlot, .morning)
        XCTAssertGreaterThan(windows.first?.score ?? 0, 0.5)
    }

    func testOptimalWindowsSortedByScore() {
        for i in 0..<3 {
            profiler.recordEvent(date: makeDate(daysAgo: i, hour: 10), durationMinutes: 10, articlesRead: 5, feedName: "A")
            profiler.recordEvent(date: makeDate(daysAgo: i, hour: 14), durationMinutes: 10, articlesRead: 3, feedName: "B")
            profiler.recordEvent(date: makeDate(daysAgo: i, hour: 19), durationMinutes: 10, articlesRead: 1, feedName: "C")
        }
        let windows = profiler.computeOptimalWindows()
        for i in 0..<(windows.count - 1) {
            XCTAssertGreaterThanOrEqual(windows[i].score, windows[i + 1].score)
        }
    }

    // MARK: - Reader Type

    func testReaderTypeNewcomer() {
        XCTAssertEqual(profiler.classifyReaderType(), "Newcomer")
    }

    func testReaderTypeDedicatedScholar() {
        for day in 0..<14 {
            profiler.recordEvent(date: makeDate(daysAgo: day, hour: 10), durationMinutes: 30, articlesRead: 5, feedName: "Academic")
        }
        XCTAssertEqual(profiler.classifyReaderType(), "Dedicated Scholar")
    }

    func testReaderTypeDeepDiver() {
        for i in 0..<10 {
            profiler.recordEvent(date: makeDate(daysAgo: i * 5, hour: 10), durationMinutes: 60, articlesRead: 8, feedName: "Feed")
        }
        let type = profiler.classifyReaderType()
        XCTAssertTrue(type == "Deep Diver" || type == "Deep Thinker")
    }

    func testReaderTypeSpeedScanner() {
        for i in 0..<10 {
            profiler.recordEvent(date: makeDate(daysAgo: i, hour: 10), durationMinutes: 3, articlesRead: 2, feedName: "Feed")
        }
        XCTAssertEqual(profiler.classifyReaderType(), "Speed Scanner")
    }

    func testReaderTypeExplorer() {
        profiler.recordEvent(date: makeDate(daysAgo: 0), durationMinutes: 10, articlesRead: 2, feedName: "A")
        profiler.recordEvent(date: makeDate(daysAgo: 1), durationMinutes: 20, articlesRead: 3, feedName: "B")
        profiler.recordEvent(date: makeDate(daysAgo: 3), durationMinutes: 15, articlesRead: 2, feedName: "C")
        XCTAssertEqual(profiler.classifyReaderType(), "Explorer")
    }

    // MARK: - Recommendations

    func testRecommendationsFewEvents() {
        profiler.recordEvent(date: makeDate(), durationMinutes: 10, articlesRead: 1, feedName: "A")
        let recs = profiler.generateRecommendations()
        XCTAssertEqual(recs.count, 1)
        XCTAssertTrue(recs[0].message.contains("few more sessions"))
    }

    func testRecommendationsConsistencyWarning() {
        profiler.recordEvent(date: makeDate(daysAgo: 0), durationMinutes: 10, articlesRead: 1, feedName: "A")
        profiler.recordEvent(date: makeDate(daysAgo: 15), durationMinutes: 10, articlesRead: 1, feedName: "B")
        profiler.recordEvent(date: makeDate(daysAgo: 30), durationMinutes: 10, articlesRead: 1, feedName: "C")
        let recs = profiler.generateRecommendations()
        let consistency = recs.first { $0.category == "Consistency" }
        XCTAssertNotNil(consistency)
        XCTAssertTrue(consistency!.message.contains("sporadic"))
    }

    func testRecommendationsDepthWarning() {
        for i in 0..<10 {
            profiler.recordEvent(date: makeDate(daysAgo: i), durationMinutes: 3, articlesRead: 1, feedName: "A")
        }
        let recs = profiler.generateRecommendations()
        let depth = recs.first { $0.category == "Depth" }
        XCTAssertNotNil(depth)
    }

    func testRecommendationsLateNightWarning() {
        for i in 0..<6 {
            profiler.recordEvent(date: makeDate(daysAgo: i, hour: 3), durationMinutes: 20, articlesRead: 2, feedName: "A")
        }
        let recs = profiler.generateRecommendations()
        let timing = recs.first { $0.category == "Timing" }
        XCTAssertNotNil(timing)
        XCTAssertTrue(timing!.message.contains("late at night"))
    }

    func testRecommendationsSortedByPriority() {
        for i in 0..<10 {
            profiler.recordEvent(date: makeDate(daysAgo: i * 5, hour: 3), durationMinutes: 3, articlesRead: 1, feedName: "A")
        }
        let recs = profiler.generateRecommendations()
        for i in 0..<(recs.count - 1) {
            XCTAssertLessThanOrEqual(recs[i].priority, recs[i + 1].priority)
        }
    }

    func testRecommendationsOptimalWindow() {
        for i in 0..<5 {
            profiler.recordEvent(date: makeDate(daysAgo: i, hour: 10), durationMinutes: 20, articlesRead: 5, feedName: "A")
            profiler.recordEvent(date: makeDate(daysAgo: i, hour: 19), durationMinutes: 20, articlesRead: 2, feedName: "B")
        }
        let recs = profiler.generateRecommendations()
        let opt = recs.first { $0.category == "Optimization" }
        XCTAssertNotNil(opt)
        XCTAssertTrue(opt!.message.contains("productive"))
    }

    // MARK: - Profile Generation

    func testGenerateProfileEmpty() {
        let profile = profiler.generateProfile()
        XCTAssertEqual(profile.totalEvents, 0)
        XCTAssertEqual(profile.totalMinutes, 0)
        XCTAssertEqual(profile.totalArticles, 0)
        XCTAssertNil(profile.dateRange)
        XCTAssertEqual(profile.readerType, "Newcomer")
    }

    func testGenerateProfileAggregates() {
        profiler.recordEvent(date: makeDate(daysAgo: 1, hour: 10), durationMinutes: 20, articlesRead: 3, feedName: "A")
        profiler.recordEvent(date: makeDate(daysAgo: 0, hour: 14), durationMinutes: 30, articlesRead: 5, feedName: "B")
        let profile = profiler.generateProfile()
        XCTAssertEqual(profile.totalEvents, 2)
        XCTAssertEqual(profile.totalMinutes, 50)
        XCTAssertEqual(profile.totalArticles, 8)
        XCTAssertNotNil(profile.dateRange)
    }

    func testGenerateProfileCached() {
        profiler.recordEvent(date: makeDate(), durationMinutes: 10, articlesRead: 1, feedName: "A")
        let p1 = profiler.generateProfile()
        let p2 = profiler.generateProfile()
        XCTAssertEqual(p1.generatedAt, p2.generatedAt)
    }

    func testProfileCacheInvalidatedOnNewEvent() {
        profiler.recordEvent(date: makeDate(), durationMinutes: 10, articlesRead: 1, feedName: "A")
        let p1 = profiler.generateProfile()
        XCTAssertEqual(p1.totalEvents, 1)
        profiler.recordEvent(date: makeDate(), durationMinutes: 20, articlesRead: 2, feedName: "B")
        let p2 = profiler.generateProfile()
        XCTAssertEqual(p2.totalEvents, 2)
    }

    func testProfileHasAllTimeSlots() {
        profiler.recordEvent(date: makeDate(hour: 10), durationMinutes: 10, articlesRead: 1, feedName: "A")
        let profile = profiler.generateProfile()
        XCTAssertEqual(profile.timeSlotDistribution.count, TimeSlot.allCases.count)
    }

    func testProfileHasAllDays() {
        profiler.recordEvent(date: makeDate(hour: 10), durationMinutes: 10, articlesRead: 1, feedName: "A")
        let profile = profiler.generateProfile()
        XCTAssertEqual(profile.dayOfWeekDistribution.count, 7)
    }

    // MARK: - Export

    func testExportProfileJSON() {
        profiler.recordEvent(date: makeDate(), durationMinutes: 15, articlesRead: 2, feedName: "Test")
        let json = profiler.exportProfileJSON()
        XCTAssertNotNil(json)
        XCTAssertTrue(json!.contains("totalEvents"))
        XCTAssertTrue(json!.contains("readerType"))
        XCTAssertTrue(json!.contains("recommendations"))
    }

    func testExportEventsJSON() {
        profiler.recordEvent(date: makeDate(), durationMinutes: 15, articlesRead: 2, feedName: "Test")
        let json = profiler.exportEventsJSON()
        XCTAssertNotNil(json)
        XCTAssertTrue(json!.contains("feedName"))
        XCTAssertTrue(json!.contains("durationMinutes"))
    }

    func testExportEmptyReturnsValidJSON() {
        let json = profiler.exportProfileJSON()
        XCTAssertNotNil(json)
        XCTAssertTrue(json!.contains("Newcomer"))
    }

    // MARK: - Summary

    func testProfileSummary() {
        for i in 0..<5 {
            profiler.recordEvent(date: makeDate(daysAgo: i, hour: 10), durationMinutes: 20, articlesRead: 3, feedName: "Feed")
        }
        let summary = profiler.profileSummary()
        XCTAssertTrue(summary.contains("Reading Habits Profile"))
        XCTAssertTrue(summary.contains("Reader Type:"))
        XCTAssertTrue(summary.contains("Total Sessions: 5"))
        XCTAssertTrue(summary.contains("Peak Reading Time"))
        XCTAssertTrue(summary.contains("Recommendations"))
    }

    func testProfileSummaryEmpty() {
        let summary = profiler.profileSummary()
        XCTAssertTrue(summary.contains("Total Sessions: 0"))
        XCTAssertTrue(summary.contains("Newcomer"))
    }

    // MARK: - Init with Events

    func testInitWithExistingEvents() {
        let events = [
            ReadingEvent(date: makeDate(daysAgo: 0), durationMinutes: 10, articlesRead: 1, feedName: "A"),
            ReadingEvent(date: makeDate(daysAgo: 1), durationMinutes: 20, articlesRead: 2, feedName: "B")
        ]
        let p = ReadingHabitsProfiler(events: events)
        XCTAssertEqual(p.eventCount, 2)
    }

    func testInitTruncatesExcessEvents() {
        var events: [ReadingEvent] = []
        for i in 0..<6000 {
            events.append(ReadingEvent(date: makeDate(daysAgo: i % 365), durationMinutes: 10, articlesRead: 1, feedName: "Feed"))
        }
        let p = ReadingHabitsProfiler(events: events)
        XCTAssertEqual(p.eventCount, ReadingHabitsProfiler.maxEvents)
    }

    // MARK: - TimeSlotStats Averages

    func testTimeSlotStatsAverages() {
        var stats = TimeSlotStats(slot: .morning)
        stats.eventCount = 4
        stats.totalMinutes = 100
        stats.totalArticles = 20
        XCTAssertEqual(stats.averageMinutes, 25)
        XCTAssertEqual(stats.averageArticles, 5)
    }

    func testTimeSlotStatsAveragesEmpty() {
        let stats = TimeSlotStats(slot: .morning)
        XCTAssertEqual(stats.averageMinutes, 0)
        XCTAssertEqual(stats.averageArticles, 0)
    }

    // MARK: - Edge Cases

    func testAllTimeSlotsCovered() {
        let hours = [6, 10, 14, 18, 22, 3]
        let expectedSlots: [TimeSlot] = [.earlyMorning, .morning, .afternoon, .evening, .night, .lateNight]
        for (i, hour) in hours.enumerated() {
            profiler.recordEvent(date: makeDate(daysAgo: i, hour: hour), durationMinutes: 10, articlesRead: 1, feedName: "Feed")
        }
        let dist = profiler.computeTimeSlotDistribution()
        for slot in expectedSlots {
            let stats = dist.first { $0.slot == slot }!
            XCTAssertGreaterThan(stats.eventCount, 0, "Slot \(slot.label) should have events")
        }
    }

    func testMultipleEventsOnSameDay() {
        profiler.recordEvent(date: makeDate(daysAgo: 0, hour: 10), durationMinutes: 10, articlesRead: 1, feedName: "A")
        profiler.recordEvent(date: makeDate(daysAgo: 0, hour: 14), durationMinutes: 10, articlesRead: 1, feedName: "B")
        profiler.recordEvent(date: makeDate(daysAgo: 0, hour: 19), durationMinutes: 10, articlesRead: 1, feedName: "C")
        profiler.recordEvent(date: makeDate(daysAgo: 10, hour: 10), durationMinutes: 10, articlesRead: 1, feedName: "D")
        let score = profiler.computeConsistencyScore()
        XCTAssertLessThan(score, 0.3)
    }

    func testHabitRecommendationEquatable() {
        let r1 = HabitRecommendation(category: "Test", message: "Hello", priority: 1)
        let r2 = HabitRecommendation(category: "Test", message: "Hello", priority: 1)
        let r3 = HabitRecommendation(category: "Test", message: "Different", priority: 1)
        XCTAssertEqual(r1, r2)
        XCTAssertNotEqual(r1, r3)
    }
}
