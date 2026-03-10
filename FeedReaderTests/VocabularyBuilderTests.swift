//
//  VocabularyBuilderTests.swift
//  FeedReaderTests
//

import XCTest
@testable import FeedReader

class VocabularyBuilderTests: XCTestCase {
    var builder: VocabularyBuilder!
    var calendar: Calendar!

    override func setUp() {
        super.setUp()
        calendar = Calendar.current
        builder = VocabularyBuilder(calendar: calendar, persistencePath: nil)
    }

    func testAddWord() {
        let entry = builder.addWord("ephemeral")
        XCTAssertEqual(entry.word, "ephemeral")
        XCTAssertEqual(entry.mastery, .new)
        XCTAssertEqual(builder.wordCount, 1)
    }

    func testAddWordNormalises() {
        builder.addWord("  Ephemeral  ")
        XCTAssertTrue(builder.contains("ephemeral"))
        XCTAssertTrue(builder.contains("EPHEMERAL"))
        XCTAssertEqual(builder.wordCount, 1)
    }

    func testAddEmptyWord() {
        let entry = builder.addWord("")
        XCTAssertEqual(entry.word, "")
        XCTAssertEqual(builder.wordCount, 0)
    }

    func testAddWordWithDefinition() {
        let entry = builder.addWord("ubiquitous", definition: "present everywhere")
        XCTAssertEqual(entry.definition, "present everywhere")
    }

    func testAddWordWithContext() {
        let ctx = WordContext(sentence: "The ubiquitous nature of smartphones.", articleTitle: "Tech",
            articleLink: "https://example.com", feedName: "TechCrunch", date: Date())
        let entry = builder.addWord("ubiquitous", context: ctx)
        XCTAssertEqual(entry.contexts.count, 1)
        XCTAssertEqual(entry.contexts.first?.feedName, "TechCrunch")
    }

    func testAddExistingWordAppendsContext() {
        let ctx1 = WordContext(sentence: "S1", articleTitle: "A1", articleLink: "", feedName: "F1", date: Date())
        let ctx2 = WordContext(sentence: "S2", articleTitle: "A2", articleLink: "", feedName: "F2", date: Date())
        builder.addWord("paradigm", context: ctx1)
        builder.addWord("paradigm", context: ctx2)
        XCTAssertEqual(builder.lookup("paradigm")?.contexts.count, 2)
    }

    func testContextCappedAt50() {
        for i in 0..<55 {
            let ctx = WordContext(sentence: "S\(i)", articleTitle: "A", articleLink: "", feedName: "F", date: Date())
            builder.addWord("prolific", context: ctx)
        }
        XCTAssertEqual(builder.lookup("prolific")?.contexts.count, 50)
    }

    func testAddWordWithTags() {
        let entry = builder.addWord("mitochondria", tags: ["biology", "science"])
        XCTAssertEqual(entry.tags, ["biology", "science"])
    }

    func testAddWordMergesTags() {
        builder.addWord("mitochondria", tags: ["biology"])
        builder.addWord("mitochondria", tags: ["science"])
        let e = builder.lookup("mitochondria")
        XCTAssertEqual(e?.tags.count, 2)
        XCTAssertTrue(e?.tags.contains("biology") ?? false)
    }

    func testAddWordAutoEstimates() {
        XCTAssertEqual(builder.addWord("cat").difficulty, .basic)
        XCTAssertTrue(builder.addWord("antidisestablishmentarianism").difficulty >= .advanced)
    }

    func testAddWordCustomDifficulty() {
        XCTAssertEqual(builder.addWord("synapse", difficulty: .expert).difficulty, .expert)
    }

    func testRemoveWord() {
        builder.addWord("ephemeral")
        XCTAssertTrue(builder.removeWord("ephemeral"))
        XCTAssertEqual(builder.wordCount, 0)
    }

    func testRemoveNonexistent() { XCTAssertFalse(builder.removeWord("nope")) }

    func testLookup() {
        builder.addWord("paradigm", definition: "a model")
        XCTAssertEqual(builder.lookup("paradigm")?.definition, "a model")
    }

    func testLookupMissing() { XCTAssertNil(builder.lookup("nope")) }

    func testSetDefinition() {
        builder.addWord("entropy")
        builder.setDefinition("entropy", definition: "disorder")
        XCTAssertEqual(builder.lookup("entropy")?.definition, "disorder")
    }

    func testSetNote() {
        builder.addWord("entropy")
        builder.setNote("entropy", note: "thermodynamics")
        XCTAssertEqual(builder.lookup("entropy")?.note, "thermodynamics")
    }

    func testToggleStar() {
        builder.addWord("quixotic")
        XCTAssertTrue(builder.toggleStar("quixotic"))
        XCTAssertTrue(builder.lookup("quixotic")?.starred ?? false)
        XCTAssertFalse(builder.toggleStar("quixotic"))
    }

    func testToggleStarNonexistent() { XCTAssertFalse(builder.toggleStar("nope")) }

    func testSetTags() {
        builder.addWord("paradigm")
        builder.setTags("paradigm", tags: ["philosophy", "science"])
        XCTAssertEqual(builder.lookup("paradigm")?.tags, ["philosophy", "science"])
    }

    func testAllWords() {
        builder.addWord("a"); builder.addWord("b"); builder.addWord("c")
        XCTAssertEqual(builder.allWords().count, 3)
    }

    func testFilterByDifficulty() {
        builder.addWord("cat", difficulty: .basic)
        builder.addWord("ubiquitous", difficulty: .advanced)
        builder.addWord("mitochondria", difficulty: .advanced)
        XCTAssertEqual(builder.words(difficulty: .advanced).count, 2)
    }

    func testFilterByMastery() {
        builder.addWord("a"); builder.addWord("b")
        XCTAssertEqual(builder.words(mastery: .new).count, 2)
    }

    func testSearch() {
        builder.addWord("paradigm", definition: "a model or pattern")
        builder.addWord("entropy", definition: "measure of disorder")
        let r = builder.search("model")
        XCTAssertEqual(r.count, 1)
        XCTAssertEqual(r.first?.word, "paradigm")
    }

    func testSearchByTag() {
        builder.addWord("mitochondria", tags: ["biology"])
        builder.addWord("entropy", tags: ["physics"])
        XCTAssertEqual(builder.search("biology").count, 1)
    }

    func testWordsByTag() {
        builder.addWord("mitochondria", tags: ["biology"])
        builder.addWord("ribosome", tags: ["biology"])
        builder.addWord("entropy", tags: ["physics"])
        XCTAssertEqual(builder.words(tag: "biology").count, 2)
    }

    func testStarredWords() {
        builder.addWord("a"); builder.addWord("b"); builder.toggleStar("a")
        XCTAssertEqual(builder.starredWords().count, 1)
    }

    func testAllTags() {
        builder.addWord("a", tags: ["science"]); builder.addWord("b", tags: ["art", "science"])
        XCTAssertEqual(builder.allTags(), ["art", "science"])
    }

    func testRecordReviewCorrect() {
        builder.addWord("paradigm")
        let u = builder.recordReview("paradigm", correct: true)
        XCTAssertEqual(u?.reviewCount, 1); XCTAssertEqual(u?.correctCount, 1)
        XCTAssertEqual(u?.mastery, .learning)
    }

    func testRecordReviewIncorrect() {
        builder.addWord("paradigm")
        _ = builder.recordReview("paradigm", correct: true)
        let u = builder.recordReview("paradigm", correct: false)
        XCTAssertEqual(u?.mastery, .learning); XCTAssertEqual(u?.reviewCount, 2)
    }

    func testMasteryProgression() {
        builder.addWord("paradigm")
        var e = builder.recordReview("paradigm", correct: true); XCTAssertEqual(e?.mastery, .learning)
        e = builder.recordReview("paradigm", correct: true); XCTAssertEqual(e?.mastery, .familiar)
        e = builder.recordReview("paradigm", correct: true); XCTAssertEqual(e?.mastery, .familiar)
        e = builder.recordReview("paradigm", correct: true); XCTAssertEqual(e?.mastery, .confident)
    }

    func testMasteryRegression() {
        builder.addWord("paradigm")
        _ = builder.recordReview("paradigm", correct: true)
        _ = builder.recordReview("paradigm", correct: true)
        XCTAssertEqual(builder.recordReview("paradigm", correct: false)?.mastery, .learning)
    }

    func testRecordReviewNonexistent() { XCTAssertNil(builder.recordReview("nope", correct: true)) }

    func testDifficultyEstimation() {
        XCTAssertEqual(WordDifficultyEstimator.estimate("the"), .basic)
        XCTAssertEqual(WordDifficultyEstimator.estimate("cat"), .basic)
        XCTAssertTrue(WordDifficultyEstimator.estimate("antidisestablishmentarianism") >= .advanced)
    }

    func testSyllableEstimation() {
        XCTAssertEqual(WordDifficultyEstimator.estimateSyllables("cat"), 1)
        XCTAssertEqual(WordDifficultyEstimator.estimateSyllables("hello"), 2)
        XCTAssertTrue(WordDifficultyEstimator.estimateSyllables("university") >= 4)
    }

    func testSuggestWords() {
        let text = "The pharmaceutical industry has seen unprecedented consolidation through mergers. Regulatory frameworks for biotechnological innovations remain fragmented."
        let s = builder.suggestWords(from: text)
        XCTAssertTrue(s.count > 0)
        XCTAssertFalse(s.map { $0.word }.contains("the"))
    }

    func testSuggestWordsSkipsExisting() {
        builder.addWord("pharmaceutical")
        let s = builder.suggestWords(from: "The pharmaceutical industry is growing.")
        XCTAssertFalse(s.map { $0.word }.contains("pharmaceutical"))
    }

    func testSuggestWordsLimit() {
        let text = "Antidisestablishmentarianism, floccinaucinihilipilification, supercalifragilisticexpialidocious, thyroparathyroidectomized."
        XCTAssertTrue(builder.suggestWords(from: text, maxSuggestions: 2).count <= 2)
    }

    func testStatsEmpty() {
        let s = builder.stats()
        XCTAssertEqual(s.totalWords, 0); XCTAssertEqual(s.totalReviews, 0); XCTAssertEqual(s.dueForReview, 0)
    }

    func testStatsWithData() {
        builder.addWord("paradigm", difficulty: .advanced)
        builder.addWord("entropy", difficulty: .moderate)
        builder.addWord("quixotic", difficulty: .advanced)
        _ = builder.recordReview("paradigm", correct: true)
        _ = builder.recordReview("paradigm", correct: true)
        let s = builder.stats()
        XCTAssertEqual(s.totalWords, 3); XCTAssertEqual(s.byDifficulty[.advanced], 2)
        XCTAssertEqual(s.totalReviews, 2); XCTAssertTrue(s.averageAccuracy == 1.0)
    }

    func testStatsRecent() {
        builder.addWord("a"); builder.addWord("b")
        let s = builder.stats()
        XCTAssertEqual(s.wordsAddedLast7Days, 2); XCTAssertEqual(s.wordsAddedLast30Days, 2)
    }

    func testWordsFromFeed() {
        let ctx = WordContext(sentence: "T", articleTitle: "A", articleLink: "", feedName: "TC", date: Date())
        builder.addWord("paradigm", context: ctx); builder.addWord("entropy")
        XCTAssertEqual(builder.wordsFromFeed("TC").count, 1)
    }

    func testExportImport() {
        builder.addWord("paradigm", definition: "a model")
        builder.addWord("entropy", difficulty: .expert)
        let json = builder.exportJSON()
        let b2 = VocabularyBuilder(calendar: calendar, persistencePath: nil)
        XCTAssertEqual(b2.importJSON(json), 2)
        XCTAssertTrue(b2.contains("paradigm")); XCTAssertTrue(b2.contains("entropy"))
    }

    func testImportSkipsDuplicates() {
        builder.addWord("paradigm")
        let json = builder.exportJSON()
        let b2 = VocabularyBuilder(calendar: calendar, persistencePath: nil)
        b2.addWord("paradigm")
        XCTAssertEqual(b2.importJSON(json), 0)
    }

    func testImportRejectsOversized() {
        XCTAssertEqual(builder.importJSON(String(repeating: "x", count: 10_485_761)), 0)
    }

    func testImportRejectsInvalid() { XCTAssertEqual(builder.importJSON("bad"), 0) }

    func testReset() {
        builder.addWord("a"); builder.addWord("b"); builder.reset()
        XCTAssertEqual(builder.wordCount, 0)
    }

    func testSchedulerCorrect() {
        let e = VocabularyEntry(word: "t", difficulty: .moderate, definition: nil, note: nil, contexts: [],
            reviewCount: 2, correctCount: 2, mastery: .learning, addedDate: Date(), lastReviewDate: nil,
            nextReviewDate: nil, tags: [], starred: false)
        let (m, n) = SpacedRepetitionScheduler.schedule(entry: e, correct: true)
        XCTAssertEqual(m, .familiar); XCTAssertTrue(n > Date())
    }

    func testSchedulerIncorrect() {
        let e = VocabularyEntry(word: "t", difficulty: .moderate, definition: nil, note: nil, contexts: [],
            reviewCount: 5, correctCount: 3, mastery: .confident, addedDate: Date(), lastReviewDate: nil,
            nextReviewDate: nil, tags: [], starred: false)
        XCTAssertEqual(SpacedRepetitionScheduler.schedule(entry: e, correct: false).mastery, .familiar)
    }

    func testSchedulerMasteredStays() {
        let e = VocabularyEntry(word: "t", difficulty: .moderate, definition: nil, note: nil, contexts: [],
            reviewCount: 10, correctCount: 9, mastery: .mastered, addedDate: Date(), lastReviewDate: nil,
            nextReviewDate: nil, tags: [], starred: false)
        XCTAssertEqual(SpacedRepetitionScheduler.schedule(entry: e, correct: true).mastery, .mastered)
    }

    func testDifficultyOrdering() {
        XCTAssertTrue(WordDifficulty.basic < .moderate)
        XCTAssertTrue(WordDifficulty.moderate < .advanced)
        XCTAssertTrue(WordDifficulty.advanced < .expert)
    }
}
