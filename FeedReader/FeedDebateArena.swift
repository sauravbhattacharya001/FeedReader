//
//  FeedDebateArena.swift
//  FeedReader
//
//  Autonomous debate/argument extraction engine that identifies opposing
//  viewpoints across RSS feeds on the same topic. Extracts claims, classifies
//  stances, clusters arguments into debate topics, calculates balance scores,
//  detects echo chambers, and generates proactive insights.
//
//  Agentic capabilities:
//  - Auto-extracts claims and classifies stance (for/against/mixed/neutral)
//  - Clusters arguments into debate topics via Jaccard keyword similarity
//  - Calculates balance scores and detects one-sided coverage
//  - Detects echo chambers across feed sources
//  - Generates cross-topic insights (bridge concepts, hidden consensus, framing gaps)
//  - Proactive alerts for contradictions, echo chambers, consensus forming
//  - Auto-monitor mode for continuous analysis
//
//  Fully offline — no network, no dependencies beyond Foundation.
//

import Foundation

// MARK: - Notifications

extension Notification.Name {
    static let debateTopicCreated = Notification.Name("DebateTopicCreatedNotification")
    static let debateAlertGenerated = Notification.Name("DebateAlertGeneratedNotification")
    static let debateEchoChamberDetected = Notification.Name("DebateEchoChamberDetectedNotification")
    static let debateConsensusForming = Notification.Name("DebateConsensusFormingNotification")
}

// MARK: - Debate Stance

/// The stance an article takes on a debatable topic.
enum DebateStance: String, Codable, CaseIterable {
    case `for` = "for"
    case against = "against"
    case mixed = "mixed"
    case neutral = "neutral"

    var label: String {
        switch self {
        case .for: return "For"
        case .against: return "Against"
        case .mixed: return "Mixed"
        case .neutral: return "Neutral"
        }
    }

    var numericValue: Double {
        switch self {
        case .for: return 1.0
        case .against: return -1.0
        case .mixed: return 0.0
        case .neutral: return 0.0
        }
    }
}

// MARK: - Debate Argument

/// A single extracted argument/claim from an article.
struct DebateArgument: Codable, Identifiable {
    let id: String
    let articleTitle: String
    let articleLink: String
    let sourceFeed: String
    let date: Date
    let stance: DebateStance
    let claimText: String
    let supportingEvidence: [String]
    let confidence: Double
    let keywords: [String]

    init(articleTitle: String, articleLink: String, sourceFeed: String,
         date: Date = Date(), stance: DebateStance, claimText: String,
         supportingEvidence: [String] = [], confidence: Double,
         keywords: [String]) {
        self.id = UUID().uuidString
        self.articleTitle = articleTitle
        self.articleLink = articleLink
        self.sourceFeed = sourceFeed
        self.date = date
        self.stance = stance
        self.claimText = String(claimText.prefix(300))
        self.supportingEvidence = supportingEvidence
        self.confidence = min(1.0, max(0.0, confidence))
        self.keywords = keywords
    }
}

// MARK: - Debate Topic

/// A cluster of arguments forming a debate on a topic.
struct DebateTopic: Codable, Identifiable {
    let id: String
    var topicLabel: String
    var keywords: [String]
    var arguments: [DebateArgument]
    let createdDate: Date
    var lastUpdated: Date

    /// Balance score: 0.0 = completely one-sided, 1.0 = perfectly balanced.
    var balanceScore: Double {
        let forCount = Double(arguments.filter { $0.stance == .for }.count)
        let againstCount = Double(arguments.filter { $0.stance == .against }.count)
        let total = forCount + againstCount
        guard total > 0 else { return 1.0 }
        return 1.0 - abs(forCount - againstCount) / total
    }

    /// The dominant stance in the debate.
    var dominantStance: DebateStance {
        let forCount = arguments.filter { $0.stance == .for }.count
        let againstCount = arguments.filter { $0.stance == .against }.count
        if forCount > againstCount { return .for }
        if againstCount > forCount { return .against }
        return .mixed
    }

    /// Whether the debate is controversial (multiple stances with decent coverage).
    var isControversial: Bool {
        let forCount = arguments.filter { $0.stance == .for }.count
        let againstCount = arguments.filter { $0.stance == .against }.count
        return forCount >= 2 && againstCount >= 2
    }

    /// Number of distinct sources contributing.
    var sourceCount: Int {
        Set(arguments.map { $0.sourceFeed }).count
    }

    init(topicLabel: String, keywords: [String], arguments: [DebateArgument] = []) {
        self.id = UUID().uuidString
        self.topicLabel = topicLabel
        self.keywords = keywords
        self.arguments = arguments
        self.createdDate = Date()
        self.lastUpdated = Date()
    }
}

// MARK: - Debate Alert

/// Proactive alerts about debate dynamics.
struct DebateAlert: Codable, Identifiable {
    enum Severity: String, Codable {
        case info, warning, critical
    }

    enum AlertType: String, Codable {
        case newContradiction
        case echoChamber
        case newPerspective
        case consensusForming
        case staleDebate
        case unbalancedCoverage
    }

    let id: String
    let severity: Severity
    let message: String
    let topicId: String
    let date: Date
    let alertType: AlertType

    init(severity: Severity, message: String, topicId: String, alertType: AlertType) {
        self.id = UUID().uuidString
        self.severity = severity
        self.message = message
        self.topicId = topicId
        self.date = Date()
        self.alertType = alertType
    }
}

// MARK: - Debate Insight

/// Cross-topic analytical insights.
struct DebateInsight: Codable, Identifiable {
    enum InsightType: String, Codable {
        case bridgeConcept
        case hiddenConsensus
        case framingDifference
        case evidenceGap
        case sourceCluster
    }

    let id: String
    let insightType: InsightType
    let description: String
    let relatedTopicIds: [String]
    let confidence: Double

    init(insightType: InsightType, description: String,
         relatedTopicIds: [String], confidence: Double) {
        self.id = UUID().uuidString
        self.insightType = insightType
        self.description = description
        self.relatedTopicIds = relatedTopicIds
        self.confidence = min(1.0, max(0.0, confidence))
    }
}

// MARK: - Feed Debate Arena

/// Autonomous debate extraction and analysis engine.
class FeedDebateArena {

    // MARK: - Properties

    private(set) var topics: [DebateTopic] = []
    private(set) var alerts: [DebateAlert] = []
    private(set) var insights: [DebateInsight] = []
    private var pendingArguments: [DebateArgument] = []

    var isAutoMonitorEnabled: Bool = false
    var polarizationThreshold: Double = 0.3
    var minimumArgumentsForDebate: Int = 3
    var topicSimilarityThreshold: Double = 0.3

    private let storageKey = "FeedDebateArena_Data"

    // MARK: - Stance Indicator Words

    private let proIndicators: Set<String> = [
        "supports", "advocates", "benefit", "benefits", "advantage", "advantages",
        "proves", "proven", "improves", "improvement", "progress", "promising",
        "opportunity", "innovation", "breakthrough", "solution", "effective",
        "successful", "recommends", "endorses", "favors", "praises", "applauds",
        "welcomes", "celebrates", "enables", "empowers", "strengthens", "positive",
        "optimistic", "encouraging", "constructive", "productive", "efficient",
        "should", "must", "essential", "necessary", "important", "vital"
    ]

    private let conIndicators: Set<String> = [
        "opposes", "criticizes", "risk", "risks", "danger", "dangerous",
        "fails", "failure", "harmful", "damage", "threatens", "threatens",
        "warns", "warning", "concern", "concerns", "problematic", "flawed",
        "inadequate", "insufficient", "rejects", "condemns", "denounces",
        "undermines", "weakens", "negative", "pessimistic", "controversial",
        "questionable", "dubious", "misleading", "alarming", "devastating",
        "crisis", "catastrophe", "ban", "prohibit", "restrict", "oppose"
    ]

    private let negationWords: Set<String> = [
        "not", "no", "never", "neither", "nor", "hardly", "barely",
        "scarcely", "don't", "doesn't", "didn't", "won't", "wouldn't",
        "can't", "cannot", "isn't", "aren't", "wasn't", "weren't"
    ]

    private let claimIndicators: Set<String> = [
        "because", "therefore", "however", "although", "despite",
        "argues", "claims", "suggests", "demonstrates", "reveals",
        "according", "study", "research", "evidence", "data",
        "shows", "indicates", "proves", "confirms", "found",
        "report", "survey", "analysis", "experts", "scientists",
        "should", "must", "will", "could", "would"
    ]

    // MARK: - Initialization

    init() {
        load()
    }

    // MARK: - Article Ingestion

    /// Analyze an article, extract claims, classify stance, and queue for topic assignment.
    @discardableResult
    func ingestArticle(title: String, link: String, source: String,
                       content: String, date: Date = Date()) -> [DebateArgument] {
        let words = tokenize(content)
        let keywords = extractKeywords(from: words, limit: 15)
        let claims = extractClaims(from: content)
        var extracted: [DebateArgument] = []

        if claims.isEmpty {
            // Treat entire article as a single argument
            let (stance, confidence) = classifyStance(text: content, keywords: keywords)
            let arg = DebateArgument(
                articleTitle: title, articleLink: link, sourceFeed: source,
                date: date, stance: stance,
                claimText: String(content.prefix(300)),
                supportingEvidence: [],
                confidence: confidence, keywords: keywords)
            extracted.append(arg)
        } else {
            for (claim, evidence) in claims {
                let (stance, confidence) = classifyStance(text: claim, keywords: keywords)
                let arg = DebateArgument(
                    articleTitle: title, articleLink: link, sourceFeed: source,
                    date: date, stance: stance,
                    claimText: claim,
                    supportingEvidence: evidence,
                    confidence: confidence, keywords: keywords)
                extracted.append(arg)
            }
        }

        pendingArguments.append(contentsOf: extracted)

        // Auto-assign to existing topics or hold for clustering
        assignToTopics(extracted)

        if isAutoMonitorEnabled {
            runAutoMonitor()
        }

        save()
        return extracted
    }

    // MARK: - Claim Extraction

    /// Extract claim sentences and their supporting evidence from text.
    func extractClaims(from text: String) -> [(String, [String])] {
        let sentences = splitSentences(text)
        guard sentences.count >= 2 else { return [] }

        var claims: [(String, [String])] = []

        for (index, sentence) in sentences.enumerated() {
            let lower = sentence.lowercased()
            let words = Set(tokenize(lower))
            let claimScore = Double(words.intersection(claimIndicators).count)

            // Sentences with opinion verbs, causal language, or quantitative claims
            let hasNumbers = sentence.range(of: "\\d+", options: .regularExpression) != nil
            let adjustedScore = claimScore + (hasNumbers ? 1.0 : 0.0)

            if adjustedScore >= 2.0 {
                // Gather nearby sentences as evidence
                var evidence: [String] = []
                if index > 0 { evidence.append(sentences[index - 1]) }
                if index < sentences.count - 1 { evidence.append(sentences[index + 1]) }

                claims.append((String(sentence.prefix(300)), evidence))
            }
        }

        return claims
    }

    // MARK: - Stance Classification

    /// Classify the stance of text using indicator word lists with negation detection.
    func classifyStance(text: String, keywords: [String]) -> (DebateStance, Double) {
        let words = tokenize(text.lowercased())
        var proScore: Double = 0
        var conScore: Double = 0

        for (index, word) in words.enumerated() {
            let isNegated = index > 0 && negationWords.contains(words[index - 1])

            if proIndicators.contains(word) {
                if isNegated { conScore += 1.0 } else { proScore += 1.0 }
            }
            if conIndicators.contains(word) {
                if isNegated { proScore += 1.0 } else { conScore += 1.0 }
            }
        }

        let total = proScore + conScore
        guard total > 0 else {
            return (.neutral, 0.3)
        }

        let ratio = proScore / total
        let confidence = min(1.0, total / 10.0)

        if ratio > 0.65 {
            return (.for, confidence)
        } else if ratio < 0.35 {
            return (.against, confidence)
        } else if total >= 3 {
            return (.mixed, confidence)
        } else {
            return (.neutral, confidence * 0.5)
        }
    }

    // MARK: - Topic Clustering

    /// Cluster pending and existing arguments into debate topics using keyword overlap.
    func detectTopics() {
        // Build keyword sets per argument
        for arg in pendingArguments {
            assignArgumentToTopic(arg)
        }
        pendingArguments.removeAll()

        // Merge similar topics
        mergeSimilarTopics()
        save()
    }

    private func assignToTopics(_ arguments: [DebateArgument]) {
        for arg in arguments {
            assignArgumentToTopic(arg)
        }
        // Remove from pending since we processed them
        pendingArguments.removeAll(where: { a in arguments.contains(where: { $0.id == a.id }) })
    }

    private func assignArgumentToTopic(_ arg: DebateArgument) {
        let argKeywords = Set(arg.keywords.map { $0.lowercased() })

        // Find best matching topic
        var bestMatch: Int? = nil
        var bestSimilarity: Double = 0

        for (index, topic) in topics.enumerated() {
            let topicKeywords = Set(topic.keywords.map { $0.lowercased() })
            let similarity = jaccardSimilarity(argKeywords, topicKeywords)
            if similarity > bestSimilarity {
                bestSimilarity = similarity
                bestMatch = index
            }
        }

        if let match = bestMatch, bestSimilarity >= topicSimilarityThreshold {
            topics[match].arguments.append(arg)
            topics[match].lastUpdated = Date()

            // Expand topic keywords
            let newKeywords = arg.keywords.filter { !topics[match].keywords.contains($0) }
            if !newKeywords.isEmpty {
                topics[match].keywords.append(contentsOf: newKeywords.prefix(5))
            }
        } else {
            // Create new topic
            let label = generateTopicLabel(from: arg.keywords)
            var topic = DebateTopic(topicLabel: label, keywords: arg.keywords,
                                     arguments: [arg])
            topic.lastUpdated = Date()
            topics.append(topic)
            NotificationCenter.default.post(name: .debateTopicCreated, object: nil,
                                            userInfo: ["topicId": topic.id])
        }
    }

    private func mergeSimilarTopics() {
        var merged = true
        while merged {
            merged = false
            outerLoop: for i in 0..<topics.count {
                for j in (i + 1)..<topics.count {
                    let kwA = Set(topics[i].keywords.map { $0.lowercased() })
                    let kwB = Set(topics[j].keywords.map { $0.lowercased() })
                    if jaccardSimilarity(kwA, kwB) >= 0.5 {
                        // Merge j into i
                        topics[i].arguments.append(contentsOf: topics[j].arguments)
                        let newKw = topics[j].keywords.filter { !topics[i].keywords.contains($0) }
                        topics[i].keywords.append(contentsOf: newKw)
                        topics[i].lastUpdated = Date()
                        topics.remove(at: j)
                        merged = true
                        break outerLoop
                    }
                }
            }
        }
    }

    // MARK: - Echo Chamber Detection

    /// Check if all sources covering a topic lean the same way.
    func detectEchoChamber(topicId: String) -> Bool {
        guard let topic = topics.first(where: { $0.id == topicId }) else { return false }
        let stancedArgs = topic.arguments.filter { $0.stance == .for || $0.stance == .against }
        guard stancedArgs.count >= 3 else { return false }

        let sources = Set(stancedArgs.map { $0.sourceFeed })
        guard sources.count >= 2 else { return false }

        // Group stances by source
        var sourceStances: [String: [DebateStance]] = [:]
        for arg in stancedArgs {
            sourceStances[arg.sourceFeed, default: []].append(arg.stance)
        }

        // Check if all sources have same dominant stance
        let dominantStances = sourceStances.values.compactMap { stances -> DebateStance? in
            let forCount = stances.filter { $0 == .for }.count
            let againstCount = stances.filter { $0 == .against }.count
            return forCount >= againstCount ? .for : .against
        }

        let uniqueStances = Set(dominantStances)
        return uniqueStances.count == 1
    }

    // MARK: - Balance Calculation

    /// Calculate balance score for a topic.
    func calculateBalance(topicId: String) -> Double {
        guard let topic = topics.first(where: { $0.id == topicId }) else { return 1.0 }
        return topic.balanceScore
    }

    // MARK: - Insight Generation

    /// Generate cross-topic insights: bridge concepts, hidden consensus, framing differences.
    func generateInsights() -> [DebateInsight] {
        var newInsights: [DebateInsight] = []

        // Bridge concepts: keywords appearing in multiple topics
        if topics.count >= 2 {
            var keywordTopics: [String: [String]] = [:]
            for topic in topics {
                for kw in topic.keywords {
                    let lower = kw.lowercased()
                    keywordTopics[lower, default: []].append(topic.id)
                }
            }
            for (keyword, topicIds) in keywordTopics {
                let unique = Array(Set(topicIds))
                if unique.count >= 2 {
                    let insight = DebateInsight(
                        insightType: .bridgeConcept,
                        description: "'\(keyword)' bridges \(unique.count) debates — may link related controversies",
                        relatedTopicIds: unique,
                        confidence: min(1.0, Double(unique.count) / Double(topics.count)))
                    newInsights.append(insight)
                }
            }
        }

        // Hidden consensus: opposing sources agreeing on sub-claims
        for topic in topics where topic.arguments.count >= 4 {
            let forSources = Set(topic.arguments.filter { $0.stance == .for }.map { $0.sourceFeed })
            let againstSources = Set(topic.arguments.filter { $0.stance == .against }.map { $0.sourceFeed })
            let overlap = forSources.intersection(againstSources)
            if !overlap.isEmpty {
                let insight = DebateInsight(
                    insightType: .hiddenConsensus,
                    description: "\(overlap.count) source(s) argue both sides of '\(topic.topicLabel)' — may indicate nuanced position",
                    relatedTopicIds: [topic.id],
                    confidence: 0.7)
                newInsights.append(insight)
            }
        }

        // Framing differences: same topic, different keyword emphasis
        for topic in topics where topic.arguments.count >= 4 {
            let forKeywords = Set(topic.arguments.filter { $0.stance == .for }.flatMap { $0.keywords })
            let againstKeywords = Set(topic.arguments.filter { $0.stance == .against }.flatMap { $0.keywords })
            let onlyFor = forKeywords.subtracting(againstKeywords)
            let onlyAgainst = againstKeywords.subtracting(forKeywords)
            if onlyFor.count >= 3 && onlyAgainst.count >= 3 {
                let forSample = Array(onlyFor.prefix(3)).joined(separator: ", ")
                let againstSample = Array(onlyAgainst.prefix(3)).joined(separator: ", ")
                let insight = DebateInsight(
                    insightType: .framingDifference,
                    description: "Framing split in '\(topic.topicLabel)': supporters emphasize [\(forSample)], opponents focus on [\(againstSample)]",
                    relatedTopicIds: [topic.id],
                    confidence: 0.65)
                newInsights.append(insight)
            }
        }

        // Evidence gaps: topics with many claims but little evidence
        for topic in topics where topic.arguments.count >= 3 {
            let evidenceCount = topic.arguments.reduce(0) { $0 + $1.supportingEvidence.count }
            let argCount = topic.arguments.count
            if argCount >= 4 && evidenceCount < argCount {
                let insight = DebateInsight(
                    insightType: .evidenceGap,
                    description: "'\(topic.topicLabel)' has \(argCount) claims but only \(evidenceCount) pieces of evidence — needs more substantiation",
                    relatedTopicIds: [topic.id],
                    confidence: 0.6)
                newInsights.append(insight)
            }
        }

        // Source clusters: groups of sources always taking same stance
        if topics.count >= 2 {
            var sourceStanceProfile: [String: [Double]] = [:]
            for topic in topics {
                for arg in topic.arguments {
                    sourceStanceProfile[arg.sourceFeed, default: []].append(arg.stance.numericValue)
                }
            }
            let sources = Array(sourceStanceProfile.keys)
            for i in 0..<sources.count {
                for j in (i + 1)..<sources.count {
                    let a = sourceStanceProfile[sources[i]] ?? []
                    let b = sourceStanceProfile[sources[j]] ?? []
                    if a.count >= 3 && b.count >= 3 {
                        let avgA = a.reduce(0, +) / Double(a.count)
                        let avgB = b.reduce(0, +) / Double(b.count)
                        if abs(avgA - avgB) < 0.2 {
                            let insight = DebateInsight(
                                insightType: .sourceCluster,
                                description: "'\(sources[i])' and '\(sources[j])' consistently align — possible editorial cluster",
                                relatedTopicIds: [],
                                confidence: 0.55)
                            newInsights.append(insight)
                        }
                    }
                }
            }
        }

        insights = newInsights
        return newInsights
    }

    // MARK: - Auto Monitor

    /// Full analysis cycle: re-cluster, score, detect alerts, generate insights.
    func runAutoMonitor() {
        detectTopics()

        var newAlerts: [DebateAlert] = []

        for topic in topics where topic.arguments.count >= minimumArgumentsForDebate {
            // Unbalanced coverage
            if topic.balanceScore < polarizationThreshold {
                let alert = DebateAlert(
                    severity: .warning,
                    message: "'\(topic.topicLabel)' is heavily \(topic.dominantStance.label)-leaning (balance: \(String(format: "%.0f%%", topic.balanceScore * 100)))",
                    topicId: topic.id,
                    alertType: .unbalancedCoverage)
                newAlerts.append(alert)
            }

            // Echo chamber
            if detectEchoChamber(topicId: topic.id) {
                let alert = DebateAlert(
                    severity: .critical,
                    message: "Echo chamber detected in '\(topic.topicLabel)' — all \(topic.sourceCount) sources lean \(topic.dominantStance.label)",
                    topicId: topic.id,
                    alertType: .echoChamber)
                newAlerts.append(alert)
                NotificationCenter.default.post(name: .debateEchoChamberDetected, object: nil,
                                                userInfo: ["topicId": topic.id])
            }

            // Consensus forming: high balance + many sources
            if topic.balanceScore > 0.8 && topic.sourceCount >= 3 {
                let forCount = topic.arguments.filter { $0.stance == .for }.count
                let againstCount = topic.arguments.filter { $0.stance == .against }.count
                if forCount >= 2 && againstCount >= 2 {
                    let alert = DebateAlert(
                        severity: .info,
                        message: "Balanced debate on '\(topic.topicLabel)' with \(topic.sourceCount) sources — consensus may be forming",
                        topicId: topic.id,
                        alertType: .consensusForming)
                    newAlerts.append(alert)
                    NotificationCenter.default.post(name: .debateConsensusForming, object: nil,
                                                    userInfo: ["topicId": topic.id])
                }
            }

            // Stale debate: no new arguments in 7+ days
            if let lastArg = topic.arguments.sorted(by: { $0.date > $1.date }).first {
                let daysSince = Calendar.current.dateComponents([.day], from: lastArg.date, to: Date()).day ?? 0
                if daysSince >= 7 {
                    let alert = DebateAlert(
                        severity: .info,
                        message: "'\(topic.topicLabel)' debate has been quiet for \(daysSince) days",
                        topicId: topic.id,
                        alertType: .staleDebate)
                    newAlerts.append(alert)
                }
            }

            // New contradictions: arguments from same source with opposing stances
            let sourceGroups = Dictionary(grouping: topic.arguments, by: { $0.sourceFeed })
            for (source, args) in sourceGroups {
                let hasFor = args.contains { $0.stance == .for }
                let hasAgainst = args.contains { $0.stance == .against }
                if hasFor && hasAgainst {
                    let alert = DebateAlert(
                        severity: .warning,
                        message: "'\(source)' contradicts itself on '\(topic.topicLabel)' — published both supporting and opposing views",
                        topicId: topic.id,
                        alertType: .newContradiction)
                    newAlerts.append(alert)
                }
            }
        }

        alerts = newAlerts
        if !newAlerts.isEmpty {
            NotificationCenter.default.post(name: .debateAlertGenerated, object: nil,
                                            userInfo: ["count": newAlerts.count])
        }

        let _ = generateInsights()
        save()
    }

    // MARK: - Summaries

    /// Generate a text summary of a debate showing both sides.
    func getDebateSummary(topicId: String) -> String {
        guard let topic = topics.first(where: { $0.id == topicId }) else {
            return "Topic not found."
        }

        var lines: [String] = []
        lines.append("═══ DEBATE: \(topic.topicLabel.uppercased()) ═══")
        lines.append("")

        let forArgs = topic.arguments.filter { $0.stance == .for }
        let againstArgs = topic.arguments.filter { $0.stance == .against }
        let mixedArgs = topic.arguments.filter { $0.stance == .mixed }

        lines.append("Balance: \(String(format: "%.0f%%", topic.balanceScore * 100)) | Sources: \(topic.sourceCount) | Controversial: \(topic.isControversial ? "Yes" : "No")")
        lines.append("")

        if !forArgs.isEmpty {
            lines.append("✅ FOR (\(forArgs.count) arguments):")
            for arg in forArgs.prefix(5) {
                lines.append("  • [\(arg.sourceFeed)] \(arg.claimText)")
            }
            lines.append("")
        }

        if !againstArgs.isEmpty {
            lines.append("❌ AGAINST (\(againstArgs.count) arguments):")
            for arg in againstArgs.prefix(5) {
                lines.append("  • [\(arg.sourceFeed)] \(arg.claimText)")
            }
            lines.append("")
        }

        if !mixedArgs.isEmpty {
            lines.append("⚖️ MIXED (\(mixedArgs.count) arguments):")
            for arg in mixedArgs.prefix(3) {
                lines.append("  • [\(arg.sourceFeed)] \(arg.claimText)")
            }
            lines.append("")
        }

        return lines.joined(separator: "\n")
    }

    /// Get the most active/controversial debates.
    func getTopDebates(limit: Int = 10) -> [DebateTopic] {
        return topics
            .filter { $0.arguments.count >= minimumArgumentsForDebate }
            .sorted { a, b in
                // Controversial first, then by argument count
                if a.isControversial != b.isControversial {
                    return a.isControversial
                }
                return a.arguments.count > b.arguments.count
            }
            .prefix(limit)
            .map { $0 }
    }

    /// Get a full report of all debates, alerts, and insights.
    func getFullReport() -> String {
        var lines: [String] = []
        lines.append("╔══════════════════════════════════════╗")
        lines.append("║       FEED DEBATE ARENA REPORT       ║")
        lines.append("╚══════════════════════════════════════╝")
        lines.append("")
        lines.append("Topics: \(topics.count) | Arguments: \(topics.reduce(0) { $0 + $1.arguments.count }) | Alerts: \(alerts.count) | Insights: \(insights.count)")
        lines.append("")

        let topDebates = getTopDebates(limit: 5)
        if !topDebates.isEmpty {
            lines.append("── TOP DEBATES ──")
            for topic in topDebates {
                let flag = topic.isControversial ? "🔥" : "💬"
                lines.append("\(flag) \(topic.topicLabel) — \(topic.arguments.count) args, balance \(String(format: "%.0f%%", topic.balanceScore * 100)), \(topic.sourceCount) sources")
            }
            lines.append("")
        }

        if !alerts.isEmpty {
            lines.append("── ALERTS ──")
            for alert in alerts.prefix(10) {
                let icon: String
                switch alert.severity {
                case .critical: icon = "🚨"
                case .warning: icon = "⚠️"
                case .info: icon = "ℹ️"
                }
                lines.append("\(icon) \(alert.message)")
            }
            lines.append("")
        }

        if !insights.isEmpty {
            lines.append("── INSIGHTS ──")
            for insight in insights.prefix(10) {
                let icon: String
                switch insight.insightType {
                case .bridgeConcept: icon = "🌉"
                case .hiddenConsensus: icon = "🤝"
                case .framingDifference: icon = "🔀"
                case .evidenceGap: icon = "❓"
                case .sourceCluster: icon = "👥"
                }
                lines.append("\(icon) \(insight.description)")
            }
        }

        return lines.joined(separator: "\n")
    }

    // MARK: - Export

    /// Export all debate data as JSON.
    func exportJSON() -> String {
        struct ExportData: Codable {
            let topics: [DebateTopic]
            let alerts: [DebateAlert]
            let insights: [DebateInsight]
            let exportDate: Date
            let stats: ExportStats
        }
        struct ExportStats: Codable {
            let topicCount: Int
            let totalArguments: Int
            let alertCount: Int
            let insightCount: Int
            let controversialTopics: Int
            let echoChamberCount: Int
        }

        let stats = ExportStats(
            topicCount: topics.count,
            totalArguments: topics.reduce(0) { $0 + $1.arguments.count },
            alertCount: alerts.count,
            insightCount: insights.count,
            controversialTopics: topics.filter { $0.isControversial }.count,
            echoChamberCount: alerts.filter { $0.alertType == .echoChamber }.count)

        let data = ExportData(
            topics: topics, alerts: alerts, insights: insights,
            exportDate: Date(), stats: stats)

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]

        guard let jsonData = try? encoder.encode(data),
              let jsonString = String(data: jsonData, encoding: .utf8) else {
            return "{\"error\": \"Export failed\"}"
        }
        return jsonString
    }

    // MARK: - Persistence

    func save() {
        struct StorageData: Codable {
            let topics: [DebateTopic]
            let alerts: [DebateAlert]
            let insights: [DebateInsight]
            let isAutoMonitorEnabled: Bool
            let polarizationThreshold: Double
        }

        let data = StorageData(
            topics: topics, alerts: alerts, insights: insights,
            isAutoMonitorEnabled: isAutoMonitorEnabled,
            polarizationThreshold: polarizationThreshold)

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        if let encoded = try? encoder.encode(data) {
            UserDefaults.standard.set(encoded, forKey: storageKey)
        }
    }

    func load() {
        struct StorageData: Codable {
            let topics: [DebateTopic]
            let alerts: [DebateAlert]
            let insights: [DebateInsight]
            let isAutoMonitorEnabled: Bool
            let polarizationThreshold: Double
        }

        guard let data = UserDefaults.standard.data(forKey: storageKey) else { return }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        if let stored = try? decoder.decode(StorageData.self, from: data) {
            topics = stored.topics
            alerts = stored.alerts
            insights = stored.insights
            isAutoMonitorEnabled = stored.isAutoMonitorEnabled
            polarizationThreshold = stored.polarizationThreshold
        }
    }

    /// Reset all data.
    func reset() {
        topics.removeAll()
        alerts.removeAll()
        insights.removeAll()
        pendingArguments.removeAll()
        UserDefaults.standard.removeObject(forKey: storageKey)
    }

    // MARK: - Text Utilities

    private func tokenize(_ text: String) -> [String] {
        let lower = text.lowercased()
        let cleaned = lower.unicodeScalars.map { CharacterSet.letters.contains($0) || $0 == " " ? Character($0) : Character(" ") }
        return String(cleaned).split(separator: " ").map(String.init).filter { $0.count > 2 }
    }

    private func extractKeywords(from words: [String], limit: Int = 15) -> [String] {
        let stopWords: Set<String> = [
            "the", "and", "for", "are", "but", "not", "you", "all", "can",
            "had", "her", "was", "one", "our", "out", "has", "have", "been",
            "that", "this", "with", "they", "from", "will", "would", "there",
            "their", "what", "about", "which", "when", "make", "like", "time",
            "very", "your", "than", "them", "some", "could", "other", "into",
            "more", "also", "its", "over", "such", "how", "said", "each"
        ]

        var freq: [String: Int] = [:]
        for w in words where !stopWords.contains(w) && w.count > 3 {
            freq[w, default: 0] += 1
        }
        return freq.sorted { $0.value > $1.value }.prefix(limit).map { $0.key }
    }

    private func splitSentences(_ text: String) -> [String] {
        let delimiters = CharacterSet(charactersIn: ".!?")
        return text.unicodeScalars
            .split { delimiters.contains($0) }
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { $0.count > 20 }
    }

    private func jaccardSimilarity(_ a: Set<String>, _ b: Set<String>) -> Double {
        guard !a.isEmpty || !b.isEmpty else { return 0 }
        let intersection = Double(a.intersection(b).count)
        let union = Double(a.union(b).count)
        return intersection / union
    }

    private func generateTopicLabel(from keywords: [String]) -> String {
        let top = keywords.prefix(3).map { $0.capitalized }
        return top.joined(separator: " / ")
    }
}
