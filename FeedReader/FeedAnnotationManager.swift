//
//  FeedAnnotationManager.swift
//  FeedReader
//
//  Positional annotations anchored to specific text selections within
//  articles. Each annotation captures a quoted passage, the user's
//  comment, a category tag, and context (surrounding text). Supports
//  search, filtering, aggregate stats, and JSON/text export.
//

import Foundation

/// Notification posted when annotations change.
extension Notification.Name {
    static let feedAnnotationsDidChange = Notification.Name("FeedAnnotationsDidChangeNotification")
}

class FeedAnnotationManager {

    // MARK: - Singleton

    static let shared = FeedAnnotationManager()

    // MARK: - Types

    /// Category for classifying annotations.
    enum AnnotationCategory: String, Codable, CaseIterable {
        case insight = "insight"
        case question = "question"
        case disagreement = "disagreement"
        case factCheck = "fact-check"
        case reference = "reference"
        case actionItem = "action-item"
        case quote = "quote"
        case definition = "definition"
        case bookmark = "bookmark"
        case other = "other"

        var emoji: String {
            switch self {
            case .insight: return "💡"
            case .question: return "❓"
            case .disagreement: return "🤔"
            case .factCheck: return "✅"
            case .reference: return "🔗"
            case .actionItem: return "📌"
            case .quote: return "💬"
            case .definition: return "📖"
            case .bookmark: return "🔖"
            case .other: return "📝"
            }
        }

        var label: String {
            switch self {
            case .insight: return "Insight"
            case .question: return "Question"
            case .disagreement: return "Disagreement"
            case .factCheck: return "Fact Check"
            case .reference: return "Reference"
            case .actionItem: return "Action Item"
            case .quote: return "Quote"
            case .definition: return "Definition"
            case .bookmark: return "Bookmark"
            case .other: return "Other"
            }
        }
    }

    /// A single positional annotation within an article.
    struct Annotation: Codable, Equatable {
        let id: String
        let articleLink: String
        let articleTitle: String
        let feedName: String
        let selectedText: String
        let comment: String
        let category: AnnotationCategory
        let contextBefore: String
        let contextAfter: String
        let characterOffset: Int
        let createdAt: Date
        var updatedAt: Date
        var isResolved: Bool

        static func == (lhs: Annotation, rhs: Annotation) -> Bool {
            return lhs.id == rhs.id
        }
    }

    /// Summary statistics for annotation activity.
    struct AnnotationStats: Equatable {
        let totalAnnotations: Int
        let totalArticlesAnnotated: Int
        let totalFeedsAnnotated: Int
        let categoryBreakdown: [AnnotationCategory: Int]
        let resolvedCount: Int
        let unresolvedCount: Int
        let averageAnnotationsPerArticle: Double
        let oldestAnnotation: Date?
        let newestAnnotation: Date?
        let topFeedsByAnnotations: [(feed: String, count: Int)]
        let averageCommentLength: Double
        let averageQuoteLength: Double

        static func == (lhs: AnnotationStats, rhs: AnnotationStats) -> Bool {
            return lhs.totalAnnotations == rhs.totalAnnotations &&
                   lhs.totalArticlesAnnotated == rhs.totalArticlesAnnotated &&
                   lhs.resolvedCount == rhs.resolvedCount
        }
    }

    // MARK: - Constants

    static let maxAnnotations = 2000
    static let maxCommentLength = 2000
    static let maxSelectedTextLength = 1000
    static let maxContextLength = 100

    private static let userDefaultsKey = "FeedAnnotationManager.annotations"

    // MARK: - Storage

    private(set) var annotations: [Annotation] = []
    private let userDefaults: UserDefaults

    // MARK: - Init

    init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
        loadAnnotations()
    }

    // MARK: - CRUD

    @discardableResult
    func addAnnotation(
        articleLink: String,
        articleTitle: String,
        feedName: String,
        selectedText: String,
        comment: String,
        category: AnnotationCategory = .other,
        contextBefore: String = "",
        contextAfter: String = "",
        characterOffset: Int = 0
    ) -> Annotation? {
        guard !articleLink.isEmpty else { return nil }
        guard !selectedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        guard !comment.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        guard annotations.count < Self.maxAnnotations else { return nil }

        let trimmedSelected = String(selectedText.prefix(Self.maxSelectedTextLength))
        let trimmedComment = String(comment.prefix(Self.maxCommentLength))
        let trimmedBefore = String(contextBefore.suffix(Self.maxContextLength))
        let trimmedAfter = String(contextAfter.prefix(Self.maxContextLength))

        let now = Date()
        let annotation = Annotation(
            id: UUID().uuidString,
            articleLink: articleLink,
            articleTitle: articleTitle,
            feedName: feedName,
            selectedText: trimmedSelected,
            comment: trimmedComment,
            category: category,
            contextBefore: trimmedBefore,
            contextAfter: trimmedAfter,
            characterOffset: max(0, characterOffset),
            createdAt: now,
            updatedAt: now,
            isResolved: false
        )

        annotations.append(annotation)
        saveAnnotations()
        NotificationCenter.default.post(name: .feedAnnotationsDidChange, object: nil)
        return annotation
    }

    func updateAnnotation(
        id: String,
        newComment: String? = nil,
        newCategory: AnnotationCategory? = nil
    ) -> Bool {
        guard let index = annotations.firstIndex(where: { $0.id == id }) else { return false }
        if let comment = newComment {
            guard !comment.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return false }
            annotations[index] = Annotation(
                id: annotations[index].id,
                articleLink: annotations[index].articleLink,
                articleTitle: annotations[index].articleTitle,
                feedName: annotations[index].feedName,
                selectedText: annotations[index].selectedText,
                comment: String(comment.prefix(Self.maxCommentLength)),
                category: newCategory ?? annotations[index].category,
                contextBefore: annotations[index].contextBefore,
                contextAfter: annotations[index].contextAfter,
                characterOffset: annotations[index].characterOffset,
                createdAt: annotations[index].createdAt,
                updatedAt: Date(),
                isResolved: annotations[index].isResolved
            )
        } else if let cat = newCategory {
            annotations[index] = Annotation(
                id: annotations[index].id,
                articleLink: annotations[index].articleLink,
                articleTitle: annotations[index].articleTitle,
                feedName: annotations[index].feedName,
                selectedText: annotations[index].selectedText,
                comment: annotations[index].comment,
                category: cat,
                contextBefore: annotations[index].contextBefore,
                contextAfter: annotations[index].contextAfter,
                characterOffset: annotations[index].characterOffset,
                createdAt: annotations[index].createdAt,
                updatedAt: Date(),
                isResolved: annotations[index].isResolved
            )
        }
        saveAnnotations()
        NotificationCenter.default.post(name: .feedAnnotationsDidChange, object: nil)
        return true
    }

    func toggleResolved(id: String) -> Bool {
        guard let index = annotations.firstIndex(where: { $0.id == id }) else { return false }
        let a = annotations[index]
        annotations[index] = Annotation(
            id: a.id, articleLink: a.articleLink, articleTitle: a.articleTitle,
            feedName: a.feedName, selectedText: a.selectedText, comment: a.comment,
            category: a.category, contextBefore: a.contextBefore, contextAfter: a.contextAfter,
            characterOffset: a.characterOffset, createdAt: a.createdAt,
            updatedAt: Date(), isResolved: !a.isResolved
        )
        saveAnnotations()
        NotificationCenter.default.post(name: .feedAnnotationsDidChange, object: nil)
        return true
    }

    func removeAnnotation(id: String) -> Bool {
        let before = annotations.count
        annotations.removeAll { $0.id == id }
        if annotations.count < before {
            saveAnnotations()
            NotificationCenter.default.post(name: .feedAnnotationsDidChange, object: nil)
            return true
        }
        return false
    }

    func removeAnnotations(forArticle articleLink: String) -> Int {
        let before = annotations.count
        annotations.removeAll { $0.articleLink == articleLink }
        let removed = before - annotations.count
        if removed > 0 {
            saveAnnotations()
            NotificationCenter.default.post(name: .feedAnnotationsDidChange, object: nil)
        }
        return removed
    }

    func removeAllAnnotations() {
        guard !annotations.isEmpty else { return }
        annotations.removeAll()
        saveAnnotations()
        NotificationCenter.default.post(name: .feedAnnotationsDidChange, object: nil)
    }

    // MARK: - Queries

    func annotation(withId id: String) -> Annotation? {
        return annotations.first { $0.id == id }
    }

    func annotations(forArticle articleLink: String) -> [Annotation] {
        return annotations
            .filter { $0.articleLink == articleLink }
            .sorted { $0.characterOffset < $1.characterOffset }
    }

    func annotations(forFeed feedName: String) -> [Annotation] {
        return annotations
            .filter { $0.feedName == feedName }
            .sorted { $0.createdAt > $1.createdAt }
    }

    func annotations(inCategory category: AnnotationCategory) -> [Annotation] {
        return annotations.filter { $0.category == category }
    }

    func unresolvedAnnotations() -> [Annotation] {
        return annotations.filter {
            !$0.isResolved && ($0.category == .question || $0.category == .actionItem)
        }
    }

    func search(query: String) -> [Annotation] {
        let q = query.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return [] }
        return annotations.filter {
            $0.selectedText.lowercased().contains(q) ||
            $0.comment.lowercased().contains(q) ||
            $0.articleTitle.lowercased().contains(q)
        }
    }

    func annotations(from startDate: Date, to endDate: Date) -> [Annotation] {
        return annotations.filter {
            $0.createdAt >= startDate && $0.createdAt <= endDate
        }
    }

    func recentlyAnnotatedArticles(limit: Int = 10) -> [(articleLink: String, articleTitle: String, count: Int, lastAnnotated: Date)] {
        var articleMap: [String: (title: String, count: Int, latest: Date)] = [:]
        for a in annotations {
            if let existing = articleMap[a.articleLink] {
                articleMap[a.articleLink] = (
                    title: a.articleTitle,
                    count: existing.count + 1,
                    latest: max(existing.latest, a.createdAt)
                )
            } else {
                articleMap[a.articleLink] = (title: a.articleTitle, count: 1, latest: a.createdAt)
            }
        }
        return articleMap
            .map { (articleLink: $0.key, articleTitle: $0.value.title, count: $0.value.count, lastAnnotated: $0.value.latest) }
            .sorted { $0.lastAnnotated > $1.lastAnnotated }
            .prefix(limit)
            .map { $0 }
    }

    // MARK: - Statistics

    func computeStats() -> AnnotationStats {
        let uniqueArticles = Set(annotations.map { $0.articleLink })
        let uniqueFeeds = Set(annotations.map { $0.feedName })

        var categoryBreakdown: [AnnotationCategory: Int] = [:]
        for cat in AnnotationCategory.allCases {
            let count = annotations.filter { $0.category == cat }.count
            if count > 0 { categoryBreakdown[cat] = count }
        }

        let resolved = annotations.filter { $0.isResolved }.count
        let unresolved = annotations.filter {
            !$0.isResolved && ($0.category == .question || $0.category == .actionItem)
        }.count

        let avgPerArticle = uniqueArticles.isEmpty ? 0.0 : Double(annotations.count) / Double(uniqueArticles.count)

        var feedCounts: [String: Int] = [:]
        for a in annotations { feedCounts[a.feedName, default: 0] += 1 }
        let topFeeds = feedCounts
            .sorted { $0.value > $1.value }
            .prefix(5)
            .map { (feed: $0.key, count: $0.value) }

        let avgComment = annotations.isEmpty ? 0.0 : Double(annotations.map { $0.comment.count }.reduce(0, +)) / Double(annotations.count)
        let avgQuote = annotations.isEmpty ? 0.0 : Double(annotations.map { $0.selectedText.count }.reduce(0, +)) / Double(annotations.count)

        return AnnotationStats(
            totalAnnotations: annotations.count,
            totalArticlesAnnotated: uniqueArticles.count,
            totalFeedsAnnotated: uniqueFeeds.count,
            categoryBreakdown: categoryBreakdown,
            resolvedCount: resolved,
            unresolvedCount: unresolved,
            averageAnnotationsPerArticle: avgPerArticle,
            oldestAnnotation: annotations.map { $0.createdAt }.min(),
            newestAnnotation: annotations.map { $0.createdAt }.max(),
            topFeedsByAnnotations: topFeeds,
            averageCommentLength: avgComment,
            averageQuoteLength: avgQuote
        )
    }

    // MARK: - Export

    func exportJSON() -> Data? {
        return try? JSONCoding.iso8601PrettyEncoder.encode(annotations)
    }

    func importJSON(_ data: Data) -> Int {
        guard let imported = try? JSONCoding.iso8601Decoder.decode([Annotation].self, from: data) else { return 0 }
        let existingIds = Set(annotations.map { $0.id })
        var added = 0
        for a in imported {
            guard !existingIds.contains(a.id) else { continue }
            guard annotations.count < Self.maxAnnotations else { break }
            annotations.append(a)
            added += 1
        }
        if added > 0 {
            saveAnnotations()
            NotificationCenter.default.post(name: .feedAnnotationsDidChange, object: nil)
        }
        return added
    }

    func exportText() -> String {
        let dateFormatter = DateFormatter()
        dateFormatter.dateStyle = .medium
        dateFormatter.timeStyle = .short

        var lines: [String] = []
        lines.append("Feed Reader — Annotations Export")
        lines.append("Generated: \(dateFormatter.string(from: Date()))")
        lines.append("Total: \(annotations.count) annotations across \(Set(annotations.map { $0.articleLink }).count) articles")
        lines.append(String(repeating: "=", count: 60))
        lines.append("")

        var articleGroups: [String: [Annotation]] = [:]
        for a in annotations {
            articleGroups[a.articleLink, default: []].append(a)
        }

        for (_, group) in articleGroups.sorted(by: { ($0.value.first?.createdAt ?? .distantPast) > ($1.value.first?.createdAt ?? .distantPast) }) {
            guard let first = group.first else { continue }
            let sorted = group.sorted { $0.characterOffset < $1.characterOffset }
            lines.append("📄 \(first.articleTitle)")
            lines.append("   Feed: \(first.feedName)")
            lines.append("   Link: \(first.articleLink)")
            lines.append("")

            for a in sorted {
                let resolved = a.isResolved ? " ✅" : ""
                lines.append("   \(a.category.emoji) [\(a.category.label)]\(resolved)")
                lines.append("   \"\(a.selectedText)\"")
                lines.append("   → \(a.comment)")
                lines.append("   \(dateFormatter.string(from: a.createdAt))")
                lines.append("")
            }
            lines.append(String(repeating: "-", count: 40))
            lines.append("")
        }

        return lines.joined(separator: "\n")
    }

    // MARK: - Persistence

    private func saveAnnotations() {
        if let data = try? JSONCoding.iso8601Encoder.encode(annotations) {
            userDefaults.set(data, forKey: Self.userDefaultsKey)
        }
    }

    private func loadAnnotations() {
        guard let data = userDefaults.data(forKey: Self.userDefaultsKey) else { return }
        if let loaded = try? JSONCoding.iso8601Decoder.decode([Annotation].self, from: data) {
            annotations = loaded
        }
    }
}
