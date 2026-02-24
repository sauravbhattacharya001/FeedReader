//
//  ReadingHistoryManager.swift
//  FeedReader
//
//  Browsable, searchable timeline of every article the user has read.
//  Tracks rich metadata per entry: visit timestamps, counts, scroll
//  progress, and time spent. Unlike ReadStatusManager (binary read/unread)
//  or ReadingStatsManager (aggregate analytics), this provides a fully
//  browsable history like browser history for RSS articles.
//

import Foundation

// MARK: - Notification

extension Notification.Name {
    static let readingHistoryDidChange = Notification.Name("ReadingHistoryDidChangeNotification")
}

// MARK: - HistoryEntry Model

/// A single reading history entry with rich metadata.
class HistoryEntry: NSObject, NSSecureCoding, Codable {
    static var supportsSecureCoding: Bool { return true }
    
    /// Article URL (unique key).
    let link: String
    
    /// Article title.
    let title: String
    
    /// Source feed name.
    let feedName: String
    
    /// When the article was first read.
    let readAt: Date
    
    /// When the article was last viewed (updated on re-visit).
    var lastVisitedAt: Date
    
    /// How many times the article was opened.
    var visitCount: Int
    
    /// 0.0 to 1.0, how far the user read (future-proof).
    var scrollProgress: Double
    
    /// Approximate time spent on the article in seconds.
    var timeSpentSeconds: Double
    
    init(link: String, title: String, feedName: String, readAt: Date = Date(),
         lastVisitedAt: Date? = nil, visitCount: Int = 1,
         scrollProgress: Double = 0.0, timeSpentSeconds: Double = 0.0) {
        self.link = link
        self.title = title
        self.feedName = feedName
        self.readAt = readAt
        self.lastVisitedAt = lastVisitedAt ?? readAt
        self.visitCount = visitCount
        self.scrollProgress = min(max(scrollProgress, 0.0), 1.0)
        self.timeSpentSeconds = max(timeSpentSeconds, 0.0)
        super.init()
    }
    
    // MARK: - NSSecureCoding
    
    private enum CodingKeys: String, CodingKey {
        case link, title, feedName, readAt, lastVisitedAt, visitCount, scrollProgress, timeSpentSeconds
    }
    
    private enum NSCodingKeys {
        static let link = "link"
        static let title = "title"
        static let feedName = "feedName"
        static let readAt = "readAt"
        static let lastVisitedAt = "lastVisitedAt"
        static let visitCount = "visitCount"
        static let scrollProgress = "scrollProgress"
        static let timeSpentSeconds = "timeSpentSeconds"
    }
    
    func encode(with coder: NSCoder) {
        coder.encode(link as NSString, forKey: NSCodingKeys.link)
        coder.encode(title as NSString, forKey: NSCodingKeys.title)
        coder.encode(feedName as NSString, forKey: NSCodingKeys.feedName)
        coder.encode(readAt as NSDate, forKey: NSCodingKeys.readAt)
        coder.encode(lastVisitedAt as NSDate, forKey: NSCodingKeys.lastVisitedAt)
        coder.encode(visitCount as NSNumber, forKey: NSCodingKeys.visitCount)
        coder.encode(scrollProgress as NSNumber, forKey: NSCodingKeys.scrollProgress)
        coder.encode(timeSpentSeconds as NSNumber, forKey: NSCodingKeys.timeSpentSeconds)
    }
    
    required init?(coder: NSCoder) {
        guard let link = coder.decodeObject(of: NSString.self, forKey: NSCodingKeys.link) as String?,
              let title = coder.decodeObject(of: NSString.self, forKey: NSCodingKeys.title) as String?,
              let feedName = coder.decodeObject(of: NSString.self, forKey: NSCodingKeys.feedName) as String?,
              let readAt = coder.decodeObject(of: NSDate.self, forKey: NSCodingKeys.readAt) as Date?,
              let lastVisitedAt = coder.decodeObject(of: NSDate.self, forKey: NSCodingKeys.lastVisitedAt) as Date?,
              let visitCountNum = coder.decodeObject(of: NSNumber.self, forKey: NSCodingKeys.visitCount),
              let scrollProgressNum = coder.decodeObject(of: NSNumber.self, forKey: NSCodingKeys.scrollProgress),
              let timeSpentNum = coder.decodeObject(of: NSNumber.self, forKey: NSCodingKeys.timeSpentSeconds) else {
            return nil
        }
        self.link = link
        self.title = title
        self.feedName = feedName
        self.readAt = readAt
        self.lastVisitedAt = lastVisitedAt
        self.visitCount = visitCountNum.intValue
        self.scrollProgress = scrollProgressNum.doubleValue
        self.timeSpentSeconds = timeSpentNum.doubleValue
        super.init()
    }
}

// MARK: - HistorySummary

/// Summary statistics for reading history display.
struct HistorySummary {
    let totalArticles: Int
    let totalVisits: Int
    let averageTimeSpentSeconds: Double
    let topFeed: String?
    let topFeedCount: Int
    let uniqueFeeds: Int
    let oldestEntry: Date?
    let newestEntry: Date?
    let daysWithActivity: Int
}

// MARK: - ReadingHistoryManager

class ReadingHistoryManager {
    
    // MARK: - Singleton
    
    static let shared = ReadingHistoryManager()
    
    // MARK: - Properties
    
    /// All history entries, sorted by lastVisitedAt descending (newest first).
    private(set) var entries: [HistoryEntry] = []
    
    /// Index mapping link → position in entries array for O(1) lookup.
    private var entryIndex: [String: Int] = [:]
    
    /// Maximum number of history entries to store.
    static let maxEntries = 2000
    
    /// UserDefaults key for persisting history.
    static let userDefaultsKey = "ReadingHistoryManager.entries"
    
    // MARK: - Initialization
    
    init() {
        load()
    }
    
    // MARK: - Recording
    
    /// Record a visit to an article. Creates new entry or updates existing.
    func recordVisit(link: String, title: String, feedName: String,
                     timeSpent: Double = 0, scrollProgress: Double = 0) {
        let now = Date()
        
        if let index = entryIndex[link] {
            // Update existing entry
            let entry = entries[index]
            entry.lastVisitedAt = now
            entry.visitCount += 1
            entry.timeSpentSeconds += max(timeSpent, 0)
            entry.scrollProgress = min(max(scrollProgress, 0.0), 1.0)
            
            // Move to front (newest first by lastVisitedAt)
            entries.remove(at: index)
            entries.insert(entry, at: 0)
            rebuildIndex()
        } else {
            // Create new entry
            let entry = HistoryEntry(
                link: link, title: title, feedName: feedName,
                readAt: now, lastVisitedAt: now, visitCount: 1,
                scrollProgress: min(max(scrollProgress, 0.0), 1.0),
                timeSpentSeconds: max(timeSpent, 0)
            )
            entries.insert(entry, at: 0)
            rebuildIndex()
            pruneIfNeeded()
        }
        
        save()
        NotificationCenter.default.post(name: .readingHistoryDidChange, object: nil)
    }
    
    /// Update time spent on current article (called when leaving article view).
    func updateTimeSpent(link: String, additionalSeconds: Double) {
        guard let index = entryIndex[link] else { return }
        entries[index].timeSpentSeconds += max(additionalSeconds, 0)
        save()
        NotificationCenter.default.post(name: .readingHistoryDidChange, object: nil)
    }
    
    /// Update scroll progress for an article.
    func updateScrollProgress(link: String, progress: Double) {
        guard let index = entryIndex[link] else { return }
        entries[index].scrollProgress = min(max(progress, 0.0), 1.0)
        save()
        NotificationCenter.default.post(name: .readingHistoryDidChange, object: nil)
    }
    
    // MARK: - Querying
    
    /// Get all history entries sorted by lastVisitedAt (newest first).
    func allEntries() -> [HistoryEntry] {
        return entries
    }
    
    /// Get entries for a specific date (by day).
    func entries(for date: Date) -> [HistoryEntry] {
        let calendar = Calendar.current
        let startOfDay = calendar.startOfDay(for: date)
        guard let endOfDay = calendar.date(byAdding: .day, value: 1, to: startOfDay) else {
            return []
        }
        return entries.filter { entry in
            entry.lastVisitedAt >= startOfDay && entry.lastVisitedAt < endOfDay
        }
    }
    
    /// Get entries within a date range (inclusive of both start and end days).
    func entries(from startDate: Date, to endDate: Date) -> [HistoryEntry] {
        let calendar = Calendar.current
        let rangeStart = calendar.startOfDay(for: startDate)
        guard let rangeEnd = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: endDate)) else {
            return []
        }
        return entries.filter { entry in
            entry.lastVisitedAt >= rangeStart && entry.lastVisitedAt < rangeEnd
        }
    }
    
    /// Get entries for a specific feed.
    func entries(forFeed feedName: String) -> [HistoryEntry] {
        let lowerFeed = feedName.lowercased()
        return entries.filter { $0.feedName.lowercased() == lowerFeed }
    }
    
    /// Search entries by title or feed name (case-insensitive).
    func search(query: String) -> [HistoryEntry] {
        let q = query.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return entries }
        return entries.filter {
            $0.title.lowercased().contains(q) ||
            $0.feedName.lowercased().contains(q)
        }
    }
    
    /// Get the N most frequently visited articles.
    func mostVisited(limit: Int = 10) -> [HistoryEntry] {
        let sorted = entries.sorted { $0.visitCount > $1.visitCount }
        return Array(sorted.prefix(limit))
    }
    
    /// Get the N most recently visited articles.
    func recentlyVisited(limit: Int = 20) -> [HistoryEntry] {
        return Array(entries.prefix(limit))
    }
    
    /// Get unique dates that have history entries (for section headers).
    /// Dates are normalized to start-of-day, sorted newest first.
    func datesWithEntries() -> [Date] {
        let calendar = Calendar.current
        var seen = Set<Date>()
        var dates: [Date] = []
        for entry in entries {
            let day = calendar.startOfDay(for: entry.lastVisitedAt)
            if seen.insert(day).inserted {
                dates.append(day)
            }
        }
        return dates.sorted(by: >)
    }
    
    /// Check if an article has been visited before.
    func hasVisited(link: String) -> Bool {
        return entryIndex[link] != nil
    }
    
    /// Get a specific entry by link.
    func entry(forLink link: String) -> HistoryEntry? {
        guard let index = entryIndex[link] else { return nil }
        return entries[index]
    }
    
    // MARK: - Statistics
    
    /// Total number of unique articles in history.
    var totalArticles: Int {
        return entries.count
    }
    
    /// Total number of visits (including re-visits).
    var totalVisits: Int {
        return entries.reduce(0) { $0 + $1.visitCount }
    }
    
    /// Average time spent per article.
    var averageTimeSpent: Double {
        guard !entries.isEmpty else { return 0 }
        let totalTime = entries.reduce(0.0) { $0 + $1.timeSpentSeconds }
        return totalTime / Double(entries.count)
    }
    
    /// Most-read feed name.
    var topFeed: String? {
        var feedCounts: [String: Int] = [:]
        for entry in entries {
            feedCounts[entry.feedName, default: 0] += entry.visitCount
        }
        return feedCounts.max(by: { $0.value < $1.value })?.key
    }
    
    /// Reading history summary for display.
    func historySummary() -> HistorySummary {
        var feedCounts: [String: Int] = [:]
        for entry in entries {
            feedCounts[entry.feedName, default: 0] += entry.visitCount
        }
        let topEntry = feedCounts.max(by: { $0.value < $1.value })
        
        let calendar = Calendar.current
        var activeDays = Set<Date>()
        for entry in entries {
            activeDays.insert(calendar.startOfDay(for: entry.lastVisitedAt))
        }
        
        return HistorySummary(
            totalArticles: entries.count,
            totalVisits: totalVisits,
            averageTimeSpentSeconds: averageTimeSpent,
            topFeed: topEntry?.key,
            topFeedCount: topEntry?.value ?? 0,
            uniqueFeeds: feedCounts.count,
            oldestEntry: entries.last?.readAt,
            newestEntry: entries.first?.lastVisitedAt,
            daysWithActivity: activeDays.count
        )
    }
    
    // MARK: - Management
    
    /// Delete a single entry. Returns true if an entry was deleted.
    @discardableResult
    func deleteEntry(link: String) -> Bool {
        guard let index = entryIndex[link] else { return false }
        entries.remove(at: index)
        rebuildIndex()
        save()
        NotificationCenter.default.post(name: .readingHistoryDidChange, object: nil)
        return true
    }
    
    /// Delete all entries for a specific date. Returns the number deleted.
    @discardableResult
    func deleteEntries(for date: Date) -> Int {
        let calendar = Calendar.current
        let startOfDay = calendar.startOfDay(for: date)
        guard let endOfDay = calendar.date(byAdding: .day, value: 1, to: startOfDay) else {
            return 0
        }
        let before = entries.count
        entries.removeAll { entry in
            entry.lastVisitedAt >= startOfDay && entry.lastVisitedAt < endOfDay
        }
        let removed = before - entries.count
        if removed > 0 {
            rebuildIndex()
            save()
            NotificationCenter.default.post(name: .readingHistoryDidChange, object: nil)
        }
        return removed
    }
    
    /// Delete all entries older than a given date. Returns the number deleted.
    @discardableResult
    func deleteEntriesBefore(date: Date) -> Int {
        let before = entries.count
        entries.removeAll { $0.lastVisitedAt < date }
        let removed = before - entries.count
        if removed > 0 {
            rebuildIndex()
            save()
            NotificationCenter.default.post(name: .readingHistoryDidChange, object: nil)
        }
        return removed
    }
    
    /// Clear all history.
    func clearAll() {
        entries.removeAll()
        entryIndex.removeAll()
        save()
        NotificationCenter.default.post(name: .readingHistoryDidChange, object: nil)
    }
    
    /// Export history as formatted text, grouped by date.
    func exportAsText() -> String {
        guard !entries.isEmpty else { return "No reading history." }
        
        let calendar = Calendar.current
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        
        let timeFormatter = DateFormatter()
        timeFormatter.dateStyle = .none
        timeFormatter.timeStyle = .short
        
        // Group entries by day
        var grouped: [Date: [HistoryEntry]] = [:]
        for entry in entries {
            let day = calendar.startOfDay(for: entry.lastVisitedAt)
            grouped[day, default: []].append(entry)
        }
        
        let sortedDays = grouped.keys.sorted(by: >)
        var lines: [String] = []
        
        for day in sortedDays {
            lines.append("## \(formatter.string(from: day))")
            if let dayEntries = grouped[day] {
                for entry in dayEntries {
                    let time = timeFormatter.string(from: entry.lastVisitedAt)
                    var line = "- [\(time)] \(entry.title) (\(entry.feedName))"
                    if entry.visitCount > 1 {
                        line += " — \(entry.visitCount) visits"
                    }
                    lines.append(line)
                }
            }
            lines.append("")
        }
        
        return lines.joined(separator: "\n")
    }
    
    /// Export history as JSON data.
    func exportAsJSON() -> Data? {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = .prettyPrinted
        return try? encoder.encode(entries)
    }
    
    // MARK: - Persistence
    
    private func save() {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        if let data = try? encoder.encode(entries) {
            UserDefaults.standard.set(data, forKey: ReadingHistoryManager.userDefaultsKey)
        }
    }
    
    private func load() {
        guard let data = UserDefaults.standard.data(forKey: ReadingHistoryManager.userDefaultsKey) else {
            entries = []
            entryIndex = [:]
            return
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        if let loaded = try? decoder.decode([HistoryEntry].self, from: data) {
            entries = loaded.sorted { $0.lastVisitedAt > $1.lastVisitedAt }
            rebuildIndex()
        } else {
            entries = []
            entryIndex = [:]
        }
    }
    
    /// Remove oldest entries (by readAt) when over maxEntries.
    /// Prunes by readAt rather than lastVisitedAt to preserve frequently re-visited articles.
    private func pruneIfNeeded() {
        guard entries.count > ReadingHistoryManager.maxEntries else { return }
        // Sort a copy by readAt ascending to find the oldest by original read date
        let sortedByReadAt = entries.sorted { $0.readAt < $1.readAt }
        let excess = entries.count - ReadingHistoryManager.maxEntries
        let linksToRemove = Set(sortedByReadAt.prefix(excess).map { $0.link })
        entries.removeAll { linksToRemove.contains($0.link) }
        rebuildIndex()
    }
    
    /// Rebuild the entryIndex from the entries array.
    private func rebuildIndex() {
        entryIndex.removeAll(keepingCapacity: true)
        for (index, entry) in entries.enumerated() {
            entryIndex[entry.link] = index
        }
    }
    
    // MARK: - Testing Support
    
    /// Reset to empty state (for tests).
    func reset() {
        entries.removeAll()
        entryIndex.removeAll()
        UserDefaults.standard.removeObject(forKey: ReadingHistoryManager.userDefaultsKey)
    }
    
    /// Reload from UserDefaults (for tests verifying persistence).
    func reloadFromDefaults() {
        load()
    }
}
