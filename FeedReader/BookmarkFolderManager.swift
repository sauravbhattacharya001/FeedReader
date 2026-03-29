//
//  BookmarkFolderManager.swift
//  FeedReader
//
//  Organizes bookmarks into named folders for better categorization.
//  Users can create folders (e.g., "Tech", "Science", "Read Later"),
//  move bookmarks between folders, and browse bookmarks by folder.
//
//  Usage:
//      BookmarkFolderManager.shared.createFolder("Tech")
//      BookmarkFolderManager.shared.addBookmark(story, toFolder: "Tech")
//      let techArticles = BookmarkFolderManager.shared.bookmarks(inFolder: "Tech")
//

import Foundation

/// Notification posted when bookmark folders change (create/delete/rename/move).
extension Notification.Name {
    static let bookmarkFoldersDidChange = Notification.Name("BookmarkFoldersDidChangeNotification")
}

/// Represents a named bookmark folder with an ordered list of story links.
class BookmarkFolder: NSObject, NSSecureCoding {

    static var supportsSecureCoding: Bool { return true }

    /// Display name of the folder.
    var name: String

    /// Ordered list of story links belonging to this folder.
    var storyLinks: [String]

    /// Emoji icon for the folder (optional, defaults to 📁).
    var icon: String

    /// Creation date.
    let createdAt: Date

    init(name: String, icon: String = "📁", storyLinks: [String] = []) {
        self.name = name
        self.icon = icon
        self.storyLinks = storyLinks
        self.createdAt = Date()
        super.init()
    }

    // MARK: - NSSecureCoding

    func encode(with coder: NSCoder) {
        coder.encode(name as NSString, forKey: "name")
        coder.encode(storyLinks as NSArray, forKey: "storyLinks")
        coder.encode(icon as NSString, forKey: "icon")
        coder.encode(createdAt as NSDate, forKey: "createdAt")
    }

    required init?(coder: NSCoder) {
        guard let name = coder.decodeObject(of: NSString.self, forKey: "name") as String?,
              let links = coder.decodeObject(of: [NSArray.self, NSString.self], forKey: "storyLinks") as? [String],
              let icon = coder.decodeObject(of: NSString.self, forKey: "icon") as String?,
              let date = coder.decodeObject(of: NSDate.self, forKey: "createdAt") as Date? else {
            return nil
        }
        self.name = name
        self.storyLinks = links
        self.icon = icon
        self.createdAt = date
        super.init()
    }
}

/// Manages bookmark folders with persistent storage.
/// Works alongside BookmarkManager — folders reference stories by link URL.
class BookmarkFolderManager {

    // MARK: - Singleton

    static let shared = BookmarkFolderManager()

    // MARK: - Properties

    private(set) var folders: [BookmarkFolder] = []

    /// Quick lookup: story link → set of folder names it belongs to.
    private var linkToFolders: [String: Set<String>] = [:]

    private let store = SecureCodingStore<BookmarkFolder>(
        filename: "bookmarkFolders",
        additionalClasses: [NSString.self, NSDate.self]
    )

    /// Maximum number of folders a user can create.
    static let maxFolders = 50

    // MARK: - Initialization

    private init() {
        loadFolders()
    }

    // MARK: - Folder CRUD

    /// Create a new folder. Returns false if name is empty, duplicate, or limit reached.
    @discardableResult
    func createFolder(_ name: String, icon: String = "📁") -> Bool {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        guard folders.count < BookmarkFolderManager.maxFolders else { return false }
        guard !folders.contains(where: { $0.name.lowercased() == trimmed.lowercased() }) else {
            return false
        }

        let folder = BookmarkFolder(name: trimmed, icon: icon)
        folders.append(folder)
        saveFolders()
        notifyChange()
        return true
    }

    /// Delete a folder by name. Bookmarks in the folder are NOT deleted from
    /// BookmarkManager — they just lose their folder association.
    @discardableResult
    func deleteFolder(_ name: String) -> Bool {
        guard let index = folders.firstIndex(where: { $0.name == name }) else {
            return false
        }
        let folder = folders.remove(at: index)
        // Clean up reverse index
        for link in folder.storyLinks {
            linkToFolders[link]?.remove(name)
            if linkToFolders[link]?.isEmpty == true {
                linkToFolders.removeValue(forKey: link)
            }
        }
        saveFolders()
        notifyChange()
        return true
    }

    /// Rename a folder. Returns false if new name is taken or empty.
    @discardableResult
    func renameFolder(_ oldName: String, to newName: String) -> Bool {
        let trimmed = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        guard !folders.contains(where: { $0.name.lowercased() == trimmed.lowercased() && $0.name != oldName }) else {
            return false
        }
        guard let folder = folders.first(where: { $0.name == oldName }) else {
            return false
        }

        // Update reverse index
        for link in folder.storyLinks {
            linkToFolders[link]?.remove(oldName)
            linkToFolders[link]?.insert(trimmed)
        }

        folder.name = trimmed
        saveFolders()
        notifyChange()
        return true
    }

    /// Change a folder's icon emoji.
    func setFolderIcon(_ name: String, icon: String) {
        guard let folder = folders.first(where: { $0.name == name }) else { return }
        folder.icon = icon
        saveFolders()
        notifyChange()
    }

    // MARK: - Bookmark ↔ Folder Operations

    /// Add a bookmark to a folder (by story link). No-op if already in folder.
    @discardableResult
    func addBookmark(_ story: Story, toFolder folderName: String) -> Bool {
        guard let folder = folders.first(where: { $0.name == folderName }) else {
            return false
        }
        guard !folder.storyLinks.contains(story.link) else { return false }

        folder.storyLinks.insert(story.link, at: 0) // newest first
        linkToFolders[story.link, default: []].insert(folderName)
        saveFolders()
        notifyChange()
        return true
    }

    /// Remove a bookmark from a folder.
    @discardableResult
    func removeBookmark(_ story: Story, fromFolder folderName: String) -> Bool {
        guard let folder = folders.first(where: { $0.name == folderName }) else {
            return false
        }
        guard folder.storyLinks.contains(story.link) else { return false }

        folder.storyLinks.removeAll { $0 == story.link }
        linkToFolders[story.link]?.remove(folderName)
        if linkToFolders[story.link]?.isEmpty == true {
            linkToFolders.removeValue(forKey: story.link)
        }
        saveFolders()
        notifyChange()
        return true
    }

    /// Move a bookmark from one folder to another.
    @discardableResult
    func moveBookmark(_ story: Story, from source: String, to destination: String) -> Bool {
        guard removeBookmark(story, fromFolder: source) else { return false }
        return addBookmark(story, toFolder: destination)
    }

    // MARK: - Queries

    /// Get all story links in a folder, in order.
    func storyLinks(inFolder name: String) -> [String] {
        return folders.first(where: { $0.name == name })?.storyLinks ?? []
    }

    /// Get resolved Story objects for a folder by cross-referencing BookmarkManager.
    func bookmarks(inFolder name: String) -> [Story] {
        let links = storyLinks(inFolder: name)
        let allBookmarks = BookmarkManager.shared.bookmarks
        let linkSet = Set(links)
        // Preserve folder ordering
        let bookmarkMap = Dictionary(uniqueKeysWithValues: allBookmarks.map { ($0.link, $0) })
        return links.compactMap { bookmarkMap[$0] }
    }

    /// Get all folder names a story belongs to.
    func foldersContaining(_ story: Story) -> [String] {
        return Array(linkToFolders[story.link] ?? []).sorted()
    }

    /// Check if a story is in a specific folder.
    func isBookmark(_ story: Story, inFolder name: String) -> Bool {
        return linkToFolders[story.link]?.contains(name) == true
    }

    /// Get stories that aren't in any folder (uncategorized bookmarks).
    func uncategorizedBookmarks() -> [Story] {
        let allBookmarks = BookmarkManager.shared.bookmarks
        return allBookmarks.filter { linkToFolders[$0.link]?.isEmpty != false }
    }

    /// Total number of folders.
    var folderCount: Int {
        return folders.count
    }

    /// Summary stats: folder name → bookmark count.
    func folderStats() -> [(name: String, icon: String, count: Int)] {
        return folders.map { ($0.name, $0.icon, $0.storyLinks.count) }
    }

    // MARK: - Reorder

    /// Move a folder from one position to another (for drag-to-reorder).
    func moveFolder(from sourceIndex: Int, to destinationIndex: Int) {
        guard sourceIndex != destinationIndex,
              sourceIndex >= 0, sourceIndex < folders.count,
              destinationIndex >= 0, destinationIndex < folders.count else { return }
        let folder = folders.remove(at: sourceIndex)
        folders.insert(folder, at: destinationIndex)
        saveFolders()
        notifyChange()
    }

    // MARK: - Persistence

    private func saveFolders() {
        store.save(folders)
    }

    private func loadFolders() {
        folders = store.load()
        rebuildIndex()
    }

    private func rebuildIndex() {
        linkToFolders.removeAll()
        for folder in folders {
            for link in folder.storyLinks {
                linkToFolders[link, default: []].insert(folder.name)
            }
        }
    }

    /// Force reload from disk (useful for testing).
    func reload() {
        loadFolders()
    }

    /// Remove all folders.
    func clearAll() {
        folders.removeAll()
        linkToFolders.removeAll()
        saveFolders()
        notifyChange()
    }

    // MARK: - Notifications

    private func notifyChange() {
        NotificationCenter.default.post(name: .bookmarkFoldersDidChange, object: nil)
    }
}
