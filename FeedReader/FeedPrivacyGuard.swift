//
//  FeedPrivacyGuard.swift
//  FeedReader
//
//  Analyzes feed articles for privacy-invasive elements: tracking pixels,
//  external analytics scripts, fingerprinting attempts, and data-harvesting
//  patterns. Provides per-feed and per-article privacy scores, flags risky
//  content, and generates privacy reports.
//
//  Fully offline — pattern matching only, no network calls.
//

import Foundation

// MARK: - Notification

extension Notification.Name {
    /// Posted when privacy scan results are updated.
    static let privacyScanDidUpdate = Notification.Name("PrivacyScanDidUpdateNotification")
}

// MARK: - PrivacyThreatCategory

/// Categories of privacy threats detected in article content.
enum PrivacyThreatCategory: String, Codable, CaseIterable {
    case trackingPixel      // 1x1 or tiny invisible images
    case analyticsScript    // Known analytics/tracking JS
    case fingerprinting     // Browser/device fingerprinting attempts
    case externalBeacon     // Beacon/ping endpoints
    case hiddenForm         // Hidden form fields that auto-submit
    case crossSiteTracker   // Known cross-site tracking domains
    case emailTracker       // Email open-tracking patterns
    case adNetwork          // Ad network resources

    /// Human-readable label.
    var label: String {
        switch self {
        case .trackingPixel:    return "Tracking Pixel"
        case .analyticsScript:  return "Analytics Script"
        case .fingerprinting:   return "Fingerprinting"
        case .externalBeacon:   return "Beacon/Ping"
        case .hiddenForm:       return "Hidden Form"
        case .crossSiteTracker: return "Cross-Site Tracker"
        case .emailTracker:     return "Email Tracker"
        case .adNetwork:        return "Ad Network"
        }
    }

    /// Severity weight (higher = more invasive).
    var severity: Double {
        switch self {
        case .fingerprinting:   return 1.0
        case .crossSiteTracker: return 0.9
        case .hiddenForm:       return 0.85
        case .analyticsScript:  return 0.7
        case .externalBeacon:   return 0.65
        case .emailTracker:     return 0.6
        case .adNetwork:        return 0.5
        case .trackingPixel:    return 0.4
        }
    }
}

// MARK: - PrivacySeverity

/// Overall severity rating for a privacy concern.
enum PrivacySeverity: String, Codable, Comparable {
    case low
    case medium
    case high
    case critical

    static func < (lhs: PrivacySeverity, rhs: PrivacySeverity) -> Bool {
        let order: [PrivacySeverity] = [.low, .medium, .high, .critical]
        return (order.firstIndex(of: lhs) ?? 0) < (order.firstIndex(of: rhs) ?? 0)
    }

    /// Map a 0-1 threat score to severity.
    static func from(score: Double) -> PrivacySeverity {
        switch score {
        case ..<0.2:  return .low
        case ..<0.5:  return .medium
        case ..<0.8:  return .high
        default:      return .critical
        }
    }
}

// MARK: - PrivacyThreat

/// A single detected privacy threat in article content.
struct PrivacyThreat: Codable, Equatable {
    /// Unique identifier.
    let id: String
    /// The category of threat.
    let category: PrivacyThreatCategory
    /// Human-readable description of what was found.
    let description: String
    /// The matched pattern or domain.
    let evidence: String
    /// Severity of this specific threat.
    let severity: PrivacySeverity
    /// Line or position hint (for debugging).
    let location: String?

    static func == (lhs: PrivacyThreat, rhs: PrivacyThreat) -> Bool {
        return lhs.id == rhs.id
    }
}

// MARK: - ArticlePrivacyScan

/// Privacy scan results for a single article.
struct ArticlePrivacyScan: Codable, Equatable {
    /// Article URL (link).
    let articleURL: String
    /// Article title.
    let articleTitle: String
    /// Feed name.
    let feedName: String
    /// Scan timestamp.
    let scannedAt: Date
    /// All detected threats.
    let threats: [PrivacyThreat]
    /// Privacy score (0 = very invasive, 100 = clean).
    let privacyScore: Int
    /// Overall severity.
    let severity: PrivacySeverity
    /// Number of external domains referenced.
    let externalDomainCount: Int
    /// List of external domains found.
    let externalDomains: [String]

    /// Whether the article is considered clean (no significant threats).
    var isClean: Bool { threats.isEmpty }

    /// Count of threats by category.
    var threatsByCategory: [PrivacyThreatCategory: Int] {
        var counts: [PrivacyThreatCategory: Int] = [:]
        for t in threats {
            counts[t.category, default: 0] += 1
        }
        return counts
    }

    static func == (lhs: ArticlePrivacyScan, rhs: ArticlePrivacyScan) -> Bool {
        return lhs.articleURL == rhs.articleURL && lhs.scannedAt == rhs.scannedAt
    }
}

// MARK: - FeedPrivacyProfile

/// Aggregated privacy profile for a feed.
struct FeedPrivacyProfile: Codable, Equatable {
    /// Feed name.
    let feedName: String
    /// Feed URL.
    let feedURL: String
    /// Average privacy score across articles (0-100).
    let averageScore: Int
    /// Overall severity.
    let severity: PrivacySeverity
    /// Letter grade (A+ through F).
    let grade: String
    /// Total articles scanned.
    let articlesScanned: Int
    /// Number of clean articles.
    let cleanArticles: Int
    /// Most common threat categories.
    let topThreats: [(category: PrivacyThreatCategory, count: Int)]
    /// Total unique external domains across all articles.
    let uniqueExternalDomains: Int
    /// Top external domains by frequency.
    let topExternalDomains: [(domain: String, count: Int)]
    /// Recommendation text.
    let recommendation: String
    /// Profile generation timestamp.
    let generatedAt: Date

    /// Percentage of articles that are clean.
    var cleanPercentage: Double {
        guard articlesScanned > 0 else { return 100.0 }
        return Double(cleanArticles) / Double(articlesScanned) * 100.0
    }

    // Custom Equatable (tuples aren't auto-Equatable).
    static func == (lhs: FeedPrivacyProfile, rhs: FeedPrivacyProfile) -> Bool {
        return lhs.feedName == rhs.feedName
            && lhs.feedURL == rhs.feedURL
            && lhs.averageScore == rhs.averageScore
            && lhs.articlesScanned == rhs.articlesScanned
    }

    // Custom Codable (tuples aren't auto-Codable).
    enum CodingKeys: String, CodingKey {
        case feedName, feedURL, averageScore, severity, grade
        case articlesScanned, cleanArticles
        case topThreatsData, uniqueExternalDomains, topDomainsData
        case recommendation, generatedAt
    }

    struct ThreatCount: Codable {
        let category: PrivacyThreatCategory
        let count: Int
    }

    struct DomainCount: Codable {
        let domain: String
        let count: Int
    }

    init(feedName: String, feedURL: String, averageScore: Int,
         severity: PrivacySeverity, grade: String, articlesScanned: Int,
         cleanArticles: Int,
         topThreats: [(category: PrivacyThreatCategory, count: Int)],
         uniqueExternalDomains: Int,
         topExternalDomains: [(domain: String, count: Int)],
         recommendation: String, generatedAt: Date) {
        self.feedName = feedName
        self.feedURL = feedURL
        self.averageScore = averageScore
        self.severity = severity
        self.grade = grade
        self.articlesScanned = articlesScanned
        self.cleanArticles = cleanArticles
        self.topThreats = topThreats
        self.uniqueExternalDomains = uniqueExternalDomains
        self.topExternalDomains = topExternalDomains
        self.recommendation = recommendation
        self.generatedAt = generatedAt
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(feedName, forKey: .feedName)
        try c.encode(feedURL, forKey: .feedURL)
        try c.encode(averageScore, forKey: .averageScore)
        try c.encode(severity, forKey: .severity)
        try c.encode(grade, forKey: .grade)
        try c.encode(articlesScanned, forKey: .articlesScanned)
        try c.encode(cleanArticles, forKey: .cleanArticles)
        try c.encode(topThreats.map { ThreatCount(category: $0.category, count: $0.count) }, forKey: .topThreatsData)
        try c.encode(uniqueExternalDomains, forKey: .uniqueExternalDomains)
        try c.encode(topExternalDomains.map { DomainCount(domain: $0.domain, count: $0.count) }, forKey: .topDomainsData)
        try c.encode(recommendation, forKey: .recommendation)
        try c.encode(generatedAt, forKey: .generatedAt)
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        feedName = try c.decode(String.self, forKey: .feedName)
        feedURL = try c.decode(String.self, forKey: .feedURL)
        averageScore = try c.decode(Int.self, forKey: .averageScore)
        severity = try c.decode(PrivacySeverity.self, forKey: .severity)
        grade = try c.decode(String.self, forKey: .grade)
        articlesScanned = try c.decode(Int.self, forKey: .articlesScanned)
        cleanArticles = try c.decode(Int.self, forKey: .cleanArticles)
        let td = try c.decode([ThreatCount].self, forKey: .topThreatsData)
        topThreats = td.map { ($0.category, $0.count) }
        uniqueExternalDomains = try c.decode(Int.self, forKey: .uniqueExternalDomains)
        let dd = try c.decode([DomainCount].self, forKey: .topDomainsData)
        topExternalDomains = dd.map { ($0.domain, $0.count) }
        recommendation = try c.decode(String.self, forKey: .recommendation)
        generatedAt = try c.decode(Date.self, forKey: .generatedAt)
    }
}

// MARK: - PrivacyReport

/// Fleet-wide privacy report across all feeds.
struct PrivacyReport {
    /// Total feeds analyzed.
    let totalFeeds: Int
    /// Total articles scanned.
    let totalArticles: Int
    /// Overall privacy score (0-100).
    let overallScore: Int
    /// Overall severity.
    let overallSeverity: PrivacySeverity
    /// Feeds ranked by privacy score (worst first).
    let feedRankings: [(feedName: String, score: Int, grade: String)]
    /// Global threat distribution.
    let threatDistribution: [PrivacyThreatCategory: Int]
    /// Most privacy-invasive domains across all feeds.
    let worstDomains: [(domain: String, feedCount: Int, totalHits: Int)]
    /// Percentage of clean articles across all feeds.
    let cleanPercentage: Double
    /// Actionable summary.
    let summary: String

    /// Text report.
    func textReport() -> String {
        var lines = [String]()
        lines.append("═══ Feed Privacy Report ═══")
        lines.append("")
        lines.append("Overall Score: \(overallScore)/100 (\(overallSeverity.rawValue.uppercased()))")
        lines.append("Feeds Analyzed: \(totalFeeds)")
        lines.append("Articles Scanned: \(totalArticles)")
        lines.append("Clean Articles: \(String(format: "%.1f", cleanPercentage))%")
        lines.append("")

        if !feedRankings.isEmpty {
            lines.append("── Feed Rankings (worst → best) ──")
            for (i, r) in feedRankings.prefix(10).enumerated() {
                lines.append("  \(i + 1). [\(r.grade)] \(r.feedName) — \(r.score)/100")
            }
            lines.append("")
        }

        if !threatDistribution.isEmpty {
            lines.append("── Threat Distribution ──")
            let sorted = threatDistribution.sorted { $0.value > $1.value }
            for (cat, count) in sorted {
                lines.append("  \(cat.label): \(count)")
            }
            lines.append("")
        }

        if !worstDomains.isEmpty {
            lines.append("── Most Tracked Domains ──")
            for d in worstDomains.prefix(10) {
                lines.append("  \(d.domain) — \(d.totalHits) hits across \(d.feedCount) feeds")
            }
            lines.append("")
        }

        lines.append(summary)
        return lines.joined(separator: "\n")
    }
}

// MARK: - FeedPrivacyGuard

/// Scans article content for privacy-invasive elements and scores feeds
/// by their tracking/fingerprinting behavior.
///
/// Usage:
/// ```swift
/// let guard = FeedPrivacyGuard()
///
/// // Scan a single article
/// let scan = guard.scanArticle(title: "News",
///                              body: htmlContent,
///                              link: "https://example.com/article",
///                              feedName: "Example Feed")
/// print("Privacy score: \(scan.privacyScore)/100")
/// print("Threats: \(scan.threats.count)")
///
/// // Get feed profile
/// let profile = guard.feedProfile(feedName: "Example Feed",
///                                 feedURL: "https://example.com/feed")
/// print("Grade: \(profile.grade)")
///
/// // Generate fleet-wide report
/// let report = guard.generateReport()
/// print(report.textReport())
/// ```
class FeedPrivacyGuard {

    // MARK: - Known Tracker Domains

    /// Known tracking/analytics domains (partial match).
    static let trackerDomains: Set<String> = [
        // Analytics
        "google-analytics.com", "googletagmanager.com",
        "analytics.google.com", "stats.g.doubleclick.net",
        "hotjar.com", "mixpanel.com", "segment.com",
        "amplitude.com", "heap.io", "heapanalytics.com",
        "plausible.io", "matomo.org", "piwik.org",
        "chartbeat.com", "parsely.com", "comscore.com",
        "quantserve.com", "scorecardresearch.com",
        "newrelic.com", "nr-data.net",
        "fullstory.com", "mouseflow.com",
        "crazyegg.com", "clicktale.com",
        "optimizely.com", "abtasty.com",

        // Ad networks
        "doubleclick.net", "googlesyndication.com",
        "googleadservices.com", "adnxs.com",
        "adsrvr.org", "criteo.com", "criteo.net",
        "taboola.com", "outbrain.com",
        "facebook.net", "fbcdn.net",
        "amazon-adsystem.com",

        // Cross-site trackers
        "facebook.com/tr", "connect.facebook.net",
        "platform.twitter.com", "syndication.twitter.com",
        "snap.licdn.com", "linkedin.com/px",
        "bat.bing.com", "clarity.ms",

        // Email tracking
        "list-manage.com", "mailchimp.com",
        "sendgrid.net", "sparkpost.com",
        "returnpath.net", "litmus.com",

        // Fingerprinting
        "fingerprintjs.com", "fpjs.io",
        "deviceid.io",
    ]

    // MARK: - Unified Pattern Rules

    /// A single detection rule: regex pattern, human label, threat category, and severity.
    struct DetectionRule {
        let pattern: String
        let label: String
        let category: PrivacyThreatCategory
        let severity: PrivacySeverity
    }

    /// All regex-based detection rules, checked in a single pass by `scanArticle`.
    static let detectionRules: [DetectionRule] = {
        var rules = [DetectionRule]()

        // Tracking pixel rules
        let pixelPatterns: [(String, String)] = [
            ("width=\"1\".*height=\"1\"", "1x1 tracking pixel"),
            ("width='1'.*height='1'", "1x1 tracking pixel"),
            ("width:1px.*height:1px", "1x1 CSS tracking pixel"),
            ("width:0.*height:0", "Zero-size tracking element"),
            ("display:\\s*none.*<img", "Hidden image tracker"),
            ("visibility:\\s*hidden.*<img", "Invisible image tracker"),
            ("style=\"[^\"]*position:\\s*absolute[^\"]*left:\\s*-\\d+", "Off-screen positioned tracker"),
        ]
        for (p, l) in pixelPatterns {
            rules.append(DetectionRule(pattern: p, label: l, category: .trackingPixel, severity: .low))
        }

        // Fingerprinting rules
        let fpPatterns: [(String, String)] = [
            ("canvas\\.toDataURL", "Canvas fingerprinting"),
            ("getImageData", "Canvas data extraction"),
            ("webgl.*getParameter", "WebGL fingerprinting"),
            ("AudioContext.*createOscillator", "Audio fingerprinting"),
            ("navigator\\.plugins", "Plugin enumeration"),
            ("navigator\\.languages", "Language fingerprinting"),
            ("screen\\.colorDepth", "Screen fingerprinting"),
            ("navigator\\.hardwareConcurrency", "Hardware fingerprinting"),
            ("navigator\\.deviceMemory", "Device memory detection"),
            ("getBattery", "Battery API fingerprinting"),
        ]
        for (p, l) in fpPatterns {
            rules.append(DetectionRule(pattern: p, label: l, category: .fingerprinting, severity: .high))
        }

        // Beacon/ping rules
        let beaconPatterns: [(String, String)] = [
            ("navigator\\.sendBeacon", "Beacon API tracking"),
            ("new\\s+Image\\(\\)\\.src\\s*=", "Image beacon"),
            ("<img[^>]+src=[\"'][^\"']*\\?(utm_|_ga|fbclid|mc_)", "Tracking query parameter beacon"),
            ("ping=\"", "Link ping attribute"),
        ]
        for (p, l) in beaconPatterns {
            rules.append(DetectionRule(pattern: p, label: l, category: .externalBeacon, severity: .medium))
        }

        // Email tracking rules
        let emailPatterns: [(String, String)] = [
            ("open\\.gif\\?", "Email open tracking pattern"),
            ("track\\.gif\\?", "Email open tracking pattern"),
            ("pixel\\.gif\\?", "Email open tracking pattern"),
            ("beacon\\.gif\\?", "Email open tracking pattern"),
            ("t\\.gif\\?", "Email open tracking pattern"),
            ("o\\.gif\\?", "Email open tracking pattern"),
            ("/track/open", "Email open tracking pattern"),
            ("/tracking/pixel", "Email open tracking pattern"),
            ("/email/open", "Email open tracking pattern"),
        ]
        for (p, l) in emailPatterns {
            rules.append(DetectionRule(pattern: p, label: l, category: .emailTracker, severity: .medium))
        }

        return rules
    }()

    // MARK: - Properties

    /// Cached scan results by article URL.
    private var scanCache: [String: ArticlePrivacyScan] = [:]

    /// Persistence store.
    private let store = UserDefaultsCodableStore<[String: ArticlePrivacyScanData]>(
        key: "feed_privacy_scans",
        dateStrategy: .iso8601
    )

    /// Maximum cached scans (prevents unbounded memory growth).
    private let maxCacheSize = 500

    // MARK: - Codable wrapper (ArticlePrivacyScan has tuple properties)

    struct ArticlePrivacyScanData: Codable {
        let articleURL: String
        let articleTitle: String
        let feedName: String
        let scannedAt: Date
        let threats: [PrivacyThreat]
        let privacyScore: Int
        let severity: PrivacySeverity
        let externalDomainCount: Int
        let externalDomains: [String]

        init(from scan: ArticlePrivacyScan) {
            self.articleURL = scan.articleURL
            self.articleTitle = scan.articleTitle
            self.feedName = scan.feedName
            self.scannedAt = scan.scannedAt
            self.threats = scan.threats
            self.privacyScore = scan.privacyScore
            self.severity = scan.severity
            self.externalDomainCount = scan.externalDomainCount
            self.externalDomains = scan.externalDomains
        }

        func toScan() -> ArticlePrivacyScan {
            return ArticlePrivacyScan(
                articleURL: articleURL,
                articleTitle: articleTitle,
                feedName: feedName,
                scannedAt: scannedAt,
                threats: threats,
                privacyScore: privacyScore,
                severity: severity,
                externalDomainCount: externalDomainCount,
                externalDomains: externalDomains
            )
        }
    }

    // MARK: - Init

    init() {
        loadScans()
    }

    // MARK: - Public API

    /// Scan a single article for privacy threats.
    ///
    /// - Parameters:
    ///   - title: Article title.
    ///   - body: Article HTML/text content.
    ///   - link: Article URL.
    ///   - feedName: Name of the source feed.
    ///   - now: Current timestamp (injectable for testing).
    /// - Returns: Scan result with detected threats and score.
    @discardableResult
    func scanArticle(title: String, body: String, link: String,
                     feedName: String, now: Date = Date()) -> ArticlePrivacyScan {
        var threats = [PrivacyThreat]()
        let lowered = body.lowercased()

        // 1. Run all regex-based detection rules in one pass
        var matchedEmailTracker = false
        for rule in Self.detectionRules {
            // Email tracker: only report the first match (one is enough).
            if rule.category == .emailTracker && matchedEmailTracker { continue }

            if let range = lowered.range(of: rule.pattern, options: .regularExpression) {
                let evidence = (rule.category == .trackingPixel)
                    ? String(lowered[range].prefix(80))
                    : rule.pattern
                threats.append(PrivacyThreat(
                    id: UUID().uuidString,
                    category: rule.category,
                    description: rule.label,
                    evidence: evidence,
                    severity: rule.severity,
                    location: nil
                ))
                if rule.category == .emailTracker { matchedEmailTracker = true }
            }
        }

        // 2. Check for known tracker domains
        let domains = extractDomains(from: body)
        for domain in domains {
            let lowDomain = domain.lowercased()
            for tracker in Self.trackerDomains {
                if lowDomain.contains(tracker) {
                    let category = categorizeTrackerDomain(tracker)
                    threats.append(PrivacyThreat(
                        id: UUID().uuidString,
                        category: category,
                        description: "Known tracker: \(tracker)",
                        evidence: domain,
                        severity: category == .crossSiteTracker ? .high : .medium,
                        location: nil
                    ))
                    break  // One match per domain
                }
            }
        }

        // 3. Check for hidden forms (requires structural match, not simple pattern)
        if lowered.contains("<input") && lowered.contains("type=\"hidden\"") {
            if lowered.range(of: "<form[^>]*>.*<input[^>]*type=\"hidden\"", options: .regularExpression) != nil {
                threats.append(PrivacyThreat(
                    id: UUID().uuidString,
                    category: .hiddenForm,
                    description: "Hidden form with concealed input fields",
                    evidence: "hidden form fields detected",
                    severity: .high,
                    location: nil
                ))
            }
        }

        // Deduplicate by category + evidence
        var seen = Set<String>()
        threats = threats.filter { t in
            let key = "\(t.category.rawValue)|\(t.evidence)"
            if seen.contains(key) { return false }
            seen.insert(key)
            return true
        }

        // Calculate privacy score
        let score = calculatePrivacyScore(threats: threats, externalDomains: domains)
        let severity = PrivacySeverity.from(score: 1.0 - Double(score) / 100.0)

        let scan = ArticlePrivacyScan(
            articleURL: link,
            articleTitle: title,
            feedName: feedName,
            scannedAt: now,
            threats: threats,
            privacyScore: score,
            severity: severity,
            externalDomainCount: domains.count,
            externalDomains: Array(domains.sorted().prefix(20))
        )

        // Cache the result
        scanCache[link] = scan
        trimCacheIfNeeded()
        saveScans()
        NotificationCenter.default.post(name: .privacyScanDidUpdate, object: self)

        return scan
    }

    /// Get a cached scan for an article, if available.
    func cachedScan(for articleURL: String) -> ArticlePrivacyScan? {
        return scanCache[articleURL]
    }

    /// Get all scans for a specific feed.
    func scans(for feedName: String) -> [ArticlePrivacyScan] {
        return scanCache.values.filter { $0.feedName == feedName }
    }

    /// Get all cached scans.
    func allScans() -> [ArticlePrivacyScan] {
        return Array(scanCache.values).sorted { $0.scannedAt > $1.scannedAt }
    }

    // MARK: - Shared Aggregation

    /// Aggregated threat and domain statistics from a set of scans.
    private struct ScanAggregation {
        let averageScore: Int
        let cleanCount: Int
        let threatCounts: [PrivacyThreatCategory: Int]
        let domainCounts: [String: Int]

        /// Top threat categories by frequency.
        func topThreats(_ limit: Int = 5) -> [(category: PrivacyThreatCategory, count: Int)] {
            threatCounts.sorted { $0.value > $1.value }
                .prefix(limit).map { ($0.key, $0.value) }
        }

        /// Top external domains by frequency.
        func topDomains(_ limit: Int = 10) -> [(domain: String, count: Int)] {
            domainCounts.sorted { $0.value > $1.value }
                .prefix(limit).map { ($0.key, $0.value) }
        }

        /// Number of unique external domains.
        var uniqueDomainCount: Int { domainCounts.count }

        /// Percentage of clean (no-threat) scans.
        func cleanPercentage(of total: Int) -> Double {
            guard total > 0 else { return 100.0 }
            return Double(cleanCount) / Double(total) * 100.0
        }
    }

    /// Aggregate threat counts, domain counts, average score, and clean count
    /// from a collection of scans. Shared by `feedProfile` and `generateReport`.
    private func aggregate(_ scans: [ArticlePrivacyScan]) -> ScanAggregation {
        var threatCounts: [PrivacyThreatCategory: Int] = [:]
        var domainCounts: [String: Int] = [:]
        var totalScore = 0
        var cleanCount = 0
        for scan in scans {
            totalScore += scan.privacyScore
            if scan.isClean { cleanCount += 1 }
            for threat in scan.threats {
                threatCounts[threat.category, default: 0] += 1
            }
            for domain in scan.externalDomains {
                domainCounts[domain, default: 0] += 1
            }
        }
        let avg = scans.isEmpty ? 100 : totalScore / scans.count
        return ScanAggregation(averageScore: avg, cleanCount: cleanCount,
                               threatCounts: threatCounts, domainCounts: domainCounts)
    }

    /// Generate a privacy profile for a specific feed.
    func feedProfile(feedName: String, feedURL: String,
                     now: Date = Date()) -> FeedPrivacyProfile {
        let feedScans = scans(for: feedName)
        guard !feedScans.isEmpty else {
            return FeedPrivacyProfile(
                feedName: feedName, feedURL: feedURL,
                averageScore: 100, severity: .low, grade: "A+",
                articlesScanned: 0, cleanArticles: 0,
                topThreats: [], uniqueExternalDomains: 0,
                topExternalDomains: [],
                recommendation: "No articles scanned yet.",
                generatedAt: now
            )
        }

        let agg = aggregate(feedScans)

        let grade = Self.scoreToGrade(agg.averageScore)
        let severity = PrivacySeverity.from(score: 1.0 - Double(agg.averageScore) / 100.0)
        let recommendation = generateRecommendation(
            score: agg.averageScore, threats: agg.threatCounts,
            cleanRatio: agg.cleanPercentage(of: feedScans.count) / 100.0
        )

        return FeedPrivacyProfile(
            feedName: feedName, feedURL: feedURL,
            averageScore: agg.averageScore, severity: severity, grade: grade,
            articlesScanned: feedScans.count, cleanArticles: agg.cleanCount,
            topThreats: agg.topThreats(),
            uniqueExternalDomains: agg.uniqueDomainCount,
            topExternalDomains: agg.topDomains(),
            recommendation: recommendation,
            generatedAt: now
        )
    }

    /// Generate a fleet-wide privacy report across all feeds.
    func generateReport() -> PrivacyReport {
        let allResults = allScans()
        let feedGroups = Dictionary(grouping: allResults, by: { $0.feedName })

        guard !allResults.isEmpty else {
            return PrivacyReport(
                totalFeeds: 0, totalArticles: 0,
                overallScore: 100, overallSeverity: .low,
                feedRankings: [], threatDistribution: [:],
                worstDomains: [], cleanPercentage: 100.0,
                summary: "No articles scanned. Add feeds and scan articles to see privacy insights."
            )
        }

        // Per-feed scores (reuses aggregate for consistency)
        var feedRankings: [(feedName: String, score: Int, grade: String)] = []
        for (feedName, scans) in feedGroups {
            let avg = scans.reduce(0) { $0 + $1.privacyScore } / scans.count
            feedRankings.append((feedName, avg, Self.scoreToGrade(avg)))
        }
        feedRankings.sort { $0.score < $1.score }  // Worst first

        // Global aggregation via shared helper
        let agg = aggregate(allResults)

        // Domain→feed cross-reference (report-specific, not in aggregate)
        var domainToFeeds: [String: Set<String>] = [:]
        for scan in allResults {
            for domain in scan.externalDomains {
                domainToFeeds[domain, default: []].insert(scan.feedName)
            }
        }
        let worstDomains = agg.domainCounts.sorted { $0.value > $1.value }
            .prefix(15)
            .map { (domain: $0.key, feedCount: domainToFeeds[$0.key]?.count ?? 0, totalHits: $0.value) }

        let cleanPct = agg.cleanPercentage(of: allResults.count)
        let summary = generateSummary(score: agg.averageScore, feedCount: feedGroups.count,
                                       articleCount: allResults.count, cleanPct: cleanPct)

        return PrivacyReport(
            totalFeeds: feedGroups.count,
            totalArticles: allResults.count,
            overallScore: agg.averageScore,
            overallSeverity: PrivacySeverity.from(score: 1.0 - Double(agg.averageScore) / 100.0),
            feedRankings: feedRankings,
            threatDistribution: agg.threatCounts,
            worstDomains: worstDomains,
            cleanPercentage: cleanPct,
            summary: summary
        )
    }

    /// Remove all cached scans.
    func clearScans() {
        scanCache.removeAll()
        saveScans()
    }

    /// Remove scans for a specific feed.
    func clearScans(for feedName: String) {
        scanCache = scanCache.filter { $0.value.feedName != feedName }
        saveScans()
    }

    /// Number of cached scan results.
    var scanCount: Int { scanCache.count }

    /// Export scans as JSON data.
    func exportJSON() -> Data? {
        let exportable = scanCache.values.map { ArticlePrivacyScanData(from: $0) }
        let encoder = JSONCoding.iso8601PrettyEncoder
        return try? encoder.encode(exportable)
    }

    /// Import scans from JSON data.
    @discardableResult
    func importJSON(_ data: Data) -> Int {
        let decoder = JSONCoding.iso8601Decoder
        guard let imported = try? decoder.decode([ArticlePrivacyScanData].self, from: data) else {
            return 0
        }
        var count = 0
        for item in imported {
            let scan = item.toScan()
            if scanCache[scan.articleURL] == nil {
                scanCache[scan.articleURL] = scan
                count += 1
            }
        }
        trimCacheIfNeeded()
        saveScans()
        return count
    }

    // MARK: - Private Helpers

    /// Extract domains from URLs in HTML content.
    private func extractDomains(from content: String) -> Set<String> {
        var domains = Set<String>()
        // Match URLs in src=, href=, url( attributes
        let urlPatterns = [
            "(?:src|href|action)\\s*=\\s*[\"']https?://([^/\"'\\s]+)",
            "url\\s*\\(\\s*[\"']?https?://([^/\"'\\s\\)]+)",
        ]
        for pattern in urlPatterns {
            if let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) {
                let range = NSRange(content.startIndex..., in: content)
                let matches = regex.matches(in: content, range: range)
                for match in matches {
                    if match.numberOfRanges > 1,
                       let domainRange = Range(match.range(at: 1), in: content) {
                        domains.insert(String(content[domainRange]).lowercased())
                    }
                }
            }
        }
        return domains
    }

    /// Categorize a tracker domain into the most specific threat category.
    private func categorizeTrackerDomain(_ domain: String) -> PrivacyThreatCategory {
        let adDomains = ["doubleclick", "googlesyndication", "googleadservices",
                         "adnxs", "adsrvr", "criteo", "taboola", "outbrain",
                         "amazon-adsystem"]
        if adDomains.contains(where: { domain.contains($0) }) { return .adNetwork }

        let crossSite = ["facebook.com/tr", "connect.facebook", "platform.twitter",
                         "snap.licdn", "linkedin.com/px", "bat.bing", "clarity.ms"]
        if crossSite.contains(where: { domain.contains($0) }) { return .crossSiteTracker }

        let emailTrackers = ["list-manage", "mailchimp", "sendgrid", "sparkpost",
                             "returnpath", "litmus"]
        if emailTrackers.contains(where: { domain.contains($0) }) { return .emailTracker }

        let fingerprint = ["fingerprintjs", "fpjs", "deviceid"]
        if fingerprint.contains(where: { domain.contains($0) }) { return .fingerprinting }

        return .analyticsScript
    }

    /// Calculate privacy score (0-100) from threats and external domains.
    private func calculatePrivacyScore(threats: [PrivacyThreat], externalDomains: Set<String>) -> Int {
        guard !threats.isEmpty || !externalDomains.isEmpty else { return 100 }

        var penalty = 0.0

        // Threat penalties (weighted by category severity)
        for threat in threats {
            penalty += threat.category.severity * 15.0
        }

        // External domain penalty (diminishing returns)
        let domainPenalty = min(Double(externalDomains.count) * 2.0, 20.0)
        penalty += domainPenalty

        // Cap at 100
        let score = max(0, 100 - Int(penalty))
        return score
    }

    /// Generate a recommendation based on the feed's privacy profile.
    private func generateRecommendation(score: Int, threats: [PrivacyThreatCategory: Int],
                                        cleanRatio: Double) -> String {
        if score >= 90 {
            return "Excellent privacy practices. This feed respects your privacy."
        } else if score >= 70 {
            let topThreat = threats.max(by: { $0.value < $1.value })?.key
            let threatName = topThreat?.label ?? "trackers"
            return "Moderate privacy concerns. Primary issue: \(threatName). Consider using a content blocker."
        } else if score >= 50 {
            return "Significant privacy concerns. Multiple tracking mechanisms detected. Use reader mode when possible."
        } else {
            return "Poor privacy. Heavy tracking detected. Consider unsubscribing or using a privacy-focused alternative."
        }
    }

    /// Generate overall summary text.
    private func generateSummary(score: Int, feedCount: Int,
                                  articleCount: Int, cleanPct: Double) -> String {
        let grade = Self.scoreToGrade(score)
        if score >= 80 {
            return "Your feed collection has good privacy practices (Grade \(grade)). \(String(format: "%.0f", cleanPct))% of articles are tracker-free."
        } else if score >= 60 {
            return "Mixed privacy across your feeds (Grade \(grade)). Some feeds embed significant tracking. Review the rankings above for the worst offenders."
        } else {
            return "Privacy concerns detected across your feeds (Grade \(grade)). Many articles contain tracking pixels, analytics scripts, or fingerprinting code. Consider pruning feeds with poor privacy scores."
        }
    }

    /// Convert a 0-100 score to a letter grade.
    static func scoreToGrade(_ score: Int) -> String {
        switch score {
        case 95...100: return "A+"
        case 90..<95:  return "A"
        case 85..<90:  return "A-"
        case 80..<85:  return "B+"
        case 75..<80:  return "B"
        case 70..<75:  return "B-"
        case 65..<70:  return "C+"
        case 60..<65:  return "C"
        case 55..<60:  return "C-"
        case 50..<55:  return "D+"
        case 45..<50:  return "D"
        case 40..<45:  return "D-"
        default:       return "F"
        }
    }

    /// Trim cache to max size (evict oldest).
    private func trimCacheIfNeeded() {
        guard scanCache.count > maxCacheSize else { return }
        let sorted = scanCache.sorted { $0.value.scannedAt < $1.value.scannedAt }
        let toRemove = sorted.prefix(scanCache.count - maxCacheSize)
        for (key, _) in toRemove {
            scanCache.removeValue(forKey: key)
        }
    }

    // MARK: - Persistence

    private func saveScans() {
        let data = scanCache.mapValues { ArticlePrivacyScanData(from: $0) }
        store.save(data)
    }

    private func loadScans() {
        guard let data = store.load() else { return }
        scanCache = data.mapValues { $0.toScan() }
    }
}
