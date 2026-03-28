//
//  ArticleQuizGenerator.swift
//  FeedReader
//
//  Generates comprehension quiz questions from article content to help readers
//  test and reinforce their understanding of what they've read.
//
//  Features:
//    - Multiple choice questions generated from article text
//    - True/false questions from key claims
//    - Fill-in-the-blank from important sentences
//    - Difficulty levels (easy, medium, hard)
//    - Quiz history tracking with scores
//    - Spaced review integration — resurface quizzes for retention
//    - Export quizzes as JSON or plain text
//
//  Persistence: UserDefaults via UserDefaultsCodableStore.
//  Works entirely offline with no external dependencies.
//

import Foundation

// MARK: - Notifications

extension Notification.Name {
    /// Posted when a quiz is generated or a quiz attempt is recorded.
    static let articleQuizDidUpdate = Notification.Name("ArticleQuizDidUpdateNotification")
}

// MARK: - Models

/// Difficulty level for quiz questions.
enum QuizDifficulty: String, Codable, CaseIterable {
    case easy
    case medium
    case hard
}

/// Type of quiz question.
enum QuizQuestionType: String, Codable, CaseIterable {
    case multipleChoice
    case trueFalse
    case fillInTheBlank
}

/// A single quiz question.
struct QuizQuestion: Codable, Equatable, Identifiable {
    let id: String
    let type: QuizQuestionType
    let difficulty: QuizDifficulty
    let questionText: String
    let options: [String]          // For multiple choice; empty for fill-in-blank
    let correctAnswerIndex: Int    // Index into options, or 0=true/1=false
    let explanation: String        // Why this is the correct answer
    let sourceExcerpt: String      // The article text this question derives from
}

/// A complete quiz for an article.
struct ArticleQuiz: Codable, Equatable, Identifiable {
    let id: String
    let articleURL: String
    let articleTitle: String
    let questions: [QuizQuestion]
    let generatedDate: Date
    let difficulty: QuizDifficulty
}

/// A record of a user's quiz attempt.
struct QuizAttempt: Codable, Equatable, Identifiable {
    let id: String
    let quizId: String
    let articleURL: String
    let answers: [Int]             // User's selected answer indices
    let correctCount: Int
    let totalCount: Int
    let score: Double              // 0.0–1.0
    let date: Date
    let timeSpentSeconds: Int
}

/// Aggregate quiz stats for a user.
struct QuizStats: Codable, Equatable {
    var totalQuizzesTaken: Int = 0
    var totalQuestionsAnswered: Int = 0
    var totalCorrect: Int = 0
    var averageScore: Double = 0.0
    var bestScore: Double = 0.0
    var currentStreak: Int = 0     // Consecutive quizzes with score >= 0.7
    var bestStreak: Int = 0
    var quizzesByDifficulty: [String: Int] = [:]  // difficulty -> count
}

// MARK: - ArticleQuizGenerator

/// Generates comprehension quizzes from article text and tracks quiz history.
final class ArticleQuizGenerator {

    // MARK: - Singleton

    static let shared = ArticleQuizGenerator()

    // MARK: - Storage

    private let quizStore = UserDefaultsCodableStore<[ArticleQuiz]>(key: "ArticleQuizGenerator.quizzes", defaultValue: [])
    private let attemptStore = UserDefaultsCodableStore<[QuizAttempt]>(key: "ArticleQuizGenerator.attempts", defaultValue: [])
    private let statsStore = UserDefaultsCodableStore<QuizStats>(key: "ArticleQuizGenerator.stats", defaultValue: QuizStats())

    private init() {}

    // MARK: - Quiz Generation

    /// Generate a quiz from article content.
    ///
    /// - Parameters:
    ///   - title: The article title.
    ///   - text: The full article body text.
    ///   - url: The article URL (used as identifier).
    ///   - difficulty: Desired difficulty level.
    ///   - questionCount: Number of questions to generate (capped at available content).
    /// - Returns: A generated `ArticleQuiz`.
    func generateQuiz(title: String, text: String, url: String,
                      difficulty: QuizDifficulty = .medium,
                      questionCount: Int = 5) -> ArticleQuiz {
        let sentences = extractSentences(from: text)
        let keyFacts = extractKeyFacts(from: sentences, title: title)

        var questions: [QuizQuestion] = []
        let targetCount = min(questionCount, max(keyFacts.count, 1))

        // Distribute question types
        for i in 0..<targetCount {
            let fact = keyFacts[i % keyFacts.count]
            let questionType: QuizQuestionType
            switch i % 3 {
            case 0: questionType = .multipleChoice
            case 1: questionType = .trueFalse
            default: questionType = .fillInTheBlank
            }

            if let question = createQuestion(from: fact, type: questionType,
                                              difficulty: difficulty, allFacts: keyFacts) {
                questions.append(question)
            }
        }

        let quiz = ArticleQuiz(
            id: UUID().uuidString,
            articleURL: url,
            articleTitle: title,
            questions: questions,
            generatedDate: Date(),
            difficulty: difficulty
        )

        // Persist
        var quizzes = quizStore.value
        quizzes.append(quiz)
        quizStore.value = quizzes

        NotificationCenter.default.post(name: .articleQuizDidUpdate, object: self)
        return quiz
    }

    // MARK: - Quiz Submission

    /// Submit answers for a quiz and record the attempt.
    ///
    /// - Parameters:
    ///   - quizId: The quiz ID.
    ///   - answers: Array of selected answer indices (one per question).
    ///   - timeSpentSeconds: Total time spent on the quiz.
    /// - Returns: The recorded `QuizAttempt`, or nil if quiz not found.
    func submitQuiz(quizId: String, answers: [Int], timeSpentSeconds: Int = 0) -> QuizAttempt? {
        guard let quiz = getQuiz(byId: quizId) else { return nil }

        let correctCount = zip(quiz.questions, answers).reduce(0) { count, pair in
            count + (pair.0.correctAnswerIndex == pair.1 ? 1 : 0)
        }
        let total = quiz.questions.count
        let score = total > 0 ? Double(correctCount) / Double(total) : 0.0

        let attempt = QuizAttempt(
            id: UUID().uuidString,
            quizId: quizId,
            articleURL: quiz.articleURL,
            answers: answers,
            correctCount: correctCount,
            totalCount: total,
            score: score,
            date: Date(),
            timeSpentSeconds: timeSpentSeconds
        )

        var attempts = attemptStore.value
        attempts.append(attempt)
        attemptStore.value = attempts

        updateStats(with: attempt)

        NotificationCenter.default.post(name: .articleQuizDidUpdate, object: self)
        return attempt
    }

    // MARK: - Retrieval

    /// Get all quizzes for a specific article.
    func quizzes(forURL url: String) -> [ArticleQuiz] {
        return quizStore.value.filter { $0.articleURL == url }
    }

    /// Get a quiz by its ID.
    func getQuiz(byId id: String) -> ArticleQuiz? {
        return quizStore.value.first { $0.id == id }
    }

    /// Get all attempts for a specific quiz.
    func attempts(forQuizId quizId: String) -> [QuizAttempt] {
        return attemptStore.value.filter { $0.quizId == quizId }
    }

    /// Get all attempts across all quizzes.
    func allAttempts() -> [QuizAttempt] {
        return attemptStore.value
    }

    /// Get the best attempt for a quiz.
    func bestAttempt(forQuizId quizId: String) -> QuizAttempt? {
        return attempts(forQuizId: quizId).max(by: { $0.score < $1.score })
    }

    /// Get current quiz stats.
    func currentStats() -> QuizStats {
        return statsStore.value
    }

    /// Get articles that need review (scored below threshold).
    func articlesNeedingReview(threshold: Double = 0.7) -> [String] {
        let attempts = attemptStore.value
        var bestByArticle: [String: Double] = [:]
        for attempt in attempts {
            let current = bestByArticle[attempt.articleURL] ?? 0.0
            bestByArticle[attempt.articleURL] = max(current, attempt.score)
        }
        return bestByArticle.filter { $0.value < threshold }.map { $0.key }
    }

    // MARK: - Export

    /// Export a quiz as JSON data.
    func exportAsJSON(quizId: String) -> Data? {
        guard let quiz = getQuiz(byId: quizId) else { return nil }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return try? encoder.encode(quiz)
    }

    /// Export a quiz as plain text.
    func exportAsPlainText(quizId: String) -> String? {
        guard let quiz = getQuiz(byId: quizId) else { return nil }

        var lines: [String] = []
        lines.append("Quiz: \(quiz.articleTitle)")
        lines.append("Difficulty: \(quiz.difficulty.rawValue)")
        lines.append("Generated: \(ISO8601DateFormatter().string(from: quiz.generatedDate))")
        lines.append(String(repeating: "=", count: 60))
        lines.append("")

        for (i, q) in quiz.questions.enumerated() {
            lines.append("Q\(i + 1). [\(q.type.rawValue)] \(q.questionText)")
            if q.type == .multipleChoice {
                for (j, opt) in q.options.enumerated() {
                    let marker = j == q.correctAnswerIndex ? "✓" : " "
                    lines.append("  \(marker) \(Character(UnicodeScalar(65 + j)!)). \(opt)")
                }
            } else if q.type == .trueFalse {
                lines.append("  Answer: \(q.correctAnswerIndex == 0 ? "True" : "False")")
            } else {
                lines.append("  Answer: \(q.options.first ?? "N/A")")
            }
            lines.append("  Explanation: \(q.explanation)")
            lines.append("")
        }
        return lines.joined(separator: "\n")
    }

    /// Delete a quiz by ID.
    func deleteQuiz(id: String) {
        var quizzes = quizStore.value
        quizzes.removeAll { $0.id == id }
        quizStore.value = quizzes
        NotificationCenter.default.post(name: .articleQuizDidUpdate, object: self)
    }

    /// Delete all quizzes and attempts.
    func resetAll() {
        quizStore.value = []
        attemptStore.value = []
        statsStore.value = QuizStats()
        NotificationCenter.default.post(name: .articleQuizDidUpdate, object: self)
    }

    // MARK: - Private Helpers

    /// Extract sentences from text.
    private func extractSentences(from text: String) -> [String] {
        var sentences: [String] = []
        text.enumerateSubstrings(in: text.startIndex..<text.endIndex,
                                 options: .bySentences) { substring, _, _, _ in
            if let s = substring?.trimmingCharacters(in: .whitespacesAndNewlines),
               s.count >= 15 {
                sentences.append(s)
            }
        }
        return sentences
    }

    /// Extract key facts (important sentences) from the article.
    private func extractKeyFacts(from sentences: [String], title: String) -> [String] {
        guard !sentences.isEmpty else {
            return ["This article discusses \(title)."]
        }

        // Score sentences by importance
        let titleWords = Set(title.lowercased().split(separator: " ")
            .map(String.init)
            .filter { $0.count > 3 })

        let scored = sentences.enumerated().map { (index, sentence) -> (String, Double) in
            var score = 0.0
            let lower = sentence.lowercased()

            // Bonus for containing title words
            for word in titleWords {
                if lower.contains(word) { score += 2.0 }
            }

            // Bonus for sentences with numbers (facts/data)
            if sentence.range(of: "\\d+", options: .regularExpression) != nil {
                score += 1.5
            }

            // Bonus for indicator phrases
            let indicators = ["important", "significant", "found that", "shows that",
                             "according to", "research", "study", "result",
                             "concluded", "discovered", "revealed", "demonstrated"]
            for ind in indicators {
                if lower.contains(ind) { score += 1.0 }
            }

            // Position bonus (earlier sentences are often more important)
            let positionFactor = 1.0 - (Double(index) / Double(sentences.count))
            score += positionFactor * 0.5

            // Penalize very short or very long sentences
            let wordCount = sentence.split(separator: " ").count
            if wordCount < 8 { score -= 1.0 }
            if wordCount > 40 { score -= 0.5 }

            return (sentence, score)
        }

        return scored.sorted { $0.1 > $1.1 }
            .prefix(10)
            .map { $0.0 }
    }

    /// Create a question from a fact sentence.
    private func createQuestion(from fact: String, type: QuizQuestionType,
                                difficulty: QuizDifficulty,
                                allFacts: [String]) -> QuizQuestion? {
        switch type {
        case .multipleChoice:
            return createMultipleChoice(from: fact, difficulty: difficulty, allFacts: allFacts)
        case .trueFalse:
            return createTrueFalse(from: fact, difficulty: difficulty)
        case .fillInTheBlank:
            return createFillInBlank(from: fact, difficulty: difficulty)
        }
    }

    /// Create a multiple choice question.
    private func createMultipleChoice(from fact: String, difficulty: QuizDifficulty,
                                      allFacts: [String]) -> QuizQuestion {
        let words = fact.split(separator: " ").map(String.init)
        // Find a key term to ask about
        let significantWords = words.filter { $0.count > 4 && $0.first?.isUppercase == false }
        let keyTerm = significantWords.randomElement() ?? words.last ?? "this"

        let truncated = truncateSentence(fact, around: keyTerm)
        let questionText = "According to the article, which of the following is mentioned in relation to: \"\(truncated)\"?"

        // Build options — correct answer is the fact itself (abbreviated)
        let correctOption = abbreviate(fact, maxLength: 80)
        var distractors: [String] = []

        // Use other facts as distractors
        let otherFacts = allFacts.filter { $0 != fact }
        for other in otherFacts.shuffled().prefix(3) {
            distractors.append(abbreviate(other, maxLength: 80))
        }

        // Pad with generic distractors if needed
        let genericDistractors = [
            "None of the information presented applies.",
            "The article does not address this topic.",
            "This was mentioned in a different context."
        ]
        while distractors.count < 3 {
            distractors.append(genericDistractors[distractors.count % genericDistractors.count])
        }

        var options = distractors.prefix(3).map(String.init)
        let correctIndex = Int.random(in: 0...3)
        options.insert(correctOption, at: correctIndex)

        return QuizQuestion(
            id: UUID().uuidString,
            type: .multipleChoice,
            difficulty: difficulty,
            questionText: questionText,
            options: options,
            correctAnswerIndex: correctIndex,
            explanation: "The article states: \"\(abbreviate(fact, maxLength: 120))\"",
            sourceExcerpt: fact
        )
    }

    /// Create a true/false question.
    private func createTrueFalse(from fact: String, difficulty: QuizDifficulty) -> QuizQuestion {
        let isTrue = Bool.random()
        let displayFact: String
        let correctIndex: Int

        if isTrue {
            displayFact = abbreviate(fact, maxLength: 120)
            correctIndex = 0  // True
        } else {
            // Negate or distort the fact
            displayFact = distortFact(abbreviate(fact, maxLength: 120))
            correctIndex = 1  // False
        }

        return QuizQuestion(
            id: UUID().uuidString,
            type: .trueFalse,
            difficulty: difficulty,
            questionText: "True or False: \(displayFact)",
            options: ["True", "False"],
            correctAnswerIndex: correctIndex,
            explanation: isTrue
                ? "This is directly stated in the article."
                : "The original article states: \"\(abbreviate(fact, maxLength: 100))\"",
            sourceExcerpt: fact
        )
    }

    /// Create a fill-in-the-blank question.
    private func createFillInBlank(from fact: String, difficulty: QuizDifficulty) -> QuizQuestion {
        let words = fact.split(separator: " ").map(String.init)
        // Pick a significant word to blank out
        let candidates = words.enumerated().filter { $0.element.count > 4 }
        guard let target = candidates.randomElement() else {
            // Fallback to a simpler question
            return QuizQuestion(
                id: UUID().uuidString,
                type: .fillInTheBlank,
                difficulty: difficulty,
                questionText: "Complete: \(abbreviate(fact, maxLength: 100))",
                options: [words.last ?? "answer"],
                correctAnswerIndex: 0,
                explanation: "The full sentence reads: \"\(abbreviate(fact, maxLength: 120))\"",
                sourceExcerpt: fact
            )
        }

        var blanked = words
        blanked[target.offset] = "________"
        let questionText = "Fill in the blank: \(blanked.joined(separator: " "))"

        return QuizQuestion(
            id: UUID().uuidString,
            type: .fillInTheBlank,
            difficulty: difficulty,
            questionText: questionText,
            options: [target.element],
            correctAnswerIndex: 0,
            explanation: "The missing word is \"\(target.element)\". Full sentence: \"\(abbreviate(fact, maxLength: 120))\"",
            sourceExcerpt: fact
        )
    }

    /// Abbreviate a sentence to a maximum length.
    private func abbreviate(_ text: String, maxLength: Int) -> String {
        if text.count <= maxLength { return text }
        let index = text.index(text.startIndex, offsetBy: maxLength - 3)
        return String(text[..<index]) + "..."
    }

    /// Truncate around a key term for context.
    private func truncateSentence(_ text: String, around term: String) -> String {
        return abbreviate(text, maxLength: 80)
    }

    /// Distort a fact to make it false for true/false questions.
    private func distortFact(_ fact: String) -> String {
        let distortions: [(String, String)] = [
            ("all", "none of the"),
            ("always", "never"),
            ("most", "very few"),
            ("many", "no"),
            ("significant", "insignificant"),
            ("important", "unimportant"),
            ("increased", "decreased"),
            ("higher", "lower"),
            ("more", "fewer"),
            ("can", "cannot"),
            ("is", "is not"),
            ("was", "was never"),
            ("found", "failed to find"),
            ("show", "disprove"),
        ]

        for (original, replacement) in distortions.shuffled() {
            if let range = fact.range(of: original, options: .caseInsensitive) {
                return fact.replacingCharacters(in: range, with: replacement)
            }
        }

        // Fallback: prepend negation
        return "It is not true that " + fact.prefix(1).lowercased() + fact.dropFirst()
    }

    /// Update aggregate stats after a quiz attempt.
    private func updateStats(with attempt: QuizAttempt) {
        var stats = statsStore.value
        stats.totalQuizzesTaken += 1
        stats.totalQuestionsAnswered += attempt.totalCount
        stats.totalCorrect += attempt.correctCount

        if stats.totalQuestionsAnswered > 0 {
            stats.averageScore = Double(stats.totalCorrect) / Double(stats.totalQuestionsAnswered)
        }
        if attempt.score > stats.bestScore {
            stats.bestScore = attempt.score
        }

        // Streak tracking
        if attempt.score >= 0.7 {
            stats.currentStreak += 1
            stats.bestStreak = max(stats.bestStreak, stats.currentStreak)
        } else {
            stats.currentStreak = 0
        }

        // Difficulty tracking
        if let quiz = getQuiz(byId: attempt.quizId) {
            let key = quiz.difficulty.rawValue
            stats.quizzesByDifficulty[key] = (stats.quizzesByDifficulty[key] ?? 0) + 1
        }

        statsStore.value = stats
    }
}
