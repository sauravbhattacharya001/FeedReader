//
//  FeedHealthMonitor.swift
//  FeedReader
//
//  Monitors the health of subscribed RSS feeds by checking availability,
//  response time, and content freshness. Helps users identify dead,
//  slow, or stale feeds so they can prune their subscription list.
//
//  Usage:
//  ```
//  let monitor = FeedHealthMonitor()
//  monitor.checkFeed(url: "https://example.com/feed") { report in
//      print(report.status)          // .healthy, .slow, .stale, .dead
//      print(report.responseTimeMs)  // 342
//      print(report.lastPublished)   // Optional Date
//  }
//
//  // Batch check all feeds
//  monitor.checkAllFeeds(urls: feedURLs) { reports in
//      let dead = reports.filter { $0.status == .dead }
//      print("\(dead.count) dead feeds found")
//  }
//
//  // Get a summary
//  let summary = FeedHealthMonitor.summary(from: reports)
//  print(summary.healthyCount, summary.deadCount)
//  ```
//

import Foundation

// MARK: - Feed Health Report

/// Result of a single feed health check.
struct FeedHealthReport: Codable {

    /// Overall health status of a feed.
    enum Status: String, Codable, Comparable {
        case healthy = "Healthy"
        case slow = "Slow"
        case stale = "Stale"
        case unreachable = "Unreachable"
        case dead = "Dead"
        case malformed = "Malformed"

        private var sortOrder: Int {
            switch self {
            case .dead: return 0
            case .unreachable: return 1
            case .malformed: return 2
            case .stale: return 3
            case .slow: return 4
            case .healthy: return 5
            }
        }

        static func < (lhs: Status, rhs: Status) -> Bool {
            return lhs.sortOrder < rhs.sortOrder
        }
    }

    let feedURL: String
    let status: Status
    let httpStatusCode: Int?
    let responseTimeMs: Int
    let lastPublished: Date?
    let itemCount: Int
    let errorMessage: String?
    let checkedAt: Date

    /// Human-readable description of the feed's freshness.
    var freshnessDescription: String {
        guard let lastPublished = lastPublished else {
            return "No publish date found"
        }
        let interval = Date().timeIntervalSince(lastPublished)
        let days = Int(interval / 86400)
        if days == 0 { return "Updated today" }
        if days == 1 { return "Updated yesterday" }
        if days < 7 { return "Updated \(days) days ago" }
        if days < 30 { return "Updated \(days / 7) weeks ago" }
        if days < 365 { return "Updated \(days / 30) months ago" }
        return "Updated \(days / 365) years ago — likely dead"
    }
}

// MARK: - Health Summary

/// Aggregated summary of multiple feed health checks.
struct FeedHealthSummary {
    let totalFeeds: Int
    let healthyCount: Int
    let slowCount: Int
    let staleCount: Int
    let unreachableCount: Int
    let deadCount: Int
    let malformedCount: Int
    let averageResponseTimeMs: Int
    let slowestFeed: FeedHealthReport?
    let stalestFeed: FeedHealthReport?

    var overallScore: Int {
        guard totalFeeds > 0 else { return 100 }
        let goodFeeds = healthyCount + slowCount
        return (goodFeeds * 100) / totalFeeds
    }

    var scoreDescription: String {
        switch overallScore {
        case 90...100: return "Excellent — your feeds are in great shape!"
        case 70..<90: return "Good — a few feeds need attention"
        case 50..<70: return "Fair — consider pruning stale/dead feeds"
        default: return "Poor — many feeds are unhealthy"
        }
    }
}

// MARK: - Feed Health Monitor Configuration

/// Tunable thresholds for health classification.
struct FeedHealthConfig {
    /// Response times above this (ms) are classified as "slow".
    var slowThresholdMs: Int = 3000

    /// Feeds with no new content in this many days are "stale".
    var staleDays: Int = 90

    /// Feeds with no new content in this many days are "dead".
    var deadDays: Int = 365

    /// Timeout for HTTP requests in seconds.
    var requestTimeoutSeconds: TimeInterval = 15

    /// Maximum concurrent checks.
    var maxConcurrentChecks: Int = 5

    static let `default` = FeedHealthConfig()
}

// MARK: - Feed Health Monitor

/// Checks the health of RSS/Atom feeds by measuring availability,
/// response time, and content freshness.
class FeedHealthMonitor {

    // MARK: - Properties

    private let config: FeedHealthConfig
    private let session: URLSession
    private let historyStore: FeedHealthHistoryStore

    // MARK: - Init

    init(config: FeedHealthConfig = .default) {
        self.config = config
        let sessionConfig = URLSessionConfiguration.ephemeral
        sessionConfig.timeoutIntervalForRequest = config.requestTimeoutSeconds
        sessionConfig.timeoutIntervalForResource = config.requestTimeoutSeconds * 2
        self.session = URLSession(configuration: sessionConfig)
        self.historyStore = FeedHealthHistoryStore()
    }

    // MARK: - Single Feed Check

    /// Check the health of a single feed URL.
    func checkFeed(url: String, completion: @escaping (FeedHealthReport) -> Void) {
        guard let feedURL = URL(string: url) else {
            let report = FeedHealthReport(
                feedURL: url,
                status: .malformed,
                httpStatusCode: nil,
                responseTimeMs: 0,
                lastPublished: nil,
                itemCount: 0,
                errorMessage: "Invalid URL",
                checkedAt: Date()
            )
            completion(report)
            return
        }

        let startTime = Date()

        let task = session.dataTask(with: feedURL) { [weak self] data, response, error in
            guard let self = self else { return }
            let responseTimeMs = Int(Date().timeIntervalSince(startTime) * 1000)

            if let error = error {
                let report = FeedHealthReport(
                    feedURL: url,
                    status: .unreachable,
                    httpStatusCode: nil,
                    responseTimeMs: responseTimeMs,
                    lastPublished: nil,
                    itemCount: 0,
                    errorMessage: error.localizedDescription,
                    checkedAt: Date()
                )
                self.historyStore.record(report)
                completion(report)
                return
            }

            let httpStatus = (response as? HTTPURLResponse)?.statusCode
            guard let data = data, let httpStatus = httpStatus, (200..<400).contains(httpStatus) else {
                let report = FeedHealthReport(
                    feedURL: url,
                    status: .unreachable,
                    httpStatusCode: httpStatus,
                    responseTimeMs: responseTimeMs,
                    lastPublished: nil,
                    itemCount: 0,
                    errorMessage: "HTTP \(httpStatus ?? 0)",
                    checkedAt: Date()
                )
                self.historyStore.record(report)
                completion(report)
                return
            }

            // Parse the feed for freshness info
            let parseResult = FeedHealthXMLParser.parse(data: data)

            let status = self.classifyHealth(
                responseTimeMs: responseTimeMs,
                lastPublished: parseResult.lastPublished,
                itemCount: parseResult.itemCount,
                isValidFeed: parseResult.isValidFeed
            )

            let report = FeedHealthReport(
                feedURL: url,
                status: status,
                httpStatusCode: httpStatus,
                responseTimeMs: responseTimeMs,
                lastPublished: parseResult.lastPublished,
                itemCount: parseResult.itemCount,
                errorMessage: nil,
                checkedAt: Date()
            )
            self.historyStore.record(report)
            completion(report)
        }
        task.resume()
    }

    // MARK: - Batch Check

    /// Check multiple feeds with concurrency control.
    func checkAllFeeds(urls: [String], completion: @escaping ([FeedHealthReport]) -> Void) {
        let semaphore = DispatchSemaphore(value: config.maxConcurrentChecks)
        let group = DispatchGroup()
        let queue = DispatchQueue(label: "com.feedreader.healthmonitor", attributes: .concurrent)
        var reports: [FeedHealthReport] = []
        let lock = NSLock()

        for url in urls {
            group.enter()
            queue.async {
                semaphore.wait()
                self.checkFeed(url: url) { report in
                    lock.lock()
                    reports.append(report)
                    lock.unlock()
                    semaphore.signal()
                    group.leave()
                }
            }
        }

        group.notify(queue: .main) {
            // Sort worst-first so problematic feeds are at the top
            let sorted = reports.sorted { $0.status < $1.status }
            completion(sorted)
        }
    }

    // MARK: - Summary

    /// Generate an aggregate summary from a batch of reports.
    static func summary(from reports: [FeedHealthReport]) -> FeedHealthSummary {
        let healthy = reports.filter { $0.status == .healthy }.count
        let slow = reports.filter { $0.status == .slow }.count
        let stale = reports.filter { $0.status == .stale }.count
        let unreachable = reports.filter { $0.status == .unreachable }.count
        let dead = reports.filter { $0.status == .dead }.count
        let malformed = reports.filter { $0.status == .malformed }.count

        let avgMs: Int
        if reports.isEmpty {
            avgMs = 0
        } else {
            avgMs = reports.map { $0.responseTimeMs }.reduce(0, +) / reports.count
        }

        let slowest = reports.max(by: { $0.responseTimeMs < $1.responseTimeMs })
        let stalest = reports
            .compactMap { report -> (FeedHealthReport, Date)? in
                guard let date = report.lastPublished else { return nil }
                return (report, date)
            }
            .min(by: { $0.1 < $1.1 })?.0

        return FeedHealthSummary(
            totalFeeds: reports.count,
            healthyCount: healthy,
            slowCount: slow,
            staleCount: stale,
            unreachableCount: unreachable,
            deadCount: dead,
            malformedCount: malformed,
            averageResponseTimeMs: avgMs,
            slowestFeed: slowest,
            stalestFeed: stalest
        )
    }

    // MARK: - History

    /// Get the last N health reports for a given feed URL.
    func history(for feedURL: String, limit: Int = 10) -> [FeedHealthReport] {
        return historyStore.history(for: feedURL, limit: limit)
    }

    /// Check if a feed's health has been declining over recent checks.
    func isDeclining(feedURL: String) -> Bool {
        let recent = history(for: feedURL, limit: 5)
        guard recent.count >= 3 else { return false }

        // Declining if average response time is increasing or status is worsening
        let statuses = recent.map { $0.status }
        let hasUnhealthy = statuses.contains(where: { $0 < .slow })
        let recentlyHealthy = statuses.prefix(2).allSatisfy { $0 >= .slow }
        return hasUnhealthy && !recentlyHealthy
    }

    // MARK: - Classification

    private func classifyHealth(
        responseTimeMs: Int,
        lastPublished: Date?,
        itemCount: Int,
        isValidFeed: Bool
    ) -> FeedHealthReport.Status {
        guard isValidFeed else { return .malformed }

        if let lastPublished = lastPublished {
            let daysSinceUpdate = Int(Date().timeIntervalSince(lastPublished) / 86400)
            if daysSinceUpdate >= config.deadDays { return .dead }
            if daysSinceUpdate >= config.staleDays { return .stale }
        }

        if responseTimeMs > config.slowThresholdMs { return .slow }

        return .healthy
    }
}

// MARK: - Lightweight XML Parser for Health Checks

/// Minimal XML parser that extracts just enough to assess feed health:
/// the most recent <pubDate>/<updated>/<dc:date> and item count.
private class FeedHealthXMLParser: NSObject, XMLParserDelegate {

    struct Result {
        var lastPublished: Date?
        var itemCount: Int = 0
        var isValidFeed: Bool = false
    }

    private var result = Result()
    private var currentElement = ""
    private var currentText = ""
    private var insideItem = false
    private var dates: [Date] = []

    private static let dateFormatters: [DateFormatter] = {
        let formats = [
            "EEE, dd MMM yyyy HH:mm:ss Z",       // RFC 822
            "EEE, dd MMM yyyy HH:mm:ss zzz",
            "yyyy-MM-dd'T'HH:mm:ssZ",             // ISO 8601
            "yyyy-MM-dd'T'HH:mm:ss.SSSZ",
            "yyyy-MM-dd'T'HH:mm:ssxxxxx",
            "yyyy-MM-dd HH:mm:ss",
            "yyyy-MM-dd",
        ]
        return formats.map { fmt in
            let df = DateFormatter()
            df.dateFormat = fmt
            df.locale = Locale(identifier: "en_US_POSIX")
            df.timeZone = TimeZone(secondsFromGMT: 0)
            return df
        }
    }()

    static func parse(data: Data) -> Result {
        let parser = FeedHealthXMLParser()
        let xmlParser = XMLParser(data: data)
        xmlParser.delegate = parser
        xmlParser.parse()
        return parser.result
    }

    // MARK: - XMLParserDelegate

    func parser(_ parser: XMLParser, didStartElement elementName: String,
                namespaceURI: String?, qualifiedName qName: String?,
                attributes attributeDict: [String: String] = [:]) {

        let name = elementName.lowercased()

        if name == "rss" || name == "feed" || name == "rdf:rdf" {
            result.isValidFeed = true
        }

        if name == "item" || name == "entry" {
            insideItem = true
            result.itemCount += 1
        }

        currentElement = name
        currentText = ""
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        currentText += string
    }

    func parser(_ parser: XMLParser, didEndElement elementName: String,
                namespaceURI: String?, qualifiedName qName: String?) {

        let name = elementName.lowercased()

        if name == "item" || name == "entry" {
            insideItem = false
        }

        let dateElements = ["pubdate", "updated", "published", "dc:date", "date", "modified"]
        if dateElements.contains(name) {
            let trimmed = currentText.trimmingCharacters(in: .whitespacesAndNewlines)
            if let date = Self.parseDate(trimmed) {
                dates.append(date)
            }
        }

        currentElement = ""
        currentText = ""
    }

    func parserDidEndDocument(_ parser: XMLParser) {
        result.lastPublished = dates.max()
    }

    private static func parseDate(_ string: String) -> Date? {
        for formatter in dateFormatters {
            if let date = formatter.date(from: string) {
                return date
            }
        }
        // Try ISO8601DateFormatter as fallback
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = iso.date(from: string) { return date }
        iso.formatOptions = [.withInternetDateTime]
        return iso.date(from: string)
    }
}

// MARK: - Health History Store

/// Persists recent health check results for trend analysis.
class FeedHealthHistoryStore {

    private let storageKey = "FeedHealthHistory"
    private let maxHistoryPerFeed = 20

    /// Record a new health check result.
    func record(_ report: FeedHealthReport) {
        var allHistory = loadAll()
        var feedHistory = allHistory[report.feedURL] ?? []
        feedHistory.insert(report, at: 0)
        if feedHistory.count > maxHistoryPerFeed {
            feedHistory = Array(feedHistory.prefix(maxHistoryPerFeed))
        }
        allHistory[report.feedURL] = feedHistory
        save(allHistory)
    }

    /// Get history for a specific feed.
    func history(for feedURL: String, limit: Int) -> [FeedHealthReport] {
        let allHistory = loadAll()
        let feedHistory = allHistory[feedURL] ?? []
        return Array(feedHistory.prefix(limit))
    }

    // MARK: - Persistence

    private func loadAll() -> [String: [FeedHealthReport]] {
        guard let data = UserDefaults.standard.data(forKey: storageKey) else {
            return [:]
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return (try? decoder.decode([String: [FeedHealthReport]].self, from: data)) ?? [:]
    }

    private func save(_ history: [String: [FeedHealthReport]]) {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(history) else { return }
        UserDefaults.standard.set(data, forKey: storageKey)
    }
}
