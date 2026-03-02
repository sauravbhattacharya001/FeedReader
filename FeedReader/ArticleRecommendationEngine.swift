//
//  ArticleRecommendationEngine.swift
//  FeedReader
//
//  Recommends unread articles based on reading history patterns.
//  Scores articles using feed preference (how often the user reads
//  from each feed) and keyword affinity (words that appear frequently
//  in previously read article titles). Lightweight, runs entirely
//  on-device with no external dependencies.
//

import Foundation

// MARK: - RecommendationReason

/// Why an article was recommended — helps users understand suggestions.
enum RecommendationReason: CustomStringConvertible {
    case preferredFeed(feedName: String, readCount: Int)
    case keywordMatch(keywords: [String])
    case frequentlyRevisited
    case combined
    
    var description: String {
        switch self {
        case .preferredFeed(let name, let count):
            return "You've read \(count) articles from \(name)"
        case .keywordMatch(let keywords):
            let joined = keywords.prefix(3).joined(separator: ", ")
            return "Matches your interests: \(joined)"
        case .frequentlyRevisited:
            return "Similar to articles you've re-read"
        case .combined:
            return "Matches your reading patterns"
        }
    }
}

// MARK: - ScoredArticle

/// An article with its recommendation score and reasoning.
struct ScoredArticle {
    let story: Story
    let score: Double
    let reasons: [RecommendationReason]
    
    /// Primary reason for recommendation (highest-weight reason).
    var primaryReason: RecommendationReason? {
        return reasons.first
    }
}

// MARK: - RecommendationOptions

/// Configuration for the recommendation engine.
struct RecommendationOptions {
    /// Weight for feed preference scoring (0.0–1.0).
    var feedWeight: Double = 0.5
    
    /// Weight for keyword affinity scoring (0.0–1.0).
    var keywordWeight: Double = 0.35
    
    /// Weight for revisit pattern scoring (0.0–1.0).
    var revisitWeight: Double = 0.15
    
    /// Maximum number of recommendations to return.
    var maxResults: Int = 20
    
    /// Minimum score threshold (0.0–1.0). Articles below this aren't recommended.
    var minScore: Double = 0.05
    
    /// Number of top keywords to extract from reading history.
    var topKeywordCount: Int = 50
    
    /// Minimum keyword length to consider (filters noise words).
    var minKeywordLength: Int = 4
    
    /// How many days of history to analyze (0 = all history).
    var historyDays: Int = 30
}

// MARK: - ArticleRecommendationEngine

/// Analyzes reading history to score and rank unread articles.
///
/// Scoring factors:
/// 1. **Feed Preference** — articles from feeds the user reads often score higher
/// 2. **Keyword Affinity** — articles whose titles contain words from previously
///    read titles score higher (TF-based, with stop word filtering)
/// 3. **Revisit Bonus** — articles similar to frequently revisited content score higher
///
/// All scoring is normalized to 0.0–1.0 and combined using configurable weights.
class ArticleRecommendationEngine {
    
    // MARK: - Singleton
    
    static let shared = ArticleRecommendationEngine()
    
    // MARK: - Notifications
    
    static let recommendationsDidUpdateNotification = Notification.Name("RecommendationsDidUpdate")
    
    // MARK: - Cached Profile
    
    /// Cached user reading profile, rebuilt when history changes.
    private var cachedProfile: ReadingProfile?
    private var profileHistoryCount: Int = 0
    
    // MARK: - Stop Words
    
    /// Common English stop words filtered from keyword extraction.
    private static let stopWords: Set<String> = [
        "the", "and", "for", "that", "this", "with", "from", "have", "has",
        "had", "are", "was", "were", "been", "being", "will", "would", "could",
        "should", "shall", "may", "might", "must", "can", "does", "did", "done",
        "not", "but", "what", "which", "who", "whom", "when", "where", "why",
        "how", "all", "each", "every", "both", "few", "more", "most", "other",
        "some", "such", "than", "too", "very", "just", "about", "above", "after",
        "again", "also", "any", "back", "because", "before", "between", "come",
        "even", "first", "get", "give", "going", "good", "great", "here", "high",
        "into", "its", "know", "last", "like", "long", "look", "make", "many",
        "much", "need", "new", "now", "only", "open", "over", "part", "people",
        "say", "says", "said", "she", "show", "state", "still", "take", "tell",
        "them", "then", "there", "these", "they", "think", "time", "two", "under",
        "upon", "use", "used", "using", "want", "well", "year", "your", "you",
        "our", "out", "own", "same", "around", "while", "work", "world", "way"
    ]
    
    // MARK: - Reading Profile
    
    /// Extracted user preferences from reading history.
    private struct ReadingProfile {
        /// Feed name → normalized preference score (0.0–1.0).
        let feedScores: [String: Double]
        
        /// Keyword → normalized affinity score (0.0–1.0).
        let keywordScores: [String: Double]
        
        /// Feed name → average visit count for articles in that feed.
        let feedRevisitRates: [String: Double]
        
        /// Keywords from frequently revisited articles (visitCount > 1).
        let revisitKeywords: Set<String>
    }
    
    // MARK: - Public API
    
    /// Generate recommendations for unread articles based on reading history.
    ///
    /// - Parameters:
    ///   - candidates: Unread stories to score and rank.
    ///   - history: Reading history entries (from ReadingHistoryManager).
    ///   - options: Scoring configuration.
    /// - Returns: Scored and ranked articles, highest score first.
    func recommend(from candidates: [Story],
                   history: [HistoryEntry],
                   options: RecommendationOptions = RecommendationOptions()) -> [ScoredArticle] {
        
        // Build or use cached reading profile
        let profile = buildProfile(from: history, options: options)
        
        // Filter out already-read articles
        let readLinks = Set(history.map { $0.link })
        let unread = candidates.filter { !readLinks.contains($0.link) }
        
        // Score each candidate
        var scored: [ScoredArticle] = []
        for story in unread {
            let (score, reasons) = scoreArticle(story, profile: profile, options: options)
            if score >= options.minScore {
                scored.append(ScoredArticle(story: story, score: score, reasons: reasons))
            }
        }
        
        // Sort by score descending, limit results
        scored.sort { $0.score > $1.score }
        if scored.count > options.maxResults {
            scored = Array(scored.prefix(options.maxResults))
        }
        
        return scored
    }
    
    /// Invalidate cached profile (call when history changes significantly).
    func invalidateCache() {
        cachedProfile = nil
        profileHistoryCount = 0
    }
    
    /// Get a human-readable summary of the user's reading profile.
    func profileSummary(from history: [HistoryEntry],
                        options: RecommendationOptions = RecommendationOptions()) -> String {
        let profile = buildProfile(from: history, options: options)
        
        var lines: [String] = []
        lines.append("Reading Profile Summary")
        lines.append("=======================")
        lines.append("")
        
        // Top feeds
        let topFeeds = profile.feedScores.sorted { $0.value > $1.value }.prefix(5)
        if !topFeeds.isEmpty {
            lines.append("Top Feeds:")
            for (feed, score) in topFeeds {
                let pct = Int(score * 100)
                lines.append("  \(feed): \(pct)% preference")
            }
            lines.append("")
        }
        
        // Top keywords
        let topKeywords = profile.keywordScores.sorted { $0.value > $1.value }.prefix(10)
        if !topKeywords.isEmpty {
            lines.append("Interest Keywords:")
            lines.append("  \(topKeywords.map { $0.key }.joined(separator: ", "))")
            lines.append("")
        }
        
        // Revisit patterns
        if !profile.revisitKeywords.isEmpty {
            lines.append("Re-read Topics:")
            lines.append("  \(profile.revisitKeywords.prefix(8).joined(separator: ", "))")
        }
        
        return lines.joined(separator: "\n")
    }
    
    // MARK: - Profile Building
    
    private func buildProfile(from history: [HistoryEntry],
                               options: RecommendationOptions) -> ReadingProfile {
        // Use cache if history hasn't changed
        if let cached = cachedProfile, profileHistoryCount == history.count {
            return cached
        }
        
        // Filter by time window
        let entries: [HistoryEntry]
        if options.historyDays > 0 {
            let cutoff = Calendar.current.date(byAdding: .day, value: -options.historyDays,
                                                to: Date()) ?? Date.distantPast
            entries = history.filter { $0.readAt >= cutoff }
        } else {
            entries = history
        }
        
        // Build feed preference scores
        var feedCounts: [String: Int] = [:]
        var feedVisitTotals: [String: Int] = [:]
        var feedArticleCounts: [String: Int] = [:]
        
        for entry in entries {
            let feed = entry.feedName
            feedCounts[feed, default: 0] += 1
            feedVisitTotals[feed, default: 0] += entry.visitCount
            feedArticleCounts[feed, default: 0] += 1
        }
        
        let maxFeedCount = Double(feedCounts.values.max() ?? 1)
        var feedScores: [String: Double] = [:]
        for (feed, count) in feedCounts {
            feedScores[feed] = Double(count) / maxFeedCount
        }
        
        // Build feed revisit rates
        var feedRevisitRates: [String: Double] = [:]
        for (feed, totalVisits) in feedVisitTotals {
            let articleCount = feedArticleCounts[feed] ?? 1
            feedRevisitRates[feed] = Double(totalVisits) / Double(articleCount)
        }
        
        // Extract keywords from titles
        var keywordCounts: [String: Int] = [:]
        var revisitKeywordSet: Set<String> = []
        
        for entry in entries {
            let words = extractKeywords(from: entry.title, options: options)
            for word in words {
                keywordCounts[word, default: 0] += 1
            }
            
            // Track keywords from revisited articles
            if entry.visitCount > 1 {
                revisitKeywordSet.formUnion(words)
            }
        }
        
        // Normalize keyword scores, keep top N
        let sortedKeywords = keywordCounts.sorted { $0.value > $1.value }
            .prefix(options.topKeywordCount)
        let maxKeywordCount = Double(sortedKeywords.first?.value ?? 1)
        var keywordScores: [String: Double] = [:]
        for (word, count) in sortedKeywords {
            keywordScores[word] = Double(count) / maxKeywordCount
        }
        
        let profile = ReadingProfile(
            feedScores: feedScores,
            keywordScores: keywordScores,
            feedRevisitRates: feedRevisitRates,
            revisitKeywords: revisitKeywordSet
        )
        
        cachedProfile = profile
        profileHistoryCount = history.count
        
        return profile
    }
    
    // MARK: - Scoring
    
    private func scoreArticle(_ story: Story, profile: ReadingProfile,
                               options: RecommendationOptions) -> (Double, [RecommendationReason]) {
        var totalScore = 0.0
        var reasons: [RecommendationReason] = []
        
        // 1. Feed preference score
        let feedName = story.sourceFeedName ?? ""
        let feedScore = profile.feedScores[feedName] ?? 0.0
        if feedScore > 0 {
            totalScore += feedScore * options.feedWeight
            let readCount = Int(feedScore * Double(profile.feedScores.count))
            reasons.append(.preferredFeed(feedName: feedName, readCount: max(readCount, 1)))
        }
        
        // 2. Keyword affinity score
        let titleWords = extractKeywords(from: story.title, options: options)
        var keywordScore = 0.0
        var matchedKeywords: [String] = []
        
        for word in titleWords {
            if let score = profile.keywordScores[word] {
                keywordScore += score
                matchedKeywords.append(word)
            }
        }
        
        // Normalize by number of words to avoid bias toward long titles
        if !titleWords.isEmpty {
            keywordScore = min(keywordScore / Double(titleWords.count), 1.0)
        }
        
        if keywordScore > 0 {
            totalScore += keywordScore * options.keywordWeight
            if !matchedKeywords.isEmpty {
                reasons.append(.keywordMatch(keywords: matchedKeywords))
            }
        }
        
        // 3. Revisit pattern score
        let revisitMatches = titleWords.filter { profile.revisitKeywords.contains($0) }
        if !revisitMatches.isEmpty {
            let revisitScore = min(Double(revisitMatches.count) / Double(max(titleWords.count, 1)), 1.0)
            totalScore += revisitScore * options.revisitWeight
            reasons.append(.frequentlyRevisited)
        }
        
        // If multiple reasons, mark as combined
        if reasons.count > 1 {
            reasons.insert(.combined, at: 0)
        }
        
        return (min(totalScore, 1.0), reasons)
    }
    
    // MARK: - Keyword Extraction
    
    /// Extract meaningful keywords from text, filtering stop words and short words.
    private func extractKeywords(from text: String, options: RecommendationOptions) -> [String] {
        let words = text.lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { word in
                word.count >= options.minKeywordLength &&
                !ArticleRecommendationEngine.stopWords.contains(word)
            }
        
        // Deduplicate while preserving order
        var seen = Set<String>()
        return words.filter { seen.insert($0).inserted }
    }
}
