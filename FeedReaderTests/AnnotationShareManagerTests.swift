//
//  AnnotationShareManagerTests.swift
//  FeedReaderTests
//
//  Tests for the Annotation Share Manager — export, decode, import,
//  error handling, and round-trip consistency.
//

import XCTest
@testable import FeedReader

class AnnotationShareManagerTests: XCTestCase {

    let manager = AnnotationShareManager.shared

    override func setUp() {
        super.setUp()
        // Clear any test data
        UserDefaults.standard.removeObject(forKey: "ArticleHighlightsManager.highlights")
        UserDefaults.standard.removeObject(forKey: "ArticleNotesManager.notes")
    }

    // MARK: - ShareableHighlight

    func testShareableHighlightEquality() {
        let a = ShareableHighlight(selectedText: "hello", color: 0, annotation: nil)
        let b = ShareableHighlight(selectedText: "hello", color: 0, annotation: nil)
        let c = ShareableHighlight(selectedText: "world", color: 1, annotation: "note")
        XCTAssertEqual(a, b)
        XCTAssertNotEqual(a, c)
    }

    // MARK: - ShareableNote

    func testShareableNoteEquality() {
        let a = ShareableNote(text: "My thoughts")
        let b = ShareableNote(text: "My thoughts")
        let c = ShareableNote(text: "Different")
        XCTAssertEqual(a, b)
        XCTAssertNotEqual(a, c)
    }

    // MARK: - AnnotationBundle

    func testAnnotationBundleCodable() throws {
        let bundle = AnnotationBundle(
            version: 1,
            articleLink: "https://example.com/article",
            articleTitle: "Test Article",
            highlights: [
                ShareableHighlight(selectedText: "important text", color: 2, annotation: "key point")
            ],
            notes: [ShareableNote(text: "Great article")],
            exportedAt: "2026-03-17T00:00:00Z",
            sharedBy: "TestUser"
        )

        let data = try JSONEncoder().encode(bundle)
        let decoded = try JSONDecoder().decode(AnnotationBundle.self, from: data)

        XCTAssertEqual(bundle, decoded)
        XCTAssertEqual(decoded.version, 1)
        XCTAssertEqual(decoded.highlights.count, 1)
        XCTAssertEqual(decoded.notes.count, 1)
        XCTAssertEqual(decoded.sharedBy, "TestUser")
    }

    func testMagicPrefix() {
        XCTAssertEqual(AnnotationBundle.magicPrefix, "FR-ANN:")
    }

    // MARK: - Import Result

    func testImportResultSummary() {
        let result = AnnotationImportResult(
            articleLink: "https://example.com",
            articleTitle: "Test",
            highlightsAdded: 3,
            highlightsSkipped: 1,
            notesAdded: 1,
            notesSkipped: 0
        )
        XCTAssertEqual(result.totalAdded, 4)
        XCTAssertEqual(result.totalSkipped, 1)
        XCTAssertTrue(result.summary.contains("3 highlight(s) added"))
        XCTAssertTrue(result.summary.contains("1 note(s) added"))
    }

    func testImportResultEmptySummary() {
        let result = AnnotationImportResult(
            articleLink: "https://example.com",
            articleTitle: "Test",
            highlightsAdded: 0,
            highlightsSkipped: 0,
            notesAdded: 0,
            notesSkipped: 0
        )
        XCTAssertEqual(result.summary, "Nothing to import.")
    }

    // MARK: - Error Descriptions

    func testErrorDescriptions() {
        XCTAssertNotNil(AnnotationShareError.emptyAnnotations.errorDescription)
        XCTAssertNotNil(AnnotationShareError.encodingFailed.errorDescription)
        XCTAssertNotNil(AnnotationShareError.invalidShareCode.errorDescription)
        XCTAssertNotNil(AnnotationShareError.decodingFailed.errorDescription)
        XCTAssertNotNil(AnnotationShareError.unsupportedVersion(99).errorDescription)
        XCTAssertTrue(AnnotationShareError.unsupportedVersion(99).errorDescription!.contains("99"))

        let mismatch = AnnotationShareError.articleMismatch(expected: "A", got: "B")
        XCTAssertTrue(mismatch.errorDescription!.contains("A"))
        XCTAssertTrue(mismatch.errorDescription!.contains("B"))
    }

    // MARK: - Decode Invalid Codes

    func testDecodeInvalidCodeThrows() {
        XCTAssertThrowsError(try manager.decodeShareCode("not-valid!!!")) { error in
            XCTAssertTrue(error is AnnotationShareError)
        }
    }

    func testDecodeEmptyStringThrows() {
        XCTAssertThrowsError(try manager.decodeShareCode(""))
    }

    // MARK: - Bundle Summary

    func testBundleSummary() {
        let bundle = AnnotationBundle(
            version: 1,
            articleLink: "https://example.com/a",
            articleTitle: "My Article",
            highlights: [
                ShareableHighlight(selectedText: "x", color: 0, annotation: nil),
                ShareableHighlight(selectedText: "y", color: 1, annotation: nil)
            ],
            notes: [],
            exportedAt: "2026-03-17T00:00:00Z",
            sharedBy: "Alice"
        )

        let summary = manager.bundleSummary(bundle)
        XCTAssertTrue(summary.contains("My Article"))
        XCTAssertTrue(summary.contains("Alice"))
        XCTAssertTrue(summary.contains("2 highlight(s)"))
        XCTAssertTrue(summary.contains("0 note(s)"))
    }

    func testBundleSummaryNoSharer() {
        let bundle = AnnotationBundle(
            version: 1,
            articleLink: "https://example.com/a",
            articleTitle: "Solo",
            highlights: [],
            notes: [ShareableNote(text: "note")],
            exportedAt: "2026-01-01T00:00:00Z",
            sharedBy: nil
        )

        let summary = manager.bundleSummary(bundle)
        XCTAssertFalse(summary.contains("Shared by"))
        XCTAssertTrue(summary.contains("1 note(s)"))
    }

    // MARK: - Round-trip Encode/Decode Bundle

    func testManualRoundTrip() throws {
        let bundle = AnnotationBundle(
            version: 1,
            articleLink: "https://example.com/test",
            articleTitle: "Round Trip Test",
            highlights: [
                ShareableHighlight(selectedText: "key insight", color: 3, annotation: "pink highlight")
            ],
            notes: [ShareableNote(text: "Fascinating read")],
            exportedAt: "2026-03-17T18:00:00Z",
            sharedBy: "Tester"
        )

        // Encode manually (same as manager internals)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let jsonData = try encoder.encode(bundle)
        let base64 = jsonData.base64EncodedString()
        let code = AnnotationBundle.magicPrefix + base64

        // Decode via manager
        let decoded = try manager.decodeShareCode(code)
        XCTAssertEqual(decoded, bundle)
        XCTAssertEqual(decoded.highlights.first?.selectedText, "key insight")
        XCTAssertEqual(decoded.notes.first?.text, "Fascinating read")
    }
}
