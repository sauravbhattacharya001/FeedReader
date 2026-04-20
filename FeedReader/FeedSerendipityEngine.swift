//
//  FeedSerendipityEngine.swift
//  FeedReader
//
//  Autonomous serendipity discovery engine that finds unexpected connections
//  between articles across different feeds. Unlike ArticleSimilarityManager
//  (which finds *similar* articles), this engine specifically looks for
//  *surprising* connections — articles that share a non-obvious link through
//  bridging concepts, lateral associations, or thematic contrasts.
//
//  Key features:
//  - Serendipity paths: chains of loosely connected articles forming
//    unexpected reading journeys (A→B→C where A and C seem unrelated)
//  - Bridge concept detection: finds concepts that connect disparate topics
//  - Surprise scoring: ranks discoveries by how unexpected they are
//    (high surprise = low topic overlap + strong conceptual bridge)
//  - Autonomous scanning: proactively discovers new connections when
//    articles are added, without user prompting
//  - Serendipity digest: periodic summary of best unexpected discoveries
//  - Exploration tangents: "you're reading about X, but did you know Y?"
//  - Connection explanations: human-readable descriptions of why two
//    distant articles are linked
//
//  The engine uses an inverted concept index with TF-IDF weighting,
//  but deliberately seeks LOW overall similarity with HIGH bridge-term
//  overlap — the opposite of a typical recommendation engine.
//
//  Persistence: JSON file in Documents directory.
//  Works entirely offline with no external dependencies.
//

import Foundation

// MARK: - Notifications

extension Notification.Name {
    /// Posted when new serendipitous connections are discovered.
    static let serendipityDiscovered = Notification.Name("SerendipityDiscoveredNotification")
    /// Posted when a serendipity path is completed.
    static let serendipityPathReady = Notification.Name("SerendipityPathReadyNotification")
}

// MARK: - SerendipityConnection

/// A surprising connection between two articles via a bridging concept.
struct SerendipityConnection: Codable, Equatable {
    let sourceArticleId: String
    let sourceTitle: String
    let sourceFeed: String
    let targetArticleId: String
    let targetTitle: String
    let targetFeed: String
    let bridgeConcepts: [String]
    let surpriseScore: Double       // 0.0–1.0, higher = more unexpected
    let explanation: String         // human-readable connection description
    let discoveredAt: Date

    static func == (lhs: SerendipityConnection, rhs: SerendipityConnection) -> Bool {
        return lhs.sourceArticleId == rhs.sourceArticleId
            && lhs.targetArticleId == rhs.targetArticleId
    }
}

// MARK: - SerendipityPath

/// A chain of articles forming an unexpected reading journey.
struct SerendipityPath: Codable {
    let id: String
    let title: String               // auto-generated descriptive title
    let steps: [SerendipityPathStep]
    let totalSurprise: Double       // aggregate surprise across all hops
    let createdAt: Date
    let theme: String               // detected overarching theme

    var length: Int { return steps.count }
}

/// A single step in a serendipity path.
struct SerendipityPathStep: Codable {
    let articleId: String
    let articleTitle: String
    let feedName: String
    let bridgeToNext: String?       // concept bridging to next step
    let transitionNote: String?     // "from X, we jump to Y because..."
}

// MARK: - SerendipityTangent

/// A proactive "did you know?" suggestion while reading an article.
struct SerendipityTangent: Codable {
    let triggerArticleId: String
    let tangentArticleId: String
    let tangentTitle: String
    let tangentFeed: String
    let hookPhrase: String          // e.g., "You're reading about Mars — did you know this cooking article also discusses iron oxide?"
    let bridgeConcept: String
    let surpriseScore: Double
}

// MARK: - SerendipityDigest

/// A periodic summary of the best serendipitous discoveries.
struct SerendipityDigest: Codable {
    let id: String
    let generatedAt: Date
    let periodStart: Date
    let periodEnd: Date
    let topConnections: [SerendipityConnection]
    let bestPath: SerendipityPath?
    let stats: SerendipityStats
}

/// Aggregate serendipity statistics.
struct SerendipityStats: Codable {
    let totalConnectionsFound: Int
    let totalPathsGenerated: Int
    let avgSurpriseScore: Double
    let topBridgeConcepts: [String]
    let mostConnectedFeeds: [String]
    let feedPairsWithMostBridges: [[String]]
}

// MARK: - Internal Types

/// An indexed article for the serendipity engine.
private struct IndexedArticle: Codable {
    let id: String
    let title: String
    let feedName: String
    let concepts: [String: Double]  // concept → TF-IDF weight
    let addedAt: Date
}

// MARK: - FeedSerendipityEngine

/// Autonomous engine that discovers unexpected connections between articles.
/// Uses bridge-concept detection to find surprising links across feeds.
class FeedSerendipityEngine {

    // MARK: - Singleton

    static let shared = FeedSerendipityEngine()

    // MARK: - Configuration

    /// Minimum surprise score to surface a connection (0.0–1.0).
    var minimumSurpriseThreshold: Double = 0.3

    /// Maximum overall topic similarity allowed (connections above this are
    /// "too obvious" and filtered out).
    var maximumSimilarityThreshold: Double = 0.4

    /// Number of top connections to include in a digest.
    var digestTopCount: Int = 10

    /// Maximum path length when generating serendipity paths.
    var maxPathLength: Int = 6

    /// Minimum path length to consider valid.
    var minPathLength: Int = 3

    // MARK: - State

    private var indexedArticles: [String: IndexedArticle] = [:]
    private var invertedIndex: [String: Set<String>] = [:]  // concept → article IDs
    private var documentFrequency: [String: Int] = [:]       // concept → doc count
    private var connections: [SerendipityConnection] = []
    private var paths: [SerendipityPath] = []
    private var digests: [SerendipityDigest] = []
    private let queue = DispatchQueue(label: "com.feedreader.serendipity", qos: .utility)
    private var persistenceURL: URL?

    // MARK: - Stop Words

    private static let stopWords: Set<String> = [
        "the", "a", "an", "and", "or", "but", "in", "on", "at", "to", "for",
        "of", "with", "by", "from", "is", "it", "that", "this", "was", "are",
        "be", "has", "have", "had", "not", "no", "do", "does", "did", "will",
        "would", "could", "should", "may", "might", "can", "shall", "been",
        "being", "as", "if", "than", "then", "so", "about", "up", "out",
        "into", "over", "after", "before", "between", "under", "above",
        "which", "who", "whom", "what", "where", "when", "how", "all",
        "each", "every", "both", "few", "more", "most", "other", "some",
        "such", "only", "own", "same", "also", "just", "very", "new",
        "one", "two", "three", "first", "last", "said", "its", "like",
        "many", "well", "back", "even", "still", "way", "take", "come",
        "make", "know", "get", "got", "there", "their", "them", "they",
        "we", "he", "she", "her", "his", "my", "your", "our", "us",
        "me", "him", "i", "you", "were", "any", "these", "those"
    ]

    // MARK: - Initialization

    private init() {
        setupPersistence()
        loadState()
    }

    // MARK: - Persistence

    private func setupPersistence() {
        if let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first {
            persistenceURL = docs.appendingPathComponent("serendipity_engine.json")
        }
    }

    private struct PersistedState: Codable {
        let articles: [String: IndexedArticle]
        let connections: [SerendipityConnection]
        let paths: [SerendipityPath]
        let digests: [SerendipityDigest]
        let documentFrequency: [String: Int]
    }

    private func loadState() {
        guard let url = persistenceURL,
              let data = try? Data(contentsOf: url),
              let state = try? JSONDecoder().decode(PersistedState.self, from: data) else { return }
        indexedArticles = state.articles
        connections = state.connections
        paths = state.paths
        digests = state.digests
        documentFrequency = state.documentFrequency
        rebuildInvertedIndex()
    }

    private func saveState() {
        guard let url = persistenceURL else { return }
        let state = PersistedState(
            articles: indexedArticles,
            connections: connections,
            paths: paths,
            digests: digests,
            documentFrequency: documentFrequency
        )
        if let data = try? JSONEncoder().encode(state) {
            try? data.write(to: url, options: .atomic)
        }
    }

    private func rebuildInvertedIndex() {
        invertedIndex.removeAll()
        for (id, article) in indexedArticles {
            for concept in article.concepts.keys {
                invertedIndex[concept, default: []].insert(id)
            }
        }
    }

    // MARK: - Concept Extraction

    /// Extract weighted concepts from text using TF-IDF-like scoring.
    private func extractConcepts(from text: String) -> [String: Double] {
        let words = tokenize(text)
        guard !words.isEmpty else { return [:] }

        // Term frequency
        var tf: [String: Int] = [:]
        for w in words {
            tf[w, default: 0] += 1
        }

        // Weighted by TF and position (title words get boost)
        let totalWords = Double(words.count)
        var concepts: [String: Double] = [:]
        for (term, count) in tf {
            let rawTF = Double(count) / totalWords
            concepts[term] = rawTF
        }

        // Also extract bigrams for richer concepts
        for i in 0..<(words.count - 1) {
            let bigram = "\(words[i]) \(words[i+1])"
            concepts[bigram, default: 0] += 0.5 / totalWords
        }

        return concepts
    }

    private func tokenize(_ text: String) -> [String] {
        let lower = text.lowercased()
        let cleaned = lower.unicodeScalars.map { CharacterSet.alphanumerics.contains($0) || $0 == " " ? Character($0) : Character(" ") }
        return String(cleaned)
            .split(separator: " ")
            .map { String($0) }
            .filter { $0.count > 2 && !FeedSerendipityEngine.stopWords.contains($0) }
    }

    // MARK: - Article Indexing

    /// Index an article for serendipity discovery. Called autonomously when
    /// new articles arrive.
    func indexArticle(id: String, title: String, body: String, feedName: String) {
        queue.async { [weak self] in
            guard let self = self else { return }
            guard self.indexedArticles[id] == nil else { return }

            let fullText = "\(title) \(title) \(body)"  // title weighted 2x
            let concepts = self.extractConcepts(from: fullText)
            guard !concepts.isEmpty else { return }

            let article = IndexedArticle(
                id: id,
                title: title,
                feedName: feedName,
                concepts: concepts,
                addedAt: Date()
            )

            self.indexedArticles[id] = article

            // Update inverted index and document frequency
            for concept in concepts.keys {
                self.invertedIndex[concept, default: []].insert(id)
                self.documentFrequency[concept, default: 0] += 1
            }

            // Autonomous: scan for new serendipitous connections
            let newConnections = self.findConnectionsFor(articleId: id)
            if !newConnections.isEmpty {
                self.connections.append(contentsOf: newConnections)
                self.saveState()
                DispatchQueue.main.async {
                    NotificationCenter.default.post(
                        name: .serendipityDiscovered,
                        object: nil,
                        userInfo: ["connections": newConnections]
                    )
                }
            }
        }
    }

    /// Batch index multiple articles.
    func indexArticles(_ articles: [(id: String, title: String, body: String, feedName: String)]) {
        for a in articles {
            indexArticle(id: a.id, title: a.title, body: a.body, feedName: a.feedName)
        }
    }

    // MARK: - Connection Discovery

    /// Find serendipitous connections for a specific article.
    private func findConnectionsFor(articleId: String) -> [SerendipityConnection] {
        guard let source = indexedArticles[articleId] else { return [] }
        let totalDocs = Double(max(indexedArticles.count, 1))
        var results: [SerendipityConnection] = []

        // Find candidate articles that share at least one concept but from different feeds
        var candidates: [String: Set<String>] = [:]  // articleId → shared concepts
        for (concept, _) in source.concepts {
            guard let articleIds = invertedIndex[concept] else { continue }
            for candidateId in articleIds {
                guard candidateId != articleId else { continue }
                guard let candidate = indexedArticles[candidateId],
                      candidate.feedName != source.feedName else { continue }
                candidates[candidateId, default: []].insert(concept)
            }
        }

        for (candidateId, sharedConcepts) in candidates {
            guard let target = indexedArticles[candidateId] else { continue }

            // Calculate overall cosine similarity (we want LOW)
            let similarity = cosineSimilarity(source.concepts, target.concepts, totalDocs: totalDocs)

            // Skip if too similar (obvious) or no shared concepts
            guard similarity < maximumSimilarityThreshold else { continue }
            guard sharedConcepts.count >= 1 else { continue }

            // Calculate surprise: high when similarity is low but bridge concepts are strong
            let bridgeStrength = calculateBridgeStrength(
                sharedConcepts: sharedConcepts,
                sourceConcepts: source.concepts,
                targetConcepts: target.concepts,
                totalDocs: totalDocs
            )

            // Surprise = bridge strength × (1 - similarity)
            let surprise = bridgeStrength * (1.0 - similarity)
            guard surprise >= minimumSurpriseThreshold else { continue }

            // Find the best bridge concepts (rare globally but present in both)
            let rankedBridges = rankBridgeConcepts(
                sharedConcepts: sharedConcepts,
                totalDocs: totalDocs
            )

            let explanation = generateExplanation(
                sourceTitle: source.title,
                targetTitle: target.title,
                bridges: rankedBridges
            )

            let connection = SerendipityConnection(
                sourceArticleId: articleId,
                sourceTitle: source.title,
                sourceFeed: source.feedName,
                targetArticleId: candidateId,
                targetTitle: target.title,
                targetFeed: target.feedName,
                bridgeConcepts: Array(rankedBridges.prefix(5)),
                surpriseScore: min(surprise, 1.0),
                explanation: explanation,
                discoveredAt: Date()
            )

            // Avoid duplicate connections
            if !connections.contains(connection) {
                results.append(connection)
            }
        }

        return results.sorted { $0.surpriseScore > $1.surpriseScore }
    }

    private func cosineSimilarity(_ a: [String: Double], _ b: [String: Double], totalDocs: Double) -> Double {
        let allTerms = Set(a.keys).union(Set(b.keys))
        var dotProduct = 0.0
        var normA = 0.0
        var normB = 0.0

        for term in allTerms {
            let idf = log(totalDocs / Double(max(documentFrequency[term] ?? 1, 1)))
            let wA = (a[term] ?? 0) * idf
            let wB = (b[term] ?? 0) * idf
            dotProduct += wA * wB
            normA += wA * wA
            normB += wB * wB
        }

        guard normA > 0, normB > 0 else { return 0 }
        return dotProduct / (sqrt(normA) * sqrt(normB))
    }

    private func calculateBridgeStrength(
        sharedConcepts: Set<String>,
        sourceConcepts: [String: Double],
        targetConcepts: [String: Double],
        totalDocs: Double
    ) -> Double {
        guard !sharedConcepts.isEmpty else { return 0 }

        var totalStrength = 0.0
        for concept in sharedConcepts {
            let df = Double(documentFrequency[concept] ?? 1)
            let idf = log(totalDocs / df)
            let sourceWeight = sourceConcepts[concept] ?? 0
            let targetWeight = targetConcepts[concept] ?? 0
            // Bridge is strong when concept is rare globally but important in both docs
            totalStrength += idf * min(sourceWeight, targetWeight)
        }

        // Normalize to 0–1 range (heuristic cap)
        return min(totalStrength / Double(sharedConcepts.count), 1.0)
    }

    private func rankBridgeConcepts(sharedConcepts: Set<String>, totalDocs: Double) -> [String] {
        return sharedConcepts.sorted { a, b in
            let idfA = log(totalDocs / Double(max(documentFrequency[a] ?? 1, 1)))
            let idfB = log(totalDocs / Double(max(documentFrequency[b] ?? 1, 1)))
            return idfA > idfB  // rarer concepts first
        }
    }

    private func generateExplanation(sourceTitle: String, targetTitle: String, bridges: [String]) -> String {
        guard let primary = bridges.first else {
            return "An unexpected connection between these articles."
        }

        if bridges.count == 1 {
            return "These articles from different worlds both touch on \"\(primary)\" — a surprising thread connecting \"\(sourceTitle)\" to \"\(targetTitle)\"."
        }

        let secondary = bridges.dropFirst().prefix(2).joined(separator: "\" and \"")
        return "Despite covering different topics, both articles share the concepts of \"\(primary)\", \"\(secondary)\" — bridging \"\(sourceTitle)\" to \"\(targetTitle)\"."
    }

    // MARK: - Serendipity Paths

    /// Generate a serendipity path — a chain of loosely connected articles
    /// forming an unexpected reading journey.
    func generatePath(startingFrom articleId: String? = nil) -> SerendipityPath? {
        var visited: Set<String> = []
        var steps: [SerendipityPathStep] = []
        var totalSurprise = 0.0

        // Pick a random starting article if none specified
        let startId: String
        if let given = articleId, indexedArticles[given] != nil {
            startId = given
        } else {
            let allIds = Array(indexedArticles.keys)
            guard !allIds.isEmpty else { return nil }
            startId = allIds[Int.random(in: 0..<allIds.count)]
        }

        guard let startArticle = indexedArticles[startId] else { return nil }
        visited.insert(startId)
        steps.append(SerendipityPathStep(
            articleId: startId,
            articleTitle: startArticle.title,
            feedName: startArticle.feedName,
            bridgeToNext: nil,
            transitionNote: nil
        ))

        // Greedily extend the path by picking the most surprising unvisited connection
        var currentId = startId
        for _ in 1..<maxPathLength {
            let candidates = findConnectionsFor(articleId: currentId)
                .filter { !visited.contains($0.targetArticleId) }

            guard let best = candidates.first else { break }

            visited.insert(best.targetArticleId)
            totalSurprise += best.surpriseScore

            // Update previous step's bridge
            if var lastStep = steps.last {
                lastStep = SerendipityPathStep(
                    articleId: lastStep.articleId,
                    articleTitle: lastStep.articleTitle,
                    feedName: lastStep.feedName,
                    bridgeToNext: best.bridgeConcepts.first,
                    transitionNote: best.explanation
                )
                steps[steps.count - 1] = lastStep
            }

            guard let nextArticle = indexedArticles[best.targetArticleId] else { break }
            steps.append(SerendipityPathStep(
                articleId: best.targetArticleId,
                articleTitle: nextArticle.title,
                feedName: nextArticle.feedName,
                bridgeToNext: nil,
                transitionNote: nil
            ))

            currentId = best.targetArticleId
        }

        guard steps.count >= minPathLength else { return nil }

        let path = SerendipityPath(
            id: UUID().uuidString,
            title: generatePathTitle(steps: steps),
            steps: steps,
            totalSurprise: totalSurprise,
            createdAt: Date(),
            theme: detectPathTheme(steps: steps)
        )

        queue.async { [weak self] in
            self?.paths.append(path)
            self?.saveState()
            DispatchQueue.main.async {
                NotificationCenter.default.post(name: .serendipityPathReady, object: nil, userInfo: ["path": path])
            }
        }

        return path
    }

    private func generatePathTitle(steps: [SerendipityPathStep]) -> String {
        guard let first = steps.first, let last = steps.last else { return "Serendipity Path" }
        let feedCount = Set(steps.map { $0.feedName }).count
        return "From \"\(truncate(first.articleTitle, to: 30))\" to \"\(truncate(last.articleTitle, to: 30))\" across \(feedCount) feeds"
    }

    private func detectPathTheme(steps: [SerendipityPathStep]) -> String {
        // Collect all bridge concepts along the path
        let bridges = steps.compactMap { $0.bridgeToNext }
        guard !bridges.isEmpty else { return "exploration" }

        // Most common bridge concept = rough theme
        var freq: [String: Int] = [:]
        for b in bridges { freq[b, default: 0] += 1 }
        return freq.max(by: { $0.value < $1.value })?.key ?? "exploration"
    }

    private func truncate(_ s: String, to length: Int) -> String {
        if s.count <= length { return s }
        return String(s.prefix(length)) + "…"
    }

    // MARK: - Tangents (Proactive Suggestions)

    /// Get serendipity tangents for an article currently being read.
    /// Returns "did you know?" style suggestions.
    func tangentsForArticle(id: String, limit: Int = 3) -> [SerendipityTangent] {
        guard let source = indexedArticles[id] else { return [] }
        let totalDocs = Double(max(indexedArticles.count, 1))

        var tangents: [SerendipityTangent] = []

        // Find articles with surprising single-concept bridges
        for (concept, weight) in source.concepts {
            guard let linkedIds = invertedIndex[concept] else { continue }
            let idf = log(totalDocs / Double(max(documentFrequency[concept] ?? 1, 1)))
            // Only rare-ish concepts make good tangents
            guard idf > 1.5 else { continue }

            for targetId in linkedIds {
                guard targetId != id else { continue }
                guard let target = indexedArticles[targetId] else { continue }
                guard target.feedName != source.feedName else { continue }

                let similarity = cosineSimilarity(source.concepts, target.concepts, totalDocs: totalDocs)
                guard similarity < 0.25 else { continue }  // must be quite different

                let surprise = idf * weight * (1.0 - similarity)
                guard surprise >= minimumSurpriseThreshold else { continue }

                let hook = "You're reading about \(truncate(source.title, to: 40)) — unexpectedly, \"\(target.title)\" also explores \"\(concept)\"."

                tangents.append(SerendipityTangent(
                    triggerArticleId: id,
                    tangentArticleId: targetId,
                    tangentTitle: target.title,
                    tangentFeed: target.feedName,
                    hookPhrase: hook,
                    bridgeConcept: concept,
                    surpriseScore: min(surprise, 1.0)
                ))
            }
        }

        return Array(tangents.sorted { $0.surpriseScore > $1.surpriseScore }.prefix(limit))
    }

    // MARK: - Digest Generation

    /// Generate a serendipity digest for a time period.
    func generateDigest(from start: Date, to end: Date) -> SerendipityDigest {
        let periodConnections = connections.filter { $0.discoveredAt >= start && $0.discoveredAt <= end }
        let periodPaths = paths.filter { $0.createdAt >= start && $0.createdAt <= end }

        let topConnections = Array(periodConnections.sorted { $0.surpriseScore > $1.surpriseScore }.prefix(digestTopCount))
        let bestPath = periodPaths.max(by: { $0.totalSurprise < $1.totalSurprise })

        // Compute stats
        let avgSurprise = periodConnections.isEmpty ? 0.0 :
            periodConnections.map { $0.surpriseScore }.reduce(0, +) / Double(periodConnections.count)

        var bridgeFreq: [String: Int] = [:]
        for conn in periodConnections {
            for b in conn.bridgeConcepts { bridgeFreq[b, default: 0] += 1 }
        }
        let topBridges = Array(bridgeFreq.sorted { $0.value > $1.value }.prefix(10).map { $0.key })

        var feedFreq: [String: Int] = [:]
        for conn in periodConnections {
            feedFreq[conn.sourceFeed, default: 0] += 1
            feedFreq[conn.targetFeed, default: 0] += 1
        }
        let topFeeds = Array(feedFreq.sorted { $0.value > $1.value }.prefix(5).map { $0.key })

        var pairFreq: [String: Int] = [:]
        for conn in periodConnections {
            let pair = [conn.sourceFeed, conn.targetFeed].sorted().joined(separator: "↔")
            pairFreq[pair, default: 0] += 1
        }
        let topPairs = Array(pairFreq.sorted { $0.value > $1.value }.prefix(5).map { $0.key.components(separatedBy: "↔") })

        let stats = SerendipityStats(
            totalConnectionsFound: periodConnections.count,
            totalPathsGenerated: periodPaths.count,
            avgSurpriseScore: avgSurprise,
            topBridgeConcepts: topBridges,
            mostConnectedFeeds: topFeeds,
            feedPairsWithMostBridges: topPairs
        )

        let digest = SerendipityDigest(
            id: UUID().uuidString,
            generatedAt: Date(),
            periodStart: start,
            periodEnd: end,
            topConnections: topConnections,
            bestPath: bestPath,
            stats: stats
        )

        queue.async { [weak self] in
            self?.digests.append(digest)
            self?.saveState()
        }

        return digest
    }

    // MARK: - Queries

    /// Get the most surprising connections discovered so far.
    func topConnections(limit: Int = 20) -> [SerendipityConnection] {
        return Array(connections.sorted { $0.surpriseScore > $1.surpriseScore }.prefix(limit))
    }

    /// Get all generated serendipity paths.
    func allPaths() -> [SerendipityPath] {
        return paths.sorted { $0.totalSurprise > $1.totalSurprise }
    }

    /// Get connections involving a specific feed.
    func connectionsForFeed(_ feedName: String) -> [SerendipityConnection] {
        return connections.filter { $0.sourceFeed == feedName || $0.targetFeed == feedName }
            .sorted { $0.surpriseScore > $1.surpriseScore }
    }

    /// Get the total number of indexed articles.
    var articleCount: Int { return indexedArticles.count }

    /// Get the total number of discovered connections.
    var connectionCount: Int { return connections.count }

    /// Get all digests.
    func allDigests() -> [SerendipityDigest] {
        return digests.sorted { $0.generatedAt > $1.generatedAt }
    }

    // MARK: - Export

    /// Export all connections as JSON data.
    func exportConnectionsJSON() -> Data? {
        return try? JSONEncoder().encode(connections)
    }

    /// Export connections as a plain text summary.
    func exportConnectionsText() -> String {
        var lines: [String] = ["=== Serendipity Report ===", ""]
        lines.append("Total connections: \(connections.count)")
        lines.append("Total paths: \(paths.count)")
        lines.append("Articles indexed: \(indexedArticles.count)")
        lines.append("")

        let top = topConnections(limit: 20)
        if !top.isEmpty {
            lines.append("--- Top Surprising Connections ---")
            for (i, conn) in top.enumerated() {
                lines.append("")
                lines.append("\(i+1). Surprise: \(String(format: "%.0f%%", conn.surpriseScore * 100))")
                lines.append("   \(conn.sourceTitle) [\(conn.sourceFeed)]")
                lines.append("   ↔ \(conn.targetTitle) [\(conn.targetFeed)]")
                lines.append("   Bridge: \(conn.bridgeConcepts.joined(separator: ", "))")
                lines.append("   \(conn.explanation)")
            }
        }

        if !paths.isEmpty {
            lines.append("")
            lines.append("--- Serendipity Paths ---")
            for path in paths.prefix(5) {
                lines.append("")
                lines.append("🗺 \(path.title)")
                lines.append("  Total surprise: \(String(format: "%.0f%%", path.totalSurprise * 100)) | Theme: \(path.theme)")
                for (j, step) in path.steps.enumerated() {
                    let prefix = j == 0 ? "  ▶" : "  →"
                    lines.append("\(prefix) \(step.articleTitle) [\(step.feedName)]")
                    if let bridge = step.bridgeToNext {
                        lines.append("    via \"\(bridge)\"")
                    }
                }
            }
        }

        return lines.joined(separator: "\n")
    }

    // MARK: - Maintenance

    /// Remove articles older than the specified date from the index.
    func pruneArticlesBefore(_ date: Date) {
        queue.async { [weak self] in
            guard let self = self else { return }
            let staleIds = self.indexedArticles.filter { $0.value.addedAt < date }.map { $0.key }
            for id in staleIds {
                if let article = self.indexedArticles.removeValue(forKey: id) {
                    for concept in article.concepts.keys {
                        self.invertedIndex[concept]?.remove(id)
                        if self.invertedIndex[concept]?.isEmpty == true {
                            self.invertedIndex.removeValue(forKey: concept)
                        }
                    }
                }
            }
            // Remove connections referencing pruned articles
            self.connections.removeAll { staleIds.contains($0.sourceArticleId) || staleIds.contains($0.targetArticleId) }
            self.saveState()
        }
    }

    /// Clear all state.
    func reset() {
        queue.async { [weak self] in
            self?.indexedArticles.removeAll()
            self?.invertedIndex.removeAll()
            self?.documentFrequency.removeAll()
            self?.connections.removeAll()
            self?.paths.removeAll()
            self?.digests.removeAll()
            self?.saveState()
        }
    }
}
