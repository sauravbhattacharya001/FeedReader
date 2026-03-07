//
//  FeedSubscriptionAnalyzerTests.swift
//  FeedReaderTests
//
//  Tests for FeedSubscriptionAnalyzer — subscription events, engagement
//  tracking, lifecycle phases, hygiene reports, portfolio balance,
//  convenience queries, export, data management.
//

import XCTest
@testable import FeedReader

class FeedSubscriptionAnalyzerTests: XCTestCase {

    // MARK: - Helpers

    private let feed1 = "https://feeds.example.com/tech"
    private let feed2 = "https://feeds.example.com/science"
    private let feed3 = "https://feeds.example.com/news"

    private func daysAgo(_ days: Int) -> Date {
        return Calendar.current.date(byAdding: .day, value: -days, to: Date())!
    }

    override func setUp() {
        super.setUp()
        FeedSubscriptionAnalyzer.shared.clearAll()
    }

    override func tearDown() {
        FeedSubscriptionAnalyzer.shared.clearAll()
        super.tearDown()
    }

    // MARK: - Subscription Events

    func testRecordSubscribeEvent() {
        let event = FeedSubscriptionAnalyzer.shared.recordEvent(
            feedURL: feed1, feedTitle: "Tech Feed",
            category: "Technology",
            eventType: .subscribe
        )
        XCTAssertEqual(event.feedURL, feed1)
        XCTAssertEqual(event.feedTitle, "Tech Feed")
        XCTAssertEqual(event.category, "Technology")
        XCTAssertEqual(event.eventType, .subscribe)
        XCTAssertFalse(event.id.isEmpty)
    }

    func testRecordUnsubscribeEvent() {
        FeedSubscriptionAnalyzer.shared.recordEvent(
            feedURL: feed1, feedTitle: "Tech Feed", eventType: .subscribe)
        let event = FeedSubscriptionAnalyzer.shared.recordEvent(
            feedURL: feed1, feedTitle: "Tech Feed",
            eventType: .unsubscribe, reason: "Too noisy"
        )
        XCTAssertEqual(event.eventType, .unsubscribe)
        XCTAssertEqual(event.reason, "Too noisy")
    }

    func testRecordPauseResumeEvents() {
        FeedSubscriptionAnalyzer.shared.recordEvent(
            feedURL: feed1, feedTitle: "Tech", eventType: .subscribe)
        FeedSubscriptionAnalyzer.shared.recordEvent(
            feedURL: feed1, feedTitle: "Tech", eventType: .pause)
        FeedSubscriptionAnalyzer.shared.recordEvent(
            feedURL: feed1, feedTitle: "Tech", eventType: .resume)
        let events = FeedSubscriptionAnalyzer.shared.events(for: feed1)
        XCTAssertEqual(events.count, 3)
        XCTAssertEqual(events[0].eventType, .subscribe)
        XCTAssertEqual(events[1].eventType, .pause)
        XCTAssertEqual(events[2].eventType, .resume)
    }

    func testEventsForFeedOrdered() {
        FeedSubscriptionAnalyzer.shared.recordEvent(
            feedURL: feed1, feedTitle: "Tech",
            eventType: .subscribe, date: daysAgo(10))
        FeedSubscriptionAnalyzer.shared.recordEvent(
            feedURL: feed1, feedTitle: "Tech",
            eventType: .pause, date: daysAgo(5))
        let events = FeedSubscriptionAnalyzer.shared.events(for: feed1)
        XCTAssertTrue(events[0].date < events[1].date)
    }

    func testAllEventsOrderedMostRecentFirst() {
        FeedSubscriptionAnalyzer.shared.recordEvent(
            feedURL: feed1, feedTitle: "Tech",
            eventType: .subscribe, date: daysAgo(10))
        FeedSubscriptionAnalyzer.shared.recordEvent(
            feedURL: feed2, feedTitle: "Science",
            eventType: .subscribe, date: daysAgo(5))
        let all = FeedSubscriptionAnalyzer.shared.allEvents()
        XCTAssertTrue(all[0].date >= all[1].date)
    }

    func testEventCount() {
        FeedSubscriptionAnalyzer.shared.recordEvent(
            feedURL: feed1, feedTitle: "A", eventType: .subscribe)
        FeedSubscriptionAnalyzer.shared.recordEvent(
            feedURL: feed2, feedTitle: "B", eventType: .subscribe)
        FeedSubscriptionAnalyzer.shared.recordEvent(
            feedURL: feed1, feedTitle: "A", eventType: .unsubscribe)
        XCTAssertEqual(FeedSubscriptionAnalyzer.shared.eventCount(ofType: .subscribe), 2)
        XCTAssertEqual(FeedSubscriptionAnalyzer.shared.eventCount(ofType: .unsubscribe), 1)
    }

    // MARK: - Engagement Tracking

    func testRecordEngagementSnapshot() {
        FeedSubscriptionAnalyzer.shared.recordEngagement(
            feedURL: feed1, articlesPublished: 20,
            articlesRead: 15, articlesSkipped: 5,
            totalReadingTimeSec: 600,
            averageReadPercent: 80
        )
        let history = FeedSubscriptionAnalyzer.shared.engagementHistory(for: feed1)
        XCTAssertEqual(history.count, 1)
        XCTAssertEqual(history[0].articlesPublished, 20)
        XCTAssertEqual(history[0].articlesRead, 15)
    }

    func testEngagementSnapshotReadRate() {
        let snapshot = EngagementSnapshot(
            feedURL: feed1, windowStart: daysAgo(14), windowEnd: Date(),
            articlesPublished: 20, articlesRead: 10,
            articlesSkipped: 10, totalReadingTimeSec: 300,
            averageReadPercent: 50
        )
        XCTAssertEqual(snapshot.readRate, 0.5, accuracy: 0.01)
    }

    func testEngagementSnapshotReadRateZeroPublished() {
        let snapshot = EngagementSnapshot(
            feedURL: feed1, windowStart: daysAgo(14), windowEnd: Date(),
            articlesPublished: 0, articlesRead: 0,
            articlesSkipped: 0, totalReadingTimeSec: 0,
            averageReadPercent: 0
        )
        XCTAssertEqual(snapshot.readRate, 0)
    }

    func testEngagementScore() {
        let snapshot = EngagementSnapshot(
            feedURL: feed1, windowStart: daysAgo(14), windowEnd: Date(),
            articlesPublished: 10, articlesRead: 10,
            articlesSkipped: 0, totalReadingTimeSec: 500,
            averageReadPercent: 100
        )
        // readRate = 1.0, rateComponent = 60, depthComponent = 40
        XCTAssertEqual(snapshot.engagementScore, 100.0, accuracy: 0.1)
    }

    func testLatestEngagement() {
        FeedSubscriptionAnalyzer.shared.recordEngagement(
            feedURL: feed1, articlesPublished: 10, articlesRead: 5,
            windowStart: daysAgo(28), windowEnd: daysAgo(14))
        FeedSubscriptionAnalyzer.shared.recordEngagement(
            feedURL: feed1, articlesPublished: 10, articlesRead: 8,
            windowStart: daysAgo(14), windowEnd: Date())
        let latest = FeedSubscriptionAnalyzer.shared.latestEngagement(for: feed1)
        XCTAssertEqual(latest?.articlesRead, 8)
    }

    func testLatestEngagementNil() {
        let latest = FeedSubscriptionAnalyzer.shared.latestEngagement(for: feed1)
        XCTAssertNil(latest)
    }

    // MARK: - Lifecycle Analysis

    func testSubscriptionDate() {
        FeedSubscriptionAnalyzer.shared.recordEvent(
            feedURL: feed1, feedTitle: "Tech",
            eventType: .subscribe, date: daysAgo(30))
        let subDate = FeedSubscriptionAnalyzer.shared.subscriptionDate(for: feed1)
        XCTAssertNotNil(subDate)
    }

    func testSubscriptionAgeDays() {
        FeedSubscriptionAnalyzer.shared.recordEvent(
            feedURL: feed1, feedTitle: "Tech",
            eventType: .subscribe, date: daysAgo(45))
        let age = FeedSubscriptionAnalyzer.shared.subscriptionAgeDays(for: feed1)
        XCTAssertEqual(age, 45)
    }

    func testIsActiveAfterSubscribe() {
        FeedSubscriptionAnalyzer.shared.recordEvent(
            feedURL: feed1, feedTitle: "Tech", eventType: .subscribe)
        XCTAssertTrue(FeedSubscriptionAnalyzer.shared.isActive(feedURL: feed1))
    }

    func testIsActiveAfterUnsubscribe() {
        FeedSubscriptionAnalyzer.shared.recordEvent(
            feedURL: feed1, feedTitle: "Tech", eventType: .subscribe)
        FeedSubscriptionAnalyzer.shared.recordEvent(
            feedURL: feed1, feedTitle: "Tech", eventType: .unsubscribe)
        XCTAssertFalse(FeedSubscriptionAnalyzer.shared.isActive(feedURL: feed1))
    }

    func testIsActiveAfterPause() {
        FeedSubscriptionAnalyzer.shared.recordEvent(
            feedURL: feed1, feedTitle: "Tech", eventType: .subscribe)
        FeedSubscriptionAnalyzer.shared.recordEvent(
            feedURL: feed1, feedTitle: "Tech", eventType: .pause)
        XCTAssertFalse(FeedSubscriptionAnalyzer.shared.isActive(feedURL: feed1))
    }

    func testIsActiveAfterResume() {
        FeedSubscriptionAnalyzer.shared.recordEvent(
            feedURL: feed1, feedTitle: "Tech", eventType: .subscribe)
        FeedSubscriptionAnalyzer.shared.recordEvent(
            feedURL: feed1, feedTitle: "Tech", eventType: .pause)
        FeedSubscriptionAnalyzer.shared.recordEvent(
            feedURL: feed1, feedTitle: "Tech", eventType: .resume)
        XCTAssertTrue(FeedSubscriptionAnalyzer.shared.isActive(feedURL: feed1))
    }

    func testIsActiveNoEvents() {
        XCTAssertFalse(FeedSubscriptionAnalyzer.shared.isActive(feedURL: feed1))
    }

    func testEngagementTrend() {
        FeedSubscriptionAnalyzer.shared.recordEngagement(
            feedURL: feed1, articlesPublished: 10, articlesRead: 8,
            averageReadPercent: 80,
            windowStart: daysAgo(28), windowEnd: daysAgo(14))
        FeedSubscriptionAnalyzer.shared.recordEngagement(
            feedURL: feed1, articlesPublished: 10, articlesRead: 3,
            averageReadPercent: 30,
            windowStart: daysAgo(14), windowEnd: Date())
        let trend = FeedSubscriptionAnalyzer.shared.engagementTrend(for: feed1)
        XCTAssertTrue(trend < 0, "Trend should be negative when engagement drops")
    }

    func testEngagementTrendPositive() {
        FeedSubscriptionAnalyzer.shared.recordEngagement(
            feedURL: feed1, articlesPublished: 10, articlesRead: 3,
            averageReadPercent: 30,
            windowStart: daysAgo(28), windowEnd: daysAgo(14))
        FeedSubscriptionAnalyzer.shared.recordEngagement(
            feedURL: feed1, articlesPublished: 10, articlesRead: 8,
            averageReadPercent: 80,
            windowStart: daysAgo(14), windowEnd: Date())
        let trend = FeedSubscriptionAnalyzer.shared.engagementTrend(for: feed1)
        XCTAssertTrue(trend > 0, "Trend should be positive when engagement grows")
    }

    func testEngagementTrendSingleSnapshot() {
        FeedSubscriptionAnalyzer.shared.recordEngagement(
            feedURL: feed1, articlesPublished: 10, articlesRead: 5)
        let trend = FeedSubscriptionAnalyzer.shared.engagementTrend(for: feed1)
        XCTAssertEqual(trend, 0)
    }

    // MARK: - Lifecycle Phases

    func testPhaseHoneymoon() {
        FeedSubscriptionAnalyzer.shared.recordEvent(
            feedURL: feed1, feedTitle: "Tech",
            eventType: .subscribe, date: daysAgo(5))
        FeedSubscriptionAnalyzer.shared.recordEngagement(
            feedURL: feed1, articlesPublished: 10, articlesRead: 5)
        let phase = FeedSubscriptionAnalyzer.shared.phase(for: feed1)
        XCTAssertEqual(phase, .honeymoon)
    }

    func testPhaseGrowing() {
        FeedSubscriptionAnalyzer.shared.recordEvent(
            feedURL: feed1, feedTitle: "Tech",
            eventType: .subscribe, date: daysAgo(30))
        FeedSubscriptionAnalyzer.shared.recordEngagement(
            feedURL: feed1, articlesPublished: 10, articlesRead: 5,
            windowStart: daysAgo(7), windowEnd: Date())
        let phase = FeedSubscriptionAnalyzer.shared.phase(for: feed1)
        XCTAssertEqual(phase, .growing)
    }

    func testPhaseEstablished() {
        FeedSubscriptionAnalyzer.shared.recordEvent(
            feedURL: feed1, feedTitle: "Tech",
            eventType: .subscribe, date: daysAgo(100))
        FeedSubscriptionAnalyzer.shared.recordEngagement(
            feedURL: feed1, articlesPublished: 10, articlesRead: 5,
            windowStart: daysAgo(7), windowEnd: Date())
        let phase = FeedSubscriptionAnalyzer.shared.phase(for: feed1)
        XCTAssertEqual(phase, .established)
    }

    func testPhaseMature() {
        FeedSubscriptionAnalyzer.shared.recordEvent(
            feedURL: feed1, feedTitle: "Tech",
            eventType: .subscribe, date: daysAgo(200))
        FeedSubscriptionAnalyzer.shared.recordEngagement(
            feedURL: feed1, articlesPublished: 10, articlesRead: 5,
            windowStart: daysAgo(7), windowEnd: Date())
        let phase = FeedSubscriptionAnalyzer.shared.phase(for: feed1)
        XCTAssertEqual(phase, .mature)
    }

    func testPhasePaused() {
        FeedSubscriptionAnalyzer.shared.recordEvent(
            feedURL: feed1, feedTitle: "Tech", eventType: .subscribe)
        FeedSubscriptionAnalyzer.shared.recordEvent(
            feedURL: feed1, feedTitle: "Tech", eventType: .pause)
        let phase = FeedSubscriptionAnalyzer.shared.phase(for: feed1)
        XCTAssertEqual(phase, .paused)
    }

    func testPhaseDormant() {
        FeedSubscriptionAnalyzer.shared.recordEvent(
            feedURL: feed1, feedTitle: "Tech",
            eventType: .subscribe, date: daysAgo(90))
        // Engagement snapshot with reads, but old
        FeedSubscriptionAnalyzer.shared.recordEngagement(
            feedURL: feed1, articlesPublished: 10, articlesRead: 5,
            windowStart: daysAgo(60), windowEnd: daysAgo(45))
        let phase = FeedSubscriptionAnalyzer.shared.phase(for: feed1)
        XCTAssertEqual(phase, .dormant)
    }

    func testPhaseDeclining() {
        FeedSubscriptionAnalyzer.shared.recordEvent(
            feedURL: feed1, feedTitle: "Tech",
            eventType: .subscribe, date: daysAgo(90))
        // High engagement then sharp drop
        FeedSubscriptionAnalyzer.shared.recordEngagement(
            feedURL: feed1, articlesPublished: 10, articlesRead: 9,
            averageReadPercent: 90,
            windowStart: daysAgo(28), windowEnd: daysAgo(14))
        FeedSubscriptionAnalyzer.shared.recordEngagement(
            feedURL: feed1, articlesPublished: 10, articlesRead: 1,
            averageReadPercent: 10,
            windowStart: daysAgo(14), windowEnd: Date())
        let phase = FeedSubscriptionAnalyzer.shared.phase(for: feed1)
        XCTAssertEqual(phase, .declining)
    }

    // MARK: - Subscription Profile

    func testProfileBasic() {
        FeedSubscriptionAnalyzer.shared.recordEvent(
            feedURL: feed1, feedTitle: "Tech Feed",
            category: "Technology",
            eventType: .subscribe, date: daysAgo(30))
        FeedSubscriptionAnalyzer.shared.recordEngagement(
            feedURL: feed1, articlesPublished: 20, articlesRead: 10,
            averageReadPercent: 60,
            windowStart: daysAgo(14), windowEnd: Date())

        let profile = FeedSubscriptionAnalyzer.shared.profile(for: feed1)
        XCTAssertNotNil(profile)
        XCTAssertEqual(profile?.feedTitle, "Tech Feed")
        XCTAssertEqual(profile?.category, "Technology")
        XCTAssertEqual(profile?.ageDays, 30)
        XCTAssertEqual(profile?.totalArticlesRead, 10)
        XCTAssertTrue(profile?.isActive == true)
    }

    func testProfileNilForUnknownFeed() {
        let profile = FeedSubscriptionAnalyzer.shared.profile(for: "nonexistent")
        XCTAssertNil(profile)
    }

    func testAllProfiles() {
        FeedSubscriptionAnalyzer.shared.recordEvent(
            feedURL: feed1, feedTitle: "A", eventType: .subscribe)
        FeedSubscriptionAnalyzer.shared.recordEvent(
            feedURL: feed2, feedTitle: "B", eventType: .subscribe)
        let profiles = FeedSubscriptionAnalyzer.shared.allProfiles()
        XCTAssertEqual(profiles.count, 2)
    }

    func testROIScore() {
        FeedSubscriptionAnalyzer.shared.recordEvent(
            feedURL: feed1, feedTitle: "Tech",
            eventType: .subscribe, date: daysAgo(30))
        FeedSubscriptionAnalyzer.shared.recordEngagement(
            feedURL: feed1, articlesPublished: 20, articlesRead: 10)
        let profile = FeedSubscriptionAnalyzer.shared.profile(for: feed1)
        // ROI = (10/20) * 100 = 50
        XCTAssertEqual(profile?.roiScore ?? 0, 50.0, accuracy: 0.1)
    }

    // MARK: - Hygiene Report

    func testHygieneReportEmpty() {
        let report = FeedSubscriptionAnalyzer.shared.hygieneReport()
        XCTAssertEqual(report.totalSubscriptions, 0)
        XCTAssertEqual(report.activeSubscriptions, 0)
        XCTAssertTrue(report.suggestions.isEmpty)
    }

    func testHygieneReportHealthyFeed() {
        FeedSubscriptionAnalyzer.shared.recordEvent(
            feedURL: feed1, feedTitle: "Tech",
            category: "Technology",
            eventType: .subscribe, date: daysAgo(30))
        FeedSubscriptionAnalyzer.shared.recordEngagement(
            feedURL: feed1, articlesPublished: 10, articlesRead: 8,
            averageReadPercent: 80,
            windowStart: daysAgo(14), windowEnd: Date())

        let report = FeedSubscriptionAnalyzer.shared.hygieneReport()
        XCTAssertEqual(report.totalSubscriptions, 1)
        XCTAssertFalse(report.healthyFeeds.isEmpty)
    }

    func testHygieneReportUnsubscribeCandidate() {
        FeedSubscriptionAnalyzer.shared.recordEvent(
            feedURL: feed1, feedTitle: "Dead Feed",
            eventType: .subscribe, date: daysAgo(60))
        // Engagement with zero reads, old window
        FeedSubscriptionAnalyzer.shared.recordEngagement(
            feedURL: feed1, articlesPublished: 20, articlesRead: 0,
            windowStart: daysAgo(45), windowEnd: daysAgo(31))

        let report = FeedSubscriptionAnalyzer.shared.hygieneReport()
        XCTAssertFalse(report.unsubscribeCandidates.isEmpty)
    }

    func testHygieneReportReengageCandidate() {
        FeedSubscriptionAnalyzer.shared.recordEvent(
            feedURL: feed1, feedTitle: "Once Great",
            eventType: .subscribe, date: daysAgo(90))
        // Was engaging, now dormant
        FeedSubscriptionAnalyzer.shared.recordEngagement(
            feedURL: feed1, articlesPublished: 10, articlesRead: 8,
            averageReadPercent: 80,
            windowStart: daysAgo(60), windowEnd: daysAgo(45))

        let report = FeedSubscriptionAnalyzer.shared.hygieneReport()
        XCTAssertFalse(report.reengageCandidates.isEmpty)
    }

    func testHygieneReportSuggestionsSorted() {
        // Add a healthy feed and a dormant feed
        FeedSubscriptionAnalyzer.shared.recordEvent(
            feedURL: feed1, feedTitle: "Healthy",
            eventType: .subscribe, date: daysAgo(30))
        FeedSubscriptionAnalyzer.shared.recordEngagement(
            feedURL: feed1, articlesPublished: 10, articlesRead: 8,
            averageReadPercent: 80,
            windowStart: daysAgo(14), windowEnd: Date())

        FeedSubscriptionAnalyzer.shared.recordEvent(
            feedURL: feed2, feedTitle: "Dormant",
            eventType: .subscribe, date: daysAgo(90))
        FeedSubscriptionAnalyzer.shared.recordEngagement(
            feedURL: feed2, articlesPublished: 10, articlesRead: 0,
            windowStart: daysAgo(60), windowEnd: daysAgo(35))

        let report = FeedSubscriptionAnalyzer.shared.hygieneReport()
        // Higher urgency should come first
        if report.suggestions.count >= 2 {
            XCTAssertTrue(report.suggestions[0].urgency >= report.suggestions[1].urgency)
        }
    }

    // MARK: - Portfolio Balance

    func testPortfolioBalanceEmpty() {
        let balance = FeedSubscriptionAnalyzer.shared.portfolioBalance()
        XCTAssertEqual(balance.totalActive, 0)
        XCTAssertEqual(balance.diversityScore, 0)
    }

    func testPortfolioBalanceSingleCategory() {
        FeedSubscriptionAnalyzer.shared.recordEvent(
            feedURL: feed1, feedTitle: "A", category: "Tech", eventType: .subscribe)
        FeedSubscriptionAnalyzer.shared.recordEvent(
            feedURL: feed2, feedTitle: "B", category: "Tech", eventType: .subscribe)
        let balance = FeedSubscriptionAnalyzer.shared.portfolioBalance()
        XCTAssertEqual(balance.totalActive, 2)
        XCTAssertEqual(balance.diversityScore, 0)
        XCTAssertTrue(balance.recommendation.contains("diversify"))
    }

    func testPortfolioBalanceDiverse() {
        FeedSubscriptionAnalyzer.shared.recordEvent(
            feedURL: feed1, feedTitle: "A", category: "Tech", eventType: .subscribe)
        FeedSubscriptionAnalyzer.shared.recordEvent(
            feedURL: feed2, feedTitle: "B", category: "Science", eventType: .subscribe)
        FeedSubscriptionAnalyzer.shared.recordEvent(
            feedURL: feed3, feedTitle: "C", category: "News", eventType: .subscribe)
        let balance = FeedSubscriptionAnalyzer.shared.portfolioBalance()
        XCTAssertEqual(balance.totalActive, 3)
        XCTAssertTrue(balance.diversityScore > 50)
    }

    func testPortfolioBalanceDominantCategory() {
        FeedSubscriptionAnalyzer.shared.recordEvent(
            feedURL: feed1, feedTitle: "A", category: "Tech", eventType: .subscribe)
        FeedSubscriptionAnalyzer.shared.recordEvent(
            feedURL: feed2, feedTitle: "B", category: "Tech", eventType: .subscribe)
        FeedSubscriptionAnalyzer.shared.recordEvent(
            feedURL: feed3, feedTitle: "C", category: "Tech", eventType: .subscribe)
        let balance = FeedSubscriptionAnalyzer.shared.portfolioBalance()
        XCTAssertEqual(balance.dominantCategory, "Tech")
    }

    func testPortfolioUncategorized() {
        FeedSubscriptionAnalyzer.shared.recordEvent(
            feedURL: feed1, feedTitle: "A", category: nil, eventType: .subscribe)
        let balance = FeedSubscriptionAnalyzer.shared.portfolioBalance()
        XCTAssertEqual(balance.categoryBreakdown[0].category, "Uncategorized")
    }

    // MARK: - Convenience Queries

    func testFeedsByROI() {
        FeedSubscriptionAnalyzer.shared.recordEvent(
            feedURL: feed1, feedTitle: "Low ROI", eventType: .subscribe)
        FeedSubscriptionAnalyzer.shared.recordEngagement(
            feedURL: feed1, articlesPublished: 20, articlesRead: 2)

        FeedSubscriptionAnalyzer.shared.recordEvent(
            feedURL: feed2, feedTitle: "High ROI", eventType: .subscribe)
        FeedSubscriptionAnalyzer.shared.recordEngagement(
            feedURL: feed2, articlesPublished: 10, articlesRead: 9)

        let sorted = FeedSubscriptionAnalyzer.shared.feedsByROI()
        XCTAssertEqual(sorted.count, 2)
        XCTAssertTrue(sorted[0].roiScore > sorted[1].roiScore)
    }

    func testNeverReadFeeds() {
        FeedSubscriptionAnalyzer.shared.recordEvent(
            feedURL: feed1, feedTitle: "Read", eventType: .subscribe)
        FeedSubscriptionAnalyzer.shared.recordEngagement(
            feedURL: feed1, articlesPublished: 10, articlesRead: 5)

        FeedSubscriptionAnalyzer.shared.recordEvent(
            feedURL: feed2, feedTitle: "Never Read", eventType: .subscribe)
        FeedSubscriptionAnalyzer.shared.recordEngagement(
            feedURL: feed2, articlesPublished: 10, articlesRead: 0)

        let neverRead = FeedSubscriptionAnalyzer.shared.neverReadFeeds()
        XCTAssertEqual(neverRead.count, 1)
        XCTAssertEqual(neverRead[0].feedTitle, "Never Read")
    }

    func testRecentSubscriptions() {
        FeedSubscriptionAnalyzer.shared.recordEvent(
            feedURL: feed1, feedTitle: "Old",
            eventType: .subscribe, date: daysAgo(30))
        FeedSubscriptionAnalyzer.shared.recordEvent(
            feedURL: feed2, feedTitle: "New",
            eventType: .subscribe, date: daysAgo(2))
        let recent = FeedSubscriptionAnalyzer.shared.recentSubscriptions(withinDays: 7)
        XCTAssertEqual(recent.count, 1)
        XCTAssertEqual(recent[0].feedTitle, "New")
    }

    func testAverageSubscriptionAge() {
        FeedSubscriptionAnalyzer.shared.recordEvent(
            feedURL: feed1, feedTitle: "A",
            eventType: .subscribe, date: daysAgo(30))
        FeedSubscriptionAnalyzer.shared.recordEvent(
            feedURL: feed2, feedTitle: "B",
            eventType: .subscribe, date: daysAgo(60))
        let avgAge = FeedSubscriptionAnalyzer.shared.averageSubscriptionAge()
        XCTAssertEqual(avgAge, 45.0, accuracy: 1.0)
    }

    func testChurnRate() {
        FeedSubscriptionAnalyzer.shared.recordEvent(
            feedURL: feed1, feedTitle: "A", eventType: .subscribe)
        FeedSubscriptionAnalyzer.shared.recordEvent(
            feedURL: feed2, feedTitle: "B", eventType: .subscribe)
        FeedSubscriptionAnalyzer.shared.recordEvent(
            feedURL: feed1, feedTitle: "A", eventType: .unsubscribe)
        let churn = FeedSubscriptionAnalyzer.shared.churnRate()
        XCTAssertEqual(churn, 0.5, accuracy: 0.01)
    }

    func testChurnRateNoSubscriptions() {
        let churn = FeedSubscriptionAnalyzer.shared.churnRate()
        XCTAssertEqual(churn, 0)
    }

    // MARK: - Export

    func testExportTimeline() {
        FeedSubscriptionAnalyzer.shared.recordEvent(
            feedURL: feed1, feedTitle: "Tech", eventType: .subscribe)
        FeedSubscriptionAnalyzer.shared.recordEngagement(
            feedURL: feed1, articlesPublished: 10, articlesRead: 5)
        let jsonData = FeedSubscriptionAnalyzer.shared.exportTimeline()
        XCTAssertNotNil(jsonData)
        let json = String(data: jsonData!, encoding: .utf8)!
        XCTAssertTrue(json.contains("tech"))
    }

    // MARK: - Data Management

    func testClearFeed() {
        FeedSubscriptionAnalyzer.shared.recordEvent(
            feedURL: feed1, feedTitle: "A", eventType: .subscribe)
        FeedSubscriptionAnalyzer.shared.recordEvent(
            feedURL: feed2, feedTitle: "B", eventType: .subscribe)
        FeedSubscriptionAnalyzer.shared.recordEngagement(
            feedURL: feed1, articlesPublished: 10, articlesRead: 5)
        FeedSubscriptionAnalyzer.shared.clearFeed(feed1)
        XCTAssertTrue(FeedSubscriptionAnalyzer.shared.events(for: feed1).isEmpty)
        XCTAssertTrue(FeedSubscriptionAnalyzer.shared.engagementHistory(for: feed1).isEmpty)
        XCTAssertEqual(FeedSubscriptionAnalyzer.shared.events(for: feed2).count, 1)
    }

    func testClearAll() {
        FeedSubscriptionAnalyzer.shared.recordEvent(
            feedURL: feed1, feedTitle: "A", eventType: .subscribe)
        FeedSubscriptionAnalyzer.shared.recordEngagement(
            feedURL: feed1, articlesPublished: 10, articlesRead: 5)
        FeedSubscriptionAnalyzer.shared.clearAll()
        XCTAssertEqual(FeedSubscriptionAnalyzer.shared.totalEventCount(), 0)
        XCTAssertEqual(FeedSubscriptionAnalyzer.shared.totalSnapshotCount(), 0)
    }

    func testTotalEventCount() {
        FeedSubscriptionAnalyzer.shared.recordEvent(
            feedURL: feed1, feedTitle: "A", eventType: .subscribe)
        FeedSubscriptionAnalyzer.shared.recordEvent(
            feedURL: feed2, feedTitle: "B", eventType: .subscribe)
        XCTAssertEqual(FeedSubscriptionAnalyzer.shared.totalEventCount(), 2)
    }

    func testTotalSnapshotCount() {
        FeedSubscriptionAnalyzer.shared.recordEngagement(
            feedURL: feed1, articlesPublished: 10, articlesRead: 5)
        FeedSubscriptionAnalyzer.shared.recordEngagement(
            feedURL: feed2, articlesPublished: 10, articlesRead: 3)
        XCTAssertEqual(FeedSubscriptionAnalyzer.shared.totalSnapshotCount(), 2)
    }

    // MARK: - All Tracked Feed URLs

    func testAllTrackedFeedURLs() {
        FeedSubscriptionAnalyzer.shared.recordEvent(
            feedURL: feed1, feedTitle: "A", eventType: .subscribe)
        FeedSubscriptionAnalyzer.shared.recordEngagement(
            feedURL: feed2, articlesPublished: 10, articlesRead: 5)
        let urls = FeedSubscriptionAnalyzer.shared.allTrackedFeedURLs()
        XCTAssertEqual(urls.count, 2)
        XCTAssertTrue(urls.contains(feed1))
        XCTAssertTrue(urls.contains(feed2))
    }

    // MARK: - Edge Cases

    func testMultipleSubscribeEvents() {
        // Subscribe, unsub, re-subscribe
        FeedSubscriptionAnalyzer.shared.recordEvent(
            feedURL: feed1, feedTitle: "A",
            eventType: .subscribe, date: daysAgo(60))
        FeedSubscriptionAnalyzer.shared.recordEvent(
            feedURL: feed1, feedTitle: "A",
            eventType: .unsubscribe, date: daysAgo(30))
        FeedSubscriptionAnalyzer.shared.recordEvent(
            feedURL: feed1, feedTitle: "A",
            eventType: .subscribe, date: daysAgo(5))
        XCTAssertTrue(FeedSubscriptionAnalyzer.shared.isActive(feedURL: feed1))
        // Subscription date should be the first subscribe
        let subDate = FeedSubscriptionAnalyzer.shared.subscriptionDate(for: feed1)
        XCTAssertNotNil(subDate)
    }

    func testNotificationPosted() {
        let expectation = expectation(
            forNotification: .subscriptionDidChange, object: nil, handler: nil)
        FeedSubscriptionAnalyzer.shared.recordEvent(
            feedURL: feed1, feedTitle: "A", eventType: .subscribe)
        wait(for: [expectation], timeout: 1.0)
    }

    // MARK: - Model Properties

    func testSubscriptionPhaseEmojis() {
        for phase in SubscriptionPhase.allCases {
            XCTAssertFalse(phase.emoji.isEmpty)
            XCTAssertFalse(phase.label.isEmpty)
        }
    }

    func testSubscriptionEventTypeAllCases() {
        XCTAssertEqual(SubscriptionEventType.allCases.count, 4)
    }

    func testHygieneActionProperties() {
        for action in HygieneAction.allCases {
            XCTAssertFalse(action.label.isEmpty)
            XCTAssertFalse(action.emoji.isEmpty)
        }
    }

    func testHygieneUrgencyComparable() {
        XCTAssertTrue(HygieneUrgency.low < HygieneUrgency.medium)
        XCTAssertTrue(HygieneUrgency.medium < HygieneUrgency.high)
    }

    func testOverallHealthScore() {
        FeedSubscriptionAnalyzer.shared.recordEvent(
            feedURL: feed1, feedTitle: "A", category: "Tech", eventType: .subscribe)
        FeedSubscriptionAnalyzer.shared.recordEngagement(
            feedURL: feed1, articlesPublished: 10, articlesRead: 8,
            averageReadPercent: 80,
            windowStart: daysAgo(14), windowEnd: Date())
        let report = FeedSubscriptionAnalyzer.shared.hygieneReport()
        XCTAssertTrue(report.overallHealthScore > 0)
        XCTAssertTrue(report.overallHealthScore <= 100)
    }
}
