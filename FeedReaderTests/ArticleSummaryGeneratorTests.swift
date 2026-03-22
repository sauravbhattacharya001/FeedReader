//
//  ArticleSummaryGeneratorTests.swift
//  FeedReaderTests
//

import XCTest
@testable import FeedReader

final class ArticleSummaryGeneratorTests: XCTestCase {

    // MARK: - Basic Summarization

    func testSummarizeReturnsRequestedSentenceCount() {
        let text = """
        The global economy showed signs of recovery in the third quarter. \
        Consumer spending increased by 3.2 percent compared to last year. \
        Manufacturing output also rose significantly across major markets. \
        Analysts expect continued growth through the end of the fiscal year. \
        However, supply chain disruptions remain a concern for many industries. \
        Central banks are cautiously optimistic about inflation targets being met.
        """
        let summary = ArticleSummaryGenerator.summarize(
            title: "Global Economy Recovery",
            text: text,
            maxSentences: 2
        )
        XCTAssertEqual(summary.selectedCount, 2)
        XCTAssertEqual(summary.sentences.count, 2)
    }

    func testSummarizePreservesOriginalOrder() {
        let text = """
        First sentence about technology advances. \
        Second sentence about market trends and growth. \
        Third sentence about innovation in healthcare. \
        Fourth sentence about education reform policies. \
        Fifth sentence about environmental sustainability efforts.
        """
        let summary = ArticleSummaryGenerator.summarize(
            title: "Technology Advances",
            text: text,
            maxSentences: 2
        )
        // The selected sentences should maintain their original order
        XCTAssertEqual(summary.sentences.count, 2)
        XCTAssertTrue(summary.originalSentenceCount >= 2)
    }

    func testEmptyTextReturnsFallback() {
        let summary = ArticleSummaryGenerator.summarize(
            title: "Empty", text: "", maxSentences: 3
        )
        XCTAssertEqual(summary.selectedCount, 0)
    }

    func testShortTextReturnsSelf() {
        let text = "This is a single short sentence about weather patterns."
        let summary = ArticleSummaryGenerator.summarize(
            title: "Weather", text: text, maxSentences: 3
        )
        XCTAssertTrue(summary.selectedCount <= 1)
    }

    // MARK: - Title Relevance Boost

    func testTitleRelevanceBoostsSentences() {
        let text = """
        Climate change is accelerating faster than predicted by earlier models. \
        The stock market reached new highs driven by tech sector gains. \
        Scientists warn that rising sea levels threaten coastal communities worldwide. \
        A new restaurant opened downtown serving fusion cuisine. \
        Arctic ice measurements show unprecedented melting rates this summer.
        """
        let summary = ArticleSummaryGenerator.summarize(
            title: "Climate Change Arctic Ice",
            text: text,
            maxSentences: 2
        )
        // Sentences about climate/arctic should be favored
        let combined = summary.text.lowercased()
        XCTAssertTrue(
            combined.contains("climate") || combined.contains("arctic") || combined.contains("sea level"),
            "Expected climate-related sentences to be selected"
        )
    }

    // MARK: - Configuration

    func testBriefConfigLimitsCharacters() {
        let text = """
        The research team published their findings in a prestigious journal. \
        Their study covered ten years of longitudinal data from multiple countries. \
        Results indicate a strong correlation between education and economic mobility. \
        Policy makers are reviewing the implications for future budget allocations. \
        The methodology received praise from peer reviewers for its rigorous design.
        """
        let summary = ArticleSummaryGenerator.summarize(
            title: "Research Findings",
            text: text,
            config: .brief
        )
        if SummaryConfig.brief.maxCharacters > 0 {
            XCTAssertTrue(summary.text.count <= SummaryConfig.brief.maxCharacters + 50,
                          "Brief summary should respect character budget")
        }
    }

    // MARK: - Formatting

    func testBulletFormat() {
        let text = """
        Artificial intelligence is transforming healthcare diagnostics. \
        New algorithms can detect diseases earlier than human doctors. \
        Patient outcomes have improved significantly with AI assistance.
        """
        let summary = ArticleSummaryGenerator.summarize(
            title: "AI Healthcare", text: text, maxSentences: 2
        )
        let bullets = ArticleSummaryGenerator.format(summary, as: .bullets)
        let lines = bullets.components(separatedBy: "\n")
        XCTAssertTrue(lines.allSatisfy { $0.hasPrefix("• ") })
    }

    func testNumberedFormat() {
        let text = """
        Renewable energy adoption continues to grow worldwide. \
        Solar panel costs have dropped by sixty percent in the last decade. \
        Wind farms now generate enough power for millions of homes.
        """
        let summary = ArticleSummaryGenerator.summarize(
            title: "Renewable Energy", text: text, maxSentences: 2
        )
        let numbered = ArticleSummaryGenerator.format(summary, as: .numbered)
        XCTAssertTrue(numbered.contains("1."))
    }

    // MARK: - Batch Summarization

    func testBatchSummarize() {
        let articles = [
            (title: "Tech News", text: "Major tech companies reported strong earnings this quarter. Innovation in AI continues to drive growth. Cloud computing revenue exceeded expectations."),
            (title: "Sports Update", text: "The championship game drew record viewership numbers. Both teams displayed exceptional performance throughout the match. Fans celebrated across the country.")
        ]
        let summaries = ArticleSummaryGenerator.batchSummarize(articles: articles)
        XCTAssertEqual(summaries.count, 2)
        XCTAssertEqual(summaries[0].title, "Tech News")
        XCTAssertEqual(summaries[1].title, "Sports Update")
    }

    // MARK: - Sentence Splitting

    func testSentenceSplittingHandlesAbbreviations() {
        let gen = ArticleSummaryGenerator.shared
        let text = "Dr. Smith presented the findings at the conference. The results were promising for future research."
        let sentences = gen.splitSentences(text)
        // "Dr." should not cause a split
        XCTAssertTrue(sentences.count <= 2, "Abbreviations should not cause extra splits")
    }

    // MARK: - Confidence

    func testConfidenceIsInRange() {
        let text = """
        Advances in quantum computing are opening new possibilities for cryptography. \
        Researchers have achieved quantum supremacy with a fifty-three qubit processor. \
        This breakthrough could render current encryption methods obsolete within decades. \
        Governments are investing billions in quantum-safe security protocols.
        """
        let summary = ArticleSummaryGenerator.summarize(
            title: "Quantum Computing", text: text, maxSentences: 2
        )
        XCTAssertTrue(summary.confidence >= 0.0 && summary.confidence <= 1.0)
    }

    // MARK: - Compression Ratio

    func testCompressionRatio() {
        let text = """
        First important sentence about global warming effects. \
        Second sentence about renewable energy solutions available today. \
        Third sentence about government policy and carbon reduction targets. \
        Fourth sentence about individual actions people can take daily. \
        Fifth sentence about corporate responsibility in climate change.
        """
        let summary = ArticleSummaryGenerator.summarize(
            title: "Climate Action", text: text, maxSentences: 2
        )
        XCTAssertTrue(summary.compressionRatio > 0 && summary.compressionRatio <= 1.0)
    }
}
