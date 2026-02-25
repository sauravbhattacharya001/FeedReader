//
//  ContentFilterTests.swift
//  FeedReaderTests
//
//  Tests for ContentFilter model and ContentFilterManager.
//

import XCTest
@testable import FeedReader

class ContentFilterTests: XCTestCase {
    
    var manager: ContentFilterManager!
    
    override func setUp() {
        super.setUp()
        manager = ContentFilterManager()
        manager.clearAll()
    }
    
    // MARK: - Helper
    
    func makeStory(title: String = "Test Title", body: String = "Test body content", link: String = "https://example.com") -> Story? {
        return Story(title: title, photo: nil, description: body, link: link)
    }
    
    func makeFilter(keyword: String = "test", scope: ContentFilter.MatchScope = .both,
                    mode: ContentFilter.MatchMode = .contains, active: Bool = true) -> ContentFilter? {
        return ContentFilter(keyword: keyword, isActive: active, matchScope: scope, matchMode: mode)
    }
    
    // MARK: - ContentFilter Model Tests
    
    func testFilterInit() {
        let filter = makeFilter(keyword: "spam")
        XCTAssertNotNil(filter)
        XCTAssertEqual(filter?.keyword, "spam")
        XCTAssertTrue(filter?.isActive ?? false)
        XCTAssertEqual(filter?.matchScope, .both)
        XCTAssertEqual(filter?.matchMode, .contains)
        XCTAssertEqual(filter?.mutedCount, 0)
    }
    
    func testFilterInitTrimsWhitespace() {
        let filter = makeFilter(keyword: "  hello  ")
        XCTAssertEqual(filter?.keyword, "hello")
    }
    
    func testFilterInitEmptyKeywordFails() {
        let filter = makeFilter(keyword: "")
        XCTAssertNil(filter)
    }
    
    func testFilterInitWhitespaceOnlyFails() {
        let filter = makeFilter(keyword: "   ")
        XCTAssertNil(filter)
    }
    
    func testFilterInitMaxLength() {
        let longKeyword = String(repeating: "a", count: 300)
        let filter = makeFilter(keyword: longKeyword)
        XCTAssertNotNil(filter)
        XCTAssertEqual(filter?.keyword.count, 200)
    }
    
    func testFilterInitValidRegex() {
        let filter = makeFilter(keyword: "\\d+", mode: .regex)
        XCTAssertNotNil(filter)
    }
    
    func testFilterInitInvalidRegexFails() {
        let filter = makeFilter(keyword: "[invalid", mode: .regex)
        XCTAssertNil(filter)
    }
    
    func testFilterInitCustomScope() {
        let filter = makeFilter(keyword: "test", scope: .title)
        XCTAssertEqual(filter?.matchScope, .title)
    }
    
    func testFilterInitExactWordMode() {
        let filter = makeFilter(keyword: "test", mode: .exactWord)
        XCTAssertEqual(filter?.matchMode, .exactWord)
    }
    
    func testFilterNSSecureCodingRoundTrip() {
        let filter = makeFilter(keyword: "politics")!
        filter.mutedCount = 5
        
        let data = try! NSKeyedArchiver.archivedData(withRootObject: filter, requiringSecureCoding: true)
        let decoded = try! NSKeyedUnarchiver.unarchivedObject(ofClass: ContentFilter.self, from: data)
        
        XCTAssertNotNil(decoded)
        XCTAssertEqual(decoded?.keyword, "politics")
        XCTAssertEqual(decoded?.mutedCount, 5)
        XCTAssertEqual(decoded?.matchScope, .both)
        XCTAssertEqual(decoded?.matchMode, .contains)
        XCTAssertTrue(decoded?.isActive ?? false)
    }
    
    func testFilterCodableRoundTrip() {
        let filter = makeFilter(keyword: "spoiler", scope: .title, mode: .exactWord)!
        filter.mutedCount = 3
        
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try! encoder.encode(filter)
        
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try! decoder.decode(ContentFilter.self, from: data)
        
        XCTAssertEqual(decoded.keyword, "spoiler")
        XCTAssertEqual(decoded.matchScope, .title)
        XCTAssertEqual(decoded.matchMode, .exactWord)
        XCTAssertEqual(decoded.mutedCount, 3)
    }
    
    func testFilterSupportsSecureCoding() {
        XCTAssertTrue(ContentFilter.supportsSecureCoding)
    }
    
    func testFilterUniqueID() {
        let f1 = makeFilter(keyword: "one")!
        let f2 = makeFilter(keyword: "two")!
        XCTAssertNotEqual(f1.id, f2.id)
    }
    
    // MARK: - ContentFilterManager CRUD Tests
    
    func testAddFilter() {
        let filter = makeFilter(keyword: "spam")!
        let result = manager.addFilter(filter)
        XCTAssertTrue(result)
        XCTAssertEqual(manager.filterCount, 1)
    }
    
    func testAddDuplicateFilterFails() {
        let f1 = makeFilter(keyword: "spam")!
        let f2 = makeFilter(keyword: "SPAM")!
        manager.addFilter(f1)
        let result = manager.addFilter(f2)
        XCTAssertFalse(result)
        XCTAssertEqual(manager.filterCount, 1)
    }
    
    func testRemoveFilter() {
        let filter = makeFilter(keyword: "spam")!
        manager.addFilter(filter)
        let result = manager.removeFilter(id: filter.id)
        XCTAssertTrue(result)
        XCTAssertEqual(manager.filterCount, 0)
    }
    
    func testRemoveNonexistentFilterFails() {
        let result = manager.removeFilter(id: "nonexistent")
        XCTAssertFalse(result)
    }
    
    func testToggleFilter() {
        let filter = makeFilter(keyword: "spam")!
        manager.addFilter(filter)
        XCTAssertTrue(filter.isActive)
        manager.toggleFilter(id: filter.id)
        XCTAssertFalse(filter.isActive)
        manager.toggleFilter(id: filter.id)
        XCTAssertTrue(filter.isActive)
    }
    
    func testToggleNonexistentFilterFails() {
        let result = manager.toggleFilter(id: "nonexistent")
        XCTAssertFalse(result)
    }
    
    func testUpdateFilter() {
        let filter = makeFilter(keyword: "old")!
        manager.addFilter(filter)
        let result = manager.updateFilter(id: filter.id, keyword: "new", matchScope: .title, matchMode: .exactWord)
        XCTAssertTrue(result)
        XCTAssertEqual(filter.keyword, "new")
        XCTAssertEqual(filter.matchScope, .title)
        XCTAssertEqual(filter.matchMode, .exactWord)
    }
    
    func testUpdateFilterEmptyKeywordFails() {
        let filter = makeFilter(keyword: "old")!
        manager.addFilter(filter)
        let result = manager.updateFilter(id: filter.id, keyword: "", matchScope: .both, matchMode: .contains)
        XCTAssertFalse(result)
        XCTAssertEqual(filter.keyword, "old")
    }
    
    func testUpdateFilterDuplicateKeywordFails() {
        let f1 = makeFilter(keyword: "one")!
        let f2 = makeFilter(keyword: "two")!
        manager.addFilter(f1)
        manager.addFilter(f2)
        let result = manager.updateFilter(id: f2.id, keyword: "one", matchScope: .both, matchMode: .contains)
        XCTAssertFalse(result)
    }
    
    func testUpdateFilterInvalidRegexFails() {
        let filter = makeFilter(keyword: "old")!
        manager.addFilter(filter)
        let result = manager.updateFilter(id: filter.id, keyword: "[bad", matchScope: .both, matchMode: .regex)
        XCTAssertFalse(result)
    }
    
    func testGetFilter() {
        let filter = makeFilter(keyword: "find me")!
        manager.addFilter(filter)
        let found = manager.getFilter(id: filter.id)
        XCTAssertNotNil(found)
        XCTAssertEqual(found?.keyword, "find me")
    }
    
    func testGetFilterNotFound() {
        let found = manager.getFilter(id: "nope")
        XCTAssertNil(found)
    }
    
    func testClearAll() {
        manager.addFilter(makeFilter(keyword: "a")!)
        manager.addFilter(makeFilter(keyword: "b")!)
        manager.clearAll()
        XCTAssertEqual(manager.filterCount, 0)
    }
    
    func testActiveFilters() {
        let f1 = makeFilter(keyword: "active", active: true)!
        let f2 = makeFilter(keyword: "inactive", active: false)!
        manager.addFilter(f1)
        manager.addFilter(f2)
        XCTAssertEqual(manager.activeFilterCount, 1)
        XCTAssertEqual(manager.activeFilters.count, 1)
        XCTAssertEqual(manager.activeFilters.first?.keyword, "active")
    }
    
    func testMaxFiltersLimit() {
        for i in 0..<50 {
            manager.addFilter(makeFilter(keyword: "kw\(i)")!)
        }
        XCTAssertEqual(manager.filterCount, 50)
        let result = manager.addFilter(makeFilter(keyword: "overflow")!)
        XCTAssertFalse(result)
        XCTAssertEqual(manager.filterCount, 50)
    }
    
    // MARK: - Matching: Contains
    
    func testContainsCaseInsensitive() {
        let filter = makeFilter(keyword: "SPAM", mode: .contains)!
        let story = makeStory(title: "No spam here", body: "Clean body")!
        XCTAssertTrue(manager.matchesFilter(story, filter: filter))
    }
    
    func testContainsNoMatch() {
        let filter = makeFilter(keyword: "xyz123", mode: .contains)!
        let story = makeStory()!
        XCTAssertFalse(manager.matchesFilter(story, filter: filter))
    }
    
    func testContainsSubstring() {
        let filter = makeFilter(keyword: "est", mode: .contains)!
        let story = makeStory(title: "Testing")!
        XCTAssertTrue(manager.matchesFilter(story, filter: filter))
    }
    
    // MARK: - Matching: ExactWord
    
    func testExactWordMatch() {
        let filter = makeFilter(keyword: "test", mode: .exactWord)!
        let story = makeStory(title: "A test case", body: "body")!
        XCTAssertTrue(manager.matchesFilter(story, filter: filter))
    }
    
    func testExactWordNoPartialMatch() {
        let filter = makeFilter(keyword: "test", mode: .exactWord)!
        let story = makeStory(title: "Testing things", body: "untested")!
        XCTAssertFalse(manager.matchesFilter(story, filter: filter))
    }
    
    // MARK: - Matching: Regex
    
    func testRegexMatch() {
        let filter = makeFilter(keyword: "\\d{3}-\\d{4}", mode: .regex)!
        let story = makeStory(title: "Call 555-1234", body: "body")!
        XCTAssertTrue(manager.matchesFilter(story, filter: filter))
    }
    
    func testRegexNoMatch() {
        let filter = makeFilter(keyword: "^xyz$", mode: .regex)!
        let story = makeStory(title: "Something else", body: "body")!
        XCTAssertFalse(manager.matchesFilter(story, filter: filter))
    }
    
    // MARK: - Matching Scopes
    
    func testScopeTitleOnly() {
        let filter = makeFilter(keyword: "secret", scope: .title, mode: .contains)!
        let storyInTitle = makeStory(title: "A secret plan", body: "Clean body")!
        let storyInBody = makeStory(title: "Normal title", body: "A secret plan")!
        XCTAssertTrue(manager.matchesFilter(storyInTitle, filter: filter))
        XCTAssertFalse(manager.matchesFilter(storyInBody, filter: filter))
    }
    
    func testScopeBodyOnly() {
        let filter = makeFilter(keyword: "secret", scope: .body, mode: .contains)!
        let storyInTitle = makeStory(title: "A secret plan", body: "Clean body")!
        let storyInBody = makeStory(title: "Normal title", body: "A secret plan")!
        XCTAssertFalse(manager.matchesFilter(storyInTitle, filter: filter))
        XCTAssertTrue(manager.matchesFilter(storyInBody, filter: filter))
    }
    
    func testScopeBoth() {
        let filter = makeFilter(keyword: "secret", scope: .both, mode: .contains)!
        let storyInTitle = makeStory(title: "A secret plan", body: "Clean body")!
        let storyInBody = makeStory(title: "Normal title", body: "A secret plan")!
        XCTAssertTrue(manager.matchesFilter(storyInTitle, filter: filter))
        XCTAssertTrue(manager.matchesFilter(storyInBody, filter: filter))
    }
    
    // MARK: - shouldMute
    
    func testShouldMuteWithActiveFilter() {
        let filter = makeFilter(keyword: "spam")!
        manager.addFilter(filter)
        let story = makeStory(title: "Spam alert", body: "body")!
        XCTAssertTrue(manager.shouldMute(story))
    }
    
    func testShouldMuteIncrementsMutedCount() {
        let filter = makeFilter(keyword: "spam")!
        manager.addFilter(filter)
        let story = makeStory(title: "Spam alert", body: "body")!
        _ = manager.shouldMute(story)
        XCTAssertEqual(filter.mutedCount, 1)
    }
    
    func testShouldNotMuteCleanStory() {
        let filter = makeFilter(keyword: "spam")!
        manager.addFilter(filter)
        let story = makeStory(title: "Good news", body: "Nice content")!
        XCTAssertFalse(manager.shouldMute(story))
    }
    
    func testShouldNotMuteInactiveFilter() {
        let filter = makeFilter(keyword: "spam", active: false)!
        manager.addFilter(filter)
        let story = makeStory(title: "Spam alert", body: "body")!
        XCTAssertFalse(manager.shouldMute(story))
    }
    
    func testShouldMuteMultipleFilters() {
        manager.addFilter(makeFilter(keyword: "spam")!)
        manager.addFilter(makeFilter(keyword: "ads")!)
        let story = makeStory(title: "Check these ads", body: "body")!
        XCTAssertTrue(manager.shouldMute(story))
    }
    
    // MARK: - filteredStories / mutedStories
    
    func testFilteredStories() {
        manager.addFilter(makeFilter(keyword: "spam")!)
        let s1 = makeStory(title: "Good news", body: "Nice content")!
        let s2 = makeStory(title: "Spam alert", body: "body")!
        let result = manager.filteredStories(from: [s1, s2])
        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result.first?.title, "Good news")
    }
    
    func testMutedStories() {
        manager.addFilter(makeFilter(keyword: "spam")!)
        let s1 = makeStory(title: "Good news", body: "Nice content")!
        let s2 = makeStory(title: "Spam alert", body: "body")!
        let result = manager.mutedStories(from: [s1, s2])
        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result.first?.title, "Spam alert")
    }
    
    func testFilteredStoriesNoFilters() {
        let s1 = makeStory(title: "Anything", body: "goes")!
        let result = manager.filteredStories(from: [s1])
        XCTAssertEqual(result.count, 1)
    }
    
    // MARK: - Muted Count Tracking
    
    func testResetMutedCounts() {
        let filter = makeFilter(keyword: "spam")!
        manager.addFilter(filter)
        let story = makeStory(title: "Spam", body: "body")!
        _ = manager.shouldMute(story)
        XCTAssertEqual(filter.mutedCount, 1)
        manager.resetMutedCounts()
        XCTAssertEqual(filter.mutedCount, 0)
    }
    
    // MARK: - topFilters
    
    func testTopFiltersSorting() {
        let f1 = makeFilter(keyword: "low")!
        f1.mutedCount = 2
        let f2 = makeFilter(keyword: "high")!
        f2.mutedCount = 10
        let f3 = makeFilter(keyword: "mid")!
        f3.mutedCount = 5
        manager.addFilter(f1)
        manager.addFilter(f2)
        manager.addFilter(f3)
        let top = manager.topFilters(limit: 2)
        XCTAssertEqual(top.count, 2)
        XCTAssertEqual(top[0].keyword, "high")
        XCTAssertEqual(top[1].keyword, "mid")
    }
    
    func testTopFiltersLimitExceedsCount() {
        let f1 = makeFilter(keyword: "only")!
        manager.addFilter(f1)
        let top = manager.topFilters(limit: 10)
        XCTAssertEqual(top.count, 1)
    }
    
    // MARK: - Import / Export
    
    func testExportImportRoundTrip() {
        manager.addFilter(makeFilter(keyword: "politics", scope: .title, mode: .exactWord)!)
        manager.addFilter(makeFilter(keyword: "spoiler", scope: .body, mode: .contains)!)
        let json = manager.exportFilters()
        
        let manager2 = ContentFilterManager()
        manager2.clearAll()
        let result = manager2.importFilters(json: json)
        XCTAssertEqual(result.added, 2)
        XCTAssertEqual(result.skipped, 0)
        XCTAssertEqual(result.errors, 0)
        XCTAssertEqual(manager2.filterCount, 2)
    }
    
    func testImportSkipsDuplicates() {
        manager.addFilter(makeFilter(keyword: "existing")!)
        let json = manager.exportFilters()
        let result = manager.importFilters(json: json)
        XCTAssertEqual(result.added, 0)
        XCTAssertEqual(result.skipped, 1)
    }
    
    func testImportInvalidJSON() {
        let result = manager.importFilters(json: "not json")
        XCTAssertEqual(result.errors, 1)
    }
    
    func testExportEmptyFilters() {
        let json = manager.exportFilters()
        XCTAssertEqual(json, "[\n\n]")
    }
    
    // MARK: - Edge Cases
    
    func testEmptyStoryTitle() {
        // Story with empty title won't init (returns nil), so test filter against body match
        let filter = makeFilter(keyword: "content", scope: .body)!
        let story = makeStory(title: "Has title", body: "Some content here")!
        XCTAssertTrue(manager.matchesFilter(story, filter: filter))
    }
    
    func testOverlappingFilters() {
        manager.addFilter(makeFilter(keyword: "spam")!)
        manager.addFilter(makeFilter(keyword: "alert")!)
        let story = makeStory(title: "Spam alert", body: "body")!
        // Both match but shouldMute returns true on first match
        XCTAssertTrue(manager.shouldMute(story))
    }
    
    func testFilterCountAndActiveCount() {
        manager.addFilter(makeFilter(keyword: "a", active: true)!)
        manager.addFilter(makeFilter(keyword: "b", active: false)!)
        manager.addFilter(makeFilter(keyword: "c", active: true)!)
        XCTAssertEqual(manager.filterCount, 3)
        XCTAssertEqual(manager.activeFilterCount, 2)
    }
    
    func testNotificationPosted() {
        let expectation = self.expectation(forNotification: ContentFilterManager.contentFiltersDidChangeNotification, object: nil)
        manager.addFilter(makeFilter(keyword: "notify")!)
        wait(for: [expectation], timeout: 1.0)
    }
    
    func testContainsMatchInBody() {
        let filter = makeFilter(keyword: "hidden", scope: .both)!
        let story = makeStory(title: "Normal", body: "A hidden message")!
        XCTAssertTrue(manager.matchesFilter(story, filter: filter))
    }
    
    func testExactWordCaseInsensitive() {
        let filter = makeFilter(keyword: "Test", mode: .exactWord)!
        let story = makeStory(title: "A TEST case", body: "body")!
        XCTAssertTrue(manager.matchesFilter(story, filter: filter))
    }
    
    func testRegexCaseInsensitive() {
        let filter = makeFilter(keyword: "spam", mode: .regex)!
        let story = makeStory(title: "SPAM here", body: "body")!
        XCTAssertTrue(manager.matchesFilter(story, filter: filter))
    }
    
    func testUpdateFilterSameKeywordSameId() {
        let filter = makeFilter(keyword: "same")!
        manager.addFilter(filter)
        let result = manager.updateFilter(id: filter.id, keyword: "same", matchScope: .title, matchMode: .exactWord)
        XCTAssertTrue(result)
    }
    
    func testFilterWithSpecialCharactersContains() {
        let filter = makeFilter(keyword: "c++", mode: .contains)!
        let story = makeStory(title: "Learn C++ today", body: "body")!
        XCTAssertTrue(manager.matchesFilter(story, filter: filter))
    }
    
    func testExactWordWithSpecialChars() {
        let filter = makeFilter(keyword: "c++", mode: .exactWord)!
        let story = makeStory(title: "Learn c++ today", body: "body")!
        // NSRegularExpression.escapedPattern handles the ++
        XCTAssertTrue(manager.matchesFilter(story, filter: filter))
    }
    
    func testEmptyBodyScopeBody() {
        // Story requires non-empty body so we test with minimal body
        let filter = makeFilter(keyword: "xyz", scope: .body)!
        let story = makeStory(title: "Title", body: "no match here")!
        XCTAssertFalse(manager.matchesFilter(story, filter: filter))
    }
    
    func testMultipleScopesMultipleFilters() {
        let f1 = makeFilter(keyword: "title-word", scope: .title)!
        let f2 = makeFilter(keyword: "body-word", scope: .body)!
        manager.addFilter(f1)
        manager.addFilter(f2)
        let story = makeStory(title: "Has title-word", body: "Has body-word")!
        XCTAssertTrue(manager.shouldMute(story))
    }
    
    func testInactiveFilterDoesNotMatch() {
        let filter = makeFilter(keyword: "hidden", active: false)!
        manager.addFilter(filter)
        let story = makeStory(title: "hidden content", body: "body")!
        let filtered = manager.filteredStories(from: [story])
        XCTAssertEqual(filtered.count, 1) // not filtered out
    }
    
    func testMutedStoriesEmpty() {
        manager.addFilter(makeFilter(keyword: "nothing")!)
        let story = makeStory(title: "All good", body: "Clean content")!
        let muted = manager.mutedStories(from: [story])
        XCTAssertEqual(muted.count, 0)
    }
}
