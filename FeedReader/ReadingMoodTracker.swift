//
//  ReadingMoodTracker.swift
//  FeedReader
//
//  Tracks user mood before and after reading sessions, correlates moods
//  with feeds/categories, and suggests articles based on current mood.
//
//  Key features:
//  - Log mood (emoji + optional note) before/after reading
//  - Mood history with date filtering
//  - Mood-to-feed/category correlation analysis
//  - "Read to feel better" suggestions based on positive mood shifts
//  - Mood streaks and patterns (time-of-day, day-of-week)
//  - Mood impact score per feed (does this feed improve or worsen mood?)
//  - Export mood journal as JSON or CSV
//
//  Persistence: JSON file in Documents directory.
//

import Foundation

// MARK: - Notifications

extension Notification.Name {
    /// Posted when a mood entry is logged.
    static let readingMoodDidChange = Notification.Name("ReadingMoodDidChangeNotification")
}

// MARK: - Mood Model

/// Represents a user's mood on a simple scale with emoji.
enum MoodLevel: Int, Codable, CaseIterable, Comparable {
    case terrible = 1
    case bad = 2
    case neutral = 3
    case good = 4
    case great = 5

    var emoji: String {
        switch self {
        case .terrible: return "😢"
        case .bad: return "😕"
        case .neutral: return "😐"
        case .good: return "🙂"
        case .great: return "😄"
        }
    }

    var label: String {
        switch self {
        case .terrible: return "Terrible"
        case .bad: return "Bad"
        case .neutral: return "Neutral"
        case .good: return "Good"
        case .great: return "Great"
        }
    }

    static func < (lhs: MoodLevel, rhs: MoodLevel) -> Bool {
        return lhs.rawValue < rhs.rawValue
    }
}

/// A single mood entry tied to a reading session.
struct MoodEntry: Codable, Identifiable {
    let id: String
    let date: Date
    let mood: MoodLevel
    let note: String?
    let phase: MoodPhase
    let sessionId: String?
    let feedURL: String?
    let feedTitle: String?
    let category: String?
    let articleTitle: String?

    enum MoodPhase: String, Codable {
        case before = "before"
        case after = "after"
        case standalone = "standalone"
    }
}

/// Mood shift for a reading session (before → after).
struct MoodShift: Codable {
    let sessionId: String
    let before: MoodLevel
    let after: MoodLevel
    let feedURL: String?
    let feedTitle: String?
    let category: String?
    let date: Date

    var delta: Int { after.rawValue - before.rawValue }
    var improved: Bool { delta > 0 }
    var worsened: Bool { delta < 0 }
    var unchanged: Bool { delta == 0 }
}

/// Per-feed mood impact analysis.
struct FeedMoodImpact {
    let feedURL: String
    let feedTitle: String
    let sessionCount: Int
    let averageDelta: Double
    let improvedCount: Int
    let worsenedCount: Int
    let unchangedCount: Int

    var impactLabel: String {
        if averageDelta > 0.3 { return "😄 Mood Booster" }
        if averageDelta < -0.3 { return "😕 Mood Drainer" }
        return "😐 Neutral"
    }
}

/// Mood pattern by time of day.
struct MoodTimePattern {
    let hour: Int
    let averageMood: Double
    let entryCount: Int

    var timeLabel: String {
        switch hour {
        case 5..<12: return "Morning"
        case 12..<17: return "Afternoon"
        case 17..<21: return "Evening"
        default: return "Night"
        }
    }
}

/// Day-of-week mood pattern.
struct MoodDayPattern {
    let weekday: Int  // 1=Sunday, 7=Saturday
    let averageMood: Double
    let entryCount: Int

    var dayLabel: String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US")
        return formatter.weekdaySymbols[weekday - 1]
    }
}

/// Mood journal export data.
struct MoodJournalExport: Codable {
    let exportDate: Date
    let totalEntries: Int
    let entries: [MoodEntry]
}

// MARK: - ReadingMoodTracker

/// Tracks reading mood, analyzes patterns, and suggests mood-improving articles.
final class ReadingMoodTracker {

    static let shared = ReadingMoodTracker()

    private var entries: [MoodEntry] = []
    private let storageURL: URL
    private let calendar = Calendar.current

    private init() {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        storageURL = docs.appendingPathComponent("reading_mood_tracker.json")
        loadEntries()
    }

    // MARK: - Logging

    /// Log a mood entry.
    @discardableResult
    func logMood(
        mood: MoodLevel,
        phase: MoodEntry.MoodPhase = .standalone,
        note: String? = nil,
        sessionId: String? = nil,
        feedURL: String? = nil,
        feedTitle: String? = nil,
        category: String? = nil,
        articleTitle: String? = nil
    ) -> MoodEntry {
        let entry = MoodEntry(
            id: UUID().uuidString,
            date: Date(),
            mood: mood,
            note: note,
            phase: phase,
            sessionId: sessionId,
            feedURL: feedURL,
            feedTitle: feedTitle,
            category: category,
            articleTitle: articleTitle
        )
        entries.append(entry)
        saveEntries()
        NotificationCenter.default.post(name: .readingMoodDidChange, object: entry)
        return entry
    }

    /// Remove a mood entry by ID.
    func removeEntry(id: String) -> Bool {
        guard let idx = entries.firstIndex(where: { $0.id == id }) else { return false }
        entries.remove(at: idx)
        saveEntries()
        return true
    }

    // MARK: - Queries

    /// All entries, optionally filtered by date range.
    func getEntries(from startDate: Date? = nil, to endDate: Date? = nil) -> [MoodEntry] {
        var result = entries
        if let start = startDate {
            result = result.filter { $0.date >= start }
        }
        if let end = endDate {
            result = result.filter { $0.date <= end }
        }
        return result.sorted { $0.date > $1.date }
    }

    /// Get entries for today.
    func todayEntries() -> [MoodEntry] {
        let start = calendar.startOfDay(for: Date())
        let end = calendar.date(byAdding: .day, value: 1, to: start)!
        return getEntries(from: start, to: end)
    }

    /// Get the most recent mood entry.
    func currentMood() -> MoodEntry? {
        return entries.max(by: { $0.date < $1.date })
    }

    /// Average mood over a date range (or all time).
    func averageMood(from startDate: Date? = nil, to endDate: Date? = nil) -> Double? {
        let filtered = getEntries(from: startDate, to: endDate)
        guard !filtered.isEmpty else { return nil }
        let sum = filtered.reduce(0) { $0 + $1.mood.rawValue }
        return Double(sum) / Double(filtered.count)
    }

    // MARK: - Mood Shifts

    /// Compute mood shifts for sessions that have both before and after entries.
    func moodShifts() -> [MoodShift] {
        let sessions = Dictionary(grouping: entries.filter { $0.sessionId != nil }, by: { $0.sessionId! })
        var shifts: [MoodShift] = []

        for (sessionId, sessionEntries) in sessions {
            guard let before = sessionEntries.first(where: { $0.phase == .before }),
                  let after = sessionEntries.first(where: { $0.phase == .after }) else { continue }

            shifts.append(MoodShift(
                sessionId: sessionId,
                before: before.mood,
                after: after.mood,
                feedURL: before.feedURL ?? after.feedURL,
                feedTitle: before.feedTitle ?? after.feedTitle,
                category: before.category ?? after.category,
                date: before.date
            ))
        }

        return shifts.sorted { $0.date > $1.date }
    }

    // MARK: - Feed Impact Analysis

    /// Analyze mood impact per feed.
    func feedMoodImpact() -> [FeedMoodImpact] {
        let shifts = moodShifts()
        let byFeed = Dictionary(grouping: shifts.filter { $0.feedURL != nil }, by: { $0.feedURL! })

        return byFeed.map { (url, feedShifts) in
            let avgDelta = feedShifts.isEmpty ? 0.0 : Double(feedShifts.reduce(0) { $0 + $1.delta }) / Double(feedShifts.count)
            return FeedMoodImpact(
                feedURL: url,
                feedTitle: feedShifts.first?.feedTitle ?? url,
                sessionCount: feedShifts.count,
                averageDelta: avgDelta,
                improvedCount: feedShifts.filter { $0.improved }.count,
                worsenedCount: feedShifts.filter { $0.worsened }.count,
                unchangedCount: feedShifts.filter { $0.unchanged }.count
            )
        }.sorted { $0.averageDelta > $1.averageDelta }
    }

    /// Get feeds that tend to improve mood (mood boosters).
    func moodBoosterFeeds(minSessions: Int = 2) -> [FeedMoodImpact] {
        return feedMoodImpact().filter { $0.sessionCount >= minSessions && $0.averageDelta > 0 }
    }

    /// Get feeds that tend to worsen mood (mood drainers).
    func moodDrainerFeeds(minSessions: Int = 2) -> [FeedMoodImpact] {
        return feedMoodImpact().filter { $0.sessionCount >= minSessions && $0.averageDelta < 0 }
    }

    // MARK: - Mood Suggestions

    /// Suggest feed URLs to read based on current mood. If mood is low, suggest mood boosters.
    func suggestFeedsForMood(_ mood: MoodLevel) -> [String] {
        let boosters = moodBoosterFeeds()
        switch mood {
        case .terrible, .bad:
            // Strongly recommend mood boosters
            return boosters.prefix(5).map { $0.feedURL }
        case .neutral:
            // Mix of boosters and neutral
            return boosters.prefix(3).map { $0.feedURL }
        case .good, .great:
            // Any feed is fine, but still highlight boosters
            return boosters.prefix(2).map { $0.feedURL }
        }
    }

    // MARK: - Patterns

    /// Mood patterns by hour of day.
    func moodByTimeOfDay() -> [MoodTimePattern] {
        let byHour = Dictionary(grouping: entries) { calendar.component(.hour, from: $0.date) }
        return byHour.map { (hour, hourEntries) in
            let avg = hourEntries.isEmpty ? 0.0 : Double(hourEntries.reduce(0) { $0 + $1.mood.rawValue }) / Double(hourEntries.count)
            return MoodTimePattern(hour: hour, averageMood: avg, entryCount: hourEntries.count)
        }.sorted { $0.hour < $1.hour }
    }

    /// Mood patterns by day of week.
    func moodByDayOfWeek() -> [MoodDayPattern] {
        let byDay = Dictionary(grouping: entries) { calendar.component(.weekday, from: $0.date) }
        return byDay.map { (day, dayEntries) in
            let avg = dayEntries.isEmpty ? 0.0 : Double(dayEntries.reduce(0) { $0 + $1.mood.rawValue }) / Double(dayEntries.count)
            return MoodDayPattern(weekday: day, averageMood: avg, entryCount: dayEntries.count)
        }.sorted { $0.weekday < $1.weekday }
    }

    /// Best time of day for reading (when mood is highest).
    func bestReadingTime() -> MoodTimePattern? {
        return moodByTimeOfDay().max(by: { $0.averageMood < $1.averageMood })
    }

    // MARK: - Streaks

    /// Count consecutive days with at least one mood entry.
    func currentMoodStreak() -> Int {
        let uniqueDays = Set(entries.map { calendar.startOfDay(for: $0.date) }).sorted(by: >)
        guard !uniqueDays.isEmpty else { return 0 }

        var streak = 0
        var expected = calendar.startOfDay(for: Date())

        for day in uniqueDays {
            if day == expected {
                streak += 1
                expected = calendar.date(byAdding: .day, value: -1, to: expected)!
            } else if day < expected {
                break
            }
        }
        return streak
    }

    // MARK: - Export

    /// Export mood journal as JSON data.
    func exportAsJSON() -> Data? {
        let export = MoodJournalExport(
            exportDate: Date(),
            totalEntries: entries.count,
            entries: entries.sorted { $0.date > $1.date }
        )
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try? encoder.encode(export)
    }

    /// Export mood journal as CSV string.
    func exportAsCSV() -> String {
        var csv = "id,date,mood_level,mood_emoji,mood_label,phase,note,feed_title,category,article_title\n"
        let formatter = ISO8601DateFormatter()

        for entry in entries.sorted(by: { $0.date > $1.date }) {
            let fields: [String] = [
                entry.id,
                formatter.string(from: entry.date),
                "\(entry.mood.rawValue)",
                entry.mood.emoji,
                entry.mood.label,
                entry.phase.rawValue,
                (entry.note ?? "").replacingOccurrences(of: ",", with: ";"),
                (entry.feedTitle ?? "").replacingOccurrences(of: ",", with: ";"),
                (entry.category ?? "").replacingOccurrences(of: ",", with: ";"),
                (entry.articleTitle ?? "").replacingOccurrences(of: ",", with: ";")
            ]
            csv += fields.joined(separator: ",") + "\n"
        }
        return csv
    }

    // MARK: - Summary

    /// Generate a mood summary report.
    func summary(days: Int = 30) -> String {
        let startDate = calendar.date(byAdding: .day, value: -days, to: Date())!
        let recent = getEntries(from: startDate)
        let shifts = moodShifts().filter { $0.date >= startDate }

        var report = "📊 Mood Summary (last \(days) days)\n"
        report += "─────────────────────────\n"
        report += "Total entries: \(recent.count)\n"

        if let avg = averageMood(from: startDate) {
            let avgMood = MoodLevel(rawValue: Int(avg.rounded())) ?? .neutral
            report += "Average mood: \(avgMood.emoji) \(String(format: "%.1f", avg))/5\n"
        }

        report += "Mood streak: \(currentMoodStreak()) days\n\n"

        if !shifts.isEmpty {
            let improved = shifts.filter { $0.improved }.count
            let total = shifts.count
            report += "Reading sessions with mood shift: \(total)\n"
            report += "  ↑ Improved: \(improved) (\(Int(Double(improved)/Double(total)*100))%)\n"
            report += "  ↓ Worsened: \(shifts.filter { $0.worsened }.count)\n"
            report += "  → Unchanged: \(shifts.filter { $0.unchanged }.count)\n\n"
        }

        let boosters = moodBoosterFeeds()
        if !boosters.isEmpty {
            report += "🌟 Top Mood Boosters:\n"
            for feed in boosters.prefix(3) {
                report += "  \(feed.feedTitle) (+\(String(format: "%.1f", feed.averageDelta)))\n"
            }
            report += "\n"
        }

        let drainers = moodDrainerFeeds()
        if !drainers.isEmpty {
            report += "⚠️ Mood Drainers:\n"
            for feed in drainers.prefix(3) {
                report += "  \(feed.feedTitle) (\(String(format: "%.1f", feed.averageDelta)))\n"
            }
        }

        return report
    }

    // MARK: - Persistence

    private func loadEntries() {
        guard FileManager.default.fileExists(atPath: storageURL.path),
              let data = try? Data(contentsOf: storageURL) else { return }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        entries = (try? decoder.decode([MoodEntry].self, from: data)) ?? []
    }

    private func saveEntries() {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        if let data = try? encoder.encode(entries) {
            try? data.write(to: storageURL)
        }
    }
}
