//
//  FeedSerendipityEngine.swift
//  FeedReaderCore
//
//  Autonomous serendipitous article discovery engine.
//  Finds unexpected connections between articles from different feeds
//  using keyword co-occurrence and topic bridging to suggest surprising
//  cross-topic reads users wouldn't normally find.
//

import Foundation

// MARK: - Models

/// A discovered serendipitous connection between two articles.
public struct SerendipityConnection: Sendable {
    /// First article in the connection.
    public let articleA: SerendipityArticle
    /// Second article in the connection.
    public let articleB: SerendipityArticle
    /// Shared keywords that bridge the two articles.
    public let bridgeKeywords: [String]
    /// Serendipity score (0-1): higher means more surprising/unexpected.
    public let serendipityScore: Double
    /// Human-readable explanation of the connection.
    public let explanation: String
    /// The type of serendipitous link.
    public let connectionType: ConnectionType
}

/// Types of serendipitous connections.
public enum ConnectionType: String, Sendable {
    case crossDomain = "Cross-Domain Bridge"
    case hiddenThread = "Hidden Thread"
    case contrastingView = "Contrasting Viewpoint"
    case unexpectedParallel = "Unexpected Parallel"
    case emergingNexus = "Emerging Nexus"
}

/// Lightweight article representation for serendipity analysis.
public struct SerendipityArticle: Sendable {
    public let title: String
    public let body: String
    public let link: String
    public let feedName: String
    public let keywords: [String]
    public let domain: String

    public init(title: String, body: String, link: String, feedName: String) {
        self.title = title
        self.body = body
        self.link = link
        self.feedName = feedName
        self.keywords = SerendipityArticle.extractKeywords(from: title + " " + body)
        self.domain = SerendipityArticle.inferDomain(from: feedName, title: title)
    }

    /// Stop words excluded from serendipity keyword extraction.
    ///
    /// Declared as a static constant so it is constructed exactly once for
    /// the lifetime of the process. Previously this was a function-local
    /// `Set<String>` literal, which the Swift runtime rebuilds on every call
    /// - meaning every `SerendipityArticle(...)` allocated a fresh 48-element
    /// hash set just to throw it away. Hoisting it out is free and matters
    /// at the volumes the discovery engine runs at (hundreds of articles).
    private static let extractionStopWords: Set<String> = [
        "that", "this", "with", "from", "have", "been", "were", "they",
        "their", "about", "would", "could", "should", "which", "there",
        "when", "what", "more", "some", "than", "them", "will", "into",
        "just", "also", "said", "says", "like", "been", "other", "over",
        "after", "most", "such", "only", "very", "year", "even", "back",
        "make", "made", "still", "each", "much", "many", "well", "does"
    ]

    private static func extractKeywords(from text: String) -> [String] {
        // Fuse the length filter and stop-word filter into the frequency
        // counting pass. The previous implementation materialized a fully
        // filtered `[String]` (one allocation per surviving token) and then
        // iterated it again to count. The new version walks the token list
        // exactly once and only allocates frequency-table entries.
        let tokens = text.lowercased().components(separatedBy: CharacterSet.alphanumerics.inverted)
        let stopWords = extractionStopWords
        var freq: [String: Int] = [:]
        freq.reserveCapacity(min(tokens.count, 256))
        for w in tokens {
            if w.count <= 3 { continue }
            if stopWords.contains(w) { continue }
            freq[w, default: 0] += 1
        }

        return freq.sorted { $0.value > $1.value }
            .prefix(20)
            .map { $0.key }
    }

    private static func inferDomain(from feedName: String, title: String) -> String {
        let combined = (feedName + " " + title).lowercased()
        let domains: [(String, [String])] = [
            ("technology", ["tech", "software", "ai", "computer", "digital", "cyber", "app", "data"]),
            ("science", ["science", "research", "study", "discovery", "space", "quantum", "climate"]),
            ("business", ["business", "market", "economy", "stock", "finance", "company", "startup"]),
            ("politics", ["politic", "government", "election", "congress", "senate", "diplomat"]),
            ("health", ["health", "medical", "disease", "hospital", "vaccine", "treatment"]),
            ("culture", ["culture", "art", "music", "film", "book", "entertainment"]),
            ("sports", ["sport", "game", "team", "player", "championship", "league"]),
            ("environment", ["environment", "climate", "energy", "pollution", "renewable"]),
        ]
        for (domain, signals) in domains {
            if signals.contains(where: { combined.contains($0) }) {
                return domain
            }
        }
        return "general"
    }
}

/// Configuration for the serendipity engine.
public struct SerendipityConfig: Sendable {
    /// Minimum keyword overlap to consider a connection (1-10).
    public var minSharedKeywords: Int
    /// Maximum connections to return.
    public var maxConnections: Int
    /// Minimum serendipity score threshold (0-1).
    public var minSerendipityScore: Double
    /// Whether to prefer cross-domain connections.
    public var preferCrossDomain: Bool

    public init(
        minSharedKeywords: Int = 2,
        maxConnections: Int = 10,
        minSerendipityScore: Double = 0.3,
        preferCrossDomain: Bool = true
    ) {
        self.minSharedKeywords = max(1, min(10, minSharedKeywords))
        self.maxConnections = max(1, min(50, maxConnections))
        self.minSerendipityScore = max(0, min(1, minSerendipityScore))
        self.preferCrossDomain = preferCrossDomain
    }
}

/// Summary of a serendipity discovery session.
public struct SerendipityReport: Sendable {
    /// All discovered connections, sorted by serendipity score.
    public let connections: [SerendipityConnection]
    /// Total articles analyzed.
    public let articlesAnalyzed: Int
    /// Total unique feeds involved.
    public let feedsInvolved: Int
    /// Breakdown by connection type.
    public let typeBreakdown: [ConnectionType: Int]
    /// Top bridge keywords across all connections.
    public let topBridgeKeywords: [String]
    /// Average serendipity score.
    public let averageSerendipity: Double
    /// Proactive recommendations for broader reading.
    public let recommendations: [String]
}

// MARK: - Engine

/// Autonomous serendipitous article discovery engine.
///
/// Analyzes articles across feeds to find unexpected, surprising connections
/// that a user wouldn't normally discover by reading feeds independently.
///
/// Usage:
/// ```swift
/// let engine = FeedSerendipityEngine()
/// let articles = [
///     SerendipityArticle(title: "AI in Healthcare", body: "...", link: "...", feedName: "TechCrunch"),
///     SerendipityArticle(title: "Hospital Robots", body: "...", link: "...", feedName: "BBC Science"),
/// ]
/// let report = engine.discover(articles: articles)
/// print(engine.formatReport(report))
/// ```
public final class FeedSerendipityEngine: @unchecked Sendable {

    private let config: SerendipityConfig

    /// History of previously surfaced connections (by link pairs) for novelty tracking.
    private var surfacedPairs: Set<String> = []

    public init(config: SerendipityConfig = SerendipityConfig()) {
        self.config = config
    }

    // MARK: - Discovery

    /// Discover serendipitous connections across articles.
    public func discover(articles: [SerendipityArticle]) -> SerendipityReport {
        guard articles.count >= 2 else {
            return SerendipityReport(
                connections: [], articlesAnalyzed: articles.count,
                feedsInvolved: 0, typeBreakdown: [:], topBridgeKeywords: [],
                averageSerendipity: 0, recommendations: ["Add more articles from diverse feeds."]
            )
        }

        var connections: [SerendipityConnection] = []

        // Pre-compute per-article derived data ONCE before the O(N^2) loop.
        //
        // The previous implementation called `Set(a.keywords)` and
        // `Set(b.keywords)` inside the inner loop, so each article's keyword
        // list was hashed into a Set roughly (N-1) times. It also re-tokenized
        // each article body (lowercased + whitespace split + Set construction)
        // every time `classifyConnection` was reached - again, O(N) per article.
        // For 200 articles that's ~20,000 redundant Set constructions and ~200
        // redundant body tokenizations per article. Hoisting both yields a
        // measurable speedup on real feed loads.
        let keywordSets: [Set<String>] = articles.map { Set($0.keywords) }

        // Body word sets are only needed by `classifyConnection`. We compute
        // them lazily because `contrastingView` is a rare branch - we don't
        // want to pay for every article's body tokenization up front when
        // most calls won't need it. The cache survives the entire pair loop.
        var bodyWordCache: [Int: Set<String>] = [:]
        bodyWordCache.reserveCapacity(articles.count)
        func bodyWords(forIndex idx: Int) -> Set<String> {
            if let cached = bodyWordCache[idx] { return cached }
            let s = Set(articles[idx].body.lowercased().components(separatedBy: .whitespaces))
            bodyWordCache[idx] = s
            return s
        }

        // Compare all cross-feed pairs
        for i in 0..<articles.count {
            let a = articles[i]
            let aSet = keywordSets[i]
            for j in (i + 1)..<articles.count {
                let b = articles[j]

                // Skip same-feed pairs (less serendipitous)
                if a.feedName == b.feedName { continue }

                let shared = aSet.intersection(keywordSets[j])
                if shared.count < config.minSharedKeywords { continue }

                let score = computeSerendipityScore(
                    a: a, b: b,
                    aKeywordSet: aSet, bKeywordSet: keywordSets[j],
                    sharedKeywords: shared
                )
                if score < config.minSerendipityScore { continue }

                let connectionType = classifyConnection(
                    a: a, b: b, shared: shared,
                    aBodyWords: { bodyWords(forIndex: i) },
                    bBodyWords: { bodyWords(forIndex: j) }
                )
                let explanation = generateExplanation(a: a, b: b, shared: shared, type: connectionType)

                let pairKey = [a.link, b.link].sorted().joined(separator: "|")
                let isNovel = !surfacedPairs.contains(pairKey)
                let finalScore = isNovel ? score : score * 0.7

                connections.append(SerendipityConnection(
                    articleA: a, articleB: b,
                    bridgeKeywords: Array(shared).sorted(),
                    serendipityScore: finalScore,
                    explanation: explanation,
                    connectionType: connectionType
                ))
            }
        }

        // Sort by serendipity score and take top N
        connections.sort { $0.serendipityScore > $1.serendipityScore }
        let topConnections = Array(connections.prefix(config.maxConnections))

        // Track surfaced pairs
        for c in topConnections {
            let key = [c.articleA.link, c.articleB.link].sorted().joined(separator: "|")
            surfacedPairs.insert(key)
        }

        let feedNames = Set(articles.map { $0.feedName })
        let typeBreakdown = Dictionary(grouping: topConnections, by: { $0.connectionType })
            .mapValues { $0.count }

        var bridgeFreq: [String: Int] = [:]
        for c in topConnections {
            for kw in c.bridgeKeywords {
                bridgeFreq[kw, default: 0] += 1
            }
        }
        let topBridge = bridgeFreq.sorted { $0.value > $1.value }.prefix(10).map { $0.key }

        let avgScore = topConnections.isEmpty ? 0 :
            topConnections.reduce(0.0) { $0 + $1.serendipityScore } / Double(topConnections.count)

        let recommendations = generateRecommendations(
            articles: articles, connections: topConnections, feedNames: feedNames
        )

        return SerendipityReport(
            connections: topConnections,
            articlesAnalyzed: articles.count,
            feedsInvolved: feedNames.count,
            typeBreakdown: typeBreakdown,
            topBridgeKeywords: topBridge,
            averageSerendipity: avgScore,
            recommendations: recommendations
        )
    }

    // MARK: - Scoring

    private func computeSerendipityScore(
        a: SerendipityArticle, b: SerendipityArticle,
        aKeywordSet: Set<String>, bKeywordSet: Set<String>,
        sharedKeywords: Set<String>
    ) -> Double {
        let allKeywords = aKeywordSet.union(bKeywordSet)
        let jaccard = allKeywords.isEmpty ? 0 : Double(sharedKeywords.count) / Double(allKeywords.count)

        // Surprise factor: connections with moderate overlap are most serendipitous
        // Too much overlap = obvious, too little = tenuous
        let overlapRatio = Double(sharedKeywords.count) / Double(max(a.keywords.count, b.keywords.count, 1))
        let surpriseFactor = 4.0 * overlapRatio * (1.0 - overlapRatio) // peaks at 0.5

        // Cross-domain bonus
        let crossDomainBonus: Double = (a.domain != b.domain) ? 0.25 : 0.0

        // Feed diversity bonus
        let feedDiversityBonus: Double = (a.feedName != b.feedName) ? 0.1 : 0.0

        let raw = (jaccard * 0.3) + (surpriseFactor * 0.4) + crossDomainBonus + feedDiversityBonus
        return min(1.0, max(0.0, raw))
    }

    /// Module-level Sets so they are constructed exactly once instead of
    /// rebuilt on every `classifyConnection` call.
    private static let contrastWords: Set<String> = [
        "but", "however", "despite", "although", "versus", "against", "debate"
    ]
    private static let emergingWords: Set<String> = [
        "new", "emerging", "rising", "growing", "breakthrough", "first"
    ]

    private func classifyConnection(
        a: SerendipityArticle, b: SerendipityArticle, shared: Set<String>,
        aBodyWords: () -> Set<String>,
        bBodyWords: () -> Set<String>
    ) -> ConnectionType {
        if a.domain != b.domain && shared.count >= 3 {
            return .crossDomain
        }

        // Check for contrasting sentiment signals. The body-word sets come
        // from the caller's per-article cache so we don't re-tokenize the
        // same article body for every pair it appears in.
        let aWords = aBodyWords()
        let bWords = bBodyWords()
        let contrastWords = FeedSerendipityEngine.contrastWords
        if !aWords.intersection(contrastWords).isEmpty && !bWords.intersection(contrastWords).isEmpty {
            return .contrastingView
        }

        if a.domain == b.domain && shared.count >= 4 {
            return .hiddenThread
        }

        if !shared.intersection(FeedSerendipityEngine.emergingWords).isEmpty {
            return .emergingNexus
        }

        return .unexpectedParallel
    }

    private func generateExplanation(
        a: SerendipityArticle, b: SerendipityArticle, shared: Set<String>, type: ConnectionType
    ) -> String {
        let kwList = shared.sorted().prefix(4).joined(separator: ", ")
        switch type {
        case .crossDomain:
            return "Articles from \(a.domain) and \(b.domain) unexpectedly converge on: \(kwList)"
        case .hiddenThread:
            return "A hidden thread connects these \(a.domain) articles through: \(kwList)"
        case .contrastingView:
            return "These articles offer contrasting perspectives linked by: \(kwList)"
        case .unexpectedParallel:
            return "An unexpected parallel emerges between '\(a.feedName)' and '\(b.feedName)' via: \(kwList)"
        case .emergingNexus:
            return "An emerging nexus is forming around: \(kwList)"
        }
    }

    // MARK: - Recommendations

    private func generateRecommendations(
        articles: [SerendipityArticle],
        connections: [SerendipityConnection],
        feedNames: Set<String>
    ) -> [String] {
        var recs: [String] = []

        // Domain coverage analysis
        let domains = Set(articles.map { $0.domain })
        let allDomains: Set<String> = ["technology", "science", "business", "politics", "health", "culture", "sports", "environment"]
        let missing = allDomains.subtracting(domains)
        if !missing.isEmpty {
            let top = missing.sorted().prefix(3).joined(separator: ", ")
            recs.append("Add feeds covering \(top) to unlock more cross-domain discoveries.")
        }

        // Feed diversity
        if feedNames.count < 4 {
            recs.append("Subscribe to more diverse feeds — serendipity thrives on variety.")
        }

        // Connection density
        if connections.count < 3 && articles.count > 10 {
            recs.append("Your feeds may be too siloed. Look for feeds that bridge your interests.")
        }

        // Bridge keyword insight
        if let top = connections.first {
            let kw = top.bridgeKeywords.prefix(3).joined(separator: ", ")
            recs.append("Your strongest connection bridge is around '\(kw)' — explore this intersection.")
        }

        // High serendipity encouragement
        let highSerendipity = connections.filter { $0.serendipityScore > 0.7 }
        if highSerendipity.count > 0 {
            recs.append("\(highSerendipity.count) highly serendipitous connection(s) found — these are rare gems worth reading!")
        }

        if recs.isEmpty {
            recs.append("Great feed diversity! Keep reading broadly for more serendipitous discoveries.")
        }

        return recs
    }

    // MARK: - Formatting

    /// Format a serendipity report as a human-readable string.
    public func formatReport(_ report: SerendipityReport) -> String {
        var lines: [String] = []
        lines.append("╔══════════════════════════════════════════════════╗")
        lines.append("║         🔮 SERENDIPITY DISCOVERY REPORT         ║")
        lines.append("╚══════════════════════════════════════════════════╝")
        lines.append("")
        lines.append("📊 Overview")
        lines.append("  Articles analyzed:  \(report.articlesAnalyzed)")
        lines.append("  Feeds involved:     \(report.feedsInvolved)")
        lines.append("  Connections found:  \(report.connections.count)")
        lines.append("  Avg serendipity:    \(String(format: "%.0f%%", report.averageSerendipity * 100))")
        lines.append("")

        if !report.typeBreakdown.isEmpty {
            lines.append("🏷️  Connection Types")
            for (type, count) in report.typeBreakdown.sorted(by: { $0.value > $1.value }) {
                let bar = String(repeating: "█", count: min(count, 20))
                lines.append("  \(type.rawValue): \(bar) \(count)")
            }
            lines.append("")
        }

        if !report.topBridgeKeywords.isEmpty {
            lines.append("🔑 Top Bridge Keywords: \(report.topBridgeKeywords.joined(separator: ", "))")
            lines.append("")
        }

        if !report.connections.isEmpty {
            lines.append("🔗 Serendipitous Connections")
            lines.append(String(repeating: "─", count: 50))
            for (i, c) in report.connections.enumerated() {
                let pct = String(format: "%.0f%%", c.serendipityScore * 100)
                lines.append("")
                lines.append("  #\(i + 1) [\(c.connectionType.rawValue)] — \(pct) serendipity")
                lines.append("  📰 \(c.articleA.title)")
                lines.append("     from \(c.articleA.feedName)")
                lines.append("  🔀")
                lines.append("  📰 \(c.articleB.title)")
                lines.append("     from \(c.articleB.feedName)")
                lines.append("  🌉 Bridge: \(c.bridgeKeywords.joined(separator: ", "))")
                lines.append("  💡 \(c.explanation)")
            }
            lines.append("")
        }

        if !report.recommendations.isEmpty {
            lines.append("🧭 Recommendations")
            for r in report.recommendations {
                lines.append("  • \(r)")
            }
        }

        return lines.joined(separator: "\n")
    }

    /// Export report as JSON-compatible dictionary.
    public func exportJSON(_ report: SerendipityReport) -> [String: Any] {
        return [
            "articlesAnalyzed": report.articlesAnalyzed,
            "feedsInvolved": report.feedsInvolved,
            "averageSerendipity": report.averageSerendipity,
            "topBridgeKeywords": report.topBridgeKeywords,
            "recommendations": report.recommendations,
            "connections": report.connections.map { c in
                [
                    "articleA": ["title": c.articleA.title, "link": c.articleA.link, "feed": c.articleA.feedName],
                    "articleB": ["title": c.articleB.title, "link": c.articleB.link, "feed": c.articleB.feedName],
                    "bridgeKeywords": c.bridgeKeywords,
                    "serendipityScore": c.serendipityScore,
                    "connectionType": c.connectionType.rawValue,
                    "explanation": c.explanation,
                ] as [String: Any]
            },
        ]
    }
}
