//
//  FeedKnowledgeGraph.swift
//  FeedReader
//
//  Autonomous knowledge graph builder that extracts entities (people,
//  organizations, topics, locations) from articles using heuristic NLP,
//  then builds a connected entity graph based on co-occurrence. Surfaces
//  related past reads, emerging entities, entity timelines, and clusters.
//
//  How it works:
//    1. Each ingested article's title + body is scanned for entities
//       using capitalization heuristics, suffix patterns, and a built-in
//       gazetteer of major locations
//    2. Extracted entities become nodes; co-occurrence in the same article
//       creates weighted edges between them
//    3. The graph enables discovery: related articles share entities,
//       entity timelines show narrative arcs, clusters reveal topic
//       constellations
//    4. Auto-monitor mode periodically detects emerging entities and
//       posts notifications
//
//  Usage:
//    let graph = FeedKnowledgeGraph()
//    graph.ingest(articleId: "a1", title: "OpenAI launches GPT-5",
//        body: "Sam Altman announced...", date: Date())
//    graph.ingest(articleId: "a2", title: "Sam Altman on AI safety",
//        body: "The OpenAI CEO discussed...", date: Date())
//
//    let related = graph.relatedArticles(for: "a1")
//    // ["a2"] -- connected through "Sam Altman" and "OpenAI"
//
//    let hot = graph.hotEntities(topN: 5)
//    let recs = graph.recommendations()
//    let clusters = graph.entityClusters()
//
//  Persistence: JSON file in Documents directory.
//  Fully offline -- no network, no dependencies beyond Foundation.
//

import Foundation

// MARK: - Notifications

extension Notification.Name {
    /// Posted when new entities are extracted from an ingested article.
    static let knowledgeGraphUpdated = Notification.Name("FeedKnowledgeGraphUpdatedNotification")
    /// Posted when an emerging entity is detected by auto-monitor.
    static let knowledgeGraphEmergingEntity = Notification.Name("FeedKnowledgeGraphEmergingEntityNotification")
}

// MARK: - Entity Type

/// Classification of a knowledge entity.
enum KnowledgeEntityType: String, Codable, CaseIterable {
    case person
    case organization
    case topic
    case location

    var emoji: String {
        switch self {
        case .person:       return "person"
        case .organization: return "org"
        case .topic:        return "topic"
        case .location:     return "loc"
        }
    }

    var displayName: String {
        switch self {
        case .person:       return "Person"
        case .organization: return "Organization"
        case .topic:        return "Topic"
        case .location:     return "Location"
        }
    }
}

// MARK: - Data Models

/// A node in the knowledge graph.
struct KnowledgeEntity: Codable {
    let id: String
    var name: String
    var type: KnowledgeEntityType
    var articleIds: [String]
    var firstSeen: Date
    var lastSeen: Date
    var mentionCount: Int

    /// Canonical id from name.
    static func makeId(from name: String) -> String {
        return name.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

/// A weighted edge between two entities.
struct EntityEdge: Codable {
    let entity1Id: String
    let entity2Id: String
    var weight: Int
    var articleIds: [String]

    /// Canonical edge key (alphabetical order).
    static func key(_ a: String, _ b: String) -> String {
        return a < b ? "\(a)|\(b)" : "\(b)|\(a)"
    }
}

/// A cluster of tightly connected entities.
struct EntityCluster {
    let entities: [KnowledgeEntity]
    let label: String
    let articleCount: Int
}

/// Summary statistics for the knowledge graph.
struct KnowledgeGraphStats {
    let totalEntities: Int
    let totalEdges: Int
    let topEntities: [KnowledgeEntity]
    let articlesCovered: Int
}

/// An article reference with shared entity info.
struct RelatedArticle {
    let articleId: String
    let sharedEntities: [String]
    let score: Int
}

/// A point in an entity's timeline.
struct EntityTimelineEntry {
    let articleId: String
    let date: Date
}

// MARK: - Persistence Container

private struct KnowledgeGraphStore: Codable {
    var entities: [String: KnowledgeEntity]
    var edges: [String: EntityEdge]
    var articleEntityMap: [String: [String]]
    var lastMonitorCheck: Date?
}

// MARK: - FeedKnowledgeGraph

/// Autonomous knowledge graph builder for FeedReader articles.
final class FeedKnowledgeGraph {

    // MARK: - Properties

    private var entities: [String: KnowledgeEntity] = [:]
    private var edges: [String: EntityEdge] = [:]
    private var articleEntityMap: [String: [String]] = [:]
    private var lastMonitorCheck: Date?
    private var monitorTimer: Timer?

    private let persistenceURL: URL

    // MARK: - Location Gazetteer

    private static let knownLocations: Set<String> = [
        "london", "paris", "tokyo", "beijing", "shanghai", "new york",
        "los angeles", "san francisco", "chicago", "seattle", "berlin",
        "munich", "moscow", "sydney", "melbourne", "toronto", "vancouver",
        "singapore", "hong kong", "dubai", "mumbai", "delhi", "bangalore",
        "seoul", "taipei", "bangkok", "istanbul", "cairo", "lagos",
        "nairobi", "rome", "madrid", "barcelona", "amsterdam", "zurich",
        "vienna", "stockholm", "oslo", "dublin", "brussels", "lisbon",
        "warsaw", "prague", "budapest", "washington", "boston", "austin",
        "denver", "miami", "atlanta", "houston", "dallas", "phoenix",
        "united states", "china", "india", "japan", "germany", "france",
        "united kingdom", "brazil", "canada", "australia", "russia",
        "south korea", "israel", "saudi arabia", "mexico", "indonesia",
        "africa", "europe", "asia", "silicon valley", "wall street"
    ]

    /// Words to skip when extracting person names.
    private static let nonNameWords: Set<String> = [
        "the", "a", "an", "and", "or", "but", "in", "on", "at", "to",
        "for", "of", "with", "by", "from", "is", "are", "was", "were",
        "has", "have", "had", "will", "would", "could", "should", "may",
        "might", "can", "do", "does", "did", "not", "no", "yes", "all",
        "any", "each", "every", "both", "few", "more", "most", "other",
        "some", "such", "than", "too", "very", "just", "about", "above",
        "after", "before", "between", "into", "through", "during", "out",
        "over", "under", "again", "further", "then", "once", "here",
        "there", "when", "where", "why", "how", "this", "that", "these",
        "those", "new", "old", "big", "small", "first", "last", "next",
        "also", "back", "even", "still", "well", "now", "said", "says",
        "according", "report", "reports", "monday", "tuesday", "wednesday",
        "thursday", "friday", "saturday", "sunday", "january", "february",
        "march", "april", "may", "june", "july", "august", "september",
        "october", "november", "december", "today", "yesterday", "week",
        "month", "year", "image", "photo", "video", "source", "read",
        "more", "click", "share", "comment", "like", "follow", "subscribe",
        "breaking", "update", "exclusive", "opinion", "analysis", "review",
        "however", "meanwhile", "although", "while", "since", "because",
        "despite", "though", "whether", "until", "unless", "already",
        "really", "actually", "recently", "earlier", "later", "around"
    ]

    /// Suffixes that indicate an organization name.
    private static let orgSuffixes: Set<String> = ["inc", "corp", "ltd", "llc", "co",
        "group", "foundation", "institute", "labs", "technologies",
        "systems", "solutions", "partners", "ventures", "capital"]

    /// Known organization names (tech/major).
    private static let knownOrgs: Set<String> = [
        "google", "apple", "microsoft", "amazon", "meta", "facebook",
        "openai", "anthropic", "nvidia", "tesla", "spacex", "twitter",
        "netflix", "uber", "airbnb", "spotify", "adobe", "oracle",
        "ibm", "intel", "amd", "samsung", "sony", "nintendo",
        "github", "gitlab", "docker", "kubernetes", "linux",
        "nasa", "fbi", "cia", "nsa", "fda", "who", "nato", "un",
        "eu", "sec", "fed", "ftc", "doj", "epa", "usda",
        "reuters", "bloomberg", "associated press", "bbc", "cnn",
        "nyt", "washington post", "wall street journal",
        "stanford", "mit", "harvard", "berkeley", "oxford", "cambridge"
    ]

    // MARK: - Init

    init() {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        self.persistenceURL = docs.appendingPathComponent("feed_knowledge_graph.json")
        load()
    }

    // MARK: - Ingestion

    /// Ingest an article, extract entities, and update the graph.
    @discardableResult
    func ingest(articleId: String, title: String, body: String, date: Date) -> [String] {
        if articleEntityMap[articleId] != nil { return [] }

        let text = title + " " + title + " " + body
        let extracted = extractEntities(from: text)

        var entityIds: [String] = []

        for (name, type) in extracted {
            let eid = KnowledgeEntity.makeId(from: name)
            if var existing = entities[eid] {
                existing.mentionCount += 1
                existing.lastSeen = date
                if !existing.articleIds.contains(articleId) {
                    existing.articleIds.append(articleId)
                }
                entities[eid] = existing
            } else {
                entities[eid] = KnowledgeEntity(
                    id: eid, name: name, type: type,
                    articleIds: [articleId],
                    firstSeen: date, lastSeen: date,
                    mentionCount: 1
                )
            }
            entityIds.append(eid)
        }

        let uniqueIds = Array(Set(entityIds))
        for i in 0..<uniqueIds.count {
            for j in (i + 1)..<uniqueIds.count {
                let key = EntityEdge.key(uniqueIds[i], uniqueIds[j])
                if var existing = edges[key] {
                    existing.weight += 1
                    if !existing.articleIds.contains(articleId) {
                        existing.articleIds.append(articleId)
                    }
                    edges[key] = existing
                } else {
                    edges[key] = EntityEdge(
                        entity1Id: min(uniqueIds[i], uniqueIds[j]),
                        entity2Id: max(uniqueIds[i], uniqueIds[j]),
                        weight: 1,
                        articleIds: [articleId]
                    )
                }
            }
        }

        articleEntityMap[articleId] = uniqueIds
        save()

        NotificationCenter.default.post(
            name: .knowledgeGraphUpdated,
            object: self,
            userInfo: ["articleId": articleId, "entityCount": uniqueIds.count]
        )

        return uniqueIds.compactMap { entities[$0]?.name }
    }

    // MARK: - Entity Extraction

    private func extractEntities(from text: String) -> [(String, KnowledgeEntityType)] {
        var results: [(String, KnowledgeEntityType)] = []
        var seen = Set<String>()

        let lowerText = text.lowercased()

        // 1. Location matching
        for loc in FeedKnowledgeGraph.knownLocations {
            if lowerText.contains(loc) {
                let canonical = loc.split(separator: " ")
                    .map { $0.prefix(1).uppercased() + $0.dropFirst() }
                    .joined(separator: " ")
                if !seen.contains(loc) {
                    seen.insert(loc)
                    results.append((canonical, .location))
                }
            }
        }

        // 2. Organization matching
        for org in FeedKnowledgeGraph.knownOrgs {
            if lowerText.contains(org) {
                let canonical = org.split(separator: " ")
                    .map { $0.prefix(1).uppercased() + $0.dropFirst() }
                    .joined(separator: " ")
                if !seen.contains(org) {
                    seen.insert(org)
                    results.append((canonical, .organization))
                }
            }
        }

        // 3. Capitalized sequences for people/orgs/topics
        let words = text.components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
        var i = 0
        while i < words.count {
            let word = words[i].trimmingCharacters(in: .punctuationCharacters)
            guard word.count >= 2,
                  let first = word.unicodeScalars.first,
                  CharacterSet.uppercaseLetters.contains(first) else {
                i += 1
                continue
            }

            let lower = word.lowercased()
            if FeedKnowledgeGraph.nonNameWords.contains(lower) {
                i += 1
                continue
            }

            var sequence = [word]
            var j = i + 1
            while j < words.count && sequence.count < 3 {
                let next = words[j].trimmingCharacters(in: .punctuationCharacters)
                guard next.count >= 2,
                      let nf = next.unicodeScalars.first,
                      CharacterSet.uppercaseLetters.contains(nf),
                      !FeedKnowledgeGraph.nonNameWords.contains(next.lowercased()) else {
                    break
                }
                sequence.append(next)
                j += 1
            }

            let fullName = sequence.joined(separator: " ")
            let fullKey = fullName.lowercased()

            if !seen.contains(fullKey) {
                seen.insert(fullKey)

                let lastWord = sequence.last!.lowercased()
                if FeedKnowledgeGraph.orgSuffixes.contains(lastWord) ||
                   FeedKnowledgeGraph.knownOrgs.contains(fullKey) {
                    results.append((fullName, .organization))
                } else if FeedKnowledgeGraph.knownLocations.contains(fullKey) {
                    // Already caught
                } else if sequence.count >= 2 && sequence.count <= 3 {
                    results.append((fullName, .person))
                } else if sequence.count == 1 && word.count >= 3 {
                    results.append((fullName, .topic))
                }
            }

            i = j
        }

        return results
    }

    // MARK: - Queries

    /// Find articles related to the given one through shared entities.
    func relatedArticles(for articleId: String) -> [RelatedArticle] {
        guard let myEntities = articleEntityMap[articleId] else { return [] }

        var scores: [String: (Int, [String])] = [:]

        for eid in myEntities {
            guard let entity = entities[eid] else { continue }
            for aid in entity.articleIds where aid != articleId {
                var entry = scores[aid] ?? (0, [])
                entry.0 += 1
                entry.1.append(entity.name)
                scores[aid] = entry
            }
        }

        return scores.map {
            RelatedArticle(articleId: $0.key, sharedEntities: $0.value.1, score: $0.value.0)
        }.sorted { $0.score > $1.score }
    }

    /// Get the chronological timeline of articles mentioning an entity.
    func entityTimeline(entity name: String) -> [EntityTimelineEntry] {
        let eid = KnowledgeEntity.makeId(from: name)
        guard let entity = entities[eid] else { return [] }
        return entity.articleIds.map {
            EntityTimelineEntry(articleId: $0, date: entity.firstSeen)
        }
    }

    /// Find entities that emerged recently and are gaining mentions.
    func emergingEntities(since date: Date) -> [KnowledgeEntity] {
        return entities.values
            .filter { $0.firstSeen >= date && $0.mentionCount >= 2 }
            .sorted { $0.mentionCount > $1.mentionCount }
    }

    /// Top N most-mentioned entities in the last 7 days.
    func hotEntities(topN: Int = 10) -> [KnowledgeEntity] {
        let cutoff = Date().addingTimeInterval(-7 * 24 * 3600)
        return Array(
            entities.values
                .filter { $0.lastSeen >= cutoff }
                .sorted { $0.mentionCount > $1.mentionCount }
                .prefix(topN)
        )
    }

    /// Greedy clustering of entities by shared article overlap.
    func entityClusters() -> [EntityCluster] {
        var remaining = Set(entities.keys)
        var clusters: [EntityCluster] = []

        while !remaining.isEmpty {
            guard let seed = remaining.first else { break }
            remaining.remove(seed)
            guard let seedEntity = entities[seed] else { continue }

            var clusterIds = [seed]
            let seedArticles = Set(seedEntity.articleIds)

            for eid in remaining {
                guard let entity = entities[eid] else { continue }
                let otherArticles = Set(entity.articleIds)
                let intersection = seedArticles.intersection(otherArticles).count
                let union = seedArticles.union(otherArticles).count
                if union > 0 && Double(intersection) / Double(union) > 0.3 {
                    clusterIds.append(eid)
                }
            }

            if clusterIds.count >= 2 {
                for eid in clusterIds { remaining.remove(eid) }
                let clusterEntities = clusterIds.compactMap { entities[$0] }
                let allArticles = Set(clusterEntities.flatMap { $0.articleIds })
                let label = clusterEntities
                    .max(by: { $0.mentionCount < $1.mentionCount })?.name ?? "Unknown"
                clusters.append(EntityCluster(
                    entities: clusterEntities,
                    label: label,
                    articleCount: allArticles.count
                ))
            }
        }

        return clusters.sorted { $0.articleCount > $1.articleCount }
    }

    /// Proactive recommendations based on current graph state.
    func recommendations() -> [String] {
        var recs: [String] = []
        let oneDayAgo = Date().addingTimeInterval(-24 * 3600)

        let emerging = emergingEntities(since: oneDayAgo)
        for entity in emerging.prefix(3) {
            recs.append("[Emerging] '\(entity.name)' appeared in \(entity.articleIds.count) articles recently")
        }

        let hot = hotEntities(topN: 5)
        for entity in hot.prefix(3) where !emerging.contains(where: { $0.id == entity.id }) {
            recs.append("[Hot] '\(entity.name)' mentioned \(entity.mentionCount) times across \(entity.articleIds.count) articles")
        }

        let strongEdges = edges.values
            .filter { $0.weight >= 3 }
            .sorted { $0.weight > $1.weight }
            .prefix(3)

        for edge in strongEdges {
            let name1 = entities[edge.entity1Id]?.name ?? edge.entity1Id
            let name2 = entities[edge.entity2Id]?.name ?? edge.entity2Id
            recs.append("[Link] '\(name1)' and '\(name2)' co-occur in \(edge.articleIds.count) articles")
        }

        let cls = entityClusters()
        if let top = cls.first, top.entities.count >= 3 {
            let names = top.entities.prefix(4).map { $0.name }.joined(separator: ", ")
            recs.append("[Cluster] Topic constellation: \(names) (\(top.articleCount) articles)")
        }

        if recs.isEmpty {
            recs.append("[Stats] Knowledge graph: \(entities.count) entities, \(edges.count) connections, \(articleEntityMap.count) articles")
        }

        return recs
    }

    /// Overall graph statistics.
    func stats() -> KnowledgeGraphStats {
        let top = Array(entities.values
            .sorted { $0.mentionCount > $1.mentionCount }
            .prefix(10))
        return KnowledgeGraphStats(
            totalEntities: entities.count,
            totalEdges: edges.count,
            topEntities: top,
            articlesCovered: articleEntityMap.count
        )
    }

    /// Look up an entity by name.
    func entity(named name: String) -> KnowledgeEntity? {
        return entities[KnowledgeEntity.makeId(from: name)]
    }

    /// Get all entities of a given type.
    func entitiesOfType(_ type: KnowledgeEntityType) -> [KnowledgeEntity] {
        return entities.values
            .filter { $0.type == type }
            .sorted { $0.mentionCount > $1.mentionCount }
    }

    /// Get edges for a given entity.
    func connections(for entityName: String) -> [(entity: KnowledgeEntity, weight: Int)] {
        let eid = KnowledgeEntity.makeId(from: entityName)
        var results: [(KnowledgeEntity, Int)] = []

        for edge in edges.values {
            if edge.entity1Id == eid, let other = entities[edge.entity2Id] {
                results.append((other, edge.weight))
            } else if edge.entity2Id == eid, let other = entities[edge.entity1Id] {
                results.append((other, edge.weight))
            }
        }

        return results.sorted { $0.1 > $1.1 }
    }

    // MARK: - Auto-Monitor

    /// Start periodic monitoring for emerging entities.
    func startAutoMonitor() {
        stopAutoMonitor()
        lastMonitorCheck = Date()
        monitorTimer = Timer.scheduledTimer(withTimeInterval: 300, repeats: true) { [weak self] _ in
            self?.runMonitorCheck()
        }
    }

    /// Stop the auto-monitor.
    func stopAutoMonitor() {
        monitorTimer?.invalidate()
        monitorTimer = nil
    }

    /// Whether the auto-monitor is currently running.
    var isMonitoring: Bool {
        return monitorTimer?.isValid ?? false
    }

    private func runMonitorCheck() {
        let since = lastMonitorCheck ?? Date().addingTimeInterval(-300)
        let emerging = emergingEntities(since: since)

        for entity in emerging.prefix(5) {
            NotificationCenter.default.post(
                name: .knowledgeGraphEmergingEntity,
                object: self,
                userInfo: [
                    "entityName": entity.name,
                    "entityType": entity.type.rawValue,
                    "mentionCount": entity.mentionCount
                ]
            )
        }

        lastMonitorCheck = Date()
        save()
    }

    // MARK: - Reset

    /// Clear all graph data.
    func reset() {
        entities = [:]
        edges = [:]
        articleEntityMap = [:]
        lastMonitorCheck = nil
        save()
    }

    // MARK: - Persistence

    private func save() {
        let store = KnowledgeGraphStore(
            entities: entities,
            edges: edges,
            articleEntityMap: articleEntityMap,
            lastMonitorCheck: lastMonitorCheck
        )
        do {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            encoder.outputFormatting = .prettyPrinted
            let data = try encoder.encode(store)
            try data.write(to: persistenceURL, options: .atomic)
        } catch {
            // Silent fail
        }
    }

    private func load() {
        guard FileManager.default.fileExists(atPath: persistenceURL.path) else { return }
        do {
            let data = try Data(contentsOf: persistenceURL)
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            let store = try decoder.decode(KnowledgeGraphStore.self, from: data)
            entities = store.entities
            edges = store.edges
            articleEntityMap = store.articleEntityMap
            lastMonitorCheck = store.lastMonitorCheck
        } catch {
            // Silent fail
        }
    }
}
