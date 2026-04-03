//
//  ArticleFlashcardGenerator.swift
//  FeedReader
//
//  Generates spaced-repetition flashcards from article content using
//  pattern-based extraction (definitions, statistics, comparisons,
//  processes, facts). Implements SM-2 algorithm for review scheduling.
//  Supports decks, review sessions, statistics, and JSON export/import.
//

import Foundation

// MARK: - Notifications

extension Notification.Name {
    static let flashcardsDidChange = Notification.Name("FlashcardsDidChangeNotification")
}

// MARK: - Difficulty Rating

/// Difficulty rating for SM-2 algorithm (0-5 scale).
enum ReviewDifficulty: Int, Codable {
    case blackout = 0      // Complete failure
    case incorrect = 1     // Wrong but recognized
    case difficult = 2     // Correct but very difficult
    case hesitant = 3      // Correct with hesitation
    case easy = 4          // Correct with ease
    case perfect = 5       // Perfect recall

    /// Ratings >= 3 count as correct.
    var isCorrect: Bool { rawValue >= 3 }
}

// MARK: - Flashcard Type

/// The extraction pattern that produced a flashcard.
enum FlashcardType: String, Codable, CaseIterable {
    case definition
    case statistic
    case comparison
    case process
    case fact
    case custom
}

// MARK: - Flashcard Model

/// A single flashcard with SM-2 scheduling data.
class Flashcard: Codable, Equatable {
    let id: String
    var front: String
    var back: String
    let type: FlashcardType
    let articleId: String
    let articleTitle: String
    let createdDate: Date

    // SM-2 fields
    var repetitions: Int = 0
    var interval: Int = 1
    var easeFactor: Double = 2.5
    var nextReviewDate: Date
    var totalReviews: Int = 0
    var correctReviews: Int = 0

    var isNew: Bool { totalReviews == 0 }
    var isDue: Bool { nextReviewDate <= Date() }

    var accuracy: Double {
        guard totalReviews > 0 else { return 0.0 }
        return Double(correctReviews) / Double(totalReviews)
    }

    var masteryLevel: String {
        if totalReviews == 0 { return "New" }
        if repetitions >= 5 && easeFactor >= 2.5 { return "Mastered" }
        if repetitions >= 3 { return "Learning" }
        return "Reviewing"
    }

    init(id: String = UUID().uuidString, front: String, back: String,
         type: FlashcardType, articleId: String, articleTitle: String,
         createdDate: Date = Date()) {
        self.id = id
        self.front = front
        self.back = back
        self.type = type
        self.articleId = articleId
        self.articleTitle = articleTitle
        self.createdDate = createdDate
        self.nextReviewDate = createdDate
    }

    static func == (lhs: Flashcard, rhs: Flashcard) -> Bool {
        lhs.id == rhs.id
    }
}

// MARK: - FlashcardDeck

/// A named collection of flashcard IDs.
struct FlashcardDeck: Codable, Equatable {
    let id: String
    var name: String
    var description: String?
    var cardIds: [String]
    let createdDate: Date

    var cardCount: Int { cardIds.count }

    init(id: String = UUID().uuidString, name: String,
         description: String? = nil, cardIds: [String] = [],
         createdDate: Date = Date()) {
        self.id = id
        self.name = name
        self.description = description
        self.cardIds = cardIds
        self.createdDate = createdDate
    }
}

// MARK: - Review Session Result

/// Result of a completed review session.
struct ReviewSessionResult: Codable {
    let sessionDate: Date
    let cardsReviewed: Int
    let correctCount: Int
    let averageDifficulty: Double
    let durationSeconds: Double
    let cardResults: [CardReviewResult]

    var accuracy: Double {
        guard cardsReviewed > 0 else { return 0.0 }
        return Double(correctCount) / Double(cardsReviewed)
    }

    var grade: String {
        let pct = accuracy
        if pct >= 0.9 { return "A" }
        if pct >= 0.8 { return "B" }
        if pct >= 0.7 { return "C" }
        if pct >= 0.6 { return "D" }
        return "F"
    }
}

/// Individual card result within a session.
struct CardReviewResult: Codable {
    let cardId: String
    let difficulty: ReviewDifficulty
    let durationSeconds: Double
}

// MARK: - Extraction Result

/// Result of extracting flashcards from an article.
struct ExtractionResult {
    let articleId: String
    let articleTitle: String
    let flashcards: [Flashcard]
    let sentenceCount: Int

    var extractedCount: Int { flashcards.count }
}

// MARK: - Learning Stats

/// Aggregate statistics for the flashcard system.
struct LearningStats {
    let totalCards: Int
    let newCards: Int
    let dueToday: Int
    let masteredCards: Int
    let averageEaseFactor: Double
    let totalReviews: Int
    let currentStreak: Int
    let longestStreak: Int
    let byType: [FlashcardType: Int]
}

// MARK: - Persistence Payload

private struct FlashcardStore: Codable {
    var cards: [Flashcard]
    var decks: [FlashcardDeck]
    var sessionHistory: [ReviewSessionResult]
    var reviewDates: [String] // ISO dates for streak tracking
}

// MARK: - ArticleFlashcardGenerator

class ArticleFlashcardGenerator {

    // MARK: - Configuration

    let minSentenceWords: Int
    private let maxCardsPerArticle: Int

    // MARK: - State

    private var cardsById: [String: Flashcard] = [:]
    private var decksById: [String: FlashcardDeck] = [:]
    private var sessionHistory: [ReviewSessionResult] = []
    private var reviewDates: Set<String> = []

    private let calendar = Calendar.current
    private lazy var dateFormatter: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withFullDate]
        return f
    }()

    // MARK: - Filler subjects to skip in definition extraction

    private static let fillerSubjects: Set<String> = [
        "it", "this", "that", "they", "we", "he", "she", "there", "here",
        "one", "these", "those", "what", "which"
    ]

    // MARK: - Initialization

    init(maxCardsPerArticle: Int = 50, minSentenceWords: Int = 5) {
        self.maxCardsPerArticle = max(1, maxCardsPerArticle)
        self.minSentenceWords = max(3, minSentenceWords)
    }

    // MARK: - Extraction

    /// Generate flashcards from article body text.
    func generateCards(articleId: String, title: String, body: String) -> ExtractionResult {
        guard !body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return ExtractionResult(articleId: articleId, articleTitle: title,
                                    flashcards: [], sentenceCount: 0)
        }

        let sentences = splitSentences(body)
        var cards: [Flashcard] = []
        var seenFronts: Set<String> = []

        for sentence in sentences {
            let words = sentence.split(separator: " ")
            guard words.count >= minSentenceWords else { continue }
            guard cards.count < maxCardsPerArticle else { break }

            let extracted = extractFromSentence(sentence, articleId: articleId, articleTitle: title)
            for card in extracted {
                let key = card.front.lowercased()
                guard !seenFronts.contains(key) else { continue }
                seenFronts.insert(key)
                cards.append(card)
                if cards.count >= maxCardsPerArticle { break }
            }
        }

        return ExtractionResult(articleId: articleId, articleTitle: title,
                                flashcards: cards, sentenceCount: sentences.count)
    }

    // MARK: - Card CRUD

    /// Add cards, skipping duplicates by front text. Returns count added.
    @discardableResult
    func addCards(_ cards: [Flashcard], toDeck deckId: String? = nil) -> Int {
        let existingFronts = Set(cardsById.values.map { $0.front.lowercased() })
        var added = 0

        for card in cards {
            let key = card.front.lowercased()
            guard !existingFronts.contains(key) && cardsById[card.id] == nil else { continue }
            cardsById[card.id] = card
            if let deckId = deckId, decksById[deckId] != nil {
                decksById[deckId]?.cardIds.append(card.id)
            }
            added += 1
        }

        if added > 0 {
            NotificationCenter.default.post(name: .flashcardsDidChange, object: nil)
        }
        return added
    }

    /// Create a custom flashcard.
    @discardableResult
    func createCustomCard(front: String, back: String, deckId: String? = nil) -> Flashcard? {
        let f = front.trimmingCharacters(in: .whitespacesAndNewlines)
        let b = back.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !f.isEmpty, !b.isEmpty else { return nil }

        let card = Flashcard(front: f, back: b, type: .custom, articleId: "", articleTitle: "")
        cardsById[card.id] = card

        if let deckId = deckId, decksById[deckId] != nil {
            decksById[deckId]?.cardIds.append(card.id)
        }

        NotificationCenter.default.post(name: .flashcardsDidChange, object: nil)
        return card
    }

    /// Delete a card by ID. Returns true if found and deleted.
    @discardableResult
    func deleteCard(_ cardId: String) -> Bool {
        guard cardsById.removeValue(forKey: cardId) != nil else { return false }
        // Remove from all decks
        for (id, _) in decksById {
            decksById[id]?.cardIds.removeAll { $0 == cardId }
        }
        NotificationCenter.default.post(name: .flashcardsDidChange, object: nil)
        return true
    }

    /// Get a card by ID.
    func getCard(_ cardId: String) -> Flashcard? {
        cardsById[cardId]
    }

    /// Get all cards with optional filters.
    func getAllCards(type: FlashcardType? = nil, articleId: String? = nil,
                    dueOnly: Bool = false) -> [Flashcard] {
        var results = Array(cardsById.values)
        if let type = type {
            results = results.filter { $0.type == type }
        }
        if let articleId = articleId {
            results = results.filter { $0.articleId == articleId }
        }
        if dueOnly {
            results = results.filter { $0.isDue }
        }
        return results.sorted { $0.createdDate < $1.createdDate }
    }

    // MARK: - Deck Management

    /// Create a named deck. Returns nil if name is empty or duplicate.
    @discardableResult
    func createDeck(name: String, description: String? = nil) -> FlashcardDeck? {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        let lower = trimmed.lowercased()
        guard !decksById.values.contains(where: { $0.name.lowercased() == lower }) else { return nil }

        let deck = FlashcardDeck(name: trimmed, description: description)
        decksById[deck.id] = deck
        return deck
    }

    /// Delete a deck by ID. Returns true if found.
    @discardableResult
    func deleteDeck(_ deckId: String) -> Bool {
        decksById.removeValue(forKey: deckId) != nil
    }

    /// Get a deck by ID.
    func getDeck(_ deckId: String) -> FlashcardDeck? {
        decksById[deckId]
    }

    /// Get all decks sorted by name.
    func getAllDecks() -> [FlashcardDeck] {
        Array(decksById.values).sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    /// Add a card to a deck. Returns false if card/deck not found or already in deck.
    @discardableResult
    func addCardToDeck(cardId: String, deckId: String) -> Bool {
        guard cardsById[cardId] != nil, decksById[deckId] != nil else { return false }
        guard !(decksById[deckId]?.cardIds.contains(cardId) ?? true) else { return false }
        decksById[deckId]?.cardIds.append(cardId)
        return true
    }

    /// Remove a card from a deck. Returns false if not found.
    @discardableResult
    func removeCardFromDeck(cardId: String, deckId: String) -> Bool {
        guard decksById[deckId] != nil else { return false }
        let before = decksById[deckId]?.cardIds.count ?? 0
        decksById[deckId]?.cardIds.removeAll { $0 == cardId }
        return (decksById[deckId]?.cardIds.count ?? 0) < before
    }

    /// Get all cards in a deck.
    func getCardsInDeck(_ deckId: String) -> [Flashcard] {
        guard let deck = decksById[deckId] else { return [] }
        return deck.cardIds.compactMap { cardsById[$0] }
    }

    /// Get due cards in a deck.
    func getDueCardsInDeck(_ deckId: String) -> [Flashcard] {
        getCardsInDeck(deckId).filter { $0.isDue }
    }

    // MARK: - SM-2 Review

    /// Review a card with a difficulty rating. Returns updated card or nil.
    @discardableResult
    func reviewCard(_ cardId: String, difficulty: ReviewDifficulty) -> Flashcard? {
        guard let card = cardsById[cardId] else { return nil }

        card.totalReviews += 1
        if difficulty.isCorrect {
            card.correctReviews += 1
        }

        // SM-2 algorithm
        let q = Double(difficulty.rawValue)

        if difficulty.isCorrect {
            switch card.repetitions {
            case 0: card.interval = 1
            case 1: card.interval = 6
            default: card.interval = Int(round(Double(card.interval) * card.easeFactor))
            }
            card.repetitions += 1
        } else {
            card.repetitions = 0
            card.interval = 1
        }

        // Update ease factor: EF' = EF + (0.1 - (5-q) * (0.08 + (5-q) * 0.02))
        let efDelta = 0.1 - (5.0 - q) * (0.08 + (5.0 - q) * 0.02)
        card.easeFactor = max(1.3, card.easeFactor + efDelta)

        // Schedule next review
        card.nextReviewDate = calendar.date(byAdding: .day, value: card.interval, to: Date()) ?? Date()

        // Track review date for streaks
        let today = dateFormatter.string(from: Date())
        reviewDates.insert(today)

        NotificationCenter.default.post(name: .flashcardsDidChange, object: nil)
        return card
    }

    // MARK: - Review Sessions

    /// Complete a review session. Returns nil if empty or all invalid.
    @discardableResult
    func completeReviewSession(reviews: [(String, ReviewDifficulty, Double)]) -> ReviewSessionResult? {
        guard !reviews.isEmpty else { return nil }

        var cardResults: [CardReviewResult] = []
        var correctCount = 0
        var totalDifficulty = 0.0
        var totalDuration = 0.0

        for (cardId, difficulty, duration) in reviews {
            guard cardsById[cardId] != nil else { continue }
            reviewCard(cardId, difficulty: difficulty)
            if difficulty.isCorrect { correctCount += 1 }
            totalDifficulty += Double(difficulty.rawValue)
            totalDuration += duration
            cardResults.append(CardReviewResult(cardId: cardId, difficulty: difficulty,
                                                 durationSeconds: duration))
        }

        guard !cardResults.isEmpty else { return nil }

        let result = ReviewSessionResult(
            sessionDate: Date(),
            cardsReviewed: cardResults.count,
            correctCount: correctCount,
            averageDifficulty: totalDifficulty / Double(cardResults.count),
            durationSeconds: totalDuration,
            cardResults: cardResults
        )

        sessionHistory.append(result)
        return result
    }

    /// Get session history, most recent first.
    func getSessionHistory(limit: Int? = nil) -> [ReviewSessionResult] {
        let sorted = sessionHistory.sorted { $0.sessionDate > $1.sessionDate }
        if let limit = limit {
            return Array(sorted.prefix(limit))
        }
        return sorted
    }

    // MARK: - Statistics

    /// Get aggregate learning statistics.
    func getStats(deckId: String? = nil) -> LearningStats {
        let cards: [Flashcard]
        if let deckId = deckId {
            cards = getCardsInDeck(deckId)
        } else {
            cards = Array(cardsById.values)
        }

        let newCards = cards.filter { $0.isNew }.count
        let dueToday = cards.filter { $0.isDue }.count
        let mastered = cards.filter { $0.masteryLevel == "Mastered" }.count
        let avgEF = cards.isEmpty ? 0.0 : cards.map { $0.easeFactor }.reduce(0, +) / Double(cards.count)
        let totalReviews = cards.map { $0.totalReviews }.reduce(0, +)

        var byType: [FlashcardType: Int] = [:]
        for card in cards {
            byType[card.type, default: 0] += 1
        }

        let (current, longest) = calculateStreaks()

        return LearningStats(
            totalCards: cards.count,
            newCards: newCards,
            dueToday: dueToday,
            masteredCards: mastered,
            averageEaseFactor: avgEF,
            totalReviews: totalReviews,
            currentStreak: current,
            longestStreak: longest,
            byType: byType
        )
    }

    /// Get the hardest cards (lowest ease factor, most failures).
    func getHardestCards(limit: Int = 10) -> [Flashcard] {
        Array(cardsById.values)
            .filter { $0.totalReviews > 0 }
            .sorted { $0.easeFactor < $1.easeFactor }
            .prefix(limit)
            .map { $0 }
    }

    /// Get review forecast for upcoming days.
    func getReviewForecast(days: Int) -> [DayForecast] {
        let today = calendar.startOfDay(for: Date())
        var forecast: [DayForecast] = []

        for offset in 0..<days {
            let day = calendar.date(byAdding: .day, value: offset, to: today)!
            let nextDay = calendar.date(byAdding: .day, value: 1, to: day)!
            let count = cardsById.values.filter { card in
                card.nextReviewDate >= day && card.nextReviewDate < nextDay
            }.count
            forecast.append(DayForecast(date: day, count: count))
        }

        return forecast
    }

    // MARK: - Report

    /// Generate a text report.
    func generateReport(deckId: String? = nil) -> String {
        let stats = getStats(deckId: deckId)
        var lines: [String] = []

        if let deckId = deckId, let deck = decksById[deckId] {
            lines.append("📚 Flashcard Report — \(deck.name)")
        } else {
            lines.append("📚 Flashcard Report")
        }
        lines.append("═══════════════════════════════")
        lines.append("Cards: \(stats.totalCards) | New: \(stats.newCards) | Due Today: \(stats.dueToday)")
        lines.append("Mastered: \(stats.masteredCards) | Reviews: \(stats.totalReviews)")
        lines.append("Streak: \(stats.currentStreak) days (Best: \(stats.longestStreak))")

        if !stats.byType.isEmpty {
            lines.append("")
            lines.append("By Type:")
            for type in FlashcardType.allCases {
                if let count = stats.byType[type], count > 0 {
                    lines.append("  \(type.rawValue.capitalized): \(count)")
                }
            }
        }

        return lines.joined(separator: "\n")
    }

    // MARK: - Export / Import

    /// Export all data as JSON string.
    func exportJSON() -> String? {
        let store = FlashcardStore(
            cards: Array(cardsById.values),
            decks: Array(decksById.values),
            sessionHistory: sessionHistory,
            reviewDates: Array(reviewDates)
        )
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = .prettyPrinted
        guard let data = try? encoder.encode(store) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    /// Import from JSON string, merging with existing data. Returns success.
    @discardableResult
    func importJSON(_ json: String) -> Bool {
        guard let data = json.data(using: .utf8) else { return false }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let store = try? decoder.decode(FlashcardStore.self, from: data) else { return false }

        for card in store.cards {
            if cardsById[card.id] == nil {
                cardsById[card.id] = card
            }
        }
        for deck in store.decks {
            if decksById[deck.id] == nil {
                decksById[deck.id] = deck
            }
        }
        sessionHistory.append(contentsOf: store.sessionHistory)
        reviewDates.formUnion(store.reviewDates)

        NotificationCenter.default.post(name: .flashcardsDidChange, object: nil)
        return true
    }

    // MARK: - Private Helpers

    private func splitSentences(_ text: String) -> [String] {
        var sentences: [String] = []
        text.enumerateSubstrings(in: text.startIndex..., options: .bySentences) { substring, _, _, _ in
            if let s = substring?.trimmingCharacters(in: .whitespacesAndNewlines), !s.isEmpty {
                sentences.append(s)
            }
        }
        return sentences
    }

    private func extractFromSentence(_ sentence: String, articleId: String, articleTitle: String) -> [Flashcard] {
        var cards: [Flashcard] = []
        let lower = sentence.lowercased()

        // Definition patterns
        if let card = extractDefinition(sentence, lower: lower, articleId: articleId, articleTitle: articleTitle) {
            cards.append(card)
        }

        // Statistic patterns
        if let card = extractStatistic(sentence, lower: lower, articleId: articleId, articleTitle: articleTitle) {
            cards.append(card)
        }

        // Comparison patterns
        if let card = extractComparison(sentence, lower: lower, articleId: articleId, articleTitle: articleTitle) {
            cards.append(card)
        }

        // Process patterns
        if let card = extractProcess(sentence, lower: lower, articleId: articleId, articleTitle: articleTitle) {
            cards.append(card)
        }

        // Fact patterns
        if let card = extractFact(sentence, lower: lower, articleId: articleId, articleTitle: articleTitle) {
            cards.append(card)
        }

        return cards
    }

    private func extractDefinition(_ sentence: String, lower: String,
                                    articleId: String, articleTitle: String) -> Flashcard? {
        let patterns: [(String, Bool)] = [
            (" is defined as ", true),
            (" is a ", true),
            (" is an ", true),
            (" refers to ", true),
            (" is known as ", true),
            (" are defined as ", true),
        ]

        for (pattern, _) in patterns {
            guard let range = lower.range(of: pattern) else { continue }
            let subject = String(sentence[sentence.startIndex..<range.lowerBound])
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let definition = String(sentence[range.upperBound...])
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .trimmingCharacters(in: CharacterSet(charactersIn: "."))

            guard !subject.isEmpty, !definition.isEmpty else { continue }
            guard subject.split(separator: " ").count <= 8 else { continue }

            // Skip filler subjects
            let subjectLower = subject.lowercased()
            if ArticleFlashcardGenerator.fillerSubjects.contains(subjectLower) { continue }

            let front = "What is \(subject)?"
            let back = definition
            return Flashcard(front: front, back: back, type: .definition,
                           articleId: articleId, articleTitle: articleTitle)
        }

        return nil
    }

    private func extractStatistic(_ sentence: String, lower: String,
                                   articleId: String, articleTitle: String) -> Flashcard? {
        let statPatterns = [
            "\\d+(\\.\\d+)?\\s*(percent|%)",
            "\\d+(\\.\\d+)?\\s*(million|billion|trillion)",
            "grew by \\d+",
            "increased by \\d+",
            "decreased by \\d+",
            "reached \\d+",
        ]

        for pattern in statPatterns {
            if lower.range(of: pattern, options: .regularExpression) != nil {
                let front = "What statistic was reported? (from \(articleTitle))"
                return Flashcard(front: front, back: sentence, type: .statistic,
                               articleId: articleId, articleTitle: articleTitle)
            }
        }

        return nil
    }

    private func extractComparison(_ sentence: String, lower: String,
                                    articleId: String, articleTitle: String) -> Flashcard? {
        let patterns = ["unlike ", "compared to ", "in contrast to ", "whereas ",
                        "while ", "on the other hand"]

        for pattern in patterns {
            if lower.hasPrefix(pattern) || lower.contains(", \(pattern)") || lower.contains(" \(pattern)") {
                // More precise check for "while" to avoid false positives
                if pattern == "while " && !lower.hasPrefix("while ") { continue }

                let front = "What comparison was made? (from \(articleTitle))"
                return Flashcard(front: front, back: sentence, type: .comparison,
                               articleId: articleId, articleTitle: articleTitle)
            }
        }

        return nil
    }

    private func extractProcess(_ sentence: String, lower: String,
                                 articleId: String, articleTitle: String) -> Flashcard? {
        let patterns = ["the process ", "the first step ", "begins with ",
                        "starts with ", "the procedure "]

        for pattern in patterns {
            if lower.contains(pattern) {
                let front = "Describe the process mentioned in \(articleTitle)."
                return Flashcard(front: front, back: sentence, type: .process,
                               articleId: articleId, articleTitle: articleTitle)
            }
        }

        return nil
    }

    private func extractFact(_ sentence: String, lower: String,
                              articleId: String, articleTitle: String) -> Flashcard? {
        let patterns = ["research shows ", "studies show ", "according to ",
                        "was founded in ", "was established in ",
                        "research indicates ", "evidence suggests "]

        for pattern in patterns {
            if lower.contains(pattern) {
                let front = "What key fact was stated? (from \(articleTitle))"
                return Flashcard(front: front, back: sentence, type: .fact,
                               articleId: articleId, articleTitle: articleTitle)
            }
        }

        return nil
    }

    private func calculateStreaks() -> (current: Int, longest: Int) {
        guard !reviewDates.isEmpty else { return (0, 0) }

        let sorted = reviewDates.compactMap { dateFormatter.date(from: $0) }.sorted()
        guard !sorted.isEmpty else { return (0, 0) }

        let today = calendar.startOfDay(for: Date())
        var current = 0
        var longest = 0
        var streak = 1

        // Check if today has a review
        let lastDate = calendar.startOfDay(for: sorted.last!)
        let daysSinceLast = calendar.dateComponents([.day], from: lastDate, to: today).day ?? 0

        if daysSinceLast > 1 {
            // Streak is broken
            current = 0
        }

        // Calculate streaks
        for i in stride(from: sorted.count - 1, to: 0, by: -1) {
            let d1 = calendar.startOfDay(for: sorted[i])
            let d2 = calendar.startOfDay(for: sorted[i - 1])
            let diff = calendar.dateComponents([.day], from: d2, to: d1).day ?? 0

            if diff == 1 {
                streak += 1
            } else if diff > 1 {
                longest = max(longest, streak)
                if current == 0 && daysSinceLast <= 1 {
                    current = streak
                }
                streak = 1
            }
            // diff == 0 means same day, continue
        }

        longest = max(longest, streak)
        if current == 0 && daysSinceLast <= 1 {
            current = streak
        }

        return (current, longest)
    }
}

// MARK: - Day Forecast

struct DayForecast {
    let date: Date
    let count: Int
}
