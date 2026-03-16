//
//  FeedCostTracker.swift
//  FeedReader
//
//  Tracks monetary costs of paid feed/newsletter subscriptions, calculates
//  cost-per-article and ROI based on reading engagement, manages budgets,
//  and surfaces spending insights.
//
//  Key features:
//  - Record subscription costs (monthly/yearly/one-time)
//  - Track cost-per-article-read for each paid feed
//  - Monthly/yearly spending summaries with category breakdowns
//  - Budget setting with alerts when approaching limits
//  - ROI scoring: engagement value vs cost
//  - Renewal tracking with upcoming payment alerts
//  - Cost comparison across feeds (best/worst value)
//  - Currency support with configurable symbol
//  - Export spending reports as JSON
//
//  Persistence: JSON file in Documents directory.
//

import Foundation

// MARK: - Notifications

extension Notification.Name {
    /// Posted when subscription cost data changes.
    static let feedCostDidChange = Notification.Name("FeedCostDidChangeNotification")
    /// Posted when spending approaches or exceeds budget.
    static let feedCostBudgetWarning = Notification.Name("FeedCostBudgetWarningNotification")
}

// MARK: - Models

/// Billing cycle for a paid subscription.
enum BillingCycle: String, Codable, CaseIterable {
    case monthly
    case yearly
    case oneTime = "one_time"
    case weekly

    /// Human-readable label.
    var label: String {
        switch self {
        case .monthly: return "Monthly"
        case .yearly: return "Yearly"
        case .oneTime: return "One-time"
        case .weekly: return "Weekly"
        }
    }

    /// Approximate number of months per cycle (for normalization).
    var monthsPerCycle: Double {
        switch self {
        case .weekly: return 1.0 / 4.33
        case .monthly: return 1.0
        case .yearly: return 12.0
        case .oneTime: return 0.0 // not recurring
        }
    }
}

/// A paid feed/newsletter subscription record.
struct FeedSubscriptionCost: Codable, Equatable {
    let id: String
    /// Feed URL or name this cost is associated with.
    var feedIdentifier: String
    /// Display name for the subscription.
    var name: String
    /// Cost per billing cycle in user's currency.
    var amount: Double
    /// Billing cycle.
    var cycle: BillingCycle
    /// Category (e.g., "Tech", "News", "Finance").
    var category: String
    /// Date the subscription started.
    var startDate: Date
    /// Next renewal date (nil for one-time).
    var nextRenewalDate: Date?
    /// Whether the subscription is currently active.
    var isActive: Bool
    /// Optional notes.
    var notes: String?

    /// Normalized monthly cost.
    var monthlyCost: Double {
        switch cycle {
        case .weekly: return amount * 4.33
        case .monthly: return amount
        case .yearly: return amount / 12.0
        case .oneTime: return 0.0
        }
    }

    /// Normalized yearly cost.
    var yearlyCost: Double {
        switch cycle {
        case .weekly: return amount * 52.0
        case .monthly: return amount * 12.0
        case .yearly: return amount
        case .oneTime: return 0.0
        }
    }
}

/// Reading engagement record for cost analysis.
struct FeedReadingEngagement: Codable, Equatable {
    var feedIdentifier: String
    var articlesRead: Int
    var totalMinutesSpent: Double
    var lastReadDate: Date?
}

/// Budget configuration.
struct CostBudget: Codable, Equatable {
    /// Monthly spending limit.
    var monthlyLimit: Double
    /// Warning threshold (0.0-1.0, e.g., 0.8 = warn at 80%).
    var warningThreshold: Double

    init(monthlyLimit: Double = 50.0, warningThreshold: Double = 0.8) {
        self.monthlyLimit = monthlyLimit
        self.warningThreshold = max(0.0, min(1.0, warningThreshold))
    }
}

/// ROI analysis result for a single feed.
struct FeedROIResult: Codable, Equatable {
    var feedIdentifier: String
    var name: String
    var monthlyCost: Double
    var articlesRead: Int
    var minutesSpent: Double
    var costPerArticle: Double
    var costPerMinute: Double
    /// Score from 0-100 (higher = better value).
    var roiScore: Int
    var verdict: String
}

/// Monthly spending summary.
struct MonthlySpendingSummary: Codable, Equatable {
    var year: Int
    var month: Int
    var totalSpending: Double
    var activeSubscriptions: Int
    var categoryBreakdown: [String: Double]
    var budgetUsagePercent: Double?
}

/// Persistent data container.
struct FeedCostData: Codable {
    var subscriptions: [FeedSubscriptionCost]
    var engagements: [FeedReadingEngagement]
    var budget: CostBudget
    var currencySymbol: String

    init() {
        subscriptions = []
        engagements = []
        budget = CostBudget()
        currencySymbol = "$"
    }
}

// MARK: - FeedCostTracker

/// Manages paid feed subscription costs, budgets, and ROI analysis.
final class FeedCostTracker {

    // MARK: - Storage

    private let fileName = "FeedCostData.json"
    private var data: FeedCostData
    private let fileURL: URL

    // MARK: - Init

    init(directory: URL? = nil) {
        let dir = directory ?? FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        self.fileURL = dir.appendingPathComponent(fileName)
        if let loaded = FeedCostTracker.load(from: self.fileURL) {
            self.data = loaded
        } else {
            self.data = FeedCostData()
        }
    }

    // MARK: - Persistence

    private static func load(from url: URL) -> FeedCostData? {
        guard let jsonData = try? Data(contentsOf: url) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(FeedCostData.self, from: jsonData)
    }

    @discardableResult
    private func save() -> Bool {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = .prettyPrinted
        guard let jsonData = try? encoder.encode(data) else { return false }
        do {
            try jsonData.write(to: fileURL, options: .atomic)
            return true
        } catch {
            return false
        }
    }

    // MARK: - Currency

    /// Get or set the currency symbol.
    var currencySymbol: String {
        get { data.currencySymbol }
        set {
            data.currencySymbol = newValue
            save()
        }
    }

    // MARK: - Subscription Management

    /// All subscriptions.
    var subscriptions: [FeedSubscriptionCost] { data.subscriptions }

    /// Active subscriptions only.
    var activeSubscriptions: [FeedSubscriptionCost] {
        data.subscriptions.filter { $0.isActive }
    }

    /// Add a new paid subscription.
    @discardableResult
    func addSubscription(feedIdentifier: String, name: String, amount: Double,
                         cycle: BillingCycle, category: String = "General",
                         startDate: Date = Date(), notes: String? = nil) -> FeedSubscriptionCost {
        let sub = FeedSubscriptionCost(
            id: UUID().uuidString,
            feedIdentifier: feedIdentifier,
            name: name,
            amount: max(0, amount),
            cycle: cycle,
            category: category,
            startDate: startDate,
            nextRenewalDate: Self.computeNextRenewal(from: startDate, cycle: cycle),
            isActive: true,
            notes: notes
        )
        data.subscriptions.append(sub)
        save()
        NotificationCenter.default.post(name: .feedCostDidChange, object: self)
        checkBudgetWarning()
        return sub
    }

    /// Remove a subscription by ID.
    @discardableResult
    func removeSubscription(id: String) -> Bool {
        let before = data.subscriptions.count
        data.subscriptions.removeAll { $0.id == id }
        if data.subscriptions.count < before {
            save()
            NotificationCenter.default.post(name: .feedCostDidChange, object: self)
            return true
        }
        return false
    }

    /// Deactivate (cancel) a subscription without removing history.
    @discardableResult
    func cancelSubscription(id: String) -> Bool {
        guard let idx = data.subscriptions.firstIndex(where: { $0.id == id }) else { return false }
        data.subscriptions[idx].isActive = false
        data.subscriptions[idx].nextRenewalDate = nil
        save()
        NotificationCenter.default.post(name: .feedCostDidChange, object: self)
        return true
    }

    /// Reactivate a cancelled subscription.
    @discardableResult
    func reactivateSubscription(id: String) -> Bool {
        guard let idx = data.subscriptions.firstIndex(where: { $0.id == id }) else { return false }
        data.subscriptions[idx].isActive = true
        data.subscriptions[idx].nextRenewalDate = Self.computeNextRenewal(
            from: Date(), cycle: data.subscriptions[idx].cycle
        )
        save()
        NotificationCenter.default.post(name: .feedCostDidChange, object: self)
        checkBudgetWarning()
        return true
    }

    // MARK: - Engagement Tracking

    /// Record reading engagement for a feed.
    func recordEngagement(feedIdentifier: String, articlesRead: Int = 1, minutesSpent: Double = 0) {
        if let idx = data.engagements.firstIndex(where: { $0.feedIdentifier == feedIdentifier }) {
            data.engagements[idx].articlesRead += max(0, articlesRead)
            data.engagements[idx].totalMinutesSpent += max(0, minutesSpent)
            data.engagements[idx].lastReadDate = Date()
        } else {
            let engagement = FeedReadingEngagement(
                feedIdentifier: feedIdentifier,
                articlesRead: max(0, articlesRead),
                totalMinutesSpent: max(0, minutesSpent),
                lastReadDate: Date()
            )
            data.engagements.append(engagement)
        }
        save()
    }

    /// Get engagement for a specific feed.
    func engagement(for feedIdentifier: String) -> FeedReadingEngagement? {
        data.engagements.first { $0.feedIdentifier == feedIdentifier }
    }

    // MARK: - Budget

    /// Get or set the cost budget.
    var budget: CostBudget {
        get { data.budget }
        set {
            data.budget = CostBudget(monthlyLimit: max(0, newValue.monthlyLimit),
                                     warningThreshold: newValue.warningThreshold)
            save()
            checkBudgetWarning()
        }
    }

    /// Current monthly spending from active subscriptions.
    var currentMonthlySpending: Double {
        activeSubscriptions.reduce(0) { $0 + $1.monthlyCost }
    }

    /// Budget usage as a percentage (0.0-1.0+).
    var budgetUsagePercent: Double {
        guard data.budget.monthlyLimit > 0 else { return 0 }
        return currentMonthlySpending / data.budget.monthlyLimit
    }

    /// Budget remaining (can be negative if over budget).
    var budgetRemaining: Double {
        data.budget.monthlyLimit - currentMonthlySpending
    }

    private func checkBudgetWarning() {
        if budgetUsagePercent >= data.budget.warningThreshold && data.budget.monthlyLimit > 0 {
            NotificationCenter.default.post(name: .feedCostBudgetWarning, object: self,
                                            userInfo: ["usage": budgetUsagePercent])
        }
    }

    // MARK: - ROI Analysis

    /// Calculate ROI for all paid feeds.
    func calculateROI() -> [FeedROIResult] {
        return activeSubscriptions.compactMap { sub in
            let eng = engagement(for: sub.feedIdentifier)
            let articles = eng?.articlesRead ?? 0
            let minutes = eng?.totalMinutesSpent ?? 0
            let monthly = sub.monthlyCost

            guard monthly > 0 else { return nil }

            let costPerArticle = articles > 0 ? monthly / Double(articles) : monthly
            let costPerMinute = minutes > 0 ? monthly / minutes : monthly

            // ROI score: based on articles-per-dollar and minutes-per-dollar
            let articlesPerDollar = Double(articles) / monthly
            let minutesPerDollar = minutes / monthly
            let rawScore = (articlesPerDollar * 10.0) + (minutesPerDollar * 2.0)
            let score = min(100, max(0, Int(rawScore)))

            let verdict: String
            switch score {
            case 80...100: verdict = "Excellent value"
            case 60..<80: verdict = "Good value"
            case 40..<60: verdict = "Fair value"
            case 20..<40: verdict = "Poor value"
            default: verdict = "Consider cancelling"
            }

            return FeedROIResult(
                feedIdentifier: sub.feedIdentifier,
                name: sub.name,
                monthlyCost: monthly,
                articlesRead: articles,
                minutesSpent: minutes,
                costPerArticle: costPerArticle,
                costPerMinute: costPerMinute,
                roiScore: score,
                verdict: verdict
            )
        }
    }

    /// Get the best value subscription.
    func bestValue() -> FeedROIResult? {
        calculateROI().max(by: { $0.roiScore < $1.roiScore })
    }

    /// Get the worst value subscription.
    func worstValue() -> FeedROIResult? {
        calculateROI().min(by: { $0.roiScore < $1.roiScore })
    }

    // MARK: - Spending Summaries

    /// Total monthly spending across active subscriptions.
    func monthlySummary() -> MonthlySpendingSummary {
        let cal = Calendar.current
        let now = Date()
        let year = cal.component(.year, from: now)
        let month = cal.component(.month, from: now)

        var categoryBreakdown: [String: Double] = [:]
        for sub in activeSubscriptions {
            categoryBreakdown[sub.category, default: 0] += sub.monthlyCost
        }

        return MonthlySpendingSummary(
            year: year,
            month: month,
            totalSpending: currentMonthlySpending,
            activeSubscriptions: activeSubscriptions.count,
            categoryBreakdown: categoryBreakdown,
            budgetUsagePercent: data.budget.monthlyLimit > 0 ? budgetUsagePercent : nil
        )
    }

    /// Yearly spending projection.
    func yearlyProjection() -> Double {
        currentMonthlySpending * 12.0
    }

    /// Spending by category.
    func spendingByCategory() -> [String: Double] {
        var result: [String: Double] = [:]
        for sub in activeSubscriptions {
            result[sub.category, default: 0] += sub.monthlyCost
        }
        return result
    }

    // MARK: - Renewal Tracking

    /// Subscriptions with renewals in the next N days.
    func upcomingRenewals(withinDays days: Int = 7) -> [FeedSubscriptionCost] {
        let now = Date()
        let cutoff = Calendar.current.date(byAdding: .day, value: days, to: now) ?? now
        return activeSubscriptions.filter { sub in
            guard let renewal = sub.nextRenewalDate else { return false }
            return renewal >= now && renewal <= cutoff
        }.sorted { ($0.nextRenewalDate ?? .distantFuture) < ($1.nextRenewalDate ?? .distantFuture) }
    }

    // MARK: - Export

    /// Export all cost data as JSON.
    func exportJSON() -> String? {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let jsonData = try? encoder.encode(data) else { return nil }
        return String(data: jsonData, encoding: .utf8)
    }

    /// Export spending report as a dictionary.
    func spendingReport() -> [String: Any] {
        let roi = calculateROI()
        let summary = monthlySummary()
        return [
            "currencySymbol": currencySymbol,
            "monthlySpending": summary.totalSpending,
            "yearlyProjection": yearlyProjection(),
            "activeSubscriptions": summary.activeSubscriptions,
            "budgetLimit": budget.monthlyLimit,
            "budgetUsagePercent": budgetUsagePercent,
            "budgetRemaining": budgetRemaining,
            "categoryBreakdown": summary.categoryBreakdown,
            "bestValue": bestValue()?.name ?? "N/A",
            "worstValue": worstValue()?.name ?? "N/A",
            "averageROIScore": roi.isEmpty ? 0 : roi.reduce(0) { $0 + $1.roiScore } / roi.count,
            "upcomingRenewals": upcomingRenewals().map { $0.name }
        ]
    }

    // MARK: - Helpers

    private static func computeNextRenewal(from date: Date, cycle: BillingCycle) -> Date? {
        let cal = Calendar.current
        switch cycle {
        case .weekly: return cal.date(byAdding: .weekOfYear, value: 1, to: date)
        case .monthly: return cal.date(byAdding: .month, value: 1, to: date)
        case .yearly: return cal.date(byAdding: .year, value: 1, to: date)
        case .oneTime: return nil
        }
    }

    // MARK: - Reset

    /// Clear all data.
    func reset() {
        data = FeedCostData()
        save()
        NotificationCenter.default.post(name: .feedCostDidChange, object: self)
    }
}
