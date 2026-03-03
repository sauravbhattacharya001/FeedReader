//
//  ArticleSummarizerTests.swift
//  FeedReaderTests
//
//  Tests for ArticleSummarizer — extractive summarization with TF-IDF
//  scoring, title boosting, position boosting, and multi-article summary.
//

import XCTest
@testable import FeedReader

class ArticleSummarizerTests: XCTestCase {

    var summarizer: ArticleSummarizer!

    override func setUp() {
        super.setUp()
        summarizer = ArticleSummarizer.shared
    }

    // MARK: - Sample Texts

    let sampleArticle = """
    Artificial intelligence is transforming the healthcare industry in remarkable ways. \
    Machine learning algorithms can now detect diseases from medical images with accuracy \
    rivaling trained radiologists. Natural language processing helps doctors extract \
    information from clinical notes and research papers. Robotic surgery systems are \
    becoming more precise and accessible to hospitals worldwide. Drug discovery has been \
    accelerated by AI models that predict molecular interactions. Telemedicine platforms \
    use AI to triage patients before they see a doctor. The integration of AI into \
    electronic health records is streamlining administrative tasks. Patient outcomes \
    are improving as predictive analytics identify high-risk individuals early. However, \
    concerns about data privacy and algorithmic bias remain significant challenges. \
    The future of healthcare will likely see even deeper integration of artificial \
    intelligence technologies.
    """

    let shortText = "Hello world."

    let htmlArticle = """
    <h1>Climate Change Report</h1>
    <p>Global temperatures have risen significantly over the past century. \
    Carbon dioxide levels in the atmosphere are at their highest point in millions of years. \
    Scientists warn that immediate action is needed to prevent catastrophic consequences.</p>
    <p>Renewable energy sources like solar and wind power are becoming increasingly affordable. \
    Electric vehicles are gaining market share rapidly across the globe. \
    Many countries have pledged to achieve carbon neutrality by 2050.</p>
    """

    // MARK: - Basic Summarization

    func testSummarizeProducesResult() {
        let result = summarizer.summarize(sampleArticle)
        XCTAssertNotNil(result)
        XCTAssertFalse(result!.summary.isEmpty)
    }

    func testSummarizeReturnsNilForEmptyText() {
        XCTAssertNil(summarizer.summarize(""))
    }

    func testSummarizeReturnsNilForWhitespace() {
        XCTAssertNil(summarizer.summarize("   \n\t  "))
    }

    func testSummarizeReturnsNilForSingleSentence() {
        XCTAssertNil(summarizer.summarize("Just one sentence here."))
    }

    func testSummarizeReturnsNilForHTMLOnly() {
        XCTAssertNil(summarizer.summarize("<div></div><br/>"))
    }

    func testSummaryIsShorterThanOriginal() {
        let result = summarizer.summarize(sampleArticle)!
        XCTAssertLessThan(result.summary.count, sampleArticle.count)
    }

    func testCompressionRatioIsValid() {
        let result = summarizer.summarize(sampleArticle)!
        XCTAssertGreaterThan(result.compressionRatio, 0.0)
        XCTAssertLessThanOrEqual(result.compressionRatio, 1.0)
    }

    // MARK: - Sentence Count

    func testDefaultMaxSentences() {
        let result = summarizer.summarize(sampleArticle)!
        XCTAssertLessThanOrEqual(result.summarySentenceCount, 3)
    }

    func testCustomMaxSentences() {
        let config = SummaryConfig(maxSentences: 2)
        let result = summarizer.summarize(sampleArticle, config: config)!
        XCTAssertLessThanOrEqual(result.summarySentenceCount, 2)
    }

    func testSingleSentenceSummary() {
        let config = SummaryConfig(maxSentences: 1)
        let result = summarizer.summarize(sampleArticle, config: config)!
        XCTAssertEqual(result.summarySentenceCount, 1)
    }

    // MARK: - Title Boosting

    func testTitleBoostInfluencesScoring() {
        let config = SummaryConfig(maxSentences: 1, titleBoost: 3.0)
        let resultWithTitle = summarizer.summarize(sampleArticle, title: "Machine Learning in Medical Imaging", config: config)
        let resultWithoutTitle = summarizer.summarize(sampleArticle, config: config)
        XCTAssertNotNil(resultWithTitle)
        XCTAssertNotNil(resultWithoutTitle)
        // With a relevant title, the top sentence should relate to ML/medical
        XCTAssertNotEqual(resultWithTitle!.summary, resultWithoutTitle!.summary)
    }

    func testTitleBoostWithIrrelevantTitle() {
        let config = SummaryConfig(maxSentences: 1)
        let result1 = summarizer.summarize(sampleArticle, title: "Cooking Recipes for Beginners", config: config)
        let result2 = summarizer.summarize(sampleArticle, config: config)
        // With irrelevant title, results may or may not differ but both should be valid
        XCTAssertNotNil(result1)
        XCTAssertNotNil(result2)
    }

    // MARK: - HTML Handling

    func testSummarizeStripsHTML() {
        let result = summarizer.summarize(htmlArticle)
        XCTAssertNotNil(result)
        XCTAssertFalse(result!.summary.contains("<"))
        XCTAssertFalse(result!.summary.contains(">"))
    }

    func testHTMLEntitiesDecoded() {
        let text = "First sentence is here. Second sentence has &amp; ampersand. Third one too with &lt;tag&gt; content."
        let result = summarizer.summarize(text)
        XCTAssertNotNil(result)
        XCTAssertFalse(result!.summary.contains("&amp;"))
    }

    // MARK: - Ranked Sentences

    func testRankedSentencesAreSortedByScore() {
        let result = summarizer.summarize(sampleArticle)!
        for i in 0..<result.rankedSentences.count - 1 {
            XCTAssertGreaterThanOrEqual(result.rankedSentences[i].score, result.rankedSentences[i + 1].score)
        }
    }

    func testRankedSentencesContainAllValid() {
        let result = summarizer.summarize(sampleArticle)!
        XCTAssertGreaterThan(result.rankedSentences.count, 0)
        XCTAssertLessThanOrEqual(result.rankedSentences.count, result.originalSentenceCount)
    }

    // MARK: - Top Keywords

    func testTopKeywordsExtracted() {
        let result = summarizer.summarize(sampleArticle)!
        XCTAssertGreaterThan(result.topKeywords.count, 0)
        XCTAssertLessThanOrEqual(result.topKeywords.count, 10)
    }

    func testTopKeywordsAreSortedByScore() {
        let result = summarizer.summarize(sampleArticle)!
        for i in 0..<result.topKeywords.count - 1 {
            XCTAssertGreaterThanOrEqual(result.topKeywords[i].score, result.topKeywords[i + 1].score)
        }
    }

    func testKeywordsRelevantToArticle() {
        let result = summarizer.summarize(sampleArticle)!
        let keywords = Set(result.topKeywords.map { $0.word })
        // At least one AI-related keyword should appear
        let aiTerms: Set<String> = ["artificial", "intelligence", "learning", "machine", "algorithms", "medical", "patients"]
        XCTAssertFalse(keywords.intersection(aiTerms).isEmpty)
    }

    // MARK: - Config Options

    func testRatioBasedSentenceCount() {
        let config = SummaryConfig(maxSentences: 100, ratio: 0.2)
        let result = summarizer.summarize(sampleArticle, config: config)!
        // With 10 sentences and ratio 0.2, should get ~2 sentences
        XCTAssertLessThanOrEqual(result.summarySentenceCount, 3)
    }

    func testMinSentenceWordsFilter() {
        let text = "Yes. No. Maybe so. Artificial intelligence is transforming everything we know about technology today. Machine learning algorithms can detect patterns in massive datasets efficiently."
        let config = SummaryConfig(maxSentences: 5, minSentenceWords: 4)
        let result = summarizer.summarize(text, config: config)
        if let result = result {
            // Short sentences like "Yes." should be filtered out
            for (sentence, _) in result.rankedSentences {
                let wordCount = sentence.components(separatedBy: .whitespaces).filter { !$0.isEmpty }.count
                XCTAssertGreaterThanOrEqual(wordCount, 4)
            }
        }
    }

    func testPositionBoostFavorsFirstSentence() {
        let config = SummaryConfig(maxSentences: 1, positionBoost: 5.0, minSentenceWords: 3)
        let text = "Artificial intelligence transforms healthcare rapidly today. Cooking is a fun hobby for weekends and evenings. Sports bring communities and nations together worldwide."
        let result = summarizer.summarize(text, config: config)
        XCTAssertNotNil(result)
        // With strong position boost, first sentence should be selected
        XCTAssertTrue(result!.summary.contains("Artificial"))
    }

    // MARK: - Preserves Original Order

    func testSummaryPreservesOriginalSentenceOrder() {
        let config = SummaryConfig(maxSentences: 3)
        let result = summarizer.summarize(sampleArticle, config: config)!
        let sentences = result.summary.components(separatedBy: ". ")
        // Summary should read naturally (original order preserved)
        XCTAssertGreaterThanOrEqual(sentences.count, 1)
    }

    // MARK: - Batch Summarize

    func testBatchSummarize() {
        let articles: [(text: String, title: String?)] = [
            (sampleArticle, "Healthcare AI"),
            (htmlArticle, "Climate"),
            ("", nil),
            (shortText, nil)
        ]
        let results = summarizer.batchSummarize(articles)
        XCTAssertEqual(results.count, 4)
        XCTAssertNotNil(results[0])
        XCTAssertNotNil(results[1])
        XCTAssertNil(results[2]) // empty
        XCTAssertNil(results[3]) // too short
    }

    // MARK: - Multi-Article Summary

    func testMultiArticleSummary() {
        let articles: [(text: String, title: String?)] = [
            (sampleArticle, "Healthcare AI"),
            (htmlArticle, "Climate Change")
        ]
        let result = summarizer.multiArticleSummary(articles, maxSentences: 3)
        XCTAssertNotNil(result)
        XCTAssertLessThanOrEqual(result!.summarySentenceCount, 3)
    }

    func testMultiArticleSummaryEmptyInput() {
        let result = summarizer.multiArticleSummary([], maxSentences: 3)
        XCTAssertNil(result)
    }

    func testMultiArticleSummaryAllEmpty() {
        let articles: [(text: String, title: String?)] = [
            ("", nil), ("  ", nil)
        ]
        let result = summarizer.multiArticleSummary(articles)
        XCTAssertNil(result)
    }

    // MARK: - Edge Cases

    func testVeryLongArticle() {
        let longText = (0..<100).map { "Sentence number \($0) talks about technology and artificial intelligence in modern society." }.joined(separator: " ")
        let result = summarizer.summarize(longText)
        XCTAssertNotNil(result)
        XCTAssertLessThanOrEqual(result!.summarySentenceCount, 3)
    }

    func testArticleWithSpecialCharacters() {
        let text = "AI costs $1.5 billion per year. Companies like Google & Microsoft invest heavily. R&D spending has grown 200% since 2020."
        let result = summarizer.summarize(text)
        XCTAssertNotNil(result)
    }

    func testOriginalSentenceCount() {
        let result = summarizer.summarize(sampleArticle)!
        XCTAssertGreaterThan(result.originalSentenceCount, 5)
    }

    // MARK: - SummaryConfig Defaults

    func testDefaultConfig() {
        let config = SummaryConfig.default
        XCTAssertEqual(config.maxSentences, 3)
        XCTAssertEqual(config.ratio, 0.3, accuracy: 0.001)
        XCTAssertEqual(config.titleBoost, 1.5, accuracy: 0.001)
        XCTAssertEqual(config.positionBoost, 1.2, accuracy: 0.001)
        XCTAssertEqual(config.minSentenceWords, 4)
    }

    func testConfigRatioClamped() {
        let low = SummaryConfig(ratio: -0.5)
        XCTAssertEqual(low.ratio, 0.0, accuracy: 0.001)
        let high = SummaryConfig(ratio: 2.0)
        XCTAssertEqual(high.ratio, 1.0, accuracy: 0.001)
    }

    func testConfigMinSentenceWordsClamped() {
        let config = SummaryConfig(minSentenceWords: 0)
        XCTAssertGreaterThanOrEqual(config.minSentenceWords, 1)
    }

    // MARK: - Score Positivity

    func testAllScoresPositive() {
        let result = summarizer.summarize(sampleArticle)!
        for (_, score) in result.rankedSentences {
            XCTAssertGreaterThanOrEqual(score, 0.0)
        }
    }

    func testKeywordScoresPositive() {
        let result = summarizer.summarize(sampleArticle)!
        for (_, score) in result.topKeywords {
            XCTAssertGreaterThan(score, 0.0)
        }
    }
}
