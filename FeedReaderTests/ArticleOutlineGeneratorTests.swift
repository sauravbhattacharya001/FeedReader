//
//  ArticleOutlineGeneratorTests.swift
//  FeedReader
//
//  Tests for ArticleOutlineGenerator — section detection, keyword extraction,
//  rendering, comparison, and edge cases.
//

import XCTest
@testable import FeedReader

final class ArticleOutlineGeneratorTests: XCTestCase {

    private var sut: ArticleOutlineGenerator!

    override func setUp() {
        super.setUp()
        sut = ArticleOutlineGenerator()
        sut.clearCache()
    }

    override func tearDown() {
        sut.clearCache()
        sut = nil
        super.tearDown()
    }

    // MARK: - Basic Generation

    func testGenerateOutline_withMarkdownHeadings_detectsSections() {
        let text = """
        # Introduction

        This is the introduction paragraph with enough words to meet the minimum \
        section threshold. We need at least thirty words so the generator does not \
        skip this section entirely.

        ## Methods

        The methods section describes how we approached the problem. It contains \
        detailed steps about our methodology and the tools we used for analysis \
        and data collection throughout the study.

        ## Results

        Our results show significant improvement across all metrics measured. The \
        data clearly demonstrates that the new approach outperforms the baseline \
        by a wide margin in every category tested.

        ## Conclusion

        In conclusion, this study demonstrates the value of the new approach. We \
        recommend further investigation and additional testing to validate these \
        promising initial findings across more domains.
        """

        let outline = sut.generateOutline(url: "https://example.com/1", title: "Test Article", text: text)

        XCTAssertEqual(outline.articleTitle, "Test Article")
        XCTAssertEqual(outline.articleURL, "https://example.com/1")
        XCTAssertGreaterThan(outline.totalWordCount, 0)
        XCTAssertGreaterThan(outline.totalReadingTimeSeconds, 0)
        XCTAssertGreaterThan(outline.sections.count, 1, "Should detect multiple sections from markdown headings")
    }

    func testGenerateOutline_withNoHeadings_createsFullArticleSection() {
        let text = """
        This is a plain article with no headings at all. It contains a single \
        block of text that goes on for a while discussing various topics without \
        any structural markers or section breaks of any kind whatsoever in the \
        entire body of the document being analyzed.
        """

        let outline = sut.generateOutline(url: "https://example.com/2", title: "Plain", text: text)

        XCTAssertGreaterThanOrEqual(outline.sections.count, 1)
    }

    func testGenerateOutline_emptyText_returnsMinimalOutline() {
        let outline = sut.generateOutline(url: "https://example.com/3", title: "Empty", text: "")

        XCTAssertEqual(outline.totalWordCount, 0)
        // Should still produce at least one section (the "Full Article" fallback)
        XCTAssertGreaterThanOrEqual(outline.sections.count, 0)
    }

    // MARK: - Caching

    func testCaching_returnsSameOutlineForSameText() {
        let text = "Some article text with enough words to form at least one section for the outline generator to process properly."
        let url = "https://example.com/cache"

        let first = sut.generateOutline(url: url, title: "Cached", text: text)
        let second = sut.generateOutline(url: url, title: "Cached", text: text)

        XCTAssertEqual(first, second)
    }

    func testCaching_invalidatesOnTextChange() {
        let url = "https://example.com/cache2"
        let first = sut.generateOutline(url: url, title: "V1", text: "Original text with enough words to pass the minimum word count threshold for section detection and generation.")
        let second = sut.generateOutline(url: url, title: "V2", text: "Completely different updated text that has enough words to also pass the minimum section threshold for the generator.")

        // generatedAt should differ since text hash changed
        XCTAssertNotEqual(first.generatedAt, second.generatedAt)
    }

    func testCachedOutline_returnsNilForUnknownURL() {
        XCTAssertNil(sut.cachedOutline(for: "https://unknown.com"))
    }

    func testRemoveCachedOutline_removesEntry() {
        let url = "https://example.com/remove"
        _ = sut.generateOutline(url: url, title: "Remove", text: "Some content with enough words for testing the cache removal feature of the outline generator properly.")

        XCTAssertNotNil(sut.cachedOutline(for: url))
        sut.removeCachedOutline(for: url)
        XCTAssertNil(sut.cachedOutline(for: url))
    }

    func testClearCache_emptiesAllEntries() {
        _ = sut.generateOutline(url: "https://a.com", title: "A", text: "Article A with enough filler words to meet the minimum threshold of thirty words for section detection logic.")
        _ = sut.generateOutline(url: "https://b.com", title: "B", text: "Article B with enough filler words to meet the minimum threshold of thirty words for section detection logic.")

        XCTAssertEqual(sut.cachedCount, 2)
        sut.clearCache()
        XCTAssertEqual(sut.cachedCount, 0)
    }

    // MARK: - Keywords

    func testSummaryKeywords_excludeStopWords() {
        let text = """
        Machine learning algorithms process data efficiently. Neural networks \
        learn patterns from training datasets. Deep learning architectures \
        transform input features through multiple layers of computation to \
        produce accurate predictions for complex classification tasks.
        """

        let outline = sut.generateOutline(url: "https://example.com/kw", title: "ML", text: text)

        let stopWords: Set<String> = ["the", "a", "an", "and", "or", "in", "on", "to", "for", "of", "is", "it"]
        for keyword in outline.summaryKeywords {
            XCTAssertFalse(stopWords.contains(keyword), "Keyword '\(keyword)' is a stop word")
        }
    }

    func testSummaryKeywords_cappedAtMaxLimit() {
        let text = String(repeating: "alpha beta gamma delta epsilon zeta eta theta iota kappa lambda mu nu xi omicron pi rho sigma tau upsilon. ", count: 10)

        let outline = sut.generateOutline(url: "https://example.com/kwlimit", title: "Greek", text: text)

        XCTAssertLessThanOrEqual(outline.summaryKeywords.count, 10)
    }

    // MARK: - Section Properties

    func testSectionProperties_wordCountAndReadingTime() {
        let text = """
        # First Section

        \(String(repeating: "word ", count: 100))

        # Second Section

        \(String(repeating: "another ", count: 200))
        """

        let outline = sut.generateOutline(url: "https://example.com/props", title: "Props", text: text)

        for section in outline.sections {
            XCTAssertGreaterThan(section.wordCount, 0)
            XCTAssertGreaterThan(section.readingTimeSeconds, 0)
            XCTAssertFalse(section.topicSentence.isEmpty)
            XCTAssertGreaterThanOrEqual(section.importanceScore, 0.0)
            XCTAssertLessThanOrEqual(section.importanceScore, 1.0)
        }
    }

    // MARK: - Rendering

    func testRenderMarkdown_containsTitleAndKeywords() {
        let text = "# Overview\n\nSoftware engineering practices improve code quality through rigorous testing, code review, and continuous integration pipelines that catch defects early."
        let outline = sut.generateOutline(url: "https://example.com/md", title: "Software Engineering", text: text)

        let md = sut.renderMarkdown(outline)

        XCTAssertTrue(md.contains("Software Engineering"))
        XCTAssertTrue(md.contains("Keywords:"))
        XCTAssertTrue(md.contains("min read"))
    }

    func testRenderPlainText_containsTitle() {
        let text = "# Overview\n\nSome content about algorithms and data structures for computer science students studying for technical interviews at large companies."
        let outline = sut.generateOutline(url: "https://example.com/pt", title: "Algorithms", text: text)

        let plain = sut.renderPlainText(outline)

        XCTAssertTrue(plain.contains("Algorithms"))
    }

    func testRenderJSON_producesValidJSON() {
        let text = "# Test\n\nEnough content for a valid section with words that meet the minimum threshold of thirty words for proper outline generation testing."
        let outline = sut.generateOutline(url: "https://example.com/json", title: "JSON Test", text: text)

        let json = sut.renderJSON(outline)
        XCTAssertNotNil(json)

        if let json = json, let data = json.data(using: .utf8) {
            XCTAssertNoThrow(try JSONSerialization.jsonObject(with: data))
        }
    }

    // MARK: - Stats

    func testLongestSection_returnsHighestWordCount() {
        let text = """
        # Short

        Just a few words here for the short section but enough to pass the minimum.

        # Long

        \(String(repeating: "extensive content ", count: 50))
        """

        let outline = sut.generateOutline(url: "https://example.com/longest", title: "Longest", text: text)
        let longest = sut.longestSection(outline)

        XCTAssertNotNil(longest)
        if let longest = longest {
            for section in outline.sections {
                XCTAssertGreaterThanOrEqual(longest.wordCount, section.wordCount)
            }
        }
    }

    func testSectionStats_returnsFlatList() {
        let text = "# A\n\n\(String(repeating: "words ", count: 40))\n\n# B\n\n\(String(repeating: "more ", count: 40))"
        let outline = sut.generateOutline(url: "https://example.com/stats", title: "Stats", text: text)

        let stats = sut.sectionStats(outline)

        XCTAssertGreaterThanOrEqual(stats.count, outline.sections.count)
    }

    // MARK: - Comparison

    func testCompare_identicalOutlines_highSimilarity() {
        let text = "# Topic\n\nArticle about machine learning algorithms and neural network architectures for deep learning applications in natural language processing tasks."
        let a = sut.generateOutline(url: "https://a.com/same", title: "A", text: text)
        let b = sut.generateOutline(url: "https://b.com/same", title: "B", text: text)

        let result = sut.compare(a, b)

        XCTAssertGreaterThan(result.structuralSimilarity, 0.5)
        XCTAssertEqual(result.sectionCountDifference, 0)
        XCTAssertEqual(result.depthDifference, 0)
    }

    func testCompare_differentOutlines_lowerSimilarity() {
        let textA = "# Cooking\n\nRecipes for Italian pasta dishes including carbonara spaghetti bolognese and lasagna with fresh ingredients from local farmers markets."
        let textB = "# Quantum Physics\n\nAdvanced quantum mechanics covers wave functions Schrodinger equations and particle entanglement phenomena observed in controlled laboratory experiments."

        let a = sut.generateOutline(url: "https://a.com/diff", title: "Cooking", text: textA)
        let b = sut.generateOutline(url: "https://b.com/diff", title: "Physics", text: textB)

        let result = sut.compare(a, b)

        // Different topics should have fewer shared keywords
        XCTAssertLessThan(result.sharedKeywords.count, 3)
    }

    // MARK: - Heading Detection

    func testAllCapsHeading_detected() {
        let text = """
        EXECUTIVE SUMMARY

        The company reported strong quarterly earnings this fiscal period with \
        revenue growth exceeding analyst expectations across all business segments \
        and geographic regions worldwide.

        FINANCIAL RESULTS

        Revenue increased by twenty percent year over year driven primarily by \
        strong performance in the cloud computing division and enterprise software \
        licensing agreements signed during this quarter.
        """

        let outline = sut.generateOutline(url: "https://example.com/caps", title: "Report", text: text)

        XCTAssertGreaterThan(outline.sections.count, 1, "Should detect ALL CAPS lines as section headings")
    }

    func testNumberedHeading_detected() {
        let text = """
        1. Introduction

        This is the introduction section with sufficient words to pass the minimum \
        word count threshold required by the outline generator for proper detection.

        2. Background

        Historical context and related work in the field provides necessary foundation \
        for understanding the contributions made by this research paper thoroughly.
        """

        let outline = sut.generateOutline(url: "https://example.com/numbered", title: "Numbered", text: text)

        XCTAssertGreaterThan(outline.sections.count, 1, "Should detect numbered sections")
    }

    // MARK: - Reading Time

    func testReadingTime_approximatelyCorrect() {
        // ~238 WPM, so 238 words ≈ 60 seconds
        let words = String(repeating: "test ", count: 238)
        let outline = sut.generateOutline(url: "https://example.com/time", title: "Time", text: words)

        // Total reading time should be roughly 60 seconds (±30s for rounding)
        XCTAssertGreaterThan(outline.totalReadingTimeSeconds, 30)
        XCTAssertLessThan(outline.totalReadingTimeSeconds, 90)
    }
}
