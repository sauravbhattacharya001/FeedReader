//
//  FeedBlindSpotDetector.swift
//  FeedReaderCore
//
//  Autonomous blind spot detection engine that identifies systematic
//  gaps in a user's reading habits — topics and domains adjacent to
//  their interests but consistently missing from their feeds.
//
//  Key capabilities:
//  - Coverage mapping across all ingested topics
//  - Adjacent topic discovery via keyword co-occurrence analysis
//  - Echo chamber detection using Shannon entropy per topic
//  - Temporal blind spot detection (abandoned topics, emerging misses)
//  - Depth imbalance analysis between related topic pairs
//  - Composite severity scoring 0-100 per blind spot
//  - Autonomous natural-language insights with recommendations
//  - Portfolio health scoring 0-100 with letter grades
//
//  Usage:
//  ```swift
//  let detector = FeedBlindSpotDetector()
//
//  detector.ingest(BlindSpotArticle(
//      id: "1", title: "Intro to ML",
//      topics: ["machine learning", "neural networks"],
//      feedURL: "https://blog.example.com/feed",
//      feedName: "Tech Blog",
//      readDate: Date(),
//      sourcePerspective: "tech"))
//
//  let report = detector.analyze()
//  print(report.healthScore)       // 0-100
//  print(report.blindSpots)        // detected gaps
//  print(report.insights)          // autonomous observations
//  ```
//
//  All processing is on-device. No network calls or external deps.
//

import Foundation

// MARK: - Blind Spot Category

/// Classification of a detected blind spot.
public enum BlindSpotCategory: String, CaseIterable, Comparable, Sendable {
    case adjacent       = "Adjacent Gap"
    case echoChamber    = "Echo Chamber"
    case temporal       = "Temporal Decay"
    case depthImbalance = "Depth Imbalance"
    case emerging       = "Emerging Miss"

    private var ordinal: Int {
        switch self {
        case .adjacent:       return 0
        case .echoChamber:    return 1
        case .temporal:       return 2
        case .depthImbalance: return 3
        case .emerging:       return 4
        }
    }

    public static func < (lhs: BlindSpotCategory, rhs: BlindSpotCategory) -> Bool {
        lhs.ordinal < rhs.ordinal
    }

    /// Emoji for display.
    public var emoji: String {
        switch self {
        case .adjacent:       return "🔗"
        case .echoChamber:    return "🔁"
        case .temporal:       return "⏳"
        case .depthImbalance: return "⚖️"
        case .emerging:       return "🌱"
        }
    }

    /// Base severity weight for scoring.
    public var baseSeverity: Double {
        switch self {
        case .echoChamber:    return 0.9
        case .emerging:       return 0.8
        case .adjacent:       return 0.6
        case .temporal:       return 0.5
        case .depthImbalance: return 0.4
        }
    }
}

// MARK: - Blind Spot Article

/// An article ingested for blind spot analysis.
public struct BlindSpotArticle: Sendable {
    /// Unique article identifier.
    public let id: String
    /// Article title.
    public let title: String
    /// Extracted topics/keywords.
    public let topics: [String]
    /// Feed URL.
    public let feedURL: String
    /// Feed display name.
    public let feedName: String
    /// When the article was read.
    public let readDate: Date
    /// Source perspective (e.g. "tech", "business", "science").
    public let sourcePerspective: String

    public init(id: String, title: String, topics: [String],
                feedURL: String, feedName: String,
                readDate: Date = Date(),
                sourcePerspective: String = "general") {
        self.id = id
        self.title = title
        self.topics = topics.map { $0.lowercased().trimmingCharacters(in: .whitespacesAndNewlines) }
        self.feedURL = feedURL
        self.feedName = feedName
        self.readDate = readDate
        self.sourcePerspective = sourcePerspective.lowercased()
    }
}

// MARK: - Blind Spot

/// A detected knowledge blind spot.
public struct BlindSpot: Sendable {
    /// The topic that represents the blind spot.
    public let topic: String
    /// Category of blind spot.
    public let category: BlindSpotCategory
    /// Severity score 0-100.
    public let severity: Double
    /// Known topics this connects to.
    public let adjacentTo: [String]
    /// Evidence/explanation.
    public let evidence: String
    /// Recommendation for the user.
    public let recommendation: String
    /// Suggested feed names/types.
    public let feedSuggestions: [String]

    public init(topic: String, category: BlindSpotCategory,
                severity: Double, adjacentTo: [String],
                evidence: String, recommendation: String,
                feedSuggestions: [String] = []) {
        self.topic = topic
        self.category = category
        self.severity = max(0, min(100, severity))
        self.adjacentTo = adjacentTo
        self.evidence = evidence
        self.recommendation = recommendation
        self.feedSuggestions = feedSuggestions
    }
}

// MARK: - Trending Topic

/// An externally reported trending topic.
public struct TrendingTopic: Sendable {
    public let topic: String
    public let mentionCount: Int
    public let timestamp: Date

    public init(topic: String, mentionCount: Int, timestamp: Date = Date()) {
        self.topic = topic.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        self.mentionCount = mentionCount
        self.timestamp = timestamp
    }
}

// MARK: - Blind Spot Report

/// Full analysis report from the blind spot detector.
public struct BlindSpotReport: Sendable {
    /// All detected blind spots, sorted by severity descending.
    public let blindSpots: [BlindSpot]
    /// Topic → article count coverage map.
    public let coverageMap: [String: Int]
    /// Topics with low source diversity (echo chambers).
    public let echoChamberTopics: [String]
    /// Previously read topics now neglected.
    public let abandonedTopics: [String]
    /// Trending topics the user hasn't engaged with.
    public let emergingMisses: [String]
    /// Portfolio health score 0-100 (higher = fewer blind spots).
    public let healthScore: Double
    /// Letter grade (A/B/C/D/F).
    public let grade: String
    /// Autonomous natural-language insights.
    public let insights: [String]
    /// Total distinct topics tracked.
    public let totalTopicsTracked: Int
    /// Total blind spots detected.
    public let totalBlindSpots: Int

    public init(blindSpots: [BlindSpot], coverageMap: [String: Int],
                echoChamberTopics: [String], abandonedTopics: [String],
                emergingMisses: [String], healthScore: Double,
                grade: String, insights: [String],
                totalTopicsTracked: Int, totalBlindSpots: Int) {
        self.blindSpots = blindSpots
        self.coverageMap = coverageMap
        self.echoChamberTopics = echoChamberTopics
        self.abandonedTopics = abandonedTopics
        self.emergingMisses = emergingMisses
        self.healthScore = healthScore
        self.grade = grade
        self.insights = insights
        self.totalTopicsTracked = totalTopicsTracked
        self.totalBlindSpots = totalBlindSpots
    }
}

// MARK: - Feed Blind Spot Detector

/// Autonomous blind spot detection engine for RSS reading portfolios.
public final class FeedBlindSpotDetector: @unchecked Sendable {

    // MARK: - Storage

    private var articles: [BlindSpotArticle] = []
    private var trendingTopics: [TrendingTopic] = []
    private var manualAdjacencies: [(String, String, Double)] = []
    private let lock = NSLock()

    // MARK: - Configuration

    /// Days without activity before a topic is considered abandoned.
    private let abandonmentThresholdDays: Double = 30
    /// Minimum articles before a topic can be flagged as abandoned.
    private let abandonmentMinArticles: Int = 5
    /// Shannon entropy threshold for echo chamber detection.
    private let echoChamberEntropyThreshold: Double = 0.5
    /// Minimum articles per topic to evaluate echo chamber status.
    private let echoChamberMinArticles: Int = 3
    /// Depth ratio threshold for imbalance detection.
    private let depthImbalanceRatio: Double = 3.0
    /// Minimum co-occurrence count to consider topics adjacent.
    private let adjacencyMinCooccurrence: Int = 2

    // MARK: - Init

    public init() {}

    // MARK: - Ingestion

    /// Ingest a single article.
    public func ingest(_ article: BlindSpotArticle) {
        lock.lock()
        defer { lock.unlock() }
        articles.append(article)
    }

    /// Ingest a batch of articles.
    public func ingestBatch(_ articles: [BlindSpotArticle]) {
        lock.lock()
        defer { lock.unlock() }
        self.articles.append(contentsOf: articles)
    }

    /// Register a manual adjacency between two topics.
    public func registerAdjacency(topic: String, adjacentTo: String, strength: Double = 1.0) {
        let t = topic.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        let a = adjacentTo.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        lock.lock()
        defer { lock.unlock() }
        manualAdjacencies.append((t, a, max(0, min(1, strength))))
    }

    /// Record a trending topic from an external signal.
    public func recordTrendingTopic(_ topic: String, mentionCount: Int, timestamp: Date = Date()) {
        lock.lock()
        defer { lock.unlock() }
        trendingTopics.append(TrendingTopic(topic: topic, mentionCount: mentionCount, timestamp: timestamp))
    }

    /// Reset all data.
    public func reset() {
        lock.lock()
        defer { lock.unlock() }
        articles.removeAll()
        trendingTopics.removeAll()
        manualAdjacencies.removeAll()
    }

    // MARK: - Analysis

    /// Run the full blind spot analysis.
    public func analyze() -> BlindSpotReport {
        lock.lock()
        let articlesCopy = articles
        let trendingCopy = trendingTopics
        let adjacenciesCopy = manualAdjacencies
        lock.unlock()

        guard !articlesCopy.isEmpty else {
            return BlindSpotReport(
                blindSpots: [], coverageMap: [:],
                echoChamberTopics: [], abandonedTopics: [],
                emergingMisses: [], healthScore: 100,
                grade: "A", insights: ["No articles ingested yet. Start reading to detect blind spots."],
                totalTopicsTracked: 0, totalBlindSpots: 0)
        }

        // Engine 1: Coverage Map
        let coverageMap = buildCoverageMap(articlesCopy)

        // Engine 2: Adjacent Topic Discovery
        let cooccurrence = buildCooccurrenceMatrix(articlesCopy)
        let adjacencyMap = buildAdjacencyMap(cooccurrence, manualAdjacencies: adjacenciesCopy)

        // Engine 3: Echo Chamber Detection
        let topicSourceMap = buildTopicSourceMap(articlesCopy)
        let echoChambers = detectEchoChambers(topicSourceMap)

        // Engine 4: Temporal Blind Spots
        let topicTimelines = buildTopicTimelines(articlesCopy)
        let abandoned = detectAbandonedTopics(topicTimelines, coverageMap: coverageMap)
        let emergingMisses = detectEmergingMisses(trendingCopy, coverageMap: coverageMap)

        // Engine 5: Depth Imbalance
        let depthImbalances = detectDepthImbalances(coverageMap, adjacencyMap: adjacencyMap)

        // Engine 6: Severity Scoring + Blind Spot Assembly
        var blindSpots: [BlindSpot] = []

        // Adjacent gaps
        let knownTopics = Set(coverageMap.keys)
        for (topic, adjacents) in adjacencyMap {
            if !knownTopics.contains(topic) {
                let knownAdj = adjacents.filter { knownTopics.contains($0.key) }
                if !knownAdj.isEmpty {
                    let avgStrength = knownAdj.values.reduce(0, +) / Double(knownAdj.count)
                    let crossFeedMentions = Double(knownAdj.keys.compactMap { coverageMap[$0] }.reduce(0, +))
                    let severity = computeSeverity(
                        adjacencyStrength: avgStrength,
                        importance: min(1.0, crossFeedMentions / 20.0),
                        gapDays: 0,
                        category: .adjacent)
                    let adjNames = Array(knownAdj.keys.prefix(5))
                    blindSpots.append(BlindSpot(
                        topic: topic,
                        category: .adjacent,
                        severity: severity,
                        adjacentTo: adjNames,
                        evidence: "Topic '\(topic)' co-occurs with \(adjNames.joined(separator: ", ")) but has no coverage in your reading.",
                        recommendation: "Explore '\(topic)' — it connects to topics you already follow.",
                        feedSuggestions: ["Search for feeds covering '\(topic)'"]))
                }
            }
        }

        // Echo chambers
        for topic in echoChambers {
            let sources = topicSourceMap[topic] ?? [:]
            let sourceCount = sources.count
            let entropy = shannonEntropy(sources)
            let severity = computeSeverity(
                adjacencyStrength: 0.5,
                importance: min(1.0, Double(coverageMap[topic] ?? 0) / 10.0),
                gapDays: 0,
                category: .echoChamber)
            blindSpots.append(BlindSpot(
                topic: topic,
                category: .echoChamber,
                severity: severity,
                adjacentTo: [],
                evidence: "\(coverageMap[topic] ?? 0) articles about '\(topic)' from only \(sourceCount) source(s) (entropy: \(String(format: "%.2f", entropy))).",
                recommendation: "Diversify your '\(topic)' sources — you're only getting one perspective.",
                feedSuggestions: ["Find alternative '\(topic)' feeds from different perspectives"]))
        }

        // Abandoned topics
        for topic in abandoned {
            let timeline = topicTimelines[topic]
            let lastSeen = timeline?.last ?? Date.distantPast
            let daysSince = Date().timeIntervalSince(lastSeen) / 86400
            let severity = computeSeverity(
                adjacencyStrength: 0.3,
                importance: min(1.0, Double(coverageMap[topic] ?? 0) / 10.0),
                gapDays: daysSince,
                category: .temporal)
            blindSpots.append(BlindSpot(
                topic: topic,
                category: .temporal,
                severity: severity,
                adjacentTo: [],
                evidence: "You read \(coverageMap[topic] ?? 0) articles about '\(topic)' but nothing in \(Int(daysSince)) days.",
                recommendation: "Revisit '\(topic)' — you used to follow this topic actively.",
                feedSuggestions: ["Check if your '\(topic)' feeds are still active"]))
        }

        // Emerging misses
        for topic in emergingMisses {
            let trending = trendingCopy.filter { $0.topic == topic }
            let totalMentions = trending.reduce(0) { $0 + $1.mentionCount }
            let severity = computeSeverity(
                adjacencyStrength: 0.5,
                importance: min(1.0, Double(totalMentions) / 50.0),
                gapDays: 0,
                category: .emerging)
            blindSpots.append(BlindSpot(
                topic: topic,
                category: .emerging,
                severity: severity,
                adjacentTo: [],
                evidence: "'\(topic)' has \(totalMentions) trending mentions but zero coverage in your reading.",
                recommendation: "'\(topic)' is trending — consider adding a feed to stay current.",
                feedSuggestions: ["Subscribe to a '\(topic)' focused feed"]))
        }

        // Depth imbalances
        for (shallowTopic, deepTopic, ratio) in depthImbalances {
            let severity = computeSeverity(
                adjacencyStrength: min(1.0, ratio / 10.0),
                importance: min(1.0, Double(coverageMap[deepTopic] ?? 0) / 15.0),
                gapDays: 0,
                category: .depthImbalance)
            blindSpots.append(BlindSpot(
                topic: shallowTopic,
                category: .depthImbalance,
                severity: severity,
                adjacentTo: [deepTopic],
                evidence: "'\(deepTopic)' has \(coverageMap[deepTopic] ?? 0) articles vs '\(shallowTopic)' with \(coverageMap[shallowTopic] ?? 0) (ratio \(String(format: "%.1f", ratio)):1).",
                recommendation: "Balance your reading — '\(shallowTopic)' is related to '\(deepTopic)' but underexplored.",
                feedSuggestions: ["Find deeper '\(shallowTopic)' content"]))
        }

        // Sort by severity descending
        blindSpots.sort { $0.severity > $1.severity }

        // Engine 7: Health Score & Insights
        let healthScore = computeHealthScore(
            blindSpotCount: blindSpots.count,
            echoChamberCount: echoChambers.count,
            abandonedCount: abandoned.count)
        let grade = letterGrade(healthScore)
        let insights = generateInsights(
            blindSpots: blindSpots,
            coverageMap: coverageMap,
            echoChambers: echoChambers,
            abandoned: abandoned,
            emergingMisses: emergingMisses,
            depthImbalances: depthImbalances,
            healthScore: healthScore)

        return BlindSpotReport(
            blindSpots: blindSpots,
            coverageMap: coverageMap,
            echoChamberTopics: echoChambers,
            abandonedTopics: abandoned,
            emergingMisses: emergingMisses,
            healthScore: healthScore,
            grade: grade,
            insights: insights,
            totalTopicsTracked: coverageMap.count,
            totalBlindSpots: blindSpots.count)
    }

    /// Get the coverage map (topic → article count).
    public func getCoverageMap() -> [String: Int] {
        lock.lock()
        let articlesCopy = articles
        lock.unlock()
        return buildCoverageMap(articlesCopy)
    }

    /// Check if a specific topic is a blind spot.
    public func isBlindSpot(_ topic: String) -> Bool {
        let normalized = topic.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        let report = analyze()
        return report.blindSpots.contains { $0.topic == normalized }
    }

    // MARK: - Engine 1: Coverage Map

    private func buildCoverageMap(_ articles: [BlindSpotArticle]) -> [String: Int] {
        var map: [String: Int] = [:]
        for article in articles {
            for topic in article.topics {
                map[topic, default: 0] += 1
            }
        }
        return map
    }

    // MARK: - Engine 2: Co-occurrence & Adjacency

    private func buildCooccurrenceMatrix(_ articles: [BlindSpotArticle]) -> [String: [String: Int]] {
        var matrix: [String: [String: Int]] = [:]
        for article in articles {
            let topics = Array(Set(article.topics))
            for i in 0..<topics.count {
                for j in (i + 1)..<topics.count {
                    let a = topics[i]
                    let b = topics[j]
                    matrix[a, default: [:]][b, default: 0] += 1
                    matrix[b, default: [:]][a, default: 0] += 1
                }
            }
        }
        return matrix
    }

    private func buildAdjacencyMap(
        _ cooccurrence: [String: [String: Int]],
        manualAdjacencies: [(String, String, Double)]
    ) -> [String: [String: Double]] {
        var adjacency: [String: [String: Double]] = [:]

        // From co-occurrence
        for (topic, neighbors) in cooccurrence {
            for (neighbor, count) in neighbors {
                if count >= adjacencyMinCooccurrence {
                    let strength = min(1.0, Double(count) / 10.0)
                    adjacency[topic, default: [:]][neighbor] = max(
                        adjacency[topic]?[neighbor] ?? 0, strength)
                    adjacency[neighbor, default: [:]][topic] = max(
                        adjacency[neighbor]?[topic] ?? 0, strength)
                }
            }
        }

        // From manual registrations
        for (a, b, strength) in manualAdjacencies {
            adjacency[a, default: [:]][b] = max(adjacency[a]?[b] ?? 0, strength)
            adjacency[b, default: [:]][a] = max(adjacency[b]?[a] ?? 0, strength)
        }

        return adjacency
    }

    // MARK: - Engine 3: Echo Chamber Detection

    private func buildTopicSourceMap(_ articles: [BlindSpotArticle]) -> [String: [String: Int]] {
        var map: [String: [String: Int]] = [:]
        for article in articles {
            for topic in article.topics {
                map[topic, default: [:]][article.feedName, default: 0] += 1
            }
        }
        return map
    }

    private func detectEchoChambers(_ topicSourceMap: [String: [String: Int]]) -> [String] {
        var echoChambers: [String] = []
        for (topic, sources) in topicSourceMap {
            let totalArticles = sources.values.reduce(0, +)
            guard totalArticles >= echoChamberMinArticles else { continue }
            let entropy = shannonEntropy(sources)
            if entropy < echoChamberEntropyThreshold {
                echoChambers.append(topic)
            }
        }
        return echoChambers.sorted()
    }

    private func shannonEntropy(_ distribution: [String: Int]) -> Double {
        let total = Double(distribution.values.reduce(0, +))
        guard total > 0 else { return 0 }
        var entropy = 0.0
        for (_, count) in distribution {
            let p = Double(count) / total
            if p > 0 {
                entropy -= p * log(p)
            }
        }
        return entropy
    }

    // MARK: - Engine 4: Temporal Blind Spots

    private func buildTopicTimelines(_ articles: [BlindSpotArticle]) -> [String: [Date]] {
        var timelines: [String: [Date]] = [:]
        for article in articles {
            for topic in article.topics {
                timelines[topic, default: []].append(article.readDate)
            }
        }
        // Sort each timeline
        for key in timelines.keys {
            timelines[key]?.sort()
        }
        return timelines
    }

    private func detectAbandonedTopics(
        _ timelines: [String: [Date]],
        coverageMap: [String: Int]
    ) -> [String] {
        let now = Date()
        var abandoned: [String] = []
        for (topic, dates) in timelines {
            guard let lastDate = dates.last else { continue }
            let articleCount = coverageMap[topic] ?? 0
            guard articleCount >= abandonmentMinArticles else { continue }
            let daysSince = now.timeIntervalSince(lastDate) / 86400
            if daysSince >= abandonmentThresholdDays {
                abandoned.append(topic)
            }
        }
        return abandoned.sorted()
    }

    private func detectEmergingMisses(
        _ trending: [TrendingTopic],
        coverageMap: [String: Int]
    ) -> [String] {
        var trendingSet: Set<String> = []
        for t in trending {
            trendingSet.insert(t.topic)
        }
        let coveredTopics = Set(coverageMap.keys)
        let misses = trendingSet.subtracting(coveredTopics)
        return Array(misses).sorted()
    }

    // MARK: - Engine 5: Depth Imbalance

    private func detectDepthImbalances(
        _ coverageMap: [String: Int],
        adjacencyMap: [String: [String: Double]]
    ) -> [(String, String, Double)] {
        var imbalances: [(String, String, Double)] = []
        var seen: Set<String> = []

        for (topic, neighbors) in adjacencyMap {
            guard let topicCount = coverageMap[topic], topicCount > 0 else { continue }
            for (neighbor, _) in neighbors {
                guard let neighborCount = coverageMap[neighbor], neighborCount > 0 else { continue }
                let pairKey = [topic, neighbor].sorted().joined(separator: "|")
                guard !seen.contains(pairKey) else { continue }
                seen.insert(pairKey)

                let ratio = Double(max(topicCount, neighborCount)) / Double(min(topicCount, neighborCount))
                if ratio >= depthImbalanceRatio {
                    let shallow = topicCount < neighborCount ? topic : neighbor
                    let deep = topicCount >= neighborCount ? topic : neighbor
                    imbalances.append((shallow, deep, ratio))
                }
            }
        }

        return imbalances.sorted { $0.2 > $1.2 }
    }

    // MARK: - Engine 6: Severity Scoring

    private func computeSeverity(
        adjacencyStrength: Double,
        importance: Double,
        gapDays: Double,
        category: BlindSpotCategory
    ) -> Double {
        let normalizedGap = min(1.0, gapDays / 90.0)
        let raw = adjacencyStrength * 0.3
            + importance * 0.3
            + normalizedGap * 0.2
            + category.baseSeverity * 0.2
        return min(100, max(0, raw * 100))
    }

    // MARK: - Health Score

    private func computeHealthScore(
        blindSpotCount: Int,
        echoChamberCount: Int,
        abandonedCount: Int
    ) -> Double {
        let penalty = Double(blindSpotCount) * 5.0
            + Double(echoChamberCount) * 8.0
            + Double(abandonedCount) * 3.0
        return max(0, min(100, 100 - penalty))
    }

    private func letterGrade(_ score: Double) -> String {
        switch score {
        case 85...100: return "A"
        case 70..<85:  return "B"
        case 55..<70:  return "C"
        case 40..<55:  return "D"
        default:       return "F"
        }
    }

    // MARK: - Engine 7: Insight Generator

    private func generateInsights(
        blindSpots: [BlindSpot],
        coverageMap: [String: Int],
        echoChambers: [String],
        abandoned: [String],
        emergingMisses: [String],
        depthImbalances: [(String, String, Double)],
        healthScore: Double
    ) -> [String] {
        var insights: [String] = []

        // Overall health
        let grade = letterGrade(healthScore)
        insights.append("Your reading portfolio health is \(grade) (\(String(format: "%.0f", healthScore))/100) with \(blindSpots.count) blind spot(s) detected.")

        // Coverage breadth
        let topicCount = coverageMap.count
        if topicCount < 5 {
            insights.append("Very narrow reading — only \(topicCount) topic(s) tracked. Consider broadening your subscriptions.")
        } else if topicCount > 20 {
            insights.append("Broad coverage across \(topicCount) topics — good information diversity.")
        }

        // Echo chambers
        if !echoChambers.isEmpty {
            let topEcho = echoChambers.prefix(3).joined(separator: ", ")
            insights.append("Echo chamber warning: topics [\(topEcho)] have very low source diversity. You're seeing only one perspective.")
        }

        // Abandoned topics
        if !abandoned.isEmpty {
            let topAbandoned = abandoned.prefix(3).joined(separator: ", ")
            insights.append("You've drifted away from: \(topAbandoned). These were once active interests worth revisiting.")
        }

        // Emerging misses
        if !emergingMisses.isEmpty {
            let topEmerging = emergingMisses.prefix(3).joined(separator: ", ")
            insights.append("Trending topics you're missing: \(topEmerging). These are gaining traction but not in your feeds.")
        }

        // Depth imbalances
        if !depthImbalances.isEmpty {
            let (shallow, deep, ratio) = depthImbalances[0]
            insights.append("Depth imbalance: '\(deep)' has \(String(format: "%.0f", ratio))x more coverage than related topic '\(shallow)'.")
        }

        // Adjacent gaps (top severity)
        let adjacentGaps = blindSpots.filter { $0.category == .adjacent }
        if let top = adjacentGaps.first {
            insights.append("Top adjacent gap: '\(top.topic)' connects to your interests but has zero coverage. Severity: \(String(format: "%.0f", top.severity)).")
        }

        // Positive signals
        if blindSpots.isEmpty {
            insights.append("Excellent! No significant blind spots detected. Your reading diet is well-balanced.")
        }

        return insights
    }
}
