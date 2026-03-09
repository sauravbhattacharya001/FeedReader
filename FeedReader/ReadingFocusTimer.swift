//
//  ReadingFocusTimer.swift
//  FeedReader
//
//  Pomodoro-style focus timer for reading sessions. Helps users
//  maintain concentrated reading periods with structured breaks.
//
//  Features:
//  - Configurable focus/break durations (default: 25/5 min)
//  - Long break after N focus rounds (default: 4 rounds → 15 min break)
//  - Pause/resume support
//  - Distraction-free mode flag
//  - Per-session article tracking with reading pace (articles/hour)
//  - Session history with daily/weekly aggregates
//  - Streak tracking (consecutive days with ≥1 completed focus session)
//  - Customizable timer presets (Pomodoro, Deep Read, Sprint, Marathon)
//  - JSON export/import
//
//  Persistence: UserDefaults via Codable.
//

import Foundation

// MARK: - Notifications

extension Notification.Name {
    /// Posted when a focus period starts.
    static let focusTimerDidStart = Notification.Name("FocusTimerDidStartNotification")
    /// Posted when a focus period completes (not cancelled).
    static let focusTimerDidComplete = Notification.Name("FocusTimerDidCompleteNotification")
    /// Posted when a break starts.
    static let focusTimerBreakDidStart = Notification.Name("FocusTimerBreakDidStartNotification")
    /// Posted when a break ends.
    static let focusTimerBreakDidEnd = Notification.Name("FocusTimerBreakDidEndNotification")
    /// Posted when the timer is paused or resumed.
    static let focusTimerDidPause = Notification.Name("FocusTimerDidPauseNotification")
    /// Posted when a reading streak changes.
    static let focusTimerStreakDidChange = Notification.Name("FocusTimerStreakDidChangeNotification")
}

// MARK: - Timer Preset

/// Predefined timer configurations.
struct TimerPreset: Codable, Equatable {
    let name: String
    let focusMinutes: Int
    let shortBreakMinutes: Int
    let longBreakMinutes: Int
    let roundsBeforeLongBreak: Int

    /// Classic Pomodoro: 25 focus / 5 short / 15 long / 4 rounds.
    static let pomodoro = TimerPreset(
        name: "Pomodoro",
        focusMinutes: 25,
        shortBreakMinutes: 5,
        longBreakMinutes: 15,
        roundsBeforeLongBreak: 4
    )

    /// Deep reading: 50 focus / 10 short / 20 long / 3 rounds.
    static let deepRead = TimerPreset(
        name: "Deep Read",
        focusMinutes: 50,
        shortBreakMinutes: 10,
        longBreakMinutes: 20,
        roundsBeforeLongBreak: 3
    )

    /// Quick sprint: 15 focus / 3 short / 10 long / 6 rounds.
    static let sprint = TimerPreset(
        name: "Sprint",
        focusMinutes: 15,
        shortBreakMinutes: 3,
        longBreakMinutes: 10,
        roundsBeforeLongBreak: 6
    )

    /// Marathon: 90 focus / 15 short / 30 long / 2 rounds.
    static let marathon = TimerPreset(
        name: "Marathon",
        focusMinutes: 90,
        shortBreakMinutes: 15,
        longBreakMinutes: 30,
        roundsBeforeLongBreak: 2
    )

    /// All built-in presets.
    static let allPresets: [TimerPreset] = [.pomodoro, .deepRead, .sprint, .marathon]
}

// MARK: - Timer Phase

/// Current phase of the focus timer cycle.
enum TimerPhase: String, Codable, Equatable {
    case idle
    case focus
    case shortBreak
    case longBreak
    case paused
}

// MARK: - Focus Session Record

/// A completed focus session (one focus period).
struct FocusSessionRecord: Codable, Equatable {
    let id: String
    let startedAt: Date
    let endedAt: Date
    let durationSeconds: Int
    let targetDurationSeconds: Int
    let articlesRead: [FocusArticle]
    let preset: String
    let completed: Bool  // true if full duration, false if cancelled early
    let distractionFreeMode: Bool

    /// Reading pace: articles per hour.
    var articlesPerHour: Double {
        guard durationSeconds > 0 else { return 0 }
        let hours = Double(durationSeconds) / 3600.0
        return Double(articlesRead.count) / hours
    }

    /// Completion percentage (0-100).
    var completionPercent: Double {
        guard targetDurationSeconds > 0 else { return 0 }
        return min(100.0, Double(durationSeconds) / Double(targetDurationSeconds) * 100.0)
    }
}

/// An article read during a focus session.
struct FocusArticle: Codable, Equatable {
    let link: String
    let title: String
    let readAt: Date
}

// MARK: - Daily Summary

/// Summary of focus sessions for a single day.
struct DailyFocusSummary: Codable, Equatable {
    let date: Date
    let sessions: [FocusSessionRecord]

    /// Total focused time in seconds.
    var totalFocusSeconds: Int {
        sessions.reduce(0) { $0 + $1.durationSeconds }
    }

    /// Number of completed (full duration) sessions.
    /// Uses reduce instead of filter+count to avoid allocating a
    /// temporary array just for counting.
    var completedSessions: Int {
        sessions.reduce(0) { $0 + ($1.completed ? 1 : 0) }
    }

    /// Total articles read across all sessions.
    var totalArticles: Int {
        sessions.reduce(0) { $0 + $1.articlesRead.count }
    }

    /// Average reading pace across sessions.
    var averageArticlesPerHour: Double {
        let totalHours = Double(totalFocusSeconds) / 3600.0
        guard totalHours > 0 else { return 0 }
        return Double(totalArticles) / totalHours
    }

    /// Completion rate (% of sessions that ran full duration).
    var completionRate: Double {
        guard !sessions.isEmpty else { return 0 }
        return Double(completedSessions) / Double(sessions.count) * 100.0
    }
}

// MARK: - Streak Info

/// Information about the user's focus streak.
struct FocusStreak: Codable, Equatable {
    var currentStreak: Int
    var longestStreak: Int
    var lastActiveDate: Date?

    static let empty = FocusStreak(currentStreak: 0, longestStreak: 0, lastActiveDate: nil)
}

// MARK: - ReadingFocusTimer

/// Pomodoro-style focus timer for structured reading sessions.
class ReadingFocusTimer {

    // MARK: - Storage Keys

    private let sessionsKey = "ReadingFocusTimer.sessions"
    private let streakKey = "ReadingFocusTimer.streak"
    private let presetKey = "ReadingFocusTimer.activePreset"

    // MARK: - State

    private(set) var phase: TimerPhase = .idle
    private(set) var activePreset: TimerPreset
    private(set) var currentRound: Int = 0
    private(set) var distractionFreeMode: Bool = false
    private(set) var streak: FocusStreak

    private var focusStartTime: Date?
    private var pauseStartTime: Date?
    private var totalPausedSeconds: Int = 0
    private var currentArticles: [FocusArticle] = []
    private var sessions: [FocusSessionRecord] = []

    /// Whether the timer is actively running (focus or break phase).
    var isActive: Bool {
        phase == .focus || phase == .shortBreak || phase == .longBreak
    }

    /// Whether the timer is paused.
    var isPaused: Bool {
        phase == .paused
    }

    /// Elapsed focus seconds in the current session (excluding pauses).
    var elapsedFocusSeconds: Int {
        guard let start = focusStartTime else { return 0 }
        let now = Date()
        let total = Int(now.timeIntervalSince(start))
        return max(0, total - totalPausedSeconds)
    }

    /// Remaining seconds in the current focus period.
    var remainingFocusSeconds: Int {
        max(0, activePreset.focusMinutes * 60 - elapsedFocusSeconds)
    }

    /// Number of completed sessions in history.
    /// Avoids temporary array allocation from filter — counts in-place.
    var totalCompletedSessions: Int {
        sessions.reduce(0) { $0 + ($1.completed ? 1 : 0) }
    }

    // MARK: - Init

    init(preset: TimerPreset = .pomodoro) {
        self.activePreset = preset
        self.streak = FocusStreak.empty
        loadSessions()
        loadStreak()
    }

    // MARK: - Timer Control

    /// Start a new focus period.
    @discardableResult
    func startFocus(distractionFree: Bool = false) -> Bool {
        guard phase == .idle || phase == .shortBreak || phase == .longBreak else {
            return false
        }
        phase = .focus
        focusStartTime = Date()
        pauseStartTime = nil
        totalPausedSeconds = 0
        currentArticles = []
        distractionFreeMode = distractionFree

        NotificationCenter.default.post(name: .focusTimerDidStart, object: self)
        return true
    }

    /// Pause the current focus session.
    @discardableResult
    func pause() -> Bool {
        guard phase == .focus else { return false }
        phase = .paused
        pauseStartTime = Date()
        NotificationCenter.default.post(name: .focusTimerDidPause, object: self)
        return true
    }

    /// Resume a paused focus session.
    @discardableResult
    func resume() -> Bool {
        guard phase == .paused, let pauseStart = pauseStartTime else {
            return false
        }
        let pausedDuration = Int(Date().timeIntervalSince(pauseStart))
        totalPausedSeconds += pausedDuration
        pauseStartTime = nil
        phase = .focus
        NotificationCenter.default.post(name: .focusTimerDidPause, object: self)
        return true
    }

    /// Complete the current focus session (timer ran out or user finished early).
    /// - Parameter completed: Whether the full duration was reached.
    /// - Returns: The session record, or nil if no active session.
    @discardableResult
    func endFocus(completed: Bool = true) -> FocusSessionRecord? {
        guard phase == .focus || phase == .paused else { return nil }

        // If paused, account for remaining pause time
        if let pauseStart = pauseStartTime {
            totalPausedSeconds += Int(Date().timeIntervalSince(pauseStart))
        }

        guard let start = focusStartTime else { return nil }

        let duration = max(0, Int(Date().timeIntervalSince(start)) - totalPausedSeconds)
        let target = activePreset.focusMinutes * 60

        let record = FocusSessionRecord(
            id: UUID().uuidString,
            startedAt: start,
            endedAt: Date(),
            durationSeconds: duration,
            targetDurationSeconds: target,
            articlesRead: currentArticles,
            preset: activePreset.name,
            completed: completed,
            distractionFreeMode: distractionFreeMode
        )

        sessions.append(record)
        currentRound += 1
        saveSessions()

        if completed {
            updateStreak()
            NotificationCenter.default.post(name: .focusTimerDidComplete, object: self, userInfo: ["record": record])
        }

        // Transition to break
        if currentRound >= activePreset.roundsBeforeLongBreak {
            phase = .longBreak
            currentRound = 0
            NotificationCenter.default.post(name: .focusTimerBreakDidStart, object: self, userInfo: ["type": "long"])
        } else {
            phase = .shortBreak
            NotificationCenter.default.post(name: .focusTimerBreakDidStart, object: self, userInfo: ["type": "short"])
        }

        // Reset focus state
        focusStartTime = nil
        pauseStartTime = nil
        totalPausedSeconds = 0
        currentArticles = []
        distractionFreeMode = false

        return record
    }

    /// End the current break and go back to idle.
    func endBreak() {
        guard phase == .shortBreak || phase == .longBreak else { return }
        phase = .idle
        NotificationCenter.default.post(name: .focusTimerBreakDidEnd, object: self)
    }

    /// Cancel the current session entirely (no record saved).
    func cancel() {
        phase = .idle
        focusStartTime = nil
        pauseStartTime = nil
        totalPausedSeconds = 0
        currentArticles = []
        distractionFreeMode = false
    }

    /// Skip the current break and go straight to idle.
    func skipBreak() {
        endBreak()
    }

    // MARK: - Article Tracking

    /// Record an article read during the current focus session.
    func recordArticle(link: String, title: String) {
        guard phase == .focus || phase == .paused else { return }
        let article = FocusArticle(link: link, title: title, readAt: Date())
        currentArticles.append(article)
    }

    /// Number of articles in the current focus session.
    var currentArticleCount: Int {
        currentArticles.count
    }

    // MARK: - Preset Management

    /// Switch to a different preset (only while idle).
    @discardableResult
    func setPreset(_ preset: TimerPreset) -> Bool {
        guard phase == .idle else { return false }
        activePreset = preset
        currentRound = 0
        savePreset()
        return true
    }

    // MARK: - History & Stats

    /// All session records (most recent first).
    var allSessions: [FocusSessionRecord] {
        sessions.sorted { $0.startedAt > $1.startedAt }
    }

    /// Sessions from a specific day.
    func sessions(for date: Date) -> [FocusSessionRecord] {
        let calendar = Calendar.current
        return sessions.filter { calendar.isDate($0.startedAt, inSameDayAs: date) }
    }

    /// Daily summary for a specific date.
    func dailySummary(for date: Date) -> DailyFocusSummary {
        let daySessions = sessions(for: date)
        return DailyFocusSummary(date: date, sessions: daySessions)
    }

    /// Daily summaries for the last N days.
    func recentDailySummaries(days: Int = 7) -> [DailyFocusSummary] {
        let calendar = Calendar.current
        var summaries: [DailyFocusSummary] = []
        for offset in 0..<max(0, days) {
            guard let date = calendar.date(byAdding: .day, value: -offset, to: Date()) else { continue }
            let summary = dailySummary(for: date)
            summaries.append(summary)
        }
        return summaries
    }

    /// Total focus time across all sessions (seconds).
    var totalFocusTime: Int {
        sessions.reduce(0) { $0 + $1.durationSeconds }
    }

    /// Average focus session duration (seconds).
    var averageSessionDuration: Double {
        guard !sessions.isEmpty else { return 0 }
        return Double(totalFocusTime) / Double(sessions.count)
    }

    /// Overall completion rate (% of sessions fully completed).
    var completionRate: Double {
        guard !sessions.isEmpty else { return 0 }
        return Double(totalCompletedSessions) / Double(sessions.count) * 100.0
    }

    /// Total articles read across all focus sessions.
    var totalArticlesRead: Int {
        sessions.reduce(0) { $0 + $1.articlesRead.count }
    }

    /// Overall reading pace (articles/hour).
    var overallArticlesPerHour: Double {
        let hours = Double(totalFocusTime) / 3600.0
        guard hours > 0 else { return 0 }
        return Double(totalArticlesRead) / hours
    }

    /// Preferred reading time (hour of day with most sessions).
    var preferredReadingHour: Int? {
        guard !sessions.isEmpty else { return nil }
        let calendar = Calendar.current
        var hourCounts: [Int: Int] = [:]
        for s in sessions {
            let hour = calendar.component(.hour, from: s.startedAt)
            hourCounts[hour, default: 0] += 1
        }
        return hourCounts.max(by: { $0.value < $1.value })?.key
    }

    /// Most used preset name.
    var favoritePreset: String? {
        guard !sessions.isEmpty else { return nil }
        var presetCounts: [String: Int] = [:]
        for s in sessions {
            presetCounts[s.preset, default: 0] += 1
        }
        return presetCounts.max(by: { $0.value < $1.value })?.key
    }

    // MARK: - Streak

    /// Update streak based on today's activity.
    private func updateStreak() {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())

        if let lastActive = streak.lastActiveDate {
            let lastDay = calendar.startOfDay(for: lastActive)
            if calendar.isDate(lastDay, inSameDayAs: today) {
                // Same day — streak unchanged
                return
            }
            let yesterday = calendar.date(byAdding: .day, value: -1, to: today)!
            if calendar.isDate(lastDay, inSameDayAs: yesterday) {
                // Consecutive day — extend streak
                streak.currentStreak += 1
            } else {
                // Gap — reset streak
                streak.currentStreak = 1
            }
        } else {
            // First session ever
            streak.currentStreak = 1
        }

        streak.lastActiveDate = today
        if streak.currentStreak > streak.longestStreak {
            streak.longestStreak = streak.currentStreak
        }

        saveStreak()
        NotificationCenter.default.post(name: .focusTimerStreakDidChange, object: self)
    }

    // MARK: - JSON Export/Import

    /// Export all session data as JSON.
    func exportJSON() -> String {
        let data: [String: Any] = [
            "version": 1,
            "exportedAt": ISO8601DateFormatter().string(from: Date()),
            "activePreset": activePreset.name,
            "streak": [
                "current": streak.currentStreak,
                "longest": streak.longestStreak,
                "lastActive": streak.lastActiveDate.map { ISO8601DateFormatter().string(from: $0) } ?? ""
            ],
            "totalSessions": sessions.count,
            "totalFocusMinutes": totalFocusTime / 60,
            "totalArticlesRead": totalArticlesRead,
            "completionRate": String(format: "%.1f", completionRate),
            "sessions": sessions.map { s in
                [
                    "id": s.id,
                    "startedAt": ISO8601DateFormatter().string(from: s.startedAt),
                    "endedAt": ISO8601DateFormatter().string(from: s.endedAt),
                    "durationSeconds": s.durationSeconds,
                    "targetDurationSeconds": s.targetDurationSeconds,
                    "preset": s.preset,
                    "completed": s.completed,
                    "distractionFreeMode": s.distractionFreeMode,
                    "articleCount": s.articlesRead.count,
                    "articlesPerHour": String(format: "%.1f", s.articlesPerHour)
                ] as [String: Any]
            }
        ]

        guard let jsonData = try? JSONSerialization.data(withJSONObject: data, options: [.prettyPrinted, .sortedKeys]) else {
            return "{}"
        }
        return String(data: jsonData, encoding: .utf8) ?? "{}"
    }

    /// Import sessions from JSON data.
    @discardableResult
    func importJSON(_ jsonString: String) -> Int {
        guard let jsonData = jsonString.data(using: .utf8),
              let dict = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any],
              let sessionsArray = dict["sessions"] as? [[String: Any]] else {
            return 0
        }

        let formatter = ISO8601DateFormatter()
        var imported = 0

        for entry in sessionsArray {
            guard let id = entry["id"] as? String,
                  let startStr = entry["startedAt"] as? String,
                  let endStr = entry["endedAt"] as? String,
                  let startDate = formatter.date(from: startStr),
                  let endDate = formatter.date(from: endStr),
                  let duration = entry["durationSeconds"] as? Int,
                  let target = entry["targetDurationSeconds"] as? Int,
                  let preset = entry["preset"] as? String,
                  let completed = entry["completed"] as? Bool else {
                continue
            }

            // Skip duplicates
            if sessions.contains(where: { $0.id == id }) { continue }

            let dfm = entry["distractionFreeMode"] as? Bool ?? false

            let record = FocusSessionRecord(
                id: id,
                startedAt: startDate,
                endedAt: endDate,
                durationSeconds: duration,
                targetDurationSeconds: target,
                articlesRead: [],
                preset: preset,
                completed: completed,
                distractionFreeMode: dfm
            )
            sessions.append(record)
            imported += 1
        }

        if imported > 0 { saveSessions() }
        return imported
    }

    // MARK: - Text Report

    /// Generate a readable summary report.
    func generateReport() -> String {
        var lines: [String] = []
        lines.append("╔══════════════════════════════════════════╗")
        lines.append("║       Reading Focus Timer Report         ║")
        lines.append("╠══════════════════════════════════════════╣")
        lines.append("║")
        lines.append("║  Streak: \(streak.currentStreak) days (best: \(streak.longestStreak))")
        lines.append("║  Total sessions: \(sessions.count) (\(totalCompletedSessions) completed)")
        lines.append("║  Total focus time: \(totalFocusTime / 3600)h \((totalFocusTime % 3600) / 60)m")
        lines.append("║  Articles read: \(totalArticlesRead)")
        lines.append("║  Completion rate: \(String(format: "%.0f", completionRate))%")
        lines.append("║  Avg session: \(String(format: "%.0f", averageSessionDuration / 60))m")
        lines.append("║  Reading pace: \(String(format: "%.1f", overallArticlesPerHour)) articles/hr")

        if let fav = favoritePreset {
            lines.append("║  Favorite preset: \(fav)")
        }
        if let hour = preferredReadingHour {
            lines.append("║  Preferred hour: \(hour):00")
        }

        lines.append("║")

        // Last 7 days
        let recent = recentDailySummaries(days: 7)
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "EEE"

        lines.append("║  Last 7 days:")
        for summary in recent {
            let day = dateFormatter.string(from: summary.date)
            let mins = summary.totalFocusSeconds / 60
            let bar = String(repeating: "█", count: min(20, mins / 5))
            lines.append("║    \(day): \(bar) \(mins)m (\(summary.completedSessions) sessions)")
        }

        lines.append("║")
        lines.append("╚══════════════════════════════════════════╝")
        return lines.joined(separator: "\n")
    }

    // MARK: - Data Management

    /// Clear all session history and reset streak.
    func clearHistory() {
        sessions.removeAll()
        streak = .empty
        currentRound = 0
        saveSessions()
        saveStreak()
    }

    /// Remove sessions older than a given date.
    func pruneSessionsBefore(_ date: Date) -> Int {
        let before = sessions.count
        sessions.removeAll { $0.startedAt < date }
        let removed = before - sessions.count
        if removed > 0 { saveSessions() }
        return removed
    }

    // MARK: - Persistence

    private func saveSessions() {
        if let data = try? JSONEncoder().encode(sessions) {
            UserDefaults.standard.set(data, forKey: sessionsKey)
        }
    }

    private func loadSessions() {
        guard let data = UserDefaults.standard.data(forKey: sessionsKey),
              let decoded = try? JSONDecoder().decode([FocusSessionRecord].self, from: data) else {
            return
        }
        sessions = decoded
    }

    private func saveStreak() {
        if let data = try? JSONEncoder().encode(streak) {
            UserDefaults.standard.set(data, forKey: streakKey)
        }
    }

    private func loadStreak() {
        guard let data = UserDefaults.standard.data(forKey: streakKey),
              let decoded = try? JSONDecoder().decode(FocusStreak.self, from: data) else {
            return
        }
        streak = decoded
    }

    private func savePreset() {
        if let data = try? JSONEncoder().encode(activePreset) {
            UserDefaults.standard.set(data, forKey: presetKey)
        }
    }
}
