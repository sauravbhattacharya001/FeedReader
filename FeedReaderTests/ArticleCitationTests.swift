//
//  ArticleCitationTests.swift
//  FeedReaderTests
//
//  Tests for ArticleCitationGenerator.
//

import XCTest
@testable import FeedReader

class ArticleCitationTests: XCTestCase {

    var generator: ArticleCitationGenerator!
    var fixedDate: Date!
    var fixedAccessDate: Date!

    override func setUp() {
        super.setUp()
        generator = ArticleCitationGenerator()
        // 2026-03-15
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        fixedDate = cal.date(from: DateComponents(year: 2026, month: 3, day: 15))!
        fixedAccessDate = cal.date(from: DateComponents(year: 2026, month: 4, day: 1))!
    }

    // MARK: - Author Parsing

    func testParseAuthor_FirstLast() {
        let author = ArticleCitationGenerator.parseAuthorName("John Smith")
        XCTAssertEqual(author.firstName, "John")
        XCTAssertEqual(author.lastName, "Smith")
        XCTAssertTrue(author.middleInitials.isEmpty)
    }

    func testParseAuthor_FirstMiddleLast() {
        let author = ArticleCitationGenerator.parseAuthorName("John A. Smith")
        XCTAssertEqual(author.firstName, "John")
        XCTAssertEqual(author.lastName, "Smith")
        XCTAssertEqual(author.middleInitials, ["A."])
    }

    func testParseAuthor_LastCommaFirst() {
        let author = ArticleCitationGenerator.parseAuthorName("Smith, John")
        XCTAssertEqual(author.firstName, "John")
        XCTAssertEqual(author.lastName, "Smith")
        XCTAssertTrue(author.middleInitials.isEmpty)
    }

    func testParseAuthor_LastCommaFirstMiddle() {
        let author = ArticleCitationGenerator.parseAuthorName("Smith, John Andrew")
        XCTAssertEqual(author.firstName, "John")
        XCTAssertEqual(author.lastName, "Smith")
        XCTAssertEqual(author.middleInitials, ["Andrew"])
    }

    func testParseAuthor_SingleName() {
        let author = ArticleCitationGenerator.parseAuthorName("Aristotle")
        XCTAssertEqual(author.firstName, "Aristotle")
        XCTAssertEqual(author.lastName, "")
    }

    func testParseAuthor_EmptyString() {
        let author = ArticleCitationGenerator.parseAuthorName("")
        XCTAssertEqual(author.firstName, "")
        XCTAssertEqual(author.lastName, "")
    }

    func testParseAuthor_MultipleMiddleNames() {
        let author = ArticleCitationGenerator.parseAuthorName("John Paul George Harrison")
        XCTAssertEqual(author.firstName, "John")
        XCTAssertEqual(author.lastName, "Harrison")
        XCTAssertEqual(author.middleInitials, ["Paul", "George"])
    }

    // MARK: - Author Format Methods

    func testAuthorName_FullName() {
        let author = AuthorName(firstName: "John", lastName: "Smith", middleInitials: ["A"])
        XCTAssertEqual(author.fullName, "John A. Smith")
    }

    func testAuthorName_APAFormat() {
        let author = AuthorName(firstName: "John", lastName: "Smith", middleInitials: ["A"])
        XCTAssertEqual(author.apaFormat, "Smith, J. A.")
    }

    func testAuthorName_MLAFormatFirst() {
        let author = AuthorName(firstName: "John", lastName: "Smith", middleInitials: [])
        XCTAssertEqual(author.mlaFormat(isFirst: true), "Smith, John")
    }

    func testAuthorName_MLAFormatSubsequent() {
        let author = AuthorName(firstName: "Jane", lastName: "Doe", middleInitials: [])
        XCTAssertEqual(author.mlaFormat(isFirst: false), "Jane Doe")
    }

    func testAuthorName_IEEEFormat() {
        let author = AuthorName(firstName: "John", lastName: "Smith", middleInitials: ["A"])
        XCTAssertEqual(author.ieeeFormat, "J. A. Smith")
    }

    func testAuthorName_HarvardFormat() {
        let author = AuthorName(firstName: "John", lastName: "Smith", middleInitials: ["A"])
        XCTAssertEqual(author.harvardFormat, "Smith, J.A.")
    }

    func testAuthorName_BibTeXFormat() {
        let author = AuthorName(firstName: "John", lastName: "Smith", middleInitials: ["A"])
        XCTAssertEqual(author.bibtexFormat, "Smith, John A.")
    }

    // MARK: - APA Format

    func testAPA_SingleAuthor() {
        let meta = CitationMetadata(
            title: "AI Safety in 2026",
            authors: ["John Smith"],
            publicationDate: fixedDate,
            siteName: "Tech Review",
            url: "https://example.com/article",
            accessDate: fixedAccessDate
        )
        let result = generator.generate(metadata: meta, format: .apa)
        XCTAssertTrue(result.citation.contains("Smith, J."))
        XCTAssertTrue(result.citation.contains("2026"))
        XCTAssertTrue(result.citation.contains("AI Safety in 2026"))
        XCTAssertTrue(result.citation.contains("*Tech Review*"))
        XCTAssertTrue(result.citation.contains("https://example.com/article"))
    }

    func testAPA_TwoAuthors() {
        let meta = CitationMetadata(
            title: "Test",
            authors: ["John Smith", "Jane Doe"],
            publicationDate: fixedDate,
            siteName: "Site",
            url: "https://example.com",
            accessDate: fixedAccessDate
        )
        let result = generator.generate(metadata: meta, format: .apa)
        XCTAssertTrue(result.citation.contains("& Doe"))
    }

    func testAPA_NoDate() {
        let meta = CitationMetadata(
            title: "Test Article",
            authors: ["John Smith"],
            accessDate: fixedAccessDate
        )
        let result = generator.generate(metadata: meta, format: .apa)
        XCTAssertTrue(result.citation.contains("(n.d.)"))
    }

    func testAPA_WithDOI() {
        let meta = CitationMetadata(
            title: "Test",
            authors: ["John Smith"],
            publicationDate: fixedDate,
            url: "https://example.com",
            accessDate: fixedAccessDate,
            doi: "10.1234/test.5678"
        )
        let result = generator.generate(metadata: meta, format: .apa)
        XCTAssertTrue(result.citation.contains("https://doi.org/10.1234/test.5678"))
        // DOI takes priority over URL
        XCTAssertFalse(result.citation.contains("example.com"))
    }

    // MARK: - MLA Format

    func testMLA_SingleAuthor() {
        let meta = CitationMetadata(
            title: "AI Ethics Today",
            authors: ["John Smith"],
            publicationDate: fixedDate,
            siteName: "Tech Blog",
            url: "https://example.com/ethics",
            accessDate: fixedAccessDate
        )
        let result = generator.generate(metadata: meta, format: .mla)
        XCTAssertTrue(result.citation.contains("Smith, John"))
        XCTAssertTrue(result.citation.contains("\"AI Ethics Today.\""))
        XCTAssertTrue(result.citation.contains("*Tech Blog*"))
        XCTAssertTrue(result.citation.contains("Accessed"))
    }

    func testMLA_ThreeAuthors() {
        let meta = CitationMetadata(
            title: "Test",
            authors: ["John Smith", "Jane Doe", "Bob Jones"],
            publicationDate: fixedDate,
            siteName: "Site",
            accessDate: fixedAccessDate
        )
        let result = generator.generate(metadata: meta, format: .mla)
        XCTAssertTrue(result.citation.contains("et al."))
    }

    func testMLA_URLWithoutProtocol() {
        let meta = CitationMetadata(
            title: "Test",
            authors: ["John Smith"],
            url: "https://www.example.com/path",
            accessDate: fixedAccessDate
        )
        let result = generator.generate(metadata: meta, format: .mla)
        // MLA strips protocol
        XCTAssertTrue(result.citation.contains("www.example.com/path"))
        XCTAssertFalse(result.citation.contains("https://"))
    }

    // MARK: - Chicago Format

    func testChicago_SingleAuthor() {
        let meta = CitationMetadata(
            title: "Deep Learning Review",
            authors: ["John Smith"],
            publicationDate: fixedDate,
            siteName: "AI Journal",
            url: "https://example.com",
            accessDate: fixedAccessDate
        )
        let result = generator.generate(metadata: meta, format: .chicago)
        XCTAssertTrue(result.citation.contains("Smith, John."))
        XCTAssertTrue(result.citation.contains("2026."))
        XCTAssertTrue(result.citation.contains("\"Deep Learning Review.\""))
    }

    func testChicago_FourAuthorsEtAl() {
        let meta = CitationMetadata(
            title: "Test",
            authors: ["A Smith", "B Jones", "C Lee", "D Kim"],
            publicationDate: fixedDate,
            accessDate: fixedAccessDate
        )
        let result = generator.generate(metadata: meta, format: .chicago)
        XCTAssertTrue(result.citation.contains("et al."))
    }

    func testChicago_ThreeAuthors() {
        let meta = CitationMetadata(
            title: "Test",
            authors: ["A Smith", "B Jones", "C Lee"],
            publicationDate: fixedDate,
            accessDate: fixedAccessDate
        )
        let result = generator.generate(metadata: meta, format: .chicago)
        // Chicago: 3 authors listed, with "and" before last
        XCTAssertTrue(result.citation.contains(", and"))
        XCTAssertFalse(result.citation.contains("et al."))
    }

    // MARK: - IEEE Format

    func testIEEE_SingleAuthor() {
        let meta = CitationMetadata(
            title: "Neural Networks",
            authors: ["John A. Smith"],
            publicationDate: fixedDate,
            siteName: "IEEE Review",
            url: "https://example.com",
            accessDate: fixedAccessDate
        )
        let result = generator.generate(metadata: meta, format: .ieee)
        XCTAssertTrue(result.citation.contains("J. A. Smith"))
        XCTAssertTrue(result.citation.contains("\"Neural Networks,\""))
        XCTAssertTrue(result.citation.contains("[Online]. Available:"))
        XCTAssertTrue(result.citation.contains("[Accessed:"))
    }

    func testIEEE_TwoAuthors() {
        let meta = CitationMetadata(
            title: "Test",
            authors: ["John Smith", "Jane Doe"],
            publicationDate: fixedDate,
            accessDate: fixedAccessDate
        )
        let result = generator.generate(metadata: meta, format: .ieee)
        XCTAssertTrue(result.citation.contains("J. Smith and J. Doe"))
    }

    // MARK: - Harvard Format

    func testHarvard_SingleAuthor() {
        let meta = CitationMetadata(
            title: "Machine Learning Overview",
            authors: ["John Smith"],
            publicationDate: fixedDate,
            siteName: "CS Portal",
            url: "https://example.com",
            accessDate: fixedAccessDate
        )
        let result = generator.generate(metadata: meta, format: .harvard)
        XCTAssertTrue(result.citation.contains("Smith, J."))
        XCTAssertTrue(result.citation.contains("(2026)"))
        XCTAssertTrue(result.citation.contains("'Machine Learning Overview'"))
        XCTAssertTrue(result.citation.contains("Available at:"))
        XCTAssertTrue(result.citation.contains("(Accessed:"))
    }

    func testHarvard_NoDate() {
        let meta = CitationMetadata(
            title: "Test",
            authors: ["John Smith"],
            accessDate: fixedAccessDate
        )
        let result = generator.generate(metadata: meta, format: .harvard)
        XCTAssertTrue(result.citation.contains("(n.d.)"))
    }

    // MARK: - BibTeX Format

    func testBibTeX_BasicEntry() {
        let meta = CitationMetadata(
            title: "AI Safety Research",
            authors: ["John Smith"],
            publicationDate: fixedDate,
            siteName: "Tech Blog",
            url: "https://example.com/ai",
            accessDate: fixedAccessDate
        )
        let result = generator.generate(metadata: meta, format: .bibtex)
        XCTAssertTrue(result.citation.contains("@misc{"))
        XCTAssertTrue(result.citation.contains("author = {Smith, John}"))
        XCTAssertTrue(result.citation.contains("title = {AI Safety Research}"))
        XCTAssertTrue(result.citation.contains("year = {2026}"))
        XCTAssertTrue(result.citation.contains("url = {https://example.com/ai}"))
        XCTAssertTrue(result.citation.contains("note = {Accessed:"))
    }

    func testBibTeX_MultipleAuthors() {
        let meta = CitationMetadata(
            title: "Test",
            authors: ["John Smith", "Jane Doe"],
            publicationDate: fixedDate,
            accessDate: fixedAccessDate
        )
        let result = generator.generate(metadata: meta, format: .bibtex)
        XCTAssertTrue(result.citation.contains("Smith, John and Doe, Jane"))
    }

    func testBibTeX_KeyGeneration() {
        let meta = CitationMetadata(
            title: "The Future of AI Safety",
            authors: ["John Smith"],
            publicationDate: fixedDate,
            accessDate: fixedAccessDate
        )
        let key = generator.bibtexKey(metadata: meta)
        XCTAssertEqual(key, "smith2026future")
    }

    func testBibTeX_KeyWithoutAuthor() {
        let meta = CitationMetadata(
            title: "AI Safety",
            accessDate: fixedAccessDate
        )
        let key = generator.bibtexKey(metadata: meta)
        XCTAssertEqual(key, "ai")
    }

    func testBibTeX_WithDOI() {
        let meta = CitationMetadata(
            title: "Test",
            authors: ["John Smith"],
            publicationDate: fixedDate,
            accessDate: fixedAccessDate,
            doi: "10.1234/test"
        )
        let result = generator.generate(metadata: meta, format: .bibtex)
        XCTAssertTrue(result.citation.contains("doi = {10.1234/test}"))
    }

    // MARK: - Warnings

    func testWarnings_NoAuthors() {
        let meta = CitationMetadata(title: "Test", accessDate: fixedAccessDate)
        let result = generator.generate(metadata: meta, format: .apa)
        XCTAssertTrue(result.warnings.contains("No authors specified"))
    }

    func testWarnings_NoDate() {
        let meta = CitationMetadata(title: "Test", authors: ["A"], accessDate: fixedAccessDate)
        let result = generator.generate(metadata: meta, format: .apa)
        XCTAssertTrue(result.warnings.contains("No publication date"))
    }

    func testWarnings_NoURLOrDOI() {
        let meta = CitationMetadata(title: "Test", accessDate: fixedAccessDate)
        let result = generator.generate(metadata: meta, format: .apa)
        XCTAssertTrue(result.warnings.contains("No URL or DOI provided"))
    }

    func testWarnings_EmptyTitle() {
        let meta = CitationMetadata(title: "", accessDate: fixedAccessDate)
        let result = generator.generate(metadata: meta, format: .apa)
        XCTAssertTrue(result.warnings.contains("Title is empty"))
    }

    func testWarnings_CompleteMetadata_NoWarnings() {
        let meta = CitationMetadata(
            title: "Test",
            authors: ["John Smith"],
            publicationDate: fixedDate,
            url: "https://example.com",
            accessDate: fixedAccessDate
        )
        let result = generator.generate(metadata: meta, format: .apa)
        XCTAssertEqual(result.warnings.count, 0)
    }

    // MARK: - Generate All

    func testGenerateAll_ReturnsAllFormats() {
        let meta = CitationMetadata(
            title: "Test",
            authors: ["John Smith"],
            publicationDate: fixedDate,
            url: "https://example.com",
            accessDate: fixedAccessDate
        )
        let results = generator.generateAll(metadata: meta)
        XCTAssertEqual(results.count, CitationFormat.allCases.count)

        let formats = Set(results.map { $0.format })
        for f in CitationFormat.allCases {
            XCTAssertTrue(formats.contains(f))
        }
    }

    // MARK: - Batch Operations

    func testBatchGenerate() {
        let metas = [
            CitationMetadata(title: "Article 1", authors: ["A Smith"], publicationDate: fixedDate, accessDate: fixedAccessDate),
            CitationMetadata(title: "Article 2", authors: ["B Jones"], publicationDate: fixedDate, accessDate: fixedAccessDate),
            CitationMetadata(title: "Article 3", authors: ["C Lee"], publicationDate: fixedDate, accessDate: fixedAccessDate)
        ]
        let results = generator.batchGenerate(metadataList: metas, format: .apa)
        XCTAssertEqual(results.count, 3)
    }

    func testBibliography_Numbered() {
        let metas = [
            CitationMetadata(title: "First", authors: ["A Smith"], publicationDate: fixedDate, accessDate: fixedAccessDate),
            CitationMetadata(title: "Second", authors: ["B Jones"], publicationDate: fixedDate, accessDate: fixedAccessDate)
        ]
        let bib = generator.bibliography(metadataList: metas, format: .ieee, numbered: true)
        XCTAssertTrue(bib.contains("[1]"))
        XCTAssertTrue(bib.contains("[2]"))
    }

    func testBibliography_Unnumbered() {
        let metas = [
            CitationMetadata(title: "First", authors: ["A Smith"], publicationDate: fixedDate, accessDate: fixedAccessDate),
            CitationMetadata(title: "Second", authors: ["B Jones"], publicationDate: fixedDate, accessDate: fixedAccessDate)
        ]
        let bib = generator.bibliography(metadataList: metas, format: .apa, numbered: false)
        XCTAssertFalse(bib.contains("[1]"))
        XCTAssertTrue(bib.contains("First"))
        XCTAssertTrue(bib.contains("Second"))
    }

    func testBibtexFile_MultipleEntries() {
        let metas = [
            CitationMetadata(title: "AI Safety", authors: ["John Smith"], publicationDate: fixedDate, accessDate: fixedAccessDate),
            CitationMetadata(title: "ML Ethics", authors: ["Jane Doe"], publicationDate: fixedDate, accessDate: fixedAccessDate)
        ]
        let file = generator.bibtexFile(metadataList: metas)
        let entries = file.components(separatedBy: "@misc{")
        XCTAssertEqual(entries.count, 3) // 1 empty prefix + 2 entries
    }

    // MARK: - Quality Score

    func testQualityScore_Complete() {
        let meta = CitationMetadata(
            title: "Test Article",
            authors: ["John Smith", "Jane Doe"],
            publicationDate: fixedDate,
            siteName: "Tech Blog",
            url: "https://example.com",
            accessDate: fixedAccessDate
        )
        let score = generator.qualityScore(metadata: meta)
        XCTAssertEqual(score, 95) // 25 + 20 + 5 + 20 + 15 + 10
    }

    func testQualityScore_CompleteWithDOI() {
        let meta = CitationMetadata(
            title: "Test Article",
            authors: ["John Smith", "Jane Doe"],
            publicationDate: fixedDate,
            siteName: "Journal",
            accessDate: fixedAccessDate,
            doi: "10.1234/test"
        )
        let score = generator.qualityScore(metadata: meta)
        XCTAssertEqual(score, 100) // 25 + 20 + 5 + 20 + 15 + 15
    }

    func testQualityScore_MinimalMetadata() {
        let meta = CitationMetadata(title: "Test", accessDate: fixedAccessDate)
        let score = generator.qualityScore(metadata: meta)
        XCTAssertEqual(score, 25) // Title only
    }

    func testQualityScore_Empty() {
        let meta = CitationMetadata(title: "", accessDate: fixedAccessDate)
        let score = generator.qualityScore(metadata: meta)
        XCTAssertEqual(score, 0)
    }

    // MARK: - Quality Report

    func testQualityReport_Complete() {
        let meta = CitationMetadata(
            title: "Test",
            authors: ["John Smith"],
            publicationDate: fixedDate,
            siteName: "Blog",
            url: "https://example.com",
            accessDate: fixedAccessDate
        )
        let report = generator.qualityReport(metadata: meta)
        XCTAssertTrue(report.contains("Citation Quality Report"))
        XCTAssertTrue(report.contains("✓ Authors: 1"))
        XCTAssertTrue(report.contains("✓ Publication date present"))
        XCTAssertTrue(report.contains("✓ Site name: Blog"))
    }

    func testQualityReport_MissingFields() {
        let meta = CitationMetadata(title: "Test", accessDate: fixedAccessDate)
        let report = generator.qualityReport(metadata: meta)
        XCTAssertTrue(report.contains("⚠ Missing: Authors"))
        XCTAssertTrue(report.contains("⚠ Missing: Publication date"))
        XCTAssertTrue(report.contains("⚠ Missing: URL and DOI"))
    }

    // MARK: - JSON Persistence

    func testExportToJSON() {
        let meta = CitationMetadata(
            title: "Test Article",
            authors: ["John Smith"],
            publicationDate: fixedDate,
            siteName: "Blog",
            url: "https://example.com",
            accessDate: fixedAccessDate,
            publisher: "Pub Co",
            doi: "10.1234/test"
        )
        let json = generator.exportToJSON(metadata: meta)
        XCTAssertEqual(json["title"] as? String, "Test Article")
        XCTAssertEqual((json["authors"] as? [String])?.count, 1)
        XCTAssertEqual(json["siteName"] as? String, "Blog")
        XCTAssertEqual(json["doi"] as? String, "10.1234/test")
        XCTAssertEqual(json["publisher"] as? String, "Pub Co")
    }

    func testImportFromJSON() {
        let dict: [String: Any] = [
            "title": "Imported Article",
            "authors": ["Jane Doe"],
            "publicationDate": "2026-03-15",
            "siteName": "Portal",
            "url": "https://example.com",
            "accessDate": "2026-04-01"
        ]
        let meta = generator.importFromJSON(dict)
        XCTAssertNotNil(meta)
        XCTAssertEqual(meta?.title, "Imported Article")
        XCTAssertEqual(meta?.authors, ["Jane Doe"])
        XCTAssertEqual(meta?.siteName, "Portal")
    }

    func testImportFromJSON_MissingTitle() {
        let dict: [String: Any] = ["authors": ["A"]]
        let meta = generator.importFromJSON(dict)
        XCTAssertNil(meta)
    }

    func testRoundTrip_JSONExportImport() {
        let original = CitationMetadata(
            title: "Round Trip",
            authors: ["Alice Brown", "Bob White"],
            publicationDate: fixedDate,
            siteName: "Test Site",
            url: "https://roundtrip.com",
            accessDate: fixedAccessDate,
            doi: "10.5678/rt"
        )
        let json = generator.exportToJSON(metadata: original)
        let imported = generator.importFromJSON(json)
        XCTAssertNotNil(imported)
        XCTAssertEqual(imported?.title, original.title)
        XCTAssertEqual(imported?.authors, original.authors)
        XCTAssertEqual(imported?.siteName, original.siteName)
        XCTAssertEqual(imported?.doi, original.doi)
    }

    // MARK: - Edge Cases

    func testFormat_NoAuthors_NoDate() {
        let meta = CitationMetadata(
            title: "Anonymous Article",
            url: "https://example.com",
            accessDate: fixedAccessDate
        )
        // Should not crash for any format
        for format in CitationFormat.allCases {
            let result = generator.generate(metadata: meta, format: format)
            XCTAssertFalse(result.citation.isEmpty, "Citation should not be empty for \(format)")
        }
    }

    func testFormat_AllFormatsPopulated() {
        let meta = CitationMetadata(
            title: "Complete Article",
            authors: ["John Smith", "Jane Doe"],
            publicationDate: fixedDate,
            siteName: "Science Daily",
            url: "https://example.com/article",
            accessDate: fixedAccessDate,
            publisher: "Science Corp",
            doi: "10.1234/complete"
        )
        for format in CitationFormat.allCases {
            let result = generator.generate(metadata: meta, format: format)
            XCTAssertFalse(result.citation.isEmpty, "Citation should not be empty for \(format)")
            XCTAssertEqual(result.format, format)
        }
    }

    func testCitationFormat_AllCases() {
        XCTAssertEqual(CitationFormat.allCases.count, 6)
    }

    func testCitationFormat_RawValues() {
        XCTAssertEqual(CitationFormat.apa.rawValue, "apa")
        XCTAssertEqual(CitationFormat.mla.rawValue, "mla")
        XCTAssertEqual(CitationFormat.chicago.rawValue, "chicago")
        XCTAssertEqual(CitationFormat.ieee.rawValue, "ieee")
        XCTAssertEqual(CitationFormat.harvard.rawValue, "harvard")
        XCTAssertEqual(CitationFormat.bibtex.rawValue, "bibtex")
    }

    // MARK: - MLA Publisher vs Site Name

    func testMLA_PublisherDifferentFromSite() {
        let meta = CitationMetadata(
            title: "Test",
            authors: ["John Smith"],
            publicationDate: fixedDate,
            siteName: "Science Daily",
            url: "https://example.com",
            accessDate: fixedAccessDate,
            publisher: "Science Corp"
        )
        let result = generator.generate(metadata: meta, format: .mla)
        XCTAssertTrue(result.citation.contains("Science Daily"))
        XCTAssertTrue(result.citation.contains("Science Corp"))
    }

    func testMLA_PublisherSameAsSite() {
        let meta = CitationMetadata(
            title: "Test",
            authors: ["John Smith"],
            publicationDate: fixedDate,
            siteName: "Science Daily",
            url: "https://example.com",
            accessDate: fixedAccessDate,
            publisher: "Science Daily"
        )
        let result = generator.generate(metadata: meta, format: .mla)
        // Publisher should not be duplicated
        let count = result.citation.components(separatedBy: "Science Daily").count - 1
        XCTAssertEqual(count, 1)
    }

    // MARK: - APA Many Authors

    func testAPA_MoreThan20Authors() {
        let authors = (1...22).map { "Author\($0) Last\($0)" }
        let meta = CitationMetadata(
            title: "Large Team Paper",
            authors: authors,
            publicationDate: fixedDate,
            accessDate: fixedAccessDate
        )
        let result = generator.generate(metadata: meta, format: .apa)
        XCTAssertTrue(result.citation.contains(". . ."))
    }

    // MARK: - IEEE Many Authors

    func testIEEE_MoreThan6Authors() {
        let authors = (1...8).map { "Author\($0) Last\($0)" }
        let meta = CitationMetadata(
            title: "Big Team",
            authors: authors,
            publicationDate: fixedDate,
            accessDate: fixedAccessDate
        )
        let result = generator.generate(metadata: meta, format: .ieee)
        XCTAssertTrue(result.citation.contains("et al."))
    }

    // MARK: - Harvard Multiple Authors

    func testHarvard_TwoAuthors() {
        let meta = CitationMetadata(
            title: "Test",
            authors: ["John Smith", "Jane Doe"],
            publicationDate: fixedDate,
            accessDate: fixedAccessDate
        )
        let result = generator.generate(metadata: meta, format: .harvard)
        XCTAssertTrue(result.citation.contains(" and "))
    }

    func testHarvard_FourAuthorsEtAl() {
        let meta = CitationMetadata(
            title: "Test",
            authors: ["A Smith", "B Jones", "C Lee", "D Kim"],
            publicationDate: fixedDate,
            accessDate: fixedAccessDate
        )
        let result = generator.generate(metadata: meta, format: .harvard)
        XCTAssertTrue(result.citation.contains("et al."))
    }

    // MARK: - Citation Result Properties

    func testCitationResult_Metadata() {
        let meta = CitationMetadata(
            title: "Test",
            authors: ["John Smith"],
            publicationDate: fixedDate,
            accessDate: fixedAccessDate
        )
        let result = generator.generate(metadata: meta, format: .apa)
        XCTAssertEqual(result.metadata.title, "Test")
        XCTAssertEqual(result.format, .apa)
    }

    // MARK: - Whitespace Handling

    func testTitle_WithWhitespace() {
        let meta = CitationMetadata(
            title: "  Spaces Around  ",
            authors: ["A Smith"],
            publicationDate: fixedDate,
            accessDate: fixedAccessDate
        )
        let result = generator.generate(metadata: meta, format: .apa)
        XCTAssertTrue(result.citation.contains("Spaces Around"))
    }

    func testAuthor_WithWhitespace() {
        let author = ArticleCitationGenerator.parseAuthorName("  John   Smith  ")
        XCTAssertEqual(author.firstName, "John")
        XCTAssertEqual(author.lastName, "Smith")
    }
}
