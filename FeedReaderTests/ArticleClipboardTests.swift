//
//  ArticleClipboardTests.swift
//  FeedReaderTests
//
//  Tests for ArticleClipboard and ClipboardSnippet.
//

import XCTest
@testable import FeedReader

class ClipboardSnippetTests: XCTestCase {

    // MARK: - Initialization

    func testValidSnippetCreation() {
        let snippet = ClipboardSnippet(
            sourceURL: "https://example.com/article",
            sourceTitle: "Test Article",
            text: "An interesting quote."
        )
        XCTAssertNotNil(snippet)
        XCTAssertEqual(snippet?.sourceURL, "https://example.com/article")
        XCTAssertEqual(snippet?.sourceTitle, "Test Article")
        XCTAssertEqual(snippet?.text, "An interesting quote.")
        XCTAssertNil(snippet?.note)
        XCTAssertTrue(snippet?.tags.isEmpty ?? false)
        XCTAssertFalse(snippet?.id.isEmpty ?? true)
    }

    func testEmptyTextReturnsNil() {
        let snippet = ClipboardSnippet(
            sourceURL: "https://example.com",
            sourceTitle: "Title",
            text: ""
        )
        XCTAssertNil(snippet)
    }

    func testWhitespaceOnlyTextReturnsNil() {
        let snippet = ClipboardSnippet(
            sourceURL: "https://example.com",
            sourceTitle: "Title",
            text: "   \n\t  "
        )
        XCTAssertNil(snippet)
    }

    func testEmptyURLReturnsNil() {
        let snippet = ClipboardSnippet(
            sourceURL: "",
            sourceTitle: "Title",
            text: "Some text"
        )
        XCTAssertNil(snippet)
    }

    func testEmptyTitleDefaultsToUntitled() {
        let snippet = ClipboardSnippet(
            sourceURL: "https://example.com",
            sourceTitle: "",
            text: "Some text"
        )
        XCTAssertEqual(snippet?.sourceTitle, "Untitled")
    }

    func testTextTruncation() {
        let longText = String(repeating: "a", count: 6000)
        let snippet = ClipboardSnippet(
            sourceURL: "https://example.com",
            sourceTitle: "Title",
            text: longText
        )
        XCTAssertEqual(snippet?.text.count, ClipboardSnippet.maxTextLength)
    }

    func testNoteTruncation() {
        let longNote = String(repeating: "n", count: 1500)
        let snippet = ClipboardSnippet(
            sourceURL: "https://example.com",
            sourceTitle: "Title",
            text: "Quote",
            note: longNote
        )
        XCTAssertEqual(snippet?.note?.count, ClipboardSnippet.maxNoteLength)
    }

    func testEmptyNoteBecomesNil() {
        let snippet = ClipboardSnippet(
            sourceURL: "https://example.com",
            sourceTitle: "Title",
            text: "Quote",
            note: "   "
        )
        XCTAssertNil(snippet?.note)
    }

    func testTextTrimsWhitespace() {
        let snippet = ClipboardSnippet(
            sourceURL: "https://example.com",
            sourceTitle: "Title",
            text: "  spaced text  "
        )
        XCTAssertEqual(snippet?.text, "spaced text")
    }

    // MARK: - Tags

    func testTagSanitization() {
        let snippet = ClipboardSnippet(
            sourceURL: "https://example.com",
            sourceTitle: "Title",
            text: "Quote",
            tags: ["AI", "  Research ", "ai", "ML"]
        )
        // "ai" appears twice — deduplication
        XCTAssertEqual(snippet?.tags, ["ai", "research", "ml"])
    }

    func testMaxTagsEnforced() {
        let tooManyTags = (0..<20).map { "tag\($0)" }
        let snippet = ClipboardSnippet(
            sourceURL: "https://example.com",
            sourceTitle: "Title",
            text: "Quote",
            tags: tooManyTags
        )
        XCTAssertEqual(snippet?.tags.count, ClipboardSnippet.maxTags)
    }

    func testAddTag() {
        let snippet = ClipboardSnippet(
            sourceURL: "https://example.com",
            sourceTitle: "Title",
            text: "Quote"
        )!
        XCTAssertTrue(snippet.addTag("research"))
        XCTAssertEqual(snippet.tags, ["research"])
    }

    func testAddDuplicateTagFails() {
        let snippet = ClipboardSnippet(
            sourceURL: "https://example.com",
            sourceTitle: "Title",
            text: "Quote",
            tags: ["research"]
        )!
        XCTAssertFalse(snippet.addTag("research"))
    }

    func testAddEmptyTagFails() {
        let snippet = ClipboardSnippet(
            sourceURL: "https://example.com",
            sourceTitle: "Title",
            text: "Quote"
        )!
        XCTAssertFalse(snippet.addTag(""))
        XCTAssertFalse(snippet.addTag("   "))
    }

    func testRemoveTag() {
        let snippet = ClipboardSnippet(
            sourceURL: "https://example.com",
            sourceTitle: "Title",
            text: "Quote",
            tags: ["ai", "research"]
        )!
        XCTAssertTrue(snippet.removeTag("ai"))
        XCTAssertEqual(snippet.tags, ["research"])
    }

    func testRemoveNonexistentTagFails() {
        let snippet = ClipboardSnippet(
            sourceURL: "https://example.com",
            sourceTitle: "Title",
            text: "Quote"
        )!
        XCTAssertFalse(snippet.removeTag("missing"))
    }

    // MARK: - Word Count

    func testWordCount() {
        let snippet = ClipboardSnippet(
            sourceURL: "https://example.com",
            sourceTitle: "Title",
            text: "The quick brown fox jumps"
        )!
        XCTAssertEqual(snippet.wordCount, 5)
    }

    func testWordCountSingleWord() {
        let snippet = ClipboardSnippet(
            sourceURL: "https://example.com",
            sourceTitle: "Title",
            text: "Hello"
        )!
        XCTAssertEqual(snippet.wordCount, 1)
    }

    // MARK: - NSSecureCoding

    func testSecureCodingRoundTrip() {
        let original = ClipboardSnippet(
            sourceURL: "https://example.com/test",
            sourceTitle: "Coding Test",
            text: "Important insight about testing.",
            note: "Remember this",
            tags: ["testing", "swift"]
        )!

        guard let data = try? NSKeyedArchiver.archivedData(
            withRootObject: original, requiringSecureCoding: true
        ) else {
            XCTFail("Failed to archive")
            return
        }

        guard let decoded = try? NSKeyedUnarchiver.unarchivedObject(
            ofClass: ClipboardSnippet.self, from: data
        ) else {
            XCTFail("Failed to unarchive")
            return
        }

        XCTAssertEqual(decoded.id, original.id)
        XCTAssertEqual(decoded.sourceURL, original.sourceURL)
        XCTAssertEqual(decoded.sourceTitle, original.sourceTitle)
        XCTAssertEqual(decoded.text, original.text)
        XCTAssertEqual(decoded.note, original.note)
        XCTAssertEqual(decoded.tags, original.tags)
        XCTAssertEqual(decoded.clippedDate, original.clippedDate)
    }
}

// MARK: - ArticleClipboard Tests

class ArticleClipboardTests: XCTestCase {

    private func makeClipboard() -> ArticleClipboard {
        ArticleClipboard(snippets: [])
    }

    private func makePopulatedClipboard() -> ArticleClipboard {
        let clipboard = makeClipboard()
        clipboard.clip(sourceURL: "https://a.com/1", sourceTitle: "AI Safety",
                       text: "Alignment is critical for safe AI deployment.",
                       tags: ["ai", "safety"])
        clipboard.clip(sourceURL: "https://a.com/1", sourceTitle: "AI Safety",
                       text: "Interpretability helps us understand model behavior.",
                       tags: ["ai", "interpretability"])
        clipboard.clip(sourceURL: "https://b.com/2", sourceTitle: "Climate Report",
                       text: "Global temperatures have risen 1.1°C since pre-industrial times.",
                       tags: ["climate", "science"])
        return clipboard
    }

    // MARK: - Clip

    func testClipAddsSnippet() {
        let clipboard = makeClipboard()
        let snippet = clipboard.clip(
            sourceURL: "https://example.com",
            sourceTitle: "Article",
            text: "A great quote."
        )
        XCTAssertNotNil(snippet)
        XCTAssertEqual(clipboard.count, 1)
    }

    func testClipInvalidTextReturnsNil() {
        let clipboard = makeClipboard()
        let snippet = clipboard.clip(
            sourceURL: "https://example.com",
            sourceTitle: "Article",
            text: ""
        )
        XCTAssertNil(snippet)
        XCTAssertEqual(clipboard.count, 0)
    }

    func testClipNewestFirst() {
        let clipboard = makeClipboard()
        clipboard.clip(sourceURL: "https://a.com", sourceTitle: "First", text: "One")
        clipboard.clip(sourceURL: "https://b.com", sourceTitle: "Second", text: "Two")
        let all = clipboard.allSnippets
        XCTAssertEqual(all[0].sourceTitle, "Second")
        XCTAssertEqual(all[1].sourceTitle, "First")
    }

    func testClipAtCapacity() {
        var snippets: [ClipboardSnippet] = []
        for i in 0..<ArticleClipboard.maxSnippets {
            if let s = ClipboardSnippet(
                sourceURL: "https://e.com/\(i)",
                sourceTitle: "T\(i)",
                text: "Text \(i)"
            ) {
                snippets.append(s)
            }
        }
        let clipboard = ArticleClipboard(snippets: snippets)
        XCTAssertTrue(clipboard.isFull)

        let extra = clipboard.clip(
            sourceURL: "https://overflow.com",
            sourceTitle: "Overflow",
            text: "Should not be added"
        )
        XCTAssertNil(extra)
        XCTAssertEqual(clipboard.count, ArticleClipboard.maxSnippets)
    }

    // MARK: - Remove

    func testRemoveById() {
        let clipboard = makeClipboard()
        let snippet = clipboard.clip(
            sourceURL: "https://example.com",
            sourceTitle: "Article",
            text: "Quote"
        )!
        XCTAssertTrue(clipboard.remove(id: snippet.id))
        XCTAssertEqual(clipboard.count, 0)
    }

    func testRemoveNonexistentReturnsFalse() {
        let clipboard = makeClipboard()
        XCTAssertFalse(clipboard.remove(id: "nonexistent"))
    }

    func testRemoveAll() {
        let clipboard = makePopulatedClipboard()
        XCTAssertEqual(clipboard.count, 3)
        clipboard.removeAll()
        XCTAssertTrue(clipboard.isEmpty)
    }

    func testRemoveAllOnEmptyIsNoOp() {
        let clipboard = makeClipboard()
        clipboard.removeAll() // should not crash
        XCTAssertTrue(clipboard.isEmpty)
    }

    // MARK: - Query

    func testSnippetById() {
        let clipboard = makeClipboard()
        let snippet = clipboard.clip(
            sourceURL: "https://example.com",
            sourceTitle: "Article",
            text: "Quote"
        )!
        XCTAssertNotNil(clipboard.snippet(id: snippet.id))
        XCTAssertNil(clipboard.snippet(id: "missing"))
    }

    func testSnippetsFromArticle() {
        let clipboard = makePopulatedClipboard()
        let fromA = clipboard.snippets(fromArticle: "https://a.com/1")
        XCTAssertEqual(fromA.count, 2)
    }

    func testSnippetsTagged() {
        let clipboard = makePopulatedClipboard()
        let aiSnippets = clipboard.snippets(tagged: "ai")
        XCTAssertEqual(aiSnippets.count, 2)
        let climateSnippets = clipboard.snippets(tagged: "climate")
        XCTAssertEqual(climateSnippets.count, 1)
    }

    func testAllTags() {
        let clipboard = makePopulatedClipboard()
        let tags = clipboard.allTags
        XCTAssertEqual(tags, ["ai", "climate", "interpretability", "safety", "science"])
    }

    func testTagCounts() {
        let clipboard = makePopulatedClipboard()
        let counts = clipboard.tagCounts
        let aiCount = counts.first { $0.tag == "ai" }
        XCTAssertEqual(aiCount?.count, 2)
    }

    func testSourceCount() {
        let clipboard = makePopulatedClipboard()
        XCTAssertEqual(clipboard.sourceCount, 2)
    }

    func testTotalWordCount() {
        let clipboard = makeClipboard()
        clipboard.clip(sourceURL: "https://a.com", sourceTitle: "A",
                       text: "one two three")
        clipboard.clip(sourceURL: "https://b.com", sourceTitle: "B",
                       text: "four five")
        XCTAssertEqual(clipboard.totalWordCount, 5)
    }

    func testIsEmpty() {
        let clipboard = makeClipboard()
        XCTAssertTrue(clipboard.isEmpty)
        clipboard.clip(sourceURL: "https://a.com", sourceTitle: "A", text: "quote")
        XCTAssertFalse(clipboard.isEmpty)
    }

    // MARK: - Search

    func testSearchByText() {
        let clipboard = makePopulatedClipboard()
        let results = clipboard.search("alignment")
        XCTAssertEqual(results.count, 1)
        XCTAssertEqual(results[0].text, "Alignment is critical for safe AI deployment.")
    }

    func testSearchBySourceTitle() {
        let clipboard = makePopulatedClipboard()
        let results = clipboard.search("climate report")
        XCTAssertEqual(results.count, 1)
    }

    func testSearchByTag() {
        let clipboard = makePopulatedClipboard()
        let results = clipboard.search("safety")
        XCTAssertEqual(results.count, 1)
    }

    func testSearchByNote() {
        let clipboard = makeClipboard()
        clipboard.clip(sourceURL: "https://a.com", sourceTitle: "A",
                       text: "Quote text", note: "key insight here")
        let results = clipboard.search("key insight")
        XCTAssertEqual(results.count, 1)
    }

    func testSearchCaseInsensitive() {
        let clipboard = makePopulatedClipboard()
        let upper = clipboard.search("ALIGNMENT")
        let lower = clipboard.search("alignment")
        XCTAssertEqual(upper.count, lower.count)
    }

    func testSearchEmptyReturnsAll() {
        let clipboard = makePopulatedClipboard()
        let results = clipboard.search("")
        XCTAssertEqual(results.count, clipboard.count)
    }

    func testSearchNoMatch() {
        let clipboard = makePopulatedClipboard()
        let results = clipboard.search("xyznonexistent")
        XCTAssertTrue(results.isEmpty)
    }

    // MARK: - Update

    func testUpdateNote() {
        let clipboard = makeClipboard()
        let snippet = clipboard.clip(
            sourceURL: "https://a.com", sourceTitle: "A", text: "Quote"
        )!
        XCTAssertTrue(clipboard.updateNote(id: snippet.id, note: "My note"))
        XCTAssertEqual(clipboard.snippet(id: snippet.id)?.note, "My note")
    }

    func testUpdateNoteToNil() {
        let clipboard = makeClipboard()
        let snippet = clipboard.clip(
            sourceURL: "https://a.com", sourceTitle: "A", text: "Quote",
            note: "Original"
        )!
        XCTAssertTrue(clipboard.updateNote(id: snippet.id, note: nil))
        XCTAssertNil(clipboard.snippet(id: snippet.id)?.note)
    }

    func testUpdateNoteInvalidId() {
        let clipboard = makeClipboard()
        XCTAssertFalse(clipboard.updateNote(id: "bad", note: "Note"))
    }

    func testAddTagToSnippet() {
        let clipboard = makeClipboard()
        let snippet = clipboard.clip(
            sourceURL: "https://a.com", sourceTitle: "A", text: "Quote"
        )!
        XCTAssertTrue(clipboard.addTag(id: snippet.id, tag: "new"))
        XCTAssertTrue(clipboard.snippet(id: snippet.id)?.tags.contains("new") ?? false)
    }

    func testRemoveTagFromSnippet() {
        let clipboard = makeClipboard()
        let snippet = clipboard.clip(
            sourceURL: "https://a.com", sourceTitle: "A", text: "Quote",
            tags: ["removeme"]
        )!
        XCTAssertTrue(clipboard.removeTag(id: snippet.id, tag: "removeme"))
        XCTAssertTrue(clipboard.snippet(id: snippet.id)?.tags.isEmpty ?? false)
    }

    // MARK: - Export Markdown

    func testExportMarkdownNotEmpty() {
        let clipboard = makePopulatedClipboard()
        let md = clipboard.exportMarkdown()
        XCTAssertFalse(md.isEmpty)
        XCTAssertTrue(md.contains("# Research Clipboard"))
    }

    func testExportMarkdownContainsSnippetText() {
        let clipboard = makePopulatedClipboard()
        let md = clipboard.exportMarkdown()
        XCTAssertTrue(md.contains("Alignment is critical"))
        XCTAssertTrue(md.contains("Global temperatures"))
    }

    func testExportMarkdownGroupsBySource() {
        let clipboard = makePopulatedClipboard()
        let md = clipboard.exportMarkdown()
        XCTAssertTrue(md.contains("## AI Safety"))
        XCTAssertTrue(md.contains("## Climate Report"))
    }

    func testExportMarkdownIncludesTags() {
        let clipboard = makePopulatedClipboard()
        let md = clipboard.exportMarkdown()
        XCTAssertTrue(md.contains("#ai"))
        XCTAssertTrue(md.contains("#safety"))
    }

    func testExportMarkdownWithoutMetadata() {
        let clipboard = makePopulatedClipboard()
        let md = clipboard.exportMarkdown(includeMetadata: false)
        XCTAssertFalse(md.contains("#ai"))
        XCTAssertFalse(md.contains("Clipped:"))
    }

    func testExportMarkdownEmptyClipboard() {
        let clipboard = makeClipboard()
        XCTAssertEqual(clipboard.exportMarkdown(), "")
    }

    func testExportMarkdownSubset() {
        let clipboard = makePopulatedClipboard()
        let aiOnly = clipboard.snippets(tagged: "ai")
        let md = clipboard.exportMarkdown(snippets: aiOnly)
        XCTAssertTrue(md.contains("AI Safety"))
        XCTAssertFalse(md.contains("Climate Report"))
    }

    // MARK: - Export Plain Text

    func testExportPlainText() {
        let clipboard = makePopulatedClipboard()
        let text = clipboard.exportPlainText()
        XCTAssertTrue(text.contains("RESEARCH CLIPBOARD"))
        XCTAssertTrue(text.contains("Alignment is critical"))
    }

    func testExportPlainTextNumbering() {
        let clipboard = makePopulatedClipboard()
        let text = clipboard.exportPlainText()
        XCTAssertTrue(text.contains("[1]"))
        XCTAssertTrue(text.contains("[2]"))
        XCTAssertTrue(text.contains("[3]"))
    }

    // MARK: - Export JSON

    func testExportJSON() {
        let clipboard = makePopulatedClipboard()
        let json = clipboard.exportJSON()
        XCTAssertFalse(json.isEmpty)
        // Should be valid JSON
        let data = json.data(using: .utf8)!
        let parsed = try? JSONSerialization.jsonObject(with: data)
        XCTAssertNotNil(parsed)
        let array = parsed as? [[String: Any]]
        XCTAssertEqual(array?.count, 3)
    }

    func testExportJSONContainsFields() {
        let clipboard = makeClipboard()
        clipboard.clip(sourceURL: "https://a.com", sourceTitle: "Test",
                       text: "Quote", note: "Note here", tags: ["tag1"])
        let json = clipboard.exportJSON()
        XCTAssertTrue(json.contains("sourceURL"))
        XCTAssertTrue(json.contains("sourceTitle"))
        XCTAssertTrue(json.contains("text"))
        XCTAssertTrue(json.contains("note"))
        XCTAssertTrue(json.contains("tags"))
        XCTAssertTrue(json.contains("wordCount"))
    }

    func testExportJSONEmpty() {
        let clipboard = makeClipboard()
        XCTAssertEqual(clipboard.exportJSON(), "[]")
    }

    // MARK: - Export Generic

    func testExportFormatMarkdown() {
        let clipboard = makePopulatedClipboard()
        let result = clipboard.export(format: .markdown)
        XCTAssertTrue(result.contains("# Research Clipboard"))
    }

    func testExportFormatPlainText() {
        let clipboard = makePopulatedClipboard()
        let result = clipboard.export(format: .plainText)
        XCTAssertTrue(result.contains("RESEARCH CLIPBOARD"))
    }

    func testExportFormatJSON() {
        let clipboard = makePopulatedClipboard()
        let result = clipboard.export(format: .json)
        XCTAssertTrue(result.starts(with: "["))
    }

    // MARK: - Statistics

    func testStats() {
        let clipboard = makePopulatedClipboard()
        let stats = clipboard.stats
        XCTAssertEqual(stats.snippetCount, 3)
        XCTAssertEqual(stats.sourceCount, 2)
        XCTAssertTrue(stats.totalWordCount > 0)
        XCTAssertEqual(stats.tagCount, 5)
        XCTAssertTrue(stats.topTags.count <= 5)
        XCTAssertNotNil(stats.oldestClip)
        XCTAssertNotNil(stats.newestClip)
    }

    func testStatsDateRange() {
        let clipboard = makePopulatedClipboard()
        let range = clipboard.stats.dateRange
        XCTAssertFalse(range.isEmpty)
        XCTAssertNotEqual(range, "N/A")
    }

    func testStatsEmptyClipboard() {
        let clipboard = makeClipboard()
        let stats = clipboard.stats
        XCTAssertEqual(stats.snippetCount, 0)
        XCTAssertEqual(stats.sourceCount, 0)
        XCTAssertEqual(stats.totalWordCount, 0)
        XCTAssertNil(stats.oldestClip)
        XCTAssertEqual(stats.dateRange, "N/A")
    }

    // MARK: - Notification

    func testClipPostsNotification() {
        let clipboard = makeClipboard()
        let expectation = self.expectation(
            forNotification: .articleClipboardDidChange, object: clipboard
        )
        clipboard.clip(sourceURL: "https://a.com", sourceTitle: "A", text: "Quote")
        wait(for: [expectation], timeout: 1.0)
    }

    func testRemovePostsNotification() {
        let clipboard = makeClipboard()
        let snippet = clipboard.clip(
            sourceURL: "https://a.com", sourceTitle: "A", text: "Quote"
        )!
        let expectation = self.expectation(
            forNotification: .articleClipboardDidChange, object: clipboard
        )
        clipboard.remove(id: snippet.id)
        wait(for: [expectation], timeout: 1.0)
    }

    // MARK: - Init with Snippets

    func testInitWithSnippets() {
        let s1 = ClipboardSnippet(sourceURL: "https://a.com", sourceTitle: "A", text: "One")!
        let s2 = ClipboardSnippet(sourceURL: "https://b.com", sourceTitle: "B", text: "Two")!
        let clipboard = ArticleClipboard(snippets: [s1, s2])
        XCTAssertEqual(clipboard.count, 2)
        XCTAssertNotNil(clipboard.snippet(id: s1.id))
    }
}
