//
//  VocabularyBuilder.swift
//  FeedReader
//
//  Vocabulary builder that tracks uncommon/difficult words encountered
//  while reading articles. Supports word saving, difficulty grading,
//  context tracking, spaced repetition scheduling, and vocabulary
//  analytics across feeds and topics.
//

import Foundation

// MARK: - Models

/// Difficulty tier for a vocabulary word, from everyday language to specialised terminology.
enum WordDifficulty: String, Codable, CaseIterable, Comparable {
    case basic, moderate, advanced, expert
    private var order: Int {
        switch self { case .basic: return 0; case .moderate: return 1; case .advanced: return 2; case .expert: return 3 }
    }
    static func < (lhs: WordDifficulty, rhs: WordDifficulty) -> Bool { lhs.order < rhs.order }
}

/// Tracks how well the user has learned a word, progressing through stages
/// from newly encountered to fully mastered via spaced repetition.
enum MasteryLevel: String, Codable, CaseIterable {
    case new, learning, familiar, confident, mastered
}

/// The sentence and article metadata where a vocabulary word was encountered,
/// providing real-world usage context for review.
struct WordContext: Codable, Equatable {
    let sentence: String
    let articleTitle: String
    let articleLink: String
    let feedName: String
    let date: Date
}

/// A single vocabulary word with its definition, usage contexts, review history,
/// spaced-repetition schedule, tags, and star status.
struct VocabularyEntry: Codable, Equatable {
    let word: String
    var difficulty: WordDifficulty
    var definition: String?
    var note: String?
    var contexts: [WordContext]
    var reviewCount: Int
    var correctCount: Int
    var mastery: MasteryLevel
    let addedDate: Date
    var lastReviewDate: Date?
    var nextReviewDate: Date?
    var tags: [String]
    var starred: Bool
    static func == (lhs: VocabularyEntry, rhs: VocabularyEntry) -> Bool { lhs.word == rhs.word }
}

/// Aggregate statistics for the user's vocabulary: word counts by difficulty and mastery,
/// review accuracy, streak data, and top contributing feeds.
struct VocabularyStats: Equatable {
    let totalWords: Int
    let byDifficulty: [WordDifficulty: Int]
    let byMastery: [MasteryLevel: Int]
    let wordsAddedLast7Days: Int
    let wordsAddedLast30Days: Int
    let totalReviews: Int
    let averageAccuracy: Double
    let dueForReview: Int
    let topFeeds: [(name: String, count: Int)]
    let longestStreak: Int
    let currentStreak: Int
    static func == (lhs: VocabularyStats, rhs: VocabularyStats) -> Bool {
        lhs.totalWords == rhs.totalWords && lhs.wordsAddedLast7Days == rhs.wordsAddedLast7Days && lhs.totalReviews == rhs.totalReviews
    }
}

// MARK: - Spaced Repetition

/// Calculates the next review date and mastery-level transition for a vocabulary word
/// using a modified Leitner/SM-2 spaced repetition algorithm.
///
/// Correct answers advance mastery and increase the review interval;
/// incorrect answers demote mastery and shorten it. The interval is
/// further scaled by the user's cumulative accuracy on that word.
struct SpacedRepetitionScheduler {
    static let baseIntervals: [MasteryLevel: Int] = [.new: 0, .learning: 1, .familiar: 3, .confident: 7, .mastered: 21]

    /// Compute the next mastery level and review date after a review attempt.
    /// - Parameters:
    ///   - entry: The vocabulary entry being reviewed.
    ///   - correct: Whether the user answered correctly.
    ///   - calendar: Calendar used for date arithmetic (injectable for testing).
    /// - Returns: A tuple of the new mastery level and next scheduled review date.
    static func schedule(entry: VocabularyEntry, correct: Bool, calendar: Calendar = .current) -> (mastery: MasteryLevel, nextReview: Date) {
        var newMastery = entry.mastery
        let now = Date()
        if correct {
            switch entry.mastery {
            case .new: newMastery = .learning
            case .learning: newMastery = entry.correctCount >= 1 ? .familiar : .learning
            case .familiar: newMastery = entry.correctCount >= 3 ? .confident : .familiar
            case .confident: newMastery = entry.correctCount >= 5 ? .mastered : .confident
            case .mastered: newMastery = .mastered
            }
        } else {
            switch entry.mastery {
            case .mastered: newMastery = .confident
            case .confident: newMastery = .familiar
            case .familiar: newMastery = .learning
            case .learning: newMastery = .learning
            case .new: newMastery = .new
            }
        }
        let baseDays = baseIntervals[newMastery] ?? 1
        let accuracy = entry.reviewCount > 0 ? Double(entry.correctCount) / Double(entry.reviewCount) : 0.5
        let multiplier = max(0.5, min(2.0, accuracy * 1.5))
        let intervalDays = max(1, Int(Double(baseDays) * multiplier))
        let nextDate = calendar.date(byAdding: .day, value: intervalDays, to: now) ?? now
        return (newMastery, nextDate)
    }
}

// MARK: - Word Difficulty Estimator

/// Heuristically estimates word difficulty based on length, syllable count,
/// and membership in a common-words set (~150 most frequent English words).
struct WordDifficultyEstimator {
    private static let commonWords: Set<String> = [
        "the","be","to","of","and","a","in","that","have","i","it","for","not","on","with","he","as","you","do","at",
        "this","but","his","by","from","they","we","say","her","she","or","an","will","my","one","all","would","there",
        "their","what","so","up","out","if","about","who","get","which","go","me","when","make","can","like","time",
        "no","just","him","know","take","people","into","year","your","good","some","could","them","see","other",
        "than","then","now","look","only","come","its","over","think","also","back","after","use","two","how","our",
        "work","first","well","way","even","new","want","because","any","these","give","day","most","us","are","is",
        "was","were","been","has","had","did","does","being","more","very","much","where","here","still","must","own",
        "need","should","through","while","right","part","since","such","each","many","those","same","both","before",
        "too","may","down","already","find","long","made","thing","help","ask","every","never","start","keep","call",
        "show","move","play","run","read","hand","off","last","great","old","big","end","set","try","turn","few","left","might"
    ]

    /// Estimate the difficulty tier of a single word.
    /// - Parameter word: The word to classify.
    /// - Returns: A ``WordDifficulty`` level based on length and syllable heuristics.
    static func estimate(_ word: String) -> WordDifficulty {
        let lower = word.lowercased()
        if commonWords.contains(lower) { return .basic }
        let length = lower.count
        let syllables = estimateSyllables(lower)
        if length <= 5 && syllables <= 2 { return .basic }
        if length <= 8 && syllables <= 3 { return .moderate }
        if length >= 12 || syllables >= 5 { return .expert }
        return .advanced
    }

    /// Approximate the number of syllables in an English word using vowel-cluster counting.
    static func estimateSyllables(_ word: String) -> Int {
        let vowels: Set<Character> = ["a","e","i","o","u","y"]
        var count = 0; var prevVowel = false
        for ch in word.lowercased() {
            let isVowel = vowels.contains(ch)
            if isVowel && !prevVowel { count += 1 }
            prevVowel = isVowel
        }
        if word.lowercased().hasSuffix("e") && count > 1 { count -= 1 }
        return max(1, count)
    }
}

// MARK: - Vocabulary Builder

/// Manages a user's vocabulary list: adding/removing words, tracking usage contexts,
/// scheduling spaced-repetition reviews, computing analytics, and persisting state to disk.
///
/// Words are normalised to lowercase and deduplicated. Each word tracks its difficulty,
/// definition, contexts from articles, review history, mastery level, and next review date.
/// The builder supports import/export as JSON for backup or sync.
class VocabularyBuilder {
    private var entries: [String: VocabularyEntry] = [:]
    private let calendar: Calendar
    private var persistencePath: URL?

    init(calendar: Calendar = .current, persistencePath: URL? = nil) {
        self.calendar = calendar
        self.persistencePath = persistencePath ?? Self.defaultPath()
        load()
    }

    private static func defaultPath() -> URL? {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first?
            .appendingPathComponent("vocabulary_builder.json")
    }

    // MARK: - Word Management

    /// Add a word (or update an existing one with new context/definition/tags).
    /// - Returns: The created or updated ``VocabularyEntry``.
    @discardableResult
    func addWord(_ word: String, definition: String? = nil, difficulty: WordDifficulty? = nil,
                 context: WordContext? = nil, tags: [String] = []) -> VocabularyEntry {
        let normalised = normalise(word)
        guard !normalised.isEmpty else {
            return VocabularyEntry(word: "", difficulty: .basic, definition: nil, note: nil,
                contexts: [], reviewCount: 0, correctCount: 0, mastery: .new, addedDate: Date(),
                lastReviewDate: nil, nextReviewDate: nil, tags: [], starred: false)
        }
        if var existing = entries[normalised] {
            if let ctx = context {
                existing.contexts.append(ctx)
                if existing.contexts.count > 50 { existing.contexts = Array(existing.contexts.suffix(50)) }
            }
            if let def = definition { existing.definition = def }
            if !tags.isEmpty { existing.tags = Array(Set(existing.tags).union(tags)).sorted() }
            entries[normalised] = existing; save(); return existing
        }
        let entry = VocabularyEntry(
            word: normalised, difficulty: difficulty ?? WordDifficultyEstimator.estimate(normalised),
            definition: definition, note: nil, contexts: context.map { [$0] } ?? [],
            reviewCount: 0, correctCount: 0, mastery: .new, addedDate: Date(),
            lastReviewDate: nil, nextReviewDate: calendar.date(byAdding: .day, value: 1, to: Date()),
            tags: tags.sorted(), starred: false)
        entries[normalised] = entry; save(); return entry
    }

    /// Remove a word from the vocabulary. Returns `true` if the word existed.
    @discardableResult func removeWord(_ word: String) -> Bool {
        guard entries.removeValue(forKey: normalise(word)) != nil else { return false }; save(); return true
    }
    /// Look up a word's entry, or `nil` if not tracked.
    func lookup(_ word: String) -> VocabularyEntry? { entries[normalise(word)] }
    /// Check whether a word is in the vocabulary.
    func contains(_ word: String) -> Bool { entries[normalise(word)] != nil }

    /// Update the definition for a tracked word.
    func setDefinition(_ word: String, definition: String?) { entries[normalise(word)]?.definition = definition; save() }
    /// Update the personal note for a tracked word.
    func setNote(_ word: String, note: String?) { entries[normalise(word)]?.note = note; save() }

    /// Toggle the starred status of a word. Returns the new starred state.
    @discardableResult func toggleStar(_ word: String) -> Bool {
        let key = normalise(word)
        guard var entry = entries[key] else { return false }
        entry.starred = !entry.starred; entries[key] = entry; save(); return entry.starred
    }

    /// Replace all tags on a word.
    func setTags(_ word: String, tags: [String]) { entries[normalise(word)]?.tags = tags.sorted(); save() }

    // MARK: - Listing & Filtering

    /// All vocabulary entries, most recently added first.
    func allWords() -> [VocabularyEntry] { entries.values.sorted { $0.addedDate > $1.addedDate } }
    /// Words filtered by difficulty tier.
    func words(difficulty: WordDifficulty) -> [VocabularyEntry] { entries.values.filter { $0.difficulty == difficulty }.sorted { $0.addedDate > $1.addedDate } }
    /// Words filtered by mastery level.
    func words(mastery: MasteryLevel) -> [VocabularyEntry] { entries.values.filter { $0.mastery == mastery }.sorted { $0.addedDate > $1.addedDate } }

    /// Full-text search across word, definition, note, and tags.
    func search(_ query: String) -> [VocabularyEntry] {
        let q = query.lowercased()
        return entries.values.filter { e in
            e.word.contains(q) || (e.definition?.lowercased().contains(q) ?? false)
                || (e.note?.lowercased().contains(q) ?? false) || e.tags.contains { $0.lowercased().contains(q) }
        }
    }

    /// Words matching a specific tag (case-insensitive).
    func words(tag: String) -> [VocabularyEntry] {
        let t = tag.lowercased()
        return entries.values.filter { $0.tags.contains { $0.lowercased() == t } }.sorted { $0.addedDate > $1.addedDate }
    }

    /// All starred/favourite words.
    func starredWords() -> [VocabularyEntry] { entries.values.filter { $0.starred }.sorted { $0.addedDate > $1.addedDate } }
    /// All unique tags across the vocabulary.
    func allTags() -> [String] { var t = Set<String>(); entries.values.forEach { t.formUnion($0.tags) }; return t.sorted() }
    /// Total number of tracked words.
    var wordCount: Int { entries.count }

    // MARK: - Spaced Repetition / Review

    /// Words whose next review date has passed (or was never set), sorted by mastery
    /// (lowest first) then oldest-reviewed first, capped at `limit`.
    func wordsDueForReview(limit: Int = 20) -> [VocabularyEntry] {
        let now = Date()
        return entries.values.filter { e in guard let next = e.nextReviewDate else { return true }; return next <= now }
            .sorted { a, b in if a.mastery != b.mastery { return a.mastery < b.mastery }; return (a.lastReviewDate ?? .distantPast) < (b.lastReviewDate ?? .distantPast) }
            .prefix(limit).map { $0 }
    }

    /// Record a review attempt, updating mastery and scheduling the next review.
    /// - Returns: The updated entry, or `nil` if the word isn't tracked.
    @discardableResult
    func recordReview(_ word: String, correct: Bool) -> VocabularyEntry? {
        let key = normalise(word)
        guard var entry = entries[key] else { return nil }
        entry.reviewCount += 1; if correct { entry.correctCount += 1 }; entry.lastReviewDate = Date()
        let (m, n) = SpacedRepetitionScheduler.schedule(entry: entry, correct: correct, calendar: calendar)
        entry.mastery = m; entry.nextReviewDate = n; entries[key] = entry; save(); return entry
    }

    // MARK: - Article Analysis

    /// Scan article text and suggest uncommon words the user hasn't saved yet,
    /// ranked by difficulty (hardest first).
    /// - Parameters:
    ///   - text: The full article body text.
    ///   - articleTitle: Title for context tracking.
    ///   - articleLink: URL for context tracking.
    ///   - feedName: Source feed name for context tracking.
    ///   - maxSuggestions: Maximum number of suggestions to return.
    /// - Returns: Tuples of (word, difficulty, example sentence).
    func suggestWords(from text: String, articleTitle: String = "", articleLink: String = "",
                      feedName: String = "", maxSuggestions: Int = 10) -> [(word: String, difficulty: WordDifficulty, sentence: String)] {
        let uniqueWords = Set(tokenise(text).map { $0.lowercased() })
        let sentences = splitSentences(text)
        var candidates: [(word: String, difficulty: WordDifficulty, sentence: String)] = []
        for word in uniqueWords {
            if contains(word) || word.count < 4 || word.allSatisfy({ $0.isNumber }) { continue }
            let diff = WordDifficultyEstimator.estimate(word)
            if diff == .basic { continue }
            let ctx = sentences.first { $0.lowercased().contains(word) } ?? ""
            candidates.append((word, diff, ctx))
        }
        candidates.sort { a, b in if a.difficulty != b.difficulty { return a.difficulty > b.difficulty }; return a.word < b.word }
        return Array(candidates.prefix(maxSuggestions))
    }

    // MARK: - Analytics

    /// Compute aggregate vocabulary statistics including word counts, review accuracy,
    /// streaks, and top contributing feeds.
    func stats() -> VocabularyStats {
        let all = Array(entries.values); let now = Date()
        var byDiff: [WordDifficulty: Int] = [:]; for d in WordDifficulty.allCases { byDiff[d] = 0 }
        all.forEach { byDiff[$0.difficulty, default: 0] += 1 }
        var byMast: [MasteryLevel: Int] = [:]; for m in MasteryLevel.allCases { byMast[m] = 0 }
        all.forEach { byMast[$0.mastery, default: 0] += 1 }
        let sevenAgo = calendar.date(byAdding: .day, value: -7, to: now) ?? now
        let thirtyAgo = calendar.date(byAdding: .day, value: -30, to: now) ?? now
        let last7 = all.filter { $0.addedDate >= sevenAgo }.count
        let last30 = all.filter { $0.addedDate >= thirtyAgo }.count
        let totalReviews = all.reduce(0) { $0 + $1.reviewCount }
        let totalCorrect = all.reduce(0) { $0 + $1.correctCount }
        let avgAcc = totalReviews > 0 ? Double(totalCorrect) / Double(totalReviews) : 0.0
        let due = all.filter { e in guard let n = e.nextReviewDate else { return true }; return n <= now }.count
        var feedCounts: [String: Int] = [:]
        all.forEach { e in for c in e.contexts { feedCounts[c.feedName, default: 0] += 1 } }
        let topFeeds = feedCounts.sorted { $0.value > $1.value }.prefix(5).map { (name: $0.key, count: $0.value) }
        let (current, longest) = calculateStreaks(all)
        return VocabularyStats(totalWords: all.count, byDifficulty: byDiff, byMastery: byMast,
            wordsAddedLast7Days: last7, wordsAddedLast30Days: last30, totalReviews: totalReviews,
            averageAccuracy: avgAcc, dueForReview: due, topFeeds: topFeeds,
            longestStreak: longest, currentStreak: current)
    }

    /// All words that have at least one context from the given feed.
    func wordsFromFeed(_ feedName: String) -> [VocabularyEntry] {
        let lower = feedName.lowercased()
        return entries.values.filter { $0.contexts.contains { $0.feedName.lowercased() == lower } }
    }

    // MARK: - Export / Import

    /// Export the entire vocabulary as a JSON string.
    func exportJSON() -> String {
        guard let data = try? JSONEncoder().encode(allWords()) else { return "[]" }
        return String(data: data, encoding: .utf8) ?? "[]"
    }

    /// Import vocabulary entries from JSON, adding only words not already present.
    /// Rejects payloads over 10 MB. Returns the number of new words imported.
    @discardableResult
    func importJSON(_ json: String) -> Int {
        guard json.utf8.count <= 10_485_760,
              let data = json.data(using: .utf8),
              let imported = try? JSONDecoder().decode([VocabularyEntry].self, from: data) else { return 0 }
        var count = 0
        for entry in imported { let key = normalise(entry.word); guard !key.isEmpty else { continue }
            if entries[key] == nil { entries[key] = entry; count += 1 } }
        save(); return count
    }

    /// Delete all vocabulary entries.
    func reset() { entries.removeAll(); save() }

    // MARK: - Persistence

    private struct PersistenceData: Codable { let entries: [VocabularyEntry] }

    private func save() {
        guard let path = persistencePath else { return }
        if let encoded = try? JSONEncoder().encode(PersistenceData(entries: Array(entries.values))) {
            try? encoded.write(to: path, options: .atomic)
        }
    }

    private func load() {
        guard let path = persistencePath, FileManager.default.fileExists(atPath: path.path),
              let data = try? Data(contentsOf: path),
              let decoded = try? JSONDecoder().decode(PersistenceData.self, from: data) else { return }
        for entry in decoded.entries { let key = normalise(entry.word); if !key.isEmpty { entries[key] = entry } }
    }

    // MARK: - Helpers

    private func normalise(_ word: String) -> String { word.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }

    private func tokenise(_ text: String) -> [String] {
        text.components(separatedBy: CharacterSet.letters.inverted).filter { $0.count >= 2 }
    }

    private func splitSentences(_ text: String) -> [String] {
        text.components(separatedBy: CharacterSet(charactersIn: ".!?"))
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
    }

    private func calculateStreaks(_ words: [VocabularyEntry]) -> (current: Int, longest: Int) {
        guard !words.isEmpty else { return (0, 0) }
        var days = Set<String>(); let fmt = DateFormatter(); fmt.dateFormat = "yyyy-MM-dd"
        for w in words { days.insert(fmt.string(from: w.addedDate)) }
        let sorted = days.sorted().reversed().compactMap { fmt.date(from: $0) }
        guard !sorted.isEmpty else { return (0, 0) }
        var current = 1, longest = 1, streak = 1
        let today = calendar.startOfDay(for: Date())
        let mostRecent = calendar.startOfDay(for: sorted[0])
        let daysDiff = calendar.dateComponents([.day], from: mostRecent, to: today).day ?? 0
        if daysDiff > 1 { current = 0 }
        // Track whether the consecutive run still connects to the most
        // recent date.  Once a gap breaks the chain, older consecutive
        // runs must not inflate `current`.
        var currentStreakBroken = daysDiff > 1
        for i in 1..<sorted.count {
            let prev = calendar.startOfDay(for: sorted[i-1])
            let curr = calendar.startOfDay(for: sorted[i])
            let gap = calendar.dateComponents([.day], from: curr, to: prev).day ?? 0
            if gap == 1 {
                streak += 1
                longest = max(longest, streak)
                if !currentStreakBroken { current = streak }
            } else {
                streak = 1
                currentStreakBroken = true
            }
        }
        longest = max(longest, streak); return (current, longest)
    }
}
