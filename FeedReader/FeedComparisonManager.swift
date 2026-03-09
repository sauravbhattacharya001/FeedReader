//
//  FeedComparisonManager.swift
//  FeedReader
//
//  Compares two RSS feeds side-by-side: content overlap, unique articles,
//  topic similarity via keyword extraction, and update frequency analysis.
//  Useful for deciding which feeds to keep, merge, or prune.
//

import Foundation

/// Notification posted when a comparison completes.
extension Notification.Name {
    static let feedComparisonDidComplete = Notification.Name("FeedComparisonDidCompleteNotification")
}

class FeedComparisonManager {
    
    // MARK: - Singleton
    
    static let shared = FeedComparisonManager()
    
    // MARK: - Types
    
    /// Result of comparing two feeds.
    struct ComparisonResult {
        let feedA: FeedSnapshot
        let feedB: FeedSnapshot
        let overlap: OverlapAnalysis
        let topicSimilarity: TopicSimilarity
        let recommendation: Recommendation
        let comparedAt: Date
        
        /// Human-readable summary of the comparison.
        var summary: String {
            var lines: [String] = []
            lines.append("=== Feed Comparison ===")
            lines.append("\(feedA.name) vs \(feedB.name)")
            lines.append("")
            lines.append("--- Article Counts ---")
            lines.append("\(feedA.name): \(feedA.articleCount) articles")
            lines.append("\(feedB.name): \(feedB.articleCount) articles")
            lines.append("")
            lines.append("--- Overlap ---")
            lines.append("Exact URL matches: \(overlap.exactMatches)")
            lines.append("Title similarity matches: \(overlap.titleMatches)")
            lines.append("Overlap ratio: \(String(format: "%.1f%%", overlap.overlapRatio * 100))")
            lines.append("Unique to \(feedA.name): \(overlap.uniqueToA)")
            lines.append("Unique to \(feedB.name): \(overlap.uniqueToB)")
            lines.append("")
            lines.append("--- Topic Similarity ---")
            lines.append("Cosine similarity: \(String(format: "%.2f", topicSimilarity.score))")
            lines.append("Shared keywords: \(topicSimilarity.sharedKeywords.joined(separator: ", "))")
            if !topicSimilarity.uniqueToA.isEmpty {
                lines.append("Unique to \(feedA.name): \(topicSimilarity.uniqueToA.joined(separator: ", "))")
            }
            if !topicSimilarity.uniqueToB.isEmpty {
                lines.append("Unique to \(feedB.name): \(topicSimilarity.uniqueToB.joined(separator: ", "))")
            }
            lines.append("")
            lines.append("--- Recommendation ---")
            lines.append(recommendation.description)
            return lines.joined(separator: "\n")
        }
    }
    
    /// Snapshot of a feed's articles at comparison time.
    struct FeedSnapshot {
        let name: String
        let url: String
        let articleCount: Int
        let articles: [ArticleSummary]
        let keywords: [String: Int]
    }
    
    /// Lightweight article representation for comparison.
    struct ArticleSummary {
        let title: String
        let link: String
        let normalizedTitle: String
        let words: Set<String>
    }
    
    /// Analysis of content overlap between two feeds.
    struct OverlapAnalysis {
        /// Articles sharing the exact same URL.
        let exactMatches: Int
        /// Articles with very similar titles (>80% word overlap).
        let titleMatches: Int
        /// Overlap as fraction of the smaller feed's article count.
        let overlapRatio: Double
        /// Articles unique to feed A.
        let uniqueToA: Int
        /// Articles unique to feed B.
        let uniqueToB: Int
        /// Pairs of overlapping articles (title from A, title from B).
        let matchedPairs: [(String, String)]
    }
    
    /// Keyword-based topic similarity analysis.
    struct TopicSimilarity {
        /// Cosine similarity score (0.0 = no overlap, 1.0 = identical topics).
        let score: Double
        /// Keywords appearing in both feeds.
        let sharedKeywords: [String]
        /// Top keywords unique to feed A.
        let uniqueToA: [String]
        /// Top keywords unique to feed B.
        let uniqueToB: [String]
    }
    
    /// Actionable recommendation based on the comparison.
    enum Recommendation {
        case highOverlap       // Consider removing one feed
        case complementary     // Feeds cover different topics well
        case partialOverlap    // Some redundancy but both add value
        case noData            // Not enough data to compare
        
        var description: String {
            switch self {
            case .highOverlap:
                return "⚠️ High overlap detected. These feeds cover very similar content. Consider keeping only one to reduce noise."
            case .complementary:
                return "✅ These feeds complement each other well. They cover different topics with minimal overlap."
            case .partialOverlap:
                return "ℹ️ Some overlap exists, but both feeds contribute unique content. Worth keeping both."
            case .noData:
                return "❓ Not enough articles to make a meaningful comparison. Try again after more articles are fetched."
            }
        }
    }
    
    // MARK: - Storage
    
    private let historyKey = "FeedComparisonHistory"
    private let maxHistorySize = 50
    
    /// Serializable comparison record for history.
    struct ComparisonRecord: Codable {
        let feedAName: String
        let feedBName: String
        let feedAURL: String
        let feedBURL: String
        let overlapRatio: Double
        let topicScore: Double
        let recommendation: String
        let date: Date
    }
    
    // MARK: - Public API
    
    /// Compare two feeds using their currently loaded stories.
    ///
    /// - Parameters:
    ///   - feedA: First feed to compare.
    ///   - feedB: Second feed to compare.
    ///   - storiesA: Articles from feed A.
    ///   - storiesB: Articles from feed B.
    /// - Returns: A detailed comparison result.
    func compare(feedA: Feed, feedB: Feed, storiesA: [Story], storiesB: [Story]) -> ComparisonResult {
        let snapshotA = buildSnapshot(feed: feedA, stories: storiesA)
        let snapshotB = buildSnapshot(feed: feedB, stories: storiesB)
        
        let overlap = analyzeOverlap(a: snapshotA, b: snapshotB)
        let topics = analyzeTopicSimilarity(a: snapshotA, b: snapshotB)
        let recommendation = makeRecommendation(overlap: overlap, topics: topics,
                                                  countA: snapshotA.articleCount,
                                                  countB: snapshotB.articleCount)
        
        let result = ComparisonResult(
            feedA: snapshotA,
            feedB: snapshotB,
            overlap: overlap,
            topicSimilarity: topics,
            recommendation: recommendation,
            comparedAt: Date()
        )
        
        saveToHistory(result)
        NotificationCenter.default.post(name: .feedComparisonDidComplete, object: result)
        
        return result
    }
    
    /// Compare all enabled feeds pairwise and return results sorted by overlap.
    func compareAllFeeds(feeds: [Feed], storiesByFeed: [String: [Story]]) -> [ComparisonResult] {
        var results: [ComparisonResult] = []
        
        for i in 0..<feeds.count {
            for j in (i + 1)..<feeds.count {
                let feedA = feeds[i]
                let feedB = feeds[j]
                let storiesA = storiesByFeed[feedA.url] ?? []
                let storiesB = storiesByFeed[feedB.url] ?? []
                
                let result = compare(feedA: feedA, feedB: feedB,
                                     storiesA: storiesA, storiesB: storiesB)
                results.append(result)
            }
        }
        
        return results.sorted { $0.overlap.overlapRatio > $1.overlap.overlapRatio }
    }
    
    /// Find feeds that are most redundant (high overlap) and suggest pruning.
    func findRedundantFeeds(feeds: [Feed], storiesByFeed: [String: [Story]],
                            threshold: Double = 0.5) -> [(Feed, Feed, Double)] {
        var redundant: [(Feed, Feed, Double)] = []
        
        for i in 0..<feeds.count {
            for j in (i + 1)..<feeds.count {
                let feedA = feeds[i]
                let feedB = feeds[j]
                let storiesA = storiesByFeed[feedA.url] ?? []
                let storiesB = storiesByFeed[feedB.url] ?? []
                
                let snapshotA = buildSnapshot(feed: feedA, stories: storiesA)
                let snapshotB = buildSnapshot(feed: feedB, stories: storiesB)
                let overlap = analyzeOverlap(a: snapshotA, b: snapshotB)
                
                if overlap.overlapRatio >= threshold {
                    redundant.append((feedA, feedB, overlap.overlapRatio))
                }
            }
        }
        
        return redundant.sorted { $0.2 > $1.2 }
    }
    
    /// Retrieve comparison history.
    func getHistory() -> [ComparisonRecord] {
        guard let data = UserDefaults.standard.data(forKey: historyKey),
              let records = try? JSONDecoder().decode([ComparisonRecord].self, from: data) else {
            return []
        }
        return records
    }
    
    /// Clear comparison history.
    func clearHistory() {
        UserDefaults.standard.removeObject(forKey: historyKey)
    }
    
    // MARK: - Internal
    
    private func buildSnapshot(feed: Feed, stories: [Story]) -> FeedSnapshot {
        let articles = stories.map { story -> ArticleSummary in
            let normalized = normalizeTitle(story.title)
            let words = extractWords(from: story.title + " " + story.body)
            return ArticleSummary(
                title: story.title,
                link: story.link,
                normalizedTitle: normalized,
                words: words
            )
        }
        
        let keywords = extractKeywords(from: stories)
        
        return FeedSnapshot(
            name: feed.name,
            url: feed.url,
            articleCount: stories.count,
            articles: articles,
            keywords: keywords
        )
    }
    
    private func analyzeOverlap(a: FeedSnapshot, b: FeedSnapshot) -> OverlapAnalysis {
        let linksA = Set(a.articles.map { $0.link.lowercased() })
        let linksB = Set(b.articles.map { $0.link.lowercased() })
        let exactMatchLinks = linksA.intersection(linksB)
        let exactMatches = exactMatchLinks.count
        
        // Build sets of indices already matched by URL so title matching
        // doesn't double-count them.
        let urlMatchedA = Set(a.articles.indices.filter {
            exactMatchLinks.contains(a.articles[$0].link.lowercased())
        })
        let urlMatchedB = Set(b.articles.indices.filter {
            exactMatchLinks.contains(b.articles[$0].link.lowercased())
        })
        
        // Title similarity matching — skip articles already matched by URL
        var titleMatches = 0
        var matchedPairs: [(String, String)] = []
        var matchedB = urlMatchedB // start with URL-matched B indices excluded
        
        for (idxA, articleA) in a.articles.enumerated() {
            guard !urlMatchedA.contains(idxA) else { continue }
            for (idxB, articleB) in b.articles.enumerated() {
                guard !matchedB.contains(idxB) else { continue }
                
                let similarity = titleSimilarity(articleA.normalizedTitle, articleB.normalizedTitle)
                if similarity > 0.8 {
                    titleMatches += 1
                    matchedPairs.append((articleA.title, articleB.title))
                    matchedB.insert(idxB)
                    break
                }
            }
        }
        
        let totalOverlap = exactMatches + titleMatches
        let minCount = min(a.articleCount, b.articleCount)
        let overlapRatio = minCount > 0 ? Double(totalOverlap) / Double(minCount) : 0.0
        
        // Unique counts: total articles minus those matched (by URL or title).
        // Each feed's matched count is bounded by totalOverlap but also by
        // the feed's own article count, so unique is always >= 0.
        let matchedInA = urlMatchedA.count + (titleMatches)  // A articles consumed
        let matchedInB = matchedB.count                       // B articles consumed (URL + title)
        
        return OverlapAnalysis(
            exactMatches: exactMatches,
            titleMatches: titleMatches,
            overlapRatio: min(overlapRatio, 1.0),
            uniqueToA: max(0, a.articleCount - matchedInA),
            uniqueToB: max(0, b.articleCount - matchedInB),
            matchedPairs: matchedPairs
        )
    }
    
    private func analyzeTopicSimilarity(a: FeedSnapshot, b: FeedSnapshot) -> TopicSimilarity {
        let allKeys = Set(a.keywords.keys).union(Set(b.keywords.keys))
        guard !allKeys.isEmpty else {
            return TopicSimilarity(score: 0, sharedKeywords: [], uniqueToA: [], uniqueToB: [])
        }
        
        // Cosine similarity on keyword frequency vectors
        var dotProduct = 0.0
        var magnitudeA = 0.0
        var magnitudeB = 0.0
        
        for key in allKeys {
            let valA = Double(a.keywords[key] ?? 0)
            let valB = Double(b.keywords[key] ?? 0)
            dotProduct += valA * valB
            magnitudeA += valA * valA
            magnitudeB += valB * valB
        }
        
        let magnitude = sqrt(magnitudeA) * sqrt(magnitudeB)
        let score = magnitude > 0 ? dotProduct / magnitude : 0.0
        
        let keysA = Set(a.keywords.keys)
        let keysB = Set(b.keywords.keys)
        let shared = keysA.intersection(keysB)
            .sorted { (a.keywords[$0] ?? 0) + (b.keywords[$0] ?? 0) > (a.keywords[$1] ?? 0) + (b.keywords[$1] ?? 0) }
        let uniqueA = keysA.subtracting(keysB)
            .sorted { a.keywords[$0] ?? 0 > a.keywords[$1] ?? 0 }
        let uniqueB = keysB.subtracting(keysA)
            .sorted { b.keywords[$0] ?? 0 > b.keywords[$1] ?? 0 }
        
        return TopicSimilarity(
            score: score,
            sharedKeywords: Array(shared.prefix(10)),
            uniqueToA: Array(uniqueA.prefix(5)),
            uniqueToB: Array(uniqueB.prefix(5))
        )
    }
    
    private func makeRecommendation(overlap: OverlapAnalysis, topics: TopicSimilarity,
                                     countA: Int, countB: Int) -> Recommendation {
        if countA < 3 || countB < 3 {
            return .noData
        }
        if overlap.overlapRatio > 0.6 || (overlap.overlapRatio > 0.3 && topics.score > 0.8) {
            return .highOverlap
        }
        if overlap.overlapRatio < 0.1 && topics.score < 0.3 {
            return .complementary
        }
        return .partialOverlap
    }
    
    // MARK: - Text Processing
    
    /// Normalize a story title for deduplication comparison.
    /// Delegates stop word filtering to `TextAnalyzer.shared`.
    private func normalizeTitle(_ title: String) -> String {
        return TextAnalyzer.shared.tokenize(title, minLength: 1)
            .joined(separator: " ")
    }
    
    /// Extract unique words from text, filtering stop words.
    /// Delegates to `TextAnalyzer.shared` for consistent tokenization.
    private func extractWords(from text: String) -> Set<String> {
        return Set(TextAnalyzer.shared.tokenize(text))
    }
    
    /// Extract keyword document-frequency counts from a set of stories.
    /// Uses `TextAnalyzer.shared` for tokenization and stop word filtering.
    private func extractKeywords(from stories: [Story]) -> [String: Int] {
        var freq: [String: Int] = [:]
        
        for story in stories {
            let tokens = TextAnalyzer.shared.tokenize(story.title + " " + story.body, minLength: 4)
            
            // Count unique words per article (document frequency)
            for word in Set(tokens) {
                freq[word, default: 0] += 1
            }
        }
        
        // Keep only keywords that appear in at least 2 articles but less than 80% of articles
        let maxFreq = max(1, Int(Double(stories.count) * 0.8))
        return freq.filter { $0.value >= 2 && $0.value <= maxFreq }
    }
    
    private func titleSimilarity(_ a: String, _ b: String) -> Double {
        let wordsA = Set(a.components(separatedBy: " "))
        let wordsB = Set(b.components(separatedBy: " "))
        guard !wordsA.isEmpty || !wordsB.isEmpty else { return 0 }
        let intersection = wordsA.intersection(wordsB).count
        let smaller = min(wordsA.count, wordsB.count)
        return smaller > 0 ? Double(intersection) / Double(smaller) : 0
    }
    
    // MARK: - History Persistence
    
    private func saveToHistory(_ result: ComparisonResult) {
        var history = getHistory()
        let record = ComparisonRecord(
            feedAName: result.feedA.name,
            feedBName: result.feedB.name,
            feedAURL: result.feedA.url,
            feedBURL: result.feedB.url,
            overlapRatio: result.overlap.overlapRatio,
            topicScore: result.topicSimilarity.score,
            recommendation: result.recommendation.description,
            date: result.comparedAt
        )
        history.insert(record, at: 0)
        if history.count > maxHistorySize {
            history = Array(history.prefix(maxHistorySize))
        }
        if let data = try? JSONEncoder().encode(history) {
            UserDefaults.standard.set(data, forKey: historyKey)
        }
    }
}
