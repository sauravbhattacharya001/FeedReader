//
//  BookmarkManager.swift
//  FeedReader
//
//  Manages bookmarked stories with persistent storage.
//  Provides add/remove/toggle/check operations with NSCoding-based persistence.
//

import UIKit

/// Notification posted when the bookmarks list changes.
extension Notification.Name {
    static let bookmarksDidChange = Notification.Name("BookmarksDidChangeNotification")
}

class BookmarkManager {
    
    // MARK: - Singleton
    
    static let shared = BookmarkManager()
    
    // MARK: - Properties
    
    private(set) var bookmarks: [Story] = []
    
    /// O(1) lookup index for bookmark checks. Stores the link strings
    /// of all bookmarked stories, eliminating the previous O(n) scan
    /// in isBookmarked() which was called per-cell during table rendering.
    private var bookmarkIndex = Set<String>()
    
    private static let archiveURL: URL = {
        let documentsDirectory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        return documentsDirectory.appendingPathComponent("bookmarks")
    }()
    
    // MARK: - Initialization
    
    private init() {
        loadBookmarks()
    }
    
    // MARK: - Public Methods
    
    /// Check if a story is bookmarked (O(1) lookup via index set).
    func isBookmarked(_ story: Story) -> Bool {
        return bookmarkIndex.contains(story.link)
    }
    
    /// Add a story to bookmarks. No-op if already bookmarked.
    func addBookmark(_ story: Story) {
        guard !isBookmarked(story) else { return }
        bookmarks.insert(story, at: 0) // newest first
        bookmarkIndex.insert(story.link)
        saveBookmarks()
        NotificationCenter.default.post(name: .bookmarksDidChange, object: nil)
    }
    
    /// Remove a story from bookmarks (matched by link URL).
    func removeBookmark(_ story: Story) {
        bookmarks.removeAll { $0.link == story.link }
        bookmarkIndex.remove(story.link)
        saveBookmarks()
        NotificationCenter.default.post(name: .bookmarksDidChange, object: nil)
    }
    
    /// Toggle bookmark state for a story. Returns true if now bookmarked.
    @discardableResult
    func toggleBookmark(_ story: Story) -> Bool {
        if isBookmarked(story) {
            removeBookmark(story)
            return false
        } else {
            addBookmark(story)
            return true
        }
    }
    
    /// Remove a bookmark at a specific index.
    func removeBookmark(at index: Int) {
        guard index >= 0 && index < bookmarks.count else { return }
        let removed = bookmarks.remove(at: index)
        bookmarkIndex.remove(removed.link)
        saveBookmarks()
        NotificationCenter.default.post(name: .bookmarksDidChange, object: nil)
    }
    
    /// Number of bookmarked stories.
    var count: Int {
        return bookmarks.count
    }
    
    /// Remove all bookmarks.
    func clearAll() {
        bookmarks.removeAll()
        bookmarkIndex.removeAll()
        saveBookmarks()
        NotificationCenter.default.post(name: .bookmarksDidChange, object: nil)
    }
    
    // MARK: - Persistence
    
    private func saveBookmarks() {
        do {
            let data = try NSKeyedArchiver.archivedData(withRootObject: bookmarks, requiringSecureCoding: true)
            try data.write(to: BookmarkManager.archiveURL)
        } catch {
            print("Failed to save bookmarks: \(error)")
        }
    }
    
    private func loadBookmarks() {
        guard let data = try? Data(contentsOf: BookmarkManager.archiveURL) else {
            bookmarks = []
            bookmarkIndex = Set<String>()
            return
        }
        if let loaded = (try? NSKeyedUnarchiver.unarchivedObject(ofClasses: [NSArray.self, Story.self], from: data)) as? [Story] {
            bookmarks = loaded
            bookmarkIndex = Set(loaded.map { $0.link })
        } else {
            bookmarks = []
            bookmarkIndex = Set<String>()
        }
    }
    
    /// Force a reload from disk (useful for testing).
    func reload() {
        loadBookmarks()
    }
}
