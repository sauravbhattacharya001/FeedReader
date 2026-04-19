//
//  FeedAutopilot.swift
//  FeedReader
//
//  Autonomous reading queue curator that learns user preferences
//  and auto-generates a prioritized daily reading queue within
//  a configurable time budget.
//
//  How it works:
//  1. Observes reading history to build a preference model
//     (preferred topics, feeds, article lengths, reading times)
//  2. Scores unread articles with a weighted multi-factor model
//  3. Selects the best articles that fit within the time budget
//  4. Provides "why" explanations for each pick
//  5. Learns from accept/skip/snooze feedback to improve over time
//
//  Usage:
//  ```
//  let autopilot = FeedAutopilot.shared
//
//  // Configure
//  autopilot.config.dailyTimeBudgetMinutes = 30
//  autopilot.config.diversityWeight = 0.3
//
//  // Train on history
//  autopilot.trainOnHistory(sessions: readingSessions)
//
//  // Generate today's queue
//  let queue = autopilot.generateQueue(from: unreadStories)
//  for pick in queue.picks {
//      print("\(pick.story.title) — \(pick.score) — \(pick.reason)")
//  }
//
//  // Feedback loop
//  autopilot.recordFeedback(.read, for: pick)
//  autopilot.recordFeedback(.skipped, for: otherPick)
//
//  // Insights
//  let profile = autopilot.userProfile()
//  let report = autopilot.generateReport()
//  ```
//
//  All processing is on-device. No network calls.
//

import Foundation

// MARK: - Notifications

extension Notification.Name {
    /// Posted when the autopilot generates a new queue.
    static let autopilotQueueGenerated = Notification.Name("FeedAutopilotQueueGeneratedNotification")
    /// Posted when the preference model is updated from feedback.
    static let autopilotModelUpdated = Notification.Name("FeedAutopilotModelUpdatedNotification")
}

// MARK: - Configuration

/// Autopilot configuration with sensible defaults.
struct AutopilotConfig: Codable {
    /// Daily reading time budget in minutes.
    var dailyTimeBudgetMinutes: Int = 30

    /// Maximum articles in a single queue.
    var maxQueueSize: Int = 15

    /// Minimum article score (0–1) to include.
    var minimumScore: Double = 0.15

    /// How much to value topic diversity (0 = ignore, 1 = maximize).
    var diversityWeight: Double = 0.25

    /// How much to boost articles from feeds with high read-through rate.
    var feedAffinityWeight: Double = 0.30

    /// How much to boost articles matching preferred length.
    var lengthPreferenceWeight: Double = 0.15

    /// How much to value recency.
    var recencyWeight: Double = 0.20

    /// How much to value topic interest.
    var topicInterestWeight: Double = 0.30

    /// Decay factor for older feedback (0–1). Higher = longer memory.
    var feedbackDecay: Double = 0.95

    /// Whether to auto-generate queue at preferred reading time.
    var autoGenerateEnabled: Bool = true

    /// Preferred reading time (hour, 0–23).
    var preferredHour: Int = 8
}

// MARK: - Models

/// Reason why an article was picked.
enum PickReason: String, Codable {
    case topicMatch = "topic_match"
    case feedAffinity = "feed_affinity"
    case trendingTopic = "trending_topic"
    case lengthFit = "length_fit"
    case diversityPick = "diversity_pick"
    case highRecency = "high_recency"
    case strongOverall = "strong_overall"
}

/// User feedback on a pick.
enum PickFeedback: String, Codable {
    case read
    case skipped
    case snoozed
    case loved
}

/// A single scored article pick.
struct AutopilotPick: Codable {
    let storyTitle: String
    let storyURL: String
    let feedName: String
    let score: Double
    let estimatedMinutes: Int
    let reasons: [PickReason]
    let topicTags: [String]
    let timestamp: Date

    /// Human-readable explanation.
    var explanation: String {
        let parts = reasons.map { reason -> String in
            switch reason {
            case .topicMatch: return "matches your interests"
            case .feedAffinity: return "from a feed you read often"
            case .trendingTopic: return "trending topic"
            case .lengthFit: return "fits your preferred length"
            case .diversityPick: return "adds variety"
            case .highRecency: return "just published"
            case .strongOverall: return "strong overall match"
            }
        }
        return parts.joined(separator: ", ")
    }
}

/// A generated reading queue.
struct AutopilotQueue: Codable {
    let picks: [AutopilotPick]
    let generatedAt: Date
    let totalMinutes: Int
    let budgetMinutes: Int
    let articlesConsidered: Int
    let averageScore: Double
    let topicDistribution: [String: Int]

    /// Utilization of time budget (0–1).
    var budgetUtilization: Double {
        guard budgetMinutes > 0 else { return 0 }
        return min(1.0, Double(totalMinutes) / Double(budgetMinutes))
    }
}

/// Feedback record for learning.
struct FeedbackRecord: Codable {
    let storyURL: String
    let feedName: String
    let topics: [String]
    let feedback: PickFeedback
    let score: Double
    let timestamp: Date
}

/// Learned preference profile.
struct PreferenceProfile: Codable {
    var topicScores: [String: Double]
    var feedScores: [String: Double]
    var preferredLengthMinutes: Double
    var lengthTolerance: Double
    var totalFeedbackCount: Int
    var lastUpdated: Date

    /// Top N topics by score.
    func topTopics(_ n: Int = 5) -> [(topic: String, score: Double)] {
        return topicScores
            .sorted { $0.value > $1.value }
            .prefix(n)
            .map { (topic: $0.key, score: $0.value) }
    }

    /// Top N feeds by score.
    func topFeeds(_ n: Int = 5) -> [(feed: String, score: Double)] {
        return feedScores
            .sorted { $0.value > $1.value }
            .prefix(n)
            .map { (feed: $0.key, score: $0.value) }
    }
}

/// Simple story representation for scoring (avoids coupling to Story model).
struct AutopilotArticle {
    let title: String
    let url: String
    let feedName: String
    let publishedDate: Date?
    let wordCount: Int
    let topics: [String]
}

// MARK: - Autopilot Engine

class FeedAutopilot {

    // MARK: - Singleton

    static let shared = FeedAutopilot()

    // MARK: - Properties

    var config = AutopilotConfig()

    private var profile = PreferenceProfile(
        topicScores: [:],
        feedScores: [:],
        preferredLengthMinutes: 5.0,
        lengthTolerance: 3.0,
        totalFeedbackCount: 0,
        lastUpdated: Date()
    )

    private var feedbackHistory: [FeedbackRecord] = []
    private var currentQueue: AutopilotQueue?
    private var queueHistory: [AutopilotQueue] = []

    private let storageKey = "FeedAutopilot"
    private let maxFeedbackHistory = 500
    private let maxQueueHistory = 30

    // MARK: - Init

    private init() {
        load()
    }

    // MARK: - Queue Generation

    /// Generate an optimized reading queue from available articles.
    func generateQueue(from articles: [AutopilotArticle]) -> AutopilotQueue {
        let scored = articles.map { article -> (article: AutopilotArticle, score: Double, reasons: [PickReason]) in
            let (score, reasons) = scoreArticle(article)
            return (article, score, reasons)
        }
        .filter { $0.score >= config.minimumScore }
        .sorted { $0.score > $1.score }

        // Greedy selection: pick highest-scoring articles that fit the budget,
        // with diversity bonus to avoid all picks from one topic.
        var picks: [AutopilotPick] = []
        var remainingMinutes = config.dailyTimeBudgetMinutes
        var topicCounts: [String: Int] = [:]

        for item in scored {
            guard picks.count < config.maxQueueSize else { break }

            let estMinutes = max(1, item.article.wordCount / 200)
            guard estMinutes <= remainingMinutes else { continue }

            // Diversity penalty: reduce effective score if topic is overrepresented.
            let topicPenalty: Double
            if config.diversityWeight > 0 {
                let maxTopicCount = item.article.topics
                    .compactMap { topicCounts[$0] }
                    .max() ?? 0
                topicPenalty = Double(maxTopicCount) * config.diversityWeight * 0.15
            } else {
                topicPenalty = 0
            }

            let adjustedScore = max(0, item.score - topicPenalty)
            guard adjustedScore >= config.minimumScore else { continue }

            var reasons = item.reasons
            let dominantTopic = item.article.topics.first ?? ""
            if (topicCounts[dominantTopic] ?? 0) == 0 && !dominantTopic.isEmpty {
                reasons.append(.diversityPick)
            }

            let pick = AutopilotPick(
                storyTitle: item.article.title,
                storyURL: item.article.url,
                feedName: item.article.feedName,
                score: adjustedScore,
                estimatedMinutes: estMinutes,
                reasons: reasons,
                topicTags: item.article.topics,
                timestamp: Date()
            )

            picks.append(pick)
            remainingMinutes -= estMinutes
            for topic in item.article.topics {
                topicCounts[topic, default: 0] += 1
            }
        }

        let totalMinutes = picks.reduce(0) { $0 + $1.estimatedMinutes }
        let avgScore = picks.isEmpty ? 0 : picks.reduce(0.0) { $0 + $1.score } / Double(picks.count)

        let queue = AutopilotQueue(
            picks: picks,
            generatedAt: Date(),
            totalMinutes: totalMinutes,
            budgetMinutes: config.dailyTimeBudgetMinutes,
            articlesConsidered: articles.count,
            averageScore: avgScore,
            topicDistribution: topicCounts
        )

        currentQueue = queue
        queueHistory.append(queue)
        if queueHistory.count > maxQueueHistory {
            queueHistory.removeFirst(queueHistory.count - maxQueueHistory)
        }

        save()
        NotificationCenter.default.post(name: .autopilotQueueGenerated, object: queue)

        return queue
    }

    // MARK: - Scoring

    /// Score an article against the preference model.
    private func scoreArticle(_ article: AutopilotArticle) -> (score: Double, reasons: [PickReason]) {
        var components: [(weight: Double, value: Double, reason: PickReason)] = []

        // 1. Topic interest
        let topicScore = articleTopicScore(article)
        components.append((config.topicInterestWeight, topicScore, .topicMatch))

        // 2. Feed affinity
        let feedScore = profile.feedScores[article.feedName] ?? 0.5
        components.append((config.feedAffinityWeight, feedScore, .feedAffinity))

        // 3. Length preference fit
        let estMinutes = Double(max(1, article.wordCount / 200))
        let lengthDiff = abs(estMinutes - profile.preferredLengthMinutes)
        let lengthScore = max(0, 1.0 - lengthDiff / max(1, profile.lengthTolerance * 2))
        components.append((config.lengthPreferenceWeight, lengthScore, .lengthFit))

        // 4. Recency
        let recencyScore: Double
        if let pubDate = article.publishedDate {
            let hoursAgo = Date().timeIntervalSince(pubDate) / 3600
            recencyScore = max(0, 1.0 - hoursAgo / 168) // Decays over a week
        } else {
            recencyScore = 0.3
        }
        components.append((config.recencyWeight, recencyScore, .highRecency))

        // Weighted sum
        let totalWeight = components.reduce(0.0) { $0 + $1.weight }
        guard totalWeight > 0 else { return (0, []) }
        let rawScore = components.reduce(0.0) { $0 + $1.weight * $1.value } / totalWeight

        // Determine primary reasons (components scoring above threshold)
        let reasons = components
            .filter { $0.value > 0.6 }
            .sorted { $0.weight * $0.value > $1.weight * $1.value }
            .prefix(3)
            .map { $0.reason }

        let finalReasons = reasons.isEmpty ? [.strongOverall] : Array(reasons)
        return (rawScore, finalReasons)
    }

    /// Average topic score for an article's topics.
    private func articleTopicScore(_ article: AutopilotArticle) -> Double {
        guard !article.topics.isEmpty else { return 0.3 }
        let scores = article.topics.map { profile.topicScores[$0] ?? 0.5 }
        // Use max rather than average so a single strong match counts.
        return scores.max() ?? 0.3
    }

    // MARK: - Feedback & Learning

    /// Record user feedback on a pick to improve the model.
    func recordFeedback(_ feedback: PickFeedback, for pick: AutopilotPick) {
        let record = FeedbackRecord(
            storyURL: pick.storyURL,
            feedName: pick.feedName,
            topics: pick.topicTags,
            feedback: feedback,
            score: pick.score,
            timestamp: Date()
        )

        feedbackHistory.append(record)
        if feedbackHistory.count > maxFeedbackHistory {
            feedbackHistory.removeFirst(feedbackHistory.count - maxFeedbackHistory)
        }

        updateModel(from: record)
        save()

        NotificationCenter.default.post(name: .autopilotModelUpdated, object: nil)
    }

    /// Update preference model from a single feedback signal.
    private func updateModel(from record: FeedbackRecord) {
        let delta: Double
        switch record.feedback {
        case .loved: delta = 0.15
        case .read: delta = 0.05
        case .skipped: delta = -0.08
        case .snoozed: delta = -0.02
        }

        // Update topic scores
        for topic in record.topics {
            let current = profile.topicScores[topic] ?? 0.5
            profile.topicScores[topic] = clamp(current + delta, min: 0, max: 1)
        }

        // Update feed score
        let currentFeed = profile.feedScores[record.feedName] ?? 0.5
        profile.feedScores[record.feedName] = clamp(currentFeed + delta, min: 0, max: 1)

        profile.totalFeedbackCount += 1
        profile.lastUpdated = Date()

        // Apply decay to all scores periodically (every 50 feedback events)
        if profile.totalFeedbackCount % 50 == 0 {
            applyDecay()
        }
    }

    /// Decay all scores toward neutral (0.5) to prevent stale preferences.
    private func applyDecay() {
        let decay = config.feedbackDecay
        for (topic, score) in profile.topicScores {
            profile.topicScores[topic] = 0.5 + (score - 0.5) * decay
        }
        for (feed, score) in profile.feedScores {
            profile.feedScores[feed] = 0.5 + (score - 0.5) * decay
        }
    }

    // MARK: - Training

    /// Batch-train on historical reading sessions.
    /// Each tuple: (feedName, topics, wordCount, readDurationSeconds).
    func trainOnHistory(sessions: [(feedName: String, topics: [String], wordCount: Int, readDurationSeconds: Int)]) {
        guard !sessions.isEmpty else { return }

        // Build frequency-based scores
        var topicFreq: [String: Int] = [:]
        var feedFreq: [String: Int] = [:]
        var totalLengthMinutes: Double = 0
        var count = 0

        for session in sessions {
            for topic in session.topics {
                topicFreq[topic, default: 0] += 1
            }
            feedFreq[session.feedName, default: 0] += 1
            totalLengthMinutes += Double(max(1, session.wordCount / 200))
            count += 1
        }

        // Normalize topic scores
        let maxTopicFreq = Double(topicFreq.values.max() ?? 1)
        for (topic, freq) in topicFreq {
            let normalized = 0.3 + 0.7 * (Double(freq) / maxTopicFreq)
            let existing = profile.topicScores[topic] ?? 0.5
            profile.topicScores[topic] = (existing + normalized) / 2.0
        }

        // Normalize feed scores
        let maxFeedFreq = Double(feedFreq.values.max() ?? 1)
        for (feed, freq) in feedFreq {
            let normalized = 0.3 + 0.7 * (Double(freq) / maxFeedFreq)
            let existing = profile.feedScores[feed] ?? 0.5
            profile.feedScores[feed] = (existing + normalized) / 2.0
        }

        // Update length preference
        if count > 0 {
            let avgLength = totalLengthMinutes / Double(count)
            profile.preferredLengthMinutes = (profile.preferredLengthMinutes + avgLength) / 2.0
        }

        profile.lastUpdated = Date()
        save()
    }

    // MARK: - Profile & Reports

    /// Current user preference profile.
    func userProfile() -> PreferenceProfile {
        return profile
    }

    /// Current queue if one has been generated today.
    func todaysQueue() -> AutopilotQueue? {
        guard let queue = currentQueue else { return nil }
        let calendar = Calendar.current
        if calendar.isDateInToday(queue.generatedAt) {
            return queue
        }
        return nil
    }

    /// Generate a text report of autopilot status.
    func generateReport() -> AutopilotReport {
        let topTopics = profile.topTopics(5)
        let topFeeds = profile.topFeeds(5)

        let recentFeedback = feedbackHistory.suffix(50)
        let readCount = recentFeedback.filter { $0.feedback == .read || $0.feedback == .loved }.count
        let skipCount = recentFeedback.filter { $0.feedback == .skipped }.count
        let acceptRate = recentFeedback.isEmpty ? 0 : Double(readCount) / Double(recentFeedback.count)

        let queueAccuracy: Double
        if let queue = currentQueue, !queue.picks.isEmpty {
            let feedbackURLs = Set(feedbackHistory.suffix(queue.picks.count).map { $0.storyURL })
            let matched = queue.picks.filter { feedbackURLs.contains($0.storyURL) }.count
            queueAccuracy = Double(matched) / Double(queue.picks.count)
        } else {
            queueAccuracy = 0
        }

        return AutopilotReport(
            topTopics: topTopics.map { "\($0.topic): \(String(format: "%.0f%%", $0.score * 100))" },
            topFeeds: topFeeds.map { "\($0.feed): \(String(format: "%.0f%%", $0.score * 100))" },
            acceptRate: acceptRate,
            totalFeedback: profile.totalFeedbackCount,
            recentReads: readCount,
            recentSkips: skipCount,
            queueAccuracy: queueAccuracy,
            preferredLength: profile.preferredLengthMinutes,
            currentBudget: config.dailyTimeBudgetMinutes,
            queuesGenerated: queueHistory.count
        )
    }

    // MARK: - Persistence

    private func save() {
        let data = AutopilotData(
            config: config,
            profile: profile,
            feedbackHistory: feedbackHistory,
            queueHistory: queueHistory
        )
        guard let encoded = try? JSONEncoder().encode(data) else { return }
        UserDefaults.standard.set(encoded, forKey: storageKey)
    }

    private func load() {
        guard let data = UserDefaults.standard.data(forKey: storageKey),
              let decoded = try? JSONDecoder().decode(AutopilotData.self, from: data) else { return }
        config = decoded.config
        profile = decoded.profile
        feedbackHistory = decoded.feedbackHistory
        queueHistory = decoded.queueHistory
        currentQueue = queueHistory.last
    }

    /// Reset all learned preferences and history.
    func reset() {
        profile = PreferenceProfile(
            topicScores: [:],
            feedScores: [:],
            preferredLengthMinutes: 5.0,
            lengthTolerance: 3.0,
            totalFeedbackCount: 0,
            lastUpdated: Date()
        )
        feedbackHistory = []
        queueHistory = []
        currentQueue = nil
        save()
    }

    // MARK: - Helpers

    private func clamp(_ value: Double, min: Double, max: Double) -> Double {
        return Swift.min(max, Swift.max(min, value))
    }
}

// MARK: - Report Model

struct AutopilotReport {
    let topTopics: [String]
    let topFeeds: [String]
    let acceptRate: Double
    let totalFeedback: Int
    let recentReads: Int
    let recentSkips: Int
    let queueAccuracy: Double
    let preferredLength: Double
    let currentBudget: Int
    let queuesGenerated: Int

    /// Summary text.
    var summary: String {
        var lines: [String] = []
        lines.append("📡 Autopilot Report")
        lines.append("━━━━━━━━━━━━━━━━━━━")
        lines.append("")
        lines.append("🎯 Accept Rate: \(String(format: "%.0f%%", acceptRate * 100))")
        lines.append("📊 Total Feedback: \(totalFeedback) (\(recentReads) reads, \(recentSkips) skips recently)")
        lines.append("⏱️ Preferred Length: \(String(format: "%.0f", preferredLength)) min")
        lines.append("🕐 Daily Budget: \(currentBudget) min")
        lines.append("📋 Queues Generated: \(queuesGenerated)")
        lines.append("")
        if !topTopics.isEmpty {
            lines.append("🏷️ Top Topics:")
            for t in topTopics { lines.append("   • \(t)") }
            lines.append("")
        }
        if !topFeeds.isEmpty {
            lines.append("📰 Top Feeds:")
            for f in topFeeds { lines.append("   • \(f)") }
        }
        return lines.joined(separator: "\n")
    }
}

// MARK: - Persistence Model

private struct AutopilotData: Codable {
    let config: AutopilotConfig
    let profile: PreferenceProfile
    let feedbackHistory: [FeedbackRecord]
    let queueHistory: [AutopilotQueue]
}
