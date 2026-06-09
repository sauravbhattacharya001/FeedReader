//
//  FeedReadingRecallScheduler.swift
//  FeedReaderCore
//
//  Agentic spaced-recall advisor for read articles. Estimates per-article
//  retention via an Ebbinghaus-inspired forgetting curve, then recommends
//  which articles the reader should revisit and when, before the memory
//  fades. Distinct from FeedArticleStalenessDetector (UNREAD queue
//  archival), FeedReadingPaceAnalyzer (speed/wpm only),
//  FeedReadingStreakEngine (gamification) and FeedReadingAutopilot (time-
//  budgeted UNREAD playlists). This advisor is whole-article-level and
//  operates on items the user has ALREADY read.
//
//  Key capabilities:
//  - Per-article recall strength estimate using R = exp(-t / S) where
//    stability S is boosted by engagement, importance, bookmarks, notes,
//    vocabulary anchors and prior revisit count
//  - 7 verdicts (revisitNow / revisitToday / revisitThisWeek /
//    scheduledRecall / safelyRetained / archived / insufficientData)
//  - 0..100 recallScore (urgency) with risk_appetite modulation
//  - P0..P3 prioritized playbook with blastRadius + reversibility
//  - Cross-library insights (highDecayBacklog, retentionAtRisk, etc.)
//  - Deterministic given a fixed `now: () -> Date`; never mutates inputs
//  - text / markdown / byte-stable JSON renderers
//  - simulate(report:applyTopN:) projects retention lift if the top N
//    playbook actions are applied; never mutates the input report
//
//  All processing is on-device. Foundation only - no UIKit, no network.
//

import Foundation

// MARK: - Risk Appetite

/// Controls how aggressively the scheduler recommends revisits.
public enum RecallRiskAppetite: String, Sendable, CaseIterable {
    case cautious
    case balanced
    case aggressive

    var multiplier: Double {
        switch self {
        case .cautious:   return 1.15
        case .balanced:   return 1.0
        case .aggressive: return 0.85
        }
    }
}

// MARK: - Input Model

/// One article the user has already read (or revisited at least once).
public struct ReadArticleRecord: Sendable, Equatable {
    public let id: String
    public let title: String
    public let feedName: String
    public let readAt: Date
    public let lastRevisitedAt: Date?
    public let revisitCount: Int
    public let readDurationSeconds: Double
    public let articleLengthSeconds: Double
    public let isBookmarked: Bool
    public let hasNotes: Bool
    public let notesCount: Int
    public let vocabularyHits: Int
    public let topicInterest: Double
    public let importanceHint: Double
    public let isArchived: Bool

    public init(
        id: String,
        title: String,
        feedName: String,
        readAt: Date,
        lastRevisitedAt: Date? = nil,
        revisitCount: Int = 0,
        readDurationSeconds: Double = 0,
        articleLengthSeconds: Double = 0,
        isBookmarked: Bool = false,
        hasNotes: Bool = false,
        notesCount: Int = 0,
        vocabularyHits: Int = 0,
        topicInterest: Double = 0.5,
        importanceHint: Double = 0.5,
        isArchived: Bool = false
    ) {
        self.id = id
        self.title = title
        self.feedName = feedName
        self.readAt = readAt
        self.lastRevisitedAt = lastRevisitedAt
        self.revisitCount = max(0, revisitCount)
        self.readDurationSeconds = max(0, readDurationSeconds)
        self.articleLengthSeconds = max(0, articleLengthSeconds)
        self.isBookmarked = isBookmarked
        self.hasNotes = hasNotes
        self.notesCount = max(0, notesCount)
        self.vocabularyHits = max(0, vocabularyHits)
        self.topicInterest = max(0, min(1, topicInterest))
        self.importanceHint = max(0, min(1, importanceHint))
        self.isArchived = isArchived
    }
}

// MARK: - Output Models

public enum RecallVerdict: String, Sendable, CaseIterable {
    case revisitNow
    case revisitToday
    case revisitThisWeek
    case scheduledRecall
    case safelyRetained
    case archived
    case insufficientData
}

public enum RecallReason: String, Sendable, CaseIterable {
    case shortRetentionWindow
    case longSinceRead
    case neverRevisited
    case recallStrengthLow
    case highImportance
    case bookmarkSignal
    case notesSignal
    case vocabularyAnchor
    case fullyEngaged
    case partiallyRead
    case recentlyRevisited
    case archivedByUser
    case freshlyRead
}

public enum RetentionGrade: String, Sendable, CaseIterable {
    case A, B, C, D, F
}

public struct ArticleRecallResult: Sendable {
    public let articleId: String
    public let title: String
    public let feedName: String
    public let recallScore: Int
    public let recallStrength: Double
    public let priority: Int
    public let verdict: RecallVerdict
    public let reasons: [RecallReason]
    public let nextRevisitAt: Date?
    public let recommendedAction: String
    public let daysSinceRead: Double

    public init(
        articleId: String,
        title: String,
        feedName: String,
        recallScore: Int,
        recallStrength: Double,
        priority: Int,
        verdict: RecallVerdict,
        reasons: [RecallReason],
        nextRevisitAt: Date?,
        recommendedAction: String,
        daysSinceRead: Double
    ) {
        self.articleId = articleId
        self.title = title
        self.feedName = feedName
        self.recallScore = max(0, min(100, recallScore))
        self.recallStrength = max(0, min(1, recallStrength))
        self.priority = max(0, min(3, priority))
        self.verdict = verdict
        self.reasons = reasons
        self.nextRevisitAt = nextRevisitAt
        self.recommendedAction = recommendedAction
        self.daysSinceRead = max(0, daysSinceRead)
    }
}

public struct RecallAction: Sendable {
    public let id: String
    public let priority: Int
    public let label: String
    public let reason: String
    public let owner: String
    public let blastRadius: Int
    public let reversibility: String
    public let articleIds: [String]

    public init(
        id: String,
        priority: Int,
        label: String,
        reason: String,
        owner: String,
        blastRadius: Int,
        reversibility: String,
        articleIds: [String]
    ) {
        self.id = id
        self.priority = max(0, min(3, priority))
        self.label = label
        self.reason = reason
        self.owner = owner
        self.blastRadius = max(1, min(5, blastRadius))
        self.reversibility = reversibility
        self.articleIds = articleIds
    }
}

public enum RecallInsight: String, Sendable, CaseIterable {
    case highDecayBacklog   = "HIGH_DECAY_BACKLOG"
    case retentionAtRisk    = "RETENTION_AT_RISK"
    case noRecallScheduled  = "NO_RECALL_SCHEDULED"
    case revisitMomentum    = "REVISIT_MOMENTUM"
    case bookmarksAtRisk    = "BOOKMARKS_AT_RISK"
    case heavyArchiver      = "HEAVY_ARCHIVER"
    case wellRetained       = "WELL_RETAINED"
    case freshLibrary       = "FRESH_LIBRARY"
    case emptyLibrary       = "EMPTY_LIBRARY"
}

public struct RecallReport: Sendable {
    public let results: [ArticleRecallResult]
    public let retentionScore: Int
    public let grade: RetentionGrade
    public let headline: String
    public let playbook: [RecallAction]
    public let insights: [RecallInsight]
    public let dueNowIds: [String]

    public init(
        results: [ArticleRecallResult],
        retentionScore: Int,
        grade: RetentionGrade,
        headline: String,
        playbook: [RecallAction],
        insights: [RecallInsight],
        dueNowIds: [String]
    ) {
        self.results = results
        self.retentionScore = max(0, min(100, retentionScore))
        self.grade = grade
        self.headline = headline
        self.playbook = playbook
        self.insights = insights
        self.dueNowIds = dueNowIds
    }
}

// MARK: - Scheduler

/// Agentic spaced-recall scheduler over read articles.
public final class FeedReadingRecallScheduler: @unchecked Sendable {

    private let nowProvider: () -> Date

    public init(now: @escaping () -> Date = { Date() }) {
        self.nowProvider = now
    }

    // MARK: Public API

    public func analyze(records: [ReadArticleRecord], appetite: RecallRiskAppetite = .balanced) -> RecallReport {
        let now = nowProvider()
        let snapshot = records

        if snapshot.isEmpty {
            return RecallReport(
                results: [],
                retentionScore: 100,
                grade: .A,
                headline: "VERDICT: grade=A N=0 P0=0 P1=0 retention=100",
                playbook: [
                    RecallAction(
                        id: "MAINTAIN_RECALL_PRACTICE",
                        priority: 3,
                        label: "Maintain recall practice",
                        reason: "Library is empty.",
                        owner: "reader",
                        blastRadius: 1,
                        reversibility: "high",
                        articleIds: []
                    )
                ],
                insights: [.emptyLibrary],
                dueNowIds: []
            )
        }

        var perArticle: [ArticleRecallResult] = []
        perArticle.reserveCapacity(snapshot.count)
        for rec in snapshot {
            perArticle.append(scoreOne(record: rec, now: now, appetite: appetite))
        }

        perArticle.sort { lhs, rhs in
            if lhs.recallScore != rhs.recallScore { return lhs.recallScore > rhs.recallScore }
            return lhs.articleId < rhs.articleId
        }

        let nonArchived = perArticle.filter { $0.verdict != .archived }
        let retentionScore: Int
        if nonArchived.isEmpty {
            retentionScore = 100
        } else {
            let mean = nonArchived.map(\.recallStrength).reduce(0, +) / Double(nonArchived.count)
            retentionScore = Int((mean * 100).rounded())
        }

        let insights = computeInsights(results: perArticle, snapshot: snapshot, now: now)
        let grade = computeGrade(retentionScore: retentionScore, results: perArticle)

        let dueNowIds = perArticle
            .filter { $0.verdict == .revisitNow || $0.verdict == .revisitToday }
            .map(\.articleId)
            .sorted()

        let playbook = computePlaybook(
            results: perArticle,
            insights: insights,
            grade: grade,
            appetite: appetite
        )

        let p0 = perArticle.filter { $0.priority == 0 }.count
        let p1 = perArticle.filter { $0.priority == 1 }.count
        let headline = "VERDICT: grade=\(grade.rawValue) N=\(perArticle.count) P0=\(p0) P1=\(p1) retention=\(retentionScore)"

        return RecallReport(
            results: perArticle,
            retentionScore: retentionScore,
            grade: grade,
            headline: headline,
            playbook: playbook,
            insights: insights,
            dueNowIds: dueNowIds
        )
    }

    /// Project retention if the top N playbook actions are applied. Never mutates input.
    public func simulate(report: RecallReport, applyTopN: Int) -> RecallReport {
        let n = max(0, min(applyTopN, report.playbook.count))
        if n == 0 {
            return report
        }

        // Map articleId -> mutable copy of result.
        var byId: [String: ArticleRecallResult] = [:]
        for r in report.results {
            byId[r.articleId] = r
        }

        for i in 0..<n {
            let action = report.playbook[i]
            let baseLift = liftFor(actionId: action.id)
            let damped = baseLift * pow(0.85, Double(i))
            for aid in action.articleIds {
                guard let cur = byId[aid] else { continue }
                if cur.verdict == .archived { continue }
                let newStrength = max(0.0, min(1.0, cur.recallStrength + damped))
                let newScore = max(0, cur.recallScore - Int((damped * 100).rounded()))
                let (newVerdict, newPriority) = recomputeVerdictForSimulate(
                    original: cur,
                    newStrength: newStrength,
                    newScore: newScore
                )
                byId[aid] = ArticleRecallResult(
                    articleId: cur.articleId,
                    title: cur.title,
                    feedName: cur.feedName,
                    recallScore: newScore,
                    recallStrength: newStrength,
                    priority: newPriority,
                    verdict: newVerdict,
                    reasons: cur.reasons,
                    nextRevisitAt: cur.nextRevisitAt,
                    recommendedAction: cur.recommendedAction,
                    daysSinceRead: cur.daysSinceRead
                )
            }
        }

        // Rebuild results in original sort order.
        var results: [ArticleRecallResult] = []
        for r in report.results {
            results.append(byId[r.articleId] ?? r)
        }
        // Re-sort.
        results.sort { lhs, rhs in
            if lhs.recallScore != rhs.recallScore { return lhs.recallScore > rhs.recallScore }
            return lhs.articleId < rhs.articleId
        }

        // Recompute portfolio retention.
        let nonArchived = results.filter { $0.verdict != .archived }
        let retentionScore: Int
        if nonArchived.isEmpty {
            retentionScore = 100
        } else {
            let mean = nonArchived.map(\.recallStrength).reduce(0, +) / Double(nonArchived.count)
            retentionScore = Int((mean * 100).rounded())
        }
        let grade = computeGrade(retentionScore: retentionScore, results: results)

        let dueNowIds = results
            .filter { $0.verdict == .revisitNow || $0.verdict == .revisitToday }
            .map(\.articleId)
            .sorted()

        let p0 = results.filter { $0.priority == 0 }.count
        let p1 = results.filter { $0.priority == 1 }.count
        let headline = "VERDICT: grade=\(grade.rawValue) N=\(results.count) P0=\(p0) P1=\(p1) retention=\(retentionScore)"

        return RecallReport(
            results: results,
            retentionScore: retentionScore,
            grade: grade,
            headline: headline,
            playbook: report.playbook,
            insights: report.insights,
            dueNowIds: dueNowIds
        )
    }

    // MARK: Internals (scoring)

    private func scoreOne(record rec: ReadArticleRecord, now: Date, appetite: RecallRiskAppetite) -> ArticleRecallResult {
        let lastEngagement = rec.lastRevisitedAt ?? rec.readAt
        let secondsSinceEngagement = max(0, now.timeIntervalSince(lastEngagement))
        let daysSinceEngagement = secondsSinceEngagement / 86400.0
        let secondsSinceRead = max(0, now.timeIntervalSince(rec.readAt))
        let daysSinceRead = secondsSinceRead / 86400.0

        // Stability S in days.
        let s0: Double = 1.5
        var stability = s0
        stability *= 1.0 + 0.5 * rec.importanceHint
        stability *= 1.0 + 0.5 * rec.topicInterest
        let engagementRatio: Double
        if rec.articleLengthSeconds > 0 {
            engagementRatio = min(rec.readDurationSeconds / rec.articleLengthSeconds, 1.0)
        } else {
            engagementRatio = 0.0
        }
        stability *= 1.0 + 0.4 * engagementRatio
        stability *= 1.0 + 0.3 * (Double(min(rec.notesCount, 5)) / 5.0)
        stability *= 1.0 + 0.5 * (rec.isBookmarked ? 1.0 : 0.0)
        stability *= 1.0 + 0.4 * (Double(min(rec.vocabularyHits, 10)) / 10.0)
        stability *= 1.0 + Double(min(rec.revisitCount, 5)) * 0.6
        stability = max(0.5, stability)

        // Recall strength via Ebbinghaus exp decay.
        var recallStrength = exp(-daysSinceEngagement / stability)
        if recallStrength.isNaN || recallStrength.isInfinite { recallStrength = 0.5 }
        recallStrength = max(0, min(1, recallStrength))

        // Freshly read floor.
        if daysSinceRead < 0.25 {
            recallStrength = max(recallStrength, 0.97)
        } else if daysSinceRead < 0.5 {
            recallStrength = max(recallStrength, 0.95)
        }

        // Reasons.
        var reasons: [RecallReason] = []
        if rec.isArchived {
            reasons.append(.archivedByUser)
        }
        if daysSinceRead < 0.5 {
            reasons.append(.freshlyRead)
        }
        if daysSinceEngagement >= 14 {
            reasons.append(.longSinceRead)
        }
        if rec.lastRevisitedAt == nil && daysSinceRead >= 1.0 {
            reasons.append(.neverRevisited)
        }
        if recallStrength < 0.4 {
            reasons.append(.recallStrengthLow)
        }
        if recallStrength < 0.3 {
            reasons.append(.shortRetentionWindow)
        }
        if rec.importanceHint >= 0.65 {
            reasons.append(.highImportance)
        }
        if rec.isBookmarked {
            reasons.append(.bookmarkSignal)
        }
        if rec.hasNotes || rec.notesCount > 0 {
            reasons.append(.notesSignal)
        }
        if rec.vocabularyHits >= 1 {
            reasons.append(.vocabularyAnchor)
        }
        if engagementRatio >= 0.85 {
            reasons.append(.fullyEngaged)
        } else if engagementRatio > 0 && engagementRatio < 0.4 {
            reasons.append(.partiallyRead)
        }
        if let lr = rec.lastRevisitedAt {
            let daysSinceRevisit = now.timeIntervalSince(lr) / 86400.0
            if daysSinceRevisit <= 2.0 {
                reasons.append(.recentlyRevisited)
            }
        }

        // recallScore (urgency).
        var urgency = (1.0 - recallStrength) * 100.0
        urgency += 10.0 * rec.importanceHint
        if rec.isBookmarked {
            urgency += 8.0
        }
        if rec.hasNotes || rec.notesCount > 0 {
            urgency += 5.0
        }
        urgency += 4.0 * min(Double(rec.vocabularyHits) / 10.0, 1.0)
        if let lr = rec.lastRevisitedAt {
            let daysSinceRevisit = now.timeIntervalSince(lr) / 86400.0
            if daysSinceRevisit <= 2.0 {
                urgency -= 15.0
            }
        }
        urgency *= appetite.multiplier
        if urgency < 0 { urgency = 0 }
        if urgency > 100 { urgency = 100 }
        let recallScore = Int(urgency.rounded())

        // Verdict + priority + nextRevisitAt.
        let verdict: RecallVerdict
        let priority: Int
        let nextRevisitAt: Date?

        if rec.isArchived {
            verdict = .archived
            priority = 3
            nextRevisitAt = nil
        } else if daysSinceRead < 0.25 {
            verdict = .insufficientData
            priority = 3
            nextRevisitAt = nil
        } else if daysSinceRead < 0.5 {
            verdict = .safelyRetained
            priority = 3
            nextRevisitAt = lastEngagement.addingTimeInterval(stability * log(1.0 / 0.5) * 86400.0)
        } else if recallScore >= 75 && (rec.importanceHint >= 0.5 || rec.isBookmarked || rec.hasNotes || rec.vocabularyHits >= 1) {
            verdict = .revisitNow
            priority = 0
            nextRevisitAt = now
        } else if recallScore >= 60 {
            verdict = .revisitToday
            priority = 1
            nextRevisitAt = now.addingTimeInterval(6 * 3600)
        } else if recallScore >= 40 {
            verdict = .revisitThisWeek
            priority = 2
            nextRevisitAt = now.addingTimeInterval(3 * 86400)
        } else if recallStrength >= 0.7, let lr = rec.lastRevisitedAt, now.timeIntervalSince(lr) <= 7 * 86400 {
            verdict = .safelyRetained
            priority = 3
            nextRevisitAt = lr.addingTimeInterval(stability * log(1.0 / 0.5) * 86400.0)
        } else {
            verdict = .scheduledRecall
            priority = 3
            // Plan revisit when retention dips to ~60%.
            let plannedDays = stability * log(1.0 / 0.6)
            let candidate = lastEngagement.addingTimeInterval(plannedDays * 86400.0)
            // Ensure >= now + 1d.
            let floor = now.addingTimeInterval(86400.0)
            nextRevisitAt = candidate < floor ? floor : candidate
        }

        let recommendedAction: String
        switch verdict {
        case .revisitNow:        recommendedAction = "Revisit now"
        case .revisitToday:      recommendedAction = "Revisit today"
        case .revisitThisWeek:   recommendedAction = "Revisit this week"
        case .scheduledRecall:   recommendedAction = "Scheduled recall"
        case .safelyRetained:    recommendedAction = "Safely retained"
        case .archived:          recommendedAction = "Archived"
        case .insufficientData:  recommendedAction = "Insufficient data"
        }

        return ArticleRecallResult(
            articleId: rec.id,
            title: rec.title,
            feedName: rec.feedName,
            recallScore: recallScore,
            recallStrength: recallStrength,
            priority: priority,
            verdict: verdict,
            reasons: reasons,
            nextRevisitAt: nextRevisitAt,
            recommendedAction: recommendedAction,
            daysSinceRead: daysSinceRead
        )
    }

    private func liftFor(actionId: String) -> Double {
        switch actionId {
        case "OPEN_RECALL_FLASH_REVIEW":      return 0.40
        case "RECOVER_HIGH_VALUE_BOOKMARKS":  return 0.45
        case "BATCH_REVISIT_TODAY":           return 0.30
        case "RECONNECT_VOCAB_ANCHORS":       return 0.25
        case "BLOCK_RECALL_WINDOW_THIS_WEEK": return 0.18
        case "BACKFILL_REVISIT_HISTORY":      return 0.05
        case "ARCHIVE_LOW_VALUE_BACKLOG":     return 0.0
        case "SCHEDULE_RECALL_AUDIT":         return 0.03
        case "MAINTAIN_RECALL_PRACTICE":      return 0.0
        default:                              return 0.0
        }
    }

    private func recomputeVerdictForSimulate(
        original: ArticleRecallResult,
        newStrength: Double,
        newScore: Int
    ) -> (RecallVerdict, Int) {
        if original.verdict == .archived { return (.archived, 3) }
        if original.verdict == .insufficientData { return (.insufficientData, 3) }
        if newScore >= 75 { return (.revisitNow, 0) }
        if newScore >= 60 { return (.revisitToday, 1) }
        if newScore >= 40 { return (.revisitThisWeek, 2) }
        if newStrength >= 0.7 { return (.safelyRetained, 3) }
        return (.scheduledRecall, 3)
    }

    // MARK: Internals (insights / grade / playbook)

    private func computeInsights(
        results: [ArticleRecallResult],
        snapshot: [ReadArticleRecord],
        now: Date
    ) -> [RecallInsight] {
        var out: [RecallInsight] = []
        let active = results.filter { $0.verdict != .archived }

        if active.isEmpty {
            out.append(.emptyLibrary)
            return out
        }

        let archivedCount = results.filter { $0.verdict == .archived }.count
        let revisitNow = results.filter { $0.verdict == .revisitNow }.count
        let revisitToday = results.filter { $0.verdict == .revisitToday }.count
        let scheduled = results.filter { $0.verdict == .scheduledRecall }.count
        let safely = results.filter { $0.verdict == .safelyRetained }.count
        let lowStrength = active.filter { $0.recallStrength < 0.4 }.count
        let bookmarksAtRiskCount = snapshot.filter { rec in
            guard rec.isBookmarked, !rec.isArchived else { return false }
            let strength = results.first(where: { $0.articleId == rec.id })?.recallStrength ?? 1.0
            return strength < 0.5
        }.count
        let recentRevisits = snapshot.filter { rec in
            guard let lr = rec.lastRevisitedAt else { return false }
            return now.timeIntervalSince(lr) <= 3 * 86400
        }.count

        let allFresh = active.allSatisfy { $0.daysSinceRead < 0.5 }
        if allFresh {
            out.append(.freshLibrary)
        }

        if revisitNow >= 3 || (revisitNow >= 1 && bookmarksAtRiskCount >= 1) {
            out.append(.highDecayBacklog)
        }

        if !allFresh && Double(lowStrength) / Double(max(1, active.count)) >= 0.5 {
            out.append(.retentionAtRisk)
        }

        if scheduled == 0 && (revisitNow + revisitToday) == 0 && safely == active.count && active.count > 0 {
            out.append(.wellRetained)
        }

        if !allFresh && scheduled == 0 && safely < active.count && (revisitNow + revisitToday) > 0 {
            out.append(.noRecallScheduled)
        }

        if recentRevisits >= 3 {
            out.append(.revisitMomentum)
        }

        if bookmarksAtRiskCount >= 2 {
            out.append(.bookmarksAtRisk)
        }

        if archivedCount >= max(3, snapshot.count / 2) {
            out.append(.heavyArchiver)
        }

        if out.isEmpty {
            out.append(.wellRetained)
        }

        let order: [RecallInsight] = [
            .highDecayBacklog,
            .retentionAtRisk,
            .bookmarksAtRisk,
            .noRecallScheduled,
            .revisitMomentum,
            .heavyArchiver,
            .wellRetained,
            .freshLibrary,
            .emptyLibrary
        ]
        var seen = Set<RecallInsight>()
        var sortedOut: [RecallInsight] = []
        for o in order where out.contains(o) && !seen.contains(o) {
            sortedOut.append(o)
            seen.insert(o)
        }
        return sortedOut
    }

    private func computeGrade(retentionScore: Int, results: [ArticleRecallResult]) -> RetentionGrade {
        let revisitNow = results.filter { $0.verdict == .revisitNow }
        let revisitNowCount = revisitNow.count
        let revisitNowBookmarked = revisitNow.filter { r in
            r.reasons.contains(.bookmarkSignal)
        }.count

        if revisitNowCount >= 3 || (revisitNowCount >= 1 && revisitNowBookmarked >= 1) {
            return .F
        }
        let cap: RetentionGrade? = revisitNowCount >= 1 ? .C : nil

        let base: RetentionGrade
        if retentionScore >= 85 { base = .A }
        else if retentionScore >= 70 { base = .B }
        else if retentionScore >= 55 { base = .C }
        else if retentionScore >= 40 { base = .D }
        else { base = .F }

        if let cap = cap {
            return clamp(grade: base, max: cap)
        }
        return base
    }

    private func clamp(grade: RetentionGrade, max cap: RetentionGrade) -> RetentionGrade {
        let order: [RetentionGrade] = [.A, .B, .C, .D, .F]
        let gi = order.firstIndex(of: grade) ?? 0
        let ci = order.firstIndex(of: cap) ?? (order.count - 1)
        return gi >= ci ? grade : cap
    }

    private func computePlaybook(
        results: [ArticleRecallResult],
        insights: [RecallInsight],
        grade: RetentionGrade,
        appetite: RecallRiskAppetite
    ) -> [RecallAction] {
        var out: [RecallAction] = []

        let nowList = results.filter { $0.verdict == .revisitNow }
        let today = results.filter { $0.verdict == .revisitToday }
        let week = results.filter { $0.verdict == .revisitThisWeek }
        let scheduled = results.filter { $0.verdict == .scheduledRecall }
        let archived = results.filter { $0.verdict == .archived }
        let bookmarkAtRisk = results.filter {
            $0.reasons.contains(.bookmarkSignal) && $0.recallStrength < 0.5 && $0.verdict != .archived
        }
        let vocabAtRisk = results.filter {
            $0.reasons.contains(.vocabularyAnchor) && $0.recallStrength < 0.6 && $0.verdict != .archived
        }

        if !nowList.isEmpty {
            out.append(RecallAction(
                id: "OPEN_RECALL_FLASH_REVIEW",
                priority: 0,
                label: "Open recall flash review",
                reason: "\(nowList.count) high-decay article(s) need immediate revisit.",
                owner: "reader",
                blastRadius: min(5, max(2, nowList.count)),
                reversibility: "high",
                articleIds: nowList.map(\.articleId).sorted()
            ))
        }
        if !bookmarkAtRisk.isEmpty {
            out.append(RecallAction(
                id: "RECOVER_HIGH_VALUE_BOOKMARKS",
                priority: 0,
                label: "Recover high-value bookmarks",
                reason: "\(bookmarkAtRisk.count) bookmarked article(s) below 50% retention.",
                owner: "reader",
                blastRadius: min(5, max(2, bookmarkAtRisk.count)),
                reversibility: "high",
                articleIds: bookmarkAtRisk.map(\.articleId).sorted()
            ))
        }

        if !today.isEmpty {
            out.append(RecallAction(
                id: "BATCH_REVISIT_TODAY",
                priority: 1,
                label: "Batch revisit today",
                reason: "\(today.count) article(s) due for revisit today.",
                owner: "reader",
                blastRadius: min(5, max(2, today.count)),
                reversibility: "high",
                articleIds: today.map(\.articleId).sorted()
            ))
        }
        if !vocabAtRisk.isEmpty {
            out.append(RecallAction(
                id: "RECONNECT_VOCAB_ANCHORS",
                priority: 1,
                label: "Reconnect vocabulary anchors",
                reason: "\(vocabAtRisk.count) vocabulary-anchor article(s) decaying.",
                owner: "reader",
                blastRadius: min(5, max(2, vocabAtRisk.count)),
                reversibility: "high",
                articleIds: vocabAtRisk.map(\.articleId).sorted()
            ))
        }

        if !week.isEmpty {
            out.append(RecallAction(
                id: "BLOCK_RECALL_WINDOW_THIS_WEEK",
                priority: 2,
                label: "Block recall window this week",
                reason: "\(week.count) article(s) scheduled within 7 days.",
                owner: "reader",
                blastRadius: min(5, max(2, week.count)),
                reversibility: "high",
                articleIds: week.map(\.articleId).sorted()
            ))
        }
        let neverRevisited = results.filter {
            $0.reasons.contains(.neverRevisited) && $0.verdict != .archived && $0.verdict != .insufficientData
        }
        if !neverRevisited.isEmpty {
            out.append(RecallAction(
                id: "BACKFILL_REVISIT_HISTORY",
                priority: 2,
                label: "Backfill revisit history",
                reason: "\(neverRevisited.count) article(s) have never been revisited.",
                owner: "reader",
                blastRadius: min(5, max(2, neverRevisited.count)),
                reversibility: "high",
                articleIds: neverRevisited.map(\.articleId).sorted()
            ))
        }

        if archived.count >= 5 {
            out.append(RecallAction(
                id: "ARCHIVE_LOW_VALUE_BACKLOG",
                priority: 3,
                label: "Archive low-value backlog",
                reason: "\(archived.count) article(s) already archived; consider pruning.",
                owner: "reader",
                blastRadius: 1,
                reversibility: "high",
                articleIds: archived.map(\.articleId).sorted()
            ))
        }
        if !scheduled.isEmpty {
            out.append(RecallAction(
                id: "SCHEDULE_RECALL_AUDIT",
                priority: 3,
                label: "Schedule recall audit",
                reason: "\(scheduled.count) article(s) on long-term recall schedule.",
                owner: "reader",
                blastRadius: 1,
                reversibility: "high",
                articleIds: scheduled.map(\.articleId).sorted()
            ))
        }

        if out.isEmpty {
            out.append(RecallAction(
                id: "MAINTAIN_RECALL_PRACTICE",
                priority: 3,
                label: "Maintain recall practice",
                reason: "Library retention is healthy.",
                owner: "reader",
                blastRadius: 1,
                reversibility: "high",
                articleIds: []
            ))
        }

        out.sort { lhs, rhs in
            if lhs.priority != rhs.priority { return lhs.priority < rhs.priority }
            return lhs.id < rhs.id
        }
        return out
    }
}

// MARK: - Renderers (RecallReport)

extension RecallReport {

    /// Plain text renderer.
    public func toText() -> String {
        var lines: [String] = []
        lines.append(headline)
        lines.append("")
        lines.append("Grade: \(grade.rawValue) | Retention: \(retentionScore)/100")
        lines.append("Articles: \(results.count) | Due now: \(dueNowIds.count)")
        lines.append("")
        if !results.isEmpty {
            lines.append("--- Articles ---")
            for r in results {
                let reasons = r.reasons.map(\.rawValue).joined(separator: ", ")
                let strengthPct = Int((r.recallStrength * 100).rounded())
                lines.append("[P\(r.priority) \(r.verdict.rawValue)] \(r.title) (score=\(r.recallScore), retention=\(strengthPct)%, days=\(String(format: "%.1f", r.daysSinceRead)), \(reasons))")
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

    /// Markdown renderer with always-present sections.
    public func toMarkdown() -> String {
        var lines: [String] = []
        lines.append("## Summary")
        lines.append("")
        lines.append("| Metric | Value |")
        lines.append("|--------|-------|")
        lines.append("| Grade | \(grade.rawValue) |")
        lines.append("| Retention Score | \(retentionScore)/100 |")
        lines.append("| Total Articles | \(results.count) |")
        lines.append("| Due Now | \(dueNowIds.count) |")
        lines.append("")

        lines.append("## Articles")
        lines.append("")
        lines.append("| ID | Title | Feed | Verdict | Priority | Score | Strength% | Days | Next Revisit | Reasons |")
        lines.append("|----|-------|------|---------|----------|-------|-----------|------|--------------|---------|")
        if results.isEmpty {
            lines.append("| _(none)_ | _(none)_ | _(none)_ | _(none)_ | _(none)_ | _(none)_ | _(none)_ | _(none)_ | _(none)_ | _(none)_ |")
        } else {
            for r in results {
                let trimmedTitle = r.title.count > 40
                    ? String(r.title.prefix(37)) + "..."
                    : r.title
                let reasons = r.reasons.map(\.rawValue).joined(separator: ", ")
                let strengthPct = Int((r.recallStrength * 100).rounded())
                let nextStr: String
                if let d = r.nextRevisitAt {
                    let f = ISO8601DateFormatter()
                    f.formatOptions = [.withInternetDateTime]
                    nextStr = f.string(from: d)
                } else {
                    nextStr = "-"
                }
                let escTitle = trimmedTitle.replacingOccurrences(of: "|", with: "\\|")
                let escFeed = r.feedName.replacingOccurrences(of: "|", with: "\\|")
                let escId = r.articleId.replacingOccurrences(of: "|", with: "\\|")
                let escReasons = reasons.replacingOccurrences(of: "|", with: "\\|")
                lines.append("| \(escId) | \(escTitle) | \(escFeed) | \(r.verdict.rawValue) | P\(r.priority) | \(r.recallScore) | \(strengthPct) | \(String(format: "%.1f", r.daysSinceRead)) | \(nextStr) | \(escReasons) |")
            }
        }
        lines.append("")

        lines.append("## Playbook")
        lines.append("")
        lines.append("| Priority | Action | Reason | Owner | Blast | Reversibility |")
        lines.append("|----------|--------|--------|-------|-------|---------------|")
        if playbook.isEmpty {
            lines.append("| _(none)_ | _(none)_ | _(none)_ | _(none)_ | _(none)_ | _(none)_ |")
        } else {
            for a in playbook {
                let escLabel = a.label.replacingOccurrences(of: "|", with: "\\|")
                let escReason = a.reason.replacingOccurrences(of: "|", with: "\\|")
                lines.append("| P\(a.priority) | \(escLabel) | \(escReason) | \(a.owner) | \(a.blastRadius) | \(a.reversibility) |")
            }
        }
        lines.append("")

        lines.append("## Insights")
        lines.append("")
        if insights.isEmpty {
            lines.append("- _(none)_")
        } else {
            for i in insights {
                lines.append("- \(i.rawValue)")
            }
        }

        return lines.joined(separator: "\n")
    }

    /// Byte-stable JSON renderer (sorted keys, 2-space indent).
    public func toJSON() -> String {
        var dict: [String: Any] = [:]
        dict["dueNowIds"] = dueNowIds.sorted()
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
            var entry: [String: Any] = [
                "articleId": r.articleId,
                "daysSinceRead": RecallReport._round(r.daysSinceRead, 3),
                "feedName": r.feedName,
                "priority": r.priority,
                "reasons": r.reasons.map(\.rawValue).sorted(),
                "recallScore": r.recallScore,
                "recallStrength": RecallReport._round(r.recallStrength, 3),
                "recommendedAction": r.recommendedAction,
                "title": r.title,
                "verdict": r.verdict.rawValue
            ]
            if let nra = r.nextRevisitAt {
                let f = ISO8601DateFormatter()
                f.formatOptions = [.withInternetDateTime]
                entry["nextRevisitAt"] = f.string(from: nra)
            } else {
                entry["nextRevisitAt"] = NSNull()
            }
            return entry
        }
        dict["results"] = resultsArr
        dict["retentionScore"] = retentionScore
        return RecallReport.stableJSON(dict, indent: 0)
    }

    static func _round(_ d: Double, _ places: Int) -> Double {
        let mult = pow(10.0, Double(places))
        return (d * mult).rounded() / mult
    }

    static func stableJSON(_ value: Any, indent: Int = 0) -> String {
        let pad = String(repeating: "  ", count: indent)
        let innerPad = String(repeating: "  ", count: indent + 1)
        if value is NSNull {
            return "null"
        }
        if let dict = value as? [String: Any] {
            if dict.isEmpty { return "{}" }
            let keys = dict.keys.sorted()
            var lines: [String] = ["{"]
            for (i, key) in keys.enumerated() {
                let val = stableJSON(dict[key]!, indent: indent + 1)
                let comma = i < keys.count - 1 ? "," : ""
                lines.append("\(innerPad)\"\(escapeJSONStr(key))\": \(val)\(comma)")
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
            return "\"\(escapeJSONStr(s))\""
        } else if let b = value as? Bool {
            return b ? "true" : "false"
        } else if let n = value as? Int {
            return "\(n)"
        } else if let d = value as? Double {
            if d.rounded() == d && abs(d) < 1e15 {
                return "\(Int(d))"
            }
            return "\(d)"
        }
        return "null"
    }

    private static func escapeJSONStr(_ s: String) -> String {
        s.replacingOccurrences(of: "\\", with: "\\\\")
         .replacingOccurrences(of: "\"", with: "\\\"")
         .replacingOccurrences(of: "\n", with: "\\n")
         .replacingOccurrences(of: "\r", with: "\\r")
         .replacingOccurrences(of: "\t", with: "\\t")
    }
}