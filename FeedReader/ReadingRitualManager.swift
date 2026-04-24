//
//  ReadingRitualManager.swift
//  FeedReader
//
//  Reading Rituals — define named, recurring reading sessions with
//  specific feeds, time windows, and article goals. Tracks completions,
//  builds streaks, and surfaces the right content at the right time.
//
//  Examples:
//    - "Morning Tech Briefing": Mon-Fri 7-9 AM, tech feeds, 5 articles
//    - "Weekend Deep Dive": Sat-Sun 10 AM-12 PM, longform feeds, 3 articles
//    - "Lunch News Scan": Mon-Fri 12-1 PM, news feeds, 10 articles
//
//  Features:
//    - Named rituals with schedules, feed filters, and article count goals
//    - Active ritual detection (what ritual applies right now?)
//    - Completion tracking with per-session logs
//    - Ritual streaks (consecutive scheduled completions)
//    - Adherence score (completions / scheduled occurrences)
//    - Suggested reading queue per ritual from subscribed feeds
//    - Summary & analytics: best ritual, most skipped, time patterns
//    - Plain text and JSON export
//
//  Persistence: JSON file in Documents directory.
//  Fully offline — no network, no dependencies beyond Foundation.
//

import Foundation

// MARK: - Notifications

extension Notification.Name {
    /// Posted when a ritual is created, updated, or deleted.
    static let readingRitualDidChange = Notification.Name("ReadingRitualDidChangeNotification")
    /// Posted when a ritual session is completed.
    static let readingRitualCompleted = Notification.Name("ReadingRitualCompletedNotification")
}

// MARK: - Schedule

/// Days of the week for ritual scheduling.
struct RitualSchedule: Codable, Equatable {
    /// Days when this ritual is active (1=Sun, 2=Mon, ..., 7=Sat).
    let activeDays: Set<Int>
    /// Start hour (0-23) in local time.
    let startHour: Int
    /// End hour (0-23) in local time.
    let endHour: Int

    /// Whether the given date falls within this schedule.
    func isActive(at date: Date) -> Bool {
        let calendar = Calendar.current
        let weekday = calendar.component(.weekday, from: date)
        let hour = calendar.component(.hour, from: date)
        guard activeDays.contains(weekday) else { return false }
        if startHour <= endHour {
            return hour >= startHour && hour < endHour
        } else {
            // Wraps midnight (e.g., 22-2)
            return hour >= startHour || hour < endHour
        }
    }

    /// Human-readable schedule description.
    var displayText: String {
        let dayNames = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]
        let days = (1...7).filter { activeDays.contains($0) }
            .map { dayNames[$0 - 1] }
            .joined(separator: ", ")
        let startStr = String(format: "%d:%02d", startHour, 0)
        let endStr = String(format: "%d:%02d", endHour, 0)
        return "\(days) \(startStr)–\(endStr)"
    }

    /// Weekday-only convenience.
    static var weekdays: RitualSchedule {
        RitualSchedule(activeDays: [2, 3, 4, 5, 6], startHour: 7, endHour: 9)
    }

    /// Weekend convenience.
    static var weekends: RitualSchedule {
        RitualSchedule(activeDays: [1, 7], startHour: 10, endHour: 12)
    }
}

// MARK: - Ritual

/// A named reading ritual with schedule, feed scope, and goals.
struct ReadingRitual: Codable, Equatable {
    /// Unique identifier.
    let id: String
    /// User-chosen name (e.g., "Morning Tech Briefing").
    var name: String
    /// Optional description / motivation.
    var description: String?
    /// Emoji icon for display.
    var icon: String
    /// When this ritual is active.
    var schedule: RitualSchedule
    /// Feed names to include (empty = all feeds).
    var feedFilter: [String]
    /// Minimum article word count (0 = no minimum).
    var minWordCount: Int
    /// Maximum article word count (0 = no maximum).
    var maxWordCount: Int
    /// Target number of articles per session.
    var articleGoal: Int
    /// Whether the ritual is enabled.
    var isEnabled: Bool
    /// When the ritual was created.
    let createdAt: Date

    init(name: String, icon: String = "📖", schedule: RitualSchedule,
         feedFilter: [String] = [], minWordCount: Int = 0,
         maxWordCount: Int = 0, articleGoal: Int = 5,
         description: String? = nil) {
        self.id = UUID().uuidString
        self.name = name
        self.icon = icon
        self.schedule = schedule
        self.feedFilter = feedFilter
        self.minWordCount = minWordCount
        self.maxWordCount = maxWordCount
        self.articleGoal = articleGoal
        self.isEnabled = true
        self.createdAt = Date()
        self.description = description
    }

    static func == (lhs: ReadingRitual, rhs: ReadingRitual) -> Bool {
        lhs.id == rhs.id
    }
}

// MARK: - Session Log

/// Record of a single ritual session (completed or partial).
struct RitualSession: Codable, Equatable {
    /// The ritual ID this session belongs to.
    let ritualId: String
    /// When the session started.
    let startedAt: Date
    /// When the session ended (nil if ongoing).
    var completedAt: Date?
    /// Articles read during this session (links).
    var articlesRead: [String]
    /// Whether the article goal was met.
    var goalMet: Bool
    /// Calendar date string (yyyy-MM-dd) for dedup.
    let dateKey: String

    init(ritualId: String, date: Date = Date()) {
        self.ritualId = ritualId
        self.startedAt = date
        self.completedAt = nil
        self.articlesRead = []
        self.goalMet = false
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        self.dateKey = formatter.string(from: date)
    }
}

// MARK: - Analytics

/// Aggregate statistics for a single ritual.
struct RitualAnalytics: Equatable {
    let ritualId: String
    let ritualName: String
    let totalSessions: Int
    let completedSessions: Int
    let totalArticlesRead: Int
    let adherenceRate: Double       // completedSessions / scheduledOccurrences
    let currentStreak: Int          // consecutive scheduled completions
    let longestStreak: Int
    let averageArticlesPerSession: Double
    let scheduledOccurrences: Int   // how many times was this scheduled since creation
}

// MARK: - Manager

class ReadingRitualManager {

    // MARK: - Singleton

    static let shared = ReadingRitualManager()

    // MARK: - Storage

    private(set) var rituals: [ReadingRitual] = []
    private(set) var sessions: [RitualSession] = []
    private let fileManager = FileManager.default

    private var storageURL: URL {
        let docs = fileManager.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return docs.appendingPathComponent("reading_rituals.json")
    }

    private var sessionsURL: URL {
        let docs = fileManager.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return docs.appendingPathComponent("ritual_sessions.json")
    }

    // MARK: - Init

    init() {
        loadRituals()
        loadSessions()
    }

    // MARK: - CRUD

    /// Create a new ritual.
    @discardableResult
    func createRitual(name: String, icon: String = "📖",
                      schedule: RitualSchedule, feedFilter: [String] = [],
                      minWordCount: Int = 0, maxWordCount: Int = 0,
                      articleGoal: Int = 5, description: String? = nil) -> ReadingRitual {
        let ritual = ReadingRitual(
            name: name, icon: icon, schedule: schedule,
            feedFilter: feedFilter, minWordCount: minWordCount,
            maxWordCount: maxWordCount, articleGoal: articleGoal,
            description: description
        )
        rituals.append(ritual)
        saveRituals()
        NotificationCenter.default.post(name: .readingRitualDidChange, object: ritual)
        return ritual
    }

    /// Update an existing ritual by ID.
    func updateRitual(_ id: String, update: (inout ReadingRitual) -> Void) -> Bool {
        guard let index = rituals.firstIndex(where: { $0.id == id }) else { return false }
        update(&rituals[index])
        saveRituals()
        NotificationCenter.default.post(name: .readingRitualDidChange, object: rituals[index])
        return true
    }

    /// Delete a ritual and its sessions.
    func deleteRitual(_ id: String) -> Bool {
        guard let index = rituals.firstIndex(where: { $0.id == id }) else { return false }
        let removed = rituals.remove(at: index)
        sessions.removeAll { $0.ritualId == id }
        saveRituals()
        saveSessions()
        NotificationCenter.default.post(name: .readingRitualDidChange, object: removed)
        return true
    }

    /// Get ritual by ID.
    func ritual(byId id: String) -> ReadingRitual? {
        rituals.first { $0.id == id }
    }

    /// Get ritual by name (case-insensitive).
    func ritual(byName name: String) -> ReadingRitual? {
        rituals.first { $0.name.lowercased() == name.lowercased() }
    }

    // MARK: - Active Ritual Detection

    /// Returns rituals whose schedule matches the given date.
    func activeRituals(at date: Date = Date()) -> [ReadingRitual] {
        rituals.filter { $0.isEnabled && $0.schedule.isActive(at: date) }
    }

    /// Returns the next upcoming ritual today (or nil if none remain).
    func nextRitualToday(after date: Date = Date()) -> (ritual: ReadingRitual, startsAt: Int)? {
        let calendar = Calendar.current
        let weekday = calendar.component(.weekday, from: date)
        let currentHour = calendar.component(.hour, from: date)

        let upcoming = rituals.filter { ritual in
            ritual.isEnabled &&
            ritual.schedule.activeDays.contains(weekday) &&
            ritual.schedule.startHour > currentHour
        }.sorted { $0.schedule.startHour < $1.schedule.startHour }

        guard let next = upcoming.first else { return nil }
        return (next, next.schedule.startHour)
    }

    // MARK: - Session Tracking

    /// Start a session for a ritual. Returns the session.
    @discardableResult
    func startSession(ritualId: String, date: Date = Date()) -> RitualSession? {
        guard rituals.contains(where: { $0.id == ritualId }) else { return nil }
        // Prevent duplicate sessions for same ritual+date
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        let dateKey = formatter.string(from: date)
        if sessions.contains(where: { $0.ritualId == ritualId && $0.dateKey == dateKey }) {
            return sessions.first { $0.ritualId == ritualId && $0.dateKey == dateKey }
        }
        let session = RitualSession(ritualId: ritualId, date: date)
        sessions.append(session)
        saveSessions()
        return session
    }

    /// Log an article read during a ritual session.
    func logArticleRead(ritualId: String, articleLink: String, date: Date = Date()) -> Bool {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        let dateKey = formatter.string(from: date)

        guard let index = sessions.firstIndex(where: {
            $0.ritualId == ritualId && $0.dateKey == dateKey
        }) else { return false }

        guard !sessions[index].articlesRead.contains(articleLink) else { return true }

        sessions[index].articlesRead.append(articleLink)

        // Check goal completion
        if let ritual = ritual(byId: ritualId),
           sessions[index].articlesRead.count >= ritual.articleGoal {
            sessions[index].goalMet = true
            sessions[index].completedAt = date
            NotificationCenter.default.post(name: .readingRitualCompleted, object: ritual)
        }

        saveSessions()
        return true
    }

    /// Complete a session manually (even if goal not fully met).
    func completeSession(ritualId: String, date: Date = Date()) -> Bool {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        let dateKey = formatter.string(from: date)

        guard let index = sessions.firstIndex(where: {
            $0.ritualId == ritualId && $0.dateKey == dateKey
        }) else { return false }

        sessions[index].completedAt = date
        if let ritual = ritual(byId: ritualId) {
            sessions[index].goalMet = sessions[index].articlesRead.count >= ritual.articleGoal
        }
        saveSessions()
        return true
    }

    // MARK: - Analytics

    /// Compute analytics for a specific ritual.
    func analytics(for ritualId: String) -> RitualAnalytics? {
        guard let ritual = ritual(byId: ritualId) else { return nil }

        let ritualSessions = sessions.filter { $0.ritualId == ritualId }
        let completed = ritualSessions.filter { $0.goalMet }
        let totalArticles = ritualSessions.reduce(0) { $0 + $1.articlesRead.count }
        let scheduled = scheduledOccurrences(for: ritual)
        let adherence = scheduled > 0 ? Double(completed.count) / Double(scheduled) : 0
        let avgArticles = ritualSessions.isEmpty ? 0 : Double(totalArticles) / Double(ritualSessions.count)
        let (current, longest) = computeStreaks(for: ritual, sessions: ritualSessions)

        return RitualAnalytics(
            ritualId: ritualId,
            ritualName: ritual.name,
            totalSessions: ritualSessions.count,
            completedSessions: completed.count,
            totalArticlesRead: totalArticles,
            adherenceRate: adherence,
            currentStreak: current,
            longestStreak: longest,
            averageArticlesPerSession: avgArticles,
            scheduledOccurrences: scheduled
        )
    }

    /// Analytics for all rituals.
    func allAnalytics() -> [RitualAnalytics] {
        rituals.compactMap { analytics(for: $0.id) }
    }

    /// Best performing ritual by adherence rate.
    func bestRitual() -> RitualAnalytics? {
        allAnalytics().max(by: { $0.adherenceRate < $1.adherenceRate })
    }

    /// Most skipped ritual (lowest adherence with >0 scheduled).
    func mostSkippedRitual() -> RitualAnalytics? {
        allAnalytics()
            .filter { $0.scheduledOccurrences > 0 }
            .min(by: { $0.adherenceRate < $1.adherenceRate })
    }

    // MARK: - Suggested Queue

    /// Build a reading queue for a ritual based on its feed filter and word count criteria.
    /// Takes a list of available stories and filters/ranks them.
    func suggestedQueue(for ritualId: String, from stories: [SuggestedStory]) -> [SuggestedStory] {
        guard let ritual = ritual(byId: ritualId) else { return [] }

        let todaySessions = sessions.filter { $0.ritualId == ritualId }
        let alreadyRead = Set(todaySessions.flatMap { $0.articlesRead })

        var filtered = stories.filter { story in
            // Exclude already-read
            guard !alreadyRead.contains(story.link) else { return false }
            // Feed filter
            if !ritual.feedFilter.isEmpty {
                guard ritual.feedFilter.contains(where: {
                    story.feedName.lowercased().contains($0.lowercased())
                }) else { return false }
            }
            // Word count filter
            if ritual.minWordCount > 0, story.wordCount < ritual.minWordCount { return false }
            if ritual.maxWordCount > 0, story.wordCount > ritual.maxWordCount { return false }
            return true
        }

        // Sort by recency (newest first)
        filtered.sort { $0.publishDate > $1.publishDate }

        // Limit to goal count
        return Array(filtered.prefix(ritual.articleGoal))
    }

    // MARK: - Export

    /// Plain text summary of all rituals and their stats.
    func exportPlainText() -> String {
        var lines: [String] = ["=== Reading Rituals ===", ""]

        for ritual in rituals {
            lines.append("\(ritual.icon) \(ritual.name)")
            if let desc = ritual.description { lines.append("  \(desc)") }
            lines.append("  Schedule: \(ritual.schedule.displayText)")
            lines.append("  Goal: \(ritual.articleGoal) articles")
            if !ritual.feedFilter.isEmpty {
                lines.append("  Feeds: \(ritual.feedFilter.joined(separator: ", "))")
            }
            lines.append("  Status: \(ritual.isEnabled ? "Active" : "Paused")")

            if let stats = analytics(for: ritual.id) {
                lines.append("  Sessions: \(stats.totalSessions) (\(stats.completedSessions) completed)")
                lines.append("  Adherence: \(String(format: "%.0f%%", stats.adherenceRate * 100))")
                lines.append("  Streak: \(stats.currentStreak) (best: \(stats.longestStreak))")
                lines.append("  Articles: \(stats.totalArticlesRead) total")
            }
            lines.append("")
        }

        if rituals.isEmpty {
            lines.append("No rituals defined yet.")
        }

        return lines.joined(separator: "\n")
    }

    /// JSON export of all data.
    func exportJSON() -> String {
        struct Export: Codable {
            let rituals: [ReadingRitual]
            let sessions: [RitualSession]
        }
        let export = Export(rituals: rituals, sessions: sessions)
        guard let data = try? JSONCoding.iso8601PrettyEncoder.encode(export),
              let json = String(data: data, encoding: .utf8) else {
            return "{}"
        }
        return json
    }

    // MARK: - Presets

    /// Create common preset rituals.
    func createMorningBriefing(feeds: [String] = []) -> ReadingRitual {
        createRitual(
            name: "Morning Briefing",
            icon: "☀️",
            schedule: .weekdays,
            feedFilter: feeds,
            articleGoal: 5,
            description: "Quick morning scan of top stories"
        )
    }

    func createWeekendDeepDive(feeds: [String] = []) -> ReadingRitual {
        createRitual(
            name: "Weekend Deep Dive",
            icon: "📚",
            schedule: .weekends,
            feedFilter: feeds,
            minWordCount: 1000,
            articleGoal: 3,
            description: "Long-form weekend reading"
        )
    }

    func createLunchScan(feeds: [String] = []) -> ReadingRitual {
        createRitual(
            name: "Lunch News Scan",
            icon: "🥪",
            schedule: RitualSchedule(activeDays: [2, 3, 4, 5, 6], startHour: 12, endHour: 13),
            feedFilter: feeds,
            articleGoal: 10,
            description: "Quick news catch-up over lunch"
        )
    }

    func createEveningWind­Down(feeds: [String] = []) -> ReadingRitual {
        createRitual(
            name: "Evening Wind-Down",
            icon: "🌙",
            schedule: RitualSchedule(activeDays: Set(1...7), startHour: 21, endHour: 23),
            feedFilter: feeds,
            maxWordCount: 800,
            articleGoal: 3,
            description: "Light reading before bed"
        )
    }

    // MARK: - Private Helpers

    private func scheduledOccurrences(for ritual: ReadingRitual) -> Int {
        let calendar = Calendar.current
        let now = Date()
        guard let daysSinceCreation = calendar.dateComponents([.day],
                from: calendar.startOfDay(for: ritual.createdAt),
                to: calendar.startOfDay(for: now)).day else { return 0 }

        var count = 0
        for dayOffset in 0...max(0, daysSinceCreation) {
            guard let date = calendar.date(byAdding: .day, value: -dayOffset, to: now) else { continue }
            let weekday = calendar.component(.weekday, from: date)
            if ritual.schedule.activeDays.contains(weekday) {
                count += 1
            }
        }
        return count
    }

    private func computeStreaks(for ritual: ReadingRitual, sessions: [RitualSession]) -> (current: Int, longest: Int) {
        let calendar = Calendar.current
        let completedDates = Set(sessions.filter { $0.goalMet }.map { $0.dateKey })

        guard !completedDates.isEmpty else { return (0, 0) }

        // Walk backward from today counting consecutive scheduled days that were completed
        let now = Date()
        var currentStreak = 0
        var longestStreak = 0
        var tempStreak = 0
        var checkingCurrent = true

        for dayOffset in 0..<365 {
            guard let date = calendar.date(byAdding: .day, value: -dayOffset, to: now) else { break }
            let weekday = calendar.component(.weekday, from: date)

            // Skip non-scheduled days
            guard ritual.schedule.activeDays.contains(weekday) else { continue }

            let formatter = DateFormatter()
            formatter.dateFormat = "yyyy-MM-dd"
            let key = formatter.string(from: date)

            if completedDates.contains(key) {
                tempStreak += 1
                longestStreak = max(longestStreak, tempStreak)
                if checkingCurrent { currentStreak = tempStreak }
            } else {
                checkingCurrent = false
                tempStreak = 0
            }
        }

        return (currentStreak, longestStreak)
    }

    // MARK: - Persistence

    private func saveRituals() {
        guard let data = try? JSONCoding.iso8601Encoder.encode(rituals) else { return }
        try? data.write(to: storageURL, options: .atomic)
    }

    private func loadRituals() {
        guard let data = try? Data(contentsOf: storageURL) else { return }
        rituals = (try? JSONCoding.iso8601Decoder.decode([ReadingRitual].self, from: data)) ?? []
    }

    private func saveSessions() {
        guard let data = try? JSONCoding.iso8601Encoder.encode(sessions) else { return }
        try? data.write(to: sessionsURL, options: .atomic)
    }

    private func loadSessions() {
        guard let data = try? Data(contentsOf: sessionsURL) else { return }
        sessions = (try? JSONCoding.iso8601Decoder.decode([RitualSession].self, from: data)) ?? []
    }
}

// MARK: - Suggested Story (Input Model)

/// Lightweight story model for queue building.
struct SuggestedStory {
    let link: String
    let title: String
    let feedName: String
    let publishDate: Date
    let wordCount: Int
}
