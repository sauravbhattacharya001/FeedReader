//
//  ReadStatusManager.swift
//  FeedReader
//
//  Tracks read/unread status for stories. Uses UserDefaults for
//  lightweight persistent storage. Stories are identified by their
//  link URL, consistent with BookmarkManager's approach.
//

import Foundation

/// Notification posted when read status changes.
extension Notification.Name {
    static let readStatusDidChange = Notification.Name("ReadStatusDidChangeNotification")
}

class ReadStatusManager {
    
    // MARK: - Singleton
    
    static let shared = ReadStatusManager()
    
    // MARK: - Properties
    
    /// Ordered list of story links that have been read (oldest first).
    /// New entries are appended; pruning removes from the front (FIFO).
    private var readLinksOrdered: [String]
    
    /// Set for O(1) lookup of read status.
    private var readLinksSet: Set<String>
    
    /// UserDefaults key for persisting read links.
    private static let userDefaultsKey = "ReadStatusManager.readLinks"
    
    /// Maximum number of read links to store (prevents unbounded growth).
    /// Old entries are pruned when this limit is exceeded.
    static let maxStoredLinks = 5000
    
    // MARK: - Initialization
    
    private init() {
        let loaded = ReadStatusManager.loadFromDefaults()
        readLinksOrdered = loaded
        readLinksSet = Set(loaded)
    }
    
    // MARK: - Public Methods
    
    /// Check if a story has been read.
    func isRead(_ story: Story) -> Bool {
        return readLinksSet.contains(story.link)
    }
    
    /// Check if a story link has been read.
    func isRead(link: String) -> Bool {
        return readLinksSet.contains(link)
    }
    
    /// Mark a story as read. Returns true if newly marked (was unread before).
    @discardableResult
    func markAsRead(_ story: Story) -> Bool {
        return markAsRead(link: story.link)
    }
    
    /// Mark a story link as read. Returns true if newly marked.
    @discardableResult
    func markAsRead(link: String) -> Bool {
        guard !readLinksSet.contains(link) else { return false }
        readLinksSet.insert(link)
        readLinksOrdered.append(link)
        pruneIfNeeded()
        save()
        NotificationCenter.default.post(name: .readStatusDidChange, object: nil)
        return true
    }
    
    /// Mark a story as unread. Returns true if was previously read.
    @discardableResult
    func markAsUnread(_ story: Story) -> Bool {
        return markAsUnread(link: story.link)
    }
    
    /// Mark a story link as unread. Returns true if was previously read.
    @discardableResult
    func markAsUnread(link: String) -> Bool {
        guard readLinksSet.remove(link) != nil else { return false }
        if let idx = readLinksOrdered.firstIndex(of: link) {
            readLinksOrdered.remove(at: idx)
        }
        save()
        NotificationCenter.default.post(name: .readStatusDidChange, object: nil)
        return true
    }
    
    /// Toggle read/unread status. Returns true if now read.
    @discardableResult
    func toggleReadStatus(_ story: Story) -> Bool {
        if isRead(story) {
            markAsUnread(story)
            return false
        } else {
            markAsRead(story)
            return true
        }
    }
    
    /// Mark all stories in the array as read.
    func markAllAsRead(_ stories: [Story]) {
        var changed = false
        for story in stories {
            if !readLinksSet.contains(story.link) {
                readLinksSet.insert(story.link)
                readLinksOrdered.append(story.link)
                changed = true
            }
        }
        if changed {
            pruneIfNeeded()
            save()
            NotificationCenter.default.post(name: .readStatusDidChange, object: nil)
        }
    }
    
    /// Count unread stories from the given array.
    func unreadCount(in stories: [Story]) -> Int {
        return stories.reduce(0) { acc, story in
            readLinksSet.contains(story.link) ? acc : acc + 1
        }
    }
    
    /// Filter stories by read status.
    func filterStories(_ stories: [Story], readStatus: ReadFilter) -> [Story] {
        switch readStatus {
        case .all:
            return stories
        case .unread:
            return stories.filter { !readLinksSet.contains($0.link) }
        case .read:
            return stories.filter { readLinksSet.contains($0.link) }
        }
    }
    
    /// Total number of tracked read links.
    var readCount: Int {
        return readLinksSet.count
    }
    
    /// Clear all read status data.
    func clearAll() {
        readLinksOrdered.removeAll()
        readLinksSet.removeAll()
        save()
        NotificationCenter.default.post(name: .readStatusDidChange, object: nil)
    }
    
    // MARK: - Filter Enum
    
    /// Filter options for story read status.
    enum ReadFilter: Int, CaseIterable {
        case all = 0
        case unread = 1
        case read = 2
        
        var title: String {
            switch self {
            case .all: return "All"
            case .unread: return "Unread"
            case .read: return "Read"
            }
        }
    }
    
    // MARK: - Persistence
    
    private func save() {
        // Save as ordered array — preserves insertion order for FIFO pruning
        UserDefaults.standard.set(readLinksOrdered, forKey: ReadStatusManager.userDefaultsKey)
    }
    
    private static func loadFromDefaults() -> [String] {
        guard let array = UserDefaults.standard.stringArray(forKey: userDefaultsKey) else {
            return []
        }
        return array
    }
    
    /// Prune oldest entries (FIFO) if we exceed the max stored links.
    /// Removes from the front of the ordered array, which contains the
    /// earliest-added entries.
    private func pruneIfNeeded() {
        if readLinksOrdered.count > ReadStatusManager.maxStoredLinks {
            let excess = readLinksOrdered.count - ReadStatusManager.maxStoredLinks
            let pruned = Array(readLinksOrdered.prefix(excess))
            readLinksOrdered.removeFirst(excess)
            for link in pruned {
                readLinksSet.remove(link)
            }
        }
    }
    
    /// Force a reload from UserDefaults (useful for testing).
    func reload() {
        let loaded = ReadStatusManager.loadFromDefaults()
        readLinksOrdered = loaded
        readLinksSet = Set(loaded)
    }
}
