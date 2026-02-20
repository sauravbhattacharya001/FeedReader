//
//  ReadingStatsManager.swift
//  FeedReader
//
//  Tracks reading activity with timestamps for analytics.
//  Records when stories are read to compute streaks, averages,
//  hourly patterns, and per-feed breakdowns.
//

import Foundation

/// Notification posted when reading stats change.
extension Notification.Name {
    static let readingStatsDidChange = Notification.Name("ReadingStatsDidChangeNotification")
}

class ReadingStatsManager {
    
    // MARK: - Singleton
    
    static let shared = ReadingStatsManager()
    
    // MARK: - Types
    
    /// A single reading event recording when a story was read.
    struct ReadEvent: Codable {
        let link: String
        let title: String
        let feedName: String
        let timestamp: Date
    }
    
    /// Summary statistics computed from reading events.
    struct ReadingStats {
        let totalStoriesRead: Int
        let readToday: Int
        let readThisWeek: Int
        let readThisMonth: Int
        let dailyAverage: Double
        let currentStreak: Int
        let longestStreak: Int
        let mostActiveHour: Int?
        let hourlyDistribution: [Int: Int]  // hour (0-23) → count
        let feedBreakdown: [(name: String, count: Int)]  // sorted by count desc
        let totalBookmarks: Int
        let firstReadDate: Date?
        let daysTracking: Int
    }
    
    // MARK: - Properties
    
    /// All recorded reading events, ordered by timestamp (newest first).
    private(set) var events: [ReadEvent] = []
    
    /// UserDefaults key for persisting reading events.
    private static let userDefaultsKey = "ReadingStatsManager.events"
    
    /// Maximum number of events to store (prevents unbounded growth).
    static let maxStoredEvents = 10000
    
    // MARK: - Initialization
    
    private init() {
        loadEvents()
    }
    
    // MARK: - Public Methods
    
    /// Record a reading event for a story.
    /// - Parameters:
    ///   - story: The story that was read.
    ///   - feedName: Optional feed name for per-feed breakdown.
    func recordRead(story: Story, feedName: String = "Unknown") {
        let event = ReadEvent(
            link: story.link,
            title: story.title,
            feedName: feedName,
            timestamp: Date()
        )
        events.insert(event, at: 0) // newest first
        pruneIfNeeded()
        save()
        NotificationCenter.default.post(name: .readingStatsDidChange, object: nil)
    }
    
    /// Record a reading event with explicit parameters (for testing).
    func recordEvent(link: String, title: String, feedName: String, timestamp: Date) {
        let event = ReadEvent(
            link: link,
            title: title,
            feedName: feedName,
            timestamp: timestamp
        )
        events.insert(event, at: 0)
        pruneIfNeeded()
        save()
        NotificationCenter.default.post(name: .readingStatsDidChange, object: nil)
    }
    
    /// Compute current reading statistics.
    func computeStats() -> ReadingStats {
        let calendar = Calendar.current
        let now = Date()
        let startOfToday = calendar.startOfDay(for: now)
        
        // Stories read today
        let readToday = events.filter { $0.timestamp >= startOfToday }.count
        
        // Stories read this week (last 7 days)
        let weekAgo = calendar.date(byAdding: .day, value: -7, to: startOfToday)!
        let readThisWeek = events.filter { $0.timestamp >= weekAgo }.count
        
        // Stories read this month (last 30 days)
        let monthAgo = calendar.date(byAdding: .day, value: -30, to: startOfToday)!
        let readThisMonth = events.filter { $0.timestamp >= monthAgo }.count
        
        // Daily average
        let daysTracking = computeDaysTracking(calendar: calendar, now: now)
        let dailyAverage = daysTracking > 0 ? Double(events.count) / Double(daysTracking) : 0
        
        // Streaks
        let (currentStreak, longestStreak) = computeStreaks(calendar: calendar, now: now)
        
        // Hourly distribution
        var hourlyDist: [Int: Int] = [:]
        for event in events {
            let hour = calendar.component(.hour, from: event.timestamp)
            hourlyDist[hour, default: 0] += 1
        }
        let mostActiveHour = hourlyDist.max(by: { $0.value < $1.value })?.key
        
        // Feed breakdown
        var feedCounts: [String: Int] = [:]
        for event in events {
            feedCounts[event.feedName, default: 0] += 1
        }
        let feedBreakdown = feedCounts
            .map { (name: $0.key, count: $0.value) }
            .sorted { $0.count > $1.count }
        
        // Bookmark count
        let totalBookmarks = BookmarkManager.shared.count
        
        // First read date
        let firstReadDate = events.last?.timestamp
        
        return ReadingStats(
            totalStoriesRead: events.count,
            readToday: readToday,
            readThisWeek: readThisWeek,
            readThisMonth: readThisMonth,
            dailyAverage: dailyAverage,
            currentStreak: currentStreak,
            longestStreak: longestStreak,
            mostActiveHour: mostActiveHour,
            hourlyDistribution: hourlyDist,
            feedBreakdown: feedBreakdown,
            totalBookmarks: totalBookmarks,
            firstReadDate: firstReadDate,
            daysTracking: daysTracking
        )
    }
    
    /// Total number of recorded events.
    var eventCount: Int {
        return events.count
    }
    
    /// Clear all reading stats.
    func clearAll() {
        events.removeAll()
        save()
        NotificationCenter.default.post(name: .readingStatsDidChange, object: nil)
    }
    
    /// Force reload from storage (useful for testing).
    func reload() {
        loadEvents()
    }
    
    // MARK: - Private Methods
    
    /// Compute number of days since first event (minimum 1).
    private func computeDaysTracking(calendar: Calendar, now: Date) -> Int {
        guard let firstDate = events.last?.timestamp else { return 0 }
        let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: firstDate), to: calendar.startOfDay(for: now)).day ?? 0
        return max(days + 1, 1)
    }
    
    /// Compute current and longest reading streaks.
    /// A streak is the number of consecutive days with at least one story read.
    private func computeStreaks(calendar: Calendar, now: Date) -> (current: Int, longest: Int) {
        guard !events.isEmpty else { return (0, 0) }
        
        // Get unique days with reading activity (sorted descending)
        var activeDays = Set<Date>()
        for event in events {
            activeDays.insert(calendar.startOfDay(for: event.timestamp))
        }
        let sortedDays = activeDays.sorted(by: >)
        
        guard !sortedDays.isEmpty else { return (0, 0) }
        
        // Current streak: count consecutive days from today/yesterday backward
        let today = calendar.startOfDay(for: now)
        let yesterday = calendar.date(byAdding: .day, value: -1, to: today)!
        
        var currentStreak = 0
        if sortedDays[0] == today || sortedDays[0] == yesterday {
            currentStreak = 1
            var prevDay = sortedDays[0]
            for i in 1..<sortedDays.count {
                let expectedPrev = calendar.date(byAdding: .day, value: -1, to: prevDay)!
                if sortedDays[i] == expectedPrev {
                    currentStreak += 1
                    prevDay = sortedDays[i]
                } else {
                    break
                }
            }
        }
        
        // Longest streak: find max consecutive run in all sorted days
        var longestStreak = 1
        var streak = 1
        let ascending = sortedDays.reversed() as [Date]
        for i in 1..<ascending.count {
            let expected = calendar.date(byAdding: .day, value: 1, to: ascending[i-1])!
            if ascending[i] == expected {
                streak += 1
                longestStreak = max(longestStreak, streak)
            } else {
                streak = 1
            }
        }
        longestStreak = max(longestStreak, currentStreak)
        
        return (currentStreak, longestStreak)
    }
    
    // MARK: - Persistence
    
    private func save() {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        if let data = try? encoder.encode(events) {
            UserDefaults.standard.set(data, forKey: ReadingStatsManager.userDefaultsKey)
        }
    }
    
    private func loadEvents() {
        guard let data = UserDefaults.standard.data(forKey: ReadingStatsManager.userDefaultsKey) else {
            events = []
            return
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        if let loaded = try? decoder.decode([ReadEvent].self, from: data) {
            events = loaded
        } else {
            events = []
        }
    }
    
    /// Prune oldest events if we exceed the max.
    private func pruneIfNeeded() {
        if events.count > ReadingStatsManager.maxStoredEvents {
            events = Array(events.prefix(ReadingStatsManager.maxStoredEvents))
        }
    }
}
