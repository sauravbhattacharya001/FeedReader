//
//  FeedCrossReferenceEngine.swift
//  FeedReaderCore
//
//  Autonomous cross-article fact corroboration and contradiction detection
//  engine. Extracts factual claims (numbers, dates, names, statistics) from
//  articles and cross-references them across sources to find corroborations,
//  contradictions, and uncorroborated claims.
//
//  Agentic capabilities:
//  - **Claim Extraction:** Identifies factual assertions (numbers, dates,
//    percentages, named entities, quantities) from article text
//  - **Cross-Reference Matching:** Finds related claims across articles
//    using topic similarity and entity overlap
//  - **Corroboration Detection:** Scores how well multiple sources agree
//    on the same factual claims
//  - **Contradiction Detection:** Flags conflicting claims from different
//    sources with severity classification
//  - **Confidence Scoring:** Composite reliability score based on source
//    count, agreement level, and source diversity
//  - **Claim Provenance Tracking:** Full audit trail of which articles
//    support or contradict each claim
//  - **Autonomous Alerts:** Proactive notifications for contradictions,
//    low-confidence claims, and emerging consensus
//  - **Fleet Health Scoring:** Overall information reliability score 0-100
//
//  Fully offline — no network, no dependencies beyond Foundation.
//

import Foundation

// MARK: - Notifications

extension Notification.Name {
    static let crossRefContradictionDetected = Notification.Name("CrossRefContradictionDetectedNotification")
    static let crossRefConsensusFormed = Notification.Name("CrossRefConsensusFormedNotification")
    static let crossRefLowConfidenceClaim = Notification.Name("CrossRefLowConfidenceClaimNotification")
}

// MARK: - Claim Type

/// Categories of factual claims extracted from articles.
public enum ClaimType: String, Codable, CaseIterable {
    case numeric        // Numbers, quantities, measurements
    case percentage     // Percentage values
    case monetary       // Currency amounts
    case temporal       // Dates, durations, timeframes
    case entity         // Named entities (people, organizations, places)
    case statistic      // Statistical claims ("doubled", "fell by half")
    case attribution    // "X said Y" claims
    case causal         // "X caused Y" claims
}

// MARK: - Corroboration Level

/// How well a claim is supported across sources.
public enum CorroborationLevel: String, Codable, CaseIterable, Comparable {
    case strongConsensus = "Strong Consensus"   // 3+ sources agree
    case corroborated = "Corroborated"          // 2 sources agree
    case uncorroborated = "Uncorroborated"      // Single source only
    case disputed = "Disputed"                  // Sources disagree mildly
    case contradicted = "Contradicted"          // Sources directly conflict

    private var ordinal: Int {
        switch self {
        case .contradicted: return 0
        case .disputed: return 1
        case .uncorroborated: return 2
        case .corroborated: return 3
        case .strongConsensus: return 4
        }
    }

    public static func < (lhs: CorroborationLevel, rhs: CorroborationLevel) -> Bool {
        return lhs.ordinal < rhs.ordinal
    }
}

// MARK: - Contradiction Severity

/// Severity of a detected contradiction between sources.
public enum ContradictionSeverity: String, Codable, CaseIterable {
    case minor = "Minor"         // Small numeric discrepancies
    case moderate = "Moderate"   // Significant factual differences
    case major = "Major"         // Directly opposing claims
    case critical = "Critical"   // Fundamental factual conflict
}

// MARK: - Alert Type

/// Types of proactive alerts the engine generates.
public enum CrossRefAlertType: String, Codable, CaseIterable {
    case contradictionFound      // Conflicting claims detected
    case consensusFormed         // Multiple sources now agree
    case singleSourceClaim       // Important claim from only one source
    case numericDiscrepancy      // Numbers don't match across sources
    case sourceReliabilityDrop   // A source's cross-ref accuracy is declining
    case emergingFact            // New claim gaining multi-source support
}

// MARK: - Models

/// A factual claim extracted from an article.
public struct ExtractedClaim: Sendable {
    public let id: String
    public let articleId: String
    public let articleTitle: String
    public let sourceId: String
    public let claimType: ClaimType
    public let claimText: String
    public let keywords: [String]
    public let numericValue: Double?
    public let timestamp: Date

    public init(id: String = UUID().uuidString,
                articleId: String,
                articleTitle: String,
                sourceId: String,
                claimType: ClaimType,
                claimText: String,
                keywords: [String],
                numericValue: Double? = nil,
                timestamp: Date = Date()) {
        self.id = id
        self.articleId = articleId
        self.articleTitle = articleTitle
        self.sourceId = sourceId
        self.claimType = claimType
        self.claimText = claimText
        self.keywords = keywords
        self.numericValue = numericValue
        self.timestamp = timestamp
    }
}

/// A cross-reference match between related claims.
public struct CrossReference: Sendable {
    public let id: String
    public let primaryClaimId: String
    public let relatedClaimId: String
    public let similarity: Double           // 0-1 keyword overlap
    public let agreement: AgreementType
    public let numericDeviation: Double?     // Percentage deviation if both numeric
    public let timestamp: Date

    public init(id: String = UUID().uuidString,
                primaryClaimId: String,
                relatedClaimId: String,
                similarity: Double,
                agreement: AgreementType,
                numericDeviation: Double? = nil,
                timestamp: Date = Date()) {
        self.id = id
        self.primaryClaimId = primaryClaimId
        self.relatedClaimId = relatedClaimId
        self.similarity = similarity
        self.agreement = agreement
        self.numericDeviation = numericDeviation
        self.timestamp = timestamp
    }
}

/// Whether two claims agree or disagree.
public enum AgreementType: String, Codable, CaseIterable {
    case agrees = "Agrees"
    case partiallyAgrees = "Partially Agrees"
    case neutral = "Neutral"
    case partiallyDisagrees = "Partially Disagrees"
    case contradicts = "Contradicts"
}

/// A cluster of related claims about the same topic.
public struct ClaimCluster: Sendable {
    public let id: String
    public let topic: String
    public let claims: [ExtractedClaim]
    public let crossReferences: [CrossReference]
    public let corroborationLevel: CorroborationLevel
    public let confidenceScore: Double       // 0-100
    public let sourceCount: Int
    public let contradictions: [Contradiction]

    public init(id: String = UUID().uuidString,
                topic: String,
                claims: [ExtractedClaim],
                crossReferences: [CrossReference],
                corroborationLevel: CorroborationLevel,
                confidenceScore: Double,
                sourceCount: Int,
                contradictions: [Contradiction]) {
        self.id = id
        self.topic = topic
        self.claims = claims
        self.crossReferences = crossReferences
        self.corroborationLevel = corroborationLevel
        self.confidenceScore = confidenceScore
        self.sourceCount = sourceCount
        self.contradictions = contradictions
    }
}

/// A detected contradiction between claims.
public struct Contradiction: Sendable {
    public let id: String
    public let claimA: ExtractedClaim
    public let claimB: ExtractedClaim
    public let severity: ContradictionSeverity
    public let description: String
    public let numericDeviation: Double?

    public init(id: String = UUID().uuidString,
                claimA: ExtractedClaim,
                claimB: ExtractedClaim,
                severity: ContradictionSeverity,
                description: String,
                numericDeviation: Double? = nil) {
        self.id = id
        self.claimA = claimA
        self.claimB = claimB
        self.severity = severity
        self.description = description
        self.numericDeviation = numericDeviation
    }
}

/// Alert generated proactively by the engine.
public struct CrossRefAlert: Sendable {
    public let id: String
    public let alertType: CrossRefAlertType
    public let severity: ContradictionSeverity
    public let message: String
    public let relatedClaimIds: [String]
    public let timestamp: Date

    public init(id: String = UUID().uuidString,
                alertType: CrossRefAlertType,
                severity: ContradictionSeverity,
                message: String,
                relatedClaimIds: [String],
                timestamp: Date = Date()) {
        self.id = id
        self.alertType = alertType
        self.severity = severity
        self.message = message
        self.relatedClaimIds = relatedClaimIds
        self.timestamp = timestamp
    }
}

/// Source reliability profile based on cross-referencing accuracy.
public struct SourceReliabilityProfile: Sendable {
    public let sourceId: String
    public var totalClaims: Int
    public var corroboratedClaims: Int
    public var contradictedClaims: Int
    public var uniqueClaims: Int
    public var accuracyScore: Double         // 0-100
    public var reliabilityTrend: Double      // Positive = improving

    public init(sourceId: String,
                totalClaims: Int = 0,
                corroboratedClaims: Int = 0,
                contradictedClaims: Int = 0,
                uniqueClaims: Int = 0,
                accuracyScore: Double = 50.0,
                reliabilityTrend: Double = 0.0) {
        self.sourceId = sourceId
        self.totalClaims = totalClaims
        self.corroboratedClaims = corroboratedClaims
        self.contradictedClaims = contradictedClaims
        self.uniqueClaims = uniqueClaims
        self.accuracyScore = accuracyScore
        self.reliabilityTrend = reliabilityTrend
    }
}

/// Fleet-level cross-referencing health report.
public struct CrossRefHealthReport: Sendable {
    public let healthScore: Double           // 0-100
    public let totalClaims: Int
    public let totalClusters: Int
    public let corroborationRate: Double     // 0-1
    public let contradictionRate: Double     // 0-1
    public let averageSourcesPerClaim: Double
    public let sourceProfiles: [SourceReliabilityProfile]
    public let topContradictions: [Contradiction]
    public let activeAlerts: [CrossRefAlert]
    public let insights: [String]

    public init(healthScore: Double,
                totalClaims: Int,
                totalClusters: Int,
                corroborationRate: Double,
                contradictionRate: Double,
                averageSourcesPerClaim: Double,
                sourceProfiles: [SourceReliabilityProfile],
                topContradictions: [Contradiction],
                activeAlerts: [CrossRefAlert],
                insights: [String]) {
        self.healthScore = healthScore
        self.totalClaims = totalClaims
        self.totalClusters = totalClusters
        self.corroborationRate = corroborationRate
        self.contradictionRate = contradictionRate
        self.averageSourcesPerClaim = averageSourcesPerClaim
        self.sourceProfiles = sourceProfiles
        self.topContradictions = topContradictions
        self.activeAlerts = activeAlerts
        self.insights = insights
    }
}

// MARK: - Claim Extraction Engine

/// Extracts factual claims from article text using pattern matching.
public class ClaimExtractor {

    // MARK: - Regex Patterns

    private static let percentagePattern: NSRegularExpression = {
        try! NSRegularExpression(pattern: "\\b(\\d+\\.?\\d*)\\s*(%|percent|percentage)\\b", options: .caseInsensitive)
    }()

    private static let monetaryPattern: NSRegularExpression = {
        try! NSRegularExpression(pattern: "\\$\\s*(\\d[\\d,]*\\.?\\d*)\\s*(billion|million|thousand|trillion)?|\\b(\\d[\\d,]*\\.?\\d*)\\s*(dollars|euros|pounds|yen)", options: .caseInsensitive)
    }()

    private static let numericPattern: NSRegularExpression = {
        try! NSRegularExpression(pattern: "\\b(\\d[\\d,]*\\.?\\d*)\\s+(people|users|customers|employees|units|deaths|cases|patients|students|workers|miles|kilometers|tons|pounds|gallons|liters|acres|hectares)\\b", options: .caseInsensitive)
    }()

    private static let statisticPattern: NSRegularExpression = {
        try! NSRegularExpression(pattern: "\\b(doubled|tripled|halved|increased|decreased|rose|fell|dropped|surged|plummeted|grew|declined|jumped|slipped)\\s+(by\\s+)?(\\d+\\.?\\d*)?", options: .caseInsensitive)
    }()

    private static let attributionPattern: NSRegularExpression = {
        try! NSRegularExpression(pattern: "\\b([A-Z][a-z]+(?:\\s+[A-Z][a-z]+)+)\\s+(said|stated|announced|claimed|reported|confirmed|denied|warned|revealed)\\b", options: [])
    }()

    private static let causalPattern: NSRegularExpression = {
        try! NSRegularExpression(pattern: "\\b(caused|led to|resulted in|triggered|prompted|due to|because of|owing to|attributed to)\\b", options: .caseInsensitive)
    }()

    private static let temporalPattern: NSRegularExpression = {
        try! NSRegularExpression(pattern: "\\b(January|February|March|April|May|June|July|August|September|October|November|December)\\s+\\d{1,2},?\\s+\\d{4}|\\b\\d{1,2}/\\d{1,2}/\\d{2,4}|\\b(20\\d{2}|19\\d{2})\\b", options: [])
    }()

    public init() {}

    /// Extracts all factual claims from an article.
    public func extractClaims(from story: RSSStory, sourceId: String) -> [ExtractedClaim] {
        let text = "\(story.title) \(story.body)"
        var claims: [ExtractedClaim] = []
        let keywords = Array(Set(TextUtilities.extractSignificantWords(from: text).prefix(10)))

        // Extract percentage claims
        claims.append(contentsOf: extractRegexClaims(
            text: text, pattern: Self.percentagePattern, type: .percentage,
            articleId: story.link, articleTitle: story.title, sourceId: sourceId, keywords: keywords
        ))

        // Extract monetary claims
        claims.append(contentsOf: extractRegexClaims(
            text: text, pattern: Self.monetaryPattern, type: .monetary,
            articleId: story.link, articleTitle: story.title, sourceId: sourceId, keywords: keywords
        ))

        // Extract numeric claims
        claims.append(contentsOf: extractRegexClaims(
            text: text, pattern: Self.numericPattern, type: .numeric,
            articleId: story.link, articleTitle: story.title, sourceId: sourceId, keywords: keywords
        ))

        // Extract statistic claims
        claims.append(contentsOf: extractRegexClaims(
            text: text, pattern: Self.statisticPattern, type: .statistic,
            articleId: story.link, articleTitle: story.title, sourceId: sourceId, keywords: keywords
        ))

        // Extract attribution claims
        claims.append(contentsOf: extractRegexClaims(
            text: text, pattern: Self.attributionPattern, type: .attribution,
            articleId: story.link, articleTitle: story.title, sourceId: sourceId, keywords: keywords
        ))

        // Extract causal claims
        claims.append(contentsOf: extractRegexClaims(
            text: text, pattern: Self.causalPattern, type: .causal,
            articleId: story.link, articleTitle: story.title, sourceId: sourceId, keywords: keywords
        ))

        // Extract temporal claims
        claims.append(contentsOf: extractRegexClaims(
            text: text, pattern: Self.temporalPattern, type: .temporal,
            articleId: story.link, articleTitle: story.title, sourceId: sourceId, keywords: keywords
        ))

        return claims
    }

    private func extractRegexClaims(
        text: String,
        pattern: NSRegularExpression,
        type: ClaimType,
        articleId: String,
        articleTitle: String,
        sourceId: String,
        keywords: [String]
    ) -> [ExtractedClaim] {
        let nsText = text as NSString
        let range = NSRange(location: 0, length: nsText.length)
        let matches = pattern.matches(in: text, options: [], range: range)

        return matches.compactMap { match in
            let matchRange = match.range
            // Expand to sentence context
            let contextStart = max(0, matchRange.location - 50)
            let contextEnd = min(nsText.length, matchRange.location + matchRange.length + 50)
            let contextRange = NSRange(location: contextStart, length: contextEnd - contextStart)
            let claimText = nsText.substring(with: contextRange)
                .trimmingCharacters(in: .whitespacesAndNewlines)

            let matchedText = nsText.substring(with: matchRange)
            let numericValue = extractNumericValue(from: matchedText)

            return ExtractedClaim(
                articleId: articleId,
                articleTitle: articleTitle,
                sourceId: sourceId,
                claimType: type,
                claimText: claimText,
                keywords: keywords,
                numericValue: numericValue
            )
        }
    }

    /// Extracts a numeric value from matched text.
    private func extractNumericValue(from text: String) -> Double? {
        let cleaned = text.replacingOccurrences(of: ",", with: "")
        let nsText = cleaned as NSString
        let numPattern = try! NSRegularExpression(pattern: "(\\d+\\.?\\d*)", options: [])
        let range = NSRange(location: 0, length: nsText.length)
        guard let match = numPattern.firstMatch(in: cleaned, options: [], range: range) else {
            return nil
        }
        let numStr = nsText.substring(with: match.range(at: 1))
        var value = Double(numStr) ?? 0

        let lower = text.lowercased()
        if lower.contains("trillion") { value *= 1_000_000_000_000 }
        else if lower.contains("billion") { value *= 1_000_000_000 }
        else if lower.contains("million") { value *= 1_000_000 }
        else if lower.contains("thousand") { value *= 1_000 }

        return value
    }
}

// MARK: - Cross-Reference Matcher

/// Matches related claims across articles using keyword similarity.
public class CrossReferenceMatcher {

    /// Minimum keyword Jaccard similarity to consider claims related.
    public var similarityThreshold: Double = 0.15

    /// Maximum numeric deviation (as fraction) to consider claims agreeing.
    public var numericAgreementThreshold: Double = 0.10

    public init() {}

    /// Finds cross-references between claims from different sources.
    public func findCrossReferences(claims: [ExtractedClaim]) -> [CrossReference] {
        var refs: [CrossReference] = []

        for i in 0..<claims.count {
            for j in (i + 1)..<claims.count {
                let a = claims[i]
                let b = claims[j]

                // Only cross-reference across different sources
                guard a.sourceId != b.sourceId else { continue }
                // Same claim type preferred
                guard a.claimType == b.claimType else { continue }

                let similarity = jaccardSimilarity(a.keywords, b.keywords)
                guard similarity >= similarityThreshold else { continue }

                let (agreement, deviation) = assessAgreement(a, b)

                refs.append(CrossReference(
                    primaryClaimId: a.id,
                    relatedClaimId: b.id,
                    similarity: similarity,
                    agreement: agreement,
                    numericDeviation: deviation
                ))
            }
        }

        return refs
    }

    /// Jaccard similarity between two keyword sets.
    private func jaccardSimilarity(_ a: [String], _ b: [String]) -> Double {
        let setA = Set(a)
        let setB = Set(b)
        let intersection = setA.intersection(setB).count
        let union = setA.union(setB).count
        guard union > 0 else { return 0 }
        return Double(intersection) / Double(union)
    }

    /// Assesses agreement between two claims.
    private func assessAgreement(_ a: ExtractedClaim, _ b: ExtractedClaim) -> (AgreementType, Double?) {
        // If both have numeric values, compare them
        if let numA = a.numericValue, let numB = b.numericValue, numA > 0 {
            let deviation = abs(numA - numB) / numA
            if deviation <= 0.05 {
                return (.agrees, deviation)
            } else if deviation <= numericAgreementThreshold {
                return (.partiallyAgrees, deviation)
            } else if deviation <= 0.30 {
                return (.partiallyDisagrees, deviation)
            } else {
                return (.contradicts, deviation)
            }
        }

        // Text-based agreement: check for negation indicators
        let negationWords: Set<String> = ["not", "no", "never", "denied", "false", "incorrect",
                                           "wrong", "untrue", "rejected", "disputed", "contrary"]

        let wordsA = Set(a.claimText.lowercased().components(separatedBy: .whitespacesAndNewlines))
        let wordsB = Set(b.claimText.lowercased().components(separatedBy: .whitespacesAndNewlines))

        let negA = !wordsA.intersection(negationWords).isEmpty
        let negB = !wordsB.intersection(negationWords).isEmpty

        if negA != negB {
            return (.partiallyDisagrees, nil)
        }

        return (.neutral, nil)
    }
}

// MARK: - Claim Clusterer

/// Groups related claims into topic clusters.
public class ClaimClusterer {

    /// Minimum similarity to merge claims into a cluster.
    public var clusterThreshold: Double = 0.20

    public init() {}

    /// Clusters claims by topic similarity.
    public func clusterClaims(claims: [ExtractedClaim], crossReferences: [CrossReference]) -> [ClaimCluster] {
        guard !claims.isEmpty else { return [] }

        // Build adjacency from cross-references
        var claimById: [String: ExtractedClaim] = [:]
        for c in claims { claimById[c.id] = c }

        var adjacency: [String: Set<String>] = [:]
        for ref in crossReferences {
            adjacency[ref.primaryClaimId, default: []].insert(ref.relatedClaimId)
            adjacency[ref.relatedClaimId, default: []].insert(ref.primaryClaimId)
        }

        // Also cluster claims from different articles with high keyword overlap
        for i in 0..<claims.count {
            for j in (i + 1)..<claims.count {
                let a = claims[i]
                let b = claims[j]
                guard a.articleId != b.articleId else { continue }
                let setA = Set(a.keywords)
                let setB = Set(b.keywords)
                let inter = setA.intersection(setB).count
                let uni = setA.union(setB).count
                guard uni > 0 else { continue }
                let sim = Double(inter) / Double(uni)
                if sim >= clusterThreshold {
                    adjacency[a.id, default: []].insert(b.id)
                    adjacency[b.id, default: []].insert(a.id)
                }
            }
        }

        // Connected components via BFS
        var visited: Set<String> = []
        var clusters: [ClaimCluster] = []

        for claim in claims {
            guard !visited.contains(claim.id) else { continue }

            var component: [String] = []
            var queue: [String] = [claim.id]
            visited.insert(claim.id)

            while !queue.isEmpty {
                let current = queue.removeFirst()
                component.append(current)

                for neighbor in adjacency[current, default: []] {
                    guard !visited.contains(neighbor) else { continue }
                    visited.insert(neighbor)
                    queue.append(neighbor)
                }
            }

            let clusterClaims = component.compactMap { claimById[$0] }
            let clusterRefs = crossReferences.filter { ref in
                let ids = Set(component)
                return ids.contains(ref.primaryClaimId) || ids.contains(ref.relatedClaimId)
            }

            // Determine topic from most common keywords
            var keywordCounts: [String: Int] = [:]
            for c in clusterClaims {
                for kw in c.keywords {
                    keywordCounts[kw, default: 0] += 1
                }
            }
            let topKeywords = keywordCounts.sorted { $0.value > $1.value }.prefix(3).map { $0.key }
            let topic = topKeywords.joined(separator: " / ")

            // Detect contradictions
            let contradictions = detectContradictions(claims: clusterClaims, refs: clusterRefs, claimById: claimById)

            // Count unique sources
            let sources = Set(clusterClaims.map { $0.sourceId })

            // Score confidence
            let confidence = scoreConfidence(
                claimCount: clusterClaims.count,
                sourceCount: sources.count,
                agreementRefs: clusterRefs.filter { $0.agreement == .agrees || $0.agreement == .partiallyAgrees },
                contradictions: contradictions
            )

            // Determine corroboration level
            let level = classifyCorroboration(
                sourceCount: sources.count,
                contradictions: contradictions,
                agreementCount: clusterRefs.filter { $0.agreement == .agrees || $0.agreement == .partiallyAgrees }.count
            )

            clusters.append(ClaimCluster(
                topic: topic,
                claims: clusterClaims,
                crossReferences: clusterRefs,
                corroborationLevel: level,
                confidenceScore: confidence,
                sourceCount: sources.count,
                contradictions: contradictions
            ))
        }

        return clusters.sorted { $0.claims.count > $1.claims.count }
    }

    private func detectContradictions(claims: [ExtractedClaim], refs: [CrossReference], claimById: [String: ExtractedClaim]) -> [Contradiction] {
        var contradictions: [Contradiction] = []

        for ref in refs {
            guard ref.agreement == .contradicts || ref.agreement == .partiallyDisagrees else { continue }
            guard let claimA = claimById[ref.primaryClaimId],
                  let claimB = claimById[ref.relatedClaimId] else { continue }

            let severity: ContradictionSeverity
            if let dev = ref.numericDeviation {
                if dev > 1.0 { severity = .critical }
                else if dev > 0.5 { severity = .major }
                else if dev > 0.2 { severity = .moderate }
                else { severity = .minor }
            } else {
                severity = ref.agreement == .contradicts ? .major : .moderate
            }

            let desc: String
            if let dev = ref.numericDeviation {
                desc = "Numeric discrepancy of \(String(format: "%.1f%%", dev * 100)): '\(claimA.sourceId)' vs '\(claimB.sourceId)'"
            } else {
                desc = "Conflicting claims between '\(claimA.sourceId)' and '\(claimB.sourceId)'"
            }

            contradictions.append(Contradiction(
                claimA: claimA,
                claimB: claimB,
                severity: severity,
                description: desc,
                numericDeviation: ref.numericDeviation
            ))
        }

        return contradictions
    }

    private func scoreConfidence(claimCount: Int, sourceCount: Int, agreementRefs: [CrossReference], contradictions: [Contradiction]) -> Double {
        var score = 30.0  // Base

        // More sources = more confidence
        score += min(30.0, Double(sourceCount) * 15.0)

        // Agreement refs boost confidence
        score += min(20.0, Double(agreementRefs.count) * 5.0)

        // Contradictions reduce confidence
        for c in contradictions {
            switch c.severity {
            case .critical: score -= 20.0
            case .major: score -= 15.0
            case .moderate: score -= 10.0
            case .minor: score -= 5.0
            }
        }

        return max(0, min(100, score))
    }

    private func classifyCorroboration(sourceCount: Int, contradictions: [Contradiction], agreementCount: Int) -> CorroborationLevel {
        let hasMajorContradiction = contradictions.contains { $0.severity == .critical || $0.severity == .major }
        let hasMinorContradiction = contradictions.contains { $0.severity == .moderate || $0.severity == .minor }

        if hasMajorContradiction { return .contradicted }
        if hasMinorContradiction && sourceCount > 1 { return .disputed }
        if sourceCount >= 3 && agreementCount >= 2 { return .strongConsensus }
        if sourceCount >= 2 && agreementCount >= 1 { return .corroborated }
        return .uncorroborated
    }
}

// MARK: - Alert Generator

/// Generates proactive alerts from cross-reference analysis.
public class CrossRefAlertGenerator {

    public init() {}

    /// Generates alerts from claim clusters.
    public func generateAlerts(clusters: [ClaimCluster], sourceProfiles: [SourceReliabilityProfile]) -> [CrossRefAlert] {
        var alerts: [CrossRefAlert] = []

        for cluster in clusters {
            // Contradiction alerts
            for contradiction in cluster.contradictions {
                let alert = CrossRefAlert(
                    alertType: .contradictionFound,
                    severity: contradiction.severity,
                    message: "⚠️ \(contradiction.description) on topic '\(cluster.topic)'",
                    relatedClaimIds: [contradiction.claimA.id, contradiction.claimB.id]
                )
                alerts.append(alert)
                NotificationCenter.default.post(name: .crossRefContradictionDetected, object: nil)
            }

            // Consensus alerts
            if cluster.corroborationLevel == .strongConsensus {
                alerts.append(CrossRefAlert(
                    alertType: .consensusFormed,
                    severity: .minor,
                    message: "✅ Strong consensus formed on '\(cluster.topic)' from \(cluster.sourceCount) sources",
                    relatedClaimIds: cluster.claims.map { $0.id }
                ))
                NotificationCenter.default.post(name: .crossRefConsensusFormed, object: nil)
            }

            // Single-source important claims
            if cluster.sourceCount == 1 && cluster.claims.count >= 2 {
                alerts.append(CrossRefAlert(
                    alertType: .singleSourceClaim,
                    severity: .moderate,
                    message: "⚡ Multiple claims about '\(cluster.topic)' from only one source (\(cluster.claims[0].sourceId))",
                    relatedClaimIds: cluster.claims.map { $0.id }
                ))
                NotificationCenter.default.post(name: .crossRefLowConfidenceClaim, object: nil)
            }

            // Numeric discrepancy alerts
            let numericContradictions = cluster.contradictions.filter { $0.numericDeviation != nil }
            for nc in numericContradictions {
                if let dev = nc.numericDeviation, dev > 0.2 {
                    alerts.append(CrossRefAlert(
                        alertType: .numericDiscrepancy,
                        severity: dev > 0.5 ? .major : .moderate,
                        message: "📊 Numbers don't match on '\(cluster.topic)': \(String(format: "%.0f%%", dev * 100)) deviation",
                        relatedClaimIds: [nc.claimA.id, nc.claimB.id]
                    ))
                }
            }
        }

        // Source reliability alerts
        for profile in sourceProfiles {
            if profile.reliabilityTrend < -10.0 {
                alerts.append(CrossRefAlert(
                    alertType: .sourceReliabilityDrop,
                    severity: .moderate,
                    message: "📉 Source '\(profile.sourceId)' cross-reference accuracy declining (trend: \(String(format: "%.1f", profile.reliabilityTrend)))",
                    relatedClaimIds: []
                ))
            }
        }

        return alerts
    }
}

// MARK: - Source Reliability Tracker

/// Builds reliability profiles for sources based on cross-referencing accuracy.
public class SourceReliabilityTracker {

    private var profiles: [String: SourceReliabilityProfile] = [:]
    private var previousScores: [String: Double] = [:]

    public init() {}

    /// Updates source profiles based on claim clusters.
    public func updateProfiles(clusters: [ClaimCluster]) -> [SourceReliabilityProfile] {
        var sourceStats: [String: (total: Int, corroborated: Int, contradicted: Int, unique: Int)] = [:]

        for cluster in clusters {
            let sources = Set(cluster.claims.map { $0.sourceId })
            for claim in cluster.claims {
                let sid = claim.sourceId
                var stats = sourceStats[sid] ?? (total: 0, corroborated: 0, contradicted: 0, unique: 0)
                stats.total += 1

                if sources.count == 1 {
                    stats.unique += 1
                } else if cluster.corroborationLevel == .contradicted {
                    // Check if this source is on the contradicted side
                    let isContradicted = cluster.contradictions.contains { $0.claimA.sourceId == sid || $0.claimB.sourceId == sid }
                    if isContradicted { stats.contradicted += 1 }
                    else { stats.corroborated += 1 }
                } else if cluster.corroborationLevel >= .corroborated {
                    stats.corroborated += 1
                }

                sourceStats[sid] = stats
            }
        }

        var results: [SourceReliabilityProfile] = []

        for (sourceId, stats) in sourceStats {
            let accuracy: Double
            if stats.total > 0 {
                let verified = Double(stats.corroborated)
                let total = Double(stats.total - stats.unique)  // Don't penalize unique claims
                accuracy = total > 0 ? min(100, (verified / total) * 100) : 50.0
            } else {
                accuracy = 50.0
            }

            let prevScore = previousScores[sourceId] ?? accuracy
            let trend = accuracy - prevScore
            previousScores[sourceId] = accuracy

            let profile = SourceReliabilityProfile(
                sourceId: sourceId,
                totalClaims: stats.total,
                corroboratedClaims: stats.corroborated,
                contradictedClaims: stats.contradicted,
                uniqueClaims: stats.unique,
                accuracyScore: accuracy,
                reliabilityTrend: trend
            )
            profiles[sourceId] = profile
            results.append(profile)
        }

        return results.sorted { $0.accuracyScore > $1.accuracyScore }
    }

    /// Returns the current profile for a source.
    public func profile(for sourceId: String) -> SourceReliabilityProfile? {
        return profiles[sourceId]
    }

    /// Returns all tracked profiles.
    public func allProfiles() -> [SourceReliabilityProfile] {
        return Array(profiles.values).sorted { $0.accuracyScore > $1.accuracyScore }
    }
}

// MARK: - FeedCrossReferenceEngine

/// Autonomous cross-article fact corroboration and contradiction detection engine.
///
/// Processes articles from multiple RSS sources, extracts factual claims,
/// cross-references them, and produces corroboration assessments, contradiction
/// alerts, and source reliability profiles.
///
/// ## Usage
/// ```swift
/// let engine = FeedCrossReferenceEngine()
///
/// // Ingest articles from multiple sources
/// engine.ingestArticle(story1, sourceId: "BBC")
/// engine.ingestArticle(story2, sourceId: "Reuters")
/// engine.ingestArticle(story3, sourceId: "NPR")
///
/// // Run cross-reference analysis
/// let report = engine.analyze()
///
/// // Check results
/// print("Health Score: \(report.healthScore)")
/// for cluster in report.topContradictions {
///     print("⚠️ \(cluster.description)")
/// }
/// ```
public class FeedCrossReferenceEngine {

    // MARK: - Engines

    private let extractor = ClaimExtractor()
    private let matcher = CrossReferenceMatcher()
    private let clusterer = ClaimClusterer()
    private let alertGenerator = CrossRefAlertGenerator()
    private let reliabilityTracker = SourceReliabilityTracker()

    // MARK: - State

    private var claims: [ExtractedClaim] = []
    private var clusters: [ClaimCluster] = []
    private var alerts: [CrossRefAlert] = []
    private var analysisCount: Int = 0

    // MARK: - Configuration

    /// Minimum keyword similarity for cross-referencing (0-1).
    public var similarityThreshold: Double {
        get { matcher.similarityThreshold }
        set { matcher.similarityThreshold = newValue }
    }

    /// Maximum numeric deviation to consider claims agreeing (0-1).
    public var numericAgreementThreshold: Double {
        get { matcher.numericAgreementThreshold }
        set { matcher.numericAgreementThreshold = newValue }
    }

    // MARK: - Init

    public init() {}

    // MARK: - Ingestion

    /// Ingests an article and extracts its factual claims.
    /// - Parameters:
    ///   - story: The RSS story to analyze.
    ///   - sourceId: Identifier for the source feed (e.g. "BBC", "Reuters").
    /// - Returns: Number of claims extracted.
    @discardableResult
    public func ingestArticle(_ story: RSSStory, sourceId: String) -> Int {
        let extracted = extractor.extractClaims(from: story, sourceId: sourceId)
        claims.append(contentsOf: extracted)
        return extracted.count
    }

    /// Ingests multiple articles from a source at once.
    /// - Parameters:
    ///   - stories: Array of RSS stories.
    ///   - sourceId: Source feed identifier.
    /// - Returns: Total claims extracted.
    @discardableResult
    public func ingestArticles(_ stories: [RSSStory], sourceId: String) -> Int {
        var total = 0
        for story in stories {
            total += ingestArticle(story, sourceId: sourceId)
        }
        return total
    }

    // MARK: - Analysis

    /// Runs full cross-reference analysis on all ingested claims.
    /// - Returns: Comprehensive health report with corroboration status, contradictions, and alerts.
    public func analyze() -> CrossRefHealthReport {
        analysisCount += 1

        // Find cross-references
        let crossRefs = matcher.findCrossReferences(claims: claims)

        // Cluster related claims
        clusters = clusterer.clusterClaims(claims: claims, crossReferences: crossRefs)

        // Update source reliability profiles
        let profiles = reliabilityTracker.updateProfiles(clusters: clusters)

        // Generate alerts
        alerts = alertGenerator.generateAlerts(clusters: clusters, sourceProfiles: profiles)

        // Compute fleet health
        let corroboratedCount = clusters.filter { $0.corroborationLevel >= .corroborated }.count
        let contradictedCount = clusters.filter { $0.corroborationLevel == .contradicted }.count
        let totalClusters = clusters.count

        let corroborationRate = totalClusters > 0 ? Double(corroboratedCount) / Double(totalClusters) : 0
        let contradictionRate = totalClusters > 0 ? Double(contradictedCount) / Double(totalClusters) : 0

        let avgSources: Double
        if clusters.isEmpty {
            avgSources = 0
        } else {
            avgSources = Double(clusters.map { $0.sourceCount }.reduce(0, +)) / Double(clusters.count)
        }

        let healthScore = computeHealthScore(
            corroborationRate: corroborationRate,
            contradictionRate: contradictionRate,
            avgSources: avgSources,
            totalClaims: claims.count
        )

        let insights = generateInsights(
            clusters: clusters,
            profiles: profiles,
            healthScore: healthScore
        )

        let topContradictions = clusters
            .flatMap { $0.contradictions }
            .sorted { severityOrdinal($0.severity) > severityOrdinal($1.severity) }
            .prefix(5)

        return CrossRefHealthReport(
            healthScore: healthScore,
            totalClaims: claims.count,
            totalClusters: totalClusters,
            corroborationRate: corroborationRate,
            contradictionRate: contradictionRate,
            averageSourcesPerClaim: avgSources,
            sourceProfiles: profiles,
            topContradictions: Array(topContradictions),
            activeAlerts: alerts,
            insights: insights
        )
    }

    // MARK: - Query

    /// Returns all current claim clusters.
    public func currentClusters() -> [ClaimCluster] {
        return clusters
    }

    /// Returns clusters with contradictions.
    public func contradictedClusters() -> [ClaimCluster] {
        return clusters.filter { $0.corroborationLevel == .contradicted || $0.corroborationLevel == .disputed }
    }

    /// Returns clusters with strong consensus.
    public func consensusClusters() -> [ClaimCluster] {
        return clusters.filter { $0.corroborationLevel == .strongConsensus }
    }

    /// Returns claims for a specific source.
    public func claims(for sourceId: String) -> [ExtractedClaim] {
        return claims.filter { $0.sourceId == sourceId }
    }

    /// Returns the reliability profile for a source.
    public func sourceReliability(_ sourceId: String) -> SourceReliabilityProfile? {
        return reliabilityTracker.profile(for: sourceId)
    }

    /// Returns all active alerts.
    public func activeAlerts() -> [CrossRefAlert] {
        return alerts
    }

    /// Returns total ingested claims count.
    public func totalClaimsCount() -> Int {
        return claims.count
    }

    /// Resets all state for a fresh analysis.
    public func reset() {
        claims.removeAll()
        clusters.removeAll()
        alerts.removeAll()
    }

    // MARK: - HTML Report

    /// Generates an interactive HTML dashboard for the cross-reference analysis.
    public func generateHTMLReport() -> String {
        let report = analyze()

        var html = """
        <!DOCTYPE html>
        <html lang="en">
        <head>
        <meta charset="UTF-8">
        <meta name="viewport" content="width=device-width, initial-scale=1.0">
        <title>Cross-Reference Analysis Dashboard</title>
        <style>
        * { margin: 0; padding: 0; box-sizing: border-box; }
        body { font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', system-ui, sans-serif;
               background: #0a0a0f; color: #e0e0e0; padding: 20px; }
        .header { text-align: center; padding: 30px 0; }
        .header h1 { font-size: 28px; color: #60a5fa; }
        .header .subtitle { color: #888; margin-top: 8px; }
        .score-ring { width: 120px; height: 120px; margin: 20px auto; position: relative; }
        .score-ring svg { transform: rotate(-90deg); }
        .score-ring .value { position: absolute; top: 50%; left: 50%; transform: translate(-50%, -50%);
                             font-size: 32px; font-weight: bold; }
        .grid { display: grid; grid-template-columns: repeat(auto-fit, minmax(300px, 1fr)); gap: 16px; margin: 20px 0; }
        .card { background: #1a1a2e; border-radius: 12px; padding: 20px; border: 1px solid #2a2a3e; }
        .card h2 { font-size: 16px; color: #60a5fa; margin-bottom: 12px; }
        .stat { display: flex; justify-content: space-between; padding: 8px 0; border-bottom: 1px solid #2a2a3e; }
        .stat:last-child { border-bottom: none; }
        .stat .label { color: #888; }
        .stat .value { font-weight: 600; }
        .badge { display: inline-block; padding: 2px 8px; border-radius: 12px; font-size: 12px; font-weight: 600; }
        .badge-green { background: #064e3b; color: #34d399; }
        .badge-yellow { background: #78350f; color: #fbbf24; }
        .badge-red { background: #7f1d1d; color: #f87171; }
        .badge-blue { background: #1e3a5f; color: #60a5fa; }
        .alert-item { padding: 12px; margin: 8px 0; border-radius: 8px; border-left: 3px solid; }
        .alert-minor { border-color: #34d399; background: #064e3b22; }
        .alert-moderate { border-color: #fbbf24; background: #78350f22; }
        .alert-major { border-color: #f97316; background: #7c2d1222; }
        .alert-critical { border-color: #f87171; background: #7f1d1d22; }
        .insight { padding: 10px 16px; margin: 6px 0; background: #1e293b; border-radius: 8px;
                   border-left: 3px solid #60a5fa; font-size: 14px; }
        .cluster-item { padding: 12px; margin: 8px 0; background: #16162a; border-radius: 8px; }
        .bar { height: 8px; border-radius: 4px; background: #2a2a3e; margin-top: 4px; }
        .bar-fill { height: 100%; border-radius: 4px; transition: width 0.3s; }
        .tabs { display: flex; gap: 4px; margin-bottom: 16px; }
        .tab { padding: 8px 16px; background: #1a1a2e; border: 1px solid #2a2a3e; border-radius: 8px 8px 0 0;
               cursor: pointer; font-size: 14px; color: #888; }
        .tab.active { background: #2a2a3e; color: #60a5fa; border-bottom-color: #2a2a3e; }
        .tab-content { display: none; }
        .tab-content.active { display: block; }
        .source-row { display: flex; align-items: center; gap: 12px; padding: 10px; margin: 4px 0;
                      background: #16162a; border-radius: 8px; }
        .source-name { min-width: 100px; font-weight: 600; }
        .source-bar { flex: 1; }
        .source-score { min-width: 50px; text-align: right; font-weight: 600; }
        </style>
        </head>
        <body>
        <div class="header">
            <h1>🔗 Cross-Reference Analysis</h1>
            <div class="subtitle">Autonomous Fact Corroboration & Contradiction Detection</div>
        """

        // Health score ring
        let strokeColor = report.healthScore >= 70 ? "#34d399" : report.healthScore >= 40 ? "#fbbf24" : "#f87171"
        let circumference = 2.0 * Double.pi * 50.0
        let offset = circumference * (1.0 - report.healthScore / 100.0)

        html += """
            <div class="score-ring">
                <svg width="120" height="120">
                    <circle cx="60" cy="60" r="50" fill="none" stroke="#2a2a3e" stroke-width="8"/>
                    <circle cx="60" cy="60" r="50" fill="none" stroke="\(strokeColor)" stroke-width="8"
                            stroke-dasharray="\(String(format: "%.1f", circumference))"
                            stroke-dashoffset="\(String(format: "%.1f", offset))" stroke-linecap="round"/>
                </svg>
                <div class="value" style="color: \(strokeColor)">\(Int(report.healthScore))</div>
            </div>
        </div>
        """

        // Summary cards
        html += """
        <div class="grid">
            <div class="card">
                <h2>📊 Overview</h2>
                <div class="stat"><span class="label">Total Claims</span><span class="value">\(report.totalClaims)</span></div>
                <div class="stat"><span class="label">Claim Clusters</span><span class="value">\(report.totalClusters)</span></div>
                <div class="stat"><span class="label">Corroboration Rate</span><span class="value">\(String(format: "%.0f%%", report.corroborationRate * 100))</span></div>
                <div class="stat"><span class="label">Contradiction Rate</span><span class="value">\(String(format: "%.0f%%", report.contradictionRate * 100))</span></div>
                <div class="stat"><span class="label">Avg Sources/Claim</span><span class="value">\(String(format: "%.1f", report.averageSourcesPerClaim))</span></div>
            </div>
            <div class="card">
                <h2>🚨 Active Alerts</h2>
        """

        if report.activeAlerts.isEmpty {
            html += "<p style='color:#888;padding:20px 0;text-align:center'>No active alerts</p>"
        } else {
            for alert in report.activeAlerts.prefix(5) {
                let cssClass: String
                switch alert.severity {
                case .minor: cssClass = "alert-minor"
                case .moderate: cssClass = "alert-moderate"
                case .major: cssClass = "alert-major"
                case .critical: cssClass = "alert-critical"
                }
                html += "<div class=\"alert-item \(cssClass)\">\(TextUtilities.escapeHTML(alert.message))</div>"
            }
        }

        html += """
            </div>
        </div>
        """

        // Tabs for clusters, sources, insights
        html += """
        <div class="tabs">
            <div class="tab active" onclick="showTab('clusters')">Claim Clusters</div>
            <div class="tab" onclick="showTab('sources')">Source Reliability</div>
            <div class="tab" onclick="showTab('contradictions')">Contradictions</div>
            <div class="tab" onclick="showTab('insights')">Insights</div>
        </div>
        """

        // Clusters tab
        html += "<div id=\"tab-clusters\" class=\"tab-content active\">"
        if clusters.isEmpty {
            html += "<p style='color:#888;text-align:center;padding:20px'>No claims ingested yet</p>"
        } else {
            for cluster in clusters.prefix(10) {
                let levelBadge: String
                switch cluster.corroborationLevel {
                case .strongConsensus: levelBadge = "<span class='badge badge-green'>Strong Consensus</span>"
                case .corroborated: levelBadge = "<span class='badge badge-green'>Corroborated</span>"
                case .uncorroborated: levelBadge = "<span class='badge badge-yellow'>Uncorroborated</span>"
                case .disputed: levelBadge = "<span class='badge badge-yellow'>Disputed</span>"
                case .contradicted: levelBadge = "<span class='badge badge-red'>Contradicted</span>"
                }

                let barColor = cluster.confidenceScore >= 70 ? "#34d399" : cluster.confidenceScore >= 40 ? "#fbbf24" : "#f87171"

                html += """
                <div class="cluster-item">
                    <div style="display:flex;justify-content:space-between;align-items:center">
                        <strong>\(TextUtilities.escapeHTML(cluster.topic))</strong>
                        \(levelBadge)
                    </div>
                    <div style="color:#888;font-size:13px;margin-top:4px">
                        \(cluster.claims.count) claims · \(cluster.sourceCount) sources · \(cluster.contradictions.count) contradictions
                    </div>
                    <div class="bar"><div class="bar-fill" style="width:\(Int(cluster.confidenceScore))%;background:\(barColor)"></div></div>
                    <div style="color:#888;font-size:12px;margin-top:2px">Confidence: \(Int(cluster.confidenceScore))%</div>
                </div>
                """
            }
        }
        html += "</div>"

        // Sources tab
        html += "<div id=\"tab-sources\" class=\"tab-content\">"
        if report.sourceProfiles.isEmpty {
            html += "<p style='color:#888;text-align:center;padding:20px'>No source data yet</p>"
        } else {
            for profile in report.sourceProfiles {
                let barColor = profile.accuracyScore >= 70 ? "#34d399" : profile.accuracyScore >= 40 ? "#fbbf24" : "#f87171"
                html += """
                <div class="source-row">
                    <span class="source-name">\(TextUtilities.escapeHTML(profile.sourceId))</span>
                    <div class="source-bar">
                        <div class="bar"><div class="bar-fill" style="width:\(Int(profile.accuracyScore))%;background:\(barColor)"></div></div>
                    </div>
                    <span class="source-score" style="color:\(barColor)">\(Int(profile.accuracyScore))%</span>
                </div>
                <div style="color:#888;font-size:12px;padding:0 12px 8px">
                    \(profile.totalClaims) claims · \(profile.corroboratedClaims) corroborated · \(profile.contradictedClaims) contradicted · \(profile.uniqueClaims) unique
                </div>
                """
            }
        }
        html += "</div>"

        // Contradictions tab
        html += "<div id=\"tab-contradictions\" class=\"tab-content\">"
        if report.topContradictions.isEmpty {
            html += "<p style='color:#888;text-align:center;padding:20px'>No contradictions detected ✅</p>"
        } else {
            for c in report.topContradictions {
                let cssClass: String
                switch c.severity {
                case .minor: cssClass = "alert-minor"
                case .moderate: cssClass = "alert-moderate"
                case .major: cssClass = "alert-major"
                case .critical: cssClass = "alert-critical"
                }
                html += """
                <div class="alert-item \(cssClass)">
                    <div style="font-weight:600">\(c.severity.rawValue) Contradiction</div>
                    <div style="margin-top:4px">\(TextUtilities.escapeHTML(c.description))</div>
                    <div style="color:#888;font-size:13px;margin-top:6px">
                        A: \(TextUtilities.escapeHTML(c.claimA.claimText.prefix(80).description))…<br>
                        B: \(TextUtilities.escapeHTML(c.claimB.claimText.prefix(80).description))…
                    </div>
                </div>
                """
            }
        }
        html += "</div>"

        // Insights tab
        html += "<div id=\"tab-insights\" class=\"tab-content\">"
        if report.insights.isEmpty {
            html += "<p style='color:#888;text-align:center;padding:20px'>No insights yet</p>"
        } else {
            for insight in report.insights {
                html += "<div class=\"insight\">\(TextUtilities.escapeHTML(insight))</div>"
            }
        }
        html += "</div>"

        // JavaScript for tabs
        html += """
        <script>
        function showTab(name) {
            document.querySelectorAll('.tab-content').forEach(el => el.classList.remove('active'));
            document.querySelectorAll('.tab').forEach(el => el.classList.remove('active'));
            document.getElementById('tab-' + name).classList.add('active');
            event.target.classList.add('active');
        }
        </script>
        </body>
        </html>
        """

        return html
    }

    // MARK: - Private

    private func computeHealthScore(corroborationRate: Double, contradictionRate: Double, avgSources: Double, totalClaims: Int) -> Double {
        guard totalClaims > 0 else { return 50.0 }

        var score = 50.0

        // Corroboration boosts health
        score += corroborationRate * 30.0

        // Contradictions reduce health
        score -= contradictionRate * 40.0

        // More sources per claim is better
        score += min(15.0, avgSources * 5.0)

        // Having enough claims for meaningful analysis
        if totalClaims >= 10 { score += 5.0 }

        return max(0, min(100, score))
    }

    private func generateInsights(clusters: [ClaimCluster], profiles: [SourceReliabilityProfile], healthScore: Double) -> [String] {
        var insights: [String] = []

        // Health summary
        if healthScore >= 80 {
            insights.append("🟢 Information ecosystem is healthy — most claims are well-corroborated across sources")
        } else if healthScore >= 60 {
            insights.append("🟡 Moderate information reliability — some claims need additional sourcing")
        } else if healthScore >= 40 {
            insights.append("🟠 Below-average reliability — significant contradictions or single-source claims detected")
        } else {
            insights.append("🔴 Low information reliability — many contradictions and uncorroborated claims")
        }

        // Source diversity
        let sourceCount = profiles.count
        if sourceCount >= 5 {
            insights.append("📰 Good source diversity: \(sourceCount) distinct sources contributing claims")
        } else if sourceCount >= 2 {
            insights.append("📰 Limited source diversity: only \(sourceCount) sources — consider adding more feeds for better corroboration")
        } else if sourceCount == 1 {
            insights.append("⚠️ Single-source problem: all claims from one source — no cross-referencing possible")
        }

        // Contradiction hotspots
        let contradictedClusters = clusters.filter { $0.corroborationLevel == .contradicted }
        if !contradictedClusters.isEmpty {
            let topics = contradictedClusters.prefix(3).map { "'\($0.topic)'" }.joined(separator: ", ")
            insights.append("⚡ Contradiction hotspots: \(topics) — check these topics for factual accuracy")
        }

        // Consensus highlights
        let consensusClusters = clusters.filter { $0.corroborationLevel == .strongConsensus }
        if !consensusClusters.isEmpty {
            insights.append("✅ \(consensusClusters.count) topic(s) have strong multi-source consensus")
        }

        // Most reliable source
        if let best = profiles.first, best.accuracyScore >= 70 {
            insights.append("🏆 Most reliable source: '\(best.sourceId)' with \(Int(best.accuracyScore))% cross-reference accuracy")
        }

        // Least reliable source
        if let worst = profiles.last, profiles.count > 1 && worst.accuracyScore < 50 {
            insights.append("⚠️ Least reliable source: '\(worst.sourceId)' with \(Int(worst.accuracyScore))% accuracy — claims should be verified")
        }

        // Claim type distribution
        var typeCounts: [ClaimType: Int] = [:]
        for cluster in clusters {
            for claim in cluster.claims {
                typeCounts[claim.claimType, default: 0] += 1
            }
        }
        if let topType = typeCounts.max(by: { $0.value < $1.value }) {
            insights.append("📊 Most common claim type: \(topType.key.rawValue) (\(topType.value) claims)")
        }

        return insights
    }

    private func severityOrdinal(_ severity: ContradictionSeverity) -> Int {
        switch severity {
        case .minor: return 0
        case .moderate: return 1
        case .major: return 2
        case .critical: return 3
        }
    }
}
