//
//  ReadingBingoCard.swift
//  FeedReader
//
//  Gamified reading bingo cards — 5×5 grids of diverse reading challenges.
//  Each cell has a challenge like "Read 5 articles before noon" or
//  "Read from 3 different feeds in one day." Users mark cells as they
//  complete challenges, aiming for rows, columns, diagonals, or full-card
//  "blackout" completions.
//
//  Cards can be generated from templates or randomly from a challenge pool.
//  Tracks completion history, best times, and current streaks of bingo wins.
//
//  Persistence: UserDefaults via Codable JSON.
//  Fully offline — no network, no dependencies beyond Foundation.
//

import Foundation

// MARK: - Notifications

extension Notification.Name {
    /// Posted when a bingo cell is marked or unmarked.
    static let bingoCellDidChange = Notification.Name("ReadingBingoCellDidChangeNotification")
    /// Posted when a bingo line (row/col/diagonal) is completed.
    static let bingoLineCompleted = Notification.Name("ReadingBingoLineCompletedNotification")
    /// Posted when a full card blackout is achieved.
    static let bingoBlackoutCompleted = Notification.Name("ReadingBingoBlackoutCompletedNotification")
}

// MARK: - Models

/// The type of reading challenge in a bingo cell.
enum BingoChallengeType: String, Codable, CaseIterable {
    case articleCount       // Read N articles total
    case feedDiversity      // Read from N different feeds
    case categoryExplore    // Read from a specific category
    case timeOfDay          // Read during a specific time window
    case readingTime        // Spend N minutes reading
    case streak             // Read N consecutive days
    case longRead           // Read an article over N words
    case shortRead          // Read N articles under 2 minutes each
    case weekendReading     // Read on a weekend
    case shareArticle       // Share an article
    case bookmarkArticle    // Bookmark N articles
    case topicDiscovery     // Read about a new topic
}

/// Difficulty affects the targets within each challenge type.
enum BingoDifficulty: String, Codable, CaseIterable {
    case easy
    case medium
    case hard

    var displayName: String { rawValue.capitalized }

    /// Multiplier for challenge targets.
    var multiplier: Double {
        switch self {
        case .easy: return 0.6
        case .medium: return 1.0
        case .hard: return 1.5
        }
    }
}

/// A single cell on the bingo card.
struct BingoCell: Codable, Equatable {
    let id: String
    let challengeType: BingoChallengeType
    let title: String
    let description: String
    let target: Int
    var progress: Int
    var isCompleted: Bool
    var completedDate: Date?
    let isFreeSpace: Bool

    /// Progress as fraction (0.0–1.0).
    var progressFraction: Double {
        guard target > 0 else { return isCompleted ? 1.0 : 0.0 }
        return min(Double(progress) / Double(target), 1.0)
    }

    /// Mark completed with timestamp.
    mutating func markCompleted() {
        isCompleted = true
        progress = target
        completedDate = completedDate ?? Date()
    }
}

/// A completed bingo line (row, column, or diagonal).
struct BingoLine: Codable, Equatable {
    enum LineType: String, Codable {
        case row, column, diagonal
    }
    let type: LineType
    let index: Int  // row/col number, or 0=main diagonal, 1=anti diagonal
    let completedDate: Date
}

/// A 5×5 bingo card with reading challenges.
struct BingoCard: Codable {
    let id: String
    let name: String
    let difficulty: BingoDifficulty
    let createdDate: Date
    var cells: [[BingoCell]]  // 5×5 grid
    var completedLines: [BingoLine]
    var isBlackout: Bool
    var blackoutDate: Date?

    static let gridSize = 5
    static let centerIndex = 2

    /// All cells flattened.
    var allCells: [BingoCell] {
        cells.flatMap { $0 }
    }

    /// Count of completed cells.
    var completedCount: Int {
        allCells.filter { $0.isCompleted }.count
    }

    /// Total cell count.
    var totalCells: Int { BingoCard.gridSize * BingoCard.gridSize }

    /// Overall progress fraction.
    var overallProgress: Double {
        Double(completedCount) / Double(totalCells)
    }
}

/// Summary of a player's bingo history.
struct BingoStats: Codable {
    var totalCardsCreated: Int
    var totalBlackouts: Int
    var totalLinesCompleted: Int
    var totalCellsCompleted: Int
    var fastestBlackoutDays: Double?
    var currentActiveCards: Int
    var longestLineStreak: Int  // most lines completed across all cards
}

// MARK: - Challenge Templates

/// Generates challenge descriptions and targets for bingo cells.
struct BingoChallengeTemplate {

    struct ChallengeSpec {
        let type: BingoChallengeType
        let title: String
        let description: String
        let baseTarget: Int
    }

    /// Pool of possible challenges.
    static let challengePool: [ChallengeSpec] = [
        ChallengeSpec(type: .articleCount, title: "Avid Reader", description: "Read 5 articles", baseTarget: 5),
        ChallengeSpec(type: .articleCount, title: "Page Turner", description: "Read 10 articles", baseTarget: 10),
        ChallengeSpec(type: .articleCount, title: "Bookworm", description: "Read 20 articles", baseTarget: 20),
        ChallengeSpec(type: .feedDiversity, title: "Feed Hopper", description: "Read from 3 different feeds", baseTarget: 3),
        ChallengeSpec(type: .feedDiversity, title: "Explorer", description: "Read from 5 different feeds", baseTarget: 5),
        ChallengeSpec(type: .categoryExplore, title: "Tech Buff", description: "Read a tech article", baseTarget: 1),
        ChallengeSpec(type: .categoryExplore, title: "News Hound", description: "Read 3 news articles", baseTarget: 3),
        ChallengeSpec(type: .categoryExplore, title: "Science Fan", description: "Read a science article", baseTarget: 1),
        ChallengeSpec(type: .timeOfDay, title: "Early Bird", description: "Read before 8 AM", baseTarget: 1),
        ChallengeSpec(type: .timeOfDay, title: "Night Owl", description: "Read after 10 PM", baseTarget: 1),
        ChallengeSpec(type: .timeOfDay, title: "Lunch Reader", description: "Read during lunch (12-1 PM)", baseTarget: 1),
        ChallengeSpec(type: .readingTime, title: "Focused", description: "Spend 15 minutes reading", baseTarget: 15),
        ChallengeSpec(type: .readingTime, title: "Deep Dive", description: "Spend 30 minutes reading", baseTarget: 30),
        ChallengeSpec(type: .readingTime, title: "Marathon", description: "Spend 60 minutes reading", baseTarget: 60),
        ChallengeSpec(type: .streak, title: "Consistent", description: "Read 3 days in a row", baseTarget: 3),
        ChallengeSpec(type: .streak, title: "Dedicated", description: "Read 5 days in a row", baseTarget: 5),
        ChallengeSpec(type: .longRead, title: "Long Form", description: "Read an article over 1000 words", baseTarget: 1),
        ChallengeSpec(type: .longRead, title: "Epic Read", description: "Read 3 long articles", baseTarget: 3),
        ChallengeSpec(type: .shortRead, title: "Speed Round", description: "Read 5 quick articles", baseTarget: 5),
        ChallengeSpec(type: .weekendReading, title: "Weekend Warrior", description: "Read on a weekend", baseTarget: 1),
        ChallengeSpec(type: .shareArticle, title: "Sharer", description: "Share an article", baseTarget: 1),
        ChallengeSpec(type: .shareArticle, title: "Curator", description: "Share 3 articles", baseTarget: 3),
        ChallengeSpec(type: .bookmarkArticle, title: "Collector", description: "Bookmark 3 articles", baseTarget: 3),
        ChallengeSpec(type: .bookmarkArticle, title: "Archivist", description: "Bookmark 5 articles", baseTarget: 5),
        ChallengeSpec(type: .topicDiscovery, title: "Adventurer", description: "Read about a new topic", baseTarget: 1),
    ]

    /// Generate 24 random challenges (center is free space) for a card.
    static func generateCells(difficulty: BingoDifficulty, seed: UInt64? = nil) -> [[BingoCell]] {
        var pool = challengePool.shuffled()
        // Ensure we have enough — repeat pool if needed
        while pool.count < 24 {
            pool.append(contentsOf: challengePool.shuffled())
        }
        let selected = Array(pool.prefix(24))

        var grid: [[BingoCell]] = []
        var specIndex = 0

        for row in 0..<BingoCard.gridSize {
            var rowCells: [BingoCell] = []
            for col in 0..<BingoCard.gridSize {
                if row == BingoCard.centerIndex && col == BingoCard.centerIndex {
                    // Free space
                    rowCells.append(BingoCell(
                        id: UUID().uuidString,
                        challengeType: .articleCount,
                        title: "FREE",
                        description: "Free space — already complete!",
                        target: 0,
                        progress: 0,
                        isCompleted: true,
                        completedDate: Date(),
                        isFreeSpace: true
                    ))
                } else {
                    let spec = selected[specIndex]
                    let adjustedTarget = max(1, Int(Double(spec.baseTarget) * difficulty.multiplier))
                    rowCells.append(BingoCell(
                        id: UUID().uuidString,
                        challengeType: spec.type,
                        title: spec.title,
                        description: "\(spec.description) (\(adjustedTarget))",
                        target: adjustedTarget,
                        progress: 0,
                        isCompleted: false,
                        completedDate: nil,
                        isFreeSpace: false
                    ))
                    specIndex += 1
                }
            }
            grid.append(rowCells)
        }
        return grid
    }
}

// MARK: - BingoCardManager

/// Manages reading bingo cards — create, update cells, check bingo lines, track stats.
final class BingoCardManager {

    static let shared = BingoCardManager()

    private let cardsKey = "ReadingBingoCards"
    private let statsKey = "ReadingBingoStats"

    private var cards: [BingoCard] = []
    private var stats: BingoStats

    private init() {
        cards = Self.loadCards()
        stats = Self.loadStats()
    }

    // MARK: - Persistence

    private static func loadCards() -> [BingoCard] {
        guard let data = UserDefaults.standard.data(forKey: "ReadingBingoCards") else { return [] }
        return (try? JSONDecoder().decode([BingoCard].self, from: data)) ?? []
    }

    private static func loadStats() -> BingoStats {
        guard let data = UserDefaults.standard.data(forKey: "ReadingBingoStats") else {
            return BingoStats(totalCardsCreated: 0, totalBlackouts: 0,
                              totalLinesCompleted: 0, totalCellsCompleted: 0,
                              fastestBlackoutDays: nil, currentActiveCards: 0,
                              longestLineStreak: 0)
        }
        return (try? JSONDecoder().decode(BingoStats.self, from: data)) ?? BingoStats(
            totalCardsCreated: 0, totalBlackouts: 0, totalLinesCompleted: 0,
            totalCellsCompleted: 0, fastestBlackoutDays: nil, currentActiveCards: 0,
            longestLineStreak: 0)
    }

    private func save() {
        if let data = try? JSONEncoder().encode(cards) {
            UserDefaults.standard.set(data, forKey: cardsKey)
        }
        if let data = try? JSONEncoder().encode(stats) {
            UserDefaults.standard.set(data, forKey: statsKey)
        }
    }

    // MARK: - Card CRUD

    /// All cards.
    var allCards: [BingoCard] { cards }

    /// Active (non-blackout) cards.
    var activeCards: [BingoCard] { cards.filter { !$0.isBlackout } }

    /// Create a new bingo card with random challenges.
    @discardableResult
    func createCard(name: String, difficulty: BingoDifficulty = .medium) -> BingoCard {
        let card = BingoCard(
            id: UUID().uuidString,
            name: name,
            difficulty: difficulty,
            createdDate: Date(),
            cells: BingoChallengeTemplate.generateCells(difficulty: difficulty),
            completedLines: [],
            isBlackout: false,
            blackoutDate: nil
        )
        cards.append(card)
        stats.totalCardsCreated += 1
        stats.currentActiveCards = activeCards.count
        save()
        return card
    }

    /// Get card by ID.
    func card(withId id: String) -> BingoCard? {
        cards.first { $0.id == id }
    }

    /// Delete a card.
    func deleteCard(withId id: String) {
        cards.removeAll { $0.id == id }
        stats.currentActiveCards = activeCards.count
        save()
    }

    // MARK: - Cell Updates

    /// Update progress on a specific cell and check for bingo.
    func updateCell(cardId: String, cellId: String, progress: Int) -> (cellCompleted: Bool, newLines: [BingoLine], isBlackout: Bool) {
        guard let cardIndex = cards.firstIndex(where: { $0.id == cardId }) else {
            return (false, [], false)
        }

        var cellCompleted = false
        var newLines: [BingoLine] = []
        var isBlackout = false

        // Find and update the cell
        for row in 0..<BingoCard.gridSize {
            for col in 0..<BingoCard.gridSize {
                if cards[cardIndex].cells[row][col].id == cellId {
                    let wasCompleted = cards[cardIndex].cells[row][col].isCompleted
                    cards[cardIndex].cells[row][col].progress = min(progress, cards[cardIndex].cells[row][col].target)

                    if !wasCompleted && progress >= cards[cardIndex].cells[row][col].target {
                        cards[cardIndex].cells[row][col].markCompleted()
                        cellCompleted = true
                        stats.totalCellsCompleted += 1

                        // Check for new bingo lines
                        newLines = checkNewLines(cardIndex: cardIndex, row: row, col: col)

                        // Check for blackout
                        if !cards[cardIndex].isBlackout && cards[cardIndex].completedCount == cards[cardIndex].totalCells {
                            cards[cardIndex].isBlackout = true
                            cards[cardIndex].blackoutDate = Date()
                            isBlackout = true
                            stats.totalBlackouts += 1

                            let days = Date().timeIntervalSince(cards[cardIndex].createdDate) / 86400
                            if let fastest = stats.fastestBlackoutDays {
                                stats.fastestBlackoutDays = min(fastest, days)
                            } else {
                                stats.fastestBlackoutDays = days
                            }

                            NotificationCenter.default.post(name: .bingoBlackoutCompleted, object: self,
                                                            userInfo: ["cardId": cardId])
                        }
                    }

                    NotificationCenter.default.post(name: .bingoCellDidChange, object: self,
                                                    userInfo: ["cardId": cardId, "cellId": cellId])
                    break
                }
            }
        }

        stats.currentActiveCards = activeCards.count
        save()
        return (cellCompleted, newLines, isBlackout)
    }

    /// Mark a cell as completed directly.
    func markCellCompleted(cardId: String, cellId: String) -> (cellCompleted: Bool, newLines: [BingoLine], isBlackout: Bool) {
        guard let cardIndex = cards.firstIndex(where: { $0.id == cardId }) else {
            return (false, [], false)
        }
        // Find the cell's target
        for row in 0..<BingoCard.gridSize {
            for col in 0..<BingoCard.gridSize {
                if cards[cardIndex].cells[row][col].id == cellId {
                    let target = cards[cardIndex].cells[row][col].target
                    return updateCell(cardId: cardId, cellId: cellId, progress: target)
                }
            }
        }
        return (false, [], false)
    }

    // MARK: - Bingo Line Detection

    private func checkNewLines(cardIndex: Int, row: Int, col: Int) -> [BingoLine] {
        var newLines: [BingoLine] = []
        let card = cards[cardIndex]
        let existing = Set(card.completedLines.map { "\($0.type.rawValue)-\($0.index)" })

        // Check row
        if (0..<BingoCard.gridSize).allSatisfy({ card.cells[row][$0].isCompleted }) {
            let key = "row-\(row)"
            if !existing.contains(key) {
                let line = BingoLine(type: .row, index: row, completedDate: Date())
                cards[cardIndex].completedLines.append(line)
                newLines.append(line)
            }
        }

        // Check column
        if (0..<BingoCard.gridSize).allSatisfy({ card.cells[$0][col].isCompleted }) {
            let key = "column-\(col)"
            if !existing.contains(key) {
                let line = BingoLine(type: .column, index: col, completedDate: Date())
                cards[cardIndex].completedLines.append(line)
                newLines.append(line)
            }
        }

        // Check main diagonal (if cell is on it)
        if row == col {
            if (0..<BingoCard.gridSize).allSatisfy({ card.cells[$0][$0].isCompleted }) {
                let key = "diagonal-0"
                if !existing.contains(key) {
                    let line = BingoLine(type: .diagonal, index: 0, completedDate: Date())
                    cards[cardIndex].completedLines.append(line)
                    newLines.append(line)
                }
            }
        }

        // Check anti-diagonal (if cell is on it)
        if row + col == BingoCard.gridSize - 1 {
            let size = BingoCard.gridSize
            if (0..<size).allSatisfy({ card.cells[$0][size - 1 - $0].isCompleted }) {
                let key = "diagonal-1"
                if !existing.contains(key) {
                    let line = BingoLine(type: .diagonal, index: 1, completedDate: Date())
                    cards[cardIndex].completedLines.append(line)
                    newLines.append(line)
                }
            }
        }

        if !newLines.isEmpty {
            stats.totalLinesCompleted += newLines.count
            stats.longestLineStreak = max(stats.longestLineStreak, cards[cardIndex].completedLines.count)
            for line in newLines {
                NotificationCenter.default.post(name: .bingoLineCompleted, object: self,
                                                userInfo: ["cardId": cards[cardIndex].id, "line": line.type.rawValue])
            }
        }

        return newLines
    }

    // MARK: - Stats

    /// Overall bingo stats.
    func getStats() -> BingoStats {
        var s = stats
        s.currentActiveCards = activeCards.count
        return s
    }

    /// Summary for a specific card.
    func cardSummary(cardId: String) -> String {
        guard let card = card(withId: cardId) else { return "Card not found." }

        var lines: [String] = []
        lines.append("📋 \(card.name) (\(card.difficulty.displayName))")
        lines.append("Progress: \(card.completedCount)/\(card.totalCells) cells (\(Int(card.overallProgress * 100))%)")
        lines.append("Lines: \(card.completedLines.count)/12 possible")

        if card.isBlackout, let date = card.blackoutDate {
            let days = date.timeIntervalSince(card.createdDate) / 86400
            lines.append("🎉 BLACKOUT in \(String(format: "%.1f", days)) days!")
        }

        // Grid visualization
        lines.append("")
        for row in card.cells {
            let rowStr = row.map { cell -> String in
                if cell.isFreeSpace { return "★" }
                return cell.isCompleted ? "✅" : "⬜"
            }.joined(separator: " ")
            lines.append(rowStr)
        }

        return lines.joined(separator: "\n")
    }

    // MARK: - Preset Cards

    /// Create a "Weekly Reader" themed card.
    @discardableResult
    func createWeeklyCard() -> BingoCard {
        return createCard(name: "Weekly Reader \(formattedDate())", difficulty: .medium)
    }

    /// Create a "Speed Challenge" card (easy difficulty, quick tasks).
    @discardableResult
    func createSpeedCard() -> BingoCard {
        return createCard(name: "Speed Challenge \(formattedDate())", difficulty: .easy)
    }

    /// Create an "Endurance" card (hard difficulty).
    @discardableResult
    func createEnduranceCard() -> BingoCard {
        return createCard(name: "Endurance \(formattedDate())", difficulty: .hard)
    }

    private func formattedDate() -> String {
        let f = DateFormatter()
        f.dateFormat = "MMM d"
        return f.string(from: Date())
    }

    // MARK: - Reset

    /// Clear all cards and stats.
    func resetAll() {
        cards = []
        stats = BingoStats(totalCardsCreated: 0, totalBlackouts: 0,
                           totalLinesCompleted: 0, totalCellsCompleted: 0,
                           fastestBlackoutDays: nil, currentActiveCards: 0,
                           longestLineStreak: 0)
        save()
    }
}
