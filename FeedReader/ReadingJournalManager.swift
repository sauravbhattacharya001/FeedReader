//
//  ReadingJournalManager.swift
//  FeedReader
//
//  Auto-generated daily reading journal that combines reading history,
//  highlights, and notes into rich journal entries. Supports Markdown
//  export, reflection prompts, weekly/monthly digests, and streaks.
//

import Foundation

// MARK: - Notifications

extension Notification.Name {
    static let readingJournalDidChange = Notification.Name("ReadingJournalDidChangeNotification")
}

// MARK: - JournalEntry Model

/// A single daily journal entry summarizing reading activity.
class JournalEntry: NSObject, NSSecureCoding, Codable {
    static var supportsSecureCoding: Bool { true }

    /// Date key in "yyyy-MM-dd" format.
    let dateKey: String

    /// Articles read that day (links + titles).
    var articlesRead: [(link: String, title: String, feedName: String, timeSpent: Double)]

    /// Highlights created that day.
    var highlights: [(text: String, articleTitle: String, color: String)]

    /// Notes written that day.
    var notes: [(text: String, articleTitle: String)]

    /// Total reading time in seconds.
    var totalReadingTime: Double

    /// User's optional personal reflection.
    var reflection: String?

    /// Auto-generated mood tag based on content sentiment.
    var moodTag: String?

    /// When this entry was generated/last updated.
    var generatedAt: Date

    // Codable-friendly storage
    private var articlesData: [[String: String]]
    private var highlightsData: [[String: String]]
    private var notesData: [[String: String]]

    var articleCount: Int { articlesData.count }

    init(dateKey: String) {
        self.dateKey = dateKey
        self.articlesRead = []
        self.highlights = []
        self.notes = []
        self.totalReadingTime = 0
        self.reflection = nil
        self.moodTag = nil
        self.generatedAt = Date()
        self.articlesData = []
        self.highlightsData = []
        self.notesData = []
        super.init()
    }

    // MARK: - Article Management

    func addArticle(link: String, title: String, feedName: String, timeSpent: Double) {
        articlesRead.append((link: link, title: title, feedName: feedName, timeSpent: timeSpent))
        articlesData.append(["link": link, "title": title, "feedName": feedName, "timeSpent": String(timeSpent)])
        totalReadingTime += timeSpent
    }

    func addHighlight(text: String, articleTitle: String, color: String) {
        highlights.append((text: text, articleTitle: articleTitle, color: color))
        highlightsData.append(["text": text, "articleTitle": articleTitle, "color": color])
    }

    func addNote(text: String, articleTitle: String) {
        notes.append((text: text, articleTitle: articleTitle))
        notesData.append(["text": text, "articleTitle": articleTitle])
    }

    // MARK: - NSSecureCoding

    func encode(with coder: NSCoder) {
        coder.encode(dateKey as NSString, forKey: "dateKey")
        coder.encode(totalReadingTime, forKey: "totalReadingTime")
        coder.encode(reflection as NSString?, forKey: "reflection")
        coder.encode(moodTag as NSString?, forKey: "moodTag")
        coder.encode(generatedAt as NSDate, forKey: "generatedAt")
        if let data = try? JSONEncoder().encode(articlesData) {
            coder.encode(data as NSData, forKey: "articlesData")
        }
        if let data = try? JSONEncoder().encode(highlightsData) {
            coder.encode(data as NSData, forKey: "highlightsData")
        }
        if let data = try? JSONEncoder().encode(notesData) {
            coder.encode(data as NSData, forKey: "notesData")
        }
    }

    required init?(coder: NSCoder) {
        guard let dk = coder.decodeObject(of: NSString.self, forKey: "dateKey") as String? else { return nil }
        self.dateKey = dk
        self.totalReadingTime = coder.decodeDouble(forKey: "totalReadingTime")
        self.reflection = coder.decodeObject(of: NSString.self, forKey: "reflection") as String?
        self.moodTag = coder.decodeObject(of: NSString.self, forKey: "moodTag") as String?
        self.generatedAt = (coder.decodeObject(of: NSDate.self, forKey: "generatedAt") as Date?) ?? Date()

        if let ad = coder.decodeObject(of: NSData.self, forKey: "articlesData") as Data?,
           let decoded = try? JSONDecoder().decode([[String: String]].self, from: ad) {
            self.articlesData = decoded
        } else {
            self.articlesData = []
        }
        if let hd = coder.decodeObject(of: NSData.self, forKey: "highlightsData") as Data?,
           let decoded = try? JSONDecoder().decode([[String: String]].self, from: hd) {
            self.highlightsData = decoded
        } else {
            self.highlightsData = []
        }
        if let nd = coder.decodeObject(of: NSData.self, forKey: "notesData") as Data?,
           let decoded = try? JSONDecoder().decode([[String: String]].self, from: nd) {
            self.notesData = decoded
        } else {
            self.notesData = []
        }

        self.articlesRead = articlesData.map { d in
            (link: d["link"] ?? "", title: d["title"] ?? "",
             feedName: d["feedName"] ?? "", timeSpent: Double(d["timeSpent"] ?? "0") ?? 0)
        }
        self.highlights = highlightsData.map { d in
            (text: d["text"] ?? "", articleTitle: d["articleTitle"] ?? "", color: d["color"] ?? "Yellow")
        }
        self.notes = notesData.map { d in
            (text: d["text"] ?? "", articleTitle: d["articleTitle"] ?? "")
        }

        super.init()
    }

    // MARK: - Codable

    enum CodingKeys: String, CodingKey {
        case dateKey, totalReadingTime, reflection, moodTag, generatedAt
        case articlesData, highlightsData, notesData
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(dateKey, forKey: .dateKey)
        try container.encode(totalReadingTime, forKey: .totalReadingTime)
        try container.encodeIfPresent(reflection, forKey: .reflection)
        try container.encodeIfPresent(moodTag, forKey: .moodTag)
        try container.encode(generatedAt, forKey: .generatedAt)
        try container.encode(articlesData, forKey: .articlesData)
        try container.encode(highlightsData, forKey: .highlightsData)
        try container.encode(notesData, forKey: .notesData)
    }

    required init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.dateKey = try container.decode(String.self, forKey: .dateKey)
        self.totalReadingTime = try container.decode(Double.self, forKey: .totalReadingTime)
        self.reflection = try container.decodeIfPresent(String.self, forKey: .reflection)
        self.moodTag = try container.decodeIfPresent(String.self, forKey: .moodTag)
        self.generatedAt = try container.decode(Date.self, forKey: .generatedAt)
        self.articlesData = try container.decode([[String: String]].self, forKey: .articlesData)
        self.highlightsData = try container.decode([[String: String]].self, forKey: .highlightsData)
        self.notesData = try container.decode([[String: String]].self, forKey: .notesData)

        self.articlesRead = articlesData.map { d in
            (link: d["link"] ?? "", title: d["title"] ?? "",
             feedName: d["feedName"] ?? "", timeSpent: Double(d["timeSpent"] ?? "0") ?? 0)
        }
        self.highlights = highlightsData.map { d in
            (text: d["text"] ?? "", articleTitle: d["articleTitle"] ?? "", color: d["color"] ?? "Yellow")
        }
        self.notes = notesData.map { d in
            (text: d["text"] ?? "", articleTitle: d["articleTitle"] ?? "")
        }

        super.init()
    }
}

// MARK: - ReadingJournalManager

class ReadingJournalManager {

    // MARK: - Singleton

    static let shared = ReadingJournalManager()

    // MARK: - Constants

    /// Maximum journal entries to keep (roughly 1 year).
    static let maxEntries = 365

    private static let userDefaultsKey = "ReadingJournalManager.entries"

    // MARK: - Reflection Prompts

    private static let reflectionPrompts = [
        "What was the most surprising thing you read today?",
        "Did anything you read change your perspective?",
        "Which article would you recommend to a friend?",
        "What questions did today's reading raise for you?",
        "How does today's reading connect to something you already knew?",
        "What's one thing you want to explore further?",
        "Did any article challenge your assumptions?",
        "What was the most useful takeaway from today's reading?",
        "If you could discuss one article with anyone, which would it be?",
        "What pattern are you noticing in the topics you read about?",
        "Did anything you read today inspire a new idea?",
        "What would you tell your past self about what you learned today?",
        "Which feed surprised you the most today?",
        "What's the connection between the articles you read today?",
        "How would you summarize today's reading in one sentence?"
    ]

    // MARK: - Properties

    private var entriesByDate: [String: JournalEntry]
    private let dateFormatter: DateFormatter

    // MARK: - Initialization

    private init() {
        self.entriesByDate = [:]
        self.dateFormatter = DateFormatter()
        self.dateFormatter.dateFormat = "yyyy-MM-dd"
        self.dateFormatter.timeZone = TimeZone.current
        loadEntries()
    }

    // MARK: - Date Helpers

    private func dateKey(for date: Date) -> String {
        return dateFormatter.string(from: date)
    }

    private func date(from key: String) -> Date? {
        return dateFormatter.date(from: key)
    }

    /// Returns today's date key.
    var todayKey: String {
        return dateKey(for: Date())
    }

    // MARK: - Entry Access

    /// Get entry for a specific date. Returns nil if no entry exists.
    func entry(for date: Date) -> JournalEntry? {
        return entriesByDate[dateKey(for: date)]
    }

    /// Get entry by date key string.
    func entry(forKey key: String) -> JournalEntry? {
        return entriesByDate[key]
    }

    /// Get today's entry, creating one if needed.
    func todayEntry() -> JournalEntry {
        let key = todayKey
        if let existing = entriesByDate[key] {
            return existing
        }
        let entry = JournalEntry(dateKey: key)
        entriesByDate[key] = entry
        enforceCapacity()
        save()
        return entry
    }

    /// All entries sorted by date, newest first.
    var allEntries: [JournalEntry] {
        return entriesByDate.values.sorted { $0.dateKey > $1.dateKey }
    }

    /// Number of journal entries.
    var entryCount: Int {
        return entriesByDate.count
    }

    // MARK: - Record Reading Activity

    /// Record an article read into today's journal.
    @discardableResult
    func recordArticleRead(link: String, title: String, feedName: String, timeSpent: Double = 0) -> JournalEntry {
        let entry = todayEntry()
        // Avoid duplicates
        if !entry.articlesRead.contains(where: { $0.link == link }) {
            entry.addArticle(link: link, title: title, feedName: feedName, timeSpent: timeSpent)
            entry.generatedAt = Date()
            save()
            NotificationCenter.default.post(name: .readingJournalDidChange, object: nil)
        }
        return entry
    }

    /// Record a highlight into today's journal.
    @discardableResult
    func recordHighlight(text: String, articleTitle: String, color: String = "Yellow") -> JournalEntry {
        let entry = todayEntry()
        entry.addHighlight(text: text, articleTitle: articleTitle, color: color)
        entry.generatedAt = Date()
        save()
        NotificationCenter.default.post(name: .readingJournalDidChange, object: nil)
        return entry
    }

    /// Record a note into today's journal.
    @discardableResult
    func recordNote(text: String, articleTitle: String) -> JournalEntry {
        let entry = todayEntry()
        entry.addNote(text: text, articleTitle: articleTitle)
        entry.generatedAt = Date()
        save()
        NotificationCenter.default.post(name: .readingJournalDidChange, object: nil)
        return entry
    }

    // MARK: - Reflections

    /// Set a personal reflection on a journal entry.
    func setReflection(_ text: String, for date: Date) {
        guard let entry = entriesByDate[dateKey(for: date)] else { return }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        entry.reflection = trimmed.isEmpty ? nil : String(trimmed.prefix(2000))
        entry.generatedAt = Date()
        save()
        NotificationCenter.default.post(name: .readingJournalDidChange, object: nil)
    }

    /// Get a random reflection prompt for today.
    func todayReflectionPrompt() -> String {
        let dayOfYear = Calendar.current.ordinality(of: .day, in: .year, for: Date()) ?? 0
        let index = dayOfYear % ReadingJournalManager.reflectionPrompts.count
        return ReadingJournalManager.reflectionPrompts[index]
    }

    // MARK: - Mood Tags

    /// Set a mood tag on a journal entry (e.g. "curious", "inspired", "overwhelmed").
    func setMoodTag(_ mood: String, for date: Date) {
        guard let entry = entriesByDate[dateKey(for: date)] else { return }
        let trimmed = mood.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        entry.moodTag = trimmed.isEmpty ? nil : String(trimmed.prefix(30))
        entry.generatedAt = Date()
        save()
        NotificationCenter.default.post(name: .readingJournalDidChange, object: nil)
    }

    /// Mood frequency across all entries.
    func moodFrequency() -> [(mood: String, count: Int)] {
        var freq: [String: Int] = [:]
        for entry in entriesByDate.values {
            if let mood = entry.moodTag {
                freq[mood, default: 0] += 1
            }
        }
        return freq.map { (mood: $0.key, count: $0.value) }.sorted { $0.count > $1.count }
    }

    // MARK: - Streaks

    /// Current journaling streak (consecutive days with entries).
    var currentStreak: Int {
        let calendar = Calendar.current
        var streak = 0
        var checkDate = Date()

        while true {
            let key = dateKey(for: checkDate)
            guard let entry = entriesByDate[key], entry.articleCount > 0 else { break }
            streak += 1
            guard let prev = calendar.date(byAdding: .day, value: -1, to: checkDate) else { break }
            checkDate = prev
        }
        return streak
    }

    /// Longest journaling streak ever.
    var longestStreak: Int {
        let sortedKeys = entriesByDate.keys.sorted()
        guard !sortedKeys.isEmpty else { return 0 }

        let calendar = Calendar.current
        var longest = 1
        var current = 1

        for i in 1..<sortedKeys.count {
            guard let prev = date(from: sortedKeys[i - 1]),
                  let curr = date(from: sortedKeys[i]) else { continue }
            let diff = calendar.dateComponents([.day], from: prev, to: curr).day ?? 0
            if diff == 1 {
                current += 1
                longest = max(longest, current)
            } else {
                current = 1
            }
        }
        return longest
    }

    // MARK: - Weekly Digest

    /// Generate a weekly digest for the week containing the given date.
    func weeklyDigest(containing date: Date = Date()) -> WeeklyDigest {
        let calendar = Calendar.current
        let weekStart = calendar.date(from: calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: date))!
        let weekEnd = calendar.date(byAdding: .day, value: 6, to: weekStart)!

        var entries: [JournalEntry] = []
        var checkDate = weekStart
        while checkDate <= weekEnd {
            if let entry = entriesByDate[dateKey(for: checkDate)] {
                entries.append(entry)
            }
            checkDate = calendar.date(byAdding: .day, value: 1, to: checkDate)!
        }

        let totalArticles = entries.reduce(0) { $0 + $1.articleCount }
        let totalTime = entries.reduce(0.0) { $0 + $1.totalReadingTime }
        let totalHighlights = entries.reduce(0) { $0 + $1.highlights.count }
        let totalNotes = entries.reduce(0) { $0 + $1.notes.count }

        // Most-read feeds
        var feedCounts: [String: Int] = [:]
        for entry in entries {
            for article in entry.articlesRead {
                feedCounts[article.feedName, default: 0] += 1
            }
        }
        let topFeeds = feedCounts.sorted { $0.value > $1.value }.prefix(5).map { $0.key }

        return WeeklyDigest(
            weekStart: weekStart,
            weekEnd: weekEnd,
            daysActive: entries.count,
            totalArticles: totalArticles,
            totalReadingTime: totalTime,
            totalHighlights: totalHighlights,
            totalNotes: totalNotes,
            topFeeds: Array(topFeeds),
            moods: entries.compactMap { $0.moodTag }
        )
    }

    // MARK: - Monthly Summary

    /// Generate a monthly summary.
    func monthlySummary(year: Int, month: Int) -> MonthlySummary {
        let calendar = Calendar.current
        var components = DateComponents()
        components.year = year
        components.month = month
        components.day = 1
        let monthStart = calendar.date(from: components)!
        let range = calendar.range(of: .day, in: .month, for: monthStart)!

        var entries: [JournalEntry] = []
        for day in range {
            components.day = day
            if let d = calendar.date(from: components), let entry = entriesByDate[dateKey(for: d)] {
                entries.append(entry)
            }
        }

        let totalArticles = entries.reduce(0) { $0 + $1.articleCount }
        let totalTime = entries.reduce(0.0) { $0 + $1.totalReadingTime }
        let avgArticlesPerDay = entries.isEmpty ? 0.0 : Double(totalArticles) / Double(entries.count)

        var feedCounts: [String: Int] = [:]
        for entry in entries {
            for article in entry.articlesRead {
                feedCounts[article.feedName, default: 0] += 1
            }
        }
        let topFeeds = feedCounts.sorted { $0.value > $1.value }.prefix(5).map { $0.key }

        return MonthlySummary(
            year: year,
            month: month,
            daysActive: entries.count,
            totalDays: range.count,
            totalArticles: totalArticles,
            totalReadingTime: totalTime,
            averageArticlesPerDay: avgArticlesPerDay,
            topFeeds: Array(topFeeds),
            reflectionCount: entries.filter { $0.reflection != nil }.count,
            moods: entries.compactMap { $0.moodTag }
        )
    }

    // MARK: - Markdown Export

    /// Export a single journal entry as Markdown.
    func exportEntryAsMarkdown(_ entry: JournalEntry) -> String {
        var md = "# 📖 Reading Journal — \(entry.dateKey)\n\n"

        // Summary line
        let minutes = Int(entry.totalReadingTime / 60)
        md += "**\(entry.articleCount) articles** read"
        if minutes > 0 { md += " · \(minutes) min" }
        if !entry.highlights.isEmpty { md += " · \(entry.highlights.count) highlights" }
        if !entry.notes.isEmpty { md += " · \(entry.notes.count) notes" }
        md += "\n\n"

        // Mood
        if let mood = entry.moodTag {
            md += "**Mood:** \(mood)\n\n"
        }

        // Articles
        if !entry.articlesRead.isEmpty {
            md += "## 📰 Articles Read\n\n"
            for (i, article) in entry.articlesRead.enumerated() {
                let time = Int(article.timeSpent / 60)
                md += "\(i + 1). **\(article.title)**"
                if !article.feedName.isEmpty { md += " _(\(article.feedName))_" }
                if time > 0 { md += " — \(time) min" }
                md += "\n"
            }
            md += "\n"
        }

        // Highlights
        if !entry.highlights.isEmpty {
            md += "## ✨ Highlights\n\n"
            for hl in entry.highlights {
                md += "> \(hl.text)\n"
                md += "> — _\(hl.articleTitle)_ [\(hl.color)]\n\n"
            }
        }

        // Notes
        if !entry.notes.isEmpty {
            md += "## 📝 Notes\n\n"
            for note in entry.notes {
                md += "**\(note.articleTitle):**\n\(note.text)\n\n"
            }
        }

        // Reflection
        if let reflection = entry.reflection {
            md += "## 💭 Reflection\n\n\(reflection)\n\n"
        }

        md += "---\n_Generated by FeedReader Reading Journal_\n"
        return md
    }

    /// Export a date range as a combined Markdown document.
    func exportRangeAsMarkdown(from startDate: Date, to endDate: Date) -> String {
        let calendar = Calendar.current
        var md = "# 📖 Reading Journal\n\n"
        md += "_\(dateKey(for: startDate)) to \(dateKey(for: endDate))_\n\n"

        var checkDate = startDate
        var entryCount = 0
        while checkDate <= endDate {
            if let entry = entriesByDate[dateKey(for: checkDate)], entry.articleCount > 0 {
                md += exportEntryAsMarkdown(entry)
                md += "\n\n"
                entryCount += 1
            }
            checkDate = calendar.date(byAdding: .day, value: 1, to: checkDate)!
        }

        if entryCount == 0 {
            md += "_No journal entries in this period._\n"
        }
        return md
    }

    /// Export all entries as JSON Data.
    func exportAsJSON() -> Data? {
        let entries = allEntries
        return try? JSONEncoder().encode(entries)
    }

    // MARK: - Search

    /// Search journal entries by keyword across articles, highlights, notes, and reflections.
    func search(query: String) -> [JournalEntry] {
        let q = query.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return [] }

        return allEntries.filter { entry in
            // Check articles
            if entry.articlesRead.contains(where: {
                $0.title.lowercased().contains(q) || $0.feedName.lowercased().contains(q)
            }) { return true }

            // Check highlights
            if entry.highlights.contains(where: { $0.text.lowercased().contains(q) }) { return true }

            // Check notes
            if entry.notes.contains(where: {
                $0.text.lowercased().contains(q) || $0.articleTitle.lowercased().contains(q)
            }) { return true }

            // Check reflection
            if let r = entry.reflection, r.lowercased().contains(q) { return true }

            // Check mood
            if let m = entry.moodTag, m.contains(q) { return true }

            return false
        }
    }

    // MARK: - Statistics

    /// Overall journal statistics.
    func statistics() -> JournalStatistics {
        let entries = allEntries
        let totalArticles = entries.reduce(0) { $0 + $1.articleCount }
        let totalTime = entries.reduce(0.0) { $0 + $1.totalReadingTime }
        let totalHighlights = entries.reduce(0) { $0 + $1.highlights.count }
        let totalNotes = entries.reduce(0) { $0 + $1.notes.count }
        let reflections = entries.filter { $0.reflection != nil }.count
        let avgArticlesPerDay = entries.isEmpty ? 0.0 : Double(totalArticles) / Double(entries.count)

        return JournalStatistics(
            totalEntries: entries.count,
            totalArticles: totalArticles,
            totalReadingTime: totalTime,
            totalHighlights: totalHighlights,
            totalNotes: totalNotes,
            totalReflections: reflections,
            averageArticlesPerDay: avgArticlesPerDay,
            currentStreak: currentStreak,
            longestStreak: longestStreak
        )
    }

    // MARK: - Delete

    /// Remove a journal entry for a specific date.
    func removeEntry(for date: Date) {
        let key = dateKey(for: date)
        entriesByDate.removeValue(forKey: key)
        save()
        NotificationCenter.default.post(name: .readingJournalDidChange, object: nil)
    }

    /// Clear all journal entries.
    func clearAll() {
        entriesByDate.removeAll()
        save()
        NotificationCenter.default.post(name: .readingJournalDidChange, object: nil)
    }

    // MARK: - Persistence

    private func save() {
        guard let data = try? NSKeyedArchiver.archivedData(
            withRootObject: entriesByDate as NSDictionary,
            requiringSecureCoding: true
        ) else { return }
        UserDefaults.standard.set(data, forKey: ReadingJournalManager.userDefaultsKey)
    }

    private func loadEntries() {
        guard let data = UserDefaults.standard.data(forKey: ReadingJournalManager.userDefaultsKey),
              let dict = try? NSKeyedUnarchiver.unarchivedObject(
                ofClasses: [NSDictionary.self, NSString.self, JournalEntry.self],
                from: data
              ) as? [String: JournalEntry] else { return }
        self.entriesByDate = dict
    }

    private func enforceCapacity() {
        while entriesByDate.count > ReadingJournalManager.maxEntries {
            if let oldest = entriesByDate.keys.sorted().first {
                entriesByDate.removeValue(forKey: oldest)
            }
        }
    }
}

// MARK: - Support Types

struct WeeklyDigest {
    let weekStart: Date
    let weekEnd: Date
    let daysActive: Int
    let totalArticles: Int
    let totalReadingTime: Double
    let totalHighlights: Int
    let totalNotes: Int
    let topFeeds: [String]
    let moods: [String]

    var averageArticlesPerDay: Double {
        daysActive == 0 ? 0 : Double(totalArticles) / Double(daysActive)
    }

    var readingTimeMinutes: Int {
        Int(totalReadingTime / 60)
    }
}

struct MonthlySummary {
    let year: Int
    let month: Int
    let daysActive: Int
    let totalDays: Int
    let totalArticles: Int
    let totalReadingTime: Double
    let averageArticlesPerDay: Double
    let topFeeds: [String]
    let reflectionCount: Int
    let moods: [String]

    var readingTimeHours: Double {
        totalReadingTime / 3600.0
    }

    var completionRate: Double {
        totalDays == 0 ? 0 : Double(daysActive) / Double(totalDays)
    }
}

struct JournalStatistics {
    let totalEntries: Int
    let totalArticles: Int
    let totalReadingTime: Double
    let totalHighlights: Int
    let totalNotes: Int
    let totalReflections: Int
    let averageArticlesPerDay: Double
    let currentStreak: Int
    let longestStreak: Int

    var readingTimeHours: Double {
        totalReadingTime / 3600.0
    }
}
