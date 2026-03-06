//
//  ReadingDataExporterTests.swift
//  FeedReaderTests
//
//  Tests for ReadingDataExporter — archive format, validation,
//  preview, import/export round-trip, and conflict strategies.
//

import XCTest
@testable import FeedReader

class ReadingDataExporterTests: XCTestCase {
    
    // MARK: - Export Options
    
    func testExportOptionsAll_DefaultsToTrue() {
        let opts = ExportOptions.all
        XCTAssertTrue(opts.includeBookmarks)
        XCTAssertTrue(opts.includeHighlights)
        XCTAssertTrue(opts.includeNotes)
        XCTAssertTrue(opts.includeHistory)
        XCTAssertTrue(opts.includeCollections)
        XCTAssertTrue(opts.includeStreaks)
        XCTAssertTrue(opts.includeFeeds)
        XCTAssertTrue(opts.prettyPrint)
    }
    
    func testExportOptionsAnnotationsOnly_ExcludesHistoryStreaksFeeds() {
        let opts = ExportOptions.annotationsOnly
        XCTAssertTrue(opts.includeBookmarks)
        XCTAssertTrue(opts.includeHighlights)
        XCTAssertTrue(opts.includeNotes)
        XCTAssertTrue(opts.includeCollections)
        XCTAssertFalse(opts.includeHistory)
        XCTAssertFalse(opts.includeStreaks)
        XCTAssertFalse(opts.includeFeeds)
    }
    
    // MARK: - Archive Data Models (Codable Round-Trip)
    
    func testBookmarkExport_CodableRoundTrip() {
        let bookmark = BookmarkExport(
            articleLink: "https://example.com/article",
            articleTitle: "Test Article",
            feedName: "Test Feed",
            bookmarkedDate: Date(timeIntervalSince1970: 1700000000)
        )
        
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        
        let data = try! encoder.encode(bookmark)
        let decoded = try! decoder.decode(BookmarkExport.self, from: data)
        
        XCTAssertEqual(decoded.articleLink, "https://example.com/article")
        XCTAssertEqual(decoded.articleTitle, "Test Article")
        XCTAssertEqual(decoded.feedName, "Test Feed")
        XCTAssertEqual(decoded.bookmarkedDate.timeIntervalSince1970,
                       bookmark.bookmarkedDate.timeIntervalSince1970, accuracy: 1.0)
    }
    
    func testHighlightExport_CodableRoundTrip() {
        let highlight = HighlightExport(
            id: "hl-001",
            articleLink: "https://example.com/article",
            articleTitle: "Test Article",
            text: "Important highlighted text",
            color: 2,
            note: "My annotation",
            createdDate: Date(timeIntervalSince1970: 1700000000)
        )
        
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        
        let data = try! encoder.encode(highlight)
        let decoded = try! decoder.decode(HighlightExport.self, from: data)
        
        XCTAssertEqual(decoded.id, "hl-001")
        XCTAssertEqual(decoded.text, "Important highlighted text")
        XCTAssertEqual(decoded.color, 2)
        XCTAssertEqual(decoded.note, "My annotation")
    }
    
    func testNoteExport_CodableRoundTrip() {
        let created = Date(timeIntervalSince1970: 1700000000)
        let modified = Date(timeIntervalSince1970: 1700001000)
        
        let note = NoteExport(
            articleLink: "https://example.com/article",
            articleTitle: "Test Article",
            text: "My thoughts on this article",
            createdDate: created,
            modifiedDate: modified
        )
        
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        
        let data = try! encoder.encode(note)
        let decoded = try! decoder.decode(NoteExport.self, from: data)
        
        XCTAssertEqual(decoded.text, "My thoughts on this article")
        XCTAssertTrue(decoded.modifiedDate > decoded.createdDate)
    }
    
    func testHistoryExport_CodableRoundTrip() {
        let entry = HistoryExport(
            link: "https://example.com/article",
            title: "Test Article",
            feedName: "Tech Feed",
            visitDate: Date(timeIntervalSince1970: 1700000000),
            timeSpentSeconds: 245.5,
            scrollProgress: 0.87
        )
        
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        
        let data = try! encoder.encode(entry)
        let decoded = try! decoder.decode(HistoryExport.self, from: data)
        
        XCTAssertEqual(decoded.timeSpentSeconds, 245.5)
        XCTAssertEqual(decoded.scrollProgress, 0.87, accuracy: 0.001)
    }
    
    func testCollectionExport_CodableRoundTrip() {
        let collection = CollectionExport(
            id: "col-001",
            name: "AI Articles",
            icon: "🤖",
            description: "Interesting AI reads",
            articleLinks: ["https://a.com", "https://b.com", "https://c.com"],
            createdDate: Date(timeIntervalSince1970: 1700000000)
        )
        
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        
        let data = try! encoder.encode(collection)
        let decoded = try! decoder.decode(CollectionExport.self, from: data)
        
        XCTAssertEqual(decoded.name, "AI Articles")
        XCTAssertEqual(decoded.icon, "🤖")
        XCTAssertEqual(decoded.articleLinks.count, 3)
    }
    
    func testStreakExport_CodableRoundTrip() {
        let streak = StreakExport(
            currentStreak: 7,
            longestStreak: 14,
            totalArticlesRead: 150,
            dailyRecords: [
                DailyRecordExport(date: Date(timeIntervalSince1970: 1700000000), articlesRead: 5, goalMet: true),
                DailyRecordExport(date: Date(timeIntervalSince1970: 1700086400), articlesRead: 3, goalMet: true),
            ]
        )
        
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        
        let data = try! encoder.encode(streak)
        let decoded = try! decoder.decode(StreakExport.self, from: data)
        
        XCTAssertEqual(decoded.currentStreak, 7)
        XCTAssertEqual(decoded.longestStreak, 14)
        XCTAssertEqual(decoded.dailyRecords.count, 2)
    }
    
    func testFeedExport_CodableRoundTrip() {
        let feed = FeedExport(
            title: "Hacker News",
            url: "https://news.ycombinator.com/rss",
            category: "Tech"
        )
        
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        
        let data = try! encoder.encode(feed)
        let decoded = try! decoder.decode(FeedExport.self, from: data)
        
        XCTAssertEqual(decoded.title, "Hacker News")
        XCTAssertEqual(decoded.url, "https://news.ycombinator.com/rss")
        XCTAssertEqual(decoded.category, "Tech")
    }
    
    func testFeedExport_NilCategory() {
        let feed = FeedExport(title: "Misc", url: "https://misc.rss", category: nil)
        
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        
        let data = try! encoder.encode(feed)
        let decoded = try! decoder.decode(FeedExport.self, from: data)
        XCTAssertNil(decoded.category)
    }
    
    // MARK: - Full Archive Codable
    
    func testFullArchive_CodableRoundTrip() {
        let archive = ReadingDataArchive(
            version: ReadingDataArchive.currentVersion,
            exportDate: Date(),
            appVersion: "1.0",
            sections: ArchiveSections(
                bookmarks: [
                    BookmarkExport(articleLink: "https://a.com", articleTitle: "A", feedName: "F", bookmarkedDate: Date())
                ],
                highlights: [
                    HighlightExport(id: "h1", articleLink: "https://a.com", articleTitle: "A", text: "text", color: 0, note: nil, createdDate: Date())
                ],
                notes: [
                    NoteExport(articleLink: "https://a.com", articleTitle: "A", text: "note", createdDate: Date(), modifiedDate: Date())
                ],
                history: nil,
                collections: nil,
                streaks: nil,
                feeds: nil
            ),
            metadata: ArchiveMetadata(totalItems: 3, includedSections: ["bookmarks", "highlights", "notes"], exportDurationMs: 5)
        )
        
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        
        let data = try! encoder.encode(archive)
        let decoded = try! decoder.decode(ReadingDataArchive.self, from: data)
        
        XCTAssertEqual(decoded.version, ReadingDataArchive.currentVersion)
        XCTAssertEqual(decoded.appVersion, "1.0")
        XCTAssertEqual(decoded.sections.bookmarks?.count, 1)
        XCTAssertEqual(decoded.sections.highlights?.count, 1)
        XCTAssertEqual(decoded.sections.notes?.count, 1)
        XCTAssertNil(decoded.sections.history)
        XCTAssertNil(decoded.sections.collections)
        XCTAssertNil(decoded.sections.streaks)
        XCTAssertNil(decoded.sections.feeds)
        XCTAssertEqual(decoded.metadata.totalItems, 3)
    }
    
    func testArchiveVersion_IsOne() {
        XCTAssertEqual(ReadingDataArchive.currentVersion, 1)
    }
    
    // MARK: - Archive Preview
    
    func testArchivePreview_FormatsSmallFileSize() {
        let preview = ArchivePreview(
            version: 1, exportDate: Date(), appVersion: "1.0",
            bookmarkCount: 5, highlightCount: 3, noteCount: 2,
            historyCount: 100, collectionCount: 1, feedCount: 10,
            hasStreakData: true, totalItems: 121, fileSizeBytes: 2560
        )
        
        XCTAssertEqual(preview.fileSizeFormatted, "2.5 KB")
    }
    
    func testArchivePreview_FormatsLargeFileSize() {
        let preview = ArchivePreview(
            version: 1, exportDate: Date(), appVersion: "1.0",
            bookmarkCount: 0, highlightCount: 0, noteCount: 0,
            historyCount: 0, collectionCount: 0, feedCount: 0,
            hasStreakData: false, totalItems: 0, fileSizeBytes: 1_572_864
        )
        
        XCTAssertEqual(preview.fileSizeFormatted, "1.5 MB")
    }
    
    func testArchivePreview_SummaryIncludesAllTypes() {
        let preview = ArchivePreview(
            version: 1, exportDate: Date(), appVersion: "1.0",
            bookmarkCount: 5, highlightCount: 3, noteCount: 2,
            historyCount: 100, collectionCount: 1, feedCount: 10,
            hasStreakData: true, totalItems: 121, fileSizeBytes: 1024
        )
        
        let summary = preview.summary
        XCTAssertTrue(summary.contains("5 bookmarks"))
        XCTAssertTrue(summary.contains("3 highlights"))
        XCTAssertTrue(summary.contains("2 notes"))
        XCTAssertTrue(summary.contains("100 history entries"))
        XCTAssertTrue(summary.contains("1 collections"))
        XCTAssertTrue(summary.contains("10 feeds"))
        XCTAssertTrue(summary.contains("streak data"))
    }
    
    func testArchivePreview_EmptyArchive() {
        let preview = ArchivePreview(
            version: 1, exportDate: Date(), appVersion: "1.0",
            bookmarkCount: 0, highlightCount: 0, noteCount: 0,
            historyCount: 0, collectionCount: 0, feedCount: 0,
            hasStreakData: false, totalItems: 0, fileSizeBytes: 128
        )
        
        XCTAssertEqual(preview.summary, "Empty archive")
    }
    
    // MARK: - Import Counts
    
    func testImportCounts_ZeroByDefault() {
        let counts = ImportCounts()
        XCTAssertEqual(counts.bookmarks, 0)
        XCTAssertEqual(counts.highlights, 0)
        XCTAssertEqual(counts.notes, 0)
        XCTAssertEqual(counts.history, 0)
        XCTAssertEqual(counts.collections, 0)
        XCTAssertEqual(counts.feeds, 0)
        XCTAssertEqual(counts.streakRecords, 0)
    }
    
    func testImportResult_TotalImported() {
        var imported = ImportCounts()
        imported.bookmarks = 3
        imported.highlights = 2
        imported.notes = 1
        imported.collections = 1
        imported.feeds = 5
        
        let result = ImportResult(
            success: true,
            message: "OK",
            imported: imported,
            skipped: ImportCounts(),
            errors: []
        )
        
        XCTAssertEqual(result.totalImported, 12)
    }
    
    // MARK: - Validation Tests
    
    func testValidation_InvalidJSON_ReturnsError() {
        let exporter = makeExporter()
        let badData = Data("not json at all".utf8)
        let errors = exporter.validateArchive(badData)
        XCTAssertFalse(errors.isEmpty)
        XCTAssertTrue(errors[0].contains("Parse error"))
    }
    
    func testValidation_FutureVersion_ReturnsError() {
        let exporter = makeExporter()
        let archive = ReadingDataArchive(
            version: 999,
            exportDate: Date(),
            appVersion: "1.0",
            sections: ArchiveSections(),
            metadata: ArchiveMetadata(totalItems: 0, includedSections: [], exportDurationMs: 0)
        )
        
        let data = encodeArchive(archive)
        let errors = exporter.validateArchive(data)
        XCTAssertTrue(errors.contains { $0.contains("newer") })
    }
    
    func testValidation_EmptyBookmarkLink_ReturnsError() {
        let exporter = makeExporter()
        let archive = ReadingDataArchive(
            version: 1,
            exportDate: Date(),
            appVersion: "1.0",
            sections: ArchiveSections(
                bookmarks: [BookmarkExport(articleLink: "", articleTitle: "T", feedName: "F", bookmarkedDate: Date())]
            ),
            metadata: ArchiveMetadata(totalItems: 1, includedSections: ["bookmarks"], exportDurationMs: 0)
        )
        
        let data = encodeArchive(archive)
        let errors = exporter.validateArchive(data)
        XCTAssertTrue(errors.contains { $0.contains("Bookmark") && $0.contains("empty") })
    }
    
    func testValidation_EmptyHighlightText_ReturnsError() {
        let exporter = makeExporter()
        let archive = ReadingDataArchive(
            version: 1,
            exportDate: Date(),
            appVersion: "1.0",
            sections: ArchiveSections(
                highlights: [HighlightExport(id: "h1", articleLink: "https://a.com", articleTitle: "A", text: "", color: 0, note: nil, createdDate: Date())]
            ),
            metadata: ArchiveMetadata(totalItems: 1, includedSections: ["highlights"], exportDurationMs: 0)
        )
        
        let data = encodeArchive(archive)
        let errors = exporter.validateArchive(data)
        XCTAssertTrue(errors.contains { $0.contains("Highlight") && $0.contains("empty text") })
    }
    
    func testValidation_DuplicateCollectionIds_ReturnsError() {
        let exporter = makeExporter()
        let archive = ReadingDataArchive(
            version: 1,
            exportDate: Date(),
            appVersion: "1.0",
            sections: ArchiveSections(
                collections: [
                    CollectionExport(id: "c1", name: "A", icon: "📚", description: "", articleLinks: [], createdDate: Date()),
                    CollectionExport(id: "c1", name: "B", icon: "📖", description: "", articleLinks: [], createdDate: Date()),
                ]
            ),
            metadata: ArchiveMetadata(totalItems: 2, includedSections: ["collections"], exportDurationMs: 0)
        )
        
        let data = encodeArchive(archive)
        let errors = exporter.validateArchive(data)
        XCTAssertTrue(errors.contains { $0.contains("duplicate") })
    }
    
    func testValidation_ValidArchive_NoErrors() {
        let exporter = makeExporter()
        let archive = ReadingDataArchive(
            version: 1,
            exportDate: Date(),
            appVersion: "1.0",
            sections: ArchiveSections(
                bookmarks: [BookmarkExport(articleLink: "https://a.com", articleTitle: "A", feedName: "F", bookmarkedDate: Date())],
                highlights: [HighlightExport(id: "h1", articleLink: "https://a.com", articleTitle: "A", text: "text", color: 0, note: nil, createdDate: Date())],
                notes: [NoteExport(articleLink: "https://a.com", articleTitle: "A", text: "note", createdDate: Date(), modifiedDate: Date())],
                collections: [CollectionExport(id: "c1", name: "Collection", icon: "📚", description: "", articleLinks: ["https://a.com"], createdDate: Date())]
            ),
            metadata: ArchiveMetadata(totalItems: 4, includedSections: ["bookmarks", "highlights", "notes", "collections"], exportDurationMs: 0)
        )
        
        let data = encodeArchive(archive)
        let errors = exporter.validateArchive(data)
        XCTAssertTrue(errors.isEmpty, "Valid archive should have no errors: \(errors)")
    }
    
    // MARK: - Preview Tests
    
    func testPreview_ValidArchive_ReturnsCorrectCounts() {
        let exporter = makeExporter()
        let archive = ReadingDataArchive(
            version: 1,
            exportDate: Date(timeIntervalSince1970: 1700000000),
            appVersion: "2.5",
            sections: ArchiveSections(
                bookmarks: [
                    BookmarkExport(articleLink: "https://a.com", articleTitle: "A", feedName: "F", bookmarkedDate: Date()),
                    BookmarkExport(articleLink: "https://b.com", articleTitle: "B", feedName: "F", bookmarkedDate: Date()),
                ],
                highlights: [
                    HighlightExport(id: "h1", articleLink: "https://a.com", articleTitle: "A", text: "text", color: 0, note: nil, createdDate: Date()),
                ],
                notes: nil,
                history: nil,
                collections: nil,
                streaks: StreakExport(currentStreak: 5, longestStreak: 10, totalArticlesRead: 50, dailyRecords: []),
                feeds: [
                    FeedExport(title: "Feed1", url: "https://f1.rss", category: "Tech"),
                    FeedExport(title: "Feed2", url: "https://f2.rss", category: nil),
                    FeedExport(title: "Feed3", url: "https://f3.rss", category: "News"),
                ]
            ),
            metadata: ArchiveMetadata(totalItems: 6, includedSections: ["bookmarks", "highlights", "streaks", "feeds"], exportDurationMs: 3)
        )
        
        let data = encodeArchive(archive)
        let preview = exporter.previewArchive(data)
        
        XCTAssertNotNil(preview)
        XCTAssertEqual(preview?.bookmarkCount, 2)
        XCTAssertEqual(preview?.highlightCount, 1)
        XCTAssertEqual(preview?.noteCount, 0)
        XCTAssertEqual(preview?.feedCount, 3)
        XCTAssertTrue(preview?.hasStreakData ?? false)
        XCTAssertEqual(preview?.appVersion, "2.5")
    }
    
    func testPreview_InvalidData_ReturnsNil() {
        let exporter = makeExporter()
        let preview = exporter.previewArchive(Data("bad".utf8))
        XCTAssertNil(preview)
    }
    
    // MARK: - Import Invalid Data
    
    func testImport_InvalidJSON_Fails() {
        let exporter = makeExporter()
        let result = exporter.importData(Data("not json".utf8))
        XCTAssertFalse(result.success)
        XCTAssertFalse(result.errors.isEmpty)
    }
    
    func testImport_FutureVersion_Fails() {
        let exporter = makeExporter()
        let archive = ReadingDataArchive(
            version: 999,
            exportDate: Date(),
            appVersion: "1.0",
            sections: ArchiveSections(),
            metadata: ArchiveMetadata(totalItems: 0, includedSections: [], exportDurationMs: 0)
        )
        
        let data = encodeArchive(archive)
        let result = exporter.importData(data)
        XCTAssertFalse(result.success)
        XCTAssertTrue(result.message.contains("newer"))
    }
    
    func testImport_EmptyArchive_Succeeds() {
        let exporter = makeExporter()
        let archive = ReadingDataArchive(
            version: 1,
            exportDate: Date(),
            appVersion: "1.0",
            sections: ArchiveSections(),
            metadata: ArchiveMetadata(totalItems: 0, includedSections: [], exportDurationMs: 0)
        )
        
        let data = encodeArchive(archive)
        let result = exporter.importData(data)
        XCTAssertTrue(result.success)
        XCTAssertEqual(result.totalImported, 0)
    }
    
    // MARK: - Helpers
    
    private func makeExporter() -> ReadingDataExporter {
        return ReadingDataExporter(
            bookmarkManager: BookmarkManager.shared,
            highlightsManager: ArticleHighlightsManager.shared,
            notesManager: ArticleNotesManager.shared,
            historyManager: ReadingHistoryManager.shared,
            collectionManager: ArticleCollectionManager.shared,
            streakTracker: ReadingStreakTracker.shared,
            feedManager: FeedManager.shared
        )
    }
    
    private func encodeArchive(_ archive: ReadingDataArchive) -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return try! encoder.encode(archive)
    }
}
