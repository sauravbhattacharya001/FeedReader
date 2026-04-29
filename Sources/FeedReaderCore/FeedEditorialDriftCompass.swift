//
//  FeedEditorialDriftCompass.swift
//  FeedReaderCore
//
//  Autonomous editorial drift detection engine that monitors feed sources
//  for silent topic shifts. Detects when a feed's content diverges from its
//  established editorial identity — e.g., a tech blog starts covering politics,
//  or a science feed drifts toward opinion pieces.
//
//  Key capabilities:
//  - Builds editorial identity profiles from historical article topics
//  - Detects gradual topic proportion changes via sliding windows
//  - Classifies drift types: topic invasion, identity erosion, pivot, dilution
//  - Calculates drift velocity and acceleration (how fast is it changing?)
//  - Predicts future identity state if drift continues
//  - Generates subscriber-aligned relevance warnings
//
//  Usage:
//  ```swift
//  let compass = FeedEditorialDriftCompass()
//
//  // Record articles over time
//  compass.ingestArticle(feedURL: "https://techblog.com/feed",
//                        title: "New iPhone Review",
//                        topics: ["technology", "mobile", "apple"])
//
//  // Analyze drift for a feed
//  let report = compass.analyzeDrift(feedURL: "https://techblog.com/feed")
//  print(report.driftScore)         // 0-100 how much it has drifted
//  print(report.driftType)          // .topicInvasion, .identityErosion, etc.
//  print(report.invadingTopics)     // topics that weren't part of identity
//  print(report.erodingTopics)      // original topics that are fading
//  print(report.prediction)         // projected identity in 30 days
//  ```
//
//  All processing is on-device. No network calls.
//

import Foundation

// MARK: - Drift Type Classification

/// Type of editorial drift detected in a feed.
public enum EditorialDriftType: String, CaseIterable, Sendable {
    /// New topics are invading the feed's established domain.
    case topicInvasion = "topic_invasion"
    /// Original core topics are gradually disappearing.
    case identityErosion = "identity_erosion"
    /// Feed is deliberately pivoting to a new domain.
    case pivot = "pivot"
    /// Feed is diluting focus by adding too many tangential topics.
    case dilution = "dilution"
    /// Feed maintains its editorial identity.
    case stable = "stable"
    /// Not enough data to assess.
    case insufficient = "insufficient_data"

    /// Human-readable description.
    public var description: String {
        switch self {
        case .topicInvasion: return "New topics are appearing that weren't part of this feed's identity"
        case .identityErosion: return "Core topics that defined this feed are fading away"
        case .pivot: return "This feed appears to be pivoting to a different focus area"
        case .dilution: return "Feed is losing focus by covering too many unrelated topics"
        case .stable: return "Feed maintains consistent editorial identity"
        case .insufficient: return "Not enough history to assess drift"
        }
    }

    /// Emoji for display.
    public var emoji: String {
        switch self {
        case .topicInvasion: return "🚨"
        case .identityErosion: return "🌊"
        case .pivot: return "↪️"
        case .dilution: return "💨"
        case .stable: return "✅"
        case .insufficient: return "❓"
        }
    }
}

// MARK: - Drift Severity

/// How severe the detected drift is.
public enum DriftSeverity: String, Comparable, CaseIterable, Sendable {
    case none = "none"
    case mild = "mild"
    case moderate = "moderate"
    case significant = "significant"
    case extreme = "extreme"

    private var order: Int {
        switch self {
        case .none: return 0
        case .mild: return 1
        case .moderate: return 2
        case .significant: return 3
        case .extreme: return 4
        }
    }

    public static func < (lhs: DriftSeverity, rhs: DriftSeverity) -> Bool {
        lhs.order < rhs.order
    }
}

// MARK: - Topic Observation

/// A single topic observation from an article at a point in time.
public struct TopicObservation: Sendable {
    /// The topic/category detected.
    public let topic: String
    /// When this observation was recorded.
    public let timestamp: Date
    /// Confidence that the article belongs to this topic (0.0-1.0).
    public let confidence: Double

    public init(topic: String, timestamp: Date, confidence: Double = 1.0) {
        self.topic = topic.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        self.timestamp = timestamp
        self.confidence = min(1.0, max(0.0, confidence))
    }
}

// MARK: - Editorial Identity

/// Captures the editorial identity of a feed based on historical topic distribution.
public struct EditorialIdentity: Sendable {
    /// Feed URL this identity belongs to.
    public let feedURL: String
    /// Core topics that define this feed (topic → proportion 0.0-1.0).
    public let coreTopics: [String: Double]
    /// When this identity was established (first observation).
    public let establishedDate: Date
    /// Number of articles used to build this identity.
    public let articleCount: Int
    /// Shannon entropy of the topic distribution (higher = more diverse).
    public let topicEntropy: Double
    /// Top N topics that form the feed's "brand".
    public let brandTopics: [String]

    /// How focused this feed is (0.0 = scattered, 1.0 = single-topic).
    public var focusScore: Double {
        guard !coreTopics.isEmpty else { return 0.0 }
        let maxPossibleEntropy = log2(Double(coreTopics.count))
        guard maxPossibleEntropy > 0 else { return 1.0 }
        return 1.0 - (topicEntropy / maxPossibleEntropy)
    }
}

// MARK: - Drift Vector

/// Represents the direction and magnitude of editorial drift.
public struct DriftVector: Sendable {
    /// Topic being affected.
    public let topic: String
    /// Change in proportion from baseline (-1.0 to 1.0).
    public let delta: Double
    /// Whether this topic is growing or shrinking in the feed.
    public let direction: DriftDirection
    /// Speed of change (delta per day).
    public let velocity: Double

    public enum DriftDirection: String, Sendable {
        case growing = "growing"
        case shrinking = "shrinking"
        case stable = "stable"
    }
}

// MARK: - Drift Report

/// Complete drift analysis report for a feed.
public struct EditorialDriftReport: Sendable {
    /// Feed URL analyzed.
    public let feedURL: String
    /// Feed name (if known).
    public let feedName: String?
    /// Overall drift score (0 = no drift, 100 = completely different feed).
    public let driftScore: Int
    /// Classification of the drift type.
    public let driftType: EditorialDriftType
    /// Severity level.
    public let severity: DriftSeverity
    /// The feed's established editorial identity.
    public let identity: EditorialIdentity
    /// Individual topic drift vectors (sorted by absolute delta).
    public let driftVectors: [DriftVector]
    /// Topics that are new/invading the feed.
    public let invadingTopics: [String]
    /// Original brand topics that are eroding.
    public let erodingTopics: [String]
    /// Predicted dominant topics in 30 days if drift continues.
    public let predictedTopics: [String: Double]
    /// Days until the feed's identity is unrecognizable (nil if stable).
    public let daysUntilIdentityLoss: Int?
    /// Human-readable summary.
    public let summary: String
    /// Actionable recommendations for the subscriber.
    public let recommendations: [String]
    /// When this report was generated.
    public let generatedAt: Date
}

// MARK: - Fleet Drift Report

/// Drift analysis across all monitored feeds.
public struct FleetDriftReport: Sendable {
    /// Individual feed reports sorted by drift score (highest first).
    public let feedReports: [EditorialDriftReport]
    /// Number of feeds with significant drift.
    public let driftingFeedCount: Int
    /// Number of stable feeds.
    public let stableFeedCount: Int
    /// Overall subscription health score (0-100).
    public let subscriptionHealthScore: Int
    /// Feeds recommended for review/unsubscribe.
    public let reviewCandidates: [String]
    /// When this report was generated.
    public let generatedAt: Date
}

// MARK: - Feed Editorial Drift Compass

/// Autonomous engine that monitors feeds for editorial drift.
public final class FeedEditorialDriftCompass: @unchecked Sendable {

    // MARK: - Configuration

    /// Minimum articles needed to establish an identity.
    public var minimumIdentityArticles: Int = 10

    /// Number of days for the baseline identity window.
    public var identityWindowDays: Int = 60

    /// Number of days for the recent comparison window.
    public var recentWindowDays: Int = 14

    /// Threshold for considering a topic "core" (minimum proportion).
    public var coreTopicThreshold: Double = 0.10

    /// Drift score threshold for "significant" severity.
    public var significantDriftThreshold: Int = 50

    // MARK: - Storage

    /// All topic observations per feed URL.
    private var observations: [String: [TopicObservation]] = [:]

    /// Feed name lookup.
    private var feedNames: [String: String] = [:]

    /// Lock for thread safety.
    private let lock = NSLock()

    // MARK: - Initialization

    public init() {}

    // MARK: - Ingestion

    /// Record article topics for a feed.
    /// - Parameters:
    ///   - feedURL: The feed's URL identifier.
    ///   - feedName: Optional display name.
    ///   - title: Article title (used for topic extraction if topics are empty).
    ///   - topics: Detected topics/categories for this article.
    ///   - timestamp: When the article was published (defaults to now).
    public func ingestArticle(
        feedURL: String,
        feedName: String? = nil,
        title: String = "",
        topics: [String],
        timestamp: Date = Date()
    ) {
        let normalizedURL = feedURL.lowercased()
        let effectiveTopics = topics.isEmpty ? extractTopicsFromTitle(title) : topics

        lock.lock()
        defer { lock.unlock() }

        if let name = feedName {
            feedNames[normalizedURL] = name
        }

        var feedObs = observations[normalizedURL] ?? []
        for topic in effectiveTopics {
            feedObs.append(TopicObservation(topic: topic, timestamp: timestamp))
        }
        observations[normalizedURL] = feedObs
    }

    /// Ingest a batch of articles for a feed.
    public func ingestBatch(
        feedURL: String,
        feedName: String? = nil,
        articles: [(title: String, topics: [String], timestamp: Date)]
    ) {
        for article in articles {
            ingestArticle(
                feedURL: feedURL,
                feedName: feedName,
                title: article.title,
                topics: article.topics,
                timestamp: article.timestamp
            )
        }
    }

    // MARK: - Analysis

    /// Analyze editorial drift for a specific feed.
    /// - Parameter feedURL: The feed to analyze.
    /// - Returns: A complete drift report, or nil if the feed has no observations.
    public func analyzeDrift(feedURL: String) -> EditorialDriftReport? {
        let normalizedURL = feedURL.lowercased()

        lock.lock()
        let feedObs = observations[normalizedURL] ?? []
        let name = feedNames[normalizedURL]
        lock.unlock()

        guard !feedObs.isEmpty else { return nil }

        // Build identity from baseline window
        let identity = buildIdentity(feedURL: normalizedURL, observations: feedObs)

        // If insufficient data, return early
        guard identity.articleCount >= minimumIdentityArticles else {
            return EditorialDriftReport(
                feedURL: normalizedURL,
                feedName: name,
                driftScore: 0,
                driftType: .insufficient,
                severity: .none,
                identity: identity,
                driftVectors: [],
                invadingTopics: [],
                erodingTopics: [],
                predictedTopics: [:],
                daysUntilIdentityLoss: nil,
                summary: "Not enough articles to assess drift (have \(identity.articleCount), need \(minimumIdentityArticles)).",
                recommendations: ["Keep reading — more data needed for drift analysis."],
                generatedAt: Date()
            )
        }

        // Get recent topic distribution
        let recentDistribution = computeRecentDistribution(observations: feedObs)

        // Compute drift vectors
        let vectors = computeDriftVectors(
            baseline: identity.coreTopics,
            recent: recentDistribution,
            observations: feedObs
        )

        // Classify drift
        let (driftType, driftScore) = classifyDrift(
            identity: identity,
            recentDistribution: recentDistribution,
            vectors: vectors
        )

        let severity = classifySeverity(score: driftScore)

        // Find invading and eroding topics
        let invading = vectors
            .filter { $0.direction == .growing && !identity.brandTopics.contains($0.topic) }
            .map { $0.topic }

        let eroding = vectors
            .filter { $0.direction == .shrinking && identity.brandTopics.contains($0.topic) }
            .map { $0.topic }

        // Predict future state
        let predicted = predictFutureTopics(
            current: recentDistribution,
            vectors: vectors,
            daysAhead: 30
        )

        // Estimate days until identity loss
        let daysUntilLoss = estimateDaysUntilIdentityLoss(
            driftScore: driftScore,
            vectors: vectors
        )

        // Generate summary and recommendations
        let summary = generateSummary(
            feedName: name ?? normalizedURL,
            driftType: driftType,
            driftScore: driftScore,
            invading: invading,
            eroding: eroding
        )

        let recommendations = generateRecommendations(
            driftType: driftType,
            severity: severity,
            invading: invading,
            eroding: eroding
        )

        return EditorialDriftReport(
            feedURL: normalizedURL,
            feedName: name,
            driftScore: driftScore,
            driftType: driftType,
            severity: severity,
            identity: identity,
            driftVectors: vectors,
            invadingTopics: invading,
            erodingTopics: eroding,
            predictedTopics: predicted,
            daysUntilIdentityLoss: daysUntilLoss,
            summary: summary,
            recommendations: recommendations,
            generatedAt: Date()
        )
    }

    /// Analyze drift across all monitored feeds.
    public func analyzeFleet() -> FleetDriftReport {
        lock.lock()
        let allURLs = Array(observations.keys)
        lock.unlock()

        let reports = allURLs.compactMap { analyzeDrift(feedURL: $0) }
            .sorted { $0.driftScore > $1.driftScore }

        let drifting = reports.filter { $0.severity >= .moderate }.count
        let stable = reports.filter { $0.driftType == .stable }.count

        let healthScore: Int
        if reports.isEmpty {
            healthScore = 100
        } else {
            let avgDrift = reports.map { Double($0.driftScore) }.reduce(0, +) / Double(reports.count)
            healthScore = max(0, min(100, 100 - Int(avgDrift)))
        }

        let reviewCandidates = reports
            .filter { $0.severity >= .significant }
            .map { $0.feedName ?? $0.feedURL }

        return FleetDriftReport(
            feedReports: reports,
            driftingFeedCount: drifting,
            stableFeedCount: stable,
            subscriptionHealthScore: healthScore,
            reviewCandidates: reviewCandidates,
            generatedAt: Date()
        )
    }

    /// Get the current editorial identity for a feed.
    public func getIdentity(feedURL: String) -> EditorialIdentity? {
        let normalizedURL = feedURL.lowercased()
        lock.lock()
        let feedObs = observations[normalizedURL] ?? []
        lock.unlock()
        guard !feedObs.isEmpty else { return nil }
        return buildIdentity(feedURL: normalizedURL, observations: feedObs)
    }

    /// Get all monitored feed URLs.
    public var monitoredFeeds: [String] {
        lock.lock()
        defer { lock.unlock() }
        return Array(observations.keys)
    }

    /// Total observations recorded.
    public var totalObservations: Int {
        lock.lock()
        defer { lock.unlock() }
        return observations.values.map { $0.count }.reduce(0, +)
    }

    /// Clear all data for a feed.
    public func clearFeed(feedURL: String) {
        let normalizedURL = feedURL.lowercased()
        lock.lock()
        observations.removeValue(forKey: normalizedURL)
        feedNames.removeValue(forKey: normalizedURL)
        lock.unlock()
    }

    /// Clear all data.
    public func clearAll() {
        lock.lock()
        observations.removeAll()
        feedNames.removeAll()
        lock.unlock()
    }

    // MARK: - Private: Identity Building

    private func buildIdentity(feedURL: String, observations: [TopicObservation]) -> EditorialIdentity {
        // Use the earlier portion of data as the baseline identity
        let sorted = observations.sorted { $0.timestamp < $1.timestamp }

        let baselineEnd: Date
        if let first = sorted.first {
            baselineEnd = first.timestamp.addingTimeInterval(Double(identityWindowDays) * 86400)
        } else {
            baselineEnd = Date()
        }

        let baselineObs = sorted.filter { $0.timestamp <= baselineEnd }
        let effectiveObs = baselineObs.isEmpty ? sorted : baselineObs

        // Compute topic distribution
        let distribution = computeDistribution(from: effectiveObs)

        // Compute Shannon entropy
        let entropy = computeEntropy(distribution: distribution)

        // Identify brand topics (above threshold, sorted by proportion)
        let brandTopics = distribution
            .filter { $0.value >= coreTopicThreshold }
            .sorted { $0.value > $1.value }
            .map { $0.key }

        // Article count = unique timestamps (roughly)
        let uniqueTimestamps = Set(effectiveObs.map { Int($0.timestamp.timeIntervalSince1970 / 60) })

        return EditorialIdentity(
            feedURL: feedURL,
            coreTopics: distribution,
            establishedDate: sorted.first?.timestamp ?? Date(),
            articleCount: uniqueTimestamps.count,
            topicEntropy: entropy,
            brandTopics: brandTopics
        )
    }

    // MARK: - Private: Distribution Computing

    private func computeDistribution(from observations: [TopicObservation]) -> [String: Double] {
        var counts: [String: Double] = [:]
        for obs in observations {
            counts[obs.topic, default: 0] += obs.confidence
        }
        let total = counts.values.reduce(0, +)
        guard total > 0 else { return [:] }
        return counts.mapValues { $0 / total }
    }

    private func computeRecentDistribution(observations: [TopicObservation]) -> [String: Double] {
        let cutoff = Date().addingTimeInterval(-Double(recentWindowDays) * 86400)
        let recentObs = observations.filter { $0.timestamp > cutoff }

        // If no recent observations, use the last 25% of observations
        let effectiveObs: [TopicObservation]
        if recentObs.isEmpty {
            let sorted = observations.sorted { $0.timestamp < $1.timestamp }
            let startIndex = sorted.count * 3 / 4
            effectiveObs = Array(sorted[startIndex...])
        } else {
            effectiveObs = recentObs
        }

        return computeDistribution(from: effectiveObs)
    }

    // MARK: - Private: Drift Computation

    private func computeDriftVectors(
        baseline: [String: Double],
        recent: [String: Double],
        observations: [TopicObservation]
    ) -> [DriftVector] {
        let allTopics = Set(baseline.keys).union(recent.keys)
        let timeSpanDays = computeTimeSpanDays(observations: observations)

        return allTopics.map { topic in
            let baselineVal = baseline[topic] ?? 0.0
            let recentVal = recent[topic] ?? 0.0
            let delta = recentVal - baselineVal

            let direction: DriftVector.DriftDirection
            if abs(delta) < 0.03 {
                direction = .stable
            } else if delta > 0 {
                direction = .growing
            } else {
                direction = .shrinking
            }

            let velocity = timeSpanDays > 0 ? delta / timeSpanDays : 0.0

            return DriftVector(
                topic: topic,
                delta: delta,
                direction: direction,
                velocity: velocity
            )
        }
        .sorted { abs($0.delta) > abs($1.delta) }
    }

    private func computeTimeSpanDays(observations: [TopicObservation]) -> Double {
        guard let first = observations.min(by: { $0.timestamp < $1.timestamp }),
              let last = observations.max(by: { $0.timestamp < $1.timestamp }) else {
            return 1.0
        }
        let days = last.timestamp.timeIntervalSince(first.timestamp) / 86400
        return max(1.0, days)
    }

    // MARK: - Private: Classification

    private func classifyDrift(
        identity: EditorialIdentity,
        recentDistribution: [String: Double],
        vectors: [DriftVector]
    ) -> (EditorialDriftType, Int) {

        let growingNonCore = vectors.filter {
            $0.direction == .growing && !identity.brandTopics.contains($0.topic)
        }
        let shrinkingCore = vectors.filter {
            $0.direction == .shrinking && identity.brandTopics.contains($0.topic)
        }

        // Compute Jensen-Shannon divergence as drift score
        let jsd = jensenShannonDivergence(p: identity.coreTopics, q: recentDistribution)
        let rawScore = Int(min(100, jsd * 200)) // Scale 0.0-0.5 → 0-100

        // Classify type based on what's happening
        let type: EditorialDriftType
        if rawScore < 15 {
            type = .stable
        } else if !growingNonCore.isEmpty && shrinkingCore.isEmpty {
            // New topics arriving but core intact → invasion
            type = .topicInvasion
        } else if growingNonCore.isEmpty && !shrinkingCore.isEmpty {
            // Core fading but nothing replacing it specifically → erosion
            type = .identityErosion
        } else if !growingNonCore.isEmpty && !shrinkingCore.isEmpty {
            // Both growing new + shrinking core
            let totalGrowth = growingNonCore.map { $0.delta }.reduce(0, +)
            let totalShrink = shrinkingCore.map { abs($0.delta) }.reduce(0, +)
            if totalGrowth > 0.3 && totalShrink > 0.3 {
                type = .pivot
            } else {
                type = .dilution
            }
        } else {
            // Many small shifts without clear direction
            let recentEntropy = computeEntropy(distribution: recentDistribution)
            if recentEntropy > identity.topicEntropy * 1.5 {
                type = .dilution
            } else {
                type = .stable
            }
        }

        return (type, rawScore)
    }

    private func classifySeverity(score: Int) -> DriftSeverity {
        switch score {
        case 0..<15: return .none
        case 15..<30: return .mild
        case 30..<50: return .moderate
        case 50..<75: return .significant
        default: return .extreme
        }
    }

    // MARK: - Private: Prediction

    private func predictFutureTopics(
        current: [String: Double],
        vectors: [DriftVector],
        daysAhead: Int
    ) -> [String: Double] {
        var predicted = current
        for vector in vectors {
            let projectedDelta = vector.velocity * Double(daysAhead)
            predicted[vector.topic, default: 0] += projectedDelta
        }

        // Normalize and clamp
        let total = predicted.values.filter { $0 > 0 }.reduce(0, +)
        guard total > 0 else { return current }
        return predicted
            .filter { $0.value > 0 }
            .mapValues { max(0, $0 / total) }
    }

    private func estimateDaysUntilIdentityLoss(
        driftScore: Int,
        vectors: [DriftVector]
    ) -> Int? {
        guard driftScore > 15 else { return nil }

        // Estimate based on current velocity how long until score reaches 80
        let maxVelocity = vectors.map { abs($0.velocity) }.max() ?? 0.0
        guard maxVelocity > 0.001 else { return nil }

        let remainingDrift = Double(80 - driftScore) / 100.0
        let daysEstimate = Int(remainingDrift / maxVelocity)
        return max(1, min(365, daysEstimate))
    }

    // MARK: - Private: Information Theory

    private func computeEntropy(distribution: [String: Double]) -> Double {
        let values = distribution.values.filter { $0 > 0 }
        guard !values.isEmpty else { return 0.0 }
        return -values.map { $0 * log2($0) }.reduce(0, +)
    }

    private func jensenShannonDivergence(p: [String: Double], q: [String: Double]) -> Double {
        let allKeys = Set(p.keys).union(q.keys)
        guard !allKeys.isEmpty else { return 0.0 }

        // Compute midpoint distribution M = (P + Q) / 2
        var m: [String: Double] = [:]
        for key in allKeys {
            m[key] = ((p[key] ?? 0.0) + (q[key] ?? 0.0)) / 2.0
        }

        // JSD = (KL(P||M) + KL(Q||M)) / 2
        let klPM = klDivergence(from: p, to: m, keys: allKeys)
        let klQM = klDivergence(from: q, to: m, keys: allKeys)

        return (klPM + klQM) / 2.0
    }

    private func klDivergence(from p: [String: Double], to q: [String: Double], keys: Set<String>) -> Double {
        var sum = 0.0
        for key in keys {
            let pVal = p[key] ?? 0.0
            let qVal = q[key] ?? 0.0
            if pVal > 0 && qVal > 0 {
                sum += pVal * log2(pVal / qVal)
            }
        }
        return max(0, sum)
    }

    // MARK: - Private: Topic Extraction

    private func extractTopicsFromTitle(_ title: String) -> [String] {
        let words = title.lowercased()
            .components(separatedBy: .alphanumerics.inverted)
            .filter { $0.count > 3 }

        // Simple keyword-to-topic mapping
        let topicKeywords: [String: [String]] = [
            "technology": ["tech", "software", "hardware", "digital", "computer", "code", "programming", "developer"],
            "artificial_intelligence": ["ai", "machine", "learning", "neural", "model", "gpt", "llm", "deep"],
            "science": ["research", "study", "scientist", "discovery", "experiment", "physics", "biology", "chemistry"],
            "politics": ["election", "government", "policy", "political", "vote", "democrat", "republican", "congress"],
            "business": ["startup", "company", "market", "revenue", "funding", "investment", "stock", "ipo"],
            "health": ["health", "medical", "doctor", "patient", "hospital", "disease", "treatment", "vaccine"],
            "entertainment": ["movie", "film", "music", "game", "celebrity", "show", "streaming", "netflix"],
            "sports": ["team", "player", "game", "score", "championship", "league", "coach", "season"],
            "opinion": ["opinion", "editorial", "commentary", "think", "argue", "believe", "should"],
            "climate": ["climate", "carbon", "emission", "renewable", "energy", "solar", "warming", "sustainability"],
        ]

        var detected: [String] = []
        for (topic, keywords) in topicKeywords {
            if words.contains(where: { keywords.contains($0) }) {
                detected.append(topic)
            }
        }

        return detected.isEmpty ? ["general"] : detected
    }

    // MARK: - Private: Summary Generation

    private func generateSummary(
        feedName: String,
        driftType: EditorialDriftType,
        driftScore: Int,
        invading: [String],
        eroding: [String]
    ) -> String {
        switch driftType {
        case .stable:
            return "\(feedName) maintains a consistent editorial focus. No significant drift detected."
        case .insufficient:
            return "\(feedName) doesn't have enough history for drift analysis yet."
        case .topicInvasion:
            let topics = invading.prefix(3).joined(separator: ", ")
            return "\(feedName) is seeing new topics appear: \(topics). Drift score: \(driftScore)/100."
        case .identityErosion:
            let topics = eroding.prefix(3).joined(separator: ", ")
            return "\(feedName)'s core identity is fading — topics like \(topics) are declining. Drift score: \(driftScore)/100."
        case .pivot:
            return "\(feedName) appears to be pivoting its editorial focus. Original topics are being replaced by new ones. Drift score: \(driftScore)/100."
        case .dilution:
            return "\(feedName) is losing editorial focus by covering an increasingly scattered range of topics. Drift score: \(driftScore)/100."
        }
    }

    private func generateRecommendations(
        driftType: EditorialDriftType,
        severity: DriftSeverity,
        invading: [String],
        eroding: [String]
    ) -> [String] {
        var recs: [String] = []

        switch driftType {
        case .stable, .insufficient:
            recs.append("No action needed — feed is on track.")
        case .topicInvasion:
            recs.append("Review whether the new topics (\(invading.prefix(3).joined(separator: ", "))) match your interests.")
            if severity >= .significant {
                recs.append("Consider finding a more focused alternative if the new direction doesn't serve you.")
            }
        case .identityErosion:
            recs.append("The topics you originally subscribed for (\(eroding.prefix(3).joined(separator: ", "))) are fading.")
            recs.append("Look for alternative sources that still cover these topics well.")
        case .pivot:
            recs.append("This feed is changing direction. Decide if the new focus still serves your needs.")
            recs.append("Consider keeping it on a watchlist while you find replacements for lost coverage.")
        case .dilution:
            recs.append("Feed is becoming less focused. Consider if the signal-to-noise ratio is still worth it.")
            if severity >= .moderate {
                recs.append("Use topic filters to only see articles in your areas of interest.")
            }
        }

        if severity >= .significant {
            recs.append("⚠️ High drift detected — review this subscription soon.")
        }

        return recs
    }
}
