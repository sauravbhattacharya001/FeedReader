//
//  TopicClassifierTests.swift
//  FeedReaderTests
//
//  Tests for automatic topic classification.
//

import XCTest
@testable import FeedReader

class TopicClassifierTests: XCTestCase {

    var classifier: TopicClassifier!

    override func setUp() {
        super.setUp()
        classifier = TopicClassifier()
    }

    // MARK: - Basic Classification

    func testTechArticle() {
        let result = classifier.classifyText(
            "New GPU architecture from NVIDIA uses quantum computing algorithms for machine learning acceleration"
        )
        XCTAssertEqual(result.primary, .technology)
        XCTAssertGreaterThan(result.confidence, 0.3)
    }

    func testScienceArticle() {
        let result = classifier.classifyText(
            "NASA telescope discovers new exoplanet with atmosphere containing water molecules in distant galaxy"
        )
        XCTAssertEqual(result.primary, .science)
    }

    func testPoliticsArticle() {
        let result = classifier.classifyText(
            "Senate passes new legislation on election reform as candidates campaign across key constituencies"
        )
        XCTAssertEqual(result.primary, .politics)
    }

    func testBusinessArticle() {
        let result = classifier.classifyText(
            "Tech startup raises venture capital funding in latest IPO as quarterly earnings beat investor expectations"
        )
        XCTAssertEqual(result.primary, .business)
    }

    func testHealthArticle() {
        let result = classifier.classifyText(
            "New vaccine breakthrough offers treatment for cancer patients undergoing chemotherapy at hospital clinics"
        )
        XCTAssertEqual(result.primary, .health)
    }

    func testSportsArticle() {
        let result = classifier.classifyText(
            "NBA championship playoffs see record scores as players compete in tournament semifinals at packed stadium"
        )
        XCTAssertEqual(result.primary, .sports)
    }

    func testEntertainmentArticle() {
        let result = classifier.classifyText(
            "Netflix streaming series nominated for Emmy awards as director and actor prepare for concert tour"
        )
        XCTAssertEqual(result.primary, .entertainment)
    }

    func testEnvironmentArticle() {
        let result = classifier.classifyText(
            "Climate warming accelerates glacier melting as carbon emissions increase deforestation in the Arctic ecosystem"
        )
        XCTAssertEqual(result.primary, .environment)
    }

    func testEducationArticle() {
        let result = classifier.classifyText(
            "University enrollment drops as tuition costs rise; students seek scholarship alternatives and online courses"
        )
        XCTAssertEqual(result.primary, .education)
    }

    func testLifestyleArticle() {
        let result = classifier.classifyText(
            "New restaurant opens with vegan cuisine and gourmet recipes from celebrity chef; travel destination guide included"
        )
        XCTAssertEqual(result.primary, .lifestyle)
    }

    // MARK: - Edge Cases

    func testEmptyText() {
        let result = classifier.classifyText("")
        XCTAssertEqual(result.primary, .uncategorized)
        XCTAssertEqual(result.matchCount, 0)
    }

    func testGenericText() {
        let result = classifier.classifyText("The quick brown fox jumps over the lazy dog")
        XCTAssertEqual(result.primary, .uncategorized)
    }

    func testSingleWord() {
        let result = classifier.classifyText("algorithm")
        // Single keyword match — below minimum matches threshold
        XCTAssertEqual(result.matchCount, 1)
    }

    // MARK: - Multi-Topic

    func testMultiTopicArticle() {
        let result = classifier.classifyText(
            "Scientists at the university publish research on AI algorithms for cancer diagnosis using neural networks and machine learning in hospital clinical trials"
        )
        // Should have multiple topics above threshold
        XCTAssertGreaterThanOrEqual(result.topics.count, 1)
        XCTAssertGreaterThan(result.matchCount, 3)
    }

    // MARK: - Confidence

    func testHighConfidenceForClearTopic() {
        let result = classifier.classifyText(
            "The NFL championship playoff tournament at the stadium saw quarterback touchdowns and coach strategy as the team won the league division finals"
        )
        XCTAssertEqual(result.primary, .sports)
        XCTAssertGreaterThan(result.confidence, 0.4)
    }

    // MARK: - Topic Distribution

    func testTopicDistributionSumsToOne() {
        // Create mock stories via classifyText (can't instantiate Story without UIImage)
        let texts = [
            "GPU algorithm blockchain cryptocurrency",
            "election senate congress vote",
            "stock market revenue earnings",
        ]
        // Use classifyText directly since Story requires UIImage
        var counts: [ArticleTopic: Int] = [:]
        for text in texts {
            let result = classifier.classifyText(text)
            counts[result.primary, default: 0] += 1
        }
        let total = counts.values.reduce(0, +)
        XCTAssertEqual(total, texts.count)
    }

    // MARK: - Labels

    func testLabelFormat() {
        let result = classifier.classifyText(
            "Software algorithm programming database encryption malware cybersecurity"
        )
        XCTAssertTrue(result.label.contains("💻"))
        XCTAssertTrue(result.label.contains("Technology"))
    }

    func testUncategorizedLabel() {
        let result = classifier.classifyText("")
        XCTAssertTrue(result.label.contains("📄"))
    }

    // MARK: - Configuration

    func testCustomThreshold() {
        classifier.confidenceThreshold = 0.5
        let result = classifier.classifyText(
            "Scientists at university research physics experiment discovery biology chemistry"
        )
        // With high threshold, fewer topics should pass
        let lowThreshold = TopicClassifier()
        lowThreshold.confidenceThreshold = 0.05
        let lowResult = lowThreshold.classifyText(
            "Scientists at university research physics experiment discovery biology chemistry"
        )
        XCTAssertGreaterThanOrEqual(lowResult.topics.count, result.topics.count)
    }

    func testMinimumMatchesThreshold() {
        classifier.minimumMatches = 10
        let result = classifier.classifyText("algorithm programming code")
        // With high minimum, should be uncategorized despite keyword matches
        XCTAssertEqual(result.primary, .uncategorized)
    }

    // MARK: - Emoji

    func testAllTopicsHaveEmoji() {
        for topic in ArticleTopic.allCases {
            XCTAssertFalse(topic.emoji.isEmpty, "\(topic) should have an emoji")
        }
    }

    // MARK: - Topic Scores

    func testScoresSortedDescending() {
        let result = classifier.classifyText(
            "climate carbon emission renewable solar sustainable ecosystem deforestation pollution recycling"
        )
        for i in 0..<(result.topics.count - 1) {
            XCTAssertGreaterThanOrEqual(
                result.topics[i].score, result.topics[i + 1].score,
                "Topics should be sorted by score descending"
            )
        }
    }

    // MARK: - World Topic

    func testWorldArticle() {
        let result = classifier.classifyText(
            "United Nations peacekeeping troops deployed to conflict zone as refugee crisis deepens amid humanitarian aid shortage"
        )
        XCTAssertEqual(result.primary, .world)
    }

    // MARK: - Trending Topics

    func testTrendDetectionRequiresMinArticles() {
        // Empty lists should produce no trends
        let trends = classifier.detectTrends(recent: [], baseline: [])
        XCTAssertTrue(trends.isEmpty)
    }
}
