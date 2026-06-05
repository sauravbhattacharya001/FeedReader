//
//  FeedArticleStalenessDetector.swift
//  FeedReaderCore
//
//  Agentic advisor that identifies stale articles in the user's unread
//  queue - stories superseded by newer coverage, time-sensitive posts
//  whose window has passed, or items that have aged beyond practical
//  relevance - and recommends archive / deprioritize / mark-read actions
//  so the reader's backlog stays fresh and actionable.
//
//  Distinct from FeedReadingFatigueAdvisor (reader cognitive state),
//  FeedSubscriptionROI (feed-level value), and FeedContentCalendar
//  (scheduling). This advisor is article-centric: it answers "which
//  specific unread items should I skip or archive right now?"
//
//  Key capabilities:
//  - 6 staleness signals per article: age, supersession (newer article
//    from same feed with overlapping keywords), event-window expiry,
//    topic saturation, source-has-correction, and declining relevance
//    (topic interest vs. age decay)
//  - 0..100 composite stalenessScore per article, A..F grade
//  - 5 verdict tiers (expired / stale / fading / watchlist / fresh)
//  - P0-P3 prioritized playbook with blast-radius + reversibility
//  - Risk appetite knob (cautious / balanced / aggressive)
//  - Deterministic given a fixed now closure; never mutates inputs
//  - text / markdown / byte-stable JSON renderers
//
//  All processing is on-device. Foundation only - no UIKit, no network.
//

import Foundation

// MARK: - Risk Appetite

/// Controls how aggressively the detector recommends purging stale articles.
public enum StalenessRiskAppetite: String, Sendable, CaseIterable {
    /// Conservative - only flag obviously expired items.
    case cautious
    /// Default - balanced freshness vs. potential relevance.
    case balanced
    /// Aggressive - actively prune anything showing age signals.
    case aggressive

    var multiplier: Double {
        switch self {
        case .cautious:  return 0.85
        case .balanced:  return 1.0
        case .aggressive: return 1.15
        }
    }
}

// MARK: - Input Model

/// An unread article in the user's reading queue.
public struct UnreadArticle: Sendable, Equatable {
    /// Unique article identifier.
    public let id: String
    /// Article title.
    public let title: String
    /// Feed this article belongs to.
    public let feedName: String
    /// Publication date.
    public let publishedAt: Date
    /// Lowercased topic/keyword tags.
    public let keywords: [String]
    /// Whether the article references a time-bounded event.
    public let isTimeSensitive: Bool
    /// Optional event date for time-sensitive articles.
    public let eventDate: Date?
    /// Whether the source has published a correction/update referencing this article.
    public let hasCorrection: Bool
    /// User's interest level in the article's primary topic (0..1).
    public let topicInterest: Double

    public init(
        id: String,
        title: String,
        feedName: String,
        publishedAt: Date,
        keywords: [String] = [],
        isTimeSensitive: Bool = false,
        eventDate: Date? = nil,
        hasCorrection: Bool = false,
        topicInterest: Double = 0.5
    ) {
        self.id = id
        self.title = title
        self.feedName = feedName
        self.publishedAt = publishedAt
        self.keywords = keywords.map { $0.lowercased() }
        self.isTimeSensitive = isTimeSensitive
        self.eventDate = eventDate
        self.hasCorrection = hasCorrection
        self.topicInterest = max(0, min(1, topicInterest))
    }
}

// MARK: - Output Models

/// Staleness verdict for a single article.
public enum StalenessVerdict: String, Sendable, CaseIterable {
    case expired
    case stale
    case fading
    case watchlist
    case fresh
}

/// Reason a staleness signal fired for an article.
public enum StalenessReason: String, Sendable, CaseIterable {
    case aged
    case superseded
    case eventExpired
    case topicSaturated
    case correctionIssued
    case interestDecayed
    case insufficientData
}

/// Grade for overall backlog freshness.
public enum BacklogGrade: String, Sendable, CaseIterable {
    case A, B, C, D, F
}

/// Analysis result for one article.
public struct ArticleStalenessResult: Sendable {
    public let articleId: String
    public let title: String
    public let feedName: String
    public let stalenessScore: Int
    public let verdict: StalenessVerdict
    public let priority: Int
    public let reasons: [StalenessReason]
    public let ageHours: Double
    public let recommendedAction: String
}

/// A playbook action recommendation.
public struct StalenessAction: Sendable {
    public let id: String
    public let priority: Int
    public let label: String
    public let reason: String
    public let owner: String
    public let blastRadius: Int
    public let reversibility: String
    public let articleIds: [String]
}

/// An insight about the overall backlog.
public enum StalenessInsight: String, Sendable {
    case backlogFresh = "BACKLOG_FRESH"
    case agingBacklog = "AGING_BACKLOG"
    case eventArticlesExpired = "EVENT_ARTICLES_EXPIRED"
    case topicPileup = "TOPIC_PILEUP"
    case correctionsPresent = "CORRECTIONS_PRESENT"
    case heavilySuperseded = "HEAVILY_SUPERSEDED"
    case emptyQueue = "EMPTY_QUEUE"
    case mixedFreshness = "MIXED_FRESHNESS"
}

/// Full analysis report.
public struct StalenessReport: Sendable {
    /// Per-article results sorted by staleness score descending.
    public let results: [ArticleStalenessResult]
    /// Overall backlog staleness score (mean of top-3 or all if fewer).
    public let backlogScore: Int
    /// Grade A..F.
    public let grade: BacklogGrade
    /// Headline summary.
    public let headline: String
    /// Priority-sorted playbook actions.
    public let playbook: [StalenessAction]
    /// Cross-article insights.
    public let insights: [StalenessInsight]
    /// Article IDs recommended for archiving (expired + stale verdicts).
    public let archiveCandidateIds: [String]

    /// Plain text summary.
    public func renderText() -> String {
        var lines: [String] = []
        lines.append(headline)
        lines.append("")
        lines.append("Grade: \(grade.rawValue) | Backlog Score: \(backlogScore)/100")
        lines.append("Articles: \(results.count) | Archive Candidates: \(archiveCandidateIds.count)")
        lines.append("")
        if !results.isEmpty {
            lines.append("--- Articles ---")
            for r in results {
                let reasons = r.reasons.map(\.rawValue).joined(separator: ", ")
                lines.append("[\(r.verdict.rawValue.uppercased())] \(r.title) (score=\(r.stalenessScore), \(reasons))")
            }
            lines.append("")
        }
        if !playbook.isEmpty {
            lines.append("--- Playbook ---")
            for a in playbook {
                lines.append("P\(a.priority): \(a.label) - \(a.reason)")
            }
            lines.append("")
        }
        lines.append("Insights: \(insights.map(\.rawValue).joined(separator: ", "))")
        return lines.joined(separator: "\n")
    }

    /// Markdown tables.
    public func renderMarkdown() -> String {
        var lines: [String] = []
        lines.append("## Summary")
        lines.append("")
        lines.append("| Metric | Value |")
        lines.append("|--------|-------|")
        lines.append("| Grade | \(grade.rawValue) |")
        lines.append("| Backlog Score | \(backlogScore)/100 |")
        lines.append("| Total Articles | \(results.count) |")
        lines.append("| Archive Candidates | \(archiveCandidateIds.count) |")
        lines.append("")
        if !results.isEmpty {
            lines.append("## Articles")
            lines.append("")
            lines.append("| Title | Feed | Score | Verdict | Reasons | Action |")
            lines.append("|-------|------|-------|---------|---------|--------|")
            for r in results {
                let reasons = r.reasons.map(\.rawValue).joined(separator: ", ")
                let escaped = r.title.replacingOccurrences(of: "|", with: "\\|")
                lines.append("| \(escaped) | \(r.feedName) | \(r.stalenessScore) | \(r.verdict.rawValue) | \(reasons) | \(r.recommendedAction) |")
            }
            lines.append("")
        }
        if !playbook.isEmpty {
            lines.append("## Playbook")
            lines.append("")
            lines.append("| Priority | Action | Reason | Owner | Blast | Reversibility |")
            lines.append("|----------|--------|--------|-------|-------|---------------|")
            for a in playbook {
                lines.append("| P\(a.priority) | \(a.label) | \(a.reason) | \(a.owner) | \(a.blastRadius) | \(a.reversibility) |")
            }
            lines.append("")
        }
        lines.append("## Insights")
        lines.append("")
        for i in insights {
            lines.append("- \(i.rawValue)")
        }
        return lines.joined(separator: "\n")
    }

    /// Byte-stable JSON (sorted keys, 2-space indent).
    public func renderJSON() -> String {
        var dict: [String: Any] = [:]
        dict["archiveCandidateIds"] = archiveCandidateIds.sorted()
        dict["backlogScore"] = backlogScore
        dict["grade"] = grade.rawValue
        dict["headline"] = headline
        dict["insights"] = insights.map(\.rawValue).sorted()
        let playbookArr = playbook.map { a -> [String: Any] in
            [
                "articleIds": a.articleIds.sorted(),
                "blastRadius": a.blastRadius,
                "id": a.id,
                "label": a.label,
                "owner": a.owner,
                "priority": a.priority,
                "reason": a.reason,
                "reversibility": a.reversibility
            ]
        }
        dict["playbook"] = playbookArr
        let resultsArr = results.map { r -> [String: Any] in
            [
                "ageHours": Int(r.ageHours),
                "articleId": r.articleId,
                "feedName": r.feedName,
                "priority": r.priority,
                "reasons": r.reasons.map(\.rawValue).sorted(),
                "recommendedAction": r.recommendedAction,
                "stalenessScore": r.stalenessScore,
                "title": r.title,
                "verdict": r.verdict.rawValue
            ]
        }
        dict["results"] = resultsArr
        return StalenessReport.stableJSON(dict)
    }

    static func stableJSON(_ value: Any, indent: Int = 0) -> String {
        let pad = String(repeating: "  ", count: indent)
        let innerPad = String(repeating: "  ", count: indent + 1)
        if let dict = value as? [String: Any] {
            if dict.isEmpty { return "{}" }
            let keys = dict.keys.sorted()
            var lines: [String] = ["{"]
            for (i, key) in keys.enumerated() {
                let val = stableJSON(dict[key]!, indent: indent + 1)
                let comma = i < keys.count - 1 ? "," : ""
                lines.append("\(innerPad)\"\(escapeJSON(key))\": \(val)\(comma)")
            }
            lines.append("\(pad)}")
            return lines.joined(separator: "\n")
        } else if let arr = value as? [Any] {
            if arr.isEmpty { return "[]" }
            var lines: [String] = ["["]
            for (i, elem) in arr.enumerated() {
                let val = stableJSON(elem, indent: indent + 1)
                let comma = i < arr.count - 1 ? "," : ""
                lines.append("\(innerPad)\(val)\(comma)")
            }
            lines.append("\(pad)]")
            return lines.joined(separator: "\n")
        } else if let s = value as? String {
            return "\"\(escapeJSON(s))\""
        } else if let n = value as? Int {
            return "\(n)"
        } else if let d = value as? Double {
            return "\(d)"
        } else if let b = value as? Bool {
            return b ? "true" : "false"
        }
        return "null"
    }

    private static func escapeJSON(_ s: String) -> String {
        s.replacingOccurrences(of: "\\", with: "\\\\")
         .replacingOccurrences(of: "\"", with: "\\\"")
         .replacingOccurrences(of: "\n", with: "\\n")
         .replacingOccurrences(of: "\r", with: "\\r")
         .replacingOccurrences(of: "\t", with: "\\t")
    }
}

// MARK: - Detector

/// Agentic staleness detector for unread article queues.
public final class FeedArticleStalenessDetector: @unchecked Sendable {

    /// Risk appetite controlling aggressiveness of staleness flagging.
    public var riskAppetite: StalenessRiskAppetite = .balanced

    /// Age threshold in days before the aged signal fires.
    public var ageThresholdDays: Double = 7.0

    /// Keyword overlap fraction (0..1) to trigger superseded.
    public var supersessionOverlap: Double = 0.5

    /// Maximum articles on the same topic before topicSaturated fires.
    public var topicSaturationThreshold: Int = 4

    /// Interest level below which interestDecayed fires.
    public var interestDecayFloor: Double = 0.3

    private let nowProvider: () -> Date

    /// Creates a detector with an injectable clock for deterministic testing.
    public init(now: @escaping () -> Date) {
        self.nowProvider = now
    }

    // MARK: - Analysis

    /// Analyzes the unread queue and produces a staleness report.
    /// Never mutates the input array.
    public func analyze(articles: [UnreadArticle]) -> StalenessReport {
        let now = nowProvider()
        let items = articles

        if items.isEmpty {
            return StalenessReport(
                results: [],
                backlogScore: 0,
                grade: .A,
                headline: "VERDICT: grade=A articles=0 backlogScore=0",
                playbook: [],
                insights: [.emptyQueue],
                archiveCandidateIds: []
            )
        }

        // Pre-compute topic frequency for saturation detection
        var topicCounts: [String: Int] = [:]
        for article in items {
            for kw in article.keywords {
                topicCounts[kw, default: 0] += 1
            }
        }

        // Per-feed article grouping (for supersession)
        var feedArticles: [String: [UnreadArticle]] = [:]
        for article in items {
            feedArticles[article.feedName, default: []].append(article)
        }

        // Analyze each article
        var results: [ArticleStalenessResult] = []
        for article in items {
            let result = analyzeArticle(article, now: now, topicCounts: topicCounts, feedArticles: feedArticles)
            results.append(result)
        }

        // Sort by staleness score descending
        results.sort { $0.stalenessScore > $1.stalenessScore }

        // Portfolio score = mean of top-3 (or all if < 3)
        let topN = min(3, results.count)
        let backlogScore = results.prefix(topN).reduce(0) { $0 + $1.stalenessScore } / topN

        // Grade
        let grade = computeGrade(backlogScore: backlogScore, results: results)

        // Archive candidates
        let archiveIds = results
            .filter { $0.verdict == .expired || $0.verdict == .stale }
            .map(\.articleId)

        // Insights
        let insights = computeInsights(results: results)

        // Playbook
        let playbook = computePlaybook(results: results, grade: grade)

        let p0 = results.filter { $0.priority == 0 }.count
        let p1 = results.filter { $0.priority == 1 }.count
        let headline = "VERDICT: grade=\(grade.rawValue) articles=\(results.count) P0=\(p0) P1=\(p1) backlogScore=\(backlogScore)"

        return StalenessReport(
            results: results,
            backlogScore: backlogScore,
            grade: grade,
            headline: headline,
            playbook: playbook,
            insights: insights,
            archiveCandidateIds: archiveIds
        )
    }

    // MARK: - Per-Article Analysis

    private func analyzeArticle(
        _ article: UnreadArticle,
        now: Date,
        topicCounts: [String: Int],
        feedArticles: [String: [UnreadArticle]]
    ) -> ArticleStalenessResult {
        let ageHours = now.timeIntervalSince(article.publishedAt) / 3600.0
        let ageDays = ageHours / 24.0

        var rawScore: Double = 0
        var reasons: [StalenessReason] = []

        // Signal 1: Age
        if ageDays >= ageThresholdDays {
            let ageContrib = min(40.0, 15.0 + (ageDays - ageThresholdDays) * 2.5)
            rawScore += ageContrib
            reasons.append(.aged)
        }

        // Signal 2: Supersession
        if let siblings = feedArticles[article.feedName] {
            let newerSiblings = siblings.filter { $0.publishedAt > article.publishedAt && $0.id != article.id }
            for newer in newerSiblings {
                if !article.keywords.isEmpty && !newer.keywords.isEmpty {
                    let overlap = Set(article.keywords).intersection(Set(newer.keywords))
                    let overlapFraction = Double(overlap.count) / Double(article.keywords.count)
                    if overlapFraction >= supersessionOverlap {
                        rawScore += 25.0
                        reasons.append(.superseded)
                        break
                    }
                }
            }
        }

        // Signal 3: Event window expired
        if article.isTimeSensitive {
            if let eventDate = article.eventDate, eventDate < now {
                rawScore += 35.0
                reasons.append(.eventExpired)
            } else if article.eventDate == nil && ageDays >= 3.0 {
                rawScore += 20.0
                reasons.append(.eventExpired)
            }
        }

        // Signal 4: Topic saturation
        let maxTopicCount = article.keywords.map { topicCounts[$0, default: 0] }.max() ?? 0
        if maxTopicCount >= topicSaturationThreshold {
            rawScore += 15.0
            reasons.append(.topicSaturated)
        }

        // Signal 5: Correction issued
        if article.hasCorrection {
            rawScore += 30.0
            reasons.append(.correctionIssued)
        }

        // Signal 6: Interest decay
        if article.topicInterest < interestDecayFloor {
            rawScore += 20.0
            reasons.append(.interestDecayed)
        }

        // Insufficient data check
        if article.keywords.isEmpty && ageDays < 1.0 {
            reasons = [.insufficientData]
            rawScore = 0
        }

        // Apply risk appetite
        rawScore *= riskAppetite.multiplier
        let finalScore = min(100, max(0, Int(rawScore)))

        // Verdict
        let verdict: StalenessVerdict
        let priority: Int
        if finalScore >= 75 {
            verdict = .expired
            priority = 0
        } else if finalScore >= 50 {
            verdict = .stale
            priority = 1
        } else if finalScore >= 30 {
            verdict = .fading
            priority = 2
        } else if finalScore >= 15 {
            verdict = .watchlist
            priority = 3
        } else {
            verdict = .fresh
            priority = 3
        }

        let action: String
        switch verdict {
        case .expired: action = "archive"
        case .stale: action = "archive_or_skim"
        case .fading: action = "deprioritize"
        case .watchlist: action = "monitor"
        case .fresh: action = "keep"
        }

        return ArticleStalenessResult(
            articleId: article.id,
            title: article.title,
            feedName: article.feedName,
            stalenessScore: finalScore,
            verdict: verdict,
            priority: priority,
            reasons: reasons,
            ageHours: ageHours,
            recommendedAction: action
        )
    }

    // MARK: - Grade

    private func computeGrade(backlogScore: Int, results: [ArticleStalenessResult]) -> BacklogGrade {
        let expiredCount = results.filter { $0.verdict == .expired }.count
        if expiredCount >= 3 || backlogScore >= 75 { return .F }
        if expiredCount >= 1 || backlogScore >= 55 { return .D }
        if backlogScore >= 35 { return .C }
        if backlogScore >= 18 { return .B }
        return .A
    }

    // MARK: - Insights

    private func computeInsights(results: [ArticleStalenessResult]) -> [StalenessInsight] {
        var insights: [StalenessInsight] = []

        let expiredCount = results.filter { $0.verdict == .expired }.count
        let staleCount = results.filter { $0.verdict == .stale }.count
        let freshCount = results.filter { $0.verdict == .fresh }.count
        let eventExpiredCount = results.filter { $0.reasons.contains(.eventExpired) }.count
        let supersededCount = results.filter { $0.reasons.contains(.superseded) }.count
        let topicSatCount = results.filter { $0.reasons.contains(.topicSaturated) }.count
        let correctionCount = results.filter { $0.reasons.contains(.correctionIssued) }.count

        if freshCount == results.count {
            insights.append(.backlogFresh)
        } else if expiredCount + staleCount >= results.count / 2 {
            insights.append(.agingBacklog)
        } else {
            insights.append(.mixedFreshness)
        }

        if eventExpiredCount >= 2 {
            insights.append(.eventArticlesExpired)
        }
        if topicSatCount >= 3 {
            insights.append(.topicPileup)
        }
        if correctionCount >= 1 {
            insights.append(.correctionsPresent)
        }
        if supersededCount >= 3 {
            insights.append(.heavilySuperseded)
        }

        if insights.isEmpty {
            insights.append(.mixedFreshness)
        }

        return insights
    }

    // MARK: - Playbook

    private func computePlaybook(results: [ArticleStalenessResult], grade: BacklogGrade) -> [StalenessAction] {
        var actions: [StalenessAction] = []
        var usedLabels: Set<String> = []

        let expiredIds = results.filter { $0.verdict == .expired }.map(\.articleId)
        let staleIds = results.filter { $0.verdict == .stale }.map(\.articleId)
        let eventExpiredIds = results.filter { $0.reasons.contains(.eventExpired) }.map(\.articleId)
        let supersededIds = results.filter { $0.reasons.contains(.superseded) }.map(\.articleId)
        let correctionIds = results.filter { $0.reasons.contains(.correctionIssued) }.map(\.articleId)
        let saturatedIds = results.filter { $0.reasons.contains(.topicSaturated) }.map(\.articleId)

        if !expiredIds.isEmpty && usedLabels.insert("ARCHIVE_EXPIRED_ARTICLES").inserted {
            actions.append(StalenessAction(
                id: "archive_expired", priority: 0,
                label: "ARCHIVE_EXPIRED_ARTICLES",
                reason: "\(expiredIds.count) articles past useful life",
                owner: "reader", blastRadius: 3, reversibility: "high",
                articleIds: expiredIds
            ))
        }

        if eventExpiredIds.count >= 2 && usedLabels.insert("DISMISS_PAST_EVENTS").inserted {
            actions.append(StalenessAction(
                id: "dismiss_events", priority: 0,
                label: "DISMISS_PAST_EVENTS",
                reason: "\(eventExpiredIds.count) time-sensitive articles with events already passed",
                owner: "reader", blastRadius: 2, reversibility: "high",
                articleIds: eventExpiredIds
            ))
        }

        if !correctionIds.isEmpty && usedLabels.insert("REVIEW_CORRECTED_ARTICLES").inserted {
            actions.append(StalenessAction(
                id: "review_corrections", priority: 0,
                label: "REVIEW_CORRECTED_ARTICLES",
                reason: "\(correctionIds.count) articles with published corrections",
                owner: "reader", blastRadius: 2, reversibility: "high",
                articleIds: correctionIds
            ))
        }

        if !staleIds.isEmpty && usedLabels.insert("ARCHIVE_STALE_BATCH").inserted {
            actions.append(StalenessAction(
                id: "archive_stale", priority: 1,
                label: "ARCHIVE_STALE_BATCH",
                reason: "\(staleIds.count) significantly stale articles",
                owner: "reader", blastRadius: 3, reversibility: "high",
                articleIds: staleIds
            ))
        }

        if supersededIds.count >= 2 && usedLabels.insert("DEDUPLICATE_SUPERSEDED").inserted {
            actions.append(StalenessAction(
                id: "dedup_superseded", priority: 1,
                label: "DEDUPLICATE_SUPERSEDED",
                reason: "\(supersededIds.count) articles superseded by newer coverage",
                owner: "reader", blastRadius: 2, reversibility: "high",
                articleIds: supersededIds
            ))
        }

        if saturatedIds.count >= 3 && usedLabels.insert("THIN_TOPIC_PILEUP").inserted {
            actions.append(StalenessAction(
                id: "thin_pileup", priority: 2,
                label: "THIN_TOPIC_PILEUP",
                reason: "\(saturatedIds.count) articles on over-represented topic",
                owner: "reader", blastRadius: 2, reversibility: "high",
                articleIds: saturatedIds
            ))
        }

        if riskAppetite == .cautious && (grade == .C || grade == .D || grade == .F) {
            if usedLabels.insert("SCHEDULE_BACKLOG_REVIEW").inserted {
                actions.append(StalenessAction(
                    id: "schedule_review", priority: 2,
                    label: "SCHEDULE_BACKLOG_REVIEW",
                    reason: "Backlog grade \(grade.rawValue) - schedule time to clear queue",
                    owner: "reader", blastRadius: 1, reversibility: "high",
                    articleIds: []
                ))
            }
        }

        // P3 fallback
        if actions.isEmpty || riskAppetite != .aggressive {
            if usedLabels.insert("MAINTAIN_READING_ROUTINE").inserted {
                actions.append(StalenessAction(
                    id: "maintain_routine", priority: 3,
                    label: "MAINTAIN_READING_ROUTINE",
                    reason: "Continue regular reading to prevent backlog growth",
                    owner: "reader", blastRadius: 1, reversibility: "high",
                    articleIds: []
                ))
            }
        }

        // Aggressive trims P3 when P0/P1 present
        if riskAppetite == .aggressive {
            let hasHighPriority = actions.contains { $0.priority <= 1 }
            if hasHighPriority {
                return actions.filter { $0.priority <= 2 }
            }
        }

        return actions
    }
}
