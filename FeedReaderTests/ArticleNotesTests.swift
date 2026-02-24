//
//  ArticleNotesTests.swift
//  FeedReaderTests
//
//  Tests for ArticleNote model and ArticleNotesManager —
//  CRUD, search, persistence, notifications, edge cases.
//

import XCTest
@testable import FeedReader

class ArticleNotesTests: XCTestCase {
    
    var manager: ArticleNotesManager!
    
    override func setUp() {
        super.setUp()
        manager = ArticleNotesManager.shared
        manager.reset()
    }
    
    override func tearDown() {
        manager.reset()
        super.tearDown()
    }
    
    // MARK: - ArticleNote Model Tests
    
    func testNoteInitialization() {
        let note = ArticleNote(
            articleLink: "https://example.com/article1",
            articleTitle: "Test Article",
            text: "My note"
        )
        XCTAssertEqual(note.articleLink, "https://example.com/article1")
        XCTAssertEqual(note.articleTitle, "Test Article")
        XCTAssertEqual(note.text, "My note")
    }
    
    func testNoteDefaultDates() {
        let before = Date()
        let note = ArticleNote(
            articleLink: "https://example.com/1",
            articleTitle: "Title",
            text: "Text"
        )
        let after = Date()
        
        XCTAssertGreaterThanOrEqual(note.createdDate, before)
        XCTAssertLessThanOrEqual(note.createdDate, after)
        XCTAssertGreaterThanOrEqual(note.modifiedDate, before)
        XCTAssertLessThanOrEqual(note.modifiedDate, after)
    }
    
    func testNoteCustomDates() {
        let created = Date(timeIntervalSince1970: 1000000)
        let modified = Date(timeIntervalSince1970: 2000000)
        let note = ArticleNote(
            articleLink: "https://example.com/1",
            articleTitle: "Title",
            text: "Text",
            createdDate: created,
            modifiedDate: modified
        )
        XCTAssertEqual(note.createdDate, created)
        XCTAssertEqual(note.modifiedDate, modified)
    }
    
    func testNoteSecureCoding() {
        let original = ArticleNote(
            articleLink: "https://example.com/coding-test",
            articleTitle: "Coding Article",
            text: "Important note about coding"
        )
        
        guard let data = try? NSKeyedArchiver.archivedData(
            withRootObject: original, requiringSecureCoding: true
        ) else {
            XCTFail("Failed to archive ArticleNote")
            return
        }
        
        guard let decoded = try? NSKeyedUnarchiver.unarchivedObject(
            ofClass: ArticleNote.self, from: data
        ) else {
            XCTFail("Failed to unarchive ArticleNote")
            return
        }
        
        XCTAssertEqual(decoded.articleLink, original.articleLink)
        XCTAssertEqual(decoded.articleTitle, original.articleTitle)
        XCTAssertEqual(decoded.text, original.text)
        XCTAssertEqual(decoded.createdDate.timeIntervalSince1970,
                       original.createdDate.timeIntervalSince1970, accuracy: 0.001)
        XCTAssertEqual(decoded.modifiedDate.timeIntervalSince1970,
                       original.modifiedDate.timeIntervalSince1970, accuracy: 0.001)
    }
    
    func testNoteSecureCodingSupported() {
        XCTAssertTrue(ArticleNote.supportsSecureCoding)
    }
    
    // MARK: - setNote Tests
    
    func testSetNoteCreatesNew() {
        manager.setNote(for: "https://example.com/1", title: "Article 1", text: "My note")
        XCTAssertEqual(manager.count, 1)
    }
    
    func testSetNoteReturnsNote() {
        let note = manager.setNote(for: "https://example.com/1", title: "Article 1", text: "My note")
        XCTAssertNotNil(note)
        XCTAssertEqual(note?.articleLink, "https://example.com/1")
        XCTAssertEqual(note?.articleTitle, "Article 1")
        XCTAssertEqual(note?.text, "My note")
    }
    
    func testSetNoteUpdatesExisting() {
        manager.setNote(for: "https://example.com/1", title: "Article 1", text: "Original note")
        manager.setNote(for: "https://example.com/1", title: "Article 1", text: "Updated note")
        
        XCTAssertEqual(manager.count, 1)
        XCTAssertEqual(manager.getNote(for: "https://example.com/1")?.text, "Updated note")
    }
    
    func testSetNoteUpdatesModifiedDate() {
        manager.setNote(for: "https://example.com/1", title: "Article 1", text: "Original")
        let originalModified = manager.getNote(for: "https://example.com/1")?.modifiedDate
        
        // Small delay to ensure date difference
        Thread.sleep(forTimeInterval: 0.01)
        
        manager.setNote(for: "https://example.com/1", title: "Article 1", text: "Updated")
        let updatedModified = manager.getNote(for: "https://example.com/1")?.modifiedDate
        
        XCTAssertNotNil(originalModified)
        XCTAssertNotNil(updatedModified)
        if let orig = originalModified, let updated = updatedModified {
            XCTAssertGreaterThan(updated, orig)
        }
    }
    
    func testSetNoteTrimsWhitespace() {
        let note = manager.setNote(
            for: "https://example.com/1",
            title: "Article 1",
            text: "  \n  My note  \n  "
        )
        XCTAssertEqual(note?.text, "My note")
    }
    
    func testSetNoteEmptyTextRemovesNote() {
        manager.setNote(for: "https://example.com/1", title: "Article 1", text: "Some note")
        XCTAssertEqual(manager.count, 1)
        
        let result = manager.setNote(for: "https://example.com/1", title: "Article 1", text: "")
        XCTAssertNil(result)
        XCTAssertEqual(manager.count, 0)
    }
    
    func testSetNoteWhitespaceOnlyRemovesNote() {
        manager.setNote(for: "https://example.com/1", title: "Article 1", text: "Some note")
        XCTAssertEqual(manager.count, 1)
        
        let result = manager.setNote(for: "https://example.com/1", title: "Article 1", text: "   \n\t  ")
        XCTAssertNil(result)
        XCTAssertEqual(manager.count, 0)
    }
    
    func testSetNoteClampsLength() {
        let longText = String(repeating: "a", count: ArticleNotesManager.maxNoteLength + 1000)
        let note = manager.setNote(for: "https://example.com/1", title: "Article", text: longText)
        
        XCTAssertNotNil(note)
        XCTAssertEqual(note?.text.count, ArticleNotesManager.maxNoteLength)
    }
    
    func testSetNotePrunesWhenAtCapacity() {
        // Fill to capacity
        for i in 0..<ArticleNotesManager.maxNotes {
            manager.setNote(
                for: "https://example.com/\(i)",
                title: "Article \(i)",
                text: "Note \(i)"
            )
        }
        XCTAssertEqual(manager.count, ArticleNotesManager.maxNotes)
        
        // Add one more — should prune oldest and stay at max
        manager.setNote(
            for: "https://example.com/new",
            title: "New Article",
            text: "New note"
        )
        XCTAssertEqual(manager.count, ArticleNotesManager.maxNotes)
        XCTAssertNotNil(manager.getNote(for: "https://example.com/new"))
    }
    
    // MARK: - getNote Tests
    
    func testGetNoteReturnsExisting() {
        manager.setNote(for: "https://example.com/1", title: "Article 1", text: "My note")
        let note = manager.getNote(for: "https://example.com/1")
        
        XCTAssertNotNil(note)
        XCTAssertEqual(note?.text, "My note")
    }
    
    func testGetNoteReturnsNilForMissing() {
        let note = manager.getNote(for: "https://example.com/nonexistent")
        XCTAssertNil(note)
    }
    
    // MARK: - hasNote Tests
    
    func testHasNoteReturnsTrueWhenExists() {
        manager.setNote(for: "https://example.com/1", title: "Article 1", text: "Note")
        XCTAssertTrue(manager.hasNote(for: "https://example.com/1"))
    }
    
    func testHasNoteReturnsFalseWhenMissing() {
        XCTAssertFalse(manager.hasNote(for: "https://example.com/nonexistent"))
    }
    
    // MARK: - removeNote Tests
    
    func testRemoveNoteReturnsTrueWhenExists() {
        manager.setNote(for: "https://example.com/1", title: "Article 1", text: "Note")
        let result = manager.removeNote(for: "https://example.com/1")
        XCTAssertTrue(result)
    }
    
    func testRemoveNoteReturnsFalseWhenMissing() {
        let result = manager.removeNote(for: "https://example.com/nonexistent")
        XCTAssertFalse(result)
    }
    
    func testRemoveNoteDecreasesCount() {
        manager.setNote(for: "https://example.com/1", title: "Article 1", text: "Note 1")
        manager.setNote(for: "https://example.com/2", title: "Article 2", text: "Note 2")
        XCTAssertEqual(manager.count, 2)
        
        manager.removeNote(for: "https://example.com/1")
        XCTAssertEqual(manager.count, 1)
        XCTAssertNil(manager.getNote(for: "https://example.com/1"))
        XCTAssertNotNil(manager.getNote(for: "https://example.com/2"))
    }
    
    // MARK: - getAllNotes Tests
    
    func testGetAllNotesSortedByModifiedDate() {
        // Create notes with staggered times
        let note1 = manager.setNote(for: "https://example.com/1", title: "Oldest", text: "Note 1")
        Thread.sleep(forTimeInterval: 0.01)
        let note2 = manager.setNote(for: "https://example.com/2", title: "Middle", text: "Note 2")
        Thread.sleep(forTimeInterval: 0.01)
        let note3 = manager.setNote(for: "https://example.com/3", title: "Newest", text: "Note 3")
        
        let allNotes = manager.getAllNotes()
        XCTAssertEqual(allNotes.count, 3)
        // Most recently modified first
        XCTAssertEqual(allNotes[0].articleLink, "https://example.com/3")
        XCTAssertEqual(allNotes[2].articleLink, "https://example.com/1")
    }
    
    func testGetAllNotesReturnsEmptyWhenNoNotes() {
        let allNotes = manager.getAllNotes()
        XCTAssertTrue(allNotes.isEmpty)
    }
    
    func testGetAllNotesReturnsCorrectCount() {
        manager.setNote(for: "https://example.com/1", title: "A1", text: "N1")
        manager.setNote(for: "https://example.com/2", title: "A2", text: "N2")
        manager.setNote(for: "https://example.com/3", title: "A3", text: "N3")
        
        XCTAssertEqual(manager.getAllNotes().count, 3)
    }
    
    // MARK: - count Tests
    
    func testCountInitiallyZero() {
        XCTAssertEqual(manager.count, 0)
    }
    
    func testCountIncreasesOnAdd() {
        manager.setNote(for: "https://example.com/1", title: "A1", text: "N1")
        XCTAssertEqual(manager.count, 1)
        
        manager.setNote(for: "https://example.com/2", title: "A2", text: "N2")
        XCTAssertEqual(manager.count, 2)
    }
    
    func testCountDecreasesOnRemove() {
        manager.setNote(for: "https://example.com/1", title: "A1", text: "N1")
        manager.setNote(for: "https://example.com/2", title: "A2", text: "N2")
        XCTAssertEqual(manager.count, 2)
        
        manager.removeNote(for: "https://example.com/1")
        XCTAssertEqual(manager.count, 1)
    }
    
    // MARK: - search Tests
    
    func testSearchByNoteText() {
        manager.setNote(for: "https://example.com/1", title: "Article 1", text: "Swift programming tips")
        manager.setNote(for: "https://example.com/2", title: "Article 2", text: "Python best practices")
        
        let results = manager.search(query: "Swift")
        XCTAssertEqual(results.count, 1)
        XCTAssertEqual(results[0].articleLink, "https://example.com/1")
    }
    
    func testSearchByArticleTitle() {
        manager.setNote(for: "https://example.com/1", title: "iOS Development Guide", text: "Great resource")
        manager.setNote(for: "https://example.com/2", title: "Android Tips", text: "Also useful")
        
        let results = manager.search(query: "iOS")
        XCTAssertEqual(results.count, 1)
        XCTAssertEqual(results[0].articleLink, "https://example.com/1")
    }
    
    func testSearchCaseInsensitive() {
        manager.setNote(for: "https://example.com/1", title: "Article", text: "SwiftUI is great")
        
        let results = manager.search(query: "swiftui")
        XCTAssertEqual(results.count, 1)
    }
    
    func testSearchEmptyQueryReturnsAll() {
        manager.setNote(for: "https://example.com/1", title: "A1", text: "N1")
        manager.setNote(for: "https://example.com/2", title: "A2", text: "N2")
        
        let results = manager.search(query: "")
        XCTAssertEqual(results.count, 2)
    }
    
    func testSearchNoResultsReturnsEmpty() {
        manager.setNote(for: "https://example.com/1", title: "Article", text: "Some note")
        
        let results = manager.search(query: "zzzznonexistent")
        XCTAssertTrue(results.isEmpty)
    }
    
    func testSearchWhitespaceQueryReturnsAll() {
        manager.setNote(for: "https://example.com/1", title: "A1", text: "N1")
        manager.setNote(for: "https://example.com/2", title: "A2", text: "N2")
        
        let results = manager.search(query: "   ")
        XCTAssertEqual(results.count, 2)
    }
    
    // MARK: - clearAll Tests
    
    func testClearAllReturnsCount() {
        manager.setNote(for: "https://example.com/1", title: "A1", text: "N1")
        manager.setNote(for: "https://example.com/2", title: "A2", text: "N2")
        manager.setNote(for: "https://example.com/3", title: "A3", text: "N3")
        
        let removed = manager.clearAll()
        XCTAssertEqual(removed, 3)
    }
    
    func testClearAllRemovesAllNotes() {
        manager.setNote(for: "https://example.com/1", title: "A1", text: "N1")
        manager.setNote(for: "https://example.com/2", title: "A2", text: "N2")
        
        manager.clearAll()
        
        XCTAssertEqual(manager.count, 0)
        XCTAssertNil(manager.getNote(for: "https://example.com/1"))
        XCTAssertNil(manager.getNote(for: "https://example.com/2"))
    }
    
    func testClearAllEmptyReturnsZero() {
        let removed = manager.clearAll()
        XCTAssertEqual(removed, 0)
    }
    
    // MARK: - exportAsText Tests
    
    func testExportAsTextFormatsCorrectly() {
        manager.setNote(
            for: "https://example.com/1",
            title: "My Article",
            text: "Great read!"
        )
        
        let exported = manager.exportAsText()
        XCTAssertTrue(exported.contains("## My Article"))
        XCTAssertTrue(exported.contains("https://example.com/1"))
        XCTAssertTrue(exported.contains("Great read!"))
        XCTAssertTrue(exported.contains("---"))
    }
    
    func testExportAsTextEmptyReturnsNoNotes() {
        let exported = manager.exportAsText()
        XCTAssertEqual(exported, "No notes.")
    }
    
    func testExportAsTextMultipleNotes() {
        manager.setNote(for: "https://example.com/1", title: "Article 1", text: "Note 1")
        manager.setNote(for: "https://example.com/2", title: "Article 2", text: "Note 2")
        
        let exported = manager.exportAsText()
        XCTAssertTrue(exported.contains("Article 1"))
        XCTAssertTrue(exported.contains("Article 2"))
        XCTAssertTrue(exported.contains("Note 1"))
        XCTAssertTrue(exported.contains("Note 2"))
    }
    
    // MARK: - Persistence Tests
    
    func testNotePersistedToUserDefaults() {
        manager.setNote(for: "https://example.com/persist", title: "Persist", text: "Persisted note")
        
        // Reload from defaults
        manager.reloadFromDefaults()
        
        let note = manager.getNote(for: "https://example.com/persist")
        XCTAssertNotNil(note)
        XCTAssertEqual(note?.text, "Persisted note")
    }
    
    func testNoteLoadedFromUserDefaults() {
        manager.setNote(for: "https://example.com/1", title: "A1", text: "N1")
        manager.setNote(for: "https://example.com/2", title: "A2", text: "N2")
        
        manager.reloadFromDefaults()
        
        XCTAssertEqual(manager.count, 2)
        XCTAssertNotNil(manager.getNote(for: "https://example.com/1"))
        XCTAssertNotNil(manager.getNote(for: "https://example.com/2"))
    }
    
    func testRemoveNotePersistedToUserDefaults() {
        manager.setNote(for: "https://example.com/1", title: "A1", text: "N1")
        manager.removeNote(for: "https://example.com/1")
        
        manager.reloadFromDefaults()
        
        XCTAssertEqual(manager.count, 0)
        XCTAssertNil(manager.getNote(for: "https://example.com/1"))
    }
    
    // MARK: - Notification Tests
    
    func testSetNotePostsNotification() {
        let expectation = self.expectation(forNotification: .articleNotesDidChange, object: nil)
        
        manager.setNote(for: "https://example.com/1", title: "Article", text: "Note")
        
        wait(for: [expectation], timeout: 1.0)
    }
    
    func testRemoveNotePostsNotification() {
        manager.setNote(for: "https://example.com/1", title: "Article", text: "Note")
        
        let expectation = self.expectation(forNotification: .articleNotesDidChange, object: nil)
        manager.removeNote(for: "https://example.com/1")
        
        wait(for: [expectation], timeout: 1.0)
    }
    
    func testClearAllPostsNotification() {
        manager.setNote(for: "https://example.com/1", title: "Article", text: "Note")
        
        let expectation = self.expectation(forNotification: .articleNotesDidChange, object: nil)
        manager.clearAll()
        
        wait(for: [expectation], timeout: 1.0)
    }
    
    // MARK: - Edge Cases
    
    func testSetNoteWithVeryLongText() {
        let longText = String(repeating: "Lorem ipsum dolor sit amet. ", count: 500)
        let note = manager.setNote(for: "https://example.com/1", title: "Long", text: longText)
        
        XCTAssertNotNil(note)
        XCTAssertLessThanOrEqual(note!.text.count, ArticleNotesManager.maxNoteLength)
    }
    
    func testSetNoteWithSpecialCharacters() {
        let specialText = "Note with émojis 🎉🚀 and spëcîal chars: <>&\"'\\n\\t日本語"
        let note = manager.setNote(
            for: "https://example.com/special",
            title: "Spëcîal Tïtle 🌟",
            text: specialText
        )
        
        XCTAssertNotNil(note)
        XCTAssertEqual(note?.text, specialText)
        XCTAssertEqual(note?.articleTitle, "Spëcîal Tïtle 🌟")
    }
    
    func testSetNoteWithEmptyTitle() {
        let note = manager.setNote(for: "https://example.com/1", title: "", text: "Note text")
        
        XCTAssertNotNil(note)
        XCTAssertEqual(note?.articleTitle, "")
        XCTAssertEqual(note?.text, "Note text")
    }
    
    func testMultipleNotesForDifferentArticles() {
        for i in 1...20 {
            manager.setNote(
                for: "https://example.com/\(i)",
                title: "Article \(i)",
                text: "Note for article \(i)"
            )
        }
        
        XCTAssertEqual(manager.count, 20)
        
        for i in 1...20 {
            XCTAssertTrue(manager.hasNote(for: "https://example.com/\(i)"))
            XCTAssertEqual(
                manager.getNote(for: "https://example.com/\(i)")?.text,
                "Note for article \(i)"
            )
        }
    }
    
    func testMaxNotesLimit() {
        // Add exactly maxNotes
        for i in 0..<ArticleNotesManager.maxNotes {
            manager.setNote(
                for: "https://example.com/\(i)",
                title: "Article \(i)",
                text: "Note \(i)"
            )
        }
        XCTAssertEqual(manager.count, ArticleNotesManager.maxNotes)
        
        // Adding one more should still be at maxNotes (oldest pruned)
        manager.setNote(
            for: "https://example.com/overflow",
            title: "Overflow",
            text: "Overflow note"
        )
        XCTAssertEqual(manager.count, ArticleNotesManager.maxNotes)
        XCTAssertNotNil(manager.getNote(for: "https://example.com/overflow"))
    }
    
    func testPruneRemovesOldest() {
        // Create notes with known creation order
        // First note created = oldest = should be pruned
        manager.setNote(for: "https://example.com/oldest", title: "Oldest", text: "Oldest note")
        Thread.sleep(forTimeInterval: 0.01)
        
        // Fill remaining capacity
        for i in 1..<ArticleNotesManager.maxNotes {
            manager.setNote(
                for: "https://example.com/\(i)",
                title: "Article \(i)",
                text: "Note \(i)"
            )
        }
        XCTAssertEqual(manager.count, ArticleNotesManager.maxNotes)
        XCTAssertNotNil(manager.getNote(for: "https://example.com/oldest"))
        
        // Add one more — oldest should be pruned
        manager.setNote(
            for: "https://example.com/newest",
            title: "Newest",
            text: "Newest note"
        )
        XCTAssertEqual(manager.count, ArticleNotesManager.maxNotes)
        XCTAssertNil(manager.getNote(for: "https://example.com/oldest"),
                     "Oldest note should have been pruned")
        XCTAssertNotNil(manager.getNote(for: "https://example.com/newest"))
    }
}
