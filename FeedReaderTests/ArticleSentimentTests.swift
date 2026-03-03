//
//  ArticleSentimentTests.swift
//  FeedReaderTests
//

import XCTest
@testable import FeedReader

class ArticleSentimentTests: XCTestCase {

    // MARK: - Empty / Trivial Input

    func testEmptyTextReturnsNeutral() {
        let result = ArticleSentimentAnalyzer.analyze("")
        XCTAssertEqual(result.label, .neutral)
        XCTAssertEqual(result.score, 0)
        XCTAssertEqual(result.wordCount, 0)
        XCTAssertEqual(result.positiveWordCount, 0)
        XCTAssertEqual(result.negativeWordCount, 0)
    }

    func testWhitespaceOnlyReturnsNeutral() {
        let result = ArticleSentimentAnalyzer.analyze("   \n\t  ")
        XCTAssertEqual(result.label, .neutral)
        XCTAssertEqual(result.wordCount, 0)
    }

    // MARK: - Positive Sentiment

    func testClearlyPositiveText() {
        let text = "This is an excellent and wonderful product. I am thrilled with the amazing results."
        let result = ArticleSentimentAnalyzer.analyze(text)
        XCTAssertGreaterThan(result.score, 0.3)
        XCTAssertTrue([.positive, .veryPositive].contains(result.label),
                       "Expected positive, got \(result.label)")
        XCTAssertGreaterThan(result.positiveWordCount, 0)
    }

    func testMildlyPositiveText() {
        let text = "The weather is nice today and the park is pleasant."
        let result = ArticleSentimentAnalyzer.analyze(text)
        XCTAssertGreaterThan(result.score, 0)
    }

    // MARK: - Negative Sentiment

    func testClearlyNegativeText() {
        let text = "This is terrible and horrible. The failure was devastating and catastrophic."
        let result = ArticleSentimentAnalyzer.analyze(text)
        XCTAssertLessThan(result.score, -0.3)
        XCTAssertTrue([.negative, .veryNegative].contains(result.label),
                       "Expected negative, got \(result.label)")
        XCTAssertGreaterThan(result.negativeWordCount, 0)
    }

    func testMildlyNegativeText() {
        let text = "There were some problems and a few mistakes in the process."
        let result = ArticleSentimentAnalyzer.analyze(text)
        XCTAssertLessThan(result.score, 0)
    }

    // MARK: - Neutral

    func testFactualTextIsNeutral() {
        let text = "The meeting was held on Tuesday at the office. Three people attended."
        let result = ArticleSentimentAnalyzer.analyze(text)
        XCTAssertTrue(abs(result.score) < 0.3,
                       "Expected near-neutral, got \(result.score)")
    }

    // MARK: - Negation Handling

    func testNegationFlipsSentiment() {
        let positive = ArticleSentimentAnalyzer.analyze("This is good.")
        let negated = ArticleSentimentAnalyzer.analyze("This is not good.")
        XCTAssertGreaterThan(positive.score, negated.score,
                              "Negation should reduce the score")
    }

    func testNegationOfNegative() {
        let negative = ArticleSentimentAnalyzer.analyze("This is terrible.")
        let negated = ArticleSentimentAnalyzer.analyze("This is not terrible.")
        XCTAssertGreaterThan(negated.score, negative.score,
                              "Negating a negative should increase the score")
    }

    // MARK: - Intensifiers

    func testIntensifierAmplifies() {
        let normal = ArticleSentimentAnalyzer.analyze("This is good.")
        let intensified = ArticleSentimentAnalyzer.analyze("This is extremely good.")
        XCTAssertGreaterThan(intensified.score, normal.score,
                              "Intensifier should amplify the score")
    }

    // MARK: - Sentence Sentiments

    func testSentenceSentimentsCount() {
        let text = "Great news today. But there are problems ahead. Overall things are fine."
        let result = ArticleSentimentAnalyzer.analyze(text)
        XCTAssertEqual(result.sentenceSentiments.count, 3,
                        "Should have 3 sentence scores")
    }

    func testSentenceSentimentsRange() {
        let text = "Excellent work. Terrible outcome."
        let result = ArticleSentimentAnalyzer.analyze(text)
        for score in result.sentenceSentiments {
            XCTAssertGreaterThanOrEqual(score, -1.0)
            XCTAssertLessThanOrEqual(score, 1.0)
        }
    }

    // MARK: - Top Terms

    func testTopPositiveTermsPopulated() {
        let text = "Excellent, wonderful, amazing, fantastic, brilliant, superb work!"
        let result = ArticleSentimentAnalyzer.analyze(text)
        XCTAssertFalse(result.topPositiveTerms.isEmpty)
        XCTAssertLessThanOrEqual(result.topPositiveTerms.count, 5)
    }

    func testTopNegativeTermsPopulated() {
        let text = "Terrible, horrible, catastrophic, devastating, dreadful problems."
        let result = ArticleSentimentAnalyzer.analyze(text)
        XCTAssertFalse(result.topNegativeTerms.isEmpty)
        XCTAssertLessThanOrEqual(result.topNegativeTerms.count, 5)
    }

    // MARK: - Subjectivity

    func testHighSubjectivityText() {
        let text = "Excellent amazing wonderful terrible horrible dreadful"
        let result = ArticleSentimentAnalyzer.analyze(text)
        XCTAssertGreaterThan(result.subjectivity, 0.5,
                              "All-sentiment text should have high subjectivity")
    }

    func testLowSubjectivityText() {
        let text = "The report was submitted on Monday. It contains five sections. Each section has three paragraphs."
        let result = ArticleSentimentAnalyzer.analyze(text)
        XCTAssertLessThan(result.subjectivity, 0.3,
                           "Factual text should have low subjectivity")
    }

    // MARK: - Emotion Detection

    func testJoyEmotion() {
        let text = "I am so happy and thrilled! This is wonderful, I enjoy every moment."
        let result = ArticleSentimentAnalyzer.analyze(text)
        XCTAssertEqual(result.dominantEmotion, .joy)
    }

    func testFearEmotion() {
        let text = "There is a dangerous threat. People are afraid and anxious about the alarming risk."
        let result = ArticleSentimentAnalyzer.analyze(text)
        XCTAssertEqual(result.dominantEmotion, .fear)
    }

    func testAngerEmotion() {
        let text = "Citizens are angry and furious about the outrage. They condemn the hostile actions."
        let result = ArticleSentimentAnalyzer.analyze(text)
        XCTAssertEqual(result.dominantEmotion, .anger)
    }

    // MARK: - Score Range

    func testScoreNeverExceedsBounds() {
        let texts = [
            "Excellent excellent excellent excellent excellent excellent",
            "Terrible terrible terrible terrible terrible terrible",
            "Good bad good bad good bad good bad good bad",
            String(repeating: "amazing ", count: 100),
        ]
        for text in texts {
            let result = ArticleSentimentAnalyzer.analyze(text)
            XCTAssertGreaterThanOrEqual(result.score, -1.0,
                                         "Score should not go below -1.0")
            XCTAssertLessThanOrEqual(result.score, 1.0,
                                      "Score should not go above 1.0")
        }
    }

    // MARK: - Sentence Splitting

    func testSplitSentences() {
        let text = "Hello world. How are you? I am fine!"
        let sentences = ArticleSentimentAnalyzer.splitSentences(text)
        XCTAssertEqual(sentences.count, 3)
    }

    func testSplitSentencesWithNewlines() {
        let text = "First sentence.\nSecond sentence.\nThird."
        let sentences = ArticleSentimentAnalyzer.splitSentences(text)
        XCTAssertEqual(sentences.count, 3)
    }

    // MARK: - Mixed Sentiment

    func testMixedSentiment() {
        let text = """
        The product has excellent build quality and amazing design.
        However, the terrible battery life and horrible customer service
        ruin the experience. The price is great but the performance is awful.
        """
        let result = ArticleSentimentAnalyzer.analyze(text)
        XCTAssertTrue(result.positiveWordCount > 0)
        XCTAssertTrue(result.negativeWordCount > 0)
    }

    // MARK: - Emoji

    func testSentimentLabelEmoji() {
        for label in SentimentLabel.allCases {
            XCTAssertFalse(label.emoji.isEmpty, "\(label) should have an emoji")
        }
    }

    func testDominantEmotionEmoji() {
        for emotion in DominantEmotion.allCases {
            XCTAssertFalse(emotion.emoji.isEmpty, "\(emotion) should have an emoji")
        }
    }

    // MARK: - Word Count

    func testWordCountAccurate() {
        let text = "one two three four five"
        let result = ArticleSentimentAnalyzer.analyze(text)
        XCTAssertEqual(result.wordCount, 5)
    }
}
