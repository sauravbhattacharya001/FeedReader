//
//  ReadingDataExporter.swift
//  FeedReader
//
//  Full reading data export/import for backup and portability.
//  Exports bookmarks, highlights, notes, reading history, collections,
//  reading streaks, and feed subscriptions into a single JSON archive.
//  Supports selective export (choose which data types to include) and
//  import with conflict resolution (skip, overwrite, merge).
//

import Foundation

// MARK: - Export Configuration

/// Which data types to include in the export.
struct ExportOptions {
    var includeBookmarks: Bool = true
    var includeHighlights: Bool = true
    var includeNotes: Bool = true
    var includeHistory: Bool = true
    var includeCollections: Bool = true
    var includeStreaks: Bool = true
    var includeFeeds: Bool = true
    var prettyPrint: Bool = true
    
    /// Export everything.
    static var all: ExportOptions { ExportOptions() }
    
    /// Annotations only (bookmarks, highlights, notes, collections).
    static var annotationsOnly: ExportOptions {
        var opts = ExportOptions()
        opts.includeHistory = false
        opts.includeStreaks = false
        opts.includeFeeds = false
        return opts
    }
}

// MARK: - Import Strategy

/// How to handle conflicts when importing data that already exists.
enum ImportConflictStrategy {
    /// Skip items that already exist.
    case skip
    /// Overwrite existing items with imported data.
    case overwrite
    /// Merge imported data (keep newer timestamp).
    case mergeKeepNewer
}

// MARK: - Export Data Models

/// Top-level archive structure.
struct ReadingDataArchive: Codable {
    let version: Int
    let exportDate: Date
    let appVersion: String
    let sections: ArchiveSections
    let metadata: ArchiveMetadata
    
    static let currentVersion = 1
}

struct ArchiveMetadata: Codable {
    let totalItems: Int
    let includedSections: [String]
    let exportDurationMs: Int
}

struct ArchiveSections: Codable {
    var bookmarks: [BookmarkExport]?
    var highlights: [HighlightExport]?
    var notes: [NoteExport]?
    var history: [HistoryExport]?
    var collections: [CollectionExport]?
    var streaks: StreakExport?
    var feeds: [FeedExport]?
}

struct BookmarkExport: Codable {
    let articleLink: String
    let articleTitle: String
    let feedName: String
    let bookmarkedDate: Date
}

struct HighlightExport: Codable {
    let id: String
    let articleLink: String
    let articleTitle: String
    let text: String
    let color: Int
    let note: String?
    let createdDate: Date
}

struct NoteExport: Codable {
    let articleLink: String
    let articleTitle: String
    let text: String
    let createdDate: Date
    let modifiedDate: Date
}

struct HistoryExport: Codable {
    let link: String
    let title: String
    let feedName: String
    let visitDate: Date
    let timeSpentSeconds: Double
    let scrollProgress: Double
}

struct CollectionExport: Codable {
    let id: String
    let name: String
    let icon: String
    let description: String
    let articleLinks: [String]
    let createdDate: Date
}

struct StreakExport: Codable {
    let currentStreak: Int
    let longestStreak: Int
    let totalArticlesRead: Int
    let dailyRecords: [DailyRecordExport]
}

struct DailyRecordExport: Codable {
    let date: Date
    let articlesRead: Int
    let goalMet: Bool
}

struct FeedExport: Codable {
    let title: String
    let url: String
    let category: String?
}

// MARK: - Import Result

struct ImportResult {
    let success: Bool
    let message: String
    let imported: ImportCounts
    let skipped: ImportCounts
    let errors: [String]
    
    var totalImported: Int {
        imported.bookmarks + imported.highlights + imported.notes +
        imported.history + imported.collections + imported.feeds
    }
}

struct ImportCounts {
    var bookmarks: Int = 0
    var highlights: Int = 0
    var notes: Int = 0
    var history: Int = 0
    var collections: Int = 0
    var feeds: Int = 0
    var streakRecords: Int = 0
}

// MARK: - Exporter

/// Exports and imports reading data for backup and portability.
class ReadingDataExporter {

    // MARK: - Import Safety Limits

    /// Maximum import file/data size (50 MB). Prevents memory exhaustion
    /// from oversized archives — a crafted multi-GB JSON payload could OOM
    /// the app during JSONDecoder.decode(). 50 MB is generous for reading
    /// data (typical exports are <1 MB).
    static let maxImportSizeBytes = 50 * 1024 * 1024

    /// Maximum items per archive section. Prevents resource exhaustion from
    /// archives with millions of entries in a single section (e.g., 10M
    /// bookmarks that each create a Story object and call into BookmarkManager).
    static let maxItemsPerSection = 50_000

    /// Maximum article links per collection. Prevents memory exhaustion from
    /// a single collection with millions of link entries.
    static let maxArticleLinksPerCollection = 10_000

    private static let iso8601DayFormatter = DateFormatting.isoDate
    
    private let bookmarkManager: BookmarkManager
    private let highlightsManager: ArticleHighlightsManager
    private let notesManager: ArticleNotesManager
    private let historyManager: ReadingHistoryManager
    private let collectionManager: ArticleCollectionManager
    private let streakTracker: ReadingStreakTracker
    private let feedManager: FeedManager
    
    /// Date formatter for consistent archive dates.
    private static let archiveDateFormatter: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()
    
    init(bookmarkManager: BookmarkManager,
         highlightsManager: ArticleHighlightsManager,
         notesManager: ArticleNotesManager,
         historyManager: ReadingHistoryManager,
         collectionManager: ArticleCollectionManager,
         streakTracker: ReadingStreakTracker,
         feedManager: FeedManager) {
        self.bookmarkManager = bookmarkManager
        self.highlightsManager = highlightsManager
        self.notesManager = notesManager
        self.historyManager = historyManager
        self.collectionManager = collectionManager
        self.streakTracker = streakTracker
        self.feedManager = feedManager
    }
    
    // MARK: - Export
    
    /// Export reading data to JSON Data.
    func exportData(options: ExportOptions = .all) -> (data: Data?, error: String?) {
        let startTime = Date()
        var sections = ArchiveSections()
        var includedSections: [String] = []
        var totalItems = 0
        
        if options.includeBookmarks {
            let bookmarks = exportBookmarks()
            sections.bookmarks = bookmarks
            includedSections.append("bookmarks")
            totalItems += bookmarks.count
        }
        
        if options.includeHighlights {
            let highlights = exportHighlights()
            sections.highlights = highlights
            includedSections.append("highlights")
            totalItems += highlights.count
        }
        
        if options.includeNotes {
            let notes = exportNotes()
            sections.notes = notes
            includedSections.append("notes")
            totalItems += notes.count
        }
        
        if options.includeHistory {
            let history = exportHistory()
            sections.history = history
            includedSections.append("history")
            totalItems += history.count
        }
        
        if options.includeCollections {
            let collections = exportCollections()
            sections.collections = collections
            includedSections.append("collections")
            totalItems += collections.count
        }
        
        if options.includeStreaks {
            let streaks = exportStreaks()
            sections.streaks = streaks
            includedSections.append("streaks")
            totalItems += streaks.dailyRecords.count
        }
        
        if options.includeFeeds {
            let feeds = exportFeeds()
            sections.feeds = feeds
            includedSections.append("feeds")
            totalItems += feeds.count
        }
        
        let durationMs = Int(Date().timeIntervalSince(startTime) * 1000)
        
        let archive = ReadingDataArchive(
            version: ReadingDataArchive.currentVersion,
            exportDate: Date(),
            appVersion: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0",
            sections: sections,
            metadata: ArchiveMetadata(
                totalItems: totalItems,
                includedSections: includedSections,
                exportDurationMs: durationMs
            )
        )
        
        let encoder = JSONCoding.iso8601Encoder
        if options.prettyPrint {
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        }
        
        do {
            let data = try encoder.encode(archive)
            return (data, nil)
        } catch {
            return (nil, "Export failed: \(error.localizedDescription)")
        }
    }
    
    /// Export to a file URL. Returns the file size in bytes.
    func exportToFile(url: URL, options: ExportOptions = .all) -> (fileSize: Int, error: String?) {
        let result = exportData(options: options)
        guard let data = result.data else {
            return (0, result.error ?? "Unknown export error")
        }
        
        do {
            try data.write(to: url, options: .atomic)
            return (data.count, nil)
        } catch {
            return (0, "Failed to write file: \(error.localizedDescription)")
        }
    }
    
    // MARK: - Import
    
    /// Import reading data from JSON Data.
    func importData(_ data: Data, strategy: ImportConflictStrategy = .skip) -> ImportResult {
        // Guard: reject oversized archives to prevent OOM during parsing
        guard data.count <= ReadingDataExporter.maxImportSizeBytes else {
            let sizeMB = String(format: "%.1f", Double(data.count) / 1_048_576.0)
            let limitMB = ReadingDataExporter.maxImportSizeBytes / 1_048_576
            return ImportResult(
                success: false,
                message: "Archive too large (\(sizeMB) MB). Maximum allowed: \(limitMB) MB.",
                imported: ImportCounts(),
                skipped: ImportCounts(),
                errors: ["Archive exceeds maximum import size of \(limitMB) MB"]
            )
        }

        let decoder = JSONCoding.iso8601Decoder
        let archive: ReadingDataArchive
        do {
            archive = try decoder.decode(ReadingDataArchive.self, from: data)
        } catch {
            return ImportResult(
                success: false,
                message: "Failed to parse archive: \(error.localizedDescription)",
                imported: ImportCounts(),
                skipped: ImportCounts(),
                errors: [error.localizedDescription]
            )
        }
        
        guard archive.version <= ReadingDataArchive.currentVersion else {
            return ImportResult(
                success: false,
                message: "Archive version \(archive.version) is newer than supported version \(ReadingDataArchive.currentVersion).",
                imported: ImportCounts(),
                skipped: ImportCounts(),
                errors: ["Unsupported archive version"]
            )
        }

        // Guard: reject archives with oversized sections to prevent
        // resource exhaustion during import (each item triggers manager
        // operations — Story creation, duplicate checks, persistence).
        let sectionCounts: [(String, Int)] = [
            ("bookmarks", archive.sections.bookmarks?.count ?? 0),
            ("highlights", archive.sections.highlights?.count ?? 0),
            ("notes", archive.sections.notes?.count ?? 0),
            ("history", archive.sections.history?.count ?? 0),
            ("collections", archive.sections.collections?.count ?? 0),
            ("feeds", archive.sections.feeds?.count ?? 0),
            ("streakRecords", archive.sections.streaks?.dailyRecords.count ?? 0),
        ]
        let limit = ReadingDataExporter.maxItemsPerSection
        for (section, count) in sectionCounts {
            if count > limit {
                return ImportResult(
                    success: false,
                    message: "Section '\(section)' has \(count) items, exceeding the maximum of \(limit).",
                    imported: ImportCounts(),
                    skipped: ImportCounts(),
                    errors: ["Section '\(section)' exceeds maximum item count (\(count) > \(limit))"]
                )
            }
        }

        // Guard: reject collections with oversized article link arrays
        if let collections = archive.sections.collections {
            let linkLimit = ReadingDataExporter.maxArticleLinksPerCollection
            for (i, col) in collections.enumerated() {
                if col.articleLinks.count > linkLimit {
                    return ImportResult(
                        success: false,
                        message: "Collection[\(i)] '\(col.name)' has \(col.articleLinks.count) article links, exceeding the maximum of \(linkLimit).",
                        imported: ImportCounts(),
                        skipped: ImportCounts(),
                        errors: ["Collection '\(col.name)' exceeds maximum article links (\(col.articleLinks.count) > \(linkLimit))"]
                    )
                }
            }
        }

        var imported = ImportCounts()
        var skipped = ImportCounts()
        var errors: [String] = []
        
        // Import bookmarks
        if let bookmarks = archive.sections.bookmarks {
            let result = importBookmarks(bookmarks, strategy: strategy)
            imported.bookmarks = result.imported
            skipped.bookmarks = result.skipped
            errors.append(contentsOf: result.errors)
        }
        
        // Import highlights
        if let highlights = archive.sections.highlights {
            let result = importHighlights(highlights, strategy: strategy)
            imported.highlights = result.imported
            skipped.highlights = result.skipped
            errors.append(contentsOf: result.errors)
        }
        
        // Import notes
        if let notes = archive.sections.notes {
            let result = importNotes(notes, strategy: strategy)
            imported.notes = result.imported
            skipped.notes = result.skipped
            errors.append(contentsOf: result.errors)
        }
        
        // Import collections
        if let collections = archive.sections.collections {
            let result = importCollections(collections, strategy: strategy)
            imported.collections = result.imported
            skipped.collections = result.skipped
            errors.append(contentsOf: result.errors)
        }
        
        let totalImported = imported.bookmarks + imported.highlights +
            imported.notes + imported.collections
        
        return ImportResult(
            success: errors.isEmpty,
            message: errors.isEmpty
                ? "Successfully imported \(totalImported) items."
                : "Import completed with \(errors.count) error(s). \(totalImported) items imported.",
            imported: imported,
            skipped: skipped,
            errors: errors
        )
    }
    
    /// Import from a file URL.
    func importFromFile(url: URL, strategy: ImportConflictStrategy = .skip) -> ImportResult {
        // Check file size before loading into memory — prevents OOM
        // from multi-GB files that would be rejected by importData()
        // anyway but only after allocating the full Data buffer.
        do {
            let attrs = try FileManager.default.attributesOfItem(atPath: url.path)
            if let fileSize = attrs[.size] as? Int,
               fileSize > ReadingDataExporter.maxImportSizeBytes {
                let sizeMB = String(format: "%.1f", Double(fileSize) / 1_048_576.0)
                let limitMB = ReadingDataExporter.maxImportSizeBytes / 1_048_576
                return ImportResult(
                    success: false,
                    message: "File too large (\(sizeMB) MB). Maximum allowed: \(limitMB) MB.",
                    imported: ImportCounts(),
                    skipped: ImportCounts(),
                    errors: ["File exceeds maximum import size of \(limitMB) MB"]
                )
            }
        } catch {
            // Fall through — file read below will report the error
        }

        do {
            let data = try Data(contentsOf: url)
            return importData(data, strategy: strategy)
        } catch {
            return ImportResult(
                success: false,
                message: "Failed to read file: \(error.localizedDescription)",
                imported: ImportCounts(),
                skipped: ImportCounts(),
                errors: [error.localizedDescription]
            )
        }
    }
    
    /// Validate an archive without importing. Returns validation errors (empty = valid).
    func validateArchive(_ data: Data) -> [String] {
        // Guard: reject oversized archives
        if data.count > ReadingDataExporter.maxImportSizeBytes {
            let sizeMB = String(format: "%.1f", Double(data.count) / 1_048_576.0)
            let limitMB = ReadingDataExporter.maxImportSizeBytes / 1_048_576
            return ["Archive too large (\(sizeMB) MB). Maximum allowed: \(limitMB) MB."]
        }

        let decoder = JSONCoding.iso8601Decoder
        var errors: [String] = []
        
        do {
            let archive = try decoder.decode(ReadingDataArchive.self, from: data)
            
            if archive.version > ReadingDataArchive.currentVersion {
                errors.append("Archive version \(archive.version) is newer than supported (\(ReadingDataArchive.currentVersion)).")
            }

            // Validate section sizes
            let limit = ReadingDataExporter.maxItemsPerSection
            let sectionCounts: [(String, Int)] = [
                ("bookmarks", archive.sections.bookmarks?.count ?? 0),
                ("highlights", archive.sections.highlights?.count ?? 0),
                ("notes", archive.sections.notes?.count ?? 0),
                ("history", archive.sections.history?.count ?? 0),
                ("collections", archive.sections.collections?.count ?? 0),
                ("feeds", archive.sections.feeds?.count ?? 0),
            ]
            for (section, count) in sectionCounts {
                if count > limit {
                    errors.append("\(section): \(count) items exceeds maximum of \(limit)")
                }
            }
            
            // Validate bookmarks
            if let bookmarks = archive.sections.bookmarks {
                for (i, bm) in bookmarks.enumerated() {
                    if bm.articleLink.isEmpty {
                        errors.append("Bookmark[\(i)]: empty article link")
                    }
                }
            }
            
            // Validate highlights
            if let highlights = archive.sections.highlights {
                for (i, hl) in highlights.enumerated() {
                    if hl.id.isEmpty {
                        errors.append("Highlight[\(i)]: empty ID")
                    }
                    if hl.text.isEmpty {
                        errors.append("Highlight[\(i)]: empty text")
                    }
                }
            }
            
            // Validate notes
            if let notes = archive.sections.notes {
                for (i, note) in notes.enumerated() {
                    if note.articleLink.isEmpty {
                        errors.append("Note[\(i)]: empty article link")
                    }
                    if note.text.isEmpty {
                        errors.append("Note[\(i)]: empty text")
                    }
                }
            }
            
            // Validate collections
            if let collections = archive.sections.collections {
                let ids = collections.map { $0.id }
                let uniqueIds = Set(ids)
                if ids.count != uniqueIds.count {
                    errors.append("Collections: duplicate IDs found")
                }
                let linkLimit = ReadingDataExporter.maxArticleLinksPerCollection
                for (i, col) in collections.enumerated() {
                    if col.name.isEmpty {
                        errors.append("Collection[\(i)]: empty name")
                    }
                    if col.articleLinks.count > linkLimit {
                        errors.append("Collection[\(i)]: \(col.articleLinks.count) links exceeds maximum of \(linkLimit)")
                    }
                }
            }

            // Validate feed URLs — imported feeds bypass the normal
            // FeedManager.addFeed() flow which validates URLs, so we
            // must check here to prevent SSRF (e.g., file://, ftp://,
            // or internal IP feeds being imported from a malicious archive).
            if let feeds = archive.sections.feeds {
                for (i, feed) in feeds.enumerated() {
                    if feed.url.isEmpty {
                        errors.append("Feed[\(i)]: empty URL")
                    } else if !URLValidator.isSafe(feed.url) {
                        errors.append("Feed[\(i)]: unsafe or invalid URL '\(feed.url)'")
                    }
                }
            }
            
        } catch {
            errors.append("Parse error: \(error.localizedDescription)")
        }
        
        return errors
    }
    
    /// Get a summary of what's in an archive without importing.
    func previewArchive(_ data: Data) -> ArchivePreview? {
        let decoder = JSONCoding.iso8601Decoder
        guard let archive = try? decoder.decode(ReadingDataArchive.self, from: data) else {
            return nil
        }
        
        return ArchivePreview(
            version: archive.version,
            exportDate: archive.exportDate,
            appVersion: archive.appVersion,
            bookmarkCount: archive.sections.bookmarks?.count ?? 0,
            highlightCount: archive.sections.highlights?.count ?? 0,
            noteCount: archive.sections.notes?.count ?? 0,
            historyCount: archive.sections.history?.count ?? 0,
            collectionCount: archive.sections.collections?.count ?? 0,
            feedCount: archive.sections.feeds?.count ?? 0,
            hasStreakData: archive.sections.streaks != nil,
            totalItems: archive.metadata.totalItems,
            fileSizeBytes: data.count
        )
    }
    
    // MARK: - Private Export Methods
    
    private func exportBookmarks() -> [BookmarkExport] {
        return bookmarkManager.bookmarks.map { story in
            BookmarkExport(
                articleLink: story.link,
                articleTitle: story.title,
                feedName: story.sourceFeedName ?? "Unknown",
                bookmarkedDate: Date()
            )
        }
    }
    
    private func exportHighlights() -> [HighlightExport] {
        return highlightsManager.getAllHighlights().map { hl in
            HighlightExport(
                id: hl.id,
                articleLink: hl.articleLink,
                articleTitle: hl.articleTitle,
                text: hl.selectedText,
                color: hl.color.rawValue,
                note: hl.annotation,
                createdDate: hl.createdDate
            )
        }
    }
    
    private func exportNotes() -> [NoteExport] {
        return notesManager.getAllNotes().map { note in
            NoteExport(
                articleLink: note.articleLink,
                articleTitle: note.articleTitle,
                text: note.text,
                createdDate: note.createdDate,
                modifiedDate: note.modifiedDate
            )
        }
    }
    
    private func exportHistory() -> [HistoryExport] {
        return historyManager.allEntries().map { entry in
            HistoryExport(
                link: entry.link,
                title: entry.title,
                feedName: entry.feedName,
                visitDate: entry.readAt,
                timeSpentSeconds: entry.timeSpentSeconds,
                scrollProgress: entry.scrollProgress
            )
        }
    }
    
    private func exportCollections() -> [CollectionExport] {
        return collectionManager.collections.map { col in
            CollectionExport(
                id: col.id,
                name: col.name,
                icon: col.icon,
                description: col.description,
                articleLinks: col.articleLinks,
                createdDate: col.createdAt
            )
        }
    }
    
    private func exportStreaks() -> StreakExport {
        let stats = streakTracker.getStats()
        let records = streakTracker.records(
            from: Calendar.current.date(byAdding: .year, value: -2, to: Date()) ?? Date(),
            to: Date()
        )
        
        return StreakExport(
            currentStreak: stats.currentStreak,
            longestStreak: stats.longestStreak,
            totalArticlesRead: stats.totalArticlesRead,
                        dailyRecords: records.compactMap { rec in
                guard let date = Self.iso8601DayFormatter.date(from: rec.date) else { return nil }
                return DailyRecordExport(
                    date: date,
                    articlesRead: rec.articlesRead,
                    goalMet: rec.goalMet
                )
            }
        )
    }
    
    private func exportFeeds() -> [FeedExport] {
        return feedManager.feeds.map { feed in
            FeedExport(
                title: feed.name,
                url: feed.url,
                category: feed.category
            )
        }
    }
    
    // MARK: - Private Import Methods
    
    private func importBookmarks(_ bookmarks: [BookmarkExport], strategy: ImportConflictStrategy) -> (imported: Int, skipped: Int, errors: [String]) {
        var importedCount = 0
        var skippedCount = 0
        
        for bm in bookmarks {
            guard !bm.articleLink.isEmpty else {
                skippedCount += 1
                continue
            }
            
            guard let story = Story(
                title: bm.articleTitle,
                photo: nil,
                description: "",
                link: bm.articleLink
            ) else {
                skippedCount += 1
                continue
            }
            story.sourceFeedName = bm.feedName
            
            let exists = bookmarkManager.isBookmarked(story)
            
            switch strategy {
            case .skip:
                if exists {
                    skippedCount += 1
                } else {
                    bookmarkManager.addBookmark(story)
                    importedCount += 1
                }
            case .overwrite, .mergeKeepNewer:
                if !exists {
                    bookmarkManager.addBookmark(story)
                    importedCount += 1
                } else {
                    skippedCount += 1
                }
            }
        }
        
        return (importedCount, skippedCount, [])
    }
    
    private func importHighlights(_ highlights: [HighlightExport], strategy: ImportConflictStrategy) -> (imported: Int, skipped: Int, errors: [String]) {
        var importedCount = 0
        var skippedCount = 0
        
        for hl in highlights {
            guard !hl.id.isEmpty, !hl.text.isEmpty else {
                skippedCount += 1
                continue
            }
            
            let color = HighlightColor(rawValue: hl.color) ?? .yellow
            let existing = highlightsManager.highlights(for: hl.articleLink)
            let isDuplicate = existing.contains { $0.id == hl.id || $0.text == hl.text }
            
            switch strategy {
            case .skip:
                if isDuplicate {
                    skippedCount += 1
                } else {
                    highlightsManager.addHighlight(
                        articleLink: hl.articleLink,
                        articleTitle: hl.articleTitle,
                        text: hl.selectedText,
                        color: color,
                        note: hl.note
                    )
                    importedCount += 1
                }
            case .overwrite:
                if isDuplicate {
                    // Remove existing and re-add
                    if let existingHL = existing.first(where: { $0.id == hl.id || $0.text == hl.text }) {
                        highlightsManager.removeHighlight(id: existingHL.id)
                    }
                    highlightsManager.addHighlight(
                        articleLink: hl.articleLink,
                        articleTitle: hl.articleTitle,
                        text: hl.selectedText,
                        color: color,
                        note: hl.note
                    )
                    importedCount += 1
                } else {
                    highlightsManager.addHighlight(
                        articleLink: hl.articleLink,
                        articleTitle: hl.articleTitle,
                        text: hl.selectedText,
                        color: color,
                        note: hl.note
                    )
                    importedCount += 1
                }
            case .mergeKeepNewer:
                if isDuplicate {
                    if let existingHL = existing.first(where: { $0.id == hl.id || $0.text == hl.text }) {
                        if hl.createdDate > existingHL.createdDate {
                            highlightsManager.removeHighlight(id: existingHL.id)
                            highlightsManager.addHighlight(
                                articleLink: hl.articleLink,
                                articleTitle: hl.articleTitle,
                                text: hl.selectedText,
                                color: color,
                                note: hl.note
                            )
                            importedCount += 1
                        } else {
                            skippedCount += 1
                        }
                    }
                } else {
                    highlightsManager.addHighlight(
                        articleLink: hl.articleLink,
                        articleTitle: hl.articleTitle,
                        text: hl.selectedText,
                        color: color,
                        note: hl.note
                    )
                    importedCount += 1
                }
            }
        }
        
        return (importedCount, skippedCount, [])
    }
    
    private func importNotes(_ notes: [NoteExport], strategy: ImportConflictStrategy) -> (imported: Int, skipped: Int, errors: [String]) {
        var importedCount = 0
        var skippedCount = 0
        
        for note in notes {
            guard !note.articleLink.isEmpty, !note.text.isEmpty else {
                skippedCount += 1
                continue
            }
            
            let existing = notesManager.getNote(for: note.articleLink)
            
            switch strategy {
            case .skip:
                if existing != nil {
                    skippedCount += 1
                } else {
                    notesManager.saveNote(
                        articleLink: note.articleLink,
                        articleTitle: note.articleTitle,
                        text: note.text
                    )
                    importedCount += 1
                }
            case .overwrite:
                _ = notesManager.setNote(
                    for: note.articleLink,
                    title: note.articleTitle,
                    text: note.text
                )
                importedCount += 1
            case .mergeKeepNewer:
                if let existingNote = existing {
                    if note.modifiedDate > existingNote.modifiedDate {
                        notesManager.saveNote(
                            articleLink: note.articleLink,
                            articleTitle: note.articleTitle,
                            text: note.text
                        )
                        importedCount += 1
                    } else {
                        skippedCount += 1
                    }
                } else {
                    notesManager.saveNote(
                        articleLink: note.articleLink,
                        articleTitle: note.articleTitle,
                        text: note.text
                    )
                    importedCount += 1
                }
            }
        }
        
        return (importedCount, skippedCount, [])
    }
    
    private func importCollections(_ collections: [CollectionExport], strategy: ImportConflictStrategy) -> (imported: Int, skipped: Int, errors: [String]) {
        var importedCount = 0
        var skippedCount = 0
        
        for col in collections {
            guard !col.name.isEmpty else {
                skippedCount += 1
                continue
            }
            
            let existing = collectionManager.collection(named: col.name)
            
            switch strategy {
            case .skip:
                if existing != nil {
                    skippedCount += 1
                } else {
                    if let created = collectionManager.createCollection(
                        name: col.name, icon: col.icon, description: col.description) {
                        for link in col.articleLinks {
                            _ = collectionManager.addArticle(link: link, toCollection: created.id)
                        }
                        importedCount += 1
                    }
                }
            case .overwrite:
                if let existing = existing {
                    _ = collectionManager.deleteCollection(id: existing.id)
                }
                if let created = collectionManager.createCollection(
                    name: col.name, icon: col.icon, description: col.description) {
                    for link in col.articleLinks {
                        _ = collectionManager.addArticle(link: link, toCollection: created.id)
                    }
                    importedCount += 1
                }
            case .mergeKeepNewer:
                if let existing = existing {
                    // Merge: add any articles not already in the collection
                    for link in col.articleLinks {
                        _ = collectionManager.addArticle(link: link, toCollection: existing.id)
                    }
                    importedCount += 1
                } else {
                    if let created = collectionManager.createCollection(
                        name: col.name, icon: col.icon, description: col.description) {
                        for link in col.articleLinks {
                            _ = collectionManager.addArticle(link: link, toCollection: created.id)
                        }
                        importedCount += 1
                    }
                }
            }
        }
        
        return (importedCount, skippedCount, [])
    }
}

// MARK: - Archive Preview

struct ArchivePreview {
    let version: Int
    let exportDate: Date
    let appVersion: String
    let bookmarkCount: Int
    let highlightCount: Int
    let noteCount: Int
    let historyCount: Int
    let collectionCount: Int
    let feedCount: Int
    let hasStreakData: Bool
    let totalItems: Int
    let fileSizeBytes: Int
    
    var fileSizeFormatted: String {
        let kb = Double(fileSizeBytes) / 1024.0
        if kb < 1024 {
            return String(format: "%.1f KB", kb)
        }
        let mb = kb / 1024.0
        return String(format: "%.1f MB", mb)
    }
    
    var summary: String {
        var parts: [String] = []
        if bookmarkCount > 0 { parts.append("\(bookmarkCount) bookmarks") }
        if highlightCount > 0 { parts.append("\(highlightCount) highlights") }
        if noteCount > 0 { parts.append("\(noteCount) notes") }
        if historyCount > 0 { parts.append("\(historyCount) history entries") }
        if collectionCount > 0 { parts.append("\(collectionCount) collections") }
        if feedCount > 0 { parts.append("\(feedCount) feeds") }
        if hasStreakData { parts.append("streak data") }
        return parts.isEmpty ? "Empty archive" : parts.joined(separator: ", ")
    }
}
