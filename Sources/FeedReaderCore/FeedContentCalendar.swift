//
//  FeedContentCalendar.swift
//  FeedReaderCore
//
//  Autonomous publication pattern detection and schedule forecasting.
//  Analyzes when feeds publish articles, detects regular schedules,
//  predicts upcoming publications, and alerts when expected content
//  is late or missing.
//

import Foundation

// MARK: - Publication Day Profile

/// Aggregated publishing statistics for a specific day of the week.
public struct DayProfile: Sendable {
    /// Day of week (1 = Sunday … 7 = Saturday).
    public let weekday: Int
    /// Total articles published on this day across all history.
    public let totalArticles: Int
    /// Average articles per occurrence of this day.
    public let averageArticles: Double
    /// Most common publication hour (0-23), nil if no data.
    public let peakHour: Int?
    /// Whether this day is a regular publishing day (above median).
    public let isRegularDay: Bool

    /// Human-readable weekday name.
    public var dayName: String {
        let names = ["", "Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday"]
        guard weekday >= 1 && weekday <= 7 else { return "Unknown" }
        return names[weekday]
    }

    /// Short weekday name.
    public var shortDayName: String {
        let names = ["", "Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]
        guard weekday >= 1 && weekday <= 7 else { return "?" }
        return names[weekday]
    }
}

// MARK: - Schedule Pattern

/// Detected publishing schedule pattern for a feed.
public enum SchedulePattern: String, Sendable {
    case daily = "daily"
    case weekdays = "weekdays"
    case weekly = "weekly"
    case biweekly = "biweekly"
    case sporadic = "sporadic"
    case inactive = "inactive"

    /// Human-readable description.
    public var description: String {
        switch self {
        case .daily: return "Publishes daily"
        case .weekdays: return "Publishes on weekdays"
        case .weekly: return "Publishes weekly"
        case .biweekly: return "Publishes every two weeks"
        case .sporadic: return "Irregular schedule"
        case .inactive: return "No recent activity"
        }
    }

    /// Emoji indicator.
    public var emoji: String {
        switch self {
        case .daily: return "📅"
        case .weekdays: return "💼"
        case .weekly: return "📰"
        case .biweekly: return "🗓️"
        case .sporadic: return "🎲"
        case .inactive: return "💤"
        }
    }
}

// MARK: - Gap Alert

/// Alert for a detected gap in expected publishing.
public struct GapAlert: Sendable {
    /// Feed name.
    public let feedName: String
    /// How many days since last publication.
    public let daysSinceLastPost: Int
    /// Average interval between posts for this feed.
    public let averageIntervalDays: Double
    /// How many standard deviations this gap exceeds the mean.
    public let deviations: Double
    /// Severity level.
    public let severity: GapSeverity

    public enum GapSeverity: String, Sendable {
        case notice = "notice"
        case warning = "warning"
        case alert = "alert"

        public var emoji: String {
            switch self {
            case .notice: return "ℹ️"
            case .warning: return "⚠️"
            case .alert: return "🚨"
            }
        }
    }
}

// MARK: - Publication Forecast

/// Predicted upcoming publication event.
public struct PublicationForecast: Sendable {
    /// Feed name.
    public let feedName: String
    /// Predicted publication date.
    public let predictedDate: Date
    /// Confidence score 0.0–1.0.
    public let confidence: Double
    /// Basis for the prediction.
    public let basis: String
}

// MARK: - Feed Calendar Report

/// Complete calendar analysis for a single feed.
public struct FeedCalendarReport: Sendable {
    /// Feed name.
    public let feedName: String
    /// Detected schedule pattern.
    public let pattern: SchedulePattern
    /// Per-day profiles (always 7 entries, Sun–Sat).
    public let dayProfiles: [DayProfile]
    /// Average gap between publications (in days).
    public let averageGapDays: Double
    /// Standard deviation of gaps.
    public let gapStdDev: Double
    /// Regularity score 0.0–1.0 (higher = more consistent).
    public let regularityScore: Double
    /// Most productive day.
    public let busiestDay: DayProfile?
    /// Any active gap alerts.
    public let gapAlerts: [GapAlert]
    /// Upcoming publication forecasts.
    public let forecasts: [PublicationForecast]
    /// Total articles analyzed.
    public let totalArticlesAnalyzed: Int
    /// Date range of analyzed articles.
    public let analysisStartDate: Date?
    public let analysisEndDate: Date?
}

// MARK: - Fleet Calendar Summary

/// Aggregated calendar insights across all feeds.
public struct FleetCalendarSummary: Sendable {
    /// Per-feed reports.
    public let reports: [FeedCalendarReport]
    /// Total gap alerts across fleet.
    public let totalAlerts: Int
    /// Feeds with most consistent schedules.
    public let mostReliableFeeds: [String]
    /// Feeds that seem to have gone dormant.
    public let dormantFeeds: [String]
    /// Day of week with most content across all feeds.
    public let busiestGlobalDay: String
    /// Proactive insights.
    public let insights: [String]
}

// MARK: - FeedContentCalendar

/// Autonomous publication pattern analyzer. Detects schedules, forecasts
/// upcoming publications, and generates gap alerts when feeds deviate
/// from their established patterns.
public final class FeedContentCalendar: @unchecked Sendable {

    // MARK: - Types

    /// Minimal article representation for calendar analysis.
    public struct ArticleEntry: Sendable {
        public let feedName: String
        public let title: String
        public let publishedDate: Date

        public init(feedName: String, title: String, publishedDate: Date) {
            self.feedName = feedName
            self.title = title
            self.publishedDate = publishedDate
        }
    }

    // MARK: - Properties

    private let calendar = Calendar(identifier: .gregorian)
    private let now: Date

    // MARK: - Init

    /// Create a content calendar analyzer.
    /// - Parameter referenceDate: Override "now" for testing. Defaults to current date.
    public init(referenceDate: Date = Date()) {
        self.now = referenceDate
    }

    // MARK: - Public API

    /// Analyze a single feed's publishing calendar.
    public func analyze(feedName: String, articles: [ArticleEntry]) -> FeedCalendarReport {
        let sorted = articles
            .filter { $0.feedName == feedName }
            .sorted { $0.publishedDate < $1.publishedDate }

        guard sorted.count >= 2 else {
            return makeEmptyReport(feedName: feedName, count: sorted.count)
        }

        let dayProfiles = buildDayProfiles(articles: sorted)
        let gaps = computeGaps(articles: sorted)
        let avgGap = gaps.isEmpty ? 0 : gaps.reduce(0, +) / Double(gaps.count)
        let stdDev = standardDeviation(gaps)
        let regularity = computeRegularity(gaps: gaps, stdDev: stdDev, avgGap: avgGap)
        let pattern = detectPattern(dayProfiles: dayProfiles, avgGap: avgGap, regularity: regularity, articles: sorted)
        let busiest = dayProfiles.max(by: { $0.averageArticles < $1.averageArticles })
        let gapAlerts = detectGapAlerts(feedName: feedName, articles: sorted, avgGap: avgGap, stdDev: stdDev)
        let forecasts = generateForecasts(feedName: feedName, articles: sorted, pattern: pattern, dayProfiles: dayProfiles, avgGap: avgGap)

        return FeedCalendarReport(
            feedName: feedName,
            pattern: pattern,
            dayProfiles: dayProfiles,
            averageGapDays: avgGap,
            gapStdDev: stdDev,
            regularityScore: regularity,
            busiestDay: busiest,
            gapAlerts: gapAlerts,
            forecasts: forecasts,
            totalArticlesAnalyzed: sorted.count,
            analysisStartDate: sorted.first?.publishedDate,
            analysisEndDate: sorted.last?.publishedDate
        )
    }

    /// Analyze all feeds and produce a fleet summary.
    public func analyzeFleet(articles: [ArticleEntry]) -> FleetCalendarSummary {
        let feedNames = Set(articles.map { $0.feedName })
        let reports = feedNames.map { name in
            analyze(feedName: name, articles: articles.filter { $0.feedName == name })
        }.sorted { $0.feedName < $1.feedName }

        let totalAlerts = reports.reduce(0) { $0 + $1.gapAlerts.count }
        let mostReliable = reports
            .filter { $0.regularityScore > 0.7 && $0.pattern != .inactive && $0.pattern != .sporadic }
            .sorted { $0.regularityScore > $1.regularityScore }
            .prefix(5)
            .map { $0.feedName }
        let dormant = reports
            .filter { $0.pattern == .inactive }
            .map { $0.feedName }

        // Global busiest day
        var globalDayCounts = [Int: Int]()
        for report in reports {
            for dp in report.dayProfiles {
                globalDayCounts[dp.weekday, default: 0] += dp.totalArticles
            }
        }
        let busiestDayNum = globalDayCounts.max(by: { $0.value < $1.value })?.key ?? 2
        let dayNames = ["", "Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday"]
        let busiestGlobal = (busiestDayNum >= 1 && busiestDayNum <= 7) ? dayNames[busiestDayNum] : "Unknown"

        let insights = generateFleetInsights(reports: reports, dormant: dormant, busiestDay: busiestGlobal, totalAlerts: totalAlerts)

        return FleetCalendarSummary(
            reports: reports,
            totalAlerts: totalAlerts,
            mostReliableFeeds: Array(mostReliable),
            dormantFeeds: dormant,
            busiestGlobalDay: busiestGlobal,
            insights: insights
        )
    }

    /// Generate a text report for a single feed.
    public func formatReport(_ report: FeedCalendarReport) -> String {
        var lines = [String]()
        lines.append("═══════════════════════════════════════════════")
        lines.append("  \(report.pattern.emoji) Content Calendar: \(report.feedName)")
        lines.append("═══════════════════════════════════════════════")
        lines.append("")
        lines.append("Pattern: \(report.pattern.description)")
        lines.append("Regularity: \(String(format: "%.0f%%", report.regularityScore * 100))")
        lines.append("Articles analyzed: \(report.totalArticlesAnalyzed)")
        lines.append("Avg gap: \(String(format: "%.1f", report.averageGapDays)) days (σ \(String(format: "%.1f", report.gapStdDev)))")
        lines.append("")

        // Weekly heatmap
        lines.append("┌─────────────────────────────────────┐")
        lines.append("│        Weekly Publication Heatmap    │")
        lines.append("├─────────────────────────────────────┤")
        let maxAvg = report.dayProfiles.map { $0.averageArticles }.max() ?? 1.0
        for dp in report.dayProfiles {
            let barLen = maxAvg > 0 ? Int((dp.averageArticles / maxAvg) * 20.0) : 0
            let bar = String(repeating: "█", count: barLen) + String(repeating: "░", count: 20 - barLen)
            let marker = dp.isRegularDay ? "●" : "○"
            let peakStr = dp.peakHour.map { String(format: "%02d:00", $0) } ?? "  --"
            lines.append("│ \(marker) \(dp.shortDayName) \(bar) \(String(format: "%5.1f", dp.averageArticles)) avg  peak \(peakStr) │")
        }
        lines.append("└─────────────────────────────────────┘")
        lines.append("")

        // Gap alerts
        if !report.gapAlerts.isEmpty {
            lines.append("⚠️  Gap Alerts:")
            for alert in report.gapAlerts {
                lines.append("  \(alert.severity.emoji) \(alert.daysSinceLastPost) days since last post (\(String(format: "%.1f", alert.deviations))σ above mean)")
            }
            lines.append("")
        }

        // Forecasts
        if !report.forecasts.isEmpty {
            lines.append("🔮 Upcoming Forecasts:")
            let fmt = DateFormatter()
            fmt.dateFormat = "EEE MMM d"
            for fc in report.forecasts.prefix(5) {
                let conf = String(format: "%.0f%%", fc.confidence * 100)
                lines.append("  📌 \(fmt.string(from: fc.predictedDate)) — \(conf) confidence (\(fc.basis))")
            }
            lines.append("")
        }

        return lines.joined(separator: "\n")
    }

    /// Generate a text fleet summary.
    public func formatFleetSummary(_ summary: FleetCalendarSummary) -> String {
        var lines = [String]()
        lines.append("╔═══════════════════════════════════════════════╗")
        lines.append("║     📅 Fleet Content Calendar Summary         ║")
        lines.append("╚═══════════════════════════════════════════════╝")
        lines.append("")
        lines.append("Feeds analyzed: \(summary.reports.count)")
        lines.append("Busiest day globally: \(summary.busiestGlobalDay)")
        lines.append("Total gap alerts: \(summary.totalAlerts)")
        lines.append("")

        if !summary.mostReliableFeeds.isEmpty {
            lines.append("🏆 Most Reliable:")
            for f in summary.mostReliableFeeds { lines.append("  ✅ \(f)") }
            lines.append("")
        }
        if !summary.dormantFeeds.isEmpty {
            lines.append("💤 Dormant Feeds:")
            for f in summary.dormantFeeds { lines.append("  ⚪ \(f)") }
            lines.append("")
        }

        // Pattern distribution
        var patternCounts = [SchedulePattern: Int]()
        for r in summary.reports { patternCounts[r.pattern, default: 0] += 1 }
        lines.append("📊 Schedule Distribution:")
        for (pat, count) in patternCounts.sorted(by: { $0.value > $1.value }) {
            lines.append("  \(pat.emoji) \(pat.rawValue): \(count)")
        }
        lines.append("")

        if !summary.insights.isEmpty {
            lines.append("💡 Proactive Insights:")
            for insight in summary.insights {
                lines.append("  → \(insight)")
            }
        }

        return lines.joined(separator: "\n")
    }

    // MARK: - Private Helpers

    private func makeEmptyReport(feedName: String, count: Int) -> FeedCalendarReport {
        let emptyProfiles = (1...7).map { day in
            DayProfile(weekday: day, totalArticles: 0, averageArticles: 0, peakHour: nil, isRegularDay: false)
        }
        return FeedCalendarReport(
            feedName: feedName,
            pattern: count == 0 ? .inactive : .sporadic,
            dayProfiles: emptyProfiles,
            averageGapDays: 0,
            gapStdDev: 0,
            regularityScore: 0,
            busiestDay: nil,
            gapAlerts: [],
            forecasts: [],
            totalArticlesAnalyzed: count,
            analysisStartDate: nil,
            analysisEndDate: nil
        )
    }

    private func buildDayProfiles(articles: [ArticleEntry]) -> [DayProfile] {
        // Group by weekday
        var dayArticles = [Int: [ArticleEntry]]()
        var dayOccurrences = [Int: Set<String>]() // unique dates per weekday
        let dateFmt = DateFormatter()
        dateFmt.dateFormat = "yyyy-MM-dd"

        for a in articles {
            let wd = calendar.component(.weekday, from: a.publishedDate)
            dayArticles[wd, default: []].append(a)
            dayOccurrences[wd, default: []].insert(dateFmt.string(from: a.publishedDate))
        }

        // Compute median article count for regularity threshold
        let counts = (1...7).map { Double(dayArticles[$0]?.count ?? 0) }
        let sortedCounts = counts.sorted()
        let median = sortedCounts[3]

        return (1...7).map { wd in
            let arts = dayArticles[wd] ?? []
            let occurrences = max(dayOccurrences[wd]?.count ?? 0, 1)
            let avg = Double(arts.count) / Double(max(occurrences, 1))

            // Peak hour
            var hourCounts = [Int: Int]()
            for a in arts {
                let hr = calendar.component(.hour, from: a.publishedDate)
                hourCounts[hr, default: 0] += 1
            }
            let peak = hourCounts.max(by: { $0.value < $1.value })?.key

            return DayProfile(
                weekday: wd,
                totalArticles: arts.count,
                averageArticles: avg,
                peakHour: peak,
                isRegularDay: Double(arts.count) > median * 0.5
            )
        }
    }

    private func computeGaps(articles: [ArticleEntry]) -> [Double] {
        guard articles.count >= 2 else { return [] }
        var gaps = [Double]()
        for i in 1..<articles.count {
            let diff = articles[i].publishedDate.timeIntervalSince(articles[i-1].publishedDate)
            gaps.append(diff / 86400.0) // days
        }
        return gaps
    }

    private func standardDeviation(_ values: [Double]) -> Double {
        guard values.count > 1 else { return 0 }
        let mean = values.reduce(0, +) / Double(values.count)
        let variance = values.reduce(0) { $0 + ($1 - mean) * ($1 - mean) } / Double(values.count - 1)
        return sqrt(variance)
    }

    private func computeRegularity(gaps: [Double], stdDev: Double, avgGap: Double) -> Double {
        guard avgGap > 0 else { return 0 }
        let cv = stdDev / avgGap // coefficient of variation
        // Low CV = high regularity. Map CV to 0-1 score.
        return max(0, min(1, 1.0 - cv))
    }

    private func detectPattern(dayProfiles: [DayProfile], avgGap: Double, regularity: Double, articles: [ArticleEntry]) -> SchedulePattern {
        guard articles.count >= 2 else { return .inactive }

        // Check for inactivity (no posts in last 30 days)
        if let last = articles.last {
            let daysSince = now.timeIntervalSince(last.publishedDate) / 86400.0
            if daysSince > 30 { return .inactive }
        }

        let regularDays = dayProfiles.filter { $0.isRegularDay }

        if regularity > 0.6 && avgGap < 1.5 {
            return .daily
        }
        if regularity > 0.5 {
            let weekdayRegulars = regularDays.filter { $0.weekday >= 2 && $0.weekday <= 6 }
            let weekendRegulars = regularDays.filter { $0.weekday == 1 || $0.weekday == 7 }
            if weekdayRegulars.count >= 4 && weekendRegulars.isEmpty {
                return .weekdays
            }
        }
        if regularity > 0.4 && avgGap >= 5 && avgGap <= 9 {
            return .weekly
        }
        if regularity > 0.3 && avgGap >= 12 && avgGap <= 18 {
            return .biweekly
        }
        return .sporadic
    }

    private func detectGapAlerts(feedName: String, articles: [ArticleEntry], avgGap: Double, stdDev: Double) -> [GapAlert] {
        guard let last = articles.last, avgGap > 0 else { return [] }

        let daysSince = now.timeIntervalSince(last.publishedDate) / 86400.0
        guard daysSince > avgGap else { return [] }

        let deviations = stdDev > 0 ? (daysSince - avgGap) / stdDev : daysSince / avgGap

        let severity: GapAlert.GapSeverity
        if deviations > 3.0 { severity = .alert }
        else if deviations > 2.0 { severity = .warning }
        else if deviations > 1.0 { severity = .notice }
        else { return [] }

        return [GapAlert(
            feedName: feedName,
            daysSinceLastPost: Int(daysSince),
            averageIntervalDays: avgGap,
            deviations: deviations,
            severity: severity
        )]
    }

    private func generateForecasts(feedName: String, articles: [ArticleEntry], pattern: SchedulePattern, dayProfiles: [DayProfile], avgGap: Double) -> [PublicationForecast] {
        guard let last = articles.last, pattern != .inactive else { return [] }

        var forecasts = [PublicationForecast]()

        switch pattern {
        case .daily:
            // Predict next 3 days
            for i in 1...3 {
                if let date = calendar.date(byAdding: .day, value: i, to: now) {
                    forecasts.append(PublicationForecast(
                        feedName: feedName, predictedDate: date, confidence: max(0.5, 0.9 - Double(i) * 0.1), basis: "daily pattern"
                    ))
                }
            }
        case .weekdays:
            // Next 3 weekdays
            var count = 0
            var dayOffset = 1
            while count < 3 && dayOffset < 10 {
                if let date = calendar.date(byAdding: .day, value: dayOffset, to: now) {
                    let wd = calendar.component(.weekday, from: date)
                    if wd >= 2 && wd <= 6 {
                        forecasts.append(PublicationForecast(
                            feedName: feedName, predictedDate: date, confidence: 0.8, basis: "weekday pattern"
                        ))
                        count += 1
                    }
                }
                dayOffset += 1
            }
        case .weekly, .biweekly:
            // Use avg gap from last post
            let gapDays = pattern == .weekly ? 7.0 : 14.0
            for i in 1...3 {
                let daysFromLast = gapDays * Double(i)
                let targetDate = last.publishedDate.addingTimeInterval(daysFromLast * 86400.0)
                if targetDate > now {
                    forecasts.append(PublicationForecast(
                        feedName: feedName, predictedDate: targetDate, confidence: max(0.4, 0.75 - Double(i) * 0.1), basis: "\(pattern.rawValue) pattern"
                    ))
                }
            }
        case .sporadic:
            // Best guess: avg gap from last
            if avgGap > 0 {
                let nextDate = last.publishedDate.addingTimeInterval(avgGap * 86400.0)
                if nextDate > now {
                    forecasts.append(PublicationForecast(
                        feedName: feedName, predictedDate: nextDate, confidence: 0.3, basis: "average interval"
                    ))
                }
            }
        case .inactive:
            break
        }

        return forecasts
    }

    private func generateFleetInsights(reports: [FeedCalendarReport], dormant: [String], busiestDay: String, totalAlerts: Int) -> [String] {
        var insights = [String]()

        // Content desert days
        var globalDayCounts = [Int: Int]()
        for r in reports {
            for dp in r.dayProfiles { globalDayCounts[dp.weekday, default: 0] += dp.totalArticles }
        }
        let dayNames = ["", "Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday"]
        if let quietest = globalDayCounts.min(by: { $0.value < $1.value }), quietest.key >= 1 && quietest.key <= 7 {
            insights.append("\(dayNames[quietest.key]) has the least content — consider scheduling personal reading catch-up then.")
        }

        // Alert summary
        if totalAlerts > 0 {
            let alertFeeds = reports.filter { !$0.gapAlerts.isEmpty }.map { $0.feedName }
            insights.append("\(totalAlerts) gap alert(s) across \(alertFeeds.count) feed(s) — some feeds may be going dormant or experiencing issues.")
        }

        // Regularity spread
        let highReg = reports.filter { $0.regularityScore > 0.7 }.count
        let lowReg = reports.filter { $0.regularityScore < 0.3 && $0.pattern != .inactive }.count
        if highReg > 0 {
            insights.append("\(highReg) feed(s) publish on a very consistent schedule — great for planning reading time.")
        }
        if lowReg > 0 {
            insights.append("\(lowReg) feed(s) are highly unpredictable — check them manually rather than relying on schedules.")
        }

        // Dormancy
        if dormant.count > 2 {
            insights.append("\(dormant.count) feeds appear dormant — consider unsubscribing or archiving to reduce noise.")
        }

        // Peak alignment
        let morningFeeds = reports.filter { $0.busiestDay?.peakHour ?? 12 < 12 }.count
        let eveningFeeds = reports.filter { ($0.busiestDay?.peakHour ?? 12) >= 17 }.count
        if morningFeeds > reports.count / 2 {
            insights.append("Most of your feeds publish in the morning — check your reader early for fresh content.")
        } else if eveningFeeds > reports.count / 2 {
            insights.append("Most of your feeds publish in the evening — plan your reading time accordingly.")
        }

        return insights
    }
}
