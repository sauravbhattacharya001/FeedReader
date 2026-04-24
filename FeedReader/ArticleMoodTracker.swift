//
//  ArticleMoodTracker.swift
//  FeedReader
//
//  Lets users tag how an article made them feel and tracks emotional
//  patterns across their reading history. Supports predefined moods
//  (inspired, anxious, informed, amused, sad, angry, hopeful, bored,
//  curious, surprised) plus custom moods. Provides analytics:
//  mood distribution, mood-over-time trends, most common mood per
//  feed, and mood-based article recommendations.
//
//  Features:
//  - Tag articles with one or more moods
//  - Predefined mood palette with emoji
//  - Custom mood support
//  - Mood distribution stats (pie-chart-ready data)
//  - Daily/weekly mood timeline
//  - Per-feed mood profile
//  - Find articles by mood
//  - Export mood data as JSON or CSV
//
//  Persistence: JSON file in Documents directory.
//

import Foundation

// MARK: - Notifications

extension Notification.Name {
    /// Posted when mood data changes (mood tagged, removed, or cleared).
    static let articleMoodDidChange = Notification.Name("ArticleMoodDidChangeNotification")
}

// MARK: - Mood

/// Represents a mood that can be associated with an article.
public struct Mood: Codable, Equatable, Hashable {
    public let identifier: String
    public let emoji: String
    public let label: String

    public init(identifier: String, emoji: String, label: String) {
        self.identifier = identifier
        self.emoji = emoji
        self.label = label
    }
}

// MARK: - Predefined Moods

public extension Mood {
    static let inspired   = Mood(identifier: "inspired",   emoji: "✨", label: "Inspired")
    static let anxious    = Mood(identifier: "anxious",    emoji: "😰", label: "Anxious")
    static let informed   = Mood(identifier: "informed",   emoji: "🧠", label: "Informed")
    static let amused     = Mood(identifier: "amused",     emoji: "😂", label: "Amused")
    static let sad        = Mood(identifier: "sad",        emoji: "😢", label: "Sad")
    static let angry      = Mood(identifier: "angry",      emoji: "😡", label: "Angry")
    static let hopeful    = Mood(identifier: "hopeful",    emoji: "🌈", label: "Hopeful")
    static let bored      = Mood(identifier: "bored",      emoji: "😴", label: "Bored")
    static let curious    = Mood(identifier: "curious",    emoji: "🤔", label: "Curious")
    static let surprised  = Mood(identifier: "surprised",  emoji: "😲", label: "Surprised")
    static let calm       = Mood(identifier: "calm",       emoji: "😌", label: "Calm")
    static let motivated  = Mood(identifier: "motivated",  emoji: "💪", label: "Motivated")

    /// All predefined moods.
    static let all: [Mood] = [
        .inspired, .anxious, .informed, .amused, .sad, .angry,
        .hopeful, .bored, .curious, .surprised, .calm, .motivated
    ]
}

// MARK: - Mood Entry

/// A single mood-tagging event for an article.
public struct MoodEntry: Codable, Equatable {
    public let articleURL: String
    public let articleTitle: String
    public let feedTitle: String
    public let mood: Mood
    public let timestamp: Date
    public let note: String?

    public init(articleURL: String, articleTitle: String, feedTitle: String,
                mood: Mood, timestamp: Date = Date(), note: String? = nil) {
        self.articleURL = articleURL
        self.articleTitle = articleTitle
        self.feedTitle = feedTitle
        self.mood = mood
        self.timestamp = timestamp
        self.note = note
    }
}

// MARK: - Mood Stats

/// Aggregated mood statistics.
public struct MoodDistribution {
    public let mood: Mood
    public let count: Int
    public let percentage: Double
}

/// Mood data for a specific time period.
public struct MoodTimeline {
    public let date: Date
    public let moods: [Mood: Int]

    /// The dominant mood for this period.
    public var dominantMood: Mood? {
        moods.max(by: { $0.value < $1.value })?.key
    }
}

/// Mood profile for a specific feed.
public struct FeedMoodProfile {
    public let feedTitle: String
    public let totalEntries: Int
    public let distribution: [MoodDistribution]

    /// The most common mood for this feed.
    public var dominantMood: Mood? {
        distribution.max(by: { $0.count < $1.count })?.mood
    }
}

// MARK: - ArticleMoodTracker

/// Tracks moods associated with articles and provides analytics.
public final class ArticleMoodTracker {

    // MARK: - Singleton

    public static let shared = ArticleMoodTracker()

    // MARK: - Storage

    private var entries: [MoodEntry] = []
    private var customMoods: [Mood] = []
    private let storageURL: URL

    // MARK: - Init

    public init() {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        storageURL = docs.appendingPathComponent("article_mood_tracker.json")
        load()
    }

    // MARK: - Tagging

    /// Tag an article with a mood. Multiple moods per article are allowed.
    @discardableResult
    public func tagArticle(url: String, title: String, feedTitle: String,
                           mood: Mood, note: String? = nil) -> MoodEntry {
        let entry = MoodEntry(articleURL: url, articleTitle: title,
                              feedTitle: feedTitle, mood: mood, note: note)
        entries.append(entry)
        save()
        NotificationCenter.default.post(name: .articleMoodDidChange, object: self)
        return entry
    }

    /// Remove all mood tags for a specific article.
    public func removeMoods(forArticleURL url: String) {
        entries.removeAll { $0.articleURL == url }
        save()
        NotificationCenter.default.post(name: .articleMoodDidChange, object: self)
    }

    /// Remove a specific mood tag from an article.
    public func removeMood(_ mood: Mood, fromArticleURL url: String) {
        entries.removeAll { $0.articleURL == url && $0.mood == mood }
        save()
        NotificationCenter.default.post(name: .articleMoodDidChange, object: self)
    }

    /// Get all moods tagged for a specific article.
    public func moods(forArticleURL url: String) -> [MoodEntry] {
        entries.filter { $0.articleURL == url }
    }

    // MARK: - Custom Moods

    /// Register a custom mood.
    public func addCustomMood(_ mood: Mood) {
        guard !customMoods.contains(mood) else { return }
        customMoods.append(mood)
        save()
    }

    /// All available moods (predefined + custom).
    public var availableMoods: [Mood] {
        Mood.all + customMoods
    }

    // MARK: - Analytics

    /// Overall mood distribution across all entries.
    public func moodDistribution() -> [MoodDistribution] {
        let total = entries.count
        guard total > 0 else { return [] }

        var counts: [String: (Mood, Int)] = [:]
        for entry in entries {
            let key = entry.mood.identifier
            if let existing = counts[key] {
                counts[key] = (existing.0, existing.1 + 1)
            } else {
                counts[key] = (entry.mood, 1)
            }
        }

        return counts.values
            .map { MoodDistribution(mood: $0.0, count: $0.1,
                                     percentage: Double($0.1) / Double(total) * 100.0) }
            .sorted { $0.count > $1.count }
    }

    /// Daily mood timeline for the last N days (default 30).
    public func dailyTimeline(days: Int = 30) -> [MoodTimeline] {
        let calendar = Calendar.current
        let now = Date()
        var result: [MoodTimeline] = []

        for dayOffset in 0..<days {
            guard let date = calendar.date(byAdding: .day, value: -dayOffset, to: now) else { continue }
            let dayStart = calendar.startOfDay(for: date)
            guard let dayEnd = calendar.date(byAdding: .day, value: 1, to: dayStart) else { continue }

            let dayEntries = entries.filter { $0.timestamp >= dayStart && $0.timestamp < dayEnd }
            var moods: [Mood: Int] = [:]
            for entry in dayEntries {
                moods[entry.mood, default: 0] += 1
            }

            result.append(MoodTimeline(date: dayStart, moods: moods))
        }

        return result.reversed()
    }

    /// Weekly mood timeline for the last N weeks (default 12).
    public func weeklyTimeline(weeks: Int = 12) -> [MoodTimeline] {
        let calendar = Calendar.current
        let now = Date()
        var result: [MoodTimeline] = []

        for weekOffset in 0..<weeks {
            guard let weekStart = calendar.date(byAdding: .weekOfYear, value: -weekOffset, to: now) else { continue }
            let start = calendar.startOfDay(for: calendar.dateInterval(of: .weekOfYear, for: weekStart)?.start ?? weekStart)
            guard let end = calendar.date(byAdding: .weekOfYear, value: 1, to: start) else { continue }

            let weekEntries = entries.filter { $0.timestamp >= start && $0.timestamp < end }
            var moods: [Mood: Int] = [:]
            for entry in weekEntries {
                moods[entry.mood, default: 0] += 1
            }

            result.append(MoodTimeline(date: start, moods: moods))
        }

        return result.reversed()
    }

    /// Mood profile per feed.
    public func feedMoodProfiles() -> [FeedMoodProfile] {
        let grouped = Dictionary(grouping: entries, by: { $0.feedTitle })
        return grouped.map { feedTitle, feedEntries in
            let total = feedEntries.count
            var counts: [String: (Mood, Int)] = [:]
            for entry in feedEntries {
                let key = entry.mood.identifier
                if let existing = counts[key] {
                    counts[key] = (existing.0, existing.1 + 1)
                } else {
                    counts[key] = (entry.mood, 1)
                }
            }
            let dist = counts.values
                .map { MoodDistribution(mood: $0.0, count: $0.1,
                                         percentage: Double($0.1) / Double(total) * 100.0) }
                .sorted { $0.count > $1.count }
            return FeedMoodProfile(feedTitle: feedTitle, totalEntries: total, distribution: dist)
        }.sorted { $0.totalEntries > $1.totalEntries }
    }

    /// Find articles tagged with a specific mood.
    public func articles(withMood mood: Mood) -> [MoodEntry] {
        entries.filter { $0.mood == mood }
            .sorted { $0.timestamp > $1.timestamp }
    }

    /// Get the most recent mood entries.
    public func recentEntries(limit: Int = 20) -> [MoodEntry] {
        Array(entries.sorted { $0.timestamp > $1.timestamp }.prefix(limit))
    }

    /// Total number of mood tags.
    public var totalEntries: Int { entries.count }

    /// Number of unique articles with mood tags.
    public var uniqueArticlesTagged: Int {
        Set(entries.map { $0.articleURL }).count
    }

    // MARK: - Export

    /// Export all mood data as JSON.
    public func exportJSON() -> Data? {
        struct ExportData: Codable {
            let exportDate: Date
            let totalEntries: Int
            let customMoods: [Mood]
            let entries: [MoodEntry]
        }

        let data = ExportData(exportDate: Date(), totalEntries: entries.count,
                              customMoods: customMoods, entries: entries)
        return try? JSONCoding.iso8601PrettyEncoder.encode(data)
    }

    /// Export mood data as CSV string.
    public func exportCSV() -> String {
        var csv = "timestamp,article_url,article_title,feed_title,mood_id,mood_emoji,mood_label,note\n"
        let formatter = ISO8601DateFormatter()

        for entry in entries.sorted(by: { $0.timestamp < $1.timestamp }) {
            let ts = formatter.string(from: entry.timestamp)
            let url = entry.articleURL.replacingOccurrences(of: ",", with: "%2C")
            let title = entry.articleTitle.replacingOccurrences(of: "\"", with: "\"\"")
            let feed = entry.feedTitle.replacingOccurrences(of: "\"", with: "\"\"")
            let note = (entry.note ?? "").replacingOccurrences(of: "\"", with: "\"\"")
            csv += "\(ts),\(url),\"\(title)\",\"\(feed)\",\(entry.mood.identifier),\(entry.mood.emoji),\(entry.mood.label),\"\(note)\"\n"
        }

        return csv
    }

    // MARK: - Clear

    /// Clear all mood data.
    public func clearAll() {
        entries.removeAll()
        customMoods.removeAll()
        save()
        NotificationCenter.default.post(name: .articleMoodDidChange, object: self)
    }

    // MARK: - Persistence

    private struct StorageModel: Codable {
        let entries: [MoodEntry]
        let customMoods: [Mood]
    }

    private func save() {
        let model = StorageModel(entries: entries, customMoods: customMoods)
        if let data = try? JSONCoding.iso8601Encoder.encode(model) {
            try? data.write(to: storageURL, options: .atomic)
        }
    }

    private func load() {
        guard let data = try? Data(contentsOf: storageURL) else { return }
        if let model = try? JSONCoding.iso8601Decoder.decode(StorageModel.self, from: data) {
            entries = model.entries
            customMoods = model.customMoods
        }
    }
}
