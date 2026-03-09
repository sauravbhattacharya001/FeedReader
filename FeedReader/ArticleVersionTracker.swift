//
//  ArticleVersionTracker.swift
//  FeedReader
//
//  Tracks article content changes over time to detect silent edits,
//  corrections, and significant updates. Many publishers update articles
//  after initial publication without notifying readers — this module
//  detects those changes by comparing content fingerprints.
//
//  Features:
//    - Content fingerprinting via normalized text hashing
//    - Version history with timestamped snapshots
//    - Change significance scoring (minor typo vs major rewrite)
//    - Word-level diff summaries between versions
//    - Notification-worthy change detection
//    - Per-feed and per-article change statistics
//    - JSON persistence for version history
//
//  Fully offline — no network, no dependencies beyond Foundation.
//

import Foundation

// MARK: - ArticleSnapshot

/// A point-in-time capture of an article's content.
struct ArticleSnapshot: Equatable {
    /// When this snapshot was taken.
    let timestamp: Date
    /// SHA-256 hash of the normalized content.
    let contentHash: String
    /// Normalized title at time of capture.
    let title: String
    /// Word count of the body.
    let wordCount: Int
    /// First 200 characters of body (for preview).
    let bodyPreview: String

    static func == (lhs: ArticleSnapshot, rhs: ArticleSnapshot) -> Bool {
        return lhs.timestamp == rhs.timestamp &&
               lhs.contentHash == rhs.contentHash &&
               lhs.title == rhs.title
    }
}

// MARK: - ArticleChange

/// Describes a detected change between two versions.
struct ArticleChange: Equatable {
    /// When the change was detected.
    let detectedAt: Date
    /// Version number (1-indexed, version 1 = first change from original).
    let version: Int
    /// Previous content hash.
    let previousHash: String
    /// New content hash.
    let newHash: String
    /// Change significance score (0.0 = identical, 1.0 = complete rewrite).
    let significance: Double
    /// Classification of the change.
    let category: ChangeCategory
    /// Human-readable summary of what changed.
    let summary: String
    /// Whether this change is worth notifying the user about.
    let isNotifiable: Bool
    /// Title changed?
    let titleChanged: Bool
    /// Word count delta (positive = added, negative = removed).
    let wordCountDelta: Int
}

// MARK: - ChangeCategory

/// Classification of how significant an article change is.
enum ChangeCategory: String {
    /// No meaningful change (whitespace, formatting only).
    case cosmetic = "cosmetic"
    /// Minor edit (typo fixes, small wording tweaks, <5% change).
    case minor = "minor"
    /// Moderate update (new paragraph, corrections, 5-25% change).
    case moderate = "moderate"
    /// Major revision (significant rewrite, >25% change).
    case major = "major"
    /// Title changed — always notable.
    case titleChange = "title_change"
    /// Complete replacement (>75% different content).
    case rewrite = "rewrite"
}

// MARK: - ArticleVersionHistory

/// Complete version history for a single article.
struct ArticleVersionHistory: Equatable {
    /// Article link (unique identifier).
    let link: String
    /// Feed this article belongs to.
    let feedName: String
    /// All captured snapshots, oldest first.
    var snapshots: [ArticleSnapshot]
    /// Detected changes between snapshots.
    var changes: [ArticleChange]
    /// Whether this article is actively being tracked.
    var isTracking: Bool

    /// Current version number (0 = original, 1+ = edits detected).
    var currentVersion: Int {
        return changes.count
    }

    /// Most recent snapshot.
    var latestSnapshot: ArticleSnapshot? {
        return snapshots.last
    }

    /// Whether any significant changes have been detected.
    var hasSignificantChanges: Bool {
        return changes.contains { $0.significance >= 0.15 }
    }
}

// MARK: - VersionTrackerStats

/// Aggregate statistics about article version tracking.
struct VersionTrackerStats: Equatable {
    /// Total articles being tracked.
    let trackedCount: Int
    /// Articles that have been modified at least once.
    let modifiedCount: Int
    /// Total changes detected across all articles.
    let totalChanges: Int
    /// Average significance of detected changes.
    let averageSignificance: Double
    /// Most frequently updated article link.
    let mostUpdatedLink: String?
    /// Most frequently updated article change count.
    let mostUpdatedChangeCount: Int
    /// Changes by category.
    let categoryBreakdown: [ChangeCategory: Int]
    /// Per-feed modification rates.
    let feedModificationRates: [String: Double]
}

// MARK: - VersionComparisonResult

/// Result of comparing two specific versions of an article.
struct VersionComparisonResult: Equatable {
    /// Article link.
    let link: String
    /// From version number.
    let fromVersion: Int
    /// To version number.
    let toVersion: Int
    /// Words added.
    let wordsAdded: [String]
    /// Words removed.
    let wordsRemoved: [String]
    /// Net word count change.
    let wordCountDelta: Int
    /// Title changed.
    let titleChanged: Bool
    /// Old title (if changed).
    let oldTitle: String?
    /// New title (if changed).
    let newTitle: String?
    /// Overall similarity (0.0-1.0).
    let similarity: Double
}

// MARK: - ArticleVersionTracker

/// Tracks and analyzes article content changes over time.
class ArticleVersionTracker {

    // MARK: - Properties

    /// Version histories keyed by article link.
    private(set) var histories: [String: ArticleVersionHistory] = [:]

    /// Minimum significance threshold for notifications (default 0.10).
    var notificationThreshold: Double

    /// Maximum snapshots to keep per article (prevents unbounded growth).
    var maxSnapshotsPerArticle: Int

    // MARK: - Initialization

    /// Creates a new version tracker.
    /// - Parameters:
    ///   - notificationThreshold: Minimum change significance to trigger notification (0.0-1.0).
    ///   - maxSnapshotsPerArticle: Maximum snapshots retained per article.
    init(notificationThreshold: Double = 0.10, maxSnapshotsPerArticle: Int = 50) {
        self.notificationThreshold = max(0.0, min(1.0, notificationThreshold))
        self.maxSnapshotsPerArticle = max(2, maxSnapshotsPerArticle)
    }

    // MARK: - Tracking

    /// Records a snapshot of an article's current state.
    /// If the content has changed since the last snapshot, a change record is created.
    /// - Parameters:
    ///   - link: Article URL (unique identifier).
    ///   - title: Current article title.
    ///   - body: Current article body text.
    ///   - feedName: Name of the feed this article belongs to.
    ///   - timestamp: When this snapshot was taken (defaults to now).
    /// - Returns: The detected change, if any, or nil if content is unchanged.
    @discardableResult
    func recordSnapshot(link: String, title: String, body: String,
                        feedName: String = "", timestamp: Date = Date()) -> ArticleChange? {
        let normalizedTitle = normalizeText(title)
        let normalizedBody = normalizeText(body)
        let contentHash = computeHash(normalizedTitle + "|" + normalizedBody)
        let words = normalizedBody.split(separator: " ")
        let wordCount = words.count
        let preview = String(normalizedBody.prefix(200))

        let snapshot = ArticleSnapshot(
            timestamp: timestamp,
            contentHash: contentHash,
            title: normalizedTitle,
            wordCount: wordCount,
            bodyPreview: preview
        )

        // First time seeing this article
        guard var history = histories[link] else {
            histories[link] = ArticleVersionHistory(
                link: link,
                feedName: feedName,
                snapshots: [snapshot],
                changes: [],
                isTracking: true
            )
            return nil
        }

        // Check if content actually changed
        guard let lastSnapshot = history.latestSnapshot,
              lastSnapshot.contentHash != contentHash else {
            return nil
        }

        // Compute change details
        let previousWords = Set(lastSnapshot.bodyPreview.split(separator: " ").map(String.init))
        let currentWords = Set(normalizedBody.prefix(500).split(separator: " ").map(String.init))

        let significance = computeSignificance(
            oldHash: lastSnapshot.contentHash,
            newHash: contentHash,
            oldTitle: lastSnapshot.title,
            newTitle: normalizedTitle,
            oldWordCount: lastSnapshot.wordCount,
            newWordCount: wordCount,
            oldWords: previousWords,
            newWords: currentWords
        )

        let titleChanged = lastSnapshot.title != normalizedTitle
        let category = classifyChange(significance: significance, titleChanged: titleChanged)
        let wordCountDelta = wordCount - lastSnapshot.wordCount

        let change = ArticleChange(
            detectedAt: timestamp,
            version: history.changes.count + 1,
            previousHash: lastSnapshot.contentHash,
            newHash: contentHash,
            significance: significance,
            category: category,
            summary: generateChangeSummary(
                category: category,
                titleChanged: titleChanged,
                wordCountDelta: wordCountDelta,
                significance: significance
            ),
            isNotifiable: significance >= notificationThreshold,
            titleChanged: titleChanged,
            wordCountDelta: wordCountDelta
        )

        history.snapshots.append(snapshot)
        history.changes.append(change)

        // Enforce snapshot limit (keep first + most recent)
        if history.snapshots.count > maxSnapshotsPerArticle {
            let first = history.snapshots[0]
            let recentCount = maxSnapshotsPerArticle - 1
            let recent = Array(history.snapshots.suffix(recentCount))
            history.snapshots = [first] + recent
        }

        histories[link] = history
        return change
    }

    /// Stops tracking an article.
    func stopTracking(link: String) {
        histories[link]?.isTracking = false
    }

    /// Resumes tracking an article.
    func resumeTracking(link: String) {
        histories[link]?.isTracking = true
    }

    /// Removes all version history for an article.
    func removeHistory(link: String) {
        histories.removeValue(forKey: link)
    }

    /// Returns the version history for an article.
    func getHistory(link: String) -> ArticleVersionHistory? {
        return histories[link]
    }

    /// Returns all articles that have been modified.
    func getModifiedArticles() -> [ArticleVersionHistory] {
        return histories.values
            .filter { !$0.changes.isEmpty }
            .sorted { ($0.changes.last?.detectedAt ?? .distantPast) >
                      ($1.changes.last?.detectedAt ?? .distantPast) }
    }

    /// Returns articles with notifiable changes since a given date.
    func getNotifiableChanges(since date: Date) -> [(ArticleVersionHistory, ArticleChange)] {
        var results: [(ArticleVersionHistory, ArticleChange)] = []
        for history in histories.values {
            for change in history.changes where change.isNotifiable && change.detectedAt >= date {
                results.append((history, change))
            }
        }
        return results.sorted { $0.1.detectedAt > $1.1.detectedAt }
    }

    /// Returns all actively tracked article links.
    func getTrackedLinks() -> [String] {
        return histories.values
            .filter { $0.isTracking }
            .map { $0.link }
            .sorted()
    }

    // MARK: - Comparison

    /// Compares two versions of an article.
    /// - Parameters:
    ///   - link: Article link.
    ///   - fromVersion: Starting version (0 = original).
    ///   - toVersion: Ending version (-1 = latest).
    /// - Returns: Comparison result, or nil if versions don't exist.
    func compareVersions(link: String, fromVersion: Int = 0, toVersion: Int = -1) -> VersionComparisonResult? {
        guard let history = histories[link],
              !history.snapshots.isEmpty else { return nil }

        let fromIdx = fromVersion
        let toIdx = toVersion < 0 ? history.snapshots.count - 1 : toVersion

        guard fromIdx >= 0, fromIdx < history.snapshots.count,
              toIdx >= 0, toIdx < history.snapshots.count,
              fromIdx != toIdx else { return nil }

        let fromSnapshot = history.snapshots[fromIdx]
        let toSnapshot = history.snapshots[toIdx]

        let fromWords = fromSnapshot.bodyPreview.split(separator: " ").map(String.init)
        let toWords = toSnapshot.bodyPreview.split(separator: " ").map(String.init)

        let fromSet = Set(fromWords)
        let toSet = Set(toWords)

        let added = Array(toSet.subtracting(fromSet)).sorted()
        let removed = Array(fromSet.subtracting(toSet)).sorted()

        let titleChanged = fromSnapshot.title != toSnapshot.title
        let union = fromSet.union(toSet)
        let intersection = fromSet.intersection(toSet)
        let similarity = union.isEmpty ? 1.0 : Double(intersection.count) / Double(union.count)

        return VersionComparisonResult(
            link: link,
            fromVersion: fromIdx,
            toVersion: toIdx,
            wordsAdded: added,
            wordsRemoved: removed,
            wordCountDelta: toSnapshot.wordCount - fromSnapshot.wordCount,
            titleChanged: titleChanged,
            oldTitle: titleChanged ? fromSnapshot.title : nil,
            newTitle: titleChanged ? toSnapshot.title : nil,
            similarity: similarity
        )
    }

    // MARK: - Statistics

    /// Computes aggregate tracking statistics.
    func computeStats() -> VersionTrackerStats {
        let tracked = histories.values.filter { $0.isTracking }
        let modified = tracked.filter { !$0.changes.isEmpty }
        let allChanges = tracked.flatMap { $0.changes }

        let avgSig = allChanges.isEmpty ? 0.0 :
            allChanges.reduce(0.0) { $0 + $1.significance } / Double(allChanges.count)

        // Category breakdown
        var catBreakdown: [ChangeCategory: Int] = [:]
        for change in allChanges {
            catBreakdown[change.category, default: 0] += 1
        }

        // Most updated article
        let mostUpdated = modified.max { $0.changes.count < $1.changes.count }

        // Per-feed modification rates
        var feedTotal: [String: Int] = [:]
        var feedModified: [String: Int] = [:]
        for h in tracked {
            feedTotal[h.feedName, default: 0] += 1
            if !h.changes.isEmpty {
                feedModified[h.feedName, default: 0] += 1
            }
        }
        var feedRates: [String: Double] = [:]
        for (feed, total) in feedTotal where !feed.isEmpty {
            feedRates[feed] = Double(feedModified[feed, default: 0]) / Double(total)
        }

        return VersionTrackerStats(
            trackedCount: tracked.count,
            modifiedCount: modified.count,
            totalChanges: allChanges.count,
            averageSignificance: avgSig,
            mostUpdatedLink: mostUpdated?.link,
            mostUpdatedChangeCount: mostUpdated?.changes.count ?? 0,
            categoryBreakdown: catBreakdown,
            feedModificationRates: feedRates
        )
    }

    /// Generates a text report of tracking activity.
    func generateReport() -> String {
        let stats = computeStats()
        var lines: [String] = []

        lines.append("=== Article Version Tracker Report ===")
        lines.append("")
        lines.append("Tracked articles: \(stats.trackedCount)")
        lines.append("Modified articles: \(stats.modifiedCount)")
        lines.append("Total changes detected: \(stats.totalChanges)")
        lines.append(String(format: "Average change significance: %.1f%%", stats.averageSignificance * 100))
        lines.append("")

        if !stats.categoryBreakdown.isEmpty {
            lines.append("Changes by category:")
            for (cat, count) in stats.categoryBreakdown.sorted(by: { $0.value > $1.value }) {
                lines.append("  \(cat.rawValue): \(count)")
            }
            lines.append("")
        }

        if let mostLink = stats.mostUpdatedLink {
            lines.append("Most updated: \(mostLink) (\(stats.mostUpdatedChangeCount) changes)")
            lines.append("")
        }

        if !stats.feedModificationRates.isEmpty {
            lines.append("Feed modification rates:")
            for (feed, rate) in stats.feedModificationRates.sorted(by: { $0.value > $1.value }) {
                lines.append(String(format: "  %@: %.0f%%", feed, rate * 100))
            }
            lines.append("")
        }

        // Recent notable changes
        let recentNotifiable = getNotifiableChanges(
            since: Date(timeIntervalSinceNow: -7 * 24 * 3600)
        ).prefix(10)
        if !recentNotifiable.isEmpty {
            lines.append("Recent notable changes (last 7 days):")
            for (history, change) in recentNotifiable {
                lines.append("  [\(change.category.rawValue)] \(history.link)")
                lines.append("    \(change.summary)")
            }
        }

        return lines.joined(separator: "\n")
    }

    // MARK: - Persistence

    /// Exports all version histories as JSON-compatible dictionaries.
    func exportToJSON() -> [[String: Any]] {
        return histories.values.map { history in
            var dict: [String: Any] = [
                "link": history.link,
                "feedName": history.feedName,
                "isTracking": history.isTracking,
                "snapshotCount": history.snapshots.count,
                "changeCount": history.changes.count
            ]

            dict["snapshots"] = history.snapshots.map { snap in
                [
                    "timestamp": snap.timestamp.timeIntervalSince1970,
                    "contentHash": snap.contentHash,
                    "title": snap.title,
                    "wordCount": snap.wordCount,
                    "bodyPreview": snap.bodyPreview
                ] as [String: Any]
            }

            dict["changes"] = history.changes.map { change in
                [
                    "detectedAt": change.detectedAt.timeIntervalSince1970,
                    "version": change.version,
                    "previousHash": change.previousHash,
                    "newHash": change.newHash,
                    "significance": change.significance,
                    "category": change.category.rawValue,
                    "summary": change.summary,
                    "isNotifiable": change.isNotifiable,
                    "titleChanged": change.titleChanged,
                    "wordCountDelta": change.wordCountDelta
                ] as [String: Any]
            }

            return dict
        }
    }

    /// Imports version histories from JSON-compatible dictionaries.
    func importFromJSON(_ data: [[String: Any]]) {
        for dict in data {
            guard let link = dict["link"] as? String,
                  let feedName = dict["feedName"] as? String else { continue }

            let isTracking = dict["isTracking"] as? Bool ?? true

            var snapshots: [ArticleSnapshot] = []
            if let snapData = dict["snapshots"] as? [[String: Any]] {
                for sd in snapData {
                    guard let ts = sd["timestamp"] as? TimeInterval,
                          let hash = sd["contentHash"] as? String,
                          let title = sd["title"] as? String,
                          let wc = sd["wordCount"] as? Int else { continue }
                    let preview = sd["bodyPreview"] as? String ?? ""
                    snapshots.append(ArticleSnapshot(
                        timestamp: Date(timeIntervalSince1970: ts),
                        contentHash: hash,
                        title: title,
                        wordCount: wc,
                        bodyPreview: preview
                    ))
                }
            }

            var changes: [ArticleChange] = []
            if let changeData = dict["changes"] as? [[String: Any]] {
                for cd in changeData {
                    guard let ts = cd["detectedAt"] as? TimeInterval,
                          let version = cd["version"] as? Int,
                          let prevHash = cd["previousHash"] as? String,
                          let newHash = cd["newHash"] as? String,
                          let sig = cd["significance"] as? Double,
                          let catStr = cd["category"] as? String,
                          let cat = ChangeCategory(rawValue: catStr) else { continue }
                    let summary = cd["summary"] as? String ?? ""
                    let notifiable = cd["isNotifiable"] as? Bool ?? false
                    let titleChg = cd["titleChanged"] as? Bool ?? false
                    let wcDelta = cd["wordCountDelta"] as? Int ?? 0

                    changes.append(ArticleChange(
                        detectedAt: Date(timeIntervalSince1970: ts),
                        version: version,
                        previousHash: prevHash,
                        newHash: newHash,
                        significance: sig,
                        category: cat,
                        summary: summary,
                        isNotifiable: notifiable,
                        titleChanged: titleChg,
                        wordCountDelta: wcDelta
                    ))
                }
            }

            histories[link] = ArticleVersionHistory(
                link: link,
                feedName: feedName,
                snapshots: snapshots,
                changes: changes,
                isTracking: isTracking
            )
        }
    }

    /// Clears all tracking data.
    func clearAll() {
        histories.removeAll()
    }

    // MARK: - Private Helpers

    /// Normalizes text for consistent comparison.
    private func normalizeText(_ text: String) -> String {
        return text.lowercased()
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }

    /// Computes a simple hash string for content fingerprinting.
    /// Uses djb2 algorithm for speed (no crypto needed here).
    private func computeHash(_ text: String) -> String {
        var hash: UInt64 = 5381
        for byte in text.utf8 {
            hash = ((hash << 5) &+ hash) &+ UInt64(byte)
        }
        return String(format: "%016llx", hash)
    }

    /// Computes how significant a change is between two versions.
    private func computeSignificance(
        oldHash: String, newHash: String,
        oldTitle: String, newTitle: String,
        oldWordCount: Int, newWordCount: Int,
        oldWords: Set<String>, newWords: Set<String>
    ) -> Double {
        // Title change is always significant
        if oldTitle != newTitle {
            let titleSimilarity = jaccardSimilarity(
                Set(oldTitle.split(separator: " ").map(String.init)),
                Set(newTitle.split(separator: " ").map(String.init))
            )
            if titleSimilarity < 0.5 {
                return max(0.5, 1.0 - titleSimilarity)
            }
        }

        // Word-level Jaccard distance
        let wordSimilarity = jaccardSimilarity(oldWords, newWords)

        // Word count ratio change
        let maxWC = max(oldWordCount, newWordCount, 1)
        let wcRatio = Double(abs(newWordCount - oldWordCount)) / Double(maxWC)

        // Combined significance (word dissimilarity weighted more)
        let significance = (1.0 - wordSimilarity) * 0.7 + wcRatio * 0.3
        return min(1.0, max(0.0, significance))
    }

    /// Jaccard similarity between two sets.
    private func jaccardSimilarity(_ a: Set<String>, _ b: Set<String>) -> Double {
        let union = a.union(b)
        guard !union.isEmpty else { return 1.0 }
        let intersection = a.intersection(b)
        guard !union.isEmpty else { return 0.0 }
        return Double(intersection.count) / Double(union.count)
    }

    /// Classifies a change based on its significance score.
    private func classifyChange(significance: Double, titleChanged: Bool) -> ChangeCategory {
        if titleChanged { return .titleChange }
        if significance >= 0.75 { return .rewrite }
        if significance >= 0.25 { return .major }
        if significance >= 0.10 { return .moderate }
        if significance >= 0.03 { return .minor }
        return .cosmetic
    }

    /// Generates a human-readable summary of a change.
    private func generateChangeSummary(
        category: ChangeCategory, titleChanged: Bool,
        wordCountDelta: Int, significance: Double
    ) -> String {
        var parts: [String] = []

        switch category {
        case .cosmetic:
            parts.append("Minor formatting or whitespace change")
        case .minor:
            parts.append("Small edit (typo fix or wording tweak)")
        case .moderate:
            parts.append("Moderate update with new or revised content")
        case .major:
            parts.append("Significant revision of article content")
        case .titleChange:
            parts.append("Article title was changed")
        case .rewrite:
            parts.append("Article was substantially rewritten")
        }

        if titleChanged && category != .titleChange {
            parts.append("title also changed")
        }

        if wordCountDelta > 0 {
            parts.append("\(wordCountDelta) words added")
        } else if wordCountDelta < 0 {
            parts.append("\(abs(wordCountDelta)) words removed")
        }

        parts.append(String(format: "%.0f%% change", significance * 100))

        return parts.joined(separator: "; ")
    }
}
