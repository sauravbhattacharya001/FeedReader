//
//  ArticleQuoteJournal.swift
//  FeedReader
//
//  A personal commonplace book for saving favorite excerpts and quotes
//  from articles. Captures the exact text, source attribution, optional
//  personal reflection, and tags for organization.
//
//  Features:
//  - Save quotes with source article URL, title, author, and date
//  - Add personal reflections/notes to each quote
//  - Tag quotes for categorization (e.g. "wisdom", "science", "funny")
//  - Search quotes by text, tag, source, or date range
//  - Favorite/star quotes for quick access
//  - Daily random quote ("Quote of the Day")
//  - Export as Markdown, JSON, or plain text
//  - Statistics: quotes per feed, most-used tags, collection growth
//
//  Persistence: JSON file in Documents directory.
//

import Foundation
import os.log

// MARK: - Notifications

extension Notification.Name {
    /// Posted when a quote is added, updated, or removed.
    static let quoteJournalDidChange = Notification.Name("QuoteJournalDidChangeNotification")
}

// MARK: - SavedQuote

/// A single saved quote with source attribution and metadata.
struct SavedQuote: Codable, Equatable {
    /// Unique identifier.
    let id: String
    /// The quoted text excerpt.
    var text: String
    /// Optional personal reflection or note about this quote.
    var reflection: String?
    /// Source article title.
    var articleTitle: String
    /// Source article URL.
    var articleURL: String
    /// Source article author (if known).
    var articleAuthor: String?
    /// Source feed name.
    var feedName: String?
    /// User-assigned tags for organization.
    var tags: [String]
    /// Whether this quote is starred/favorited.
    var isFavorite: Bool
    /// Date the quote was saved.
    let savedDate: Date
    /// Date the quote was last edited (nil if never edited).
    var lastEdited: Date?

    static func == (lhs: SavedQuote, rhs: SavedQuote) -> Bool {
        lhs.id == rhs.id
    }
}

// MARK: - QuoteSearchCriteria

/// Criteria for filtering/searching quotes.
struct QuoteSearchCriteria {
    var textQuery: String?
    var tags: [String]?
    var feedName: String?
    var favoritesOnly: Bool = false
    var fromDate: Date?
    var toDate: Date?
    var sortBy: QuoteSortOrder = .newest

    enum QuoteSortOrder {
        case newest, oldest, alphabetical
    }
}

// MARK: - QuoteJournalStats

/// Aggregate statistics about the quote journal.
struct QuoteJournalStats {
    let totalQuotes: Int
    let totalFavorites: Int
    let uniqueTags: Int
    let uniqueSources: Int
    let quotesPerFeed: [(feed: String, count: Int)]
    let topTags: [(tag: String, count: Int)]
    let oldestQuote: Date?
    let newestQuote: Date?
    let averageQuoteLength: Int
}

// MARK: - ExportFormat

/// Supported export formats for the quote journal.
enum QuoteExportFormat {
    case markdown, json, plainText
}

// MARK: - ArticleQuoteJournal

/// Manages a personal collection of saved article quotes.
///
/// Thread-safe via serial dispatch queue. All mutations persist
/// automatically to a JSON file in the app's Documents directory.
final class ArticleQuoteJournal {

    // MARK: Storage

    private var quotes: [SavedQuote] = []
    private let queue = DispatchQueue(label: "com.feedreader.quotejournal")
    private let fileURL: URL

    // MARK: Init

    /// Creates a journal backed by a JSON file.
    /// - Parameter directory: Directory for the backing file.
    ///   Defaults to the user's Documents directory.
    init(directory: URL? = nil) {
        let dir = directory
            ?? FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        self.fileURL = dir.appendingPathComponent("quote_journal.json")
        load()
    }

    // MARK: - CRUD

    /// Save a new quote from an article.
    @discardableResult
    func saveQuote(
        text: String,
        articleTitle: String,
        articleURL: String,
        articleAuthor: String? = nil,
        feedName: String? = nil,
        reflection: String? = nil,
        tags: [String] = [],
        isFavorite: Bool = false
    ) -> SavedQuote? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            os_log("saveQuote called with empty text — ignored", log: FeedReaderLogger.quotes, type: .error)
            return nil
        }

        let quote = SavedQuote(
            id: UUID().uuidString,
            text: trimmed,
            reflection: reflection?.trimmingCharacters(in: .whitespacesAndNewlines),
            articleTitle: articleTitle,
            articleURL: articleURL,
            articleAuthor: articleAuthor,
            feedName: feedName,
            tags: tags.map { $0.lowercased().trimmingCharacters(in: .whitespaces) },
            isFavorite: isFavorite,
            savedDate: Date(),
            lastEdited: nil
        )

        queue.sync {
            quotes.append(quote)
            persist()
        }
        NotificationCenter.default.post(name: .quoteJournalDidChange, object: nil)
        return quote
    }

    /// Update an existing quote's text, reflection, tags, or favorite status.
    @discardableResult
    func updateQuote(
        id: String,
        text: String? = nil,
        reflection: String? = nil,
        tags: [String]? = nil,
        isFavorite: Bool? = nil
    ) -> SavedQuote? {
        var updated: SavedQuote?
        queue.sync {
            guard let idx = quotes.firstIndex(where: { $0.id == id }) else { return }
            if let t = text {
                quotes[idx].text = t.trimmingCharacters(in: .whitespacesAndNewlines)
            }
            if let r = reflection {
                quotes[idx].reflection = r.trimmingCharacters(in: .whitespacesAndNewlines)
            }
            if let tg = tags {
                quotes[idx].tags = tg.map { $0.lowercased().trimmingCharacters(in: .whitespaces) }
            }
            if let fav = isFavorite {
                quotes[idx].isFavorite = fav
            }
            quotes[idx].lastEdited = Date()
            updated = quotes[idx]
            persist()
        }
        if updated != nil {
            NotificationCenter.default.post(name: .quoteJournalDidChange, object: nil)
        }
        return updated
    }

    /// Delete a quote by ID. Returns true if found and removed.
    @discardableResult
    func deleteQuote(id: String) -> Bool {
        var removed = false
        queue.sync {
            if let idx = quotes.firstIndex(where: { $0.id == id }) {
                quotes.remove(at: idx)
                removed = true
                persist()
            }
        }
        if removed {
            NotificationCenter.default.post(name: .quoteJournalDidChange, object: nil)
        }
        return removed
    }

    /// Toggle favorite status on a quote. Returns the new status.
    func toggleFavorite(id: String) -> Bool? {
        var newStatus: Bool?
        queue.sync {
            guard let idx = quotes.firstIndex(where: { $0.id == id }) else { return }
            quotes[idx].isFavorite.toggle()
            quotes[idx].lastEdited = Date()
            newStatus = quotes[idx].isFavorite
            persist()
        }
        if newStatus != nil {
            NotificationCenter.default.post(name: .quoteJournalDidChange, object: nil)
        }
        return newStatus
    }

    // MARK: - Retrieval

    /// Get a quote by ID.
    func quote(byID id: String) -> SavedQuote? {
        queue.sync { quotes.first { $0.id == id } }
    }

    /// Get all quotes (newest first by default).
    func allQuotes() -> [SavedQuote] {
        queue.sync { quotes.sorted { $0.savedDate > $1.savedDate } }
    }

    /// Get all favorited quotes.
    func favorites() -> [SavedQuote] {
        queue.sync {
            quotes.filter { $0.isFavorite }
                  .sorted { $0.savedDate > $1.savedDate }
        }
    }

    /// Get quotes from a specific article URL.
    func quotes(fromArticle url: String) -> [SavedQuote] {
        queue.sync {
            quotes.filter { $0.articleURL == url }
                  .sorted { $0.savedDate > $1.savedDate }
        }
    }

    /// Get all unique tags across all quotes, sorted by frequency.
    func allTags() -> [(tag: String, count: Int)] {
        queue.sync {
            var counts: [String: Int] = [:]
            for q in quotes {
                for tag in q.tags {
                    counts[tag, default: 0] += 1
                }
            }
            return counts.map { (tag: $0.key, count: $0.value) }
                         .sorted { $0.count > $1.count }
        }
    }

    // MARK: - Search

    /// Search quotes using flexible criteria.
    func search(_ criteria: QuoteSearchCriteria) -> [SavedQuote] {
        queue.sync {
            var results = quotes

            // Text query — searches quote text, reflection, article title, author
            if let query = criteria.textQuery?.lowercased(), !query.isEmpty {
                results = results.filter { q in
                    q.text.lowercased().contains(query)
                    || (q.reflection?.lowercased().contains(query) ?? false)
                    || q.articleTitle.lowercased().contains(query)
                    || (q.articleAuthor?.lowercased().contains(query) ?? false)
                }
            }

            // Tag filter — matches any of the provided tags
            if let tags = criteria.tags, !tags.isEmpty {
                let lowerTags = Set(tags.map { $0.lowercased() })
                results = results.filter { q in
                    !Set(q.tags).intersection(lowerTags).isEmpty
                }
            }

            // Feed filter
            if let feed = criteria.feedName {
                results = results.filter { $0.feedName == feed }
            }

            // Favorites only
            if criteria.favoritesOnly {
                results = results.filter { $0.isFavorite }
            }

            // Date range
            if let from = criteria.fromDate {
                results = results.filter { $0.savedDate >= from }
            }
            if let to = criteria.toDate {
                results = results.filter { $0.savedDate <= to }
            }

            // Sort
            switch criteria.sortBy {
            case .newest:
                results.sort { $0.savedDate > $1.savedDate }
            case .oldest:
                results.sort { $0.savedDate < $1.savedDate }
            case .alphabetical:
                results.sort { $0.text.lowercased() < $1.text.lowercased() }
            }

            return results
        }
    }

    // MARK: - Quote of the Day

    /// Returns a deterministic "quote of the day" based on the current date.
    /// Uses a date-seeded selection so it stays consistent within a day.
    func quoteOfTheDay() -> SavedQuote? {
        queue.sync {
            guard !quotes.isEmpty else { return nil }
            let daysSinceEpoch = Int(Date().timeIntervalSince1970 / 86400)
            let index = daysSinceEpoch % quotes.count
            let sorted = quotes.sorted { $0.id < $1.id } // stable order
            return sorted[index]
        }
    }

    /// Returns a truly random quote.
    func randomQuote() -> SavedQuote? {
        queue.sync {
            quotes.randomElement()
        }
    }

    // MARK: - Statistics

    /// Compute aggregate statistics about the journal.
    func statistics() -> QuoteJournalStats {
        queue.sync {
            var feedCounts: [String: Int] = [:]
            var tagCounts: [String: Int] = [:]
            var totalLength = 0

            for q in quotes {
                totalLength += q.text.count
                if let feed = q.feedName {
                    feedCounts[feed, default: 0] += 1
                }
                for tag in q.tags {
                    tagCounts[tag, default: 0] += 1
                }
            }

            let sortedFeeds = feedCounts.map { (feed: $0.key, count: $0.value) }
                                        .sorted { $0.count > $1.count }
            let sortedTags = tagCounts.map { (tag: $0.key, count: $0.value) }
                                      .sorted { $0.count > $1.count }
            let dates = quotes.map { $0.savedDate }

            return QuoteJournalStats(
                totalQuotes: quotes.count,
                totalFavorites: quotes.filter { $0.isFavorite }.count,
                uniqueTags: Set(quotes.flatMap { $0.tags }).count,
                uniqueSources: Set(quotes.map { $0.articleURL }).count,
                quotesPerFeed: Array(sortedFeeds.prefix(10)),
                topTags: Array(sortedTags.prefix(10)),
                oldestQuote: dates.min(),
                newestQuote: dates.max(),
                averageQuoteLength: quotes.isEmpty ? 0 : totalLength / quotes.count
            )
        }
    }

    // MARK: - Export

    /// Export the journal (or a subset) in the specified format.
    func export(
        quotes subset: [SavedQuote]? = nil,
        format: QuoteExportFormat
    ) -> String {
        let data: [SavedQuote] = queue.sync {
            subset ?? self.quotes.sorted { $0.savedDate > $1.savedDate }
        }

        switch format {
        case .markdown:
            return exportMarkdown(data)
        case .json:
            return exportJSON(data)
        case .plainText:
            return exportPlainText(data)
        }
    }

    // MARK: - Persistence

    private func persist() {
        do {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(quotes)
            try data.write(to: fileURL, options: .atomicWrite)
        } catch {
            os_log("Failed to save: %{private}s", log: FeedReaderLogger.quotes, type: .error, error.localizedDescription)
        }
    }

    private func load() {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return }
        do {
            let data = try Data(contentsOf: fileURL)
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            quotes = try decoder.decode([SavedQuote].self, from: data)
        } catch {
            os_log("Failed to load: %{private}s", log: FeedReaderLogger.quotes, type: .error, error.localizedDescription)
            quotes = []
        }
    }

    /// Delete all quotes and reset the journal.
    func reset() {
        queue.sync {
            quotes.removeAll()
            persist()
        }
        NotificationCenter.default.post(name: .quoteJournalDidChange, object: nil)
    }

    /// Total number of saved quotes.
    var count: Int {
        queue.sync { quotes.count }
    }

    // MARK: - Private Export Helpers

    private func exportMarkdown(_ data: [SavedQuote]) -> String {
        let df = DateFormatter()
        df.dateStyle = .medium
        df.timeStyle = .none

        var lines = ["# Quote Journal", ""]
        lines.append("_\(data.count) quotes exported on \(df.string(from: Date()))_")
        lines.append("")

        for q in data {
            let star = q.isFavorite ? " ⭐" : ""
            lines.append("---")
            lines.append("")
            lines.append("> \(q.text)\(star)")
            lines.append("")
            var source = "— [\(q.articleTitle)](\(q.articleURL))"
            if let author = q.articleAuthor { source += " by \(author)" }
            lines.append(source)
            if let feed = q.feedName {
                lines.append("*Feed: \(feed)*")
            }
            if !q.tags.isEmpty {
                lines.append("Tags: \(q.tags.map { "#\($0)" }.joined(separator: " "))")
            }
            if let reflection = q.reflection, !reflection.isEmpty {
                lines.append("")
                lines.append("💭 \(reflection)")
            }
            lines.append("*Saved: \(df.string(from: q.savedDate))*")
            lines.append("")
        }
        return lines.joined(separator: "\n")
    }

    private func exportJSON(_ data: [SavedQuote]) -> String {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let jsonData = try? encoder.encode(data),
              let str = String(data: jsonData, encoding: .utf8) else {
            return "[]"
        }
        return str
    }

    private func exportPlainText(_ data: [SavedQuote]) -> String {
        let df = DateFormatter()
        df.dateStyle = .medium
        df.timeStyle = .none

        var lines = ["QUOTE JOURNAL", String(repeating: "=", count: 40), ""]

        for (i, q) in data.enumerated() {
            let star = q.isFavorite ? " [★]" : ""
            lines.append("\(i + 1). \"\(q.text)\"\(star)")
            var source = "   Source: \(q.articleTitle)"
            if let author = q.articleAuthor { source += " by \(author)" }
            lines.append(source)
            lines.append("   URL: \(q.articleURL)")
            if let feed = q.feedName {
                lines.append("   Feed: \(feed)")
            }
            if !q.tags.isEmpty {
                lines.append("   Tags: \(q.tags.joined(separator: ", "))")
            }
            if let reflection = q.reflection, !reflection.isEmpty {
                lines.append("   Note: \(reflection)")
            }
            lines.append("   Saved: \(df.string(from: q.savedDate))")
            lines.append("")
        }
        return lines.joined(separator: "\n")
    }
}
