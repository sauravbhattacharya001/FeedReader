//
//  FeedOutageForecaster.swift
//  FeedReaderCore
//
//  Agentic predictive advisor that forecasts which RSS feed sources are
//  likely to experience outages or degradation in the near future based
//  on historical fetch telemetry patterns.
//
//  Distinct from `FeedHealthMonitor` (reports *current* health status) —
//  this advisor projects *future* reliability based on trend analysis:
//  rising error rates, increasing latency, response-size shrinkage
//  (partial responses), certificate expiry proximity, and fetch-gap
//  irregularity.
//
//  Key capabilities:
//  - 7 predictive signals per feed: error_rate_trend, latency_trend,
//    response_shrinkage, fetch_gap_irregularity, certificate_expiry,
//    consecutive_soft_errors, content_staleness_acceleration
//  - 0..100 composite `outageRisk` score per feed, A..F grade
//  - 6 verdict tiers (imminent / likely / elevated / possible / unlikely / stable)
//  - P0-P3 prioritized playbook with blast-radius + reversibility
//  - Risk appetite knob (cautious / balanced / aggressive)
//  - Forecast horizon (hours) for time-to-predicted-outage
//  - Deterministic given a fixed `now` closure; never mutates inputs
//  - text / markdown / byte-stable JSON renderers
//
//  Usage:
//  ```swift
//  let forecaster = FeedOutageForecaster(now: { fixedDate })
//  forecaster.riskAppetite = .cautious
//  let report = forecaster.analyze(feeds: feedTelemetry)
//  print(report.renderMarkdown())
//  ```
//
//  All processing is on-device. Foundation only — no UIKit, no network.
//

import Foundation

// MARK: - Input Models

/// A single fetch attempt record for a feed.
public struct FetchAttempt: Sendable, Equatable {
    /// Timestamp of the fetch attempt.
    public let timestamp: Date
    /// HTTP status code (0 if network-level failure).
    public let statusCode: Int
    /// Response latency in milliseconds.
    public let latencyMs: Double
    /// Response body size in bytes (0 if failed).
    public let responseSizeBytes: Int
    /// Whether the fetch succeeded (2xx status).
    public let succeeded: Bool
    /// Optional TLS certificate expiry date observed.
    public let certExpiryDate: Date?

    public init(
        timestamp: Date,
        statusCode: Int,
        latencyMs: Double,
        responseSizeBytes: Int,
        succeeded: Bool,
        certExpiryDate: Date? = nil
    ) {
        self.timestamp = timestamp
        self.statusCode = max(0, statusCode)
        self.latencyMs = max(0, latencyMs)
        self.responseSizeBytes = max(0, responseSizeBytes)
        self.succeeded = succeeded
        self.certExpiryDate = certExpiryDate
    }
}

/// Telemetry for a single feed source.
public struct FeedTelemetry: Sendable {
    /// Feed display name.
    public let feedName: String
    /// Feed URL.
    public let feedURL: String
    /// Historical fetch attempts, ordered chronologically.
    public let attempts: [FetchAttempt]
    /// Whether this is a critical/high-priority feed for the user.
    public let isCritical: Bool

    public init(feedName: String, feedURL: String, attempts: [FetchAttempt], isCritical: Bool = false) {
        self.feedName = feedName
        self.feedURL = feedURL
        self.attempts = attempts.sorted { $0.timestamp < $1.timestamp }
        self.isCritical = isCritical
    }
}

// MARK: - Risk Appetite

/// Controls how aggressively the forecaster flags potential outages.
public enum OutageRiskAppetite: String, Sendable, CaseIterable {
    case cautious
    case balanced
    case aggressive

    var multiplier: Double {
        switch self {
        case .cautious: return 1.15
        case .balanced: return 1.0
        case .aggressive: return 0.85
        }
    }
}

// MARK: - Output Models

/// Verdict tier for a feed's predicted reliability.
public enum OutageVerdict: String, Sendable, CaseIterable, Comparable {
    case imminent
    case likely
    case elevated
    case possible
    case unlikely
    case stable

    private var order: Int {
        switch self {
        case .imminent: return 5
        case .likely: return 4
        case .elevated: return 3
        case .possible: return 2
        case .unlikely: return 1
        case .stable: return 0
        }
    }

    public static func < (lhs: OutageVerdict, rhs: OutageVerdict) -> Bool {
        return lhs.order < rhs.order
    }
}

/// Grade for overall portfolio outage risk.
public enum OutageGrade: String, Sendable, CaseIterable {
    case A, B, C, D, F
}

/// Priority tier for playbook actions.
public enum OutagePriority: Int, Sendable, Comparable {
    case p0 = 0, p1 = 1, p2 = 2, p3 = 3

    public static func < (lhs: OutagePriority, rhs: OutagePriority) -> Bool {
        return lhs.rawValue < rhs.rawValue
    }
}

/// Reason code for a signal detection.
public enum OutageReasonCode: String, Sendable {
    case errorRateRising = "ERROR_RATE_RISING"
    case latencyDegrading = "LATENCY_DEGRADING"
    case responseShrinking = "RESPONSE_SHRINKING"
    case fetchGapIrregular = "FETCH_GAP_IRREGULAR"
    case certificateExpiring = "CERTIFICATE_EXPIRING"
    case consecutiveSoftErrors = "CONSECUTIVE_SOFT_ERRORS"
    case contentStaleAccelerating = "CONTENT_STALE_ACCELERATING"
    case criticalAsset = "CRITICAL_ASSET"
    case insufficientData = "INSUFFICIENT_DATA"
}

/// Per-feed forecast result.
public struct FeedOutageForecast: Sendable {
    /// Feed name.
    public let feedName: String
    /// Feed URL.
    public let feedURL: String
    /// Composite outage risk score 0..100.
    public let outageRisk: Int
    /// Verdict tier.
    public let verdict: OutageVerdict
    /// Priority bucket.
    public let priority: OutagePriority
    /// Estimated hours until predicted outage (nil if stable/insufficient data).
    public let predictedHoursToOutage: Double?
    /// Detected reason codes.
    public let reasons: [OutageReasonCode]
    /// Whether this is a critical feed.
    public let isCritical: Bool
}

/// A recommended action in the playbook.
public struct OutagePlaybookAction: Sendable {
    public let id: String
    public let priority: OutagePriority
    public let label: String
    public let reason: String
    public let owner: String
    public let blastRadius: Int
    public let reversibility: String
    public let feedURLs: [String]
}

/// Cross-feed insight.
public struct OutageInsight: Sendable {
    public let code: String
    public let message: String
}

/// Full analysis report.
public struct OutageForecasterReport: Sendable {
    /// Per-feed forecasts sorted by outageRisk descending.
    public let forecasts: [FeedOutageForecast]
    /// Overall portfolio risk score 0..100.
    public let portfolioRisk: Int
    /// Overall grade.
    public let grade: OutageGrade
    /// Playbook actions sorted P0-first.
    public let playbook: [OutagePlaybookAction]
    /// Cross-feed insights.
    public let insights: [OutageInsight]
    /// Summary headline.
    public let headline: String
    /// Timestamp of analysis.
    public let generatedAt: Date
    /// Risk appetite used.
    public let riskAppetite: OutageRiskAppetite

    // MARK: - Renderers

    /// Plain-text summary.
    public func renderText() -> String {
        var lines: [String] = []
        lines.append(headline)
        lines.append("")
        lines.append("Portfolio risk: \(portfolioRisk)/100 | Grade: \(grade.rawValue)")
        lines.append("Feeds analyzed: \(forecasts.count)")
        lines.append("")
        let atRisk = forecasts.filter { $0.verdict >= .elevated }
        if !atRisk.isEmpty {
            lines.append("At-risk feeds:")
            for f in atRisk.prefix(10) {
                let hrs = f.predictedHoursToOutage.map { String(format: "%.0fh", $0) } ?? "?"
                lines.append("  [\(f.priority)] \(f.feedName) — \(f.verdict.rawValue) (risk=\(f.outageRisk), ETA=\(hrs))")
            }
            lines.append("")
        }
        if !playbook.isEmpty {
            lines.append("Playbook:")
            for a in playbook {
                lines.append("  [P\(a.priority.rawValue)] \(a.label) — \(a.reason)")
            }
            lines.append("")
        }
        if !insights.isEmpty {
            lines.append("Insights:")
            for i in insights { lines.append("  • \(i.message)") }
        }
        return lines.joined(separator: "\n")
    }

    /// Markdown report.
    public func renderMarkdown() -> String {
        var md: [String] = []
        md.append("## Summary\n")
        md.append("| Metric | Value |")
        md.append("|--------|-------|")
        md.append("| Portfolio Risk | \(portfolioRisk)/100 |")
        md.append("| Grade | \(grade.rawValue) |")
        md.append("| Feeds Analyzed | \(forecasts.count) |")
        md.append("| P0 Count | \(forecasts.filter { $0.priority == .p0 }.count) |")
        md.append("| P1 Count | \(forecasts.filter { $0.priority == .p1 }.count) |")
        md.append("| Risk Appetite | \(riskAppetite.rawValue) |")
        md.append("")
        md.append("## Feeds\n")
        md.append("| Feed | Verdict | Risk | Priority | ETA | Reasons |")
        md.append("|------|---------|------|----------|-----|---------|")
        for f in forecasts.prefix(15) {
            let hrs = f.predictedHoursToOutage.map { String(format: "%.0fh", $0) } ?? "-"
            let reasons = f.reasons.map { $0.rawValue }.joined(separator: ", ")
            md.append("| \(f.feedName) | \(f.verdict.rawValue) | \(f.outageRisk) | P\(f.priority.rawValue) | \(hrs) | \(reasons) |")
        }
        md.append("")
        md.append("## Playbook\n")
        if playbook.isEmpty {
            md.append("No actions required.")
        } else {
            md.append("| Priority | Action | Reason | Owner | Blast | Reversibility |")
            md.append("|----------|--------|--------|-------|-------|---------------|")
            for a in playbook {
                md.append("| P\(a.priority.rawValue) | \(a.label) | \(a.reason) | \(a.owner) | \(a.blastRadius) | \(a.reversibility) |")
            }
        }
        md.append("")
        md.append("## Insights\n")
        if insights.isEmpty {
            md.append("No notable signals.")
        } else {
            for i in insights { md.append("- **\(i.code)**: \(i.message)") }
        }
        return md.joined(separator: "\n")
    }

    /// Byte-stable JSON.
    public func renderJSON() -> String {
        var parts: [String] = []
        parts.append("{")
        parts.append("  \"generatedAt\": \"\(iso8601(generatedAt))\",")
        parts.append("  \"grade\": \"\(grade.rawValue)\",")
        parts.append("  \"headline\": \(jsonString(headline)),")
        parts.append("  \"insights\": [")
        for (i, ins) in insights.enumerated() {
            let comma = i < insights.count - 1 ? "," : ""
            parts.append("    {\"code\": \(jsonString(ins.code)), \"message\": \(jsonString(ins.message))}\(comma)")
        }
        parts.append("  ],")
        parts.append("  \"playbook\": [")
        for (i, a) in playbook.enumerated() {
            let comma = i < playbook.count - 1 ? "," : ""
            let urls = a.feedURLs.map { jsonString($0) }.joined(separator: ", ")
            parts.append("    {\"blastRadius\": \(a.blastRadius), \"feedURLs\": [\(urls)], \"id\": \(jsonString(a.id)), \"label\": \(jsonString(a.label)), \"owner\": \(jsonString(a.owner)), \"priority\": \(a.priority.rawValue), \"reason\": \(jsonString(a.reason)), \"reversibility\": \(jsonString(a.reversibility))}\(comma)")
        }
        parts.append("  ],")
        parts.append("  \"portfolioRisk\": \(portfolioRisk),")
        parts.append("  \"riskAppetite\": \"\(riskAppetite.rawValue)\",")
        parts.append("  \"forecasts\": [")
        for (i, f) in forecasts.enumerated() {
            let comma = i < forecasts.count - 1 ? "," : ""
            let hrs = f.predictedHoursToOutage.map { String(format: "%.1f", $0) } ?? "null"
            let reasons = f.reasons.map { jsonString($0.rawValue) }.joined(separator: ", ")
            parts.append("    {\"feedName\": \(jsonString(f.feedName)), \"feedURL\": \(jsonString(f.feedURL)), \"isCritical\": \(f.isCritical), \"outageRisk\": \(f.outageRisk), \"predictedHoursToOutage\": \(hrs), \"priority\": \(f.priority.rawValue), \"reasons\": [\(reasons)], \"verdict\": \(jsonString(f.verdict.rawValue))}\(comma)")
        }
        parts.append("  ]")
        parts.append("}")
        return parts.joined(separator: "\n")
    }

    private func iso8601(_ date: Date) -> String {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f.string(from: date)
    }

    private func jsonString(_ s: String) -> String {
        let escaped = s
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "\n", with: "\\n")
            .replacingOccurrences(of: "\r", with: "\\r")
            .replacingOccurrences(of: "\t", with: "\\t")
        return "\"\(escaped)\""
    }
}

// MARK: - Forecaster

/// Agentic outage forecaster for RSS feed sources.
public final class FeedOutageForecaster: @unchecked Sendable {

    /// Risk appetite for scoring.
    public var riskAppetite: OutageRiskAppetite = .balanced

    /// Injectable clock for deterministic testing.
    private let now: () -> Date

    /// Minimum number of fetch attempts required for meaningful analysis.
    private let minAttempts = 5

    public init(now: @escaping () -> Date = { Date() }) {
        self.now = now
    }

    /// Analyze feed telemetry and produce an outage forecast report.
    public func analyze(feeds: [FeedTelemetry]) -> OutageForecasterReport {
        let currentDate = now()
        var forecasts: [FeedOutageForecast] = []

        for feed in feeds {
            forecasts.append(analyzeFeed(feed, now: currentDate))
        }

        // Sort by risk descending
        forecasts.sort { $0.outageRisk > $1.outageRisk }

        let portfolioRisk = computePortfolioRisk(forecasts)
        let grade = computeGrade(forecasts: forecasts, portfolioRisk: portfolioRisk)
        let playbook = buildPlaybook(forecasts: forecasts, grade: grade)
        let insights = buildInsights(forecasts: forecasts, portfolioRisk: portfolioRisk)

        let p0Count = forecasts.filter { $0.priority == .p0 }.count
        let p1Count = forecasts.filter { $0.priority == .p1 }.count
        let headline = "VERDICT: grade=\(grade.rawValue) feeds=\(forecasts.count) P0=\(p0Count) P1=\(p1Count) portfolio_risk=\(portfolioRisk)"

        return OutageForecasterReport(
            forecasts: forecasts,
            portfolioRisk: portfolioRisk,
            grade: grade,
            playbook: playbook,
            insights: insights,
            headline: headline,
            generatedAt: currentDate,
            riskAppetite: riskAppetite
        )
    }

    // MARK: - Per-Feed Analysis

    private func analyzeFeed(_ feed: FeedTelemetry, now: Date) -> FeedOutageForecast {
        let attempts = feed.attempts

        guard attempts.count >= minAttempts else {
            return FeedOutageForecast(
                feedName: feed.feedName,
                feedURL: feed.feedURL,
                outageRisk: 0,
                verdict: .stable,
                priority: .p3,
                predictedHoursToOutage: nil,
                reasons: [.insufficientData],
                isCritical: feed.isCritical
            )
        }

        var signals: [(score: Double, reason: OutageReasonCode)] = []

        // 1. Error rate trend (comparing recent half vs older half)
        let midpoint = attempts.count / 2
        let olderHalf = Array(attempts.prefix(midpoint))
        let recentHalf = Array(attempts.suffix(attempts.count - midpoint))

        let olderErrorRate = olderHalf.isEmpty ? 0.0 : Double(olderHalf.filter { !$0.succeeded }.count) / Double(olderHalf.count)
        let recentErrorRate = recentHalf.isEmpty ? 0.0 : Double(recentHalf.filter { !$0.succeeded }.count) / Double(recentHalf.count)

        if recentErrorRate > olderErrorRate + 0.10 {
            let delta = recentErrorRate - olderErrorRate
            signals.append((min(40.0 + delta * 100.0, 80.0), .errorRateRising))
        }

        // 2. Latency trend
        let olderLatency = olderHalf.isEmpty ? 0.0 : olderHalf.map { $0.latencyMs }.reduce(0, +) / Double(olderHalf.count)
        let recentLatency = recentHalf.isEmpty ? 0.0 : recentHalf.map { $0.latencyMs }.reduce(0, +) / Double(recentHalf.count)

        if olderLatency > 0 && recentLatency > olderLatency * 1.5 {
            let ratio = recentLatency / olderLatency
            signals.append((min(25.0 + (ratio - 1.5) * 30.0, 60.0), .latencyDegrading))
        }

        // 3. Response size shrinkage (partial responses / broken feeds)
        let olderSize = olderHalf.filter { $0.succeeded }.map { Double($0.responseSizeBytes) }
        let recentSize = recentHalf.filter { $0.succeeded }.map { Double($0.responseSizeBytes) }

        if let olderMean = olderSize.isEmpty ? nil : olderSize.reduce(0, +) / Double(olderSize.count),
           let recentMean = recentSize.isEmpty ? nil : recentSize.reduce(0, +) / Double(recentSize.count),
           olderMean > 100, recentMean < olderMean * 0.5 {
            signals.append((35.0, .responseShrinking))
        }

        // 4. Fetch gap irregularity (coefficient of variation of inter-fetch gaps)
        if attempts.count >= 4 {
            var gaps: [Double] = []
            for i in 1..<attempts.count {
                gaps.append(attempts[i].timestamp.timeIntervalSince(attempts[i-1].timestamp))
            }
            let meanGap = gaps.reduce(0, +) / Double(gaps.count)
            if meanGap > 0 {
                let variance = gaps.map { ($0 - meanGap) * ($0 - meanGap) }.reduce(0, +) / Double(gaps.count)
                let cv = sqrt(variance) / meanGap
                if cv > 1.5 {
                    signals.append((min(20.0 + (cv - 1.5) * 15.0, 45.0), .fetchGapIrregular))
                }
            }
        }

        // 5. Certificate expiry proximity
        if let lastAttempt = attempts.last, let certExpiry = lastAttempt.certExpiryDate {
            let daysToExpiry = certExpiry.timeIntervalSince(now) / 86400.0
            if daysToExpiry <= 7 && daysToExpiry > 0 {
                signals.append((60.0, .certificateExpiring))
            } else if daysToExpiry <= 30 && daysToExpiry > 7 {
                signals.append((30.0, .certificateExpiring))
            } else if daysToExpiry <= 0 {
                signals.append((90.0, .certificateExpiring))
            }
        }

        // 6. Consecutive soft errors (tail of attempts)
        let tailCount = min(attempts.count, 10)
        let tail = Array(attempts.suffix(tailCount))
        var consecutiveFails = 0
        for a in tail.reversed() {
            if !a.succeeded { consecutiveFails += 1 } else { break }
        }
        if consecutiveFails >= 3 {
            signals.append((min(30.0 + Double(consecutiveFails - 3) * 15.0, 80.0), .consecutiveSoftErrors))
        }

        // 7. Content staleness acceleration (time since last new content growing)
        let successfulAttempts = attempts.filter { $0.succeeded && $0.responseSizeBytes > 0 }
        if successfulAttempts.count >= 4 {
            let recentSuccessful = Array(successfulAttempts.suffix(4))
            var sizeChanges = 0
            for i in 1..<recentSuccessful.count {
                if recentSuccessful[i].responseSizeBytes != recentSuccessful[i-1].responseSizeBytes {
                    sizeChanges += 1
                }
            }
            if sizeChanges == 0 {
                // Content hasn't changed in last 4 successful fetches
                let staleDuration = now.timeIntervalSince(recentSuccessful.first!.timestamp)
                let staleHours = staleDuration / 3600.0
                if staleHours > 72 {
                    signals.append((min(20.0 + (staleHours - 72) * 0.5, 50.0), .contentStaleAccelerating))
                }
            }
        }

        // Compute composite risk
        let sortedSignals = signals.sorted { $0.score > $1.score }
        var rawRisk: Double = 0
        if let top = sortedSignals.first {
            rawRisk = top.score
            let rest = sortedSignals.dropFirst().map { $0.score }.reduce(0, +)
            rawRisk += 0.4 * min(rest, 60.0)
        }

        // Critical asset bump
        if feed.isCritical && rawRisk > 10 {
            rawRisk += 10
        }

        // Apply risk appetite
        rawRisk *= riskAppetite.multiplier

        let outageRisk = min(100, max(0, Int(rawRisk)))
        let reasons = sortedSignals.map { $0.reason }

        // Verdict
        let verdict: OutageVerdict
        switch outageRisk {
        case 80...100: verdict = .imminent
        case 65..<80: verdict = .likely
        case 45..<65: verdict = .elevated
        case 25..<45: verdict = .possible
        case 10..<25: verdict = .unlikely
        default: verdict = .stable
        }

        // Priority
        let priority: OutagePriority
        if outageRisk >= 75 || (feed.isCritical && outageRisk >= 60) { priority = .p0 }
        else if outageRisk >= 50 { priority = .p1 }
        else if outageRisk >= 25 { priority = .p2 }
        else { priority = .p3 }

        // Predicted hours to outage
        var predictedHours: Double? = nil
        if outageRisk >= 25 {
            // Rough projection: higher risk = sooner
            predictedHours = max(1.0, Double(200 - outageRisk * 2))
        }

        return FeedOutageForecast(
            feedName: feed.feedName,
            feedURL: feed.feedURL,
            outageRisk: outageRisk,
            verdict: verdict,
            priority: priority,
            predictedHoursToOutage: predictedHours,
            reasons: reasons,
            isCritical: feed.isCritical
        )
    }

    // MARK: - Portfolio

    private func computePortfolioRisk(_ forecasts: [FeedOutageForecast]) -> Int {
        guard !forecasts.isEmpty else { return 0 }
        let sorted = forecasts.sorted { $0.outageRisk > $1.outageRisk }
        let top3 = sorted.prefix(3)
        let worst = Double(sorted.first?.outageRisk ?? 0)
        let meanTop3 = top3.isEmpty ? 0.0 : Double(top3.map { $0.outageRisk }.reduce(0, +)) / Double(top3.count)
        return min(100, Int(worst * 0.6 + meanTop3 * 0.4))
    }

    private func computeGrade(forecasts: [FeedOutageForecast], portfolioRisk: Int) -> OutageGrade {
        let p0Count = forecasts.filter { $0.priority == .p0 }.count
        let hasCriticalP0 = forecasts.contains { $0.isCritical && $0.priority == .p0 }

        if hasCriticalP0 || p0Count >= 3 || portfolioRisk >= 75 { return .F }
        if p0Count >= 1 || portfolioRisk >= 55 { return .D }
        if portfolioRisk >= 35 { return .C }
        if portfolioRisk >= 18 { return .B }
        return .A
    }

    // MARK: - Playbook

    private func buildPlaybook(forecasts: [FeedOutageForecast], grade: OutageGrade) -> [OutagePlaybookAction] {
        var actions: [OutagePlaybookAction] = []
        var usedIds: Set<String> = []

        let imminent = forecasts.filter { $0.verdict == .imminent }
        let likely = forecasts.filter { $0.verdict == .likely }
        let elevated = forecasts.filter { $0.verdict == .elevated }

        // P0: Prepare backup sources for imminent outages
        if !imminent.isEmpty {
            let id = "PREPARE_BACKUP_SOURCES"
            if !usedIds.contains(id) {
                usedIds.insert(id)
                actions.append(OutagePlaybookAction(
                    id: id, priority: .p0,
                    label: "Prepare backup sources for feeds with imminent outage risk",
                    reason: "\(imminent.count) feed(s) show imminent outage signals",
                    owner: "user", blastRadius: 4, reversibility: "high",
                    feedURLs: imminent.map { $0.feedURL }
                ))
            }
        }

        // P0: Alert on critical feeds at risk
        let criticalAtRisk = forecasts.filter { $0.isCritical && $0.priority <= .p1 }
        if !criticalAtRisk.isEmpty {
            let id = "ALERT_CRITICAL_FEEDS_AT_RISK"
            if !usedIds.contains(id) {
                usedIds.insert(id)
                actions.append(OutagePlaybookAction(
                    id: id, priority: .p0,
                    label: "Alert: critical feeds showing reliability degradation",
                    reason: "\(criticalAtRisk.count) critical feed(s) at elevated risk",
                    owner: "user", blastRadius: 5, reversibility: "high",
                    feedURLs: criticalAtRisk.map { $0.feedURL }
                ))
            }
        }

        // P1: Investigate latency/error trends
        let degrading = forecasts.filter { $0.reasons.contains(.latencyDegrading) || $0.reasons.contains(.errorRateRising) }
        if !degrading.isEmpty {
            let id = "INVESTIGATE_DEGRADATION_TREND"
            if !usedIds.contains(id) {
                usedIds.insert(id)
                actions.append(OutagePlaybookAction(
                    id: id, priority: .p1,
                    label: "Investigate feeds with rising error rates or latency",
                    reason: "\(degrading.count) feed(s) show degradation trends",
                    owner: "platform", blastRadius: 3, reversibility: "high",
                    feedURLs: degrading.prefix(10).map { $0.feedURL }
                ))
            }
        }

        // P1: Renew certificates
        let certFeeds = forecasts.filter { $0.reasons.contains(.certificateExpiring) }
        if !certFeeds.isEmpty {
            let id = "RENEW_EXPIRING_CERTIFICATES"
            if !usedIds.contains(id) {
                usedIds.insert(id)
                actions.append(OutagePlaybookAction(
                    id: id, priority: .p1,
                    label: "Note: TLS certificates expiring soon on feed sources",
                    reason: "\(certFeeds.count) feed(s) have certificates expiring within 30 days",
                    owner: "platform", blastRadius: 3, reversibility: "medium",
                    feedURLs: certFeeds.map { $0.feedURL }
                ))
            }
        }

        // P2: Monitor elevated feeds
        if !elevated.isEmpty {
            let id = "MONITOR_ELEVATED_RISK_FEEDS"
            if !usedIds.contains(id) {
                usedIds.insert(id)
                actions.append(OutagePlaybookAction(
                    id: id, priority: .p2,
                    label: "Increase monitoring frequency for elevated-risk feeds",
                    reason: "\(elevated.count) feed(s) at elevated risk level",
                    owner: "platform", blastRadius: 2, reversibility: "high",
                    feedURLs: elevated.prefix(10).map { $0.feedURL }
                ))
            }
        }

        // P2: Schedule audit (cautious + grade C/D/F)
        if riskAppetite == .cautious && (grade == .C || grade == .D || grade == .F) {
            let id = "SCHEDULE_FEED_RELIABILITY_AUDIT"
            if !usedIds.contains(id) {
                usedIds.insert(id)
                actions.append(OutagePlaybookAction(
                    id: id, priority: .p2,
                    label: "Schedule feed reliability audit",
                    reason: "Portfolio grade \(grade.rawValue) warrants review",
                    owner: "user", blastRadius: 1, reversibility: "high",
                    feedURLs: []
                ))
            }
        }

        // P3: Fallback
        if actions.isEmpty {
            actions.append(OutagePlaybookAction(
                id: "MAINTAIN_FEED_MONITORING", priority: .p3,
                label: "Continue routine feed monitoring",
                reason: "No significant outage risks detected",
                owner: "platform", blastRadius: 1, reversibility: "high",
                feedURLs: []
            ))
        }

        // Aggressive trim: remove P3 when P0/P1 present
        if riskAppetite == .aggressive && actions.contains(where: { $0.priority <= .p1 }) {
            return actions.filter { $0.priority <= .p2 }
        }

        return actions.sorted { $0.priority < $1.priority }
    }

    // MARK: - Insights

    private func buildInsights(forecasts: [FeedOutageForecast], portfolioRisk: Int) -> [OutageInsight] {
        var insights: [OutageInsight] = []

        if forecasts.isEmpty {
            insights.append(OutageInsight(code: "NO_FEEDS_ANALYZED", message: "No feed telemetry provided"))
            return insights
        }

        let imminentCount = forecasts.filter { $0.verdict == .imminent }.count
        if imminentCount >= 2 {
            insights.append(OutageInsight(code: "MULTI_FEED_OUTAGE_CLUSTER", message: "\(imminentCount) feeds simultaneously showing imminent outage risk"))
        }

        let certCount = forecasts.filter { $0.reasons.contains(.certificateExpiring) }.count
        if certCount >= 2 {
            insights.append(OutageInsight(code: "CERTIFICATE_EXPIRY_WAVE", message: "\(certCount) feeds have certificates expiring soon"))
        }

        let errorTrendCount = forecasts.filter { $0.reasons.contains(.errorRateRising) }.count
        if errorTrendCount >= 3 {
            insights.append(OutageInsight(code: "WIDESPREAD_ERROR_TREND", message: "\(errorTrendCount) feeds show rising error rates — possible upstream issue"))
        }

        let staleCount = forecasts.filter { $0.reasons.contains(.contentStaleAccelerating) }.count
        if staleCount >= 3 {
            insights.append(OutageInsight(code: "CONTENT_STALENESS_CLUSTER", message: "\(staleCount) feeds showing accelerating staleness"))
        }

        let insufficientCount = forecasts.filter { $0.reasons.contains(.insufficientData) }.count
        if insufficientCount > forecasts.count / 2 {
            insights.append(OutageInsight(code: "SPARSE_TELEMETRY", message: "Over half of feeds lack sufficient data for forecasting"))
        }

        let criticalAtRisk = forecasts.filter { $0.isCritical && $0.priority <= .p1 }.count
        if criticalAtRisk >= 1 {
            insights.append(OutageInsight(code: "CRITICAL_FEEDS_AT_RISK", message: "\(criticalAtRisk) critical feed(s) at elevated or higher risk"))
        }

        if insights.isEmpty {
            if portfolioRisk < 15 {
                insights.append(OutageInsight(code: "HEALTHY_FEED_FLEET", message: "All monitored feeds show stable reliability"))
            } else {
                insights.append(OutageInsight(code: "NO_NOTABLE_SIGNALS", message: "No cross-feed patterns detected"))
            }
        }

        return insights
    }
}
