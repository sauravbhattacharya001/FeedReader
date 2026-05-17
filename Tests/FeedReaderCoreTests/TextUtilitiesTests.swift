//
//  TextUtilitiesTests.swift
//  FeedReaderCoreTests
//
//  Tests for the shared text-processing utilities used across the
//  FeedReaderCore library. These exercise the public API surface
//  (XML/HTML escaping, word counting, reading time, significant
//  word extraction, and frequency analysis) including the fast-path
//  shortcuts and edge cases.
//

import XCTest
@testable import FeedReaderCore

final class TextUtilitiesTests: XCTestCase {

    // MARK: - escapeXML

    func testEscapeXMLAllSpecialCharacters() {
        let input  = #"Tom & Jerry <said> "hi" 'world'"#
        let result = TextUtilities.escapeXML(input)
        XCTAssertEqual(
            result,
            "Tom &amp; Jerry &lt;said&gt; &quot;hi&quot; &apos;world&apos;"
        )
    }

    func testEscapeXMLNoSpecialCharactersReturnsInputUnchanged() {
        let input  = "Hello, world. Plain ASCII 123."
        let result = TextUtilities.escapeXML(input)
        XCTAssertEqual(result, input)
        // Fast path should preserve unicode that doesn't need escaping.
        let unicode = "Café — résumé 日本語"
        XCTAssertEqual(TextUtilities.escapeXML(unicode), unicode)
    }

    func testEscapeXMLEmptyString() {
        XCTAssertEqual(TextUtilities.escapeXML(""), "")
    }

    func testEscapeXMLAmpersandDoubleEscapeSafety() {
        // Confirm that already-escaped entities get escaped again — the
        // function operates on raw input, not previously-escaped XML.
        let input  = "AT&amp;T"
        let result = TextUtilities.escapeXML(input)
        XCTAssertEqual(result, "AT&amp;amp;T")
    }

    func testEscapeXMLOnlySpecialCharacters() {
        XCTAssertEqual(
            TextUtilities.escapeXML("<>&\"'"),
            "&lt;&gt;&amp;&quot;&apos;"
        )
    }

    // MARK: - escapeHTML

    func testEscapeHTMLEscapesFourEntities() {
        let input  = #"<a href="x">Tom & Jerry</a>"#
        let result = TextUtilities.escapeHTML(input)
        XCTAssertEqual(
            result,
            "&lt;a href=&quot;x&quot;&gt;Tom &amp; Jerry&lt;/a&gt;"
        )
    }

    func testEscapeHTMLDoesNotEscapeSingleQuotes() {
        // Differs from escapeXML — apostrophes are preserved for readability.
        let input  = "It's a 'test'"
        let result = TextUtilities.escapeHTML(input)
        XCTAssertEqual(result, "It's a 'test'")
    }

    func testEscapeHTMLNoSpecialCharactersReturnsInputUnchanged() {
        let input  = "Just text with apostrophes: It's fine."
        XCTAssertEqual(TextUtilities.escapeHTML(input), input)
    }

    func testEscapeHTMLEmptyString() {
        XCTAssertEqual(TextUtilities.escapeHTML(""), "")
    }

    // MARK: - countWords

    func testCountWordsBasic() {
        XCTAssertEqual(TextUtilities.countWords("Hello world"), 2)
        XCTAssertEqual(TextUtilities.countWords("One"), 1)
    }

    func testCountWordsCollapsesWhitespace() {
        // Multiple spaces, tabs, and newlines should all collapse cleanly.
        XCTAssertEqual(TextUtilities.countWords("  hello   world  \n  foo\tbar  "), 4)
    }

    func testCountWordsEmptyAndWhitespaceOnly() {
        XCTAssertEqual(TextUtilities.countWords(""), 0)
        XCTAssertEqual(TextUtilities.countWords("     "), 0)
        XCTAssertEqual(TextUtilities.countWords("\n\t  \r\n"), 0)
    }

    func testCountWordsCountsPunctuationAsPartOfToken() {
        // Word boundaries are whitespace-only; punctuation is part of the token.
        XCTAssertEqual(TextUtilities.countWords("Hello, world! It's me."), 4)
    }

    // MARK: - estimateReadTime

    func testEstimateReadTimeZeroOrShortReturnsAtLeastOne() {
        XCTAssertEqual(TextUtilities.estimateReadTime(wordCount: 0), 1)
        XCTAssertEqual(TextUtilities.estimateReadTime(wordCount: 1), 1)
        XCTAssertEqual(TextUtilities.estimateReadTime(wordCount: 199), 1)
    }

    func testEstimateReadTimeStandardRates() {
        XCTAssertEqual(TextUtilities.estimateReadTime(wordCount: 200), 1)
        XCTAssertEqual(TextUtilities.estimateReadTime(wordCount: 400), 2)
        XCTAssertEqual(TextUtilities.estimateReadTime(wordCount: 1000), 5)
        XCTAssertEqual(TextUtilities.estimateReadTime(wordCount: 2050), 10)
    }

    // MARK: - extractSignificantWords

    func testExtractSignificantWordsFiltersStopWords() {
        // "the", "a", "with", "of" are stop words and should be dropped.
        let words = TextUtilities.extractSignificantWords(
            from: "The quick brown fox jumps over a lazy dog with lots of style"
        )
        XCTAssertFalse(words.contains("the"))
        XCTAssertFalse(words.contains("a"))
        XCTAssertFalse(words.contains("with"))
        XCTAssertFalse(words.contains("of"))
        XCTAssertTrue(words.contains("quick"))
        XCTAssertTrue(words.contains("brown"))
        XCTAssertTrue(words.contains("fox"))
        XCTAssertTrue(words.contains("jumps"))
        XCTAssertTrue(words.contains("lazy"))
        XCTAssertTrue(words.contains("dog"))
        XCTAssertTrue(words.contains("lots"))
        XCTAssertTrue(words.contains("style"))
    }

    func testExtractSignificantWordsLowercasesOutput() {
        let words = TextUtilities.extractSignificantWords(from: "FOO BAR Baz")
        XCTAssertTrue(words.allSatisfy { $0 == $0.lowercased() })
        XCTAssertEqual(Set(words), Set(["foo", "bar", "baz"]))
    }

    func testExtractSignificantWordsRespectsMinimumLength() {
        // Default minimum length is 3 — "hi" and "ok" should be filtered out.
        let defaultWords = TextUtilities.extractSignificantWords(from: "hi all ok folks")
        XCTAssertFalse(defaultWords.contains("hi"))
        XCTAssertFalse(defaultWords.contains("ok"))

        // With a larger minimum, "all" (stop word) is still gone, and
        // "folks" (5 letters) survives; "ok" is filtered for length.
        let stricter = TextUtilities.extractSignificantWords(
            from: "hi all ok folks",
            minimumLength: 5
        )
        XCTAssertEqual(stricter, ["folks"])
    }

    func testExtractSignificantWordsFiltersPurelyNumericTokens() {
        let words = TextUtilities.extractSignificantWords(from: "Build 12345 released")
        XCTAssertFalse(words.contains("12345"))
        XCTAssertTrue(words.contains("build"))
        XCTAssertTrue(words.contains("released"))
    }

    func testExtractSignificantWordsPreservesOrderAndDuplicates() {
        // The function returns words in order of appearance (no dedup).
        let words = TextUtilities.extractSignificantWords(from: "alpha beta alpha gamma")
        XCTAssertEqual(words, ["alpha", "beta", "alpha", "gamma"])
    }

    func testExtractSignificantWordsHandlesEmptyAndStopWordOnlyText() {
        XCTAssertEqual(TextUtilities.extractSignificantWords(from: ""), [])
        // All stop words → no output.
        XCTAssertEqual(
            TextUtilities.extractSignificantWords(from: "the a an and or but"),
            []
        )
    }

    // MARK: - computeWordFrequencies

    func testComputeWordFrequenciesCountsCorrectly() {
        let freq = TextUtilities.computeWordFrequencies(
            from: "alpha beta alpha gamma alpha beta"
        )
        XCTAssertEqual(freq["alpha"], 3)
        XCTAssertEqual(freq["beta"], 2)
        XCTAssertEqual(freq["gamma"], 1)
        XCTAssertEqual(freq.count, 3)
    }

    func testComputeWordFrequenciesAppliesSameFiltersAsExtractor() {
        // Stop words, short words, and numeric tokens should not appear.
        let freq = TextUtilities.computeWordFrequencies(
            from: "The 2026 build ok build BUILD release"
        )
        XCTAssertNil(freq["the"])
        XCTAssertNil(freq["2026"])
        XCTAssertNil(freq["ok"])
        XCTAssertEqual(freq["build"], 3, "Frequency analysis is case-insensitive")
        XCTAssertEqual(freq["release"], 1)
    }

    func testComputeWordFrequenciesIsConsistentWithExtractSignificantWords() {
        let text = "Swift testing is fun and Swift testing is robust"
        let words = TextUtilities.extractSignificantWords(from: text)
        let freq  = TextUtilities.computeWordFrequencies(from: text)

        // Frequencies must match the bag-of-words from the extractor.
        var manual: [String: Int] = [:]
        for w in words { manual[w, default: 0] += 1 }
        XCTAssertEqual(freq, manual)
    }

    func testComputeWordFrequenciesEmptyInput() {
        XCTAssertEqual(TextUtilities.computeWordFrequencies(from: "").count, 0)
        XCTAssertEqual(TextUtilities.computeWordFrequencies(from: "the and or").count, 0)
    }

    func testComputeWordFrequenciesRespectsMinimumLength() {
        let freq = TextUtilities.computeWordFrequencies(
            from: "cat dog elephant cat",
            minimumLength: 4
        )
        // "cat" (3) and "dog" (3) filtered; only "elephant" remains.
        XCTAssertNil(freq["cat"])
        XCTAssertNil(freq["dog"])
        XCTAssertEqual(freq["elephant"], 1)
    }

    // MARK: - Stop words sanity

    func testStopWordsAreLowercaseAndNonEmpty() {
        XCTAssertFalse(TextUtilities.stopWords.isEmpty)
        for word in TextUtilities.stopWords {
            XCTAssertFalse(word.isEmpty, "Stop words must not be empty")
            XCTAssertEqual(
                word,
                word.lowercased(),
                "Stop word '\(word)' must be lowercase so filtering is case-insensitive"
            )
        }
    }
}
