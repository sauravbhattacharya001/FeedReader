//
//  VocabularyBuilderTests.swift
//  FeedReaderTests
//
//  Tests for VocabularyBuilder — word extraction, mastery tracking,
//  review scheduling, filtering, search, import/export, and statistics.
//

import XCTest
@testable import FeedReader

class VocabularyBuilderTests: XCTestCase {
    
    var builder: VocabularyBuilder!
    
    override func setUp() {
        super.setUp()
        builder = VocabularyBuilder.shared
        builder.clearAll()
    }
    
    override func tearDown() {
        builder.clearAll()
        super.tearDown()
    }
    
    // MARK: - Word Extraction
    
    func testExtractWordsFiltersCommon() {
        let text = "The government established unprecedented regulations for the environment."
        let words = builder.extractWords(from: text)
        XCTAssertTrue(words.contains("government"))
        XCTAssertTrue(words.contains("established"))
        XCTAssertTrue(words.contains("unprecedented"))
        XCTAssertTrue(words.contains("regulations"))
        XCTAssertTrue(words.contains("environment"))
        // "the" and "for" should be filtered
        XCTAssertFalse(words.contains("the"))
        XCTAssertFalse(words.contains("for"))
    }
    
    func testExtractWordsMinLength() {
        let text = "A big cat ran fast across the field"
        let words = builder.extractWords(from: text)
        // Words under 6 chars should be excluded
        XCTAssertFalse(words.contains("big"))
        XCTAssertFalse(words.contains("cat"))
        XCTAssertFalse(words.contains("ran"))
        XCTAssertFalse(words.contains("fast"))
        XCTAssertTrue(words.contains("across"))
    }
    
    func testExtractWordsDeduplicates() {
        let text = "Technology drives technology forward with technology"
        let words = builder.extractWords(from: text)
        let techCount = words.filter { $0 == "technology" }.count
        XCTAssertEqual(techCount, 1)
    }
    
    func testExtractWordsEmptyText() {
        let words = builder.extractWords(from: "")
        XCTAssertTrue(words.isEmpty)
    }
    
    // MARK: - Context Sentence
    
    func testContextSentenceFound() {
        let text = "The economy is growing. Inflation remains unprecedented in recent years. Markets are stable."
        let context = builder.contextSentence(for: "unprecedented", in: text)
        XCTAssertTrue(context.contains("unprecedented"))
        XCTAssertTrue(context.hasSuffix("."))
    }
    
    func testContextSentenceNotFound() {
        let text = "The sky is blue. The grass is green."
        let context = builder.contextSentence(for: "extraordinary", in: text)
        XCTAssertEqual(context, "")
    }
    
    // MARK: - Process Article
    
    func testProcessArticleAddsWords() {
        let body = "The unprecedented transformation of cryptocurrency markets demonstrates remarkable volatility and extraordinary resilience."
        let added = builder.processArticle(title: "Crypto News", body: body, feedName: "TechCrunch")
        XCTAssertGreaterThan(added.count, 0)
        XCTAssertTrue(added.allSatisfy { $0.sourceFeedName == "TechCrunch" })
        XCTAssertTrue(added.allSatisfy { $0.sourceArticleTitle == "Crypto News" })
    }
    
    func testProcessArticleMaxWords() {
        let body = "Extraordinary unprecedented remarkable significant comprehensive substantial magnificent revolutionary transformative exceptional"
        let added = builder.processArticle(title: "Test", body: body, feedName: "Feed", maxWords: 3)
        XCTAssertLessThanOrEqual(added.count, 3)
    }
    
    func testProcessArticleSkipsDuplicates() {
        let body = "Unprecedented changes in the technological landscape"
        _ = builder.processArticle(title: "First", body: body, feedName: "Feed1")
        let secondAdded = builder.processArticle(title: "Second", body: body, feedName: "Feed2")
        XCTAssertEqual(secondAdded.count, 0)
    }
    
    // MARK: - Manual Add/Remove
    
    func testAddWord() {
        builder.addWord("serendipity", context: "A moment of serendipity.", articleTitle: "Life", feedName: "Blog")
        XCTAssertEqual(builder.words.count, 1)
        XCTAssertEqual(builder.words.first?.word, "serendipity")
        XCTAssertEqual(builder.words.first?.masteryLevel, .new)
    }
    
    func testAddDuplicateWordIgnored() {
        builder.addWord("serendipity", context: "Context 1", articleTitle: "A1", feedName: "F1")
        builder.addWord("Serendipity", context: "Context 2", articleTitle: "A2", feedName: "F2")
        XCTAssertEqual(builder.words.count, 1)
    }
    
    func testRemoveWord() {
        builder.addWord("ephemeral", context: "Test", articleTitle: "A", feedName: "F")
        XCTAssertEqual(builder.words.count, 1)
        builder.removeWord("ephemeral")
        XCTAssertEqual(builder.words.count, 0)
    }
    
    func testClearAll() {
        builder.addWord("alpha", context: "", articleTitle: "", feedName: "")
        builder.addWord("bravo", context: "", articleTitle: "", feedName: "")
        builder.clearAll()
        XCTAssertTrue(builder.words.isEmpty)
    }
    
    // MARK: - Mastery & Review
    
    func testReviewWordAdvancesMastery() {
        builder.addWord("catalyst", context: "", articleTitle: "", feedName: "")
        XCTAssertEqual(builder.words.first?.masteryLevel, .new)
        
        builder.reviewWord("catalyst", knewIt: true)
        XCTAssertEqual(builder.words.first?.masteryLevel, .learning)
        XCTAssertEqual(builder.words.first?.reviewCount, 1)
        
        builder.reviewWord("catalyst", knewIt: true)
        XCTAssertEqual(builder.words.first?.masteryLevel, .familiar)
        
        builder.reviewWord("catalyst", knewIt: true)
        XCTAssertEqual(builder.words.first?.masteryLevel, .mastered)
    }
    
    func testReviewWordDemotesMastery() {
        builder.addWord("catalyst", context: "", articleTitle: "", feedName: "")
        builder.reviewWord("catalyst", knewIt: true) // -> learning
        builder.reviewWord("catalyst", knewIt: false) // -> new
        XCTAssertEqual(builder.words.first?.masteryLevel, .new)
    }
    
    func testReviewWordCapsAtMastered() {
        builder.addWord("catalyst", context: "", articleTitle: "", feedName: "")
        for _ in 0..<10 { builder.reviewWord("catalyst", knewIt: true) }
        XCTAssertEqual(builder.words.first?.masteryLevel, .mastered)
    }
    
    func testReviewWordDoesNotGoBelowNew() {
        builder.addWord("catalyst", context: "", articleTitle: "", feedName: "")
        builder.reviewWord("catalyst", knewIt: false)
        XCTAssertEqual(builder.words.first?.masteryLevel, .new)
    }
    
    func testWordsDueForReview() {
        builder.addWord("ancient", context: "", articleTitle: "", feedName: "")
        // Newly added word with nextReviewDate = dateAdded + 1 day, so not due yet
        let due = builder.wordsDueForReview()
        XCTAssertEqual(due.count, 0)
    }
    
    // MARK: - Filtering
    
    func testFilterByMastery() {
        builder.addWord("alpha", context: "", articleTitle: "", feedName: "")
        builder.addWord("bravo", context: "", articleTitle: "", feedName: "")
        builder.reviewWord("bravo", knewIt: true) // -> learning
        
        XCTAssertEqual(builder.words(at: .new).count, 1)
        XCTAssertEqual(builder.words(at: .learning).count, 1)
    }
    
    func testFilterByFeed() {
        builder.addWord("alpha", context: "", articleTitle: "", feedName: "BBC")
        builder.addWord("bravo", context: "", articleTitle: "", feedName: "NPR")
        
        XCTAssertEqual(builder.words(fromFeed: "BBC").count, 1)
        XCTAssertEqual(builder.words(fromFeed: "NPR").count, 1)
        XCTAssertEqual(builder.words(fromFeed: "CNN").count, 0)
    }
    
    func testSearchWords() {
        builder.addWord("algorithm", context: "", articleTitle: "", feedName: "")
        builder.addWord("algebra", context: "", articleTitle: "", feedName: "")
        builder.addWord("biology", context: "", articleTitle: "", feedName: "")
        
        XCTAssertEqual(builder.searchWords("alg").count, 2)
        XCTAssertEqual(builder.searchWords("bio").count, 1)
        XCTAssertEqual(builder.searchWords("xyz").count, 0)
    }
    
    // MARK: - Statistics
    
    func testGenerateStats() {
        builder.addWord("alpha", context: "", articleTitle: "", feedName: "BBC")
        builder.addWord("bravo", context: "", articleTitle: "", feedName: "BBC")
        builder.addWord("charlie", context: "", articleTitle: "", feedName: "NPR")
        
        let stats = builder.generateStats()
        XCTAssertEqual(stats.totalWords, 3)
        XCTAssertEqual(stats.newCount, 3)
        XCTAssertEqual(stats.wordsAddedToday, 3)
        XCTAssertGreaterThan(stats.topSources.count, 0)
    }
    
    func testStatsEmptyVocabulary() {
        let stats = builder.generateStats()
        XCTAssertEqual(stats.totalWords, 0)
        XCTAssertEqual(stats.masteryPercentage, 0.0)
    }
    
    // MARK: - Export / Import
    
    func testExportJSON() {
        builder.addWord("quantum", context: "Quantum computing.", articleTitle: "Tech", feedName: "Wired")
        let data = builder.exportAsJSON()
        XCTAssertNotNil(data)
    }
    
    func testExportCSV() {
        builder.addWord("quantum", context: "Quantum computing.", articleTitle: "Tech", feedName: "Wired")
        let csv = builder.exportAsCSV()
        XCTAssertTrue(csv.contains("quantum"))
        XCTAssertTrue(csv.contains("Word,Mastery"))
    }
    
    func testImportJSON() {
        builder.addWord("original", context: "", articleTitle: "", feedName: "")
        let data = builder.exportAsJSON()!
        builder.clearAll()
        
        let imported = builder.importFromJSON(data)
        XCTAssertEqual(imported, 1)
        XCTAssertEqual(builder.words.first?.word, "original")
    }
    
    func testImportJSONSkipsDuplicates() {
        builder.addWord("existing", context: "", articleTitle: "", feedName: "")
        let data = builder.exportAsJSON()!
        
        let imported = builder.importFromJSON(data)
        XCTAssertEqual(imported, 0) // already exists
        XCTAssertEqual(builder.words.count, 1)
    }
    
    func testImportInvalidJSON() {
        let badData = "not json".data(using: .utf8)!
        let imported = builder.importFromJSON(badData)
        XCTAssertEqual(imported, 0)
    }
    
    // MARK: - VocabularyWord Model
    
    func testWordEquality() {
        let w1 = VocabularyWord(word: "test", contextSentence: "", sourceArticleTitle: "", sourceFeedName: "")
        let w2 = VocabularyWord(word: "test", contextSentence: "different", sourceArticleTitle: "different", sourceFeedName: "different")
        XCTAssertEqual(w1, w2)
    }
    
    func testMasteryLevelComparable() {
        XCTAssertTrue(VocabularyWord.MasteryLevel.new < .learning)
        XCTAssertTrue(VocabularyWord.MasteryLevel.learning < .familiar)
        XCTAssertTrue(VocabularyWord.MasteryLevel.familiar < .mastered)
    }
    
    func testMasteryDisplayNames() {
        XCTAssertEqual(VocabularyWord.MasteryLevel.new.displayName, "New")
        XCTAssertEqual(VocabularyWord.MasteryLevel.learning.displayName, "Learning")
        XCTAssertEqual(VocabularyWord.MasteryLevel.familiar.displayName, "Familiar")
        XCTAssertEqual(VocabularyWord.MasteryLevel.mastered.displayName, "Mastered")
    }
    
    func testMasteryReviewIntervals() {
        XCTAssertEqual(VocabularyWord.MasteryLevel.new.reviewIntervalDays, 1)
        XCTAssertEqual(VocabularyWord.MasteryLevel.learning.reviewIntervalDays, 3)
        XCTAssertEqual(VocabularyWord.MasteryLevel.familiar.reviewIntervalDays, 7)
        XCTAssertEqual(VocabularyWord.MasteryLevel.mastered.reviewIntervalDays, 30)
    }
    
    // MARK: - Notifications
    
    func testVocabularyUpdateNotification() {
        let expectation = self.expectation(forNotification: .vocabularyDidUpdate, object: builder)
        builder.addWord("notification", context: "", articleTitle: "", feedName: "")
        wait(for: [expectation], timeout: 1.0)
    }
    
    func testMasteryChangeNotification() {
        builder.addWord("mastery", context: "", articleTitle: "", feedName: "")
        let expectation = self.expectation(forNotification: .vocabularyMasteryDidChange, object: builder)
        builder.reviewWord("mastery", knewIt: true)
        wait(for: [expectation], timeout: 1.0)
    }
}
