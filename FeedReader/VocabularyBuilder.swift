//
//  VocabularyBuilder.swift
//  FeedReader
//
//  Extracts and tracks vocabulary words from articles the user reads.
//  Maintains a personal word list with definitions, context sentences,
//  mastery levels, and spaced review scheduling.
//
//  Features:
//  - Extract uncommon/interesting words from article text
//  - Track words with source article, context sentence, and date
//  - Mastery levels: New → Learning → Familiar → Mastered
//  - Spaced review scheduling based on mastery
//  - Word frequency stats and category grouping
//  - Export vocabulary list as JSON or CSV
//  - Filter by mastery level, date range, or source feed
//
//  Persistence: UserDefaults via Codable.
//

import Foundation

// MARK: - Notifications

extension Notification.Name {
    /// Posted when a new word is added to the vocabulary.
    static let vocabularyDidUpdate = Notification.Name("VocabularyDidUpdateNotification")
    /// Posted when a word's mastery level changes.
    static let vocabularyMasteryDidChange = Notification.Name("VocabularyMasteryDidChangeNotification")
}

// MARK: - VocabularyWord

/// A single vocabulary word tracked by the builder.
struct VocabularyWord: Codable, Equatable {
    
    /// Mastery level for spaced repetition.
    enum MasteryLevel: Int, Codable, Comparable {
        case new = 0
        case learning = 1
        case familiar = 2
        case mastered = 3
        
        static func < (lhs: MasteryLevel, rhs: MasteryLevel) -> Bool {
            return lhs.rawValue < rhs.rawValue
        }
        
        var displayName: String {
            switch self {
            case .new: return "New"
            case .learning: return "Learning"
            case .familiar: return "Familiar"
            case .mastered: return "Mastered"
            }
        }
        
        /// Days until next review at this mastery level.
        var reviewIntervalDays: Int {
            switch self {
            case .new: return 1
            case .learning: return 3
            case .familiar: return 7
            case .mastered: return 30
            }
        }
    }
    
    let word: String
    let contextSentence: String
    let sourceArticleTitle: String
    let sourceFeedName: String
    let dateAdded: Date
    var masteryLevel: MasteryLevel
    var lastReviewed: Date?
    var reviewCount: Int
    var nextReviewDate: Date
    
    init(word: String, contextSentence: String, sourceArticleTitle: String,
         sourceFeedName: String, dateAdded: Date = Date()) {
        self.word = word.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        self.contextSentence = contextSentence
        self.sourceArticleTitle = sourceArticleTitle
        self.sourceFeedName = sourceFeedName
        self.dateAdded = dateAdded
        self.masteryLevel = .new
        self.lastReviewed = nil
        self.reviewCount = 0
        self.nextReviewDate = dateAdded.addingTimeInterval(TimeInterval(MasteryLevel.new.reviewIntervalDays * 86400))
    }
    
    static func == (lhs: VocabularyWord, rhs: VocabularyWord) -> Bool {
        return lhs.word == rhs.word
    }
}

// MARK: - VocabularyStats

/// Summary statistics for the vocabulary.
struct VocabularyStats {
    let totalWords: Int
    let newCount: Int
    let learningCount: Int
    let familiarCount: Int
    let masteredCount: Int
    let wordsAddedToday: Int
    let wordsAddedThisWeek: Int
    let dueForReview: Int
    let topSources: [(feed: String, count: Int)]
    
    var masteryPercentage: Double {
        guard totalWords > 0 else { return 0.0 }
        return Double(masteredCount) / Double(totalWords) * 100.0
    }
}

// MARK: - VocabularyBuilder

/// Manages the user's vocabulary word list extracted from articles.
class VocabularyBuilder {
    
    // MARK: - Singleton
    
    static let shared = VocabularyBuilder()
    
    // MARK: - Properties
    
    private(set) var words: [VocabularyWord] = []
    private let storageKey = "VocabularyBuilder_Words"
    
    /// Common English words to exclude from vocabulary extraction.
    /// These are the ~300 most frequent English words that aren't interesting to learn.
    private let commonWords: Set<String> = {
        let list = [
            "the", "be", "to", "of", "and", "a", "in", "that", "have", "i",
            "it", "for", "not", "on", "with", "he", "as", "you", "do", "at",
            "this", "but", "his", "by", "from", "they", "we", "say", "her", "she",
            "or", "an", "will", "my", "one", "all", "would", "there", "their", "what",
            "so", "up", "out", "if", "about", "who", "get", "which", "go", "me",
            "when", "make", "can", "like", "time", "no", "just", "him", "know", "take",
            "people", "into", "year", "your", "good", "some", "could", "them", "see",
            "other", "than", "then", "now", "look", "only", "come", "its", "over",
            "think", "also", "back", "after", "use", "two", "how", "our", "work",
            "first", "well", "way", "even", "new", "want", "because", "any", "these",
            "give", "day", "most", "us", "was", "is", "are", "been", "were", "had",
            "has", "did", "said", "each", "tell", "does", "set", "three", "very",
            "hand", "high", "keep", "last", "long", "made", "much", "must", "name",
            "never", "next", "old", "own", "part", "place", "same", "show", "side",
            "small", "still", "such", "sure", "thing", "too", "turn", "here", "why",
            "ask", "went", "men", "read", "need", "land", "off", "may", "might",
            "while", "found", "big", "between", "should", "home", "more", "world",
            "being", "those", "before", "many", "where", "through", "right", "down",
            "still", "find", "head", "end", "few", "house", "start", "got", "going",
            "don", "let", "put", "great", "since", "every", "another", "under", "been",
            "left", "run", "away", "help", "always", "near", "around", "live", "point",
            "hard", "something", "school", "state", "number", "water", "called", "may",
            "people", "than", "been", "many", "then", "just", "also", "that", "into",
            "very", "when", "come", "more", "made", "after", "did", "some", "could",
            "other", "about", "time", "these", "only", "like", "over", "such",
            "than", "where", "most", "them", "same", "been", "said", "will", "each",
            "having", "doing", "getting", "making", "looking", "using", "working",
            "going", "coming", "being", "seeing", "saying", "taking", "thinking",
            "really", "would", "should", "could", "might", "shall", "however",
            "already", "often", "until", "without", "during", "both", "between",
            "among", "per", "within", "against", "along", "whether", "though",
            "although", "across", "yet", "quite", "ever", "ago", "almost",
            "become", "became", "enough", "rather", "whose", "nothing", "less",
            "else", "maybe", "perhaps"
        ]
        return Set(list)
    }()
    
    // MARK: - Initialization
    
    private init() {
        loadWords()
    }
    
    // MARK: - Persistence
    
    private func loadWords() {
        guard let data = UserDefaults.standard.data(forKey: storageKey) else { return }
        do {
            words = try JSONDecoder().decode([VocabularyWord].self, from: data)
        } catch {
            print("VocabularyBuilder: Failed to load words: \(error)")
        }
    }
    
    private func saveWords() {
        do {
            let data = try JSONEncoder().encode(words)
            UserDefaults.standard.set(data, forKey: storageKey)
        } catch {
            print("VocabularyBuilder: Failed to save words: \(error)")
        }
    }
    
    // MARK: - Word Extraction
    
    /// Extracts uncommon words from article text.
    /// Words must be 6+ characters, not in the common words list,
    /// and contain only alphabetic characters.
    func extractWords(from text: String) -> [String] {
        let cleaned = text.lowercased()
            .components(separatedBy: CharacterSet.letters.inverted)
            .filter { word in
                word.count >= 6 &&
                !commonWords.contains(word) &&
                word.rangeOfCharacter(from: CharacterSet.letters.inverted) == nil
            }
        
        // Deduplicate while preserving order
        var seen = Set<String>()
        return cleaned.filter { seen.insert($0).inserted }
    }
    
    /// Finds the sentence containing a given word in the source text.
    func contextSentence(for word: String, in text: String) -> String {
        let sentences = text.components(separatedBy: CharacterSet(charactersIn: ".!?"))
        for sentence in sentences {
            if sentence.lowercased().contains(word.lowercased()) {
                let trimmed = sentence.trimmingCharacters(in: .whitespacesAndNewlines)
                if trimmed.count > 10 && trimmed.count < 300 {
                    return trimmed + "."
                }
            }
        }
        return ""
    }
    
    /// Extracts and adds interesting words from an article.
    /// Returns the list of newly added words (skips duplicates).
    @discardableResult
    func processArticle(title: String, body: String, feedName: String, maxWords: Int = 5) -> [VocabularyWord] {
        let candidates = extractWords(from: body)
        let existingWords = Set(words.map { $0.word })
        var added: [VocabularyWord] = []
        
        for candidate in candidates {
            guard !existingWords.contains(candidate) else { continue }
            guard added.count < maxWords else { break }
            
            let context = contextSentence(for: candidate, in: body)
            let vocabWord = VocabularyWord(
                word: candidate,
                contextSentence: context,
                sourceArticleTitle: title,
                sourceFeedName: feedName
            )
            added.append(vocabWord)
        }
        
        if !added.isEmpty {
            words.append(contentsOf: added)
            saveWords()
            NotificationCenter.default.post(name: .vocabularyDidUpdate, object: self)
        }
        
        return added
    }
    
    // MARK: - Word Management
    
    /// Manually add a word to the vocabulary.
    func addWord(_ word: String, context: String, articleTitle: String, feedName: String) {
        let normalized = word.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        guard !words.contains(where: { $0.word == normalized }) else { return }
        
        let vocabWord = VocabularyWord(
            word: normalized,
            contextSentence: context,
            sourceArticleTitle: articleTitle,
            sourceFeedName: feedName
        )
        words.append(vocabWord)
        saveWords()
        NotificationCenter.default.post(name: .vocabularyDidUpdate, object: self)
    }
    
    /// Remove a word from the vocabulary.
    func removeWord(_ word: String) {
        let normalized = word.lowercased()
        words.removeAll { $0.word == normalized }
        saveWords()
        NotificationCenter.default.post(name: .vocabularyDidUpdate, object: self)
    }
    
    /// Remove all words.
    func clearAll() {
        words.removeAll()
        saveWords()
        NotificationCenter.default.post(name: .vocabularyDidUpdate, object: self)
    }
    
    // MARK: - Mastery & Review
    
    /// Mark a word as reviewed and advance mastery if appropriate.
    func reviewWord(_ word: String, knewIt: Bool) {
        guard let index = words.firstIndex(where: { $0.word == word.lowercased() }) else { return }
        
        words[index].reviewCount += 1
        words[index].lastReviewed = Date()
        
        if knewIt && words[index].masteryLevel < .mastered {
            words[index].masteryLevel = VocabularyWord.MasteryLevel(
                rawValue: words[index].masteryLevel.rawValue + 1
            ) ?? .mastered
        } else if !knewIt && words[index].masteryLevel > .new {
            words[index].masteryLevel = VocabularyWord.MasteryLevel(
                rawValue: words[index].masteryLevel.rawValue - 1
            ) ?? .new
        }
        
        let interval = TimeInterval(words[index].masteryLevel.reviewIntervalDays * 86400)
        words[index].nextReviewDate = Date().addingTimeInterval(interval)
        
        saveWords()
        NotificationCenter.default.post(name: .vocabularyMasteryDidChange, object: self)
    }
    
    /// Returns words that are due for review.
    func wordsDueForReview() -> [VocabularyWord] {
        let now = Date()
        return words.filter { $0.nextReviewDate <= now && $0.masteryLevel != .mastered }
            .sorted { $0.nextReviewDate < $1.nextReviewDate }
    }
    
    // MARK: - Filtering & Search
    
    /// Filter words by mastery level.
    func words(at level: VocabularyWord.MasteryLevel) -> [VocabularyWord] {
        return words.filter { $0.masteryLevel == level }
    }
    
    /// Filter words by source feed.
    func words(fromFeed feedName: String) -> [VocabularyWord] {
        return words.filter { $0.sourceFeedName == feedName }
    }
    
    /// Search words by prefix or substring.
    func searchWords(_ query: String) -> [VocabularyWord] {
        let q = query.lowercased()
        return words.filter { $0.word.contains(q) }
    }
    
    /// Words added within a date range.
    func words(from startDate: Date, to endDate: Date) -> [VocabularyWord] {
        return words.filter { $0.dateAdded >= startDate && $0.dateAdded <= endDate }
    }
    
    // MARK: - Statistics
    
    /// Generate vocabulary statistics.
    func generateStats() -> VocabularyStats {
        let now = Date()
        let calendar = Calendar.current
        let todayStart = calendar.startOfDay(for: now)
        let weekStart = calendar.date(byAdding: .day, value: -7, to: now) ?? now
        
        let byFeed = Dictionary(grouping: words, by: { $0.sourceFeedName })
        let topSources = byFeed.map { (feed: $0.key, count: $0.value.count) }
            .sorted { $0.count > $1.count }
            .prefix(5)
        
        return VocabularyStats(
            totalWords: words.count,
            newCount: words.filter { $0.masteryLevel == .new }.count,
            learningCount: words.filter { $0.masteryLevel == .learning }.count,
            familiarCount: words.filter { $0.masteryLevel == .familiar }.count,
            masteredCount: words.filter { $0.masteryLevel == .mastered }.count,
            wordsAddedToday: words.filter { $0.dateAdded >= todayStart }.count,
            wordsAddedThisWeek: words.filter { $0.dateAdded >= weekStart }.count,
            dueForReview: wordsDueForReview().count,
            topSources: Array(topSources)
        )
    }
    
    // MARK: - Export
    
    /// Export vocabulary as JSON data.
    func exportAsJSON() -> Data? {
        return try? JSONEncoder().encode(words)
    }
    
    /// Export vocabulary as CSV string.
    func exportAsCSV() -> String {
        var csv = "Word,Mastery,Context,Source Article,Source Feed,Date Added,Review Count\n"
        let dateFormatter = DateFormatter()
        dateFormatter.dateStyle = .medium
        
        for word in words {
            let escapedContext = word.contextSentence.replacingOccurrences(of: "\"", with: "\"\"")
            let escapedTitle = word.sourceArticleTitle.replacingOccurrences(of: "\"", with: "\"\"")
            csv += "\"\(word.word)\",\"\(word.masteryLevel.displayName)\","
            csv += "\"\(escapedContext)\",\"\(escapedTitle)\","
            csv += "\"\(word.sourceFeedName)\",\"\(dateFormatter.string(from: word.dateAdded))\","
            csv += "\(word.reviewCount)\n"
        }
        
        return csv
    }
    
    /// Import vocabulary from JSON data (merges, skipping duplicates).
    func importFromJSON(_ data: Data) -> Int {
        guard let imported = try? JSONDecoder().decode([VocabularyWord].self, from: data) else { return 0 }
        let existingWords = Set(words.map { $0.word })
        let newWords = imported.filter { !existingWords.contains($0.word) }
        words.append(contentsOf: newWords)
        saveWords()
        if !newWords.isEmpty {
            NotificationCenter.default.post(name: .vocabularyDidUpdate, object: self)
        }
        return newWords.count
    }
}
