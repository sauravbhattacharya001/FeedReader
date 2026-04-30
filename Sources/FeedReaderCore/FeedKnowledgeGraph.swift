//
//  FeedKnowledgeGraph.swift
//  FeedReaderCore
//
//  Autonomous personal knowledge graph builder that extracts concepts
//  and entities from reading history, maps relationships between them,
//  detects knowledge gaps, and suggests articles to fill those gaps.
//
//  Key capabilities:
//  - **Concept Extraction:** Identifies key concepts/entities from articles
//  - **Relationship Mapping:** Discovers how concepts connect across articles
//  - **Knowledge Clusters:** Groups related concepts into topic clusters
//  - **Gap Detection:** Finds under-explored areas adjacent to strong knowledge
//  - **Learning Paths:** Suggests reading sequences to build expertise
//  - **Knowledge Decay:** Tracks concept freshness and suggests refreshers
//  - **Expertise Profiling:** Scores user's depth across topic areas
//
//  Usage:
//  ```swift
//  let graph = FeedKnowledgeGraph()
//
//  // Ingest reading history
//  let article = KGArticle(id: "1", title: "Intro to ML",
//      concepts: ["machine learning", "neural networks", "training"],
//      feedSource: "TechCrunch", readDate: Date())
//  graph.ingest(article)
//
//  // Get knowledge map
//  let report = graph.analyze()
//  print(report.clusters)          // Topic clusters
//  print(report.gaps)              // Knowledge gaps
//  print(report.expertiseProfile)  // Depth per topic
//  print(report.learningPaths)     // Suggested reading sequences
//  print(report.decayingConcepts)  // Concepts needing refresh
//  ```
//

import Foundation

// MARK: - Models

/// An article ingested into the knowledge graph.
public struct KGArticle: Sendable {
    /// Unique article identifier.
    public let id: String
    /// Article title.
    public let title: String
    /// Extracted concepts/entities from the article.
    public let concepts: [String]
    /// Source feed name.
    public let feedSource: String
    /// When the article was read.
    public let readDate: Date
    /// Optional category/topic tag.
    public let category: String?

    public init(id: String, title: String, concepts: [String],
                feedSource: String, readDate: Date, category: String? = nil) {
        self.id = id
        self.title = title
        self.concepts = concepts.map { $0.lowercased().trimmingCharacters(in: .whitespaces) }
        self.feedSource = feedSource
        self.readDate = readDate
        self.category = category
    }
}

/// A node in the knowledge graph representing a concept.
public struct KGNode: Sendable {
    /// The concept name (normalized lowercase).
    public let concept: String
    /// Number of articles mentioning this concept.
    public let frequency: Int
    /// First time this concept was encountered.
    public let firstSeen: Date
    /// Most recent encounter.
    public let lastSeen: Date
    /// Sources that mention this concept.
    public let sources: Set<String>
    /// Depth score (0-100) based on frequency, recency, source diversity.
    public let depthScore: Double
}

/// An edge connecting two concepts that co-occur in articles.
public struct KGEdge: Sendable {
    /// First concept.
    public let conceptA: String
    /// Second concept.
    public let conceptB: String
    /// Number of articles where both concepts co-occur.
    public let coOccurrences: Int
    /// Strength of the relationship (0-1).
    public let strength: Double
}

/// A cluster of related concepts forming a topic area.
public struct KGCluster: Sendable {
    /// Cluster label (most central concept).
    public let label: String
    /// All concepts in this cluster.
    public let concepts: [String]
    /// Average depth across concepts.
    public let averageDepth: Double
    /// Number of articles contributing to this cluster.
    public let articleCount: Int
    /// Cohesion score (0-1): how tightly connected the concepts are.
    public let cohesion: Double
}

/// A detected gap in knowledge.
public struct KGGap: Sendable {
    /// The concept or area that's under-explored.
    public let concept: String
    /// Why it's considered a gap.
    public let reason: String
    /// Adjacent known concepts that make this relevant.
    public let adjacentKnowledge: [String]
    /// Priority score (0-100): higher = more impactful to fill.
    public let priority: Double
    /// Type of gap.
    public let gapType: GapType
}

/// Types of knowledge gaps.
public enum GapType: String, Sendable {
    /// Concept mentioned few times but highly connected to strong areas.
    case shallow = "shallow"
    /// Bridge concept between two clusters that's under-explored.
    case bridge = "bridge"
    /// Concept that was known but hasn't been refreshed recently.
    case decayed = "decayed"
    /// Concept adjacent to multiple strong areas but never encountered.
    case blind = "blind"
    /// A cluster exists but lacks foundational concepts.
    case foundational = "foundational"
}

/// A suggested learning path to build expertise.
public struct KGLearningPath: Sendable {
    /// Name/goal of the learning path.
    public let name: String
    /// Ordered concepts to explore.
    public let steps: [String]
    /// Current progress (0-1): how many steps are already strong.
    public let progress: Double
    /// Estimated reading needed (article count).
    public let estimatedArticles: Int
    /// Target expertise level.
    public let targetLevel: ExpertiseLevel
}

/// Expertise levels.
public enum ExpertiseLevel: String, Sendable, Comparable {
    case novice = "novice"
    case familiar = "familiar"
    case competent = "competent"
    case proficient = "proficient"
    case expert = "expert"

    private var rank: Int {
        switch self {
        case .novice: return 0
        case .familiar: return 1
        case .competent: return 2
        case .proficient: return 3
        case .expert: return 4
        }
    }

    public static func < (lhs: ExpertiseLevel, rhs: ExpertiseLevel) -> Bool {
        lhs.rank < rhs.rank
    }
}

/// Expertise profile for a topic area.
public struct KGExpertiseProfile: Sendable {
    /// Topic/cluster name.
    public let topic: String
    /// Current expertise level.
    public let level: ExpertiseLevel
    /// Depth score (0-100).
    public let depth: Double
    /// Breadth: fraction of subtopics covered.
    public let breadth: Double
    /// Trend: improving, stable, or declining.
    public let trend: KGTrend
    /// Key concepts the user is strong in.
    public let strengths: [String]
    /// Concepts needing work.
    public let weaknesses: [String]
}

/// Knowledge trend direction.
public enum KGTrend: String, Sendable {
    case improving = "improving"
    case stable = "stable"
    case declining = "declining"
}

/// A concept needing refresh due to decay.
public struct KGDecayingConcept: Sendable {
    /// The concept.
    public let concept: String
    /// Days since last encountered.
    public let daysSinceLastSeen: Int
    /// Original depth before decay.
    public let peakDepth: Double
    /// Current effective depth after decay.
    public let currentDepth: Double
    /// Urgency of refresh (0-100).
    public let refreshUrgency: Double
}

/// Full knowledge graph analysis report.
public struct KGReport: Sendable {
    /// All concept nodes in the graph.
    public let nodes: [KGNode]
    /// All edges (co-occurrence relationships).
    public let edges: [KGEdge]
    /// Detected topic clusters.
    public let clusters: [KGCluster]
    /// Knowledge gaps with fill recommendations.
    public let gaps: [KGGap]
    /// Expertise profile per topic area.
    public let expertiseProfile: [KGExpertiseProfile]
    /// Suggested learning paths.
    public let learningPaths: [KGLearningPath]
    /// Concepts needing refresh.
    public let decayingConcepts: [KGDecayingConcept]
    /// Overall knowledge health score (0-100).
    public let healthScore: Double
    /// Total unique concepts tracked.
    public let totalConcepts: Int
    /// Total articles ingested.
    public let totalArticles: Int
    /// Autonomous insights generated.
    public let insights: [String]
}

// MARK: - Engine

/// Autonomous knowledge graph builder from reading history.
///
/// Ingests articles, extracts concept relationships, and provides
/// analysis including gap detection, expertise profiling, and
/// learning path suggestions.
public class FeedKnowledgeGraph {

    // MARK: - Configuration

    /// Half-life for knowledge decay in days.
    public var decayHalfLifeDays: Double = 30.0

    /// Minimum co-occurrences to form an edge.
    public var minEdgeCoOccurrences: Int = 2

    /// Minimum concepts to form a cluster.
    public var minClusterSize: Int = 3

    /// Maximum gap results to return.
    public var maxGaps: Int = 20

    /// Maximum learning paths to generate.
    public var maxPaths: Int = 5

    // MARK: - State

    private var articles: [KGArticle] = []
    private var conceptFrequency: [String: Int] = [:]
    private var conceptFirstSeen: [String: Date] = [:]
    private var conceptLastSeen: [String: Date] = [:]
    private var conceptSources: [String: Set<String>] = [:]
    private var conceptArticleIds: [String: Set<String>] = [:]
    private var coOccurrenceMatrix: [String: [String: Int]] = [:]

    // MARK: - Initialization

    public init() {}

    // MARK: - Ingestion

    /// Ingest an article into the knowledge graph.
    /// - Parameter article: The article to ingest.
    public func ingest(_ article: KGArticle) {
        articles.append(article)

        let concepts = Array(Set(article.concepts)) // dedupe within article

        for concept in concepts {
            conceptFrequency[concept, default: 0] += 1

            if conceptFirstSeen[concept] == nil || article.readDate < conceptFirstSeen[concept]! {
                conceptFirstSeen[concept] = article.readDate
            }
            if conceptLastSeen[concept] == nil || article.readDate > conceptLastSeen[concept]! {
                conceptLastSeen[concept] = article.readDate
            }

            conceptSources[concept, default: Set()].insert(article.feedSource)
            conceptArticleIds[concept, default: Set()].insert(article.id)
        }

        // Build co-occurrence edges
        for i in 0..<concepts.count {
            for j in (i+1)..<concepts.count {
                let a = concepts[i]
                let b = concepts[j]
                let key1 = min(a, b)
                let key2 = max(a, b)
                coOccurrenceMatrix[key1, default: [:]][key2, default: 0] += 1
            }
        }
    }

    /// Ingest multiple articles at once.
    /// - Parameter articles: Articles to ingest.
    public func ingestBatch(_ articles: [KGArticle]) {
        for article in articles {
            ingest(article)
        }
    }

    // MARK: - Analysis

    /// Perform full knowledge graph analysis.
    /// - Parameter referenceDate: Date to use as "now" for decay calculations. Defaults to current date.
    /// - Returns: Complete knowledge graph report.
    public func analyze(referenceDate: Date = Date()) -> KGReport {
        let nodes = buildNodes(referenceDate: referenceDate)
        let edges = buildEdges()
        let clusters = detectClusters(nodes: nodes, edges: edges)
        let gaps = detectGaps(nodes: nodes, edges: edges, clusters: clusters, referenceDate: referenceDate)
        let expertise = buildExpertiseProfiles(clusters: clusters, nodes: nodes, referenceDate: referenceDate)
        let paths = generateLearningPaths(gaps: gaps, clusters: clusters, nodes: nodes)
        let decaying = findDecayingConcepts(nodes: nodes, referenceDate: referenceDate)
        let insights = generateInsights(nodes: nodes, edges: edges, clusters: clusters, gaps: gaps, decaying: decaying)
        let health = computeHealthScore(nodes: nodes, gaps: gaps, decaying: decaying, clusters: clusters)

        return KGReport(
            nodes: nodes,
            edges: edges,
            clusters: clusters,
            gaps: gaps,
            expertiseProfile: expertise,
            learningPaths: paths,
            decayingConcepts: decaying,
            healthScore: health,
            totalConcepts: conceptFrequency.count,
            totalArticles: articles.count,
            insights: insights
        )
    }

    // MARK: - Node Building

    private func buildNodes(referenceDate: Date) -> [KGNode] {
        return conceptFrequency.map { concept, freq in
            let firstSeen = conceptFirstSeen[concept] ?? referenceDate
            let lastSeen = conceptLastSeen[concept] ?? referenceDate
            let sources = conceptSources[concept] ?? Set()

            let recencyDays = max(0, Calendar.current.dateComponents([.day],
                from: lastSeen, to: referenceDate).day ?? 0)
            let recencyFactor = exp(-0.693 * Double(recencyDays) / decayHalfLifeDays)
            let freqScore = min(1.0, Double(freq) / 10.0)
            let diversityScore = min(1.0, Double(sources.count) / 5.0)
            let depth = (freqScore * 0.4 + recencyFactor * 0.35 + diversityScore * 0.25) * 100.0

            return KGNode(
                concept: concept,
                frequency: freq,
                firstSeen: firstSeen,
                lastSeen: lastSeen,
                sources: sources,
                depthScore: min(100, max(0, depth))
            )
        }.sorted { $0.depthScore > $1.depthScore }
    }

    // MARK: - Edge Building

    private func buildEdges() -> [KGEdge] {
        var edges: [KGEdge] = []

        for (conceptA, neighbors) in coOccurrenceMatrix {
            for (conceptB, count) in neighbors where count >= minEdgeCoOccurrences {
                let maxFreq = max(
                    Double(conceptFrequency[conceptA] ?? 1),
                    Double(conceptFrequency[conceptB] ?? 1)
                )
                let strength = min(1.0, Double(count) / maxFreq)
                edges.append(KGEdge(
                    conceptA: conceptA,
                    conceptB: conceptB,
                    coOccurrences: count,
                    strength: strength
                ))
            }
        }

        return edges.sorted { $0.strength > $1.strength }
    }

    // MARK: - Cluster Detection

    private func detectClusters(nodes: [KGNode], edges: [KGEdge]) -> [KGCluster] {
        // Simple connected-component clustering via adjacency
        var adjacency: [String: Set<String>] = [:]
        for edge in edges {
            adjacency[edge.conceptA, default: Set()].insert(edge.conceptB)
            adjacency[edge.conceptB, default: Set()].insert(edge.conceptA)
        }

        var visited: Set<String> = []
        var clusters: [KGCluster] = []

        let nodeMap = Dictionary(uniqueKeysWithValues: nodes.map { ($0.concept, $0) })

        for node in nodes where !visited.contains(node.concept) {
            // BFS to find connected component
            var component: [String] = []
            var queue: [String] = [node.concept]
            visited.insert(node.concept)

            while !queue.isEmpty {
                let current = queue.removeFirst()
                component.append(current)
                for neighbor in adjacency[current] ?? Set() {
                    if !visited.contains(neighbor) {
                        visited.insert(neighbor)
                        queue.append(neighbor)
                    }
                }
            }

            guard component.count >= minClusterSize else { continue }

            let avgDepth = component.compactMap { nodeMap[$0]?.depthScore }
                .reduce(0, +) / max(1, Double(component.count))

            let articleIds = component.flatMap { conceptArticleIds[$0] ?? Set() }
            let articleCount = Set(articleIds).count

            // Cohesion: fraction of possible edges that exist
            let possibleEdges = component.count * (component.count - 1) / 2
            let actualEdges = edges.filter {
                component.contains($0.conceptA) && component.contains($0.conceptB)
            }.count
            let cohesion = possibleEdges > 0 ? Double(actualEdges) / Double(possibleEdges) : 0

            // Label is the concept with highest depth in cluster
            let label = component.max(by: {
                (nodeMap[$0]?.depthScore ?? 0) < (nodeMap[$1]?.depthScore ?? 0)
            }) ?? component[0]

            clusters.append(KGCluster(
                label: label,
                concepts: component.sorted(),
                averageDepth: avgDepth,
                articleCount: articleCount,
                cohesion: min(1.0, cohesion)
            ))
        }

        return clusters.sorted { $0.averageDepth > $1.averageDepth }
    }

    // MARK: - Gap Detection

    private func detectGaps(nodes: [KGNode], edges: [KGEdge], clusters: [KGCluster],
                           referenceDate: Date) -> [KGGap] {
        var gaps: [KGGap] = []
        let nodeMap = Dictionary(uniqueKeysWithValues: nodes.map { ($0.concept, $0) })

        // Find shallow concepts connected to strong concepts
        for node in nodes where node.depthScore < 30 {
            let neighbors = getNeighbors(of: node.concept)
            let strongNeighbors = neighbors.filter { (nodeMap[$0]?.depthScore ?? 0) > 60 }
            if strongNeighbors.count >= 2 {
                let priority = Double(strongNeighbors.count) * 15.0 + (30 - node.depthScore)
                gaps.append(KGGap(
                    concept: node.concept,
                    reason: "Mentioned \(node.frequency) times but weakly understood; connected to \(strongNeighbors.count) strong concepts",
                    adjacentKnowledge: Array(strongNeighbors.prefix(5)),
                    priority: min(100, priority),
                    gapType: .shallow
                ))
            }
        }

        // Find bridge concepts between clusters
        for edge in edges {
            let clusterA = clusters.first { $0.concepts.contains(edge.conceptA) }
            let clusterB = clusters.first { $0.concepts.contains(edge.conceptB) }
            if let cA = clusterA, let cB = clusterB, cA.label != cB.label {
                let nodeA = nodeMap[edge.conceptA]
                let nodeB = nodeMap[edge.conceptB]
                let weakerConcept = (nodeA?.depthScore ?? 0) < (nodeB?.depthScore ?? 0) ? edge.conceptA : edge.conceptB
                let weakerNode = nodeMap[weakerConcept]
                if (weakerNode?.depthScore ?? 0) < 40 {
                    gaps.append(KGGap(
                        concept: weakerConcept,
                        reason: "Bridges clusters '\(cA.label)' and '\(cB.label)' but under-explored",
                        adjacentKnowledge: [edge.conceptA, edge.conceptB].filter { $0 != weakerConcept },
                        priority: min(100, 70 + edge.strength * 30),
                        gapType: .bridge
                    ))
                }
            }
        }

        // Find decayed concepts
        for node in nodes {
            let daysSince = Calendar.current.dateComponents([.day],
                from: node.lastSeen, to: referenceDate).day ?? 0
            if daysSince > Int(decayHalfLifeDays) && node.frequency >= 3 {
                let decayFactor = exp(-0.693 * Double(daysSince) / decayHalfLifeDays)
                let effectiveDepth = node.depthScore * decayFactor
                if effectiveDepth < 30 && node.depthScore > 50 {
                    gaps.append(KGGap(
                        concept: node.concept,
                        reason: "Was well-known (depth \(Int(node.depthScore))) but not seen for \(daysSince) days",
                        adjacentKnowledge: Array(getNeighbors(of: node.concept).prefix(3)),
                        priority: min(100, node.depthScore * (1 - decayFactor)),
                        gapType: .decayed
                    ))
                }
            }
        }

        return gaps.sorted { $0.priority > $1.priority }
            .prefix(maxGaps).map { $0 }
    }

    // MARK: - Expertise Profiling

    private func buildExpertiseProfiles(clusters: [KGCluster], nodes: [KGNode],
                                        referenceDate: Date) -> [KGExpertiseProfile] {
        let nodeMap = Dictionary(uniqueKeysWithValues: nodes.map { ($0.concept, $0) })

        return clusters.prefix(10).map { cluster in
            let depths = cluster.concepts.compactMap { nodeMap[$0]?.depthScore }
            let avgDepth = depths.isEmpty ? 0 : depths.reduce(0, +) / Double(depths.count)
            let strongCount = depths.filter { $0 > 60 }.count
            let breadth = depths.isEmpty ? 0 : Double(strongCount) / Double(depths.count)

            let level: ExpertiseLevel
            switch avgDepth {
            case 0..<20: level = .novice
            case 20..<40: level = .familiar
            case 40..<60: level = .competent
            case 60..<80: level = .proficient
            default: level = .expert
            }

            // Determine trend from recency
            let recentConcepts = cluster.concepts.filter { concept in
                guard let lastSeen = conceptLastSeen[concept] else { return false }
                let days = Calendar.current.dateComponents([.day], from: lastSeen, to: referenceDate).day ?? 0
                return days < 14
            }
            let recentRatio = cluster.concepts.isEmpty ? 0 : Double(recentConcepts.count) / Double(cluster.concepts.count)
            let trend: KGTrend = recentRatio > 0.5 ? .improving : (recentRatio < 0.2 ? .declining : .stable)

            let strengths = cluster.concepts
                .filter { (nodeMap[$0]?.depthScore ?? 0) > 60 }
                .sorted { (nodeMap[$0]?.depthScore ?? 0) > (nodeMap[$1]?.depthScore ?? 0) }
                .prefix(5).map { $0 }

            let weaknesses = cluster.concepts
                .filter { (nodeMap[$0]?.depthScore ?? 0) < 30 }
                .sorted { (nodeMap[$0]?.depthScore ?? 0) < (nodeMap[$1]?.depthScore ?? 0) }
                .prefix(5).map { $0 }

            return KGExpertiseProfile(
                topic: cluster.label,
                level: level,
                depth: avgDepth,
                breadth: breadth,
                trend: trend,
                strengths: strengths,
                weaknesses: weaknesses
            )
        }
    }

    // MARK: - Learning Paths

    private func generateLearningPaths(gaps: [KGGap], clusters: [KGCluster],
                                        nodes: [KGNode]) -> [KGLearningPath] {
        var paths: [KGLearningPath] = []
        let nodeMap = Dictionary(uniqueKeysWithValues: nodes.map { ($0.concept, $0) })

        // Generate paths for top gap clusters
        let gapClusters = Dictionary(grouping: gaps) { gap -> String in
            // Find which cluster the gap belongs to
            clusters.first { $0.concepts.contains(gap.concept) }?.label ?? "general"
        }

        for (clusterLabel, clusterGaps) in gapClusters.prefix(maxPaths) {
            let steps = clusterGaps
                .sorted { $0.priority > $1.priority }
                .prefix(8)
                .map { $0.concept }

            // Reorder: foundational concepts first, then building up
            let ordered = steps.sorted { a, b in
                let freqA = conceptFrequency[a] ?? 0
                let freqB = conceptFrequency[b] ?? 0
                return freqA > freqB // More referenced = more foundational
            }

            let strongSteps = ordered.filter { (nodeMap[$0]?.depthScore ?? 0) > 50 }
            let progress = ordered.isEmpty ? 0 : Double(strongSteps.count) / Double(ordered.count)

            let targetLevel: ExpertiseLevel
            if progress < 0.3 { targetLevel = .competent }
            else if progress < 0.6 { targetLevel = .proficient }
            else { targetLevel = .expert }

            paths.append(KGLearningPath(
                name: "Master \(clusterLabel)",
                steps: ordered,
                progress: progress,
                estimatedArticles: max(1, ordered.count * 2),
                targetLevel: targetLevel
            ))
        }

        return paths.sorted { $0.progress < $1.progress } // Least progress first
    }

    // MARK: - Decay Detection

    private func findDecayingConcepts(nodes: [KGNode], referenceDate: Date) -> [KGDecayingConcept] {
        return nodes.compactMap { node in
            let daysSince = Calendar.current.dateComponents([.day],
                from: node.lastSeen, to: referenceDate).day ?? 0
            guard daysSince > 7 else { return nil }

            let decayFactor = exp(-0.693 * Double(daysSince) / decayHalfLifeDays)
            let currentDepth = node.depthScore * decayFactor
            let lostDepth = node.depthScore - currentDepth

            guard lostDepth > 15 else { return nil }

            let urgency = min(100, lostDepth * (Double(daysSince) / decayHalfLifeDays))

            return KGDecayingConcept(
                concept: node.concept,
                daysSinceLastSeen: daysSince,
                peakDepth: node.depthScore,
                currentDepth: currentDepth,
                refreshUrgency: urgency
            )
        }
        .sorted { $0.refreshUrgency > $1.refreshUrgency }
        .prefix(15).map { $0 }
    }

    // MARK: - Insights

    private func generateInsights(nodes: [KGNode], edges: [KGEdge],
                                  clusters: [KGCluster], gaps: [KGGap],
                                  decaying: [KGDecayingConcept]) -> [String] {
        var insights: [String] = []

        // Total knowledge breadth
        if nodes.count > 0 {
            let avgDepth = nodes.map { $0.depthScore }.reduce(0, +) / Double(nodes.count)
            insights.append("Knowledge breadth: \(nodes.count) concepts tracked across \(articles.count) articles (avg depth: \(Int(avgDepth)))")
        }

        // Strongest cluster
        if let strongest = clusters.first {
            insights.append("Strongest knowledge area: '\(strongest.label)' with \(strongest.concepts.count) concepts (cohesion: \(String(format: "%.0f%%", strongest.cohesion * 100)))")
        }

        // Knowledge concentration
        if clusters.count >= 2 {
            let topClusterSize = clusters[0].concepts.count
            let totalConcepts = nodes.count
            let concentration = totalConcepts > 0 ? Double(topClusterSize) / Double(totalConcepts) : 0
            if concentration > 0.5 {
                insights.append("⚠️ Knowledge is highly concentrated (\(Int(concentration * 100))%) in '\(clusters[0].label)' — consider diversifying")
            }
        }

        // Gap urgency
        let highPriorityGaps = gaps.filter { $0.priority > 70 }
        if highPriorityGaps.count > 0 {
            insights.append("🎯 \(highPriorityGaps.count) high-priority knowledge gap(s) detected — top: '\(highPriorityGaps[0].concept)'")
        }

        // Decay warning
        let urgentDecay = decaying.filter { $0.refreshUrgency > 60 }
        if urgentDecay.count > 0 {
            insights.append("⏳ \(urgentDecay.count) concept(s) urgently need refresh — top: '\(urgentDecay[0].concept)' (was depth \(Int(urgentDecay[0].peakDepth)), now \(Int(urgentDecay[0].currentDepth)))")
        }

        // Source diversity
        let allSources = Set(articles.map { $0.feedSource })
        if allSources.count <= 2 && articles.count > 10 {
            insights.append("📡 Knowledge sourced from only \(allSources.count) feed(s) — broader sources would strengthen graph diversity")
        }

        // Bridge opportunities
        let bridges = gaps.filter { $0.gapType == .bridge }
        if bridges.count > 0 {
            insights.append("🌉 \(bridges.count) bridge concept(s) could connect your knowledge areas — explore '\(bridges[0].concept)' to link topics")
        }

        return insights
    }

    // MARK: - Health Score

    private func computeHealthScore(nodes: [KGNode], gaps: [KGGap],
                                    decaying: [KGDecayingConcept], clusters: [KGCluster]) -> Double {
        guard !nodes.isEmpty else { return 0 }

        // Components:
        // 1. Average depth (40% weight)
        let avgDepth = nodes.map { $0.depthScore }.reduce(0, +) / Double(nodes.count)
        let depthComponent = avgDepth / 100.0

        // 2. Gap penalty (25% weight) — fewer gaps = healthier
        let gapPenalty = min(1.0, Double(gaps.count) / 20.0)
        let gapComponent = 1.0 - gapPenalty

        // 3. Decay penalty (20% weight)
        let decayPenalty = min(1.0, Double(decaying.count) / 15.0)
        let decayComponent = 1.0 - decayPenalty

        // 4. Cluster cohesion (15% weight)
        let avgCohesion = clusters.isEmpty ? 0.5 :
            clusters.map { $0.cohesion }.reduce(0, +) / Double(clusters.count)

        let score = (depthComponent * 0.4 + gapComponent * 0.25 +
                    decayComponent * 0.2 + avgCohesion * 0.15) * 100.0

        return min(100, max(0, score))
    }

    // MARK: - Helpers

    private func getNeighbors(of concept: String) -> [String] {
        var neighbors: [String] = []
        for (conceptA, conceptBMap) in coOccurrenceMatrix {
            if conceptA == concept {
                neighbors.append(contentsOf: conceptBMap.keys)
            } else if conceptBMap[concept] != nil {
                neighbors.append(conceptA)
            }
        }
        return neighbors
    }

    /// Reset the knowledge graph.
    public func reset() {
        articles = []
        conceptFrequency = [:]
        conceptFirstSeen = [:]
        conceptLastSeen = [:]
        conceptSources = [:]
        conceptArticleIds = [:]
        coOccurrenceMatrix = [:]
    }

    /// Get current article count.
    public var articleCount: Int { articles.count }

    /// Get current concept count.
    public var conceptCount: Int { conceptFrequency.count }
}
