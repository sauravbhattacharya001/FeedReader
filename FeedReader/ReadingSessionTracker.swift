//
//  ReadingSessionTracker.swift
//  FeedReader
//
//  Tracks focused reading sessions — timed periods when the user
//  actively reads articles. Each session records start/end times,
//  articles consumed, time-per-article, and an optional focus tag.
//
//  Use cases:
//  - "I read for 25 minutes and got through 4 articles"
//  - Weekly/monthly session summaries
//  - Average session duration and articles-per-session trends
//  - Focus tagging ("commute", "morning", "research")
//
//  Persistence: UserDefaults via Codable.
//  Integrates with ReadingHistoryManager for automatic article tracking.
//

import Foundation

// MARK: - Notifications

extension Notification.Name {
    /// Posted when a session starts, stops, or is updated.
    static let readingSessionDidChange = Notification.Name("ReadingSessionDidChangeNotification")
    /// Posted when a session completes with a summary.
    static let readingSessionDidComplete = Notification.Name("ReadingSessionDidCompleteNotification")
}

// MARK: - Models

/// A single article read during a session.
struct SessionArticle: Codable, Equatable {
    /// Article URL.
    let link: String
    /// Article title.
    let title: String
    /// Feed name.
    let feedName: String
    /// When the user started reading this article.
    let startedAt: Date
    /// Seconds spent on this article (updated on finish or session end).
    var timeSpent: TimeInterval

    init(link: String, title: String, feedName: String, startedAt: Date = Date(), timeSpent: TimeInterval = 0) {
        self.link = link
        self.title = title
        self.feedName = feedName
        self.startedAt = startedAt
        self.timeSpent = timeSpent
    }
}

/// A completed or in-progress reading session.
struct ReadingSession: Codable, Equatable {
    /// Unique identifier.
    let id: String
    /// When the session started.
    let startedAt: Date
    /// When the session ended (nil if still active).
    var endedAt: Date?
    /// Total pause time accumulated during the session.
    var totalPauseTime: TimeInterval
    /// Articles read during this session.
    var articles: [SessionArticle]
    /// Optional focus tag (e.g., "commute", "research", "morning").
    var tag: String?

    /// Whether the session is still active.
    var isActive: Bool {
        return endedAt == nil
    }

    /// Total wall-clock duration from start to end (or now), minus pauses.
    var activeDuration: TimeInterval {
        let end = endedAt ?? Date()
        let wall = end.timeIntervalSince(startedAt)
        return max(0, wall - totalPauseTime)
    }

    /// Number of articles read.
    var articleCount: Int {
        return articles.count
    }

    /// Average time per article in seconds, or nil if no articles.
    var averageTimePerArticle: TimeInterval? {
        guard articles.count > 0 else { return nil }
        let total = articles.reduce(0) { $0 + $1.timeSpent }
        return total / Double(articles.count)
    }

    /// Articles per minute reading rate.
    var articlesPerMinute: Double? {
        let mins = activeDuration / 60.0
        guard mins > 0 else { return nil }
        return Double(articles.count) / mins
    }

    init(id: String = UUID().uuidString, startedAt: Date = Date(), tag: String? = nil) {
        self.id = id
        self.startedAt = startedAt
        self.endedAt = nil
        self.totalPauseTime = 0
        self.articles = []
        self.tag = tag
    }
}

/// Summary statistics for a time period.
struct SessionSummary: Equatable {
    /// Number of sessions in the period.
    let sessionCount: Int
    /// Total reading time across all sessions (seconds).
    let totalReadingTime: TimeInterval
    /// Total articles read.
    let totalArticles: Int
    /// Average session duration (seconds).
    let averageSessionDuration: TimeInterval
    /// Average articles per session.
    let averageArticlesPerSession: Double
    /// Most-used tag, or nil.
    let topTag: String?
    /// Longest single session duration (seconds).
    let longestSessionDuration: TimeInterval
    /// Feeds that appeared most often across sessions.
    let topFeeds: [(name: String, count: Int)]

    static let empty = SessionSummary(
        sessionCount: 0,
        totalReadingTime: 0,
        totalArticles: 0,
        averageSessionDuration: 0,
        averageArticlesPerSession: 0,
        topTag: nil,
        longestSessionDuration: 0,
        topFeeds: []
    )
}

// MARK: - ReadingSessionTracker

class ReadingSessionTracker {

    // MARK: - Singleton

    static let shared = ReadingSessionTracker()

    // MARK: - Storage

    private let storageKey = "ReadingSessionTracker.sessions"
    private let maxStoredSessions = 500
    private var sessions: [ReadingSession] = []

    /// The currently active session, if any.
    private(set) var activeSession: ReadingSession?

    /// When the session was last paused (nil if not paused).
    private var pausedAt: Date?

    /// The article currently being read (tracked for time-per-article).
    private var currentArticleIndex: Int?

    // MARK: - Init

    init() {
        loadSessions()
    }

    // MARK: - Session Lifecycle

    /// Start a new reading session.
    /// - Parameter tag: Optional focus tag (e.g., "commute", "research").
    /// - Returns: The newly created session.
    @discardableResult
    func startSession(tag: String? = nil) -> ReadingSession {
        // End any active session first
        if activeSession != nil {
            endSession()
        }

        let session = ReadingSession(tag: tag)
        activeSession = session
        pausedAt = nil
        currentArticleIndex = nil

        NotificationCenter.default.post(name: .readingSessionDidChange, object: self)
        return session
    }

    /// Pause the active session (e.g., user backgrounds the app).
    func pauseSession() {
        guard activeSession != nil, pausedAt == nil else { return }

        // Close out time for current article
        finalizeCurrentArticleTime()

        pausedAt = Date()
        NotificationCenter.default.post(name: .readingSessionDidChange, object: self)
    }

    /// Resume the active session after a pause.
    func resumeSession() {
        guard activeSession != nil, let paused = pausedAt else { return }

        let pauseDuration = Date().timeIntervalSince(paused)
        activeSession?.totalPauseTime += pauseDuration
        pausedAt = nil

        NotificationCenter.default.post(name: .readingSessionDidChange, object: self)
    }

    /// End the active session and archive it.
    /// - Returns: The completed session, or nil if no active session.
    @discardableResult
    func endSession() -> ReadingSession? {
        guard var session = activeSession else { return nil }

        // If paused, account for final pause
        if let paused = pausedAt {
            let pauseDuration = Date().timeIntervalSince(paused)
            session.totalPauseTime += pauseDuration
            pausedAt = nil
        }

        // Close out current article time
        finalizeCurrentArticleTime()
        session.articles = activeSession?.articles ?? session.articles

        session.endedAt = Date()
        activeSession = nil
        currentArticleIndex = nil

        // Archive
        sessions.insert(session, at: 0)
        trimSessions()
        saveSessions()

        NotificationCenter.default.post(
            name: .readingSessionDidComplete,
            object: self,
            userInfo: ["session": session]
        )
        NotificationCenter.default.post(name: .readingSessionDidChange, object: self)

        return session
    }

    /// Whether a session is currently active (and not paused).
    var isReading: Bool {
        return activeSession != nil && pausedAt == nil
    }

    /// Whether a session is active but paused.
    var isPaused: Bool {
        return activeSession != nil && pausedAt != nil
    }

    // MARK: - Article Tracking

    /// Record that the user started reading an article in the current session.
    /// - Parameters:
    ///   - link: Article URL.
    ///   - title: Article title.
    ///   - feedName: Feed the article belongs to.
    func startArticle(link: String, title: String, feedName: String) {
        guard activeSession != nil, pausedAt == nil else { return }

        // Finalize time on previous article
        finalizeCurrentArticleTime()

        let article = SessionArticle(link: link, title: title, feedName: feedName)
        activeSession?.articles.append(article)
        currentArticleIndex = (activeSession?.articles.count ?? 1) - 1
    }

    /// Mark the current article as finished and stop timing it.
    func finishArticle() {
        finalizeCurrentArticleTime()
        currentArticleIndex = nil
    }

    /// Number of articles in the current session.
    var currentSessionArticleCount: Int {
        return activeSession?.articleCount ?? 0
    }

    // MARK: - Query

    /// Get all completed sessions, newest first.
    var completedSessions: [ReadingSession] {
        return sessions
    }

    /// Get sessions from the last N days.
    func sessions(lastDays days: Int) -> [ReadingSession] {
        let cutoff = Calendar.current.date(byAdding: .day, value: -days, to: Date()) ?? Date()
        return sessions.filter { $0.startedAt >= cutoff }
    }

    /// Get sessions with a specific tag.
    func sessions(withTag tag: String) -> [ReadingSession] {
        return sessions.filter { $0.tag == tag }
    }

    /// Get all unique tags used across sessions.
    var allTags: [String] {
        let tags = sessions.compactMap { $0.tag }
        return Array(Set(tags)).sorted()
    }

    /// Get a session by ID.
    func session(byId id: String) -> ReadingSession? {
        if let active = activeSession, active.id == id { return active }
        return sessions.first { $0.id == id }
    }

    // MARK: - Summaries

    /// Generate a summary for the given sessions.
    func summary(for sessionList: [ReadingSession]) -> SessionSummary {
        guard !sessionList.isEmpty else { return .empty }

        let totalTime = sessionList.reduce(0) { $0 + $1.activeDuration }
        let totalArticles = sessionList.reduce(0) { $0 + $1.articleCount }
        let avgDuration = totalTime / Double(sessionList.count)
        let avgArticles = Double(totalArticles) / Double(sessionList.count)
        let longestDuration = sessionList.map { $0.activeDuration }.max() ?? 0

        // Find top tag
        var tagCounts: [String: Int] = [:]
        for s in sessionList {
            if let tag = s.tag {
                tagCounts[tag, default: 0] += 1
            }
        }
        let topTag = tagCounts.max(by: { $0.value < $1.value })?.key

        // Find top feeds
        var feedCounts: [String: Int] = [:]
        for s in sessionList {
            for a in s.articles {
                feedCounts[a.feedName, default: 0] += 1
            }
        }
        let topFeeds = feedCounts.sorted { $0.value > $1.value }
            .prefix(5)
            .map { (name: $0.key, count: $0.value) }

        return SessionSummary(
            sessionCount: sessionList.count,
            totalReadingTime: totalTime,
            totalArticles: totalArticles,
            averageSessionDuration: avgDuration,
            averageArticlesPerSession: avgArticles,
            topTag: topTag,
            longestSessionDuration: longestDuration,
            topFeeds: topFeeds
        )
    }

    /// Summary for the last 7 days.
    var weeklySummary: SessionSummary {
        return summary(for: sessions(lastDays: 7))
    }

    /// Summary for the last 30 days.
    var monthlySummary: SessionSummary {
        return summary(for: sessions(lastDays: 30))
    }

    // MARK: - Export

    /// Export session history as JSON data.
    func exportAsJSON() -> Data? {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try? encoder.encode(sessions)
    }

    /// Export session history as formatted text.
    func exportAsText() -> String {
        var lines: [String] = ["Reading Session History", String(repeating: "=", count: 40), ""]

        let dateFormatter = DateFormatter()
        dateFormatter.dateStyle = .medium
        dateFormatter.timeStyle = .short

        for session in sessions {
            let tag = session.tag.map { " [\($0)]" } ?? ""
            let duration = formatSessionDuration(session.activeDuration)
            lines.append("Session\(tag) — \(dateFormatter.string(from: session.startedAt))")
            lines.append("  Duration: \(duration) | Articles: \(session.articleCount)")

            if let avg = session.averageTimePerArticle {
                lines.append("  Avg time/article: \(formatSessionDuration(avg))")
            }

            for article in session.articles {
                let timeStr = formatSessionDuration(article.timeSpent)
                lines.append("    • \(article.title) (\(timeStr)) — \(article.feedName)")
            }
            lines.append("")
        }

        return lines.joined(separator: "\n")
    }

    // MARK: - Management

    /// Delete a session by ID.
    @discardableResult
    func deleteSession(id: String) -> Bool {
        if let idx = sessions.firstIndex(where: { $0.id == id }) {
            sessions.remove(at: idx)
            saveSessions()
            NotificationCenter.default.post(name: .readingSessionDidChange, object: self)
            return true
        }
        return false
    }

    /// Clear all session history.
    func clearHistory() {
        sessions.removeAll()
        saveSessions()
        NotificationCenter.default.post(name: .readingSessionDidChange, object: self)
    }

    /// Total number of completed sessions.
    var totalSessionCount: Int {
        return sessions.count
    }

    // MARK: - Private Helpers

    private func finalizeCurrentArticleTime() {
        guard let idx = currentArticleIndex,
              var session = activeSession,
              idx < session.articles.count else { return }

        let elapsed = Date().timeIntervalSince(session.articles[idx].startedAt)
        let alreadyTracked = session.articles[idx].timeSpent
        session.articles[idx].timeSpent = max(alreadyTracked, elapsed)
        activeSession = session
    }

    private func trimSessions() {
        if sessions.count > maxStoredSessions {
            sessions = Array(sessions.prefix(maxStoredSessions))
        }
    }

    private func saveSessions() {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        if let data = try? encoder.encode(sessions) {
            UserDefaults.standard.set(data, forKey: storageKey)
        }
    }

    private func loadSessions() {
        guard let data = UserDefaults.standard.data(forKey: storageKey) else { return }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        if let loaded = try? decoder.decode([ReadingSession].self, from: data) {
            sessions = loaded
        }
    }

    private func formatSessionDuration(_ seconds: TimeInterval) -> String {
        let totalSeconds = Int(seconds)
        if totalSeconds < 60 { return "\(totalSeconds)s" }
        let minutes = totalSeconds / 60
        let secs = totalSeconds % 60
        if minutes < 60 {
            return secs > 0 ? "\(minutes)m \(secs)s" : "\(minutes)m"
        }
        let hours = minutes / 60
        let mins = minutes % 60
        if mins == 0 { return "\(hours)h" }
        return "\(hours)h \(mins)m"
    }
}
