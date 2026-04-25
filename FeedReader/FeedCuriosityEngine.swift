//
//  FeedCuriosityEngine.swift
//  FeedReader
//
//  Autonomous curiosity-driven exploration engine that analyzes reading
//  patterns to identify knowledge gaps, generate unanswered questions,
//  and suggest exploration paths. Encourages deeper reading by detecting
//  surface-level engagement and nudging toward deeper understanding.
//
//  How it works:
//    1. Articles are ingested with topics, keywords, and reading depth
//       signals (time spent, scroll percentage, highlights made)
//    2. The engine builds a "curiosity map" — topics with depth scores
//       showing how deeply the user has explored each area
//    3. Gap detection identifies topics the user reads about shallowly
//       but frequently (high breadth, low depth = knowledge gap)
//    4. Question generation creates open-ended questions based on
//       topic intersections and unexplored edges
//    5. Exploration paths suggest sequences of reads that would
//       deepen understanding in gap areas
//    6. Auto-monitor mode periodically surfaces curiosity nudges
//
//  Usage:
//    let engine = FeedCuriosityEngine()
//    engine.ingest(articleId: "a1", title: "Intro to Quantum Computing",
//        topics: ["quantum", "computing"], keywords: ["qubit", "superposition"],
//        readingDepth: .skim, date: Date())
//    engine.ingest(articleId: "a2", title: "Quantum Error Correction",
//        topics: ["quantum", "error correction"], keywords: ["decoherence"],
//        readingDepth: .deep, date: Date())
//
//    let gaps = engine.knowledgeGaps(topN: 5)
//    let questions = engine.curiosityQuestions(topN: 10)
//    let paths = engine.explorationPaths(topN: 3)
//    let report = engine.curiosityReport()
//
//  Persistence: JSON file in Documents directory.
//  Fully offline — no network, no dependencies beyond Foundation.
//

import Foundation

// MARK: - Notifications

extension Notification.Name {
    /// Posted when a new knowledge gap is detected.
    static let curiosityGapDetected = Notification.Name("FeedCuriosityGapDetectedNotification")
    /// Posted when curiosity questions are generated.
    static let curiosityQuestionsGenerated = Notification.Name("FeedCuriosityQuestionsGeneratedNotification")
    /// Posted when auto-monitor discovers new exploration opportunities.
    static let curiosityNudge = Notification.Name("FeedCuriosityNudgeNotification")
}

// MARK: - Reading Depth

/// How deeply the user engaged with an article.
enum ReadingDepth: String, Codable, CaseIterable, Comparable {
    case glance      // < 10s or < 10% scroll
    case skim        // 10-60s or 10-50% scroll
    case read        // 1-5 min or 50-90% scroll
    case deep        // > 5 min or > 90% scroll, highlights
    case study       // Bookmarked, noted, revisited

    var score: Double {
        switch self {
        case .glance: return 0.1
        case .skim:   return 0.3
        case .read:   return 0.6
        case .deep:   return 0.85
        case .study:  return 1.0
        }
    }

    var displayName: String {
        switch self {
        case .glance: return "Glance"
        case .skim:   return "Skim"
        case .read:   return "Read"
        case .deep:   return "Deep Read"
        case .study:  return "Study"
        }
    }

    static func < (lhs: ReadingDepth, rhs: ReadingDepth) -> Bool {
        lhs.score < rhs.score
    }
}

// MARK: - Data Models

/// Record of a single article ingestion.
struct CuriosityArticleRecord: Codable {
    let articleId: String
    let title: String
    let topics: [String]
    let keywords: [String]
    let readingDepth: ReadingDepth
    let date: Date
}

/// A topic node in the curiosity map.
struct CuriosityTopicNode: Codable {
    let topic: String
    var articleCount: Int
    var totalDepthScore: Double
    var keywords: [String: Int]           // keyword -> frequency
    var connectedTopics: [String: Int]    // co-occurring topic -> count
    var firstSeen: Date
    var lastSeen: Date
    var depthHistory: [DepthSample]

    /// Average depth across all articles.
    var averageDepth: Double {
        guard articleCount > 0 else { return 0 }
        return totalDepthScore / Double(articleCount)
    }

    /// Breadth: how many unique keywords touched.
    var breadth: Int { keywords.count }

    /// Gap score: high breadth + low depth = knowledge gap.
    var gapScore: Double {
        guard articleCount >= 2 else { return 0 }
        let depthPenalty = max(0, 1.0 - averageDepth)
        let breadthSignal = min(1.0, Double(breadth) / 10.0)
        let frequencySignal = min(1.0, Double(articleCount) / 5.0)
        return depthPenalty * breadthSignal * frequencySignal
    }
}

/// Depth sample for tracking engagement over time.
struct DepthSample: Codable {
    let date: Date
    let depth: ReadingDepth
}

/// A detected knowledge gap.
struct KnowledgeGap: Codable {
    let topic: String
    let gapScore: Double
    let articleCount: Int
    let averageDepth: Double
    let breadth: Int
    let unexploredKeywords: [String]
    let suggestedDirection: String
}

/// A curiosity question generated from reading patterns.
struct CuriosityQuestion: Codable {
    let question: String
    let category: QuestionCategory
    let relatedTopics: [String]
    let confidence: Double
}

/// Categories of curiosity questions.
enum QuestionCategory: String, Codable, CaseIterable {
    case bridging       // Connects two topics the user reads separately
    case deepening      // Goes deeper into a shallow topic
    case contrasting    // Explores opposing viewpoints
    case application    // How to apply knowledge practically
    case historical     // Origins and history of a topic
    case future         // Future implications and trends

    var displayName: String {
        switch self {
        case .bridging:    return "Bridging"
        case .deepening:   return "Deepening"
        case .contrasting: return "Contrasting"
        case .application: return "Application"
        case .historical:  return "Historical"
        case .future:      return "Future"
        }
    }

    var template: String {
        switch self {
        case .bridging:    return "How does %@ relate to %@?"
        case .deepening:   return "What are the deeper mechanics behind %@?"
        case .contrasting: return "What are the counterarguments to mainstream views on %@?"
        case .application: return "How could understanding %@ change practical decisions?"
        case .historical:  return "What historical developments led to current thinking on %@?"
        case .future:      return "Where is %@ heading in the next 5 years?"
        }
    }
}

/// A suggested exploration path.
struct ExplorationPath: Codable {
    let title: String
    let description: String
    let topics: [String]
    let estimatedArticles: Int
    let depthTarget: ReadingDepth
    let priority: Double
}

/// Curiosity profile summary.
struct CuriosityProfile: Codable {
    let totalTopics: Int
    let totalArticles: Int
    let averageDepth: Double
    let deepestTopic: String?
    let shallowestTopic: String?
    let biggestGap: String?
    let curiosityScore: Double      // 0-100, higher = more curious/exploratory
    let explorerType: ExplorerType
}

/// Archetype classification based on reading behavior.
enum ExplorerType: String, Codable {
    case butterfly      // Many topics, shallow depth
    case miner          // Few topics, great depth
    case explorer       // Many topics, good depth
    case specialist     // Moderate topics, deep in some
    case dormant        // Low activity

    var displayName: String {
        switch self {
        case .butterfly:  return "Butterfly"
        case .miner:      return "Deep Miner"
        case .explorer:   return "Explorer"
        case .specialist: return "Specialist"
        case .dormant:    return "Dormant"
        }
    }

    var description: String {
        switch self {
        case .butterfly:  return "You flit across many topics — try going deeper on ones that intrigue you."
        case .miner:      return "You dig deep into your interests — consider branching out to related fields."
        case .explorer:   return "You balance breadth and depth beautifully — keep exploring!"
        case .specialist: return "You have deep pockets of knowledge — bridge them to find surprising connections."
        case .dormant:    return "Your reading has slowed — what topic could reignite your curiosity?"
        }
    }
}

/// Persistent state.
struct CuriosityEngineState: Codable {
    var articles: [CuriosityArticleRecord]
    var topicNodes: [String: CuriosityTopicNode]
    var answeredQuestions: [String]   // Questions the user dismissed/answered
    var lastMonitorDate: Date?
    var nudgeHistory: [NudgeRecord]
}

/// Record of a curiosity nudge.
struct NudgeRecord: Codable {
    let date: Date
    let type: String
    let topic: String
    let accepted: Bool
}

// MARK: - FeedCuriosityEngine

/// Autonomous curiosity engine that identifies knowledge gaps and
/// generates exploration suggestions from reading patterns.
final class FeedCuriosityEngine {

    // MARK: - Properties

    private var state: CuriosityEngineState
    private let fileName = "feed_curiosity_engine.json"
    private var monitorTimer: Timer?

    /// Maximum articles to retain (rolling window).
    private let maxArticles = 2000

    // MARK: - Init

    init() {
        state = CuriosityEngineState(
            articles: [],
            topicNodes: [:],
            answeredQuestions: [],
            lastMonitorDate: nil,
            nudgeHistory: []
        )
        loadState()
    }

    // MARK: - Ingestion

    /// Ingest an article reading event.
    func ingest(articleId: String, title: String, topics: [String],
                keywords: [String], readingDepth: ReadingDepth, date: Date) {
        let normalizedTopics = topics.map { $0.lowercased().trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        let normalizedKeywords = keywords.map { $0.lowercased().trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }

        guard !normalizedTopics.isEmpty else { return }

        // Deduplicate
        if state.articles.contains(where: { $0.articleId == articleId }) { return }

        let record = CuriosityArticleRecord(
            articleId: articleId, title: title, topics: normalizedTopics,
            keywords: normalizedKeywords, readingDepth: readingDepth, date: date
        )
        state.articles.append(record)

        // Update topic nodes
        for topic in normalizedTopics {
            var node = state.topicNodes[topic] ?? CuriosityTopicNode(
                topic: topic, articleCount: 0, totalDepthScore: 0,
                keywords: [:], connectedTopics: [:],
                firstSeen: date, lastSeen: date, depthHistory: []
            )
            node.articleCount += 1
            node.totalDepthScore += readingDepth.score
            node.lastSeen = date
            node.depthHistory.append(DepthSample(date: date, depth: readingDepth))

            for kw in normalizedKeywords {
                node.keywords[kw, default: 0] += 1
            }
            for other in normalizedTopics where other != topic {
                node.connectedTopics[other, default: 0] += 1
            }
            state.topicNodes[topic] = node
        }

        // Trim old articles
        if state.articles.count > maxArticles {
            state.articles = Array(state.articles.suffix(maxArticles))
        }

        saveState()
        NotificationCenter.default.post(name: .curiosityGapDetected, object: nil)
    }

    // MARK: - Knowledge Gaps

    /// Detect knowledge gaps — topics with high breadth but low depth.
    func knowledgeGaps(topN: Int = 5) -> [KnowledgeGap] {
        let nodes = state.topicNodes.values
            .filter { $0.articleCount >= 2 && $0.gapScore > 0.1 }
            .sorted { $0.gapScore > $1.gapScore }

        return Array(nodes.prefix(topN)).map { node in
            let allKeywords = Set(node.keywords.keys)
            let deepArticles = state.articles.filter {
                $0.topics.contains(node.topic) && $0.readingDepth >= .deep
            }
            let deepKeywords = Set(deepArticles.flatMap { $0.keywords.map { $0.lowercased() } })
            let unexplored = Array(allKeywords.subtracting(deepKeywords).prefix(5))

            let direction = suggestDirection(for: node)

            return KnowledgeGap(
                topic: node.topic,
                gapScore: node.gapScore,
                articleCount: node.articleCount,
                averageDepth: node.averageDepth,
                breadth: node.breadth,
                unexploredKeywords: unexplored,
                suggestedDirection: direction
            )
        }
    }

    /// Suggest an exploration direction for a topic.
    private func suggestDirection(for node: CuriosityTopicNode) -> String {
        if node.averageDepth < 0.3 {
            return "Start with a comprehensive overview of \(node.topic)"
        }
        if let topConnected = node.connectedTopics.max(by: { $0.value < $1.value }) {
            let connectedNode = state.topicNodes[topConnected.key]
            if let cn = connectedNode, cn.averageDepth > node.averageDepth {
                return "Explore how \(topConnected.key) connects to \(node.topic) — you already understand \(topConnected.key) well"
            }
        }
        let recentDepths = node.depthHistory.suffix(3)
        let improving = recentDepths.count >= 2 &&
            recentDepths.last!.depth > recentDepths.first!.depth
        if improving {
            return "Your depth in \(node.topic) is improving — keep going deeper"
        }
        return "Look for articles that explain the 'why' behind \(node.topic), not just the 'what'"
    }

    // MARK: - Curiosity Questions

    /// Generate curiosity questions from reading patterns.
    func curiosityQuestions(topN: Int = 10) -> [CuriosityQuestion] {
        var questions: [CuriosityQuestion] = []

        // Bridging questions: find topic pairs that are both read but never together
        let topicPairs = findDisconnectedTopicPairs()
        for (t1, t2) in topicPairs.prefix(3) {
            let q = String(format: QuestionCategory.bridging.template, t1, t2)
            if !state.answeredQuestions.contains(q) {
                questions.append(CuriosityQuestion(
                    question: q, category: .bridging,
                    relatedTopics: [t1, t2], confidence: 0.8
                ))
            }
        }

        // Deepening questions: shallow but frequent topics
        let gaps = knowledgeGaps(topN: 3)
        for gap in gaps {
            let q = String(format: QuestionCategory.deepening.template, gap.topic)
            if !state.answeredQuestions.contains(q) {
                questions.append(CuriosityQuestion(
                    question: q, category: .deepening,
                    relatedTopics: [gap.topic], confidence: gap.gapScore
                ))
            }
        }

        // Contrasting questions: topics with many articles but same depth
        let monotoneTopics = state.topicNodes.values.filter { node in
            node.articleCount >= 3 &&
            node.depthHistory.count >= 3 &&
            Set(node.depthHistory.suffix(3).map { $0.depth }).count == 1
        }
        for node in monotoneTopics.prefix(2) {
            let q = String(format: QuestionCategory.contrasting.template, node.topic)
            if !state.answeredQuestions.contains(q) {
                questions.append(CuriosityQuestion(
                    question: q, category: .contrasting,
                    relatedTopics: [node.topic], confidence: 0.6
                ))
            }
        }

        // Application questions: deep topics that might have practical uses
        let deepTopics = state.topicNodes.values
            .filter { $0.averageDepth >= 0.7 && $0.articleCount >= 3 }
            .sorted { $0.averageDepth > $1.averageDepth }
        for node in deepTopics.prefix(2) {
            let q = String(format: QuestionCategory.application.template, node.topic)
            if !state.answeredQuestions.contains(q) {
                questions.append(CuriosityQuestion(
                    question: q, category: .application,
                    relatedTopics: [node.topic], confidence: 0.7
                ))
            }
        }

        // Future questions: trending topics (increasing article frequency)
        let trending = findTrendingTopics()
        for topic in trending.prefix(2) {
            let q = String(format: QuestionCategory.future.template, topic)
            if !state.answeredQuestions.contains(q) {
                questions.append(CuriosityQuestion(
                    question: q, category: .future,
                    relatedTopics: [topic], confidence: 0.75
                ))
            }
        }

        return Array(questions.sorted { $0.confidence > $1.confidence }.prefix(topN))
    }

    /// Find topic pairs that appear in the user's reading but never co-occur.
    private func findDisconnectedTopicPairs() -> [(String, String)] {
        let activeTopics = state.topicNodes.values
            .filter { $0.articleCount >= 2 }
            .sorted { $0.articleCount > $1.articleCount }
            .prefix(15)
            .map { $0.topic }

        var pairs: [(String, String, Double)] = []
        for i in 0..<activeTopics.count {
            for j in (i+1)..<activeTopics.count {
                let t1 = activeTopics[i]
                let t2 = activeTopics[j]
                let node1 = state.topicNodes[t1]!
                let coOccurrence = node1.connectedTopics[t2] ?? 0
                if coOccurrence == 0 {
                    let score = Double(node1.articleCount + state.topicNodes[t2]!.articleCount)
                    pairs.append((t1, t2, score))
                }
            }
        }
        return pairs.sorted { $0.2 > $1.2 }.map { ($0.0, $0.1) }
    }

    /// Find topics with increasing article frequency recently.
    private func findTrendingTopics() -> [String] {
        let now = Date()
        let cal = Calendar.current
        guard let twoWeeksAgo = cal.date(byAdding: .day, value: -14, to: now),
              let fourWeeksAgo = cal.date(byAdding: .day, value: -28, to: now) else {
            return []
        }

        var trending: [(String, Double)] = []
        for (topic, node) in state.topicNodes where node.articleCount >= 3 {
            let recentCount = node.depthHistory.filter { $0.date >= twoWeeksAgo }.count
            let priorCount = node.depthHistory.filter {
                $0.date >= fourWeeksAgo && $0.date < twoWeeksAgo
            }.count
            if recentCount > priorCount && recentCount >= 2 {
                let acceleration = Double(recentCount - priorCount) / max(1.0, Double(priorCount))
                trending.append((topic, acceleration))
            }
        }
        return trending.sorted { $0.1 > $1.1 }.map { $0.0 }
    }

    // MARK: - Exploration Paths

    /// Generate suggested exploration paths to deepen knowledge.
    func explorationPaths(topN: Int = 3) -> [ExplorationPath] {
        var paths: [ExplorationPath] = []

        // Path 1: Fill biggest knowledge gap
        let gaps = knowledgeGaps(topN: 3)
        for gap in gaps {
            let connected = state.topicNodes[gap.topic]?.connectedTopics
                .sorted { $0.value > $1.value }
                .prefix(3)
                .map { $0.key } ?? []
            let topicChain = [gap.topic] + connected

            paths.append(ExplorationPath(
                title: "Deep Dive: \(gap.topic.capitalized)",
                description: "You've touched \(gap.topic) \(gap.articleCount) times but mostly at surface level. "
                    + "Follow this path to build real understanding.",
                topics: topicChain,
                estimatedArticles: max(3, gap.articleCount),
                depthTarget: .deep,
                priority: gap.gapScore
            ))
        }

        // Path 2: Bridge disconnected areas
        let disconnected = findDisconnectedTopicPairs()
        for (t1, t2) in disconnected.prefix(2) {
            paths.append(ExplorationPath(
                title: "Bridge: \(t1.capitalized) ↔ \(t2.capitalized)",
                description: "You read about \(t1) and \(t2) separately — "
                    + "finding connections between them could yield surprising insights.",
                topics: [t1, t2],
                estimatedArticles: 3,
                depthTarget: .read,
                priority: 0.7
            ))
        }

        // Path 3: Deepen a strength
        if let strongest = state.topicNodes.values
            .filter({ $0.averageDepth >= 0.6 && $0.articleCount >= 4 })
            .max(by: { $0.averageDepth < $1.averageDepth }) {

            let adjacent = strongest.connectedTopics
                .filter { (state.topicNodes[$0.key]?.averageDepth ?? 0) < 0.5 }
                .sorted { $0.value > $1.value }
                .prefix(3)
                .map { $0.key }

            if !adjacent.isEmpty {
                paths.append(ExplorationPath(
                    title: "Expand Expertise: \(strongest.topic.capitalized)",
                    description: "You know \(strongest.topic) well — "
                        + "explore its weaker connections to become a true expert.",
                    topics: [strongest.topic] + adjacent,
                    estimatedArticles: adjacent.count + 1,
                    depthTarget: .deep,
                    priority: 0.65
                ))
            }
        }

        return Array(paths.sorted { $0.priority > $1.priority }.prefix(topN))
    }

    // MARK: - Curiosity Profile

    /// Generate a curiosity profile summarizing reading behavior.
    func curiosityProfile() -> CuriosityProfile {
        let topics = state.topicNodes
        let totalTopics = topics.count
        let totalArticles = state.articles.count
        let avgDepth = topics.values.isEmpty ? 0 :
            topics.values.map { $0.averageDepth }.reduce(0, +) / Double(topics.count)

        let deepest = topics.values.max(by: { $0.averageDepth < $1.averageDepth })?.topic
        let shallowest = topics.values
            .filter { $0.articleCount >= 2 }
            .min(by: { $0.averageDepth < $1.averageDepth })?.topic
        let biggestGap = knowledgeGaps(topN: 1).first?.topic

        // Curiosity score: balance of breadth, depth, and exploration rate
        let breadthScore = min(1.0, Double(totalTopics) / 20.0) * 30
        let depthScore = avgDepth * 40
        let explorationRate = recentExplorationRate() * 30
        let curiosityScore = min(100, breadthScore + depthScore + explorationRate)

        let explorerType = classifyExplorer(
            topicCount: totalTopics, avgDepth: avgDepth, articleCount: totalArticles
        )

        return CuriosityProfile(
            totalTopics: totalTopics,
            totalArticles: totalArticles,
            averageDepth: avgDepth,
            deepestTopic: deepest,
            shallowestTopic: shallowest,
            biggestGap: biggestGap,
            curiosityScore: curiosityScore,
            explorerType: explorerType
        )
    }

    /// Calculate how much new exploration happened recently.
    private func recentExplorationRate() -> Double {
        let cal = Calendar.current
        guard let twoWeeksAgo = cal.date(byAdding: .day, value: -14, to: Date()) else { return 0 }
        let recentArticles = state.articles.filter { $0.date >= twoWeeksAgo }
        let recentTopics = Set(recentArticles.flatMap { $0.topics })
        let allTopics = Set(state.topicNodes.keys)
        guard !allTopics.isEmpty else { return 0 }
        // New topics in recent period
        let olderArticles = state.articles.filter { $0.date < twoWeeksAgo }
        let olderTopics = Set(olderArticles.flatMap { $0.topics })
        let newTopics = recentTopics.subtracting(olderTopics)
        return min(1.0, Double(newTopics.count) / max(1.0, Double(recentTopics.count)))
    }

    /// Classify the user's explorer archetype.
    private func classifyExplorer(topicCount: Int, avgDepth: Double, articleCount: Int) -> ExplorerType {
        guard articleCount >= 5 else { return .dormant }
        let breadth = topicCount >= 8
        let deep = avgDepth >= 0.6

        switch (breadth, deep) {
        case (true, true):   return .explorer
        case (true, false):  return .butterfly
        case (false, true):  return .miner
        case (false, false): return .specialist
        }
    }

    // MARK: - Mark Question Answered

    /// Dismiss a curiosity question (user answered or not interested).
    func dismissQuestion(_ question: String) {
        state.answeredQuestions.append(question)
        // Keep bounded
        if state.answeredQuestions.count > 500 {
            state.answeredQuestions = Array(state.answeredQuestions.suffix(500))
        }
        saveState()
    }

    // MARK: - Curiosity Report

    /// Generate a full-text curiosity report.
    func curiosityReport() -> String {
        let profile = curiosityProfile()
        let gaps = knowledgeGaps(topN: 5)
        let questions = curiosityQuestions(topN: 8)
        let paths = explorationPaths(topN: 3)

        var lines: [String] = []
        lines.append("=== CURIOSITY REPORT ===")
        lines.append("")

        // Profile
        lines.append("## Your Curiosity Profile")
        lines.append("Type: \(profile.explorerType.displayName)")
        lines.append(profile.explorerType.description)
        lines.append("Curiosity Score: \(String(format: "%.0f", profile.curiosityScore))/100")
        lines.append("Topics explored: \(profile.totalTopics)")
        lines.append("Articles ingested: \(profile.totalArticles)")
        lines.append("Average depth: \(String(format: "%.1f%%", profile.averageDepth * 100))")
        if let d = profile.deepestTopic { lines.append("Deepest topic: \(d)") }
        if let s = profile.shallowestTopic { lines.append("Shallowest topic: \(s)") }
        lines.append("")

        // Knowledge Gaps
        if !gaps.isEmpty {
            lines.append("## Knowledge Gaps")
            for (i, gap) in gaps.enumerated() {
                lines.append("\(i+1). \(gap.topic.capitalized) (gap score: \(String(format: "%.2f", gap.gapScore)))")
                lines.append("   Articles: \(gap.articleCount), Avg depth: \(String(format: "%.0f%%", gap.averageDepth * 100))")
                if !gap.unexploredKeywords.isEmpty {
                    lines.append("   Unexplored: \(gap.unexploredKeywords.joined(separator: ", "))")
                }
                lines.append("   → \(gap.suggestedDirection)")
            }
            lines.append("")
        }

        // Questions
        if !questions.isEmpty {
            lines.append("## Curiosity Questions")
            for (i, q) in questions.enumerated() {
                lines.append("\(i+1). [\(q.category.displayName)] \(q.question)")
            }
            lines.append("")
        }

        // Exploration Paths
        if !paths.isEmpty {
            lines.append("## Exploration Paths")
            for (i, path) in paths.enumerated() {
                lines.append("\(i+1). \(path.title)")
                lines.append("   \(path.description)")
                lines.append("   Topics: \(path.topics.joined(separator: " → "))")
                lines.append("   Est. articles: \(path.estimatedArticles), Target depth: \(path.depthTarget.displayName)")
            }
            lines.append("")
        }

        // Recommendations
        lines.append("## Proactive Recommendations")
        let recs = recommendations()
        for rec in recs {
            lines.append("• \(rec)")
        }

        return lines.joined(separator: "\n")
    }

    /// Generate proactive recommendations.
    func recommendations() -> [String] {
        var recs: [String] = []
        let profile = curiosityProfile()

        switch profile.explorerType {
        case .butterfly:
            recs.append("Pick your top interest and commit to 3 deep reads this week")
        case .miner:
            recs.append("Try reading one article outside your comfort zone each day")
        case .explorer:
            recs.append("You're doing great — consider starting a reading journal to cement insights")
        case .specialist:
            recs.append("Look for articles that bridge your specialties for cross-pollination")
        case .dormant:
            recs.append("Start with just 5 minutes of reading today — momentum builds naturally")
        }

        let gaps = knowledgeGaps(topN: 2)
        for gap in gaps {
            recs.append("Knowledge gap in '\(gap.topic)' — you've read \(gap.articleCount) articles but mostly skimmed. Try one deep read.")
        }

        // Depth trend
        let recentArticles = state.articles.suffix(10)
        let recentAvgDepth = recentArticles.isEmpty ? 0 :
            recentArticles.map { $0.readingDepth.score }.reduce(0, +) / Double(recentArticles.count)
        if recentAvgDepth < 0.3 && !state.articles.isEmpty {
            recs.append("Your recent reading has been mostly skimming — slow down and engage more deeply")
        } else if recentAvgDepth > 0.7 {
            recs.append("Excellent reading depth recently — you're building real understanding")
        }

        return recs
    }

    // MARK: - Auto-Monitor

    /// Start auto-monitoring for curiosity nudges.
    func startAutoMonitor(intervalSeconds: TimeInterval = 3600) {
        stopAutoMonitor()
        monitorTimer = Timer.scheduledTimer(withTimeInterval: intervalSeconds, repeats: true) { [weak self] _ in
            self?.runMonitorCycle()
        }
    }

    /// Stop auto-monitoring.
    func stopAutoMonitor() {
        monitorTimer?.invalidate()
        monitorTimer = nil
    }

    /// Run a single monitor cycle.
    func runMonitorCycle() {
        let gaps = knowledgeGaps(topN: 1)
        if let gap = gaps.first, gap.gapScore > 0.4 {
            let nudge = NudgeRecord(date: Date(), type: "gap", topic: gap.topic, accepted: false)
            state.nudgeHistory.append(nudge)
            if state.nudgeHistory.count > 200 {
                state.nudgeHistory = Array(state.nudgeHistory.suffix(200))
            }
            state.lastMonitorDate = Date()
            saveState()
            NotificationCenter.default.post(
                name: .curiosityNudge, object: nil,
                userInfo: ["topic": gap.topic, "gapScore": gap.gapScore]
            )
        }
    }

    // MARK: - Topic Depth Over Time

    /// Get depth progression for a specific topic.
    func depthTimeline(for topic: String) -> [DepthSample] {
        return state.topicNodes[topic.lowercased()]?.depthHistory ?? []
    }

    // MARK: - Statistics

    /// Total number of topics tracked.
    var topicCount: Int { state.topicNodes.count }

    /// Total number of articles ingested.
    var articleCount: Int { state.articles.count }

    /// All tracked topic names.
    var allTopics: [String] { Array(state.topicNodes.keys.sorted()) }

    // MARK: - Export

    /// Export curiosity data as JSON string.
    func exportJSON() -> String? {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(state) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    // MARK: - Persistence

    private var fileURL: URL {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return docs.appendingPathComponent(fileName)
    }

    private func saveState() {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(state) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }

    private func loadState() {
        guard let data = try? Data(contentsOf: fileURL) else { return }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        if let loaded = try? decoder.decode(CuriosityEngineState.self, from: data) {
            state = loaded
        }
    }
}
