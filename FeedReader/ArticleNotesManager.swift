//
//  ArticleNotesManager.swift
//  FeedReader
//
//  Manages personal notes attached to articles with persistent storage.
//  Provides CRUD, search, export, and capacity management.
//

import Foundation

/// Notification posted when the article notes list changes.
extension Notification.Name {
    static let articleNotesDidChange = Notification.Name("ArticleNotesDidChangeNotification")
}

class ArticleNotesManager {
    
    // MARK: - Singleton
    
    static let shared = ArticleNotesManager()
    
    // MARK: - Constants
    
    /// Maximum number of notes to store.
    static let maxNotes = 500
    
    /// Maximum length of a single note's text.
    static let maxNoteLength = 5000
    
    private static let userDefaultsKey = "ArticleNotesManager.notes"
    
    // MARK: - Properties
    
    /// Notes keyed by article link for O(1) lookup.
    private var notesByLink: [String: ArticleNote]
    
    // MARK: - Initialization
    
    private init() {
        notesByLink = ArticleNotesManager.loadFromDefaults()
    }
    
    // MARK: - CRUD
    
    /// Add or update a note for an article.
    /// Returns the created/updated note, or nil if text is empty after trimming.
    @discardableResult
    func setNote(for articleLink: String, title: String, text: String) -> ArticleNote? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            // Empty text = delete note
            removeNote(for: articleLink)
            return nil
        }
        
        let clampedText = String(trimmed.prefix(ArticleNotesManager.maxNoteLength))
        
        if let existing = notesByLink[articleLink] {
            existing.text = clampedText
            existing.modifiedDate = Date()
            notesByLink[articleLink] = existing
        } else {
            // Enforce max notes limit — remove oldest if at capacity
            if notesByLink.count >= ArticleNotesManager.maxNotes {
                pruneOldest()
            }
            let note = ArticleNote(articleLink: articleLink, articleTitle: title, text: clampedText)
            notesByLink[articleLink] = note
        }
        
        save()
        NotificationCenter.default.post(name: .articleNotesDidChange, object: nil)
        return notesByLink[articleLink]
    }
    
    /// Get the note for an article, if any.
    func getNote(for articleLink: String) -> ArticleNote? {
        return notesByLink[articleLink]
    }
    
    /// Check if an article has a note.
    func hasNote(for articleLink: String) -> Bool {
        return notesByLink[articleLink] != nil
    }
    
    /// Remove a note for an article. Returns true if a note was removed.
    @discardableResult
    func removeNote(for articleLink: String) -> Bool {
        guard notesByLink.removeValue(forKey: articleLink) != nil else { return false }
        save()
        NotificationCenter.default.post(name: .articleNotesDidChange, object: nil)
        return true
    }
    
    /// Get all notes, sorted by most recently modified.
    func getAllNotes() -> [ArticleNote] {
        return notesByLink.values.sorted { $0.modifiedDate > $1.modifiedDate }
    }
    
    /// Get notes count.
    var count: Int {
        return notesByLink.count
    }
    
    /// Search notes by text content (case-insensitive).
    func search(query: String) -> [ArticleNote] {
        let q = query.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return getAllNotes() }
        return getAllNotes().filter {
            $0.text.lowercased().contains(q) ||
            $0.articleTitle.lowercased().contains(q)
        }
    }
    
    /// Clear all notes. Returns count of removed notes.
    @discardableResult
    func clearAll() -> Int {
        let removedCount = notesByLink.count
        guard removedCount > 0 else { return 0 }
        notesByLink.removeAll()
        save()
        NotificationCenter.default.post(name: .articleNotesDidChange, object: nil)
        return removedCount
    }
    
    /// Export all notes as a formatted string (for sharing).
    func exportAsText() -> String {
        let notes = getAllNotes()
        guard !notes.isEmpty else { return "No notes." }
        return notes.map { note in
            "## \(note.articleTitle)\n\(note.articleLink)\n\(note.text)\n---"
        }.joined(separator: "\n\n")
    }
    
    // MARK: - Persistence
    
    private func save() {
        let data = try? NSKeyedArchiver.archivedData(
            withRootObject: Array(notesByLink.values),
            requiringSecureCoding: true
        )
        UserDefaults.standard.set(data, forKey: ArticleNotesManager.userDefaultsKey)
    }
    
    private static func loadFromDefaults() -> [String: ArticleNote] {
        guard let data = UserDefaults.standard.data(forKey: userDefaultsKey),
              let notes = try? NSKeyedUnarchiver.unarchivedArrayOfObjects(
                ofClass: ArticleNote.self, from: data
              ) else {
            return [:]
        }
        var dict: [String: ArticleNote] = [:]
        for note in notes {
            dict[note.articleLink] = note
        }
        return dict
    }
    
    private func pruneOldest() {
        if let oldest = notesByLink.values.min(by: { $0.createdDate < $1.createdDate }) {
            notesByLink.removeValue(forKey: oldest.articleLink)
        }
    }
    
    // MARK: - Testing Support
    
    /// Reset to empty state (for tests).
    func reset() {
        notesByLink.removeAll()
        UserDefaults.standard.removeObject(forKey: ArticleNotesManager.userDefaultsKey)
    }
    
    /// Load from UserDefaults (for tests verifying persistence).
    func reloadFromDefaults() {
        notesByLink = ArticleNotesManager.loadFromDefaults()
    }
}
