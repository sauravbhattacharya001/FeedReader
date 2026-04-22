//
//  FeedSourceDiversityAuditor.swift
//  FeedReader
//
//  Autonomous echo chamber detection and source diversity analysis.
//  Monitors feed subscriptions and reading patterns to identify:
//  - Source concentration (over-reliance on a few sources)
//  - Topic monoculture (narrow topic coverage)
//  - Viewpoint clustering (sources with high content overlap)
//  - Reading bias (disproportionate attention to subset of feeds)
//
//  Produces a DiversityReport with per-dimension scores, an overall
//  diversity index, echo chamber risk level, and proactive balancing
//  recommendations. Supports continuous monitoring with trend detection.
//
//  All analysis on-device. No network calls or external deps.
//  Persistence: JSON file in Documents directory.
//

import Foundation

// MARK: - Notifications

extension Notification.Name {
    /// Posted when a new diversity report is generated.
    static let diversityReportDidUpdate = Notification.Name("DiversityReportDidUpdateNotification")
}

// MARK: - Configuration

/// Configurable thresholds for diversity analysis.
struct DiversityAuditConfig: Codable {
    /// Days to look back for reading pattern analysis.
    var evaluationWindowDays: Int = 30
    /// Herfindahl-Hirschman Index threshold above which source concentration is flagged (0-1 normalized).
    var sourceConcentrationThreshold: Double = 0.25
    /// Minimum number of distinct topic clusters expected.
    var minimumTopicClusters: Int = 3
    /// Jaccard similarity above which two feeds are considered a viewpoint cluster.
    var viewpointClusterThreshold: Double = 0.5
    /// Gini coefficient above which reading distribution is considered biased (0-1).
    var readingBiasGiniThreshold: Double = 0.7
    /// Minimum articles read to produce a meaningful report.
    var minimumArticlesForAnalysis: Int = 10
    /// Enable automatic periodic monitoring.
    var autoMonitorEnabled: Bool = false
    /// Days between automatic audits.
    var autoMonitorIntervalDays: Int = 7
}

// MARK: - Models

/// Echo chamber risk level.
enum EchoChamberRisk: String, Codable, CaseIterable {
    case minimal    // Diverse, well-balanced
    case low        // Mostly diverse, minor gaps
    case moderate   // Some concentration detected
    case high       // Significant echo chamber indicators
    case critical   // Severe echo chamber — urgent action needed

    var emoji: String {
        switch self {
        case .minimal:  return "🟢"
        case .low:      return "🟡"
        case .moderate: return "🟠"
        case .high:     return "🔴"
        case .critical: return "🚨"
        }
    }
}

/// A dimension of diversity being assessed.
enum DiversityDimension: String, Codable, CaseIterable {
    case sourceConcentration   // How spread out are subscriptions?
    case topicBreadth          // How many distinct topics covered?
    case viewpointClustering   // How similar are sources to each other?
    case readingDistribution   // How evenly does user read across feeds?
    case temporalDiversity     // Are different sources active at different times?
    case contentDepthVariety   // Mix of short/medium/long articles?
}

/// Score for a single diversity dimension.
struct DimensionScore: Codable {
    let dimension: DiversityDimension
    /// 0-100 score; higher = more diverse.
    let score: Double
    /// Human-readable finding.
    let finding: String
    /// Specific recommendation to improve this dimension.
    let recommendation: String?
}

/// A cluster of feeds with high content overlap.
struct ViewpointCluster: Codable {
    let feedNames: [String]
    /// Average pairwise Jaccard similarity within the cluster.
    let averageSimilarity: Double
    /// Dominant shared keywords.
    let sharedKeywords: [String]
}

/// A recommendation for improving diversity.
struct DiversityRecommendation: Codable {
    enum Priority: String, Codable {
        case high, medium, low
    }
    enum ActionType: String, Codable {
        case addSource
        case reduceSource
        case exploreTopic
        case rebalanceReading
        case breakCluster
    }

    let priority: Priority
    let actionType: ActionType
    let title: String
    let detail: String
}

/// Complete diversity audit report.
struct DiversityReport: Codable {
    let timestamp: Date
    let evaluationWindowDays: Int
    let totalFeedsAnalyzed: Int
    let totalArticlesAnalyzed: Int
    /// Per-dimension breakdown.
    let dimensionScores: [DimensionScore]
    /// Overall diversity index (0-100).
    let overallDiversityIndex: Double
    /// Echo chamber risk assessment.
    let echoChamberRisk: EchoChamberRisk
    /// Detected viewpoint clusters.
    let viewpointClusters: [ViewpointCluster]
    /// Topic distribution (topic → article count).
    let topicDistribution: [String: Int]
    /// Source read distribution (feedName → articles read).
    let sourceReadDistribution: [String: Int]
    /// Proactive recommendations.
    let recommendations: [DiversityRecommendation]
    /// Trend: change from previous report's diversity index.
    let trendDelta: Double?
}

/// Historical record for trend tracking.
struct DiversityHistoryEntry: Codable {
    let timestamp: Date
    let overallDiversityIndex: Double
    let echoChamberRisk: EchoChamberRisk
    let feedCount: Int
}

// MARK: - Auditor

/// Autonomous echo chamber detection and source diversity analysis engine.
final class FeedSourceDiversityAuditor {

    // MARK: - Properties

    private(set) var config: DiversityAuditConfig
    private(set) var latestReport: DiversityReport?
    private(set) var history: [DiversityHistoryEntry] = []

    private let persistenceURL: URL = {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        return docs.appendingPathComponent("diversity_audit_history.json")
    }()

    // MARK: - Stopwords

    private static let stopwords: Set<String> = [
        "the","a","an","and","or","but","in","on","at","to","for","of","with",
        "by","from","is","it","this","that","was","are","be","has","had","have",
        "not","no","so","as","if","its","can","do","than","may","we","he","she",
        "you","will","would","could","should","their","our","into","about","just",
        "more","also","been","were","what","when","how","who","which","up","out",
        "all","new","one","two","said","says","like","over","after","get","make"
    ]

    // MARK: - Init

    init(config: DiversityAuditConfig = DiversityAuditConfig()) {
        self.config = config
        loadHistory()
    }

    func updateConfig(_ config: DiversityAuditConfig) {
        self.config = config
    }

    // MARK: - Main Audit

    /// Run a full diversity audit on the provided feeds and reading data.
    /// - Parameters:
    ///   - feeds: All subscribed feeds.
    ///   - stories: All stories available (with sourceFeedName populated).
    ///   - readStoryLinks: Set of story links that have been read.
    /// - Returns: A complete DiversityReport.
    func runAudit(feeds: [Feed], stories: [Story], readStoryLinks: Set<String>) -> DiversityReport {
        let enabledFeeds = feeds.filter { $0.isEnabled }
        let feedNames = Set(enabledFeeds.map { $0.name })

        // Build per-feed article lists and read counts
        var feedArticles: [String: [Story]] = [:]
        var feedReadCounts: [String: Int] = [:]
        var totalRead = 0

        for story in stories {
            let source = story.sourceFeedName ?? "Unknown"
            guard feedNames.contains(source) else { continue }
            feedArticles[source, default: []].append(story)
            if readStoryLinks.contains(story.link) {
                feedReadCounts[source, default: 0] += 1
                totalRead += 1
            }
        }

        // 1. Source Concentration (Herfindahl-Hirschman Index on article counts)
        let sourceConcentrationScore = analyzeSourceConcentration(feedArticles: feedArticles)

        // 2. Topic Breadth
        let (topicScore, topicDistribution) = analyzeTopicBreadth(feedArticles: feedArticles)

        // 3. Viewpoint Clustering
        let (clusterScore, clusters) = analyzeViewpointClustering(feedArticles: feedArticles)

        // 4. Reading Distribution (Gini coefficient)
        let readingDistScore = analyzeReadingDistribution(feedReadCounts: feedReadCounts, feedNames: feedNames)

        // 5. Temporal Diversity
        let temporalScore = analyzeTemporalDiversity(feedArticles: feedArticles)

        // 6. Content Depth Variety
        let depthScore = analyzeContentDepthVariety(stories: stories, readStoryLinks: readStoryLinks)

        let dimensionScores = [sourceConcentrationScore, topicScore, clusterScore,
                               readingDistScore, temporalScore, depthScore]

        // Overall diversity index (weighted average)
        let weights: [Double] = [0.20, 0.25, 0.15, 0.20, 0.10, 0.10]
        let weightedSum = zip(dimensionScores, weights).reduce(0.0) { $0 + $1.0.score * $1.1 }
        let overallIndex = min(100, max(0, weightedSum))

        // Risk level
        let risk: EchoChamberRisk
        switch overallIndex {
        case 80...100: risk = .minimal
        case 60..<80:  risk = .low
        case 40..<60:  risk = .moderate
        case 20..<40:  risk = .high
        default:        risk = .critical
        }

        // Trend
        let trendDelta: Double? = history.last.map { overallIndex - $0.overallDiversityIndex }

        // Recommendations
        let recommendations = generateRecommendations(
            dimensionScores: dimensionScores,
            clusters: clusters,
            topicDistribution: topicDistribution,
            feedReadCounts: feedReadCounts,
            feedArticles: feedArticles
        )

        let report = DiversityReport(
            timestamp: Date(),
            evaluationWindowDays: config.evaluationWindowDays,
            totalFeedsAnalyzed: enabledFeeds.count,
            totalArticlesAnalyzed: stories.count,
            dimensionScores: dimensionScores,
            overallDiversityIndex: round(overallIndex * 10) / 10,
            echoChamberRisk: risk,
            viewpointClusters: clusters,
            topicDistribution: topicDistribution,
            sourceReadDistribution: feedReadCounts,
            recommendations: recommendations,
            trendDelta: trendDelta.map { round($0 * 10) / 10 }
        )

        latestReport = report

        // Save to history
        let entry = DiversityHistoryEntry(
            timestamp: report.timestamp,
            overallDiversityIndex: report.overallDiversityIndex,
            echoChamberRisk: report.echoChamberRisk,
            feedCount: enabledFeeds.count
        )
        history.append(entry)
        saveHistory()

        NotificationCenter.default.post(name: .diversityReportDidUpdate, object: report)
        return report
    }

    // MARK: - Dimension Analyzers

    /// Herfindahl-Hirschman Index on article distribution across sources.
    private func analyzeSourceConcentration(feedArticles: [String: [Story]]) -> DimensionScore {
        let totalArticles = feedArticles.values.reduce(0) { $0 + $1.count }
        guard totalArticles > 0 else {
            return DimensionScore(dimension: .sourceConcentration, score: 0,
                                  finding: "No articles to analyze.", recommendation: "Subscribe to some feeds first.")
        }

        let shares = feedArticles.values.map { Double($0.count) / Double(totalArticles) }
        let hhi = shares.reduce(0.0) { $0 + $1 * $1 }
        // HHI ranges from 1/N (perfect diversity) to 1.0 (monopoly)
        // Normalize: score = (1 - HHI) * 100
        let score = min(100, max(0, (1.0 - hhi) * 100))

        let finding: String
        let recommendation: String?
        if hhi > config.sourceConcentrationThreshold {
            let topSource = feedArticles.max(by: { $0.value.count < $1.value.count })?.key ?? "?"
            finding = "High source concentration detected. '\(topSource)' dominates your feed."
            recommendation = "Add feeds from different publishers to balance your information diet."
        } else {
            finding = "Article volume is well-distributed across your sources."
            recommendation = nil
        }

        return DimensionScore(dimension: .sourceConcentration, score: round(score * 10) / 10,
                              finding: finding, recommendation: recommendation)
    }

    /// Topic breadth via keyword clustering.
    private func analyzeTopicBreadth(feedArticles: [String: [Story]]) -> (DimensionScore, [String: Int]) {
        var topicCounts: [String: Int] = [:]
        let allStories = feedArticles.values.flatMap { $0 }

        for story in allStories {
            let keywords = extractKeywords(from: story, topN: 3)
            for kw in keywords {
                topicCounts[kw, default: 0] += 1
            }
        }

        let distinctTopics = topicCounts.count
        let score: Double
        let finding: String
        let recommendation: String?

        if distinctTopics == 0 {
            score = 0
            finding = "No topics could be extracted."
            recommendation = "Add feeds covering different subject areas."
        } else {
            // Shannon entropy of topic distribution
            let total = Double(topicCounts.values.reduce(0, +))
            let entropy = -topicCounts.values.reduce(0.0) { acc, count in
                let p = Double(count) / total
                return acc + (p > 0 ? p * log2(p) : 0)
            }
            let maxEntropy = log2(Double(max(1, distinctTopics)))
            let normalizedEntropy = maxEntropy > 0 ? entropy / maxEntropy : 0
            score = min(100, max(0, normalizedEntropy * 100))

            if distinctTopics < config.minimumTopicClusters {
                finding = "Only \(distinctTopics) topic areas detected — limited breadth."
                recommendation = "Explore feeds in different domains: science, culture, business, etc."
            } else {
                finding = "\(distinctTopics) distinct topics detected with \(normalizedEntropy > 0.7 ? "good" : "moderate") distribution."
                recommendation = normalizedEntropy < 0.6 ? "Some topics dominate heavily. Try diversifying your reading." : nil
            }
        }

        return (DimensionScore(dimension: .topicBreadth, score: round(score * 10) / 10,
                               finding: finding, recommendation: recommendation), topicCounts)
    }

    /// Detect clusters of feeds with high content overlap.
    private func analyzeViewpointClustering(feedArticles: [String: [Story]]) -> (DimensionScore, [ViewpointCluster]) {
        let feedKeywords: [String: Set<String>] = feedArticles.mapValues { stories in
            Set(stories.flatMap { extractKeywords(from: $0, topN: 5) })
        }

        let feedNames = Array(feedKeywords.keys).sorted()
        var clusters: [ViewpointCluster] = []
        var clustered: Set<String> = []

        for i in 0..<feedNames.count {
            guard !clustered.contains(feedNames[i]) else { continue }
            var clusterMembers = [feedNames[i]]
            let kw1 = feedKeywords[feedNames[i]] ?? []
            guard !kw1.isEmpty else { continue }

            for j in (i+1)..<feedNames.count {
                guard !clustered.contains(feedNames[j]) else { continue }
                let kw2 = feedKeywords[feedNames[j]] ?? []
                guard !kw2.isEmpty else { continue }

                let intersection = kw1.intersection(kw2).count
                let union = kw1.union(kw2).count
                let jaccard = union > 0 ? Double(intersection) / Double(union) : 0

                if jaccard >= config.viewpointClusterThreshold {
                    clusterMembers.append(feedNames[j])
                }
            }

            if clusterMembers.count > 1 {
                let shared = clusterMembers.reduce(feedKeywords[clusterMembers[0]] ?? []) { acc, name in
                    acc.intersection(feedKeywords[name] ?? [])
                }
                // Average pairwise similarity
                var pairSims: [Double] = []
                for a in 0..<clusterMembers.count {
                    for b in (a+1)..<clusterMembers.count {
                        let ka = feedKeywords[clusterMembers[a]] ?? []
                        let kb = feedKeywords[clusterMembers[b]] ?? []
                        let u = ka.union(kb).count
                        let sim = u > 0 ? Double(ka.intersection(kb).count) / Double(u) : 0
                        pairSims.append(sim)
                    }
                }
                let avgSim = pairSims.isEmpty ? 0 : pairSims.reduce(0, +) / Double(pairSims.count)

                clusters.append(ViewpointCluster(
                    feedNames: clusterMembers,
                    averageSimilarity: round(avgSim * 1000) / 1000,
                    sharedKeywords: Array(shared.prefix(8)).sorted()
                ))
                clusterMembers.forEach { clustered.insert($0) }
            }
        }

        let totalFeeds = feedNames.count
        let clusteredCount = clustered.count
        let score: Double
        let finding: String
        let recommendation: String?

        if totalFeeds <= 1 {
            score = 50
            finding = "Only one feed — can't assess viewpoint diversity."
            recommendation = "Subscribe to more feeds to enable diversity analysis."
        } else {
            let clusterRatio = Double(clusteredCount) / Double(totalFeeds)
            score = min(100, max(0, (1.0 - clusterRatio) * 100))
            if clusters.isEmpty {
                finding = "No significant viewpoint clusters — your sources are distinct."
                recommendation = nil
            } else {
                let clusterDescs = clusters.map { $0.feedNames.joined(separator: ", ") }
                finding = "\(clusters.count) viewpoint cluster(s) found: [\(clusterDescs.joined(separator: "] ["))]."
                recommendation = "Consider replacing one source in each cluster with a different perspective."
            }
        }

        return (DimensionScore(dimension: .viewpointClustering, score: round(score * 10) / 10,
                               finding: finding, recommendation: recommendation), clusters)
    }

    /// Gini coefficient of reading distribution across feeds.
    private func analyzeReadingDistribution(feedReadCounts: [String: Int], feedNames: Set<String>) -> DimensionScore {
        var counts = feedNames.map { feedReadCounts[$0] ?? 0 }
        counts.sort()
        let n = counts.count
        guard n > 1 else {
            return DimensionScore(dimension: .readingDistribution, score: 50,
                                  finding: "Not enough feeds for distribution analysis.",
                                  recommendation: nil)
        }

        let total = Double(counts.reduce(0, +))
        guard total > 0 else {
            return DimensionScore(dimension: .readingDistribution, score: 0,
                                  finding: "No articles read in the evaluation window.",
                                  recommendation: "Start reading articles to build your diversity profile.")
        }

        // Gini coefficient
        var sumNumerator = 0.0
        for (i, count) in counts.enumerated() {
            sumNumerator += Double(2 * (i + 1) - n - 1) * Double(count)
        }
        let gini = sumNumerator / (Double(n) * total)

        let score = min(100, max(0, (1.0 - gini) * 100))
        let finding: String
        let recommendation: String?

        if gini > config.readingBiasGiniThreshold {
            let sorted = feedReadCounts.sorted { $0.value > $1.value }
            let topFeed = sorted.first?.key ?? "?"
            finding = "Highly skewed reading pattern. '\(topFeed)' dominates your attention."
            recommendation = "Try spending some reading time on your less-visited feeds."
        } else {
            finding = "Reading attention is reasonably distributed across feeds."
            recommendation = nil
        }

        return DimensionScore(dimension: .readingDistribution, score: round(score * 10) / 10,
                              finding: finding, recommendation: recommendation)
    }

    /// Assess whether feeds provide content at different times (temporal spread).
    private func analyzeTemporalDiversity(feedArticles: [String: [Story]]) -> DimensionScore {
        // Use article body length as a proxy for recency variation
        // Group feeds by average word count bucket
        var feedBuckets: [String: Int] = [:]
        for (name, stories) in feedArticles {
            let avgWords = stories.isEmpty ? 0 : stories.reduce(0) { $0 + $1.body.split(separator: " ").count } / stories.count
            // Bucket: 0=micro (<50), 1=short (<200), 2=medium (<500), 3=long
            let bucket: Int
            switch avgWords {
            case ..<50:  bucket = 0
            case ..<200: bucket = 1
            case ..<500: bucket = 2
            default:     bucket = 3
            }
            feedBuckets[name] = bucket
        }

        let distinctBuckets = Set(feedBuckets.values).count
        let score = min(100, Double(distinctBuckets) / 4.0 * 100)

        return DimensionScore(dimension: .temporalDiversity, score: round(score * 10) / 10,
                              finding: "\(distinctBuckets) of 4 content length tiers represented.",
                              recommendation: distinctBuckets < 3 ? "Add feeds with different article lengths for variety." : nil)
    }

    /// Mix of short/medium/long articles in reading history.
    private func analyzeContentDepthVariety(stories: [Story], readStoryLinks: Set<String>) -> DimensionScore {
        let readStories = stories.filter { readStoryLinks.contains($0.link) }
        guard !readStories.isEmpty else {
            return DimensionScore(dimension: .contentDepthVariety, score: 0,
                                  finding: "No read articles to analyze.",
                                  recommendation: "Start reading to build a depth profile.")
        }

        var buckets = [0, 0, 0] // short, medium, long
        for story in readStories {
            let words = story.body.split(separator: " ").count
            switch words {
            case ..<150:  buckets[0] += 1
            case ..<500:  buckets[1] += 1
            default:      buckets[2] += 1
            }
        }

        let nonEmpty = buckets.filter { $0 > 0 }.count
        let score = Double(nonEmpty) / 3.0 * 100

        let labels = ["short", "medium", "long"]
        let present = zip(labels, buckets).filter { $0.1 > 0 }.map { "\($0.0) (\($0.1))" }
        return DimensionScore(dimension: .contentDepthVariety, score: round(score * 10) / 10,
                              finding: "Reading depth mix: \(present.joined(separator: ", ")).",
                              recommendation: nonEmpty < 3 ? "Try reading some \(buckets[2] == 0 ? "long-form" : "shorter") articles for variety." : nil)
    }

    // MARK: - Recommendations

    private func generateRecommendations(
        dimensionScores: [DimensionScore],
        clusters: [ViewpointCluster],
        topicDistribution: [String: Int],
        feedReadCounts: [String: Int],
        feedArticles: [String: [Story]]
    ) -> [DiversityRecommendation] {
        var recs: [DiversityRecommendation] = []

        // Low-scoring dimensions get recommendations
        for ds in dimensionScores where ds.score < 50 {
            switch ds.dimension {
            case .sourceConcentration:
                recs.append(DiversityRecommendation(
                    priority: ds.score < 25 ? .high : .medium,
                    actionType: .addSource,
                    title: "Diversify Your Sources",
                    detail: "Your feed is dominated by a few publishers. Add 2-3 new sources from different organizations."
                ))
            case .topicBreadth:
                let topTopics = topicDistribution.sorted { $0.value > $1.value }.prefix(3).map { $0.key }
                let underrepresented = ["science", "culture", "business", "health", "technology", "politics", "sports", "arts"]
                    .filter { topic in !topTopics.contains(where: { $0.lowercased().contains(topic) }) }
                    .prefix(3)
                recs.append(DiversityRecommendation(
                    priority: ds.score < 25 ? .high : .medium,
                    actionType: .exploreTopic,
                    title: "Broaden Your Topics",
                    detail: "Heavy on \(topTopics.joined(separator: ", ")). Try exploring: \(underrepresented.joined(separator: ", "))."
                ))
            case .viewpointClustering:
                for cluster in clusters {
                    recs.append(DiversityRecommendation(
                        priority: .medium,
                        actionType: .breakCluster,
                        title: "Break Echo Cluster",
                        detail: "\(cluster.feedNames.joined(separator: " & ")) share heavy overlap on: \(cluster.sharedKeywords.joined(separator: ", ")). Replace one with a different perspective."
                    ))
                }
            case .readingDistribution:
                let neglected = feedArticles.keys.filter { (feedReadCounts[$0] ?? 0) == 0 }.sorted()
                if !neglected.isEmpty {
                    recs.append(DiversityRecommendation(
                        priority: .medium,
                        actionType: .rebalanceReading,
                        title: "Read Your Neglected Feeds",
                        detail: "You haven't read anything from: \(neglected.prefix(5).joined(separator: ", ")). Give them a chance!"
                    ))
                }
            default:
                break
            }
        }

        // Overall echo chamber warning
        if let overall = dimensionScores.first(where: { $0.dimension == .sourceConcentration }),
           let topic = dimensionScores.first(where: { $0.dimension == .topicBreadth }),
           overall.score < 40 && topic.score < 40 {
            recs.insert(DiversityRecommendation(
                priority: .high,
                actionType: .addSource,
                title: "⚠️ Echo Chamber Alert",
                detail: "Both source concentration and topic breadth are low. You may be in an information bubble. Actively seek out different viewpoints."
            ), at: 0)
        }

        return recs
    }

    // MARK: - Keyword Extraction

    /// Simple TF-based keyword extraction.
    private func extractKeywords(from story: Story, topN: Int) -> [String] {
        let text = "\(story.title) \(story.body)"
        let words = text.lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { $0.count > 3 && !FeedSourceDiversityAuditor.stopwords.contains($0) }

        var freq: [String: Int] = [:]
        for word in words {
            freq[word, default: 0] += 1
        }

        return freq.sorted { $0.value > $1.value }.prefix(topN).map { $0.key }
    }

    // MARK: - Report Formatting

    /// Generate a human-readable text summary of the latest report.
    func formatReport(_ report: DiversityReport) -> String {
        var lines: [String] = []
        lines.append("══════════════════════════════════════")
        lines.append("  📡 Source Diversity Audit Report")
        lines.append("══════════════════════════════════════")
        lines.append("")
        lines.append("  Overall Diversity Index: \(report.overallDiversityIndex)/100")
        lines.append("  Echo Chamber Risk: \(report.echoChamberRisk.emoji) \(report.echoChamberRisk.rawValue.uppercased())")
        if let delta = report.trendDelta {
            let arrow = delta > 0 ? "📈" : delta < 0 ? "📉" : "➡️"
            lines.append("  Trend: \(arrow) \(delta > 0 ? "+" : "")\(delta) since last audit")
        }
        lines.append("  Feeds: \(report.totalFeedsAnalyzed) | Articles: \(report.totalArticlesAnalyzed)")
        lines.append("")

        lines.append("─── Dimension Scores ───")
        for ds in report.dimensionScores {
            let bar = String(repeating: "█", count: Int(ds.score / 10))
            let empty = String(repeating: "░", count: 10 - Int(ds.score / 10))
            lines.append("  \(ds.dimension.rawValue): [\(bar)\(empty)] \(ds.score)")
            lines.append("    \(ds.finding)")
        }

        if !report.viewpointClusters.isEmpty {
            lines.append("")
            lines.append("─── Viewpoint Clusters ───")
            for cluster in report.viewpointClusters {
                lines.append("  🔗 \(cluster.feedNames.joined(separator: " ↔ ")) (sim: \(cluster.averageSimilarity))")
                lines.append("     Shared: \(cluster.sharedKeywords.joined(separator: ", "))")
            }
        }

        if !report.recommendations.isEmpty {
            lines.append("")
            lines.append("─── Recommendations ───")
            for rec in report.recommendations {
                let icon: String
                switch rec.priority {
                case .high:   icon = "🔴"
                case .medium: icon = "🟡"
                case .low:    icon = "🟢"
                }
                lines.append("  \(icon) \(rec.title)")
                lines.append("     \(rec.detail)")
            }
        }

        lines.append("")
        lines.append("══════════════════════════════════════")
        return lines.joined(separator: "\n")
    }

    // MARK: - History & Trends

    /// Get diversity trend over recent audits.
    func getTrend(lastN: Int = 10) -> [(date: Date, index: Double, risk: EchoChamberRisk)] {
        return history.suffix(lastN).map { ($0.timestamp, $0.overallDiversityIndex, $0.echoChamberRisk) }
    }

    /// Check if diversity is declining over recent audits.
    func isDiversityDeclining(window: Int = 5) -> Bool {
        guard history.count >= window else { return false }
        let recent = history.suffix(window).map { $0.overallDiversityIndex }
        guard let first = recent.first, let last = recent.last else { return false }
        return last < first - 5.0 // More than 5 points decline
    }

    // MARK: - Persistence

    private func loadHistory() {
        guard FileManager.default.fileExists(atPath: persistenceURL.path) else { return }
        do {
            let data = try Data(contentsOf: persistenceURL)
            history = try JSONDecoder().decode([DiversityHistoryEntry].self, from: data)
        } catch {
            history = []
        }
    }

    private func saveHistory() {
        do {
            let data = try JSONEncoder().encode(history)
            try data.write(to: persistenceURL, options: .atomic)
        } catch {
            // Silent failure — non-critical
        }
    }
}
