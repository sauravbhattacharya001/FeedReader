//
//  KeywordExtractorTests.swift
//  FeedReaderCoreTests
//
//  Tests for KeywordExtractor: term-frequency keyword extraction
//  with stop-word filtering.
//

import XCTest
@testable import FeedReaderCore

final class KeywordExtractorTests: XCTestCase {

    var extractor: KeywordExtractor!

    override func setUp() {
        super.setUp()
        extractor = KeywordExtractor()
    }

    override func tearDown() {
        extractor = nil
        super.tearDown()
    }

    // MARK: - Basic Extraction

    func testExtractKeywordsFromSimpleText() {
        let text = "Swift programming language Swift development Swift code"
        let keywords = extractor.extractKeywords(from: text)

        XCTAssertFalse(keywords.isEmpty)
        XCTAssertEqual(keywords.first, "swift", "Most frequent word should be first")
    }

    func testExtractKeywordsRespectsCount() {
        let text = "apple banana cherry date elderberry fig grape honeydew"
        let keywords = extractor.extractKeywords(from: text, count: 3)

        XCTAssertEqual(keywords.count, 3)
    }

    func testExtractKeywordsDefaultCount() {
        // Default count is 5
        let text = "alpha bravo charlie delta echo foxtrot golf hotel india juliet"
        let keywords = extractor.extractKeywords(from: text)

        XCTAssertLessThanOrEqual(keywords.count, 5)
    }

    func testExtractKeywordsFiltersStopWords() {
        let text = "the quick brown fox jumps over the lazy dog"
        let keywords = extractor.extractKeywords(from: text)

        XCTAssertFalse(keywords.contains("the"))
        XCTAssertFalse(keywords.contains("over"))
        // "quick", "brown", "jumps", "lazy" should survive
        XCTAssertTrue(keywords.contains("quick") || keywords.contains("brown"))
    }

    func testExtractKeywordsFiltersShortWords() {
        let text = "go to be or do it on at by if"
        let keywords = extractor.extractKeywords(from: text)

        XCTAssertTrue(keywords.isEmpty, "All words are too short or are stop words")
    }

    func testExtractKeywordsFiltersNumbers() {
        let text = "test 123 456 789 experiment 2024"
        let keywords = extractor.extractKeywords(from: text)

        XCTAssertFalse(keywords.contains("123"))
        XCTAssertFalse(keywords.contains("456"))
        XCTAssertFalse(keywords.contains("2024"))
    }

    func testExtractKeywordsIsCaseInsensitive() {
        let text = "Swift SWIFT swift SwIfT programming"
        let keywords = extractor.extractKeywords(from: text, count: 1)

        XCTAssertEqual(keywords.first, "swift")
    }

    func testExtractKeywordsFromEmptyString() {
        let keywords = extractor.extractKeywords(from: "")

        XCTAssertTrue(keywords.isEmpty)
    }

    func testExtractKeywordsReturnsLowercased() {
        let text = "TECHNOLOGY Innovation Research"
        let keywords = extractor.extractKeywords(from: text)

        for keyword in keywords {
            XCTAssertEqual(keyword, keyword.lowercased())
        }
    }

    // MARK: - Frequency Ordering

    func testKeywordsAreSortedByFrequency() {
        let text = "climate climate climate energy energy solar"
        let keywords = extractor.extractKeywords(from: text, count: 3)

        XCTAssertEqual(keywords[0], "climate")
        XCTAssertEqual(keywords[1], "energy")
        XCTAssertEqual(keywords[2], "solar")
    }

    // MARK: - Configuration

    func testMinimumWordLengthIsConfigurable() {
        extractor.minimumWordLength = 6
        let text = "swift code programming language development"
        let keywords = extractor.extractKeywords(from: text, count: 10)

        for keyword in keywords {
            XCTAssertGreaterThanOrEqual(keyword.count, 6)
        }
        XCTAssertFalse(keywords.contains("swift"))  // 5 chars
        XCTAssertFalse(keywords.contains("code"))    // 4 chars
    }

    func testDefaultCountIsConfigurable() {
        extractor.defaultCount = 2
        let text = "alpha bravo charlie delta echo foxtrot golf hotel"
        let keywords = extractor.extractKeywords(from: text)

        XCTAssertLessThanOrEqual(keywords.count, 2)
    }

    // MARK: - extractTags (RSSStory integration)

    func testExtractTagsFromStory() {
        guard let story = RSSStory(
            title: "Climate Change Summit Results",
            body: "World leaders gathered to discuss climate policy and emissions targets for carbon reduction.",
            link: "https://example.com/article"
        ) else {
            XCTFail("Failed to create story")
            return
        }

        let tags = extractor.extractTags(from: story, count: 5)

        XCTAssertFalse(tags.isEmpty)
        // "climate" appears in both title (3x weight) and body — should rank high
        XCTAssertEqual(tags.first, "climate")
    }

    func testExtractTagsTitleWordsWeightedHigher() {
        guard let story = RSSStory(
            title: "Quantum Computing Breakthrough",
            body: "Scientists reported advances in artificial intelligence and machine learning research today.",
            link: "https://example.com/article"
        ) else {
            XCTFail("Failed to create story")
            return
        }

        let tags = extractor.extractTags(from: story, count: 3)

        // Title words should dominate despite appearing only once (3x weight)
        XCTAssertTrue(tags.contains("quantum") || tags.contains("computing") || tags.contains("breakthrough"))
    }

    // MARK: - extractThemes (Multi-story)

    func testExtractThemesFromMultipleStories() {
        let stories = [
            RSSStory(title: "Climate Policy Update", body: "New climate regulations announced for carbon emissions.", link: "https://example.com/1")!,
            RSSStory(title: "Carbon Tax Debate", body: "Climate scientists support carbon pricing mechanisms.", link: "https://example.com/2")!,
            RSSStory(title: "Renewable Energy Growth", body: "Solar and wind energy investments climate targets.", link: "https://example.com/3")!,
        ]

        let themes = extractor.extractThemes(from: stories, count: 5)

        XCTAssertFalse(themes.isEmpty)
        // "climate" appears in all 3 stories — should be a top theme
        XCTAssertTrue(themes.contains("climate"))
    }

    func testExtractThemesFiltersSingleStoryWords() {
        let stories = [
            RSSStory(title: "Space Mission Launch", body: "NASA launched a new space telescope mission.", link: "https://example.com/1")!,
            RSSStory(title: "Ocean Exploration", body: "Deep sea research discovers new marine species.", link: "https://example.com/2")!,
        ]

        let themes = extractor.extractThemes(from: stories, count: 10)

        // Words unique to one story shouldn't be themes (unless both stories share them)
        // "space" only in story 1, "ocean" only in story 2
        XCTAssertFalse(themes.contains("space"))
        XCTAssertFalse(themes.contains("ocean"))
    }

    func testExtractThemesFromSingleStory() {
        let stories = [
            RSSStory(title: "Tech News", body: "Technology advances continue rapidly.", link: "https://example.com/1")!,
        ]

        // With only 1 story, minDocs becomes 1 so all keywords qualify
        let themes = extractor.extractThemes(from: stories, count: 5)
        XCTAssertFalse(themes.isEmpty)
    }

    func testExtractThemesFromEmptyArray() {
        let themes = extractor.extractThemes(from: [], count: 5)
        XCTAssertTrue(themes.isEmpty)
    }
}
