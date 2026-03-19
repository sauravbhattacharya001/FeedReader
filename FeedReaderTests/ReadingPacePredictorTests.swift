//
//  ReadingPacePredictorTests.swift
//  FeedReaderTests
//
//  Tests for ReadingPacePredictor functionality.
//

import XCTest
@testable import FeedReader

class ReadingPacePredictorTests: XCTestCase {

    override func setUp() {
        super.setUp()
        ReadingPacePredictor.shared.clearHistory()
    }

    func testGenerateForecastReturnsValidForecast() {
        let forecast = ReadingPacePredictor.shared.generateForecast()
        XCTAssertFalse(forecast.id.isEmpty)
        XCTAssertGreaterThanOrEqual(forecast.queueSize, 0)
        XCTAssertGreaterThanOrEqual(forecast.totalMinutesNeeded, 0)
        XCTAssertGreaterThan(forecast.effectiveWPM, 0)
    }

    func testGenerateScheduleReturnsOrderedItems() {
        let schedule = ReadingPacePredictor.shared.generateSchedule()
        for (index, item) in schedule.enumerated() {
            XCTAssertEqual(item.position, index + 1)
            if index > 0 {
                XCTAssertGreaterThanOrEqual(item.cumulativeMinutes, schedule[index - 1].cumulativeMinutes)
            }
        }
    }

    func testPaceScenarioMultipliers() {
        XCTAssertEqual(PaceScenario.conservative.multiplier, 0.75)
        XCTAssertEqual(PaceScenario.current.multiplier, 1.0)
        XCTAssertEqual(PaceScenario.optimistic.multiplier, 1.25)
        XCTAssertEqual(PaceScenario.aggressive.multiplier, 1.50)
    }

    func testAllScenariosReturnResults() {
        for scenario in PaceScenario.allCases {
            let result = ReadingPacePredictor.shared.forecastForScenario(scenario)
            // Result may be nil if queue is empty, but shouldn't crash
            if let days = result.daysToComplete {
                XCTAssertGreaterThanOrEqual(days, 0)
            }
        }
    }

    func testBacklogTrendWithNoHistory() {
        let trend = ReadingPacePredictor.shared.analyzeBacklogTrend()
        XCTAssertEqual(trend, .stable)
    }

    func testBacklogTrendEmoji() {
        XCTAssertEqual(BacklogTrend.shrinking.emoji, "📉")
        XCTAssertEqual(BacklogTrend.stable.emoji, "➡️")
        XCTAssertEqual(BacklogTrend.growing.emoji, "📈")
        XCTAssertEqual(BacklogTrend.exploding.emoji, "🚨")
    }

    func testQueueHealthSummaryContainsExpectedKeys() {
        let summary = ReadingPacePredictor.shared.queueHealthSummary()
        XCTAssertNotNil(summary["queueSize"])
        XCTAssertNotNil(summary["totalReadingHours"])
        XCTAssertNotNil(summary["readingSpeed"])
        XCTAssertNotNil(summary["dailyReadingMinutes"])
        XCTAssertNotNil(summary["backlogTrend"])
        XCTAssertNotNil(summary["weeklyCapacity"])
        XCTAssertNotNil(summary["daysToComplete"])
    }

    func testExportAsJSONProducesValidJSON() {
        let _ = ReadingPacePredictor.shared.generateForecast()
        guard let json = ReadingPacePredictor.shared.exportAsJSON() else {
            XCTFail("Export returned nil")
            return
        }
        XCTAssertFalse(json.isEmpty)
        let data = json.data(using: .utf8)!
        XCTAssertNoThrow(try JSONSerialization.jsonObject(with: data))
    }

    func testClearHistoryRemovesAll() {
        let _ = ReadingPacePredictor.shared.generateForecast()
        XCTAssertFalse(ReadingPacePredictor.shared.getForecastHistory().isEmpty)
        ReadingPacePredictor.shared.clearHistory()
        XCTAssertTrue(ReadingPacePredictor.shared.getForecastHistory().isEmpty)
    }

    func testForecastHistoryGrows() {
        let _ = ReadingPacePredictor.shared.generateForecast()
        let _ = ReadingPacePredictor.shared.generateForecast()
        XCTAssertEqual(ReadingPacePredictor.shared.getForecastHistory().count, 2)
    }
}
