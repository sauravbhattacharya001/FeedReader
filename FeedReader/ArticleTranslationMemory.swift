//
//  ArticleTranslationMemory.swift
//  FeedReader
//
//  A personal translation memory for language learners who follow
//  foreign-language feeds. Stores phrase pairs (source → translation)
//  encountered across articles, building a reusable glossary over time.
//
//  Features:
//  - Add/edit/delete translation entries with source & target language
//  - Auto-detect source language using ArticleLanguageDetector trigrams
//  - Fuzzy search across source and translated phrases
//  - Frequency tracking: how often a phrase appears across articles
//  - Confidence scoring: user-rated mastery per entry (0-5)
//  - Spaced repetition review queue based on mastery level
//  - Category/topic grouping for organized study
//  - Statistics: entries per language pair, mastery distribution
//  - Export as CSV, JSON, or Anki-compatible TSV
//  - Import from CSV/JSON
//  - Duplicate detection with similarity threshold
//
//  Persistence: JSON file in Documents directory.
//

import Foundation

// MARK: - Notifications

extension Notification.Name {
    /// Posted when the translation memory changes (entry added, edited, deleted, reviewed).
    static let translationMemoryDidChange = Notification.Name("TranslationMemoryDidChangeNotification")
}

// MARK: - Models

/// A single translation entry pairing a source phrase with its translation.
struct TranslationEntry: Codable, Identifiable {
    let id: String
    var sourcePhrase: String
    var translatedPhrase: String
    var sourceLanguage: String       // ISO 639-1 code (e.g. "fr")
    var targetLanguage: String       // ISO 639-1 code (e.g. "en")
    var category: String             // user-defined topic (e.g. "Politics", "Tech")
    var notes: String                // user notes or usage context
    var articleIds: [String]         // articles where this phrase was encountered
    var masteryLevel: Int            // 0-5, spaced repetition quality rating
    var occurrenceCount: Int         // times seen across articles
    var createdDate: String          // ISO 8601
    var lastReviewedDate: String?    // ISO 8601, nil if never reviewed
    var nextReviewDate: String?      // ISO 8601, computed from spaced repetition
    var reviewCount: Int             // total review sessions
}

/// A language pair with aggregated stats.
struct LanguagePairStats: Codable {
    let sourceLanguage: String
    let targetLanguage: String
    var entryCount: Int
    var averageMastery: Double
    var totalReviews: Int
}

/// Review session result.
struct ReviewResult: Codable {
    let entryId: String
    let quality: Int           // 0-5 rating
    let reviewedDate: String   // ISO 8601
    let responseTimeSeconds: Double
}

/// Export format options.
enum TranslationExportFormat: String, CaseIterable {
    case json = "json"
    case csv = "csv"
    case ankiTSV = "anki_tsv"  // Tab-separated for Anki import
}

// MARK: - Translation Memory Manager

/// Manages a persistent translation memory with spaced repetition review.
class ArticleTranslationMemory {

    /// Shared singleton instance.
    static let shared = ArticleTranslationMemory()

    /// All translation entries.
    private(set) var entries: [TranslationEntry] = []

    /// Review history.
    private(set) var reviewHistory: [ReviewResult] = []

    private let fileManager = FileManager.default
    private let entriesFileName = "translation_memory_entries.json"
    private let reviewFileName = "translation_memory_reviews.json"

    // Spaced repetition intervals in days, indexed by mastery level 0-5.
    private let reviewIntervals: [Int] = [0, 1, 3, 7, 14, 30]

    private var dateFormatter: DateFormatter {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd'T'HH:mm:ssZ"
        f.locale = Locale(identifier: "en_US_POSIX")
        return f
    }

    private var dayFormatter: DateFormatter {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.locale = Locale(identifier: "en_US_POSIX")
        return f
    }

    // MARK: - Init

    private init() {
        loadEntries()
        loadReviewHistory()
    }

    // MARK: - Persistence

    private func documentsURL() -> URL {
        return fileManager.urls(for: .documentDirectory, in: .userDomainMask)[0]
    }

    private func loadEntries() {
        let url = documentsURL().appendingPathComponent(entriesFileName)
        guard let data = try? Data(contentsOf: url) else { return }
        entries = (try? JSONDecoder().decode([TranslationEntry].self, from: data)) ?? []
    }

    private func saveEntries() {
        let url = documentsURL().appendingPathComponent(entriesFileName)
        if let data = try? JSONEncoder().encode(entries) {
            try? data.write(to: url, options: .atomic)
        }
        NotificationCenter.default.post(name: .translationMemoryDidChange, object: nil)
    }

    private func loadReviewHistory() {
        let url = documentsURL().appendingPathComponent(reviewFileName)
        guard let data = try? Data(contentsOf: url) else { return }
        reviewHistory = (try? JSONDecoder().decode([ReviewResult].self, from: data)) ?? []
    }

    private func saveReviewHistory() {
        let url = documentsURL().appendingPathComponent(reviewFileName)
        if let data = try? JSONEncoder().encode(reviewHistory) {
            try? data.write(to: url, options: .atomic)
        }
    }

    // MARK: - CRUD

    /// Add a new translation entry. Returns the created entry or nil if duplicate detected.
    @discardableResult
    func addEntry(
        sourcePhrase: String,
        translatedPhrase: String,
        sourceLanguage: String,
        targetLanguage: String,
        category: String = "General",
        notes: String = "",
        articleId: String? = nil
    ) -> TranslationEntry? {
        let trimmedSource = sourcePhrase.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedTranslation = translatedPhrase.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !trimmedSource.isEmpty, !trimmedTranslation.isEmpty else { return nil }

        // Check for near-duplicates
        if let existing = findDuplicate(source: trimmedSource, sourceLang: sourceLanguage, targetLang: targetLanguage) {
            // Increment occurrence count and add article reference
            if let idx = entries.firstIndex(where: { $0.id == existing.id }) {
                entries[idx].occurrenceCount += 1
                if let aid = articleId, !entries[idx].articleIds.contains(aid) {
                    entries[idx].articleIds.append(aid)
                }
                saveEntries()
            }
            return existing
        }

        let now = dateFormatter.string(from: Date())
        let entry = TranslationEntry(
            id: UUID().uuidString,
            sourcePhrase: trimmedSource,
            translatedPhrase: trimmedTranslation,
            sourceLanguage: sourceLanguage.lowercased(),
            targetLanguage: targetLanguage.lowercased(),
            category: category,
            notes: notes,
            articleIds: articleId != nil ? [articleId!] : [],
            masteryLevel: 0,
            occurrenceCount: 1,
            createdDate: now,
            lastReviewedDate: nil,
            nextReviewDate: now, // Due immediately
            reviewCount: 0
        )

        entries.append(entry)
        saveEntries()
        return entry
    }

    /// Update an existing entry's translation, category, or notes.
    func updateEntry(id: String, translatedPhrase: String? = nil, category: String? = nil, notes: String? = nil) -> Bool {
        guard let idx = entries.firstIndex(where: { $0.id == id }) else { return false }
        if let t = translatedPhrase { entries[idx].translatedPhrase = t }
        if let c = category { entries[idx].category = c }
        if let n = notes { entries[idx].notes = n }
        saveEntries()
        return true
    }

    /// Delete an entry by ID.
    @discardableResult
    func deleteEntry(id: String) -> Bool {
        let before = entries.count
        entries.removeAll { $0.id == id }
        if entries.count < before {
            saveEntries()
            return true
        }
        return false
    }

    /// Delete all entries for a specific language pair.
    func deleteLanguagePair(source: String, target: String) -> Int {
        let before = entries.count
        entries.removeAll { $0.sourceLanguage == source && $0.targetLanguage == target }
        let removed = before - entries.count
        if removed > 0 { saveEntries() }
        return removed
    }

    // MARK: - Search

    /// Fuzzy search across source and translated phrases.
    func search(query: String, sourceLanguage: String? = nil, targetLanguage: String? = nil, category: String? = nil) -> [TranslationEntry] {
        let q = query.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return entries }

        return entries.filter { entry in
            if let sl = sourceLanguage, entry.sourceLanguage != sl { return false }
            if let tl = targetLanguage, entry.targetLanguage != tl { return false }
            if let cat = category, entry.category.lowercased() != cat.lowercased() { return false }

            return entry.sourcePhrase.lowercased().contains(q) ||
                   entry.translatedPhrase.lowercased().contains(q) ||
                   entry.notes.lowercased().contains(q)
        }
    }

    /// Find entries from a specific article.
    func entriesForArticle(articleId: String) -> [TranslationEntry] {
        return entries.filter { $0.articleIds.contains(articleId) }
    }

    /// Get all unique categories.
    func categories() -> [String] {
        return Array(Set(entries.map { $0.category })).sorted()
    }

    /// Get all unique language pairs.
    func languagePairs() -> [(source: String, target: String)] {
        let pairs = Set(entries.map { "\($0.sourceLanguage)|\($0.targetLanguage)" })
        return pairs.sorted().map { pair in
            let parts = pair.split(separator: "|")
            return (source: String(parts[0]), target: String(parts[1]))
        }
    }

    // MARK: - Duplicate Detection

    /// Find a near-duplicate entry using normalized string comparison.
    private func findDuplicate(source: String, sourceLang: String, targetLang: String, threshold: Double = 0.85) -> TranslationEntry? {
        let normalizedSource = normalize(source)
        return entries.first { entry in
            entry.sourceLanguage == sourceLang &&
            entry.targetLanguage == targetLang &&
            similarity(normalize(entry.sourcePhrase), normalizedSource) >= threshold
        }
    }

    /// Normalize a phrase for comparison: lowercase, strip diacritics, collapse whitespace.
    private func normalize(_ text: String) -> String {
        return text.lowercased()
            .folding(options: .diacriticInsensitive, locale: nil)
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }

    /// Compute Jaccard similarity between two strings based on character bigrams.
    private func similarity(_ a: String, _ b: String) -> Double {
        let bigramsA = Set(bigrams(a))
        let bigramsB = Set(bigrams(b))
        guard !bigramsA.isEmpty || !bigramsB.isEmpty else { return 1.0 }
        let intersection = bigramsA.intersection(bigramsB).count
        let union = bigramsA.union(bigramsB).count
        return Double(intersection) / Double(union)
    }

    /// Extract character bigrams from a string.
    private func bigrams(_ text: String) -> [String] {
        guard text.count >= 2 else { return [text] }
        let chars = Array(text)
        return (0..<chars.count - 1).map { String(chars[$0]) + String(chars[$0 + 1]) }
    }

    // MARK: - Spaced Repetition Review

    /// Get entries due for review, sorted by overdue-ness.
    func reviewQueue(limit: Int = 20) -> [TranslationEntry] {
        let now = Date()
        return entries
            .filter { entry in
                guard let nextStr = entry.nextReviewDate,
                      let nextDate = dateFormatter.date(from: nextStr) else { return true }
                return nextDate <= now
            }
            .sorted { a, b in
                // Lower mastery first, then older review dates
                if a.masteryLevel != b.masteryLevel { return a.masteryLevel < b.masteryLevel }
                return (a.lastReviewedDate ?? "") < (b.lastReviewedDate ?? "")
            }
            .prefix(limit)
            .map { $0 }
    }

    /// Record a review result and update spaced repetition scheduling.
    /// Quality: 0 = complete blank, 1 = wrong, 2 = hard, 3 = okay, 4 = good, 5 = perfect.
    func recordReview(entryId: String, quality: Int, responseTimeSeconds: Double = 0) -> Bool {
        guard let idx = entries.firstIndex(where: { $0.id == entryId }) else { return false }
        let clampedQuality = max(0, min(5, quality))
        let now = Date()
        let nowStr = dateFormatter.string(from: now)

        // Update mastery using SM-2 inspired logic
        if clampedQuality >= 3 {
            entries[idx].masteryLevel = min(5, entries[idx].masteryLevel + 1)
        } else {
            entries[idx].masteryLevel = max(0, entries[idx].masteryLevel - 1)
        }

        entries[idx].lastReviewedDate = nowStr
        entries[idx].reviewCount += 1

        // Schedule next review
        let intervalDays = reviewIntervals[entries[idx].masteryLevel]
        let nextDate = Calendar.current.date(byAdding: .day, value: intervalDays, to: now) ?? now
        entries[idx].nextReviewDate = dateFormatter.string(from: nextDate)

        // Save review result
        let result = ReviewResult(
            entryId: entryId,
            quality: clampedQuality,
            reviewedDate: nowStr,
            responseTimeSeconds: responseTimeSeconds
        )
        reviewHistory.append(result)

        saveEntries()
        saveReviewHistory()
        return true
    }

    // MARK: - Statistics

    /// Get stats per language pair.
    func languagePairStats() -> [LanguagePairStats] {
        let pairs = languagePairs()
        return pairs.map { pair in
            let pairEntries = entries.filter { $0.sourceLanguage == pair.source && $0.targetLanguage == pair.target }
            let avgMastery = pairEntries.isEmpty ? 0.0 : Double(pairEntries.map { $0.masteryLevel }.reduce(0, +)) / Double(pairEntries.count)
            let totalReviews = pairEntries.map { $0.reviewCount }.reduce(0, +)
            return LanguagePairStats(
                sourceLanguage: pair.source,
                targetLanguage: pair.target,
                entryCount: pairEntries.count,
                averageMastery: avgMastery,
                totalReviews: totalReviews
            )
        }
    }

    /// Mastery distribution: count of entries at each level 0-5.
    func masteryDistribution() -> [Int: Int] {
        var dist: [Int: Int] = [:]
        for level in 0...5 { dist[level] = 0 }
        for entry in entries {
            dist[entry.masteryLevel, default: 0] += 1
        }
        return dist
    }

    /// Overall stats summary.
    func summary() -> (totalEntries: Int, languagePairs: Int, dueForReview: Int, averageMastery: Double, totalReviews: Int) {
        let due = reviewQueue(limit: Int.max).count
        let avgMastery = entries.isEmpty ? 0.0 : Double(entries.map { $0.masteryLevel }.reduce(0, +)) / Double(entries.count)
        let totalRevs = entries.map { $0.reviewCount }.reduce(0, +)
        return (entries.count, languagePairs().count, due, avgMastery, totalRevs)
    }

    // MARK: - Export

    /// Export entries in the specified format.
    func export(format: TranslationExportFormat, sourceLanguage: String? = nil, targetLanguage: String? = nil, category: String? = nil) -> String {
        var filtered = entries
        if let sl = sourceLanguage { filtered = filtered.filter { $0.sourceLanguage == sl } }
        if let tl = targetLanguage { filtered = filtered.filter { $0.targetLanguage == tl } }
        if let cat = category { filtered = filtered.filter { $0.category == cat } }

        switch format {
        case .json:
            return exportJSON(filtered)
        case .csv:
            return exportCSV(filtered)
        case .ankiTSV:
            return exportAnkiTSV(filtered)
        }
    }

    private func exportJSON(_ items: [TranslationEntry]) -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(items),
              let str = String(data: data, encoding: .utf8) else { return "[]" }
        return str
    }

    private func exportCSV(_ items: [TranslationEntry]) -> String {
        var lines = ["source_phrase,translated_phrase,source_lang,target_lang,category,mastery,occurrences,notes"]
        for entry in items {
            let row = [
                csvEscape(entry.sourcePhrase),
                csvEscape(entry.translatedPhrase),
                entry.sourceLanguage,
                entry.targetLanguage,
                csvEscape(entry.category),
                "\(entry.masteryLevel)",
                "\(entry.occurrenceCount)",
                csvEscape(entry.notes)
            ]
            lines.append(row.joined(separator: ","))
        }
        return lines.joined(separator: "\n")
    }

    private func exportAnkiTSV(_ items: [TranslationEntry]) -> String {
        // Anki basic format: front\tback\ttags
        var lines: [String] = []
        for entry in items {
            let front = entry.sourcePhrase.replacingOccurrences(of: "\t", with: " ")
            let back = entry.translatedPhrase.replacingOccurrences(of: "\t", with: " ")
            let tags = "\(entry.sourceLanguage)::\(entry.targetLanguage) \(entry.category.replacingOccurrences(of: " ", with: "_"))"
            lines.append("\(front)\t\(back)\t\(tags)")
        }
        return lines.joined(separator: "\n")
    }

    private func csvEscape(_ text: String) -> String {
        let escaped = text.replacingOccurrences(of: "\"", with: "\"\"")
        return text.contains(",") || text.contains("\"") || text.contains("\n")
            ? "\"\(escaped)\""
            : escaped
    }

    // MARK: - Import

    /// Import entries from a CSV string. Returns count of entries imported.
    func importCSV(_ csvString: String, defaultSourceLang: String = "en", defaultTargetLang: String = "en") -> Int {
        let lines = csvString.components(separatedBy: .newlines).filter { !$0.isEmpty }
        guard lines.count > 1 else { return 0 }

        var imported = 0
        for line in lines.dropFirst() { // Skip header
            let fields = parseCSVLine(line)
            guard fields.count >= 2 else { continue }

            let source = fields[0]
            let translated = fields[1]
            let srcLang = fields.count > 2 ? fields[2] : defaultSourceLang
            let tgtLang = fields.count > 3 ? fields[3] : defaultTargetLang
            let cat = fields.count > 4 ? fields[4] : "Imported"
            let notes = fields.count > 7 ? fields[7] : ""

            if addEntry(sourcePhrase: source, translatedPhrase: translated,
                        sourceLanguage: srcLang, targetLanguage: tgtLang,
                        category: cat, notes: notes) != nil {
                imported += 1
            }
        }
        return imported
    }

    /// Simple CSV line parser that handles quoted fields.
    private func parseCSVLine(_ line: String) -> [String] {
        var fields: [String] = []
        var current = ""
        var inQuotes = false

        for char in line {
            if char == "\"" {
                inQuotes.toggle()
            } else if char == "," && !inQuotes {
                fields.append(current)
                current = ""
            } else {
                current.append(char)
            }
        }
        fields.append(current)
        return fields.map { $0.trimmingCharacters(in: .whitespaces) }
    }

    // MARK: - Bulk Operations

    /// Merge another translation memory's entries into this one.
    func merge(entries newEntries: [TranslationEntry]) -> (added: Int, merged: Int) {
        var added = 0
        var merged = 0

        for entry in newEntries {
            if let result = addEntry(
                sourcePhrase: entry.sourcePhrase,
                translatedPhrase: entry.translatedPhrase,
                sourceLanguage: entry.sourceLanguage,
                targetLanguage: entry.targetLanguage,
                category: entry.category,
                notes: entry.notes
            ) {
                // If the returned entry has occurrenceCount > 1, it was merged with existing
                if result.occurrenceCount > 1 {
                    merged += 1
                } else {
                    added += 1
                }
            }
        }
        return (added, merged)
    }

    /// Reset all mastery levels to 0 (start fresh review cycle).
    func resetAllMastery() {
        let now = dateFormatter.string(from: Date())
        for i in entries.indices {
            entries[i].masteryLevel = 0
            entries[i].nextReviewDate = now
        }
        saveEntries()
    }

    /// Remove all entries and review history.
    func clearAll() {
        entries.removeAll()
        reviewHistory.removeAll()
        saveEntries()
        saveReviewHistory()
    }
}
