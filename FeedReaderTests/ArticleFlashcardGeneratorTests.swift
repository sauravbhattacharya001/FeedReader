//
//  ArticleFlashcardGeneratorTests.swift
//  FeedReaderTests
//

import XCTest
@testable import FeedReader

class ArticleFlashcardGeneratorTests: XCTestCase {

    var generator: ArticleFlashcardGenerator!

    override func setUp() {
        super.setUp()
        generator = ArticleFlashcardGenerator()
    }

    // MARK: - Extraction: Definitions

    func testExtractDefinition_isDefinedAs() {
        let body = "Machine learning is defined as a subset of artificial intelligence that enables systems to learn from data."
        let result = generator.generateCards(articleId: "a1", title: "ML Guide", body: body)
        XCTAssertGreaterThan(result.extractedCount, 0)
        XCTAssertEqual(result.flashcards.first?.type, .definition)
    }

    func testExtractDefinition_isA() {
        let body = "A neural network is a computing system inspired by biological neural networks in the brain."
        let result = generator.generateCards(articleId: "a2", title: "Neural Nets", body: body)
        XCTAssertGreaterThan(result.extractedCount, 0)
    }

    func testExtractDefinition_refersTo() {
        let body = "Deep learning refers to neural networks with many layers that can learn hierarchical representations."
        let result = generator.generateCards(articleId: "a3", title: "Deep Learning", body: body)
        XCTAssertGreaterThan(result.extractedCount, 0)
        XCTAssertEqual(result.flashcards.first?.type, .definition)
    }

    func testExtractDefinition_skipsFillerSubjects() {
        let body = "It is a very common practice in software engineering."
        let result = generator.generateCards(articleId: "a4", title: "SE", body: body)
        // "It" should be skipped as filler
        let defs = result.flashcards.filter { $0.type == .definition }
        XCTAssertEqual(defs.count, 0)
    }

    func testExtractDefinition_articleMetadata() {
        let body = "Kubernetes is defined as an open source container orchestration platform for automating deployment."
        let result = generator.generateCards(articleId: "k8s-101", title: "K8s Guide", body: body)
        XCTAssertEqual(result.articleId, "k8s-101")
        XCTAssertEqual(result.articleTitle, "K8s Guide")
        if let card = result.flashcards.first {
            XCTAssertEqual(card.articleId, "k8s-101")
            XCTAssertEqual(card.articleTitle, "K8s Guide")
        }
    }

    // MARK: - Extraction: Statistics

    func testExtractStatistic() {
        let body = "The market grew by 45 percent in the last quarter alone due to increased demand."
        let result = generator.generateCards(articleId: "s1", title: "Market Report", body: body)
        let stats = result.flashcards.filter { $0.type == .statistic }
        XCTAssertGreaterThan(stats.count, 0)
    }

    func testExtractStatistic_billions() {
        let body = "Global AI spending reached 150 billion in 2025 according to the latest industry survey report."
        let result = generator.generateCards(articleId: "s2", title: "AI Spending", body: body)
        XCTAssertGreaterThan(result.extractedCount, 0)
    }

    // MARK: - Extraction: Comparisons

    func testExtractComparison_unlike() {
        let body = "Unlike traditional databases, NoSQL systems sacrifice consistency for availability and partition tolerance."
        let result = generator.generateCards(articleId: "c1", title: "Databases", body: body)
        let comparisons = result.flashcards.filter { $0.type == .comparison }
        XCTAssertGreaterThan(comparisons.count, 0)
    }

    func testExtractComparison_comparedTo() {
        let body = "Compared to Python, Rust offers memory safety without garbage collection at compile time."
        let result = generator.generateCards(articleId: "c2", title: "Languages", body: body)
        let comparisons = result.flashcards.filter { $0.type == .comparison }
        XCTAssertGreaterThan(comparisons.count, 0)
    }

    // MARK: - Extraction: Process

    func testExtractProcess() {
        let body = "The process begins with data collection from multiple sources across the enterprise network."
        let result = generator.generateCards(articleId: "p1", title: "Data Pipeline", body: body)
        let processes = result.flashcards.filter { $0.type == .process }
        XCTAssertGreaterThan(processes.count, 0)
    }

    // MARK: - Extraction: Facts

    func testExtractFact_researchShows() {
        let body = "Research shows that regular exercise improves cognitive function and reduces risk of dementia significantly."
        let result = generator.generateCards(articleId: "f1", title: "Health", body: body)
        let facts = result.flashcards.filter { $0.type == .fact }
        XCTAssertGreaterThan(facts.count, 0)
    }

    func testExtractFact_wasFoundedIn() {
        let body = "The organization was founded in 1945 to promote international cooperation and global peace."
        let result = generator.generateCards(articleId: "f2", title: "History", body: body)
        XCTAssertGreaterThan(result.extractedCount, 0)
    }

    // MARK: - Extraction: Edge Cases

    func testShortSentencesIgnored() {
        let body = "Hello. Yes. No. Ok. Fine."
        let result = generator.generateCards(articleId: "e1", title: "Short", body: body)
        XCTAssertEqual(result.extractedCount, 0)
    }

    func testEmptyBody() {
        let result = generator.generateCards(articleId: "e2", title: "Empty", body: "")
        XCTAssertEqual(result.extractedCount, 0)
        XCTAssertEqual(result.sentenceCount, 0)
    }

    func testDeduplication() {
        let body = """
        Machine learning is defined as a method for teaching computers. \
        Machine learning is defined as a method for teaching computers.
        """
        let result = generator.generateCards(articleId: "d1", title: "ML", body: body)
        // Should deduplicate identical fronts
        let fronts = result.flashcards.map { $0.front.lowercased() }
        XCTAssertEqual(fronts.count, Set(fronts).count)
    }

    func testMaxCardsPerArticle() {
        let gen = ArticleFlashcardGenerator(maxCardsPerArticle: 2)
        var body = ""
        for i in 1...10 {
            body += "Concept \(i) is defined as a very important thing that we need to understand deeply. "
        }
        let result = gen.generateCards(articleId: "m1", title: "Many", body: body)
        XCTAssertLessThanOrEqual(result.extractedCount, 2)
    }

    func testExtractionResult_sentenceCount() {
        let body = "First sentence here with enough words. Second sentence with more words here. Third sentence added."
        let result = generator.generateCards(articleId: "sc", title: "Count", body: body)
        XCTAssertEqual(result.sentenceCount, 3)
    }

    // MARK: - Card Management

    func testAddCards() {
        let result = generator.generateCards(articleId: "a1", title: "Test",
            body: "Machine learning is defined as a method of data analysis that automates analytical models.")
        let added = generator.addCards(result.flashcards)
        XCTAssertGreaterThan(added, 0)
        XCTAssertEqual(generator.getAllCards().count, added)
    }

    func testAddCards_noDuplicates() {
        let card = Flashcard(front: "Q?", back: "A", type: .custom, articleId: "x", articleTitle: "X")
        let added1 = generator.addCards([card])
        let added2 = generator.addCards([card])
        XCTAssertEqual(added1, 1)
        XCTAssertEqual(added2, 0)
        XCTAssertEqual(generator.getAllCards().count, 1)
    }

    func testCreateCustomCard() {
        let card = generator.createCustomCard(front: "What is Swift?", back: "A programming language by Apple")
        XCTAssertNotNil(card)
        XCTAssertEqual(card?.type, .custom)
        XCTAssertEqual(card?.front, "What is Swift?")
        XCTAssertEqual(generator.getAllCards().count, 1)
    }

    func testCreateCustomCard_emptyFront() {
        let card = generator.createCustomCard(front: "", back: "answer")
        XCTAssertNil(card)
    }

    func testCreateCustomCard_emptyBack() {
        let card = generator.createCustomCard(front: "question", back: "   ")
        XCTAssertNil(card)
    }

    func testDeleteCard() {
        let card = generator.createCustomCard(front: "Q?", back: "A")!
        XCTAssertTrue(generator.deleteCard(card.id))
        XCTAssertNil(generator.getCard(card.id))
    }

    func testDeleteCard_nonExistent() {
        XCTAssertFalse(generator.deleteCard("nonexistent"))
    }

    func testDeleteCard_removesFromDecks() {
        let deck = generator.createDeck(name: "Test Deck")!
        let card = generator.createCustomCard(front: "Q?", back: "A", deckId: deck.id)!
        XCTAssertEqual(generator.getDeck(deck.id)?.cardCount, 1)
        generator.deleteCard(card.id)
        XCTAssertEqual(generator.getDeck(deck.id)?.cardCount, 0)
    }

    func testGetCard() {
        let card = generator.createCustomCard(front: "Q?", back: "A")!
        let fetched = generator.getCard(card.id)
        XCTAssertEqual(fetched?.front, "Q?")
    }

    func testGetAllCards_filterByType() {
        generator.createCustomCard(front: "Q1?", back: "A1")
        generator.addCards([Flashcard(front: "F1", back: "A", type: .definition, articleId: "a", articleTitle: "T")])
        let customs = generator.getAllCards(type: .custom)
        XCTAssertEqual(customs.count, 1)
        XCTAssertEqual(customs.first?.type, .custom)
    }

    func testGetAllCards_filterByArticle() {
        generator.addCards([
            Flashcard(front: "F1", back: "A", type: .fact, articleId: "a1", articleTitle: "T1"),
            Flashcard(front: "F2", back: "B", type: .fact, articleId: "a2", articleTitle: "T2")
        ])
        let filtered = generator.getAllCards(articleId: "a1")
        XCTAssertEqual(filtered.count, 1)
    }

    func testGetAllCards_dueOnly() {
        let card = generator.createCustomCard(front: "Q?", back: "A")!
        // New cards are due immediately
        let due = generator.getAllCards(dueOnly: true)
        XCTAssertEqual(due.count, 1)

        // Review with perfect score — should reschedule
        generator.reviewCard(card.id, difficulty: .perfect)
        let dueAfter = generator.getAllCards(dueOnly: true)
        XCTAssertEqual(dueAfter.count, 0)
    }

    // MARK: - Deck Management

    func testCreateDeck() {
        let deck = generator.createDeck(name: "My Deck", description: "Test deck")
        XCTAssertNotNil(deck)
        XCTAssertEqual(deck?.name, "My Deck")
        XCTAssertEqual(deck?.description, "Test deck")
    }

    func testCreateDeck_emptyName() {
        let deck = generator.createDeck(name: "")
        XCTAssertNil(deck)
    }

    func testCreateDeck_duplicateName() {
        generator.createDeck(name: "My Deck")
        let dup = generator.createDeck(name: "My Deck")
        XCTAssertNil(dup)
    }

    func testCreateDeck_duplicateNameCaseInsensitive() {
        generator.createDeck(name: "My Deck")
        let dup = generator.createDeck(name: "my deck")
        XCTAssertNil(dup)
    }

    func testDeleteDeck() {
        let deck = generator.createDeck(name: "Delete Me")!
        XCTAssertTrue(generator.deleteDeck(deck.id))
        XCTAssertNil(generator.getDeck(deck.id))
    }

    func testDeleteDeck_nonExistent() {
        XCTAssertFalse(generator.deleteDeck("nope"))
    }

    func testGetAllDecks_sorted() {
        generator.createDeck(name: "Zebra")
        generator.createDeck(name: "Alpha")
        generator.createDeck(name: "Middle")
        let decks = generator.getAllDecks()
        XCTAssertEqual(decks.map { $0.name }, ["Alpha", "Middle", "Zebra"])
    }

    func testAddCardToDeck() {
        let deck = generator.createDeck(name: "Deck")!
        let card = generator.createCustomCard(front: "Q?", back: "A")!
        XCTAssertTrue(generator.addCardToDeck(cardId: card.id, deckId: deck.id))
        XCTAssertEqual(generator.getDeck(deck.id)?.cardCount, 1)
    }

    func testAddCardToDeck_duplicate() {
        let deck = generator.createDeck(name: "Deck")!
        let card = generator.createCustomCard(front: "Q?", back: "A")!
        generator.addCardToDeck(cardId: card.id, deckId: deck.id)
        XCTAssertFalse(generator.addCardToDeck(cardId: card.id, deckId: deck.id))
    }

    func testAddCardToDeck_invalidCard() {
        let deck = generator.createDeck(name: "Deck")!
        XCTAssertFalse(generator.addCardToDeck(cardId: "fake", deckId: deck.id))
    }

    func testAddCardToDeck_invalidDeck() {
        let card = generator.createCustomCard(front: "Q?", back: "A")!
        XCTAssertFalse(generator.addCardToDeck(cardId: card.id, deckId: "fake"))
    }

    func testRemoveCardFromDeck() {
        let deck = generator.createDeck(name: "Deck")!
        let card = generator.createCustomCard(front: "Q?", back: "A", deckId: deck.id)!
        XCTAssertTrue(generator.removeCardFromDeck(cardId: card.id, deckId: deck.id))
        XCTAssertEqual(generator.getDeck(deck.id)?.cardCount, 0)
        // Card still exists
        XCTAssertNotNil(generator.getCard(card.id))
    }

    func testGetCardsInDeck() {
        let deck = generator.createDeck(name: "Deck")!
        let card1 = generator.createCustomCard(front: "Q1?", back: "A1", deckId: deck.id)!
        let card2 = generator.createCustomCard(front: "Q2?", back: "A2", deckId: deck.id)!
        let deckCards = generator.getCardsInDeck(deck.id)
        XCTAssertEqual(deckCards.count, 2)
    }

    func testGetDueCardsInDeck() {
        let deck = generator.createDeck(name: "Deck")!
        let card = generator.createCustomCard(front: "Q?", back: "A", deckId: deck.id)!
        XCTAssertEqual(generator.getDueCardsInDeck(deck.id).count, 1)
        generator.reviewCard(card.id, difficulty: .perfect)
        XCTAssertEqual(generator.getDueCardsInDeck(deck.id).count, 0)
    }

    func testAddCardsWithDeck() {
        let deck = generator.createDeck(name: "Deck")!
        let cards = [
            Flashcard(front: "F1", back: "A1", type: .fact, articleId: "a", articleTitle: "T"),
            Flashcard(front: "F2", back: "A2", type: .fact, articleId: "a", articleTitle: "T")
        ]
        generator.addCards(cards, toDeck: deck.id)
        XCTAssertEqual(generator.getDeck(deck.id)?.cardCount, 2)
    }

    // MARK: - SM-2 Spaced Repetition

    func testReviewCard_perfect() {
        let card = generator.createCustomCard(front: "Q?", back: "A")!
        let reviewed = generator.reviewCard(card.id, difficulty: .perfect)!
        XCTAssertEqual(reviewed.repetitions, 1)
        XCTAssertEqual(reviewed.interval, 1)
        XCTAssertEqual(reviewed.totalReviews, 1)
        XCTAssertEqual(reviewed.correctReviews, 1)
        XCTAssertGreaterThan(reviewed.easeFactor, 2.5) // Perfect increases EF
    }

    func testReviewCard_secondPerfect() {
        let card = generator.createCustomCard(front: "Q?", back: "A")!
        generator.reviewCard(card.id, difficulty: .perfect)
        let reviewed = generator.reviewCard(card.id, difficulty: .perfect)!
        XCTAssertEqual(reviewed.repetitions, 2)
        XCTAssertEqual(reviewed.interval, 6)
    }

    func testReviewCard_thirdPerfect() {
        let card = generator.createCustomCard(front: "Q?", back: "A")!
        generator.reviewCard(card.id, difficulty: .perfect)
        generator.reviewCard(card.id, difficulty: .perfect)
        let reviewed = generator.reviewCard(card.id, difficulty: .perfect)!
        XCTAssertEqual(reviewed.repetitions, 3)
        // interval = round(6 * easeFactor)
        XCTAssertGreaterThan(reviewed.interval, 6)
    }

    func testReviewCard_incorrect_resetsRepetitions() {
        let card = generator.createCustomCard(front: "Q?", back: "A")!
        generator.reviewCard(card.id, difficulty: .perfect)
        generator.reviewCard(card.id, difficulty: .perfect)
        let reviewed = generator.reviewCard(card.id, difficulty: .blackout)!
        XCTAssertEqual(reviewed.repetitions, 0)
        XCTAssertEqual(reviewed.interval, 1)
    }

    func testReviewCard_easeFactorFloor() {
        let card = generator.createCustomCard(front: "Q?", back: "A")!
        // Repeated failures should not drop EF below 1.3
        for _ in 0..<20 {
            generator.reviewCard(card.id, difficulty: .blackout)
        }
        let updated = generator.getCard(card.id)!
        XCTAssertGreaterThanOrEqual(updated.easeFactor, 1.3)
    }

    func testReviewCard_nonExistent() {
        let result = generator.reviewCard("fake", difficulty: .perfect)
        XCTAssertNil(result)
    }

    func testReviewCard_masteryProgression() {
        let card = generator.createCustomCard(front: "Q?", back: "A")!
        XCTAssertEqual(generator.getCard(card.id)?.masteryLevel, "New")

        generator.reviewCard(card.id, difficulty: .hesitant)
        XCTAssertEqual(generator.getCard(card.id)?.masteryLevel, "Reviewing")

        generator.reviewCard(card.id, difficulty: .hesitant)
        generator.reviewCard(card.id, difficulty: .hesitant)
        XCTAssertEqual(generator.getCard(card.id)?.masteryLevel, "Learning")

        // Get to mastered: need repetitions >= 5 and EF >= 2.5
        generator.reviewCard(card.id, difficulty: .perfect)
        generator.reviewCard(card.id, difficulty: .perfect)
        let mastered = generator.getCard(card.id)!
        XCTAssertEqual(mastered.masteryLevel, "Mastered")
    }

    func testReviewCard_accuracy() {
        let card = generator.createCustomCard(front: "Q?", back: "A")!
        generator.reviewCard(card.id, difficulty: .perfect) // correct
        generator.reviewCard(card.id, difficulty: .blackout) // incorrect
        let updated = generator.getCard(card.id)!
        XCTAssertEqual(updated.accuracy, 0.5, accuracy: 0.01)
    }

    // MARK: - Review Sessions

    func testCompleteReviewSession() {
        let c1 = generator.createCustomCard(front: "Q1?", back: "A1")!
        let c2 = generator.createCustomCard(front: "Q2?", back: "A2")!

        let result = generator.completeReviewSession(reviews: [
            (c1.id, .perfect, 2.0),
            (c2.id, .difficult, 5.0)
        ])

        XCTAssertNotNil(result)
        XCTAssertEqual(result?.cardsReviewed, 2)
        XCTAssertEqual(result?.correctCount, 2) // Both >= 3
        XCTAssertEqual(result?.durationSeconds, 7.0)
        XCTAssertEqual(result?.grade, "A")
    }

    func testCompleteReviewSession_mixed() {
        let c1 = generator.createCustomCard(front: "Q1?", back: "A1")!
        let c2 = generator.createCustomCard(front: "Q2?", back: "A2")!

        let result = generator.completeReviewSession(reviews: [
            (c1.id, .perfect, 1.0),
            (c2.id, .blackout, 3.0)
        ])

        XCTAssertEqual(result?.correctCount, 1)
        XCTAssertEqual(result?.accuracy, 0.5, accuracy: 0.01)
    }

    func testCompleteReviewSession_empty() {
        let result = generator.completeReviewSession(reviews: [])
        XCTAssertNil(result)
    }

    func testCompleteReviewSession_invalidCards() {
        let result = generator.completeReviewSession(reviews: [
            ("fake1", .perfect, 1.0),
            ("fake2", .perfect, 1.0)
        ])
        XCTAssertNil(result)
    }

    func testSessionHistory() {
        let card = generator.createCustomCard(front: "Q?", back: "A")!
        generator.completeReviewSession(reviews: [(card.id, .perfect, 1.0)])
        generator.completeReviewSession(reviews: [(card.id, .difficult, 2.0)])

        let history = generator.getSessionHistory()
        XCTAssertEqual(history.count, 2)
        // Most recent first
        XCTAssertGreaterThanOrEqual(history[0].sessionDate, history[1].sessionDate)
    }

    func testSessionHistory_limit() {
        let card = generator.createCustomCard(front: "Q?", back: "A")!
        for _ in 0..<5 {
            generator.completeReviewSession(reviews: [(card.id, .perfect, 1.0)])
        }
        let limited = generator.getSessionHistory(limit: 2)
        XCTAssertEqual(limited.count, 2)
    }

    // MARK: - Statistics

    func testGetStats_empty() {
        let stats = generator.getStats()
        XCTAssertEqual(stats.totalCards, 0)
        XCTAssertEqual(stats.newCards, 0)
        XCTAssertEqual(stats.dueToday, 0)
    }

    func testGetStats_withCards() {
        generator.createCustomCard(front: "Q1?", back: "A1")
        generator.createCustomCard(front: "Q2?", back: "A2")
        let stats = generator.getStats()
        XCTAssertEqual(stats.totalCards, 2)
        XCTAssertEqual(stats.newCards, 2)
        XCTAssertEqual(stats.dueToday, 2)
    }

    func testGetStats_forDeck() {
        let deck = generator.createDeck(name: "Deck")!
        generator.createCustomCard(front: "Q1?", back: "A1", deckId: deck.id)
        generator.createCustomCard(front: "Q2?", back: "A2") // Not in deck
        let deckStats = generator.getStats(deckId: deck.id)
        XCTAssertEqual(deckStats.totalCards, 1)
    }

    func testGetHardestCards() {
        let c1 = generator.createCustomCard(front: "Easy", back: "A")!
        let c2 = generator.createCustomCard(front: "Hard", back: "B")!

        // Make c2 harder by failing it
        generator.reviewCard(c2.id, difficulty: .blackout)
        generator.reviewCard(c2.id, difficulty: .blackout)
        generator.reviewCard(c1.id, difficulty: .perfect)

        let hardest = generator.getHardestCards(limit: 1)
        XCTAssertEqual(hardest.count, 1)
        XCTAssertEqual(hardest.first?.id, c2.id)
    }

    func testGetReviewForecast() {
        generator.createCustomCard(front: "Q?", back: "A")
        let forecast = generator.getReviewForecast(days: 3)
        XCTAssertEqual(forecast.count, 3)
        // New cards are due today
        XCTAssertGreaterThan(forecast[0].count, 0)
    }

    // MARK: - Report

    func testGenerateReport() {
        generator.createCustomCard(front: "Q?", back: "A")
        let report = generator.generateReport()
        XCTAssertTrue(report.contains("Flashcard Report"))
        XCTAssertTrue(report.contains("Cards: 1"))
        XCTAssertTrue(report.contains("Due Today"))
    }

    func testGenerateReport_forDeck() {
        let deck = generator.createDeck(name: "My Deck")!
        generator.createCustomCard(front: "Q?", back: "A", deckId: deck.id)
        let report = generator.generateReport(deckId: deck.id)
        XCTAssertTrue(report.contains("My Deck"))
    }

    // MARK: - Persistence

    func testExportImportJSON() {
        let deck = generator.createDeck(name: "Persist Deck")!
        generator.createCustomCard(front: "Q?", back: "A", deckId: deck.id)

        let json = generator.exportJSON()
        XCTAssertNotNil(json)

        // Import into fresh generator
        let gen2 = ArticleFlashcardGenerator()
        XCTAssertTrue(gen2.importJSON(json!))
        XCTAssertEqual(gen2.getAllCards().count, 1)
        XCTAssertEqual(gen2.getAllDecks().count, 1)
    }

    func testImportJSON_invalid() {
        XCTAssertFalse(generator.importJSON("not json"))
    }

    func testImportJSON_merges() {
        generator.createCustomCard(front: "Q1?", back: "A1")

        let gen2 = ArticleFlashcardGenerator()
        gen2.createCustomCard(front: "Q2?", back: "A2")
        let json = gen2.exportJSON()!

        generator.importJSON(json)
        XCTAssertEqual(generator.getAllCards().count, 2)
    }

    // MARK: - Flashcard Model

    func testFlashcard_isNew() {
        let card = Flashcard(front: "Q", back: "A", type: .custom, articleId: "a", articleTitle: "T")
        XCTAssertTrue(card.isNew)
    }

    func testFlashcard_isDue() {
        let card = Flashcard(front: "Q", back: "A", type: .custom, articleId: "a", articleTitle: "T")
        XCTAssertTrue(card.isDue) // Immediately due
    }

    func testFlashcard_accuracy_noReviews() {
        let card = Flashcard(front: "Q", back: "A", type: .custom, articleId: "a", articleTitle: "T")
        XCTAssertEqual(card.accuracy, 0.0)
    }

    func testFlashcard_equality() {
        let card1 = Flashcard(id: "same", front: "Q", back: "A", type: .custom, articleId: "a", articleTitle: "T")
        let card2 = Flashcard(id: "same", front: "X", back: "Y", type: .fact, articleId: "b", articleTitle: "U")
        XCTAssertEqual(card1, card2)
    }

    // MARK: - ReviewSessionResult

    func testReviewSessionResult_grading() {
        // Test all grade boundaries
        let gradeA = ReviewSessionResult(sessionDate: Date(), cardsReviewed: 10, correctCount: 9,
                                          averageDifficulty: 4.0, durationSeconds: 60, cardResults: [])
        XCTAssertEqual(gradeA.grade, "A")

        let gradeD = ReviewSessionResult(sessionDate: Date(), cardsReviewed: 10, correctCount: 6,
                                          averageDifficulty: 3.0, durationSeconds: 60, cardResults: [])
        XCTAssertEqual(gradeD.grade, "D")

        let gradeF = ReviewSessionResult(sessionDate: Date(), cardsReviewed: 10, correctCount: 5,
                                          averageDifficulty: 2.0, durationSeconds: 60, cardResults: [])
        XCTAssertEqual(gradeF.grade, "F")
    }

    func testReviewSessionResult_zeroCards() {
        let result = ReviewSessionResult(sessionDate: Date(), cardsReviewed: 0, correctCount: 0,
                                          averageDifficulty: 0, durationSeconds: 0, cardResults: [])
        XCTAssertEqual(result.accuracy, 0.0)
    }

    // MARK: - FlashcardDeck

    func testFlashcardDeck_cardCount() {
        let deck = FlashcardDeck(name: "Test", cardIds: ["a", "b", "c"])
        XCTAssertEqual(deck.cardCount, 3)
    }

    // MARK: - Multi-article Extraction

    func testMultiArticleExtraction() {
        let body1 = "Photosynthesis is defined as the process by which green plants convert light energy into chemical energy."
        let body2 = "The mitochondria is known as the powerhouse of the cell providing energy for cellular processes."

        let r1 = generator.generateCards(articleId: "bio1", title: "Plants", body: body1)
        let r2 = generator.generateCards(articleId: "bio2", title: "Cells", body: body2)

        generator.addCards(r1.flashcards)
        generator.addCards(r2.flashcards)

        let bio1Cards = generator.getAllCards(articleId: "bio1")
        let bio2Cards = generator.getAllCards(articleId: "bio2")
        XCTAssertGreaterThan(bio1Cards.count, 0)
        XCTAssertGreaterThan(bio2Cards.count, 0)
    }

    // MARK: - Streaks

    func testStreak_noReviews() {
        let stats = generator.getStats()
        XCTAssertEqual(stats.currentStreak, 0)
        XCTAssertEqual(stats.longestStreak, 0)
    }

    func testStreak_reviewToday() {
        let card = generator.createCustomCard(front: "Q?", back: "A")!
        generator.reviewCard(card.id, difficulty: .perfect)
        let stats = generator.getStats()
        XCTAssertEqual(stats.currentStreak, 1)
    }

    // MARK: - Configuration

    func testCustomMinSentenceWords() {
        let gen = ArticleFlashcardGenerator(minSentenceWords: 10)
        let body = "Short sentence here. This is also a short one. Very brief."
        let result = gen.generateCards(articleId: "x", title: "X", body: body)
        XCTAssertEqual(result.extractedCount, 0)
    }

    func testMinSentenceWords_floor() {
        let gen = ArticleFlashcardGenerator(minSentenceWords: 1)
        // Should be clamped to at least 3
        XCTAssertGreaterThanOrEqual(gen.minSentenceWords, 3)
    }

    // MARK: - LearningStats

    func testLearningStats_averageEaseFactor() {
        let c1 = generator.createCustomCard(front: "Q1?", back: "A1")!
        let c2 = generator.createCustomCard(front: "Q2?", back: "A2")!
        let stats = generator.getStats()
        // Both start at 2.5
        XCTAssertEqual(stats.averageEaseFactor, 2.5, accuracy: 0.01)
    }

    // MARK: - Mixed Type Extraction

    func testMixedContentExtraction() {
        let body = """
        Machine learning is defined as a subset of artificial intelligence. \
        The market grew by 35 percent in the last quarter due to increased investment. \
        Unlike traditional programming, ML systems learn from data patterns automatically. \
        Research shows that deep learning outperforms classical methods in image recognition tasks.
        """
        let result = generator.generateCards(articleId: "mixed", title: "ML Overview", body: body)
        let types = Set(result.flashcards.map { $0.type })
        XCTAssertGreaterThanOrEqual(types.count, 2) // Should extract multiple types
    }
}
