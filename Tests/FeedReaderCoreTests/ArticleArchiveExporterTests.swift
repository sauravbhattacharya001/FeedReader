//
//  ArticleArchiveExporterTests.swift
//  FeedReaderCoreTests
//
//  Tests for ArticleArchiveExporter.
//

import XCTest
@testable import FeedReaderCore

final class ArticleArchiveExporterTests: XCTestCase {
    
    private func makeStory(title: String = "Test Article", body: String = "This is a test article body with enough words to be meaningful.", link: String = "https://example.com/article") -> RSSStory {
        return RSSStory(title: title, body: body, link: link)!
    }
    
    private var tempDir: URL!
    
    override func setUp() {
        super.setUp()
        tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }
    
    override func tearDown() {
        try? FileManager.default.removeItem(at: tempDir)
        super.tearDown()
    }
    
    // MARK: - Single Export
    
    func testExportSingleArticle() {
        let exporter = ArticleArchiveExporter()
        let story = makeStory()
        let result = exporter.exportArticle(story)
        
        XCTAssertEqual(result.articleCount, 1)
        XCTAssertTrue(result.filename.hasSuffix(".html"))
        XCTAssertTrue(result.htmlContent.contains("Test Article"))
        XCTAssertTrue(result.htmlContent.contains("<!DOCTYPE html>"))
    }
    
    func testExportContainsLink() {
        let exporter = ArticleArchiveExporter()
        let result = exporter.exportArticle(makeStory())
        
        XCTAssertTrue(result.htmlContent.contains("https://example.com/article"))
        XCTAssertTrue(result.htmlContent.contains("Original Article"))
    }
    
    func testExportWordCount() {
        let exporter = ArticleArchiveExporter()
        let result = exporter.exportArticle(makeStory())
        
        XCTAssertGreaterThan(result.totalWordCount, 0)
        XCTAssertTrue(result.htmlContent.contains("words"))
    }
    
    func testExportReadTime() {
        let exporter = ArticleArchiveExporter()
        let result = exporter.exportArticle(makeStory())
        
        XCTAssertTrue(result.htmlContent.contains("min read"))
    }
    
    // MARK: - Themes
    
    func testLightTheme() {
        let exporter = ArticleArchiveExporter(options: .init(theme: .light))
        let result = exporter.exportArticle(makeStory())
        XCTAssertTrue(result.htmlContent.contains("#ffffff"))
    }
    
    func testDarkTheme() {
        let exporter = ArticleArchiveExporter(options: .init(theme: .dark))
        let result = exporter.exportArticle(makeStory())
        XCTAssertTrue(result.htmlContent.contains("#1a1a2e"))
    }
    
    func testSepiaTheme() {
        let exporter = ArticleArchiveExporter(options: .init(theme: .sepia))
        let result = exporter.exportArticle(makeStory())
        XCTAssertTrue(result.htmlContent.contains("#f4ecd8"))
    }
    
    func testNewspaperTheme() {
        let exporter = ArticleArchiveExporter(options: .init(theme: .newspaper))
        let result = exporter.exportArticle(makeStory())
        XCTAssertTrue(result.htmlContent.contains("#fafaf0"))
    }
    
    func testAllThemesExist() {
        XCTAssertEqual(ArticleArchiveExporter.Theme.allCases.count, 4)
    }
    
    // MARK: - Options
    
    func testNoMetadata() {
        let exporter = ArticleArchiveExporter(options: .init(includeMetadata: false))
        let result = exporter.exportArticle(makeStory())
        XCTAssertFalse(result.htmlContent.contains("words"))
        XCTAssertFalse(result.htmlContent.contains("min read"))
    }
    
    func testCustomCSS() {
        let exporter = ArticleArchiveExporter(options: .init(customCSS: ".custom-class{color:red}"))
        let result = exporter.exportArticle(makeStory())
        XCTAssertTrue(result.htmlContent.contains(".custom-class{color:red}"))
    }
    
    // MARK: - Batch Export
    
    func testBatchExport() {
        let exporter = ArticleArchiveExporter()
        let stories = [
            makeStory(title: "Article One"),
            makeStory(title: "Article Two"),
            makeStory(title: "Article Three"),
        ]
        let result = exporter.exportArticles(stories)
        
        XCTAssertNotNil(result)
        XCTAssertEqual(result!.articleCount, 3)
        XCTAssertTrue(result!.htmlContent.contains("Article One"))
        XCTAssertTrue(result!.htmlContent.contains("Article Two"))
        XCTAssertTrue(result!.htmlContent.contains("Article Three"))
        XCTAssertTrue(result!.htmlContent.contains("3 articles"))
    }
    
    func testBatchExportEmpty() {
        let exporter = ArticleArchiveExporter()
        let result = exporter.exportArticles([])
        XCTAssertNil(result)
    }
    
    func testBatchWithTableOfContents() {
        let exporter = ArticleArchiveExporter(options: .init(includeTableOfContents: true))
        let stories = [makeStory(title: "First"), makeStory(title: "Second")]
        let result = exporter.exportArticles(stories)!
        
        XCTAssertTrue(result.htmlContent.contains("Table of Contents"))
        XCTAssertTrue(result.htmlContent.contains("#article-0"))
        XCTAssertTrue(result.htmlContent.contains("#article-1"))
    }
    
    func testBatchFilename() {
        let exporter = ArticleArchiveExporter()
        let result = exporter.exportArticles([makeStory()])!
        XCTAssertTrue(result.filename.contains("1_articles"))
    }
    
    // MARK: - Save / List / Delete
    
    func testSaveAndList() {
        let exporter = ArticleArchiveExporter()
        let result = exporter.exportArticle(makeStory())
        
        let url = exporter.save(result, to: tempDir)
        XCTAssertNotNil(url)
        
        let archives = exporter.listArchives(in: tempDir)
        XCTAssertEqual(archives.count, 1)
        XCTAssertEqual(archives.first?.filename, result.filename)
    }
    
    func testDelete() {
        let exporter = ArticleArchiveExporter()
        let result = exporter.exportArticle(makeStory())
        exporter.save(result, to: tempDir)
        
        let deleted = exporter.deleteArchive(named: result.filename, in: tempDir)
        XCTAssertTrue(deleted)
        
        let archives = exporter.listArchives(in: tempDir)
        XCTAssertEqual(archives.count, 0)
    }
    
    func testDeleteNonexistent() {
        let exporter = ArticleArchiveExporter()
        let deleted = exporter.deleteArchive(named: "nope.html", in: tempDir)
        XCTAssertFalse(deleted)
    }
    
    func testListEmptyDir() {
        let exporter = ArticleArchiveExporter()
        let archives = exporter.listArchives(in: tempDir)
        XCTAssertEqual(archives.count, 0)
    }
    
    // MARK: - Utilities
    
    func testWordCount() {
        let exporter = ArticleArchiveExporter()
        XCTAssertEqual(exporter.countWords("hello world foo"), 3)
        XCTAssertEqual(exporter.countWords(""), 0)
        XCTAssertEqual(exporter.countWords("single"), 1)
    }
    
    func testReadTime() {
        let exporter = ArticleArchiveExporter()
        XCTAssertEqual(exporter.estimateReadTime(wordCount: 200), 1)
        XCTAssertEqual(exporter.estimateReadTime(wordCount: 400), 2)
        XCTAssertEqual(exporter.estimateReadTime(wordCount: 50), 1) // minimum 1
    }
    
    // MARK: - HTML Safety
    
    func testHTMLEscaping() {
        let exporter = ArticleArchiveExporter()
        let story = makeStory(title: "Title <script>alert('xss')</script>")
        let result = exporter.exportArticle(story)
        
        XCTAssertFalse(result.htmlContent.contains("<script>"))
        XCTAssertTrue(result.htmlContent.contains("&lt;script&gt;"))
    }
    
    func testFilenamesSanitized() {
        let exporter = ArticleArchiveExporter()
        let story = makeStory(title: "Bad/File:Name?Here")
        let result = exporter.exportArticle(story)
        
        XCTAssertFalse(result.filename.contains("/"))
        XCTAssertFalse(result.filename.contains(":"))
        XCTAssertFalse(result.filename.contains("?"))
    }
    
    // MARK: - Print Styles
    
    func testPrintMediaQuery() {
        let exporter = ArticleArchiveExporter()
        let result = exporter.exportArticle(makeStory())
        XCTAssertTrue(result.htmlContent.contains("@media print"))
    }
}
