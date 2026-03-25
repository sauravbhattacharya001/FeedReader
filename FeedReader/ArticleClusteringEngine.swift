//
//  ArticleClusteringEngine.swift
//  FeedReader
//
//  Groups similar articles together using TF-IDF keyword overlap so users
//  can read about the same topic in batches. Works entirely offline with
//  no external dependencies beyond Foundation.
//
//  Usage:
//    let engine = ArticleClusteringEngine()
//    engine.addArticles(stories)
//    let clusters = engine.cluster(maxClusters: 10, similarityThreshold: 0.25)
//    // Each cluster has a label, representative keywords, and member stories.
//

import Foundation

// MARK: - Notifications

extension Notification.Name {
    static let articleClustersDidUpdate = Notification.Name("ArticleClustersDidUpdateNotification")
}

// MARK: - ArticleCluster

/// A group of related articles sharing similar content.
struct ArticleCluster: Codable {
    /// Unique identifier for this cluster.
    let id: UUID
    /// Human-readable label derived from top keywords.
    let label: String
    /// The top keywords that define this cluster's topic.
    let keywords: [String]
    /// Links of the articles in this cluster (references into Story objects).
    let articleLinks: [String]
    /// Number of articles in the cluster.
    var count: Int { articleLinks.count }
    /// When the cluster was generated.
    let createdAt: Date
}

// MARK: - ClusterSummary

/// Lightweight overview of clustering results.
struct ClusterSummary: Codable {
    let totalArticles: Int
    let totalClusters: Int
    let averageClusterSize: Double
    let largestClusterLabel: String?
    let unclustered: Int
    let generatedAt: Date
}

// MARK: - ArticleClusteringEngine

/// Groups articles by content similarity using TF-IDF cosine similarity.
class ArticleClusteringEngine {

    // MARK: - Types

    /// Internal representation of an article for vectorization.
    private struct ArticleVector {
        let link: String
        let title: String
        let tfidf: [String: Double]
    }

    // MARK: - Properties

    private var articles: [ArticleVector] = []
    private var documentFrequency: [String: Int] = [:]
    private var totalDocuments: Int = 0

    /// Stop words filtered out during tokenization.
    private static let stopWords: Set<String> = [
        "the", "a", "an", "and", "or", "but", "in", "on", "at", "to", "for",
        "of", "with", "by", "from", "is", "it", "that", "this", "was", "are",
        "be", "has", "had", "have", "will", "would", "could", "should", "may",
        "can", "do", "did", "not", "so", "if", "as", "its", "his", "her",
        "he", "she", "they", "we", "you", "all", "been", "were", "being",
        "their", "them", "than", "then", "when", "what", "which", "who",
        "how", "more", "some", "any", "no", "just", "about", "also", "into",
        "out", "up", "one", "new", "said", "like", "over", "after", "most",
        "only", "other", "very", "your", "our", "such", "each", "those",
        "these", "many", "much", "own", "same", "both", "here", "there"
    ]

    // MARK: - Singleton

    static let shared = ArticleClusteringEngine()

    init() {}

    // MARK: - Public API

    /// Clears all articles and resets internal state.
    func reset() {
        articles.removeAll()
        documentFrequency.removeAll()
        articleNorms.removeAll()
        totalDocuments = 0
    }

    /// Add stories to the engine for clustering.
    func addArticles(_ stories: [Story]) {
        // First pass: compute document frequencies
        var rawTokenSets: [(String, String, Set<String>)] = []

        for story in stories {
            let tokens = tokenize(story.title + " " + story.body)
            let tokenSet = Set(tokens)
            rawTokenSets.append((story.link, story.title, tokenSet))
            for token in tokenSet {
                documentFrequency[token, default: 0] += 1
            }
        }

        totalDocuments += stories.count

        // Second pass: compute TF-IDF vectors
        for (link, title, tokenSet) in rawTokenSets {
            let tokens = Array(tokenSet)
            let termFreq = computeTermFrequency(Array(tokenSet))
            var tfidf: [String: Double] = [:]

            for token in tokens {
                let tf = termFreq[token] ?? 0
                let df = documentFrequency[token] ?? 1
                let idf = log(Double(totalDocuments) / Double(df))
                let score = tf * idf
                if score > 0 {
                    tfidf[token] = score
                }
            }

            let norm = sqrt(tfidf.values.reduce(0.0) { $0 + $1 * $1 })
            articles.append(ArticleVector(link: link, title: title, tfidf: tfidf))
            articleNorms.append(norm)
        }
    }

    /// Cluster articles using agglomerative (bottom-up) clustering.
    ///
    /// - Parameters:
    ///   - maxClusters: Maximum number of clusters to return (default 15).
    ///   - similarityThreshold: Minimum cosine similarity to merge clusters (0-1, default 0.2).
    /// - Returns: Array of `ArticleCluster` sorted by size (largest first).
    func cluster(maxClusters: Int = 15, similarityThreshold: Double = 0.2) -> [ArticleCluster] {
        guard !articles.isEmpty else { return [] }

        let n = articles.count

        // Pre-compute pairwise similarity matrix (upper triangle).
        // This avoids redundant O(|V|) cosine computations during the
        // O(n²)-per-merge agglomerative loop, reducing total similarity
        // work from O(n³ · |V|) to O(n² · |V|) + O(n³) index lookups.
        var simMatrix: [[Double]] = Array(repeating: Array(repeating: 0.0, count: n), count: n)
        for i in 0..<n {
            for j in (i + 1)..<n {
                let s = cosineSimilarity(articles[i].tfidf, articles[j].tfidf,
                                         normA: articleNorms[i], normB: articleNorms[j])
                simMatrix[i][j] = s
                simMatrix[j][i] = s
            }
        }

        // Initialize: each article is its own cluster
        var clusters: [[Int]] = articles.indices.map { [$0] }

        // Pre-compute cluster-pair average similarities using the matrix.
        // Track them in a dictionary keyed by (clusterIndex_i, clusterIndex_j).
        // On merge, only recompute similarities for the merged cluster.

        // Agglomerative merging with cached similarity lookups
        while clusters.count > maxClusters {
            var bestSim = -1.0
            var bestI = 0
            var bestJ = 1

            for i in 0..<clusters.count {
                for j in (i + 1)..<clusters.count {
                    let sim = averageLinkSimilarityFromMatrix(clusters[i], clusters[j], simMatrix: simMatrix)
                    if sim > bestSim {
                        bestSim = sim
                        bestI = i
                        bestJ = j
                    }
                }
            }

            // Stop if best similarity is below threshold
            if bestSim < similarityThreshold { break }

            // Merge j into i
            clusters[bestI].append(contentsOf: clusters[bestJ])
            clusters.remove(at: bestJ)
        }

        // Build ArticleCluster objects
        let now = Date()
        let result: [ArticleCluster] = clusters
            .filter { $0.count >= 2 } // Only meaningful clusters
            .map { indices in
                let links = indices.map { articles[$0].link }
                let keywords = topKeywords(for: indices, count: 5)
                let label = keywords.prefix(3).joined(separator: ", ")
                return ArticleCluster(
                    id: UUID(),
                    label: label.isEmpty ? "Misc" : label.capitalized,
                    keywords: keywords,
                    articleLinks: links,
                    createdAt: now
                )
            }
            .sorted { $0.count > $1.count }

        NotificationCenter.default.post(name: .articleClustersDidUpdate, object: result)
        return result
    }

    /// Generate a summary of the last clustering run.
    func summary(from clusters: [ArticleCluster]) -> ClusterSummary {
        let clusteredCount = clusters.reduce(0) { $0 + $1.count }
        let avgSize = clusters.isEmpty ? 0 : Double(clusteredCount) / Double(clusters.count)
        return ClusterSummary(
            totalArticles: articles.count,
            totalClusters: clusters.count,
            averageClusterSize: avgSize,
            largestClusterLabel: clusters.first?.label,
            unclustered: articles.count - clusteredCount,
            generatedAt: Date()
        )
    }

    /// Find articles similar to a given story link.
    func findSimilar(to link: String, limit: Int = 5) -> [(link: String, title: String, similarity: Double)] {
        guard let sourceIdx = articles.firstIndex(where: { $0.link == link }) else {
            return []
        }

        let source = articles[sourceIdx]
        let sourceNorm = articleNorms[sourceIdx]
        var results: [(link: String, title: String, similarity: Double)] = []

        for (idx, article) in articles.enumerated() where idx != sourceIdx {
            let sim = cosineSimilarity(source.tfidf, article.tfidf,
                                       normA: sourceNorm, normB: articleNorms[idx])
            if sim > 0.05 {
                results.append((link: article.link, title: article.title, similarity: sim))
            }
        }

        return results
            .sorted { $0.similarity > $1.similarity }
            .prefix(limit)
            .map { $0 }
    }

    // MARK: - Tokenization

    private func tokenize(_ text: String) -> [String] {
        let lowered = text.lowercased()
        let cleaned = lowered.unicodeScalars.filter {
            CharacterSet.alphanumerics.contains($0) || $0 == " "
        }
        let words = String(cleaned)
            .split(separator: " ")
            .map(String.init)
            .filter { $0.count >= 3 && !Self.stopWords.contains($0) }
        return words
    }

    private func computeTermFrequency(_ tokens: [String]) -> [String: Double] {
        var freq: [String: Double] = [:]
        let total = Double(tokens.count)
        for token in tokens {
            freq[token, default: 0] += 1.0 / total
        }
        return freq
    }

    // MARK: - Similarity

    /// Pre-computed L2 norms for each article vector, populated in `addArticles`.
    /// Avoids recomputing O(|V|) norm sums on every `cosineSimilarity` call —
    /// critical since clustering invokes similarity O(n²) times.
    private var articleNorms: [Double] = []

    private func cosineSimilarity(_ a: [String: Double], _ b: [String: Double], normA: Double, normB: Double) -> Double {
        // Iterate over the smaller dictionary for fewer lookups
        let (smaller, larger) = a.count <= b.count ? (a, b) : (b, a)
        var dot = 0.0
        for (key, valS) in smaller {
            if let valL = larger[key] {
                dot += valS * valL
            }
        }
        guard dot > 0 else { return 0 }
        let denom = normA * normB
        return denom > 0 ? dot / denom : 0
    }

    /// Backwards-compatible overload for callers without pre-computed norms.
    private func cosineSimilarity(_ a: [String: Double], _ b: [String: Double]) -> Double {
        let normA = sqrt(a.values.reduce(0.0) { $0 + $1 * $1 })
        let normB = sqrt(b.values.reduce(0.0) { $0 + $1 * $1 })
        return cosineSimilarity(a, b, normA: normA, normB: normB)
    }

    /// Average-link similarity between two clusters using pre-computed matrix.
    /// O(|A|·|B|) index lookups instead of O(|A|·|B|·|V|) cosine computations.
    private func averageLinkSimilarityFromMatrix(_ clusterA: [Int], _ clusterB: [Int], simMatrix: [[Double]]) -> Double {
        var total = 0.0
        for i in clusterA {
            for j in clusterB {
                total += simMatrix[i][j]
            }
        }
        let count = clusterA.count * clusterB.count
        return count > 0 ? total / Double(count) : 0
    }

    /// Average-link similarity between two clusters (original, for backward compat).
    private func averageLinkSimilarity(_ clusterA: [Int], _ clusterB: [Int]) -> Double {
        var total = 0.0
        var count = 0
        for i in clusterA {
            for j in clusterB {
                total += cosineSimilarity(articles[i].tfidf, articles[j].tfidf)
                count += 1
            }
        }
        return count > 0 ? total / Double(count) : 0
    }

    /// Extract top keywords from a set of article indices.
    private func topKeywords(for indices: [Int], count: Int) -> [String] {
        var aggregated: [String: Double] = [:]
        for idx in indices {
            for (word, score) in articles[idx].tfidf {
                aggregated[word, default: 0] += score
            }
        }
        return aggregated
            .sorted { $0.value > $1.value }
            .prefix(count)
            .map { $0.key }
    }
}
