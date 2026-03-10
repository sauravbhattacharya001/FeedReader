//
//  ArticleFlashcardGenerator.swift
//  FeedReader
//
//  Generates spaced-repetition flashcards from article content.
//  Extracts key facts, definitions, and statistics from article text,
//  then manages review scheduling using the SM-2 algorithm.
//
//  Features:
//  - Automatic flashcard extraction from article text
//  - Definition/fact/statistic pattern detection
//  - SM-2 spaced repetition scheduling
//  - Deck management with article grouping
//  - Review sessions with difficulty ratings
//  - Learning statistics and progress tracking
//  - JSON persistence
//

import Foundation

// MARK: - Models

/// Difficulty rating for a flashcard review (SM-2 scale).
enum ReviewDifficulty: Int, Codable {
    case blackout = 0      // Complete blackout
    case incorrect = 1     // Incorrect but recognized answer
    case hard = 2          // Incorrect but easy to recall once shown
    case difficult = 3     // Correct with serious difficulty
    case hesitant = 4      // Correct after hesitation
    case perfect = 5       // Perfect response
}

/// Type of flashcard content.
enum FlashcardType: String, Codable {
    case definition      // "X is Y" patterns
    case fact            // Key factual statements
    case statistic       // Numerical data points
    case concept         // Abstract concept explanations
    case comparison      // "X vs Y" or "unlike X, Y" patterns
    case process         // Step/process descriptions
    case custom          // User-created cards
}

/// A single flashcard with front (question) and back (answer).
struct Flashcard: Codable, Equatable {
    let id: String
    let front: String
    let back: String
    let type: FlashcardType
    let articleId: String
    let articleTitle: String
    let createdAt: Date

    // SM-2 scheduling fields
    var easeFactor: Double   // Starts at 2.5
    var interval: Int        // Days until next review
    var repetitions: Int     // Consecutive correct reviews
    var nextReviewDate: Date
    var lastReviewDate: Date?
    var totalReviews: Int
    var correctReviews: Int

    var isNew: Bool { return totalReviews == 0 }
    var isDue: Bool { return nextReviewDate <= Date() }

    var accuracy: Double {
        guard totalReviews > 0 else { return 0.0 }
        return Double(correctReviews) / Double(totalReviews)
    }

    var masteryLevel: String {
        if totalReviews == 0 { return "New" }
        if easeFactor >= 2.5 && repetitions >= 5 { return "Mastered" }
        if easeFactor >= 2.0 && repetitions >= 3 { return "Learning" }
        if repetitions >= 1 { return "Reviewing" }
        return "Struggling"
    }

    init(id: String = UUID().uuidString,
         front: String,
         back: String,
         type: FlashcardType,
         articleId: String,
         articleTitle: String,
         createdAt: Date = Date()) {
        self.id = id
        self.front = front
        self.back = back
        self.type = type
        self.articleId = articleId
        self.articleTitle = articleTitle
        self.createdAt = createdAt
        self.easeFactor = 2.5
        self.interval = 0
        self.repetitions = 0
        self.nextReviewDate = createdAt
        self.lastReviewDate = nil
        self.totalReviews = 0
        self.correctReviews = 0
    }

    static func == (lhs: Flashcard, rhs: Flashcard) -> Bool {
        return lhs.id == rhs.id
    }
}

/// A collection of flashcards grouped by topic or article.
struct FlashcardDeck: Codable {
    let id: String
    let name: String
    let description: String
    let createdAt: Date
    var cardIds: [String]

    var cardCount: Int { return cardIds.count }

    init(id: String = UUID().uuidString,
         name: String,
         description: String = "",
         createdAt: Date = Date(),
         cardIds: [String] = []) {
        self.id = id
        self.name = name
        self.description = description
        self.createdAt = createdAt
        self.cardIds = cardIds
    }
}

/// Result of a review session.
struct ReviewSessionResult: Codable {
    let sessionDate: Date
    let cardsReviewed: Int
    let correctCount: Int
    let averageDifficulty: Double
    let durationSeconds: TimeInterval
    let cardResults: [CardReviewResult]

    var accuracy: Double {
        guard cardsReviewed > 0 else { return 0.0 }
        return Double(correctCount) / Double(cardsReviewed)
    }

    var grade: String {
        let pct = accuracy * 100
        if pct >= 90 { return "A" }
        if pct >= 80 { return "B" }
        if pct >= 70 { return "C" }
        if pct >= 60 { return "D" }
        return "F"
    }
}

/// Individual card result within a session.
struct CardReviewResult: Codable {
    let cardId: String
    let difficulty: ReviewDifficulty
    let responseTimeSeconds: TimeInterval
}

/// Learning statistics for a deck or all cards.
struct LearningStats: Codable {
    let totalCards: Int
    let newCards: Int
    let learningCards: Int
    let reviewingCards: Int
    let masteredCards: Int
    let strugglingCards: Int
    let dueToday: Int
    let averageEaseFactor: Double
    let averageAccuracy: Double
    let totalReviewSessions: Int
    let currentStreak: Int
    let longestStreak: Int
    let cardsPerDay: Double
}

/// Extraction result from article analysis.
struct ExtractionResult {
    let flashcards: [Flashcard]
    let articleId: String
    let articleTitle: String
    let sentenceCount: Int
    let extractedCount: Int
}

// MARK: - Flashcard Generator Service

/// Generates and manages spaced-repetition flashcards from article content.
class ArticleFlashcardGenerator {

    // MARK: - Storage

    private var cards: [String: Flashcard] = [:]
    private var decks: [String: FlashcardDeck] = [:]
    private var sessionHistory: [ReviewSessionResult] = []
    private var reviewDates: [String] = [] // YYYY-MM-DD for streak tracking (sorted)
    private var reviewDatesSet: Set<String> = [] // O(1) companion for contains() lookups

    // MARK: - Configuration

    /// Minimum sentence length to consider for extraction.
    let minSentenceWords: Int

    /// Maximum cards to extract per article.
    let maxCardsPerArticle: Int

    // MARK: - Init

    init(minSentenceWords: Int = 5, maxCardsPerArticle: Int = 20) {
        self.minSentenceWords = max(3, minSentenceWords)
        self.maxCardsPerArticle = max(1, maxCardsPerArticle)
    }

    // MARK: - Card Extraction

    /// Extract flashcards from an article.
    func generateCards(articleId: String, title: String, body: String) -> ExtractionResult {
        let sentences = splitSentences(body)
        var extracted: [Flashcard] = []

        for sentence in sentences {
            let words = sentence.split(separator: " ")
            guard words.count >= minSentenceWords else { continue }
            guard extracted.count < maxCardsPerArticle else { break }

            if let card = tryExtractDefinition(sentence, articleId: articleId, articleTitle: title) {
                extracted.append(card)
            } else if let card = tryExtractStatistic(sentence, articleId: articleId, articleTitle: title) {
                extracted.append(card)
            } else if let card = tryExtractComparison(sentence, articleId: articleId, articleTitle: title) {
                extracted.append(card)
            } else if let card = tryExtractProcess(sentence, articleId: articleId, articleTitle: title) {
                extracted.append(card)
            } else if let card = tryExtractFact(sentence, articleId: articleId, articleTitle: title) {
                extracted.append(card)
            }
        }

        // De-duplicate by front text
        var seen = Set<String>()
        var unique: [Flashcard] = []
        for card in extracted {
            let key = card.front.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
            if !seen.contains(key) {
                seen.insert(key)
                unique.append(card)
            }
        }

        return ExtractionResult(
            flashcards: unique,
            articleId: articleId,
            articleTitle: title,
            sentenceCount: sentences.count,
            extractedCount: unique.count
        )
    }

    /// Add extracted cards to storage and optionally to a deck.
    func addCards(_ flashcards: [Flashcard], toDeck deckId: String? = nil) -> Int {
        var added = 0
        for card in flashcards {
            guard cards[card.id] == nil else { continue }
            cards[card.id] = card
            added += 1

            if let deckId = deckId, var deck = decks[deckId] {
                if !deck.cardIds.contains(card.id) {
                    deck.cardIds.append(card.id)
                    decks[deckId] = deck
                }
            }
        }
        return added
    }

    /// Create a custom flashcard.
    func createCustomCard(front: String, back: String, articleId: String = "custom",
                          articleTitle: String = "Custom", deckId: String? = nil) -> Flashcard? {
        let trimmedFront = front.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedBack = back.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedFront.isEmpty, !trimmedBack.isEmpty else { return nil }

        let card = Flashcard(front: trimmedFront, back: trimmedBack, type: .custom,
                             articleId: articleId, articleTitle: articleTitle)
        cards[card.id] = card

        if let deckId = deckId, var deck = decks[deckId] {
            deck.cardIds.append(card.id)
            decks[deckId] = deck
        }

        return card
    }

    /// Delete a card by ID.
    func deleteCard(_ cardId: String) -> Bool {
        guard cards.removeValue(forKey: cardId) != nil else { return false }
        // Remove from all decks
        for (deckId, var deck) in decks {
            deck.cardIds.removeAll { $0 == cardId }
            decks[deckId] = deck
        }
        return true
    }

    /// Get a card by ID.
    func getCard(_ cardId: String) -> Flashcard? {
        return cards[cardId]
    }

    /// Get all cards, optionally filtered.
    func getAllCards(type: FlashcardType? = nil, articleId: String? = nil,
                    dueOnly: Bool = false) -> [Flashcard] {
        var result = Array(cards.values)
        if let type = type {
            result = result.filter { $0.type == type }
        }
        if let articleId = articleId {
            result = result.filter { $0.articleId == articleId }
        }
        if dueOnly {
            result = result.filter { $0.isDue }
        }
        return result.sorted { $0.createdAt < $1.createdAt }
    }

    // MARK: - Deck Management

    /// Create a new deck.
    func createDeck(name: String, description: String = "") -> FlashcardDeck? {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        // Prevent duplicate deck names
        if decks.values.contains(where: { $0.name.lowercased() == trimmed.lowercased() }) {
            return nil
        }
        let deck = FlashcardDeck(name: trimmed, description: description)
        decks[deck.id] = deck
        return deck
    }

    /// Delete a deck (does not delete contained cards).
    func deleteDeck(_ deckId: String) -> Bool {
        return decks.removeValue(forKey: deckId) != nil
    }

    /// Get a deck by ID.
    func getDeck(_ deckId: String) -> FlashcardDeck? {
        return decks[deckId]
    }

    /// Get all decks.
    func getAllDecks() -> [FlashcardDeck] {
        return Array(decks.values).sorted { $0.name < $1.name }
    }

    /// Add a card to a deck.
    func addCardToDeck(cardId: String, deckId: String) -> Bool {
        guard cards[cardId] != nil else { return false }
        guard var deck = decks[deckId] else { return false }
        guard !deck.cardIds.contains(cardId) else { return false }
        deck.cardIds.append(cardId)
        decks[deckId] = deck
        return true
    }

    /// Remove a card from a deck (does not delete the card).
    func removeCardFromDeck(cardId: String, deckId: String) -> Bool {
        guard var deck = decks[deckId] else { return false }
        let before = deck.cardIds.count
        deck.cardIds.removeAll { $0 == cardId }
        decks[deckId] = deck
        return deck.cardIds.count < before
    }

    /// Get cards in a deck.
    func getCardsInDeck(_ deckId: String) -> [Flashcard] {
        guard let deck = decks[deckId] else { return [] }
        return deck.cardIds.compactMap { cards[$0] }
    }

    /// Get due cards in a deck.
    func getDueCardsInDeck(_ deckId: String) -> [Flashcard] {
        return getCardsInDeck(deckId).filter { $0.isDue }
    }

    // MARK: - SM-2 Spaced Repetition

    /// Review a card with a difficulty rating. Returns the updated card.
    /// Uses the SM-2 algorithm by Piotr Wozniak.
    func reviewCard(_ cardId: String, difficulty: ReviewDifficulty,
                    reviewDate: Date = Date()) -> Flashcard? {
        guard var card = cards[cardId] else { return nil }

        let q = Double(difficulty.rawValue)
        card.totalReviews += 1
        card.lastReviewDate = reviewDate

        if difficulty.rawValue >= 3 {
            // Correct response
            card.correctReviews += 1
            if card.repetitions == 0 {
                card.interval = 1
            } else if card.repetitions == 1 {
                card.interval = 6
            } else {
                card.interval = Int(round(Double(card.interval) * card.easeFactor))
            }
            card.repetitions += 1
        } else {
            // Incorrect — reset
            card.repetitions = 0
            card.interval = 1
        }

        // Update ease factor: EF' = EF + (0.1 - (5 - q) * (0.08 + (5 - q) * 0.02))
        let delta = 0.1 - (5.0 - q) * (0.08 + (5.0 - q) * 0.02)
        card.easeFactor = max(1.3, card.easeFactor + delta)

        // Schedule next review
        card.nextReviewDate = Calendar.current.date(
            byAdding: .day, value: card.interval, to: reviewDate
        ) ?? reviewDate.addingTimeInterval(TimeInterval(card.interval * 86400))

        cards[cardId] = card

        // Track review date for streaks
        let dateStr = formatDate(reviewDate)
        if !reviewDatesSet.contains(dateStr) {
            reviewDatesSet.insert(dateStr)
            reviewDates.append(dateStr)
            reviewDates.sort()
        }

        return card
    }

    /// Run a review session on due cards (or a specific deck).
    /// Takes an array of (cardId, difficulty, responseTimeSeconds) tuples.
    func completeReviewSession(
        reviews: [(cardId: String, difficulty: ReviewDifficulty, responseTime: TimeInterval)],
        sessionDate: Date = Date()
    ) -> ReviewSessionResult? {
        guard !reviews.isEmpty else { return nil }

        var cardResults: [CardReviewResult] = []
        var correctCount = 0
        var totalDifficulty = 0.0
        var totalTime: TimeInterval = 0

        for review in reviews {
            guard reviewCard(review.cardId, difficulty: review.difficulty, reviewDate: sessionDate) != nil else {
                continue
            }
            if review.difficulty.rawValue >= 3 {
                correctCount += 1
            }
            totalDifficulty += Double(review.difficulty.rawValue)
            totalTime += review.responseTime

            cardResults.append(CardReviewResult(
                cardId: review.cardId,
                difficulty: review.difficulty,
                responseTimeSeconds: review.responseTime
            ))
        }

        guard !cardResults.isEmpty else { return nil }

        let result = ReviewSessionResult(
            sessionDate: sessionDate,
            cardsReviewed: cardResults.count,
            correctCount: correctCount,
            averageDifficulty: totalDifficulty / Double(cardResults.count),
            durationSeconds: totalTime,
            cardResults: cardResults
        )

        sessionHistory.append(result)
        return result
    }

    // MARK: - Statistics

    /// Get learning statistics for all cards or a specific deck.
    func getStats(deckId: String? = nil) -> LearningStats {
        let allCards: [Flashcard]
        if let deckId = deckId {
            allCards = getCardsInDeck(deckId)
        } else {
            allCards = Array(cards.values)
        }

        let newCards = allCards.filter { $0.masteryLevel == "New" }.count
        let learning = allCards.filter { $0.masteryLevel == "Learning" }.count
        let reviewing = allCards.filter { $0.masteryLevel == "Reviewing" }.count
        let mastered = allCards.filter { $0.masteryLevel == "Mastered" }.count
        let struggling = allCards.filter { $0.masteryLevel == "Struggling" }.count
        let dueToday = allCards.filter { $0.isDue }.count

        let avgEF = allCards.isEmpty ? 0.0 :
            allCards.map { $0.easeFactor }.reduce(0, +) / Double(allCards.count)
        let avgAcc = allCards.isEmpty ? 0.0 :
            allCards.filter { $0.totalReviews > 0 }.map { $0.accuracy }.reduce(0, +) /
            max(1, Double(allCards.filter { $0.totalReviews > 0 }.count))

        let streak = calculateStreak()
        let longestStreak = calculateLongestStreak()

        // Cards per day (over last 7 days)
        let sevenDaysAgo = Calendar.current.date(byAdding: .day, value: -7, to: Date()) ?? Date()
        let recentSessions = sessionHistory.filter { $0.sessionDate >= sevenDaysAgo }
        let recentReviewed = recentSessions.map { $0.cardsReviewed }.reduce(0, +)
        let cardsPerDay = Double(recentReviewed) / 7.0

        return LearningStats(
            totalCards: allCards.count,
            newCards: newCards,
            learningCards: learning,
            reviewingCards: reviewing,
            masteredCards: mastered,
            strugglingCards: struggling,
            dueToday: dueToday,
            averageEaseFactor: avgEF,
            averageAccuracy: avgAcc,
            totalReviewSessions: sessionHistory.count,
            currentStreak: streak,
            longestStreak: longestStreak,
            cardsPerDay: cardsPerDay
        )
    }

    /// Get review session history.
    func getSessionHistory(limit: Int? = nil) -> [ReviewSessionResult] {
        let sorted = sessionHistory.sorted { $0.sessionDate > $1.sessionDate }
        if let limit = limit {
            return Array(sorted.prefix(limit))
        }
        return sorted
    }

    /// Get the hardest cards (lowest ease factor among reviewed cards).
    func getHardestCards(limit: Int = 5) -> [Flashcard] {
        return cards.values
            .filter { $0.totalReviews > 0 }
            .sorted { $0.easeFactor < $1.easeFactor }
            .prefix(limit)
            .map { $0 }
    }

    /// Get upcoming review schedule: how many cards are due each day for the next N days.
    func getReviewForecast(days: Int = 7) -> [(date: String, count: Int)] {
        var forecast: [(date: String, count: Int)] = []
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())

        for dayOffset in 0..<max(1, days) {
            guard let date = calendar.date(byAdding: .day, value: dayOffset, to: today) else { continue }
            let nextDay = calendar.date(byAdding: .day, value: 1, to: date) ?? date
            let count = cards.values.filter { card in
                card.nextReviewDate >= date && card.nextReviewDate < nextDay
            }.count
            forecast.append((date: formatDate(date), count: count))
        }

        return forecast
    }

    /// Text report of learning progress.
    func generateReport(deckId: String? = nil) -> String {
        let stats = getStats(deckId: deckId)
        let deckName = deckId.flatMap { decks[$0]?.name } ?? "All Cards"
        var lines: [String] = []

        lines.append("=== Flashcard Report: \(deckName) ===")
        lines.append("")
        lines.append("Cards: \(stats.totalCards) total")
        lines.append("  New: \(stats.newCards)")
        lines.append("  Learning: \(stats.learningCards)")
        lines.append("  Reviewing: \(stats.reviewingCards)")
        lines.append("  Mastered: \(stats.masteredCards)")
        lines.append("  Struggling: \(stats.strugglingCards)")
        lines.append("")
        lines.append("Due Today: \(stats.dueToday)")
        lines.append("Avg Ease Factor: \(String(format: "%.2f", stats.averageEaseFactor))")
        lines.append("Avg Accuracy: \(String(format: "%.0f%%", stats.averageAccuracy * 100))")
        lines.append("")
        lines.append("Review Sessions: \(stats.totalReviewSessions)")
        lines.append("Current Streak: \(stats.currentStreak) days")
        lines.append("Longest Streak: \(stats.longestStreak) days")
        lines.append("Cards/Day (7d avg): \(String(format: "%.1f", stats.cardsPerDay))")

        if !getHardestCards(limit: 3).isEmpty {
            lines.append("")
            lines.append("--- Hardest Cards ---")
            for card in getHardestCards(limit: 3) {
                lines.append("  EF=\(String(format: "%.2f", card.easeFactor)): \(card.front)")
            }
        }

        let forecast = getReviewForecast(days: 5)
        if !forecast.isEmpty {
            lines.append("")
            lines.append("--- Upcoming Reviews ---")
            for entry in forecast {
                lines.append("  \(entry.date): \(entry.count) cards")
            }
        }

        return lines.joined(separator: "\n")
    }

    // MARK: - Persistence

    /// Export all data as JSON.
    func exportJSON() -> String? {
        let data = PersistenceData(
            cards: Array(cards.values).sorted { $0.createdAt < $1.createdAt },
            decks: Array(decks.values).sorted { $0.name < $1.name },
            sessionHistory: sessionHistory,
            reviewDates: reviewDates
        )
        let encoder = JSONCoding.iso8601PrettyUnsortedEncoder
        guard let jsonData = try? encoder.encode(data) else { return nil }
        return String(data: jsonData, encoding: .utf8)
    }

    /// Import data from JSON.
    func importJSON(_ json: String) -> Bool {
        // Size guard: reject input larger than 10 MB to prevent OOM
        // on adversarial or accidentally huge payloads (CWE-400).
        guard json.utf8.count <= 10_485_760 else { return false }

        guard let jsonData = json.data(using: .utf8) else { return false }
        let decoder = JSONCoding.iso8601Decoder
        guard let data = try? decoder.decode(PersistenceData.self, from: jsonData) else { return false }

        for card in data.cards {
            cards[card.id] = card
        }
        for deck in data.decks {
            decks[deck.id] = deck
        }
        sessionHistory.append(contentsOf: data.sessionHistory)
        for date in data.reviewDates {
            if !reviewDatesSet.contains(date) {
                reviewDatesSet.insert(date)
                reviewDates.append(date)
            }
        }
        reviewDates.sort()
        return true
    }

    // MARK: - Pattern Extraction (Private)

    private func tryExtractDefinition(_ sentence: String, articleId: String, articleTitle: String) -> Flashcard? {
        let lower = sentence.lowercased()

        // Pattern: "X is/are Y" where X is short and Y is descriptive
        let definitionPatterns = [
            "is defined as", "is a type of", "refers to", "is known as",
            "can be described as", "is the process of", "is a form of",
            "are defined as", "are known as"
        ]

        for pattern in definitionPatterns {
            if let range = lower.range(of: pattern) {
                let subject = String(sentence[sentence.startIndex..<range.lowerBound])
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                let definition = String(sentence[range.upperBound...])
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                    .trimmingCharacters(in: CharacterSet(charactersIn: "."))

                guard subject.split(separator: " ").count >= 1,
                      subject.split(separator: " ").count <= 8,
                      definition.split(separator: " ").count >= 3 else { continue }

                return Flashcard(
                    front: "What \(pattern) \(subject.lowercased())?",
                    back: definition,
                    type: .definition,
                    articleId: articleId,
                    articleTitle: articleTitle
                )
            }
        }

        // Pattern: "X is Y" (simpler, only if Y is substantial)
        let isPatterns: [(String, String)] = [
            (" is a ", "What is "), (" is an ", "What is "),
            (" is the ", "What is "), (" are a ", "What are "),
            (" are the ", "What are ")
        ]

        for (pattern, questionPrefix) in isPatterns {
            if let range = lower.range(of: pattern) {
                let subject = String(sentence[sentence.startIndex..<range.lowerBound])
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                let definition = String(sentence[range.lowerBound...])
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                    .trimmingCharacters(in: CharacterSet(charactersIn: "."))

                let subjectWords = subject.split(separator: " ").count
                let defWords = definition.split(separator: " ").count
                guard subjectWords >= 1, subjectWords <= 6,
                      defWords >= 4 else { continue }

                // Skip if subject starts with common filler
                let skipPrefixes = ["it", "this", "that", "there", "here", "he", "she", "they", "we", "i"]
                if skipPrefixes.contains(subject.lowercased().split(separator: " ").first.map(String.init) ?? "") {
                    continue
                }

                return Flashcard(
                    front: "\(questionPrefix)\(subject.lowercased())?",
                    back: subject + definition,
                    type: .definition,
                    articleId: articleId,
                    articleTitle: articleTitle
                )
            }
        }

        return nil
    }

    private func tryExtractStatistic(_ sentence: String, articleId: String, articleTitle: String) -> Flashcard? {
        // Look for sentences with numbers + context
        let numPattern = try? NSRegularExpression(
            pattern: "\\b(\\d+(?:\\.\\d+)?(?:\\s*(?:%|percent|billion|million|thousand|trillion)))\\b",
            options: .caseInsensitive
        )

        let range = NSRange(sentence.startIndex..., in: sentence)
        guard let match = numPattern?.firstMatch(in: sentence, options: [], range: range) else { return nil }

        // Must have enough context around the number
        guard sentence.split(separator: " ").count >= 6 else { return nil }

        let matchedNumber = String(sentence[Range(match.range(at: 1), in: sentence)!])

        // Build question: remove the number and ask about it
        let cleaned = sentence.trimmingCharacters(in: CharacterSet(charactersIn: "."))
        return Flashcard(
            front: "According to \"\(articleTitle)\", what statistic is mentioned? (\(cleaned.prefix(50))...)",
            back: cleaned,
            type: .statistic,
            articleId: articleId,
            articleTitle: articleTitle
        )
    }

    private func tryExtractComparison(_ sentence: String, articleId: String, articleTitle: String) -> Flashcard? {
        let lower = sentence.lowercased()

        let comparisonIndicators = [
            "unlike", "compared to", "in contrast to", "whereas",
            "while", "on the other hand", "as opposed to",
            "differs from", "different from", "similar to but",
            "more than", "less than", "better than", "worse than"
        ]

        for indicator in comparisonIndicators {
            if lower.contains(indicator) {
                let cleaned = sentence.trimmingCharacters(in: CharacterSet(charactersIn: "."))
                guard cleaned.split(separator: " ").count >= 6 else { continue }

                return Flashcard(
                    front: "What comparison is made? (\(cleaned.prefix(40))...)",
                    back: cleaned,
                    type: .comparison,
                    articleId: articleId,
                    articleTitle: articleTitle
                )
            }
        }

        return nil
    }

    private func tryExtractProcess(_ sentence: String, articleId: String, articleTitle: String) -> Flashcard? {
        let lower = sentence.lowercased()

        let processIndicators = [
            "the first step", "the process begins", "starts with",
            "followed by", "the next step", "finally,",
            "in order to", "the procedure", "the method involves",
            "by first", "then,"
        ]

        for indicator in processIndicators {
            if lower.contains(indicator) {
                let cleaned = sentence.trimmingCharacters(in: CharacterSet(charactersIn: "."))
                guard cleaned.split(separator: " ").count >= 6 else { continue }

                return Flashcard(
                    front: "Describe this process step: (\(cleaned.prefix(40))...)",
                    back: cleaned,
                    type: .process,
                    articleId: articleId,
                    articleTitle: articleTitle
                )
            }
        }

        return nil
    }

    private func tryExtractFact(_ sentence: String, articleId: String, articleTitle: String) -> Flashcard? {
        let lower = sentence.lowercased()

        // Only extract if the sentence seems factual (not opinion/speculation)
        let factIndicators = [
            "research shows", "studies have", "according to",
            "scientists found", "data suggests", "evidence indicates",
            "was discovered", "was developed", "was invented",
            "was founded", "was established", "was created",
            "is caused by", "results in", "leads to",
            "consists of", "is composed of", "is made up of"
        ]

        for indicator in factIndicators {
            if lower.contains(indicator) {
                let cleaned = sentence.trimmingCharacters(in: CharacterSet(charactersIn: "."))
                guard cleaned.split(separator: " ").count >= 6 else { continue }

                return Flashcard(
                    front: "What fact is stated? (\(cleaned.prefix(50))...)",
                    back: cleaned,
                    type: .fact,
                    articleId: articleId,
                    articleTitle: articleTitle
                )
            }
        }

        return nil
    }

    // MARK: - Text Processing Helpers

    private func splitSentences(_ text: String) -> [String] {
        var sentences: [String] = []
        let cleaned = text.replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "\r", with: " ")
            .replacingOccurrences(of: "  ", with: " ")

        // Split on sentence boundaries
        let terminators: [Character] = [".", "!", "?"]
        var current = ""
        for char in cleaned {
            current.append(char)
            if terminators.contains(char) {
                let trimmed = current.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty {
                    sentences.append(trimmed)
                }
                current = ""
            }
        }
        // Don't forget remaining text without terminal punctuation
        let remaining = current.trimmingCharacters(in: .whitespacesAndNewlines)
        if !remaining.isEmpty && remaining.split(separator: " ").count >= minSentenceWords {
            sentences.append(remaining)
        }

        return sentences
    }

    private static let iso8601DayFormatter = DateFormatting.isoDate

    private func formatDate(_ date: Date) -> String {
        return Self.iso8601DayFormatter.string(from: date)
    }

    private func calculateStreak() -> Int {
        guard !reviewDates.isEmpty else { return 0 }
        let today = formatDate(Date())
        let yesterday = formatDate(Calendar.current.date(byAdding: .day, value: -1, to: Date()) ?? Date())

        // Must have reviewed today or yesterday to have an active streak
        guard reviewDatesSet.contains(today) || reviewDatesSet.contains(yesterday) else { return 0 }

        var streak = 0
        let startDate = reviewDatesSet.contains(today) ? Date() :
            (Calendar.current.date(byAdding: .day, value: -1, to: Date()) ?? Date())

        var checkDate = startDate
        while true {
            let dateStr = formatDate(checkDate)
            if reviewDatesSet.contains(dateStr) {
                streak += 1
                checkDate = Calendar.current.date(byAdding: .day, value: -1, to: checkDate) ?? checkDate
            } else {
                break
            }
        }

        return streak
    }

    private func calculateLongestStreak() -> Int {
        guard reviewDates.count > 1 else { return reviewDates.count }

        var longest = 1
        var current = 1
                for i in 1..<reviewDates.count {
            guard let prev = Self.iso8601DayFormatter.date(from: reviewDates[i - 1]),
                  let curr = Self.iso8601DayFormatter.date(from: reviewDates[i]) else { continue }

            let diff = Calendar.current.dateComponents([.day], from: prev, to: curr).day ?? 0
            if diff == 1 {
                current += 1
                longest = max(longest, current)
            } else if diff > 1 {
                current = 1
            }
        }

        return longest
    }

    // MARK: - Persistence Data

    private struct PersistenceData: Codable {
        let cards: [Flashcard]
        let decks: [FlashcardDeck]
        let sessionHistory: [ReviewSessionResult]
        let reviewDates: [String]
    }
}
