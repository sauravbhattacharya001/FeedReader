//
//  ArticleThreadManager.swift
//  FeedReader
//
//  Tracks developing stories by linking related articles into narrative
//  threads. Users can follow an evolving story (e.g., an election, a
//  product launch, a crisis) across multiple feeds and time periods.
//
//  Fully offline — no network, no dependencies beyond Foundation.
//

import Foundation

// MARK: - Notification

extension Notification.Name {
    static let threadsDidUpdate = Notification.Name("ThreadsDidUpdateNotification")
}

// MARK: - ThreadStatus

/// Lifecycle status of a story thread.
enum ThreadStatus: String, Codable {
    case active      // story is still developing
    case stale       // no new articles in a while
    case archived    // user archived it
    case resolved    // story reached a conclusion
}

// MARK: - ThreadEntry

/// A single article linked to a thread, with context about why it belongs.
struct ThreadEntry: Codable, Equatable {
    /// Article title.
    let title: String
    /// Article URL/link.
    let link: String
    /// Source feed name.
    let feedSource: String
    /// When the article was added to the thread.
    let addedDate: Date
    /// Optional user note about this article's relevance.
    var note: String?
    /// Auto-detected relevance score (0.0-1.0).
    let relevanceScore: Double

    static func == (lhs: ThreadEntry, rhs: ThreadEntry) -> Bool {
        return lhs.link == rhs.link
    }
}

// MARK: - StoryThread

/// A collection of related articles forming a narrative thread.
struct StoryThread: Codable {
    /// Unique identifier.
    let id: String
    /// User-assigned title for the thread (e.g., "2026 Election").
    var title: String
    /// Keywords that define this thread's topic.
    var keywords: [String]
    /// Articles in this thread, ordered chronologically.
    var entries: [ThreadEntry]
    /// Current lifecycle status.
    var status: ThreadStatus
    /// When the thread was created.
    let createdDate: Date
    /// When the thread was last updated (new article added).
    var lastUpdatedDate: Date
    /// Optional color tag for UI display (hex string).
    var colorTag: String?

    /// Number of unique feeds contributing to this thread.
    var feedCount: Int {
        return Set(entries.map { $0.feedSource }).count
    }

    /// Time span from first to last entry.
    var timeSpan: TimeInterval? {
        guard let first = entries.first?.addedDate,
              let last = entries.last?.addedDate else { return nil }
        return last.timeIntervalSince(first)
    }

    /// Human-readable time span description.
    var timeSpanDescription: String {
        guard let span = timeSpan else { return "No articles" }
        let days = Int(span / 86400)
        if days == 0 { return "Today" }
        if days == 1 { return "1 day" }
        if days < 7 { return "\(days) days" }
        let weeks = days / 7
        if weeks == 1 { return "1 week" }
        if weeks < 5 { return "\(weeks) weeks" }
        let months = days / 30
        return months == 1 ? "1 month" : "\(months) months"
    }
}

// MARK: - ThreadSuggestion

/// An auto-detected suggestion to create a new thread or add an article to one.
struct ThreadSuggestion {
    enum Kind {
        case newThread(keywords: [String])
        case addToThread(threadId: String, threadTitle: String)
    }
    let kind: Kind
    let articleTitle: String
    let articleLink: String
    let confidence: Double
}

// MARK: - ThreadTimeline

/// A summary view of a thread's progression over time.
struct ThreadTimeline {
    struct Segment {
        let date: Date
        let articleCount: Int
        let feedSources: [String]
        let headlines: [String]
    }
    let threadTitle: String
    let segments: [Segment]
    let totalArticles: Int
    let totalDays: Int
}

// MARK: - ArticleThreadManager

/// Manages story threads — creating, auto-matching, and tracking
/// narrative arcs across articles and feeds.
class ArticleThreadManager {

    // MARK: - Singleton

    static let shared = ArticleThreadManager()

    // MARK: - Properties

    private(set) var threads: [StoryThread] = []
    private let storageKey = "ArticleThreadManager_threads"
    private let staleThresholdDays: Int = 7

    // MARK: - Init

    private init() {
        loadThreads()
    }

    // MARK: - Thread CRUD

    /// Create a new story thread with initial keywords.
    @discardableResult
    func createThread(title: String, keywords: [String], colorTag: String? = nil) -> StoryThread {
        let thread = StoryThread(
            id: UUID().uuidString,
            title: title,
            keywords: keywords.map { $0.lowercased() },
            entries: [],
            status: .active,
            createdDate: Date(),
            lastUpdatedDate: Date(),
            colorTag: colorTag
        )
        threads.append(thread)
        saveThreads()
        NotificationCenter.default.post(name: .threadsDidUpdate, object: nil)
        return thread
    }

    /// Delete a thread by ID.
    func deleteThread(id: String) {
        threads.removeAll { $0.id == id }
        saveThreads()
        NotificationCenter.default.post(name: .threadsDidUpdate, object: nil)
    }

    /// Update a thread's status.
    func updateStatus(threadId: String, status: ThreadStatus) {
        guard let index = threads.firstIndex(where: { $0.id == threadId }) else { return }
        threads[index].status = status
        saveThreads()
        NotificationCenter.default.post(name: .threadsDidUpdate, object: nil)
    }

    /// Rename a thread.
    func renameThread(threadId: String, newTitle: String) {
        guard let index = threads.firstIndex(where: { $0.id == threadId }) else { return }
        threads[index].title = newTitle
        saveThreads()
    }

    /// Update keywords for a thread.
    func updateKeywords(threadId: String, keywords: [String]) {
        guard let index = threads.firstIndex(where: { $0.id == threadId }) else { return }
        threads[index].keywords = keywords.map { $0.lowercased() }
        saveThreads()
    }

    // MARK: - Adding Articles

    /// Manually add an article to a thread.
    @discardableResult
    func addArticle(toThread threadId: String, title: String, link: String,
                    feedSource: String, note: String? = nil) -> Bool {
        guard let index = threads.firstIndex(where: { $0.id == threadId }) else { return false }

        // Avoid duplicates
        if threads[index].entries.contains(where: { $0.link == link }) { return false }

        let relevance = computeRelevance(title: title, keywords: threads[index].keywords)
        let entry = ThreadEntry(
            title: title,
            link: link,
            feedSource: feedSource,
            addedDate: Date(),
            note: note,
            relevanceScore: relevance
        )
        threads[index].entries.append(entry)
        threads[index].lastUpdatedDate = Date()
        if threads[index].status == .stale {
            threads[index].status = .active
        }
        saveThreads()
        NotificationCenter.default.post(name: .threadsDidUpdate, object: nil)
        return true
    }

    /// Remove an article from a thread by link.
    func removeArticle(fromThread threadId: String, link: String) {
        guard let index = threads.firstIndex(where: { $0.id == threadId }) else { return }
        threads[index].entries.removeAll { $0.link == link }
        saveThreads()
    }

    // MARK: - Auto-Matching

    /// Check an article against all active threads and return suggestions.
    func findMatches(title: String, link: String, feedSource: String) -> [ThreadSuggestion] {
        var suggestions: [ThreadSuggestion] = []
        let titleLower = title.lowercased()

        for thread in threads where thread.status == .active {
            let relevance = computeRelevance(title: titleLower, keywords: thread.keywords)
            if relevance >= 0.3 {
                // Don't suggest if already in thread
                guard !thread.entries.contains(where: { $0.link == link }) else { continue }
                suggestions.append(ThreadSuggestion(
                    kind: .addToThread(threadId: thread.id, threadTitle: thread.title),
                    articleTitle: title,
                    articleLink: link,
                    confidence: relevance
                ))
            }
        }

        return suggestions.sorted { $0.confidence > $1.confidence }
    }

    /// Auto-add an article to matching threads (above threshold).
    func autoMatch(title: String, link: String, feedSource: String,
                   threshold: Double = 0.6) -> [String] {
        var matchedThreadIds: [String] = []
        let suggestions = findMatches(title: title, link: link, feedSource: feedSource)

        for suggestion in suggestions {
            if suggestion.confidence >= threshold {
                if case .addToThread(let threadId, _) = suggestion.kind {
                    if addArticle(toThread: threadId, title: title, link: link, feedSource: feedSource) {
                        matchedThreadIds.append(threadId)
                    }
                }
            }
        }
        return matchedThreadIds
    }

    // MARK: - Timeline

    /// Generate a timeline view of a thread, grouped by day.
    func generateTimeline(threadId: String) -> ThreadTimeline? {
        guard let thread = threads.first(where: { $0.id == threadId }) else { return nil }
        guard !thread.entries.isEmpty else { return nil }

        let calendar = Calendar.current
        var dayGroups: [Date: [ThreadEntry]] = [:]

        for entry in thread.entries {
            let dayStart = calendar.startOfDay(for: entry.addedDate)
            dayGroups[dayStart, default: []].append(entry)
        }

        let segments = dayGroups.keys.sorted().map { date -> ThreadTimeline.Segment in
            let entries = dayGroups[date]!
            return ThreadTimeline.Segment(
                date: date,
                articleCount: entries.count,
                feedSources: Array(Set(entries.map { $0.feedSource })),
                headlines: entries.map { $0.title }
            )
        }

        let totalDays: Int
        if let first = segments.first?.date, let last = segments.last?.date {
            totalDays = max(1, calendar.dateComponents([.day], from: first, to: last).day ?? 1)
        } else {
            totalDays = 1
        }

        return ThreadTimeline(
            threadTitle: thread.title,
            segments: segments,
            totalArticles: thread.entries.count,
            totalDays: totalDays
        )
    }

    // MARK: - Staleness Detection

    /// Mark threads with no recent activity as stale.
    func detectStaleThreads() -> [String] {
        var staleIds: [String] = []
        let cutoff = Date().addingTimeInterval(TimeInterval(-staleThresholdDays * 86400))

        for (index, thread) in threads.enumerated() {
            if thread.status == .active && thread.lastUpdatedDate < cutoff {
                threads[index].status = .stale
                staleIds.append(thread.id)
            }
        }

        if !staleIds.isEmpty {
            saveThreads()
            NotificationCenter.default.post(name: .threadsDidUpdate, object: nil)
        }
        return staleIds
    }

    // MARK: - Queries

    /// Get all active threads sorted by last update.
    func activeThreads() -> [StoryThread] {
        return threads.filter { $0.status == .active }
            .sorted { $0.lastUpdatedDate > $1.lastUpdatedDate }
    }

    /// Get threads that an article belongs to.
    func threadsContaining(link: String) -> [StoryThread] {
        return threads.filter { thread in
            thread.entries.contains { $0.link == link }
        }
    }

    /// Search threads by title or keyword.
    func searchThreads(query: String) -> [StoryThread] {
        let q = query.lowercased()
        return threads.filter { thread in
            thread.title.lowercased().contains(q) ||
            thread.keywords.contains(where: { $0.contains(q) })
        }
    }

    /// Summary statistics.
    func statistics() -> (active: Int, stale: Int, archived: Int,
                          totalArticles: Int, avgArticlesPerThread: Double) {
        let active = threads.filter { $0.status == .active }.count
        let stale = threads.filter { $0.status == .stale }.count
        let archived = threads.filter { $0.status == .archived || $0.status == .resolved }.count
        let totalArticles = threads.reduce(0) { $0 + $1.entries.count }
        let avg = threads.isEmpty ? 0.0 : Double(totalArticles) / Double(threads.count)
        return (active, stale, archived, totalArticles, avg)
    }

    // MARK: - Export

    /// Export a thread as a Markdown document.
    func exportAsMarkdown(threadId: String) -> String? {
        guard let thread = threads.first(where: { $0.id == threadId }) else { return nil }

        var md = "# \(thread.title)\n\n"
        md += "**Status:** \(thread.status.rawValue) | "
        md += "**Articles:** \(thread.entries.count) | "
        md += "**Feeds:** \(thread.feedCount) | "
        md += "**Span:** \(thread.timeSpanDescription)\n\n"
        md += "**Keywords:** \(thread.keywords.joined(separator: ", "))\n\n"
        md += "---\n\n"

        let calendar = Calendar.current
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short

        // Group by day
        var dayGroups: [Date: [ThreadEntry]] = [:]
        for entry in thread.entries {
            let day = calendar.startOfDay(for: entry.addedDate)
            dayGroups[day, default: []].append(entry)
        }

        for day in dayGroups.keys.sorted() {
            let dayStr = formatter.string(from: day)
            md += "## \(dayStr)\n\n"
            for entry in dayGroups[day]! {
                md += "- **[\(entry.title)](\(entry.link))** — _\(entry.feedSource)_"
                if let note = entry.note {
                    md += "\n  > \(note)"
                }
                md += "\n"
            }
            md += "\n"
        }

        return md
    }

    // MARK: - Persistence

    private func saveThreads() {
        guard let data = try? JSONEncoder().encode(threads) else { return }
        UserDefaults.standard.set(data, forKey: storageKey)
    }

    private func loadThreads() {
        guard let data = UserDefaults.standard.data(forKey: storageKey),
              let decoded = try? JSONDecoder().decode([StoryThread].self, from: data) else { return }
        threads = decoded
    }

    // MARK: - Relevance Scoring

    private func computeRelevance(title: String, keywords: [String]) -> Double {
        let titleLower = title.lowercased()
        let words = Set(titleLower.components(separatedBy: .alphanumerics.inverted).filter { !$0.isEmpty })

        var matchCount = 0
        for keyword in keywords {
            // Check exact word match or substring in title
            if words.contains(keyword) || titleLower.contains(keyword) {
                matchCount += 1
            }
        }

        guard !keywords.isEmpty else { return 0.0 }
        return min(1.0, Double(matchCount) / Double(keywords.count))
    }
}
