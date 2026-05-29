//
//  FeedSourceDiversityGuardian.swift
//  FeedReaderCore
//
//  Agentic echo-chamber detection and source diversity advisor.
//  Monitors reading patterns across multiple diversity axes:
//
//  - Topic concentration (are you reading only one subject?)
//  - Source concentration (are few feeds dominating your time?)
//  - Geographic diversity (domestic vs international perspectives)
//  - Publication type balance (mainstream, independent, academic, blog)
//  - Recency bias (only reading breaking news vs deeper analysis?)
//
//  The guardian proactively flags when diversity drops below healthy
//  thresholds and recommends corrective actions (new feeds, specific
//  articles from underrepresented categories, reading challenges).
//
//  Usage:
//  ```swift
//  let guardian = FeedSourceDiversityGuardian()
//
//  let report = guardian.analyze(
//      readingHistory: recentArticles,
//      subscriptions: allFeeds,
//      config: .default
//  )
//
//  print(report.overallScore)        // 0-100 diversity health
//  print(report.grade)               // A-F
//  print(report.axes)                // per-axis breakdown
//  print(report.alerts)              // proactive warnings
//  print(report.recommendations)     // actionable suggestions
//  print(report.echoChamberRisk)     // none/low/moderate/high/severe
//  ```
//
//  All processing is on-device. No network calls or external deps.
//

import Foundation

// MARK: - Models

/// A record of a read article for diversity analysis.
public struct DiversityReadRecord: Sendable {
    public let articleId: String
    public let title: String
    public let feedName: String
    public let topics: [String]
    public let region: SourceRegion
    public let publicationType: PublicationType
    public let contentDepth: ContentDepth
    public let readAt: Date

    public init(
        articleId: String,
        title: String,
        feedName: String,
        topics: [String] = [],
        region: SourceRegion = .domestic,
        publicationType: PublicationType = .mainstream,
        contentDepth: ContentDepth = .standard,
        readAt: Date = Date()
    ) {
        self.articleId = articleId
        self.title = title
        self.feedName = feedName
        self.topics = topics
        self.region = region
        self.publicationType = publicationType
        self.contentDepth = contentDepth
        self.readAt = readAt
    }
}

/// Geographic region of a source.
public enum SourceRegion: String, CaseIterable, Sendable {
    case domestic      = "domestic"
    case northAmerica  = "north_america"
    case europe        = "europe"
    case asia          = "asia"
    case africa        = "africa"
    case latinAmerica  = "latin_america"
    case oceania       = "oceania"
    case middleEast    = "middle_east"
}

/// Publication type classification.
public enum PublicationType: String, CaseIterable, Sendable {
    case mainstream   = "mainstream"
    case independent  = "independent"
    case academic     = "academic"
    case blog         = "blog"
    case newsletter   = "newsletter"
    case government   = "government"
    case nonprofit    = "nonprofit"
}

/// Content depth classification.
public enum ContentDepth: String, CaseIterable, Sendable {
    case breaking    = "breaking"
    case standard    = "standard"
    case longform    = "longform"
    case analysis    = "analysis"
    case research    = "research"
}

/// Echo chamber risk level.
public enum EchoChamberRisk: String, Sendable, Comparable {
    case none     = "none"
    case low      = "low"
    case moderate = "moderate"
    case high     = "high"
    case severe   = "severe"

    public static func < (lhs: EchoChamberRisk, rhs: EchoChamberRisk) -> Bool {
        lhs.numericValue < rhs.numericValue
    }

    var numericValue: Int {
        switch self {
        case .none:     return 0
        case .low:      return 1
        case .moderate: return 2
        case .high:     return 3
        case .severe:   return 4
        }
    }
}

/// Diversity axis identifier.
public enum DiversityAxis: String, CaseIterable, Sendable {
    case topicConcentration   = "topic_concentration"
    case sourceConcentration  = "source_concentration"
    case geographicSpread     = "geographic_spread"
    case publicationTypeSpread = "publication_type_spread"
    case contentDepthBalance  = "content_depth_balance"
}

/// Score for a single diversity axis.
public struct AxisScore: Sendable {
    public let axis: DiversityAxis
    public let score: Double         // 0-100
    public let grade: String         // A-F
    public let dominantValue: String // e.g. "technology" or "TechCrunch"
    public let dominantPct: Double   // % of readings in dominant category
    public let uniqueCount: Int      // distinct values seen
    public let insight: String       // human-readable observation
}

/// A proactive diversity alert.
public struct DiversityAlert: Sendable {
    public enum Severity: String, Sendable {
        case info    = "info"
        case warning = "warning"
        case critical = "critical"
    }

    public let severity: Severity
    public let axis: DiversityAxis
    public let message: String
    public let triggerValue: Double  // the metric that fired the alert
}

/// A recommendation to improve diversity.
public struct DiversityRecommendation: Sendable {
    public enum ActionType: String, Sendable {
        case subscribeFeed        = "subscribe_feed"
        case readFromCategory     = "read_from_category"
        case diversityChallenge   = "diversity_challenge"
        case reduceSource         = "reduce_source"
        case exploreRegion        = "explore_region"
        case tryContentDepth      = "try_content_depth"
    }

    public let actionType: ActionType
    public let priority: Int         // 1-5, 1 = highest
    public let title: String
    public let reason: String
    public let targetAxis: DiversityAxis
}

/// Full diversity analysis report.
public struct DiversityReport: Sendable {
    public let overallScore: Double       // 0-100
    public let grade: String              // A-F
    public let echoChamberRisk: EchoChamberRisk
    public let axes: [AxisScore]
    public let alerts: [DiversityAlert]
    public let recommendations: [DiversityRecommendation]
    public let articleCount: Int
    public let analysisWindowDays: Int
    public let generatedAt: Date

    /// Human-readable summary.
    public var summary: String {
        let riskStr = echoChamberRisk.rawValue
        return "Diversity grade \(grade) (score \(Int(overallScore))/100). " +
               "Echo chamber risk: \(riskStr). " +
               "\(alerts.count) alert(s), \(recommendations.count) recommendation(s). " +
               "Based on \(articleCount) articles over \(analysisWindowDays) days."
    }
}

/// Configuration for the guardian.
public struct DiversityGuardianConfig: Sendable {
    /// Minimum articles needed for meaningful analysis.
    public let minArticlesForAnalysis: Int
    /// Days to look back for reading history.
    public let windowDays: Int
    /// Threshold (0-1) above which a single category dominance triggers alert.
    public let concentrationAlertThreshold: Double
    /// Weight per axis for overall score.
    public let axisWeights: [DiversityAxis: Double]

    public static let `default` = DiversityGuardianConfig(
        minArticlesForAnalysis: 5,
        windowDays: 30,
        concentrationAlertThreshold: 0.6,
        axisWeights: [
            .topicConcentration: 0.30,
            .sourceConcentration: 0.25,
            .geographicSpread: 0.20,
            .publicationTypeSpread: 0.15,
            .contentDepthBalance: 0.10
        ]
    )

    public init(
        minArticlesForAnalysis: Int = 5,
        windowDays: Int = 30,
        concentrationAlertThreshold: Double = 0.6,
        axisWeights: [DiversityAxis: Double]? = nil
    ) {
        self.minArticlesForAnalysis = minArticlesForAnalysis
        self.windowDays = windowDays
        self.concentrationAlertThreshold = concentrationAlertThreshold
        self.axisWeights = axisWeights ?? DiversityGuardianConfig.default.axisWeights
    }
}

// MARK: - Guardian

/// Agentic source diversity monitor and echo-chamber detector.
public final class FeedSourceDiversityGuardian: Sendable {

    public init() {}

    /// Analyze reading history for diversity health.
    public func analyze(
        readingHistory: [DiversityReadRecord],
        config: DiversityGuardianConfig = .default
    ) -> DiversityReport {
        let now = Date()
        let windowStart = Calendar.current.date(
            byAdding: .day, value: -config.windowDays, to: now
        ) ?? now

        let filtered = readingHistory.filter { $0.readAt >= windowStart }

        guard filtered.count >= config.minArticlesForAnalysis else {
            return insufficientDataReport(
                articleCount: filtered.count,
                windowDays: config.windowDays,
                generatedAt: now
            )
        }

        let topicAxis = scoreTopicConcentration(filtered, config: config)
        let sourceAxis = scoreSourceConcentration(filtered, config: config)
        let geoAxis = scoreGeographicSpread(filtered, config: config)
        let pubAxis = scorePublicationTypeSpread(filtered, config: config)
        let depthAxis = scoreContentDepthBalance(filtered, config: config)

        let axes = [topicAxis, sourceAxis, geoAxis, pubAxis, depthAxis]

        // Weighted overall score
        var overallScore: Double = 0
        for axis in axes {
            let weight = config.axisWeights[axis.axis] ?? 0.2
            overallScore += axis.score * weight
        }
        overallScore = min(100, max(0, overallScore))

        let grade = gradeFromScore(overallScore)
        let risk = riskFromScore(overallScore)
        let alerts = generateAlerts(axes: axes, config: config)
        let recommendations = generateRecommendations(axes: axes, risk: risk)

        return DiversityReport(
            overallScore: overallScore,
            grade: grade,
            echoChamberRisk: risk,
            axes: axes,
            alerts: alerts,
            recommendations: recommendations,
            articleCount: filtered.count,
            analysisWindowDays: config.windowDays,
            generatedAt: now
        )
    }

    // MARK: - Axis Scoring

    private func scoreTopicConcentration(
        _ records: [DiversityReadRecord],
        config: DiversityGuardianConfig
    ) -> AxisScore {
        var topicCounts: [String: Int] = [:]
        for r in records {
            let topics = r.topics.isEmpty ? ["uncategorized"] : r.topics
            for t in topics {
                topicCounts[t.lowercased(), default: 0] += 1
            }
        }
        return concentrationAxisScore(
            axis: .topicConcentration,
            counts: topicCounts,
            total: records.count,
            config: config
        )
    }

    private func scoreSourceConcentration(
        _ records: [DiversityReadRecord],
        config: DiversityGuardianConfig
    ) -> AxisScore {
        var sourceCounts: [String: Int] = [:]
        for r in records {
            sourceCounts[r.feedName, default: 0] += 1
        }
        return concentrationAxisScore(
            axis: .sourceConcentration,
            counts: sourceCounts,
            total: records.count,
            config: config
        )
    }

    private func scoreGeographicSpread(
        _ records: [DiversityReadRecord],
        config: DiversityGuardianConfig
    ) -> AxisScore {
        var regionCounts: [String: Int] = [:]
        for r in records {
            regionCounts[r.region.rawValue, default: 0] += 1
        }
        return concentrationAxisScore(
            axis: .geographicSpread,
            counts: regionCounts,
            total: records.count,
            config: config
        )
    }

    private func scorePublicationTypeSpread(
        _ records: [DiversityReadRecord],
        config: DiversityGuardianConfig
    ) -> AxisScore {
        var typeCounts: [String: Int] = [:]
        for r in records {
            typeCounts[r.publicationType.rawValue, default: 0] += 1
        }
        return concentrationAxisScore(
            axis: .publicationTypeSpread,
            counts: typeCounts,
            total: records.count,
            config: config
        )
    }

    private func scoreContentDepthBalance(
        _ records: [DiversityReadRecord],
        config: DiversityGuardianConfig
    ) -> AxisScore {
        var depthCounts: [String: Int] = [:]
        for r in records {
            depthCounts[r.contentDepth.rawValue, default: 0] += 1
        }
        return concentrationAxisScore(
            axis: .contentDepthBalance,
            counts: depthCounts,
            total: records.count,
            config: config
        )
    }

    /// Generic concentration scorer using normalized Shannon entropy.
    private func concentrationAxisScore(
        axis: DiversityAxis,
        counts: [String: Int],
        total: Int,
        config: DiversityGuardianConfig
    ) -> AxisScore {
        guard total > 0, !counts.isEmpty else {
            return AxisScore(
                axis: axis, score: 50, grade: "C",
                dominantValue: "unknown", dominantPct: 0,
                uniqueCount: 0, insight: "No data available."
            )
        }

        // Shannon entropy normalized to 0-1
        let n = Double(total)
        var entropy: Double = 0
        for (_, count) in counts {
            let p = Double(count) / n
            if p > 0 { entropy -= p * log2(p) }
        }
        let maxEntropy = log2(Double(max(counts.count, 2)))
        let normalizedEntropy = maxEntropy > 0 ? entropy / maxEntropy : 0

        // Score: higher entropy = more diverse = higher score
        let score = min(100, max(0, normalizedEntropy * 100))

        let sorted = counts.sorted { $0.value > $1.value }
        let dominant = sorted.first!
        let dominantPct = Double(dominant.value) / n

        let grade = gradeFromScore(score)
        let insight = insightForAxis(axis, score: score, dominant: dominant.key, dominantPct: dominantPct)

        return AxisScore(
            axis: axis,
            score: score,
            grade: grade,
            dominantValue: dominant.key,
            dominantPct: dominantPct,
            uniqueCount: counts.count,
            insight: insight
        )
    }

    // MARK: - Risk & Grade

    private func gradeFromScore(_ score: Double) -> String {
        switch score {
        case 80...: return "A"
        case 65..<80: return "B"
        case 50..<65: return "C"
        case 35..<50: return "D"
        default:      return "F"
        }
    }

    private func riskFromScore(_ score: Double) -> EchoChamberRisk {
        switch score {
        case 80...: return .none
        case 65..<80: return .low
        case 45..<65: return .moderate
        case 25..<45: return .high
        default:      return .severe
        }
    }

    // MARK: - Alerts

    private func generateAlerts(
        axes: [AxisScore],
        config: DiversityGuardianConfig
    ) -> [DiversityAlert] {
        var alerts: [DiversityAlert] = []

        for axis in axes {
            if axis.dominantPct >= config.concentrationAlertThreshold {
                let severity: DiversityAlert.Severity =
                    axis.dominantPct >= 0.8 ? .critical :
                    axis.dominantPct >= 0.6 ? .warning : .info

                alerts.append(DiversityAlert(
                    severity: severity,
                    axis: axis.axis,
                    message: "\(axisLabel(axis.axis)): '\(axis.dominantValue)' dominates at \(Int(axis.dominantPct * 100))%",
                    triggerValue: axis.dominantPct
                ))
            }

            if axis.score < 35 {
                alerts.append(DiversityAlert(
                    severity: .critical,
                    axis: axis.axis,
                    message: "\(axisLabel(axis.axis)) score critically low (\(Int(axis.score))/100)",
                    triggerValue: axis.score
                ))
            }
        }

        return alerts.sorted { a, b in
            severityOrder(a.severity) > severityOrder(b.severity)
        }
    }

    private func severityOrder(_ s: DiversityAlert.Severity) -> Int {
        switch s {
        case .critical: return 3
        case .warning:  return 2
        case .info:     return 1
        }
    }

    // MARK: - Recommendations

    private func generateRecommendations(
        axes: [AxisScore],
        risk: EchoChamberRisk
    ) -> [DiversityRecommendation] {
        var recs: [DiversityRecommendation] = []

        for axis in axes where axis.score < 65 {
            let priority = axis.score < 35 ? 1 : axis.score < 50 ? 2 : 3

            switch axis.axis {
            case .topicConcentration:
                recs.append(DiversityRecommendation(
                    actionType: .readFromCategory,
                    priority: priority,
                    title: "Explore topics beyond '\(axis.dominantValue)'",
                    reason: "Your reading is \(Int(axis.dominantPct * 100))% concentrated in '\(axis.dominantValue)'. Try branching into adjacent topics.",
                    targetAxis: axis.axis
                ))
            case .sourceConcentration:
                recs.append(DiversityRecommendation(
                    actionType: .subscribeFeed,
                    priority: priority,
                    title: "Add feeds beyond '\(axis.dominantValue)'",
                    reason: "'\(axis.dominantValue)' makes up \(Int(axis.dominantPct * 100))% of your reading. Subscribe to alternative sources for balance.",
                    targetAxis: axis.axis
                ))
            case .geographicSpread:
                recs.append(DiversityRecommendation(
                    actionType: .exploreRegion,
                    priority: priority,
                    title: "Read international perspectives",
                    reason: "\(Int(axis.dominantPct * 100))% of sources are '\(axis.dominantValue)'. Seek out coverage from other regions.",
                    targetAxis: axis.axis
                ))
            case .publicationTypeSpread:
                recs.append(DiversityRecommendation(
                    actionType: .subscribeFeed,
                    priority: priority,
                    title: "Diversify publication types",
                    reason: "Heavy reliance on '\(axis.dominantValue)' sources. Try academic papers, independent media, or newsletters.",
                    targetAxis: axis.axis
                ))
            case .contentDepthBalance:
                recs.append(DiversityRecommendation(
                    actionType: .tryContentDepth,
                    priority: priority,
                    title: "Vary your reading depth",
                    reason: "Most reading is '\(axis.dominantValue)'. Mix in some \(axis.dominantValue == "breaking" ? "longform analysis" : "current news") for balance.",
                    targetAxis: axis.axis
                ))
            }
        }

        // Add a diversity challenge if risk is high
        if risk >= .high {
            recs.append(DiversityRecommendation(
                actionType: .diversityChallenge,
                priority: 1,
                title: "7-day diversity challenge",
                reason: "Your echo chamber risk is \(risk.rawValue). Try reading one article per day from an unfamiliar source or topic.",
                targetAxis: .topicConcentration
            ))
        }

        return recs.sorted { $0.priority < $1.priority }
    }

    // MARK: - Helpers

    private func insufficientDataReport(
        articleCount: Int,
        windowDays: Int,
        generatedAt: Date
    ) -> DiversityReport {
        DiversityReport(
            overallScore: 50,
            grade: "C",
            echoChamberRisk: .low,
            axes: [],
            alerts: [DiversityAlert(
                severity: .info,
                axis: .topicConcentration,
                message: "Insufficient reading history (\(articleCount) articles). Need at least 5 for analysis.",
                triggerValue: Double(articleCount)
            )],
            recommendations: [DiversityRecommendation(
                actionType: .readFromCategory,
                priority: 3,
                title: "Read more to enable diversity tracking",
                reason: "The guardian needs at least 5 articles in the analysis window to provide meaningful insights.",
                targetAxis: .topicConcentration
            )],
            articleCount: articleCount,
            analysisWindowDays: windowDays,
            generatedAt: generatedAt
        )
    }

    private func insightForAxis(
        _ axis: DiversityAxis,
        score: Double,
        dominant: String,
        dominantPct: Double
    ) -> String {
        let pctStr = "\(Int(dominantPct * 100))%"
        switch axis {
        case .topicConcentration:
            if score >= 80 { return "Healthy topic variety across your reading." }
            return "'\(dominant)' dominates at \(pctStr). Consider branching out."
        case .sourceConcentration:
            if score >= 80 { return "Well-distributed across multiple sources." }
            return "'\(dominant)' accounts for \(pctStr) of your reading."
        case .geographicSpread:
            if score >= 80 { return "Good international perspective coverage." }
            return "Reading heavily skewed toward '\(dominant)' (\(pctStr))."
        case .publicationTypeSpread:
            if score >= 80 { return "Balanced mix of publication types." }
            return "'\(dominant)' type dominates at \(pctStr)."
        case .contentDepthBalance:
            if score >= 80 { return "Good balance between quick reads and deep dives." }
            return "Content depth concentrated in '\(dominant)' (\(pctStr))."
        }
    }

    private func axisLabel(_ axis: DiversityAxis) -> String {
        switch axis {
        case .topicConcentration:    return "Topic concentration"
        case .sourceConcentration:   return "Source concentration"
        case .geographicSpread:      return "Geographic spread"
        case .publicationTypeSpread: return "Publication type"
        case .contentDepthBalance:   return "Content depth"
        }
    }
}
