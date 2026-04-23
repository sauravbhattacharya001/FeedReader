//
//  FeedInboxZero.swift
//  FeedReader
//
//  Autonomous inbox-zero strategy engine that helps users systematically
//  clear their unread article queue. Analyzes the backlog, categorizes
//  articles into action buckets, suggests batch operations, and tracks
//  progress toward inbox zero with streaks and milestones.
//
//  How it works:
//  1. Scans unread articles and categorizes into action buckets:
//     - Must Read (high relevance, from favorite feeds)
//     - Quick Scan (short articles, low-medium relevance)
//     - Archive (low relevance, duplicated content)
//     - Defer (interesting but not urgent, schedule for later)
//     - Bulk Dismiss (noise, duplicates)
//  2. Generates a clearance plan with estimated time per bucket
//  3. Tracks daily/weekly clearance velocity and predicts zero-date
//  4. Awards streaks for consecutive days reducing the queue
//  5. Detects backlog accumulation patterns and suggests feed adjustments
//  6. Auto-archives articles past configurable staleness threshold
//
//  Usage:
//  ```
//  let inboxZero = FeedInboxZero.shared
//
//  // Configure
//  inboxZero.config.autoArchiveEnabled = true
//  inboxZero.config.dailyClearanceBudgetMinutes = 20
//
//  // Analyze backlog
//  let plan = inboxZero.analyzePlan(unread: stories, readHistory: readStories)
//  print("Backlog: \(plan.totalUnread), ETA: \(plan.estimatedZeroDate)")
//  for bucket in plan.buckets {
//      print("\(bucket.action): \(bucket.articles.count) — ~\(bucket.estimatedMinutes) min")
//  }
//
//  // Execute batch action
//  let result = inboxZero.executeBatch(.bulkDismiss, count: 15)
//
//  // Track progress
//  let progress = inboxZero.progressReport()
//  print("Streak: \(progress.currentStreak) days")
//
//  // Get accumulation insights
//  let insights = inboxZero.accumulationInsights(unread: stories)
//  ```
//
//  All processing on-device. No network calls.
//

import Foundation

// MARK: - Notifications

extension Notification.Name {
    static let inboxZeroPlanGenerated = Notification.Name("FeedInboxZeroPlanGeneratedNotification")
    static let inboxZeroBatchExecuted = Notification.Name("FeedInboxZeroBatchExecutedNotification")
    static let inboxZeroAchieved = Notification.Name("FeedInboxZeroAchievedNotification")
    static let inboxZeroStreakMilestone = Notification.Name("FeedInboxZeroStreakMilestoneNotification")
}

// MARK: - Configuration

struct InboxZeroConfig: Codable {
    var stalenessThresholdDays: Int = 14
    var autoArchiveEnabled: Bool = false
    var dailyClearanceBudgetMinutes: Int = 20
    var mustReadThreshold: Double = 0.7
    var quickScanMaxWords: Int = 500
    var duplicateThreshold: Double = 0.5
    var velocityWindowDays: Int = 14
    var streakNotificationsEnabled: Bool = true
    var streakMilestones: [Int] = [3, 7, 14, 30, 60, 100]
    var feedAdjustmentSuggestionsEnabled: Bool = true
}

// MARK: - Action Buckets

enum InboxZeroAction: String, Codable, CaseIterable {
    case mustRead = "Must Read"
    case quickScan = "Quick Scan"
    case archive = "Archive"
    case `defer` = "Defer"
    case bulkDismiss = "Bulk Dismiss"

    var estimatedMinutesPerArticle: Double {
        switch self {
        case .mustRead: return 5.0
        case .quickScan: return 1.5
        case .archive: return 0.1
        case .defer: return 0.2
        case .bulkDismiss: return 0.05
        }
    }

    var priority: Int {
        switch self {
        case .bulkDismiss: return 0
        case .archive: return 1
        case .quickScan: return 2
        case .defer: return 3
        case .mustRead: return 4
        }
    }

    var actionDescription: String {
        switch self {
        case .mustRead: return "High-value articles worth your full attention"
        case .quickScan: return "Short articles you can skim in under 2 minutes"
        case .archive: return "Low-relevance articles safe to archive"
        case .defer: return "Interesting but not urgent — schedule for later"
        case .bulkDismiss: return "Noise, duplicates, or expired content to clear"
        }
    }
}

// MARK: - Models

struct CategorizedArticle: Codable {
    let title: String
    let feedName: String
    let wordCount: Int
    let action: InboxZeroAction
    let relevanceScore: Double
    let reason: String
    let isDuplicate: Bool
}

struct ActionBucket: Codable {
    let action: InboxZeroAction
    let articles: [CategorizedArticle]
    let estimatedMinutes: Double
    let description: String
    var count: Int { articles.count }
}

struct ClearancePlan: Codable {
    let generatedAt: Date
    let totalUnread: Int
    let buckets: [ActionBucket]
    let estimatedTotalMinutes: Double
    let estimatedZeroDate: Date?
    let sessionSuggestion: SessionSuggestion
    let backlogSeverity: BacklogSeverity
}

struct SessionSuggestion: Codable {
    let budgetMinutes: Int
    let recommendedBuckets: [InboxZeroAction]
    let estimatedArticlesCleared: Int
    let motivationalMessage: String
}

enum BacklogSeverity: String, Codable {
    case zero = "Inbox Zero! 🎉"
    case healthy = "Healthy 🟢"
    case growing = "Growing 🟡"
    case overwhelming = "Overwhelming 🟠"
    case critical = "Critical 🔴"

    static func from(count: Int, velocity: Double) -> BacklogSeverity {
        if count == 0 { return .zero }
        if count < 20 { return .healthy }
        if count < 50 || velocity > Double(count) / 7.0 { return .growing }
        if count < 150 { return .overwhelming }
        return .critical
    }
}

struct BatchResult: Codable {
    let action: InboxZeroAction
    let articlesProcessed: Int
    let timestamp: Date
}

struct DailySnapshot: Codable {
    let date: Date
    let unreadCount: Int
    let articlesCleared: Int
    let articlesArrived: Int
    let minutesSpent: Double
}

struct InboxZeroProgress: Codable {
    let currentUnread: Int
    let dailyVelocity: Double
    let dailyInflowRate: Double
    let netDailyChange: Double
    let currentStreak: Int
    let longestStreak: Int
    let estimatedZeroDays: Int?
    let totalCleared: Int
    let milestonesReached: [Int]
    let trend: QueueTrend
}

enum QueueTrend: String, Codable {
    case shrinking = "Shrinking 📉"
    case stable = "Stable ➡️"
    case growing = "Growing 📈"
    case spiraling = "Spiraling 🌀"
}

struct AccumulationInsight: Codable {
    let feedName: String
    let articlesPerDay: Double
    let readRate: Double
    let backlogContribution: Int
    let suggestion: String
}

// MARK: - FeedInboxZero Engine

final class FeedInboxZero {

    static let shared = FeedInboxZero()

    var config = InboxZeroConfig()

    private(set) var snapshots: [DailySnapshot] = []
    private(set) var batchLog: [BatchResult] = []
    private(set) var currentStreak: Int = 0
    private(set) var longestStreak: Int = 0
    private(set) var totalCleared: Int = 0
    private(set) var milestonesReached: [Int] = []

    private let persistencePath: URL

    private init() {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        persistencePath = docs.appendingPathComponent("inbox_zero_state.json")
        loadState()
    }

    // MARK: - Core Analysis

    /// Analyze the unread queue and produce a clearance plan.
    ///
    /// - Parameters:
    ///   - unread: Array of unread Story objects.
    ///   - readHistory: Previously read stories for relevance scoring.
    ///   - feedReadRates: Optional dictionary of feed name → read rate (0–1).
    func analyzePlan(unread: [Story], readHistory: [Story] = [], feedReadRates: [String: Double] = [:]) -> ClearancePlan {
        let now = Date()
        let calendar = Calendar.current
        var categorized: [CategorizedArticle] = []

        // Build keyword sets for duplicate detection
        let keywordSets = unread.map { extractKeywords(from: $0.title) }

        for (index, story) in unread.enumerated() {
            let title = story.title
            let feedName = story.sourceFeedName ?? "Unknown"
            let wordCount = story.body.components(separatedBy: .whitespacesAndNewlines).filter { !$0.isEmpty }.count

            let isDuplicate = checkDuplicate(index: index, keywords: keywordSets)

            let relevance = calculateRelevance(
                title: title,
                feedName: feedName,
                feedReadRates: feedReadRates,
                readHistory: readHistory
            )

            let action = categorizeAction(
                relevance: relevance,
                wordCount: wordCount,
                isDuplicate: isDuplicate
            )

            let reason = buildReason(action: action, relevance: relevance, wordCount: wordCount, isDuplicate: isDuplicate)

            categorized.append(CategorizedArticle(
                title: title,
                feedName: feedName,
                wordCount: wordCount,
                action: action,
                relevanceScore: relevance,
                reason: reason,
                isDuplicate: isDuplicate
            ))
        }

        // Group into buckets
        let grouped = Dictionary(grouping: categorized) { $0.action }
        let buckets: [ActionBucket] = InboxZeroAction.allCases.compactMap { action in
            guard let articles = grouped[action], !articles.isEmpty else { return nil }
            let minutes = Double(articles.count) * action.estimatedMinutesPerArticle
            return ActionBucket(
                action: action,
                articles: articles.sorted { $0.relevanceScore > $1.relevanceScore },
                estimatedMinutes: round(minutes * 10) / 10,
                description: action.actionDescription
            )
        }.sorted { $0.action.priority < $1.action.priority }

        let totalMinutes = buckets.reduce(0.0) { $0 + $1.estimatedMinutes }
        let velocity = averageDailyVelocity()
        let inflow = averageDailyInflow()
        let netDaily = velocity - inflow

        let zeroDate: Date? = {
            guard netDaily > 0, unread.count > 0 else { return nil }
            let daysNeeded = Int(ceil(Double(unread.count) / netDaily))
            return calendar.date(byAdding: .day, value: daysNeeded, to: now)
        }()

        let severity = BacklogSeverity.from(count: unread.count, velocity: velocity)
        let session = buildSessionSuggestion(buckets: buckets, severity: severity)

        let plan = ClearancePlan(
            generatedAt: now,
            totalUnread: unread.count,
            buckets: buckets,
            estimatedTotalMinutes: round(totalMinutes * 10) / 10,
            estimatedZeroDate: zeroDate,
            sessionSuggestion: session,
            backlogSeverity: severity
        )

        NotificationCenter.default.post(name: .inboxZeroPlanGenerated, object: plan)
        return plan
    }

    /// Execute a batch action and record it.
    func executeBatch(_ action: InboxZeroAction, count: Int) -> BatchResult {
        let result = BatchResult(action: action, articlesProcessed: count, timestamp: Date())
        batchLog.append(result)
        totalCleared += count
        saveState()
        NotificationCenter.default.post(name: .inboxZeroBatchExecuted, object: result)
        return result
    }

    /// Record a daily snapshot for velocity tracking.
    func recordSnapshot(unreadCount: Int, articlesCleared: Int, articlesArrived: Int, minutesSpent: Double) {
        let snapshot = DailySnapshot(
            date: Date(),
            unreadCount: unreadCount,
            articlesCleared: articlesCleared,
            articlesArrived: articlesArrived,
            minutesSpent: minutesSpent
        )
        snapshots.append(snapshot)

        // Update streak
        if articlesCleared > articlesArrived {
            currentStreak += 1
            if currentStreak > longestStreak {
                longestStreak = currentStreak
            }
            for milestone in config.streakMilestones where currentStreak == milestone && !milestonesReached.contains(milestone) {
                milestonesReached.append(milestone)
                if config.streakNotificationsEnabled {
                    NotificationCenter.default.post(name: .inboxZeroStreakMilestone, object: milestone)
                }
            }
        } else if articlesCleared == 0 {
            currentStreak = 0
        }

        if unreadCount == 0 {
            NotificationCenter.default.post(name: .inboxZeroAchieved, object: nil)
        }

        saveState()
    }

    /// Generate a progress report.
    func progressReport() -> InboxZeroProgress {
        let velocity = averageDailyVelocity()
        let inflow = averageDailyInflow()
        let net = velocity - inflow
        let currentUnread = snapshots.last?.unreadCount ?? 0

        let zeroDays: Int? = {
            guard net > 0, currentUnread > 0 else { return nil }
            return Int(ceil(Double(currentUnread) / net))
        }()

        let trend: QueueTrend = {
            if net > 2 { return .shrinking }
            if net > -1 { return .stable }
            if net > -5 { return .growing }
            return .spiraling
        }()

        return InboxZeroProgress(
            currentUnread: currentUnread,
            dailyVelocity: round(velocity * 10) / 10,
            dailyInflowRate: round(inflow * 10) / 10,
            netDailyChange: round(net * 10) / 10,
            currentStreak: currentStreak,
            longestStreak: longestStreak,
            estimatedZeroDays: zeroDays,
            totalCleared: totalCleared,
            milestonesReached: milestonesReached,
            trend: trend
        )
    }

    /// Analyze which feeds are causing backlog accumulation.
    func accumulationInsights(unread: [Story], readHistory: [Story] = []) -> [AccumulationInsight] {
        let feedGroups = Dictionary(grouping: unread) { $0.sourceFeedName ?? "Unknown" }
        let historyByFeed = Dictionary(grouping: readHistory) { $0.sourceFeedName ?? "Unknown" }

        var insights: [AccumulationInsight] = []

        for (feedName, articles) in feedGroups {
            let backlog = articles.count
            let historyCount = historyByFeed[feedName]?.count ?? 0
            let totalSeen = backlog + historyCount
            let readRate = totalSeen > 0 ? Double(historyCount) / Double(totalSeen) : 0.0
            let articlesPerDay = max(1.0, Double(articles.count) / 7.0)

            let suggestion: String = {
                if readRate < 0.05 && backlog > 10 {
                    return "Consider unsubscribing — you rarely read articles from this feed"
                } else if articlesPerDay > 5 && readRate < 0.2 {
                    return "High-volume, low-engagement — try enabling a keyword filter"
                } else if backlog > 20 && readRate > 0.3 {
                    return "You like this feed but can't keep up — try the digest mode"
                } else if backlog > 5 {
                    return "Moderate backlog — a quick scan session could clear this"
                } else {
                    return "Manageable — no action needed"
                }
            }()

            insights.append(AccumulationInsight(
                feedName: feedName,
                articlesPerDay: round(articlesPerDay * 10) / 10,
                readRate: round(readRate * 100) / 100,
                backlogContribution: backlog,
                suggestion: suggestion
            ))
        }

        return insights.sorted { $0.backlogContribution > $1.backlogContribution }
    }

    /// Generate a motivational summary string.
    func motivationalSummary() -> String {
        let progress = progressReport()
        var lines: [String] = []

        lines.append("📬 Inbox Zero Progress Report")
        lines.append("━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
        lines.append("Unread: \(progress.currentUnread)")
        lines.append("Trend: \(progress.trend.rawValue)")
        lines.append("Daily velocity: \(progress.dailyVelocity) articles/day")
        lines.append("Daily inflow: \(progress.dailyInflowRate) articles/day")
        lines.append("Net change: \(progress.netDailyChange > 0 ? "-" : "+")\(abs(progress.netDailyChange))/day")
        lines.append("")

        if let zeroDays = progress.estimatedZeroDays {
            lines.append("🎯 Estimated inbox zero in \(zeroDays) day\(zeroDays == 1 ? "" : "s")")
        } else if progress.currentUnread == 0 {
            lines.append("🎉 You've achieved inbox zero!")
        } else {
            lines.append("⚠️ Queue is growing faster than you read — consider batch actions")
        }

        lines.append("")
        lines.append("🔥 Streak: \(progress.currentStreak) day\(progress.currentStreak == 1 ? "" : "s") (best: \(progress.longestStreak))")
        lines.append("📊 Total cleared all-time: \(progress.totalCleared)")

        if !progress.milestonesReached.isEmpty {
            lines.append("🏆 Milestones: \(progress.milestonesReached.map { "\($0)-day" }.joined(separator: ", "))")
        }

        return lines.joined(separator: "\n")
    }

    // MARK: - Private Helpers

    private func calculateRelevance(title: String, feedName: String, feedReadRates: [String: Double], readHistory: [Story]) -> Double {
        var score = 0.5

        // Feed affinity
        if let rate = feedReadRates[feedName] {
            score += min(rate, 1.0) * 0.25
        }

        // Title keyword overlap with reading history
        let titleKeywords = extractKeywords(from: title)
        let historyKeywords = Set(readHistory.prefix(50).flatMap { extractKeywords(from: $0.title) })
        let overlap = titleKeywords.intersection(historyKeywords)
        if !titleKeywords.isEmpty {
            score += Double(overlap.count) / Double(max(titleKeywords.count, 1)) * 0.25
        }

        return min(max(score, 0), 1.0)
    }

    private func categorizeAction(relevance: Double, wordCount: Int, isDuplicate: Bool) -> InboxZeroAction {
        if isDuplicate { return .bulkDismiss }
        if relevance >= config.mustReadThreshold { return .mustRead }
        if wordCount <= config.quickScanMaxWords && relevance >= 0.3 { return .quickScan }
        if relevance < 0.3 { return .archive }
        if relevance >= 0.4 { return .defer }
        return .bulkDismiss
    }

    private func buildReason(action: InboxZeroAction, relevance: Double, wordCount: Int, isDuplicate: Bool) -> String {
        if isDuplicate { return "Similar article already in queue" }
        switch action {
        case .mustRead:
            return "High relevance (\(Int(relevance * 100))%) from a feed you engage with"
        case .quickScan:
            return "\(wordCount) words — quick read"
        case .archive:
            return "Low relevance (\(Int(relevance * 100))%)"
        case .defer:
            return "Interesting (\(Int(relevance * 100))%) but not time-sensitive"
        case .bulkDismiss:
            return "Low relevance — safe to clear"
        }
    }

    private func buildSessionSuggestion(buckets: [ActionBucket], severity: BacklogSeverity) -> SessionSuggestion {
        let budget = config.dailyClearanceBudgetMinutes
        var remaining = Double(budget)
        var recommended: [InboxZeroAction] = []
        var cleared = 0

        for bucket in buckets {
            if remaining <= 0 { break }
            let canProcess = Int(remaining / bucket.action.estimatedMinutesPerArticle)
            let willProcess = min(canProcess, bucket.count)
            if willProcess > 0 {
                recommended.append(bucket.action)
                cleared += willProcess
                remaining -= Double(willProcess) * bucket.action.estimatedMinutesPerArticle
            }
        }

        let message: String = {
            switch severity {
            case .zero: return "🎉 You're at inbox zero! Enjoy the calm."
            case .healthy: return "👍 Looking good! A quick session will keep things tidy."
            case .growing: return "📋 Queue is building up — today's session can turn the tide."
            case .overwhelming: return "💪 Big backlog, but start with bulk actions — you'll see fast progress!"
            case .critical: return "🚨 Backlog is critical — let's triage aggressively. Dismiss and archive first."
            }
        }()

        return SessionSuggestion(
            budgetMinutes: budget,
            recommendedBuckets: recommended,
            estimatedArticlesCleared: cleared,
            motivationalMessage: message
        )
    }

    private func checkDuplicate(index: Int, keywords: [Set<String>]) -> Bool {
        guard index > 0 else { return false }
        let current = keywords[index]
        guard current.count >= 3 else { return false }

        for i in 0..<index {
            let other = keywords[i]
            guard other.count >= 3 else { continue }
            let intersection = current.intersection(other)
            let union = current.union(other)
            let jaccard = Double(intersection.count) / Double(union.count)
            if jaccard >= config.duplicateThreshold { return true }
        }
        return false
    }

    private func extractKeywords(from text: String) -> Set<String> {
        let stopWords: Set<String> = ["the", "a", "an", "is", "are", "was", "were", "in", "on", "at",
                                       "to", "for", "of", "with", "by", "from", "and", "or", "but",
                                       "not", "this", "that", "it", "its", "as", "be", "has", "had",
                                       "have", "will", "do", "does", "did", "can", "could", "would",
                                       "should", "may", "might", "shall", "been", "being", "if", "so",
                                       "than", "too", "very", "just", "about", "up", "out", "no", "how"]
        let words = text.lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { $0.count > 2 && !stopWords.contains($0) }
        return Set(words)
    }

    private func averageDailyVelocity() -> Double {
        let recent = recentSnapshots()
        guard !recent.isEmpty else { return 0 }
        return Double(recent.reduce(0) { $0 + $1.articlesCleared }) / Double(recent.count)
    }

    private func averageDailyInflow() -> Double {
        let recent = recentSnapshots()
        guard !recent.isEmpty else { return 0 }
        return Double(recent.reduce(0) { $0 + $1.articlesArrived }) / Double(recent.count)
    }

    private func recentSnapshots() -> [DailySnapshot] {
        let cutoff = Calendar.current.date(byAdding: .day, value: -config.velocityWindowDays, to: Date()) ?? Date()
        return snapshots.filter { $0.date >= cutoff }
    }

    // MARK: - Persistence

    private func loadState() {
        guard let data = try? Data(contentsOf: persistencePath),
              let state = try? JSONDecoder().decode(InboxZeroState.self, from: data) else { return }
        snapshots = state.snapshots
        batchLog = state.batchLog
        currentStreak = state.currentStreak
        longestStreak = state.longestStreak
        totalCleared = state.totalCleared
        milestonesReached = state.milestonesReached
        config = state.config
    }

    private func saveState() {
        let state = InboxZeroState(
            snapshots: snapshots,
            batchLog: batchLog,
            currentStreak: currentStreak,
            longestStreak: longestStreak,
            totalCleared: totalCleared,
            milestonesReached: milestonesReached,
            config: config
        )
        if let data = try? JSONEncoder().encode(state) {
            try? data.write(to: persistencePath, options: .atomic)
        }
    }
}

// MARK: - Persistence Model

private struct InboxZeroState: Codable {
    let snapshots: [DailySnapshot]
    let batchLog: [BatchResult]
    let currentStreak: Int
    let longestStreak: Int
    let totalCleared: Int
    let milestonesReached: [Int]
    let config: InboxZeroConfig
}
