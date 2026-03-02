//
//  KeywordAlertTests.swift
//  FeedReaderTests
//
//  Tests for KeywordAlert model and KeywordAlertManager.
//

import XCTest
@testable import FeedReader

class KeywordAlertTests: XCTestCase {
    
    var manager: KeywordAlertManager!
    
    override func setUp() {
        super.setUp()
        manager = KeywordAlertManager()
        manager.removeAll()
    }
    
    // MARK: - Helper
    
    func makeStory(title: String = "Test Title", body: String = "Test body", link: String = "https://example.com") -> Story? {
        return Story(title: title, photo: nil, description: body, link: link)
    }
    
    // MARK: - KeywordAlert Model Tests
    
    func testAlertInit() {
        let alert = KeywordAlert(keyword: "swift")
        XCTAssertNotNil(alert)
        XCTAssertEqual(alert?.keyword, "swift")
        XCTAssertTrue(alert?.isActive ?? false)
        XCTAssertEqual(alert?.priority, .medium)
        XCTAssertEqual(alert?.matchScope, .both)
        XCTAssertEqual(alert?.matchCount, 0)
    }
    
    func testAlertInitTrimsWhitespace() {
        let alert = KeywordAlert(keyword: "  security  ")
        XCTAssertEqual(alert?.keyword, "security")
    }
    
    func testAlertInitEmptyKeywordFails() {
        let alert = KeywordAlert(keyword: "")
        XCTAssertNil(alert)
    }
    
    func testAlertInitWhitespaceOnlyFails() {
        let alert = KeywordAlert(keyword: "   ")
        XCTAssertNil(alert)
    }
    
    func testAlertInitTruncatesLongKeyword() {
        let longKeyword = String(repeating: "a", count: 300)
        let alert = KeywordAlert(keyword: longKeyword)
        XCTAssertNotNil(alert)
        XCTAssertEqual(alert?.keyword.count, KeywordAlert.maxKeywordLength)
    }
    
    func testAlertInitCustomPriority() {
        let alert = KeywordAlert(keyword: "urgent", priority: .high)
        XCTAssertEqual(alert?.priority, .high)
    }
    
    func testAlertInitCustomScope() {
        let alert = KeywordAlert(keyword: "ios", matchScope: .title)
        XCTAssertEqual(alert?.matchScope, .title)
    }
    
    func testAlertInitWithColorHex() {
        let alert = KeywordAlert(keyword: "warning", colorHex: "#FF6B6B")
        XCTAssertEqual(alert?.colorHex, "#FF6B6B")
    }
    
    func testAlertInitWithoutColorHex() {
        let alert = KeywordAlert(keyword: "info")
        XCTAssertNil(alert?.colorHex)
    }
    
    func testAlertUniqueId() {
        let a1 = KeywordAlert(keyword: "swift")
        let a2 = KeywordAlert(keyword: "swift")
        XCTAssertNotEqual(a1?.id, a2?.id)
    }
    
    // MARK: - Matching Tests
    
    func testMatchesTitleScope() {
        let alert = KeywordAlert(keyword: "swift", matchScope: .title)!
        XCTAssertTrue(alert.matches(title: "Learning Swift", body: "Some body"))
        XCTAssertFalse(alert.matches(title: "Other", body: "swift is great"))
    }
    
    func testMatchesBodyScope() {
        let alert = KeywordAlert(keyword: "security", matchScope: .body)!
        XCTAssertFalse(alert.matches(title: "security alert", body: "Normal body"))
        XCTAssertTrue(alert.matches(title: "Other", body: "security vulnerability found"))
    }
    
    func testMatchesBothScope() {
        let alert = KeywordAlert(keyword: "AI", matchScope: .both)!
        XCTAssertTrue(alert.matches(title: "AI Revolution", body: "Normal body"))
        XCTAssertTrue(alert.matches(title: "Other", body: "AI is changing the world"))
        XCTAssertFalse(alert.matches(title: "Other", body: "Nothing here"))
    }
    
    func testMatchIsCaseInsensitive() {
        let alert = KeywordAlert(keyword: "Swift")!
        XCTAssertTrue(alert.matches(title: "SWIFT programming", body: ""))
        XCTAssertTrue(alert.matches(title: "swift is nice", body: ""))
        XCTAssertTrue(alert.matches(title: "", body: "SWIFT rocks"))
    }
    
    func testInactiveAlertDoesNotMatch() {
        let alert = KeywordAlert(keyword: "swift", isActive: false)!
        XCTAssertFalse(alert.matches(title: "Swift programming", body: "Swift body"))
    }
    
    func testMatchesPartialWord() {
        let alert = KeywordAlert(keyword: "secur")!
        XCTAssertTrue(alert.matches(title: "Security alert", body: ""))
    }
    
    func testNoMatchWhenKeywordAbsent() {
        let alert = KeywordAlert(keyword: "python")!
        XCTAssertFalse(alert.matches(title: "Swift is great", body: "iOS development"))
    }
    
    // MARK: - AlertPriority Tests
    
    func testPrioritySortOrder() {
        XCTAssertLessThan(AlertPriority.high.sortOrder, AlertPriority.medium.sortOrder)
        XCTAssertLessThan(AlertPriority.medium.sortOrder, AlertPriority.low.sortOrder)
    }
    
    // MARK: - Manager CRUD Tests
    
    func testAddAlert() {
        let result = manager.addAlert(keyword: "swift")
        XCTAssertTrue(result)
        XCTAssertEqual(manager.alerts.count, 1)
        XCTAssertEqual(manager.alerts.first?.keyword, "swift")
    }
    
    func testAddAlertWithEmptyKeyword() {
        let result = manager.addAlert(keyword: "")
        XCTAssertFalse(result)
        XCTAssertEqual(manager.alerts.count, 0)
    }
    
    func testAddDuplicateKeywordFails() {
        manager.addAlert(keyword: "swift")
        let result = manager.addAlert(keyword: "swift")
        XCTAssertFalse(result)
        XCTAssertEqual(manager.alerts.count, 1)
    }
    
    func testAddDuplicateKeywordCaseInsensitive() {
        manager.addAlert(keyword: "Swift")
        let result = manager.addAlert(keyword: "SWIFT")
        XCTAssertFalse(result)
        XCTAssertEqual(manager.alerts.count, 1)
    }
    
    func testAddAlertRespectsLimit() {
        for i in 0..<KeywordAlert.maxAlerts {
            manager.addAlert(keyword: "keyword\(i)")
        }
        XCTAssertEqual(manager.alerts.count, KeywordAlert.maxAlerts)
        
        let result = manager.addAlert(keyword: "one more")
        XCTAssertFalse(result)
        XCTAssertEqual(manager.alerts.count, KeywordAlert.maxAlerts)
    }
    
    func testAddAlertWithPriority() {
        manager.addAlert(keyword: "critical", priority: .high)
        XCTAssertEqual(manager.alerts.first?.priority, .high)
    }
    
    func testAddAlertWithScope() {
        manager.addAlert(keyword: "headline", matchScope: .title)
        XCTAssertEqual(manager.alerts.first?.matchScope, .title)
    }
    
    func testAddAlertWithColor() {
        manager.addAlert(keyword: "warning", colorHex: "#FF0000")
        XCTAssertEqual(manager.alerts.first?.colorHex, "#FF0000")
    }
    
    func testRemoveAlert() {
        manager.addAlert(keyword: "swift")
        let id = manager.alerts.first!.id
        
        let result = manager.removeAlert(id: id)
        XCTAssertTrue(result)
        XCTAssertEqual(manager.alerts.count, 0)
    }
    
    func testRemoveNonexistentAlert() {
        let result = manager.removeAlert(id: "fake-id")
        XCTAssertFalse(result)
    }
    
    func testToggleAlert() {
        manager.addAlert(keyword: "swift")
        let id = manager.alerts.first!.id
        XCTAssertTrue(manager.alerts.first!.isActive)
        
        manager.toggleAlert(id: id)
        XCTAssertFalse(manager.alerts.first!.isActive)
        
        manager.toggleAlert(id: id)
        XCTAssertTrue(manager.alerts.first!.isActive)
    }
    
    func testSetPriority() {
        manager.addAlert(keyword: "swift")
        let id = manager.alerts.first!.id
        
        manager.setPriority(id: id, priority: .high)
        XCTAssertEqual(manager.alerts.first!.priority, .high)
        
        manager.setPriority(id: id, priority: .low)
        XCTAssertEqual(manager.alerts.first!.priority, .low)
    }
    
    func testRemoveAll() {
        manager.addAlert(keyword: "swift")
        manager.addAlert(keyword: "ios")
        manager.addAlert(keyword: "xcode")
        XCTAssertEqual(manager.alerts.count, 3)
        
        manager.removeAll()
        XCTAssertEqual(manager.alerts.count, 0)
    }
    
    func testActiveAlerts() {
        manager.addAlert(keyword: "active1")
        manager.addAlert(keyword: "active2")
        manager.addAlert(keyword: "inactive", priority: .low)
        
        let id = manager.alerts.last!.id
        manager.toggleAlert(id: id)
        
        XCTAssertEqual(manager.activeAlerts.count, 2)
    }
    
    // MARK: - Story Matching Tests
    
    func testMatchingAlertsForStory() {
        manager.addAlert(keyword: "swift")
        manager.addAlert(keyword: "python")
        
        guard let story = makeStory(title: "Swift programming guide", body: "Learn Swift") else {
            XCTFail("Failed to create story")
            return
        }
        
        let matched = manager.matchingAlerts(for: story)
        XCTAssertEqual(matched.count, 1)
        XCTAssertEqual(matched.first?.keyword, "swift")
    }
    
    func testIsAlerted() {
        manager.addAlert(keyword: "breaking")
        
        guard let story1 = makeStory(title: "Breaking news!", body: ""),
              let story2 = makeStory(title: "Regular story", body: "Normal content") else {
            XCTFail("Failed to create stories")
            return
        }
        
        XCTAssertTrue(manager.isAlerted(story: story1))
        XCTAssertFalse(manager.isAlerted(story: story2))
    }
    
    func testScanStories() {
        manager.addAlert(keyword: "swift")
        manager.addAlert(keyword: "python")
        
        let stories = [
            makeStory(title: "Swift 6 released", body: "New features", link: "https://a.com"),
            makeStory(title: "Cooking tips", body: "Bake a cake", link: "https://b.com"),
            makeStory(title: "Python 4", body: "Big update", link: "https://c.com"),
            makeStory(title: "Weather", body: "Sunny day", link: "https://d.com")
        ].compactMap { $0 }
        
        let results = manager.scanStories(stories)
        XCTAssertEqual(results.count, 2)
    }
    
    func testScanIncreasesMatchCount() {
        manager.addAlert(keyword: "swift")
        let initialCount = manager.alerts.first!.matchCount
        
        let stories = [
            makeStory(title: "Swift 6", body: "", link: "https://a.com"),
            makeStory(title: "Swift tips", body: "", link: "https://b.com")
        ].compactMap { $0 }
        
        _ = manager.scanStories(stories)
        XCTAssertEqual(manager.alerts.first!.matchCount, initialCount + 2)
    }
    
    func testScanSortsByPriority() {
        manager.addAlert(keyword: "low", priority: .low)
        manager.addAlert(keyword: "high", priority: .high)
        
        let stories = [
            makeStory(title: "low priority item", body: "", link: "https://a.com"),
            makeStory(title: "high priority item", body: "", link: "https://b.com")
        ].compactMap { $0 }
        
        let results = manager.scanStories(stories)
        XCTAssertEqual(results.count, 2)
        // High priority should come first
        XCTAssertEqual(results.first?.highestPriority, .high)
    }
    
    func testScanReturnsEmptyForNoMatches() {
        manager.addAlert(keyword: "nonexistent")
        
        let stories = [
            makeStory(title: "Normal news", body: "Nothing special", link: "https://a.com")
        ].compactMap { $0 }
        
        let results = manager.scanStories(stories)
        XCTAssertTrue(results.isEmpty)
    }
    
    func testMultipleAlertsMatchSingleStory() {
        manager.addAlert(keyword: "swift")
        manager.addAlert(keyword: "programming")
        
        guard let story = makeStory(title: "Swift programming guide", body: "Learn programming in Swift") else {
            XCTFail()
            return
        }
        
        let matched = manager.matchingAlerts(for: story)
        XCTAssertEqual(matched.count, 2)
    }
    
    func testInactiveAlertNotMatchedInScan() {
        manager.addAlert(keyword: "swift")
        let id = manager.alerts.first!.id
        manager.toggleAlert(id: id)
        
        let stories = [
            makeStory(title: "Swift news", body: "", link: "https://a.com")
        ].compactMap { $0 }
        
        let results = manager.scanStories(stories)
        XCTAssertTrue(results.isEmpty)
    }
    
    // MARK: - AlertedStory Tests
    
    func testAlertedStoryHighestPriority() {
        let lowAlert = KeywordAlert(keyword: "low", priority: .low)!
        let highAlert = KeywordAlert(keyword: "high", priority: .high)!
        
        guard let story = makeStory() else { XCTFail(); return }
        let alerted = AlertedStory(story: story, matchedAlerts: [lowAlert, highAlert])
        
        XCTAssertEqual(alerted.highestPriority, .high)
    }
    
    func testAlertedStorySingleAlert() {
        let alert = KeywordAlert(keyword: "test", priority: .medium)!
        guard let story = makeStory() else { XCTFail(); return }
        let alerted = AlertedStory(story: story, matchedAlerts: [alert])
        
        XCTAssertEqual(alerted.highestPriority, .medium)
        XCTAssertEqual(alerted.matchedAlerts.count, 1)
    }
    
    // MARK: - Summary Tests
    
    func testSummaryEmpty() {
        let summary = manager.summary()
        XCTAssertTrue(summary.contains("0 alerts"))
        XCTAssertTrue(summary.contains("0 active"))
    }
    
    func testSummaryWithAlerts() {
        manager.addAlert(keyword: "swift")
        manager.addAlert(keyword: "ios")
        let id = manager.alerts.last!.id
        manager.toggleAlert(id: id)
        
        let summary = manager.summary()
        XCTAssertTrue(summary.contains("2 alerts"))
        XCTAssertTrue(summary.contains("1 active"))
    }
    
    // MARK: - NSSecureCoding Tests
    
    func testAlertEncodeAndDecode() {
        let original = KeywordAlert(keyword: "swift", priority: .high,
                                     matchScope: .title, colorHex: "#FF0000")!
        original.matchCount = 42
        
        guard let data = try? NSKeyedArchiver.archivedData(
            withRootObject: original, requiringSecureCoding: true
        ) else {
            XCTFail("Failed to archive")
            return
        }
        
        let allowedClasses: [AnyClass] = [KeywordAlert.self, NSString.self, NSDate.self, NSNumber.self]
        guard let decoded = try? NSKeyedUnarchiver.unarchivedObject(
            ofClasses: allowedClasses, from: data
        ) as? KeywordAlert else {
            XCTFail("Failed to unarchive")
            return
        }
        
        XCTAssertEqual(decoded.id, original.id)
        XCTAssertEqual(decoded.keyword, original.keyword)
        XCTAssertEqual(decoded.priority, .high)
        XCTAssertEqual(decoded.matchScope, .title)
        XCTAssertEqual(decoded.matchCount, 42)
        XCTAssertEqual(decoded.colorHex, "#FF0000")
        XCTAssertEqual(decoded.isActive, true)
    }
}
