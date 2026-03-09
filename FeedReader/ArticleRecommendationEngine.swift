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
    /// Hash of history state used for cache invalidation. Using a content
    /// hash instead of just count detects revisit-count changes, time-spent
    /// updates, and entry replacements that don't change the array length.
    private var profileHistoryHash: Int = 0
    
    // MARK: - Stop Words
    
    // Stop words and tokenization are provided by TextAnalyzer.shared
    
    // MARK: - Reading Profile
    
    /// Extracted user preferences from reading history.
    private struct ReadingProfile {
        /// Feed name → normalized preference score (0.0–1.0).
        let feedScores: [String: Double]
        
        /// Feed name → number of articles read from that feed.
        let feedArticleCounts: [String: Int]
        
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
        profileHistoryHash = 0
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
        // Use cache if history hasn't changed (content-aware hash, not just count).
        // The old count-based check missed revisit-count bumps and time-spent
        // updates that don't change array length but do change profile scores.
        let historyHash = Self.computeHistoryHash(history)
        if let cached = cachedProfile, profileHistoryHash == historyHash {
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
        
        // Build feed preference scores and revisit rates in a single pass.
        // feedCounts tracks articles per feed (used for both scoring and
        // revisit rate denominator — the old code had a redundant
        // feedArticleCounts dictionary that was always identical).
        var feedCounts: [String: Int] = [:]
        var feedVisitTotals: [String: Int] = [:]
        
        for entry in entries {
            let feed = entry.feedName
            feedCounts[feed, default: 0] += 1
            feedVisitTotals[feed, default: 0] += entry.visitCount
        }
        
        let maxFeedCount = Double(feedCounts.values.max() ?? 1)
        var feedScores: [String: Double] = [:]
        var feedRevisitRates: [String: Double] = [:]
        for (feed, count) in feedCounts {
            feedScores[feed] = Double(count) / maxFeedCount
            let totalVisits = feedVisitTotals[feed] ?? count
            feedRevisitRates[feed] = Double(totalVisits) / Double(count)
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
            feedArticleCounts: feedCounts,
            keywordScores: keywordScores,
            feedRevisitRates: feedRevisitRates,
            revisitKeywords: revisitKeywordSet
        )
        
        cachedProfile = profile
        profileHistoryHash = historyHash
        
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
            let readCount = profile.feedArticleCounts[feedName] ?? 1
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
    /// Delegates to TextAnalyzer for consistent tokenization across the app.
    private func extractKeywords(from text: String, options: RecommendationOptions) -> [String] {
        return TextAnalyzer.shared.extractKeywords(
            from: text,
            minLength: options.minKeywordLength
        )
    }

    // MARK: - Cache Helpers

    /// Compute a content-aware hash of history entries for cache invalidation.
    /// Incorporates count, visit counts, and time spent — changes to any of
    /// these (e.g., revisiting an article) will invalidate the cached profile.
    private static func computeHistoryHash(_ history: [HistoryEntry]) -> Int {
        var hasher = Hasher()
        hasher.combine(history.count)
        for entry in history {
            hasher.combine(entry.link)
            hasher.combine(entry.visitCount)
            hasher.combine(entry.feedName)
            // Round time to nearest second to avoid floating-point noise
            hasher.combine(Int(entry.timeSpentSeconds))
        }
        return hasher.finalize()
    }
}
