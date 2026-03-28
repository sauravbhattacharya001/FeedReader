//
//  ReadingYearInReview.swift
//  FeedReader
//
//  Generates an annual reading summary ("Year in Review") from
//  ReadingStatsManager events. Includes total articles, monthly
//  breakdown, top feeds, top topics, reading streaks, busiest
//  day/hour, and shareable text summary.
//

import Foundation

class ReadingYearInReview {
    
    // MARK: - Types
    
    /// Complete year-in-review report for a given year.
    struct YearReport {
        let year: Int
        let totalArticles: Int
        let totalFeeds: Int
        let monthlyBreakdown: [Int: Int]          // month (1-12) → count
        let topFeeds: [(name: String, count: Int)] // sorted desc, max 10
        let topTopics: [(topic: String, count: Int)] // from title keywords, max 10
        let busiestDay: (date: Date, count: Int)?
        let busiestHour: Int?                      // 0-23
        let busiestDayOfWeek: Int?                 // 1=Sun, 7=Sat
        let longestStreak: Int                     // consecutive days
        let averagePerDay: Double
        let averagePerWeek: Double
        let peakMonth: Int?                        // 1-12
        let quietestMonth: Int?                    // 1-12
        let firstArticleDate: Date?
        let lastArticleDate: Date?
        let weekdayVsWeekend: (weekday: Int, weekend: Int)
    }
    
    // MARK: - Singleton
    
    static let shared = ReadingYearInReview()
    
    // MARK: - Private
    
    private let calendar = Calendar.current
    
    /// Stop words excluded from topic extraction.
    /// Delegates to the canonical stop-word list in TextAnalyzer.
    private var stopWords: Set<String> { TextAnalyzer.stopWords }
    
    // MARK: - Public API
    
    /// Generate a year-in-review report for the specified year.
    /// Uses events from `ReadingStatsManager.shared`.
    func generateReport(for year: Int) -> YearReport {
        let events = eventsForYear(year)
        return buildReport(year: year, events: events)
    }
    
    /// Generate a report from a custom set of events (for testing).
    func generateReport(for year: Int, from events: [ReadingStatsManager.ReadEvent]) -> YearReport {
        let filtered = events.filter { calendar.component(.year, from: $0.timestamp) == year }
        return buildReport(year: year, events: filtered)
    }
    
    /// Generate a shareable text summary of the year report.
    func formatSummary(_ report: YearReport) -> String {
        var lines: [String] = []
        lines.append("📖 Your \(report.year) Reading Year in Review")
        lines.append(String(repeating: "─", count: 40))
        lines.append("")
        lines.append("📚 Total articles read: \(report.totalArticles)")
        lines.append("📡 Feeds followed: \(report.totalFeeds)")
        lines.append("📅 Daily average: \(String(format: "%.1f", report.averagePerDay))")
        lines.append("📆 Weekly average: \(String(format: "%.1f", report.averagePerWeek))")
        lines.append("🔥 Longest streak: \(report.longestStreak) days")
        lines.append("")
        
        if let peak = report.peakMonth {
            lines.append("📈 Peak month: \(monthName(peak))")
        }
        if let quiet = report.quietestMonth {
            lines.append("📉 Quietest month: \(monthName(quiet))")
        }
        
        let wd = report.weekdayVsWeekend
        lines.append("🏢 Weekday reads: \(wd.weekday)  |  🏖 Weekend reads: \(wd.weekend)")
        lines.append("")
        
        if !report.topFeeds.isEmpty {
            lines.append("⭐ Top Feeds:")
            for (i, feed) in report.topFeeds.prefix(5).enumerated() {
                lines.append("  \(i + 1). \(feed.name) (\(feed.count))")
            }
            lines.append("")
        }
        
        if !report.topTopics.isEmpty {
            lines.append("🏷 Top Topics:")
            for (i, topic) in report.topTopics.prefix(5).enumerated() {
                lines.append("  \(i + 1). \(topic.topic) (\(topic.count))")
            }
        }
        
        return lines.joined(separator: "\n")
    }
    
    // MARK: - Private Helpers
    
    private func eventsForYear(_ year: Int) -> [ReadingStatsManager.ReadEvent] {
        let allEvents = ReadingStatsManager.shared.events
        return allEvents.filter { calendar.component(.year, from: $0.timestamp) == year }
    }
    
    private func buildReport(year: Int, events: [ReadingStatsManager.ReadEvent]) -> YearReport {
        guard !events.isEmpty else {
            return YearReport(
                year: year, totalArticles: 0, totalFeeds: 0,
                monthlyBreakdown: [:], topFeeds: [], topTopics: [],
                busiestDay: nil, busiestHour: nil, busiestDayOfWeek: nil,
                longestStreak: 0, averagePerDay: 0, averagePerWeek: 0,
                peakMonth: nil, quietestMonth: nil,
                firstArticleDate: nil, lastArticleDate: nil,
                weekdayVsWeekend: (0, 0)
            )
        }
        
        // Monthly breakdown
        var monthly: [Int: Int] = [:]
        for event in events {
            let month = calendar.component(.month, from: event.timestamp)
            monthly[month, default: 0] += 1
        }
        
        // Feed breakdown
        var feedCounts: [String: Int] = [:]
        for event in events {
            feedCounts[event.feedName, default: 0] += 1
        }
        let topFeeds = feedCounts.sorted { $0.value > $1.value }
            .prefix(10)
            .map { (name: $0.key, count: $0.value) }
        
        // Topic extraction from titles
        let topTopics = extractTopics(from: events)
        
        // Daily counts for busiest day and streaks
        var dailyCounts: [DateComponents: Int] = [:]
        for event in events {
            let dc = calendar.dateComponents([.year, .month, .day], from: event.timestamp)
            dailyCounts[dc, default: 0] += 1
        }
        
        let busiestDay: (date: Date, count: Int)? = dailyCounts.max(by: { $0.value < $1.value }).flatMap { entry in
            guard let date = calendar.date(from: entry.key) else { return nil }
            return (date: date, count: entry.value)
        }
        
        // Busiest hour
        var hourlyCounts: [Int: Int] = [:]
        for event in events {
            let hour = calendar.component(.hour, from: event.timestamp)
            hourlyCounts[hour, default: 0] += 1
        }
        let busiestHour = hourlyCounts.max(by: { $0.value < $1.value })?.key
        
        // Busiest day of week
        var dowCounts: [Int: Int] = [:]
        for event in events {
            let dow = calendar.component(.weekday, from: event.timestamp)
            dowCounts[dow, default: 0] += 1
        }
        let busiestDow = dowCounts.max(by: { $0.value < $1.value })?.key
        
        // Longest streak
        let sortedDays = dailyCounts.keys
            .compactMap { calendar.date(from: $0) }
            .sorted()
        let longestStreak = computeLongestStreak(sortedDays)
        
        // Averages
        let sorted = events.sorted { $0.timestamp < $1.timestamp }
        let firstDate = sorted.first!.timestamp
        let lastDate = sorted.last!.timestamp
        let daySpan = max(1, calendar.dateComponents([.day], from: firstDate, to: lastDate).day! + 1)
        let avgPerDay = Double(events.count) / Double(daySpan)
        let avgPerWeek = avgPerDay * 7.0
        
        // Peak / quietest month
        let peakMonth = monthly.max(by: { $0.value < $1.value })?.key
        let quietestMonth = monthly.min(by: { $0.value < $1.value })?.key
        
        // Weekday vs weekend
        var weekdayCount = 0
        var weekendCount = 0
        for event in events {
            let dow = calendar.component(.weekday, from: event.timestamp)
            if dow == 1 || dow == 7 {
                weekendCount += 1
            } else {
                weekdayCount += 1
            }
        }
        
        return YearReport(
            year: year,
            totalArticles: events.count,
            totalFeeds: feedCounts.count,
            monthlyBreakdown: monthly,
            topFeeds: Array(topFeeds),
            topTopics: topTopics,
            busiestDay: busiestDay,
            busiestHour: busiestHour,
            busiestDayOfWeek: busiestDow,
            longestStreak: longestStreak,
            averagePerDay: avgPerDay,
            averagePerWeek: avgPerWeek,
            peakMonth: peakMonth,
            quietestMonth: quietestMonth,
            firstArticleDate: firstDate,
            lastArticleDate: lastDate,
            weekdayVsWeekend: (weekday: weekdayCount, weekend: weekendCount)
        )
    }
    
    private func extractTopics(from events: [ReadingStatsManager.ReadEvent]) -> [(topic: String, count: Int)] {
        var wordCounts: [String: Int] = [:]
        for event in events {
            let words = event.title
                .lowercased()
                .components(separatedBy: CharacterSet.alphanumerics.inverted)
                .filter { $0.count >= 3 && !stopWords.contains($0) }
            for word in Set(words) { // count each word once per article
                wordCounts[word, default: 0] += 1
            }
        }
        return wordCounts.sorted { $0.value > $1.value }
            .prefix(10)
            .map { (topic: $0.key, count: $0.value) }
    }
    
    private func computeLongestStreak(_ sortedDates: [Date]) -> Int {
        guard sortedDates.count > 1 else { return sortedDates.count }
        var maxStreak = 1
        var currentStreak = 1
        for i in 1..<sortedDates.count {
            let daysBetween = calendar.dateComponents([.day], from: sortedDates[i - 1], to: sortedDates[i]).day ?? 0
            if daysBetween == 1 {
                currentStreak += 1
                maxStreak = max(maxStreak, currentStreak)
            } else if daysBetween > 1 {
                currentStreak = 1
            }
            // daysBetween == 0 means same day (skip)
        }
        return maxStreak
    }
    
    private func monthName(_ month: Int) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US")
        return formatter.monthSymbols[month - 1]
    }
}
