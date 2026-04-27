//
//  FeedInterestEvolver.swift
//  FeedReaderCore
//
//  Autonomous interest evolution tracker that monitors how the user's
//  reading interests change over time. Creates periodic "interest snapshots"
//  and analyzes them to detect:
//
//  - Emerging interests (new topics gaining traction)
//  - Fading interests (topics the user stopped caring about)
//  - Cyclical interests (topics that come and go periodically)
//  - Stable passions (consistently high engagement over time)
//  - Interest trajectories (where curiosity is heading)
//
//  Produces an EvolutionReport with a personal "intellectual biography"
//  timeline, predicted future interests, and curiosity diversity metrics.
//
//  Usage:
//  ```swift
//  let evolver = FeedInterestEvolver()
//
//  // Record snapshots from reading history
//  evolver.recordSnapshot(articles: recentArticles)
//
//  // Analyze evolution over time
//  let report = evolver.analyzeEvolution()
//  print(report.biography)          // narrative timeline
//  print(report.emergingTopics)     // what's growing
//  print(report.fadingTopics)       // what's declining
//  print(report.predictions)        // predicted future interests
//  ```
//
//  All processing is on-device. No network calls or external deps.
//

import Foundation

// MARK: - Interest Phase

/// Lifecycle phase of a tracked interest.
public enum InterestPhase: String, CaseIterable, Sendable {
    case emerging   = "emerging"
    case growing    = "growing"
    case stable     = "stable"
    case cyclical   = "cyclical"
    case fading     = "fading"
    case dormant    = "dormant"

    /// Emoji representation for display.
    public var emoji: String {
        switch self {
        case .emerging:  return "🌱"
        case .growing:   return "📈"
        case .stable:    return "⭐"
        case .cyclical:  return "🔄"
        case .fading:    return "🌅"
        case .dormant:   return "💤"
        }
    }

    /// Human-readable description.
    public var displayName: String {
        switch self {
        case .emerging:  return "Emerging Interest"
        case .growing:   return "Growing Interest"
        case .stable:    return "Stable Passion"
        case .cyclical:  return "Cyclical Interest"
        case .fading:    return "Fading Interest"
        case .dormant:   return "Dormant Interest"
        }
    }
}

// MARK: - Interest Snapshot

/// A point-in-time snapshot of the user's reading interests.
public struct InterestSnapshot: Sendable {
    /// When this snapshot was taken.
    public let timestamp: Date
    /// Topic → normalized weight (0.0–1.0). Weights sum to ~1.0.
    public let topicWeights: [String: Double]
    /// Number of articles analyzed for this snapshot.
    public let articleCount: Int

    public init(timestamp: Date, topicWeights: [String: Double], articleCount: Int) {
        self.timestamp = timestamp
        self.topicWeights = topicWeights
        self.articleCount = articleCount
    }
}

// MARK: - Interest Trajectory

/// Tracks how a single topic's weight has evolved over time.
public struct InterestTrajectory: Sendable {
    /// The topic keyword.
    public let topic: String
    /// Current lifecycle phase.
    public let phase: InterestPhase
    /// Weight history: (timestamp, weight) pairs in chronological order.
    public let history: [(Date, Double)]
    /// Current momentum: positive = growing, negative = fading.
    public let momentum: Double
    /// Predicted weight in the next snapshot period.
    public let predictedNextWeight: Double
    /// Confidence in the prediction (0.0–1.0).
    public let predictionConfidence: Double
    /// Number of peaks detected (for cyclical detection).
    public let peakCount: Int
    /// Average days between peaks (nil if not cyclical).
    public let cyclePeriodDays: Double?

    public init(topic: String, phase: InterestPhase, history: [(Date, Double)],
                momentum: Double, predictedNextWeight: Double,
                predictionConfidence: Double, peakCount: Int,
                cyclePeriodDays: Double?) {
        self.topic = topic
        self.phase = phase
        self.history = history
        self.momentum = momentum
        self.predictedNextWeight = predictedNextWeight
        self.predictionConfidence = predictionConfidence
        self.peakCount = peakCount
        self.cyclePeriodDays = cyclePeriodDays
    }
}

// MARK: - Evolution Report

/// Complete analysis of how the user's interests have evolved.
public struct EvolutionReport: Sendable {
    /// All tracked interest trajectories, sorted by current weight descending.
    public let trajectories: [InterestTrajectory]
    /// Topics in the emerging or growing phase.
    public let emergingTopics: [InterestTrajectory]
    /// Topics in the fading or dormant phase.
    public let fadingTopics: [InterestTrajectory]
    /// Topics detected as cyclical.
    public let cyclicalTopics: [InterestTrajectory]
    /// Topics with stable high engagement.
    public let stablePassions: [InterestTrajectory]
    /// Predicted future top interests (topic → predicted weight).
    public let predictions: [(topic: String, weight: Double, confidence: Double)]
    /// Curiosity breadth: how many distinct topics over the analysis window.
    public let curiosityBreadth: Int
    /// Curiosity depth: average weight concentration (higher = more focused).
    public let curiosityDepth: Double
    /// Shannon entropy of current interest distribution (higher = more diverse).
    public let diversityEntropy: Double
    /// Number of snapshots analyzed.
    public let snapshotCount: Int
    /// Time span covered.
    public let timeSpanDays: Int
    /// Narrative biography of interest evolution.
    public let biography: [BiographyEntry]

    public init(trajectories: [InterestTrajectory], emergingTopics: [InterestTrajectory],
                fadingTopics: [InterestTrajectory], cyclicalTopics: [InterestTrajectory],
                stablePassions: [InterestTrajectory],
                predictions: [(topic: String, weight: Double, confidence: Double)],
                curiosityBreadth: Int, curiosityDepth: Double, diversityEntropy: Double,
                snapshotCount: Int, timeSpanDays: Int, biography: [BiographyEntry]) {
        self.trajectories = trajectories
        self.emergingTopics = emergingTopics
        self.fadingTopics = fadingTopics
        self.cyclicalTopics = cyclicalTopics
        self.stablePassions = stablePassions
        self.predictions = predictions
        self.curiosityBreadth = curiosityBreadth
        self.curiosityDepth = curiosityDepth
        self.diversityEntropy = diversityEntropy
        self.snapshotCount = snapshotCount
        self.timeSpanDays = timeSpanDays
        self.biography = biography
    }
}

// MARK: - Biography Entry

/// A single entry in the user's intellectual biography timeline.
public struct BiographyEntry: Sendable {
    /// When this event occurred.
    public let date: Date
    /// What happened (e.g., "You discovered AI safety").
    public let narrative: String
    /// Related topics.
    public let topics: [String]
    /// Type of event.
    public let eventType: BiographyEventType

    public init(date: Date, narrative: String, topics: [String], eventType: BiographyEventType) {
        self.date = date
        self.narrative = narrative
        self.topics = topics
        self.eventType = eventType
    }
}

/// Types of events in the intellectual biography.
public enum BiographyEventType: String, CaseIterable, Sendable {
    case discoveredTopic    = "discovered"
    case deepDive           = "deep_dive"
    case interestShift      = "shift"
    case interestFaded      = "faded"
    case interestReturned   = "returned"
    case curiosityExpanded  = "expanded"
    case focusNarrowed      = "narrowed"
}

// MARK: - FeedInterestEvolver

/// Autonomous interest evolution tracker.
///
/// Maintains a time-series of interest snapshots extracted from reading
/// history, then analyzes the series to detect phase transitions,
/// cyclical patterns, momentum, and predict future interest trajectories.
public class FeedInterestEvolver {

    // MARK: - Configuration

    /// Minimum weight for a topic to be tracked across snapshots.
    public var minimumTopicWeight: Double = 0.02

    /// Number of top keywords to extract per article.
    public var keywordsPerArticle: Int = 5

    /// Minimum snapshots required for meaningful evolution analysis.
    public var minimumSnapshotsForAnalysis: Int = 2

    /// Momentum threshold above which a topic is considered growing.
    public var growingMomentumThreshold: Double = 0.05

    /// Momentum threshold below which a topic is considered fading.
    public var fadingMomentumThreshold: Double = -0.05

    /// Minimum peaks to consider a topic cyclical.
    public var minimumPeaksForCyclical: Int = 2

    /// Weight threshold for a topic to be considered a "stable passion".
    public var stablePassionMinWeight: Double = 0.08

    /// Maximum coefficient of variation for "stable" classification.
    public var stableMaxCoeffOfVariation: Double = 0.4

    // MARK: - State

    private var snapshots: [InterestSnapshot] = []
    private let keywordExtractor = KeywordExtractor()

    // MARK: - Initialization

    public init() {
        keywordExtractor.defaultCount = keywordsPerArticle
    }

    // MARK: - Snapshot Recording

    /// Creates an interest snapshot from a batch of recently read articles.
    ///
    /// - Parameters:
    ///   - articles: Tuples of (title, body, feedName) for each article.
    ///   - timestamp: When to date this snapshot (defaults to now).
    /// - Returns: The created snapshot, or nil if no articles provided.
    @discardableResult
    public func recordSnapshot(
        articles: [(title: String, body: String, feedName: String)],
        timestamp: Date = Date()
    ) -> InterestSnapshot? {
        guard !articles.isEmpty else { return nil }

        var rawWeights: [String: Double] = [:]

        for article in articles {
            let combined = article.title + " " + article.title + " " + article.body
            let keywords = keywordExtractor.extractKeywords(from: combined, count: keywordsPerArticle)

            for (index, keyword) in keywords.enumerated() {
                // Weight by position: first keyword gets highest weight
                let positionWeight = Double(keywordsPerArticle - index) / Double(keywordsPerArticle)
                rawWeights[keyword, default: 0] += positionWeight
            }
        }

        // Normalize to sum to 1.0
        let total = rawWeights.values.reduce(0, +)
        guard total > 0 else { return nil }

        var normalized: [String: Double] = [:]
        for (topic, weight) in rawWeights {
            let norm = weight / total
            if norm >= minimumTopicWeight {
                normalized[topic] = norm
            }
        }

        // Re-normalize after filtering
        let filteredTotal = normalized.values.reduce(0, +)
        if filteredTotal > 0 && filteredTotal != 1.0 {
            for key in normalized.keys {
                normalized[key]! /= filteredTotal
            }
        }

        let snapshot = InterestSnapshot(
            timestamp: timestamp,
            topicWeights: normalized,
            articleCount: articles.count
        )
        snapshots.append(snapshot)
        snapshots.sort { $0.timestamp < $1.timestamp }
        return snapshot
    }

    /// Adds a pre-built snapshot directly.
    public func addSnapshot(_ snapshot: InterestSnapshot) {
        snapshots.append(snapshot)
        snapshots.sort { $0.timestamp < $1.timestamp }
    }

    /// Returns the current number of snapshots.
    public var snapshotCount: Int { snapshots.count }

    /// Clears all recorded snapshots.
    public func reset() {
        snapshots.removeAll()
    }

    // MARK: - Evolution Analysis

    /// Analyzes the full evolution of reading interests across all snapshots.
    ///
    /// - Returns: An `EvolutionReport` with trajectories, predictions, and biography.
    public func analyzeEvolution() -> EvolutionReport {
        guard snapshots.count >= minimumSnapshotsForAnalysis else {
            return EvolutionReport(
                trajectories: [], emergingTopics: [], fadingTopics: [],
                cyclicalTopics: [], stablePassions: [],
                predictions: [], curiosityBreadth: 0, curiosityDepth: 0,
                diversityEntropy: 0, snapshotCount: snapshots.count,
                timeSpanDays: 0, biography: []
            )
        }

        // Collect all topics ever seen
        var allTopics = Set<String>()
        for snapshot in snapshots {
            allTopics.formUnion(snapshot.topicWeights.keys)
        }

        // Build trajectory for each topic
        var trajectories: [InterestTrajectory] = []
        for topic in allTopics {
            let trajectory = buildTrajectory(for: topic)
            trajectories.append(trajectory)
        }

        // Sort by current weight (last snapshot's weight)
        trajectories.sort { currentWeight(for: $0) > currentWeight(for: $1) }

        let emerging = trajectories.filter { $0.phase == .emerging || $0.phase == .growing }
        let fading = trajectories.filter { $0.phase == .fading || $0.phase == .dormant }
        let cyclical = trajectories.filter { $0.phase == .cyclical }
        let stable = trajectories.filter { $0.phase == .stable }

        // Predictions: top emerging/growing by predicted weight
        let predictions: [(topic: String, weight: Double, confidence: Double)] = trajectories
            .filter { $0.predictedNextWeight > minimumTopicWeight }
            .sorted { $0.predictedNextWeight > $1.predictedNextWeight }
            .prefix(10)
            .map { (topic: $0.topic, weight: $0.predictedNextWeight, confidence: $0.predictionConfidence) }

        // Curiosity metrics
        let breadth = allTopics.count
        let latestWeights = snapshots.last?.topicWeights ?? [:]
        let depth = computeConcentration(latestWeights)
        let entropy = computeEntropy(latestWeights)

        // Time span
        let timeSpan: Int
        if let first = snapshots.first?.timestamp, let last = snapshots.last?.timestamp {
            timeSpan = max(1, Calendar.current.dateComponents([.day], from: first, to: last).day ?? 0)
        } else {
            timeSpan = 0
        }

        // Generate biography
        let biography = generateBiography(trajectories: trajectories)

        return EvolutionReport(
            trajectories: trajectories,
            emergingTopics: emerging,
            fadingTopics: fading,
            cyclicalTopics: cyclical,
            stablePassions: stable,
            predictions: predictions,
            curiosityBreadth: breadth,
            curiosityDepth: depth,
            diversityEntropy: entropy,
            snapshotCount: snapshots.count,
            timeSpanDays: timeSpan,
            biography: biography
        )
    }

    // MARK: - Trajectory Building

    private func buildTrajectory(for topic: String) -> InterestTrajectory {
        // Extract time series for this topic
        let history: [(Date, Double)] = snapshots.map { snapshot in
            (snapshot.timestamp, snapshot.topicWeights[topic] ?? 0.0)
        }

        let weights = history.map { $0.1 }

        // Compute momentum via simple linear regression slope
        let momentum = computeSlope(weights)

        // Detect peaks for cyclical analysis
        let peaks = detectPeaks(weights)
        let cyclePeriod = computeCyclePeriod(peaks: peaks, timestamps: history.map { $0.0 })

        // Predict next weight using exponential moving average
        let (predicted, confidence) = predictNext(weights)

        // Classify phase
        let phase = classifyPhase(
            weights: weights,
            momentum: momentum,
            peakCount: peaks.count,
            hasCyclePeriod: cyclePeriod != nil
        )

        return InterestTrajectory(
            topic: topic, phase: phase, history: history,
            momentum: momentum, predictedNextWeight: predicted,
            predictionConfidence: confidence, peakCount: peaks.count,
            cyclePeriodDays: cyclePeriod
        )
    }

    private func classifyPhase(weights: [Double], momentum: Double,
                                peakCount: Int, hasCyclePeriod: Bool) -> InterestPhase {
        guard let last = weights.last else { return .dormant }

        let mean = weights.reduce(0, +) / Double(weights.count)
        let stdDev = sqrt(weights.map { ($0 - mean) * ($0 - mean) }.reduce(0, +) / Double(weights.count))
        let coeffOfVariation = mean > 0 ? stdDev / mean : 0

        // Check if dormant (zero or near-zero recently)
        let recentWeights = Array(weights.suffix(max(1, weights.count / 3)))
        let recentMean = recentWeights.reduce(0, +) / Double(recentWeights.count)
        if recentMean < minimumTopicWeight / 2 {
            return .dormant
        }

        // Check for cyclical pattern
        if peakCount >= minimumPeaksForCyclical && hasCyclePeriod {
            return .cyclical
        }

        // Check for stable passion
        if mean >= stablePassionMinWeight && coeffOfVariation <= stableMaxCoeffOfVariation && weights.count >= 3 {
            return .stable
        }

        // Emerging: appeared recently with upward momentum
        let earlyWeights = Array(weights.prefix(max(1, weights.count / 3)))
        let earlyMean = earlyWeights.reduce(0, +) / Double(earlyWeights.count)
        if earlyMean < minimumTopicWeight && last > minimumTopicWeight && momentum > 0 {
            return .emerging
        }

        // Growing vs fading by momentum
        if momentum > growingMomentumThreshold {
            return .growing
        }
        if momentum < fadingMomentumThreshold {
            return .fading
        }

        // Default to stable if none of the above triggered
        return .stable
    }

    // MARK: - Statistical Helpers

    /// Linear regression slope over evenly-spaced data points.
    private func computeSlope(_ values: [Double]) -> Double {
        let n = Double(values.count)
        guard n >= 2 else { return 0 }

        let xMean = (n - 1) / 2.0
        let yMean = values.reduce(0, +) / n

        var numerator = 0.0
        var denominator = 0.0
        for (i, y) in values.enumerated() {
            let x = Double(i)
            numerator += (x - xMean) * (y - yMean)
            denominator += (x - xMean) * (x - xMean)
        }

        return denominator > 0 ? numerator / denominator : 0
    }

    /// Detect local peaks (values higher than both neighbors).
    private func detectPeaks(_ values: [Double]) -> [Int] {
        guard values.count >= 3 else { return [] }
        var peaks: [Int] = []
        for i in 1..<(values.count - 1) {
            if values[i] > values[i - 1] && values[i] > values[i + 1] {
                peaks.append(i)
            }
        }
        return peaks
    }

    /// Compute average cycle period in days from detected peaks.
    private func computeCyclePeriod(peaks: [Int], timestamps: [Date]) -> Double? {
        guard peaks.count >= minimumPeaksForCyclical else { return nil }
        var intervals: [Double] = []
        for i in 1..<peaks.count {
            let days = Calendar.current.dateComponents(
                [.day], from: timestamps[peaks[i - 1]], to: timestamps[peaks[i]]
            ).day ?? 0
            if days > 0 {
                intervals.append(Double(days))
            }
        }
        guard !intervals.isEmpty else { return nil }
        return intervals.reduce(0, +) / Double(intervals.count)
    }

    /// Predict next value using exponential moving average.
    private func predictNext(_ values: [Double]) -> (predicted: Double, confidence: Double) {
        guard !values.isEmpty else { return (0, 0) }
        guard values.count >= 2 else { return (values[0], 0.3) }

        let alpha = 0.3  // smoothing factor
        var ema = values[0]
        for v in values.dropFirst() {
            ema = alpha * v + (1 - alpha) * ema
        }

        // Confidence based on how stable the series is
        let mean = values.reduce(0, +) / Double(values.count)
        let variance = values.map { ($0 - mean) * ($0 - mean) }.reduce(0, +) / Double(values.count)
        let cv = mean > 0 ? sqrt(variance) / mean : 1.0
        let confidence = max(0.1, min(0.95, 1.0 - cv))

        return (max(0, ema), confidence)
    }

    /// Herfindahl-Hirschman Index — measures concentration.
    private func computeConcentration(_ weights: [String: Double]) -> Double {
        guard !weights.isEmpty else { return 0 }
        return weights.values.map { $0 * $0 }.reduce(0, +)
    }

    /// Shannon entropy of a probability distribution.
    private func computeEntropy(_ weights: [String: Double]) -> Double {
        guard !weights.isEmpty else { return 0 }
        var entropy = 0.0
        for w in weights.values where w > 0 {
            entropy -= w * log2(w)
        }
        return entropy
    }

    private func currentWeight(for trajectory: InterestTrajectory) -> Double {
        return trajectory.history.last?.1 ?? 0
    }

    // MARK: - Biography Generation

    private func generateBiography(trajectories: [InterestTrajectory]) -> [BiographyEntry] {
        var entries: [BiographyEntry] = []

        for trajectory in trajectories {
            let weights = trajectory.history.map { $0.1 }
            let timestamps = trajectory.history.map { $0.0 }
            guard weights.count >= 2 else { continue }

            // Detect first appearance
            if let firstNonZero = weights.firstIndex(where: { $0 >= minimumTopicWeight }) {
                if firstNonZero > 0 || (firstNonZero == 0 && weights.count > 1 && weights[1] > weights[0]) {
                    entries.append(BiographyEntry(
                        date: timestamps[firstNonZero],
                        narrative: "Discovered interest in \(trajectory.topic)",
                        topics: [trajectory.topic],
                        eventType: .discoveredTopic
                    ))
                }
            }

            // Detect deep dives (sudden significant increase)
            for i in 1..<weights.count {
                if weights[i] > 0.15 && weights[i] > weights[i - 1] * 2.0 {
                    entries.append(BiographyEntry(
                        date: timestamps[i],
                        narrative: "Deep dive into \(trajectory.topic)",
                        topics: [trajectory.topic],
                        eventType: .deepDive
                    ))
                }
            }

            // Detect fading (went from significant to near-zero)
            if trajectory.phase == .fading || trajectory.phase == .dormant {
                if let lastSignificant = weights.lastIndex(where: { $0 >= stablePassionMinWeight }) {
                    if lastSignificant < weights.count - 1 {
                        entries.append(BiographyEntry(
                            date: timestamps[min(lastSignificant + 1, timestamps.count - 1)],
                            narrative: "Interest in \(trajectory.topic) began fading",
                            topics: [trajectory.topic],
                            eventType: .interestFaded
                        ))
                    }
                }
            }

            // Detect returns (cyclical topics coming back)
            if trajectory.phase == .cyclical && trajectory.peakCount >= 2 {
                let peaks = detectPeaks(weights)
                if let lastPeak = peaks.last, lastPeak < timestamps.count {
                    entries.append(BiographyEntry(
                        date: timestamps[lastPeak],
                        narrative: "Returned to \(trajectory.topic) (cyclical pattern detected)",
                        topics: [trajectory.topic],
                        eventType: .interestReturned
                    ))
                }
            }
        }

        // Sort chronologically
        entries.sort { $0.date < $1.date }

        // Detect curiosity expansion/narrowing events from snapshots
        for i in 1..<snapshots.count {
            let prevCount = snapshots[i - 1].topicWeights.count
            let currCount = snapshots[i].topicWeights.count
            let ratio = Double(currCount) / Double(max(1, prevCount))

            if ratio > 1.5 && currCount - prevCount >= 3 {
                let newTopics = Set(snapshots[i].topicWeights.keys)
                    .subtracting(snapshots[i - 1].topicWeights.keys)
                entries.append(BiographyEntry(
                    date: snapshots[i].timestamp,
                    narrative: "Curiosity expanded — exploring \(newTopics.prefix(3).joined(separator: ", "))",
                    topics: Array(newTopics.prefix(3)),
                    eventType: .curiosityExpanded
                ))
            } else if ratio < 0.6 && prevCount - currCount >= 3 {
                entries.append(BiographyEntry(
                    date: snapshots[i].timestamp,
                    narrative: "Focus narrowed to fewer topics",
                    topics: Array(snapshots[i].topicWeights.keys.prefix(3)),
                    eventType: .focusNarrowed
                ))
            }
        }

        entries.sort { $0.date < $1.date }
        return entries
    }
}
