//
//  ArticleSimilarityManager.swift
//  FeedReader
//
//  Finds similar articles across feeds using TF-IDF keyword similarity.
//  Users can discover related content they might have missed from other feeds.
//  Works entirely offline with no external dependencies.
//

import Foundation

// MARK: - Notification

extension Notification.Name {
    static let similarityIndexDidUpdate = Notification.Name("SimilarityIndexDidUpdateNotification")
}

// MARK: - SimilarArticle

/// Represents a match result with a similarity score.
struct SimilarArticle {
    let story: Story
    let score: Double       // 0.0 to 1.0 cosine similarity
    let sharedKeywords: [String]  // top shared terms for explainability
}

// MARK: - ArticleSimilarityManager

/// Finds similar articles using TF-IDF cosine similarity on article titles
/// and bodies. Maintains an inverted index for efficient lookup.
class ArticleSimilarityManager {
    
    // MARK: - Singleton
    
    static let shared = ArticleSimilarityManager()
    
    // MARK: - Types
    
    /// Internal representation of a document in the index.
    private struct IndexedDocument {
        let link: String
        let title: String
        let feedName: String
        let termFrequencies: [String: Double]  // TF vector (normalized)
        weak var story: Story?
    }
    
    // MARK: - Properties
    
    /// All indexed documents, keyed by link.
    private var documents: [String: IndexedDocument] = [:]
    
    /// Inverted index: term → set of document links containing it.
    private var invertedIndex: [String: Set<String>] = [:]
    
    /// IDF cache: term → inverse document frequency.
    private var idfCache: [String: Double] = [:]
    
    /// Whether IDF needs recalculation.
    private var idfDirty = true
    
    /// Common English stop words — provided by TextAnalyzer.shared.
    /// Kept as a forwarding reference for any internal code that
    /// referenced ArticleSimilarityManager.stopWords directly.
    private static var stopWords: Set<String> { TextAnalyzer.stopWords }
    
    /// Minimum term length to index.
    private static let minTermLength = TextAnalyzer.defaultMinTermLength
    
    /// Maximum number of similar articles to return.
    static let defaultLimit = 10
    
    /// Minimum similarity score to include in results.
    static let defaultThreshold = 0.05
    
    // MARK: - Initialization
    
    init() {}
    
    // MARK: - Indexing
    
    /// Index a single story. Call this when articles are loaded or fetched.
    func index(story: Story) {
        let text = "\(story.title) \(story.title) \(story.body)"  // title weighted 2x
        let terms = tokenize(text)
        let tf = computeTF(terms)
        
        // Remove old entry if re-indexing
        if let old = documents[story.link] {
            for term in old.termFrequencies.keys {
                invertedIndex[term]?.remove(story.link)
                if invertedIndex[term]?.isEmpty == true {
                    invertedIndex.removeValue(forKey: term)
                }
            }
        }
        
        let doc = IndexedDocument(
            link: story.link,
            title: story.title,
            feedName: story.sourceFeedName ?? "Unknown",
            termFrequencies: tf,
            story: story
        )
        documents[story.link] = doc
        
        for term in tf.keys {
            invertedIndex[term, default: []].insert(story.link)
        }
        
        idfDirty = true
    }
    
    /// Index multiple stories at once.
    func indexAll(stories: [Story]) {
        for story in stories {
            index(story: story)
        }
        NotificationCenter.default.post(name: .similarityIndexDidUpdate, object: nil)
    }
    
    /// Remove a story from the index.
    func remove(link: String) {
        guard let doc = documents.removeValue(forKey: link) else { return }
        for term in doc.termFrequencies.keys {
            invertedIndex[term]?.remove(link)
            if invertedIndex[term]?.isEmpty == true {
                invertedIndex.removeValue(forKey: term)
            }
        }
        idfDirty = true
    }
    
    // MARK: - Similarity Search
    
    /// Find articles similar to the given story.
    ///
    /// - Parameters:
    ///   - story: The reference article to find similarities for.
    ///   - limit: Maximum number of results (default 10).
    ///   - threshold: Minimum cosine similarity (default 0.05).
    ///   - excludeSameFeed: If true, excludes articles from the same feed.
    /// - Returns: Array of SimilarArticle sorted by descending similarity.
    func findSimilar(to story: Story, limit: Int = defaultLimit,
                     threshold: Double = defaultThreshold,
                     excludeSameFeed: Bool = false) -> [SimilarArticle] {
        
        // Ensure the query story is indexed
        if documents[story.link] == nil {
            index(story: story)
        }
        
        guard let queryDoc = documents[story.link] else { return [] }
        
        refreshIDFIfNeeded()
        
        let queryVector = tfidfVector(for: queryDoc)
        
        // Find candidate documents that share at least one term
        var candidateLinks = Set<String>()
        for term in queryDoc.termFrequencies.keys {
            if let links = invertedIndex[term] {
                candidateLinks.formUnion(links)
            }
        }
        candidateLinks.remove(story.link)  // exclude self
        
        var results: [SimilarArticle] = []
        
        for link in candidateLinks {
            guard let doc = documents[link] else { continue }
            
            if excludeSameFeed && doc.feedName == queryDoc.feedName {
                continue
            }
            
            let docVector = tfidfVector(for: doc)
            let similarity = cosineSimilarity(queryVector, docVector)
            
            guard similarity >= threshold else { continue }
            
            // Find shared keywords for explainability
            let shared = findSharedKeywords(queryDoc, doc, topN: 5)
            
            // Try to use the stored weak reference, otherwise create a minimal story
            if let originalStory = doc.story {
                results.append(SimilarArticle(
                    story: originalStory, score: similarity, sharedKeywords: shared
                ))
            }
        }
        
        results.sort { $0.score > $1.score }
        return Array(results.prefix(limit))
    }
    
    /// Find articles similar to a given text query (not necessarily an indexed story).
    func findSimilar(toText text: String, limit: Int = defaultLimit,
                     threshold: Double = defaultThreshold) -> [SimilarArticle] {
        let terms = tokenize(text)
        let tf = computeTF(terms)
        
        refreshIDFIfNeeded()
        
        // Build TF-IDF query vector. Use the same fallback IDF as
        // tfidfVector(for:) (1.0) so cosine similarity is consistent
        // between query terms and document terms.
        var properQuery: [String: Double] = [:]
        for (term, freq) in tf {
            properQuery[term] = freq * (idfCache[term] ?? 1.0)
        }
        
        var candidateLinks = Set<String>()
        for term in tf.keys {
            if let links = invertedIndex[term] {
                candidateLinks.formUnion(links)
            }
        }
        
        var results: [SimilarArticle] = []
        
        for link in candidateLinks {
            guard let doc = documents[link] else { continue }
            let docVector = tfidfVector(for: doc)
            let similarity = cosineSimilarity(properQuery, docVector)
            
            guard similarity >= threshold, let story = doc.story else { continue }
            
            let sharedTerms = Set(tf.keys).intersection(Set(doc.termFrequencies.keys))
            let shared = Array(sharedTerms.prefix(5))
            
            results.append(SimilarArticle(
                story: story, score: similarity, sharedKeywords: shared
            ))
        }
        
        results.sort { $0.score > $1.score }
        return Array(results.prefix(limit))
    }
    
    // MARK: - Clustering
    
    /// Group all indexed articles into topic clusters based on similarity.
    /// Returns arrays of links grouped by topic. Uses a simple greedy approach.
    func clusterArticles(threshold: Double = 0.15) -> [[String]] {
        refreshIDFIfNeeded()
        
        // Pre-compute all TF-IDF vectors once. The previous implementation
        // called tfidfVector(for:) inside a nested loop — each document's
        // vector was recomputed O(n) times across different seed iterations,
        // wasting CPU on redundant dictionary allocations and IDF lookups.
        var vectorCache: [String: [String: Double]] = [:]
        vectorCache.reserveCapacity(documents.count)
        for (link, doc) in documents {
            vectorCache[link] = tfidfVector(for: doc)
        }
        
        var unassigned = Set(documents.keys)
        var clusters: [[String]] = []
        
        while !unassigned.isEmpty {
            guard let seed = unassigned.first else { break }
            guard let seedVector = vectorCache[seed] else {
                unassigned.remove(seed)
                continue
            }
            
            var cluster = [seed]
            unassigned.remove(seed)
            
            for link in unassigned {
                guard let docVector = vectorCache[link] else { continue }
                let sim = cosineSimilarity(seedVector, docVector)
                if sim >= threshold {
                    cluster.append(link)
                }
            }
            
            // Remove assigned items
            for link in cluster.dropFirst() {
                unassigned.remove(link)
            }
            
            clusters.append(cluster)
        }
        
        // Sort clusters by size descending
        clusters.sort { $0.count > $1.count }
        return clusters
    }
    
    /// Get top keywords for a cluster of articles (for labeling).
    func clusterKeywords(links: [String], topN: Int = 5) -> [String] {
        refreshIDFIfNeeded()
        
        var aggregated: [String: Double] = [:]
        for link in links {
            guard let doc = documents[link] else { continue }
            for (term, tf) in doc.termFrequencies {
                let idf = idfCache[term] ?? 1.0
                aggregated[term, default: 0] += tf * idf
            }
        }
        
        return aggregated.sorted { $0.value > $1.value }
            .prefix(topN)
            .map { $0.key }
    }
    
    // MARK: - Statistics
    
    /// Number of indexed documents.
    var documentCount: Int { documents.count }
    
    /// Number of unique terms in the index.
    var termCount: Int { invertedIndex.count }
    
    // MARK: - Management
    
    /// Clear the entire index.
    func clearIndex() {
        documents.removeAll()
        invertedIndex.removeAll()
        idfCache.removeAll()
        idfDirty = false
    }
    
    // MARK: - Private Helpers
    
    /// Tokenize text into lowercase terms, removing stop words and short terms.
    /// Delegates to TextAnalyzer for consistent tokenization across the app.
    private func tokenize(_ text: String) -> [String] {
        return TextAnalyzer.shared.tokenize(text, minLength: ArticleSimilarityManager.minTermLength)
    }
    
    /// Compute normalized term frequency for a list of tokens.
    /// Delegates to TextAnalyzer for the core computation.
    private func computeTF(_ tokens: [String]) -> [String: Double] {
        return TextAnalyzer.shared.computeTermFrequency(tokens)
    }
    
    /// Recalculate IDF values if the index has changed.
    private func refreshIDFIfNeeded() {
        guard idfDirty else { return }
        let n = Double(max(documents.count, 1))
        idfCache.removeAll(keepingCapacity: true)
        for (term, docLinks) in invertedIndex {
            let df = Double(docLinks.count)
            idfCache[term] = log(n / df) + 1.0  // smoothed IDF
        }
        idfDirty = false
    }
    
    /// Compute TF-IDF vector for a document.
    private func tfidfVector(for doc: IndexedDocument) -> [String: Double] {
        var vector: [String: Double] = [:]
        for (term, tf) in doc.termFrequencies {
            let idf = idfCache[term] ?? 1.0
            vector[term] = tf * idf
        }
        return vector
    }
    
    /// Cosine similarity between two sparse vectors.
    private func cosineSimilarity(_ a: [String: Double], _ b: [String: Double]) -> Double {
        var dotProduct = 0.0
        var normA = 0.0
        var normB = 0.0
        
        for (term, valA) in a {
            normA += valA * valA
            if let valB = b[term] {
                dotProduct += valA * valB
            }
        }
        for (_, valB) in b {
            normB += valB * valB
        }
        
        let denom = sqrt(normA) * sqrt(normB)
        guard denom > 0 else { return 0 }
        return dotProduct / denom
    }
    
    /// Find the top N shared keywords between two documents by combined TF-IDF weight.
    private func findSharedKeywords(_ a: IndexedDocument, _ b: IndexedDocument, topN: Int) -> [String] {
        let sharedTerms = Set(a.termFrequencies.keys).intersection(Set(b.termFrequencies.keys))
        let scored = sharedTerms.map { term -> (String, Double) in
            let idf = idfCache[term] ?? 1.0
            let weight = (a.termFrequencies[term]! + b.termFrequencies[term]!) * idf
            return (term, weight)
        }
        return scored.sorted { $0.1 > $1.1 }.prefix(topN).map { $0.0 }
    }
}
