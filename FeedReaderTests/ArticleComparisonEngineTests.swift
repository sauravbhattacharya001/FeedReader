//
//  ArticleComparisonEngineTests.swift
//  FeedReaderTests
//
//  Tests for ArticleComparisonEngine — side-by-side article comparison.
//

import XCTest
@testable import FeedReader

class ArticleComparisonEngineTests: XCTestCase {

    var engine: ArticleComparisonEngine!

    override func setUp() {
        super.setUp()
        engine = ArticleComparisonEngine()
    }

    override func tearDown() {
        engine = nil
        super.tearDown()
    }

    // MARK: - Helpers

    private func makeStory(
        title: String,
        body: String,
        link: String = "https://example.com/article",
        feedName: String = "TestFeed"
    ) -> Story {
        let story = Story(title: title, photo: nil, description: body, link: link)!
        story.sourceFeedName = feedName
        return story
    }

    private let longBodyA = """
    Artificial intelligence researchers have made significant breakthroughs in natural language \
    processing this year. The latest large language models demonstrate unprecedented capabilities \
    in understanding context, generating coherent text, and even reasoning about complex problems. \
    These advances have profound implications for education, healthcare, and scientific research. \
    Companies across Silicon Valley are racing to deploy these technologies in consumer products, \
    while ethicists warn about potential risks including bias, misinformation, and job displacement. \
    The debate between innovation speed and safety continues to intensify as governments worldwide \
    consider regulatory frameworks for artificial intelligence development and deployment.
    """

    private let longBodyB = """
    The artificial intelligence industry is experiencing rapid growth with billions of dollars in \
    new investment. Major technology companies have announced competing products that leverage \
    advanced machine learning algorithms. While the commercial potential is enormous, several \
    prominent researchers have raised concerns about the environmental impact of training massive \
    neural networks, which require enormous computational resources and energy consumption. \
    Academic institutions are struggling to retain talent as private companies offer significantly \
    higher compensation packages. International cooperation on artificial intelligence governance \
    remains fragmented despite several high-profile summits.
    """

    // MARK: - Basic Comparison

    func testBasicComparison() {
        let storyA = makeStory(title: "AI Breakthroughs in NLP", body: longBodyA, feedName: "TechNews")
        let storyB = makeStory(title: "AI Industry Growth", body: longBodyB, feedName: "BusinessWire")

        let result = engine.compare(storyA, storyB)
        XCTAssertNotNil(result)

        if let r = result {
            XCTAssertEqual(r.titleA, "AI Breakthroughs in NLP")
            XCTAssertEqual(r.titleB, "AI Industry Growth")
            XCTAssertEqual(r.sourceA, "TechNews")
            XCTAssertEqual(r.sourceB, "BusinessWire")
            XCTAssertFalse(r.dimensions.isEmpty)
            XCTAssertGreaterThanOrEqual(r.similarityScore, 0.0)
            XCTAssertLessThanOrEqual(r.similarityScore, 1.0)
            XCTAssertFalse(r.summary.isEmpty)
        }
    }

    // MARK: - Too Short Articles

    func testRejectsShortArticleA() {
        let short = makeStory(title: "Short", body: "Too short.")
        let long = makeStory(title: "Long", body: longBodyA)
        XCTAssertNil(engine.compare(short, long))
    }

    func testRejectsShortArticleB() {
        let long = makeStory(title: "Long", body: longBodyA)
        let short = makeStory(title: "Short", body: "Tiny text.")
        XCTAssertNil(engine.compare(long, short))
    }

    func testRejectsBothShort() {
        let a = makeStory(title: "A", body: "Brief.")
        let b = makeStory(title: "B", body: "Also brief.")
        XCTAssertNil(engine.compare(a, b))
    }

    // MARK: - Dimensions Present

    func testDimensionsIncluded() {
        let storyA = makeStory(title: "Article A", body: longBodyA)
        let storyB = makeStory(title: "Article B", body: longBodyB)

        let result = engine.compare(storyA, storyB)!
        let dimNames = Set(result.dimensions.map(\.name))

        XCTAssertTrue(dimNames.contains("Depth (Word Count)"))
        XCTAssertTrue(dimNames.contains("Readability"))
        XCTAssertTrue(dimNames.contains("Sentence Length"))
        XCTAssertTrue(dimNames.contains("Sentiment / Tone"))
        XCTAssertTrue(dimNames.contains("Emotional Tone"))
        XCTAssertTrue(dimNames.contains("Reading Time"))
        XCTAssertTrue(dimNames.contains("Topic Coverage"))
    }

    func testDimensionValuesNotEmpty() {
        let storyA = makeStory(title: "A", body: longBodyA)
        let storyB = makeStory(title: "B", body: longBodyB)

        let result = engine.compare(storyA, storyB)!
        for dim in result.dimensions {
            XCTAssertFalse(dim.valueA.isEmpty, "Dimension \(dim.name) valueA should not be empty")
            XCTAssertFalse(dim.valueB.isEmpty, "Dimension \(dim.name) valueB should not be empty")
            XCTAssertFalse(dim.explanation.isEmpty, "Dimension \(dim.name) explanation should not be empty")
        }
    }

    // MARK: - Keyword Analysis

    func testKeywordAnalysisPresent() {
        let storyA = makeStory(title: "A", body: longBodyA)
        let storyB = makeStory(title: "B", body: longBodyB)

        let result = engine.compare(storyA, storyB)!
        let kw = result.keywordAnalysis

        XCTAssertGreaterThanOrEqual(kw.overlapScore, 0.0)
        XCTAssertLessThanOrEqual(kw.overlapScore, 1.0)
        XCTAssertGreaterThan(kw.totalUniqueKeywords, 0)
    }

    func testSharedKeywordsExist() {
        let storyA = makeStory(title: "A", body: longBodyA)
        let storyB = makeStory(title: "B", body: longBodyB)

        let result = engine.compare(storyA, storyB)!
        // Both talk about AI — should have shared keywords
        XCTAssertFalse(result.keywordAnalysis.shared.isEmpty,
            "Articles about similar topics should have shared keywords")
    }

    func testUniqueKeywordsExist() {
        let storyA = makeStory(title: "A", body: longBodyA)
        let storyB = makeStory(title: "B", body: longBodyB)

        let result = engine.compare(storyA, storyB)!
        // Each article has unique angles
        XCTAssertFalse(result.keywordAnalysis.uniqueToA.isEmpty,
            "Articles should have some unique keywords")
    }

    // MARK: - Verdict

    func testVerdictIsValid() {
        let storyA = makeStory(title: "A", body: longBodyA)
        let storyB = makeStory(title: "B", body: longBodyB)

        let result = engine.compare(storyA, storyB)!
        let validVerdicts: [ComparisonVerdict] = [.articleABetter, .articleBBetter, .roughlyEqual, .complementary]
        XCTAssertTrue(validVerdicts.contains(result.verdict))
    }

    func testVerdictEmoji() {
        XCTAssertFalse(ComparisonVerdict.articleABetter.emoji.isEmpty)
        XCTAssertFalse(ComparisonVerdict.articleBBetter.emoji.isEmpty)
        XCTAssertFalse(ComparisonVerdict.roughlyEqual.emoji.isEmpty)
        XCTAssertFalse(ComparisonVerdict.complementary.emoji.isEmpty)
    }

    // MARK: - Identical Articles

    func testIdenticalArticles() {
        let storyA = makeStory(title: "Same Title", body: longBodyA, feedName: "Feed1")
        let storyB = makeStory(title: "Same Title", body: longBodyA, feedName: "Feed2")

        let result = engine.compare(storyA, storyB)!
        // Identical content should have high similarity
        XCTAssertGreaterThan(result.similarityScore, 0.5)
        // Keyword analysis should show high overlap
        XCTAssertGreaterThan(result.keywordAnalysis.overlapScore, 0.8)
        // Verdict should be roughly equal
        XCTAssertEqual(result.verdict, .roughlyEqual)
    }

    // MARK: - Quick Similarity

    func testQuickSimilarity() {
        let storyA = makeStory(title: "A", body: longBodyA)
        let storyB = makeStory(title: "B", body: longBodyB)

        let sim = engine.quickSimilarity(storyA, storyB)
        XCTAssertGreaterThanOrEqual(sim, 0.0)
        XCTAssertLessThanOrEqual(sim, 1.0)
    }

    func testQuickSimilarityIdentical() {
        let storyA = makeStory(title: "A", body: longBodyA)
        let storyB = makeStory(title: "B", body: longBodyA)

        let sim = engine.quickSimilarity(storyA, storyB)
        XCTAssertEqual(sim, 1.0, accuracy: 0.001, "Identical bodies should have 1.0 similarity")
    }

    func testQuickSimilarityDifferent() {
        let cooking = makeStory(title: "A", body: """
        The best pasta recipes start with high quality ingredients including semolina flour, \
        fresh eggs from local farms, and extra virgin olive oil from Italian producers. Rolling \
        the dough requires patience and proper technique. Let the pasta rest for thirty minutes \
        before cutting into your desired shape whether fettuccine or pappardelle.
        """)
        let physics = makeStory(title: "B", body: """
        Quantum mechanics describes the behavior of particles at the subatomic scale where \
        classical physics breaks down completely. The wave function collapses upon measurement, \
        producing probabilistic outcomes that Einstein famously objected to. Modern experiments \
        with entangled photons have confirmed these predictions with extraordinary precision.
        """)

        let sim = engine.quickSimilarity(cooking, physics)
        XCTAssertLessThan(sim, 0.2, "Unrelated articles should have low similarity")
    }

    // MARK: - Report Formatting

    func testFormatReport() {
        let storyA = makeStory(title: "AI Progress", body: longBodyA, feedName: "TechDaily")
        let storyB = makeStory(title: "AI Industry", body: longBodyB, feedName: "BizNews")

        let result = engine.compare(storyA, storyB)!
        let report = engine.formatReport(result)

        XCTAssertTrue(report.contains("Article Comparison Report"))
        XCTAssertTrue(report.contains("AI Progress"))
        XCTAssertTrue(report.contains("AI Industry"))
        XCTAssertTrue(report.contains("TechDaily"))
        XCTAssertTrue(report.contains("BizNews"))
        XCTAssertTrue(report.contains("Similarity:"))
        XCTAssertTrue(report.contains("Verdict:"))
        XCTAssertTrue(report.contains("Keyword Analysis"))
    }

    // MARK: - JSON Formatting

    func testFormatJSON() {
        let storyA = makeStory(title: "A", body: longBodyA)
        let storyB = makeStory(title: "B", body: longBodyB)

        let result = engine.compare(storyA, storyB)!
        let json = engine.formatJSON(result)

        XCTAssertNotNil(json)
        if let jsonStr = json {
            XCTAssertTrue(jsonStr.contains("\"titleA\""))
            XCTAssertTrue(jsonStr.contains("\"titleB\""))
            XCTAssertTrue(jsonStr.contains("\"verdict\""))
            XCTAssertTrue(jsonStr.contains("\"dimensions\""))
            XCTAssertTrue(jsonStr.contains("\"keywords\""))
            XCTAssertTrue(jsonStr.contains("\"similarityScore\""))

            // Should be valid JSON
            let data = jsonStr.data(using: .utf8)!
            let parsed = try? JSONSerialization.jsonObject(with: data)
            XCTAssertNotNil(parsed, "JSON output should be valid JSON")
        }
    }

    // MARK: - Source Feed Names

    func testMissingSourceFeedName() {
        let storyA = Story(title: "No Feed", photo: nil, description: longBodyA, link: "https://a.com/1")!
        // Don't set sourceFeedName
        let storyB = makeStory(title: "Has Feed", body: longBodyB, feedName: "KnownFeed")

        let result = engine.compare(storyA, storyB)
        XCTAssertNotNil(result)
        XCTAssertEqual(result?.sourceA, "Unknown")
        XCTAssertEqual(result?.sourceB, "KnownFeed")
    }

    // MARK: - ComparisonDimension Equatable

    func testDimensionEquality() {
        let dim1 = ComparisonDimension(name: "Test", valueA: "1", valueB: "2",
                                        winner: .articleA, explanation: "A wins")
        let dim2 = ComparisonDimension(name: "Test", valueA: "1", valueB: "2",
                                        winner: .articleA, explanation: "A wins")
        XCTAssertEqual(dim1, dim2)
    }

    // MARK: - KeywordAnalysis Equatable

    func testKeywordAnalysisEquality() {
        let kw1 = KeywordAnalysis(shared: ["a"], uniqueToA: ["b"], uniqueToB: ["c"],
                                   overlapScore: 0.5, totalUniqueKeywords: 3)
        let kw2 = KeywordAnalysis(shared: ["a"], uniqueToA: ["b"], uniqueToB: ["c"],
                                   overlapScore: 0.5, totalUniqueKeywords: 3)
        XCTAssertEqual(kw1, kw2)
    }

    // MARK: - ComparisonWinner

    func testComparisonWinnerRawValues() {
        XCTAssertEqual(ComparisonWinner.articleA.rawValue, "A")
        XCTAssertEqual(ComparisonWinner.articleB.rawValue, "B")
    }

    // MARK: - Notification

    func testComparisonPostsNotification() {
        let expectation = self.expectation(forNotification: .articleComparisonDidComplete, object: nil)

        let storyA = makeStory(title: "A", body: longBodyA)
        let storyB = makeStory(title: "B", body: longBodyB)
        _ = engine.compare(storyA, storyB)

        wait(for: [expectation], timeout: 1.0)
    }

    // MARK: - Symmetric Comparison

    func testComparisonSymmetry() {
        let storyA = makeStory(title: "Article Alpha", body: longBodyA, feedName: "FeedA")
        let storyB = makeStory(title: "Article Beta", body: longBodyB, feedName: "FeedB")

        let resultAB = engine.compare(storyA, storyB)!
        let resultBA = engine.compare(storyB, storyA)!

        // Similarity should be the same regardless of order
        XCTAssertEqual(resultAB.similarityScore, resultBA.similarityScore, accuracy: 0.01,
            "Similarity should be symmetric")

        // Keyword overlap should be the same
        XCTAssertEqual(resultAB.keywordAnalysis.overlapScore, resultBA.keywordAnalysis.overlapScore, accuracy: 0.01)
        XCTAssertEqual(resultAB.keywordAnalysis.shared.count, resultBA.keywordAnalysis.shared.count)
    }

    // MARK: - Timestamp

    func testComparedAtTimestamp() {
        let before = Date()
        let storyA = makeStory(title: "A", body: longBodyA)
        let storyB = makeStory(title: "B", body: longBodyB)
        let result = engine.compare(storyA, storyB)!
        let after = Date()

        XCTAssertGreaterThanOrEqual(result.comparedAt, before)
        XCTAssertLessThanOrEqual(result.comparedAt, after)
    }

    // MARK: - Very Different Articles

    func testVeryDifferentArticles() {
        let cooking = makeStory(title: "Pasta Making Guide", body: """
        Making fresh pasta at home requires simple ingredients but careful technique. Start with \
        two cups of semolina flour and three large eggs. Create a well in the center of the flour \
        and crack the eggs into it. Use a fork to gradually incorporate the flour into the eggs \
        until a shaggy dough forms. Knead for ten minutes until smooth and elastic. Cover with \
        plastic wrap and let rest for thirty minutes at room temperature before rolling.
        """, feedName: "FoodBlog")

        let quantum = makeStory(title: "Quantum Computing Advances", body: """
        Researchers at leading universities have demonstrated quantum error correction operating \
        below the fault tolerance threshold for the first time. The experiment used topological \
        qubits arranged in a surface code lattice with ancilla measurements for syndrome extraction. \
        This milestone suggests that large-scale quantum computers capable of breaking current \
        encryption standards may arrive sooner than previously estimated by the cryptography community.
        """, feedName: "ScienceDaily")

        let result = engine.compare(cooking, quantum)!
        XCTAssertLessThan(result.similarityScore, 0.3,
            "Completely different topics should have low similarity")
    }
}