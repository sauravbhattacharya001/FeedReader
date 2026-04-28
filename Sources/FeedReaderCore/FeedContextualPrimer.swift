//
//  FeedContextualPrimer.swift
//  FeedReaderCore
//
//  Autonomous reading preparation engine that primes the reader before
//  diving into an article. Analyzes the target article against the reader's
//  history to produce a contextual primer containing:
//
//  - **Background Refresher:** Related articles the reader has seen before,
//    ranked by relevance, to jog memory on prerequisite context.
//  - **Concept Familiarity Map:** Terms/concepts in the article scored by
//    how familiar they are based on past reading frequency.
//  - **Knowledge Readiness Score:** 0-100 estimate of how prepared the
//    reader is for the article given prior reading.
//  - **Optimal Reading Order:** Given a set of queued articles, suggests
//    an ordering that builds knowledge progressively (concept scaffolding).
//  - **Blind Spots:** Important concepts that appear frequently in the
//    article but have never appeared in the reader's history.
//
//  Usage:
//  ```swift
//  let primer = FeedContextualPrimer()
//
//  // Register reading history
//  primer.recordReading(story: someStory)
//
//  // Get a primer for a new article
//  let brief = primer.preparePrimer(for: targetStory)
//  print(brief.readinessScore)         // 72
//  print(brief.backgroundRefreshers)   // related past articles
//  print(brief.blindSpots)             // concepts you haven't seen
//  print(brief.familiarityMap)         // term → familiarity level
//
//  // Optimal reading order for queued articles
//  let order = primer.suggestReadingOrder(for: queuedStories)
//  ```
//
//  All processing is on-device. No network calls or external deps.
//

import Foundation

// MARK: - Familiarity Level

/// How familiar the reader is with a given concept based on reading history.
public enum FamiliarityLevel: String, CaseIterable, Sendable, Comparable {
    case unknown    = "unknown"     // Never seen
    case glimpsed   = "glimpsed"   // Seen 1-2 times
    case familiar   = "familiar"   // Seen 3-7 times
    case wellKnown  = "well_known" // Seen 8+ times

    /// Numeric weight for scoring (0.0 – 1.0).
    public var weight: Double {
        switch self {
        case .unknown:   return 0.0
        case .glimpsed:  return 0.3
        case .familiar:  return 0.7
        case .wellKnown: return 1.0
        }
    }

    public static func < (lhs: FamiliarityLevel, rhs: FamiliarityLevel) -> Bool {
        return lhs.weight < rhs.weight
    }
}

// MARK: - Concept Entry

/// A concept/term found in an article with its familiarity assessment.
public struct ConceptEntry: Sendable {
    /// The concept term (lowercased).
    public let term: String
    /// How many times it appears in the target article.
    public let articleFrequency: Int
    /// How many times the reader has encountered it historically.
    public let historicalExposure: Int
    /// Assessed familiarity level.
    public let familiarity: FamiliarityLevel

    public init(term: String, articleFrequency: Int, historicalExposure: Int, familiarity: FamiliarityLevel) {
        self.term = term
        self.articleFrequency = articleFrequency
        self.historicalExposure = historicalExposure
        self.familiarity = familiarity
    }
}

// MARK: - Background Refresher

/// A past article related to the target, useful for refreshing context.
public struct BackgroundRefresher: Sendable {
    /// Title of the related past article.
    public let title: String
    /// Link to the past article.
    public let link: String
    /// Relevance score (0.0 – 1.0) based on concept overlap.
    public let relevanceScore: Double
    /// Shared concepts between the past article and the target.
    public let sharedConcepts: [String]

    public init(title: String, link: String, relevanceScore: Double, sharedConcepts: [String]) {
        self.title = title
        self.link = link
        self.relevanceScore = relevanceScore
        self.sharedConcepts = sharedConcepts
    }
}

// MARK: - Reading Order Item

/// An article in a suggested reading sequence with scaffolding rationale.
public struct ReadingOrderItem: Sendable {
    /// The article title.
    public let title: String
    /// The article link.
    public let link: String
    /// Position in the suggested order (1-based).
    public let position: Int
    /// Concepts this article introduces that later articles depend on.
    public let conceptsIntroduced: [String]
    /// Knowledge readiness score at this position assuming prior articles are read.
    public let cumulativeReadiness: Double

    public init(title: String, link: String, position: Int, conceptsIntroduced: [String], cumulativeReadiness: Double) {
        self.title = title
        self.link = link
        self.position = position
        self.conceptsIntroduced = conceptsIntroduced
        self.cumulativeReadiness = cumulativeReadiness
    }
}

// MARK: - Primer Report

/// Complete contextual primer for a target article.
public struct PrimerReport: Sendable {
    /// The target article title.
    public let targetTitle: String
    /// The target article link.
    public let targetLink: String
    /// Knowledge readiness score (0–100).
    public let readinessScore: Int
    /// Readiness label.
    public let readinessLabel: String
    /// Familiarity map: concept → entry with familiarity assessment.
    public let familiarityMap: [ConceptEntry]
    /// Concepts the reader has never encountered.
    public let blindSpots: [String]
    /// Related past articles for background refresher.
    public let backgroundRefreshers: [BackgroundRefresher]
    /// Summary text describing preparation status.
    public let summary: String
    /// Timestamp of primer generation.
    public let generatedAt: Date

    public init(targetTitle: String, targetLink: String, readinessScore: Int,
                readinessLabel: String, familiarityMap: [ConceptEntry],
                blindSpots: [String], backgroundRefreshers: [BackgroundRefresher],
                summary: String, generatedAt: Date) {
        self.targetTitle = targetTitle
        self.targetLink = targetLink
        self.readinessScore = readinessScore
        self.readinessLabel = readinessLabel
        self.familiarityMap = familiarityMap
        self.blindSpots = blindSpots
        self.backgroundRefreshers = backgroundRefreshers
        self.summary = summary
        self.generatedAt = generatedAt
    }
}

// MARK: - History Entry (internal)

/// Internal record of a read article's extracted concepts.
struct ReadingHistoryEntry: Codable {
    let title: String
    let link: String
    let concepts: [String: Int]  // term → frequency in that article
    let readAt: Date
}

// MARK: - FeedContextualPrimer

/// Autonomous reading preparation engine.
///
/// Maintains a concept-indexed reading history and uses it to assess how
/// prepared the reader is for any new article. Produces contextual primers
/// with background refreshers, concept familiarity maps, blind spot warnings,
/// and optimal reading order suggestions.
public class FeedContextualPrimer {

    // MARK: - Configuration

    /// Minimum word length for concept extraction.
    public var minimumConceptLength: Int = 4

    /// Maximum number of background refreshers to include in a primer.
    public var maxRefreshers: Int = 5

    /// Maximum number of blind spots to report.
    public var maxBlindSpots: Int = 10

    /// Minimum relevance score to include a refresher (0.0–1.0).
    public var refresherThreshold: Double = 0.1

    /// Decay factor for historical exposure (older readings count less).
    /// Applied per 30-day period. 1.0 = no decay.
    public var decayFactor: Double = 0.85

    /// Days after which a reading is considered stale for decay purposes.
    public var decayWindowDays: Int = 30

    // MARK: - State

    private var history: [ReadingHistoryEntry] = []

    /// Aggregated concept exposure across all history (with decay applied lazily).
    private var conceptExposureCache: [String: Int]?
    private var cacheDate: Date?

    // MARK: - Initialization

    public init() {}

    // MARK: - Recording History

    /// Records a read article into the history.
    /// - Parameter story: The article that was read.
    public func recordReading(story: RSSStory) {
        recordReading(title: story.title, link: story.link, body: story.body)
    }

    /// Records a read article using raw fields.
    public func recordReading(title: String, link: String, body: String, readAt: Date = Date()) {
        let text = title + " " + body
        let frequencies = TextUtilities.computeWordFrequencies(from: text, minimumLength: minimumConceptLength)
        let entry = ReadingHistoryEntry(title: title, link: link, concepts: frequencies, readAt: readAt)
        history.append(entry)
        conceptExposureCache = nil  // invalidate cache
    }

    /// Number of articles in the reading history.
    public var historyCount: Int { history.count }

    /// Clears all reading history.
    public func clearHistory() {
        history.removeAll()
        conceptExposureCache = nil
    }

    // MARK: - Primer Generation

    /// Generates a contextual primer for a target article.
    /// - Parameter story: The article to prepare for.
    /// - Returns: A `PrimerReport` with readiness assessment and recommendations.
    public func preparePrimer(for story: RSSStory) -> PrimerReport {
        return preparePrimer(title: story.title, link: story.link, body: story.body)
    }

    /// Generates a contextual primer using raw fields.
    public func preparePrimer(title: String, link: String, body: String) -> PrimerReport {
        let text = title + " " + body
        let articleFreqs = TextUtilities.computeWordFrequencies(from: text, minimumLength: minimumConceptLength)
        let exposure = computeExposure()

        // Build familiarity map
        let familiarityMap = buildFamiliarityMap(articleFreqs: articleFreqs, exposure: exposure)

        // Compute readiness score
        let readinessScore = computeReadiness(familiarityMap: familiarityMap)
        let readinessLabel = labelForReadiness(readinessScore)

        // Identify blind spots
        let blindSpots = familiarityMap
            .filter { $0.familiarity == .unknown }
            .sorted { $0.articleFrequency > $1.articleFrequency }
            .prefix(maxBlindSpots)
            .map { $0.term }

        // Find background refreshers
        let refreshers = findRefreshers(articleConcepts: Set(articleFreqs.keys), link: link)

        // Build summary
        let summary = buildSummary(readinessScore: readinessScore, blindSpotCount: blindSpots.count,
                                   refresherCount: refreshers.count, totalConcepts: familiarityMap.count)

        return PrimerReport(
            targetTitle: title,
            targetLink: link,
            readinessScore: readinessScore,
            readinessLabel: readinessLabel,
            familiarityMap: familiarityMap,
            blindSpots: blindSpots,
            backgroundRefreshers: refreshers,
            summary: summary,
            generatedAt: Date()
        )
    }

    // MARK: - Reading Order

    /// Suggests an optimal reading order for a set of articles that builds
    /// knowledge progressively (concept scaffolding).
    ///
    /// Uses a greedy algorithm: at each step picks the article whose concepts
    /// are most already-known (from history + previously ordered articles),
    /// so each article builds on what came before.
    ///
    /// - Parameter stories: The articles to order.
    /// - Returns: Ordered list of `ReadingOrderItem` with scaffolding metadata.
    public func suggestReadingOrder(for stories: [RSSStory]) -> [ReadingOrderItem] {
        return suggestReadingOrder(articles: stories.map { (title: $0.title, link: $0.link, body: $0.body) })
    }

    /// Suggests reading order using raw article tuples.
    public func suggestReadingOrder(articles: [(title: String, link: String, body: String)]) -> [ReadingOrderItem] {
        guard !articles.isEmpty else { return [] }

        // Extract concepts for each article
        let articleConcepts: [(title: String, link: String, concepts: [String: Int])] = articles.map { a in
            let text = a.title + " " + a.body
            let freqs = TextUtilities.computeWordFrequencies(from: text, minimumLength: minimumConceptLength)
            return (title: a.title, link: a.link, concepts: freqs)
        }

        var knownConcepts = Set(computeExposure().keys)
        var remaining = Array(articleConcepts.enumerated())
        var ordered: [ReadingOrderItem] = []

        while !remaining.isEmpty {
            // Score each remaining article: what fraction of its concepts are already known?
            let scored = remaining.map { (idx, article) -> (index: Int, score: Double, item: (title: String, link: String, concepts: [String: Int])) in
                let totalConcepts = article.concepts.count
                guard totalConcepts > 0 else {
                    return (index: idx, score: 1.0, item: article)
                }
                let knownCount = article.concepts.keys.filter { knownConcepts.contains($0) }.count
                let score = Double(knownCount) / Double(totalConcepts)
                return (index: idx, score: score, item: article)
            }

            // Pick the article with the highest readiness (most concepts already known)
            let best = scored.max(by: { $0.score < $1.score })!

            // Concepts this article introduces (new to knownConcepts)
            let introduced = best.item.concepts.keys.filter { !knownConcepts.contains($0) }

            // Add to known concepts
            for concept in best.item.concepts.keys {
                knownConcepts.insert(concept)
            }

            let position = ordered.count + 1
            let cumulativeReadiness = min(100.0, best.score * 100.0)

            ordered.append(ReadingOrderItem(
                title: best.item.title,
                link: best.item.link,
                position: position,
                conceptsIntroduced: Array(introduced.sorted().prefix(10)),
                cumulativeReadiness: cumulativeReadiness
            ))

            remaining.removeAll { $0.offset == best.index }
        }

        return ordered
    }

    // MARK: - Persistence

    /// Exports reading history as JSON data for persistence.
    public func exportHistory() -> Data? {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return try? encoder.encode(history)
    }

    /// Imports reading history from JSON data.
    /// - Parameter data: JSON data previously exported.
    /// - Returns: Number of entries imported, or nil on failure.
    @discardableResult
    public func importHistory(from data: Data) -> Int? {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let entries = try? decoder.decode([ReadingHistoryEntry].self, from: data) else {
            return nil
        }
        history.append(contentsOf: entries)
        conceptExposureCache = nil
        return entries.count
    }

    // MARK: - Private Helpers

    /// Computes aggregated concept exposure with time decay.
    private func computeExposure() -> [String: Int] {
        if let cached = conceptExposureCache, let cDate = cacheDate,
           Date().timeIntervalSince(cDate) < 60 {
            return cached
        }

        let now = Date()
        var exposure: [String: Double] = [:]

        for entry in history {
            let ageDays = now.timeIntervalSince(entry.readAt) / 86400.0
            let periods = ageDays / Double(decayWindowDays)
            let decay = pow(decayFactor, periods)

            for (term, freq) in entry.concepts {
                exposure[term, default: 0] += Double(freq) * decay
            }
        }

        let intExposure = exposure.mapValues { Int(round($0)) }.filter { $0.value > 0 }
        conceptExposureCache = intExposure
        cacheDate = now
        return intExposure
    }

    /// Builds a familiarity map for an article's concepts.
    private func buildFamiliarityMap(articleFreqs: [String: Int], exposure: [String: Int]) -> [ConceptEntry] {
        return articleFreqs.map { (term, freq) in
            let historicalCount = exposure[term] ?? 0
            let familiarity: FamiliarityLevel
            switch historicalCount {
            case 0:       familiarity = .unknown
            case 1...2:   familiarity = .glimpsed
            case 3...7:   familiarity = .familiar
            default:      familiarity = .wellKnown
            }
            return ConceptEntry(term: term, articleFrequency: freq, historicalExposure: historicalCount, familiarity: familiarity)
        }.sorted { $0.articleFrequency > $1.articleFrequency }
    }

    /// Computes a readiness score (0–100) from the familiarity map.
    private func computeReadiness(familiarityMap: [ConceptEntry]) -> Int {
        guard !familiarityMap.isEmpty else { return 100 }

        // Weighted by article frequency: more frequent terms matter more
        var weightedSum = 0.0
        var totalWeight = 0.0
        for entry in familiarityMap {
            let weight = Double(entry.articleFrequency)
            weightedSum += entry.familiarity.weight * weight
            totalWeight += weight
        }

        let raw = totalWeight > 0 ? (weightedSum / totalWeight) * 100.0 : 0.0
        return min(100, max(0, Int(round(raw))))
    }

    /// Maps readiness score to a human-readable label.
    private func labelForReadiness(_ score: Int) -> String {
        switch score {
        case 80...100: return "Well Prepared"
        case 60..<80:  return "Mostly Ready"
        case 40..<60:  return "Some Gaps"
        case 20..<40:  return "Significant Gaps"
        default:       return "New Territory"
        }
    }

    /// Finds past articles related to the target article's concepts.
    private func findRefreshers(articleConcepts: Set<String>, link: String) -> [BackgroundRefresher] {
        guard !articleConcepts.isEmpty else { return [] }

        var refreshers: [BackgroundRefresher] = []

        for entry in history {
            // Skip the same article
            guard entry.link != link else { continue }

            let entryConcepts = Set(entry.concepts.keys)
            let shared = articleConcepts.intersection(entryConcepts)

            guard !shared.isEmpty else { continue }

            // Jaccard similarity
            let union = articleConcepts.union(entryConcepts)
            let relevance = Double(shared.count) / Double(union.count)

            guard relevance >= refresherThreshold else { continue }

            refreshers.append(BackgroundRefresher(
                title: entry.title,
                link: entry.link,
                relevanceScore: round(relevance * 1000) / 1000,
                sharedConcepts: Array(shared.sorted().prefix(8))
            ))
        }

        return refreshers
            .sorted { $0.relevanceScore > $1.relevanceScore }
            .prefix(maxRefreshers)
            .map { $0 }
    }

    /// Builds a human-readable summary.
    private func buildSummary(readinessScore: Int, blindSpotCount: Int,
                              refresherCount: Int, totalConcepts: Int) -> String {
        var parts: [String] = []

        parts.append("Knowledge readiness: \(readinessScore)/100 (\(labelForReadiness(readinessScore))).")

        if blindSpotCount > 0 {
            parts.append("\(blindSpotCount) concept\(blindSpotCount == 1 ? "" : "s") you haven't encountered before.")
        } else {
            parts.append("No blind spots — you've seen all the key concepts.")
        }

        if refresherCount > 0 {
            parts.append("\(refresherCount) related article\(refresherCount == 1 ? "" : "s") from your history for background.")
        }

        parts.append("Analyzed \(totalConcepts) significant concept\(totalConcepts == 1 ? "" : "s").")

        return parts.joined(separator: " ")
    }
}
