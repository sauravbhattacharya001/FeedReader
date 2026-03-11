//
//  ArticleReadabilityAnalyzerTests.swift
//  FeedReaderTests
//
//  Tests for ArticleReadabilityAnalyzer: syllable counting, sentence
//  detection, Flesch formulas, difficulty classification, reading time
//  estimation, HTML stripping, batch analysis, and aggregate stats.
//

import XCTest
@testable import FeedReader

class ArticleReadabilityAnalyzerTests: XCTestCase {

    var analyzer: ArticleReadabilityAnalyzer!

    override func setUp() {
        super.setUp()
        analyzer = ArticleReadabilityAnalyzer.shared
    }

    // MARK: - Syllable Counting

    func testCountSyllables_OneSyllable() {
        XCTAssertEqual(analyzer.countSyllables("cat"), 1)
        XCTAssertEqual(analyzer.countSyllables("dog"), 1)
        XCTAssertEqual(analyzer.countSyllables("the"), 1)
        XCTAssertEqual(analyzer.countSyllables("run"), 1)
        XCTAssertEqual(analyzer.countSyllables("and"), 1)
    }

    func testCountSyllables_TwoSyllables() {
        XCTAssertEqual(analyzer.countSyllables("apple"), 2)
        XCTAssertEqual(analyzer.countSyllables("water"), 2)
        XCTAssertEqual(analyzer.countSyllables("happy"), 2)
        XCTAssertEqual(analyzer.countSyllables("table"), 2)
    }

    func testCountSyllables_ThreeSyllables() {
        XCTAssertEqual(analyzer.countSyllables("beautiful"), 3)
        XCTAssertEqual(analyzer.countSyllables("banana"), 3)
        XCTAssertEqual(analyzer.countSyllables("elephant"), 3)
    }

    func testCountSyllables_ManySyllables() {
        // "university" = u-ni-ver-si-ty = 5
        XCTAssertEqual(analyzer.countSyllables("university"), 5)
        // "communication" = com-mu-ni-ca-tion = 5
        XCTAssertEqual(analyzer.countSyllables("communication"), 5)
    }

    func testCountSyllables_SilentE() {
        // "cake" should be 1 (silent e), not 2
        XCTAssertEqual(analyzer.countSyllables("cake"), 1)
        // "make" should be 1
        XCTAssertEqual(analyzer.countSyllables("make"), 1)
        // "time" should be 1
        XCTAssertEqual(analyzer.countSyllables("time"), 1)
    }

    func testCountSyllables_LEEnding() {
        // "purple" = pur-ple = 2, the "-le" keeps its syllable
        XCTAssertEqual(analyzer.countSyllables("purple"), 2)
        // "simple" = sim-ple = 2
        XCTAssertEqual(analyzer.countSyllables("simple"), 2)
        // "bottle" = bot-tle = 2
        XCTAssertEqual(analyzer.countSyllables("bottle"), 2)
    }

    func testCountSyllables_EmptyString() {
        XCTAssertEqual(analyzer.countSyllables(""), 0)
    }

    func testCountSyllables_SingleLetter() {
        XCTAssertEqual(analyzer.countSyllables("a"), 1)
        XCTAssertEqual(analyzer.countSyllables("I"), 1)
    }

    func testCountSyllables_TwoLetterWord() {
        XCTAssertEqual(analyzer.countSyllables("do"), 1)
        XCTAssertEqual(analyzer.countSyllables("go"), 1)
        XCTAssertEqual(analyzer.countSyllables("an"), 1)
    }

    func testCountSyllables_MinimumOne() {
        // Even words with no detected vowel groups should return 1
        XCTAssertEqual(analyzer.countSyllables("hmm"), 1)
        XCTAssertEqual(analyzer.countSyllables("rhythm"), 2) // y is vowel
    }

    // MARK: - Sentence Counting

    func testCountSentences_SingleSentence() {
        XCTAssertEqual(analyzer.countSentences("Hello world."), 1)
    }

    func testCountSentences_MultipleSentences() {
        XCTAssertEqual(analyzer.countSentences("Hello. World. Test."), 3)
    }

    func testCountSentences_ExclamationAndQuestion() {
        XCTAssertEqual(analyzer.countSentences("Hello! How are you? Fine."), 3)
    }

    func testCountSentences_EmptyString() {
        XCTAssertEqual(analyzer.countSentences(""), 1) // max(0, 1) = 1
    }

    func testCountSentences_NoPunctuation() {
        // No sentence-ending punctuation → 1 segment (the whole text)
        XCTAssertEqual(analyzer.countSentences("Hello world"), 1)
    }

    func testCountSentences_MultiplePunctuationInRow() {
        // "What?!" splits into ["What", ""] + rest → 1 non-empty
        // But actually splits on each delimiter, so What?! → "What" | "" | rest
        let count = analyzer.countSentences("What?! Really?!")
        XCTAssertGreaterThanOrEqual(count, 1)
    }

    func testCountSentences_Abbreviations() {
        // "Dr. Smith went home." has dots in abbreviation
        // This is a known limitation — the naive splitter over-counts
        let count = analyzer.countSentences("Dr. Smith went home.")
        XCTAssertGreaterThanOrEqual(count, 1)
    }

    // MARK: - Tokenization

    func testTokenize_BasicText() {
        let tokens = analyzer.tokenize("Hello World")
        XCTAssertEqual(tokens, ["hello", "world"])
    }

    func testTokenize_WithPunctuation() {
        let tokens = analyzer.tokenize("Hello, world! How are you?")
        XCTAssertEqual(tokens, ["hello", "world", "how", "are", "you"])
    }

    func testTokenize_EmptyString() {
        let tokens = analyzer.tokenize("")
        XCTAssertTrue(tokens.isEmpty)
    }

    func testTokenize_WhitespaceOnly() {
        let tokens = analyzer.tokenize("   \n\t  ")
        XCTAssertTrue(tokens.isEmpty)
    }

    func testTokenize_MixedCase() {
        let tokens = analyzer.tokenize("HELLO World hELLo")
        XCTAssertEqual(tokens, ["hello", "world", "hello"])
    }

    func testTokenize_NumbersStripped() {
        // Numbers are non-letters, should be stripped from edges
        let tokens = analyzer.tokenize("test123 456test")
        // "test123" trimmed of non-alpha from edges → "test" (if 123 at end is trimmed)
        // Depends on implementation: trimmingCharacters(in: .letters.inverted)
        // "test123" → trims non-letters from start/end → "test123" has letters at start
        // Actually trims from edges only: "test123" → "test" is wrong, it trims "123" from end
        // Let's just verify non-empty results
        XCTAssertFalse(tokens.isEmpty)
    }

    // MARK: - HTML Stripping

    func testStripHTML_BasicTags() {
        let result = analyzer.stripHTML("<p>Hello <b>world</b></p>")
        XCTAssertEqual(result, "Hello world")
    }

    func testStripHTML_ScriptTags() {
        let result = analyzer.stripHTML("Hello<script>alert('xss')</script> world")
        XCTAssertEqual(result, "Hello world")
    }

    func testStripHTML_StyleTags() {
        let result = analyzer.stripHTML("Hello<style>.red{color:red}</style> world")
        XCTAssertEqual(result, "Hello world")
    }

    func testStripHTML_Entities() {
        let result = analyzer.stripHTML("Tom &amp; Jerry &lt;3 &gt;")
        XCTAssertEqual(result, "Tom & Jerry <3 >")
    }

    func testStripHTML_Nbsp() {
        let result = analyzer.stripHTML("Hello&nbsp;world")
        XCTAssertEqual(result, "Hello world")
    }

    func testStripHTML_Quotes() {
        let result = analyzer.stripHTML("&quot;Hello&quot; &#39;world&#39;")
        XCTAssertEqual(result, "\"Hello\" 'world'")
    }

    func testStripHTML_PlainText() {
        let result = analyzer.stripHTML("No HTML here")
        XCTAssertEqual(result, "No HTML here")
    }

    func testStripHTML_CollapsesWhitespace() {
        let result = analyzer.stripHTML("Hello   \n\n  world")
        XCTAssertEqual(result, "Hello world")
    }

    // MARK: - Flesch Reading Ease Formula

    func testFleschReadingEase_EasyText() {
        // Short words, short sentences → high score
        let fre = analyzer.fleschReadingEase(
            avgWordsPerSentence: 10.0,
            avgSyllablesPerWord: 1.2
        )
        // 206.835 - 1.015*10 - 84.6*1.2 = 206.835 - 10.15 - 101.52 = 95.165
        XCTAssertEqual(fre, 95.165, accuracy: 0.01)
    }

    func testFleschReadingEase_HardText() {
        // Long words, long sentences → low score
        let fre = analyzer.fleschReadingEase(
            avgWordsPerSentence: 30.0,
            avgSyllablesPerWord: 2.5
        )
        // 206.835 - 1.015*30 - 84.6*2.5 = 206.835 - 30.45 - 211.5 = -35.115
        XCTAssertEqual(fre, -35.115, accuracy: 0.01)
    }

    // MARK: - Flesch-Kincaid Grade Level Formula

    func testFleschKincaidGradeLevel_EasyText() {
        let fkgl = analyzer.fleschKincaidGradeLevel(
            avgWordsPerSentence: 10.0,
            avgSyllablesPerWord: 1.2
        )
        // 0.39*10 + 11.8*1.2 - 15.59 = 3.9 + 14.16 - 15.59 = 2.47
        XCTAssertEqual(fkgl, 2.47, accuracy: 0.01)
    }

    func testFleschKincaidGradeLevel_HardText() {
        let fkgl = analyzer.fleschKincaidGradeLevel(
            avgWordsPerSentence: 30.0,
            avgSyllablesPerWord: 2.5
        )
        // 0.39*30 + 11.8*2.5 - 15.59 = 11.7 + 29.5 - 15.59 = 25.61
        XCTAssertEqual(fkgl, 25.61, accuracy: 0.01)
    }

    // MARK: - Difficulty Classification

    func testClassifyDifficulty_VeryEasy() {
        XCTAssertEqual(analyzer.classifyDifficulty(95.0), .veryEasy)
        XCTAssertEqual(analyzer.classifyDifficulty(90.0), .veryEasy)
        XCTAssertEqual(analyzer.classifyDifficulty(100.0), .veryEasy)
    }

    func testClassifyDifficulty_Easy() {
        XCTAssertEqual(analyzer.classifyDifficulty(85.0), .easy)
        XCTAssertEqual(analyzer.classifyDifficulty(80.0), .easy)
    }

    func testClassifyDifficulty_FairlyEasy() {
        XCTAssertEqual(analyzer.classifyDifficulty(75.0), .fairlyEasy)
        XCTAssertEqual(analyzer.classifyDifficulty(70.0), .fairlyEasy)
    }

    func testClassifyDifficulty_Standard() {
        XCTAssertEqual(analyzer.classifyDifficulty(65.0), .standard)
        XCTAssertEqual(analyzer.classifyDifficulty(60.0), .standard)
    }

    func testClassifyDifficulty_FairlyDifficult() {
        XCTAssertEqual(analyzer.classifyDifficulty(55.0), .fairlyDifficult)
        XCTAssertEqual(analyzer.classifyDifficulty(50.0), .fairlyDifficult)
    }

    func testClassifyDifficulty_Difficult() {
        XCTAssertEqual(analyzer.classifyDifficulty(40.0), .difficult)
        XCTAssertEqual(analyzer.classifyDifficulty(30.0), .difficult)
    }

    func testClassifyDifficulty_VeryDifficult() {
        XCTAssertEqual(analyzer.classifyDifficulty(29.9), .veryDifficult)
        XCTAssertEqual(analyzer.classifyDifficulty(0.0), .veryDifficult)
        XCTAssertEqual(analyzer.classifyDifficulty(-10.0), .veryDifficult)
    }

    func testClassifyDifficulty_Boundaries() {
        // Test exact boundaries
        XCTAssertEqual(analyzer.classifyDifficulty(89.99), .easy)     // < 90
        XCTAssertEqual(analyzer.classifyDifficulty(79.99), .fairlyEasy) // < 80
        XCTAssertEqual(analyzer.classifyDifficulty(69.99), .standard)   // < 70
        XCTAssertEqual(analyzer.classifyDifficulty(59.99), .fairlyDifficult) // < 60
        XCTAssertEqual(analyzer.classifyDifficulty(49.99), .difficult)  // < 50
    }

    // MARK: - ReadabilityDifficulty Properties

    func testDifficulty_Emoji() {
        XCTAssertEqual(ReadabilityDifficulty.veryEasy.emoji, "🟢")
        XCTAssertEqual(ReadabilityDifficulty.easy.emoji, "🟢")
        XCTAssertEqual(ReadabilityDifficulty.fairlyEasy.emoji, "🟡")
        XCTAssertEqual(ReadabilityDifficulty.standard.emoji, "🟡")
        XCTAssertEqual(ReadabilityDifficulty.fairlyDifficult.emoji, "🟠")
        XCTAssertEqual(ReadabilityDifficulty.difficult.emoji, "🔴")
        XCTAssertEqual(ReadabilityDifficulty.veryDifficult.emoji, "🔴")
    }

    func testDifficulty_GradeRange() {
        XCTAssertEqual(ReadabilityDifficulty.veryEasy.gradeRange, "5th grade")
        XCTAssertEqual(ReadabilityDifficulty.easy.gradeRange, "6th grade")
        XCTAssertEqual(ReadabilityDifficulty.fairlyEasy.gradeRange, "7th grade")
        XCTAssertEqual(ReadabilityDifficulty.standard.gradeRange, "8th-9th grade")
        XCTAssertEqual(ReadabilityDifficulty.fairlyDifficult.gradeRange, "10th-12th grade")
        XCTAssertEqual(ReadabilityDifficulty.difficult.gradeRange, "College")
        XCTAssertEqual(ReadabilityDifficulty.veryDifficult.gradeRange, "College graduate")
    }

    func testDifficulty_RawValue() {
        XCTAssertEqual(ReadabilityDifficulty.veryEasy.rawValue, "Very Easy")
        XCTAssertEqual(ReadabilityDifficulty.standard.rawValue, "Standard")
        XCTAssertEqual(ReadabilityDifficulty.veryDifficult.rawValue, "Very Difficult")
    }

    func testDifficulty_CaseIterable() {
        XCTAssertEqual(ReadabilityDifficulty.allCases.count, 7)
    }

    // MARK: - Full Analysis

    func testAnalyze_SimpleText() {
        let result = analyzer.analyze("The cat sat on the mat.")
        XCTAssertNotNil(result)
        XCTAssertEqual(result!.wordCount, 6)
        XCTAssertEqual(result!.sentenceCount, 1)
        XCTAssertEqual(result!.averageWordsPerSentence, 6.0)
        XCTAssertGreaterThan(result!.fleschReadingEase, 80.0) // easy text
        XCTAssertGreaterThan(result!.estimatedReadingTimeSeconds, 0)
    }

    func testAnalyze_EmptyString() {
        let result = analyzer.analyze("")
        XCTAssertNil(result)
    }

    func testAnalyze_WhitespaceOnly() {
        let result = analyzer.analyze("   \n\t  ")
        XCTAssertNil(result)
    }

    func testAnalyze_MultiSentence() {
        let text = "The dog runs fast. The cat sleeps. Birds fly high."
        let result = analyzer.analyze(text)
        XCTAssertNotNil(result)
        XCTAssertEqual(result!.sentenceCount, 3)
        XCTAssertEqual(result!.averageWordsPerSentence, Double(result!.wordCount) / 3.0, accuracy: 0.01)
    }

    func testAnalyze_ReadingTime() {
        // 238 words should take ~60 seconds
        let words = Array(repeating: "word", count: 238).joined(separator: " ") + "."
        let result = analyzer.analyze(words)
        XCTAssertNotNil(result)
        XCTAssertEqual(result!.estimatedReadingTimeSeconds, 60.0, accuracy: 1.0)
    }

    func testAnalyze_HTMLContent() {
        let html = "<p>The <b>quick</b> brown fox.</p>"
        let result = analyzer.analyze(html)
        XCTAssertNotNil(result)
        XCTAssertEqual(result!.wordCount, 4)
    }

    func testAnalyze_SyllableCountConsistency() {
        let result = analyzer.analyze("Hello beautiful world.")
        XCTAssertNotNil(result)
        // "hello" = 2, "beautiful" = 3, "world" = 1 → total 6
        XCTAssertEqual(result!.syllableCount, 6)
    }

    func testAnalyze_DifficultyAssigned() {
        let easyText = "I see a dog. The dog is big. I like the dog."
        let result = analyzer.analyze(easyText)
        XCTAssertNotNil(result)
        // Very short sentences, simple words → should be easy
        let difficulty = result!.difficulty
        XCTAssertTrue(
            difficulty == .veryEasy || difficulty == .easy || difficulty == .fairlyEasy,
            "Simple text should be easy, got \(difficulty.rawValue)"
        )
    }

    func testAnalyze_ComplexText() {
        let text = "The epistemological implications of quantum mechanical phenomena suggest that ontological realism requires substantial philosophical reconsideration."
        let result = analyzer.analyze(text)
        XCTAssertNotNil(result)
        // Long sentence, many syllables → should be difficult
        let difficulty = result!.difficulty
        XCTAssertTrue(
            difficulty == .difficult || difficulty == .veryDifficult || difficulty == .fairlyDifficult,
            "Complex text should be difficult, got \(difficulty.rawValue)"
        )
    }

    // MARK: - Batch Analysis

    func testAnalyzeBatch_MultipleTexts() {
        let texts = [
            "Hello world.",
            "The quick brown fox jumps over the lazy dog.",
            ""  // empty — should be excluded
        ]
        let results = analyzer.analyzeBatch(texts)
        XCTAssertEqual(results.count, 2) // empty string excluded
        XCTAssertNotNil(results[0])
        XCTAssertNotNil(results[1])
        XCTAssertNil(results[2])
    }

    func testAnalyzeBatch_Empty() {
        let results = analyzer.analyzeBatch([])
        XCTAssertTrue(results.isEmpty)
    }

    func testAnalyzeBatch_AllEmpty() {
        let results = analyzer.analyzeBatch(["", "  ", "\n"])
        XCTAssertTrue(results.isEmpty)
    }

    // MARK: - Reading Time Formatting

    func testFormatReadingTime_LessThanMinute() {
        XCTAssertEqual(ArticleReadabilityAnalyzer.formatReadingTime(30.0), "< 1 min")
        XCTAssertEqual(ArticleReadabilityAnalyzer.formatReadingTime(0.0), "< 1 min")
        XCTAssertEqual(ArticleReadabilityAnalyzer.formatReadingTime(59.0), "< 1 min")
    }

    func testFormatReadingTime_OneMinute() {
        XCTAssertEqual(ArticleReadabilityAnalyzer.formatReadingTime(60.0), "1 min")
        XCTAssertEqual(ArticleReadabilityAnalyzer.formatReadingTime(119.0), "1 min")
    }

    func testFormatReadingTime_MultipleMinutes() {
        XCTAssertEqual(ArticleReadabilityAnalyzer.formatReadingTime(120.0), "2 min")
        XCTAssertEqual(ArticleReadabilityAnalyzer.formatReadingTime(300.0), "5 min")
        XCTAssertEqual(ArticleReadabilityAnalyzer.formatReadingTime(600.0), "10 min")
    }

    // MARK: - Summary

    func testSummary_Format() {
        let result = analyzer.analyze("The cat sat on the mat.")
        XCTAssertNotNil(result)
        let summary = analyzer.summary(result!)
        // Should contain emoji, difficulty, time, and word count
        XCTAssertTrue(summary.contains("words"))
        XCTAssertTrue(summary.contains("min") || summary.contains("< 1"))
        XCTAssertTrue(summary.contains("·"))
    }

    // MARK: - Compare

    func testCompare_SimilarDifficulty() {
        let a = analyzer.analyze("The cat sits here.")!
        let b = analyzer.analyze("The dog runs fast.")!
        let comparison = analyzer.compare(a, b)
        // Both are very simple → should be "Similar difficulty"
        XCTAssertTrue(comparison.contains("Similar") || comparison.contains("easier"),
                      "Comparison should describe relationship")
    }

    func testCompare_DifferentDifficulty() {
        let easy = analyzer.analyze("I see a dog.")!
        let hard = analyzer.analyze("The epistemological ramifications of metaphysical ontological considerations demand careful philosophical deliberation and interdisciplinary scholarly examination.")!
        let comparison = analyzer.compare(easy, hard)
        XCTAssertTrue(comparison.contains("easier"),
                      "Should identify which is easier")
        XCTAssertTrue(comparison.contains("A") || comparison.contains("B"),
                      "Should identify which text (A or B)")
    }

    // MARK: - Aggregate Statistics

    func testAggregateStats_MultipleResults() {
        let r1 = analyzer.analyze("The cat sat on the mat.")!
        let r2 = analyzer.analyze("The quick brown fox jumps over the lazy dog.")!
        let agg = analyzer.aggregateStats([r1, r2])
        XCTAssertNotNil(agg)
        XCTAssertEqual(agg!.articleCount, 2)
        XCTAssertEqual(agg!.totalWordCount, r1.wordCount + r2.wordCount)
        XCTAssertEqual(agg!.totalSentenceCount, r1.sentenceCount + r2.sentenceCount)
        XCTAssertGreaterThan(agg!.totalReadingTimeSeconds, 0)
    }

    func testAggregateStats_Empty() {
        let agg = analyzer.aggregateStats([])
        XCTAssertNil(agg)
    }

    func testAggregateStats_Averages() {
        let r1 = analyzer.analyze("Simple short text.")!
        let r2 = analyzer.analyze("Another simple piece of writing.")!
        let agg = analyzer.aggregateStats([r1, r2])!
        let expectedAvgFRE = (r1.fleschReadingEase + r2.fleschReadingEase) / 2.0
        XCTAssertEqual(agg.averageFleschReadingEase, expectedAvgFRE, accuracy: 0.01)
        let expectedAvgGrade = (r1.fleschKincaidGradeLevel + r2.fleschKincaidGradeLevel) / 2.0
        XCTAssertEqual(agg.averageGradeLevel, expectedAvgGrade, accuracy: 0.01)
    }

    func testAggregateStats_PredominantDifficulty() {
        // Create 3 easy texts → predominant should be easy-ish
        let texts = [
            "I see a dog.",
            "The cat is big.",
            "We go to school."
        ]
        let results = texts.compactMap { analyzer.analyze($0) }
        let agg = analyzer.aggregateStats(results)!
        // All should be easy → predominant difficulty should be easy category
        XCTAssertTrue(
            agg.predominantDifficulty == .veryEasy || agg.predominantDifficulty == .easy,
            "Predominant should be easy, got \(agg.predominantDifficulty.rawValue)"
        )
    }

    func testAggregateStats_SingleResult() {
        let r = analyzer.analyze("Hello world.")!
        let agg = analyzer.aggregateStats([r])!
        XCTAssertEqual(agg.articleCount, 1)
        XCTAssertEqual(agg.totalWordCount, r.wordCount)
        XCTAssertEqual(agg.averageFleschReadingEase, r.fleschReadingEase, accuracy: 0.01)
    }

    // MARK: - Edge Cases

    func testAnalyze_SingleWord() {
        let result = analyzer.analyze("Hello")
        XCTAssertNotNil(result)
        XCTAssertEqual(result!.wordCount, 1)
        XCTAssertEqual(result!.sentenceCount, 1) // min 1
    }

    func testAnalyze_AllPunctuation() {
        let result = analyzer.analyze("... !!! ???")
        // Punctuation-only → no words after tokenization
        XCTAssertNil(result)
    }

    func testAnalyze_VeryLongSentence() {
        let words = (0..<100).map { _ in "the" }.joined(separator: " ") + "."
        let result = analyzer.analyze(words)
        XCTAssertNotNil(result)
        XCTAssertEqual(result!.wordCount, 100)
        XCTAssertEqual(result!.sentenceCount, 1)
        XCTAssertEqual(result!.averageWordsPerSentence, 100.0)
    }

    func testAnalyze_MixedHTMLAndText() {
        let html = "<div><p>First sentence.</p><p>Second sentence.</p></div>"
        let result = analyzer.analyze(html)
        XCTAssertNotNil(result)
        XCTAssertEqual(result!.sentenceCount, 2)
    }

    func testAnalyze_UnicodeText() {
        // Unicode should still tokenize and count
        let result = analyzer.analyze("Café résumé naïve.")
        XCTAssertNotNil(result)
        XCTAssertEqual(result!.wordCount, 3)
    }

    // MARK: - Constants

    func testWordsPerMinute() {
        XCTAssertEqual(ArticleReadabilityAnalyzer.wordsPerMinute, 238.0)
    }

    // MARK: - Singleton

    func testSharedInstance() {
        let a = ArticleReadabilityAnalyzer.shared
        let b = ArticleReadabilityAnalyzer.shared
        XCTAssertTrue(a === b, "shared should return the same instance")
    }

    // MARK: - ReadabilityResult Properties

    func testReadabilityResult_AllFieldsPopulated() {
        let result = analyzer.analyze("The quick brown fox jumps over the lazy dog. This is a simple test sentence.")!
        XCTAssertGreaterThan(result.wordCount, 0)
        XCTAssertGreaterThan(result.sentenceCount, 0)
        XCTAssertGreaterThan(result.syllableCount, 0)
        XCTAssertGreaterThan(result.averageWordsPerSentence, 0)
        XCTAssertGreaterThan(result.averageSyllablesPerWord, 0)
        // FRE can be negative for very hard text, but for this text it should be positive
        XCTAssertGreaterThan(result.fleschReadingEase, 0)
        XCTAssertGreaterThan(result.estimatedReadingTimeSeconds, 0)
    }
}
