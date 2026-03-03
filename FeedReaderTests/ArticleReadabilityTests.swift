//
//  ArticleReadabilityTests.swift
//  FeedReaderTests
//
//  Tests for ArticleReadabilityAnalyzer — Flesch scores, syllable counting,
//  sentence detection, HTML stripping, and difficulty classification.
//

import XCTest
@testable import FeedReader

class ArticleReadabilityTests: XCTestCase {

    var analyzer: ArticleReadabilityAnalyzer!

    override func setUp() {
        super.setUp()
        analyzer = ArticleReadabilityAnalyzer.shared
    }

    // MARK: - Basic Analysis

    func testAnalyzeSimpleText() {
        let result = analyzer.analyze("The cat sat on the mat. The dog ran fast.")
        XCTAssertNotNil(result)
        XCTAssertEqual(result!.wordCount, 10)
        XCTAssertEqual(result!.sentenceCount, 2)
        XCTAssertEqual(result!.averageWordsPerSentence, 5.0, accuracy: 0.01)
    }

    func testAnalyzeReturnsNilForEmptyText() {
        XCTAssertNil(analyzer.analyze(""))
    }

    func testAnalyzeReturnsNilForWhitespaceOnly() {
        XCTAssertNil(analyzer.analyze("   \n\t  "))
    }

    func testAnalyzeReturnsNilForHTMLOnlyText() {
        XCTAssertNil(analyzer.analyze("<div></div><br/>"))
    }

    func testAnalyzeSingleWord() {
        let result = analyzer.analyze("Hello")
        XCTAssertNotNil(result)
        XCTAssertEqual(result!.wordCount, 1)
        XCTAssertEqual(result!.sentenceCount, 1)
    }

    func testAnalyzeSingleSentence() {
        let result = analyzer.analyze("This is a simple sentence.")
        XCTAssertNotNil(result)
        XCTAssertEqual(result!.sentenceCount, 1)
        XCTAssertEqual(result!.wordCount, 5)
    }

    // MARK: - Syllable Counting

    func testCountSyllablesMonosyllabic() {
        XCTAssertEqual(analyzer.countSyllables("cat"), 1)
        XCTAssertEqual(analyzer.countSyllables("dog"), 1)
        XCTAssertEqual(analyzer.countSyllables("run"), 1)
        XCTAssertEqual(analyzer.countSyllables("the"), 1)
    }

    func testCountSyllablesTwoSyllables() {
        XCTAssertEqual(analyzer.countSyllables("apple"), 2)
        XCTAssertEqual(analyzer.countSyllables("water"), 2)
        XCTAssertEqual(analyzer.countSyllables("happy"), 2)
    }

    func testCountSyllablesThreeSyllables() {
        XCTAssertEqual(analyzer.countSyllables("beautiful"), 3)
        XCTAssertEqual(analyzer.countSyllables("elephant"), 3)
    }

    func testCountSyllablesMultiSyllable() {
        XCTAssertEqual(analyzer.countSyllables("university"), 5)
        XCTAssertEqual(analyzer.countSyllables("communication"), 5)
    }

    func testCountSyllablesSilentE() {
        // "make" has silent e — 1 syllable
        XCTAssertEqual(analyzer.countSyllables("make"), 1)
        XCTAssertEqual(analyzer.countSyllables("hope"), 1)
        XCTAssertEqual(analyzer.countSyllables("time"), 1)
    }

    func testCountSyllablesEmptyString() {
        XCTAssertEqual(analyzer.countSyllables(""), 0)
    }

    func testCountSyllablesShortWords() {
        // Two-letter words always return 1
        XCTAssertEqual(analyzer.countSyllables("an"), 1)
        XCTAssertEqual(analyzer.countSyllables("I"), 1)
        XCTAssertEqual(analyzer.countSyllables("go"), 1)
    }

    func testCountSyllablesMinimumOne() {
        // Even consonant-only strings get minimum 1
        XCTAssertEqual(analyzer.countSyllables("gym"), 1)
    }

    // MARK: - Sentence Counting

    func testCountSentencesPeriods() {
        XCTAssertEqual(analyzer.countSentences("Hello. World."), 2)
    }

    func testCountSentencesExclamation() {
        XCTAssertEqual(analyzer.countSentences("Wow! Great! Nice!"), 3)
    }

    func testCountSentencesQuestion() {
        XCTAssertEqual(analyzer.countSentences("What? Why? How?"), 3)
    }

    func testCountSentencesMixed() {
        XCTAssertEqual(analyzer.countSentences("Hello. How are you? Great!"), 3)
    }

    func testCountSentencesNoDelimiter() {
        // No sentence ender → min 1
        XCTAssertEqual(analyzer.countSentences("Hello world"), 1)
    }

    func testCountSentencesEmptyString() {
        XCTAssertEqual(analyzer.countSentences(""), 1)
    }

    // MARK: - HTML Stripping

    func testStripHTMLRemovesTags() {
        let result = analyzer.stripHTML("<p>Hello <b>world</b></p>")
        XCTAssertEqual(result, "Hello world")
    }

    func testStripHTMLRemovesScriptTags() {
        let result = analyzer.stripHTML("Before<script>alert('xss')</script>After")
        XCTAssertEqual(result, "Before After")
    }

    func testStripHTMLRemovesStyleTags() {
        let result = analyzer.stripHTML("Text<style>body{color:red}</style>More")
        XCTAssertEqual(result, "Text More")
    }

    func testStripHTMLDecodesEntities() {
        let result = analyzer.stripHTML("A &amp; B &lt; C &gt; D &quot;E&quot; &#39;F&#39;")
        XCTAssertEqual(result, "A & B < C > D \"E\" 'F'")
    }

    func testStripHTMLDecodesNbsp() {
        let result = analyzer.stripHTML("Hello&nbsp;world")
        XCTAssertEqual(result, "Hello world")
    }

    func testStripHTMLCollapsesWhitespace() {
        let result = analyzer.stripHTML("Hello    \n\n   world")
        XCTAssertEqual(result, "Hello world")
    }

    func testStripHTMLPlainTextUnchanged() {
        let result = analyzer.stripHTML("Just plain text here")
        XCTAssertEqual(result, "Just plain text here")
    }

    // MARK: - Tokenization

    func testTokenizeBasic() {
        let tokens = analyzer.tokenize("Hello World Test")
        XCTAssertEqual(tokens, ["hello", "world", "test"])
    }

    func testTokenizeStripsEdgePunctuation() {
        let tokens = analyzer.tokenize("Hello, world! How's it?")
        XCTAssertTrue(tokens.contains("hello"))
        XCTAssertTrue(tokens.contains("world"))
        XCTAssertTrue(tokens.contains("how's"))
    }

    func testTokenizeEmptyString() {
        let tokens = analyzer.tokenize("")
        XCTAssertEqual(tokens, [])
    }

    func testTokenizeFiltersEmptyTokens() {
        let tokens = analyzer.tokenize("  ,,, ... ")
        XCTAssertEqual(tokens, [])
    }

    // MARK: - Flesch Formulas

    func testFleschReadingEaseFormula() {
        // FRE = 206.835 - 1.015 * ASL - 84.6 * ASW
        let fre = analyzer.fleschReadingEase(avgWordsPerSentence: 10.0,
                                              avgSyllablesPerWord: 1.5)
        let expected = 206.835 - 1.015 * 10.0 - 84.6 * 1.5
        XCTAssertEqual(fre, expected, accuracy: 0.001)
    }

    func testFleschKincaidGradeLevelFormula() {
        // FKGL = 0.39 * ASL + 11.8 * ASW - 15.59
        let fkgl = analyzer.fleschKincaidGradeLevel(avgWordsPerSentence: 10.0,
                                                      avgSyllablesPerWord: 1.5)
        let expected = 0.39 * 10.0 + 11.8 * 1.5 - 15.59
        XCTAssertEqual(fkgl, expected, accuracy: 0.001)
    }

    func testVeryEasyTextHasHighFRE() {
        // Short sentences, simple words
        let result = analyzer.analyze("I run. I sit. He ran. She sat. We go.")
        XCTAssertNotNil(result)
        XCTAssertGreaterThan(result!.fleschReadingEase, 80)
    }

    func testComplexTextHasLowFRE() {
        // Long sentences, multi-syllable words
        let text = "The implementation of sophisticated algorithmic methodologies " +
            "necessitates comprehensive understanding of computational complexity " +
            "and mathematical abstraction throughout distributed architecture."
        let result = analyzer.analyze(text)
        XCTAssertNotNil(result)
        XCTAssertLessThan(result!.fleschReadingEase, 30)
    }

    // MARK: - Difficulty Classification

    func testClassifyVeryEasy() {
        XCTAssertEqual(analyzer.classifyDifficulty(95), .veryEasy)
        XCTAssertEqual(analyzer.classifyDifficulty(90), .veryEasy)
    }

    func testClassifyEasy() {
        XCTAssertEqual(analyzer.classifyDifficulty(85), .easy)
        XCTAssertEqual(analyzer.classifyDifficulty(80), .easy)
    }

    func testClassifyFairlyEasy() {
        XCTAssertEqual(analyzer.classifyDifficulty(75), .fairlyEasy)
        XCTAssertEqual(analyzer.classifyDifficulty(70), .fairlyEasy)
    }

    func testClassifyStandard() {
        XCTAssertEqual(analyzer.classifyDifficulty(65), .standard)
        XCTAssertEqual(analyzer.classifyDifficulty(60), .standard)
    }

    func testClassifyFairlyDifficult() {
        XCTAssertEqual(analyzer.classifyDifficulty(55), .fairlyDifficult)
        XCTAssertEqual(analyzer.classifyDifficulty(50), .fairlyDifficult)
    }

    func testClassifyDifficult() {
        XCTAssertEqual(analyzer.classifyDifficulty(40), .difficult)
        XCTAssertEqual(analyzer.classifyDifficulty(30), .difficult)
    }

    func testClassifyVeryDifficult() {
        XCTAssertEqual(analyzer.classifyDifficulty(20), .veryDifficult)
        XCTAssertEqual(analyzer.classifyDifficulty(-5), .veryDifficult)
    }

    // MARK: - Reading Time

    func testEstimatedReadingTime() {
        // 238 words → 60 seconds
        let words = Array(repeating: "word", count: 238).joined(separator: " ") + "."
        let result = analyzer.analyze(words)
        XCTAssertNotNil(result)
        XCTAssertEqual(result!.estimatedReadingTimeSeconds, 60.0, accuracy: 1.0)
    }

    func testFormatReadingTimeLessThanMinute() {
        XCTAssertEqual(ArticleReadabilityAnalyzer.formatReadingTime(30), "< 1 min")
    }

    func testFormatReadingTimeOneMinute() {
        XCTAssertEqual(ArticleReadabilityAnalyzer.formatReadingTime(60), "1 min")
        XCTAssertEqual(ArticleReadabilityAnalyzer.formatReadingTime(90), "1 min")
    }

    func testFormatReadingTimeMultipleMinutes() {
        XCTAssertEqual(ArticleReadabilityAnalyzer.formatReadingTime(120), "2 min")
        XCTAssertEqual(ArticleReadabilityAnalyzer.formatReadingTime(300), "5 min")
    }

    // MARK: - Summary

    func testSummaryContainsDifficulty() {
        let result = analyzer.analyze("The cat sat on the mat.")
        XCTAssertNotNil(result)
        let sum = analyzer.summary(result!)
        XCTAssertTrue(sum.contains(result!.difficulty.rawValue))
    }

    func testSummaryContainsWordCount() {
        let result = analyzer.analyze("Hello world test words here.")
        XCTAssertNotNil(result)
        let sum = analyzer.summary(result!)
        XCTAssertTrue(sum.contains("\(result!.wordCount) words"))
    }

    func testSummaryContainsReadingTime() {
        let result = analyzer.analyze("Simple text.")
        XCTAssertNotNil(result)
        let sum = analyzer.summary(result!)
        XCTAssertTrue(sum.contains("min") || sum.contains("< 1"))
    }

    // MARK: - Batch Analysis

    func testAnalyzeBatch() {
        let texts = ["Hello world.", "The cat sat.", ""]
        let results = analyzer.analyzeBatch(texts)
        XCTAssertEqual(results.count, 2) // empty string returns nil
        XCTAssertNotNil(results[0])
        XCTAssertNotNil(results[1])
        XCTAssertNil(results[2])
    }

    func testAnalyzeBatchEmpty() {
        let results = analyzer.analyzeBatch([])
        XCTAssertTrue(results.isEmpty)
    }

    // MARK: - Story Analysis

    func testAnalyzeStory() {
        guard let story = Story(
            title: "Test Story",
            photo: nil,
            description: "This is the body of the story. It has multiple sentences. Very interesting.",
            link: "https://example.com/story"
        ) else {
            XCTFail("Failed to create Story")
            return
        }
        let result = analyzer.analyzeStory(story)
        XCTAssertNotNil(result)
        XCTAssertGreaterThan(result!.wordCount, 5)
        XCTAssertEqual(result!.sentenceCount, 3)
    }

    func testAnalyzeStoryEmptyBody() {
        // Story init fails with empty description, so test analyzeStory on
        // a story that would have minimal content
        let result = analyzer.analyze("")
        XCTAssertNil(result)
    }

    // MARK: - Compare

    func testCompareSimilarDifficulty() {
        let a = analyzer.analyze("The cat sat.")!
        let b = analyzer.analyze("The dog ran.")!
        let comparison = analyzer.compare(a, b)
        XCTAssertTrue(comparison.contains("Similar"))
    }

    func testCompareDifferentDifficulty() {
        let simple = analyzer.analyze("I run. I sit. Go. Stop. Run.")!
        let complex = analyzer.analyze(
            "The implementation of sophisticated algorithmic methodologies " +
            "necessitates comprehensive understanding of computational complexity."
        )!
        let comparison = analyzer.compare(simple, complex)
        XCTAssertTrue(comparison.contains("easier") || comparison.contains("Similar"))
    }

    // MARK: - Aggregate Stats

    func testAggregateStats() {
        let r1 = analyzer.analyze("Simple text here.")!
        let r2 = analyzer.analyze("Another simple sentence.")!
        let agg = analyzer.aggregateStats([r1, r2])
        XCTAssertNotNil(agg)
        XCTAssertEqual(agg!.articleCount, 2)
        XCTAssertEqual(agg!.totalWordCount, r1.wordCount + r2.wordCount)
        XCTAssertEqual(agg!.totalSentenceCount, r1.sentenceCount + r2.sentenceCount)
    }

    func testAggregateStatsEmpty() {
        XCTAssertNil(analyzer.aggregateStats([]))
    }

    func testAggregateTotalReadingTime() {
        let r1 = analyzer.analyze("Word one two three four.")!
        let r2 = analyzer.analyze("Six seven eight nine ten.")!
        let agg = analyzer.aggregateStats([r1, r2])!
        XCTAssertEqual(agg.totalReadingTimeSeconds,
                       r1.estimatedReadingTimeSeconds + r2.estimatedReadingTimeSeconds,
                       accuracy: 0.01)
    }

    // MARK: - ReadabilityDifficulty Enum

    func testDifficultyEmoji() {
        XCTAssertEqual(ReadabilityDifficulty.veryEasy.emoji, "🟢")
        XCTAssertEqual(ReadabilityDifficulty.standard.emoji, "🟡")
        XCTAssertEqual(ReadabilityDifficulty.difficult.emoji, "🔴")
    }

    func testDifficultyGradeRange() {
        XCTAssertEqual(ReadabilityDifficulty.veryEasy.gradeRange, "5th grade")
        XCTAssertEqual(ReadabilityDifficulty.standard.gradeRange, "8th-9th grade")
        XCTAssertEqual(ReadabilityDifficulty.veryDifficult.gradeRange, "College graduate")
    }

    func testDifficultyRawValue() {
        XCTAssertEqual(ReadabilityDifficulty.veryEasy.rawValue, "Very Easy")
        XCTAssertEqual(ReadabilityDifficulty.fairlyDifficult.rawValue, "Fairly Difficult")
    }

    func testAllCases() {
        XCTAssertEqual(ReadabilityDifficulty.allCases.count, 7)
    }

    // MARK: - Edge Cases

    func testAnalyzeWithHTMLContent() {
        let html = "<p>This is <b>bold</b> text.</p><p>Another paragraph here!</p>"
        let result = analyzer.analyze(html)
        XCTAssertNotNil(result)
        XCTAssertEqual(result!.wordCount, 7)
        XCTAssertEqual(result!.sentenceCount, 2)
    }

    func testAnalyzeWithNumbers() {
        let result = analyzer.analyze("There are 100 items in 5 boxes.")
        XCTAssertNotNil(result)
        // Numbers are filtered out by tokenizer (non-letter chars)
        XCTAssertGreaterThan(result!.wordCount, 0)
    }

    func testAnalyzeVeryLongSentence() {
        let words = Array(repeating: "word", count: 100).joined(separator: " ") + "."
        let result = analyzer.analyze(words)
        XCTAssertNotNil(result)
        XCTAssertEqual(result!.sentenceCount, 1)
        XCTAssertEqual(result!.averageWordsPerSentence, 100.0, accuracy: 0.01)
    }

    func testAnalyzeMultipleParagraphs() {
        let text = """
        First paragraph with simple words. Short and sweet.
        
        Second paragraph is also quite simple. It has easy words too.
        """
        let result = analyzer.analyze(text)
        XCTAssertNotNil(result)
        XCTAssertEqual(result!.sentenceCount, 4)
    }

    func testSyllableCountConsistency() {
        // Same word always returns same count
        let count1 = analyzer.countSyllables("algorithm")
        let count2 = analyzer.countSyllables("algorithm")
        XCTAssertEqual(count1, count2)
    }

    func testAveragesArePositive() {
        let result = analyzer.analyze("The quick brown fox jumps over the lazy dog.")
        XCTAssertNotNil(result)
        XCTAssertGreaterThan(result!.averageWordsPerSentence, 0)
        XCTAssertGreaterThan(result!.averageSyllablesPerWord, 0)
    }

    func testReadingTimeIsPositive() {
        let result = analyzer.analyze("Any text at all.")
        XCTAssertNotNil(result)
        XCTAssertGreaterThan(result!.estimatedReadingTimeSeconds, 0)
    }

    func testGradeLevelReasonableRange() {
        // Simple text should have grade level < 12
        let result = analyzer.analyze("The cat sat on a mat. It was fun.")
        XCTAssertNotNil(result)
        XCTAssertLessThan(result!.fleschKincaidGradeLevel, 12)
    }
}
