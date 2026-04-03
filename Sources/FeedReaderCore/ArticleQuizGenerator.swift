//
//  ArticleQuizGenerator.swift
//  FeedReaderCore
//
//  Generates comprehension quiz questions from RSS article content.
//  Useful for active reading, knowledge retention, and study modes.
//  Works entirely offline using extractive NLP techniques — no API needed.
//

import Foundation

/// A single quiz question with multiple-choice answers.
public struct QuizQuestion: Sendable {
    /// The question text.
    public let question: String
    /// Array of possible answers.
    public let choices: [String]
    /// Index of the correct answer in `choices`.
    public let correctIndex: Int
    /// The sentence from the article that contains the answer.
    public let sourceExcerpt: String
    /// Question category.
    public let category: QuizCategory

    /// The correct answer text.
    public var correctAnswer: String { choices[correctIndex] }

    public enum QuizCategory: String, Sendable, CaseIterable {
        case factual = "Factual"
        case vocabulary = "Vocabulary"
        case inference = "Inference"
        case titleBased = "Title-Based"
    }
}

/// Result of a completed quiz attempt.
public struct QuizResult: Sendable {
    /// Questions in this quiz.
    public let questions: [QuizQuestion]
    /// User's answers (indices into each question's choices).
    public let userAnswers: [Int]
    /// Number of correct answers.
    public var score: Int {
        zip(questions, userAnswers).filter { $0.0.correctIndex == $0.1 }.count
    }
    /// Score as a percentage (0–100).
    public var percentage: Double {
        questions.isEmpty ? 0 : Double(score) / Double(questions.count) * 100
    }
    /// Per-question correctness.
    public var breakdown: [(question: QuizQuestion, userAnswer: Int, correct: Bool)] {
        zip(questions, userAnswers).map { ($0.0, $0.1, $0.0.correctIndex == $0.1) }
    }
}

/// Generates comprehension quizzes from RSS stories.
///
/// Uses extractive techniques to create questions about article content:
/// - **Factual**: Fill-in-the-blank from key sentences
/// - **Vocabulary**: Identify words that appeared in the article
/// - **Title-Based**: Questions about the article's main topic
///
/// ## Usage
/// ```swift
/// let generator = ArticleQuizGenerator()
/// let questions = generator.generateQuiz(from: story, count: 5)
/// for q in questions {
///     print(q.question)
///     for (i, choice) in q.choices.enumerated() {
///         print("  \(i == q.correctIndex ? "✓" : " ") \(choice)")
///     }
/// }
///
/// // Score a quiz
/// let result = QuizResult(questions: questions, userAnswers: [0, 2, 1, 3, 0])
/// print("Score: \(result.score)/\(questions.count) (\(result.percentage)%)")
/// ```
public class ArticleQuizGenerator {

    // MARK: - Configuration

    /// Number of answer choices per question.
    public var choiceCount: Int = 4

    /// Minimum sentence length (characters) to use for question generation.
    public var minimumSentenceLength: Int = 30

    /// Random number generator seed for reproducible quizzes (nil = random).
    public var seed: UInt64?

    // MARK: - Initialization

    public init() {}

    // MARK: - Public API

    /// Generates a quiz from a single RSS story.
    /// - Parameters:
    ///   - story: The RSS story to generate questions from.
    ///   - count: Number of questions to generate (best effort).
    /// - Returns: Array of quiz questions.
    public func generateQuiz(from story: RSSStory, count: Int = 5) -> [QuizQuestion] {
        var rng: RandomNumberGenerator = seed.map { SeededRNG(seed: $0) } ?? SystemRandomNumberGenerator() as RandomNumberGenerator
        var questions: [QuizQuestion] = []

        // Generate different question types
        let sentences = splitSentences(story.body)
        let goodSentences = sentences.filter { $0.count >= minimumSentenceLength }

        // 1. Title-based question (always try one)
        if let titleQ = generateTitleQuestion(story: story, rng: &rng) {
            questions.append(titleQ)
        }

        // 2. Factual fill-in-the-blank questions
        let factualSentences = goodSentences.shuffled(using: &rng)
        for sentence in factualSentences.prefix(count) {
            if let q = generateFactualQuestion(sentence: sentence, allSentences: goodSentences, rng: &rng) {
                questions.append(q)
                if questions.count >= count { break }
            }
        }

        // 3. Vocabulary questions if we need more
        if questions.count < count {
            if let vocabQ = generateVocabularyQuestion(story: story, rng: &rng) {
                questions.append(vocabQ)
            }
        }

        return Array(questions.prefix(count))
    }

    /// Generates a quiz from multiple stories (cross-article quiz).
    /// - Parameters:
    ///   - stories: Array of RSS stories.
    ///   - questionsPerStory: Questions to attempt per story.
    /// - Returns: Mixed quiz questions from all stories.
    public func generateCrossArticleQuiz(from stories: [RSSStory], questionsPerStory: Int = 2) -> [QuizQuestion] {
        var all: [QuizQuestion] = []
        for story in stories {
            let qs = generateQuiz(from: story, count: questionsPerStory)
            all.append(contentsOf: qs)
        }
        return all.shuffled()
    }

    /// Scores user answers against a quiz.
    /// - Parameters:
    ///   - questions: The quiz questions.
    ///   - answers: User's selected answer indices.
    /// - Returns: A QuizResult with score breakdown.
    public func score(questions: [QuizQuestion], answers: [Int]) -> QuizResult {
        let paddedAnswers = answers + Array(repeating: -1, count: max(0, questions.count - answers.count))
        return QuizResult(questions: questions, userAnswers: Array(paddedAnswers.prefix(questions.count)))
    }

    // MARK: - Question Generators

    private func generateTitleQuestion(story: RSSStory, rng: inout RandomNumberGenerator) -> QuizQuestion? {
        let titleWords = extractSignificantWords(from: story.title)
        guard titleWords.count >= 2 else { return nil }

        // "What is this article primarily about?"
        let correctTopic = titleWords.prefix(3).joined(separator: ", ")
        var distractors = generateDistractorTopics(excluding: Set(titleWords), from: story.body, rng: &rng)
        distractors = Array(distractors.prefix(choiceCount - 1))

        guard distractors.count >= choiceCount - 1 else { return nil }

        var choices = distractors
        let correctIdx = Int.random(in: 0..<choiceCount, using: &rng)
        choices.insert(correctTopic, at: correctIdx)

        return QuizQuestion(
            question: "What is the main topic of this article?",
            choices: choices,
            correctIndex: correctIdx,
            sourceExcerpt: story.title,
            category: .titleBased
        )
    }

    private func generateFactualQuestion(sentence: String, allSentences: [String], rng: inout RandomNumberGenerator) -> QuizQuestion? {
        let words = extractSignificantWords(from: sentence)
        guard words.count >= 3 else { return nil }

        // Pick a keyword to blank out
        let targetWord = words.randomElement(using: &rng)!
        let blanked = sentence.replacingOccurrences(
            of: "\\b\(NSRegularExpression.escapedPattern(for: targetWord))\\b",
            with: "______",
            options: [.regularExpression, .caseInsensitive],
            range: sentence.startIndex..<sentence.endIndex
        )

        guard blanked != sentence else { return nil }

        // Generate distractors from other sentences
        var distractorPool = Set<String>()
        for s in allSentences where s != sentence {
            for w in extractSignificantWords(from: s) {
                if w.lowercased() != targetWord.lowercased() {
                    distractorPool.insert(w)
                }
            }
        }

        let distractors = Array(distractorPool.shuffled(using: &rng).prefix(choiceCount - 1))
        guard distractors.count >= choiceCount - 1 else { return nil }

        var choices = distractors
        let correctIdx = Int.random(in: 0..<choiceCount, using: &rng)
        choices.insert(targetWord, at: correctIdx)

        return QuizQuestion(
            question: "Fill in the blank: \(blanked)",
            choices: choices,
            correctIndex: correctIdx,
            sourceExcerpt: sentence,
            category: .factual
        )
    }

    private func generateVocabularyQuestion(story: RSSStory, rng: inout RandomNumberGenerator) -> QuizQuestion? {
        let articleWords = Set(extractSignificantWords(from: story.body).map { $0.lowercased() })
        guard articleWords.count >= choiceCount else { return nil }

        let correctWord = articleWords.randomElement()!

        // Generate words that are plausible but NOT in the article
        let fakeWords = Self.commonWords.filter { !articleWords.contains($0.lowercased()) }.shuffled(using: &rng)
        let distractors = Array(fakeWords.prefix(choiceCount - 1))
        guard distractors.count >= choiceCount - 1 else { return nil }

        var choices = distractors
        let correctIdx = Int.random(in: 0..<choiceCount, using: &rng)
        choices.insert(correctWord, at: correctIdx)

        return QuizQuestion(
            question: "Which of these words appeared in the article?",
            choices: choices,
            correctIndex: correctIdx,
            sourceExcerpt: "(vocabulary check)",
            category: .vocabulary
        )
    }

    // MARK: - Text Processing

    private func splitSentences(_ text: String) -> [String] {
        var sentences: [String] = []
        text.enumerateSubstrings(in: text.startIndex..., options: .bySentences) { sub, _, _, _ in
            if let s = sub?.trimmingCharacters(in: .whitespacesAndNewlines), !s.isEmpty {
                sentences.append(s)
            }
        }
        return sentences
    }

    private func extractSignificantWords(from text: String) -> [String] {
        return TextUtilities.extractSignificantWords(from: text, minimumLength: 4)
    }

    private func generateDistractorTopics(excluding: Set<String>, from body: String, rng: inout RandomNumberGenerator) -> [String] {
        let bodyWords = extractSignificantWords(from: body)
        let excludeLowered = Set(excluding.map { $0.lowercased() })
        let candidates = bodyWords.filter { !excludeLowered.contains($0.lowercased()) }

        var distractors: [String] = []
        var used = Set<String>()
        for word in candidates.shuffled(using: &rng) {
            let low = word.lowercased()
            if !used.contains(low) {
                used.insert(low)
                distractors.append(word)
                if distractors.count >= choiceCount { break }
            }
        }

        // Pad with common words if needed
        if distractors.count < choiceCount - 1 {
            for w in Self.commonWords.shuffled(using: &rng) {
                if !excludeLowered.contains(w) && !used.contains(w) {
                    distractors.append(w)
                    used.insert(w)
                    if distractors.count >= choiceCount - 1 { break }
                }
            }
        }

        return distractors
    }

    // MARK: - Word Lists

    // Stop words are provided by TextUtilities.stopWords

    /// Common English words used as distractors.
    private static let commonWords: [String] = [
        "algorithm", "quantum", "blockchain", "neural", "satellite",
        "democracy", "ecosystem", "infrastructure", "legislation", "metabolism",
        "philosophy", "radiation", "telescope", "vaccination", "wavelength",
        "archaeology", "biodiversity", "cryptocurrency", "diplomacy", "evolution",
        "geopolitics", "hypothesis", "innovation", "jurisdiction", "kinetic",
        "linguistics", "microscope", "nanotechnology", "optimization", "photosynthesis",
    ]

    // MARK: - Seeded RNG

    private struct SeededRNG: RandomNumberGenerator {
        private var state: UInt64
        init(seed: UInt64) { self.state = seed }
        mutating func next() -> UInt64 {
            state &+= 0x9e3779b97f4a7c15
            var z = state
            z = (z ^ (z >> 30)) &* 0xbf58476d1ce4e5b9
            z = (z ^ (z >> 27)) &* 0x94d049bb133111eb
            return z ^ (z >> 31)
        }
    }
}
