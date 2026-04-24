//
//  FeedDiffTracker.swift
//  FeedReader
//
//  Tracks differences between consecutive feed refreshes, showing users
//  which stories are new, which disappeared, and which persisted. Provides
//  a feed-level changelog so users can see what changed since their last
//  visit without scrolling through the full list.
//
//  Key features:
//  - Snapshot feed state on each refresh
//  - Compute diff between snapshots (added/removed/persisted stories)
//  - Per-feed diff history with configurable retention
//  - Summary statistics (churn rate, avg new stories per refresh)
//  - "What's new since I last checked" convenience query
//  - JSON export of diff history
//
//  Persistence: UserDefaults via Codable.
//

import Foundation

// MARK: - Notifications

extension Notification.Name {
    /// Posted when a new feed diff is recorded.
    static let feedDiffDidUpdate = Notification.Name("FeedDiffDidUpdateNotification")
}

// MARK: - Models

/// Lightweight fingerprint of a story for diff comparison.
struct StoryFingerprint: Codable, Equatable, Hashable {
    let link: String
    let title: String
    
    init(story: Story) {
        self.link = story.link.lowercased()
        self.title = story.title
    }
    
    init(link: String, title: String) {
        self.link = link.lowercased()
        self.title = title
    }
    
    func hash(into hasher: inout Hasher) {
        hasher.combine(link)
    }
    
    static func == (lhs: StoryFingerprint, rhs: StoryFingerprint) -> Bool {
        return lhs.link == rhs.link
    }
}

/// A snapshot of a feed's stories at a point in time.
struct FeedSnapshot: Codable {
    let feedURL: String
    let timestamp: Date
    let storyFingerprints: [StoryFingerprint]
    
    var storyCount: Int {
        return storyFingerprints.count
    }
}

/// The diff between two consecutive snapshots.
struct FeedDiff: Codable {
    let feedURL: String
    let timestamp: Date
    let previousTimestamp: Date
    
    /// Stories present in new snapshot but not in previous.
    let added: [StoryFingerprint]
    
    /// Stories present in previous snapshot but not in new.
    let removed: [StoryFingerprint]
    
    /// Stories present in both snapshots.
    let persisted: [StoryFingerprint]
    
    /// Total stories in the new snapshot.
    var currentCount: Int {
        return added.count + persisted.count
    }
    
    /// Total stories in the previous snapshot.
    var previousCount: Int {
        return removed.count + persisted.count
    }
    
    /// Fraction of stories that changed (0.0 – 1.0).
    var churnRate: Double {
        let totalUnique = Set(added + removed + persisted).count
        guard totalUnique > 0 else { return 0.0 }
        return Double(added.count + removed.count) / Double(totalUnique)
    }
    
    /// Human-readable summary of this diff.
    var summary: String {
        var parts: [String] = []
        if !added.isEmpty {
            parts.append("+\(added.count) new")
        }
        if !removed.isEmpty {
            parts.append("-\(removed.count) removed")
        }
        parts.append("\(persisted.count) unchanged")
        return parts.joined(separator: ", ")
    }
    
    /// True if nothing changed between snapshots.
    var isEmpty: Bool {
        return added.isEmpty && removed.isEmpty
    }
}

/// Aggregate statistics for a feed's diff history.
struct FeedDiffStats: Codable {
    let feedURL: String
    let totalDiffs: Int
    let totalAdded: Int
    let totalRemoved: Int
    let avgNewPerRefresh: Double
    let avgRemovedPerRefresh: Double
    let avgChurnRate: Double
    let highestChurnRate: Double
    let lastDiffTimestamp: Date?
}

// MARK: - FeedDiffTracker

class FeedDiffTracker {
    
    // MARK: - Singleton
    
    static let shared = FeedDiffTracker()
    
    // MARK: - Configuration
    
    /// Maximum number of snapshots to retain per feed.
    static let maxSnapshotsPerFeed = 50
    
    /// Maximum number of diffs to retain per feed.
    static let maxDiffsPerFeed = 100
    
    // MARK: - Storage
    
    /// Most recent snapshot per feed URL.
    private var latestSnapshots: [String: FeedSnapshot] = [:]
    
    /// Diff history per feed URL (newest first).
    private var diffHistory: [String: [FeedDiff]] = [:]
    
    /// Previous snapshots per feed URL for rollback/analysis.
    private var snapshotHistory: [String: [FeedSnapshot]] = [:]
    
    private let storageKey = "FeedDiffTracker_Data"
    
    // MARK: - Initialization
    
    private init() {
        load()
    }
    
    // MARK: - Core Operations
    
    /// Record a new snapshot for a feed and compute the diff against the previous snapshot.
    /// Returns the diff if a previous snapshot existed, nil for the first snapshot.
    @discardableResult
    func recordRefresh(feedURL: String, stories: [Story]) -> FeedDiff? {
        let normalizedURL = feedURL.lowercased()
        let fingerprints = stories.map { StoryFingerprint(story: $0) }
        let snapshot = FeedSnapshot(
            feedURL: normalizedURL,
            timestamp: Date(),
            storyFingerprints: fingerprints
        )
        
        let previousSnapshot = latestSnapshots[normalizedURL]
        
        // Store snapshot in history
        var history = snapshotHistory[normalizedURL] ?? []
        history.insert(snapshot, at: 0)
        if history.count > FeedDiffTracker.maxSnapshotsPerFeed {
            history = Array(history.prefix(FeedDiffTracker.maxSnapshotsPerFeed))
        }
        snapshotHistory[normalizedURL] = history
        latestSnapshots[normalizedURL] = snapshot
        
        // Compute diff if we have a previous snapshot
        guard let previous = previousSnapshot else {
            save()
            return nil
        }
        
        let previousSet = Set(previous.storyFingerprints)
        let currentSet = Set(fingerprints)
        
        let added = fingerprints.filter { !previousSet.contains($0) }
        let removed = previous.storyFingerprints.filter { !currentSet.contains($0) }
        let persisted = fingerprints.filter { previousSet.contains($0) }
        
        let diff = FeedDiff(
            feedURL: normalizedURL,
            timestamp: snapshot.timestamp,
            previousTimestamp: previous.timestamp,
            added: added,
            removed: removed,
            persisted: persisted
        )
        
        // Store diff
        var diffs = diffHistory[normalizedURL] ?? []
        diffs.insert(diff, at: 0)
        if diffs.count > FeedDiffTracker.maxDiffsPerFeed {
            diffs = Array(diffs.prefix(FeedDiffTracker.maxDiffsPerFeed))
        }
        diffHistory[normalizedURL] = diffs
        
        save()
        NotificationCenter.default.post(name: .feedDiffDidUpdate, object: nil,
                                         userInfo: ["feedURL": normalizedURL])
        
        return diff
    }
    
    // MARK: - Queries
    
    /// Get the most recent diff for a feed.
    func latestDiff(for feedURL: String) -> FeedDiff? {
        return diffHistory[feedURL.lowercased()]?.first
    }
    
    /// Get all diffs for a feed, newest first.
    func diffs(for feedURL: String) -> [FeedDiff] {
        return diffHistory[feedURL.lowercased()] ?? []
    }
    
    /// Get diffs for a feed within a time range.
    func diffs(for feedURL: String, since: Date) -> [FeedDiff] {
        return diffs(for: feedURL).filter { $0.timestamp >= since }
    }
    
    /// "What's new since I last checked" — all new stories added across
    /// all feeds since the given date.
    func newStoriesSince(_ date: Date) -> [(feedURL: String, stories: [StoryFingerprint])] {
        var results: [(feedURL: String, stories: [StoryFingerprint])] = []
        
        for (feedURL, diffs) in diffHistory {
            let recentDiffs = diffs.filter { $0.timestamp >= date }
            var allNew: [StoryFingerprint] = []
            var seen = Set<String>()
            
            for diff in recentDiffs {
                for story in diff.added {
                    if !seen.contains(story.link) {
                        allNew.append(story)
                        seen.insert(story.link)
                    }
                }
            }
            
            if !allNew.isEmpty {
                results.append((feedURL: feedURL, stories: allNew))
            }
        }
        
        return results.sorted { $0.stories.count > $1.stories.count }
    }
    
    /// Get aggregate statistics for a feed.
    func stats(for feedURL: String) -> FeedDiffStats? {
        let normalizedURL = feedURL.lowercased()
        guard let diffs = diffHistory[normalizedURL], !diffs.isEmpty else {
            return nil
        }
        
        let totalAdded = diffs.reduce(0) { $0 + $1.added.count }
        let totalRemoved = diffs.reduce(0) { $0 + $1.removed.count }
        let avgNew = Double(totalAdded) / Double(diffs.count)
        let avgRemoved = Double(totalRemoved) / Double(diffs.count)
        let avgChurn = diffs.reduce(0.0) { $0 + $1.churnRate } / Double(diffs.count)
        let highestChurn = diffs.map { $0.churnRate }.max() ?? 0.0
        
        return FeedDiffStats(
            feedURL: normalizedURL,
            totalDiffs: diffs.count,
            totalAdded: totalAdded,
            totalRemoved: totalRemoved,
            avgNewPerRefresh: avgNew,
            avgRemovedPerRefresh: avgRemoved,
            avgChurnRate: avgChurn,
            highestChurnRate: highestChurn,
            lastDiffTimestamp: diffs.first?.timestamp
        )
    }
    
    /// Get stats for all tracked feeds.
    func allStats() -> [FeedDiffStats] {
        return diffHistory.keys.compactMap { stats(for: $0) }
            .sorted { ($0.lastDiffTimestamp ?? .distantPast) > ($1.lastDiffTimestamp ?? .distantPast) }
    }
    
    /// Get the latest snapshot for a feed.
    func latestSnapshot(for feedURL: String) -> FeedSnapshot? {
        return latestSnapshots[feedURL.lowercased()]
    }
    
    /// All feed URLs currently tracked.
    var trackedFeeds: [String] {
        return Array(latestSnapshots.keys).sorted()
    }
    
    /// Total number of diffs recorded across all feeds.
    var totalDiffCount: Int {
        return diffHistory.values.reduce(0) { $0 + $1.count }
    }
    
    // MARK: - Export
    
    /// Export all diff history as JSON data.
    func exportJSON() -> Data? {
        let exportData = ExportPayload(
            exportDate: Date(),
            feeds: diffHistory.map { feedURL, diffs in
                ExportPayload.FeedEntry(feedURL: feedURL, diffs: diffs)
            }
        )
        
        return try? JSONCoding.iso8601PrettyEncoder.encode(exportData)
    }
    
    /// Export diff history as a JSON string.
    func exportJSONString() -> String? {
        guard let data = exportJSON() else { return nil }
        return String(data: data, encoding: .utf8)
    }
    
    // MARK: - Maintenance
    
    /// Clear all history for a specific feed.
    func clearHistory(for feedURL: String) {
        let normalized = feedURL.lowercased()
        latestSnapshots.removeValue(forKey: normalized)
        diffHistory.removeValue(forKey: normalized)
        snapshotHistory.removeValue(forKey: normalized)
        save()
    }
    
    /// Clear all tracking data.
    func clearAll() {
        latestSnapshots.removeAll()
        diffHistory.removeAll()
        snapshotHistory.removeAll()
        save()
    }
    
    /// Remove diffs older than a specified date.
    func pruneHistory(before date: Date) {
        for (feedURL, diffs) in diffHistory {
            let kept = diffs.filter { $0.timestamp >= date }
            if kept.isEmpty {
                diffHistory.removeValue(forKey: feedURL)
            } else {
                diffHistory[feedURL] = kept
            }
        }
        
        for (feedURL, snapshots) in snapshotHistory {
            let kept = snapshots.filter { $0.timestamp >= date }
            if kept.isEmpty {
                snapshotHistory.removeValue(forKey: feedURL)
            } else {
                snapshotHistory[feedURL] = kept
            }
        }
        
        save()
    }
    
    // MARK: - Persistence
    
    private struct StoragePayload: Codable {
        let latestSnapshots: [String: FeedSnapshot]
        let diffHistory: [String: [FeedDiff]]
        let snapshotHistory: [String: [FeedSnapshot]]
    }
    
    private struct ExportPayload: Codable {
        let exportDate: Date
        let feeds: [FeedEntry]
        
        struct FeedEntry: Codable {
            let feedURL: String
            let diffs: [FeedDiff]
        }
    }
    
    private func save() {
        let payload = StoragePayload(
            latestSnapshots: latestSnapshots,
            diffHistory: diffHistory,
            snapshotHistory: snapshotHistory
        )
        
        guard let data = try? JSONCoding.iso8601Encoder.encode(payload) else {
            print("FeedDiffTracker: Failed to encode data")
            return
        }
        
        // Guard against unbounded storage growth
        let maxBytes = 5 * 1024 * 1024  // 5 MB limit
        guard data.count <= maxBytes else {
            print("FeedDiffTracker: Storage exceeds \(maxBytes / 1024)KB limit, pruning oldest entries")
            pruneOldest()
            return
        }
        
        UserDefaults.standard.set(data, forKey: storageKey)
    }
    
    private func load() {
        guard let data = UserDefaults.standard.data(forKey: storageKey) else { return }
        
        guard let payload = try? JSONCoding.iso8601Decoder.decode(StoragePayload.self, from: data) else {
            print("FeedDiffTracker: Failed to decode stored data")
            return
        }
        
        latestSnapshots = payload.latestSnapshots
        diffHistory = payload.diffHistory
        snapshotHistory = payload.snapshotHistory
    }
    
    /// Emergency prune: remove oldest half of diffs and snapshots per feed.
    private func pruneOldest() {
        for (feedURL, diffs) in diffHistory {
            let keep = max(diffs.count / 2, 1)
            diffHistory[feedURL] = Array(diffs.prefix(keep))
        }
        for (feedURL, snapshots) in snapshotHistory {
            let keep = max(snapshots.count / 2, 1)
            snapshotHistory[feedURL] = Array(snapshots.prefix(keep))
        }
        
        if let data = try? JSONCoding.iso8601Encoder.encode(StoragePayload(
            latestSnapshots: latestSnapshots,
            diffHistory: diffHistory,
            snapshotHistory: snapshotHistory
        )) {
            UserDefaults.standard.set(data, forKey: storageKey)
        }
    }
}
