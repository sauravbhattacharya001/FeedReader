//
//  FeedBurnoutDetector.swift
//  FeedReader
//
//  Detects signs of information overload and reading burnout by
//  analyzing reading patterns over time. Monitors key indicators:
//  - Completion rate decline (opening but not finishing articles)
//  - Excessive session frequency (doom-scrolling detection)
//  - Late-night reading binges (unhealthy reading hours)
//  - Feed switching rate (rapid feed-hopping without reading)
//  - Unread article pile-up (growing backlog stress)
//  - Reading time spikes (sudden increases in daily reading)
//
//  Produces a BurnoutReport with a 0-100 risk score, individual
//  signal breakdowns, trend direction, and actionable suggestions.
//
//  All analysis is on-device. No network calls or external deps.
//  Persistence: JSON file in Documents directory.
//

import Foundation

// MARK: - Notifications

extension Notification.Name {
    /// Posted when a new burnout report is generated.
    static let burnoutReportDidUpdate = Notification.Name("BurnoutReportDidUpdateNotification")
}

// MARK: - Models

/// A single burnout signal with its own score and metadata.
struct BurnoutSignal: Codable {
    /// Signal identifier.
    let id: String
    /// Human-readable label.
    let label: String
    /// Score from 0 (healthy) to 100 (critical).
    let score: Int
    /// Severity level derived from score.
    var severity: BurnoutSeverity {
        switch score {
        case 0..<25: return .healthy
        case 25..<50: return .mild
        case 50..<75: return .moderate
        default: return .critical
        }
    }
    /// Description of what was detected.
    let detail: String
    /// The raw metric value.
    let rawValue: Double
    /// Threshold that triggered concern.
    let threshold: Double
}

/// Overall burnout severity.
enum BurnoutSeverity: String, Codable, CaseIterable, Comparable {
    case healthy = "healthy"
    case mild = "mild"
    case moderate = "moderate"
    case critical = "critical"

    var label: String {
        switch self {
        case .healthy: return "✅ Healthy"
        case .mild: return "⚠️ Mild Concern"
        case .moderate: return "🟠 Moderate Risk"
        case .critical: return "🔴 High Risk"
        }
    }

    var emoji: String {
        switch self {
        case .healthy: return "✅"
        case .mild: return "⚠️"
        case .moderate: return "🟠"
        case .critical: return "🔴"
        }
    }

    static func < (lhs: BurnoutSeverity, rhs: BurnoutSeverity) -> Bool {
        let order: [BurnoutSeverity] = [.healthy, .mild, .moderate, .critical]
        return order.firstIndex(of: lhs)! < order.firstIndex(of: rhs)!
    }
}

/// Trend direction for burnout risk over time.
enum BurnoutTrend: String, Codable {
    case improving = "improving"
    case stable = "stable"
    case worsening = "worsening"

    var label: String {
        switch self {
        case .improving: return "📉 Improving"
        case .stable: return "➡️ Stable"
        case .worsening: return "📈 Worsening"
        }
    }
}

/// A complete burnout assessment report.
struct BurnoutReport: Codable {
    /// When this report was generated.
    let generatedAt: Date
    /// Analysis window start.
    let windowStart: Date
    /// Analysis window end.
    let windowEnd: Date
    /// Overall burnout risk score (0-100).
    let overallScore: Int
    /// Overall severity.
    var severity: BurnoutSeverity {
        switch overallScore {
        case 0..<25: return .healthy
        case 25..<50: return .mild
        case 50..<75: return .moderate
        default: return .critical
        }
    }
    /// Trend compared to previous report.
    let trend: BurnoutTrend
    /// Individual signal breakdowns.
    let signals: [BurnoutSignal]
    /// Actionable suggestions.
    let suggestions: [String]
    /// Number of articles analyzed.
    let articlesAnalyzed: Int
    /// Number of sessions analyzed.
    let sessionsAnalyzed: Int
}

/// A recorded reading event for burnout analysis.
struct BurnoutReadingEvent: Codable {
    let timestamp: Date
    let feedURL: String
    let articleTitle: String
    let durationSeconds: Double
    let completionPercent: Double  // 0.0 to 1.0
    let wordCount: Int
}

/// Daily aggregate for trend tracking.
struct DailyBurnoutSnapshot: Codable {
    let date: Date
    let score: Int
    let articlesRead: Int
    let totalReadingMinutes: Double
    let avgCompletion: Double
    let lateNightMinutes: Double
}

// MARK: - Configuration

/// Tunable thresholds for burnout detection.
struct BurnoutConfig: Codable {
    /// Analysis window in days.
    var windowDays: Int = 7
    /// Completion rate below this % triggers concern (0-1).
    var completionThreshold: Double = 0.4
    /// Sessions per day above this count triggers concern.
    var sessionsPerDayThreshold: Double = 8.0
    /// Reading minutes after this hour (0-23) count as late-night.
    var lateNightStartHour: Int = 23
    /// Reading minutes before this hour count as late-night.
    var lateNightEndHour: Int = 5
    /// Late-night minutes per day above this triggers concern.
    var lateNightMinutesThreshold: Double = 30.0
    /// Feed switches per session above this triggers concern.
    var feedSwitchThreshold: Double = 10.0
    /// Unread count above this triggers pile-up concern.
    var unreadPileupThreshold: Int = 200
    /// Daily reading minutes above this triggers time-spike concern.
    var dailyMinutesThreshold: Double = 180.0
    /// Weight multipliers for each signal (must sum roughly to 6).
    var weights: [String: Double] = [
        "completion": 1.0,
        "session_frequency": 1.0,
        "late_night": 1.0,
        "feed_switching": 1.0,
        "unread_pileup": 1.0,
        "time_spike": 1.0
    ]
}

// MARK: - Persistence

/// Stores burnout history for trend analysis.
struct BurnoutHistory: Codable {
    var reports: [BurnoutReport] = []
    var dailySnapshots: [DailyBurnoutSnapshot] = []
    var config: BurnoutConfig = BurnoutConfig()
    var lastAnalyzedDate: Date?

    /// Keep only last 90 days of data.
    mutating func prune() {
        let cutoff = Calendar.current.date(byAdding: .day, value: -90, to: Date()) ?? Date()
        reports = reports.filter { $0.generatedAt > cutoff }
        dailySnapshots = dailySnapshots.filter { $0.date > cutoff }
    }
}

// MARK: - FeedBurnoutDetector

/// Analyzes reading patterns to detect information overload and burnout risk.
///
/// Usage:
/// ```swift
/// let detector = FeedBurnoutDetector()
///
/// // Record reading events as they happen
/// detector.recordEvent(BurnoutReadingEvent(
///     timestamp: Date(),
///     feedURL: "https://example.com/feed",
///     articleTitle: "Some Article",
///     durationSeconds: 120,
///     completionPercent: 0.3,
///     wordCount: 800
/// ))
///
/// // Generate a burnout report
/// let report = detector.analyze(unreadCount: 350)
/// print(report.severity.label)        // "🟠 Moderate Risk"
/// print(report.overallScore)          // 62
/// print(report.trend.label)           // "📈 Worsening"
/// for suggestion in report.suggestions {
///     print("💡 \(suggestion)")
/// }
///
/// // Get weekly summary
/// let summary = detector.weeklySummary()
/// ```
class FeedBurnoutDetector {

    // MARK: - Storage

    private let storageKey = "FeedBurnoutDetector"
    private var history: BurnoutHistory
    private var events: [BurnoutReadingEvent] = []

    private var storageURL: URL {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        return docs.appendingPathComponent("burnout_detector.json")
    }

    private var eventsURL: URL {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        return docs.appendingPathComponent("burnout_events.json")
    }

    // MARK: - Init

    init() {
        history = BurnoutHistory()
        load()
    }

    // MARK: - Event Recording

    /// Record a reading event for burnout analysis.
    func recordEvent(_ event: BurnoutReadingEvent) {
        events.append(event)
        pruneOldEvents()
        saveEvents()
    }

    /// Record multiple events at once.
    func recordEvents(_ newEvents: [BurnoutReadingEvent]) {
        events.append(contentsOf: newEvents)
        pruneOldEvents()
        saveEvents()
    }

    // MARK: - Analysis

    /// Run burnout analysis and produce a report.
    /// - Parameter unreadCount: Current total unread article count.
    /// - Returns: A BurnoutReport with scores, signals, and suggestions.
    func analyze(unreadCount: Int = 0) -> BurnoutReport {
        let config = history.config
        let now = Date()
        let windowStart = Calendar.current.date(byAdding: .day, value: -config.windowDays, to: now) ?? now
        let windowEvents = events.filter { $0.timestamp >= windowStart && $0.timestamp <= now }

        var signals: [BurnoutSignal] = []

        // 1. Completion Rate Decline
        let completionSignal = analyzeCompletion(events: windowEvents, config: config)
        signals.append(completionSignal)

        // 2. Session Frequency (doom-scrolling)
        let sessionSignal = analyzeSessionFrequency(events: windowEvents, config: config)
        signals.append(sessionSignal)

        // 3. Late-Night Reading
        let lateNightSignal = analyzeLateNight(events: windowEvents, config: config)
        signals.append(lateNightSignal)

        // 4. Feed Switching Rate
        let switchSignal = analyzeFeedSwitching(events: windowEvents, config: config)
        signals.append(switchSignal)

        // 5. Unread Pile-Up
        let pileupSignal = analyzeUnreadPileup(unreadCount: unreadCount, config: config)
        signals.append(pileupSignal)

        // 6. Reading Time Spikes
        let spikeSignal = analyzeTimeSpikes(events: windowEvents, config: config)
        signals.append(spikeSignal)

        // Calculate weighted overall score
        let totalWeight = signals.reduce(0.0) { sum, sig in
            sum + (config.weights[sig.id] ?? 1.0)
        }
        let weightedSum = signals.reduce(0.0) { sum, sig in
            sum + Double(sig.score) * (config.weights[sig.id] ?? 1.0)
        }
        let overallScore = totalWeight > 0 ? Int(weightedSum / totalWeight) : 0

        // Determine trend
        let trend = determineTrend(currentScore: overallScore)

        // Generate suggestions
        let suggestions = generateSuggestions(signals: signals, overallScore: overallScore)

        let report = BurnoutReport(
            generatedAt: now,
            windowStart: windowStart,
            windowEnd: now,
            overallScore: min(100, max(0, overallScore)),
            trend: trend,
            signals: signals,
            suggestions: suggestions,
            articlesAnalyzed: windowEvents.count,
            sessionsAnalyzed: countSessions(events: windowEvents)
        )

        // Save report and snapshot
        history.reports.append(report)
        let snapshot = DailyBurnoutSnapshot(
            date: now,
            score: report.overallScore,
            articlesRead: windowEvents.count,
            totalReadingMinutes: windowEvents.reduce(0) { $0 + $1.durationSeconds } / 60.0,
            avgCompletion: windowEvents.isEmpty ? 1.0 : windowEvents.reduce(0) { $0 + $1.completionPercent } / Double(windowEvents.count),
            lateNightMinutes: calculateLateNightMinutes(events: windowEvents, config: config)
        )
        history.dailySnapshots.append(snapshot)
        history.lastAnalyzedDate = now
        history.prune()
        save()

        NotificationCenter.default.post(name: .burnoutReportDidUpdate, object: report)
        return report
    }

    /// Get the most recent report without re-analyzing.
    func latestReport() -> BurnoutReport? {
        return history.reports.last
    }

    /// Get daily burnout score trend for charting.
    func scoreTrend(days: Int = 30) -> [(date: Date, score: Int)] {
        let cutoff = Calendar.current.date(byAdding: .day, value: -days, to: Date()) ?? Date()
        return history.dailySnapshots
            .filter { $0.date > cutoff }
            .map { (date: $0.date, score: $0.score) }
    }

    /// Generate a human-readable weekly summary.
    func weeklySummary() -> String {
        let report = analyze()
        var lines: [String] = []
        lines.append("📊 Weekly Burnout Report")
        lines.append("========================")
        lines.append("")
        lines.append("Overall Risk: \(report.severity.label) (\(report.overallScore)/100)")
        lines.append("Trend: \(report.trend.label)")
        lines.append("Articles Analyzed: \(report.articlesAnalyzed)")
        lines.append("")
        lines.append("Signal Breakdown:")
        for signal in report.signals {
            lines.append("  \(signal.severity.emoji) \(signal.label): \(signal.score)/100 — \(signal.detail)")
        }
        if !report.suggestions.isEmpty {
            lines.append("")
            lines.append("Suggestions:")
            for suggestion in report.suggestions {
                lines.append("  💡 \(suggestion)")
            }
        }
        return lines.joined(separator: "\n")
    }

    // MARK: - Configuration

    /// Update detection thresholds.
    func updateConfig(_ config: BurnoutConfig) {
        history.config = config
        save()
    }

    /// Get current configuration.
    func currentConfig() -> BurnoutConfig {
        return history.config
    }

    /// Reset all burnout data and history.
    func reset() {
        history = BurnoutHistory()
        events = []
        save()
        saveEvents()
    }

    // MARK: - Signal Analyzers (Private)

    private func analyzeCompletion(events: [BurnoutReadingEvent], config: BurnoutConfig) -> BurnoutSignal {
        guard !events.isEmpty else {
            return BurnoutSignal(id: "completion", label: "Completion Rate", score: 0,
                                 detail: "No reading data available", rawValue: 1.0, threshold: config.completionThreshold)
        }
        let avgCompletion = events.reduce(0.0) { $0 + $1.completionPercent } / Double(events.count)
        let score: Int
        if avgCompletion >= config.completionThreshold {
            score = Int((1.0 - avgCompletion) * 50.0)  // Some mild concern even at moderate completion
        } else {
            let deficit = (config.completionThreshold - avgCompletion) / config.completionThreshold
            score = 50 + Int(deficit * 50.0)
        }
        let pct = Int(avgCompletion * 100)
        return BurnoutSignal(id: "completion", label: "Completion Rate", score: min(100, max(0, score)),
                             detail: "Average completion: \(pct)% (threshold: \(Int(config.completionThreshold * 100))%)",
                             rawValue: avgCompletion, threshold: config.completionThreshold)
    }

    private func analyzeSessionFrequency(events: [BurnoutReadingEvent], config: BurnoutConfig) -> BurnoutSignal {
        let sessionCount = countSessions(events: events)
        let days = max(1, config.windowDays)
        let sessionsPerDay = Double(sessionCount) / Double(days)
        let score: Int
        if sessionsPerDay <= config.sessionsPerDayThreshold {
            score = Int((sessionsPerDay / config.sessionsPerDayThreshold) * 40.0)
        } else {
            let excess = (sessionsPerDay - config.sessionsPerDayThreshold) / config.sessionsPerDayThreshold
            score = 40 + Int(min(excess, 1.5) * 40.0)
        }
        return BurnoutSignal(id: "session_frequency", label: "Session Frequency", score: min(100, max(0, score)),
                             detail: String(format: "%.1f sessions/day (threshold: %.0f)", sessionsPerDay, config.sessionsPerDayThreshold),
                             rawValue: sessionsPerDay, threshold: config.sessionsPerDayThreshold)
    }

    private func analyzeLateNight(events: [BurnoutReadingEvent], config: BurnoutConfig) -> BurnoutSignal {
        let lateMinutes = calculateLateNightMinutes(events: events, config: config)
        let days = max(1, config.windowDays)
        let latePerDay = lateMinutes / Double(days)
        let score: Int
        if latePerDay <= config.lateNightMinutesThreshold {
            score = Int((latePerDay / config.lateNightMinutesThreshold) * 40.0)
        } else {
            let excess = (latePerDay - config.lateNightMinutesThreshold) / config.lateNightMinutesThreshold
            score = 40 + Int(min(excess, 1.5) * 40.0)
        }
        return BurnoutSignal(id: "late_night", label: "Late-Night Reading", score: min(100, max(0, score)),
                             detail: String(format: "%.0f min/day late-night (threshold: %.0f min)", latePerDay, config.lateNightMinutesThreshold),
                             rawValue: latePerDay, threshold: config.lateNightMinutesThreshold)
    }

    private func analyzeFeedSwitching(events: [BurnoutReadingEvent], config: BurnoutConfig) -> BurnoutSignal {
        let sessions = groupIntoSessions(events: events)
        guard !sessions.isEmpty else {
            return BurnoutSignal(id: "feed_switching", label: "Feed Switching", score: 0,
                                 detail: "No session data", rawValue: 0, threshold: config.feedSwitchThreshold)
        }
        var totalSwitches = 0
        for session in sessions {
            var switches = 0
            for i in 1..<session.count {
                if session[i].feedURL != session[i-1].feedURL {
                    switches += 1
                }
            }
            totalSwitches += switches
        }
        let avgSwitches = Double(totalSwitches) / Double(sessions.count)
        let score: Int
        if avgSwitches <= config.feedSwitchThreshold {
            score = Int((avgSwitches / config.feedSwitchThreshold) * 40.0)
        } else {
            let excess = (avgSwitches - config.feedSwitchThreshold) / config.feedSwitchThreshold
            score = 40 + Int(min(excess, 1.5) * 40.0)
        }
        return BurnoutSignal(id: "feed_switching", label: "Feed Switching", score: min(100, max(0, score)),
                             detail: String(format: "%.1f switches/session (threshold: %.0f)", avgSwitches, config.feedSwitchThreshold),
                             rawValue: avgSwitches, threshold: config.feedSwitchThreshold)
    }

    private func analyzeUnreadPileup(unreadCount: Int, config: BurnoutConfig) -> BurnoutSignal {
        let score: Int
        if unreadCount <= config.unreadPileupThreshold {
            score = Int((Double(unreadCount) / Double(config.unreadPileupThreshold)) * 40.0)
        } else {
            let excess = Double(unreadCount - config.unreadPileupThreshold) / Double(config.unreadPileupThreshold)
            score = 40 + Int(min(excess, 1.5) * 40.0)
        }
        return BurnoutSignal(id: "unread_pileup", label: "Unread Pile-Up", score: min(100, max(0, score)),
                             detail: "\(unreadCount) unread articles (threshold: \(config.unreadPileupThreshold))",
                             rawValue: Double(unreadCount), threshold: Double(config.unreadPileupThreshold))
    }

    private func analyzeTimeSpikes(events: [BurnoutReadingEvent], config: BurnoutConfig) -> BurnoutSignal {
        let cal = Calendar.current
        var dailyMinutes: [String: Double] = [:]
        for event in events {
            let key = Self.dayKey(event.timestamp, calendar: cal)
            dailyMinutes[key, default: 0] += event.durationSeconds / 60.0
        }
        let avgMinutes = dailyMinutes.isEmpty ? 0 : dailyMinutes.values.reduce(0, +) / Double(dailyMinutes.count)
        let score: Int
        if avgMinutes <= config.dailyMinutesThreshold {
            score = Int((avgMinutes / config.dailyMinutesThreshold) * 40.0)
        } else {
            let excess = (avgMinutes - config.dailyMinutesThreshold) / config.dailyMinutesThreshold
            score = 40 + Int(min(excess, 1.5) * 40.0)
        }
        return BurnoutSignal(id: "time_spike", label: "Daily Reading Time", score: min(100, max(0, score)),
                             detail: String(format: "%.0f min/day avg (threshold: %.0f min)", avgMinutes, config.dailyMinutesThreshold),
                             rawValue: avgMinutes, threshold: config.dailyMinutesThreshold)
    }

    // MARK: - Helpers

    private func calculateLateNightMinutes(events: [BurnoutReadingEvent], config: BurnoutConfig) -> Double {
        let cal = Calendar.current
        return events.reduce(0.0) { total, event in
            let hour = cal.component(.hour, from: event.timestamp)
            let isLateNight = hour >= config.lateNightStartHour || hour < config.lateNightEndHour
            return total + (isLateNight ? event.durationSeconds / 60.0 : 0)
        }
    }

    private func countSessions(events: [BurnoutReadingEvent]) -> Int {
        return groupIntoSessions(events: events).count
    }

    /// Group events into sessions (gap > 30 min = new session).
    private func groupIntoSessions(events: [BurnoutReadingEvent]) -> [[BurnoutReadingEvent]] {
        let sorted = events.sorted { $0.timestamp < $1.timestamp }
        guard !sorted.isEmpty else { return [] }
        var sessions: [[BurnoutReadingEvent]] = [[sorted[0]]]
        for i in 1..<sorted.count {
            let gap = sorted[i].timestamp.timeIntervalSince(sorted[i-1].timestamp)
            if gap > 1800 { // 30 minutes
                sessions.append([sorted[i]])
            } else {
                sessions[sessions.count - 1].append(sorted[i])
            }
        }
        return sessions
    }

    private func determineTrend(currentScore: Int) -> BurnoutTrend {
        let recentReports = history.reports.suffix(3)
        guard recentReports.count >= 2 else { return .stable }
        let previousAvg = recentReports.dropLast().reduce(0) { $0 + $1.overallScore } / max(1, recentReports.count - 1)
        let diff = currentScore - previousAvg
        if diff > 10 { return .worsening }
        if diff < -10 { return .improving }
        return .stable
    }

    private func generateSuggestions(signals: [BurnoutSignal], overallScore: Int) -> [String] {
        var suggestions: [String] = []

        for signal in signals where signal.score >= 50 {
            switch signal.id {
            case "completion":
                suggestions.append("Try reading fewer articles but finishing them. Quality over quantity.")
            case "session_frequency":
                suggestions.append("Consider setting specific reading times instead of checking feeds throughout the day.")
            case "late_night":
                suggestions.append("Set a reading curfew. Late-night reading disrupts sleep and increases fatigue.")
            case "feed_switching":
                suggestions.append("Focus on one feed at a time. Rapid switching suggests restless browsing, not intentional reading.")
            case "unread_pileup":
                suggestions.append("Mark-all-read or unsubscribe from low-value feeds. A huge backlog creates guilt, not value.")
            case "time_spike":
                suggestions.append("Set a daily reading time budget. Taking breaks helps retention and prevents fatigue.")
            default:
                break
            }
        }

        if overallScore >= 75 {
            suggestions.insert("🚨 Consider taking a 24-hour break from feeds entirely. Your reading patterns suggest significant overload.", at: 0)
        } else if overallScore >= 50 {
            suggestions.insert("Consider reducing your feed subscriptions to your top 5-10 most valuable sources.", at: 0)
        }

        if suggestions.isEmpty {
            suggestions.append("Your reading habits look healthy! Keep up the balanced approach. 🌟")
        }

        return suggestions
    }

    private static func dayKey(_ date: Date, calendar: Calendar) -> String {
        let comps = calendar.dateComponents([.year, .month, .day], from: date)
        return "\(comps.year!)-\(comps.month!)-\(comps.day!)"
    }

    private func pruneOldEvents() {
        let cutoff = Calendar.current.date(byAdding: .day, value: -90, to: Date()) ?? Date()
        events = events.filter { $0.timestamp > cutoff }
    }

    // MARK: - Persistence

    private func load() {
        if let data = try? Data(contentsOf: storageURL),
           let decoded = try? JSONDecoder().decode(BurnoutHistory.self, from: data) {
            history = decoded
        }
        if let data = try? Data(contentsOf: eventsURL),
           let decoded = try? JSONDecoder().decode([BurnoutReadingEvent].self, from: data) {
            events = decoded
        }
    }

    private func save() {
        if let data = try? JSONEncoder().encode(history) {
            try? data.write(to: storageURL)
        }
    }

    private func saveEvents() {
        if let data = try? JSONEncoder().encode(events) {
            try? data.write(to: eventsURL)
        }
    }
}
