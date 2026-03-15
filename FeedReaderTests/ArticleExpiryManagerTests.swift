//
//  ArticleExpiryManagerTests.swift
//  FeedReaderTests
//
//  Tests for ArticleExpiryManager — policy CRUD, candidate evaluation,
//  dry-run, sweep execution, storage estimation, and log tracking.
//

import XCTest
@testable import FeedReader

class ArticleExpiryManagerTests: XCTestCase {
    
    var manager: ArticleExpiryManager!
    
    override func setUp() {
        super.setUp()
        manager = ArticleExpiryManager()
        manager.resetAll()
    }
    
    override func tearDown() {
        manager.resetAll()
        super.tearDown()
    }
    
    // MARK: - Helpers
    
    private func makeArticle(
        link: String = "https://example.com/article",
        title: String = "Test Article",
        feedName: String = "TestFeed",
        daysOld: Int = 0,
        body: String = "Article body text",
        isRead: Bool = true,
        isBookmarked: Bool = false,
        isAnnotated: Bool = false,
        referenceDate: Date = Date()
    ) -> (link: String, title: String, feedName: String, publishedDate: Date,
          body: String, isRead: Bool, isBookmarked: Bool, isAnnotated: Bool) {
        let published = Calendar.current.date(byAdding: .day, value: -daysOld, to: referenceDate)!
        return (link, title, feedName, published, body, isRead, isBookmarked, isAnnotated)
    }
    
    // MARK: - Policy CRUD Tests
    
    func testAddPolicy() {
        let policy = ExpiryPolicy(feedName: nil, maxAgeDays: 30)
        manager.addPolicy(policy)
        XCTAssertEqual(manager.policies.count, 1)
        XCTAssertEqual(manager.policies[0].maxAgeDays, 30)
    }
    
    func testRemovePolicy() {
        let policy = ExpiryPolicy(id: "test-1", feedName: nil, maxAgeDays: 14)
        manager.addPolicy(policy)
        XCTAssertEqual(manager.policies.count, 1)
        manager.removePolicy(id: "test-1")
        XCTAssertEqual(manager.policies.count, 0)
    }
    
    func testUpdatePolicy() {
        var policy = ExpiryPolicy(id: "test-2", feedName: nil, maxAgeDays: 30)
        manager.addPolicy(policy)
        policy.maxAgeDays = 7
        manager.updatePolicy(policy)
        XCTAssertEqual(manager.policies[0].maxAgeDays, 7)
    }
    
    func testDefaultPolicy() {
        let policy = manager.createDefaultPolicy()
        XCTAssertNil(policy.feedName)
        XCTAssertEqual(policy.maxAgeDays, 30)
        XCTAssertTrue(policy.onlyExpireRead)
        XCTAssertTrue(policy.protectBookmarked)
        XCTAssertTrue(policy.protectAnnotated)
        XCTAssertEqual(policy.maxArticleCount, 500)
    }
    
    // MARK: - Effective Policy
    
    func testEffectivePolicyFeedOverridesGlobal() {
        let global = ExpiryPolicy(feedName: nil, maxAgeDays: 30)
        let feedSpecific = ExpiryPolicy(feedName: "Reuters", maxAgeDays: 7)
        manager.addPolicy(global)
        manager.addPolicy(feedSpecific)
        
        let effective = manager.effectivePolicy(forFeed: "Reuters")
        XCTAssertEqual(effective?.maxAgeDays, 7)
        XCTAssertEqual(effective?.feedName, "Reuters")
    }
    
    func testEffectivePolicyFallsBackToGlobal() {
        let global = ExpiryPolicy(feedName: nil, maxAgeDays: 30)
        manager.addPolicy(global)
        
        let effective = manager.effectivePolicy(forFeed: "UnknownFeed")
        XCTAssertNil(effective?.feedName)
        XCTAssertEqual(effective?.maxAgeDays, 30)
    }
    
    // MARK: - Candidate Evaluation
    
    func testOldReadArticlesAreExpiryCandidates() {
        let ref = Date()
        let policy = ExpiryPolicy(maxAgeDays: 7, onlyExpireRead: true)
        let articles = [
            makeArticle(link: "a1", daysOld: 10, isRead: true, referenceDate: ref),
            makeArticle(link: "a2", daysOld: 3, isRead: true, referenceDate: ref),
            makeArticle(link: "a3", daysOld: 10, isRead: false, referenceDate: ref),
        ]
        
        let candidates = manager.evaluateCandidates(articles: articles, policy: policy, referenceDate: ref)
        XCTAssertEqual(candidates.count, 1)
        XCTAssertEqual(candidates[0].link, "a1")
        XCTAssertEqual(candidates[0].reason, .tooOld)
    }
    
    func testBookmarkedArticlesAreProtected() {
        let ref = Date()
        let policy = ExpiryPolicy(maxAgeDays: 7, protectBookmarked: true)
        let articles = [
            makeArticle(link: "a1", daysOld: 10, isRead: true, isBookmarked: true, referenceDate: ref),
        ]
        
        let candidates = manager.evaluateCandidates(articles: articles, policy: policy, referenceDate: ref)
        XCTAssertTrue(candidates.isEmpty)
    }
    
    func testAnnotatedArticlesAreProtected() {
        let ref = Date()
        let policy = ExpiryPolicy(maxAgeDays: 7, protectAnnotated: true)
        let articles = [
            makeArticle(link: "a1", daysOld: 10, isRead: true, isAnnotated: true, referenceDate: ref),
        ]
        
        let candidates = manager.evaluateCandidates(articles: articles, policy: policy, referenceDate: ref)
        XCTAssertTrue(candidates.isEmpty)
    }
    
    func testCountLimitCandidates() {
        let ref = Date()
        let policy = ExpiryPolicy(maxAgeDays: 365, onlyExpireRead: false, maxArticleCount: 2)
        let articles = [
            makeArticle(link: "a1", daysOld: 30, referenceDate: ref),
            makeArticle(link: "a2", daysOld: 20, referenceDate: ref),
            makeArticle(link: "a3", daysOld: 10, referenceDate: ref),
            makeArticle(link: "a4", daysOld: 5, referenceDate: ref),
        ]
        
        let candidates = manager.evaluateCandidates(articles: articles, policy: policy, referenceDate: ref)
        // Oldest 2 should be candidates (4 articles - 2 max = 2 overflow)
        XCTAssertEqual(candidates.count, 2)
        let links = candidates.map { $0.link }
        XCTAssertTrue(links.contains("a1"))
        XCTAssertTrue(links.contains("a2"))
    }
    
    func testDisabledPolicyReturnsNoCandidates() {
        let ref = Date()
        let policy = ExpiryPolicy(maxAgeDays: 1, isEnabled: false)
        let articles = [makeArticle(link: "a1", daysOld: 100, referenceDate: ref)]
        
        let candidates = manager.evaluateCandidates(articles: articles, policy: policy, referenceDate: ref)
        XCTAssertTrue(candidates.isEmpty)
    }
    
    func testFeedSpecificPolicyOnlyAffectsTargetFeed() {
        let ref = Date()
        let policy = ExpiryPolicy(feedName: "Reuters", maxAgeDays: 7, onlyExpireRead: false)
        let articles = [
            makeArticle(link: "a1", feedName: "Reuters", daysOld: 10, referenceDate: ref),
            makeArticle(link: "a2", feedName: "BBC", daysOld: 10, referenceDate: ref),
        ]
        
        let candidates = manager.evaluateCandidates(articles: articles, policy: policy, referenceDate: ref)
        XCTAssertEqual(candidates.count, 1)
        XCTAssertEqual(candidates[0].feedName, "Reuters")
    }
    
    // MARK: - Dry Run
    
    func testDryRunDoesNotRemove() {
        let ref = Date()
        let policy = ExpiryPolicy(maxAgeDays: 7, onlyExpireRead: false)
        let articles = [
            makeArticle(link: "a1", daysOld: 10, referenceDate: ref),
            makeArticle(link: "a2", daysOld: 10, referenceDate: ref),
        ]
        
        let result = manager.dryRun(articles: articles, policy: policy, referenceDate: ref)
        XCTAssertTrue(result.isDryRun)
        XCTAssertEqual(result.candidateCount, 2)
        XCTAssertEqual(result.removedCount, 0)
        XCTAssertTrue(result.estimatedBytesFreed > 0)
    }
    
    // MARK: - Execute Sweep
    
    func testExecuteSweepLogsResults() {
        let ref = Date()
        let policy = ExpiryPolicy(id: "sweep-test", maxAgeDays: 7, onlyExpireRead: false)
        let articles = [
            makeArticle(link: "a1", daysOld: 10, referenceDate: ref),
        ]
        
        let result = manager.executeSweep(articles: articles, policy: policy, referenceDate: ref)
        XCTAssertFalse(result.isDryRun)
        XCTAssertEqual(result.removedCount, 1)
        XCTAssertEqual(manager.expiryLog.count, 1)
        XCTAssertEqual(manager.expiryLog[0].policyId, "sweep-test")
        XCTAssertNotNil(manager.lastRunDate)
    }
    
    // MARK: - Storage Estimation
    
    func testStorageEstimation() {
        let articles = [
            (link: "https://a.com", title: "Hello World", body: "Some body text here"),
            (link: "https://b.com", title: "Another Article", body: "More content"),
        ]
        
        let usage = manager.estimateStorageUsage(articles: articles)
        XCTAssertEqual(usage.articleCount, 2)
        XCTAssertTrue(usage.estimatedBytes > 0)
        XCTAssertFalse(usage.formattedSize.isEmpty)
    }
    
    // MARK: - Lifetime Stats
    
    func testLifetimeStats() {
        let ref = Date()
        let policy = ExpiryPolicy(maxAgeDays: 1, onlyExpireRead: false)
        let articles = [
            makeArticle(link: "a1", daysOld: 5, referenceDate: ref),
            makeArticle(link: "a2", daysOld: 5, referenceDate: ref),
        ]
        
        _ = manager.executeSweep(articles: articles, policy: policy, referenceDate: ref)
        _ = manager.executeSweep(articles: articles, policy: policy, referenceDate: ref)
        
        let stats = manager.lifetimeStats()
        XCTAssertEqual(stats.totalRuns, 2)
        XCTAssertEqual(stats.totalRemoved, 4)
        XCTAssertTrue(stats.totalBytesFreed > 0)
    }
    
    func testRecentLog() {
        let ref = Date()
        let policy = ExpiryPolicy(maxAgeDays: 1, onlyExpireRead: false)
        let articles = [makeArticle(link: "a1", daysOld: 5, referenceDate: ref)]
        
        _ = manager.executeSweep(articles: articles, policy: policy, referenceDate: ref)
        
        let recent = manager.recentLog(limit: 5)
        XCTAssertEqual(recent.count, 1)
    }
    
    // MARK: - Reset
    
    func testResetClearsEverything() {
        let policy = ExpiryPolicy(maxAgeDays: 7)
        manager.addPolicy(policy)
        manager.resetAll()
        
        XCTAssertTrue(manager.policies.isEmpty)
        XCTAssertTrue(manager.expiryLog.isEmpty)
        XCTAssertNil(manager.lastRunDate)
    }
}
