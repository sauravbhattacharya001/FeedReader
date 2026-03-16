//
//  FeedCostTrackerTests.swift
//  FeedReaderTests
//

import XCTest
@testable import FeedReader

class FeedCostTrackerTests: XCTestCase {

    var tracker: FeedCostTracker!
    var tempDir: URL!

    override func setUp() {
        super.setUp()
        tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        tracker = FeedCostTracker(directory: tempDir)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: tempDir)
        super.tearDown()
    }

    // MARK: - Subscription CRUD

    func testAddSubscription() {
        let sub = tracker.addSubscription(feedIdentifier: "tech-blog", name: "Tech Weekly",
                                          amount: 9.99, cycle: .monthly, category: "Tech")
        XCTAssertEqual(tracker.subscriptions.count, 1)
        XCTAssertEqual(sub.name, "Tech Weekly")
        XCTAssertEqual(sub.amount, 9.99)
        XCTAssertEqual(sub.cycle, .monthly)
        XCTAssertTrue(sub.isActive)
    }

    func testAddMultipleSubscriptions() {
        tracker.addSubscription(feedIdentifier: "f1", name: "Feed 1", amount: 5.0, cycle: .monthly)
        tracker.addSubscription(feedIdentifier: "f2", name: "Feed 2", amount: 50.0, cycle: .yearly)
        tracker.addSubscription(feedIdentifier: "f3", name: "Feed 3", amount: 2.0, cycle: .weekly)
        XCTAssertEqual(tracker.subscriptions.count, 3)
    }

    func testRemoveSubscription() {
        let sub = tracker.addSubscription(feedIdentifier: "f1", name: "Feed 1", amount: 5.0, cycle: .monthly)
        XCTAssertTrue(tracker.removeSubscription(id: sub.id))
        XCTAssertEqual(tracker.subscriptions.count, 0)
    }

    func testRemoveNonexistent() {
        XCTAssertFalse(tracker.removeSubscription(id: "nonexistent"))
    }

    func testCancelSubscription() {
        let sub = tracker.addSubscription(feedIdentifier: "f1", name: "Feed 1", amount: 10.0, cycle: .monthly)
        XCTAssertTrue(tracker.cancelSubscription(id: sub.id))
        XCTAssertEqual(tracker.activeSubscriptions.count, 0)
        XCTAssertEqual(tracker.subscriptions.count, 1) // still in history
        XCTAssertFalse(tracker.subscriptions[0].isActive)
    }

    func testReactivateSubscription() {
        let sub = tracker.addSubscription(feedIdentifier: "f1", name: "Feed 1", amount: 10.0, cycle: .monthly)
        tracker.cancelSubscription(id: sub.id)
        XCTAssertTrue(tracker.reactivateSubscription(id: sub.id))
        XCTAssertEqual(tracker.activeSubscriptions.count, 1)
        XCTAssertTrue(tracker.subscriptions[0].isActive)
        XCTAssertNotNil(tracker.subscriptions[0].nextRenewalDate)
    }

    func testCancelNonexistent() {
        XCTAssertFalse(tracker.cancelSubscription(id: "nope"))
    }

    func testReactivateNonexistent() {
        XCTAssertFalse(tracker.reactivateSubscription(id: "nope"))
    }

    // MARK: - Cost Calculations

    func testMonthlyCostNormalization() {
        let monthly = tracker.addSubscription(feedIdentifier: "m", name: "Monthly", amount: 10.0, cycle: .monthly)
        XCTAssertEqual(monthly.monthlyCost, 10.0, accuracy: 0.01)

        let yearly = tracker.addSubscription(feedIdentifier: "y", name: "Yearly", amount: 120.0, cycle: .yearly)
        XCTAssertEqual(yearly.monthlyCost, 10.0, accuracy: 0.01)

        let weekly = tracker.addSubscription(feedIdentifier: "w", name: "Weekly", amount: 2.0, cycle: .weekly)
        XCTAssertEqual(weekly.monthlyCost, 8.66, accuracy: 0.01)

        let oneTime = tracker.addSubscription(feedIdentifier: "o", name: "OneTime", amount: 50.0, cycle: .oneTime)
        XCTAssertEqual(oneTime.monthlyCost, 0.0)
    }

    func testYearlyCostNormalization() {
        let yearly = tracker.addSubscription(feedIdentifier: "y", name: "Yearly", amount: 99.0, cycle: .yearly)
        XCTAssertEqual(yearly.yearlyCost, 99.0)

        let monthly = tracker.addSubscription(feedIdentifier: "m", name: "Monthly", amount: 10.0, cycle: .monthly)
        XCTAssertEqual(monthly.yearlyCost, 120.0)
    }

    func testCurrentMonthlySpending() {
        tracker.addSubscription(feedIdentifier: "f1", name: "A", amount: 10.0, cycle: .monthly)
        tracker.addSubscription(feedIdentifier: "f2", name: "B", amount: 120.0, cycle: .yearly)
        // 10 + 10 = 20
        XCTAssertEqual(tracker.currentMonthlySpending, 20.0, accuracy: 0.01)
    }

    func testYearlyProjection() {
        tracker.addSubscription(feedIdentifier: "f1", name: "A", amount: 10.0, cycle: .monthly)
        XCTAssertEqual(tracker.yearlyProjection(), 120.0, accuracy: 0.01)
    }

    // MARK: - Budget

    func testBudgetDefaults() {
        XCTAssertEqual(tracker.budget.monthlyLimit, 50.0)
        XCTAssertEqual(tracker.budget.warningThreshold, 0.8)
    }

    func testBudgetUsage() {
        tracker.budget = CostBudget(monthlyLimit: 100.0)
        tracker.addSubscription(feedIdentifier: "f1", name: "A", amount: 60.0, cycle: .monthly)
        XCTAssertEqual(tracker.budgetUsagePercent, 0.6, accuracy: 0.01)
        XCTAssertEqual(tracker.budgetRemaining, 40.0, accuracy: 0.01)
    }

    func testBudgetOverspend() {
        tracker.budget = CostBudget(monthlyLimit: 10.0)
        tracker.addSubscription(feedIdentifier: "f1", name: "A", amount: 15.0, cycle: .monthly)
        XCTAssertGreaterThan(tracker.budgetUsagePercent, 1.0)
        XCTAssertLessThan(tracker.budgetRemaining, 0)
    }

    func testBudgetWarningNotification() {
        let expectation = XCTestExpectation(description: "Budget warning posted")
        let observer = NotificationCenter.default.addObserver(
            forName: .feedCostBudgetWarning, object: nil, queue: nil
        ) { _ in expectation.fulfill() }
        tracker.budget = CostBudget(monthlyLimit: 10.0, warningThreshold: 0.5)
        tracker.addSubscription(feedIdentifier: "f1", name: "A", amount: 8.0, cycle: .monthly)
        wait(for: [expectation], timeout: 1.0)
        NotificationCenter.default.removeObserver(observer)
    }

    // MARK: - Engagement & ROI

    func testRecordEngagement() {
        tracker.recordEngagement(feedIdentifier: "f1", articlesRead: 5, minutesSpent: 30.0)
        let eng = tracker.engagement(for: "f1")
        XCTAssertNotNil(eng)
        XCTAssertEqual(eng?.articlesRead, 5)
        XCTAssertEqual(eng?.totalMinutesSpent, 30.0)
    }

    func testEngagementAccumulates() {
        tracker.recordEngagement(feedIdentifier: "f1", articlesRead: 3, minutesSpent: 15.0)
        tracker.recordEngagement(feedIdentifier: "f1", articlesRead: 2, minutesSpent: 10.0)
        let eng = tracker.engagement(for: "f1")
        XCTAssertEqual(eng?.articlesRead, 5)
        XCTAssertEqual(eng?.totalMinutesSpent, 25.0)
    }

    func testROICalculation() {
        tracker.addSubscription(feedIdentifier: "f1", name: "Good Feed", amount: 5.0, cycle: .monthly)
        tracker.recordEngagement(feedIdentifier: "f1", articlesRead: 20, minutesSpent: 120.0)
        let roi = tracker.calculateROI()
        XCTAssertEqual(roi.count, 1)
        XCTAssertEqual(roi[0].costPerArticle, 0.25, accuracy: 0.01)
        XCTAssertGreaterThan(roi[0].roiScore, 0)
    }

    func testROINoEngagement() {
        tracker.addSubscription(feedIdentifier: "f1", name: "Unread Feed", amount: 10.0, cycle: .monthly)
        let roi = tracker.calculateROI()
        XCTAssertEqual(roi.count, 1)
        XCTAssertEqual(roi[0].roiScore, 0)
        XCTAssertEqual(roi[0].verdict, "Consider cancelling")
    }

    func testBestAndWorstValue() {
        tracker.addSubscription(feedIdentifier: "f1", name: "Best", amount: 2.0, cycle: .monthly)
        tracker.addSubscription(feedIdentifier: "f2", name: "Worst", amount: 20.0, cycle: .monthly)
        tracker.recordEngagement(feedIdentifier: "f1", articlesRead: 50, minutesSpent: 200.0)
        tracker.recordEngagement(feedIdentifier: "f2", articlesRead: 1, minutesSpent: 2.0)

        XCTAssertEqual(tracker.bestValue()?.name, "Best")
        XCTAssertEqual(tracker.worstValue()?.name, "Worst")
    }

    // MARK: - Spending

    func testSpendingByCategory() {
        tracker.addSubscription(feedIdentifier: "f1", name: "A", amount: 10.0, cycle: .monthly, category: "Tech")
        tracker.addSubscription(feedIdentifier: "f2", name: "B", amount: 5.0, cycle: .monthly, category: "News")
        tracker.addSubscription(feedIdentifier: "f3", name: "C", amount: 8.0, cycle: .monthly, category: "Tech")
        let cats = tracker.spendingByCategory()
        XCTAssertEqual(cats["Tech"], 18.0, accuracy: 0.01)
        XCTAssertEqual(cats["News"], 5.0, accuracy: 0.01)
    }

    func testMonthlySummary() {
        tracker.addSubscription(feedIdentifier: "f1", name: "A", amount: 10.0, cycle: .monthly, category: "Tech")
        let summary = tracker.monthlySummary()
        XCTAssertEqual(summary.activeSubscriptions, 1)
        XCTAssertEqual(summary.totalSpending, 10.0, accuracy: 0.01)
    }

    // MARK: - Renewals

    func testUpcomingRenewals() {
        tracker.addSubscription(feedIdentifier: "f1", name: "Soon", amount: 10.0, cycle: .weekly)
        let renewals = tracker.upcomingRenewals(withinDays: 14)
        XCTAssertEqual(renewals.count, 1)
    }

    func testNoRenewalsForOneTime() {
        tracker.addSubscription(feedIdentifier: "f1", name: "One-time", amount: 50.0, cycle: .oneTime)
        let renewals = tracker.upcomingRenewals(withinDays: 365)
        XCTAssertEqual(renewals.count, 0)
    }

    // MARK: - Currency

    func testCurrencySymbol() {
        XCTAssertEqual(tracker.currencySymbol, "$")
        tracker.currencySymbol = "€"
        XCTAssertEqual(tracker.currencySymbol, "€")
    }

    // MARK: - Export

    func testExportJSON() {
        tracker.addSubscription(feedIdentifier: "f1", name: "Test", amount: 5.0, cycle: .monthly)
        let json = tracker.exportJSON()
        XCTAssertNotNil(json)
        XCTAssertTrue(json!.contains("Test"))
    }

    func testSpendingReport() {
        tracker.addSubscription(feedIdentifier: "f1", name: "A", amount: 10.0, cycle: .monthly)
        let report = tracker.spendingReport()
        XCTAssertEqual(report["activeSubscriptions"] as? Int, 1)
        XCTAssertEqual(report["monthlySpending"] as? Double, 10.0)
    }

    // MARK: - Persistence

    func testPersistence() {
        tracker.addSubscription(feedIdentifier: "f1", name: "Persist", amount: 7.0, cycle: .monthly)
        tracker.recordEngagement(feedIdentifier: "f1", articlesRead: 10, minutesSpent: 50.0)
        // Reload
        let tracker2 = FeedCostTracker(directory: tempDir)
        XCTAssertEqual(tracker2.subscriptions.count, 1)
        XCTAssertEqual(tracker2.subscriptions[0].name, "Persist")
        XCTAssertEqual(tracker2.engagement(for: "f1")?.articlesRead, 10)
    }

    // MARK: - Reset

    func testReset() {
        tracker.addSubscription(feedIdentifier: "f1", name: "A", amount: 10.0, cycle: .monthly)
        tracker.recordEngagement(feedIdentifier: "f1", articlesRead: 5, minutesSpent: 20.0)
        tracker.reset()
        XCTAssertEqual(tracker.subscriptions.count, 0)
        XCTAssertNil(tracker.engagement(for: "f1"))
    }

    // MARK: - Edge Cases

    func testNegativeAmountClampedToZero() {
        let sub = tracker.addSubscription(feedIdentifier: "f1", name: "Free?", amount: -5.0, cycle: .monthly)
        XCTAssertEqual(sub.amount, 0.0)
    }

    func testBillingCycleLabels() {
        XCTAssertEqual(BillingCycle.monthly.label, "Monthly")
        XCTAssertEqual(BillingCycle.yearly.label, "Yearly")
        XCTAssertEqual(BillingCycle.oneTime.label, "One-time")
        XCTAssertEqual(BillingCycle.weekly.label, "Weekly")
    }

    func testBillingCycleMonthsPerCycle() {
        XCTAssertEqual(BillingCycle.monthly.monthsPerCycle, 1.0)
        XCTAssertEqual(BillingCycle.yearly.monthsPerCycle, 12.0)
        XCTAssertEqual(BillingCycle.oneTime.monthsPerCycle, 0.0)
    }

    func testZeroBudgetLimit() {
        tracker.budget = CostBudget(monthlyLimit: 0)
        XCTAssertEqual(tracker.budgetUsagePercent, 0)
    }

    func testCancelledSubsNotInSpending() {
        let sub = tracker.addSubscription(feedIdentifier: "f1", name: "A", amount: 10.0, cycle: .monthly)
        tracker.cancelSubscription(id: sub.id)
        XCTAssertEqual(tracker.currentMonthlySpending, 0.0)
    }
}
