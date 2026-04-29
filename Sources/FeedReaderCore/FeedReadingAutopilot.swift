//
//  FeedReadingAutopilot.swift
//  FeedReaderCore
//
//  Autonomous reading session planner that curates optimal article sequences
//  given a time budget. The autopilot considers:
//
//  - Priority scoring (freshness, source credibility, topic relevance)
//  - Estimated reading time per article
//  - Topic diversity (avoids monotonous single-topic sessions)
//  - Cognitive load balancing (alternates heavy/light content)
//  - Reading momentum (starts accessible, builds complexity, winds down)
//
//  Usage:
//  ```swift
//  let autopilot = FeedReadingAutopilot()
//
//  // Plan a 20-minute reading session
//  let session = autopilot.planSession(
//      articles: allArticles,
//      timeBudgetMinutes: 20,
//      preferences: .default
//  )
//
//  print(session.playlist)          // ordered article list
//  print(session.totalMinutes)      // estimated total time
//  print(session.diversityScore)    // topic variety 0-100
//  print(session.cognitiveProfile)  // load curve description
//  print(session.sessionBrief)      // human-readable summary
//  ```
//
//  All processing is on-device. No network calls or external deps.
//

import Foundation

// MARK: - Cognitive Load Level

/// Estimated cognitive demand of an article.
public enum CognitiveLoad: String, CaseIterable, Sendable, Comparable {
    case light    = "light"
    case moderate = "moderate"
    case heavy    = "heavy"
    case dense    = "dense"

    public var weight: Double {
        switch self {
        case .light:    return 1.0
        case .moderate: return 2.0
        case .heavy:    return 3.0
        case .dense:    return 4.0
        }
    }

    public var emoji: String {
        switch self {
        case .light:    return "☀️"
        case .moderate: return "⛅"
        case .heavy:    return "🌧️"
        case .dense:    return "🌩️"
        }
    }

    public static func < (lhs: CognitiveLoad, rhs: CognitiveLoad) -> Bool {
        lhs.weight < rhs.weight
    }
}

// MARK: - Session Mood

/// Desired reading session mood/intensity.
public enum SessionMood: String, CaseIterable, Sendable {
    case relaxed     = "relaxed"      // prefer light content
    case balanced    = "balanced"     // mix of everything
    case focused     = "focused"      // prefer deep reads
    case exploratory = "exploratory"  // maximize topic diversity

    public var description: String {
        switch self {
        case .relaxed:     return "Light & easy reading"
        case .balanced:    return "Mix of depth and breadth"
        case .focused:     return "Deep, concentrated reading"
        case .exploratory: return "Wide-ranging discovery"
        }
    }
}

// MARK: - Session Preferences

/// Configuration for session planning.
public struct SessionPreferences: Sendable {
    /// Desired mood/intensity.
    public var mood: SessionMood

    /// Preferred topics (boost priority for matching articles).
    public var preferredTopics: [String]

    /// Topics to avoid in this session.
    public var excludedTopics: [String]

    /// Minimum topic diversity (0.0 to 1.0). Higher = more varied.
    public var minimumDiversity: Double

    /// Whether to include a "cooldown" article at the end.
    public var includeCooldown: Bool

    /// Maximum reading time per article in minutes (skip longer ones).
    public var maxArticleMinutes: Int

    public static let `default` = SessionPreferences(
        mood: .balanced,
        preferredTopics: [],
        excludedTopics: [],
        minimumDiversity: 0.4,
        includeCooldown: true,
        maxArticleMinutes: 12
    )

    public init(
        mood: SessionMood = .balanced,
        preferredTopics: [String] = [],
        excludedTopics: [String] = [],
        minimumDiversity: Double = 0.4,
        includeCooldown: Bool = true,
        maxArticleMinutes: Int = 12
    ) {
        self.mood = mood
        self.preferredTopics = preferredTopics
        self.excludedTopics = excludedTopics
        self.minimumDiversity = max(0, min(1, minimumDiversity))
        self.includeCooldown = includeCooldown
        self.maxArticleMinutes = maxArticleMinutes
    }
}

// MARK: - Planned Article

/// An article selected for the reading session with computed metadata.
public struct PlannedArticle: Sendable {
    /// Original article title.
    public let title: String

    /// Original article body text.
    public let body: String

    /// Article source link.
    public let link: String

    /// Estimated reading time in minutes.
    public let estimatedMinutes: Double

    /// Detected primary topic.
    public let topic: String

    /// Cognitive load classification.
    public let cognitiveLoad: CognitiveLoad

    /// Priority score (0-100).
    public let priorityScore: Double

    /// Position in the session playlist (1-based).
    public let position: Int

    /// Why this article was selected.
    public let selectionReason: String
}

// MARK: - Session Plan

/// Complete reading session plan with analytics.
public struct SessionPlan: Sendable {
    /// Ordered list of articles to read.
    public let playlist: [PlannedArticle]

    /// Total estimated reading time in minutes.
    public let totalMinutes: Double

    /// Time budget that was requested.
    public let budgetMinutes: Int

    /// Topic diversity score (0-100).
    public let diversityScore: Double

    /// Cognitive load curve description.
    public let cognitiveProfile: String

    /// Number of distinct topics covered.
    public let topicCount: Int

    /// Unique topics in order of appearance.
    public let topics: [String]

    /// Average priority score of selected articles.
    public let averagePriority: Double

    /// Session mood that was used.
    public let mood: SessionMood

    /// Human-readable session brief.
    public let sessionBrief: String

    /// Utilization: totalMinutes / budgetMinutes (0-1).
    public var budgetUtilization: Double {
        guard budgetMinutes > 0 else { return 0 }
        return min(1.0, totalMinutes / Double(budgetMinutes))
    }

    /// Number of articles in the playlist.
    public var articleCount: Int { playlist.count }
}

// MARK: - Autopilot Engine

/// Autonomous reading session planner.
public class FeedReadingAutopilot {

    // MARK: - Configuration

    /// Average reading speed in words per minute.
    public var wordsPerMinute: Int = 230

    /// Weight for freshness in priority calculation (0-1).
    public var freshnessWeight: Double = 0.3

    /// Weight for topic relevance in priority calculation (0-1).
    public var relevanceWeight: Double = 0.4

    /// Weight for content quality signals in priority calculation (0-1).
    public var qualityWeight: Double = 0.3

    // MARK: - Internal State

    private let keywordExtractor: KeywordExtractor

    // MARK: - Initialization

    public init() {
        self.keywordExtractor = KeywordExtractor()
    }

    // MARK: - Public API

    /// Plan a reading session given available articles and a time budget.
    /// - Parameters:
    ///   - articles: Available articles to choose from.
    ///   - timeBudgetMinutes: Total reading time available.
    ///   - preferences: Session configuration.
    /// - Returns: An optimized SessionPlan.
    public func planSession(
        articles: [RSSStory],
        timeBudgetMinutes: Int,
        preferences: SessionPreferences = .default
    ) -> SessionPlan {
        guard !articles.isEmpty, timeBudgetMinutes > 0 else {
            return emptyPlan(budgetMinutes: timeBudgetMinutes, mood: preferences.mood)
        }

        // Phase 1: Score and classify all articles
        let candidates = articles.compactMap { article -> ArticleCandidate? in
            return scoreArticle(article, preferences: preferences)
        }

        // Phase 2: Filter by preferences
        let filtered = filterCandidates(candidates, preferences: preferences)

        guard !filtered.isEmpty else {
            return emptyPlan(budgetMinutes: timeBudgetMinutes, mood: preferences.mood)
        }

        // Phase 3: Select articles within time budget using greedy optimization
        let selected = selectArticles(
            from: filtered,
            budgetMinutes: Double(timeBudgetMinutes),
            preferences: preferences
        )

        // Phase 4: Sequence for optimal cognitive flow
        let sequenced = sequenceForFlow(selected, mood: preferences.mood)

        // Phase 5: Build the session plan
        return buildPlan(
            sequenced: sequenced,
            budgetMinutes: timeBudgetMinutes,
            mood: preferences.mood
        )
    }

    /// Quick estimate: how many articles fit in a time budget.
    public func estimateCapacity(
        articles: [RSSStory],
        timeBudgetMinutes: Int
    ) -> Int {
        guard !articles.isEmpty, timeBudgetMinutes > 0 else { return 0 }
        let avgWords = articles.reduce(0) { $0 + wordCount($1.body) } / articles.count
        let avgMinutes = Double(avgWords) / Double(wordsPerMinute)
        guard avgMinutes > 0 else { return 0 }
        return Int(Double(timeBudgetMinutes) / avgMinutes)
    }

    /// Suggest an ideal time budget given available articles.
    public func suggestBudget(articles: [RSSStory], targetArticles: Int = 5) -> Int {
        guard !articles.isEmpty else { return 0 }
        let sorted = articles.sorted { wordCount($0.body) < wordCount($1.body) }
        let topN = Array(sorted.prefix(targetArticles))
        let totalWords = topN.reduce(0) { $0 + wordCount($1.body) }
        let minutes = Double(totalWords) / Double(wordsPerMinute)
        return Int(ceil(minutes))
    }

    // MARK: - Internal Types

    private struct ArticleCandidate {
        let story: RSSStory
        let readingMinutes: Double
        let topic: String
        let cognitiveLoad: CognitiveLoad
        let priorityScore: Double
        let keywords: [String]
    }

    // MARK: - Phase 1: Scoring

    private func scoreArticle(
        _ article: RSSStory,
        preferences: SessionPreferences
    ) -> ArticleCandidate? {
        let words = wordCount(article.body)
        guard words > 10 else { return nil } // Skip extremely short articles

        let minutes = Double(words) / Double(wordsPerMinute)
        let keywords = keywordExtractor.extractKeywords(from: article.body, count: 5)
        let topic = keywords.first ?? "general"
        let load = classifyCognitiveLoad(words: words, body: article.body)

        // Calculate priority score
        let qualityScore = calculateQualityScore(article)
        let relevanceScore = calculateRelevanceScore(keywords: keywords, preferences: preferences)
        let freshnessScore = calculateFreshnessScore(article)

        let priority = (freshnessWeight * freshnessScore +
                       relevanceWeight * relevanceScore +
                       qualityWeight * qualityScore) * 100.0

        return ArticleCandidate(
            story: article,
            readingMinutes: minutes,
            topic: topic,
            cognitiveLoad: load,
            priorityScore: min(100, max(0, priority)),
            keywords: keywords
        )
    }

    private func classifyCognitiveLoad(words: Int, body: String) -> CognitiveLoad {
        // Heuristics for cognitive load:
        // - Word count (longer = heavier)
        // - Average sentence length
        // - Technical indicator words
        let sentenceCount = max(1, body.components(separatedBy: CharacterSet(charactersIn: ".!?")).count - 1)
        let avgSentenceLength = Double(words) / Double(sentenceCount)

        let technicalIndicators = [
            "algorithm", "implementation", "framework", "architecture",
            "infrastructure", "methodology", "optimization", "hypothesis",
            "correlation", "statistical", "quantum", "neural", "cryptograph"
        ]
        let lowerBody = body.lowercased()
        let techCount = technicalIndicators.filter { lowerBody.contains($0) }.count

        var score: Double = 0
        // Word count contribution
        if words > 1500 { score += 3 }
        else if words > 800 { score += 2 }
        else if words > 400 { score += 1 }

        // Sentence complexity
        if avgSentenceLength > 25 { score += 2 }
        else if avgSentenceLength > 18 { score += 1 }

        // Technical density
        score += Double(min(techCount, 3))

        if score >= 6 { return .dense }
        if score >= 4 { return .heavy }
        if score >= 2 { return .moderate }
        return .light
    }

    private func calculateQualityScore(_ article: RSSStory) -> Double {
        var score = 0.5
        let words = wordCount(article.body)

        // Prefer articles with meaningful length
        if words >= 200 && words <= 2000 { score += 0.3 }
        else if words >= 100 { score += 0.15 }

        // Title quality
        if !article.title.isEmpty && article.title.count > 10 { score += 0.1 }

        // Has image
        if article.imagePath != nil { score += 0.1 }

        return min(1.0, score)
    }

    private func calculateRelevanceScore(
        keywords: [String],
        preferences: SessionPreferences
    ) -> Double {
        guard !preferences.preferredTopics.isEmpty else { return 0.5 }

        let lowerPreferred = preferences.preferredTopics.map { $0.lowercased() }
        let matchCount = keywords.filter { kw in
            lowerPreferred.contains(where: { kw.contains($0) || $0.contains(kw) })
        }.count

        return min(1.0, Double(matchCount) / Double(max(1, min(3, lowerPreferred.count))))
    }

    private func calculateFreshnessScore(_ article: RSSStory) -> Double {
        // Without published date, use position-based heuristic
        // Articles earlier in feed tend to be newer
        return 0.6 // Neutral freshness when no date available
    }

    // MARK: - Phase 2: Filtering

    private func filterCandidates(
        _ candidates: [ArticleCandidate],
        preferences: SessionPreferences
    ) -> [ArticleCandidate] {
        let lowerExcluded = preferences.excludedTopics.map { $0.lowercased() }

        return candidates.filter { candidate in
            // Respect max article length
            if candidate.readingMinutes > Double(preferences.maxArticleMinutes) {
                return false
            }

            // Exclude topics
            if !lowerExcluded.isEmpty {
                let hasExcluded = candidate.keywords.contains { kw in
                    lowerExcluded.contains(where: { kw.contains($0) || $0.contains(kw) })
                }
                if hasExcluded { return false }
            }

            // Mood-based filtering
            switch preferences.mood {
            case .relaxed:
                return candidate.cognitiveLoad <= .moderate
            case .focused:
                return candidate.cognitiveLoad >= .moderate
            case .balanced, .exploratory:
                return true
            }
        }
    }

    // MARK: - Phase 3: Selection (Knapsack-inspired greedy)

    private func selectArticles(
        from candidates: [ArticleCandidate],
        budgetMinutes: Double,
        preferences: SessionPreferences
    ) -> [ArticleCandidate] {
        // Sort by value density: priority per minute
        let sorted = candidates.sorted { a, b in
            let densityA = a.priorityScore / max(0.5, a.readingMinutes)
            let densityB = b.priorityScore / max(0.5, b.readingMinutes)
            return densityA > densityB
        }

        var selected: [ArticleCandidate] = []
        var remainingMinutes = budgetMinutes
        var selectedTopics = Set<String>()

        // First pass: greedy by priority density with diversity bonus
        for candidate in sorted {
            guard remainingMinutes >= candidate.readingMinutes else { continue }

            // Diversity check: if we already have 2+ articles on same topic, skip
            let topicCount = selected.filter { $0.topic == candidate.topic }.count
            if topicCount >= 2 && preferences.mood == .exploratory { continue }
            if topicCount >= 3 { continue }

            selected.append(candidate)
            selectedTopics.insert(candidate.topic)
            remainingMinutes -= candidate.readingMinutes
        }

        // If diversity is too low and we have alternatives, swap some
        if preferences.minimumDiversity > 0 && selected.count > 2 {
            let diversity = Double(selectedTopics.count) / Double(selected.count)
            if diversity < preferences.minimumDiversity {
                selected = improveDiversity(
                    selected: selected,
                    pool: sorted,
                    budgetMinutes: budgetMinutes,
                    targetDiversity: preferences.minimumDiversity
                )
            }
        }

        return selected
    }

    private func improveDiversity(
        selected: [ArticleCandidate],
        pool: [ArticleCandidate],
        budgetMinutes: Double,
        targetDiversity: Double
    ) -> [ArticleCandidate] {
        var result = selected

        // Find overrepresented topics
        var topicCounts: [String: Int] = [:]
        for article in result {
            topicCounts[article.topic, default: 0] += 1
        }

        // Replace duplicate-topic articles with diverse alternatives
        let overrepresented = topicCounts.filter { $0.value > 1 }
        let usedLinks = Set(result.map { $0.story.link })

        for (topic, _) in overrepresented {
            // Find an alternative from a different topic
            if let alternative = pool.first(where: { candidate in
                candidate.topic != topic &&
                !usedLinks.contains(candidate.story.link) &&
                !result.contains(where: { $0.story.link == candidate.story.link })
            }) {
                // Replace the lowest-priority duplicate
                if let idx = result.lastIndex(where: { $0.topic == topic }) {
                    let totalWithSwap = result.enumerated()
                        .filter { $0.offset != idx }
                        .reduce(0.0) { $0 + $1.element.readingMinutes } + alternative.readingMinutes

                    if totalWithSwap <= budgetMinutes {
                        result[idx] = alternative
                    }
                }
            }

            // Check if we've met diversity target
            let uniqueTopics = Set(result.map { $0.topic })
            let currentDiversity = Double(uniqueTopics.count) / Double(result.count)
            if currentDiversity >= targetDiversity { break }
        }

        return result
    }

    // MARK: - Phase 4: Sequencing for Cognitive Flow

    private func sequenceForFlow(
        _ articles: [ArticleCandidate],
        mood: SessionMood
    ) -> [ArticleCandidate] {
        guard articles.count > 2 else { return articles }

        switch mood {
        case .relaxed:
            // Lightest first, gradually heavier (but never too heavy)
            return articles.sorted { $0.cognitiveLoad < $1.cognitiveLoad }

        case .focused:
            // Start moderate, build to heavy, end moderate
            return buildArcSequence(articles, peak: .heavy)

        case .balanced:
            // Wave pattern: light-heavy-light-heavy with diversity interleaving
            return buildWaveSequence(articles)

        case .exploratory:
            // Maximize topic transitions (no two adjacent same-topic)
            return buildDiverseSequence(articles)
        }
    }

    private func buildArcSequence(_ articles: [ArticleCandidate], peak: CognitiveLoad) -> [ArticleCandidate] {
        let sorted = articles.sorted { $0.cognitiveLoad < $1.cognitiveLoad }
        guard sorted.count >= 3 else { return sorted }

        // Build an arc: light → heavy → light
        var result: [ArticleCandidate] = []
        let mid = sorted.count / 2

        // First half: ascending
        let ascending = Array(sorted[0..<mid])
        // Middle: heaviest
        let peak = Array(sorted[mid...])
        // Interleave for arc shape
        result.append(contentsOf: ascending)
        result.append(contentsOf: peak.reversed())

        return result
    }

    private func buildWaveSequence(_ articles: [ArticleCandidate]) -> [ArticleCandidate] {
        let light = articles.filter { $0.cognitiveLoad <= .moderate }
            .sorted { $0.priorityScore > $1.priorityScore }
        let heavy = articles.filter { $0.cognitiveLoad > .moderate }
            .sorted { $0.priorityScore > $1.priorityScore }

        var result: [ArticleCandidate] = []
        var li = 0, hi = 0

        // Alternate light and heavy
        while li < light.count || hi < heavy.count {
            if li < light.count {
                result.append(light[li])
                li += 1
            }
            if hi < heavy.count {
                result.append(heavy[hi])
                hi += 1
            }
        }

        return result
    }

    private func buildDiverseSequence(_ articles: [ArticleCandidate]) -> [ArticleCandidate] {
        var remaining = articles
        var result: [ArticleCandidate] = []

        // Greedy: always pick the next article with a different topic
        var lastTopic: String? = nil

        while !remaining.isEmpty {
            let differentTopic = remaining.first { $0.topic != lastTopic }
            let next: ArticleCandidate

            if let dt = differentTopic {
                next = dt
            } else {
                next = remaining[0]
            }

            result.append(next)
            lastTopic = next.topic
            remaining.removeAll { $0.story.link == next.story.link }
        }

        return result
    }

    // MARK: - Phase 5: Build Plan

    private func buildPlan(
        sequenced: [ArticleCandidate],
        budgetMinutes: Int,
        mood: SessionMood
    ) -> SessionPlan {
        let totalMinutes = sequenced.reduce(0.0) { $0 + $1.readingMinutes }
        let topics = orderedUniqueTopics(sequenced)
        let diversityScore = sequenced.isEmpty ? 0 :
            (Double(topics.count) / Double(sequenced.count)) * 100.0
        let avgPriority = sequenced.isEmpty ? 0 :
            sequenced.reduce(0.0) { $0 + $1.priorityScore } / Double(sequenced.count)

        let playlist = sequenced.enumerated().map { idx, candidate in
            PlannedArticle(
                title: candidate.story.title,
                body: candidate.story.body,
                link: candidate.story.link,
                estimatedMinutes: candidate.readingMinutes,
                topic: candidate.topic,
                cognitiveLoad: candidate.cognitiveLoad,
                priorityScore: candidate.priorityScore,
                position: idx + 1,
                selectionReason: buildReason(candidate, position: idx, total: sequenced.count)
            )
        }

        let cognitiveProfile = describeCognitiveProfile(sequenced)
        let brief = generateBrief(
            articleCount: sequenced.count,
            totalMinutes: totalMinutes,
            budgetMinutes: budgetMinutes,
            topics: topics,
            mood: mood,
            cognitiveProfile: cognitiveProfile
        )

        return SessionPlan(
            playlist: playlist,
            totalMinutes: totalMinutes,
            budgetMinutes: budgetMinutes,
            diversityScore: min(100, diversityScore),
            cognitiveProfile: cognitiveProfile,
            topicCount: topics.count,
            topics: topics,
            averagePriority: avgPriority,
            mood: mood,
            sessionBrief: brief
        )
    }

    private func buildReason(
        _ candidate: ArticleCandidate,
        position: Int,
        total: Int
    ) -> String {
        var reasons: [String] = []

        if candidate.priorityScore >= 70 {
            reasons.append("high priority")
        }
        if position == 0 {
            reasons.append("accessible opener")
        }
        if position == total - 1 && candidate.cognitiveLoad <= .moderate {
            reasons.append("light cooldown")
        }
        if candidate.cognitiveLoad == .light {
            reasons.append("easy read")
        }
        if candidate.cognitiveLoad >= .heavy {
            reasons.append("deep dive")
        }

        return reasons.isEmpty ? "good fit for session" : reasons.joined(separator: ", ")
    }

    private func describeCognitiveProfile(_ articles: [ArticleCandidate]) -> String {
        guard !articles.isEmpty else { return "empty" }

        let loads = articles.map { $0.cognitiveLoad }
        let avgLoad = loads.reduce(0.0) { $0 + $1.weight } / Double(loads.count)

        if loads.count <= 2 {
            return "brief session"
        }

        let first = loads[0]
        let middle = loads[loads.count / 2]
        let last = loads[loads.count - 1]

        if first < middle && middle > last {
            return "arc pattern (builds up, winds down)"
        }
        if avgLoad <= 1.5 {
            return "light throughout"
        }
        if avgLoad >= 3.0 {
            return "intensive deep reading"
        }

        // Check for wave pattern
        var transitions = 0
        for i in 1..<loads.count {
            if loads[i] != loads[i-1] { transitions += 1 }
        }
        if transitions >= loads.count / 2 {
            return "wave pattern (alternating depth)"
        }

        return "varied mix"
    }

    private func generateBrief(
        articleCount: Int,
        totalMinutes: Double,
        budgetMinutes: Int,
        topics: [String],
        mood: SessionMood,
        cognitiveProfile: String
    ) -> String {
        let minutesStr = String(format: "%.0f", totalMinutes)
        let topicList = topics.prefix(4).joined(separator: ", ")
        let moodEmoji: String
        switch mood {
        case .relaxed:     moodEmoji = "🌿"
        case .balanced:    moodEmoji = "⚖️"
        case .focused:     moodEmoji = "🎯"
        case .exploratory: moodEmoji = "🧭"
        }

        return "\(moodEmoji) \(articleCount) articles · ~\(minutesStr) min · " +
               "Topics: \(topicList) · " +
               "Flow: \(cognitiveProfile)"
    }

    // MARK: - Utilities

    private func wordCount(_ text: String) -> Int {
        text.split(whereSeparator: { $0.isWhitespace || $0.isNewline }).count
    }

    private func orderedUniqueTopics(_ candidates: [ArticleCandidate]) -> [String] {
        var seen = Set<String>()
        var result: [String] = []
        for candidate in candidates {
            if !seen.contains(candidate.topic) {
                seen.insert(candidate.topic)
                result.append(candidate.topic)
            }
        }
        return result
    }

    private func emptyPlan(budgetMinutes: Int, mood: SessionMood) -> SessionPlan {
        return SessionPlan(
            playlist: [],
            totalMinutes: 0,
            budgetMinutes: budgetMinutes,
            diversityScore: 0,
            cognitiveProfile: "empty",
            topicCount: 0,
            topics: [],
            averagePriority: 0,
            mood: mood,
            sessionBrief: "No articles available for this session."
        )
    }
}
