//
//  ArticleQuizGenerator.swift
//  FeedReader
//
//  Generates reading comprehension quizzes from article content.
//  Extracts key sentences and transforms them into multiple-choice,
//  true/false, and fill-in-the-blank questions. Tracks quiz history,
//  scores, and per-article comprehension levels.
//
//  Features:
//  - Three question types: multiple choice, true/false, fill-in-the-blank
//  - Automatic question extraction from article text
//  - Distractor generation for multiple choice answers
//  - Configurable quiz length and difficulty
//  - Score tracking with per-article history
//  - Comprehension level assessment
//  - Quiz review with explanations
//  - JSON persistence via UserDefaultsCodableStore
//

import Foundation

// MARK: - Models

/// Type of quiz question.
enum QuestionType: String, Codable {
    case multipleChoice   // Pick the correct answer from 4 options
    case trueFalse        // Determine if a statement is true or false
    case fillInTheBlank   // Complete the sentence with the missing word/phrase
}

/// Difficulty level for quiz generation.
enum QuizDifficulty: String, Codable {
    case easy       // Straightforward factual recall
    case medium     // Requires understanding context
    case hard       // Requires inference or synthesis
}

/// A single quiz question.
struct QuizQuestion: Codable, Equatable {
    let id: String
    let questionText: String
    let type: QuestionType
    let correctAnswer: String
    let options: [String]        // For multipleChoice; empty for others
    let explanation: String      // Why this answer is correct
    let difficulty: QuizDifficulty
    let sourceExcerpt: String    // The sentence/passage this was derived from

    init(id: String = UUID().uuidString,
         questionText: String,
         type: QuestionType,
         correctAnswer: String,
         options: [String] = [],
         explanation: String = "",
         difficulty: QuizDifficulty = .medium,
         sourceExcerpt: String = "") {
        self.id = id
        self.questionText = questionText
        self.type = type
        self.correctAnswer = correctAnswer
        self.options = options
        self.explanation = explanation
        self.difficulty = difficulty
        self.sourceExcerpt = sourceExcerpt
    }
}

/// A user's answer to a quiz question.
struct QuizAnswer: Codable, Equatable {
    let questionId: String
    let userAnswer: String
    let isCorrect: Bool
    let answeredAt: Date
}

/// A complete quiz for an article.
struct Quiz: Codable, Equatable {
    let id: String
    let articleId: String
    let articleTitle: String
    let questions: [QuizQuestion]
    let createdAt: Date
    var answers: [QuizAnswer]
    var completedAt: Date?
    var score: Double?           // 0.0–1.0

    var isComplete: Bool {
        return completedAt != nil
    }

    var answeredCount: Int {
        return answers.count
    }

    var totalQuestions: Int {
        return questions.count
    }

    var correctCount: Int {
        return answers.filter { $0.isCorrect }.count
    }

    /// Comprehension level based on score.
    var comprehensionLevel: String {
        guard let s = score else { return "Not attempted" }
        if s >= 0.9 { return "Excellent" }
        if s >= 0.7 { return "Good" }
        if s >= 0.5 { return "Fair" }
        if s >= 0.3 { return "Needs Review" }
        return "Poor"
    }

    init(id: String = UUID().uuidString,
         articleId: String,
         articleTitle: String,
         questions: [QuizQuestion],
         createdAt: Date = Date(),
         answers: [QuizAnswer] = [],
         completedAt: Date? = nil,
         score: Double? = nil) {
        self.id = id
        self.articleId = articleId
        self.articleTitle = articleTitle
        self.questions = questions
        self.createdAt = createdAt
        self.answers = answers
        self.completedAt = completedAt
        self.score = score
    }
}

/// Configuration for quiz generation.
struct QuizConfig {
    var questionCount: Int
    var difficulty: QuizDifficulty
    var includeMultipleChoice: Bool
    var includeTrueFalse: Bool
    var includeFillInTheBlank: Bool

    static let `default` = QuizConfig(
        questionCount: 5,
        difficulty: .medium,
        includeMultipleChoice: true,
        includeTrueFalse: true,
        includeFillInTheBlank: true
    )

    /// Enabled question types based on configuration.
    var enabledTypes: [QuestionType] {
        var types: [QuestionType] = []
        if includeMultipleChoice { types.append(.multipleChoice) }
        if includeTrueFalse { types.append(.trueFalse) }
        if includeFillInTheBlank { types.append(.fillInTheBlank) }
        if types.isEmpty { types.append(.multipleChoice) } // Always at least one
        return types
    }
}

/// Aggregate quiz statistics.
struct QuizStats: Codable {
    var totalQuizzesTaken: Int
    var totalQuestionsAnswered: Int
    var totalCorrect: Int
    var averageScore: Double
    var bestScore: Double
    var worstScore: Double
    var quizzesByArticle: [String: Int]   // articleId → count
    var scoresByDifficulty: [String: [Double]]  // difficulty → scores

    static let empty = QuizStats(
        totalQuizzesTaken: 0,
        totalQuestionsAnswered: 0,
        totalCorrect: 0,
        averageScore: 0.0,
        bestScore: 0.0,
        worstScore: 1.0,
        quizzesByArticle: [:],
        scoresByDifficulty: [:]
    )
}

// MARK: - ArticleQuizGenerator

/// Generates and manages reading comprehension quizzes from article content.
final class ArticleQuizGenerator {

    // MARK: - Storage

    private let quizStore = UserDefaultsCodableStore<[Quiz]>(key: "article_quizzes")
    private var quizzes: [Quiz] = []

    // MARK: - Sentence Extraction Patterns

    /// Words that often start informative, quiz-worthy sentences.
    private static let informativeStarters = [
        "the", "a", "an", "this", "these", "those", "it",
        "researchers", "scientists", "experts", "studies",
        "according", "however", "furthermore", "moreover",
        "in", "on", "at", "during", "after", "before",
        "new", "recent", "current", "latest"
    ]

    /// Words to use as distractors for true/false negation.
    private static let negationWords = ["not", "never", "rarely", "unlikely", "impossible"]

    /// Common filler words to skip when selecting key terms for fill-in-the-blank.
    private static let stopWords: Set<String> = [
        "the", "a", "an", "is", "are", "was", "were", "be", "been",
        "being", "have", "has", "had", "do", "does", "did", "will",
        "would", "could", "should", "may", "might", "can", "shall",
        "to", "of", "in", "for", "on", "with", "at", "by", "from",
        "as", "into", "through", "during", "before", "after", "above",
        "below", "between", "and", "but", "or", "nor", "so", "yet",
        "both", "either", "neither", "not", "only", "also", "very",
        "that", "this", "these", "those", "it", "its", "he", "she",
        "they", "them", "their", "his", "her", "we", "our", "my",
        "your", "which", "who", "whom", "whose", "what", "when",
        "where", "why", "how", "all", "each", "every", "some",
        "any", "no", "more", "most", "other", "than", "then",
        "just", "about", "up", "out", "if", "over", "such", "own"
    ]

    // MARK: - Initialization

    init() {
        load()
    }

    // MARK: - Persistence

    private func load() {
        quizzes = quizStore.load() ?? []
    }

    private func save() {
        quizStore.save(quizzes)
    }

    // MARK: - Quiz Generation

    /// Generate a quiz from article content.
    /// - Parameters:
    ///   - articleId: Unique identifier for the article
    ///   - title: Article title
    ///   - content: Article body text
    ///   - config: Quiz configuration (defaults to `.default`)
    /// - Returns: A generated `Quiz`, or nil if content is too short
    func generateQuiz(articleId: String, title: String, content: String,
                      config: QuizConfig = .default) -> Quiz? {
        let sentences = extractSentences(from: content)
        guard sentences.count >= 3 else { return nil }

        let informative = rankSentences(sentences, difficulty: config.difficulty)
        guard !informative.isEmpty else { return nil }

        var questions: [QuizQuestion] = []
        let enabledTypes = config.enabledTypes
        let target = min(config.questionCount, informative.count)

        for i in 0..<target {
            let sentence = informative[i]
            let qType = enabledTypes[i % enabledTypes.count]

            if let question = generateQuestion(from: sentence, type: qType,
                                                difficulty: config.difficulty,
                                                allSentences: sentences) {
                questions.append(question)
            }
        }

        guard !questions.isEmpty else { return nil }

        let quiz = Quiz(articleId: articleId, articleTitle: title, questions: questions)
        quizzes.append(quiz)
        save()
        return quiz
    }

    /// Extract clean sentences from text.
    func extractSentences(from text: String) -> [String] {
        let cleaned = text.replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "\r", with: " ")
            .replacingOccurrences(of: "\t", with: " ")

        // Split on sentence-ending punctuation
        var sentences: [String] = []
        var current = ""

        for char in cleaned {
            current.append(char)
            if char == "." || char == "!" || char == "?" {
                let trimmed = current.trimmingCharacters(in: .whitespaces)
                let wordCount = trimmed.split(separator: " ").count
                // Keep sentences with 5+ words for meaningful questions
                if wordCount >= 5 && wordCount <= 50 {
                    sentences.append(trimmed)
                }
                current = ""
            }
        }

        return sentences
    }

    /// Rank sentences by informativeness for quiz question generation.
    func rankSentences(_ sentences: [String], difficulty: QuizDifficulty) -> [String] {
        var scored: [(String, Double)] = []

        for sentence in sentences {
            var score = 0.0
            let lower = sentence.lowercased()
            let words = lower.split(separator: " ")

            // Longer sentences (up to a point) are more informative
            let wordCount = Double(words.count)
            if wordCount >= 8 && wordCount <= 30 {
                score += 2.0
            } else if wordCount >= 5 {
                score += 1.0
            }

            // Sentences with numbers/statistics are good quiz material
            if sentence.range(of: "\\d+", options: .regularExpression) != nil {
                score += 3.0
            }

            // Sentences with proper nouns (capitalized words mid-sentence)
            let midWords = words.dropFirst()
            for word in midWords {
                if let first = word.first, first.isUppercase {
                    score += 1.0
                    break
                }
            }

            // Sentences with key informative patterns
            if lower.contains("because") || lower.contains("therefore") ||
               lower.contains("result") || lower.contains("cause") {
                score += 2.0
            }

            // Definition patterns get bonus
            if lower.contains(" is ") || lower.contains(" are ") ||
               lower.contains(" means ") || lower.contains(" refers to ") {
                score += 2.5
            }

            // Comparison patterns
            if lower.contains("more than") || lower.contains("less than") ||
               lower.contains("compared to") || lower.contains("unlike") {
                score += 2.0
            }

            // Difficulty adjustment
            switch difficulty {
            case .easy:
                // Prefer shorter, definition-like sentences
                if wordCount <= 15 { score += 1.0 }
            case .medium:
                break // Default scoring
            case .hard:
                // Prefer complex sentences with multiple clauses
                if sentence.contains(",") { score += 1.0 }
                if wordCount >= 15 { score += 1.5 }
            }

            scored.append((sentence, score))
        }

        return scored.sorted { $0.1 > $1.1 }.map { $0.0 }
    }

    /// Generate a single question from a sentence.
    func generateQuestion(from sentence: String, type: QuestionType,
                          difficulty: QuizDifficulty,
                          allSentences: [String]) -> QuizQuestion? {
        switch type {
        case .multipleChoice:
            return generateMultipleChoice(from: sentence, allSentences: allSentences, difficulty: difficulty)
        case .trueFalse:
            return generateTrueFalse(from: sentence, difficulty: difficulty)
        case .fillInTheBlank:
            return generateFillInTheBlank(from: sentence, difficulty: difficulty)
        }
    }

    // MARK: - Multiple Choice Generation

    /// Generate a multiple-choice question from a sentence.
    func generateMultipleChoice(from sentence: String, allSentences: [String],
                                difficulty: QuizDifficulty) -> QuizQuestion? {
        let words = sentence.split(separator: " ").map(String.init)
        guard words.count >= 5 else { return nil }

        // Find the key term (longest non-stop-word)
        let keyTerms = words.filter { word in
            let lower = word.lowercased().trimmingCharacters(in: .punctuationCharacters)
            return lower.count >= 4 && !ArticleQuizGenerator.stopWords.contains(lower)
        }
        guard let keyTerm = keyTerms.max(by: { $0.count < $1.count }) else { return nil }

        let cleanKey = keyTerm.trimmingCharacters(in: .punctuationCharacters)
        let questionText = "According to the article, which of the following is mentioned in relation to: \"\(truncate(sentence, maxLength: 100))\"?"

        // Generate distractors from other sentences
        var distractors: [String] = []
        for other in allSentences where other != sentence {
            let otherWords = other.split(separator: " ").map(String.init)
            let candidates = otherWords.filter { word in
                let lower = word.lowercased().trimmingCharacters(in: .punctuationCharacters)
                return lower.count >= 4 &&
                    !ArticleQuizGenerator.stopWords.contains(lower) &&
                    lower != cleanKey.lowercased()
            }
            if let distractor = candidates.max(by: { $0.count < $1.count }) {
                let clean = distractor.trimmingCharacters(in: .punctuationCharacters)
                if !distractors.contains(where: { $0.lowercased() == clean.lowercased() }) &&
                   clean.lowercased() != cleanKey.lowercased() {
                    distractors.append(clean)
                }
            }
            if distractors.count >= 3 { break }
        }

        // Pad with generic distractors if needed
        let fallbacks = ["phenomenon", "methodology", "infrastructure", "correlation",
                         "implementation", "development", "framework", "perspective"]
        while distractors.count < 3 {
            let fb = fallbacks[distractors.count % fallbacks.count]
            if !distractors.contains(fb) && fb.lowercased() != cleanKey.lowercased() {
                distractors.append(fb)
            } else {
                break
            }
        }

        // Shuffle options with correct answer
        var options = Array(distractors.prefix(3))
        options.append(cleanKey)
        options.shuffle()

        return QuizQuestion(
            questionText: questionText,
            type: .multipleChoice,
            correctAnswer: cleanKey,
            options: options,
            explanation: "The article states: \"\(truncate(sentence, maxLength: 150))\"",
            difficulty: difficulty,
            sourceExcerpt: sentence
        )
    }

    // MARK: - True/False Generation

    /// Generate a true/false question from a sentence.
    func generateTrueFalse(from sentence: String, difficulty: QuizDifficulty) -> QuizQuestion? {
        let words = sentence.split(separator: " ").map(String.init)
        guard words.count >= 5 else { return nil }

        // 50/50 chance: present the true statement or a negated false one
        let presentTrue = Int.random(in: 0...1) == 0

        if presentTrue {
            let questionText = "True or False: \(truncate(sentence, maxLength: 200))"
            return QuizQuestion(
                questionText: questionText,
                type: .trueFalse,
                correctAnswer: "True",
                options: ["True", "False"],
                explanation: "This statement is directly from the article.",
                difficulty: difficulty,
                sourceExcerpt: sentence
            )
        } else {
            // Create a false version by negating or altering the sentence
            let modified = negateSentence(sentence)
            let questionText = "True or False: \(truncate(modified, maxLength: 200))"
            return QuizQuestion(
                questionText: questionText,
                type: .trueFalse,
                correctAnswer: "False",
                options: ["True", "False"],
                explanation: "The article actually states: \"\(truncate(sentence, maxLength: 150))\"",
                difficulty: difficulty,
                sourceExcerpt: sentence
            )
        }
    }

    /// Negate a sentence to create a false statement.
    func negateSentence(_ sentence: String) -> String {
        let replacements: [(String, String)] = [
            (" is ", " is not "),
            (" are ", " are not "),
            (" was ", " was not "),
            (" were ", " were not "),
            (" can ", " cannot "),
            (" will ", " will not "),
            (" has ", " has not "),
            (" have ", " have not "),
            (" does ", " does not "),
            (" do ", " do not "),
            (" should ", " should not "),
            (" could ", " could not "),
            (" would ", " would not ")
        ]

        for (target, replacement) in replacements {
            if let range = sentence.range(of: target, options: .caseInsensitive) {
                return sentence.replacingCharacters(in: range, with: replacement)
            }
        }

        // Fallback: insert "not" after the first word
        let words = sentence.split(separator: " ", maxSplits: 1).map(String.init)
        if words.count >= 2 {
            return words[0] + " not " + words[1]
        }
        return sentence
    }

    // MARK: - Fill-in-the-Blank Generation

    /// Generate a fill-in-the-blank question from a sentence.
    func generateFillInTheBlank(from sentence: String, difficulty: QuizDifficulty) -> QuizQuestion? {
        let words = sentence.split(separator: " ").map(String.init)
        guard words.count >= 5 else { return nil }

        // Find a suitable word to blank out (non-stop-word, 4+ chars)
        let candidates = words.enumerated().compactMap { (index, word) -> (Int, String)? in
            let lower = word.lowercased().trimmingCharacters(in: .punctuationCharacters)
            guard lower.count >= 4, !ArticleQuizGenerator.stopWords.contains(lower) else { return nil }
            // Don't blank the first word (easier to parse) or last (might be punctuation-heavy)
            guard index > 0 && index < words.count - 1 else { return nil }
            return (index, word)
        }

        guard let chosen = difficulty == .hard
            ? candidates.max(by: { $0.1.count < $1.1.count })  // Hardest: longest word
            : candidates.first                                    // Easy/medium: first suitable
        else { return nil }

        let blankWord = chosen.1.trimmingCharacters(in: .punctuationCharacters)
        var blankedWords = words
        blankedWords[chosen.0] = "________"
        let questionText = "Fill in the blank: " + blankedWords.joined(separator: " ")

        return QuizQuestion(
            questionText: questionText,
            type: .fillInTheBlank,
            correctAnswer: blankWord,
            explanation: "The original sentence reads: \"\(truncate(sentence, maxLength: 150))\"",
            difficulty: difficulty,
            sourceExcerpt: sentence
        )
    }

    // MARK: - Quiz Answering

    /// Submit an answer to a quiz question.
    /// - Parameters:
    ///   - quizId: The quiz identifier
    ///   - questionId: The question identifier
    ///   - answer: The user's answer string
    /// - Returns: The `QuizAnswer`, or nil if quiz/question not found
    @discardableResult
    func submitAnswer(quizId: String, questionId: String, answer: String) -> QuizAnswer? {
        guard let index = quizzes.firstIndex(where: { $0.id == quizId }) else { return nil }
        guard quizzes[index].questions.contains(where: { $0.id == questionId }) else { return nil }

        // Don't allow re-answering
        guard !quizzes[index].answers.contains(where: { $0.questionId == questionId }) else { return nil }

        let question = quizzes[index].questions.first { $0.id == questionId }!
        let isCorrect = checkAnswer(userAnswer: answer, correctAnswer: question.correctAnswer, type: question.type)

        let quizAnswer = QuizAnswer(
            questionId: questionId,
            userAnswer: answer,
            isCorrect: isCorrect,
            answeredAt: Date()
        )

        quizzes[index].answers.append(quizAnswer)

        // Complete quiz if all questions answered
        if quizzes[index].answers.count == quizzes[index].questions.count {
            quizzes[index].completedAt = Date()
            let correct = quizzes[index].answers.filter { $0.isCorrect }.count
            quizzes[index].score = Double(correct) / Double(quizzes[index].questions.count)
        }

        save()
        return quizAnswer
    }

    /// Check if an answer is correct (case-insensitive, trimmed).
    func checkAnswer(userAnswer: String, correctAnswer: String, type: QuestionType) -> Bool {
        let user = userAnswer.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let correct = correctAnswer.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()

        switch type {
        case .trueFalse:
            return user == correct
        case .multipleChoice:
            return user == correct
        case .fillInTheBlank:
            // Allow minor variations: exact match or contained within answer
            if user == correct { return true }
            // Accept if the correct word starts with what the user typed (4+ chars)
            if user.count >= 4 && correct.hasPrefix(user) { return true }
            return false
        }
    }

    // MARK: - Quiz Retrieval

    /// Get all quizzes.
    func getAllQuizzes() -> [Quiz] {
        return quizzes
    }

    /// Get quizzes for a specific article.
    func getQuizzes(forArticle articleId: String) -> [Quiz] {
        return quizzes.filter { $0.articleId == articleId }
    }

    /// Get a quiz by ID.
    func getQuiz(id: String) -> Quiz? {
        return quizzes.first { $0.id == id }
    }

    /// Get only completed quizzes.
    func getCompletedQuizzes() -> [Quiz] {
        return quizzes.filter { $0.isComplete }
    }

    /// Get in-progress (started but not finished) quizzes.
    func getInProgressQuizzes() -> [Quiz] {
        return quizzes.filter { !$0.isComplete && $0.answeredCount > 0 }
    }

    /// Get the next unanswered question in a quiz.
    func getNextQuestion(quizId: String) -> QuizQuestion? {
        guard let quiz = getQuiz(id: quizId) else { return nil }
        let answeredIds = Set(quiz.answers.map { $0.questionId })
        return quiz.questions.first { !answeredIds.contains($0.id) }
    }

    // MARK: - Quiz Deletion

    /// Delete a quiz by ID.
    @discardableResult
    func deleteQuiz(id: String) -> Bool {
        let before = quizzes.count
        quizzes.removeAll { $0.id == id }
        if quizzes.count < before {
            save()
            return true
        }
        return false
    }

    /// Delete all quizzes for an article.
    func deleteQuizzes(forArticle articleId: String) {
        quizzes.removeAll { $0.articleId == articleId }
        save()
    }

    /// Clear all quizzes.
    func clearAll() {
        quizzes.removeAll()
        save()
    }

    // MARK: - Statistics

    /// Compute aggregate quiz statistics.
    func getStats() -> QuizStats {
        let completed = getCompletedQuizzes()
        guard !completed.isEmpty else { return .empty }

        let scores = completed.compactMap { $0.score }
        let totalAnswers = completed.reduce(0) { $0 + $1.answers.count }
        let totalCorrect = completed.reduce(0) { $0 + $1.correctCount }

        var byArticle: [String: Int] = [:]
        for q in completed {
            byArticle[q.articleId, default: 0] += 1
        }

        var byDifficulty: [String: [Double]] = [:]
        for q in completed {
            for question in q.questions {
                let diffKey = question.difficulty.rawValue
                if let answer = q.answers.first(where: { $0.questionId == question.id }) {
                    byDifficulty[diffKey, default: []].append(answer.isCorrect ? 1.0 : 0.0)
                }
            }
        }

        return QuizStats(
            totalQuizzesTaken: completed.count,
            totalQuestionsAnswered: totalAnswers,
            totalCorrect: totalCorrect,
            averageScore: scores.isEmpty ? 0.0 : scores.reduce(0, +) / Double(scores.count),
            bestScore: scores.max() ?? 0.0,
            worstScore: scores.min() ?? 0.0,
            quizzesByArticle: byArticle,
            scoresByDifficulty: byDifficulty
        )
    }

    /// Get comprehension score for a specific article (average of all quiz scores).
    func getArticleComprehension(articleId: String) -> Double? {
        let articleQuizzes = getQuizzes(forArticle: articleId).filter { $0.isComplete }
        guard !articleQuizzes.isEmpty else { return nil }
        let scores = articleQuizzes.compactMap { $0.score }
        guard !scores.isEmpty else { return nil }
        return scores.reduce(0, +) / Double(scores.count)
    }

    /// Get articles ranked by comprehension score (highest first).
    func getArticleComprehensionRanking() -> [(articleId: String, title: String, score: Double, quizCount: Int)] {
        var byArticle: [String: (title: String, scores: [Double])] = [:]

        for quiz in quizzes where quiz.isComplete {
            if var entry = byArticle[quiz.articleId] {
                if let s = quiz.score { entry.scores.append(s) }
                byArticle[quiz.articleId] = entry
            } else {
                byArticle[quiz.articleId] = (
                    title: quiz.articleTitle,
                    scores: quiz.score.map { [$0] } ?? []
                )
            }
        }

        return byArticle.map { (articleId, data) in
            let avg = data.scores.isEmpty ? 0.0 : data.scores.reduce(0, +) / Double(data.scores.count)
            return (articleId: articleId, title: data.title, score: avg, quizCount: data.scores.count)
        }.sorted { $0.score > $1.score }
    }

    // MARK: - Quiz Review

    /// Get a detailed review of a completed quiz.
    func getQuizReview(quizId: String) -> [(question: QuizQuestion, answer: QuizAnswer?, isCorrect: Bool?)]? {
        guard let quiz = getQuiz(id: quizId) else { return nil }

        return quiz.questions.map { question in
            let answer = quiz.answers.first { $0.questionId == question.id }
            return (question: question, answer: answer, isCorrect: answer?.isCorrect)
        }
    }

    // MARK: - Helpers

    /// Truncate text to a maximum length with ellipsis.
    private func truncate(_ text: String, maxLength: Int) -> String {
        if text.count <= maxLength { return text }
        let end = text.index(text.startIndex, offsetBy: maxLength)
        return String(text[..<end]) + "..."
    }
}
