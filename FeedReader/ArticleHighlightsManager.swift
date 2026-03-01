//
//  ArticleHighlightsManager.swift
//  FeedReader
//
//  Manages highlighted text snippets from articles.
//  Provides CRUD, search, filtering by color/article, and export.
//

import Foundation

/// Notification posted when highlights change.
extension Notification.Name {
    static let articleHighlightsDidChange = Notification.Name("ArticleHighlightsDidChangeNotification")
}

class ArticleHighlightsManager {
    
    // MARK: - Singleton
    
    static let shared = ArticleHighlightsManager()
    
    // MARK: - Constants
    
    static let maxHighlights = 1000
    private static let userDefaultsKey = "ArticleHighlightsManager.highlights"
    
    // MARK: - Properties
    
    private var highlightsById: [String: ArticleHighlight]
    
    // MARK: - Initialization
    
    private init() {
        highlightsById = ArticleHighlightsManager.loadFromDefaults()
    }
    
    // MARK: - CRUD
    
    /// Add a highlight. Returns nil if at capacity or invalid input.
    @discardableResult
    func addHighlight(articleLink: String, articleTitle: String,
                      selectedText: String, color: HighlightColor = .yellow,
                      annotation: String? = nil) -> ArticleHighlight? {
        guard highlightsById.count < ArticleHighlightsManager.maxHighlights else { return nil }
        
        guard let highlight = ArticleHighlight(
            articleLink: articleLink,
            articleTitle: articleTitle,
            selectedText: selectedText,
            color: color,
            annotation: annotation
        ) else { return nil }
        
        highlightsById[highlight.id] = highlight
        save()
        NotificationCenter.default.post(name: .articleHighlightsDidChange, object: nil)
        return highlight
    }
    
    /// Get a highlight by ID.
    func getHighlight(id: String) -> ArticleHighlight? {
        return highlightsById[id]
    }
    
    /// Remove a highlight by ID. Returns true if removed.
    @discardableResult
    func removeHighlight(id: String) -> Bool {
        guard highlightsById.removeValue(forKey: id) != nil else { return false }
        save()
        NotificationCenter.default.post(name: .articleHighlightsDidChange, object: nil)
        return true
    }
    
    /// Update a highlight's color.
    func updateColor(id: String, color: HighlightColor) {
        guard let highlight = highlightsById[id] else { return }
        highlight.color = color
        save()
        NotificationCenter.default.post(name: .articleHighlightsDidChange, object: nil)
    }
    
    /// Update a highlight's annotation.
    func updateAnnotation(id: String, annotation: String?) {
        guard let highlight = highlightsById[id] else { return }
        if let ann = annotation?.trimmingCharacters(in: .whitespacesAndNewlines), !ann.isEmpty {
            highlight.annotation = String(ann.prefix(ArticleHighlight.maxAnnotationLength))
        } else {
            highlight.annotation = nil
        }
        save()
        NotificationCenter.default.post(name: .articleHighlightsDidChange, object: nil)
    }
    
    // MARK: - Queries
    
    /// All highlights sorted by most recent first.
    func getAllHighlights() -> [ArticleHighlight] {
        return highlightsById.values.sorted { $0.createdDate > $1.createdDate }
    }
    
    /// Highlights for a specific article.
    func highlights(for articleLink: String) -> [ArticleHighlight] {
        return highlightsById.values
            .filter { $0.articleLink == articleLink }
            .sorted { $0.createdDate < $1.createdDate }
    }
    
    /// Highlights filtered by color.
    func highlights(byColor color: HighlightColor) -> [ArticleHighlight] {
        return highlightsById.values
            .filter { $0.color == color }
            .sorted { $0.createdDate > $1.createdDate }
    }
    
    /// Search highlights by text content (case-insensitive).
    func search(query: String) -> [ArticleHighlight] {
        let q = query.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return getAllHighlights() }
        return getAllHighlights().filter {
            $0.selectedText.lowercased().contains(q) ||
            $0.articleTitle.lowercased().contains(q) ||
            ($0.annotation?.lowercased().contains(q) ?? false)
        }
    }
    
    /// Count of highlights.
    var count: Int {
        return highlightsById.count
    }
    
    /// Count of highlights for a specific article.
    func count(for articleLink: String) -> Int {
        return highlightsById.values.filter { $0.articleLink == articleLink }.count
    }
    
    /// Articles that have highlights, with count, sorted by most recent highlight.
    func articlesWithHighlights() -> [(articleLink: String, articleTitle: String, count: Int, latestDate: Date)] {
        var grouped: [String: (title: String, count: Int, latest: Date)] = [:]
        for h in highlightsById.values {
            if let existing = grouped[h.articleLink] {
                grouped[h.articleLink] = (
                    title: existing.title,
                    count: existing.count + 1,
                    latest: max(existing.latest, h.createdDate)
                )
            } else {
                grouped[h.articleLink] = (title: h.articleTitle, count: 1, latest: h.createdDate)
            }
        }
        return grouped.map { (articleLink: $0.key, articleTitle: $0.value.title,
                              count: $0.value.count, latestDate: $0.value.latest) }
            .sorted { $0.latestDate > $1.latestDate }
    }
    
    // MARK: - Bulk Operations
    
    /// Remove all highlights for a specific article.
    @discardableResult
    func removeHighlights(for articleLink: String) -> Int {
        let toRemove = highlightsById.values.filter { $0.articleLink == articleLink }
        guard !toRemove.isEmpty else { return 0 }
        for h in toRemove {
            highlightsById.removeValue(forKey: h.id)
        }
        save()
        NotificationCenter.default.post(name: .articleHighlightsDidChange, object: nil)
        return toRemove.count
    }
    
    /// Clear all highlights.
    @discardableResult
    func clearAll() -> Int {
        let count = highlightsById.count
        guard count > 0 else { return 0 }
        highlightsById.removeAll()
        save()
        NotificationCenter.default.post(name: .articleHighlightsDidChange, object: nil)
        return count
    }
    
    // MARK: - Export
    
    /// Export highlights as formatted text.
    func exportAsText() -> String {
        let highlights = getAllHighlights()
        guard !highlights.isEmpty else { return "No highlights." }
        
        // Group by article
        var grouped: [String: [ArticleHighlight]] = [:]
        for h in highlights {
            grouped[h.articleLink, default: []].append(h)
        }
        
        return grouped.map { (link, highlights) in
            let title = highlights.first?.articleTitle ?? "Unknown"
            let snippets = highlights.map { h in
                var line = "  [\(h.color.displayName)] \"\(h.selectedText)\""
                if let ann = h.annotation {
                    line += "\n    → \(ann)"
                }
                return line
            }.joined(separator: "\n")
            return "## \(title)\n\(link)\n\(snippets)"
        }.joined(separator: "\n\n---\n\n")
    }
    
    // MARK: - Persistence
    
    private func save() {
        let data = try? NSKeyedArchiver.archivedData(
            withRootObject: Array(highlightsById.values),
            requiringSecureCoding: true
        )
        UserDefaults.standard.set(data, forKey: ArticleHighlightsManager.userDefaultsKey)
    }
    
    private static func loadFromDefaults() -> [String: ArticleHighlight] {
        guard let data = UserDefaults.standard.data(forKey: userDefaultsKey),
              let highlights = try? NSKeyedUnarchiver.unarchivedArrayOfObjects(
                ofClass: ArticleHighlight.self, from: data
              ) else {
            return [:]
        }
        var dict: [String: ArticleHighlight] = [:]
        for h in highlights {
            dict[h.id] = h
        }
        return dict
    }
    
    // MARK: - Testing Support
    
    func reset() {
        highlightsById.removeAll()
        UserDefaults.standard.removeObject(forKey: ArticleHighlightsManager.userDefaultsKey)
    }
    
    func reloadFromDefaults() {
        highlightsById = ArticleHighlightsManager.loadFromDefaults()
    }
}
