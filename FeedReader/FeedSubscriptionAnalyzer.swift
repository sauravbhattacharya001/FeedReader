//
//  FeedSubscriptionAnalyzer.swift
//  FeedReader
//
//  Tracks feed subscription lifecycle — when feeds were added, how
//  engagement changes over time, detects interest decay, and surfaces
//  subscription hygiene suggestions (unsubscribe candidates, re-engage
//  candidates, healthy subscriptions).
//
//  Key features:
//  - Record subscription events (subscribe, unsubscribe, pause, resume)
//  - Track per-feed engagement metrics (reads, skips, time spent)
//  - Engagement decay detection via sliding-window comparison
//  - Subscription age and lifecycle phase classification
//  - Hygiene report: stale feeds, declining engagement, never-read feeds
//  - Re-engagement suggestions for feeds with past high engagement
//  - Subscription portfolio balance (category diversity)
//  - Feed ROI score: engagement-per-article ratio
//  - Export subscription timeline as JSON
//
//  Persistence: JSON file in Documents directory.
//

import Foundation

// MARK: - Notifications

extension Notification.Name {
    /// Posted when a subscription event is recorded.
    static let subscriptionDidChange = Notification.Name("FeedSubscriptionDidChangeNotification")
}

// MARK: - Models

/// Type of subscription lifecycle event.
enum SubscriptionEventType: String, Codable, CaseIterable {
    case subscribe = "subscribe"
    case unsubscribe = "unsubscribe"
    case pause = "pause"
    case resume = "resume"
}

/// A single subscription lifecycle event.
struct SubscriptionEvent: Codable, Identifiable {
    let id: String
    let feedURL: String
    let feedTitle: String
    let category: String?
    let eventType: SubscriptionEventType
    let date: Date
    let reason: String?

    init(feedURL: String, feedTitle: String, category: String? = nil,
         eventType: SubscriptionEventType, date: Date = Date(),
         reason: String? = nil) {
        self.id = UUID().uuidString
        self.feedURL = feedURL
        self.feedTitle = feedTitle
        self.category = category
        self.eventType = eventType
        self.date = date
        self.reason = reason
    }
}

/// An engagement data point for a specific feed over a time window.
struct EngagementSnapshot: Codable {
    let feedURL: String
    let windowStart: Date
    let windowEnd: Date
    let articlesPublished: Int
    let articlesRead: Int
    let articlesSkipped: Int
    let totalReadingTimeSec: Double
    let averageReadPercent: Double

    /// Read rate: fraction of published articles actually read.
    var readRate: Double {
        guard articlesPublished > 0 else { return 0 }
        return Double(articlesRead) / Double(articlesPublished)
    }

    /// Engagement score: weighted combination of read rate and depth.
    var engagementScore: Double {
        let rateComponent = readRate * 60.0
        let depthComponent = min(averageReadPercent, 100.0) * 0.4
        return min(rateComponent + depthComponent, 100.0)
    }
}

/// Lifecycle phase of a subscription.
enum SubscriptionPhase: String, Codable, CaseIterable {
    case honeymoon = "honeymoon"      // < 14 days
    case growing = "growing"          // 14-60 days
    case established = "established"  // 60-180 days
    case mature = "mature"            // 180+ days
    case declining = "declining"      // engagement dropping
    case dormant = "dormant"          // no reads in 30+ days
    case paused = "paused"            // explicitly paused

    var label: String {
        switch self {
        case .honeymoon:   return "Honeymoon"
        case .growing:     return "Growing"
        case .established: return "Established"
        case .mature:      return "Mature"
        case .declining:   return "Declining"
        case .dormant:     return "Dormant"
        case .paused:      return "Paused"
        }
    }

    var emoji: String {
        switch self {
        case .honeymoon:   return "🌱"
        case .growing:     return "📈"
        case .established: return "✅"
        case .mature:      return "🏆"
        case .declining:   return "📉"
        case .dormant:     return "💤"
        case .paused:      return "⏸️"
        }
    }
}

/// Per-feed subscription profile with computed lifecycle metrics.
struct SubscriptionProfile {
    let feedURL: String
    let feedTitle: String
    let category: String?
    let subscribedDate: Date
    let phase: SubscriptionPhase
    let ageDays: Int
    let currentEngagement: Double
    let previousEngagement: Double
    let engagementTrend: Double       // positive = growing, negative = declining
    let totalArticlesRead: Int
    let totalReadingTimeSec: Double
    let roiScore: Double              // engagement per published article
    let isActive: Bool
}

/// Hygiene suggestion for a feed subscription.
struct HygieneSuggestion {
    let feedURL: String
    let feedTitle: String
    let action: HygieneAction
    let reason: String
    let urgency: HygieneUrgency
    let engagementScore: Double
}

/// Suggested hygiene action.
enum HygieneAction: String, CaseIterable {
    case unsubscribe = "unsubscribe"
    case reengage = "reengage"
    case keep = "keep"
    case review = "review"

    var label: String {
        switch self {
        case .unsubscribe: return "Consider Unsubscribing"
        case .reengage:    return "Try Re-engaging"
        case .keep:        return "Keep"
        case .review:      return "Review"
        }
    }

    var emoji: String {
        switch self {
        case .unsubscribe: return "🗑️"
        case .reengage:    return "🔄"
        case .keep:        return "✅"
        case .review:      return "🔍"
        }
    }
}

/// Urgency level for hygiene suggestions.
enum HygieneUrgency: Int, Comparable {
    case low = 1
    case medium = 2
    case high = 3

    static func < (lhs: HygieneUrgency, rhs: HygieneUrgency) -> Bool {
        return lhs.rawValue < rhs.rawValue
    }
}

/// Portfolio diversity analysis.
struct PortfolioBalance {
    let totalActive: Int
    let categoryBreakdown: [(category: String, count: Int, percent: Double)]
    let dominantCategory: String?
    let diversityScore: Double       // 0-100, higher = more diverse
    let recommendation: String
}

/// Complete hygiene report.
struct HygieneReport {
    let generatedAt: Date
    let totalSubscriptions: Int
    let activeSubscriptions: Int
    let suggestions: [HygieneSuggestion]
    let portfolioBalance: PortfolioBalance
    let overallHealthScore: Double   // 0-100

    var unsubscribeCandidates: [HygieneSuggestion] {
        return suggestions.filter { $0.action == .unsubscribe }
    }

    var reengageCandidates: [HygieneSuggestion] {
        return suggestions.filter { $0.action == .reengage }
    }

    var healthyFeeds: [HygieneSuggestion] {
        return suggestions.filter { $0.action == .keep }
    }
}

// MARK: - Persistence Model

struct SubscriptionData: Codable {
    var events: [SubscriptionEvent]
    var engagementHistory: [String: [EngagementSnapshot]]  // feedURL -> snapshots

    init() {
        self.events = []
        self.engagementHistory = [:]
    }
}

// MARK: - FeedSubscriptionAnalyzer

class FeedSubscriptionAnalyzer {

    static let shared = FeedSubscriptionAnalyzer()

    private var data: SubscriptionData
    private let storageKey = "FeedSubscriptionAnalyzerData"

    // MARK: - Thresholds

    /// Days without reads before a feed is considered dormant.
    static let dormantThresholdDays = 30
    /// Engagement trend below this triggers declining phase.
    static let decliningThreshold: Double = -15.0
    /// Engagement score below this suggests unsubscribe.
    static let unsubscribeThreshold: Double = 10.0
    /// Engagement score where re-engage is suggested over unsubscribe.
    static let reengageThreshold: Double = 25.0
    /// Window size in days for engagement snapshots.
    static let engagementWindowDays = 14

    // MARK: - Init

    init() {
        self.data = SubscriptionData()
        loadData()
    }

    // MARK: - Subscription Events

    /// Record a subscription event (subscribe, unsubscribe, pause, resume).
    @discardableResult
    func recordEvent(feedURL: String, feedTitle: String,
                     category: String? = nil,
                     eventType: SubscriptionEventType,
                     date: Date = Date(),
                     reason: String? = nil) -> SubscriptionEvent {
        let event = SubscriptionEvent(
            feedURL: feedURL, feedTitle: feedTitle,
            category: category, eventType: eventType,
            date: date, reason: reason
        )
        data.events.append(event)
        saveData()
        NotificationCenter.default.post(name: .subscriptionDidChange,
                                        object: self,
                                        userInfo: ["event": event])
        return event
    }

    /// All events for a specific feed, ordered by date.
    func events(for feedURL: String) -> [SubscriptionEvent] {
        return data.events
            .filter { $0.feedURL == feedURL }
            .sorted { $0.date < $1.date }
    }

    /// All recorded events, ordered by date (most recent first).
    func allEvents() -> [SubscriptionEvent] {
        return data.events.sorted { $0.date > $1.date }
    }

    /// Count of events matching a type.
    func eventCount(ofType type: SubscriptionEventType) -> Int {
        return data.events.filter { $0.eventType == type }.count
    }

    // MARK: - Engagement Tracking

    /// Record an engagement snapshot for a feed.
    func recordEngagement(feedURL: String, articlesPublished: Int,
                          articlesRead: Int, articlesSkipped: Int = 0,
                          totalReadingTimeSec: Double = 0,
                          averageReadPercent: Double = 0,
                          windowStart: Date? = nil,
                          windowEnd: Date? = nil) {
        let now = Date()
        let windowDays = FeedSubscriptionAnalyzer.engagementWindowDays
        let start = windowStart ?? Calendar.current.date(
            byAdding: .day, value: -windowDays, to: now)!
        let end = windowEnd ?? now

        let snapshot = EngagementSnapshot(
            feedURL: feedURL,
            windowStart: start,
            windowEnd: end,
            articlesPublished: articlesPublished,
            articlesRead: articlesRead,
            articlesSkipped: articlesSkipped,
            totalReadingTimeSec: totalReadingTimeSec,
            averageReadPercent: averageReadPercent
        )

        if data.engagementHistory[feedURL] == nil {
            data.engagementHistory[feedURL] = []
        }
        data.engagementHistory[feedURL]!.append(snapshot)
        saveData()
    }

    /// Get engagement history for a feed, ordered by window start.
    func engagementHistory(for feedURL: String) -> [EngagementSnapshot] {
        return (data.engagementHistory[feedURL] ?? [])
            .sorted { $0.windowStart < $1.windowStart }
    }

    /// Latest engagement snapshot for a feed.
    func latestEngagement(for feedURL: String) -> EngagementSnapshot? {
        return engagementHistory(for: feedURL).last
    }

    // MARK: - Lifecycle Analysis

    /// Determine the subscription date for a feed (first subscribe event).
    func subscriptionDate(for feedURL: String) -> Date? {
        return events(for: feedURL)
            .first { $0.eventType == .subscribe }?.date
    }

    /// Subscription age in days.
    func subscriptionAgeDays(for feedURL: String) -> Int? {
        guard let subDate = subscriptionDate(for: feedURL) else { return nil }
        return Calendar.current.dateComponents([.day], from: subDate, to: Date()).day
    }

    /// Whether a feed is currently active (subscribed and not paused/unsubscribed).
    func isActive(feedURL: String) -> Bool {
        guard let lastEvent = events(for: feedURL).last else { return false }
        return lastEvent.eventType == .subscribe || lastEvent.eventType == .resume
    }

    /// Compute the engagement trend: difference between latest and previous window.
    func engagementTrend(for feedURL: String) -> Double {
        let history = engagementHistory(for: feedURL)
        guard history.count >= 2 else { return 0 }
        let current = history[history.count - 1].engagementScore
        let previous = history[history.count - 2].engagementScore
        return current - previous
    }

    /// Determine the lifecycle phase for a feed.
    func phase(for feedURL: String) -> SubscriptionPhase {
        // Check if paused
        if let lastEvent = events(for: feedURL).last,
           lastEvent.eventType == .pause {
            return .paused
        }

        // Check engagement trend
        let trend = engagementTrend(for: feedURL)
        if trend < FeedSubscriptionAnalyzer.decliningThreshold {
            return .declining
        }

        // Check dormancy: no engagement snapshots with reads in last N days
        let history = engagementHistory(for: feedURL)
        if let lastRead = history.last(where: { $0.articlesRead > 0 }) {
            let daysSinceRead = Calendar.current.dateComponents(
                [.day], from: lastRead.windowEnd, to: Date()).day ?? 0
            if daysSinceRead >= FeedSubscriptionAnalyzer.dormantThresholdDays {
                return .dormant
            }
        } else if !history.isEmpty {
            // Has snapshots but zero reads ever
            return .dormant
        }

        // Age-based phase
        guard let ageDays = subscriptionAgeDays(for: feedURL) else {
            return .honeymoon
        }
        switch ageDays {
        case 0..<14:   return .honeymoon
        case 14..<60:  return .growing
        case 60..<180: return .established
        default:       return .mature
        }
    }

    /// Build a complete subscription profile for a feed.
    func profile(for feedURL: String) -> SubscriptionProfile? {
        guard let subDate = subscriptionDate(for: feedURL) else { return nil }
        let feedEvents = events(for: feedURL)
        let title = feedEvents.last?.feedTitle ?? feedURL
        let category = feedEvents.last?.category
        let ageDays = subscriptionAgeDays(for: feedURL) ?? 0
        let history = engagementHistory(for: feedURL)

        let currentEng = history.last?.engagementScore ?? 0
        let previousEng = history.count >= 2
            ? history[history.count - 2].engagementScore : 0
        let trend = engagementTrend(for: feedURL)

        let totalRead = history.reduce(0) { $0 + $1.articlesRead }
        let totalTime = history.reduce(0.0) { $0 + $1.totalReadingTimeSec }
        let totalPublished = history.reduce(0) { $0 + $1.articlesPublished }

        let roi = totalPublished > 0
            ? (Double(totalRead) / Double(totalPublished)) * 100.0 : 0

        return SubscriptionProfile(
            feedURL: feedURL,
            feedTitle: title,
            category: category,
            subscribedDate: subDate,
            phase: phase(for: feedURL),
            ageDays: ageDays,
            currentEngagement: currentEng,
            previousEngagement: previousEng,
            engagementTrend: trend,
            totalArticlesRead: totalRead,
            totalReadingTimeSec: totalTime,
            roiScore: roi,
            isActive: isActive(feedURL: feedURL)
        )
    }

    /// Profiles for all tracked feeds.
    func allProfiles() -> [SubscriptionProfile] {
        let urls = allTrackedFeedURLs()
        return urls.compactMap { profile(for: $0) }
    }

    /// All unique feed URLs with at least one event or engagement record.
    func allTrackedFeedURLs() -> [String] {
        var urls = Set<String>()
        for event in data.events { urls.insert(event.feedURL) }
        for url in data.engagementHistory.keys { urls.insert(url) }
        return Array(urls).sorted()
    }

    // MARK: - Hygiene Report

    /// Generate a subscription hygiene report with actionable suggestions.
    func hygieneReport() -> HygieneReport {
        let profiles = allProfiles()
        let activeProfiles = profiles.filter { $0.isActive }
        var suggestions: [HygieneSuggestion] = []

        for p in profiles {
            let suggestion = classifySuggestion(profile: p)
            suggestions.append(suggestion)
        }

        // Sort: high urgency first, then by engagement (ascending)
        suggestions.sort { a, b in
            if a.urgency != b.urgency { return a.urgency > b.urgency }
            return a.engagementScore < b.engagementScore
        }

        let balance = portfolioBalance(profiles: activeProfiles)
        let healthScore = computeOverallHealth(profiles: activeProfiles)

        return HygieneReport(
            generatedAt: Date(),
            totalSubscriptions: profiles.count,
            activeSubscriptions: activeProfiles.count,
            suggestions: suggestions,
            portfolioBalance: balance,
            overallHealthScore: healthScore
        )
    }

    /// Classify what action to suggest for a feed.
    private func classifySuggestion(profile: SubscriptionProfile) -> HygieneSuggestion {
        let eng = profile.currentEngagement

        // Dormant feeds with history of good engagement -> re-engage
        if profile.phase == .dormant && profile.previousEngagement > 30 {
            return HygieneSuggestion(
                feedURL: profile.feedURL,
                feedTitle: profile.feedTitle,
                action: .reengage,
                reason: "Was engaging (\(Int(profile.previousEngagement))%) but dormant for 30+ days",
                urgency: .medium,
                engagementScore: eng
            )
        }

        // Dormant feeds with no history -> unsubscribe
        if profile.phase == .dormant {
            return HygieneSuggestion(
                feedURL: profile.feedURL,
                feedTitle: profile.feedTitle,
                action: .unsubscribe,
                reason: "No reads in 30+ days with low prior engagement",
                urgency: .high,
                engagementScore: eng
            )
        }

        // Very low engagement -> unsubscribe
        if eng < FeedSubscriptionAnalyzer.unsubscribeThreshold
            && profile.ageDays > 14 {
            return HygieneSuggestion(
                feedURL: profile.feedURL,
                feedTitle: profile.feedTitle,
                action: .unsubscribe,
                reason: "Engagement below \(Int(FeedSubscriptionAnalyzer.unsubscribeThreshold))% for \(profile.ageDays) days",
                urgency: .high,
                engagementScore: eng
            )
        }

        // Declining trend -> review
        if profile.phase == .declining {
            return HygieneSuggestion(
                feedURL: profile.feedURL,
                feedTitle: profile.feedTitle,
                action: .review,
                reason: "Engagement declining (trend: \(String(format: "%.1f", profile.engagementTrend)))",
                urgency: .medium,
                engagementScore: eng
            )
        }

        // Low-ish engagement -> re-engage
        if eng < FeedSubscriptionAnalyzer.reengageThreshold
            && profile.ageDays > 14 {
            return HygieneSuggestion(
                feedURL: profile.feedURL,
                feedTitle: profile.feedTitle,
                action: .reengage,
                reason: "Low engagement (\(Int(eng))%) — consider checking recent articles",
                urgency: .low,
                engagementScore: eng
            )
        }

        // Healthy
        return HygieneSuggestion(
            feedURL: profile.feedURL,
            feedTitle: profile.feedTitle,
            action: .keep,
            reason: "Healthy engagement (\(Int(eng))%)",
            urgency: .low,
            engagementScore: eng
        )
    }

    // MARK: - Portfolio Balance

    /// Analyze category diversity of active subscriptions.
    func portfolioBalance(profiles: [SubscriptionProfile]? = nil) -> PortfolioBalance {
        let active = profiles ?? allProfiles().filter { $0.isActive }
        let total = active.count

        guard total > 0 else {
            return PortfolioBalance(
                totalActive: 0,
                categoryBreakdown: [],
                dominantCategory: nil,
                diversityScore: 0,
                recommendation: "No active subscriptions."
            )
        }

        // Count per category
        var categoryCounts: [String: Int] = [:]
        for p in active {
            let cat = p.category ?? "Uncategorized"
            categoryCounts[cat, default: 0] += 1
        }

        let breakdown = categoryCounts
            .sorted { $0.value > $1.value }
            .map { (category: $0.key, count: $0.value,
                     percent: Double($0.value) / Double(total) * 100.0) }

        let dominant = breakdown.first?.category

        // Simpson's diversity index (1 - sum of squared proportions)
        let simpson = 1.0 - breakdown.reduce(0.0) { acc, item in
            let p = Double(item.count) / Double(total)
            return acc + (p * p)
        }
        let diversityScore = simpson * 100.0

        // Recommendation
        let recommendation: String
        if breakdown.count == 1 {
            recommendation = "All feeds in one category. Consider diversifying."
        } else if let top = breakdown.first, top.percent > 60 {
            recommendation = "\(top.category) dominates (\(Int(top.percent))%). Consider balancing."
        } else if diversityScore > 70 {
            recommendation = "Good diversity across \(breakdown.count) categories."
        } else {
            recommendation = "Moderate diversity. Could explore new categories."
        }

        return PortfolioBalance(
            totalActive: total,
            categoryBreakdown: breakdown,
            dominantCategory: dominant,
            diversityScore: diversityScore,
            recommendation: recommendation
        )
    }

    // MARK: - Health Score

    /// Compute overall subscription health (0-100).
    private func computeOverallHealth(profiles: [SubscriptionProfile]) -> Double {
        guard !profiles.isEmpty else { return 0 }

        // Average engagement across active feeds
        let avgEngagement = profiles.reduce(0.0) { $0 + $1.currentEngagement }
            / Double(profiles.count)

        // Penalty for dormant/declining feeds
        let problematic = profiles.filter {
            $0.phase == .dormant || $0.phase == .declining
        }.count
        let problemRatio = Double(problematic) / Double(profiles.count)
        let healthPenalty = problemRatio * 30.0

        // Diversity bonus
        let balance = portfolioBalance(profiles: profiles)
        let diversityBonus = balance.diversityScore * 0.1

        return min(max(avgEngagement - healthPenalty + diversityBonus, 0), 100)
    }

    // MARK: - Convenience Queries

    /// Feeds sorted by ROI score (highest first).
    func feedsByROI() -> [SubscriptionProfile] {
        return allProfiles()
            .filter { $0.isActive }
            .sorted { $0.roiScore > $1.roiScore }
    }

    /// Feeds that have never been read.
    func neverReadFeeds() -> [SubscriptionProfile] {
        return allProfiles().filter { $0.totalArticlesRead == 0 && $0.isActive }
    }

    /// Feeds subscribed in the last N days.
    func recentSubscriptions(withinDays days: Int = 7) -> [SubscriptionEvent] {
        let cutoff = Calendar.current.date(byAdding: .day, value: -days, to: Date())!
        return data.events
            .filter { $0.eventType == .subscribe && $0.date >= cutoff }
            .sorted { $0.date > $1.date }
    }

    /// Average subscription age in days across all active feeds.
    func averageSubscriptionAge() -> Double {
        let active = allProfiles().filter { $0.isActive }
        guard !active.isEmpty else { return 0 }
        let totalDays = active.reduce(0) { $0 + $1.ageDays }
        return Double(totalDays) / Double(active.count)
    }

    /// Churn rate: unsubscribes / total subscriptions.
    func churnRate() -> Double {
        let subs = eventCount(ofType: .subscribe)
        guard subs > 0 else { return 0 }
        let unsubs = eventCount(ofType: .unsubscribe)
        return Double(unsubs) / Double(subs)
    }

    // MARK: - Export

    /// Export subscription timeline as JSON data.
    func exportTimeline() -> Data? {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try? encoder.encode(data)
    }

    // MARK: - Data Management

    /// Remove all events for a specific feed.
    func clearFeed(_ feedURL: String) {
        data.events.removeAll { $0.feedURL == feedURL }
        data.engagementHistory.removeValue(forKey: feedURL)
        saveData()
    }

    /// Remove all data.
    func clearAll() {
        data = SubscriptionData()
        saveData()
    }

    /// Total number of events recorded.
    func totalEventCount() -> Int {
        return data.events.count
    }

    /// Total number of engagement snapshots across all feeds.
    func totalSnapshotCount() -> Int {
        return data.engagementHistory.values.reduce(0) { $0 + $1.count }
    }

    // MARK: - Persistence

    private func saveData() {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        if let encoded = try? encoder.encode(data) {
            UserDefaults.standard.set(encoded, forKey: storageKey)
        }
    }

    private func loadData() {
        guard let saved = UserDefaults.standard.data(forKey: storageKey) else { return }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        if let decoded = try? decoder.decode(SubscriptionData.self, from: saved) {
            data = decoded
        }
    }

    /// Reload data from storage.
    func reload() {
        loadData()
    }
}
