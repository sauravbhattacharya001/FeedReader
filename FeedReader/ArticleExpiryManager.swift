//
//  ArticleExpiryManager.swift
//  FeedReader
//
//  Automatic cleanup of stale articles based on configurable expiry
//  policies. Users can define rules per-feed or globally: expire after
//  N days, keep bookmarked/unread articles, set storage limits, and
//  preview what would be removed before committing.
//
//  Features:
//  - Global and per-feed expiry policies (age, read status, count limits)
//  - Dry-run preview before deletion
//  - Bookmarked/starred articles are always protected
//  - Storage usage estimation
//  - Expiry event log for auditing
//  - JSON persistence for policies and logs
//

import Foundation

// MARK: - Notifications

extension Notification.Name {
    static let articleExpiryDidRun = Notification.Name("ArticleExpiryDidRunNotification")
    static let expiryPoliciesDidChange = Notification.Name("ExpiryPoliciesDidChangeNotification")
}

// MARK: - Data Types

/// Defines when and how articles should expire.
struct ExpiryPolicy: Codable, Equatable {
    /// Unique identifier for the policy.
    let id: String
    /// Optional feed name this policy applies to. Nil means global.
    let feedName: String?
    /// Maximum age in days. Articles older than this are candidates for removal.
    var maxAgeDays: Int
    /// If true, only expire articles that have been read.
    var onlyExpireRead: Bool
    /// Maximum number of articles to keep (per feed or globally). 0 = unlimited.
    var maxArticleCount: Int
    /// If true, bookmarked articles are never expired.
    var protectBookmarked: Bool
    /// If true, articles with highlights or notes are never expired.
    var protectAnnotated: Bool
    /// Whether this policy is active.
    var isEnabled: Bool
    /// When this policy was created.
    let createdAt: Date
    /// When this policy was last modified.
    var modifiedAt: Date
    
    init(id: String = UUID().uuidString,
         feedName: String? = nil,
         maxAgeDays: Int = 30,
         onlyExpireRead: Bool = true,
         maxArticleCount: Int = 0,
         protectBookmarked: Bool = true,
         protectAnnotated: Bool = true,
         isEnabled: Bool = true) {
        self.id = id
        self.feedName = feedName
        self.maxAgeDays = maxAgeDays
        self.onlyExpireRead = onlyExpireRead
        self.maxArticleCount = maxArticleCount
        self.protectBookmarked = protectBookmarked
        self.protectAnnotated = protectAnnotated
        self.isEnabled = isEnabled
        let now = Date()
        self.createdAt = now
        self.modifiedAt = now
    }
}

/// Represents a single article candidate for expiry evaluation.
struct ExpiryCandidate: Codable, Equatable {
    let link: String
    let title: String
    let feedName: String
    let publishedDate: Date
    let isRead: Bool
    let isBookmarked: Bool
    let isAnnotated: Bool
    /// The reason this article is a candidate for removal.
    let reason: ExpiryReason
    /// Age of the article in days.
    let ageDays: Int
}

/// Why an article was flagged for expiry.
enum ExpiryReason: String, Codable {
    case tooOld = "exceeded_max_age"
    case overCountLimit = "exceeded_max_count"
    case both = "exceeded_age_and_count"
}

/// Result of running an expiry sweep (either dry-run or actual).
struct ExpirySweepResult: Codable {
    let timestamp: Date
    let isDryRun: Bool
    let policyId: String
    let candidateCount: Int
    let removedCount: Int
    let protectedCount: Int
    let candidates: [ExpiryCandidate]
    /// Estimated bytes freed (rough estimate based on title + body length).
    let estimatedBytesFreed: Int
}

/// A log entry for completed expiry runs.
struct ExpiryLogEntry: Codable {
    let timestamp: Date
    let policyId: String
    let policyFeedName: String?
    let removedCount: Int
    let protectedCount: Int
    let estimatedBytesFreed: Int
}

// MARK: - ArticleExpiryManager

/// Manages article expiry policies and executes cleanup sweeps.
class ArticleExpiryManager {
    
    // MARK: - Singleton
    
    static let shared = ArticleExpiryManager()
    
    // MARK: - Storage
    
    private let policiesKey = "ArticleExpiryPolicies"
    private let logKey = "ArticleExpiryLog"
    private let lastRunKey = "ArticleExpiryLastRun"
    
    private let policiesStore = UserDefaultsCodableStore<[ExpiryPolicy]>(key: "ArticleExpiryPolicies")
    private let logStore = UserDefaultsCodableStore<[ExpiryLogEntry]>(key: "ArticleExpiryLog")
    private let lastRunStore = UserDefaultsCodableStore<Date>(key: "ArticleExpiryLastRun")
    
    // MARK: - Properties
    
    /// All configured expiry policies.
    private(set) var policies: [ExpiryPolicy] = []
    
    /// Log of past expiry runs.
    private(set) var expiryLog: [ExpiryLogEntry] = []
    
    /// When the last expiry sweep ran.
    private(set) var lastRunDate: Date?
    
    // MARK: - Init
    
    init() {
        loadPolicies()
        loadLog()
        lastRunDate = lastRunStore.load()
    }
    
    // MARK: - Policy Management
    
    /// Add a new expiry policy.
    func addPolicy(_ policy: ExpiryPolicy) {
        policies.append(policy)
        savePolicies()
        NotificationCenter.default.post(name: .expiryPoliciesDidChange, object: self)
    }
    
    /// Update an existing policy by ID.
    func updatePolicy(_ policy: ExpiryPolicy) {
        guard let index = policies.firstIndex(where: { $0.id == policy.id }) else { return }
        var updated = policy
        updated.modifiedAt = Date()
        policies[index] = updated
        savePolicies()
        NotificationCenter.default.post(name: .expiryPoliciesDidChange, object: self)
    }
    
    /// Remove a policy by ID.
    func removePolicy(id: String) {
        policies.removeAll { $0.id == id }
        savePolicies()
        NotificationCenter.default.post(name: .expiryPoliciesDidChange, object: self)
    }
    
    /// Get the effective policy for a given feed (per-feed first, then global).
    func effectivePolicy(forFeed feedName: String) -> ExpiryPolicy? {
        // Per-feed policy takes precedence
        if let feedPolicy = policies.first(where: { $0.feedName == feedName && $0.isEnabled }) {
            return feedPolicy
        }
        // Fall back to global policy
        return policies.first(where: { $0.feedName == nil && $0.isEnabled })
    }
    
    /// Create a default global policy.
    func createDefaultPolicy() -> ExpiryPolicy {
        return ExpiryPolicy(
            feedName: nil,
            maxAgeDays: 30,
            onlyExpireRead: true,
            maxArticleCount: 500,
            protectBookmarked: true,
            protectAnnotated: true
        )
    }
    
    // MARK: - Expiry Evaluation
    
    /// Evaluate articles against a policy and return candidates for removal.
    /// This is a pure evaluation — does not remove anything.
    func evaluateCandidates(
        articles: [(link: String, title: String, feedName: String, publishedDate: Date,
                     body: String, isRead: Bool, isBookmarked: Bool, isAnnotated: Bool)],
        policy: ExpiryPolicy,
        referenceDate: Date = Date()
    ) -> [ExpiryCandidate] {
        guard policy.isEnabled else { return [] }
        
        // Filter to relevant feed if policy is feed-specific
        let relevant: [(link: String, title: String, feedName: String, publishedDate: Date,
                         body: String, isRead: Bool, isBookmarked: Bool, isAnnotated: Bool)]
        if let feed = policy.feedName {
            relevant = articles.filter { $0.feedName == feed }
        } else {
            relevant = articles
        }
        
        var candidates: [ExpiryCandidate] = []
        let calendar = Calendar.current
        
        // Sort by date ascending for count-based evaluation
        let sorted = relevant.sorted { $0.publishedDate < $1.publishedDate }
        
        // Determine which are over the age limit
        let ageCandidateLinks = Set(sorted.compactMap { article -> String? in
            let days = calendar.dateComponents([.day], from: article.publishedDate, to: referenceDate).day ?? 0
            return days > policy.maxAgeDays ? article.link : nil
        })
        
        // Determine which are over the count limit
        let countCandidateLinks: Set<String>
        if policy.maxArticleCount > 0 && sorted.count > policy.maxArticleCount {
            let overflow = sorted.count - policy.maxArticleCount
            countCandidateLinks = Set(sorted.prefix(overflow).map { $0.link })
        } else {
            countCandidateLinks = []
        }
        
        let allCandidateLinks = ageCandidateLinks.union(countCandidateLinks)
        
        for article in sorted where allCandidateLinks.contains(article.link) {
            // Skip protected articles
            if policy.protectBookmarked && article.isBookmarked { continue }
            if policy.protectAnnotated && article.isAnnotated { continue }
            if policy.onlyExpireRead && !article.isRead { continue }
            
            let days = calendar.dateComponents([.day], from: article.publishedDate, to: referenceDate).day ?? 0
            
            let reason: ExpiryReason
            let inAge = ageCandidateLinks.contains(article.link)
            let inCount = countCandidateLinks.contains(article.link)
            if inAge && inCount {
                reason = .both
            } else if inAge {
                reason = .tooOld
            } else {
                reason = .overCountLimit
            }
            
            candidates.append(ExpiryCandidate(
                link: article.link,
                title: article.title,
                feedName: article.feedName,
                publishedDate: article.publishedDate,
                isRead: article.isRead,
                isBookmarked: article.isBookmarked,
                isAnnotated: article.isAnnotated,
                reason: reason,
                ageDays: days
            ))
        }
        
        return candidates
    }
    
    /// Run a dry-run sweep — returns what would be removed without changing anything.
    func dryRun(
        articles: [(link: String, title: String, feedName: String, publishedDate: Date,
                     body: String, isRead: Bool, isBookmarked: Bool, isAnnotated: Bool)],
        policy: ExpiryPolicy,
        referenceDate: Date = Date()
    ) -> ExpirySweepResult {
        let candidates = evaluateCandidates(articles: articles, policy: policy, referenceDate: referenceDate)
        
        // Estimate bytes: rough heuristic based on title length
        let estimatedBytes = candidates.reduce(0) { sum, c in
            sum + (c.title.utf8.count * 20) // ~20x title length as rough body estimate
        }
        
        return ExpirySweepResult(
            timestamp: referenceDate,
            isDryRun: true,
            policyId: policy.id,
            candidateCount: candidates.count,
            removedCount: 0,
            protectedCount: 0,
            candidates: candidates,
            estimatedBytesFreed: estimatedBytes
        )
    }
    
    /// Execute an actual expiry sweep. Returns links of removed articles.
    /// The caller is responsible for actually deleting/archiving the articles
    /// using the returned links.
    func executeSweep(
        articles: [(link: String, title: String, feedName: String, publishedDate: Date,
                     body: String, isRead: Bool, isBookmarked: Bool, isAnnotated: Bool)],
        policy: ExpiryPolicy,
        referenceDate: Date = Date()
    ) -> ExpirySweepResult {
        let candidates = evaluateCandidates(articles: articles, policy: policy, referenceDate: referenceDate)
        
        let estimatedBytes = candidates.reduce(0) { sum, c in
            sum + (c.title.utf8.count * 20)
        }
        
        // Log the run
        let logEntry = ExpiryLogEntry(
            timestamp: referenceDate,
            policyId: policy.id,
            policyFeedName: policy.feedName,
            removedCount: candidates.count,
            protectedCount: 0,
            estimatedBytesFreed: estimatedBytes
        )
        expiryLog.append(logEntry)
        if expiryLog.count > 100 {
            expiryLog = Array(expiryLog.suffix(100))
        }
        saveLog()
        
        lastRunDate = referenceDate
        lastRunStore.save(referenceDate)
        
        let result = ExpirySweepResult(
            timestamp: referenceDate,
            isDryRun: false,
            policyId: policy.id,
            candidateCount: candidates.count,
            removedCount: candidates.count,
            protectedCount: 0,
            candidates: candidates,
            estimatedBytesFreed: estimatedBytes
        )
        
        NotificationCenter.default.post(name: .articleExpiryDidRun, object: self,
                                        userInfo: ["result": result])
        return result
    }
    
    // MARK: - Statistics
    
    /// Summary statistics across all expiry log entries.
    func lifetimeStats() -> (totalRuns: Int, totalRemoved: Int, totalBytesFreed: Int) {
        let runs = expiryLog.count
        let removed = expiryLog.reduce(0) { $0 + $1.removedCount }
        let bytes = expiryLog.reduce(0) { $0 + $1.estimatedBytesFreed }
        return (runs, removed, bytes)
    }
    
    /// Get the most recent N log entries.
    func recentLog(limit: Int = 10) -> [ExpiryLogEntry] {
        return Array(expiryLog.suffix(limit))
    }
    
    // MARK: - Storage Usage Estimation
    
    /// Estimate total storage used by articles (rough heuristic).
    func estimateStorageUsage(
        articles: [(link: String, title: String, body: String)]
    ) -> (articleCount: Int, estimatedBytes: Int, formattedSize: String) {
        let count = articles.count
        let bytes = articles.reduce(0) { sum, a in
            sum + a.title.utf8.count + a.body.utf8.count + a.link.utf8.count
        }
        let formatted: String
        if bytes < 1024 {
            formatted = "\(bytes) B"
        } else if bytes < 1024 * 1024 {
            formatted = String(format: "%.1f KB", Double(bytes) / 1024.0)
        } else {
            formatted = String(format: "%.1f MB", Double(bytes) / (1024.0 * 1024.0))
        }
        return (count, bytes, formatted)
    }
    
    // MARK: - Persistence
    
    private func savePolicies() {
        policiesStore.save(policies)
    }
    
    private func loadPolicies() {
        policies = policiesStore.load() ?? []
    }
    
    private func saveLog() {
        logStore.save(expiryLog)
    }
    
    private func loadLog() {
        expiryLog = logStore.load() ?? []
    }
    
    /// Reset all policies and logs (for testing).
    func resetAll() {
        policies = []
        expiryLog = []
        lastRunDate = nil
        policiesStore.remove()
        logStore.remove()
        lastRunStore.remove()
    }
}
