//
//  FeedAttentionAllocator.swift
//  FeedReaderCore
//
//  Autonomous attention budget manager that tracks how reading attention
//  is distributed across topics and sources, detects "attention sinks",
//  manages per-topic budgets, and proactively reallocates attention to
//  maximize information diversity and value.
//
//  The allocator detects five types of attention sinks:
//  - Rabbit holes (deep-diving into a single topic excessively)
//  - Doom scrolling (consuming one source for too long)
//  - Echo chambers (reading the same perspective repeatedly)
//  - Novelty traps (shallow scanning across many topics)
//  - Obligation reads (spending time on low-engagement content)
//
//  Usage:
//  ```swift
//  let allocator = FeedAttentionAllocator()
//
//  let report = allocator.analyze(
//      records: attentionRecords,
//      customBudgets: myBudgets     // optional
//  )
//
//  print(report?.diversityScore)      // 0-100 Shannon-based
//  print(report?.attentionEfficiency) // 0-100
//  print(report?.sinks)              // detected attention traps
//  print(report?.reallocations)      // suggested shifts
//  print(report?.overallVerdict)     // human-readable summary
//  ```
//
//  All processing is on-device. No network calls or external deps.
//

import Foundation

// MARK: - Attention Sink Type

/// Classification of attention trap patterns.
public enum AttentionSinkType: String, CaseIterable, Sendable {
    case rabbitHole     = "rabbit_hole"
    case doomScroll     = "doom_scroll"
    case echoChamber    = "echo_chamber"
    case noveltyTrap    = "novelty_trap"
    case obligationRead = "obligation_read"

    /// Emoji representation for display.
    public var emoji: String {
        switch self {
        case .rabbitHole:     return "🕳️"
        case .doomScroll:     return "📱"
        case .echoChamber:    return "🔁"
        case .noveltyTrap:    return "🦋"
        case .obligationRead: return "😩"
        }
    }

    /// Human-readable description.
    public var description: String {
        switch self {
        case .rabbitHole:
            return "Deep-diving into a single topic excessively, losing sight of other areas"
        case .doomScroll:
            return "Consuming content from one source for too long without switching"
        case .echoChamber:
            return "Reading the same perspective repeatedly, missing diverse viewpoints"
        case .noveltyTrap:
            return "Shallow scanning across many topics without meaningful engagement"
        case .obligationRead:
            return "Spending time on content that provides low engagement or value"
        }
    }
}

// MARK: - Attention Severity

/// Severity level for detected attention issues.
public enum AttentionSeverity: Int, Comparable, CaseIterable, Sendable {
    case mild     = 0
    case moderate = 1
    case severe   = 2
    case critical = 3

    public static func < (lhs: AttentionSeverity, rhs: AttentionSeverity) -> Bool {
        return lhs.rawValue < rhs.rawValue
    }

    /// Emoji representation for display.
    public var emoji: String {
        switch self {
        case .mild:     return "🟡"
        case .moderate: return "🟠"
        case .severe:   return "🔴"
        case .critical: return "🚨"
        }
    }

    /// Human-readable label.
    public var label: String {
        switch self {
        case .mild:     return "Mild"
        case .moderate: return "Moderate"
        case .severe:   return "Severe"
        case .critical: return "Critical"
        }
    }
}

// MARK: - Attention Record

/// A single reading attention event.
public struct AttentionRecord: Sendable {
    /// Unique identifier for the article.
    public let articleId: String
    /// Topic/category of the article.
    public let topic: String
    /// Source/feed name.
    public let source: String
    /// Minutes spent reading this article.
    public let minutesSpent: Double
    /// When the reading occurred.
    public let timestamp: Date

    public init(articleId: String, topic: String, source: String,
                minutesSpent: Double, timestamp: Date = Date()) {
        self.articleId = articleId
        self.topic = topic
        self.source = source
        self.minutesSpent = max(0, minutesSpent)
        self.timestamp = timestamp
    }
}

// MARK: - Attention Budget

/// Per-topic or per-source attention budget.
public struct AttentionBudget: Sendable {
    /// Topic or source name.
    public let category: String
    /// Desired maximum minutes per day.
    public let budgetMinutes: Double
    /// Actually consumed minutes.
    public let actualMinutes: Double
    /// Utilization ratio (actual / budget). Values > 1.0 indicate over-budget.
    public var utilizationRatio: Double {
        guard budgetMinutes > 0 else { return actualMinutes > 0 ? Double.infinity : 0 }
        return actualMinutes / budgetMinutes
    }

    public init(category: String, budgetMinutes: Double, actualMinutes: Double) {
        self.category = category
        self.budgetMinutes = max(0, budgetMinutes)
        self.actualMinutes = max(0, actualMinutes)
    }
}

// MARK: - Attention Sink

/// A detected attention trap.
public struct AttentionSink: Sendable {
    /// The category (topic or source) involved.
    public let category: String
    /// Type of sink pattern detected.
    public let sinkType: AttentionSinkType
    /// How severe the issue is.
    public let severity: AttentionSeverity
    /// Estimated minutes lost to this sink.
    public let minutesWasted: Double
    /// Human-readable description of the issue.
    public let description: String
    /// Actionable recommendation.
    public let recommendation: String

    public init(category: String, sinkType: AttentionSinkType,
                severity: AttentionSeverity, minutesWasted: Double,
                description: String, recommendation: String) {
        self.category = category
        self.sinkType = sinkType
        self.severity = severity
        self.minutesWasted = max(0, minutesWasted)
        self.description = description
        self.recommendation = recommendation
    }
}

// MARK: - Attention Reallocation

/// A suggested attention reallocation.
public struct AttentionReallocation: Sendable {
    /// Category to shift attention away from.
    public let fromCategory: String
    /// Category to shift attention toward.
    public let toCategory: String
    /// Minutes to redistribute.
    public let minutesToShift: Double
    /// Reason for the reallocation.
    public let reason: String
    /// Expected improvement in diversity score (0-100).
    public let expectedDiversityGain: Double

    public init(fromCategory: String, toCategory: String,
                minutesToShift: Double, reason: String,
                expectedDiversityGain: Double) {
        self.fromCategory = fromCategory
        self.toCategory = toCategory
        self.minutesToShift = max(0, minutesToShift)
        self.reason = reason
        self.expectedDiversityGain = min(100, max(0, expectedDiversityGain))
    }
}

// MARK: - Attention Report

/// Complete attention analysis output.
public struct AttentionReport: Sendable {
    /// All input records.
    public let records: [AttentionRecord]
    /// Computed budgets.
    public let budgets: [AttentionBudget]
    /// Detected attention sinks.
    public let sinks: [AttentionSink]
    /// Suggested reallocations.
    public let reallocations: [AttentionReallocation]
    /// Topic diversity score (0-100, Shannon entropy based).
    public let diversityScore: Double
    /// Attention efficiency score (0-100).
    public let attentionEfficiency: Double
    /// Top 5 time-consuming categories.
    public let topConsumers: [(category: String, minutes: Double)]
    /// Topics with budget but zero actual reading.
    public let neglectedTopics: [String]
    /// Human-readable overall verdict.
    public let overallVerdict: String
    /// Actionable recommendations.
    public let recommendations: [String]
    /// When the report was generated.
    public let generatedAt: Date
}

// MARK: - FeedAttentionAllocator

/// Autonomous attention budget manager.
///
/// Tracks how reading attention is distributed across topics and sources,
/// detects attention sinks, and proactively suggests reallocations to
/// maximize information diversity and reading value.
public final class FeedAttentionAllocator: @unchecked Sendable {

    // MARK: - Configuration

    /// Default daily reading budget in minutes.
    public var defaultDailyBudgetMinutes: Double = 60.0

    /// Ratio threshold above which a single topic is flagged as a potential sink.
    /// For example, 0.35 means any topic consuming > 35% of total time is suspicious.
    public var sinkThresholdRatio: Double = 0.35

    /// Weight given to diversity in efficiency calculations (0-1).
    public var diversityWeight: Double = 0.6

    /// Minimum number of records required to produce a meaningful analysis.
    public var minRecordsForAnalysis: Int = 5

    // MARK: - Initialization

    public init() {}

    // MARK: - Main Analysis

    /// Analyze attention records and produce a comprehensive report.
    ///
    /// - Parameters:
    ///   - records: Array of attention records to analyze.
    ///   - customBudgets: Optional per-topic budgets. If nil, budgets are derived
    ///     by splitting `defaultDailyBudgetMinutes` evenly across detected topics.
    /// - Returns: An `AttentionReport`, or `nil` if there are fewer than
    ///   `minRecordsForAnalysis` records.
    public func analyze(records: [AttentionRecord],
                        customBudgets: [AttentionBudget]? = nil) -> AttentionReport? {
        guard records.count >= minRecordsForAnalysis else { return nil }

        // 1. Aggregate minutes per topic and per source
        let topicMinutes = aggregateMinutes(records: records, by: \.topic)
        let sourceMinutes = aggregateMinutes(records: records, by: \.source)
        let totalMinutes = topicMinutes.values.reduce(0, +)

        // 2. Compute article counts per topic
        let topicArticleCounts = aggregateCounts(records: records, by: \.topic)

        // 3. Compute budgets
        let budgets: [AttentionBudget]
        if let custom = customBudgets, !custom.isEmpty {
            budgets = mergeBudgets(custom: custom, topicMinutes: topicMinutes)
        } else {
            budgets = deriveBudgets(topicMinutes: topicMinutes)
        }

        // 4. Detect sinks
        let sinks = detectSinks(topicMinutes: topicMinutes,
                                sourceMinutes: sourceMinutes,
                                topicArticleCounts: topicArticleCounts,
                                totalMinutes: totalMinutes,
                                recordCount: records.count)

        // 5. Generate reallocations
        let reallocations = generateReallocations(budgets: budgets, sinks: sinks)

        // 6. Diversity score
        let diversityScore = computeDiversityScore(topicMinutes: topicMinutes)

        // 7. Efficiency
        let attentionEfficiency = computeEfficiency(budgets: budgets)

        // 8. Top consumers (top 5)
        let topConsumers = topicMinutes
            .sorted { $0.value > $1.value }
            .prefix(5)
            .map { (category: $0.key, minutes: $0.value) }

        // 9. Neglected topics — topics in budget but with 0 actual minutes
        let neglectedTopics = budgets
            .filter { $0.actualMinutes == 0 }
            .map { $0.category }
            .sorted()

        // 10. Verdict and recommendations
        let verdict = generateVerdict(diversityScore: diversityScore,
                                       efficiency: attentionEfficiency,
                                       sinks: sinks)
        let recommendations = generateRecommendations(
            sinks: sinks, budgets: budgets,
            diversityScore: diversityScore,
            neglectedTopics: neglectedTopics)

        return AttentionReport(
            records: records,
            budgets: budgets,
            sinks: sinks,
            reallocations: reallocations,
            diversityScore: diversityScore,
            attentionEfficiency: attentionEfficiency,
            topConsumers: topConsumers,
            neglectedTopics: neglectedTopics,
            overallVerdict: verdict,
            recommendations: recommendations,
            generatedAt: Date()
        )
    }

    // MARK: - Aggregation

    private func aggregateMinutes(records: [AttentionRecord],
                                   by keyPath: KeyPath<AttentionRecord, String>) -> [String: Double] {
        var result: [String: Double] = [:]
        for record in records {
            let key = record[keyPath: keyPath]
            result[key, default: 0] += record.minutesSpent
        }
        return result
    }

    private func aggregateCounts(records: [AttentionRecord],
                                  by keyPath: KeyPath<AttentionRecord, String>) -> [String: Int] {
        var result: [String: Int] = [:]
        for record in records {
            let key = record[keyPath: keyPath]
            result[key, default: 0] += 1
        }
        return result
    }

    // MARK: - Budget Computation

    private func deriveBudgets(topicMinutes: [String: Double]) -> [AttentionBudget] {
        let topicCount = max(1, topicMinutes.count)
        let perTopicBudget = defaultDailyBudgetMinutes / Double(topicCount)
        return topicMinutes.map { topic, actual in
            AttentionBudget(category: topic, budgetMinutes: perTopicBudget, actualMinutes: actual)
        }.sorted { $0.category < $1.category }
    }

    private func mergeBudgets(custom: [AttentionBudget],
                               topicMinutes: [String: Double]) -> [AttentionBudget] {
        let customMap = Dictionary(custom.map { ($0.category, $0.budgetMinutes) },
                                    uniquingKeysWith: { first, _ in first })

        var allTopics = Set(topicMinutes.keys)
        for key in customMap.keys { allTopics.insert(key) }

        return allTopics.map { topic in
            let budget = customMap[topic] ?? (defaultDailyBudgetMinutes / Double(max(1, allTopics.count)))
            let actual = topicMinutes[topic] ?? 0
            return AttentionBudget(category: topic, budgetMinutes: budget, actualMinutes: actual)
        }.sorted { $0.category < $1.category }
    }

    // MARK: - Sink Detection

    /// Detect attention sinks across topics and sources.
    public func detectSinks(topicMinutes: [String: Double],
                            sourceMinutes: [String: Double],
                            topicArticleCounts: [String: Int],
                            totalMinutes: Double,
                            recordCount: Int) -> [AttentionSink] {
        guard totalMinutes > 0 else { return [] }

        var sinks: [AttentionSink] = []

        // Rabbit Hole: >sinkThresholdRatio of total time on one topic AND >3 articles
        for (topic, minutes) in topicMinutes {
            let ratio = minutes / totalMinutes
            let articleCount = topicArticleCounts[topic] ?? 0
            if ratio > sinkThresholdRatio && articleCount > 3 {
                let severity = severityForRatio(ratio)
                let wasted = minutes - (totalMinutes * sinkThresholdRatio)
                sinks.append(AttentionSink(
                    category: topic,
                    sinkType: .rabbitHole,
                    severity: severity,
                    minutesWasted: max(0, wasted),
                    description: "Spent \(String(format: "%.1f", minutes)) min (\(String(format: "%.0f", ratio * 100))%) on '\(topic)' across \(articleCount) articles",
                    recommendation: "Set a \(String(format: "%.0f", totalMinutes * 0.25)) min cap on '\(topic)' and explore other topics"
                ))
            }
        }

        // Doom Scroll: single source > 40% of total time
        for (source, minutes) in sourceMinutes {
            let ratio = minutes / totalMinutes
            if ratio > 0.4 {
                let severity = severityForRatio(ratio)
                let wasted = minutes - (totalMinutes * 0.4)
                sinks.append(AttentionSink(
                    category: source,
                    sinkType: .doomScroll,
                    severity: severity,
                    minutesWasted: max(0, wasted),
                    description: "Consumed \(String(format: "%.1f", minutes)) min (\(String(format: "%.0f", ratio * 100))%) from '\(source)'",
                    recommendation: "Diversify sources — try reading from at least 3 different feeds"
                ))
            }
        }

        // Echo Chamber: >60% of articles from one topic AND diversity < 40
        let diversityScore = computeDiversityScore(topicMinutes: topicMinutes)
        for (topic, count) in topicArticleCounts {
            let articleRatio = Double(count) / Double(max(1, recordCount))
            if articleRatio > 0.6 && diversityScore < 40 {
                let minutes = topicMinutes[topic] ?? 0
                sinks.append(AttentionSink(
                    category: topic,
                    sinkType: .echoChamber,
                    severity: .severe,
                    minutesWasted: minutes * 0.3,
                    description: "\(String(format: "%.0f", articleRatio * 100))% of articles are about '\(topic)' with diversity score \(String(format: "%.0f", diversityScore))",
                    recommendation: "Add feeds from opposing viewpoints or different domains"
                ))
            }
        }

        // Novelty Trap: many topics with <2 min each indicating shallow scanning
        let shallowTopics = topicMinutes.filter { $0.value < 2.0 }
        if shallowTopics.count >= 4 {
            let totalShallow = shallowTopics.values.reduce(0, +)
            sinks.append(AttentionSink(
                category: "Multiple Topics",
                sinkType: .noveltyTrap,
                severity: shallowTopics.count >= 6 ? .moderate : .mild,
                minutesWasted: totalShallow * 0.5,
                description: "\(shallowTopics.count) topics received less than 2 min each — possible shallow scanning",
                recommendation: "Pick 2-3 topics that interest you most and spend quality time on them"
            ))
        }

        // Obligation Read: topic with high time but low engagement (many short reads)
        for (topic, minutes) in topicMinutes {
            let count = topicArticleCounts[topic] ?? 0
            guard count >= 5 else { continue }
            let avgMinutes = minutes / Double(count)
            // High total time but very short avg = skimming through obligations
            if minutes > totalMinutes * 0.2 && avgMinutes < 1.5 {
                sinks.append(AttentionSink(
                    category: topic,
                    sinkType: .obligationRead,
                    severity: .moderate,
                    minutesWasted: minutes * 0.4,
                    description: "Spent \(String(format: "%.1f", minutes)) min on '\(topic)' but avg only \(String(format: "%.1f", avgMinutes)) min/article — possible obligation reading",
                    recommendation: "Consider unsubscribing from '\(topic)' feeds or muting this topic"
                ))
            }
        }

        return sinks.sorted { $0.minutesWasted > $1.minutesWasted }
    }

    private func severityForRatio(_ ratio: Double) -> AttentionSeverity {
        switch ratio {
        case 0..<0.4:  return .mild
        case 0.4..<0.6: return .moderate
        case 0.6..<0.8: return .severe
        default:        return .critical
        }
    }

    // MARK: - Reallocation

    /// Generate suggested reallocations from over-budget to under-budget categories.
    public func generateReallocations(budgets: [AttentionBudget],
                                      sinks: [AttentionSink]) -> [AttentionReallocation] {
        let overBudget = budgets.filter { $0.utilizationRatio > 1.2 }
            .sorted { $0.utilizationRatio > $1.utilizationRatio }
        let underBudget = budgets.filter { $0.utilizationRatio < 0.5 }
            .sorted { $0.utilizationRatio < $1.utilizationRatio }

        guard !overBudget.isEmpty && !underBudget.isEmpty else { return [] }

        var reallocations: [AttentionReallocation] = []
        var underIdx = 0

        for over in overBudget {
            guard underIdx < underBudget.count else { break }
            let excess = over.actualMinutes - over.budgetMinutes
            guard excess > 0 else { continue }

            let under = underBudget[underIdx]
            let deficit = under.budgetMinutes - under.actualMinutes
            let shiftAmount = min(excess, max(deficit, 1.0))

            // Estimate diversity gain: shifting from dominant to neglected improves entropy
            let gain = min(100, shiftAmount / max(1, over.actualMinutes) * 100 * 0.8)

            let sinkInfo = sinks.first { $0.category == over.category }
            let reason: String
            if let sink = sinkInfo {
                reason = "\(sink.sinkType.emoji) \(over.category) is a \(sink.sinkType.rawValue) sink — redirect to \(under.category)"
            } else {
                reason = "\(over.category) is \(String(format: "%.0f", (over.utilizationRatio - 1) * 100))% over budget — \(under.category) needs attention"
            }

            reallocations.append(AttentionReallocation(
                fromCategory: over.category,
                toCategory: under.category,
                minutesToShift: shiftAmount,
                reason: reason,
                expectedDiversityGain: gain
            ))

            underIdx += 1
        }

        return reallocations
    }

    // MARK: - Diversity Score

    /// Compute Shannon entropy-based diversity score (0-100).
    ///
    /// Formula: H = -Σ(pᵢ × log₂(pᵢ)) normalized by log₂(N)
    /// where pᵢ is the proportion of time on topic i and N is topic count.
    public func computeDiversityScore(topicMinutes: [String: Double]) -> Double {
        let total = topicMinutes.values.reduce(0, +)
        guard total > 0, topicMinutes.count > 1 else { return 0 }

        var entropy: Double = 0
        for (_, minutes) in topicMinutes {
            let p = minutes / total
            if p > 0 {
                entropy -= p * log2(p)
            }
        }

        let maxEntropy = log2(Double(topicMinutes.count))
        guard maxEntropy > 0 else { return 0 }

        return min(100, max(0, (entropy / maxEntropy) * 100))
    }

    // MARK: - Efficiency

    /// Compute attention efficiency (0-100).
    ///
    /// Perfect efficiency means every budget is at exactly 100% utilization.
    /// Score = average of (1 - |utilization - 1|) clamped to [0, 1], scaled to 100.
    public func computeEfficiency(budgets: [AttentionBudget]) -> Double {
        guard !budgets.isEmpty else { return 0 }

        let scores = budgets.map { budget -> Double in
            let deviation = abs(budget.utilizationRatio - 1.0)
            return max(0, 1.0 - deviation)
        }

        let avg = scores.reduce(0, +) / Double(scores.count)
        return min(100, max(0, avg * 100))
    }

    // MARK: - Verdict & Recommendations

    private func generateVerdict(diversityScore: Double,
                                  efficiency: Double,
                                  sinks: [AttentionSink]) -> String {
        let criticalSinks = sinks.filter { $0.severity == .critical }
        let severeSinks = sinks.filter { $0.severity == .severe }

        if !criticalSinks.isEmpty {
            return "🚨 Critical attention imbalance detected — \(criticalSinks.count) critical sink(s) require immediate attention"
        }
        if !severeSinks.isEmpty {
            return "🔴 Significant attention issues — \(severeSinks.count) severe sink(s) found. Rebalancing recommended"
        }
        if diversityScore < 30 {
            return "🟠 Low diversity (score: \(String(format: "%.0f", diversityScore))) — reading is concentrated in too few areas"
        }
        if efficiency < 40 {
            return "🟠 Poor budget adherence (efficiency: \(String(format: "%.0f", efficiency))%) — attention budgets need adjustment"
        }
        if diversityScore > 70 && efficiency > 60 && sinks.isEmpty {
            return "✅ Excellent attention balance — diverse reading with good budget adherence"
        }
        if diversityScore > 50 && efficiency > 50 {
            return "🟡 Decent attention balance — some room for improvement in diversity and focus"
        }
        return "🟡 Mixed attention health — review sinks and consider rebalancing"
    }

    private func generateRecommendations(sinks: [AttentionSink],
                                          budgets: [AttentionBudget],
                                          diversityScore: Double,
                                          neglectedTopics: [String]) -> [String] {
        var recs: [String] = []

        // Sink-based recommendations
        for sink in sinks.prefix(3) {
            recs.append("\(sink.sinkType.emoji) \(sink.recommendation)")
        }

        // Diversity recommendations
        if diversityScore < 30 {
            recs.append("📊 Diversity score is very low (\(String(format: "%.0f", diversityScore))). Try adding feeds from 2-3 new topic areas")
        } else if diversityScore < 50 {
            recs.append("📊 Diversity could improve (\(String(format: "%.0f", diversityScore))). Consider exploring one new topic this week")
        }

        // Neglected topics
        if !neglectedTopics.isEmpty {
            let topicList = neglectedTopics.prefix(3).joined(separator: ", ")
            recs.append("👻 Neglected topics: \(topicList) — schedule short reading sessions for these")
        }

        // Over-budget warnings
        let heavilyOver = budgets.filter { $0.utilizationRatio > 2.0 }
        for budget in heavilyOver.prefix(2) {
            recs.append("⚠️ '\(budget.category)' is at \(String(format: "%.0f", budget.utilizationRatio * 100))% of budget — set a timer or use reading limits")
        }

        return recs
    }
}
