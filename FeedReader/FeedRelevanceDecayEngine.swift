//
//  FeedRelevanceDecayEngine.swift
//  FeedReader
//
//  Autonomous article relevance decay engine. Tracks how article
//  relevance decays over time, classifies content as evergreen vs
//  perishable, and helps users prioritise their reading queue by
//  urgency. Four decay models (exponential / linear / step-function /
//  logarithmic) capture the distinct shelf-lives of breaking news,
//  tutorials, opinion pieces, reference material and more.
//

import Foundation

// MARK: - Notifications

extension Notification.Name {
    static let relevanceDecayDidChange   = Notification.Name("RelevanceDecayDidChangeNotification")
    static let urgentReadingDetected     = Notification.Name("UrgentReadingDetectedNotification")
}

// MARK: - ContentType

/// The editorial category of an article, each with a characteristic
/// default half-life measured in **hours**.
enum RelevanceContentType: String, Codable, CaseIterable {
    case breaking   = "breaking"
    case trending   = "trending"
    case analysis   = "analysis"
    case opinion    = "opinion"
    case tutorial   = "tutorial"
    case reference  = "reference"
    case evergreen  = "evergreen"
    case seasonal   = "seasonal"
    case archive    = "archive"

    /// Default half-life in **seconds**.
    var defaultHalfLife: TimeInterval {
        switch self {
        case .breaking:   return   2 * 3600   //   2 h
        case .trending:   return  12 * 3600   //  12 h
        case .analysis:   return  72 * 3600   //  72 h
        case .opinion:    return  48 * 3600   //  48 h
        case .tutorial:   return 720 * 3600   //  30 d
        case .reference:  return 2160 * 3600  //  90 d
        case .evergreen:  return 4320 * 3600  // 180 d
        case .seasonal:   return 168 * 3600   //   7 d
        case .archive:    return 8640 * 3600  // 360 d
        }
    }
}

// MARK: - DecayModel

/// Mathematical curve used to compute remaining relevance.
enum RelevanceDecayModel: String, Codable {
    case exponential
    case linear
    case stepFunction
    case logarithmic

    /// Returns a fraction in `[0, 1]` representing how much relevance
    /// remains after `elapsed` seconds given `halfLife`.
    func factor(elapsed: TimeInterval, halfLife: TimeInterval) -> Double {
        guard halfLife > 0, elapsed >= 0 else { return 1.0 }
        let t = elapsed
        switch self {
        case .exponential:
            let lambda = log(2.0) / halfLife
            return exp(-lambda * t)
        case .linear:
            return max(0, 1.0 - t / (2.0 * halfLife))
        case .stepFunction:
            return t < halfLife ? 1.0 : 0.3
        case .logarithmic:
            return 1.0 / (1.0 + log(1.0 + t / halfLife))
        }
    }
}

// MARK: - UrgencyTier

enum UrgencyTier: Int, Codable, Comparable {
    case immediate = 0
    case today     = 1
    case thisWeek  = 2
    case whenever  = 3
    case archived  = 4

    static func < (lhs: UrgencyTier, rhs: UrgencyTier) -> Bool {
        lhs.rawValue < rhs.rawValue
    }

    var label: String {
        switch self {
        case .immediate: return "Read Now"
        case .today:     return "Today"
        case .thisWeek:  return "This Week"
        case .whenever:  return "Whenever"
        case .archived:  return "Archived"
        }
    }

    static func from(relevance: Double, decayRate: Double) -> UrgencyTier {
        // High-decay + still-relevant → immediate
        if relevance > 60 && decayRate > 0.3  { return .immediate }
        if relevance > 40                       { return .today }
        if relevance > 20                       { return .thisWeek }
        if relevance > 5                        { return .whenever }
        return .archived
    }
}

// MARK: - InsightSeverity

enum RelevanceInsightSeverity: String, Codable, Comparable {
    case low      = "low"
    case medium   = "medium"
    case high     = "high"
    case critical = "critical"

    private var order: Int {
        switch self {
        case .low:      return 0
        case .medium:   return 1
        case .high:     return 2
        case .critical: return 3
        }
    }

    static func < (lhs: Self, rhs: Self) -> Bool {
        lhs.order < rhs.order
    }
}

// MARK: - InsightType

enum RelevanceInsightType: String, Codable {
    case urgentReading
    case expiringContent
    case evergreenDiscovery
    case readingWindowClosing
    case topicSaturation
    case optimalReadingOrder
    case staleBatchDetected
    case freshContentSurge
}

// MARK: - HealthTier

enum RelevanceHealthTier: String, Codable {
    case thriving = "Thriving"
    case healthy  = "Healthy"
    case aging    = "Aging"
    case decaying = "Decaying"
    case stale    = "Stale"

    static func from(score: Double) -> RelevanceHealthTier {
        switch score {
        case 80...:       return .thriving
        case 60..<80:     return .healthy
        case 40..<60:     return .aging
        case 20..<40:     return .decaying
        default:          return .stale
        }
    }
}

// MARK: - Models

struct ArticleRelevanceProfile: Codable, Equatable {
    let articleId: String
    let articleTitle: String
    let feedURL: String
    let publishedDate: Date
    var topics: [String]
    var contentType: RelevanceContentType
    var relevanceScore: Double       // 0-100
    var halfLife: TimeInterval
    var decayRate: Double            // fraction lost per hour at assessment time
    var decayModel: RelevanceDecayModel
    var lastAssessed: Date
    var readByUser: Bool
    var userInteractionCount: Int

    static func == (lhs: Self, rhs: Self) -> Bool { lhs.articleId == rhs.articleId }
}

struct QueuePriority: Codable {
    let articleId: String
    let articleTitle: String
    let feedURL: String
    let currentRelevance: Double
    let timeToHalfRelevance: TimeInterval
    let urgencyTier: UrgencyTier
    let recommendedAction: String
}

struct RelevanceFleetHealth: Codable {
    let totalArticles: Int
    let avgRelevance: Double
    let evergreenRatio: Double
    let expiringCount: Int
    let healthScore: Double
    let healthTier: RelevanceHealthTier
}

struct RelevanceInsight: Codable {
    let id: String
    let type: RelevanceInsightType
    let title: String
    let message: String
    let severity: RelevanceInsightSeverity
    let affectedArticles: [String]
    let generatedAt: Date
    let confidence: Double
}

// MARK: - FeedRelevanceDecayEngine

class FeedRelevanceDecayEngine {

    static let shared = FeedRelevanceDecayEngine()

    private var articles: [String: ArticleRelevanceProfile] = [:]
    private let defaults: UserDefaults
    private let dateProvider: () -> Date
    private let calendar: Calendar

    private let articlesKey = "feedRelevanceDecay_articles"

    // MARK: - Init

    init(defaults: UserDefaults = .standard,
         dateProvider: @escaping () -> Date = { Date() },
         calendar: Calendar = .current) {
        self.defaults = defaults
        self.dateProvider = dateProvider
        self.calendar = calendar
        loadState()
    }

    func reset() {
        articles.removeAll()
        defaults.removeObject(forKey: articlesKey)
    }

    // MARK: - Persistence

    private func saveState() {
        if let data = try? JSONEncoder().encode(articles) {
            defaults.set(data, forKey: articlesKey)
        }
    }

    private func loadState() {
        guard let data = defaults.data(forKey: articlesKey),
              let decoded = try? JSONDecoder().decode([String: ArticleRelevanceProfile].self, from: data) else { return }
        articles = decoded
    }

    // MARK: - 1. Content Classifier

    func classifyContent(title: String, topics: [String]) -> RelevanceContentType {
        let combined = (title + " " + topics.joined(separator: " ")).lowercased()

        let rules: [(keywords: [String], type: RelevanceContentType)] = [
            (["breaking", "urgent", "alert", "just in", "developing", "live update"], .breaking),
            (["trending", "viral", "popular", "hot", "buzz"],                          .trending),
            (["how to", "tutorial", "guide", "step by step", "walkthrough", "learn"],  .tutorial),
            (["reference", "documentation", "spec", "rfc", "manual", "api doc"],       .reference),
            (["opinion", "editorial", "commentary", "op-ed", "perspective"],           .opinion),
            (["analysis", "deep dive", "in-depth", "investigation", "research"],       .analysis),
            (["seasonal", "holiday", "christmas", "halloween", "summer", "winter"],    .seasonal),
            (["archive", "retrospective", "classic", "throwback", "history of"],       .archive),
            (["evergreen", "timeless", "fundamentals", "principles", "101"],           .evergreen),
        ]

        for rule in rules {
            for keyword in rule.keywords {
                if combined.contains(keyword) { return rule.type }
            }
        }
        return .analysis  // default
    }

    // MARK: - 2. Decay Calculator

    func calculateRelevance(profile: ArticleRelevanceProfile) -> Double {
        let elapsed = dateProvider().timeIntervalSince(profile.publishedDate)
        let factor = profile.decayModel.factor(elapsed: elapsed, halfLife: profile.halfLife)
        // Interaction bonus: each interaction adds a small bump (up to +10)
        let interactionBonus = min(Double(profile.userInteractionCount) * 2.0, 10.0)
        return min(100, max(0, factor * 100.0 + interactionBonus))
    }

    // MARK: - 3. Half-Life Estimator

    func estimateHalfLife(contentType: RelevanceContentType, topics: [String]) -> TimeInterval {
        var halfLife = contentType.defaultHalfLife
        let topicStr = topics.joined(separator: " ").lowercased()

        // Topic-based adjustments
        if topicStr.contains("security") || topicStr.contains("vulnerability") || topicStr.contains("cve") {
            halfLife *= 0.5   // security items expire faster
        }
        if topicStr.contains("fundamental") || topicStr.contains("principle") || topicStr.contains("concept") {
            halfLife *= 1.5   // conceptual content lasts longer
        }
        if topicStr.contains("release") || topicStr.contains("launch") || topicStr.contains("announcement") {
            halfLife *= 0.7   // announcements are time-sensitive
        }
        return halfLife
    }

    // MARK: - 4. Decay Model Selector

    private func selectDecayModel(contentType: RelevanceContentType) -> RelevanceDecayModel {
        switch contentType {
        case .breaking, .trending:
            return .exponential
        case .seasonal:
            return .stepFunction
        case .evergreen, .reference, .archive:
            return .logarithmic
        case .analysis, .opinion, .tutorial:
            return .linear
        }
    }

    // MARK: - Public API

    @discardableResult
    func trackArticle(articleId: String, title: String, feedURL: String,
                      publishedDate: Date, topics: [String] = []) -> ArticleRelevanceProfile {
        let contentType = classifyContent(title: title, topics: topics)
        let halfLife = estimateHalfLife(contentType: contentType, topics: topics)
        let decayModel = selectDecayModel(contentType: contentType)
        let elapsed = dateProvider().timeIntervalSince(publishedDate)
        let factor = decayModel.factor(elapsed: elapsed, halfLife: halfLife)

        let profile = ArticleRelevanceProfile(
            articleId: articleId,
            articleTitle: title,
            feedURL: feedURL,
            publishedDate: publishedDate,
            topics: topics,
            contentType: contentType,
            relevanceScore: factor * 100.0,
            halfLife: halfLife,
            decayRate: computeDecayRate(elapsed: elapsed, halfLife: halfLife, model: decayModel),
            decayModel: decayModel,
            lastAssessed: dateProvider(),
            readByUser: false,
            userInteractionCount: 0
        )
        articles[articleId] = profile
        saveState()
        NotificationCenter.default.post(name: .relevanceDecayDidChange, object: self)
        return profile
    }

    func markRead(articleId: String) {
        guard var profile = articles[articleId] else { return }
        profile.readByUser = true
        articles[articleId] = profile
        saveState()
    }

    func recordInteraction(articleId: String) {
        guard var profile = articles[articleId] else { return }
        profile.userInteractionCount += 1
        articles[articleId] = profile
        saveState()
    }

    // MARK: - 5. Urgency Ranker + Queue Optimizer

    func assessRelevance(articleId: String) -> Double {
        guard let profile = articles[articleId] else { return 0 }
        return calculateRelevance(profile: profile)
    }

    func generateQueue(limit: Int = 20) -> [QueuePriority] {
        let now = dateProvider()
        var ranked: [(profile: ArticleRelevanceProfile, relevance: Double, decay: Double)] = []

        for (_, profile) in articles where !profile.readByUser {
            let relevance = calculateRelevance(profile: profile)
            guard relevance > 1 else { continue }
            let elapsed = now.timeIntervalSince(profile.publishedDate)
            let decay = computeDecayRate(elapsed: elapsed, halfLife: profile.halfLife, model: profile.decayModel)
            ranked.append((profile, relevance, decay))
        }

        // Sort by urgency: highest decay-rate articles with remaining relevance first
        ranked.sort { a, b in
            let urgA = a.relevance * a.decay
            let urgB = b.relevance * b.decay
            if urgA != urgB { return urgA > urgB }
            return a.relevance > b.relevance
        }

        let capped = Array(ranked.prefix(limit))
        return capped.map { item in
            let tier = UrgencyTier.from(relevance: item.relevance, decayRate: item.decay)
            let ttHalf = estimateTimeToHalfRelevance(currentRelevance: item.relevance,
                                                      halfLife: item.profile.halfLife,
                                                      model: item.profile.decayModel,
                                                      elapsed: now.timeIntervalSince(item.profile.publishedDate))
            let action: String
            switch tier {
            case .immediate: action = "Read immediately — relevance dropping fast"
            case .today:     action = "Read today for best value"
            case .thisWeek:  action = "Schedule for this week"
            case .whenever:  action = "Low urgency — read when convenient"
            case .archived:  action = "Content has mostly expired"
            }
            return QueuePriority(
                articleId: item.profile.articleId,
                articleTitle: item.profile.articleTitle,
                feedURL: item.profile.feedURL,
                currentRelevance: item.relevance,
                timeToHalfRelevance: ttHalf,
                urgencyTier: tier,
                recommendedAction: action
            )
        }
    }

    // MARK: - 6. Fleet Health Scorer

    func getFleetHealth() -> RelevanceFleetHealth {
        let now = dateProvider()
        let total = articles.count
        guard total > 0 else {
            return RelevanceFleetHealth(totalArticles: 0, avgRelevance: 0,
                                        evergreenRatio: 0, expiringCount: 0,
                                        healthScore: 0, healthTier: .stale)
        }

        var sumRelevance = 0.0
        var evergreenCount = 0
        var expiringCount = 0

        for (_, profile) in articles {
            let rel = calculateRelevance(profile: profile)
            sumRelevance += rel

            if profile.contentType == .evergreen || profile.contentType == .reference || profile.contentType == .archive {
                evergreenCount += 1
            }

            // Expiring = unread + relevance dropping below 30 within 24h
            if !profile.readByUser && rel > 5 && rel < 30 {
                expiringCount += 1
            }
        }

        let avgRelevance = sumRelevance / Double(total)
        let evergreenRatio = Double(evergreenCount) / Double(total)

        // Composite score: weighted average of avg relevance, evergreen ratio, and freshness
        let freshnessBonus = min(avgRelevance / 100.0, 1.0) * 30
        let evergreenBonus = evergreenRatio * 30
        let expiringPenalty = min(Double(expiringCount) / Double(total) * 40, 40)
        let score = min(100, max(0, avgRelevance * 0.4 + freshnessBonus + evergreenBonus - expiringPenalty))

        return RelevanceFleetHealth(
            totalArticles: total,
            avgRelevance: avgRelevance,
            evergreenRatio: evergreenRatio,
            expiringCount: expiringCount,
            healthScore: score,
            healthTier: RelevanceHealthTier.from(score: score)
        )
    }

    // MARK: - 7. Insight Generator

    func generateInsights() -> [RelevanceInsight] {
        let now = dateProvider()
        var insights: [RelevanceInsight] = []

        // Urgent reading: unread articles with high decay rate and good relevance
        let urgent = articles.values.filter { !$0.readByUser }
            .filter { profile in
                let rel = calculateRelevance(profile: profile)
                let elapsed = now.timeIntervalSince(profile.publishedDate)
                let decay = computeDecayRate(elapsed: elapsed, halfLife: profile.halfLife, model: profile.decayModel)
                return rel > 50 && decay > 0.4
            }
        if !urgent.isEmpty {
            insights.append(RelevanceInsight(
                id: UUID().uuidString, type: .urgentReading,
                title: "Urgent Reading Required",
                message: "\(urgent.count) article(s) with high relevance are decaying rapidly — read soon or lose value",
                severity: urgent.count > 3 ? .critical : .high,
                affectedArticles: urgent.map { $0.articleId },
                generatedAt: now, confidence: 0.9
            ))
        }

        // Expiring content: relevance between 5 and 25, unread
        let expiring = articles.values.filter { !$0.readByUser }
            .filter { calculateRelevance(profile: $0) > 5 && calculateRelevance(profile: $0) < 25 }
        if !expiring.isEmpty {
            insights.append(RelevanceInsight(
                id: UUID().uuidString, type: .expiringContent,
                title: "Content Expiring Soon",
                message: "\(expiring.count) article(s) are almost past their useful life",
                severity: .medium,
                affectedArticles: expiring.map { $0.articleId },
                generatedAt: now, confidence: 0.85
            ))
        }

        // Evergreen discovery: high-stability content with good remaining relevance
        let eg = articles.values.filter {
            ($0.contentType == .evergreen || $0.contentType == .reference || $0.contentType == .tutorial)
            && calculateRelevance(profile: $0) > 70
        }
        if !eg.isEmpty {
            insights.append(RelevanceInsight(
                id: UUID().uuidString, type: .evergreenDiscovery,
                title: "Evergreen Content Available",
                message: "\(eg.count) timeless article(s) remain highly relevant — great for deep learning",
                severity: .low,
                affectedArticles: eg.map { $0.articleId },
                generatedAt: now, confidence: 0.8
            ))
        }

        // Stale batch: more than 60% of articles below 10 relevance
        let staleCount = articles.values.filter { calculateRelevance(profile: $0) < 10 }.count
        if articles.count > 0 && Double(staleCount) / Double(articles.count) > 0.6 {
            insights.append(RelevanceInsight(
                id: UUID().uuidString, type: .staleBatchDetected,
                title: "Stale Content Accumulating",
                message: "\(staleCount) of \(articles.count) articles are stale — consider archiving",
                severity: .high,
                affectedArticles: articles.values.filter { calculateRelevance(profile: $0) < 10 }.map { $0.articleId },
                generatedAt: now, confidence: 0.9
            ))
        }

        // Fresh content surge: many articles published in last 2 hours
        let recentCount = articles.values.filter {
            now.timeIntervalSince($0.publishedDate) < 7200
        }.count
        if recentCount > 5 {
            insights.append(RelevanceInsight(
                id: UUID().uuidString, type: .freshContentSurge,
                title: "Fresh Content Surge",
                message: "\(recentCount) articles published in the last 2 hours — prioritise by decay rate",
                severity: .medium,
                affectedArticles: articles.values.filter { now.timeIntervalSince($0.publishedDate) < 7200 }.map { $0.articleId },
                generatedAt: now, confidence: 0.85
            ))
        }

        // Reading window closing: articles with relevance 25-50 and high decay
        let closing = articles.values.filter { !$0.readByUser }
            .filter { profile in
                let rel = calculateRelevance(profile: profile)
                let elapsed = now.timeIntervalSince(profile.publishedDate)
                let decay = computeDecayRate(elapsed: elapsed, halfLife: profile.halfLife, model: profile.decayModel)
                return rel >= 25 && rel <= 50 && decay > 0.2
            }
        if !closing.isEmpty {
            insights.append(RelevanceInsight(
                id: UUID().uuidString, type: .readingWindowClosing,
                title: "Reading Window Closing",
                message: "\(closing.count) article(s) are in the last useful window — read now or skip",
                severity: .medium,
                affectedArticles: closing.map { $0.articleId },
                generatedAt: now, confidence: 0.8
            ))
        }

        // Topic saturation: single topic dominating unread queue
        let topicCounts = articles.values.filter { !$0.readByUser }
            .flatMap { $0.topics }
            .reduce(into: [String: Int]()) { $0[$1, default: 0] += 1 }
        let unreadCount = articles.values.filter { !$0.readByUser }.count
        if let (topTopic, topCount) = topicCounts.max(by: { $0.value < $1.value }),
           unreadCount > 3, Double(topCount) / Double(unreadCount) > 0.6 {
            insights.append(RelevanceInsight(
                id: UUID().uuidString, type: .topicSaturation,
                title: "Topic Saturation: \(topTopic)",
                message: "\(topCount) of \(unreadCount) unread articles are about '\(topTopic)' — consider diversifying",
                severity: .low,
                affectedArticles: articles.values.filter { !$0.readByUser && $0.topics.contains(topTopic) }.map { $0.articleId },
                generatedAt: now, confidence: 0.75
            ))
        }

        return insights.sorted { $0.severity > $1.severity }
    }

    // MARK: - Filters

    func getExpiringArticles(withinHours: Double = 24) -> [ArticleRelevanceProfile] {
        return articles.values.filter { profile in
            guard !profile.readByUser else { return false }
            let currentRel = calculateRelevance(profile: profile)
            guard currentRel > 5 else { return false }

            // Simulate future relevance
            let futureElapsed = dateProvider().timeIntervalSince(profile.publishedDate) + withinHours * 3600
            let futureFactor = profile.decayModel.factor(elapsed: futureElapsed, halfLife: profile.halfLife)
            let futureRel = futureFactor * 100.0
            return futureRel < 20 && currentRel >= 20
        }.sorted { calculateRelevance(profile: $0) > calculateRelevance(profile: $1) }
    }

    func getEvergreenArticles() -> [ArticleRelevanceProfile] {
        return articles.values.filter { profile in
            let rel = calculateRelevance(profile: profile)
            return rel > 50 && (profile.contentType == .evergreen || profile.contentType == .reference ||
                                profile.contentType == .tutorial || profile.contentType == .archive)
        }.sorted { calculateRelevance(profile: $0) > calculateRelevance(profile: $1) }
    }

    // MARK: - Full Analysis

    func fullAnalysis() -> (queue: [QueuePriority], health: RelevanceFleetHealth, insights: [RelevanceInsight]) {
        return (generateQueue(), getFleetHealth(), generateInsights())
    }

    // MARK: - Internal Helpers

    /// Instantaneous fractional decay rate (fraction lost per hour).
    private func computeDecayRate(elapsed: TimeInterval, halfLife: TimeInterval,
                                  model: RelevanceDecayModel) -> Double {
        guard halfLife > 0 else { return 0 }
        let dt: TimeInterval = 3600  // 1 hour
        let now = model.factor(elapsed: elapsed, halfLife: halfLife)
        let later = model.factor(elapsed: elapsed + dt, halfLife: halfLife)
        guard now > 0 else { return 0 }
        return max(0, (now - later) / now)
    }

    /// Estimate how many seconds until relevance halves from its current value.
    private func estimateTimeToHalfRelevance(currentRelevance: Double, halfLife: TimeInterval,
                                              model: RelevanceDecayModel, elapsed: TimeInterval) -> TimeInterval {
        guard currentRelevance > 1 else { return 0 }
        let target = currentRelevance / 2.0 / 100.0  // as fraction
        // Binary search for time to reach target
        var lo: TimeInterval = 0
        var hi: TimeInterval = halfLife * 10
        for _ in 0..<50 {
            let mid = (lo + hi) / 2.0
            let val = model.factor(elapsed: elapsed + mid, halfLife: halfLife)
            if val > target {
                lo = mid
            } else {
                hi = mid
            }
        }
        return (lo + hi) / 2.0
    }

    // MARK: - Accessors (for testing)

    var articleCount: Int { articles.count }

    func getProfile(articleId: String) -> ArticleRelevanceProfile? {
        return articles[articleId]
    }

    var allProfiles: [ArticleRelevanceProfile] {
        Array(articles.values)
    }
}
