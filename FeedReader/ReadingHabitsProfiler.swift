//
//  ReadingHabitsProfiler.swift
//  FeedReader
//
//  Analyzes reading behavior patterns to build a user profile:
//  - Time-of-day distribution (when you read most)
//  - Day-of-week patterns (weekday vs weekend habits)
//  - Session length clustering (quick scans vs deep reads)
//  - Topic preferences by time slot (what you read when)
//  - Reading consistency scoring
//  - Optimal reading windows (your most productive times)
//  - Actionable recommendations for better reading habits
//
//  All analysis is on-device using reading history data.
//  No external dependencies or network calls.
//
//  Persistence: JSON file in Documents directory.
//

import Foundation

// MARK: - Notifications

extension Notification.Name {
    /// Posted when the reading profile is updated.
    static let readingProfileDidUpdate = Notification.Name("ReadingProfileDidUpdateNotification")
}

// MARK: - Models

/// Time slot within a day (6 slots).
enum TimeSlot: String, Codable, CaseIterable, Comparable {
    case earlyMorning = "early_morning"  // 5am-9am
    case morning      = "morning"         // 9am-12pm
    case afternoon    = "afternoon"       // 12pm-5pm
    case evening      = "evening"         // 5pm-9pm
    case night        = "night"           // 9pm-1am
    case lateNight    = "late_night"      // 1am-5am

    var label: String {
        switch self {
        case .earlyMorning: return "Early Morning (5-9am)"
        case .morning:      return "Morning (9am-12pm)"
        case .afternoon:    return "Afternoon (12-5pm)"
        case .evening:      return "Evening (5-9pm)"
        case .night:        return "Night (9pm-1am)"
        case .lateNight:    return "Late Night (1-5am)"
        }
    }

    var sortOrder: Int {
        switch self {
        case .earlyMorning: return 0
        case .morning:      return 1
        case .afternoon:    return 2
        case .evening:      return 3
        case .night:        return 4
        case .lateNight:    return 5
        }
    }

    static func < (lhs: TimeSlot, rhs: TimeSlot) -> Bool {
        lhs.sortOrder < rhs.sortOrder
    }

    static func from(hour: Int) -> TimeSlot {
        switch hour {
        case 5..<9:   return .earlyMorning
        case 9..<12:  return .morning
        case 12..<17: return .afternoon
        case 17..<21: return .evening
        case 21...23: return .night
        case 0..<1:   return .night
        default:      return .lateNight  // 1-4
        }
    }
}

/// Session length category.
enum SessionCategory: String, Codable, CaseIterable {
    case quickScan  = "quick_scan"   // < 5 min
    case shortRead  = "short_read"   // 5-15 min
    case mediumRead = "medium_read"  // 15-30 min
    case deepRead   = "deep_read"    // 30-60 min
    case marathon   = "marathon"     // > 60 min

    var label: String {
        switch self {
        case .quickScan:  return "Quick Scan (<5m)"
        case .shortRead:  return "Short Read (5-15m)"
        case .mediumRead: return "Medium Read (15-30m)"
        case .deepRead:   return "Deep Read (30-60m)"
        case .marathon:   return "Marathon (60m+)"
        }
    }

    static func from(minutes: Double) -> SessionCategory {
        switch minutes {
        case ..<5:    return .quickScan
        case ..<15:   return .shortRead
        case ..<30:   return .mediumRead
        case ..<60:   return .deepRead
        default:      return .marathon
        }
    }
}

/// A recorded reading event for profiling.
struct ReadingEvent: Codable, Equatable {
    let id: String
    let date: Date
    let durationMinutes: Double
    let articlesRead: Int
    let feedName: String
    let topic: String?
    let timeSlot: TimeSlot
    let dayOfWeek: Int  // 1=Sunday ... 7=Saturday

    init(id: String = UUID().uuidString,
         date: Date,
         durationMinutes: Double,
         articlesRead: Int,
         feedName: String,
         topic: String? = nil) {
        self.id = id
        self.date = date
        self.durationMinutes = max(0, durationMinutes)
        self.articlesRead = max(0, articlesRead)
        self.feedName = feedName
        self.topic = topic

        let calendar = Calendar.current
        let hour = calendar.component(.hour, from: date)
        self.timeSlot = TimeSlot.from(hour: hour)
        self.dayOfWeek = calendar.component(.weekday, from: date)
    }
}

/// Time slot statistics.
struct TimeSlotStats: Codable {
    let slot: TimeSlot
    var eventCount: Int = 0
    var totalMinutes: Double = 0
    var totalArticles: Int = 0
    var topics: [String: Int] = [:]

    var averageMinutes: Double {
        eventCount > 0 ? totalMinutes / Double(eventCount) : 0
    }

    var averageArticles: Double {
        eventCount > 0 ? Double(totalArticles) / Double(eventCount) : 0
    }

    var topTopics: [String] {
        topics.sorted { $0.value > $1.value }.prefix(3).map { $0.key }
    }
}

/// Day of week statistics.
struct DayOfWeekStats: Codable {
    let dayOfWeek: Int  // 1=Sunday ... 7=Saturday
    var eventCount: Int = 0
    var totalMinutes: Double = 0
    var totalArticles: Int = 0

    var dayName: String {
        let names = ["", "Sunday", "Monday", "Tuesday", "Wednesday",
                     "Thursday", "Friday", "Saturday"]
        return dayOfWeek >= 1 && dayOfWeek <= 7 ? names[dayOfWeek] : "Unknown"
    }

    var isWeekend: Bool {
        dayOfWeek == 1 || dayOfWeek == 7
    }
}

/// Optimal reading window.
struct ReadingWindow: Codable {
    let timeSlot: TimeSlot
    let dayOfWeek: Int?  // nil = any day
    let score: Double    // 0-1, productivity score
    let reason: String
}

/// Habit recommendation.
struct HabitRecommendation: Codable, Equatable {
    let category: String
    let message: String
    let priority: Int  // 1=high, 2=medium, 3=low

    static func == (lhs: HabitRecommendation, rhs: HabitRecommendation) -> Bool {
        lhs.category == rhs.category && lhs.message == rhs.message && lhs.priority == rhs.priority
    }
}

/// Complete reading profile.
struct ReadingProfile: Codable {
    let generatedAt: Date
    let totalEvents: Int
    let totalMinutes: Double
    let totalArticles: Int
    let dateRange: (start: Date, end: Date)?
    let timeSlotDistribution: [TimeSlotStats]
    let dayOfWeekDistribution: [DayOfWeekStats]
    let sessionCategoryBreakdown: [String: Int]
    let consistencyScore: Double       // 0-1
    let weekdayVsWeekendRatio: Double  // >1 means more weekday reading
    let optimalWindows: [ReadingWindow]
    let recommendations: [HabitRecommendation]
    let readerType: String

    // Custom coding for tuple
    enum CodingKeys: String, CodingKey {
        case generatedAt, totalEvents, totalMinutes, totalArticles
        case dateRangeStart, dateRangeEnd
        case timeSlotDistribution, dayOfWeekDistribution
        case sessionCategoryBreakdown, consistencyScore
        case weekdayVsWeekendRatio, optimalWindows
        case recommendations, readerType
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(generatedAt, forKey: .generatedAt)
        try c.encode(totalEvents, forKey: .totalEvents)
        try c.encode(totalMinutes, forKey: .totalMinutes)
        try c.encode(totalArticles, forKey: .totalArticles)
        try c.encodeIfPresent(dateRange?.start, forKey: .dateRangeStart)
        try c.encodeIfPresent(dateRange?.end, forKey: .dateRangeEnd)
        try c.encode(timeSlotDistribution, forKey: .timeSlotDistribution)
        try c.encode(dayOfWeekDistribution, forKey: .dayOfWeekDistribution)
        try c.encode(sessionCategoryBreakdown, forKey: .sessionCategoryBreakdown)
        try c.encode(consistencyScore, forKey: .consistencyScore)
        try c.encode(weekdayVsWeekendRatio, forKey: .weekdayVsWeekendRatio)
        try c.encode(optimalWindows, forKey: .optimalWindows)
        try c.encode(recommendations, forKey: .recommendations)
        try c.encode(readerType, forKey: .readerType)
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        generatedAt = try c.decode(Date.self, forKey: .generatedAt)
        totalEvents = try c.decode(Int.self, forKey: .totalEvents)
        totalMinutes = try c.decode(Double.self, forKey: .totalMinutes)
        totalArticles = try c.decode(Int.self, forKey: .totalArticles)
        let start = try c.decodeIfPresent(Date.self, forKey: .dateRangeStart)
        let end = try c.decodeIfPresent(Date.self, forKey: .dateRangeEnd)
        dateRange = (start != nil && end != nil) ? (start!, end!) : nil
        timeSlotDistribution = try c.decode([TimeSlotStats].self, forKey: .timeSlotDistribution)
        dayOfWeekDistribution = try c.decode([DayOfWeekStats].self, forKey: .dayOfWeekDistribution)
        sessionCategoryBreakdown = try c.decode([String: Int].self, forKey: .sessionCategoryBreakdown)
        consistencyScore = try c.decode(Double.self, forKey: .consistencyScore)
        weekdayVsWeekendRatio = try c.decode(Double.self, forKey: .weekdayVsWeekendRatio)
        optimalWindows = try c.decode([ReadingWindow].self, forKey: .optimalWindows)
        recommendations = try c.decode([HabitRecommendation].self, forKey: .recommendations)
        readerType = try c.decode(String.self, forKey: .readerType)
    }

    init(generatedAt: Date, totalEvents: Int, totalMinutes: Double,
         totalArticles: Int, dateRange: (start: Date, end: Date)?,
         timeSlotDistribution: [TimeSlotStats],
         dayOfWeekDistribution: [DayOfWeekStats],
         sessionCategoryBreakdown: [String: Int],
         consistencyScore: Double,
         weekdayVsWeekendRatio: Double,
         optimalWindows: [ReadingWindow],
         recommendations: [HabitRecommendation],
         readerType: String) {
        self.generatedAt = generatedAt
        self.totalEvents = totalEvents
        self.totalMinutes = totalMinutes
        self.totalArticles = totalArticles
        self.dateRange = dateRange
        self.timeSlotDistribution = timeSlotDistribution
        self.dayOfWeekDistribution = dayOfWeekDistribution
        self.sessionCategoryBreakdown = sessionCategoryBreakdown
        self.consistencyScore = consistencyScore
        self.weekdayVsWeekendRatio = weekdayVsWeekendRatio
        self.optimalWindows = optimalWindows
        self.recommendations = recommendations
        self.readerType = readerType
    }
}

// MARK: - ReadingHabitsProfiler

class ReadingHabitsProfiler {

    // MARK: - Constants

    static let maxEvents = 5000
    private static let storageKey = "ReadingHabitsProfiler.events"

    // MARK: - Properties

    private var events: [ReadingEvent]
    private var cachedProfile: ReadingProfile?

    // MARK: - Initialization

    init(events: [ReadingEvent] = []) {
        self.events = Array(events.prefix(ReadingHabitsProfiler.maxEvents))
    }

    // MARK: - Event Recording

    /// Record a reading event.
    @discardableResult
    func recordEvent(date: Date,
                     durationMinutes: Double,
                     articlesRead: Int,
                     feedName: String,
                     topic: String? = nil) -> ReadingEvent? {
        guard durationMinutes > 0, articlesRead > 0 else { return nil }
        guard events.count < ReadingHabitsProfiler.maxEvents else { return nil }

        let event = ReadingEvent(
            date: date,
            durationMinutes: durationMinutes,
            articlesRead: articlesRead,
            feedName: feedName,
            topic: topic
        )
        events.append(event)
        cachedProfile = nil
        return event
    }

    /// Get all events.
    func allEvents() -> [ReadingEvent] {
        return events
    }

    /// Get events within a date range.
    func events(from start: Date, to end: Date) -> [ReadingEvent] {
        return events.filter { $0.date >= start && $0.date <= end }
    }

    /// Remove all events.
    func clearEvents() {
        events.removeAll()
        cachedProfile = nil
    }

    /// Number of recorded events.
    var eventCount: Int { events.count }

    // MARK: - Profile Generation

    /// Generate a complete reading habits profile.
    func generateProfile() -> ReadingProfile {
        if let cached = cachedProfile { return cached }

        let profile = ReadingProfile(
            generatedAt: Date(),
            totalEvents: events.count,
            totalMinutes: events.reduce(0) { $0 + $1.durationMinutes },
            totalArticles: events.reduce(0) { $0 + $1.articlesRead },
            dateRange: computeDateRange(),
            timeSlotDistribution: computeTimeSlotDistribution(),
            dayOfWeekDistribution: computeDayOfWeekDistribution(),
            sessionCategoryBreakdown: computeSessionCategories(),
            consistencyScore: computeConsistencyScore(),
            weekdayVsWeekendRatio: computeWeekdayWeekendRatio(),
            optimalWindows: computeOptimalWindows(),
            recommendations: generateRecommendations(),
            readerType: classifyReaderType()
        )
        cachedProfile = profile
        return profile
    }

    // MARK: - Time Slot Analysis

    /// Compute per-time-slot statistics.
    func computeTimeSlotDistribution() -> [TimeSlotStats] {
        var stats: [TimeSlot: TimeSlotStats] = [:]
        for slot in TimeSlot.allCases {
            stats[slot] = TimeSlotStats(slot: slot)
        }

        for event in events {
            stats[event.timeSlot]?.eventCount += 1
            stats[event.timeSlot]?.totalMinutes += event.durationMinutes
            stats[event.timeSlot]?.totalArticles += event.articlesRead
            if let topic = event.topic, !topic.isEmpty {
                stats[event.timeSlot]?.topics[topic, default: 0] += 1
            }
        }

        return TimeSlot.allCases.compactMap { stats[$0] }
    }

    /// Get the peak reading time slot.
    func peakTimeSlot() -> TimeSlot? {
        let dist = computeTimeSlotDistribution()
        return dist.max(by: { $0.totalMinutes < $1.totalMinutes })?.slot
    }

    // MARK: - Day of Week Analysis

    /// Compute per-day-of-week statistics.
    func computeDayOfWeekDistribution() -> [DayOfWeekStats] {
        var stats: [Int: DayOfWeekStats] = [:]
        for day in 1...7 {
            stats[day] = DayOfWeekStats(dayOfWeek: day)
        }

        for event in events {
            stats[event.dayOfWeek]?.eventCount += 1
            stats[event.dayOfWeek]?.totalMinutes += event.durationMinutes
            stats[event.dayOfWeek]?.totalArticles += event.articlesRead
        }

        return (1...7).compactMap { stats[$0] }
    }

    /// Get the most active day of the week.
    func peakDayOfWeek() -> Int? {
        let dist = computeDayOfWeekDistribution()
        return dist.max(by: { $0.totalMinutes < $1.totalMinutes })?.dayOfWeek
    }

    /// Compute weekday vs weekend reading ratio.
    func computeWeekdayWeekendRatio() -> Double {
        let dayStats = computeDayOfWeekDistribution()
        let weekdayMinutes = dayStats.filter { !$0.isWeekend }.reduce(0.0) { $0 + $1.totalMinutes }
        let weekendMinutes = dayStats.filter { $0.isWeekend }.reduce(0.0) { $0 + $1.totalMinutes }

        guard weekendMinutes > 0 else {
            return weekdayMinutes > 0 ? Double.infinity : 0
        }
        // Normalize: 5 weekdays vs 2 weekend days
        let weekdayAvg = weekdayMinutes / 5.0
        let weekendAvg = weekendMinutes / 2.0
        return weekendAvg > 0 ? weekdayAvg / weekendAvg : 0
    }

    // MARK: - Session Categories

    /// Categorize sessions by duration.
    func computeSessionCategories() -> [String: Int] {
        var counts: [String: Int] = [:]
        for cat in SessionCategory.allCases {
            counts[cat.rawValue] = 0
        }

        for event in events {
            let category = SessionCategory.from(minutes: event.durationMinutes)
            counts[category.rawValue, default: 0] += 1
        }

        return counts
    }

    // MARK: - Consistency

    /// Compute reading consistency (0-1).
    /// Measures how regularly the user reads across the week.
    func computeConsistencyScore() -> Double {
        guard events.count >= 3 else { return 0 }

        let calendar = Calendar.current

        // Group events by date (day granularity)
        var daySet = Set<String>()
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"

        var minDate = events[0].date
        var maxDate = events[0].date

        for event in events {
            daySet.insert(formatter.string(from: event.date))
            if event.date < minDate { minDate = event.date }
            if event.date > maxDate { maxDate = event.date }
        }

        let totalDays = max(1, calendar.dateComponents([.day], from: minDate, to: maxDate).day ?? 1)
        let activeDays = daySet.count

        // Consistency = fraction of days with reading activity
        let rawScore = Double(activeDays) / Double(totalDays)
        return min(1.0, max(0.0, rawScore))
    }

    // MARK: - Optimal Windows

    /// Find the best reading windows based on articles-per-minute efficiency.
    func computeOptimalWindows() -> [ReadingWindow] {
        let slotStats = computeTimeSlotDistribution()
        var windows: [ReadingWindow] = []

        for stats in slotStats {
            guard stats.totalMinutes > 0, stats.eventCount >= 2 else { continue }

            let efficiency = Double(stats.totalArticles) / stats.totalMinutes
            let maxEfficiency = slotStats.compactMap { s -> Double? in
                guard s.totalMinutes > 0 else { return nil }
                return Double(s.totalArticles) / s.totalMinutes
            }.max() ?? 1.0

            let score = maxEfficiency > 0 ? efficiency / maxEfficiency : 0

            if score >= 0.5 {
                let reason: String
                if score >= 0.9 {
                    reason = "Your peak productivity — \(String(format: "%.1f", stats.averageArticles)) articles per session"
                } else if score >= 0.7 {
                    reason = "Strong reading time — good focus and throughput"
                } else {
                    reason = "Decent reading window — \(String(format: "%.0f", stats.averageMinutes)) min avg sessions"
                }

                windows.append(ReadingWindow(
                    timeSlot: stats.slot,
                    dayOfWeek: nil,
                    score: min(1.0, score),
                    reason: reason
                ))
            }
        }

        return windows.sorted { $0.score > $1.score }
    }

    // MARK: - Reader Type Classification

    /// Classify the user's reader type based on behavior patterns.
    func classifyReaderType() -> String {
        guard !events.isEmpty else { return "Newcomer" }

        let totalMinutes = events.reduce(0.0) { $0 + $1.durationMinutes }
        let avgDuration = totalMinutes / Double(events.count)
        let categories = computeSessionCategories()
        let consistency = computeConsistencyScore()

        let marathonCount = categories[SessionCategory.marathon.rawValue] ?? 0
        let deepCount = categories[SessionCategory.deepRead.rawValue] ?? 0
        let quickCount = categories[SessionCategory.quickScan.rawValue] ?? 0

        let deepRatio = Double(marathonCount + deepCount) / Double(events.count)
        let quickRatio = Double(quickCount) / Double(events.count)

        if consistency > 0.7 && avgDuration > 20 {
            return "Dedicated Scholar"
        } else if deepRatio > 0.5 {
            return "Deep Diver"
        } else if quickRatio > 0.6 {
            return "Speed Scanner"
        } else if consistency > 0.5 {
            return "Steady Reader"
        } else if events.count > 50 && consistency < 0.3 {
            return "Binge Reader"
        } else if avgDuration > 30 {
            return "Deep Thinker"
        } else {
            return "Explorer"
        }
    }

    // MARK: - Recommendations

    /// Generate actionable reading habit recommendations.
    func generateRecommendations() -> [HabitRecommendation] {
        guard events.count >= 3 else {
            return [HabitRecommendation(
                category: "Getting Started",
                message: "Keep reading! You need at least a few more sessions for meaningful habit analysis.",
                priority: 3
            )]
        }

        var recs: [HabitRecommendation] = []

        // Consistency check
        let consistency = computeConsistencyScore()
        if consistency < 0.3 {
            recs.append(HabitRecommendation(
                category: "Consistency",
                message: "Your reading is sporadic. Try setting a daily reading reminder — even 10 minutes helps build the habit.",
                priority: 1
            ))
        } else if consistency > 0.7 {
            recs.append(HabitRecommendation(
                category: "Consistency",
                message: "Great consistency! You read regularly. Consider increasing session depth for more retention.",
                priority: 3
            ))
        }

        // Session length balance
        let categories = computeSessionCategories()
        let quickCount = categories[SessionCategory.quickScan.rawValue] ?? 0
        let deepCount = (categories[SessionCategory.deepRead.rawValue] ?? 0) +
                        (categories[SessionCategory.marathon.rawValue] ?? 0)

        if Double(quickCount) / Double(events.count) > 0.7 {
            recs.append(HabitRecommendation(
                category: "Depth",
                message: "Most of your sessions are quick scans. Try allocating one 20-minute deep reading block per day.",
                priority: 2
            ))
        }

        if Double(deepCount) / Double(events.count) > 0.7 {
            recs.append(HabitRecommendation(
                category: "Balance",
                message: "You favor long sessions. Consider shorter check-ins during the day to catch breaking stories.",
                priority: 3
            ))
        }

        // Time distribution
        let slotStats = computeTimeSlotDistribution()
        let lateNight = slotStats.first { $0.slot == .lateNight }
        if let late = lateNight, late.eventCount > 0,
           Double(late.eventCount) / Double(events.count) > 0.3 {
            recs.append(HabitRecommendation(
                category: "Timing",
                message: "You read a lot late at night (1-5am). Consider shifting to morning reading for better retention.",
                priority: 1
            ))
        }

        // Weekday/weekend balance
        let ratio = computeWeekdayWeekendRatio()
        if ratio > 3.0 {
            recs.append(HabitRecommendation(
                category: "Balance",
                message: "You read mostly on weekdays. Weekends are great for longer, exploratory reading sessions.",
                priority: 3
            ))
        } else if ratio < 0.3 && ratio > 0 {
            recs.append(HabitRecommendation(
                category: "Balance",
                message: "Most reading happens on weekends. Try quick weekday sessions to stay current with daily feeds.",
                priority: 2
            ))
        }

        // Topic diversity
        let uniqueTopics = Set(events.compactMap { $0.topic }).count
        if uniqueTopics == 1 && events.count > 10 {
            recs.append(HabitRecommendation(
                category: "Diversity",
                message: "You're focused on a single topic. Consider exploring related topics for broader perspective.",
                priority: 2
            ))
        }

        // Optimal window suggestion
        let windows = computeOptimalWindows()
        if let best = windows.first {
            recs.append(HabitRecommendation(
                category: "Optimization",
                message: "Your most productive reading time is \(best.timeSlot.label). Schedule important reads there.",
                priority: 2
            ))
        }

        return recs.sorted { $0.priority < $1.priority }
    }

    // MARK: - Export

    /// Export profile as JSON string.
    func exportProfileJSON() -> String? {
        let profile = generateProfile()
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(profile) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    /// Export events as JSON string.
    func exportEventsJSON() -> String? {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(events) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    // MARK: - Summary

    /// Generate a human-readable profile summary.
    func profileSummary() -> String {
        let profile = generateProfile()
        var lines: [String] = []

        lines.append("📊 Reading Habits Profile")
        lines.append("═══════════════════════════")
        lines.append("")
        lines.append("Reader Type: \(profile.readerType)")
        lines.append("Total Sessions: \(profile.totalEvents)")
        lines.append("Total Reading Time: \(String(format: "%.0f", profile.totalMinutes)) minutes")
        lines.append("Articles Read: \(profile.totalArticles)")
        lines.append("Consistency: \(String(format: "%.0f", profile.consistencyScore * 100))%")
        lines.append("")

        // Peak time
        if let peak = peakTimeSlot() {
            lines.append("⏰ Peak Reading Time: \(peak.label)")
        }

        // Peak day
        if let peakDay = peakDayOfWeek() {
            let dayStats = computeDayOfWeekDistribution()
            if let stat = dayStats.first(where: { $0.dayOfWeek == peakDay }) {
                lines.append("📅 Most Active Day: \(stat.dayName)")
            }
        }

        lines.append("")

        // Recommendations
        if !profile.recommendations.isEmpty {
            lines.append("💡 Recommendations:")
            for rec in profile.recommendations.prefix(5) {
                let priority = rec.priority == 1 ? "❗" : rec.priority == 2 ? "💭" : "✨"
                lines.append("  \(priority) [\(rec.category)] \(rec.message)")
            }
        }

        return lines.joined(separator: "\n")
    }

    // MARK: - Private Helpers

    private func computeDateRange() -> (start: Date, end: Date)? {
        guard let first = events.min(by: { $0.date < $1.date }),
              let last = events.max(by: { $0.date < $1.date }) else {
            return nil
        }
        return (first.date, last.date)
    }
}
