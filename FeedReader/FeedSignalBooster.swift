//
//  FeedSignalBooster.swift
//  FeedReader
//
//  Autonomous cross-feed trending topic detector. Monitors incoming
//  articles across all subscribed feeds and detects when multiple
//  independent sources converge on the same topic within a time window.
//  Convergence indicates a breaking or trending story worth surfacing.
//
//  How it works:
//    1. Each new article's title + body is tokenized into keyword n-grams
//    2. Keywords are grouped into topic clusters using Jaccard similarity
//    3. When a cluster hits the convergence threshold (N feeds covering
//       the same topic within a time window), a signal boost is triggered
//    4. Boosted topics are ranked by signal strength (feed count × recency)
//    5. Historical boosts are tracked to detect topic lifecycle (emerging,
//       peaking, fading)
//
//  Usage:
//    let booster = FeedSignalBooster()
//
//    // Ingest articles as they arrive
//    booster.ingest(articleId: "a1", title: "OpenAI launches GPT-5",
//        body: "OpenAI unveiled GPT-5 today...", feedURL: "techcrunch.com",
//        publishedDate: Date())
//    booster.ingest(articleId: "a2", title: "GPT-5 announced by OpenAI",
//        body: "The AI company released...", feedURL: "theverge.com",
//        publishedDate: Date())
//
//    // Check for boosted topics
//    let boosted = booster.activeBoostedTopics()
//    // [BoostedTopic(keywords: ["openai","gpt-5"], signalStrength: 0.85,
//    //   feedCount: 2, phase: .emerging, articleIds: ["a1","a2"])]
//
//    // Proactive recommendations
//    let recs = booster.recommendations()
//    // ["🔥 Trending: 'OpenAI GPT-5' covered by 2 feeds — read now"]
//
//  Persistence: JSON file in Documents directory.
//  Fully offline — no network, no dependencies beyond Foundation.
//

import Foundation

// MARK: - Notifications

extension Notification.Name {
    /// Posted when a new topic is signal-boosted (trending detected).
    static let signalBoostDetected = Notification.Name("FeedSignalBoostDetectedNotification")
    /// Posted when a boosted topic changes phase (emerging → peaking → fading).
    static let signalBoostPhaseChanged = Notification.Name("FeedSignalBoostPhaseChangedNotification")
}

// MARK: - Types

/// Lifecycle phase of a boosted topic.
enum SignalBoostPhase: String, Codable, CaseIterable {
    case emerging   // Just detected, feed count growing
    case peaking    // Maximum coverage reached
    case fading     // Coverage declining, fewer new articles
    case archived   // No longer active

    var emoji: String {
        switch self {
        case .emerging:  return "🚀"
        case .peaking:   return "🔥"
        case .fading:    return "📉"
        case .archived:  return "📦"
        }
    }

    var displayName: String {
        switch self {
        case .emerging:  return "Emerging"
        case .peaking:   return "Peaking"
        case .fading:    return "Fading"
        case .archived:  return "Archived"
        }
    }
}

/// A single ingested article signal.
struct ArticleSignal: Codable {
    let articleId: String
    let keywords: [String]
    let feedURL: String
    let publishedDate: Date
    let ingestedDate: Date
}

/// A detected trending topic boosted by cross-feed convergence.
struct BoostedTopic: Codable {
    let id: String
    let keywords: [String]
    var signalStrength: Double        // 0.0–1.0
    var feedCount: Int
    var articleCount: Int
    var phase: SignalBoostPhase
    var articleIds: [String]
    var feedURLs: [String]
    var firstDetected: Date
    var lastUpdated: Date
    var peakFeedCount: Int

    /// Human-readable label from top keywords.
    var label: String {
        let top = Array(keywords.prefix(3))
        return top.joined(separator: " / ").capitalized
    }

    /// Summary line for display.
    var summary: String {
        return "\(phase.emoji) \(label) — \(feedCount) feeds, \(articleCount) articles (strength: \(String(format: "%.0f%%", signalStrength * 100)))"
    }
}

/// Configuration for the signal booster.
struct SignalBoosterConfig: Codable {
    /// Minimum number of distinct feeds covering a topic to trigger a boost.
    var convergenceThreshold: Int = 2
    /// Time window in seconds for convergence detection (default: 24 hours).
    var timeWindowSeconds: TimeInterval = 86400
    /// Minimum Jaccard similarity to merge two article keyword sets into one cluster.
    var clusterSimilarityThreshold: Double = 0.25
    /// Maximum number of active boosted topics to track.
    var maxActiveTopics: Int = 50
    /// Number of top keywords extracted per article.
    var keywordsPerArticle: Int = 8
    /// Hours after last update before a topic transitions to fading.
    var fadingThresholdHours: Double = 12
    /// Hours after fading before archiving.
    var archiveThresholdHours: Double = 48
}

// MARK: - FeedSignalBooster

/// Detects trending topics by monitoring cross-feed keyword convergence.
///
/// Ingests articles from multiple feeds and clusters them by keyword
/// similarity. When multiple independent feeds converge on the same
/// topic within a time window, it triggers a signal boost — surfacing
/// the topic as trending with strength scoring and lifecycle tracking.
class FeedSignalBooster {

    // MARK: - Properties

    private(set) var config: SignalBoosterConfig
    private var signals: [ArticleSignal] = []
    private var boostedTopics: [BoostedTopic] = []
    private var seenArticleIds: Set<String> = []

    private let stopWords: Set<String> = [
        "the", "a", "an", "is", "are", "was", "were", "be", "been", "being",
        "have", "has", "had", "do", "does", "did", "will", "would", "could",
        "should", "may", "might", "shall", "can", "need", "dare", "ought",
        "used", "to", "of", "in", "for", "on", "with", "at", "by", "from",
        "as", "into", "through", "during", "before", "after", "above", "below",
        "between", "out", "off", "over", "under", "again", "further", "then",
        "once", "here", "there", "when", "where", "why", "how", "all", "each",
        "every", "both", "few", "more", "most", "other", "some", "such", "no",
        "nor", "not", "only", "own", "same", "so", "than", "too", "very",
        "just", "because", "but", "and", "or", "if", "while", "about", "up",
        "that", "this", "these", "those", "it", "its", "they", "them", "their",
        "we", "our", "you", "your", "he", "she", "his", "her", "what", "which",
        "who", "whom", "new", "also", "says", "said", "like", "get", "got",
        "one", "two", "first", "now", "even", "much", "many", "well", "back",
        "make", "way", "still", "since", "long", "right", "think", "take"
    ]

    // MARK: - Persistence

    private var storageURL: URL {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        return docs.appendingPathComponent("signal_booster_data.json")
    }

    // MARK: - Initialization

    init(config: SignalBoosterConfig = SignalBoosterConfig()) {
        self.config = config
        loadState()
    }

    // MARK: - Ingestion

    /// Ingest a new article and check for signal boosts.
    ///
    /// - Parameters:
    ///   - articleId: Unique identifier for the article.
    ///   - title: Article title.
    ///   - body: Article body text (can be empty).
    ///   - feedURL: The feed source URL or identifier.
    ///   - publishedDate: When the article was published.
    /// - Returns: A `BoostedTopic` if this article triggered or strengthened a boost, nil otherwise.
    @discardableResult
    func ingest(articleId: String, title: String, body: String,
                feedURL: String, publishedDate: Date) -> BoostedTopic? {
        guard !seenArticleIds.contains(articleId) else { return nil }
        seenArticleIds.insert(articleId)

        let keywords = extractKeywords(from: title + " " + body)
        guard !keywords.isEmpty else { return nil }

        let signal = ArticleSignal(
            articleId: articleId,
            keywords: keywords,
            feedURL: feedURL,
            publishedDate: publishedDate,
            ingestedDate: Date()
        )
        signals.append(signal)
        pruneOldSignals()

        let result = clusterAndDetect(newSignal: signal)
        updatePhases()
        saveState()
        return result
    }

    // MARK: - Querying

    /// Returns all currently active (non-archived) boosted topics, sorted by signal strength.
    func activeBoostedTopics() -> [BoostedTopic] {
        return boostedTopics
            .filter { $0.phase != .archived }
            .sorted { $0.signalStrength > $1.signalStrength }
    }

    /// Returns only emerging and peaking topics — the most newsworthy items.
    func hotTopics() -> [BoostedTopic] {
        return boostedTopics
            .filter { $0.phase == .emerging || $0.phase == .peaking }
            .sorted { $0.signalStrength > $1.signalStrength }
    }

    /// Returns topics in a specific phase.
    func topics(in phase: SignalBoostPhase) -> [BoostedTopic] {
        return boostedTopics.filter { $0.phase == phase }
    }

    /// Signal strength histogram: how many topics at each strength tier.
    func strengthDistribution() -> [String: Int] {
        var dist: [String: Int] = [
            "🔴 Strong (>75%)": 0,
            "🟠 Moderate (50-75%)": 0,
            "🟡 Weak (25-50%)": 0,
            "⚪ Faint (<25%)": 0
        ]
        for topic in activeBoostedTopics() {
            if topic.signalStrength > 0.75 { dist["🔴 Strong (>75%)"]! += 1 }
            else if topic.signalStrength > 0.50 { dist["🟠 Moderate (50-75%)"]! += 1 }
            else if topic.signalStrength > 0.25 { dist["🟡 Weak (25-50%)"]! += 1 }
            else { dist["⚪ Faint (<25%)"]! += 1 }
        }
        return dist
    }

    /// Phase distribution of all tracked topics.
    func phaseDistribution() -> [SignalBoostPhase: Int] {
        var dist: [SignalBoostPhase: Int] = [:]
        for phase in SignalBoostPhase.allCases { dist[phase] = 0 }
        for topic in boostedTopics { dist[topic.phase]! += 1 }
        return dist
    }

    // MARK: - Proactive Recommendations

    /// Generate actionable recommendations based on current signal state.
    func recommendations() -> [String] {
        var recs: [String] = []

        let hot = hotTopics()
        for topic in hot.prefix(3) {
            recs.append("🔥 Trending: '\(topic.label)' covered by \(topic.feedCount) feeds — read now for comprehensive coverage")
        }

        let emerging = topics(in: .emerging)
        for topic in emerging.prefix(2) {
            if !hot.prefix(3).contains(where: { $0.id == topic.id }) {
                recs.append("🚀 Developing story: '\(topic.label)' just appeared in \(topic.feedCount) feeds — keep watching")
            }
        }

        let fading = topics(in: .fading)
        for topic in fading.prefix(2) {
            recs.append("📉 '\(topic.label)' coverage declining — read now before it falls off your radar")
        }

        if hot.isEmpty && emerging.isEmpty {
            recs.append("📡 No trending topics detected — your feeds are covering diverse topics right now")
        }

        let totalFeeds = Set(signals.map { $0.feedURL }).count
        if totalFeeds < 3 {
            recs.append("💡 Add more feeds for better trend detection — currently monitoring \(totalFeeds) source(s)")
        }

        return recs
    }

    // MARK: - Statistics

    /// Summary statistics for the signal booster.
    func stats() -> [String: Any] {
        let active = activeBoostedTopics()
        return [
            "totalSignals": signals.count,
            "uniqueFeeds": Set(signals.map { $0.feedURL }).count,
            "activeBoostedTopics": active.count,
            "hotTopics": hotTopics().count,
            "totalTrackedTopics": boostedTopics.count,
            "averageStrength": active.isEmpty ? 0.0 : active.reduce(0.0) { $0 + $1.signalStrength } / Double(active.count),
            "strongestTopic": active.first?.label ?? "none"
        ]
    }

    // MARK: - Configuration

    /// Update configuration.
    func updateConfig(_ newConfig: SignalBoosterConfig) {
        config = newConfig
        saveState()
    }

    /// Reset all data.
    func reset() {
        signals = []
        boostedTopics = []
        seenArticleIds = []
        saveState()
    }

    // MARK: - Keyword Extraction (Private)

    private func extractKeywords(from text: String) -> [String] {
        let lower = text.lowercased()
        let cleaned = lower.unicodeScalars.filter {
            CharacterSet.alphanumerics.contains($0) || CharacterSet.whitespaces.contains($0)
        }
        let words = String(cleaned)
            .components(separatedBy: .whitespaces)
            .filter { $0.count > 2 && !stopWords.contains($0) }

        // Term frequency
        var freq: [String: Int] = [:]
        for word in words { freq[word, default: 0] += 1 }

        // Also capture bigrams from title-weight zone (first 20 words)
        let titleWords = Array(words.prefix(20))
        for i in 0..<max(0, titleWords.count - 1) {
            let bigram = "\(titleWords[i])_\(titleWords[i + 1])"
            freq[bigram, default: 0] += 3 // Title bigrams get weight boost
        }

        return freq.sorted { $0.value > $1.value }
            .prefix(config.keywordsPerArticle)
            .map { $0.key }
    }

    // MARK: - Clustering & Detection (Private)

    private func clusterAndDetect(newSignal: ArticleSignal) -> BoostedTopic? {
        let newKeySet = Set(newSignal.keywords)
        var bestMatch: (index: Int, similarity: Double)?

        // Find best matching existing topic
        for (i, topic) in boostedTopics.enumerated() {
            let topicKeySet = Set(topic.keywords)
            let similarity = jaccardSimilarity(newKeySet, topicKeySet)
            if similarity >= config.clusterSimilarityThreshold {
                if bestMatch == nil || similarity > bestMatch!.similarity {
                    bestMatch = (i, similarity)
                }
            }
        }

        if let match = bestMatch {
            // Update existing topic
            var topic = boostedTopics[match.index]
            if !topic.articleIds.contains(newSignal.articleId) {
                topic.articleIds.append(newSignal.articleId)
                topic.articleCount = topic.articleIds.count
            }
            if !topic.feedURLs.contains(newSignal.feedURL) {
                topic.feedURLs.append(newSignal.feedURL)
                topic.feedCount = topic.feedURLs.count
                topic.peakFeedCount = max(topic.peakFeedCount, topic.feedCount)
            }
            // Merge keywords (union of top keywords)
            let merged = mergeKeywords(existing: topic.keywords, new: newSignal.keywords)
            topic.keywords = Array(merged.prefix(config.keywordsPerArticle))
            topic.lastUpdated = Date()
            topic.signalStrength = computeStrength(topic: topic)
            boostedTopics[match.index] = topic

            if topic.feedCount >= config.convergenceThreshold {
                NotificationCenter.default.post(name: .signalBoostDetected, object: topic)
                return topic
            }
            return nil
        }

        // Check against recent signals for new cluster formation
        let cutoff = Date().addingTimeInterval(-config.timeWindowSeconds)
        let recentSignals = signals.filter { $0.ingestedDate >= cutoff && $0.articleId != newSignal.articleId }

        var clusterFeeds: Set<String> = [newSignal.feedURL]
        var clusterArticles: [String] = [newSignal.articleId]
        var clusterKeywords = newKeySet

        for signal in recentSignals {
            let sigKeySet = Set(signal.keywords)
            let sim = jaccardSimilarity(newKeySet, sigKeySet)
            if sim >= config.clusterSimilarityThreshold {
                clusterFeeds.insert(signal.feedURL)
                if !clusterArticles.contains(signal.articleId) {
                    clusterArticles.append(signal.articleId)
                }
                clusterKeywords = clusterKeywords.union(sigKeySet)
            }
        }

        if clusterFeeds.count >= config.convergenceThreshold {
            let topKeywords = Array(clusterKeywords.prefix(config.keywordsPerArticle))
            let topic = BoostedTopic(
                id: UUID().uuidString,
                keywords: topKeywords,
                signalStrength: 0.0,
                feedCount: clusterFeeds.count,
                articleCount: clusterArticles.count,
                phase: .emerging,
                articleIds: clusterArticles,
                feedURLs: Array(clusterFeeds),
                firstDetected: Date(),
                lastUpdated: Date(),
                peakFeedCount: clusterFeeds.count
            )
            var mutableTopic = topic
            mutableTopic.signalStrength = computeStrength(topic: mutableTopic)

            boostedTopics.append(mutableTopic)
            trimTopics()

            NotificationCenter.default.post(name: .signalBoostDetected, object: mutableTopic)
            return mutableTopic
        }

        return nil
    }

    private func jaccardSimilarity(_ a: Set<String>, _ b: Set<String>) -> Double {
        guard !a.isEmpty || !b.isEmpty else { return 0.0 }
        let intersection = a.intersection(b).count
        let union = a.union(b).count
        return Double(intersection) / Double(union)
    }

    private func mergeKeywords(existing: [String], new: [String]) -> [String] {
        var seen: Set<String> = []
        var merged: [String] = []
        for kw in existing + new {
            if seen.insert(kw).inserted {
                merged.append(kw)
            }
        }
        return merged
    }

    private func computeStrength(topic: BoostedTopic) -> Double {
        // Signal strength = f(feed diversity, article count, recency)
        let feedScore = min(Double(topic.feedCount) / 5.0, 1.0)  // Saturates at 5 feeds
        let articleScore = min(Double(topic.articleCount) / 10.0, 1.0) // Saturates at 10 articles
        let hoursSinceUpdate = Date().timeIntervalSince(topic.lastUpdated) / 3600.0
        let recencyScore = max(0.0, 1.0 - (hoursSinceUpdate / 48.0))  // Decays over 48h

        return (feedScore * 0.45 + articleScore * 0.25 + recencyScore * 0.30)
    }

    // MARK: - Phase Management (Private)

    private func updatePhases() {
        let now = Date()
        for i in 0..<boostedTopics.count {
            var topic = boostedTopics[i]
            let hoursSinceUpdate = now.timeIntervalSince(topic.lastUpdated) / 3600.0
            let oldPhase = topic.phase

            switch topic.phase {
            case .emerging:
                if topic.feedCount >= topic.peakFeedCount && topic.feedCount >= config.convergenceThreshold + 1 {
                    topic.phase = .peaking
                }
                if hoursSinceUpdate > config.fadingThresholdHours {
                    topic.phase = .fading
                }
            case .peaking:
                if hoursSinceUpdate > config.fadingThresholdHours {
                    topic.phase = .fading
                }
            case .fading:
                if hoursSinceUpdate > config.archiveThresholdHours {
                    topic.phase = .archived
                }
            case .archived:
                break
            }

            topic.signalStrength = computeStrength(topic: topic)
            boostedTopics[i] = topic

            if topic.phase != oldPhase {
                NotificationCenter.default.post(name: .signalBoostPhaseChanged, object: topic)
            }
        }
    }

    // MARK: - Pruning (Private)

    private func pruneOldSignals() {
        let cutoff = Date().addingTimeInterval(-config.timeWindowSeconds * 2)
        signals = signals.filter { $0.ingestedDate >= cutoff }
    }

    private func trimTopics() {
        if boostedTopics.count > config.maxActiveTopics {
            // Remove oldest archived topics first
            boostedTopics.sort { $0.lastUpdated > $1.lastUpdated }
            while boostedTopics.count > config.maxActiveTopics {
                if let archIdx = boostedTopics.lastIndex(where: { $0.phase == .archived }) {
                    boostedTopics.remove(at: archIdx)
                } else {
                    boostedTopics.removeLast()
                }
            }
        }
    }

    // MARK: - Persistence (Private)

    private func loadState() {
        guard let data = try? Data(contentsOf: storageURL) else { return }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        if let state = try? decoder.decode(BoosterState.self, from: data) {
            signals = state.signals
            boostedTopics = state.boostedTopics
            seenArticleIds = state.seenArticleIds
            config = state.config
        }
    }

    private func saveState() {
        let state = BoosterState(
            signals: signals,
            boostedTopics: boostedTopics,
            seenArticleIds: seenArticleIds,
            config: config
        )
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = .prettyPrinted
        if let data = try? encoder.encode(state) {
            try? data.write(to: storageURL, options: .atomic)
        }
    }
}

// MARK: - State Container

private struct BoosterState: Codable {
    let signals: [ArticleSignal]
    let boostedTopics: [BoostedTopic]
    let seenArticleIds: Set<String>
    let config: SignalBoosterConfig
}
