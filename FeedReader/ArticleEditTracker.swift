//
//  ArticleEditTracker.swift
//  FeedReader
//
//  Detects when RSS articles are silently updated between fetches.
//  Stores revision snapshots and provides diff-like change summaries.
//  Useful for tracking stealth-edited news articles.
//

import Foundation

/// Represents a single revision snapshot of an article.
struct ArticleRevision: Codable, Equatable {
    let timestamp: Date
    let title: String
    let body: String
    let link: String

    /// Word-level diff summary compared to a previous revision.
    struct ChangeSummary: Codable, Equatable {
        let wordsAdded: Int
        let wordsRemoved: Int
        let titleChanged: Bool
        let addedSegments: [String]
        let removedSegments: [String]

        var hasChanges: Bool {
            return wordsAdded > 0 || wordsRemoved > 0 || titleChanged
        }

        var description: String {
            var parts: [String] = []
            if titleChanged { parts.append("title changed") }
            if wordsAdded > 0 { parts.append("+\(wordsAdded) words") }
            if wordsRemoved > 0 { parts.append("-\(wordsRemoved) words") }
            return parts.isEmpty ? "no changes" : parts.joined(separator: ", ")
        }
    }
}

/// Tracks article revisions across fetches and detects edits.
class ArticleEditTracker {

    // MARK: - Singleton

    static let shared = ArticleEditTracker()

    // MARK: - Storage

    /// Maps article link → array of revisions (oldest first).
    private var revisions: [String: [ArticleRevision]] = [:]

    /// Maximum revisions to keep per article.
    private let maxRevisionsPerArticle = 20

    /// File URL for persistence.
    private static let storageURL: URL = {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        return docs.appendingPathComponent("articleEditTracker.json")
    }()

    // MARK: - Init

    init() {
        load()
    }

    // MARK: - Public API

    /// Record a new snapshot for an article. Returns a change summary
    /// if the article content has changed since the last snapshot, or nil
    /// if this is the first snapshot or content is unchanged.
    @discardableResult
    func recordSnapshot(link: String, title: String, body: String) -> ArticleRevision.ChangeSummary? {
        let normalizedLink = link.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedLink.isEmpty else { return nil }

        let revision = ArticleRevision(
            timestamp: Date(),
            title: title.trimmingCharacters(in: .whitespacesAndNewlines),
            body: body.trimmingCharacters(in: .whitespacesAndNewlines),
            link: normalizedLink
        )

        var history = revisions[normalizedLink] ?? []

        // Check if content actually changed from last revision
        if let lastRevision = history.last {
            if lastRevision.title == revision.title && lastRevision.body == revision.body {
                return nil // No change
            }
            // Content changed — compute diff
            let summary = computeChangeSummary(old: lastRevision, new: revision)
            history.append(revision)
            if history.count > maxRevisionsPerArticle {
                history.removeFirst(history.count - maxRevisionsPerArticle)
            }
            revisions[normalizedLink] = history
            save()
            return summary
        } else {
            // First snapshot
            history.append(revision)
            revisions[normalizedLink] = history
            save()
            return nil
        }
    }

    /// Returns all revisions for an article, oldest first.
    func getRevisions(for link: String) -> [ArticleRevision] {
        let normalizedLink = link.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        return revisions[normalizedLink] ?? []
    }

    /// Returns the number of edits detected for an article (revisions - 1).
    func editCount(for link: String) -> Int {
        let revs = getRevisions(for: link)
        return max(0, revs.count - 1)
    }

    /// Returns all articles that have been edited at least once.
    func editedArticles() -> [(link: String, editCount: Int, lastEdit: Date)] {
        return revisions.compactMap { (link, revs) in
            guard revs.count > 1, let lastRev = revs.last else { return nil }
            return (link: link, editCount: revs.count - 1, lastEdit: lastRev.timestamp)
        }.sorted { $0.lastEdit > $1.lastEdit }
    }

    /// Returns change summaries between consecutive revisions for an article.
    func changeHistory(for link: String) -> [ArticleRevision.ChangeSummary] {
        let revs = getRevisions(for: link)
        guard revs.count > 1 else { return [] }

        var summaries: [ArticleRevision.ChangeSummary] = []
        for i in 1..<revs.count {
            summaries.append(computeChangeSummary(old: revs[i - 1], new: revs[i]))
        }
        return summaries
    }

    /// Clears all tracked revisions.
    func clearAll() {
        revisions = [:]
        save()
    }

    /// Removes revision history for a specific article.
    func clearRevisions(for link: String) {
        let normalizedLink = link.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        revisions.removeValue(forKey: normalizedLink)
        save()
    }

    /// Returns total number of articles being tracked.
    var trackedArticleCount: Int {
        return revisions.count
    }

    /// Returns total number of edits detected across all articles.
    var totalEditsDetected: Int {
        return revisions.values.reduce(0) { sum, revs in sum + max(0, revs.count - 1) }
    }

    /// Prunes articles with only one revision (never edited) that are
    /// older than the given interval, to prevent unbounded storage growth.
    func pruneStale(olderThan interval: TimeInterval = 30 * 24 * 3600) {
        let cutoff = Date().addingTimeInterval(-interval)
        var pruned = 0
        for (link, revs) in revisions {
            if revs.count == 1, let only = revs.first, only.timestamp < cutoff {
                revisions.removeValue(forKey: link)
                pruned += 1
            }
        }
        if pruned > 0 { save() }
    }

    // MARK: - Diff Engine

    /// Computes a word-level change summary between two revisions.
    func computeChangeSummary(old: ArticleRevision, new: ArticleRevision) -> ArticleRevision.ChangeSummary {
        let oldWords = tokenize(old.body)
        let newWords = tokenize(new.body)

        let oldSet = NSCountedSet(array: oldWords)
        let newSet = NSCountedSet(array: newWords)

        var wordsAdded = 0
        var wordsRemoved = 0

        for word in newSet {
            let diff = newSet.count(for: word) - oldSet.count(for: word)
            if diff > 0 { wordsAdded += diff }
        }
        for word in oldSet {
            let diff = oldSet.count(for: word) - newSet.count(for: word)
            if diff > 0 { wordsRemoved += diff }
        }

        // Extract added/removed text segments (sentence-level granularity)
        let oldSentences = Set(sentences(old.body))
        let newSentences = Set(sentences(new.body))

        let addedSegments = Array(newSentences.subtracting(oldSentences).prefix(5))
        let removedSegments = Array(oldSentences.subtracting(newSentences).prefix(5))

        return ArticleRevision.ChangeSummary(
            wordsAdded: wordsAdded,
            wordsRemoved: wordsRemoved,
            titleChanged: old.title != new.title,
            addedSegments: addedSegments,
            removedSegments: removedSegments
        )
    }

    // MARK: - Text Processing

    private func tokenize(_ text: String) -> [String] {
        return text.lowercased()
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
    }

    private func sentences(_ text: String) -> [String] {
        var result: [String] = []
        text.enumerateSubstrings(in: text.startIndex..., options: .bySentences) { substring, _, _, _ in
            if let s = substring?.trimmingCharacters(in: .whitespacesAndNewlines), !s.isEmpty {
                result.append(s)
            }
        }
        return result.isEmpty ? [text] : result
    }

    // MARK: - Persistence

    private func save() {
        do {
            let data = try JSONEncoder().encode(revisions)
            try data.write(to: ArticleEditTracker.storageURL, options: .atomic)
        } catch {
            print("ArticleEditTracker: save failed — \(error.localizedDescription)")
        }
    }

    private func load() {
        guard FileManager.default.fileExists(atPath: ArticleEditTracker.storageURL.path) else { return }
        do {
            let data = try Data(contentsOf: ArticleEditTracker.storageURL)
            revisions = try JSONDecoder().decode([String: [ArticleRevision]].self, from: data)
        } catch {
            print("ArticleEditTracker: load failed — \(error.localizedDescription)")
            revisions = [:]
        }
    }
}
