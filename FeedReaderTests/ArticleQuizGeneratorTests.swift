//
//  ArticleQuizGeneratorTests.swift
//  FeedReaderTests
//

import XCTest
@testable import FeedReader

final class ArticleQuizGeneratorTests: XCTestCase {

    var generator: ArticleQuizGenerator!

    override func setUp() {
        super.setUp()
        generator = ArticleQuizGenerator()
        generator.clearAll()
    }

    override func tearDown() {
        generator.clearAll()
        generator = nil
        super.tearDown()
    }

    // MARK: - Sample Content

    let sampleContent = """
    Artificial intelligence has transformed the technology industry significantly. \
    Machine learning algorithms can process vast amounts of data in seconds. \
    Neural networks are inspired by the structure of the human brain. \
    Deep learning is a subset of machine learning that uses multiple layers. \
    Natural language processing enables computers to understand human language. \
    Computer vision allows machines to interpret and analyze visual information. \
    Reinforcement learning teaches agents to make decisions through trial and error. \
    Transfer learning enables models to apply knowledge from one domain to another. \
    Generative adversarial networks create realistic synthetic data samples. \
    Transformer architectures have revolutionized natural language understanding.
    """

    let shortContent = "Too short."

    let mediumContent = """
    The global temperature has risen by approximately 1.1 degrees Celsius since pre-industrial times. \
    Scientists predict that without intervention, temperatures could rise by 3 degrees by 2100. \
    Renewable energy sources now account for 29 percent of global electricity generation.
    """

    // MARK: - Quiz Generation

    func testGenerateQuizFromContent() {
        let quiz = generator.generateQuiz(articleId: "art1", title: "AI Overview", content: sampleContent)
        XCTAssertNotNil(quiz)
        XCTAssertEqual(quiz?.articleTitle, "AI Overview")
        XCTAssertEqual(quiz?.articleId, "art1")
        XCTAssertFalse(quiz?.questions.isEmpty ?? true)
    }

    func testGenerateQuizDefaultConfig() {
        let quiz = generator.generateQuiz(articleId: "art1", title: "Test", content: sampleContent)
        XCTAssertNotNil(quiz)
        // Default is 5 questions
        XCTAssertLessThanOrEqual(quiz!.questions.count, 5)
        XCTAssertGreaterThan(quiz!.questions.count, 0)
    }

    func testGenerateQuizCustomConfig() {
        let config = QuizConfig(questionCount: 3, difficulty: .easy,
                                includeMultipleChoice: true, includeTrueFalse: false,
                                includeFillInTheBlank: false)
        let quiz = generator.generateQuiz(articleId: "art1", title: "Test", content: sampleContent, config: config)
        XCTAssertNotNil(quiz)
        XCTAssertLessThanOrEqual(quiz!.questions.count, 3)
        // All should be multiple choice since others are disabled
        for q in quiz!.questions {
            XCTAssertEqual(q.type, .multipleChoice)
        }
    }

    func testGenerateQuizReturnsNilForShortContent() {
        let quiz = generator.generateQuiz(articleId: "art1", title: "Short", content: shortContent)
        XCTAssertNil(quiz)
    }

    func testGenerateQuizPersisted() {
        let quiz = generator.generateQuiz(articleId: "art1", title: "Test", content: sampleContent)
        XCTAssertNotNil(quiz)
        XCTAssertEqual(generator.getAllQuizzes().count, 1)
    }

    func testMultipleQuizzesForSameArticle() {
        _ = generator.generateQuiz(articleId: "art1", title: "Test", content: sampleContent)
        _ = generator.generateQuiz(articleId: "art1", title: "Test", content: sampleContent)
        XCTAssertEqual(generator.getQuizzes(forArticle: "art1").count, 2)
    }

    // MARK: - Sentence Extraction

    func testExtractSentences() {
        let sentences = generator.extractSentences(from: sampleContent)
        XCTAssertGreaterThan(sentences.count, 0)
        for s in sentences {
            XCTAssertTrue(s.hasSuffix("."))
        }
    }

    func testExtractSentencesFiltersShort() {
        let text = "Hi. OK. This is a longer sentence that should be kept."
        let sentences = generator.extractSentences(from: text)
        XCTAssertEqual(sentences.count, 1) // Only the long one
    }

    func testExtractSentencesHandlesNewlines() {
        let text = "First sentence here.\nSecond sentence with enough words to keep."
        let sentences = generator.extractSentences(from: text)
        XCTAssertEqual(sentences.count, 2)
    }

    // MARK: - Sentence Ranking

    func testRankSentencesPreferNumeric() {
        let sentences = [
            "The cat sat on the mat quietly.",
            "The temperature rose by 3 degrees in 2023.",
            "Birds fly south for the winter season."
        ]
        let ranked = generator.rankSentences(sentences, difficulty: .medium)
        // Numeric sentence should rank higher
        XCTAssertEqual(ranked.first, "The temperature rose by 3 degrees in 2023.")
    }

    func testRankSentencesPreferDefinitions() {
        let sentences = [
            "The weather was quite pleasant today.",
            "A neural network is a computing system inspired by biological networks.",
            "Birds sing in the morning hours regularly."
        ]
        let ranked = generator.rankSentences(sentences, difficulty: .medium)
        XCTAssertEqual(ranked.first, "A neural network is a computing system inspired by biological networks.")
    }

    // MARK: - Question Generation

    func testGenerateMultipleChoice() {
        let sentences = generator.extractSentences(from: sampleContent)
        guard sentences.count >= 2 else { XCTFail("Not enough sentences"); return }
        let q = generator.generateMultipleChoice(from: sentences[0], allSentences: sentences, difficulty: .medium)
        XCTAssertNotNil(q)
        XCTAssertEqual(q?.type, .multipleChoice)
        XCTAssertEqual(q?.options.count, 4)
        XCTAssertTrue(q?.options.contains(q!.correctAnswer) ?? false)
    }

    func testGenerateTrueFalse() {
        let q = generator.generateTrueFalse(
            from: "Machine learning algorithms can process vast amounts of data.",
            difficulty: .medium
        )
        XCTAssertNotNil(q)
        XCTAssertEqual(q?.type, .trueFalse)
        XCTAssertTrue(["True", "False"].contains(q!.correctAnswer))
        XCTAssertEqual(q?.options.count, 2)
    }

    func testGenerateFillInTheBlank() {
        let q = generator.generateFillInTheBlank(
            from: "Neural networks are inspired by the structure of the human brain.",
            difficulty: .medium
        )
        XCTAssertNotNil(q)
        XCTAssertEqual(q?.type, .fillInTheBlank)
        XCTAssertTrue(q!.questionText.contains("________"))
        XCTAssertFalse(q!.correctAnswer.isEmpty)
    }

    func testGenerateQuestionReturnsNilForTooShort() {
        let q = generator.generateQuestion(from: "Too short.", type: .multipleChoice, difficulty: .easy, allSentences: [])
        XCTAssertNil(q)
    }

    // MARK: - True/False Negation

    func testNegateSentenceWithIs() {
        let result = generator.negateSentence("AI is transforming the industry rapidly.")
        XCTAssertTrue(result.contains("not"))
    }

    func testNegateSentenceWithCan() {
        let result = generator.negateSentence("Algorithms can process large datasets quickly.")
        XCTAssertTrue(result.contains("cannot"))
    }

    func testNegateSentenceFallback() {
        let result = generator.negateSentence("Researchers discovered a new molecule yesterday.")
        XCTAssertTrue(result.contains("not"))
    }

    // MARK: - Answer Submission

    func testSubmitCorrectAnswer() {
        let quiz = generator.generateQuiz(articleId: "art1", title: "Test", content: sampleContent)!
        let question = quiz.questions[0]
        let answer = generator.submitAnswer(quizId: quiz.id, questionId: question.id, answer: question.correctAnswer)
        XCTAssertNotNil(answer)
        XCTAssertTrue(answer!.isCorrect)
    }

    func testSubmitIncorrectAnswer() {
        let quiz = generator.generateQuiz(articleId: "art1", title: "Test", content: sampleContent)!
        let question = quiz.questions[0]
        let answer = generator.submitAnswer(quizId: quiz.id, questionId: question.id, answer: "definitely_wrong_answer_xyz")
        XCTAssertNotNil(answer)
        XCTAssertFalse(answer!.isCorrect)
    }

    func testSubmitAnswerPreventsDuplicate() {
        let quiz = generator.generateQuiz(articleId: "art1", title: "Test", content: sampleContent)!
        let question = quiz.questions[0]
        _ = generator.submitAnswer(quizId: quiz.id, questionId: question.id, answer: question.correctAnswer)
        let dup = generator.submitAnswer(quizId: quiz.id, questionId: question.id, answer: "other")
        XCTAssertNil(dup) // Can't re-answer
    }

    func testSubmitAnswerInvalidQuiz() {
        let answer = generator.submitAnswer(quizId: "nonexistent", questionId: "q1", answer: "test")
        XCTAssertNil(answer)
    }

    func testQuizCompletesWhenAllAnswered() {
        let config = QuizConfig(questionCount: 2, difficulty: .easy,
                                includeMultipleChoice: true, includeTrueFalse: true,
                                includeFillInTheBlank: false)
        let quiz = generator.generateQuiz(articleId: "art1", title: "Test", content: sampleContent, config: config)!

        for question in quiz.questions {
            _ = generator.submitAnswer(quizId: quiz.id, questionId: question.id, answer: question.correctAnswer)
        }

        let completed = generator.getQuiz(id: quiz.id)!
        XCTAssertTrue(completed.isComplete)
        XCTAssertNotNil(completed.completedAt)
        XCTAssertNotNil(completed.score)
    }

    func testPerfectScore() {
        let config = QuizConfig(questionCount: 3, difficulty: .easy,
                                includeMultipleChoice: true, includeTrueFalse: true,
                                includeFillInTheBlank: true)
        let quiz = generator.generateQuiz(articleId: "art1", title: "Test", content: sampleContent, config: config)!

        for question in quiz.questions {
            _ = generator.submitAnswer(quizId: quiz.id, questionId: question.id, answer: question.correctAnswer)
        }

        let completed = generator.getQuiz(id: quiz.id)!
        XCTAssertEqual(completed.score, 1.0)
        XCTAssertEqual(completed.comprehensionLevel, "Excellent")
    }

    // MARK: - Answer Checking

    func testCheckAnswerCaseInsensitive() {
        XCTAssertTrue(generator.checkAnswer(userAnswer: "TRUE", correctAnswer: "True", type: .trueFalse))
        XCTAssertTrue(generator.checkAnswer(userAnswer: "neural", correctAnswer: "Neural", type: .multipleChoice))
    }

    func testCheckAnswerTrimmed() {
        XCTAssertTrue(generator.checkAnswer(userAnswer: "  True  ", correctAnswer: "True", type: .trueFalse))
    }

    func testCheckFillInBlankPartialMatch() {
        // Fill-in-the-blank accepts prefix match if 4+ chars
        XCTAssertTrue(generator.checkAnswer(userAnswer: "neur", correctAnswer: "neural", type: .fillInTheBlank))
        XCTAssertFalse(generator.checkAnswer(userAnswer: "neu", correctAnswer: "neural", type: .fillInTheBlank))
    }

    // MARK: - Retrieval

    func testGetQuizById() {
        let quiz = generator.generateQuiz(articleId: "art1", title: "Test", content: sampleContent)!
        let found = generator.getQuiz(id: quiz.id)
        XCTAssertNotNil(found)
        XCTAssertEqual(found?.id, quiz.id)
    }

    func testGetCompletedQuizzes() {
        let config = QuizConfig(questionCount: 1, difficulty: .easy,
                                includeMultipleChoice: true, includeTrueFalse: false,
                                includeFillInTheBlank: false)
        let q1 = generator.generateQuiz(articleId: "art1", title: "T1", content: sampleContent, config: config)!
        _ = generator.generateQuiz(articleId: "art2", title: "T2", content: sampleContent, config: config)!

        // Complete only q1
        _ = generator.submitAnswer(quizId: q1.id, questionId: q1.questions[0].id, answer: q1.questions[0].correctAnswer)

        XCTAssertEqual(generator.getCompletedQuizzes().count, 1)
    }

    func testGetNextQuestion() {
        let config = QuizConfig(questionCount: 3, difficulty: .easy,
                                includeMultipleChoice: true, includeTrueFalse: true,
                                includeFillInTheBlank: true)
        let quiz = generator.generateQuiz(articleId: "art1", title: "Test", content: sampleContent, config: config)!

        let first = generator.getNextQuestion(quizId: quiz.id)
        XCTAssertNotNil(first)
        XCTAssertEqual(first?.id, quiz.questions[0].id)

        _ = generator.submitAnswer(quizId: quiz.id, questionId: quiz.questions[0].id, answer: "x")
        let second = generator.getNextQuestion(quizId: quiz.id)
        XCTAssertEqual(second?.id, quiz.questions[1].id)
    }

    func testGetInProgressQuizzes() {
        let config = QuizConfig(questionCount: 2, difficulty: .easy,
                                includeMultipleChoice: true, includeTrueFalse: true,
                                includeFillInTheBlank: false)
        let quiz = generator.generateQuiz(articleId: "art1", title: "T1", content: sampleContent, config: config)!
        _ = generator.submitAnswer(quizId: quiz.id, questionId: quiz.questions[0].id, answer: "x")

        XCTAssertEqual(generator.getInProgressQuizzes().count, 1)
    }

    // MARK: - Deletion

    func testDeleteQuiz() {
        let quiz = generator.generateQuiz(articleId: "art1", title: "Test", content: sampleContent)!
        XCTAssertTrue(generator.deleteQuiz(id: quiz.id))
        XCTAssertNil(generator.getQuiz(id: quiz.id))
    }

    func testDeleteQuizInvalidId() {
        XCTAssertFalse(generator.deleteQuiz(id: "nonexistent"))
    }

    func testDeleteQuizzesForArticle() {
        _ = generator.generateQuiz(articleId: "art1", title: "T1", content: sampleContent)
        _ = generator.generateQuiz(articleId: "art1", title: "T1", content: sampleContent)
        _ = generator.generateQuiz(articleId: "art2", title: "T2", content: sampleContent)
        generator.deleteQuizzes(forArticle: "art1")
        XCTAssertEqual(generator.getAllQuizzes().count, 1)
    }

    func testClearAll() {
        _ = generator.generateQuiz(articleId: "art1", title: "T1", content: sampleContent)
        _ = generator.generateQuiz(articleId: "art2", title: "T2", content: sampleContent)
        generator.clearAll()
        XCTAssertTrue(generator.getAllQuizzes().isEmpty)
    }

    // MARK: - Statistics

    func testStatsEmpty() {
        let stats = generator.getStats()
        XCTAssertEqual(stats.totalQuizzesTaken, 0)
        XCTAssertEqual(stats.averageScore, 0.0)
    }

    func testStatsAfterCompletion() {
        let config = QuizConfig(questionCount: 2, difficulty: .easy,
                                includeMultipleChoice: true, includeTrueFalse: true,
                                includeFillInTheBlank: false)
        let quiz = generator.generateQuiz(articleId: "art1", title: "Test", content: sampleContent, config: config)!

        for q in quiz.questions {
            _ = generator.submitAnswer(quizId: quiz.id, questionId: q.id, answer: q.correctAnswer)
        }

        let stats = generator.getStats()
        XCTAssertEqual(stats.totalQuizzesTaken, 1)
        XCTAssertEqual(stats.averageScore, 1.0)
        XCTAssertEqual(stats.bestScore, 1.0)
    }

    func testArticleComprehension() {
        let config = QuizConfig(questionCount: 1, difficulty: .easy,
                                includeMultipleChoice: true, includeTrueFalse: false,
                                includeFillInTheBlank: false)
        let quiz = generator.generateQuiz(articleId: "art1", title: "Test", content: sampleContent, config: config)!
        _ = generator.submitAnswer(quizId: quiz.id, questionId: quiz.questions[0].id, answer: quiz.questions[0].correctAnswer)

        let score = generator.getArticleComprehension(articleId: "art1")
        XCTAssertNotNil(score)
        XCTAssertEqual(score!, 1.0)
    }

    func testArticleComprehensionNilForUnquizzed() {
        XCTAssertNil(generator.getArticleComprehension(articleId: "none"))
    }

    func testComprehensionRanking() {
        let config = QuizConfig(questionCount: 1, difficulty: .easy,
                                includeMultipleChoice: true, includeTrueFalse: false,
                                includeFillInTheBlank: false)
        let q1 = generator.generateQuiz(articleId: "art1", title: "Good", content: sampleContent, config: config)!
        let q2 = generator.generateQuiz(articleId: "art2", title: "Bad", content: sampleContent, config: config)!

        _ = generator.submitAnswer(quizId: q1.id, questionId: q1.questions[0].id, answer: q1.questions[0].correctAnswer)
        _ = generator.submitAnswer(quizId: q2.id, questionId: q2.questions[0].id, answer: "wrong")

        let ranking = generator.getArticleComprehensionRanking()
        XCTAssertEqual(ranking.count, 2)
        XCTAssertEqual(ranking[0].articleId, "art1") // Perfect score first
    }

    // MARK: - Quiz Review

    func testQuizReview() {
        let config = QuizConfig(questionCount: 2, difficulty: .easy,
                                includeMultipleChoice: true, includeTrueFalse: true,
                                includeFillInTheBlank: false)
        let quiz = generator.generateQuiz(articleId: "art1", title: "Test", content: sampleContent, config: config)!

        _ = generator.submitAnswer(quizId: quiz.id, questionId: quiz.questions[0].id, answer: quiz.questions[0].correctAnswer)

        let review = generator.getQuizReview(quizId: quiz.id)
        XCTAssertNotNil(review)
        XCTAssertEqual(review?.count, 2)
        XCTAssertNotNil(review?[0].answer) // First answered
        XCTAssertNil(review?[1].answer)    // Second not yet
    }

    func testQuizReviewInvalidId() {
        XCTAssertNil(generator.getQuizReview(quizId: "nonexistent"))
    }

    // MARK: - Model Properties

    func testQuizComprehensionLevel() {
        XCTAssertEqual(Quiz(articleId: "a", articleTitle: "t", questions: [], score: 0.95).comprehensionLevel, "Excellent")
        XCTAssertEqual(Quiz(articleId: "a", articleTitle: "t", questions: [], score: 0.75).comprehensionLevel, "Good")
        XCTAssertEqual(Quiz(articleId: "a", articleTitle: "t", questions: [], score: 0.55).comprehensionLevel, "Fair")
        XCTAssertEqual(Quiz(articleId: "a", articleTitle: "t", questions: [], score: 0.35).comprehensionLevel, "Needs Review")
        XCTAssertEqual(Quiz(articleId: "a", articleTitle: "t", questions: [], score: 0.1).comprehensionLevel, "Poor")
        XCTAssertEqual(Quiz(articleId: "a", articleTitle: "t", questions: []).comprehensionLevel, "Not attempted")
    }

    func testQuizConfigEnabledTypes() {
        let allOff = QuizConfig(questionCount: 5, difficulty: .easy,
                                includeMultipleChoice: false, includeTrueFalse: false,
                                includeFillInTheBlank: false)
        // Falls back to at least multipleChoice
        XCTAssertEqual(allOff.enabledTypes, [.multipleChoice])

        let tfOnly = QuizConfig(questionCount: 5, difficulty: .easy,
                                includeMultipleChoice: false, includeTrueFalse: true,
                                includeFillInTheBlank: false)
        XCTAssertEqual(tfOnly.enabledTypes, [.trueFalse])
    }

    func testQuizStatsEmpty() {
        let s = QuizStats.empty
        XCTAssertEqual(s.totalQuizzesTaken, 0)
        XCTAssertEqual(s.averageScore, 0.0)
        XCTAssertTrue(s.quizzesByArticle.isEmpty)
    }

    // MARK: - Difficulty Modes

    func testEasyDifficultyConfig() {
        let config = QuizConfig(questionCount: 3, difficulty: .easy,
                                includeMultipleChoice: true, includeTrueFalse: true,
                                includeFillInTheBlank: true)
        let quiz = generator.generateQuiz(articleId: "art1", title: "Easy", content: sampleContent, config: config)
        XCTAssertNotNil(quiz)
    }

    func testHardDifficultyConfig() {
        let config = QuizConfig(questionCount: 3, difficulty: .hard,
                                includeMultipleChoice: true, includeTrueFalse: true,
                                includeFillInTheBlank: true)
        let quiz = generator.generateQuiz(articleId: "art1", title: "Hard", content: sampleContent, config: config)
        XCTAssertNotNil(quiz)
    }

    // MARK: - Edge Cases

    func testGenerateQuizWithMediumContent() {
        let quiz = generator.generateQuiz(articleId: "art1", title: "Medium", content: mediumContent)
        XCTAssertNotNil(quiz)
    }

    func testQuizQuestionHasExplanation() {
        let quiz = generator.generateQuiz(articleId: "art1", title: "Test", content: sampleContent)!
        for q in quiz.questions {
            XCTAssertFalse(q.explanation.isEmpty, "Question should have an explanation")
        }
    }

    func testQuizQuestionHasSourceExcerpt() {
        let quiz = generator.generateQuiz(articleId: "art1", title: "Test", content: sampleContent)!
        for q in quiz.questions {
            XCTAssertFalse(q.sourceExcerpt.isEmpty, "Question should reference source text")
        }
    }
}
