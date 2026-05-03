//
//  FeedPredictiveInterestEngine.swift
//  FeedReaderCore
//
//  Autonomous predictive interest engine that forecasts future reading
//  interests before the user explicitly searches for them. Analyzes
//  interest trajectory vectors, detects emerging curiosity signals,
//  and proactively surfaces articles aligned with predicted interests.
//
//  Key capabilities:
//  - Interest trajectory tracking with velocity/acceleration vectors
//  - Curiosity signal detection (repeated tangential exposure, dwell patterns)
//  - Adjacent interest prediction via co-occurrence analysis
//  - Interest momentum forecasting with confidence intervals
//  - Proactive article surfacing ranked by predicted relevance
//  - Prediction accuracy self-tracking and model adaptation
//  - Autonomous insights about interest evolution
//  - Health scoring 0-100 with prediction quality grades
//
//  Usage:
//  ```swift
//  let engine = FeedPredictiveInterestEngine()
//
//  engine.recordInteraction(topic: "machine learning",
//                           feedURL: "https://blog.ai/feed",
//                           articleId: "a1",
//                           interactionType: .read,
//                           dwellSeconds: 180,
//                           timestamp: Date())
//
//  let forecast = engine.forecast()
//  print(forecast.predictions)       // Predicted future interests
//  print(forecast.surfacedArticles)  // Proactively recommended articles
//  print(forecast.healthScore)       // 0-100
//  print(forecast.insights)          // Autonomous observations
//  ```
//
//  All processing is on-device. No network calls or external deps.
//

import Foundation

// MARK: - Interaction Type

/// Type of user interaction with content.
public enum InteractionType: String, CaseIterable, Sendable {
    case read       = "Read"        // Full article read
    case skim       = "Skim"        // Quick scan (<30s)
    case bookmark   = "Bookmark"    // Saved for later
    case share      = "Share"       // Shared externally
    case search     = "Search"      // Actively searched for
    case click      = "Click"       // Clicked but bounced
    case highlight  = "Highlight"   // Highlighted text

    /// Weight for interest signal strength.
    public var signalWeight: Double {
        switch self {
        case .search:    return 1.0
        case .bookmark:  return 0.9
        case .share:     return 0.85
        case .highlight: return 0.8
        case .read:      return 0.7
        case .skim:      return 0.3
        case .click:     return 0.2
        }
    }
}

// MARK: - Interest Phase

/// Phase of an interest's lifecycle trajectory.
public enum InterestPhase: String, CaseIterable, Comparable, Sendable {
    case latent     = "Latent"      // Sub-threshold curiosity signals
    case emerging   = "Emerging"    // Early acceleration detected
    case growing    = "Growing"     // Active growth phase
    case peak       = "Peak"        // Maximum engagement
    case stable     = "Stable"      // Consistent sustained interest
    case waning     = "Waning"      // Declining engagement
    case dormant    = "Dormant"     // No recent activity

    private var ordinal: Int {
        switch self {
        case .latent:   return 0
        case .emerging: return 1
        case .growing:  return 2
        case .peak:     return 3
        case .stable:   return 4
        case .waning:   return 5
        case .dormant:  return 6
        }
    }

    public static func < (lhs: InterestPhase, rhs: InterestPhase) -> Bool {
        lhs.ordinal < rhs.ordinal
    }

    /// Emoji indicator.
    public var emoji: String {
        switch self {
        case .latent:   return "🫥"
        case .emerging: return "🌱"
        case .growing:  return "📈"
        case .peak:     return "⭐"
        case .stable:   return "📊"
        case .waning:   return "📉"
        case .dormant:  return "💤"
        }
    }
}

// MARK: - Prediction Confidence

/// Confidence level of an interest prediction.
public enum PredictionConfidence: String, CaseIterable, Comparable, Sendable {
    case high       = "High"        // Strong signal convergence
    case medium     = "Medium"      // Moderate evidence
    case low        = "Low"         // Weak but detectable signal
    case speculative = "Speculative" // Pattern-based inference only

    private var ordinal: Int {
        switch self {
        case .high:        return 3
        case .medium:      return 2
        case .low:         return 1
        case .speculative: return 0
        }
    }

    public static func < (lhs: PredictionConfidence, rhs: PredictionConfidence) -> Bool {
        lhs.ordinal < rhs.ordinal
    }

    /// Numeric threshold for this confidence level.
    public var threshold: Double {
        switch self {
        case .high:        return 0.75
        case .medium:      return 0.5
        case .low:         return 0.25
        case .speculative: return 0.0
        }
    }
}

// MARK: - Interest Signal

/// A recorded interaction representing an interest signal.
public struct InterestSignal: Sendable {
    public let topic: String
    public let feedURL: String
    public let articleId: String
    public let interactionType: InteractionType
    public let dwellSeconds: Double
    public let timestamp: Date
    public let relatedTopics: [String]

    public init(topic: String, feedURL: String, articleId: String,
                interactionType: InteractionType, dwellSeconds: Double = 0,
                timestamp: Date = Date(), relatedTopics: [String] = []) {
        self.topic = topic.lowercased().trimmingCharacters(in: .whitespaces)
        self.feedURL = feedURL
        self.articleId = articleId
        self.interactionType = interactionType
        self.dwellSeconds = dwellSeconds
        self.timestamp = timestamp
        self.relatedTopics = relatedTopics.map { $0.lowercased().trimmingCharacters(in: .whitespaces) }
    }
}

// MARK: - Interest Trajectory

/// Trajectory vector for a tracked interest.
public struct InterestTrajectory: Sendable {
    public let topic: String
    public let phase: InterestPhase
    public let currentStrength: Double      // 0-1 weighted signal strength
    public let velocity: Double             // Change rate (per day)
    public let acceleration: Double         // Rate of velocity change
    public let daysSinceLastSignal: Int
    public let totalSignals: Int
    public let feedSpread: Int              // Number of distinct feeds
    public let dwellAverage: Double         // Average dwell time
    public let firstSeen: Date
    public let lastSeen: Date

    /// Predicted strength N days from now using trajectory.
    public func predictedStrength(daysAhead: Int) -> Double {
        let t = Double(daysAhead)
        let predicted = currentStrength + velocity * t + 0.5 * acceleration * t * t
        return max(0, min(1, predicted))
    }
}

// MARK: - Interest Prediction

/// A predicted future interest with confidence and evidence.
public struct InterestPrediction: Sendable {
    public let topic: String
    public let confidence: PredictionConfidence
    public let confidenceScore: Double      // 0-1 numeric
    public let reason: String               // Why predicted
    public let predictedPhaseIn7Days: InterestPhase
    public let predictedStrengthIn7Days: Double
    public let evidenceSignals: Int         // Supporting signals
    public let adjacentTopics: [String]     // Related known interests
    public let suggestedAction: String      // What to do about it
}

// MARK: - Surfaced Article

/// An article proactively surfaced based on predicted interests.
public struct SurfacedArticle: Sendable {
    public let articleId: String
    public let feedURL: String
    public let matchedPrediction: String    // Which prediction it matches
    public let relevanceScore: Double       // 0-1
    public let reason: String
}

// MARK: - Prediction Accuracy Record

/// Tracks prediction outcomes for self-improvement.
public struct PredictionOutcome: Sendable {
    public let predictedTopic: String
    public let predictionDate: Date
    public let confidence: PredictionConfidence
    public let wasAccurate: Bool            // Did user actually engage?
    public let actualStrength: Double       // Actual engagement level
}

// MARK: - Forecast Result

/// Complete forecast output from the engine.
public struct InterestForecast: Sendable {
    public let predictions: [InterestPrediction]
    public let trajectories: [InterestTrajectory]
    public let surfacedArticles: [SurfacedArticle]
    public let healthScore: Int             // 0-100
    public let healthGrade: String          // A-F
    public let predictionAccuracy: Double   // Historical accuracy 0-1
    public let insights: [String]
    public let generatedAt: Date
}

// MARK: - Candidate Article

/// An article available for proactive surfacing.
public struct CandidateArticle: Sendable {
    public let articleId: String
    public let feedURL: String
    public let topics: [String]
    public let publishedAt: Date

    public init(articleId: String, feedURL: String, topics: [String], publishedAt: Date = Date()) {
        self.articleId = articleId
        self.feedURL = feedURL
        self.topics = topics.map { $0.lowercased().trimmingCharacters(in: .whitespaces) }
        self.publishedAt = publishedAt
    }
}

// MARK: - Engine

/// Autonomous predictive interest engine.
public final class FeedPredictiveInterestEngine: @unchecked Sendable {

    // MARK: - Configuration

    /// Minimum signals to form a trajectory.
    public var minimumSignalsForTrajectory: Int = 3

    /// Days of history to consider for trajectory computation.
    public var trajectoryWindowDays: Int = 30

    /// Decay half-life in days for signal freshness.
    public var decayHalfLifeDays: Double = 7.0

    /// Minimum co-occurrence count to infer adjacency.
    public var minimumCoOccurrence: Int = 2

    /// Maximum predictions to return.
    public var maxPredictions: Int = 20

    /// Maximum surfaced articles to return.
    public var maxSurfacedArticles: Int = 15

    // MARK: - State

    private var signals: [InterestSignal] = []
    private var outcomes: [PredictionOutcome] = []
    private var candidates: [CandidateArticle] = []
    private let calendar = Calendar.current

    // MARK: - Init

    public init() {}

    // MARK: - Recording

    /// Record a user interaction as an interest signal.
    public func recordInteraction(topic: String, feedURL: String, articleId: String,
                                  interactionType: InteractionType,
                                  dwellSeconds: Double = 0,
                                  timestamp: Date = Date(),
                                  relatedTopics: [String] = []) {
        let signal = InterestSignal(
            topic: topic, feedURL: feedURL, articleId: articleId,
            interactionType: interactionType, dwellSeconds: dwellSeconds,
            timestamp: timestamp, relatedTopics: relatedTopics
        )
        signals.append(signal)
    }

    /// Record a prediction outcome for self-improvement.
    public func recordOutcome(predictedTopic: String, predictionDate: Date,
                              confidence: PredictionConfidence,
                              wasAccurate: Bool, actualStrength: Double = 0) {
        let outcome = PredictionOutcome(
            predictedTopic: predictedTopic, predictionDate: predictionDate,
            confidence: confidence, wasAccurate: wasAccurate,
            actualStrength: actualStrength
        )
        outcomes.append(outcome)
    }

    /// Register candidate articles for proactive surfacing.
    public func registerCandidates(_ articles: [CandidateArticle]) {
        candidates.append(contentsOf: articles)
    }

    /// Clear all candidates.
    public func clearCandidates() {
        candidates.removeAll()
    }

    /// Get current signal count.
    public var signalCount: Int { signals.count }

    /// Get current outcome count.
    public var outcomeCount: Int { outcomes.count }

    // MARK: - Forecasting

    /// Generate a complete interest forecast.
    public func forecast(asOf: Date = Date()) -> InterestForecast {
        let trajectories = computeTrajectories(asOf: asOf)
        let coOccurrenceMap = buildCoOccurrenceMap()
        let predictions = generatePredictions(trajectories: trajectories,
                                              coOccurrenceMap: coOccurrenceMap,
                                              asOf: asOf)
        let surfaced = surfaceArticles(predictions: predictions, asOf: asOf)
        let accuracy = computeAccuracy()
        let insights = generateInsights(trajectories: trajectories,
                                        predictions: predictions,
                                        accuracy: accuracy,
                                        asOf: asOf)
        let health = computeHealthScore(trajectories: trajectories,
                                        predictions: predictions,
                                        accuracy: accuracy)

        return InterestForecast(
            predictions: Array(predictions.prefix(maxPredictions)),
            trajectories: trajectories,
            surfacedArticles: Array(surfaced.prefix(maxSurfacedArticles)),
            healthScore: health.score,
            healthGrade: health.grade,
            predictionAccuracy: accuracy,
            insights: insights,
            generatedAt: asOf
        )
    }

    /// Get trajectories only (lighter weight).
    public func getTrajectories(asOf: Date = Date()) -> [InterestTrajectory] {
        return computeTrajectories(asOf: asOf)
    }

    // MARK: - Trajectory Computation

    private func computeTrajectories(asOf: Date) -> [InterestTrajectory] {
        let windowStart = calendar.date(byAdding: .day, value: -trajectoryWindowDays, to: asOf) ?? asOf
        let relevantSignals = signals.filter { $0.timestamp >= windowStart && $0.timestamp <= asOf }

        // Group by topic
        var topicSignals: [String: [InterestSignal]] = [:]
        for signal in relevantSignals {
            topicSignals[signal.topic, default: []].append(signal)
        }

        var trajectories: [InterestTrajectory] = []

        for (topic, topicSigs) in topicSignals {
            guard topicSigs.count >= minimumSignalsForTrajectory else { continue }

            let sorted = topicSigs.sorted { $0.timestamp < $1.timestamp }
            let firstSeen = sorted.first!.timestamp
            let lastSeen = sorted.last!.timestamp
            let daysSinceLast = calendar.dateComponents([.day], from: lastSeen, to: asOf).day ?? 0

            // Compute weighted strength with exponential decay
            let strength = computeDecayedStrength(signals: topicSigs, asOf: asOf)

            // Compute velocity: split window into halves and compare
            let midpoint = calendar.date(byAdding: .day, value: -trajectoryWindowDays / 2, to: asOf) ?? asOf
            let firstHalf = topicSigs.filter { $0.timestamp < midpoint }
            let secondHalf = topicSigs.filter { $0.timestamp >= midpoint }
            let halfDays = Double(trajectoryWindowDays) / 2.0

            let firstRate = Double(firstHalf.count) / max(halfDays, 1.0)
            let secondRate = Double(secondHalf.count) / max(halfDays, 1.0)
            let velocity = (secondRate - firstRate) / max(halfDays, 1.0)

            // Compute acceleration: split second half further
            let quarterPoint = calendar.date(byAdding: .day, value: -trajectoryWindowDays / 4, to: asOf) ?? asOf
            let q3 = secondHalf.filter { $0.timestamp < quarterPoint }
            let q4 = secondHalf.filter { $0.timestamp >= quarterPoint }
            let quarterDays = Double(trajectoryWindowDays) / 4.0
            let q3Rate = Double(q3.count) / max(quarterDays, 1.0)
            let q4Rate = Double(q4.count) / max(quarterDays, 1.0)
            let acceleration = (q4Rate - q3Rate) / max(quarterDays, 1.0)

            // Feed spread
            let feeds = Set(topicSigs.map { $0.feedURL })

            // Average dwell
            let dwells = topicSigs.filter { $0.dwellSeconds > 0 }.map { $0.dwellSeconds }
            let avgDwell = dwells.isEmpty ? 0 : dwells.reduce(0, +) / Double(dwells.count)

            // Phase classification
            let phase = classifyPhase(strength: strength, velocity: velocity,
                                      acceleration: acceleration, daysSinceLast: daysSinceLast)

            let trajectory = InterestTrajectory(
                topic: topic, phase: phase, currentStrength: strength,
                velocity: velocity, acceleration: acceleration,
                daysSinceLastSignal: daysSinceLast, totalSignals: topicSigs.count,
                feedSpread: feeds.count, dwellAverage: avgDwell,
                firstSeen: firstSeen, lastSeen: lastSeen
            )
            trajectories.append(trajectory)
        }

        return trajectories.sorted { $0.currentStrength > $1.currentStrength }
    }

    private func computeDecayedStrength(signals sigs: [InterestSignal], asOf: Date) -> Double {
        let lambda = log(2.0) / decayHalfLifeDays
        var totalWeight = 0.0

        for signal in sigs {
            let daysAgo = Double(calendar.dateComponents([.day], from: signal.timestamp, to: asOf).day ?? 0)
            let decay = exp(-lambda * max(daysAgo, 0))
            let weight = signal.interactionType.signalWeight * decay
            // Bonus for long dwell
            let dwellBonus = signal.dwellSeconds > 120 ? 0.1 : 0
            totalWeight += weight + dwellBonus
        }

        // Normalize to 0-1 (cap at 10 as "maximum")
        return min(1.0, totalWeight / 10.0)
    }

    private func classifyPhase(strength: Double, velocity: Double,
                               acceleration: Double, daysSinceLast: Int) -> InterestPhase {
        if daysSinceLast > 14 { return .dormant }
        if daysSinceLast > 7 && velocity < 0 { return .waning }
        if strength < 0.15 && acceleration > 0 { return .latent }
        if strength < 0.3 && velocity > 0 { return .emerging }
        if velocity > 0.02 && acceleration > 0 { return .growing }
        if strength > 0.7 && abs(velocity) < 0.01 { return .peak }
        if velocity < -0.01 { return .waning }
        return .stable
    }

    // MARK: - Co-occurrence Map

    private func buildCoOccurrenceMap() -> [String: [String: Int]] {
        var coOccurrence: [String: [String: Int]] = [:]

        // Build from related topics in signals
        for signal in signals {
            for related in signal.relatedTopics {
                coOccurrence[signal.topic, default: [:]][related, default: 0] += 1
                coOccurrence[related, default: [:]][signal.topic, default: 0] += 1
            }
        }

        // Build from same-article co-occurrence
        var articleTopics: [String: Set<String>] = [:]
        for signal in signals {
            articleTopics[signal.articleId, default: []].insert(signal.topic)
        }
        for (_, topics) in articleTopics where topics.count > 1 {
            let topicArray = Array(topics)
            for i in 0..<topicArray.count {
                for j in (i+1)..<topicArray.count {
                    coOccurrence[topicArray[i], default: [:]][topicArray[j], default: 0] += 1
                    coOccurrence[topicArray[j], default: [:]][topicArray[i], default: 0] += 1
                }
            }
        }

        return coOccurrence
    }

    // MARK: - Prediction Generation

    private func generatePredictions(trajectories: [InterestTrajectory],
                                     coOccurrenceMap: [String: [String: Int]],
                                     asOf: Date) -> [InterestPrediction] {
        var predictions: [InterestPrediction] = []

        // Strategy 1: Trajectory-based predictions (growing/emerging topics)
        for traj in trajectories where traj.phase == .emerging || traj.phase == .growing || traj.phase == .latent {
            let predictedStrength = traj.predictedStrength(daysAhead: 7)
            let confidence = computeTrajectoryConfidence(traj)
            let predictedPhase = predictPhase(currentPhase: traj.phase,
                                             velocity: traj.velocity,
                                             acceleration: traj.acceleration)

            let reason: String
            switch traj.phase {
            case .latent:
                reason = "Sub-threshold curiosity detected — \(traj.totalSignals) tangential exposures with positive acceleration"
            case .emerging:
                reason = "Interest emergence detected — velocity \(String(format: "%.3f", traj.velocity))/day across \(traj.feedSpread) feeds"
            case .growing:
                reason = "Active growth trajectory — strength \(String(format: "%.2f", traj.currentStrength)) with positive acceleration"
            default:
                reason = "Trajectory analysis"
            }

            let action: String
            if traj.phase == .latent {
                action = "Surface introductory content to catalyze interest"
            } else if traj.phase == .emerging {
                action = "Increase exposure — user is developing this interest"
            } else {
                action = "Prioritize deep-dive content on this topic"
            }

            predictions.append(InterestPrediction(
                topic: traj.topic, confidence: confidence,
                confidenceScore: trajectoryConfidenceScore(traj),
                reason: reason, predictedPhaseIn7Days: predictedPhase,
                predictedStrengthIn7Days: predictedStrength,
                evidenceSignals: traj.totalSignals,
                adjacentTopics: findAdjacentTopics(traj.topic, coOccurrenceMap: coOccurrenceMap),
                suggestedAction: action
            ))
        }

        // Strategy 2: Adjacent interest predictions
        let knownTopics = Set(trajectories.map { $0.topic })
        var adjacentCandidates: [String: (score: Double, sources: [String])] = [:]

        for traj in trajectories where traj.currentStrength > 0.3 {
            if let neighbors = coOccurrenceMap[traj.topic] {
                for (neighbor, count) in neighbors where count >= minimumCoOccurrence {
                    if !knownTopics.contains(neighbor) || trajectories.first(where: { $0.topic == neighbor })?.phase == .dormant {
                        let score = traj.currentStrength * Double(count) * 0.1
                        adjacentCandidates[neighbor, default: (0, [])].score += score
                        adjacentCandidates[neighbor, default: (0, [])].sources.append(traj.topic)
                    }
                }
            }
        }

        for (topic, info) in adjacentCandidates where info.score > 0.1 {
            let confidenceScore = min(1.0, info.score)
            let confidence: PredictionConfidence
            if confidenceScore >= 0.75 { confidence = .high }
            else if confidenceScore >= 0.5 { confidence = .medium }
            else if confidenceScore >= 0.25 { confidence = .low }
            else { confidence = .speculative }

            let uniqueSources = Array(Set(info.sources))
            predictions.append(InterestPrediction(
                topic: topic, confidence: confidence,
                confidenceScore: confidenceScore,
                reason: "Adjacent to active interests: \(uniqueSources.prefix(3).joined(separator: ", "))",
                predictedPhaseIn7Days: .emerging,
                predictedStrengthIn7Days: min(0.4, info.score),
                evidenceSignals: 0,
                adjacentTopics: uniqueSources,
                suggestedAction: "Introduce content bridging from \(uniqueSources.first ?? "related") topics"
            ))
        }

        // Strategy 3: Cyclical interest detection (dormant topics that had prior peaks)
        for traj in trajectories where traj.phase == .dormant && traj.totalSignals >= 5 {
            let daysSinceFirst = calendar.dateComponents([.day], from: traj.firstSeen, to: asOf).day ?? 0
            if daysSinceFirst > 30 {
                predictions.append(InterestPrediction(
                    topic: traj.topic, confidence: .speculative,
                    confidenceScore: 0.2,
                    reason: "Previously strong interest (\(traj.totalSignals) signals) now dormant — cyclical resurgence possible",
                    predictedPhaseIn7Days: .latent,
                    predictedStrengthIn7Days: 0.1,
                    evidenceSignals: traj.totalSignals,
                    adjacentTopics: findAdjacentTopics(traj.topic, coOccurrenceMap: coOccurrenceMap),
                    suggestedAction: "Occasional light exposure to test for renewed interest"
                ))
            }
        }

        return predictions.sorted { $0.confidenceScore > $1.confidenceScore }
    }

    private func computeTrajectoryConfidence(_ traj: InterestTrajectory) -> PredictionConfidence {
        let score = trajectoryConfidenceScore(traj)
        if score >= 0.75 { return .high }
        if score >= 0.5 { return .medium }
        if score >= 0.25 { return .low }
        return .speculative
    }

    private func trajectoryConfidenceScore(_ traj: InterestTrajectory) -> Double {
        var score = 0.0
        // More signals = more confidence
        score += min(0.3, Double(traj.totalSignals) * 0.03)
        // Multi-feed spread = more confidence
        score += min(0.2, Double(traj.feedSpread) * 0.1)
        // Positive velocity
        if traj.velocity > 0 { score += min(0.2, traj.velocity * 10) }
        // Positive acceleration
        if traj.acceleration > 0 { score += min(0.15, traj.acceleration * 20) }
        // High dwell
        if traj.dwellAverage > 60 { score += 0.15 }
        else if traj.dwellAverage > 30 { score += 0.1 }
        return min(1.0, score)
    }

    private func predictPhase(currentPhase: InterestPhase, velocity: Double, acceleration: Double) -> InterestPhase {
        switch currentPhase {
        case .latent:
            return acceleration > 0.01 ? .emerging : .latent
        case .emerging:
            return velocity > 0.02 ? .growing : .emerging
        case .growing:
            return acceleration < 0 ? .peak : .growing
        default:
            return currentPhase
        }
    }

    private func findAdjacentTopics(_ topic: String, coOccurrenceMap: [String: [String: Int]]) -> [String] {
        guard let neighbors = coOccurrenceMap[topic] else { return [] }
        return neighbors
            .filter { $0.value >= minimumCoOccurrence }
            .sorted { $0.value > $1.value }
            .prefix(5)
            .map { $0.key }
    }

    // MARK: - Article Surfacing

    private func surfaceArticles(predictions: [InterestPrediction], asOf: Date) -> [SurfacedArticle] {
        guard !candidates.isEmpty && !predictions.isEmpty else { return [] }

        var surfaced: [SurfacedArticle] = []

        for candidate in candidates {
            var bestMatch: (prediction: InterestPrediction, score: Double)?

            for prediction in predictions {
                // Check if candidate topics match prediction
                let matchScore = computeTopicMatch(candidateTopics: candidate.topics,
                                                   predictionTopic: prediction.topic,
                                                   adjacentTopics: prediction.adjacentTopics)
                if matchScore > 0 {
                    let relevance = matchScore * prediction.confidenceScore
                    if bestMatch == nil || relevance > bestMatch!.score {
                        bestMatch = (prediction, relevance)
                    }
                }
            }

            if let match = bestMatch, match.score > 0.1 {
                let reason: String
                if candidate.topics.contains(match.prediction.topic) {
                    reason = "Direct match with predicted interest '\(match.prediction.topic)'"
                } else {
                    reason = "Related to predicted interest '\(match.prediction.topic)' via topic adjacency"
                }

                surfaced.append(SurfacedArticle(
                    articleId: candidate.articleId,
                    feedURL: candidate.feedURL,
                    matchedPrediction: match.prediction.topic,
                    relevanceScore: match.score,
                    reason: reason
                ))
            }
        }

        return surfaced.sorted { $0.relevanceScore > $1.relevanceScore }
    }

    private func computeTopicMatch(candidateTopics: [String], predictionTopic: String,
                                   adjacentTopics: [String]) -> Double {
        // Direct match
        if candidateTopics.contains(predictionTopic) { return 1.0 }

        // Partial string match
        for cTopic in candidateTopics {
            if cTopic.contains(predictionTopic) || predictionTopic.contains(cTopic) {
                return 0.8
            }
        }

        // Adjacent topic match
        let candidateSet = Set(candidateTopics)
        let adjacentSet = Set(adjacentTopics)
        let overlap = candidateSet.intersection(adjacentSet)
        if !overlap.isEmpty {
            return 0.5 * Double(overlap.count) / Double(max(adjacentSet.count, 1))
        }

        return 0
    }

    // MARK: - Accuracy Tracking

    private func computeAccuracy() -> Double {
        guard !outcomes.isEmpty else { return 0.5 } // Default neutral
        let accurate = outcomes.filter { $0.wasAccurate }.count
        return Double(accurate) / Double(outcomes.count)
    }

    // MARK: - Health Score

    private func computeHealthScore(trajectories: [InterestTrajectory],
                                    predictions: [InterestPrediction],
                                    accuracy: Double) -> (score: Int, grade: String) {
        var score = 0.0

        // Data richness (0-25)
        let signalDensity = min(1.0, Double(signals.count) / 100.0)
        score += signalDensity * 25

        // Trajectory diversity (0-20)
        let phases = Set(trajectories.map { $0.phase })
        let phaseDiversity = Double(phases.count) / Double(InterestPhase.allCases.count)
        score += phaseDiversity * 20

        // Prediction quality (0-25)
        let highConfPredictions = predictions.filter { $0.confidence >= .medium }.count
        let predQuality = min(1.0, Double(highConfPredictions) / 5.0)
        score += predQuality * 25

        // Historical accuracy (0-20)
        score += accuracy * 20

        // Active trajectories (0-10)
        let activeTrajectories = trajectories.filter { $0.phase != .dormant }.count
        score += min(10, Double(activeTrajectories) * 2)

        let finalScore = min(100, max(0, Int(score)))
        let grade: String
        switch finalScore {
        case 90...100: grade = "A"
        case 80..<90:  grade = "B"
        case 70..<80:  grade = "C"
        case 60..<70:  grade = "D"
        default:       grade = "F"
        }

        return (finalScore, grade)
    }

    // MARK: - Insight Generation

    private func generateInsights(trajectories: [InterestTrajectory],
                                  predictions: [InterestPrediction],
                                  accuracy: Double,
                                  asOf: Date) -> [String] {
        var insights: [String] = []

        // Fastest growing interest
        if let fastest = trajectories.filter({ $0.velocity > 0 }).max(by: { $0.velocity < $1.velocity }) {
            insights.append("🚀 '\(fastest.topic)' is your fastest-growing interest (velocity: \(String(format: "%.3f", fastest.velocity))/day)")
        }

        // Latent interests about to emerge
        let latentEmerging = trajectories.filter { $0.phase == .latent && $0.acceleration > 0 }
        if !latentEmerging.isEmpty {
            let topics = latentEmerging.prefix(3).map { "'\($0.topic)'" }.joined(separator: ", ")
            insights.append("🫥 Latent curiosity signals detected for \(topics) — these may become active interests soon")
        }

        // Multi-feed convergence
        let multiFeed = trajectories.filter { $0.feedSpread >= 3 && $0.phase != .dormant }
        if !multiFeed.isEmpty {
            let topics = multiFeed.prefix(2).map { "'\($0.topic)' (\($0.feedSpread) feeds)" }.joined(separator: ", ")
            insights.append("🌐 Cross-feed convergence: \(topics) appearing across multiple sources")
        }

        // Prediction accuracy
        if !outcomes.isEmpty {
            if accuracy >= 0.8 {
                insights.append("🎯 Prediction model performing well (\(Int(accuracy * 100))% accuracy over \(outcomes.count) predictions)")
            } else if accuracy < 0.4 {
                insights.append("⚠️ Prediction accuracy low (\(Int(accuracy * 100))%) — model needs more interaction data to calibrate")
            }
        }

        // High-confidence predictions
        let highConf = predictions.filter { $0.confidence == .high }
        if !highConf.isEmpty {
            let topics = highConf.prefix(3).map { "'\($0.topic)'" }.joined(separator: ", ")
            insights.append("🔮 High-confidence predictions: \(topics) — strong evidence of developing interest")
        }

        // Interest velocity acceleration
        let accelerating = trajectories.filter { $0.acceleration > 0.01 && $0.phase != .dormant }
        if accelerating.count >= 3 {
            insights.append("⚡ \(accelerating.count) interests are accelerating — you're in an active exploration phase")
        }

        // Dormant interests
        let dormant = trajectories.filter { $0.phase == .dormant }
        if dormant.count > trajectories.count / 2 && trajectories.count >= 4 {
            insights.append("💤 \(dormant.count)/\(trajectories.count) tracked interests are dormant — your active focus has narrowed")
        }

        // Deep engagement signal
        let deepDwell = trajectories.filter { $0.dwellAverage > 180 }
        if !deepDwell.isEmpty {
            let topics = deepDwell.prefix(2).map { "'\($0.topic)'" }.joined(separator: ", ")
            insights.append("📖 Deep engagement detected: \(topics) (avg dwell >3min) — these are genuine interests, not just passing clicks")
        }

        return insights
    }

    // MARK: - Utility

    /// Reset all engine state.
    public func reset() {
        signals.removeAll()
        outcomes.removeAll()
        candidates.removeAll()
    }

    /// Get summary statistics.
    public var stats: (signals: Int, topics: Int, outcomes: Int, candidates: Int) {
        let topics = Set(signals.map { $0.topic }).count
        return (signals.count, topics, outcomes.count, candidates.count)
    }
}
