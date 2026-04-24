//
//  FeedAnomalyDetector.swift
//  FeedReader
//
//  Autonomous anomaly detection for RSS feeds. Monitors feed behavior
//  over time and detects unusual patterns that may indicate feed issues,
//  hijacking, or significant editorial changes.
//
//  Detection channels:
//  1. Posting frequency anomalies (sudden bursts or droughts)
//  2. Content length anomalies (articles significantly shorter/longer than normal)
//  3. Topic drift detection (feed suddenly covers different subjects)
//  4. Author pattern changes (new/missing authors)
//  5. Link domain anomalies (articles linking to unusual domains)
//  6. Title pattern anomalies (style/format changes in titles)
//
//  Features:
//  - Baseline learning from historical feed data
//  - Z-score based statistical anomaly detection
//  - Severity classification (info/warning/critical)
//  - Anomaly timeline with persistence
//  - Auto-monitor mode for continuous background scanning
//  - Proactive recommendations per anomaly type
//  - Feed trust scoring based on anomaly history
//  - JSON export of anomaly reports
//

import Foundation

// MARK: - Notifications

extension Notification.Name {
    /// Posted when new anomalies are detected.
    static let feedAnomaliesDetected = Notification.Name("FeedAnomaliesDetectedNotification")
    /// Posted when a feed's trust score changes significantly.
    static let feedTrustScoreChanged = Notification.Name("FeedTrustScoreChangedNotification")
}

// MARK: - Data Types

/// Severity level for detected anomalies.
enum AnomalySeverity: String, Codable, Comparable {
    case info = "info"
    case warning = "warning"
    case critical = "critical"

    private var rank: Int {
        switch self {
        case .info: return 0
        case .warning: return 1
        case .critical: return 2
        }
    }

    static func < (lhs: AnomalySeverity, rhs: AnomalySeverity) -> Bool {
        lhs.rank < rhs.rank
    }
}

/// The type of anomaly detected.
enum AnomalyChannel: String, Codable {
    case postingFrequency = "posting_frequency"
    case contentLength = "content_length"
    case topicDrift = "topic_drift"
    case authorChange = "author_change"
    case linkDomain = "link_domain"
    case titlePattern = "title_pattern"

    var displayName: String {
        switch self {
        case .postingFrequency: return "Posting Frequency"
        case .contentLength: return "Content Length"
        case .topicDrift: return "Topic Drift"
        case .authorChange: return "Author Change"
        case .linkDomain: return "Link Domain"
        case .titlePattern: return "Title Pattern"
        }
    }
}

/// A single detected anomaly.
struct FeedAnomaly: Codable, Equatable {
    let id: String
    let feedName: String
    let channel: AnomalyChannel
    let severity: AnomalySeverity
    let description: String
    let recommendation: String
    let detectedAt: Date
    /// The z-score or deviation metric that triggered this anomaly.
    let deviationScore: Double
    /// Whether the user has acknowledged/dismissed this anomaly.
    var isDismissed: Bool

    static func == (lhs: FeedAnomaly, rhs: FeedAnomaly) -> Bool {
        lhs.id == rhs.id
    }
}

/// Baseline statistics for a single feed.
struct FeedBaseline: Codable {
    let feedName: String
    var updatedAt: Date

    // Posting frequency (articles per day)
    var avgPostsPerDay: Double
    var stdPostsPerDay: Double
    var sampleDays: Int

    // Content length (word count)
    var avgWordCount: Double
    var stdWordCount: Double
    var sampleArticles: Int

    // Known authors
    var knownAuthors: Set<String>

    // Known link domains
    var knownDomains: Set<String>

    // Top keywords (simple TF proxy)
    var topKeywords: [String: Int]

    // Title average word count and character count
    var avgTitleWords: Double
    var stdTitleWords: Double
}

/// Trust score for a feed based on anomaly history.
struct FeedTrustScore: Codable {
    let feedName: String
    var score: Double // 0.0 (untrusted) to 100.0 (fully trusted)
    var totalAnomalies: Int
    var criticalCount: Int
    var warningCount: Int
    var infoCount: Int
    var lastUpdated: Date
}

/// Full anomaly report for export.
struct AnomalyReport: Codable {
    let generatedAt: Date
    let feedName: String?
    let anomalies: [FeedAnomaly]
    let trustScores: [FeedTrustScore]
    let baselines: [FeedBaseline]
    let summary: AnomalyReportSummary
}

struct AnomalyReportSummary: Codable {
    let totalFeeds: Int
    let totalAnomalies: Int
    let criticalCount: Int
    let warningCount: Int
    let infoCount: Int
    let mostAnomalousFeed: String?
    let mostCommonChannel: String?
    let recommendations: [String]
}

// MARK: - FeedAnomalyDetector

/// Autonomous feed anomaly detection engine.
final class FeedAnomalyDetector {

    // MARK: - Configuration

    /// Z-score thresholds for severity classification.
    struct Thresholds {
        var infoZScore: Double = 1.5
        var warningZScore: Double = 2.5
        var criticalZScore: Double = 3.5
        /// Minimum sample size before anomaly detection activates.
        var minSampleSize: Int = 7
        /// Topic drift: fraction of new keywords that triggers an anomaly.
        var topicDriftThreshold: Double = 0.6
        /// Trust score penalty per anomaly severity.
        var criticalPenalty: Double = 15.0
        var warningPenalty: Double = 5.0
        var infoPenalty: Double = 1.0
        /// Trust score recovery per clean scan (no anomalies).
        var cleanScanRecovery: Double = 2.0
    }

    var thresholds = Thresholds()

    // MARK: - State

    private var baselines: [String: FeedBaseline] = [:]
    private var anomalies: [FeedAnomaly] = []
    private var trustScores: [String: FeedTrustScore] = [:]
    private let persistencePath: String

    // MARK: - Init

    init(directory: String? = nil) {
        let dir = directory ?? {
            let paths = NSSearchPathForDirectoriesInDomains(.documentDirectory, .userDomainMask, true)
            return paths.first ?? NSTemporaryDirectory()
        }()
        self.persistencePath = (dir as NSString).appendingPathComponent("feed_anomaly_detector.json")
        loadState()
    }

    // MARK: - Baseline Learning

    /// Build or update a baseline from a collection of articles.
    /// Each article is represented as a dictionary with keys:
    ///   "title", "content", "author", "link", "publishedDate" (ISO8601)
    func learnBaseline(feedName: String, articles: [[String: String]]) {
        guard !articles.isEmpty else { return }

        // Parse dates
        let formatter = ISO8601DateFormatter()
        var dates: [Date] = []
        var wordCounts: [Double] = []
        var authors: Set<String> = []
        var domains: Set<String> = []
        var keywordCounts: [String: Int] = [:]
        var titleWordCounts: [Double] = []

        for article in articles {
            if let dateStr = article["publishedDate"], let date = formatter.date(from: dateStr) {
                dates.append(date)
            }
            if let content = article["content"] {
                let words = content.split(separator: " ")
                wordCounts.append(Double(words.count))
                // Simple keyword extraction: lowercase words > 4 chars
                for word in words {
                    let w = word.lowercased().trimmingCharacters(in: .punctuationCharacters)
                    if w.count > 4 {
                        keywordCounts[w, default: 0] += 1
                    }
                }
            }
            if let author = article["author"], !author.isEmpty {
                authors.insert(author.lowercased())
            }
            if let link = article["link"], let url = URL(string: link), let host = url.host {
                domains.insert(host.lowercased())
            }
            if let title = article["title"] {
                titleWordCounts.append(Double(title.split(separator: " ").count))
            }
        }

        // Posting frequency: articles per day
        let (avgPosts, stdPosts, days) = computePostingFrequency(dates: dates)

        // Content length stats
        let avgWords = wordCounts.isEmpty ? 0 : wordCounts.reduce(0, +) / Double(wordCounts.count)
        let stdWords = standardDeviation(wordCounts)

        // Title stats
        let avgTitle = titleWordCounts.isEmpty ? 0 : titleWordCounts.reduce(0, +) / Double(titleWordCounts.count)
        let stdTitle = standardDeviation(titleWordCounts)

        // Keep top 50 keywords
        let topKW = Dictionary(uniqueKeysWithValues:
            keywordCounts.sorted { $0.value > $1.value }.prefix(50))

        let baseline = FeedBaseline(
            feedName: feedName,
            updatedAt: Date(),
            avgPostsPerDay: avgPosts,
            stdPostsPerDay: stdPosts,
            sampleDays: days,
            avgWordCount: avgWords,
            stdWordCount: stdWords,
            sampleArticles: articles.count,
            knownAuthors: authors,
            knownDomains: domains,
            topKeywords: topKW,
            avgTitleWords: avgTitle,
            stdTitleWords: stdTitle
        )
        baselines[feedName] = baseline
        saveState()
    }

    // MARK: - Anomaly Detection

    /// Scan a feed's recent articles for anomalies against its baseline.
    /// Returns newly detected anomalies.
    @discardableResult
    func scan(feedName: String, recentArticles: [[String: String]]) -> [FeedAnomaly] {
        guard let baseline = baselines[feedName] else { return [] }
        guard baseline.sampleArticles >= thresholds.minSampleSize else { return [] }

        var detected: [FeedAnomaly] = []

        // 1. Posting frequency check
        detected += checkPostingFrequency(feedName: feedName, baseline: baseline, articles: recentArticles)

        // 2. Content length check
        detected += checkContentLength(feedName: feedName, baseline: baseline, articles: recentArticles)

        // 3. Topic drift check
        detected += checkTopicDrift(feedName: feedName, baseline: baseline, articles: recentArticles)

        // 4. Author change check
        detected += checkAuthorChanges(feedName: feedName, baseline: baseline, articles: recentArticles)

        // 5. Link domain check
        detected += checkLinkDomains(feedName: feedName, baseline: baseline, articles: recentArticles)

        // 6. Title pattern check
        detected += checkTitlePatterns(feedName: feedName, baseline: baseline, articles: recentArticles)

        // Store anomalies
        anomalies.append(contentsOf: detected)

        // Update trust score
        updateTrustScore(feedName: feedName, newAnomalies: detected)

        // Trim old anomalies (keep last 500)
        if anomalies.count > 500 {
            anomalies = Array(anomalies.suffix(500))
        }

        saveState()

        if !detected.isEmpty {
            NotificationCenter.default.post(
                name: .feedAnomaliesDetected,
                object: self,
                userInfo: ["feedName": feedName, "anomalies": detected]
            )
        }

        return detected
    }

    /// Scan all feeds with known baselines.
    func scanAll(articlesByFeed: [String: [[String: String]]]) -> [String: [FeedAnomaly]] {
        var results: [String: [FeedAnomaly]] = [:]
        for (feed, articles) in articlesByFeed {
            let found = scan(feedName: feed, recentArticles: articles)
            if !found.isEmpty {
                results[feed] = found
            }
        }
        return results
    }

    // MARK: - Queries

    /// Get all anomalies for a feed, optionally filtered by severity.
    func anomalies(for feedName: String? = nil, severity: AnomalySeverity? = nil, includeDismissed: Bool = false) -> [FeedAnomaly] {
        anomalies.filter { a in
            if let feed = feedName, a.feedName != feed { return false }
            if let sev = severity, a.severity != sev { return false }
            if !includeDismissed && a.isDismissed { return false }
            return true
        }
    }

    /// Get the trust score for a feed.
    func trustScore(for feedName: String) -> FeedTrustScore {
        trustScores[feedName] ?? FeedTrustScore(
            feedName: feedName, score: 100.0,
            totalAnomalies: 0, criticalCount: 0, warningCount: 0, infoCount: 0,
            lastUpdated: Date()
        )
    }

    /// Get all trust scores sorted by score ascending (least trusted first).
    func allTrustScores() -> [FeedTrustScore] {
        trustScores.values.sorted { $0.score < $1.score }
    }

    /// Dismiss an anomaly by ID.
    func dismiss(anomalyId: String) {
        if let idx = anomalies.firstIndex(where: { $0.id == anomalyId }) {
            anomalies[idx].isDismissed = true
            saveState()
        }
    }

    /// Dismiss all anomalies for a feed.
    func dismissAll(for feedName: String) {
        for i in anomalies.indices where anomalies[i].feedName == feedName {
            anomalies[i].isDismissed = true
        }
        saveState()
    }

    // MARK: - Reporting

    /// Generate a full anomaly report, optionally for a single feed.
    func generateReport(feedName: String? = nil) -> AnomalyReport {
        let filtered = anomalies(for: feedName)
        let scores: [FeedTrustScore]
        let baselineList: [FeedBaseline]
        if let feed = feedName {
            scores = [trustScore(for: feed)]
            baselineList = baselines[feed].map { [$0] } ?? []
        } else {
            scores = allTrustScores()
            baselineList = Array(baselines.values)
        }

        let critical = filtered.filter { $0.severity == .critical }.count
        let warning = filtered.filter { $0.severity == .warning }.count
        let info = filtered.filter { $0.severity == .info }.count

        // Most anomalous feed
        var feedCounts: [String: Int] = [:]
        for a in filtered { feedCounts[a.feedName, default: 0] += 1 }
        let mostAnomalous = feedCounts.max(by: { $0.value < $1.value })?.key

        // Most common channel
        var channelCounts: [String: Int] = [:]
        for a in filtered { channelCounts[a.channel.rawValue, default: 0] += 1 }
        let mostCommon = channelCounts.max(by: { $0.value < $1.value })?.key

        // Recommendations
        var recs: [String] = []
        if critical > 0 {
            recs.append("Review \(critical) critical anomalies immediately — possible feed compromise or major editorial change.")
        }
        if let worst = scores.first, worst.score < 50 {
            recs.append("Feed '\(worst.feedName)' has a trust score of \(Int(worst.score))%. Consider unsubscribing or verifying the source.")
        }
        if feedCounts.count > 3 {
            recs.append("\(feedCounts.count) feeds have anomalies. Run a full feed audit to identify patterns.")
        }
        if filtered.isEmpty {
            recs.append("No anomalies detected. All feeds are behaving within expected parameters.")
        }

        let summary = AnomalyReportSummary(
            totalFeeds: feedName != nil ? 1 : baselines.count,
            totalAnomalies: filtered.count,
            criticalCount: critical,
            warningCount: warning,
            infoCount: info,
            mostAnomalousFeed: mostAnomalous,
            mostCommonChannel: mostCommon,
            recommendations: recs
        )

        return AnomalyReport(
            generatedAt: Date(),
            feedName: feedName,
            anomalies: filtered,
            trustScores: scores,
            baselines: baselineList,
            summary: summary
        )
    }

    /// Export report as JSON data.
    func exportJSON(feedName: String? = nil) -> Data? {
        let report = generateReport(feedName: feedName)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try? encoder.encode(report)
    }

    // MARK: - Detection Channels

    private func checkPostingFrequency(feedName: String, baseline: FeedBaseline, articles: [[String: String]]) -> [FeedAnomaly] {
        guard baseline.sampleDays >= thresholds.minSampleSize else { return [] }
        let formatter = ISO8601DateFormatter()
        let dates = articles.compactMap { $0["publishedDate"].flatMap { formatter.date(from: $0) } }
        guard !dates.isEmpty else { return [] }

        // Count articles in the last 24 hours
        let oneDayAgo = Date().addingTimeInterval(-86400)
        let recentCount = Double(dates.filter { $0 > oneDayAgo }.count)

        guard baseline.stdPostsPerDay > 0 else { return [] }
        let z = abs(recentCount - baseline.avgPostsPerDay) / baseline.stdPostsPerDay
        let severity = classifySeverity(zScore: z)
        guard severity != nil else { return [] }

        let direction = recentCount > baseline.avgPostsPerDay ? "spike" : "drought"
        let desc = "Posting frequency \(direction): \(Int(recentCount)) articles in last 24h vs baseline avg \(String(format: "%.1f", baseline.avgPostsPerDay))±\(String(format: "%.1f", baseline.stdPostsPerDay))."
        let rec: String
        if direction == "spike" {
            rec = "Unusual burst of posts. Check if the feed is flooding or if there's a major event. Consider temporarily muting."
        } else {
            rec = "Feed has gone unusually quiet. The source may be down, paywalled, or discontinued. Verify the feed URL."
        }

        return [FeedAnomaly(
            id: UUID().uuidString, feedName: feedName,
            channel: .postingFrequency, severity: severity!,
            description: desc, recommendation: rec,
            detectedAt: Date(), deviationScore: z, isDismissed: false
        )]
    }

    private func checkContentLength(feedName: String, baseline: FeedBaseline, articles: [[String: String]]) -> [FeedAnomaly] {
        guard baseline.stdWordCount > 0 else { return [] }
        var results: [FeedAnomaly] = []

        let wordCounts = articles.compactMap { $0["content"]?.split(separator: " ").count }
        guard !wordCounts.isEmpty else { return [] }
        let avgRecent = Double(wordCounts.reduce(0, +)) / Double(wordCounts.count)

        let z = abs(avgRecent - baseline.avgWordCount) / baseline.stdWordCount
        if let severity = classifySeverity(zScore: z) {
            let direction = avgRecent > baseline.avgWordCount ? "longer" : "shorter"
            let desc = "Articles are significantly \(direction) than usual: avg \(Int(avgRecent)) words vs baseline \(Int(baseline.avgWordCount))±\(Int(baseline.stdWordCount))."
            let rec = direction == "shorter"
                ? "Content may be truncated, behind a paywall, or the feed format changed. Check article quality."
                : "Unusually long articles may indicate scraped/duplicated content or format changes."
            results.append(FeedAnomaly(
                id: UUID().uuidString, feedName: feedName,
                channel: .contentLength, severity: severity,
                description: desc, recommendation: rec,
                detectedAt: Date(), deviationScore: z, isDismissed: false
            ))
        }
        return results
    }

    private func checkTopicDrift(feedName: String, baseline: FeedBaseline, articles: [[String: String]]) -> [FeedAnomaly] {
        guard !baseline.topKeywords.isEmpty else { return [] }
        var recentKeywords: Set<String> = []
        for article in articles {
            if let content = article["content"] {
                for word in content.split(separator: " ") {
                    let w = word.lowercased().trimmingCharacters(in: .punctuationCharacters)
                    if w.count > 4 { recentKeywords.insert(w) }
                }
            }
        }
        guard !recentKeywords.isEmpty else { return [] }

        let baselineKeys = Set(baseline.topKeywords.keys)
        let overlap = recentKeywords.intersection(baselineKeys)
        let overlapRatio = baselineKeys.isEmpty ? 1.0 : Double(overlap.count) / Double(baselineKeys.count)
        let driftScore = 1.0 - overlapRatio

        if driftScore >= thresholds.topicDriftThreshold {
            let severity: AnomalySeverity = driftScore >= 0.85 ? .critical : (driftScore >= 0.7 ? .warning : .info)
            let newTopics = recentKeywords.subtracting(baselineKeys).prefix(10)
            let desc = "Significant topic drift detected (\(Int(driftScore * 100))% new content). New topics include: \(newTopics.joined(separator: ", "))."
            let rec = "The feed's editorial direction may have changed. Review recent articles to ensure it still matches your interests."
            return [FeedAnomaly(
                id: UUID().uuidString, feedName: feedName,
                channel: .topicDrift, severity: severity,
                description: desc, recommendation: rec,
                detectedAt: Date(), deviationScore: driftScore, isDismissed: false
            )]
        }
        return []
    }

    private func checkAuthorChanges(feedName: String, baseline: FeedBaseline, articles: [[String: String]]) -> [FeedAnomaly] {
        guard !baseline.knownAuthors.isEmpty else { return [] }
        let recentAuthors = Set(articles.compactMap { $0["author"]?.lowercased() }.filter { !$0.isEmpty })
        guard !recentAuthors.isEmpty else { return [] }

        let newAuthors = recentAuthors.subtracting(baseline.knownAuthors)
        let missingAuthors = baseline.knownAuthors.subtracting(recentAuthors)
        let changeRatio = Double(newAuthors.count + missingAuthors.count) / Double(baseline.knownAuthors.count + recentAuthors.count)

        if changeRatio > 0.5 {
            let severity: AnomalySeverity = changeRatio > 0.8 ? .critical : .warning
            var desc = "Author lineup changed significantly (\(Int(changeRatio * 100))% different)."
            if !newAuthors.isEmpty { desc += " New: \(newAuthors.prefix(5).joined(separator: ", "))." }
            if !missingAuthors.isEmpty { desc += " Missing: \(missingAuthors.prefix(5).joined(separator: ", "))." }
            let rec = "Major author changes may indicate editorial restructuring or feed hijacking. Verify the source."
            return [FeedAnomaly(
                id: UUID().uuidString, feedName: feedName,
                channel: .authorChange, severity: severity,
                description: desc, recommendation: rec,
                detectedAt: Date(), deviationScore: changeRatio, isDismissed: false
            )]
        }
        return []
    }

    private func checkLinkDomains(feedName: String, baseline: FeedBaseline, articles: [[String: String]]) -> [FeedAnomaly] {
        guard !baseline.knownDomains.isEmpty else { return [] }
        let recentDomains = Set(articles.compactMap { article -> String? in
            guard let link = article["link"], let url = URL(string: link) else { return nil }
            return url.host?.lowercased()
        })
        guard !recentDomains.isEmpty else { return [] }

        let unknownDomains = recentDomains.subtracting(baseline.knownDomains)
        let unknownRatio = Double(unknownDomains.count) / Double(recentDomains.count)

        if unknownRatio > 0.5 {
            let severity: AnomalySeverity = unknownRatio > 0.8 ? .critical : .warning
            let desc = "Articles linking to unusual domains (\(Int(unknownRatio * 100))% unknown): \(unknownDomains.prefix(5).joined(separator: ", "))."
            let rec = "Unknown link domains may indicate feed hijacking, spam injection, or affiliate link manipulation. Inspect carefully."
            return [FeedAnomaly(
                id: UUID().uuidString, feedName: feedName,
                channel: .linkDomain, severity: severity,
                description: desc, recommendation: rec,
                detectedAt: Date(), deviationScore: unknownRatio, isDismissed: false
            )]
        }
        return []
    }

    private func checkTitlePatterns(feedName: String, baseline: FeedBaseline, articles: [[String: String]]) -> [FeedAnomaly] {
        guard baseline.stdTitleWords > 0 else { return [] }
        let titleLengths = articles.compactMap { $0["title"]?.split(separator: " ").count }.map(Double.init)
        guard !titleLengths.isEmpty else { return [] }

        let avgRecent = titleLengths.reduce(0, +) / Double(titleLengths.count)
        let z = abs(avgRecent - baseline.avgTitleWords) / baseline.stdTitleWords

        if let severity = classifySeverity(zScore: z) {
            let direction = avgRecent > baseline.avgTitleWords ? "longer" : "shorter"
            let desc = "Article titles are significantly \(direction) than usual: avg \(String(format: "%.1f", avgRecent)) words vs baseline \(String(format: "%.1f", baseline.avgTitleWords))±\(String(format: "%.1f", baseline.stdTitleWords))."
            let rec = "Title format changes may indicate a new content management system, editorial policy change, or automated content generation."
            return [FeedAnomaly(
                id: UUID().uuidString, feedName: feedName,
                channel: .titlePattern, severity: severity,
                description: desc, recommendation: rec,
                detectedAt: Date(), deviationScore: z, isDismissed: false
            )]
        }
        return []
    }

    // MARK: - Trust Score

    private func updateTrustScore(feedName: String, newAnomalies: [FeedAnomaly]) {
        var score = trustScores[feedName] ?? FeedTrustScore(
            feedName: feedName, score: 100.0,
            totalAnomalies: 0, criticalCount: 0, warningCount: 0, infoCount: 0,
            lastUpdated: Date()
        )

        if newAnomalies.isEmpty {
            // Clean scan: recover trust
            score.score = min(100.0, score.score + thresholds.cleanScanRecovery)
        } else {
            for a in newAnomalies {
                score.totalAnomalies += 1
                switch a.severity {
                case .critical:
                    score.criticalCount += 1
                    score.score = max(0, score.score - thresholds.criticalPenalty)
                case .warning:
                    score.warningCount += 1
                    score.score = max(0, score.score - thresholds.warningPenalty)
                case .info:
                    score.infoCount += 1
                    score.score = max(0, score.score - thresholds.infoPenalty)
                }
            }
        }
        score.lastUpdated = Date()
        trustScores[feedName] = score

        if newAnomalies.contains(where: { $0.severity >= .warning }) {
            NotificationCenter.default.post(
                name: .feedTrustScoreChanged,
                object: self,
                userInfo: ["feedName": feedName, "score": score.score]
            )
        }
    }

    // MARK: - Helpers

    private func classifySeverity(zScore: Double) -> AnomalySeverity? {
        if zScore >= thresholds.criticalZScore { return .critical }
        if zScore >= thresholds.warningZScore { return .warning }
        if zScore >= thresholds.infoZScore { return .info }
        return nil
    }

    private func computePostingFrequency(dates: [Date]) -> (avg: Double, std: Double, days: Int) {
        guard dates.count >= 2 else { return (Double(dates.count), 0, 1) }
        let sorted = dates.sorted()
        let cal = Calendar.current
        guard let first = sorted.first, let last = sorted.last else { return (0, 0, 0) }
        let totalDays = max(1, cal.dateComponents([.day], from: first, to: last).day ?? 1)

        // Count articles per day
        var dayCounts: [String: Int] = [:]
        let df = DateFormatter()
        df.dateFormat = "yyyy-MM-dd"
        for d in sorted { dayCounts[df.string(from: d), default: 0] += 1 }

        let counts = dayCounts.values.map(Double.init)
        let avg = counts.reduce(0, +) / Double(max(1, counts.count))
        let std = standardDeviation(counts)
        return (avg, std, totalDays)
    }

    private func standardDeviation(_ values: [Double]) -> Double {
        guard values.count > 1 else { return 0 }
        let mean = values.reduce(0, +) / Double(values.count)
        let variance = values.reduce(0) { $0 + ($1 - mean) * ($1 - mean) } / Double(values.count - 1)
        return sqrt(variance)
    }

    // MARK: - Persistence

    private struct PersistedState: Codable {
        let baselines: [String: FeedBaseline]
        let anomalies: [FeedAnomaly]
        let trustScores: [String: FeedTrustScore]
    }

    private func saveState() {
        let state = PersistedState(baselines: baselines, anomalies: anomalies, trustScores: trustScores)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        if let data = try? encoder.encode(state) {
            try? data.write(to: URL(fileURLWithPath: persistencePath), options: .atomic)
        }
    }

    private func loadState() {
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: persistencePath)) else { return }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        if let state = try? decoder.decode(PersistedState.self, from: data) {
            self.baselines = state.baselines
            self.anomalies = state.anomalies
            self.trustScores = state.trustScores
        }
    }

    /// Clear all state.
    func reset() {
        baselines = [:]
        anomalies = []
        trustScores = [:]
        saveState()
    }
}
