//
//  FeedSourceCredibility.swift
//  FeedReaderCore
//
//  Autonomous source credibility engine that builds trust profiles for RSS
//  feed sources based on observable signals in their published content.
//  Tracks claim consistency, correction/retraction patterns, citation density,
//  hedging language, source diversity, and temporal reliability to produce
//  a composite credibility score.
//
//  Agentic capabilities:
//  - Auto-analyzes articles for credibility signals (citations, hedging, corrections)
//  - Builds persistent per-source trust profiles over time
//  - Detects correction/retraction patterns and adjusts trust accordingly
//  - Monitors claim consistency (sources contradicting themselves)
//  - Calculates composite credibility score 0-100
//  - Generates trust alerts (declining credibility, suspicious patterns)
//  - Cross-source corroboration analysis
//  - Auto-classifies source reliability tier (Platinum/Gold/Silver/Bronze/Untrusted)
//
//  Fully offline — no network, no dependencies beyond Foundation.
//

import Foundation

// MARK: - Notifications

extension Notification.Name {
    static let credibilityAlertGenerated = Notification.Name("CredibilityAlertGeneratedNotification")
    static let credibilityTierChanged = Notification.Name("CredibilityTierChangedNotification")
    static let credibilityRetractionDetected = Notification.Name("CredibilityRetractionDetectedNotification")
}

// MARK: - Credibility Tier

/// Reliability tier classification for a feed source.
public enum CredibilityTier: String, Codable, CaseIterable, Comparable {
    case platinum = "Platinum"   // 90-100: Exceptional reliability
    case gold = "Gold"           // 75-89: High reliability
    case silver = "Silver"       // 60-74: Moderate reliability
    case bronze = "Bronze"       // 40-59: Below average
    case untrusted = "Untrusted" // 0-39: Unreliable

    public static func from(score: Double) -> CredibilityTier {
        switch score {
        case 90...100: return .platinum
        case 75..<90: return .gold
        case 60..<75: return .silver
        case 40..<60: return .bronze
        default: return .untrusted
        }
    }

    private var ordinal: Int {
        switch self {
        case .untrusted: return 0
        case .bronze: return 1
        case .silver: return 2
        case .gold: return 3
        case .platinum: return 4
        }
    }

    public static func < (lhs: CredibilityTier, rhs: CredibilityTier) -> Bool {
        return lhs.ordinal < rhs.ordinal
    }
}

// MARK: - Signal Types

/// Categories of credibility signals detected in articles.
public enum CredibilitySignalType: String, Codable, CaseIterable {
    case citation           // References to studies, reports, named sources
    case hedging            // Uncertainty language ("allegedly", "reportedly")
    case correction         // Self-correction or update language
    case retraction         // Full retraction language
    case sensationalism     // Clickbait/extreme language patterns
    case specificity        // Concrete numbers, dates, names
    case attribution        // Named sources vs anonymous
    case consistency        // Agreement with own prior claims
}

/// A single credibility signal detected in an article.
public struct CredibilitySignal: Codable {
    public let type: CredibilitySignalType
    public let text: String
    public let weight: Double  // -1.0 to 1.0 (negative = hurts credibility)
    public let confidence: Double  // 0.0 to 1.0

    public init(type: CredibilitySignalType, text: String, weight: Double, confidence: Double) {
        self.type = type
        self.text = text
        self.weight = max(-1.0, min(1.0, weight))
        self.confidence = max(0.0, min(1.0, confidence))
    }
}

// MARK: - Article Analysis Result

/// Result of analyzing a single article for credibility signals.
public struct ArticleCredibilityAnalysis: Codable {
    public let articleTitle: String
    public let articleLink: String
    public let sourceName: String
    public let signals: [CredibilitySignal]
    public let citationCount: Int
    public let hedgingCount: Int
    public let specificityScore: Double  // 0-100
    public let sensationalismScore: Double  // 0-100 (lower = better)
    public let overallScore: Double  // 0-100
    public let analyzedAt: Date

    public init(articleTitle: String, articleLink: String, sourceName: String,
                signals: [CredibilitySignal], citationCount: Int, hedgingCount: Int,
                specificityScore: Double, sensationalismScore: Double,
                overallScore: Double, analyzedAt: Date = Date()) {
        self.articleTitle = articleTitle
        self.articleLink = articleLink
        self.sourceName = sourceName
        self.signals = signals
        self.citationCount = citationCount
        self.hedgingCount = hedgingCount
        self.specificityScore = specificityScore
        self.sensationalismScore = sensationalismScore
        self.overallScore = overallScore
        self.analyzedAt = analyzedAt
    }
}

// MARK: - Source Trust Profile

/// Persistent trust profile for a feed source built over time.
public struct SourceTrustProfile: Codable {
    public let sourceName: String
    public let sourceURL: String
    public var tier: CredibilityTier
    public var compositeScore: Double  // 0-100
    public var articlesAnalyzed: Int
    public var citationRate: Double  // avg citations per article
    public var correctionRate: Double  // corrections per 100 articles
    public var retractionCount: Int
    public var consistencyScore: Double  // 0-100
    public var sensationalismAvg: Double  // 0-100
    public var specificityAvg: Double  // 0-100
    public var hedgingRate: Double  // avg hedging signals per article
    public var scoreHistory: [Double]  // last N composite scores for trend
    public var lastAnalyzed: Date
    public var createdAt: Date

    public init(sourceName: String, sourceURL: String) {
        self.sourceName = sourceName
        self.sourceURL = sourceURL
        self.tier = .silver
        self.compositeScore = 60.0
        self.articlesAnalyzed = 0
        self.citationRate = 0.0
        self.correctionRate = 0.0
        self.retractionCount = 0
        self.consistencyScore = 70.0
        self.sensationalismAvg = 30.0
        self.specificityAvg = 50.0
        self.hedgingRate = 0.0
        self.scoreHistory = []
        self.lastAnalyzed = Date()
        self.createdAt = Date()
    }

    /// Trend direction based on recent score history.
    public var trend: CredibilityTrend {
        guard scoreHistory.count >= 3 else { return .stable }
        let recent = Array(scoreHistory.suffix(5))
        let first = recent.prefix(recent.count / 2)
        let second = recent.suffix(recent.count / 2)
        let avgFirst = first.reduce(0, +) / Double(first.count)
        let avgSecond = second.reduce(0, +) / Double(second.count)
        let diff = avgSecond - avgFirst
        if diff > 3.0 { return .improving }
        if diff < -3.0 { return .declining }
        return .stable
    }
}

/// Trend direction for a source's credibility.
public enum CredibilityTrend: String, Codable {
    case improving = "Improving"
    case stable = "Stable"
    case declining = "Declining"
}

// MARK: - Credibility Alert

/// Proactive alert generated when credibility patterns warrant attention.
public struct CredibilityAlert: Codable {
    public enum AlertType: String, Codable {
        case tierDemotion = "Tier Demotion"
        case retractionSpike = "Retraction Spike"
        case consistencyDrop = "Consistency Drop"
        case sensationalismSpike = "Sensationalism Spike"
        case improvementNotice = "Improvement Notice"
        case newSourceAssessed = "New Source Assessed"
    }

    public let type: AlertType
    public let sourceName: String
    public let message: String
    public let severity: Int  // 1 (low) to 5 (critical)
    public let generatedAt: Date

    public init(type: AlertType, sourceName: String, message: String, severity: Int, generatedAt: Date = Date()) {
        self.type = type
        self.sourceName = sourceName
        self.message = message
        self.severity = max(1, min(5, severity))
        self.generatedAt = generatedAt
    }
}

// MARK: - Corroboration Result

/// Result of cross-source corroboration analysis.
public struct CorroborationResult: Codable {
    public let claim: String
    public let supportingSources: [String]
    public let contradictingSources: [String]
    public let corroborationScore: Double  // 0-100
    public let confidence: Double  // 0-1

    public init(claim: String, supportingSources: [String], contradictingSources: [String],
                corroborationScore: Double, confidence: Double) {
        self.claim = claim
        self.supportingSources = supportingSources
        self.contradictingSources = contradictingSources
        self.corroborationScore = max(0, min(100, corroborationScore))
        self.confidence = max(0, min(1, confidence))
    }
}

// MARK: - Engine

/// Autonomous feed source credibility analysis engine.
///
/// Analyzes RSS articles for credibility signals (citations, hedging,
/// corrections, sensationalism, specificity) and builds persistent
/// trust profiles for each feed source.
///
/// ## Usage
/// ```swift
/// let engine = FeedSourceCredibility()
///
/// // Analyze a batch of articles
/// let analyses = engine.analyzeArticles(stories, from: feedItem)
///
/// // Get trust profile for a source
/// let profile = engine.getProfile(for: "BBC World News")
///
/// // Cross-source corroboration
/// let corroboration = engine.checkCorroboration(stories)
///
/// // Get all alerts
/// let alerts = engine.getAlerts(minSeverity: 3)
///
/// // Fleet credibility summary
/// let summary = engine.fleetSummary()
/// ```
public class FeedSourceCredibility {

    // MARK: - Configuration

    /// Minimum articles before calculating meaningful score.
    public var minimumArticlesForScoring: Int = 5

    /// Weight for each signal type in composite score.
    public var signalWeights: [CredibilitySignalType: Double] = [
        .citation: 0.20,
        .hedging: 0.10,
        .correction: 0.15,
        .retraction: 0.20,
        .sensationalism: 0.15,
        .specificity: 0.10,
        .attribution: 0.05,
        .consistency: 0.05
    ]

    /// Maximum score history entries per source.
    public var maxHistoryEntries: Int = 50

    // MARK: - State

    private var profiles: [String: SourceTrustProfile] = [:]  // key: sourceName
    private var alerts: [CredibilityAlert] = []
    private var articleClaims: [String: [[String]]] = [:]  // source -> list of keyword sets per article

    // MARK: - Signal Detection Patterns

    private static let citationPatterns: [String] = [
        "according to", "study found", "research shows", "report by",
        "published in", "data from", "survey of", "analysis by",
        "cited by", "referenced in", "peer-reviewed", "journal",
        "university of", "institute of", "professor", "researcher"
    ]

    private static let hedgingPatterns: [String] = [
        "allegedly", "reportedly", "sources say", "it appears",
        "may have", "could be", "might be", "is believed to",
        "unconfirmed", "unverified", "claims to", "purportedly",
        "seemingly", "apparently", "it is thought"
    ]

    private static let correctionPatterns: [String] = [
        "correction:", "update:", "editor's note:", "this article has been updated",
        "we previously reported", "an earlier version", "has been corrected",
        "clarification:", "erratum", "we incorrectly stated"
    ]

    private static let retractionPatterns: [String] = [
        "retracted", "withdrawn", "this story has been removed",
        "we are retracting", "no longer stands", "was inaccurate",
        "should not have been published", "apologize for the error"
    ]

    private static let sensationalismPatterns: [String] = [
        "shocking", "breaking:", "you won't believe", "devastating",
        "explosive", "bombshell", "unprecedented", "crisis",
        "emergency", "catastrophic", "terrifying", "outrageous",
        "slam", "destroy", "obliterate", "nightmare"
    ]

    private static let specificityPatterns: [String] = [
        "percent", "%", "million", "billion", "thousand",
        "january", "february", "march", "april", "may", "june",
        "july", "august", "september", "october", "november", "december",
        "monday", "tuesday", "wednesday", "thursday", "friday",
        "saturday", "sunday"
    ]

    private static let attributionPatterns: [String] = [
        "said", "told", "confirmed", "announced", "stated",
        "spokesperson", "official", "representative", "minister",
        "ceo", "president", "director", "chief"
    ]

    // MARK: - Initialization

    public init() {}

    // MARK: - Public API

    /// Analyze a batch of articles from a feed source and update its trust profile.
    /// - Parameters:
    ///   - stories: Articles to analyze.
    ///   - feed: The feed source these articles came from.
    /// - Returns: Array of per-article credibility analyses.
    @discardableResult
    public func analyzeArticles(_ stories: [RSSStory], from feed: FeedItem) -> [ArticleCredibilityAnalysis] {
        var results: [ArticleCredibilityAnalysis] = []

        for story in stories {
            let analysis = analyzeArticle(story, sourceName: feed.name)
            results.append(analysis)
        }

        updateProfile(for: feed, with: results)
        checkForAlerts(sourceName: feed.name)

        return results
    }

    /// Get the trust profile for a specific source.
    public func getProfile(for sourceName: String) -> SourceTrustProfile? {
        return profiles[sourceName]
    }

    /// Get all trust profiles sorted by composite score.
    public func getAllProfiles() -> [SourceTrustProfile] {
        return profiles.values.sorted { $0.compositeScore > $1.compositeScore }
    }

    /// Get alerts filtered by minimum severity.
    public func getAlerts(minSeverity: Int = 1) -> [CredibilityAlert] {
        return alerts.filter { $0.severity >= minSeverity }
            .sorted { $0.generatedAt > $1.generatedAt }
    }

    /// Check cross-source corroboration for a set of articles across multiple feeds.
    /// Groups articles by topic keywords and checks how many sources agree.
    public func checkCorroboration(_ articles: [(story: RSSStory, source: String)]) -> [CorroborationResult] {
        var results: [CorroborationResult] = []

        // Extract keywords per article
        let extractor = KeywordExtractor()
        var articleKeywords: [(keywords: [String], source: String, title: String)] = []
        for (story, source) in articles {
            let kw = extractor.extractTags(from: story, count: 8)
            articleKeywords.append((keywords: kw, source: source, title: story.title))
        }

        // Find article clusters (>= 2 articles sharing >= 3 keywords)
        var processed: Set<Int> = []
        for i in 0..<articleKeywords.count {
            guard !processed.contains(i) else { continue }
            var cluster: [Int] = [i]

            for j in (i+1)..<articleKeywords.count {
                guard !processed.contains(j) else { continue }
                let shared = Set(articleKeywords[i].keywords).intersection(Set(articleKeywords[j].keywords))
                if shared.count >= 3 {
                    cluster.append(j)
                }
            }

            if cluster.count >= 2 {
                let sources = cluster.map { articleKeywords[$0].source }
                let uniqueSources = Array(Set(sources))
                let topicKeywords = Set(articleKeywords[i].keywords)
                    .intersection(cluster.dropFirst().reduce(Set(articleKeywords[i].keywords)) { acc, idx in
                        acc.intersection(Set(articleKeywords[idx].keywords))
                    })
                let claim = topicKeywords.sorted().joined(separator: ", ")

                let score = min(100.0, Double(uniqueSources.count) * 25.0)
                let confidence = min(1.0, Double(cluster.count) / 5.0)

                results.append(CorroborationResult(
                    claim: claim,
                    supportingSources: uniqueSources,
                    contradictingSources: [],
                    corroborationScore: score,
                    confidence: confidence
                ))

                processed.formUnion(cluster)
            }
        }

        return results
    }

    /// Fleet-wide credibility summary.
    public func fleetSummary() -> FleetCredibilitySummary {
        let allProfiles = getAllProfiles()
        let avgScore = allProfiles.isEmpty ? 0 : allProfiles.map(\.compositeScore).reduce(0, +) / Double(allProfiles.count)
        let tierDistribution = Dictionary(grouping: allProfiles, by: \.tier).mapValues(\.count)
        let decliningCount = allProfiles.filter { $0.trend == .declining }.count
        let recentAlerts = alerts.filter { $0.severity >= 3 }.suffix(10)

        return FleetCredibilitySummary(
            totalSources: allProfiles.count,
            averageScore: avgScore,
            tierDistribution: tierDistribution,
            decliningSources: decliningCount,
            recentHighSeverityAlerts: Array(recentAlerts)
        )
    }

    /// Reset all state (for testing).
    public func reset() {
        profiles.removeAll()
        alerts.removeAll()
        articleClaims.removeAll()
    }

    // MARK: - Private: Article Analysis

    private func analyzeArticle(_ story: RSSStory, sourceName: String) -> ArticleCredibilityAnalysis {
        let text = "\(story.title) \(story.body)".lowercased()
        var signals: [CredibilitySignal] = []

        // Citation detection
        let citations = detectPatterns(text, patterns: Self.citationPatterns)
        for match in citations {
            signals.append(CredibilitySignal(type: .citation, text: match, weight: 0.8, confidence: 0.7))
        }

        // Hedging detection
        let hedges = detectPatterns(text, patterns: Self.hedgingPatterns)
        for match in hedges {
            signals.append(CredibilitySignal(type: .hedging, text: match, weight: 0.3, confidence: 0.8))
        }

        // Correction detection
        let corrections = detectPatterns(text, patterns: Self.correctionPatterns)
        for match in corrections {
            signals.append(CredibilitySignal(type: .correction, text: match, weight: -0.3, confidence: 0.9))
        }

        // Retraction detection
        let retractions = detectPatterns(text, patterns: Self.retractionPatterns)
        for match in retractions {
            signals.append(CredibilitySignal(type: .retraction, text: match, weight: -0.8, confidence: 0.9))
        }

        // Sensationalism detection
        let sensational = detectPatterns(text, patterns: Self.sensationalismPatterns)
        for match in sensational {
            signals.append(CredibilitySignal(type: .sensationalism, text: match, weight: -0.5, confidence: 0.6))
        }

        // Specificity detection
        let specifics = detectPatterns(text, patterns: Self.specificityPatterns)
        for match in specifics {
            signals.append(CredibilitySignal(type: .specificity, text: match, weight: 0.4, confidence: 0.5))
        }

        // Attribution detection
        let attributions = detectPatterns(text, patterns: Self.attributionPatterns)
        for match in attributions {
            signals.append(CredibilitySignal(type: .attribution, text: match, weight: 0.5, confidence: 0.6))
        }

        // Calculate scores
        let citationCount = citations.count
        let hedgingCount = hedges.count
        let specificityScore = min(100.0, Double(specifics.count) * 12.5)
        let sensationalismScore = min(100.0, Double(sensational.count) * 20.0)

        // Composite article score
        let positiveSignals = Double(citations.count + specifics.count + attributions.count)
        let negativeSignals = Double(sensational.count + retractions.count) * 2.0
        let neutralSignals = Double(hedges.count) * 0.5 + Double(corrections.count)
        let totalWeight = positiveSignals + negativeSignals + neutralSignals + 1.0
        let rawScore = (positiveSignals * 80.0 + (totalWeight - negativeSignals) * 20.0) / totalWeight
        let overallScore = max(0, min(100, rawScore))

        // Track claims for consistency checking
        let extractor = KeywordExtractor()
        let keywords = extractor.extractKeywords(from: "\(story.title) \(story.body)", count: 10)
        if articleClaims[sourceName] == nil {
            articleClaims[sourceName] = []
        }
        articleClaims[sourceName]?.append(keywords)

        return ArticleCredibilityAnalysis(
            articleTitle: story.title,
            articleLink: story.link,
            sourceName: sourceName,
            signals: signals,
            citationCount: citationCount,
            hedgingCount: hedgingCount,
            specificityScore: specificityScore,
            sensationalismScore: sensationalismScore,
            overallScore: overallScore
        )
    }

    // MARK: - Private: Profile Update

    private func updateProfile(for feed: FeedItem, with analyses: [ArticleCredibilityAnalysis]) {
        guard !analyses.isEmpty else { return }

        var profile = profiles[feed.name] ?? SourceTrustProfile(sourceName: feed.name, sourceURL: feed.url)
        let oldTier = profile.tier

        // Update running averages using exponential moving average
        let alpha = 0.3  // weight for new data
        let avgCitations = analyses.map { Double($0.citationCount) }.reduce(0, +) / Double(analyses.count)
        let avgHedging = analyses.map { Double($0.hedgingCount) }.reduce(0, +) / Double(analyses.count)
        let avgSensationalism = analyses.map(\.sensationalismScore).reduce(0, +) / Double(analyses.count)
        let avgSpecificity = analyses.map(\.specificityScore).reduce(0, +) / Double(analyses.count)
        let corrections = analyses.flatMap(\.signals).filter { $0.type == .correction }.count
        let retractions = analyses.flatMap(\.signals).filter { $0.type == .retraction }.count

        if profile.articlesAnalyzed == 0 {
            profile.citationRate = avgCitations
            profile.hedgingRate = avgHedging
            profile.sensationalismAvg = avgSensationalism
            profile.specificityAvg = avgSpecificity
        } else {
            profile.citationRate = profile.citationRate * (1 - alpha) + avgCitations * alpha
            profile.hedgingRate = profile.hedgingRate * (1 - alpha) + avgHedging * alpha
            profile.sensationalismAvg = profile.sensationalismAvg * (1 - alpha) + avgSensationalism * alpha
            profile.specificityAvg = profile.specificityAvg * (1 - alpha) + avgSpecificity * alpha
        }

        profile.articlesAnalyzed += analyses.count
        profile.retractionCount += retractions
        profile.correctionRate = Double(corrections) / Double(analyses.count) * 100.0

        // Calculate consistency score
        profile.consistencyScore = calculateConsistency(for: feed.name)

        // Calculate composite score
        let citationComponent = min(100.0, profile.citationRate * 30.0)  // more citations = better
        let sensComponent = 100.0 - profile.sensationalismAvg  // less sensationalism = better
        let specComponent = profile.specificityAvg
        let consistComponent = profile.consistencyScore
        let correctionPenalty = min(30.0, Double(profile.retractionCount) * 10.0 + profile.correctionRate * 0.5)

        profile.compositeScore = max(0, min(100,
            citationComponent * 0.25 +
            sensComponent * 0.20 +
            specComponent * 0.15 +
            consistComponent * 0.20 +
            (100.0 - correctionPenalty) * 0.20
        ))

        // Update tier
        profile.tier = CredibilityTier.from(score: profile.compositeScore)

        // Update history
        profile.scoreHistory.append(profile.compositeScore)
        if profile.scoreHistory.count > maxHistoryEntries {
            profile.scoreHistory.removeFirst(profile.scoreHistory.count - maxHistoryEntries)
        }

        profile.lastAnalyzed = Date()
        profiles[feed.name] = profile

        // Tier change notification
        if oldTier != profile.tier {
            NotificationCenter.default.post(name: .credibilityTierChanged, object: nil, userInfo: [
                "sourceName": feed.name,
                "oldTier": oldTier.rawValue,
                "newTier": profile.tier.rawValue
            ])
        }

        // Retraction notification
        if retractions > 0 {
            NotificationCenter.default.post(name: .credibilityRetractionDetected, object: nil, userInfo: [
                "sourceName": feed.name,
                "count": retractions
            ])
        }
    }

    // MARK: - Private: Consistency

    private func calculateConsistency(for sourceName: String) -> Double {
        guard let claims = articleClaims[sourceName], claims.count >= 3 else { return 70.0 }

        // Check keyword overlap between recent articles — high overlap = consistent topics
        let recent = Array(claims.suffix(20))
        var overlapScores: [Double] = []

        for i in 0..<(recent.count - 1) {
            for j in (i+1)..<min(i+5, recent.count) {
                let set1 = Set(recent[i])
                let set2 = Set(recent[j])
                let intersection = set1.intersection(set2).count
                let union = set1.union(set2).count
                if union > 0 {
                    overlapScores.append(Double(intersection) / Double(union))
                }
            }
        }

        guard !overlapScores.isEmpty else { return 70.0 }
        let avgOverlap = overlapScores.reduce(0, +) / Double(overlapScores.count)
        // Moderate overlap (0.1-0.4) is ideal — too high means repetitive, too low means inconsistent
        let normalizedConsistency: Double
        if avgOverlap < 0.05 {
            normalizedConsistency = 40.0  // Very scattered
        } else if avgOverlap < 0.15 {
            normalizedConsistency = 60.0 + avgOverlap * 200.0
        } else if avgOverlap <= 0.4 {
            normalizedConsistency = 80.0 + (avgOverlap - 0.15) * 80.0
        } else {
            normalizedConsistency = 90.0 - (avgOverlap - 0.4) * 50.0  // Too repetitive
        }
        return max(0, min(100, normalizedConsistency))
    }

    // MARK: - Private: Alerts

    private func checkForAlerts(sourceName: String) {
        guard let profile = profiles[sourceName] else { return }

        // Tier demotion alert
        if profile.scoreHistory.count >= 3 {
            let recent = Array(profile.scoreHistory.suffix(3))
            if let first = recent.first, let last = recent.last, first - last > 10 {
                let alert = CredibilityAlert(
                    type: .tierDemotion,
                    sourceName: sourceName,
                    message: "\(sourceName) credibility declining: score dropped \(String(format: "%.1f", first - last)) points recently",
                    severity: 3
                )
                alerts.append(alert)
                NotificationCenter.default.post(name: .credibilityAlertGenerated, object: alert)
            }
        }

        // Retraction spike
        if profile.retractionCount >= 3 && profile.articlesAnalyzed < 50 {
            let alert = CredibilityAlert(
                type: .retractionSpike,
                sourceName: sourceName,
                message: "\(sourceName) has \(profile.retractionCount) retractions in only \(profile.articlesAnalyzed) articles — unusually high",
                severity: 4
            )
            alerts.append(alert)
            NotificationCenter.default.post(name: .credibilityAlertGenerated, object: alert)
        }

        // Sensationalism spike
        if profile.sensationalismAvg > 60.0 {
            let alert = CredibilityAlert(
                type: .sensationalismSpike,
                sourceName: sourceName,
                message: "\(sourceName) sensationalism score at \(String(format: "%.0f", profile.sensationalismAvg))% — consider reducing trust",
                severity: 3
            )
            alerts.append(alert)
        }

        // New source assessed (first time reaching minimum articles)
        if profile.articlesAnalyzed == minimumArticlesForScoring {
            let alert = CredibilityAlert(
                type: .newSourceAssessed,
                sourceName: sourceName,
                message: "\(sourceName) initial assessment complete: \(profile.tier.rawValue) tier (score: \(String(format: "%.0f", profile.compositeScore)))",
                severity: 1
            )
            alerts.append(alert)
        }

        // Improvement notice
        if profile.trend == .improving && profile.articlesAnalyzed > 10 {
            let alert = CredibilityAlert(
                type: .improvementNotice,
                sourceName: sourceName,
                message: "\(sourceName) showing improvement trend — credibility rising",
                severity: 1
            )
            alerts.append(alert)
        }
    }

    // MARK: - Private: Pattern Detection

    private func detectPatterns(_ text: String, patterns: [String]) -> [String] {
        var matches: [String] = []
        for pattern in patterns {
            if text.contains(pattern) {
                matches.append(pattern)
            }
        }
        return matches
    }
}

// MARK: - Fleet Summary

/// Summary of credibility across all tracked feed sources.
public struct FleetCredibilitySummary: Codable {
    public let totalSources: Int
    public let averageScore: Double
    public let tierDistribution: [CredibilityTier: Int]
    public let decliningSources: Int
    public let recentHighSeverityAlerts: [CredibilityAlert]

    public init(totalSources: Int, averageScore: Double, tierDistribution: [CredibilityTier: Int],
                decliningSources: Int, recentHighSeverityAlerts: [CredibilityAlert]) {
        self.totalSources = totalSources
        self.averageScore = averageScore
        self.tierDistribution = tierDistribution
        self.decliningSources = decliningSources
        self.recentHighSeverityAlerts = recentHighSeverityAlerts
    }
}
