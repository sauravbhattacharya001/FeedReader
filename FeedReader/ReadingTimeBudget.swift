//
//  ReadingTimeBudget.swift
//  FeedReader
//
//  Lets users set daily and weekly reading time budgets (in minutes),
//  tracks time spent reading against those budgets, recommends articles
//  that fit remaining time, and generates budget reports with trends.
//
//  Key features:
//  - Configurable daily/weekly minute budgets
//  - Time tracking with start/stop sessions
//  - Remaining budget calculation with pace analysis
//  - Article suggestions that fit remaining time
//  - Weekly reports with daily breakdown and adherence scoring
//  - Budget streaks and consistency tracking
//  - Overtime/undertime analysis
//
//  Persistence: JSON file in Documents directory.
//

import Foundation

// MARK: - Notifications

extension Notification.Name {
    /// Posted when time budget configuration or tracked time changes.
    static let readingTimeBudgetDidChange = Notification.Name("ReadingTimeBudgetDidChangeNotification")
    /// Posted when daily budget is fully consumed.
    static let readingTimeBudgetExhausted = Notification.Name("ReadingTimeBudgetExhaustedNotification")
}

// MARK: - Models

/// User-configurable time budget settings.
struct TimeBudgetConfig: Codable, Equatable {
    /// Target reading minutes per day. 0 = no daily budget.
    var dailyMinutes: Int
    /// Target reading minutes per week. 0 = no weekly budget.
    var weeklyMinutes: Int
    /// Average words per minute for time estimation. Default 238.
    var wordsPerMinute: Int
    /// Whether to count weekends toward weekly budget. Default true.
    var includeWeekends: Bool

    static let `default` = TimeBudgetConfig(
        dailyMinutes: 30,
        weeklyMinutes: 150,
        wordsPerMinute: 238,
        includeWeekends: true
    )

    /// Validates that the config has sensible values.
    var isValid: Bool {
        return dailyMinutes >= 0 && weeklyMinutes >= 0 && wordsPerMinute > 0
    }
}

/// A recorded reading time entry.
struct ReadingTimeEntry: Codable, Equatable {
    let id: String
    let date: Date
    /// Duration in seconds.
    let duration: TimeInterval
    /// Article title, if associated.
    let articleTitle: String?
    /// Feed name, if known.
    let feedName: String?
    /// Word count of article read (for pace calculation).
    let wordCount: Int?

    /// Duration in minutes.
    var durationMinutes: Double {
        return duration / 60.0
    }

    /// Words per minute achieved, if word count is known and duration > 0.
    var actualWPM: Int? {
        guard let wc = wordCount, duration > 0 else { return nil }
        return Int(Double(wc) / (duration / 60.0))
    }
}

/// An article candidate for time-fitting recommendations.
struct TimeFitArticle: Equatable {
    let title: String
    let feedName: String?
    let estimatedMinutes: Double
    let wordCount: Int

    /// How well this fits the remaining budget (0.0 = doesn't fit, 1.0 = perfect fit).
    var fitScore: Double = 0.0
}

/// Daily budget summary.
struct DailyBudgetSummary: Equatable {
    let date: Date
    let budgetMinutes: Int
    let usedMinutes: Double
    let remainingMinutes: Double
    let articleCount: Int
    let averageWPM: Int?

    var usagePercent: Double {
        guard budgetMinutes > 0 else { return 0 }
        return min((usedMinutes / Double(budgetMinutes)) * 100.0, 999.9)
    }

    var isOverBudget: Bool {
        return usedMinutes > Double(budgetMinutes) && budgetMinutes > 0
    }

    var overtimeMinutes: Double {
        guard isOverBudget else { return 0 }
        return usedMinutes - Double(budgetMinutes)
    }

    /// Grade: A (90-110%), B (75-125%), C (50-150%), D (25-175%), F (rest)
    var grade: String {
        guard budgetMinutes > 0 else { return "-" }
        let pct = usedMinutes / Double(budgetMinutes)
        if pct >= 0.9 && pct <= 1.1 { return "A" }
        if pct >= 0.75 && pct <= 1.25 { return "B" }
        if pct >= 0.5 && pct <= 1.5 { return "C" }
        if pct >= 0.25 && pct <= 1.75 { return "D" }
        return "F"
    }
}

/// Weekly budget report.
struct WeeklyBudgetReport: Equatable {
    let weekStartDate: Date
    let weekEndDate: Date
    let config: TimeBudgetConfig
    let dailySummaries: [DailyBudgetSummary]
    let totalBudgetMinutes: Int
    let totalUsedMinutes: Double
    let totalArticles: Int
    let adherenceScore: Double  // 0-100
    let streak: Int  // consecutive days within budget
    let longestStreak: Int
    let averageDailyMinutes: Double
    let busiestDay: String?
    let quietestDay: String?

    var isOverBudget: Bool {
        return totalUsedMinutes > Double(totalBudgetMinutes) && totalBudgetMinutes > 0
    }

    var weeklyUsagePercent: Double {
        guard totalBudgetMinutes > 0 else { return 0 }
        return (totalUsedMinutes / Double(totalBudgetMinutes)) * 100.0
    }
}

/// Pace analysis for budget tracking.
struct BudgetPace: Equatable {
    /// Minutes used so far today.
    let usedToday: Double
    /// Daily budget in minutes.
    let dailyBudget: Int
    /// Minutes remaining today.
    let remainingToday: Double
    /// Minutes used this week.
    let usedThisWeek: Double
    /// Weekly budget in minutes.
    let weeklyBudget: Int
    /// Minutes remaining this week.
    let remainingThisWeek: Double
    /// Days remaining in the week (including today).
    let daysRemainingInWeek: Int
    /// Suggested minutes per remaining day to stay on weekly budget.
    let suggestedDailyPace: Double
    /// Whether currently on track for weekly budget.
    let onTrack: Bool

    var paceDescription: String {
        if dailyBudget == 0 && weeklyBudget == 0 { return "No budget set" }
        var parts: [String] = []
        if dailyBudget > 0 {
            let pct = Int((usedToday / Double(dailyBudget)) * 100)
            parts.append("Today: \(String(format: "%.0f", usedToday))/\(dailyBudget) min (\(pct)%)")
        }
        if weeklyBudget > 0 {
            let pct = Int((usedThisWeek / Double(weeklyBudget)) * 100)
            parts.append("Week: \(String(format: "%.0f", usedThisWeek))/\(weeklyBudget) min (\(pct)%)")
            if daysRemainingInWeek > 0 {
                parts.append("Pace: \(String(format: "%.0f", suggestedDailyPace)) min/day remaining")
            }
        }
        return parts.joined(separator: " | ")
    }
}

// MARK: - ReadingTimeBudgetManager

/// Manages reading time budgets, tracking, and reporting.
class ReadingTimeBudgetManager {

    // MARK: - Cached Date Formatters

    private static let dayOfWeekFormatter = DateFormatting.fullWeekday

    private static let shortMonthDayFormatter = DateFormatting.monthDay

    private static let shortDayFormatter = DateFormatting.shortWeekday

    // MARK: - Storage

    private var config: TimeBudgetConfig
    private var entries: [ReadingTimeEntry]
    private var activeSessionStart: Date?
    private var activeArticleTitle: String?
    private var activeArticleFeedName: String?
    private var activeArticleWordCount: Int?
    private let calendar: Calendar
    private let persistencePath: String?

    // MARK: - Init

    /// Creates a manager. Pass nil for persistencePath to disable file persistence (for tests).
    init(config: TimeBudgetConfig = .default,
         entries: [ReadingTimeEntry] = [],
         calendar: Calendar = .current,
         persistencePath: String? = nil) {
        self.config = config
        self.entries = entries
        self.calendar = calendar
        self.persistencePath = persistencePath
        if let path = persistencePath {
            loadFromDisk(path: path)
        }
    }

    // MARK: - Configuration

    func getConfig() -> TimeBudgetConfig {
        return config
    }

    func updateConfig(_ newConfig: TimeBudgetConfig) {
        guard newConfig.isValid else { return }
        config = newConfig
        save()
        NotificationCenter.default.post(name: .readingTimeBudgetDidChange, object: nil)
    }

    // MARK: - Session Tracking

    /// Starts a reading session for time tracking.
    func startSession(articleTitle: String? = nil, feedName: String? = nil, wordCount: Int? = nil) {
        activeSessionStart = Date()
        activeArticleTitle = articleTitle
        activeArticleFeedName = feedName
        activeArticleWordCount = wordCount
    }

    /// Starts a reading session at a specific time (for testing).
    func startSession(at date: Date, articleTitle: String? = nil, feedName: String? = nil, wordCount: Int? = nil) {
        activeSessionStart = date
        activeArticleTitle = articleTitle
        activeArticleFeedName = feedName
        activeArticleWordCount = wordCount
    }

    /// Whether a reading session is currently active.
    var isSessionActive: Bool {
        return activeSessionStart != nil
    }

    /// Stops the active session and records the time entry. Returns the entry, or nil if no session was active.
    @discardableResult
    func stopSession(at endDate: Date? = nil) -> ReadingTimeEntry? {
        guard let start = activeSessionStart else { return nil }
        let end = endDate ?? Date()
        let duration = end.timeIntervalSince(start)
        guard duration > 0 else {
            activeSessionStart = nil
            return nil
        }

        let entry = ReadingTimeEntry(
            id: UUID().uuidString,
            date: start,
            duration: duration,
            articleTitle: activeArticleTitle,
            feedName: activeArticleFeedName,
            wordCount: activeArticleWordCount
        )
        entries.append(entry)
        activeSessionStart = nil
        activeArticleTitle = nil
        activeArticleFeedName = nil
        activeArticleWordCount = nil
        save()

        // Check if daily budget exhausted
        let todayUsed = minutesUsed(on: start)
        if config.dailyMinutes > 0 && todayUsed >= Double(config.dailyMinutes) {
            NotificationCenter.default.post(name: .readingTimeBudgetExhausted, object: nil)
        }
        NotificationCenter.default.post(name: .readingTimeBudgetDidChange, object: nil)
        return entry
    }

    /// Manually log a reading time entry (e.g., for imported sessions).
    @discardableResult
    func logEntry(date: Date, durationSeconds: TimeInterval, articleTitle: String? = nil,
                  feedName: String? = nil, wordCount: Int? = nil) -> ReadingTimeEntry? {
        guard durationSeconds > 0 else { return nil }
        let entry = ReadingTimeEntry(
            id: UUID().uuidString,
            date: date,
            duration: durationSeconds,
            articleTitle: articleTitle,
            feedName: feedName,
            wordCount: wordCount
        )
        entries.append(entry)
        save()
        NotificationCenter.default.post(name: .readingTimeBudgetDidChange, object: nil)
        return entry
    }

    /// Remove an entry by ID.
    @discardableResult
    func removeEntry(id: String) -> Bool {
        let before = entries.count
        entries.removeAll { $0.id == id }
        if entries.count < before {
            save()
            return true
        }
        return false
    }

    /// All tracked entries.
    func allEntries() -> [ReadingTimeEntry] {
        return entries
    }

    /// Entries for a specific date.
    func entries(on date: Date) -> [ReadingTimeEntry] {
        return entries.filter { calendar.isDate($0.date, inSameDayAs: date) }
    }

    /// Entries in a date range (inclusive).
    func entries(from start: Date, to end: Date) -> [ReadingTimeEntry] {
        return entries.filter { $0.date >= start && $0.date <= end }
    }

    // MARK: - Budget Calculations

    /// Minutes used on a specific date.
    func minutesUsed(on date: Date) -> Double {
        return entries(on: date).reduce(0) { $0 + $1.durationMinutes }
    }

    /// Minutes remaining today. Negative if over budget.
    func remainingToday(as of: Date = Date()) -> Double {
        guard config.dailyMinutes > 0 else { return Double.infinity }
        return Double(config.dailyMinutes) - minutesUsed(on: of)
    }

    /// Minutes used in the week containing the given date (Mon-Sun).
    func minutesUsedThisWeek(containing date: Date = Date()) -> Double {
        let weekDates = datesInWeek(containing: date)
        return weekDates.reduce(0) { $0 + minutesUsed(on: $1) }
    }

    /// Minutes remaining in the week. Negative if over budget.
    func remainingThisWeek(containing date: Date = Date()) -> Double {
        guard config.weeklyMinutes > 0 else { return Double.infinity }
        return Double(config.weeklyMinutes) - minutesUsedThisWeek(containing: date)
    }

    /// Current pace analysis.
    func currentPace(as of: Date = Date()) -> BudgetPace {
        let usedToday = minutesUsed(on: of)
        let usedWeek = minutesUsedThisWeek(containing: of)
        let remToday = config.dailyMinutes > 0 ? max(0, Double(config.dailyMinutes) - usedToday) : 0
        let remWeek = config.weeklyMinutes > 0 ? max(0, Double(config.weeklyMinutes) - usedWeek) : 0

        let weekday = calendar.component(.weekday, from: of)
        // Days remaining in week (Sun=1..Sat=7, week starts Mon)
        let daysLeft = max(1, 8 - (weekday == 1 ? 7 : weekday - 1))

        let suggestedPace: Double
        if config.weeklyMinutes > 0 && daysLeft > 0 {
            suggestedPace = remWeek / Double(daysLeft)
        } else {
            suggestedPace = 0
        }

        let onTrack: Bool
        if config.weeklyMinutes > 0 {
            // On track if remaining can be covered within daily budget * remaining days
            let maxPossible = config.dailyMinutes > 0 ? Double(config.dailyMinutes) * Double(daysLeft) : remWeek
            onTrack = remWeek <= maxPossible
        } else {
            onTrack = true
        }

        return BudgetPace(
            usedToday: usedToday,
            dailyBudget: config.dailyMinutes,
            remainingToday: remToday,
            usedThisWeek: usedWeek,
            weeklyBudget: config.weeklyMinutes,
            remainingThisWeek: remWeek,
            daysRemainingInWeek: daysLeft,
            suggestedDailyPace: suggestedPace,
            onTrack: onTrack
        )
    }

    // MARK: - Daily Summary

    /// Summary for a specific date.
    func dailySummary(for date: Date) -> DailyBudgetSummary {
        let dayEntries = entries(on: date)
        let usedMin = dayEntries.reduce(0.0) { $0 + $1.durationMinutes }
        let wpms = dayEntries.compactMap { $0.actualWPM }
        let avgWPM = wpms.isEmpty ? nil : wpms.reduce(0, +) / wpms.count

        return DailyBudgetSummary(
            date: date,
            budgetMinutes: config.dailyMinutes,
            usedMinutes: usedMin,
            remainingMinutes: config.dailyMinutes > 0 ? max(0, Double(config.dailyMinutes) - usedMin) : 0,
            articleCount: dayEntries.count,
            averageWPM: avgWPM
        )
    }

    // MARK: - Weekly Report

    /// Generate a weekly budget report for the week containing the given date.
    func weeklyReport(containing date: Date = Date()) -> WeeklyBudgetReport {
        let weekDates = datesInWeek(containing: date)
        let dailySummaries = weekDates.map { dailySummary(for: $0) }

        let totalUsed = dailySummaries.reduce(0.0) { $0 + $1.usedMinutes }
        let totalArticles = dailySummaries.reduce(0) { $0 + $1.articleCount }

        // Adherence: how well daily usage stays within budget (0-100)
        let adherence = calculateAdherence(dailySummaries)

        // Streaks
        let (current, longest) = calculateStreaks(dailySummaries)

        let avgDaily = dailySummaries.isEmpty ? 0 : totalUsed / Double(dailySummaries.count)

        // Busiest/quietest
        let activeDays = dailySummaries.filter { $0.usedMinutes > 0 }
        let busiest = activeDays.max(by: { $0.usedMinutes < $1.usedMinutes })
        let quietest = dailySummaries.min(by: { $0.usedMinutes < $1.usedMinutes })

        return WeeklyBudgetReport(
            weekStartDate: weekDates.first ?? date,
            weekEndDate: weekDates.last ?? date,
            config: config,
            dailySummaries: dailySummaries,
            totalBudgetMinutes: config.weeklyMinutes,
            totalUsedMinutes: totalUsed,
            totalArticles: totalArticles,
            adherenceScore: adherence,
            streak: current,
            longestStreak: longest,
            averageDailyMinutes: avgDaily,
            busiestDay: busiest.map { Self.dayOfWeekFormatter.string(from: $0.date) },
            quietestDay: quietest.map { Self.dayOfWeekFormatter.string(from: $0.date) }
        )
    }

    // MARK: - Article Recommendations

    /// Suggest articles that fit within the remaining daily time budget.
    /// Articles are scored by how well their estimated reading time fits the remaining minutes.
    func suggestArticles(_ candidates: [TimeFitArticle], on date: Date = Date(), maxResults: Int = 5) -> [TimeFitArticle] {
        let remaining = config.dailyMinutes > 0 ? remainingToday(as: date) : 30.0 // default 30 min if no budget
        guard remaining > 0 else { return [] }

        var scored = candidates.map { article -> TimeFitArticle in
            var a = article
            // Score: prefer articles that fit well (not too long, not trivially short)
            if article.estimatedMinutes <= remaining {
                // Fits: score by ratio (closer to filling remaining = higher)
                let ratio = article.estimatedMinutes / remaining
                a.fitScore = 0.5 + (ratio * 0.5) // 0.5-1.0
            } else {
                // Doesn't fit: penalize by how much it exceeds
                let overRatio = remaining / article.estimatedMinutes
                a.fitScore = overRatio * 0.3 // 0.0-0.3
            }
            return a
        }

        scored.sort { $0.fitScore > $1.fitScore }
        return Array(scored.prefix(maxResults))
    }

    /// Estimate reading time for an article based on word count.
    func estimateReadingMinutes(wordCount: Int) -> Double {
        guard config.wordsPerMinute > 0 else { return 0 }
        return Double(wordCount) / Double(config.wordsPerMinute)
    }

    // MARK: - Statistics

    /// Average minutes read per day over the last N days.
    func averageDailyMinutes(lastDays: Int = 7, as of: Date = Date()) -> Double {
        guard lastDays > 0 else { return 0 }
        var total = 0.0
        for i in 0..<lastDays {
            if let day = calendar.date(byAdding: .day, value: -i, to: of) {
                total += minutesUsed(on: day)
            }
        }
        return total / Double(lastDays)
    }

    /// Total minutes read all time.
    func totalMinutesAllTime() -> Double {
        return entries.reduce(0) { $0 + $1.durationMinutes }
    }

    /// Total articles read all time.
    func totalArticlesAllTime() -> Int {
        return entries.filter { $0.articleTitle != nil }.count
    }

    /// Unique reading days.
    func uniqueReadingDays() -> Int {
        let days = Set(entries.map { calendar.startOfDay(for: $0.date) })
        return days.count
    }

    /// Top feeds by reading time.
    func topFeedsByTime(limit: Int = 5) -> [(feedName: String, minutes: Double)] {
        var feedMinutes: [String: Double] = [:]
        for entry in entries {
            if let feed = entry.feedName {
                feedMinutes[feed, default: 0] += entry.durationMinutes
            }
        }
        return feedMinutes
            .sorted { $0.value > $1.value }
            .prefix(limit)
            .map { (feedName: $0.key, minutes: $0.value) }
    }

    // MARK: - Text Report

    /// Generate a human-readable text report for the current week.
    func textReport(containing date: Date = Date()) -> String {
        let report = weeklyReport(containing: date)
        var lines: [String] = []
        lines.append("📊 Reading Time Budget Report")
        lines.append("Week of \(Self.shortMonthDayFormatter.string(from: report.weekStartDate)) - \(Self.shortMonthDayFormatter.string(from: report.weekEndDate))")
        lines.append("")

        if report.totalBudgetMinutes > 0 {
            lines.append("Weekly Budget: \(report.totalBudgetMinutes) min | Used: \(String(format: "%.0f", report.totalUsedMinutes)) min (\(String(format: "%.0f", report.weeklyUsagePercent))%)")
        }
        lines.append("Articles Read: \(report.totalArticles)")
        lines.append("Adherence Score: \(String(format: "%.0f", report.adherenceScore))/100")
        lines.append("Streak: \(report.streak) days | Longest: \(report.longestStreak) days")
        lines.append("")

        lines.append("Daily Breakdown:")
        for summary in report.dailySummaries {
            let day = Self.shortDayFormatter.string(from: summary.date)
            let bar = summary.budgetMinutes > 0
                ? " [\(summary.grade)]"
                : ""
            lines.append("  \(day): \(String(format: "%.0f", summary.usedMinutes)) min, \(summary.articleCount) articles\(bar)")
        }

        if let busiest = report.busiestDay {
            lines.append("")
            lines.append("Busiest: \(busiest) | Quietest: \(report.quietestDay ?? "-")")
        }

        let pace = currentPace(as: date)
        lines.append("")
        lines.append("Pace: \(pace.paceDescription)")

        return lines.joined(separator: "\n")
    }

    // MARK: - Persistence

    private struct PersistenceData: Codable {
        let config: TimeBudgetConfig
        let entries: [ReadingTimeEntry]
    }

    private func save() {
        guard let path = persistencePath else { return }
        let data = PersistenceData(config: config, entries: entries)
        if let encoded = try? JSONEncoder().encode(data) {
            try? encoded.write(to: URL(fileURLWithPath: path))
        }
    }

    private func loadFromDisk(path: String) {
        let url = URL(fileURLWithPath: path)
        guard let data = try? Data(contentsOf: url),
              let decoded = try? JSONDecoder().decode(PersistenceData.self, from: data) else { return }
        self.config = decoded.config
        self.entries = decoded.entries
    }

    /// Export state as JSON string.
    func exportJSON() -> String? {
        let data = PersistenceData(config: config, entries: entries)
        guard let encoded = try? JSONEncoder().encode(data) else { return nil }
        return String(data: encoded, encoding: .utf8)
    }

    /// Import state from JSON string.
    func importJSON(_ json: String) -> Bool {
        guard let data = json.data(using: .utf8),
              let decoded = try? JSONDecoder().decode(PersistenceData.self, from: data) else { return false }
        self.config = decoded.config
        self.entries = decoded.entries
        save()
        return true
    }

    // MARK: - Helpers

    private func datesInWeek(containing date: Date) -> [Date] {
        // Find Monday of the week
        var cal = calendar
        cal.firstWeekday = 2 // Monday
        guard let weekInterval = cal.dateInterval(of: .weekOfYear, for: date) else { return [] }
        var dates: [Date] = []
        var current = weekInterval.start
        for _ in 0..<7 {
            dates.append(current)
            guard let next = cal.date(byAdding: .day, value: 1, to: current) else { break }
            current = next
        }
        return dates
    }

    private func calculateAdherence(_ summaries: [DailyBudgetSummary]) -> Double {
        guard config.dailyMinutes > 0 else { return 100 }
        let daysWithActivity = summaries.filter { $0.usedMinutes > 0 || $0.budgetMinutes > 0 }
        guard !daysWithActivity.isEmpty else { return 100 }

        var totalScore = 0.0
        for s in daysWithActivity {
            let ratio = s.usedMinutes / Double(s.budgetMinutes)
            // Perfect adherence at 100%. Penalty for over or under.
            let deviation = abs(1.0 - ratio)
            let dayScore = max(0, 1.0 - deviation)
            totalScore += dayScore
        }
        return (totalScore / Double(daysWithActivity.count)) * 100.0
    }

    private func calculateStreaks(_ summaries: [DailyBudgetSummary]) -> (current: Int, longest: Int) {
        guard config.dailyMinutes > 0 else { return (0, 0) }
        var current = 0
        var longest = 0
        var streak = 0

        for s in summaries {
            let ratio = s.usedMinutes / Double(s.budgetMinutes)
            if ratio >= 0.5 && ratio <= 1.5 {
                streak += 1
                longest = max(longest, streak)
            } else {
                streak = 0
            }
        }
        current = streak
        return (current, longest)
    }
}
