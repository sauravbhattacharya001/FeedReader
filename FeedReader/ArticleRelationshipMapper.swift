//
//  ArticleRelationshipMapper.swift
//  FeedReader
//
//  User-curated relationship graph between articles. Unlike the automatic
//  ArticleSimilarityManager (TF-IDF) or ArticleCrossReferenceEngine
//  (entity co-occurrence), this lets users manually define named,
//  directional connections between articles — building a personal
//  knowledge graph of how articles relate to each other.
//
//  Features:
//    - Named relationship types (contradicts, builds-on, inspired-by, etc.)
//    - Directional edges: "Article A contradicts Article B"
//    - User notes on each relationship explaining the connection
//    - Relationship strength (weak, moderate, strong)
//    - Graph queries: neighbors, paths, clusters
//    - Relationship statistics and type distribution
//    - JSON export/import of the full graph
//    - Merge-safe import (skip duplicates)
//
//  Persistence: UserDefaults via UserDefaultsCodableStore.
//  Works entirely offline with no external dependencies.
//

import Foundation

// MARK: - Notifications

extension Notification.Name {
    /// Posted when relationships are added, removed, or modified.
    static let articleRelationshipsDidChange = Notification.Name("ArticleRelationshipsDidChangeNotification")
}

// MARK: - Relationship Types

/// The kind of connection between two articles.
enum RelationshipType: String, Codable, CaseIterable {
    case contradictsBy = "contradicts"
    case buildsOn = "builds-on"
    case inspiredBy = "inspired-by"
    case supplements = "supplements"
    case updates = "updates"
    case refutes = "refutes"
    case summarizes = "summarizes"
    case exemplifies = "exemplifies"
    case relatedTo = "related-to"
    case custom = "custom"

    /// Human-readable label for display.
    var displayName: String {
        switch self {
        case .contradictsBy: return "Contradicts"
        case .buildsOn: return "Builds On"
        case .inspiredBy: return "Inspired By"
        case .supplements: return "Supplements"
        case .updates: return "Updates"
        case .refutes: return "Refutes"
        case .summarizes: return "Summarizes"
        case .exemplifies: return "Exemplifies"
        case .relatedTo: return "Related To"
        case .custom: return "Custom"
        }
    }

    /// Emoji for quick visual identification.
    var emoji: String {
        switch self {
        case .contradictsBy: return "⚔️"
        case .buildsOn: return "🧱"
        case .inspiredBy: return "💡"
        case .supplements: return "📎"
        case .updates: return "🔄"
        case .refutes: return "❌"
        case .summarizes: return "📝"
        case .exemplifies: return "🔍"
        case .relatedTo: return "🔗"
        case .custom: return "🏷️"
        }
    }

    /// The reverse relationship (for bidirectional queries).
    var inverse: RelationshipType {
        switch self {
        case .contradictsBy: return .contradictsBy
        case .buildsOn: return .inspiredBy
        case .inspiredBy: return .buildsOn
        case .supplements: return .supplements
        case .updates: return .updates
        case .refutes: return .refutes
        case .summarizes: return .exemplifies
        case .exemplifies: return .summarizes
        case .relatedTo: return .relatedTo
        case .custom: return .custom
        }
    }

    /// Whether this relationship is symmetric (A→B implies B→A of same type).
    var isSymmetric: Bool {
        return self == inverse
    }
}

// MARK: - Relationship Strength

/// How strongly two articles are connected.
enum RelationshipStrength: String, Codable, CaseIterable, Comparable {
    case weak = "weak"
    case moderate = "moderate"
    case strong = "strong"

    private var sortOrder: Int {
        switch self {
        case .weak: return 0
        case .moderate: return 1
        case .strong: return 2
        }
    }

    static func < (lhs: RelationshipStrength, rhs: RelationshipStrength) -> Bool {
        return lhs.sortOrder < rhs.sortOrder
    }
}

// MARK: - ArticleRelationship

/// A single directional edge in the relationship graph.
struct ArticleRelationship: Codable, Equatable {
    let id: String
    let sourceLink: String
    let sourceTitle: String
    let targetLink: String
    let targetTitle: String
    var type: RelationshipType
    var strength: RelationshipStrength
    var note: String?
    var customLabel: String?
    let createdAt: Date
    var modifiedAt: Date

    static func == (lhs: ArticleRelationship, rhs: ArticleRelationship) -> Bool {
        return lhs.id == rhs.id
    }
}

// MARK: - Relationship Statistics

/// Aggregate statistics about the relationship graph.
struct RelationshipGraphStats {
    let totalRelationships: Int
    let uniqueArticles: Int
    let typeDistribution: [RelationshipType: Int]
    let strengthDistribution: [RelationshipStrength: Int]
    let mostConnected: (link: String, title: String, count: Int)?
    let averageConnections: Double
    let clusterCount: Int
}

// MARK: - ArticleRelationshipMapper

/// Manages a user-curated graph of relationships between articles.
class ArticleRelationshipMapper {

    static let shared = ArticleRelationshipMapper()

    private var relationships: [String: ArticleRelationship] = [:]
    private var adjacency: [String: Set<String>] = [:]
    private var reverseAdjacency: [String: Set<String>] = [:]

    private let store = UserDefaultsCodableStore<[ArticleRelationship]>(
        key: "article_relationships_v1",
        dateStrategy: .iso8601
    )

    private var titleCache: [String: String] = [:]

    init() {
        loadFromStore()
    }

    // MARK: - CRUD

    @discardableResult
    func addRelationship(
        sourceLink: String,
        sourceTitle: String,
        targetLink: String,
        targetTitle: String,
        type: RelationshipType,
        strength: RelationshipStrength = .moderate,
        note: String? = nil,
        customLabel: String? = nil
    ) -> ArticleRelationship? {
        guard sourceLink != targetLink else { return nil }

        let existing = relationships.values.first {
            $0.sourceLink == sourceLink &&
            $0.targetLink == targetLink &&
            $0.type == type
        }
        if existing != nil { return nil }

        let rel = ArticleRelationship(
            id: UUID().uuidString,
            sourceLink: sourceLink,
            sourceTitle: sourceTitle,
            targetLink: targetLink,
            targetTitle: targetTitle,
            type: type,
            strength: strength,
            note: note,
            customLabel: customLabel,
            createdAt: Date(),
            modifiedAt: Date()
        )

        relationships[rel.id] = rel
        adjacency[sourceLink, default: []].insert(rel.id)
        reverseAdjacency[targetLink, default: []].insert(rel.id)
        titleCache[sourceLink] = sourceTitle
        titleCache[targetLink] = targetTitle

        persist()
        NotificationCenter.default.post(name: .articleRelationshipsDidChange, object: nil)
        return rel
    }

    @discardableResult
    func removeRelationship(id: String) -> Bool {
        guard let rel = relationships.removeValue(forKey: id) else { return false }

        adjacency[rel.sourceLink]?.remove(id)
        if adjacency[rel.sourceLink]?.isEmpty == true {
            adjacency.removeValue(forKey: rel.sourceLink)
        }
        reverseAdjacency[rel.targetLink]?.remove(id)
        if reverseAdjacency[rel.targetLink]?.isEmpty == true {
            reverseAdjacency.removeValue(forKey: rel.targetLink)
        }

        persist()
        NotificationCenter.default.post(name: .articleRelationshipsDidChange, object: nil)
        return true
    }

    @discardableResult
    func updateRelationship(
        id: String,
        type: RelationshipType? = nil,
        strength: RelationshipStrength? = nil,
        note: String? = nil,
        customLabel: String? = nil
    ) -> ArticleRelationship? {
        guard var rel = relationships[id] else { return nil }

        if let t = type { rel.type = t }
        if let s = strength { rel.strength = s }
        if let n = note { rel.note = n }
        if let c = customLabel { rel.customLabel = c }
        rel.modifiedAt = Date()

        relationships[id] = rel
        persist()
        NotificationCenter.default.post(name: .articleRelationshipsDidChange, object: nil)
        return rel
    }

    @discardableResult
    func removeAllRelationships(forArticle link: String) -> Int {
        let outgoing = adjacency[link] ?? []
        let incoming = reverseAdjacency[link] ?? []
        let toRemove = outgoing.union(incoming)

        var count = 0
        for id in toRemove {
            if let rel = relationships.removeValue(forKey: id) {
                adjacency[rel.sourceLink]?.remove(id)
                reverseAdjacency[rel.targetLink]?.remove(id)
                count += 1
            }
        }

        adjacency.removeValue(forKey: link)
        reverseAdjacency.removeValue(forKey: link)

        if count > 0 {
            persist()
            NotificationCenter.default.post(name: .articleRelationshipsDidChange, object: nil)
        }
        return count
    }

    // MARK: - Queries

    var allRelationships: [ArticleRelationship] {
        return Array(relationships.values).sorted { $0.createdAt > $1.createdAt }
    }

    var count: Int { return relationships.count }

    func relationship(byId id: String) -> ArticleRelationship? {
        return relationships[id]
    }

    func outgoingRelationships(forArticle link: String) -> [ArticleRelationship] {
        let ids = adjacency[link] ?? []
        return ids.compactMap { relationships[$0] }.sorted { $0.createdAt > $1.createdAt }
    }

    func incomingRelationships(forArticle link: String) -> [ArticleRelationship] {
        let ids = reverseAdjacency[link] ?? []
        return ids.compactMap { relationships[$0] }.sorted { $0.createdAt > $1.createdAt }
    }

    func allRelationships(forArticle link: String) -> [ArticleRelationship] {
        let outIds = adjacency[link] ?? []
        let inIds = reverseAdjacency[link] ?? []
        let allIds = outIds.union(inIds)
        return allIds.compactMap { relationships[$0] }.sorted { $0.createdAt > $1.createdAt }
    }

    func neighbors(ofArticle link: String) -> [(link: String, title: String, relationship: ArticleRelationship)] {
        let rels = allRelationships(forArticle: link)
        return rels.map { rel in
            if rel.sourceLink == link {
                return (link: rel.targetLink, title: rel.targetTitle, relationship: rel)
            } else {
                return (link: rel.sourceLink, title: rel.sourceTitle, relationship: rel)
            }
        }
    }

    func relationships(ofType type: RelationshipType) -> [ArticleRelationship] {
        return relationships.values
            .filter { $0.type == type }
            .sorted { $0.createdAt > $1.createdAt }
    }

    func relationships(minStrength: RelationshipStrength) -> [ArticleRelationship] {
        return relationships.values
            .filter { $0.strength >= minStrength }
            .sorted { $0.createdAt > $1.createdAt }
    }

    func searchByNote(query: String) -> [ArticleRelationship] {
        let q = query.lowercased()
        return relationships.values
            .filter { ($0.note?.lowercased().contains(q) ?? false) }
            .sorted { $0.createdAt > $1.createdAt }
    }

    var allArticleLinks: Set<String> {
        var links = Set<String>()
        for rel in relationships.values {
            links.insert(rel.sourceLink)
            links.insert(rel.targetLink)
        }
        return links
    }

    func connectionCount(forArticle link: String) -> Int {
        let out = adjacency[link]?.count ?? 0
        let `in` = reverseAdjacency[link]?.count ?? 0
        return out + `in`
    }

    // MARK: - Graph Analysis

    func findClusters() -> [[String]] {
        var visited = Set<String>()
        var clusters: [[String]] = []

        for link in allArticleLinks {
            guard !visited.contains(link) else { continue }

            var queue = [link]
            var cluster: [String] = []
            var head = 0

            while head < queue.count {
                let current = queue[head]
                head += 1

                guard !visited.contains(current) else { continue }
                visited.insert(current)
                cluster.append(current)

                for (neighborLink, _, _) in neighbors(ofArticle: current) {
                    if !visited.contains(neighborLink) {
                        queue.append(neighborLink)
                    }
                }
            }

            if !cluster.isEmpty {
                clusters.append(cluster)
            }
        }

        return clusters.sorted { $0.count > $1.count }
    }

    func computeStats() -> RelationshipGraphStats {
        let allRels = Array(relationships.values)
        let articles = allArticleLinks

        var typeDist: [RelationshipType: Int] = [:]
        var strengthDist: [RelationshipStrength: Int] = [:]
        for rel in allRels {
            typeDist[rel.type, default: 0] += 1
            strengthDist[rel.strength, default: 0] += 1
        }

        var connectionCounts: [String: Int] = [:]
        for link in articles {
            connectionCounts[link] = connectionCount(forArticle: link)
        }
        let mostConnected: (link: String, title: String, count: Int)? = connectionCounts
            .max(by: { $0.value < $1.value })
            .map { (link: $0.key, title: titleCache[$0.key] ?? $0.key, count: $0.value) }

        let avgConnections = articles.isEmpty ? 0.0 :
            Double(connectionCounts.values.reduce(0, +)) / Double(articles.count)

        let clusters = findClusters()

        return RelationshipGraphStats(
            totalRelationships: allRels.count,
            uniqueArticles: articles.count,
            typeDistribution: typeDist,
            strengthDistribution: strengthDist,
            mostConnected: mostConnected,
            averageConnections: avgConnections,
            clusterCount: clusters.count
        )
    }

    // MARK: - Export / Import

    func exportJSON(prettyPrint: Bool = true) -> Data? {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        if prettyPrint {
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        }
        return try? encoder.encode(Array(relationships.values))
    }

    func exportJSONString(prettyPrint: Bool = true) -> String? {
        guard let data = exportJSON(prettyPrint: prettyPrint) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    @discardableResult
    func importJSON(data: Data, skipDuplicates: Bool = true) -> Int {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let imported = try? decoder.decode([ArticleRelationship].self, from: data) else {
            return 0
        }

        var count = 0
        for rel in imported {
            guard rel.sourceLink != rel.targetLink else { continue }

            if skipDuplicates {
                let isDuplicate = relationships.values.contains {
                    $0.sourceLink == rel.sourceLink &&
                    $0.targetLink == rel.targetLink &&
                    $0.type == rel.type
                }
                if isDuplicate { continue }
            }

            let newRel = ArticleRelationship(
                id: UUID().uuidString,
                sourceLink: rel.sourceLink,
                sourceTitle: rel.sourceTitle,
                targetLink: rel.targetLink,
                targetTitle: rel.targetTitle,
                type: rel.type,
                strength: rel.strength,
                note: rel.note,
                customLabel: rel.customLabel,
                createdAt: rel.createdAt,
                modifiedAt: Date()
            )

            relationships[newRel.id] = newRel
            adjacency[newRel.sourceLink, default: []].insert(newRel.id)
            reverseAdjacency[newRel.targetLink, default: []].insert(newRel.id)
            titleCache[newRel.sourceLink] = newRel.sourceTitle
            titleCache[newRel.targetLink] = newRel.targetTitle
            count += 1
        }

        if count > 0 {
            persist()
            NotificationCenter.default.post(name: .articleRelationshipsDidChange, object: nil)
        }
        return count
    }

    // MARK: - Bulk Operations

    func removeAll() {
        relationships.removeAll()
        adjacency.removeAll()
        reverseAdjacency.removeAll()
        persist()
        NotificationCenter.default.post(name: .articleRelationshipsDidChange, object: nil)
    }

    // MARK: - Persistence

    private func persist() {
        store.save(Array(relationships.values))
    }

    private func loadFromStore() {
        guard let loaded = store.load() else { return }
        for rel in loaded {
            relationships[rel.id] = rel
            adjacency[rel.sourceLink, default: []].insert(rel.id)
            reverseAdjacency[rel.targetLink, default: []].insert(rel.id)
            titleCache[rel.sourceLink] = rel.sourceTitle
            titleCache[rel.targetLink] = rel.targetTitle
        }
    }
}
