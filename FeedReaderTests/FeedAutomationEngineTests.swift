//
//  FeedAutomationEngineTests.swift
//  FeedReaderTests
//

import XCTest
@testable import FeedReader

class FeedAutomationEngineTests: XCTestCase {
    
    var engine: FeedAutomationEngine!
    
    override func setUp() {
        super.setUp()
        engine = FeedAutomationEngine()
    }
    
    // MARK: - MatchMode Tests
    
    func testMatchModeContains() {
        XCTAssertTrue(MatchMode.contains.matches("Hello World", pattern: "world"))
        XCTAssertTrue(MatchMode.contains.matches("Hello World", pattern: "HELLO"))
        XCTAssertFalse(MatchMode.contains.matches("Hello", pattern: "xyz"))
    }
    
    func testMatchModeExactMatch() {
        XCTAssertTrue(MatchMode.exactMatch.matches("hello", pattern: "HELLO"))
        XCTAssertFalse(MatchMode.exactMatch.matches("hello world", pattern: "hello"))
    }
    
    func testMatchModeStartsWith() {
        XCTAssertTrue(MatchMode.startsWith.matches("Hello World", pattern: "hello"))
        XCTAssertFalse(MatchMode.startsWith.matches("Hello World", pattern: "world"))
    }
    
    func testMatchModeEndsWith() {
        XCTAssertTrue(MatchMode.endsWith.matches("Hello World", pattern: "world"))
        XCTAssertFalse(MatchMode.endsWith.matches("Hello World", pattern: "hello"))
    }
    
    func testMatchModeRegex() {
        XCTAssertTrue(MatchMode.regex.matches("version 2.5.3", pattern: "\\d+\\.\\d+\\.\\d+"))
        XCTAssertFalse(MatchMode.regex.matches("no version here", pattern: "\\d+\\.\\d+\\.\\d+"))
    }
    
    func testMatchModeRegexInvalidPattern() {
        XCTAssertFalse(MatchMode.regex.matches("test", pattern: "[invalid"))
    }
    
    // MARK: - AutomationCondition Tests
    
    func testConditionTitleField() {
        let cond = AutomationCondition(field: .title, pattern: "breaking")
        XCTAssertTrue(cond.evaluate(title: "Breaking News", body: "", link: "", feedName: ""))
        XCTAssertFalse(cond.evaluate(title: "Regular Update", body: "breaking stuff", link: "", feedName: ""))
    }
    
    func testConditionBodyField() {
        let cond = AutomationCondition(field: .body, pattern: "important")
        XCTAssertTrue(cond.evaluate(title: "", body: "This is important", link: "", feedName: ""))
        XCTAssertFalse(cond.evaluate(title: "important", body: "nothing", link: "", feedName: ""))
    }
    
    func testConditionLinkField() {
        let cond = AutomationCondition(field: .link, pattern: "github.com")
        XCTAssertTrue(cond.evaluate(title: "", body: "", link: "https://github.com/test", feedName: ""))
        XCTAssertFalse(cond.evaluate(title: "", body: "", link: "https://example.com", feedName: ""))
    }
    
    func testConditionFeedNameField() {
        let cond = AutomationCondition(field: .feedName, pattern: "TechCrunch")
        XCTAssertTrue(cond.evaluate(title: "", body: "", link: "", feedName: "TechCrunch"))
        XCTAssertFalse(cond.evaluate(title: "", body: "", link: "", feedName: "BBC News"))
    }
    
    func testConditionAnyField() {
        let cond = AutomationCondition(field: .any, pattern: "swift")
        XCTAssertTrue(cond.evaluate(title: "Swift 6.0 Released", body: "", link: "", feedName: ""))
        XCTAssertTrue(cond.evaluate(title: "", body: "Learn Swift programming", link: "", feedName: ""))
        XCTAssertTrue(cond.evaluate(title: "", body: "", link: "", feedName: "Swift Blog"))
        XCTAssertFalse(cond.evaluate(title: "Rust News", body: "Go update", link: "rust.dev", feedName: "DevBlog"))
    }
    
    func testConditionNegate() {
        let cond = AutomationCondition(field: .title, pattern: "sponsored", negate: true)
        XCTAssertTrue(cond.evaluate(title: "Regular Article", body: "", link: "", feedName: ""))
        XCTAssertFalse(cond.evaluate(title: "Sponsored Content", body: "", link: "", feedName: ""))
    }
    
    func testConditionRegexMatch() {
        let cond = AutomationCondition(field: .title, mode: .regex, pattern: "^\\[.*\\]")
        XCTAssertTrue(cond.evaluate(title: "[Update] New Version", body: "", link: "", feedName: ""))
        XCTAssertFalse(cond.evaluate(title: "No Brackets", body: "", link: "", feedName: ""))
    }
    
    // MARK: - ConditionGroup Tests
    
    func testConditionGroupAllLogic() {
        let group = ConditionGroup(logic: .all, conditions: [
            AutomationCondition(field: .title, pattern: "swift"),
            AutomationCondition(field: .feedName, pattern: "apple")
        ])
        XCTAssertTrue(group.evaluate(title: "Swift Update", body: "", link: "", feedName: "Apple Blog"))
        XCTAssertFalse(group.evaluate(title: "Swift Update", body: "", link: "", feedName: "Google Blog"))
        XCTAssertFalse(group.evaluate(title: "Java Update", body: "", link: "", feedName: "Apple Blog"))
    }
    
    func testConditionGroupAnyLogic() {
        let group = ConditionGroup(logic: .any, conditions: [
            AutomationCondition(field: .title, pattern: "swift"),
            AutomationCondition(field: .title, pattern: "rust")
        ])
        XCTAssertTrue(group.evaluate(title: "Swift Release", body: "", link: "", feedName: ""))
        XCTAssertTrue(group.evaluate(title: "Rust Release", body: "", link: "", feedName: ""))
        XCTAssertFalse(group.evaluate(title: "Python Release", body: "", link: "", feedName: ""))
    }
    
    func testConditionGroupEmptyConditions() {
        let group = ConditionGroup(logic: .all, conditions: [])
        XCTAssertFalse(group.evaluate(title: "Test", body: "", link: "", feedName: ""))
    }
    
    // MARK: - Rule Management Tests
    
    func testAddRule() {
        let rule = AutomationRule(
            name: "Star Swift",
            conditions: [AutomationCondition(field: .title, pattern: "swift")],
            actions: [.markStarred]
        )
        let id = engine.addRule(rule)
        XCTAssertFalse(id.isEmpty)
        XCTAssertEqual(engine.rules.count, 1)
    }
    
    func testAddRuleEmptyNameRejected() {
        let rule = AutomationRule(
            name: "  ",
            conditions: [AutomationCondition(field: .title, pattern: "test")],
            actions: [.markRead]
        )
        let id = engine.addRule(rule)
        XCTAssertTrue(id.isEmpty)
        XCTAssertEqual(engine.rules.count, 0)
    }
    
    func testAddRuleNoConditionsRejected() {
        let rule = AutomationRule(
            name: "Bad Rule",
            conditions: [],
            actions: [.markRead]
        )
        let id = engine.addRule(rule)
        XCTAssertTrue(id.isEmpty)
    }
    
    func testAddRuleNoActionsRejected() {
        let rule = AutomationRule(
            name: "Bad Rule",
            conditions: [AutomationCondition(field: .title, pattern: "test")],
            actions: []
        )
        let id = engine.addRule(rule)
        XCTAssertTrue(id.isEmpty)
    }
    
    func testRemoveRule() {
        let rule = AutomationRule(
            name: "Test",
            conditions: [AutomationCondition(field: .title, pattern: "test")],
            actions: [.markRead]
        )
        let id = engine.addRule(rule)
        XCTAssertTrue(engine.removeRule(id: id))
        XCTAssertEqual(engine.rules.count, 0)
    }
    
    func testRemoveNonexistentRule() {
        XCTAssertFalse(engine.removeRule(id: "nonexistent"))
    }
    
    func testUpdateRule() {
        var rule = AutomationRule(
            name: "Original",
            conditions: [AutomationCondition(field: .title, pattern: "test")],
            actions: [.markRead]
        )
        engine.addRule(rule)
        
        rule.name = "Updated"
        XCTAssertTrue(engine.updateRule(rule))
        XCTAssertEqual(engine.getRule(id: rule.id)?.name, "Updated")
    }
    
    func testSetRuleEnabled() {
        let rule = AutomationRule(
            name: "Test",
            conditions: [AutomationCondition(field: .title, pattern: "test")],
            actions: [.markRead]
        )
        let id = engine.addRule(rule)
        
        XCTAssertTrue(engine.setRuleEnabled(id: id, enabled: false))
        XCTAssertFalse(engine.getRule(id: id)!.isEnabled)
        
        XCTAssertTrue(engine.setRuleEnabled(id: id, enabled: true))
        XCTAssertTrue(engine.getRule(id: id)!.isEnabled)
    }
    
    func testSetRuleEnabledNonexistent() {
        XCTAssertFalse(engine.setRuleEnabled(id: "fake", enabled: true))
    }
    
    func testRulesSortedByPriority() {
        let low = AutomationRule(
            name: "Low",
            conditions: [AutomationCondition(field: .title, pattern: "a")],
            actions: [.markRead],
            priority: 200
        )
        let high = AutomationRule(
            name: "High",
            conditions: [AutomationCondition(field: .title, pattern: "b")],
            actions: [.markStarred],
            priority: 10
        )
        engine.addRule(low)
        engine.addRule(high)
        
        XCTAssertEqual(engine.rules[0].name, "High")
        XCTAssertEqual(engine.rules[1].name, "Low")
    }
    
    func testEnabledRules() {
        let r1 = AutomationRule(
            name: "Enabled",
            conditions: [AutomationCondition(field: .title, pattern: "a")],
            actions: [.markRead]
        )
        var r2 = AutomationRule(
            name: "Disabled",
            conditions: [AutomationCondition(field: .title, pattern: "b")],
            actions: [.markRead]
        )
        r2.isEnabled = false
        
        engine.addRule(r1)
        engine.addRule(r2)
        
        let enabled = engine.enabledRules()
        XCTAssertEqual(enabled.count, 1)
        XCTAssertEqual(enabled[0].name, "Enabled")
    }
    
    func testMoveRulePriority() {
        let rule = AutomationRule(
            name: "Test",
            conditions: [AutomationCondition(field: .title, pattern: "a")],
            actions: [.markRead],
            priority: 100
        )
        let id = engine.addRule(rule)
        XCTAssertTrue(engine.moveRule(id: id, toPriority: 5))
        XCTAssertEqual(engine.getRule(id: id)?.priority, 5)
    }
    
    func testDuplicateRule() {
        let rule = AutomationRule(
            name: "Original",
            conditions: [AutomationCondition(field: .title, pattern: "swift")],
            actions: [.markStarred],
            priority: 50
        )
        let id = engine.addRule(rule)
        let copyId = engine.duplicateRule(id: id)
        
        XCTAssertNotNil(copyId)
        XCTAssertEqual(engine.rules.count, 2)
        
        let copy = engine.getRule(id: copyId!)
        XCTAssertEqual(copy?.name, "Original (Copy)")
        XCTAssertFalse(copy!.isEnabled)  // copies start disabled
    }
    
    func testDuplicateRuleCustomName() {
        let rule = AutomationRule(
            name: "Base",
            conditions: [AutomationCondition(field: .title, pattern: "test")],
            actions: [.markRead]
        )
        let id = engine.addRule(rule)
        let copyId = engine.duplicateRule(id: id, newName: "Custom Copy")
        
        XCTAssertEqual(engine.getRule(id: copyId!)?.name, "Custom Copy")
    }
    
    func testDuplicateNonexistentRule() {
        XCTAssertNil(engine.duplicateRule(id: "fake"))
    }
    
    // MARK: - Article Processing Tests
    
    func testProcessArticleMatch() {
        let rule = AutomationRule(
            name: "Tag AI articles",
            conditions: [AutomationCondition(field: .title, pattern: "AI")],
            actions: [.addTag("artificial-intelligence")]
        )
        engine.addRule(rule)
        
        let result = engine.processArticle(
            title: "AI Revolution in 2026",
            body: "Content here",
            link: "https://example.com/ai",
            feedName: "TechBlog"
        )
        
        XCTAssertEqual(result.matchedRules.count, 1)
        XCTAssertEqual(result.executedActions.count, 1)
        if case .addTag(let tag) = result.executedActions[0] {
            XCTAssertEqual(tag, "artificial-intelligence")
        } else {
            XCTFail("Expected addTag action")
        }
    }
    
    func testProcessArticleNoMatch() {
        let rule = AutomationRule(
            name: "Star AI",
            conditions: [AutomationCondition(field: .title, pattern: "AI")],
            actions: [.markStarred]
        )
        engine.addRule(rule)
        
        let result = engine.processArticle(
            title: "Cooking recipes",
            body: "Delicious food",
            link: "https://example.com",
            feedName: "FoodBlog"
        )
        
        XCTAssertEqual(result.matchedRules.count, 0)
        XCTAssertEqual(result.executedActions.count, 0)
    }
    
    func testProcessArticleMultipleRulesMatch() {
        let r1 = AutomationRule(
            name: "Tag Swift",
            conditions: [AutomationCondition(field: .title, pattern: "swift")],
            actions: [.addTag("swift")],
            priority: 1
        )
        let r2 = AutomationRule(
            name: "Star Apple",
            conditions: [AutomationCondition(field: .feedName, pattern: "apple")],
            actions: [.markStarred],
            priority: 2
        )
        engine.addRule(r1)
        engine.addRule(r2)
        
        let result = engine.processArticle(
            title: "Swift 6.0",
            body: "",
            link: "https://apple.com/swift",
            feedName: "Apple Blog"
        )
        
        XCTAssertEqual(result.matchedRules.count, 2)
        XCTAssertEqual(result.executedActions.count, 2)
    }
    
    func testProcessArticleStopProcessing() {
        let r1 = AutomationRule(
            name: "Stop Rule",
            conditions: [AutomationCondition(field: .title, pattern: "test")],
            actions: [.markRead],
            priority: 1,
            stopProcessing: true
        )
        let r2 = AutomationRule(
            name: "Should Be Skipped",
            conditions: [AutomationCondition(field: .title, pattern: "test")],
            actions: [.markStarred],
            priority: 2
        )
        engine.addRule(r1)
        engine.addRule(r2)
        
        let result = engine.processArticle(
            title: "test article",
            body: "",
            link: "",
            feedName: ""
        )
        
        XCTAssertEqual(result.matchedRules.count, 1)
        XCTAssertEqual(result.skippedRules.count, 1)
        XCTAssertEqual(result.skippedRules[0].reason, "stopped by rule 'Stop Rule'")
    }
    
    func testProcessArticleFeedScope() {
        let rule = AutomationRule(
            name: "TechCrunch only",
            conditions: [AutomationCondition(field: .title, pattern: "launch")],
            actions: [.markStarred],
            feedScope: ["TechCrunch"]
        )
        engine.addRule(rule)
        
        // Should match — in scope
        let r1 = engine.processArticle(title: "New Launch", body: "", link: "", feedName: "TechCrunch")
        XCTAssertEqual(r1.matchedRules.count, 1)
        
        // Should skip — out of scope
        let r2 = engine.processArticle(title: "New Launch", body: "", link: "", feedName: "BBC")
        XCTAssertEqual(r2.matchedRules.count, 0)
        XCTAssertEqual(r2.skippedRules.count, 1)
        XCTAssertEqual(r2.skippedRules[0].reason, "feed not in scope")
    }
    
    func testProcessArticleFeedScopeCaseInsensitive() {
        let rule = AutomationRule(
            name: "Test",
            conditions: [AutomationCondition(field: .title, pattern: "news")],
            actions: [.markRead],
            feedScope: ["techcrunch"]
        )
        engine.addRule(rule)
        
        let result = engine.processArticle(title: "News Update", body: "", link: "", feedName: "TechCrunch")
        XCTAssertEqual(result.matchedRules.count, 1)
    }
    
    func testProcessArticleDisabledRuleSkipped() {
        var rule = AutomationRule(
            name: "Disabled",
            conditions: [AutomationCondition(field: .title, pattern: "test")],
            actions: [.markRead]
        )
        rule.isEnabled = false
        engine.addRule(rule)
        
        let result = engine.processArticle(title: "test", body: "", link: "", feedName: "")
        XCTAssertEqual(result.matchedRules.count, 0)
    }
    
    func testProcessArticleUpdatesStats() {
        let rule = AutomationRule(
            name: "Track",
            conditions: [AutomationCondition(field: .title, pattern: "test")],
            actions: [.markRead]
        )
        let id = engine.addRule(rule)
        
        _ = engine.processArticle(title: "test article", body: "", link: "http://a.com", feedName: "Blog")
        _ = engine.processArticle(title: "test again", body: "", link: "http://b.com", feedName: "Blog")
        
        let updated = engine.getRule(id: id)!
        XCTAssertEqual(updated.triggerCount, 2)
        XCTAssertNotNil(updated.lastTriggeredAt)
    }
    
    func testProcessArticleDryRunNoStateMutation() {
        let rule = AutomationRule(
            name: "DryRun",
            conditions: [AutomationCondition(field: .title, pattern: "test")],
            actions: [.markStarred]
        )
        let id = engine.addRule(rule)
        
        let result = engine.processArticle(
            title: "test article", body: "", link: "", feedName: "",
            dryRun: true
        )
        
        XCTAssertEqual(result.matchedRules.count, 1)
        XCTAssertEqual(engine.getRule(id: id)!.triggerCount, 0)
        XCTAssertEqual(engine.executionHistory.count, 0)
    }
    
    func testProcessArticleDeduplicatesActions() {
        let r1 = AutomationRule(
            name: "Rule A",
            conditions: [AutomationCondition(field: .title, pattern: "test")],
            actions: [.markStarred, .addTag("news")],
            priority: 1
        )
        let r2 = AutomationRule(
            name: "Rule B",
            conditions: [AutomationCondition(field: .title, pattern: "test")],
            actions: [.markStarred, .addTag("tech")],  // markStarred is duplicate
            priority: 2
        )
        engine.addRule(r1)
        engine.addRule(r2)
        
        let result = engine.processArticle(title: "test", body: "", link: "", feedName: "")
        
        XCTAssertEqual(result.matchedRules.count, 2)
        // markStarred should appear only once, both tags should appear
        XCTAssertEqual(result.executedActions.count, 3)
    }
    
    func testProcessArticleRateLimit() {
        let rule = AutomationRule(
            name: "Limited",
            conditions: [AutomationCondition(field: .title, pattern: "alert")],
            actions: [.notify("Alert!")],
            maxTriggersPerDay: 2
        )
        engine.addRule(rule)
        
        let now = Date()
        let r1 = engine.processArticle(title: "alert 1", body: "", link: "1", feedName: "", now: now)
        XCTAssertEqual(r1.matchedRules.count, 1)
        
        let r2 = engine.processArticle(title: "alert 2", body: "", link: "2", feedName: "", now: now)
        XCTAssertEqual(r2.matchedRules.count, 1)
        
        // Third should be rate-limited
        let r3 = engine.processArticle(title: "alert 3", body: "", link: "3", feedName: "", now: now)
        XCTAssertEqual(r3.matchedRules.count, 0)
        XCTAssertEqual(r3.skippedRules.count, 1)
        XCTAssertEqual(r3.skippedRules[0].reason, "daily trigger limit reached")
    }
    
    func testProcessArticleRateLimitResetsNextDay() {
        let rule = AutomationRule(
            name: "Limited",
            conditions: [AutomationCondition(field: .title, pattern: "alert")],
            actions: [.notify("Alert!")],
            maxTriggersPerDay: 1
        )
        engine.addRule(rule)
        
        let today = Date()
        _ = engine.processArticle(title: "alert 1", body: "", link: "1", feedName: "", now: today)
        
        // Rate limited today
        let r2 = engine.processArticle(title: "alert 2", body: "", link: "2", feedName: "", now: today)
        XCTAssertEqual(r2.matchedRules.count, 0)
        
        // Should work tomorrow
        let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: today)!
        let r3 = engine.processArticle(title: "alert 3", body: "", link: "3", feedName: "", now: tomorrow)
        XCTAssertEqual(r3.matchedRules.count, 1)
    }
    
    // MARK: - Batch Processing Tests
    
    func testProcessArticlesBatch() {
        let rule = AutomationRule(
            name: "Tag AI",
            conditions: [AutomationCondition(field: .title, pattern: "AI")],
            actions: [.addTag("ai")]
        )
        engine.addRule(rule)
        
        let articles = [
            (title: "AI News", body: "", link: "1", feedName: "Tech"),
            (title: "Sports Update", body: "", link: "2", feedName: "Sports"),
            (title: "AI Ethics", body: "", link: "3", feedName: "Ethics")
        ]
        
        let results = engine.processArticles(articles)
        XCTAssertEqual(results.count, 3)
        XCTAssertEqual(results[0].matchedRules.count, 1)
        XCTAssertEqual(results[1].matchedRules.count, 0)
        XCTAssertEqual(results[2].matchedRules.count, 1)
    }
    
    // MARK: - Execution History Tests
    
    func testExecutionHistoryRecorded() {
        let rule = AutomationRule(
            name: "Test",
            conditions: [AutomationCondition(field: .title, pattern: "news")],
            actions: [.markRead]
        )
        engine.addRule(rule)
        
        _ = engine.processArticle(title: "news today", body: "", link: "https://a.com", feedName: "Blog")
        
        XCTAssertEqual(engine.executionHistory.count, 1)
        XCTAssertEqual(engine.executionHistory[0].ruleName, "Test")
        XCTAssertEqual(engine.executionHistory[0].articleTitle, "news today")
    }
    
    func testHistoryForRule() {
        let r1 = AutomationRule(
            name: "Rule A",
            conditions: [AutomationCondition(field: .title, pattern: "test")],
            actions: [.markRead]
        )
        let r2 = AutomationRule(
            name: "Rule B",
            conditions: [AutomationCondition(field: .title, pattern: "other")],
            actions: [.markStarred]
        )
        let id1 = engine.addRule(r1)
        engine.addRule(r2)
        
        _ = engine.processArticle(title: "test 1", body: "", link: "1", feedName: "")
        _ = engine.processArticle(title: "test 2", body: "", link: "2", feedName: "")
        _ = engine.processArticle(title: "other thing", body: "", link: "3", feedName: "")
        
        let history = engine.historyForRule(id: id1)
        XCTAssertEqual(history.count, 2)
    }
    
    func testHistoryForArticle() {
        let rule = AutomationRule(
            name: "Test",
            conditions: [AutomationCondition(field: .title, pattern: "news")],
            actions: [.markRead]
        )
        engine.addRule(rule)
        
        _ = engine.processArticle(title: "news today", body: "", link: "https://example.com/1", feedName: "")
        _ = engine.processArticle(title: "news update", body: "", link: "https://example.com/2", feedName: "")
        
        let history = engine.historyForArticle(link: "https://example.com/1")
        XCTAssertEqual(history.count, 1)
    }
    
    func testRecentHistory() {
        let rule = AutomationRule(
            name: "Test",
            conditions: [AutomationCondition(field: .title, pattern: "a")],
            actions: [.markRead]
        )
        engine.addRule(rule)
        
        for i in 0..<5 {
            _ = engine.processArticle(title: "a\(i)", body: "", link: "\(i)", feedName: "")
        }
        
        let recent = engine.recentHistory(limit: 3)
        XCTAssertEqual(recent.count, 3)
    }
    
    func testClearHistory() {
        let rule = AutomationRule(
            name: "Test",
            conditions: [AutomationCondition(field: .title, pattern: "test")],
            actions: [.markRead]
        )
        engine.addRule(rule)
        _ = engine.processArticle(title: "test", body: "", link: "", feedName: "")
        
        engine.clearHistory()
        XCTAssertEqual(engine.executionHistory.count, 0)
    }
    
    func testHistorySizeCapped() {
        engine.maxHistorySize = 5
        let rule = AutomationRule(
            name: "Test",
            conditions: [AutomationCondition(field: .title, pattern: "x")],
            actions: [.markRead]
        )
        engine.addRule(rule)
        
        for i in 0..<10 {
            _ = engine.processArticle(title: "x\(i)", body: "", link: "\(i)", feedName: "")
        }
        
        XCTAssertEqual(engine.executionHistory.count, 5)
    }
    
    // MARK: - Statistics Tests
    
    func testStatistics() {
        let r1 = AutomationRule(
            name: "Active",
            conditions: [AutomationCondition(field: .title, pattern: "test")],
            actions: [.markRead]
        )
        var r2 = AutomationRule(
            name: "Inactive",
            conditions: [AutomationCondition(field: .title, pattern: "other")],
            actions: [.markStarred]
        )
        r2.isEnabled = false
        
        engine.addRule(r1)
        engine.addRule(r2)
        
        _ = engine.processArticle(title: "test 1", body: "", link: "1", feedName: "")
        _ = engine.processArticle(title: "test 2", body: "", link: "2", feedName: "")
        
        let stats = engine.statistics()
        XCTAssertEqual(stats.totalRules, 2)
        XCTAssertEqual(stats.enabledRules, 1)
        XCTAssertEqual(stats.disabledRules, 1)
        XCTAssertEqual(stats.totalExecutions, 2)
        XCTAssertEqual(stats.topRulesByTriggers.count, 1)
        XCTAssertEqual(stats.topRulesByTriggers[0].count, 2)
        XCTAssertEqual(stats.rulesNeverTriggered.count, 1)
        XCTAssertEqual(stats.averageTriggersPerRule, 1.0)
    }
    
    func testStatisticsEmptyEngine() {
        let stats = engine.statistics()
        XCTAssertEqual(stats.totalRules, 0)
        XCTAssertEqual(stats.averageTriggersPerRule, 0.0)
    }
    
    // MARK: - Preset Rules Tests
    
    func testPresetMuteByKeyword() {
        let rule = FeedAutomationEngine.presetMuteByKeyword("sponsored")
        engine.addRule(rule)
        
        let result = engine.processArticle(title: "Sponsored Content", body: "", link: "", feedName: "")
        XCTAssertEqual(result.matchedRules.count, 1)
        XCTAssertEqual(result.executedActions.count, 2)
    }
    
    func testPresetTagByFeed() {
        let rule = FeedAutomationEngine.presetTagByFeed(feedName: "Hacker News", tag: "HN")
        engine.addRule(rule)
        
        let r1 = engine.processArticle(title: "Show HN", body: "", link: "", feedName: "Hacker News")
        XCTAssertEqual(r1.matchedRules.count, 1)
        
        let r2 = engine.processArticle(title: "Article", body: "", link: "", feedName: "Reddit")
        XCTAssertEqual(r2.matchedRules.count, 0)
    }
    
    func testPresetStarByKeyword() {
        let rule = FeedAutomationEngine.presetStarByKeyword("breaking")
        engine.addRule(rule)
        
        let result = engine.processArticle(title: "Breaking: Major Event", body: "", link: "", feedName: "")
        XCTAssertEqual(result.matchedRules.count, 1)
        if case .markStarred = result.executedActions[0] {
            // pass
        } else {
            XCTFail("Expected markStarred")
        }
    }
    
    func testPresetNotifyOnKeyword() {
        let rule = FeedAutomationEngine.presetNotifyOnKeyword("security")
        engine.addRule(rule)
        
        XCTAssertEqual(rule.maxTriggersPerDay, 10)
        
        let result = engine.processArticle(title: "Security Alert", body: "", link: "", feedName: "")
        XCTAssertEqual(result.matchedRules.count, 1)
    }
    
    // MARK: - Import/Export Tests
    
    func testExportRules() {
        let rule = AutomationRule(
            name: "Export Test",
            conditions: [AutomationCondition(field: .title, pattern: "test")],
            actions: [.markRead, .addTag("exported")]
        )
        engine.addRule(rule)
        
        let json = engine.exportRulesAsString()
        XCTAssertNotNil(json)
        XCTAssertTrue(json!.contains("Export Test"))
        XCTAssertTrue(json!.contains("exported"))
    }
    
    func testImportRulesMerge() {
        let existing = AutomationRule(
            name: "Existing",
            conditions: [AutomationCondition(field: .title, pattern: "old")],
            actions: [.markRead]
        )
        engine.addRule(existing)
        
        // Create rules to import
        let importEngine = FeedAutomationEngine()
        let imported = AutomationRule(
            name: "Imported",
            conditions: [AutomationCondition(field: .title, pattern: "new")],
            actions: [.markStarred]
        )
        importEngine.addRule(imported)
        let json = importEngine.exportRules()!
        
        let count = engine.importRules(from: json)
        XCTAssertEqual(count, 1)
        XCTAssertEqual(engine.rules.count, 2)
    }
    
    func testImportRulesReplace() {
        let existing = AutomationRule(
            name: "Existing",
            conditions: [AutomationCondition(field: .title, pattern: "old")],
            actions: [.markRead]
        )
        engine.addRule(existing)
        
        let importEngine = FeedAutomationEngine()
        let imported = AutomationRule(
            name: "Replacement",
            conditions: [AutomationCondition(field: .title, pattern: "new")],
            actions: [.markStarred]
        )
        importEngine.addRule(imported)
        let json = importEngine.exportRules()!
        
        let count = engine.importRules(from: json, replace: true)
        XCTAssertEqual(count, 1)
        XCTAssertEqual(engine.rules.count, 1)
        XCTAssertEqual(engine.rules[0].name, "Replacement")
    }
    
    func testImportSkipsDuplicateNames() {
        let existing = AutomationRule(
            name: "Same Name",
            conditions: [AutomationCondition(field: .title, pattern: "old")],
            actions: [.markRead]
        )
        engine.addRule(existing)
        
        let importEngine = FeedAutomationEngine()
        let dup = AutomationRule(
            name: "Same Name",
            conditions: [AutomationCondition(field: .title, pattern: "new")],
            actions: [.markStarred]
        )
        importEngine.addRule(dup)
        let json = importEngine.exportRules()!
        
        let count = engine.importRules(from: json)
        XCTAssertEqual(count, 0)
        XCTAssertEqual(engine.rules.count, 1)
    }
    
    func testImportFromString() {
        let importEngine = FeedAutomationEngine()
        importEngine.addRule(AutomationRule(
            name: "StringImport",
            conditions: [AutomationCondition(field: .title, pattern: "test")],
            actions: [.markRead]
        ))
        let jsonStr = importEngine.exportRulesAsString()!
        
        let count = engine.importRules(from: jsonStr)
        XCTAssertEqual(count, 1)
    }
    
    func testImportInvalidJSON() {
        let count = engine.importRules(from: "not json".data(using: .utf8)!)
        XCTAssertEqual(count, 0)
    }
    
    // MARK: - Rule Validation Tests
    
    func testValidateValidRule() {
        let rule = AutomationRule(
            name: "Valid",
            conditions: [AutomationCondition(field: .title, pattern: "test")],
            actions: [.markRead]
        )
        let issues = engine.validateRule(rule)
        XCTAssertTrue(issues.isEmpty)
    }
    
    func testValidateEmptyName() {
        let rule = AutomationRule(name: "", conditions: [AutomationCondition(field: .title, pattern: "test")], actions: [.markRead])
        let issues = engine.validateRule(rule)
        XCTAssertTrue(issues.contains("Rule name cannot be empty"))
    }
    
    func testValidateNoConditions() {
        let rule = AutomationRule(name: "Test", conditions: [], actions: [.markRead])
        let issues = engine.validateRule(rule)
        XCTAssertTrue(issues.contains("Rule must have at least one condition"))
    }
    
    func testValidateNoActions() {
        let rule = AutomationRule(name: "Test", conditions: [AutomationCondition(field: .title, pattern: "x")], actions: [])
        let issues = engine.validateRule(rule)
        XCTAssertTrue(issues.contains("Rule must have at least one action"))
    }
    
    func testValidateInvalidRegex() {
        let rule = AutomationRule(
            name: "Bad Regex",
            conditions: [AutomationCondition(field: .title, mode: .regex, pattern: "[invalid")],
            actions: [.markRead]
        )
        let issues = engine.validateRule(rule)
        XCTAssertTrue(issues.contains { $0.contains("Invalid regex") })
    }
    
    func testValidateEmptyPattern() {
        let rule = AutomationRule(
            name: "Empty Pattern",
            conditions: [AutomationCondition(field: .title, pattern: "  ")],
            actions: [.markRead]
        )
        let issues = engine.validateRule(rule)
        XCTAssertTrue(issues.contains("Condition pattern cannot be empty"))
    }
    
    func testValidateInvalidMaxTriggers() {
        let rule = AutomationRule(
            name: "Bad Limit",
            conditions: [AutomationCondition(field: .title, pattern: "test")],
            actions: [.markRead],
            maxTriggersPerDay: 0
        )
        let issues = engine.validateRule(rule)
        XCTAssertTrue(issues.contains("Max triggers per day must be positive"))
    }
    
    // MARK: - Test Rule Tests
    
    func testTestRuleMatches() {
        let rule = AutomationRule(
            name: "Test",
            conditions: [AutomationCondition(field: .title, pattern: "swift")],
            actions: [.markStarred]
        )
        
        XCTAssertTrue(engine.testRule(rule, title: "Swift 6.0"))
        XCTAssertFalse(engine.testRule(rule, title: "Rust 2.0"))
    }
    
    func testTestRuleRespectsScope() {
        let rule = AutomationRule(
            name: "Scoped",
            conditions: [AutomationCondition(field: .title, pattern: "news")],
            actions: [.markRead],
            feedScope: ["BBC"]
        )
        
        XCTAssertTrue(engine.testRule(rule, title: "Breaking news", feedName: "BBC"))
        XCTAssertFalse(engine.testRule(rule, title: "Breaking news", feedName: "CNN"))
    }
    
    // MARK: - Bulk Operations Tests
    
    func testEnableAll() {
        var r1 = AutomationRule(name: "A", conditions: [AutomationCondition(field: .title, pattern: "a")], actions: [.markRead])
        r1.isEnabled = false
        var r2 = AutomationRule(name: "B", conditions: [AutomationCondition(field: .title, pattern: "b")], actions: [.markRead])
        r2.isEnabled = false
        engine.addRule(r1)
        engine.addRule(r2)
        
        engine.enableAll()
        XCTAssertTrue(engine.rules.allSatisfy { $0.isEnabled })
    }
    
    func testDisableAll() {
        engine.addRule(AutomationRule(name: "A", conditions: [AutomationCondition(field: .title, pattern: "a")], actions: [.markRead]))
        engine.addRule(AutomationRule(name: "B", conditions: [AutomationCondition(field: .title, pattern: "b")], actions: [.markRead]))
        
        engine.disableAll()
        XCTAssertTrue(engine.rules.allSatisfy { !$0.isEnabled })
    }
    
    func testRemoveAll() {
        engine.addRule(AutomationRule(name: "A", conditions: [AutomationCondition(field: .title, pattern: "a")], actions: [.markRead]))
        engine.addRule(AutomationRule(name: "B", conditions: [AutomationCondition(field: .title, pattern: "b")], actions: [.markRead]))
        
        engine.removeAll()
        XCTAssertEqual(engine.rules.count, 0)
    }
    
    func testResetStats() {
        let rule = AutomationRule(name: "Test", conditions: [AutomationCondition(field: .title, pattern: "x")], actions: [.markRead])
        engine.addRule(rule)
        _ = engine.processArticle(title: "x", body: "", link: "", feedName: "")
        
        engine.resetStats()
        
        XCTAssertEqual(engine.rules[0].triggerCount, 0)
        XCTAssertNil(engine.rules[0].lastTriggeredAt)
        XCTAssertTrue(engine.rules[0].dailyTriggers.isEmpty)
        XCTAssertTrue(engine.executionHistory.isEmpty)
    }
    
    // MARK: - Search & Filter Tests
    
    func testRulesForFeed() {
        let r1 = AutomationRule(name: "Scoped", conditions: [AutomationCondition(field: .title, pattern: "a")], actions: [.markRead], feedScope: ["TechCrunch"])
        let r2 = AutomationRule(name: "Global", conditions: [AutomationCondition(field: .title, pattern: "b")], actions: [.markRead])
        engine.addRule(r1)
        engine.addRule(r2)
        
        let techRules = engine.rulesForFeed("TechCrunch")
        XCTAssertEqual(techRules.count, 2)  // scoped + global
        
        let bbcRules = engine.rulesForFeed("BBC")
        XCTAssertEqual(bbcRules.count, 1)  // global only
    }
    
    func testRulesWithAction() {
        engine.addRule(AutomationRule(name: "Tag", conditions: [AutomationCondition(field: .title, pattern: "a")], actions: [.addTag("test")]))
        engine.addRule(AutomationRule(name: "Star", conditions: [AutomationCondition(field: .title, pattern: "b")], actions: [.markStarred]))
        
        let tagRules = engine.rulesWithAction("addTag")
        XCTAssertEqual(tagRules.count, 1)
        XCTAssertEqual(tagRules[0].name, "Tag")
    }
    
    func testSearchRules() {
        engine.addRule(AutomationRule(name: "AI Articles", conditions: [AutomationCondition(field: .title, pattern: "ai")], actions: [.markRead]))
        engine.addRule(AutomationRule(name: "Swift News", conditions: [AutomationCondition(field: .title, pattern: "swift")], actions: [.markRead]))
        
        let results = engine.searchRules(query: "ai")
        XCTAssertEqual(results.count, 1)
        XCTAssertEqual(results[0].name, "AI Articles")
    }
    
    func testSearchRulesCaseInsensitive() {
        engine.addRule(AutomationRule(name: "Swift News", conditions: [AutomationCondition(field: .title, pattern: "swift")], actions: [.markRead]))
        
        let results = engine.searchRules(query: "SWIFT")
        XCTAssertEqual(results.count, 1)
    }
    
    // MARK: - AutomationAction Codable Tests
    
    func testActionCodableRoundTrip() {
        let actions: [AutomationAction] = [
            .addTag("test"),
            .markRead,
            .markStarred,
            .moveToCollection("favorites"),
            .setHighPriority,
            .notify("Alert!"),
            .markHidden
        ]
        
        for action in actions {
            let data = try! JSONEncoder().encode(action)
            let decoded = try! JSONDecoder().decode(AutomationAction.self, from: data)
            XCTAssertEqual(action, decoded)
        }
    }
    
    // MARK: - Complex Scenario Tests
    
    func testComplexMultiConditionRule() {
        let rule = AutomationRule(
            name: "Important Tech from Apple",
            conditions: [
                AutomationCondition(field: .feedName, mode: .exactMatch, pattern: "Apple Blog"),
                AutomationCondition(field: .title, pattern: "release"),
                AutomationCondition(field: .title, pattern: "sponsored", negate: true)
            ],
            logic: .all,
            actions: [.markStarred, .addTag("apple-release"), .notify("New Apple release!")]
        )
        engine.addRule(rule)
        
        // Matches: from Apple, title has "release", not sponsored
        let r1 = engine.processArticle(title: "iOS 20 Release", body: "", link: "", feedName: "Apple Blog")
        XCTAssertEqual(r1.matchedRules.count, 1)
        XCTAssertEqual(r1.executedActions.count, 3)
        
        // Doesn't match: sponsored
        let r2 = engine.processArticle(title: "Sponsored Release Event", body: "", link: "", feedName: "Apple Blog")
        XCTAssertEqual(r2.matchedRules.count, 0)
        
        // Doesn't match: wrong feed
        let r3 = engine.processArticle(title: "Android Release", body: "", link: "", feedName: "Google Blog")
        XCTAssertEqual(r3.matchedRules.count, 0)
    }
    
    func testORConditionsWithDifferentFields() {
        let rule = AutomationRule(
            name: "Security alerts",
            conditions: [
                AutomationCondition(field: .title, pattern: "CVE-"),
                AutomationCondition(field: .title, pattern: "vulnerability"),
                AutomationCondition(field: .body, pattern: "zero-day")
            ],
            logic: .any,
            actions: [.markStarred, .setHighPriority]
        )
        engine.addRule(rule)
        
        let r1 = engine.processArticle(title: "CVE-2026-1234 Found", body: "", link: "", feedName: "")
        XCTAssertEqual(r1.matchedRules.count, 1)
        
        let r2 = engine.processArticle(title: "Normal", body: "zero-day exploit discovered", link: "", feedName: "")
        XCTAssertEqual(r2.matchedRules.count, 1)
        
        let r3 = engine.processArticle(title: "Cooking Tips", body: "Delicious", link: "", feedName: "")
        XCTAssertEqual(r3.matchedRules.count, 0)
    }
}
