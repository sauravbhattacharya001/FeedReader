//
//  SmartFeedTests.swift
//  FeedReaderTests
//
//  Tests for SmartFeed and SmartFeedManager — CRUD, matching, persistence, edge cases.
//

import XCTest
@testable import FeedReader

class SmartFeedTests: XCTestCase {
    
    // MARK: - Helpers
    
    private var manager: SmartFeedManager!
    
    private func makeStory(title: String = "Test Story", description: String = "A test description", link: String = "https://example.com/story1") -> Story {
        return Story(title: title, photo: nil, description: description, link: link)!
    }
    
    private func makeSmartFeed(name: String = "Tech News",
                               keywords: [String] = ["swift", "ios"],
                               matchMode: SmartFeed.MatchMode = .any,
                               searchScope: SmartFeed.SearchScope = .titleAndBody,
                               isEnabled: Bool = true) -> SmartFeed {
        return SmartFeed(name: name, keywords: keywords, matchMode: matchMode,
                         searchScope: searchScope, isEnabled: isEnabled)!
    }
    
    override func setUp() {
        super.setUp()
        manager = SmartFeedManager()
        manager.clearAll()
    }
    
    override func tearDown() {
        manager.clearAll()
        super.tearDown()
    }
    
    // MARK: - SmartFeed Init (1–8)
    
    func testSmartFeedInitWithValidParameters() {
        let feed = SmartFeed(name: "AI News", keywords: ["artificial intelligence", "machine learning"],
                             matchMode: .any, searchScope: .titleAndBody)
        XCTAssertNotNil(feed)
        XCTAssertEqual(feed?.name, "AI News")
        XCTAssertEqual(feed?.keywords, ["artificial intelligence", "machine learning"])
        XCTAssertEqual(feed?.matchMode, .any)
        XCTAssertEqual(feed?.searchScope, .titleAndBody)
        XCTAssertTrue(feed?.isEnabled ?? false)
    }
    
    func testSmartFeedInitWithDefaults() {
        let feed = SmartFeed(name: "Test", keywords: ["keyword"])
        XCTAssertNotNil(feed)
        XCTAssertEqual(feed?.matchMode, .any)
        XCTAssertEqual(feed?.searchScope, .titleAndBody)
        XCTAssertTrue(feed?.isEnabled ?? false)
    }
    
    func testSmartFeedNameTrimming() {
        let feed = SmartFeed(name: "  Padded Name  ", keywords: ["test"])
        XCTAssertEqual(feed?.name, "Padded Name")
    }
    
    func testSmartFeedNameMaxLength() {
        let longName = String(repeating: "A", count: 100)
        let feed = SmartFeed(name: longName, keywords: ["test"])
        XCTAssertNotNil(feed)
        XCTAssertEqual(feed?.name.count, SmartFeed.maxNameLength)
    }
    
    func testSmartFeedEmptyNameRejected() {
        let feed = SmartFeed(name: "", keywords: ["test"])
        XCTAssertNil(feed, "Empty name should cause init to fail")
    }
    
    func testSmartFeedWhitespaceOnlyNameRejected() {
        let feed = SmartFeed(name: "   ", keywords: ["test"])
        XCTAssertNil(feed, "Whitespace-only name should be rejected")
    }
    
    func testSmartFeedKeywordNormalization() {
        let feed = SmartFeed(name: "Test", keywords: ["  Swift  ", "IOS", "MacOS  "])
        XCTAssertEqual(feed?.keywords, ["swift", "ios", "macos"])
    }
    
    func testSmartFeedKeywordWhitespaceOnlyStripped() {
        let feed = SmartFeed(name: "Test", keywords: ["valid", "   ", "", "also valid"])
        XCTAssertEqual(feed?.keywords, ["valid", "also valid"])
    }
    
    // MARK: - SmartFeed Limits (9–12)
    
    func testSmartFeedMaxKeywordsLimit() {
        let manyKeywords = (1...20).map { "keyword\($0)" }
        let feed = SmartFeed(name: "Test", keywords: manyKeywords)
        XCTAssertEqual(feed?.keywords.count, SmartFeed.maxKeywords)
    }
    
    func testSmartFeedMaxKeywordLength() {
        let longKeyword = String(repeating: "x", count: 200)
        let feed = SmartFeed(name: "Test", keywords: [longKeyword])
        XCTAssertEqual(feed?.keywords.first?.count, SmartFeed.maxKeywordLength)
    }
    
    func testSmartFeedEmptyKeywordsAllowed() {
        let feed = SmartFeed(name: "Test", keywords: [])
        XCTAssertNotNil(feed)
        XCTAssertEqual(feed?.keywords.count, 0)
    }
    
    func testSmartFeedAllMatchMode() {
        let feed = SmartFeed(name: "Test", keywords: ["a", "b"], matchMode: .all)
        XCTAssertEqual(feed?.matchMode, .all)
    }
    
    // MARK: - NSSecureCoding (13–16)
    
    func testSmartFeedSecureCodingRoundTrip() {
        let original = makeSmartFeed(name: "AI News", keywords: ["ai", "ml", "llm"],
                                     matchMode: .all, searchScope: .titleOnly)
        
        let data = try! NSKeyedArchiver.archivedData(withRootObject: original, requiringSecureCoding: true)
        let decoded = try! NSKeyedUnarchiver.unarchivedObject(ofClass: SmartFeed.self, from: data)
        
        XCTAssertNotNil(decoded)
        XCTAssertEqual(decoded?.name, "AI News")
        XCTAssertEqual(decoded?.keywords, ["ai", "ml", "llm"])
        XCTAssertEqual(decoded?.matchMode, .all)
        XCTAssertEqual(decoded?.searchScope, .titleOnly)
    }
    
    func testSmartFeedCodingPreservesEnabled() {
        let feed = makeSmartFeed(isEnabled: false)
        let data = try! NSKeyedArchiver.archivedData(withRootObject: feed, requiringSecureCoding: true)
        let decoded = try! NSKeyedUnarchiver.unarchivedObject(ofClass: SmartFeed.self, from: data)
        
        XCTAssertFalse(decoded?.isEnabled ?? true)
    }
    
    func testSmartFeedCodingPreservesCreatedAt() {
        let date = Date(timeIntervalSince1970: 1000000)
        let feed = SmartFeed(name: "Test", keywords: ["test"], createdAt: date)!
        let data = try! NSKeyedArchiver.archivedData(withRootObject: feed, requiringSecureCoding: true)
        let decoded = try! NSKeyedUnarchiver.unarchivedObject(ofClass: SmartFeed.self, from: data)
        
        XCTAssertEqual(decoded?.createdAt.timeIntervalSince1970, 1000000, accuracy: 1.0)
    }
    
    func testSmartFeedCodingBodyOnlyScope() {
        let feed = makeSmartFeed(searchScope: .bodyOnly)
        let data = try! NSKeyedArchiver.archivedData(withRootObject: feed, requiringSecureCoding: true)
        let decoded = try! NSKeyedUnarchiver.unarchivedObject(ofClass: SmartFeed.self, from: data)
        
        XCTAssertEqual(decoded?.searchScope, .bodyOnly)
    }
    
    // MARK: - SmartFeedManager CRUD (17–28)
    
    func testAddSmartFeed() {
        let feed = makeSmartFeed()
        manager.addSmartFeed(feed)
        
        XCTAssertEqual(manager.count, 1)
        XCTAssertEqual(manager.smartFeeds.first?.name, "Tech News")
    }
    
    func testAddMultipleSmartFeeds() {
        manager.addSmartFeed(makeSmartFeed(name: "Feed 1", keywords: ["a"]))
        manager.addSmartFeed(makeSmartFeed(name: "Feed 2", keywords: ["b"]))
        manager.addSmartFeed(makeSmartFeed(name: "Feed 3", keywords: ["c"]))
        
        XCTAssertEqual(manager.count, 3)
    }
    
    func testAddDuplicateNameRejected() {
        manager.addSmartFeed(makeSmartFeed(name: "AI News"))
        manager.addSmartFeed(makeSmartFeed(name: "AI News"))
        
        XCTAssertEqual(manager.count, 1, "Duplicate names should be rejected")
    }
    
    func testAddDuplicateNameCaseInsensitive() {
        manager.addSmartFeed(makeSmartFeed(name: "AI News"))
        manager.addSmartFeed(makeSmartFeed(name: "ai news"))
        
        XCTAssertEqual(manager.count, 1, "Case-insensitive duplicate should be rejected")
    }
    
    func testRemoveSmartFeedAtIndex() {
        manager.addSmartFeed(makeSmartFeed(name: "Feed 1"))
        manager.addSmartFeed(makeSmartFeed(name: "Feed 2"))
        
        manager.removeSmartFeed(at: 0)
        
        XCTAssertEqual(manager.count, 1)
        XCTAssertEqual(manager.smartFeeds.first?.name, "Feed 2")
    }
    
    func testRemoveSmartFeedAtInvalidIndex() {
        manager.addSmartFeed(makeSmartFeed())
        
        manager.removeSmartFeed(at: 5)
        manager.removeSmartFeed(at: -1)
        
        XCTAssertEqual(manager.count, 1, "Invalid index should not remove anything")
    }
    
    func testRemoveSmartFeedByName() {
        manager.addSmartFeed(makeSmartFeed(name: "To Remove"))
        manager.addSmartFeed(makeSmartFeed(name: "To Keep"))
        
        manager.removeSmartFeed(byName: "To Remove")
        
        XCTAssertEqual(manager.count, 1)
        XCTAssertEqual(manager.smartFeeds.first?.name, "To Keep")
    }
    
    func testRemoveSmartFeedByNameCaseInsensitive() {
        manager.addSmartFeed(makeSmartFeed(name: "AI News"))
        
        manager.removeSmartFeed(byName: "ai news")
        
        XCTAssertEqual(manager.count, 0)
    }
    
    func testRemoveSmartFeedByNameNonexistent() {
        manager.addSmartFeed(makeSmartFeed(name: "Existing"))
        
        manager.removeSmartFeed(byName: "Nonexistent")
        
        XCTAssertEqual(manager.count, 1, "Removing nonexistent name should be no-op")
    }
    
    func testUpdateSmartFeed() {
        manager.addSmartFeed(makeSmartFeed(name: "Old Name"))
        
        let updated = makeSmartFeed(name: "New Name", keywords: ["new keyword"])
        manager.updateSmartFeed(at: 0, with: updated)
        
        XCTAssertEqual(manager.smartFeeds.first?.name, "New Name")
        XCTAssertEqual(manager.smartFeeds.first?.keywords, ["new keyword"])
    }
    
    func testUpdateSmartFeedAtInvalidIndex() {
        manager.addSmartFeed(makeSmartFeed(name: "Original"))
        
        let updated = makeSmartFeed(name: "Updated")
        manager.updateSmartFeed(at: 5, with: updated)
        
        XCTAssertEqual(manager.smartFeeds.first?.name, "Original", "Invalid index update should be no-op")
    }
    
    func testSmartFeedNamedLookup() {
        manager.addSmartFeed(makeSmartFeed(name: "AI News", keywords: ["ai"]))
        manager.addSmartFeed(makeSmartFeed(name: "Sports", keywords: ["football"]))
        
        let found = manager.smartFeed(named: "AI News")
        XCTAssertNotNil(found)
        XCTAssertEqual(found?.name, "AI News")
    }
    
    // MARK: - SmartFeed Lookup (29–31)
    
    func testSmartFeedNamedCaseInsensitive() {
        manager.addSmartFeed(makeSmartFeed(name: "AI News"))
        
        let found = manager.smartFeed(named: "ai news")
        XCTAssertNotNil(found)
    }
    
    func testSmartFeedNamedNotFound() {
        manager.addSmartFeed(makeSmartFeed(name: "Existing"))
        
        let found = manager.smartFeed(named: "Nonexistent")
        XCTAssertNil(found)
    }
    
    func testSmartFeedNamedEmptyManager() {
        let found = manager.smartFeed(named: "Anything")
        XCTAssertNil(found)
    }
    
    // MARK: - Max Limit (32–33)
    
    func testMaxSmartFeedsLimit() {
        for i in 1...25 {
            manager.addSmartFeed(makeSmartFeed(name: "Feed \(i)", keywords: ["kw\(i)"]))
        }
        
        XCTAssertEqual(manager.count, SmartFeedManager.maxSmartFeeds)
    }
    
    func testMaxSmartFeedsLimitExact() {
        for i in 1...SmartFeedManager.maxSmartFeeds {
            manager.addSmartFeed(makeSmartFeed(name: "Feed \(i)", keywords: ["kw\(i)"]))
        }
        XCTAssertEqual(manager.count, SmartFeedManager.maxSmartFeeds)
        
        // One more should be rejected
        manager.addSmartFeed(makeSmartFeed(name: "Overflow", keywords: ["overflow"]))
        XCTAssertEqual(manager.count, SmartFeedManager.maxSmartFeeds)
    }
    
    // MARK: - Enable/Disable (34–36)
    
    func testEnabledSmartFeeds() {
        let feed1 = makeSmartFeed(name: "Enabled", isEnabled: true)
        let feed2 = makeSmartFeed(name: "Disabled", isEnabled: false)
        manager.addSmartFeed(feed1)
        manager.addSmartFeed(feed2)
        
        XCTAssertEqual(manager.enabledSmartFeeds.count, 1)
        XCTAssertEqual(manager.enabledSmartFeeds.first?.name, "Enabled")
    }
    
    func testAllDisabledSmartFeeds() {
        let feed1 = makeSmartFeed(name: "Disabled1", isEnabled: false)
        let feed2 = makeSmartFeed(name: "Disabled2", isEnabled: false)
        manager.addSmartFeed(feed1)
        manager.addSmartFeed(feed2)
        
        XCTAssertEqual(manager.enabledSmartFeeds.count, 0)
    }
    
    func testToggleEnableDisable() {
        let feed = makeSmartFeed(name: "Toggle", isEnabled: true)
        manager.addSmartFeed(feed)
        
        // Disable it
        feed.isEnabled = false
        manager.updateSmartFeed(at: 0, with: feed)
        
        XCTAssertEqual(manager.enabledSmartFeeds.count, 0)
    }
    
    // MARK: - Matching: Any Mode (37–39)
    
    func testMatchesAnyModeMatchesFirstKeyword() {
        let feed = makeSmartFeed(keywords: ["swift", "kotlin"], matchMode: .any, searchScope: .titleAndBody)
        let story = makeStory(title: "Learn Swift Today", description: "A great tutorial")
        
        XCTAssertTrue(manager.matchesSmartFeed(story, smartFeed: feed))
    }
    
    func testMatchesAnyModeMatchesSecondKeyword() {
        let feed = makeSmartFeed(keywords: ["swift", "kotlin"], matchMode: .any, searchScope: .titleAndBody)
        let story = makeStory(title: "Kotlin Guide", description: "Learn kotlin programming")
        
        XCTAssertTrue(manager.matchesSmartFeed(story, smartFeed: feed))
    }
    
    func testMatchesAnyModeNoMatch() {
        let feed = makeSmartFeed(keywords: ["swift", "kotlin"], matchMode: .any, searchScope: .titleAndBody)
        let story = makeStory(title: "Python Basics", description: "Learn python programming")
        
        XCTAssertFalse(manager.matchesSmartFeed(story, smartFeed: feed))
    }
    
    // MARK: - Matching: All Mode (40–42)
    
    func testMatchesAllModeAllPresent() {
        let feed = makeSmartFeed(keywords: ["swift", "ios"], matchMode: .all, searchScope: .titleAndBody)
        let story = makeStory(title: "Swift for iOS", description: "Build iOS apps with Swift")
        
        XCTAssertTrue(manager.matchesSmartFeed(story, smartFeed: feed))
    }
    
    func testMatchesAllModeOnlyOnePresent() {
        let feed = makeSmartFeed(keywords: ["swift", "android"], matchMode: .all, searchScope: .titleAndBody)
        let story = makeStory(title: "Swift Tutorial", description: "Learn Swift programming")
        
        XCTAssertFalse(manager.matchesSmartFeed(story, smartFeed: feed))
    }
    
    func testMatchesAllModeNonePresent() {
        let feed = makeSmartFeed(keywords: ["rust", "go"], matchMode: .all, searchScope: .titleAndBody)
        let story = makeStory(title: "Python Basics", description: "Learn python")
        
        XCTAssertFalse(manager.matchesSmartFeed(story, smartFeed: feed))
    }
    
    // MARK: - Matching: Search Scope (43–45)
    
    func testMatchesTitleOnly() {
        let feed = makeSmartFeed(keywords: ["swift"], searchScope: .titleOnly)
        let story = makeStory(title: "Swift Tutorial", description: "No keyword in body")
        
        XCTAssertTrue(manager.matchesSmartFeed(story, smartFeed: feed))
    }
    
    func testMatchesTitleOnlyDoesNotMatchBody() {
        let feed = makeSmartFeed(keywords: ["swift"], searchScope: .titleOnly)
        let story = makeStory(title: "Programming Tutorial", description: "Learn Swift here")
        
        XCTAssertFalse(manager.matchesSmartFeed(story, smartFeed: feed))
    }
    
    func testMatchesBodyOnly() {
        let feed = makeSmartFeed(keywords: ["swift"], searchScope: .bodyOnly)
        let story = makeStory(title: "No keyword in title", description: "Learn Swift programming")
        
        XCTAssertTrue(manager.matchesSmartFeed(story, smartFeed: feed))
    }
    
    // MARK: - Matching: Case & Partial (46–48)
    
    func testCaseInsensitiveMatching() {
        let feed = makeSmartFeed(keywords: ["swift"])
        let story = makeStory(title: "SWIFT Programming", description: "About SWIFT language")
        
        XCTAssertTrue(manager.matchesSmartFeed(story, smartFeed: feed))
    }
    
    func testPartialWordMatching() {
        let feed = makeSmartFeed(keywords: ["ai"])
        let story = makeStory(title: "AI safety and FAIR research", description: "Discussing AI")
        
        XCTAssertTrue(manager.matchesSmartFeed(story, smartFeed: feed))
    }
    
    func testSpecialCharactersInKeywords() {
        let feed = makeSmartFeed(keywords: ["c++", "c#"])
        let story = makeStory(title: "Learn C++ Today", description: "C++ programming guide")
        
        XCTAssertTrue(manager.matchesSmartFeed(story, smartFeed: feed))
    }
    
    // MARK: - Matching: Empty / Edge (49–51)
    
    func testEmptyKeywordsMatchNothing() {
        let feed = SmartFeed(name: "Empty", keywords: [])!
        let story = makeStory(title: "Any Title", description: "Any body content")
        
        XCTAssertFalse(manager.matchesSmartFeed(story, smartFeed: feed))
    }
    
    func testMatchesBodyOnlyDoesNotMatchTitle() {
        let feed = makeSmartFeed(keywords: ["swift"], searchScope: .bodyOnly)
        let story = makeStory(title: "Swift Guide", description: "A programming tutorial")
        
        XCTAssertFalse(manager.matchesSmartFeed(story, smartFeed: feed))
    }
    
    func testMatchesTitleAndBody() {
        let feed = makeSmartFeed(keywords: ["tutorial"], searchScope: .titleAndBody)
        let story = makeStory(title: "No match here", description: "A great tutorial")
        
        XCTAssertTrue(manager.matchesSmartFeed(story, smartFeed: feed))
    }
    
    // MARK: - matchingStories (52–55)
    
    func testMatchingStoriesFiltersCorrectly() {
        let feed = makeSmartFeed(keywords: ["swift"])
        let stories = [
            makeStory(title: "Swift News", description: "About Swift", link: "https://example.com/1"),
            makeStory(title: "Python News", description: "About Python", link: "https://example.com/2"),
            makeStory(title: "Swift Tips", description: "More Swift", link: "https://example.com/3")
        ]
        
        let matches = manager.matchingStories(for: feed, in: stories)
        XCTAssertEqual(matches.count, 2)
    }
    
    func testMatchingStoriesEmptyArray() {
        let feed = makeSmartFeed(keywords: ["swift"])
        let matches = manager.matchingStories(for: feed, in: [])
        
        XCTAssertEqual(matches.count, 0)
    }
    
    func testMatchingStoriesNoMatches() {
        let feed = makeSmartFeed(keywords: ["rust"])
        let stories = [
            makeStory(title: "Swift News", description: "About Swift", link: "https://example.com/1"),
            makeStory(title: "Python News", description: "About Python", link: "https://example.com/2")
        ]
        
        let matches = manager.matchingStories(for: feed, in: stories)
        XCTAssertEqual(matches.count, 0)
    }
    
    func testMatchingStoriesAllMatch() {
        let feed = makeSmartFeed(keywords: ["news"])
        let stories = [
            makeStory(title: "Tech News", description: "Technology news", link: "https://example.com/1"),
            makeStory(title: "Sports News", description: "Sports news today", link: "https://example.com/2")
        ]
        
        let matches = manager.matchingStories(for: feed, in: stories)
        XCTAssertEqual(matches.count, 2)
    }
    
    // MARK: - ClearAll (56–57)
    
    func testClearAllRemovesEverything() {
        for i in 1...5 {
            manager.addSmartFeed(makeSmartFeed(name: "Feed \(i)", keywords: ["kw\(i)"]))
        }
        
        manager.clearAll()
        
        XCTAssertEqual(manager.count, 0)
        XCTAssertEqual(manager.enabledSmartFeeds.count, 0)
    }
    
    func testClearAllWhenEmpty() {
        manager.clearAll()
        XCTAssertEqual(manager.count, 0, "Clearing empty manager should be a no-op")
    }
    
    // MARK: - Notifications (58–60)
    
    func testNotificationOnAdd() {
        let feed = makeSmartFeed()
        let expectation = self.expectation(forNotification: SmartFeedManager.smartFeedsDidChangeNotification, object: nil)
        
        manager.addSmartFeed(feed)
        
        wait(for: [expectation], timeout: 1.0)
    }
    
    func testNotificationOnRemove() {
        let feed = makeSmartFeed()
        manager.addSmartFeed(feed)
        
        let expectation = self.expectation(forNotification: SmartFeedManager.smartFeedsDidChangeNotification, object: nil)
        manager.removeSmartFeed(at: 0)
        
        wait(for: [expectation], timeout: 1.0)
    }
    
    func testNotificationOnClearAll() {
        manager.addSmartFeed(makeSmartFeed())
        
        let expectation = self.expectation(forNotification: SmartFeedManager.smartFeedsDidChangeNotification, object: nil)
        manager.clearAll()
        
        wait(for: [expectation], timeout: 1.0)
    }
    
    // MARK: - Persistence (61–63)
    
    func testPersistenceSaveAndLoad() {
        let feed = makeSmartFeed(name: "Persist Me", keywords: ["persistence", "test"],
                                 matchMode: .all, searchScope: .bodyOnly)
        manager.addSmartFeed(feed)
        
        // Create a new manager instance to test loading
        let newManager = SmartFeedManager()
        
        XCTAssertEqual(newManager.count, 1)
        XCTAssertEqual(newManager.smartFeeds.first?.name, "Persist Me")
        XCTAssertEqual(newManager.smartFeeds.first?.keywords, ["persistence", "test"])
        XCTAssertEqual(newManager.smartFeeds.first?.matchMode, .all)
        XCTAssertEqual(newManager.smartFeeds.first?.searchScope, .bodyOnly)
        
        newManager.clearAll()
    }
    
    func testPersistenceAfterRemove() {
        manager.addSmartFeed(makeSmartFeed(name: "Feed 1"))
        manager.addSmartFeed(makeSmartFeed(name: "Feed 2"))
        manager.removeSmartFeed(at: 0)
        
        let newManager = SmartFeedManager()
        XCTAssertEqual(newManager.count, 1)
        XCTAssertEqual(newManager.smartFeeds.first?.name, "Feed 2")
        
        newManager.clearAll()
    }
    
    func testPersistenceAfterClearAll() {
        manager.addSmartFeed(makeSmartFeed(name: "Will Be Cleared"))
        manager.clearAll()
        
        let newManager = SmartFeedManager()
        XCTAssertEqual(newManager.count, 0)
    }
    
    // MARK: - Additional Edge Cases (64–70)
    
    func testSmartFeedCreatedAtIsSet() {
        let before = Date()
        let feed = makeSmartFeed()
        let after = Date()
        
        XCTAssertGreaterThanOrEqual(feed.createdAt, before)
        XCTAssertLessThanOrEqual(feed.createdAt, after)
    }
    
    func testMatchingWithMultiWordKeyword() {
        let feed = makeSmartFeed(keywords: ["machine learning"], matchMode: .any)
        let story = makeStory(title: "Deep Machine Learning Models", description: "About ML")
        
        XCTAssertTrue(manager.matchesSmartFeed(story, smartFeed: feed))
    }
    
    func testMatchingWithMultiWordKeywordNoMatch() {
        let feed = makeSmartFeed(keywords: ["machine learning"], matchMode: .any)
        let story = makeStory(title: "Machine Translation", description: "Learning languages")
        
        // "machine learning" as a phrase should NOT match because "machine" and "learning" are in different fields
        // but since scope is titleAndBody, both words appear in the combined text
        // Actually "machine" is in title, "learning" is in body → combined has both but not as "machine learning" phrase
        // The combined text is "machine translation learning languages" which does NOT contain "machine learning"
        XCTAssertFalse(manager.matchesSmartFeed(story, smartFeed: feed))
    }
    
    func testCountProperty() {
        XCTAssertEqual(manager.count, 0)
        
        manager.addSmartFeed(makeSmartFeed(name: "One"))
        XCTAssertEqual(manager.count, 1)
        
        manager.addSmartFeed(makeSmartFeed(name: "Two"))
        XCTAssertEqual(manager.count, 2)
        
        manager.removeSmartFeed(at: 0)
        XCTAssertEqual(manager.count, 1)
    }
    
    func testUpdatePreservesCount() {
        manager.addSmartFeed(makeSmartFeed(name: "Original"))
        let updated = makeSmartFeed(name: "Updated")
        manager.updateSmartFeed(at: 0, with: updated)
        
        XCTAssertEqual(manager.count, 1)
    }
    
    func testMatchingAllModeWithSingleKeyword() {
        let feed = makeSmartFeed(keywords: ["swift"], matchMode: .all)
        let story = makeStory(title: "Swift Programming", description: "Learn Swift")
        
        XCTAssertTrue(manager.matchesSmartFeed(story, smartFeed: feed))
    }
    
    func testMatchingAnyModeWithSingleKeyword() {
        let feed = makeSmartFeed(keywords: ["swift"], matchMode: .any)
        let story = makeStory(title: "Swift Programming", description: "Learn Swift")
        
        XCTAssertTrue(manager.matchesSmartFeed(story, smartFeed: feed))
    }
}
