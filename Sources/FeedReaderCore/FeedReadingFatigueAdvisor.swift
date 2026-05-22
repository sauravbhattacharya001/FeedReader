//
//  FeedReadingFatigueAdvisor.swift
//  FeedReaderCore
//
//  Agentic advisor that watches the *human reader's* cognitive load over
//  recent reading sessions and recommends rest / diversification / pace
//  adjustments before burnout sets in.
//
//  Unlike `FeedSubscriptionROI` (which scores feeds) or
//  `FeedBlindSpotDetector` (which finds coverage gaps), this advisor is
//  centred on the person doing the reading: how long they read, how
//  diverse their inputs are, whether sessions are running late at night,
//  whether sentiment has turned heavy, whether they've ever taken a
//  break, and so on.
//
//  Key capabilities:
//  - 10 weighted fatigue signals across volume, depth, diversity,
//    sentiment, timing and continuity
//  - 0..100 composite `fatigueScore`, A..F grade, 5-tier verdict ladder
//    (fresh / engaged / mildFatigue / heavyFatigue / burnout)
//  - Deduped P0-first playbook with blast-radius + reversibility
//  - Risk appetite knob (cautious / balanced / aggressive)
//  - Deterministic given a fixed `now` closure; never mutates inputs
//  - text / markdown / byte-stable JSON renderers
//
//  Usage:
//  ```swift
//  let advisor = FeedReadingFatigueAdvisor(now: { fixedDate })
//  advisor.riskAppetite = .balanced
//  let report = advisor.analyze(sessions: recentSessions)
//  print(report.summaryHeadline)
//  print(report.renderMarkdown())
//  ```
//
//  All processing is on-device. Foundation only — no UIKit, no network.
//

import Foundation

// MARK: - Reading Session

/// A single reading session captured by the host app.
///
/// All numeric fields are non-negative — the initializer clamps negatives
/// to zero so detectors can rely on the invariant.
public struct ReadingSession: Sendable, Equatable {
    /// Stable identifier for the session (used for dedup and evidence lines).
    public let id: String
    /// Local wall-clock time at which the session began.
    public let startedAt: Date
    /// Number of distinct articles opened during the session.
    public let articleCount: Int
    /// Total seconds the reader spent dwelling on articles in this session.
    public let totalDwellSeconds: TimeInterval
    /// Rapid-scroll events; high ratio vs `articleCount` is a skim signal.
    public let scrollEventCount: Int
    /// Lowercased topic tags read in this session.
    public let topicsRead: [String]
    /// Feed URLs (or names) the articles came from.
    public let feedsRead: [String]
    /// Optional sentiment in [-1.0, 1.0]; negative = heavy/depressing material.
    public let sentimentScore: Double?
    /// App foreground/background or article-abandoned events during the session.
    public let interruptionCount: Int

    /// Creates a `ReadingSession`. Negative counts are clamped to zero and
    /// `topicsRead` is normalised to lowercase for consistent grouping.
    ///
    /// - Parameters:
    ///   - id: Stable session identifier.
    ///   - startedAt: Local wall-clock start time.
    ///   - articleCount: Number of articles opened (clamped to `>= 0`).
    ///   - totalDwellSeconds: Total dwell time in seconds (clamped to `>= 0`).
    ///   - scrollEventCount: Number of rapid-scroll events (clamped to `>= 0`).
    ///   - topicsRead: Topic tags read; lowercased on store.
    ///   - feedsRead: Feed identifiers contributing to the session.
    ///   - sentimentScore: Optional rolling sentiment in `[-1.0, 1.0]`.
    ///   - interruptionCount: Backgrounding / abandonment events (clamped to `>= 0`).
    public init(
        id: String,
        startedAt: Date,
        articleCount: Int,
        totalDwellSeconds: TimeInterval,
        scrollEventCount: Int = 0,
        topicsRead: [String] = [],
        feedsRead: [String] = [],
        sentimentScore: Double? = nil,
        interruptionCount: Int = 0
    ) {
        self.id = id
        self.startedAt = startedAt
        self.articleCount = max(0, articleCount)
        self.totalDwellSeconds = max(0, totalDwellSeconds)
        self.scrollEventCount = max(0, scrollEventCount)
        self.topicsRead = topicsRead.map { $0.lowercased() }
        self.feedsRead = feedsRead
        self.sentimentScore = sentimentScore
        self.interruptionCount = max(0, interruptionCount)
    }
}

// MARK: - Verdict

/// Overall fatigue verdict tier for a reading window.
public enum FatigueVerdict: String, CaseIterable, Comparable, Sendable {
    case fresh
    case engaged
    case mildFatigue
    case heavyFatigue
    case burnout

    private var ordinal: Int {
        switch self {
        case .fresh:        return 0
        case .engaged:      return 1
        case .mildFatigue:  return 2
        case .heavyFatigue: return 3
        case .burnout:      return 4
        }
    }

    public static func < (lhs: FatigueVerdict, rhs: FatigueVerdict) -> Bool {
        lhs.ordinal < rhs.ordinal
    }

    public var emoji: String {
        switch self {
        case .fresh:        return "🌿"
        case .engaged:      return "📖"
        case .mildFatigue:  return "😐"
        case .heavyFatigue: return "😵"
        case .burnout:      return "🔥"
        }
    }

    public var description: String {
        switch self {
        case .fresh:        return "Reader is fresh and well-paced."
        case .engaged:      return "Reader is engaged with mild signals."
        case .mildFatigue:  return "Mild reading fatigue is building."
        case .heavyFatigue: return "Heavy fatigue — recovery actions recommended."
        case .burnout:      return "Burnout — break required."
        }
    }
}

// MARK: - Signals

/// Distinct fatigue signals detected over the lookback window.
public enum FatigueSignal: String, CaseIterable, Sendable {
    case sessionOverload
    case dwellCollapse
    case skimDominance
    case topicMonoculture
    case negativeSentimentSpike
    case lateNightBingeing
    case interruptionStorm
    case sourceMonoculture
    case weekendMarathon
    case streakWithoutBreak

    public var emoji: String {
        switch self {
        case .sessionOverload:        return "📈"
        case .dwellCollapse:          return "📉"
        case .skimDominance:          return "👀"
        case .topicMonoculture:       return "🥱"
        case .negativeSentimentSpike: return "🌧️"
        case .lateNightBingeing:      return "🦉"
        case .interruptionStorm:      return "🔔"
        case .sourceMonoculture:      return "📰"
        case .weekendMarathon:        return "🏃"
        case .streakWithoutBreak:     return "🛌"
        }
    }

    public var description: String {
        switch self {
        case .sessionOverload:        return "Too many long sessions packed into a single day."
        case .dwellCollapse:          return "Average dwell time per article is dropping vs baseline."
        case .skimDominance:          return "Scroll-to-article ratio dominated by skimming."
        case .topicMonoculture:       return "Topic mix has collapsed — low Shannon entropy."
        case .negativeSentimentSpike: return "Rolling sentiment skewed negative — heavy material streak."
        case .lateNightBingeing:      return "Multiple sessions started between 23:00 and 04:00."
        case .interruptionStorm:      return "High interruption rate per article — fragmented reading."
        case .sourceMonoculture:      return "One feed accounts for the majority of articles read."
        case .weekendMarathon:        return "Single weekend day exceeded 3h of total dwell."
        case .streakWithoutBreak:     return "14+ consecutive days with at least one session."
        }
    }

    /// Base severity weight (0..1) before contextual modifiers.
    public var baseSeverity: Double {
        switch self {
        case .sessionOverload:        return 0.85
        case .dwellCollapse:          return 0.70
        case .skimDominance:          return 0.60
        case .topicMonoculture:       return 0.55
        case .negativeSentimentSpike: return 0.80
        case .lateNightBingeing:      return 0.75
        case .interruptionStorm:      return 0.55
        case .sourceMonoculture:      return 0.50
        case .weekendMarathon:        return 0.45
        case .streakWithoutBreak:     return 0.70
        }
    }
}

// MARK: - Actions

/// Recommended remediation actions surfaced in the playbook.
public enum FatigueAction: String, CaseIterable, Sendable {
    case takeReadingBreak
    case diversifyTopics
    case addPalateCleanser
    case enforceQuietHours
    case archiveBacklog
    case switchToLongForm
    case addSecondarySources
    case pauseHeavyFeeds
    case scheduleDigestMode
    case celebrateProgress
    case scheduleReadingAudit

    public var emoji: String {
        switch self {
        case .takeReadingBreak:     return "🛑"
        case .diversifyTopics:      return "🌈"
        case .addPalateCleanser:    return "🍋"
        case .enforceQuietHours:    return "🌙"
        case .archiveBacklog:       return "🗄️"
        case .switchToLongForm:     return "📚"
        case .addSecondarySources:  return "🧭"
        case .pauseHeavyFeeds:      return "⏸️"
        case .scheduleDigestMode:   return "📬"
        case .celebrateProgress:    return "🎉"
        case .scheduleReadingAudit: return "🔍"
        }
    }

    public var description: String {
        switch self {
        case .takeReadingBreak:     return "Take at least one full day off from reading."
        case .diversifyTopics:      return "Surface articles from under-read topic clusters."
        case .addPalateCleanser:    return "Inject a light/positive piece between heavy reads."
        case .enforceQuietHours:    return "Block the feed UI between 23:00 and 06:00."
        case .archiveBacklog:       return "Bulk-archive stale unread items to reduce pressure."
        case .switchToLongForm:     return "Replace skimming with a single deep read."
        case .addSecondarySources:  return "Add secondary sources to break the source monoculture."
        case .pauseHeavyFeeds:      return "Temporarily mute the heaviest-sentiment feeds."
        case .scheduleDigestMode:   return "Switch to a daily digest rollup instead of live feeds."
        case .celebrateProgress:    return "Healthy reading pattern — keep it up."
        case .scheduleReadingAudit: return "Schedule a reflective reading-habits audit."
        }
    }
}

// MARK: - Priority

/// Priority bucket assigned to findings and playbook items.
public enum FatiguePriority: String, CaseIterable, Comparable, Sendable {
    case p0, p1, p2, p3

    private var ordinal: Int {
        switch self {
        case .p0: return 0
        case .p1: return 1
        case .p2: return 2
        case .p3: return 3
        }
    }

    public static func < (lhs: FatiguePriority, rhs: FatiguePriority) -> Bool {
        lhs.ordinal < rhs.ordinal
    }
}

// MARK: - Risk Appetite

/// Tunes thresholds and severity multipliers.
public enum FatigueRiskAppetite: String, CaseIterable, Sendable {
    case cautious
    case balanced
    case aggressive

    public var severityMultiplier: Double {
        switch self {
        case .cautious:   return 1.15
        case .balanced:   return 1.0
        case .aggressive: return 0.85
        }
    }
}

// MARK: - Findings & Playbook

/// A single fatigue signal observation with evidence and recommended actions.
public struct FatigueFinding: Sendable {
    /// The signal that was triggered.
    public let signal: FatigueSignal
    /// Severity in `0...100` after risk-appetite scaling.
    public let severity: Double
    /// Priority bucket derived from severity + signal class.
    public let priority: FatiguePriority
    /// Human-readable evidence lines, suitable for display.
    public let evidence: [String]
    /// Actions recommended for this finding (deduped into the playbook).
    public let recommendedActions: [FatigueAction]
}

/// A deduped, prioritised playbook entry derived from one or more findings.
public struct FatiguePlaybookItem: Sendable {
    /// Stable identifier (`action_signal`) used for deduplication.
    public let id: String
    /// Priority bucket inherited from the originating finding.
    public let priority: FatiguePriority
    /// The action the reader is being asked to take.
    public let action: FatigueAction
    /// Short, action-oriented summary fit for a list row.
    public let headline: String
    /// One-line rationale referencing the triggering signal.
    public let reason: String
    /// Blast-radius estimate (`1` = local, higher = more disruptive).
    public let blastRadius: Int
    /// Reversibility tag (`"high"` / `"medium"` / `"low"`).
    public let reversibility: String
    /// Estimated points the composite fatigue score would shift if applied.
    public let estFatigueDelta: Double
}

// MARK: - Report

/// Complete fatigue analysis report produced by ``FeedReadingFatigueAdvisor/analyze(sessions:)``.
public struct FatigueReport: Sendable {
    /// Wall-clock time at which the report was generated (uses the advisor's `now` provider).
    public let generatedAt: Date
    /// Overall verdict tier covering the lookback window.
    public let verdict: FatigueVerdict
    /// Composite fatigue score in `0...100`.
    public let fatigueScore: Double
    /// Letter grade `A`–`F` derived from the verdict.
    public let grade: String
    /// All fatigue findings, sorted by priority then severity then signal name.
    public let findings: [FatigueFinding]
    /// Deduped, prioritised playbook of recommended actions.
    public let playbook: [FatiguePlaybookItem]
    /// Higher-level qualitative insights (e.g. `BURNOUT_COMBO`, `ECHO_CHAMBER`).
    public let insights: [String]
    /// One-line headline summarising the verdict and counts.
    public let summaryHeadline: String

    // MARK: Renderers

    /// Renders the report as a plain-text block suitable for logs or CLI output.
    public func renderText() -> String {
        var lines: [String] = []
        lines.append("VERDICT: \(verdict.emoji) \(verdict.rawValue) grade=\(grade) fatigue=\(Int(fatigueScore.rounded()))/100")
        lines.append(summaryHeadline)
        if !findings.isEmpty {
            lines.append("")
            lines.append("Findings:")
            for f in findings {
                lines.append("  \(f.signal.emoji) [\(f.priority.rawValue)] \(f.signal.rawValue) sev=\(Int(f.severity.rounded()))")
                for e in f.evidence {
                    lines.append("    - \(e)")
                }
            }
        }
        if !playbook.isEmpty {
            lines.append("")
            lines.append("Playbook:")
            for p in playbook {
                lines.append("  \(p.action.emoji) [\(p.priority.rawValue)] \(p.headline) (blast=\(p.blastRadius), rev=\(p.reversibility))")
                lines.append("      reason: \(p.reason)")
            }
        }
        if !insights.isEmpty {
            lines.append("")
            lines.append("Insights:")
            for i in insights {
                lines.append("  • \(i)")
            }
        }
        return lines.joined(separator: "\n")
    }

    /// Renders the report as a Markdown document with summary, findings, playbook, and insights sections.
    public func renderMarkdown() -> String {
        var lines: [String] = []
        lines.append("# Reading Fatigue Report")
        lines.append("")
        lines.append("## Summary")
        lines.append("")
        lines.append("- **Verdict:** \(verdict.emoji) `\(verdict.rawValue)`")
        lines.append("- **Grade:** `\(grade)`")
        lines.append("- **Fatigue score:** `\(Int(fatigueScore.rounded()))/100`")
        lines.append("- **Headline:** \(summaryHeadline)")
        lines.append("")
        lines.append("## Findings")
        lines.append("")
        if findings.isEmpty {
            lines.append("_No fatigue signals fired in the lookback window._")
        } else {
            lines.append("| Priority | Signal | Severity | Evidence |")
            lines.append("| --- | --- | --- | --- |")
            for f in findings {
                let ev = f.evidence.joined(separator: "; ").replacingOccurrences(of: "|", with: "\\|")
                lines.append("| \(f.priority.rawValue) | \(f.signal.emoji) \(f.signal.rawValue) | \(Int(f.severity.rounded())) | \(ev) |")
            }
        }
        lines.append("")
        lines.append("## Playbook")
        lines.append("")
        if playbook.isEmpty {
            lines.append("_No actions recommended._")
        } else {
            lines.append("| Priority | Action | Headline | Blast | Reversibility |")
            lines.append("| --- | --- | --- | --- | --- |")
            for p in playbook {
                let h = p.headline.replacingOccurrences(of: "|", with: "\\|")
                lines.append("| \(p.priority.rawValue) | \(p.action.emoji) \(p.action.rawValue) | \(h) | \(p.blastRadius) | \(p.reversibility) |")
            }
        }
        lines.append("")
        lines.append("## Insights")
        lines.append("")
        for i in insights {
            lines.append("- \(i)")
        }
        return lines.joined(separator: "\n")
    }

    /// Byte-stable JSON (sorted keys, pretty-printed, ISO8601 dates).
    public func renderJSON() throws -> String {
        let snapshot = ReportJSON(report: self)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .prettyPrinted]
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(snapshot)
        return String(data: data, encoding: .utf8) ?? ""
    }
}

// MARK: - JSON snapshot

private struct ReportJSON: Codable {
    let generatedAt: Date
    let verdict: String
    let fatigueScore: Double
    let grade: String
    let summaryHeadline: String
    let findings: [FindingJSON]
    let playbook: [PlaybookJSON]
    let insights: [String]

    init(report: FatigueReport) {
        self.generatedAt = report.generatedAt
        self.verdict = report.verdict.rawValue
        // Round to 2dp for byte-stability.
        self.fatigueScore = (report.fatigueScore * 100).rounded() / 100
        self.grade = report.grade
        self.summaryHeadline = report.summaryHeadline
        self.findings = report.findings.map(FindingJSON.init)
        self.playbook = report.playbook.map(PlaybookJSON.init)
        self.insights = report.insights
    }
}

private struct FindingJSON: Codable {
    let signal: String
    let severity: Double
    let priority: String
    let evidence: [String]
    let recommendedActions: [String]

    init(_ f: FatigueFinding) {
        self.signal = f.signal.rawValue
        self.severity = (f.severity * 100).rounded() / 100
        self.priority = f.priority.rawValue
        self.evidence = f.evidence
        self.recommendedActions = f.recommendedActions.map { $0.rawValue }
    }
}

private struct PlaybookJSON: Codable {
    let id: String
    let priority: String
    let action: String
    let headline: String
    let reason: String
    let blastRadius: Int
    let reversibility: String
    let estFatigueDelta: Double

    init(_ p: FatiguePlaybookItem) {
        self.id = p.id
        self.priority = p.priority.rawValue
        self.action = p.action.rawValue
        self.headline = p.headline
        self.reason = p.reason
        self.blastRadius = p.blastRadius
        self.reversibility = p.reversibility
        self.estFatigueDelta = (p.estFatigueDelta * 100).rounded() / 100
    }
}

// MARK: - Advisor

/// Agentic reading-fatigue advisor.
///
/// `FeedReadingFatigueAdvisor` is deterministic given a fixed `now` provider:
/// the same inputs always produce the same report. The advisor never mutates
/// or persists the input sessions. Configure ``riskAppetite`` and
/// ``lookbackDays`` before calling ``analyze(sessions:)``.
public final class FeedReadingFatigueAdvisor {
    /// Tunes detector thresholds and severity multipliers. Defaults to `.balanced`.
    public var riskAppetite: FatigueRiskAppetite = .balanced
    /// Number of days back from `now` to include in analysis. Clamped to `>= 1` at use.
    public var lookbackDays: Int = 14

    private let nowProvider: () -> Date

    /// Creates an advisor.
    ///
    /// - Parameter now: Closure returning the current time. Defaults to `Date.init`.
    ///   Inject a fixed-time closure in tests to get reproducible reports.
    public init(now: @escaping () -> Date = Date.init) {
        self.nowProvider = now
    }

    // MARK: Public entry

    /// Analyzes the supplied sessions and produces a complete fatigue report.
    ///
    /// Only sessions whose `startedAt` falls within the last ``lookbackDays``
    /// (and not in the future relative to the advisor's `now`) are considered.
    /// Sessions are processed in chronological order; the input array is not
    /// mutated.
    ///
    /// - Parameter sessions: Sessions to analyze.
    /// - Returns: A fully populated ``FatigueReport``.
    public func analyze(sessions: [ReadingSession]) -> FatigueReport {
        let now = nowProvider()
        let window: TimeInterval = TimeInterval(max(1, lookbackDays) * 86_400)
        let cutoff = now.addingTimeInterval(-window)
        let recent = sessions
            .filter { $0.startedAt >= cutoff && $0.startedAt <= now }
            .sorted { $0.startedAt < $1.startedAt }

        var findings: [FatigueFinding] = []

        findings.append(contentsOf: detectSessionOverload(recent, now: now))
        if let f = detectDwellCollapse(recent) { findings.append(f) }
        if let f = detectSkimDominance(recent) { findings.append(f) }
        if let f = detectTopicMonoculture(recent) { findings.append(f) }
        if let f = detectNegativeSentimentSpike(recent) { findings.append(f) }
        if let f = detectLateNightBingeing(recent) { findings.append(f) }
        if let f = detectInterruptionStorm(recent) { findings.append(f) }
        if let f = detectSourceMonoculture(recent) { findings.append(f) }
        if let f = detectWeekendMarathon(recent) { findings.append(f) }
        if let f = detectStreakWithoutBreak(recent, now: now) { findings.append(f) }

        // Stable order: priority asc, severity desc, signal rawValue asc.
        findings.sort { lhs, rhs in
            if lhs.priority != rhs.priority { return lhs.priority < rhs.priority }
            if lhs.severity != rhs.severity { return lhs.severity > rhs.severity }
            return lhs.signal.rawValue < rhs.signal.rawValue
        }

        // Scoring.
        let mult = riskAppetite.severityMultiplier
        let sortedBySeverity = findings.sorted { $0.severity > $1.severity }
        let top = sortedBySeverity.first?.severity ?? 0
        let restSum = sortedBySeverity.dropFirst().map { $0.severity }.reduce(0, +)
        var raw = top + 0.4 * min(restSum, 60)
        raw *= mult
        let fatigueScore = max(0, min(100, raw))

        // Verdict.
        let hasBurnoutCombo = findings.contains { $0.signal == .negativeSentimentSpike }
            && findings.contains { $0.signal == .sessionOverload }
        let verdict: FatigueVerdict
        if fatigueScore >= 80 || hasBurnoutCombo {
            verdict = .burnout
        } else if fatigueScore >= 60 {
            verdict = .heavyFatigue
        } else if fatigueScore >= 35 {
            verdict = .mildFatigue
        } else if fatigueScore >= 15 {
            verdict = .engaged
        } else {
            verdict = .fresh
        }

        // Grade.
        let grade: String
        switch verdict {
        case .burnout:      grade = "F"
        case .heavyFatigue: grade = "D"
        case .mildFatigue:  grade = "C"
        case .engaged:      grade = "B"
        case .fresh:        grade = "A"
        }

        // Playbook.
        var playbook = buildPlaybook(findings: findings, verdict: verdict, grade: grade)
        if riskAppetite == .cautious, (grade == "C" || grade == "D" || grade == "F") {
            let item = FatiguePlaybookItem(
                id: "schedule_reading_audit",
                priority: .p2,
                action: .scheduleReadingAudit,
                headline: "Schedule a reflective reading-habits audit",
                reason: "Cautious appetite + grade \(grade): reserve 30 minutes to review reading data.",
                blastRadius: 1,
                reversibility: "high",
                estFatigueDelta: -3
            )
            playbook.append(item)
        }
        if riskAppetite == .aggressive {
            let hasHigher = playbook.contains { $0.priority == .p0 || $0.priority == .p1 }
            if hasHigher {
                playbook.removeAll {
                    $0.priority == .p3 && $0.action == .celebrateProgress
                }
            }
        }

        // Deterministic sort: priority asc, action rawValue asc, id asc.
        playbook.sort { lhs, rhs in
            if lhs.priority != rhs.priority { return lhs.priority < rhs.priority }
            if lhs.action.rawValue != rhs.action.rawValue {
                return lhs.action.rawValue < rhs.action.rawValue
            }
            return lhs.id < rhs.id
        }

        // Insights.
        let insights = buildInsights(findings: findings, verdict: verdict, recent: recent)

        // Headline.
        let headline = "Reader is \(verdict.rawValue) over the last \(lookbackDays) days — \(findings.count) signal(s), \(playbook.count) action(s)."

        return FatigueReport(
            generatedAt: now,
            verdict: verdict,
            fatigueScore: fatigueScore,
            grade: grade,
            findings: findings,
            playbook: playbook,
            insights: insights,
            summaryHeadline: headline
        )
    }

    // MARK: Detectors

    private func scaledSeverity(_ signal: FatigueSignal, _ intensity: Double) -> Double {
        // intensity in [0,1] is a fraction-of-evidence; severity in [0,100].
        let clamped = max(0, min(1, intensity))
        return signal.baseSeverity * 100.0 * clamped
    }

    private func priorityFor(_ severity: Double, signal: FatigueSignal) -> FatiguePriority {
        // Sentiment + overload are always at least P1.
        let burnoutSignals: Set<FatigueSignal> = [.negativeSentimentSpike, .sessionOverload, .lateNightBingeing]
        if severity >= 70 { return .p0 }
        if burnoutSignals.contains(signal) && severity >= 50 { return .p0 }
        if severity >= 50 { return .p1 }
        if severity >= 30 { return .p2 }
        return .p3
    }

    private func detectSessionOverload(_ sessions: [ReadingSession], now: Date) -> [FatigueFinding] {
        guard !sessions.isEmpty else { return [] }
        let cal = Calendar(identifier: .gregorian)
        var perDay: [DateComponents: Int] = [:]
        for s in sessions where s.totalDwellSeconds >= 900 { // >=15min counts as a "long" session
            let comps = cal.dateComponents([.year, .month, .day], from: s.startedAt)
            perDay[comps, default: 0] += 1
        }
        let threshold = riskAppetite == .cautious ? 3 : (riskAppetite == .aggressive ? 5 : 4)
        let breaches = perDay.filter { $0.value >= threshold }
        guard !breaches.isEmpty else { return [] }
        let worst = breaches.values.max() ?? threshold
        let intensity = min(1.0, Double(worst) / Double(threshold + 2))
        let sev = scaledSeverity(.sessionOverload, intensity)
        let evidence = breaches.keys.sorted { ($0.year ?? 0, $0.month ?? 0, $0.day ?? 0) < ($1.year ?? 0, $1.month ?? 0, $1.day ?? 0) }.map { dc -> String in
            return "\(dc.year ?? 0)-\(String(format: "%02d", dc.month ?? 0))-\(String(format: "%02d", dc.day ?? 0)): \(perDay[dc] ?? 0) long sessions"
        }
        return [FatigueFinding(
            signal: .sessionOverload,
            severity: sev,
            priority: priorityFor(sev, signal: .sessionOverload),
            evidence: evidence,
            recommendedActions: [.takeReadingBreak, .scheduleDigestMode, .archiveBacklog]
        )]
    }

    private func detectDwellCollapse(_ sessions: [ReadingSession]) -> FatigueFinding? {
        guard sessions.count >= 6 else { return nil }
        let half = sessions.count / 2
        let baseline = sessions.prefix(half)
        let recent = sessions.suffix(sessions.count - half)
        let baseAvg = avgDwellPerArticle(Array(baseline))
        let recentAvg = avgDwellPerArticle(Array(recent))
        guard baseAvg > 0 else { return nil }
        let drop = (baseAvg - recentAvg) / baseAvg
        guard drop > 0.40 else { return nil }
        let intensity = min(1.0, (drop - 0.40) / 0.40 + 0.5)
        let sev = scaledSeverity(.dwellCollapse, intensity)
        let evidence = [
            String(format: "Baseline avg dwell %.1fs/article", baseAvg),
            String(format: "Recent avg dwell %.1fs/article", recentAvg),
            String(format: "Drop %.0f%%", drop * 100)
        ]
        return FatigueFinding(
            signal: .dwellCollapse,
            severity: sev,
            priority: priorityFor(sev, signal: .dwellCollapse),
            evidence: evidence,
            recommendedActions: [.switchToLongForm, .archiveBacklog]
        )
    }

    private func avgDwellPerArticle(_ sessions: [ReadingSession]) -> Double {
        let totalDwell = sessions.reduce(0.0) { $0 + $1.totalDwellSeconds }
        let totalArticles = sessions.reduce(0) { $0 + $1.articleCount }
        guard totalArticles > 0 else { return 0 }
        return totalDwell / Double(totalArticles)
    }

    private func detectSkimDominance(_ sessions: [ReadingSession]) -> FatigueFinding? {
        let totalArticles = sessions.reduce(0) { $0 + $1.articleCount }
        let totalScrolls = sessions.reduce(0) { $0 + $1.scrollEventCount }
        guard totalArticles >= 10 else { return nil }
        let ratio = Double(totalScrolls) / Double(totalArticles)
        let threshold: Double = riskAppetite == .cautious ? 6.0 : (riskAppetite == .aggressive ? 10.0 : 8.0)
        guard ratio >= threshold else { return nil }
        let intensity = min(1.0, (ratio - threshold) / threshold + 0.5)
        let sev = scaledSeverity(.skimDominance, intensity)
        return FatigueFinding(
            signal: .skimDominance,
            severity: sev,
            priority: priorityFor(sev, signal: .skimDominance),
            evidence: [String(format: "%.1f scroll events per article over %d articles", ratio, totalArticles)],
            recommendedActions: [.switchToLongForm, .archiveBacklog]
        )
    }

    private func detectTopicMonoculture(_ sessions: [ReadingSession]) -> FatigueFinding? {
        var counts: [String: Int] = [:]
        for s in sessions {
            for t in s.topicsRead {
                let k = t.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !k.isEmpty else { continue }
                counts[k, default: 0] += 1
            }
        }
        let total = counts.values.reduce(0, +)
        guard total >= 10, counts.count >= 2 else { return nil }
        let entropy = shannonEntropy(counts.values.map { Double($0) }, total: Double(total))
        let maxEntropy = log2(Double(counts.count))
        guard maxEntropy > 0 else { return nil }
        let normalized = entropy / maxEntropy
        let threshold: Double = riskAppetite == .cautious ? 0.65 : (riskAppetite == .aggressive ? 0.40 : 0.50)
        guard normalized < threshold else { return nil }
        let intensity = min(1.0, (threshold - normalized) / threshold + 0.4)
        let sev = scaledSeverity(.topicMonoculture, intensity)
        let topTopic = counts.max { $0.value < $1.value }?.key ?? "?"
        return FatigueFinding(
            signal: .topicMonoculture,
            severity: sev,
            priority: priorityFor(sev, signal: .topicMonoculture),
            evidence: [
                String(format: "Normalized topic entropy %.2f (threshold %.2f)", normalized, threshold),
                "Top topic: \(topTopic)"
            ],
            recommendedActions: [.diversifyTopics, .addPalateCleanser]
        )
    }

    private func shannonEntropy(_ counts: [Double], total: Double) -> Double {
        guard total > 0 else { return 0 }
        var h = 0.0
        for c in counts where c > 0 {
            let p = c / total
            h -= p * log2(p)
        }
        return h
    }

    private func detectNegativeSentimentSpike(_ sessions: [ReadingSession]) -> FatigueFinding? {
        let scored = sessions.compactMap { $0.sentimentScore }
        guard scored.count >= 4 else { return nil }
        let mean = scored.reduce(0, +) / Double(scored.count)
        let threshold: Double = riskAppetite == .cautious ? -0.20 : (riskAppetite == .aggressive ? -0.40 : -0.30)
        guard mean <= threshold else { return nil }
        let intensity = min(1.0, (threshold - mean) / 0.60 + 0.5)
        let sev = scaledSeverity(.negativeSentimentSpike, intensity)
        return FatigueFinding(
            signal: .negativeSentimentSpike,
            severity: sev,
            priority: priorityFor(sev, signal: .negativeSentimentSpike),
            evidence: [String(format: "Mean sentiment %.2f across %d scored sessions", mean, scored.count)],
            recommendedActions: [.pauseHeavyFeeds, .addPalateCleanser]
        )
    }

    private func detectLateNightBingeing(_ sessions: [ReadingSession]) -> FatigueFinding? {
        let cal = Calendar(identifier: .gregorian)
        var lateCount = 0
        var evidenceDays: [String] = []
        for s in sessions {
            let h = cal.component(.hour, from: s.startedAt)
            if h >= 23 || h < 4 {
                lateCount += 1
                let d = cal.dateComponents([.year, .month, .day, .hour], from: s.startedAt)
                evidenceDays.append("\(d.year ?? 0)-\(String(format: "%02d", d.month ?? 0))-\(String(format: "%02d", d.day ?? 0)) @ \(String(format: "%02d:00", d.hour ?? 0))")
            }
        }
        let threshold = riskAppetite == .cautious ? 2 : (riskAppetite == .aggressive ? 4 : 3)
        guard lateCount >= threshold else { return nil }
        let intensity = min(1.0, Double(lateCount) / Double(threshold + 2))
        let sev = scaledSeverity(.lateNightBingeing, intensity)
        return FatigueFinding(
            signal: .lateNightBingeing,
            severity: sev,
            priority: priorityFor(sev, signal: .lateNightBingeing),
            evidence: Array(evidenceDays.prefix(5)),
            recommendedActions: [.enforceQuietHours, .takeReadingBreak]
        )
    }

    private func detectInterruptionStorm(_ sessions: [ReadingSession]) -> FatigueFinding? {
        let totalArticles = sessions.reduce(0) { $0 + $1.articleCount }
        let totalInt = sessions.reduce(0) { $0 + $1.interruptionCount }
        guard totalArticles >= 10 else { return nil }
        let ratio = Double(totalInt) / Double(totalArticles)
        let threshold: Double = riskAppetite == .cautious ? 1.0 : (riskAppetite == .aggressive ? 2.5 : 1.6)
        guard ratio >= threshold else { return nil }
        let intensity = min(1.0, (ratio - threshold) / threshold + 0.5)
        let sev = scaledSeverity(.interruptionStorm, intensity)
        return FatigueFinding(
            signal: .interruptionStorm,
            severity: sev,
            priority: priorityFor(sev, signal: .interruptionStorm),
            evidence: [String(format: "%.2f interruptions per article over %d articles", ratio, totalArticles)],
            recommendedActions: [.scheduleDigestMode, .enforceQuietHours]
        )
    }

    private func detectSourceMonoculture(_ sessions: [ReadingSession]) -> FatigueFinding? {
        var feedCounts: [String: Int] = [:]
        var total = 0
        for s in sessions {
            for f in s.feedsRead {
                let k = f.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !k.isEmpty else { continue }
                feedCounts[k, default: 0] += 1
                total += 1
            }
        }
        guard total >= 10 else { return nil }
        guard let top = feedCounts.max(by: { $0.value < $1.value }) else { return nil }
        let share = Double(top.value) / Double(total)
        let threshold: Double = riskAppetite == .cautious ? 0.55 : (riskAppetite == .aggressive ? 0.80 : 0.70)
        guard share >= threshold else { return nil }
        let intensity = min(1.0, (share - threshold) / (1.0 - threshold + 0.01) + 0.4)
        let sev = scaledSeverity(.sourceMonoculture, intensity)
        return FatigueFinding(
            signal: .sourceMonoculture,
            severity: sev,
            priority: priorityFor(sev, signal: .sourceMonoculture),
            evidence: ["Top feed '\(top.key)' = \(Int((share * 100).rounded()))% of articles"],
            recommendedActions: [.addSecondarySources, .diversifyTopics]
        )
    }

    private func detectWeekendMarathon(_ sessions: [ReadingSession]) -> FatigueFinding? {
        let cal = Calendar(identifier: .gregorian)
        var perDay: [DateComponents: Double] = [:]
        for s in sessions {
            let comps = cal.dateComponents([.year, .month, .day, .weekday], from: s.startedAt)
            perDay[comps, default: 0] += s.totalDwellSeconds
        }
        let weekendBreaches = perDay.filter { entry in
            let wd = entry.key.weekday ?? 0
            return (wd == 1 || wd == 7) && entry.value >= 3 * 3600
        }
        guard !weekendBreaches.isEmpty else { return nil }
        let worst = weekendBreaches.values.max() ?? 0
        let intensity = min(1.0, (worst / 3600.0 - 3.0) / 4.0 + 0.4)
        let sev = scaledSeverity(.weekendMarathon, intensity)
        let evidence = weekendBreaches.keys.sorted { ($0.year ?? 0, $0.month ?? 0, $0.day ?? 0) < ($1.year ?? 0, $1.month ?? 0, $1.day ?? 0) }.map { dc -> String in
            let hours = (perDay[dc] ?? 0) / 3600
            return String(format: "%04d-%02d-%02d: %.1fh", dc.year ?? 0, dc.month ?? 0, dc.day ?? 0, hours)
        }
        return FatigueFinding(
            signal: .weekendMarathon,
            severity: sev,
            priority: priorityFor(sev, signal: .weekendMarathon),
            evidence: evidence,
            recommendedActions: [.takeReadingBreak, .scheduleDigestMode]
        )
    }

    private func detectStreakWithoutBreak(_ sessions: [ReadingSession], now: Date) -> FatigueFinding? {
        let cal = Calendar(identifier: .gregorian)
        var days = Set<DateComponents>()
        for s in sessions {
            days.insert(cal.dateComponents([.year, .month, .day], from: s.startedAt))
        }
        guard days.count >= 14 else { return nil }
        // Check for a 14-day window ending on the most recent session day with reads every day.
        let sortedDays = days.compactMap { cal.date(from: $0) }.sorted()
        guard let last = sortedDays.last else { return nil }
        var streak = 1
        var cursor = last
        while true {
            guard let prev = cal.date(byAdding: .day, value: -1, to: cursor) else { break }
            let prevComps = cal.dateComponents([.year, .month, .day], from: prev)
            if days.contains(prevComps) {
                streak += 1
                cursor = prev
            } else {
                break
            }
        }
        guard streak >= 14 else { return nil }
        let intensity = min(1.0, Double(streak - 14) / 14.0 + 0.5)
        let sev = scaledSeverity(.streakWithoutBreak, intensity)
        return FatigueFinding(
            signal: .streakWithoutBreak,
            severity: sev,
            priority: priorityFor(sev, signal: .streakWithoutBreak),
            evidence: ["Active streak: \(streak) consecutive days"],
            recommendedActions: [.takeReadingBreak, .enforceQuietHours]
        )
    }

    // MARK: Playbook

    private func buildPlaybook(findings: [FatigueFinding], verdict: FatigueVerdict, grade: String) -> [FatiguePlaybookItem] {
        var items: [FatiguePlaybookItem] = []
        var seen = Set<String>()

        func add(_ item: FatiguePlaybookItem) {
            if !seen.contains(item.id) {
                seen.insert(item.id)
                items.append(item)
            }
        }

        // Top-level break for burnout / heavy fatigue.
        if verdict == .burnout {
            add(FatiguePlaybookItem(
                id: "take_reading_break_p0",
                priority: .p0,
                action: .takeReadingBreak,
                headline: "Take at least 24h fully off the feed",
                reason: "Burnout verdict triggered; aggressive rest required.",
                blastRadius: 3,
                reversibility: "high",
                estFatigueDelta: -25
            ))
        } else if verdict == .heavyFatigue {
            add(FatiguePlaybookItem(
                id: "take_reading_break_p1",
                priority: .p1,
                action: .takeReadingBreak,
                headline: "Schedule a recovery day this week",
                reason: "Heavy fatigue detected — one rest day prevents escalation.",
                blastRadius: 2,
                reversibility: "high",
                estFatigueDelta: -15
            ))
        }

        for f in findings {
            for action in f.recommendedActions {
                let id = "\(action.rawValue)_\(f.signal.rawValue)"
                let priority: FatiguePriority
                if f.priority == .p0 { priority = .p0 }
                else if f.priority == .p1 { priority = .p1 }
                else { priority = .p2 }
                add(FatiguePlaybookItem(
                    id: id,
                    priority: priority,
                    action: action,
                    headline: actionHeadline(action),
                    reason: "Triggered by \(f.signal.rawValue) (severity \(Int(f.severity.rounded()))).",
                    blastRadius: blastRadiusFor(action),
                    reversibility: reversibilityFor(action),
                    estFatigueDelta: estDeltaFor(action)
                ))
            }
        }

        // P3 fallback when empty.
        if items.isEmpty {
            add(FatiguePlaybookItem(
                id: "celebrate_progress",
                priority: .p3,
                action: .celebrateProgress,
                headline: "Healthy reading pattern — keep it up",
                reason: "No fatigue signals fired in the lookback window.",
                blastRadius: 1,
                reversibility: "high",
                estFatigueDelta: 0
            ))
        }
        return items
    }

    private func actionHeadline(_ a: FatigueAction) -> String {
        switch a {
        case .takeReadingBreak:     return "Take a deliberate reading break"
        case .diversifyTopics:      return "Diversify the topic mix"
        case .addPalateCleanser:    return "Insert palate-cleansing reads"
        case .enforceQuietHours:    return "Enforce evening quiet hours"
        case .archiveBacklog:       return "Archive the stale backlog"
        case .switchToLongForm:     return "Switch to long-form deep reads"
        case .addSecondarySources:  return "Add secondary sources"
        case .pauseHeavyFeeds:      return "Pause heavy-sentiment feeds"
        case .scheduleDigestMode:   return "Switch to daily digest mode"
        case .celebrateProgress:    return "Celebrate the healthy pattern"
        case .scheduleReadingAudit: return "Schedule a reading-habits audit"
        }
    }

    private func blastRadiusFor(_ a: FatigueAction) -> Int {
        switch a {
        case .takeReadingBreak, .pauseHeavyFeeds: return 3
        case .archiveBacklog, .enforceQuietHours, .scheduleDigestMode: return 2
        default: return 1
        }
    }

    private func reversibilityFor(_ a: FatigueAction) -> String {
        switch a {
        case .archiveBacklog: return "medium"
        default: return "high"
        }
    }

    private func estDeltaFor(_ a: FatigueAction) -> Double {
        switch a {
        case .takeReadingBreak:     return -20
        case .enforceQuietHours:    return -12
        case .pauseHeavyFeeds:      return -10
        case .scheduleDigestMode:   return -8
        case .archiveBacklog:       return -6
        case .switchToLongForm:     return -6
        case .diversifyTopics:      return -5
        case .addSecondarySources:  return -5
        case .addPalateCleanser:    return -4
        case .scheduleReadingAudit: return -3
        case .celebrateProgress:    return 0
        }
    }

    // MARK: Insights

    private func buildInsights(findings: [FatigueFinding], verdict: FatigueVerdict, recent: [ReadingSession]) -> [String] {
        _ = recent
        _ = verdict
        var out: [String] = []
        if findings.contains(where: { $0.signal == .negativeSentimentSpike })
            && findings.contains(where: { $0.signal == .sessionOverload }) {
            out.append("BURNOUT_COMBO: heavy sentiment + session overload — protect the next 48 hours")
        }
        if findings.contains(where: { $0.signal == .lateNightBingeing }) {
            out.append("SLEEP_RISK: late-night sessions are eroding recovery time")
        }
        if findings.contains(where: { $0.signal == .topicMonoculture })
            && findings.contains(where: { $0.signal == .sourceMonoculture }) {
            out.append("ECHO_CHAMBER: both topic and source diversity are collapsing")
        }
        if findings.contains(where: { $0.signal == .skimDominance })
            && findings.contains(where: { $0.signal == .dwellCollapse }) {
            out.append("ATTENTION_FRAGMENTATION: skimming and dwell collapse co-occurring")
        }
        if findings.contains(where: { $0.signal == .streakWithoutBreak }) {
            out.append("NO_REST_DAY: 14+ day reading streak — schedule a true off-day")
        }
        if findings.isEmpty {
            out.append("HEALTHY_READING_PATTERN")
        }
        // Always return something.
        if out.isEmpty {
            out.append("READING_PATTERN_NOTABLE: review findings for details")
        }
        return out
    }
}
