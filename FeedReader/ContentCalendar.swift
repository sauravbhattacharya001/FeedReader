//
//  ContentCalendar.swift
//  FeedReader
//
//  Analyzes feed publishing patterns to detect schedules, predict
//  next updates, and identify optimal reading windows. Helps users
//  know when to check feeds for fresh content.
//

import Foundation

/// A published article record for calendar analysis.
struct PublishEvent: Codable, Equatable {
    let feedURL: String
    let feedName: String
    let articleTitle: String
    let publishedDate: Date
    let wordCount: Int
    
    init(feedURL: String, feedName: String, articleTitle: String,
         publishedDate: Date, wordCount: Int = 0) {
        self.feedURL = feedURL
        self.feedName = feedName
        self.articleTitle = articleTitle
        self.publishedDate = publishedDate
        self.wordCount = max(0, wordCount)
    }
}

/// Day of the week (1=Sunday, 7=Saturday).
enum Weekday: Int, Codable, CaseIterable, Comparable {
    case sunday = 1, monday, tuesday, wednesday, thursday, friday, saturday
    
    var name: String {
        switch self {
        case .sunday: return "Sunday"
        case .monday: return "Monday"
        case .tuesday: return "Tuesday"
        case .wednesday: return "Wednesday"
        case .thursday: return "Thursday"
        case .friday: return "Friday"
        case .saturday: return "Saturday"
        }
    }
    
    var shortName: String {
        return String(name.prefix(3))
    }
    
    static func < (lhs: Weekday, rhs: Weekday) -> Bool {
        return lhs.rawValue < rhs.rawValue
    }
}

/// Hour slot (0-23).
struct HourSlot: Codable, Equatable, Comparable {
    let hour: Int // 0-23
    
    var label: String {
        if hour == 0 { return "12 AM" }
        if hour < 12 { return "\(hour) AM" }
        if hour == 12 { return "12 PM" }
        return "\(hour - 12) PM"
    }
    
    static func < (lhs: HourSlot, rhs: HourSlot) -> Bool {
        return lhs.hour < rhs.hour
    }
}

/// Detected publishing cadence for a feed.
enum PublishingCadence: String, Codable {
    case multipleDaily = "Multiple times daily"
    case daily = "Daily"
    case weekdays = "Weekdays only"
    case weekends = "Weekends only"
    case weekly = "Weekly"
    case biweekly = "Bi-weekly"
    case irregular = "Irregular"
    case inactive = "Inactive"
    
    var emoji: String {
        switch self {
        case .multipleDaily: return "🔥"
        case .daily: return "📅"
        case .weekdays: return "💼"
        case .weekends: return "🌴"
        case .weekly: return "📰"
        case .biweekly: return "📆"
        case .irregular: return "🎲"
        case .inactive: return "💤"
        }
    }
}

/// Publishing schedule analysis for a single feed.
struct FeedScheduleProfile: Codable, Equatable {
    let feedURL: String
    let feedName: String
    let cadence: PublishingCadence
    let avgArticlesPerDay: Double
    let peakDays: [Weekday]
    let peakHours: [HourSlot]
    let quietDays: [Weekday]
    let avgIntervalHours: Double
    let lastPublished: Date?
    let predictedNextUpdate: Date?
    let totalArticles: Int
    let analysisWindow: DateInterval
}

/// A recommended reading window.
struct ReadingWindow: Codable, Equatable {
    let startHour: Int
    let endHour: Int
    let expectedNewArticles: Double
    let feedNames: [String]
    let quality: ReadingWindowQuality
    
    var label: String {
        let start = HourSlot(hour: startHour).label
        let end = HourSlot(hour: endHour).label
        return "\(start) – \(end)"
    }
}

enum ReadingWindowQuality: String, Codable {
    case optimal = "Optimal"
    case good = "Good"
    case fair = "Fair"
}

/// Daily content forecast.
struct DailyForecast: Codable, Equatable {
    let date: Date
    let weekday: Weekday
    let expectedArticleCount: Double
    let activeFeedCount: Int
    let busyFeeds: [String]
    let quietFeeds: [String]
    let intensity: ContentIntensity
}

enum ContentIntensity: String, Codable {
    case light = "Light"
    case moderate = "Moderate"
    case heavy = "Heavy"
    case veryHeavy = "Very Heavy"
    
    var emoji: String {
        switch self {
        case .light: return "🟢"
        case .moderate: return "🟡"
        case .heavy: return "🟠"
        case .veryHeavy: return "🔴"
        }
    }
}

/// Full calendar analysis report.
struct CalendarReport: Codable {
    let generatedAt: Date
    let analysisWindow: DateInterval
    let feedProfiles: [FeedScheduleProfile]
    let readingWindows: [ReadingWindow]
    let weeklyForecast: [DailyForecast]
    let busiestDay: Weekday?
    let quietestDay: Weekday?
    let busiestHour: HourSlot?
    let totalFeedsAnalyzed: Int
    let overallAvgArticlesPerDay: Double
}

/// Notification posted when calendar analysis completes.
extension Notification.Name {
    static let contentCalendarDidUpdate = Notification.Name("ContentCalendarDidUpdateNotification")
}

/// Analyzes feed publishing patterns and generates reading schedules.
class ContentCalendar {
    
    // MARK: - Storage
    
    private var events: [PublishEvent] = []
    private let calendar = Calendar.current
    private let maxEvents = 10000
    
    // MARK: - Persistence
    
    private static let storageKey = "ContentCalendar_events"
    
    init() {}
    
    // MARK: - Event Recording
    
    /// Record a publish event for analysis.
    func recordEvent(_ event: PublishEvent) {
        events.append(event)
        if events.count > maxEvents {
            // Keep most recent events
            events = Array(events.suffix(maxEvents))
        }
    }
    
    /// Record multiple events at once.
    func recordEvents(_ newEvents: [PublishEvent]) {
        events.append(contentsOf: newEvents)
        if events.count > maxEvents {
            events = Array(events.suffix(maxEvents))
        }
    }
    
    /// Clear all events.
    func clearEvents() {
        events.removeAll()
    }
    
    /// Get event count.
    var eventCount: Int { events.count }
    
    /// Get events for a specific feed.
    func events(forFeed feedURL: String) -> [PublishEvent] {
        return events.filter { $0.feedURL == feedURL }
    }
    
    // MARK: - Schedule Detection
    
    /// Analyze publishing schedule for a specific feed.
    func analyzeSchedule(forFeed feedURL: String, referenceDate: Date = Date()) -> FeedScheduleProfile? {
        let feedEvents = events.filter { $0.feedURL == feedURL }
            .sorted { $0.publishedDate < $1.publishedDate }
        
        guard !feedEvents.isEmpty else { return nil }
        guard let feedName = feedEvents.first?.feedName else { return nil }
        
        let windowStart = feedEvents.first!.publishedDate
        let windowEnd = max(feedEvents.last!.publishedDate, referenceDate)
        let window = DateInterval(start: windowStart, end: windowEnd)
        
        // Count articles per weekday
        var weekdayCounts: [Weekday: Int] = [:]
        var hourCounts: [Int: Int] = [:]
        
        for event in feedEvents {
            let comps = calendar.dateComponents([.weekday, .hour], from: event.publishedDate)
            if let wd = comps.weekday, let weekday = Weekday(rawValue: wd) {
                weekdayCounts[weekday, default: 0] += 1
            }
            if let hour = comps.hour {
                hourCounts[hour, default: 0] += 1
            }
        }
        
        // Calculate intervals between articles
        var intervals: [TimeInterval] = []
        for i in 1..<feedEvents.count {
            let interval = feedEvents[i].publishedDate.timeIntervalSince(feedEvents[i-1].publishedDate)
            if interval > 0 {
                intervals.append(interval)
            }
        }
        
        let avgInterval = intervals.isEmpty ? 0 : intervals.reduce(0, +) / Double(intervals.count)
        let avgIntervalHours = avgInterval / 3600.0
        
        // Days in analysis window
        let totalDays = max(1, window.duration / 86400.0)
        let avgPerDay = Double(feedEvents.count) / totalDays
        
        // Detect cadence
        let cadence = detectCadence(avgPerDay: avgPerDay, weekdayCounts: weekdayCounts,
                                     avgIntervalHours: avgIntervalHours, totalDays: totalDays,
                                     totalArticles: feedEvents.count)
        
        // Peak days (above average)
        let avgPerWeekday = Double(feedEvents.count) / max(1.0, Double(weekdayCounts.count))
        let peakDays = weekdayCounts.filter { Double($0.value) > avgPerWeekday }
            .sorted { $0.value > $1.value }
            .map { $0.key }
        
        // Quiet days (zero articles)
        let activeDays = Set(weekdayCounts.keys)
        let quietDays = Weekday.allCases.filter { !activeDays.contains($0) }
        
        // Peak hours (top 3)
        let peakHours = hourCounts.sorted { $0.value > $1.value }
            .prefix(3)
            .map { HourSlot(hour: $0.key) }
            .sorted()
        
        // Predict next update
        let lastPublished = feedEvents.last?.publishedDate
        let predictedNext: Date?
        if let last = lastPublished, avgInterval > 0 {
            predictedNext = last.addingTimeInterval(avgInterval)
        } else {
            predictedNext = nil
        }
        
        return FeedScheduleProfile(
            feedURL: feedURL,
            feedName: feedName,
            cadence: cadence,
            avgArticlesPerDay: round(avgPerDay * 100) / 100,
            peakDays: peakDays,
            peakHours: peakHours,
            quietDays: quietDays,
            avgIntervalHours: round(avgIntervalHours * 10) / 10,
            lastPublished: lastPublished,
            predictedNextUpdate: predictedNext,
            totalArticles: feedEvents.count,
            analysisWindow: window
        )
    }
    
    /// Detect the publishing cadence from metrics.
    private func detectCadence(avgPerDay: Double, weekdayCounts: [Weekday: Int],
                                avgIntervalHours: Double, totalDays: Double,
                                totalArticles: Int) -> PublishingCadence {
        // Not enough data
        if totalArticles < 2 { return .inactive }
        if totalDays < 1 { return .irregular }
        
        // Check if inactive (very low rate over long period)
        if avgPerDay < 0.05 && totalDays > 30 { return .inactive }
        
        // Multiple times daily
        if avgPerDay >= 2.0 { return .multipleDaily }
        
        // Daily
        if avgPerDay >= 0.8 { return .daily }
        
        // Check weekday/weekend patterns
        let weekdayKeys: Set<Weekday> = [.monday, .tuesday, .wednesday, .thursday, .friday]
        let weekendKeys: Set<Weekday> = [.saturday, .sunday]
        
        let weekdayArticles = weekdayCounts.filter { weekdayKeys.contains($0.key) }.values.reduce(0, +)
        let weekendArticles = weekdayCounts.filter { weekendKeys.contains($0.key) }.values.reduce(0, +)
        
        if weekdayArticles > 0 && weekendArticles == 0 && totalDays > 14 {
            return .weekdays
        }
        if weekendArticles > 0 && weekdayArticles == 0 && totalDays > 14 {
            return .weekends
        }
        
        // Weekly
        if avgPerDay >= 0.1 && avgPerDay < 0.3 { return .weekly }
        
        // Bi-weekly
        if avgPerDay >= 0.03 && avgPerDay < 0.1 { return .biweekly }
        
        // Weekdays (higher weekday ratio)
        if totalDays > 14 && weekdayArticles > 0 && weekendArticles == 0 {
            return .weekdays
        }
        
        return .irregular
    }
    
    // MARK: - Reading Windows
    
    /// Find optimal reading windows across all feeds.
    func findReadingWindows(referenceDate: Date = Date()) -> [ReadingWindow] {
        guard !events.isEmpty else { return [] }
        
        // Count articles per hour across all feeds
        var hourArticleCounts: [Int: (count: Int, feeds: Set<String>)] = [:]
        
        for event in events {
            let hour = calendar.component(.hour, from: event.publishedDate)
            var entry = hourArticleCounts[hour] ?? (count: 0, feeds: Set())
            entry.count += 1
            entry.feeds.insert(event.feedName)
            hourArticleCounts[hour] = entry
        }
        
        guard !hourArticleCounts.isEmpty else { return [] }
        
        // Find 3-hour windows with most content
        var windows: [(start: Int, end: Int, score: Double, feeds: Set<String>)] = []
        
        for startHour in 0..<24 {
            let endHour = (startHour + 3) % 24
            var totalCount = 0
            var feeds: Set<String> = []
            
            for offset in 0..<3 {
                let h = (startHour + offset) % 24
                if let entry = hourArticleCounts[h] {
                    totalCount += entry.count
                    feeds.formUnion(entry.feeds)
                }
            }
            
            if totalCount > 0 {
                let totalDays = max(1.0, events.map { $0.publishedDate }.span / 86400.0)
                let avgPerWindow = Double(totalCount) / totalDays
                windows.append((startHour, endHour, avgPerWindow, feeds))
            }
        }
        
        // Sort by score, take top 3 non-overlapping
        windows.sort { $0.score > $1.score }
        
        var result: [ReadingWindow] = []
        var usedHours: Set<Int> = []
        
        for w in windows {
            let hours = Set((0..<3).map { (w.start + $0) % 24 })
            if hours.isDisjoint(with: usedHours) {
                let quality: ReadingWindowQuality
                if result.isEmpty { quality = .optimal }
                else if result.count == 1 { quality = .good }
                else { quality = .fair }
                
                result.append(ReadingWindow(
                    startHour: w.start,
                    endHour: w.end,
                    expectedNewArticles: round(w.score * 10) / 10,
                    feedNames: w.feeds.sorted(),
                    quality: quality
                ))
                usedHours.formUnion(hours)
                
                if result.count >= 3 { break }
            }
        }
        
        return result
    }
    
    // MARK: - Forecasting
    
    /// Generate a 7-day content forecast.
    func generateWeeklyForecast(startDate: Date = Date()) -> [DailyForecast] {
        guard !events.isEmpty else { return [] }
        
        // Build per-feed, per-weekday averages
        let feedURLs = Set(events.map { $0.feedURL })
        let totalDays = max(1.0, events.map { $0.publishedDate }.span / 86400.0)
        let weeksInData = max(1.0, totalDays / 7.0)
        
        var weekdayFeedCounts: [Weekday: [String: Int]] = [:]
        
        for event in events {
            let wd = calendar.component(.weekday, from: event.publishedDate)
            guard let weekday = Weekday(rawValue: wd) else { continue }
            weekdayFeedCounts[weekday, default: [:]][event.feedName, default: 0] += 1
        }
        
        var forecasts: [DailyForecast] = []
        
        for dayOffset in 0..<7 {
            guard let date = calendar.date(byAdding: .day, value: dayOffset, to: startDate) else { continue }
            let wd = calendar.component(.weekday, from: date)
            guard let weekday = Weekday(rawValue: wd) else { continue }
            
            let feedCounts = weekdayFeedCounts[weekday] ?? [:]
            let expectedTotal = feedCounts.values.reduce(0.0) { $0 + Double($1) / weeksInData }
            
            let sortedFeeds = feedCounts.sorted { $0.value > $1.value }
            let busyFeeds = sortedFeeds.prefix(3).map { $0.key }
            
            let activeFeeds = Set(feedCounts.filter { $0.value > 0 }.keys)
            let allFeedNames = Set(events.map { $0.feedName })
            let quietFeeds = Array(allFeedNames.subtracting(activeFeeds)).sorted().prefix(3).map { $0 }
            
            let intensity: ContentIntensity
            let avgDailyOverall = Double(events.count) / totalDays
            if expectedTotal < avgDailyOverall * 0.5 {
                intensity = .light
            } else if expectedTotal < avgDailyOverall * 1.0 {
                intensity = .moderate
            } else if expectedTotal < avgDailyOverall * 1.5 {
                intensity = .heavy
            } else {
                intensity = .veryHeavy
            }
            
            forecasts.append(DailyForecast(
                date: date,
                weekday: weekday,
                expectedArticleCount: round(expectedTotal * 10) / 10,
                activeFeedCount: activeFeeds.count,
                busyFeeds: busyFeeds,
                quietFeeds: Array(quietFeeds),
                intensity: intensity
            ))
        }
        
        return forecasts
    }
    
    // MARK: - Full Report
    
    /// Generate a comprehensive calendar analysis report.
    func generateReport(referenceDate: Date = Date()) -> CalendarReport {
        let feedURLs = Set(events.map { $0.feedURL })
        
        let profiles = feedURLs.compactMap { analyzeSchedule(forFeed: $0, referenceDate: referenceDate) }
            .sorted { $0.avgArticlesPerDay > $1.avgArticlesPerDay }
        
        let windows = findReadingWindows(referenceDate: referenceDate)
        let forecast = generateWeeklyForecast(startDate: referenceDate)
        
        // Overall stats
        var globalWeekdayCounts: [Weekday: Int] = [:]
        var globalHourCounts: [Int: Int] = [:]
        
        for event in events {
            let comps = calendar.dateComponents([.weekday, .hour], from: event.publishedDate)
            if let wd = comps.weekday, let weekday = Weekday(rawValue: wd) {
                globalWeekdayCounts[weekday, default: 0] += 1
            }
            if let hour = comps.hour {
                globalHourCounts[hour, default: 0] += 1
            }
        }
        
        let busiestDay = globalWeekdayCounts.max(by: { $0.value < $1.value })?.key
        let quietestDay = Weekday.allCases.min(by: {
            (globalWeekdayCounts[$0] ?? 0) < (globalWeekdayCounts[$1] ?? 0)
        })
        let busiestHour = globalHourCounts.max(by: { $0.value < $1.value }).map { HourSlot(hour: $0.key) }
        
        let totalDays = max(1.0, events.map { $0.publishedDate }.span / 86400.0)
        let overallAvg = Double(events.count) / totalDays
        
        let windowStart = events.map { $0.publishedDate }.min() ?? referenceDate
        let windowEnd = events.map { $0.publishedDate }.max() ?? referenceDate
        
        return CalendarReport(
            generatedAt: referenceDate,
            analysisWindow: DateInterval(start: windowStart, end: max(windowStart.addingTimeInterval(1), windowEnd)),
            feedProfiles: profiles,
            readingWindows: windows,
            weeklyForecast: forecast,
            busiestDay: busiestDay,
            quietestDay: quietestDay,
            busiestHour: busiestHour,
            totalFeedsAnalyzed: feedURLs.count,
            overallAvgArticlesPerDay: round(overallAvg * 100) / 100
        )
    }
    
    // MARK: - Export
    
    /// Export calendar data as JSON.
    func exportJSON(referenceDate: Date = Date()) -> String? {
        let report = generateReport(referenceDate: referenceDate)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(report) else { return nil }
        return String(data: data, encoding: .utf8)
    }
}

// MARK: - Array Extension for Date Span

private extension Array where Element == Date {
    /// Time span from earliest to latest date.
    var span: TimeInterval {
        guard let earliest = self.min(), let latest = self.max() else { return 0 }
        return latest.timeIntervalSince(earliest)
    }
}
