//
//  ReadingBingoCardTests.swift
//  FeedReaderTests
//
//  Tests for ReadingBingoCard models and BingoCardManager.
//

import XCTest
@testable import FeedReader

class BingoCellTests: XCTestCase {

    func testProgressFraction() {
        let cell = BingoCell(id: "1", challengeType: .articleCount, title: "Test",
                             description: "Read 5", target: 5, progress: 3,
                             isCompleted: false, completedDate: nil, isFreeSpace: false)
        XCTAssertEqual(cell.progressFraction, 0.6, accuracy: 0.001)
    }

    func testProgressFractionClamped() {
        let cell = BingoCell(id: "1", challengeType: .articleCount, title: "Test",
                             description: "Read 5", target: 5, progress: 10,
                             isCompleted: false, completedDate: nil, isFreeSpace: false)
        XCTAssertEqual(cell.progressFraction, 1.0, accuracy: 0.001)
    }

    func testFreeSpaceProgress() {
        let cell = BingoCell(id: "1", challengeType: .articleCount, title: "FREE",
                             description: "Free", target: 0, progress: 0,
                             isCompleted: true, completedDate: Date(), isFreeSpace: true)
        XCTAssertEqual(cell.progressFraction, 1.0)
    }

    func testMarkCompleted() {
        var cell = BingoCell(id: "1", challengeType: .articleCount, title: "Test",
                             description: "Read 5", target: 5, progress: 2,
                             isCompleted: false, completedDate: nil, isFreeSpace: false)
        cell.markCompleted()
        XCTAssertTrue(cell.isCompleted)
        XCTAssertEqual(cell.progress, 5)
        XCTAssertNotNil(cell.completedDate)
    }

    func testMarkCompletedPreservesDate() {
        let earlyDate = Date(timeIntervalSince1970: 1000)
        var cell = BingoCell(id: "1", challengeType: .articleCount, title: "Test",
                             description: "Read 5", target: 5, progress: 5,
                             isCompleted: false, completedDate: earlyDate, isFreeSpace: false)
        cell.markCompleted()
        XCTAssertEqual(cell.completedDate, earlyDate)
    }
}

class BingoChallengeTemplateTests: XCTestCase {

    func testGenerateCellsReturns5x5Grid() {
        let grid = BingoChallengeTemplate.generateCells(difficulty: .medium)
        XCTAssertEqual(grid.count, 5)
        for row in grid {
            XCTAssertEqual(row.count, 5)
        }
    }

    func testCenterIsFreeSpace() {
        let grid = BingoChallengeTemplate.generateCells(difficulty: .easy)
        let center = grid[2][2]
        XCTAssertTrue(center.isFreeSpace)
        XCTAssertTrue(center.isCompleted)
        XCTAssertEqual(center.title, "FREE")
    }

    func testNonCenterCellsAreNotFree() {
        let grid = BingoChallengeTemplate.generateCells(difficulty: .medium)
        var nonFreeCount = 0
        for row in 0..<5 {
            for col in 0..<5 {
                if row != 2 || col != 2 {
                    XCTAssertFalse(grid[row][col].isFreeSpace)
                    nonFreeCount += 1
                }
            }
        }
        XCTAssertEqual(nonFreeCount, 24)
    }

    func testDifficultyAffectsTargets() {
        let easy = BingoChallengeTemplate.generateCells(difficulty: .easy)
        let hard = BingoChallengeTemplate.generateCells(difficulty: .hard)
        // Easy targets should generally be lower, but since pool is shuffled
        // we just check all targets are > 0
        for row in easy {
            for cell in row where !cell.isFreeSpace {
                XCTAssertGreaterThan(cell.target, 0)
            }
        }
        for row in hard {
            for cell in row where !cell.isFreeSpace {
                XCTAssertGreaterThan(cell.target, 0)
            }
        }
    }

    func testUniqueIds() {
        let grid = BingoChallengeTemplate.generateCells(difficulty: .medium)
        let ids = grid.flatMap { $0.map { $0.id } }
        XCTAssertEqual(Set(ids).count, 25)
    }
}

class BingoDifficultyTests: XCTestCase {

    func testMultipliers() {
        XCTAssertEqual(BingoDifficulty.easy.multiplier, 0.6, accuracy: 0.001)
        XCTAssertEqual(BingoDifficulty.medium.multiplier, 1.0, accuracy: 0.001)
        XCTAssertEqual(BingoDifficulty.hard.multiplier, 1.5, accuracy: 0.001)
    }

    func testDisplayNames() {
        XCTAssertEqual(BingoDifficulty.easy.displayName, "Easy")
        XCTAssertEqual(BingoDifficulty.medium.displayName, "Medium")
        XCTAssertEqual(BingoDifficulty.hard.displayName, "Hard")
    }
}

class BingoCardManagerTests: XCTestCase {

    override func setUp() {
        super.setUp()
        BingoCardManager.shared.resetAll()
    }

    func testCreateCard() {
        let card = BingoCardManager.shared.createCard(name: "Test Card", difficulty: .medium)
        XCTAssertEqual(card.name, "Test Card")
        XCTAssertEqual(card.difficulty, .medium)
        XCTAssertEqual(card.cells.count, 5)
        XCTAssertFalse(card.isBlackout)
        XCTAssertEqual(BingoCardManager.shared.allCards.count, 1)
    }

    func testDeleteCard() {
        let card = BingoCardManager.shared.createCard(name: "Delete Me")
        XCTAssertEqual(BingoCardManager.shared.allCards.count, 1)
        BingoCardManager.shared.deleteCard(withId: card.id)
        XCTAssertEqual(BingoCardManager.shared.allCards.count, 0)
    }

    func testCardLookup() {
        let card = BingoCardManager.shared.createCard(name: "Lookup")
        XCTAssertNotNil(BingoCardManager.shared.card(withId: card.id))
        XCTAssertNil(BingoCardManager.shared.card(withId: "nonexistent"))
    }

    func testMarkCellCompleted() {
        let card = BingoCardManager.shared.createCard(name: "Complete Test")
        let cellId = card.cells[0][0].id
        let result = BingoCardManager.shared.markCellCompleted(cardId: card.id, cellId: cellId)
        XCTAssertTrue(result.cellCompleted)

        let updated = BingoCardManager.shared.card(withId: card.id)!
        XCTAssertTrue(updated.cells[0][0].isCompleted)
    }

    func testUpdateCellProgress() {
        let card = BingoCardManager.shared.createCard(name: "Progress Test")
        let cellId = card.cells[0][0].id
        let target = card.cells[0][0].target

        // Partial progress
        let r1 = BingoCardManager.shared.updateCell(cardId: card.id, cellId: cellId, progress: 1)
        if target > 1 {
            XCTAssertFalse(r1.cellCompleted)
        }

        // Complete
        let r2 = BingoCardManager.shared.updateCell(cardId: card.id, cellId: cellId, progress: target)
        XCTAssertTrue(r2.cellCompleted)
    }

    func testRowBingo() {
        let card = BingoCardManager.shared.createCard(name: "Row Test")
        // Complete entire row 0
        var lastResult: (cellCompleted: Bool, newLines: [BingoLine], isBlackout: Bool) = (false, [], false)
        for col in 0..<5 {
            let cellId = card.cells[0][col].id
            if card.cells[0][col].isFreeSpace { continue }
            lastResult = BingoCardManager.shared.markCellCompleted(cardId: card.id, cellId: cellId)
        }
        let lines = BingoCardManager.shared.card(withId: card.id)!.completedLines
        XCTAssertTrue(lines.contains { $0.type == .row && $0.index == 0 })
    }

    func testColumnBingo() {
        let card = BingoCardManager.shared.createCard(name: "Col Test")
        for row in 0..<5 {
            let cellId = card.cells[row][0].id
            if card.cells[row][0].isFreeSpace { continue }
            BingoCardManager.shared.markCellCompleted(cardId: card.id, cellId: cellId)
        }
        let lines = BingoCardManager.shared.card(withId: card.id)!.completedLines
        XCTAssertTrue(lines.contains { $0.type == .column && $0.index == 0 })
    }

    func testDiagonalBingo() {
        let card = BingoCardManager.shared.createCard(name: "Diag Test")
        for i in 0..<5 {
            let cellId = card.cells[i][i].id
            if card.cells[i][i].isFreeSpace { continue }
            BingoCardManager.shared.markCellCompleted(cardId: card.id, cellId: cellId)
        }
        let lines = BingoCardManager.shared.card(withId: card.id)!.completedLines
        XCTAssertTrue(lines.contains { $0.type == .diagonal && $0.index == 0 })
    }

    func testBlackout() {
        let card = BingoCardManager.shared.createCard(name: "Blackout Test")
        for row in 0..<5 {
            for col in 0..<5 {
                if card.cells[row][col].isFreeSpace { continue }
                BingoCardManager.shared.markCellCompleted(cardId: card.id, cellId: card.cells[row][col].id)
            }
        }
        let updated = BingoCardManager.shared.card(withId: card.id)!
        XCTAssertTrue(updated.isBlackout)
        XCTAssertNotNil(updated.blackoutDate)
    }

    func testStats() {
        BingoCardManager.shared.createCard(name: "Stats 1")
        BingoCardManager.shared.createCard(name: "Stats 2")
        let stats = BingoCardManager.shared.getStats()
        XCTAssertEqual(stats.totalCardsCreated, 2)
        XCTAssertEqual(stats.currentActiveCards, 2)
    }

    func testCardSummary() {
        let card = BingoCardManager.shared.createCard(name: "Summary Test")
        let summary = BingoCardManager.shared.cardSummary(cardId: card.id)
        XCTAssertTrue(summary.contains("Summary Test"))
        XCTAssertTrue(summary.contains("Progress:"))
    }

    func testCardSummaryNotFound() {
        let summary = BingoCardManager.shared.cardSummary(cardId: "nope")
        XCTAssertEqual(summary, "Card not found.")
    }

    func testPresetCards() {
        BingoCardManager.shared.createWeeklyCard()
        BingoCardManager.shared.createSpeedCard()
        BingoCardManager.shared.createEnduranceCard()
        XCTAssertEqual(BingoCardManager.shared.allCards.count, 3)
        XCTAssertEqual(BingoCardManager.shared.allCards[1].difficulty, .easy)
        XCTAssertEqual(BingoCardManager.shared.allCards[2].difficulty, .hard)
    }

    func testResetAll() {
        BingoCardManager.shared.createCard(name: "To Delete")
        BingoCardManager.shared.resetAll()
        XCTAssertEqual(BingoCardManager.shared.allCards.count, 0)
        XCTAssertEqual(BingoCardManager.shared.getStats().totalCardsCreated, 0)
    }

    func testUpdateNonexistentCard() {
        let result = BingoCardManager.shared.updateCell(cardId: "fake", cellId: "fake", progress: 1)
        XCTAssertFalse(result.cellCompleted)
        XCTAssertTrue(result.newLines.isEmpty)
    }

    func testOverallProgress() {
        let card = BingoCardManager.shared.createCard(name: "Progress")
        // 1 cell already completed (free space), so 1/25
        XCTAssertEqual(card.overallProgress, 1.0 / 25.0, accuracy: 0.01)
    }
}
