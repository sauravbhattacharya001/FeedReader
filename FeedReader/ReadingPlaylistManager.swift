//
//  ReadingPlaylistManager.swift
//  FeedReader
//
//  Named reading playlists for organizing articles into themed
//  sequences. Like music playlists but for articles — create
//  "Morning News", "Research Papers", "Weekend Reads", etc.
//
//  Features:
//  - Create, rename, delete named playlists
//  - Add/remove/reorder articles within playlists
//  - Playback position tracking (current article index)
//  - Auto-advance to next article on completion
//  - Shuffle mode for randomized reading order
//  - Playlist duration estimates based on reading speed
//  - Smart playlists: auto-populate by topic/feed/keyword rules
//  - Playlist sharing via export/import (JSON)
//  - Playlist statistics: completion rate, time spent, articles read
//
//  Persistence: UserDefaults via Codable.
//

import Foundation

// MARK: - Notifications

extension Notification.Name {
    /// Posted when any playlist is created, modified, or deleted.
    static let readingPlaylistsDidChange = Notification.Name("ReadingPlaylistsDidChangeNotification")
}

// MARK: - PlaylistItem

/// A single article entry in a playlist.
struct PlaylistItem: Codable, Equatable {
    let id: String
    let articleLink: String
    let articleTitle: String
    let sourceFeedName: String
    let wordCount: Int
    let addedDate: Date
    var isCompleted: Bool
    var completedDate: Date?
    /// Time in seconds the user actually spent reading this item.
    var timeSpentSeconds: Double?

    init(articleLink: String, articleTitle: String, sourceFeedName: String = "", wordCount: Int = 0) {
        self.id = UUID().uuidString
        self.articleLink = articleLink
        self.articleTitle = articleTitle
        self.sourceFeedName = sourceFeedName
        self.wordCount = wordCount
        self.addedDate = Date()
        self.isCompleted = false
        self.completedDate = nil
        self.timeSpentSeconds = nil
    }

    static func == (lhs: PlaylistItem, rhs: PlaylistItem) -> Bool {
        return lhs.id == rhs.id
    }
}

// MARK: - SmartPlaylistRule

/// Rule for auto-populating a smart playlist.
struct SmartPlaylistRule: Codable, Equatable {
    enum RuleType: String, Codable, CaseIterable {
        case topic       // Match by topic/category
        case feed        // Match by source feed name
        case keyword     // Match by keyword in title/body
        case minWordCount // Minimum word count
        case maxWordCount // Maximum word count
    }

    let type: RuleType
    let value: String
    /// Maximum number of articles to auto-add (0 = unlimited).
    let limit: Int

    init(type: RuleType, value: String, limit: Int = 0) {
        self.type = type
        self.value = value
        self.limit = limit
    }
}

// MARK: - ReadingPlaylist

/// A named, ordered collection of articles for sequential reading.
struct ReadingPlaylist: Codable {
    let id: String
    var name: String
    var description: String
    let createdDate: Date
    var modifiedDate: Date
    var items: [PlaylistItem]
    /// Index of the current article in the playback sequence.
    var currentIndex: Int
    /// Whether shuffle mode is active.
    var isShuffled: Bool
    /// Shuffled order indices (only used when isShuffled is true).
    var shuffleOrder: [Int]
    /// Smart playlist rules (empty = manual playlist).
    var smartRules: [SmartPlaylistRule]
    /// Custom emoji icon for the playlist.
    var icon: String

    init(name: String, description: String = "", icon: String = "📚") {
        self.id = UUID().uuidString
        self.name = name
        self.description = description
        self.createdDate = Date()
        self.modifiedDate = Date()
        self.items = []
        self.currentIndex = 0
        self.isShuffled = false
        self.shuffleOrder = []
        self.smartRules = []
        self.icon = icon
    }

    // MARK: - Computed Properties

    /// Number of completed items.
    var completedCount: Int {
        return items.filter { $0.isCompleted }.count
    }

    /// Completion percentage (0.0 - 1.0).
    var completionRate: Double {
        guard !items.isEmpty else { return 0.0 }
        return Double(completedCount) / Double(items.count)
    }

    /// Total word count across all items.
    var totalWordCount: Int {
        return items.reduce(0) { $0 + $1.wordCount }
    }

    /// Remaining word count (uncompleted items only).
    var remainingWordCount: Int {
        return items.filter { !$0.isCompleted }.reduce(0) { $0 + $1.wordCount }
    }

    /// Total time spent reading in this playlist (seconds).
    var totalTimeSpentSeconds: Double {
        return items.compactMap { $0.timeSpentSeconds }.reduce(0, +)
    }

    /// Whether this is a smart (auto-populated) playlist.
    var isSmart: Bool {
        return !smartRules.isEmpty
    }

    /// The current item in playback order, or nil if playlist is empty/finished.
    var currentItem: PlaylistItem? {
        let idx = effectiveIndex(for: currentIndex)
        guard idx >= 0, idx < items.count else { return nil }
        return items[idx]
    }

    // MARK: - Playback Helpers

    /// Translate a playback position to the actual items array index.
    func effectiveIndex(for position: Int) -> Int {
        guard !items.isEmpty else { return -1 }
        if isShuffled && !shuffleOrder.isEmpty {
            let clampedPos = max(0, min(position, shuffleOrder.count - 1))
            return shuffleOrder[clampedPos]
        }
        return max(0, min(position, items.count - 1))
    }

    /// Number of items remaining from current position.
    var remainingCount: Int {
        let total = items.count
        guard total > 0 else { return 0 }
        return max(0, total - currentIndex)
    }
}

// MARK: - ReadingPlaylistManager

class ReadingPlaylistManager {

    // MARK: - Singleton

    static let shared = ReadingPlaylistManager()

    // MARK: - Storage

    private let defaultsKey = "ReadingPlaylists_v1"
    private var playlists: [ReadingPlaylist] = []
    private let defaults: UserDefaults

    /// Default reading speed (WPM) for time estimates.
    var wordsPerMinute: Double = 238.0

    // MARK: - Init

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        load()
    }

    // MARK: - Persistence

    private func load() {
        guard let data = defaults.data(forKey: defaultsKey) else { return }
        if let decoded = try? JSONDecoder().decode([ReadingPlaylist].self, from: data) {
            playlists = decoded
        }
    }

    private func save() {
        if let data = try? JSONEncoder().encode(playlists) {
            defaults.set(data, forKey: defaultsKey)
        }
        NotificationCenter.default.post(name: .readingPlaylistsDidChange, object: self)
    }

    // MARK: - CRUD

    /// Create a new playlist. Returns the created playlist.
    @discardableResult
    func createPlaylist(name: String, description: String = "", icon: String = "📚") -> ReadingPlaylist {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return ReadingPlaylist(name: "Untitled")
        }
        var playlist = ReadingPlaylist(name: trimmed, description: description, icon: icon)
        playlist.modifiedDate = Date()
        playlists.append(playlist)
        save()
        return playlist
    }

    /// Get all playlists.
    func allPlaylists() -> [ReadingPlaylist] {
        return playlists
    }

    /// Get a playlist by ID.
    func playlist(byId id: String) -> ReadingPlaylist? {
        return playlists.first { $0.id == id }
    }

    /// Rename a playlist.
    func renamePlaylist(id: String, newName: String) -> Bool {
        guard let idx = playlists.firstIndex(where: { $0.id == id }) else { return false }
        let trimmed = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        playlists[idx].name = trimmed
        playlists[idx].modifiedDate = Date()
        save()
        return true
    }

    /// Update a playlist's description.
    func updateDescription(id: String, description: String) -> Bool {
        guard let idx = playlists.firstIndex(where: { $0.id == id }) else { return false }
        playlists[idx].description = description
        playlists[idx].modifiedDate = Date()
        save()
        return true
    }

    /// Delete a playlist by ID.
    @discardableResult
    func deletePlaylist(id: String) -> Bool {
        guard let idx = playlists.firstIndex(where: { $0.id == id }) else { return false }
        playlists.remove(at: idx)
        save()
        return true
    }

    /// Delete all playlists.
    func deleteAll() {
        playlists.removeAll()
        save()
    }

    /// Number of playlists.
    var count: Int {
        return playlists.count
    }

    // MARK: - Item Management

    /// Add an article to a playlist. Returns false if article already exists in playlist.
    @discardableResult
    func addItem(to playlistId: String, articleLink: String, articleTitle: String,
                 sourceFeedName: String = "", wordCount: Int = 0) -> Bool {
        guard let idx = playlists.firstIndex(where: { $0.id == playlistId }) else { return false }
        // Prevent duplicates by link
        if playlists[idx].items.contains(where: { $0.articleLink == articleLink }) {
            return false
        }
        let item = PlaylistItem(articleLink: articleLink, articleTitle: articleTitle,
                                sourceFeedName: sourceFeedName, wordCount: wordCount)
        playlists[idx].items.append(item)
        playlists[idx].modifiedDate = Date()
        if playlists[idx].isShuffled {
            regenerateShuffle(for: idx)
        }
        save()
        return true
    }

    /// Remove an item from a playlist by item ID.
    @discardableResult
    func removeItem(from playlistId: String, itemId: String) -> Bool {
        guard let pIdx = playlists.firstIndex(where: { $0.id == playlistId }) else { return false }
        guard let iIdx = playlists[pIdx].items.firstIndex(where: { $0.id == itemId }) else { return false }
        playlists[pIdx].items.remove(at: iIdx)
        // Adjust current index if needed
        if playlists[pIdx].currentIndex >= playlists[pIdx].items.count {
            playlists[pIdx].currentIndex = max(0, playlists[pIdx].items.count - 1)
        }
        if playlists[pIdx].isShuffled {
            regenerateShuffle(for: pIdx)
        }
        playlists[pIdx].modifiedDate = Date()
        save()
        return true
    }

    /// Move an item within a playlist.
    @discardableResult
    func moveItem(in playlistId: String, from fromIndex: Int, to toIndex: Int) -> Bool {
        guard let pIdx = playlists.firstIndex(where: { $0.id == playlistId }) else { return false }
        guard fromIndex >= 0, fromIndex < playlists[pIdx].items.count,
              toIndex >= 0, toIndex < playlists[pIdx].items.count else { return false }
        let item = playlists[pIdx].items.remove(at: fromIndex)
        playlists[pIdx].items.insert(item, at: toIndex)
        playlists[pIdx].modifiedDate = Date()
        save()
        return true
    }

    // MARK: - Playback

    /// Advance to the next article. Returns the next item or nil if at end.
    @discardableResult
    func advanceToNext(in playlistId: String) -> PlaylistItem? {
        guard let pIdx = playlists.firstIndex(where: { $0.id == playlistId }) else { return nil }
        let nextIndex = playlists[pIdx].currentIndex + 1
        let total = playlists[pIdx].items.count
        guard nextIndex < total else { return nil }
        playlists[pIdx].currentIndex = nextIndex
        playlists[pIdx].modifiedDate = Date()
        save()
        return playlists[pIdx].currentItem
    }

    /// Go back to the previous article.
    @discardableResult
    func goToPrevious(in playlistId: String) -> PlaylistItem? {
        guard let pIdx = playlists.firstIndex(where: { $0.id == playlistId }) else { return nil }
        guard playlists[pIdx].currentIndex > 0 else { return nil }
        playlists[pIdx].currentIndex -= 1
        playlists[pIdx].modifiedDate = Date()
        save()
        return playlists[pIdx].currentItem
    }

    /// Jump to a specific position in the playlist.
    @discardableResult
    func jumpTo(in playlistId: String, position: Int) -> PlaylistItem? {
        guard let pIdx = playlists.firstIndex(where: { $0.id == playlistId }) else { return nil }
        guard position >= 0, position < playlists[pIdx].items.count else { return nil }
        playlists[pIdx].currentIndex = position
        playlists[pIdx].modifiedDate = Date()
        save()
        return playlists[pIdx].currentItem
    }

    /// Mark the current item as completed and auto-advance.
    @discardableResult
    func completeCurrentAndAdvance(in playlistId: String, timeSpentSeconds: Double? = nil) -> PlaylistItem? {
        guard let pIdx = playlists.firstIndex(where: { $0.id == playlistId }) else { return nil }
        let effectiveIdx = playlists[pIdx].effectiveIndex(for: playlists[pIdx].currentIndex)
        guard effectiveIdx >= 0, effectiveIdx < playlists[pIdx].items.count else { return nil }
        playlists[pIdx].items[effectiveIdx].isCompleted = true
        playlists[pIdx].items[effectiveIdx].completedDate = Date()
        playlists[pIdx].items[effectiveIdx].timeSpentSeconds = timeSpentSeconds
        playlists[pIdx].modifiedDate = Date()
        save()
        return advanceToNext(in: playlistId)
    }

    /// Reset playback position to the beginning.
    func resetPlayback(in playlistId: String) {
        guard let pIdx = playlists.firstIndex(where: { $0.id == playlistId }) else { return }
        playlists[pIdx].currentIndex = 0
        playlists[pIdx].modifiedDate = Date()
        save()
    }

    // MARK: - Shuffle

    /// Toggle shuffle mode for a playlist.
    func toggleShuffle(in playlistId: String) -> Bool {
        guard let pIdx = playlists.firstIndex(where: { $0.id == playlistId }) else { return false }
        playlists[pIdx].isShuffled.toggle()
        if playlists[pIdx].isShuffled {
            regenerateShuffle(for: pIdx)
        } else {
            playlists[pIdx].shuffleOrder = []
        }
        playlists[pIdx].currentIndex = 0
        playlists[pIdx].modifiedDate = Date()
        save()
        return playlists[pIdx].isShuffled
    }

    private func regenerateShuffle(for playlistIndex: Int) {
        let count = playlists[playlistIndex].items.count
        playlists[playlistIndex].shuffleOrder = Array(0..<count).shuffled()
    }

    // MARK: - Time Estimates

    /// Estimated reading time for a playlist in minutes.
    func estimatedReadingTime(for playlistId: String) -> Double {
        guard let playlist = playlist(byId: playlistId) else { return 0 }
        return Double(playlist.totalWordCount) / wordsPerMinute
    }

    /// Estimated remaining reading time (uncompleted items only).
    func estimatedRemainingTime(for playlistId: String) -> Double {
        guard let playlist = playlist(byId: playlistId) else { return 0 }
        return Double(playlist.remainingWordCount) / wordsPerMinute
    }

    /// Formatted time string (e.g. "1h 23m" or "45m").
    func formattedTime(minutes: Double) -> String {
        let totalMinutes = Int(ceil(minutes))
        if totalMinutes < 60 {
            return "\(totalMinutes)m"
        }
        let hours = totalMinutes / 60
        let mins = totalMinutes % 60
        return mins > 0 ? "\(hours)h \(mins)m" : "\(hours)h"
    }

    // MARK: - Smart Playlists

    /// Create a smart playlist with auto-population rules.
    @discardableResult
    func createSmartPlaylist(name: String, rules: [SmartPlaylistRule], icon: String = "🤖") -> ReadingPlaylist {
        var playlist = ReadingPlaylist(name: name, icon: icon)
        playlist.smartRules = rules
        playlists.append(playlist)
        save()
        return playlist
    }

    /// Check if an article matches smart playlist rules.
    func matchesRules(_ rules: [SmartPlaylistRule], title: String, body: String,
                      feedName: String, wordCount: Int) -> Bool {
        guard !rules.isEmpty else { return false }
        // All rules must match (AND logic)
        return rules.allSatisfy { rule in
            switch rule.type {
            case .topic:
                let lowerValue = rule.value.lowercased()
                return title.lowercased().contains(lowerValue) || body.lowercased().contains(lowerValue)
            case .feed:
                return feedName.lowercased() == rule.value.lowercased()
            case .keyword:
                let lowerValue = rule.value.lowercased()
                return title.lowercased().contains(lowerValue) || body.lowercased().contains(lowerValue)
            case .minWordCount:
                if let min = Int(rule.value) { return wordCount >= min }
                return false
            case .maxWordCount:
                if let max = Int(rule.value) { return wordCount <= max }
                return false
            }
        }
    }

    /// Refresh a smart playlist by evaluating rules against provided articles.
    func refreshSmartPlaylist(id: String, articles: [(link: String, title: String,
                                                       body: String, feedName: String, wordCount: Int)]) -> Int {
        guard let pIdx = playlists.firstIndex(where: { $0.id == id }) else { return 0 }
        guard playlists[pIdx].isSmart else { return 0 }
        var addedCount = 0
        for article in articles {
            if matchesRules(playlists[pIdx].smartRules, title: article.title,
                           body: article.body, feedName: article.feedName,
                           wordCount: article.wordCount) {
                // Check limit per rule
                let totalLimit = playlists[pIdx].smartRules.map { $0.limit }.max() ?? 0
                if totalLimit > 0 && playlists[pIdx].items.count >= totalLimit { break }
                if addItem(to: playlists[pIdx].id, articleLink: article.link,
                          articleTitle: article.title, sourceFeedName: article.feedName,
                          wordCount: article.wordCount) {
                    addedCount += 1
                }
            }
        }
        return addedCount
    }

    // MARK: - Export / Import

    /// Export a playlist as JSON data.
    func exportPlaylist(id: String) -> Data? {
        guard let playlist = playlist(byId: id) else { return nil }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return try? encoder.encode(playlist)
    }

    /// Export a playlist as a JSON string.
    func exportPlaylistAsString(id: String) -> String? {
        guard let data = exportPlaylist(id: id) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    /// Import a playlist from JSON data. Returns the imported playlist or nil.
    @discardableResult
    func importPlaylist(from data: Data) -> ReadingPlaylist? {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard var playlist = try? decoder.decode(ReadingPlaylist.self, from: data) else { return nil }
        // Assign new ID to avoid conflicts
        let mirror = ReadingPlaylist(name: playlist.name, description: playlist.description, icon: playlist.icon)
        var imported = mirror
        imported.items = playlist.items
        imported.smartRules = playlist.smartRules
        playlists.append(imported)
        save()
        return imported
    }

    /// Import a playlist from a JSON string.
    @discardableResult
    func importPlaylist(from jsonString: String) -> ReadingPlaylist? {
        guard let data = jsonString.data(using: .utf8) else { return nil }
        return importPlaylist(from: data)
    }

    // MARK: - Statistics

    /// Get statistics for a playlist.
    func playlistStats(id: String) -> PlaylistStats? {
        guard let playlist = playlist(byId: id) else { return nil }
        return PlaylistStats(
            totalItems: playlist.items.count,
            completedItems: playlist.completedCount,
            completionRate: playlist.completionRate,
            totalWordCount: playlist.totalWordCount,
            remainingWordCount: playlist.remainingWordCount,
            estimatedTotalMinutes: estimatedReadingTime(for: id),
            estimatedRemainingMinutes: estimatedRemainingTime(for: id),
            totalTimeSpentSeconds: playlist.totalTimeSpentSeconds,
            uniqueFeeds: Set(playlist.items.map { $0.sourceFeedName }).filter { !$0.isEmpty }.count,
            isSmart: playlist.isSmart,
            isShuffled: playlist.isShuffled
        )
    }

    /// Aggregate statistics across all playlists.
    func globalStats() -> PlaylistGlobalStats {
        let total = playlists.count
        let totalItems = playlists.reduce(0) { $0 + $1.items.count }
        let completedItems = playlists.reduce(0) { $0 + $1.completedCount }
        let totalTime = playlists.reduce(0.0) { $0 + $1.totalTimeSpentSeconds }
        let smartCount = playlists.filter { $0.isSmart }.count
        return PlaylistGlobalStats(
            playlistCount: total,
            totalItems: totalItems,
            completedItems: completedItems,
            totalTimeSpentSeconds: totalTime,
            smartPlaylistCount: smartCount,
            manualPlaylistCount: total - smartCount
        )
    }

    // MARK: - Sorting

    /// Sort playlists by various criteria.
    func sortedPlaylists(by criteria: PlaylistSortCriteria) -> [ReadingPlaylist] {
        switch criteria {
        case .name:
            return playlists.sorted { $0.name.lowercased() < $1.name.lowercased() }
        case .created:
            return playlists.sorted { $0.createdDate > $1.createdDate }
        case .modified:
            return playlists.sorted { $0.modifiedDate > $1.modifiedDate }
        case .itemCount:
            return playlists.sorted { $0.items.count > $1.items.count }
        case .completion:
            return playlists.sorted { $0.completionRate > $1.completionRate }
        }
    }
}

// MARK: - Supporting Types

struct PlaylistStats: Equatable {
    let totalItems: Int
    let completedItems: Int
    let completionRate: Double
    let totalWordCount: Int
    let remainingWordCount: Int
    let estimatedTotalMinutes: Double
    let estimatedRemainingMinutes: Double
    let totalTimeSpentSeconds: Double
    let uniqueFeeds: Int
    let isSmart: Bool
    let isShuffled: Bool
}

struct PlaylistGlobalStats: Equatable {
    let playlistCount: Int
    let totalItems: Int
    let completedItems: Int
    let totalTimeSpentSeconds: Double
    let smartPlaylistCount: Int
    let manualPlaylistCount: Int
}

enum PlaylistSortCriteria: String, CaseIterable {
    case name
    case created
    case modified
    case itemCount
    case completion
}
