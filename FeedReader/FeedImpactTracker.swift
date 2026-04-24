//
//  FeedImpactTracker.swift
//  FeedReader
//
//  Autonomous article impact tracking engine that measures how influential
//  articles are over time. Detects when later articles reference, follow up on,
//  or relate to earlier tracked articles, building an "impact score" that
//  evolves through lifecycle phases.
//
//  Agentic capabilities:
//  - Tracks articles and detects ripple effects (follow-ups, citations,
//    reactions, expansions, contradictions) via Jaccard keyword similarity
//  - Impact scoring with recency decay and type-weighted ripple counts
//  - 5-phase lifecycle tracking (emerging → growing → peaking → fading → dormant)
//  - 6 alert types: viral detection, phase transitions, cross-feed spread,
//    contradictions, dormant revivals, impact milestones
//  - Auto-monitor mode for continuous impact analysis
//  - Full impact reports with summary stats, top articles, phase distribution
//  - Proactive notifications for significant impact events
//
//  Fully offline — no network, no dependencies beyond Foundation.
//

import Foundation

// MARK: - Notifications

extension Notification.Name {
    static let impactRippleDetected = Notification.Name("ImpactRippleDetectedNotification")
    static let impactPhaseChanged = Notification.Name("ImpactPhaseChangedNotification")
    static let impactAlertGenerated = Notification.Name("ImpactAlertGeneratedNotification")
    static let impactViralDetected = Notification.Name("ImpactViralDetectedNotification")
}

// MARK: - Impact Phase

/// Lifecycle phase of a tracked article's impact.
enum ImpactPhase: String, Codable, CaseIterable {
    case emerging = "emerging"
    case growing = "growing"
    case peaking = "peaking"
    case fading = "fading"
    case dormant = "dormant"

    var label: String {
        switch self {
        case .emerging: return "Emerging"
        case .growing: return "Growing"
        case .peaking: return "Peaking"
        case .fading: return "Fading"
        case .dormant: return "Dormant"
        }
    }

    var emoji: String {
        switch self {
        case .emerging: return "🌱"
        case .growing: return "📈"
        case .peaking: return "🔥"
        case .fading: return "🌅"
        case .dormant: return "💤"
        }
    }
}

// MARK: - Ripple Type

/// How a later article relates to the original tracked article.
enum RippleType: String, Codable, CaseIterable {
    case followUp = "follow_up"
    case citation = "citation"
    case reaction = "reaction"
    case expansion = "expansion"
    case contradiction = "contradiction"

    var label: String {
        switch self {
        case .followUp: return "Follow-Up"
        case .citation: return "Citation"
        case .reaction: return "Reaction"
        case .expansion: return "Expansion"
        case .contradiction: return "Contradiction"
        }
    }

    /// Weight multiplier for impact score calculation.
    var weight: Double {
        switch self {
        case .followUp: return 1.0
        case .citation: return 1.5
        case .reaction: return 0.8
        case .expansion: return 1.3
        case .contradiction: return 1.2
        }
    }
}

// MARK: - Alert Severity

enum ImpactAlertSeverity: String, Codable, CaseIterable {
    case low = "low"
    case medium = "medium"
    case high = "high"
    case critical = "critical"

    var label: String { rawValue.capitalized }
}

// MARK: - Impact Alert Type

enum ImpactAlertType: String, Codable, CaseIterable {
    case viralDetected = "viral_detected"
    case phaseTransition = "phase_transition"
    case crossFeedSpread = "cross_feed_spread"
    case contradictionFound = "contradiction_found"
    case dormantRevival = "dormant_revival"
    case impactMilestone = "impact_milestone"

    var label: String {
        switch self {
        case .viralDetected: return "Viral Detected"
        case .phaseTransition: return "Phase Transition"
        case .crossFeedSpread: return "Cross-Feed Spread"
        case .contradictionFound: return "Contradiction Found"
        case .dormantRevival: return "Dormant Revival"
        case .impactMilestone: return "Impact Milestone"
        }
    }
}

// MARK: - Data Models

/// A tracked article whose impact is being monitored.
struct ImpactEntry: Codable, Identifiable {
    let id: String
    let articleTitle: String
    let articleLink: String
    let sourceFeed: String
    let publishDate: Date
    let keywords: [String]
    var impactScore: Double
    var rippleCount: Int
    var firstRippleDate: Date?
    var lastRippleDate: Date?
    var peakImpactScore: Double
    var phase: ImpactPhase
    var relatedArticleIds: [String]

    init(articleTitle: String, articleLink: String, sourceFeed: String,
         publishDate: Date = Date(), keywords: [String]) {
        self.id = UUID().uuidString
        self.articleTitle = articleTitle
        self.articleLink = articleLink
        self.sourceFeed = sourceFeed
        self.publishDate = publishDate
        self.keywords = keywords.map { $0.lowercased() }
        self.impactScore = 0.0
        self.rippleCount = 0
        self.firstRippleDate = nil
        self.lastRippleDate = nil
        self.peakImpactScore = 0.0
        self.phase = .emerging
        self.relatedArticleIds = []
    }
}

/// A detected ripple — a later article that relates to a tracked entry.
struct ImpactRipple: Codable, Identifiable {
    let id: String
    let sourceEntryId: String
    let rippleArticleTitle: String
    let rippleArticleLink: String
    let rippleFeed: String
    let rippleDate: Date
    let similarityScore: Double
    let rippleType: RippleType

    init(sourceEntryId: String, rippleArticleTitle: String,
         rippleArticleLink: String, rippleFeed: String,
         rippleDate: Date = Date(), similarityScore: Double,
         rippleType: RippleType) {
        self.id = UUID().uuidString
        self.sourceEntryId = sourceEntryId
        self.rippleArticleTitle = rippleArticleTitle
        self.rippleArticleLink = rippleArticleLink
        self.rippleFeed = rippleFeed
        self.rippleDate = rippleDate
        self.similarityScore = similarityScore
        self.rippleType = rippleType
    }
}

/// An alert generated by the impact tracker.
struct ImpactAlert: Codable, Identifiable {
    let id: String
    let entryId: String
    let alertType: ImpactAlertType
    let message: String
    let date: Date
    let severity: ImpactAlertSeverity

    init(entryId: String, alertType: ImpactAlertType, message: String,
         severity: ImpactAlertSeverity) {
        self.id = UUID().uuidString
        self.entryId = entryId
        self.alertType = alertType
        self.message = message
        self.date = Date()
        self.severity = severity
    }
}

/// Summary report of all tracked impact data.
struct ImpactReport {
    let totalTracked: Int
    let totalRipples: Int
    let activeAlerts: Int
    let topArticles: [ImpactEntry]
    let phaseDistribution: [ImpactPhase: Int]
    let crossFeedInsights: [String]
    let averageImpactScore: Double
    let mostImpactfulFeed: String?
    let recentAlerts: [ImpactAlert]
}

// MARK: - FeedImpactTracker

/// Autonomous engine that tracks article impact over time by detecting
/// ripple effects — follow-ups, citations, reactions, expansions, and
/// contradictions — across RSS feed articles.
final class FeedImpactTracker {

    // MARK: - Public State

    private(set) var entries: [ImpactEntry] = []
    private(set) var ripples: [ImpactRipple] = []
    private(set) var alerts: [ImpactAlert] = []

    var autoMonitorEnabled: Bool = false
    var autoMonitorInterval: TimeInterval = 300 // 5 minutes

    // MARK: - Private

    private var monitorTimer: Timer?
    private let storageKey = "FeedImpactTracker_entries"
    private let ripplesStorageKey = "FeedImpactTracker_ripples"
    private let alertsStorageKey = "FeedImpactTracker_alerts"

    private let similarityThreshold: Double = 0.15
    private let viralThreshold: Int = 5 // ripples in 24h
    private let crossFeedThreshold: Int = 3 // unique feeds
    private let dormantDays: Int = 14

    // Keyword sets for ripple type classification
    private let citationKeywords: Set<String> = [
        "according", "reported", "study", "research", "found", "published",
        "confirmed", "stated", "announced", "revealed", "data", "evidence"
    ]
    private let contradictionKeywords: Set<String> = [
        "however", "dispute", "deny", "contradict", "refute", "challenge",
        "disagree", "debunk", "question", "doubt", "false", "misleading"
    ]
    private let reactionKeywords: Set<String> = [
        "opinion", "believe", "think", "response", "react", "backlash",
        "praise", "criticize", "support", "oppose", "outrage", "celebrate"
    ]

    // MARK: - Singleton

    static let shared = FeedImpactTracker()

    init() {
        loadState()
    }

    // MARK: - Track Article

    /// Begin tracking a new article for impact monitoring.
    /// - Parameters:
    ///   - title: Article title.
    ///   - link: Article URL.
    ///   - feed: Source feed name.
    ///   - date: Publish date.
    ///   - keywords: Keywords/tags for similarity matching.
    /// - Returns: The created ImpactEntry.
    @discardableResult
    func trackArticle(title: String, link: String, feed: String,
                      date: Date = Date(), keywords: [String]) -> ImpactEntry {
        // Avoid duplicates
        if let existing = entries.first(where: { $0.articleLink == link }) {
            return existing
        }
        let entry = ImpactEntry(articleTitle: title, articleLink: link,
                                sourceFeed: feed, publishDate: date,
                                keywords: keywords)
        entries.append(entry)
        saveState()
        return entry
    }

    /// Remove a tracked entry.
    func untrackArticle(entryId: String) {
        entries.removeAll { $0.id == entryId }
        ripples.removeAll { $0.sourceEntryId == entryId }
        alerts.removeAll { $0.entryId == entryId }
        saveState()
    }

    // MARK: - Process New Articles

    /// Incoming article tuple for ripple scanning.
    struct IncomingArticle {
        let title: String
        let link: String
        let feed: String
        let date: Date
        let content: String
    }

    /// Scan a batch of new articles for ripples against all tracked entries.
    /// Updates impact scores, phases, and generates alerts.
    /// - Parameter articles: Array of new articles to scan.
    /// - Returns: Array of detected ripples.
    @discardableResult
    func processNewArticles(_ articles: [IncomingArticle]) -> [ImpactRipple] {
        var detected: [ImpactRipple] = []

        for article in articles {
            let articleKeywords = extractKeywords(from: article.title + " " + article.content)

            for i in 0..<entries.count {
                if let ripple = detectRipple(entry: entries[i], articleTitle: article.title,
                                              articleLink: article.link, articleFeed: article.feed,
                                              articleDate: article.date,
                                              articleKeywords: articleKeywords) {
                    ripples.append(ripple)
                    detected.append(ripple)

                    // Update entry
                    entries[i].rippleCount += 1
                    if entries[i].firstRippleDate == nil {
                        entries[i].firstRippleDate = article.date
                    }
                    entries[i].lastRippleDate = article.date
                    entries[i].relatedArticleIds.append(ripple.id)

                    NotificationCenter.default.post(
                        name: .impactRippleDetected,
                        object: self,
                        userInfo: ["ripple": ripple, "entryId": entries[i].id]
                    )
                }
            }
        }

        // Recalculate scores and phases
        recalculateAll()
        generateAlerts()
        saveState()

        return detected
    }

    // MARK: - Ripple Detection

    /// Detect whether an article is a ripple of a tracked entry.
    private func detectRipple(entry: ImpactEntry, articleTitle: String,
                              articleLink: String, articleFeed: String,
                              articleDate: Date,
                              articleKeywords: [String]) -> ImpactRipple? {
        // Skip self-references
        if articleLink == entry.articleLink { return nil }

        let entrySet = Set(entry.keywords)
        let articleSet = Set(articleKeywords)

        let intersection = entrySet.intersection(articleSet)
        let union = entrySet.union(articleSet)

        guard !union.isEmpty else { return nil }

        let similarity = Double(intersection.count) / Double(union.count)
        guard similarity >= similarityThreshold else { return nil }

        let rippleType = classifyRippleType(similarity: similarity,
                                             articleKeywords: articleKeywords,
                                             entryKeywords: entry.keywords)

        return ImpactRipple(sourceEntryId: entry.id,
                            rippleArticleTitle: articleTitle,
                            rippleArticleLink: articleLink,
                            rippleFeed: articleFeed,
                            rippleDate: articleDate,
                            similarityScore: similarity,
                            rippleType: rippleType)
    }

    /// Classify the type of ripple based on keyword analysis.
    private func classifyRippleType(similarity: Double,
                                     articleKeywords: [String],
                                     entryKeywords: [String]) -> RippleType {
        let articleSet = Set(articleKeywords)

        // Check contradiction signals
        if !articleSet.intersection(contradictionKeywords).isEmpty {
            return .contradiction
        }

        // Check citation signals
        if !articleSet.intersection(citationKeywords).isEmpty {
            return .citation
        }

        // High similarity + new keywords = expansion
        let entrySet = Set(entryKeywords)
        let newKeywords = articleSet.subtracting(entrySet)
        if similarity > 0.4 && newKeywords.count >= 3 {
            return .expansion
        }

        // Reaction signals
        if !articleSet.intersection(reactionKeywords).isEmpty {
            return .reaction
        }

        // Default: follow-up
        return .followUp
    }

    // MARK: - Score & Phase Calculation

    /// Recalculate impact scores and phases for all entries.
    private func recalculateAll() {
        let now = Date()
        for i in 0..<entries.count {
            entries[i].impactScore = calculateImpactScore(for: entries[i], now: now)
            if entries[i].impactScore > entries[i].peakImpactScore {
                entries[i].peakImpactScore = entries[i].impactScore
            }
            let oldPhase = entries[i].phase
            entries[i].phase = calculatePhase(for: entries[i], now: now)
            if oldPhase != entries[i].phase {
                NotificationCenter.default.post(
                    name: .impactPhaseChanged,
                    object: self,
                    userInfo: ["entryId": entries[i].id,
                               "oldPhase": oldPhase.rawValue,
                               "newPhase": entries[i].phase.rawValue]
                )
            }
        }
    }

    /// Calculate impact score for an entry using weighted ripples with recency decay.
    private func calculateImpactScore(for entry: ImpactEntry, now: Date) -> Double {
        let entryRipples = ripples.filter { $0.sourceEntryId == entry.id }
        guard !entryRipples.isEmpty else { return 0.0 }

        var score: Double = 0.0
        for ripple in entryRipples {
            let daysSinceRipple = max(1.0, now.timeIntervalSince(ripple.rippleDate) / 86400.0)
            let recencyDecay = 1.0 / log2(daysSinceRipple + 1.0)
            score += ripple.rippleType.weight * recencyDecay * ripple.similarityScore
        }

        return round(score * 100.0) / 100.0
    }

    /// Calculate the lifecycle phase based on ripple velocity.
    private func calculatePhase(for entry: ImpactEntry, now: Date) -> ImpactPhase {
        let entryRipples = ripples.filter { $0.sourceEntryId == entry.id }

        // Check dormant first
        if let lastRipple = entry.lastRippleDate {
            let daysSinceLast = now.timeIntervalSince(lastRipple) / 86400.0
            if daysSinceLast > Double(dormantDays) {
                return .dormant
            }
        }

        // Calculate 7-day ripple velocity
        let sevenDaysAgo = now.addingTimeInterval(-7 * 86400)
        let recentRipples = entryRipples.filter { $0.rippleDate >= sevenDaysAgo }
        let velocity = Double(recentRipples.count) / 7.0

        if entryRipples.count < 3 && velocity < 0.5 {
            return .emerging
        }

        if velocity > 2.0 {
            return .peaking
        }

        if velocity >= 0.5 {
            return .growing
        }

        // Was previously active but slowed
        if entry.phase == .peaking || entry.phase == .growing {
            return .fading
        }

        if entry.rippleCount == 0 {
            return .emerging
        }

        return .fading
    }

    // MARK: - Alert Generation

    /// Generate proactive alerts based on current state.
    private func generateAlerts() {
        let now = Date()
        let oneDayAgo = now.addingTimeInterval(-86400)

        for entry in entries {
            let entryRipples = ripples.filter { $0.sourceEntryId == entry.id }

            // Viral detection: >5 ripples in 24h
            let recentRipples = entryRipples.filter { $0.rippleDate >= oneDayAgo }
            if recentRipples.count >= viralThreshold {
                if !hasRecentAlert(entryId: entry.id, type: .viralDetected, since: oneDayAgo) {
                    let alert = ImpactAlert(
                        entryId: entry.id,
                        alertType: .viralDetected,
                        message: "'\(entry.articleTitle)' is going viral with \(recentRipples.count) ripples in the last 24h!",
                        severity: .critical
                    )
                    alerts.append(alert)
                    NotificationCenter.default.post(name: .impactViralDetected, object: self,
                                                    userInfo: ["alert": alert])
                    NotificationCenter.default.post(name: .impactAlertGenerated, object: self,
                                                    userInfo: ["alert": alert])
                }
            }

            // Cross-feed spread
            let uniqueFeeds = Set(entryRipples.map { $0.rippleFeed })
            if uniqueFeeds.count >= crossFeedThreshold {
                if !hasRecentAlert(entryId: entry.id, type: .crossFeedSpread, since: oneDayAgo) {
                    let alert = ImpactAlert(
                        entryId: entry.id,
                        alertType: .crossFeedSpread,
                        message: "'\(entry.articleTitle)' has spread across \(uniqueFeeds.count) different feeds.",
                        severity: .high
                    )
                    alerts.append(alert)
                    NotificationCenter.default.post(name: .impactAlertGenerated, object: self,
                                                    userInfo: ["alert": alert])
                }
            }

            // Contradiction found
            let contradictions = entryRipples.filter { $0.rippleType == .contradiction }
            let recentContradictions = contradictions.filter { $0.rippleDate >= oneDayAgo }
            if !recentContradictions.isEmpty {
                if !hasRecentAlert(entryId: entry.id, type: .contradictionFound, since: oneDayAgo) {
                    let alert = ImpactAlert(
                        entryId: entry.id,
                        alertType: .contradictionFound,
                        message: "'\(entry.articleTitle)' has been contradicted by \(recentContradictions.count) article(s).",
                        severity: .medium
                    )
                    alerts.append(alert)
                    NotificationCenter.default.post(name: .impactAlertGenerated, object: self,
                                                    userInfo: ["alert": alert])
                }
            }

            // Dormant revival: was dormant, now has new ripples
            if entry.phase != .dormant {
                let fourteenDaysAgo = now.addingTimeInterval(-Double(dormantDays) * 86400)
                let oldRipples = entryRipples.filter { $0.rippleDate < fourteenDaysAgo }
                let freshRipples = entryRipples.filter { $0.rippleDate >= oneDayAgo }
                if !oldRipples.isEmpty && !freshRipples.isEmpty {
                    let gapBetween = oldRipples.max(by: { $0.rippleDate < $1.rippleDate })
                    if let lastOld = gapBetween?.rippleDate {
                        let gapDays = (freshRipples.first?.rippleDate.timeIntervalSince(lastOld) ?? 0) / 86400
                        if gapDays > Double(dormantDays) {
                            if !hasRecentAlert(entryId: entry.id, type: .dormantRevival, since: oneDayAgo) {
                                let alert = ImpactAlert(
                                    entryId: entry.id,
                                    alertType: .dormantRevival,
                                    message: "'\(entry.articleTitle)' has revived after \(Int(gapDays)) days of dormancy!",
                                    severity: .high
                                )
                                alerts.append(alert)
                                NotificationCenter.default.post(name: .impactAlertGenerated, object: self,
                                                                userInfo: ["alert": alert])
                            }
                        }
                    }
                }
            }

            // Impact milestones (every 10 ripples)
            let milestoneThresholds = [10, 25, 50, 100, 250, 500]
            for milestone in milestoneThresholds {
                if entry.rippleCount >= milestone {
                    let existingMilestone = alerts.first(where: {
                        $0.entryId == entry.id &&
                        $0.alertType == .impactMilestone &&
                        $0.message.contains("\(milestone)")
                    })
                    if existingMilestone == nil {
                        let alert = ImpactAlert(
                            entryId: entry.id,
                            alertType: .impactMilestone,
                            message: "'\(entry.articleTitle)' has reached \(milestone) ripples!",
                            severity: milestone >= 100 ? .critical : milestone >= 25 ? .high : .medium
                        )
                        alerts.append(alert)
                        NotificationCenter.default.post(name: .impactAlertGenerated, object: self,
                                                        userInfo: ["alert": alert])
                    }
                }
            }
        }
    }

    /// Check if an alert of a given type was already generated recently.
    private func hasRecentAlert(entryId: String, type: ImpactAlertType, since: Date) -> Bool {
        return alerts.contains {
            $0.entryId == entryId && $0.alertType == type && $0.date >= since
        }
    }

    // MARK: - Queries

    /// Get the top impact articles sorted by score.
    func getTopImpactArticles(limit: Int = 10) -> [ImpactEntry] {
        return Array(entries.sorted { $0.impactScore > $1.impactScore }.prefix(limit))
    }

    /// Get chronological ripple timeline for a specific entry.
    func getImpactTimeline(for entryId: String) -> [ImpactRipple] {
        return ripples.filter { $0.sourceEntryId == entryId }
            .sorted { $0.rippleDate < $1.rippleDate }
    }

    /// Get ripples grouped by type for an entry.
    func getRipplesByType(for entryId: String) -> [RippleType: [ImpactRipple]] {
        let entryRipples = ripples.filter { $0.sourceEntryId == entryId }
        return Dictionary(grouping: entryRipples, by: { $0.rippleType })
    }

    /// Get all entries in a specific phase.
    func getEntriesByPhase(_ phase: ImpactPhase) -> [ImpactEntry] {
        return entries.filter { $0.phase == phase }
    }

    /// Generate a comprehensive impact report.
    func getImpactReport() -> ImpactReport {
        let phaseDistribution = Dictionary(grouping: entries, by: { $0.phase })
            .mapValues { $0.count }

        let avgScore = entries.isEmpty ? 0.0 :
            entries.reduce(0.0) { $0 + $1.impactScore } / Double(entries.count)

        // Cross-feed insights
        var insights: [String] = []
        let feedRippleCounts = Dictionary(grouping: ripples, by: { $0.rippleFeed })
            .mapValues { $0.count }
            .sorted { $0.value > $1.value }

        if let topFeed = feedRippleCounts.first {
            insights.append("Most active ripple source: \(topFeed.key) (\(topFeed.value) ripples)")
        }

        let contradictionCount = ripples.filter { $0.rippleType == .contradiction }.count
        if contradictionCount > 0 {
            insights.append("\(contradictionCount) contradictions detected across all tracked articles")
        }

        let peakingCount = entries.filter { $0.phase == .peaking }.count
        if peakingCount > 0 {
            insights.append("\(peakingCount) article(s) currently peaking in impact")
        }

        let dormantRevivable = entries.filter { $0.phase == .dormant && $0.rippleCount > 5 }
        if !dormantRevivable.isEmpty {
            insights.append("\(dormantRevivable.count) high-impact article(s) went dormant — watch for revivals")
        }

        // Most impactful feed
        let feedScores = Dictionary(grouping: entries, by: { $0.sourceFeed })
            .mapValues { entries in entries.reduce(0.0) { $0 + $1.impactScore } }
        let topFeedByScore = feedScores.max { $0.value < $1.value }

        let recentAlerts = Array(alerts.sorted { $0.date > $1.date }.prefix(10))

        return ImpactReport(
            totalTracked: entries.count,
            totalRipples: ripples.count,
            activeAlerts: alerts.filter {
                $0.date >= Date().addingTimeInterval(-86400)
            }.count,
            topArticles: getTopImpactArticles(limit: 5),
            phaseDistribution: phaseDistribution,
            crossFeedInsights: insights,
            averageImpactScore: round(avgScore * 100.0) / 100.0,
            mostImpactfulFeed: topFeedByScore?.key,
            recentAlerts: recentAlerts
        )
    }

    // MARK: - Auto-Monitor

    /// Start autonomous monitoring. Periodically recalculates scores and phases.
    func startAutoMonitor() {
        stopAutoMonitor()
        autoMonitorEnabled = true
        monitorTimer = Timer.scheduledTimer(withTimeInterval: autoMonitorInterval,
                                            repeats: true) { [weak self] _ in
            self?.runAutoMonitorCycle()
        }
    }

    /// Stop autonomous monitoring.
    func stopAutoMonitor() {
        autoMonitorEnabled = false
        monitorTimer?.invalidate()
        monitorTimer = nil
    }

    /// Single auto-monitor cycle: recalculate and generate alerts.
    private func runAutoMonitorCycle() {
        recalculateAll()
        generateAlerts()
        saveState()
    }

    // MARK: - Keyword Extraction

    /// Extract keywords from text using simple tokenization and stop word removal.
    private func extractKeywords(from text: String) -> [String] {
        let stopWords: Set<String> = [
            "the", "a", "an", "is", "are", "was", "were", "be", "been", "being",
            "have", "has", "had", "do", "does", "did", "will", "would", "could",
            "should", "may", "might", "shall", "can", "need", "dare", "ought",
            "used", "to", "of", "in", "for", "on", "with", "at", "by", "from",
            "as", "into", "through", "during", "before", "after", "above",
            "below", "between", "out", "off", "over", "under", "again",
            "further", "then", "once", "here", "there", "when", "where", "why",
            "how", "all", "both", "each", "few", "more", "most", "other",
            "some", "such", "no", "nor", "not", "only", "own", "same", "so",
            "than", "too", "very", "just", "because", "but", "and", "or", "if",
            "while", "about", "up", "that", "this", "these", "those", "it", "its",
            "i", "me", "my", "we", "our", "you", "your", "he", "him", "his",
            "she", "her", "they", "them", "their", "what", "which", "who"
        ]

        let cleaned = text.lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { $0.count > 2 && !stopWords.contains($0) }

        // Deduplicate while preserving order
        var seen = Set<String>()
        return cleaned.filter { seen.insert($0).inserted }
    }

    // MARK: - Persistence

    /// Save all state to UserDefaults.
    private func saveState() {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        if let data = try? encoder.encode(entries) {
            UserDefaults.standard.set(data, forKey: storageKey)
        }
        if let data = try? encoder.encode(ripples) {
            UserDefaults.standard.set(data, forKey: ripplesStorageKey)
        }
        if let data = try? encoder.encode(alerts) {
            UserDefaults.standard.set(data, forKey: alertsStorageKey)
        }
    }

    /// Load state from UserDefaults.
    private func loadState() {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        if let data = UserDefaults.standard.data(forKey: storageKey),
           let decoded = try? decoder.decode([ImpactEntry].self, from: data) {
            entries = decoded
        }
        if let data = UserDefaults.standard.data(forKey: ripplesStorageKey),
           let decoded = try? decoder.decode([ImpactRipple].self, from: data) {
            ripples = decoded
        }
        if let data = UserDefaults.standard.data(forKey: alertsStorageKey),
           let decoded = try? decoder.decode([ImpactAlert].self, from: data) {
            alerts = decoded
        }
    }

    /// Clear all tracked data.
    func resetAll() {
        entries.removeAll()
        ripples.removeAll()
        alerts.removeAll()
        saveState()
    }
}
