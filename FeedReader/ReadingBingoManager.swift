//
//  ReadingBingoManager.swift
//  FeedReader
//
//  Reading Bingo — a gamified 5×5 bingo card with randomized reading challenges.
//  Each cell contains a different reading task (e.g., "Read 3 articles before noon",
//  "Read from a new feed", "Highlight a passage"). Users mark cells as they complete
//  tasks. Tracks bingo lines (rows, columns, diagonals), blackout completion,
//  and card history. Generates fresh cards on demand from a pool of 40+ challenges.
//
//  Persistence: UserDefaults via Codable JSON.
//  Fully offline — no network, no dependencies beyond Foundation.
//

import Foundation

// MARK: - Notifications

extension Notification.Name {
    /// Posted when bingo card state changes (cell marked, bingo achieved, new card).
    static let readingBingoDidChange = Notification.Name("ReadingBingoDidChangeNotification")
    /// Posted when a bingo line is completed (row, column, or diagonal).
    static let readingBingoLineCompleted = Notification.Name("ReadingBingoLineCompletedNotification")
    /// Posted when all 25 cells are marked (blackout).
    static let readingBingoBlackout = Notification.Name("ReadingBingoBlackoutNotification")
}

// MARK: - BingoCell

/// A single cell on the 5×5 bingo card.
struct BingoCell: Codable, Equatable {
    /// Unique identifier for this cell.
    let id: String
    /// The challenge text displayed in the cell.
    let challenge: String
    /// Category for color-coding or grouping.
    let category: BingoChallengeCategory
    /// Whether this cell has been marked as completed.
    var isMarked: Bool
    /// When the cell was marked, if applicable.
    var markedDate: Date?
    /// Whether this is the free center space.
    let isFreeSpace: Bool
}

// MARK: - BingoChallengeCategory

/// Categories for bingo challenges.
enum BingoChallengeCategory: String, Codable, CaseIterable {
    case volume = "volume"           // Read X articles
    case exploration = "exploration" // Try new feeds/topics
    case engagement = "engagement"   // Highlight, note, share
    case timing = "timing"           // Time-based challenges
    case streak = "streak"           // Consistency challenges
    case wildcard = "wildcard"       // Fun/quirky challenges
}

// MARK: - BingoCard

/// A complete 5×5 bingo card with 25 cells.
struct BingoCard: Codable {
    /// Unique identifier for this card.
    let id: String
    /// When the card was created.
    let createdDate: Date
    /// The 25 cells in row-major order (5 rows × 5 columns).
    var cells: [BingoCell]
    /// Number of bingo lines completed (rows + columns + diagonals).
    var completedLines: Int
    /// Whether all 25 cells are marked.
    var isBlackout: Bool
    /// When the card was completed (blackout), if applicable.
    var completedDate: Date?

    /// Access cell by row and column (0-indexed).
    func cell(row: Int, col: Int) -> BingoCell? {
        guard row >= 0, row < 5, col >= 0, col < 5 else { return nil }
        return cells[row * 5 + col]
    }

    /// The 5 rows.
    var rows: [[BingoCell]] {
        (0..<5).map { r in (0..<5).map { c in cells[r * 5 + c] } }
    }

    /// The 5 columns.
    var columns: [[BingoCell]] {
        (0..<5).map { c in (0..<5).map { r in cells[r * 5 + c] } }
    }

    /// The 2 diagonals.
    var diagonals: [[BingoCell]] {
        [
            (0..<5).map { i in cells[i * 5 + i] },           // top-left to bottom-right
            (0..<5).map { i in cells[i * 5 + (4 - i)] }      // top-right to bottom-left
        ]
    }

    /// All lines (rows + columns + diagonals) — 12 total.
    var allLines: [[BingoCell]] { rows + columns + diagonals }

    /// Count of currently completed lines.
    var currentCompletedLines: Int {
        allLines.filter { line in line.allSatisfy { $0.isMarked } }.count
    }
}

// MARK: - BingoStats

/// Aggregate stats across all bingo cards.
struct BingoStats: Codable {
    var totalCardsCreated: Int = 0
    var totalCardsCompleted: Int = 0
    var totalCellsMarked: Int = 0
    var totalLinesCompleted: Int = 0
    var totalBlackouts: Int = 0
    var fastestBlackoutSeconds: TimeInterval?
    var averageCellsPerCard: Double = 0
}

// MARK: - Challenge Pool

/// The pool of possible bingo challenges.
private let challengePool: [(String, BingoChallengeCategory)] = [
    // Volume
    ("Read 5 articles today", .volume),
    ("Read 10 articles today", .volume),
    ("Read 3 long-form articles", .volume),
    ("Read an article over 2000 words", .volume),
    ("Read 3 articles under 500 words", .volume),
    ("Clear your entire reading queue", .volume),
    ("Read 7 articles in one sitting", .volume),

    // Exploration
    ("Read from a feed you rarely visit", .exploration),
    ("Subscribe to a new feed", .exploration),
    ("Read about a topic you know nothing about", .exploration),
    ("Read from 5 different feeds", .exploration),
    ("Find an article that changes your mind", .exploration),
    ("Read an article in a different language", .exploration),
    ("Read the oldest unread article in your queue", .exploration),

    // Engagement
    ("Highlight 3 passages", .engagement),
    ("Write a note on an article", .engagement),
    ("Share an article with someone", .engagement),
    ("Save 5 articles to read later", .engagement),
    ("Create a collection of related articles", .engagement),
    ("Summarize an article in your own words", .engagement),
    ("Quote-journal a memorable passage", .engagement),

    // Timing
    ("Read for 30 minutes straight", .timing),
    ("Read an article before 8 AM", .timing),
    ("Read during your lunch break", .timing),
    ("Read 3 articles after dinner", .timing),
    ("Spend 1 hour reading today", .timing),
    ("Read something within 5 min of waking up", .timing),
    ("Read an article published today", .timing),

    // Streak
    ("Read every day for 3 days", .streak),
    ("Read at the same time 2 days in a row", .streak),
    ("Read from the same feed 3 days in a row", .streak),
    ("Mark all articles in a feed as read", .streak),
    ("Read at least 1 article for 5 days", .streak),
    ("Complete your daily reading goal", .streak),

    // Wildcard
    ("Read an article with your phone upside down", .wildcard),
    ("Read the last article in your queue first", .wildcard),
    ("Read only headlines for 10 articles", .wildcard),
    ("Find a typo in an article", .wildcard),
    ("Read an article you bookmarked over a week ago", .wildcard),
    ("Read an article and disagree with it", .wildcard),
    ("Read the shortest article in your feed", .wildcard),
    ("Read something purely for fun", .wildcard),
]

// MARK: - ReadingBingoManager

/// Manages reading bingo cards — creation, marking, line detection, stats.
final class ReadingBingoManager {

    /// Shared singleton instance.
    static let shared = ReadingBingoManager()

    // MARK: - Storage Keys

    private let currentCardKey = "ReadingBingo_CurrentCard"
    private let cardHistoryKey = "ReadingBingo_CardHistory"
    private let statsKey = "ReadingBingo_Stats"

    // MARK: - State

    /// The currently active bingo card, or nil if none.
    private(set) var currentCard: BingoCard? {
        didSet { persistCurrentCard() }
    }

    /// Completed card history (most recent first).
    private(set) var cardHistory: [BingoCard] = []

    /// Aggregate stats.
    private(set) var stats: BingoStats = BingoStats()

    // MARK: - Init

    private init() {
        loadState()
    }

    // MARK: - Card Creation

    /// Generate a new 5×5 bingo card with randomized challenges.
    /// Any existing card is archived to history.
    @discardableResult
    func newCard() -> BingoCard {
        // Archive current card if it exists
        if let current = currentCard {
            archiveCard(current)
        }

        // Pick 24 random challenges (center is free space)
        var pool = challengePool.shuffled()
        var cells: [BingoCell] = []

        for i in 0..<25 {
            if i == 12 {
                // Center free space
                cells.append(BingoCell(
                    id: UUID().uuidString,
                    challenge: "FREE SPACE",
                    category: .wildcard,
                    isMarked: true,
                    markedDate: Date(),
                    isFreeSpace: true
                ))
            } else {
                let (challenge, category) = pool.removeFirst()
                cells.append(BingoCell(
                    id: UUID().uuidString,
                    challenge: challenge,
                    category: category,
                    isMarked: false,
                    markedDate: nil,
                    isFreeSpace: false
                ))
            }
        }

        let card = BingoCard(
            id: UUID().uuidString,
            createdDate: Date(),
            cells: cells,
            completedLines: 0,
            isBlackout: false,
            completedDate: nil
        )

        currentCard = card
        stats.totalCardsCreated += 1
        persistStats()

        NotificationCenter.default.post(name: .readingBingoDidChange, object: self)
        return card
    }

    // MARK: - Cell Marking

    /// Mark a cell as completed by its ID. Returns true if the cell was found and not already marked.
    @discardableResult
    func markCell(id: String) -> Bool {
        guard var card = currentCard,
              let index = card.cells.firstIndex(where: { $0.id == id && !$0.isMarked }) else {
            return false
        }

        card.cells[index].isMarked = true
        card.cells[index].markedDate = Date()

        // Check for new completed lines
        let previousLines = card.completedLines
        card.completedLines = card.currentCompletedLines

        // Check for blackout
        if card.cells.allSatisfy({ $0.isMarked }) {
            card.isBlackout = true
            card.completedDate = Date()
            stats.totalBlackouts += 1

            let elapsed = card.completedDate!.timeIntervalSince(card.createdDate)
            if stats.fastestBlackoutSeconds == nil || elapsed < stats.fastestBlackoutSeconds! {
                stats.fastestBlackoutSeconds = elapsed
            }

            NotificationCenter.default.post(name: .readingBingoBlackout, object: self)
        }

        stats.totalCellsMarked += 1
        currentCard = card

        if card.completedLines > previousLines {
            stats.totalLinesCompleted += (card.completedLines - previousLines)
            NotificationCenter.default.post(
                name: .readingBingoLineCompleted,
                object: self,
                userInfo: ["newLines": card.completedLines - previousLines]
            )
        }

        persistStats()
        NotificationCenter.default.post(name: .readingBingoDidChange, object: self)
        return true
    }

    /// Unmark a cell by its ID. Returns true if the cell was found and was marked.
    @discardableResult
    func unmarkCell(id: String) -> Bool {
        guard var card = currentCard,
              let index = card.cells.firstIndex(where: { $0.id == id && $0.isMarked && !$0.isFreeSpace }) else {
            return false
        }

        card.cells[index].isMarked = false
        card.cells[index].markedDate = nil
        card.completedLines = card.currentCompletedLines
        card.isBlackout = false
        card.completedDate = nil

        stats.totalCellsMarked = max(0, stats.totalCellsMarked - 1)
        currentCard = card

        persistStats()
        NotificationCenter.default.post(name: .readingBingoDidChange, object: self)
        return true
    }

    // MARK: - Queries

    /// Number of marked cells on the current card.
    var markedCount: Int {
        currentCard?.cells.filter { $0.isMarked }.count ?? 0
    }

    /// Number of unmarked cells on the current card.
    var unmarkedCount: Int {
        currentCard?.cells.filter { !$0.isMarked }.count ?? 0
    }

    /// Completion percentage of the current card (0.0–1.0).
    var completionPercentage: Double {
        guard let card = currentCard else { return 0 }
        return Double(card.cells.filter { $0.isMarked }.count) / 25.0
    }

    /// Lines that are currently completed on the active card.
    var completedLineDescriptions: [String] {
        guard let card = currentCard else { return [] }
        var lines: [String] = []

        for (i, row) in card.rows.enumerated() {
            if row.allSatisfy({ $0.isMarked }) {
                lines.append("Row \(i + 1)")
            }
        }
        for (i, col) in card.columns.enumerated() {
            if col.allSatisfy({ $0.isMarked }) {
                lines.append("Column \(i + 1)")
            }
        }
        let diags = card.diagonals
        if diags[0].allSatisfy({ $0.isMarked }) { lines.append("Diagonal ↘") }
        if diags[1].allSatisfy({ $0.isMarked }) { lines.append("Diagonal ↙") }

        return lines
    }

    /// Get cells that are closest to completing a line (most marked in an incomplete line).
    func nearestLineOpportunities() -> [(line: String, remaining: [BingoCell])] {
        guard let card = currentCard else { return [] }

        var opportunities: [(String, [BingoCell])] = []

        for (i, row) in card.rows.enumerated() {
            let unmarked = row.filter { !$0.isMarked }
            if !unmarked.isEmpty && unmarked.count <= 2 {
                opportunities.append(("Row \(i + 1)", unmarked))
            }
        }
        for (i, col) in card.columns.enumerated() {
            let unmarked = col.filter { !$0.isMarked }
            if !unmarked.isEmpty && unmarked.count <= 2 {
                opportunities.append(("Column \(i + 1)", unmarked))
            }
        }
        let diags = card.diagonals
        let diagNames = ["Diagonal ↘", "Diagonal ↙"]
        for (i, diag) in diags.enumerated() {
            let unmarked = diag.filter { !$0.isMarked }
            if !unmarked.isEmpty && unmarked.count <= 2 {
                opportunities.append((diagNames[i], unmarked))
            }
        }

        return opportunities.sorted { $0.1.count < $1.1.count }
    }

    /// ASCII representation of the current card for display/debugging.
    func asciiCard() -> String {
        guard let card = currentCard else { return "No active bingo card." }

        var output = "╔═══════════════════════════════════════════════════════╗\n"
        output +=    "║              R E A D I N G   B I N G O              ║\n"
        output +=    "╠═══════════╦═══════════╦═══════════╦═══════════╦═══════════╣\n"

        for row in 0..<5 {
            var line1 = "║"
            var line2 = "║"
            for col in 0..<5 {
                let cell = card.cells[row * 5 + col]
                let mark = cell.isMarked ? "  ✅  " : "  ⬜  "
                let text = String(cell.challenge.prefix(9)).padding(toLength: 9, withPad: " ", startingAt: 0)
                line1 += " \(mark)  ║"
                line2 += " \(text) ║"
            }
            output += line1 + "\n"
            output += line2 + "\n"
            if row < 4 {
                output += "╠═══════════╬═══════════╬═══════════╬═══════════╬═══════════╣\n"
            }
        }
        output += "╚═══════════╩═══════════╩═══════════╩═══════════╩═══════════╝\n"
        output += "Lines: \(card.completedLines)/12 | Cells: \(markedCount)/25 | \(Int(completionPercentage * 100))%"

        return output
    }

    // MARK: - History

    /// Archive a card to history.
    private func archiveCard(_ card: BingoCard) {
        cardHistory.insert(card, at: 0)
        // Keep last 50 cards
        if cardHistory.count > 50 {
            cardHistory = Array(cardHistory.prefix(50))
        }
        updateAverageStats()
        persistHistory()
    }

    /// Update running average stats.
    private func updateAverageStats() {
        guard !cardHistory.isEmpty else { return }
        let totalMarked = cardHistory.reduce(0) { $0 + $1.cells.filter { $0.isMarked }.count }
        stats.averageCellsPerCard = Double(totalMarked) / Double(cardHistory.count)
        stats.totalCardsCompleted = cardHistory.filter { $0.isBlackout }.count
    }

    // MARK: - Reset

    /// Clear all bingo data.
    func resetAll() {
        currentCard = nil
        cardHistory = []
        stats = BingoStats()
        persistHistory()
        persistStats()
        NotificationCenter.default.post(name: .readingBingoDidChange, object: self)
    }

    // MARK: - Persistence

    private func persistCurrentCard() {
        if let card = currentCard, let data = try? JSONEncoder().encode(card) {
            UserDefaults.standard.set(data, forKey: currentCardKey)
        } else {
            UserDefaults.standard.removeObject(forKey: currentCardKey)
        }
    }

    private func persistHistory() {
        if let data = try? JSONEncoder().encode(cardHistory) {
            UserDefaults.standard.set(data, forKey: cardHistoryKey)
        }
    }

    private func persistStats() {
        if let data = try? JSONEncoder().encode(stats) {
            UserDefaults.standard.set(data, forKey: statsKey)
        }
    }

    private func loadState() {
        if let data = UserDefaults.standard.data(forKey: currentCardKey),
           let card = try? JSONDecoder().decode(BingoCard.self, from: data) {
            currentCard = card
        }
        if let data = UserDefaults.standard.data(forKey: cardHistoryKey),
           let history = try? JSONDecoder().decode([BingoCard].self, from: data) {
            cardHistory = history
        }
        if let data = UserDefaults.standard.data(forKey: statsKey),
           let s = try? JSONDecoder().decode(BingoStats.self, from: data) {
            stats = s
        }
    }
}
