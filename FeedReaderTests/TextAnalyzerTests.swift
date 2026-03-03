//
//  TextAnalyzerTests.swift
//  FeedReaderTests
//
//  Tests for TextAnalyzer — tokenization, stop word filtering,
//  keyword extraction, and term frequency computation.
//

import XCTest
@testable import FeedReader

class TextAnalyzerTests: XCTestCase {

    var analyzer: TextAnalyzer!

    override func setUp() {
        super.setUp()
        analyzer = TextAnalyzer.shared
    }

    // MARK: - Tokenization

    func testTokenizeBasicSentence() {
        let tokens = analyzer.tokenize("The quick brown fox jumps over the lazy dog")
        // "the", "quick", "brown", "fox", "jumps", "over", "the", "lazy", "dog"
        // After stop word removal: "quick", "brown", "fox", "jumps", "lazy", "dog"
        // After min length 3: same (all >= 3)
        XCTAssertTrue(tokens.contains("quick"))
        XCTAssertTrue(tokens.contains("brown"))
        XCTAssertTrue(tokens.contains("fox"))
        XCTAssertTrue(tokens.contains("jumps"))
        XCTAssertTrue(tokens.contains("lazy"))
        XCTAssertTrue(tokens.contains("dog"))
        // "the" and "over" are stop words
        XCTAssertFalse(tokens.contains("the"))
        XCTAssertFalse(tokens.contains("over"))
    }

    func testTokenizeLowercases() {
        let tokens = analyzer.tokenize("HELLO World MiXeD")
        XCTAssertTrue(tokens.contains("hello"))
        XCTAssertTrue(tokens.contains("world"))
        XCTAssertTrue(tokens.contains("mixed"))
        XCTAssertFalse(tokens.contains("HELLO"))
        XCTAssertFalse(tokens.contains("World"))
    }

    func testTokenizeRemovesStopWords() {
        let tokens = analyzer.tokenize("I am the very best")
        // "i", "am" (< 3 chars), "the", "very", "best" → "best" survives
        XCTAssertFalse(tokens.contains("the"))
        XCTAssertFalse(tokens.contains("very"))
        XCTAssertTrue(tokens.contains("best"))
    }

    func testTokenizeFiltersShortTerms() {
        let tokens = analyzer.tokenize("AI is a good OS for my PC")
        // "ai" (2 chars), "is" (stop + 2 chars), "a" (stop + 1 char),
        // "good" (stop), "for" (stop + 3), "my" (stop + 2), "pc" (2 chars)
        XCTAssertFalse(tokens.contains("ai"))
        XCTAssertFalse(tokens.contains("is"))
        XCTAssertFalse(tokens.contains("pc"))
    }

    func testTokenizeCustomMinLength() {
        let tokens = analyzer.tokenize("cat dog elephant", minLength: 4)
        XCTAssertFalse(tokens.contains("cat"))
        XCTAssertFalse(tokens.contains("dog"))
        XCTAssertTrue(tokens.contains("elephant"))
    }

    func testTokenizeSplitsOnPunctuation() {
        let tokens = analyzer.tokenize("Hello, world! This is a test—really? Yes.")
        XCTAssertTrue(tokens.contains("hello"))
        XCTAssertTrue(tokens.contains("test"))
        XCTAssertTrue(tokens.contains("really"))
        XCTAssertTrue(tokens.contains("yes"))
    }

    func testTokenizeSplitsOnSpecialCharacters() {
        let tokens = analyzer.tokenize("machine-learning/deep_learning@neural.networks")
        XCTAssertTrue(tokens.contains("machine"))
        XCTAssertTrue(tokens.contains("learning"))
        XCTAssertTrue(tokens.contains("deep"))
        XCTAssertTrue(tokens.contains("neural"))
        XCTAssertTrue(tokens.contains("networks"))
    }

    func testTokenizeEmptyString() {
        let tokens = analyzer.tokenize("")
        XCTAssertTrue(tokens.isEmpty)
    }

    func testTokenizeAllStopWords() {
        let tokens = analyzer.tokenize("the is are was were")
        XCTAssertTrue(tokens.isEmpty)
    }

    func testTokenizePreservesDuplicates() {
        let tokens = analyzer.tokenize("apple banana apple cherry banana apple")
        let appleCount = tokens.filter { $0 == "apple" }.count
        XCTAssertEqual(appleCount, 3)
    }

    func testTokenizeWithNumbers() {
        let tokens = analyzer.tokenize("Python 3.12 released with 500 improvements")
        XCTAssertTrue(tokens.contains("python"))
        XCTAssertTrue(tokens.contains("released"))
        XCTAssertTrue(tokens.contains("improvements"))
        XCTAssertTrue(tokens.contains("500"))
    }

    func testTokenizeMinLengthOne() {
        let tokens = analyzer.tokenize("I see a big cat", minLength: 1)
        // Even with minLength 1, stop words still removed
        XCTAssertFalse(tokens.contains("i"))
        XCTAssertFalse(tokens.contains("a"))
        XCTAssertTrue(tokens.contains("see"))
        XCTAssertTrue(tokens.contains("big"))
        XCTAssertTrue(tokens.contains("cat"))
    }

    // MARK: - Stop Words

    func testStopWordsContainsCommonArticles() {
        XCTAssertTrue(TextAnalyzer.stopWords.contains("a"))
        XCTAssertTrue(TextAnalyzer.stopWords.contains("an"))
        XCTAssertTrue(TextAnalyzer.stopWords.contains("the"))
    }

    func testStopWordsContainsCommonPronouns() {
        XCTAssertTrue(TextAnalyzer.stopWords.contains("i"))
        XCTAssertTrue(TextAnalyzer.stopWords.contains("you"))
        XCTAssertTrue(TextAnalyzer.stopWords.contains("they"))
        XCTAssertTrue(TextAnalyzer.stopWords.contains("we"))
    }

    func testStopWordsContainsCommonPrepositions() {
        XCTAssertTrue(TextAnalyzer.stopWords.contains("in"))
        XCTAssertTrue(TextAnalyzer.stopWords.contains("on"))
        XCTAssertTrue(TextAnalyzer.stopWords.contains("at"))
        XCTAssertTrue(TextAnalyzer.stopWords.contains("to"))
    }

    func testStopWordsContainsBeVerbs() {
        XCTAssertTrue(TextAnalyzer.stopWords.contains("is"))
        XCTAssertTrue(TextAnalyzer.stopWords.contains("are"))
        XCTAssertTrue(TextAnalyzer.stopWords.contains("was"))
        XCTAssertTrue(TextAnalyzer.stopWords.contains("were"))
        XCTAssertTrue(TextAnalyzer.stopWords.contains("been"))
    }

    func testStopWordsDoesNotContainTechnicalTerms() {
        XCTAssertFalse(TextAnalyzer.stopWords.contains("algorithm"))
        XCTAssertFalse(TextAnalyzer.stopWords.contains("data"))
        XCTAssertFalse(TextAnalyzer.stopWords.contains("python"))
        XCTAssertFalse(TextAnalyzer.stopWords.contains("function"))
    }

    func testDefaultMinTermLength() {
        XCTAssertEqual(TextAnalyzer.defaultMinTermLength, 3)
    }

    // MARK: - Keyword Extraction

    func testExtractKeywordsDeduplicates() {
        let keywords = analyzer.extractKeywords(from: "apple banana apple cherry banana apple")
        XCTAssertEqual(keywords.count, 3)
        XCTAssertTrue(keywords.contains("apple"))
        XCTAssertTrue(keywords.contains("banana"))
        XCTAssertTrue(keywords.contains("cherry"))
    }

    func testExtractKeywordsPreservesFirstOccurrenceOrder() {
        let keywords = analyzer.extractKeywords(from: "cherry banana apple cherry banana")
        XCTAssertEqual(keywords[0], "cherry")
        XCTAssertEqual(keywords[1], "banana")
        XCTAssertEqual(keywords[2], "apple")
    }

    func testExtractKeywordsFiltersStopWords() {
        let keywords = analyzer.extractKeywords(from: "The quick brown fox is very fast")
        XCTAssertFalse(keywords.contains("the"))
        XCTAssertFalse(keywords.contains("is"))
        XCTAssertFalse(keywords.contains("very"))
        XCTAssertTrue(keywords.contains("quick"))
        XCTAssertTrue(keywords.contains("brown"))
        XCTAssertTrue(keywords.contains("fox"))
        XCTAssertTrue(keywords.contains("fast"))
    }

    func testExtractKeywordsEmpty() {
        let keywords = analyzer.extractKeywords(from: "")
        XCTAssertTrue(keywords.isEmpty)
    }

    func testExtractKeywordsAllStopWords() {
        let keywords = analyzer.extractKeywords(from: "the is are was were have has")
        XCTAssertTrue(keywords.isEmpty)
    }

    func testExtractKeywordsCustomMinLength() {
        let keywords = analyzer.extractKeywords(from: "big cat runs fast", minLength: 4)
        XCTAssertFalse(keywords.contains("big"))
        XCTAssertFalse(keywords.contains("cat"))
        XCTAssertTrue(keywords.contains("runs"))
        XCTAssertTrue(keywords.contains("fast"))
    }

    func testExtractKeywordsFromRealArticleTitle() {
        let keywords = analyzer.extractKeywords(
            from: "Apple releases iOS 18 with breakthrough AI features for iPhone users"
        )
        XCTAssertTrue(keywords.contains("apple"))
        XCTAssertTrue(keywords.contains("releases"))
        XCTAssertTrue(keywords.contains("ios"))
        XCTAssertTrue(keywords.contains("breakthrough"))
        XCTAssertTrue(keywords.contains("features"))
        XCTAssertTrue(keywords.contains("iphone"))
        XCTAssertTrue(keywords.contains("users"))
    }

    // MARK: - Term Frequency

    func testComputeTermFrequencyBasic() {
        let tokens = ["apple", "banana", "apple", "cherry", "apple"]
        let tf = analyzer.computeTermFrequency(tokens)

        // apple appears 3 times (max), so its TF = 1.0
        XCTAssertEqual(tf["apple"], 1.0, accuracy: 0.001)
        // banana appears 1 time, TF = 1/3
        XCTAssertEqual(tf["banana"]!, 1.0 / 3.0, accuracy: 0.001)
        // cherry appears 1 time, TF = 1/3
        XCTAssertEqual(tf["cherry"]!, 1.0 / 3.0, accuracy: 0.001)
    }

    func testComputeTermFrequencyAllSame() {
        let tokens = ["hello", "hello", "hello"]
        let tf = analyzer.computeTermFrequency(tokens)
        XCTAssertEqual(tf.count, 1)
        XCTAssertEqual(tf["hello"], 1.0)
    }

    func testComputeTermFrequencyAllUnique() {
        let tokens = ["alpha", "beta", "gamma"]
        let tf = analyzer.computeTermFrequency(tokens)
        XCTAssertEqual(tf.count, 3)
        // Each appears once, max is 1, so all are 1.0
        XCTAssertEqual(tf["alpha"], 1.0)
        XCTAssertEqual(tf["beta"], 1.0)
        XCTAssertEqual(tf["gamma"], 1.0)
    }

    func testComputeTermFrequencyEmpty() {
        let tf = analyzer.computeTermFrequency([])
        XCTAssertTrue(tf.isEmpty)
    }

    func testComputeTermFrequencyNormalization() {
        // Verify all values are between 0.0 and 1.0
        let tokens = ["swift", "python", "swift", "java", "swift", "python"]
        let tf = analyzer.computeTermFrequency(tokens)

        for (_, value) in tf {
            XCTAssertGreaterThanOrEqual(value, 0.0)
            XCTAssertLessThanOrEqual(value, 1.0)
        }

        // swift: 3/3 = 1.0, python: 2/3 ≈ 0.667, java: 1/3 ≈ 0.333
        XCTAssertEqual(tf["swift"], 1.0, accuracy: 0.001)
        XCTAssertEqual(tf["python"]!, 2.0 / 3.0, accuracy: 0.001)
        XCTAssertEqual(tf["java"]!, 1.0 / 3.0, accuracy: 0.001)
    }

    func testComputeTermFrequencySingleToken() {
        let tf = analyzer.computeTermFrequency(["only"])
        XCTAssertEqual(tf.count, 1)
        XCTAssertEqual(tf["only"], 1.0)
    }

    // MARK: - Integration: Tokenize + TF Pipeline

    func testTokenizeThenComputeTermFrequency() {
        let text = "machine learning is transforming machine learning applications in deep learning"
        let tokens = analyzer.tokenize(text)
        let tf = analyzer.computeTermFrequency(tokens)

        // "machine" appears 2x, "learning" appears 3x (max), "transforming" 1x,
        // "applications" 1x, "deep" 1x
        XCTAssertEqual(tf["learning"], 1.0, accuracy: 0.001)
        XCTAssertTrue(tf["machine"]! < tf["learning"]!)
        XCTAssertTrue(tf.keys.contains("transforming"))
        XCTAssertTrue(tf.keys.contains("applications"))
        XCTAssertTrue(tf.keys.contains("deep"))
    }

    func testExtractKeywordsThenComputeTermFrequency() {
        // Keywords are deduplicated, so TF should be uniform
        let keywords = analyzer.extractKeywords(from: "rust cargo rust crate rust")
        let tf = analyzer.computeTermFrequency(keywords)
        // Keywords: ["rust", "cargo", "crate"] — each once
        XCTAssertEqual(tf.count, 3)
        for (_, value) in tf {
            XCTAssertEqual(value, 1.0, accuracy: 0.001)
        }
    }

    // MARK: - Edge Cases

    func testTokenizeUnicodeText() {
        let tokens = analyzer.tokenize("café résumé naïve")
        // Unicode characters are alphanumeric, so they should be kept
        XCTAssertTrue(tokens.contains("café") || tokens.contains("caf"))
        XCTAssertTrue(tokens.contains("résumé") || tokens.contains("r"))
        XCTAssertTrue(tokens.contains("naïve") || tokens.contains("na"))
    }

    func testTokenizeURLInText() {
        let tokens = analyzer.tokenize("Visit https://example.com/path for details")
        // URL gets split on non-alphanumeric chars
        XCTAssertTrue(tokens.contains("visit"))
        XCTAssertTrue(tokens.contains("https"))
        XCTAssertTrue(tokens.contains("example"))
        XCTAssertTrue(tokens.contains("details"))
    }

    func testTokenizeOnlyWhitespace() {
        let tokens = analyzer.tokenize("   \t\n   ")
        XCTAssertTrue(tokens.isEmpty)
    }

    func testTokenizeSingleLongWord() {
        let tokens = analyzer.tokenize("antidisestablishmentarianism")
        XCTAssertEqual(tokens.count, 1)
        XCTAssertEqual(tokens[0], "antidisestablishmentarianism")
    }

    func testStopWordsSetIsNotEmpty() {
        XCTAssertGreaterThan(TextAnalyzer.stopWords.count, 50)
    }

    func testSingletonIdentity() {
        let a = TextAnalyzer.shared
        let b = TextAnalyzer.shared
        XCTAssertTrue(a === b)
    }
}
