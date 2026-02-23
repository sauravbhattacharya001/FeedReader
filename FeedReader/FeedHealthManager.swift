//
//  FeedHealthManager.swift
//  FeedReader
//
//  Tracks per-feed health metrics — success rates, response times,
//  error history, and staleness detection. Helps users identify
//  broken, slow, or stale feeds that need attention.
//

import Foundation

/// Notification posted when feed health data changes.
extension Notification.Name {
    static let feedHealthDidChange = Notification.Name("FeedHealthDidChangeNotification")
}

/// Records a single fetch attempt for a feed.
struct FetchRecord: Codable, Equatable {
    let feedURL: String
    let timestamp: Date
    let success: Bool
    let responseTimeMs: Int
    let errorMessage: String?
    let storiesFound: Int
}

/// Health status classification for a feed.
enum FeedHealthStatus: String, Codable {
    case healthy    // ≥ 90% success rate, responding
    case degraded   // 50-89% success rate or slow
    case unhealthy  // < 50% success rate
    case stale      // No new articles in threshold period
    case unknown    // Not enough data
    
    /// Human-readable description.
    var label: String {
        switch self {
        case .healthy: return "Healthy"
        case .degraded: return "Degraded"
        case .unhealthy: return "Unhealthy"
        case .stale: return "Stale"
        case .unknown: return "Unknown"
        }
    }
    
    /// Traffic light color name for UI.
    var colorName: String {
        switch self {
        case .healthy: return "green"
        case .degraded: return "yellow"
        case .unhealthy: return "red"
        case .stale: return "orange"
        case .unknown: return "gray"
        }
    }
    
    /// Sort priority (lower = worse, for sorting worst-first).
    var priority: Int {
        switch self {
        case .unhealthy: return 0
        case .degraded: return 1
        case .stale: return 2
        case .unknown: return 3
        case .healthy: return 4
        }
    }
}

/// Aggregated health report for a single feed.
struct FeedHealthReport: Equatable {
    let feedURL: String
    let feedName: String
    let status: FeedHealthStatus
    let totalFetches: Int
    let successCount: Int
    let failureCount: Int
    let successRate: Double            // 0.0 – 1.0
    let avgResponseTimeMs: Double
    let minResponseTimeMs: Int
    let maxResponseTimeMs: Int
    let p95ResponseTimeMs: Int         // 95th percentile
    let lastFetchDate: Date?
    let lastSuccessDate: Date?
    let lastErrorDate: Date?
    let lastErrorMessage: String?
    let consecutiveFailures: Int
    let lastStoryCount: Int
    let daysSinceNewContent: Int?      // nil if unknown
    let recentErrors: [FetchRecord]    // last 5 errors
    
    /// Whether this feed needs user attention.
    var needsAttention: Bool {
        return status == .unhealthy || status == .degraded || consecutiveFailures >= 3
    }
    
    /// A one-line summary of the feed's health.
    var summary: String {
        let rate = Int(successRate * 100)
        switch status {
        case .healthy:
            return "\(rate)% success, avg \(Int(avgResponseTimeMs))ms"
        case .degraded:
            return "\(rate)% success, \(consecutiveFailures) recent failures"
        case .unhealthy:
            let msg = lastErrorMessage ?? "Unknown error"
            return "\(rate)% success — \(msg)"
        case .stale:
            if let days = daysSinceNewContent {
                return "No new content in \(days) day\(days == 1 ? "" : "s")"
            }
            return "No new content detected"
        case .unknown:
            return "No fetch data available"
        }
    }
}

/// Overall health summary across all feeds.
struct HealthSummary: Equatable {
    let totalFeeds: Int
    let healthyCount: Int
    let degradedCount: Int
    let unhealthyCount: Int
    let staleCount: Int
    let unknownCount: Int
    let overallSuccessRate: Double
    let avgResponseTimeMs: Double
    let feedsNeedingAttention: Int
    
    /// Overall system status based on feed health distribution.
    var overallStatus: FeedHealthStatus {
        if totalFeeds == 0 { return .unknown }
        if unhealthyCount > 0 { return .unhealthy }
        if degradedCount > 0 || staleCount > 0 { return .degraded }
        if unknownCount == totalFeeds { return .unknown }
        return .healthy
    }
    
    /// Brief description of overall health.
    var overallDescription: String {
        if totalFeeds == 0 { return "No feeds configured" }
        if feedsNeedingAttention == 0 {
            return "All \(totalFeeds) feeds healthy"
        }
        return "\(feedsNeedingAttention) of \(totalFeeds) feed\(totalFeeds == 1 ? "" : "s") need\(feedsNeedingAttention == 1 ? "s" : "") attention"
    }
}

class FeedHealthManager {
    
    // MARK: - Singleton
    
    static let shared = FeedHealthManager()
    
    // MARK: - Configuration
    
    /// Maximum fetch records to store per feed (prevents unbounded growth).
    static let maxRecordsPerFeed = 100
    
    /// Maximum total records across all feeds.
    static let maxTotalRecords = 2000
    
    /// Number of days without new content before a feed is considered stale.
    static let staleDaysThreshold = 7
    
    /// Response time (ms) above which a feed is considered slow.
    static let slowResponseThresholdMs = 5000
    
    /// Minimum fetches required before classifying health (otherwise "unknown").
    static let minimumFetchesForClassification = 3
    
    // MARK: - Properties
    
    /// All fetch records, grouped by feed URL.
    private(set) var records: [String: [FetchRecord]] = [:]
    
    /// Last known story count per feed URL (for staleness detection).
    private(set) var lastStoryCount: [String: Int] = [:]
    
    /// Date when a feed last had new content (story count increased).
    private(set) var lastNewContentDate: [String: Date] = [:]
    
    /// Feed URL → feed name mapping for display purposes.
    private(set) var feedNames: [String: String] = [:]
    
    /// UserDefaults keys for persistence.
    private static let recordsKey = "FeedHealthManager.records"
    private static let storyCountKey = "FeedHealthManager.storyCount"
    private static let newContentDateKey = "FeedHealthManager.newContentDate"
    private static let feedNamesKey = "FeedHealthManager.feedNames"
    
    // MARK: - Initialization
    
    init() {
        loadData()
    }
    
    // MARK: - Recording
    
    /// Record the result of a feed fetch attempt.
    func recordFetch(
        feedURL: String,
        feedName: String,
        success: Bool,
        responseTimeMs: Int,
        storiesFound: Int,
        errorMessage: String? = nil
    ) {
        let record = FetchRecord(
            feedURL: feedURL,
            timestamp: Date(),
            success: success,
            responseTimeMs: max(0, responseTimeMs),
            errorMessage: success ? nil : errorMessage,
            storiesFound: max(0, storiesFound)
        )
        
        recordFetch(record: record, feedName: feedName)
    }
    
    /// Record a fetch with a pre-built FetchRecord (useful for testing).
    func recordFetch(record: FetchRecord, feedName: String) {
        let url = record.feedURL
        feedNames[url] = feedName
        
        var feedRecords = records[url] ?? []
        feedRecords.append(record)
        
        // Trim to max per feed
        if feedRecords.count > FeedHealthManager.maxRecordsPerFeed {
            feedRecords = Array(feedRecords.suffix(FeedHealthManager.maxRecordsPerFeed))
        }
        records[url] = feedRecords
        
        // Track story count for staleness detection
        if record.success && record.storiesFound > 0 {
            let previousCount = lastStoryCount[url]
            lastStoryCount[url] = record.storiesFound
            
            // If story count changed (new content), update the date
            if previousCount == nil || record.storiesFound != previousCount {
                lastNewContentDate[url] = record.timestamp
            }
        }
        
        // Enforce global record limit
        enforceGlobalLimit()
        
        saveData()
        NotificationCenter.default.post(name: .feedHealthDidChange, object: nil)
    }
    
    // MARK: - Health Reports
    
    /// Generate a health report for a specific feed.
    func healthReport(for feedURL: String) -> FeedHealthReport {
        let feedRecords = records[feedURL] ?? []
        let name = feedNames[feedURL] ?? feedURL
        
        guard !feedRecords.isEmpty else {
            return FeedHealthReport(
                feedURL: feedURL,
                feedName: name,
                status: .unknown,
                totalFetches: 0,
                successCount: 0,
                failureCount: 0,
                successRate: 0,
                avgResponseTimeMs: 0,
                minResponseTimeMs: 0,
                maxResponseTimeMs: 0,
                p95ResponseTimeMs: 0,
                lastFetchDate: nil,
                lastSuccessDate: nil,
                lastErrorDate: nil,
                lastErrorMessage: nil,
                consecutiveFailures: 0,
                lastStoryCount: 0,
                daysSinceNewContent: nil,
                recentErrors: []
            )
        }
        
        // Basic counts
        let successRecords = feedRecords.filter { $0.success }
        let failureRecords = feedRecords.filter { !$0.success }
        let successRate = Double(successRecords.count) / Double(feedRecords.count)
        
        // Response time statistics (from successful fetches only)
        let responseTimes = successRecords.map { $0.responseTimeMs }
        let avgResponseTime: Double
        let minResponseTime: Int
        let maxResponseTime: Int
        let p95ResponseTime: Int
        
        if responseTimes.isEmpty {
            avgResponseTime = 0
            minResponseTime = 0
            maxResponseTime = 0
            p95ResponseTime = 0
        } else {
            avgResponseTime = Double(responseTimes.reduce(0, +)) / Double(responseTimes.count)
            minResponseTime = responseTimes.min()!
            maxResponseTime = responseTimes.max()!
            let sorted = responseTimes.sorted()
            let p95Index = min(Int(Double(sorted.count) * 0.95), sorted.count - 1)
            p95ResponseTime = sorted[p95Index]
        }
        
        // Consecutive failures (from most recent backwards)
        var consecutiveFailures = 0
        for record in feedRecords.reversed() {
            if !record.success {
                consecutiveFailures += 1
            } else {
                break
            }
        }
        
        // Last dates
        let sortedByDate = feedRecords.sorted { $0.timestamp < $1.timestamp }
        let lastFetch = sortedByDate.last?.timestamp
        let lastSuccess = successRecords.sorted(by: { $0.timestamp < $1.timestamp }).last?.timestamp
        let lastError = failureRecords.sorted(by: { $0.timestamp < $1.timestamp }).last
        
        // Recent errors (last 5)
        let recentErrors = Array(failureRecords.suffix(5))
        
        // Staleness
        let daysSinceNew: Int?
        if let lastNewDate = lastNewContentDate[feedURL] {
            daysSinceNew = Calendar.current.dateComponents([.day], from: lastNewDate, to: Date()).day
        } else if !successRecords.isEmpty {
            // If we've fetched but never seen content change, use first fetch
            daysSinceNew = Calendar.current.dateComponents(
                [.day],
                from: successRecords.first!.timestamp,
                to: Date()
            ).day
        } else {
            daysSinceNew = nil
        }
        
        // Classify status
        let status = classifyHealth(
            successRate: successRate,
            totalFetches: feedRecords.count,
            consecutiveFailures: consecutiveFailures,
            avgResponseTimeMs: avgResponseTime,
            daysSinceNewContent: daysSinceNew
        )
        
        let storyCount = lastStoryCount[feedURL] ?? 0
        
        return FeedHealthReport(
            feedURL: feedURL,
            feedName: name,
            status: status,
            totalFetches: feedRecords.count,
            successCount: successRecords.count,
            failureCount: failureRecords.count,
            successRate: successRate,
            avgResponseTimeMs: avgResponseTime,
            minResponseTimeMs: minResponseTime,
            maxResponseTimeMs: maxResponseTime,
            p95ResponseTimeMs: p95ResponseTime,
            lastFetchDate: lastFetch,
            lastSuccessDate: lastSuccess,
            lastErrorDate: lastError?.timestamp,
            lastErrorMessage: lastError?.errorMessage,
            consecutiveFailures: consecutiveFailures,
            lastStoryCount: storyCount,
            daysSinceNewContent: daysSinceNew,
            recentErrors: recentErrors
        )
    }
    
    /// Generate health reports for all tracked feeds, sorted worst-first.
    func allHealthReports() -> [FeedHealthReport] {
        let urls = Set(records.keys).union(Set(feedNames.keys))
        return urls.map { healthReport(for: $0) }
            .sorted { $0.status.priority < $1.status.priority }
    }
    
    /// Generate an overall health summary.
    func healthSummary() -> HealthSummary {
        let reports = allHealthReports()
        
        let healthyCount = reports.filter { $0.status == .healthy }.count
        let degradedCount = reports.filter { $0.status == .degraded }.count
        let unhealthyCount = reports.filter { $0.status == .unhealthy }.count
        let staleCount = reports.filter { $0.status == .stale }.count
        let unknownCount = reports.filter { $0.status == .unknown }.count
        
        // Overall success rate (weighted by number of fetches)
        let totalFetches = reports.reduce(0) { $0 + $1.totalFetches }
        let totalSuccesses = reports.reduce(0) { $0 + $1.successCount }
        let overallSuccessRate = totalFetches > 0 ? Double(totalSuccesses) / Double(totalFetches) : 0
        
        // Average response time (weighted by number of successful fetches)
        let totalWeightedTime = reports.reduce(0.0) { $0 + $1.avgResponseTimeMs * Double($1.successCount) }
        let avgResponseTime = totalSuccesses > 0 ? totalWeightedTime / Double(totalSuccesses) : 0
        
        let needingAttention = reports.filter { $0.needsAttention }.count
        
        return HealthSummary(
            totalFeeds: reports.count,
            healthyCount: healthyCount,
            degradedCount: degradedCount,
            unhealthyCount: unhealthyCount,
            staleCount: staleCount,
            unknownCount: unknownCount,
            overallSuccessRate: overallSuccessRate,
            avgResponseTimeMs: avgResponseTime,
            feedsNeedingAttention: needingAttention
        )
    }
    
    // MARK: - Queries
    
    /// Get feeds that need user attention (unhealthy, degraded, or failing).
    func feedsNeedingAttention() -> [FeedHealthReport] {
        return allHealthReports().filter { $0.needsAttention }
    }
    
    /// Get the total number of fetch records across all feeds.
    func totalRecordCount() -> Int {
        return records.values.reduce(0) { $0 + $1.count }
    }
    
    /// Get the number of tracked feeds.
    func trackedFeedCount() -> Int {
        return records.count
    }
    
    /// Get fetch history for a specific feed, newest first.
    func fetchHistory(for feedURL: String, limit: Int = 20) -> [FetchRecord] {
        let feedRecords = records[feedURL] ?? []
        return Array(feedRecords.suffix(limit).reversed())
    }
    
    /// Get the most recent error across all feeds.
    func mostRecentError() -> FetchRecord? {
        return records.values
            .flatMap { $0 }
            .filter { !$0.success }
            .max(by: { $0.timestamp < $1.timestamp })
    }
    
    /// Get average response time across all feeds (from recent successful fetches).
    func overallAvgResponseTimeMs() -> Double {
        let allSuccessful = records.values
            .flatMap { $0 }
            .filter { $0.success }
        guard !allSuccessful.isEmpty else { return 0 }
        let total = allSuccessful.reduce(0) { $0 + $1.responseTimeMs }
        return Double(total) / Double(allSuccessful.count)
    }
    
    // MARK: - Health Classification
    
    /// Classify a feed's health status based on its metrics.
    private func classifyHealth(
        successRate: Double,
        totalFetches: Int,
        consecutiveFailures: Int,
        avgResponseTimeMs: Double,
        daysSinceNewContent: Int?
    ) -> FeedHealthStatus {
        // Not enough data to classify
        if totalFetches < FeedHealthManager.minimumFetchesForClassification {
            return .unknown
        }
        
        // Staleness check (only if feed was previously working)
        if let days = daysSinceNewContent,
           days >= FeedHealthManager.staleDaysThreshold,
           successRate >= 0.5 {
            return .stale
        }
        
        // Unhealthy: very low success rate or many consecutive failures
        if successRate < 0.5 || consecutiveFailures >= 5 {
            return .unhealthy
        }
        
        // Degraded: moderate issues
        if successRate < 0.9 ||
           consecutiveFailures >= 2 ||
           avgResponseTimeMs > Double(FeedHealthManager.slowResponseThresholdMs) {
            return .degraded
        }
        
        return .healthy
    }
    
    // MARK: - Data Management
    
    /// Remove all health data for a specific feed.
    func clearFeed(_ feedURL: String) {
        records.removeValue(forKey: feedURL)
        lastStoryCount.removeValue(forKey: feedURL)
        lastNewContentDate.removeValue(forKey: feedURL)
        feedNames.removeValue(forKey: feedURL)
        saveData()
        NotificationCenter.default.post(name: .feedHealthDidChange, object: nil)
    }
    
    /// Remove all health data.
    func clearAll() {
        records.removeAll()
        lastStoryCount.removeAll()
        lastNewContentDate.removeAll()
        feedNames.removeAll()
        saveData()
        NotificationCenter.default.post(name: .feedHealthDidChange, object: nil)
    }
    
    /// Enforce the global record limit by dropping oldest records from
    /// the feeds with the most records.
    private func enforceGlobalLimit() {
        var total = totalRecordCount()
        while total > FeedHealthManager.maxTotalRecords {
            // Find the feed with the most records
            guard let maxFeed = records.max(by: { $0.value.count < $1.value.count }) else { break }
            let url = maxFeed.key
            var feedRecords = maxFeed.value
            
            // Drop the oldest half from this feed
            let dropCount = max(1, feedRecords.count / 2)
            feedRecords = Array(feedRecords.dropFirst(dropCount))
            records[url] = feedRecords
            total = totalRecordCount()
        }
    }
    
    // MARK: - Persistence
    
    private func saveData() {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .secondsSince1970
        
        if let recordsData = try? encoder.encode(records) {
            UserDefaults.standard.set(recordsData, forKey: FeedHealthManager.recordsKey)
        }
        if let storyCountData = try? encoder.encode(lastStoryCount) {
            UserDefaults.standard.set(storyCountData, forKey: FeedHealthManager.storyCountKey)
        }
        if let dateData = try? encoder.encode(lastNewContentDate) {
            UserDefaults.standard.set(dateData, forKey: FeedHealthManager.newContentDateKey)
        }
        if let namesData = try? encoder.encode(feedNames) {
            UserDefaults.standard.set(namesData, forKey: FeedHealthManager.feedNamesKey)
        }
    }
    
    private func loadData() {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        
        if let data = UserDefaults.standard.data(forKey: FeedHealthManager.recordsKey),
           let loaded = try? decoder.decode([String: [FetchRecord]].self, from: data) {
            records = loaded
        }
        if let data = UserDefaults.standard.data(forKey: FeedHealthManager.storyCountKey),
           let loaded = try? decoder.decode([String: Int].self, from: data) {
            lastStoryCount = loaded
        }
        if let data = UserDefaults.standard.data(forKey: FeedHealthManager.newContentDateKey),
           let loaded = try? decoder.decode([String: Date].self, from: data) {
            lastNewContentDate = loaded
        }
        if let data = UserDefaults.standard.data(forKey: FeedHealthManager.feedNamesKey),
           let loaded = try? decoder.decode([String: String].self, from: data) {
            feedNames = loaded
        }
    }
    
    /// Force reload from storage (useful for testing).
    func reload() {
        loadData()
    }
}
